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

**Matching v2 (2026-09-18):** migration `20260918150000` adds
`get_bank_reconciliation_candidates_v2`; the client moved to it, a global
assignment, acquirer calibration and suggestions for unregistered rows. On the
owner's real June–September 2026 statements (229 movements) v1 preselected 2;
v2 preselects 125, offers a one-tap suggestion for 15 more and ties 5 transfers
to salaries Nómina still owes. v1 stays deployed, unchanged, for older builds.

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

## Candidate catalog (v2)

v1 sent every payment twice — the payment and the journal entry it posted —
because its exclusion list named the modules `sales`, `purchases` and
`expenses`, while the ledger writes `sales_payments`, `purchase_payments` and
`expense_payments`. Two identical candidates meant no row was ever unique. v2
calls v1 for eligibility (access, range, account, allocated targets) and then:

- drops a journal whose `source_module` is a payment module or whose
  `source_reference` is a candidate payment;
- adds every name a bank line may print for the counterparty: customer;
  supplier name, legal name, trade name, owner and aliases; for a salary, the
  employee (via `payroll_voucher_lines.expense_id` or a payment-workspace leg)
  plus `payroll_beneficiary_aliases`. Salary expenses carry no supplier, so v1
  called every one of them «Proveedor»;
- adds `bank_evidence`: the bank rows Nómina already tied to that salary
  payment (`payroll_payment_statement_allocations`,
  `payroll_statement_allocations`). Nómina registered weeks of July salaries on
  12 August; the evidence keeps the real transfer date;
- returns the payroll lines Nómina still owes, open sales and purchase
  invoices, a directory of counterparties with the expense account each was
  booked to, and earlier reconciliation decisions, so an unregistered row can
  be proposed. A payroll line is owed while its balance (total minus payments
  and applied advances, as `pay_payroll_voucher_v2` computes it) is positive,
  and carries the week's status and `reconciliation_version`. Until
  2026-09-18 it was «a line without an expense»; confirming a week books every
  line's expense, so a confirmed, unpaid week disappeared from the review.

The client asks from 45 days before the statement: a salary can be registered
weeks after its transfer.

## Direct matching

Bank lines print the holder's legal name, reordered, with the channel word
«Internet», accents dropped and the whole line cut at a fixed width. Identity
is therefore token based and order free; only the last bank word may be a cut
word («Univer» → «Universal»); a four-letter ERP name may be a nickname
(«Cata»); one-letter misspellings match («Natero» / «Nattero»). Placeholders
(«Cliente Mostrador», «Sin registro», «Proveedor») identify nobody; two real
names that share nothing are a conflict — someone else paid — and are proposed
but never preselected.

Every row ranks its options by amount, name, date distance and evidence; the
date window widens only for a strong name (12 days, 40 for salaries and
recurring payees). Rows are then assigned **together**: a row Nómina tied to
operations is fixed first, then one operation per row by maximum total score
(Hungarian method per group of competing rows), then one transfer paying
several operations of the same party (a salary plus a reimbursement). Greedy
row-by-row assignment gave a July group the June salary that a June transfer
needed. A pair starts selected only when the next-best arrangement — this row
taking another operation, or another row taking this one — scores clearly
lower.

## Acquirer deposits

The statement proves the acquirer's real terms: a deposit that equals one sale
net of `round(gross × rate)` and 19% VAT on that commission, to the peso, is a
measurement. With at least three such fits the dominant rate replaces a
configured rate it contradicts, and the review warns. On the owner's statements
debit cost 1,21% + VAT at 2 banking days while Terminales POS said 1,75% at 1;
credit showed 1,60% and 1,61% at 3 days (two deposits only: credit varies by
card). Terminales POS was corrected to 121 bps / 2 days and 160 bps / 3 days on
2026-09-18, keeping `effective_from` 2026-05-20 because the statements show
those terms since June.

A sale's window is the configured delay plus booking grace, widened to one
banking day either side of the delay the statement proved, whether or not the
proved rate equals the configured one. Transbank debit usually pays in 2 days
and sometimes in 1 (a Friday-night sale paid Monday). Before 2026-09-18 the
widening applied only to a contradicted configuration, so correcting
Terminales POS to the real 2 days lost five next-day deposits, among them one
that had been preselected. The penalty
measures the distance to the proved delay, not to the window's first day.

