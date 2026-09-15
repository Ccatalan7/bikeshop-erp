# Transmisión menor: integración independiente antes de publicar

2026-09-07. Candidato final de cuatro plantillas; 34 definiciones, 39 usos,
33 casos. Sustituye la propuesta inicial del colaborador. No aplicado aún.

- **Kits de fijación:** DS-1 sí se cierra sin ampliar el motor. Se retira el uso
  anterior como legacy y se crea una tabla por pieza con un valor de paso y su
  unidad. Las fixtures se traducen usando la unidad explícita de la columna
  antigua, nunca desde el nominal; RCF47 mantiene 9 mm y 26 TPI representables
  sin una prohibición por dialecto. Eso no certifica que esas cifras pertenezcan
  a un producto. La fuente [Park](https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts)
  confirma la independencia con el ejemplo 10 mm × 26 TPI. El paso en una pieza
  declarada sin rosca bloquea y el accionamiento del kit no pasa a una golilla.
- **Extensores:** [Wolf Tooth RoadLink](https://www.wolftoothcomponents.com/pages/roadlink-tech-page)
  distingue versión DM/Standard, cambio, cassette y valoración; el mismo 42T
  no significa lo mismo con 11T que con 10T. La fila mantiene esa combinación,
  modelo del extensor, generación/jaula del cambio, estado y capacidad/condiciones.
  Se preserva la declaración sobre capacidad de RoadLink sin convertirla en
  ley para todo extensor de otra marca. La página contiene una afirmación
  adicional de mejora parcial para 10–42; el caso conserva el estado de su lista
  de compatibilidad, no inventa un veredicto universal ni compatibilidad de fábrica.
- **Guardas:** [OneUp V2, junio 2023](https://int.oneupcomponents.com/blogs/bashguides-chainguides/bashguard-chainguide-install-instructions)
  publica placas reemplazables con coberturas diferentes. Cada placa/configuración
  enlaza por ID al montaje; no se unen sus límites ni se confunde contenido con
  piezas alternativas disponibles. La fixture de dos placas prueba declaración
  de configuraciones, no afirma que ambas se incluyan en un SKU.
- **Anillos:** [Sheldon, Lockring](https://www.sheldonbrown.com/gloss_l.html)
  separa rosca del anillo, objetivo, edición y piñón exterior. La fila ahora dice
  quién posee la interfaz. El piñón fijo y su contratuerca son dos componentes,
  no dos roscas propias de un anillo. El nominal aproximado HG 30 mm × 24 TPI
  permanece aproximado y no identifica un SKU. Campagnolo 1996–1999 conserva
  su ámbito; no se copia a 2000+. Se retiran los dos escalares de objetivo y
  piñón exterior. La etiqueta nueva es «Anillo de bloqueo de transmisión»;
  la clave/UUID histórica cassette_lockring permanece y no reasigna productos.

37 pruebas Dart pasan. SQL conserva una incidencia por celda contradictoria,
Dart compara conjuntos: dos casos explicitan dos incidencias SQL idénticas en
código/campo, sin cambiar el bloqueo ni el motor. El publicador de pruebas ahora
elige otra definición compartida cuando el bloque no usa kit_members; mantiene
ese sujeto para los bloques anteriores. El primer fallo fue esa suposición del
harness, no una prueba de la migración. Misma ruta de rollback y guardas.

Preimagen viva 2026-09-08T01:06:19Z, ocho compartidas exactas y cero colisiones.
Mismo publicador: 26 definiciones/49 opciones/4 plantillas/39 usos nuevos.
Backup restringido 20260908T0130Z-drivetrain-small-part-metadata. Ninguna escritura
de productos, hechos, referencias ni asignaciones. No certifica la familia
completa ni habilita llenado. SQL/publicador en
.tmp/db/drivetrain-small-parts-publication-tests.log; debe pasar antes de aplicar.

| Artefacto | SHA-256 |
|---|---|
| scripts/inventory/compile_drivetrain_small_parts_catalog.py | `c00397509c0a4ce6d24d7c5eb48366de4af9f744474bb2f314f2bf78e321a49a` |
| docs/development/product-specs-research-2026-09-05/drivetrain-small-parts-catalog-2026-09-07.json | `1dbb2f526f09368d34550d5aca249ff4849dbb998fe47ad2bef6afce2a619213` |
| docs/development/product-specs-research-2026-09-05/drivetrain-small-parts-cases-2026-09-07.json | `63ba1e2adb73aca43fec19c545289a4bc063db01cd9da2a51ea9aa770de62d59` |
| docs/development/product-specs-research-2026-09-05/drivetrain-small-parts-publication-preimage-2026-09-07.json | `1e8c7dcf491b6f5ee10aabd74095ae3c5eeb184387c2ba9058e68ad5acc6a7d7` |
| docs/development/product-specs-research-2026-09-05/drivetrain-small-parts-publication-packet-2026-09-07.json | `c8c29ccc44c4e31459857e5a7d2f24cc7734873e7dde65ada775d462a17bac4c` |
| supabase/migrations/20260908013000_drivetrain_small_part_spec_templates.sql | `9339b8193d8ce567e9a33659bb7ccf5e089886c29004b544e13996f7fd15a1da` |
| supabase/manual_checks/verification/20260908013000_drivetrain_small_part_spec_templates.sql | `3897a23d760390362605444f536769eb74a71474497ffe0f11e89150e768d7a2` |

## Adjudicación DT-1/DT-2 antes de aplicar — 2026-09-07, 18:44 LA

La revisión independiente encontró dos huecos reales; se corrigen antes de
aplicar. El candidato anterior de 33 casos queda sustituido. Ahora son
4 plantillas, 36 definiciones, 41 usos y 46 casos: 50 Dart pasan y los
46 casos SQL más cinco pruebas del publicador pasan en rollback local.

DT-1: el nominal de texto de cada pieza deja de competir con el paso numérico.
Diámetro decimal y unidad son independientes del paso y su unidad. La designación
OEM literal es un camino exclusivo, sin geometría descompuesta; no se cierra el
universo a los tamaños del enum histórico. La traducción finita de cinco valores
se aplica sólo a fixtures sintéticas identificadas, jamás a productos.

DT-2: se agregan claves compuestas por la configuración real. Cassette, cambio,
jaula, velocidades, montaje y apartado de fuente individualizan el veredicto.
El máximo sin cassette tiene su propia tabla y clave: no se inventa un piñón
menor cero para hacerlo participar. Una elección inicial abre combinaciones,
límites o ambos, y pide las filas correspondientes. Guardas distinguen la
presentación; interfaces de anillo distinguen dueño, edición y configuración.
Misma configuración completa con dos estados opuestos bloquea; diferente jaula,
cassette, presentación o interfaz conserva su propia declaración. Una identidad
incompleta sigue pendiente: no se afirma deduplicación semántica de nombres
libres ni equivalencia entre etiquetas distintas. No se añade unique_by a tablas
sin identidad de colección justificada ni se mutan definiciones legacy compartidas.

Releí [Wolf Tooth](https://www.wolftoothcomponents.com/pages/roadlink-tech-page):
el apartado RoadLink DM, 11s Cassette Compatibility dice Not Supported para
10–42; el comentario siguiente dice mejora parcial sin nivel de fábrica. La
fixture conserva el veredicto de esa lista y registra la salvedad en condiciones
y su apartado en source_scope; no transforma una mejora en soporte OEM.

Preimagen nueva: 2026-09-08T01:41:12Z, ocho compartidas exactas, cero colisiones.
La anterior y su backup se conservan. Publicación propuesta: 28 definiciones,
52 opciones, 4 plantillas y 41 usos. Backup revisado:
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260908T014349Z-drivetrain-reviewed-metadata`.
Sin aplicar todavía, sin nuevas asignaciones ni llenado.

| Artefacto vigente | SHA-256 |
|---|---|
| compile_drivetrain_small_parts_catalog.py | `977358216d6101b786c629b8d3e1a726e922409ae12ab3a64db0ea56d375d7f2` |
| drivetrain-small-parts-catalog-2026-09-07.json | `e847f24f1a6cac14a34d90f2cf54a713df621dced5bb2f9a9eda7cc07a10b25d` |
| drivetrain-small-parts-cases-2026-09-07.json | `3b9a86eb94fdb6fd5818162936998e9896928d2e25ff94a4217db7c0fac28f12` |
| drivetrain-small-parts-publication-preimage-reviewed-2026-09-07.json | `0b94c71cd171fbbbaac8936ad1b0319c9e9163142e80217a70ebc3c8d2a556d0` |
| drivetrain-small-parts-publication-packet-2026-09-07.json | `5f5fc45f590b7df15d962d8b499af86b3f3a21b3fc9a218ac939ada72387740c` |
| 20260908013000_drivetrain_small_part_spec_templates.sql | `56f02a5b82208478fcc086ed550dc8562e1afd76f6b92aede315c4e21c4c7eea` |
| 20260908013000_drivetrain_small_part_spec_templates.sql | `2a3b84547900b861873d7b76af32e094e87dc31046bf0cf5717d53e77d8b1cbb` |
