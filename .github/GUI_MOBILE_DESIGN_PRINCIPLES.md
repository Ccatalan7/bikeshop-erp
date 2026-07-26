# Mobile and Tablet GUI Design Principles — Viñabike ERP

This is the canonical composition and interaction guide for phone, tablet, and
responsive ERP work.

Read it together with
[`GUI_DESIGN_PRINCIPLES.md`](GUI_DESIGN_PRINCIPLES.md). The general guide owns
the visual language, color, typography, spacing, common accessibility,
overlays, popovers, and rules that apply on every platform.
This guide owns phone and tablet composition and interaction. It references
the general guide instead of copying those recipes.

Business entry points and action parity are registered separately in
[`docs/architecture/canonical-ui-surfaces.md`](../docs/architecture/canonical-ui-surfaces.md).
That registry owns routed, embedded, split-pane, quick-action, desktop, tablet,
and phone surface coverage.
This guide does not own business rules, commands, persistence, or routing.
Responsive surfaces must compose the same canonical commands, permissions, and
persistent effects registered there.

## Scope and ownership

Use this guide whenever a change affects any of the following:

- a phone or tablet route;
- a breakpoint, compact host, responsive branch, or adaptive navigation;
- touch interaction, virtual-keyboard behavior, SafeArea, or compact scrolling;
- a desktop table or form that must be recomposed for a narrower surface; or
- context preservation between a compact list and its details or editors.

The ownership boundary is deliberate:

- `GUI_DESIGN_PRINCIPLES.md` owns shared visual and accessibility rules.
- `GUI_MOBILE_DESIGN_PRINCIPLES.md` owns compact composition, touch workflow,
  responsive state preservation, compact forms, and the required width matrix.
- `canonical-ui-surfaces.md` owns which business surfaces and actions must
  exist and which canonical implementation each surface composes.
- Feature architecture documents own domain truth and command boundaries.

If a rule applies identically everywhere, put it in the general guide and link
to it here. If it exists because phone or tablet constraints change the
composition or interaction, put it here and link to it from the general guide.
Do not maintain two copies of the same recipe.

## Product priority and responsive classes

macOS desktop remains the operational priority for dense, high-throughput ERP
work. Phone and tablet are still first-class product surfaces: every route that
can be opened there must have an intentional, efficient, user-friendly
composition.

Classify the available content width from real layout constraints, not from the
operating-system name:

- phone: `<600px`
- tablet: `600-899px`
- desktop: `>=900px`

A feature may use an additional internal breakpoint only when its content
requires one. The exception must be named in
`canonical-ui-surfaces.md`, must not redefine the three product classes, and
must have boundary tests.

Responsive design is not:

- shrinking a desktop table until it technically fits;
- placing a desktop table inside automatic horizontal scroll on phone;
- stretching phone cards across a desktop window;
- hiding a desktop action without giving touch users another clear path; or
- using one operating-system check as a substitute for measuring constraints.

Desktop, tablet, and phone may present information differently. They must share
the same domain read model, permission checks, commands, idempotency behavior,
validation, and persistent effects.

## Start with the operating loop

Before laying out a compact screen, identify:

1. the record identity the operator scans for;
2. the state or exception that changes the next decision;
3. the related entity needed to recognize the work;
4. the two or three actions performed repeatedly;
5. the secondary information that is useful only after intent; and
6. the list context that must survive a detail round trip.

The first read of an operational record should normally expose:

- identity;
- current state;
- primary related entity;
- the most important monetary, timing, or workflow exception; and
- frequent direct actions.

Do not make the operator open a generic detail form merely to change status,
inspect prices, identify the related bicycle/customer/document, or reach the
normal next action.

## Dedicated phone composition

### Dense lists and cards

A desktop data table normally becomes an editable, scannable phone list. Each
record should be one coherent surface, not a stack of cards within cards.

Use:

