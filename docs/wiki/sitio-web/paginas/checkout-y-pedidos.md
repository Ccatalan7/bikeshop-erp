---
titulo: Carrito, checkout y pedidos online
resumen: cómo compra un cliente en vinabike.cl, qué pagos acepta, qué pasa con el stock, la venta y los correos, y dónde opera el pedido el equipo
fuentes: [repositorio]
archivos: [docs/runbooks/ONLINE_ORDER_OPERATIONS.md, supabase/functions/_shared/mercadopago_paid_amount.ts, supabase/functions/_shared/transactional_email/templates.ts, supabase/migrations/20261013120000_mercadopago_paid_amount_includes_shipping.sql, supabase/migrations/20261013150000_online_order_test_flag.sql, services/storefront_html/lib/src/checkout_page_view.dart, services/storefront_html/lib/src/checkout_page_script.dart, services/storefront_html/lib/src/checkout_records_script.dart, services/storefront_html/tool/local_checkout_seed.sql, supabase/migrations/20261006090000_public_checkout_processes_signed_in_transfer.sql, docs/user-guides/WEBSITE_ONLINE_SALES_USER_GUIDE.md, lib/public_store/pages/checkout_page.dart, lib/public_store/pages/order_confirmation_page.dart, lib/public_store/providers/cart_provider.dart, lib/public_store/services/public_checkout_capability_service.dart, lib/modules/website/pages/online_orders_page.dart, lib/modules/website/widgets/online_order_sheet.dart, lib/modules/website/services/online_order_shipping_label_pdf.dart, lib/modules/website/widgets/online_order_shipping_label_dialog.dart, lib/modules/website/widgets/shipment_receipt_dialog.dart, lib/modules/website/services/online_order_shipment_service.dart, lib/modules/website/models/online_order_shipment.dart, lib/modules/website/widgets/online_order_shipment_section.dart, supabase/migrations/20261013210000_online_order_shipment_receipt.sql, supabase/migrations/20261013220000_transactional_email_brand_from_site_theme.sql, supabase/migrations/20261013230000_online_order_shipment_email_preview.sql, supabase/migrations/20261014010000_online_order_shipment_expense.sql, supabase/migrations/20261014020000_online_order_shipment_expense_skips_tests.sql, supabase/migrations/20261014030000_online_shipping_zones.sql, lib/modules/website/pages/shipping_zones_page.dart, lib/modules/website/models/shipping_zone.dart, lib/modules/website/widgets/shipment_expense_fields.dart, supabase/functions/preview-transactional-order-email/index.ts, lib/shared/widgets/email_html_view.dart, lib/modules/website/services/mercadopago_service.dart, supabase/migrations/20261009020000_online_order_push_alert.sql, supabase/functions/push-notification/online_order_push.ts]
tablas: [online_orders, online_order_items, online_order_inventory_reservations, online_order_access_tokens, online_order_payment_preferences, online_order_events, online_order_official_documents, online_order_corrections, online_order_shipments, online_shipping_zones, online_shipping_rate_tiers, expenses, expense_attachments, website_settings]
revisado: 2026-10-13
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

1. **Carrito** (`/carrito`): desde el 2026-10-06 lo dibuja el servidor HTML.
   Lo que el visitante eligió vive en su navegador (el mismo documento que
   lee `CartProvider`, con su candado entre pestañas); la página pide
   `/carrito/lineas` y el servidor vuelve a leer precio, stock y tasa de IVA
   de cada producto, ajusta al stock y dibuja líneas y resumen con la misma
   regla de IVA que el checkout (`StorefrontTaxSummary`, en el núcleo). Un
   producto sin tasa bloquea «Proceder al pago» `[Repo]`.
2. **Checkout** (`/checkout`): `get_public_checkout_capabilities` dice qué
   métodos y entregas están activos; `quote_public_online_shipping` cotiza el
   envío **con la región de la dirección** (ver «Despacho por zona»);
   `google-places-proxy` autocompleta la dirección. Un producto sin tasa
   de IVA explícita bloquea el checkout `[Repo]`. Desde el 2026-10-06 lo
   dibuja el servidor HTML (d487113c): manda el formulario y los medios de
   pago; el navegador pide `/checkout/lineas`, cotiza y crea el pedido con
   **las mismas llamadas** que Flutter, y guarda el mismo registro de
   recuperación (`CheckoutSessionStore`: intento, recibo, acceso al pedido,
   resultado del carrito), que también lee la app. Con la sesión del cliente
   (`sb-<ref>-auth-token` de Flutter, renovada si venció) liga el pedido a su
   cuenta y guarda la dirección `[Repo]`.
