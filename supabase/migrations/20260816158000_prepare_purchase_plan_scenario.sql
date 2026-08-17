-- Deployment status: DEPLOYED and registered on production
-- xzdvtzdqjeyqxnkqprtf on 2026-08-16; exact function/ACL read-back passed.
-- Atomic adoption of a bounded basket scenario into a review-only plan.
--
-- The command composes the already-audited single-line command inside one
-- database transaction. A failure on any line rolls the whole scenario back;
-- no purchase order, invoice, payment, receipt or inventory movement is made.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.prepare_purchase_plan_scenario_v1(
  p_plan_id uuid,
  p_expected_plan_version bigint,
  p_lines jsonb,
  p_profile text,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set lock_timeout = '750ms'
as $$
declare
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_plan_id uuid := p_plan_id;
  v_plan_version bigint := p_expected_plan_version;
  v_step jsonb;
  v_changed boolean := false;
  v_all_replayed boolean := true;
  v_prepared_count integer := 0;
  v_line record;
begin
  if jsonb_typeof(p_lines) <> 'array'
     or jsonb_array_length(p_lines) not between 1 and 8
     or p_profile not in ('balanced', 'profitability', 'urgent_local')
     or v_operation_key = '' or octet_length(v_operation_key) > 180
     or (p_plan_id is null and p_expected_plan_version is not null)
     or (p_plan_id is not null and p_expected_plan_version is null) then
    raise exception 'Los datos del escenario no son válidos.'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_lines) line(value)
    where jsonb_typeof(line.value) <> 'object'
       or line.value - array[
         'sourceNeedId', 'candidateId', 'quantity'
       ] <> '{}'::jsonb
       or jsonb_typeof(line.value -> 'sourceNeedId') <> 'string'
       or not ((line.value ->> 'sourceNeedId') ~*
         '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
       or jsonb_typeof(line.value -> 'candidateId') <> 'string'
       or not ((line.value ->> 'candidateId') ~*
         '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
       or jsonb_typeof(line.value -> 'quantity') <> 'number'
       or (line.value ->> 'quantity')::numeric <= 0
       or (line.value ->> 'quantity')::numeric > 999999
  ) then
    raise exception 'Las líneas del escenario no son válidas.'
      using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_lines) line(value)
    group by line.value ->> 'sourceNeedId'
    having count(*) > 1
  ) then
    raise exception 'Una necesidad no puede repetirse en el escenario.'
      using errcode = '22023';
  end if;

  for v_line in
    select line.ordinality::integer as line_order,
      (line.value ->> 'sourceNeedId')::uuid as source_need_id,
      (line.value ->> 'candidateId')::uuid as candidate_id,
      (line.value ->> 'quantity')::numeric as quantity
    from jsonb_array_elements(p_lines) with ordinality line(value, ordinality)
    order by line.ordinality
  loop
    v_step := public.prepare_purchase_plan_line_v1(
      v_plan_id,
      v_plan_version,
      v_line.source_need_id,
      v_line.candidate_id,
      v_line.quantity,
      p_profile,
      v_operation_key || ':line:' || lpad(v_line.line_order::text, 2, '0')
    );
    v_plan_id := (v_step ->> 'plan_id')::uuid;
    v_plan_version := (v_step ->> 'plan_version')::bigint;
    v_changed := v_changed or coalesce((v_step ->> 'changed')::boolean, false);
    v_all_replayed := v_all_replayed
      and coalesce((v_step ->> 'replay')::boolean, false);
    v_prepared_count := v_prepared_count + 1;
  end loop;

  return jsonb_build_object(
    'plan_id', v_plan_id,
    'plan_version', v_plan_version,
    'prepared_line_count', v_prepared_count,
    'changed', v_changed,
    'replay', v_all_replayed
  );
end;
$$;

revoke all on function public.prepare_purchase_plan_scenario_v1(
  uuid, bigint, jsonb, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.prepare_purchase_plan_scenario_v1(
  uuid, bigint, jsonb, text, text
) to authenticated;

comment on function public.prepare_purchase_plan_scenario_v1(
  uuid, bigint, jsonb, text, text
) is
  'Atomically adopts up to eight external scenario candidates into a versioned review-only purchase plan. Canonical hash-derived candidate UUIDs are accepted.';

notify pgrst, 'reload schema';

commit;
