-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-10
-- Connects payment create/edit/delete actions to invoice status, job paid state,
-- payment journals, and the zero-inventory-side-effect invariant.

begin;

alter table public.purchase_invoices
  add column if not exists discount_amount numeric(12,2) not null default 0;

alter table public.mechanic_job_items
  add column if not exists description text;

create or replace function public.recalculate_purchase_invoice_payments(p_invoice_id uuid)
returns void as $$
declare
  v_invoice record;
  v_total numeric(12,2);
  v_new_status text;
  v_balance numeric(12,2);
begin
  if p_invoice_id is null then
    return;
  end if;

  select id,
         total,
         status,
         prepayment_model,
         received_date
    into v_invoice
    from public.purchase_invoices
   where id = p_invoice_id
   for update;

  if not found then
    return;
  end if;

  select public.clp_round(coalesce(sum(amount), 0))
    into v_total
    from public.purchase_payments
   where invoice_id = p_invoice_id
     and deleted_at is null;

  v_balance := greatest(public.clp_round(coalesce(v_invoice.total, 0)) - v_total, 0);

  if v_invoice.status = 'cancelled' then
    v_new_status := 'cancelled';
  elsif v_invoice.status = 'received' or v_invoice.received_date is not null then
    v_new_status := 'received';
  elsif v_invoice.status IN ('draft', 'sent') then
    v_new_status := v_invoice.status;
  elsif v_balance = 0 and v_total > 0 then
    v_new_status := 'paid';
  elsif v_total > 0 and v_balance > 0 then
    v_new_status := 'confirmed';
  else
    v_new_status := case
      when v_invoice.status = 'paid' then 'confirmed'
      else v_invoice.status
    end;
  end if;

  update public.purchase_invoices
     set paid_amount = v_total,
         balance = v_balance,
         status = v_new_status,
         updated_at = now()
   where id = p_invoice_id;
end;
$$ language plpgsql;


create or replace function public.delete_purchase_payment_journal_entry(
  p_payment_id uuid,
  p_invoice_id uuid,
  p_tenant_id uuid,
  p_expected_amount numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_number text;
  v_id_journal_count integer;
  v_legacy_journal_count integer;
  v_matching_legacy_count integer;
begin
  if p_payment_id is null then
    return;
  end if;

  select count(*)::integer
    into v_id_journal_count
    from public.journal_entries entry
   where entry.tenant_id = p_tenant_id
     and entry.source_module = 'purchase_payments'
     and entry.source_reference = p_payment_id::text;

  if v_id_journal_count > 1 then
    raise exception 'Payment % has % current journal entries', p_payment_id, v_id_journal_count
      using errcode = 'check_violation';
  elsif v_id_journal_count = 1 then
    delete from public.journal_entries entry
     where entry.tenant_id = p_tenant_id
       and entry.source_module = 'purchase_payments'
       and entry.source_reference = p_payment_id::text;
    return;
  end if;

  select invoice.invoice_number
    into v_invoice_number
    from public.purchase_invoices invoice
   where invoice.id = p_invoice_id
     and invoice.tenant_id = p_tenant_id;

  if v_invoice_number is null then
    return;
  end if;

  select
    count(*)::integer,
    count(*) filter (
      where public.clp_round(entry.total_debit)
            = public.clp_round(p_expected_amount)
        and public.clp_round(entry.total_credit)
            = public.clp_round(p_expected_amount)
    )::integer
    into v_legacy_journal_count, v_matching_legacy_count
    from public.journal_entries entry
   where entry.tenant_id = p_tenant_id
     and entry.source_module = 'purchase_payments'
     and entry.source_reference = v_invoice_number;

  if v_legacy_journal_count = 0 then
    return;
  end if;

  if v_legacy_journal_count <> 1 or v_matching_legacy_count <> 1 then
    raise exception
      'Legacy payment journals for invoice % are ambiguous (journals %, matching amount %); payment edit/undo stopped for audit review',
      v_invoice_number, v_legacy_journal_count, v_matching_legacy_count
      using errcode = 'check_violation';
  end if;

  delete from public.journal_entries entry
   where entry.tenant_id = p_tenant_id
     and entry.source_module = 'purchase_payments'
     and entry.source_reference = v_invoice_number;
end;
$$;

create or replace function public.handle_purchase_payment_change()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    perform public.create_purchase_payment_journal_entry(NEW.id);
    perform public.recalculate_purchase_invoice_payments(NEW.invoice_id);
  elsif TG_OP = 'UPDATE' then
    if NEW.invoice_id is distinct from OLD.invoice_id then
      perform public.recalculate_purchase_invoice_payments(OLD.invoice_id);
    end if;
    perform public.delete_purchase_payment_journal_entry(
      OLD.id, OLD.invoice_id, OLD.tenant_id, OLD.amount
    );
    perform public.create_purchase_payment_journal_entry(NEW.id);
    perform public.recalculate_purchase_invoice_payments(NEW.invoice_id);
  elsif TG_OP = 'DELETE' then
    perform public.delete_purchase_payment_journal_entry(
      OLD.id, OLD.invoice_id, OLD.tenant_id, OLD.amount
    );
    perform public.recalculate_purchase_invoice_payments(OLD.invoice_id);
  end if;
  return NULL;
end;
$$ language plpgsql;

create or replace function public.inventory_trace_payment_snapshot(p_row jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', p_row->'id',
    'invoice_id', p_row->'invoice_id',
    'payment_method_id', p_row->'payment_method_id',
    'amount', p_row->'amount',
    'date', p_row->'date',
    'reference', p_row->'reference',
    'idempotency_key', p_row->'idempotency_key',
    'deleted_at', p_row->'deleted_at',
    'deleted_by', p_row->'deleted_by',
    'created_at', p_row->'created_at',
    'updated_at', p_row->'updated_at'
  ));
