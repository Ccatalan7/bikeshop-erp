-- FASTEST: Show ONLY tables missing tenant_id

select table_name
from information_schema.tables
where table_schema = 'public'
  and table_type = 'BASE TABLE'
  and table_name not in ('tenants', 'reserved_subdomains', 'migrations', 'schema_migrations', 'user_activity_log')
  and table_name not in (
    select table_name 
    from information_schema.columns 
    where table_schema = 'public' 
    and column_name = 'tenant_id'
  )
order by table_name;
