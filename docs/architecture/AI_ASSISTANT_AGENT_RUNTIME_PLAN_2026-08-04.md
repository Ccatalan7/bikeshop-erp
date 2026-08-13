# Asistente IA — plan maestro del runtime agéntico

- Fecha de inicio: 2026-08-04
- Estado: runtime durable activo en producción; gateway Edge v66 `ACTIVE`,
  `verify_jwt=true`, bundle
  `d34f707a703baa1cd5fa829b33059ae3d0462e4562e509962b34df5d1b8b1808`, con
  búsqueda web general/técnica, inventario estructurado y reconocimiento de
  límites verificados en producción el 13 de agosto de 2026
- Owner de contratos, seguridad e integración: Codex
- Owner de interacción y revisión visual: Claude

## Resultado buscado

El Asistente IA de Viñabike debe resolver trabajo operativo real usando las
capacidades autorizadas del ERP, y no limitarse a enseñar frases predefinidas o
a responder «no tengo la capacidad» cuando ya existe una lectura, un borrador
seguro o una acción confirmable que puede ejecutar.

Corrección de producto del 11 de agosto de 2026: una frase que hoy falla no se
arregla agregándola a un clasificador ni escribiendo una respuesta especial. El
gateway nuevo es **model-first**: recibe lenguaje libre, infiere el objetivo
desde la conversación y el contexto autorizado, decide y encadena herramientas,
contrasta las fuentes disponibles y recién entonces responde u ofrece una
acción. Los prompts concretos del dataset son regresiones y mediciones, nunca
reglas de dispatch ni copy de producción. El engine determinístico heredado no
recibe nuevas intenciones; se retira al activar el gateway validado.

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
- catorce herramientas ERP anunciables: snapshot/atención operacional,
  inventario y riesgos, trabajos, tareas, clientes, proveedores, facturas de
  venta/compra, gastos, caja/cobranza, conversaciones y preparación de tareas;
- `research_public_web` usa Gemini Interactions stateless con búsqueda Google
  obligatoria y verificada; se anuncia sólo con el transporte server-side y el
  modelo lo invoca con `{}`. El servidor deriva la tarea exclusivamente del
  mensaje actual del operador, nunca del historial, resultados de tools ni texto
  agregado por el modelo;
- una petición explícita de web, actualidad u otra fuente pública exige
  `research_public_web` en el protocolo del proveedor —Gemini `ANY` con nombre
  permitido, OpenAI `tool_choice` de función y Anthropic `tool_choice` de tool—.
  El proveedor conserva el ID y la continuación reales, pero no puede cerrar con
  una respuesta de memoria; la síntesis posterior vuelve al planning normal;
- tarjetas con destinos cerrados; las lecturas informativas esperan clic y una
  petición explícita de lista puede abrir únicamente una proyección server-owned
  ya filtrada;
- gateway Gemini/OpenAI/Anthropic autenticado y tenant-bound con tool loop,
  cuotas, leases, recibos y replay durable implementados localmente;
- engine Flutter completo para ese gateway, seleccionado una sola vez por sesión
  mediante `AI_AGENT_GATEWAY_ENABLED` y sin fallback por turno. El 12 de agosto
  de 2026 quedó activo en la sesión Debug canónica; las builds que no reciben el
  define conservan el default legado;
- el cliente Browser Use efímero permanece como scaffold desactivado incluso si
  aparece una credencial: no podrá activarse hasta que exista una política
  read-only impuesta por el proveedor y un trace atestable de URLs/acciones.

Las limitaciones estructurales de esta línea base son:

- `AIAssistantService` decide proveedor, loop, intención, herramientas y copy;
- el modelo está acoplado a `GeminiProxyService` y a un modelo literal;
- las herramientas viven en un `if/else`, sin definición tipada de riesgo,
  permiso, timeout, idempotencia ni recibo;
- el rollout productivo del gateway ya existe, pero cada capacidad nueva sigue
  requiriendo migración, deploy y smoke autenticado antes de considerarse
  activa;
- `searchInternet` no es Browser Use;
- el navegador ERP existente no es un worker seguro: contiene sesión, cookies y
  credenciales y no se expone directamente al modelo.

