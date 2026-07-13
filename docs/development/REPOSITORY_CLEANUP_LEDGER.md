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
  marker so the still-connected external project skips every build.
- **Remaining owner action:** disconnect/archive the Vercel Git integration when
  convenient; the marker prevents its failing build from competing with the
  governed Firebase preview pipeline meanwhile.

## Retained pending classification

- root deployment/fix/recovery SQL;
- old/legacy Dart files;
- one-off Python/Dart mutation scripts and their historical inputs;
- external Vercel project disconnection after the repository retirement marker
  is observed as a skipped build;
- archived handoff documents whose unique doctrine has not yet been merged.
