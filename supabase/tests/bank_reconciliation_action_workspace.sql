begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  to_regprocedure(
    'public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)'
  ) is not null
  and has_function_privilege(
    'authenticated',
    'public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.bank_reconciliation_target_snapshot(uuid,uuid,text,uuid)',
    'EXECUTE'
  ),
  'the action workspace is authenticated and its target projection stays sealed'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'bank_reconciliation_row_decisions'
      and column_name = 'action_kind'
      and is_nullable = 'NO'
  )
  and exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'bank_reconciliation_row_decisions'
      and column_name = 'generated_target_id'
  ),
  'durable row decisions record the real action and generated target lineage'
);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, timezone)
values (
  'a2000000-0000-4000-8000-000000000001',
  'Bank Action Workspace Test',
  'America/Santiago'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a2000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'bank-actions@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'a2000000-0000-4000-8000-000000000003',
  'a2000000-0000-4000-8000-000000000002',
  'a2000000-0000-4000-8000-000000000001',
  'accountant', '{"access_accounting":true}'::jsonb, true
);

insert into public.accounts (
  id, tenant_id, code, name, type, category, is_active
) values
  (
    'a2000000-0000-4000-8000-000000000010',
    'a2000000-0000-4000-8000-000000000001',
    '1110', 'Banco de Chile', 'asset', 'currentAsset', true
  ),
  (
    'a2000000-0000-4000-8000-000000000011',
    'a2000000-0000-4000-8000-000000000001',
    '6201', 'Servicios digitales', 'expense', 'operatingExpense', true
  ),
  (
    'a2000000-0000-4000-8000-000000000012',
    'a2000000-0000-4000-8000-000000000001',
    '2105', 'Cuentas por pagar', 'liability', 'currentLiability', true
  ),
  (
    'a2000000-0000-4000-8000-000000000013',
    'a2000000-0000-4000-8000-000000000001',
    '2199', 'Préstamo conocido', 'liability', 'currentLiability', true
  );

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, is_active
) values (
  'a2000000-0000-4000-8000-000000000020',
  'a2000000-0000-4000-8000-000000000001',
  'bank_transfer', 'Transferencia bancaria',
  'a2000000-0000-4000-8000-000000000010', true
);

-- Models the real NIC row: a paid/posting-complete expense whose payment was
-- embedded in the expense before expense_payments became canonical.
insert into public.expenses (
  id, tenant_id, expense_number, supplier_name, document_type,
  document_number, issue_date, due_date, posting_status, payment_status,
  subtotal, tax_amount, total_amount, amount_paid, balance, reference,
  approval_status, approved_by, approved_at, posted_at, paid_at,
  payment_account_id, payment_method_id, created_by
) values (
  'a2000000-0000-4000-8000-000000000030',
  'a2000000-0000-4000-8000-000000000001',
  'GTO-NIC', 'NIC Chile', 'invoice', '21179232',
  '2026-07-17 12:00:00+00', '2026-07-17 12:00:00+00',
  'posted', 'paid', 19980, 0, 19980, 19980, 0, '21179232',
  'approved', 'a2000000-0000-4000-8000-000000000002', now(),
  '2026-07-17 12:00:00+00', '2026-07-17 12:00:00+00',
  'a2000000-0000-4000-8000-000000000010',
  'a2000000-0000-4000-8000-000000000020',
  'a2000000-0000-4000-8000-000000000002'
);

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment
) values (
  'a2000000-0000-4000-8000-000000000040',
  'a2000000-0000-4000-8000-000000000001',
  'FV-CARD-001', 'Cliente tarjeta', 'paid', 'manual_sale',
  80609, 80609, 0, 80609, 80609, 0, 'no_tax'
);

insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, idempotency_key,
  amount, date, reference
) values (
  'a2000000-0000-4000-8000-000000000041',
  'a2000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000040',
  'a2000000-0000-4000-8000-000000000020',
  'bank-actions:card-sale:001', 80609, '2026-07-18 12:00:00+00',
  'CARD-SETTLEMENT-SOURCE'
);

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"a2000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a2000000-0000-4000-8000-000000000002',
  true
);

select is(
  (
    select candidate->>'target_kind'
    from jsonb_array_elements(
      public.get_bank_reconciliation_candidates_v1(
        'a2000000-0000-4000-8000-000000000010',
        '2026-07-01', '2026-07-31'
      )->'candidates'
    ) candidate
    where candidate->>'target_id' =
      'a2000000-0000-4000-8000-000000000030'
  ),
  'expense',
  'a legacy paid NIC-style expense is an exact existing-operation candidate'
);

select is(
  (
    select candidate->>'reference'
    from jsonb_array_elements(
      public.get_bank_reconciliation_candidates_v1(
        'a2000000-0000-4000-8000-000000000010',
        '2026-07-01', '2026-07-31'
      )->'candidates'
    ) candidate
    where candidate->>'target_id' =
      'a2000000-0000-4000-8000-000000000041'
  ),
  'CARD-SETTLEMENT-SOURCE',
  'sales candidates use the canonical payment reference without requiring a legacy invoice-reference column'
);

