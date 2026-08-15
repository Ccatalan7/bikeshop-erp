begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  to_regclass('public.payment_terminal_settlements') is not null
  and to_regprocedure(
    'public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)'
  ) is not null,
  'terminal settlements extend the canonical bank action writer'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.apply_bank_reconciliation_actions_v2(uuid,bigint,text,jsonb)',
    'EXECUTE'
  )
  and not has_table_privilege(
    'authenticated', 'public.payment_terminal_settlements', 'INSERT'
  )
  and (
    select relrowsecurity
      from pg_class
     where oid = 'public.payment_terminal_settlements'::regclass
  ),
  'operators use the sealed writer and cannot forge settlement rows'
);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, timezone)
values (
  'd2000000-0000-4000-8000-000000000001',
  'Terminal Settlement Test',
  'America/Santiago'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'd2000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'terminal-settlement@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'd2000000-0000-4000-8000-000000000003',
  'd2000000-0000-4000-8000-000000000002',
  'd2000000-0000-4000-8000-000000000001',
  'accountant', '{"access_accounting":true}'::jsonb, true
);

insert into public.accounts (
  id, tenant_id, code, name, type, category, is_active
) values
  (
    'd2000000-0000-4000-8000-000000000010',
    'd2000000-0000-4000-8000-000000000001',
    '1110', 'Banco de Chile', 'asset', 'currentAsset', true
  ),
  (
    'd2000000-0000-4000-8000-000000000011',
    'd2000000-0000-4000-8000-000000000001',
    '1110-OTRO', 'Otro banco', 'asset', 'currentAsset', true
  ),
  (
    'd2000000-0000-4000-8000-000000000012',
    'd2000000-0000-4000-8000-000000000001',
    '1140-TBK', 'Fondos por recibir · Transbank',
    'asset', 'currentAsset', true
  ),
  (
    'd2000000-0000-4000-8000-000000000013',
    'd2000000-0000-4000-8000-000000000001',
    '6601-TBK', 'Comisiones · Transbank',
    'expense', 'financialExpense', true
  ),
  (
    'd2000000-0000-4000-8000-000000000014',
    'd2000000-0000-4000-8000-000000000001',
    '1140-MP', 'Fondos por recibir · Mercado Pago',
    'asset', 'currentAsset', true
  ),
  (
    'd2000000-0000-4000-8000-000000000015',
    'd2000000-0000-4000-8000-000000000001',
    '6601-MP', 'Comisiones · Mercado Pago',
    'expense', 'financialExpense', true
  );

insert into public.payment_terminal_profiles (
  id, tenant_id, provider_code, provider_name, terminal_name,
  clearing_account_id, commission_expense_account_id,
  settlement_account_id, descriptor_patterns, is_active
) values
  (
    'd2000000-0000-4000-8000-000000000020',
    'd2000000-0000-4000-8000-000000000001',
    'transbank', 'Transbank', 'POS del local',
    'd2000000-0000-4000-8000-000000000012',
    'd2000000-0000-4000-8000-000000000013',
    'd2000000-0000-4000-8000-000000000010',
    array['transbank', 'abonos debito y credito'], true
  ),
  (
    'd2000000-0000-4000-8000-000000000021',
    'd2000000-0000-4000-8000-000000000001',
    'mercadopago_point', 'Mercado Pago', 'Point futuro',
    'd2000000-0000-4000-8000-000000000014',
    'd2000000-0000-4000-8000-000000000015',
    'd2000000-0000-4000-8000-000000000010',
    array['mercado pago', 'point'], true
  );

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, is_active,
  settlement_provider, payment_instrument, usage_scope, terminal_profile_id
) values
  (
    'd2000000-0000-4000-8000-000000000030',
    'd2000000-0000-4000-8000-000000000001',
    'card_debit', 'Tarjeta de débito',
    'd2000000-0000-4000-8000-000000000012', true,
    'transbank', 'debit', 'inbound',
    'd2000000-0000-4000-8000-000000000020'
  ),
  (
    'd2000000-0000-4000-8000-000000000031',
    'd2000000-0000-4000-8000-000000000001',
    'card_credit', 'Tarjeta de crédito',
    'd2000000-0000-4000-8000-000000000012', true,
    'transbank', 'credit', 'inbound',
    'd2000000-0000-4000-8000-000000000020'
  ),
  (
    'd2000000-0000-4000-8000-000000000032',
    'd2000000-0000-4000-8000-000000000001',
    'mercadopago_point_debit', 'Débito · Point futuro',
    'd2000000-0000-4000-8000-000000000014', true,
    'mercadopago', 'debit', 'inbound',
    'd2000000-0000-4000-8000-000000000021'
  );

