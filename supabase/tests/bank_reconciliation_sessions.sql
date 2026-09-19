begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  has_function_privilege('authenticated',
    'public.open_bank_reconciliation_session_v1(uuid,uuid[])', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.save_bank_reconciliation_session_draft_v1(uuid,bigint,jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.list_bank_reconciliation_sessions_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.open_bank_reconciliation_session_v1(uuid,uuid[])', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.save_bank_reconciliation_session_draft_v1(uuid,bigint,jsonb)', 'EXECUTE')
  and not has_table_privilege('authenticated',
    'public.bank_reconciliation_sessions', 'UPDATE'),
  'accountants open, save and list conciliations only through the functions'
);

insert into public.tenants (id, shop_name, timezone) values
  ('e6000000-0000-4000-8000-000000000001', 'Borradores', 'America/Santiago'),
  ('e6000000-0000-4000-8000-000000000101', 'Otra tienda', 'America/Santiago');
set local session_replication_role = replica;
delete from public.payment_terminal_terms
 where tenant_id in ('e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000101');
delete from public.payment_terminal_profiles
 where tenant_id in ('e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000101');
delete from public.payment_methods
 where tenant_id in ('e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000101');
delete from public.accounts
 where tenant_id in ('e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000101');
set local session_replication_role = origin;

insert into public.accounts (id, tenant_id, code, name, type, category) values
  ('e6000000-0000-4000-8000-000000000010', 'e6000000-0000-4000-8000-000000000001',
   '1110', 'Banco de Chile', 'asset', 'currentAsset'),
  ('e6000000-0000-4000-8000-000000000013', 'e6000000-0000-4000-8000-000000000001',
   '6190', 'Gastos generales', 'expense', 'operatingExpense'),
  ('e6000000-0000-4000-8000-000000000110', 'e6000000-0000-4000-8000-000000000101',
   '1110', 'Banco ajeno', 'asset', 'currentAsset');
insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values
  ('e6000000-0000-4000-8000-000000000020', 'e6000000-0000-4000-8000-000000000001',
   'transfer', 'Transferencia', 'e6000000-0000-4000-8000-000000000010', 'no_tax');

set local session_replication_role = replica;
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e6000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'drafts@example.invalid', '', now(), '{"account_type":"erp_staff"}'::jsonb,
   '{}'::jsonb, now(), now()),
  ('e6000000-0000-4000-8000-000000000102', 'authenticated', 'authenticated',
   'other-shop@example.invalid', '', now(), '{"account_type":"erp_staff"}'::jsonb,
   '{}'::jsonb, now(), now());
insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values
  ('e6000000-0000-4000-8000-000000000003', 'e6000000-0000-4000-8000-000000000002',
   'e6000000-0000-4000-8000-000000000001', 'accountant',
   '{"access_accounting":true}'::jsonb, true),
  ('e6000000-0000-4000-8000-000000000103', 'e6000000-0000-4000-8000-000000000102',
   'e6000000-0000-4000-8000-000000000101', 'accountant',
   '{"access_accounting":true}'::jsonb, true);
set local session_replication_role = origin;

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

select pg_temp.act_as('e6000000-0000-4000-8000-000000000002');

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

create temp table imports on commit drop as
select
  (public.save_bank_statement_import_v1(
    'drafts:import-june', repeat('c', 64), null,
    'e6000000-0000-4000-8000-000000000010',
    '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
    jsonb_build_array(
      pg_temp.statement_row('j1', 1, '2026-06-01', 98000, 500000, 'App-traspaso A: Maria Angelica'),
      pg_temp.statement_row('j2', 2, '2026-06-09', 1328, 498672, 'Pago: Google Cloud')
    )
  )->>'import_id')::uuid as june,
  (public.save_bank_statement_import_v1(
    'drafts:import-july', repeat('d', 64), null,
    'e6000000-0000-4000-8000-000000000010',
    '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
    jsonb_build_array(
      pg_temp.statement_row('k1', 1, '2026-07-07', 133000, 365672, 'App-traspaso A: Maria Angelica')
    )
  )->>'import_id')::uuid as july;

create temp table opened on commit drop as
select public.open_bank_reconciliation_session_v1(
  'e6000000-0000-4000-8000-000000000010',
  array[(select june from imports), (select july from imports)]
) as receipt;

select ok(
  (select (receipt->>'created')::boolean from opened)
  and (select receipt->'draft' from opened) = '{}'::jsonb
  and (select jsonb_array_length(receipt->'import_ids') from opened) = 2,
  'two statements imported together open one new conciliation with an empty draft'
);

select is(
  (select count(distinct session_id)::int from public.bank_statement_imports
    where tenant_id = 'e6000000-0000-4000-8000-000000000001'
      and id in ((select june from imports), (select july from imports))),
  1,
  'both statements belong to it'
);

