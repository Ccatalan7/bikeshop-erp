-- Deployment status: DEPLOYED 2026-07-11. No tenant was activated by this migration.
-- Internal financial credit notes do not claim official Chilean DTE issuance.

begin;

alter table public.purchase_invoices
  add column if not exists credited_amount numeric(12,2) not null default 0,
  add column if not exists supplier_credit_balance numeric(12,2) not null default 0;

create table if not exists public.purchase_credit_note_control_settings (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  control_mode text not null default 'disabled'
    check (control_mode in ('disabled', 'shadow', 'enforce')),
  activated_at timestamp with time zone,
  activated_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.purchase_credit_notes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete restrict,
  credit_note_number text not null,
  supplier_credit_note_number text,
  status text not null default 'posted' check (status in ('posted', 'voided')),
  official_dte_status text not null default 'internal'
    check (official_dte_status in ('internal', 'pending', 'issued', 'rejected', 'cancelled')),
  issue_date timestamp with time zone not null,
  reason_code text not null,
  reason text not null,
  net_amount numeric(12,2) not null check (net_amount >= 0),
  tax_amount numeric(12,2) not null check (tax_amount >= 0),
  total_amount numeric(12,2) not null check (total_amount > 0),
  idempotency_key text not null,
  operation_id uuid not null,
  journal_entry_id uuid not null references public.journal_entries(id) on delete restrict,
  created_by uuid references auth.users(id),
  created_at timestamp with time zone not null default clock_timestamp(),
  void_operation_id uuid,
  void_journal_entry_id uuid references public.journal_entries(id) on delete restrict,
  void_idempotency_key text,
  voided_at timestamp with time zone,
  voided_by uuid references auth.users(id),
  void_reason text,
  unique (tenant_id, credit_note_number),
  unique (tenant_id, idempotency_key),
  unique (tenant_id, id),
  foreign key (tenant_id, operation_id)
    references public.inventory_accounting_operations(tenant_id, id) on delete restrict,
  check (total_amount = net_amount + tax_amount)
);

create unique index if not exists uq_purchase_credit_notes_void_idempotency
  on public.purchase_credit_notes(tenant_id, void_idempotency_key)
  where void_idempotency_key is not null;

create table if not exists public.purchase_credit_note_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_credit_note_id uuid not null,
  purchase_invoice_id uuid not null references public.purchase_invoices(id) on delete restrict,
  source_line_key text not null,
  source_line_index integer not null check (source_line_index >= 0),
  product_id uuid references public.products(id) on delete restrict,
  product_name text not null,
  product_sku text,
  purchase_treatment text not null check (purchase_treatment in ('inventory', 'workshop_consumable')),
  disposition text not null check (disposition in ('financial_only', 'supplier_return')),
  supplier_return_line_id uuid references public.purchase_supplier_return_lines(id) on delete restrict,
  credited_quantity integer not null default 0 check (credited_quantity >= 0),
  original_quantity integer not null check (original_quantity >= 0),
  original_allocated_net numeric(12,2) not null check (original_allocated_net >= 0),
  original_allocated_tax numeric(12,2) not null check (original_allocated_tax >= 0),
  net_amount numeric(12,2) not null check (net_amount >= 0),
  tax_amount numeric(12,2) not null check (tax_amount >= 0),
  total_amount numeric(12,2) not null check (total_amount > 0),
  line_snapshot jsonb not null,
  created_at timestamp with time zone not null default clock_timestamp(),
  unique (tenant_id, purchase_credit_note_id, source_line_key),
  foreign key (tenant_id, purchase_credit_note_id)
    references public.purchase_credit_notes(tenant_id, id) on delete restrict,
  check (total_amount = net_amount + tax_amount),
  check (
    (disposition = 'supplier_return' and supplier_return_line_id is not null and credited_quantity > 0)
    or (disposition = 'financial_only' and supplier_return_line_id is null)
  )
);

create index if not exists idx_purchase_credit_notes_invoice
  on public.purchase_credit_notes(tenant_id, purchase_invoice_id, created_at desc);
create index if not exists idx_purchase_credit_note_lines_source
  on public.purchase_credit_note_lines(tenant_id, purchase_invoice_id, source_line_key);

alter table public.purchase_credit_note_control_settings enable row level security;
alter table public.purchase_credit_notes enable row level security;
alter table public.purchase_credit_note_lines enable row level security;
drop policy if exists purchase_credit_note_settings_select on public.purchase_credit_note_control_settings;
create policy purchase_credit_note_settings_select on public.purchase_credit_note_control_settings
  for select to authenticated using (tenant_id = public.user_tenant_id());
