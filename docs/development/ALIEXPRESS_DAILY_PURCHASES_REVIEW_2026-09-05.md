# Compras del día de AliExpress: observación del recorrido

Fecha de prueba: 2026-09-05. Compra seleccionada: **2026-08-12**.
Fuente: `c83fe9a349e0cac23f59eb10c93ec64c4eeb783e`, sesión macOS Debug
canónica `payroll`, tema claro y zoom de aplicación 80 %.

## Alcance y punto de parada

El dueño pidió recorrer la función, enviarla al flujo OCR, observar posibles
mejoras y detenerse en **Revisión de productos de la factura**. La pantalla
queda abierta en el espacio `Factura AliExpress · 2026-08-12`.
El dueño inició sesión en AliExpress durante el recorrido. No se confirmó
ninguna decisión de producto, no se pulsó Guardar plantilla y no se guardó
una nueva factura. Esto no es una certificación del guardado posterior.

## Resultado observado

- El calendario marcó el 12 de agosto como **Compra ya facturada**; el diálogo
  también informó que existe una factura para ese día.
- `Preparar factura` reunió **7 pedidos / 7 líneas**, generó el PDF y abrió
  `Factura leída`. Entre el primer registro de API y el PDF hubo **28,0 s**;
  esta medición excluye navegación e inicio de sesión.
- El renderer canónico produjo 333.188 bytes. La pantalla identificó la entrada
  como **Archivo estructurado**: el flujo aprovecha los datos extraídos de
  AliExpress, no acredita una segunda lectura remota por OCR del PDF.
- Se mostraron proveedor AliExpress, número `AE120826`, fecha 12/8/2026 y
  **$157.898 CLP**. Suma de líneas y total final coincidieron.
- `Revisar 7 productos` abrió el espacio de conciliación. Su análisis automático
  recuperó cinco resoluciones anteriores, incluyendo packs y descomposición;
  al detener la interacción quedaron **5 listas / 2 por decidir** y el botón
  final deshabilitado. En ese primer punto de parada no se abrieron candidatos.
  La ampliación de abajo registra la inspección posterior solicitada por el
  dueño; tampoco confirma la exactitud ni aplica ninguna propuesta.

## Hallazgos y mejoras propuestas

1. **Mostrar la diferencia del desglose, además del total final.** El registro
   `invoice.combined` informó `componentDifference: 2376`, mientras la tabla
   mostró `Diferencia $0` porque sus líneas ya recibieron el reparto del total
   de pedidos. Son comprobaciones distintas. Conviene mostrar los avisos del
   origen y un desglose por pedido antes de dar por conciliada la importación.
   Esto no demuestra que $157.898 esté equivocado; el desglose exige revisión.

2. **Corregir o verificar la lectura de envío y fecha del detalle.** Tres
   pedidos tuvieron `shipping: null` y advertencia de envío ilegible aunque el
   fragmento del detalle incluía `Free shipping`. El envío explícitamente
   gratuito debería distinguirse del dato ausente. Los siete detalles también
   devolvieron fechas del 26–29 de agosto; el merge conservó correctamente el
   12 de agosto del listado. Hay que verificar qué fecha captura el selector
   del detalle, especialmente para la importación de un pedido individual.

3. **Resolver el desbordamiento en Factura leída.** La captura real muestra el
   indicador de overflow de Flutter junto a `Costo unit. factura`; el extremo
   derecho deja cortado `Estado`. Revisar anchos, encabezados y descubribilidad
   del desplazamiento horizontal con la ventana y zoom del dueño.

4. **Alinear validaciones con la decisión de cada fila.** En conciliación,
   cinco filas aparecen listas con reglas recordadas, pero siguen mostrando
   `Categoría: Elegir`, `Sin marca` y el error rojo de familia faltante. Esto
   mezcla los requisitos de crear un producto con la presentación de un
   vínculo existente y ocupa gran parte de la altura. Mostrar los datos del
   producto vinculado y reservar los errores de creación para esa decisión;
   contrastarlo con las reglas efectivas antes de cambiar validaciones.

