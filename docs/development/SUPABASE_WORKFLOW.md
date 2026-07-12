# Supabase Development Workflow

The repository remains linked to production for deployment metadata. Development and destructive tests use local Supabase; staging is used for hosted integration. Commands never relink the repository as a side effect.

## Fast daily commands

```text
just db-status
just db-start
just db-test payment_integrity_guards
just db-test stock_ledger_continuity sales_credit_note_kernel
just db-query local "select count(*) from stock_movements"
```

`db-start` reuses the running local stack when the canonical schema hash is unchanged. It rebuilds only when the schema changes, the expected ERP objects are absent, or `--reset` is requested. Detailed schema output goes to `.tmp/db/` instead of flooding the agent context.

`db-test` accepts partial pgTAP filenames and prints exactly which files run. With no selector it runs all database tests against the already prepared local database.

## Query helper

```text
bash scripts/db/query.sh local --sql "select * from stock_movements limit 10" --format table
bash scripts/db/query.sh staging --sql "select count(*) as movements from stock_movements" --format json
bash scripts/db/query.sh production --file supabase/manual_checks/diagnostics/example.sql
just db-trace production operation 00000000-0000-4000-8000-000000000000
just db-trace production product 00000000-0000-4000-8000-000000000000
just db-trace production tenant 00000000-0000-4000-8000-000000000000
```

Formats are `table`, `csv`, and `json`. Staging and production queries automatically run inside a read-only transaction with a 30-second timeout. Transaction escape statements are rejected. The helper never permits production writes. Staging writes require both `--write` and `VINABIKE_DB_WRITE_CONFIRM=staging`.

Remote passwords are read without printing from macOS Keychain. Windows/CI can supply `SUPABASE_DB_PASSWORD`, `SUPABASE_STAGING_PROJECT_REF`, and `SUPABASE_STAGING_DB_PASSWORD` through the approved credential store/environment.

## Full database gate

Run `just db-gate` only for schema/trigger/function changes or a phase/release checkpoint. It deliberately drops the disposable local `public` schema, applies `supabase/sql/core_schema.sql`, and runs every pgTAP file. This is the slow proof; it is not the default debugging loop.

Production mutation, repair, migration, and deployment remain separate reviewed operations with before/after invariants and the database backup runbook.

`db-trace` returns analysis-ready JSON from the canonical operation trace, stock-movement audit, or tenant inconsistency views. UUID validation prevents SQL injection, results are capped, and hosted queries inherit the same read-only transaction and timeout guards.
