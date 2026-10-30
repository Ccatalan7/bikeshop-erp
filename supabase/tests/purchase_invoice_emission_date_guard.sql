-- 20261030010000: an impossible emission date is refused when a purchase
-- invoice is written, and a posted invoice's journal entry follows its date.
-- Dates come from tenant_business_date, the clock the guard uses.
begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(18);

insert into public.tenants(id, shop_name, timezone) values
  ('9d300000-0000-4000-8000-000000000001',
   'Emission Date Guard Tenant', 'America/Santiago');

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create temp table emission_clock on commit drop as
select public.tenant_business_date('9d300000-0000-4000-8000-000000000001')
  as today;

create function pg_temp.local_midnight(p_day date)
returns timestamptz
language sql
immutable
as $$ select p_day::timestamp at time zone 'America/Santiago' $$;

select has_function(
  'public', 'purchase_document_date_problem', array['uuid', 'timestamp with time zone'],
  'the emission-date rule exists'
);

select has_trigger(
  'public', 'purchase_invoices', 'trg_guard_purchase_invoice_emission_date',
  'purchase invoices are guarded on insert and on a date change'
);

select is(
  public.purchase_document_date_problem(
    '9d300000-0000-4000-8000-000000000001',
    pg_temp.local_midnight((select today from emission_clock))),
  null,
  'today is a valid emission date'
);

select is(
  public.purchase_document_date_problem(
    '9d300000-0000-4000-8000-000000000001',
    pg_temp.local_midnight(
      make_date(extract(year from (select today from emission_clock))::integer - 1, 1, 1))),
  null,
  'January 1 of last year is still accepted'
);

select isnt(
  public.purchase_document_date_problem(
    '9d300000-0000-4000-8000-000000000001',
    pg_temp.local_midnight(
      make_date(extract(year from (select today from emission_clock))::integer - 1, 1, 1) - 1)),
  null,
  'the day before January 1 of last year is refused'
);

select is(
  public.purchase_document_date_problem(
    '9d300000-0000-4000-8000-000000000001',
    pg_temp.local_midnight((select today from emission_clock) - 330)),
  null,
  'an eleven-month-old AliExpress backfill is accepted'
);

select matches(
  public.purchase_document_date_problem(
    '9d300000-0000-4000-8000-000000000001',
    pg_temp.local_midnight(date '2014-08-22')),
  'resolución del SII',
  'the SII resolution date is refused and named'
);

select matches(
  public.purchase_document_date_problem(
    '9d300000-0000-4000-8000-000000000001',
    pg_temp.local_midnight((select today from emission_clock) + 2)),
  'posterior a hoy',
  'a date after tomorrow is refused'
);

select is(
  public.purchase_document_date_problem(
    '9d300000-0000-4000-8000-000000000001',
    pg_temp.local_midnight((select today from emission_clock) + 1)),
  null,
  'tomorrow is tolerated'
);

select throws_ok(
  $$insert into public.purchase_invoices (
      id, tenant_id, invoice_number, supplier_name, status, date, items)
    values ('9d300000-0000-4000-8000-000000000010',
            '9d300000-0000-4000-8000-000000000001',
            'EMI-2014', 'TeknoBike', 'draft',
            '2014-08-22 04:00:00+00', '[]'::jsonb)$$,
  '22023',
  null,
  'a new invoice dated 22-08-2014 is refused'
);

select throws_ok(
  $$insert into public.purchase_invoices (
      id, tenant_id, invoice_number, supplier_name, status, date,
      supplier_invoice_date, items)
    values ('9d300000-0000-4000-8000-000000000011',
            '9d300000-0000-4000-8000-000000000001',
            'EMI-SUPPLIER-2014', 'TeknoBike', 'draft', now(),
            '2014-08-22 04:00:00+00', '[]'::jsonb)$$,
  '22023',
  null,
  'a supplier invoice date of 22-08-2014 is refused'
);

