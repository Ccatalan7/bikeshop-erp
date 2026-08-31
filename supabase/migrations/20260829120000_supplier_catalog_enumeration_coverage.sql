-- Enumerar el catálogo del proveedor, y decir cuánto se alcanzó a mirar.
--
-- El defecto que originó esto no era de calce sino de descubrimiento: la
-- primera página del buscador por palabra se guardaba y se leía como «el
-- catálogo del proveedor para esta necesidad». Diez filas de una consulta
-- angosta ocupaban el lugar de dieciocho cámaras repartidas en tres páginas.
--
-- Esta migración agrega las tres cosas que faltaban, todas como DATO:
--
--   1. cómo recorrer un nodo de la taxonomía del portal, página por página;
--   2. dónde leer esa taxonomía, para descubrirla en vez de escribirla a mano;
--   3. cuánto se enumeró — separado del estado, porque el estado dice cómo
--      terminó la corrida y la cobertura dice qué alcanzó a ver. Fusionarlos
--      es exactamente lo que dejó pasar «10» por «todo».
--
-- El tope de filas sube en el recibo Y en el adaptador a la vez: moverlos por
-- separado produce una enumeración correcta que muere en el `insert` con
-- 22023, con el portal ya consultado.

begin;

-- ---------------------------------------------------------------------------
-- 1. Taxonomía descubierta del portal
-- ---------------------------------------------------------------------------

alter table public.supplier_portal_probes
  add column if not exists catalog_taxonomy jsonb,
  add column if not exists catalog_taxonomy_discovered_at timestamptz;

alter table public.supplier_portal_probes
  drop constraint if exists supplier_portal_probes_catalog_taxonomy_check;
alter table public.supplier_portal_probes
  add constraint supplier_portal_probes_catalog_taxonomy_check check (
    catalog_taxonomy is null
    or (
      jsonb_typeof(catalog_taxonomy) = 'object'
      and jsonb_typeof(catalog_taxonomy -> 'nodes') = 'array'
      and jsonb_array_length(catalog_taxonomy -> 'nodes') <= 2000
      and octet_length(catalog_taxonomy::text) <= 262144
    )
  );

comment on column public.supplier_portal_probes.catalog_taxonomy is
  'Taxonomía descubierta del portal (nodos navegables + huella). Es caché con vencimiento, nunca una tabla escrita a mano por proveedor. La escribe sólo record_supplier_portal_catalog_taxonomy_v1.';
comment on column public.supplier_portal_probes.catalog_taxonomy_discovered_at
  is 'Cuándo la LEYÓ EL SERVIDOR. Vencida se vuelve a descubrir; la huella detecta deriva. Nunca la fija el cliente.';

-- ---------------------------------------------------------------------------
-- 1.b El caché es del servidor, y hay que hacerlo cumplir
--
-- `supplier_portal_probes` tiene DML completo concedido a `anon` y a
-- `authenticated`, y su política es `for all` acotada sólo por tenant. Medido
-- en producción el 2026-08-28:
--
--   anon          | DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
--   authenticated | DELETE,INSERT,REFERENCES,SELECT,TRIGGER,TRUNCATE,UPDATE
--
-- Es decir: cualquier usuario del tenant puede escribir estas dos columnas por
-- PostgREST sin pasar por el recibo, y envenenar el caché —incluida una fecha
-- futura que apagaría el redescubrimiento—. Un `revoke update` a secas no
-- sirve: el privilegio de columna no puede recortar un UPDATE ya concedido a
-- nivel de tabla, y revocarlo entero cambiaría la postura de una tabla de
-- configuración que este cambio no vino a tocar.
--
-- Se protegen **sólo las dos columnas nuevas**, con un disparador. Dentro de
-- una función `security definer` el `current_user` es su dueño, así que el
-- recibo pasa y la escritura directa del rol del API no. Las ediciones de
-- configuración de siempre siguen funcionando: si el caché no cambia, el
-- disparador ni opina.
-- ---------------------------------------------------------------------------

