-- Buscar en el portal lo que pide la necesidad abierta.
--
-- `supplier_availability_checks` sigue siendo el dueño de una consulta por SKU
-- conocido. Una necesidad sin producto confirmado no tiene SKU: antes la fila
-- de proveedor reemplazaba esa pregunta por el barrido global de reposición y
-- terminaba mostrando cámaras y bielas mientras el operador buscaba un motor.
--
-- Este camino guarda la pregunta real, los candidatos que devolvió el portal y
-- cuánto de la ficha pudo demostrarse. `possible` significa que el portal no
-- publicó información suficiente; nunca se promueve a `exact` por semejanza.

begin;

alter table public.supplier_portal_probes
  add column if not exists need_search_url_template text,
  add column if not exists need_search_term_limit integer not null default 40;

alter table public.supplier_portal_probes
  drop constraint if exists supplier_portal_probes_need_template_check;
alter table public.supplier_portal_probes
  add constraint supplier_portal_probes_need_template_check check (
    need_search_url_template is null
    or (
      position('{query}' in need_search_url_template) > 0
      and (
        need_search_url_template like 'https://%'
        or need_search_url_template like 'http://%'
      )
    )
  );

alter table public.supplier_portal_probes
  drop constraint if exists supplier_portal_probes_need_term_limit_check;
alter table public.supplier_portal_probes
  add constraint supplier_portal_probes_need_term_limit_check check (
    need_search_term_limit between 1 and 80
  );

comment on column public.supplier_portal_probes.need_search_url_template is
  'Búsqueda por palabra/categoría para una necesidad sin SKU. {query} se codifica en el cliente.';
comment on column public.supplier_portal_probes.need_search_term_limit is
  'Máximo que acepta el buscador del proveedor; RBX publica 15 caracteres.';

-- RBX publica una búsqueda «Por Palabra» aparte de «Por Código». Se navega el
-- frameset completo para conservar la sesión y permitir que el resultado viva
-- en su marco `mainFrame`.
update public.supplier_portal_probes probe
set need_search_url_template =
      'http://www.rburgos.cl/sitio/aplicaciones/catalogo.asp'
      || '?url=cat_pal_sf.asp&url1=cat_pal_cf.asp'
      || '&Clasificacion2={query}&folio=0&paginaabsoluta=1',
    need_search_term_limit = 15,
    updated_at = now()
from public.suppliers supplier
where supplier.id = probe.supplier_id
  and supplier.tenant_id = probe.tenant_id
  and supplier.name = 'RBX';

create table if not exists public.supplier_need_portal_searches (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  supply_need_id uuid not null references public.supply_needs(id) on delete cascade,
  search_query text not null,
  checked_at timestamptz not null default now(),
  status text not null,
  source_url text,
  results jsonb not null default '[]'::jsonb,
  evidence jsonb not null default '{}'::jsonb,
  created_by uuid,
  constraint supplier_need_portal_searches_status_check check (
    status in ('completed', 'no_matches', 'session_expired', 'unreadable')
  ),
  constraint supplier_need_portal_searches_query_check check (
    char_length(btrim(search_query)) between 1 and 80
  ),
  constraint supplier_need_portal_searches_results_check check (
    jsonb_typeof(results) = 'array'
  ),
  constraint supplier_need_portal_searches_evidence_check check (
    jsonb_typeof(evidence) = 'object'
  )
);

create index if not exists supplier_need_portal_searches_lookup_idx
  on public.supplier_need_portal_searches (
    tenant_id, supply_need_id, supplier_id, checked_at desc
  );

comment on table public.supplier_need_portal_searches is
  'Respuesta del catálogo del proveedor a una necesidad sin SKU. No afirma stock: conserva candidatos y evidencia de calce.';

alter table public.supplier_need_portal_searches enable row level security;

drop policy if exists supplier_need_portal_searches_tenant_select
  on public.supplier_need_portal_searches;
create policy supplier_need_portal_searches_tenant_select
  on public.supplier_need_portal_searches
  for select
  using (tenant_id = public.user_tenant_id());

