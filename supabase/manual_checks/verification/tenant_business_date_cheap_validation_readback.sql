-- Read-back de `tenant_business_date` sin escaneo del catálogo de zonas.
--
-- La prueba de fondo no es que la función exista: es que el **ranking por texto
-- libre vuelva a caber en su presupuesto**. Tardaba ~32 s contra un
-- `statement_timeout` de 4,5 s porque la vista de métricas llamaba a esta
-- función tres veces por fila, y cada llamada recorría las 1.194 filas de
-- `pg_timezone_names`.

-- La garantía se conserva: se convierte en la zona del tenant y una zona no
-- reconocida sigue terminando en el mismo error.
select 1 / (case when pg_get_functiondef(
  'public.tenant_business_date(uuid,timestamptz)'::regprocedure
) like '%at time zone%' then 1 else 0 end) as converts_in_tenant_zone;

select 1 / (case when pg_get_functiondef(
  'public.tenant_business_date(uuid,timestamptz)'::regprocedure
) like '%Tenant timezone is invalid%' then 1 else 0 end) as still_fails_closed;

-- Y el escaneo por llamada ya no está.
select 1 / (case when pg_get_functiondef(
  'public.tenant_business_date(uuid,timestamptz)'::regprocedure
) not like '%pg_timezone_names%' then 1 else 0 end) as catalog_scan_removed;

-- Los otros modos de fallo siguen intactos, en el mismo orden.
select 1 / (case when pg_get_functiondef(
  'public.tenant_business_date(uuid,timestamptz)'::regprocedure
) like '%Active tenant membership required%' then 1 else 0 end) as membership_guard_intact;

select 1 / (case when pg_get_functiondef(
  'public.tenant_business_date(uuid,timestamptz)'::regprocedure
) like '%Tenant not found for business date%' then 1 else 0 end) as missing_tenant_guard_intact;

-- Contexto del tenant con más candidatos: el caso real, no el más cómodo.
select set_config(
  'request.jwt.claim.sub',
  (select p.user_id::text
     from public.user_profiles p
     join public.tenants t on t.id = p.tenant_id and t.is_active is true
    where p.is_active is true
      and p.tenant_id = (
        select m.tenant_id
          from public.purchase_candidate_metrics_v1 m
         group by m.tenant_id
         order by count(*) desc
         limit 1
      )
    group by p.user_id
   having count(*) = 1
    limit 1),
  true
) as tenant_context_ready;

-- LA PRUEBA QUE IMPORTA: el ranking por **texto libre** completa. Con el
-- escaneo por llamada esto se cortaba por timeout.
with ranked as (
  select public.rank_purchase_candidates_v1('camara', null, null, 'balanced', 5)
    as payload
)
select
  1 / (case when (payload->>'status') in ('success', 'verifiedEmpty')
        then 1 else 0 end) as free_text_ranking_completes,
  1 / (case when jsonb_typeof(payload->'items') = 'array'
        then 1 else 0 end) as free_text_ranking_returns_a_list,
  1 / (case when not exists (
        select 1 from jsonb_array_elements(payload->'items') item
        where (item.value->>'evidenceAgeDays')::int < 0
      ) then 1 else 0 end) as evidence_age_still_sane
from ranked;
