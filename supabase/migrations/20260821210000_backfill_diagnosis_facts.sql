-- Fase 6: los hallazgos de diagnóstico entran a la tabla única.
--
-- El blob anida por sistema y nombra cada campo por su pieza —
-- `hub_bearing_condition`, `pad_contamination_status`, `rotor_trueness_status`.
-- En el registro compartido eso son tres campos genéricos —condición,
-- contaminación, trueness— sobre distintos sistemas, y el sistema viaja en
-- `subject_scope`. Doce nombres de campo colapsan en cuatro.
--
-- El blob NO se borra: sigue siendo lo que la app lee. Esto escribe el espejo.

begin;

-- Dos estados que sólo le pasan a un cable y que la condición compartida no
-- tenía: `high_friction` (roza y cuesta mover) y `housing_damaged` (la funda
-- está dañada). Salieron de los datos, no de la imaginación: son 4 hallazgos
-- reales que se habrían perdido al migrar.
update public.spec_definitions set
  allowed_values = allowed_values
    || '["high_friction","housing_damaged"]'::jsonb,
  updated_at = now()
where key = 'component_condition' and tenant_id is null
  and not allowed_values @> '["high_friction"]'::jsonb;

insert into public.spec_definition_values (
  tenant_id, spec_definition_id, code, label, sort_order
)
select null, d.id, nuevo.codigo, nuevo.etiqueta, nuevo.orden
from public.spec_definitions d
cross join (values
  ('high_friction', 'Roza / cuesta mover', 13),
  ('housing_damaged', 'Funda dañada', 14)
) as nuevo(codigo, etiqueta, orden)
where d.key = 'component_condition' and d.tenant_id is null
on conflict (spec_definition_id, code) do update set
  label = excluded.label, updated_at = now();

create temporary table puente_diagnostico (
  campo_blob text, campo_registro text, parte text
) on commit drop;

-- La PIEZA también es parte del sujeto, no del campo. En una rueda delantera
-- hay condición de llanta, de rayos, de neumático y de maza: cuatro hechos del
-- mismo campo sobre cuatro piezas. Aplastarlos en «condición del sistema»
-- perdería tres de cada cuatro — el primer intento de esta migración chocó
-- justamente ahí, y el choque tenía razón.
insert into puente_diagnostico values
  ('overall_status',             'overall_status',       null),
  ('notes',                      'diagnosis_notes',      null),
  ('tubeless_status',            'tubeless_status',      null),
  ('noise_status',               'noise_status',         null),
  ('chain_wear_percent',         'wear_percent',         'chain'),
  ('pad_wear_percent',           'wear_percent',         'pad'),
  ('rotor_thickness_mm',         'rotor_thickness_mm',   'rotor'),
  ('cassette_condition',         'component_condition',  'cassette'),
  ('chainring_condition',        'component_condition',  'chainring'),
  ('shifter_condition',          'component_condition',  'shifter'),
  ('cable_condition',            'component_condition',  'cable'),
  ('front_derailleur_condition', 'component_condition',  'front_derailleur'),
  ('rear_derailleur_condition',  'component_condition',  'rear_derailleur'),
  ('fork_condition',             'component_condition',  'fork'),
  ('rear_shock_condition',       'component_condition',  'rear_shock'),
  ('headset_bearing_condition',  'component_condition',  'headset_bearing'),
  ('hub_bearing_condition',      'component_condition',  'hub_bearing'),
  ('rim_condition',              'component_condition',  'rim'),
  ('spoke_condition',            'component_condition',  'spoke'),
  ('tire_condition',             'component_condition',  'tire'),
  ('rotor_trueness_status',      'component_condition',  'rotor'),
  ('pad_contamination_status',   'contamination_status', 'pad'),
  ('rotor_contamination_status', 'contamination_status', 'rotor'),
  ('fork_noise_status',          'noise_status',         'fork'),
  ('headset_noise_status',       'noise_status',         'headset'),
  ('rear_shock_noise_status',    'noise_status',         'rear_shock');

create temporary table hallazgos on commit drop as
select mjb.tenant_id, mjb.id as job_bike_id,
  -- El alcance es sistema y pieza: `front_wheel/rim`, `front_brake/pad`.
  s.sistema || coalesce('/' || p.parte, '') as alcance,
  f.valor, d.id as definicion_id, d.data_type
from public.mechanic_job_bikes mjb
cross join lateral jsonb_each(mjb.diagnosis_sheet_data) as s(sistema, datos)
cross join lateral jsonb_each(s.datos) as f(campo, valor)
join puente_diagnostico p on p.campo_blob = f.campo
join public.spec_definitions d
  on d.key = p.campo_registro and d.tenant_id is null
where mjb.diagnosis_sheet_data is not null
  and jsonb_typeof(s.datos) = 'object'
  and jsonb_typeof(f.valor) <> 'null'
  and nullif(f.valor #>> '{}', '') is not null;

insert into public.spec_facts (
  tenant_id, subject_type, subject_id, subject_scope, spec_definition_id,
  value_number, value_text, source, confirmed
)
select h.tenant_id, 'job_bike', h.job_bike_id, h.alcance, h.definicion_id,
  case when h.data_type = 'number' then (h.valor #>> '{}')::numeric end,
  case when h.data_type = 'text' then h.valor #>> '{}' end,
  -- Un hallazgo de diagnóstico lo escribió el mecánico con la bici delante.
  'mechanic', true
from hallazgos h
where h.data_type in ('number', 'text')
   or h.data_type in ('single_select', 'multi_select')
on conflict (tenant_id, subject_type, subject_id, spec_definition_id,
             coalesce(subject_scope, ''))
do update set
  value_number = excluded.value_number,
  value_text = excluded.value_text,
  updated_at = now();

-- Los valores de lista ya vienen en código —`ok`, `attention`, `replace`—,
-- que es exactamente lo que el registro guarda. Calzan sin traducir.
insert into public.spec_fact_values (fact_id, value_id, position)
select f.id, sv.id, 0
from hallazgos h
join public.spec_facts f
  on f.tenant_id = h.tenant_id and f.subject_type = 'job_bike'
 and f.subject_id = h.job_bike_id and f.subject_scope = h.alcance
 and f.spec_definition_id = h.definicion_id
join public.spec_definition_values sv
  on sv.spec_definition_id = h.definicion_id and sv.code = h.valor #>> '{}'
where h.data_type = 'single_select'
on conflict do nothing;

commit;
