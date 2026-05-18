# Codex Agent Instructions (Repo-Wide)

- Before making changes, read `.github/copilot-instructions.md` and follow it.
- For UI/frontend work, read `.github/GUI_DESIGN_PRINCIPLES.md` first and follow it.
- For bike workshop architecture work, read `BIKE_WORKSHOP_MASTER_SCHEMA.md` first and update it in the same task when behavior/schema/data-flow changes.
- For Supabase/database work:
  - Prefer Supabase CLI for local DB workflows and verification (schema, triggers, functions, policies, tests).
  - Treat `supabase/sql/core_schema.sql` as the canonical schema snapshot. If any schema SQL is authored or run, mirror it into `supabase/sql/core_schema.sql` (or confirm it already contains the same objects/logic).
  - Keep `supabase/sql/core_schema.sql` idempotent (safe to re-run on an existing local DB).
