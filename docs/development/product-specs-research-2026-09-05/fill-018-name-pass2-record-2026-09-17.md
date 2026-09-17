# fill-018 · Segunda pasada de nombres con vocabulario de tienda (2026-09-17)

**Qué es.** Una segunda lectura de los nombres de **todo el catálogo activo** (1 520 fichas con
plantilla, con y sin stock), con dos cambios de fondo respecto a la primera pasada (fill-002):

1. El lector del servidor aprende **términos de lectura**: cada opción de lista y cada campo
   booleano declara las frases con que la tienda lo nombra («QR», «c/bloqueo», «(CL)»,
   «FreeWheel», «W/O CG», «perforado», «macizo», «DER.», «d/pared», «1-1/8», «apernar»,
   «6 vel / 8v / 10s», «1/4», «prostático»…). Antes sólo valía la etiqueta de la opción o las
   palabras largas del rótulo del booleano, así que ese vocabulario se quedaba en el nombre.
2. Reglas por familia para **70 familias** (antes 27), con el orden que exige la guardia de
   coherencia: la posición y los indicadores «lleva núcleo» / «para disco» se leen antes de la
   clase que abren.

Nada se infiere entre campos ni se convierte de unidad: cada hecho cita el pedazo literal del
nombre y el RPC `record_product_spec_reading_v1` lo vuelve a comprobar en vivo.

## Migraciones (las tres aplicadas en producción con verificador y stamp)

| Migración | Qué hace |
|---|---|
| `20260916280000_name_reading_terms` | `spec_definition_values.reading_terms text[]`, `spec_definitions.reading_terms` / `reading_terms_false`; `spec_terms_hit_internal_v1`; `spec_boolean_from_terms_internal_v1` (la vieja `spec_boolean_from_field_vocabulary_internal_v1` delega); `spec_reading_rejection_internal_v1` puntúa `[1, 1000]` a la opción cuyo término está en la cita (más que cualquier cobertura parcial de una hermana), y los booleanos suman rótulo + términos afirmativos y respetan los negativos; el digest del recibo incluye los términos. Primera tanda: 149 opciones y 24 booleanos. |
| `20260917010000_name_reading_terms_vocabulary` | Segunda tanda de términos que pidieron las reglas (88 opciones, 13 booleanos). Trampa: `array_agg(distinct …)` sobre un arreglo vacío devuelve `null` y la columna es `not null` → `coalesce(…, '{}')`. |
| `20260917020000_name_reading_terms_specificity` | Entre dos opciones con término en la cita gana **la frase más larga** (`spec_terms_best_length_internal_v1`; puntaje `[1, 1000 + largo]`); misma frase sigue empatando y no se lee. Reparte el vocabulario de las presentaciones: «juego / jgo / set / par / del-tra» nombran «Par de mecanismos» (herraduras) y «juego de frenos» el «Par delantero y trasero» (hidráulicos). Tercera tanda de términos. |

pgTAP `supabase/tests/spec_name_reading_terms.sql` (38 verdes): término entero y no prefijo,
normalización igual que la cita, término ajeno no lee la opción, media etiqueta pierde contra
el término entero de la hermana, empate de frases del mismo largo, especificidad, negación
delante de un término, término negativo, conflicto sí/no, digest que cambia con el vocabulario,
y la función de rótulo intacta.

`supabase/tests/spec_name_reading_evidence.sql` falla en local **antes** de llegar a estas
funciones («el campo no pertenece a la ficha técnica activa»): su fixture de plantilla quedó
vieja frente a las migraciones del 14–15 (la suite ya fallaba en los logs del 2026-09-15). No es
de esta ronda; queda anotado.

## Reglas (`scripts/inventory/spec_name_reading_rules.py`)

- La réplica offline copia el nuevo `spec_reading_rejection_internal_v1` (términos, largo,
  booleanos con negativos) y lee del catálogo exportado las columnas `value_terms`
  (`label>>t1;t2||…`), `reading_terms` y `reading_terms_false`.
- Lectores nuevos: `only_if` (una golilla mide espesor, no largo), `single_cog` (un piñón
  libre de un diente es su menor y su mayor), `M_THREADS` (M5…M22 sin tragarse «M15» por
  «M5»), `PACK_UNITS` (unidades/pcs/pzs sin contar «MINIMO 20 PCS»), fracciones con
  guardia (`1/8` no es «1-1/8» ni «1 1/8»).
