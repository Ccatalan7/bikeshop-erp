# Website Editor Engineering Contract

**Status:** Mandatory for every Website Builder, public storefront, campaign,
and editor-management change  
**Last updated:** 2026-07-29

This document is the current engineering contract for the Viñabike Website
Editor. Read it before changing website editor controls, blocks, renderers,
routes, preview behavior, campaigns, catalog destinations, or storefront theme
behavior. It supersedes older dated notes and code snippets when they conflict.

After this contract, read
[`website-builder-agent-handoff.md`](website-builder-agent-handoff.md). It is
the operational summary of the refactor, defines AI action equivalence, maps
the connected configuration owners, and contains the current catalog/category
evolution plan.

Track the progressive architecture phases and their verified completion in
[`WEBSITE_BUILDER_PROGRESSIVE_ARCHITECTURE_REFACTOR_PLAN_2026-07-29.md`](../development/WEBSITE_BUILDER_PROGRESSIVE_ARCHITECTURE_REFACTOR_PLAN_2026-07-29.md).

The editor is not a mockup layered over a separate website. It is the CMS for
the real website. A result is complete only when the saved editor state fully
explains the editor canvas, Preview, and the published storefront.

## Core invariant

The system must preserve this relationship:

```text
editor control -> staged editor value -> shared renderer -> editor canvas
                                      -> Preview
                                      -> saved value -> published storefront
```

The editor may add selection borders, handles, grids, toolbars, and drag/drop
targets. Those are the only intentional visual differences. Content layout,
fonts, colors, images, transforms, clipping, responsive visibility, CTA
destinations, and animation settings must mean the same thing in every mode.

Every change must satisfy all four parts of the editor-owned contract:

1. **Owner:** one canonical persisted model owns the value.
2. **Control:** the user can find and change it through the real editor or its
   connected management workspace.
3. **Operation:** the editor and agent automation use the same defaults,
   validation, persisted schema, and save/publication invariants; automation
   acting on a live draft also uses the normal staging/history path.
4. **Consumer:** every editor, Preview, and public renderer reads the same value.

## Canonical system map

| Responsibility | Canonical implementation |
|---|---|
| Inline store/editor shell and page-route controller | `PublicStoreLayout` |
| Persistent right inspector | `PersistentEditorShell`, `WebsiteEditorPanel` |
| Typed active document, scoped drafts, page context, selection, and history | `WebsiteEditModeProvider`, `WebsiteEditorDocument` |
| Page visibility, order, spacing, full-bleed and height projection | `WebsitePageComposition` |
| Page-level Edit/Preview/Public composition | `PageComposition` |
| Editable block composition and block hit testing | `EditableBlockRenderer` |
| Public block rendering | `WebsiteBlockRenderer` |
| Layered campaign rendering | `CanvasBlock`, `DeferredCanvasBlock` |
| Layered campaign inspector | `_CanvasBlockControls` |
| Typed CTA destinations | `WebsiteLinkValueEditor`, `WebsiteDestination` |
| CTA value and rendering | `WebsiteActionValue`, `WebsiteActionEditor`, `WebsiteActionButton` |
| Global site theme | shell-owned `WebsiteResolvedTheme`, projected by `WebsiteThemeBuilder` from saved/staged `website_settings` |
| Page/catalog/navigation management | Website Builder management workspaces registered in `canonical-ui-surfaces.md` |
| Persistence orchestration | `WebsiteSaveCoordinator` through global `Guardar` |
| Atomic page-block replacement | `replace_page_blocks` through `WebsiteService.replacePageBlocks(...)` |

The visual canvas, right inspector, page selector, and black management bar are
connected parts of this one system. They may expose different tasks, but they
must never create competing owners for the same value.

## Agent-created campaigns are real editor operations

When a user asks an agent to create a banner, carousel slide, promotion,
featured-product section, seasonal campaign, announcement, or other periodic
website content, the request is to operate and, when necessary, extend the CMS.
It is not permission to produce a visually similar hardcoded storefront patch.

The finished state must be indistinguishable from content a website
administrator built manually in the editor:

- Every visible object exists as an editor block, slide, Canvas layer, product
  selection, navigation record, page record, theme value, or other canonical
  editable object.
- Every design choice is represented by its control: copy, media, product
  binding, dimensions, spacing, position, rotation, colors, typography, button
  presentation, animation, visibility, focal point, CTA, and responsive
  behavior.
- Reopening the editor must show every value in the corresponding control. The
  user can change or remove the result without an agent.
- Generated media is uploaded through the editor's normal media path and then
  selected like any other asset.
- Code may add a missing editor capability, but the requested content must then
  be created through that completed schema/provider/control path. A hidden
  constant, renderer-only branch, direct SQL content mutation, or agent-only
  service path is not the completed campaign.
- Calling a provider/service instead of clicking is acceptable only when it is
  the exact canonical operation used by the editor and the result fully
  round-trips through the visible controls, global save, Preview, and reload.

If the current editor cannot represent part of the requested campaign, stop
treating that part as simple content entry. Implement the missing reusable
editor capability first, verify it across all consumers, and only then create
the campaign with it.

### Campaign creative quality and product truth

Editor-native does not mean visually generic. Campaigns should use the
professional composition expected from a real commerce design: clear sections,
intentional hierarchy, restrained but expressive typography, product-focused
imagery, readable contrast, and a strong CTA.

- Use an original composition adapted to Viñabike rather than copying a
  reference banner. References establish quality and layout ideas, not a
  template to reproduce.
- Keep essential copy, product images, shapes, and buttons as editor-native
  layers. A generated background may support the design, but it must not flatten
  the whole campaign or bake editable text/CTA controls into a bitmap.
- Prefer real linked catalog images and current product/brand data. Brand names
  may describe real products sold by the store; do not fabricate models,
  packaging, specifications, discounts, availability, endorsements, or logos.