- one clear identity/header line;
- restrained tonal separation or a subtle divider between records;
- one compact semantic state treatment;
- deliberate typography and spacing hierarchy;
- a small, labelled frequent-action rail when several destinations matter; and
- one clearly labelled disclosure for secondary detail.

Avoid:

- card inside card;
- chip walls;
- a border around every field and row;
- the same decorative icon repeated beside every label;
- rainbow status/action palettes;
- a completely flat white block where record boundaries disappear;
- permanently expanded narratives and lifecycle metadata; and
- rows so tall that ordinary work cannot be scanned.

Neutral-first does not mean monochromatic or lifeless. Follow the color rules
in `GUI_DESIGN_PRINCIPLES.md`: use restrained tonal depth to separate command
and record surfaces, one deliberate accent for the primary action, and
low-saturation semantic color only for real state or exceptions.

### Progressive disclosure

Information that is useful but not required for the first decision belongs in
a clearly labelled, in-place disclosure. Examples include:

- customer request or long description;
- full lifecycle timing;
- deadline history;
- detailed paid/balance projection;
- technical trace; and
- low-frequency secondary commands.

The label must describe what opens; an unlabelled chevron is not enough when
the content is not obvious. Expanding or collapsing a record must preserve its
identity and the list scroll position.

Use an overflow menu or bottom sheet for low-frequency commands when an inline
rail would become crowded. Keep the menu grouped and labelled; moving a chip
wall into a sheet is not simplification.

### Tables and line editors

Do not automatically wrap a desktop table in horizontal scroll for phone.
Recompose each row into a vertical editor that preserves every operative field
and action through the same controllers and callbacks.

For editable line items, retain as applicable:

- product/service identity and configuration;
- quantity or hours;
- unit price and discount;
- line total;
- stock or validation warning;
- ordering; and
- removal.

The mobile editor must preserve stable line identity and hidden domain metadata
even when those values are not visible controls. It must never introduce a
mobile-only writer.

Horizontal panning is acceptable only when the content itself is spatial, such
as a timeline, spreadsheet, image canvas, or other registered exception. The
phone composition must still provide touchable controls and an obvious
orientation aid around that spatial viewport.

## Tablet composition

Tablet is not an oversized phone and not a squeezed desktop.

At `600-899px`, choose the composition that supports the task:

- a compact list with more metadata per row;
- a reduced-column table with an explicit record inspector;
- a two-pane layout only when both panes retain useful touch widths; or
- a phone-style list with an inline workspace when rapid return matters more
  than simultaneous visibility.

Do not create an arbitrary extra column merely because space exists. Do not
retain a desktop toolbar if its hover, secondary-click, or tiny icon affordances
are the only way to operate the record.

## In-page and in-block navigation

High-frequency list → work → list loops should normally preserve the host
instead of replacing the route.

The approved compact workspace pattern is:

1. the list host retains scope, view, search, filters, selection, disclosures,
   and its scroll controller;
2. a direct record action replaces only the list body with the canonical child
   editor, detail, or preview;
3. the child renders without a nested application shell or top-level
   `Scaffold`;
4. a minimal, labelled back control returns through the host callback;
5. a successful save refreshes authoritative data and returns automatically;
6. cancel/back leaves persistent data unchanged; and
7. a child with unsaved mutable state owns an explicit discard guard; and
8. an open mutable child stays mounted when constraints cross a breakpoint
   until save, cancel, or confirmed discard completes.

Use the same canonical form/editor used by routed or desktop surfaces. An
inline host is a composition boundary, not permission to create a reduced
mobile editor with different validation.

Never let a `LayoutBuilder` branch silently dispose an open draft. If retaining
the child is impossible, move the draft through an explicit state owner and
apply the same discard contract before changing composition.

Document previews should prepare their bytes or model without launching an
export side effect. Opening the inline preview must not automatically open a
file picker or share sheet; export/share remains an explicit action.