$$;

create or replace function public.begin_invoice_payment_trace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_row jsonb;
  v_new_row jsonb;
  v_effective_row jsonb;
  v_payment_before jsonb;
  v_payment_after jsonb;
  v_invoice_before jsonb;
  v_operation_id uuid;
  v_operation_key text;
  v_tenant_id uuid;
  v_payment_id uuid;
  v_invoice_id uuid;
  v_document_type text;
  v_invoice_type text;
  v_source_channel text;
begin
  if TG_OP = 'INSERT' then
    v_new_row := to_jsonb(NEW);
    v_effective_row := v_new_row;
  elsif TG_OP = 'UPDATE' then
    if NEW.invoice_id is distinct from OLD.invoice_id then
      raise exception 'A posted payment cannot be reassigned to another invoice; reverse it and create a new payment'
        using errcode = 'check_violation';
    end if;
    v_old_row := to_jsonb(OLD);
    v_new_row := to_jsonb(NEW);
    v_effective_row := v_new_row;
  else
    v_old_row := to_jsonb(OLD);
    v_effective_row := v_old_row;
  end if;

  v_tenant_id := nullif(v_effective_row->>'tenant_id', '')::uuid;
  v_payment_id := nullif(v_effective_row->>'id', '')::uuid;
  v_invoice_id := nullif(v_effective_row->>'invoice_id', '')::uuid;

  if v_tenant_id is null or v_payment_id is null or v_invoice_id is null then
    raise exception 'Payment trace requires tenant_id, payment id, and invoice_id';
  end if;

  if TG_TABLE_NAME = 'sales_payments' then
    v_document_type := 'sales_payment';
    v_invoice_type := 'sales_invoice';
    select
      coalesce(nullif(invoice.source, ''), 'manual_sale') || '_payment',
      public.inventory_trace_document_snapshot(to_jsonb(invoice))
      into v_source_channel, v_invoice_before
      from sales_invoices invoice
     where invoice.id = v_invoice_id
       and invoice.tenant_id = v_tenant_id;
  elsif TG_TABLE_NAME = 'purchase_payments' then
    v_document_type := 'purchase_payment';
    v_invoice_type := 'purchase_invoice';
    v_source_channel := 'purchase_payment';
    select public.inventory_trace_document_snapshot(to_jsonb(invoice))
      into v_invoice_before
      from purchase_invoices invoice
     where invoice.id = v_invoice_id
       and invoice.tenant_id = v_tenant_id;
  else
    raise exception 'Unsupported payment trace source table: %', TG_TABLE_NAME;
  end if;

  if v_invoice_before is null then
    raise exception 'Payment invoice % does not belong to tenant %', v_invoice_id, v_tenant_id
      using errcode = 'foreign_key_violation';
  end if;

  v_payment_before := case
    when v_old_row is null then null
    else public.inventory_trace_payment_snapshot(v_old_row)
  end;
  v_payment_after := case
    when v_new_row is null then null
    else public.inventory_trace_payment_snapshot(v_new_row)
  end;
  v_operation_key := format(
    '%s:%s:%s:%s',
    v_document_type,
    v_payment_id,
    lower(TG_OP),
    coalesce(
      nullif(current_setting('app.inventory_idempotency_key', true), ''),
      gen_random_uuid()::text
    )
  );

  insert into inventory_accounting_operations (
    tenant_id,
    operation_key,
    source_channel,
    action,
    document_type,
    document_id,
    actor_id,
    executor,
    before_snapshot,
    after_snapshot,
    context
  ) values (
    v_tenant_id,
    v_operation_key,
    v_source_channel,
    lower(TG_OP),
    v_document_type,
    v_payment_id,
    auth.uid(),
    'database_trigger',
    v_payment_before,
    v_payment_after,
    jsonb_build_object(
      'table', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
      'invoice_type', v_invoice_type,
      'invoice_id', v_invoice_id,
      'invoice_before', v_invoice_before,
      'transaction_id', txid_current()::text
    )
  )
  returning id into v_operation_id;

  perform set_config('app.inventory_operation_id', v_operation_id::text, true);
  perform set_config('app.inventory_source_document_type', v_document_type, true);
  perform set_config('app.inventory_source_document_id', v_payment_id::text, true);
  perform set_config('app.inventory_source_channel', v_source_channel, true);

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'accepted',
    'started',
    v_document_type,
    v_payment_id,
    jsonb_build_object(
      'action', lower(TG_OP),
      'invoice_type', v_invoice_type,
      'invoice_id', v_invoice_id
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'source_snapshotted',
    'completed',
    v_document_type,
    v_payment_id,
    jsonb_build_object(
      'payment_before', v_payment_before,
      'payment_after', v_payment_after,
      'invoice_before', v_invoice_before
    )
  );

  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