- Present products as customers recognize them commercially. Components should
  be shown plausibly and cleanly—for example, inner tubes folded or boxed as
  sold, not as an unexplained inflated tube floating beside a bicycle.
- Product campaign imagery must be presentation-ready. When a catalog photo
  contains a white studio rectangle, create or select a transparent media
  cutout and keep that cutout as the editable image layer; do not disguise the
  rectangle by placing several catalog photos inside a larger decorative card.
  Preserve the real package, label, proportions, and product binding. A linked
  Canvas image exposes `Imagen visible`: `product` follows the catalog image;
  `manual` keeps the same `productId` binding while rendering the selected
  picker asset. The renderer must never silently replace a deliberate cutout
  with the product's white-background catalog image.
- Reject generated imagery with distorted bikes/components, impossible product
  geometry, illegible packaging, fake labels, or other obvious AI artifacts.
- Copy and CTA claims must be supported by the current catalog/promotion state.
  A category campaign should not imply stock or brands that its destination
  cannot actually show.
- Verify desktop and mobile compositions separately; do not assume a complex
  desktop layer arrangement remains legible when merely scaled down.

## Two connected control planes

The Website Builder has two connected control planes. A complete campaign may
require both.

| Control plane | Owns |
|---|---|
| Visual page editor and right inspector | Blocks, slides, Canvas layers, copy, media, presentation, CTA usage, ordering, visibility, and responsive layout |
| Top management/configuration bar | Real pages, canonical destinations, product/category publication, featured products, navigation records, global theme/header/footer settings, integrations, and publication state |

Future agents must never treat these as unrelated applications. The visible
campaign can depend on catalog/page/navigation/theme entities managed in the
top workspace, while the management workspace must remain the canonical owner
of those entities.

For a category campaign, the complete workflow is:

1. Find or configure the real category under `Catálogo web > Categorías`.
2. Confirm it is included in the public catalog and contains eligible published
   products under the current catalog rules.
3. Build the banner/slide through its editor controls and editor-native layers.
4. Select the category, product, page, or filtered catalog destination through
   `WebsiteLinkValueEditor`; do not hand-author a query string.
5. Confirm the destination is represented in
   `Estructura > Destinos y enlaces` with its owner and readiness state.
6. Add it to header/footer navigation only when requested, using
   `website_navigation`. A campaign CTA is not automatically a menu item.
7. Preview the real routed destination and verify the expected filtered public
   products.
8. Save and publish through the normal Website Editor workflow, then reopen the
   slide and destination controls to confirm round-trip.

A normal category already has a catalog destination. Do not create a duplicate
CMS page merely to make its campaign button work. Likewise, do not restore
redundant product/category publishers: contextual shortcuts must open the same
canonical catalog owner.

## Editor, Preview, and published-renderer parity

Edit mode must be the public visual result plus editing affordances. Preview is
the public visual result without editing affordances. Published mode is the
saved public visual result.

Required rules:

- Home, dynamic CMS pages and policy pages must project their block document
  through `WebsitePageComposition`. That projection is the sole owner of
  breakpoint visibility, `order_index` (with legacy `sort_order` fallback),
  `spacingAfter`, `fullBleed`, and height behavior.
- `PageComposition` is the only page-level switch between editable chrome and
  shared content rendering. Preview and public use the same public visibility
  projection. Edit alone retains hidden blocks so they remain repairable.
- `WebsiteBlockCapabilityRegistry` owns one height behavior per block type:
  `exact` fixes the saved height, `minimum` allows content to grow beyond it,
  and `intrinsic` ignores a legacy saved height. The inspector, Edit renderer
  and Preview/public composition must consume that same capability.
- Block gaps exist only between projected blocks. There is no implicit trailing
  section gap, and a progressive Home slice cannot leave a gap for an
  unpainted block.
- Editor insertion and spacing affordances live in the composition chrome
  layer. A zero or small persisted gap keeps its exact page geometry while the
  linked overlay retains a real 24 px hit target.
- Reuse the same renderer, value resolver, theme, and layout math wherever
  possible. If mode-specific wrappers are necessary, keep the content subtree
  and its transforms identical.
- Never let an `editable` branch apply a transform, font, padding, alignment,
  fit, visibility rule, or clipping behavior that the non-editable branch
  bypasses. A branch such as `editable ? transformed : rawContent` is invalid
  when `transformed` represents saved content rather than editor chrome.
- Draft values must appear immediately in the editor canvas and Preview.
  Preview must not silently fall back to stale database values.
- Public rendering must not contain selection borders, grids, drag targets,
  resize handles, editor toolbars, or admin-only gestures.
- Defaults are fallbacks only. Once an editor value exists, it wins in all
  modes.
- A block whose row is not explicitly hidden but whose desktop, tablet, and
  mobile visibility values are all false is still absent from every public
  surface. It cannot contribute runtime text, static HTML, SEO eligibility, or
  sitemap freshness. Edit may keep it available for repair.
- A parity fix belongs in the shared renderer or shared value resolver, not in
  one campaign's stored data.

For every visual option, verify at least Edit, Preview, and published rendering.
Do not infer parity because one of the three looks correct.

## Selection and right-inspector contract

Anything that looks editable must reliably open its matching controls.

### Inspector information architecture

The right inspector is a task-focused editing surface, not a serialization of
every field in `block_data`. It must preserve professional editor conventions:

- The selected block identity, visibility state, and primary block actions stay
  visible while its controls scroll.
- First-level navigation separates **Content**, **Design** (block geometry and
  spacing), and **Style** (background, padding, border, and shadow). Changing
  the selected block always returns to Content and scrolls to the top; a block
  must never inherit the previous block's inspector depth or scroll position.
- Long block-specific inspectors use progressive disclosure with meaningful
  groups. Common editing starts expanded; secondary behavior, media, overlay,
  display, and advanced settings start collapsed unless their saved state makes
  them immediately relevant.
