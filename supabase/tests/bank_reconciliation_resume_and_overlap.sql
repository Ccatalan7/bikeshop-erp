begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  not has_function_privilege(
    'authenticated',
    'public.apply_bank_reconciliation_actions_without_terminal_settlements(uuid,bigint,text,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_bank_reconciliation_candidates_v2(uuid,date,date)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.get_bank_reconciliation_candidates_v2(uuid,date,date)',
    'EXECUTE'
  ),
  'the kernel stays private; accountants read the catalog, anonymous callers cannot'
);

insert into public.tenants (id, shop_name, timezone) values
  ('e5000000-0000-4000-8000-000000000001', 'Retoma cartolas', 'America/Santiago');
-- New tenants are seeded with a chart, methods and a card terminal that
-- reference each other both ways; this test brings its own.
set local session_replication_role = replica;
delete from public.payment_terminal_terms
 where tenant_id = 'e5000000-0000-4000-8000-000000000001';
delete from public.payment_terminal_profiles
 where tenant_id = 'e5000000-0000-4000-8000-000000000001';
delete from public.payment_methods
 where tenant_id = 'e5000000-0000-4000-8000-000000000001';
delete from public.accounts
 where tenant_id = 'e5000000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

insert into public.accounts (id, tenant_id, code, name, type, category) values
  ('e5000000-0000-4000-8000-000000000010', 'e5000000-0000-4000-8000-000000000001',
   '1110', 'Banco de Chile', 'asset', 'currentAsset'),
  ('e5000000-0000-4000-8000-000000000011', 'e5000000-0000-4000-8000-000000000001',
   '2105', 'Cuentas por Pagar - Gastos', 'liability', 'currentLiability'),
  ('e5000000-0000-4000-8000-000000000013', 'e5000000-0000-4000-8000-000000000001',
   '6190', 'Gastos generales', 'expense', 'operatingExpense');
insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values
  ('e5000000-0000-4000-8000-000000000020', 'e5000000-0000-4000-8000-000000000001',
   'transfer', 'Transferencia', 'e5000000-0000-4000-8000-000000000010', 'no_tax');

set local session_replication_role = replica;
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e5000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'resume-statements@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'e5000000-0000-4000-8000-000000000003',
  'e5000000-0000-4000-8000-000000000002',
  'e5000000-0000-4000-8000-000000000001',
  'accountant', '{"access_accounting":true}'::jsonb, true
);
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"e5000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', 'e5000000-0000-4000-8000-000000000002', true
);

create function pg_temp.statement_row(
  p_source_row_id text,
  p_ordinal integer,
  p_booking_date date,
  p_amount numeric,
  p_balance numeric,
  p_description text
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

create function pg_temp.expense(p_row_id uuid, p_description text)
returns jsonb language sql as $$
  select jsonb_build_object(
    'row_id', p_row_id, 'action', 'create_expense',
    'expense', jsonb_build_object(
      'account_id', 'e5000000-0000-4000-8000-000000000013',
      'payment_method_id', 'e5000000-0000-4000-8000-000000000020',
      'description', p_description
    )
  )
$$;

create function pg_temp.revision(p_import_id uuid)
returns bigint language sql as $$
  select revision from public.bank_statement_imports where id = p_import_id
$$;

-- Statement A: early September, cut on the 3rd.
create temp table statement_a on commit drop as
select public.save_bank_statement_import_v1(
  'resume:import-a', repeat('a', 64), repeat('b', 64),
  'e5000000-0000-4000-8000-000000000010',
  '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
  jsonb_build_array(
    pg_temp.statement_row('a1', 1, '2026-09-01', 5000, 100000, 'Pago: Google Play'),
    pg_temp.statement_row('a2', 2, '2026-09-02', 7000, 93000, 'App-traspaso A: Vicente Diaz'),
    pg_temp.statement_row('a3', 3, '2026-09-03', 3000, 90000, 'Comision mantencion')
  )
) as receipt;

create temp table ids on commit drop as
select
  (select (receipt->>'import_id')::uuid from statement_a) as import_a,
  (select id from public.bank_statement_rows
    where tenant_id = 'e5000000-0000-4000-8000-000000000001' and source_row_id = 'a1') as a1,
  (select id from public.bank_statement_rows
    where tenant_id = 'e5000000-0000-4000-8000-000000000001' and source_row_id = 'a2') as a2,
  (select id from public.bank_statement_rows
    where tenant_id = 'e5000000-0000-4000-8000-000000000001' and source_row_id = 'a3') as a3;

-- First sitting: only the subscription is settled; the rest stays open.
select lives_ok(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_a from ids), pg_temp.revision((select import_a from ids)),
    'resume:apply-a-1',
    jsonb_build_array(
      pg_temp.expense((select a1 from ids), 'Suscripción Google'),
      jsonb_build_object('row_id', (select a2 from ids), 'action', 'pending'),
      jsonb_build_object('row_id', (select a3 from ids), 'action', 'pending')
    )
  ),
  'a statement is applied with rows left pending'
);

