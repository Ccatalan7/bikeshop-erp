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

## Búsqueda en portales de proveedor (hallazgo 2)

`lib/shared/services/supplier_need_portal_search.dart` traduce claves de la necesidad a tipos
de medida (`_identityKindByField`); 9 de sus 15 claves eran `legacy`. Se añadieron los sucesores
al mismo mapa, con la clave retirada al lado: `spoke_hole_count`, `hub_old_mm`,
`hub_axle_diameter_mm`, `hub_drive_receiver_kind`, `hub_package_position` (un «Juego» ya no se
lee como delantera), `valve_standard`, `valve_length_mm_value`, `sprocket_count`,
`chainring_bcd_mm`, `crank_arm_length_mm`, `bar_clamp_diameter_mm`, `pack_quantity` y los
materiales por familia. `seatpost_diameter_mm`, que el matcher devolvía `unresolved` por no ser
filtrable, es filtrable desde la publicación de flags del 09-16. 122 pruebas verdes en los cinco
archivos del portal (1 nueva: maza por `hub_old_mm` + `spoke_hole_count` y cámara por
`valve_standard` discriminan igual que las claves retiradas).

La ficha pública de la tienda (hallazgo 3) no necesita migrar claves: la página pinta lo que
devuelve la RPC, que ya excluye `legacy` y trae los sucesores con su etiqueta; su mapa de claves
sólo sobreescribe rótulos. Lo que sí faltaba, visto en vinabike.cl con la maza Novatec AE0313
(«Cantidad de agujeros para rayos: 32», «Posición de las mazas de este envase: Trasera»): los
títulos de sección de los contratos nuevos salían en inglés (`MEASUREMENT`, `PRIMARY`); ahora
`primary` → Principales, `measurement` → Medidas, `contents` → Contenido del envase,
`declaration` → Declaraciones del fabricante. Se despliega con el merge a `main`.

## Qué sigue en este consumidor

Transmisión (`drivetrain_*`, `chain_*`, `freehub_type` → `freehub_bodies_accepted` en cassettes,
`cassette_cog_sequence`, `shift_actuation_family`), pedalier (`bb_shell_*`, `bb_construction`,
`spindle_interface_accepted`) y freno (`brake_type`, `caliper_hydraulic`, `piston_count`,
`mount_standard`, `hose_*`): 30 claves `legacy` más, muchas con cambio de forma (filas y
alternativas tipadas), que se migran con el mapa de cada adjudicación, no renombrando.
