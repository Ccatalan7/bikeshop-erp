# Viñabike universal UI component system

Status: canonical architecture and adoption contract.

**The visual catalog lives in Design, and is read — not looked at.** It is the
page `GUÍA GENERAL Viñabike - Componentes` in project `ERP Bikeshop UI Mockups`
(`a0fa3196-6315-4b96-bde7-7cc801e7a74e`), renamed from
`Sistema Visual Viñabike - Componentes`. Every shared control is defined there
under an id (`S-05 Select corto`, `O-02 Popover`, `I-01 Campo de texto`…) with
its anatomy, limits, keyboard behaviour, tokens and anti-patterns.

Before implementing any shared component, read it from that page with
`DesignSync get_file` and implement under its id. Values are bound to theme
roles, never pasted as hex — the guide's own first rule is
`PROHIBIDO EL HEX LITERAL EN CUALQUIER WIDGET`. Estimating a value off a
screenshot is prohibited; see
[`../development/DESIGN_HANDOFF_SYNC_CONTRACT.md`](../development/DESIGN_HANDOFF_SYNC_CONTRACT.md).

A module that needs a screen composed from those parts gets its **own Design
canvas**; the shared guide is not edited to fit one module.

This document defines how Viñabike gets one coherent visual system without
turning one successful module into a universal layout template. The canonical
GUI guides remain authoritative for interaction, responsive composition,
navigation, accessibility, and validation.

## 1. Visual authority

The rebuilt Payroll experience is the current visual north star. Its palette
relationships, typography, density, surface ladder, geometry, depth,
iconography, action hierarchy, and interaction states define the product
language.

Payroll's week strip, table, columns, rails, headers, payment workflow, and
block arrangement are not reusable by default. Every module still chooses the
composition that best serves its operating loop.

The legacy application is inspected for domain and UX truth, not as visual
precedent. A component may be designed from first principles while preserving
its canonical command, state, permission, persistence, navigation, and input
contracts.

## 2. One visual cascade

Every reusable visual decision has one owner and follows this dependency
direction:

1. **Foundation values** — private palette values, type families, spacing,
   geometry, depth, and motion.
2. **Semantic roles** — purpose and host relationships such as
   `actionPrimaryOnSurface`, `actionPrimaryOnShell`, `selectionAccent`,
   `focusRing`, `surfaceSunken`, and semantic status families.
3. **Component roles** — button, field, search, selector, chip, notice, menu,
   popover, dialog, table, and pane styling derived from semantic roles.
4. **Canonical components** — shared Flutter implementations with stable
   behavior and controlled variants.
5. **Contextual recipes** — task-specific compositions of canonical
   components. A recipe is evidence for that task, not a universal layout.

Features must not reverse this dependency, import another feature's tokens,
copy resolved values, or accept arbitrary visual overrides.

Tokens are named by meaning, never by their current hue or module. Cyan on navy
and blue on a light surface may intentionally represent separate contrast
roles. Changing `actionPrimaryOnShell` from cyan to orange must update every
intended consumer without recoloring success, warning, information, selection,
or focus.

## 3. Theme presets and ownership

`AppearanceService` owns the selected appearance preset and its persistence.
The root `MaterialApp` resolves that preset into the complete semantic theme
and component roles. `MainLayout`, workspace chrome, right toolbar, and feature
surfaces consume the resolved theme; none owns a competing palette.

The existing `SidebarPaletteOption` presets are migration input. They must
evolve from sidebar-only palettes into complete product presets, similar to a
Slack theme:

- the component anatomy and interaction contract stay constant;
- the preset changes the product's visual personality through semantic roles;
- contrast and semantic distinctions remain valid;
- shell and feature UI update together;
- a preview shows the same representative components before applying a preset.

Appearance mode is orthogonal to palette preset. Every preset resolves
`light`, `dark`, and `system` through the same semantic roles. Dark mode is a
designed surface hierarchy, not an inverted light palette: canvas, sunken,
surface, raised, overlay, borders, focus, disabled content, and all semantic
tones must preserve contrast and relative emphasis. The catalog previews both
modes and records contrast evidence for shared text and interactive states.
The dark hierarchy uses chromatic near-black slate, navy, graphite, or
palette-derived tones rather than painting the product pure black. Depth comes
from controlled differences in tone, chroma, border, and restrained shadow;
primary text is a softened near-white and semantic colors have dark-host
variants. A blanket black background or a global brightness reduction is not
an acceptable dark theme.