insert into public.sales_invoices (
  id, tenant_id, invoice_number, customer_name, status, source,
  subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment
) values
  (
    'd2000000-0000-4000-8000-000000000040',
    'd2000000-0000-4000-8000-000000000001',
    'FV-TBK-D', 'Cliente débito', 'paid', 'pos',
    50000, 50000, 0, 50000, 50000, 0, 'no_tax'
  ),
  (
    'd2000000-0000-4000-8000-000000000041',
    'd2000000-0000-4000-8000-000000000001',
    'FV-TBK-C', 'Cliente crédito', 'paid', 'ecommerce',
    30000, 30000, 0, 30000, 30000, 0, 'no_tax'
  ),
  (
    'd2000000-0000-4000-8000-000000000042',
    'd2000000-0000-4000-8000-000000000001',
    'FV-MP-D', 'Cliente Point', 'paid', 'manual_sale',
    20000, 20000, 0, 20000, 20000, 0, 'no_tax'
  );

insert into public.sales_payments (
  id, tenant_id, invoice_id, payment_method_id, idempotency_key,
  amount, date, reference
) values
  (
    'd2000000-0000-4000-8000-000000000050',
    'd2000000-0000-4000-8000-000000000001',
    'd2000000-0000-4000-8000-000000000040',
    'd2000000-0000-4000-8000-000000000030',
    'terminal-settlement:tbk-debit', 50000,
    '2026-08-10 12:00:00+00', 'TBK-D'
  ),
  (
    'd2000000-0000-4000-8000-000000000051',
    'd2000000-0000-4000-8000-000000000001',
    'd2000000-0000-4000-8000-000000000041',
    'd2000000-0000-4000-8000-000000000031',
    'terminal-settlement:tbk-credit', 30000,
    '2026-08-11 12:00:00+00', 'TBK-C'
  ),
  (
    'd2000000-0000-4000-8000-000000000052',
    'd2000000-0000-4000-8000-000000000001',
    'd2000000-0000-4000-8000-000000000042',
    'd2000000-0000-4000-8000-000000000032',
    'terminal-settlement:mp-debit', 20000,
    '2026-08-11 12:00:00+00', 'MP-D'
  );

set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  '{"sub":"d2000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'd2000000-0000-4000-8000-000000000002',
  true
);

select results_eq(
  $$select candidate->>'target_id'
      from jsonb_array_elements(
        public.get_bank_reconciliation_candidates_v1(
          'd2000000-0000-4000-8000-000000000010',
          '2026-08-01', '2026-08-31'
        )->'candidates'
      ) candidate
     where candidate->>'terminal_profile_id' is not null
     order by candidate->>'target_id'$$,
  $$values
    ('d2000000-0000-4000-8000-000000000050'::text),
    ('d2000000-0000-4000-8000-000000000051'::text),
    ('d2000000-0000-4000-8000-000000000052'::text)$$,
  'two acquiring profiles may explicitly settle into the same bank while exposing all of their clearing candidates'
);

select is(
  (
    select count(*)
      from jsonb_array_elements(
        public.get_bank_reconciliation_candidates_v1(
          'd2000000-0000-4000-8000-000000000011',
          '2026-08-01', '2026-08-31'
        )->'candidates'
      ) candidate
     where candidate->>'terminal_profile_id' is not null
  ),
  0::bigint,
  'a processor sale is not proposed against a bank outside its configured profile'
);