5. **Dar una salida útil al aviso de compra ya facturada.** El aviso funciona,
   pero no identifica ni abre la factura existente. Añadir esa acción y
   distinguir `Volver a revisar con OCR` de la preparación inicial haría más
   claro el resultado de continuar. El recorrido actual sí declara que no
   guardará ni creará productos hasta confirmar.

6. **Hacer más explícito el avance.** El primer estado observado fue el modal
   `Preparando factura AliExpress / Abriendo tus pedidos...`, sin acción de
   cancelación expuesta en esa lectura. Un resumen del progreso por pedido y
   una cancelación segura serían útiles. No se concluye que falten contadores
   en todos los estados intermedios: la extracción terminó entre lecturas.

## Evidencia local

- `.tmp/aliexpress-aug12-request.png`: fecha y aviso de factura existente.
- `.tmp/aliexpress-aug12-read-invoice.png`: datos importados, tabla y overflow.
- `.tmp/aliexpress-aug12-product-review.png`: entrada en conciliación.
- `.tmp/aliexpress-aug12-review/product-review-stopped.txt`: estado al detenerse.
- `.tmp/aliexpress-aug12-review/extraction-summary.json`: fases y desglose
  acotado, sin credenciales ni direcciones personales.

No se modificó la implementación. Los puntos anteriores quedan como trabajo
propuesto; no deben presentarse como correcciones ya aplicadas.

## Ampliación: composición de la revisión y calidad de las propuestas

El dueño pidió evaluar un rediseño desde cero, con atención a comparación,
packs, sets y posiciones físicas. Se abrió el selector de alternativas de la
primera línea, se cerró sin seleccionar y se verificó la revisión a 430 puntos
de ancho en la misma sesión macOS. Se restauró la ventana a 1274 × 861 y quedó
abierta la revisión, con las mismas dos decisiones pendientes. La comprobación
compacta no sustituye una prueba en Android con teclado y gestos.

### Problemas observados

- **La decisión queda después de la edición.** SKU, nombre, categoría, marca,
  costo, precio y venta compiten con la comparación. En ancho de teléfono,
  estos campos consumen casi toda la primera pantalla y la acción de vincular
  exige desplazarse. La causa está en `_CompactLineEditor`, que presenta la
  ficha completa por línea y apila sus pares de campos bajo 460 puntos.
- **La información no tiene un orden de lectura útil.** El título original se
  corta, se repite como nombre editable y la cantidad resultante de un pack
  queda dentro de texto de decisión. La fila no permite comparar rápidamente
  artículo comprado, variante elegida, identidad de catálogo y unidades finales.
- **El selector mezcla evidencia y acciones de diferente significado.** La
  maza Novatec muestra 3 candidatos viables y 37 descartados en la misma lista.
  Un candidato descartado por 32H frente a 36H y fabricante distinto ofrece
  el mismo botón `Es este`. El selector devuelve ambos mediante
  `OcrCandidateLink`; esta inspección no ejercitó validaciones posteriores.
  Si se permite una corrección manual, debe exponerse como tal y explicar el
  conflicto, separada de la recomendación ordinaria.
- **La explicación cambia entre superficies.** La fila llama a la maza
  `Muy parecido` y el selector `Casi seguro`. También expone claves internas
  como `object, function, shape, model, spec, manufacturer, image, name`.
  Hace falta una explicación compartida en lenguaje del operador y diferencias
  de identidad visibles, no una acumulación de etiquetas y razones técnicas.

### Lo que demuestra esta compra sobre la lógica

- Cinco filas recuperaron resoluciones anteriores de la variante de proveedor:
  3 juegos de pinzas → 3 delanteras + 3 traseras; 5 paquetes de discos → 10
  unidades de catálogo; 2 mangueras → 2 unidades; 2 paquetes de 4 pares de
  pastillas → 8 unidades de catálogo; 1 paquete de olivas → 10 unidades.
  Es recuperación de decisiones previas, no cinco aciertos nuevos de IA.