The resolved theme is the product of both axes:
`resolve(appearancePreset, appearanceMode)`. `system` selects the current light
or dark branch; it is not a third visual palette. Controls must present the
saved preference and the effective `Theme.of(context).brightness` honestly,
instead of treating `ThemeMode.system` as light. The selected preset supplies
the chromatic bias for the complete product, not only the navigation:

| Preset | Intended dark character |
| --- | --- |
| Vinabike | cool ink and restrained blue-grey layers |
| Midnight | blue-black and deep navy layers |
| Aubergine | deep plum and muted violet layers |
| Graphite | warm charcoal and restrained copper layers |
| Evergreen | forest, graphite-green, and muted teal layers |
| Pacific | oceanic navy, petrol blue, and cool cyan layers |

These characters are direction, not literal feature colors. The theme resolver
must derive a perceptually separated `canvas → sunken → surface → raised →
overlay` ladder, plus borders, text, actions, selection, and focus for each
preset. It must not reuse the sidebar background for every dark surface or
produce six identical graphite canvases distinguished only by the primary
button. Semantic success, warning, error, and information retain their meaning
while receiving contrast-safe dark-host variants.

Per-user preference remains distinct from an optional tenant default. Neither
may create module-specific themes.

### Dark-mode completeness gate

Dark compatibility is a whole-surface contract, not a claim a feature can make
because its scaffold background changed. A registered surface remains
`not migrated` until all of these consumers use resolved semantic roles:

- shell, module command surface, canvas, cards, panes, tables, dividers, and
  sticky regions;
- fields, selectors, search, date/time controls, menus, popovers, dialogs,
  sheets, tooltips, and drag/selection feedback;
- default, hover, focus-visible, pressed, selected, disabled, read-only,
  loading, empty, error, offline, and permission-denied states;
- text, icons, tenant branding, illustrations, charts, badges, and all
  semantic status tones;
- routed, embedded, split-pane, quick-action, desktop, tablet, and phone hosts
  registered for that workflow.

Theme changes must update an already-mounted route and its open overlay without
losing route, draft, selection, filters, scroll, or workspace state. A feature
must not cache resolved colors or choose its appearance only during `initState`.

The minimum release gate is:

1. a resolver test for every preset in both light and dark modes;
2. automated contrast checks for text, controls, focus, selection, and status
   roles;
3. representative component and shell goldens covering the six preset
   personalities, with dedicated interaction-state goldens for the chromatic
   extremes;
4. a static guard against feature-owned literal colors and local component
   theme families, with explicit reviewed exemptions for data visualization or
   authored content;
5. host-level checks at 1440 desktop, 834 tablet, and 390 phone, including
   overlays and the 899/900 shell transition;
6. an entry in the canonical surface registry recording `not migrated`,
   `in progress`, or `light + dark verified`.

No mixed state is silently accepted. If a legacy child cannot yet consume the
resolved theme, the owning surface stays visibly classified as migration debt
rather than presenting partial dark mode as complete.

The Jobs table is the first dark-theme canary. In `Pacific + dark`, the Pacific
identity must continue from the shell into the feature without tinting every
panel blue: the shell uses the deepest ocean tone; the module command surface,
filter/search band, table header, rows, hover/selection, sticky footer, right
tool rail, and empty remainder each occupy a deliberate step in the same cool
tonal family. Large pure-black voids, an unrelated grey module header,
light-mode white pills, illegible disabled commands, or a table that merely
sits on a black rectangle fail the canary.

## 4. Global shell family

`MainLayout`, workspace navigation, global tools, and the active module command
surface form one coordinated shell family. The Claude Design Payroll concepts
3a and 3b are the visual target for this family, but the repository's real
navigation and workspace contracts remain authoritative.

The desktop compositions are:

- a 56px compact navigation rail or a resizable 200–400px expanded sidebar
  (280px default);
- the workspace strip beginning after that navigation width, never underneath
  or across it;