- Compuertas que enseñó la guardia en el ensayo (37 rechazos de 1 720 en la primera corrida,
  0 de 1 705 en la segunda): `bearing_element_retention` sólo aplica a cartuchos; `pulley_teeth`
  sólo a roldana individual; `thread` no aplica a golillas; `grip_length_mm` sólo a puño por
  unidad; accionamiento y estilo de manilla no aplican a un par sin lado; `rated_power_w` sólo
  a cargadores; las presentaciones de `rim_brake` son «Par de mecanismos», no «Par delantero y
  trasero»; el hijo «… - Delantero» de un juego no es un par.
- Lo que el contrato de la plantilla restringe con `allowed_options` no lo ve la función de
  rechazo (juzga contra todas las opciones de la definición): «Plástico» en portacaramagiolas
  (el contrato pide «Plástico / nylon» y el término de la hermana «Plástico» gana), «Acero» en
  piolas (galvanizado/inoxidable/recubierto) y «Carbono» en cintas quedan fuera a propósito.

## Corrida

1. `spec_name_reading_rules.py` sobre el catálogo vivo → 1 705 candidatos en 1 047 productos
   predichos `recorded`; descartados antes de llamar: 328 `kept_existing` (campos con hecho
   investigado o importado), 5 ambiguos (dos lecturas distintas en un mismo campo), 21 que la
   réplica rechaza (cita sin el valor, número con signo, etc.).
2. `fill_name_readings.py --mode dry` (una transacción por 40 productos, rollback):
   1 705 `recorded`, 0 rechazos, 0 fallos. Réplica y guardia coinciden 1 705 / 1 705.
3. `--mode commit`: 1 705 `recorded`. Lectura de vuelta en producción: **815 hechos
   `name_reading` nuevos en 576 productos**; los otros 890 eran campos ya leídos en fill-002 que
   ahora tienen recibo con el vocabulario nuevo (repetir la lectura no duplica el hecho).

## Medición por campos de la ficha (no por productos tocados)

Campos filtrables no legacy del contrato de cada plantilla, hechos presentes en la raíz del
producto (`bindings.csv` antes y después, tenant Viñabike, activos con plantilla):

| | Fichas | Campos | Llenos | Sólo nombre | Investigado / importado | Fichas sin nada |
|---|---:|---:|---:|---:|---:|---:|
| Antes | 1 520 | 11 633 | 1 887 (16,2 %) | 892 | 995 | 676 |
| Después | 1 520 | 11 633 | 2 702 (23,2 %) | 1 707 | 995 | 266 |

Por familia (campos llenos por ficha, promedio; sólo las que cambiaron o tienen ≥10 fichas):

