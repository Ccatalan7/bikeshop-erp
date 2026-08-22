-- Fase 4: los hechos que ya existen entran a la tabla única.
--
-- Tres orígenes, tres formas distintas, un solo destino:
--
--   * `product_spec_values` — 282 valores. Las listas guardan la ETIQUETA en
--     `value_option`, así que se resuelven contra el vocabulario por etiqueta
--     para encontrar su código. Es la última vez que hay que hacer eso.
--   * `bike_profiles.technical_profile` — 619 hechos en tres mapas paralelos
--     (`values`, `sources`, `confirmed`), con claves camelCase y valores en
--     código. El código ya calza; la clave hay que traducirla al `key` de
--     `spec_definitions`, que es snake_case.
--   * `diagnosis_sheet_data` va en su propia migración: sus claves están
--     anidadas por sistema y no calzan una a una con `spec_definitions`.
--
-- Nada se borra. Los blobs y `product_spec_values` siguen siendo la fuente que
-- la app lee hasta que se muevan los lectores; esta migración sólo escribe el
-- espejo. Si algo sale mal, se borra `spec_facts` y no se perdió nada.

begin;

-- ── Productos ──────────────────────────────────────────────────────────────
insert into public.spec_facts (
  tenant_id, subject_type, subject_id, spec_definition_id,
  value_number, value_boolean, value_text, source, confirmed
)
select v.tenant_id, 'product', v.product_id, v.spec_definition_id,
  v.value_number, v.value_boolean,
  case when d.data_type = 'text' then v.value_text end,
  -- El backfill del pedalier de hoy salió del nombre del producto, revisado.
  -- No hay forma de distinguirlo aquí producto por producto, así que entra
  -- como importación: es cierto para todos y no le pone una confirmación que
  -- nadie dio.
  'import', false
from public.product_spec_values v
join public.spec_definitions d on d.id = v.spec_definition_id
on conflict (tenant_id, subject_type, subject_id, spec_definition_id)
do update set
  value_number = excluded.value_number,
  value_boolean = excluded.value_boolean,
  value_text = excluded.value_text,
  updated_at = now();

-- Los valores de lista de esos productos, resueltos por etiqueta.
insert into public.spec_fact_values (fact_id, value_id, position)
select f.id, sv.id, 0
from public.product_spec_values v
join public.spec_definitions d on d.id = v.spec_definition_id
join public.spec_facts f
  on f.tenant_id = v.tenant_id and f.subject_type = 'product'
 and f.subject_id = v.product_id and f.spec_definition_id = v.spec_definition_id
join public.spec_definition_values sv
  on sv.spec_definition_id = d.id and sv.label = v.value_option
where d.data_type = 'single_select' and v.value_option is not null
on conflict do nothing;

-- Multi-valor: cada elemento del array es su propia fila.
insert into public.spec_fact_values (fact_id, value_id, position)
select f.id, sv.id, (elem.ordinality - 1)::integer
from public.product_spec_values v
join public.spec_definitions d on d.id = v.spec_definition_id
join public.spec_facts f
  on f.tenant_id = v.tenant_id and f.subject_type = 'product'
 and f.subject_id = v.product_id and f.spec_definition_id = v.spec_definition_id
cross join lateral jsonb_array_elements_text(v.value_json) with ordinality as elem(texto, ordinality)
join public.spec_definition_values sv
  on sv.spec_definition_id = d.id and sv.label = elem.texto
where d.data_type = 'multi_select' and jsonb_typeof(v.value_json) = 'array'
on conflict do nothing;

-- ── Bicis ──────────────────────────────────────────────────────────────────
-- `bottomBracketFamily` en el perfil ↔ `bottom_bracket_family` en las
-- definiciones. La traducción es mecánica salvo donde el nombre difiere de
-- verdad, y esos van a mano.
create temporary table puente_bici (clave_perfil text, clave_definicion text)
on commit drop;

insert into puente_bici values
  ('brakeType', 'brake_type'),
  ('valveType', 'valve_type'),
  ('freehubType', 'freehub_type'),
  ('bottomBracketFamily', 'bottom_bracket_family'),
  ('spindleInterface', 'spindle_interface'),
  ('bbShellWidthMm', 'bb_shell_width_mm'),
  ('bbShellDiameterMm', 'bb_shell_diameter_mm'),
  ('frontSpokeHoles', 'spoke_holes'),
  ('drivetrainSpeeds', 'drivetrain_speeds'),
  ('frontRotorSizeMm', 'rotor_diameter_mm');

insert into public.spec_facts (
  tenant_id, subject_type, subject_id, spec_definition_id,
  value_number, value_text, source, confirmed
)
select bp.tenant_id, 'bike', bp.bike_id, d.id,
  case when d.data_type = 'number'
       then nullif(bp.technical_profile -> 'values' ->> p.clave_perfil, '')::numeric end,
  case when d.data_type = 'text'
       then bp.technical_profile -> 'values' ->> p.clave_perfil end,
  coalesce(nullif(bp.technical_profile -> 'sources' ->> p.clave_perfil, ''), 'mechanic'),
  coalesce((bp.technical_profile -> 'confirmed' ->> p.clave_perfil)::boolean, false)
from public.bike_profiles bp
join puente_bici p on bp.technical_profile -> 'values' ? p.clave_perfil
join public.spec_definitions d
  on d.key = p.clave_definicion and d.tenant_id is null
where bp.bike_id is not null
  and nullif(bp.technical_profile -> 'values' ->> p.clave_perfil, '') is not null
  -- Un «no sé» disfrazado de valor no entra: en la tabla nueva la ausencia es
  -- la forma de decirlo, y `confirmed` recupera su significado.
  and lower(bp.technical_profile -> 'values' ->> p.clave_perfil)
      not in ('other', 'otro', 'unknown', 'desconocido')
on conflict (tenant_id, subject_type, subject_id, spec_definition_id)
do update set
  value_number = excluded.value_number,
  value_text = excluded.value_text,
  source = excluded.source,
  confirmed = excluded.confirmed,
  updated_at = now();

-- Los valores de lista de las bicis ya vienen en código: calzan directo.
insert into public.spec_fact_values (fact_id, value_id, position)
select f.id, sv.id, 0
from public.bike_profiles bp
join puente_bici p on bp.technical_profile -> 'values' ? p.clave_perfil
join public.spec_definitions d
  on d.key = p.clave_definicion and d.tenant_id is null
 and d.data_type in ('single_select', 'multi_select')
join public.spec_facts f
  on f.tenant_id = bp.tenant_id and f.subject_type = 'bike'
 and f.subject_id = bp.bike_id and f.spec_definition_id = d.id
join public.spec_definition_values sv
  on sv.spec_definition_id = d.id
 and sv.code = bp.technical_profile -> 'values' ->> p.clave_perfil
on conflict do nothing;

commit;
