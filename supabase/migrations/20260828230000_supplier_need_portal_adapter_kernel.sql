-- La búsqueda por necesidad deja de ser un caso Dart para RBX/motores.
--
-- La interpretación de lenguaje natural ya produjo categoría + predicados
-- tipados y la categoría ya resuelve su ficha técnica. Esta columna sólo
-- describe cómo UN portal expresa esa familia: vocabulario, navegación,
-- columnas y capturas. Agregar otra familia o proveedor pasa a ser dato.

begin;

alter table public.supplier_portal_probes
  add column if not exists need_search_adapter jsonb;

alter table public.supplier_portal_probes
  drop constraint if exists supplier_portal_probes_need_adapter_check;
alter table public.supplier_portal_probes
  add constraint supplier_portal_probes_need_adapter_check check (
    need_search_adapter is null
    or (
      jsonb_typeof(need_search_adapter) = 'object'
      and need_search_adapter->>'version' = '1'
      and (
        coalesce(
          jsonb_typeof(need_search_adapter->'families') = 'object', false
        )
        or coalesce(
          jsonb_typeof(need_search_adapter->'categories') = 'object', false
        )
      )
      and octet_length(need_search_adapter::text) <= 32768
    )
  );

comment on column public.supplier_portal_probes.need_search_adapter is
  'Adaptador versionado por proveedor: taxonomía, navegación y parser para buscar una necesidad técnica. La app falla cerrada si la familia no está configurada.';

-- Lo que se observó en RBX: el catálogo de motores se abre con dos selects,
-- la palabra acota a ejes sellados y sus filas publican Código, Descripción,
-- Marca, Origen y Valor. El patrón 73 x 118 no es una regla de RBX en Dart:
-- es la forma documentada en que esa familia expresa dos campos técnicos.
update public.supplier_portal_probes probe
set need_search_adapter = jsonb_build_object(
      'version', 1,
      'initial_url',
        'http://www.rburgos.cl/sitio/aplicaciones/seleccion.asp?folio=0',
      'session_error_pattern',
        'Microsoft OLE DB Provider[\s\S]*Sintaxis incorrecta cerca de',
      'result_schema', jsonb_build_object(
        'columns', jsonb_build_object(
          'code', jsonb_build_array('Código'),
          'name', jsonb_build_array('Descripción'),
          'brand', jsonb_build_array('Marca'),
          'origin', jsonb_build_array('Origen'),
          'price', jsonb_build_array('Valor')
        ),
        'no_result_phrases',
          jsonb_build_array('No hay ningún producto que mostrar')
      ),
      'families', jsonb_build_object(
        'bottom_bracket', jsonb_build_object(
          'identity_family', 'bottom_bracket',
          'search_terms', jsonb_build_array('eje sellado'),
          'identity_terms', jsonb_build_array(
            'motor', 'movimiento central', 'caja pedalera', 'eje sellado'
          ),
          'navigation', jsonb_build_array(
            jsonb_build_object(
              'action', 'select_option',
              'field', 'Clasificacion1',
              'value', 'TRANSMISION Y PARTES'
            ),
            jsonb_build_object(
              'action', 'select_option',
              'field', 'Clasificacion2',
              'value', 'MOTOR (MOVIMIENTO CENTRAL)'
            )
          ),
          'capture_patterns', jsonb_build_array(
            jsonb_build_object(
              'pattern', $pattern$\b(\d{2,3}(?:[.,]\d+)?)\s*[x×/]\s*(\d{2,3}(?:[.,]\d+)?)\s*(?:mm)?\b$pattern$,
              'fields', jsonb_build_object(
                '1', 'bb_shell_width_mm',
                '2', 'spindle_length_mm'
              )
            )
          )
        )
      )
    ),
    updated_at = now()
from public.suppliers supplier
where supplier.id = probe.supplier_id
  and supplier.tenant_id = probe.tenant_id
  and supplier.name = 'RBX'
  and probe.need_search_url_template is not null;

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
  v_adapter jsonb;
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
    source_url, results, evidence, created_by
  ) values (
    v_tenant_id, p_supplier_id, p_supply_need_id, v_query, p_status,
    v_source_url, p_results, p_evidence, auth.uid()
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

commit;
