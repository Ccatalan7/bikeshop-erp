# Maneta: pieza física y requisitos según construcción

**Publicado y verificado 05:41:48 UTC**, migración `20260915054000`, SHA
`ded86efb78dbdbdf5a4b470af9f4adb18f6c809d4fbb455142ffb86bc6ea7ce1`.
Se revisó `brake_lever`, ID
`dee33c12-b165-48ea-ac1a-7a10b0144d1a`, revisión 2→28, con 18 productos por
binding efectivo. Se conservan los seis campos existentes y sus IDs; tres
quedan legacy. No se crean como históricos `fluid_type` ni `hose_system_code`,
nunca unidos a esta plantilla. Se retiran los contenidos, mando integrado y
convertidores del prototipo: conjuntos y controles combinados tienen otro dueño.

La propuesta 228 de Claude acierta en separar tiro entregado/exigido, lado y
rueda, pieza y presentación, y fluido admitido/cargado. Root no acepta su
definición universal de una maneta con abrazadera, depósito y sólo salidas.
La evidencia primaria exige estas ramas adicionales:

- [Park Tool, manetas en línea](https://www.parktool.com/en-us/blog/repair-help/in-line-brake-levers):
  el cable atraviesa la maneta auxiliar, que actúa sobre la funda. El diámetro
  de fijación corresponde a la sección concreta del manubrio, no a una medida
  universal de manillar de ruta. De ahí los prerrequisitos de interfaz anclada
  frente a pasante y de montaje; no se copia un rango numérico general.
- [Paul Cross Lever](https://www.paulcomp.com/shop/components/brake-levers/inline/cross-lever/):
  el mismo modelo permite uso en línea o con cabeza de cable, y cambia de tiro
  al cambiar el pivote. No se impone «en línea nunca admite cabeza» ni se
  convierte Ajustable en compatibilidad universal; se documentan posiciones.
- [Paul Reverse Levers, instrucciones OEM](https://www.paulcomp.com/wp-content/uploads/2024/09/Reverse-Levers.pdf):
  montaje por expansor con rango de diámetro interior, frente a la abrazadera
  exterior. Motiva método de fijación previo y límites numéricos ordenados;
  ningún valor del manual se rellena en productos del catálogo.
- [Shimano GRX DM-GADBR01-06](https://si.shimano.com/en/pdfs/dm/GADBR01/DM-GADBR01-06-ENG.pdf),
  páginas 15–16 y 46–53: BL-RX812 conecta la maneta principal y la pinza, y
  necesita una zona de montaje de diámetro y longitud determinados. No se
  representa como una principal con puertos exclusivamente de salida. Las
  conexiones de la auxiliar tienen su tabla propia, condicionada al papel
  hidráulico. Los nombres de extremos no afirman flujo unidireccional.
- [Sheldon Brown, manetas y tiro](https://www.sheldonbrown.com/gloss_bo-z.html):
  relación de tiro y montaje son propiedades diferentes. Se permiten, por
  ejemplo, abrazadera pequeña/tiro corto y maneta de ruta/tiro largo; nunca se
  decide compatibilidad sólo por apariencia, marca o diámetro.
- [Shimano C-421](https://productinfo.shimano.com/en/compatibility/C-421) distingue
  manetas I-SPEC EV e I-SPEC II. El campo identifica la interfaz de esta pieza;
  no hereda todos los montajes ni los adaptadores que podrían convertirla.
- [SRAM MatchMaker X](https://www.sram.com/en/service/models/db-acc-mmx-a1)
  identifica esa interfaz como sistema de abrazadera. No se deduce por marca
  ni se confunde con incluir un mando de cambio en el producto.

`cable_head` existente describe el cable vendido y ofrece «Doble cabeza
(universal)». No se reutiliza como alojamiento de maneta. La tabla nueva
identifica cada perfil admitido y su fuente; cada perfil exige código
o dimensiones para poder distinguirlo. Pasante sólo no admite esa tabla; el uso doble requiere una
elección expresa del modelo, apoyada en su documentación.

Puertos de principal: sólo Salida. Puertos de auxiliar: extremo hacia mando o
pinza, con ID físico único. Ambos campos son mutuamente inaplicables según el
papel hidráulico. Purga sólo corresponde a Maneta y no convierte cualquier
tornillo sellado en purgador. Tiro y perfiles de cabeza no se permiten en una
maneta hidráulica. La mano nunca decide qué rueda frena.

Compilador: `scripts/inventory/compile_brake_lever_successor.py`; outputs
`brake-lever-2026-09-15-{catalog,cases,packet}.json`. Trece definiciones nuevas;
las globales ya publicadas son inmutables. Los flags de nuevas escalares se
habilitan explícitamente; las definiciones existentes mantienen sus flags
actuales, incluidos tiro y abrazadera no públicos/no filtrables. Esta limitación
de consumidores requiere su propia decisión; no se presenta como resuelta.

Las pruebas son límites de representación y conservación, no aprobación OEM.
Se mantienen valores inválidos y expectativas de rechazo al ajustar nombres
de error al validador: `range_order` para rango invertido y `row_shape` en Dart /
`field_constraint` en SQL para perfiles de cabeza inválidos o duplicados. La
comparación SQL ordena códigos/campos; el primer fallo del rango se debía al
orden de la lista esperada, no a falta de rechazo. No se relajan datos ni reglas.

La cohorte incluye nombres de pares/juegos. La plantilla heredada no prueba
que sean piezas únicas; el saneamiento de presentaciones sigue abierto antes
del llenado. Revisar fotos/contenido sin deducir «unidad» de ausencia de filas.
El contrato registra interfaces, no certifica el circuito completo ni evalúa
relaciones OEM entre perfiles.

Claude dejó su propuesta de 160 líneas y llegó al límite antes del cierre
visible. El intento con Opus 5 recibió el mismo bloqueo de sesión. No se
atribuye revisión independiente al candidato implementado por Root; ésta,
la publicación y los recorridos reales siguen pendientes.

Candidato actual SQL `ded86efb78dbdbdf5a4b470af9f4adb18f6c809d4fbb455142ffb86bc6ea7ce1`,
catálogo `c2df108e88ee457e0e2aeae0230c21fee7c21a93ed77dbf846c274c65719f480`.
Revisión propuesta 2→28, 25 campos y trece definiciones nuevas. Pasan 39 pruebas
Dart (una plantilla +38 casos), 38 casos SQL con publicación/repetición exacta
en rollback y 13 aserciones del escritor autenticado mediante
`test_brake_lever_profiles.py`: dos manetas retienen rangos distintos; no entran
abrazadera en expansor, límites invertidos, conexiones de auxiliar en principal,
entrada en puerto principal, mando integrado ajeno ni medida en la raíz.
Un cambio ordinario de raíz conserva las dos piezas. Nada se escribió en
productos reales.

Captura autenticada de las 18 manetas terminada 04:57:26 UTC; un fallo de red
dejó inicialmente 14 archivos, y la lectura retomó únicamente los cuatro
faltantes. La adopción fresca final conserva cero observaciones y cero hechos
sin proyectar; los 18 productos quedan pendientes, ninguno bloqueado. Evidencia
privada en `.tmp/product-spec-catalog/brake-lever-20260915/`, incluidos
`adoption-final.json`, `profile-tests/profiles.log` y `dart-v3.log`.


## Publicación y recorrido real, 05:53 UTC

Claude completó visiblemente la ronda 229 y aprobó el SHA exacto, condicionado
a evidencia reciente. Se conservaron los logs históricos fallidos y se agregaron
`sql-tests-v4` (38 casos, forward/replay) y `dart-v4.log` (39/39), con manifiesto
de hashes `review-condition-evidence.json`; F1 está resuelto. El arnés
`profile-tests` ya contenía también los casos de representación, además de las
13 pruebas de guardado, pero la separación de evidencia evita confundirlo con
los tres ensayos históricos fallidos. No hubo cambio de candidato para cerrar F1.

Preimagen autenticada de los 18 productos completada 05:40:47; metadatos vivos
iguales a la preimagen revisada. Publicación, 38 casos reales, readback exacto y
sello verificados. Lecturas autenticadas posteriores completadas 05:42:27,
comparación 05:42:57: datos completos del producto, observaciones, referencias,
revisión, valores del editor, perfiles e historial intactos. Las 18 lecturas
anónimas contienen cero valores antes y después. Cero llenado.

AE0319 en el editor enrutado de macOS claro cargó la revisión nueva sin guardar:
Mecánico exige tiro/interfaz; Expansor exige diámetro interior mínimo/máximo;
22/19 muestra conflicto en ambos campos. Cambiar a Abrazadera conserva los dos
valores incompatibles en controles con `Retirar este valor`; retirarlos del
borrador elimina esas incidencias. Hidráulico excluye los campos de cable y
pide su función; Auxiliar en línea muestra su tabla propia y no la de salidas
de principal. Se salió por Atrás del workspace, regresando al editor anterior
AE0244; lectura autenticada 05:53:53.666444 UTC conserva íntegramente AE0319,
sin hechos ni perfiles. Capturas y recibos en
`.tmp/product-spec-catalog/brake-lever-20260915/`.

La foto de AE0319 muestra dos manetas. Es evidencia adicional para la revisión
de su presentación, no una autorización para inventar dimensiones ni para
tratar el par como una sola pieza. La clase/presentación de la cohorte sigue
abierta. No se verificaron estos recorridos en teléfono ni en editor embebido;
no se hizo una nueva distribución. Las limitaciones F2/F3 del revisor siguen
registradas y no se transforman en compatibilidad aprobada.
