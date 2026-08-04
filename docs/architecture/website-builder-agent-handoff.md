# Website Builder Agent Handoff and Evolution Plan

**Status:** Mandatory context for every AI agent changing the Website Builder,
public storefront, campaigns, catalog routes, category presentation, filters,
SEO, navigation, or website configuration  
**Last updated:** 2026-07-29
**Normative contract:**
[`website-editor-contract.md`](website-editor-contract.md)  
**Surface registry:**
[`canonical-ui-surfaces.md`](canonical-ui-surfaces.md)
**Progressive architecture tracker:**
[`WEBSITE_BUILDER_PROGRESSIVE_ARCHITECTURE_REFACTOR_PLAN_2026-07-29.md`](../development/WEBSITE_BUILDER_PROGRESSIVE_ARCHITECTURE_REFACTOR_PLAN_2026-07-29.md)

This document is the short, operational handoff from the Website Builder
refactor and the incidents that motivated it. It explains what “make the
change as if a normal user did it in the editor” means, which system owns each
kind of state, what failures must not recur, and how to evolve the storefront
without creating a second hardcoded website beside the CMS.

It does not require an agent to perform slow literal mouse clicks. Automation,
typed JSON, provider calls, seed helpers, and repository scripts are welcome
when they use the exact canonical model and operation that the editor uses.
The requirement is **action equivalence**, not physical input equivalence.

## The non-negotiable invariant

Every durable website result created by an agent must be explainable entirely
by state that a normal administrator can reopen, inspect, change, remove, save,
preview, and publish through the Website Builder.

```text
agent request
  -> existing editor capability, or a reusable capability added first
  -> canonical owner and validated persisted value
  -> visible editor/configuration control
  -> shared staged/save operation
  -> shared Edit / Preview / public consumer
  -> reload returns the same value to the same control
```

The public renderer is never an independent place to “make the website look
right.” It is a consumer of editor-owned state.

Every change must have all four parts:

1. **Owner:** one canonical entity owns the meaning.
2. **Control:** the value is discoverable and editable in the proper UI.
3. **Operation:** editor actions and agent automation use the same defaults,
   validation, persisted schema, and durable save/publication invariants;
   automation acting on a live draft also uses normal staging/history.
4. **Consumers:** Edit, Preview, public rendering, navigation audits, and other
   affected surfaces resolve the same value.

If one part is absent, the feature or content operation is incomplete.

## What action equivalence permits and forbids

| Acceptable automation | Unacceptable shortcut |
|---|---|
| Calling the same provider/service command used by an editor control | Adding a renderer-only conditional for one campaign/category |
| Creating canonical block/slide/Canvas JSON that validates against the same schema, defaults, and controls | Inventing hidden JSON keys that no control can display or edit |
| Using a seed/helper for initial content, then verifying complete UI round-trip | Keeping campaign content in a Dart constant, fixture, CSS rule, or agent-only seed read at runtime |
| Uploading an asset through the normal media service and selecting its stored record | Referencing a local, temporary, or raw external URL that the media picker cannot own |
| Selecting a typed page/category/product/catalog-filter destination | Hand-authoring internal routes or query strings inside a banner |
| Adding a missing reusable schema/control/consumer capability before using it | Styling one instance in renderer code because the editor lacks the control |
| Using migrations for schema evolution and explicit compatibility backfills | Using direct SQL as the normal content-authoring path |

A hidden seed is acceptable only as an efficient authoring mechanism. Once it
runs, no hidden seed-specific runtime branch may be necessary, and the result
must be indistinguishable from data created through the visible editor. Initial
seed/import state created outside an open draft does not need synthetic undo
history, but it must use the canonical normalized schema/writer and pass the
same reload, control, renderer, and publication checks.

### The round-trip proof

For every value an agent creates or changes:

1. Open the real routed surface in Edit mode.
2. Select the owning block, slide, layer, page, category, product, navigation
   item, or theme setting.
3. Confirm the corresponding control shows the exact value.
4. Change a reversible value through that control and confirm the draft.
5. Compare Edit content with Preview.
6. Save through the global save path when persistence is authorized.
7. Reload and confirm the control and rendering reconstruct the same state.
8. Exercise the destination or product query rather than only inspecting its
   serialized value.

## One CMS with two connected control planes

The visual editor and the top management/configuration workspaces are not
separate applications. They are two surfaces over one website model.

| Control plane | Canonical responsibility |
|---|---|
| Page canvas and right inspector | Blocks, slides, Canvas layers, copy, media usage, CTA usage, local presentation, geometry, ordering, responsive behavior |
| Management/configuration workspaces | Pages, catalog publication, categories, featured products, typed destinations, navigation hierarchy, site theme, header/footer, SEO, integrations, publication state |

A visual request often crosses both planes. A category campaign, for example,
is not complete after creating a slide. The category must be a valid public
catalog owner, its eligible products must come from the canonical catalog
query, the CTA must store a typed category/filter destination, optional menu
placement must use navigation management, and the final routed catalog must be
verified.

Contextual shortcuts may open a canonical management workspace. They must not
create a second copy of its settings inside a block inspector.

## Canonical ownership map