revoke all on table public.supplier_need_portal_searches
  from public, anon, authenticated, service_role;
grant select on table public.supplier_need_portal_searches to authenticated;

create or replace function public.record_supplier_need_portal_search_v1(
  p_supplier_id uuid,
  p_supply_need_id uuid,
  p_search_query text,
  p_status text,
  p_source_url text default null,
  p_results jsonb default '[]'::jsonb,
  p_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_query text := btrim(coalesce(p_search_query, ''));
  v_limit integer;
  v_id uuid;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;

  select probe.need_search_term_limit
  into v_limit
  from public.supplier_portal_probes probe
  where probe.tenant_id = v_tenant_id
    and probe.supplier_id = p_supplier_id
    and probe.is_enabled
    and probe.need_search_url_template is not null;

  if v_limit is null then
    raise exception 'Need search is not configured' using errcode = 'P0002';
  end if;
  if char_length(v_query) not between 1 and v_limit
     or p_status not in (
       'completed', 'no_matches', 'session_expired', 'unreadable'
     )
     or jsonb_typeof(coalesce(p_results, 'null'::jsonb)) <> 'array'
     or jsonb_array_length(p_results) > 40
     or (p_status <> 'completed' and jsonb_array_length(p_results) > 0)
     or octet_length(p_results::text) > 32768
     or jsonb_typeof(coalesce(p_evidence, 'null'::jsonb)) <> 'object'
     or octet_length(p_evidence::text) > 8192
     or octet_length(coalesce(p_source_url, '')) > 500
     or (
       nullif(btrim(coalesce(p_source_url, '')), '') is not null
       and p_source_url not like 'https://%'
       and p_source_url not like 'http://%'
     ) then
    raise exception 'Invalid need portal search' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_results) result
    where jsonb_typeof(result) <> 'object'
       or coalesce(result->>'matchState', '') not in (
         'exact', 'possible', 'conflict'
       )
       or octet_length(coalesce(result->>'code', '')) > 80
       or octet_length(coalesce(result->>'name', '')) > 240
  ) then
    raise exception 'Invalid need portal result' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.supply_needs need
    where need.id = p_supply_need_id and need.tenant_id = v_tenant_id
  ) then
    raise exception 'Supply need not found' using errcode = 'P0002';
  end if;

  insert into public.supplier_need_portal_searches (
    tenant_id, supplier_id, supply_need_id, search_query, status,
    source_url, results, evidence, created_by
  ) values (
    v_tenant_id, p_supplier_id, p_supply_need_id, v_query, p_status,
    nullif(btrim(coalesce(p_source_url, '')), ''),
    p_results, p_evidence, auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object('status', 'recorded', 'searchId', v_id);
end;
$$;

revoke all on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb
) to authenticated;

create or replace function public.supplier_last_need_portal_search_v1(
  p_supplier_id uuid,
  p_supply_need_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_result jsonb;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.suppliers supplier
    where supplier.id = p_supplier_id and supplier.tenant_id = v_tenant_id
  ) or not exists (
    select 1 from public.supply_needs need
    where need.id = p_supply_need_id and need.tenant_id = v_tenant_id
  ) then
    raise exception 'Search scope not found' using errcode = 'P0002';
  end if;

  select jsonb_build_object(
    'status', search.status,
    'searchQuery', search.search_query,
    'checkedAt', search.checked_at,
    'sourceUrl', search.source_url,
    'results', search.results
  )
  into v_result
  from public.supplier_need_portal_searches search
  where search.tenant_id = v_tenant_id
    and search.supplier_id = p_supplier_id
    and search.supply_need_id = p_supply_need_id
  order by search.checked_at desc
  limit 1;

  return coalesce(v_result, jsonb_build_object('status', 'never_searched'));
end;
$$;

revoke all on function public.supplier_last_need_portal_search_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.supplier_last_need_portal_search_v1(uuid, uuid)
  to authenticated;

commit;
