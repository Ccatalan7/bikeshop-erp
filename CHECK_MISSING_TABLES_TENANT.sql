-- Check if the 7 extra tables have tenant_id

select 
  t.table_name,
  case 
    when c.column_name is not null then '✅ HAS tenant_id'
    else '❌ MISSING tenant_id'
  end as status
from (
  select 'categories' as table_name
  union all select 'contracts'
  union all select 'payments'
  union all select 'product_images'
  union all select 'warehouses'
  union all select 'website_pages'
  union all select 'work_orders'
) t
left join information_schema.columns c 
  on c.table_name = t.table_name 
  and c.table_schema = 'public'
  and c.column_name = 'tenant_id'
order by t.table_name;
