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
- There is no hosted test database (owner, 2026-10-30). Browser journeys run
  against the local stack through the local launchers in `scripts/e2e/`
  (`run_task_form_local.sh`, `run_android_local_journey.sh`, …); checks that
  need real data run in production, as `docs/runbooks/STAGING_SUPABASE.md`
  («Where tests run») describes.
- Production smoke checks are authenticated and non-destructive.
- Database tests use disposable local data and must refuse the production
  project reference. Because the historical canonical bootstrap also differs
  from production, local pgTAP proves the repository SQL contract but not remote
  production parity.
- CI artifacts may retain screenshots/traces; personal screenshots do not belong in Git.

The staging suite (manual stock adjustment/reversal and the CLP 8,999 + 1
rounded/partial-payment journey) was removed with the staging project on
2026-10-30. Its specs stay in Git history
(`git log --diff-filter=D -- 'e2e/staging_*.spec.ts'`); port one to a local
fixture when that regression needs browser coverage again.
