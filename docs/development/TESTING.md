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
- Production smoke checks are authenticated and non-destructive.
- Database tests use disposable local/staging data and must refuse the production project reference.
- CI artifacts may retain screenshots/traces; personal screenshots do not belong in Git.

The critical workflow matrix remains the one defined in the engineering plan: multi-bike jobs, rounded/partial payments, every sales channel, receiving, returns/credit notes, ledger continuity, and balanced journals in both forward and reversal directions.