- an optional module command surface immediately below the workspace strip;
- the active module canvas using the remaining width;
- the existing right tool rail, when enabled, as the final shell-owned edge.

The navigation identity and workspace strip must read as one continuous shell
surface even though they retain separate behavioral owners. There is one brand
mark: the compact rail uses the monogram and the expanded sidebar uses the full
logo. A module never repeats either.

Workspace drag/reorder, pin, close, dirty state, back, forward, share, capture,
new-workspace, appearance controls, and workspace count remain available. They
are restyled as on-shell controls; a light pill or toolbar island must not be
introduced merely to preserve overlay theming. Menus, dialogs, and tooltips
resolve their own surface roles when opened.

The module command surface has one title/scope and one primary action cluster.
It must not become a second application bar or reproduce global tools. With the
workspace strip it may read as one navy block separated by an internal
hairline, with a single boundary against the canvas.

Below the persistent-desktop breakpoint, the same state changes presentation:
the sidebar becomes a drawer, open workspaces move to a selector or sheet, and
global tools move to the header overflow. Responsive recomposition must not
unmount a workspace or lose route history, selection, drafts, pinned state,
unsaved indicators, or in-progress workflows.

The visual reference baseline is the application at 100% display scale. The
root still owns one user-controlled zoom preference that applies uniformly to
the shell and every active feature and is validated at both `0.8` and `1.0`.
No route changes it when activated. Shell and feature components also share
the same `compact` or `comfortable` density setting. Density changes tokenized
geometry and typography intentionally; it is not implemented with a route
transform, browser zoom, `MediaQuery` scale override, or an automatic
per-workspace scale change. Legacy surfaces must be migrated instead of making
80% a prerequisite for using the application.

Shell colors consume semantic roles such as `shellCanvas`, `shellRaised`,
`onShell`, `onShellMuted`, `shellSelection`, and `actionPrimaryOnShell`.
Neither `MainLayout` nor `WorkspaceTabBar` may import feature-owned tokens.

## 5. Foundation kit

The first stable kit is intentionally bounded. It should finish approximately
20–25 essential pieces before expanding from real consumers.

### P0: foundations and high-drift primitives

- semantic theme and density roles;
- primary, secondary, tertiary, destructive, icon, and split actions;
- text, numeric/currency, textarea, and canonical search fields;
- status, selection, and filter chips;
- inline and persistent notices;
- anchored popover infrastructure;
- short select and searchable selector;
- adaptive date/date-range picker;
- adaptive column specification;
- accessible split-pane resize and collapse behavior;
- loading, empty, error, no-results, read-only, and permission-blocked states.

### P1: complete operational families

- checkbox, radio, switch, and segmented control;
- menus and contextual actions;
- dialog, side sheet, and bottom sheet;
- row, list, disclosure, tabs, and local subnavigation;
- table header, sort, filter, selection, sticky regions, and row actions;
- time picker, multi-select, and autocomplete.

### P2: contextual recipes

- decision queue;
- inspector;
- payment composer;
- monetary summary;
- activity timeline;
- batch review;
- responsive record workspace.

Recipes may use the same primitives but must remain task-specific.

## 6. Selection rules

The system prevents both visual drift and choosing the wrong control.

| Need | Default surface |
| --- | --- |
| Two to four short visible choices | Radio or segmented control |
| Stable short list, normally up to about seven options | Select |
| Long, dynamic, frequently searched, or long-label list | Searchable selector |
| User knows part of a non-critical value | Autocomplete |
| Immediate binary setting | Switch |
| Selection committed by a later action | Checkbox |
| Compare values across stable columns | Table |
| Brief task anchored to a trigger | Popover |
| Short secondary task that preserves host context | Side sheet |
| Truly blocking atomic decision | Dialog |
| Compact selection or short secondary task | Bottom sheet |
| Deep, recoverable workflow | Routed page |

A status chip informs. It is never the only execution control. One surface of
decision has one unmistakable primary action.

## 7. Stable component contract

A component is not stable until its catalog entry and implementation define:

- purpose, non-use cases, and anatomy;
- legitimate variants and the evidence for each;
- default, hover, focus-visible, pressed, selected, disabled, loading,
  read-only, and error states where relevant;