3. **Crear el pedido:** `create_public_online_order_with_access` congela precio,
   costo e IVA por línea, **reserva** las unidades (disponible = físico − reservas
   activas, para que dos clientes no compren la última) y devuelve un token de
   acceso `[Repo]`.
4. **Pago:**
   - Mercado Pago: `mercadopago-create-preference` → pago en Mercado Pago →
     `mercadopago-webhook` (firma HMAC validada antes de nada, se vuelve a
     consultar el pago por API) → el pago se confirma en una transacción
     propia antes de crear la venta ERP. Las preferencias vencen
     (`mercadopago-expire-preferences`). El despacho va en la preferencia
     como `shipments.cost` y **Mercado Pago sí lo cobra**, pero lo informa
     aparte: el pago trae `transaction_amount` (productos) y
     `shipping_amount` (despacho); lo que vale para el pedido es la suma
     (`mercadoPagoOrderPaidAmount`). Los intereses de cuotas que paga el
     comprador quedan en `total_paid_amount` y no son del pedido `[Repo]`
     `[Prod 2026-10-13]`.
   - Transferencia: el pedido queda pendiente con las instrucciones; el equipo
     confirma con **Confirmar transferencia** (cartola, monto exacto, fecha,
     referencia), nunca editando el estado a mano.
5. **Confirmación** (`/pedido/:id`): se abre con el token
   (`get_public_online_order_by_access_token`); `noindex`. Correo transaccional
   por `send-transactional-order-email` (Resend). Desde el 2026-10-06 (fase 3c)
   la dibuja el servidor HTML: el marco es el mismo para todos (con los datos
   de transferencia del editor) y el navegador toma el token de la pestaña,
   cierra el carrito una vez, **verifica** el regreso de Mercado Pago con
   `mercadopago-get-payment` antes de creerle a `?status=` y lee el pedido. El
   PDF del resumen lo arma el servidor (`POST /pedido/resumen.pdf`, token en el
   cuerpo) con el mismo código que la app (`buildOrderSummaryPdf`, núcleo)
   `[Repo]`.

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
| `shipped` | `shipped` | «Tu pedido … ya fue enviado»: transportista, servicio, el código en grande, botón a la página de seguimiento, admisión, dirección de entrega y total pagado |
| `delivered` | `delivered` | «Tu pedido … fue entregado» |
| `cancelled` | `cancelled` | «Actualización de tu pedido …» |
| reembolso | `refund_completed` | «Reembolso completado · …» |

Los dos correos con montos (`order_received`, `payment_confirmed`) muestran
**Productos**, **Despacho a domicilio** (o «Retiro en tienda · Sin costo») y
el total como «Total a pagar» o «Total pagado»; el de pedido recibido dice
además «Pago: Pendiente de confirmación» mientras no esté pagado. Hasta el
2026-10-13 mostraban los productos y un «Total» sin la línea de despacho, y
el cliente de WEB-26-00021 vio $11.000 y «Total $17.990» sin explicación
`[Repo]`.

Estado real (2026-10-04) `[Prod]`: el worker está activo en `send`, corre cada
minuto y no tiene errores. En producción sólo se han enviado `order_received` (3
entregados, 1 fallido el 19-jul) y `cancelled` (5 entregados): **ningún pedido real
llegó a pagarse desde que existe este sistema**, así que los correos de pago,
preparación, retiro, envío y entrega no se han visto en vivo. El taller no recibe
correo de un pedido nuevo: tiene el aviso dentro del ERP (`Sitio Web`, badge y
notificaciones) y, desde el 2026-10-09, **el teléfono de cada persona del
equipo suena aunque la app esté cerrada**. Un pedido por transferencia (o
contra entrega) avisa apenas se crea, para revisar la cartola; uno de Mercado
Pago avisa cuando queda pagado, para prepararlo. No avisa por un carrito de
Mercado Pago sin pagar: 41 de 63 nunca se pagaron. Con el ERP abierto, el
pago deja además el aviso «Venta online pagada» dentro del ERP. Tocar el
aviso abre el pedido (`trg_online_orders_push_alert` → `push-notification`, detalle en
`docs/NOTIFICATION_IMPLEMENTATION.md` §1.6) `[Repo]`.

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

