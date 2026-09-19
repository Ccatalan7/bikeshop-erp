begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

insert into public.tenants (id, shop_name, timezone) values
  ('e6000000-0000-4000-8000-000000000001', 'Divide movimientos', 'America/Santiago'),
  ('e6000000-0000-4000-8000-000000000901', 'Otro taller', 'America/Santiago');
-- New tenants are seeded with a chart, methods and a card terminal that
-- reference each other both ways; this test brings its own.
set local session_replication_role = replica;
delete from public.payment_terminal_terms
 where tenant_id in (
   'e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000901'
 );
delete from public.payment_terminal_profiles
 where tenant_id in (
   'e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000901'
 );
delete from public.payment_methods
 where tenant_id in (
   'e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000901'
 );
delete from public.accounts
 where tenant_id in (
   'e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000901'
 );
set local session_replication_role = origin;

insert into public.accounts (id, tenant_id, code, name, type, category) values
  ('e6000000-0000-4000-8000-000000000010', 'e6000000-0000-4000-8000-000000000001',
   '1110', 'Banco de Chile', 'asset', 'currentAsset'),
  ('e6000000-0000-4000-8000-000000000011', 'e6000000-0000-4000-8000-000000000001',
   '2105', 'Cuentas por Pagar - Gastos', 'liability', 'currentLiability'),
  ('e6000000-0000-4000-8000-000000000012', 'e6000000-0000-4000-8000-000000000001',
   '2150', 'IVA Débito Fiscal', 'liability', 'currentLiability'),
  ('e6000000-0000-4000-8000-000000000013', 'e6000000-0000-4000-8000-000000000001',
   '6103', 'Honorarios Profesionales', 'expense', 'operatingExpense'),
  ('e6000000-0000-4000-8000-000000000014', 'e6000000-0000-4000-8000-000000000001',
   '6502', 'Patentes y Contribuciones', 'expense', 'taxExpense');
insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values
  ('e6000000-0000-4000-8000-000000000020', 'e6000000-0000-4000-8000-000000000001',
   'transfer', 'Transferencia', 'e6000000-0000-4000-8000-000000000010', 'no_tax');
insert into public.suppliers (id, tenant_id, name) values
  ('e6000000-0000-4000-8000-000000000030', 'e6000000-0000-4000-8000-000000000001',
   'Pedro Madrid'),
  ('e6000000-0000-4000-8000-000000000031', 'e6000000-0000-4000-8000-000000000001',
   'Municipalidad de Viña del Mar'),
  ('e6000000-0000-4000-8000-000000000930', 'e6000000-0000-4000-8000-000000000901',
   'Contador ajeno');

set local session_replication_role = replica;
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e6000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'split-movement@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'e6000000-0000-4000-8000-000000000003',
  'e6000000-0000-4000-8000-000000000002',
  'e6000000-0000-4000-8000-000000000001',
  'accountant', '{"access_accounting":true}'::jsonb, true
);
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"e6000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', 'e6000000-0000-4000-8000-000000000002', true
);

create function pg_temp.statement_row(
  p_source_row_id text, p_ordinal integer, p_booking_date date,
  p_direction text, p_amount numeric, p_balance numeric, p_description text
) returns jsonb language sql as $$
  select jsonb_build_object(
    'source_row_id', p_source_row_id, 'ordinal', p_ordinal,
    'booking_date', p_booking_date, 'operation_date', null,
    'direction', p_direction, 'amount', p_amount,
    'description', p_description,
    'normalized_description', lower(p_description),
    'counterparty_observed', null, 'document_number', null,
    'balance', p_balance, 'warning_codes', '[]'::jsonb, 'source_page', 1,
    'source_line_start', p_ordinal, 'source_line_end', p_ordinal,
    'fingerprint', encode(extensions.digest(p_source_row_id, 'sha256'), 'hex')
  )
$$;

create function pg_temp.part(
  p_account text, p_amount numeric, p_description text, p_supplier text default null
) returns jsonb language sql as $$
  select jsonb_build_object(
    'account_id', p_account, 'amount', p_amount, 'description', p_description
  ) || case when p_supplier is null then '{}'::jsonb
       else jsonb_build_object('supplier_id', p_supplier) end
$$;

create function pg_temp.split(p_row_id uuid, p_parts jsonb)
returns jsonb language sql as $$
  select jsonb_build_object(
    'row_id', p_row_id, 'action', 'split',
    'split', jsonb_build_object(
      'payment_method_id', 'e6000000-0000-4000-8000-000000000020',
      'parts', p_parts
    )
  )
$$;

create function pg_temp.revision(p_import_id uuid)
returns bigint language sql as $$
  select revision from public.bank_statement_imports where id = p_import_id
$$;

create temp table statement on commit drop as
select public.save_bank_statement_import_v1(
  'split:import', repeat('a', 64), repeat('b', 64),
  'e6000000-0000-4000-8000-000000000010',
  '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
  jsonb_build_array(
    pg_temp.statement_row('mother', 1, '2026-08-17', 'debit', 214685, 800000,
      'App-traspaso A: Maria Angelica Sandoval'),
    pg_temp.statement_row('deposit', 2, '2026-08-18', 'credit', 30000, 830000,
      'Traspaso De: Cliente')
  )
) as receipt;

create temp table ids on commit drop as
select
  (select (receipt->>'import_id')::uuid from statement) as import_id,
  (select id from public.bank_statement_rows
    where tenant_id = 'e6000000-0000-4000-8000-000000000001' and source_row_id = 'mother') as mother,
  (select id from public.bank_statement_rows
    where tenant_id = 'e6000000-0000-4000-8000-000000000001' and source_row_id = 'deposit') as deposit;

