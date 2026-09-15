# Mandos y desviadores: candidato sin aplicar — 2026-09-08

Sucesor local para las tres originales `shifter`, `rear_derailleur` y
`front_derailleur`. **No aplicado.** Sin escrituras de producción, migración,
publicación, asignaciones ni llenado; sin commit, push ni runtime. Este
documento contiene sólo agregados, metadatos y ejemplos OEM públicos.

## 1. Entradas fijadas y salida

| entrada | sha256 |
|---|---|
| `all-family-port-cardinality-integrated-2026-09-07.json` | `16459826…fadf15` |
| `all-family-port-cardinality-cases-integrated-2026-09-07.json` | `329ad3e5…3716d7` |
| `existing-shifting-preimage-2026-09-08.json` | `9ed37fdd…9cf3b3e` |

| salida | sha256 |
|---|---|
| `scripts/inventory/compile_existing_shifting_catalog.py` | `4ab70f7c…7232015` |
| `existing-shifting-catalog-2026-09-08.json` | `740c13a2…398cf4` |
| `existing-shifting-cases-2026-09-08.json` | `0ecc0ecc…53f69c` |

La preimagen se capturó con `preimage_query` y `scripts/db/query.sh production`
en un único SELECT sin `--out` (`captured_at 2026-09-08T18:35:14.97963+00:00`) y
trae **21 definiciones publicadas** para las tres familias. Salida: 3
plantillas, 40 definiciones, 54 usos de campo, **33 casos ejecutables y 7
pendientes**. El compilador es determinista —los ids nuevos son `uuid5` sobre la
clave— y el `catalogue_sha256` de los casos corresponde al catálogo publicado
arriba.

**Las 21 definiciones publicadas se reutilizan sin una sola diferencia** de
`id`, rótulo, tipo, unidad, dominio ni reglas, comparadas campo a campo contra
la preimagen. Las 19 definiciones nuevas tienen alcance de familia.

| plantilla | campos | nuevos | retirados a legacy |
|---|---|---|---|
| `shifter` | 17 | 5 | 5 |
| `rear_derailleur` | 18 | 6 | 2 |
| `front_derailleur` | 19 | 9 | 5 |

Un campo retirado conserva su observación: queda en la plantilla con rol
`legacy`, el motor lo despoja antes de validar y por eso no bloquea ni deja
pendiente. Nada se borra.

## 2. Los cuatro ejes que separa el candidato

1. **La pieza y el envase.** Un envase «Par» trae dos mandos distintos. Los
   escalares del mando —posiciones indexadas, diámetro de manillar, estilo,
   accionamiento— sólo aplican al envase individual; el par responde con
   `shifter_units`, una fila por mando con su lado, su mecanismo y su
   documento, y `shifter_unit_count` cerrando la cardinalidad. Un mando
   individual **no** puede listar unidades de envase, y un par **no** puede
   cargar un escalar por los dos.
2. **La interfaz de mando.** `shifter_control_style` es la forma de la palanca
   y no una compatibilidad: dos gatillos distintos no son intercambiables por
   ser gatillos.
3. **El accionamiento.** El indexado vive en el mando —Sheldon: «The detents
   (click stops) that provide indexing are in the shifters»—, así que el
   accionamiento es `shifter_actuation_mode` y el desviador nunca declara
   fricción o indexado como mecanismo propio. Las posiciones indexadas sólo
   son admisibles con modo indexado o conmutable; declaradas sobre un mando de
   fricción, bloquean.
4. **La declaración documentada.** Cada familia tiene su tabla de
   declaraciones con `scope_kind` en «Modelo documentado» o «Interfaz o
   estándar documentado». Una declaración de modelo exige marca y modelo; una
   declaración de interfaz **no puede** nombrar un modelo. Ninguna convierte
   marca, velocidades, jaula o diámetro en compatibilidad universal.

Además, por familia:

- **Trasero.** El sentido de retorno del resorte es un eje propio del modelo
  (Sheldon: «Shimano Rapid Rise derailers work the opposite way»), separado del
  embrague: un nombre de diseño del cuerpo no prueba embrague. La uña que
  sostiene la tuerca del eje o el cierre rápido es **contenido del envase**, no
  la interfaz que ofrece el cuadro; la referencia de esa pieza sólo es
  admisible si el envase la trae. La capacidad total es la que publica el
  fabricante, no una suma de rangos de otras piezas.
- **Delantero.** El diámetro de abrazadera publicado es un `single_select` de
  un solo valor y **tres de los quince** registros del alcance nombran dos
  diámetros —otros cinco nombran uno—; se retira y responde
  `front_derailleur_clamp_options`, una
  fila por diámetro que dice si necesita adaptador y si ese adaptador viene en
  el envase. El plato de diseño es un rango ordenado (mínimo y máximo), porque
  Sheldon documenta que «new models are optimized for particular ratios».
  La ruta del cable, la geometría de la jaula y la posición del cable en el
  perno son tres campos distintos: anclar por fuera del perno mueve la jaula
  menos por cada milímetro de cable, y eso no es la dirección desde la que
  llega el cable.

## 3. Lo implementado y ejecutado

```
fvm flutter test --no-pub test/unit/product_spec_integrated_catalog_test.dart \
  --dart-define=SPEC_CATALOG_INPUT=…/existing-shifting-catalog-2026-09-08.json \
  --dart-define=SPEC_CATALOG_CASES=…/existing-shifting-cases-2026-09-08.json
```

