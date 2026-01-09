 # Website Editor Refactor Handoff (Vinabike)

Date: 2026-01-08

This document is the high-fidelity handoff for the full Website Editor refactor work that happened across this chat.

It combines two big streams of work that overlapped in the same session:

1) The broader “Wix/WordPress-level” Website Editor roadmap (schema-first, block definitions, normalization/migrations, responsive overrides, actions, templates/assets).
2) The navigation/footer refactor (header/footer navigation moved to Supabase, inline footer editing UX, unified save pipeline, reorder behavior).

IMPORTANT: This document intentionally contains **no code snippets** and should remain “copy-pastable” into a new chat as context.

---

## 1) High-level goals

### 1.1 Editor roadmap goal (Jan 2026 plan)

Evolve the current website builder into a scalable, “Wix/WordPress-level” editor without breaking existing tenants/pages, while preserving the current architectural pillars:

- Blocks-based CMS, stored in `website_blocks.block_data`.
- Inline editor (edit/preview inside the public store).
- Supabase persistence.
- Existing design system (no random new visual language).

Core constraints:

- Backwards compatible: existing stored block data must keep rendering.
- Incremental: ship safe improvements in phases.
- Multi-tenant safe: all persisted data stays tenant-scoped.
- No hardcoded site content: site content must come from DB/editor.

### 1.2 Navigation/footer refactor goal

- Make header + footer navigation a single source of truth in Supabase.
- Make footer configuration editable inline in the editor panel.
- Remove confusing “footer-only save”; everything persists through the global “Guardar”.

### 1.3 SEO + Google Merchant hardening goal (critical)

Make the public store reliably “crawler-trustworthy” (Google Search + Google Merchant Center), while preserving the editor model.

Non-negotiables:

- Editor content changes must persist only via the global “Guardar” (no per-control saves).
- Operational controls outside the editor save pipeline (e.g., publish/unpublish) may be immediate-save if they are intentionally treated as site operations rather than staged edits.
- Canonical URLs must be stable and consistent across:
  - runtime routing (Flutter)
  - structured data (JSON-LD)
  - Merchant feed URLs
  - deploy-time static outputs
- Reduce SPA crawler mismatch: product landing pages must not rely on client-side JS execution to expose critical facts (title/price/availability/identity/policies).

### 1.4 Desktop-Mobile Consistent UI goal

Ensure complete feature parity between desktop and mobile views in the website editor.

Non-negotiables:

- All dropdowns, controls, and functions available on desktop must also be accessible on mobile.
- No hidden or missing functionality when switching between breakpoints.
- Editor panel controls should adapt responsively but never omit features on smaller screens.
- Any desktop-only UI patterns (e.g., hover dropdowns, context menus) must have equivalent mobile-friendly alternatives (e.g., tap menus, bottom sheets).

---

## 2) Current architecture snapshot (what exists today)

### 2.1 Storage model (Supabase)

Blocks / pages / settings:

- `website_pages`: per-page metadata (slug, published, SEO fields, etc).
- `website_blocks`: per-page blocks; editable content lives in `block_data` JSON.
- `website_settings`: global site settings (theme, footer contact info, social links, etc).

Navigation:

- `website_navigation`: hierarchical navigation for header and footer.
  - `menu_location` differentiates header/footer.
  - `parent_id` models hierarchy.
  - `order_index` controls ordering.

### 2.2 Rendering model (Flutter)

- Public rendering: `WebsiteBlockRenderer`.
- Edit rendering: `EditableBlockRenderer` wraps the renderer and adds selection/resizing/edit affordances.

### 2.3 Editor UI model

- Editor panel: `WebsiteEditorPanel`.
  - Schema-driven “generic controls” exist and are used for many blocks.
  - Some complex blocks still use bespoke controls.
- State: `WebsiteEditModeProvider`.
  - Holds selection, mode (preview/edit), and pending unsaved changes.
  - Tracks “pending” settings/order changes so preview updates immediately, and persistence happens only through the global save.

### 2.4 Unified save pipeline

The editor save is centralized through `WebsiteService.saveEditorChanges(...)`, invoked by `PersistentEditorShell` (preferred) and/or `PublicStoreLayout` (legacy path).

