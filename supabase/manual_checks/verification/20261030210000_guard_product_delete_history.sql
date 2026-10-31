-- Read-back of 20261030210000. Fails before the migration and passes after.

select
  (select count(*)
     from pg_trigger
    where tgname = 'trg_guard_product_delete_history'
      and tgrelid = 'public.products'::regclass
      and not tgisinternal) as guardia,
  (select count(*)
     from pg_proc
    where oid = to_regprocedure('public.delete_or_archive_product_v1(uuid,uuid)')) as comando;

select 1 / (case when exists (
  select 1
    from pg_trigger
   where tgname = 'trg_guard_product_delete_history'
     and tgrelid = 'public.products'::regclass
     and not tgisinternal
     and tgenabled = 'O'
     and pg_get_triggerdef(oid) like '%BEFORE DELETE ON public.products FOR EACH ROW%'
) then 1 else 0 end) as afirma_guardia_activa;

select 1 / (case when
  (select bool_and(prosecdef)
     from pg_proc
    where oid in (
      'public.guard_product_delete_history()'::regprocedure,
      'public.product_history_reasons_internal(uuid,uuid)'::regprocedure,
      'public.delete_or_archive_product_v1(uuid,uuid)'::regprocedure))
  and has_function_privilege('authenticated', 'public.delete_or_archive_product_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.delete_or_archive_product_v1(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.product_history_reasons_internal(uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.product_history_reasons_internal(uuid,uuid)', 'EXECUTE')
then 1 else 0 end) as afirma_permisos;

-- The newest stock movement of the shop: its product reads movements, so the
-- guard would refuse to delete it.
select 1 / (case when (
  select public.product_history_reasons_internal(m.product_id, m.tenant_id)
           @> array['movimientos de stock']
    from public.stock_movements m
   where m.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   order by m.created_at desc
   limit 1
) then 1 else 0 end) as afirma_historia_se_lee;
