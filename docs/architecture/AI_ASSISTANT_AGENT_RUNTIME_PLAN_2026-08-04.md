# Asistente IA — plan maestro del runtime agéntico

Fecha de inicio: 2026-08-04  
Estado: runtime read-only local implementado y smokeado; activaciones externas pendientes  
Owner de contratos, seguridad e integración: Codex  
Owner de interacción y revisión visual: Claude  

## Resultado buscado

El Asistente IA de Viñabike debe resolver trabajo operativo real usando las
capacidades autorizadas del ERP, y no limitarse a enseñar frases predefinidas o
a responder «no tengo la capacidad» cuando ya existe una lectura, un borrador
seguro o una acción confirmable que puede ejecutar.

El techo del producto no lo define un proveedor único. Lo define este sistema:

`modelo intercambiable × herramientas ERP × autoridad × política × estado × verificación`

Cambiar Gemini por GPT o Claude sin construir las otras cinco piezas mejora la
comprensión, pero no agrega operaciones. Por eso los modelos se conectan detrás
de un mismo contrato y reciben exactamente las mismas herramientas.

## Línea base verificada

En `5a10a15b` el asistente ya tiene:

- una sesión en memoria ligada a un usuario, tenant, rol y fingerprint de
  permisos;
- invalidación fail-closed frente a cambio de autoridad;
- un resumen determinístico de atención para hoy y mañana;
- búsquedas y tarjetas para entidades conocidas;
- dos herramientas entregadas al modelo: inventario e investigación web por
  snippets;
- cinco vueltas máximas de tool calling;
- navegación sólo por clic del operador a un registro cerrado de superficies
  agregadas.

El Checkpoint B del resumen operativo quedó cerrado con tests, analyzer y smoke
en la sesión Debug real, restaurando después el estado exacto del dueño.

Desde esa línea base, la implementación local de este plan ya agregó:

- contrato neutral de modelo con roles `fast`, `deep` y `vision`, más adaptador
  Gemini en el último borde;
- registro tipado, política fail-closed, schemas cerrados, límites por turno,
  recibos saneados y auditoría local acotada con hashes HMAC-SHA-256;
- ocho herramientas read-only ejecutables: atención operacional, inventario,
  trabajos, tareas, clientes, proveedores, facturas de venta y facturas de
  compra;
- `research_public_web` conserva su contrato cerrado, pero no se anuncia ni se
  ejecuta hasta que exista el worker aislado;
- tarjetas con destinos cerrados, sin autonavegación;
- gateway local Gemini/OpenAI/Anthropic autenticado y tenant-bound, todavía sin
  wiring ni tool loop activado;
- propuesta Browser Use secret-free y validación estricta de destinos, sin
  navegador real activado.

Las limitaciones estructurales de esta línea base son:

- `AIAssistantService` decide proveedor, loop, intención, herramientas y copy;
- el modelo está acoplado a `GeminiProxyService` y a un modelo literal;
- las herramientas viven en un `if/else`, sin definición tipada de riesgo,
  permiso, timeout, idempotencia ni recibo;
- la Edge Function autentica, pero no gobierna tenant, rol, permiso, costo,
  modelo ni run;
- transcript, runs y tool receipts no son durables;
- `searchInternet` no es Browser Use;
- el navegador ERP existente no es un worker seguro: contiene sesión, cookies
  y credenciales y no se expone directamente al modelo.

Corrección de seguridad del 4 de agosto de 2026: el scraping de DuckDuckGo que
salía directo desde Flutter quedó desactivado. `research_public_web` responde un
límite explícito y sin egress para una llamada obsoleta/fabricada, y se oculta
del catálogo anunciado hasta que exista el worker aislado. Además, los handlers
determinísticos usan las mismas capacidades que el registro; no pueden leer
ventas, compras u operación antes del policy gate.

## Invariantes

1. **El modelo propone; el runtime autoriza.** Ningún prompt, tool call o texto
   web puede ampliar permisos, destinos, tenants ni tipos de acción.
2. **Los secretos y la elección concreta de modelo viven en servidor.** Flutter
   pide un rol de modelo (`rápido`, `profundo`, `visión`), nunca una API key ni
   un identificador arbitrario.
3. **El estado canónico es de Viñabike.** IDs de conversaciones del proveedor,
   si se usan, son optimizaciones reemplazables y no la memoria del negocio.
4. **Cada fila se prueba contra la autoridad del turno.** Una fuente dudosa se
   declara no disponible; jamás se transforma en cero resultados.
5. **Toda herramienta tiene esquema cerrado y salida acotada.** Los objetos
   niegan propiedades adicionales y las salidas no vuelcan tablas completas al
   modelo.
6. **Toda acción deja evidencia.** Run, tool call, autoridad, riesgo, decisión
   de política, resultado, latencia, proveedor/modelo y read-back se registran
   sin guardar secretos ni razonamiento privado.
