# Website Editor Refactor — Implementation Plan (Jan 2026)

Goal: evolve the current website builder into a scalable “Wix/WordPress-level” editor **without breaking existing tenants/pages**, keeping the current architecture (blocks + inline editor + Supabase) and respecting the project design system.

## Status Update (as of 2026-01-03)

### ✅ Already Implemented
- **Phase 1 foundation is effectively done**:
  - `WebsiteBlockType` is complete.
  - `WebsiteBlockRegistry` has fallback definitions for **all** block types (including modern blocks and `googleReviews`).
  - `WebsiteEditorPanel` can render schema-driven controls via a generic renderer (schema → controls).
- **CTA is migrated to schema-driven side-panel editing**:
  - No longer has a bespoke editor case in `WebsiteEditorPanel`.
  - Added a backward-compat write-through: editing `subtitle` also updates legacy `description`.
- **CTA banner parity improved in renderers** (inline + public):
  - CTA now supports banner-style background image + overlay fields.
  - Formatting + legacy key fallback behavior preserved.

### 🔧 Current “Custom Editor” (Bespoke) Routing
These block types still go through a dedicated editor widget in `WebsiteEditorPanel`:
- `hero`, `carousel`, `canvas`
- `text`, `button`, `divider`
- `products`
- `about`
- `categoryGrid`, `videoBanner`, `partnersBanner`, `brandLogos`

Everything else is currently expected to flow through the schema-driven generic controls (when a definition exists).

### 🚧 Not Implemented Yet (Core “Wix-level” work)
- Phase 2: `schemaVersion` convention + centralized migration/normalization hook on load.
- Phase 3+: unified payload envelope (`content/style/responsive/actions`) across all blocks.
- Responsive overrides engine.
- Actions model + animation presets + templates/sections + asset library.

## Principles
- **Schema-first**: the block schema registry is the single source of truth.
- **Backwards compatible**: existing stored `block_data` must keep rendering.
- **Incremental**: ship improvements in small, safe phases.
- **Multi-tenant safe**: all persisted changes remain tenant-scoped (no global leakage).
- **No hardcoded site content**: editor-driven content only.

## Current Architecture Snapshot (baseline)
- Block types: `WebsiteBlockType` enum.
- Schema + defaults: `WebsiteBlockDefinition`, `WebsiteBlockFieldSchema`, registry: `WebsiteBlockRegistry`.
- Render path:
  - Public view: `WebsiteBlockRenderer`.
  - Edit view: `EditableBlockRenderer` wraps the renderer and adds selection/resizing.
- Editor UI: `WebsiteEditorPanel` (add/edit/page/theme/sync).
- State: `WebsiteEditModeProvider` (selection, history undo/redo, pending theme/header).
- Persistence/data: `WebsiteService` (RPC-driven load + caches).

## Roadmap Overview

### Phase 1 — Foundation: “One Registry to Rule Them All”
**Outcome**: every block type has a definition; the editor panel uses registry metadata instead of hardcoded maps.

Deliverables:
1) **Complete fallback definitions**
   - Ensure **every** `WebsiteBlockType` has a `WebsiteBlockDefinition` in `_fallbackDefinitions`.
   - For simple blocks, provide minimal defaults + field schema.
   - For complex blocks (hero, carousel, products), keep `usesCustomEditor: true`.

2) **Registry-powered labels/icons in editor**
   - Replace hardcoded label/icon maps in `WebsiteEditorPanel` with:
     - `parseWebsiteBlockType(blockType)`
     - `WebsiteBlockRegistry.definitionFor(type)` for title/icon.

3) **Remove “undefined block” paths**
   - Avoid “Bloque sin definición registrada” during normal operation.

Files likely touched:
- `lib/modules/website/models/website_block_registry.dart`
- `lib/modules/website/widgets/website_editor_panel.dart`

Validation:
- `flutter analyze` on modified files.
- Manual: Add each block from the panel; ensure it renders in preview and can be selected.

Status: ✅ Done (with CTA migrated to schema-driven controls).

---

### Phase 2 — Data Model: Versioning + Migration Hooks
**Outcome**: safe evolution of block payloads.

Deliverables:
1) Add a `schemaVersion` field convention (stored inside `block_data`).
2) Implement a migration hook (initially **noop**) in a single place:
   - e.g. a helper `normalizeBlockData(type, rawData)` that:
     - applies defaults
     - ensures required keys exist
     - migrates old versions forward

Files likely touched:
- `lib/modules/website/services/website_service.dart` (normalize on load)
- `lib/modules/website/models/website_block_registry.dart` (version metadata)

Validation:
- Load existing tenant pages; confirm no runtime errors.

Status: 🚧 Not started.

---

### Phase 3 — Unified Editing Model: Content + Style + Responsive + Actions
**Outcome**: consistent editing UX across blocks; less custom switch/case.