create temp table first_sitting on commit drop as
select decision.decided_at, decision.generated_target_id,
       (decision.action_snapshot->>'expense_payment_id')::uuid as payment_id
  from public.bank_reconciliation_row_decisions decision
 where decision.row_id = (select a1 from ids);

select throws_like(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_a from ids), pg_temp.revision((select import_a from ids)),
    'resume:apply-a-redecide',
    jsonb_build_array(
      jsonb_build_object('row_id', (select a1 from ids), 'action', 'pending'),
      jsonb_build_object('row_id', (select a2 from ids), 'action', 'pending'),
      jsonb_build_object('row_id', (select a3 from ids), 'action', 'pending')
    )
  ),
  '%bank_reconciliation_row_already_decided%',
  'a decided row is final: a later apply cannot reopen it'
);

select throws_like(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_a from ids), pg_temp.revision((select import_a from ids)),
    'resume:apply-a-partial',
    jsonb_build_array(
      jsonb_build_object('row_id', (select a2 from ids), 'action', 'pending')
    )
  ),
  '%bank_reconciliation_action_coverage_invalid%',
  'a later apply still covers every open row'
);

-- Second sitting: the statement created an expense, and it can still be
-- finished (it was refused as generated_review_immutable before).
select lives_ok(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_a from ids), pg_temp.revision((select import_a from ids)),
    'resume:apply-a-2',
    jsonb_build_array(
      pg_temp.expense((select a2 from ids), 'Reembolso repuesto a Vicente'),
      jsonb_build_object(
        'row_id', (select a3 from ids), 'action', 'dismiss',
        'reason', 'Cargo del banco revisado aparte'
      )
    )
  ),
  'the rows left pending are resolved in a later sitting'
);

select results_eq(
  $$select decision.disposition
      from public.bank_reconciliation_row_decisions decision
      join public.bank_statement_rows row on row.id = decision.row_id
     where decision.import_id = (select import_a from ids)
     order by row.ordinal$$,
  $$values ('reconciled'::text), ('reconciled'), ('ignored')$$,
  'every row of the statement ends decided'
);

select ok(
  (select decision.decided_at = first_sitting.decided_at
          and decision.generated_target_id = first_sitting.generated_target_id
     from public.bank_reconciliation_row_decisions decision, first_sitting
    where decision.row_id = (select a1 from ids))
  and (select count(*) from public.expenses
        where tenant_id = 'e5000000-0000-4000-8000-000000000001') = 2,
  'the first sitting is kept as it was; nothing is created twice'
);

select is(
  (select status from public.bank_statement_imports
    where id = (select import_a from ids)),
  'partially_reconciled',
  'a dismissed row keeps the statement partially reconciled'
);

-- The catalog shows what is settled and stops offering what a row explains.
create temp table catalog_a on commit drop as
select public.get_bank_reconciliation_candidates_v2(
  'e5000000-0000-4000-8000-000000000010', '2026-08-15', '2026-09-30'
) as payload;

select results_eq(
  $$select item->>'source_row_id', item->>'file_sha256', item->>'disposition'
      from catalog_a,
           jsonb_array_elements(payload->'reconciled_rows') item
     order by item->>'source_row_id'$$,
  $$values ('a1'::text, repeat('a', 64), 'reconciled'::text),
           ('a2', repeat('a', 64), 'reconciled'),
           ('a3', repeat('a', 64), 'ignored')$$,
  'reconciled_rows names each settled row by its statement and row'
);

