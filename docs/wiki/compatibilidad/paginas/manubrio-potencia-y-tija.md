---
titulo: Manubrio, potencia, puños y tija
resumen: diámetros de abrazadera del manubrio, zona de mandos, potencia al tubo, tija y abrazadera del asiento
fuentes: [sheldon-brown, park-tool]
k: [K20, K21]
claves_bici: []
claves_producto: [handlebar_clamp_mm, bar_clamp_diameter_mm, bar_clamp_configurations, grip_area_diameter_mm, grip_bar_nominal_diameter_mm, grip_inner_diameter_mm, stem_steerer_clamp_diameter_mm, seatpost_diameter_mm, seatpost_min_insertion_mm, seatpost_kind, seatpost_shim_shape, saddle_rail_geometry, dropper_travel_mm, dropper_actuation, dropper_cable_routing]
revisado: 2026-10-02
---

# Manubrio, potencia, puños y tija

## Lo esencial

- Manubrio y potencia calzan por el **diámetro de la abrazadera** (centro del
  manubrio). Las manillas y puños calzan por el **diámetro de la zona de mandos**
  (los extremos). Son medidas distintas del mismo manubrio [SB].
- Tija, collarín del asiento y tubo del asiento son tres diámetros distintos;
  ninguno reemplaza al otro ([K20]).
- Una laina (shim) permite poner un manubrio **más delgado** en una potencia más
  grande, nunca al revés [Taller].

## Abrazadera del manubrio

| Diámetro | Dónde |
|---|---|
| 22,2 mm (7/8") | BMX y MTB antiguas de acero |
| 25,4 mm (1") | paseo, MTB y ruta antiguas |
| 26,0 mm | ruta italiana clásica |
| 31,8 mm | MTB y ruta actuales («oversize») |
| 35,0 mm | MTB actual (enduro, trail) |

[SB][Taller para 35 mm] — Sheldon lista además medidas obsoletas (25,0 francesa,
25,8, 26,4 Cinelli antigua).

## Zona de mandos (puños, manillas, cambios)

| Diámetro | Dónde |
|---|---|
| 22,2 mm | manubrio plano, MTB, BMX, paseo |
| 23,8 mm | manubrio de ruta (drop); manillas de ruta |

[SB] — Por eso una manilla de MTB no entra en un manubrio de ruta y una de ruta
queda suelta en uno plano [Taller].

## Potencia al tubo de dirección

- Sin rosca: abrazadera de 28,6 mm (1⅛"), 31,8 mm (1¼") o 25,4 mm (1"); con
  laina se baja una medida [Taller].
- Roscada (cuello o *quill*): 22,2 mm para tubos de 1" [Taller].
- Ver [direccion.md](direccion.md).

## Tija y asiento

- Diámetros de tija más vistos: 25,4 · 26,8 · 27,2 · 30,9 · 31,6 · 34,9 mm. Se usa
  el que indica el cuadro (grabado en la tija vieja o medido por dentro); con
  casquillo se baja de diámetro [Taller].
- **Inserción mínima**: marcada en la tija; debe quedar dentro del cuadro hasta
  pasar la unión con el tubo horizontal [Taller][Fab].
- **Tija telescópica**: además del diámetro, el recorrido, el largo total, la
  inserción del cuadro, el accionamiento (cable, hidráulica, inalámbrica) y el
  paso del cable (interno o externo) ([K21]).
- **Rieles del asiento**: redondos de 7 mm o ovalados de carbono (7 × 9 o
  similar); la cabeza de la tija debe aceptar ese riel [Taller].

## Trampas frecuentes

- Vender un manubrio de 35 para una potencia de 31,8.
- Medir la tija por fuera del tubo del asiento.
- Tija telescópica que no cabe porque el tubo del asiento tiene una curva o un
  tope antes de la inserción que pide.

## En Vinabike

- **Producto:** `handlebar_clamp_mm`/`bar_clamp_diameter_mm` (la tienda muestra
  «Para manubrio de»), `bar_clamp_configurations` (lainas), `grip_area_diameter_mm`,
  `grip_bar_nominal_diameter_mm`, `grip_inner_diameter_mm`,
  `stem_steerer_clamp_diameter_mm`, `seatpost_diameter_mm`,
  `seatpost_min_insertion_mm`, `seatpost_kind`, `seatpost_shim_shape`,
  `saddle_rail_geometry`, `dropper_travel_mm`, `dropper_actuation`,
  `dropper_cable_routing`.
- **Bici:** la ficha de la bici no guarda manubrio ni tija; es un hueco de la
  matriz unificada.

## Fuentes

- Sheldon Brown, crib sheet «Handlebars».
- Park Tool, «Headset Standards» (potencia sin rosca).
