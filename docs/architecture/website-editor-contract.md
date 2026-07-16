# Website Editor Engineering Contract

**Status:** Mandatory for every Website Builder, public storefront, campaign,
and editor-management change  
**Last updated:** 2026-07-14

This document is the current engineering contract for the Viñabike Website
Editor. Read it before changing website editor controls, blocks, renderers,
routes, preview behavior, campaigns, catalog destinations, or storefront theme
behavior. It supersedes older dated notes and code snippets when they conflict.

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

Every change must satisfy all three parts of the existing editor-owned contract:

1. **Owner:** one canonical persisted model owns the value.
2. **Control:** the user can find and change it through the real editor or its
   connected management workspace.
3. **Consumer:** every editor, Preview, and public renderer reads the same value.

## Canonical system map

| Responsibility | Canonical implementation |
|---|---|
| Inline store/editor shell and page-route controller | `PublicStoreLayout` |
| Persistent right inspector | `PersistentEditorShell`, `WebsiteEditorPanel` |
| Draft, page context, selection, history, and global save state | `WebsiteEditModeProvider` |
| Editable block composition and block hit testing | `EditableBlockRenderer` |
| Public block rendering | `WebsiteBlockRenderer` |
| Layered campaign rendering | `CanvasBlock`, `DeferredCanvasBlock` |
| Layered campaign inspector | `_CanvasBlockControls` |
| Typed CTA destinations | `WebsiteLinkValueEditor`, `WebsiteDestination` |
| CTA value and rendering | `WebsiteActionValue`, `WebsiteActionEditor`, `WebsiteActionButton` |
| Global site theme | `WebsiteThemeBuilder` plus saved `website_settings` |
| Page/catalog/navigation management | Website Builder management workspaces registered in `canonical-ui-surfaces.md` |
| Persistence | `WebsiteService.saveEditorChanges(...)` through global `Guardar` |

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

- Raw URL entry may exist only as a collapsed secondary/advanced option.
- Reuse `InlineEditableImage` or the shared schema-routed media control. Never
  create a block-local URL-only dialog.
- Generated or externally sourced assets must enter through the normal media
  upload/storage path and be represented by the same editor control afterward.
- Image value, alt text, focal point, fit, responsive variant, Preview, and
  public rendering must round-trip together.
- Product-linked image layers must continue to show their product owner and use
  the current catalog image; a manual asset may be an explicit fallback.

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
- Route filters selected by a CTA, including category plus brand/search, must
  survive navigation and reopen visibly in `WebsiteLinkValueEditor`.
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
- `Estructura > Páginas` owns CMS page records.
- `Estructura > Navegación y menús` and `website_navigation` own header/footer
  placement and hierarchy.
- `Estructura > Destinos y enlaces` audits CTA/menu destination integrity.
- `Tema` owns global typography, colors, background, and button tokens.
- The visual page editor owns page blocks, slides, and their presentation.

Contextual shortcuts may open these owners. They must not duplicate their data,
save semantics, or business rules.

## Shared capabilities are universal

If a capability exists in more than one block, it must be implemented once and
reused:

| Capability | Shared contract |
|---|---|
| CTA label, destination, and presentation | `WebsiteActionValue`, `WebsiteActionEditor`, `WebsiteActionButton` |
| Destination selection | `WebsiteLinkValueEditor` and typed `WebsiteDestination` |
| Formatted inline text | `InlineEditableTextV2`, `TextFormattingToolbar` |
| Images | `InlineEditableImage` / shared media picker |
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

## Known implementation debt

This contract is the target behavior, not a claim that every legacy path already
complies. Future work touching these areas must reduce, not copy, the remaining
debt:

- Canvas `activeElementId` is intended to be transient, but some provider paths
  can still mark the draft dirty and serialize nested slide selection. Move
  selection to provider-only UI state or strip it recursively from persistence;
  selection alone must never enable `Guardar`.
- Canvas edit content still passes through editor decoration that can introduce
  a small inset absent from public rendering. Editor chrome must be overlaid
  around the same content geometry, not change its padding or dimensions.
- Media upload is not yet one public shared component everywhere:
  `InlineEditableImage` and the inspector's private picker use different upload
  paths, and legacy URL-only fields remain. Consolidate them behind one shared
  picker/storage service before describing the media system as a searchable
  library.
- Save orchestration exists in both `PublicStoreLayout` and
  `PersistentEditorShell`. They currently reach the same service but can drift;
  converge on one save coordinator/result finalizer and verify that failures
  retain every dirty staged bucket.
- Current architecture tests include source-contract assertions. Add real
  widget/golden/integration coverage for transform parity, bounded clipping,
  repeated nested selection, picker interaction, routed product loading,
  global theme reach, and save/reload round-trip.

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
| Responsive behavior | Desktop/tablet/mobile controls remain editable | Same visibility and composition | Same visibility and composition |
| Persistence | Global save owns content/config | Saved Preview survives reload | Public result survives reload/cache refresh |

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
