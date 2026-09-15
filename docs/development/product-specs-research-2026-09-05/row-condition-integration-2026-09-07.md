# Condiciones dentro de cada configuración

Motor aplicado y verificado, 2026-09-07. Los checkpoints locales de abajo conservan la evidencia anterior al despliegue. 0200 enlaza filas por ID, pero una
condición de ficha no expresa aún «esta fila necesita un modelo de adaptador
si declara que lo requiere». Se añade un bloque de contrato por plantilla,
`row_conditions`, versión 1, con mapas `allowed_when`, `required_when` y
`allowed_options` para columnas de cada campo de filas. El esquema reusable
conserva tipos, unidades e IDs; la plantilla determina el contexto de uso.

Las expresiones reutilizan exactamente el lenguaje de condiciones v2, pero
sus operandos pertenecen exclusivamente a la misma fila. Se validan columna,
tipo, opciones y ausencia de ciclos antes de publicar metadata. No se cruzan
filas ni se toma una columna de otro miembro para satisfacer el requisito.
Una opción explícitamente contradictoria bloquea guardar; información
ausente mantiene un pendiente no bloqueante. Ninguno de estos resultados
certifica por sí mismo una compatibilidad OEM.

La escritura, la validación Dart y el editor deben usar el mismo contrato.
Cambiar el dato inicial conserva el valor dependiente para corregirlo y
muestra el conflicto: nunca borra silenciosamente una observación. Las
columnas no aplicables vacías se omiten; una columna con dato conservado
continúa visible. El retiro de un vínculo o la etiqueta del miembro no
redirecciona ninguna fila.

No se publica sobre hechos o referencias existentes sin diagnóstico y
migración explícita. Quedan fuera de este bloque los recuentos/completitud
de conjuntos, comparaciones entre fila y escalar y la evaluación mecánica
por contraparte. Se verificarán por separado antes del llenado global.

## Revisión del editor y paridad (2026-09-07)

El revisor independiente reprodujo tres defectos del editor: el texto seguía
visible al retirar un valor pendiente, el token abierto ignoraba las opciones
de plantilla y el selector de referencia ofrecía destinos fuera del alcance.
Se corrigieron con sincronización de valor externo sin reiniciar el cursor en
cada pulsación e intersección de las opciones. Pasan 65 pruebas combinadas
(35 motor, 14 límites independientes, 16 widget en 390/768/1280 y claro/oscuro).
El análisis tiene cero errores/advertencias y 31 avisos informativos existentes
en los archivos de formulario/servicio. Todavía no se recargó esta parte en
la sesión nativa al escribir el checkpoint.

La regresión de todas las plantillas descubrió ocho diferencias de código de
diagnóstico, sin diferencias de rechazo: Dart llamaba `prerequisite` a un valor
conocidamente inaplicable y SQL `field_applicability`. Dart adopta el segundo
para el rechazo conocido; el requisito desconocido conserva su código y estado
pendiente. Pasan 241 pruebas de catálogo y contrato tras ese ajuste.

## Carrera de publicación reproducida, todavía sin desplegar

La prueba local con dos conexiones y constraints IMMEDIATE encontró que una
referencia y un producto nuevo podían guardar una fila bajo el contrato previo
mientras otra transacción publicaba una condición sobre un campo aparentemente
vacío. Ambas transacciones commiteaban y la ficha resultaba contradictoria. El
producto ya existente sí quedó bloqueado en ese intercalado; no se extrapoló
esa protección al alta. Evidencia anterior al candidato:
`.tmp/db/spec-row-conditions-concurrency-expanded-before.log`.

La corrección preparada toma SHARE de la plantilla antes de leer/comprobar su
versión en el agregado. La publicación toma UPDATE de las definiciones endpoint
en orden estable, espera los writers que ya tienen SHARE y sólo después lee
población en otra sentencia. Así también incluye las referencias, que no pasan
por el agregado. La prueba posterior y el despliegue están pendientes. Una
edición concurrente de definición puede adquirir locks en el orden opuesto y
terminar en deadlock con rollback; no debe reintentarse ciegamente.

El probe es local con fixtures c0bf, nunca una mutación de producción. Su
limpieza debe retirar hechos polimórficos antes del producto y suspender sólo
el trigger inmutable de esa referencia bajo lock/transacción para retirar la
referencia sintética. Dos fallos del cleanup inicial se identificaron como
fallos del propio ensayo, sin alterar productos reales ni relajar guards de
producción.

## Cierre productivo del motor 2200

