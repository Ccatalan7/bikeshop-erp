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

Operational priority does not make the current desktop widget visual or
navigation authority. Apply the general guide's
`Legacy consistency is not approval` rule before adapting a workflow: preserve
canonical business behavior, remove shared or desktop debt that is in scope,
then compose each viewport from the validated operating loop.

Classify the available content width from real layout constraints, not from the
operating-system name:

- phone: `<600px`
- tablet: `600-899px`
- desktop: `>=900px`

A feature may use an additional internal breakpoint only when its content
requires one. The exception must be named in
`canonical-ui-surfaces.md`, must not redefine the three product classes, and
must have boundary tests.

Width class does not prove input capability. Detect or design explicitly for
the capabilities the host actually offers:

- mouse, trackpad, hover, keyboard, shortcuts, and secondary click;
- touch, system Back, gestures, SafeArea, and the virtual keyboard; and
- browser history, deep links, text scale, and reduced motion.

macOS, Windows, iOS, and Android share business rules, but they do not need
identical affordances. Do not enable a hover-dependent control merely because
a tablet crossed a width boundary, and do not remove keyboard efficiency from a
touch-capable desktop.

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
4. the actions performed repeatedly and their relative frequency;
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
- direct access to the actions that genuinely dominate the workflow;
- an action rail only when several repeated, peer destinations justify the
  permanent row it consumes; and
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
in `GUI_DESIGN_PRINCIPLES.md`: use the theme's coherent accent and semantic
roles, restrained tonal depth, and purposeful emphasis. Do not turn one accent
into a repeated blue personality layer, and do not remove all color in the name
of restraint.

An action rail is not a default card footer or a miniature tab bar. If a
sensible row target, one direct action plus overflow, or an in-place control
supports the task with less height, prefer that composition.

### Use the available width

Compact does not mean narrow and centered.

- Remove duplicated gutters and padding introduced by nested hosts.
- Let forms, editors, lists, and workspaces use the safe content width
  responsibly.
- Avoid a desktop max-width wrapper that leaves a phone editor in a thin central
  column.
- Do not stretch small controls merely to fill space; allocate width according
  to reading order, touchability, and content value.
- Test the real route after drawers, system insets, and host chrome consume
  their share of the viewport.

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
- a two-pane layout only when repeated comparison or list-detail work benefits
  from simultaneous visibility and both panes retain useful touch widths; or
- a phone-style list with an inline workspace when rapid return matters more
  than simultaneous visibility.

Do not create an arbitrary extra column merely because space exists. Do not
retain a desktop toolbar if its hover, secondary-click, or tiny icon affordances
are the only way to operate the record.

These are options, not tablet templates. A long list, by itself, does not force
a split pane; selection frequency, comparison value, task depth, and useful
pane width must justify it.

## In-page and in-block navigation

High-frequency list → work → list loops should normally preserve the host
instead of replacing the route.

When the task evidence favors an inline or in-page workspace, its contract is:

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
host exactly—not a generic root or canonical list for the entity that was
visited.

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

For cross-module navigation, also retain the originating module and its return
contract. Visiting a customer, bicycle, invoice, or document from a workflow
must not make Back fall through to that entity's generic list.

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

