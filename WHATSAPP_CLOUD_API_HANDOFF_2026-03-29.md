# Handoff: WhatsApp Cloud API

*Última actualización: 30 de Marzo de 2026*
Repo: bikeshop-erp
Objetivo: dejar documentado el estado actual de la integracion de WhatsApp Cloud API para continuar el trabajo desde otro computador.

## Actualización 30 de Marzo 2026 (Estrategia de Producción y UI)

En la sesión de hoy estructuramos la salida a producción y corregimos la separación de responsabilidades en la UI:

1. **Desacople en UI Facturas:** Se arregló la pantalla de facturas (`InvoiceFormPage`). El botón "Enviar" vuelve a ser una simple transición de estado ERP (`draft` -> `sent`), sin disparar flujos de WhatsApp. El envío de PDF vía Cloud API se mantiene vivo de forma exclusiva desde el Chat Widget.
2. **Estrategia de Número para Producción:** Se definió usar un **NUEVO NÚMERO** celular asignado exclusivamente al ERP (Cloud API). El número histórico se mantendrá en el teléfono físico en la tienda usando la app WhatsApp Business normal para atenciones complejas (audios, llamadas).
3. **Estado Meta Business:** La verificación de "NEWEN SpA" quedó temporalmente en espera ("Se necesita más información"). Sin embargo, **se continuará con la integración en estado Unverified**, lo que otorga un límite de 250 conversaciones de negocio iniciadas por el bot al día (suficiente para iniciar).
4. **Aclaración del Billing Meta:** 
   - Conversaciones "Utility" (ERP manda cotización/factura primero): **Tienen costo** desde el mensaje 1 (~$0.04 USD por 24 hrs).
   - Conversaciones "Service" (Cliente dice hola primero, ERP responde con factura): **Gratis** (hasta 1,000 al mes).

### Siguientes pasos exactos para retomar en el nuevo computador:
1. Ir a Meta for Developers > WhatsApp > API Setup (Ignorar el número de prueba).
2. Hacer scroll presionar **Agregar número de teléfono** y registrar el **nuevo número (chip nuevo)**.
3. Copiar de la pantalla los nuevos **Identificador de número de teléfono** y **Identificador de la cuenta de WhatsApp Business**.
4. Ir a Meta Business Settings > Usuarios del sistema > Generar un **token permanente** con permisos `whatsapp_business_messaging` y `whatsapp_business_management`.
5. Reemplazar el secreto en Supabase: `supabase secrets set --project-ref xzdvtzdqjeyqxnkqprtf WHATSAPP_ACCESS_TOKEN="<NUEVO_TOKEN_PERMANENTE>"`
6. Registrar el nuevo canal en la BD corriendo este SQL en Supabase:
   ```sql
   INSERT INTO whatsapp_channels (tenant_id, phone_number_id, business_account_id, display_name, display_phone_number, is_active) 
   VALUES ('5443b130-cc28-45af-a420-cd500b288890', '<NUEVO_PHONE_NUMBER_ID>', '<NUEVO_BUSINESS_ACCOUNT_ID>', 'Viñabike Notificaciones', '+569XXXXXXXX', true);
   ```
7. Probar flujo enviando un mensaje directo.

---

## Resumen ejecutivo

Se implemento la base backend para integrar WhatsApp Cloud API con el ERP usando Supabase como backend principal.

En la sesion posterior a este handoff tambien se avanzo bastante en Flutter y en el flujo real de envio de presupuestos/facturas por WhatsApp:

- ya existe integracion Flutter para disparar `whatsapp-send`
- el chat del ERP ya puede enviar solicitudes interactivas por WhatsApp Cloud API
- el presupuesto adjunto ahora reutiliza el mismo PDF bonito del modulo de facturas
- el webhook ya quedo corregido para que `approve_quote` sobre invoices confirme la factura (`sent` -> `confirmed`) cuando el cliente toca `Aprobar` en WhatsApp

La solucion quedo dividida en 3 piezas:

1. Schema y RPCs en `supabase/sql/core_schema.sql`
2. Migration puntual en `supabase/migrations/20260329_whatsapp_cloud_api_integration.sql`
3. Edge Functions:
   - `supabase/functions/whatsapp-webhook/index.ts`
   - `supabase/functions/whatsapp-send/index.ts`

La idea central es:

- Meta envia webhooks a una Edge Function de Supabase.
- La Edge Function valida firma, normaliza el payload y llama RPCs SQL.
- Los mensajes entrantes/salientes se persisten en la tabla `messages` existente.
- Se reutiliza el sistema actual de `conversations`, `conversation_participants` y `conversation_contexts`.
- Las automatizaciones de pegas se ejecutan en la base de datos para mantener consistencia y realtime.

## Archivos modificados o creados

### Fuente de verdad del schema

- `supabase/sql/core_schema.sql`

Se agrego la seccion `WHATSAPP CLOUD API INTEGRATION`.

### Migration puntual para deploy

- `supabase/migrations/20260329_whatsapp_cloud_api_integration.sql`

Este archivo contiene el extracto listo para ejecutar en Supabase SQL Editor sin redeployar todo el `core_schema.sql`.

### Edge Functions nuevas

- `supabase/functions/whatsapp-webhook/index.ts`
- `supabase/functions/whatsapp-send/index.ts`

### Flutter / ERP (agregado en esta sesion)

