# Website Builder refactor — implementation status

**Snapshot date:** 2026-07-22  
**Repository:** `bikeshop-erp`  
**Scope:** Website Builder, Catálogo web, public storefront, category
collections, typed destinations, navigation, Preview parity, product detail,
Google Merchant and Search foundations  
**Normative sources:**
[`website-editor-contract.md`](website-editor-contract.md),
[`website-builder-agent-handoff.md`](website-builder-agent-handoff.md) and
[`canonical-ui-surfaces.md`](canonical-ui-surfaces.md)

This document records the **actual implementation state** of the current local
checkout. It is not a replacement for the architectural contract. Its purpose
is to separate what is already working from what is only partially implemented,
still pending, or recommended as a future professional enhancement.

## Executive verdict

The complete Website Builder/storefront refactor is **not finished**.

The current checkout contains an integrated, editor-owned catalog and
collection implementation: catalog management, root/category presentation,
clean product and service routes with durable aliases, canonical navigation
and mega-menu interaction, responsive catalog rendering, shared storefront
theme projection, restrictive runtime SEO, crawler snapshots, and one typed
commerce projection shared by product detail, JSON-LD, snapshots,
cart/checkout and Merchant consumers.

The implementation is still **not release-complete**. The additive server-side
facet wrappers are deployed and verified in production, but the Merchant Edge
Functions and generated redirect/snapshot artifacts have not been deliberately
deployed in this slice. The unlocked macOS desktop pass now covers catalog
management, rules/filters, publication confirmation, inline product editing,
Preview collection/detail navigation and the canonical full-width `Componentes`
mega menu. Responsive/mobile, saved-presentation reopen, complete browser E2E
and browser-level commerce value-equality proof remain release gates. Advanced
editorial modules and richer structured product facets remain follow-up work.

## Status legend

| Status | Meaning |
|---|---|
| ✅ Completed | Implemented in the canonical owner and verified in proportion to its current scope |
| 🟡 Partial | Useful implementation exists, but one or more required controls, consumers or verification paths remain |
| ⬜ Pending | Required by the agreed evolution plan and not implemented yet |
| 💡 Suggested | Optional professional enhancement; not required to call the current agreed phase complete |

## Product and UX benchmark that motivated the refactor

This section preserves the original comparison and runtime observations that
led to the current implementation. It is a **historical baseline**, not a claim
that every Viñabike symptom described below still exists in the current
checkout.

Commencal is used only as a reference for information architecture, hierarchy,
spacing and interaction quality. The goal is not to copy its visual identity.
Every Viñabike result must remain driven by its own editor, catalog, navigation,
theme and real product data.

### Original walkthrough performed

The following real Preview path was exercised without editing files:

1. Home and header.
2. `Componentes` mega menu.
3. `Transmisión` group.
4. `Cadenas` and `Cámaras` categories.
5. Filter changes and loading states.
6. Product grid.
7. Individual Cámara product.
8. Category/catalog breadcrumb return.

### Commencal versus Viñabike baseline

| Area | Commencal reference | Viñabike observed baseline | Current checkout status |
|---|---|---|---|
| Header | Primary navigation plus a contextual second row | Functional header, but opening the mega menu felt like a separate large black application layer | 🟡 Saved `website_navigation` now selects the responsive full-width mega-menu renderer; desktop ERP Preview and standalone-public interaction passed, while mobile/accessibility acceptance remains |
| Mega menu | Few primary choices with strong hierarchy | Too many categories and products appeared simultaneously; the panel was tall, dark and visually saturated | ✅ Hierarchy, typed destinations, hover intent, click, keyboard/Escape and mobile navigation are implemented without category-name branches |
| Category page | Hero, description, breadcrumb, subcategories and catalog | Category was only a filter applied to `/productos` | 🟡 A real collection route, full-width hero, breadcrumb, subcategory navigation, grid and SEO controls exist; optional editorial modules remain |
| Hierarchy | `Components / Components / Drivetrain` remained visible | Menu hierarchy disappeared after entering a generic page titled `PRODUCTOS` | ✅ Navigation, category route, breadcrumb and product-detail return resolve the same stable category hierarchy |
| Filters | Category, brand, material, standards and speed count | Search plus four public categories | 🟡 Category/availability plus typed brand/effective-price support are active through the production one-scan facet RPC; richer structured attributes remain |
| Grid | Large images, airy cards and consistent hierarchy | Five columns could compress long titles and reduce product-image presence | 🟡 Editor-controlled density, shared responsive metrics and theme projection are implemented; unlocked desktop Cámaras passed, while narrow/mobile visual stress testing remains |
| Product detail | Not part of the original Commencal comparison | Viñabike already had a solid structure: image, price, stock, SKU, purchase actions, delivery, pickup and detail tabs | ✅ Product route now opens correctly and includes canonical category context when available |
| Loading transitions | Selection, count and products changed coherently | New selection could appear while the old count/grid remained visible for several seconds | 🟡 Token guards, row clearing and atomic result/facet commits are implemented; browser E2E for the exact cross-category/back sequences remains |

### Original functional inconsistency found

The baseline produced two false intermediate states:

1. While changing from `Cadenas` to `Cámaras`, `Cadenas` first showed zero
   products. After selecting `Cámaras`, the UI showed `Cámaras (22)` as selected
   while the grid still displayed the eight Cadenas products. The correct
   Cámara products arrived several seconds later.