| Meaning | Canonical owner / API | Editor surface |
|---|---|---|
| CMS page identity, slug, SEO and publication | `website_pages` through `WebsiteService` | `Estructura > Páginas` |
| Page composition | `website_blocks`, registered block schemas, `WebsitePageComposition`, and `PageComposition` | Visual page editor + right inspector |
| Typed document, scoped drafts, selection and undo/redo | `WebsiteEditModeProvider` and `WebsiteEditorDocument` | Editor shell `Guardar` / `Descartar` |
| Global save protocol | `WebsiteSaveCoordinator`; blocks use transactional `replace_page_blocks` | Editor shell `Guardar` |
| Header/footer navigation hierarchy | `website_navigation` | `Estructura > Navegación y menús` |
| Typed links and filtered catalog destinations | `WebsiteDestination`, `WebsiteLinkValueEditor` | CTA controls and `Estructura > Destinos y enlaces` |
| CTA label, destination and presentation | `WebsiteActionValue`, `WebsiteActionEditor`, `WebsiteActionButton` | Every CTA-capable block/layer |
| Product/category publication and eligibility | Real inventory/category records plus website visibility policy | `Catálogo web` |
| Featured products | Canonical featured-product configuration | `Catálogo web > Productos destacados` |
| Root/category collection presentation, SEO and route aliases | `WebsiteCatalogPresentationRegistry`, keyed by reserved root owner or stable category ID | `Catálogo web > Categorías > Presentación` |
| Public catalog facet state | `WebsiteCatalogQuery` plus the canonical public eligibility/availability query | Ordered facet controls in category/root presentation and the routed catalog |
| Public commerce identity and offer projection | Product/category owners through `PublicCommerceProductProjection` and its equivalent shared TypeScript contract | Product `Tienda Online` controls plus catalog/SEO readiness surfaces |
| Site SEO identity and canonical origin | Normalized `website_settings`; `store_url` is canonical and `seo_canonical_url` is a compatibility mirror | Site settings |
| Cross-owner SEO diagnosis | Read-only `WebsiteSeoCenterProjection` with separate app, deployed-build and Google evidence | `/website/seo`, with handoffs to the owning site/page/product/category surface |
| Global fonts, colors, background, buttons and header/footer tokens | `PublicStoreLayout` resolves saved/staged `website_settings` once into immutable `WebsiteResolvedTheme`; `WebsiteThemeBuilder` projects it | `Tema` / site settings |
| Website media | shared website media service and picker | Biblioteca / Productos / Subir / URL avanzada |
| Layered campaign composition | `CanvasBlock`, `_CanvasBlockControls`, registered Canvas element factory | Canvas inline controls + inspector |
| Public catalog products and counts | `PublicInventoryService` and current public visibility/availability rules | `ProductCatalogPage` and other catalog consumers |

When implementation names evolve, preserve the ownership boundary. Update
this table, the engineering contract, and the canonical surface registry in
the same task.

Standalone text and button are converged renderer families. The text block
resolves one `WebsiteTextBlockPresentation` and responsive max-width frame for
all modes; Edit injects only its inline text/format/width presenter.
`WebsiteActionButton` likewise owns button presentation while Edit injects only
the inline label presenter. Its visible `style` alias and the canonical
`actions` variant must remain synchronized. Do not restore either bespoke
editable renderer.

Resolved 2026-07-30: all 24 registered renderer families converged on the
shared content renderer with geometric parity coverage; every bespoke
`_buildEditableXxx` builder was deleted with its batch (4A simples, 4B
colecciones, 4C hero/carousel, 4D canvas). Edit injects only presenters,
typed edit bindings and chrome. The storefront mode is a single provider-owned
FSM (`public | preview | edit`); the URL is an entry command plus write-through
projection and can never compete as a second owner. Do not recreate a bespoke
editable renderer, a runtime migration flag, or a URL/provider mode
synchronizer.

Resolved 2026-08-02: global storefront theme values now have one immutable
runtime owner, `WebsiteResolvedTheme`. The shell resolves saved/staged values;
Home, Policy, Dynamic and Contact consume the published extension, the `Tema`
control reopens against the same pending-aware reader, and
`WebsiteThemeBuilder` projects the exact owner value into `ThemeData`. Do not
restore page-local theme readers, parsers or fallback palettes.

## Rules by capability

### Pages, routes, destinations, and navigation

- A CMS page is created and configured through the page owner. Do not add a
  GoRouter branch and call that a completed page feature.
- A product category and a product already have canonical destinations. Do not
  create duplicate `website_pages` rows solely to produce links for them.
- Internal links are typed references to Page, Category, Product, System, or
  Catalog Filters. Raw internal route text is advanced compatibility state,
  not the primary model.
- `WebsiteDestination` owns normalization. Renderers, blocks, menus, and agents
  must not each build their own `/tienda`, slug, or query-string variants.
- `website_navigation` alone owns header/footer placement, hierarchy, order,
  visibility, and mega-menu presentation. A CTA does not automatically become
  a navigation item.
- The editor page selector must navigate the real routed surface while keeping
  the correct page/draft context. System pages such as `/productos` must load
  their real data in editor mode.
- Destination integrity must remain visible in `Estructura > Destinos y
  enlaces`, including unresolved, unpublished, empty, or incompatible targets.

### Catalog, categories, products, and filters

- `Catálogo web` is the human owner of website product/category inclusion.
  Product forms may expose relevant shortcuts, but they are not a second
  publication system.
- Public grids, search, category counts, campaign products, and product pickers
  must consume the same public eligibility policy. Never copy a product list
  into block JSON to simulate a category query.
- A curated manual product selection is valid only when the editor explicitly
  presents it as such and stores real product IDs.
- Category filters use stable category identity. A display name is not a safe
  relational key, and a search term is not a category substitute.
- `product_categories.show_on_website` owns whether a category is a public
  destination/navigation option. It does not erase active descendants from a
  published ancestor's membership; only the separate
  `requireVisibleCategory` public rule may restrict product eligibility by
  that publication set.
- Combined destinations such as Category + brand/search/type must be created
  by the typed catalog-filter editor and reopen with every filter visible.
- Route context and user-added facets are different. A category landing page
  may present “Cámaras” as its page context/breadcrumb instead of an ugly
  removable chip; secondary user filters remain visible and removable.
- Changing a product/category title or image must not silently change its
  publication state, destination identity, navigation placement, or SEO owner.