A deposit is explained by card sales inside their banking-day windows (Chilean
holidays included); terminal-cleared and legacy bank-booked sales are never
mixed in one deposit. It starts selected only when one combination fits to the
peso and a coincidental fit is unlikely: with many eligible sales some subset
hits any amount by chance, so the density of reachable sums near the deposit is
measured. Otherwise the closest combination under the proven rate is proposed
with its residue, and only then the broad legacy estimate below.

### Legacy Transbank estimate (fallback)

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

No estimated (non-exact) Transbank group is preselected. The user must approve it. The
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
- A direct proposal stays within the CLP tolerance and its date window. Only a
  decisive result starts selected: Nómina evidence, a strong name with the
  amount within 1% (transfers round salaries up), or an exact amount within
  three days that nothing else competes for — each with a clear margin over the
  best alternative arrangement.
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

## Unregistered movements

A row nothing explains gets one suggestion, firmest evidence first: a transfer
and its return cancel each other (dismiss both); an earlier decision for the
same counterparty or merchant; a salary Nómina still owes (paid from here, see
below); an open invoice with that balance
(register the payment in Ventas or Compras); the account a supplier or payee
was booked to before (e.g. the monthly rent); a goods supplier with no
purchase (register it in Compras); the merchant of a card charge (Google Cloud,
Meta, NIC Chile…) or a bank fee (a journal to financial expenses, never a
look-alike supplier). A suggestion this workspace can apply carries a
prefilled decision; «Usar sugerencias seguras» applies only high-confidence
ones and leaves them editable until the review is applied.

## Salaries Nómina owes

A transfer to a worker that matches an owed payroll line (strong name, amount
within 1%, paid from the week's close to 35 days later) is proposed as
«Pagar sueldo». Applying it goes through `apply_bank_reconciliation_actions_v3`,
which in one transaction pays the salary with Nómina's own commands and then
associates the row with the payment they created — the reconciliation never
books a salary itself, so the result is the same as paying it in Nómina:

- a draft week is confirmed first with `confirm_payroll_voucher_v2`, only when
  the row says so (`confirm_draft`, shown to the operator as «la semana se
  confirma»); a week another statement confirmed meanwhile is paid without
  confirming it again;
- the salary is paid with `pay_payroll_voucher_v2`, dated on the bank booking
  date, from this bank account with its active «Transferencia» method; the
  amount is the transfer, at most the balance, and a rounding up to $1.000
  stays on the row as any direct association tolerates;
- the row's allocation names the new expense payment, and its decision keeps
  `payroll_payment` (week, line, worker, payment) in `action_snapshot`.

The server refuses rather than guesses: a line whose balance is not the one
the review saw (`bank_reconciliation_payroll_line_changed`), a draft without
consent, another tenant's week, a method that does not pay into this account,
or a date Nómina only accepts as an advance. Nothing is saved when any row
fails. A retry with the same operation key returns the first receipt without
calling Nómina again. Nómina keeps its own path; either one leaves the line
paid, and the next review associates what Nómina paid.

## Several statements at once

The operator may pick several statements of the same account. They are read
and reviewed together — a sale of 30 June settled on 2 July is explained across
files — and a movement repeated by overlapping statements (same date, amount,
balance and text) is reviewed once. Each file is still persisted as its own
import under its own row ids, so importing a file again never duplicates rows,
and applying replays per file after a partial failure.

## Responsive composition

At 900 logical pixels and above, the workspace uses a bank-row list plus a
contextual split-pane resolver. The resolver keeps the observed date,
description, direction and amount in view while the operator chooses a real
action and fills only its required fields. Below 900, selecting a row opens the
same resolver as a focused in-route step with Back; it never adds a centered
desktop modal or horizontal scroll. S-06 owns searchable ERP operations,
accounts and payment methods, E-01 names status, E-04 owns persistent notices
and F-03 owns every CLP value.