- `lib/modules/messaging/widgets/chat_window.dart`
- `lib/modules/messaging/services/messaging_service.dart`
- `lib/shared/services/whatsapp_service.dart`
- `lib/shared/utils/invoice_pdf_generator.dart`
- `lib/modules/sales/pages/invoice_form_page.dart`
- `lib/shared/widgets/whatsapp_web_viewer.dart`

## Lo que ya quedo implementado

### 1. Tablas nuevas

#### `whatsapp_channels`

Sirve para registrar los canales/numeros de WhatsApp por tenant.

Campos importantes:

- `tenant_id`
- `phone_number_id`
- `business_account_id`
- `display_name`
- `display_phone_number`
- `is_active`

Incluye:

- RLS por tenant
- indices
- trigger `updated_at`

#### `whatsapp_conversation_bindings`

Vincula una conversacion del ERP con un contacto de WhatsApp.

Campos importantes:

- `tenant_id`
- `conversation_id`
- `channel_id`
- `customer_id`
- `external_wa_id`
- `external_phone_number`
- `contact_name`
- `last_inbound_at`
- `last_outbound_at`

Incluye:

- RLS por tenant
- indices
- trigger `updated_at`

#### `whatsapp_webhook_events`

Ledger de eventos webhook para idempotencia y trazabilidad.

Campos importantes:

- `tenant_id`
- `channel_id`
- `event_key`
- `event_type`
- `direction`
- `payload`

Incluye:

- RLS por tenant
- unique `(channel_id, event_key)`
- indices por tenant, canal y tipo

### 2. Extensiones a la tabla `messages`

Se agregaron estas columnas:

- `external_provider`
- `external_message_id`
- `message_direction`
- `external_status`

Tambien se agregaron constraints para normalizar:

- proveedor permitido: `whatsapp`
- direccion permitida: `inbound`, `outbound`
- estados permitidos: `accepted`, `sent`, `delivered`, `read`, `failed`

Y se agregaron indices:

- por `external_provider`
- unico por `external_message_id`

### 3. Funciones SQL / RPCs nuevas

#### `normalize_whatsapp_phone(p_phone text)`

Normaliza telefonos para matching de clientes y bindings.

#### `ensure_whatsapp_conversation_binding(...)`

Responsabilidades:

- encontrar o crear binding WhatsApp <-> conversacion
- encontrar o crear la conversacion `support`
- asociar cliente si existe
- insertar `conversation_contexts` si viene contexto

Nota:

- hoy agrega como participante al cliente autenticado si `customers.auth_user_id` existe
- no agrega automaticamente usuarios internos del equipo

#### `mark_whatsapp_job_quote_sent(...)`

Responsabilidades:

- marcar que el diagnostico/presupuesto fue enviado por WhatsApp
- mover la pega a `ESPERANDO_APROBACION` si ese status existe para el tenant
- setear `diagnostic_sent_at`
- dejar timeline en `mechanic_job_timeline`

#### `apply_whatsapp_job_action(...)`

Responsabilidades:

- procesar acciones derivadas de replies interactivos de WhatsApp
- actualizar `mechanic_jobs.status` y `status_id`
- actualizar `approved_by_customer`, `approved_at`, `requires_approval`, `quotation_status`
- registrar timeline

Acciones soportadas actualmente:

- `approve_quote`
- `approve_budget`
- `approve_estimate`
- `reject_quote`
- `reject_budget`
- `reject_estimate`
- `confirm_delivery`
- `cancel_delivery`

Mapeo actual:

- aprobar presupuesto -> `EN_CURSO`
- rechazar presupuesto -> `CANCELADO`
- confirmar entrega -> `ENTREGADO`
- cancelar entrega -> `FINALIZADO`

#### `ingest_whatsapp_inbound_message(...)`

Responsabilidades:

- resolver el canal por `phone_number_id`
- encontrar cliente por telefono si existe
- registrar evento webhook con idempotencia
- asegurar binding/conversacion
- insertar mensaje entrante en `messages`
- actualizar `last_inbound_at` y `last_message_at`

Tipos UI actuales derivados:

- `image` -> `image`
- `document`, `audio`, `video` -> `file`
- `interactive` -> `text`
- resto -> `text`

#### `record_whatsapp_message_status(...)`

Responsabilidades:

- registrar eventos de estado de Meta con idempotencia
- actualizar `messages.external_status`
- guardar payload del estado en `metadata`
- si el estado es `read` y la conversacion tiene contexto `job`, registrar timeline `whatsapp_read`

### 4. Edge Function `whatsapp-webhook`

Archivo:

- `supabase/functions/whatsapp-webhook/index.ts`

Responsabilidades:

- responder challenge GET de Meta
- verificar firma `x-hub-signature-256`
- parsear payloads `messages` y `statuses`
- llamar:
  - `record_whatsapp_message_status(...)`
  - `ingest_whatsapp_inbound_message(...)`
- si llega un interactive reply con id del tipo `job:<uuid>:<action>` o `invoice:<uuid>:<action>`, disparar automatizacion

Automatizacion actual:

- `job:*` -> `apply_whatsapp_job_action(...)`
- `invoice:*` con `approve_invoice`, `confirm_invoice` o `approve_quote` -> `confirm_invoice_approval(...)`

Formato esperado para botones interactivos:

- `job:<job_id>:approve_quote`
- `job:<job_id>:reject_quote`
- `job:<job_id>:confirm_delivery`
- `invoice:<invoice_id>:confirm_invoice`
- `invoice:<invoice_id>:approve_quote`

