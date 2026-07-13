# Engineering Environment and Repository Professionalization Plan

**Status:** implementation in progress

**Prepared:** 2026-07-12

**Scope:** secure and standardize development on macOS and Windows, make testing/deployment reproducible, and clinically clean the repository without risking production data or active code.

## Execution ledger

This ledger records completed gates without redefining the original scope.

| Phase | State | Verified result |
|---|---|---|
| 0 — Security containment | In progress | Private recovery baseline, HEAD sanitization, Gitleaks gate, database-password rotation, and protected secret storage completed. Historical purge and remaining provider-alert disposition remain. |
| 1 — Governed delivery | In progress | `main` is protected with required secret/integrity checks; staging/Production environments and reconciliation PR #2 exist. Canonical merge and production proof remain. |
| 2 — Reproducible workstations | In progress | Pinned tool manifest, FVM/Volta/uv contracts, unified `just` commands, Mac/Windows bootstrap, and doctor scripts implemented. Mac doctor passes; clean Windows 2022 checkout, dependency install, release build, packaging, checksum, and artifact publication passed in GitHub Actions run 29186477212. A physical clean-Windows bootstrap/doctor exercise remains optional operational proof. |
| 3 — Staging/database | In progress | Lean staging contract is mandatory; canonical hosted apply passed with unchanged business counts; local/staging application drift is zero; first-pass view idempotency and included-SQL cache invalidation are regression-tested. Browser discovery restored a missing dashboard RPC contract. Production/canonical historical drift remains classified but unresolved. |
| 4 — Test ladder | In progress | Secret and ERP integrity workflows exist; the complete 724-assertion pgTAP suite passes. Playwright verifies routed inventory/sales/purchases, reversible stock adjustment, and the historical CLP 8,999 + 1 partial-payment failure mode through both payment reversals. Database post-checks prove exact balances/statuses, journal cleanup, completed traces, and zero payment stock effects. Remaining document journeys and native coverage remain. |
| 5 — Releases/rollback | In progress | Firebase web releases now embed/retain commit and checksum evidence, verify the exact live commit, and run post-deploy read-only ERP invariants. A practiced rollback and signing completion remain. |
| 6 — Repository cleanup | Completed | Generated waste/screenshots and dead rewrites were removed; root SQL is fully classified; historical records are archived; the three confirmed dead `*_old`/`*_legacy` Dart implementations were removed; active architecture, guides, and development plans now live in their canonical directories with only four mandated Markdown entry/doctrine files at root. No ambiguous source was deleted. |
| 7 — Technology radar | In progress | Dependabot coverage, upgrade policy, living radar, and weekly issue automation are implemented. First scheduled run and controlled trial evidence remain. |

## Target outcome

Any authorized developer or Codex session must be able to clone the repository, run one bootstrap command, pass one doctor command, start a disposable Supabase environment, test the real ERP workflows in a browser, build every supported release, and deploy only through guarded pipelines. The repository must contain source, reproducible configuration, tests, and useful documentation—not credentials, local caches, virtual environments, screenshots, or unidentified one-off files.

This is not a one-time setup. The project must continuously discover relevant changes in AI-agent capabilities, SDKs, CLIs, browsers, databases, CI systems, security tooling, and platform build systems. The agent is responsible for finding useful improvements proactively, evaluating them against this ERP, and keeping the approved stack current without waiting for the owner to name each new tool.

## Audit baseline

The initial read-only audit found:

- The public GitHub repository has **9 open secret-scanning alerts**. Tracked files include production credential material, Zoho token output, and the shared ERP debug login. Credential response is therefore Phase 0, before normal cleanup.
- The current working branch is `smartpegas1.0`; it is hundreds of commits ahead of the default `main` branch. Neither branch is protected, so the current CI gate does not govern all production changes.
- Flutter 3.38.5 is installed and matches CI, but Flutter/Dart and Android tools are missing from `PATH`; Android licenses are incomplete. Node 26 is an unpinned Current release, not the preferred LTS line.
- Supabase, Firebase, GitHub, Docker/Colima, PostgreSQL, Xcode, CocoaPods, and Chrome are available and authenticated on this Mac. Supabase production is healthy; the existing staging project is inactive.
- Existing coverage is valuable: 39 pgTAP files, 29 Flutter test files, analyzer execution, ERP web compilation, and Windows packaging. There are no Playwright tests and no Flutter `integration_test` suite.
- CI and local Supabase versions drift, migrations are disabled/non-replayable, and `core_schema.sql` is currently the only deterministic database bootstrap.
- The repository tracks 5,204 files, including 235 files in the root: 91 SQL, 51 Markdown, 23 Python, and many temporary outputs. It also tracks a 3,059-file Python virtual environment, Firebase caches, scratch folders, token output, and hundreds of screenshots. Git storage is about 1 GB.
- The current dirty worktree contains unrelated user changes. They must be preserved throughout this program.