2. Returning from a product detail could show `Todas (547)` as selected while
   the grid still contained the 22 Cámara products. The full result set arrived
   later.

This is not acceptable as harmless loading polish: during those transitions
the interface stated something false.

The required transition contract is:

- cancel an obsolete request when supported, or ignore its response with a
  monotonic request token;
- never combine a new selection with old rows or an old count;
- clear or skeleton the result region while the next coherent snapshot loads;
- commit route context, selected facet, count and product rows as one coherent
  visible transition;
- preserve the same contract for direct navigation, back/forward and return
  from product detail.

Current implementation progress:

- ✅ Stale catalog responses are rejected through load tokens.
- ✅ Filter/category changes clear old result rows while loading.
- ✅ Edit → Preview explicitly reloads the canonical public result instead of
  retaining the editable set.
- ✅ The validated Cámaras Preview returned 22 effective products and retained
  that context through product detail and breadcrumb return.
- ⬜ Automated coverage is still required for the exact
  Cadenas → Cámaras and Cámara detail → back sequences on desktop, mobile and
  the standalone public storefront.

### Original mega-menu assessment

The underlying taxonomy was valuable, but its presentation obscured that
value:

- the panel was excessively tall and dark;
- too many left-column families had equal visual weight;
- the right side resembled a matrix of dispersed words;
- category, subcategory and product roles were not sufficiently distinct;
- entering `Transmisión` removed the hierarchy and landed on a generic catalog;
- there was no strong visual transition from the menu selection into the
  destination collection.

The target is a mega menu that behaves as an extension of the header and is
generated from the same canonical navigation/category hierarchy as collection
routes and breadcrumbs. It must support accessible hover intent, click and
keyboard interaction without hardcoded category names.

### Original product-detail assessment

The product-detail page was already one of Viñabike's strongest surfaces. The
baseline identified two integration problems:

- the breadcrumb used `Inicio / Productos / Producto` instead of including the
  real category when available;
- the editor top bar could show `Página: Inicio` while a dynamic product route
  was active.

Both issues are addressed in the current checkout through the canonical
category destination and exact dynamic path recognition, but they remain part
of the regression contract.

### Design direction derived from the comparison

The professional collection target remains:

- a clean typed route owned by the real category;
- breadcrumb generated from the canonical hierarchy;
- configurable full-width hero;
- editable title, description, image and SEO;
- subcategory/buying-path navigation;
- filters derived from real catalog attributes;
- responsive grid with sufficient image and title space;
- skeleton or contained loading state;
- atomic URL/selection/count/result transitions;
- mega menu generated from the same hierarchy;
- complete Edit, Preview, standalone public, direct navigation, back/forward
  and mobile verification.

The original priority order was:

1. Fix inconsistent transitions and dynamic routes.
2. Build a real category collection template.
3. Redesign the mega menu from the same canonical hierarchy.
4. Add canonical professional facets and improve grid spacing.
5. Verify editor, Preview, public storefront, direct links, browser history
   and mobile.

Priorities 1–4 now have an integrated implementation at code/contract level.
Priority 5 remains incomplete until the real Edit/Preview/public
desktop/mobile acceptance matrix is finished.

## Non-negotiable implementation rules

Every remaining item must continue to satisfy these rules:

1. **Owner:** one canonical entity owns the meaning.
2. **Control:** an administrator can find, edit, remove and understand it in
   the Website Builder or its management workspaces.
3. **Operation:** UI and automation use the same validation and persisted
   representation.
4. **Consumers:** Edit, Preview and the public storefront resolve the same
   saved value.
5. Product results are query-backed. Category pages must never contain copied
   or hardcoded product lists.
6. Navigation remains owned by `website_navigation`; category presentation
   does not silently add menu items.
7. Category publication remains owned by
   `product_categories.show_on_website`; presentation does not change it.
8. New visual or behavioral values require visible controls and round-trip
   persistence. Renderer-only category/name conditionals are forbidden.

## Canonical ownership matrix

