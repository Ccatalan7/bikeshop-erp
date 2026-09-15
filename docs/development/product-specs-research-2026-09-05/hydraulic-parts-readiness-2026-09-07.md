# Hidráulica — sucesor acotado (2026-09-07)

Familias: `hydraulic_hose`, `hydraulic_fitting`, `brake_fluid`. Candidato.
`mechanical_coverage_complete` y `automatic_fill_authorized` en `false`; sin
hechos, sin asignaciones, sin migración, sin cambios de motor, sin tocar tus
bloques.

Cuatro propuestas implementadas con casos, y cuatro vacíos que quedan
identificados. **Estas tres familias no quedan saneadas.**

## Alcance real, medido

Congelados verificados por hash al compilar: catálogo `16459826…f15`, casos
`329ad3e5…6d7`. Una sola fixture heredada (`brake_dot5_is_distinct_stock_description`).

Diferencia contra el congelado, computada y no declarada:

| | |
|---|---|
| Definiciones **añadidas** | `hydraulic_hose_members`, `hydraulic_hose_end_configurations`, `hydraulic_fitting_components`, `brake_fluid_declarations` — las cuatro de una sola familia |
| Definiciones **modificadas** | **ninguna** |
| Retiros, sólo de plantilla | `hose_length_mm`, `hose_outer_diameter_mm`, `hose_inner_diameter_mm` en la manguera; `brake_fitting_insert_length_mm` en el conector; `fluid_type` en el líquido |

Comprobado byte a byte que siguen idénticas `brake_hydraulic_connections`
(7 familias), `compatible_brake_models` (5), `kit_members` (23), `fluid_type`
(4), `hose_length_mm` (2), `hose_system_code` (5), `pack_quantity` (19),
`volume_ml` (4) y `spec_evidence_source` (105).

Lecturas de sólo lectura en producción: las tres plantillas están **ausentes**;
de las definiciones implicadas sólo `fluid_type` y `hose_length_mm` están
publicadas, y de ambas sólo se retira el uso local.

## HY-1 — la manguera se declara por tramo, y «se corta al instalar» es un estado propio

Jagwire publica que sus kits «include hose and fittings for a single brake» y
que las cajas a granel traen «10x 2000mm hoses with caliper-side fittings
pre-installed» o treinta metros sin cortar. Un producto de manguera es entonces
uno o varios tramos, y su largo puede estar **publicado**, quedar **a cortar por
el instalador**, o **no declararse**. El escalar único obligatorio no distinguía
ninguno de los tres.

`hydraulic_hose_members` lleva `length_form` con esos tres valores, y el largo
sólo se abre cuando está declarado. Los diámetros exterior e interior viajan
también por tramo y ninguno se deriva del otro.

## HY-2 — los dos extremos de una manguera no son la misma clase de cosa

Jagwire entrega «2 pre-installed caliper-side universal couplers» y vende el
adaptador de maneta por separado. Es decir: un mismo producto puede tener el
extremo de cáliper resuelto de fábrica y el de maneta todavía por comprar. Eso
no cabía en ninguna parte: `brake_hydraulic_connections` es la tabla de circuito
compartida por siete familias y no describe oliva, inserto ni rosca por extremo.

`hydraulic_hose_end_configurations` añade `supply` (preinstalado, incluido sin
instalar, se vende por separado, no declarado), la terminación, la oliva y el
inserto, y la rosca. Cada extremo se ata a su tramo por **id de fila** mediante
`row_coherence.links`, y `unique_by [[member_row_id, end_role]]` impide que un
tramo tenga dos extremos de maneta.

La rosca usa el camino estructurado con `thread_form`: o cifras descompuestas
con su unidad, o una designación literal, nunca las dos. **No hay un nominal de
texto libre junto a las cifras**, que es por donde se cuela un paso que ninguna
compuerta lee.

## HY-3 — un conector es varias piezas, y cada una tiene su interfaz

`brake_fitting_insert_length_mm` era un escalar único para un producto que suele
ser un juego de oliva más inserto. `hydraulic_fitting_components` lleva una fila
por pieza, con el mismo camino de rosca estructurado, y el largo de inserto
abierto sólo para las piezas que son inserto.

## HY-4 — clase, norma y designación son tres declaraciones, y la marca no decide ninguna

`fluid_type` mezclaba en un token la clase y la norma: «Aceite Mineral» junto a
«DOT 4». Son cosas distintas, y la diferencia es exactamente lo que pediste
proteger.

La evidencia está en los dos kits de purga de Park, que no se tocan entre sí. El
mineral es «for mineral oil-based hydraulic bicycle brake systems only» y su
lista de marcas incluye **SRAM® DB8**; el de DOT cubre «SRAM®, Formula®,
Hayes®, and Hope®». **La misma marca aparece en las dos clases**, así que el
nombre del fabricante no determina qué líquido lleva un freno. Ambas páginas
advierten que «DOT fluid and mineral oil should never be mixed».

`brake_fluid_declarations` separa `fluid_class`, `specification_form`,
`specification`, `oem_designation` y `approval_scope`. Los antecedentes están en
el ámbito que los hace expresables con los seis operadores, sin negación y sin
inventar nada:

- la **norma publicada** sólo se abre para la clase DOT;
- la **designación del fabricante** es **obligatoria** para el aceite mineral,
  porque el mineral no tiene norma publicada y su único identificador es el
  nombre de quien lo hace. Ésa es la forma ejecutable de «no llamar compatible
  cualquier aceite mineral»: la ficha no puede registrar un mineral sin decir
  cuál es;