- Repeatable collections use one shared collection navigator: a compact
  overview of every item plus exactly one active item form. Never render every
  category, testimonial, service, FAQ, team member, price, logo, or nested link
  form expanded at the same time. Adding, selecting, duplicating, reordering,
  and deleting stay available beside the overview; the active item's text/data
  opens first while media, actions, nested collections, and advanced options
  use progressive disclosure.
- Inline toolbars are contextual, not one generic row of every serialized
  field. They expose frequent direct actions for the selected type (text
  formatting; image fit/crop/reframe; button presentation; shape form) plus a
  compact universal set for rotation, alignment, arrangement, duplicate, and
  delete. Secondary and precise controls remain in the right inspector.
- Canvas toolbars use a stable, shallow hierarchy. The primary rail contains
  the selected type's frequent actions, **move one layer backward/forward**,
  Arrange, More, Duplicate, and Delete. Relative layer order must never be
  buried behind a generic ellipsis. Arrange is one in-place palette containing
  the four layer-order commands plus six canvas-alignment commands; More is one
  in-place palette for precise-inspector handoff, rotation/reset, lock, and
  genuinely secondary type actions. A palette returns directly to the primary
  rail; there are no palette-inside-palette flows.
- Type-specific primary actions follow the same contract everywhere: images
  lead with a labelled Replace action, fit and crop; text leads with
  bold/italic/underline, a compact size stepper and an explicit alignment
  palette; buttons lead with presentation variants; shapes lead with form;
  catalog layers expose their frequent layout/price switches. Less frequent
  media processing and exact values stay in More or the inspector rather than
  expanding the rail into a permanent second row.
- The selected layer's **Design** inspector mirrors alignment and all four
  layer-order operations using labelled controls, disables impossible boundary
  actions, and keeps X/Y/width/height/rotation as the precision path. Inline
  and inspector controls update the same element list and saved properties;
  neither surface owns a private transform.
- Every transformable Canvas layer exposes direct edge/corner resize handles
  and a rotation handle. The inspector remains the accessible precision
  fallback for X/Y/width/height/rotation, so a capability is neither
  mouse-only nor hidden in inline chrome.
- Direct-manipulation targets must be fully inside a hit-testable overlay and
  the rotation target must not begin at the element's exact center (a zero
  pointer vector produces a dead or jumping angle). `Clip.none` changes paint,
  not Flutter hit-test bounds. Do not put `Tooltip`, `PopupMenuButton`,
  `MenuAnchor`, `showMenu`, or another `OverlayPortal` inside rotated selection
  chrome or the rapidly rebuilding positioned Canvas toolbar; these can fail
  during macOS layout. Use semantics plus a local non-interactive hover label,
  and present secondary actions as in-place toolbar palettes.
- Keyboard interaction follows the same model: arrows nudge, Shift+arrows use
  a larger step, Command/Ctrl+D duplicates, and Delete removes the selected
  layer when text editing is not active. Transient crop/selection modes never
  become published data.
- A saved transform is never a design-only constant. All Canvas element types
  that the shared renderer can rotate must expose the same persisted rotation
  control, including a clear reset action.
- Canvas position limits must never be invisible. The editor draws the shared
  responsive safe area and exposes X/Y/width/height/rotation at the top of the
  selected-layer inspector. Boundary behavior is one persisted canvas/slide
  policy applied to every existing and future layer, never a toggle repeated on
  each layer. Disabling the canvas-wide constraint permits intentional edge
  bleed while retaining a visible grab target; carousel preview and public
  rendering still clip at the slide boundary.
- Image crop is non-destructive website-layout framing. The layer's `x`, `y`,
  `w`, and `h` own the visible frame; `fit`, normalized `focalPointX/Y`, and
  `rotation` own how the media appears in it. Crop mode itself is transient.
  Dragging within crop mode changes the focal point, eight edge/corner handles
  change the frame, and Preview/public consume the same saved values. Do not
  write a second cropped bitmap or editor-only transform for this workflow.
- The visible carousel slide and the slide selected in its inspector are one
  transient UI selection. Arrow/indicator navigation and inspector slide tabs
  update each other without writing selection state into published block data
  or marking the page dirty.

Do not solve inspector density by deleting capabilities, hiding them in an
unrelated tab, or creating block-local dialogs. Organize the canonical controls
and preserve keyboard, pointer, and responsive access.

### Block selection

- Clicking a block background selects its `blockId` and opens that block in the
  right inspector.
- Empty space inside an editable block remains hit-testable. Use intentional
  hit-test behavior rather than relying on painted pixels.
- Decorative overlays must not steal input. Use `IgnorePointer` where a visual
  layer is not itself editable.

### Nested element selection

Canvas elements inside carousel slides have two pieces of selection context:

1. the owning carousel block; and
2. the active element inside the selected slide.

Selecting a nested text, image, shape, product, gallery, or button must first
restore/select the owning carousel and then update the slide's transient
`activeElementId`. The inspector cannot resolve a nested element without its
parent block context.

- Clicking an already-active element must re-emit selection. Do not return
  early merely because the element ID did not change; another action may have
  cleared the parent inspector context.
- Clicking the composed slide background selects the carousel and clears the
  nested element when appropriate.
- Selection state is transient UI state. It must not create undo-history noise
  or be treated as published content.
- Dragging, resizing, duplicating, deleting, and inspector-driven selection
  must keep canvas and inspector selection synchronized.
- Editor toolbars may remain outside the content clipping layer when necessary,
  but their hit targets must not block selection of unrelated content.

Test both a first click and a repeated click on the same already-selected
element. Also test returning from another block or management workspace.

## Geometry, transforms, and clipping

