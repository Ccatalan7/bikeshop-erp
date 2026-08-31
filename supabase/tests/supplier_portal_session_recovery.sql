begin;

select no_plan();

select has_column(
  'public', 'supplier_portal_probes', 'session_login_url',
  'provider session recovery is configured as data'
);
select col_type_is(
  'public', 'supplier_portal_probes', 'session_login_url', 'text',
  'the provider login route is text'
);
select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.supplier_portal_probes'::regclass
      and conname = 'supplier_portal_probes_session_login_url_check'
  ),
  'the database rejects unsafe automatic-login routes'
);
select ok(
  not exists (
    select 1
    from public.supplier_portal_probes
    where session_login_url is not null
      and (
        session_login_url !~ '^https://'
        or position('@' in split_part(session_login_url, '/', 3)) > 0
        or position('#' in session_login_url) > 0
      )
  ),
  'every configured recovery route is HTTPS and credential-free'
);

select * from finish();
rollback;
