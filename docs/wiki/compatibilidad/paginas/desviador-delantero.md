---
titulo: Desviador delantero
resumen: abrazadera, montaje, sentido de giro y tiro, platos y velocidades
fuentes: [sheldon-brown]
k: [K10, K13]
claves_bici: [drivetrainConfig, drivetrainSpeeds]
claves_producto: [front_derailleur_clamp_options, front_derailleur_clamp_mm, front_derailleur_mount_type, front_derailleur_swing, front_derailleur_pull_direction, front_derailleur_cable_pull, front_derailleur_application_configurations, front_derailleur_compatibility_claims, seat_tube_outer_for_fd_mm]
revisado: 2026-10-02
---

# Desviador delantero

## Lo esencial

Un desviador calza cuando coinciden:

1. **Montaje**: abrazadera de 28,6, 31,8 o 34,9 mm (al diámetro del tubo del
   asiento; con casquillo se baja de 34,9 a 31,8 o 28,6), soldado (*braze-on*,
   ruta), **direct mount** o **E-type** (sujeto al pedalier) [Taller][Fab].
2. **Sentido de giro** (*top swing*, *down swing*, *side swing*) y **tiro de
   cable** (desde arriba o desde abajo): dependen del paso del cable en el cuadro
   [Fab][Taller].
3. **Platos**: cantidad (2 o 3), plato grande máximo y diferencia entre platos
   que admite [Fab].
4. **Velocidades y familia del mando**: un desviador de 2×11 de ruta Shimano pide
   mando de ruta 11 [Fab].
5. **Línea de cadena**: un desviador de MTB con línea de cadena Boost u otra no
   alinea con platos de otra línea [SB][Taller].

## Abrazaderas

| Abrazadera | Tubo del asiento |
|---|---|
| 28,6 mm (1⅛") | tubos delgados, acero |
| 31,8 mm (1¼") | aluminio común |
| 34,9 mm (1⅜") | tubos anchos; con casquillos baja a 31,8 o 28,6 |

[Taller]

## Trampas frecuentes

- Pedir «el desviador de 31,8» sin decir si es top o down swing ni de dónde
  viene el cable.
- Montar un desviador de 3 platos con platos de 2 (o al revés): la jaula no
  coincide.
- La tienda muestra la transmisión como «3x7 o 3x8»: platos adelante por piñones
  atrás.

## En Vinabike

- **Producto:** `front_derailleur_clamp_options` (opciones con casquillo; la
  tienda muestra «34,9 mm, 31,8 mm (con casquillo)»), `front_derailleur_mount_type`,
  `front_derailleur_swing`, `front_derailleur_pull_direction`,
  `front_derailleur_cable_pull`, `front_derailleur_application_configurations`
  (platos × piñones).
- **Bici:** `drivetrainConfig` dice si hay desviador; el diámetro del tubo del
  asiento (`seat_tube_outer_for_fd_mm` en productos) no está en la ficha de la bici.
- **Motor:** `_assessFrontDerailleurFamilyCompatibility`.

## Fuentes

- Sheldon Brown, crib sheet «Bottom Brackets, Threaded» (línea de cadena).
- El resto es criterio de taller; Park Tool «Front Derailleur Adjustment» queda
  pendiente de ingerir ([fuentes/park-tool.md](../fuentes/park-tool.md)).