create or replace function public.supplier_portal_probes_guard_catalog_cache()
returns trigger
language plpgsql
-- **Invoker a propósito.** Con `security definer` el `current_user` pasaría a
-- ser el dueño de ESTA función y la comprobación se auto-aprobaría siempre.
security invoker
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_owner name;
  v_touched_cache boolean := false;
  v_identity_changed boolean := false;
begin
  if tg_op = 'UPDATE' then
    v_touched_cache :=
      new.catalog_taxonomy is distinct from old.catalog_taxonomy
      or new.catalog_taxonomy_discovered_at
         is distinct from old.catalog_taxonomy_discovered_at;

    -- **Un caché sobrevive a su origen y deja de ser suyo.** La taxonomía la
    -- produjo un proveedor concreto leyendo una ruta concreta: si cambia el
    -- proveedor, el tenant, el origen del portal o el adaptador que dice dónde
    -- leerla y cómo recorrerla, lo guardado describe otra cosa. Conservarlo
    -- haría que un caché vigente se heredara por otro proveedor o por una
    -- configuración distinta, y el ERP enumeraría nodos que ya no existen.
    v_identity_changed :=
      new.tenant_id is distinct from old.tenant_id
      or new.supplier_id is distinct from old.supplier_id
      or new.search_url_template is distinct from old.search_url_template
      or new.need_search_url_template
         is distinct from old.need_search_url_template
      or new.need_search_adapter is distinct from old.need_search_adapter;

    if v_identity_changed and not v_touched_cache then
      -- Se invalida, no se bloquea: cambiar la configuración es legítimo, y
      -- lo único que no puede pasar es que el caché viejo siga pareciendo
      -- vigente. La próxima necesidad lo vuelve a descubrir.
      new.catalog_taxonomy := null;
      new.catalog_taxonomy_discovered_at := null;
      return new;
    end if;
    if not v_touched_cache then
      return new;
    end if;
  end if;
  if tg_op = 'INSERT'
     and new.catalog_taxonomy is null
     and new.catalog_taxonomy_discovered_at is null then
    return new;
  end if;

  select pg_catalog.pg_get_userbyid(class.relowner)
  into v_owner
  from pg_catalog.pg_class class
  join pg_catalog.pg_namespace namespace
    on namespace.oid = class.relnamespace
  where namespace.nspname = 'public'
    and class.relname = 'supplier_portal_probes';

  -- El dueño de la tabla (y quien pueda asumirlo) escribe: por ahí pasan las
  -- migraciones y el recibo `security definer`. Nadie más.
  if v_owner is not null
     and pg_catalog.pg_has_role(current_user, v_owner, 'MEMBER') then
    return new;
  end if;

  raise exception
    'catalog_taxonomy is written only through record_supplier_portal_catalog_taxonomy_v1'
    using errcode = '42501';
end;
$$;

comment on function public.supplier_portal_probes_guard_catalog_cache() is
  'El caché de taxonomía es del servidor: sólo el dueño de la tabla lo escribe, y el resto pasa por el recibo. No estorba a las ediciones de configuración.';

drop trigger if exists supplier_portal_probes_guard_catalog_cache
  on public.supplier_portal_probes;
create trigger supplier_portal_probes_guard_catalog_cache
  before insert or update on public.supplier_portal_probes
  for each row
  execute function public.supplier_portal_probes_guard_catalog_cache();

-- ---------------------------------------------------------------------------
-- 2. Cobertura de una búsqueda, separada de su estado
-- ---------------------------------------------------------------------------

alter table public.supplier_need_portal_searches
  add column if not exists coverage jsonb not null default '{}'::jsonb;

alter table public.supplier_need_portal_searches
  drop constraint if exists supplier_need_portal_searches_coverage_check;
alter table public.supplier_need_portal_searches
  add constraint supplier_need_portal_searches_coverage_check check (
    jsonb_typeof(coverage) = 'object'
    and octet_length(coverage::text) <= 4096
    -- **Una cobertura completa sólo puede venir de haber enumerado.** Sin esta
    -- regla, cualquier corte —un tope propio, una sesión caída— podría
    -- guardarse como «catálogo completo» y el ERP afirmaría una ausencia que
    -- nadie comprobó.
    and (
      coalesce(coverage ->> 'complete', 'false') <> 'true'
      or coverage ->> 'limit' = 'enumerated'
    )
  );

