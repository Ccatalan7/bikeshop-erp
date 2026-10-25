-- Read-back of 20261024070000: the store keeps the searches it finds nothing
-- for, and the ERP reads and edits the search's words. Plain SQL: a missing
-- invariant divides by zero after printing what it found.

select 1 / (case when to_regclass('public.catalog_search_misses') is not null
  and (select relrowsecurity from pg_class where oid = 'public.catalog_search_misses'::regclass)
  and not has_table_privilege('anon', 'public.catalog_search_misses', 'select')
  and not has_table_privilege('authenticated', 'public.catalog_search_misses', 'select')
  then 1 else 0 end) as afirma_tabla_cerrada;

select 1 / (case when has_function_privilege('anon', 'public.catalog_search_miss_record_v1(uuid,text)', 'execute')
  and not has_function_privilege('service_role', 'public.catalog_search_miss_record_v1(uuid,text)', 'execute')
  and not has_function_privilege('anon', 'public.catalog_search_misses_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.catalog_search_vocabulary_v1(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.catalog_search_add_words_v1(uuid,text,text[],text,text)', 'execute')
  and not has_function_privilege('anon', 'public.catalog_search_remove_word_v1(uuid,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.catalog_search_miss_close_v1(uuid,text,boolean)', 'execute')
  and not has_function_privilege('anon', 'public.catalog_search_counts_internal_v1(uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.catalog_search_counts_internal_v1(uuid,text)', 'execute')
  and has_function_privilege('authenticated', 'public.catalog_search_add_words_v1(uuid,text,text[],text,text)', 'execute')
  then 1 else 0 end) as afirma_permisos;

-- The shared vocabulary still holds every concept, and a store's row may
-- hold only a phrase.
select count(*) as conceptos_compartidos
  from public.catalog_search_terms where tenant_id is null;
select 1 / (case when (select count(*) from public.catalog_search_terms where tenant_id is null) >= 94
  and position('tenant_id IS NOT NULL' in pg_get_constraintdef(
    (select oid from pg_constraint where conname = 'catalog_search_terms_terms_present'))) > 0
  then 1 else 0 end) as afirma_vocabulario_y_regla;

-- What a search the store understands leaves: nothing (it lists products).
select public.catalog_search_miss_record_v1('5443b130-cc28-45af-a420-cd500b288890', 'camara fv');
select 1 / (case when not exists (
    select 1 from public.catalog_search_misses
     where tenant_id = '5443b130-cc28-45af-a420-cd500b288890' and term = 'camara fv')
  then 1 else 0 end) as afirma_lo_que_encuentra_no_queda;
