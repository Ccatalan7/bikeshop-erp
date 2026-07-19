-- User-facing discard for standalone, unpaid sales invoices.
--
-- This is intentionally not a physical DELETE. It records a command root,
-- lets the canonical invoice trigger reverse stock and accounting atomically,
-- and retains the cancelled invoice under the explicit "Anuladas" filter.
-- Paid invoices and invoices linked to workshop jobs use their dedicated
-- correction workflows instead.

begin;

alter table public.sales_invoices
  add column if not exists void_operation_id uuid,
  add column if not exists void_idempotency_key text,
  add column if not exists voided_at timestamp with time zone,
  add column if not exists voided_by uuid references auth.users(id) on delete set null,
  add column if not exists void_reason text;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'sales_invoices_void_operation_tenant_fkey'
       and conrelid = 'public.sales_invoices'::regclass
  ) then
    alter table public.sales_invoices
      add constraint sales_invoices_void_operation_tenant_fkey
      foreign key (tenant_id, void_operation_id)
      references public.inventory_accounting_operations(tenant_id, id)
      on delete restrict;
  end if;
end;
$$;

create unique index if not exists uq_sales_invoices_void_idempotency
  on public.sales_invoices(tenant_id, void_idempotency_key)
  where void_idempotency_key is not null;

comment on column public.sales_invoices.void_operation_id is
  'Trace command root for the user action that discarded this invoice.';
comment on column public.sales_invoices.void_reason is
  'Mandatory operational reason for discarding an unpaid standalone invoice.';

