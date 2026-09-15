# Intelligent Bank Reconciliation Contract

**Owner:** Accounting  
**Canonical route:** `/accounting/bank-reconciliation`  
**Effective:** 2026-08-14

**Production foundation:** migrations `20260814130000`, `20260814131000`,
`20260814132000` and `20260814133000` were applied and read back on 2026-08-14
from exact SHA-256 values
`d27267272a94a0b17b91b316e492d430adf92a9e3e367d88fe037da62bf7b659`,
`184ebbe57f8d661a8bc67dfa0377c485904607cd2b6cf2a320f3acbff857c46f`,
`3303d0e46e59a30d34001cf1cbfc9e84d7795f3055414ce862db16fc7e5434cb`
and `c1be6f1313bf6f572a413f75f203839b69e32be579d2900db6a3ec132b7e8022`.
The final read-back found the authenticated action RPC with anon denied, the
sealed target projection, all five decision-lineage columns and zero applied
action operations. It also projected production expense `GTO-00136` as the
17/07 NIC Chile debit for CLP 19,980, proving the legacy-paid-expense seam
without creating or changing a business row.

## Product boundary

The operator imports a bank statement to resolve what each bank debit or credit
means. The workspace is bank-row-first: every movement remains visible,
proposed links are editable, and unresolved rows may remain pending. A row can
link an existing ERP operation, create and pay a real expense, post a balanced
classification entry, or be explicitly excluded with a reason. The whole
statement never has to be resolved in one session.

The decision is not a cosmetic label. `create_expense` creates a posted expense
with its cost line and canonical bank payment; `post_journal` creates one
balanced posted entry; and `associate_existing` only preserves evidence against
the authoritative operation, without posting it again. `dismiss` creates no
accounting and never makes the import look fully reconciled. All writes for one
review are tenant-scoped, idempotent, revision-checked and atomic.

The source file and full OCR text stay in memory. Persistence is limited to a
file hash, an optional hashed account identity, parser metadata, structured
movements, source coordinates, decisions and allocations.

## Date semantics

`booking_date` is the date printed by Banco de Chile. It is accounting
evidence, not proof of the moment a purchase, transfer or sale happened.
`operation_date` is a separate optional field and is never fabricated when the
statement does not provide it. The matcher uses a bounded date distance to
rank candidates rather than demanding equality.

Banco de Chile's public Banconexión account-statement guide presents a single
visible `Fecha` for each movement. CMF reporting definitions separately name
operation and accounting dates. The ERP therefore preserves the narrower
claim made by the actual document instead of silently promoting it to an event
timestamp.

Sources:

- [Banco de Chile · Consulta de cuentas Banconexión](https://portales.bancochile.cl/uploads/000/011/348/0b858c20-8963-487a-a1de-895412983e4a/original/bch_banconexion-consultacuentas_v2.pdf)
- [CMF · definitions for operation and accounting dates](https://www.cmfchile.cl/portal/estadisticas/617/w3-propertyvalue-29581.html)

## Transbank estimates

Transbank deposits are settlement groups, not one sale. The first policy uses
the combined ERP card method and keeps its instrument as `unknown`; it examines
bounded subsets ending on the bank booking date. Zero through four preceding
business days are the preferred window and up to seven preceding business days
form an explicitly lower-confidence fallback. This matters because Banco de
Chile's booking date can trail the commercial event and because one settlement
must not swallow unrelated card sales from the same window. A candidate is
shown only when the deposit does not
exceed the subset's gross sales and the implied net deduction is within the
configured plausible envelope. It shows the equation:

`gross card sales − estimated commission/IVA/retentions/adjustments = bank deposit`

No estimated Transbank group is preselected. The user must approve it. The
allocation records both each source payment's authoritative gross amount and a
proportional share of the net bank deposit, so many sales can explain one bank
row without pretending that fees disappeared.

The schema and Dart model publish `unknown`, `debit`, `credit` and `prepaid`
from the first release. A future Transbank settlement file or explicit payment
method can refine those rails without changing the import, review or
many-to-many allocation contract.

Official basis:

- [Transbank · Webpay Plus payout timing](https://publico.transbank.cl/productos-y-servicios/soluciones-para-ventas-internet/webpay-plus): debit/prepaid normally 24 business hours; credit normally 48.
- [Transbank · Anticipo de abono and cutoff behavior](https://publico.transbank.cl/anticipo-de-abono)
- [Transbank · Mis Abonos](https://publico.transbank.cl/portal-de-clientes/modulos-y-reportes/mis-abonos): deposits expose included sales, reversals, charges and totals.
- [Transbank · technical settlement-output specification](https://www.transbankdevelopers.cl/files/manual-especificaciones-tecnicas-de-salidas-especiales-20201112.pdf): settlement dates, purchase/process dates, commissions, IVA and retentions are separate fields.

## Matching and persistence invariants

- Direction must agree: bank credit with incoming ERP money; bank debit with
  outgoing ERP money.
- A direct proposal stays within the configured date and CLP tolerance. Only a
  unique, exact, high-confidence result starts selected.
- Existing-operation candidates include canonical payment rows and legacy paid
  expenses that embedded their bank account/method before `expense_payments`
  became the write model. The latter is how a NIC Chile payment can be linked
  without creating a duplicate expense or payment.
- A reviewed bank row cannot allocate more than its bank amount. The same ERP
  operation cannot be selected from two bank rows or receive more bank
  allocation than its authoritative amount. The client prevents the duplicate
  decision and the database revalidates it.
- A reconciled row is fully allocated. Pending and dismissed rows have no
  allocations; dismissal requires a durable reason and keeps the import
  partial rather than manufacturing reconciliation.
- Target existence, tenant, account, direction and amount are revalidated in
  the database at save time. A stale target fails the whole command.
- Import and apply are separate idempotent commands. Applying replaces one
  complete review snapshot under optimistic revision control.
- Authenticated clients can read their accounting scope but cannot directly
  insert or mutate reconciliation tables.

## Responsive composition

At 900 logical pixels and above, the workspace uses a bank-row list plus a
contextual split-pane resolver. The resolver keeps the observed date,
description, direction and amount in view while the operator chooses a real
action and fills only its required fields. Below 900, selecting a row opens the
same resolver as a focused in-route step with Back; it never adds a centered
desktop modal or horizontal scroll. S-06 owns searchable ERP operations,
accounts and payment methods, E-01 names status, E-04 owns persistent notices
and F-03 owns every CLP value.
