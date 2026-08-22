-- Ficha de los 14 productos hermanos del pedalier, desde lo que declara el
-- nombre: 8 cubetas, 3 ejes sueltos y 3 rodamientos.
--
-- Antes, una correccion de dominio que salio de correr la clasificacion en
-- seco contra el catalogo: `Cubetas Motor Bmx Americana Sellada Eje 19mm` es
-- una caja americana con rodamientos prensados, y la regla de cubetas solo
-- admitia copa y cono para esa caja. El americano de BMX acepta las dos: el
-- juego de bolas sueltas de toda la vida y el de dos rodamientos sellados a
-- presion.
--
-- Lo que NO se llena, por no estar declarado:
--   * la interfaz del eje de los tres ejes sueltos. `Pta Cuadrada` prueba que
--     el cono es cuadrado, no si es JIS o ISO.
--   * el largo de esos mismos ejes: los codigos `3-p`, `3-r` y `5-u` son
--     nomenclatura de proveedor y no se pueden traducir a milimetros sin la
--     pieza en la mano.
--   * el tamano y la cantidad de bolita de `Canastillo Rodamiento Para Motor
--     20unid`: `20unid` es cuantos vienen en la bolsa, no cuantas bolitas
--     lleva el canastillo.

begin;

update public.spec_template_fields tf set
  option_rules =
    '[{"field":"bb_shell_standard","operator":"in",'
    '"value":["BSA 1.37x24","Italiano 36x24","T47","Francés 35x1","Suizo 35x1",'
    '"Euro BMX roscado 68"],"allow":["Copa y cono","Copas externas"]},'
    '{"field":"bb_shell_standard","operator":"in",'
    '"value":["BB86 / BB92 41mm","PF30 46mm","BB30 42mm","BB386EVO 46mm",'
    '"BB90 / BB95","BBRight / OSBB","Mid BMX 41.2mm","Spanish BMX 37mm"],'
    '"allow":["Rodamientos prensados","Thread-together"]},'
    '{"field":"bb_shell_standard","operator":"eq","value":"Americano 51.5mm",'
    '"allow":["Copa y cono","Rodamientos prensados"]}]'::jsonb,
  updated_at = now()
from public.spec_templates t, public.spec_definitions d
where tf.template_id = t.id and tf.spec_definition_id = d.id
  and t.key = 'bottom_bracket_cup' and d.key = 'bb_construction';

create temporary table hermanos_backfill on commit drop as
with target as (
  select p.id, p.tenant_id, c.name as categoria, upper(unaccent(p.name)) as n
  from public.products p
  join public.product_categories c on c.id = p.category_id
  where c.name in ('Cubetas', 'Ejes de motor', 'Rodamientos Motor')
    and p.is_active is true
)
select
  t.id as product_id, t.tenant_id,
  case
    when t.categoria <> 'Cubetas' then null
    when t.n like '%AMERICAN%' or t.n like '%BMX%' then 'Americano 51.5mm'
    else 'BSA 1.37x24'
  end as shell_standard,
  case
    when t.categoria = 'Rodamientos Motor' and t.n like '%CANASTILLO%'
      then 'Copa y cono'
    when t.categoria = 'Rodamientos Motor' then 'Cartucho sellado'
    -- Una cubeta sellada de americano son rodamientos prensados, no cartucho.
    when t.categoria = 'Cubetas' and t.n like '%SELLAD%'
      then 'Rodamientos prensados'
    else 'Copa y cono'
  end as construction,
  case
    when t.categoria <> 'Cubetas' then null
    when t.n ~ 'DER/ ?IZQ' then 'Derecha / Izquierda (BSA inglés)'
    when t.n ~ 'DER/ ?DER' or t.n like '%R/R%'
      then 'Derecha / Derecha (italiano o genérico)'
    else null
  end as thread_pair,
  case when t.categoria = 'Cubetas' then (
    select min(replace(k[1], ',', '.')::numeric)
    from regexp_matches(t.n, '([0-9]+(?:[.,][0-9]+)?) ?MM', 'g') k
    where replace(k[1], ',', '.')::numeric between 30 and 60
  ) end as cup_diameter,
  case when t.n ~ '1/4' then '1/4' end as ball_size,
  case when t.n ~ '1/4 ?X ?9' then 9 end as ball_count,
  substring(t.n from '([0-9]{6})') as bearing_code,
  case when t.n ~ 'EJE ([0-9]+) ?MM'
       then (regexp_match(t.n, 'EJE ([0-9]+) ?MM'))[1]::numeric end as spindle_diameter
from target t;

insert into public.product_spec_values (
  tenant_id, product_id, spec_definition_id,
  value_text, value_number, value_option
)
select b.tenant_id, b.product_id, d.id,
       f.text_value, f.number_value, f.option_value
from hermanos_backfill b
cross join lateral (values
  ('bb_shell_standard', null::text, null::numeric, b.shell_standard),
  ('bb_construction', null, null, b.construction),
  ('bb_cup_thread_pair', null, null, b.thread_pair),
  ('bb_cup_outer_diameter_mm', null, b.cup_diameter, null),
  ('bb_ball_size_in', null, null, b.ball_size),
  ('bb_ball_count_per_side', null, b.ball_count::numeric, null),
  ('bearing_size_code', b.bearing_code, null, null),
  ('spindle_diameter_mm', null, b.spindle_diameter, null)
) as f(def_key, text_value, number_value, option_value)
join public.spec_definitions d
  on d.key = f.def_key and d.tenant_id is null
where coalesce(f.text_value, f.number_value::text, f.option_value) is not null
on conflict (tenant_id, product_id, spec_definition_id) do update set
  value_text = excluded.value_text,
  value_number = excluded.value_number,
  value_option = excluded.value_option,
  updated_at = now();

commit;
