# Revisión funcional de Mensajería — 2026-09-04

Implementación y verificación funcional terminadas; publicación macOS + Android
solicitada por el dueño y gestionada por el flujo preparado de release. Checkout:
`/Users/Claudio/Dev/bikeshop-erp`, rama `smartpegas1.0`.

## Correcciones

- El inbox de proveedores publicaba hints restaurados antes de cargar compras:
  mostraba 8 filas y teléfonos, y luego 6 filas y montos. Los dos índices ahora
  se publican juntos, tanto en el panel como en `/chat`; el caché completo abre
  inmediatamente. Vacío, carga y error son estados distintos, con reintento y
  conservación del último conjunto durante refresh.
- `PurchaseService` comparte la lectura pendiente por usuario/tenant. Un segundo
  consumidor ya no interpreta el caché todavía vacío como una respuesta final.
- Responder y copiar están en el menú de cada mensaje compatible. La respuesta
  incluye una cita en composer e historial y contexto real de WhatsApp. La
  proyección durable reconstruye autor/contenido desde el mensaje original y
  rechaza referencias ajenas; una cita entrante histórica sin original visible
  conserva un placeholder explícito.
- Texto, cita y archivos pendientes sobreviven al cambio/cierre del chat dentro
  de la sesión. Un fallo tardío restaura sólo el borrador de origen. Un lote que
  se interrumpe al navegar conserva los archivos todavía no intentados; las
  reservas ambiguas mantienen identidad, texto y cita para reintento seguro.
- Una selección de archivo o generación de PDF que termina tras cambiar de
  conversación no puede adjuntarse al destinatario nuevo. El hilo de tareas se
  captura antes de subir y el destino optimista no depende del widget posterior.
- El chip de documento respeta el ancho disponible en bandejas angostas. Las
  citas están limitadas visualmente en claro/oscuro y el foco diferido se cancela
  al navegar. Las reacciones rápidas exponen acciones accesibles individuales.

## Verificación

- 305 pruebas de mensajería pasaron: carga, caché, filtros/búsqueda, historial,
  recibos, ventanas/plantillas, reacciones, adjuntos, errores y aislamiento entre
  conversaciones; la prueba adicional de accesibilidad vive en la misma suite
  de respuestas/borradores. Análisis `lib test` sin errores (avisos preexistentes).
- 14 aserciones pgTAP de citas pasaron, incluyendo adjunto privado, replay
  idempotente, hilo de tareas y rechazo de referencia a otro chat. El conjunto
  SQL relacionado pasó además sus 98 aserciones previas.
- 8 pruebas del handler real de `whatsapp-send` con proveedor controlado pasaron:
  contexto en texto/audio y bloqueo de referencia ajena antes de contactar Meta.
- Migración `20260905001500_messaging_quoted_replies.sql` aplicada y registrada en
  producción mediante wrapper, con lectura posterior de trigger/RPC/permisos.
  `whatsapp-send` desplegada después. No se modifican migraciones ya aplicadas.
- Sesión macOS canónica conservada, con hot restart: panel final con 6 filas y
  montos, reapertura y conversación citada conservada. La captura del usuario
  confirma que WhatsApp muestra la cita «Test» en la respuesta enviada.
- Pruebas externas limitadas al contacto personal autorizado terminado en 1387:
  texto citado `8c933d5a-1596-4f6d-80ca-03d1f0b6687a` con recibo `read`, reacción
  sobre su Test y archivo sintético sin datos de terceros
  `5d236794-47bb-48dd-8292-c96251efc65c` con recibo `delivered`.

La evidencia local queda en `.tmp/supplier-inbox-diagnosis/`; las regresiones
están versionadas. La prueba de contexto de audio es automática, no una grabación
real. No se recibió aún una respuesta citada nueva desde el teléfono del dueño;
la recepción se valida en SQL/modelo. Los borradores se conservan durante la
sesión, no se promete persistencia al cerrar la aplicación. Instagram/Messenger
conservan sus capacidades vigentes; esta revisión no promete paridad con todas
las funciones de la aplicación WhatsApp.

## Aprendizajes

Un `PopupMenuItem(enabled: false)` alrededor de toda una fila de emojis aplica
`MergeSemantics`: asignar etiquetas a los hijos no basta. Una entrada sin esa
fusión preserva cada acción y su lectura accesible. La regresión inspecciona el
label exacto y la acción tap de cada emoji. Los cambios en clases que contienen
estado pueden requerir hot restart: hot reload conserva instancias del tipo
anterior y no constituye una prueba válida de ese cambio.
