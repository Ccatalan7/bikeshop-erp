# Repository Cleanup Ledger

Cleanup is evidence-based. A batch is deleted only after checking Git tracking,
size, repository references, producer/consumer behavior, and relevant builds or
tests. Ambiguous business SQL, migrations, Dart entry points, and operational
recovery evidence are retained until separately classified.

## Completed batches

### 2026-07-12 — generated root analysis/debug outputs

- **Removed:** 29 tracked files / 947,602 bytes from the working tree.
- **Classes:** model/API captures, embedding captures, import comparison CSVs,
  debug JSON, temporary analysis reports, editor target dumps, generated patch
  scripts, and OCR verification output.
- **Evidence:** 27 files had zero repository references. The two referenced
  files (`temp_full_analysis.json`, `temp_sync_report.json`) are explicitly
  generated outputs of retained scripts, not inputs or source fixtures.
- **Guard:** exact root output patterns were added to `.gitignore`.
- **Verification:** `just verify-fast`, working-tree secret scan, and the full
  database/ERP gates remain required before merge.

### 2026-07-12 — superseded root source mutators

- **Removed:** 22 unreferenced Python/shell/text files that performed literal
  one-time rewrites of Dart, SVG, or SQL source.
- **Evidence:** every script had zero callers; each encoded a completed
  replacement against a specific historical file shape or `/tmp` directory.
  The only script input (`old_code.txt`) was removed with its sole consumer.
- **Guard:** root `fix_*`, `update_*`, patch, replacement, and old-code patterns
  are ignored. Maintained automation must live under `scripts/` and have a
  documented command and safety contract.

### 2026-07-12 — temporary import probes and generated reports

- **Removed:** eight unreferenced `temp_*` Python probes and three generated
  Odoo/Zoho comparison/progress text reports.
- **Evidence:** the probes had no callers and encoded one-off token, schema,
  supplier-fix, or verification sessions. The text files were generated human
  reports with no consumers; referenced CSV migration inputs were retained.
- **Guard:** temporary import probes and named generated report families are
  ignored inside their original directories.

### 2026-07-12 — root database/UI probes

- **Removed:** eleven unreferenced Dart, Python, and JavaScript probes.
- **Evidence:** these were empty placeholders or direct one-off reads against
  specific production URLs, invoice numbers, job IDs, logs, `/tmp` SVG files,
  or source-rewrite targets. None was called by CI, `just`, application code,
  or maintained tests.
- **Guard:** root check/test probes are ignored. Maintained verification belongs
  in `test/`, `supabase/tests/`, or a documented read-only script directory.

### 2026-07-12 — inactive hosting configurations

- **Verified:** `vinabike.cl` resolves to Firebase Hosting and `www` points to
  `vinabike-store.web.app`; repository workflows deploy Firebase ERP/store.
  Vercel's last production deployment was 2025-10-16 and current activity is
  preview-only. No Netlify consumer was found.
- **Changed:** removed `netlify.toml` and replaced the obsolete Vercel Flutter
  build configuration with an explicit supported `ignoreCommand` retirement
  marker while the external integration was being retired.
- **External retirement completed:** disconnected the exact
  `ccatalan7s-projects/vinabike-erp` project from
  `Ccatalan7/bikeshop-erp` through Vercel CLI on 2026-07-12. The provider
  confirmed that repository pushes will no longer create Vercel deployments.
  Removed the temporary retirement marker afterward; Firebase remains the only
  repository-controlled hosting path.

### 2026-07-12 — root SQL diagnostics and terminal captures

- **Relocated:** seven reusable, read-only accounting/workshop diagnostics from
  the repository root to `supabase/manual_checks/diagnostics/`, with descriptive
  names and unchanged SQL content.
- **Removed:** ten unreferenced files / 43,142 bytes: two pasted `psql` table
  captures that were not valid SQL, five hard-coded tenant investigation probes,
  two one-line scratch checks (one invalid), and one generically named WhatsApp
  scratch query.
- **Evidence:** every removed file had zero repository consumers; the retained
  diagnostics were checked for mutating statements before relocation. Mutating
  recovery, test-data, and historical deployment SQL remains pending rather
  than being bulk-deleted.
- **Guard:** `supabase/manual_checks/README.md` now separates read-only
  diagnostics from quarantined recovery and archived deployment evidence and
  directs hosted reads through the enforced read-only query helper.

### 2026-07-12 — root mutating and historical SQL quarantine

