---
titulo: Carrito, checkout y pedidos online
resumen: cómo compra un cliente en vinabike.cl, qué pagos acepta, qué pasa con el stock, la venta y los correos, y dónde opera el pedido el equipo
fuentes: [repositorio]
archivos: [docs/runbooks/ONLINE_ORDER_OPERATIONS.md, docs/user-guides/WEBSITE_ONLINE_SALES_USER_GUIDE.md, lib/public_store/pages/checkout_page.dart, lib/public_store/pages/order_confirmation_page.dart, lib/public_store/providers/cart_provider.dart, lib/public_store/services/public_checkout_capability_service.dart, lib/modules/website/pages/online_orders_page.dart, lib/modules/website/services/mercadopago_service.dart]
tablas: [online_orders, online_order_items, online_order_inventory_reservations, online_order_access_tokens, online_order_payment_preferences, online_order_events, online_order_official_documents, online_order_corrections, website_settings]
revisado: 2026-10-04
---

# Carrito, checkout y pedidos online

## Lo esencial

El cliente arma el carrito, elige retiro o envío, paga con **Mercado Pago** o
**transferencia**, y el pedido aparece en el ERP (`Sitio Web > Pedidos online`,
`/website/orders`) con una alerta. El runbook que manda es
`docs/runbooks/ONLINE_ORDER_OPERATIONS.md`; esta página resume `[Repo]`.

## Cinco cosas que no se confunden

Pedido (lo que pidió), pago (la evidencia del banco o Mercado Pago), venta ERP
(dueña del stock y los asientos), comprobante del operador de pago (no
tributario) y boleta electrónica (DTE del SII). Hasta que exista una integración
DTE verificable, los PDF dicen «Comprobante de pedido — no constituye documento
tributario» `[Repo]`.

## El recorrido del cliente

1. **Carrito** (`/carrito`): `CartProvider` con almacenamiento local y candado
   entre pestañas (`cart_lock`).
2. **Checkout** (`/checkout`): `get_public_checkout_capabilities` dice qué
   métodos y entregas están activos; `quote_public_online_shipping` cotiza el
   envío; `google-places-proxy` autocompleta la dirección. Un producto sin tasa
   de IVA explícita bloquea el checkout `[Repo]`.
3. **Crear el pedido:** `create_public_online_order_with_access` congela precio,
   costo e IVA por línea, **reserva** las unidades (disponible = físico − reservas
   activas, para que dos clientes no compren la última) y devuelve un token de
   acceso `[Repo]`.
4. **Pago:**
   - Mercado Pago: `mercadopago-create-preference` → pago en Mercado Pago →
     `mercadopago-webhook` (firma HMAC validada antes de nada, se vuelve a
     consultar el pago por API) → el pago se confirma en una transacción
     propia antes de crear la venta ERP. Las preferencias vencen
     (`mercadopago-expire-preferences`).
   - Transferencia: el pedido queda pendiente con las instrucciones; el equipo
     confirma con **Confirmar transferencia** (cartola, monto exacto, fecha,
     referencia), nunca editando el estado a mano.
5. **Confirmación** (`/pedido/:id`): se abre con el token
   (`get_public_online_order_by_access_token`); `noindex`. Correo transaccional
   por `send-transactional-order-email` (Resend).

## Correos al cliente

Cada cambio del pedido escribe un evento (`online_order_events`); un disparador
(`enqueue_transactional_email_from_order_event`) lo convierte en un correo en
`transactional_email_outbox`, y el worker `send-transactional-order-email` lo
envía por Resend desde **Ventas Viñabike <ventas@vinabike.cl>**; los eventos de
entrega vuelven por `resend-transactional-webhook` `[Repo]` `[Prod 2026-10-04]`.

