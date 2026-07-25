# Import Tool Agent Guide

These files are historical integration helpers, not blanket authorization to
mutate production. Before using one, review the exact tracked script and its
write path. Ignored `config.py` files and local copies are not trusted inputs.

## Agent contract

1. Read `docs/development/SUPABASE_WORKFLOW.md` and
   `docs/runbooks/STAGING_SUPABASE.md`.
2. Agents perform discovery, credential-presence checks, dry-run/preview,
   execution, read-back, and reporting. Ask the owner only when a provider
   credential/login is unavailable or an irreversible business decision is
   required.
3. Inject private values from the operating-system credential store into one
   process. Never prompt for reusable secrets, source `.env`, print values, or
   write them into `config.py`.
4. Require the exact `SUPABASE_URL`; use `SUPABASE_SECRET_KEY` only for a
   reviewed privileged operation. Never use the legacy service-role JWT.
5. Use a synthetic authenticated session and the narrow canonical RPC whenever
   the operation belongs to an ordinary app user. Product stock changes use
   only `public.apply_product_import_stock`.
6. Validate the complete batch before mutation. Use a stable idempotency key
   and import reference for every logical operation.
7. Preserve tenant boundaries and financial/inventory evidence. Do not factory
   reset, truncate, replace production data wholesale, or update stock
   directly.
8. Read back affected records and their stock movements, journals, command
   receipts, and error rows. A successful HTTP response alone is not evidence
   of a correct import.

## Credential names

- `SUPABASE_URL`: exact reviewed production URL or explicit loopback URL.
- `SUPABASE_SECRET_KEY`: modern independently managed privileged key.
- `ZOHO_CLIENT_ID`, `ZOHO_CLIENT_SECRET`, `ZOHO_REFRESH_TOKEN`: Zoho OAuth.
- `ODOO_API_KEY`: Odoo access key.

If the required provider credential is unavailable to the agent, stop before
network access and request only that credential-store/provider handoff. Do not
ask the user to paste a value into chat or source.

## Before adopting a helper

- Confirm the file is tracked.
- Confirm it has a dry-run or read-only preview.
- Confirm its writes use the current canonical RPC/aggregate boundary.
- Add focused tests for parsing, tenant scope, idempotency, partial failure,
  replay, and read-back.
- Run the repository secret gate and the database validation appropriate to the
  change.

Helpers that do not satisfy this list are reference material until migrated.
