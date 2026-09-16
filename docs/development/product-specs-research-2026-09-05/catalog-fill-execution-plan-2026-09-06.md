# Preparación del llenado completo del catálogo

Estado: cola inicial preparada el 2026-09-06; todavía no se aplicaron lotes de
relleno. El dueño encargó la investigación y el llenado a Codex y Claude. La
captura rutinaria no se devuelve al dueño. Continúa junto con la arquitectura
de todas las familias, no sólo con cadenas.

**Orden precisado por el dueño el 2026-09-06:** auditar todos los productos con
ficha y sin ficha, sanear asignaciones y campos de todas las familias, verificar
globalmente y después llenar. La cola por lotes organiza investigación y futura
ejecución; no habilita llenar una familia mientras el saneamiento global siga
abierto. El [estado comprobado y backup](global-audit-and-sanitation-2026-09-06.md)
es la referencia de continuidad; las cifras de esta cola son su fotografía inicial.

**Continuación 2026-09-07:** ya existe un
[snapshot y simulador autenticado](research-simulator-integration-2026-09-07.md)
con contrato de propuesta v2, evidencia archivada y detección de deriva. 2300
está aplicada/verificada. La primera simulación real de CL573R conserva los
seis efectos de referencia y el cambio propuesto de modelo, con cero problemas
de validación y cero escrituras. Su nueva preimagen requiere nueva revisión;
no hereda la aprobación del v1. Siguen pendientes el saneamiento global y el
aplicador autenticado de sólo ficha, con backup/recibos y preservación integral.

## Inventario comprobado

`catalog-fill-coverage.sql` y `catalog-fill-manifest.sql` leen exclusivamente
Viñabike mediante el wrapper guardado. Incluyen productos físicos inactivos;
los servicios conservan su contrato de trabajo separado.

| Medida | Todo el catálogo físico |
|---|---:|
| Productos / activos | 1.605 / 1.558 |
| Con marca / modelo / MPN estructurado | 1.292 / 12 / 0 |
| Con referencia documental vinculada | 0 |
| Con alguna observación técnica / observaciones totales | 461 / 1.653 |
| Sin familia técnica asignada | 742 |
| Sin categoría | 197 |
| Con imagen principal / código de barras / descripción | 1.313 / 10 / 36 |

La cola tiene **161 lotes de hasta 20 productos**, separados por familia o
categoría pendiente y estado activo. Los tres primeros contienen los nueve
conectores y las 31 cadenas. Siguen cassette, cambio trasero, mandos y pastillas;
la cola incluye también todas las demás familias y categorías. Cada fila
conserva ID, identidad actual, imagen, plantilla/versión, revisión del producto,
timestamp, valores actuales, procedencia de las observaciones y pistas del
proveedor. Incluye la biblioteca de once referencias y candidatas por marca y
familia; esas candidatas nunca se convierten en vínculos automáticos.

Reproducir sin escribir datos del ERP:

```bash
scripts/db/query.sh production --file docs/development/product-specs-research-2026-09-05/catalog-fill-coverage.sql --format json > .tmp/db/catalog-fill-coverage.json
scripts/db/query.sh production --file docs/development/product-specs-research-2026-09-05/catalog-fill-manifest.sql --format json > .tmp/db/catalog-fill-manifest.json
scripts/db/query.sh production --file docs/development/product-specs-research-2026-09-05/catalog-fill-references.sql --format json > .tmp/db/catalog-fill-references.json
python3 scripts/inventory/prepare_product_spec_research.py --manifest .tmp/db/catalog-fill-manifest.json --references .tmp/db/catalog-fill-references.json --output .tmp/product-spec-catalog/research-queue.json
```

Los datos de la cola son una fotografía para investigar. Antes de cualquier
aplicación se vuelven a leer revisión y timestamp. La cola no es un archivo
ejecutable de cambios y el preparador no tiene acceso a la base.

## Contrato de investigación por producto

1. Resolver familia funcional y marca/modelo con las señales existentes. Nombre,
   descripción, imágenes, códigos y documentación del proveedor son pistas;
   el extractor canónico distingue identidad de medidas y compatibilidad.
2. Buscar el modelo exacto en fuentes oficiales y comprobar variante, revisión,
   mercado y presentación. Sheldon/Park explican las relaciones y requisitos;
   la especificación del fabricante sostiene hechos concretos del modelo.
