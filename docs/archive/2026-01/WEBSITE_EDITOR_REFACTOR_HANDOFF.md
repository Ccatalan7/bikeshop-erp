 # Website Editor Refactor Handoff (Vinabike)

Date: 2026-01-08

This document is the high-fidelity handoff for the full Website Editor refactor work that happened across this chat.

It combines two big streams of work that overlapped in the same session:

1) The broader “Wix/WordPress-level” Website Editor roadmap (schema-first, block definitions, normalization/migrations, responsive overrides, actions, templates/assets).
2) The navigation/footer refactor (header/footer navigation moved to Supabase, inline footer editing UX, unified save pipeline, reorder behavior).

IMPORTANT: This document intentionally contains **no code snippets** and should remain “copy-pastable” into a new chat as context.

---

## 0.1) June 5, 2026 inspection: editor-owned changes mandate

This inspection was triggered by the current inline editor screenshot showing `Tema > Textos` with heading font set to Oswald and paragraph font set to Barlow, even though the user expected prior website font work to be reflected universally.

The deeper requirement is now explicit in `.github/copilot-instructions.md`:

- Any website change must be backed by a real editor feature, setting, or editable data model.
- Agents must apply website changes by using or extending the editor-owned option, not by hardcoding private behavior in renderers.
- The user must be able to find, change, and revert the result later from the inline editor or a website management screen.

### Current source-of-truth pieces that already exist

- Global theme values live in `website_settings` under `theme_*` keys.
- The right-side editor panel exposes `Tema > Textos` controls for heading/body font and base sizes.
- `WebsiteEditModeProvider` stages pending theme settings for live preview.
- `PersistentEditorShell` saves pending theme/header/footer/site/page/category/block changes through `WebsiteService.saveEditorChanges(...)`.
- `PublicStoreLayout` builds a `WebsiteThemeBuilder` theme from saved or pending theme settings.
- Home, dynamic pages, and static policy pages already read many effective theme settings and pass heading/body fonts into block renderers.
- `WebsiteLinkValueEditor` exists as the canonical link picker and is used by block fields and several footer/navigation editing paths.
- Header/footer navigation is stored in `website_navigation`, with hierarchy, visibility, ordering, and link metadata.

### Current drift found during inspection

1) Theme consumption is not universal yet.

Several public-store pages still reference hardcoded `PublicStoreTheme.defaultHeadingFont` / `PublicStoreTheme.defaultBodyFont` directly. The most visible affected surfaces include product detail, product catalog, cart, checkout, order confirmation, and some header/footer fragments. These hardcoded font families can override the editor's global typography settings, which matches the screenshot complaint.

2) The theme font picker is not governed by a single font registry.

The editor lists multiple fonts, including duplicates and fonts that are not registered in `pubspec.yaml`. The app currently bundles Oswald and Barlow; other listed fonts may silently fall back depending on platform/browser font availability. That makes the editor look more capable than the renderer can guarantee.

3) Mega-menu behavior is only partially editor-owned.

Navigation hierarchy is editable through `website_navigation`, and one management dialog exposes a "Mega Menu" toggle stored as `css_class = megamenu`. But the desktop renderer currently treats any visible parent with children as a mega menu. That means menu presentation is still partly implicit renderer behavior, not a clean user-owned option.

4) Navigation/footer save semantics are inconsistent.

The unified save pipeline accepts pending footer navigation label/destination edits, but at least one inline footer/navigation editing path still calls the navigation update service directly. Content/config edits inside the editor should stage and persist through global `Guardar`; direct saves should be reserved for intentional operations.

5) The side panel is too large for safe evolution.

`website_editor_panel.dart` has grown into a very large mixed-responsibility file. Theme controls, block controls, footer navigation, category visibility, page SEO, canvas editing, and bespoke block editors share one file, which encourages one-off fixes and makes it harder to prove that a capability is universal.

6) Block capability drift still exists.

The registry gives every block a definition, but several blocks still use custom editors or renderer-level compatibility fallbacks. That is fine during migration, but each shared capability needs one owner: links, text presets, media/focal point, actions, responsive visibility, and theme consumption.

### Refactor plan from this inspection

#### P0: Stop agent-only website changes

