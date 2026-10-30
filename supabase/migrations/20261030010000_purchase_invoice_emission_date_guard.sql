-- 20261030010000: a purchase document cannot carry an impossible emission
-- date, and a posted purchase keeps its journal entry on its own date.
--
-- 2026-10-29: TeknoBike 142770 (entered 2026-07-23) and 143739 (applied
-- 2026-09-04) were saved with 22-08-2014. That is the SII resolution date
-- every electronic invoice prints («Res. 80 del 22-08-2014»); the invoice
-- reader returned it as the emission date, the form copied it without a
-- check, and two different people saved it. Both purchases, their VAT credit
-- and their payables sat in 2014 for three months until the owner found them
-- reviewing tyre costs. Owner (2026-10-02): the system validates the human,
-- not the other way around.
--
-- What changes:
-- 1. purchase_document_date_problem(tenant, date) says, in Spanish, why an
--    emission date cannot be right: after tomorrow, or before January 1 of
--    last year, in the tenant's timezone. The window keeps the AliExpress
--    backfills (up to 11 months old when they were entered) and refuses a
--    date from another decade.
-- 2. guard_purchase_invoice_emission_date applies it when a purchase invoice
--    is created or its date (or supplier_invoice_date) moves to another day.
--    Stored rows and updates that keep the day are not judged again, and the
--    supplier-foundation restore keeps its exemption, like every other
--    invoice trigger.
-- 3. handle_purchase_invoice_change: a posted invoice (confirmed, received,
--    paid) whose day changes with the same amounts moves its own purchase
--    journal entry to that day, keeping the entry's number and lines. Until
--    now only an amount change reposted it, so a corrected date left the
--    entry in the old period: the two 2014 entries were moved by hand on
--    2026-10-29. Payments and their entries are not touched.
--
-- The rest of handle_purchase_invoice_change is the production body as of
-- 2026-10-29, unchanged.

create or replace function public.purchase_document_date_problem(
  p_tenant_id uuid,
  p_date timestamptz
)
returns text
language plpgsql
stable
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_timezone text;
  v_today date;
  v_day date;
  v_earliest date;
begin
  if p_date is null then
    return null;
  end if;

  select coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago')
    into v_timezone
    from public.tenants tenant
   where tenant.id = p_tenant_id;
  v_timezone := coalesce(v_timezone, 'America/Santiago');

  v_today := (statement_timestamp() at time zone v_timezone)::date;
  v_day := (p_date at time zone v_timezone)::date;
  v_earliest := make_date(extract(year from v_today)::integer - 1, 1, 1);

  if v_day > v_today + 1 then
    return format(
      'La fecha de emisión %s es posterior a hoy (%s). Revisa la fecha en el documento.',
      to_char(v_day, 'DD/MM/YYYY'),
      to_char(v_today, 'DD/MM/YYYY')
    );
  end if;

  if v_day < v_earliest then
    return format(
      'La fecha de emisión %s no puede ser: una compra se registra con fecha de este año o del anterior (desde el %s).%s',
      to_char(v_day, 'DD/MM/YYYY'),
      to_char(v_earliest, 'DD/MM/YYYY'),
      case
        when v_day = date '2014-08-22' then
          ' El 22-08-2014 es la resolución del SII que traen impresa las facturas electrónicas («Res. 80»); la emisión está junto a «Fecha Emisión».'
        else
          ' Revisa la fecha en el documento.'
      end
    );
  end if;

  return null;
end;
$$;

revoke all on function public.purchase_document_date_problem(uuid, timestamptz)
  from public, anon, authenticated, service_role;

create or replace function public.guard_purchase_invoice_emission_date()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_timezone text;
  v_problem text;
begin
  select coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago')
    into v_timezone
    from public.tenants tenant
   where tenant.id = new.tenant_id;
  v_timezone := coalesce(v_timezone, 'America/Santiago');

  if tg_op = 'INSERT' then
    v_problem := public.purchase_document_date_problem(new.tenant_id, new.date);
    if v_problem is null then
      v_problem := public.purchase_document_date_problem(
        new.tenant_id,
        new.supplier_invoice_date
      );
    end if;
  else
    if (new.date at time zone v_timezone)::date
         is distinct from (old.date at time zone v_timezone)::date then
      v_problem := public.purchase_document_date_problem(new.tenant_id, new.date);
    end if;
    if v_problem is null
       and (new.supplier_invoice_date at time zone v_timezone)::date
         is distinct from (old.supplier_invoice_date at time zone v_timezone)::date then
      v_problem := public.purchase_document_date_problem(
        new.tenant_id,
        new.supplier_invoice_date
      );
    end if;
  end if;

  if v_problem is not null then
    raise exception '%', v_problem
      using errcode = '22023',
            hint = 'purchase_document_date_implausible';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_purchase_invoice_emission_date()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_guard_purchase_invoice_emission_date
  on public.purchase_invoices;