| Capability | Owner | Human control | Operation | Main consumers | State |
|---|---|---|---|---|---|
| Product web publication | Product record plus public visibility policy | `Catálogo web > Productos` | Canonical `WebsiteService` product visibility commands | Catalog workspace, Preview, public grid, product detail | ✅ |
| Category publication/navigation availability | `product_categories.show_on_website` | `Catálogo web > Categorías > Publicación` | Canonical category visibility operation | Filters, destinations, mega menu eligibility | ✅ |
| Homepage featured products | Canonical `featured_products` configuration | `Catálogo web > Portada` | Featured-product service | Product blocks configured with the featured source | ✅ |
| Catalog/category collection presentation | `WebsiteCatalogPresentation`, keyed by canonical root owner or stable category ID | `Catálogo web > Categorías > Presentación` | Typed `WebsiteService` save/remove/reload boundary with an explicit local draft | Edit, Preview and public collection renderer | ✅ |
| Category/product destinations | `WebsiteDestination` plus the presentation registry's current slug/aliases | CTA/link editor, presentation aliases and `Estructura > Destinos y enlaces` | Shared parse/build/normalize/alias-resolution helpers | Blocks, menus, mega menu, breadcrumbs, router, snapshots and redirects | ✅ |
| Header and mega-menu hierarchy | `website_navigation` | `Estructura > Navegación y menús`, including saved `megamenu` presentation | Navigation service | Desktop hover/click/keyboard, mobile navigation and destination audit | ✅ |
| Global storefront appearance | `website_settings` theme values | `Tema` and site settings | Global website save flow through `WebsiteThemeBuilder` | Header, footer, blocks, catalog, detail, cart and checkout | ✅ for the implemented commerce surfaces |
| Professional catalog facets | Public catalog eligibility plus stable product/category/brand facts | `Catálogo web > Categorías > Presentación` ordered facet controls | Typed `WebsiteCatalogQuery` and additive public facet RPCs | Edit, Preview, public catalog, direct links and browser history | 🟡 |
| Category/root SEO and discovery | `WebsiteCatalogPresentation` SEO values, current slug, durable aliases and system route/indexability policy | `Catálogo web > Categorías > Presentación > SEO y compartir` plus visible route-alias controls | Typed save/remove/reload, collision validation, automatic previous-slug preservation and restrictive runtime SEO projection | Runtime metadata/canonicalization, crawler snapshots, sitemap and generated Firebase redirects | ✅ locally; deployment/browser proof pending |
| Merchant/Search product projection | Product owner plus effective public eligibility, price, availability and active linked brand | Product `Tienda Online > SEO / Google Merchant` and website SEO settings | `PublicCommerceProductProjection` and the equivalent shared TypeScript projection | Visible landing, initial HTML, JSON-LD, snapshots, Merchant, cart and checkout | 🟡 until deployed-feed/browser equality proof |

## Completed implementation

### 1. Catalog management workspace redesign

- ✅ `Productos`, `Categorías` and `Portada` have distinct responsibilities.
- ✅ Product-list category filters no longer mutate category publication.
- ✅ Compact publication totals and a progressive detailed breakdown restore
  the important catalog counts without occupying most of the viewport.
- ✅ Public rules and advanced filters use progressive disclosure.
- ✅ The primary result action is a filled **Publicar** action; hide/replace
  alternatives remain in the split dropdown.
- ✅ Every bulk result action opens a scoped confirmation dialog before writing.
- ✅ Rows separate stored **Marcado web** intent from effective **Estado**.
- ✅ Effective statuses reuse the Jobs-table operational badge language.
- ✅ A product marked for web but blocked by a public rule keeps its intent
  visible without falsely appearing published.
- ✅ Product editing opens the canonical product form inline at the website
  section and refreshes the catalog projection after save.

Primary implementation:

- `lib/modules/website/pages/product_website_visibility_page.dart`
- `lib/modules/inventory/widgets/product_editor_dialog.dart`
- `lib/modules/inventory/pages/product_form_page.dart`
- `lib/modules/website/pages/featured_products_page.dart`

### 2. Typed category collection presentation foundation

- ✅ A versioned `WebsiteCatalogPresentationRegistry` is persisted in the
  existing tenant-scoped website-settings family.
- ✅ Presentations are keyed by stable category ID rather than display name.
- ✅ `/productos` and `/servicios` are visible reserved owners in the same
  registry; they do not masquerade as categories or duplicate CMS pages.
- ✅ Duplicate public slugs are rejected by the canonical save operation.
- ✅ Blank title, description and image overrides inherit the real category
  values instead of manufacturing hidden content.
- ✅ The workspace can select a real category, edit the presentation, preview
  real products, save and remove/reset the override.
- ✅ Existing controls cover clean slug, hero image, eyebrow, title,
  description, hero height, alignment, overlay, breadcrumbs, subcategories,
  grid density and the currently supported facets.
- ✅ Root catalog controls expose the durable facet order and grid density used
  by Edit, Preview and public rendering instead of relying on hidden defaults.
- ✅ Root and category owners expose search title, meta description, social
  image through the shared media picker and an explicit allow-indexing
  restriction. Blank values inherit canonical category/site content.
- ✅ The workspace distinguishes inherited, saved, dirty and pending-reset
  states. Selection changes protect dirty drafts; reset is staged until save;
  discard restores the loaded baseline; reload reads the persisted registry.
- ✅ The save/remove read-modify-write refreshes the registry first, preventing
  a directly opened workspace from overwriting entries absent from a stale
  service cache.

Primary implementation:

- `lib/modules/website/models/website_catalog_presentation.dart`
- `lib/modules/website/services/website_service.dart`
- `lib/modules/website/pages/product_website_visibility_page.dart`

### 3. Clean category routes and typed destinations

- ✅ Product and service collections support clean canonical routes:
  `/productos/categoria/:slug` and `/servicios/categoria/:slug`.
- ✅ Changing a saved slug preserves the previous value as an
  editor-visible/editable/removable alias for both product and service
  collection routes.
- ✅ Current slugs and aliases share one collision-validated namespace;
  ambiguous imported claims and duplicate legacy leaf names fail closed.
- ✅ Runtime alias navigation replaces the old URL with the clean canonical;
  generated alias snapshots use `noindex,follow`, stay out of the sitemap and
  feed exact Firebase 301 redirect entries without deploying them from Edit.
- ✅ ERP-mounted Edit/Preview routes use the same destination under `/tienda`.
- ✅ Legacy category query links remain readable.
- ✅ Newly edited typed destinations can write clean routes and preserve
  supported search/product-type filters.
- ✅ Category routes are registered before dynamic product-detail routes, so
  `categoria` cannot be interpreted as a product SKU.
