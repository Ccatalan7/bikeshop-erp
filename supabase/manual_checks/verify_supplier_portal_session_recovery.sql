select
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'supplier_portal_probes'
  and column_name = 'session_login_url';

select
  supplier.name,
  probe.session_login_url,
  probe.is_enabled
from public.supplier_portal_probes probe
join public.suppliers supplier on supplier.id = probe.supplier_id
where supplier.name = 'RBX';

select
  1 / (case when exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'supplier_portal_probes'
      and column_name = 'session_login_url'
      and data_type = 'text'
      and is_nullable = 'YES'
  ) then 1 else 0 end) as login_url_column_exists,
  1 / (case when exists (
    select 1
    from pg_constraint
    where conrelid = 'public.supplier_portal_probes'::regclass
      and conname = 'supplier_portal_probes_session_login_url_check'
      and pg_get_constraintdef(oid) like '%https://%'
  ) then 1 else 0 end) as login_url_constraint_exists,
  1 / (case when not exists (
    select 1
    from public.supplier_portal_probes
    where session_login_url is not null
      and (
        session_login_url !~ '^https://'
        or position('@' in split_part(session_login_url, '/', 3)) > 0
        or position('#' in session_login_url) > 0
      )
  ) then 1 else 0 end) as configured_login_urls_are_safe,
  1 / (case when exists (
    select 1
    from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'RBX'
      and probe.session_login_url = 'https://portal.rburgos.cl/login/'
  ) then 1 else 0 end) as rbx_login_route_is_declared;