create or replace function public.void_sales_invoice(
  p_invoice_id uuid,
  p_reason text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_invoice public.sales_invoices%rowtype;
  v_after public.sales_invoices%rowtype;
  v_parent_operation_id uuid := gen_random_uuid();
  v_child_operation_id uuid;
  v_child_operation_key text;
  v_reason text := nullif(btrim(p_reason), '');
  v_idempotency_key text := nullif(btrim(p_idempotency_key), '');
  v_status text;
  v_active_payments integer := 0;
  v_linked_jobs integer := 0;
  v_posted_credit_notes integer := 0;
  v_posted_returns integer := 0;
  v_stock_line_count integer := 0;
  v_stock_movement_count_before integer := 0;
  v_stock_movement_count_after integer := 0;
  v_stock_net_errors integer := 0;
  v_stock_column_drift integer := 0;
  v_invoice_journals_before integer := 0;
  v_invoice_journals_after integer := 0;
  v_journal_reversal_checkpoints integer := 0;
begin
  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Se requiere una sesión de empleado autenticada.'
      using errcode = '42501';
  end if;

  if v_reason is null then
    raise exception 'Debes indicar por qué se descarta la factura.'
      using errcode = '22023';
  end if;
  if v_idempotency_key is null then
    raise exception 'La operación de descarte requiere una clave de reintento.'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
      from public.user_profiles profile
     where profile.user_id = v_actor_id
       and profile.tenant_id = v_tenant_id
       and coalesce(profile.is_active, false)
       and (
         profile.role in ('admin', 'manager')
         or lower(coalesce(profile.permissions->>'delete_invoices', 'false')) = 'true'
       )
  ) then
    raise exception 'No tienes permiso para descartar facturas.'
      using errcode = '42501';
  end if;

  select *
    into v_invoice
    from public.sales_invoices invoice
   where invoice.id = p_invoice_id
     and invoice.tenant_id = v_tenant_id
   for update;

  if not found then
    raise exception 'La factura no existe en este negocio.'
      using errcode = 'P0002';
  end if;

  v_status := lower(coalesce(v_invoice.status, 'draft'));

  if v_status in ('cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada') then
    if v_invoice.void_idempotency_key = v_idempotency_key then
      return jsonb_build_object(
        'invoice_id', v_invoice.id,
        'invoice_number', v_invoice.invoice_number,
        'status', v_invoice.status,
        'operation_id', v_invoice.void_operation_id,
        'replayed', true
      );
    end if;
    raise exception 'La factura ya está anulada.'
      using errcode = '23514';
  end if;

  if v_status in ('draft', 'borrador') then
    raise exception 'Los borradores se eliminan con la acción Eliminar borrador.'
      using errcode = '23514';
  end if;

  if v_status in ('paid', 'pagado', 'pagada') then
    raise exception 'Una factura pagada representa dinero recibido. Usa devolución o nota de crédito, no Descartar factura.'
      using errcode = '23514';
  end if;

  if v_status not in (
    'sent', 'enviado', 'enviada', 'issued', 'emitido', 'emitida',
    'confirmed', 'confirmado', 'confirmada',
    'overdue', 'vencido', 'vencida'
  ) then
    raise exception 'El estado actual de la factura no admite el descarte seguro.'
      using errcode = '23514';
  end if;

  select count(*)::integer
    into v_linked_jobs
    from public.mechanic_jobs job
   where job.tenant_id = v_tenant_id
     and job.invoice_id = v_invoice.id
     and job.deleted_at is null;
  if v_linked_jobs <> 0 then
    raise exception 'Esta factura pertenece a un trabajo de taller. Administra la anulación desde el trabajo para no separar sus datos.'
      using errcode = '23514';
  end if;

  select count(*)::integer
    into v_active_payments
    from public.sales_payments payment
   where payment.tenant_id = v_tenant_id
     and payment.invoice_id = v_invoice.id
     and payment.deleted_at is null;
  if v_active_payments <> 0 then
    raise exception 'La factura tiene pagos activos. Revierte primero esos pagos o usa la corrección posterior a la venta.'
      using errcode = '23514';
  end if;

  select count(*)::integer
    into v_posted_credit_notes
    from public.sales_credit_notes note
   where note.tenant_id = v_tenant_id
     and note.sales_invoice_id = v_invoice.id
     and note.status = 'posted';
  select count(*)::integer
    into v_posted_returns
    from public.sales_returns returned
   where returned.tenant_id = v_tenant_id
     and returned.sales_invoice_id = v_invoice.id
     and returned.status = 'posted';
  if v_posted_credit_notes <> 0 or v_posted_returns <> 0 then
    raise exception 'La factura ya tiene devoluciones o notas de crédito contabilizadas. Anula primero esas correcciones.'
      using errcode = '23514';
  end if;

  select count(*)::integer
    into v_stock_line_count
    from jsonb_array_elements(coalesce(v_invoice.items, '[]'::jsonb)) item
    join public.products product
      on product.id = nullif(item->>'product_id', '')::uuid
     and product.tenant_id = v_tenant_id
   where not coalesce((item->>'is_service')::boolean, false)
     and coalesce(nullif(item->>'purchase_treatment', ''), 'inventory') <> 'workshop_consumable'
     and coalesce(product.track_stock, true)
     and not coalesce(product.is_service, false)
     and coalesce(nullif(item->>'quantity', '')::numeric, 0) > 0;

  select count(*)::integer
    into v_stock_movement_count_before
    from public.stock_movements movement
   where movement.tenant_id = v_tenant_id
     and movement.reference = 'sales_invoice:' || v_invoice.id::text;

  if v_status in (
      'confirmed', 'confirmado', 'confirmada',
      'overdue', 'vencido', 'vencida'
    ) and v_stock_line_count > 0 and v_stock_movement_count_before = 0 then
    raise exception 'La factura tiene productos inventariables pero no posee una huella de salida verificable. No se aplicó ningún cambio.'
      using errcode = '23514';
  end if;

  select count(*)::integer
    into v_stock_column_drift
    from public.products product
   where product.tenant_id = v_tenant_id
     and product.id in (
       select movement.product_id
         from public.stock_movements movement
        where movement.tenant_id = v_tenant_id
          and movement.reference = 'sales_invoice:' || v_invoice.id::text
     )
     and coalesce(product.inventory_qty, 0)
         <> coalesce(product.stock_quantity, 0);
  if v_stock_column_drift <> 0 then
    raise exception 'El stock actual tiene columnas en desacuerdo. No se aplicó ningún cambio.'
      using errcode = '23514';
  end if;

  if v_status in (
      'confirmed', 'confirmado', 'confirmada',
      'overdue', 'vencido', 'vencida'
    ) then
    select count(*)::integer
      into v_stock_net_errors
      from (
        select movement.product_id
          from public.stock_movements movement
         where movement.tenant_id = v_tenant_id
           and movement.reference = 'sales_invoice:' || v_invoice.id::text
         group by movement.product_id
        having round(sum(movement.quantity), 2) >= 0
      ) broken;
    if v_stock_net_errors <> 0 then
      raise exception 'La huella de inventario de la factura ya está compensada o es inconsistente. No se aplicó ningún cambio.'
        using errcode = '23514';
    end if;
  end if;

  select count(*)::integer
    into v_invoice_journals_before
    from public.journal_entries entry
   where entry.tenant_id = v_tenant_id
     and entry.source_module = 'sales_invoices'
     and entry.source_reference = v_invoice.invoice_number;

  if v_status in (
      'confirmed', 'confirmado', 'confirmada',
      'overdue', 'vencido', 'vencida'
    ) and v_invoice_journals_before <> 1 then
    raise exception 'La factura no tiene exactamente un asiento contable verificable. No se aplicó ningún cambio.'
      using errcode = '23514';
  end if;
  if v_status in (
      'sent', 'enviado', 'enviada', 'issued', 'emitido', 'emitida'
    ) and v_invoice_journals_before <> 0 then
    raise exception 'La factura enviada posee un asiento inesperado. No se aplicó ningún cambio.'
      using errcode = '23514';
  end if;

  insert into public.inventory_accounting_operations (
    id,
    tenant_id,
    operation_key,
    source_channel,
    action,
    document_type,
    document_id,
    actor_id,
    executor,
    old_status,
    new_status,
    before_snapshot,
    context
  ) values (
    v_parent_operation_id,
    v_tenant_id,
    format('sales_invoice_void:%s:%s', v_invoice.id, v_idempotency_key),
    'sales_invoice_discard',
    'void',
    'sales_invoice',
    v_invoice.id,
    v_actor_id,
    'database_command',
    v_invoice.status,
    'cancelled',
    public.inventory_trace_document_snapshot(to_jsonb(v_invoice)),
    jsonb_build_object(
      'reason', v_reason,
      'invoice_number', v_invoice.invoice_number,
      'active_payments_before', v_active_payments,
      'stock_movements_before', v_stock_movement_count_before,
      'invoice_journals_before', v_invoice_journals_before
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    v_parent_operation_id,
    'accepted',
    'started',
    'sales_invoice',
    v_invoice.id,
    jsonb_build_object(
      'command', 'void_sales_invoice',
      'reason', v_reason,
      'old_status', v_invoice.status,
      'new_status', 'cancelled'
    )
  );

  perform public.set_inventory_accounting_trace_context(jsonb_build_object(
    'operation_id', v_parent_operation_id,
    'source_document_type', 'sales_invoice',
    'source_document_id', v_invoice.id,
    'source_channel', 'sales_invoice_discard'
  ));
  perform set_config('app.inventory_idempotency_key', v_idempotency_key, true);

  update public.sales_invoices
     set status = 'cancelled',
         void_operation_id = v_parent_operation_id,
         void_idempotency_key = v_idempotency_key,
         voided_at = clock_timestamp(),
         voided_by = v_actor_id,
         void_reason = v_reason,
         updated_at = clock_timestamp()
   where id = v_invoice.id
     and tenant_id = v_tenant_id;

  v_child_operation_key := format(
    'sales_invoice:%s:update:%s',
    v_invoice.id,
    v_idempotency_key
  );
  select operation.id
    into v_child_operation_id
    from public.inventory_accounting_operations operation
   where operation.tenant_id = v_tenant_id
     and operation.operation_key = v_child_operation_key
     and operation.document_type = 'sales_invoice'
     and operation.document_id = v_invoice.id
     and operation.outcome = 'completed';
  if v_child_operation_id is null then
    raise exception 'La anulación no produjo una huella hija completa. Toda la operación fue revertida.'
      using errcode = '23514';
  end if;

  update public.inventory_accounting_operations
     set context = context || jsonb_build_object(
       'parent_operation_id', v_parent_operation_id,
       'command_action', 'void',
       'command_reason', v_reason
     )
   where id = v_child_operation_id
     and tenant_id = v_tenant_id;

  select *
    into v_after
    from public.sales_invoices invoice
   where invoice.id = v_invoice.id
     and invoice.tenant_id = v_tenant_id;

  select count(*)::integer
    into v_stock_movement_count_after
    from public.stock_movements movement
   where movement.tenant_id = v_tenant_id
     and movement.reference = 'sales_invoice:' || v_invoice.id::text;

  select count(*)::integer
    into v_stock_net_errors
    from (
      select movement.product_id
        from public.stock_movements movement
       where movement.tenant_id = v_tenant_id
         and movement.reference = 'sales_invoice:' || v_invoice.id::text
       group by movement.product_id
      having round(sum(movement.quantity), 2) <> 0
    ) broken;

  select count(*)::integer
    into v_stock_column_drift
    from public.products product
   where product.tenant_id = v_tenant_id
     and product.id in (
       select movement.product_id
         from public.stock_movements movement
        where movement.tenant_id = v_tenant_id
          and movement.reference = 'sales_invoice:' || v_invoice.id::text
     )
     and coalesce(product.inventory_qty, 0)
         <> coalesce(product.stock_quantity, 0);

  select count(*)::integer
    into v_invoice_journals_after
    from public.journal_entries entry
   where entry.tenant_id = v_tenant_id
     and entry.source_module = 'sales_invoices'
     and entry.source_reference = v_invoice.invoice_number;

  select count(*)::integer
    into v_journal_reversal_checkpoints
    from public.inventory_accounting_checkpoints checkpoint
   where checkpoint.operation_id = v_child_operation_id
     and checkpoint.phase = 'journal_reversed'
     and checkpoint.outcome = 'completed';

  if lower(v_after.status) <> 'cancelled'
     or v_stock_net_errors <> 0
     or v_stock_column_drift <> 0
     or v_invoice_journals_after <> 0
     or (v_invoice_journals_before > 0 and v_journal_reversal_checkpoints = 0) then
    raise exception 'Falló la verificación final de inventario o contabilidad. Toda la operación fue revertida.'
      using errcode = '23514';
  end if;

  perform public.append_inventory_accounting_checkpoint(
    v_parent_operation_id,
    'source_snapshotted',
    'completed',
    'sales_invoice',
    v_invoice.id,
    jsonb_build_object(
      'before', public.inventory_trace_document_snapshot(to_jsonb(v_invoice)),
      'after', public.inventory_trace_document_snapshot(to_jsonb(v_after)),
      'child_operation_id', v_child_operation_id
    )
  );
  perform public.append_inventory_accounting_checkpoint(
    v_parent_operation_id,
    'inventory_applied',
    'completed',
    'sales_invoice',
    v_invoice.id,
    jsonb_build_object(
      'child_operation_id', v_child_operation_id,
      'movement_count_before', v_stock_movement_count_before,
      'movement_count_after', v_stock_movement_count_after,
      'net_movement_errors', v_stock_net_errors,
      'stock_column_drift', v_stock_column_drift
    )
  );
  perform public.append_inventory_accounting_checkpoint(
    v_parent_operation_id,
    'journal_reversed',
    'completed',
    'sales_invoice',
    v_invoice.id,
    jsonb_build_object(
      'child_operation_id', v_child_operation_id,
      'journals_before', v_invoice_journals_before,
      'journals_after', v_invoice_journals_after,
      'archive_checkpoints', v_journal_reversal_checkpoints
    )
  );

  update public.inventory_accounting_operations
     set after_snapshot = public.inventory_trace_document_snapshot(to_jsonb(v_after)),
         context = context || jsonb_build_object(
           'child_operation_id', v_child_operation_id,
           'stock_movements_after', v_stock_movement_count_after,
           'invoice_journals_after', v_invoice_journals_after
         )
   where id = v_parent_operation_id
     and tenant_id = v_tenant_id;

  perform public.complete_inventory_accounting_operation(
    v_parent_operation_id,
    v_tenant_id,
    jsonb_build_object(
      'invoice_id', v_invoice.id,
      'invoice_number', v_invoice.invoice_number,
      'status', v_after.status,
      'reason', v_reason,
      'child_operation_id', v_child_operation_id,
      'stock_movements_added',
        v_stock_movement_count_after - v_stock_movement_count_before
    )
  );

  perform public.set_inventory_accounting_trace_context('{}'::jsonb);
  perform set_config('app.inventory_idempotency_key', '', true);

  return jsonb_build_object(
    'invoice_id', v_invoice.id,
    'invoice_number', v_invoice.invoice_number,
    'status', v_after.status,
    'operation_id', v_parent_operation_id,
    'child_operation_id', v_child_operation_id,
    'stock_movements_added',
      v_stock_movement_count_after - v_stock_movement_count_before,
    'replayed', false
  );
exception
  when others then
    perform public.set_inventory_accounting_trace_context('{}'::jsonb);
    perform set_config('app.inventory_idempotency_key', '', true);
    raise;
end;
$$;

revoke all on function public.void_sales_invoice(uuid, text, text)
  from public, anon, service_role;
grant execute on function public.void_sales_invoice(uuid, text, text)
  to authenticated;

-- Additive read models keep the original trace/ledger contracts stable while
-- surfacing the command that caused a trigger-owned movement. This lets the
-- Movements UI distinguish an intentional invoice discard from an unexplained
-- historical reversal.
create or replace view public.inventory_accounting_operation_trace_enriched_view
with (security_invoker = on)
as
select
  trace.*,
  operation.context,
  parent.id as parent_operation_id,
  parent.action as parent_action,
  parent.source_channel as parent_source_channel,
  parent.actor_id as parent_actor_id,
  parent.outcome as parent_outcome,
  parent.context as parent_context
from public.inventory_accounting_operation_trace_view trace
join public.inventory_accounting_operations operation
  on operation.id = trace.operation_id
 and operation.tenant_id = trace.tenant_id
left join public.inventory_accounting_operations parent
  on parent.tenant_id = operation.tenant_id
 and parent.id::text = operation.context->>'parent_operation_id';

grant select on public.inventory_accounting_operation_trace_enriched_view
  to authenticated;

create or replace view public.stock_movements_operational_view
with (security_invoker = on)
as
select
  ledger.*,
  coalesce(parent.id, operation.id) as trigger_operation_id,
  coalesce(parent.action, operation.action) as trigger_action,
  coalesce(parent.source_channel, operation.source_channel)
    as trigger_source_channel,
  coalesce(parent.actor_id, operation.actor_id) as trigger_actor_id,
  coalesce(
    parent.context->>'reason',
    operation.context->>'command_reason'
  ) as trigger_reason
from public.stock_movements_ledger_view ledger
left join public.inventory_accounting_operations operation
  on operation.id = ledger.operation_id
 and operation.tenant_id = ledger.tenant_id
left join public.inventory_accounting_operations parent
  on parent.tenant_id = operation.tenant_id
 and parent.id::text = operation.context->>'parent_operation_id';

grant select on public.stock_movements_operational_view to authenticated;

notify pgrst, 'reload schema';

commit;
