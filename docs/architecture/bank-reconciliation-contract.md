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

The owner's reality the windows are built for (2026-09-18): salaries go out
the Monday or Tuesday after the payroll week and sometimes days later, and the
bank's date can trail the real transfer (a Saturday transfer books on Monday).
Every window is therefore two-sided and generous where the party is known:

- a salary Nómina still owes: from its week's operational close (Saturday for
  a Sunday close, `payable_from` in the catalog) to 35 days after the week;
  a transfer up to three days before the end is still recognised, and said
  to be an advance, because Nómina refuses earlier money as that week's
  salary;
- a payment Nómina or another module already registered: 5 days either side,
  12 with a strong name, 40 for a person or recurring payee, and any distance
  when Nómina tied the transfer to it;
- acquirer deposits: banking days after the sale, one day either side of the
  delay the statement proves.

A salary paid from here is dated on the statement's date, never the guessed
real one: the bank account in the ERP then matches the statement line by line,
and a booking date is never earlier than the transfer, so it cannot turn a
salary into an advance.

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
but never preselected. A conflicting option does not enter the assignment
either: it only appears as a low-confidence alternative. Until 2026-09-18 it
competed for the operation and could hold it, so a $2.450 bonus Nómina paid to
Vicente sat on a Google charge of $2.740 and his $122.500 transfer lost its
salary + bonus pair.

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
- Import and apply are separate idempotent commands under optimistic revision
  control. A decided row is final: a later apply of the same statement covers
  exactly the rows still open and the kernel refuses a decided one
  (`bank_reconciliation_row_already_decided`). Before 2026-09-19 an apply
  replaced the whole statement and refused one that had created anything, so
  a movement left pending could never be resolved while the page said it
  could. A reopened statement shows what an earlier sitting applied as «Ya
  conciliado» and sends nothing for it.
- A manual association may take several operations: one transfer can pay
  several (the owner's mother paid two salaries of week 29 and was repaid
  $133.000 in one transfer, 7 July). It counts only once the operations add up
  to the movement within the direct tolerance; each takes its own amount and
  the last takes the remainder.
- Authenticated clients can read their accounting scope but cannot directly
  insert or mutate reconciliation tables.

## Unregistered movements

A row nothing explains gets one suggestion, firmest evidence first: a transfer
and its return cancel each other (dismiss both); a salary Nómina still owes
(paid from here, see below); a company rule for the line's words (next
section); an earlier decision for the same counterparty or merchant; an open
invoice with that balance
(register the payment in Ventas or Compras); the account a supplier or payee
was booked to before (e.g. the monthly rent); a goods supplier with no
purchase (register it in Compras); the merchant of a card charge (Google Cloud,
Meta, NIC Chile…) or a bank fee (a journal to financial expenses, never a
look-alike supplier). A suggestion this workspace can apply carries a
prefilled decision; «Usar sugerencias seguras» applies only high-confidence
ones and leaves them editable until the review is applied.

## Company rules

The merchant table is the same for every company: Google Play or YouTube may
be a business tool for one and the owner's personal subscription for another.
What a company decided lives in `bank_reconciliation_rules` — «the charges
whose words are X go to account Y, as a journal (`post_journal`) or as a paid
expense (`create_expense`)» — and the advisor proposes it as a **safe**
suggestion, ahead of earlier decisions and of the merchant table, with the
reason «Regla de la empresa: los cargos «X» van a …».

- **Words, not the whole line.** A rule is written in the line's words
  without the bank's channel words (`BankStatementRuleText`: «Pago: Google
  Play Youtu Renca» → `google play youtu`). It matches a line when each of its
  words starts a word of the line, in order: `youtu` speaks for «Dl*google
  Youtube» and «Google Play Youtu». A rule taught from a row leaves out words
  with a digit — the bank's code for that one charge («Google Cloud Jl5r»,
  «Hwm3») — so it also speaks for next month's charge. The longest matching
  rule wins; a rule only speaks in its direction.
- **Never for a person.** A transfer to or from a person and a card deposit
  are decided by who it is and what the ERP owes, never by their words: no
  rule is taught from them or applied to them.
- **Teaching.** On a row resolved as a classification or an expense, «Usar
  siempre para «X»» saves the rule (`save_bank_reconciliation_rule_v1`,
  accounting role; the same words and direction replace the rule) and decides
  the same way the open rows of the review it matches. A row a rule already
  decided does not offer it again. `delete_bank_reconciliation_rule_v1`
  removes one; a rule's account must be the tenant's and active, and an
  expense rule needs an expense account and a debit.

Viñabike's first rules (2026-09-19): the YouTube / Google Play and Meli+
subscriptions (`youtu`, `melimas`, debits) are the owner's personal
consumption, booked as a journal to 3103 «Retiros de socio · Claudio
Catalán» (equity), not as a business expense: an expense the business did not
need would be a rejected expense (gasto rechazado) in the tax return. Changing
the decision is teaching another rule for the same words.

