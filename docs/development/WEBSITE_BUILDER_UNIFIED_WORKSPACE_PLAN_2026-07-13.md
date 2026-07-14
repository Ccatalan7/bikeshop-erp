# Website Builder Unified Workspace Plan

**Date:** 2026-07-13  
**Status:** Implemented — authenticated visual QA remains  
**Scope:** ERP Website Editor, its black management bar, catalog publication,
categories, pages, navigation, and campaign destinations

**Mandatory current engineering contract:**
[`docs/architecture/website-editor-contract.md`](../architecture/website-editor-contract.md).
That contract incorporates the implemented workspace design plus later lessons
about editor/Preview parity, Canvas clipping, nested inspector selection,
media-picking, routed system pages, global theme behavior, and agent-created
campaigns.

## Goal

Make the Website Builder feel like one connected system while preserving one
canonical owner for every setting. A user should be able to design a campaign,
prepare its catalog/category destination, connect the CTA, preview it, and
publish it without guessing which of several overlapping screens is correct.

The public website, visual canvas, right inspector, and management bar must all
represent the same saved state. No renderer-only or agent-only paths are
allowed.

## Confirmed Problems

1. The management bar embeds complete ERP pages inside the editor viewport
   while the unrelated 380 px block inspector remains visible. A full product
   table therefore competes with carousel controls on the same screen.
2. `Tienda > Productos (publicar en web)` opens the generic inventory
   `ProductListPage`, while `Visibilidad de productos` is the actual bulk web
   publication screen. The labels imply two competing publishers.
3. Category public visibility edits the same
   `product_categories.show_on_website` state in multiple places:
   `ProductWebsiteVisibilityPage` and `Tema > Categorías`. These surfaces have
   different scope and save semantics.
4. `Tema > Categorías` describes category visibility as navigation behavior,
   but real header/footer menu placement belongs to `website_navigation`.
   Catalog visibility and menu placement are separate concepts.
5. The header inspector writes a competing `header_nav_links` setting while
   the public header consumes `website_navigation`.
6. `Contenido (banners / textos)` opens the legacy `website_contents`
   management surface, while live page banners and text are editor blocks.
7. Category CRUD and website publication are disconnected. Editing a category
   currently rebuilds the model without preserving `showOnWebsite`, which can
   unintentionally reset its public visibility.
8. `WebsiteLinkValueEditor` can select active categories, but it does not prove
   that the category is publicly visible or contains public products. Its
   summary can expose a raw category UUID instead of a useful category name.

## Target Information Architecture

The black bar switches between workspaces; it must never display two unrelated
jobs at the same time.

### 1. Editar página

- Website canvas plus the right block inspector.
- Blocks, slides, text, images, layout, CTA, animation, theme, header, and
  footer presentation.
- Global editor `Guardar`, preview, and publish behavior remains intact.

### 2. Catálogo web

One full-width management workspace with these subviews:

- **Productos:** publish/hide products and show readiness problems.
- **Categorías:** create/edit the category tree and control public catalog
  visibility in the same canonical view.
- **Colección destacada:** manage the reusable featured-product set.
- **Reglas:** stock, required image, category filtering, and uncategorized
  product behavior.

Full inventory CRUD remains available through a clearly labeled
`Abrir Inventario` action. It is not embedded as a second website publisher.

### 3. Estructura

- **Páginas:** create, edit, order, publish, and select website pages.
- **Navegación:** manage header/footer links, hierarchy, dropdowns, and mega
  menus through canonical `website_navigation` records.
- A normal product category uses its generated catalog destination. Do not
  create a duplicate `website_pages` row merely to obtain a category URL.

### 4. Ajustes

- Theme/site settings, SEO, domain, payments, and integrations.
- Orders, analytics, feed tools, and other operations may live here or in a
  small overflow/Website Center; they must not compete with page composition.

## Workspace Behavior

Introduce an explicit workspace state such as:

```dart
enum WebsiteWorkspaceMode {
  pageEditor,
  catalog,
  structure,
  settings,
}
```

- `pageEditor` shows the canvas and persistent inspector.
- Every management workspace uses the full available width and hides/suspends
  the block inspector.
- Show a clear `Volver al editor` action with the current page name.
- Preserve the selected page, selected block/slide, scroll position, and draft
  state when switching workspaces.
- If page changes are pending, switching must preserve them or present an
  explicit `Guardar / Descartar / Cancelar` guard. Never silently lose them.
- Management operations must not be confused with the editor-wide staged
  `Guardar` pipeline.

## Canonical Ownership