This pipeline is responsible for persisting, in one cohesive operation:

- Block changes (page-specific blocks).
- Settings changes (header/footer/theme, etc).
- Footer navigation ordering changes.

Save semantics rule (guardrail):

- Editor content/config changes inside the editor shell should stage in `WebsiteEditModeProvider`.
- Persistence for staged editor changes happens via `WebsiteService.saveEditorChanges(...)` on the global “Guardar”.
- The black preview top bar in `PublicStoreLayout` is allowed to include immediate-save operational actions (example: publish/unpublish), as long as they are clearly treated as operations and not part of the staged editor content.

Note on menu responsibilities:

- Page management lives under `Sitio > Páginas`.
- The `Página: …` dropdown is page-scoped actions (copy/open link), not a second page-management entry point.

### 2.5 SEO sources of truth (avoid “editor vs Google” mismatch)

There are multiple layers of SEO data and Google will not “average them”:

- `website_pages`: per-page SEO fields.
- `website_settings`: site-wide SEO/contact keys used by deploy-time scripts and global chrome.
- `web/index.html`: static meta + JSON-LD seen by bots before Flutter boots.

Key rule:

- When saving HOME page SEO (and any site-wide SEO fields), mirror the saved result into the `website_settings` keys that `scripts/sync_seo_index.sh` uses.
- Do not re-introduce character limits in the editor that prevent writing merchant-compliant legal/policy text.

Primary artifacts:

- `scripts/sync_seo_index.sh` (deploy-time index.html generation)
- `lib/modules/website/services/website_service.dart` (save pipeline + mirroring)
- `lib/modules/website/pages/seo_settings_page.dart` (editor surface)

### 2.6 Product SEO + Merchant: “crawler parity” strategy

Google Merchant “Información engañosa” is treated here as a parity/trust issue.

The product URL shown in the feed must resolve to a page that clearly exposes:

- product title
- price + currency
- availability / stock state
- store identity + contact info
- policy links (shipping/returns/privacy/terms)

To reduce SPA mismatch:

- Use deploy-time product SEO snapshots so `/productos/<uuid>` can serve static HTML (meta tags + Product JSON-LD).
- Keep the canonical product route stable (router + links + JSON-LD + feed).

Primary artifacts:

- `scripts/generate_product_seo_snapshots.dart`
- `firebase.json` (headers/routing behavior for product snapshot paths)
- `lib/public_store/routes/public_store_router.dart` (canonical + redirects)
- `lib/public_store/pages/product_detail_page.dart` (runtime SEO + structured data)

---

## 3) Roadmap phases (from the Jan 2026 plan) and current status

This section mirrors the plan you provided in `.agent/plans/website_editor_refactor_plan.md`, and reflects the repo state and the work done in this chat.

### Phase 1 — Foundation: “One Registry to Rule Them All”

Outcome:
- Every `WebsiteBlockType` has a `WebsiteBlockDefinition` registered (fallback definitions are complete).
- The editor can render schema-driven controls via a generic renderer (schema → controls).

Status:
- Considered effectively DONE per the plan’s status update.

Key artifacts:
- `lib/modules/website/models/website_block_registry.dart`
- `lib/modules/website/widgets/website_editor_panel.dart`

Notes:
- The goal here is not to eliminate all bespoke editors; it is to ensure every block has at least a safe definition, defaults, and a consistent metadata source (label, icon, fields).

### Phase 2 — Data model: versioning + migration/normalization hooks

Outcome:
- Safe evolution of `block_data` JSON via a central migration/normalization step.

Plan deliverables:
- Establish a `schemaVersion` convention inside `block_data`.
- Centralize a migration/normalization hook on load that:
  - applies defaults
  - ensures required keys exist
  - migrates old payloads forward

Status in practice:
- PARTIALLY STARTED:
  - The plan notes that `WebsiteService` normalizes block payloads on load (defaults + `schemaVersion` + minimal legacy migrations).
- STILL LEFT:
  - Make `schemaVersion` and migrations a formal convention across all blocks.
  - Ensure migrations are centralized and not duplicated across widgets.

