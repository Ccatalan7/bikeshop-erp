begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';
select no_plan();

select ok(
  has_function_privilege('authenticated',
    'public.save_bank_reconciliation_rule_v1(text,text,text,uuid,text)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.delete_bank_reconciliation_rule_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.save_bank_reconciliation_rule_v1(text,text,text,uuid,text)', 'EXECUTE')
  and not has_table_privilege('authenticated',
    'public.bank_reconciliation_rules', 'INSERT'),
  'accountants save rules only through the function'
);

insert into public.tenants (id, shop_name, timezone) values
  ('e8000000-0000-4000-8000-000000000001', 'Reglas de cartola', 'America/Santiago'),
  ('e8000000-0000-4000-8000-000000000101', 'Otra tienda', 'America/Santiago');
set local session_replication_role = replica;
delete from public.payment_terminal_terms
 where tenant_id in ('e8000000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-000000000101');
delete from public.payment_terminal_profiles
 where tenant_id in ('e8000000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-000000000101');
delete from public.payment_methods
 where tenant_id in ('e8000000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-000000000101');
delete from public.accounts
 where tenant_id in ('e8000000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-000000000101');
set local session_replication_role = origin;

insert into public.accounts (id, tenant_id, code, name, type, category) values
  ('e8000000-0000-4000-8000-000000000010', 'e8000000-0000-4000-8000-000000000001',
   '1110', 'Banco de Chile', 'asset', 'currentAsset'),
  ('e8000000-0000-4000-8000-000000000013', 'e8000000-0000-4000-8000-000000000001',
   '6190', 'Gastos generales', 'expense', 'operatingExpense'),
  ('e8000000-0000-4000-8000-000000000014', 'e8000000-0000-4000-8000-000000000001',
   '3103', 'Retiros de socio', 'equity', 'capital'),
  ('e8000000-0000-4000-8000-000000000110', 'e8000000-0000-4000-8000-000000000101',
   '1110', 'Banco ajeno', 'asset', 'currentAsset');
insert into public.payment_methods (
  id, tenant_id, code, name, account_id, default_tax_treatment
) values
  ('e8000000-0000-4000-8000-000000000020', 'e8000000-0000-4000-8000-000000000001',
   'transfer', 'Transferencia', 'e8000000-0000-4000-8000-000000000010', 'no_tax');

set local session_replication_role = replica;
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('e8000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated',
   'rules@example.invalid', '', now(), '{"account_type":"erp_staff"}'::jsonb,
   '{}'::jsonb, now(), now()),
  ('e8000000-0000-4000-8000-000000000102', 'authenticated', 'authenticated',
   'rules-other@example.invalid', '', now(), '{"account_type":"erp_staff"}'::jsonb,
   '{}'::jsonb, now(), now());
insert into public.user_profiles (
  id, user_id, tenant_id, role, permissions, is_active
) values
  ('e8000000-0000-4000-8000-000000000003', 'e8000000-0000-4000-8000-000000000002',
   'e8000000-0000-4000-8000-000000000001', 'accountant',
   '{"access_accounting":true}'::jsonb, true),
  ('e8000000-0000-4000-8000-000000000103', 'e8000000-0000-4000-8000-000000000102',
   'e8000000-0000-4000-8000-000000000101', 'accountant',
   '{"access_accounting":true}'::jsonb, true);
set local session_replication_role = origin;

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  select set_config('request.jwt.claim.sub', p_user::text, true);
$$;

select pg_temp.act_as('e8000000-0000-4000-8000-000000000002');


select is(
  public.save_bank_reconciliation_rule_v1(
    '  Google Play   YOUTU ', 'debit', 'post_journal',
    'e8000000-0000-4000-8000-000000000014', 'Suscripción YouTube (personal)'
  )->>'pattern',
  'google play youtu',
  'a rule keeps the text in one normalized form'
);

select is(
  (public.save_bank_reconciliation_rule_v1(
    'google play youtu', 'debit', 'create_expense',
    'e8000000-0000-4000-8000-000000000013', 'Suscripción del negocio'
  )->>'action'),
  'create_expense',
  'teaching the same text again replaces the rule'
);

select is(
  (select count(*)::int from public.bank_reconciliation_rules
    where tenant_id = 'e8000000-0000-4000-8000-000000000001'),
  1,
  'one rule per text and direction'
);

select throws_like(
  $q$select public.save_bank_reconciliation_rule_v1('youtu', 'debit',
    'create_expense', 'e8000000-0000-4000-8000-000000000014', 'Retiro')$q$,
  '%bank_reconciliation_rule_account_invalid%',
  'an expense rule needs an expense account'
);

select throws_like(
  $q$select public.save_bank_reconciliation_rule_v1('traspaso de gregorio', 'credit',
    'create_expense', 'e8000000-0000-4000-8000-000000000013', 'Venta')$q$,
  '%bank_reconciliation_rule_invalid%',
  'money coming in is never an expense'
);

select pg_temp.act_as('e8000000-0000-4000-8000-000000000102');

select throws_like(
  $q$select public.save_bank_reconciliation_rule_v1('youtu', 'debit',
    'post_journal', 'e8000000-0000-4000-8000-000000000014', 'Retiro')$q$,
  '%bank_reconciliation_rule_account_invalid%',
  'another tenant cannot point a rule at an account that is not its own'
);

set local role authenticated;
select is(
  (select count(*)::int from public.bank_reconciliation_rules),
  0,
  'another tenant reads no rules'
);
reset role;

select * from finish();
rollback;