select lives_ok(
  format(
    $$insert into public.purchase_invoices (
        id, tenant_id, invoice_number, supplier_name, status, date, items)
      values ('9d300000-0000-4000-8000-000000000012',
              '9d300000-0000-4000-8000-000000000001',
              'EMI-DRAFT', 'TeknoBike', 'draft', %L, '[]'::jsonb)$$,
    pg_temp.local_midnight((select today from emission_clock) - 3)),
  'a draft dated three days ago is accepted'
);

-- The supplier-foundation restore writes backed-up dates as they were.
select set_config(
  'app.supplier_foundation_invoice_rehydrate_tenant',
  '9d300000-0000-4000-8000-000000000001',
  true
);
select lives_ok(
  $$update public.purchase_invoices
       set date = '2014-08-22 04:00:00+00'
     where id = '9d300000-0000-4000-8000-000000000012'$$,
  'the restore path keeps its exemption'
);
select set_config('app.supplier_foundation_invoice_rehydrate_tenant', '', true);

select lives_ok(
  $$update public.purchase_invoices
       set notes = 'Sólo una nota',
           date = date + interval '3 hours'
     where id = '9d300000-0000-4000-8000-000000000012'$$,
  'a stored date is not judged again while its day stays the same'
);

select throws_ok(
  $$update public.purchase_invoices
       set date = '2014-08-23 04:00:00+00'
     where id = '9d300000-0000-4000-8000-000000000012'$$,
  '22023',
  null,
  'moving a date to another impossible day is refused'
);

-- A posted invoice carries its journal entry along when its day changes.
-- A purchase entry needs its supplier (journal provenance).
insert into public.suppliers (id, tenant_id, name, is_active, updated_at)
values ('9d300000-0000-4000-8000-000000000030',
        '9d300000-0000-4000-8000-000000000001', 'TeknoBike', true, now());

insert into public.purchase_invoices (
  id, tenant_id, invoice_number, supplier_id, supplier_name, status, date,
  subtotal, net_amount, tax, iva_amount, total, paid_amount, balance, items
) values (
  '9d300000-0000-4000-8000-000000000020',
  '9d300000-0000-4000-8000-000000000001',
  'EMI-POSTED', '9d300000-0000-4000-8000-000000000030', 'TeknoBike', 'confirmed',
  pg_temp.local_midnight((select today from emission_clock) - 10),
  10000, 10000, 1900, 1900, 11900, 0, 11900, '[]'::jsonb
);

create temp table emission_entry_before on commit drop as
select entry.id, entry.entry_number, entry.entry_date::date as entry_date,
       (select sum(line.debit_amount)
          from public.journal_lines line
         where line.entry_id = entry.id) as debit
  from public.journal_entries entry
 where entry.tenant_id = '9d300000-0000-4000-8000-000000000001'
   and entry.source_module = 'purchase_invoices'
   and entry.source_reference = 'EMI-POSTED';

select is(
  (select entry_date from emission_entry_before),
  (select today from emission_clock) - 10,
  'the posted entry starts on the invoice date'
);

update public.purchase_invoices
   set date = pg_temp.local_midnight((select today from emission_clock) - 4)
 where id = '9d300000-0000-4000-8000-000000000020';

select results_eq(
  $$select entry.id, entry.entry_number, entry.entry_date::date,
           (select sum(line.debit_amount)
              from public.journal_lines line
             where line.entry_id = entry.id)
      from public.journal_entries entry
     where entry.tenant_id = '9d300000-0000-4000-8000-000000000001'
       and entry.source_module = 'purchase_invoices'
       and entry.source_reference = 'EMI-POSTED'$$,
  $$select id, entry_number, (select today from emission_clock) - 4, debit
      from emission_entry_before$$,
  'the same entry, number and lines move to the corrected date'
);

select is(
  (select count(*)::integer
     from public.journal_entries entry
    where entry.tenant_id = '9d300000-0000-4000-8000-000000000001'
      and entry.source_module = 'purchase_invoices'),
  1,
  'correcting the date neither duplicates nor drops the entry'
);

select * from finish();
rollback;
