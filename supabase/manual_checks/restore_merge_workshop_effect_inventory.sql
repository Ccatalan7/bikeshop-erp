-- Read-only schema inventory for the next C2 workshop recovery forward.
-- No business rows, identifiers, files or payloads are returned. This is not a
-- deployment assertion: it identifies the actual writers to integrate/review.
with requested(table_name) as (values
  ('bikes'), ('bike_profiles'), ('mechanic_jobs'), ('mechanic_job_bikes'),
  ('mechanic_job_items'), ('mechanic_job_timeline'), ('bike_events'),
  ('bike_observations'), ('bike_interventions'), ('bike_system_states'),
  ('bike_component_lifecycles'), ('smart_tasks'), ('smart_task_attachments'),
  ('smart_task_job_items'), ('smart_task_job_item_notes'),
  ('bike_technical_fact_patches'), ('bike_fact_spec_links'),
  ('workshop_command_attempts'), ('mechanic_job_line_saves'),
  ('mechanic_job_creations'), ('mechanic_job_line_gate_deferrals')
)
select jsonb_build_object(
  'table', r.table_name,
  'exists', c.oid is not null,
  'captured_by_backup', exists(select 1 from public.restore_backup_covered_scope() s
    where s.table_name=r.table_name),
  'columns', coalesce((select jsonb_agg(jsonb_build_object(
    'name', a.attname, 'type', format_type(a.atttypid,a.atttypmod),
    'required', a.attnotnull, 'generated', a.attgenerated,
    'default', pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
    from pg_attribute a left join pg_attrdef d
      on d.adrelid=a.attrelid and d.adnum=a.attnum
    where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped), '[]'::jsonb),
  'foreign_keys', coalesce((select jsonb_agg(jsonb_build_object(
    'definition',pg_get_constraintdef(k.oid),'parent',k.confrelid::regclass::text,
    'delete_action',k.confdeltype,'update_action',k.confupdtype))
    from pg_constraint k where k.conrelid=c.oid and k.contype='f'), '[]'::jsonb),
  'triggers', coalesce((select jsonb_agg(jsonb_build_object(
    'trigger',pg_get_triggerdef(t.oid),'enabled',t.tgenabled,
    'function',t.tgfoid::regprocedure::text,
    'normalized_definition_md5',md5(replace(pg_get_functiondef(t.tgfoid),E'\r\n',E'\n')),
    'body',p.prosrc))
    from pg_trigger t join pg_proc p on p.oid=t.tgfoid
    where t.tgrelid=c.oid and not t.tgisinternal), '[]'::jsonb)
) as shape
from requested r left join pg_class c
  on c.oid=to_regclass(format('public.%I',r.table_name))
order by r.table_name;
