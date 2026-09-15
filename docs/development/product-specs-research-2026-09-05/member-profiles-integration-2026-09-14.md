# Fichas por componente incluido

F2 sigue abierto. El trabajo reutiliza `spec_facts.subject_scope`, las fichas
existentes y el mismo validador por familia. No crea productos de inventario
para piezas incluidas ni convierte nombres en referencias OEM.

### Estado actual del editor y guardado — 14 de septiembre, 23:10 UTC

El guardado legacy tipado está **APPLIED** (`20260914222500`), verificado y
estampado a `22:40:31Z`, SHA
`a4c15f5273edb961dcf84d8112458bf9453ee325d036b1ad9b6d7969ae77ca44`.
Compara números exactos y filas canónicas sin reescribir observaciones
retiradas. Catorce casos pgTAP con rollback pasan; el paquete mantuvo los
ocho fingerprints de datos y la ACL. La revisión independiente está en
`legacy-typed-roundtrip-review-2026-09-14.md`. Un esquema histórico de filas
ya inválido frente al esquema actual sigue rechazándose; ese residual no
autoriza datos nuevos ni cambios legacy.

Las correcciones E1–E4/G1/R2/R4 del editor fueron revisadas por Claude en
el anexo 211 de `member-profile-editor-review-2026-09-14.md`. Confirmar sin
cambio no bloquea vincular; referencias de variante exigen MPN confirmado;
cambio de usuario o tenant limpia y bloquea el borrador con un aviso; piezas
repetidas muestran su ubicación. El recibo remonta los campos con el valor
confirmado. El historial muestra fecha y etiquetas por identidad de definición
cuando están disponibles; si la plantilla retirada ya no está cargada, dice
que la etiqueta no está disponible, sin inventarla ni mostrar una clave técnica.

La batería ampliada pasa **95 pruebas** (editor, borradores, decoder,
referencias, mensajes por pieza y autoridad), evidencia privada
`.tmp/product-spec-catalog/member-editor-final-tests-20260914.log`.
Analizador: cero errores/cero warnings, 24 infos previos del formulario y
contrato. R1 quedó **APPLIED** y estampado a `22:52:36Z` mediante
`20260914225500`, SHA
`93b9f3c3228e03a2957b6f5196ddf864500791ce53f6c737f27f961d96fb25e3`.
El error devuelve el detalle de la pieza y campo sin exponer el JSON como
mensaje. Cuatro casos SQL pasan, incluido rechazo sin alterar datos previos;
la revisión independiente 212 no dejó bloqueantes.

La app real conservó un cambio de ancho 2.20 → 2.21 en el borrador de una
cubierta al alternar pestañas, actualizar la ficha y reducir la ventana a
430 px. Tras descartarlo y reabrir el producto, el valor persistido seguía
siendo 2.20. Evidencia privada: `member-editor-compact-fields-20260914.png`
y `member-editor-persisted-value-unchanged-20260914.log` en
`.tmp/product-spec-catalog/`. No se guardó el cambio.

**Corrección R5:** los cinco llamadores reales de `ProductFormPage` fijan
`lockProductType: true`; el cambio Producto → Servicio no está expuesto en
esas rutas. La preservación defensiva fue revisada en código, pero no se
declara esa transición probada en runtime ni se desbloquea para simularla.
**Actualización 15-09, 01:10 UTC:** nueve colecciones ya están habilitadas por
`20260915004000`, con revisión 215 concluida, sello y verificación productiva.
Las lecturas autenticadas de sus 68 productos conservaron todos los datos.
En la app real AE0317 permitió crear en borrador la ficha independiente de un
soporte incluido, con sus campos propios. El formulario se cerró sin guardar;
la lectura posterior confirmó identidad, observaciones, referencias, historial
y estado activo intactos, y cero perfiles persistidos. Evidencia en
`.tmp/product-spec-catalog/member-enablement-live-20260915/`, frame
`member-support-desktop.png` y `ui-discard-readback.json`. F2 sigue abierto:
falta interacción embebida y la adjudicación de kits y conjuntos excluidos.
El 15-09 se comprobaron las etiquetas legibles y creación de ficha en compacto
430×940; el borrador se descartó y el read-back conservó todos los datos
(`family-labels-20260915/discard-readback.json`). No se activa ningún sucesor
original ni se realiza llenado con este paquete.

