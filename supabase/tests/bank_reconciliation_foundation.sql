begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  to_regclass('public.bank_statement_imports') is not null
  and to_regclass('public.bank_statement_rows') is not null
  and to_regclass('public.bank_reconciliation_allocations') is not null
  and to_regprocedure(
    'public.get_bank_reconciliation_candidates_v1(uuid,date,date)'
  ) is not null
  and to_regprocedure(
    'public.save_bank_statement_import_v1(text,text,text,uuid,jsonb,jsonb)'
  ) is not null
  and to_regprocedure(
    'public.apply_bank_reconciliation_v1(uuid,bigint,text,jsonb,jsonb)'
  ) is not null,
  'bank reconciliation installs its evidence tables and three public RPCs'
);

select ok(
  exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'payment_methods'
      and column_name = 'settlement_provider'
  )
  and exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'payment_methods'
      and column_name = 'payment_instrument'
  ),
  'payment methods reserve separate provider and card-instrument dimensions'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.get_bank_reconciliation_candidates_v1(uuid,date,date)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.save_bank_statement_import_v1(text,text,text,uuid,jsonb,jsonb)',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.apply_bank_reconciliation_v1(uuid,bigint,text,jsonb,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.apply_bank_reconciliation_v1(uuid,bigint,text,jsonb,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.bank_reconciliation_target_snapshot(uuid,uuid,text,uuid)',
    'EXECUTE'
  ),
  'authenticated users enter through sealed RPCs and cannot call the helper'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.bank_statement_imports', 'INSERT'
  )
  and not has_table_privilege(
    'authenticated', 'public.bank_statement_rows', 'UPDATE'
  )
  and not has_table_privilege(
    'authenticated', 'public.bank_reconciliation_allocations', 'DELETE'
  )
  and (
    select class.relrowsecurity
    from pg_class class
    where class.oid = 'public.bank_statement_imports'::regclass
  ),
  'clients cannot forge evidence or allocations and imports are protected by RLS'
);

select ok(
  exists (
    select 1
    from pg_index index_row
    join pg_class class on class.oid = index_row.indexrelid
    where class.relname = 'uq_bank_reconciliation_allocations_target'
      and index_row.indisunique
  ),
  'one ERP payment or journal operation can belong to only one bank movement'
);

select lives_ok(
  $$select public.bank_reconciliation_target_snapshot(
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000002',
    'purchase_payment',
    '00000000-0000-4000-8000-000000000003'
  )$$,
  'the sealed purchase-payment projection uses the real reference column'
);

select throws_ok(
  $$select public.get_bank_reconciliation_candidates_v1(
    'a1000000-0000-4000-8000-000000000001',
    '2026-08-01',
    '2026-08-31'
  )$$,
  '42501',
  'accounting_access_required',
  'an unauthenticated caller cannot read accounting candidates'
);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, timezone)
values (
  'a1000000-0000-4000-8000-000000000001',
  'Bank Reconciliation Test',
  'America/Santiago'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a1000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'bank-reconciliation@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'a1000000-0000-4000-8000-000000000003',
  'a1000000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000001',
  'accountant', '{"access_accounting":true}'::jsonb, true
);

insert into public.accounts (
  id, tenant_id, code, name, type, category, is_active
) values
  (
    'a1000000-0000-4000-8000-000000000010',
    'a1000000-0000-4000-8000-000000000001',
    '1110', 'Banco de Chile', 'asset', 'currentAsset', true
  ),
  (
    'a1000000-0000-4000-8000-000000000011',
    'a1000000-0000-4000-8000-000000000001',
    '2199', 'Préstamo conocido', 'liability', 'currentLiability', true
  );

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, is_active
) values (
  'a1000000-0000-4000-8000-000000000020',
  'a1000000-0000-4000-8000-000000000001',
  'card', 'Tarjeta combinada',
  'a1000000-0000-4000-8000-000000000010', true
);