### 5. Edge Function `whatsapp-send`

Archivo:

- `supabase/functions/whatsapp-send/index.ts`

Responsabilidades:

- autenticar usuario usando `Authorization` de Supabase
- resolver `tenant_id` desde `user_profiles`
- resolver canal activo desde `whatsapp_channels`
- asegurar binding/conversacion con `ensure_whatsapp_conversation_binding(...)`
- enviar mensaje a Graph API
- persistir el mensaje saliente en `messages`
- opcionalmente marcar presupuesto enviado con `mark_whatsapp_job_quote_sent(...)`

Tipos soportados actualmente:

- `text`
- `document`
- `template`
- `interactive`

Avance adicional de esta sesion:

- los mensajes `interactive` ahora pueden incluir `header` de tipo `document`
- esto permite mandar el PDF del presupuesto directamente dentro de la tarjeta interactiva de WhatsApp
- para presupuestos enviados desde el chat del ERP se adjunta el PDF antes de los botones `Rechazar / Aprobar`

## Lo que ya quedo implementado en Flutter / ERP

### 6. Chat del ERP conectado a WhatsApp Cloud API

Archivo principal:

- `lib/modules/messaging/widgets/chat_window.dart`

Responsabilidades implementadas:

- enviar solicitudes interactivas de WhatsApp desde conversaciones del ERP
- resolver automaticamente el contacto del cliente asociado a la conversacion
- soportar acciones:
   - `approve_quote`
   - `pay_now`
   - `confirm_delivery`
- mover la factura a `sent` antes de enviar la solicitud de aprobacion del presupuesto
- mostrar feedback en UI segun si el envio salio por Cloud API o por fallback manual

### 7. Resolucion de contacto WhatsApp desde conversaciones

Archivo:

- `lib/modules/messaging/services/messaging_service.dart`

Se agrego:

- `getSupportConversationContact(conversationId)`

Responsabilidades:

- intentar resolver el contacto desde `whatsapp_conversation_bindings`
- fallback a contexto invoice/job
- fallback final a participantes de la conversacion vinculados a `customers.auth_user_id`

### 8. Servicio Flutter para acciones interactivas

Archivo:

- `lib/shared/services/whatsapp_service.dart`

Se agrego:

- `sendInteractiveAction(...)`

Responsabilidades:

- encapsular el llamado Flutter -> Edge Function `whatsapp-send`
- permitir acciones interactivas con metadatos, monto, contexto y documento adjunto
- mantener fallback manual cuando Cloud API falle o no este disponible

### 9. Presupuesto PDF compartido y reutilizable

Archivo:

- `lib/shared/utils/invoice_pdf_generator.dart`

Se implemento un generador compartido para reutilizar exactamente el layout de PDF ya usado en facturas/presupuestos del modulo de ventas.

Responsabilidades:

- resolver nombres de bicicletas para invoices con una o multiples bicicletas
- generar el PDF con el mismo estilo del formulario de factura
- cachear el logo de la empresa para no volver a descargarlo en cada export

Importante:

- durante esta sesion se descartaron los experimentos de layout alternativo
- el PDF adjunto en WhatsApp ya usa el layout bueno/reutilizado, no una UI nueva improvisada

### 10. Envio de presupuesto con PDF adjunto desde el chat

Archivo:

- `lib/modules/messaging/widgets/chat_window.dart`

Responsabilidades:

- buscar la invoice asociada al contexto de chat
- regenerar el PDF del presupuesto desde la invoice real
- subir el PDF a Supabase Storage (`vinabike-assets`)
- enviar una tarjeta interactiva de WhatsApp con:
   - documento PDF adjunto
   - mensaje de contexto
   - botones `Rechazar` / `Aprobar`

### 11. Envio de factura al cliente desde la pantalla de factura

Archivo:

- `lib/modules/sales/pages/invoice_form_page.dart`

Avances:

- el boton `Enviar` ahora paso a ser `Enviar al cliente`
- usa `WhatsAppService.sendInvoice(...)`
- si el envio tiene exito, la factura puede quedar marcada como `sent`
- se agrego sidebar de chat contextual (`EntityChatSidebar`) cuando la factura ya existe

### 12. Ajustes de experiencia en fallback manual

Archivo:

- `lib/shared/widgets/whatsapp_web_viewer.dart`

Avances:

- mejora visual del WebView en macOS
- limpieza de estado temporal no usado
- soporte para abrir `wa.me` externamente en macOS desde `WhatsAppService`

Si no se provee `interactive` manualmente pero se envian `actionType` y `actionTargetId` o `jobId`, la funcion construye botones reply automaticamente.

Casos pensados:

- enviar presupuesto PDF
- enviar texto simple
- enviar template aprobado por Meta
- enviar boton de aprobar/rechazar presupuesto
- enviar boton de confirmar entrega

## Decisiones de arquitectura tomadas

### Reutilizar el sistema de mensajeria existente

No se creo un modulo paralelo de chat para WhatsApp.

Se reutilizan:

- `conversations`
- `conversation_participants`
- `messages`
- `conversation_contexts`

Esto evita duplicar UI, mantiene realtime y deja toda la trazabilidad en un solo lugar.

### Automatizacion en SQL, no en Flutter

Las transiciones de pegas no se hacen desde el cliente.

Se hacen en funciones SQL porque:

