# Revocar una aplicación de investigación — 2026-09-16

La revisión del registrador (`registrar-independent-review-2026-09-16.md`) dejó abierto que
«nadie puede revocar una aplicación salvo por SQL privilegiado directo». Desde
`20260916240000_product_spec_research_revocation.sql` el mismo actor que aplicó una propuesta
la revoca con un motivo, por el mismo camino guardado del aplicador.

## Qué hace `revoke_product_spec_research_application_v1(aplicación, motivo)`

- Exige tenant y actor autenticados, que la aplicación sea de ese actor y un motivo de al menos
  ocho caracteres. Misma llave de bloqueo que el aplicador; la segunda llamada devuelve el recibo
  (`replayed = true`).
- Registrada pero nunca aplicada: la cierra (`revoked_at`) para que el aplicador no pueda
  correrla. Aplicada: recorre `changed_fact_ids` del recibo y, **sólo si el hecho sigue siendo
  exactamente lo que la aplicación escribió** (mismo `fact_sha256` que la postimagen), lo
  devuelve a su preimagen archivada —valor, procedencia, confirmación, opciones y lecturas de
  nombre— o lo borra si no existía. Un hecho que un mecánico confirmó o editó después se
  conserva y se informa (`kept_fact_ids`); uno ya borrado, `missing_fact_ids`.
- La identidad parchada (`model`, `manufacturer_sku`, `gtin`, referencia) vuelve igual: sólo
  mientras el producto siga con el valor que la aplicación puso.
- Valida el producto con la guardia del motor, guarda preimagen y postimagen en
  `product_spec_research_revocations` (RLS, sin grants) y devuelve el recibo:
  restaurados, borrados, conservados, ausentes, identidad restaurada, revisión.
- `get_product_spec_research_revocation_v1(aplicación)`: el actor lee su recibo sin los
  snapshots. Nada de esto reabre la aplicación: el aplicador sigue respondiendo con el recibo
  original y nunca vuelve a aplicar.

## Cómo se corre

```bash
python3 scripts/inventory/revoke_product_spec_research.py \
  --project xzdvtzdqjeyqxnkqprtf --actor-id <actor> --application-id <aplicación> \
  --reason 'La fuente resultó equivocada' --folder .tmp/product-spec-catalog/revoke-001 --dry
```

`--dry` llama al RPC dentro de una transacción revertida y guarda el recibo que produciría;
sin `--dry` confirma una sola vez, relee el recibo con el lector y captura el snapshot posterior.

## Prueba

`supabase/tests/product_spec_research_application_candidate.sql` cierra con el escenario: motivo
corto rechazado, aplicación ajena rechazada, revocación de la aplicación sembrada (dos hechos
restaurados, ninguno borrado, `model` y `gtin` de vuelta, la opción vuelve a `01` con su
procedencia `name_reading` y su lectura archivada reatada, la fila añadida desaparece y la
original conserva su decimal exacto), la repetición devuelve el recibo sin efecto, el lector
devuelve el motivo y el aplicador sigue contestando con el recibo original. 59 pruebas verdes.
Aplicada y verificada en producción (recibo `20260916240000`).

## Límite documentado

La revocación no distingue una edición posterior «menor» de una confirmación: cualquier cambio
posterior al hecho lo deja fuera del retroceso. Es a propósito: el retroceso nunca pisa lo que
un mecánico tocó.
