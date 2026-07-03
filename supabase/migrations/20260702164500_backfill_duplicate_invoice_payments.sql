-- Backfill payment integrity after the historical duplicate-submit bug.
-- This is intentionally conservative: it only soft-deletes exact duplicate
-- payment rows when removing those extras still leaves the invoice fully paid.

alter table public.sales_payments
  add column if not exists idempotency_key text,
  add column if not exists notes text,
  add column if not exists deleted_at timestamp with time zone,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_at timestamp with time zone not null default now();

alter table public.purchase_payments
  add column if not exists idempotency_key text,
  add column if not exists notes text,
  add column if not exists deleted_at timestamp with time zone,
  add column if not exists deleted_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_at timestamp with time zone not null default now();

create table if not exists public.payment_integrity_backfill_audit (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade,
  payment_table text not null check (payment_table in ('sales_payments', 'purchase_payments')),
  payment_id uuid not null,
  invoice_id uuid not null,
  invoice_number text,
  action text not null,
  reason text not null,
  amount numeric(12,2) not null,
  payment_date timestamp with time zone,
  payment_reference text,
  created_at timestamp with time zone not null default now()
);

create unique index if not exists idx_payment_integrity_backfill_audit_payment_reason
  on public.payment_integrity_backfill_audit(payment_table, payment_id, reason);

create temp table _payment_integrity_duplicate_candidates (
  payment_table text not null,
  payment_id uuid not null,
  tenant_id uuid,
  invoice_id uuid not null,
  invoice_number text,
  amount numeric(12,2) not null,
  payment_date timestamp with time zone,
  payment_reference text,
  reason text not null,
  primary key (payment_table, payment_id)
) on commit drop;

create temp table _payment_integrity_raw_duplicate_candidates (
  payment_table text not null,
  payment_id uuid not null,
  tenant_id uuid,
  invoice_id uuid not null,
  invoice_number text,
  amount numeric(12,2) not null,
  payment_date timestamp with time zone,
  payment_reference text,
  reason text not null,
  invoice_paid_total numeric(12,2) not null,
  invoice_total numeric(12,2) not null,
  primary key (payment_table, payment_id)
) on commit drop;

with active_invoice_totals as (
  select
    pp.invoice_id,
    coalesce(pp.tenant_id, pi.tenant_id) as tenant_id,
    round(coalesce(sum(round(coalesce(pp.amount, 0), 2)), 0), 2) as paid_total,
    round(coalesce(pi.total, 0), 2) as invoice_total
  from public.purchase_payments pp
  join public.purchase_invoices pi on pi.id = pp.invoice_id
  where pp.deleted_at is null
  group by pp.invoice_id, coalesce(pp.tenant_id, pi.tenant_id), round(coalesce(pi.total, 0), 2)
  having round(coalesce(sum(round(coalesce(pp.amount, 0), 2)), 0), 2) > round(coalesce(pi.total, 0), 2)
),
ranked_duplicates as (
  select
    pp.id,
    coalesce(pp.tenant_id, pi.tenant_id) as tenant_id,
    pp.invoice_id,
    pi.invoice_number,
    round(coalesce(pp.amount, 0), 2) as amount,
    pp.date as payment_date,
    nullif(btrim(coalesce(pp.reference, '')), '') as payment_reference,
    ait.paid_total,
    ait.invoice_total,
    row_number() over (
      partition by
        coalesce(pp.tenant_id, pi.tenant_id),
        pp.invoice_id,
        pp.payment_method_id,
        round(coalesce(pp.amount, 0), 2),
        pp.date::date,
        coalesce(nullif(btrim(pp.reference), ''), '')
      order by pp.created_at nulls last, pp.date nulls last, pp.id
    ) as duplicate_rank
  from public.purchase_payments pp
  join public.purchase_invoices pi on pi.id = pp.invoice_id
  join active_invoice_totals ait on ait.invoice_id = pp.invoice_id
  where pp.deleted_at is null
    and round(coalesce(pp.amount, 0), 2) > 0
)
insert into _payment_integrity_raw_duplicate_candidates (
  payment_table,
  payment_id,
  tenant_id,
  invoice_id,
  invoice_number,
  amount,
  payment_date,
  payment_reference,
  reason,
  invoice_paid_total,
  invoice_total
)
select
  'purchase_payments',
  id,
  tenant_id,
  invoice_id,
  invoice_number,
  amount,
  payment_date,
  payment_reference,
  'duplicate_purchase_payment_exact_match',
  paid_total,
  invoice_total