- Keep the new repo-wide instruction as a hard contract.
- Add a review habit for every website task: identify the editor control/data owner before editing renderers.
- Reject website changes that cannot be changed later by the user from the editor or a website management screen.

Done in this task:

- `.github/copilot-instructions.md` now includes the mandatory "Editor-Owned Website Changes" rule.
- `WebsiteFontRegistry` now owns the supported website font list. The theme panel only offers bundled fonts (`Oswald`, `Barlow`), stale saved values are resolved to supported defaults, and the main theme/block renderer paths normalize fonts through the registry.

#### P0: Make theme truly global

- Introduce one small theme-consumption layer for public storefront pages so product detail, catalog, cart, checkout, order confirmation, policy pages, dynamic pages, blocks, header, and footer all resolve typography/colors from the same effective theme values.
- Treat `PublicStoreTheme` constants as fallback defaults only.
- Remove direct page-local font-family overrides where the editor already has an equivalent theme control.
- Replace the hardcoded editor font list with a single registered-font/source-of-truth list. Show only guaranteed bundled fonts by default, or explicitly mark system/browser fonts as best-effort.
- Add a smoke check: changing `Tema > Textos` must affect header, hero, product cards, product detail, cart, checkout, order confirmation, dynamic pages, static policy pages, and footer after save/reload.

#### P0: Make navigation and mega menus fully user-owned

- Define a canonical editable menu presentation option for parent navigation items: normal link, dropdown, mega menu, or automatic if intentionally supported.
- Store that option in an explicit model. If a schema change is chosen, update Supabase migrations and `supabase/sql/core_schema.sql` in the same task; if compatibility uses `css_class` temporarily, document it as a migration bridge rather than the final model.
- Make the renderer follow the saved presentation option instead of assuming every item with children is a mega menu.
- Ensure users can add, edit, hide, reorder, and nest submenus from the editor/management UI.
- Keep desktop and mobile presentations equivalent in capability, even if the visual pattern differs.

#### P0: Reconcile save semantics

- Audit every website editor control and classify it as staged content/config or immediate operation.
- Route staged changes through `WebsiteEditModeProvider` and `WebsiteService.saveEditorChanges(...)`.
- Remove direct persistence from inline footer/navigation/content controls unless the UI clearly labels the action as an immediate operation.
- Ensure `Descartar` really discards staged theme/nav/footer/category/page/block changes.

#### P1: Split the editor panel by capability

- Keep the external `WebsiteEditorPanel` API stable first.
- Extract focused panels/services in small steps:
  - theme controls
  - block schema controls
  - navigation/footer controls
  - page/SEO controls
  - category visibility controls
  - canvas/bespoke block controls
- Move shared controls into reusable widgets: link picker, font picker, color picker, media/focal-point picker, responsive visibility, action picker, repeater editor.
- Each extracted panel should be testable without loading the full editor shell.

#### P1: Standardize block capabilities

- Expand the schema model so fields can declare capability metadata: text preset, link destination, media/focal point, action, responsive override, theme inheritance.
- Continue "compat + normalize + converge": render legacy keys safely, normalize in `WebsiteService`, and write canonical keys on save.
- Move renderer defaults back toward registry defaults. Renderers may use safe fallbacks only when saved data is missing.
- Prioritize migrating hero, carousel, products, video banner, button, footer, and category grid because they are the places users naturally expect universal controls.

#### P1: Add verification guardrails

- Add focused tests or scripts that fail when new public-store page code hardcodes editor-owned fonts/colors.
- Add schema coverage checks: every link-capable field uses the link field type and `WebsiteLinkValueEditor`.
- Add save pipeline checks: staged theme/navigation/footer changes persist only after `Guardar` and survive reload.
- Add desktop/mobile editor smoke checks for the right-side panel and menu controls.

#### P2: Formalize migrations and schema versions

- Make `schemaVersion` a consistent convention across block payloads.
- Centralize block migrations and normalization in the service/registry layer.
- Add one-time tenant cleanup scripts only after load/save normalization is already safe.

### Acceptance criteria for the big refactor

- A font change made in `Tema > Textos` is visible everywhere the public storefront renders customer-facing text, including commerce pages outside block rendering.
- A mega menu can be created, edited, populated with submenus, switched to another presentation, and reordered by the user without code changes.
- Every new visible website feature has an obvious editor-owned control or data owner.
- The editor preview and saved public site agree after reload.
- No renderer-only website customization ships without an editor path and documented migration/compat behavior.