comment on column public.supplier_need_portal_searches.coverage is
  'Cuánto del catálogo se enumeró: método, completitud, límite que la detuvo, nodos/páginas/filas. El estado dice cómo terminó la corrida; esto dice qué alcanzó a ver.';

-- ---------------------------------------------------------------------------
-- 2.b El CHECK del adaptador decía menos de lo que el cliente acepta
--
-- `supplier_portal_probes_need_adapter_check` (migración 20260828230000) exige
-- `families` o `categories`. El adaptador Dart, en cambio, acepta un portal que
-- declare sólo `generic_family_search` —hay prueba unitaria de eso— y ése es
-- justamente el caso de un proveedor que publica un buscador por palabra para
-- todo su catálogo. Con el CHECK anterior, ese portal válido no se podía
-- configurar: la solución general quedaba trabada en la base.
--
-- Se acepta uno de los tres, y nada más: forma, versión y tamaño siguen
-- cerrados, y `generic_family_search` cuenta sólo si es el booleano `true`
-- —una cadena `"true"` no alcanza—.
-- ---------------------------------------------------------------------------

alter table public.supplier_portal_probes
  drop constraint if exists supplier_portal_probes_need_adapter_check;
alter table public.supplier_portal_probes
  add constraint supplier_portal_probes_need_adapter_check check (
    need_search_adapter is null
    or (
      jsonb_typeof(need_search_adapter) = 'object'
      -- **Cada término va con `coalesce`, y no es cosmético.** Una clave
      -- ausente hace que `->` devuelva NULL, la comparación sea NULL, y un
      -- CHECK cuya expresión es NULL **pasa**. Sin esto el guardián acepta
      -- cualquier objeto que no sea explícitamente falso: fail-open. Lo
      -- encontró la prueba de «un adaptador que no declara nada».
      and coalesce(need_search_adapter ->> 'version' = '1', false)
      -- **Presente no es lo mismo que declarado.** `families: {}` es un objeto
      -- y pasaba el chequeo de tipo, pero el adaptador Dart lo lee como mapa
      -- vacío y —sin el flag genérico— lanza `FormatException`, que en
      -- `enabledProbe` apaga la capacidad EN SILENCIO. La base aceptaba una
      -- configuración que el cliente ignora: el peor de los dos mundos, porque
      -- el portal queda «configurado» y no busca nada.
      --
      -- `jsonb_object_length` no existe en PostgreSQL 17.6 (comprobado contra
      -- `pg_proc`); la comparación con `'{}'::jsonb` es el equivalente y, a
      -- diferencia de un `jsonb_each`, sí se puede escribir en un CHECK —una
      -- función que devuelve conjuntos no está permitida acá—.
      and (
        coalesce(
          jsonb_typeof(need_search_adapter -> 'families') = 'object'
          and need_search_adapter -> 'families' <> '{}'::jsonb,
          false
        )
        or coalesce(
          jsonb_typeof(need_search_adapter -> 'categories') = 'object'
          and need_search_adapter -> 'categories' <> '{}'::jsonb,
          false
        )
        or coalesce(
          need_search_adapter -> 'generic_family_search' = 'true'::jsonb, false
        )
      )
      and octet_length(need_search_adapter::text) <= 32768
    )
  );

-- ---------------------------------------------------------------------------
-- 3. RBX: ruta de catálogo, dónde leer la taxonomía y presupuesto
--
-- Verificado en una carga autenticada real: la ruta responde por GET y es
-- request-driven (un control negativo con otra clasificación cambió las filas,
-- y volver reprodujo las mismas). `tamanopagina` se IGNORA: el portal sirve 9
-- pase lo que pase, así que el tamaño declarado es el que sirve, no el que uno
-- pediría — declarar 27 haría que la primera página de 9 se leyera como página
-- corta y cerrara el nodo con un tercio del catálogo.
-- ---------------------------------------------------------------------------

