begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local timezone = 'UTC';

select plan(7);

insert into public.tenants (id, shop_name, timezone)
values (
  '8d111111-1111-4111-8111-111111111111',
  'Payroll Civil Date Test',
  'America/Santiago'
);

select is(
  public.payroll_payment_civil_date_is_future(
    '8d111111-1111-4111-8111-111111111111',
    (
      public.tenant_business_date(
        '8d111111-1111-4111-8111-111111111111'
      )::timestamp + interval '12 hours'
    ) at time zone 'UTC'
  ),
  false,
  'UTC noon for the tenant business date is accepted as today'
);

select is(
  public.payroll_payment_civil_date_is_future(
    '8d111111-1111-4111-8111-111111111111',
    (
      (
        public.tenant_business_date(
          '8d111111-1111-4111-8111-111111111111'
        ) + 1
      )::timestamp + interval '12 hours'
    ) at time zone 'UTC'
  ),
  true,
  'the next civil date remains future'
);

select is(
  public.payroll_payment_civil_date_is_future(
    '8d111111-1111-4111-8111-111111111111',
    (
      (
        public.tenant_business_date(
          '8d111111-1111-4111-8111-111111111111'
        ) - 1
      )::timestamp + interval '12 hours'
    ) at time zone 'UTC'
  ),
  false,
  'an earlier civil date remains valid'
);

select ok(
  position(
    'public.payroll_payment_civil_date_is_future('
    in pg_get_functiondef(
      'public.pay_payroll_voucher_internal(uuid,jsonb)'::regprocedure
    )
  ) > 0,
  'the payroll writer delegates future-date policy to the civil-date owner'
);

select ok(
  position(
    'v_payment_date > now() + interval ''5 minutes'''
    in pg_get_functiondef(
      'public.pay_payroll_voucher_internal(uuid,jsonb)'::regprocedure
    )
  ) = 0,
  'the payroll writer no longer compares a civil date transport to now()'
);

select ok(
  exists (
    select 1
    from pg_proc function_row
    join pg_namespace namespace_row
      on namespace_row.oid = function_row.pronamespace
    where namespace_row.nspname = 'public'
      and function_row.proname = 'payroll_payment_civil_date_is_future'
      and function_row.prosecdef is true
      and function_row.provolatile = 's'
      and function_row.proconfig
        @> array['search_path=pg_catalog, public, pg_temp']::text[]
  ),
  'the internal civil-date owner is stable, sealed and search-path hardened'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.payroll_payment_civil_date_is_future(uuid,timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.payroll_payment_civil_date_is_future(uuid,timestamptz)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'service_role',
    'public.payroll_payment_civil_date_is_future(uuid,timestamptz)',
    'EXECUTE'
  ),
  'client and service roles cannot invoke the internal date helper directly'
);

select * from finish();

rollback;
