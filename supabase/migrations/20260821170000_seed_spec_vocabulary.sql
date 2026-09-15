-- Fase 2: llenar el vocabulario, sin inventar códigos que ya existen.
--
-- Orden de precedencia para el código de cada valor:
--   1. el que ya usa el wizard de servicios en `options_json` — 192 de 505
--      etiquetas lo tienen, y son los códigos que el sistema lleva años
--      guardando en `bike_profiles` y en las respuestas de los mecánicos;
--   2. el curado del pedalier, que nació hoy y no tiene historia que respetar;
--   3. el generado desde la etiqueta, para el resto.
--
-- El punto 1 es lo que hace que esto una en vez de agregar una quinta forma.

begin;

create temporary table vocabulario_curado (campo text, etiqueta text, codigo text)
on commit drop;

insert into vocabulario_curado (campo, etiqueta, codigo) values
  ('bb_shell_standard', 'BSA / Caja inglesa 34,8 mm (1.37") x 24', 'bsa_threaded'),
  ('bb_shell_standard', 'Italiano 36 mm x 24',        'italian_threaded'),
  ('bb_shell_standard', 'T47 47 mm',                  't47_threaded'),
  ('bb_shell_standard', 'Francés 35 mm x 1',          'french_threaded'),
  ('bb_shell_standard', 'Suizo 35 mm x 1',            'swiss_threaded'),
  ('bb_shell_standard', 'Euro BMX roscado 68 mm',     'euro_bmx_threaded'),
  ('bb_shell_standard', 'BB86 / BB92 41 mm',          'bb86_bb92'),
  ('bb_shell_standard', 'PF30 46 mm',                 'pf30'),
  ('bb_shell_standard', 'BB30 42 mm',                 'bb30'),
  ('bb_shell_standard', 'BB386EVO 46 mm',             'bb386evo'),
  ('bb_shell_standard', 'BB90 / BB95',                'bb90_bb95'),
  ('bb_shell_standard', 'BBRight / OSBB',             'bbright_osbb'),
  ('bb_shell_standard', 'Mid BMX 41,2 mm',            'mid_bmx'),
  ('bb_shell_standard', 'Spanish BMX 37 mm',          'spanish_bmx'),
  ('bb_shell_standard', 'Americano 51,5 mm',          'american_one_piece'),

  ('bb_construction', 'Rodamiento sellado',   'sealed_cartridge'),
  ('bb_construction', 'Integrado',            'external_cups'),
  ('bb_construction', 'Cubetas y canastillo', 'cup_and_cone'),
  ('bb_construction', 'A presión',            'press_fit'),
  ('bb_construction', 'Roscado entre sí',     'thread_together'),

  ('bb_cup_thread_pair', 'Derecha / Izquierda (BSA inglés)',       'right_left'),
  ('bb_cup_thread_pair', 'Derecha / Derecha (italiano o genérico)', 'right_right'),
  ('bb_cup_thread_pair', 'Sin rosca (a presión)',                   'pressed'),

  ('bb_ball_size_in', '1/8',  'ball_1_8'),
  ('bb_ball_size_in', '5/32', 'ball_5_32'),
  ('bb_ball_size_in', '3/16', 'ball_3_16'),
  ('bb_ball_size_in', '1/4',  'ball_1_4');

-- Las puntas de eje van en los dos campos que comparten vocabulario.
insert into vocabulario_curado (campo, etiqueta, codigo)
select campo, etiqueta, codigo
from (values
  ('Cuadrado JIS', 'square_jis'), ('Cuadrado ISO', 'square_iso'),
  ('Hollowtech / 24mm', 'hollowtech_24'), ('SRAM GXP 24/22', 'sram_gxp'),
  ('SRAM DUB 28.99mm', 'sram_dub'), ('BB30 30mm', 'bb30_30'),
  ('ISIS', 'isis'), ('Octalink', 'octalink'), ('Con chaveta', 'cottered'),
  ('BMX 19mm', 'bmx_19'), ('BMX 22mm', 'bmx_22'), ('BMX 24mm', 'bmx_24'),
  ('One-piece / americano', 'one_piece'), ('Powerspline', 'powerspline')
) as puntas(etiqueta, codigo)
cross join (values ('spindle_interface'), ('spindle_interface_accepted')) as campos(campo);

insert into public.spec_definition_values (
  tenant_id, spec_definition_id, code, label, sort_order
)
select d.tenant_id, d.id,
  coalesce(
    curado.codigo,
    wizard.codigo,
    public.spec_value_code_from_label_internal_v1(valor.etiqueta),
    'valor_' || valor.orden
  ) as code,
  valor.etiqueta,
  valor.orden::integer
from public.spec_definitions d
cross join lateral (
  select v #>> '{}' as etiqueta, ordinality as orden
  from jsonb_array_elements(d.allowed_values) with ordinality as v(v, ordinality)
) valor
left join vocabulario_curado curado
  on curado.campo = d.key and curado.etiqueta = valor.etiqueta
left join lateral (
  -- El código que el wizard ya usa para esa misma etiqueta en ese mismo campo.
  select o ->> 'value' as codigo
  from public.service_profile_questions q,
       lateral jsonb_array_elements(q.options_json) o
  where q.key = d.key
    and lower(public.unaccent(o ->> 'label')) = lower(public.unaccent(valor.etiqueta))
    and o ->> 'value' ~ '^[a-z][a-z0-9_]{0,63}$'
  limit 1
) wizard on true
where jsonb_array_length(d.allowed_values) > 0
on conflict (spec_definition_id, code) do update set
  label = excluded.label,
  sort_order = excluded.sort_order,
  updated_at = now();

commit;