## Non-negotiable safety rules

1. **Rotate credentials before deleting or rewriting history.** Removing a secret from Git does not revoke it.
2. **Back up before structural work.** Create a remote tag, repository mirror, production schema/data backup, and restore proof before migration or history surgery.
3. **Never use production for destructive tests.** Browser and reversal journeys use a disposable staging tenant and deterministic fixtures.
4. **Quarantine uncertainty.** Delete only generated files or files proven unused by references, routes, history, builds, and tests. Ambiguous SQL/data-repair evidence is catalogued and retained.
5. **Small, single-purpose commits.** Security, tooling, file moves, dead-code removal, schema work, and behavior changes never share one large commit.
6. **Verify before and after every batch.** Capture the baseline, apply one batch, rerun its gate, and compare results.
7. **Preserve canonical sources.** `supabase/sql/core_schema.sql` remains idempotent and canonical; applied migration history is never casually edited or deleted.
8. **Stay current without chasing novelty.** Awareness is continuous; adoption is controlled. Prefer supported stable/LTS releases, prove compatibility in staging, and never auto-promote an untested toolchain or model change into production.

## Execution plan

### Phase 0 — Security containment and recoverable baseline

- Export the GitHub secret-alert inventory without printing secret values and run Gitleaks against the working tree and full Git history.
- Revoke/rotate every confirmed exposed credential, beginning with Supabase database/service credentials, Zoho OAuth tokens, the shared ERP login, and any Google/Firebase keys identified as private. Verify each dependent app/function after rotation.
- Replace secrets in documentation, launch configuration, scripts, and examples with variable names and safe lookup instructions. Store local secrets in macOS Keychain or Windows Credential Manager/password-manager-backed local environment files; store CI secrets only in protected GitHub Environments.
- Create a limited, non-production E2E user. Never reuse the owner/coworker login in automated tests.
- Tag the current known state, create an offline mirror, record the dirty-worktree manifest, and take an independent encrypted database backup.
- After rotation, remove secret-bearing files from HEAD. Coordinate a separate `git filter-repo` history purge, force-push, invalidate old clones, and freshly clone every development machine.

**Gate:** no valid open secret alerts; full-history Gitleaks passes; rotated integrations work; backup and fresh-clone instructions are proven.

### Phase 1 — One governed delivery branch

- Reconcile `smartpegas1.0` into a backed-up canonical `main`; do not discard either history.
- Protect `main`: pull requests, required integrity/E2E checks, resolved conversations, no force pushes, and no direct production deploys.
- Create GitHub `staging` and `production` Environments. Production requires approval and keeps deployment credentials separate from preview credentials.
- Change local deploy helpers so they run verification and dispatch the guarded workflow; they must not bypass CI with a direct production upload.
- Keep Firebase ERP/store and Windows releases tied to the same canonical commit SHA and release record.

**Gate:** an untested commit cannot reach Firebase, Supabase, or a Windows release.

### Phase 2 — Reproducible macOS and Windows workstations

Create and commit the following contracts:

- `.fvmrc`: initially pin the currently proven Flutter 3.38.5. Test a move to the latest supported stable patch on a separate upgrade branch; do not combine it with cleanup.
- `package.json`/lockfile: pin Node 24 LTS with Volta and pin project-local Supabase CLI, Firebase CLI, Playwright, and other Node tools. Use `npm ci`, not floating global installs.
- Python services: replace committed virtual environments with `pyproject.toml` + `uv.lock`; pin Python and recreate environments with `uv sync`.
- Pin/document Deno, Wrangler, PostgreSQL client, JDK 17, CocoaPods, and platform SDK expectations in a machine-readable version manifest.
- `Brewfile` plus `scripts/bootstrap/bootstrap_macos.sh` for Git/GitHub CLI, FVM, Volta, uv, Docker-compatible runtime, PostgreSQL, CocoaPods, PowerShell 7, Gitleaks, shell tooling, and `just`.
- WinGet configuration plus `scripts/bootstrap/bootstrap_windows.ps1` for Git, GitHub CLI, FVM, Volta, uv, Docker Desktop, PowerShell 7, PostgreSQL, Android tooling, Visual Studio 2022 C++ workload, Windows SDK, WebView2, Gitleaks, and `just`.
- `scripts/dev/doctor.sh` and `doctor.ps1` check versions, `PATH`, disk/RAM, Docker, Flutter targets, Android licenses, auth/link state, required secrets by name only, Firebase aliases, Supabase project ref, and writable build directories. They must explain an exact fix and return nonzero on a blocker.
- Commit both Android Gradle wrappers; a fresh clone must not depend on wrappers ignored on the original machine.