drop policy if exists purchase_credit_notes_select on public.purchase_credit_notes;
create policy purchase_credit_notes_select on public.purchase_credit_notes
  for select to authenticated using (tenant_id = public.user_tenant_id());
drop policy if exists purchase_credit_note_lines_select on public.purchase_credit_note_lines;
create policy purchase_credit_note_lines_select on public.purchase_credit_note_lines
  for select to authenticated using (tenant_id = public.user_tenant_id());
revoke insert, update, delete on public.purchase_credit_note_control_settings from public, anon, authenticated;
revoke insert, update, delete on public.purchase_credit_notes from public, anon, authenticated;
revoke insert, update, delete on public.purchase_credit_note_lines from public, anon, authenticated;
grant select on public.purchase_credit_note_control_settings to authenticated;
grant select on public.purchase_credit_notes to authenticated;
grant select on public.purchase_credit_note_lines to authenticated;

create or replace view public.purchase_credit_note_line_balance_view
with (security_invoker = true)
as
with raw as (
  select invoice.id purchase_invoice_id, invoice.tenant_id,
         invoice.subtotal invoice_subtotal, invoice.tax invoice_tax,
         source.ordinality::integer - 1 source_line_index, source.item line_snapshot,
         coalesce(nullif(source.item->>'line_id',''), nullif(source.item->>'id',''),
           md5(invoice.id::text || ':' || (source.ordinality::integer - 1)::text || ':' || coalesce(source.item->>'product_id',''))) source_line_key,
         coalesce(nullif(source.item->>'quantity','')::numeric,0)::integer original_quantity,
         greatest(coalesce(nullif(source.item->>'quantity','')::numeric,0) * coalesce(nullif(source.item->>'unit_cost','')::numeric,0) - coalesce(nullif(source.item->>'discount','')::numeric,0),0) raw_net
  from public.purchase_invoices invoice
  cross join lateral jsonb_array_elements(invoice.items) with ordinality source(item,ordinality)
), base as (
  select raw.*, case when sum(raw_net) over(partition by purchase_invoice_id)>0
    then public.clp_round(raw_net/sum(raw_net) over(partition by purchase_invoice_id)*invoice_subtotal) else 0 end net_base
  from raw
), net_alloc as (
  select base.*, net_base + case when row_number() over(partition by purchase_invoice_id order by raw_net desc,source_line_index)=1
    then public.clp_round(invoice_subtotal-sum(net_base) over(partition by purchase_invoice_id)) else 0 end original_allocated_net
  from base
), tax_base as (
  select net_alloc.*, case when invoice_subtotal>0 then public.clp_round(original_allocated_net/invoice_subtotal*invoice_tax) else 0 end tax_pre
  from net_alloc
), allocations as (
  select tax_base.*, tax_pre + case when row_number() over(partition by purchase_invoice_id order by original_allocated_net desc,source_line_index)=1
    then public.clp_round(invoice_tax-sum(tax_pre) over(partition by purchase_invoice_id)) else 0 end original_allocated_tax
  from tax_base
), credits as (
  select line.tenant_id,line.purchase_invoice_id,line.source_line_key,
         coalesce(sum(line.credited_quantity),0)::integer credited_quantity,
         coalesce(sum(line.net_amount),0) credited_net,
         coalesce(sum(line.tax_amount),0) credited_tax
  from public.purchase_credit_note_lines line
  join public.purchase_credit_notes note on note.id=line.purchase_credit_note_id
  where note.status='posted'
  group by line.tenant_id,line.purchase_invoice_id,line.source_line_key
)
select allocation.tenant_id,allocation.purchase_invoice_id,allocation.source_line_index,
       allocation.source_line_key,nullif(allocation.line_snapshot->>'product_id','')::uuid product_id,
       coalesce(allocation.line_snapshot->>'product_name','Producto') product_name,
       allocation.line_snapshot->>'product_sku' product_sku,
       coalesce(nullif(allocation.line_snapshot->>'purchase_treatment',''),'inventory') purchase_treatment,
       allocation.original_quantity,allocation.original_allocated_net,allocation.original_allocated_tax,
       coalesce(credit.credited_quantity,0) credited_quantity,
       coalesce(credit.credited_net,0) credited_net,coalesce(credit.credited_tax,0) credited_tax,
       greatest(allocation.original_quantity-coalesce(credit.credited_quantity,0),0) remaining_quantity,
       greatest(allocation.original_allocated_net-coalesce(credit.credited_net,0),0) remaining_net,
       greatest(allocation.original_allocated_tax-coalesce(credit.credited_tax,0),0) remaining_tax,
       allocation.line_snapshot
