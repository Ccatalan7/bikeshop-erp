-- «Agregar imagen…» de un proveedor nunca pudo guardar.
--
-- El comando escribía `public.suppliers` **directo desde el cliente**, y el rol
-- `authenticated` no tiene ningún grant sobre esa tabla: ni UPDATE ni SELECT.
-- Cada comando hermano del módulo —`create_supplier_engagement` y compañía— va
-- por una RPC `security definer`; éste se quedó fuera de esa regla y contestaba
-- «permission denied for table suppliers» (42501) apenas se elegía la imagen.
-- Medido en producción el 2026-09-17 con la app de escritorio.
--
-- La función sigue la misma forma que sus hermanas: pertenencia activa al
-- tenant salvo para `service_role`, el proveedor tiene que existir dentro del
-- tenant, y devuelve la fila que el llamador verifica contra su propio scope.

create or replace function public.update_supplier_image_url(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_image_url text
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_image_url text := nullif(btrim(coalesce(p_image_url, '')), '');
  v_row public.suppliers%rowtype;
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required'
      using errcode = '42501';
  end if;

  update public.suppliers
     set image_url = v_image_url,
         updated_at = now()
   where tenant_id = p_tenant_id
     and id = p_supplier_id
  returning * into v_row;

  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'id', v_row.id,
    'tenant_id', v_row.tenant_id,
    'image_url', v_row.image_url
  );
end;
$function$;

-- Una función nueva nace con el grant por defecto de `public`: se retira y se
-- entrega explícitamente, igual que sus hermanas.
revoke all on function public.update_supplier_image_url(uuid, uuid, text) from public;
grant execute on function public.update_supplier_image_url(uuid, uuid, text)
  to authenticated, service_role;