create function pg_temp.apply(p_key text, p_mother jsonb, p_deposit jsonb)
returns text language sql as $$
  select format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_id from ids), pg_temp.revision((select import_id from ids)),
    p_key, jsonb_build_array(p_mother, p_deposit)
  )
$$;

create function pg_temp.pending_deposit() returns jsonb language sql as $$
  select jsonb_build_object('row_id', (select deposit from ids), 'action', 'pending')
$$;

select throws_like(
  pg_temp.apply('split:short', pg_temp.split((select mother from ids), jsonb_build_array(
    pg_temp.part('e6000000-0000-4000-8000-000000000013', 50000, 'Honorarios contador'),
    pg_temp.part('e6000000-0000-4000-8000-000000000012', 90149, 'F29 de junio')
  )), pg_temp.pending_deposit()),
  '%bank_reconciliation_split_total_mismatch%',
  'the parts must add up to the movement'
);

select throws_like(
  pg_temp.apply('split:foreign-supplier', pg_temp.split((select mother from ids), jsonb_build_array(
    pg_temp.part('e6000000-0000-4000-8000-000000000013', 50000, 'Honorarios contador',
      'e6000000-0000-4000-8000-000000000930'),
    pg_temp.part('e6000000-0000-4000-8000-000000000012', 164685, 'F29 y patente')
  )), pg_temp.pending_deposit()),
  '%bank_reconciliation_split_supplier_invalid%',
  'a supplier of another shop is refused'
);

select throws_like(
  pg_temp.apply('split:bank-line', pg_temp.split((select mother from ids), jsonb_build_array(
    pg_temp.part('e6000000-0000-4000-8000-000000000010', 50000, 'Al propio banco'),
    pg_temp.part('e6000000-0000-4000-8000-000000000012', 164685, 'F29 y patente')
  )), pg_temp.pending_deposit()),
  '%bank_reconciliation_counterpart_account_invalid%',
  'a part cannot go back to the bank account itself'
);

select throws_like(
  pg_temp.apply('split:credit-expense',
    jsonb_build_object('row_id', (select mother from ids), 'action', 'pending'),
    pg_temp.split((select deposit from ids), jsonb_build_array(
      pg_temp.part('e6000000-0000-4000-8000-000000000013', 10000, 'Honorarios'),
      pg_temp.part('e6000000-0000-4000-8000-000000000012', 20000, 'IVA')
    ))),
  '%bank_reconciliation_split_expense_needs_debit%',
  'money coming in is never booked as an expense'
);

select lives_ok(
  pg_temp.apply('split:mother', pg_temp.split((select mother from ids), jsonb_build_array(
    pg_temp.part('e6000000-0000-4000-8000-000000000013', 50000,
      'Honorarios contador julio', 'e6000000-0000-4000-8000-000000000030'),
    pg_temp.part('e6000000-0000-4000-8000-000000000014', 74536,
      'Patente comercial 2º semestre 2026', 'e6000000-0000-4000-8000-000000000031'),
    pg_temp.part('e6000000-0000-4000-8000-000000000012', 90149, 'F29 de junio')
  )), pg_temp.pending_deposit()),
  'the repayment to the owner''s mother is split in one apply'
);

select results_eq(
  $$select e.supplier_id::text, e.supplier_name, e.total_amount::integer,
           e.payment_status, l.account_code
      from public.expenses e
      join public.expense_lines l on l.expense_id = e.id
     where e.tenant_id = 'e6000000-0000-4000-8000-000000000001'
     order by e.total_amount$$,
  $$values
      ('e6000000-0000-4000-8000-000000000030'::text, 'Pedro Madrid'::text, 50000, 'paid'::text, '6103'::text),
      ('e6000000-0000-4000-8000-000000000031', 'Municipalidad de Viña del Mar', 74536, 'paid', '6502')$$,
  'each expense part is a paid expense with its supplier and account'
);

select results_eq(
  $$select jl.account_code, jl.debit_amount::integer, jl.credit_amount::integer
      from public.journal_lines jl
      join public.journal_entries je on je.id = jl.entry_id
     where je.tenant_id = 'e6000000-0000-4000-8000-000000000001'
       and je.source_module = 'bank_reconciliation'
     order by jl.account_code$$,
  $$values ('1110'::text, 0, 90149), ('2150', 90149, 0)$$,
  'the non-expense part is one balanced journal against the bank'
);

select ok(
  (select sum(bank_amount) from public.bank_reconciliation_allocations
    where row_id = (select mother from ids)) = 214685
  and (select count(*) from public.bank_reconciliation_allocations
        where row_id = (select mother from ids)) = 3
  and (select action_kind = 'split'
              and disposition = 'reconciled'
              and jsonb_array_length(action_snapshot->'parts') = 3
         from public.bank_reconciliation_row_decisions
        where row_id = (select mother from ids)),
  'the movement is fully explained by its three parts'
);

create temp table catalog on commit drop as
select public.get_bank_reconciliation_candidates_v2(
  'e6000000-0000-4000-8000-000000000010', '2026-08-01', '2026-08-31'
) as payload;

select ok(
  exists (
    select 1 from catalog, jsonb_array_elements(payload->'decisions') item
     where item->>'action' = 'split'
       and jsonb_array_length(item->'parts') = 3
  ),
  'the next review learns the split'
);

select * from finish();
rollback;