**Actualización 15-09, 02:29 UTC:** el kit de transmisión es la décima ficha
habilitada y el primer reemplazo adaptado de una familia original. Migración
`20260915023000`, seis productos releídos sin cambios y borrador AE0244
con ficha propia de Rodamiento descartado y verificado. El recorrido acredita
identidad y campos de la plantilla vigente, no las medidas del sucesor de
rodamientos pendiente. F2 conserva la interacción embebida y los otros conjuntos
como trabajo abierto. [Evidencia](drivetrain-kit-members-adjudication-2026-09-15.md).

La prueba SQL con includes de `scripts/inventory/sql` se ejecuta con
`scripts/db/query.sh local --write --file`: el runner `db/test.sh` invoca
un contenedor que no monta ese directorio. Su primer fallo fue de ruta,
sin ejecutar casos; no fue una regresión del escritor. Inspeccionar además
`not ok` en el resultado pgTAP: el proceso SQL puede salir 0 con aserciones
fallidas. Las pruebas finales arriba tienen todas las aserciones aprobadas.

## Consumidor de taller

La ruta general y la detallada de `drivetrain_kit` usaban el matcher de bielas:
un kit que sólo declaraba una cadena heredaba `1x · Mid / BMX` del contexto de
la bicicleta y pedía parte trasera. El cambio separa ambos despachos y conserva
cautela por la evaluación pendiente de las piezas realmente incluidas y sus
uniones. No elimina una incompatibilidad comprobada: la ruta anterior devolvía
una descripción y prioridad de bielas sin dueño válido.

Regresión RED antes del cambio: `.tmp/product-spec-catalog/kit-consumer-before-20260914.log`.
83 pruebas PASS: `.tmp/product-spec-catalog/kit-consumer-after-20260914.log`.
Analizador sin incidencias: `.tmp/product-spec-catalog/kit-consumer-analysis-20260914.log`.
Tras corregir la fixture al sobre publicado `schema_version/id/values/sources`,
regresión focal PASS: `.tmp/product-spec-catalog/kit-consumer-focused-20260914.log`.
El cambio no se ha verificado en runtime ni distribuido todavía.

Claude encontró además que la compuerta previa del consumidor ignoraba
`blocking`: un `required_missing` anulaba incluso una diferencia de maza
110/100 mm. Ambas regresiones se reprodujeron y se corrigieron. La compuerta
global y la de cadena usan el mismo criterio bloqueante; un pendiente conserva
las contradicciones conocidas y la explicación propia del kit. Una futura
coincidencia positiva con pendientes se mantiene en cautela.
85 pruebas PASS en `pending-consumer-after-20260914.log` y analizador sin
incidencias en `pending-consumer-analysis-20260914.log`, ambos bajo
`.tmp/product-spec-catalog/`. La sonda RED está en
`pending-consumer-before-20260914.log`.

## Persistencia en implementación

Preimagen productiva de funciones capturada el 14 de septiembre a las
19:37:59 UTC: cero hechos de producto con alcance no nulo. La nueva cabecera
debe identificar una fila de contenido de un producto y fijar su identidad,
plantilla y referencia exacta opcional. Los hechos siguen perteneciendo al
producto, acotados a un UUID de perfil: reutilizar el id textual de la fila
como alcance permitiría atribuir hechos anteriores a una pieza reemplazada.

Quitar o reclasificar la pieza exige archivar explícitamente el perfil previo,
conservando hechos y lecturas. La omisión en un cliente viejo conserva perfiles;
si su cambio deja uno huérfano, el guardado completo se rechaza. No hay borrado
automático ni enlace a otro producto por texto.