---

## 0.2) June 5, 2026 inspection: universal controls, redundancies, and missing features

The next layer of the refactor is control universality: if two blocks expose the same kind of capability, they must share the same control, stored keys, preview behavior, renderer semantics, and save behavior.

Important correction from the June 5 follow-up: examples mentioned by the user are only symptoms. The scope is not "fix carousel vs canvas." The scope is the whole editor surface. Every `WebsiteBlockType`, every block field, every inline renderer, every side-panel control, and every save path must be audited against the same capability matrix.

### Inspection scope used for this pass

- Block enum: 24 block types in `WebsiteBlockType`.
- Registry: all 24 have `WebsiteBlockDefinition` entries, but the schema cannot yet describe richer capabilities such as formatted text, cover media, focal point, alt text, responsive overrides, or shared actions.
- Side-panel routing: hero/carousel share carousel controls, canvas/products have custom controls, several modern blocks use generic schema controls, and footer is a special selected element outside normal block routing.
- Editable renderer routing: only hero, carousel, canvas, text, button, divider, about, cta, features, faq, contact, services, pricing, testimonials, stats, team, and gallery have explicit editable builders. Products, category grid, video banner, partners banner, brand logos, Google reviews, and footer fall back or are handled elsewhere.
- Shared controls inspected: `WebsiteLinkValueEditor`, `InlineEditableTextV2`, `TextFormattingToolbar`, `FocalPointPicker`, `InlineEditableImage`, `_ImagePicker`, `_VideoPicker`, `_EditorTextField`, `_EditorDropdown`, `_EditorSlider`, the removed `_LinkPicker`, and `CanvasElementToolbar`.
- Save behavior inspected: global editor save via `WebsiteEditModeProvider`/`WebsiteService.saveEditorChanges(...)`, legacy `WebsiteSettingsDialog.saveSettings(...)`, Google sync direct settings writes, and footer navigation direct service writes.

### Block capability coverage matrix

This matrix is intentionally broader than any single user-surfaced example. It should be treated as the starting audit for the full refactor, then verified again during implementation with UI smoke tests.

