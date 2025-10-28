-- Ultra-simple table list (no joins, no aggregations)
-- Just list table names - count them manually or in your app

select table_name
from information_schema.tables
where table_schema = 'public'
  and table_type = 'BASE TABLE'
order by table_name;
