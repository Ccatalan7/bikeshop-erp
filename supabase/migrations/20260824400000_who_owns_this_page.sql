-- Quién es el proveedor de esta página, sin escribir nada.
--
-- El chequeo necesita saber a qué proveedor pertenece el portal abierto ANTES
-- de preguntar nada. La función de reconocimiento resolvía eso de paso, pero
-- escribía evidencia: usarla sólo para preguntar dejaría una fila
-- `probe_missing` por cada chequeo.
--
-- Resuelve por dominio raíz, igual que el reconocimiento: `portal.rburgos.cl` y
-- `www.rburgos.cl` son el mismo proveedor.

begin;

create or replace function public.supplier_for_origin_v1(p_origin_url text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_supplier record;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if octet_length(coalesce(p_origin_url, '')) > 400 then
    raise exception 'Invalid origin' using errcode = '22023';
  end if;

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
      = public.registrable_domain_internal_v1(p_origin_url)
  order by supplier.name
  limit 1;

  if v_supplier.id is null then
    return jsonb_build_object('status', 'no_supplier_for_origin');
  end if;
  return jsonb_build_object(
    'status', 'found',
    'supplierId', v_supplier.id,
    'supplierName', v_supplier.name
  );
end;
$$;

revoke all on function public.supplier_for_origin_v1(text)
  from public, anon, authenticated, service_role;
grant execute on function public.supplier_for_origin_v1(text) to authenticated;

commit;