insert into public.journal_entries (
  id, tenant_id, entry_number, entry_date, description, type,
  source_module, source_reference, status, total_debit, total_credit
) values (
  'a1000000-0000-4000-8000-000000000030',
  'a1000000-0000-4000-8000-000000000001',
  'ASI-BANK-001', '2026-08-11 15:00:00+00',
  'Devolución de préstamo de persona conocida', 'manual',
  'accounting', 'WHATSAPP-REF-1', 'posted', 50000, 50000
);

insert into public.journal_lines (
  id, tenant_id, entry_id, account_id, account_code, account_name,
  description, debit_amount, credit_amount
) values
  (
    'a1000000-0000-4000-8000-000000000031',
    'a1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000030',
    'a1000000-0000-4000-8000-000000000010',
    '1110', 'Banco de Chile', 'Entrada bancaria', 50000, 0
  ),
  (
    'a1000000-0000-4000-8000-000000000032',
    'a1000000-0000-4000-8000-000000000001',
    'a1000000-0000-4000-8000-000000000030',
    'a1000000-0000-4000-8000-000000000011',
    '2199', 'Préstamo conocido', 'Cierre del préstamo', 0, 50000
  );

set local session_replication_role = origin;

update public.payment_methods
set settlement_provider = 'transbank', payment_instrument = 'unknown'
where id = 'a1000000-0000-4000-8000-000000000020';

select set_config(
  'request.jwt.claims',
  '{"sub":"a1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a1000000-0000-4000-8000-000000000002',
  true
);

select is(
  (
    select candidate->>'target_kind'
    from jsonb_array_elements(
      public.get_bank_reconciliation_candidates_v1(
        'a1000000-0000-4000-8000-000000000010',
        '2026-08-01',
        '2026-08-31'
      )->'candidates'
    ) candidate
    where candidate->>'target_id' =
      'a1000000-0000-4000-8000-000000000030'
  ),
  'journal_entry',
  'the candidate projection includes an existing standalone journal operation'
);

select is(
  (
    select candidate->>'direction'
    from jsonb_array_elements(
      public.get_bank_reconciliation_candidates_v1(
        'a1000000-0000-4000-8000-000000000010',
        '2026-08-01',
        '2026-08-31'
      )->'candidates'
    ) candidate
    where candidate->>'target_id' =
      'a1000000-0000-4000-8000-000000000030'
  ),
  'credit',
  'a debit in the ERP bank account projects as a bank-statement credit'
);

create temp table bank_reconciliation_import_receipt on commit drop as
select public.save_bank_statement_import_v1(
  'bank-import:test:001',
  repeat('a', 64),
  repeat('b', 64),
  'a1000000-0000-4000-8000-000000000010',
  '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
  jsonb_build_array(
    jsonb_build_object(
      'source_row_id', 'row-credit',
      'ordinal', 1,
      'booking_date', '2026-08-12',
      'operation_date', null,
      'direction', 'credit',
      'amount', 50000,
      'description', 'Transferencia de persona conocida',
      'normalized_description', 'transferencia de persona conocida',
      'counterparty_observed', 'Persona conocida',
      'document_number', null,
      'balance', 150000,
      'warning_codes', '[]'::jsonb,
      'source_page', 1,
      'source_line_start', 10,
      'source_line_end', 10,
      'fingerprint', repeat('c', 64)
    ),
    jsonb_build_object(
      'source_row_id', 'row-pending',
      'ordinal', 2,
      'booking_date', '2026-08-12',
      'operation_date', null,
      'direction', 'debit',
      'amount', 10000,
      'description', 'Movimiento aún no identificado',
      'normalized_description', 'movimiento aun no identificado',
      'counterparty_observed', null,
      'document_number', null,
      'balance', 140000,
      'warning_codes', '[]'::jsonb,
      'source_page', 1,
      'source_line_start', 11,
      'source_line_end', 11,
      'fingerprint', repeat('d', 64)
    )
  )
) as receipt;

