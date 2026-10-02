---
titulo: Frenos de llanta y manillas
resumen: V-brake, cantilever, caliper de ruta y U-brake; tiro largo o corto de la manilla; pastillas y pista
fuentes: [sheldon-brown]
k: [K23, K25]
claves_bici: [brakeType, rimBrakeFamily]
claves_producto: [brake_type, brake_actuation, lever_cable_pull, lever_cable_pull_positions, rim_brake_mount_fitments, boss_spacing_mm, rim_pad_stud_type, rim_pad_length_mm, rim_pad_construction, rim_material, brake_track]
revisado: 2026-10-02
---

# Frenos de llanta y manillas

## Lo esencial

- La **manilla y el freno deben ser del mismo tiro**. Las V-brake (*direct pull*,
  tiro lineal) tienen el doble de ventaja mecánica, así que piden una manilla que
  tire **el doble de cable** con la mitad de fuerza: **tiro largo** [SB][K23].
- Cantilever clásico, U-brake y caliper de ruta usan manilla de **tiro corto**
  (estándar) [SB].
- Mezclarlas no es seguro: una manilla de tiro corto con V-brake llega al
  manubrio antes de frenar en mojado; una de tiro largo con caliper frena de golpe
  o no da fuerza [SB].

## Familias de freno de llanta

| Familia | Montaje | Manilla |
|---|---|---|
| V-brake | pernos (bosses) en el cuadro/horquilla | tiro largo |
| Cantilever | pernos (bosses) | tiro corto |
| Mini-V | pernos | tiro corto (de ruta) por diseño [Fab] |
| U-brake | pernos sobre el tirante (BMX) | tiro corto [SB] |
| Caliper de ruta | perno central | tiro corto |
| Caliper de alcance largo | perno central | tiro corto |

Hay adaptadores de recorrido (Travel Agent y similares) que dejan usar manillas
de ruta con V-brake [SB][Taller].

## Alcance del caliper

El **alcance (reach)** es la distancia del perno central a la pista de frenado.
Un caliper de alcance corto no llega en un cuadro hecho para alcance largo (y al
revés queda sin recorrido). Se mide en la bici antes de vender [Taller].

## Pastillas

- Se identifican por su **forma y forma de fijación**, no por la marca del freno:
  perno roscado (V-brake), perno liso (cantilever), cartucho de ruta (Shimano o
  Campagnolo) ([K25]).
- El compuesto va con la **pista**: aluminio o carbono. Una pastilla de aluminio en
  una llanta de carbono la daña [Taller][Fab].

## Trampas frecuentes

- Cambiar la manilla de una MTB con V-brake por una «de 3 dedos» de tiro corto.
- Pastilla de V-brake (perno roscado) para un cantilever de perno liso.

## En Vinabike

- **Bici:** `brakeType` (llanta, disco mecánico, hidráulico, contrapedal,
  tambor…) y, si es de llanta, `rimBrakeFamily` (`v_brake`, `cantilever`,
  `road_caliper_short_reach`, `road_caliper_long_reach`). Kernel V1: no se
  aplana todo en «llanta».
- **Producto:** `brake_type`, `brake_actuation`, `lever_cable_pull` (y por
  posición en manillas combinadas), `rim_brake_mount_fitments`, `boss_spacing_mm`,
  `rim_pad_stud_type`, `rim_pad_length_mm`, `rim_pad_construction`; en la llanta,
  `rim_material` y `brake_track`.
- **Motor:** `_assessRimBrakeFamilyCompatibility`, `_assessBrakePadFamilyCompatibility`
  y `_assessBrakeLeverFamilyCompatibility`.

## Fuentes

- Sheldon Brown, «Adjusting Direct-pull Cantilever Brakes» y «Adjusting U-Brake»
  (leídas por resumen de búsqueda; ver [fuentes/sheldon-brown.md](../fuentes/sheldon-brown.md)).