Transforms change paint bounds without changing the original layout bounds. A
rotated element whose unrotated rectangle ends at the bottom of a banner can
paint below that banner even when its stored `x`, `y`, `w`, and `h` are valid.

Required rules:

- Saved rotation, scale, alignment, and fit values use identical math in Edit,
  Preview, and published modes.
- A bounded component establishes a deliberate paint boundary. Carousel slides,
  heroes, cards, thumbnails, and cover-image frames must not paint into the next
  page section.
- Layered carousel content must enable `clipContentToBounds`. The clipping layer
  contains transformed content at the slide rectangle while leaving editor
  toolbars usable.
- Standalone Canvas overflow may remain available only as an explicit layout
  behavior. Do not inherit `Clip.none` accidentally from a free-form editor into
  a bounded banner/card context.
- Do not "fix" overflow by shrinking or moving one campaign's elements. Fix the
  owning container boundary so future rotations and campaigns behave correctly.
- Responsive scaling, element hit testing, resize bounds, guides, and clipping
  must use the same coordinate space.
- Regression tests must exercise pointer-driven rotation on both scaled and
  unscaled canvases, including a short layer such as a button. Merely asserting
  that a rotation icon or serialized field exists is not interaction coverage.

Visual regression checks must include rotated elements touching the top,
bottom, left, and right edges at desktop and mobile widths.

## Layered carousel and Canvas contract

Advanced carousel slides store editor-native layers in the slide's `elements`
list and reuse `CanvasBlock` plus `_CanvasBlockControls`.

- Keep copy, images, products, shapes, and CTA buttons as separate editable
  layers when practical. Do not flatten a campaign into one poster image.
- The slide owns `useComposition`, design dimensions, its `elements`, and its
  transient active element. Do not move these into a hidden renderer constant.
- The editor and public store must both consume the same element schema.
- A carousel-specific constraint, such as clipping to slide bounds, must be an
  explicit shared option passed through `DeferredCanvasBlock` to `CanvasBlock`.
- Adding a new Canvas capability requires both the canvas renderer and the
  shared inspector control, plus public-mode consumption and regression tests.
- All layer creation entry points use the canonical Canvas element factory.
  Do not duplicate type defaults in the canvas, inspector, and provider; shared
  capabilities such as rotation, locking, responsive fields, or image focal
  data must exist regardless of where the layer was inserted.

## Media-control contract

Every image field must offer the canonical visual picker/upload workflow as the
primary action.

- The canonical picker exposes `Biblioteca`, `Productos`, `Subir`, and
  `URL avanzada`. `Productos` is tenant-scoped and searches product name, SKU,
  brand, and category; products without an image remain visible with an
  explicit unavailable state instead of silently disappearing.
- Reusing a product image must not upload or duplicate the asset. Generic image
  fields consume only the selected image URL. Product-aware Canvas image layers
  additionally offer two explicit outcomes: `Usar sólo imagen` or
  `Vincular producto`.
- A linked Canvas image stores the real product id and follows the catalog's
  primary image. Selecting a non-primary gallery image may retain the product
  relationship while using an explicit manual image source so the chosen
  variant is not silently replaced.
- Raw URL entry may exist only as a collapsed secondary/advanced option.
- Reuse `InlineEditableImage` or the shared schema-routed media control. Never
  create a block-local URL-only dialog.
- Generated or externally sourced assets must enter through the normal media
  upload/storage path and be represented by the same editor control afterward.
- Image value, alt text, focal point, fit, responsive variant, Preview, and
  public rendering must round-trip together.
- Product-linked image layers must continue to show their product owner and use
  the current catalog image; a manual asset may be an explicit fallback.
- Background removal is a shared media operation, not a campaign-specific
  workaround. Canvas image toolbars and schema image controls open the same
  non-destructive Before/After workflow. Applying it keeps the transparent
  source in the normal Website Builder media path, automatically creates the
  bounded WebP delivery asset and its lightweight library thumbnail, keeps the
  pre-removal URL restorable, sets a linked Canvas image to the explicit
  `manual` source, and remains undoable through the page draft.
- The free local path removes only a near-uniform background connected to the
  image border and exposes its tolerance. It must run before any paid provider.
  An asset that already contains meaningful transparency is a no-op: preview
  the existing cutout on the transparency grid, explain that no new copy is
  needed, and disable both Apply and paid processing. Never flood-fill an
  existing transparent cutout as though its transparent RGB values were a
  removable solid background.
  Complex-background processing is an explicit user action, is authenticated
  and tenant-scoped through `website-remove-background`, and states that it
  consumes one provider credit. Provider secrets never enter Flutter or saved
  block data.

## Visual-input contract

Inspector controls describe design intent in the language of a professional
editor. Serialized values remain an implementation detail.

- All color fields route through `WebsiteColorPickerField`. The collapsed
  inspector shows a swatch, a readable color family, and explicit opacity. The
  picker exposes the site palette, recent colors, a full visual selector, and
  opacity; hexadecimal/ARGB input exists only under `Código avanzado`.
- Existing `#RRGGBB` and `#AARRGGBB` values must round-trip unchanged. When a
  renderer accepts alpha, the inspector must expose that alpha as an ordinary
  percentage/slider rather than hiding it in the first two hex digits.
- Media backed by a user file leads with library/upload/file selection. Direct
  URLs and provider IDs are collapsed advanced sources for already hosted
  media, never the first or only workflow.
- Schema fields, Canvas layers, block-specific inspectors, header/footer, and
  global `Tema` consume the same controls. A new block may declare capability
  metadata, but it must not create its own palette, raw color field, or
  URL-first uploader.
- Visual changes still stage through `WebsiteEditModeProvider`, use global
  `Guardar`, and render identically in Edit, Preview, and public mode.

## Page navigation inside the editor

The page menu in `PublicStoreLayout` is the editor's page-route controller. It
is not merely a list of links, and it must not be replaced with a second
standalone editor.

Required behavior:

