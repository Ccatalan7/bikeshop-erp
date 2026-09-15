# Suspensión y dirección: fork, rear_shock, spacer, headset_small_part

2026-09-07. Sucesor reproducible del catálogo congelado
`all-family-port-cardinality-integrated-2026-09-07.json`
(`16459826fee4c589cce37243afe4e159317212ddf1d47d6d6f1d76f9b3fadf15`) y sus casos congelados.

| artefacto | SHA-256 |
|---|---|
| `compile_suspension_headset_parts_catalog.py` | `4d132c9a3ed02237b84743848a2f5f4f524a17e02aff14b174413cd4139e3900` |
| `suspension-headset-parts-catalog-2026-09-07.json` | `fcc4728832eb9b17008be9e6ed14c897b913c82c09deb87179e3477c8ab31e2a` |
| `suspension-headset-parts-cases-2026-09-07.json` | `bd9159f36fbd02a29f312820f21bf50ca7b5cf13661ef88a315642cffaee1f72` |

4 plantillas, 42 definiciones, 50 usos, 23 casos (16 nuevos y 7 heredados de la ronda WSS).
**27/27 en el test Dart parametrizado**, incluidos los siete heredados.

Sin base de datos, migraciones, publicación, git, runtime ni subagentes. Sin llenado ni asignaciones.
El compilador importa `column`, `retire` y `table` de `compile_wheel_small_parts_catalog.py` **sin
editarlo**.

## Qué cambié, y por qué cada cosa

Sólo defectos comprobados. Ningún margen habitual se convierte en regla.

### SH-1 · `fork`: la envolvente ya tenía dueño y los escalares seguían compitiendo

Tu propia adjudicación WSS-W07 dice que el máximo no identifica la envolvente y que va una envolvente
por asiento de talón. `fork_tire_clearance_configurations` ya lo hacía, pero `bead_seat_diameter_mm`
—requerido— y `max_tire_width_mm` seguían vivos con las mismas dos magnitudes fuera de toda
envolvente, de modo que una horquilla que admite dos tamaños de rueda sólo podía declarar uno, y el
ancho máximo quedaba sin rueda a la que referirse.

Retiré los dos escalares e hice la tabla requerida. `max_tire_width_mm` es una definición **publicada**
—la usa también `fender`—, así que el cambio es de plantilla, no de definición: no la toco.

### SH-2 · `rear_shock`: una regla viva sobre un campo retirado

`shock_mount_kind` era `legacy` y a la vez `required_when: always`. La regla es inerte —un campo
legacy se descarta antes de validar— pero se lee como obligatoria. Es la misma limpieza que hiciste en
el bloque de puntos de contacto. `shock_end_configurations` ya nombra el extremo de cuerpo y el de
vástago por separado.

### SH-3 · `rear_shock`: medidas sólo en milímetros, con el fabricante publicando pulgadas

FOX documenta FLOAT DPS y FLOAT X en pulgadas —7.875 x 2.00, 7.875 x 2.25, 8.50 x 2.50, distancia
entre ojales por recorrido— mientras los amortiguadores actuales son métricos. Con
`eye_to_eye_mm` y `stroke_mm` sólo en milímetros, registrar un 7.875" obliga a convertir, y el
redondeo lo elegimos nosotros.

Agregué `shock_size_declarations` con magnitud, valor, **unidad** en mm o in, configuración,
condiciones y fuente, y retiré los dos escalares. Es la misma forma que ya aceptaste para presión y
para apriete. Las dos notaciones conviven en el mercado, así que la unidad viaja con la cifra en vez
de decidirse una vez para la familia.

### SH-5 · `headset_small_part`: un expansor se especifica por un rango, y por dos tornillos

Un tapón expansor se declara por el **rango** de diámetro interior de espiga que abraza, más su
profundidad de inserción, y lleva **dos aprietes distintos**: el del tornillo de la tapa y el del
tornillo de expansión. La plantilla tenía un único `steerer_inner_diameter_mm` y ningún campo de
profundidad ni de apriete.

