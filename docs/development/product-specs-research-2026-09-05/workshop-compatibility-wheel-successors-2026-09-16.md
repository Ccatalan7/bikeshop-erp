# Compatibilidad de taller: familias de rueda leen los sucesores — 2026-09-16

Primer bloque del consumidor que la auditoría de consumidores dejó como siguiente paso
([definition-consumer-audit-2026-09-16.md](definition-consumer-audit-2026-09-16.md), hallazgo 1):
`lib/modules/bikeshop/services/bike_product_compatibility_service.dart` leía sólo las claves
originales (`hub_spacing_mm`, `spoke_holes`, `wheel_size`, `valve_type`, `freehub_type`,
`wheel_position`), que hoy son `legacy` y el lector `get_product_spec_contexts_v1` excluye. Las
878 lecturas de nombre del día ([fill-002-name-readings-record.md](fill-002-name-readings-record.md))
cayeron justamente en los sucesores (`hub_old_mm`, `spoke_hole_count`, `bead_seat_diameter_mm`,
`valve_standard`, `hub_package_position`, `hub_drive_receiver_kind`), así que sin este bloque el
mecánico no las veía en la recomendación de repuestos.

## Qué cambia en las reglas

| Regla | Antes leía | Ahora lee (sucesor primero, original de respaldo) | Veredicto nuevo |
|---|---|---|---|
| Maza | `wheel_position`, `hub_spacing_mm`, `spoke_holes`, `freehub_type` | `hub_package_position`, `hub_old_mm`, `spoke_hole_count`, `hub_drive_receiver_kind` | «Juego delantera + trasera» → cautela por pieza, nunca se lee como delantera. `Núcleo estriado de cassette` refuta una bici de rueda libre roscada; frente a una bici de cassette deja «estriado del núcleo» por confirmar, no aprueba ni rechaza. `Rosca para rueda libre` / `piñón fijo` / `Driver BMX` siguen refutando un núcleo de cassette. |
| Llanta | `wheel_size`, `spoke_holes`, `valve_type` | `bead_seat_diameter_mm`, `spoke_hole_count` (+ los originales) | BSD medido frente a rótulo inequívoco de la bici (`29"`/`700c` = 622, `27.5"` = 584) → coincide o **incompatible** con ambos números. Rótulos ambiguos (`26"`, `24"`, `20"`, `16"`) siguen en cautela con el BSD y su rodado. |
| Cámara, cubre cámara, válvula tubeless | `valve_type` | `valve_standard` (+ `valve_type`) | Sin cambio de veredicto: `Presta (francesa)`, `Schrader (americana / auto)` y `Dunlop (inglesa)` canonizan igual que antes. |
| Rotor | ya leía `rotor_diameter_mm_value` | — | — |

Las claves sucesoras se añadieron a `_wheelRelevantSpecKeys`, que es la compuerta de «este
producto trae algo que la regla sabe leer»: sin eso, un producto sólo con sucesores no entraba a
la regla detallada.

## Evidencia

- `test/unit/bike_product_compatibility_service_test.dart`: 100 pruebas verdes (91 previas sin
  tocar + 9 nuevas en el grupo «wheel successor keys»): maza trasera por sucesores con núcleo de
  cassette (cautela, «estriado del núcleo»), ancho 142 vs 135 (incompatible), juego (cautela por
  pieza), rosca de rueda libre vs bici HG (incompatible), núcleo de cassette vs bici roscada
  (incompatible), llanta BSD 622 vs bici 29" (coincide), 559 vs 29" (incompatible), cámara y
  válvula tubeless por `valve_standard`.
- BSD por rótulo según ISO 5775 (tabla de Sheldon Brown): 622 = 29"/700c, 584 = 27.5"/650B; el
  resto de rótulos comerciales cubre varios diámetros ISO y no se convierte en veredicto.

## Qué sigue en este consumidor

Transmisión (`drivetrain_*`, `chain_*`, `freehub_type` → `freehub_bodies_accepted` en cassettes,
`cassette_cog_sequence`, `shift_actuation_family`), pedalier (`bb_shell_*`, `bb_construction`,
`spindle_interface_accepted`) y freno (`brake_type`, `caliper_hydraulic`, `piston_count`,
`mount_standard`, `hose_*`): 30 claves `legacy` más, muchas con cambio de forma (filas y
alternativas tipadas), que se migran con el mapa de cada adjudicación, no renombrando.
