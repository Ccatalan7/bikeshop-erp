# Repository Structure

## Canonical locations

- `lib/`: Flutter production code organized by business module.
- `test/`: Flutter unit/widget/integration tests and named fixtures.
- `supabase/migrations/`: immutable historical migrations.
- `supabase/sql/core_schema.sql`: idempotent canonical schema snapshot.
- `supabase/tests/`: pgTAP database contracts.
- `supabase/functions/`: Edge Functions.
- `scripts/bootstrap/`: workstation installation.
- `scripts/dev/`: doctor, verification and safe cleanup.
- `scripts/deploy/`: guarded deployment entry points only.
- `scripts/diagnostics/`: maintained read-only diagnostics.
- `scripts/data_migrations/`: reviewed, repeatable data migrations.
- `docs/architecture/`: active architectural doctrine.
- `docs/development/`: developer contracts and standards.
- `docs/runbooks/`: operational procedures.
- `docs/archive/`: indexed historical handoffs.
- `tools/`: separately reproducible support services.

## Forbidden tracked content

Do not track installed dependencies, virtual environments, build/cache directories, credentials, token outputs, personal screenshots, raw command logs, editor-local launch secrets or temporary repair scripts.

Historical SQL, one-off scripts and root documentation are not deleted by pattern. Each receives a provenance classification before it is kept, moved, archived or removed. `just clean-generated` previews explicit generated paths and requires `VINABIKE_CLEAN_CONFIRM=YES` before deleting local copies.
