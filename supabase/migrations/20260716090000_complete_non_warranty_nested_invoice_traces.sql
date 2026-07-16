-- Deployment status: DEPLOYED AND VERIFIED IN PRODUCTION 2026-07-16.
--
-- Purpose:
--   Close invoice-owned trace roots created by invoice updates nested inside a
--   normal workshop service/component status transition. Covered warranties
--   deliberately keep their nested sales-invoice root active until the
--   warranty lifecycle trigger attaches its explicit stock and cost-journal
--   effects. Every other nested invoice root is complete before its parent
--   trace context is restored. This migration replaces trigger logic only; it
--   performs no business-row rewrite or historical trace backfill.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- The covered-warranty lifecycle is the only caller that must keep a nested
-- invoice trace open after the invoice UPDATE returns. Publish an exact marker
-- only around that UPDATE and its explicit invoice-owned writers. The previous
-- transaction-local value is restored on success and error so multi-row
-- statements cannot leak one job's identity into the next row.
create or replace function public.sync_covered_warranty_invoice_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_old_complete boolean := false;
  v_new_complete boolean;
  v_invoice_id uuid;
  v_tenant_id uuid;
  v_invoice public.sales_invoices%rowtype;
  v_operation_text text;
  v_operation_id uuid;
  v_previous_warranty_marker text;
begin
  v_previous_warranty_marker := current_setting(
    'app.covered_warranty_nested_invoice_trace_marker',
    true
  );

  if tg_op = 'UPDATE'
     and old.status is not distinct from new.status
     and old.status_id is not distinct from new.status_id then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    v_invoice_id := coalesce(old.invoice_id, new.invoice_id);
    v_tenant_id := old.tenant_id;
  else
    v_invoice_id := new.invoice_id;
    v_tenant_id := new.tenant_id;
  end if;

  if new.job_type <> 'warranty'
     or new.workflow_kind <> 'warranty'
     or new.warranty_outcome <> 'covered'
     or v_invoice_id is null then
    return new;
  end if;

  if tg_op = 'UPDATE' then
    select invoice.* into v_invoice
    from public.sales_invoices invoice
    where invoice.id = v_invoice_id
      and invoice.tenant_id = v_tenant_id
    for update;

    if v_invoice.id is not null and (
      lower(v_invoice.status) in ('paid', 'pagado', 'pagada')
      or coalesce(v_invoice.paid_amount, 0) > 0
      or exists (
        select 1
        from public.sales_payments payment
        where payment.invoice_id = v_invoice.id
          and payment.tenant_id = v_invoice.tenant_id
          and payment.deleted_at is null
          and coalesce(payment.amount, 0) > 0
      )
    ) then
      raise exception 'La garantía cubierta tiene evidencia de pago. Su estado y efectos contables no pueden cambiar sin una corrección financiera auditada.'
        using errcode = '55000';
    end if;
  end if;

  if tg_op = 'UPDATE' then
    v_old_complete := public.mechanic_job_resolves_completion(
      old.status,
      old.status_id
    );
  end if;
  v_new_complete := public.mechanic_job_resolves_completion(
    new.status,
    new.status_id
  );

  perform set_config(
    'app.covered_warranty_nested_invoice_trace_marker',
    jsonb_build_object(
      'tenant_id', v_tenant_id,
      'job_id', new.id,
      'invoice_id', v_invoice_id,
      'transaction_id', txid_current()::text
    )::text,
    true
  );

  if v_new_complete then
    update public.sales_invoices invoice
    set status = 'confirmed', updated_at = clock_timestamp()
    where invoice.id = v_invoice_id
      and invoice.tenant_id = v_tenant_id
      and lower(invoice.status) in (
        'draft','borrador','sent','enviado','enviada','issued','emitido','emitida'
      )
    returning invoice.* into v_invoice;

    if v_invoice.id is not null then
      perform public.consume_sales_invoice_inventory(v_invoice);
      perform public.create_service_warranty_cost_journal(v_invoice);

      v_operation_text := nullif(
        current_setting('app.inventory_operation_id', true),
        ''
      );
      if v_operation_text ~* '^[0-9a-f-]{36}$' then
        v_operation_id := v_operation_text::uuid;
        if exists (
          select 1
          from public.inventory_accounting_operations operation
          where operation.id = v_operation_id
            and operation.tenant_id = v_tenant_id
            and operation.document_type = 'sales_invoice'
            and operation.document_id = v_invoice.id
            and operation.outcome = 'started'
        ) then
          perform public.complete_inventory_accounting_operation(
            v_operation_id,
            v_tenant_id,
            jsonb_build_object(
              'trigger_operation', lower(tg_op),
              'service_warranty_lifecycle', 'posted'
            )
          );
        end if;
        perform set_config('app.inventory_operation_id', '', true);
        perform set_config('app.inventory_source_document_type', '', true);
        perform set_config('app.inventory_source_document_id', '', true);
        perform set_config('app.inventory_source_channel', '', true);
      end if;
    end if;
  elsif v_old_complete then
    select * into v_invoice
    from public.sales_invoices invoice
    where invoice.id = v_invoice_id
      and invoice.tenant_id = v_tenant_id
      and lower(invoice.status) not in (
        'draft','borrador','sent','enviado','enviada','issued','emitido','emitida',
        'cancelled','cancelado','cancelada','anulado','anulada'
      )
    for update;

    if v_invoice.id is not null then
      update public.sales_invoices
      set status = case when upper(coalesce(new.status, '')) = 'CANCELADO'
        then 'cancelled' else 'draft' end,
        updated_at = clock_timestamp()
      where id = v_invoice.id;

      perform public.restore_sales_invoice_inventory(v_invoice);
      delete from public.journal_entries
      where tenant_id = v_invoice.tenant_id
        and source_module = 'sales_invoices'
        and source_reference = v_invoice.invoice_number;

      v_operation_text := nullif(
        current_setting('app.inventory_operation_id', true),
        ''
      );
      if v_operation_text ~* '^[0-9a-f-]{36}$' then
        v_operation_id := v_operation_text::uuid;
        if exists (
          select 1
          from public.inventory_accounting_operations operation
          where operation.id = v_operation_id
            and operation.tenant_id = v_tenant_id
            and operation.document_type = 'sales_invoice'
            and operation.document_id = v_invoice.id
            and operation.outcome = 'started'
        ) then
          perform public.complete_inventory_accounting_operation(
            v_operation_id,
            v_tenant_id,
            jsonb_build_object(
              'trigger_operation', lower(tg_op),
              'service_warranty_lifecycle', 'reversed'
            )
          );
        end if;
        perform set_config('app.inventory_operation_id', '', true);
        perform set_config('app.inventory_source_document_type', '', true);
        perform set_config('app.inventory_source_document_id', '', true);
        perform set_config('app.inventory_source_channel', '', true);
      end if;
    end if;
  end if;

  perform set_config(
    'app.covered_warranty_nested_invoice_trace_marker',
    coalesce(v_previous_warranty_marker, ''),
    true
  );
  return new;
