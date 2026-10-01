-- C2: capture the workshop graph with the legacy store snapshot in ONE SQL
-- snapshot. The destructive legacy recovery scope remains unchanged.
-- This forward is prepared, not APPLIED. Deploy with 20260930171000 and
-- 20260930172000 (the integrated recovery) after their local gate.
-- Claude's review, 2026-09-30: `mechanic_job_line_gate_deferrals` holds rows
-- of transactions in flight (keyed by txid) and is not business data, so it
-- is not captured; `supply_needs` (repuestos por conseguir) hangs from the
-- job and its bikes and is captured with them.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

create or replace function public.workshop_backup_scope_internal()
returns table(ord integer, table_name text, predicate text)
language sql immutable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select * from public.restore_backup_covered_scope()
  union all
  select 100 + addition.ord, addition.table_name,
         'tenant_id = p_tenant_id'::text
  from (values
    (1, 'bike_profiles'),
    (2, 'bike_events'),
    (3, 'bike_observations'),
    (4, 'bike_component_lifecycles'),
    (5, 'bike_interventions'),
    (6, 'bike_system_states'),
    (7, 'bike_technical_fact_patches'),
    (8, 'bike_aggregate_save_operations'),
    (9, 'mechanic_job_bikes'),
    (10, 'mechanic_job_creations'),
    (11, 'mechanic_job_line_saves'),
    (12, 'supply_needs'),
    (13, 'mechanic_job_archive_events'),
    (14, 'mechanic_job_delivery_events'),
    (15, 'mechanic_job_mode_events'),
    (16, 'mechanic_job_status_transition_events'),
    (17, 'mechanic_job_status_transitions'),
    (18, 'mechanic_job_task_preferences'),
    (19, 'mechanic_job_tasks'),
    (20, 'smart_tasks'),
    (21, 'smart_task_attachments'),
    (22, 'smart_task_job_items'),
    (23, 'smart_task_job_item_notes'),
    (24, 'smart_task_events'),
    (25, 'smart_task_command_receipts'),
    (26, 'smart_task_message_channels'),
    (27, 'smart_task_user_state'),
    (28, 'workshop_command_attempts'),
    (29, 'mechanic_job_warranty_claim_events'),
    (30, 'job_statuses'),
    (31, 'job_subjects'),
    (32, 'service_packages')
  ) addition(ord, table_name)
$function$;

-- Each branch is an explicit closed table/predicate; identifiers are quoted
-- and tenant values are parameters. A missing relation/tenant column fails
-- the backup rather than silently producing an incomplete completed record.
-- An empty table is captured as JSON null, like the legacy capture: the
-- legacy replay inserts every array with `select *`, and an empty array of
-- `products` still names its generated column and fails (Claude, 2026-09-30,
-- restore_backup_missing_images). The integrated recovery skips null.
create or replace function public.capture_workshop_backup_internal(p_tenant_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_sql text;
  v_data jsonb;
begin
  if p_tenant_id is null then
    raise exception 'Backup tenant is required' using errcode = '22023';
  end if;
  select string_agg(format(
    'select %L::text as table_name, jsonb_agg(to_jsonb(row)) as rows from public.%I row where %s',
    s.table_name, s.table_name, replace(s.predicate, 'p_tenant_id', '$1')),
    ' union all ' order by s.ord)
    into v_sql from public.workshop_backup_scope_internal() s;
  execute 'select jsonb_object_agg(table_name, rows) from (' || v_sql || ') captured'
    into v_data using p_tenant_id;
  return v_data;
end;
$function$;

create or replace function public.create_backup_internal(
  p_tenant_id uuid, p_backup_name text,
  p_backup_type text default 'manual', p_notes text default null
) returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_backup_id uuid;
  v_data jsonb;
  v_summary jsonb;
  v_size bigint;
begin
  -- Public create_backup rechecks admin authority; the scheduler uses this
  -- private function directly. No new public capture bypass is introduced.
  v_data := public.capture_workshop_backup_internal(p_tenant_id);
  select jsonb_object_agg(k, case when jsonb_typeof(v) = 'array' then jsonb_array_length(v) else 0 end)
    into v_summary from jsonb_each(v_data) captured(k, v);
  v_summary := v_summary || jsonb_build_object(
    'captured_at', statement_timestamp(),
    'capture_contract', 'workshop_graph_v1',
    'chat_attachments', (select count(*) from jsonb_array_elements(
      case when jsonb_typeof(v_data -> 'messages') = 'array' then v_data -> 'messages'
           else '[]'::jsonb end) m
      where m ->> 'type' in ('image', 'file') or (m -> 'metadata') ?| array[
        'url','media_url','documentUrl','document_url']));
  v_size := octet_length(v_data::text);
  insert into public.database_backups(
    tenant_id, backup_name, backup_type, status, backup_data, summary,
    backup_size_bytes, notes, created_by
  ) values (
    p_tenant_id, p_backup_name, p_backup_type, 'completed', v_data, v_summary,
    v_size, p_notes, auth.uid()
  ) returning id into v_backup_id;
  -- Preserve the supplier-secret redaction contract and its measured size.
  if not public.redact_supplier_passwords_from_backup_row(v_backup_id) then
    raise exception 'Created backup could not be sanitized' using errcode = 'P0001';
  end if;
  -- The legacy redactor measures characters. Measure the sanitized UTF-8
  -- payload in bytes here, including non-ASCII customer/description text.
  update public.database_backups b
    set backup_size_bytes = octet_length(b.backup_data::text)
    where b.id = v_backup_id and b.tenant_id = p_tenant_id
    returning b.backup_size_bytes into v_size;
  if v_size is null then
    raise exception 'Sanitized backup size could not be verified' using errcode = 'P0001';
  end if;
  return jsonb_build_object('success', true, 'backup_id', v_backup_id,
    'summary', v_summary, 'size_mb', round((v_size / 1024.0 / 1024.0)::numeric, 2));
exception when others then
  -- The exception block rolls back capture/insertion/redaction together.
  insert into public.database_backups(
    tenant_id, backup_name, backup_type, status, backup_data, error_message, created_by
  ) values (
    p_tenant_id, p_backup_name, p_backup_type, 'failed', '{}'::jsonb, SQLERRM, auth.uid()
  );
  return jsonb_build_object('success', false,
    'error', 'No se pudo completar el respaldo. No se guardó una copia parcial.');
end;
$function$;

revoke all on function public.workshop_backup_scope_internal(),
  public.capture_workshop_backup_internal(uuid),
  public.create_backup_internal(uuid,text,text,text)
  from public, anon, authenticated, service_role;

commit;