- permite centralizar reglas
- reduce riesgo de inconsistencias
- funciona igual si el evento entra por webhook
- encaja mejor con Supabase Realtime

### Seguridad server-side

Credenciales sensibles se consideran server-side:

- `META_APP_SECRET`
- `WHATSAPP_VERIFY_TOKEN`
- `WHATSAPP_ACCESS_TOKEN`

No se dejo nada de esto para cliente Flutter.

## Validacion y Estado Actual (Sesion 29 de Marzo)

Se valido con el sistema de errores del editor:

- `supabase/functions/whatsapp-webhook/index.ts` -> sin errores
- `supabase/functions/whatsapp-send/index.ts` -> sin errores
- `lib/shared/utils/invoice_pdf_generator.dart` -> sin errores de compilacion
- `lib/modules/messaging/widgets/chat_window.dart` -> sin errores de compilacion
- `lib/shared/services/whatsapp_service.dart` -> sin errores de compilacion
- `lib/modules/sales/pages/invoice_form_page.dart` -> sin errores de compilacion

Nota sobre `flutter analyze`:

- sigue retornando exit code `1` por lints/info preexistentes (`use_build_context_synchronously`, `deprecated_member_use`, etc.)
- no quedan errores de compilacion en el flujo nuevo de PDF + WhatsApp

### Estado real validado al cierre de esta sesion

- ✅ **Webhook verificado y funcionando:** el challenge GET de Meta responde bien y los POST ya estan entrando correctamente.
- ✅ **Secrets corregidos en servidor:** el problema real era una discrepancia en `META_APP_SECRET`; despues de corregir el secret desplegado y redeployar `whatsapp-webhook`, los eventos POST quedaron validando firma correctamente.
- ✅ **Functions desplegadas:** `whatsapp-webhook` y `whatsapp-send` quedaron deployadas en `xzdvtzdqjeyqxnkqprtf`.
- ✅ **Flujo end-to-end validado:** al tocar `Aprobar` en WhatsApp, la invoice pasa de `sent` a `confirmed`.
- ✅ **Chat ERP -> WhatsApp funcionando:** desde el chat ya se puede enviar texto simple al cliente, no solo la invoice/presupuesto.
- ✅ **UX del chat mejorada:**
  - el mensaje sale con burbuja optimista
  - ya no aparece snackbar verde en cada envio exitoso por Cloud API
  - ya no aparece spinner en el boton enviar
  - las burbujas salientes muestran estado estilo WhatsApp (`pending`, `sent`, `delivered`, `read`, `failed`) usando `messages.external_status`
- ✅ **Invoice form sincronizada en vivo:** cuando la invoice cambia de estado en backend, la pantalla abierta de factura ahora refresca el status y los botones sin necesidad de navegar fuera y volver.

### Root cause importante que quedo resuelto

El bug mas dificil de esta sesion fue este:

- outbound de WhatsApp funcionaba
- inbound/messages/status no llegaban a BD
- `whatsapp_webhook_events` quedaba vacia
- la invoice no se confirmaba al tocar `Aprobar`

La causa real fue:

- `META_APP_SECRET` desplegado en Supabase no coincidia con el app secret real configurado en Meta
- el webhook GET verificaba bien, pero el POST fallaba validacion de firma

Una vez corregido ese secret y redeployado `whatsapp-webhook`, el flujo quedo operativo.

## Estado actual de deploy

### Backend / Supabase

Ya esta activo en servidor:

- `supabase/functions/whatsapp-webhook/index.ts`
- `supabase/functions/whatsapp-send/index.ts`
- schema SQL / RPCs de WhatsApp
- canal de prueba en `whatsapp_channels`

### Flutter / ERP

Ya esta activo en codigo:

- envio de presupuesto con PDF adjunto y botones interactivos
- envio de factura al cliente
- envio de mensaje de texto desde el chat ERP
- estados visuales estilo WhatsApp en mensajes salientes
- refresco live de la pantalla de factura cuando cambia estado/pagos

## Lo que falta si quieres dejarlo funcionando de verdad

### 1. Entender la limitacion actual del numero de prueba

Hoy el sistema ya funciona, pero sigue usando el **numero de prueba de Meta**.

Eso implica una restriccion importante:

- si intentas enviar a un numero no autorizado en la lista de prueba, Graph API devuelve error `131030`
- mensaje tipico: `Recipient phone number not in allowed list`

Esto **no es un bug del ERP**.

Es una restriccion normal del entorno de prueba de WhatsApp Cloud API.

### 2. Para seguir probando ahora mismo

Si quieres seguir usando el numero de prueba actual:

1. Agrega el numero destino en la lista de destinatarios permitidos de Meta.
2. Verifica ese numero con el codigo SMS/llamada que pide Meta.
3. Reintenta desde el ERP.

Con eso deberia enviar por Cloud API sin cambiar nada del codigo.

### 3. Para salir de test/dev y poder escribir a numeros reales sin allowlist

No basta con "activar" el numero de prueba. Hay que pasar a un setup productivo real:

1. Verificar el negocio en Meta Business Suite.
2. Tener una WhatsApp Business Account real asociada al negocio.
3. Agregar un numero telefonico real de envio del negocio.
4. Configurar nombre para mostrar y perfil comercial.
5. Configurar billing/pagos en WhatsApp Manager.
6. Generar token permanente de system user con permisos:
   - `business_management`
   - `whatsapp_business_messaging`
   - `whatsapp_business_management`
