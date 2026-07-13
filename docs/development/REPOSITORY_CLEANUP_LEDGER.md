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

## Retained pending classification

- root deployment/fix/recovery SQL;
- old/legacy Dart files;
- one-off Python/Dart mutation scripts and their historical inputs;
- Vercel/Netlify configuration while external integration/DNS provenance is
  being confirmed;
- archived handoff documents whose unique doctrine has not yet been merged.