## One movement, several accounts

A transfer can pay several things at once: the owner's mother pays the
accountant's fee (Pedro Madrid, $50.000 a month), the monthly F29 and the
municipal licence, and he repays her in one transfer — 17 August, $214.685 =
fee $50.000 + F29 $90.149 + second half-year licence $74.536 (she reported
«IVA $140.149», fee included). «Dividir» books such a row as 2 to 10 parts
that add up to it. The operator types the parts he knows and the last one takes
what is left, so the F29 need not be known. A part on an expense account is a
paid expense with its supplier and the bank method, exactly as «Crear gasto»
books one; any other account (IVA Débito Fiscal for the F29) is a line of one
balanced journal against the bank. Money coming in is never an expense.

The split is learned: the next transfer to the same person is proposed with
the same parts — medium confidence, never among the safe suggestions — because
the structure repeats and the amounts do not.

Money coming in is never split into an expense account: the kernel books
every part on an expense account as a paid expense, which only a charge can
be. The editor does not offer those accounts for a deposit, and neither the
AI nor a learned split proposes them.

## What somebody else paid, and what never reached the bank

Two deterministic readings cover what the name on the statement cannot:

- **Paid by somebody else.** The owner's mother paid Vicente $94.500 and Lucas
  $38.500 of week 29, Nómina registered both on 12 August, and he repaid her
  $133.000 on 7 July. `BankThirdPartyFinder` proposes a movement as the sum of
  1–3 ERP operations nothing else explains, within 45 days, only when exactly
  one combination adds up to the peso and the parts form a batch (one kind,
  registered within 7 days; money coming in from one customer only). It is
  never selected: a sum can coincide. On the owner's four 2026 statements it
  proposes that one case and nothing else; before the batch rule it paired
  three customers' sales weeks apart with a $20.000 deposit.
- **One transfer, another name.** Rosita Bustamante's $34.000 sale by
  transfer arrived from Osvaldo Quezada the same day; Máximo Gallardo's
  $76.000, paid on Saturday 27 June, from Patricio Basau on Tuesday 30 June
  (Monday 29 was a holiday). The matcher keeps a payment whose party
  contradicts the bank's name as a mere alternative — between a card charge
  and a person that contradiction is real — so the owner had to find these
  by hand (2026-09-19). Between two people it is a relative or a borrowed
  account: when the bank row is a person-to-person transfer, the ERP
  recorded the operation as a transfer, the amount is exact, the bank booked
  it from one banking day before to three after (`BankBusinessCalendar`),
  and neither side has another candidate, the finder proposes it in place of
  that alternative. Booked the same or the next banking day it is high
  confidence and a safe suggestion (`BankSuggestionKind.otherPayer`, whose
  `proposalId` the acceptance selects); later, a medium proposal. Its
  reasons say when each side dated it, why the bank took that long
  (evening transfer, weekend, holiday) and who paid instead of whom. On the
  owner's statements it finds exactly those four and nothing else.
- The finder only reads person-to-person transfers, and a single operation
  that fits two movements of the same amount is proposed for neither.
- **Same person, another amount.** A transfer with no sale says so when the
  same person has an operation by transfer, within five days and for
  another amount, that no movement explains: Carlos Sánchez sent $18.000 on
  7 July, the day his $7.000 sale was recorded as a transfer that never
  arrived. When that operation is smaller, the suggestion (medium, never
  safe) links it and books the rest as «Venta no registrada · nombre» on the
  sales income account — the association remainder below; the advisor adds
  that choice to the row's proposals («Misma persona: …»).
- **Money from someone, no sale at all.** Most likely a sale nobody
  registered. The suggestion (low, never safe) books it as the sales kernel
  books a transfer sale — 4100 Ingresos Operacionales, no VAT, «Venta no
  registrada · nombre» — and says to register it in Ventas instead when what
  was sold is known. The owner keeps the five of 2026 pending until Vicente
  says what they were (2026-09-19).
- **ERP without bank.** «N operaciones del ERP no aparecen en la cartola» lists
  what the ERP records as paid or collected through this account, dated inside
  the statements (minus a 3-day booking lag), that no selected movement
  explains: a test purchase «paid» by transfer, a sale registered as a
  transfer that never arrived, salaries a relative paid. Card sales are left
  out; the acquirer pays them later and in groups.

## An association and what it leaves

