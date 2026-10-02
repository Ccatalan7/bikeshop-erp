---
titulo: Ruedas, llantas y neumáticos
resumen: diámetro de asiento (BSD), cómo se escriben las medidas, qué ancho de neumático va en qué llanta y tubeless
fuentes: [sheldon-brown, park-tool]
k: [K14, K15, K16, K37]
claves_bici: [wheelSize, frontWheelBsdMm, rearWheelBsdMm, frontRimBsdMm, rearRimBsdMm, frontTireBsdMm, rearTireBsdMm]
claves_producto: [bead_seat_diameter_mm, front_bead_seat_diameter_mm, rear_bead_seat_diameter_mm, wheel_size, rim_etrto, tire_etrto, rim_internal_width_mm, rim_external_width_mm, tire_width_mm, tire_width_in, max_tire_width_mm, tire_rim_configurations, rim_tubeless_ready, tire_tubeless_ready, rim_wall_type, tire_bead_type, fork_tire_clearance_configurations]
revisado: 2026-10-02
---

# Ruedas, llantas y neumáticos

## Lo esencial

- **Un neumático calza en una llanta cuando tienen el mismo diámetro de
  asiento del talón (BSD, en mm).** Es el número grande de la medida ISO/ETRTO:
  en `37-622`, 622 es el BSD y 37 el ancho [SB][PT][K14].
- El nombre en pulgadas **no** identifica el diámetro. Una medida decimal y una
  fraccionaria iguales en números no son el mismo neumático: 26 × 1.75 y
  26 × 1¾ son distintos («ley de Brown») [SB][PT].
- La llanta se escribe `BSD × ancho interior` (`622x19`). El ancho del
  neumático debe ir con el ancho **interior** de la llanta, no con el exterior
  [SB][PT][K16].
- Tubeless se evalúa como **sistema**: neumático tubeless ready + llanta
  tubeless ready + cinta + válvula + sellante. Entre marcas puede o no sellar;
  forzar piezas no tubeless no es seguro [PT][K15].

## Diámetros (BSD) que más se ven

| BSD | Nombres | Uso típico |
|---|---|---|
| 203 | 12½" | infantil, scooters |
| 305 | 16" decimal | infantil, BMX chico, remolques |
| 349 | 16" fraccionario (16 × 1⅜) | plegables (Brompton) |
| 355 | 18" | plegables Birdy, BMX |
| 406 | 20" decimal | BMX, infantil, plegables, reclinadas |
| 451 | 20" fraccionario (20 × 1⅛) | BMX de carrera, plegables, reclinadas |
| 507 | 24" decimal | MTB infantil |
| 520 | 24 × 1 / 1⅛ | ruta pequeña (Terry) |
| 559 | 26" decimal | MTB, cruiser, fatbike |
| 571 | 26 × 1¾ / 650C | triatlón y ruta talla chica |
| 584 | 27.5" / 650B / 26 × 1½ | MTB moderna, gravel, ciudad francesa |
| 590 | 26 × 1⅜ (650A) | paseo inglés antiguo |
| 597 | 26 × 1¼ / 1⅜ (S-6) | Schwinn, inglesas antiguas |
| 622 | 700C / 28" / 29" | ruta, gravel, híbrida, MTB 29 |
| 630 | 27" | ruta antigua |
| 635 | 28 × 1½ (700B) | bicis de varilla, carga |

[SB][PT]

**Ojo:** «26 × 1⅜» puede ser 590, 597 o 547; «28"» en Europa es 622 pero
28 × 1½ es 635; «27"» (630) no es 700C (622) [SB][PT].

## Ancho de neumático según ancho interior de llanta

Regla de Park Tool: el ancho ISO del neumático entre **1,5 y 2 veces** el ancho
interior de la llanta [PT]. La tabla conservadora de Sheldon Brown (Georg
Boeger), por ancho interior de llanta:

| Ancho interior (mm) | Neumático (mm) |
|---|---|
| 13 | 18–25 |
| 15 | 20–32 |
| 17 | 23–37 |
| 19 | 25–44 |
| 21 | 32–50 |
| 23 | 40–54 |
| 25 | 44–57 |

[SB] — el mismo artículo advierte que la tabla es prudente. Hoy los
fabricantes aprueban neumáticos más angostos en llantas más anchas (por ejemplo
25 mm en 19 mm interior); en ese caso manda la tabla del fabricante de la llanta
y del neumático [Fab][Taller].

## Tubeless y llantas sin gancho (hookless)

- Neumático y llanta deben decir **tubeless ready** (o UST, la norma vieja); un
  neumático con talón para cámara no se vuelve tubeless [PT].
- Se necesitan cinta adhesiva resistente al sellante, válvula tubeless con
  sello en la base y sellante. Los sellantes de látex no siempre se mezclan
  entre marcas [PT].
- Llanta **hookless**: sólo neumáticos aprobados para hookless y presión
  máxima limitada por el fabricante de la llanta (en ruta suele ser cerca de
  5 bar / 72 psi). Un neumático no aprobado puede salirse [Fab][Taller].

## Trampas frecuentes

- Vender un neumático por el nombre «27.5 × 2.2» sin mirar el 584.
- Creer que «29» y «700C» son distintos: los dos son 622.
- Usar el ancho exterior de la llanta para elegir el neumático.
- Montar un neumático más ancho que el espacio del cuadro u horquilla: el
  diámetro y el ancho reales crecen con el balón [SB].

## En Vinabike

- **Bici:** `wheelSize` es el nombre de la plataforma; los BSD por rueda
  (`frontWheelBsdMm`, `rearWheelBsdMm`, y por pieza `front/rearRimBsdMm`,
  `front/rearTireBsdMm`) son la verdad que compara el motor. La bici puede
  tener ruedas de distinto diámetro (mullet).
- **Producto:** `bead_seat_diameter_mm` y su versión por rueda, `rim_etrto`,
  `tire_etrto`, `rim_internal_width_mm`, `tire_width_mm`/`tire_width_in`,
  `rim_tubeless_ready`, `tire_tubeless_ready`, `rim_wall_type` (con o sin
  gancho), `tire_rim_configurations` (anchos aprobados por llanta) y, en la
  horquilla, `fork_tire_clearance_configurations` (aro y neumático más ancho).
- **La tienda** muestra el BSD como el cliente lo pide («29" / 700c») con
  `wheelSizeLabelForBsd` y el ancho en pulgadas y milímetros con
  `tireWidthLabel` (`lib/public_store/utils/public_spec_display.dart`).
- **Motor:** `_assessRimFamilyCompatibility` y las familias de neumático, cámara
  y tubeless comparan BSD; el ancho llanta↔neumático se juzga sólo cuando las dos
  fichas tienen el dato.
- **Falta:** un juicio de ancho de neumático contra el espacio del cuadro de la
  bici (la ficha de la bici no guarda el neumático más ancho que admite).

## Fuentes

- Sheldon Brown, «Tire Sizing Systems» y «Tire Sizes» (crib sheet).
- Park Tool, «Tire, Wheel and Inner Tube Fit Standards» y «Tubeless Tire
  Compatibility».