Corrección de seguridad del 4 de agosto de 2026, reemplazada por el runtime
server-side del 12 de agosto: el scraping de DuckDuckGo que salía directo desde
Flutter permanece desactivado. La investigación pública actual sólo se anuncia
cuando existe el transporte Gemini aislado, deriva la tarea del mensaje actual
en Edge y rechaza llamadas obsoletas/fabricadas antes del executor. Los handlers
determinísticos siguen usando las mismas capacidades que el registro; no pueden
leer ventas, compras u operación antes del policy gate.

Corrección causal del 12 de agosto de 2026: el primer contrato de egress limitó
la investigación a intenciones cerradas y códigos técnicos. Eso impedía
representar una pregunta pública general o una fuente nombrada —por ejemplo,
opiniones de Reddit— aunque Browser Use y Google Search sí pudieran resolverla.
`research_public_web` acepta ahora un tool call exacto `{}` sin campos de egress
controlados por el modelo. La tarea externa es la proyección NFKC del mensaje
actual completo del operador dentro del límite HTTP de 8192 bytes; no se
incorporan historial, contexto ERP, salidas de herramientas, dominio, URL o
locale escrito por el modelo. La frontera aplica DLP, HTTPS/citation checks,
SSRF y límites de costo/tiempo/pasos, sin dispatch de respuesta por frase ni
límite temático. El detector server-owned sólo decide que una solicitud
explícita necesita autoridad de egress; el tool choice de los tres adapters
obliga entonces una llamada nativa única a `research_public_web`. El runtime
rechaza cualquier respuesta que intente saltársela y deja de reintentar mediante
copy de prompt. El usage/costo de Gemini Search y del enriquecimiento URL
Context queda en el mismo tool receipt y se agrega atómicamente al run y sus
cuatro buckets, sin fingir un segundo provider attempt. La respuesta acepta las
dos variantes documentadas del call (`query` y `queries`) y preserva la
evidencia de búsqueda como `partial` si el enriquecimiento falla. Esto corrige
el falso «servicio no disponible» causado por rechazar una respuesta oficial y
luego botar una búsqueda válida en una segunda llamada. El parser SSE termina en
`interaction.completed`, conserva citas válidas de una respuesta acotada aunque
otra cita quede truncada y resuelve redirects de grounding a URLs directas del
publisher sin reenviar la API key ni descargar la página. Para una entidad
fechada, la identidad conserva también términos cortos y numéricos de
trim/generación, valida al publisher por dominio registrable —nunca por un
subdominio que repite la marca— y elimina antes de sintetizar toda fuente que
afirma otro trim/material/año. Un diámetro de rueda agregado al nombre natural
de una bicicleta —por ejemplo `29`— permanece en la consulta para recuperar
evidencia, pero no se exige como parte del nombre canónico cuando la fuente lo
omite; si una fuente afirma explícitamente `26`, `650b` u otra medida
incompatible, se elimina antes de sintetizar. Los alias `27.5`/`650b` y
`29`/`29er` se normalizan como evidencia de fitment; `700c` sigue siendo una
categoría explícita distinta y compartir diámetro BSD no demuestra la misma
variante. Esto no borra trims numéricos como `Fuel EX 8 Gen 6`. Una
especificación de montaje de fábrica exige además evidencia exacta del dominio
registrable del fabricante: un retailer, marketplace, foro o revendedor puede
complementar contexto, pero nunca establecer por sí solo la maza, agujeros,
cassette u otro componente OEM. Si la primera recuperación sólo entrega un
revendedor, la corrección acotada busca explícitamente el publisher oficial y
elimina la afirmación secundaria antes de sintetizar. Una única recuperación
adicional exige la identidad exacta y su costo queda agregado al mismo receipt.
Todas las páginas oficiales exactas pueden aportar hechos distintos; las fuentes
técnicas independientes se conservan cuando no pretenden ser la entidad
principal, aunque no repitan una marca o referencia de componente de la página
OEM. **Corrección final 2026-08-12:** Search selecciona URLs, pero no es la
autoridad final de una especificación técnica. Para cada URL técnica elegible el
servidor hace un GET directo, sin credenciales, redirects ni cookies, después de
validar DNS público; limita la lectura a 1 MiB/8 s y conserva spans exactos de
HTML/JSON. Recorre y puntúa todas las filas antes de aplicar el límite de
extractos, une sólo pares label→value y nunca el valor de una fila con el label
de la siguiente. El `title`/`h1` publisher vuelve a validar año y fitment: una
página histórica que Search rotula incorrectamente se elimina y consume, como
máximo, el mismo único retry de identidad exacta. Una falla de lectura conserva
Search como parcial; una contradicción publisher elimina sólo esa entidad.