«Vincular operación» accepts operations chosen by hand that add up to the
movement within $1.000 (a fee, a rounding), the last taking the difference.
When they add up to less, the row is not resolved until the rest has an
account: the link editor shows «Registrar los $X que faltan» (account and
what it was), and `associate_existing` carries `remainder` {account_id,
description, reference?} (`20260919090000`). The operations are linked for
their own amounts and the rest is one posted journal against the bank to
that account (money in: Debe banco / Haber cuenta; money out: Debe cuenta /
Haber banco). The resolution keeps the account and gloss in `accountId` and
`description`, so a saved draft restores them.

- Any row the screen does not count as resolved — a manual association
  that does not add up, a split whose parts do not reach the movement, an
  unfinished expense — is sent as `pending`: it never blocks the decided
  rows of its statement, nor reaches the kernel half-filled.
- The kernel bounds what a link may claim: a manual allocation may differ
  from its operation by at most $1.000. The exception is a card settlement,
  and it is one because the terminal adapter says so: the adapter turns each
  `processor_estimate` into a manual allocation marked `settlement` — and
  strips that mark from anything else — because it is the adapter that books
  the acquirer's commission and moves the money out of the clearing account.
  A marked settlement may be below its sale, never above. The first bound
  (`110000`) refused real settlements for an hour; telling them apart by
  their provider (`140000`) let a caller reconcile a card sale with no
  settlement posted at all (`20260919160000`).
- The journal a payment posted (sales, purchase and expense payments,
  terminal settlements, and a legacy paid expense's own journal) is never a
  target apart from its payment
  (`bank_reconciliation_target_is_payment_journal`): the same money would
  explain two movements.
- A remainder of zero or less, or one to the bank account itself, is refused.
- An operation key already applied answers from the receipt it kept, and the
  adapter answers it before the kernel sees the actions
  (`20260919170000`). The kernel hashes what it receives, which the adapter
  has normalized: once it started marking settlements, repeating a
  settlement applied before that deploy — the case operation keys exist for —
  came back as `bank_reconciliation_idempotency_conflict` with nothing the
  operator could do. The adapter takes the kernel's own
  `:bank-reconciliation` lock, compares the hash of what the **caller** sent
  with `source_payload_hash`, and replays from the stored receipt; a
  different payload under the same key is still refused.

## The first real apply (2026-09-19)

The owner's four statements: 222 of 229 movements applied in one operation
per file — 185 links, 16 expenses, 18 journals, 5 salaries paid through
Nómina (NOM-00037 and NOM-00039 confirmed). The 50 card deposits no sale
combination explains were excluded with the owner's reason («se asume que
las ventas con tarjeta están bien registradas»), five transfers from
customers and two supplier payments wait for Vicente. It exposed that
`post_journal` booked money going out backwards (13 journals, $31.443; the
bank ledger $62.886 above the statement); `20260919100000` fixed the kernel
and swapped those journals' lines in place, so their allocations keep
pointing at right journals. The conciliations list counted applied
decisions still in the draft as «sin aplicar» (`20260919130000`).

## AI analysis

«Analizar N pendientes con IA» reads the open movements the review could not
explain the way the owner's accountant would: what each one probably is, what
may be missing in the ERP, and the one question that would settle it. The
operator may answer in the row («Responder»); the answer travels with that
movement and the model proposes again with it as the truth. It never applies
anything: «Usar propuesta» only fills the row's decision, still editable.

**The model reads, the code judges.** `BankReconciliationAiAnalyst` sends
movements, operations, accounts and suppliers with short ids (M1, O4, A3, S2)
and keeps a proposal only if every id exists and the proposal fits: a link
goes the same direction as the movement and adds up to it within $1.000
(low confidence, never among the safe suggestions); an expense only for a
debit on an expense account; a split whose whole parts add up exactly. What
fails is dropped and the explanation and question remain. An id that slips
into a text is replaced by what it names — the owner never sees «M3».

It asks `gemini-2.5-flash` through `gemini-proxy` in JSON mode, 8 movements per
question, 3 questions at a time, with a bounded thinking budget. Each batch
shows up as soon as it is judged and an operation one batch linked is taken
for the batches judged after it. The proxy is an edge function cut at 150 s:
60 movements with 160 operations in one question returned 504 three times
(7½ minutes) on 2026-09-19; in batches the owner's 49 open movements take
about 30 s. A batch that fails leaves its movements unread and the rest
stands.

Card deposits are left out of the bulk analysis: without Transbank's deposit
report the model has no evidence beyond the settlement estimate, and they
were half of the owner's pending rows. The card-deposit finding says so, and
«Analizar con IA» in a row's resolver asks about one movement alone, card
deposit included. Rows already analysed are not sent again; the button counts
only the ones still unread.

## Salaries Nómina owes

