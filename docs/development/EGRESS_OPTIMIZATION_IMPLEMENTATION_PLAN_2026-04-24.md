# Egress Optimization Implementation Plan - 2026-04-24

## Purpose
Keep the ERP and public store crisp, snappy, and cheap to operate by making narrow payloads, server-side paging, targeted hydration, and live database verification the default pattern across the app.

This plan continues the work documented in
[`EGRESS_OPTIMIZATION_HANDOFF_2026-04-23.md`](../archive/2026-04/EGRESS_OPTIMIZATION_HANDOFF_2026-04-23.md).

## Current Baseline
- Product and customer hot paths are moving to preview-first queries instead of full-row startup loads.
- Public storefront product access now has tenant-scoped RPCs for paged catalog results, search, featured products, and category counts.
- Public storefront product payloads must not expose purchase cost; public RPCs currently return `cost = 0`.
- Public product visibility now requires `is_active`, `is_published`, and `show_on_website`.
- Product catalog search now loads server-side pages instead of downloading the full public catalog and filtering locally.
- Label printer and AI product keyword lookup use bounded product preview search instead of full product hydration.
- Sales invoice journal header totals were backfilled from balanced journal lines, and a trigger now keeps future journal entry totals aligned.
- Debug builds include the database/query performance gauge so broad reads can be spotted during real navigation.

## Expected Impact
- Faster first paint and navigation on POS, invoices, storefront catalog, website product blocks, label printing, and AI inventory lookup.
- Lower Supabase egress by avoiding repeated full-table reads from high-frequency screens.
- Better public data safety because storefront traffic receives storefront-safe product fields only.
- More reliable accounting reporting because journal entry header totals stay synchronized with journal lines.
- Clearer future work because broad scans become explicit exceptions instead of accidental defaults.

## Core Principle
Every large list/search flow should use this shape:

1. Fetch a small preview payload for cards, rows, dropdowns, autocomplete, and search results.
2. Page, filter, sort, and count on the server whenever the dataset can grow.
3. Hydrate full detail only when the user opens a detail page, editor, dialog, or workflow that truly needs it.
4. Reuse cache and in-flight requests before issuing another list read.
5. Verify with the database gauge and focused analysis before calling the slice complete.

## Phase 1 - Source Of Truth And Guardrails
- Reconcile the live Supabase schema and exact remote migration history with the
  relevant standalone migrations. Use `core_schema.sql` only as incomplete
  historical search context.
- Preserve deployed storefront RPCs, accounting total triggers, policies and
  helper revokes in uniquely versioned standalone forward migrations.
- Production catalogs plus migration history remain authoritative;
  `core_schema.sql` is never the long-term source of truth or a hosted input.
- Add permanent database smoke tests for public product visibility, storefront cost safety, journal total alignment, and revoked stale helper RPCs.
- Keep the existing production-safety posture: inspect live database state first, then change the smallest safe surface.

## Phase 2 - Public Store Finish Line
- After the updated frontend is deployed, remove old compatibility policies that still allow direct public `products` table reads.
- Make the public store RPC-first for all product list, search, featured, related, and category-count surfaces.
- Keep editor/preview flows separate from public render flows so draft products can be reviewed by staff without leaking publicly.
- Confirm SEO/static website flows and Google Merchant feed generation still use published, tenant-safe, storefront-safe fields.
- Use the public store router/navigation rules already in `copilot-instructions.md`; do not trade performance improvements for route regressions.

## Phase 3 - Inventory And Product Workflows
- Continue replacing hot product lookups with `Product.listPreviewSelect`, `Product.storefrontPreviewSelect`, or module-specific preview projections.
- Audit product form set/component workflows for accidental full catalog loads and replace them with bounded searches plus targeted hydration.
- Review inventory admin lists, bulk tools, import cleanup, OCR flows, and product pickers; keep true admin-wide scans explicit and filtered.
- For stock-changing flows, verify both inventory columns and stock movement/audit tables stay consistent.
- Refresh only affected product rows after stock changes instead of reloading the full catalog.

## Phase 4 - Customers, AI, And Search
- Replace remaining broad customer startup/search paths with customer preview projections and bounded server-side search.
- Avoid feeding AI assistants whole customer or product tables as context; query only the narrow records required for the current user request.
- Debounce typing-driven searches and discard stale async responses when newer searches have started.
- Use count queries or compact RPCs when the UI needs totals, not full rows.

## Phase 5 - Accounting Health
- Treat accounting as trigger-led and audit-led. Inspect existing functions and triggers before adding or changing any accounting behavior.
- Verify journal entries are balanced after every accounting-affecting workflow: sales invoices, purchase invoices, payments, expenses, payroll, and reversals.
- Keep report semantics clear: accrual reports read journal entries; cash reports read payment tables.
- Do not patch accounting totals only in Flutter if the source of truth is a database trigger or function.
- Add targeted SQL smoke checks for journal header/line mismatches after accounting migrations.

## Phase 6 - External Services, Auth, And Website
- Keep Supabase Auth and tenant profile lookup out of repeated page-level startup loops; cache session/profile context through existing app services.
- Keep Google-related website data synchronized across runtime store, static `web/index.html`, SEO settings, and Merchant feed behavior.
- Avoid adding heavy client packages to the public store bundle, especially packages that drag in large metadata payloads.
- Keep images in Supabase Storage or CDN paths; do not store binary payloads in database rows.
- For website builder changes, separate edit-mode data needs from public render data needs.

## Phase 7 - Measurement And Verification
- Run focused Dart analysis on every touched Dart file.
- Run `git diff --check` before handoff.
- Use the debug database gauge to inspect the changed user flow and watch for broad read spikes.
- Run live, read-only Supabase smoke checks before and after database-related changes.
- If a migration is deployed manually with `psql`, ensure Supabase migration history is repaired and the deployment is documented.
- Update the handoff document when a completed slice changes the optimization baseline.

## What To Avoid
- Do not use bare `.select()` on large or high-frequency tables.
- Do not load a full table to make search, dropdowns, autocomplete, or client-side pagination work.
- Do not expose `products.cost` to anonymous storefront traffic.
- Do not remove old public table policies until the deployed frontend no longer depends on them.
- Do not let debug or admin convenience paths leak into public runtime paths.
- Do not add new database functions, triggers, tables, or columns before searching `core_schema.sql` and the live database for existing equivalents.
- Do not treat standalone SQL files as the source of truth; they must be reconciled into `core_schema.sql`.
- Do not perform production repair SQL before read-only inspection proves the cause and scope.
- Do not use service-role or anonymous behavior as proof that authenticated RLS flows work.

## Definition Of Done For Each Optimization Slice
- The hot path uses a preview projection or compact RPC.
- Detail hydration happens only after the user requests detail.
- Empty search and page initialization do not trigger full-table reads.
- Tenant filtering is explicit in app queries or guaranteed by the RPC/function.
- Accounting or inventory side effects are verified through the database trigger/function path, not only through UI behavior.
- Focused analysis passes for touched Dart files.
- The query gauge or live smoke checks confirm the optimization did not introduce a new broad-read spike.