create trigger trg_guard_purchase_invoice_emission_date
  before insert or update of date, supplier_invoice_date
  on public.purchase_invoices
  for each row
  when (not public.supplier_foundation_invoice_rehydrate_is_active(new.tenant_id))
  execute function public.guard_purchase_invoice_emission_date();

CREATE OR REPLACE FUNCTION public.handle_purchase_invoice_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_old_status text;
  v_new_status text;
  v_timezone text;
  v_new_day date;
begin
  raise notice 'handle_purchase_invoice_change: TG_OP=%', TG_OP;

  if TG_OP = 'INSERT' then
    v_new_status := NEW.status;
    raise notice 'handle_purchase_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;

    -- Inventory: ONLY if inserted directly as 'received' (rare case)
    if v_new_status = 'received' then
      raise notice 'handle_purchase_invoice_change: INSERT at received, consuming inventory';
      perform public.consume_purchase_invoice_inventory(NEW);
    end if;

    -- Journal: If inserted at 'confirmed' or later
    if v_new_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: INSERT at confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);
    end if;

    perform public.recalculate_purchase_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := OLD.status;
    v_new_status := NEW.status;

    raise notice 'handle_purchase_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    -- INVENTORY HANDLING: ONLY at 'received' status
    -- Different logic for standard vs prepayment models:
    --
    -- STANDARD MODEL: Draft→Confirmed→RECEIVED→Paid
    --   Inventory added at 'received', stays through 'paid'
    --   So: received<->paid transitions do NOT change inventory
    --
    -- PREPAYMENT MODEL: Draft→Confirmed→Paid→RECEIVED
    --   Inventory added at 'received' (after payment)
    --   So: received<->paid transitions DO change inventory

    if NEW.prepayment_model then
      -- PREPAYMENT MODEL: Inventory changes whenever entering/leaving 'received'
      if v_old_status != 'received' AND v_new_status = 'received' then
        -- Transitioning TO received (from any status): add inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning TO received from %, consuming inventory', v_old_status;
        perform public.consume_purchase_invoice_inventory(NEW);

      elsif v_old_status = 'received' AND v_new_status != 'received' then
        -- Transitioning FROM received (to any status): remove inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning FROM received to %, restoring inventory', v_new_status;
        perform public.restore_purchase_invoice_inventory(OLD);

      elsif v_old_status = 'received' AND v_new_status = 'received' then
        -- Only physical item changes may replace the received stock snapshot.
        if public.invoice_inventory_signature(OLD.items)
             is distinct from public.invoice_inventory_signature(NEW.items) then
          raise notice 'handle_purchase_invoice_change: [PREPAYMENT] received items changed, updating inventory';
          perform public.restore_purchase_invoice_inventory(OLD);
          perform public.consume_purchase_invoice_inventory(NEW);
        else
          raise notice 'handle_purchase_invoice_change: [PREPAYMENT] received without item changes, no inventory change';
        end if;
      end if;

    else
      -- STANDARD MODEL: Inventory changes only when entering/leaving 'received' from/to non-paid statuses
      if v_old_status <> 'received' AND v_new_status = 'received' then
        -- Transitioning TO received from confirmed/sent/draft: add inventory
        raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning TO received from %, consuming inventory', v_old_status;
        perform public.consume_purchase_invoice_inventory(NEW);

      elsif v_old_status = 'received' AND v_new_status NOT IN ('received', 'paid') then
        -- Transitioning FROM received to confirmed/sent/draft: remove inventory
        -- Note: received→paid does NOT remove (goods stay in standard flow)
        raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning FROM received to %, restoring inventory', v_new_status;
        perform public.restore_purchase_invoice_inventory(OLD);

      elsif v_old_status = 'received' AND v_new_status = 'received' then
        -- Only physical item changes may replace the received stock snapshot.
        if public.invoice_inventory_signature(OLD.items)
             is distinct from public.invoice_inventory_signature(NEW.items) then
          raise notice 'handle_purchase_invoice_change: [STANDARD] received items changed, updating inventory';
          perform public.restore_purchase_invoice_inventory(OLD);
          perform public.consume_purchase_invoice_inventory(NEW);
        else
          raise notice 'handle_purchase_invoice_change: [STANDARD] received without item changes, no inventory change';
        end if;
      end if;
    end if;

    -- JOURNAL ENTRY HANDLING: Create ONCE at 'confirmed', delete when reverting
    -- The journal entry represents the purchase transaction (Dr Inventory / Cr Accounts Payable)
    -- It should NOT be recreated when moving between confirmed→received→paid
    -- It should ONLY be recreated if staying at same status but amounts changed

    if v_old_status IN ('draft', 'sent', 'cancelled') AND v_new_status IN ('confirmed', 'received', 'paid') then
      -- Transitioning TO confirmed/received/paid: create journal entry
      raise notice 'handle_purchase_invoice_change: transitioning TO confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);

    elsif v_old_status IN ('confirmed', 'received', 'paid') AND v_new_status IN ('draft', 'sent', 'cancelled') then
      -- Transitioning FROM confirmed/received/paid to draft/sent/cancelled: delete journal entry
      raise notice 'handle_purchase_invoice_change: transitioning FROM confirmed/received/paid, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);

    elsif v_old_status = v_new_status AND v_old_status IN ('confirmed', 'received', 'paid') then
      -- Staying at same confirmed+ status but invoice data might have changed
      -- Only recreate journal if amounts changed (not just status transition)
      if OLD.subtotal IS DISTINCT FROM NEW.subtotal OR
         OLD.tax IS DISTINCT FROM NEW.tax OR
         OLD.total IS DISTINCT FROM NEW.total OR
         OLD.supplier_id IS DISTINCT FROM NEW.supplier_id then
        raise notice 'handle_purchase_invoice_change: amounts changed at same status, recreating journal entry';
        perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);
        perform public.create_purchase_invoice_journal_entry(NEW);
      elsif OLD.date IS DISTINCT FROM NEW.date then
        -- The entry belongs to the document: a corrected emission date moves
        -- it to that day, keeping its number and lines (2026-10-30).
        select coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago')
          into v_timezone
          from public.tenants tenant
         where tenant.id = NEW.tenant_id;
        v_new_day := (NEW.date at time zone coalesce(v_timezone, 'America/Santiago'))::date;

        update public.journal_entries entry
           set entry_date = v_new_day
         where entry.tenant_id = NEW.tenant_id
           and entry.source_module = 'purchase_invoices'
           and (
             entry.source_document_id = NEW.id
             or (
               entry.source_document_id is null
               and entry.source_reference = OLD.invoice_number
             )
           )
           and entry.entry_date is distinct from v_new_day;
      end if;
    end if;

    -- Only recalculate if this is NOT a payment-only update (prevents infinite recursion)
    -- If only paid_amount, balance, or status changed → skip recalculate (it's from recalculate itself)
    -- If items, total, subtotal, tax, or other fields changed → call recalculate
    if OLD.items IS DISTINCT FROM NEW.items OR
       OLD.subtotal IS DISTINCT FROM NEW.subtotal OR
       OLD.tax IS DISTINCT FROM NEW.tax OR
       OLD.total IS DISTINCT FROM NEW.total OR
       OLD.supplier_id IS DISTINCT FROM NEW.supplier_id OR
       OLD.prepayment_model IS DISTINCT FROM NEW.prepayment_model then
      raise notice 'handle_purchase_invoice_change: invoice data changed, recalculating payments';
      perform public.recalculate_purchase_invoice_payments(NEW.id);
    else
      raise notice 'handle_purchase_invoice_change: only payment fields changed, skipping recalculate to avoid recursion';
    end if;

    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := OLD.status;
    raise notice 'handle_purchase_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;

    -- Restore inventory if was received
    if v_old_status = 'received' then
      raise notice 'handle_purchase_invoice_change: deleting received invoice, restoring inventory';
      perform public.restore_purchase_invoice_inventory(OLD);
    end if;

    -- Delete journal entry if was confirmed or later
    if v_old_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: deleting confirmed/received/paid invoice, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.invoice_number);
    end if;

    return OLD;
  end if;

  return NULL;
end;
$function$;