7. Poner la app en Live mode si aplica segun la configuracion final.
8. Actualizar en Supabase los valores productivos:
   - `WHATSAPP_ACCESS_TOKEN`
   - `phone_number_id` / canal real en `whatsapp_channels`
   - cualquier dato nuevo de la WABA si cambia

### 4. OJO: Produccion no elimina la regla de plantillas

Aunque salgas de sandbox y ya no necesites allowlist:

- **no** puedes mandar primer mensaje libre a cualquier cliente fuera de la ventana de 24h
- si el cliente no te escribio en las ultimas 24h, el primer outbound debe ser **template aprobado por Meta**
- una vez el cliente responde, se abre la customer service window de 24h y ahi si puedes seguir con texto libre

En otras palabras:

- produccion elimina el bloqueo de allowlist
- produccion **no** elimina la politica de plantillas

### 5. La puerta que queda abierta para implementar esto pronto

La implementacion actual ya deja el camino listo para un siguiente bloque muy razonable:

1. agregar templates reales en Meta (por ejemplo: presupuesto listo, recordatorio de pago, seguimiento de servicio)
2. extender `whatsapp-send` / Flutter para elegir automaticamente:
   - texto libre si la ventana de 24h esta abierta
   - template aprobado si la ventana esta cerrada
3. agregar UX en el ERP para mostrar claramente:
   - si el contacto esta dentro o fuera de la ventana de 24h
   - si el proximo envio sera libre o por template
4. agregar una pantalla de administracion de canales / templates / estados de conversacion

---

## 🤖 MANUAL DE SUPABASE CLI PARA AGENTES (¡LEER ANTES DE USAR!)

La interfaz de línea de comandos de Supabase debe usarse con cuidado. **NUNCA INVENTAR COMANDOS.** 

### Para setear secrets (Credenciales Backend)
Para setear variables de entorno en el servidor de Supabase (las que leen las Edge Functions):
```bash
# FORMA CORRECTA PARA EL PROYECTO DE PRODUCCIÓN DE VIÑABIKE:
supabase secrets set --project-ref xzdvtzdqjeyqxnkqprtf WHATSAPP_VERIFY_TOKEN="mi_token" META_APP_SECRET="el_secreto" WHATSAPP_ACCESS_TOKEN="el_token"
```

Para ver si los secrets quedaron guardados:
```bash
supabase secrets list --project-ref xzdvtzdqjeyqxnkqprtf
```

### Para deployar edge functions
```bash
# FORMA CORRECTA (Despliega una funcion específica):
supabase functions deploy whatsapp-webhook --project-ref xzdvtzdqjeyqxnkqprtf --no-verify-jwt
supabase functions deploy whatsapp-send --project-ref xzdvtzdqjeyqxnkqprtf --no-verify-jwt

# NOTA: En este proyecto, webhook y edge functions publicas llevan la flag --no-verify-jwt
# porque el webhook es público (Meta le pega directo) y whatsapp-send maneja la validacion Auth
# de manera manual viendo los headers para saber a qué Tenant pertenece.
```

---

### 6. Aprobar templates si se van a usar

La funcion de envio ya soporta `template`, pero Meta exige templates aprobados.

Esto pasa a ser importante de verdad para produccion, porque si quieres iniciar conversaciones desde el ERP a numeros reales fuera de la ventana de 24h, vas a necesitar templates si o si.

### 7. Estado actual de templates (sesion 31 Marzo 2026)

Se dejo creado en Meta un primer template de contacto inicial, actualmente **en revision**:

- nombre: `seguimiento_servicio_bicicleta`
- categoria: `Utility`
- idioma: `Spanish (CHL)`
- variables: `{{1}} = cliente`, `{{2}} = vendedor`

Texto enviado a revision:

```text
Hola {{1}}, buen día. Soy {{2}} de Viñabike y te escribo por el servicio de tu bicicleta.
```

Ademas, en Flutter ya quedo preparado un metodo dedicado en `lib/shared/services/whatsapp_service.dart` para disparar este template apenas quede aprobado.

---

## Propuesta de producto: nueva seccion WhatsApp en Configuracion

### Objetivo

Hoy la integracion ya funciona, pero demasiadas decisiones siguen “hardcodeadas” o dependen del desarrollador:

- que canal esta activo
- que template usar para primer contacto
- como se hace fallback si falla Cloud API
- como se muestran estados y errores al usuario interno
- que textos base se usan para facturas, presupuestos y seguimientos

La recomendacion es crear una seccion formal dentro de `Configuracion` del ERP para que el negocio pueda administrar y tunear el canal sin tocar codigo.

Ruta sugerida:

- `Configuracion > WhatsApp`

### Alcance de esta nueva seccion

La nueva seccion de WhatsApp deberia centralizar TODO lo ajustable del canal.

Subsecciones sugeridas:

1. **Resumen del Canal**
    - numero activo
    - `phone_number_id`
    - nombre comercial mostrado
    - WABA / business account asociada
    - estado del canal
    - ultimo webhook recibido
    - ultimo mensaje enviado
    - salud del canal (`ok`, `sin webhook`, `token expirado`, etc.)

2. **Canales y Enrutamiento**
    - ver `whatsapp_channels`
    - activar / desactivar canal
    - elegir canal por defecto
    - definir si un tenant puede tener mas de un numero
    - preparar base para futuro multi-canal