create temp table bank_action_import on commit drop as
select public.save_bank_statement_import_v1(
  'bank-actions:import:001', repeat('a', 64), repeat('b', 64),
  'a2000000-0000-4000-8000-000000000010',
  '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
  jsonb_build_array(
    jsonb_build_object(
      'source_row_id', 'nic', 'ordinal', 1, 'booking_date', '2026-07-17',
      'operation_date', null, 'direction', 'debit', 'amount', 19980,
      'description', 'Pago: Univ.de Chile Nic Renca',
      'normalized_description', 'pago universidad de chile nic renca',
      'counterparty_observed', 'NIC Chile', 'document_number', '21179232',
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 10, 'source_line_end', 10,
      'fingerprint', repeat('c', 64)
    ),
    jsonb_build_object(
      'source_row_id', 'expense', 'ordinal', 2, 'booking_date', '2026-07-18',
      'operation_date', null, 'direction', 'debit', 'amount', 13580,
      'description', 'Pago: Mercadopago comercio',
      'normalized_description', 'pago mercadopago comercio',
      'counterparty_observed', 'Mercado Pago', 'document_number', 'MP-1',
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 11, 'source_line_end', 11,
      'fingerprint', repeat('d', 64)
    ),
    jsonb_build_object(
      'source_row_id', 'journal', 'ordinal', 3, 'booking_date', '2026-07-19',
      'operation_date', null, 'direction', 'credit', 'amount', 18000,
      'description', 'Transferencia de persona conocida',
      'normalized_description', 'transferencia de persona conocida',
      'counterparty_observed', 'Persona conocida', 'document_number', null,
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 12, 'source_line_end', 12,
      'fingerprint', repeat('e', 64)
    ),
    jsonb_build_object(
      'source_row_id', 'dismiss', 'ordinal', 4, 'booking_date', '2026-07-20',
      'operation_date', null, 'direction', 'debit', 'amount', 1000,
      'description', 'Línea duplicada por el banco',
      'normalized_description', 'linea duplicada por el banco',
      'counterparty_observed', null, 'document_number', null,
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 13, 'source_line_end', 13,
      'fingerprint', repeat('f', 64)
    ),
    jsonb_build_object(
      'source_row_id', 'pending', 'ordinal', 5, 'booking_date', '2026-07-21',
      'operation_date', null, 'direction', 'debit', 'amount', 2000,
      'description', 'Movimiento todavía no identificado',
      'normalized_description', 'movimiento todavia no identificado',
      'counterparty_observed', null, 'document_number', null,
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 14, 'source_line_end', 14,
      'fingerprint', repeat('1', 64)
    )
  )
) as receipt;

create temp table bank_action_payload on commit drop as
with imported as (
  select receipt from bank_action_import
), row_ids as (
  select item->>'source_row_id' as source_row_id,
         (item->>'row_id')::uuid as row_id
  from imported, jsonb_array_elements(imported.receipt->'rows') item
)
select jsonb_agg(
    case source_row_id
      when 'nic' then jsonb_build_object(
        'row_id', row_id, 'action', 'associate_existing',
        'allocations', jsonb_build_array(jsonb_build_object(
          'row_id', row_id, 'target_kind', 'expense',
          'target_id', 'a2000000-0000-4000-8000-000000000030',
          'bank_amount', 19980, 'target_amount', 19980,
          'match_kind', 'direct', 'confidence', 'high',
          'provider', 'none', 'instrument', 'unknown',
          'rationale', '{"reason":"same amount and date"}'::jsonb
        ))
      )
      when 'expense' then jsonb_build_object(
        'row_id', row_id, 'action', 'create_expense',
        'expense', jsonb_build_object(
          'account_id', 'a2000000-0000-4000-8000-000000000011',
          'payment_method_id', 'a2000000-0000-4000-8000-000000000020',
          'description', 'Compra conciliada desde cartola',
          'supplier_name', 'Mercado Pago', 'reference', 'MP-1'
        )
      )
      when 'journal' then jsonb_build_object(
        'row_id', row_id, 'action', 'post_journal',
        'journal', jsonb_build_object(
          'counterpart_account_id', 'a2000000-0000-4000-8000-000000000013',
          'description', 'Devolución de préstamo conocida',
          'reference', 'PRESTAMO-1'
        )
      )
      when 'dismiss' then jsonb_build_object(
        'row_id', row_id, 'action', 'dismiss',
        'reason', 'Duplicado confirmado en la cartola'
      )
      else jsonb_build_object('row_id', row_id, 'action', 'pending')
    end order by source_row_id
  ) as payload
from row_ids;

create temp table bank_action_apply on commit drop as
with imported as (
  select receipt from bank_action_import
)
select public.apply_bank_reconciliation_actions_v2(
  (select (receipt->>'import_id')::uuid from imported),
  (select (receipt->>'revision')::bigint from imported),
  'bank-actions:apply:001', (select payload from bank_action_payload)
) as receipt
;