- ✅ Product URLs retain readable slug plus stable SKU identity.

Primary implementation:

- `lib/modules/website/models/website_destination.dart`
- `lib/modules/website/widgets/website_link_value_editor.dart`
- `lib/public_store/utils/product_url.dart`
- `lib/shared/routes/app_router.dart`

### 4. First professional collection-page renderer

- ✅ The category hero is full width; it is not a floating card with white
  gutters.
- ✅ Breadcrumb and optional subcategory navigation render below the hero.
- ✅ The base category is page context rather than a removable fake filter.
- ✅ The main grid uses the real category query and current public eligibility
  rules.
- ✅ The presentation controls grid density and supported facet visibility.
- ✅ Invalid category slugs produce an explicit unavailable state.
- ✅ Stale requests are token-guarded so an older category response cannot
  repaint the latest route.
- ✅ Desktop filter rail and mobile filter/sort sheets share the same state.
- ✅ Root `/productos` and `/servicios` filters and grid density resolve from
  the same editor-owned presentation registry as category collections.

Primary implementation:

- `lib/public_store/pages/product_catalog_page.dart`
- `lib/public_store/services/public_inventory_service.dart`

### 5. Preview parity and product-detail navigation

- ✅ Edit mode may inspect the complete editable inventory.
- ✅ Preview now reloads the public query instead of retaining the editable
  in-memory result set.
- ✅ Preview category counts and products therefore reflect Catálogo web
  publication plus the current public rules.
- ✅ Product cards open the canonical product detail route inside the ERP.
- ✅ Product detail loads by stable SKU and its category breadcrumb returns to
  the clean collection route without duplicated Navigator keys.
- ✅ Edit/Preview keep the complete routed `StatefulNavigationShell` ancestry
  stable during mode transitions; ERP route changes bypass the body
  `AnimatedSwitcher` that could otherwise retain two copies of its branch
  Navigator keys.
- ✅ The catalog availability row avoids the detached Ink decoration that was
  triggering a render assertion during Preview transitions.
- ✅ Debug-only traces expose mode transitions, category resolution, public
  request parameters, counts and responses.

Latest runtime evidence for Cámaras:

| Step | Observed result |
|---|---|
| Edit category collection | 131 editable Cámara products |
| Switch to Preview | `RELOAD_FOR_MODE` emitted |
| Canonical public request | Stable Cámara category UUID plus public policy |
| Preview response | 20 loaded, 22 eligible total |
| Public count breakdown | 547 total public products, 22 Cámaras |
| Open first product | Canonical detail loaded by SKU |
| Category breadcrumb | Returned to Cámaras with 22 products and Preview retained |
| Runtime regression found later | A duplicate `LabeledGlobalKey<NavigatorState>` was reproduced while the same routed shell was remounted across Edit/Preview |
| Current regression result | A real `StatefulShellRoute` widget flow now passes Edit → Preview, `push` to `/tienda/productos/categoria/camaras`, back, Preview → Edit, exit to normal and `/tienda/productos` → `/tienda` → `/tienda/productos` without duplicate Navigator/Hero keys |

Primary implementation:

- `lib/public_store/pages/product_catalog_page.dart`
- `lib/public_store/pages/product_detail_page.dart`
- `lib/public_store/widgets/public_store_layout.dart`
- `lib/public_store/utils/public_store_tenant_resolver.dart`

### 6. Connected navigation consumers

- ✅ Product-detail breadcrumbs use the canonical category destination.
- ✅ The mega menu resolves category destinations through the shared route
  model instead of category-specific hardcoded URLs.
- ✅ A saved `website_navigation.cssClass = megamenu` selects the desktop
  mega-menu presentation; the renderer does not infer it from a category name.
- ✅ Desktop interaction supports hover intent with a pointer bridge, click,
  focus, Enter/Space, Arrow Down and Escape; mobile uses the same saved
  hierarchy in its compact navigation surface.
- ✅ Renderer-created `Inicio`/`Productos`/`Servicios` items are not a competing
  navigation owner when the saved navigation is empty.
- ✅ Destination audit understands stored presentation slugs and category
  owners, including historical aliases.

Primary implementation:

- `lib/public_store/widgets/mega_menu.dart`
- `lib/modules/website/services/website_destination_audit_service.dart`
- `lib/modules/website/pages/website_destination_management_page.dart`

### 7. Typed professional-facet foundation

- ✅ Brand and effective public price are the first honest secondary facets;
  production coverage was audited before exposing them.
- ✅ Brand values use stable `brand_id` identity, including valid global brand
  rows, instead of deriving a brand from product names.
- ✅ Price filtering uses the same effective public price shown to customers.
- ✅ A typed `WebsiteCatalogQuery` owns search, type, brand, price,
  availability, sorting and pagination parameters with deterministic encoding.
- ✅ Missing facet configuration inherits the established defaults, while an
  explicit empty list remains a deliberate “show no facets” choice.
- ✅ The presentation workspace separates visible ordered facets from disabled
  available facets and supports drag, move, enable and remove operations.
- ✅ The renderer consumes the saved facet order and applies brand/price to the
  complete public result before count and pagination.
- ✅ Direct/back-forward pagination preserves the page encoded in the URL;
  stale out-of-range pages probe the real total and clamp to the last valid
  page instead of producing a false zero-product catalog.
- ✅ Brand IDs are validated as canonical UUIDs before reaching the UUID-array
  RPC contract.