## Pedidos de prueba

Al 2026-10-13 había 78 pedidos y sólo WEB-26-00021 era una venta (el dueño:
«nuestra primera venta oficial»). Los 77 anteriores eran pruebas del propio
taller y quedaron marcados con `online_orders.is_test` (migración
`20261013150000`, 77 filas) `[Prod 2026-10-13]`. La lista del ERP los oculta de
sus listas y conteos; se ven con «Pruebas» y se marcan o desmarcan uno a uno con
`set_online_order_test_flag` (comando auditado como `test_flag_changed`). La
marca no toca ventas, stock ni contabilidad. 19 pruebas tenían venta ERP; 4 ya
estaban anuladas y las otras 15 se anularon el mismo día por orden del dueño
`[Prod 2026-10-13]`: las 7 sin pago con «Descartar factura», las 8 pagadas con
nota de crédito completa (NCV-00001 a 00008). Mercado Pago confirmó por API
que 7 de esos 8 cobros fueron dinero real (en vivo, acreditados, sin devolver,
~$400); el octavo (WEB-25-00052) no existe en esta cuenta. Ese dinero quedó
como saldo a favor de los clientes de prueba, no borrado. Un pedido de prueba
nuevo se marca desde su menú «⋯»; si alcanzó a crear venta, la venta se anula
aparte, desde Ventas. El Dashboard del sitio cuenta igual que la lista: «Pedidos por
atender» y «Pedidos históricos» sin pruebas `[Repo]`; antes decía 41 «por
revisar» con un solo pedido real esperando, porque contaba `status = 'pending'`
con las pruebas dentro. La lista abre en **«Activos»** —todo lo que no está
entregado, cancelado ni devuelto— y le sigue «Por atender» (dueño,
2026-10-13: «la principal debería ser de las órdenes activas»; antes abría en
«Por atender» y un pedido despachado desaparecía de la vista inicial).

## Despacho por zona

Desde el 2026-10-14 el despacho se cobra **según la región de destino**
`[Dueño 2026-10-14]`: «revisa cómo lo hacen todos nuestros competidores más
importantes y haz lo mismo». Lo que hacen `[Ref 2026-10-14]`: Oxford, Cycling
Store y, en Viña, Tienda Ride y Padrobikes cobran el despacho en el checkout,
calculado por destino y tamaño (peso o volumen); Oxford lo regala sobre
$29.990 en comunas de Santiago durante promociones. «Por pagar» (el cliente
paga al recibir) sólo lo hacen Bikeventura (Quilpué, Starken) y Ruka como
opción. Todos tienen retiro en tienda sin costo.

El catálogo no tiene pesos ni medidas (0 de 1.463 productos web,
`[Prod 2026-10-14]`), así que el tamaño sigue siendo el **tramo de subtotal** y
se agrega el destino: `online_shipping_zones` agrupa regiones (código ISO
3166-2:CL) y cada zona tiene sus tramos en `online_shipping_rate_tiers`
(`20261014030000`). El checkout manda la región que trae la dirección (Google,
dirección guardada o escrita) y `online_shipping_region_code` la reconoce
(«Región de Valparaíso», «V Región», «RM»…). Una región fuera de toda zona
dice «Por ahora no despachamos a la región de …» antes de pagar; sin región
todavía, el resumen dice «Según tu región». El pedido vuelve a cotizar con su
`shipping_state` y debe calzar con lo que vio el cliente.

Se edita en **Sitio Web › Envíos** (`/website/shipping`,
`shipping_zones_page.dart`): zonas con su nombre, sus regiones (una región en
una sola zona) y sus tramos «desde / hasta / despacho / días»; guarda todo junto
con `save_online_shipping_zones`. Lo anterior queda inactivo, no se borra: cada
pedido guarda el tramo con que se cobró. Los tramos que había quedaron en la
zona «Todo Chile» (las 16 regiones): nada cambió de precio hasta configurar
zonas.