Después de la evidencia principal, el runtime evalúa un registro server-owned de
hechos técnicos solicitados —modelo/fabricante, eje, driver/freehub y agujeros—.
Los códigos públicos se preservan con guiones, las medidas/años/IDs de página no
se convierten en modelos, y una fuente técnica complementaria sólo establece un
hecho si publica el valor en la misma fila, enlaza el código del componente y su
dominio corresponde al fabricante mencionado por la tarea o la fuente OEM. En
particular, nombrar el cassette `PG-1230` no demuestra por sí solo su interfaz.
Una review, video, retailer o resumen generado que no pruebe ningún target
tipado se elimina antes del terminal. Evidencia repetida de una misma URL se
fusiona antes del límite de cinco fuentes. Si un hecho sigue sin fuente, queda
`unresolved`; el terminal server-owned lo renderiza como desconocido. Cuando no
hay objetivos públicos adicionales el terminal expone el schema exacto `{}`. Los
turnos posteriores a evidencia tipada se limitan a 512 tokens descartables y
cualquier cierre sin tool recibe una sola recuperación con el terminal forzado,
evitando agotar el deadline con prosa que nunca se persiste. Preguntas públicas
generales no crean targets técnicos y conservan síntesis y citas normales.

Evidencia productiva v61:

- prompt canónico Specialized: client request
  `0f4418b6-eecb-4fc6-9661-0c93d6cae01f`, run
  `277cfa96-80ca-4ec8-9dd2-22bdafcd451d`, HTTP 200 y run/receipt `succeeded`;
  recuperó exclusivamente la URL publisher `p/199785`, declaró desconocidos el
  modelo exacto y el driver/freehub, y publicó el span exacto
  `Rear Hub Alloy,
  sealed cartridge bearings, 12x148mm thru-axle, 28h`. No
  apareció `p/175252`, `p/199786`, retailer, review, video ni resumen generado.
  El receipt registró `result_count=1`, 22 unidades de `google_search_query`,
  2661/2405 tokens externos, costo externo 330030 µUSD y costo total del run
  356944 µUSD;
- smoke general Reddit: client request `854db1db-ecb6-4409-97ad-f89d7132344f`,
  run `2eb56521-dcf0-4af5-baa1-20485a4581ec`, HTTP 200 y run/receipt
  `succeeded`; respondió recomendaciones útiles de cubiertas, tubeless/sellante,
  presión, inspección y conducción con cinco URLs HTTPS directas de Reddit. El
  receipt registró `result_count=5`, seis unidades de `google_search_query`,
  1584/1633 tokens externos, costo externo 98624 µUSD y costo total 134122 µUSD.

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
9. **No hay autonavegación sorpresiva.** Una lectura informativa puede ofrecer
   tarjetas y el operador decide abrirlas. Una petición explícita de buscar,
   mostrar, listar o abrir puede activar sólo un destino agregado cerrado cuando
   el receipt adjunta la consulta, el filtro y el conjunto server-owned exactos.
   Una acción mutativa se confirma en el punto exacto de riesgo.

## Niveles de riesgo

| Nivel                  | Ejemplos                                                       | Ejecución                                                                                         |
| ---------------------- | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `read`                 | buscar trabajos, stock, clientes, pagos; analizar cartera      | automática si la autoridad y el permiso coinciden                                                 |
| `draft`                | redactar seguimiento, preparar cotización u orden de compra    | automática; crea sólo un artefacto revisable, no publica ni contabiliza                           |
| `reversibleWrite`      | crear tarea, actualizar una nota o estado permitido            | preview tipado, confirmación explícita, idempotency key y read-back                               |
| `sensitiveWrite`       | enviar mensaje, comprar, pagar, borrar, contabilidad, permisos | confirmación final específica; nunca se agrupa con otra autorización                              |
| `publicResearch`       | buscar fichas o precios públicos                               | worker aislado, sin cookies ni identidad ERP, con fuentes                                         |
| `authenticatedBrowser` | portal de proveedor sin API                                    | sesión aislada y allowlist; se detiene antes de enviar, comprar, subir, borrar o transmitir datos |

