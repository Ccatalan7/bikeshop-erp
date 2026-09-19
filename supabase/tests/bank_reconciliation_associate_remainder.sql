begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

insert into public.tenants (id, shop_name, timezone) values
  ('e7000000-0000-4000-8000-000000000001', 'Vincula y registra el resto', 'America/Santiago');
-- New tenants are seeded with a chart, methods and a card terminal that
-- reference each other both ways; this test brings its own.
set local session_replication_role = replica;
delete from public.payment_terminal_terms
 where tenant_id = 'e7000000-0000-4000-8000-000000000001';
delete from public.payment_terminal_profiles
 where tenant_id = 'e7000000-0000-4000-8000-000000000001';
delete from public.payment_methods
 where tenant_id = 'e7000000-0000-4000-8000-000000000001';
delete from public.accounts
 where tenant_id = 'e7000000-0000-4000-8000-000000000001';
set local session_replication_role = origin;

insert into public.accounts (id, tenant_id, code, name, type, category) values
  ('e7000000-0000-4000-8000-000000000010', 'e7000000-0000-4000-8000-000000000001',
   '1110', 'Banco de Chile', 'asset', 'currentAsset'),
  ('e7000000-0000-4000-8000-000000000011', 'e7000000-0000-4000-8000-000000000001',
   '4100', 'Ingresos Operacionales', 'income', 'operatingIncome'),
  ('e7000000-0000-4000-8000-000000000012', 'e7000000-0000-4000-8000-000000000001',
   '1130', 'Cuentas por Cobrar Comerciales', 'asset', 'currentAsset');

-- Carlos Sánchez's $7.000 workshop sale, collected «by transfer» on 7 July
-- and entered as a journal against the bank. A second copy was posted by a
-- sales payment: that one is the payment's money and never a target of its
-- own.
set local session_replication_role = replica;
insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type, source_module,
  source_reference, status, total_debit, total_credit
) values
  ('e7000000-0000-4000-8000-000000000040', 'e7000000-0000-4000-8000-000000000001',
   'AC-1', '2026-07-07 12:00:00+00', 'Cobro FV-00836 - Transferencia',
   'adjustment', 'journal_entries', 'FV-00836', 'posted', 7000, 7000),
  ('e7000000-0000-4000-8000-000000000041', 'e7000000-0000-4000-8000-000000000001',
   'AC-2', '2026-07-07 12:00:00+00', 'Pago factura FV-00836 - Transferencia',
   'adjustment', 'sales_payments', 'FV-00836', 'posted', 7000, 7000),
  ('e7000000-0000-4000-8000-000000000042', 'e7000000-0000-4000-8000-000000000001',
   'AC-3', '2026-07-07 12:00:00+00', 'Gasto pagado (legado)',
   'adjustment', 'expenses', 'GTO-1', 'posted', 7000, 7000);
insert into public.journal_lines (
  tenant_id, entry_id, account_id, account_code, account_name, description,
  debit_amount, credit_amount
)
select 'e7000000-0000-4000-8000-000000000001', entry.id, line.account_id,
       line.code, line.name, 'Pago FV-00836', line.debit, line.credit
  from (values ('e7000000-0000-4000-8000-000000000040'::uuid),
               ('e7000000-0000-4000-8000-000000000041'::uuid),
               ('e7000000-0000-4000-8000-000000000042'::uuid)) entry(id)
 cross join (values
   ('e7000000-0000-4000-8000-000000000010'::uuid, '1110', 'Banco de Chile', 7000, 0),
   ('e7000000-0000-4000-8000-000000000012'::uuid, '1130',
    'Cuentas por Cobrar Comerciales', 0, 7000)
 ) line(account_id, code, name, debit, credit);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'e7000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'associate-remainder@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);
insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'e7000000-0000-4000-8000-000000000003',
  'e7000000-0000-4000-8000-000000000002',
  'e7000000-0000-4000-8000-000000000001',
  'accountant', '{"access_accounting":true}'::jsonb, true
);
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"e7000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub', 'e7000000-0000-4000-8000-000000000002', true
);

create temp table statement on commit drop as
select public.save_bank_statement_import_v1(
  'remainder:import', repeat('c', 64), repeat('d', 64),
  'e7000000-0000-4000-8000-000000000010',
  '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
  jsonb_build_array(jsonb_build_object(
    'source_row_id', 'carlos', 'ordinal', 1,
    'booking_date', '2026-07-07', 'operation_date', null,
    'direction', 'credit', 'amount', 18000,
    'description', 'Traspaso De: Carlos Aurelio Sanchez Internet Sanchez',
    'normalized_description', 'traspaso de carlos aurelio sanchez internet sanchez',
    'counterparty_observed', null, 'document_number', null,
    'balance', 500000, 'warning_codes', '[]'::jsonb, 'source_page', 1,
    'source_line_start', 1, 'source_line_end', 1,
    'fingerprint', encode(extensions.digest('carlos', 'sha256'), 'hex')
  ))
) as receipt;

create temp table ids on commit drop as
select
  (select (receipt->>'import_id')::uuid from statement) as import_id,
  (select id from public.bank_statement_rows
    where tenant_id = 'e7000000-0000-4000-8000-000000000001'
      and source_row_id = 'carlos') as carlos;