## Etiqueta de despacho

Desde el 2026-10-13 la ficha del pedido imprime la etiqueta de la caja
(«Etiqueta de despacho», al final de «Entregar a» o en el menú «⋯») `[Repo]`.
Antes se escribía a mano. Formato: 10 × 15 cm, el de bulto que reciben
Chilexpress, Starken, Pullman Cargo y Correos de Chile y que imprime una
térmica; o carta con dos por hoja para recortar. Lleva lo que pide el mesón:
destinatario (nombre, dirección, comuna en grande, región, código postal,
teléfono y RUT), indicaciones del cliente, remitente con RUT de la empresa,
pedido, fecha de envío, valor declarado (los productos, no el despacho),
contenido y código de barras del pedido. **Peso y medidas no existen en la base
y el RUT del cliente casi nunca**: quedan como líneas para llenar a mano al
pesar la caja. El courier pega además su propia etiqueta con su número de
envío; la nuestra no la reemplaza `[Dueño 2026-10-13]`.

## Despacho con la boleta

Desde el 2026-10-13 el despacho se registra con la **foto de la boleta del
transportista** (la que el compañero manda desde el mesón) `[Dueño 2026-10-13]`
`[Repo]`. «Registrar despacho» —el siguiente paso de un pedido con despacho
pagado, confirmado o en preparación— abre un diálogo que:

1. Recibe la foto (cámara en el teléfono; archivo, arrastrar o PDF en el
   escritorio) o, sin boleta, los datos a mano.
2. La lee con IA (`gemini-3.6-flash` por `gemini-proxy`): transportista,
   servicio, código, fecha y sucursal de admisión, valor pagado,
   destinatario y si es boleta o factura con su folio. **Nunca el
   remitente**: la boleta trae el nombre y RUT de quien la llevó al mesón y
   no se guardan. **La fecha se coteja con el pedido**: una boleta del
   13-10-2026 se leyó «13/10/2020» `[Dueño 2026-10-13]`; una admisión
   anterior al pedido o futura pasa al año que calza (y lo dice bajo la
   fecha) o se descarta, y la base la rechaza en el registro y en la vista
   previa (`20261014010000`), porque el correo la muestra.
3. **Relee el código de seguimiento de cerca**: recorta la zona del código,
   la amplía y la lee tres veces (dos modelos). Gana la mayoría y queda
   «Confirmado de cerca» sólo si coinciden; si no, ofrece cada lectura para
   elegir y pide «Revisé…». Por qué: leyendo la foto entera, el modelo dio
   «77000000099» para un «770000000099» impreso en la mayoría de los
   intentos (los dos modelos, incluso deletreándolo); de cerca lo leyó bien
   en 9 de 9 `[Repo 2026-10-13]`. Un código mal leído llega al cliente.
4. Compara la boleta con el pedido (destinatario, RUT, comuna, calle y
   número, y el número de pedido si lo trae): una diferencia pide
   «Revisé la boleta y es de este pedido» antes de seguir.
5. **«Ver el correo antes de enviar»** (dueño, 2026-10-13: como la plantilla
   de WhatsApp antes de mandarla): «Así le llegará» muestra para quién, de
   quién, el asunto y **el correo mismo**, no una copia: la función
   `preview-transactional-order-email` lo dibuja con la plantilla del worker
   a partir de `preview_online_order_shipment_email`, que arma el contenido
   con el mismo `transactional_email_render_payload` que usa la cola y no
   escribe nada (`20261013230000`). Si el correo no saldría (sin dirección,
   bloqueado o en modo de prueba) lo dice antes.
6. **«Registrar el gasto del envío»**, encendido cuando hay valor pagado
   (dueño, 2026-10-13: «para no tener que agregarlo de nuevo en los gastos
   rápidos»): dice dónde cae (proveedor · línea), «Pagado con», «Boleta |
   Factura» y el folio. La base decide proveedor, cuenta y categoría
   (`online_order_shipment_expense_plan`: la plantilla de gasto del
   proveedor; si no, «Gastos por Transporte», como el gasto rápido) y el
   medio y documento por defecto (plantilla o último gasto de ese
   proveedor; si no, efectivo y boleta; lo leído en la boleta manda). Un
   **pedido de prueba no registra gasto** (`20261014020000`): WEB-26-00012 se
   despachó con una boleta inventada.