El modelo nunca puede degradar un nivel. La política puede elevarlo según rol,
datos transmitidos, dominio, importe o efecto real.

## Arquitectura objetivo

```text
AIChatPanel
  -> AIAssistantSessionService        autoridad y transcript visible
     -> GatewayAIAssistantTurnEngine  thread opaco, cancelación y cards cerradas
        -> ai-agent-gateway           auth, router, cuota y coordinador del run
           -> Gemini / OpenAI / Anthropic
           -> AIToolRegistry          catálogo filtrado por capacidad
              -> RPCs ERP             caller JWT + tenant derivado en DB
           -> RunStore                threads, runs, leases y receipts
           -> BrowserWorker           futuro; aislado y sin sesión ERP
```

### Gateway de modelos

El cliente envía un request neutral y cerrado: una sola frase del operador, un
rol lógico, UUID opacos de request/thread y, opcionalmente, hasta veinte UUID de
trabajos ya visibles. Nunca envía instrucciones de sistema, historial, tools,
tenant, usuario, rol ERP, permisos, proveedor o modelo concreto. El servidor
reconstruye el historial canónico, deriva autoridad, elige tools y proveedor y
devuelve sólo texto, cards cerradas, thread y run; tool calls, continuaciones,
uso interno y modelo concreto no cruzan hacia Flutter.

El servidor mantiene allowlists y routing. La primera política evaluable será:

- ruta cotidiana: modelo rápido/económico;
- planificación ambigua, síntesis multifuente o recuperación tras fallos: modelo
  profundo;
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

## Catálogo operacional y reconocimiento de límites

El modelo recibe diecisiete primitivas actuales, filtradas por autoridad:

1. `inspect_inventory_schema`
2. `search_inventory`
3. `find_inventory_risks`
4. `get_business_snapshot`
5. `list_attention_items`
6. `search_workshop_jobs`
7. `search_tasks`
8. `search_customers`
9. `search_suppliers`
10. `search_sales_invoices`
11. `search_purchase_invoices`
12. `list_recent_expenses`
13. `analyze_cash_and_receivables`
14. `search_conversations`
15. `prepare_task`
16. `report_capability_gap`
17. `research_public_web`, sólo cuando el worker server-side está activo

No existe una función por frase, producto o ejemplo. El modelo decide y encadena
primitivas según la intención; el código define únicamente la gramática segura,
la autoridad, las fuentes y los efectos que puede ejecutar. Cuando ninguna
composición cubre la petición, `report_capability_gap` acepta sólo dominio,
operación, causa y alternativa desde enums cerrados; para carencia de datos
estructurados exige además la clave exacta inspeccionada y `null` para cualquier
otra causa. El runtime ignora toda prosa del modelo y persiste una explicación
server-owned. La herramienta se
anuncia incluso si la autoridad no tiene lecturas de negocio, por lo que un
usuario sin permiso recibe una negativa honesta en vez de silencio. Una
respuesta `source_unavailable` sólo se autoriza después de un fallo real de
fuente; un schema/argumento rechazado, cero filas o cero cobertura nunca se
traducen como caída del servicio.

`inspect_inventory_schema` es introspección de negocio, no acceso a SQL. Recibe
una consulta y una categoría tentativa, resuelve el árbol real del tenant y
devuelve como máximo cuarenta filas cerradas con categoría/path, familia,
`spec_definitions.key`, label, tipo, unidad, operadores, valores finitos y
`populatedCount/productCount`. Para medidas, rangos, estándares o compatibilidad,
el runtime exige que esta inspección ocurra en una ronda anterior y vincula la
búsqueda posterior a una categoría, claves y operadores presentes en esa
respuesta; así el modelo no puede precomprometer ni cambiar una clave inventada
después de ver el esquema.