| Concern | Canonical owner | Contextual surfaces |
|---|---|---|
| Page blocks and carousel slides | Website Editor block data | Canvas and block inspector |
| Product web publication | Catalog publication command/service | `Catálogo web > Productos`, product form shortcut |
| Category taxonomy and public visibility | `CategoryService` plus one shared category management view | Catalog category tab and read-only/deep-link summaries |
| Public catalog rules | Website catalog settings service | `Catálogo web > Reglas` |
| Featured products | One featured collection service/view | Catalog tab and Products-block shortcut |
| Pages | `website_pages` through page service | Structure workspace and page selector |
| Header/footer navigation | `website_navigation` | Structure workspace and shared link picker |
| CTA destinations | `WebsiteLinkValueEditor` | Every link-capable block/menu/card |

Multiple shortcuts are acceptable. Multiple independent implementations or
stored values for the same meaning are not.

## Required Carousel-to-Category Workflow

For a request such as “add a carousel slide linking to a new category”:

1. Open `Catálogo web > Categorías`.
2. Create or edit the real category and mark it visible in the public catalog.
3. Assign/publish the intended products and verify at least one product is
   actually public under current catalog rules.
4. Return to the same carousel slide in `Editar página`.
5. Configure the slide through editor controls.
6. Use `WebsiteLinkValueEditor` and choose `Categoría` as a first-class
   destination. Store the canonical category-ID-based catalog link.
7. Preview the CTA and verify the resulting category page/products.
8. Save and publish through the normal editor workflow.

The category picker must show the category name/path, public/hidden status, and
public product count. Hidden or empty categories must produce a clear warning
and a direct `Configurar catálogo` action. Creating/configuring a category from
the picker must return the user to the same slide afterward.

## Implementation Phases

### Phase 1 — Workspace separation

- Add shared workspace mode/state.
- Make management screens full-width.
- Hide the persistent inspector outside `pageEditor`.
- Add return-to-editor context preservation and unsaved-change protection.

Primary files:

- `lib/public_store/widgets/public_store_layout.dart`
- `lib/public_store/widgets/persistent_editor_shell.dart`
- `lib/modules/website/providers/website_edit_mode_provider.dart`

### Phase 2 — One Catalog Web workspace

- Replace `Productos (publicar en web)`, `Visibilidad de productos`, and the
  separate website category publication entry with one `Catálogo web` entry.
- Use `ProductWebsiteVisibilityPage` as the starting point, then extract shared
  Products, Categories, Featured, and Rules subviews.
- Keep generic product/category CRUD under Inventory, exposed only as advanced
  handoffs.
- Centralize product publication's required `is_published` plus
  `show_on_website` write behind one command/service.

### Phase 3 — Category convergence

- Put create/edit hierarchy and `Visible en catálogo público` in the canonical
  category subview.
- Preserve `showOnWebsite` when editing existing categories.
- Remove category publication controls from `Tema` and replace any useful
  context with a status summary/deep link to the canonical catalog view.
- Label navigation placement separately and manage it only through
  `website_navigation`.

### Phase 4 — Campaign destination flow

- Upgrade `WebsiteLinkValueEditor` with first-class Page, Category, Product,
  Anchor, and External destination choices.
- Reuse catalog/category services instead of querying separate ad-hoc data.
- Show public-readiness status and friendly category paths.
- Add return-to-slide behavior after catalog configuration.

### Phase 5 — Remove misleading/dead competitors

- Remove/deprecate `header_nav_links` after compatibility review; keep
  `website_navigation` canonical.
- Remove the misleading legacy `Contenido (banners / textos)` entry unless a
  confirmed public consumer is found and intentionally migrated.
- Consolidate quick page creation with the canonical page creation flow.
- Correct menu labels so each item describes the screen it actually opens.

### Phase 6 — Documentation and surface registry

- Extend `.github/copilot-instructions.md` with the connected canvas/management
  bar contract and canonical ownership rules.
- Register the routed, embedded, editor, and quick-action website surfaces in
  `docs/architecture/canonical-ui-surfaces.md`.
- Update website architecture/handoff documentation to remove obsolete owners.

## Verification and Acceptance Criteria

- Only one editable control owns category public visibility.
- Category visibility and navigation placement have distinct language/state.
- `Catálogo web` uses the full workspace; no carousel inspector remains beside
  a product/category table.
- Switching workspaces preserves editor drafts and returns to the same page and
  selected slide.