7. «Registrar despacho y enviar correo» sube la foto a
   `vinabike-files/<tenant>/evidence/online_order_shipment/<pedido>/` y llama
   `record_online_order_shipment`: guarda la boleta en
   `online_order_shipments`, registra el gasto (contabilizado y pagado como
   un gasto rápido: un asiento contra la cuenta del medio de pago, IVA
   crédito sólo con factura, la foto adjunta y el número del pedido como
   referencia), pasa el pedido a `shipped` y encola el correo «va en
   camino», todo en una transacción e idempotente: si el gasto no se puede
   registrar, no se registra nada. Lo que se registra es lo que se vio: la
   prueba de la base compara el correo encolado con la vista previa, igual
   byte a byte.

Un pedido **confirmado puede pasar directo a «Despachado»** con su boleta: la
boleta prueba que se preparó, y pasar antes por «En preparación» le mandaba al
cliente dos correos seguidos. La ficha muestra luego la sección **ENVÍO**:
transportista, servicio, el código con «Copiar», «Seguir envío», la admisión,
**pagado al transportista contra cobrado al cliente** (WEB-26-00021: $6.240
contra $6.990), el gasto («Gasto GTO-…» abre el gasto) y la miniatura de la
boleta. Un despacho registrado sin gasto (antes de 1.0.32, o con el
interruptor apagado) muestra «Registrar gasto»:
`record_online_order_shipment_expense`, una sola vez por despacho.

**El despacho cobrado es parte de la venta** `[Prod 2026-10-14]`: va como la
línea «Despacho a domicilio» (`line_kind: shipping`) de la venta ERP, con IVA,
y su neto entra a Ingresos Operacionales con el producto (WEB-26-00021:
$6.990 = $5.874 + IVA $1.116). Lo pagado al transportista es un gasto aparte.
Con **boleta** de Correos ese envío dejó −$366 (neto cobrado $5.874 contra
$6.240 sin crédito); con **factura** a nombre del taller el IVA ($996) es
crédito y deja +$630: conviene pedir factura en el mesón.

Las páginas de seguimiento (Correos de Chile `seguimiento-en-linea`,
Chilexpress, Starken, Blue Express) **no reciben el código en el enlace**
(revisado el 2026-10-13), así que el correo da el código en grande y dice
«cópialo y pégalo en la página de seguimiento de …» `[Repo]`. El largo del
código no se valida: la boleta de Correos del dueño traía 12 dígitos y los
envíos con formato postal internacional llevan 13 caracteres («AB123456789CL»);
no hay un formato único publicado `[Dueño 2026-10-13]`.

### El correo y la marca

Desde el 2026-10-13 todos los correos al cliente comparten un diseño nuevo
(`templates.ts`): logo y número de pedido arriba, una franja del color de la
marca con la etiqueta del estado, el título y el saludo, **los cinco pasos del
pedido** (Recibido · Pagado · Preparado · En camino | Listo para retiro ·
Entregado | Retirado), las tarjetas del caso (en «enviado»: envío con el
código y la dirección), la compra con su total y una franja de ayuda. El color
y las fuentes **salen del tema del editor del sitio** (`theme_primary_color`
—la app lo guarda como ARGB, p. ej. `4279385960` = `#123F68`—,
`theme_heading_font`, `theme_body_font`), que la cola copia al correo como
`store.brandColor`, `headingFont` y `bodyFont` (`20261013220000`); un nombre de
fuente que no es un nombre simple se descarta, y con un color claro el texto
de la franja pasa a oscuro. El logo cae a `company_logo_url` si el taller no
tiene uno propio. Gmail no carga las fuentes web: se ve en Arial/Helvetica.
**La foto de la boleta no se adjunta**: trae los datos del empleado y el valor
pagado `[Repo]`.

## Estado real

- **Primer correo «va en camino» entregado: 2026-10-13**, una prueba del
  dueño sobre su pedido de prueba WEB-26-00012 (boleta de prueba leída por la
  IA, vista previa, despacho y correo `delivered` en Resend) `[Prod 2026-10-13]`.
