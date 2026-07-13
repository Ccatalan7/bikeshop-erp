# Testing Strategy

Verification is risk-based. Repeating every test after every file is wasteful; skipping the business invariant affected by a change is unsafe.

## Gates

| Change | Required local check |
|---|---|
| Documentation/configuration | `just verify-fast` |
| Isolated Dart logic/UI | affected test files plus analyzer for affected paths |
| Shared navigation/business UI | affected tests plus registered canonical surfaces |
| Inventory, accounting, invoices, payments, returns or status transitions | affected Flutter tests plus relevant pgTAP files |
| Database schema/trigger/function | clean local schema apply, affected pgTAP, second idempotency apply |
| Dependency/toolchain | doctor, lockfile audit, representative build/test |
| Phase/release checkpoint | `just verify`, `just db-test`, required builds, and authenticated read-only production smoke checks |

## Rules

- Run one full gate per coherent batch, not after each edit.
- A failed targeted test must be understood before widening the test scope.
- Browser exploration is discovery; convert a confirmed regression into a repeatable test.
- Staging browser/database automation is suspended because live manifests proved
  that staging does not represent production. Existing staging helpers are
  retained only as dormant diagnostic tooling; `just e2e` is not a release gate
  and must not be cited as production evidence.
- Production smoke checks are authenticated and non-destructive.
- Database tests use disposable local data and must refuse the production
  project reference. Because the historical canonical bootstrap also differs
  from production, local pgTAP proves the repository SQL contract but not remote
  production parity.
- CI artifacts may retain screenshots/traces; personal screenshots do not belong in Git.

The dormant staging suite contains manual stock adjustment/reversal and the
historical rounded/partial-payment journey. Those are useful regression
specifications, but they are not current production proof.