| Block | Current editing path | Coverage today | Gaps to fix |
| --- | --- | --- | --- |
| `hero` | Generic side panel plus explicit editable renderer | Inline title/subtitle use `InlineEditableTextV2`; side panel has background image, CTA link, mobile focal point | Needs shared cover-media control, schema-aware text formatting controls, and a single action/button model |
| `carousel` | Custom side panel plus explicit editable renderer | Slides support title/subtitle/CTA/media; background focal point exists for slides | Slide text side panel is plain text; slide text formatting is not schema-owned; cover media/focal logic is block-local |
| `canvas` | Custom side panel plus `CanvasBlock` | Free-position text/button/image/background/video controls exist | Own toolbar, own text style keys, own link picker, missing shared focal point for background, duplicate color/media controls |
| `text` | Generic side panel plus explicit editable renderer | Top-level inline text can save `formatting` and width | Side panel is plain textarea; no shared style inspector for the same formatting object |
| `button` | Generic side panel plus explicit editable renderer | Label/link/style exist; link uses shared schema link field | Inline label is text-only; button action/style model is not universal across CTA/pricing/canvas/header |
| `divider` | Generic side panel plus explicit editable renderer | Thickness, width, color fields exist | Should use shared spacing/dimension/color controls once those are canonical |
| `products` | Custom side panel; editable renderer currently falls back/defers | Product source/filter/sort/display controls exist and product data is ERP-owned | Product card typography, badges, empty states, actions, and theme controls are not declared as reusable capabilities |
| `services` | Generic side panel plus explicit editable renderer | Repeater content and inline text editing exist | Inline toolbar can appear without persisted formatting callbacks; no links/actions/media per card |
| `about` | Generic side panel plus explicit editable renderer | Title/body inline formatting persists; image field exists | Image editing lacks shared focal/alt/crop metadata and side-panel text formatting parity |
| `testimonials` | Generic side panel plus explicit editable renderer | Repeater and inline quote/name/role editing exist | Formatting is mostly raw text only; no shared avatar/media/focal/link model |
| `features` | Generic side panel plus explicit editable renderer | Repeater and inline title/description editing exist | Icon/style/action controls are block-specific or sparse; formatting persistence is incomplete |
| `cta` | Generic side panel plus explicit editable renderer | Title/subtitle formatting persists; CTA link uses shared link field | Background image/color/overlay should move to shared cover-media/style controls |
| `gallery` | Generic side panel plus explicit editable renderer | Images/captions can be edited | Images are text URL/schema image fields without universal alt, focal, crop, per-item link, or asset-library controls |
| `contact` | Generic side panel plus explicit editable renderer | Title/subtitle and form toggles exist | Form fields/contact sources/actions need schema ownership; inline text formatting is incomplete |
| `faq` | Generic side panel plus explicit editable renderer | Questions/answers repeater and inline editing exist | Answers are plain text/textarea, not rich text; no shared formatting or link support inside answers |
| `pricing` | Generic side panel plus explicit editable renderer | Plans, prices, feature chips, CTA text, highlight toggle exist | CTA destination is missing from schema; pricing card actions should use shared action/link model |
| `team` | Generic side panel plus explicit editable renderer | Members, avatar image, social chips, inline text exist | Social chips are raw comma text; avatar needs shared media/focal/alt; formatting persistence incomplete |
| `stats` | Generic side panel plus explicit editable renderer | Metrics, values, labels, icons, inline editing exist | Animation/count-up behavior and formatting should become shared capabilities |
| `categoryGrid` | Generic side panel; editable renderer falls back to public renderer | Title, categories, images, links are schema-defined | No explicit editable renderer; card images need shared cover-media/focal/alt; card text formatting is absent |
| `videoBanner` | Generic side panel; editable renderer falls back to public renderer | Title/subtitle, image fallback, YouTube/file video, CTA, overlay opacity exist | No explicit editable renderer; poster/background media should use shared cover-media control; text formatting absent |
| `partnersBanner` | Generic side panel; editable renderer falls back to public renderer | Title and chip list exist | Chip list is weak for structured items; no inline renderer/text style/action controls |
| `brandLogos` | Generic side panel; editable renderer falls back to public renderer | Title and logo URL chips exist | Logo upload should use asset/media control, not comma URLs; no per-logo alt/link/order metadata |
| `googleReviews` | Registry marks custom; block controls are sparse and reviews sync lives in Google settings/actions | Google review data can be synced from Google settings and rendered | Block has little direct styling/content control; sync writes settings immediately and must be classified as operational, not staged content |
| `footer` | Special selected element, not normal block flow | Footer settings partially stage through provider; nav hierarchy exists | Footer nav create/edit/reorder has direct service writes and local `Guardar`; footer block registry fields are not the actual active editor source |

### Cross-cutting defects found

1) Some registered blocks have no explicit editable renderer.

Products, category grid, video banner, partners banner, brand logos, Google reviews, and footer do not have the same live editing path as the blocks with explicit `_buildEditable...` methods. A block can have schema controls and still feel non-editable on the canvas.

Required convergence:

- Every block must declare whether it supports inline editing, side-panel editing, or both.
- A missing editable renderer must be treated as a product gap, not as an acceptable default.
- The fallback public renderer can remain as compatibility, but it should not hide missing editor capabilities.

2) Text editing is not the same as text styling.

Many blocks use `InlineEditableTextV2`, but only some pass `formatting` and `onFormattingChanged`. That means a toolbar can appear while formatting changes are not persisted. Side-panel text fields are usually `_EditorTextField`, and `WebsiteBlockFieldType.richtext` currently renders as raw HTML text.

Required convergence:

- Add schema metadata for text role and formatting capability: heading, paragraph, caption, button label, quote, stat value, nav label.
- Make every formatted text field persist a shared `TextFormatting` payload or explicitly use a text-only preset with no styling affordance.
- Add a shared side-panel text-style inspector that edits the same data as `InlineEditableTextV2`.
- Remove or quarantine the older `InlineEditableText` after migration.

3) Link and action controls are still fragmented.

`WebsiteLinkValueEditor` is the canonical link picker. The private canvas `_LinkPicker` used to exist inside `website_editor_panel.dart` for canvas button links and was removed in the June 5 implementation slice. Some blocks still store CTA text but no CTA destination, while others store `ctaLink`, `buttonLink`, `link`, or an `actions` list.

