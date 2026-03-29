# Handoff: WhatsApp Cloud API

Fecha: 2026-03-29
Repo: bikeshop-erp
Objetivo: dejar documentado el estado actual de la integracion de WhatsApp Cloud API para continuar el trabajo desde otro computador.

## Resumen ejecutivo

Se implemento la base backend para integrar WhatsApp Cloud API con el ERP usando Supabase como backend principal.

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
- `invoice:*` con `approve_invoice` o `confirm_invoice` -> `confirm_invoice_approval(...)`

Formato esperado para botones interactivos:

- `job:<job_id>:approve_quote`
- `job:<job_id>:reject_quote`
- `job:<job_id>:confirm_delivery`
- `invoice:<invoice_id>:confirm_invoice`

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

## Validacion hecha

Se valido con el sistema de errores del editor:

- `supabase/functions/whatsapp-webhook/index.ts` -> sin errores
- `supabase/functions/whatsapp-send/index.ts` -> sin errores

No se hicieron pruebas reales contra Meta ni deploy real de funciones en esta sesion.

## Lo que falta si quieres dejarlo funcionando de verdad

### 1. Deploy SQL en Supabase

Ejecutar este archivo:

- `supabase/migrations/20260329_whatsapp_cloud_api_integration.sql`

Importante:

- la fuente de verdad sigue siendo `supabase/sql/core_schema.sql`
- la migration es solo el extracto listo para deploy puntual

### 2. Deploy de Edge Functions

Hay que desplegar:

- `whatsapp-webhook`
- `whatsapp-send`

### 3. Configurar secrets en Supabase Functions

Necesarios:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `WHATSAPP_VERIFY_TOKEN`
- `META_APP_SECRET`
- `WHATSAPP_ACCESS_TOKEN`

Opcional:

- `WHATSAPP_API_VERSION` (default actual: `v23.0`)

### 4. Poblar `whatsapp_channels`

Hay que insertar al menos un registro por tenant con:

- `tenant_id`
- `phone_number_id`
- `business_account_id` si aplica
- `display_name`
- `display_phone_number`
- `is_active = true`

Sin eso el webhook y el send no podran resolver canal.

### 5. Configurar Meta Webhook

Hay que registrar en Meta:

- callback URL apuntando a `whatsapp-webhook`
- verify token igual al secret `WHATSAPP_VERIFY_TOKEN`

La funcion ya soporta el challenge GET y validacion de firma POST.

### 6. Aprobar templates si se van a usar

La funcion de envio soporta `template`, pero Meta exige templates aprobados.

## Lo que todavia no hice

### 1. Integracion Flutter

No se implemento todavia:

- servicio Flutter para invocar `whatsapp-send`
- botones en pegas/chat para disparar mensajes WhatsApp
- UI de administracion de `whatsapp_channels`
- vistas de auditoria para `whatsapp_webhook_events`

### 2. Testing funcional real

No se hicieron pruebas end-to-end de:

- envio real a Meta
- recepcion real desde Meta
- interactive replies reales
- lectura de estados `sent`, `delivered`, `read`

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

En webhook solo deje automatizacion directa de invoice para:

- `approve_invoice`
- `confirm_invoice`

No revise en detalle si el flujo real de ventas usa otros action types en mensajes existentes.

### 6. Estados adicionales de pegas

Los mapeos actuales son funcionales pero simples.

Podrian refinarse segun negocio real:

- rechazo de presupuesto podria no ser `CANCELADO` en todos los casos
- `cancel_delivery` podria necesitar otro status distinto de `FINALIZADO`

## Mejoras recomendadas

### Prioridad alta

1. Crear servicio Flutter `WhatsAppCloudService` para invocar `whatsapp-send`.
2. Agregar botones desde pegas para:
   - enviar presupuesto PDF
   - pedir aprobacion
   - confirmar entrega
3. Crear pantalla ERP para administrar `whatsapp_channels`.
4. Probar end-to-end con un numero real de prueba de Meta.

### Prioridad media

1. Guardar media inbound en Supabase Storage.
2. Agregar dashboard o tabla de `whatsapp_webhook_events`.
3. Agregar reintentos y mejor manejo de errores en `whatsapp-send`.
4. Homologar action types con los ya usados por el modulo de mensajeria.

### Prioridad media/alta

1. Resolver ownership de conversaciones WhatsApp para el equipo interno.
2. Revisar si conviene auto asignar conversaciones a empleados o managers.
3. Agregar notificaciones internas cuando entra un mensaje WhatsApp nuevo.

### Prioridad baja

1. Soportar mas tipos de interactive payload.
2. Soportar mas automatizaciones por invoice/payment.
3. Soportar credenciales multi-canal por tenant si un dia hace falta.

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

1. Abrir este repo.
2. Revisar este archivo handoff.
3. Ejecutar la migration SQL puntual en Supabase.
4. Configurar los secrets de funciones.
5. Desplegar `whatsapp-webhook` y `whatsapp-send`.
6. Insertar un `whatsapp_channels` para Viñabike.
7. Probar webhook challenge desde Meta.
8. Hacer una prueba real de envio con `whatsapp-send`.
9. Hacer una prueba real de inbound reply.
10. Recien despues cablear Flutter UI.

## Sugerencia de proximo bloque de trabajo

Si retomas despues, el siguiente bloque razonable seria:

1. Crear servicio Flutter para invocar `whatsapp-send`.
2. Agregar accion desde la pega para enviar presupuesto por WhatsApp.
3. Generar interactive message de aprobacion/rechazo.
4. Verificar que la respuesta cambie el status de la pega automaticamente.

## Estado final de esta sesion

Backend base listo.

Listo para:

- deploy SQL
- deploy de Edge Functions
- configuracion en Meta
- pruebas reales

No listo aun para:

- uso final desde Flutter
- operacion productiva sin pruebas E2E
