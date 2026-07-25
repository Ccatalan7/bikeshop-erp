# Zoho Import Quarantine

The ignored Python files under this directory are historical local artifacts.
They are not reviewed, canonical, or approved for production execution. Do not
run, copy, or treat them as agent examples, even if a local checkout still
contains one.

When a Zoho import is needed, the agent must first create or recover a tracked
tool, review it, and add focused tests. The tool must:

- obtain Zoho and Supabase private credentials from the protected process
  environment or documented operating-system credential store, never source,
  chat, `.env`, generated files, or prompts;
- require and validate the exact intended `SUPABASE_URL`;
- use the modern `SUPABASE_SECRET_KEY` only when privileged administration is
  genuinely required, never the compromised legacy service-role JWT;
- validate and preview the complete batch before mutation;
- use authenticated, tenant-scoped atomic commands. Product stock changes go
  only through the idempotent `public.apply_product_import_stock` RPC;
- use stable idempotency keys/import references and read back the resulting
  records, stock movements, and audit/accounting evidence; and
- avoid factory resets, destructive replacement, and direct stock updates.

Agents execute the routine workflow themselves. Ask the owner only for a
credential/provider approval that is unavailable to the agent or for an
irreversible business decision.

Canonical operational guidance:

- `docs/development/SUPABASE_WORKFLOW.md`
- `docs/runbooks/STAGING_SUPABASE.md`
- `.github/copilot-instructions.md`, section “Import services”

Tracked JSON, SQL, Dart, and mapping files here are historical reference data,
not proof that the ignored importer scripts are safe.
