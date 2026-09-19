begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

insert into public.tenants (id, shop_name, timezone) values
  ('e8000000-0000-4000-8000-000000000001', 'Clasifica en su sentido', 'America/Santiago');
-- New tenants are seeded with a chart, methods and a card terminal that
-- reference each other both ways; this test brings its own.
set local session_replication_role = replica;
delete from public.payment_terminal_terms
 where tenant_id = 'e8000000-0000-4000-8000-000000000001';
delete from public.payment_terminal_profiles
 where tenant_id = 'e8000000-0000-4000-8000-000000000001';
delete from public.payment_methods
 where tenant_id = 'e8000000-0000-4000-8000-000000000001';
delete from public.accounts
 where tenant_id = 'e8000000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

insert into public.accounts (id, tenant_id, code, name, type, category) values
  ('e8000000-0000-4000-8000-000000000010', 'e8000000-0000-4000-8000-000000000001',
   '1110', 'Banco de Chile', 'asset', 'currentAsset'),
  ('e8000000-0000-4000-8000-000000000011', 'e8000000-0000-4000-8000-000000000001',
   '6601', 'Gastos Financieros', 'expense', 'financialExpense'),
  ('e8000000-0000-4000-8000-000000000012', 'e8000000-0000-4000-8000-000000000001',
   '3102', 'Aportes de socio', 'equity', 'capital');

set local session_replication_role = replica;
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e8000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'post-journal-direction@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'e8000000-0000-4000-8000-000000000003',
  'e8000000-0000-4000-8000-000000000002',
  'e8000000-0000-4000-8000-000000000001',
  'accountant', '{"access_accounting":true}'::jsonb, true
);
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"e8000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', 'e8000000-0000-4000-8000-000000000002', true
);

create function pg_temp.statement_row(
  p_source_row_id text, p_ordinal integer, p_direction text, p_amount numeric,
  p_balance numeric, p_description text
) returns jsonb language sql as $$
  select jsonb_build_object(
    'source_row_id', p_source_row_id, 'ordinal', p_ordinal,
    'booking_date', '2026-09-16', 'operation_date', null,
    'direction', p_direction, 'amount', p_amount,
    'description', p_description,
    'normalized_description', lower(p_description),
    'counterparty_observed', null, 'document_number', null,
    'balance', p_balance, 'warning_codes', '[]'::jsonb, 'source_page', 1,
    'source_line_start', p_ordinal, 'source_line_end', p_ordinal,
    'fingerprint', encode(extensions.digest(p_source_row_id, 'sha256'), 'hex')
  )
$$;

create temp table statement on commit drop as
select public.save_bank_statement_import_v1(
  'direction:import', repeat('e', 64), repeat('f', 64),
  'e8000000-0000-4000-8000-000000000010',
  '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
  jsonb_build_array(
    pg_temp.statement_row('fee', 1, 'debit', 459, 99541,
      'Comision Compras En El Extranjero Oficina Central'),
    pg_temp.statement_row('owner', 2, 'credit', 300000, 399541,
      'Traspaso De: Claudio Catalan')
  )
) as receipt;

create temp table ids on commit drop as
select
  (select (receipt->>'import_id')::uuid from statement) as import_id,
  (select id from public.bank_statement_rows
    where tenant_id = 'e8000000-0000-4000-8000-000000000001'
      and source_row_id = 'fee') as fee,
  (select id from public.bank_statement_rows
    where tenant_id = 'e8000000-0000-4000-8000-000000000001'
      and source_row_id = 'owner') as owner;

select lives_ok(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_id from ids),
    (select revision from public.bank_statement_imports
      where id = (select import_id from ids)),
    'direction:apply',
    jsonb_build_array(
      jsonb_build_object(
        'row_id', (select fee from ids), 'action', 'post_journal',
        'journal', jsonb_build_object(
          'counterpart_account_id', 'e8000000-0000-4000-8000-000000000011',
          'description', 'Comisión bancaria'
        )
      ),
      jsonb_build_object(
        'row_id', (select owner from ids), 'action', 'post_journal',
        'journal', jsonb_build_object(
          'counterpart_account_id', 'e8000000-0000-4000-8000-000000000012',
          'description', 'Aporte de capital'
        )
      )
    )
  ),
  'a charge and a deposit are classified in one apply'
);

select results_eq(
  $$select je.description, jl.account_code, jl.debit_amount::integer,
           jl.credit_amount::integer
      from public.journal_lines jl
      join public.journal_entries je on je.id = jl.entry_id
     where je.tenant_id = 'e8000000-0000-4000-8000-000000000001'
       and je.source_module = 'bank_reconciliation'
     order by je.description, jl.account_code$$,
  $$values
      ('Aporte de capital'::text, '1110'::text, 300000, 0),
      ('Aporte de capital', '3102', 0, 300000),
      ('Comisión bancaria', '1110', 0, 459),
      ('Comisión bancaria', '6601', 459, 0)$$,
  'money out is Debe cuenta / Haber banco; money in is Debe banco / Haber cuenta'
);

select * from finish();
rollback;