- El checkout estuvo **caído desde julio** (último pedido web: 19-jul) porque
  Mercado Pago y transferencia no se ofrecían; se reparó el 2026-09-23
  (`20260923200000`) y se probó con un pedido real de $800 que luego se anuló
  `[Repo]`.
- 72 pedidos y 75 líneas en total (aprox., 2026-10-03) `[Prod]`.
- **Última venta web pagada: WEB-26-00015, el 2026-05-03.** Después sólo hay
  pedidos de prueba, todos anulados (2026-10-04) `[Prod]`.
- **Primera venta web oficial: WEB-26-00021, el 2026-10-12**, con despacho.
  El cliente pagó completo ($11.000 + $6.990 = $17.990; a la tienda le
  llegaron $17.306 después de la comisión de $684), pero el webhook anotó
  sólo `transaction_amount` ($11.000) y lo rechazó por monto: sin venta ERP y
  marcado para revisar un reembolso que no correspondía. Ningún pago con
  despacho se había aprobado antes. Arreglado el 2026-10-13: las funciones
  suman `shipping_amount` y `20261013120000` reparó esa única observación.
  El dueño confirmó el adaptador en el local y se procesó el mismo día:
  venta INV-26-00019 pagada por $17.990 con su línea de despacho, stock a 0,
  asientos cuadrados y correo «Pago confirmado» al cliente `[Prod 2026-10-13]`.
- **Un cliente con sesión no podía pagar por transferencia (11-jul → 6-oct).**
  El checkout procesa al tiro cada pedido que no es de Mercado Pago con
  `process_online_order`, y desde `20260711123000` esa función rechaza a todo
  usuario autenticado que no sea personal de la tienda: el pedido se deshacía
  entero y el cliente veía «No pudimos confirmar el resultado». Un invitado
  pasaba. No hay ningún pedido así en esas fechas (sí de personal y de
  invitados) `[Prod 2026-10-06]`. Arreglo `20261006090000`: el checkout procesa
  su propio pedido con `process_public_checkout_order`, interna; se encontró
  probando el checkout HTML con la tienda de prueba local `[Repo]`.

## Trampas

- **`transaction_amount` no es lo que pagó el cliente** cuando hay despacho:
  Mercado Pago deja `shipments.cost` fuera y lo informa en `shipping_amount`.
  Comparar sólo `transaction_amount` con el total rechaza todo pago con
  despacho (2026-10-13). Leer los montos de un pago real por la API (sin
  imprimir la llave) antes de suponer qué cobró.

- Marcar un pago de Mercado Pago a mano: se espera el evento verificado.
- Descontar stock desde el pedido: sólo la venta ERP mueve stock y asientos.
- Cambiar el costo actual de un producto no reescribe el costo del pedido.
- Un pedido de prueba nace `confirmed` con su venta `sent` sin asientos ni stock;
  se anula con `transition_online_order_status`, no borrando filas.
- **Probar pedidos nunca en producción:** `services/storefront_html/tool/run_local_checkout.sh`
  siembra una tienda de prueba en la base local (`local_checkout_seed.sql`:
  productos con stock e IVA, las cuatro tarifas, los dos medios de pago con
  datos falsos y un cliente con contraseña de prueba) y sirve el HTML contra
  ella. Las funciones Edge no corren en local: la prueba del navegador las
  responde (Mercado Pago, Places).
- Un pedido por transferencia nace `confirmed` y crea su venta en la misma
  llamada; con sesión, esa llamada corre con el JWT del cliente, así que
  cualquier guarda de «personal de la tienda» en ese camino tumba el pedido.
- Para mirar la página del pedido sin crear uno: la prueba del navegador deja
  el acceso en `sessionStorage` y responde ella misma
  `get_public_online_order_by_access_token` (y `mercadopago-get-payment`); así
  se comparan Flutter en producción y el HTML con el mismo pedido inventado,
  sin que nada llegue a la base. Hay que cortar GA4 y Meta: la página mide
  `purchase` en cada carga.
