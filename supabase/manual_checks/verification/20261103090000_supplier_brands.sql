-- Read-back of 20261103090000. Fails before the migration and passes after.

select
  (select count(*) from public.supplier_brands where removed_at is null) as marcas_asignadas,
  (select count(distinct supplier_id) from public.supplier_brands where removed_at is null)
    as proveedores_con_marcas,
  (select count(*) from public.supplier_brands where source = 'records') as desde_nuestras_compras;

select 1 / (case when
  to_regclass('public.supplier_brands') is not null
  and has_function_privilege('authenticated', 'public.supplier_brands_v1(uuid, uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.brand_suppliers_v1(uuid, uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.supplier_brand_index_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.remove_supplier_brand_v1(uuid, uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.supplier_brands_v1(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.refresh_supplier_brands_from_records_internal(uuid)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.supplier_brands', 'INSERT')
  and not has_table_privilege('anon', 'public.supplier_brands', 'SELECT')
  and exists (
    select 1 from pg_trigger
     where tgrelid = 'public.supplier_brands'::regclass
       and tgname = 'supplier_brands_guard')
  and exists (select 1 from cron.job where jobname = 'vinabike_supplier_brands_from_records')
  -- La primera pasada de la regla: los proveedores con compras ya tienen sus
  -- marcas (Shimano a Andes Industrial, por sus 49 productos y 6 líneas).
  and exists (
    select 1
      from public.supplier_brands sb
      join public.suppliers s on s.tenant_id = sb.tenant_id and s.id = sb.supplier_id
      join public.product_brands b on b.id = sb.brand_id
     where sb.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
       and s.name = 'Andes Industrial' and b.name = 'Shimano'
       and sb.source = 'records' and sb.removed_at is null)
  and not exists (
    select 1
      from public.supplier_brands sb
      join public.product_brands b on b.id = sb.brand_id
     where public.product_brand_is_placeholder_internal(b.name))
then 1 else 0 end) as afirma_marcas_de_proveedores;
