with resolved_targets as (
  select distinct on (bi.mechanic_job_item_id)
    bi.mechanic_job_item_id,
    bi.system_key,
    bi.component_slot_key,
    bi.location_key,
    bi.intervention_type,
    (bi.to_lifecycle_id is not null) as creates_lifecycle
  from public.bike_interventions bi
  where bi.mechanic_job_item_id is not null
  order by
    bi.mechanic_job_item_id,
    (bi.component_slot_key is not null) desc,
    bi.performed_at desc,
    bi.created_at desc
)
update public.mechanic_job_items mji
set system_key = rt.system_key,
    component_slot_key = rt.component_slot_key,
    location_key = coalesce(rt.location_key, 'none'),
    intervention_type = rt.intervention_type,
    creates_lifecycle = rt.creates_lifecycle,
    updated_at = now()
from resolved_targets rt
where mji.id = rt.mechanic_job_item_id;