update public.supplier_portal_probes probe
set need_search_adapter = probe.need_search_adapter
      || jsonb_build_object(
        'catalog_route', jsonb_build_object(
          'url_template',
            'http://www.rburgos.cl/sitio/aplicaciones/catalogo.asp'
            || '?url=cat_sel_cf.asp&url1=cat_sel_sf.asp&folio=0'
            || '&Clasificacion2={node}&paginaabsoluta={page}'
            || '&tamanopagina={page_size}',
          'page_size', 9,
          'first_page', 1,
          'max_pages_per_node', 12
        ),
        'taxonomy_discovery', jsonb_build_object(
          'url',
            'http://www.rburgos.cl/sitio/aplicaciones/seleccion.asp?folio=0',
          'parent_field', 'Clasificacion1',
          'child_field', 'Clasificacion2',
          'max_parent_probes', 3,
          'ttl_hours', 24
        ),
        'budget', jsonb_build_object(
          'max_nodes', 3,
          'max_pages', 15,
          'max_rows', 240,
          'wall_clock_seconds', 90
        ),
        'result_cap', 120
      ),
    updated_at = now()
from public.suppliers supplier
where supplier.id = probe.supplier_id
  and supplier.tenant_id = probe.tenant_id
  and supplier.name = 'RBX'
  and probe.need_search_adapter is not null
  and probe.need_search_adapter->>'version' = '1';

-- ---------------------------------------------------------------------------
-- 4. El recibo acepta la cobertura y el tope que la enumeración necesita
-- ---------------------------------------------------------------------------

-- La firma cambia: se elimina la anterior para que PostgREST no quede con dos
-- funciones del mismo nombre y una llamada ambigua.
drop function if exists public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb
);

create or replace function public.record_supplier_need_portal_search_v1(
  p_supplier_id uuid,
  p_supply_need_id uuid,
  p_search_query text,
  p_status text,
  p_source_url text default null,
  p_results jsonb default '[]'::jsonb,
  p_evidence jsonb default '{}'::jsonb,
  p_coverage jsonb default '{}'::jsonb
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
  v_adapter jsonb;
  v_result_cap integer;
  v_coverage jsonb := coalesce(p_coverage, '{}'::jsonb);
  v_source_url text := nullif(btrim(coalesce(p_source_url, '')), '');
  v_id uuid;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;

  select probe.need_search_term_limit, probe.need_search_adapter
  into v_limit, v_adapter
  from public.supplier_portal_probes probe
  where probe.tenant_id = v_tenant_id
    and probe.supplier_id = p_supplier_id
    and probe.is_enabled
    and probe.need_search_url_template is not null;

  if v_limit is null
     or v_adapter is null
     or jsonb_typeof(v_adapter) <> 'object'
     or v_adapter->>'version' <> '1' then
    raise exception 'Need search is not configured' using errcode = 'P0002';
  end if;

  -- **El tope del cliente y el del recibo son el mismo número.** El adaptador
  -- lo publica y la app lo lee: por eso acá se valida contra él y no contra
  -- una constante que quedaría desalineada en la siguiente subida.
  v_result_cap := least(
    greatest(coalesce((v_adapter->>'result_cap')::integer, 40), 1),
    120
  );

  if char_length(v_query) not between 1 and v_limit
     or p_status not in (
       'completed', 'no_matches', 'session_expired', 'unreadable'
     )
     or jsonb_typeof(coalesce(p_results, 'null'::jsonb)) <> 'array'
     or jsonb_array_length(p_results) > v_result_cap
     or (p_status <> 'completed' and jsonb_array_length(p_results) > 0)
     or octet_length(p_results::text) > 98304
     or jsonb_typeof(coalesce(p_evidence, 'null'::jsonb)) <> 'object'
     or octet_length(p_evidence::text) > 8192
     or octet_length(coalesce(v_source_url, '')) > 500
     or (
       v_source_url is not null
       and (
         v_source_url !~ '^https?://'
         or position('?' in v_source_url) > 0
         or position('#' in v_source_url) > 0
         or position('@' in v_source_url) > 0
       )
     ) then
    raise exception 'Invalid need portal search' using errcode = '22023';
  end if;

  if jsonb_typeof(v_coverage) <> 'object'
     or octet_length(v_coverage::text) > 4096
     or (
       v_coverage <> '{}'::jsonb
       and (
         coalesce(v_coverage ->> 'method', '') not in (
           'taxonomy', 'word_search', 'none'
         )
         or coalesce(v_coverage ->> 'limit', '') not in (
           'enumerated', 'max_nodes', 'max_pages', 'max_rows', 'wall_clock',
           'storage_cap', 'loop_detected', 'session_expired', 'parser_drift',
           'encoding', 'transport', 'word_search_only', 'not_attempted'
         )
         or jsonb_typeof(v_coverage -> 'complete') <> 'boolean'
       )
     ) then
    raise exception 'Invalid need portal coverage' using errcode = '22023';
  end if;

  -- Una cobertura completa sólo la produce una enumeración terminada, y
  -- jamás el buscador por palabra ni una corrida que no concluyó.
  if v_coverage ->> 'complete' = 'true'
     and (
       v_coverage ->> 'limit' <> 'enumerated'
       or v_coverage ->> 'method' <> 'taxonomy'
       or p_status in ('session_expired', 'unreadable')
     ) then
    raise exception 'Coverage cannot claim a complete catalogue'
      using errcode = '22023';
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
       or (
         result ? 'observedFacts'
         and jsonb_typeof(result->'observedFacts') <> 'object'
       )
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
    source_url, results, evidence, coverage, created_by
  ) values (
    v_tenant_id, p_supplier_id, p_supply_need_id, v_query, p_status,
    v_source_url, p_results, p_evidence, v_coverage, auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object('status', 'recorded', 'searchId', v_id);
end;
$$;

revoke all on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb
) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. La cobertura viaja de vuelta con la última búsqueda
-- ---------------------------------------------------------------------------

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
    'results', search.results,
    'coverage', search.coverage
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

