-- Una cuenta de cliente deja de leer el costo y el proveedor de los productos.
--
-- `products_select` dejaba a cualquier usuario con sesión leer, además de los
-- productos de su empresa, todos los productos publicados de cualquier
-- empresa. El registro de clientes está abierto (correo y Google) y un cliente
-- no tiene perfil de staff, así que `user_tenant_id()` le da nulo y entraba
-- por esa rama con todas las columnas, costo y proveedor incluidos
-- (diagnóstico web del 2026-09-23, fase 1b). No se cierra con permisos de
-- columna porque el staff usa el mismo rol y necesita el costo.
--
-- La tienda ya lee el catálogo como anónimo aunque el cliente haya iniciado
-- sesión (`PublicCatalogClient`), y las RPC públicas son SECURITY DEFINER.
-- Hoy ningún usuario del staff tiene perfiles activos en dos empresas, el
-- único caso en que `user_tenant_id()` también da nulo.
--
-- Se despliega después de publicar la tienda que usa `PublicCatalogClient`:
-- con la versión anterior, un cliente con sesión vería el catálogo vacío.
alter policy products_select on public.products
  using (tenant_id = (select public.user_tenant_id()));

-- En bases armadas desde el esquema histórico la misma rama vive en una
-- política aparte; en producción no existe y esto no hace nada.
drop policy if exists public_products_select_authenticated on public.products;