3. **Templates**
    - listado de templates conocidos por el ERP
    - estado (`pending`, `approved`, `rejected`, `paused`)
    - categoria (`utility`, `marketing`, etc.)
    - idioma
    - nombre exacto en Meta
    - mapeo de uso interno:
       - primer contacto
       - seguimiento de servicio
       - recordatorio de pago
       - presupuesto listo

4. **Ventana de 24h y Politica de Envio**
    - mostrar si el contacto actual esta dentro o fuera de la ventana
    - indicar si el proximo envio sera:
       - texto libre
       - template obligatorio
    - definir comportamiento por defecto cuando la ventana este cerrada:
       - usar template configurado
       - bloquear envio libre
       - prohibir fallback manual automatico

5. **Mensajes y Comportamiento**
    - texto base de contacto inicial
    - texto base de seguimiento
    - texto base de factura / presupuesto
    - activar o desactivar envio de PDF adjunto
    - activar o desactivar botones interactivos
    - reglas de fallback:
       - fallback a WhatsApp Web permitido o no
       - fallback solo en desktop
       - fallback prohibido para errores de politica Meta (ej. 24h cerrada)

6. **Auditoria y Diagnostico**
    - vista de `whatsapp_webhook_events`
    - ultimos errores Graph API
    - estados `accepted/sent/delivered/read/failed`
    - detalle de errores como:
       - `131030` allowlist
       - `131047` re-engagement / ventana cerrada
       - template no aprobado

7. **Estimador de Cobro Meta**
   - contador de primeras interacciones business-initiated
   - timestamps de apertura y cierre de ventana de 24h
   - estimacion de conversaciones cobrables por categoria
   - proyeccion diaria / semanal / mensual de costo
   - advertencia visual antes de abrir una nueva ventana cobrable
   - diferencia entre:
      - conversacion iniciada por negocio
      - conversacion iniciada por cliente
      - ventana ya abierta vs nueva ventana

### Idea adicional: calculador estimado de costo Meta

Seria muy util que la nueva seccion de WhatsApp no solo muestre el estado tecnico del canal, sino tambien una **estimacion razonable de cuanto podria cobrar Meta**.

Esto no debe venderse como “billing oficial”, sino como **estimador operativo** para que el negocio entienda:

- cuantas conversaciones nuevas esta abriendo el ERP
- cuantas de esas pueden ser cobrables
- cuanto impacto podria tener un flujo de primer contacto mas agresivo

### Como deberia funcionar este estimador

La logica sugerida es llevar un conteo de **primeras interacciones** con timestamps y usar eso para reconstruir ventanas de 24h.

Datos minimos a guardar o derivar:

- telefono / contacto
- tenant
- conversation_id
- categoria estimada (`utility`, `marketing`, `service`, etc.)
- timestamp del primer outbound que abre ventana
- timestamp del ultimo inbound del cliente
- `window_opened_at`
- `window_expires_at`
- bandera `estimated_billable`
- `estimated_charge_bucket`

### Regla operativa sugerida

1. si el cliente escribe primero, se abre una ventana de 24h customer-service
2. mientras esa ventana este abierta, los mensajes siguientes no deberian contarse como nueva apertura cobrable
3. si la ventana esta cerrada y el ERP manda un primer outbound via template, eso cuenta como nueva interaccion potencialmente cobrable
4. todos los mensajes posteriores dentro de esa ventana heredan la misma ventana y no deberian contarse doble

### Lo que deberia mostrar en UI

La seccion `Configuracion > WhatsApp` podria tener un bloque tipo dashboard con:

- `Conversaciones nuevas hoy`
- `Ventanas abiertas ahora`
- `Primeros contactos iniciados por negocio hoy`
- `Estimacion de conversaciones utility del mes`
- `Estimacion total de costo del mes`

Ademas, a nivel de contacto o chat:

- `Ventana abierta hasta: 31/03 18:42`
- `Siguiente envio abriria una nueva ventana cobrable`
- `Costo estimado: utility Chile / revisar tarifa vigente`

### Importante: esto debe ser una estimacion, no un espejo exacto de Meta

Meta puede cambiar:

- tarifas por pais
- categorias
- reglas comerciales
- forma de facturacion visible en manager

Entonces el ERP deberia presentar esto como:

- `estimacion`
- `aproximado`
- `revisar tarifa vigente en WhatsApp Manager`

Nunca como liquidacion oficial.

### Posible implementacion tecnica

Si se quiere formalizar, una opcion es crear una tabla o vista derivada, por ejemplo:

- `whatsapp_billing_windows`

Campos sugeridos:

- `tenant_id`
- `conversation_id`
- `external_phone_number`
- `category`
- `initiated_by` (`business` / `customer`)
- `window_opened_at`
- `window_expires_at`
- `estimated_billable`
- `estimated_unit_cost`
- `estimated_total_cost`
- `source_message_id`

Y complementarlo con una tabla de configuracion por pais/categoria, por ejemplo:

- `whatsapp_rate_cards`

Para guardar:

- pais
- categoria
- moneda
- valor_referencia
- vigente_desde

Con eso el frontend podria calcular y renderizar un costo aproximado bastante util para operacion.

### Idea clave: Template Preview dentro del ERP

Esto ayudaría mucho a operacion, soporte y debugging.

Se recomienda crear un **preview de templates** en la UI de WhatsApp Settings.