- Product/category/page/navigation shortcuts land on canonical shared views.
- Category edits never reset existing website visibility unintentionally.
- A category CTA cannot silently target a hidden or empty public category.
- A normal category CTA does not create a duplicate CMS page.
- CTA values round-trip through `WebsiteLinkValueEditor` and survive reload.
- Public renderers consume the saved editor/catalog/navigation values.
- Remove or migrate dead competing settings only after compatibility coverage.
- Add architecture/widget tests for workspace ownership, category visibility,
  navigation source, CTA category destinations, and unsaved-state protection.
- Verify normal user paths at desktop 80% and 100% app zoom, then check tablet
  and mobile layouts.

## Database Scope

No database migration is required for the first implementation pass. Reuse
existing `products`, `product_categories`, `website_settings`,
`featured_products`, `website_pages`, `website_navigation`, and
`website_blocks` data. Any later schema change must follow the Supabase staging
runbook and update `supabase/sql/core_schema.sql` in the same task.

## Explicit Non-Goals for the First Pass

- Rebuilding the inventory module.
- Changing public catalog business rules without a separate approved request.
- Creating a second category/page/navigation model.
- Redesigning the public storefront itself.
- Migrating product publication flags before the unified command and UI are
  stable.

## Implementation Progress — 2026-07-13

Completed in the first implementation slice:

- Added explicit editor workspace state and preserved the current page draft
  when moving between page editing and management workspaces.
- Converted management screens to full-width workspaces and hid the block
  inspector outside `Editar página`.
- Replaced competing website-product/category entries with one primary
  `Catálogo web` entry and `Productos`, `Categorías`, and `Destacados` tabs.
- Removed the duplicate category-publication control from `Tema`; website
  category publication now has one Website Builder owner.
- Preserved `showOnWebsite` and `sortOrder` during category edits so taxonomy
  maintenance cannot silently unpublish a category.
- Improved category CTA selection with friendly paths, public/hidden status,
  website-product counts, and readiness warnings.
- Added typed Page, Category, Product, System, Section, External, and advanced
  internal destination handling while preserving the existing href storage
  contract.
- Added `Estructura > Destinos y enlaces`, a read-only integrity workspace that
  finds persisted block/menu links, resolves their canonical owners, reports
  broken/draft/hidden destinations, shows every usage, and distinguishes
  `Solo campaña` from explicit header/footer placement.
- Added configure-owner actions that apply the current CTA and open the
  canonical full-width Page/Catalog/Destination workspace; returning preserves
  the selected editor block/slide and draft.
- Combined category publication and category structure/naming as two views of
  `Catálogo web > Categorías`.
- Centralized product and category web-publication writes in `WebsiteService`
  commands used by the unified catalog surface.
- Removed writes and controls for legacy `header_nav_links`; navigation is now
  owned only by `website_navigation`.
- Redirected the unconsumed legacy `/website/content` surface to the canonical
  destination-integrity workspace.
- Simplified the black management bar into `Editar página`, `Catálogo web`,
  `Estructura`, `Ajustes`, and `Más`, with an explicit return-to-editor action
  and draft-preserved indicator.
- Documented the shared canvas/management-bar contract and registered the
  canonical Website Builder surfaces.
- Added architecture regression tests; targeted tests, targeted analyzer, and
  the Flutter web debug build pass.

Completed in the universal CTA/theme slice:

- Introduced `WebsiteActionValue` as the canonical label, href, and
  presentation model and reconciled legacy aliases plus structured `actions`
  at editor/provider/service boundaries.
- Replaced banner, carousel, pricing, Products “Ver todos”, standalone, video,
  and Canvas CTA controls with `WebsiteActionEditor` and the shared typed
  destination picker.
- Routed public navigational CTA rendering through `WebsiteActionButton`, so
  action variants and theme behavior no longer need per-block implementations.
- Connected Tema `button_style` and `button_size` to global Flutter button
  themes, removed per-block radius/spacing overrides, and made Canvas inherit
  the global style by default with one explicit advanced opt-out.
- Removed the nonfunctional Transiciones entry instead of presenting a control
  that did not affect the public site.
- Added regression coverage for stale-action precedence, atomic alias syncing,
  capability completeness, and global button theme tokens.
- Fixed filtered-catalog CTA round-tripping so combined category plus
  brand/search campaigns reopen with every filter visible in the shared link
  editor, using `WebsiteDestination.routeForCatalog` as the canonical builder.

Still planned:

- Consider promoting the existing catalog rules panel to a dedicated `Reglas`
  tab after observing the consolidated workspace with real staff usage.
- Decide whether publish should hard-block broken internal destinations or keep
  the current warning-first workflow.
- Complete authenticated visual QA at the required desktop, tablet, and mobile
  widths.