| Familia | Fichas | Campos/ficha | Antes | Después | Fichas vacías |
|---|---:|---:|---:|---:|---:|
| hub | 50 | 19 | 2,36 | 3,60 | 7→2 |
| hub_axle | 20 | 5 | 1,45 | 2,25 | 0→0 |
| fastener | 22 | 15 | 0,00 | 2,82 | 22→0 |
| bearing | 16 | 16 | 0,00 | 2,00 | 16→0 |
| crank_arm | 7 | 7 | 0,00 | 3,00 | 7→0 |
| hub_small_part | 8 | 5 | 0,00 | 2,88 | 8→0 |
| seat_clamp | 11 | 7 | 0,36 | 2,00 | 9→0 |
| chain_link | 9 | 7 | 1,33 | 2,89 | 5→0 |
| tubeless_valve | 8 | 6 | 0,75 | 2,25 | 5→0 |
| workshop_chemical | 30 | 5 | 0,20 | 1,23 | 28→7 |
| workshop_tool | 44 | 4 | 0,20 | 1,02 | 35→4 |
| rider_glove | 33 | 6 | 0,00 | 1,06 | 33→1 |
| control_small_part | 19 | 6 | 0,00 | 1,05 | 19→2 |
| rim_brake | 27 | 1 | 0,00 | 0,56 | 27→12 |
| rear_derailleur | 38 | 5 | 0,42 | 1,00 | 24→13 |
| saddle | 22 | 7 | 0,45 | 1,14 | 12→2 |
| chain | 35 | 8 | 0,71 | 1,31 | 15→5 |
| pump | 15 | 7 | 0,87 | 1,47 | 6→0 |
| pedal | 33 | 10 | 1,00 | 1,58 | 9→2 |
| brake_pad | 49 | 10 | 1,02 | 1,59 | 17→5 |
| grip | 27 | 13 | 0,07 | 0,67 | 25→12 |
| headset | 15 | 4 | 0,00 | 0,60 | 15→6 |
| crankset | 31 | 11 | 1,16 | 1,68 | 8→4 |
| freewheel | 28 | 6 | 1,89 | 2,39 | 7→0 |
| handlebar | 14 | 18 | 1,57 | 2,21 | 3→1 |
| shifter | 36 | 6 | 1,67 | 2,06 | 7→2 |
| lock | 31 | 10 | 1,39 | 1,77 | 2→1 |
| light | 18 | 3 | 0,72 | 1,06 | 5→5 |
| fork | 11 | 18 | 3,64 | 4,09 | 2→2 |
| stem | 17 | 10 | 2,06 | 2,47 | 1→1 |
| chainring | 17 | 9 | 1,71 | 2,00 | 1→1 |
| brake_caliper | 11 | 9 | 1,45 | 1,73 | 1→1 |
| brake_lever | 18 | 13 | 0,33 | 0,61 | 14→9 |
| bottle_cage | 11 | 11 | 0,00 | 0,27 | 11→8 |
| seatpost | 13 | 12 | 1,85 | 2,08 | 2→0 |
| spoke | 56 | 9 | 1,07 | 1,29 | 3→3 |
| helmet | 13 | 8 | 0,77 | 0,92 | 3→3 |
| front_derailleur | 18 | 4 | 0,72 | 0,83 | 9→8 |
| control_cable | 17 | 2 | 0,00 | 0,35 | 17→11 |
| rim | 44 | 17 | 2,61 | 2,70 | 0→0 |
| cassette | 32 | 6 | 3,12 | 3,19 | 0→0 |
| rotor | 18 | 8 | 1,50 | 1,56 | 2→2 |
| tire | 118 | 7 | 2,40 | 2,42 | 5→3 |
| tube | 133 | 5 | 3,66 | 3,67 | 0→0 |
| bottom_bracket | 38 | 4 | 1,87 | 1,87 | 0→0 |
| derailleur_hanger | 26 | 2 | 0,00 | 0,00 | 26→26 |
| food_beverage | 19 | 13 | 0,00 | 0,00 | 19→19 |
| hydraulic_fitting | 10 | 1 | 0,00 | 0,00 | 10→10 |
| wheel_retention | 13 | 2 | 0,54 | 0,54 | 6→6 |

Familias chicas que también pasaron de 0: pedal_peg, rider_bag, accessory_mount,
cycle_computer, consumer_electronics, tubeless_tape, tube_repair, audible_signal,
handlebar_covering, bottom_bracket_bearing, headset_small_part, kickstand, rider_apparel,
rim_strip, seatpost_shim, souvenir, tubeless_consumable, derailleur_pulley, bike_bag, fender,
bottle, spacer, rack_basket, hydraulic_disc_brake (métrica completa en
`scratchpad/metrics-before.json` / `metrics-after.json` de la sesión).

## Lo que el nombre no puede dar (y por eso sigue la investigación OEM)

En la maza, de 19 campos el nombre alcanza a lo más 9 (posición, hoyos, OLD, diámetro de eje,
tipo de eje, para disco, lleva núcleo, tipo de núcleo, rodamientos). Los otros 10 son medidas
de fabricante: centro a brida y PCD por lado, distancia entre bridas, diámetro de hoyo de rayo,
tipo de rayo, eje pasante incluido, montaje de disco, piezas del juego. Lo mismo en llantas
(ERD, anchos, perfil), horquillas, cadenas (ancho externo, paso) y pedalieres. Esa mitad sólo
entra con la ficha del fabricante, con o sin stock: es el siguiente bloque (Novatec D041SB /
D042SB / D442SB, Formula, Blooke, ZTTO, Weinmann, KMC…).

## Quedan fuera con motivo

- Contratos con `allowed_options` distintos de la lista de la definición (portacaramagiola
  «Plástico», piola «Acero», cinta «Carbono»): la función de rechazo juzga contra la definición
  entera; leerlos pide que la función conozca la plantilla del producto.
- «Un mecanismo (un extremo)» de herraduras sueltas: «delantero / trasero» significa un freno
  completo en los hidráulicos y un mecanismo en las herraduras; un término global mentiría en
  una de las dos.
- «CAMBIO MEDIA PISTA» no es pata media; «Patín Eléctrico» es un scooter, no un patín de freno;
  «Perno Biela M15 … Integrado» no es perno de eje cuadrado; «8x1» y «Kettenspray» son un solo
  token normalizado. Todos guardados con `unless` o sin regla.
