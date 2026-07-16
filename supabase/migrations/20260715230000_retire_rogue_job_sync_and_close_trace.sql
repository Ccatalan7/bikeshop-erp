-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-15
-- Deployment verification: rogue trigger absent; the one exact historical
-- trace root completed; job/invoice/payment/stock/journal fingerprints unchanged.
-- Purpose:
--   1. Keep the obsolete statement-level mechanic_jobs -> invoice sync trigger
--      absent under a unique, registerable migration version.
--   2. Close one historical trace root left started by that removed nested
--      trigger, but only when every persisted evidence check matches exactly.
--
-- This migration changes no job, invoice, payment, stock movement, product
-- balance, journal, or journal line. It only appends trace checkpoints and
-- marks the proven historical trace root completed.
--
-- Forward recovery:
--   Trace checkpoints are append-only evidence and should not be deleted. If a
--   future client needs automatic job/invoice synchronization, implement it as
--   an explicit idempotent command rather than restoring the removed trigger.

begin;

drop trigger if exists trg_mechanic_jobs_sync_invoice_update
  on public.mechanic_jobs;

do $$
declare
  v_operation public.inventory_accounting_operations%rowtype;
  v_operation_id constant uuid := 'f1bc8019-0d5b-4871-9d59-271d0cca2f81';
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_invoice_id constant uuid := 'fee00ca7-f710-451d-9744-23c3661ddc14';
  v_job_id constant uuid := 'f9e4ed4e-0ba7-4157-8cba-f8ce8432877e';
begin
  select * into v_operation
  from public.inventory_accounting_operations
  where id = v_operation_id;

  if not found then
    return;
  end if;

  if v_operation.outcome = 'completed' then
    return;
  end if;

  if v_operation.outcome <> 'started'
     or v_operation.tenant_id is distinct from v_tenant_id
     or v_operation.operation_key is distinct from
       'sales_invoice:fee00ca7-f710-451d-9744-23c3661ddc14:update:5d1ff277-b2a6-45fc-9a55-dd2700d59f1b'
     or v_operation.source_channel is distinct from 'mechanic_job'
     or v_operation.action is distinct from 'update'
     or v_operation.document_type is distinct from 'sales_invoice'
     or v_operation.document_id is distinct from v_invoice_id
     or v_operation.old_status is distinct from 'draft'
     or v_operation.new_status is distinct from 'enviado'
     or v_operation.before_snapshot is null
     or v_operation.after_snapshot is null then
    raise exception 'Historical workshop trace repair preflight failed: operation identity changed';
  end if;

  if not exists (
    select 1
    from public.sales_invoices invoice
    where invoice.id = v_invoice_id
      and invoice.tenant_id = v_tenant_id
  ) or not exists (
    select 1
    from public.mechanic_jobs job
    where job.id = v_job_id
      and job.tenant_id = v_tenant_id
      and job.invoice_id = v_invoice_id
  ) then
    raise exception 'Historical workshop trace repair preflight failed: source graph changed';
  end if;

  if not exists (
    select 1
    from public.inventory_accounting_checkpoints checkpoint
    where checkpoint.operation_id = v_operation_id
      and checkpoint.phase = 'accepted'
      and checkpoint.outcome = 'started'
  ) or not exists (
    select 1
    from public.inventory_accounting_checkpoints checkpoint
    where checkpoint.operation_id = v_operation_id
      and checkpoint.phase = 'source_snapshotted'
      and checkpoint.outcome = 'completed'
  ) or not exists (
    select 1
    from public.inventory_accounting_checkpoints checkpoint
    where checkpoint.operation_id = v_operation_id
      and checkpoint.phase = 'invariants_verified'
      and checkpoint.outcome = 'completed'
      and checkpoint.entity_type = 'mechanic_job'
      and checkpoint.entity_id = v_job_id
      and checkpoint.payload->>'control_name' = 'workshop_invoice_owner'
      and checkpoint.payload->>'control_status' = 'compliant'
      and checkpoint.payload->>'expected_inventory_owner' = 'sales_invoice'
      and checkpoint.payload->>'job_stock_movement_count' = '0'
      and checkpoint.payload->>'invoice_stock_movement_count' = '0'
      and checkpoint.payload->>'job_journal_count' = '0'
      and checkpoint.payload->>'invoice_journal_count' = '0'
  ) then
    raise exception 'Historical workshop trace repair preflight failed: checkpoint evidence incomplete';
  end if;

  if exists (
    select 1 from public.stock_movements
    where operation_id = v_operation_id
  ) or exists (
    select 1 from public.journal_entries
    where operation_id = v_operation_id
  ) then
    raise exception 'Historical workshop trace repair preflight failed: unexpected financial effects';
  end if;

  perform public.complete_inventory_accounting_operation(
    v_operation_id,
    v_tenant_id,
    jsonb_build_object(
      'repair', 'close_removed_rogue_job_sync_trace',
      'evidence', 'source_snapshot_and_compliant_workshop_owner_checkpoint',
      'business_effects_replayed', false
    )
  );
end;
$$;

do $$
begin
  if exists (
    select 1
    from public.inventory_accounting_operations
    where id = 'f1bc8019-0d5b-4871-9d59-271d0cca2f81'
      and outcome <> 'completed'
  ) then
    raise exception 'Historical workshop trace repair did not complete';
  end if;
end;
$$;

commit;