- Solo dos líneas recibieron investigación y adjudicación nuevas. La maza
  D042SB se propuso como AE0062. El par de manetas genéricas se propuso como
  2 unidades de AE0319 por compra, 4 en total. Esta última propuesta requiere
  contrastar identidad, unidad vendida y si procede conservar izquierda/derecha;
  no se certifica ni se descarta por el título genérico solamente.
- Los tiempos registrados de las dos llamadas por línea sumaron aproximadamente
  45 y 52 segundos. Son tiempos del proveedor, no una medición de todo el flujo.
  Abrir alternativas reutiliza la decisión existente y no vuelve a llamar IA.
- El código contempla componentes delanteros/traseros e izquierdos/derechos,
  packs homogéneos y reconocimiento de sets canónicos. Se inspeccionaron tests
  de pares ambiguos que quedan pendientes, roles separados, normalización de
  cantidad total a cantidad por compra y conservación de reparto. No se
  ejecutaron tests nuevos en esta ampliación de observación.
- La propuesta reparte costo según costo de catálogo × cantidad; si todos
  carecen de costo usa cantidades. Conservar el total es necesario, pero ese
  reparto es una política estimada que la revisión debería explicar y permitir
  revisar, no presentarla como un desglose leído del proveedor.
- El corpus local de identidad desactiva lectura visual y adjudicación. Sus
  resultados no miden por sí solos la precisión del modelo real. Hace falta
  evaluar compras inéditas y separar acierto de identidad, composición,
  multiplicador, rol, unidad de inventario y abstención correcta.

### Propuesta inicial del agente (revisada por el dueño más abajo)

Mantener una vista de lote con comprado, destino en inventario, cantidad final,
costo y estado; permitir comparar y resolver cualquier fila sin imponer un
asistente secuencial. Las filas resueltas muestran un resumen verificable y una
acción de cambio. La ficha editable aparece cuando se decide crear un producto.

La comparación debe enfrentar la variante comprada con los candidatos usando
los mismos atributos, fotografías legibles y diferencias explícitas. Presentar
primero candidatos viables; dejar descartados y diagnóstico bajo una acción
secundaria. Cada decisión debe conservar un vocabulario único entre fila,
selector y resumen final.

La descomposición necesita una representación estructurada de tres cantidades:
`3 juegos comprados × (1 delantero + 1 trasero) = 3 delanteros + 3 traseros`.
Mostrar unidad de catálogo y costo asignado por componente; distinguir pares
de piezas sueltas y el set que ya existe como producto. En teléfono, mantener
un resumen compacto del lote y abrir el detalle pertinente conservando contexto
y posición, sin repetir todos los campos de escritorio en cada artículo.

Evidencia adicional: `.tmp/aliexpress-aug12-candidates-desktop.png`,
`.tmp/aliexpress-aug12-review-mobile.png` y
`.tmp/aliexpress-aug12-review/identity-trace-events.json`.

## Refactor autorizado: implementación 2026-09-05

El dueño autorizó comenzar el refactor después de la evaluación. Se reemplazó
la composición de fichas repetidas por el lote comparativo y detalle contextual,
se unificaron los estados de evidencia y se proyectó la composición tipada en
ambas superficies. Las reglas del matcher, la adjudicación y las escrituras
contables no se reemplazaron. La presencia de estos cambios no acredita una
mejora de precisión de IA sobre compras inéditas.

Se reutilizó la guía canónica guardada por DesignSync en
`c430e08f-36b4-4cf0-b14b-322c1787f4cd/tool-results/bkyc7j0gj.txt`, conforme al
fallback documentado en `DESIGN_HANDOFF_SYNC_CONTRACT.md`. Componentes y
geometría de referencia: T-01/T-03, A-01, I-01/S-06, E-01 y F-03/F-04/F-06;
colores derivados del tema. No se solicitó colaboración de Claude ni se
estimaron valores desde capturas.

