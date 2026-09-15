-- Read-back: las dos tablas existen, aisladas por tenant, y los estados que
-- impiden confundir una sesión caída con falta de stock están declarados.
select
  1 / (case when exists (
    select 1 from pg_tables where schemaname='public'
      and tablename='supplier_portal_probes' and rowsecurity
  ) then 1 else 0 end) as sondas_con_rls,
  1 / (case when exists (
    select 1 from pg_tables where schemaname='public'
      and tablename='supplier_availability_checks' and rowsecurity
  ) then 1 else 0 end) as chequeos_con_rls,
  -- Una sesión caída jamás puede contarse como «sin stock».
  1 / (case when (
    select pg_get_constraintdef(oid) from pg_constraint
    where conname='supplier_availability_checks_status_check'
  ) like '%session_expired%' then 1 else 0 end) as sesion_caida_es_su_estado,
  1 / (case when (
    select pg_get_constraintdef(oid) from pg_constraint
    where conname='supplier_portal_probes_template_check'
  ) like '%{code}%' then 1 else 0 end) as la_sonda_busca_por_codigo,
  -- El portal se consulta por HTTPS. RBX publica su login en http:// y eso ya
  -- es un problema suyo; no vamos a agregarle uno nuestro.
  1 / (case when (
    select pg_get_constraintdef(oid) from pg_constraint
    where conname='supplier_portal_probes_https_check'
  ) like '%https%' then 1 else 0 end) as solo_https;