Dos niveles posibles:

#### Opcion ideal: preview cableado al template real

El ERP deberia poder mostrar:

- nombre real del template en Meta
- idioma real
- body real
- variables esperadas
- ejemplos de variables
- preview visual estilo WhatsApp

Idealmente esto se alimenta de una fuente real y no inventada.

Opciones de implementacion:

- sincronizar templates aprobados desde Meta y cachearlos en Supabase
- o guardar manualmente en ERP un registro espejo con el body aprobado + variables + estado

Tabla sugerida si se quiere formalizar esto:

- `whatsapp_template_configs`

Campos sugeridos:

- `tenant_id`
- `template_key` interno (`first_contact`, `payment_reminder`, etc.)
- `meta_template_name`
- `language_code`
- `category`
- `status`
- `body_text`
- `header_type`
- `footer_text`
- `button_config jsonb`
- `sample_values jsonb`
- `is_active`

#### Opcion minima viable: preview simulado pero fiel

Si al principio no se quiere sincronizar Meta directamente, igual vale mucho tener un preview local que reconstruya la plantilla lo mas fiel posible.

Ese preview deberia:

- renderizar la burbuja estilo WhatsApp
- reemplazar variables con ejemplos editables
- simular encabezado / cuerpo / footer / botones
- mostrar como se veria antes de enviarla

Aunque sea “simulado”, debe basarse en el texto real configurado para que no sea un mock engañoso.

### Personalizaciones concretas que deberia poder hacer negocio sin tocar codigo

La seccion nueva deberia permitir cambiar por UI cosas como estas:

- template por defecto de primer contacto
- nombre del agente que se usa al rellenar variables
- estrategia para obtener ese nombre:
   - usuario logueado
   - display name del perfil
   - alias comercial configurable
- textos base de envio
- reglas de fallback
- si adjuntar PDF al presupuesto
- si usar botones interactivos o solo texto
- si mostrar botones de WhatsApp en facturas / pegas / chat
- si bloquear envio cuando falte template aprobado
- mensaje de error humanizado para el staff interno

### Beneficio esperado

Con esta seccion el ERP deja de depender del desarrollador para cambios operativos pequeños y pasa a tener una capa de administracion real:

- negocio cambia templates y defaults
- soporte puede inspeccionar errores
- administracion puede ver estado del canal
- el equipo interno entiende si un envio es libre o por template
- se reduce el debugging manual por terminal/Supabase

## Lo que todavia no hice

### 1. Integracion Flutter

Esto ya NO esta completamente pendiente.

Ya se implemento:

- servicio Flutter para acciones interactivas (`sendInteractiveAction`)
- botones/acciones desde chat para disparar mensajes WhatsApp
- envio de presupuesto con PDF adjunto
- envio de factura al cliente desde la pantalla de invoice

Sigue pendiente:

- nueva seccion `Configuracion > WhatsApp`
- UI de administracion de templates y reglas de envio
- UI de administracion de `whatsapp_channels`
- vistas de auditoria para `whatsapp_webhook_events`
- estimador de costo Meta basado en primeras interacciones y ventanas de 24h
- preview de templates dentro del ERP (real o simulado fiel)
- limpieza de lints/info en algunos archivos Flutter

### 2. Testing funcional real

Todavia no se hicieron pruebas completas de produccion real con numero comercial propio.

En cambio, si se valido en entorno actual de prueba:

- envio real a Meta
- recepcion real desde Meta
- interactive reply real (`Aprobar`)
- confirmacion real de invoice `sent` -> `confirmed`

Sigue pendiente probar de forma sistematica:

- lectura de estados `sent`, `delivered`, `read`
- envio con numero productivo real (no test number)
- primer contacto via template fuera de la ventana de 24h

### 3. Media avanzada

No se implemento manejo de:

- descarga de media inbound desde Meta
- upload de media a Meta antes de enviar archivo
- almacenamiento de binarios en Supabase Storage

Hoy el envio de `document` esta pensado para `documentUrl` publica o alcanzable por Meta.

### 4. Routing interno de participantes del equipo

Hoy una conversacion puede existir y persistir mensajes correctamente, pero el equipo interno podria no verla si no hay participantes internos asociados y la UI depende de ellos.

Esto hay que revisar bien con el comportamiento real de la UI actual.

Posible mejora:

- auto agregar participantes internos segun reglas del tenant
- o crear una estrategia de owner/queue para conversaciones WhatsApp

### 5. Casos de invoice mas completos

El webhook ahora ya soporta automatizacion directa de invoice para:

- `approve_invoice`
- `confirm_invoice`
- `approve_quote`

Pendiente:

- revisar si hay otros action types legacy en ventas/mensajeria que convenga homologar
- decidir si el ERP deberia crear templates especificos para:
   - primer contacto de presupuesto
   - seguimiento de aprobacion
   - recordatorio de pago
- conectar el template `seguimiento_servicio_bicicleta` al flujo de primer contacto una vez Meta lo apruebe

### 6. Estados adicionales de pegas

Los mapeos actuales son funcionales pero simples.

Podrian refinarse segun negocio real:

- rechazo de presupuesto podria no ser `CANCELADO` en todos los casos
- `cancel_delivery` podria necesitar otro status distinto de `FINALIZADO`

## Mejoras recomendadas

### Prioridad alta