from allocations allocation
left join credits credit on credit.tenant_id=allocation.tenant_id
 and credit.purchase_invoice_id=allocation.purchase_invoice_id
 and credit.source_line_key=allocation.source_line_key;
grant select on public.purchase_credit_note_line_balance_view to authenticated;

create or replace function public.recalculate_purchase_invoice_settlement(p_invoice_id uuid)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_invoice public.purchase_invoices%rowtype;
  v_paid numeric(12,2);
  v_credited numeric(12,2);
  v_effective_total numeric(12,2);
  v_balance numeric(12,2);
  v_supplier_credit numeric(12,2);
  v_status text;
begin
  select * into v_invoice from public.purchase_invoices
  where id = p_invoice_id for update;
  if not found then return; end if;

  select public.clp_round(coalesce(sum(amount), 0)) into v_paid
  from public.purchase_payments
  where invoice_id = p_invoice_id and deleted_at is null;
  select public.clp_round(coalesce(sum(total_amount), 0)) into v_credited
  from public.purchase_credit_notes
  where purchase_invoice_id = p_invoice_id and status = 'posted';

  v_effective_total := greatest(public.clp_round(v_invoice.total) - v_credited, 0);
  v_balance := greatest(v_effective_total - v_paid, 0);
  v_supplier_credit := greatest(v_paid - v_effective_total, 0);

  if v_invoice.status = 'cancelled' then v_status := 'cancelled';
  elsif v_invoice.status = 'received' or v_invoice.received_date is not null then v_status := 'received';
  elsif v_invoice.status in ('draft', 'sent') then v_status := v_invoice.status;
  elsif v_balance = 0 and v_paid > 0 then v_status := 'paid';
  elsif v_paid > 0 and v_balance > 0 then v_status := 'confirmed';
  else v_status := case when v_invoice.status = 'paid' then 'confirmed' else v_invoice.status end;
  end if;

  update public.purchase_invoices
  set paid_amount = v_paid, credited_amount = v_credited,
      balance = v_balance, supplier_credit_balance = v_supplier_credit,
      status = v_status, updated_at = now()
  where id = p_invoice_id;
end;
$$;

create or replace function public.recalculate_purchase_invoice_payments(p_invoice_id uuid)
returns void language plpgsql set search_path = public as $$
begin
  perform public.recalculate_purchase_invoice_settlement(p_invoice_id);
end;
$$;