- La puerta de Supabase acepta la clave publicable nueva (`sb_publishable_…`)
  como `Authorization` en las funciones con `verify_jwt` (la app usa la clave
  `anon` antigua): una llamada vacía a `mercadopago-get-payment` y
  `mercadopago-create-preference` llega a la función (400/403 de su código, no
  «Invalid JWT») `[Prod 2026-10-06]`.

## En el código y la base

- Tienda HTML: `services/storefront_html/lib/src/cart_page_model.dart`,
  `cart_page_view.dart` (carrito y `/carrito/lineas`); `checkout_page_view.dart`,
  `checkout_page_css.dart`, `checkout_page_script.dart` (formulario, cotización,
  pedido, Mercado Pago) y `checkout_records_script.dart` (los registros de
  `CheckoutSessionStore`, probados contra Flutter en
  `test/unit/storefront_html_checkout_contract_test.dart`); `order_page_view.dart`,
  `order_page_css.dart`, `order_page_script.dart` (página del pedido) y
  `order_summary_pdf_route.dart` (`POST /pedido/resumen.pdf`).
- Núcleo: `public_store/documents/order_summary_pdf.dart` (el resumen en PDF de
  las dos tiendas) y `public_store/models/online_order_labels.dart` (palabras de
  los estados), con `test/unit/order_summary_pdf_contract_test.dart`.
- Tienda Flutter: `cart_page.dart` (en el editor y en `/tienda`), `checkout_page.dart`,
  `order_confirmation_page.dart`, `cart_provider.dart`,
  `public_checkout_capability_service.dart`, `checkout_session_store.dart`,
  `checkout_exit_guard.dart`.
- ERP: `online_orders_page.dart` (lista y tabla), `online_order_sheet.dart` (la
  ficha del pedido: franja con total, pago, entrega y avance; hoja con productos,
  cliente, pago y evidencia; barra con WhatsApp, llamar y el siguiente paso, desde
  el 2026-10-13), `mercadopago_service.dart`, `order_communication_service.dart`,
  `online_order_official_document_service.dart`, política (transiciones y avance
  de cuatro pasos) en `online_order_workflow_policy.dart`; la etiqueta de
  despacho en `online_order_shipping_label_pdf.dart` (el PDF) y
  `online_order_shipping_label_dialog.dart` (vista previa, papel, bultos,
  descargar e imprimir); el despacho con boleta en `shipment_receipt_dialog.dart`
  (diálogo), `online_order_shipment_service.dart` (lectura con IA, recorte del
  código, subida y comando), `online_order_shipment.dart` (transportistas,
  lectura, cotejo con el pedido y `plausibleAdmission`),
  `online_order_shipment_section.dart` (sección ENVÍO de la ficha) y
  `shipment_expense_fields.dart` (el gasto del envío en el diálogo y en
  «Registrar gasto»).
- Boleta del envío: tabla `online_order_shipments` y comando
  `record_online_order_shipment` (`20261013210000`); la marca del correo desde
  el tema en `20261013220000`.
- Vista previa del correo: `preview_online_order_shipment_email`, el
  constructor compartido `transactional_email_render_payload`, el asunto
  `transactional_email_subject` y la lectura de la boleta
  `online_order_shipment_from_input` (`20261013230000`); la función
  `preview-transactional-order-email`; en la app `email_html_view.dart`.
- Gasto del envío y fecha de admisión: `online_order_shipments.expense_id`,
  `online_order_shipment_expense_plan`, `online_order_shipment_create_expense`,
  `online_order_shipment_expense_options`, `record_online_order_shipment`
  con `p_expense`, `record_online_order_shipment_expense` y
  `online_order_shipment_check_admission` (`20261014010000`); el pedido de
  prueba sin gasto en `20261014020000`.
- Pedido de prueba: columna `online_orders.is_test` y comando
  `set_online_order_test_flag` (`20261013150000`).
- Tablas: `online_orders`, `online_order_items` y las `online_order_*` de
  reservas, tokens, preferencias, eventos, documentos y correcciones.
- Base: `create_public_online_order_with_access` → `create_public_online_order_unkeyed`
  → `process_public_checkout_order` (transferencia) `[Repo]`.
- Funciones: `mercadopago-*`, `send-transactional-order-email`,
  `preview-transactional-order-email`,
  `resend-transactional-webhook`, `google-places-proxy`.