-- ---------------------------------------------------------------------------
-- 6. Guardar la taxonomía descubierta
-- ---------------------------------------------------------------------------

create or replace function public.record_supplier_portal_catalog_taxonomy_v1(
  p_supplier_id uuid,
  p_taxonomy jsonb
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
  v_nodes jsonb := p_taxonomy -> 'nodes';
  v_now timestamptz := now();
  v_stored jsonb;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_taxonomy, 'null'::jsonb)) <> 'object'
     or jsonb_typeof(v_nodes) <> 'array'
     or jsonb_array_length(v_nodes) = 0
     or jsonb_array_length(v_nodes) > 2000
     or octet_length(p_taxonomy::text) > 262144
     or coalesce(btrim(p_taxonomy ->> 'fingerprint'), '') = ''
     or exists (
       select 1
       from jsonb_array_elements(v_nodes) node
       where jsonb_typeof(node) <> 'object'
          or coalesce(btrim(node ->> 'id'), '') = ''
          or coalesce(btrim(node ->> 'label'), '') = ''
          or octet_length(node ->> 'id') > 120
          or octet_length(node ->> 'label') > 160
     ) then
    raise exception 'Invalid supplier catalog taxonomy' using errcode = '22023';
  end if;

  -- **La hora del descubrimiento es del servidor, de punta a punta.** El TTL
  -- del cliente se lee de este campo: si el que llama pudiera fecharlo, una
  -- fecha futura dejaría el caché fresco para siempre y el portal no se
  -- volvería a leer nunca. Se ignora lo que venga y se estampa acá.
  v_stored := jsonb_set(
    p_taxonomy,
    '{discoveredAt}',
    to_jsonb(to_char(v_now at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')),
    true
  );

  update public.supplier_portal_probes probe
  set catalog_taxonomy = v_stored,
      catalog_taxonomy_discovered_at = v_now,
      updated_at = v_now
  where probe.tenant_id = v_tenant_id
    and probe.supplier_id = p_supplier_id
    and probe.is_enabled;

  if not found then
    raise exception 'Supplier portal probe not found' using errcode = 'P0002';
  end if;

  -- Se devuelve la hora estampada para que el cliente no tenga que confiar en
  -- su propio reloj ni volver a leer la fila.
  return jsonb_build_object('status', 'recorded', 'discoveredAt', v_now);
end;
$$;

revoke all on function public.record_supplier_portal_catalog_taxonomy_v1(
  uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.record_supplier_portal_catalog_taxonomy_v1(
  uuid, jsonb
) to authenticated;

commit;
