begin;

select no_plan();

select has_function('public', 'assistant_analyze_sales_period_v1', array[
  'text','text','text','text','text','text'
], 'typed temporal sales analysis exists');
select has_function('public', 'assistant_analyze_cash_and_receivables_v2',
  array['text','integer'], 'bounded cash and receivables v2 exists');
select ok((select function.prosecdef
      and function.provolatile = 's'
      and function.proconfig @> array[
        'search_path=pg_catalog, public, pg_temp',
        'statement_timeout=4500ms'
      ]::text[]
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'assistant_analyze_sales_period_v1'),
  'temporal analysis is a bounded stable security-definer read');
select ok(
  has_function_privilege('authenticated',
    'public.assistant_analyze_sales_period_v1(text,text,text,text,text,text)',
    'EXECUTE')
  and not has_function_privilege('anon',
    'public.assistant_analyze_sales_period_v1(text,text,text,text,text,text)',
    'EXECUTE')
  and not has_function_privilege('service_role',
    'public.assistant_analyze_sales_period_v1(text,text,text,text,text,text)',
    'EXECUTE'),
  'temporal analysis is callable only with an authenticated user JWT');
select ok((select pg_get_functiondef(function.oid) like all(array[
      '%v_business_date := (statement_timestamp() at time zone v_timezone)::date%',
      '%payment.deleted_at is null%',
      '%count(payment.id)%',
      '%count(*)::integer invoice_count%'
    ])
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'assistant_analyze_sales_period_v1'),
  'relative periods use tenant time and distinguish payment events from invoices');
select ok((select pg_get_functiondef(function.oid) like all(array[
      '%v_business_date := (statement_timestamp() at time zone v_timezone)::date%',
      '%due_business_date%',
      '%v_end_date := v_business_date +%'
    ])
    from pg_proc function
    join pg_namespace namespace on namespace.oid = function.pronamespace
    where namespace.nspname = 'public'
      and function.proname = 'assistant_analyze_cash_and_receivables_v2'),
  'cash v2 resolves business time once for the complete read');

insert into public.tenants (id, shop_name, owner_email, timezone)
values
  ('a1770000-0000-4000-8000-000000000001', 'Temporal analysis A',
   'temporal-admin@example.invalid', 'America/Santiago'),
  ('a1770000-0000-4000-8000-000000000002', 'Temporal analysis B',
   'temporal-poison@example.invalid', 'America/Santiago');

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a1770000-0000-4000-8000-000000000011', 'authenticated',
  'authenticated', 'temporal-admin@example.invalid', '', now(),
  '{}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (user_id, tenant_id, role, permissions)
values (
  'a1770000-0000-4000-8000-000000000011',
  'a1770000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb
);

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a1770000-0000-4000-8000-000000000011',
  'role', 'authenticated'
)::text, true);
select set_config('request.jwt.claim.sub',
  'a1770000-0000-4000-8000-000000000011', true);

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, is_active
) values (
  'a1770000-0000-4000-8000-000000000021',
  'a1770000-0000-4000-8000-000000000001', 'temporal-cash',
  'Caja temporal',
  (select account.id from public.accounts account
   where account.tenant_id = 'a1770000-0000-4000-8000-000000000001'
     and account.code = '1101'),
  true
);

-- Invoice lifecycle triggers write inventory and accounting ledgers. This
-- fixture supplies immutable read-model rows only.
alter table public.sales_invoices disable trigger user;
with bounds as (
  select date_trunc('week',
    (statement_timestamp() at time zone 'America/Santiago')
  )::date - 7 start_date
)
insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, date, status,
  subtotal, total, balance
)
select fixture.id, fixture.tenant_id, fixture.invoice_number,
  fixture.customer_name,
  ((bounds.start_date + fixture.day_offset) + time '12:00')
    at time zone 'America/Santiago',
  fixture.status, fixture.total, fixture.total, fixture.balance
from bounds cross join (values
  ('a1770000-0000-4000-8000-000000000101'::uuid,
   'a1770000-0000-4000-8000-000000000001'::uuid,
   'FV-LAST-A', 'Cliente A', 1, 'paid', 150000::numeric, 0::numeric),
  ('a1770000-0000-4000-8000-000000000102'::uuid,
   'a1770000-0000-4000-8000-000000000001'::uuid,
   'FV-LAST-B', 'Cliente B', 2, 'paid', 90000::numeric, 0::numeric),
  ('a1770000-0000-4000-8000-000000000103'::uuid,
   'a1770000-0000-4000-8000-000000000001'::uuid,
   'FV-LAST-C', 'Cliente C', 3, 'sent', 200000::numeric, 200000::numeric),
  ('a1770000-0000-4000-8000-000000000104'::uuid,
   'a1770000-0000-4000-8000-000000000002'::uuid,
   'FV-POISON', 'Tenant vecino', 2, 'paid', 999999::numeric, 0::numeric)
) fixture(
  id, tenant_id, invoice_number, customer_name, day_offset, status, total,
  balance
);
alter table public.sales_invoices enable trigger user;

