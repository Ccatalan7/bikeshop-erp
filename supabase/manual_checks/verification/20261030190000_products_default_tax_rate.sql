-- Read-back of 20261030190000. Fails before the migration and passes after.

select
  (select count(*)
     from public.products
    where tax_rate is null
      and coalesce(product_type, 'product') <> 'service') as productos_sin_iva,
  (select count(*)
     from pg_trigger
    where tgname = 'trg_products_default_tax_rate'
      and tgrelid = 'public.products'::regclass
      and not tgisinternal) as trigger_del_iva;

select 1 / (case when not exists (
  select 1
    from public.products
   where tax_rate is null
     and coalesce(product_type, 'product') <> 'service'
) then 1 else 0 end) as afirma_todo_producto_tiene_iva;

select 1 / (case when exists (
  select 1
    from pg_trigger
   where tgname = 'trg_products_default_tax_rate'
     and tgrelid = 'public.products'::regclass
     and not tgisinternal
     and tgenabled = 'O'
) then 1 else 0 end) as afirma_trigger_activo;

select 1 / (case when
  pg_get_functiondef('public.products_default_tax_rate()'::regprocedure)
    like '%new.tax_rate := 19%'
  and not has_function_privilege('anon', 'public.products_default_tax_rate()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.products_default_tax_rate()', 'EXECUTE')
then 1 else 0 end) as afirma_funcion_privada;