- ninguna regla liga marca con clase, y un caso registra las dos filas del
  contraejemplo de Park conviviendo sin que una implique la otra.

## Una corrección que me hice a mí mismo

En el primer corte dejé `approval_scope` con sólo «Modelos declarados» y «Sin
aprobación declarada», razonando que el «most models» de Park prueba que una
aprobación por marca no cubre todos los modelos. Eso repetía el error que yo
mismo le critiqué a SH-1: hacía **irregistrable una declaración OEM real**. Un
fabricante que declara una marca completa debe poder quedar registrado diciendo
eso. Añadí «Marca completa declarada» y puse la advertencia donde corresponde,
en el helper: registrar no es avalar, y Park documenta la mayoría, no todos.

## Vacíos abiertos

- **V-1. No encodé que DOT 5 sea de silicona.** No pude leer ninguna fuente que
  lo diga: el artículo de soporte de SRAM devolvió **403**, los manuales de
  Magura son PDF con fuentes subconjunto y su texto no es recuperable, la página
  DOT de Park **no menciona** DOT 5 ni silicona, y la de frenos de Sheldon no
  habla de líquido hidráulico. La opción `DOT 5` se conserva separada y un caso
  fija que no es `DOT 5.1`, pero **no hay regla** que ate esa norma a una
  formulación. Sin fuente no la invento.
- **V-2. Shimano quedó ilegible.** `bike.shimano.com` y `si.shimano.com`
  devuelven 403. No entró ninguna cifra suya. El `11.2` que aparece en una
  fixture del conector es **sintético**; es además el número que el propio helper
  congelado usa como ejemplo de una medida que por sí sola no acredita un
  sistema.
- **V-3. Ningún diámetro de manguera está publicado en lo que pude leer.** Las
  páginas de Jagwire no dan exterior ni interior, así que las columnas existen y
  el `5` de una fixture es **sintético**.
- **V-4. La contaminación cruzada es una propiedad del sistema, no del envase.**
  Park prohíbe mezclar en el freno; una ficha de botella no puede expresar «esta
  botella no va en ese freno» más allá de `compatible_brake_models`, que ya
  existe y no toqué. La frontera entre mi tabla de extremos y la tabla de
  circuito compartida `brake_hydraulic_connections` también conviene fijarla al
  integrar: la mía es ferretería por extremo, la compartida es qué maneta,
  cáliper y manguera forman un circuito.

## Verificación

`test/unit/product_spec_integrated_catalog_test.dart` parametrizado:
**22 pruebas, todas verdes** — 3 de metadatos y 19 casos.

Verde al primer intento no prueba nada, así que muté el candidato tres veces y
cada mutante falla exactamente lo que debe, y nada más:

| Mutante | Falla |
|---|---|
| quitar la cláusula padre AND-ada de cada compuerta de fila | `hy_literal_thread_cannot_carry_a_pitch` y `hy_mineral_oil_cannot_claim_a_dot_standard` |
| quitar `unique_by` de los extremos | `hy_one_member_has_one_lever_end` |
| quitar el `row_coherence.links` | `hy_end_cannot_point_at_an_absent_member` |

Los tres mecanismos que añadí son portantes y está demostrado. El arnés compara
el conjunto de bloqueos de forma exacta, así que los casos que esperan «sin
bloqueo» son afirmaciones, no silencio.

## Hashes

| Archivo | SHA-256 |
|---|---|
| `scripts/inventory/compile_hydraulic_parts_catalog.py` | `4b670459c87a7226a446105fb43d004349c19bccd38d933c02e0e4d1592e0183` |
| `hydraulic-parts-catalog-2026-09-07.json` | `4af95314ac191bcb62fbe0ee01eedd22eaa41018c73c03d6a2a3298960eff979` |
| `hydraulic-parts-cases-2026-09-07.json` | `91926892bc139b90d0484895b8b8df87847cab3b2ad5ffb52c1c0067eee37bf9` |

Totales: 3 plantillas, 21 definiciones, 28 usos de campo, 19 casos.

## Fuentes

Leídas y citadas:

- Park Tool, *BKM-1.2 Hydraulic Brake Bleed Kit — Mineral* —
  https://www.parktool.com/en-us/product/hydraulic-brake-bleed-kit-mineral-bkm-1-2
- Park Tool, *BKD-1.2 Hydraulic Brake Bleed Kit — DOT* —
  https://www.parktool.com/en-us/product/hydraulic-brake-bleed-kit-dot-bkd-1-2
- Jagwire, *Pro Hydraulic Hose Kit* —
  https://www.jagwire.com/en/article/19/pro-hydraulic-hose-kit
- Jagwire, *Sport Mineral Hydraulic Hose Kit* —
  https://www.jagwire.com/en/article/21-174/sport-mineral-hydraulic-hose-kit

Intentadas y no legibles, por lo que nada suyo entró: soporte de SRAM sobre
DOT 5 y la página Avid DOT 5.1 (403 y sin contenido técnico), manuales PDF de
Magura (fuentes subconjunto, texto no recuperable) y su página de aceite mineral
(sin contenido técnico), `bike.shimano.com` y `si.shimano.com` (403), y la
página de frenos de Sheldon (no trata líquido hidráulico). Un resumen de buscador
no cuenta como lectura y no lo usé como fuente.