### Google Merchant and Search foundation

Google Merchant eligibility is a cross-cutting catalog contract, not a feed
export added after the storefront is finished. Any catalog, product-route,
price, availability, image, SEO, or publication change must preserve one
canonical projection across the visible landing page, initial semantic HTML,
Product/Offer JSON-LD, Merchant feed, sitemap and checkout.

- Product identity is stable. Merchant links use the same clean, direct,
  purchasable product URL as the storefront and its absolute canonical.
- Title, description, product image, effective price/currency and canonical
  availability must agree between product owner, landing page, structured
  data, feed and checkout. A product grid is not a valid Merchant landing.
- `out_of_stock` is a valid Merchant availability value and does not by itself
  make an otherwise eligible product fail. The reservation-aware value must
  agree on the landing page, Product/Offer JSON-LD, feed and checkout.
- Brand, GTIN and manufacturer MPN are verified product facts. Never infer
  them from names, use the retailer SKU as MPN, invent a GTIN, or assert
  `identifier_exists=false` merely because local fields are empty.
- A linked brand is usable only when its canonical row is active and belongs to
  the tenant or the approved global scope. Live rendering, snapshots, feed and
  diagnostics must resolve that same row and must not fall back to an inactive
  or foreign text claim.
- Web publication, effective public eligibility, Merchant eligibility,
  submitted status and Google approval/rejection are distinct visible states.
- The SEO center preserves three independent evidence planes: current app
  eligibility, dated deployed-build evidence and dated Google/Search Console
  evidence. A successful build or submitted sitemap is not URL-indexing proof,
  and missing evidence must stay unknown.
- Product app eligibility comes from the canonical public catalog RPC under the
  saved visibility/stock/image/category policy. Internal `is_active`,
  `is_published` or lifecycle fields cannot widen that set.
- Product runtime metadata, product-form preview and generated static snapshots
  resolve the same owner overrides, templates, locality and explicit search
  phrases. Search phrases may enrich generated customer-facing copy but never
  override explicit copy or become a hidden keyword list.
- Category/product pages intended for discovery need semantic HTML containing
  real `<a href>` links. Flutter canvas output alone is not an indexable HTML
  contract; the existing public snapshot/prerender pipeline must be extended
  from the same owners rather than becoming a second hidden content source.
- Clean category pages and each useful pagination page can be indexable with a
  self-referencing canonical. Transient search, sort and facet combinations
  use deterministic parameters, stay out of the sitemap and normally project
  `noindex,follow`; a valuable combination becomes a real editor-owned
  collection instead of an implicitly indexable filter URL.
- Runtime metadata must repeat that policy (`index,follow` for clean public
  routes; `noindex,follow` plus a clean canonical for transient/private state),
  while the initial semantic HTML remains the authoritative completion gate.
- Empty public categories are not indexed. Preview/Edit surfaces are private,
  absent from Merchant/sitemap and never treated as evidence of public HTML.
- Static-policy fallback content cannot invent publication: only a published
  `website_pages` owner can enter static trust, no-JavaScript navigation,
  structured policy references and the sitemap. Legacy free-form policy URL
  settings are not independent route owners. Private routes such as cart,
  checkout, account, order, auth and editor/ERP surfaces also require
  response-level `X-Robots-Tag` protection.
- `store_url` is one clean HTTPS origin across the editor, runtime, static
  generator and Google integration. Credentials, paths, queries and fragments
  fail closed instead of being silently stripped by one consumer.
- Product image controls and readiness diagnostics should adopt 500 x 500 as
  the forward minimum now; Google announced enforcement from 2027-01-31.

Current primary references:

