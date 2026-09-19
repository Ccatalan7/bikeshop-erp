begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

insert into public.tenants (id, shop_name, timezone) values
  ('e7000000-0000-4000-8000-000000000001', 'Cartolas con salto de página', 'America/Santiago'),
  ('e7000000-0000-4000-8000-000000000101', 'Otra tienda', 'America/Santiago');
set local session_replication_role = replica;
delete from public.payment_terminal_terms
 where tenant_id in ('e7000000-0000-4000-8000-000000000001', 'e7000000-0000-4000-8000-000000000101');
delete from public.payment_terminal_profiles
 where tenant_id in ('e7000000-0000-4000-8000-000000000001', 'e7000000-0000-4000-8000-000000000101');
delete from public.payment_methods
 where tenant_id in ('e7000000-0000-4000-8000-000000000001', 'e7000000-0000-4000-8000-000000000101');
delete from public.accounts
 where tenant_id in ('e7000000-0000-4000-8000-000000000001', 'e7000000-0000-4000-8000-000000000101');
set local session_replication_role = origin;

insert into public.accounts (id, tenant_id, code, name, type, category) values
  ('e7000000-0000-4000-8000-000000000010', 'e7000000-0000-4000-8000-000000000001',
   '1110', 'Banco de Chile', 'asset', 'currentAsset'),
  ('e7000000-0000-4000-8000-000000000013', 'e7000000-0000-4000-8000-000000000001',
   '6190', 'Gastos generales', 'expense', 'operatingExpense'),
  ('e7000000-0000-4000-8000-000000000110', 'e7000000-0000-4000-8000-000000000101',
   '1110', 'Banco ajeno', 'asset', 'currentAsset');
insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values
  ('e7000000-0000-4000-8000-000000000020', 'e7000000-0000-4000-8000-000000000001',
   'transfer', 'Transferencia', 'e7000000-0000-4000-8000-000000000010', 'no_tax');

set local session_replication_role = replica;
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e7000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'page-break@example.invalid', '', now(), '{"account_type":"erp_staff"}'::jsonb,
   '{}'::jsonb, now(), now()),
  ('e7000000-0000-4000-8000-000000000102', 'authenticated', 'authenticated',
   'page-break-other@example.invalid', '', now(), '{"account_type":"erp_staff"}'::jsonb,
   '{}'::jsonb, now(), now());
insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values
  ('e7000000-0000-4000-8000-000000000003', 'e7000000-0000-4000-8000-000000000002',
   'e7000000-0000-4000-8000-000000000001', 'accountant',
   '{"access_accounting":true}'::jsonb, true),
  ('e7000000-0000-4000-8000-000000000103', 'e7000000-0000-4000-8000-000000000102',
   'e7000000-0000-4000-8000-000000000101', 'accountant',
   '{"access_accounting":true}'::jsonb, true);
set local session_replication_role = origin;

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

select pg_temp.act_as('e7000000-0000-4000-8000-000000000002');

create function pg_temp.statement_row(
  p_source_row_id text, p_ordinal integer, p_booking_date date,
  p_amount numeric, p_balance numeric, p_description text
) returns jsonb language sql as $$
  select jsonb_build_object(
    'source_row_id', p_source_row_id, 'ordinal', p_ordinal,
    'booking_date', p_booking_date, 'operation_date', null,
    'direction', 'debit', 'amount', p_amount,
    'description', p_description,
    'normalized_description', lower(p_description),
    'counterparty_observed', null, 'document_number', null,
    'balance', p_balance, 'warning_codes', '[]'::jsonb, 'source_page', 1,
    'source_line_start', p_ordinal, 'source_line_end', p_ordinal,
    'fingerprint', encode(extensions.digest(p_source_row_id, 'sha256'), 'hex')
  )
$$;


create function pg_temp.save(p_key text, p_sha text, p_rows jsonb)
returns jsonb language sql as $$
  select public.save_bank_statement_import_v1(
    p_key, p_sha, null, 'e7000000-0000-4000-8000-000000000010',
    '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
    p_rows
  )
$$;

create temp table august on commit drop as
select pg_temp.save('page-break:august', repeat('e', 64), jsonb_build_array(
  pg_temp.statement_row('p2-l38', 1, '2026-08-11', 499467, 1000000, 'App-traspaso A: Darinka'),
  pg_temp.statement_row('p2-l39-r38', 2, '2026-08-11', 700000, 1700000, 'Traspaso De: Claudio Angel')
    || jsonb_build_object('source_page', 2, 'source_page_end', 3,
                          'source_line_start', 39, 'source_line_end', 1)
)) as receipt;

select is(
  (select jsonb_array_length(receipt->'rows') from august),
  2,
  'a statement with a movement split by a page break is saved whole'
);

select ok(
  exists (
    select 1 from public.bank_statement_rows
     where tenant_id = 'e7000000-0000-4000-8000-000000000001'
       and source_row_id = 'p2-l39-r38'
       and source_page = 2 and source_page_end = 3
       and source_line_start = 39 and source_line_end = 1
  )
  and exists (
    select 1 from public.bank_statement_rows
     where tenant_id = 'e7000000-0000-4000-8000-000000000001'
       and source_row_id = 'p2-l38' and source_page_end is null
  ),
  'the split movement keeps both pages; one on a single page keeps one'
);

select throws_like(
  $q$select pg_temp.save('page-break:backwards', repeat('f', 64), jsonb_build_array(
    pg_temp.statement_row('x', 1, '2026-08-11', 1000, 1000, 'Pago')
      || jsonb_build_object('source_line_start', 9, 'source_line_end', 3)
  ))$q$,
  '%bank_statement_row_invalid%',
  'on one page the last line still cannot precede the first'
);

select throws_like(
  $q$select pg_temp.save('page-break:earlier-page', repeat('9', 64), jsonb_build_array(
    pg_temp.statement_row('y', 1, '2026-08-11', 1000, 1000, 'Pago')
      || jsonb_build_object('source_page', 3, 'source_page_end', 2)
  ))$q$,
  '%bank_statement_row_invalid%',
  'a movement cannot end on an earlier page'
);

select * from finish();
rollback;