exception
  when others then
    perform set_config(
      'app.covered_warranty_nested_invoice_trace_marker',
      coalesce(v_previous_warranty_marker, ''),
      true
    );
    raise;
end;
$$;

revoke all on function public.sync_covered_warranty_invoice_lifecycle()
  from public, anon, authenticated, service_role;

comment on function public.sync_covered_warranty_invoice_lifecycle() is
  'Posts or reverses covered-warranty invoice effects behind an exact transaction-local nested-trace marker; diagnosis-only updates are financial no-ops.';

create or replace function public.restore_inventory_accounting_trace_context_frame()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stack jsonb;
  v_index integer;
  v_frame jsonb;
  v_row jsonb;
  v_child_operation_id uuid;
  v_child_operation_started boolean := false;
  v_deferred_covered_warranty boolean := false;
  v_warranty_marker jsonb;
begin
  v_stack := coalesce(
    nullif(current_setting('app.inventory_trace_context_stack', true), ''),
    '[]'
  )::jsonb;
  v_row := case when TG_OP = 'DELETE' then to_jsonb(OLD) else to_jsonb(NEW) end;

  select (position - 1)::integer, frame
    into v_index, v_frame
    from jsonb_array_elements(v_stack) with ordinality queued(frame, position)
   where frame->>'state' = 'active'
     and frame->>'table' = TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME
     and frame->>'trigger_operation' = lower(TG_OP)
     and frame->>'tenant_id' = v_row->>'tenant_id'
     and frame->>'document_id' = v_row->>'id'
     and (frame->>'trigger_depth')::integer = pg_trigger_depth()
     and frame->>'transaction_id' = txid_current()::text
   order by position desc
   limit 1;

  if v_index is null then
    raise exception 'Canonical trace context restore frame missing for %.% % %',
      TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP, v_row->>'id'
      using errcode = 'data_exception';
  end if;

  -- A nested invoice UPDATE with no active invoice/payment parent creates its
  -- own canonical trace root. The generic invoice completion trigger skips at
  -- trigger depth > 1, so this final restore trigger owns its completion.
  if pg_trigger_depth() > 1
     and TG_TABLE_NAME in ('sales_invoices', 'purchase_invoices')
     and v_frame->'child_context'->>'operation_id' is distinct from
           v_frame->'parent_context'->>'operation_id'
     and nullif(v_frame->'child_context'->>'operation_id', '') is not null then
    v_child_operation_id :=
      (v_frame->'child_context'->>'operation_id')::uuid;

    select exists (
      select 1
        from public.inventory_accounting_operations operation
       where operation.id = v_child_operation_id
         and operation.tenant_id = (v_frame->>'tenant_id')::uuid
         and operation.document_id = (v_frame->>'document_id')::uuid
         and operation.document_type = case TG_TABLE_NAME
           when 'sales_invoices' then 'sales_invoice'
           else 'purchase_invoice'
         end
         and operation.action = lower(TG_OP)
         and operation.context->>'table'
               = TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME
         and operation.outcome = 'started'
    ) into v_child_operation_started;
  end if;

  if v_child_operation_started and TG_TABLE_NAME = 'sales_invoices' then
    -- Covered warranty lifecycle posting/reversal performs invoice-owned
    -- stock and cost-journal work after the nested invoice UPDATE returns.
    -- It must therefore retain the child root until that explicit writer calls
    -- complete_inventory_accounting_operation. Service and component jobs do
    -- not have that post-return writer and must complete here.
    v_warranty_marker := coalesce(
      nullif(
        current_setting(
          'app.covered_warranty_nested_invoice_trace_marker',
          true
        ),
        ''
      ),
      '{}'
    )::jsonb;

    select coalesce(
      v_warranty_marker->>'tenant_id' = v_frame->>'tenant_id'
        and v_warranty_marker->>'invoice_id' = v_frame->>'document_id'
        and v_warranty_marker->>'transaction_id' = txid_current()::text
        and exists (
          select 1
            from public.mechanic_jobs job
           where job.id = (v_warranty_marker->>'job_id')::uuid
             and job.tenant_id = (v_warranty_marker->>'tenant_id')::uuid
             and job.invoice_id = (v_warranty_marker->>'invoice_id')::uuid
             and job.deleted_at is null
             and job.job_type = 'warranty'
             and job.workflow_kind = 'warranty'
             and job.warranty_outcome = 'covered'
        ),
      false
    )
    into v_deferred_covered_warranty;
  end if;

  if v_child_operation_started and not v_deferred_covered_warranty then
    perform public.complete_inventory_accounting_operation(
      v_child_operation_id,
      (v_frame->>'tenant_id')::uuid,
      jsonb_strip_nulls(jsonb_build_object(
        'trigger_operation', lower(TG_OP),
        'nested_trace_completed_by',
          'restore_inventory_accounting_trace_context_frame',
        'parent_operation_id',
          nullif(v_frame->'parent_context'->>'operation_id', '')
      ))
    );
  end if;

  perform public.set_inventory_accounting_trace_context(
    case
      when v_deferred_covered_warranty then v_frame->'child_context'
      else v_frame->'parent_context'
    end
  );
  v_stack := v_stack - v_index;
  perform set_config('app.inventory_trace_context_stack', v_stack::text, true);
  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

revoke all on function public.restore_inventory_accounting_trace_context_frame()
  from public, anon, authenticated, service_role;

comment on function public.restore_inventory_accounting_trace_context_frame() is
  'Restores the exact per-row trace frame, completing ordinary nested invoice roots while an exact transaction-local marker defers covered-warranty roots to their explicit invoice-owned writers.';

commit;