create temp table terminal_import on commit drop as
select public.save_bank_statement_import_v1(
  'terminal-settlement:import:001', repeat('d', 64), repeat('e', 64),
  'd2000000-0000-4000-8000-000000000010',
  '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
  jsonb_build_array(
    jsonb_build_object(
      'source_row_id', 'transbank', 'ordinal', 1,
      'booking_date', '2026-08-13', 'operation_date', null,
      'direction', 'credit', 'amount', 78000,
      'description', 'Pago: Abonos Debito Y Credito Transbank',
      'normalized_description', 'pago abonos debito y credito transbank',
      'counterparty_observed', 'Transbank', 'document_number', null,
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 10, 'source_line_end', 10,
      'fingerprint', repeat('f', 64)
    ),
    jsonb_build_object(
      'source_row_id', 'mercadopago', 'ordinal', 2,
      'booking_date', '2026-08-14', 'operation_date', null,
      'direction', 'credit', 'amount', 19000,
      'description', 'Abono Mercado Pago Point',
      'normalized_description', 'abono mercado pago point',
      'counterparty_observed', 'Mercado Pago', 'document_number', null,
      'balance', null, 'warning_codes', '[]'::jsonb, 'source_page', 1,
      'source_line_start', 11, 'source_line_end', 11,
      'fingerprint', repeat('a', 64)
    )
  )
) as receipt;

create temp table terminal_actions on commit drop as
with rows as (
  select item->>'source_row_id' as source_row_id,
         (item->>'row_id')::uuid as row_id
    from terminal_import,
         jsonb_array_elements(terminal_import.receipt->'rows') item
)
select jsonb_agg(
  case source_row_id
    when 'transbank' then jsonb_build_object(
      'row_id', row_id, 'action', 'associate_existing',
      'allocations', jsonb_build_array(
        jsonb_build_object(
          'row_id', row_id, 'target_kind', 'sales_payment',
          'target_id', 'd2000000-0000-4000-8000-000000000050',
          'bank_amount', 48750, 'target_amount', 50000,
          'match_kind', 'processor_estimate', 'confidence', 'medium',
          'provider', 'transbank', 'instrument', 'debit',
          'rationale', '{"profile":"Transbank POS"}'::jsonb
        ),
        jsonb_build_object(
          'row_id', row_id, 'target_kind', 'sales_payment',
          'target_id', 'd2000000-0000-4000-8000-000000000051',
          'bank_amount', 29250, 'target_amount', 30000,
          'match_kind', 'processor_estimate', 'confidence', 'medium',
          'provider', 'transbank', 'instrument', 'credit',
          'rationale', '{"profile":"Transbank POS"}'::jsonb
        )
      )
    )
    else jsonb_build_object(
      'row_id', row_id, 'action', 'associate_existing',
      'allocations', jsonb_build_array(
        jsonb_build_object(
          'row_id', row_id, 'target_kind', 'sales_payment',
          'target_id', 'd2000000-0000-4000-8000-000000000052',
          'bank_amount', 19000, 'target_amount', 20000,
          'match_kind', 'processor_estimate', 'confidence', 'medium',
          'provider', 'mercadopago', 'instrument', 'debit',
          'rationale', '{"profile":"Point futuro"}'::jsonb
        )
      )
    )
  end order by source_row_id
) as payload
from rows;

create temp table terminal_apply on commit drop as
select public.apply_bank_reconciliation_actions_v2(
  (terminal_import.receipt->>'import_id')::uuid,
  (terminal_import.receipt->>'revision')::bigint,
  'terminal-settlement:apply:001', terminal_actions.payload
) as receipt
from terminal_import, terminal_actions;

select results_eq(
  $$select receipt->>'status',
           (receipt->>'terminal_settlement_count')::integer
      from terminal_apply$$,
  $$values ('reconciled'::text, 2)$$,
  'accepting both deposits reconciles the statement and creates two net settlements'
);