`search_inventory` conserva una sola selección para texto, cards y navegación.
Su v5 separa `query` opcional, categoría canónica, disponibilidad, presentación
y `technicalPredicates`. La categoría incluye descendientes y sus familias
técnicas activas. Los predicados tipados soportan igualdad/desigualdad,
comparaciones numéricas, rango y membresía —más `contains` sólo para texto— y
PostgreSQL los revalida contra el tipo descubierto. `product_spec_values` es
autoridad y un conflicto estructurado elimina la fila. El fallback de identidad
se conserva únicamente para igualdad/membresía exacta con ficha vacía; nunca
satisface `<`, `>`, `between` ni otra comparación. Por eso un nombre con varias
medidas como `68x122.5` no puede probar cuál de ellas es el largo de eje. Cada
fila sigue declarando `product_spec`, `identity_fallback` o `not_applicable`.
Disponibilidad se aplica antes del límite. Con `open_list`, el runtime reemplaza
la prosa del modelo y Flutter abre sólo el `listRef` server-owned; con `answer`,
la card espera clic.

### Matriz de escenarios del negocio

Esta matriz evita dos extremos: herramientas diminutas por frase y una
herramienta genérica con SQL o writes arbitrarios. Cada familia nueva debe
componerse de `discover/read/filter/aggregate/compare/draft/confirm/commit`, con
un dueño canónico y un receipt verificable.

| Familia | Preguntas/peticiones frecuentes | Primitivas actuales | Brecha que debe declarar hoy / próxima primitiva segura |
|---|---|---|---|
| Operación diaria | qué urge, qué vence, qué hago primero | snapshot, atención, trabajos, tareas | asignación/estado masivo requiere preview + confirmación |
| Inventario y compatibilidad | stock por ficha, medidas, estándares, riesgos, equivalentes | inspector, búsqueda tipada, riesgos | cero cobertura se declara; comparación de compatibilidad necesita un scorer tipado |
| Taller | estado de trabajos, solicitudes, técnico, fecha prometida | búsqueda de trabajos + contexto visible | diagnóstico, presupuesto y cambio de estado requieren draft/confirm separados |
| Clientes | encontrar ficha, historial operativo, seguimiento | búsqueda de clientes; joins acotados con trabajos | timeline y borrador de contacto aún necesitan herramientas propias |
| Comunicaciones | pendientes de respuesta, canal, contexto, redactar/enviar | metadata de conversaciones | cuerpo/borrador/envío no existen; enviar será siempre sensitiveWrite confirmado |
| Ventas | factura, deuda, vencimiento, cotización, devolución | facturas de venta + cobranza | cotización/orden/devolución requieren preview exacto y commit idempotente |
| Compras | proveedor, factura, faltantes, orden, recepción | proveedores, facturas, riesgos | orden/recepción necesitan draft y confirmación; no se simulan desde texto |
| Contabilidad | gastos, caja contable, cartera, conciliación, pago | gastos + caja/cobranza | conciliación, asiento y pago no tienen tool y se declaran explícitamente |
| Tareas | buscar, priorizar, crear recordatorio | búsqueda + `prepare_task` + aprobación post-click | edición/cierre masivo requieren nuevos comandos CAS |
| Archivos y OCR | leer factura PDF/imagen, revisar candidatos, importar | el módulo OCR existe fuera del agente | el chat no tiene tool de archivo; debe declararlo hasta crear upload/parse/preview |
| Web pública | manuales, actualidad, Reddit, comparaciones públicas | investigación pública general | portal autenticado sigue desactivado y se declara, no se finge navegación |
| Proveedores autenticados | estado de pedido, disponibilidad privada, carrito | ninguna | browser aislado + allowlist + stop antes de submit; hoy capability gap |
| Tienda/marketing | productos publicados, campañas, SEO, rendimiento | ninguna lectura anunciada | read models primero; publicación siempre preview/confirm |
| Personal/nómina | turnos, liquidaciones, pendientes, pagos | ninguna herramienta del agente | lecturas PII mínimas por permiso; pagos siempre sensitiveWrite específico |
| Analítica | margen, rotación, forecast, comparación por período | snapshots acotados solamente | agregadores server-owned con métricas definidas; nunca descargar tablas al modelo |

El dataset de evaluación incluye desde esta corrección consultas técnicas con
inspección previa y escenarios no cubiertos de conciliación, pricing masivo,
OCR y forecast. El éxito no consiste en que el modelo siempre responda: consiste
en ejecutar la composición correcta o detenerse con la limitación correcta.