- [Merchant product data specification](https://support.google.com/merchants/answer/7052112?hl=en)
- [Merchant landing-page requirements](https://support.google.com/merchants/answer/4752265?hl=en)
- [Merchant listing structured data](https://developers.google.com/search/docs/appearance/structured-data/merchant-listing?hl=en)
- [Ecommerce URL structure](https://developers.google.com/search/docs/specialty/ecommerce/designing-a-url-structure-for-ecommerce-sites)
- [Faceted-navigation crawling](https://developers.google.com/crawling/docs/faceted-navigation)
- [Ecommerce site structure](https://developers.google.com/search/docs/specialty/ecommerce/help-google-understand-your-ecommerce-site-structure?hl=en)

The completion gate must compare at least one eligible and one ineligible
product end to end: ERP control -> saved owner -> public HTML -> visible page
-> JSON-LD -> Merchant projection -> cart/checkout. Any mismatch blocks the
release claim.

### Blocks, campaigns, and layered composition

- A campaign is a real block/slide/Canvas composition. Copy, images, shapes,
  products, buttons, geometry, opacity, rotation, order, visibility, and CTA
  data are editor-owned values.
- An agent may generate a background image, but editable copy, CTA, product
  images, and important decorative geometry must not be flattened into it.
- Every visible style—including alpha/transparency—must have a human control.
  Raw ARGB/hex is secondary advanced input, not the only control.
- Repeated content uses one canonical collection editor with one active item;
  do not dump every item's complete form into the inspector.
- Universal behavior is implemented in shared controls and renderers, not once
  per banner. This includes CTA, media selection, colors, text formatting,
  transforms, responsive visibility, focal point, and layer order.

### Inline editing and inspector

- Clicking any editable object restores its complete owner path and opens the
  matching inspector. Re-clicking an already selected object must work.
- Inline controls expose frequent contextual actions; the inspector exposes
  labelled precision and secondary configuration. Both update the same value.
- Canvas toolbars retain direct one-step backward/forward ordering, plus
  one-level Arrange and More palettes. Important actions are not buried behind
  nested ellipses.
- Text, images, buttons, shapes, products, and galleries use the same Canvas
  selection/transform/order contract.
- Selection, hover, open panels, crop mode, drag guides, and inspector scroll
  are transient UI state. They do not dirty or publish content.
- Geometry and toolbars remain hit-testable at responsive scale and near every
  canvas edge. Paint overflow is not accepted as hit-test support.

### Media and product imagery

- Every image control leads with the shared visual picker. It provides
  Biblioteca, Productos, Subir, and URL avanzada in that order of intent.
- URL is optional advanced input. URL-only image controls are incomplete.
- Product-aware Canvas images distinguish `Usar sólo imagen` from `Vincular
  producto`. Linking preserves the catalog relationship; click/navigation is a
  separate explicit CTA/action decision.
- Transparent cutouts, focal point, fit, crop, alt text, responsive variant,
  product binding, and selected source must all round-trip.
- Background removal is a shared non-destructive media operation: free local
  processing first when appropriate, optional paid processing only after an
  explicit cost-bearing action, original restorable, result stored in the
  normal media library. Both ordinary uploads and local/provider background
  removal feed the same authenticated optimizer: a bounded source is retained,
  while the editable/public URL points to an immutable transparent-capable
  WebP and the picker consumes its lightweight thumbnail.

### Theme and header/footer behavior

- `Tema` is global. Fonts, palette, page background, spacing, and button tokens
  must reach blocks, banners, header, footer, menus, catalog, product detail,
  cart, checkout, and policy pages.
- Hardcoded typography, colors, or button geometry are fallback defaults only.
  A local override requires an explicit visible opt-out such as
  `inheritTheme = false`.
- Header foreground/logo/icon contrast is one site-wide policy with automatic
  and explicit modes. Do not recolor descendants or repair slides one by one.
- Moving a Canvas layer behind the header must not require manual recoloring of
  each header control.
- Theme resolution has one runtime owner: `PublicStoreLayout` supplies the
  `pending > saved > fallback` reader to `WebsiteResolvedTheme` and publishes
  that exact immutable extension through `WebsiteThemeBuilder`. Home, Policy,
  Dynamic, Contact and commerce consume `WebsiteResolvedTheme.of(context)`;
  they do not read or parse `theme_*` settings locally. Reopening `Tema` uses
  the same effective reader so unsaved values remain visible in the control.
- `theme_text_color` projects exactly into `ColorScheme.onSurface` and the base
  `TextTheme`, and `Tema > Colores > Color de texto` is its visible canonical
  control. `Tema > Espaciado` owns the global inherited section gap and content
  padding within the existing composition bounds; those controls stage through
  `WebsiteEditModeProvider`, never a direct `WebsiteService` writer. A resolved
  theme key may not exist as a hidden editor key. Regression must also cover
  missing/malformed values, legacy decimal/`0x`/`Color(...)`/hex encodings,
  digit-only six/eight-character hex, bounded typography/spacing, control
  visibility and consumer convergence.

### Edit, Preview, public parity and clipping

- Content geometry and value resolution are shared. Editor-only chrome is an
  overlay, not an alternative content layout.
- The capability registry owns `exact`, `minimum`, or `intrinsic` height
  behavior for every block type. Composition, inspector and both renderers
  consume that same value; no local dynamic-height list may compete with it.
- Spacing and insertion chrome is linked to composition anchors. It may overlap
  content for operability, but it cannot add height to a zero or small saved
  gap.
- Saved rotation, alpha, position, crop, font, fit, spacing, visibility, and
  animation mean the same thing in Edit, Preview, and public mode.
- Bounded blocks such as carousels clip transformed content at their own
  boundary while keeping editor chrome reachable.
- Never repair one seeded campaign to hide a renderer/container bug. Fix the
  shared boundary or resolver.

### Save and publication

- Content/configuration changes stage through the editor-wide draft and global
  save. Dialog `Aplicar` may update the draft but does not invent a private
  persistence path.
- `WebsiteSaveCoordinator` is the only global save orchestrator. It snapshots
  page, sitewide, navigation and SEO drafts; saves idempotent families first;
  replaces page blocks through the atomic tenant/page-scoped
  `replace_page_blocks` RPC; and creates navigation rows last with stable
  idempotency keys. Sitewide-only saves do not require a page lookup.
- The RPC migration `20260729010000_atomic_replace_page_blocks.sql` was
  deployed, verified live and registered in production on 2026-07-29. Its
  anonymous execute grant is absent; `authenticated` is the sole application
  role with execute access.
- A section clears only when its successful snapshot still equals the current
  draft. Failures and concurrent edits remain staged and visible for retry.
  Successful block replacement rebaselines undo/discard history.
- Operational publication, OAuth, sync, import, and destructive actions may
  persist immediately only when the UI clearly presents them as operations.
- `GoogleBusinessService.connect` owns one service-boundary single-flight
  installed before loading notification, so synchronous listener reentry joins
  the same Future. The owning invocation holds its nonce locally and may only
  compare-clear that nonce; button disabling is secondary UX. Regression must
  include concurrent and listener-reentrant connects, one launcher/intent,
  false/cancel/error cleanup and preservation of a newer unrelated intent.
- Discard restores every staged bucket, including blocks, theme, header/footer,
  navigation, category visibility, and SEO.
- A successful write is not a round-trip proof. Reload and read back through
  the canonical UI and consumer.

### Navigation and document replacement

- `WebsiteEditorNavigationGuard` owns unsaved-change confirmation for selectors,
  CTAs, search, external links, quick page creation, explicit exits and Back.
  A page switch may discard only the captured page scope; leaving the editor
  includes sitewide and SEO drafts.
- Authorization is revision-bound. After any checkout or destination await,
  callers revalidate before committing. Back authorizes editor and checkout
  together, then commits discard and pop without an async gap.
- A nested page-stack Back is `switchPage`; the outer storefront exit is
  `leaveEditor`. Local route history closes before either draft guard, and a
  checkout authorization always captures the editor revision even when the
  editor was clean at the start.
- Stable routed identity includes more than the named content key. The outer
  navigation guard keeps one persistent `PopScope` and varies only `canPop`;
  the device viewport keeps explicit `SizedBox > DecoratedBox > ClipRect`
  wrappers and varies only their values. Conditional guard insertion and
  `Container`'s conditional decoration/clip internals can remount a plain
  GoRoute subtree. The minimum matrix proves identical State, retained text,
  focus and scroll, and zero disposals across Public/Preview/Edit plus
  desktop/tablet/mobile, without StatefulShellRoute or keep-alive shielding.
- A browser reload/assignment is always an editor exit, including same-page
  Home refresh in Preview. Never classify a document replacement from URL
  equality alone.
- Static policy trust has explicit retained provenance: editor-loaded drafts
  never become public authority. Public origin and retained stale public
  snapshots may compose; editor-only content stays unavailable and noindex.

## Failure patterns learned during the refactor

These are architecture regressions, not isolated visual bugs:

| Failure | What it revealed | Permanent prevention |
|---|---|---|
| Banner edits existed only in code | Public renderer had become a second CMS | Owner + Control + Operation + Consumers proof |
| CTA types behaved independently per block | Shared capability was copied instead of reused | One action model/editor/renderer for every CTA consumer |
| Theme font changed only some areas | Local renderers overrode global theme | Theme audit across all public surfaces |
| Edit showed rotation but Preview showed straight content | Saved transform wrapper existed only in edit mode | Shared mode-independent content renderer |
| Rotated white panels crossed the carousel bottom | Paint overflow was fixed in the campaign instead of its container | Bounded owner clips content; toolbar chrome stays outside |
| Selected nested layer did not open controls | Parent carousel/slide selection context was lost | Typed selection path and repeated-click re-emission |
| Product page inside editor loaded only shell/header/footer | Editor route skipped the public page initialization | Page selector exercises the real route/data lifecycle |
| Image control requested only a URL | A block-local implementation bypassed media ownership | Picker first everywhere; URL advanced only |
| Transparency was visible but not editable | Alpha was hidden inside serialized color | Visual palette + explicit opacity + advanced code |
| Product image looked like a pasted white rectangle | Catalog image and campaign presentation were conflated | Product binding plus explicit editable manual/cutout source |
| Dragging stopped at an invisible edge | Coordinate spaces and safe-area policy were implicit | Visible global safe area and precise geometry controls |
| Inline toolbar hid common layer order | Serialized capability was exposed without task hierarchy | Shared contextual toolbar + inspector precision mirror |
| Duplicate category/product publishers appeared | Contextual access became a second owner | Shortcuts open canonical management workspace |
| Category CTA used a hand-authored query | Destination was stored as an opaque string | Typed catalog destination with visible filters |

## Required protocol for every future agent

### Before implementation

1. Read `.github/copilot-instructions.md`, `website-editor-contract.md`, this
   handoff, `GUI_DESIGN_PRINCIPLES.md`, and `canonical-ui-surfaces.md`.
2. Identify the requested result's owner, control, operation, and consumers.
3. Trace the real route, provider/service write, persisted key/entity, editor
   control, Preview renderer, public renderer, and management workspace.
4. Search every registered consumer of the capability. A user example is a
   symptom, never permission to patch only that example.
5. Inspect the live editor or current screenshots before relying on old seed
   content or an old debug binary.

### During implementation

1. Add missing reusable capability before authoring content that needs it.
2. Use schema factories and typed value models; reject unknown hidden fields.
3. Keep contextual shortcuts connected to canonical owners.
4. Stage through the shared draft/history/save path.
5. Keep Edit, Preview, and public consumers on the same resolver/render tree.
6. Preserve unrelated working-tree changes and compatibility data.

### Before completion

1. Verify the actual current app, route, tenant context, and content version.
2. Test the normal click/navigation path, not only a direct deep link.
3. Verify desktop and mobile, Edit and Preview, then saved public rendering when
   publication is in scope.
4. Save/reload/reopen the exact controls and verify round-trip.
5. Exercise destination readiness and the final product result set.
6. Add focused regression tests for the failure class found.
7. Update this handoff, the engineering contract, and canonical surface
   registry when ownership or interaction architecture changes.

## Evolution plan: professional catalog collection pages

The next major storefront improvement should replace the current “generic
catalog with a category filter applied” experience with editor-owned,
SEO-capable collection presentation. It must not become a family of hardcoded
pages such as `if category == Cámaras`.

### Target customer experience

A category destination such as Cámaras should be able to show:

- a clean canonical category URL and breadcrumb;
- an editable category/collection hero with title, supporting copy, media or
  video, focal point, contrast, and responsive presentation;
- optional subcategory or buying-path navigation;
- optional editorial blocks such as a sizing/valve guide, trust message,
  featured products, or campaign strip;
- the real category product grid and count;
- useful secondary facets and sorting;
- page-context treatment for the base category instead of presenting it only
  as an unattractive removable filter chip;
- category-specific SEO title, description, canonical metadata, social image,
  and structured data backed by visible controls.

The category remains the catalog owner. This is a presentation attached to the
category, not a duplicate ordinary CMS page and not a static product list.

### Implementation status — 2026-07-22

The first integrated collection slice is implemented in the current checkout:

- `WebsiteCatalogPresentation` is a typed, versioned registry keyed by stable
  category ID. Its physical storage uses the existing tenant-scoped
  `website_settings` operation because that record family already owns public
  website configuration, cache, backup and restore. The typed model and
  `WebsiteService` methods are the logical owner; renderers do not read or
  write arbitrary ad-hoc values.
- `Catálogo web > Categorías > Presentación` exposes select, edit, real-product
  preview, explicit save and remove/reset for slug, hero inheritance and
  overrides, layout, breadcrumbs, subcategories, query-backed facets and grid
  density. Category publication and navigation placement stay separate.
- Clean product/service category routes are parsed, generated and normalized
  through shared helpers in standalone and ERP-mounted modes. Legacy query
  destinations remain readable, and the typed link editor writes clean routes
  after edit while preserving combined search/type filters.
- A saved slug change automatically retains the previous slug as a visible,
  editable and removable alias. Current slugs and aliases share one
  collision-validated namespace; ambiguous imported claims and duplicate
  legacy leaf names fail closed. Product and service alias routes resolve the
  stable category owner, replace the URL with the current canonical and feed
  noindex snapshots plus generated Firebase 301 entries. Editing does not
  deploy those redirects.
- The shared catalog renderer consumes the presentation in Edit, Preview and
  public modes, uses real category/product data, prevents stale requests from
  repainting a newer selection, and defines an invalid-category state.
- Product detail breadcrumbs and the mega menu now participate in the same
  canonical destination system. The mega menu remains owned by
  `website_navigation`, with its saved `megamenu` presentation consumed by
  desktop hover intent, click/focus/keyboard/Escape and the responsive mobile
  navigation; renderers do not infer menu structure from category names. Its
  recursive visual-card browser projects each typed category destination to
  the same category-owned `WebsiteCatalogPresentation.mega_menu_image_url`:
  the branch owner uses it as the left overview and nested categories use it
  as their card image. The same owner now also exposes the branch overview
  width (`300–440` px) and the top/center/bottom placement of its text content;
  legacy records retain `440` px and bottom placement. Each typed branch change
  presents its slightly enlarged eyebrow, title, rule and explore action with
  one smooth staggered fade/slide/scale entrance; reduced-motion preferences
  skip the transition. Visual cards center a larger white category title over
  their image. The image/title follows the category's typed destination, while
  the separate always-blue
  `Ver subcategorías` text-and-arrow hit target is the only hover/focus preview
  trigger and the only drilldown control; blank space in its row is inert. A
  category-owned card overlay can darken individual artwork without changing
  the shared images or relying on renderer category names. The drilled view
  exposes an explicit
  `Ver todo en …` action. Leaves remain one unified typed destination. Missing
  images use placeholders.
  The six direct **Transmisión** cards — Volantes, Piñones, Motores,
  Missinglink, Kits and Cadenas — now have authored media saved in that same
  canonical presentation registry; Volantes uses the corrected drive-side
  chainring view. All six owners request the same `0.35` card overlay, so their
  centered titles and subcategory-preview interaction share one contrast
  treatment without modifying the media assets. Future or deeper categories
  without authored media continue to use the placeholder until their image is added through
  `Catálogo web > Categorías > Presentación`.
- Root/category controls now own search title, meta description, social image,
  allow-indexing restriction and ordered facets. Runtime metadata, canonical
  cleanup, category snapshots, sitemap membership and generated alias
  redirects resolve those same saved values. Private, ERP-mounted, Edit,
  Preview, empty, invalid and transient query routes remain
  `noindex,follow`.
- Saved global theme values are projected through `WebsiteThemeBuilder` and
  `PublicStoreSurfaceTheme` into the catalog, product detail, cart and checkout
  rather than repaired with route-specific colors.
- Typed brand and effective-price facets, deterministic URL state and the
  additive one-scan server wrappers are deployed through migration
  `20260722200000`. Its production-derived pgTAP, benchmark, two independent
  reviews, rollback probe, registration and function/ACL/hash/result read-back
  pass. Unlocked desktop Preview/public category-count and navigation smoke
  also pass; combined secondary facets and responsive history flows remain.

The remaining planned work is optional editorial section composition, richer
structured catalog attributes (material, speed, size, standards), semantic
collection/breadcrumb structured data, deliberate deployment of generated
SEO/redirect artifacts, and full browser/mobile acceptance. No category-name
parser or hardcoded page may substitute for those capabilities.

### Canonical commerce projection status — 2026-07-22

The product value-drift foundation is implemented locally:

- `PublicCommerceProductProjection` is the typed Dart owner-facing projection
  used by hydrated product detail, Product JSON-LD, static deploy snapshots,
  no-JS product content, cart and checkout. The shared TypeScript projection
  uses the same precedence and eligibility issue codes for Merchant feed and
  diagnostics.
- Saved `website_merchant_title`, `website_merchant_description`, brand, GTIN,
  MPN and Google category remain product-editor controls. Title/description
  overrides now become the factual public commerce copy on every consumer;
  renderers cannot privately rewrite or pad them. Their current labels describe
  that public-commerce scope rather than presenting them as feed-only copy.
- Effective price is `website_price` then catalog price. Availability is the
  canonical sellable quantity supplied by the public/reservation-aware
  projection. Category path comes only from the category owner, linked brand
  comes only from an active tenant/global brand owner, GTIN must pass its
  checksum and restricted-prefix validation, and MPN must be explicitly
  recorded. SKU is never treated as MPN.
- Merchant eligibility fails closed with typed reasons for missing identity,
  title, description, positive price, public image, verifiable brand or public
  publication/content requirements. An out-of-stock product remains a valid
  Merchant projection with `out_of_stock` when storefront, JSON-LD, feed and
  checkout agree; stock quantity is not a required positive-value gate. A
  missing GTIN/MPN/category is unknown and omitted, not guessed.
- Product-detail loading/missing/Edit/Preview states explicitly own
  `noindex,follow` and a clean canonical, so they cannot inherit stale
  indexable metadata from the previous routed product.
- No Merchant Edge Function was deployed in this slice. Focused Dart and Deno
  contracts cover equal runtime/deploy output, active-brand parity, valid
  out-of-stock behavior, and eligible/ineligible examples.

Remaining acceptance work is browser/deploy evidence: compare one real
eligible and one real ineligible product across the visible landing, initial
HTML, hydrated JSON-LD, generated Merchant XML and checkout request. The
comparison must be repeated after the deliberate Merchant function deployment;
local code/tests are not production-feed evidence.

### Direct category membership in navigation — 2026-07-23

The catalog now distinguishes two typed operations without duplicating
taxonomy or category pages:

- Owner: `product_categories` owns membership and hierarchy;
  `WebsiteCatalogQuery.categoryScope` owns `subtree` versus `direct`; a real
  `website_navigation` row owns each visible menu option.
- Control: destination editors expose `Categoría y subcategorías` and
  `Solo productos asignados a esta categoría`. Navigation can therefore keep
  an inclusive parent such as `Cadenas`, plus an editable/removable homonymous
  child for direct membership and ordinary children such as
  `Guías de cadena`.
- Operation: the parent card image explores its saved children. Its persistent
  `Ver categoría` action and the drilled `Ver todo en …` action navigate to the
  inclusive collection. The homonymous child uses
  `category_scope=direct` and returns only products whose category ID is the
  selected category itself.
- Consumers: server products and facets, Edit-mode local filtering, result
  counts, URL/back-forward state, wide mega menu, compact dropdown, mobile
  navigation, destination audit and SEO all consume the same typed scope.
- Routes and SEO: the clean category route defaults to `subtree`; only the
  direct refinement writes `category_scope=direct`. That transient route is
  `noindex,follow` and canonicalizes to the clean inclusive collection, so it
  does not create a competing indexed category or Merchant landing page.
- Verification: parse/build/default/invalid-scope contracts, direct singleton
  versus subtree IDs, editor round-trip, exterior drill versus inclusive CTAs,
  direct-card navigation and renderer descriptors are covered by focused
  tests. Browser visual acceptance remains user-controlled for this slice.

### Current closeout matrix

| Area | Current state | Remaining gate |
|---|---|---|
| Catalog management and inline product editing | Completed in the canonical product/category/featured owners; unlocked desktop management, rules, confirmation and inline editor passed | Responsive/mobile and save/reopen stress acceptance |
| Root/category presentation and clean routes | Completed locally, including product/service slug aliases | Deliberate generated-redirect deployment smoke |
| Mega menu and responsive navigation | Hover/click/keyboard/mobile behavior implemented from `website_navigation`; the existing editor-owned `Panel ancho` presentation control is active for `Componentes`. The desktop consumer is a full-width editorial panel, derives contrast from the configured header, measures the real rendered header bottom in standalone and ERP-hosted overlays, and uses recursive category cards with a centered image title, an explicit always-blue subcategory preview/drill action, separate parent-category navigation, drilldown/back, typed leaf destinations and editor-owned `mega_menu_image_url` media, card/branch overlays, overview width and text placement. The saved Transmisión owner now requests a cropped version of its original photo with strong left-side contrast, a 330 px overview and vertically centered content; the current checkout consumes all four values, while publication of the new renderer remains a separate deliberate release action. All six direct Transmisión cards have authored category-owned media, including the corrected drive-side Volantes image, and all six request the same `0.35` card overlay through their individual presentation owners. The first warm Ruedas batch is saved on the canonical category owners for Tubeless, Rodamientos and Rayos; the Rodamientos owner now uses the exact catalog UUID and a cache-safe v2 asset. Ruedas also owns its overview image: one detached rear MTB wheel with left-side text contrast. Unauthored deeper categories retain intentional placeholders | Mobile visual and screen-reader audit; review the first Ruedas batch, then author Nipples, Neumáticos and Mazas through the canonical presentation workspace |
| Theme projection | Catalog, detail, cart and checkout consume the saved theme projection | Real breakpoint/contrast audit and lower-frequency public pages |
| Catalog facets | Ordered controls, URL state and one-scan wrappers deployed and registered as `20260722200000`; 52/52 pgTAP, benchmark, rollback probe, two reviews and live hash/ACL/result read-back passed. Management now batches the canonical availability RPC, removing the `544` versus `547` set-product undercount | Combined brand/price/history and responsive smoke |
| SEO snapshots/indexation | Editor-owned values, restrictive runtime robots/canonical, category/product snapshots, sitemap and alias redirect generation implemented locally | Semantic collection structured data plus deployed/browser proof |
| Merchant identity/value parity | Canonical projection, GTIN/MPN rules, active linked-brand parity and valid out-of-stock behavior implemented locally | Deliberate Edge deployment and eligible/ineligible browser/feed equality |
| Advanced professional catalog | Suggested/future: editorial sections, focal-point responsive media and real material/speed/size/standard facets | Add their owners, controls and canonical product attributes before rendering |

### Phase 0 — baseline and data contract

- Inventory current category, product-visibility, destination, catalog route,
  SEO, navigation, and block ownership.
- Capture the existing `/productos`, category route, query-filter, editor page
  selector, Preview, and public behavior with tests.
- Define one typed `WebsiteCatalogPresentation` domain contract linked to a
  stable category ID. Decide its physical persistence only after checking the
  live schema. If the existing website-settings record family is used, it must
  be a versioned domain registry behind typed service operations and the
  canonical editor—not ad-hoc renderer keys or an opaque agent-only blob. Do
  not duplicate a page row.
- Separate route context (category/collection) from optional user-selected
  facets (brand, price, size, stock, search, product type).

### Phase 1 — canonical category presentation owner

- Add a one-to-one category presentation owner with explicit inheritance and
  removable-override semantics; category publication remains owned by
  `product_categories.show_on_website`.
- Store editor-visible fields for display title, eyebrow, introduction, hero
  media/video, focal point, overlay, text alignment, theme inheritance,
  responsive behavior, optional section blocks, grid presentation, and SEO.
- Reuse registered block/Canvas/action/media/color/theme contracts rather than
  inventing category-only variants.
- Expose the owner under `Catálogo web > Categorías > Presentación web`, with a
  contextual `Editar presentación` handoff from the routed editor.
- Ensure a category without a presentation uses a polished shared default, not
  a generated hidden record for every category.

### Phase 2 — typed routes and destination integrity

- Evolve `WebsiteDestination` to produce and parse a canonical clean category
  route, preferably `/productos/categoria/<stable-slug>`, while preserving
  legacy `?category=<id>` links through normalization/redirect compatibility.
- Keep the stable category ID as the resolved owner even when the display slug
  changes.
- Extend the catalog-filter destination model for supported secondary facets;
  never hand-build query strings in blocks or menus.
- Make `Estructura > Destinos y enlaces` show presentation readiness, category
  publication, eligible product count, SEO readiness, and usage by CTA/menu.
- Keep menu placement in `website_navigation` and page identity out of
  `website_pages` for ordinary category collections.

### Phase 3 — shared collection renderer

- Build one collection-page renderer consumed by Edit, Preview, and public
  routes.
- Compose presentation hero/sections, breadcrumb/subcategory navigation, the
  canonical product grid, sorting, facets, pagination, empty state, and footer
  without separate mode-specific layout branches.
- Use `PublicInventoryService` and the current public eligibility policy for
  products, counts, and descendants.
- Keep optional curated product IDs as explicit editorial modules; the main
  category grid always remains query-backed.
- In Edit mode, overlay selection/editor chrome without changing public
  geometry or skipping catalog initialization.

### Phase 4 — professional catalog and filter UX

- Treat the category as route context in the header/breadcrumb. Do not rely on
  a chip labelled “Cámaras” as the page's only identity.
- Provide desktop filter rail/drawer and compact mobile filter sheet using the
  same facet state.
- Show active secondary filters clearly, support individual removal and clear
  all, and preserve state in canonical URLs when shareable.
- Define loading, empty, invalid-category, unpublished-category, zero-eligible-
  product, and stale-route states explicitly.
- Preserve back/forward navigation, pagination, sorting, and deep links.
- Ensure the editor can configure which applicable facets are visible and
  their order without hardcoding a special case per category.

### Phase 5 — SEO and discovery

- Add human controls for category SEO title, meta description, canonical slug,
  social image, indexability, and optional editorial copy.
- Render breadcrumb and collection structured data from canonical category and
  catalog values; do not duplicate product facts in presentation JSON.
- Include published category destinations in sitemap/snapshot generation using
  the same route builder.
- Verify header/footer/mega-menu links, internal CTA links, search results, and
  external catalog/product URLs continue to use canonical builders.

### Phase 6 — migration and compatibility

- Resolve existing category query links to the new typed route without losing
  combined filters.
- Do not manufacture category presentation content from product names or stale
  screenshots. Apply only safe defaults and let visible controls own future
  enrichment.
- Preserve publication fields during category/image/name edits.
- Add compatibility reads for legacy destinations, but write only the new
  canonical representation after edit/save.
- Mirror any schema change into `supabase/sql/core_schema.sql` and follow the
  staging/database runbook before remote mutation.

### Phase 7 — verification and rollout

- Unit-test route parse/build/normalize, category identity/slug changes,
  combined filters, visibility policy, empty states, and SEO projection.
- Widget-test editor handoff, presentation controls, product-grid loading,
  facet interaction, responsive layouts, and save/reload round-trip.
- Add browser integration coverage for menu/CTA -> category presentation ->
  filters -> product -> back navigation in Edit, Preview, and public mode.
- Test at least one root category, nested category, unpublished category,
  category with no eligible products, and combined category + search/brand
  destination.
- Release behind a controlled compatibility boundary if needed, but never keep
  two editable owners after rollout.

## Definition of done for future storefront changes

A future agent may report a website task complete only when:

- no visible result depends on a category name check, hidden constant,
  renderer-only branch, opaque route, or agent-only mutation;
- every durable value has a canonical owner and visible control;
- agent automation produces the same validated state as the UI operation;
- canvas and management/configuration dependencies are both resolved;
- real catalog eligibility determines products and counts;
- typed destinations survive navigation and reopen with their filters;
- Edit, Preview, public, desktop, and mobile agree on saved semantics;
- global theme and shared media/action controls are reused;
- save/reload returns every value to its control;
- relevant registry, architecture, migration snapshot, and regression tests are
  updated; and
- the user can continue editing or delete the result without the original
  agent.

## Minimal handoff for a new chat

A new agent starting Website Builder work must be told to read, in order:

1. `.github/copilot-instructions.md`
2. `docs/architecture/website-editor-contract.md`
3. `docs/architecture/website-builder-agent-handoff.md`
4. `.github/GUI_DESIGN_PRINCIPLES.md`
5. `docs/architecture/canonical-ui-surfaces.md`

Then the agent should restate the requested feature's Owner, Control,
Operation, Consumers, route impact, catalog impact, and verification matrix
before changing implementation. That restatement is the guardrail against
quietly rebuilding a hardcoded parallel storefront.

## Estado 2026-07-30 (cierre Claude, handoff de emergencia)

Implementación, pruebas y validación productiva-derivada completas (ver el plan
progresivo para el detalle de gates y conteos). Codex desplegó mediante el flujo
guardado, verificó por readback y registró
`20260730091630_harden_website_editor_reads.sql` el 2026-07-30; el health
productivo cerró con cero violaciones críticas. No queda SQL de este cierre
pendiente. Sin commit/push/staging de app por decisión del owner.
