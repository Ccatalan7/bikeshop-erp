-- =============================================================================
-- FIX: Quick Sale journal entry not being created
-- =============================================================================
-- ROOT CAUSE: The deployed handle_sales_invoice_change trigger is an older version
--   that only handles UPDATE sent→confirmed, confirmed→sent, confirmed→confirmed.
--   It does NOT handle the draft→confirmed transition.
--   Our quick-sale flow: INSERT as draft → UPDATE to confirmed → the old trigger
--   ignores the draft→confirmed UPDATE, so no invoice JE is created.
-- 
-- FIX:
--   1. Redeploy handle_sales_invoice_change with full v_non_posted array logic
--      (handles draft→confirmed, paid, and all edge cases correctly)
--   2. Add ensure_sales_invoice_journal_entry(p_invoice_id) wrapper RPC so
--      the Dart code can call it as a reliable safety net after confirming.
--      It is idempotent: if JE already exists (trigger worked), it's a no-op.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 1: Idempotent wrapper RPC called from Dart after updateInvoiceStatus
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.ensure_sales_invoice_journal_entry(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.sales_invoices%rowtype;
begin
  if p_invoice_id is null then
    return;
  end if;

  select * into v_invoice
    from public.sales_invoices
   where id = p_invoice_id;

  if not found then
    raise notice 'ensure_sales_invoice_journal_entry: invoice % not found', p_invoice_id;
    return;
  end if;

  -- create_sales_invoice_journal_entry already checks for duplicate JE internally,
  -- so calling this multiple times is safe (idempotent).
  perform public.create_sales_invoice_journal_entry(v_invoice);
end;
$$;

grant execute on function public.ensure_sales_invoice_journal_entry(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 2: Redeploy handle_sales_invoice_change with current full logic
--   Handles: draft→confirmed, sent→confirmed, both-posted, posted→draft, etc.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.handle_sales_invoice_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_non_posted constant text[] := array[
    'draft','borrador',
    'sent','enviado','enviada','issued','emitido','emitida',
    'cancelled','cancelado','cancelada','anulado','anulada'
  ];
  v_old_status text;
  v_new_status text;
  v_old_posted boolean;
  v_new_posted boolean;
begin
  raise notice 'handle_sales_invoice_change: TG_OP=%', TG_OP;

  -- 🔄 CIRCULAR SYNC GUARD: Skip if already syncing in either direction
  if current_setting('app.syncing_job_to_invoice', true) = 'true' or
     current_setting('app.syncing_invoice_to_job', true) = 'true' then
    raise notice 'handle_sales_invoice_change: skipping due to active sync';
    if TG_OP = 'DELETE' then return OLD; end if;
    return NEW;
  end if;

  -- Prevent infinite recursion
  if pg_trigger_depth() > 1 then
    raise notice 'handle_sales_invoice_change: trigger depth > 1, returning';
    if TG_OP = 'DELETE' then
      return OLD;
    else
      return NEW;
    end if;
  end if;

  if TG_OP = 'INSERT' then
    v_new_status := lower(coalesce(NEW.status, 'draft'));
    raise notice 'handle_sales_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;

    -- Only process if status is "confirmed" or "paid" (NOT "draft" or "sent")
    if not (v_new_status = any (v_non_posted)) then
      raise notice 'handle_sales_invoice_change: INSERT with posted status, consuming inventory';
      perform public.consume_sales_invoice_inventory(NEW);
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      raise notice 'handle_sales_invoice_change: INSERT with non-posted status (%), skipping', v_new_status;
    end if;

    perform public.recalculate_sales_invoice_payments(NEW.id);
    -- SYNC: Update linked pega with invoice data
    perform public.sync_invoice_items_to_job(NEW.id);
    perform public.sync_invoice_status_to_job(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    v_new_status := lower(coalesce(NEW.status, 'draft'));

    raise notice 'handle_sales_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    v_old_posted := not (v_old_status = any (v_non_posted));
    v_new_posted := not (v_new_status = any (v_non_posted));

    -- Handle inventory changes based on status transition
    if v_old_posted and v_new_posted then
      raise notice 'handle_sales_invoice_change: both posted, restore and consume';
      perform public.restore_sales_invoice_inventory(OLD);
      perform public.consume_sales_invoice_inventory(NEW);
    elsif v_old_posted and not v_new_posted then
      raise notice 'handle_sales_invoice_change: changed to non-posted, restore only';
      perform public.restore_sales_invoice_inventory(OLD);
    elsif not v_old_posted and v_new_posted then
      raise notice 'handle_sales_invoice_change: changed to posted, consume';
      perform public.consume_sales_invoice_inventory(NEW);
    else
      raise notice 'handle_sales_invoice_change: both non-posted, no inventory change';
    end if;

    -- JOURNAL ENTRY HANDLING (DELETE-based reversals, Zoho Books style)
    if v_old_posted and not v_new_posted then
      -- Confirmed/Paid → Draft/Sent: DELETE journal entry
      raise notice 'handle_sales_invoice_change: reverting to non-posted, deleting journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.invoice_number;

      -- Soft-delete associated payments
      raise notice 'handle_sales_invoice_change: reverting to non-posted, soft-deleting payments';
      update public.sales_payments
      set deleted_at = now()
      where invoice_id = OLD.id
        and deleted_at is null;

    elsif not v_old_posted and v_new_posted then
      -- Draft/Sent → Confirmed: CREATE journal entry
      raise notice 'handle_sales_invoice_change: changing to posted, creating journal entry';
      perform public.create_sales_invoice_journal_entry(NEW);

    elsif v_old_posted and v_new_posted then
      -- Both posted: delete old, create new (amounts might have changed)
      raise notice 'handle_sales_invoice_change: both posted, recreating journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.invoice_number;
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      raise notice 'handle_sales_invoice_change: both non-posted, no journal entry action';
    end if;

    perform public.recalculate_sales_invoice_payments(NEW.id);
    -- SYNC: Update linked pega with invoice changes
    perform public.sync_invoice_items_to_job(NEW.id);
    perform public.sync_invoice_status_to_job(NEW.id);
    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    raise notice '🔵 handle_sales_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;

    -- If was posted, restore inventory
    if not (v_old_status = any (v_non_posted)) then
      perform public.restore_sales_invoice_inventory(OLD);
    end if;

    -- DELETE invoice journal entry (using invoice_number as reference)
    delete from public.journal_entries
    where source_module = 'sales_invoices'
      and source_reference = OLD.invoice_number;

    -- DELETE all payment journal entries for this invoice
    delete from public.journal_entries
    where source_module = 'sales_payments'
      and source_reference = OLD.invoice_number;

    raise notice '🔵 handle_sales_invoice_change: DELETE completed, now cascade trigger should fire';
    return OLD;
  end if;

  return NULL;
end;
$$;

-- Re-attach trigger
drop trigger if exists trg_sales_invoices_change on public.sales_invoices;
create trigger trg_sales_invoices_change
  after insert or update or delete on public.sales_invoices
  for each row execute procedure public.handle_sales_invoice_change();

-- =============================================================================
-- PART 3: BACKFILL — Create missing JEs for ALL confirmed/paid sales invoices
-- =============================================================================
-- Root cause: old trigger didn't handle draft→confirmed UPDATE, so every invoice
-- saved via the normal form (draft→confirmed) has no invoice JE. This backfills them.
-- create_sales_invoice_journal_entry checks for duplicates internally, so this is
-- safe to run multiple times — it will only create JEs that don't exist yet.
-- =============================================================================
do $$
declare
  v_invoice public.sales_invoices%rowtype;
  v_count   integer := 0;
  v_skipped integer := 0;
begin
  for v_invoice in
    select si.*
      from public.sales_invoices si
     where lower(si.status) in ('confirmed','paid','pagado','pagada','confirmado','confirmada')
       and si.total > 0
       and not exists (
             select 1
               from public.journal_entries je
              where je.source_module = 'sales_invoices'
                and je.source_reference = si.invoice_number
                and je.tenant_id = si.tenant_id
           )
  loop
    begin
      perform public.create_sales_invoice_journal_entry(v_invoice);
      v_count := v_count + 1;
      raise notice 'Backfill: created JE for invoice % (status: %)', v_invoice.invoice_number, v_invoice.status;
    exception when others then
      v_skipped := v_skipped + 1;
      raise warning 'Backfill: failed for invoice % — %', v_invoice.invoice_number, sqlerrm;
    end;
  end loop;

  raise notice '============================================================';
  raise notice 'Backfill complete: % JEs created, % skipped/failed', v_count, v_skipped;
  raise notice '============================================================';
end $$;

-- =============================================================================
-- VERIFY: confirm JEs now exist for recent invoices
-- =============================================================================
select
  si.invoice_number,
  si.status,
  si.total,
  si.customer_name,
  je.entry_number  as invoice_je,
  pje.entry_number as latest_payment_je
from public.sales_invoices si
left join public.journal_entries je
       on je.source_module    = 'sales_invoices'
      and je.source_reference = si.invoice_number
      and je.tenant_id        = si.tenant_id
left join lateral (
  select entry_number
    from public.journal_entries pje2
   where pje2.source_module  = 'sales_payments'
     and pje2.tenant_id      = si.tenant_id
     and lower(pje2.description) like '%' || lower(si.invoice_number) || '%'
   order by pje2.created_at desc
   limit 1
) pje on true
where lower(si.status) in ('confirmed','paid','pagado','pagada','confirmado','confirmada')
order by si.created_at desc
limit 30;

-- ─────────────────────────────────────────────────────────────────────────────
-- VERIFY: Check trigger exists
-- ─────────────────────────────────────────────────────────────────────────────
select
  t.tgname as trigger_name,
  pg_get_triggerdef(t.oid) as trigger_definition
from pg_trigger t
join pg_class c on t.tgrelid = c.oid
where c.relname = 'sales_invoices'
  and not t.tgisinternal
order by t.tgname;
