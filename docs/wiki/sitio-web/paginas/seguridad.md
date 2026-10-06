---
titulo: Seguridad y privacidad del sitio
resumen: qué puede leer o llamar un visitante sin cuenta y un cliente con cuenta, cómo se cerraron las fugas de septiembre y qué no hay que reabrir
fuentes: [repositorio]
archivos: [docs/development/SECURITY.md, lib/modules/website/models/website_seo_settings_aliases.dart, supabase/functions/google-places-proxy/index.ts, supabase/functions/mercadopago-webhook/index.ts]
tablas: [products, website_settings, customers, user_profiles, online_order_access_tokens]
revisado: 2026-10-03
---

# Seguridad y privacidad del sitio

## Lo esencial

El sitio corre en el navegador del visitante con la **clave pública** de
Supabase. Todo lo que esa clave puede leer o ejecutar es, en la práctica,
público. La seguridad vive en la base: RLS por empresa, permisos por columna y
funciones públicas que devuelven sólo lo publicable `[Repo]`.

**Regla del repo público:** este repositorio es público. Una fuga se cierra y se
despliega **primero**; el commit que la explica va después. Este wiki sólo
describe lo que ya está cerrado.

## Tres tipos de visitante

| Quién | Qué puede |
|---|---|
| Visitante sin cuenta (`anon`) | leer 55 columnas de `products` (sin costo ni proveedor), la configuración pública del sitio y llamar las funciones `get_public_*`, `search_public_products`, `resolve_public_product_url_alias`, `quote_public_online_shipping`, `create_public_online_order_with_access`, `get_public_online_order_by_access_token` ([mapa-del-sistema](mapa-del-sistema.md)) |
| Cliente con cuenta (`authenticated`, sin perfil de personal) | lo mismo, más **sus** pedidos, trabajos, bicis y chats en el portal. No lee el catálogo por la tabla ni los costos. Desde el 2026-10-06 el servidor HTML lee el portal con **el token del cliente** (nunca con una clave de servicio): RLS decide igual que en Flutter, cada lectura filtra la tienda, y el token no se guarda ni se anota. Desde la fase 4b también escribe con ese token: sólo `customers` y `customer_addresses`, siempre con la tienda en el filtro y con el cliente y la tienda puestos por el servidor; la base sólo deja cambiar nombre, teléfono, RUT y foto (`guard_customer_identity_update`). La contraseña nueva pasa por el servidor hacia Supabase Auth y tampoco se guarda ni se anota |
| Personal del taller (`authenticated` con `user_profiles`) | el ERP según su rol, siempre dentro de su empresa (`user_tenant_id()` sólo resuelve personal) |

`[Repo]` `[Prod 2026-10-03]`

## Lo que se cerró en septiembre de 2026

| Fecha | Migración | Qué cerró |
|---|---|---|
| 2026-09-23 | `20260923180000` | un visitante leía costo y proveedor de los productos: ahora sólo 55 columnas por permiso de columna |
| 2026-09-23 | `20260923190000` | una cuenta de cliente entraba por la rama «publicado» de la política de productos: quitada; el catálogo se lee por funciones públicas |
| 2026-09-23 | `20260923201000` | la búsqueda semántica (`search_products`, `match_products_semantic`) ya no la llama un visitante |
| 2026-09-24 | `20260924020000` | la vista de costos por marca (`product_gama_v1`, sobre una vista materializada sin RLS) salió de la API, y pgTAP pasó de `public` a `extensions` |
| 2026-09-24 | (Edge Function) | `google-places-proxy` endurecido: sólo autocompletado del checkout |

## Protecciones que no se tocan

- **Configuración sensible:** `website_setting_is_sensitive` decide qué claves de
  `website_settings` (claves de API, credenciales de integraciones) nunca salen
  en la configuración pública.
- **Pedidos:** la confirmación se abre con un token de acceso
  (`online_order_access_tokens`), no con el id; el webhook de Mercado Pago valida
  la firma HMAC antes de consultar o aplicar nada y no guarda datos de tarjeta.
- **Cabeceras** del target `store`: `X-Frame-Options: SAMEORIGIN`,
  `Referrer-Policy: strict-origin-when-cross-origin`, `X-Robots-Tag` en lo
  privado `[Prod]`.
- **`store_url`** es un origen HTTPS limpio: se rechazan credenciales, rutas,
  queries y fragmentos, en el editor, el generador y las integraciones por igual
  (`WebsiteSeoSettingsAliases.normalizeHttpsOrigin`).
- Cada consulta de la tienda filtra por empresa (`tenant_id`).

## Al cambiar algo

- Una función nueva en Supabase nace ejecutable por `anon`, `authenticated` y
  `service_role` (permisos por defecto): revocar lo que no corresponda en la misma
  migración y probarlo con `has_function_privilege`.
- Una columna nueva en `products` no queda pública sola: decidir si entra a las 55.
- Una vista materializada no tiene RLS: si queda en la API, cualquiera con la clave
  pública la lee entera (así se filtraban los costos por marca).
- Un registro abierto (cualquiera crea cuenta) significa que «autenticado» no es
  «de confianza»: nunca dar acceso por estar logueado.

## En el código y la base

- Políticas y permisos: migraciones de septiembre listadas arriba; pruebas pgTAP
  en `supabase/tests/`.
- Funciones públicas: `get_public_*` y compañía (`SECURITY DEFINER`, filtradas por
  empresa).
- Proceso de seguridad del repo: `docs/development/SECURITY.md`.