-- Payment command triggers intentionally update settlements and journals. The
-- fixture isolates temporal read semantics and supplies the economic dates.
alter table public.sales_payments disable trigger user;
with bounds as (
  select date_trunc('week',
    (statement_timestamp() at time zone 'America/Santiago')
  )::date - 7 start_date
)
insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, amount, date, deleted_at
)
select fixture.id, 'a1770000-0000-4000-8000-000000000001'::uuid,
  fixture.invoice_id,
  'a1770000-0000-4000-8000-000000000021'::uuid,
  fixture.amount,
  ((bounds.start_date + fixture.day_offset) + time '15:00')
    at time zone 'America/Santiago',
  case when fixture.is_deleted then statement_timestamp() else null end
from bounds cross join (values
  ('a1770000-0000-4000-8000-000000000201'::uuid,
   'a1770000-0000-4000-8000-000000000101'::uuid, 60000::numeric, 1, false),
  ('a1770000-0000-4000-8000-000000000202'::uuid,
   'a1770000-0000-4000-8000-000000000101'::uuid, 10000::numeric, 4, false),
  ('a1770000-0000-4000-8000-000000000203'::uuid,
   'a1770000-0000-4000-8000-000000000102'::uuid, 90000::numeric, 2, false),
  ('a1770000-0000-4000-8000-000000000204'::uuid,
   'a1770000-0000-4000-8000-000000000103'::uuid, 500000::numeric, 3, true),
  ('a1770000-0000-4000-8000-000000000205'::uuid,
   'a1770000-0000-4000-8000-000000000102'::uuid, 250000::numeric, -3, false)
) fixture(id, invoice_id, amount, day_offset, is_deleted);
alter table public.sales_payments enable trigger user;

create temp table collected_last_week(payload jsonb);
create temp table issued_last_week(payload jsonb);
grant insert, select on collected_last_week, issued_last_week to authenticated;

set local role authenticated;
insert into collected_last_week
select public.assistant_analyze_sales_period_v1(
  'collected', 'relative', 'last_week', null, null, 'any'
);
insert into issued_last_week
select public.assistant_analyze_sales_period_v1(
  'issued', 'relative', 'last_week', null, null, 'any'
);

select is((select payload#>>'{items,0,invoiceCount}'
    from collected_last_week), '2',
  'last week collected count means distinct invoices, not payment rows');
select is((select payload#>>'{items,0,eventCount}'
    from collected_last_week), '3',
  'last week collected result separately reports three payment events');
select is((select payload#>>'{items,0,totalAmount}'
    from collected_last_week), '160000.00',
  'deleted and out-of-period payments do not inflate collected value');
select is((select payload#>>'{items,0,highestInvoiceNumber}'
    from collected_last_week), 'FV-LAST-B',
  'highest collected invoice is ranked by amount collected in the period');
select is((select payload#>>'{items,0,highestPeriodAmount}'
    from collected_last_week), '90000.00',
  'highest collected result exposes the exact period amount');
select ok((select payload::text not like '%FV-POISON%'
    from collected_last_week),
  'temporal analysis remains tenant-bound');
select is((select payload#>>'{items,0,invoiceCount}'
    from issued_last_week), '3',
  'issued analysis uses invoice economic dates independently of payments');
select is((select payload#>>'{items,0,highestInvoiceNumber}'
    from issued_last_week), 'FV-LAST-C',
  'issued analysis identifies the largest invoice issued in the period');
select throws_ok(
  $$select public.assistant_analyze_sales_period_v1(
    'issued', 'relative', 'last_week', '2026-01-01', null, 'any')$$,
  '22023', 'Invalid AI tool arguments',
  'relative and absolute date inputs cannot be mixed');
select throws_ok(
  $$select public.assistant_analyze_sales_period_v1(
    'issued', 'absolute', null, '2026-02-01', '2025-02-01', 'any')$$,
  '22023', 'Invalid AI tool arguments',
  'reversed absolute ranges fail closed');
reset role;

select * from finish();

rollback;