select is(
  (select receipt->>'status' from bank_action_apply),
  'partially_reconciled',
  'mixed real actions remain partial while an unidentified row is pending'
);

select results_eq(
  $$select
      (receipt->>'allocation_count')::integer,
      (receipt->>'created_expense_count')::integer,
      (receipt->>'created_journal_count')::integer
    from bank_action_apply$$,
  $$values (3, 1, 1)$$,
  'the receipt counts one existing association and two generated operations'
);

select ok(
  exists (
    select 1
    from public.bank_reconciliation_row_decisions decision
    join public.expenses expense on expense.id = decision.generated_target_id
    where decision.action_kind = 'create_expense'
      and expense.posting_status = 'posted'
      and expense.payment_status = 'paid'
      and expense.total_amount = 13580
      and expense.amount_paid = 13580
      and expense.balance = 0
      and expense.payment_account_id =
        'a2000000-0000-4000-8000-000000000010'
  ),
  'creating a gasto posts and pays the expense against the selected bank account'
);

select ok(
  exists (
    select 1
    from public.bank_reconciliation_row_decisions decision
    join public.expenses expense on expense.id = decision.generated_target_id
    join public.expense_lines line on line.expense_id = expense.id
    join public.expense_payments payment on payment.expense_id = expense.id
    where decision.action_kind = 'create_expense'
      and line.account_id = 'a2000000-0000-4000-8000-000000000011'
      and line.total = 13580
      and payment.amount = 13580
      and payment.payment_account_id =
        'a2000000-0000-4000-8000-000000000010'
  ),
  'the generated expense owns both its cost line and canonical bank payment'
);

select ok(
  exists (
    select 1
    from public.bank_reconciliation_row_decisions decision
    join public.expenses expense on expense.id = decision.generated_target_id
    join public.journal_entries entry
      on entry.source_module = 'expenses'
     and entry.source_reference in (expense.expense_number, expense.id::text)
    join public.journal_lines line on line.entry_id = entry.id
    where decision.action_kind = 'create_expense'
      and entry.status = 'posted'
      and entry.total_debit = 13580
      and entry.total_credit = 13580
      and line.account_id = 'a2000000-0000-4000-8000-000000000011'
      and line.debit_amount = 13580
  )
  and exists (
    select 1
    from public.bank_reconciliation_row_decisions decision
    join public.expenses expense on expense.id = decision.generated_target_id
    join public.expense_payments payment on payment.expense_id = expense.id
    join public.journal_entries entry
      on entry.source_module = 'expense_payments'
     and entry.source_reference = payment.id::text
    join public.journal_lines line on line.entry_id = entry.id
    where decision.action_kind = 'create_expense'
      and entry.status = 'posted'
      and entry.total_debit = 13580
      and entry.total_credit = 13580
      and line.account_id = 'a2000000-0000-4000-8000-000000000010'
      and line.credit_amount = 13580
  ),
  'the generated gasto posts accrual and bank-payment journals without double-counting'
);

select ok(
  exists (
    select 1
    from public.bank_reconciliation_row_decisions decision
    join public.journal_entries entry on entry.id = decision.generated_target_id
    join public.journal_lines debit_line on debit_line.entry_id = entry.id
    join public.journal_lines credit_line on credit_line.entry_id = entry.id
    where decision.action_kind = 'post_journal'
      and entry.status = 'posted'
      and entry.total_debit = 18000
      and entry.total_credit = 18000
      and debit_line.account_id = 'a2000000-0000-4000-8000-000000000010'
      and debit_line.debit_amount = 18000
      and credit_line.account_id = 'a2000000-0000-4000-8000-000000000013'
      and credit_line.credit_amount = 18000
  ),
  'classifying a bank credit posts a balanced bank-versus-counterpart journal'
);

select ok(
  exists (
    select 1 from public.bank_reconciliation_row_decisions decision
    where decision.action_kind = 'dismiss'
      and decision.disposition = 'ignored'
      and decision.note = 'Duplicado confirmado en la cartola'
      and decision.generated_target_id is null
  )
  and exists (
    select 1 from public.bank_reconciliation_row_decisions decision
    where decision.action_kind = 'pending'
      and decision.disposition = 'pending'
      and decision.generated_target_id is null
  ),
  'dismissal needs a reason and neither dismissal nor pending fabricates accounting'
);

select is(
  (
    with imported as (
      select receipt from bank_action_import
    )
    select public.apply_bank_reconciliation_actions_v2(
      (select (receipt->>'import_id')::uuid from imported),
      (select (receipt->>'revision')::bigint from imported),
      'bank-actions:apply:001',
      (select payload from bank_action_payload)
    )->>'replayed'
  ),
  'true',
  'the exact action workspace retry replays without duplicate writes'
);

select * from finish();
rollback;