Required convergence:

- Keep the removed `_LinkPicker` from returning; canvas button links now use `WebsiteLinkValueEditor`.
- Define a shared action model for page/category/product/search/anchor/external/WhatsApp/call/email/cart/account.
- Normalize legacy keys into canonical action/link keys on load/save.
- Do not add a button, card, pricing plan, menu item, or canvas element unless its destination is user-editable through the shared picker/action model.

4) Media/background controls are not universal.

Carousel and hero have focal-point support. Canvas background, video banner, CTA/background banners, category cards, gallery images, team avatars, logos, and other image surfaces do not share that full capability.

Required convergence:

- Create a shared `CoverMediaControl`: upload/select asset, image URL, optional video, poster/fallback, fit, overlay, focal point, responsive focal overrides, alt text, and reset-to-theme/default.
- Use it anywhere an image is used as a cover/background/card image.
- Create a separate `InlineMediaControl` for logos, avatars, and non-cover images with upload, alt text, link, and sizing.
- Keep `mobileFocalPointX/Y` as compatibility, but migrate toward canonical `focalPointX/Y` plus responsive overrides.

5) Repeaters and list editors are too generic.

Slides, services, team members, FAQ items, testimonials, gallery items, pricing plans, footer links, categories, and logo lists are all repeaters, but the UX ranges from custom cards to comma-separated chips.

Required convergence:

- Build a shared repeater/list editor with add, duplicate, delete, reorder, collapse, validation, preview label, drag support, and nested item support.
- Replace comma-chip fields where the item is actually structured data, especially brand logos, social links, pricing benefits, partners, and category cards.

6) Save semantics are inconsistent.

The main editor stages changes and persists through global `Guardar`. However, older settings dialogs, Google sync actions, footer navigation creation/editing, inline footer nav editing, and some service calls persist immediately. Some UI copy says "Los cambios se guardaran al presionar Guardar", while nearby controls still have local `Guardar` buttons.

Required convergence:

- Classify every editor control as staged content/config or immediate operation.
- Staged content/config must write to `WebsiteEditModeProvider` pending state and wait for global `Guardar`.
- Local dialogs may confirm form input, but they should update staged state and use `Aplicar`/`Listo`, not direct persistence labeled `Guardar`.
- Immediate persistence is allowed for clearly operational actions such as OAuth connect, Google sync/import, publish/unpublish, backup restore, destructive deletes, or external data refresh.
- `Descartar` must reliably discard staged theme, block, page, header, footer, navigation, category, and control changes.

7) Theme/font consumption is not complete.

The screenshot problem is still real: some public-store surfaces use saved `theme_heading_font`/`theme_body_font`, while others still reference `PublicStoreTheme.defaultHeadingFont` or `defaultBodyFont` directly.

Required convergence:

- Add a single public-store theme resolver and make every public surface consume it.
- Treat `PublicStoreTheme` constants as fallback only.
- Keep `WebsiteFontRegistry` as the single font source for the theme panel, renderer, preset defaults, and any future font-family text toolbar.

8) Capability schema is too shallow.

`WebsiteBlockFieldType` can express primitive inputs, but not capability intent. For example, `text` does not say whether the field is a heading, plain label, rich paragraph, button label, or stat number. `image` does not say whether it is a cover background, logo, avatar, gallery item, or poster.

Required convergence:

- Extend `WebsiteBlockFieldSchema` with capability metadata, not just primitive field type.
- Suggested metadata: `textRole`, `formattingPreset`, `mediaRole`, `supportsFocalPoint`, `supportsAltText`, `actionRole`, `styleRole`, `responsiveOverrides`, `themeToken`, `validation`, and `migrationAliases`.
- Renderer defaults should come from registry capability/default data, not private widget assumptions.

### Canonical controls to converge around

- Link/destination picker: `WebsiteLinkValueEditor`.
- Inline formatted text: `InlineEditableTextV2` plus `TextFormattingToolbar`.
- Text toolbar presets: `TextToolbarPreset.textOnly`, `minimal`, `basic`, `full`.
- Cover/background focal point: `FocalPointPicker`, promoted into a shared cover-media control.
- Click-to-upload image surface: `InlineEditableImage` and the shared website image upload path.
- Schema-driven side-panel fields: `WebsiteBlockFieldSchema`, expanded with capability metadata.