La primera ronda verificó lote, comparación, regla recordada, detalle de
composición y creación sin confirmar en la sesión macOS. Sus 119 pruebas
focalizadas y dos pruebas Android con teclado real pasaron antes del ajuste
de UX que se describe a continuación; no acreditan por sí solas ese ajuste. Se
conservó la compra y no se ejecutaron vínculos, reservas, confirmaciones de
reglas, creación de productos ni guardado de factura durante esta prueba.
El emulador Android ejecuta una fixture aislada de los widgets compartidos con
IME real; no sustituye una importación AliExpress completa en Android.


## Corrección del objetivo y del flujo por el dueño, 2026-09-05

El refactor inicial despejó la tabla pero dio prioridad a aceptar coincidencias
y convirtió la creación asistida en una ruta secundaria poco clara. Esa fue una
decisión del agente, no un requisito del dueño. Compras del día existe para
reducir el ingreso manual de pedidos, preparar los productos que faltan y
conservar cantidades y costos hasta la factura y recepción. El dueño pidió
priorizar UX/lógica, conservar esa asistencia y guiar mediante el proceso y los
controles, evitando sobreexplicaciones y más rondas de comprobación visual.

La implementación introduce reglas pendientes de aceptación, cambio de
decisión local, preparación asistida sin creación inmediata y unidad de catálogo
explícita. El contenido se puede ajustar con SKUs, cantidades y roles; una
selección de componente ya no aplana un pack. Las correcciones de reglas usan
revisión previa y clave idempotente según el contenido confirmado. El modelo no
decide disponibilidad de propuestas mediante su confianza autodeclarada. Se
corrigió también el reconocimiento de sets con roles invertidos y el reparto
casi nulo que recibía un componente sin costo cuando el otro sí lo tenía.

La verificación de esta ronda pasó 86 pruebas de decisiones, multiplicadores,
preservación del origen, costo total, roles, recibos y concurrencia del escritor,
y una interacción del selector que añade un componente, modifica sus unidades
y devuelve contenido para revisar sin vincular toda la línea. El análisis de
los archivos modificados no encontró incidencias y `git diff --check` pasó.
Se comprobó una regresión introduciendo temporalmente el antiguo umbral de
confianza: la prueba rechazó esa versión y volvió a pasar al restaurar los
bytes originales. Evidencia: `.tmp/ocr-ux-logic-tests-verified.txt`,
`.tmp/ocr-ux-composition-interaction-final.txt`,
`.tmp/ocr-ux-logic-analyze-final.txt` y `.tmp/ocr-ux-logic-mutation.txt`.

La sesión canónica `payroll` aplicó un hot reload de 142 bibliotecas en 12,635 ms
sin reiniciar el borrador OCR. No aparecieron errores de compilación ni
excepciones en el tramo del log de esa recarga. Evidencia:
`.tmp/ocr-ux-debug-reload-final.txt`. No se repitió una matriz visual ni se
guardó o recibió la factura AE120826; tampoco se crearon productos ni se
confirmaron reglas en producción durante esta verificación.

La precisión de IA sobre compras inéditas sigue sin certificarse. El editor de
contenido permite combinar productos existentes; la ficha nueva prepara un
producto completo o unidades homogéneas. La creación atómica de varios SKUs
nuevos distintos desde una sola línea fuente no forma parte de esta ronda.

## Comparación bloqueada después del refactor, 2026-09-05

El dueño detectó cinco filas con `Regla por revisar` y `Comparando…` permanente.
El estado real conservaba sus recibos de proveedor y todos los indicadores de
trabajo estaban en falso; el antiguo `markSupplierResolution` no cerraba el
estado `searching`. La nueva revisión explícita dejó de ocultarlo mediante el
estado vinculado. La recarga anterior compiló, pero no se comprobó esa
transición con el borrador ya abierto y el dueño quedó esperando trabajo que
había terminado.

La proyección ahora reconoce el recibo terminado sin ignorar operaciones aún
activas; la transición de resolución también cierra el estado de búsqueda.
El contador del bloqueo incluye reglas todavía sin aceptar. Evidencia del
estado previo: `.tmp/ocr-stuck-comparing-state-before.json` y
`.tmp/ocr-stuck-comparing-before.txt`. La regresión de política se comprobó
fallando con la condición anterior y pasando con la corrección restaurada:
`.tmp/ocr-stuck-comparing-regression.txt`.

