-- Read-back del ranking con gama. Falla a nivel SQL si no quedó instalado.

-- Queda UNA función: dos candidatas dejarían a PostgREST sin poder resolver la
-- llamada de cinco claves que ya hace el cliente.
select 1 / (case when (
  select count(*) from pg_proc where proname = 'rank_purchase_candidates_v1'
) = 1 then 1 else 0 end) as single_ranking_function;

select 1 / (case when exists (
  select 1 from pg_proc
   where proname = 'rank_purchase_candidates_v1'
     and pg_get_function_identity_arguments(oid) like '%p_gama text%'
) then 1 else 0 end) as ranking_accepts_gama;

-- El contrato de imágenes del candidato sigue en pie. Generar esta función
-- desde el kernel original lo habría revertido en silencio; lo detectó su
-- prueba pgTAP y esta verificación lo deja fijado.
select 1 / (case when pg_get_functiondef(
  'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)'::regprocedure
) like '%imageUrlOptimized%' then 1 else 0 end) as media_contract_preserved;

-- La gama ORDENA, nunca elimina: entra como peso del puntaje.
select 1 / (case when pg_get_functiondef(
  'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)'::regprocedure
) like '%0.25 * gama_score%' then 1 else 0 end) as gama_orders_not_filters;

-- Y su vocabulario es cerrado.
select 1 / (case when pg_get_functiondef(
  'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)'::regprocedure
) like '%''economica'', ''media'', ''alta''%' then 1 else 0 end) as gama_vocabulary_closed;

-- Sólo personal autenticado.
select 1 / (case when has_function_privilege(
  'authenticated',
  'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)',
  'execute'
) and not has_function_privilege(
  'anon',
  'public.rank_purchase_candidates_v1(text,uuid,uuid,text,integer,text)',
  'execute'
) then 1 else 0 end) as ranking_acl;