Key artifacts:
- `lib/modules/website/services/website_service.dart`
- `lib/modules/website/models/website_block_registry.dart`

### Phase 3 — Unified editing model: content + style + responsive + actions

Outcome:
- Consistent editing UX across blocks.
- Shrinks bespoke code in `WebsiteEditorPanel`.

Plan deliverables:
- Standardize the block payload envelope (conceptually):
  - content
  - style
  - responsive
  - actions
- Expand generic editor controls to cover more blocks and sections.

Status:
- PARTIALLY STARTED:
  - Schema-driven controls exist.
  - CTA is migrated to schema-driven controls.
- STILL LEFT:
  - Standardize the payload envelope across blocks.
  - Implement an “actions model” consistently rather than per-block hacks.

Key artifacts:
- `lib/modules/website/widgets/website_editor_panel.dart`
- `lib/modules/website/widgets/website_block_renderer.dart`
- `lib/modules/website/widgets/editable_block_renderer.dart`

### Phase 4 — Responsive engine (real builder responsive)

Outcome:
- Field-level responsive overrides.
- Block-level visibility per breakpoint.
- Device preview matches data correctly.

Status:
- NOT IMPLEMENTED.

### Phase 5 — Power features

Outcome:
- Builder features that users expect from Wix/WordPress-level tools.

Plan deliverables (recommended order):

1) Actions model (scroll to section, open URL, WhatsApp/call/email)
2) Animation presets (safe defaults)
3) Reusable templates/sections (save & insert)
4) Asset library (tenant-scoped media)

Status:
- NOT IMPLEMENTED.

---

## 4) Detailed: what Phase 1 delivered (practically)

### 4.1 Full coverage of block definitions

What “done” means:

- Every `WebsiteBlockType` has a definition available via the registry.
- Definitions include:
  - safe `defaultData`
  - field schema sufficient for generic controls
  - metadata used for titles/icons/labels

Why this matters:

- Prevents “undefined block” UX and “this block cannot be edited” dead ends.
- Enables incremental migration of blocks from bespoke editors to generic controls.

### 4.2 Generic schema-driven controls

What exists:

- `WebsiteEditorPanel` can render generic controls based on the block definition schema.
- Most “simple” blocks should be editable without custom switch/case UI.

What is intentionally still bespoke:

- Some blocks require complex editors (repeaters, slide lists, inventory-backed settings, element selection, etc).

---

## 5) CTA migration (explicitly called out in the plan)

What changed:

- CTA is migrated away from bespoke editor routing and is editable through schema-driven generic controls.
- Backwards compatibility is preserved via a write-through behavior:
  - Editing CTA “subtitle” updates the legacy “description” field as well.
- CTA banner parity improved in renderers:
  - Background image/overlay support exists.
  - Legacy key fallback behavior is preserved.

Why it matters:

- CTA becomes the reference example for safely migrating a block to schema-driven editing.
- It demonstrates how to handle legacy keys without breaking existing tenants.

Key artifacts:

- `lib/modules/website/widgets/website_editor_panel.dart`
- `lib/modules/website/widgets/website_block_renderer.dart`
- `lib/modules/website/widgets/editable_block_renderer.dart`

---

## 6) Remaining bespoke editors (current routing)

Per the plan, these block types still route through bespoke controls in `WebsiteEditorPanel`:

- hero
- carousel
- canvas
- button
- products
- videoBanner

Rationale:

- carousel: typically requires a slide list editor.
- canvas: typically requires element selection/manipulation.
- products: inventory-aware settings (data source, filters, layout) often exceed basic schema fields.
- hero/videoBanner/button: may have custom UX needs, depending on current implementation depth.

Migration guidance (from plan):

- “Easy bespoke” candidates to migrate to generic controls sooner:
  - about
  - categoryGrid
  - partnersBanner
  - brandLogos
  - videoBanner (candidate, but currently listed as bespoke — confirm whether it is truly “easy” in this repo)

Stop conditions:

- Don’t migrate if bespoke editor behavior cannot be represented with current schema field types.

---

## 7) Navigation + footer refactor stream (the other major iceberg)

This stream is not the same as the “Wix-level editor phases”, but it was a large portion of the changes in this chat.

