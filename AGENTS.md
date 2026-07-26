# Codex Agent Instructions (Repo-Wide)

- Before making changes, read `.github/copilot-instructions.md` and follow it.
- For any UI/frontend work, read `.github/GUI_DESIGN_PRINCIPLES.md` first and
  follow it.
- For mobile, tablet, compact, adaptive, or responsive UI work, read and follow
  both `.github/GUI_DESIGN_PRINCIPLES.md` and
  `.github/GUI_MOBILE_DESIGN_PRINCIPLES.md`.
- For business-workflow UI changes, read
  `docs/architecture/canonical-ui-surfaces.md`, update its registry when a
  surface changes, and verify the shared action on every registered routed,
  embedded, split-pane, and quick-action surface.
- For bike workshop architecture work, read `BIKE_WORKSHOP_MASTER_SCHEMA.md` first and update it in the same task when behavior/schema/data-flow changes.
- For Supabase/database work:
  - Read `docs/runbooks/STAGING_SUPABASE.md` and follow its mandatory-use and evidence rules.
  - Prefer Supabase CLI for local DB workflows and verification (schema, triggers, functions, policies, tests).
  - Treat `supabase/sql/core_schema.sql` as the canonical schema snapshot. If any schema SQL is authored or run, mirror it into `supabase/sql/core_schema.sql` (or confirm it already contains the same objects/logic).
  - Keep `supabase/sql/core_schema.sql` idempotent (safe to re-run on an existing local DB).