`00:01 +36: All tests passed!` — 3 pruebas de plantilla y metadatos de filas y
**33 casos**: positivos, negativos bloqueantes y pendientes. Salida real, no
resumen.

Seis mutantes acotados sobre el catálogo generado, cada uno corrido con los
mismos casos, para probar que las compuertas nuevas cargan peso. Cada mutante
mata exactamente el caso que lo nombra y ningún otro:

| mutante | caso que cae |
|---|---|
| aplicabilidad abierta de posiciones indexadas | `sh_a_friction_shifter_has_no_indexed_positions`, `sh_a_pair_cannot_carry_one_scalar_count` |
| sin `unique_by` de lado en las unidades | `sh_the_same_side_twice_blocks` |
| sin condiciones de fila en las unidades | `sh_a_friction_unit_has_no_indexed_positions` |
| aplicabilidad abierta de opciones de abrazadera | `fd_a_braze_on_derailleur_has_no_clamp_options` |
| aplicabilidad abierta de la referencia de uña | `rd_an_adapter_reference_without_the_adapter_blocks` |
| sin `scalar_ordered_pairs` de platos | `fd_an_inverted_chainring_range_blocks` |

Dos conductas del motor **medidas aquí**, no leídas:

- Una columna de fila **requerida estáticamente** que falta emite
  `row_incomplete`, no `row_required_missing`. El segundo código quedó para la
  columna requerida **por condición** —una declaración de modelo sin su
  modelo—. Los dos son no bloqueantes y no son intercambiables al escribir un
  caso.
- `range_order` emite en **los dos extremos** del par ordenado, no sólo en el
  segundo. Un caso que espere un único campo falla por conjunto exacto.

## 4. Lo representado sin certificación mecánica

Los 33 casos son representaciones sintéticas: `facts_verified_for_product` y
`automatic_fill_authorized` van en falso en todos, y el catálogo lleva
`mechanical_coverage_complete: false`. Ninguno certifica un montaje real ni
autoriza llenar un producto.

Se representa, sin certificar:

- Que un par de mandos admite exactamente dos lados distintos. El dominio de
  `unit_side` y el `unique_by` lo imponen; que un envase concreto traiga dos
  mandos y no tres es un hecho de ese envase.
- Que la abrazadera acepta un adaptador incluido. La tabla lo representa; qué
  trae la caja se llena con el envase a la vista, nunca con el rango escrito
  en el título.
- Que la relación de accionamiento es un texto transcrito del documento. No se
  deduce del número de velocidades ni del nombre comercial del sistema.

## 5. Fuentes exactas y límites OEM

Abiertas y leídas en esta ronda:

- `https://www.sheldonbrown.com/derailer-adjustment.html` — los topes que
  producen el indexado están en el mando; Rapid Rise trabaja al revés; la uña
  adaptadora se sostiene con la tuerca del eje o el cierre rápido; el cable por
  fuera del perno mueve la jaula menos por cada milímetro de cable; los modelos
  nuevos están optimizados para relaciones concretas.
- `https://www.parktool.com/en-us/blog/repair-help/how-a-rear-derailleur-works`
  — el mando indexado mueve el cable una cantidad predeterminada por clic.
- `https://www.parktool.com/en-us/blog/repair-help/front-derailleur-adjustment`
  — el soporte braze-on del cuadro frente a la abrazadera del desviador; el
  mando de fricción no tiene ajuste de índice.

**Límite OEM de esta ronda:** los sitios técnicos de fabricante no se
abrieron. `si.shimano.com` y `bike.shimano.com` respondieron 403 y las páginas
de producto de SunRace y microSHIFT respondieron 404, por curl y por WebFetch.
**Ningún manual de fabricante se cita como leído**, y por eso no se transcribe
ninguna relación de accionamiento, capacidad, tabla de abrazaderas ni límite de
plato desde una fuente que no se abrió. Dos páginas de Sheldon que se
buscaron por nombre (`front-derailer.html`, `front-derailleur.html`) devuelven
404: el contenido de desviador delantero que se cita vive dentro de la página
de ajuste ya listada.

## 6. Bloqueos reales de integración

1. **Asignación de mandos combinados.** Varios registros del alcance son
   mandos integrados con la maneta de freno. La familia
   `brake_shift_combined_control` ya existe; el movimiento necesita la cola de
   asignación y evidencia del producto. **No se ejecuta por el título.**
2. **Identidad del producto.** Los títulos llevan códigos de fabricante
   mientras `model` y `manufacturer_sku` están vacíos en casi todos los
   registros del alcance —3 de 82 tienen modelo, ninguno tiene MPN—. Eso se
   resuelve en la identidad del producto, nunca en un segundo almacén dentro
   de la ficha.
3. **Publicación y adopción.** El publicador, el SQL, la adjudicación y la
   integración final son de Root. Este paquete no toca el motor, la GUI, las
   migraciones ni el checkpoint global.
4. **Relación OEM dirigida y ronda de editor real.** `ProductSpecRelation` y
   `spec_relation_assess_internal_v1` ya existen con pruebas y este paquete no
   los ejercita; la validación en el editor real tampoco está corrida.
5. **Las siete pendencias** del archivo de casos —incluidas las tres de
   arriba— viajan con su razón en `pending_cases` y ninguna se resuelve
   leyendo un nombre de producto.