These are the controls to converge around unless a future task explicitly replaces them.

### Redundant or suspicious legacy files/surfaces

These should be audited before deletion, then either removed or quarantined behind explicit compatibility notes:

- `lib/modules/website/pages/visual_editor_page.dart`: standalone split-screen editor with placeholder/TODO data; appears outside the current inline editor architecture.
- `lib/modules/website/pages/visual_editor_page_advanced.dart`: older advanced editor prototype with TODO storage paths and placeholder content.
- `lib/public_store/widgets/editable_website.dart`: alternate editor/rendering shell that overlaps the inline editor.
- `lib/public_store/pages/public_home_page_old.dart`: old home implementation.
- `lib/public_store/pages/dynamic_website_page_old.dart`: old dynamic page implementation.
- `lib/modules/website/widgets/inline_editable_text.dart`: older simple inline text editor; migrate to V2 or keep only as a clearly documented compatibility wrapper.
- The unused legacy inline toolbar/settings dialog, alternate editable website
  shell, and both visual-editor prototype pages were deleted on June 8, 2026.
  Their duplicate local `Guardar` flows must not be reintroduced.
- `lib/public_store/widgets/website_page_content.dart`: may be a future consolidation target, but current references suggest it is not yet the active renderer. Decide whether to adopt it as the shared renderer or remove it to reduce confusion.

### Refactor plan from this inspection

P0: Create the capability matrix as code, not only docs.

- Add a capability declaration layer for every block: text fields, formatted text fields, media fields, action/link fields, repeaters, responsive support, animation support, and save mode.
- Make the editor panel read these declarations so missing controls are obvious.
- Add a coverage check that fails when a block declares a capability without a canonical control or when a block uses a duplicate control.

Started in the June 5 implementation slice:

- `lib/modules/website/models/website_block_capabilities.dart` now declares capability/save-mode/gap profiles for every `WebsiteBlockType`.
- `WebsiteBlockRegistry.capabilitiesFor(...)` exposes the profile next to the block definition.
- `test/unit/website_block_capabilities_test.dart` locks complete profile coverage, known blocks without explicit editable renderers, mixed save semantics, pricing CTA destination ownership, and the removal of private link pickers (`_LinkPicker`, `_DarkLinkPicker`, `_InlineLinkPicker`).
- `lib/modules/website/models/website_font_registry.dart` now limits editor-selectable theme fonts to the families actually bundled in `pubspec.yaml`, resolves unsupported legacy values, feeds the `Tema > Textos` dropdown, and is enforced by `WebsiteThemeBuilder`, `WebsiteBlockRenderer`, `EditableBlockRenderer`, `ThemePreset`, `PublicHomePage`, and `DynamicWebsitePage`.
- Existing footer navigation item edits from the side panel now stage whole `WebsiteNavigation` objects in `WebsiteEditModeProvider` and save through the global editor `Guardar`; the inline panel confirmation uses `Aplicar` instead of a misleading local `Guardar`.
- Footer contact/social dialogs in `PublicStoreLayout` now stage `updateFooterSetting(...)` changes and use `Aplicar`, instead of writing `website_settings` directly from local dialog buttons.
- Footer navigation create/edit/delete/reorder now stages through draft IDs in `WebsiteEditModeProvider` and persists only through the global editor save pipeline.

### June 8, 2026 implementation status

The following cross-cutting refactor work is now implemented and supersedes older gap notes in this document:

