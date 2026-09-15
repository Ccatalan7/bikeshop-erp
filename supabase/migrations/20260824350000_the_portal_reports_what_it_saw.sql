-- El portal cuenta lo que vio, y ese informe es lo que permite configurarlo.
--
-- Nadie puede escribir la sonda de un portal sin haberlo visto por dentro, y
-- por dentro sólo se entra con la sesión del taller. Esta RPC recibe el
-- reconocimiento que el navegador integrado hizo estando logueado y lo guarda
-- como evidencia: qué buscadores hay, si la sesión estaba viva, y qué se parece
-- a un precio o a un stock.
--
-- Se guarda como un chequeo con estado `probe_missing`, que es exactamente lo
-- que es: todavía no hay sonda configurada para ese portal, y esto es lo que
-- se vio mientras no la había.
--
-- **No recibe credenciales ni las mira.** Resuelve el proveedor por el origen
-- de la página, que es un dato público de la navegación.
--
-- RBX publica su catálogo por `http://`. La restricción de HTTPS se levanta
-- para el template porque negarse dejaría la función inservible justo en el
-- proveedor que la motivó — pero el transporte queda registrado en la
-- evidencia, para que la interfaz pueda decirlo cuando corresponda.

begin;

alter table public.supplier_portal_probes
  drop constraint if exists supplier_portal_probes_https_check;

alter table public.supplier_portal_probes
  add constraint supplier_portal_probes_scheme_check
  check (
    search_url_template like 'https://%'
    or search_url_template like 'http://%'
  );

-- El dominio raíz de una URL: `portal.rburgos.cl` y `www.rburgos.cl` son el
-- mismo proveedor. Sin esto, el login y el catálogo de RBX parecen dos sitios
-- distintos y el reconocimiento no encuentra a quién pertenece.
create or replace function public.registrable_domain_internal_v1(p_url text)
returns text
language sql
immutable
parallel safe
set search_path = pg_catalog, pg_temp
as $$
  select nullif(
    (
      select string_agg(part, '.' order by ord)
      from (
        select part, ord
        from regexp_split_to_table(
          split_part(
            regexp_replace(lower(btrim(coalesce(p_url, ''))),
              '^[a-z]+://', ''),
            '/', 1
          ),
          '\.'
        ) with ordinality as labels(part, ord)
        order by ord desc
        limit 2
      ) tail
    ), ''
  )
$$;

revoke all on function public.registrable_domain_internal_v1(text)
  from public, anon, authenticated, service_role;

create or replace function public.record_supplier_portal_discovery_v1(
  p_origin_url text,
  p_payload jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_supplier record;
  v_origin text;
  v_id uuid;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  v_origin := btrim(coalesce(p_origin_url, ''));
  if v_origin = ''
     or octet_length(v_origin) > 400
     or jsonb_typeof(coalesce(p_payload, 'null'::jsonb)) <> 'object'
     -- Un informe enorme no aporta más y sí llena la tabla: la sonda ya recorta
     -- su muestra de página.
     or octet_length(p_payload::text) > 24576 then
    raise exception 'Invalid discovery payload' using errcode = '22023';
  end if;

  -- El proveedor se resuelve por el origen de la página, no por lo que diga el
  -- cliente: así una pestaña cualquiera no puede escribir evidencia a nombre de
  -- un proveedor que no es.
  --
  -- La comparación es por DOMINIO RAÍZ y no por origen exacto, porque un portal
  -- vive en otro host que su login: RBX entra por `portal.rburgos.cl` y
  -- despacha el catálogo en `www.rburgos.cl`. Exigir el origen exacto habría
  -- dejado sin reconocer justo al proveedor que motivó esto.
  select supplier.id, supplier.name
  into v_supplier
  from public.supplier_credentials credential
  join public.suppliers supplier
    on supplier.id = credential.supplier_id
   and supplier.tenant_id = credential.tenant_id
   and supplier.is_active is true
  where credential.tenant_id = v_tenant_id
    and credential.origin_url is not null
    and public.registrable_domain_internal_v1(credential.origin_url)
      = public.registrable_domain_internal_v1(v_origin)
  order by supplier.name
  limit 1;

  if v_supplier.id is null then
    return jsonb_build_object(
      'status', 'no_supplier_for_origin',
      'origin', v_origin
    );
  end if;

  insert into public.supplier_availability_checks (
    tenant_id, supplier_id, product_id, supplier_code, status,
    source_url, evidence, created_by
  ) values (
    v_tenant_id, v_supplier.id, null, null, 'probe_missing',
    left(v_origin, 400),
    jsonb_build_object(
      'kind', 'discovery',
      'insecureTransport', v_origin like 'http://%',
      'report', p_payload
    ),
    auth.uid()
  )
  returning id into v_id;

  return jsonb_build_object(
    'status', 'recorded',
    'checkId', v_id,
    'supplierId', v_supplier.id,
    'supplierName', v_supplier.name
  );
end;
$$;

revoke all on function public.record_supplier_portal_discovery_v1(text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.record_supplier_portal_discovery_v1(text, jsonb)
  to authenticated;

commit;