3. Escribir una propuesta por campo: valor actual y procedencia, valor propuesto,
   unidad y método, URL o evidencia archivada, página/sección, fecha, alcance y
   motivo. Citas breves cuando sean necesarias; conservar hechos sintetizados,
   no copias extensas de manuales. MPN, GTIN y SKU interno son campos distintos.
4. Separar referencia de modelo y presentación comercial. Vincular una edición
   con 114 eslabones exige resolver esa presentación; un nombre DISPLAY 116 no
   se convierte en 114 porque exista una página parecida. Una referencia de
   modelo sin presentación no llena cantidades, color ni variante.
5. Registrar declaraciones de compatibilidad como relaciones con condiciones y
   exclusiones, nunca como el producto cartesiano de marcas, velocidades y
   medidas. Toda compatibilidad, identidad vinculada, cantidad de envase y
   sustitución de un dato previo requiere revisión independiente del otro agente.
6. Sin prueba suficiente, conservar el dato actual y registrar exactamente qué
   falta. Primero agotar imágenes/documentos ya disponibles. Sólo una propiedad
   físicamente ilegible o que requiere medición puede quedar como captura de
   taller; esto no convierte el llenado ordinario en trabajo del dueño.

## Evaluación de la propuesta de Claude

La [propuesta independiente](catalog-fill-claude-plan-2026-09-06.md) aporta el
registro de fuentes por marca, lotes OEM, auditoría de inferencias, simulación
y recibos. Sus 1.558 productos y 706 sin plantilla se refieren sólo a activos;
son compatibles con los conteos globales anteriores. Se ajusta lo siguiente:

- Una marca importadora o pequeña puede publicar fichas; se comprueba por marca
  antes de declarar «sin documentación». No se adopta el 45 % sin OEM ni la
  previsión de 300–350 referencias como resultados demostrados.
- «Nescafé» es una anomalía para investigar, no un error confirmado por su nombre.
  No se corrigen marcas o categorías por intuición del agente.
- Distribuidor y texto de proveedor pueden sostener observaciones nominales
  atribuidas a esa fuente. No se elevan a aprobación OEM; tampoco se descartan
  como si no contuvieran información útil. Una imagen comercial no demuestra
  por sí sola la variante exacta que está en stock.
- Accesorios, ropa y herramientas **sí entran en el llenado**: talla, material,
  función, medidas e interfaces que correspondan. No se les inventa un sistema
  de transmisión ni se les exige compatibilidad mecánica irrelevante.
- Una fuente más reciente no resuelve automáticamente una contradicción: hay
  que igualar modelo, edición y ámbito. Se pueden completar hechos no disputados
  sin convertir el campo en conflicto en una afirmación.
- No se sobrescribe una observación previa sólo porque su procedencia sea
  `inferred`, `import` o `supplier_text`. Se conserva su evidencia y se propone
  explícitamente la corrección; el otro agente contrasta identidad y fuentes.
- El read-back de una aplicación debe comparar **todos los productos y campos
  tocados**, no una muestra. Una muestra sirve para ampliar una auditoría, no
  para demostrar que una escritura concreta conservó sus datos.

## Ejecución y guardado

Codex y Claude alternan investigación y revisión en archivos separados. Ningún
agente revisa como independiente su propia propuesta. El lote registra producto,
fuentes, cambios por campo, conflictos, veredicto del revisor y resultado. Los
campos que no corresponden a la plantilla se devuelven al diseño de esa familia;
no se esconden en un texto genérico para aparentar cobertura.

Antes del primer llenado productivo falta implementar y probar el simulador y
aplicador de propuestas. Debe reutilizar el contrato de guardado atómico con
autenticación/tenant, versión de plantilla, revisión y timestamp del producto y
clave de idempotencia por producto/lote. El payload conserva observaciones
independientes, lecturas, campos comerciales, stock y documentos. No reemplaza
fichas completas con un subconjunto investigado ni escribe tablas directamente.
Las referencias nuevas son ediciones inmutables, sembradas por migración
revisada; los vínculos y hechos se aplican como comandos del producto.