- The field schema declares semantic text/media/action capability metadata and resolves sensible roles for every registered schema field.
- The generic editor routes all schema image fields through the shared image picker, exposes alt text universally, and exposes focal-point controls for cover/gallery media. Cover media also receives a mobile focal point.
- Hero, CTA, video-banner fallback images, category cards, gallery images, and carousel/hero backgrounds consume the shared focal-point values.
- Schema fields that declare persisted formatting use the canonical `TextFormattingToolbar` in the side panel and write the same formatting payload used by editable/public renderers.
- The duplicated hero-only focal-point panel was removed.
- The generic repeater now has universal add, duplicate, reorder, delete, minimum-item, and maximum-item behavior.
- Partners and brand logos now use structured repeaters instead of comma-separated lists; brand items expose the shared image, alt-text, and destination controls.
- The add-block dialog and active add-block sidebar are registry-driven and no longer maintain independent hardcoded block lists.
- Registry discovery now always returns every `WebsiteBlockType`. Marketplace JSON enriches discovery metadata but can no longer replace/remove the canonical capability-rich editor schema.
- Marketplace field parsing supports semantic text/media/action capability metadata for future external definitions.
- Carousel side-panel title/subtitle formatting writes the same payload consumed by the public carousel renderer, and carousel slides now expose desktop focal point, mobile focal point, and alt text.
- Canvas background images now expose the shared focal-point controls, mobile focal point, and alt text, and the canvas renderer consumes them.
- Footer navigation create/edit/delete/reorder and footer settings are staged. `Descartar` restores blocks and clears staged theme/site/footer/navigation/category/SEO state.
- Backup restore reloads restored database state into the active editor instead
  of invoking the global save callback and risking an overwrite from stale
  in-memory blocks.
- The legacy inline settings dialog, alternate editor shell, and visual-editor
  prototype pages were removed after their active responsibilities were
  extracted.
- Public-store commerce pages no longer force `PublicStoreTheme.defaultHeadingFont/defaultBodyFont`, allowing the active editor-owned website theme to control typography across catalog, product detail, cart, checkout, confirmation, contact, policy, header, and footer surfaces.
- Regression tests cover full capability-profile registration, universal schema metadata, canonical controls, registry-driven add-block discovery, font override scans, staged footer navigation, and discard behavior.

Remaining high-value gaps:

- Canvas element text editing still has a custom toolbar/model; canvas background
  media already uses the shared focal/media controls.
- Products, category grid, video banner, partners banner, brand logos, Google
  reviews, and footer still lack full explicit inline-editable renderers; their
  side-panel/special editor paths remain functional.
- The full shared action model should expand beyond the current canonical link
  picker and CTA action normalization.

P0: Fix save semantics.

- Remove direct content/config saves from block and footer/navigation editors.
- Route footer nav changes through pending state, then global `Guardar`.
- Keep Google sync/import and destructive operations immediate, but label them as operations and keep them separate from editable block config.

P0: Unify text editing and persistence.

- Migrate all inline text to `InlineEditableTextV2` with correct presets and persisted formatting callbacks.
- Add a shared side-panel text-style inspector for the same `TextFormatting` data.
- Ensure fields that do not support formatting use `textOnly` and do not show a misleading toolbar.

P0: Unify media/focal controls.

- Build the shared cover-media control and migrate hero, carousel, canvas background, CTA, video banner, category grid, gallery cover/card modes, and any banner/background images.
- Add a shared inline media/logo/avatar control for team avatars, logos, and non-cover images.

P0: Unify links/actions.

- Keep canvas button links on `WebsiteLinkValueEditor` and continue replacing any future/private destination pickers with the same canonical editor.
- Add missing action/link fields where blocks currently have only CTA text or implicit renderer defaults.
- Normalize aliases such as `ctaLink`, `buttonLink`, `link`, and `actions.to`.

P1: Unify repeaters/lists.

- Replace ad-hoc repeaters and comma chips with a shared list editor that supports structured items, reorder, duplicate, validation, and nested lists.
- Prioritize carousel slides, footer/nav lists, gallery items, brand logos, pricing plans, category cards, team members, FAQ items, testimonials, and service cards.

P1: Unify style/theme controls.

- Build shared color, spacing/dimension, typography, animation, and responsive controls.
- Ensure every local override can reset to theme/default.

P1: Add editor guardrails.

- Static scan for direct `PublicStoreTheme.defaultHeadingFont/defaultBodyFont` consumption outside fallback/resolver code.
- Static scan for duplicate controls like `_LinkPicker` and block-local `Guardar` buttons.
- Runtime smoke tests for changing theme font, editing block text, editing media focal point, editing links/actions, saving, discarding, and reloading.

### Acceptance criteria for universal controls

