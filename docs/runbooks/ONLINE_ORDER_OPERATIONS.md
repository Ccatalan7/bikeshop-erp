# Operación de pedidos online

Esta guía define cómo debe operar Viñabike un pedido de la tienda web y qué
evidencia debe existir antes de avanzar. La guía resumida vive también dentro
de **Sitio web > Pedidos online > Guía operativa**.

## Cinco evidencias que no deben confundirse

1. **Pedido**: intención comercial, productos, precio, entrega y estado
   logístico.
2. **Pago**: evidencia bancaria o del proveedor de pagos. Un pedido confirmado
   no implica, por sí solo, que esté pagado.
3. **Venta ERP**: documento interno que posee inventario y contabilidad. Puede
   estar preparada, contabilizada, pagada o cancelada. Su nombre técnico sigue
   siendo `sales_invoice_id`, pero no prueba por sí solo que exista una factura
   ni una boleta tributaria.
4. **Comprobante de pago del operador**: referencia publicada por Mercado Pago
   para acreditar la operación. El tipo técnico
   `mercadopago_payment_voucher` es siempre **no tributario**. El tipo separado
   `payment_voucher` puede tener valor de boleta solo bajo el modelo de emisión
   declarado por el comercio en SII y cuando cumple el contrato fiscal completo.
5. **Boleta electrónica (DTE)**: documento tributario emitido y aceptado por SII
   directamente o mediante un proveedor autorizado. No es sinónimo de un
   simple estado `approved` ni del PDF interno del ERP.

Hasta que exista una integración DTE verificable, los PDFs del ERP deben decir
**“Comprobante de pedido — no constituye documento tributario”** y nunca deben
presentarse como boleta o factura legal.

## Mercado Pago, voucher y boleta en Chile

Para ventas a consumidor final existen dos caminos legítimos; se debe usar uno
solo por transacción para no duplicar la venta ni el IVA:

Que la operación sea B2C determina que corresponde **boleta**, no factura. No
determina por sí solo quién la emite ni convierte automáticamente la respuesta
de un pago aprobado en documento tributario; eso depende del modelo vigente
declarado en SII y del artefacto efectivamente emitido.

1. **Voucher válido como boleta.** Viña Bike declara en SII el modelo “No emito
   boleta de ventas y servicios cuando recibo un pago electrónico”. En ese
   escenario, el comprobante electrónico que Mercado Pago informa al SII puede
   tener valor de boleta. La regla también contempla ventas por Internet, pero
   no convierte en boleta cualquier JSON del pago ni un PDF reconstruido por el
   ERP.
2. **Siempre emito boleta electrónica.** Viña Bike declara el modelo “Siempre
   emito boleta de ventas y servicios electrónica, aun cuando reciba un pago
   electrónico”. En ese escenario, el voucher acredita el pago, pero se debe
   emitir y entregar una BE/DTE separada. Mercado Pago recomienda este modelo
   cuando se contrata su servicio de boletas para evitar duplicidad.

Una **transferencia bancaria no genera un voucher de operador válido como
boleta**. Requiere una boleta electrónica separada.

El ERP aplica estas reglas de manera fail-closed:

- `payment_status = paid` habilita “Pago confirmado”, nunca “Boleta emitida”;
- el comprobante de pago Mercado Pago se ofrece solo cuando el pago aprobado
  fue validado y la respuesta oficial incluye un HTTPS público, completo y sin
  credenciales en `transaction_details.external_resource_url`; se etiqueta
  siempre **“No constituye boleta ni factura”**;
- el voucher válido como boleta sigue requiriendo, por separado, el modelo SII
  verificado, evidencia fiscal completa y hash del contenido del artefacto;
- una BE/DTE solo se ofrece cuando existe tipo, folio, estado emitido/aceptado y
  artefacto oficial;
- la venta ERP conserva stock y contabilidad, pero en la interfaz se muestra
  como **Venta ERP**, no como “Factura emitida”.

Antes de habilitar envíos reales hay que confirmar documentalmente en las
cuentas de Viña Bike:

- modelo de emisión vigente declarado en SII;
- si está contratado o no el servicio de boletas de Mercado Pago;
- qué producto de Mercado Pago origina cada cobro web y cómo se recupera su
  comprobante oficial;
- que el comprobante muestre los campos obligatorios y la leyenda fiscal
  correspondiente;
- flujo de anulación/nota de crédito y conciliación sin doble declaración.