- compact and comfortable density without coupling to display zoom;
- pointer, keyboard, touch, semantics, and reduced-motion behavior;
- short, long, localized, empty, and extreme numeric content;
- wrap, truncation, scroll, virtualization, and reflow rules;
- desktop, tablet, and phone adaptation;
- semantic and component roles consumed;
- canonical Flutter owner and API;
- minimum interaction, accessibility, overflow, and representative golden
  regression;
- maturity: experimental, candidate, stable, or deprecated.

Foundations and accessibility primitives may become shared immediately.
Ordinary visual variants normally need two real consumers before becoming
stable.

The catalog maintains an explicit coverage matrix at 1440px desktop, 834px
tablet, and 390px phone. A touch example alone does not qualify as mobile
coverage. Phone and tablet entries must resolve SafeArea, keyboard intrusion,
scroll, reflow, overlay substitution, 48px touch targets, orientation changes,
and state preservation across the `899/900` shell boundary. An unresolved
composition is marked pending rather than implied by a generic responsive
claim.

## 8. Guardrails

- Feature code does not introduce literal palette values, local component
  families, or visual overrides for a stable component.
- Every pointer-interactive surface exposes both a click cursor and a visible
  hover response. Cursor alone is insufficient; hover, focus-visible, pressed,
  selected, and disabled states must remain distinguishable without shifting
  layout.
- A different business state does not automatically require a new color.
- A different module does not automatically require a new component.
- Global shell, brand, workspace navigation, and tool chrome each have one
  owner and are never duplicated inside feature canvases.
- Long selectors use search, grouping, paging, or virtualization rather than
  an endless platform dropdown.
- Desktop date selection uses a modern anchored popover when appropriate;
  compact presentation adapts to a sheet or full-screen task rather than
  shrinking the desktop picker.
- Table columns use content-aware `min`/`max`/`flex` priorities and a declared
  compression order. Status and action remain separate and readable.
- A split or collapsible pane preserves selection, draft, width preference,
  focus, and return context across responsive recomposition.

## 9. Adoption

1. Approve the Claude Design foundation kit and component-to-role map.
2. Introduce the shared semantic theme and component ownership boundary.
3. Connect `AppearanceService` presets at the root `MaterialApp`.
4. Build an internal interactive catalog with state, width, density, content,
   and theme controls.
5. Stabilize P0 components with focused regressions.
6. Migrate real modules incrementally, beginning with the most duplicated and
   failure-prone families.
7. Deprecate legacy shared widgets and add a static guard against new literal
   colors and unauthorized component families.
8. Remove legacy implementations only after all registered consumers use the
   canonical owner.

Migration must preserve unrelated working-tree changes and canonical business
owners. It must not become a one-shot visual rewrite of every module.

## 10. Current evidence

The 2026-07-29 read-only inventory found widespread local implementation:

- two visibly different shared search widgets plus search UI across roughly 89
  files;
- dropdown/select usage across roughly 98 files with no canonical searchable
  selector;
- `showDatePicker` in 39 files, with separate time and range pickers;
- popup menus across roughly 61 files;
- many local chips, notices, dialogs, tables, and at least ten independently
  resizable split-pane implementations.

These are syntactic inventory counts, not a claim that every call site is a
unique component. They establish that theme changes alone cannot provide
universal harmony; canonical component ownership and migration are required.

The first resolver-backed foundation is now mounted at the authenticated ERP
root. A single `preset × brightness` resolution owns the content surface
ladder, shell roles, typography colors, focus/selection/disabled roles and the
Material component themes for:

- buttons, icon actions, fields, search, chips and selection controls;
- tables, cards, lists, dividers and progress;
- dialogs, sheets, menus, searchable dropdowns, snackbars and banners;
- date and time pickers, tooltips, tabs, segmented controls and badges;
- sliders, scrollbars, mobile navigation bars and navigation drawers.

These themes are a compatibility floor, not permission for a feature to invent
another component family. A specialized canonical component may add anatomy or
behavior, but its colors and interaction states still derive from the same
semantic owner. Resolver regression covers all six persisted presets in both
light and dark modes; shell regression additionally opens the real toolbar and
sidebar overlay to prove that chromatic nested themes do not leak into content
popovers.