create or replace function public.complete_invoice_payment_trace()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_operation_text text;
  v_operation_id uuid;
  v_tenant_id uuid;
  v_payment_id uuid;
  v_invoice_id uuid;
  v_document_type text;
  v_invoice_type text;
  v_invoice_after jsonb;
  v_invoice_total numeric;
  v_invoice_paid numeric;
  v_invoice_balance numeric;
  v_invoice_status text;
  v_received_date timestamp with time zone;
  v_ledger_paid numeric;
  v_expected_balance numeric;
  v_payment_active boolean;
  v_payment_journal_count integer;
  v_stock_movement_count integer;
  v_job_paid_mismatch integer := 0;
begin
  v_operation_text := nullif(current_setting('app.inventory_operation_id', true), '');
  if v_operation_text is null then
    return case when TG_OP = 'DELETE' then OLD else NEW end;
  end if;

  v_operation_id := v_operation_text::uuid;
  v_tenant_id := case when TG_OP = 'DELETE' then OLD.tenant_id else NEW.tenant_id end;
  v_payment_id := case when TG_OP = 'DELETE' then OLD.id else NEW.id end;
  v_invoice_id := case when TG_OP = 'DELETE' then OLD.invoice_id else NEW.invoice_id end;
  v_payment_active := TG_OP <> 'DELETE' and NEW.deleted_at is null;

  if TG_TABLE_NAME = 'sales_payments' then
    v_document_type := 'sales_payment';
    v_invoice_type := 'sales_invoice';
    select
      public.inventory_trace_document_snapshot(to_jsonb(invoice)),
      public.clp_round(invoice.total),
      public.clp_round(invoice.paid_amount),
      public.clp_round(invoice.balance),
      invoice.status,
      null::timestamp with time zone
      into v_invoice_after, v_invoice_total, v_invoice_paid,
           v_invoice_balance, v_invoice_status, v_received_date
      from sales_invoices invoice
     where invoice.id = v_invoice_id and invoice.tenant_id = v_tenant_id;

    select public.clp_round(coalesce(sum(payment.amount), 0))
      into v_ledger_paid
      from sales_payments payment
     where payment.invoice_id = v_invoice_id
       and payment.tenant_id = v_tenant_id
       and payment.deleted_at is null;

    select count(*)::integer
      into v_job_paid_mismatch
      from mechanic_jobs job
     where job.tenant_id = v_tenant_id
       and job.invoice_id = v_invoice_id
       and job.is_paid is distinct from (lower(v_invoice_status) = 'paid');
  else
    v_document_type := 'purchase_payment';
    v_invoice_type := 'purchase_invoice';
    select
      public.inventory_trace_document_snapshot(to_jsonb(invoice)),
      public.clp_round(invoice.total),
      public.clp_round(invoice.paid_amount),
      public.clp_round(invoice.balance),
      invoice.status,
      invoice.received_date
      into v_invoice_after, v_invoice_total, v_invoice_paid,
           v_invoice_balance, v_invoice_status, v_received_date
      from purchase_invoices invoice
     where invoice.id = v_invoice_id and invoice.tenant_id = v_tenant_id;

    select public.clp_round(coalesce(sum(payment.amount), 0))
      into v_ledger_paid
      from purchase_payments payment
     where payment.invoice_id = v_invoice_id
       and payment.tenant_id = v_tenant_id
       and payment.deleted_at is null;
  end if;

  if v_invoice_after is null then
    raise exception 'Payment trace could not reload related invoice %', v_invoice_id;
  end if;

  v_expected_balance := greatest(v_invoice_total - v_ledger_paid, 0);

  select count(*)::integer
    into v_payment_journal_count
    from journal_entries entry
   where entry.tenant_id = v_tenant_id
     and entry.source_module = TG_TABLE_NAME
     and entry.source_reference = v_payment_id::text;

  select count(*)::integer
    into v_stock_movement_count
    from stock_movements movement
   where movement.tenant_id = v_tenant_id
     and movement.operation_id = v_operation_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'source_snapshotted',
    'completed',
    v_invoice_type,
    v_invoice_id,
    jsonb_build_object(
      'invoice_before', (
        select operation.context->'invoice_before'
          from inventory_accounting_operations operation
         where operation.id = v_operation_id
      ),
      'invoice_after', v_invoice_after
    )
  );

  if v_invoice_paid <> v_ledger_paid
     or v_invoice_balance <> v_expected_balance
     or v_stock_movement_count <> 0
     or v_payment_journal_count <> (case when v_payment_active then 1 else 0 end)
     or v_job_paid_mismatch <> 0
     or (v_invoice_type = 'purchase_invoice'
         and v_received_date is not null
         and v_invoice_status <> 'received') then
    raise exception
      'Payment invariants failed for operation % (ledger %, invoice paid %, balance %, expected %, movements %, journals %, job mismatch %, status %)',
      v_operation_id, v_ledger_paid, v_invoice_paid, v_invoice_balance,
      v_expected_balance, v_stock_movement_count, v_payment_journal_count,
      v_job_paid_mismatch, v_invoice_status
      using errcode = 'check_violation';
  end if;

  perform public.complete_inventory_accounting_operation(
    v_operation_id,
    v_tenant_id,
    jsonb_build_object(
      'payment_id', v_payment_id,
      'payment_active', v_payment_active,
      'invoice_type', v_invoice_type,
      'invoice_id', v_invoice_id,
      'ledger_paid', v_ledger_paid,
      'invoice_balance', v_invoice_balance,
      'invoice_status', v_invoice_status,
      'stock_movement_count', v_stock_movement_count,
      'payment_journal_count', v_payment_journal_count,
      'job_paid_mismatch', v_job_paid_mismatch
    )
  );

  perform set_config('app.inventory_operation_id', '', true);
  perform set_config('app.inventory_source_document_type', '', true);
  perform set_config('app.inventory_source_document_id', '', true);
  perform set_config('app.inventory_source_channel', '', true);
  return case when TG_OP = 'DELETE' then OLD else NEW end;
