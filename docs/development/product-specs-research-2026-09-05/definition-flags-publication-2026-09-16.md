# Flags de visibilidad y filtro publicados — 2026-09-16

Publicado en producción como `supabase/migrations/20260916150000_definition_visibility_flags.sql`
(sha256 `882c76cd1a177341c79b1892d1d107aee0dbd1c6234502d6a8af920defbcdfd0`), verificado con
`supabase/manual_checks/verification/20260916150000_definition_visibility_flags.sql`
(sha256 `f9f77a65752620ee9329d5c0f406da9ecc0066d370548355f417506f00a4d676`), recibo
`.tmp/db/migration-receipts/20260916150000.receipt`. Compilado por
`scripts/inventory/compile_definition_flags_publication.py` desde la propuesta del mismo día
([definition-flags-proposal-2026-09-16.md](definition-flags-proposal-2026-09-16.md)), sin
recortes: la regla «escalar y no evidencia» sobre campos activos.

Decisión tomada por Claude bajo la instrucción del dueño de decidir todo con el negocio como
criterio: un dato técnico que el cliente no puede ver en la tienda ni pedir al asistente no vende
nada; sin estos flags, llenar las 68 familias nuevas habría sido trabajo invisible.

## Qué cambió

| Medida | Antes | Después |
|---|---|---|
| Definiciones globales visibles al cliente | 264 | 626 |
| Definiciones globales filtrables | 251 | 556 |
| Plantillas activas con al menos un campo activo visible | 39 de 107 | 100 de 107 |
| Versiones de contrato de las 107 plantillas (md5) | `7469ae34…` | `7469ae34…` (sin cambio) |
| Hechos | 2.502 | 2.502 (sin cambio) |

371 definiciones tocadas, ninguna apagada. Las dos columnas de flags están fuera del disparador
de revisión (`product_spec_definition_revision` mira reglas, tipo, opciones, etiqueta, clave y
unidad), así que ningún borrador abierto en la app quedó desfasado. Las siete plantillas que
siguen sin campo visible sólo tienen filas, evidencia o no tienen productos.

## Compuertas

| Compuerta | Resultado |
|---|---|
| Preimagen exacta | la migración exige que las 371 definiciones lleven los flags registrados en la propuesta, o ya los publicados (reejecutable); aborta sin tocar nada si difieren |
| Ensayo local | sólo sintaxis: la base local no comparte los ids de estas definiciones y la guardia abortó ahí, como debe |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después, sello registrado |
| Lectura posterior | 626 / 556 / 100, versiones y hechos idénticos |

## Efecto inmediato y qué no cambia

- Efecto inmediato pequeño: las 68 familias nuevas casi no tienen datos todavía (19 familias con
  observaciones en todo el catálogo). El efecto real llega con cada lote de llenado: lo que se
  llene aparece en la ficha pública y se puede pedir al asistente y a las necesidades de compra.
- No cambia: la compatibilidad de taller sigue leyendo sus claves antiguas hasta migrarla; la
  base local queda sin estos flags hasta un replay con los mismos ids.

Llenado técnico persistido: 0.
