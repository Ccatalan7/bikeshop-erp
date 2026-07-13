# Manual Database Checks

These files are operational evidence and reviewed manual tools. They are not
schema sources and are never applied automatically. The canonical schema is
`supabase/sql/core_schema.sql`; forward schema changes belong in the governed
migration stream and must also be mirrored into that snapshot.

## Directories

- `diagnostics/`: read-only checks. Run hosted checks through
  `bash scripts/db/query.sh <staging|production> --file <path>` so the helper
  enforces a read-only transaction and timeout.
- `recovery/`: quarantined mutating repair or test-data scripts. A file here is
  historical evidence, not authorization to execute it. Before use, prove the
  target tenant and incident, take a backup, preview affected rows, review the
  current canonical functions/triggers, and capture before/after invariants.
- `archive/`: superseded deployment/fix SQL retained only for provenance. Never
  deploy from this directory; compare any useful logic with the canonical
  snapshot and current migrations instead.

Production writes are intentionally unsupported by `scripts/db/query.sh`.
Moving a historical file into this tree does not certify that it is current.
