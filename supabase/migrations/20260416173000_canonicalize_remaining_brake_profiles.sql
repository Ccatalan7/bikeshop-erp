-- Canonicalize the remaining legacy global brake profiles that still drift on
-- wheel-target vocabulary while preserving legitimate execution-only fields.

update public.service_profiles
set
  service_family = 'brake',
  customer_summary_template = case
    when key = 'caliper_service' then 'Servicio de cáliper {{which_wheel}}'
    when key = 'brake_cable_replace_adjust' then 'Reemplazo cable y funda de freno {{which_wheel}}'
    else customer_summary_template
  end,
  mechanic_summary_template = case
    when key = 'caliper_service' then 'Servicio cáliper {{which_wheel}} — limpiar pistones, revisar sellos.'
    when key = 'brake_cable_replace_adjust' then 'Reemplazar cable/funda freno {{which_wheel}}, regular ajuste final.'
    else mechanic_summary_template
  end,
  updated_at = now()
where tenant_id is null
  and key in ('caliper_service', 'brake_cable_replace_adjust');

delete from public.service_profile_questions spq
using public.service_profiles sp
where sp.id = spq.service_profile_id
  and sp.tenant_id is null
  and sp.key in ('caliper_service', 'brake_cable_replace_adjust')
  and spq.key = 'position';

insert into public.service_profile_questions (
  id,
  tenant_id,
  service_profile_id,
  key,
  label,
  question_type,
  is_required,
  sort_order,
  options_json
)
select
  seed.id,
  null,
  sp.id,
  seed.key,
  seed.label,
  seed.question_type,
  seed.is_required,
  seed.sort_order,
  seed.options_json
from public.service_profiles sp
join (
  values
    ('00000000-0090-0001-0000-000000000001'::uuid, 'caliper_service', 'which_wheel', '¿Qué rueda(s)?', 'single_select', true, 10,
     '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb),
    ('00000000-0091-0001-0000-000000000001'::uuid, 'brake_cable_replace_adjust', 'which_wheel', '¿Qué rueda(s)?', 'single_select', true, 10,
     '[{"value":"front","label":"Delantera"},{"value":"rear","label":"Trasera"},{"value":"both","label":"Ambas"}]'::jsonb)
) as seed(id, profile_key, key, label, question_type, is_required, sort_order, options_json)
  on sp.key = seed.profile_key
where sp.tenant_id is null
  and sp.key in ('caliper_service', 'brake_cable_replace_adjust')
on conflict (service_profile_id, key) do update set
  label = excluded.label,
  question_type = excluded.question_type,
  is_required = excluded.is_required,
  sort_order = excluded.sort_order,
  options_json = excluded.options_json,
  updated_at = now();