Aplicado/verificado `2026-09-07T11:22:41Z`. Migración SHA
`6d18c2e1e985d73ca935987a5615bf6365e8a32e26720a5068e78bbb878f16a7`;
verificador SHA `2f71f70f7c904edb0b7a9765898fa49b6a022fbfccb633e29dc5dfe25a2e3acc`.
Receipt `.tmp/db/migration-receipts/20260907022000.receipt`. El verificador
falló antes por las definiciones aún ausentes/anteriores y pasó tras aplicar:
siete funciones exactas, propietarios, ACL, security/volatility/search_path y
18 casos compartidos de lectura pura. Historia productiva registrada. El
verificador de preservación confirmó hechos, lecturas, recibos, plantillas,
opciones, vínculos e identidad; ninguna configuración de producto fue escrita.

- 767 pruebas SQL, 17 archivos, en la regresión completa (`spec-row-conditions-full-pgtap.log`).
- 101 SQL de condiciones (75 root y 26 independientes), incluidos rechazo y
  preservación de hechos/revisión, metadata inválida y formato inválido con un
  único diagnóstico aunque una fila tenga enlaces y condiciones.
- 385 pruebas Dart de condiciones/editor, catálogo integrado, frenos y consumidor.
- Análisis completo `lib test`: cero errores, 27 warnings de archivos ajenos a
  este cambio y 486 avisos informativos. Archivos editados: cero errores y
  warnings, 31 avisos informativos. No se limpiaron cambios ajenos.
- Concurrencia: P/N/R se bloquean cuando publica primero; en el orden inverso
  se observó espera real de lock y rechazo 23514 tras el commit del writer.
  Regresión reproducible local: `python3 scripts/inventory/test_product_spec_publication_concurrency.py`.
  Crea dblink sólo si falta, retira sólo sus fixtures y restaura la extensión
  al estado anterior. Ambas direcciones tienen aserción ejecutable.
- Lectura con sesión real: 1.664 productos por el consumidor tipado, 38 por el
  editor, 35 familias de referencias y 17 números exactos; cero errores.
  Artefactos `authenticated-row-conditions-*-verification.json`.
- Recarga de la sesión canónica: 143/5383 bibliotecas, 6,498 s. Frame
  `runtime-row-conditions-baseline.png` inspeccionado; la medida manual 7.1,
  6/7/8 y 11/128 se conservan en el borrador. No se guardó el producto. Los
  nuevos campos aún no están publicados: este frame prueba continuidad de la
  base, no prueba runtime de esos campos en todas las superficies.

La revisión independiente de este forward está congelada en
`row-conditions-independent-review-2026-09-07.md`, SHA
`fd6ad0b211544b71155ca8a86842c19cafc01894cc17a593572c7b8b0de4ba2f`.
No quedan defectos reproducidos abiertos dentro del alcance del motor 2200.
Los demás contratos mecánicos, asignaciones globales, consumidores y
simulador/aplicador de llenado continúan abiertos. Catálogo ampliado sin
publicar y llenado cero.

## Aplicación local a todas las configuraciones

La revisión de los 48 campos y sus 94 usos produjo 14 cambios aceptados por
root: 26 requisitos condicionales y una restricción de opciones. Doce campos
reciben condiciones; 18 no necesitan una condición local adicional y 18
conservan carencias explícitas de identidad, relaciones entre filas, presencia
mínima o alcance del dato. Las 14 decisiones son de representación, no
aprobaciones mecánicas.

`compile_product_spec_condition_addendum.py` conserva la base mecánica f317 y
produce `all-family-row-conditions-integrated-2026-09-07.json`, SHA
`c12204e42f86423fc3bf3eba345a9f07568b4849d9c8d9b8ace4d44430ddcf9a`.
Las 105 plantillas, 681 definiciones, 48 tablas y 1.186 usos no cambian de
cantidad. Los 132 casos tienen SHA
`19d8e97f2fcebabf35e1fccb71c71ca66b25b001f57ca371d3e2bb5cccd5d129`.
SQL en rollback pasa los 132 casos, las guardias diferidas y la preservación;
Dart pasa 241 comprobaciones (plantillas, casos y metadatos negativos).

Se conserva el bloqueo central `row_shape` de un rango invertido. El ayudante
Dart de condiciones delega ese diagnóstico al validador de forma, mientras
el ayudante SQL también lo devuelve. El trial compara ese diagnóstico en el
resultado central y sólo los diagnósticos propios de condiciones en el
segundo comparador; no cambió el motor para acomodar la prueba.

Una expectativa anterior cambia explícitamente: una unidad física de luz no
entra en `kit_members`; corresponde a `light_member_configurations`. Esto no
resuelve por sí solo la identidad física de dos filas ni la composición total.
