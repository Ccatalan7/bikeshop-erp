# Website Builder — emergency completion handoff to Claude Code

**Date:** 2026-07-30  
**Checkout:** `/Users/Claudio/Dev/bikeshop-erp`  
**Branch:** `smartpegas1.0`  
**Observed HEAD before this closure pass:** `32404d36bcae026a1560cf0080f85f6ac7cdf157`  
**Claude chat:** `Finalización refactor Website Builder`  
**Required surface/model/effort:** Code / Fable 5 / Ultracode

## Owner authorization and objective

The owner asks Claude to take exclusive completion ownership of the Website
Builder refactor and continue persistently until the implementation, validation,
database deployment/readback/registration, and documentation are genuinely
closed.

The owner has authorized all in-scope actions needed to finish, including
production database migration deployment and migration-history registration.
Do not leave production SQL pending in a conclusion. Do not commit, push,
publish an application release, or deploy unrelated services unless the owner
explicitly asks for that separate release action.

Claude may use subagents and all available analysis/testing resources. Preserve
the one existing macOS Flutter debug runtime: do not start, kill, or replace it.

## Strict ownership boundary

- Website Builder, public storefront editor contracts, their focused tests,
  migration `20260730091630`, and directly required shared OAuth callback code
  are in scope.
- Do not touch Payroll/HR files, `lib/main.dart`, `MainLayout`, Workspace/top
  bar, or the visual-system work owned by the concurrent task.
- The checkout is extremely dirty. Preserve every unrelated/pre-existing
  change. Do not reset, revert, mass-format, stage, or attribute changes outside
  this handoff.
- No Design work is required. This is architecture, authority, data integrity,
  lifecycle, and integration closure.

## Mandatory documents

Before further architectural decisions, use the documents already read in this
session and keep them authoritative:

- `.github/copilot-instructions.md`
- `.github/GUI_DESIGN_PRINCIPLES.md`
- `docs/architecture/canonical-ui-surfaces.md`
- `docs/development/CODEX_CLAUDE_COLLABORATION.md`
- `docs/development/AGENT_DATABASE_CONTRACT.md`
- `docs/architecture/website-editor-contract.md`
- `docs/architecture/website-builder-agent-handoff.md`
- `docs/development/WEBSITE_EDITOR_PROFESSIONAL_UX_REBUILD_PLAN_2026-07-17.md`
  if present
- `docs/development/WEBSITE_BUILDER_PROGRESSIVE_ARCHITECTURE_REFACTOR_PLAN_2026-07-29.md`

## Current completed work that must be preserved and reverified

- Atomic `replace_page_blocks` RPC path and the unique
  `WebsiteSaveCoordinator`.
- Post-await write authority guards across blocks/settings/pages/navigation.
- Late non-auth coordinator errors are reclassified as
  `WebsiteEditorWriteSupersededException` when authority changed.
- Typed fail-closed CMS page/block parser.
- Dynamic/Policy/Home epoch work, including the new
  `dynamic_page_editor_aba_test.dart`.
- Tenant-scoped `delete_website_navigation` RPC plus pgTAP and management
  regression.
- Shared composition/renderer/FSM/physical partition work already present in
  the dirty checkout.

Do not trust historical “complete” checkboxes without rerunning the final
evidence on the current tree.

## P1 OAuth blocker — finish this before approval

Claude is currently implementing
`lib/modules/website/models/website_editor_oauth_intent.dart` and its
writer/callback/consumer. The first draft is not yet approvable.

Required final contract:

1. One typed/versioned persisted intent under one key. It must include a unique
   nonce, issuer identity, storefront tenant, capability fingerprint (or
   equivalent durable authority evidence), issued/expires timestamps, sanitized
   internal return path, and `openIntegrations`.
2. Use one store owner with semantic operations equivalent to `peek`, `take`,
   `restoreIfNonce`, and `clearIfNonce`.
3. The callback may inspect/validate the intent and follow only its sanitized
   internal path. It must never project `edit=true` or `preview=true`.
4. The storefront consumer must `take` (remove) the exact nonce before any
   async capability await. A second mount/replay then has nothing to redeem.
5. Only a classified transient failure may restore the same unexpired intent,
   and only if no newer intent exists. Durable denial, malformed/legacy,
   identity/tenant/fingerprint mismatch, expiry, or replay consume it
   fail-closed.
6. `connect()` receives the editor-owned capability/tenant from its consumer,
   validates the current user and grant before persisting, and clears only its
   own nonce if OAuth throws or returns false.
7. After `resolveEditorCapability`, validate the returned snapshot identity,
   storefront tenant, and fingerprint against both the captured request and
   intent **before** calling `adoptEditorEntryLease` or mutating any provider
   state. The current draft checks `expectedIssuerFingerprint` after adoption;
   move the check before every mutation.
8. Do not catch every exception as transient. Separate typed durable
   denial/contract failures from genuinely transient transport/unavailability
   failures.