Pasaron 7 pruebas de política y 34 de integración del contrato OCR; análisis
focalizado y `git diff --check` limpios. Tras una sola recarga de la sesión
`payroll`, la semántica de la compra original mostró cero `Comparando…` y cinco
botones `Revisar regla` habilitados. Se abrió el de BUCKLOS y se comprobó el
detalle con `Usar en esta compra` habilitado, sin pulsar la confirmación.
Evidencia: `.tmp/ocr-stuck-comparing-after.txt`,
`.tmp/ocr-stuck-comparing-review-open.txt` y el frame real
`.tmp/ocr-stuck-comparing-after.png`. Se conservó el borrador y no se repitió OCR
ni análisis de IA.


## Identidad primero y creación masiva visible, 2026-09-05

Esta corrección sustituye la ficha desplegable por fila y el bloque de acciones
`Por decidir / Comparar / Preparar nuevo`. El origen OCR y el primer candidato
real del inventario tienen columnas separadas. La ficha canónica se abre por
primary key; las otras coincidencias excluyen el producto que ya se muestra.
Seleccionar existente o marcar nuevo son decisiones locales, sin aplicar reglas,
reservar SKU ni crear registros. Los controles usan vocabulario profesional.

Después de identificar el lote, los existentes revisan cantidades y costos;
la acción del lote confirma los valores válidos sin exigir confirmación repetida
por fila. Las reglas sólo se ofrecen para la identidad elegida. El editor y su
confirmación usan los importes y cantidades revisados, no los valores antiguos
anteriores a la edición. Una composición que excluye el producto elegido muestra
un error y no se guarda. El total incluye los descuentos y no se descuenta dos
veces; el grafo se expande una sola vez en el kernel de recepción.

Los productos nuevos forman un paso de creación masiva con campos visibles y
alineados: nombre/SKU, categoría, marca, unidades por compra, costo y precio. En
compacto se agrupan sin expansiones por fila y conservan sus controladores. La
asistencia de origen/IA sigue preparando campos y respeta las ediciones. Crear
confirma el lote y reserva cada SKU con su identidad idempotente. Un producto ya
creado con conciliación pendiente permanece visible, no se puede volver a crear
y reintenta únicamente la conciliación.

Pasaron 112 pruebas focalizadas de lógica, unidades, reglas, selección,
comparación, edición masiva, recomposición y retorno. La nueva barrera de identidad
falló al desactivarla temporalmente y pasó al restaurarla. El análisis de los
archivos modificados no encontró incidencias. Evidencia:
`.tmp/ocr-three-step-verified-tests.txt`,
`.tmp/ocr-three-step-guard-regression.txt`,
`.tmp/ocr-three-step-complete-analyze.txt`; la verificación final del propietario
de importes/reglas queda en `.tmp/ocr-three-step-final-guard-tests.txt` y
`.tmp/ocr-three-step-final-guard-analyze.txt`.

Se reutilizó la sesión `payroll` mediante hot reload, sin repetir OCR o matcher.
La lectura inicial de esta verificación ya tenía seis identidades existentes y
una nueva elegidas en el borrador. Se conservaron; no se restablecieron a partir
de notas anteriores. Se comprobó el paso de cantidades y la tabla de identidad,
y se abrió la ficha real del rotor AE0212. Evidencia:
`.tmp/ocr-three-step-identify-live.txt`,
`.tmp/ocr-three-step-identities-verified.png`,
`.tmp/ocr-three-step-product-open.txt` y `.tmp/ocr-three-step-final-runtime.txt`.
Las pruebas de campos nuevos/compacto ejercitan widgets reales aislados; no se
repitió una importación completa en Android. No se crearon productos, guardaron
reglas ni guardó/recibió la factura mediante la automatización de esta ronda.
La precisión del matcher sobre compras inéditas permanece sin certificar.
