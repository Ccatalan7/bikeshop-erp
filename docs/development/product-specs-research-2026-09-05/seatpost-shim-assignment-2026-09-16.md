# Casquillo de tija: los dos productos asignados tras la distribución del cliente — 2026-09-16

La plantilla `seatpost_shim` (`bdd99089…`, contrato 11) se publicó el 2026-09-15 con el par
estricto de tres elementos `[shim_inner_diameter_mm, shim_outer_diameter_mm, lt]`, y la
asignación de sus dos productos quedó en espera porque el cliente entonces publicado
(f51f3777) lanzaba `FormatException` al abrir un editor con ese par. Los flujos de macOS,
Android y Windows publicaron el 2026-09-15 a las 22:25Z desde `dc1e6093`, que contiene la
extensión del cliente `8f3d8926` (29 commits después). Con esa condición cumplida, los dos
productos se asignaron por la ruta auditada.

## Evidencia privada (`.tmp/product-spec-catalog/assignment-shim-20260916/`)

| Artefacto | SHA-256 |
|---|---|
| Ficha previa por RPC de AE0266 (`b052062b….json`) | `60ac875a07ff7471fc948d7b19b3ac35ed84da55369d9792b440fc4934eb38e3` |
| Ficha previa por RPC de AE0274 (`5e8bbaed….json`) | `92267a7903750a4b4016bed8b87beee2209c25d50d5ac61633cc9e2b22ad49d7` |
| `proposal.json` (2 decisiones, sin parches de hechos ni identidad) | `b3e68405be0e863f5401c90dafd8a9e89328011423bc57333ced5a706657e22f` |
| `rehearsal.sql` (preparador; corrido en producción con rollback: `rehearsed_assignments 2`) | `de587311e74b0500f5886b90f3a56c4597ecee23910f6e2cefc43ee4c4962c9e` |
| `reviewed-application-01.sql` (ensayo + pin md5 de las dos RPC + commit) | `392728a0386988d1d7ec35c8d5aef909c5b3a324ecdec02b6681ca098bb6959b` |
| `application-01.log` (`COMMIT`) · `readback.csv` · `receipts.csv` · `after/` | — |

## Lectura posterior

| SKU | Producto | Antes | Después |
|---|---|---|---|
| AE0266 | Adaptador de Tija de Asiento 28.6-27.2mm MUQZI | sin plantilla explícita, revisión 0, 0 observaciones | `seatpost_shim` explícita, contrato 11, revisión 1, 0 observaciones, resto del producto idéntico |
| AE0274 | Adaptador de Tija de Asiento 30-27.2mm MUQZI | sin plantilla explícita, revisión 0, 0 observaciones | `seatpost_shim` explícita, contrato 11, revisión 1, 0 observaciones, resto del producto idéntico |

Recibos persistidos en `product_spec_save_receipts`: `spec-assignment-7c5b2f98-f200-5c98-bac2-48bb04f98777 · spec-assignment-55661eaa-5690-59d7-91a6-c712f2c79ef5`.
El editor de ambas fichas ya entrega el contrato con los dos pares (`lt` para diámetros,
apoyo ≤ largo). Llenado técnico persistido: 0.

## Estado del saneamiento

Cobertura viva del tenant tras la asignación: 1.594 registros no-servicio con plantilla
efectiva, 20 sin ella (10 no materiales adjudicados y 10 que requieren identidad), 726
vínculos explícitos. Del lote inicial de 746 sin ficha quedan 20; ninguno espera ya una
distribución del cliente.