Precisión adjudicada con Claude: identificar un valor antes desconocido no es
cambiar una pieza. `binding_action: identify` admite completar esa identidad
con fuentes de la fila; no sustituir un valor conocido. `rebind` exige elegir
una fila concreta de igual identidad. Ambos conservan el UUID de perfil y sus
hechos, y el registro de eventos conserva antes/después y actor. Cambiar sólo
la edición OEM para la misma identidad revalida sin exigir archivo.

Un nivel de perfiles no excluye las tablas intrínsecas de la familia. Suprimir
todos los campos `contents` puede quitar datos usados por reglas de la propia
ficha. La revisión independiente de esta discrepancia y del consumidor está
asignada a Claude en el mensaje 195, sólo en su documento de revisión.

## Código y comprobaciones actuales

`compile_product_spec_member_profiles.py` parte de seis cuerpos productivos
fijados por hash en `sql/product_spec_member_profile_predecessors.json`. Deriva
el escritor y lectores con alcance y conserva los wrappers del producto raíz:
no hay otro validador de medidas/reglas. El núcleo nuevo está en
`scripts/inventory/sql/product_spec_member_profiles_core.sql`; la salida es
`product_spec_member_profiles_candidate.sql` en ese mismo directorio.

- Cabeceras de perfil y eventos propios del tenant; escrituras sólo agregadas.
- `save_product_with_specs_v2` incluye perfiles en la transacción y recibo;
  v1 mantiene su hash anterior y conserva perfiles omitidos.
- `get_product_spec_editor_context_v3` lee raíz y perfiles en una instantánea;
  los archivados van aparte y conservan payload exacto por definición.
- El lector de plantilla de miembro admite el borrador antes de crear producto,
  verificando la colección declarada por la plantilla padre.
- `get_product_spec_research_snapshot_v2` incluye perfiles, eventos y sus hashes;
  la lectura v1 de observaciones ya cubría todos los scopes.
- El archivo protege hechos, opciones y lecturas. Cambios de lectura del miembro
  avanzan la revisión del producto; la evidencia no se puede mudar de pieza.
- Una barrera interna por plantilla coordina metadatos/perfiles sin incrementar
  la versión de la ficha al editar un producto. Siete escenarios con dos
  conexiones verificaron publicación antes/después del componente, editor viejo,
  y snapshots repeatable-read anteriores al alta o cambio de hechos. La sonda
  `scripts/inventory/test_product_spec_member_concurrency.py` restaura cuerpos,
  ACLs y fixtures locales exactamente; la evidencia está en
  `.tmp/product-spec-member-concurrency/`.

59 casos locales del grafo pasaron con rollback, incluidos coordinación y
protección de lecturas, en
`.tmp/db/member-profiles-member-latest-20260914.log`. El test versionado carga
los candidatos dentro de su propia transacción para ejecutarse sin instalarlos.
55 regresiones del contrato v1 se repitieron después de esas extensiones y
pasaron en `.tmp/db/member-profiles-root-latest-20260914.log`.
Las fixtures de lectura activas/archivadas se exportaron de SQL sintético a
`test/fixtures/product_spec_member_profiles.json`; no contienen productos reales.

**Claude, mensaje 197, entrega recibida:** implementación de
`lib/modules/inventory/models/product_spec_member_profile.dart` y
`test/unit/product_spec_member_profile_test.dart`. No toca servicio, formulario,
SQL ni documentos globales. Root es dueño de la integración y del servidor.
Root recuperó la propiedad de ambos archivos. Corrigió el bloque sin producto
para conservar las colecciones de su plantilla y exigir la misma forma de seis
claves que el servidor. Agregó `ProductSpecMemberDrafts` y el lector de plantilla
de borrador: cambios de identidad/familia no reasignan hechos; identificar exige
fuentes; volver a vincular exige fila elegida; archivo y deshacer son locales
hasta el guardado conjunto. 46 pruebas Dart PASS en
`.tmp/product-spec-catalog/member-dart-integration-20260914.log`.