Use `just` as the cross-platform command surface: `just bootstrap`, `just doctor`, `just verify`, `just db-test`, `just e2e`, `just build-all`, and `just clean-generated`.

**Gate:** fresh macOS and Windows clones bootstrap and pass `just doctor` and `just verify` without undocumented steps.

### Phase 3 — Safe staging and database source of truth

- Reactivate or recreate a separate Supabase staging project and use Firebase preview channels. Seed a dedicated tenant/user with synthetic products, jobs, invoices, payments, stock, returns, and credit-note fixtures.
- Add deterministic fixture reset/cleanup. E2E tests must leave staging in its known initial state and must refuse a production project ref.
- Before changing migration strategy, compare production, `core_schema.sql`, and a fresh local database by schema fingerprint; run `db lint` and classify every finding.
- Preserve the 283 historical migration files as immutable evidence. Create a verified baseline for new clones, resolve invalid/duplicate migration identifiers in a documented legacy manifest, then enable a clean forward-only migration stream.
- Add gates for fresh bootstrap, second application of the idempotent canonical snapshot, pgTAP, migration/snapshot parity, lint, and hosted drift detection. Mirror every future schema change into `core_schema.sql`.
- Deploy database changes serially: staging first, before/after invariants, backup confirmation, production apply, then the same invariants and business smoke queries.
- Establish off-platform encrypted logical backups and a scheduled isolated restore drill. Enable managed backups/PITR if the selected Supabase plan supports the required RPO/RTO.

**Gate:** a blank database reaches the verified schema fingerprint and passes all database tests; a documented restore succeeds without touching production.

### Phase 4 — Professional test ladder

Add failures at the earliest useful layer:

1. **Pre-commit/fast:** Gitleaks, formatting, YAML/JSON validation, shell lint, generated-file drift, and changed-file tests.
2. **Pull request:** fatal analyzer policy with an explicit burn-down baseline, all Flutter tests, all pgTAP tests, database lint/parity, dependency/security audit, CodeQL, and ERP/store release builds.
3. **Browser E2E:** Playwright on a Firebase preview/staging backend, one worker in CI for stability, screenshots/traces only as CI artifacts.
4. **Native integration:** Flutter `integration_test` for macOS/Windows and selected Android workflows; add iOS build verification on macOS where applicable.
5. **Exploratory QA:** Codex in-app browser against the preview build for visual and workflow discovery. Exploratory findings become repeatable Playwright/integration tests before closure.
6. **Post-deploy smoke:** authenticated, non-destructive checks against the exact deployed commit and read-only production invariants.

The critical E2E matrix must cover forward and backward actions for login; jobs with one and multiple bicycles; sales invoices; partial/rounded payments and reversals; POS, online and quick sales; purchase invoices and goods receipt; manual and mass stock changes; sales/purchase returns; credit notes; stock-ledger continuity; and balanced accounting journals.

Expand the canonical UI-surface registry beyond invoices so every business workflow has one routed owner, one user-visible entry point, and a route test. A hidden or unrouted feature must fail CI.

**Gate:** breaking a normal click path, reversal, stock balance, money balance, journal balance, or canonical UI surface causes a required check to fail.

### Phase 5 — Controlled builds, releases, and rollback

- Pipeline: PR preview → complete gates → staging deploy → E2E → approval → production promotion → post-deploy smoke.
- Produce identifiable artifacts for ERP web, storefront web, Windows, macOS, and supported mobile builds; embed commit SHA/version and retain checksums/SBOM where practical.
- Sign Windows releases; add Android release keystore handling; add Apple signing/notarization when macOS distribution is formalized. Secrets stay in platform/GitHub stores.
- Record deployment and schema checkpoints with actor, commit, environment, timestamps, before/after checks, and rollback reference.
- Maintain tested rollback runbooks for Firebase hosting, Windows updater, Supabase schema/data recovery, and credential failure.

