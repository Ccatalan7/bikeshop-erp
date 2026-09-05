# Revisión funcional de Mensajería — 2026-09-04

Revisión de transporte, borradores e interacción; publicación macOS + Android
solicitada por el dueño y gestionada por el flujo preparado de release. La
validación del transporte por sí sola no acredita paridad de interacción. Checkout:
`/Users/Claudio/Dev/bikeshop-erp`, rama `smartpegas1.0`.

## Correcciones

- El inbox de proveedores publicaba hints restaurados antes de cargar compras:
  mostraba 8 filas y teléfonos, y luego 6 filas y montos. Los dos índices ahora
  se publican juntos, tanto en el panel como en `/chat`; el caché completo abre
  inmediatamente. Vacío, carga y error son estados distintos, con reintento y
  conservación del último conjunto durante refresh.
- `PurchaseService` comparte la lectura pendiente por usuario/tenant. Un segundo
  consumidor ya no interpreta el caché todavía vacío como una respuesta final.
- Deslizar la burbuja hacia la derecha cita el mensaje. Mantener la burbuja
  abre sólo reacciones; mantener el fondo de la fila selecciona. La selección
  permite copiar varios mensajes en orden, responder a uno y reenviar texto
  o adjuntos a un chat elegido con confirmación final. El clic secundario
  conserva las acciones explícitas para escritorio. La respuesta
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
- Los archivos mostraban sólo su ficha y ocultaban el texto que sí se enviaba
  a WhatsApp. Ahora la burbuja muestra su caption, incluyendo mensajes ya
  guardados, sin repetir el nombre cuando no existe texto adicional.
- El chip de documento respeta el ancho disponible en bandejas angostas. Las
  citas están limitadas visualmente en claro/oscuro y el foco diferido se cancela
  al navegar. Las reacciones rápidas exponen acciones accesibles individuales.

## Verificación

- 310 pruebas de mensajería pasaron: carga, caché, filtros/búsqueda, historial,
  recibos, ventanas/plantillas, reacciones, adjuntos, errores y aislamiento entre
  conversaciones; la prueba adicional de accesibilidad vive en la misma suite
  de respuestas/borradores, junto con la regresión de caption de archivos. Análisis `lib test` sin errores (avisos preexistentes).
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

- Corrección de interacción verificada en la app macOS: reacción por pulsación,
  selección por fila, selección múltiple/copia, cita por deslizamiento y reenvío.
  La imagen `74ff7949-907d-4ed9-9a34-47ef6a215d56` y el archivo
  `6b97cc2e-d0cf-4add-9ad3-d36ba5868740` citan el Test original y tienen recibo
  `read`. El reenvío de texto `38c6e3d9-23ea-41a9-8f9e-ea6adac945fa` y archivo
  `1d9ef45c-e3b9-4427-9d58-052f6c75534c` tienen recibo `delivered`: el archivo
  tiene una reserva privada nueva y no arrastra la cita original.
- Las tres pruebas de `integration_test/messaging_gestures_device_test.dart`
  pasaron en Android `emulator-5554`: los gestos usan el componente real de
  `ChatWindow` con datos sintéticos, sin acceso a producción. La prueba comprueba
  competencia con scroll, tap del adjunto en selección y cancelación al cambiar
  de mensaje. Los envíos reales anteriores se realizaron desde macOS.

La evidencia local queda en `.tmp/supplier-inbox-diagnosis/`; las regresiones
están versionadas. La prueba de contexto de audio es automática, no una grabación
real. El archivo se abrió y su contenido se leyó en el visor real; la cita también
se verificó en un host compacto macOS de 430 px. No se recibió aún una respuesta citada nueva desde el teléfono del dueño;
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


### Interacción y superficies (corrección 2026-09-04)

El menú único de pulsación implementaba acciones, pero no el contrato de gestos
pedido. `SelectionArea` también competía por esa pulsación. El dueño común
`ChatMessageRow` separa selección del fondo y `ChatMessageBubble` administra
reacción y deslizamiento horizontal; la selección de texto queda desactivada
sólo en esas filas y la copia usa el contenido seleccionado. Un deslizamiento
corto, hacia la izquierda, vertical o cancelado no cita. Cambiar chat, identidad
o sesión invalida el gesto y la selección. Android Back/Escape cierra selección.

La barra de acciones vive debajo de la identidad del chat: reemplazar su primera
fila la situaba bajo las pestañas del workspace en escritorio, dejando las
acciones ocultas aunque la prueba aislada pasara. El timestamp saliente también
debe participar en el ancho de la burbuja: el `Positioned` anterior recortaba la
hora en textos cortos. Ambas condiciones tienen regresión y frame real.

El reenvío congela selección y destino y detiene el resto del lote al cambiar
el origen o fallar una entrega. Nunca copia referencias privadas, contexto de
negocio, hilos ni citas del origen. Reautoriza la descarga y crea una reserva
propia del destino; no convierte texto reenviado en una plantilla cuando vence
la ventana de WhatsApp y no repite automáticamente un resultado incierto.