- ✅ Category option counts, including hidden descendant roll-up and an
  uncategorized-aware `Todas` total, are derived from the same secondary-filter
  universe as the result rather than unrelated whole-catalog counts.
- ✅ RPC/transport failures render an explicit professional retry state and can
  no longer masquerade as a legitimate zero-result page.
- ✅ Additive `get_public_products_faceted_v1` and
  `get_public_product_facets_v1` wrappers plus pgTAP coverage are authored in a
  forward migration and mirrored in the canonical schema snapshot.
- ✅ The metadata wrapper derives summary, category, brand and price
  metadata from one canonical unpaged eligibility scan instead of repeating
  the reservation-aware base query for each facet family.
- ✅ Migration `20260722200000` is deployed and registered in production after
  an explicit authorization, a successful rollback probe, 52/52 pgTAP,
  production-derived benchmark, two independent reviews and exact live
  function/ACL/hash/result read-back.

Primary implementation:

- `lib/modules/website/models/website_catalog_query.dart`
- `lib/modules/website/models/website_catalog_presentation.dart`
- `lib/modules/website/pages/product_website_visibility_page.dart`
- `lib/public_store/pages/product_catalog_page.dart`
- `lib/public_store/services/public_inventory_service.dart`
- `supabase/migrations/20260722200000_add_public_catalog_facets.sql`
- `supabase/tests/public_catalog_facets.sql`

### 8. Google Merchant and Search architectural gate

- ✅ The handoff and canonical surface registry now treat Merchant eligibility
  as a cross-cutting catalog contract, not a feed-only export.
- ✅ Brand, GTIN and manufacturer MPN remain explicit facts; SKU is not MPN,
  values are not inferred from names and unknown identifiers are not declared
  nonexistent.
- ✅ Linked brand resolution accepts only the active tenant-owned or active
  global brand row in live rendering, snapshots, Merchant feed and diagnostics;
  inactive/foreign rows cannot silently become public brand claims.
- ✅ `out_of_stock` is a valid Merchant availability value. It does not by
  itself make an otherwise eligible product fail; the landing page,
  structured data, feed and checkout must all report the same canonical
  reservation-aware state.
- ✅ Product/category routes, transient facet URLs, preview exclusion and
  pagination now have an explicit indexation contract.
- ✅ Runtime metadata projects clean routes as `index,follow`; catalog query
  state, Preview/Edit, ERP-mounted and transactional routes use
  `noindex,follow` and a clean canonical path.
- ✅ The forward image-readiness target is 500 × 500 pixels.
- 🟡 Product JSON-LD/feed availability and identifier semantics now share the
  typed projection, but deployed browser/feed value equality is not yet proven.
- ✅ Crawler snapshots and sitemap categories now come from active category
  IDs, publication, saved presentation and canonical product eligibility.
  Empty/hidden collection pages and transient/private URLs are excluded;
  product-title parsing no longer manufactures category slugs, wheel sizes or
  SEO families.
- ⬜ Flutter canvas output alone is not the completion gate. Initial semantic
  HTML must expose the same visible products, links, price, availability and
  structured data without bot-only or hidden parallel copy.

## Partially completed work

### Phase 0 — baseline and data contract: 🟡

Completed:

- Typed presentation model and stable category identity.
- Route helpers and focused unit/architecture tests.
- Native ERP runtime validation for the main Cámaras flow.

Still required:

- Automated baseline coverage for the real routed collection widget.
- Saved public-host/browser baseline, not only native ERP Preview.
- Explicit fixtures for root, nested, unpublished, empty and zero-eligible
  categories.

### Phase 1 — complete category presentation owner: 🟡

Completed controls:

- Slug, hero image/text, size, alignment, overlay, breadcrumbs,
  subcategories, grid density and supported facets.

Missing controls/domain values:

- Hero video.
- Image focal point/crop and responsive media variants.
- Explicit responsive presentation settings.
- Optional editorial section modules/blocks.
- Theme inheritance and explicit per-collection opt-out controls.
- Contextual **Editar presentación** handoff from the routed collection page.

Architecture closure still required:

- The presentation workspace is now deliberately classified as an immediate
  management operation with an isolated local draft. `Guardar cambios` is the
  only persistence boundary; `Descartar`, `Recargar`, staged reset and dirty
  selection protection are explicit. A future migration into the global
  canvas draft/history is optional only if it preserves these same semantics.

### Phase 2 — routes and destination integrity: 🟡

Completed:

- Clean route generation/parsing, legacy compatibility and shared consumers.
- Destination audit resolves category IDs, generated slugs, saved slugs and
  historical aliases.
- Previous saved slugs automatically become visible aliases; product and
  service alias routes resolve the stable owner, canonicalize at runtime and
  produce noindex snapshots plus generated 301 entries.

Still required:

- Audit the **effective eligible** product count, not merely products marked
  for web before public rules.
- Show presentation readiness, SEO readiness and every relevant category use
  in one clear destination record.
- Broaden typed secondary filters only after the public server query supports
  them across the complete paginated result set.
- Release-pipeline smoke for generated redirects: old product/service route →
  current route after a deliberate snapshot/Firebase deployment.

### Phase 3 — shared collection renderer: 🟡

Completed:

- One route-backed catalog renderer for Edit, Preview and public mode.
- Hero, breadcrumb, subcategory navigation, real grid, sort, pagination,
  loading and invalid-category handling.