exception
  when others then
    perform set_config('app.inventory_operation_id', '', true);
    perform set_config('app.inventory_source_document_type', '', true);
    perform set_config('app.inventory_source_document_id', '', true);
    perform set_config('app.inventory_source_channel', '', true);
    raise;
end;
$$;

drop trigger if exists zz_inventory_trace_begin_sales_payment on sales_payments;
create trigger zz_inventory_trace_begin_sales_payment
  before insert or update or delete on sales_payments
  for each row execute function public.begin_invoice_payment_trace();

drop trigger if exists zzz_inventory_trace_complete_sales_payment on sales_payments;
create trigger zzz_inventory_trace_complete_sales_payment
  after insert or update or delete on sales_payments
  for each row execute function public.complete_invoice_payment_trace();

drop trigger if exists zz_inventory_trace_begin_purchase_payment on purchase_payments;
create trigger zz_inventory_trace_begin_purchase_payment
  before insert or update or delete on purchase_payments
  for each row execute function public.begin_invoice_payment_trace();

drop trigger if exists zzz_inventory_trace_complete_purchase_payment on purchase_payments;
create trigger zzz_inventory_trace_complete_purchase_payment
  after insert or update or delete on purchase_payments
  for each row execute function public.complete_invoice_payment_trace();

commit;
