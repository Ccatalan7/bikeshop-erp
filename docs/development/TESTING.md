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
| Phase/release checkpoint | `just verify`, `just db-test`, required builds and browser E2E |

## Rules

- Run one full gate per coherent batch, not after each edit.
- A failed targeted test must be understood before widening the test scope.
- Browser exploration is discovery; convert a confirmed regression into a repeatable test.
- `just e2e` is the repeatable staging browser gate. It always compiles
  `lib/main.dart` (ERP, not the storefront), disables the service worker to
  prevent stale test artifacts, and serves clean routes with the local SPA server.
  Before the browser starts, it verifies the exact synthetic staging tenant and
  actor, refuses a staging ref equal to production, and restores the deterministic
  fixture through the audited stock-adjustment kernel. After Playwright passes,
  a read-only database assertion proves the UI-generated 10 → 9 → 10 movement
  pair, balanced journals, completed trace checkpoints, and zero linked
  inconsistencies. Pass a spec path after the command to iterate on one journey.
- Production smoke checks are authenticated and non-destructive.
- Database tests use disposable local/staging data and must refuse the production project reference.
- CI artifacts may retain screenshots/traces; personal screenshots do not belong in Git.

The manual stock-adjustment forward/reversal journey is now covered end to end.
The remaining critical workflow matrix is multi-bike jobs, rounded/partial
payments, every sales channel, receiving, and returns/credit notes; their
database kernels already have pgTAP coverage, while their user journeys still
need the same deterministic browser treatment.