-- The sale linked for what it is, and optionally what it leaves of the
-- movement booked to an account.
create function pg_temp.link(
  p_bank_amount numeric, p_remainder jsonb,
  p_target uuid default 'e7000000-0000-4000-8000-000000000040',
  p_provider text default 'none'
)
returns jsonb language sql as $$
  select jsonb_build_object(
    'row_id', (select carlos from ids), 'action', 'associate_existing',
    'allocations', jsonb_build_array(jsonb_build_object(
      'row_id', (select carlos from ids),
      'target_kind', 'journal_entry',
      'target_id', p_target,
      'bank_amount', p_bank_amount, 'target_amount', 7000,
      'match_kind', 'manual', 'confidence', 'medium',
      'provider', p_provider, 'instrument', 'unknown'
    ))
  ) || case when p_remainder is null then '{}'::jsonb
       else jsonb_build_object('remainder', p_remainder) end
$$;

create function pg_temp.apply(p_key text, p_action jsonb)
returns text language sql as $$
  select format(
    'select public.apply_bank_reconciliation_actions_v3(%L, %s, %L, %L)',
    (select import_id from ids),
    (select revision from public.bank_statement_imports
      where id = (select import_id from ids)),
    p_key, jsonb_build_array(p_action)
  )
$$;

create function pg_temp.rest(p_account text, p_description text)
returns jsonb language sql as $$
  select jsonb_build_object('account_id', p_account, 'description', p_description)
$$;

select throws_like(
  pg_temp.apply('remainder:none', pg_temp.link(7000, null)),
  '%bank_reconciliation_row_not_fully_allocated%',
  'without a remainder the operations still have to add up'
);

select throws_like(
  pg_temp.apply('remainder:bank', pg_temp.link(7000, pg_temp.rest(
    'e7000000-0000-4000-8000-000000000010', 'Al propio banco'))),
  '%bank_reconciliation_counterpart_account_invalid%',
  'the rest cannot go back to the bank account itself'
);

select throws_like(
  pg_temp.apply('remainder:blank', pg_temp.link(7000, pg_temp.rest(
    'e7000000-0000-4000-8000-000000000011', ' '))),
  '%bank_reconciliation_remainder_invalid%',
  'the rest needs what it was'
);

select throws_like(
  pg_temp.apply('remainder:over-linked', pg_temp.link(18000, null)),
  '%bank_reconciliation_allocation_invalid%',
  'a sale chosen by hand is never linked for $11.000 more than it is'
);

select throws_like(
  pg_temp.apply('remainder:payment-journal', pg_temp.link(7000, pg_temp.rest(
    'e7000000-0000-4000-8000-000000000011', 'Venta no registrada'),
    'e7000000-0000-4000-8000-000000000041')),
  '%bank_reconciliation_target_is_payment_journal%',
  'the journal a sales payment posted is never linked apart from its payment'
);

select throws_like(
  pg_temp.apply('remainder:legacy-expense-journal', pg_temp.link(7000,
    pg_temp.rest('e7000000-0000-4000-8000-000000000011', 'Venta no registrada'),
    'e7000000-0000-4000-8000-000000000042')),
  '%bank_reconciliation_target_is_payment_journal%',
  'the journal of a legacy paid expense is never linked apart from it'
);

-- A settlement is one because the terminal adapter marked it, not because
-- the caller wrote a provider: this one is bounded like any manual link.
select throws_like(
  pg_temp.apply('remainder:card-manual', pg_temp.link(5500,
    pg_temp.rest('e7000000-0000-4000-8000-000000000011', 'Venta no registrada'),
    'e7000000-0000-4000-8000-000000000040', 'transbank')),
  '%bank_reconciliation_allocation_invalid%',
  'a manual link is bounded at $1.000 whatever provider it claims'
);

select lives_ok(
  pg_temp.apply('remainder:carlos', pg_temp.link(7000, pg_temp.rest(
    'e7000000-0000-4000-8000-000000000011',
    'Venta no registrada · Carlos Sanchez'))),
  'the sale is linked and the rest is booked in one apply'
);

select results_eq(
  $$select jl.account_code, jl.debit_amount::integer, jl.credit_amount::integer
      from public.journal_lines jl
      join public.journal_entries je on je.id = jl.entry_id
     where je.tenant_id = 'e7000000-0000-4000-8000-000000000001'
       and je.source_module = 'bank_reconciliation'
     order by jl.account_code$$,
  $$values ('1110'::text, 11000, 0), ('4100', 0, 11000)$$,
  'what the sale leaves is one balanced journal: Debe banco / Haber ingresos'
);

select results_eq(
  $$select target_kind, bank_amount::integer, target_amount::integer
      from public.bank_reconciliation_allocations
     where row_id = (select carlos from ids)
     order by bank_amount$$,
  $$values ('journal_entry'::text, 7000, 7000), ('journal_entry', 11000, 11000)$$,
  'the sale keeps its own amount and the journal takes the rest'
);

select ok(
  (select action_kind = 'associate_existing'
          and disposition = 'reconciled'
          and generated_target_kind = 'journal_entry'
          and (action_snapshot->'remainder'->>'amount')::numeric = 11000
          and action_snapshot->'remainder'->>'description'
                = 'Venta no registrada · Carlos Sanchez'
     from public.bank_reconciliation_row_decisions
    where row_id = (select carlos from ids)),
  'the decision records the link and the journal it made'
);

select * from finish();
rollback;
