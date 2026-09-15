begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  to_regclass('public.payment_terminal_profiles') is not null
  and to_regclass('public.payment_terminal_terms') is not null
  and to_regprocedure(
    'public.save_payment_terminal_profile_v1(text,jsonb,jsonb)'
  ) is not null,
  'terminal profiles, versioned terms and the sealed writer are installed'
);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'payment_methods'
      and column_name = 'usage_scope'
  ) and exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'payment_methods'
      and column_name = 'terminal_profile_id'
  ),
  'payment methods publish direction and terminal ownership'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.save_payment_terminal_profile_v1(text,jsonb,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.save_payment_terminal_profile_v1(text,jsonb,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.payment_terminal_profile_snapshot(uuid,uuid)',
    'EXECUTE'
  ),
  'authenticated accounting operators use the writer but not its helper'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.payment_terminal_profiles', 'INSERT'
  )
  and not has_table_privilege(
    'authenticated', 'public.payment_terminal_terms', 'UPDATE'
  )
  and (
    select relrowsecurity from pg_class
    where oid = 'public.payment_terminal_profiles'::regclass
  ),
  'clients cannot bypass the versioned writer and profiles are RLS protected'
);

set local session_replication_role = replica;

insert into public.tenants (id, shop_name, timezone)
values (
  'b2000000-0000-4000-8000-000000000001',
  'Terminal Profile Test',
  'America/Santiago'
);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'b2000000-0000-4000-8000-000000000002',
  'authenticated', 'authenticated', 'terminal-profile@example.invalid',
  '', now(), '{"account_type":"erp_staff"}'::jsonb, '{}'::jsonb, now(), now()
);

insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values (
  'b2000000-0000-4000-8000-000000000003',
  'b2000000-0000-4000-8000-000000000002',
  'b2000000-0000-4000-8000-000000000001',
  'accountant', '{"access_accounting":true}'::jsonb, true
);

insert into public.accounts (
  id, tenant_id, code, name, type, category, is_active
) values
  (
    'b2000000-0000-4000-8000-000000000010',
    'b2000000-0000-4000-8000-000000000001',
    '1110', 'Banco de Chile', 'asset', 'currentAsset', true
  ),
  (
    'b2000000-0000-4000-8000-000000000011',
    'b2000000-0000-4000-8000-000000000001',
    '1101', 'Caja General', 'asset', 'currentAsset', true
  );

insert into public.payment_methods (
  id, tenant_id, code, name, account_id, is_active
) values (
  'b2000000-0000-4000-8000-000000000020',
  'b2000000-0000-4000-8000-000000000001',
  'card', 'Tarjeta combinada',
  'b2000000-0000-4000-8000-000000000010', false
);

set local session_replication_role = origin;

select lives_ok(
  $$select public.seed_payment_terminal_profiles_for_tenant(
    'b2000000-0000-4000-8000-000000000001'
  )$$,
  'the canonical seed separates an existing combined card method'
);

select results_eq(
  $$select code, payment_instrument, usage_scope, is_active
      from public.payment_methods
     where tenant_id = 'b2000000-0000-4000-8000-000000000001'
     order by code$$,
  $$values
    ('card'::text, 'unknown'::text, 'outbound'::text, false),
    ('card_credit'::text, 'credit'::text, 'inbound'::text, true),
    ('card_debit'::text, 'debit'::text, 'inbound'::text, true)$$,
  'customer collections split debit and credit without reactivating a disabled business-card method'
);

select results_eq(
  $$select
      profile.clearing_account_id <> profile.settlement_account_id,
      profile.commission_expense_account_id <> profile.clearing_account_id,
      bool_and(method.account_id = profile.clearing_account_id)
    from public.payment_terminal_profiles profile
    join public.payment_methods method
      on method.tenant_id = profile.tenant_id
     and method.terminal_profile_id = profile.id
   where profile.tenant_id = 'b2000000-0000-4000-8000-000000000001'
     and profile.provider_code = 'transbank'
   group by profile.id$$,
  $$values (true, true, true)$$,
  'one terminal owns a dedicated clearing and commission account while both rails share the clearing account'
);

