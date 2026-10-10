-- Read-back de 20261010020000: la regla no tiene subconsultas (el
-- planificador la incrusta), la categoría vive en su propia función y la
-- tienda sigue diciendo lo mismo que el ERP.

select 1 / case
  when to_regprocedure('public.catalog_category_visible_v1(uuid,uuid)') is not null
   and position('exists' in lower(pg_get_functiondef(
         'public.catalog_product_web_block_v1(public.products,jsonb)'::regprocedure))) = 0
   and position('catalog_category_visible_v1' in pg_get_functiondef(
         'public.catalog_product_web_block_v1(public.products,jsonb)'::regprocedure)) > 0
  then 1 else 0
end as assert_rule_has_no_subquery;

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

select set_config(
  'request.jwt.claims',
  jsonb_build_object('sub', '7bb76d88-5455-462e-a838-5f78af922914', 'role', 'authenticated')::text,
  true
) as reader_claims_set;
select set_config('request.jwt.claim.sub', '7bb76d88-5455-462e-a838-5f78af922914', true) as reader_id_set;

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
