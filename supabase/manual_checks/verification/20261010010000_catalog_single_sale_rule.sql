-- Read-back de 20261010010000_catalog_single_sale_rule: la regla única existe,
-- la usan la tienda y el checkout, y la pantalla del ERP dice lo mismo que la
-- tienda sobre los datos reales.

select 1 / case
  when to_regprocedure('public.catalog_product_web_block_v1(public.products,jsonb)') is not null
   and to_regprocedure('public.catalog_web_policy_v1(uuid)') is not null
   and to_regprocedure('public.catalog_web_items_v1(uuid)') is not null
   and to_regprocedure('public.catalog_set_web_sale_v1(uuid,uuid[],boolean)') is not null
   and to_regprocedure('public.catalog_copy_sku_to_gtin_v1(uuid,uuid[])') is not null
   and to_regprocedure('public.catalog_undo_sku_to_gtin_v1(uuid,uuid[])') is not null
   and to_regprocedure('public.catalog_set_clearance_v1(uuid,uuid,date)') is not null
   and to_regprocedure('public.catalog_set_price_mode_v1(uuid,uuid,text)') is not null
   and to_regprocedure('public.catalog_classify_tax_v1(uuid,uuid[],numeric)') is not null
   and to_regprocedure('public.catalog_convert_item_v1(uuid,uuid,text,text)') is not null
   and to_regprocedure('public.catalog_dismiss_issue_v1(uuid,uuid,text,boolean)') is not null
   and to_regprocedure('public.catalog_archive_empty_records_v1(uuid,uuid[])') is not null
   and to_regprocedure('public.catalog_category_counts_v1(uuid)') is not null
   and to_regprocedure('public.catalog_featured_suggestions_v1(uuid,integer,integer)') is not null
   and to_regprocedure('public.catalog_replace_featured_v1(uuid,uuid[])') is not null
  then 1 else 0
end as assert_functions_exist;

select 1 / case
  when exists (
    select 1 from pg_trigger
     where tgrelid = 'public.products'::regclass
       and tgname = 'zz_guard_consumable_off_web'
       and not tgisinternal
  )
   and exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'products'
       and column_name = 'web_clearance_until'
  )
   and exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'products'
       and column_name = 'website_price_mode'
  )
   and to_regclass('public.catalog_issue_dismissals') is not null
  then 1 else 0
end as assert_guard_and_columns;

-- Cada lectura pública pregunta a la regla.
select 1 / case
  when position('catalog_product_web_block_v1' in pg_get_functiondef(
         'public.get_public_products_without_inventory_reservations(uuid,uuid[],uuid[],text,text,text,boolean,text,integer,integer)'::regprocedure)) > 0
   and position('catalog_product_web_block_v1' in pg_get_functiondef(
         'public.create_public_online_order_unkeyed(jsonb,jsonb)'::regprocedure)) > 0
   and position('catalog_product_web_block_v1' in pg_get_functiondef(
         'public.resolve_public_product_url_alias(uuid,text)'::regprocedure)) > 0
   and position('catalog_product_web_block_v1' in pg_get_functiondef(
         'public.get_public_product_tax_classifications(uuid,uuid[])'::regprocedure)) > 0
  then 1 else 0
end as assert_public_reads_use_the_rule;

-- Ni un consumible del taller en la tienda.
select 1 / case
  when not exists (
    select 1
      from public.get_public_products(
        '5443b130-cc28-45af-a420-cd500b288890', null, null, null, null,
        null, false, 'name', 100000, 0) listed
      join public.products p on p.id = listed.id
     where p.purchase_treatment = 'workshop_consumable'
  )
  then 1 else 0
end as assert_no_consumable_listed;

-- Ni uno bajo el costo con IVA sin liquidación.
select 1 / case
  when not exists (
    select 1
      from public.get_public_products(
        '5443b130-cc28-45af-a420-cd500b288890', null, null, null, null,
        'product', false, 'name', 100000, 0) listed
      join public.products p on p.id = listed.id
     where coalesce(p.cost, 0) > 0
       and coalesce(p.website_price, p.price) < p.cost * public.catalog_tax_factor_v1(p.tax_rate)
       and coalesce(p.web_clearance_until, date '1900-01-01') < current_date
  )
  then 1 else 0
end as assert_no_loss_listed;

-- La pantalla del ERP dice lo mismo que la tienda: lo que el ERP llama «en
-- venta» es exactamente lo que la tienda lista con stock.
select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', '7bb76d88-5455-462e-a838-5f78af922914', 'role', 'authenticated')::text,
  true
) as reader_claims_set;
select set_config('request.jwt.claim.sub', '7bb76d88-5455-462e-a838-5f78af922914', true) as reader_id_set;

select state, kind, count(*)
  from public.catalog_web_items_v1('5443b130-cc28-45af-a420-cd500b288890')
 group by state, kind
 order by state, kind;

select 1 / case
  when not exists (
    (
      select item.id
        from public.catalog_web_items_v1('5443b130-cc28-45af-a420-cd500b288890') item
       where item.state = 'venta'
      except
      select listed.id
        from public.get_public_products(
          '5443b130-cc28-45af-a420-cd500b288890', null, null, null, null,
          null, true, 'name', 100000, 0) listed
    )
    union all
    (
      select listed.id
        from public.get_public_products(
          '5443b130-cc28-45af-a420-cd500b288890', null, null, null, null,
          null, true, 'name', 100000, 0) listed
      except
      select item.id
        from public.catalog_web_items_v1('5443b130-cc28-45af-a420-cd500b288890') item
       where item.state = 'venta'
    )
  )
  then 1 else 0
end as assert_erp_and_store_agree_by_id;

select 1 / case
  when (
    select count(*)
      from public.catalog_web_items_v1('5443b130-cc28-45af-a420-cd500b288890') item
     where item.kind = 'consumable' and item.state <> 'taller'
  ) = 0
  then 1 else 0
end as assert_every_consumable_is_taller;