Los servicios tienen lectura v3 y despacho de escritura v2 por comando explícito,
incluidos juegos de stock. El formulario todavía usa v2/v1 hasta integrar el
editor y publicar el framework; agregar los métodos no constituye activación.
Claude entregó la revisión independiente del servidor en **mensaje 199**, en
`member-profile-server-review-2026-09-14.md`. Root reprodujo cinco fallos de las
guardas de categoría e historial en `member-profiles-review-before-20260914.log`
bajo `.tmp/db/`. La corrección agrega validación diferida y época por las
plantillas antigua/nueva de la asignación, conserva la revisión del editor ante
una reasignación compatible y rechaza actualizar/borrar eventos. La metadata
también exige las dos claves canónicas de identidad; se prueba sin perfiles
activos para que un fallo de vínculo no oculte la ausencia de esa regla.

**Diferencia local/productiva comprobada, 14 de septiembre 21:14 UTC:** la base
local tenía `spec_fact_readings.definition_id` y `vocabulary_digest` anulables y
carecía del trigger de fuente. Producción exige ambos valores y fuente
`name_reading`. El caso previo sobre un hecho `mechanic` no representaba una
lectura productiva válida. La fixture acotada
`supabase/tests/fixtures/product_spec_reading_receipt_contract.sql` instala esas
restricciones sólo dentro del rollback del test. El caso ahora identifica
campo/vocabulario y procedencia correcta. Es cobertura defensiva de evidencia:
el editor de componentes todavía no crea lecturas de nombre. Los contratos
leídos están en `.tmp/db/member-profile-reading-category-{local,production}-20260914.json`.
65 casos del grafo pasan con esas restricciones y rollback; 49 pruebas Dart
pasan tras comprobar IDs de opciones y claves de identidad.

El dueño autorizó volver a **Fable 5.1** y se verificó visualmente el cambio.
En **mensaje 201** Claude revisa sólo cliente y paquete de publicación en
`member-profile-client-publication-review-2026-09-14.md`, sin SQL ni ediciones de
implementación. Code y el chat se comprobaron antes de Send; se conserva la
suspensión de workflows/subagentes y la discrepancia de etiqueta documentada.

El mensaje 196 quedó visualmente en streaming aunque su documento y respuesta
ya estaban terminados. Tras más de 15 minutos sin cambios, Stop reconcilió el
estado y mostró el mensaje completo. Un setter del compositor tampoco se hizo
visible hasta elevar la ventana; se verificó el texto final y el mensaje 197
Running antes de continuar. No se reenviaron asignaciones duplicadas.
En esta ronda, pulsar la misma tarea en la barra lateral refrescó el AX y mostró
la entrega terminada del mensaje 197 sin detenerla; preferir ese refresco antes
de inferir un bloqueo por el estado visual de fondo.

La integración, activación, editor, consumidores, auditoría de asignaciones y
llenado siguen pendientes. Ningún producto fue rellenado en este trabajo.

## Compuerta de publicación del framework

Migración preparada `20260914213000_product_spec_member_profiles.sql`:
32 funciones, tres tablas y 12 disparadores. Añade infraestructura y no habilita
colecciones ni cambia fichas/productos existentes. H1, H2 y las claves canónicas
fueron revalidados por Claude en su revisión de servidor. Las lecturas v3 ahora
conservan `member_parent_context` cuando la categoría del borrador resuelve otra
raíz; el lector verifica producto, revisión y timestamp antes de usar ese dueño.
El recibo v2 incluye `editor_context` de la escritura confirmada, para reconstruir
el borrador y sus identidades/procedencia antes de permitir otra edición.
El servicio conserva ese acuse tanto en producto independiente como en juego.
Estos métodos todavía no están conectados al formulario.

