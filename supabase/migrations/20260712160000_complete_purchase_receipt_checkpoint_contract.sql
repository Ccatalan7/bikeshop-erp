-- Deployment status: DEPLOYED 2026-07-12 to xzdvtzdqjeyqxnkqprtf.
-- Authenticated rollback smoke proved create/void ordered phase contracts,
-- exact linked movements, zero duplicate journal, and explicit accounting no-op.
-- Completes the professional receipt trace contract without adding a second
-- inventory-value journal: the purchase invoice already owns AP/tax/value.

begin;

create or replace function public.complete_purchase_receipt_checkpoint_contract()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation public.inventory_accounting_operations%rowtype;
  v_reason constant text := 'inventory_value_ap_tax_recognized_by_purchase_invoice';
begin
  select operation.*
  into v_operation
  from public.inventory_accounting_operations operation
  where operation.id = new.operation_id
    and operation.tenant_id = new.tenant_id;

  if not found
     or v_operation.document_type <> 'purchase_receipt'
     or v_operation.source_channel <> 'purchase_receipt' then
    return new;
  end if;

  if new.phase = 'accepted' then
    if not exists (
      select 1 from public.inventory_accounting_checkpoints checkpoint
      where checkpoint.operation_id = new.operation_id
        and checkpoint.phase = 'source_snapshotted'
    ) then
      insert into public.inventory_accounting_checkpoints (
        tenant_id, operation_id, phase, outcome, entity_type, entity_id, payload
      ) values (
        new.tenant_id, new.operation_id, 'source_snapshotted', 'completed',
        case when v_operation.action = 'create' then 'purchase_invoice' else 'purchase_receipt' end,
        case
          when v_operation.action = 'create'
            then nullif(v_operation.context->>'purchase_invoice_id', '')::uuid
          else v_operation.document_id
        end,
        jsonb_build_object(
          'snapshot_location', 'inventory_accounting_operations.before_snapshot',
          'source_version_locked', true,
          'action', v_operation.action
        )
      );
    end if;

    if not exists (
      select 1 from public.inventory_accounting_checkpoints checkpoint
      where checkpoint.operation_id = new.operation_id
        and checkpoint.phase = 'inventory_planned'
    ) then
      insert into public.inventory_accounting_checkpoints (
        tenant_id, operation_id, phase, outcome, entity_type, entity_id, payload
      ) values (
        new.tenant_id, new.operation_id, 'inventory_planned', 'completed',
        'purchase_receipt', v_operation.document_id,
        jsonb_build_object(
          'physical_stock_owner', 'purchase_receipt',
          'accepted_quantities_only', v_operation.action = 'create',
          'linked_reversal_only', v_operation.action = 'void'
        )
      );
    end if;
  elsif (
    new.phase = 'movement_recorded'
    and new.entity_type = 'purchase_receipt'
    and new.payload ? 'movement_count'
  ) or (
    v_operation.action = 'void'
    and new.phase = 'inventory_applied'
    and new.entity_type = 'purchase_receipt'
    and new.payload ? 'reversal_count'
  ) then
    if not exists (
      select 1 from public.inventory_accounting_checkpoints checkpoint
      where checkpoint.operation_id = new.operation_id
        and checkpoint.phase = 'accounting_planned'
    ) then
      insert into public.inventory_accounting_checkpoints (
        tenant_id, operation_id, phase, outcome, entity_type, entity_id, payload
      ) values (
        new.tenant_id, new.operation_id, 'accounting_planned', 'completed',
        new.entity_type, new.entity_id,
        jsonb_build_object(
          'accounting_owner', 'purchase_invoice',
          'journal_expected', false,
          'reason', v_reason
        )
      );
    end if;

    if not exists (
      select 1 from public.inventory_accounting_checkpoints checkpoint
      where checkpoint.operation_id = new.operation_id
        and checkpoint.phase = 'journal_posted'
    ) then
      insert into public.inventory_accounting_checkpoints (
        tenant_id, operation_id, phase, outcome, entity_type, entity_id, payload
      ) values (
        new.tenant_id, new.operation_id, 'journal_posted', 'completed',
        new.entity_type, new.entity_id,
        jsonb_build_object(
          'journal_count', 0,
          'not_required', true,
          'reason', v_reason
        )
      );
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.complete_purchase_receipt_checkpoint_contract()
  from public, anon, authenticated;

drop trigger if exists trg_complete_purchase_receipt_checkpoint_contract
  on public.inventory_accounting_checkpoints;
create trigger trg_complete_purchase_receipt_checkpoint_contract
  before insert on public.inventory_accounting_checkpoints
  for each row execute function public.complete_purchase_receipt_checkpoint_contract();

comment on function public.complete_purchase_receipt_checkpoint_contract() is
  'Fills the ordered receipt trace phases and records the deliberate zero-journal accounting decision owned by the purchase invoice.';

commit;