Text-first does not mean wrapping every command in an outlined pill. A labelled
row target, an inline value/action pair, one primary control with a secondary
menu, or a compact toolbar may create clearer hierarchy with less visual noise.

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
[`GUI_DESIGN_PRINCIPLES.md`](GUI_DESIGN_PRINCIPLES.md#11-anchored-popovers-menus-and-pickers).

For compact composition:

- prefer a bottom sheet when a selector needs search, explanations, grouped
  options, or comfortable touch spacing;
- keep short, obvious actions in a bounded menu;
- use an inline disclosure when the information belongs to the current record
  and does not need a separate decision surface;
- restore focus and context when a sheet/menu closes;
- respect top and bottom SafeArea insets; and
- constrain and scroll long content inside the sheet.

The same canonical command may use an anchored popover with pointer input and a
sheet on phone. The surface changes; ownership, permission, validation, and
persistence do not.

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

## Compact motion and continuity

Use brief motion to make it clear that a list host remains mounted while an
inline workspace, disclosure, selector, or detail replaces part of it.

- Animate the changed region, not the entire application shell.
- Preserve scroll, selection, focus intent, and draft ownership across the
  transition.
- Do not add animation merely to make a navigation feel more substantial.
- Respect reduced motion and keep the state transition understandable with
  animation disabled.

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

The records below describe the named surfaces and the conditions recorded in
their approved pattern. They are evidence, not universal templates. Do not copy
their action rails, inline workspaces, breakpoints, cards, or compact chrome
into another workflow without repeating the task analysis required by the
general guide.

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
  lines, invoices, or proposal documents replaced the list context. Deeper
  inspection then exposed page-sized branded loaders inside individual
  bicycle fields, a permanently expanded technical-context block before the
  operative job fields, payment navigation that discarded the inline invoice,
  and multi-bicycle actions that could reopen the primary bicycle instead of
  the one the operator selected. The embedded job editor also inherited
  desktop-sized section flow: some workbench tabs were difficult to reach,
  diagnosis led with a large diagram instead of findings, validation could
  leave the responsible field off-screen, and Back could discard a real draft.
- **Cause:** Desktop fields and secondary detail were stacked into permanently
  tall cards; visual restraint was interpreted as a flat monochrome wireframe;
  direct actions delegated to routed/desktop inspectors instead of a compact
  host composition; and a responsive branch could otherwise unmount a dirty
  child when its constraints crossed the desktop threshold. Generic page
  loaders were also reused as field placeholders, desktop context summaries
  were mounted without a phone disclosure, nested tasks escaped through the
  router, and a job-level primary relation was treated as if it identified
  every clicked related row. The editor breakpoint and scroll behavior were
  owned by inner sections rather than one compact workbench contract.
- **Approved pattern:** Use one compact tonal record surface with identity,
  interactive state, primary object, date/financial exception, and a labelled
  direct-action rail in the first read. Put narrative, lifecycle timing, and
  full financial detail in one in-place disclosure. Let `Trabajo`, `Ítems`,
  `Factura`, and `PDF` replace only the list body with their canonical form,
  editor, or side-effect-free preview; minimal back and successful save return
  to the preserved list owner. Compact filter composition keeps the canonical
  desktop predicates and operators while expressing them in task language
  suited to touch. When an include/exclude mode only has meaning after a choice
  exists, reveal a clearly labelled contextual toggle beside that choice group
  instead of forcing abstract query vocabulary into a permanent control. Keep
  that inline child mounted across breakpoint changes until save, cancel, or
  confirmed discard resolves the draft. A related object opens directly when
  unambiguous; multiple objects use a touch-safe labelled selector and pass the
  exact selected identity into the same embedded canonical editor. A field
  awaiting reference data keeps field-sized geometry and announces that local
  loading state instead of inserting a page loader. On phone, technical
  context begins as identity plus the first actionable exception and a count;
  the full context and existing commands expand in place. Its canonical bike
  editor uses a dedicated phone/tablet section composition and keeps one
  labelled return control reachable from every section; that control returns
  to the immediate list host instead of delegating to browser history. A
  nested canonical task such as invoice payment becomes another inline
  workspace state: Back
  returns to its immediate parent editor, while success returns to the list and
  refreshes once. The embedded job workbench owns one compact composition
  through `899px`, with complete `General`, `Diagnóstico`, and `Ítems` tabs.
  Diagnosis begins with the selected system and editable findings; the bicycle
  diagram is a labelled disclosure. Validation selects and scrolls to the
  section that owns the error, while Back/cancel guard a dirty draft in routed
  and embedded hosts. At increased text scale, bounded selections elide safely
  and peer action groups reflow rather than clip. Within the tablet product
  class, Jobs uses its documented `720px` content exception:
  `600-719px` keeps one compact column, while `720-899px` pairs the same cards
  in two columns so tablet width improves scanning instead of stretching a
  phone card. Both variants retain the same scroll owner and actions.
- **Anti-pattern:** Rainbow icons/chips; monochrome outlined field walls;
  repeated blue icons; card-in-card nesting; permanently expanded metadata;
  horizontal desktop line tables on phone; detours through a generic desktop
  detail pane; a reduced mobile writer; or branch-driven disposal of a dirty
  editor during resize; simplifying mobile filters by dropping include/exclude
  semantics; mechanically copying database-style operator labels when a clear
  action phrase communicates the same rule; or stretching a single phone card
  across a wide tablet and leaving its decision content stranded at opposite
  edges. Do not use a full-page branded loader inside a single field, repeat a
  desktop chip wall before the actual task, route a nested step so cancel loses
  its parent editor, infer a clicked related record from the job primary key,
  hide text-scaled controls behind a horizontal overflow, hide editor sections
  behind inherited desktop scroll offsets, lead diagnosis with a decorative
  diagram, or let Back dispose a dirty embedded draft.
- **Reference implementation:**
  `lib/modules/bikeshop/pages/pegas_table_page.dart`,
  `lib/modules/bikeshop/widgets/workshop_status_filter_header.dart`,
  `lib/modules/bikeshop/widgets/workshop_mobile_bike_chooser.dart`,
  `lib/modules/bikeshop/widgets/workshop_mobile_payment_workspace.dart`,
  `lib/modules/bikeshop/pages/bike_form_dialog.dart`,
  `lib/modules/bikeshop/pages/mechanic_job_form_page.dart`, and
  `lib/modules/sales/widgets/sales_invoice_editor.dart`.
- **Minimum test:** At `384x824`, prove at least three ordinary collapsed
  records remain scannable after real chrome; open and return from Trabajo,
  Ítems, Factura, and proposal PDF; preserve scope/view/search/filters,
  disclosures, and scroll; select a grouped filter, toggle its labelled
  exclusion mode, close and reopen the filter surface, and prove that the same
  canonical predicate and persisted state are used; verify editable mobile
  line cards below 600px; run `599/600`, verify the registered tablet grid at
  `719/720`, including an odd record count and an expanded card, cross
  `899/900` with a dirty draft still mounted and guarded, run increased text
  scale/semantics, and verify the `1440x900` desktop regression with no layout
  or runtime exceptions. Delay bicycle brand/model futures and prove each
  placeholder retains field height; select the second of multiple linked
  bicycles and prove that exact aggregate editor opens; navigate that editor to
  a later technical section and use its visible return control to restore the
  immediate Jobs host; expand/collapse job context; exercise all three
  job-workbench tabs, validation focus, diagnosis disclosure, dirty
  Back/cancel, text scale, keyboard, and SafeArea at the same width matrix; and
  exercise Factura → abono → Back, proving Back restores the invoice and only
  successful completion refreshes the Jobs owner.

### Task queues choose their own collection archetype

- **Problem observed:** The compact Tasks view rendered every task as a tall,
  bordered card with repeated red treatment and form-like metadata. Only about
  three tasks were scannable in the first phone viewport, even though the
  operator's dominant loop is to scan, complete, and spot timing exceptions.
- **Cause:** “Mobile” was treated as synonymous with “cards”, and the existing
  desktop controls were treated as visual precedent before auditing the task's
  operating loop. Atomic task rows and secondary edit controls therefore
  received equal visual weight.
- **Approved pattern:** Choose list, row, card, pane, or another container only
  after identifying scan frequency, comparison needs, action frequency, and
  record complexity. For this task queue, use one grouped task-manager list:
  completion, title, and the timing exception own the collapsed row; state,
  priority, date, assignment, attachments, links, and destructive actions open
  through a labelled inline disclosure. Preserve expanded rows, filters,
  search, and scroll in the parent session. Desktop and compact presentations
  reuse the same `TaskService` commands and theme roles, but either composition
  may remove or redefine legacy visual debt independently.
- **Anti-pattern:** Assuming every compact collection needs cards; copying a
  desktop table or its outdated dropdown hierarchy without re-evaluating it;
  wrapping each atomic task in a bordered block; using a full-record error
  border for one overdue date; or repeating accent color on every disclosure
  label.
- **Reference implementation:**
  `lib/modules/bikeshop/widgets/pegas_tasks_widget.dart`.
- **Minimum test:** At `384x824`, prove eight ordinary collapsed task rows are
  fully visible after real host chrome; exercise completion and the labelled
  disclosure; edit status, priority, date, assignment, attachments, links, and
  actions through touch targets of at least 48px; preserve expanded state,
  search, filters, and scroll across a mode round trip; run increased text
  scale plus `599/600`, `899/900`, and `1440x900`; and verify that desktop still
  invokes the same canonical commands without inheriting compact-only layout.

### Identity workspaces expose purpose before completeness

- **Problem observed:** The self-profile rendered identity, employment,
  access, permissions, and security as one long information dump, while user
  administration led with a branded banner, dashboard-like metric blocks,
  repeated chips, and a wall of peer actions. On compact widths, the operator
  could not quickly distinguish audience, selected identity, current access
  state, and the next valid action. Contextual links could also open the
  generic administration route and silently select the first unrelated record.
- **Cause:** The UI was composed from the response payload and a component
  catalog instead of the identity decision being made. Decorative containers
  carried hierarchy that the information architecture did not, desktop
  selection state was mistaken for navigation identity, and no transient route
  contract named the exact staff, customer, invitation, or workforce target.
- **Approved pattern:** Keep one compact identity summary and expose one
  clearly labelled profile section at a time, preserving drafts and the
  authoritative read model across section and breakpoint changes. Treat user
  administration as a searchable audience-and-identity workflow: integrate
  useful counts into audience navigation, make the current state and next valid
  action clear, group permissions behind a labelled disclosure, and separate
  destructive access changes from ordinary maintenance. At `>=900px`, use a
  master-detail split only because repeated identity comparison and successive
  administration benefit from keeping the filtered collection visible; below
  `900px`, use an in-page list → detail transition with a labelled return and
  preserved search, audience, selection, and scroll. A contextual handoff
  carries an exact opaque target through a one-use request, keeps personally
  identifying data out of the URL, fetches a CRM-only customer when needed,
  and reports an unavailable target instead of falling back to another row.
  This is a validated identity-workspace composition, not a universal
  split-pane rule. Tooltips may clarify secondary consequences on pointer
  surfaces, but visible labels and inline context must carry the decision.
- **Anti-pattern:** A hero or KPI row before ordinary identity work; one card,
  chip, icon square, or button per payload field; exposing every profile
  section simultaneously; squeezing list and detail together on phone;
  selecting the first record when a deep-link target is missing; putting names
  or email addresses in navigation state; using tooltips as the only
  explanation; or copying the desktop split into an unrelated settings page
  without repeated comparison evidence.
- **Correction (2026-07-27):** "One section at a time" bounds *what* is shown,
  never how much care the shown section receives. The first implementation of
  this record read the entry as a minimalism budget and produced a sparse page:
  a peer column of explanatory prose consuming a quarter of the desktop
  workspace, the body capped far below the available width, and panels that
  rendered as invisible white blocks because the scheme left every
  `surfaceContainer*` role undeclared. Restating the conditions: the section
  header and its purpose belong immediately above the body it describes, the
  ownership note closes the section as a footnote, and the body then uses the
  remaining workspace width. A desktop navigator may be a persistent grouped
  rail; below `900px` it recomposes into a scrollable labelled strip. Metrics
  inside a work-owned section are legitimate when they change that section's
  decision — the anti-pattern above is a dashboard placed *before* identity
  work, not figures inside the section that owns them. Verify the rendered
  screen, not only the widget test.
- **Reference implementation:** `lib/shared/pages/my_profile_page.dart`,
  `lib/modules/settings/pages/user_management_page.dart`,
  `lib/shared/services/user_management_navigation.dart`, and
  `lib/modules/bikeshop/pages/client_logbook_page.dart`.
- **Minimum test:** Exercise the profile and user-management routes at
  `384x824`, `599/600`, `899/900`, and `1440x900`. For a profile linked to an
  active employee, prove its labor sections render, that an unlinked identity
  never exposes them, and that a failed labor read stays explicit and
  retryable instead of rendering as an empty week. Prove 48px targets,
  increased text scale, semantics, keyboard/SafeArea behavior, profile-section
  draft preservation, and explicit dirty Back handling. Verify user-management
  access denial performs no overview request; audience/search/selection/scroll
  survive list → detail → list; desktop keeps the filtered master while
  changing detail; exact staff and CRM-only customer handoffs select only their
  requested identities; a missing target never selects the first row; and
  loading, empty, filtered-empty, error, and retry states remain explicit.

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

### Live projections refresh without replacing the workspace

- **Problem observed:** The Dashboard's first financial charts appeared late
  and could remain stale after a confirmed sale or expense. Once immediate
  refresh was added, the loaded phone composition overflowed even though an
  earlier startup test had passed.
- **Cause:** Independent projections were awaited serially after unrelated
  accounting initialization, and a time-based cache had no post-commit
  invalidation owner. Direct Postgres Changes were not a safe substitute:
  financial publication coverage was partial, `DELETE` cannot be filtered by
  tenant, and one legacy invoice policy widened SELECT beyond the active
  tenant. Legacy tenantless source rows also could not map to any private
  invalidation topic. The compact chart used desktop-height assumptions, while
  its startup fixture disposed the phone surface before delayed data completed,
  so it tested the loader rather than the real payload.
- **Approved pattern:** Start independent visible projections together and
  publish one coherent snapshot. After a canonical writer receives durable
  acknowledgement, send a typed invalidation hint to the read-model owner;
  coalesce transaction-related hints and rebuild only the affected projection
  surface. Preserve the last valid content under restrained progress, keep it
  after refresh failure with an explicit retry, defer hidden work, and perform
  one process-scoped bounded revalidation on foreground resume. For
  cross-device freshness, publish only minimal event metadata through one
  private Broadcast topic derived from the durable row's tenant; authorize
  subscription against the authenticated tenant, cover parent and direct
  child projection sources, and make stale prior-tenant callbacks inert.
  Every source row must own an explicit tenant enforced by the database;
  historical rows may be backfilled only from an authoritative, unambiguous
  relation, and the migration must fail closed otherwise.
  Realtime is an additive invalidation path: canonical writers, queries and
  persisted effects remain shared with desktop. Clear visible data and cache
  across every related panel before awaiting old-channel teardown or starting
  a tenant-scope reload. A foreground resume retries a channel that failed
  before creation while still issuing only one bounded projection
  revalidation. That transport retry reuses the current scope generation and
  must never supersede an authoritative tenant resolution already in flight;
  teardown failures are contained rather than escaping from provider disposal.
  Size the compact loaded composition from its actual controls and summaries,
  not from the loader or desktop card.
- **Anti-pattern:** Reloading the route or full application after a business
  command; replacing valid charts with a page-sized spinner; polling
  aggressively; making a projection widget the mutation notifier; assuming
  cache TTL alone provides freshness; subscribing clients directly to
  sensitive financial rows when a payload-minimal invalidation is sufficient;
  trusting a client tenant filter without auditing effective RLS; treating
  unfilterable deletes or partial source coverage as live parity; querying
  while the app is paused; allowing a tenantless financial source to bypass
  topic derivation; or declaring mobile safe from a screenshot/skeleton
  test that never resolves its data futures.
- **Reference implementation:**
  `lib/modules/accounting/services/financial_projection_refresh_coordinator.dart`,
  `lib/modules/accounting/services/financial_projection_realtime_transport.dart`,
  `lib/modules/accounting/widgets/accounting_dashboard_section.dart`, and
  `lib/shared/widgets/strategic_dashboard_deck.dart`, with database ownership
  in
  `supabase/migrations/20260726164000_enable_tenant_financial_projection_broadcast.sql`
  plus its forward authorization correction
  `supabase/migrations/20260726170500_fix_financial_projection_broadcast_authorization.sql`
  and tenant-source invariant
  `supabase/migrations/20260726174500_enforce_sales_invoice_tenant_scope.sql`.
- **Minimum test:** Resolve representative chart payloads at `384x824`,
  `599/600`, `899/900`, and `1440x900`, including increased text scale, and
  assert no overflow, clipping, or layout exception. Prove independent startup
  reads begin together; one confirmed change and its duplicates produce one
  background refetch; old content remains during loading and failure; retry
  recovers; hidden/disposed surfaces do not race; foreground resume is bounded;
  and a tenant switch removes the prior snapshot before the next one appears,
  even while old-channel cancellation is deliberately stalled. Exercise
  private-topic authorization, every registered trigger, a real source-row
  event, failed-setup resume retry, contained teardown failure, stale-callback
  rejection, reconnect/resume revalidation, and a pending tenant switch that
  wins over a foreground retry of the previous tenant. Assert source tenant IDs
  are non-null and schema-enforced. Verify an in-place remote refresh that
  preserves route and widget state on phone and desktop.

### Global Android update prompts reveal detail on demand

- **Problem observed:** The first installed Android update prompt covered too
  much of the phone workspace because the full release summary was rendered
  inside a global bottom overlay.
- **Cause:** The passive alert duplicated content already available through
  `Novedades`, making every release narrative part of the persistent prompt
  height.
- **Approved pattern:** Use one compact bottom bar with the version,
  a text-first `Novedades` target, `Instalar`, and a dismiss target. Open the
  existing grouped dialog for the full summary. Expand the bar only while
  download progress, permission guidance, or an actionable error needs room,
  and preserve SafeArea plus 48px targets throughout.
- **Anti-pattern:** Rendering the full release narrative in a passive global
  overlay; hiding install or notes behind an unlabelled icon; stacking a
  failure SnackBar over the bottom prompt; or adding widget-local dismissal
  state that competes with the update service.
- **Reference implementation:**
  `lib/shared/widgets/android_update_prompt.dart`.
- **Minimum test:** At `384x824`, keep the idle prompt at or below `84px`,
  prove the release summary remains absent until `Novedades` is selected, and
  verify install, dismiss, download progress, and recoverable failure. Repeat
  layout checks at `599/600`, `899/900`, and `1440x900`, then cover increased
  text scale and bottom SafeArea without overflow or sub-48px targets.

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