1. Crear nueva seccion `Configuracion > WhatsApp` como centro de administracion funcional.
2. Dentro de esa seccion, crear pantalla ERP para administrar `whatsapp_channels`.
3. Crear UI de auditoria para `whatsapp_webhook_events` y errores Graph API.
4. Implementar estrategia de templates para primer contacto fuera de la ventana de 24h.
5. Agregar preview de templates dentro del ERP, idealmente cableado al template real o al menos reconstruido fielmente.
6. Agregar estimador de costo Meta basado en primeras interacciones y ventanas de 24h.
7. Probar end-to-end con un numero productivo real de negocio.

### Prioridad media

1. Guardar media inbound en Supabase Storage.
2. Agregar reintentos y mejor manejo de errores en `whatsapp-send`.
3. Homologar action types con los ya usados por el modulo de mensajeria.
4. Mostrar en UI si un contacto esta dentro/fuera de la ventana de 24h.
5. Permitir configurar por UI el template por defecto de primer contacto y sus ejemplos de variables.
6. Agregar tabla configurable de tarifas de referencia para el estimador de costo.

### Prioridad media/alta

1. Resolver ownership de conversaciones WhatsApp para el equipo interno.
2. Revisar si conviene auto asignar conversaciones a empleados o managers.
3. Agregar notificaciones internas cuando entra un mensaje WhatsApp nuevo.

### Prioridad baja

1. Soportar mas tipos de interactive payload.
2. Soportar mas automatizaciones por invoice/payment.
3. Soportar credenciales multi-canal por tenant si un dia hace falta.
4. Agregar highlight visual cuando una invoice cambie live en pantalla.

## Riesgos o puntos a revisar

### 1. Access token global

`WHATSAPP_ACCESS_TOKEN` quedo como secret global de la Edge Function.

Esto esta bien para una primera fase y es seguro server-side, pero si en el futuro hay multiples cuentas reales separadas por tenant o por canal, quizas haya que pasar a un modelo por canal o por tenant.

### 2. Participantes internos

No se resolvio completamente la visibilidad interna de conversaciones generadas por webhook si no tienen participantes humanos cargados.

### 3. Documento saliente

Meta necesita poder acceder al `documentUrl`. Si el archivo esta en Storage privado con signed URL corta, hay que revisar la estrategia de expiracion o usar upload de media a Meta.

### 4. Matching por telefono

El matching actual usa telefono normalizado contra `customers.phone`.

Si hay datos inconsistentes en clientes, el binding puede crear conversacion sin customer asociado.

## Recomendacion para retomar en otro computador

Orden sugerido:

1. Abrir este repo en el nuevo Mac.
2. Leer este archivo handoff para entrar en contexto.
3. Confirmar en Meta que sigues usando el numero de prueba o si ya vas a pasar a numero productivo.
4. Si sigues en test:
   - revisar allowlist de destinatarios
   - agregar/verificar el numero destino antes de probar outbound
5. Si vas a pasar a produccion:
   - verificar negocio
   - agregar numero real
   - configurar billing
   - generar token permanente
   - actualizar Supabase secrets / canal
6. Probar enviar y recibir mensajes desde el ERP.
7. Solo despues meterse al bloque de templates / admin UI / endurecimiento UX.

## Sugerencia de proximo bloque de trabajo

Si retomas despues, el siguiente bloque razonable seria:

1. Decidir si el siguiente paso es seguir en test o pasar a numero productivo.
2. Si el objetivo es negocio real: implementar la nueva seccion `Configuracion > WhatsApp`.
3. Dentro de esa seccion, construir admin UI de canales + templates + auditoria + preview.
4. Agregar un estimador de costo Meta usando contador de primeras interacciones y ventanas de 24h.
5. Conectar el template de primer contacto `seguimiento_servicio_bicicleta` cuando Meta lo apruebe.
6. Endurecer el manejo de errores de Meta en Flutter para casos como:
   - `131030 Recipient phone number not in allowed list`
   - ventana de 24h cerrada
   - template faltante o no aprobado
7. Recien despues, limpiar lints Flutter y pulir UI.

## Estado final de esta sesion

**Backend WhatsApp Cloud API operativo, webhook validando firma correctamente, functions desplegadas y flujo invoice approval funcionando end-to-end.**

**Ademas, ya existe una primera integracion Flutter utilizable para:**

- enviar presupuesto con PDF adjunto
- enviar factura al cliente
- enviar mensajes de texto desde el chat ERP
- mostrar estados estilo WhatsApp en mensajes salientes
- refrescar la pantalla de factura en vivo cuando cambia el estado

Listo para:

- seguir probando con numeros allowlisted del entorno test
- pasar a un numero productivo real cuando el negocio lo decida
- implementar templates y flujo de primer contacto en un bloque siguiente
- crear una seccion de configuracion usable para que negocio/admin pueda tunear WhatsApp sin tocar codigo

No listo aun para:

- operacion productiva abierta sobre numeros arbitrarios si sigues usando el numero de prueba de Meta
- flujo completo de templates / ventana de 24h desde UI del ERP
- administracion completa de canales, templates, preview y auditoria desde pantallas internas

Nota final importante:

- hoy el sistema ya no esta "a medias": ya funciona de verdad dentro de las reglas del entorno test de Meta
- el siguiente salto ya no es tanto backend basico, sino **producto / operacion**:
  - numero comercial real
  - business verification
  - billing
  - templates
  - UX de primer contacto fuera de la ventana de 24h