### 7.1 Navigation source of truth moved to Supabase (`website_navigation`)

What changed:

- Header + footer navigation are represented in one table.
- Footer “sections” are top-level nav items; footer links are children.

Why:

- Eliminates hardcoded navigation JSON.
- Makes navigation multi-tenant editable and auditable.

Primary artifacts:

- `lib/modules/website/services/website_service.dart`
- `lib/modules/website/pages/navigation_management_page.dart`

### 7.2 Navigation edit crash fix (Dropdown assertion)

Problem:

- Editing a navigation link could crash due to Dropdown value mismatch.

Root causes handled:

- Legacy UUID link values.
- Duplicate dropdown items.

Fix approach:

- Normalize legacy UUID link values to slug/path.
- Deduplicate dropdown option set.
- When the stored value is invalid, set selection to “no selection” instead of asserting.

Primary artifact:

- `lib/modules/website/pages/navigation_management_page.dart`

### 7.3 Inline footer editor UX (inside the editor panel)

What exists now:

- Footer “info” settings editable inline (contact/social/brand-ish fields).
- Footer navigation CRUD inline (sections + links).
- Density improvements (collapsible groups, clearer wording).

Primary artifact:

- `lib/modules/website/widgets/website_editor_panel.dart`

### 7.4 Unified “Guardar” pipeline for footer settings + footer navigation order

What changed:

- Footer settings and reorder state are staged in `WebsiteEditModeProvider` as pending changes.
- Only the global save persists them via `WebsiteService.saveEditorChanges(...)`.

Extension (latest change):

- Footer settings + footer navigation ordering follow the staged “Guardar” pipeline.
- The black preview top bar “Publicado” toggle is an operational control and currently saves immediately (writes `site_published` directly via `WebsiteService.saveSetting(...)`).

Primary artifacts:

- `lib/modules/website/providers/website_edit_mode_provider.dart`
- `lib/modules/website/services/website_service.dart`
- `lib/public_store/widgets/persistent_editor_shell.dart`

### 7.5 Default footer seeding (authenticated-only)

Problem:

- Public footer could show default/fallback columns but DB was empty, causing editor mismatch.

Solution:

- Seed a default footer navigation set into DB when authenticated and footer nav is empty.
- Never seed/insert for anonymous store browsing.

Primary artifact:

- `lib/modules/website/services/website_service.dart`

### 7.6 Ordering and drag/drop

Changes in this chat:

- Added a batch reorder method to persist an ordered ID list in one shot.
- Introduced staging/pending ordering in the provider, applied on save.

Important note:

- You stated you fixed the final “drag weirdness” outside of this chat using another agent.
- Because of that, re-validate current repo behavior and align the handoff TODOs accordingly.

---

## 8) “Definition of Done” for migrating blocks (from plan)

Use this checklist each time you migrate a block from bespoke controls to schema-driven generic controls:

- Schema + panel:
  - Registry has a definition (safe defaults + complete-enough fields).
  - Panel routes to generic controls (no bespoke case).
  - Legacy aliasing uses a single write-through rule (prefer centralized migration later).
- Renderers + compatibility:
  - Public renderer reads new keys first, falls back to legacy keys.
  - Editable renderer supports the same fields.
- Persistence:
  - Save persists, reload keeps the same.
- Safety checks:
  - Analyzer passes for touched files.
  - Manual smoke test: add block, edit fields, reload.

---

## 9) What’s still left to do (prioritized)

### P0 — Must do next

- Update the handoff and current reality around Phase 2:
  - Decide whether `schemaVersion` is already persisted and used consistently, or only partially.
  - Centralize migrations so they don’t leak into widgets.
- Standardize navigation reordering everywhere to use the batch reorder API where appropriate.
- Validate the final drag/drop behavior in the footer editor UI on Web.

### P0 — Desktop-Mobile UI Consistency (must do next)

- Audit all editor panel controls and identify any desktop-only dropdowns, menus, or functions.
- Ensure all toolbar actions and block editing options are accessible on mobile.
- Replace desktop-only patterns (hover menus, right-click context menus) with mobile-friendly alternatives.
- Test editor functionality across breakpoints to confirm no features are missing on mobile.