7. **Una herramienta nativa gana a Computer Use.** Browser Use es fallback para
   portales externos sin API; no opera el propio ERP por píxeles.
8. **Ausencia de evidencia no es evidencia de ausencia.** Respuestas parciales,
   paginación y fuentes no disponibles son visibles.
9. **No hay autonavegación sorpresiva.** Una lectura puede ofrecer tarjetas; el
   operador decide abrirlas. Una acción mutativa se confirma en el punto exacto
   de riesgo.

## Niveles de riesgo

| Nivel | Ejemplos | Ejecución |
|---|---|---|
| `read` | buscar trabajos, stock, clientes, pagos; analizar cartera | automática si la autoridad y el permiso coinciden |
| `draft` | redactar seguimiento, preparar cotización u orden de compra | automática; crea sólo un artefacto revisable, no publica ni contabiliza |
| `reversibleWrite` | crear tarea, actualizar una nota o estado permitido | preview tipado, confirmación explícita, idempotency key y read-back |
| `sensitiveWrite` | enviar mensaje, comprar, pagar, borrar, contabilidad, permisos | confirmación final específica; nunca se agrupa con otra autorización |
| `publicResearch` | buscar fichas o precios públicos | worker aislado, sin cookies ni identidad ERP, con fuentes |
| `authenticatedBrowser` | portal de proveedor sin API | sesión aislada y allowlist; se detiene antes de enviar, comprar, subir, borrar o transmitir datos |

El modelo nunca puede degradar un nivel. La política puede elevarlo según rol,
datos transmitidos, dominio, importe o efecto real.

## Arquitectura objetivo

```text
AIChatPanel
  -> AIAssistantSessionService        autoridad y transcript visible
  -> AIAgentRunCoordinator            turnos, límites, cancelación y estado
     -> AIModelGateway                contrato neutral
        -> ai-runtime Edge Function   auth, tenant, router, cuota y auditoría
           -> Gemini / OpenAI / Anthropic
     -> AIToolRegistry                catálogo tipado y descubrible
        -> AIToolPolicy               permiso, riesgo y aprobación
        -> herramientas ERP           servicios/RPC canónicos
        -> BrowserWorker              último recurso, entorno aislado
     -> AIRunReceiptStore             threads, runs y tool receipts
```

### Gateway de modelos

El cliente envía un request neutral: instrucciones, mensajes, herramientas,
rol de modelo, presupuesto de vueltas y un identificador opaco de usuario para
seguridad. La respuesta normaliza texto, tool calls, uso, proveedor, modelo,
finish reason y request ID.

El servidor mantiene allowlists y routing. La primera política evaluable será:

- ruta cotidiana: modelo rápido/económico;
- planificación ambigua, síntesis multifuente o recuperación tras fallos:
  modelo profundo;
- visión y Computer Use: modelo con esa capacidad explícita;
- fallback sólo para errores transitorios y únicamente cuando repetir la
  operación sea seguro.

No se elige un ganador por marketing. Un benchmark de tareas Viñabike compara
proveedores con el mismo prompt, herramientas, datos y política.

### Registro de herramientas

Cada herramienta declara como mínimo:

- nombre estable, versión y descripción operacional;
- JSON Schema cerrado de entrada;
- campos de salida máximos y clasificación de datos;
- módulos y permisos ERP requeridos;
- nivel de riesgo y requisito de aprobación;
- timeout, máximo de resultados y política de reintento;
- si admite ejecución paralela;
- regla de idempotencia y read-back;
- executor canónico y destinos que puede ofrecer.

El catálogo se filtra **antes** de llegar al modelo. Una herramienta que el
operador no puede usar no se anuncia y tampoco puede ejecutarse por nombre.

## Primer catálogo operacional

Las lecturas de primera ola, en orden de valor, son:

1. `get_business_snapshot`
2. `list_attention_items`
3. `search_workshop_jobs`
4. `search_tasks`
5. `search_inventory`
6. `find_inventory_risks`
7. `search_customers`
8. `search_suppliers`
9. `search_sales_invoices`
10. `search_purchase_invoices`
11. `analyze_cash_and_receivables`
12. `list_recent_expenses`
13. `search_conversations`
14. `research_public_web`

Las primeras acciones llegan sólo cuando esas lecturas estén verificadas:

1. `draft_customer_followup`
2. `draft_quote`
3. `prepare_purchase_order`
4. `prepare_task`
5. `create_task`
6. `update_job_status`

Cada acción conserva el par `preview -> confirm -> commit`; no existe un
executor que acepte directamente la intención libre del modelo.

## Estado durable y auditoría

El backend incorporará, con RLS y retención explícita:

