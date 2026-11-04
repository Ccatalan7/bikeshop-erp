-- Read-back of 20261103120000. Fails before the migration and passes after.

select
  (select count(*) from public.product_brands where logo_url is not null) as marcas_con_logo;

select 1 / (case when
  exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'product_brands'
       and column_name = 'logo_url')
  and exists (
    select 1 from pg_constraint
     where conrelid = 'public.product_brands'::regclass
       and conname = 'product_brands_logo_url_check')
  and pg_get_functiondef('public.supplier_brands_v1(uuid, uuid)'::regprocedure)
    like '%''logo_url'', c.logo_url%'
  and pg_get_functiondef('public.supplier_brands_v1(uuid, uuid)'::regprocedure)
    like '%count(distinct pi.id)%'
  and has_function_privilege('authenticated', 'public.supplier_brands_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.supplier_brands_v1(uuid, uuid)', 'EXECUTE')
then 1 else 0 end) as afirma_logo_de_marca;
