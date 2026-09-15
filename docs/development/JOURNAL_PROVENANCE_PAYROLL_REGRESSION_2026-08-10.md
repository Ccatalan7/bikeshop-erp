# El guard de procedencia bloqueó toda la nómina (2026-08-10)

Handoff para el dueño de `20260808210000_supplier_relationship_foundation.sql`.
Diagnóstico y corrección hechos desde la sesión de Claude, con la app viva y
producción delante. No hay desacuerdo con el diseño del refactor: la corrección
lo restituye.

## Lo que pasaba

`Confirmar semana` en Nóminas moría con:

```
confirm_payroll_voucher_v2
→ PostgrestException(Canonical journal source is missing or outside tenant, 23514)
```

La transacción se revertía entera, así que **ninguna semana podía confirmarse y
ningún sueldo podía pagarse**, sin dejar rastro en la base. Duró desde el
2026-08-08 hasta el 2026-08-10.

## Causa

Confirmar una semana crea, por persona, un gasto y su asiento
(`ensure_payroll_line_expense` → `create_expense_journal_entry`). Dos guards del
refactor rechazaban ese asiento:

| Función | Tabla |
|---|---|
| `validate_supplier_journal_provenance` | `journal_entries` |
| `derive_journal_line_counterparty` | `journal_lines` |

Ambas tratan `source_document_type = 'expense'` como documento de proveedor
**siempre**, y exigen que `resolve_supplier_party_for_journal_source` devuelva
una parte. Ese resolutor une `expenses` con `suppliers` por `supplier_id`, así
que devuelve `null` en dos situaciones que no se parecen en nada:

1. el documento **no existe**, o es de otro tenant → violación de procedencia;
2. el documento existe y **no nombra proveedor** → un caso normal.

Un sueldo es el segundo: no se le compra a nadie. Y no es un borde — en
producción **79 de 137 gastos no tienen proveedor**, y **79 asientos ya
existentes** caen en ese caso.

**Contradice al propio refactor.** `journal_lines_counterparty_context_check`
admite siete contextos (`supplier, landlord, utility, tax_authority,
service_provider, carrier, other`): la dimensión tipada previó contrapartes que
no son proveedor, y los guards no lo respetaban.

## Corrección

`supabase/migrations/20260810210000_journal_provenance_allows_supplierless_source.sql`

Se agrega `journal_supplier_source_exists_in_tenant(uuid, text, uuid)` y los dos
guards sólo levantan la excepción cuando el documento fuente **no existe en el
tenant**. Mensajes y `errcode` intactos; la violación real se sigue rechazando
igual. La condición pasó de `A and B` a `A and B and not C`: es estrictamente
más permisiva, así que no puede provocar un rechazo nuevo.

El tercer consumidor del resolutor, `sync_supplier_journal_counterparties`, ya
trataba bien el nulo. Se comprobó que no hay un cuarto.

## Evidencia

- Reproducido en la app viva; error capturado del log de la sesión.
- Aplicado por el camino guardado, read-back, y registrado
  (`supabase_migrations.schema_migrations` → `20260810210000`).
- Semanas **27 y 28 confirmadas** en producción tras el arreglo: 8 líneas con su
  gasto (`GTO-00150`…) y su asiento.
- Regresión nueva: `supabase/tests/journal_provenance_supplierless_source.sql`,
  **12/12**, con sesión autenticada real — incluye que un documento fuente
  inexistente siga lanzando `23514`.
- Espejado en `supabase/sql/core_schema.sql` para que local no vuelva a divergir.

## Tres cosas que quedan para ti

1. **La cabecera de `20260808210000` dice `Deployment status: pending review; do
   not deploy from this task`, y está desplegada.** Vale la pena revisar cómo
   pasó, porque el guard llegó a producción sin la revisión que él mismo pedía.

2. **`core_schema.sql` no creaba las tres columnas `triggers_*` de
   `job_statuses`**, que producción sí tiene. Un bootstrap limpio moría con
   `column status.triggers_delivery does not exist`, y eso dejaba **el stack
   local inservible para cualquiera**. Corregido acá, pero conviene revisar qué
   otra migración quedó sin espejar.

3. **27 archivos pgTAP abortan a media ejecución en local** (`Failed: 0`, exit
   3), por errores heterogéneos y en su mayoría datos residuales. Medido: con
   los guards originales esos archivos corrían **18** subpruebas; con la
   corrección corren **32**, sin fallos en ninguno de los dos casos. O sea el
   arreglo los destraba en parte y no rompe nada — pero el resto de la
   degradación es anterior y sigue ahí. El rebuild limpio no es posible hoy:
   `drop schema public cascade` muere con `out of shared memory /
   max_locks_per_transaction` en el Postgres local.