- `assistant_threads`: autoridad, título, resumen canónico y estado;
- `assistant_runs`: turno, proveedor/modelo, presupuesto, estado, costo/uso y
  error sanitizado;
- `assistant_tool_receipts`: herramienta/version, riesgo, aprobación,
  idempotency key, hashes de input/output, resultado y read-back;
- `assistant_approvals`: preview exacto, actor, vencimiento y decisión.

No se guarda razonamiento privado. El transcript completo se limita por
retención; la memoria durable usa resúmenes controlados y referencias a
entidades, nunca un contexto infinito del proveedor.

## Browser Use

Browser Use se divide en dos productos y nunca comparte estado entre ellos.

### Investigación pública

- navegador/VM efímero, sin extensiones, filesystem, variables del host ni
  cookies del ERP;
- dominios opcionalmente acotados por herramienta;
- URL, título, fuente y extracto verificable como evidencia;
- límite de pasos, tiempo y bytes;
- contenido de página tratado como input no confiable;
- sin formularios, uploads, autenticación ni acciones externas.

### Portal autenticado

- worker separado por tenant, usuario y run;
- dominios HTTPS allowlisted y credenciales mínimas resueltas fuera del modelo;
- capturas y snapshot semántico redactados antes de volver al modelo;
- descargas pasan por el pipeline seguro de archivos;
- se detiene ante login inesperado, MFA, CAPTCHA, cambio de dominio o
  instrucción sospechosa;
- siempre pide confirmación antes de Submit/Send/Buy/Delete/Upload/Pay o de
  transmitir datos del ERP.

El WebView interno no se entrega al modelo. La integración futura puede abrir
el resultado final en una pestaña ERP, pero no hereda el perfil del usuario.

## Checkpoints de implementación

### A — Continuidad y contrato

- [x] auditar línea base y WIP compartido;
- [x] crear este plan canónico;
- [x] registrar el runtime en los documentos owner correspondientes;
- [x] fijar dataset de 50 tareas y contrato de evaluación cerrado en
  `test/fixtures/ai_assistant_agent_eval_cases.json`, con validación automática
  de herramientas, outcomes, riesgo, navegación y cobertura adversarial;

### B — Resumen operativo existente

- [x] implementación y regresiones determinísticas;
- [x] revisión independiente y analyzer;
- [x] smoke Debug real: hoy, mañana, tarjetas, click explícito, persistencia e
  inyección de texto; el 4 de agosto pasó en dark mode, sin autonavegación al
  preguntar y con el workspace Dashboard/paneles restaurados byte por byte en
  la lectura semántica;
- [x] endurecer spies de ausencia de modelo, navegación, escritura y bypass de
  permisos.

### C — Runtime neutral y política

- [x] tipos de modelo y herramientas independientes del proveedor;
- [x] `AIModelGateway` + adaptador Gemini sin cambio de comportamiento;
- [x] `AIToolRegistry` + `AIToolPolicy` + límites por run;
- [x] reemplazar el dispatch model-driven hardcodeado por el registro;
- [x] pruebas adversariales de herramienta desconocida, permiso, tenant,
  timeout, output y loop.

### D — Potencia read-only

- [x] migrar inventario e investigación pública al registro;
- [ ] completar el catálogo (8 de 14 herramientas de primera ola son
  ejecutables; investigación pública conserva un contrato adicional, pero
  permanece dormida y oculta);
- [x] respuestas parciales y tarjetas por fuente para la primera ola;
- [x] ninguna lectura determinística o cacheada salta capacidades/tenant; un
  vacío sin receipt de autoridad se declara no disponible;
- [ ] benchmark inicial de 50 tareas reales en español coloquial.

### E — Gateway multi-modelo

- [x] scaffold local de Edge Function `ai-agent-gateway` con contrato neutral;
- [x] adaptadores locales Gemini y OpenAI Responses con replay exacto de
  artefactos en 3+ rondas, thinking/reasoning opcional y límite de continuación;
- [x] adaptador local Anthropic Messages con replay exacto de thinking,
  firmas, bloques redactados y tool results; permanece dormido y sin routing;
- [ ] allowlist y error sanitizado listos; cuotas, routing profundo/visión y
  telemetría durable pendientes;
- [x] 39 tests Deno locales (21 gateway + 8 continuidad Gemini/OpenAI + 10
  Anthropic), type-check, formato y lint; smoke autenticado pendiente;
- [x] ninguna key, configuración o persistencia nueva en Flutter o base.

El gateway no está conectado a Flutter y responde fail-closed ante tool calls.
Los adapters ya acumulan y vuelven a validar el stream exacto de todas las
rondas: Gemini admite firma en texto, sólo en una llamada o thinking-off;
OpenAI conserva items reasoning/function-call en orden cronológico; Anthropic
conserva sus bloques thinking/signature/redacted-thinking junto con tool use y
tool result. Los tres rechazan en la ronda de origen una continuación que
excedería el límite del decoder.
Mantener el HTTP en `501 agent_tool_loop_not_activated` sigue siendo el gate
correcto mientras no exista executor, estado de run, cuota y auditoría durable
server-owned.