Cada lote tiene simulación, instantánea anterior, aplicación acotada, recibo y
comparación completa posterior. Un conflicto de revisión obliga a releer y
revisar la fila, sin reintentar ciegamente. Una corrección posterior es otro
comando trazable. Las reglas de compatibilidad deben pasar pruebas positivas,
negativas y desconocidas. Antes de habilitar cualquier lote se cierra además
el saneamiento global de asignaciones y familias presentes en el catálogo.

## Siguiente ejecución concreta

La revisión final de Claude identificó requisitos útiles y ya se incorporaron
valores actuales, proveedor y biblioteca documental en la cola. El esquema
común es `catalog-fill-proposal.schema.json`: identidad, referencia, valores
antes/después, procedencia, evidencia por campo, alcance, conflicto y revisión.
`catalog-fill-critical-fields.json` inicia la métrica de cadenas/conectores;
las demás familias se agregan al diseñarlas, sin tratarlas como cubiertas.
`catalog-fill-first-proposal-cl573r.json` es la primera propuesta revisada por
Claude, todavía sin aplicar: modelo, referencia de modelo y seis hechos
derivados, incluida la URL que guardará el servidor. Deja cantidad/MPN sin
rellenar. Se completaron los dos cambios exigidos por su revisión: lista
completa de hechos y evidencia OEM archivada con hash. El esquema, el hash de
revisión, el hash de evidencia y la igualdad con los seis hechos de la
referencia fueron comprobados.

Antes de aplicar se resolverán dos contratos adicionales:

**Resueltos en producción el 2026-09-16** por `20260916140000`
([registro](research-applier-publication-2026-09-16.md)): la restricción de
procedencia admite `research` (un efecto de referencia se guarda `catalog`, uno
de investigación `research`, nunca `mechanic`), y el aplicador corre como el actor
autenticado real que registró el comando, con recibo por aplicación. Nada
aplicado: sin readiness habilitada no escribe.

- **Procedencia de investigación:** el writer actual asigna `mechanic` a un
  hecho explícito y `catalog` al derivado de una referencia. Una observación de
  distribuidor o foto no debe hacerse pasar por medición del mecánico. El
  aplicador tendrá recibo de investigación, evidencias y procedencia propias;
  requiere extensión revisada del contrato. Hasta entonces sólo son aplicables
  las vías existentes cuya procedencia sea correcta: referencia `catalog` o
  lectura nominal con su recibo canónico. Ninguna se aplicó en esta preparación.
- **Actor autenticado:** usar una sesión real autorizada del ERP y registrar
  actor, agente investigador y revisor. No crear una cuenta ni inventar JWT o
  `auth.uid()` para simular que investigó un mecánico. Resolver el canal de
  ejecución como parte del aplicador, con el mismo control de tenant/revisión.

La evidencia por lote vive bajo `research/<lote>/evidence/`, con índice de URL,
fecha, página/región, método y hash cuando exista artefacto. Para PDFs grandes
se conserva URL/hash y extracción acotada; no se copian documentos completos ni
se transfieren imágenes fuera de los canales autorizados. La imagen del ERP se
identifica como tal, sin afirmar que es una foto tomada en la tienda. El snapshot
de entrada y la biblioteca llevan SHA-256; un ID secuencial de lote es sólo una
etiqueta, no una clave suficiente de aplicación/reintento.

Corrección a la expectativa final de Claude: las cinco referencias de cadena
no son todas de 114 eslabones; eGlide US documenta 126 y X11 US 118. La posibilidad
de vincular cada producto se resuelve contra su edición, no con una conclusión
global de «cero vínculos sin foto».

- Investigar las nueve filas de `research-001` y las 31 de `research-002/003`
  contra las referencias ya disponibles y las imágenes existentes; resolver
  primero CL573R, Z7 y presentaciones X8/Z8.3. HV408/HV410/K710 y Risk/ZTTO
  continúan como investigaciones propias, sin sustituirlos por modelos similares.
- Preparar registro de dominios/catálogos por marca y esquema de propuestas por
  campo; construir simulador/aplicador con pruebas de conservación y concurrencia.
- Abrir en paralelo de trabajo, con propietarios distintos, investigación de
  modelos Shimano y diseño de las familias mecánicas todavía no mapeadas.
- Medir identidad y variante resueltas, hechos críticos con evidencia, productos
  aplicados y verificados, conflictos y lagunas por causa. «Todos los campos
  llenos» no es una medida de corrección ni el criterio de cierre.