**Gate:** every release is attributable, verified, and recoverable; a failed post-deploy check stops promotion or triggers the documented rollback.

### Phase 6 — Clinical repository cleanup

Generate a cleanup inventory containing `path`, `type`, `tracked`, `size`, `last change`, `references`, `production provenance`, `classification`, `decision`, and `verification`. Execute these batches independently:

1. **Confirmed generated/security waste:** remove tracked virtual environments, `.firebase` cache, `.tmp`/`tmp` outputs, token files after rotation, `.DS_Store`, generated Flutter metadata, logs, and local launch credentials; strengthen `.gitignore` and pre-commit guards.
2. **Screenshots/reports:** remove personal/debug screenshots from Git; keep only small named test fixtures under `test/fixtures`. Store intentional large media outside the source repository or with an explicitly managed artifact system.
3. **SQL:** never bulk-delete the 91 root SQL files. Establish provenance, then move retained operational checks to `supabase/manual_checks/{diagnostics,recovery,archive}` with safety/tenant/purpose headers. Delete only proven terminal captures or superseded duplicates. Keep migrations, tests, and `core_schema.sql` in their canonical locations.
4. **Scripts:** retain maintained bootstrap, CI, deploy, diagnostic, and data-migration tools; require purpose/usage/safety headers. Delete one-off mutators and outputs only after reference and historical-purpose review.
5. **Documentation:** move living docs to `docs/{architecture,development,guides,runbooks,decisions}`; consolidate stale handoffs under `docs/archive/YYYY-MM` with an index; remove dangerous competing schema documents after unique doctrine is merged.
6. **Dart/assets:** use imports, exports, routes, dynamic entry points, asset references, and builds to validate candidates. Remove dead placeholders/`*_old`/`*_legacy` files in small batches. Treat CLI entry-point Dart files separately. Fix missing asset references before removing unused prototypes.
7. **Hosting/config:** Firebase is active. Remove Netlify/Vercel/root-web leftovers only after checking DNS, GitHub integrations, and external deployment use.
8. **Modularization:** split 10k+ line Dart files by domain responsibility behind tests. Mechanical moves and behavior changes remain separate commits; consolidate duplicate model/service families incrementally.

Run the full applicable gate after every batch and compare route count, test count, schema fingerprint, artifact builds, and `git status` with the pre-batch baseline.

**Gate:** fresh clone/build/test succeeds on both platforms; no tracked generated noise returns; repository/root size falls materially; no route, migration evidence, inventory/accounting behavior, or deployment path is lost.

### Phase 7 — Continuous technology radar and controlled evolution

Create a permanent update loop so new capabilities are discovered by the agent instead of depending on the owner:

1. **Every substantive task:** read the repository instruction chain first—`AGENTS.md`, `.github/copilot-instructions.md`, and any applicable architecture/GUI document—then run `just doctor`, read the current technology radar, inspect the tools/skills/plugins/connectors available in the active Codex session, and check official release notes for any platform materially touched by the task. Record reusable discoveries in the same task.
2. **Weekly automated scan:** a scheduled GitHub Action checks Flutter/Dart, Node LTS, npm, Pub, uv/Python, Supabase CLI, Firebase CLI, Playwright/browsers, Deno/Wrangler, Docker images, Gradle, GitHub Actions, and security/deprecation advisories. Dependabot covers supported package ecosystems and actions; a repository script covers SDKs and CLIs that package managers cannot track.
3. **Weekly agent review:** a recurring Codex automation reads the machine report and official release notes, checks current Codex manual/docs and current-session capabilities, and updates one technology-radar issue. It must surface useful new skills, plugins, MCP/connectors, browser/test features, models, and developer tools even when the owner has not mentioned them.
4. **Technology radar:** maintain `docs/development/TECHNOLOGY_RADAR.md` with `Adopt`, `Trial`, `Assess`, `Hold`, and `Retire` entries. Every entry records the evidence, expected benefit, security/privacy/license/cost impact, macOS/Windows support, migration risk, proof-of-concept result, decision, and next review date.
5. **Controlled trials:** a promising tool gets a small isolated proof-of-concept branch and representative ERP tests. Adoption requires a measurable improvement in reliability, test coverage, speed, security, traceability, or maintainability; novelty alone is not a reason to add another dependency.
6. **Upgrade train:** compatible patches and security fixes are grouped weekly; minors are reviewed monthly; majors and platform/toolchain migrations use a dedicated quarterly upgrade branch or an earlier branch when support/security requires it. All use the full staging, E2E, build, and rollback gates.
7. **AI capability rule:** repository doctrine remains in `AGENTS.md` and `.github/copilot-instructions.md`; official OpenAI Docs/Codex manuals are a separate source for current product capabilities. Use both, plus callable current-session capabilities—not model memory—when choosing Codex surfaces, models, skills, plugins, hooks, MCP servers, browser control, or automation. Adopt a better capability when it is authorized and proven; otherwise create a concise approval item with the exact benefit and required user action.
8. **Retirement:** monitor end-of-life dates and remove superseded tools after all consumers move. No production dependency may silently pass its supported lifetime.

