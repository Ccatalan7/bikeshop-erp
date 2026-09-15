# Manual Database Checks

These files are operational evidence and reviewed manual tools. They are not
schema sources and are never applied automatically. Forward schema changes
belong exclusively to uniquely versioned standalone files under
`supabase/migrations/`; production migration history is their deployment stamp.
`supabase/sql/core_schema.sql` is incomplete historical/local context only.

## Directories

- `diagnostics/`: read-only checks. Run hosted checks through
  `bash scripts/db/query.sh <staging|production> --file <path>` so the helper
  enforces a read-only transaction and timeout.
- `recovery/`: quarantined mutating repair or test-data scripts. A file here is
  historical evidence, not authorization to execute it. Before use, prove the
  target tenant and incident, take a backup, preview affected rows, review the
  current live functions/triggers, and capture before/after invariants.
- `archive/`: superseded deployment/fix SQL retained only for provenance. Never
  deploy from this directory; compare any useful logic with the live catalog
  and current migrations instead.

Production diagnostics use guarded read-only `query.sh`. Authorized schema
writes use `scripts/db/deploy_migration.sh`, which accepts only a standalone
migration plus executable verification files, then verifies and stamps the
exact version. Moving a historical file into this tree does not certify that it
is current or deployable.
