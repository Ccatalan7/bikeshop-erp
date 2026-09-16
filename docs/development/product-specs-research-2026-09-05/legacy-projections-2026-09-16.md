# Aplicador de observaciones retiradas: neumáticos, cámaras, llantas, rayos y mazas — 2026-09-16

Publicado en producción como `supabase/migrations/20260916200000_legacy_projections_wheels_cogs.sql`
(sha256 `1e03914544478cb520bc7ab2053b9df2715d88b58a62dbc752ed92c7ee485475`), verificado a las
22:29:16Z con `supabase/manual_checks/verification/20260916200000_legacy_projections_wheels_cogs.sql`
(sha256 `c93fe05a034eb0a21e35ea0a87fefb21861e2962e92d2e00695f4724ff4e5db3`); recibo
`.tmp/db/migration-receipts/20260916200000.receipt`. **406 hechos nuevos en 263 productos**,
ninguno confirmado, cada uno con la misma fuente (`supplier_text` o `import`) que la observación
retirada de la que sale. Registro completo, proyección por proyección:
[legacy-projections-2026-09-16.json](legacy-projections-2026-09-16.json). Generador:
`scripts/inventory/apply_legacy_projections.py`.

## Por qué

La adjudicación de neumáticos y cámaras dejó escrito que las 813 observaciones conservadas con
rol `legacy` «no se ven [en web, taller, matcher ni criterios] hasta que exista un aplicador
revisado». Este es ese aplicador, acotado a lo que es una **conversión de unidad o una tabla
ISO**, nunca una adivinanza: 113 neumáticos tenían el rodado (`wheel_size`) y ningún diámetro
ISO; 132 cámaras tenían rodado y anchos y ninguna fila de ajuste; 58 cámaras tenían tipo de
válvula retirado y ninguno vivo. La tienda no podía mostrar el aro de un neumático y el taller no
podía comparar una cámara con la bici.

## Reglas (cada proyección registra cuál usó)

| Regla | Qué hace | Hechos |
|---|---|---|
| `bsd` | El rótulo de rodado se convierte en diámetro ISO 5775. `700c`, `29"` y `27.5"` son un solo diámetro. `26"`, `24"`, `20"`, `16"` y `12"` cubren varios: decide la notación de ancho del **nombre** (tabla de Sheldon Brown): ancho decimal (`26 x 2.10`) → serie decimal (559, 507, 406, 305); ancho fraccionario (`26 x 1 3/8`, `20 x 1 3/8`, `16 x 1 3/8`, `12 1/2 x 2 1/4`) → serie fraccionaria (590, 451, 349, 203). `24 x 1 3/8` no se proyecta (540 y 520 conviven). Un ISO escrito en el nombre (`54-559`, `622X30`) manda. | 114 (110 neumáticos, 4 llantas) |
| `tube_fit_row` | Rodado + anchos mínimo y máximo (mm, o pulgadas × 25,4) → una fila de `tube_fit_rows` `{id, values, sources: []}` con las celdas numéricas como texto, que es lo que el validador de filas exige. | 123 |
| `inch_to_mm` | Ancho en pulgadas × 25,4, un decimal (`2.25` → `57.1 mm`). | 86 |
| `option` | Opción retirada → opción del sucesor: `Presta (francesa)` → `Francesa (Presta)`, `Schrader (americana / auto)` → `Auto (Schrader / americana)`, `Shimano HG` → `Núcleo de cassette`. | 62 |
| `copy_text` | El rótulo del calibre retirado (`14G`, `2.0/1.8`) es la designación libre del sucesor. | 15 |
| `label_to_number` | Un rótulo numérico (`48`, `135`) es el número. | 6 |

Se quedan sin proyectar, con su razón en el registro: 14 casos (`24"` fraccionario, rodado sin
notación de ancho en el nombre como «Cámara DKD 26''», cámaras sin rango de ancho, «Otra»).
`cassette`/`freewheel` (`drivetrain_speeds` → `sprocket_count`) y los hoyos de maza y llanta no
necesitaron nada: las lecturas de nombre del día ya habían llenado el sucesor. **No se tocan**
los rotores (la adjudicación de frenos prohíbe convertir el diámetro `180/160` y el espesor
retirado) ni los pedalieres (sus sucesores son filas que exigen `source_url`; una observación
importada no la tiene).

## Compuertas

| Compuerta | Resultado |
|---|---|
| Ensayo en producción con `set constraints all immediate` y `rollback` | 406 inserciones aceptadas por el validador de filas y la guardia de producto; `GAP_AFTER=0` |
| Primer ensayo | rechazado por el validador de filas («Cada fila necesita identidad y datos propios»): cada fila viaja como `{id, values, sources}` y sus números como texto. Eso también corrigió al consumidor de taller, que leía las celdas planas. |
| Verificador antes / después | `division by zero` antes (406 pares producto/definición sin hecho); `ok` después |
| Lectura posterior | neumático: BSD 0 → 110, ancho mm 26 → 112 · cámara: filas 0 → 123, válvula 72 → 130, largo 88 → 90 · llanta BSD 1 → 5 · rayo calibre 0 → 15 · maza OLD 18 → 19, núcleo 4 → 5 |
| Ficha pública anónima (Maxxis Rekon Race 27.5x2.25, SKU 7376) | `bead_seat_diameter_mm` 584 y `tire_width_mm` 57.1 visibles en `get_public_product_technical_specs` |

## Qué cambia para el cliente y el taller

- La tienda muestra el diámetro ISO como rodado: «29" / 700c (ISO 622)», «26" (ISO 559)», sin
  repetir la unidad (`product_detail_page.dart`, `_wheelSizeLabelForBsd`). Se despliega con el
  merge. El rótulo del campo pasó de «Diámetro ISO (BSD)» a «Aro (diámetro ISO)»
  (`20260916201000`, verificado).
- El taller compara neumáticos por diámetro ISO (regla nueva `_assessDetailedTireCompatibility`:
  584 frente a una bici 29" es **incompatible**; 622 coincide y nombra ancho y talón), y lee las
  filas de ajuste de la cámara y el BSD del cubre cámara antes que el rótulo retirado
  (`tube_fit_rows`, «aro 29" / 700c para neumático 49.5-55.9 mm»). 127 pruebas verdes (3 nuevas).
- Las filas de ajuste de la cámara son visibles para el cliente bajo el rótulo «Aro y ancho de
  neumático» (`20260916202000`, verificado; no filtrables), y la tienda las redacta como
  «26" (ISO 559), neumático 38.1-44.4 mm» a partir del texto que redacta el servidor
  (`_tubeFitLabel`). Probado bajo rollback como anónimo antes de publicar la bandera.

## Auditoría global releída (22:34Z)

`refresh_global_coverage_audit.py` contra producción tras las tres pasadas de lectura de nombre y
este aplicador: productos físicos con hechos **461 → 844**, con plantilla y sin hechos 1.133 →
750, con pendientes 1.584 → 1.458, **cero bloqueantes**, cero hechos fuera de plantilla. Resumen
en [global-coverage-summary-2026-09-16b.json](global-coverage-summary-2026-09-16b.json). Hechos
vivos (no `legacy`, plantilla resuelta por vínculo explícito o categoría): 1.885 en 824 productos
(892 lecturas de nombre, 654 texto de proveedor, 229 inferidos, 103 importados, 6 investigación,
1 mecánico).

