---
titulo: Bielas, platos y línea de cadena
resumen: BCD, montaje directo, plato mínimo, línea de cadena y la interfaz del eje de la biela
fuentes: [sheldon-brown, park-tool, bike-matrix]
k: [K12, K18, K22]
claves_bici: [spindleInterface, drivetrainConfig]
claves_producto: [chainring_bcd_mm, chainring_bolt_count, chainring_bolt_pattern_symmetric, chainring_mount_type, chainring_mounting, chainring_direct_mount_generation, chainring_offset_mm, chainline_mm, chainring_teeth_rows, crank_axle_interface_declarations, crank_arm_length_mm, bottom_bracket_required, pedal_thread]
revisado: 2026-10-02
---

# Bielas, platos y línea de cadena

## Lo esencial

- Un plato con pernos calza en una araña con el **mismo BCD** (diámetro del
  círculo de pernos) **y la misma cantidad de pernos**. Es necesario, no
  suficiente: también cuentan la posición (exterior, medio, interior), el
  desplazamiento y la velocidad ([K12]).
- Cada BCD tiene un **plato mínimo** físico: en 110/5 no se monta un 33 de
  dientes sin que el perno toque la cadena [SB].
- Los platos de **montaje directo** (SRAM, Shimano 12 MTB, Race Face…) son de la
  generación y el estándar de esa biela; no hay BCD que comparar ([K12]).
- La biela tiene **otra interfaz** hacia el pedalier: su eje
  ([pedalier.md](pedalier.md), [K18]).

## BCD más comunes

| BCD / pernos | Plato mínimo | Dónde |
|---|---|---|
| 130 / 5 | 38 | ruta doble y triple (exterior) |
| 135 / 5 | 39 | Campagnolo |
| 110 / 5 | 33–38 | compacta, ruta, gravel |
| 110 / 4 asimétrico | 34 | Shimano ruta 9000 / R8000 (platos pareados) |
| 144 / 5 | 41 | pista |
| 104 / 4 | 30 | MTB triple (exterior y medio), una velocidad |
| 64 / 4 | 22 | MTB triple (interior) |
| 96 / 4 asimétrico | 30 | Shimano MTB XT/SLX 11 |
| 94 / 4 y 120 / 4 | 30 / 36 | SRAM (X1, GX, NX; 2×10) |
| 94 / 5 | 29 | triple compacta (exterior) |
| 74 / 5 | 24 | triple de paseo (interior) |
| 58 / 5 | 20 | triple compacta (interior) |

[SB] — la tabla completa de Sheldon tiene más de 40 patrones, muchos
obsoletos.

## Línea de cadena

| Uso | Línea de cadena (mm) |
|---|---|
| Pista, una velocidad, contrapedal | 40,5–42 |
| Ruta doble (Shimano) | 43,5 |
| Ruta triple (Shimano) | 45 |
| MTB triple / una velocidad MTB | 47,5–50 |
| Una velocidad Boost 148 | 52 |
| Rohloff | 54–58 |
| Descenso (150) | 55 |
| Fatbike | 66–76 |

[SB] — Bike Matrix usa este ejemplo para mostrar lo enredado que es: con maza
142 × 12, pedalier press-fit 30, caja de 79 mm asimétrica y biela DUB Wide, el
desplazamiento del plato (6 mm) decide si se llega a la línea de 52 mm [BM].

## Otras medidas de la biela

- **Largo de biela** (165, 170, 172,5, 175 mm) es elección del ciclista, no
  compatibilidad; sí afecta el espacio al suelo y al pie [Taller].
- **Rosca del pedal**: 9/16" en bielas de tres piezas, 1/2" en bielas de una
  pieza (bicis de paseo e infantiles americanas) ([pedales-y-calas.md](pedales-y-calas.md)) [SB].
- **Protector de plato / cubrecadena**: va al BCD o a los pernos de esa biela.

## Trampas frecuentes

- Comprar un plato 110/5 para una biela 110/4 asimétrica de Shimano.
- Poner un plato «de 12» en una biela de 1× sin mirar el desplazamiento: queda
  fuera de línea con un cuadro Boost.
- Confundir 104/4 (exterior) con 64/4 (interior) en una biela triple MTB.

## En Vinabike

- **Producto:** `chainring_bcd_mm`, `chainring_bolt_count`,
  `chainring_bolt_pattern_symmetric`, `chainring_mount_type`/`chainring_mounting`
  (pernos o directo), `chainring_direct_mount_generation`, `chainring_offset_mm`,
  `chainline_mm`, `chainring_teeth_rows` (la tienda muestra «42-34-24 dientes»),
  `crank_axle_interface_declarations` (eje de la biela), `crank_arm_length_mm`,
  `bottom_bracket_required` (qué pedalier pide la biela; la tienda aún no lo
  muestra), `pedal_thread`.
- **Bici:** `spindleInterface` (eje de la biela instalada) y `drivetrainConfig`.
- **Motor:** `_assessCrankDriveFamilyCompatibility` y
  `_assessBottomBracketFamilyCompatibility`.

## Fuentes

- Sheldon Brown, crib sheets «Cranks/Chainrings» (BCD) y «Bottom Brackets,
  Threaded» (línea de cadena).
- Bike Matrix, «Comparing Apples to Oranges».