select results_eq(
  $$select instrument, commission_rate_bps, settlement_business_days
      from public.payment_terminal_terms
     where tenant_id = 'b2000000-0000-4000-8000-000000000001'
     order by instrument$$,
  $$values
    ('credit'::text, 235, 2::smallint),
    ('debit'::text, 175, 1::smallint)$$,
  'the initial Transbank debit and credit rails keep distinct public terms'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"b2000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
select set_config(
  'request.jwt.claim.sub',
  'b2000000-0000-4000-8000-000000000002',
  true
);

create temp table terminal_save_receipt on commit drop as
select public.save_payment_terminal_profile_v1(
  'terminal-profile:create:1',
  jsonb_build_object(
    'provider_code', 'mercadopago_point',
    'provider_name', 'Mercado Pago',
    'terminal_name', 'Point del local',
    'settlement_account_id', 'b2000000-0000-4000-8000-000000000010',
    'descriptor_patterns', jsonb_build_array('mercado pago', 'point'),
    'is_active', true
  ),
  jsonb_build_array(
    jsonb_build_object(
      'instrument', 'debit',
      'commission_rate_bps', 190,
      'commission_vat_bps', 1900,
      'minimum_commission_uf', 0,
      'settlement_business_days', 1,
      'booking_grace_business_days', 1,
      'amount_tolerance_clp', 500,
      'effective_from', '2026-08-15'
    ),
    jsonb_build_object(
      'instrument', 'credit',
      'commission_rate_bps', 290,
      'commission_vat_bps', 1900,
      'minimum_commission_uf', 0,
      'settlement_business_days', 3,
      'booking_grace_business_days', 1,
      'amount_tolerance_clp', 500,
      'effective_from', '2026-08-15'
    )
  )
) as receipt;

select is(
  (select receipt->>'operation' from terminal_save_receipt),
  'save_payment_terminal_profile',
  'the writer returns a typed receipt'
);

select results_eq(
  $$select payment_instrument, usage_scope, settlement_provider
      from public.payment_methods
     where tenant_id = 'b2000000-0000-4000-8000-000000000001'
       and terminal_profile_id = (
         select (receipt#>>'{profile,id}')::uuid from terminal_save_receipt
       )
     order by payment_instrument$$,
  $$values
    ('credit'::text, 'inbound'::text, 'mercadopago'::text),
    ('debit'::text, 'inbound'::text, 'mercadopago'::text)$$,
  'a second terminal creates separate inbound rails without changing Transbank'
);

select is(
  (
    select public.save_payment_terminal_profile_v1(
      'terminal-profile:create:1',
      jsonb_build_object(
        'provider_code', 'mercadopago_point',
        'provider_name', 'Mercado Pago',
        'terminal_name', 'Point del local',
        'settlement_account_id', 'b2000000-0000-4000-8000-000000000010',
        'descriptor_patterns', jsonb_build_array('mercado pago', 'point'),
        'is_active', true
      ),
      jsonb_build_array(
        jsonb_build_object(
          'instrument', 'debit',
          'commission_rate_bps', 190,
          'commission_vat_bps', 1900,
          'minimum_commission_uf', 0,
          'settlement_business_days', 1,
          'booking_grace_business_days', 1,
          'amount_tolerance_clp', 500,
          'effective_from', '2026-08-15'
        ),
        jsonb_build_object(
          'instrument', 'credit',
          'commission_rate_bps', 290,
          'commission_vat_bps', 1900,
          'minimum_commission_uf', 0,
          'settlement_business_days', 3,
          'booking_grace_business_days', 1,
          'amount_tolerance_clp', 500,
          'effective_from', '2026-08-15'
        )
      )
    )->>'replayed'
  )::boolean,
  true,
  'an exact retry replays without creating another profile or method'
);

select throws_ok(
  $$select public.save_payment_terminal_profile_v1(
    'terminal-profile:cash-is-not-bank',
    jsonb_build_object(
      'provider_code', 'cash_terminal',
      'provider_name', 'Proveedor imposible',
      'terminal_name', 'Caja no bancaria',
      'settlement_account_id', 'b2000000-0000-4000-8000-000000000011',
      'descriptor_patterns', jsonb_build_array('descriptor imposible'),
      'is_active', true
    ),
    jsonb_build_array(
      jsonb_build_object(
        'instrument', 'debit',
        'commission_rate_bps', 100,
        'commission_vat_bps', 1900,
        'minimum_commission_uf', 0,
        'settlement_business_days', 1,
        'booking_grace_business_days', 1,
        'amount_tolerance_clp', 500,
        'effective_from', '2026-08-15'
      )
    )
  )$$,
  '23503',
  'payment_terminal_account_invalid',
  'a terminal must settle to a bank ledger branch, never to cash or another asset'
);

select is(
  (
    select count(*) from public.payment_terminal_profiles
    where tenant_id = 'b2000000-0000-4000-8000-000000000001'
  ),
  2::bigint,
  'Transbank and a future provider coexist as two terminal profiles'
);

select results_eq(
  $$select count(distinct profile.clearing_account_id),
           count(distinct profile.commission_expense_account_id)
      from public.payment_terminal_profiles profile
     where profile.tenant_id = 'b2000000-0000-4000-8000-000000000001'$$,
  $$values (2::bigint, 2::bigint)$$,
  'each provider contract receives separate clearing and commission accounts'
);

select * from finish();
rollback;