Fuentes oficiales: [SII, voucher como boleta electrónica](https://www.sii.cl/destacados/boleta_electronica_voucher/index.html),
[Resolución Exenta SII N.º 176 de 2020](https://www.sii.cl/normativa_legislacion/resoluciones/2020/reso176.pdf) y
[Mercado Pago, boletas electrónicas y modelos de emisión](https://www.mercadopago.cl/mp/boletas-electronicas).

### Límite verificado de la API de Mercado Pago

La integración web actual usa Checkout Pro. La API pública documentada permite
[obtener un pago](https://www.mercadopago.cl/developers/es/reference/online-payments/checkout-pro/overview)
para verificar estado, `status_detail`, monto y conciliación, pero no publica un
endpoint de voucher fiscal ni de DTE para ese pago. El productor conserva una
distinción estricta cuando aparece `external_resource_url`:

- en Fintoc es la URL a la que se redirige al comprador para **completar** la
  transferencia;
- en 3DS es la URL del challenge del emisor;
- en pagos offline/tickets es una instrucción de pago pendiente.

Ninguno de esos recursos prueba la existencia, el contenido ni la aceptación
fiscal de un voucher. Por eso una URL solo es aceptable como comprobante de
pago no fiscal cuando la respuesta final está `approved`, posee operación,
fecha, monto y moneda completos, usa HTTPS en un dominio público oficial de
Mercado Pago/Mercado Libre y no contiene usuario, contraseña, fragmento ni
parámetros con credenciales. Su referencia se registra con
`artifact_hash_scope = reference_url`; no se presenta como hash del contenido
remoto. Si el campo no viene, el evento inmutable conserva explícitamente
`availability = absent`. Si es inseguro o incompleto conserva
`rejected_unsafe` o `incomplete`, sin inventar un documento ni encolar correo.

El recorder fiscal exige además una
transacción de tarjeta elegible, operación, autorización, últimos cuatro
dígitos, monto, moneda y hora de aprobación idénticos a esa observación, pero
permanece sin productor hasta recibir el artefacto oficial HTTPS y sus campos
fiscales desde un canal verificable.

El servicio de boletas de Mercado Pago se administra en su portal y su propia
[documentación comercial](https://www.mercadopago.cl/mp/boletas-electronicas)
indica que la consulta/descarga se realiza en **Tu negocio > Boletas y facturas
> Gestionar > Reportes**. También exige Point Smart para contratarlo y no
documenta ese portal como API de Checkout Pro. Automatizarlo mediante scraping
autenticado sería frágil, expondría credenciales tributarias y no constituye un
contrato soportado; está expresamente descartado.

El único paso humano pendiente para escoger y habilitar el camino fiscal es que
el representante legal descargue desde SII el comprobante vigente de
**Declaración de modelo de emisión** y lo entregue por el canal seguro de
evidencia. Si dice `No emito...`, además se debe obtener de Mercado Pago un
canal soportado para recuperar el voucher real de cada cobro Checkout Pro; si
dice `Siempre emito...`, se debe contratar y autorizar un emisor DTE con API.
Hasta entonces la aplicación puede enviar el estado de pago y, si el proveedor
lo publicó de forma segura, el correo de comprobante no fiscal. No puede enviar
`payment_voucher_available` ni `tax_document_issued` sin su evidencia fiscal.

## Flujo normal

| Estado del pedido | Significado | Quién lo cambia | Próxima acción permitida |
| --- | --- | --- | --- |
| Pendiente | El checkout fue recibido; falta validar el pago o aceptar operativamente el pedido. | Checkout / proveedor de pago | Confirmar o cancelar con motivo. |
| Confirmado | El pedido fue aceptado. El pago se consulta por separado. | Pago validado o trabajador autorizado | Preparar el pedido. |
| En preparación | Los ítems están siendo separados y revisados. | Trabajador autorizado | Marcar listo para retiro o despachado. |
| Listo para retiro | Pedido de retiro verificado y disponible en tienda. | Trabajador autorizado | Entregar. |
| Despachado | Pedido de envío entregado al transportista. | Trabajador autorizado | Registrar transportista, tracking y luego entregar. |
| Entregado | Cliente recibió el pedido. Estado terminal normal. | Trabajador autorizado | Solo corrección formal si aparece una incidencia. |
| Cancelado | Pedido impago anulado con motivo y trazabilidad. | Trabajador autorizado | No reabrir; crear un pedido nuevo si corresponde. |

No se permiten retrocesos silenciosos. Una excepción debe ser una operación
separada, con motivo, actor, hora y evidencia, nunca una reescritura del estado
anterior.

## Al recibir un pedido

1. Abrir el pedido desde la notificación o la tabla.
2. Verificar identidad de la tienda, líneas, cantidades, precio, moneda y tipo
   de entrega.
3. Revisar el estado de pago:
   - **MercadoPago**: esperar el evento verificado del proveedor. No marcar
     manualmente como pagado.
   - **Transferencia**: cotejar cartola, monto exacto, fecha y referencia; usar
     únicamente **Confirmar transferencia**.
4. Confirmar que existe disponibilidad o una reserva vigente antes de prometer
   entrega.
5. Revisar la venta ERP vinculada y cualquier alerta de reconciliación.
6. Avanzar solo al siguiente estado ofrecido por la interfaz.

## Pago, inventario y contabilidad

- MercadoPago solo se aplica desde un evento del proveedor validado por monto,
  moneda, tenant e idempotencia.
- El evento del proveedor se confirma en una transacción independiente **antes**
  de crear la venta ERP. Si luego falla stock, pago interno o contabilidad, el
  cobro aprobado permanece visible y el procesamiento queda en
  `action_required`; nunca se borra el pago externo por un error interno.
- En la tabla, **Revisar** permite reintentar la misma observación validada sin
  duplicar efectos. Si aparece **Conciliar**, no se reintenta ni se ajusta stock
  manualmente: se revisa el cobro en Mercado Pago y se decide la corrección o
  reembolso formal.
- La firma HMAC del webhook se valida antes de consultar o aplicar el pago. La
  carga completa del proveedor se vuelve a consultar por API; solo se conserva
  evidencia sanitizada y nunca tokens ni datos completos de tarjeta.
- Una transferencia solo se confirma mediante el comando atómico, con
  referencia y fecha. Nunca se edita `payment_status` directamente.
- La venta ERP es el único dueño de movimientos de stock y asientos.
- El pedido no debe descontar inventario por su cuenta.
- Cada línea conserva el precio y costo observados al comprar. Cambiar el costo
  actual del producto no debe reescribir el costo histórico del pedido.
- El IVA depende de la clasificación tributaria guardada en cada producto y se
  congela por línea al crear el pedido; jamás depende de si se pagó por
  Mercado Pago o transferencia. Un producto web sin tasa tributaria explícita
  debe bloquear el checkout hasta ser clasificado.
- Un pedido pagado no se cancela directamente. Debe usar devolución, corrección
  o nota de crédito y reembolso, preservando el documento original.

### Reserva autoritativa de inventario

Crear el pedido no descuenta stock físico, pero sí compromete inmediatamente
las unidades rastreadas en `online_order_inventory_reservations`. El catálogo y
todo checkout posterior usan **disponible = físico - reservas activas**, por lo
que dos clientes no pueden prometerse la misma última unidad. El mismo piso
protege POS, ajustes manuales y cualquier otro flujo que actualice
`products.inventory_qty` / `stock_quantity`.

- `active`: unidad comprometida, todavía sin movimiento físico;
- `consuming`: transición transaccional breve mientras se contabiliza la venta;
- `consumed`: la venta ERP ya creó los movimientos exactos y sus UUID quedaron
  vinculados a la reserva;
- `released`: cancelación impaga con motivo y evento;
- `expired`: venció la ventana de pago y la unidad volvió a estar disponible.

Los sets reservan cada componente según `product_set_components`; mientras la
reserva esté viva no se puede cambiar la receta ni reducir un componente por
debajo del compromiso. Servicios, consumibles de taller y productos con
`track_stock=false` no inventan reservas físicas. Una orden compuesta solo por
esas líneas usa el TTL de pago, pero no debe mostrar una reserva inexistente.

La ventana predeterminada es 30 minutos para Mercado Pago y 24 horas para
transferencia. Puede configurarse por tenant mediante
`online_order_reservation_minutes_mercadopago` y
`online_order_reservation_minutes_transfer`; el servidor limita Mercado Pago a
5–60 minutos y transferencia a 5 minutos–7 días. La expiración se ejecuta
periódicamente y también al intentar reservar, para no depender de que cron
haya corrido justo antes.

Para diagnóstico, administración debe consultar
`online_inventory_availability_view` y la secuencia append-only
`online_order_inventory_reservation_events`; nunca debe editar la proyección.
Si aparece una fila `consuming` persistente, una reserva `active` de un pedido
terminal o una diferencia entre cantidad reservada y movimiento de venta, se
detiene la operación y se concilia antes de tocar stock. El posting de factura,
la conversión a `consumed` y el movimiento físico son una sola transacción: un
fallo revierte todo, no deja una venta a medias.

### Vigencia y replay del checkout Mercado Pago

Una preferencia Checkout Pro es un recurso pagable, no un dato efímero de UI.
El servidor registra cada generación en
`online_order_payment_preferences`; el navegador nunca suministra tenant,
monto, líneas, tarifa de envío, descuento, URL de notificación, referencia ni
vencimiento.

- La referencia tiene formato
  `vb1:<tenant_uuid>:<order_uuid>:<generation>` y se valida nuevamente al leer
  el pago. Las referencias UUID antiguas se aceptan solo como compatibilidad.
- La vigencia predeterminada es 30 minutos. La tienda puede definir
  `online_order_reservation_minutes_mercadopago`, limitado por servidor a 5–60
  minutos. Para productos con stock, el vencimiento de la preferencia es
  exactamente el menor `expires_at` de la reserva autoritativa; servicios o
  productos sin seguimiento usan el TTL limitado.
- Un clic repetido devuelve la misma preferencia activa. Si se perdió la
  respuesta del proveedor, el servidor busca por la referencia externa y
  adopta únicamente una preferencia cuyo tenant, pedido, generación, monto CLP
  y vencimiento coinciden. Nunca interpreta un timeout como “no se creó”.
- Si venció la reserva, el reintento vuelve a reservar contra stock físico
  menos reservas concurrentes. Sin stock no se crea otra preferencia y el
  cliente debe revisar su carrito; si ya existía un enlace activo o un POST de
  resultado desconocido, ese recurso se conserva como evidencia y se encola
  inmediatamente para expiración en vez de volver a entregarse.
- Al cancelar el pedido o confirmar/reembolsar el pago, todas sus preferencias
  vivas pasan a `expiration_requested`. El worker
  `mercadopago-expire-preferences` actualiza su vigencia mediante la API oficial
  y conserva intentos/errores; no borra el recibo ni muestra de nuevo el enlace.
- Un pago aprobado que alcance un pedido ya cancelado se conserva como verdad
  financiera y queda para conciliación/reembolso. Nunca se aplica como si la
  cancelación lo hubiese impedido retroactivamente.

Este contrato usa únicamente operaciones documentadas de Checkout Pro:
[definir la vigencia de la preferencia](https://www.mercadopago.cl/developers/es/docs/checkout-pro/checkout-customization/preferences/term-of-preference),
[buscar por `external_reference`](https://www.mercadopago.cl/developers/es/reference/online-payments/checkout-pro/preferences/search-preferences/get)
y [actualizar una preferencia existente](https://www.mercadopago.cl/developers/es/reference/online-payments/checkout-pro/preferences/update-preference/put).

La activación del worker exige el mismo valor secreto en Edge
(`MERCADOPAGO_PREFERENCE_WORKER_SECRET`) y Vault
(`mercadopago_preference_worker_secret`), seguida por
`configure_mercadopago_preference_worker(true, 20)`. Sin ambos, el cron queda
instalado pero fail-closed. La observabilidad operativa mínima es:

- `creating`: POST en curso o resultado desconocido; un reintento recupera
  antes de crear;
- `active`: único enlace retornable mientras pedido y reserva siguen pagables;
- `expiration_requested` / `expiring`: no retornar enlace; cierre pendiente;
- `expiration_failed`: revisar credencial/API; el worker reintenta con backoff;
- `expired`: terminal, conserva identificador y timestamps del proveedor.

### Clasificación tributaria del catálogo

La tasa no se infiere desde el nombre, la categoría ni el medio de pago. Cada
cambio de `products.tax_rate` genera un evento inmutable con valor anterior,
valor nuevo, tenant, origen, actor y hora. El checkout copia esa clasificación
a `online_order_items`; un cambio posterior del catálogo nunca reescribe una
venta histórica.

El lote inicial `vinabike-public-catalog-iva19-20260718-v1` está limitado por
dos hashes sin PII y un conteo exacto: **1.582 registros**, formados por 1.525
productos y 57 servicios públicos, activos y con precio positivo. Se aplica
como IVA 19% solamente si la membresía y su snapshot comercial siguen siendo
idénticos al audit. La operación se detiene ante cualquier drift y su replay
devuelve el mismo recibo sin duplicar eventos.

Quedan deliberadamente fuera 11 registros públicos con precio cero, un
pseudo-producto de otro tenant y 61 registros no públicos. Deben revisarse y
clasificarse individualmente; no se permite completar esos casos por defecto ni
retrotraer la tasa actual hacia pedidos ya existentes.

## Corrección de un pedido pagado

La acción canónica vive en el inspector y en el menú de la misma fila de
**Pedidos online**. No se debe editar el pedido, la venta ERP, el stock o el
estado de pago por separado.

1. Abrir **Gestionar devolución** y seleccionar las líneas y cantidades contra
   el saldo real de la venta ERP, no contra el catálogo actual.
2. Para un producto físico elegir `Reponer`, `Cuarentena` o `Dar de baja`. Un
   servicio solo admite `Corrección financiera`: el mecánico no genera stock.
3. Registrar un motivo verificable. La solicitud congela líneas, monto CLP,
   intención, versión del pedido, actor y una clave de operación reintentable.
   Reutilizar la clave con datos distintos se rechaza; no reproduce una orden
   antigua silenciosamente.
4. Justo antes de mover dinero, una prevalidación de rol contable comprueba los
   tres controles activos, venta y medio de pago, saldo exacto, trazabilidad de
   movimientos físicos y proyección acumulada. Un cajero puede consultar la
   evidencia, pero no ejecutar el reembolso.
5. Si el pago es Mercado Pago, el ERP envía el reembolso con la misma
   `X-Idempotency-Key` en cada reintento. Si se pierde la respuesta, queda
   `resultado desconocido`; nunca se interpreta como fracaso ni se crea otra
   solicitud. Éxito es terminal: una respuesta tardía de error no lo borra.
   Respuestas 408/409/425/429/5xx son desconocidas, no rechazos definitivos.
   Para transferencias, administración/contabilidad debe confirmar
   referencia y fecha después de ejecutar la devolución fuera del ERP.
6. Solo después de conservar evidencia de dinero devuelto se aplican, en una
   segunda transacción, la devolución física, nota de crédito interna y asiento
   de reembolso. Los tres comandos reutilizan los kernels contables y de
   inventario existentes y son atómicos entre sí.
7. Si Mercado Pago devolvió el dinero pero falla stock o contabilidad, aparece
   `Requiere atención`. Reintentar aplica únicamente los efectos internos; no
   vuelve a mover dinero. También se registra este fallo en devoluciones
   manuales.

Una corrección parcial conserva `payment_status = paid` y acumula el monto
reembolsado. Al alcanzar el total exacto, el pedido pasa a `refunded`. El estado
logístico no retrocede automáticamente: un producto ya entregado sigue
entregado y su devolución queda en la evidencia de corrección. La acción
**Cancelar pedido** de un pedido pagado congela una intención diferente: solo
se admite antes del despacho/entrega, exige devolver todo el saldo y entonces
pasa a `cancelled`. Los documentos internos de una corrección aplicada no se
pueden anular por separado; requieren una futura compensación canónica.

## Comunicaciones al cliente

Solo se envía un email cuando existe un evento durable del pedido. Cada envío
debe tener clave idempotente, versión de plantilla, intentos, identificador del
proveedor y estados de entrega/rebote.

Cadencia recomendada:

- pedido recibido, con resumen e instrucciones de pago si corresponde;
- pago confirmado;
- pedido en preparación;
- listo para retiro;
- despachado, con tracking HTTPS cuando exista;
- entregado;
- cancelado;
- reembolso completado;
- DTE emitido, únicamente después de una emisión tributaria comprobada.

Una devolución parcial conserva `paid`, pero igualmente crea un único outbox
`refund_completed` por corrección, con monto de esa devolución, acumulado y
marca `partialRefund`. No se falsifica una transición a reembolso total.
- comprobante de pago Mercado Pago disponible, únicamente después de registrar
  el enlace oficial del proveedor; se comunica de forma explícita como
  **no tributario**;
- voucher válido como boleta o DTE emitido, únicamente después de evidencia
  fiscal SII completa y verificada. Nunca se deriva del estado `approved`.

No incluir notas internas, secretos de pago, tokens sin alcance ni enlaces que
usen el UUID del pedido como única credencial.

### Activación operativa de email transaccional

El manifiesto versionado es
`supabase/transactional_email_deployment_manifest.json`. Para Viñabike, la
identidad revisada es **Ventas Viñabike <ventas@vinabike.cl>**, con
`Reply-To: ventas@vinabike.cl` y tienda pública `https://vinabike.cl`.
`owner_email` y `contact_email` no sustituyen esta configuración explícita.

La migración `20260718230000_prepare_transactional_email_delivery.sql` instala
el cron `vinabike_transactional_email_worker`, pero el runtime queda
**deshabilitado y en `dry_run`**. La invocación usa `pg_cron` + `pg_net` y lee
`transactional_email_worker_secret` desde Supabase Vault; el valor debe ser el
mismo que el Edge secret `TRANSACTIONAL_EMAIL_WORKER_SECRET`, pero nunca se
guarda en SQL, documentación o Flutter. Cada invocación lleva un `tenant_id`
explícito y la RPC de claim lo compara con el único tenant habilitado en el
runtime: el worker no puede arrendar filas de otra tienda aunque use
`service_role`.

Orden obligatorio de rollout:

1. desplegar la cadena de migraciones y verificar tablas, funciones, triggers,
   grants y el cron, que todavía debe estar deshabilitado;
2. desplegar `send-transactional-order-email` y
   `resend-transactional-webhook` con `verify_jwt = false`; ambas aplican su
   propia autenticación;
3. configurar Edge secrets `RESEND_API_KEY`, `RESEND_WEBHOOK_SECRET` y
   `TRANSACTIONAL_EMAIL_WORKER_SECRET`; mantener
   `TRANSACTIONAL_EMAIL_MODE=dry_run`;
4. crear en Vault `transactional_email_worker_secret` con el mismo valor del
   secreto del worker y ejecutar, como `service_role`,
   `configure_transactional_email_delivery_phase(tenant_id,'dry_run',20)`;
5. invocar el worker con `action`, `tenant_id` y `mode`; procesar únicamente
   filas `dry_run` de ese tenant y aceptar solo si terminan `rendered`,
   existen hashes HTML/texto, no hubo llamadas a Resend y el remitente/CTA/
   resumen/PDF se ven correctos;
6. registrar en Resend el endpoint HTTPS
   `.../functions/v1/resend-transactional-webhook` y suscribir solamente
   `email.sent`, `email.delivery_delayed`, `email.delivered`, `email.bounced`,
   `email.complained`, `email.failed` y `email.suppressed`;
7. recién después de esa aceptación, cambiar el Edge secret
   `TRANSACTIONAL_EMAIL_MODE=send` y ejecutar en una misma ventana controlada
   `configure_transactional_email_delivery_phase(tenant_id,'send',20)`;
8. hacer un único envío sintético autorizado y comprobar `submitted` seguido
   de evidencia webhook firmada. Un bounce permanente, complaint o suppressed
   debe crear supresión y bloquear futuros mensajes a esa dirección.

Volver a fase `disabled` detiene nuevas invocaciones, pero no borra evidencia.
Cambiar la configuración tenant no convierte filas históricas `dry_run` a
`send`: el modo, remitente y destinatario son snapshots inmutables del outbox.
Los eventos firmados de engagement (`email.opened`/`email.clicked`) se reconocen
sin persistir ni reintentar porque no cambian la verdad operativa de entrega.

Estado productivo verificado el 19 de julio de 2026: el runtime transaccional
está habilitado en `send`, batch 20, con Vault y Edge secret concordantes; el
worker de preferencias Mercado Pago también está habilitado con batch 20. Ambos
cron responden HTTP 200 y conservan `last_error` vacío. El estado exacto y las
versiones Edge están versionados en
`supabase/transactional_email_deployment_manifest.json`.

El productor E2E de `mercadopago_payment_voucher` vive en
`mercadopago-webhook` y `mercadopago-get-payment`: después de la observación
durable y del procesador de venta, llama el recorder canónico. El trigger del
ledger encola `mercadopago_payment_voucher_available` idempotentemente; la
función Edge nunca escribe el outbox directamente. Este flujo no habilita el
correo fiscal `payment_voucher_available` ni `tax_document_issued`: un pago
aprobado, un PDF interno o una factura ERP no bastan para producirlos.

### Productor no fiscal desplegado en producción

El 19 de julio de 2026 se aplicó y verificó, en este orden:

1. `20260718320000_produce_mercadopago_payment_voucher.sql`, SHA-256
   `37047b8db3d23a236c76998a2b68b45aaaece7b7a40cfbc78c057216945c7781`;
2. `mercadopago-webhook` v124, `verify_jwt=false` y HMAC obligatorio;
3. `mercadopago-get-payment` v98, `verify_jwt=true` más token acotado al pedido;
4. `send-transactional-order-email` v8, secreto de worker obligatorio.

Las canaries anónimas de las cinco entradas críticas devolvieron HTTP 401. En
clon derivado de producción pasaron 31/31 pruebas Deno y 49/49 assertions SQL,
incluidos `available`, `absent`, URL insegura y replay. El pago aprobado real
no se simuló en producción ni se cargó una tarjeta: ese camino solo debe
ejecutarse ante una observación auténtica del proveedor.

La cuenta Mercado Pago productiva permite cobrar, pero su panel **Boletas y
facturas** exige Point Smart para emisión tributaria directa. Por ello el
artefacto `mercadopago_payment_voucher` sigue siendo
`fiscal_validity=not_a_tax_document`. Habilitar boleta electrónica requiere un
emisor DTE/SII real y una nueva verificación; no se resuelve renombrando el
comprobante de pago.

## Manejo de excepciones

### Pago recibido, pero sin venta ERP

No repetir el pago ni editar el estado. Abrir **Revisar** desde el pedido: el
evento, sus intentos y la referencia del proveedor deben seguir visibles. Si la
incidencia permite reintento, el comando usa el mismo evento y devuelve el
mismo resultado; si exige conciliación o reembolso, no habilita un reintento
automático.

### Sin stock al pagar

No permitir stock negativo automático para ecommerce. Mantener el pedido en
excepción de stock, contactar al cliente y resolver mediante reposición,
sustitución aceptada o reembolso formal.

### Venta ERP y pedido no coinciden

Bloquear el avance. Antes del pago, usar el comando formal de modificación del
pedido; después del pago, usar corrección/devolución. Nunca editar ambas tablas
independientemente.

### Email rebotado o en dead-letter

Verificar dirección y consentimiento, revisar la supresión y contactar por un
canal autorizado. Un reenvío crea un evento nuevo con motivo; no modifica el
registro del envío original.

## Preparación para Google Merchant y Search

Antes de publicar productos:

- precio y disponibilidad deben coincidir entre feed, HTML/JSON-LD, página de
  producto, carrito y checkout;
- el producto debe estar activo, publicado, visible en web y ser un producto
  vendible, no un servicio interno;
- el checkout no debe exigir iniciar sesión;
- marca, producto, cantidad, precio, costo de envío y condiciones deben ser
  visibles antes de pagar;
- políticas de envío, devolución, privacidad, contacto y medios de pago deben
  ser públicas y consistentes;
- el dominio debe estar verificado y los crawlers no deben quedar bloqueados;
- el feed no debe prometer un checkout directo no disponible para el país o
  para el producto.

### Estado productivo de Merchant Center (19 de julio de 2026)

El dominio está verificado y reclamado. La fuente URL publicó 103 productos y
se solicitó una actualización manual después del despliegue. El feed expone
URL canónica, precio CLP, disponibilidad, condición e identificadores; el costo
de despacho se administra a nivel de cuenta con la misma tabla autoritativa del
checkout: 6.990, 8.990, 11.990 y 14.990 CLP según el tramo, con entrega estimada
de 3 a 12 días hábiles.

La cuenta continúa suspendida por `Información engañosa` y la consola indica
que no admite otra solicitud de revisión. Esto es un bloqueo externo de cuenta:
no debe intentarse eludirlo creando una cuenta duplicada. Mantener feed, sitio,
checkout, identidad comercial y políticas sincronizados, conservar esta
evidencia y escalar por el canal de soporte/revisión que Google vuelva a
habilitar.

### Migración a Merchant API (20 de julio de 2026)

`google-product-diagnostics` ya no llama Content API for Shopping. La consulta
de estado usa Merchant Products API v1 (`products.get`) y la actualización de
la fuente usa Merchant Data Sources API v1 (`dataSources.list` y
`dataSources.fetch`). El proyecto Google Cloud `vinabikeapp` (número
`599064625399`) quedó registrado con Merchant Center `5635601285`, con
`vinabikechile@gmail.com` como contacto de desarrollo.

La verificación productiva desde la ficha ERP confirmó que la consulta del
producto `S56467` responde `Rechazado` y que `Actualizar feed` responde
`Conectado`. Esto acredita que autenticación, registro, lectura de productos y
lectura manual de la fuente funcionan por Merchant API; no resuelve ni cambia
la suspensión externa de la cuenta descrita arriba.

## Prueba de aceptación aislada

La suite destructiva se ejecuta en un clon derivado de producción o en el
entorno local canónico con datos sintéticos. Una canary productiva solo puede
ser explícitamente autorizada, acotada, sin cargo y cancelada por el comando
canónico. Debe demostrar:

1. checkout repetido con la misma clave no duplica pedido;
2. precio web, línea, total, preferencia de pago y feed coinciden;
3. dos checkouts concurrentes no prometen la misma última unidad;
4. pago aprobado crea una sola venta ERP, un solo pago y una sola cadena de
   stock/contabilidad;
5. pago aprobado + falla de stock conserva el pago y deja `action_required`;
   al reponer stock, el reintento completa exactamente una venta;
6. un merchant order con varios intentos registra todos sus pagos y no omite un
   pago aprobado por haber recibido primero uno fallido o pendiente;
7. replay del webhook no duplica efectos ni emails;
8. cancelación impaga revierte lo que corresponde y conserva evidencia;
9. pedido pagado exige corrección y reembolso formales;
10. cada transición conserva actor, hora, causa y estado anterior;
11. email renderizado no contiene PII interna ni afirma que una confirmación de
   pago o una venta ERP sea una boleta;
12. voucher o DTE solo se encolan desde evidencia documental oficial completa;
13. la misma canasta produce el mismo neto/IVA/total con Mercado Pago o
    transferencia, usando las tasas congeladas por línea;
14. asientos balancean, stock dual coincide y pedido/venta ERP/pago reconcilian.
15. dos tenants pueden tener el mismo `order_number`, pero nunca duplicarlo
    dentro de un tenant;
16. el replay de solicitud y de Mercado Pago conserva una sola devolución;
17. una respuesta de proveedor perdida queda desconocida y no aplica stock ni
    contabilidad hasta recuperar evidencia aprobada;
18. un reembolso aprobado con falla interna conserva el dinero externo y el
    reintento crea exactamente una devolución, una nota de crédito, un asiento
    de reembolso y los movimientos físicos correctos;
19. servicios nunca crean movimientos de stock y productos físicos respetan la
    disposición reponer/cuarentena/baja elegida;
20. cajero con acceso de lectura no puede autorizar dinero de Mercado Pago;
21. preflight bloquea control desactivado, cuenta inactiva, saldo cambiado o
    movimientos físicos sin procedencia antes del request al proveedor;
22. éxito del proveedor no puede degradarse por un timeout o rechazo tardío;
23. cancelar pagado exige reembolso total y deja `cancelled`, mientras una
    devolución entregada conserva `delivered`;
24. devolución parcial encola una sola comunicación idempotente sin cambiar
    falsamente `payment_status` a `refunded`;
25. void directo de devolución, nota de crédito o settlement enlazado se
    rechaza y no altera la proyección aplicada.
26. doble clic concurrente crea como máximo una preferencia y el segundo recibe
    replay o espera limitada, nunca otro POST ciego;
27. pérdida de respuesta después del POST recupera por referencia externa y no
    duplica el enlace pagable;
28. monto, envío y descuento de la preferencia reconcilian exactamente contra
    snapshots persistidos, sin aceptar valores del navegador;
29. vencimiento de preferencia y reserva coinciden; el reintento vencido vuelve
    a validar stock antes de generar una nueva generación;
30. cancelar, pagar o reembolsar encola cierre de todos los enlaces vivos, y un
    fallo del proveedor permanece visible/reintentable sin borrar evidencia.

### Evidencia de canary productiva sin cargo (19 de julio de 2026)

El checkout público creó `WEB-26-00019` con una unidad física, neto 29.412 CLP,
IVA de producto 5.588 CLP, despacho bruto 8.990 CLP (neto 7.555 + IVA 1.435) y
total 43.990 CLP. Mercado Pago creó exactamente una preferencia por el mismo
total. No se ingresó CVV ni se ejecutó pago.

Mientras el pedido estuvo impago, el stock físico permaneció en 1, la reserva
activa fue 1 y la disponibilidad pública 0. El email `order_received` fue
entregado por Resend. La cancelación canónica se ejecutó con actor admin y creó
la operación contable `c29eb514-e64f-48fd-b9c7-c8df34b05ad7`, `outcome=completed`.
Después de cancelar: reserva `released`, stock físico 1, reserva activa 0,
disponibilidad 1, email `cancelled` entregado y preferencia `expired` con una
sola tentativa y respuesta 200 del proveedor. No existe factura, movimiento de
stock, pago ni documento fiscal para esta canary.

El release productivo `ops-20260719T052509Z-8fa03a6087c5` volvió a cargar esa
misma orden con su token público y mostró `PEDIDO CANCELADO` como estado
terminal, sin reintento de Mercado Pago ni instrucciones de transferencia. El
detalle, neto, IVA, despacho y total permanecieron visibles como registro; la
descarga se identificó como resumen informativo que no acredita pago ni
reemplaza una boleta o voucher oficial.