create or replace function public.create_purchase_credit_note(
  p_purchase_invoice_id uuid,
  p_lines jsonb,
  p_issue_date timestamp with time zone,
  p_reason_code text,
  p_reason text,
  p_supplier_credit_note_number text default null,
  p_idempotency_key text default null
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_mode text := 'disabled';
  v_invoice public.purchase_invoices%rowtype;
  v_existing public.purchase_credit_notes%rowtype;
  v_note_id uuid := gen_random_uuid();
  v_operation_id uuid := gen_random_uuid();
  v_journal_id uuid := gen_random_uuid();
  v_note_number text;
  v_request jsonb;
  v_index integer;
  v_item jsonb;
  v_source_key text;
  v_product_id uuid;
  v_treatment text;
  v_disposition text;
  v_return_line_id uuid;
  v_return_line record;
  v_original_qty integer;
  v_credit_qty integer;
  v_allocated_net numeric(12,2);
  v_allocated_tax numeric(12,2);
  v_previous_qty integer;
  v_previous_net numeric(12,2);
  v_previous_tax numeric(12,2);
  v_credit_net numeric(12,2);
  v_credit_tax numeric(12,2);
  v_total_net numeric(12,2) := 0;
  v_total_tax numeric(12,2) := 0;
  v_inventory_net numeric(12,2) := 0;
  v_supplier_claim_net numeric(12,2) := 0;
  v_consumable_net numeric(12,2) := 0;
  v_return_previously_credited integer;
  v_inventory_account uuid;
  v_consumable_account uuid;
  v_tax_account uuid;
  v_payable_account uuid;
  v_supplier_claim_account uuid;
  v_description text;
begin
  if v_actor_id is null or v_tenant_id is null then raise exception 'Authenticated employee tenant is required'; end if;
  if p_issue_date is null then raise exception 'Purchase credit note issue date is required'; end if;
  if nullif(btrim(p_reason_code), '') is null or nullif(btrim(p_reason), '') is null then
    raise exception 'Purchase credit note reason code and explanation are required';
  end if;
  if nullif(btrim(p_idempotency_key), '') is null then raise exception 'Purchase credit note idempotency key is required'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'Purchase credit note requires at least one line'; end if;

  select * into v_existing from public.purchase_credit_notes
  where tenant_id = v_tenant_id and idempotency_key = btrim(p_idempotency_key);
  if found then
    if v_existing.purchase_invoice_id <> p_purchase_invoice_id then raise exception 'Idempotency key belongs to a different purchase invoice'; end if;
    return jsonb_build_object('purchase_credit_note_id', v_existing.id, 'operation_id', v_existing.operation_id, 'credit_note_number', v_existing.credit_note_number, 'replayed', true);
  end if;
  select coalesce(setting.control_mode, 'disabled') into v_mode
  from (select 1) seed left join public.purchase_credit_note_control_settings setting on setting.tenant_id = v_tenant_id;
  if v_mode <> 'enforce' then raise exception 'Purchase credit note workflow is not active for this tenant'; end if;

  select * into v_invoice from public.purchase_invoices
  where id = p_purchase_invoice_id and tenant_id = v_tenant_id for update;
  if not found then raise exception 'Purchase invoice not found for current tenant'; end if;
  if v_invoice.status not in ('confirmed', 'received', 'paid') then raise exception 'Purchase invoice must be posted before crediting'; end if;

  insert into public.inventory_accounting_operations (
    id, tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, old_status, new_status, context
  ) values (
    v_operation_id, v_tenant_id,
    format('purchase_credit_note:%s:%s', p_purchase_invoice_id, btrim(p_idempotency_key)),
    'purchase_credit_note', 'create', 'purchase_credit_note', v_note_id,
    v_actor_id, 'database_command', v_invoice.status, v_invoice.status,
    jsonb_build_object('purchase_invoice_id', v_invoice.id, 'stock_effect', 'none', 'official_dte_status', 'internal')
  );
  perform public.append_inventory_accounting_checkpoint(v_operation_id, 'accepted', 'started', 'purchase_invoice', v_invoice.id, jsonb_build_object('line_count', jsonb_array_length(p_lines)));
  v_note_number := public.get_next_document_number(v_tenant_id, 'purchase_credit_note', 'NCC');

  create temporary table if not exists pg_temp.purchase_credit_note_work (
    source_line_key text, source_line_index integer, product_id uuid,
    product_name text, product_sku text, purchase_treatment text,
    disposition text, supplier_return_line_id uuid, credited_quantity integer,
    original_quantity integer, original_allocated_net numeric(12,2),
    original_allocated_tax numeric(12,2), net_amount numeric(12,2),
    tax_amount numeric(12,2), line_snapshot jsonb
  ) on commit drop;
  truncate pg_temp.purchase_credit_note_work;

  for v_request in select value from jsonb_array_elements(p_lines) loop
    v_index := nullif(v_request->>'line_index', '')::integer;
    if v_index is null or v_index < 0 or v_index >= jsonb_array_length(v_invoice.items) then raise exception 'Invalid purchase invoice line index %', v_index; end if;
    v_item := v_invoice.items->v_index;
    v_source_key := coalesce(nullif(v_item->>'line_id',''), nullif(v_item->>'id',''), md5(v_invoice.id::text || ':' || v_index::text || ':' || coalesce(v_item->>'product_id','')));
    if exists(select 1 from pg_temp.purchase_credit_note_work where source_line_key = v_source_key) then raise exception 'Duplicate purchase credit note line'; end if;
    v_product_id := nullif(v_item->>'product_id','')::uuid;
    v_treatment := coalesce(nullif(v_item->>'purchase_treatment',''), 'inventory');
    if v_treatment not in ('inventory','workshop_consumable') then raise exception 'Unsupported purchase treatment for credit note'; end if;
    select original_quantity,original_allocated_net,original_allocated_tax
    into v_original_qty,v_allocated_net,v_allocated_tax
    from public.purchase_credit_note_line_balance_view
    where tenant_id=v_tenant_id and purchase_invoice_id=v_invoice.id and source_line_index=v_index;
    if not found then raise exception 'Purchase credit source line allocation not found'; end if;

    select coalesce(sum(line.credited_quantity),0), coalesce(sum(line.net_amount),0), coalesce(sum(line.tax_amount),0)
    into v_previous_qty, v_previous_net, v_previous_tax
    from public.purchase_credit_note_lines line join public.purchase_credit_notes note on note.id = line.purchase_credit_note_id
    where line.tenant_id = v_tenant_id and line.purchase_invoice_id = v_invoice.id
      and line.source_line_key = v_source_key and note.status = 'posted';
    v_credit_qty := coalesce(nullif(v_request->>'credited_quantity','')::integer,0);
    if v_credit_qty < 0 or v_credit_qty + v_previous_qty > v_original_qty then raise exception 'Purchase credit quantity exceeds original line balance'; end if;
    v_credit_net := coalesce(nullif(v_request->>'net_amount','')::numeric,
      case when v_original_qty > 0 then public.clp_round(v_allocated_net * v_credit_qty / v_original_qty) else 0 end);
    v_credit_tax := coalesce(nullif(v_request->>'tax_amount','')::numeric,
      case when v_allocated_net > 0 then public.clp_round(v_allocated_tax * v_credit_net / v_allocated_net) else 0 end);
    if v_credit_net <> public.clp_round(v_credit_net) or v_credit_tax <> public.clp_round(v_credit_tax) or v_credit_net < 0 or v_credit_tax < 0 or v_credit_net + v_credit_tax <= 0 then raise exception 'Purchase credit note amounts must be positive whole CLP'; end if;
    if v_previous_net + v_credit_net > v_allocated_net or v_previous_tax + v_credit_tax > v_allocated_tax then raise exception 'Purchase credit amount exceeds original line balance'; end if;

    v_disposition := coalesce(nullif(v_request->>'disposition',''), 'financial_only');
    v_return_line_id := nullif(v_request->>'supplier_return_line_id','')::uuid;
    if v_disposition = 'supplier_return' then
      if v_return_line_id is null or v_credit_qty <= 0 then raise exception 'Supplier-return credit requires a returned receipt line and quantity'; end if;
      select return_line.*, supplier_return.status return_status into v_return_line
      from public.purchase_supplier_return_lines return_line
      join public.purchase_supplier_returns supplier_return on supplier_return.id = return_line.supplier_return_id
      where return_line.id = v_return_line_id and return_line.tenant_id = v_tenant_id
        and supplier_return.purchase_invoice_id = v_invoice.id and return_line.source_line_key = v_source_key;
      if not found or v_return_line.return_status <> 'posted' then raise exception 'Posted supplier return line not found for credited invoice line'; end if;
      select coalesce(sum(line.credited_quantity),0) into v_return_previously_credited
      from public.purchase_credit_note_lines line join public.purchase_credit_notes note on note.id = line.purchase_credit_note_id
      where line.supplier_return_line_id = v_return_line_id and note.status = 'posted';
      if v_return_previously_credited + v_credit_qty > v_return_line.returned_quantity then raise exception 'Credit quantity exceeds linked supplier return quantity'; end if;
    elsif v_disposition <> 'financial_only' or v_return_line_id is not null then
      raise exception 'Invalid purchase credit note disposition';
    end if;

    insert into pg_temp.purchase_credit_note_work values (
      v_source_key, v_index, v_product_id, coalesce(v_item->>'product_name','Producto'), v_item->>'product_sku', v_treatment,
      v_disposition, v_return_line_id, v_credit_qty, v_original_qty, v_allocated_net, v_allocated_tax,
      v_credit_net, v_credit_tax, v_item
    );
    v_total_net := v_total_net + v_credit_net; v_total_tax := v_total_tax + v_credit_tax;
    if v_treatment = 'workshop_consumable' then
      v_consumable_net := v_consumable_net + v_credit_net;
    elsif v_disposition = 'supplier_return' then
      v_supplier_claim_net := v_supplier_claim_net + v_credit_net;
    else
      v_inventory_net := v_inventory_net + v_credit_net;
    end if;
  end loop;

  if v_total_net + v_total_tax > public.clp_round(v_invoice.total - coalesce(v_invoice.credited_amount,0)) then raise exception 'Purchase credit note exceeds remaining invoice amount'; end if;
  v_description := format('Nota de crédito compra %s - factura %s', v_note_number, v_invoice.invoice_number);
  v_inventory_account := public.ensure_account(v_tenant_id,'1105','Inventarios','asset','currentAsset','Valor del inventario de productos',null);
  v_consumable_account := public.ensure_account(v_tenant_id,'5101','Consumibles de Taller','expense','costOfGoodsSold','Materiales y consumibles de taller',null);
  v_tax_account := public.ensure_account(v_tenant_id,'2120','IVA Crédito Fiscal','asset','currentAsset','IVA pagado en compras, recuperable',null);
  v_payable_account := public.ensure_account(v_tenant_id,'2101','Cuentas por Pagar Proveedores','liability','currentLiability','Obligaciones con proveedores',null);
  v_supplier_claim_account := public.ensure_account(v_tenant_id,'1145','Reclamos a Proveedores','asset','currentAsset','Mercadería devuelta pendiente de nota de crédito o reembolso',null);

  insert into public.journal_entries (
    id, tenant_id, entry_number, entry_date, description, type, source_module,
    source_reference, status, total_debit, total_credit, operation_id,
    source_document_type, source_document_id, created_by, created_at, updated_at
  ) values (
    v_journal_id, v_tenant_id, public.get_next_document_number(v_tenant_id,'journal_entry'), p_issue_date,
    v_description, 'credit_note', 'purchase_credit_notes', v_note_id::text, 'posted',
    v_total_net + v_total_tax, v_total_net + v_total_tax, v_operation_id,
    'purchase_credit_note', v_note_id, v_actor_id, clock_timestamp(), clock_timestamp()
  );
  insert into public.journal_lines (id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at)
  values (gen_random_uuid(),v_tenant_id,v_journal_id,v_payable_account,'2101','Cuentas por Pagar Proveedores',v_description,v_total_net+v_total_tax,0,now(),now());
  if v_inventory_net > 0 then insert into public.journal_lines (id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at) values (gen_random_uuid(),v_tenant_id,v_journal_id,v_inventory_account,'1105','Inventarios',v_description,0,v_inventory_net,now(),now()); end if;
  if v_consumable_net > 0 then insert into public.journal_lines (id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at) values (gen_random_uuid(),v_tenant_id,v_journal_id,v_consumable_account,'5101','Consumibles de Taller',v_description,0,v_consumable_net,now(),now()); end if;
  if v_supplier_claim_net > 0 then insert into public.journal_lines (id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at) values (gen_random_uuid(),v_tenant_id,v_journal_id,v_supplier_claim_account,'1145','Reclamos a Proveedores',v_description,0,v_supplier_claim_net,now(),now()); end if;
  if v_total_tax > 0 then insert into public.journal_lines (id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at) values (gen_random_uuid(),v_tenant_id,v_journal_id,v_tax_account,'2120','IVA Crédito Fiscal',v_description,0,v_total_tax,now(),now()); end if;

  insert into public.purchase_credit_notes (
    id,tenant_id,purchase_invoice_id,credit_note_number,supplier_credit_note_number,issue_date,
    reason_code,reason,net_amount,tax_amount,total_amount,idempotency_key,operation_id,journal_entry_id,created_by
  ) values (
    v_note_id,v_tenant_id,v_invoice.id,v_note_number,nullif(btrim(p_supplier_credit_note_number),''),p_issue_date,
    btrim(p_reason_code),btrim(p_reason),v_total_net,v_total_tax,v_total_net+v_total_tax,btrim(p_idempotency_key),v_operation_id,v_journal_id,v_actor_id
  );
  insert into public.purchase_credit_note_lines (
    tenant_id,purchase_credit_note_id,purchase_invoice_id,source_line_key,source_line_index,product_id,product_name,product_sku,
    purchase_treatment,disposition,supplier_return_line_id,credited_quantity,original_quantity,original_allocated_net,
    original_allocated_tax,net_amount,tax_amount,total_amount,line_snapshot
  ) select v_tenant_id,v_note_id,v_invoice.id,source_line_key,source_line_index,product_id,product_name,product_sku,
    purchase_treatment,disposition,supplier_return_line_id,credited_quantity,original_quantity,original_allocated_net,
    original_allocated_tax,net_amount,tax_amount,net_amount+tax_amount,line_snapshot from pg_temp.purchase_credit_note_work;

  perform public.recalculate_purchase_invoice_settlement(v_invoice.id);
  perform public.append_inventory_accounting_checkpoint(v_operation_id,'inventory_applied','completed','purchase_credit_note',v_note_id,jsonb_build_object('movement_count',0,'stock_effect','none'));
  perform public.append_inventory_accounting_checkpoint(v_operation_id,'journal_posted','completed','journal_entry',v_journal_id,jsonb_build_object('debit',v_total_net+v_total_tax,'credit',v_total_net+v_total_tax));
  perform public.append_inventory_accounting_checkpoint(v_operation_id,'invariants_verified','completed','purchase_credit_note',v_note_id,jsonb_build_object('balanced_journal',true,'official_dte_status','internal'));
  update public.inventory_accounting_operations set outcome='completed',completed_at=clock_timestamp(),after_snapshot=jsonb_build_object('purchase_credit_note_id',v_note_id,'total',v_total_net+v_total_tax) where id=v_operation_id;
  perform public.append_inventory_accounting_checkpoint(v_operation_id,'completed','completed','purchase_credit_note',v_note_id,jsonb_build_object('credit_note_number',v_note_number));
  return jsonb_build_object('purchase_credit_note_id',v_note_id,'operation_id',v_operation_id,'credit_note_number',v_note_number,'replayed',false);
end;
$$;

create or replace function public.void_purchase_credit_note(p_credit_note_id uuid,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_tenant_id uuid:=public.user_tenant_id(); v_actor_id uuid:=auth.uid();
  v_note public.purchase_credit_notes%rowtype; v_operation_id uuid:=gen_random_uuid(); v_journal_id uuid:=gen_random_uuid();
  v_line record;
begin
  if v_actor_id is null or v_tenant_id is null then raise exception 'Authenticated employee tenant is required'; end if;
  if nullif(btrim(p_reason),'') is null or nullif(btrim(p_idempotency_key),'') is null then raise exception 'Credit note void reason and idempotency key are required'; end if;
  select * into v_note from public.purchase_credit_notes where id=p_credit_note_id and tenant_id=v_tenant_id for update;
  if not found then raise exception 'Purchase credit note not found for current tenant'; end if;
  if v_note.status='voided' then
    if v_note.void_idempotency_key=btrim(p_idempotency_key) then return jsonb_build_object('purchase_credit_note_id',v_note.id,'operation_id',v_note.void_operation_id,'replayed',true); end if;
    raise exception 'Purchase credit note is already voided';
  end if;
  if v_note.official_dte_status='issued' then raise exception 'Issued tax credit notes require an official reversal document'; end if;
  insert into public.inventory_accounting_operations(id,tenant_id,operation_key,source_channel,action,document_type,document_id,actor_id,executor,old_status,new_status,context)
  values(v_operation_id,v_tenant_id,format('purchase_credit_note_void:%s:%s',p_credit_note_id,btrim(p_idempotency_key)),'purchase_credit_note','void','purchase_credit_note',p_credit_note_id,v_actor_id,'database_command','posted','voided',jsonb_build_object('reason',btrim(p_reason)));
  insert into public.journal_entries(id,tenant_id,entry_number,entry_date,description,type,source_module,source_reference,status,total_debit,total_credit,operation_id,source_document_type,source_document_id,created_by,reversal_of_id,created_at,updated_at)
  values(v_journal_id,v_tenant_id,public.get_next_document_number(v_tenant_id,'journal_entry'),clock_timestamp(),format('Anulación %s: %s',v_note.credit_note_number,btrim(p_reason)),'credit_note_void','purchase_credit_notes',p_credit_note_id::text,'posted',v_note.total_amount,v_note.total_amount,v_operation_id,'purchase_credit_note',p_credit_note_id,v_actor_id,v_note.journal_entry_id,now(),now());
  for v_line in select * from public.journal_lines where entry_id=v_note.journal_entry_id loop
    insert into public.journal_lines(id,tenant_id,entry_id,account_id,account_code,account_name,description,debit_amount,credit_amount,created_at,updated_at)
    values(gen_random_uuid(),v_tenant_id,v_journal_id,v_line.account_id,v_line.account_code,v_line.account_name,format('Anulación %s',v_note.credit_note_number),v_line.credit_amount,v_line.debit_amount,now(),now());
  end loop;
  update public.purchase_credit_notes set status='voided',void_operation_id=v_operation_id,void_journal_entry_id=v_journal_id,void_idempotency_key=btrim(p_idempotency_key),voided_at=clock_timestamp(),voided_by=v_actor_id,void_reason=btrim(p_reason) where id=p_credit_note_id;
  perform public.recalculate_purchase_invoice_settlement(v_note.purchase_invoice_id);
  perform public.append_inventory_accounting_checkpoint(v_operation_id,'inventory_applied','completed','purchase_credit_note',p_credit_note_id,jsonb_build_object('movement_count',0));
  perform public.append_inventory_accounting_checkpoint(v_operation_id,'journal_reversed','completed','journal_entry',v_journal_id,jsonb_build_object('reversal_of_id',v_note.journal_entry_id));
  perform public.append_inventory_accounting_checkpoint(v_operation_id,'invariants_verified','completed','purchase_credit_note',p_credit_note_id,jsonb_build_object('balanced_journal',true));
  update public.inventory_accounting_operations set outcome='completed',completed_at=clock_timestamp(),after_snapshot=jsonb_build_object('status','voided') where id=v_operation_id;
  perform public.append_inventory_accounting_checkpoint(v_operation_id,'completed','completed','purchase_credit_note',p_credit_note_id,jsonb_build_object('status','voided'));
  return jsonb_build_object('purchase_credit_note_id',p_credit_note_id,'operation_id',v_operation_id,'replayed',false);
end;
$$;

create or replace function public.prevent_void_supplier_return_with_posted_credit()
returns trigger language plpgsql set search_path=public as $$
begin
  if old.status='posted' and new.status='voided' and exists(
    select 1 from public.purchase_credit_note_lines line join public.purchase_credit_notes note on note.id=line.purchase_credit_note_id
    where line.supplier_return_line_id in (select id from public.purchase_supplier_return_lines where supplier_return_id=old.id)
      and note.status='posted'
  ) then raise exception 'Void linked purchase credit notes before voiding this supplier return'; end if;
  return new;
end;
$$;

create or replace function public.prevent_supplier_return_void_operation_with_posted_credit()
returns trigger language plpgsql set search_path=public as $$
begin
  if new.document_type='purchase_supplier_return' and new.action='void' and exists(
    select 1
    from public.purchase_supplier_return_lines return_line
    join public.purchase_credit_note_lines credit_line on credit_line.supplier_return_line_id=return_line.id
    join public.purchase_credit_notes note on note.id=credit_line.purchase_credit_note_id
    where return_line.supplier_return_id=new.document_id and note.status='posted'
  ) then raise exception 'Void linked purchase credit notes before voiding this supplier return'; end if;
  return new;
end;
$$;

create or replace function public.prevent_financial_edit_with_posted_purchase_credit()
returns trigger language plpgsql set search_path=public as $$
begin
  if exists(select 1 from public.purchase_credit_notes note where note.purchase_invoice_id=old.id and note.status='posted')
     and (
       new.items is distinct from old.items or new.subtotal is distinct from old.subtotal
       or new.tax is distinct from old.tax or new.total is distinct from old.total
       or new.net_amount is distinct from old.net_amount
       or new.tax_treatment is distinct from old.tax_treatment
     ) then
    raise exception 'Void posted purchase credit notes before editing invoice financial lines';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_prevent_void_supplier_return_with_credit on public.purchase_supplier_returns;
create trigger trg_prevent_void_supplier_return_with_credit before update of status on public.purchase_supplier_returns
for each row execute function public.prevent_void_supplier_return_with_posted_credit();
drop trigger if exists trg_prevent_supplier_return_void_operation_with_credit on public.inventory_accounting_operations;
create trigger trg_prevent_supplier_return_void_operation_with_credit before insert on public.inventory_accounting_operations
for each row execute function public.prevent_supplier_return_void_operation_with_posted_credit();
drop trigger if exists trg_prevent_financial_edit_with_purchase_credit on public.purchase_invoices;
create trigger trg_prevent_financial_edit_with_purchase_credit before update on public.purchase_invoices
for each row execute function public.prevent_financial_edit_with_posted_purchase_credit();

revoke all on function public.create_purchase_credit_note(uuid,jsonb,timestamp with time zone,text,text,text,text) from public,anon;
grant execute on function public.create_purchase_credit_note(uuid,jsonb,timestamp with time zone,text,text,text,text) to authenticated;
revoke all on function public.void_purchase_credit_note(uuid,text,text) from public,anon;
grant execute on function public.void_purchase_credit_note(uuid,text,text) to authenticated;

commit;