select is(
  (select receipt->>'status' from bank_reconciliation_import_receipt),
  'review',
  'a structured import starts in review without posting accounting writes'
);

select is(
  (
    select count(*)::integer
    from public.bank_statement_rows row
    where row.import_id = (
      select (receipt->>'import_id')::uuid
      from bank_reconciliation_import_receipt
    )
  ),
  2,
  'the import stores every structured movement exactly once'
);

select is(
  (
    select replay.receipt->>'replayed'
    from (
      select public.save_bank_statement_import_v1(
        'bank-import:test:001',
        repeat('a', 64),
        repeat('b', 64),
        'a1000000-0000-4000-8000-000000000010',
        '{"source_type":"pdf_text","parser_name":"banco_chile_statement","filename_extension":"pdf"}'::jsonb,
        jsonb_build_array(
          jsonb_build_object(
            'source_row_id', 'row-credit', 'ordinal', 1,
            'booking_date', '2026-08-12', 'operation_date', null,
            'direction', 'credit', 'amount', 50000,
            'description', 'Transferencia de persona conocida',
            'normalized_description', 'transferencia de persona conocida',
            'counterparty_observed', 'Persona conocida',
            'document_number', null, 'balance', 150000,
            'warning_codes', '[]'::jsonb, 'source_page', 1,
            'source_line_start', 10, 'source_line_end', 10,
            'fingerprint', repeat('c', 64)
          ),
          jsonb_build_object(
            'source_row_id', 'row-pending', 'ordinal', 2,
            'booking_date', '2026-08-12', 'operation_date', null,
            'direction', 'debit', 'amount', 10000,
            'description', 'Movimiento aún no identificado',
            'normalized_description', 'movimiento aun no identificado',
            'counterparty_observed', null, 'document_number', null,
            'balance', 140000, 'warning_codes', '[]'::jsonb,
            'source_page', 1, 'source_line_start', 11,
            'source_line_end', 11, 'fingerprint', repeat('d', 64)
          )
        )
      ) as receipt
    ) replay
  ),
  'true',
  'replaying the exact import operation returns the same durable receipt'
);

create temp table bank_reconciliation_target_before on commit drop as
select to_jsonb(entry) as snapshot
from public.journal_entries entry
where entry.id = 'a1000000-0000-4000-8000-000000000030';

create temp table bank_reconciliation_apply_receipt on commit drop as
with imported as (
  select receipt from bank_reconciliation_import_receipt
), row_ids as (
  select item->>'source_row_id' as source_row_id,
         (item->>'row_id')::uuid as row_id
  from imported,
       jsonb_array_elements(imported.receipt->'rows') item
), payload as (
  select
    jsonb_build_array(jsonb_build_object(
      'row_id', (select row_id from row_ids where source_row_id = 'row-credit'),
      'target_kind', 'journal_entry',
      'target_id', 'a1000000-0000-4000-8000-000000000030',
      'bank_amount', 50000,
      'target_amount', 50000,
      'match_kind', 'direct',
      'confidence', 'high',
      'provider', 'none',
      'instrument', 'unknown',
      'rationale', '{"reason":"exact"}'::jsonb
    )) as allocations,
    jsonb_agg(jsonb_build_object(
      'row_id', row_id,
      'disposition', case source_row_id
        when 'row-credit' then 'reconciled'
        else 'pending'
      end
    ) order by source_row_id) as decisions
  from row_ids
)
select public.apply_bank_reconciliation_v1(
  (select (receipt->>'import_id')::uuid from imported),
  (select (receipt->>'revision')::bigint from imported),
  'bank-apply:test:001',
  payload.allocations,
  payload.decisions
) as receipt
from payload;

select is(
  (select receipt->>'status' from bank_reconciliation_apply_receipt),
  'partially_reconciled',
  'partial review persists reconciled and pending rows without forcing closure'
);