Deliverables:
1) Standardize per-block payload envelope:
   - `content` (business content)
   - `style` (typography, spacing, colors, background)
   - `responsive` (visibility + overrides)
   - `actions` (navigation/open URL/call/whatsapp/anchor)

2) Expand editor controls to:
   - use schema-defined groups/sections
   - apply to all blocks consistently (even custom editors can reuse shared controls)

Files likely touched:
- `lib/modules/website/widgets/website_editor_panel.dart`
- `lib/modules/website/widgets/website_block_renderer.dart`
- `lib/modules/website/widgets/editable_block_renderer.dart`

Validation:
- Verify edits persist and re-render correctly.

Status: 🚧 Partially started (CTA parity + schema-driven controls exists; payload envelope not standardized yet).

---

### Phase 4 — Responsive Engine (Real Builder Responsive)
**Outcome**: per-device overrides and visibility rules (desktop/tablet/mobile).

Deliverables:
1) Field-level responsive overrides.
2) Block-level visibility controls per breakpoint.
3) Ensure preview mode matches device settings.

Validation:
- Toggle preview modes; verify data changes only when intended.

---

### Phase 5 — Power Features
**Outcome**: “Wix/WordPress-level” delight features.

Deliverables (in order):
1) **Actions model** (scroll to section, open external, WhatsApp/call/email)
2) **Animation presets** (safe defaults: fade/slide on load/scroll)
3) **Reusable templates/sections** (save & insert section presets)
4) **Asset library** (tenant-scoped images and reusable media)

---

## Execution Plan (what we’ll do next, concretely)

### Next Session Checklist (tomorrow)
1) **Introduce a central normalization/migration hook (Phase 2 start)**
  - Add a single helper (e.g. `normalizeBlockData(type, rawData)`) in one place.
  - Make it **noop by default**, then add *tiny* migrations where needed (CTA subtitle/description is already handled in UI, but normalization is the right long-term home).

2) **Migrate the “easy bespoke” blocks to schema-driven controls** (Phase 3 continuation)
  Goal: shrink the `switch (blockType)` in `WebsiteEditorPanel` without losing capability.
  - Best candidates (low risk): `about`, `categoryGrid`, `partnersBanner`, `brandLogos`, `videoBanner`.
  - Keep bespoke for now: `carousel` (slide list editor), `canvas` (element selection), `products` (inventory-aware settings), `hero` (depends on how advanced its current bespoke editor is).

3) **Add a consistent compatibility strategy for legacy keys**
  - Decide per-block: “read fallback” and “write-through” keys.
  - Prefer doing this in the normalization hook rather than scattering special cases.

4) **Regression checks**
  - `flutter analyze` (at least website module scopes).
  - Manual quick test: edit a CTA subtitle and confirm both `subtitle` + legacy `description` persist and render.

---

## Block Migration Definition of Done (DoD)

Use this checklist when migrating any block from bespoke panel controls → schema-driven generic controls.

### ✅ DoD — Schema + Panel
- `WebsiteBlockRegistry` has a definition for the block type with:
  - `defaultData` minimal + safe
  - `fields` complete enough for current UX
  - `controlSections` grouped logically (usually: Content / Media / Layout / Style)
- `WebsiteEditorPanel._buildBlockControls()` routes this block to `_GenericBlockControls` (no bespoke case).
- Any legacy aliasing is captured as a **single** “write-through” rule (preferably centralized later in normalization, not scattered across widgets).

### ✅ DoD — Renderers + Compatibility
- Public renderer reads new keys first, then falls back to legacy keys (no regression for existing tenants).
- Editable renderer supports inline editing for the same fields (when applicable).
- Formatting keys follow the same rule (new formatting key first, fallback to legacy formatting key).

### ✅ DoD — Persistence
- Saving blocks persists the edited values and a reload shows the same result.
- No new DB schema changes required.

### ✅ DoD — Safety Checks
- `dart analyze` / `flutter analyze` passes on the touched files.
- Manual smoke test:
  - Add the block
  - Select it
  - Change 2–3 fields via panel
  - Reload page and confirm values persist

### 🚫 Stop Conditions (don’t migrate yet)
- The bespoke editor includes complex behaviors not representable in the current field schema (e.g., carousel slide list editing, canvas element selection, inventory-backed product queries).
- The block’s renderer relies on computed/derived behavior that isn’t captured by fields yet.

## Non-Goals (for Phase 1)
- No new UI pages or extra panels.
- No new DB tables or schema changes.
- No new block types.
- No animation/interactions work yet.

## Risks & Mitigations
- **Risk: breaking existing block rendering**
  - Mitigation: keep renderer fallbacks; normalize data with defaults.
- **Risk: editor panel behavior changes**
  - Mitigation: only swap metadata sources, keep UX identical.
- **Risk: marketplace definitions vs fallback divergence**
  - Mitigation: fallback is complete; marketplace remains optional override.