Use a full route when the workflow genuinely needs a durable deep link,
cross-module history entry, independent task context, or more space than the
host can responsibly provide. Even then, returning must restore the originating
list context.

## Navigation and context preservation

The following state must survive list → detail/editor → list unless the user
explicitly resets it:

- search query;
- scope and tabs;
- selected view;
- advanced filters and sorting;
- selected or expanded record;
- loaded-page/window state where relevant; and
- scroll position.

Keep the state with the list owner. Do not reconstruct it from visible labels
or from a child editor. Do not reset it merely because an inline workspace
temporarily replaced the body.

Back behavior must be predictable:

- system back and visible back invoke the same host contract;
- while saving, prevent a second close or duplicate command;
- if there are unsaved edits, explain the discard consequence;
- after successful save, return once, refresh once, and keep the prior context;
  and
- after an error, remain in the editor with the user's input intact.

## Touch actions and navigation

Every touch target must be at least `48px` in both dimensions, including icon
buttons, row actions, disclosure triggers, drag/reorder alternatives, and
compact navigation.

No important action may depend only on:

- hover;
- secondary click;
- a keyboard shortcut;
- a desktop-only column; or
- an icon whose meaning is ambiguous without a label.

Prefer text-first controls for high-frequency compact actions. Icon-only
controls are acceptable only for universally understood actions, and they still
need a semantic label. Tooltips may support desktop discovery but do not make
an ambiguous touch icon understandable.

Place frequent actions near the record they affect. Use a bottom sheet for
bounded secondary action sets or selectors that need more vertical room. Use a
full-screen or routed flow only when the task itself needs that focus.

For drag/reorder behavior, provide a touch alternative such as labelled move
up/down controls when precise drag is not reliable or accessible.

## Forms, focus, and the virtual keyboard

Compact forms must be designed with the keyboard open, not only with an empty
viewport.

Required behavior:

- wrap the composition in the correct `SafeArea`;
- keep the focused field and its validation message visible;
- scroll focused controls above the virtual keyboard;
- use a predictable focus/traversal order;
- choose input types and IME actions that match the data;
- never let a sticky footer or save action become unreachable behind the
  keyboard or system inset;
- preserve entered data on validation or transport failure; and
- dismiss the keyboard intentionally when moving to a non-text step.

Stack fields that no longer scan as a coherent row. Do not keep a two-column
desktop form merely because each text field can shrink.

Validation must remain visible next to the affected field. Snackbars can
summarize an outcome but cannot replace field-level errors.

Test at increased text scale. Labels, errors, totals, and action text must wrap
or reflow without clipping, ellipsis that removes the decision, or overlapping
controls.

## SafeArea, scrolling, and fixed actions

Apply system insets exactly once at the correct host. Nested compact children
must not each add a second SafeArea and waste usable height.

Use one primary vertical scroll owner per focused phone surface. Nested
scrollables need a clear reason, bounded height, and tested gesture behavior.
Do not place a full list inside another unbounded list.

When a save/confirm action is fixed:

- reserve its actual height in the scroll content;
- include the bottom SafeArea inset;
- keep validation and the last field reachable above it;
- disable it while the command is in flight; and
- do not cover contextual actions or totals.

Preserve scroll position with a stable controller owned by the list or form,
not a controller recreated on every responsive rebuild.

## Menus, selectors, sheets, and overlays