9. Remove the obsolete four-key constants and all legacy reads/writes after
   consuming legacy keys fail-closed.

Behavioral tests must cover the complete writer → storage → callback →
consumer flow and at least: malformed/legacy, expiry, identity mismatch, tenant
mismatch, fingerprint mismatch, sanitized edit/preview query, replay/double
mount, take-before-await, transient restore with same nonce, newer intent not
overwritten by an older transient result, failed/false connect cleanup,
A→B→A, durable remote revoke, and zero provider mutation before a mismatched
intent is rejected.

## P1 stable-subtree blocker (“H”)

The last Codex read showed mode-derived keys still alive in:

- `lib/public_store/pages/cart_page.dart`
- `lib/public_store/pages/checkout_page.dart`
- `lib/public_store/pages/contact_page.dart`
- `lib/public_store/pages/product_catalog_page.dart`
- `lib/public_store/pages/product_detail_page.dart`

Finish one stable routed content anchor/slot chain across Public, Preview, and
Edit. Remove mode-derived `ValueKey`s in the same change. Keep routed page
state alive where the existing page contract requires it. Edit chrome remains
an overlay; it must not replace the content subtree.

Add real behavioral tests using `State` identity and user state, not source
text: scroll position, text/focus/selection where applicable, catalog filters,
cart/checkout draft state, and zero extra mode-driven CMS/data reloads across
Public ↔ Edit ↔ Preview. Preserve route changes as legitimate remounts.

## Database completion — mandatory, not optional

Candidate migration:

`supabase/migrations/20260730091630_harden_website_editor_reads.sql`

It contains the editor read authority contract and
`delete_website_navigation`.

**Completion evidence (2026-07-30):** Codex reran the seven-file local suite
(135/135) and the production-derived authority/delete suite (49/49), deployed
this exact file through `scripts/db/query.sh`, read back function bodies,
properties, ACLs, RLS, policies and unaffected aggregates, then registered
`20260730091630`. `db-health production` passed with zero critical violations
and 18 historical stock warnings. The migration checksum was
`29e2952622b518b8aecb0e6ba626553833c428ab02df9cbb2f7232904b117b45`.

First run local and production-derived validation on the final file:

```bash
just db-test website_editor_read_authority website_navigation_delete_command website_page_blocks_replace website_cms_public_policy_hardening website_cms_public_read website_category_publication_command website_navigation_seed_hardening

bash scripts/db/production_validation.sh prepare \
  --task website-editor-read-authority-direct \
  --migration supabase/migrations/20260730091630_harden_website_editor_reads.sql

bash scripts/db/production_validation.sh test \
  --task website-editor-read-authority-direct \
  --migration supabase/migrations/20260730091630_harden_website_editor_reads.sql \
  --test website_editor_read_authority \
  --test website_navigation_delete_command
```

Then deploy only through the guarded production path:

```bash
VINABIKE_DB_WRITE_CONFIRM=production \
  bash scripts/db/query.sh production \
  --write \
  --file supabase/migrations/20260730091630_harden_website_editor_reads.sql
```

Perform exact production readback of function bodies/properties, ACLs,
tenant/page invariants, and unaffected row aggregates. Only after readback,
register:

```bash
VINABIKE_DB_WRITE_CONFIRM=production \
  scripts/supabase_cli.sh migration repair --linked --status applied 20260730091630

just db-health production
```

Do not redeploy `20260728170000_harden_website_edit_authority.sql`; it was
already deployed and registered.

## Required final Flutter gate

Before running tests, ensure no other `flutter test`/analyzer process owns the
same artifacts. Never disturb the existing macOS runtime.

At minimum rerun:

- focused analyzer for `lib/modules/website`, `lib/public_store`, the shared
  OAuth callback, and all added/changed Website tests;
- the six core editor mode/document/history/navigation/stability widget tests;
- RPC client, save coordinator, save retry and backup restore;
- Home/Dynamic/Policy composition/epoch suites;
- navigation management delete;
- renderer/canvas convergence and sanitization suites;
- the full OAuth matrix above;
- the stable-subtree state-retention matrix;
- source/architecture contracts affected by F6;
- scoped and full `git diff --check`.

Any repository-wide failure must be reconciled against the dirty baseline and
reported exactly; it is not permission to ignore a Website-owned failure.

## Documentation and final verdict

Update the progressive plan, editor contract, canonical UI registry, and
Website Builder handoff to match evidence actually rerun. Remove stale
overclaims such as “no SQL pending” until production deployment/readback and
history registration have succeeded.

The final response must include:

- exact Website-owned file inventory;
- production migration deployment, readback, registration, and health
  evidence;
- exact tests/analyzer commands and counts;
- unrelated concurrent failures separately;
- remaining risks/hypotheses;
- an explicit approval verdict.

Do not declare completion or approval while either OAuth, stable-subtree
retention, the focused Flutter/DB gates, or production migration closure is
still pending.