from ranked_duplicates
where duplicate_rank > 1
on conflict do nothing;

with active_invoice_totals as (
  select
    sp.invoice_id,
    coalesce(sp.tenant_id, si.tenant_id) as tenant_id,
    round(coalesce(sum(round(coalesce(sp.amount, 0), 2)), 0), 2) as paid_total,
    round(coalesce(si.total, 0), 2) as invoice_total
  from public.sales_payments sp
  join public.sales_invoices si on si.id = sp.invoice_id
  where sp.deleted_at is null
  group by sp.invoice_id, coalesce(sp.tenant_id, si.tenant_id), round(coalesce(si.total, 0), 2)
  having round(coalesce(sum(round(coalesce(sp.amount, 0), 2)), 0), 2) > round(coalesce(si.total, 0), 2)
),
ranked_duplicates as (
  select
    sp.id,
    coalesce(sp.tenant_id, si.tenant_id) as tenant_id,
    sp.invoice_id,
    si.invoice_number,
    round(coalesce(sp.amount, 0), 2) as amount,
    sp.date as payment_date,
    nullif(btrim(coalesce(sp.reference, '')), '') as payment_reference,
    ait.paid_total,
    ait.invoice_total,
    row_number() over (
      partition by
        coalesce(sp.tenant_id, si.tenant_id),
        sp.invoice_id,
        sp.payment_method_id,
        round(coalesce(sp.amount, 0), 2),
        sp.date::date,
        coalesce(nullif(btrim(sp.reference), ''), '')
      order by sp.created_at nulls last, sp.date nulls last, sp.id
    ) as duplicate_rank
  from public.sales_payments sp
  join public.sales_invoices si on si.id = sp.invoice_id
  join active_invoice_totals ait on ait.invoice_id = sp.invoice_id
  where sp.deleted_at is null
    and round(coalesce(sp.amount, 0), 2) > 0
)
insert into _payment_integrity_raw_duplicate_candidates (
  payment_table,
  payment_id,
  tenant_id,
  invoice_id,
  invoice_number,
  amount,
  payment_date,
  payment_reference,
  reason,
  invoice_paid_total,
  invoice_total
)
select
  'sales_payments',
  id,
  tenant_id,
  invoice_id,
  invoice_number,
  amount,
  payment_date,
  payment_reference,
  'duplicate_sales_payment_exact_match',
  paid_total,
  invoice_total
from ranked_duplicates
where duplicate_rank > 1
on conflict do nothing;

with candidate_totals as (
  select
    payment_table,
    invoice_id,
    max(invoice_paid_total) as paid_total,
    max(invoice_total) as invoice_total,
    round(sum(amount), 2) as candidate_total
  from _payment_integrity_raw_duplicate_candidates
  group by payment_table, invoice_id
)
insert into _payment_integrity_duplicate_candidates (
  payment_table,
  payment_id,
  tenant_id,
  invoice_id,
  invoice_number,
  amount,
  payment_date,
  payment_reference,
  reason
)
select
  raw.payment_table,
  raw.payment_id,
  raw.tenant_id,
  raw.invoice_id,
  raw.invoice_number,
  raw.amount,
  raw.payment_date,
  raw.payment_reference,
  raw.reason