- Selecting a page navigates to the real routed storefront page while keeping
  the inline editor shell and the appropriate `edit=true` or preview context.
- Clean public-store routes and ERP-mounted `/tienda/...` routes must be
  normalized through the shared routing helpers. Do not hand-build route
  variants in individual blocks.
- `WebsiteEditModeProvider.currentPageId` and `currentPageSlug` must match the
  page whose blocks are loaded and saved.
- CMS pages load their own `website_blocks`; a save must write to that same
  page context.
- Core/system pages such as `/productos` are real routed storefront surfaces,
  even when they are not ordinary CMS block pages. They must load their normal
  public data and filters in editor mode. In particular, `ProductCatalogPage`
  must perform its initial inventory load instead of displaying only the store
  shell/header/footer.
- Switching pages must preserve the draft or show an explicit unsaved-change
  guard. Never discard a draft silently.
- `WebsiteEditorNavigationGuard` is the single confirmation boundary. Page
  switches discard only the captured page draft; leaving the editor discards
  page, sitewide and SEO scopes. Every authorization captures the provider
  revision and must still be current at the navigation operation.
- Checkout and editor Back guards authorize both scopes before any destructive
  state change. After final revalidation, discard and `Navigator.pop` occur
  synchronously with no awaited destination activation between them.
- Back inside a nested storefront page stack uses `switchPage` and preserves
  sitewide/SEO drafts; a pop that leaves the storefront editor uses
  `leaveEditor`. Route-local history is consumed before either editor intent.
  A checkout wait captures the editor revision even when it began clean, so a
  draft created while the confirmation is open cancels that stale exit.
- Replacing the browser document is `leaveEditor`, even from Preview and even
  when the destination URL is the current page. A hard Home refresh must never
  bypass page, sitewide or SEO draft confirmation as `samePage`.
- Route filters selected by a CTA, including category plus brand/search, must
  survive navigation and reopen visibly in `WebsiteLinkValueEditor`.
- Category collections use the clean typed route
  `/productos/categoria/<configured-slug>` (or the service equivalent), with
  the ERP-mounted `/tienda/...` variant produced only by the shared runtime
  normalizer. Routers register collection routes before product-detail
  parameters so a category can never fall through to the product screen.
- The page selector controls which storefront surface is being viewed/edited.
  `Estructura > Páginas` owns page records, and
  `Estructura > Navegación y menús` owns header/footer placement. These are
  connected workflows, not interchangeable controls.

Do not create a duplicate `website_pages` row for a category or product merely
to obtain a destination. Use its canonical catalog/product route.

## Management workspaces and canonical ownership

Only page composition shows the persistent block inspector. Catalog,
structure, settings, and operations use full-width management workspaces while
preserving the current page draft and return context.

- `Catálogo web` owns product/category publication and the featured collection.
- `Catálogo web > Categorías > Presentación` owns the optional presentation
  attached to a real category: stable public slug, inherited/overridden hero,
  breadcrumbs, subcategory navigation, supported facets, and grid density.
  Removing it restores the polished shared default; it never removes or
  unpublishes the category.
- `Estructura > Páginas` owns CMS page records.
- `Estructura > Navegación y menús` and `website_navigation` own header/footer
  placement and hierarchy.
- `Estructura > Destinos y enlaces` audits CTA/menu destination integrity.
- `Tema` owns global typography, colors, background, and button tokens.
- The visual page editor owns page blocks, slides, and their presentation.
- `SEO y visibilidad` reads those owners and sends the operator back to them.
  It does not own another copy of site, page, product, category, canonical,
  social, schema, analytics, or publication settings.

Contextual shortcuts may open these owners. They must not duplicate their data,
save semantics, or business rules.

### SEO visibility and evidence

SEO has one orchestration surface but not one flattened state. Every diagnostic
must preserve these independent planes:

1. **Current app eligibility:** derived now from canonical editable owners.
2. **Deployed-build evidence:** dated evidence from the deployed
   `release.json`, `sitemap.xml`, and `robots.txt`.
3. **Google evidence:** dated Search Console evidence. A submitted or downloaded
   sitemap is not proof that one URL was crawled or indexed.

The center is read-only. Site metadata and the canonical origin remain owned by
site settings (`store_url` is canonical and `seo_canonical_url` is only a
compatibility mirror); page metadata remains owned by `website_pages`; product
metadata/search phrases remain owned by the product's web controls; category
publication and collection presentation remain owned by the catalog workspaces.
The center may search, summarize, diagnose, preview effective copy, and route to
those owners, but it cannot save or delete them.

`store_url` must be one clean HTTPS origin: credentials, page paths, queries,
and fragments are invalid. The editor, runtime projection, static generators,
and Google integration must normalize or reject it through the same contract;
none may silently reinterpret an arbitrary page URL as the site origin.

Product diagnostics must compare all internal products with the exact result of
the canonical public catalog query. They must not infer web eligibility from
`is_active`, inventory publication, or lifecycle fields alone. Generated
product title/description copy uses the same resolver in runtime metadata,
product-form preview, and static snapshots. The first explicit search phrase
may enrich generated copy; it never overrides hand-written metadata or becomes
a hidden keyword dump.

Static trust follows owner publication too: a fallback body may keep a policy
route usable, but cannot make an unpublished `website_pages` owner indexable or
eligible for the sitemap. The initial no-JavaScript navigation and structured
policy references include only trust pages currently published by that owner;
legacy free-form `seo_*_policy_url` values are not route owners. Cart, checkout,
account, order, auth, ERP/editor and preview routes must also emit
response-level `X-Robots-Tag` protection; runtime meta alone is insufficient
for their cached/bootstrap responses.

