-- Read-back of 20261024080000: the search's groups have a name with its
-- accents, and a word finds a shared group by its exact key. Plain SQL: a
-- missing invariant divides by zero after printing what it found.

select count(*) filter (where label is null) as grupos_sin_nombre,
       count(*) as grupos_compartidos
  from public.catalog_search_terms where tenant_id is null;
select 1 / (case when not exists (
    select 1 from public.catalog_search_terms where tenant_id is null and label is null)
  and (select label from public.catalog_search_terms where tenant_id is null and concept = 'camara') = 'Cámara'
  then 1 else 0 end) as afirma_nombres;

select 1 / (case when to_regprocedure('public.catalog_search_add_words_v1(uuid,text,text[],text,text,text)') is not null
  and to_regprocedure('public.catalog_search_add_words_v1(uuid,text,text[],text,text)') is null
  and has_function_privilege('authenticated', 'public.catalog_search_add_words_v1(uuid,text,text[],text,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.catalog_search_add_words_v1(uuid,text,text[],text,text,text)', 'execute')
  and not has_function_privilege('anon', 'public.catalog_search_vocabulary_v1(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.catalog_search_group_key_internal_v1(uuid,text)', 'execute')
  then 1 else 0 end) as afirma_firmas_y_permisos;

select 1 / (case when public.catalog_search_group_key_internal_v1('5443b130-cc28-45af-a420-cd500b288890', 'cinta_llanta') = 'cinta_llanta'
  and public.catalog_search_group_key_internal_v1('5443b130-cc28-45af-a420-cd500b288890', 'Portabidón') = 'portabidon'
  then 1 else 0 end) as afirma_llave_exacta;
