# Product Import Stock Contract

This file formerly described the superseded session-variable/direct-update
design. It is intentionally reduced to the current contract so agents do not
copy obsolete SQL Editor, `set_config`, or multi-request mutation patterns.

Product stock imports must use
`public.apply_product_import_stock(uuid, integer, text, text)`:

- authenticated and tenant-scoped;
- one atomic database command;
- stable idempotency key and durable command receipt;
- stock movement and operation audit linkage; and
- no direct `products.stock_quantity` update.

The function and its pgTAP contract are defined in:

- `supabase/migrations/20260712095000_add_product_import_stock_command.sql`
- `supabase/tests/product_import_stock_command.sql`
- `supabase/sql/core_schema.sql`

Operational execution, credential handling, production-derived validation, and
guarded deployment are documented only in:

- `docs/development/SUPABASE_WORKFLOW.md`
- `docs/runbooks/STAGING_SUPABASE.md`
- `.github/copilot-instructions.md`, section “Import services”

Agents own routine preview, execution, replay, read-back, and evidence.
Irreversible source-of-truth choices or unavailable provider credentials are
the only valid human handoffs.