select is(
  (select (receipt->>'allocation_count')::integer
   from bank_reconciliation_apply_receipt),
  1,
  'one reviewed bank movement owns one explicit allocation'
);

select is(
  (
    select count(*)::integer
    from public.bank_reconciliation_row_decisions decision
    where decision.import_id = (
      select (receipt->>'import_id')::uuid
      from bank_reconciliation_apply_receipt
    )
  ),
  2,
  'every imported movement receives an explicit decision'
);

select is(
  (
    select before.snapshot
    from bank_reconciliation_target_before before
  ),
  (
    select to_jsonb(entry)
    from public.journal_entries entry
    where entry.id = 'a1000000-0000-4000-8000-000000000030'
  ),
  'applying reconciliation evidence does not mutate the linked journal operation'
);

select is(
  (
    with imported as (
      select receipt from bank_reconciliation_import_receipt
    ), row_ids as (
      select item->>'source_row_id' as source_row_id,
             (item->>'row_id')::uuid as row_id
      from imported,
           jsonb_array_elements(imported.receipt->'rows') item
    )
    select public.apply_bank_reconciliation_v1(
      (select (receipt->>'import_id')::uuid from imported),
      1,
      'bank-apply:test:001',
      jsonb_build_array(jsonb_build_object(
        'row_id', (select row_id from row_ids where source_row_id = 'row-credit'),
        'target_kind', 'journal_entry',
        'target_id', 'a1000000-0000-4000-8000-000000000030',
        'bank_amount', 50000,
        'target_amount', 50000,
        'match_kind', 'direct',
        'confidence', 'high',
        'provider', 'none',
        'instrument', 'unknown',
        'rationale', '{"reason":"exact"}'::jsonb
      )),
      (select jsonb_agg(jsonb_build_object(
        'row_id', row_id,
        'disposition', case source_row_id
          when 'row-credit' then 'reconciled'
          else 'pending'
        end
      ) order by source_row_id) from row_ids)
    )->>'replayed'
  ),
  'true',
  'an exact apply retry is replayed without duplicate allocations'
);

select throws_ok(
  format(
    $$select public.apply_bank_reconciliation_v1(
      %L::uuid, 1, 'bank-apply:test:stale', '[]'::jsonb, %L::jsonb
    )$$,
    (select receipt->>'import_id' from bank_reconciliation_import_receipt),
    (
      select jsonb_agg(jsonb_build_object(
        'row_id', row.id,
        'disposition', 'pending'
      ) order by row.ordinal)::text
      from public.bank_statement_rows row
      where row.import_id = (
        select (receipt->>'import_id')::uuid
        from bank_reconciliation_import_receipt
      )
    )
  ),
  '40001',
  'bank_reconciliation_revision_conflict',
  'a new apply operation cannot use a stale import revision'
);

select throws_ok(
  $$select public.save_bank_statement_import_v1(
    'bank-import:test:null-rows', repeat('e',64), null,
    'a1000000-0000-4000-8000-000000000010', '{}'::jsonb, null
  )$$,
  '22023',
  'bank_statement_import_payload_invalid',
  'null rows fail closed at the RPC boundary'
);

select is(
  (
    select count(*)::integer
    from public.bank_reconciliation_allocations allocation
    where allocation.import_id = (
      select (receipt->>'import_id')::uuid
      from bank_reconciliation_apply_receipt
    )
  ),
  1,
  'failed and replayed calls leave one allocation, never duplicates'
);

select is(
  (
    select count(*)::integer
    from jsonb_array_elements(
      public.get_bank_reconciliation_candidates_v1(
        'a1000000-0000-4000-8000-000000000010',
        '2026-08-01',
        '2026-08-31'
      )->'candidates'
    ) candidate
    where candidate->>'target_id' =
      'a1000000-0000-4000-8000-000000000030'
  ),
  0,
  'an already linked ERP operation is not proposed by a later review'
);

select * from finish();
rollback;
