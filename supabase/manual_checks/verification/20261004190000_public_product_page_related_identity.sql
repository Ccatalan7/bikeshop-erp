-- Read-back of 20261004190000: the product page read hands out only this
-- store's or global brands, and its related products carry the website fields
-- Flutter attaches to every row it draws. As anon, for the real H911 page.
-- Read-only; division by zero fails it.
set local role anon;

select jsonb_array_length(public.get_public_product_page_v1(
         '5443b130-cc28-45af-a420-cd500b288890', 'H911') -> 'related') as relacionados,
       jsonb_array_length(public.get_public_product_page_v1(
         '5443b130-cc28-45af-a420-cd500b288890', 'H911') -> 'brand_rows') as marcas;

select 1/(case when
 (select not p.prosecdef
     and p.prosrc like '%(b.tenant_id = p_tenant_id or b.tenant_id is null)%'
    from pg_proc p
   where p.oid = to_regprocedure('public.get_public_product_page_v1(uuid,text)'))
 and has_function_privilege('anon', 'public.get_public_product_page_v1(uuid,text)', 'EXECUTE')
 and public.get_public_product_page_v1('5443b130-cc28-45af-a420-cd500b288890', 'H911')
       #>> '{product,sku}' = 'H911'
 and jsonb_array_length(public.get_public_product_page_v1(
       '5443b130-cc28-45af-a420-cd500b288890', 'H911') -> 'related') > 0
 and not exists (
       select 1
         from jsonb_array_elements(public.get_public_product_page_v1(
           '5443b130-cc28-45af-a420-cd500b288890', 'H911') -> 'related') item
        where not item ? 'website_name' or item ? 'cost' or item ? 'ordinality')
 and not exists (
       select 1
         from jsonb_array_elements(public.get_public_product_page_v1(
           '5443b130-cc28-45af-a420-cd500b288890', 'H911') -> 'brand_rows') brand
        where brand ->> 'tenant_id' is not null
          and brand ->> 'tenant_id' <> '5443b130-cc28-45af-a420-cd500b288890')
then 1 else 0 end) as relacionados_con_identidad_y_marcas_propias;