select is(
  (public.save_bank_reconciliation_session_draft_v1(
    (select (receipt->>'session_id')::uuid from opened), 1,
    '{"version":1,"rows":{"c:j1":{"resolution":{"action":"split"}}}}'::jsonb
  )->>'revision')::bigint,
  2::bigint,
  'a draft is saved over the revision the screen saw'
);

select throws_like(
  format(
    'select public.save_bank_reconciliation_session_draft_v1(%L, 1, %L)',
    (select receipt->>'session_id' from opened), '{"version":1,"rows":{}}'
  ),
  '%bank_reconciliation_draft_conflict%',
  'a screen that did not see the last save cannot overwrite it'
);

select ok(
  (select (receipt->>'created')::boolean = false
          and receipt->'draft'->'rows' ? 'c:j1'
          and (receipt->>'revision')::bigint = 2
     from (select public.open_bank_reconciliation_session_v1(
       'e6000000-0000-4000-8000-000000000010',
       array[(select july from imports)]
     ) as receipt) reopened),
  'opening one of its statements again resumes the same conciliation and its draft'
);

create temp table listed on commit drop as
select public.list_bank_reconciliation_sessions_v1(
  'e6000000-0000-4000-8000-000000000010'
) as items;

select ok(
  (select jsonb_array_length(items) = 1
          and (items->0->>'statement_count')::int = 2
          and (items->0->>'movement_count')::int = 3
          and (items->0->>'decided_count')::int = 0
          and (items->0->>'first_date') = '2026-06-01'
          and (items->0->>'last_date') = '2026-07-07'
          and (items->0->>'draft_rows')::int = 1
          and (items->0->>'draft_decisions')::int = 1
          and (items->0->>'draft_analyses')::int = 0
     from listed),
  'the list says how many statements, movements and draft decisions it holds'
);

-- What a statement already applied is no longer «sin aplicar», even while
-- the draft still carries it.
select lives_ok(
  format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select june from imports),
    (select revision from public.bank_statement_imports
      where id = (select june from imports)),
    'drafts:apply-june',
    jsonb_build_array(
      jsonb_build_object(
        'row_id', (select id from public.bank_statement_rows
                    where import_id = (select june from imports)
                      and source_row_id = 'j1'),
        'action', 'dismiss', 'reason', 'Duplicado confirmado'
      ),
      jsonb_build_object(
        'row_id', (select id from public.bank_statement_rows
                    where import_id = (select june from imports)
                      and source_row_id = 'j2'),
        'action', 'pending'
      )
    )
  ),
  'one June movement is applied'
);

-- The screen has not saved since: the draft still carries the applied one.
select is(
  (public.save_bank_reconciliation_session_draft_v1(
    (select (receipt->>'session_id')::uuid from opened), 2,
    jsonb_build_object('version', 1, 'rows', jsonb_build_object(
      repeat('c', 64) || ':j1',
      '{"resolution":{"action":"dismiss","reason":"Duplicado confirmado"},"ai":{"explanation":"Duplicado"}}'::jsonb,
      repeat('c', 64) || ':j2',
      '{"resolution":{"action":"split"},"ai":{"explanation":"Google"}}'::jsonb
    ))
  )->>'revision')::bigint,
  3::bigint,
  'the draft is saved with both movements'
);

select ok(
  (select (items->0->>'decided_count')::int = 1
              and (items->0->>'draft_rows')::int = 1
              and (items->0->>'draft_decisions')::int = 1
              and (items->0->>'draft_analyses')::int = 1
         from (select public.list_bank_reconciliation_sessions_v1(
           'e6000000-0000-4000-8000-000000000010') as items) relisted),
  'the list counts only the draft decisions a statement has not applied'
);

-- Another shop sees nothing of it and cannot write to it.
select pg_temp.act_as('e6000000-0000-4000-8000-000000000102');

select is(
  public.list_bank_reconciliation_sessions_v1('e6000000-0000-4000-8000-000000000010'),
  '[]'::jsonb,
  'another tenant lists nothing for an account that is not its own'
);

select throws_like(
  format(
    'select public.save_bank_reconciliation_session_draft_v1(%L, 2, %L)',
    (select receipt->>'session_id' from opened), '{"version":1,"rows":{}}'
  ),
  '%bank_reconciliation_session_not_accessible%',
  'another tenant cannot save over the draft'
);

select throws_like(
  format(
    'select public.open_bank_reconciliation_session_v1(%L, %L)',
    'e6000000-0000-4000-8000-000000000010',
    array[(select june from imports)]
  ),
  '%bank_statement_import_not_accessible%',
  'another tenant cannot open a statement that is not its own'
);

select * from finish();
rollback;
