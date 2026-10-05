-- Read-back of 20261005130000: the thumbnail record exists with RLS and no
-- direct grant to the public key, its read is security definer with a fixed
-- search_path and callable by the public key; the product page v2 is security
-- invoker, reads Viñabike's products by SKU and by id, returns nothing
-- without a key, and v1 is the same read by SKU.
-- Read-only; division by zero fails it.
select 1/(case when
  (select c.relrowsecurity from pg_class c
    where c.oid = 'public.public_image_thumbnails'::regclass)
  and not has_table_privilege('anon', 'public.public_image_thumbnails', 'SELECT')
  and not has_table_privilege('authenticated', 'public.public_image_thumbnails', 'SELECT')
  and has_table_privilege('service_role', 'public.public_image_thumbnails', 'INSERT')
then 1 else 0 end) as registro_cerrado_al_publico;

select 1/(case when
  (select p.prosecdef and p.proconfig = array['search_path=public, pg_temp']
     from pg_proc p
    where p.oid = to_regprocedure('public.get_public_image_thumbnails_v1(uuid,text[])'))
  and has_function_privilege('anon',
        'public.get_public_image_thumbnails_v1(uuid,text[])', 'EXECUTE')
  and (select not p.prosecdef from pg_proc p
        where p.oid = to_regprocedure('public.get_public_product_page_v2(uuid,text,uuid)'))
  and has_function_privilege('anon',
        'public.get_public_product_page_v2(uuid,text,uuid)', 'EXECUTE')
  and (select p.prosrc like '%get_public_product_page_v2(p_tenant_id, p_sku, null)%'
         from pg_proc p
        where p.oid = to_regprocedure('public.get_public_product_page_v1(uuid,text)'))
then 1 else 0 end) as funciones_con_su_seguridad;

set local role anon;

with sample as (
  select r.id, r.sku
    from public.get_public_products(
           p_tenant_id := '5443b130-cc28-45af-a420-cd500b288890',
           p_only_in_stock := true,
           p_limit := 1) r
)
select 1/(case when
  (select public.get_public_product_page_v2(
            '5443b130-cc28-45af-a420-cd500b288890', sample.sku)
            #>> '{product,id}' from sample) = (select id::text from sample)
  and (select public.get_public_product_page_v2(
            '5443b130-cc28-45af-a420-cd500b288890', p_product_id := sample.id)
            #>> '{product,sku}' from sample) = (select sku from sample)
  and (select public.get_public_product_page_v1(
            '5443b130-cc28-45af-a420-cd500b288890', sample.sku)
          = public.get_public_product_page_v2(
            '5443b130-cc28-45af-a420-cd500b288890', sample.sku) from sample)
  and public.get_public_product_page_v2('5443b130-cc28-45af-a420-cd500b288890')
        is null
  and (select count(*) from public.get_public_image_thumbnails_v1(
         '5443b130-cc28-45af-a420-cd500b288890',
         array['https://example.invalid/no-existe.jpg'])) = 0
then 1 else 0 end) as ficha_por_sku_y_por_id;