68 casos pgTAP y 39 del decoder pasan; el último ensayo de 11 escenarios de
concurrencia también pasa y restaura exactamente funciones/ACL locales. La
publicación comprueba predecesores, funciones, tablas, disparadores y huellas
de diez tablas de datos en la misma transacción; espera por candados como máximo
5 s y limita la sentencia a 120 s. El ensayo local prueba aplicación y reintento
con rollback. El éxito local no sustituye el read-back productivo.

Respaldo legacy nuevo, ya verificado:
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260914T213727Z-pre-fill`.
Contiene 1.673 productos y su visor independiente; el respaldo previo se conserva.
Su SHA cifrado es `fde4bfa33aff42b47295874f9f64fec513e2249ea56816e8dde49003dd642827`.

La recuperación conservadora del framework restaura sólo los seis cuerpos
predecesores y retira acceso a las RPC nuevas, sin borrar tablas ni hechos ni
retroceder datos comerciales. El cuerpo preparado está en
`.tmp/product-spec-member-publication/recovery-functions.sql`; exige hashes
exactos y cero perfiles, scopes y habilitaciones. Se convertiría en una nueva
migración compensatoria antes de aplicarlo. Si ya se usó el framework, esa ruta
falla cerrada y se preserva la evidencia para una compensación específica.

**Publicación completada: 2026-09-14 21:43:18 UTC.** La migración figura
`APPLIED`, SHA `dbe9b55bd31b9eee2c083a0c008393d896a4be57b74c1590f4f28e3c0253f406`.
Funciones, tablas y disparadores coinciden exactamente con el manifiesto;
la huella de las diez tablas preexistentes se conservó. Cero perfiles, eventos,
hechos con scope y plantillas habilitadas en el read-back. Evidencia:
`.tmp/product-spec-member-publication/deployment.log` y
`.tmp/db/migration-receipts/20260914213000.receipt`.

Smoke autenticado con el actor real: dos productos (revisiones 0 y 3), paridad
de raíz v2/v3, bloque de componentes, snapshot de investigación v2, borrador
sin producto y rechazo 403 de producto no disponible; cero escrituras. Evidencia
en `.tmp/product-spec-member-publication/authenticated-smoke.log`. Salud ERP
sin fallos críticos; conserva la advertencia histórica de 16 existencias
negativas, fuera de este cambio. El escritor v2 se verificó con rollback local,
no mediante productos de prueba en producción.

Claude entregó C3 en el mensaje 203: el borrador sólo deriva campos activos,
rechaza referencias ajenas a su plantilla y compara las columnas de identidad
entre dueños. 54 pruebas Dart PASS; Root recuperó ambos archivos. Quedan por
resolver en el escritor compartido y la raíz el valor legacy numérico frente a
referencias y el transporte de identidad por definición; no se consideran
compatibilidad certificada por estar bloqueados al guardar.

**Ownership vigente, mensaje 205:** Claude/Fable 5.1 adapta sólo
`scripts/inventory/product_spec_legacy.py`, `product_spec_legacy_export.sql`,
`test/scripts/test_product_spec_legacy.py` y
`docs/runbooks/DATABASE_BACKUP_AND_RESTORE.md` al formato 2 con cabeceras y
eventos, conservando el formato 1 y separando miembros en el visor. Sin SQL,
llaves, respaldos reales ni runtime. Root integra el editor; no hay otro escritor.


## Editor y respaldo, siguiente comprobación del 14 de septiembre

La copia formato 2 fue creada y verificada realmente a las 22:00 UTC:
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260914T220049Z-pre-fill`,
SHA cifrado `717f574ebf4073ead9c1333bb4d8c4cceb5d9a7a7da9e4c8b3ee13cb62ab89fc`.
1.673 productos, 1.653 hechos, cero perfiles/eventos. El lector nuevo también
reabrió y verificó la copia formato 1 de las 21:37 UTC, sin modificarla.
17 pruebas sintéticas cubren el grafo y visor del respaldo; la exportación real
confirma el SQL y el descifrado, con recuperación local campo por campo.
Logs `member-backup-v{1-compat,2-tests,2-create}-20260914.log` en
`.tmp/product-spec-catalog/`. Ninguna restauración productiva.

