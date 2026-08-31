-- Una corrida del portal ya hecha se puede recuperar, y no se guarda dos veces.
--
-- **El problema medido (2026-08-30).** Con el gateway de Supabase degradado,
-- cuatro corridas seguidas contra RBX terminaron bien —portal recorrido, filas
-- leídas, veredicto calculado— y murieron en el guardado con
-- `504 upstream request timeout`. El RPC responde en 7 ms: lo que falla es el
-- transporte, así que el resultado queda DESCONOCIDO —la escritura pudo haber
-- entrado—. Sin una clave estable, reintentar duplicaría el recibo; sin
-- reintentar, se pierden minutos de navegación real y el operador tiene que
-- volver a buscar.
--
-- **Lo que agrega.** `operation_key` con su unicidad por tenant, el mismo
-- patrón que ya usan `supply_need_batch_receipts` y los recibos de venta:
-- si la clave ya existe se devuelve el recibo guardado con `replay: true`, y
-- si viene con otra petición se rechaza con `23505` en vez de pisarlo.
-- `operation_request` guarda la huella de la petición para poder distinguir un
-- reintento de una reutilización indebida de la clave.
--
-- Agrega también `supplier_need_portal_search_by_operation_key_v1`, de sólo
-- lectura: ante un resultado desconocido se pregunta primero si la corrida ya
-- quedó registrada, que es más seguro y más barato que reintentar la escritura.
--
-- **Y corrige una puerta que quedó cerrada.** El RPC exigía
-- `need_search_url_template is not null`, o sea la plantilla del buscador por
-- navegador. Una tienda que contesta por API de catálogo —WooCommerce,
-- PrestaShop— podía buscar pero no guardar lo que encontraba.
--
-- Hacia adelante y sin romper: la clave es opcional, así que un cliente que
-- todavía no la manda sigue insertando como antes.

begin;

alter table public.supplier_need_portal_searches
  add column if not exists operation_key text,
  add column if not exists operation_request jsonb;

alter table public.supplier_need_portal_searches
  drop constraint if exists supplier_need_portal_searches_operation_key_check;
alter table public.supplier_need_portal_searches
  add constraint supplier_need_portal_searches_operation_key_check
  check (
    operation_key is null
    or (
      octet_length(operation_key) between 1 and 160
      and operation_key = btrim(operation_key)
    )
  );

-- La unicidad es por tenant: dos negocios pueden generar la misma clave sin
-- pisarse, y dentro de uno la misma corrida entra una sola vez.
create unique index if not exists
  supplier_need_portal_searches_tenant_operation_key_idx
  on public.supplier_need_portal_searches (tenant_id, operation_key)
  where operation_key is not null;