Shared overlay geometry, focus, dismissal, semantics, and primitive selection
remain owned by
[`GUI_DESIGN_PRINCIPLES.md`](GUI_DESIGN_PRINCIPLES.md#13-anchored-popovers-menus--pickers).

For compact composition:

- prefer a bottom sheet when a selector needs search, explanations, grouped
  options, or comfortable touch spacing;
- keep short, obvious actions in a bounded menu;
- use an inline disclosure when the information belongs to the current record
  and does not need a separate decision surface;
- restore focus and context when a sheet/menu closes;
- respect top and bottom SafeArea insets; and
- constrain and scroll long content inside the sheet.

A selector must expose the current value and the available alternatives.
Hiding a business state behind an unlabelled ellipsis is not an acceptable
compact design.

## Accessibility and semantics

Common contrast, color-independent meaning, keyboard, focus, and semantics
rules remain owned by the general guide. Compact surfaces additionally require:

- semantic labels for icon-only controls and status actions;
- one meaningful record grouping so screen readers do not announce decorative
  containers as separate cards;
- a logical reading order matching the visible decision order;
- state changes announced when an inline workspace replaces the list;
- expanded/collapsed semantics on disclosures;
- selected semantics on scope/view controls; and
- no important information encoded only by position, color, or swipe.

Verify touch targets, text scale, screen-reader labels, and keyboard traversal
with the real compact host. A source-code label is not proof that the resulting
semantics tree is usable.

## Loading, empty, error, and offline states

Design these states as part of the surface:

- **Loading:** retain enough structure to explain what is loading; avoid a
  blank route-wide spinner when cached list context can remain visible.
- **Empty:** distinguish a truly empty dataset from filters with zero matches.
  Keep the relevant filter/reset or create action available.
- **Error:** preserve prior valid data when possible, name the failed operation,
  and provide a bounded retry.
- **Offline or outcome unknown:** distinguish “not sent,” “rejected,” and
  “possibly committed.” Do not claim rollback or enable blind duplicate writes.

An optional projection failure must not turn an authoritative base query into a
false empty list. Loading/error placeholders must not change the layout so
dramatically that controls jump beneath the user's finger.

## Required validation matrix

Every affected compact workflow must be checked at:

- approximately `384x824` for the phone canary;
- `599px` and `600px`;
- `899px` and `900px`; and
- approximately `1440x900` for the desktop regression canary.

Use the real application chrome and real routed/embedded host. An isolated card
at 384px is not evidence that the operational route fits after navigation,
workspace tabs, toolbars, SafeArea, and other fixed UI consume space.

Minimum interaction coverage:

- open the route through the normal employee path;
- use search/scope/view/filter controls;
- open each affected direct action by touch/click;
- exercise disclosure, menu/sheet, and back behavior;
- verify list context after return;
- edit representative fields without committing production data;
- open and close the virtual keyboard where a form is affected;
- inspect loading, empty, error, and offline/outcome-unknown states through
  widget fixtures or controlled test doubles;
- cross at least one responsive boundary with both a clean and a dirty inline
  workspace, proving that recomposition neither loses the draft nor bypasses
  its discard guard;
- run with increased text scale and inspect semantics labels; and
- inspect runtime logs for overflow, clipping, layout, focus, and semantics
  exceptions.

For dense operational lists, record how many ordinary collapsed records are
fully visible in the first phone viewport after real chrome. The number is not
a universal quota, but seeing only two ordinary records is a warning that
secondary detail should move behind disclosure.

Analyzer success and screenshots are not sufficient. At least one real
interaction pass and focused widget tests are required.

## Implementation discipline

- Branch on `LayoutBuilder` constraints local to the surface whenever parent
  chrome can change usable width.
- Keep compact state in the canonical host or shared controller, not in a
  second business provider.
- Reuse canonical child forms/editors through explicit embedded/compact
  contracts.
- Avoid nested `Scaffold`, duplicate `AppBar`, duplicate navigation, and
  parallel save callbacks.
- Keep stable keys/semantic labels for back, save, disclosures, menus, and
  compact line editors so behavior is testable.
- Treat phone, tablet, desktop, routed, embedded, split-pane, and quick-action
  hosts as separate registered compositions where the same business action is
  reachable.
- Update `canonical-ui-surfaces.md` whenever an entry point, host composition,
  or action location changes.

## Validated learning record

When a mobile interface takes several iterations to reach a satisfactory
result, add one reusable record here after the final behavior is validated.
Do not document every discarded experiment.

Every record must contain these exact fields:

- **Problem observed**
- **Cause**
- **Approved pattern**
- **Anti-pattern**
- **Reference implementation**
- **Minimum test**

### Dense workshop records and inline workspaces

- **Problem observed:** A phone operator could see only about two ordinary Jobs
  records in the first viewport, record boundaries were weak, and reaching job
  lines, invoices, or proposal documents replaced the list context.
- **Cause:** Desktop fields and secondary detail were stacked into permanently
  tall cards; visual restraint was interpreted as a flat monochrome wireframe;
  direct actions delegated to routed/desktop inspectors instead of a compact
  host composition; and a responsive branch could otherwise unmount a dirty
  child when its constraints crossed the desktop threshold.
- **Approved pattern:** Use one compact tonal record surface with identity,
  interactive state, primary object, date/financial exception, and a labelled
  direct-action rail in the first read. Put narrative, lifecycle timing, and
  full financial detail in one in-place disclosure. Let `Trabajo`, `Ítems`,
  `Factura`, and `PDF` replace only the list body with their canonical form,
  editor, or side-effect-free preview; minimal back and successful save return
  to the preserved list owner. Keep that inline child mounted across breakpoint
  changes until save, cancel, or confirmed discard resolves the draft. Within
  the tablet product class, Jobs uses its documented `720px` content exception:
  `600-719px` keeps one compact column, while `720-899px` pairs the same cards
  in two columns so tablet width improves scanning instead of stretching a
  phone card. Both variants retain the same scroll owner and actions.
- **Anti-pattern:** Rainbow icons/chips; monochrome outlined field walls;
  repeated blue icons; card-in-card nesting; permanently expanded metadata;
  horizontal desktop line tables on phone; detours through a generic desktop
  detail pane; a reduced mobile writer; or branch-driven disposal of a dirty
  editor during resize; or stretching a single phone card across a wide tablet
  and leaving its decision content stranded at opposite edges.
- **Reference implementation:**
  `lib/modules/bikeshop/pages/pegas_table_page.dart`,
  `lib/modules/bikeshop/pages/mechanic_job_form_page.dart`, and
  `lib/modules/sales/widgets/sales_invoice_editor.dart`.
- **Minimum test:** At `384x824`, prove at least three ordinary collapsed
  records remain scannable after real chrome; open and return from Trabajo,
  Ítems, Factura, and proposal PDF; preserve scope/view/search/filters,
  disclosures, and scroll; verify editable mobile line cards below 600px; run
  `599/600`, verify the registered tablet grid at `719/720`, including an odd
  record count and an expanded card, cross `899/900` with a dirty draft still
  mounted and guarded, run increased text scale/semantics, and verify the
  `1440x900` desktop regression with no layout or runtime exceptions.

### Compact application chrome and tool workspaces

- **Problem observed:** On phone and tablet, the desktop workspace tab strip,
  the persistent right tool rail, the `MainLayout` app bar, and successive Jobs
  command rows consumed roughly a third of the first viewport before any
  operational record appeared.
- **Cause:** Global desktop chrome was mounted independently of the compact
  route composition. Its workspace history, tab creation, screenshot, settings,
  and tool shortcuts remained permanently visible even when the same route
  already provided compact navigation and the available width could support
  only one focused task. The application-wide zoom scope also rewrites
  descendant `MediaQuery.size`; comparing that zoomed logical width directly to
  `900px` can activate desktop chrome inside a tablet-sized unzoomed viewport.
  Applying the desktop `0.8` transform to an otherwise correct compact
  composition also turns a declared `48px` control into an approximately
  `38.4px` physical touch target.
- **Approved pattern:** Below `900px`, do not mount a persistent workspace tab
  strip or right tool rail. The existing `MainLayout` drawer is the single
  compact shell and exposes clearly labelled `Navegación` and `Herramientas`
  modes. Selecting a tool closes the drawer and opens that canonical tool as a
  full-size workspace while the originating route, filters, selection, inline
  draft, and scroll owner remain mounted for return. If more than one workspace
  exists, expose a labelled selector on demand rather than restoring a
  permanent tab row. At `>=900px`, preserve the dense desktop tab strip and
  right rail. Responsive composition uses the unzoomed logical viewport
  (Flutter/CSS pixels) from the shared responsive-width owner, never the
  zoom-adjusted descendant `MediaQuery` alone. Hardware panel resolution is not
  a composition breakpoint: a 1440-pixel-wide S23 Ultra panel at DPR 3.75 is a
  384px phone viewport. The effective application scale is `1.0` below `900px`;
  the stored browser-style zoom remains a desktop preference at `>=900px`.
  Keep the zoom wrapper topology stable across the boundary so a resize changes
  composition without recreating the navigator, workspace stack, listeners, or
  an open draft. The authenticated root likewise keeps one stable shell slot:
  only its zero-height/tab-strip slot changes, while the kept-alive workspace
  stack retains a stable global identity as it moves between compact and
  desktop toolbar compositions. Before the first Jobs record, compact
  composition may expose at most two command surfaces: one
  application/workflow header and one scope/view/filter surface.
- **Anti-pattern:** Shrinking the desktop tab strip; leaving an icon rail
  permanently beside phone content; relying on an edge swipe as the only tool
  entry; opening a tool by replacing or disposing the active route; hiding
  additional workspaces without a selector; duplicating settings/navigation in
  stacked app bars; adding a separate row for every compact command group; or
  allowing a persisted zoom preference to move the `899/900` breakpoint;
  declaring a `48px` target above a compact `Transform.scale(0.8)`; or changing
  wrapper ancestry or moving an unkeyed workspace stack at the breakpoint and
  silently remounting application state.
- **Reference implementation:** `lib/main.dart`,
  `lib/shared/services/window_zoom_service.dart`,
  `lib/shared/utils/responsive_viewport.dart`,
  `lib/shared/widgets/window_zoom_scope.dart`,
  `lib/shared/widgets/workspace_tab_bar.dart`,
  `lib/shared/widgets/right_toolbar.dart`,
  `lib/shared/widgets/main_layout.dart`, and
  `lib/modules/bikeshop/pages/pegas_table_page.dart`.
- **Minimum test:** At `384x824`, `599/600`, and `899px`, verify that neither
  desktop chrome surface is persistent, both drawer modes and their semantic
  labels are reachable through `48px` targets, a selected tool fills the
  workspace, and return restores the exact mounted route/context. Create more
  than one workspace and verify the on-demand selector. Assert no more than two
  command surfaces precede Jobs content. At `900px` and `1440x900`, verify that
  desktop tabs and the right rail remain available, then cross `899/900` with
  default and non-default zoom values. Assert an effective scale of `1.0` below
  `900px`, the selected desktop scale at and above `900px`, real `48px` compact
  targets, and one continuously mounted stateful subtree. Cross from a
  scrolled/expanded Jobs list through `899/900` and back without a transient
  empty reload, preserving route, filters, scroll, disclosure, and dirty inline
  state with no overflow, clipping, layout, or semantics exception.

## Definition of done

A mobile, tablet, or responsive UI change is complete only when:

- phone, tablet, and desktop compositions are deliberate;
- every important action remains reachable without hover or secondary click;
- canonical commands, permissions, validation, and persistence are reused;
- touch targets, SafeArea, keyboard, focus, scrolling, and text scale are
  verified;
- list context survives the documented round trip;
- loading, empty, error, and offline states are covered;
- there is no overflow, clipping, hidden control, layout/semantics exception,
  or keyboard-obscured action;
- focused widget tests and analyzer pass;
- the required real interaction and width matrix pass;
- `canonical-ui-surfaces.md` reflects the affected hosts; and
- any multi-iteration learning is captured once in the validated record format
  above.