Agregué `headset_part_interfaces` —zona, superficie de calce, mínimo y máximo interiores con par
ordenado, profundidad, designación— con el rango condicionado a la superficie interior, y
`headset_torque_specifications` con tornillo, forma de la cifra, valor o rango con par ordenado y
unidad, calcada de la tabla de apriete de puños. Retiré el escalar.

*Fuente y su límite:* la ficha del tapón de compresión de Wolf Tooth publica un rango de espiga, una
profundidad de inserción y dos aprietes. Los valores concretos que vi difieren entre variantes del
mismo producto, así que **no fijo ningún rango en el vocabulario**: el hallazgo es la forma —rango, no
número—, y las cifras van en la fila, declaradas por el fabricante.

### `spacer`: sin cambios

`spacer_system` separa dirección de pedalier, y diámetro interior, espesor y exterior están bien
puestos. No encontré defecto y no lo toqué.

## Un defecto que NO parcheé, porque no me corresponde

`thru_axle_thread` no ofrece **M12 x 1.25**, y el TRA225 de Robert Axle es exactamente ese paso. Ya lo
reporté en WS-9, y ahora es peor de tocar: la definición **ya está publicada** y la usan cuatro
familias — `hub`, `fork`, `wheel_retention` y `frame` —, con `wheel_retention` publicada. Añadir la
opción es un forward que las alcanza a todas, así que lo dejo señalado y no lo modifico aquí. En
`fork` el campo sigue vivo y condicionado a los tres ejes pasantes, de modo que hoy una horquilla con
ese paso no se puede describir.

## Casos

16 nuevos, y los 7 heredados siguen pasando —incluida la envolvente FOX 40 y la pila de coronas
invertida—, que es la comprobación de que retirar los escalares no rompió lo ya adjudicado.

| caso | tipo | qué demuestra |
|---|---|---|
| `sh_fox_imperial_sizing` | positivo | dos filas en pulgadas, tal como FOX las publica |
| `sh_metric_sizing` | positivo | el mismo campo en milímetros, sin conversión |
| `sh_shock_size_without_unit` | desconocido | `row_incomplete` no bloqueante |
| `sh_shock_size_absent` | desconocido | `required_missing` no bloqueante |
| `sh_expander_bore_range` | positivo | rango de espiga y profundidad |
| `sh_headset_two_scopes` | positivo | expansor y araña conviven como dos zonas |
| `sh_headset_bore_reversed` | negativo | `row_shape` bloqueante |
| `sh_headset_bore_outside_scope` | negativo | `row_field_applicability`: sin superficie interior no hay rango |
| `sh_headset_two_fasteners` | positivo | dos aprietes distintos del mismo tapón |
| `sh_headset_nominal_is_not_range` | negativo | `row_field_applicability` |
| `sh_headset_torque_reversed` | negativo | `row_shape` |
| `sh_fork_envelope` / `sh_fork_two_wheel_sizes` | positivo | una y dos envolventes |
| `sh_fork_duplicate_bead_seat` | negativo | `row_shape` por `unique_by` |
| `sh_fork_envelope_absent` | desconocido | `required_missing` no bloqueante |

Una corrección mía durante la corrida: esperaba `row_unique` para el asiento de talón duplicado y el
motor lo reporta como `row_shape`, igual que un par invertido, porque ambos salen del esquema de
filas. Corregí la expectativa, no el motor.

## Lo que no hice

No toqué el catálogo congelado, ninguna definición compartida ni el compilador que importo. No
convertí ninguna unidad. No fijé rangos de espiga, holguras ni aprietes en el vocabulario: todos van
declarados por fila. Ninguna fixture prueba calce.

Compuertas sin cambio: `fill_allowed`, `compatibility_rules_integrated`,
`all_product_assignment_review_complete`, `all_family_domain_review_complete`.