Las migraciones `20260813174500` y `20260813180300` desplegaron inicialmente la
proyección/lista cerrada. El smoke autenticado
`clientRequestId=4384c657-d143-43f6-8aef-cc8efa9b6cf6`, run
`ea305ead-1b18-4a78-9745-2ce6cdcd7e62`, respondió HTTP 200 con seis supuestas
cámaras 29,
una sola card, `availability=in_stock`, seis UUID exactos y `autoOpen=true`.
Ese transporte era sano, pero no fue aceptación de producto: `29` coincidió con
el sufijo del EAN `6938112671129` de una cámara aro 26. El smoke de cliente
anterior `ed358d3c-9530-4e3d-96fc-d6049bb56a8d` heredó los mismos seis
resultados; sólo probó compatibilidad de wire sin `listRef`, no precisión de
catálogo.

**Cierre productivo supersedido del 13 de agosto de 2026:** la migración
`20260813190000` y el smoke v3 demostraron el filtro técnico y eliminaron la
cámara aro 26, pero todavía mezclaban categoría e identidad en `query` y el
listado parecía una búsqueda manual. Esa prueba queda como evidencia histórica,
no como contrato vigente.

**Cierre productivo supersedido del 13 de agosto de 2026:** la migración
  `20260813203000` quedó aplicada, leída de vuelta y registrada. La función v4 era
`SECURITY DEFINER`, `STABLE`, tiene `search_path=pg_catalog, public, pg_temp` y
timeout de 4500 ms; sólo `authenticated` puede ejecutarla. El gateway quedó en
v65 `ACTIVE`, `verify_jwt=true`, bundle
`ed4821b9376fafad50a2ab8f3c290b3aaf11e8e15766c88752193f880b0994e6`.

La prueba en la sesión macOS canónica usó el prompt
`buscame camaras 29 que tengamos en stock` y produjo
`clientRequestId=8c0d93c5-e0fe-495d-8e32-3513b1b7b043`, run
`5bc63393-a0b4-429b-8336-ae59a7f692a2`. Abrió Product List con cinco UUID
exactos, `availability=in_stock`, `autoOpen=true`, buscador local vacío y la card
`Cámaras · 1 ficha técnica · 4 por identidad · En stock · 29"`. Los cinco tenían
stock positivo; la cámara aro 26 no apareció. El run terminó `succeeded`, sin
`error_code`, con 14855 tokens de entrada, 1659 de salida y costo total 49618
µUSD. Los tres intentos `gemini-3.1-pro-preview` quedaron contabilizados y
`succeeded`. El primer tool call fue rechazado y receipted como
`invalid_tool_arguments`; el runtime lo reparó sin ejecutar la consulta. El
segundo receipt `search_inventory` fue la única lectura ejecutada: `succeeded`,
sin `failure_code`, `result_count=5` y `read_back_verified=true`. El transcript,
la card persistida y el listado real muestran la misma selección y declaran la
fuente técnica en vez de esconder el fallback.

La compatibilidad de rollout se mantiene: un cliente sin el header de listas
recibe la misma card sin el campo desconocido `listRef` y copy de clic veraz;
el auto-open y la lista exacta sólo se activan cuando el cliente anuncia el
contrato.

**Cierre productivo vigente del 13 de agosto de 2026:** las migraciones
`20260813213000`, `20260813214500` y `20260813215000` quedaron aplicadas, con
read-back exacto y registro de historia. La última reemplaza el allowlist y
límite global duplicados del ledger por un contrato tipado de riesgo, política
y máximo por herramienta; el inspector admite cuarenta filas, las lecturas
ordinarias siguen limitadas a diez y un nombre no registrado no produce
contrato. `assistant_runtime` permanece sin `EXECUTE` para `authenticated` ni
`service_role`; sólo los wrappers v2 atestados siguen expuestos. El validador
derivado de producción ahora captura también ese schema aislado, sin filas, y
la regresión de ledger pasó 107 assertions. El gateway v66 quedó `ACTIVE`,
`verify_jwt=true`, bundle
`d34f707a703baa1cd5fa829b33059ae3d0462e4562e509962b34df5d1b8b1808`.

La prueba real `buscame motores de menos de 125mm de eje` produjo
`clientRequestId=5d5adc5d-4085-4e02-a54d-9c14fae3c83c`, run
`441f3833-0a4b-4462-bfeb-9490e3fa683c`: `succeeded`, sin `error_code`, 14906
tokens de entrada, 917 de salida y 40816 µUSD. Los receipts fueron
`inspect_inventory_schema` (`result_count=40`) y `report_capability_gap`
(`result_count=1`), ambos `succeeded`, sin `failure_code` y con
`read_back_verified=true`. La respuesta visible declaró que el largo de eje no
está poblado en las fichas y se negó a inferirlo desde nombres ambiguos.

