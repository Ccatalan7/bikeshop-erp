# Nested invoice/payment trace context

Migration `20260716020000_repair_nested_invoice_trace_context.sql` makes the
canonical inventory/accounting trace safe for nested triggers and multi-row
statements.

## Why one current operation is not enough

The trace kernel stamps stock and journal evidence from transaction-local GUCs.
Payment triggers also recalculate their invoice, and cancelling one invoice can
soft-delete several payments in one SQL statement. PostgreSQL runs every
`BEFORE` row trigger for that statement before it drains the queued `AFTER` row
triggers. A single `app.inventory_operation_id` can therefore be overwritten by
a sibling row or a nested payment before the original invoice completes.

## Canonical frame lifecycle

Every traced invoice/payment row has one JSON frame in
`app.inventory_trace_context_stack`. UPDATE/DELETE use the following lifecycle:

1. `zy_inventory_trace_push_*` records the real parent context. A pending row at
   the same table and trigger depth is treated as a sibling, not a parent.
2. The existing `zz_inventory_trace_begin_*` creates or reuses the canonical
   operation.
3. `zza_inventory_trace_capture_*` binds the resulting operation context to the
   row frame.
4. `aa_inventory_trace_activate_*` restores that row's context before any
   business `AFTER` trigger runs. It first proves the child operation belongs to
   the exact tenant, row, action, document type, and table; a mismatch aborts
   atomically instead of allowing payment completion to trust a crossed GUC.
5. The existing `zzz_inventory_trace_complete_*` completes the correct root.
   Existing nested invoice lifecycle commands retain responsibility for the
   explicit writers and completion they execute after the nested update.
6. `zzzz_inventory_trace_restore_*` removes the frame and restores its real
   parent. A nested invoice root that is deliberately completed by its caller
   after the invoice update (the covered-warranty lifecycle) remains active for
   that caller; reused parent contexts restore normally.

Trigger names and alphabetical ordering are part of this contract. Do not
rename one of these triggers independently.

The JSON queue has a hard 512-frame ceiling so sibling lookup cannot grow
without bound. Bulk UPDATE/DELETE maintenance above that size must be chunked;
ordinary multi-row INSERT never accumulates frames because it starts in AFTER.

INSERT uses `a0_*` push, `a1_*` begin, and `a2_*` capture as the first three
successful `AFTER INSERT` triggers, followed by the same activation/business/
completion/restoration chain. It must not be moved back to `BEFORE INSERT`:
PostgreSQL fires that timing for a conflicting input row even when `ON CONFLICT
DO NOTHING` produces no row and no matching `AFTER INSERT`. `ON CONFLICT DO
UPDATE` must create one UPDATE trace, never an orphan INSERT trace.

## Historical QA reconciliation

The same migration can close three known `started` invoice roots from QA
transaction `832950`. The repair is deliberately inert on fresh/local databases
and aborts if any operation identity, snapshot hash, source graph, sibling,
checkpoint sequence, or financial-effect count differs from the frozen
evidence.

The repair only appends warning/invariant/completion checkpoints and changes the
trace outcome to `completed`. It never recreates or deletes invoice, payment,
stock, adjustment, journal, or journal-line data. Misattached journal
checkpoints remain immutable and are explained with reconciliation warnings on
both affected roots.

## Required verification

Run `supabase/tests/nested_invoice_trace_context.sql`. It cancels one fully paid
invoice with two payments in one statement and proves:

- exactly one invoice root and two payment roots are created;
- every root completes its canonical checkpoint lifecycle;
- no nested invoice root or `started` root remains;
- invoice/payment journal reversal checkpoints do not cross identities; and
- the operation/source GUCs and frame stack are empty afterward.

Because the migration contains standalone SQL, it is included from
`supabase/sql/core_schema.sql` immediately after migration `20260716010000`.