select results_eq(
  $$select profile.provider_code, settlement.gross_sales_amount,
           settlement.bank_net_amount,
           settlement.unresolved_deduction_amount,
           settlement.settlement_account_id,
           settlement.clearing_account_id
      from public.payment_terminal_settlements settlement
      join public.payment_terminal_profiles profile
        on profile.id = settlement.terminal_profile_id
     order by profile.provider_code$$,
  $$values
    (
      'mercadopago_point'::text, 20000::numeric, 19000::numeric,
      1000::numeric, 'd2000000-0000-4000-8000-000000000010'::uuid,
      'd2000000-0000-4000-8000-000000000014'::uuid
    ),
    (
      'transbank'::text, 80000::numeric, 78000::numeric,
      2000::numeric, 'd2000000-0000-4000-8000-000000000010'::uuid,
      'd2000000-0000-4000-8000-000000000012'::uuid
    )$$,
  'each provider keeps an independent clearing balance even when both deposit into Banco de Chile'
);

select results_eq(
  $$select entry.source_module, line.account_id, line.debit_amount,
           line.credit_amount
      from public.payment_terminal_settlements settlement
      join public.journal_entries entry on entry.id = settlement.journal_entry_id
      join public.journal_lines line on line.entry_id = entry.id
     order by settlement.bank_net_amount, line.debit_amount desc$$,
  $$values
    (
      'payment_terminal_settlements'::text,
      'd2000000-0000-4000-8000-000000000010'::uuid,
      19000::numeric, 0::numeric
    ),
    (
      'payment_terminal_settlements'::text,
      'd2000000-0000-4000-8000-000000000014'::uuid,
      0::numeric, 19000::numeric
    ),
    (
      'payment_terminal_settlements'::text,
      'd2000000-0000-4000-8000-000000000010'::uuid,
      78000::numeric, 0::numeric
    ),
    (
      'payment_terminal_settlements'::text,
      'd2000000-0000-4000-8000-000000000012'::uuid,
      0::numeric, 78000::numeric
    )$$,
  'the bank receives only the net amount and each provider clearing account supplies it'
);

select is(
  (
    select count(*)
      from public.payment_terminal_settlements settlement
      join public.journal_lines line on line.entry_id = settlement.journal_entry_id
     where line.account_id in (
       'd2000000-0000-4000-8000-000000000013',
       'd2000000-0000-4000-8000-000000000015'
     )
  ),
  0::bigint,
  'a bank row does not invent commission expense or tax-credit evidence'
);

select results_eq(
  $$select match_kind, count(*)
      from public.bank_reconciliation_allocations
     where import_id = (
       select (receipt->>'import_id')::uuid from terminal_import
     )
     group by match_kind$$,
  $$values ('processor_estimate'::text, 3::bigint)$$,
  'the durable evidence preserves the provider-neutral processor decision'
);

select ok(
  (
    select (
      public.apply_bank_reconciliation_actions_v2(
        (terminal_import.receipt->>'import_id')::uuid,
        (terminal_import.receipt->>'revision')::bigint,
        'terminal-settlement:apply:001', terminal_actions.payload
      )->>'replayed'
    )::boolean
      and (
        public.apply_bank_reconciliation_actions_v2(
          (terminal_import.receipt->>'import_id')::uuid,
          (terminal_import.receipt->>'revision')::bigint,
          'terminal-settlement:apply:001', terminal_actions.payload
        )->>'terminal_settlement_count'
      )::integer = 2
    from terminal_import, terminal_actions
  )
  and (
    select count(*) = 2
      from public.payment_terminal_settlements
     where tenant_id = 'd2000000-0000-4000-8000-000000000001'
  )
  and (
    select count(*) = 2
      from public.journal_entries
     where tenant_id = 'd2000000-0000-4000-8000-000000000001'
       and source_module = 'payment_terminal_settlements'
  ),
  'an exact retry replays without duplicating settlements or journals'
);

select throws_ok(
  $$select public.apply_bank_reconciliation_actions_v2(
      (terminal_import.receipt->>'import_id')::uuid,
      (terminal_import.receipt->>'revision')::bigint,
      'terminal-settlement:apply:001',
      replace(
        terminal_actions.payload::text,
        'processor_estimate', 'manual'
      )::jsonb
    )
    from terminal_import, terminal_actions$$,
  'P0001',
  'bank_reconciliation_idempotency_conflict',
  'the same operation key cannot hide a different original decision behind normalization'
);

select * from finish();
rollback;
