-- DETECTIVE SCRIPT: Find the Owner of the Mystery UUID
-- We are looking for the UUID: 2599b075-3944-4695-98b7-cde115da4cb9
-- This ID appears in the "Reference" column of a "Manual" adjustment.

do $$
declare
  v_target_id uuid := '2599b075-3944-4695-98b7-cde115da4cb9';
  v_found boolean := false;
  v_rec record;
begin
  raise notice '🔍 Hunting for UUID: %', v_target_id;

  -- 1. Check Purchase Invoices
  select * into v_rec from purchase_invoices where id = v_target_id;
  if found then
    raise notice '✅ FOUND in [purchase_invoices]!';
    raise notice '   Invoice #: %, Status: %', v_rec.invoice_number, v_rec.status;
    v_found := true;
  end if;

  -- 2. Check Sales Invoices
  select * into v_rec from sales_invoices where id = v_target_id;
  if found then
    raise notice '✅ FOUND in [sales_invoices]!';
    raise notice '   Invoice #: %, Status: %', v_rec.invoice_number, v_rec.status;
    v_found := true;
  end if;

  -- 3. Check Mechanic Jobs (Talleres) - Assuming table name 'mechanic_jobs' or 'jobs'
  --    (Trying 'mechanic_jobs' first based on modules list)
  begin
    execute 'select * from mechanic_jobs where id = $1' into v_rec using v_target_id;
    if v_rec is not null then
      raise notice '✅ FOUND in [mechanic_jobs]!';
      raise notice '   Job details: %', v_rec;
      v_found := true;
    end if;
  exception when undefined_table then
    raise notice '⚠️ Table mechanic_jobs does not exist, skipping...';
  end;

  -- 4. Check Work Orders / Tickets?
  begin
    execute 'select * from flow_tickets where id = $1' into v_rec using v_target_id;
     if v_rec is not null then
      raise notice '✅ FOUND in [flow_tickets]!';
      v_found := true;
    end if;
  exception when undefined_table then null; end;

  -- 5. Check Users? (Unlikely but possible)
  if not v_found then
    select * into v_rec from auth.users where id = v_target_id;
    if found then
      raise notice '✅ FOUND in [auth.users] (It is a User ID!)';
      v_found := true;
    end if;
  end if;

  if not v_found then
    raise notice '❌ UUID not found in any common table (Purchase, Sales, Mechanic, Users).';
  end if;

end $$;
