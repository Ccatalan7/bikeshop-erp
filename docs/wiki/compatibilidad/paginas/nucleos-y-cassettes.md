---
titulo: Núcleos, cassettes y ruedas libres
resumen: qué cassette entra en qué núcleo, separadores, rueda libre roscada y herramientas
fuentes: [sheldon-brown, park-tool]
k: [K04, K08, K09, K11]
claves_bici: [freehubType, drivetrainSpeeds]
claves_producto: [freehub_type, cassette_spline_standard, rear_drive_interface, freehub_bodies_accepted, sprocket_count, smallest_cog_teeth, largest_cog_teeth, cog_sequence, lockring_included, cog_thread_standard]
revisado: 2026-10-02
---

# Núcleos, cassettes y ruedas libres

## Lo esencial

- **Cassette o rueda libre.** Gira los piñones hacia atrás: si la ranura para la
  herramienta gira con ellos es un cassette sobre un núcleo (freehub); si no
  gira, es una rueda libre roscada en la maza [PT][K08].
- Un cassette calza en un núcleo cuando coinciden el **estriado** (la forma de
  las ranuras), el **largo del núcleo** y el **piñón más chico** que el núcleo
  admite. La cantidad de velocidades sola no lo decide.
- Piñón fijo, rueda libre de una velocidad y cassette son ramas distintas
  ([K08]).

## Los núcleos que se ven en el taller

| Núcleo | Qué recibe | Notas |
|---|---|---|
| Shimano HG 7 v | cassettes de 7 | más corto que el de 8-10 |
| Shimano HG 8-10 (y MTB 11) | 8, 9, 10 y cassettes MTB de 11; SRAM PG; LINKGLIDE | el estándar más común; ranura ancha marca la posición |
| Shimano HG ruta 11 (HG L2) | 11 y 12 de ruta Shimano; 8-10 con separador de 1,85 mm | 1,85 mm más largo que el 8-10 |
| Shimano Microspline | MTB 12 Shimano (piñón de 10 dientes) | no recibe HG |
| SRAM XD | MTB 11 y 12 SRAM (piñón de 10 dientes) | sin anillo de cierre visible |
| SRAM XDR | ruta/gravel SRAM; XD con separador de 1,85 mm | XD alargado |
| Campagnolo | 9 a 12 Campagnolo | estriado propio |
| Campagnolo N3W | 13 v y 12 v desde 2022 | admite cassettes anteriores con adaptador [Fab] |

[SB][PT][Fab][Taller]

## Separadores (Shimano)

| Montaje | Separador |
|---|---|
| Cassette de 7 en núcleo 8-10 | 4,5 mm detrás del cassette [SB] |
| Cassette de 10 en núcleo 8-9 | el de 1 mm que trae el cassette, cuando lo trae [SB] |
| Cassette 8-10 en núcleo ruta 11 | 1,85 mm [SB][Fab] |
| Cassette de ruta 11/12 en núcleo 8-10 | **no entra** (el núcleo es corto) [SB] |

Manda la ficha del cassette: algunas series traen o piden su propio separador
[Fab].

## Rueda libre roscada

- Rosca casi siempre inglesa (1,37" × 24 TPI). Las francesas e italianas
  antiguas existen; no se mezclan [SB][PT].
- Mazas de rueda libre: 5, 6 y 7 velocidades (OLD 120-126-130/135). Pasar de una
  rueda libre a cassette es cambiar la maza [SB].
- Herramientas distintas según la marca: Shimano/Sun Race 12 estrías (~23 mm),
  Suntour 2 o 4 dientes, BMX/una velocidad 4 dientes. Park advierte no usar la
  herramienta de Falcon en una Shimano aunque se parezcan [PT].

## Herramienta del anillo de cierre

- Shimano, SRAM, Sun Race, Chris King, DT: 12 estrías, ~23,4 mm (Park FR-5.2).
  El piñón chico de un cassette XD usa la misma herramienta [PT].
- Campagnolo: 12 estrías, ~22,8 mm (otra herramienta) [PT].

## Cómo se separan los dientes

| Velocidades | Paso entre piñones (mm) | Grosor de piñón (mm) |
|---|---|---|
| 7 (Shimano HG) | 5,0 | 1,85 |
| 8 (Shimano/SRAM) | 4,8 | 1,8 |
| 9 (Shimano/SRAM) | 4,34 | 1,78 |
| 9 (Campagnolo) | 4,55 | 1,75 |
| 10 (Shimano) | 3,95 | 1,6 |

[SB] — Por eso un mando indexado de 9 no cambia bien un cassette de 10: el
paso es distinto ([cambios-y-mandos.md](cambios-y-mandos.md)).

## Trampas frecuentes

- Pensar que 12 velocidades es un solo núcleo: Microspline, XD, HG ruta (Shimano
  ruta 12) y Campagnolo son cuatro.
- Instalar 11 de ruta en una rueda MTB antigua de 8-10: no aprieta y se suelta.
- LINKGLIDE: el cassette usa núcleo HG, pero cadena, cambio y mando son de la
  familia LINKGLIDE ([K04]).

## En Vinabike

- **Bici:** `freehubType` (kernel V1; admite «desconocido» explícito) con el
  vocabulario del código: `shimano_hg`, `shimano_hg_road_11`, `shimano_hg_plus`,
  `shimano_hg_sis`, `microspline`, `linkglide`, `sram_xd`, `sram_xdr`,
  `campagnolo`, `campagnolo_n3w`, `threaded_freewheel`, `bmx_driver`,
  `fixed_threaded`. En producción (2026-10-02): 25 rueda libre, 21 `shimano_hg`,
  3 Microspline, 1 XD, 2 «desconocido» y 143 fichas sin el dato.
- **Hueco:** `shimano_hg` no distingue el núcleo corto de 7 del de 8-10. Un
  cassette de 7 en una bici `shimano_hg` puede ir directo o con el separador de
  4,5 mm; el veredicto honesto es *con condiciones* hasta que se mire la rueda
  (consulta archivada, 2026-10-02).
- **Producto:** `freehub_type` (maza), `cassette_spline_standard` y
  `rear_drive_interface` (cassette), `freehub_bodies_accepted` (tabla del
  fabricante: qué núcleos acepta un cassette y si pide separador; la tienda
  todavía no la muestra), `sprocket_count`, `smallest_cog_teeth`,
  `largest_cog_teeth`, `cog_sequence` (la tienda la muestra como
  «11-13-15-…-34 dientes»), `lockring_included`.
- **Motor:** `_assessCassetteFamilyCompatibility`, `_assessFreewheelFamilyCompatibility`
  y `_assessFixedCogFamilyCompatibility`, con `_formatFreehubSet` para explicar
  qué núcleos acepta.
- **Pendiente para la tienda:** una vista de `freehub_bodies_accepted` («Núcleo:
  Shimano HG de 8 a 11 velocidades»); 17 cassettes publicados tienen el dato
  (lectura 2026-10-02).

## Fuentes

- Sheldon Brown, «Shimano Cassettes & Freehubs» (k7) y «6-speed, 7-speed, …
  11-speed?» (speeds), crib sheet «Spacing».
- Park Tool, «Determining Cassette / Freewheel Type» y «Cassette Removal and
  Installation».