- The management workspace and routed storefront now share
  `CatalogCollectionPresentationHeader` for hero/breadcrumb/subcategory
  geometry and `websiteCatalogGridMetrics` for responsive grid geometry.
- The management preview projects the saved facet order and actual eligible
  result count instead of maintaining a hero-only mockup.

Still required:

- Editor-owned optional editorial sections.
- Curated editorial product modules that remain visibly distinct from the
  query-backed main grid.
- A complete public-host parity pass after persistence/reload.
- More systematic removal of mode-specific geometry differences.

### Phase 4 — professional catalog/filter UX: 🟡

Completed:

- Category route context, search, availability, category navigation, sorting,
  pagination, desktop rail and mobile sheets.
- Server-backed brand identity and effective-price query contracts.
- One typed deterministic URL codec for the supported secondary facets, sort,
  page and page size, including legacy alias compatibility.
- Editor-controlled facet visibility and order with explicit enable/remove
  behavior.
- Ordered public facet rendering, compact active-filter removal and clear-all
  behavior.
- Immediate invalidation of obsolete requests and atomic product/facet snapshot
  commits.
- Route-authored page state survives direct navigation and browser history;
  user-authored filter changes still reset intentionally to page one.
- Published category navigation and hierarchical product membership are
  distinct: hidden active descendants can roll into a public ancestor, while
  hidden categories do not become routes or filter options unless the category
  owner publishes them.
- Missing RPC/network state is explicit and retryable, never a false empty
  result.

Still required:

- Exercise brand, price, availability, sorting and pagination together through
  the real app and browser history; the unlocked desktop pass already proved
  the production category counts and a saved category route.
- Add material, size/diameter, speed and other category-applicable facets only
  after real structured catalog coverage exists; parsing product titles is not
  an acceptable substitute.
- Explicit zero-eligible-product state and a distinct human-facing explanation
  for unpublished/hidden versus truly invalid category identity. Stable
  identity is now resolved against all active categories, but both cases still
  share one unavailable-state presentation.
- Automated back/forward coverage for every supported facet, sorting and
  pagination combination.

### Navigation and mega-menu design: 🟡

Completed:

- Canonical destination resolution and category hierarchy integration.
- Collection/detail links use the shared route model.
- Saved `website_navigation` presentation selects the mega menu; the renderer
  does not manufacture a category-specific navigation tree.
- Desktop hover intent, click, focus/keyboard opening and Escape dismissal are
  implemented and covered by focused widget/architecture tests.
- Mobile navigation consumes the same saved hierarchy and typed destinations.

Still required:

- Complete mobile visual acceptance against the current saved navigation and
  deep category trees. Desktop ERP/public activation, open-state rendering and
  `Componentes → Transmisión → Cadenas` navigation have passed.
- Screen-reader semantics/focus-order audit beyond the existing keyboard
  interaction tests.
- Verification that every header/footer/mega-menu variant uses the same
  current theme and destination readiness rules.

### Visual design and global theme parity: 🟡

Completed:

- Full-width collection hero, stronger collection hierarchy, improved product
  grid presentation and more professional spacing.
- `WebsiteThemeBuilder` projects the saved theme through one `ThemeData`.
- `PublicStoreSurfaceTheme` applies the same surface, border, readable
  foreground, typography and primary-action policy to product detail, cart and
  checkout without reintroducing a Viñabike-only palette.

Still required:

- Replace any remaining catalog-local fallback geometry with shared tokens or
  visible local overrides.
- Audit policy and lower-frequency public pages against the same theme.
- Validate high contrast, long titles, missing images and narrow/large
  breakpoints in the real unlocked app.

### Canonical product commerce projection: 🟡

Completed:

- Added a typed `PublicCommerceProductProjection` for product identity, public
  title/description, effective price/currency, sellable availability, ordered
  public images, verified brand/GTIN, explicit MPN and canonical category path.
- The precedence is now explicit and editor-owned: saved commerce override,
  then website override, then catalog value. Missing identifiers, brands and
  categories are omitted or reported; they are never inferred from SKU, title,
  retailer name or a generic category.
- Product detail content and Product/Offer JSON-LD, static product snapshots
  and no-JS fallback, cart/checkout mirrors, Merchant feed and Merchant
  diagnostics consume this contract. The feed no longer title-cases catalog
  copy, pads short descriptions or invents a brand/category.
- Linked-brand resolution is tenant-scoped and active-only across live,
  snapshot, feed and diagnostic consumers.
- `out_of_stock` remains an eligible Merchant availability value when every
  consumer agrees; it is not treated as a missing required field.
- Reservation-aware availability from the public catalog RPC remains the
  authoritative input before snapshots and Merchant eligibility are resolved.
- Dart runtime/deploy equality tests cover an eligible product and a
  deliberately ineligible product; equivalent Deno contract tests cover the
  feed projection and identifier rules.

Still required:

- Browser-level extraction that compares the rendered product heading,
  description, price and availability with initial HTML, hydrated JSON-LD,
  generated Merchant XML and the checkout request for the same real product.
- A production Merchant feed smoke read after deliberate deployment; no Edge
  Function was deployed in this slice.

## Pending agreed roadmap

### Phase 5 — category SEO and discovery: 🟡

Completed foundation:

- Published non-empty category snapshots and sitemap entries use stable
  category identity, saved presentation slugs/content and canonical public
  eligibility.
