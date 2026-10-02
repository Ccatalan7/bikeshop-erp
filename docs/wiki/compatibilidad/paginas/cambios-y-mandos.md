---
titulo: Cambios traseros, mandos y tiro de cable
resumen: por qué un mando y un cambio indexados tienen que ser de la misma familia, capacidad, piñón máximo y montaje
fuentes: [sheldon-brown, park-tool, bike-matrix]
k: [K05, K10, K13, K49]
claves_bici: [drivetrainSpeeds, drivetrainConfig]
claves_producto: [shift_actuation_family, rear_derailleur_actuation_ratio_declaration, shifter_actuation_mode, shifter_indexed_positions, rear_derailleur_total_capacity_teeth, rear_derailleur_max_teeth, rear_derailleur_min_teeth, derailleur_cage_length, rear_derailleur_mount_type, rear_derailleur_hanger_interface, rear_derailleur_application_configurations, rear_derailleur_compatibility_claims, shifter_compatibility_claims, derailleur_clutch]
revisado: 2026-10-02
---

# Cambios traseros, mandos y tiro de cable

## Lo esencial

Un cambio indexado funciona cuando **tres cosas** calzan entre sí [SB]:

1. **Cable que tira el mando por clic.**
2. **Cuánto se mueve el cambio por milímetro de cable** (relación de
   accionamiento).
3. **Paso entre piñones** del cassette ([nucleos-y-cassettes.md](nucleos-y-cassettes.md)).

Por eso el mando es **de una velocidad concreta** (un mando de 9 no cambia bien
10) y el cambio es **de una familia de tiro**. Con mando de fricción cualquier
combinación funciona [SB].

## Familias de tiro que no se mezclan

| Familia | Qué incluye | Regla |
|---|---|---|
| Shimano clásica | ruta hasta 10 (salvo Tiagra 4700) y MTB hasta 9 | mezcla entre sí dentro de las velocidades |
| Shimano Dyna-Sys | MTB 10 | mando y cambio Dyna-Sys juntos [SB] |
| Shimano ruta 11 | ruta 11 (5800, 6800, 9000, R7000…) y Tiagra 4700 de 10 | no se mezcla con ruta anterior [Fab][Taller] |
| Shimano MTB 11 / 12 | cada generación con su tabla | 12 no se mezcla con 11 [Fab] |
| SRAM 1:1 (Exact Actuation, «ESP») | MTB SRAM 7.0, 9.0, X0, X9, Eagle… | sólo con mandos SRAM 1:1 [SB] |
| SRAM ruta mecánica | 10 y 11 de ruta | con mandos de ruta SRAM [Fab] |
| Campagnolo | por generación | con Campagnolo [SB] |
| Electrónicos (Di2, AXS, T-Type) | sin cable | compatibilidad por sistema y firmware [Fab] |

Con 11 velocidades, el paso entre piñones es el mismo en Shimano, SRAM y
Campagnolo: un mando y un cambio de una marca pueden mover el cassette de otra;
lo que no se cruza es mando con cambio [SB]. Hay poleas adaptadoras (Jtek
ShiftMate) que cambian la relación; funcionan mejor las que reducen [SB].

## Capacidad y piñón máximo

- **Capacidad total** = (plato grande − plato chico) + (piñón grande − piñón
  chico). Debe ser menor o igual a la capacidad del cambio [Taller][Fab].
- **Piñón máximo**: el más grande que el cambio puede subir; ponerle un piñón
  mayor (por ejemplo un 52 dientes de otra marca a un cambio Shimano 12) puede
  funcionar mal y anula la garantía [BM].
- **Largo de jaula** (corta, media, larga) es la forma comercial de la capacidad;
  una ficha guarda la cifra, no sólo la palabra ([K10]).
- El tornillo **B** ajusta la distancia polea–piñón; no corrige un piñón fuera de
  capacidad [PT].

## Montaje

- **Patilla del cuadro (hanger)**: cada cuadro tiene la suya; la patilla es un
  repuesto de ese cuadro ([patillas-y-montajes.md](patillas-y-montajes.md)).
- **Direct mount** de Shimano y **UDH** de SRAM son interfaces distintas; SRAM
  Transmission (T-Type) se monta **sólo** en cuadros UDH, sin patilla ([K05],
  [K13]).

## Trampas frecuentes

- Mando Shimano de 11 de ruta con cambio de 10 de ruta: mismo fabricante,
  familias distintas.
- Mando de 10 de MTB (Dyna-Sys) con cambio de 9: tira de más.
- Contar los clics del mando y creer que basta: el paso del cassette también
  cuenta.
- Mando combinado (freno + cambio): la ficha distingue la pieza, la salida y a
  qué lado va ([K49]).

## En Vinabike

- **Bici:** `drivetrainConfig` (1x11, 2x10, una velocidad) y `drivetrainSpeeds`
  (marchas **totales**: 21 en una 3×7); el mando y el cambio se juzgan por los
  piñones de atrás, que salen de la configuración ([cadenas.md](cadenas.md)).
- **Producto:** `shift_actuation_family` (la familia de tiro canónica),
  `rear_derailleur_actuation_ratio_declaration`, `shifter_actuation_mode`,
  `shifter_indexed_positions`, `rear_derailleur_total_capacity_teeth`,
  `rear_derailleur_max_teeth`, `derailleur_cage_length`,
  `rear_derailleur_mount_type`, y las tablas del fabricante
  `rear_derailleur_application_configurations` (velocidades; la tienda las
  muestra) y `*_compatibility_claims` (con qué cadena o cambio declara calzar).
- **Motor:** `_assessShifterFamilyCompatibility` y
  `_assessRearDerailleurFamilyCompatibility`; arma el conjunto de familias de tiro
  de cada lado con `_shiftActuationsFromSpecs` y las que el fabricante rechaza con
  `_refusedShiftActuationsFromSpecs`.

## Fuentes

- Sheldon Brown, «Mixing Brands of Shifters, Rear Derailers and Cassettes»,
  «6-speed … 11-speed?» y «Cable Travel Adapter» (crib sheet).
- Park Tool, «How A Rear Derailleur Works», «Rear Derailleur Adjustment».
- Bike Matrix, «Anything is compatible if you use a hammer… not!».
