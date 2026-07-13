begin;

select plan(5);

select has_function(
  'public',
  'get_expense_period_details',
  array['timestamp with time zone', 'timestamp with time zone', 'boolean'],
  'dashboard expense period drill-down function exists'
);

select ok(
  (
    select procedure.prosecdef
      and procedure.proconfig @> array['search_path=public']
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'get_expense_period_details'
      and pg_get_function_identity_arguments(procedure.oid)
        = 'p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_is_cash_flow boolean'
  ),
  'dashboard expense drill-down is security definer with a pinned search path'
);

select lives_ok(
  $$select * from public.get_expense_period_details(
    now() - interval '30 days',
    now(),
    false
  )$$,
  'dashboard expense drill-down executes safely without tenant claims'
);

select lives_ok(
  $$select * from public.get_expense_period_details(
    now() - interval '30 days',
    now(),
    true
  )$$,
  'dashboard cash-flow expense drill-down executes safely without tenant claims'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.get_expense_period_details(timestamp with time zone, timestamp with time zone, boolean)',
    'execute'
  ) and has_function_privilege(
    'authenticated',
    'public.get_expense_period_details(timestamp with time zone, timestamp with time zone, boolean)',
    'execute'
  ),
  'dashboard expense drill-down is executable only by authenticated application users'
);

select * from finish();

rollback;