A transfer to a worker that matches an owed payroll line (strong name, amount
within 1%, dated from the week's operational close to 35 days after the week)
is proposed as «Pagar sueldo». One dated before the close is described as an
advance and left to Nómina. Applying it goes through `apply_bank_reconciliation_actions_v3`,
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

Advances count. The catalog returns the advances Nómina has not discounted
yet (`open_advances`); the review places each on its worker's oldest owed week
ending on or after it, as Nómina applies them, and expects the transfer to be
the balance minus those advances. «Pagar sueldo» then applies them in the same
payment (`advances` on the row, re-checked by the server: the worker's own,
still open, enough left, paid by the week's end). A transfer that pays less
than that is proposed as part of the salary with medium confidence and a
question — «¿fueron los $X un anticipo que no registraste?» — because a
forgotten cash advance is the usual reason (Braulio, week 34: $30.000 in cash
on 20 August, $10.600 by transfer). The remainder stays owed in Nómina until
the advance is registered there or paid.

The server refuses rather than guesses: a line whose balance is not the one
the review saw (`bank_reconciliation_payroll_line_changed`), a draft without
consent, another tenant's week, a method that does not pay into this account,
or a date Nómina only accepts as an advance. It reads the week under
Nómina's own settlement lock (`:payroll-settlement`, `20260919150000`), so a
payment Nómina records meanwhile waits instead of slipping between the
balance checked and the version paid. Nothing is saved when any row
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

Statements loaded on different days overlap too: a month downloaded on the
17th and the full month later. A movement another statement of the account
already decided — same booking date, direction, amount and running balance,
which the bank prints once per movement (every row of the owner's four 2026
statements carries one, all distinct) — is shown as «Ya conciliado en otra
cartola» and applied as a dismissal marked `settled_elsewhere`, which the
kernel proves against that statement. The kernel refuses to associate, book
or classify such a row (`bank_reconciliation_row_settled_elsewhere`), the
catalog stops offering operations a row already explains and returns
`reconciled_rows` for the statement's dates, and settled-elsewhere dismissals
never teach the advisor to dismiss.

## Saved conciliations and their draft

A conciliation is registered when its statements are read, not when it is
applied. Reading them saves each file as its import
(`save_bank_statement_import_v1`, idempotent per file) and
`open_bank_reconciliation_session_v1` puts the imports in one
`bank_reconciliation_sessions` row — a new one, or the one any of them already
joined, so importing a file again resumes its conciliation. The owner's four
2026 statements are one conciliation of 229 movements.

The session keeps a **draft**: what the operator decided and has not applied,
and what the AI read, for each movement he touched. It is saved 1.2 s after
each change with `save_bank_reconciliation_session_draft_v1` over the
revision the screen last saw; a screen that did not see the last save is
refused (`bank_reconciliation_draft_conflict`) and says so instead of
overwriting. The draft is the client's (`BankReconciliationDraftCodec`,
version 1): keyed by `<file sha256>:<file row id>`, never by the review's
unique ids. A sitting that loaded only some of the conciliation's
statements (July imported again alone) saves what the draft holds for the
others as it was; before 2026-09-19 its next save dropped them. Untouched movements are not saved, so reopening reviews them
against today's ERP and a sale registered since can still be proposed.

«Conciliaciones guardadas» lists the account's conciliations
(`list_bank_reconciliation_sessions_v1`: statements, movements, applied,
pending, decisions not applied, rows the AI read). «Retomar» rebuilds the
review from `bank_statement_rows` — the files are never stored — reviews it
again, and restores a saved decision only while it holds: its operations
exist and no untouched movement took them, a salary is taken as Nómina owes
it today, and a decision today's kernel would refuse (a deposit split into
an expense account) is dropped with the rest. That judgement needs the
account catalog, so «Retomar» and reimporting load the workspace options
**before** restoring the draft (until 2026-09-19 they loaded them after, and
the filter accepted everything it could not check); without them a deposit
split is decided again rather than taken as good. What no longer holds is dropped and counted in a notice. Applying
stays per file and covers only the open rows, so the operator applies what is
sure and «Seguir con los N pendientes» reopens the same conciliation with the
applied rows shown as «Ya conciliado».

A movement a page break split keeps both pages: `source_page_end` (null when
it fits one page). Until 2026-09-19 a row kept one page and required its last
line not to precede the first, so the owner's $700.000 deposit of 11 August
(page 2 line 39 → page 3 line 1) made the whole August statement fail with
`bank_statement_row_invalid` — «Aplicar» included; no import had ever been
saved in production.

## Responsive composition

At 900 logical pixels and above, the workspace uses a bank-row list plus a
contextual split-pane resolver. The resolver keeps the observed date,
description, direction and amount in view while the operator chooses a real
action and fills only its required fields. Below 900, selecting a row opens the
same resolver as a focused in-route step with Back; it never adds a centered
desktop modal or horizontal scroll. S-06 owns searchable ERP operations,
accounts and payment methods, E-01 names status, E-04 owns persistent notices
and F-03 owns every CLP value.