- Product breadcrumbs/JSON-LD use the canonical published category path.
- Transient/private URLs stay out of sitemap output, and runtime metadata
  projects deterministic `noindex,follow` plus a clean canonical.
- Category and product SEO copy no longer infers technical facts from names.
- Root/category controls now round-trip search title, meta description, social
  image and allow-indexing through the same presentation draft/save/reset
  boundary.
- Runtime category/root metadata consumes those values. The indexability
  control is restrictive only: unpublished/invalid, empty, filtered,
  ERP-mounted and Edit/Preview routes remain `noindex,follow`, and stale social
  metadata is removed when no effective image exists.
- The generic page metadata updater yields root/category and product-detail
  routes—including `/tienda/...` mounts—to their canonical dynamic owners.
- Category slug changes preserve the previous saved route as a visible,
  removable alias. Current slugs and aliases are collision-validated together;
  ambiguous legacy registries and duplicate leaf-name routes fail closed.
- Runtime replaces a resolved alias with the current canonical route. Generated
  alias snapshots use `noindex,follow` plus that canonical, stay out of the
  sitemap and feed the exact Firebase 301 redirect manifest.

Still required:

- Optional editorial SEO copy.
- Breadcrumb and collection structured data.
- Semantic treatment for genuinely useful pagination pages if they are later
  promoted for discovery. Until then page/search/sort/facet state remains
  deterministically `noindex,follow`, clean-canonical and sitemap-excluded.
- Semantic initial HTML with real `<a href>` product/category links from the
  same public eligibility projection; no canvas-only or bot-only substitute.
- SEO readiness in destination audit.
- Browser/deploy equality gate across visible product landing, initial HTML,
  Product/Offer JSON-LD, generated Merchant XML and checkout for one real
  eligible and one real ineligible product. Typed/runtime equality is covered.

### Phase 6 — migration and compatibility completion: ⬜

- Exhaustive compatibility tests for legacy category links with combined
  filters.
- Deploy and smoke the generated product/service alias redirects before
  declaring external slug compatibility active.
- Verification that category title/image edits preserve publication,
  navigation and presentation ownership.
- Controlled compatibility cleanup after real usage confirms the new routes.

### Phase 7 — verification and rollout: ⬜

- Widget tests for presentation controls, routed product loading, filter
  interaction, responsive layout and save/reload round trip.
- Browser integration flow:
  menu/CTA → collection → filters → product → back.
- Run the same flow in Edit, Preview and standalone public mode.
- Desktop and mobile coverage.
- Root, nested, unpublished, empty and zero-eligible categories.
- Combined category plus search/brand destinations when those facets exist.
- Accessibility checks for keyboard, focus, semantics and contrast.
- Controlled rollout/compatibility boundary if required.

## Suggested professional enhancements

These are proposals, not hidden implementation commitments. Each one would
need its own Owner/Control/Operation/Consumers analysis before development.

| Suggestion | Customer value | Required editor/configuration capability |
|---|---|---|
| Buying-path or subcategory cards below the hero | Helps customers choose by use case before filtering | Ordered category-navigation module using real category destinations |
| Reorderable facet groups with category-specific applicability | Shows only useful filters for each collection | Typed facet registry plus server query support and ordering control |
| Sticky desktop result toolbar | Keeps count, sort and filter access visible on long grids | Theme/layout option in collection presentation |
| Product quick view | Faster comparison without losing collection context | Shared product quick-view surface using canonical product data/actions |
| Editorial guide modules | Enables size, compatibility or buying guides | Registered reusable blocks attached to collection presentation |
| Responsive hero art direction | Better image composition on desktop and mobile | Shared media focal point, crop and responsive variant controls |
| Collection merchandising slots | Allows promoted products without corrupting the main query | Explicit curated module with real product IDs and visible labeling |
| Filter/search analytics | Shows which collections and filters help customers | Privacy-aware analytics settings and typed events |
| Collection quality/readiness score | Makes missing hero, SEO or empty results actionable | Read-only audit derived from canonical owners, not a second state system |

## Known architecture risks to resolve

These are not merely optional polish items. They are areas where the current
slice could violate the final CMS parity contract if left as-is.

| Risk | Current symptom | Required resolution |
|---|---|---|
| Category presentation persistence boundary | The management workspace is an explicit immediate management operation with an isolated draft rather than the open page/canvas draft | Preserve the documented Save/Discard/Reload/reset semantics and add full reopen-control round-trip coverage |
| Duplicate collection preview renderer | The category-presentation workspace constructs a simplified hero/product preview separate from `ProductCatalogPage` | Reuse the shared renderer/components or add parity tests that make drift impossible |
| Residual theme bypasses | Shared theme projection now reaches catalog/detail/cart/checkout, but local fallback geometry and low-frequency pages may still drift | Keep moving durable appearance into global theme tokens or visible collection overrides and prove it visually |
| Hidden category state messaging | Stable identity and hierarchy now load independently from navigation publication, but hidden and invalid routes still share one generic unavailable state | Render distinct invalid, hidden and empty explanations without exposing hidden categories as public destinations |
| Destination count mismatch | The management workspace previously undercounted three component-owned sets because a >1000-row hydration was partial | The workspace now batches the canonical reservation-aware availability RPC; keep the destination audit on that same effective eligibility contract |
| Slug-change deployment verification | Durable aliases, noindex snapshots and Firebase 301 entries are generated from the canonical registry, but this implementation task deliberately does not deploy them | Run the snapshot generator in the release pipeline, inspect the generated alias manifest and perform direct old-route → current-route smoke checks before deployment |
| Regression coverage gap | Most collection checks are unit/source-contract tests and one native flow | Add routed widget and browser E2E coverage across all required modes and states |
| Facet production acceptance | The independently reviewed one-scan additive wrappers are deployed, registered and read back without replacing the reservation-aware base owner; category count/result smoke passed in unlocked Preview | Complete combined brand/price/history and responsive interaction smoke |
| Commerce projection browser proof | Initial HTML, runtime landing, JSON-LD, Merchant and checkout now share a typed product projection, but no browser/deployed-feed test extracts and compares one real product through every surface yet | Add the real eligible/ineligible browser plus generated-XML equality gate and dedicated category SEO controls |