- The documentation and implementation audits every block type, not only examples supplied in a prompt.
- Every block declares its editable capabilities and missing capabilities are visible in code review.
- Blocks without an explicit editable renderer are either migrated or deliberately documented as non-inline-editable with a side-panel-only experience.
- Every visible text field either persists shared formatting or exposes a text-only editor with no misleading formatting toolbar.
- Any cover image can be repositioned with the same focal-point UI, not only carousel/hero.
- Any link/action destination uses the same picker and normalization path.
- Content/config edits use global `Guardar`; no block-local direct-save button persists staged website content.
- A control improved in one block becomes available to all blocks with that capability.
- Old editor prototypes are removed or clearly quarantined so future agents do not accidentally revive them.

---

## 0) The actual problem we’re solving (and why it felt like a “Frankenstein”)

This refactor started from specific bugs (ex: wrong navigation targets), but the deeper issue is systemic:

- The Website Builder stores configuration as `jsonb` (`website_blocks.block_data`). That means **wrong keys are still valid data**.
- When the editor writes one shape and the renderer reads another (or uses hardcoded fallbacks), the UI becomes a **Frankenstein**:
  - edits appear to “not work”
  - old/stale values “win” silently
  - similar features behave differently across blocks (links, toolbars, media controls, actions)

So the goal is not “fix the next bug faster” — it’s to **stop drift** by turning repeated behaviors into shared capability systems.

### North Star: capability systems (the future-promising direction)

When multiple blocks share a capability, they MUST share the same:
- UX surface (same editor widgets)
- stored data rules (canonical keys + formats)
- renderer behavior (no per-block hacks)

The guiding capability systems:

1) **Links / Navigation**
  - One picker UX everywhere (no raw text URL inputs).
  - One canonical href model (string path/URL) with normalization for legacy `/tienda/*` and legacy params.
  - Renderers must follow editor-assigned values; avoid “helpful defaults” that override saved config.

2) **Inline Text Editing**
  - One inline editing system across blocks.
  - Toolbars must be consistent via presets (so button labels don’t get a different editor than headings).

3) **Media Controls (cover/background images)**
  - One shared approach for image editing + positioning.
  - Mobile focal point / background positioning must be consistent across all cover-image blocks (not hero-only).

4) **Navigation Normalization Layer**
  - Treat stored hrefs as “user data” that may be legacy/inconsistent.
  - Normalize at load/save boundaries (service layer) so persisted data becomes more correct over time.

### Migration philosophy (how we upgrade without breaking tenants)

Prefer: **compat + normalize + converge**
- Compat: renderers can read legacy keys safely.
- Normalize on load: incoming data is shaped into the canonical format before editing.
- Normalize on save: any edit permanently repairs persisted data.
- Optional: one-time cleanup scripts per tenant to accelerate convergence.

### Definition of done for any editor change

- Editor-assigned values always win.
- The same capability behaves the same across blocks.
- Legacy data is handled and ideally normalized so it doesn’t regress later.

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

Immediate “capability convergence” priorities (to stop drift fast):

- **Text editing presets rollout:** standardize which toolbar preset each field type uses (headings vs body vs button labels) so the editor feels consistent everywhere.
- **Cover-image focal point rollout:** apply the same mobile focal point/background positioning model + controls to every block that uses cover/background images (hero, carousel, banners, cards, etc.).
- **Navigation link picker everywhere:** ensure all navigation management surfaces reuse the same link picker UX (same behavior as block link fields).

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

## 12) Remaining Deliberate Follow-up

The June 8, 2026 refactor completed the active-editor save pipeline, registry-driven
block discovery, universal schema controls, footer staging, public font inheritance,
and legacy-toolbar extraction. The remaining work is narrower:

1) Move canvas element text editing onto the same persisted rich-text model used by
   schema-backed block text fields. Canvas currently shares focal/media controls but
   still owns its element toolbar.
2) Add explicit inline renderer coverage for block types that currently rely on the
   fully functional side panel or a specialized editor: products, category grid,
   video banner, partners, brand logos, Google reviews, and footer.
3) Continue the responsive override engine and action model described in the roadmap.
4) Manually verify footer drag/drop and the main block workflows in a browser against
   a populated tenant.

Publishing, Google synchronization/import, and custom-domain operations intentionally
remain immediate operational actions. They are not content-editing save exceptions.


## 13) Non-goals (Explicitly out of scope)

- Introducing new pages, modals, or additional UX beyond the described editor refactor.
- Changing the design system (new colors/fonts/shadows).
- Adding new tables/columns unless strictly necessary.

---

End of handoff.
