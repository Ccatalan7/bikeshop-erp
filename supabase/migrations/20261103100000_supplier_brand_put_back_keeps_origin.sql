-- Volver a poner una marca quitada la deja como estaba (20261103090000).
--
-- La ficha del proveedor ofrece «Deshacer» al quitar una marca. Con
-- save_supplier_brand_v1 de 090000, reponerla la anotaba como «agregada a
-- mano» y borraba su evidencia: Shimano de Andes Industrial, que salió de su
-- sitio («Somos Shimano en Chile») y de nuestras compras, volvía sin nada de
-- eso. Reponer ahora sólo levanta removed_at: conserva de dónde salió, la
-- evidencia y cuándo se agregó; p_official decide «representante oficial»
-- (null: no lo es, porque quitar la marca se lo quitó).

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create or replace function public.save_supplier_brand_v1(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_brand_id uuid,
  p_official boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_actor uuid := auth.uid();
begin
  if v_role <> 'service_role' and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required' using errcode = '42501';
  end if;
  if p_supplier_id is null or not exists (
    select 1 from public.suppliers s
     where s.tenant_id = p_tenant_id and s.id = p_supplier_id
  ) then
    raise exception 'Supplier not found in tenant'
      using errcode = 'P0002', hint = 'supplier_not_found';
  end if;
  if p_brand_id is null then
    raise exception 'Brand is required'
      using errcode = '22023', hint = 'supplier_brand_not_found';
  end if;

  insert into public.supplier_brands as sb (
    tenant_id, supplier_id, brand_id, official, source, added_by
  ) values (
    p_tenant_id, p_supplier_id, p_brand_id, coalesce(p_official, false), 'manual', v_actor
  )
  on conflict (tenant_id, supplier_id, brand_id) do update
     set official = coalesce(p_official, case when sb.removed_at is null then sb.official else false end),
         removed_at = null,
         removed_by = null;

  return public.supplier_brands_v1(p_tenant_id, p_supplier_id);
end;
$$;

revoke all on function public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.save_supplier_brand_v1(uuid, uuid, uuid, boolean)
  to authenticated, service_role;

comment on function public.save_supplier_brand_v1(uuid, uuid, uuid, boolean) is
  'Agrega una marca a un proveedor, o repone una quitada tal como estaba (origen, evidencia, fecha), y cambia «representante oficial» si p_official no es null. Lo puede hacer cualquier miembro activo del taller, como el perfil del proveedor. Devuelve supplier_brands_v1.';

commit;
