# Emergency continuation: finish Payroll

Date: 2026-07-30  
Repository: `/Users/Claudio/Dev/bikeshop-erp`  
Branch: `smartpegas1.0`  
Baseline HEAD: `32404d36bcae026a1560cf0080f85f6ac7cdf157`

## Owner instruction

Take over **all remaining Payroll work immediately**. Codex has stopped editing
the Payroll scope. Do not stop after one punctual correction: finish the
remaining plan, verify it, and report the exact boundary that still requires
the owner's authorization.

Read these two existing artifacts first; they remain the exhaustive handoff and
living plan:

- `docs/development/CLAUDE_PAYROLL_COMPLETION_HANDOFF_2026-07-30.md`
- `docs/development/PAYROLL_COMPLETION_PLAN.md`

Also complete the mandatory preflight and canonical reads named in the original
handoff. The visible Claude session must be **Code**, repo `bikeshop-erp`,
**Fable 5**, **Effort: Ultracode**.

## Current delta since Claude's last completion pass

### Native workflow is operational

The real file flow was rechecked in the canonical macOS debug app with
`/Users/Claudio/Downloads/cartola.pdf`:

- picker completed correctly;
- embedded text extraction read 5/5 pages in seconds;
- parser produced 96 rows, 35 outgoing movements and no fatal error;
- Payroll context loaded from production;
- review opened with 5 high-confidence suggestions;
- one cross-page movement was repaired;
- no business/financial write was executed.

An apparent extraction hang was **not an OCR defect**. The macOS `Go to:`
sheet was still open and the final `Open` action had not been pressed. Do not
rewrite the extractor to solve that false diagnosis.

### Latest transfer-triage contract

The owner explicitly rejected having to classify dozens of obviously unrelated
bank rows merely to continue. Codex added a first pass in:

- `lib/modules/hr/pages/payroll_reconciliation_page.dart`
- `lib/modules/hr/widgets/payroll_reconciliation_row.dart`
- `test/widgets/payroll_reconciliation_responsive_test.dart`
- `docs/architecture/canonical-ui-surfaces.md`

Intended behavior:

1. `Calces sugeridos` opens first and contains the five proposed salary
   matches.
2. Only real ambiguity requires a human answer.
3. Clearly unrelated outgoing movements are classified automatically as
   non-Payroll, collapsed by default, auditable and reopenable.
4. Incoming movements are informational, collapsed and non-blocking.
5. The extra transfer to Vicente for CLP 22,000 remains manual/blocking because
   the beneficiary is a Payroll worker and the date is plausibly relevant; it
   must never be absorbed as salary merely because the name matches.
6. Automatic decisions are durable, emitted exactly once, carry a stable audit
   reason and use `manualConfirmation: false`.

Focused evidence already green:

- analyzer clean for the reconciliation page and row widget;
- matcher + reconciliation theme: 26 tests passed;
- focused responsive/triage suite: 5 tests passed, including automatic generic
  outgoing classification, Vicente CLP 22,000 remaining manual, one and only
  one audited automatic decision, phone no-pan, and the declared breakpoint
  matrix.

Native evidence after the change currently reads `Revisar transferencias
13/40`. Treat this as an **open acceptance check**, not proof that the UX is
finished. Inspect the progress denominator and the remaining groups. The owner
must not be forced to categorize every record. The final UI should ask only for
the five suggestions plus genuine ambiguities such as Vicente CLP 22,000;
everything demonstrably unrelated must remain safely automatic, collapsed,
auditable and reversible. Never auto-classify a worker-named, date-plausible
transfer using amount mismatch alone.

### Backend and authorization boundary

The seven versioned Payroll migrations are deployed and read back; the
versioned OCR/reconciliation capability is active. This does **not** authorize
business writes.

- `create_payroll_statement_import` is the first durable evidence write.
- `apply_payroll_statement_reconciliation` is the financial apply.
- Do not invoke either RPC, click the final apply action, create real payments,
  learn aliases, commit, push or deploy without the owner's explicit
  authorization for that exact boundary.
- CHECKPOINT B remains open.

## Current runtime

One canonical Flutter macOS debug session is active:

- Flutter runner PID: `71007`
- app PID: `73965`
- target: `lib/main.dart`

Do not start a second Flutter session, pattern-kill Flutter/Dart, or use Claude
Browser/Chrome/computer-use for this task. The owner has temporarily prohibited
those Claude tools because they overheat the Mac. Batch edits and run headless
analyzer/tests. Coordinate a hot restart of the existing native session when a
visual verification round is ready.

## Relevant dirty ownership

The shared checkout is intentionally dirty. Never reset, clean, stash or
overwrite unrelated work.

Claude owns the Payroll scope already listed in the original handoff, including
the four latest delta files above. Current relevant state includes:

- `?? lib/modules/hr/pages/payroll_reconciliation_page.dart`
- `?? lib/modules/hr/services/payroll_reconciliation_service.dart`
- `?? lib/modules/hr/services/payroll_statement_extraction_service.dart`
- `?? lib/modules/hr/widgets/payroll_reconciliation_row.dart`
- `?? test/unit/payroll_statement_extraction_service_test.dart`
- `?? test/unit/payroll_statement_matcher_test.dart`
- `?? test/widgets/payroll_reconciliation_page_theme_test.dart`
- `?? test/widgets/payroll_reconciliation_responsive_test.dart`
- `MM docs/architecture/canonical-ui-surfaces.md`
- shared shell/theme files are dirty and have other consumers; follow the
  original blast-radius rules before touching them.

Do not edit Website Builder/storefront files or another task's migrations.

## Finish criteria

Do not declare success until all of these are true:

1. the transfer screen no longer demands manual categorization of obviously
   unrelated rows;
2. suggestions and true ambiguities remain safe and explicit;
3. the real PDF can reach transfer review reliably;
4. cash remains manual per worker/week, never inferred from the statement;
5. desktop and compact, light and dark, History, Advances, payment/evidence,
   reconciliation groups and overlays pass the existing canonical visual and
   responsive contracts;
6. focused analyzer/tests are green and the living plan is updated honestly;
7. no real financial mutation occurs without CHECKPOINT B authorization.

Start implementation after reading this packet; do not return only another
plan.