The deploy-time static generator reads settings (including the presentation
registry), published product owners, public availability, brands, active
categories, product aliases, pages, and blocks as one optimistic source
revision. It accepts two identical complete reads and revalidates the same
complete revision immediately before applying generated redirects. A change in
any participating owner aborts the release instead of publishing mixed HTML,
sitemap, and redirect evidence. Known direct routes such as `/servicios` and
`/contacto` retain a route-specific `noindex,follow` snapshot when their public
owner is not eligible; they never inherit the indexable Home document.

**Known release-freshness residual (2026-07-28):** saving an editor owner does
not itself dispatch the Firebase storefront build. The current app projection
can therefore be newer than the dated deployed-build evidence until the
authorized push/manual workflow runs. UI and diagnostics must expose that age
honestly and must not claim the static snapshot, sitemap, redirects, or Google
state are live merely because an editor save succeeded. Adding an automatic
dispatch requires a separately reviewed authorization, idempotency, failure,
and deployment-ownership contract; it is not inferred by this SEO fix.

## Shared capabilities are universal

If a capability exists in more than one block, it must be implemented once and
reused:

| Capability | Shared contract |
|---|---|
| CTA label, destination, and presentation | `WebsiteActionValue`, `WebsiteActionEditor`, `WebsiteActionButton` |
| Destination selection | `WebsiteLinkValueEditor` and typed `WebsiteDestination` |
| Formatted inline text | `InlineEditableTextV2`, `TextFormattingToolbar` |
| Images | `InlineEditableImage` / shared media picker with Library, Products, Upload, and Advanced URL sources |
| Cover focal point | `FocalPointPicker` |
| Global typography/colors/buttons | `WebsiteThemeBuilder` and saved theme settings |
| Layered composition | `CanvasBlock`, `_CanvasBlockControls`, `DeferredCanvasBlock` |

Do not add a private CTA editor, URL-only image dialog, per-block font system,
custom internal-route text box, or renderer-only layout flag. When a shared
control gains a capability, audit and migrate every registered consumer.

### CTA universality

Hero, carousel, standalone CTA, video banner, pricing, Products “Ver todos”,
standalone buttons, and Canvas buttons must follow the same action model,
editor, destination picker, and renderer. CTA label, destination, and
presentation are one canonical value even when legacy block keys remain for
compatibility. A stale hidden alias or `actions` entry must never override what
the visible editor control shows.

A new CTA capability is implemented once in the shared action contract and
then verified on every registered CTA consumer. Do not fix or enhance CTA
behavior one banner type at a time.

### Global theme universality

The `Tema` tab is the canonical owner for global site appearance. Saved fonts,
colors, page background, base spacing, and global button shape/size must reach
the whole storefront: blocks, banners, Canvas elements that inherit theme,
header, footer, menus, catalog, product detail, cart, checkout, and policy/info
pages.

Hardcoded renderer fonts/colors/button geometry may exist only as fallback
defaults. A local override is valid only when the editor exposes a deliberate,
visible opt-out such as `inheritTheme = false`; the override value must remain
editable and round-trip like every other editor value.

`PublicStoreLayout` is the one runtime resolver. It builds one immutable
`WebsiteResolvedTheme` with `pending > saved > canonical fallback` precedence
and publishes that exact value as a `ThemeExtension`; `WebsiteThemeBuilder`
only projects the resolved value into `ThemeData`. Home, dynamic, contact,
policy and commerce consumers read the extension and must not parse colors,
fonts, sizes or defaults from `WebsiteService` again. Reopening `Tema` uses the
same effective-setting reader, so an unsaved draft cannot disagree with the
canvas. The resolved `theme_text_color` is a real visual token and therefore
must equal `ThemeData.colorScheme.onSurface` and the base `TextTheme` color;
background contrast may derive component roles but may not silently replace
the owner's text color. `Tema > Colores > Color de texto` is its canonical
visible control; a resolved theme key without a visible editor control violates
the Owner → Control contract. `Tema > Espaciado` visibly owns both
`theme_section_spacing` (the inherited gap for blocks without an override) and
`theme_container_padding` (the page-content inset), using the canonical bounds
already enforced by composition. Both stage through `WebsiteEditModeProvider`
and global `Guardar`; there is no direct service writer that bypasses the draft.

The minimum regression covers absent/malformed settings, every accepted legacy
color encoding (including bare six/eight-character hex), staged-over-saved
precedence, font/size/spacing bounds, identical extension/ThemeData projection,
and a source guard that rejects renderer-local `theme_*` readers/parsers.

The header owns one site-wide contrast policy. `Automático` is the safe default:
solid headers derive their foreground from the configured background luminance,
while headers over page content use one restrained tonal protection and tint the
logo, links, account controls, and icons as a single foreground system. Explicit
light/dark modes are global intentional overrides, not per-slide repairs. Moving
or resizing a Canvas layer behind the header must never require recoloring each
header child independently.

## Draft, save, and round-trip semantics

Website content/configuration edits stage in `WebsiteEditModeProvider` and
persist through the editor-wide `Guardar` action.

- Dialog actions such as `Aplicar` or `Listo` may update staged state; they do
  not persist independently.
- Operational actions such as publish/unpublish, OAuth, sync/import, and
  destructive operations may persist immediately only when the UI clearly
  presents them as operations.
- Transient selection, hover, drag guides, and open/closed inspector state do
  not belong in content history.
- After save and reload, every control must reconstruct the same value and the
  renderer must reproduce the same result.
- Discard must restore blocks and all staged theme/header/footer/navigation/SEO
  state, not only the currently visible block.
- `WebsiteSaveCoordinator` captures one immutable save command. Idempotent
  sitewide families save first, page blocks use tenant/page-scoped
  `replace_page_blocks`, and navigation creates run last with deterministic
  idempotency keys. A sitewide-only save does not resolve or replace a page.
- Each successful family is acknowledged only when the current staged value
  still matches its captured snapshot. A failed or concurrently changed family
  stays dirty and retryable; a block failure cannot delete the prior published
  page because delete and insert are one PostgreSQL transaction.
