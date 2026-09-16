# Asignaciones restantes · 2026-09-16 (Claude en solitario)

Cuatro productos del lote inicial sin ficha recibieron plantilla por el mismo
camino que las 720 anteriores: preimagen autenticada v2 del actor
`7bb76d88…` (capturada por SQL en transacción de sólo lectura con las claims del
actor, porque el token de la app Debug estaba vencido), propuesta validada por
`prepare_product_spec_assignments.py`, aplicación revisada con pin md5 del
escritor `assign_product_spec_template_v1` (`83e6922e…`) y del lector
`get_product_spec_research_snapshot_v2` (`e8bd4c93…`), transacción única con
preimagen exacta, versión de contrato exacta y comparación posterior, recibo por
producto y read-back autenticado completo. **Hechos técnicos escritos: 0.**

| SKU | Familia | Versión | Motivo (identidad, no compatibilidad) |
|---|---|---|---|
| 2854 | `brake_fluid` | 9 | Aceite mineral Chepark: el fabricante (BIC-860) y sus distribuidores lo publican como aceite mineral de freno para sistemas Shimano/Magura; la marca no vende otro aceite mineral |
| AE0281 | `hub_small_part` | 11 | «Adaptador de eje M10 a M14»: la ficha tiene la clase «Adaptador de eje»; rosca, largo y aplicación pendientes |
| AE0178 | `rack_basket` | 13 | Elástico de carga con ganchos (foto): clase «Correa / pulpo de carga» |
| NNV49 | `wheel_retention` | 15 | «Eje delantero bloqueo»: cierre de rueda (aguja o eje con tuerca), no eje interno de maza; producto inactivo |

Propuesta `fb3f32cf81a698dc…`, aplicación `7eb50771396a3fd4…`,
recibos 4/4 con `replayed=false`, read-back `2026-09-16T02:05:28.163095+00:00`: plantilla y
versión exactas, revisión +1, columnas ajenas a la vinculación idénticas, cero
observaciones, perfiles y referencias antes y después. Evidencia privada en
`.tmp/product-spec-catalog/assignment-remaining-20260916/`.

Cobertura Viñabike después: 1.673 productos, 59 servicios, 1.592 con plantilla
efectiva, 22 sin ella, 724 vinculaciones explícitas. Reparación del lote inicial:
724 de 746.

## Los 22 que quedan, con decisión

- **No aplica ficha técnica (10):** los nueve trabajos, diagnósticos, costos y
  notas de crédito ya adjudicados, más `M010` (cámara sin identificar + servicio).
  Salen del denominador técnico; no se cambian flags comerciales ni contables,
  que son un saneamiento aparte.
- **Casquillos `AE0266` y `AE0274` (2):** plantilla publicada; la asignación
  espera la distribución del cliente (la app instalada rechaza pares de tres
  elementos).
- **`NNV125` y `NNV126` (2):** piñón 1v Bettabikes, inactivos, sin foto ni
  modelo: rueda libre o fijo no se decide por nombre.
- **Identidad insuficiente (8):** `ACC-TES-59147`, `NNV7`, `NNV8`, `NNV15`,
  `NNV47`, `NNV102`, `NNV112`, `NNV113`. Sin descripción, modelo ni imagen;
  quedan documentados.

Fuera de alcance: `TES-NEU-03153` pertenece al tenant de pruebas `testbike`.
Adjudicación completa: [`remaining-assignment-adjudication-2026-09-16.json`](remaining-assignment-adjudication-2026-09-16.json).