CREATE OR REPLACE FUNCTION public.record_supplier_need_portal_search_v1(p_supplier_id uuid, p_supply_need_id uuid, p_search_query text, p_status text, p_source_url text, p_results jsonb, p_evidence jsonb, p_coverage jsonb, p_expected_need_version bigint, p_expected_revision_no bigint, p_expected_category_id uuid, p_expected_technical_family text, p_operation_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
 SET statement_timeout TO '9000ms'
AS $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_query text := btrim(coalesce(p_search_query, ''));
  v_limit integer;
  v_adapter jsonb;
  v_result_cap integer;
  v_coverage jsonb := coalesce(p_coverage, '{}'::jsonb);
  v_source_url text := nullif(btrim(coalesce(p_source_url, '')), '');
  v_id uuid;
  v_operation_key text := nullif(btrim(coalesce(p_operation_key, '')), '');
  v_request jsonb;
  v_existing public.supplier_need_portal_searches%rowtype;
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
    -- **Una tienda con API de catálogo no necesita URL de buscador.** El
    -- requisito de `{query}` describe el camino por navegador; WooCommerce y
    -- PrestaShop contestan por JSON, y exigirles además una plantilla de
    -- página las dejaba buscar sin poder guardar lo que encontraron.
    and (
      probe.need_search_url_template is not null
      or probe.need_search_adapter -> 'catalog_api' is not null
    );

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

  -- **La estampa la captura quien INICIA el recorrido, no quien lo guarda.**
  -- Un crawl que empezó en la revisión N y termina después de que alguien
  -- guardó N+1 tiene que perderse, no reetiquetarse: sus filas se leyeron
  -- contra otra ficha. El disparador compara esto contra la revisión vigente
  -- y rechaza la diferencia.
  if p_expected_need_version is null
     or p_expected_revision_no is null
     or p_expected_category_id is null
     or p_expected_need_version <= 0
     or p_expected_revision_no <= 0
     or octet_length(coalesce(p_expected_technical_family, '')) > 80 then
    raise exception 'Need search must declare the interpretation it answered'
      using errcode = '23514';
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

  -- **La misma corrida no se guarda dos veces.** Un 504 del gateway deja el
  -- resultado DESCONOCIDO: la escritura pudo haber entrado. Reintentar a
  -- ciegas duplicaría el recibo de una lectura del portal que costó minutos
  -- de navegación real. La clave se genera antes de abrir el portal y viaja
  -- con la corrida, así que el reintento es la misma operación, no otra.
  if v_operation_key is not null then
    if octet_length(v_operation_key) > 160 then
      raise exception 'Invalid need portal search' using errcode = '22023';
    end if;
    v_request := jsonb_build_object(
      'supplierId', p_supplier_id,
      'supplyNeedId', p_supply_need_id,
      'query', v_query,
      'status', p_status,
      'revisionNo', p_expected_revision_no
    );
    select search.* into v_existing
    from public.supplier_need_portal_searches search
    where search.tenant_id = v_tenant_id
      and search.operation_key = v_operation_key;
    if found then
      -- Reusar una clave con OTRA petición es un error del llamador, no un
      -- reintento: se rechaza en vez de pisar el recibo anterior.
      if v_existing.operation_request is distinct from v_request then
        raise exception 'La clave de operación pertenece a otra búsqueda.'
          using errcode = '23505';
      end if;
      return jsonb_build_object(
        'status', 'recorded',
        'searchId', v_existing.id,
        'replay', true
      );
    end if;
  end if;

  insert into public.supplier_need_portal_searches (
    tenant_id, supplier_id, supply_need_id, search_query, status,
    source_url, results, evidence, coverage, created_by,
    need_version_at_search, interpretation_revision_no,
    interpretation_category_id, interpretation_technical_family,
    operation_key, operation_request
  ) values (
    v_tenant_id, p_supplier_id, p_supply_need_id, v_query, p_status,
    v_source_url, p_results, p_evidence, v_coverage, auth.uid(),
    p_expected_need_version, p_expected_revision_no,
    p_expected_category_id, p_expected_technical_family,
    v_operation_key, v_request
  )
  returning id into v_id;

  return jsonb_build_object(
    'status', 'recorded',
    'searchId', v_id,
    'replay', false
  );
end;
$function$
;

-- Resolver un resultado desconocido sin escribir nada.
--
-- Ante un 504 la app pregunta primero por acá: si la corrida ya quedó
-- registrada devuelve su id, y sólo si no está se reintenta la escritura con
-- la misma clave. Una lectura no puede empeorar un estado desconocido.
CREATE OR REPLACE FUNCTION public.supplier_need_portal_search_by_operation_key_v1(
  p_operation_key text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '5000ms'
AS $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_key text := nullif(btrim(coalesce(p_operation_key, '')), '');
  v_search public.supplier_need_portal_searches%rowtype;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if v_key is null or octet_length(v_key) > 160 then
    raise exception 'Invalid operation key' using errcode = '22023';
  end if;

  select search.* into v_search
  from public.supplier_need_portal_searches search
  where search.tenant_id = v_tenant_id
    and search.operation_key = v_key;

  if not found then
    return jsonb_build_object('status', 'missing');
  end if;

  return jsonb_build_object(
    'status', 'recorded',
    'searchId', v_search.id,
    'checkedAt', to_char(
      v_search.checked_at at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'replay', true
  );
end;
$function$
;

revoke all on function
  public.supplier_need_portal_search_by_operation_key_v1(text) from public;
grant execute on function
  public.supplier_need_portal_search_by_operation_key_v1(text)
  to authenticated;

commit;