- A successful page-block save rebaselines undo history. Therefore
  `Guardar -> Editar -> Descartar` restores the newly saved document, not the
  session's original load.

## Failure patterns that must not recur

| Symptom | Root cause | Preventive rule |
|---|---|---|
| Elements tilt in Edit but become straight in Preview | Preview rendered raw content and bypassed the saved transform wrapper | Apply saved content transforms in the shared mode-independent renderer |
| Rotated white panels paint over the next section | Canvas allowed paint overflow and the carousel lacked a strict content boundary | Enable bounded clipping for composed carousel content; keep toolbar chrome outside that content clip |
| A layer shows an orange selection outline but the inspector says “Selecciona un bloque” | Nested element selection did not restore the parent carousel, and re-clicking the same ID emitted nothing | Select the owning block before nested state and re-emit repeated selection |
| Clicking “Imagen” opens only an image URL field | A block-local editor bypassed the shared media workflow | Visual picker first; URL secondary/advanced only |
| `/productos` shows header/footer but no catalog in the editor | The routed system page mounted without its required initial data load in edit mode | Exercise the real route and preserve the public page's initialization/filter lifecycle |
| A CTA works visually but is absent from destination/configuration tools | A raw href or duplicate page/menu owner bypassed the typed destination system | Use `WebsiteLinkValueEditor`, canonical entity routes, and destination audit |
| Theme controls change only some blocks | Renderers hardcoded fonts/colors/button geometry instead of inheriting saved theme values | Theme values are global consumers; overrides require explicit editor-visible opt-out |
| Logo or header icons disappear over a bright hero layer | Overlay mode recolored only some header descendants and trusted the hero to provide contrast | Resolve one global header foreground, tint the logo and controls together, and use the shared automatic overlay protection in Edit, Preview, and public rendering |

## Known implementation debt

This contract is the target behavior, not a claim that every legacy path already
complies. Future work touching these areas must reduce, not copy, the remaining
debt:

- Resolved 2026-07-30: Canvas `activeElementId` is transient everywhere.
  Selection travels through typed editor bindings, never inside `block_data`;
  `website_block_document_sanitizer.dart` strips it type-aware at ingress,
  history, acknowledge, mutations, save capture and the RPC client boundary;
  and a mutation whose sanitized document is unchanged never dirties the
  draft. Selection alone can never enable `Guardar` — do not reintroduce
  persisted selection.
- Canvas edit content still passes through editor decoration that can introduce
  a small inset absent from public rendering. Editor chrome must be overlaid
  around the same content geometry, not change its padding or dimensions.
- Canonical picker uploads now converge on `WebsiteMediaService`: the client
  bounds the editable source, the authenticated `website-optimize-image`
  operation creates an immutable 1920 px WebP plus a library thumbnail, and
  the saved image field receives the WebP URL while source metadata remains
  available for reprocessing. Legacy URL-only fields still need conversion to
  the shared picker when they are touched.
- Resolved 2026-07-30: all 24 registered block families render through the
  shared content renderer in every mode. Edit injects only presenters,
  bindings and chrome; every bespoke `_buildEditableXxx` was deleted with its
  batch. Do not recreate a parallel renderer or runtime migration flag.
- Resolved 2026-07-30: `WebsiteEditModeProvider.mode` is the single
  `public | preview | edit` FSM owner. The URL is an entry command plus a
  write-through projection (`website_editor_mode_route_binding.dart`), the
  shared `WebsiteEditorDocumentBinding` attaches routed page documents, and
  the legacy delayed callbacks, anti-rebounce flags, `provider || URL`
  calculations and mode-driven subtree remounts were removed. Do not add a
  second mode owner, timer or reconciliation flag.
- Some broad architecture suites still contain source-contract assertions.
  Replace the relevant assertion with widget/unit/integration behavior whenever
  that contract is touched.

Intentional edit-mode reductions such as suppressing an entrance animation are
acceptable only when they improve editing stability; the underlying geometry,
content, style, and saved animation setting must still match Preview/public.

## Required change protocol

Before editing:

1. Read this contract, `.github/copilot-instructions.md`,
   `.github/GUI_DESIGN_PRINCIPLES.md`, and
   `docs/architecture/canonical-ui-surfaces.md`.
2. Trace the real route in `app_router.dart`, the live renderer, provider write,
   inspector control, public consumer, and every embedded/quick-action surface.
3. Identify the canonical owner and shared capability. If either is missing,
   add that architecture before creating content that depends on it.

While implementing:

1. Update schema/control/provider/renderer together.
2. Keep Edit, Preview, and public content paths equivalent.
3. Wire block selection, nested selection, repeated selection, and background
   selection.
4. Define clipping and transform behavior at the owning container boundary.
5. Use canonical page/destination/media/theme/action controls.
6. Stage content changes through the global save pipeline.

Before completion:

1. Save, reload, reopen the same control, and confirm complete round-trip.
2. Test the normal page selector and CTA navigation paths, not only direct URLs.
3. Test Edit, Preview, and public rendering at desktop and mobile widths.
4. Test rotated/transformed elements against every bounded edge.
5. Test first click, repeated click, background click, switching blocks, and
   returning from a management workspace.
6. Update `canonical-ui-surfaces.md` when a surface or ownership boundary
   changes.
7. Add or update architecture/widget regression coverage.

## Minimum verification matrix

