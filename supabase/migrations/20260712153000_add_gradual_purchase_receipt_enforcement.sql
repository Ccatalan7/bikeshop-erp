-- Deployment status: DEPLOYED 2026-07-12 to xzdvtzdqjeyqxnkqprtf.
-- Authenticated rollback smoke passed both routes and mixed-route rejection;
-- Viñabike was then activated as enforce + untouched-invoice compatibility.
-- Enables a non-disruptive receipt rollout: current clients use professional
-- receipt commands while old clients remain compatible only on invoices that
-- have never entered the professional receipt ledger.

begin;

alter table public.purchase_receipt_control_settings
  add column if not exists legacy_untouched_compatibility boolean not null default false;

comment on column public.purchase_receipt_control_settings.legacy_untouched_compatibility is
  'Temporary rollout bridge. When enforce=true, legacy status receiving is allowed only for invoices with no posted/voided professional receipt evidence. Mixed ownership is always blocked.';

alter table public.purchase_receipt_compatibility_events
  drop constraint if exists purchase_receipt_compatibility_events_control_mode_check;
alter table public.purchase_receipt_compatibility_events
  add constraint purchase_receipt_compatibility_events_control_mode_check
  check (control_mode in ('shadow', 'enforce'));

create or replace function public.guard_legacy_purchase_receiving_when_enforced()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_mode text := 'disabled';
  v_legacy_compatibility boolean := false;
  v_has_professional_receipt boolean := false;
begin
  if new.status <> 'received'
     or (tg_op = 'UPDATE' and old.status is not distinct from 'received') then
    return new;
  end if;

  select
    coalesce(setting.control_mode, 'disabled'),
    coalesce(setting.legacy_untouched_compatibility, false)
  into v_mode, v_legacy_compatibility
  from (select 1) seed
  left join public.purchase_receipt_control_settings setting
    on setting.tenant_id = new.tenant_id;

  if v_mode <> 'enforce' then
    return new;
  end if;

  select exists (
    select 1
    from public.purchase_receipts receipt
    where receipt.tenant_id = new.tenant_id
      and receipt.purchase_invoice_id = new.id
  ) into v_has_professional_receipt;

  if v_has_professional_receipt then
    raise exception using
      errcode = 'P0001',
      message = 'This invoice already uses professional receipts; continue from the goods receipt workflow';
  end if;

  if not v_legacy_compatibility then
    raise exception using
      errcode = 'P0001',
      message = 'Professional receiving is active; use the goods receipt command';
  end if;

  return new;
end;
$$;

comment on function public.guard_legacy_purchase_receiving_when_enforced() is
  'Blocks mixed receipt ownership. During the temporary compatibility window, old clients may receive only untouched invoices; invoices with professional receipt evidence can only use receipt commands.';

create or replace function public.observe_legacy_purchase_receipt_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text := 'disabled';
  v_legacy_compatibility boolean := false;
  v_operation_text text := nullif(current_setting('app.inventory_operation_id', true), '');
  v_operation_id uuid;
begin
  if lower(coalesce(new.status, '')) <> 'received'
     or lower(coalesce(old.status, '')) = 'received' then
    return new;
  end if;

  select
    coalesce(setting.control_mode, 'disabled'),
    coalesce(setting.legacy_untouched_compatibility, false)
  into v_mode, v_legacy_compatibility
  from (select 1) seed
  left join public.purchase_receipt_control_settings setting
    on setting.tenant_id = new.tenant_id;

  if v_mode <> 'shadow'
     and not (v_mode = 'enforce' and v_legacy_compatibility) then
    return new;
  end if;

  if v_operation_text is not null and exists (
    select 1
    from public.inventory_accounting_operations operation
    where operation.id = v_operation_text::uuid
      and operation.tenant_id = new.tenant_id
  ) then
    v_operation_id := v_operation_text::uuid;
  end if;

  insert into public.purchase_receipt_compatibility_events (
    tenant_id,
    purchase_invoice_id,
    operation_id,
    event_type,
    old_status,
    new_status,
    control_mode,
    actor_id,
    transaction_id,
    client_context
  ) values (
    new.tenant_id,
    new.id,
    v_operation_id,
    'legacy_status_received',
    old.status,
    new.status,
    v_mode,
    auth.uid(),
    txid_current(),
    jsonb_build_object(
      'application_name', current_setting('application_name', true),
      'database_role', current_user,
      'invoice_number', new.invoice_number,
      'received_date', new.received_date,
      'rollout_route', 'legacy_invoice_status',
      'legacy_untouched_compatibility', v_legacy_compatibility
    )
  );
  return new;
end;
$$;

revoke all on function public.observe_legacy_purchase_receipt_transition()
  from public, anon, authenticated;

create or replace view public.purchase_receipt_rollout_status_view
with (security_invoker = true)
as
select
  setting.tenant_id,
  setting.control_mode,
  setting.legacy_untouched_compatibility,
  coalesce(receipt_totals.professional_receipt_count, 0) as professional_receipt_count,
  receipt_totals.latest_professional_receipt_at,
  coalesce(event_totals.legacy_receipt_event_count, 0) as legacy_receipt_event_count,
  event_totals.latest_legacy_receipt_at,
  case
    when setting.control_mode <> 'enforce' then 'not_enforced'
    when not setting.legacy_untouched_compatibility then 'professional_only'
    when event_totals.latest_legacy_receipt_at is null then 'compatibility_active_no_legacy_event_seen'
    when event_totals.latest_legacy_receipt_at >= clock_timestamp() - interval '14 days'
      then 'legacy_client_recently_active'
    else 'compatibility_review_due'
  end as rollout_status
from public.purchase_receipt_control_settings setting
left join lateral (
  select
    count(*)::bigint as professional_receipt_count,
    max(receipt.created_at) as latest_professional_receipt_at
  from public.purchase_receipts receipt
  where receipt.tenant_id = setting.tenant_id
) receipt_totals on true
left join lateral (
  select
    count(*)::bigint as legacy_receipt_event_count,
    max(event.occurred_at) as latest_legacy_receipt_at
  from public.purchase_receipt_compatibility_events event
  where event.tenant_id = setting.tenant_id
    and event.control_mode = 'enforce'
) event_totals on true;

grant select on public.purchase_receipt_rollout_status_view to authenticated;

comment on view public.purchase_receipt_rollout_status_view is
  'Evidence for retiring the temporary old-client receipt bridge. Status is advisory; compatibility is disabled only after reviewed workstation rollout evidence.';

commit;