select ok(
  not exists (
    select 1
      from catalog_a, jsonb_array_elements(payload->'candidates') item
     where item->>'target_id' in (
       select allocation.target_id::text
         from public.bank_reconciliation_allocations allocation
        where allocation.import_id = (select import_a from ids)
     )
  ),
  'an operation a row already explains is not offered again'
);

-- Statement B: the full month, overlapping A from the 2nd.
create temp table statement_b on commit drop as
select public.save_bank_statement_import_v1(
  'resume:import-b', repeat('c', 64), repeat('b', 64),
  'e5000000-0000-4000-8000-000000000010',
  '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
  jsonb_build_array(
    pg_temp.statement_row('b1', 1, '2026-09-02', 7000, 93000, 'App-traspaso A: Vicente Diaz Internet'),
    pg_temp.statement_row('b2', 2, '2026-09-04', 2000, 88000, 'Pago: Correos de Chile')
  )
) as receipt;

create temp table ids_b on commit drop as
select
  (select (receipt->>'import_id')::uuid from statement_b) as import_b,
  (select id from public.bank_statement_rows
    where tenant_id = 'e5000000-0000-4000-8000-000000000001' and source_row_id = 'b1') as b1,
  (select id from public.bank_statement_rows
    where tenant_id = 'e5000000-0000-4000-8000-000000000001' and source_row_id = 'b2') as b2;

select throws_like(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_b from ids_b), pg_temp.revision((select import_b from ids_b)),
    'resume:apply-b-twice',
    jsonb_build_array(
      pg_temp.expense((select b1 from ids_b), 'Reembolso otra vez'),
      jsonb_build_object('row_id', (select b2 from ids_b), 'action', 'pending')
    )
  ),
  '%bank_reconciliation_row_settled_elsewhere%',
  'a movement another statement settled cannot be booked again'
);

select throws_like(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_b from ids_b), pg_temp.revision((select import_b from ids_b)),
    'resume:apply-b-unproven',
    jsonb_build_array(
      jsonb_build_object('row_id', (select b1 from ids_b), 'action', 'pending'),
      jsonb_build_object(
        'row_id', (select b2 from ids_b), 'action', 'dismiss',
        'reason', 'Conciliado en otra cartola', 'settled_elsewhere', true
      )
    )
  ),
  '%bank_reconciliation_settled_elsewhere_unproven%',
  'settled elsewhere is proven, not claimed'
);

select lives_ok(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_b from ids_b), pg_temp.revision((select import_b from ids_b)),
    'resume:apply-b',
    jsonb_build_array(
      jsonb_build_object(
        'row_id', (select b1 from ids_b), 'action', 'dismiss',
        'reason', 'Conciliado en otra cartola', 'settled_elsewhere', true
      ),
      pg_temp.expense((select b2 from ids_b), 'Envío Correos')
    )
  ),
  'the repeated movement is recorded as settled elsewhere; the new one is booked'
);

select is(
  (select count(*)::integer from public.expenses
    where tenant_id = 'e5000000-0000-4000-8000-000000000001'),
  3,
  'the overlap created no second expense'
);

create temp table catalog_b on commit drop as
select public.get_bank_reconciliation_candidates_v2(
  'e5000000-0000-4000-8000-000000000010', '2026-08-15', '2026-09-30'
) as payload;

select ok(
  exists (
    select 1 from catalog_b, jsonb_array_elements(payload->'reconciled_rows') item
     where item->>'source_row_id' = 'b1'
       and (item->>'settled_elsewhere')::boolean
  )
  and not exists (
    select 1 from catalog_b, jsonb_array_elements(payload->'decisions') item
     where item->>'action' = 'dismiss' and (item->>'amount')::numeric = 7000
  )
  and exists (
    select 1 from catalog_b, jsonb_array_elements(payload->'decisions') item
     where item->>'action' = 'dismiss' and (item->>'amount')::numeric = 3000
  ),
  'a settled-elsewhere dismissal is shown as settled but never taught as a dismissal'
);

select * from finish();
rollback;