| Evento del pedido | Correo | Asunto |
|---|---|---|
| pedido creado | `order_received` | «Recibimos tu pedido …» |
| pago a `paid` | `payment_confirmed` | «Pago confirmado · …» |
| `processing` | `processing` | «Estamos preparando tu pedido …» |
| `ready_for_pickup` | `ready_for_pickup` | «Tu pedido … está listo para retiro» |
| `shipped` | `shipped` | «Tu pedido … ya fue enviado» (con seguimiento si hay URL) |
| `delivered` | `delivered` | «Tu pedido … fue entregado» |
| `cancelled` | `cancelled` | «Actualización de tu pedido …» |
| reembolso | `refund_completed` | «Reembolso completado · …» |

Estado real (2026-10-04) `[Prod]`: el worker está activo en `send`, corre cada
minuto y no tiene errores. En producción sólo se han enviado `order_received` (3
entregados, 1 fallido el 19-jul) y `cancelled` (5 entregados): **ningún pedido real
llegó a pagarse desde que existe este sistema**, así que los correos de pago,
preparación, retiro, envío y entrega no se han visto en vivo. El taller no recibe
correo de un pedido nuevo: tiene el aviso dentro del ERP (`Sitio Web`, badge y
notificaciones).

## Cuentas de cliente

- Se crean con correo (con confirmación: `mailer_autoconfirm` falso) o con Google;
  el checkout ofrece crear la cuenta al comprar (casilla) y liga el pedido al
  cliente si hay sesión `[Repo: checkout_page.dart]`.
- Los 13 correos de cuenta (confirmación, recuperación, enlace de acceso,
  invitación…) son plantillas propias del repo (`supabase/templates/`) y en
  producción coinciden exactamente (`scripts/auth/sync_supabase_auth_email_templates.mjs`,
  modo de sólo lectura, sin diferencias). Límite: 30 correos por hora, que
  Supabase sólo permite con servidor de correo propio `[Prod 2026-10-04]`.

## Estados del pedido

Pendiente → Confirmado → En preparación → Listo para retiro / Despachado →
Entregado; o Cancelado (sólo impago, con motivo). Sin retrocesos silenciosos: una
excepción es una operación aparte con motivo, actor y hora. Un pedido pagado no
se cancela: va por devolución, corrección o nota de crédito y reembolso
(`mercadopago-refund-payment`) `[Repo]`.

## Estado real

- El checkout estuvo **caído desde julio** (último pedido web: 19-jul) porque
  Mercado Pago y transferencia no se ofrecían; se reparó el 2026-09-23
  (`20260923200000`) y se probó con un pedido real de $800 que luego se anuló
  `[Repo]`.
- 72 pedidos y 75 líneas en total (aprox., 2026-10-03) `[Prod]`.
- **Última venta web pagada: WEB-26-00015, el 2026-05-03.** Después sólo hay
  pedidos de prueba, todos anulados (2026-10-04) `[Prod]`.

## Trampas

- Marcar un pago de Mercado Pago a mano: se espera el evento verificado.
- Descontar stock desde el pedido: sólo la venta ERP mueve stock y asientos.
- Cambiar el costo actual de un producto no reescribe el costo del pedido.
- Un pedido de prueba nace `confirmed` con su venta `sent` sin asientos ni stock;
  se anula con `transition_online_order_status`, no borrando filas.

## En el código y la base

- Tienda: `cart_page.dart`, `checkout_page.dart`,
  `order_confirmation_page.dart`, `cart_provider.dart`,
  `public_checkout_capability_service.dart`, `checkout_session_store.dart`,
  `checkout_exit_guard.dart`.
- ERP: `online_orders_page.dart`, `mercadopago_service.dart`,
  `order_communication_service.dart`, `online_order_official_document_service.dart`,
  política en `online_order_workflow_policy.dart`.
- Tablas: `online_orders`, `online_order_items` y las `online_order_*` de
  reservas, tokens, preferencias, eventos, documentos y correcciones.
- Funciones: `mercadopago-*`, `send-transactional-order-email`,
  `resend-transactional-webhook`, `google-places-proxy`.