- **Relocated without content changes:** all 74 remaining root SQL files. Fifty-
  four superseded rollout/schema snapshots now live in
  `supabase/manual_checks/archive/`; twenty data repair, emergency, reset, and
  mutating test scripts now live in `supabase/manual_checks/recovery/`.
- **Safety:** no SQL was executed and no historical SQL body was edited. The
  recovery directory is explicitly non-authoritative and requires incident,
  tenant, backup, preview, current-trigger, and before/after review before any
  use. Archive SQL must never be used as a deployment source.
- **References:** updated the workshop master schema, historical task-system
  docs, the rogue-trigger migration/comment, and the one Dart provenance comment
  so no live documentation points users at a root script or instructs them to
  paste obsolete SQL into production.
- **Verification:** all 74 pre/post Git blob hashes match, the repository root
  contains zero SQL files, paths have no stale consumers, and the focused fast
  repository gate is required before commit.

### 2026-07-12 — dated handoff archive

- **Relocated without content changes:** eleven explicit handoff documents from
  the repository root into `docs/archive/2026-01` through `2026-06`, based on
  their recorded date or original Git creation date.
- **References:** updated the three living documents that linked to moved
  handoffs and added `docs/archive/README.md` as the archive index and safety
  contract.
- **Safety:** archived context remains searchable and attributable, but is
  explicitly non-authoritative so old SQL/deployment instructions cannot be
  mistaken for current operating procedure.
- **Verification:** all eleven Git blob hashes are unchanged after relocation,
  no handoff remains at repository root, and no old root link remains.

### 2026-07-12 — completed fix and migration summaries

- **Relocated without content changes:** eight unreferenced documents explicitly
  describing completed fixes, migrations, schema cleanup, redesign completion,
  or a historical sync incident. Their Git creation dates place them under
  `docs/archive/2025-11` through `2026-04`.
- **Safety:** living architecture, feature specs, user guides, and active plans
  were deliberately excluded from this batch. External documentation links in
  the archived Firebase migration record remain valid.
- **Verification:** all eight Git blob hashes are unchanged, each source had zero
  repository consumers, and the archive index records the added periods.

### 2026-07-12 — completed stock-page rewrite helpers

- **Removed:** `scripts/fix_purchase_inline.py` and
  `scripts/fix_chilean_utils.py` (1,698 bytes total).
- **Evidence:** both files had zero consumers and existed only to perform literal
  one-time rewrites against `stock_movements_page.dart`; the second corrected a
  duplicate token introduced by the first. Neither was a maintained test,
  migration, build tool, or runtime input.
- **Verification:** the target Dart source remains untouched by this cleanup,
  no reference to either helper exists, and the fast repository gate is
  required before commit.

### 2026-07-12 — unreachable legacy Dart implementations

- **Removed:** `dynamic_website_page_old.dart`, `public_home_page_old.dart`, and
  `mechanic_job_task_service_legacy.dart` (2,018 lines / 66,091 bytes).
- **Evidence:** none had a code import, route, provider, test, or script consumer.
  The public-store routes use the current pages; mechanic jobs use the provider-
  registered `SmartTaskService` from both the job form and task tab. Historical
  handoff mentions remain archived as provenance, not consumers.
- **Safety:** no live surface, model, database flow, or asset changed. The bike
  workshop master now explicitly names the canonical task service so agents do
  not recreate the deleted parallel contract.
- **Verification:** analyzer/tests and ERP/store builds remain required before
  this batch is accepted.

### 2026-07-12 — living documentation layout

- **Relocated without content loss:** fifteen active architecture/specification
  documents to `docs/architecture/`, eleven operator/developer guides to
  `docs/guides/`, the egress implementation plan to `docs/development/`, and
  the unreferenced October 2025 ad-hoc rollout report—with explicitly paused
  phases and links to documents that never existed—to `docs/archive/2025-10/`.
- **Root contract:** only `README.md`, `AGENTS.md`,
  `BIKE_WORKSHOP_MASTER_SCHEMA.md`, and
  `BIKE_WORKSHOP_COMPATIBILITY_CONCEPTS.md` remain as root Markdown because they
  are repository entry points or mandated workshop doctrine.
- **References:** updated root pointers, cross-directory archive links, OCR
  entry points, and archived Smart Tasks provenance. Same-directory architecture
  and guide links remain valid after their groups moved together.
- **Verification:** Git rename detection must account for all 28 sources, edits
  are limited to corrected path references, and the permanent local Markdown
  link check in `verify-fast` must pass before acceptance.

## Retained pending classification

- no further deletion candidate is approved; retained entry scripts and living
  documents now have maintained locations or explicit repository-entry roles.