### P0 — SEO + Merchant hardening (must do next)

- Confirm the canonical product URL is `/productos/:id` everywhere:
  - router
  - internal links
  - Product JSON-LD
  - Merchant feed URL generation
- Ensure deploy-time product snapshot generation runs as part of the store deploy pipeline.
- Normalize JSON-LD output in snapshots (avoid stray newlines/whitespace inside string fields).
- Audit identity + policy parity as seen by bots:
  - contact info
  - shipping/returns/terms/privacy pages published and linked
  - checkout transparency (no mismatch between feed and landing)

### P1 — Should do soon

- Start Phase 3 payload envelope standardization:
  - content/style/responsive/actions (even if initially shallow).
- Move more “easy bespoke” blocks to schema-driven editing.
- Establish a consistent, documented legacy-key policy per block:
  - read-fallback keys
  - write-through keys
  - migration targets

### P1 — SEO + Merchant hardening (should do soon)

- Ensure HOME page SEO edits saved in `website_pages` are mirrored into the `website_settings` keys used by `scripts/sync_seo_index.sh` (so `web/index.html` matches after deploy).
- Verify product price/availability shown in snapshots matches what the feed emits (avoid mismatch between landing page and feed values).
- Re-check Firebase caching/headers for `/productos/**` so bots consistently receive HTML snapshots when intended.

### P2 — Medium-term

- Implement Phase 4 responsive overrides engine.
- Implement Phase 5 actions model.
- Later: templates/sections and an asset library.

---

## 10) QA checklist (manual, no code)

Editor routing / state:

- Enter store normal mode, preview mode, edit mode.
- Confirm the editor panel persists across route changes (no remount/jank).

Blocks:

- Add several block types that rely on generic controls and confirm the panel renders field controls.
- Add CTA, edit subtitle, confirm it persists and renders correctly after reload.
- Add a block that is still bespoke (e.g., carousel/products) and confirm bespoke editor still works.

Footer:

- Edit footer contact settings; confirm live preview updates and persistence works via Guardar.
- Create a footer section, add 2–3 links, toggle visibility, delete one.
- Reorder links and sections; confirm final order persists after reload.

Navigation admin:

- Edit an existing navigation row that historically had a UUID-style link; confirm no dropdown crash.

Multi-tenant:

- Confirm navigation and settings are scoped by tenant.
- Confirm default footer seeding never occurs in anonymous mode.

---

## 11) Known Issues / Edge Cases (Track explicitly)

### 7.1 Legacy navigation values

- Some older records may store UUIDs in link_value (page IDs) rather than paths.
- Ensure all editing surfaces normalize to the same representation.

### 7.2 Reorder performance

- Batch reorder avoids “notify storms”, but reorder UIs must still:
  - Update displayed list immediately
  - Persist order in background
  - Avoid mutating selection/state inside build

### 7.3 Footer defaults vs DB truth

- Seeding reduces “empty editor vs non-empty footer” confusion.
- Decide whether to keep any hardcoded fallbacks in the public footer or remove them.

### 7.4 Multi-page editing safety

- Save pipeline attempts to resolve/create pages by slug to avoid overwriting home accidentally.
- Verify that:
  - “home page” is treated consistently
  - policy/static pages use the right route + editing support

### 7.5 Analyzer noise

- A full repo analyzer run currently surfaces a large number of existing lint/info warnings.
- Treat analyzer failures as “signal” only when they relate to files touched by the editor/SEO changes.

---

## 12) Suggested Next Session Starting Point

When you start a fresh chat and provide this file, the recommended first actions are:

1) Confirm the repo’s current drag/drop implementation and behavior on Web for footer tabs and links.
2) Standardize all navigation reordering to use the batch reorder API.
3) Validate that only the global “Guardar” pipeline persists footer changes (no parallel save flows).
4) Decide whether to remove the public footer’s hardcoded fallback now that seeding exists.


## 13) Non-goals (Explicitly out of scope)

- Introducing new pages, modals, or additional UX beyond the described editor refactor.
- Changing the design system (new colors/fonts/shadows).
- Adding new tables/columns unless strictly necessary.

---

End of handoff.