| Area | Edit | Preview | Published/public |
|---|---|---|---|
| Text, media, theme, CTA values | Control is visible and draft updates immediately | Same visual value, no editor chrome | Same saved value after reload |
| Transform/layout | Same position, scale, rotation, font, fit, and spacing | Matches Edit content geometry | Matches Preview geometry |
| Bounded clipping | No content paints into adjacent blocks | Same boundary | Same boundary |
| Selection | Block, nested element, repeat click, and background open correct inspector | No edit selection | No edit selection |
| Page navigation | Page selector keeps editor context and loads correct data | Correct routed page and filters | Correct routed page and filters |
| Category collection | Presentation controls and actual catalog preview are visible in the canonical catalog workspace | Same hero, breadcrumb, subcategories, facets and grid over public products | Same saved presentation and query-backed products after reload |
| Responsive behavior | Desktop/tablet/mobile controls remain editable | Same visibility and composition | Same visibility and composition |
| Persistence | Global save owns content/config | Saved Preview survives reload | Public result survives reload/cache refresh |
| Page composition | Hidden blocks remain repairable; canonical order/geometry plus chrome | Current-breakpoint public visibility and canonical order/geometry | Same projection after reload; policy trust shell still owns publication/indexability |

Automated guardrails currently include:

- `test/unit/website_builder_workspace_architecture_test.dart`
- `test/unit/website_block_capabilities_test.dart`
- `test/widgets/website_destination_management_page_test.dart`

These tests are guardrails, not a substitute for authenticated visual QA of the
normal click path.

## Interactive UI and UX verification

For editor work, static analysis and source-contract assertions are necessary
but insufficient. Use the strongest available interactive surface after the
fast automated checks:

1. Run focused unit/widget tests and analyzer checks first.
2. Use Flutter widget/integration tests for repeatable selection, save,
   navigation, and state assertions.
3. Exercise the running web editor with browser automation: follow the normal
   signed-in click path, inspect the visible state, type/select values, and take
   screenshots at the points where parity or layout matters.
4. Use native macOS app interaction when a desktop-only shell, zoom boundary,
   native view, or platform-specific input behavior cannot be represented by
   the web build.
5. Convert bugs found interactively into focused widget/golden/integration
   tests so future verification is faster and less dependent on visual review.

The minimum interactive smoke path for a layered carousel change is:

- enter Edit through the normal UI;
- navigate to the target page with the editor page selector;
- select the carousel, a nested element, the same element again, and the slide
  background, confirming the right inspector each time;
- change one reversible value through the visible control and confirm the draft
  canvas;
- open Preview and compare geometry, transform, clipping, theme, and CTA;
- exercise the CTA destination and confirm routed filters/data load;
- return to Edit and confirm selection/control state remains coherent;
- save/reload only when the test scope authorizes persistence, then verify the
  control round-trip; and
- check desktop at both 80% and 100% application zoom plus a compact/mobile
  viewport.

Prefer semantic locators and visible labels over fragile pixel coordinates.
Never treat a screenshot alone as proof that hit testing, keyboard behavior,
navigation, save semantics, or reload persistence works.

## Definition of done

A Website Editor change is complete only when:

- the user can create, inspect, change, remove, and reproduce the result through
  editor-visible controls;
- the selected control and right inspector stay synchronized;
- page and CTA navigation use canonical routed/configuration owners;
- Edit, Preview, and public modes render the same saved content semantics;
- transformed content respects its owning component boundary;
- global theme/media/action/save contracts are reused;
- save/reload round-trips without hidden constants or agent-only state; and
- the relevant route, responsive surfaces, and regression tests pass.

## Autoridad, épocas y lecturas del editor (cierre 2026-07-30)

- `WebsiteEditorCapabilitySnapshot` es tipado (identity/activeTenant/
  storefrontTenant/hasAuthority/authorityEpoch); `granted` y `fingerprint` son
  derivados. Igualdad de autoridad = fingerprint **y** authorityEpoch.
- La adopción de lease hace takeover central: cualquier fingerprint o epoch
  distinto sobre un lease vivo invalida completions (generation), sube la
  identity revision y limpia buckets/owners antes de adoptar.
- Owners tipados: sesión (estampado en el grant) y documento (estampado al
  abrir/activar bajo lease granted). El guardado exige ambos según alcance y la
  verdad del servicio (`currentCapability`) en preflight y por operación
  (`writeGuard`, pre-request y post-response antes de proyección local).
- Lecturas privadas del editor: sólo `load_editor_page_with_blocks` (RPC
  authority-bound, 42501 durable con latch compartido); supersesión tipada para
  completions de identidades anteriores; parser fail-closed tipado.
- Borrado de navegación: sólo `delete_website_navigation`
  (idempotente `deleted|already_absent`; guard estructural en tests).
- Retorno OAuth: intent único tipado con nonce; take-before-await; restauración
  sólo por fallo transitorio clasificado del mismo nonce; validación de
  identidad/tenant/fingerprint antes de cualquier mutación del provider.
  `GoogleBusinessService` instala un single-flight antes de cambiar loading o
  notificar listeners, porque un listener puede reentrar sincrónicamente. Cada
  invocación dueña guarda su nonce en una variable local y sólo hace
  compare-and-clear de ese nonce; el gating de botones es UX secundaria, no el
  lock. La regresión debe cubrir llamadas concurrentes y reentrantes, un solo
  launcher/intent/loading lifecycle, false/cancel/excepción y la supervivencia
  de un intent posterior ajeno.
- Shell del storefront: un Scaffold estable y un anchor de contenido de cadena
  constante para public|preview|edit y todos los device previews; el chrome del
  editor es overlay hermano, nunca padre del contenido enrutado. La cadena
  estable incluye el `PopScope` persistente del guard de navegación y wrappers
  explícitos `SizedBox > DecoratedBox > ClipRect` en el viewport: insertar el
  guard condicionalmente o variar `Container.decoration/clipBehavior` puede
  cambiar la composición interna y remontar un GoRoute aunque el anchor tenga
  la misma key. La regresión obligatoria usa un GoRoute plano, sin shell ni
  keep-alive, y exige State idéntico, texto/foco/scroll preservados y cero
  disposals en Public→Preview→Edit y desktop/tablet/mobile.
