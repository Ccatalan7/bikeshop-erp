# Dirección original: candidato por extremo, sin aplicar

Una plantilla, 13 definiciones y 13 usos. Pasan 23 pruebas Dart y el avance,
repetición exacta y 22 casos SQL locales bajo la extensión de orden estricto,
con rollback. Se conservan sin cambios
las seis definiciones publicadas utilizadas por esta plantilla; siete son nuevas.
El paquete modifica cinco registros de metadatos y no contiene escrituras de
productos, asignaciones ni llenado. Se capturaron 15 fichas por la API autenticada,
sin errores ni escrituras: las 15 se evaluaron sin bloqueantes, con cuatro
observaciones legacy preservadas y ninguna observación activa sin proyección.
Las 15 siguen pendientes de datos; esto no certifica sus montajes ni las rellena.

## Decisiones con fuente

[Park Tool, SHIS](https://www.parktool.com/en-us/blog/repair-help/standardized-headset-identification-system)
separa extremos superior e inferior y documenta combinaciones mixtas. El código
superior nombra la interfaz de ese extremo; el inferior conserva la suya. Por
eso se separan los rodamientos y alturas instaladas de ambos extremos. Una
ficha que sólo vende el superior no puede declarar un rodamiento o código
inferior. SHIS es una nomenclatura nominal: no convierte automáticamente sus
números en cotas medidas, tolerancias o aprobación de una pieza.

[Sheldon Brown / John Allen](https://www.sheldonbrown.com/headsets.html) es la
base para distinguir el juego de dirección, el tubo de horquilla y el sistema
de potencia. Una cifra aislada en el título de un producto no identifica
necesariamente el tubo ni su rosca: antes se investiga qué pieza y cota nombra.
[Cane Creek Fifty](https://www.canecreek.com/products/fifty) ofrece varias
configuraciones SHIS. Esas variantes OEM no se cargan juntas como propiedades
del mismo SKU. La fixture ZS44/28.6 superior con EC44/40 inferior prueba la
representación de dos extremos; no identifica un producto del inventario.

El cuerpo de un cartucho/canastillo y las bolas sueltas se describen con campos
diferentes. Una fila de bolas sueltas admite cantidad y diámetro de bola, sin
asignarle diámetro exterior de cartucho. Los biseles interior y exterior siguen
separados, como establece la adjudicación de rodamientos. Una pista de corona
incluida tiene identidad de contenido; no declara por sí sola el asiento de la
horquilla ni se fuerza su presencia en todo juego completo.
La [revisión independiente](existing-headset-independent-review-2026-09-08.md)
confirmó esa separación. Su observación H1 detectó que el par escalar ID/OD no
se hereda dentro de una fila. Ambos extremos ahora declaran el par estricto
en [el esquema v2 candidato](strict-row-order-readiness-2026-09-08.md) y
rechazan ID mayor o igual que OD, sin comparar cuerpos ni filas diferentes.
La ausencia de una cota sigue pendiente. H2 se adjudica como
contenido independiente: un juego superior puede incluir una pieza adicional
identificada, sin declarar por ello un stack inferior.

## Conservación y pendientes

Los selectores antiguos de estándar, tubo y construcción se conservan como
observaciones legacy; no dominan silenciosamente los nuevos campos por extremo.
La tabla conjunta propuesta, el booleano `threaded` y el uso de altura total
nunca publicados en esta plantilla se sustituyen, sin borrar observaciones.
La definición global publicada `stack_height_mm` de otras familias permanece
intacta y fuera de este paquete.

Queda integrar referencias OEM/modelo con las interfaces SHIS. La geometría
estricta está implementada y probada localmente, pero necesita el despliegue
guardado de su extensión; la base productiva todavía usa la gramática v1.
La [revisión final](service-parts-and-row-order-delta-review-2026-09-08.md)
confirmó el delta estricto; faltan validación/distribución del cliente
antes de activar esta plantilla original. Los datos ausentes permanecen
pendientes; la ausencia de bloqueo no es aprobación de montaje.

## Evidencia

Preimagen de publicación: `2026-09-08T09:43:01.479756Z`, 15 asignaciones
efectivas. SQL generado sólo en `.tmp/db/existing-headset-forward-candidate.sql`.
Pruebas: `.tmp/product-spec-catalog/existing-headset-strict-order-tests.log` y
`.tmp/db/existing-headset-strict-order-forward-replay.log`.
Adopción: `.tmp/product-spec-catalog/existing-headset-strict-order-adoption-20260908.json`,
sobre `existing-headset-snapshots-20260908/manifest-20260908T094555603441Z.json`
dentro de ese directorio privado.

Catálogo SHA-256 `02968a0066cc3c51f401de205bc6dab933923b8cfe3ea4e9d2c42561f166db57`;
casos `1eda457a90cf3e17c17a8c52ba420db1d755a2da47d1acc6fde342d1ad33fa75`;
preimagen `4112b2b4b7bbc970617aafcd0c5cca54903d7f3f82cdb1a0897959358a469131`.