Service levels:

- critical exploited vulnerability, revoked credential, or breaking deprecation: triage the same day;
- supported low-risk patch/security update: evaluate in the next weekly train;
- compatible minor release or useful new capability: evaluate monthly;
- major release/toolchain replacement: evaluate at least quarterly and before the current version approaches end of support.

**Gate:** the weekly scan and agent review run successfully, the radar has no overdue critical item, update proposals include test evidence, and no upgrade reaches production outside the normal release controls.

## Target repository layout

```text
docs/
  architecture/  development/  decisions/  guides/  runbooks/  archive/
scripts/
  bootstrap/  ci/  deploy/  dev/  diagnostics/  data_migrations/
services/
  invoice-parser/
supabase/
  migrations/  tests/  functions/
  sql/core_schema.sql
  manual_checks/{diagnostics,recovery,archive}/
test/
  unit/  widget/  integration/  fixtures/
```

## Required living documentation

- `docs/development/TOOLCHAIN.md`
- `docs/development/SETUP_MACOS.md`
- `docs/development/SETUP_WINDOWS.md`
- `docs/development/TESTING.md`
- `docs/development/SECURITY.md`
- `docs/development/RELEASES.md`
- `docs/development/REPOSITORY_STRUCTURE.md`
- `docs/development/TECHNOLOGY_RADAR.md`
- `docs/development/UPGRADE_POLICY.md`
- `docs/runbooks/DATABASE_BACKUP_AND_RESTORE.md`
- `docs/runbooks/PRODUCTION_INCIDENT.md`

## User-only actions

Codex can implement scripts, configuration, cleanup, tests, and verification. The owner may need to complete or approve:

- credential rotation, MFA, and expired Supabase/Firebase/GitHub/Zoho sessions;
- staging project creation or billing/backup-plan changes;
- Android/Xcode license prompts requiring interactive acceptance;
- Apple signing identity, Android release keystore, and Windows signing certificate;
- coordinated fresh clones after a Git-history rewrite.

Each request must be presented as a short exact checklist; routine technical work must not be handed back to the owner.

## Definition of done

This program is complete only when:

- a clean Mac and Windows machine pass bootstrap, doctor, full verification, and supported builds;
- no valid credentials exist in HEAD/history and secret prevention is enforced;
- protected CI controls every production release;
- local, staging, and production schemas have a verified relationship and recoverable backups;
- critical forward/reversal ERP workflows pass automated browser and database checks;
- the cleanup inventory has a recorded disposition for every root/temporary candidate;
- scheduled dependency/tool/AI-capability discovery is active and produces controlled, tested upgrade proposals;
- documentation lets a non-developer follow setup and lets a future agent work without hidden assumptions.

## Authoritative references

- [Flutter SDK archive and stable-channel guidance](https://docs.flutter.dev/install/archive)
- [Supabase local development and CLI](https://supabase.com/docs/guides/local-development)
- [Firebase CLI installation and CI authentication](https://firebase.google.com/docs/cli)
- [Playwright continuous integration](https://playwright.dev/docs/ci)
- [Node.js release/LTS policy](https://nodejs.org/en/about/previous-releases)
- [GitHub sensitive-data remediation](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository)
- [GitHub Dependabot version updates](https://docs.github.com/en/code-security/concepts/supply-chain-security/dependabot-version-updates)
- [GitHub scheduled workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onschedule)
- [Codex workflow and automation use cases](https://developers.openai.com/codex/use-cases)