## Verification completed in this snapshot

| Verification | Result |
|---|---|
| Flutter analyzer for the integrated Website Builder/storefront selection | No errors or warnings; informational diagnostics remain outside this feature gate |
| Integrated presentation/query/Merchant/indexation/navigation/theme/Navigator suite | 152 tests passed after the canonical availability and mega-menu closeout |
| Focused product robots, commerce projection and Merchant identity parity suite | 22 tests passed after the P1 corrections |
| Deno Merchant feed/projection contracts | 11 tests passed, including valid `out_of_stock` and explicit identifier behavior |
| Native ERP Edit → Preview transition | Passed |
| Preview public catalog eligibility for Cámaras | Passed, 22 effective products |
| Preview product detail navigation | Passed |
| Product-detail category breadcrumb/back | Passed |
| Catalog management desktop UI | Passed: compact overview, filters, public rules, publication confirmation and inline web-product editor |
| Public `Componentes` mega menu | Passed after enabling the existing editor-owned `Panel ancho` control: full-width editorial panel, `Transmisión → Cadenas` destination, light/dark contrast coverage, and geometry derived from the actual rendered header in standalone and ERP-hosted overlays |
| Management/public product count parity | Fixed: the workspace now batches `get_product_available_quantities` for all 1,654 rows; focused coverage proves the three component-owned sets that caused `544` versus `547` |
| Duplicate Navigator/Hero key widget regression | Passed across CMS mode changes, exact Preview category push/back and ERP shell route changes |
| Category snapshot generation against production-derived reads | 547 canonical products and exactly 4 public non-empty category pages; no transient/private sitemap URLs or inferred wheel-size SEO; generated output was not deployed |
| Active linked-brand parity | Live product reads, snapshots, Merchant feed and diagnostics use tenant/global scope plus `is_active=true`; inactive/foreign fixtures are covered |
| New facet migration/pgTAP | 52/52 pgTAP passed on a fresh production-derived clone; the one-scan wrapper and core mirror are byte-identical, two independent reviews approved it, the production read-only benchmark passed (metadata median 211.992 ms; combined median 435.610 ms), and migration `20260722200000` is deployed, registered and hash/ACL/result verified |
| Final current visual acceptance | Desktop slice passed for management, Preview category/detail and standalone-public mega-menu navigation; mobile/tablet and the complete routed E2E matrix remain pending |

## Verification still required before calling the refactor complete

- Standalone public storefront after a real save/reload.
- Mobile and tablet visual/interactivity pass.
- Widget and browser end-to-end regression coverage.
- Category presentation save → reload → reopen-control round trip.
- Nested, unpublished, empty and zero-eligible category behavior.
- Real-app mobile/accessibility acceptance of the mega menu and the latest
  category route aliases; desktop click/open/navigation already passed.
- Visual theme parity across catalog, detail, cart and checkout; code and
  widget contracts are present, but the final real-app pass is not.
- Browser/deployed-feed extraction of the initial
  HTML/JSON-LD/Merchant/checkout value-equality contract.

## Recommended execution order

1. **Finish Phase 4 acceptance:** exercise the deployed one-scan facets in the
   unlocked real app across Edit, Preview, standalone public and responsive
   breakpoints.
2. **Prove the Merchant/Search projection in the browser and generated feed:**
   the typed consumers are aligned; extract one real eligible and ineligible
   product end to end, then perform a deliberate deployed-feed smoke check.
3. **Finish presentation/media controls:** focal point, responsive media,
   theme inheritance and optional editorial modules.
4. **Complete the remaining Phase 5 discovery layer:** collection/breadcrumb
   structured data and semantic category product links, using the existing
   editor-owned SEO values and aliases.
5. **Complete destination/readiness audit** using effective public eligibility.
6. **Remove remaining local visual hardcoding** by extending global theme
   tokens and visible overrides.
7. **Finish Phase 7 browser coverage** and validate standalone public,
   desktop and mobile flows.
8. **Perform compatibility rollout** and only then declare the refactor
   complete.

## Final completion gate

The refactor can be marked complete only when every durable category/catalog
value is visible and editable, the public result comes from the canonical
query, typed destinations survive save/reload/navigation, Edit/Preview/public
and desktop/mobile agree, SEO/discovery are connected, transient facets obey
the indexation contract, and at least one eligible plus one ineligible product
match end to end across the visible landing, initial HTML, JSON-LD, Merchant
and checkout. The complete route flow must be protected by automated
regression coverage.