El runtime Flutter sí registra eventos allowlisted en un buffer acotado de
memoria y usa una clave aleatoria por instancia para HMAC-SHA-256 de inputs y
outputs de baja entropía. Eso evita que un hash directo funcione como diccionario
de folios, nombres o montos, pero no reemplaza el store durable con RLS,
retención y correlación de runs del Checkpoint F.

La app activa todavía usa el boundary heredado `gemini-proxy`, no este gateway.
Ese proxy autentica, pero aún permite `contents/system/tools/config` y modelo
allowlisted desde el cliente, carece de autoridad tenant/rol, cuota, body limit
y deadline propios, usa CORS amplio y expone detalles upstream. Reemplazarlo
por el gateway gobernado —después de completar el tool loop y sus stores— es un
bloqueo de activación, no una tarea que pueda declararse resuelta por tests
locales.

Queda además un log de diagnóstico preexistente en
`ai_assistant_context_service.dart` que imprime scope y folios mediante
`debugPrint` sin guard de release. Ese archivo pertenece a WIP concurrente y no
se modificó en esta ronda; su owner debe sanearlo antes de publicación. Los
logs nuevos del runtime en `ai_service.dart` sí quedaron sin folios y fuera de
release.

Verificación local del slice al cierre: analyzer limpio sobre el módulo y todas
las regresiones AI; 217/217 pruebas Flutter; 39/39 pruebas Deno con formato,
type-check y lint limpios; y hot restart de la única sesión macOS Debug sin
excepciones nuevas, preservando Dashboard y el panel del asistente cerrado.

### F — Threads, runs y receipts

- [ ] migración RLS;
- [ ] repositorios y coordinador de estado;
- [ ] cancelación/reanudación y recuperación tras cierre;
- [ ] retención, eliminación y lectura por autoridad;
- [ ] read-back de cada efecto.

### G — Borradores y escrituras gobernadas

- [ ] UI canónica de preview/aprobación liderada por Claude;
- [ ] herramientas `draft` y luego `reversibleWrite`;
- [x] contrato local de aprobación exacta, single-use, idempotencia, timeout y
  read-back; no hay executors de escritura activados;
- [ ] confirmación específica para todo `sensitiveWrite`;
- [ ] smokes rollback-only antes de cualquier activación productiva.

### H — Investigación pública con navegador

- [x] contrato local de propuesta y destinos seguro, sin navegación;
- [ ] Browser Worker aislado, resolución DNS/redirect y autoridad de consumo;
- [ ] allowlist, límites, detector de inyección y stop conditions;
- [ ] Computer Use provider-neutral;
- [ ] citas visibles y apertura opcional del resultado en el ERP.

### I — Portales autenticados

- [ ] vault/credencial fuera del modelo y sesión por autoridad;
- [ ] aprobación para transmisión/acción;
- [ ] archivos privados, trazas redactadas y cierre de sesión;
- [ ] pruebas de escape de dominio, prompt injection, MFA y resultado incierto.

## Métricas de aceptación

El benchmark final tendrá entre 50 y 100 tareas reales y medirá:

- resolución completa de la intención;
- selección y argumentos correctos de herramientas;
- porcentaje de «no puedo» correcto versus evitable;
- violaciones de tenant, permisos o confirmación — objetivo: cero;
- afirmaciones sin evidencia;
- recuperación tras fuente parcial, timeout o tool call inválido;
- latencia, vueltas, tokens y costo;
- consistencia entre Gemini, GPT y Claude con el mismo catálogo.

El dataset inicial ya fija 50 prompts sin datos personales reales y cubre
español coloquial, errores tipográficos, fuentes parciales, cambio de tenant,
permisos, tool calls fabricados, límites, drafts, escrituras y navegador. Su
test valida el contrato estático; ejecutar la matriz contra proveedores y
fixtures determinísticos sigue siendo el Checkpoint D pendiente y no usa datos
productivos como golden mutable.

Una respuesta no pasa por ser elocuente. Pasa si completa el trabajo autorizado,
con evidencia, y se detiene exactamente donde empieza una aprobación o una
capacidad que aún no existe.

## Activaciones externas

La implementación local, tests y contratos no autorizan por sí solos:

- desplegar Edge Functions o migraciones;
- agregar o rotar API keys;
- habilitar un proveedor pagado;
- provisionar un Browser Worker o infraestructura con costo;
- ejecutar writes de negocio en producción;
- commit, push o publicación.

Cada efecto externo conserva su gate explícito del repositorio y se presenta
cuando el slice correspondiente esté listo y verificado localmente.