La prueba independiente `concilia ahora la cuenta bancaria de este mes`
produjo `clientRequestId=e6ee8f1c-dc65-4ba6-bec9-64c4fea7f204`, run
`d53ea661-8525-4a54-bf7f-15953595e59a`: `succeeded`, sin `error_code`, con un
receipt `report_capability_gap` verificado. La salida server-owned dijo que no
existe una herramienta autorizada para modificar Contabilidad y no afirmó
haber conciliado nada. Esto demuestra reconocimiento general de una capacidad
ausente fuera del caso de inventario.

La regresión real `buscame camaras 29 que tengamos en stock` produjo
`clientRequestId=07663b4f-6758-4289-86be-97fcb7d9be13`, run
`ab231a10-ade3-412a-9c84-77907d87eb37`: `succeeded`, sin `error_code`, con
receipts verificados de inspector (`result_count=6`) y búsqueda v5
(`result_count=5`). Abrió el listado server-owned de cinco cámaras con stock,
buscador manual vacío y la misma separación visible de una ficha técnica y
cuatro matches de identidad; la aro 26 no apareció.

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
- tarea pública natural independiente, con dominios preferidos y URLs HTTPS
  iniciales opcionales que no limitan otras fuentes;
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

El WebView interno no se entrega al modelo. La integración futura puede abrir el
resultado final en una pestaña ERP, pero no hereda el perfil del usuario.

## Checkpoints de implementación

### A — Continuidad y contrato

- [x] auditar línea base y WIP compartido;
- [x] crear este plan canónico;
- [x] registrar el runtime en los documentos owner correspondientes;
- [x] fijar dataset de 50 tareas y contrato de evaluación cerrado en
      `test/fixtures/ai_assistant_agent_eval_cases.json`, con validación
      automática de herramientas, outcomes, riesgo, navegación y cobertura
      adversarial;

### B — Resumen operativo existente

- [x] implementación y regresiones determinísticas;
- [x] revisión independiente y analyzer;
- [x] smoke Debug real: hoy, mañana, tarjetas, click explícito, persistencia e
      inyección de texto; el 4 de agosto pasó en dark mode, sin autonavegación
      al preguntar y con el workspace Dashboard/paneles restaurados byte por
      byte en la lectura semántica;
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
- [ ] completar el catálogo (9 de 13 lecturas ERP son ejecutables y la
      investigación pública completa 10 de 14 herramientas, condicional a su
      worker; inventario de riesgo, caja/cobranza, gastos y conversaciones están
      en el siguiente slice);
- [x] respuestas parciales y tarjetas por fuente para la primera ola;
- [x] ninguna lectura determinística o cacheada salta capacidades/tenant; un
      vacío sin receipt de autoridad se declara no disponible;
- [ ] benchmark inicial de 50 tareas reales en español coloquial.

### E — Gateway multi-modelo

- [x] Edge Function `ai-agent-gateway` con contrato v1 cerrado y neutral;
- [x] adaptadores locales Gemini y OpenAI Responses con replay exacto de
      artefactos en 3+ rondas, thinking/reasoning opcional y límite de
      continuación;
- [x] adaptador Anthropic Messages con replay exacto de thinking, firmas,
      bloques redactados y tool results; ya es seleccionable por routing server,
      pero ningún proveedor nuevo queda activado sin configuración productiva;
- [x] allowlists, errores sanitizados, routing por rol lógico, pricing exacto,
      cuota, cancelación, retry único y telemetría durable;
- [x] 95 tests Deno locales, type-check, formato y lint; smoke autenticado
      pendiente;
- [x] ninguna API key privada ni elección libre de proveedor llega a Flutter.