El formulario usa v3 y ambos recibos v2 (producto y juego). Se conservan las
ediciones/archivos por producto, se rechaza un cambio de revisión sin bendecirlo,
y se reconstruye el borrador confirmado antes de sincronizar WhatsApp. Los
renderers originales reciben explícitamente plantilla, valores, referencia,
validador y callback de cada componente. No hay formularios por familia
reimplementados. 74 pruebas del editor/modelos/referencias pasan (incluidas
12 interacciones del nuevo widget); analyzer sin errores ni warnings en esos
cinco archivos, con 26 infos anteriores o de estilo. Quedan la revisión
independiente y sus correcciones antes de considerar cerrado el editor.

Claude consolidó `reference_scope` en el validador compartido y Root retiró la
emisión duplicada del draft. La igualdad legacy numérica/filas sigue siendo un
cambio del escritor: candidato separado `product_spec_legacy_roundtrip_candidate.sql`,
12 pruebas SQL que reproducen primero el fallo y luego verifican la corrección;
68 del grafo pasan con ese escritor. Ensayo completo de publicación/reintento y
read-back local con rollback PASS. Migración `20260914222500` preparada, todavía
**sin aplicar**. Sólo cambia el cuerpo del escritor; conserva hechos, fuentes,
lecturas, timestamps, contratos, perfiles y permisos.

La lectura productiva precisa el otro residual de identidad: referencias sólo
usan definiciones globales por `spec_reference_global_scope_internal_v1`, y la
clave global es única mediante `idx_spec_definitions_system_key`; hoy hay cero
campos de plantilla de tenant. El cruce por key no se presenta en las 105
plantillas actuales. Sigue pendiente para plantillas personalizadas que usen
una definición de tenant con la misma key: el servidor rechaza por UUID y el
cliente debe anticiparlo con identidad de definición. No retirar esa guardia.
Evidencia `.tmp/db/spec-reference-boundary-{production,local}.json`.

**Runtime real, sólo lectura:** se conservó `screen payroll`, PID 90499, y se
hizo hot reload (sin restart). Se abrió el editor desde Inventario para dos
productos: aceite Shimano S56467 muestra explícitamente «Sin ficha técnica»;
MAXXIS ALAMBRE 26X2.20 IKON, SKU 4717784040011, carga Neumático / Cubierta,
26 pulgadas, talón de alambre y ancho existente 2.20, con tubeless sin confirmar.
Capturas/árboles `.tmp/product-spec-catalog/member-editor-real-{fluid,tire}-spec-20260914.*`.
No se modificaron respuestas ni se guardó ningún producto. La falta de
asignación del fluido es un caso concreto para el saneamiento global; no se
asignó una ficha desde su categoría comercial mixta. La descripción comercial
contiene una declaración amplia de compatibilidad que debe contrastarse en la
investigación del SKU, sin promoverla a evidencia técnica. Estas lecturas no
prueban el editor de miembros en producción: aún no hay colecciones habilitadas.

**Ownership mensaje 209:** Claude revisa únicamente en
`member-profile-editor-review-2026-09-14.md`; no edita implementación. Formulario
SHA `9bda1f9ceecb395f1522629610b71ea555379cbf3af61142aa9c94165b6b6d36`, widget
SHA `1b6e306ea7fe23289bcd3bc2b1ce9680eb0b85a51153a749529844a792e99899` congelados
hasta su entrega. Root prepara la corrección SQL. No otros escritores.

**Actualización 15-09, 04:02 UTC:** además del kit, se publicó `component_set`
con ocho familias de piezas admitidas. Hay once plantillas con perfiles
habilitados. Dos conjuntos mixtos quedaron asignados con recibo y lectura
autenticada; sus hechos y perfiles siguen vacíos. El borrador real NNV71 abrió
la ficha de tornillería y se descartó sin cambios persistidos. Véase
[su cierre](component-set-adjudication-2026-09-15.md).