from _payment_integrity_raw_duplicate_candidates raw
join candidate_totals totals
  on totals.payment_table = raw.payment_table
 and totals.invoice_id = raw.invoice_id
where round(totals.paid_total - totals.candidate_total, 2) >= totals.invoice_total
on conflict do nothing;

insert into public.payment_integrity_backfill_audit (
  tenant_id,
  payment_table,
  payment_id,
  invoice_id,
  invoice_number,
  action,
  reason,
  amount,
  payment_date,
  payment_reference
)
select
  tenant_id,
  payment_table,
  payment_id,
  invoice_id,
  invoice_number,
  'soft_delete_duplicate_payment',
  reason,
  amount,
  payment_date,
  payment_reference
from _payment_integrity_duplicate_candidates
on conflict (payment_table, payment_id, reason) do nothing;

update public.purchase_payments pp
   set deleted_at = coalesce(pp.deleted_at, now()),
       updated_at = now(),
       notes = concat_ws(
         E'\n',
         nullif(pp.notes, ''),
         'Anulado por backfill de integridad: pago duplicado detectado.'
       )
  from _payment_integrity_duplicate_candidates c
 where c.payment_table = 'purchase_payments'
   and pp.id = c.payment_id
   and pp.deleted_at is null;

update public.sales_payments sp
   set deleted_at = coalesce(sp.deleted_at, now()),
       updated_at = now(),
       notes = concat_ws(
         E'\n',
         nullif(sp.notes, ''),
         'Anulado por backfill de integridad: pago duplicado detectado.'
       )
  from _payment_integrity_duplicate_candidates c
 where c.payment_table = 'sales_payments'
   and sp.id = c.payment_id
   and sp.deleted_at is null;

-- Newer payment journal entries are keyed by payment id.
delete from public.journal_entries je
using _payment_integrity_duplicate_candidates c
where je.source_module = c.payment_table
  and je.source_reference = c.payment_id::text;

-- Older purchase payment journal entries were incorrectly keyed by invoice number.
-- Normalize affected invoices by deleting those legacy entries and recreating one
-- payment journal entry per remaining active purchase payment.
delete from public.journal_entries je
using (
  select distinct tenant_id, invoice_id, invoice_number
  from _payment_integrity_duplicate_candidates
  where payment_table = 'purchase_payments'
) affected
where je.source_module = 'purchase_payments'
  and (affected.tenant_id is null or je.tenant_id = affected.tenant_id)
  and je.source_reference in (
    affected.invoice_number,
    affected.invoice_id::text
  );

do $$
declare
  v_payment record;
  v_invoice record;
  v_purchase_count integer;
  v_sales_count integer;
begin
  for v_payment in
    select pp.id
      from public.purchase_payments pp
     where pp.deleted_at is null
       and pp.invoice_id in (
         select invoice_id
           from _payment_integrity_duplicate_candidates
          where payment_table = 'purchase_payments'
       )
  loop
    perform public.create_purchase_payment_journal_entry(v_payment.id);
  end loop;

  for v_invoice in
    select distinct invoice_id
      from _payment_integrity_duplicate_candidates
     where payment_table = 'purchase_payments'
  loop
    perform public.recalculate_purchase_invoice_payments(v_invoice.invoice_id);
  end loop;

  for v_invoice in
    select distinct invoice_id
      from _payment_integrity_duplicate_candidates
     where payment_table = 'sales_payments'
  loop
    perform public.recalculate_sales_invoice_payments(v_invoice.invoice_id);
  end loop;

  select count(*) into v_purchase_count
    from _payment_integrity_duplicate_candidates
   where payment_table = 'purchase_payments';

  select count(*) into v_sales_count
    from _payment_integrity_duplicate_candidates
   where payment_table = 'sales_payments';

  raise notice 'Payment integrity backfill soft-deleted % purchase duplicate(s) and % sales duplicate(s).',
    v_purchase_count, v_sales_count;
end $$;