El gateway ya ejecuta tool calls en servidor y Flutter dispone de un engine
completo para consumirlo. La selección sigue apagada por defecto: no se activa
porque una respuesta textual dé 200, sino después de migraciones, exposición del
schema aislado, secrets, read-back y smoke de todas las herramientas anunciadas
para cada capacidad. Los adapters ya acumulan y vuelven a validar el stream
exacto de todas las rondas: Gemini admite firma en texto, sólo en una llamada o
thinking-off; OpenAI conserva items reasoning/function-call en orden
cronológico; Anthropic conserva sus bloques thinking/signature/redacted-thinking
junto con tool use y tool result. Los tres rechazan en la ronda de origen una
continuación que excedería el límite del decoder. La continuación privada de
cada proveedor vive sólo durante el request, ligada al mismo proveedor/modelo y
limitada a 128 KiB. No se guarda en DB, logs ni respuesta, y nunca se cambia de
proveedor una vez iniciado un tool loop.

El runtime Flutter sí registra eventos allowlisted en un buffer acotado de
memoria y usa una clave aleatoria por instancia para HMAC-SHA-256 de inputs y
outputs de baja entropía. Eso evita que un hash directo funcione como
diccionario de folios, nombres o montos, pero no reemplaza el store durable con
RLS, retención y correlación de runs del Checkpoint F.

La app activa todavía usa el boundary heredado `gemini-proxy`, no este gateway,
porque el flag de rollout permanece apagado. Ese proxy autentica, pero aún
permite `contents/system/tools/config` y modelo allowlisted desde el cliente,
carece de autoridad tenant/rol, cuota, body limit y deadline propios y usa CORS
amplio. Sus logs y errores visibles ya fueron saneados, pero reemplazarlo por el
gateway gobernado sigue bloqueado por los gates DB/productivos y por conservar
el resumen determinístico hoy/mañana; no es una tarea que pueda declararse
resuelta por tests locales.

Los logs preexistentes del contexto, toolbar y proxy heredado fueron saneados:
no imprimen scope, folios, UUID de usuario, body upstream ni detalles de
excepción.

Verificación local de esta ampliación: analyzer limpio en los archivos Flutter
tocados; 83/83 pruebas Deno, formato, type-check y lint limpios. El runner de
Flutter no pudo crear su socket loopback dentro del sandbox, por lo que las
pruebas nuevas y el smoke macOS siguen siendo un gate real, no un verde
inferido.

### F — Threads, runs y receipts

- [x] migración local con tablas FORCE RLS y cero DML directo para clientes o
      runtime;
- [x] repositorios y coordinador server-owned con idempotencia, cuotas,
      concurrencia, lease fencing, costo y recibos hash-only;
- [x] cancelación y recuperación por expiración de lease; la continuación
      privada de proveedor deliberadamente no se reanuda ni persiste;
- [x] TTL, eliminación de thread y purge acotado con schedule cuando `pg_cron`
      está disponible;
- [x] respuesta y cards terminales se leen desde el mismo commit durable;
- [ ] pgTAP/clone de producción, despliegue, schedule read-back y smoke
      autenticado.

### G — Borradores y escrituras gobernadas

- [ ] UI canónica de preview/aprobación liderada por Claude;
- [ ] herramientas `draft` y luego `reversibleWrite`;
- [x] contrato local de aprobación exacta, single-use, idempotencia, timeout y
      read-back; no hay executors de escritura activados;
- [ ] confirmación específica para todo `sensitiveWrite`;
- [ ] smokes rollback-only antes de cualquier activación productiva.

### H — Investigación pública con navegador

- [x] contrato server-owned de tarea pública natural con DLP, dominios
      preferidos y URLs HTTPS iniciales, sin límites temáticos;
- [x] Browser Use v3 aislado, efímero y sin sesión/perfil/workspace ERP;
- [x] HTTPS-only, redirects bloqueados, salida cerrada, límites de costo,
      tiempo, pasos y bytes, contenido web tratado como datos no confiables y
      stop al cancelar;
- [x] herramienta condicional: sin `BROWSER_USE_API_KEY` no se anuncia ni puede
      fingir una búsqueda web;
- [x] citas HTTPS visibles añadidas por el runtime desde fuentes validadas;
- [ ] smoke pagado real del worker y apertura opcional de la fuente en el ERP.

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

El dataset inicial ya fija 56 prompts sin datos personales reales y cubre
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

La secuencia operativa y las variables cerradas viven en
`docs/development/AI_ASSISTANT_GATEWAY_ROLLOUT.md`. El rollback del producto es
el flag OFF en una sesión nueva; no existe fallback silencioso por turno.
