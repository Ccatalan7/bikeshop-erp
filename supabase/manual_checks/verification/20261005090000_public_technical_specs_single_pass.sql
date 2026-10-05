-- Read-back of 20261005090000: the public technical sheet computes a
-- product's values and their validation once (both CTEs materialized), keeps
-- its security definer and grants, and as anon still returns the real H911
-- sheet, the same rows the product page read hands out.
-- Read-only; division by zero fails it.
set local role anon;

select count(*) as filas_ficha_h911
  from public.get_public_product_technical_specs(
         '5443b130-cc28-45af-a420-cd500b288890',
         (public.get_public_product_page_v1(
            '5443b130-cc28-45af-a420-cd500b288890', 'H911') #>> '{product,id}')::uuid);

select 1/(case when
 (select p.prosecdef
     and p.prosrc like '%facts as materialized (%'
     and p.prosrc like '%assessed as materialized (select%'
    from pg_proc p
   where p.oid = to_regprocedure('public.get_public_product_technical_specs(uuid,uuid)'))
 and has_function_privilege('anon', 'public.get_public_product_technical_specs(uuid,uuid)', 'EXECUTE')
 and (select count(*)
        from public.get_public_product_technical_specs(
               '5443b130-cc28-45af-a420-cd500b288890',
               (public.get_public_product_page_v1(
                  '5443b130-cc28-45af-a420-cd500b288890', 'H911') #>> '{product,id}')::uuid))
     = jsonb_array_length(public.get_public_product_page_v1(
         '5443b130-cc28-45af-a420-cd500b288890', 'H911') -> 'specs')
 and jsonb_array_length(public.get_public_product_page_v1(
       '5443b130-cc28-45af-a420-cd500b288890', 'H911') -> 'specs') > 0
then 1 else 0 end) as ficha_en_una_pasada;
