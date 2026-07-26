# GUI Design Principles — Viñabike ERP

## Product design posture

Viñabike ERP must feel contemporary, professional, operationally efficient,
and visually considered. Professional does not mean colorless, flat, or
lifeless. Modern does not mean playful, saturated, or covered in decorative
chips, icons, gradients, and metric cards.

The target is the deliberate middle:

- a coherent visual identity with purposeful color;
- strong hierarchy without a wall of borders;
- compact information without cramped controls;
- subtle depth and motion that explain structure and continuity;
- familiar platform behavior without copying a generic Material demo;
- fast access to operational commands without losing the user's context.

Every visual or interaction choice must help recognition, orientation,
comparison, decision-making, or feedback. Decoration without a job is noise,
but removing all character is not design.

## Ownership and precedence

This file is the canonical owner of the shared UI language:

- product design posture and visual quality;
- theme roles, color, typography, hierarchy, spacing, and density;
- controls, lists, tables, forms, feedback, and accessibility;
- navigation continuity and choosing an interaction surface;
- overlays, anchored popovers, and shared validation rules.

For phone, tablet, compact, adaptive, or responsive work, also read
[`GUI_MOBILE_DESIGN_PRINCIPLES.md`](GUI_MOBILE_DESIGN_PRINCIPLES.md). The
mobile guide owns compact composition, touch navigation, mobile lists and
cards, disclosures, virtual-keyboard behavior, SafeArea, compact scrolling,
breakpoints, and the real-device validation matrix. It references this file
for shared visual rules rather than duplicating them.

`.github/copilot-instructions.md` is only the brief routing layer. It must link
to these guides instead of restating their recipes.

Historical prompts, screenshots, feature specifications, tests, and existing
widgets do not override these guides. Their literal colors, radii, shadows,
dimensions, dialogs, cards, or navigation structures are not visual precedent.
A shared component is reusable only while it still satisfies the current
guidance. Legacy consistency is not approval.

## 1. Design the task, not a favorite pattern

Start from the operator's task, frequency, risk, information relationships,
available space, and input capabilities. Do not start from a preferred widget.

- No module name automatically implies a table, card grid, split pane, dialog,
  or full page.
- No single successful implementation becomes a repository-wide template.
- Long lists are a reason to evaluate scanning and detail continuity, not an
  automatic mandate for a split pane.
- A visually consistent application may use different compositions for
  different tasks while sharing tokens, commands, permissions, and state.
- Recompose when the platform or viewport changes; do not merely shrink a
  desktop table or stretch a mobile card.

Before choosing a surface, answer:

1. What must remain visible while the user acts?
2. Will the user compare or edit several records in sequence?
3. Is this a local disclosure, a bounded secondary task, or an independent
   workflow?
4. Does the task need a durable URL, unusually large space, exclusive focus,
   or a security boundary?
5. How must Back, close, cancel, save, and system navigation behave?

The answers select the pattern. The pattern does not define the task.

## 2. Platform posture and capabilities

macOS desktop is the priority operational surface. Desktop design must also
behave professionally on Windows. Phone and tablet are first-class surfaces,
not reduced desktop fallbacks, and must respect iOS and Android conventions.

Viewport class and device capability are separate inputs:

- width and height determine available composition;
- pointer precision, hover, keyboard, shortcuts, and secondary click determine
  desktop affordances;
- touch, system Back, gestures, SafeArea, text scaling, and the virtual keyboard
  determine mobile affordances;
- browser history and deep links determine web navigation behavior.

Do not infer all capabilities from an operating-system check or a breakpoint.
The same business command may appear through a desktop popover, keyboard
shortcut, mobile sheet, or inline control, but it must keep one canonical
owner, permission check, validation path, and persistent effect.

## 3. Visual system and color

### Theme-owned roles

Application chrome and feature UI must consume centrally owned theme or design
system roles. A feature must not invent a Material swatch, literal hue, or hex
value for its identity, action hierarchy, or status.

The theme should provide coherent roles for concepts such as:

- canvas and nested surfaces;
- raised or selected surfaces;
- primary and secondary text;
- dividers, focus, and disabled states;
- brand or interaction accents;
- success, warning, danger, and information.

The exact hues belong to the theme, not to feature code or prose guidance.
Exceptions are limited to theme/token definitions, explicitly editor-owned or
data-driven content, and external interoperability formats.

### Purposeful color, not color quotas

Use color when it improves hierarchy, navigation, affordance, selection,
identity, status, or attention. Keep it measured and coherent, but do not
impose an arbitrary maximum number of colors per screen.

- A neutral foundation is a support structure, not a monochrome requirement.
- Accent and tonal variation may give a surface identity and visual rhythm.
- Semantic color should normally be localized instead of flooding a large
  surface.
- State must also be communicated through text, shape, iconography, position,
  or semantics; color is never the only signal.
- Saturation and prominence should match urgency and decision value.
- An existing bright or dated module palette is debt to evaluate, not a palette
  to preserve or copy into new work.

Avoid both extremes:

- rainbow interfaces where every card, icon, chip, and metric competes;
- sterile interfaces made from undifferentiated white blocks, black text,
  hard outlines, and no meaningful visual hierarchy.

### Surfaces, borders, and depth

Use grouping before containers. Related content can share alignment, spacing,
tone, and typography without placing every element inside its own card.

- Use a small, coherent surface hierarchy so users can distinguish shell,
  workspace, selection, disclosure, and transient layers.
- Combine tonal separation, spacing, dividers, and restrained shadow according
  to the context. Do not prescribe one elevation or border recipe globally.
- Avoid card-inside-card structures, repeated outlined rectangles, and grids
  that resemble a collection of unrelated widgets.
- Borders should clarify boundaries or interaction, not trace every component.
- Rounded shapes are not inherently modern. Their radius and geometry must
  belong to the shared system and fit the control's purpose.
- Gradients or tonal transitions are acceptable when subtle, coherent, and
  genuinely useful for identity or depth. Decorative multicolor gradients,
  glow, and novelty effects do not belong in operational UI.

## 4. Typography, spacing, and density

Typography must establish identity, hierarchy, grouping, and reading order.
Spacing must establish relationships. Neither should depend on a list of
universal pixel constants copied into every feature.

- Use shared type and spacing tokens.
- Give identifiers, names, totals, warnings, and active state the emphasis
  their operational importance requires.
- Use tabular or monospaced treatment when it materially improves comparison of
  codes or numbers, not as decoration.
- Keep labels identifiable during entry, autofill, error, and review. Fixed or
  floating behavior depends on the form and platform.
- Let content, localization, text scale, density mode, and input target
  requirements determine row and control height.
- Remove duplicated host padding and nested gutters. Content should use the
  available width responsibly without touching unsafe edges.
- Optimize for useful information per viewport, not for the smallest possible
  component or a fixed number of visible rows.

Whitespace is active structure. Too little destroys grouping; too much hides
the next useful record and creates oversized headers or empty bands.

## 5. Controls, actions, and iconography

Action hierarchy belongs to the current decision, not to the route as a whole.
A long-lived workspace may have different primary actions as its state changes.

- Make the next likely action clear through placement, contrast, label, and
  control weight.
- Group actions by scope: record, selection, section, or workspace.
- Use shared button components with coherent hover, focus, pressed, loading,
  selected, and disabled states.
- Avoid an entire interface made from outlined buttons, oversized pills, or
  colored icon squares.
- Use labels long enough to remove ambiguity. A verb plus object is preferable
  when a one-word label would be unclear.
- Put infrequent or destructive commands in a discoverable secondary location;
  do not hide frequent work behind repeated overflow menus.
- Icon-only controls require an unambiguous symbol, semantic label, tooltip
  where hover exists, and an accessible target.
- Use one coherent icon family. Do not decorate headings and actions with
  assorted colored emoji or repeat the same icon in every row.

### Chips, badges, and metrics

Chips and badges are compact semantic tools, not universal containers.

Use them for compact selection, tagging, or a state whose persistent visual
presence materially helps scanning. Do not use them as generic buttons,
entity containers, metadata wrappers, or a wall of decorative labels.

Metrics deserve prominent blocks only when they change a decision in the
current workflow. Otherwise integrate them into a header, summary row, list,
table, or disclosure where comparison is easier. Avoid one colored card or
mini-block per metric and avoid ornamental trend indicators.

A status may be expressed by text, a small marker, a tonal change, iconography,
or a badge. Choose the least prominent treatment that remains unmistakable.

## 6. Navigation and context continuity

The user should never have to reconstruct the state of a workflow after
inspecting related information.

When one surface opens another, preserve the origin contract as applicable:

- host module and route;
- query, search, filters, scope, sort, and active tab;
- selected record and expanded disclosures;
- scroll position and pane dimensions;
- draft values and unsaved intent;
- focus when returning to the same control.

Back, close, and cancel return to the exact origin, not automatically to the
canonical list of the entity that was visited. Cross-module navigation must
carry return context. Save may close or remain in place according to the
workflow, but its behavior must be explicit and consistent.

ERP routes keep `MainLayout` as the stable operational shell unless a documented
boundary truly requires another host. Do not mount nested top-level scaffolds,
duplicate global navigation, or add stacked header bars for local commands.
Stable shell does not mean identical inner composition.

Choose `push`, `replace`, `go`, or an equivalent API from history and return
semantics, never merely to make an animation visible.

### Choosing an interaction surface

The following are decision aids, not mandatory mappings:

| Resource | Strong signal for using it | Signal to choose something else |
|---|---|---|
| Inline or in-block disclosure/editing | The information belongs to the current object and can be understood without hiding the host | It overwhelms the host, needs durable navigation, or creates ambiguous nested scrolling |
| Split pane | Repeated list-detail inspection, comparison, or editing benefits from keeping collection and selection visible, and both panes retain useful width | The list is short or incidental, the task needs exclusive focus, or available width makes either pane ineffective |
| Anchored popover | A brief local choice, filter, preview, or command belongs to a visible trigger | The task is long, requires broad navigation, or cannot remain safely anchored |
| Sheet or contextual drawer | A bounded secondary task needs more room while the host remains conceptually present | The task is truly blocking, deeply independent, or would create competing navigation |
| Modal | A short atomic decision, confirmation, conflict, or risk genuinely requires exclusive attention | It is ordinary detail, filtering, browsing, or a form that benefits from context |
| Full route | The workflow needs durable deep linking, substantial space, independent navigation, security isolation, or sustained focus | It is a short contextual inspection or edit whose route would destroy orientation |

Use the lightest surface that preserves comprehension and supports the complete
task. Do not put split panes everywhere because they work well for some long
lists. Do not force every edit into a dialog because it is CRUD. Do not open a
new full page merely because a row is clickable.

When a full route is justified, preserve the shell and an exact return path.
When an inline, pane, popover, or sheet version exposes the same operation, it
must delegate to the same canonical command as the routed version.

## 7. Lists, tables, cards, and detail workspaces

Select the representation that best supports scanning and action:

- Desktop tables are appropriate for comparing repeated fields across many
  records.
- Structured lists are appropriate when identity and a small number of
  attributes dominate.
- Cards are appropriate when a record needs meaningful grouping or direct
  actions that a row cannot express cleanly; they are not the default mobile
  replacement for every row.
- A detail workspace may be inline, in-block, split, sheet-based, or routed
  according to the criteria above.

Shared requirements:

- Align comparable numbers and fields consistently.
- Keep the selected item and active state obvious without relying on color
  alone.
- Make the entire sensible row target interactive while preserving explicit
  controls and semantics.
- Keep common actions directly reachable; use overflow for secondary actions.
- Hover may reveal supplemental affordance, but no important action may depend
  on hover or secondary click.
- Avoid repeated icons in every cell, alternating rainbow rows, heavy grid
  borders, and nested cards.
- Allow independent scrolling where stable panes contain distinct content.
  Avoid multiple competing scroll owners inside the same pane.
- If panes are resizable, the visual handle may be subtle but its hit area must
  be comfortably operable and keyboard-accessible where appropriate.
- Size columns, panes, and rows from content, task, viewport, and user-adjusted
  preferences rather than universal constants.

Phone and tablet recomposition is owned by the mobile guide. A desktop table
must not become a horizontally scrolling miniature table by default.

## 8. Forms and editing

Forms should reflect the operator's mental model, not the storage schema.

- Group fields by decision and sequence.
- Keep labels, values, requirements, validation, and units unambiguous.
- Show field errors next to their owner and provide an accessible summary when
  several errors block submission.
- Preserve entered values after validation or a recoverable failure.
- Avoid placing every field in a separate card or exposing one control per
  backend state when a clearer operational choice exists.
- Derived totals and internal state belong in secondary context unless the
  operator must act on them.
- Separate observation from disposition in exception workflows: first record
  what happened, then offer the commercial, accounting, or logistics response.
- Let unresolved exceptions remain explicit and discoverable; never invent a
  disposition to make the form appear complete.
- Keep save/cancel behavior and dirty-state handling consistent across inline,
  pane, sheet, and routed hosts.

Compact forms must also follow the mobile guide's keyboard, focus, SafeArea,
scroll-to-error, and persistent-action rules.

## 9. Feedback and system states

Feedback prominence must match scope and duration.

- Field problems stay inline with the field.
- A persistent operation exposes a status region tied to that operation.
- A brief non-blocking confirmation may use the shared transient feedback
  component.
- A conflict or destructive decision may require a blocking surface.
- Success, warning, and error treatments use theme roles plus clear language
  and semantics; do not paint a whole feedback surface with a literal feature
  color.

Loading, empty, error, partial, stale, and offline states are first-class
compositions:

- preserve known structure and context when possible;
- prevent layout jumps that break orientation;
- use a skeleton only when it meaningfully previews stable structure;
- avoid decorative perpetual shimmer;
- expose retry and recovery where they are real;
- never represent an authoritative load failure as a trustworthy empty result.

## 10. Motion and transitions

Motion should explain where content came from, what changed, and whether the
host remains present.

- Use short, coherent transitions for disclosure, selection, reordering, and
  list-to-detail continuity.
- Keep one owner for a route or workspace transition; stacked animations create
  noise and can imply false navigation depth.
- Do not change history semantics to obtain an animation.
- Avoid bounce, glow, dramatic parallax, and decorative motion in operational
  flows.
- Respect reduced-motion preferences and ensure state remains understandable
  with animation disabled.

Subtle motion and tonal depth are allowed. Flatness is not an accessibility
requirement.

## 11. Anchored popovers, menus, and pickers

An anchored surface is interaction infrastructure, not merely a floating card.
Its positioning, overlay ownership, dismissal, focus, semantics, scrolling, and
rendering behavior must be designed together.

### UX contract

- Open a contextual popover next to its trigger, normally `4–8px` below it.
- Keep approximately `12px` between the popover and every viewport edge.
- Align the trigger and popover on the leading edge when space permits; align
  their trailing edges when the surface would overflow horizontally.
- Open above the trigger only when it does not fit below.
- Keep pointer-oriented date pickers, filters, previews, and contextual tools
  compact and anchored when that surface supports the task.
- Do not replace them automatically with a centered dialog or dim the entire
  application unless the decision genuinely blocks the workflow.
- Constrain tall content and scroll inside the popover rather than allowing it
  to escape the viewport.
- Outside click, `Escape`, cancel, selection, route disposal, and host teardown
  must have explicit behavior. Restore focus to the trigger when appropriate.
- If the host scrolls or resizes while the surface is open, the surface must
  either follow, recompute, or close. A detached popover is never acceptable.

### Choose the Flutter primitive deliberately

There is no universal overlay primitive. Use this evaluation order:

1. Use a framework-managed `PopupMenuButton`, `MenuAnchor`, or equivalent when
   the standard component satisfies the interaction and geometry.
2. For a complex, short-lived popover whose anchor is stable while open, render
   a `Positioned` child in the root Navigator overlay. Measure the trigger in
   that same overlay coordinate system, clamp it to the viewport, and implement
   below/above and leading/trailing fallbacks.
3. When the surface must continuously follow a scrolling, animated, or
   transformed anchor, prefer a tested shared implementation based on
   `OverlayPortal.overlayChildLayoutBuilder`.
4. Use `CompositedTransformTarget` / `CompositedTransformFollower` only for a
   simple leaf surface that genuinely requires continuous tracking.

`CompositedTransformFollower` is not the default for every dropdown. Never
place a widget that creates another overlay beneath a follower. This includes
`Tooltip`, `PopupMenuButton`, `MenuAnchor`, `showMenu`, and another
`OverlayPortal`. Flutter cannot reliably compute the nested portal's layout
transform because `RenderFollowerLayer` establishes it during paint, which can
produce `RenderFollowerLayer` and `debugNeedsLayout` assertions and visible
flicker. Use `OverlayPortal.overlayChildLayoutBuilder`, move the secondary
surface outside the follower, or replace it with a local non-overlay hover
label or in-place panel.

### One coordinate space, including app zoom

Never combine a transformed global origin with an untransformed
`RenderBox.size`. The ERP normally runs inside `WindowZoomScope`, so transform
both corners into the target overlay:

```dart
final anchorBox = anchorContext.findRenderObject()! as RenderBox;
final overlayBox = Navigator.of(
  context,
  rootNavigator: true,
).overlay!.context.findRenderObject()! as RenderBox;

final topLeft = anchorBox.localToGlobal(
  Offset.zero,
  ancestor: overlayBox,
);
final bottomRight = anchorBox.localToGlobal(
  anchorBox.size.bottomRight(Offset.zero),
  ancestor: overlayBox,
);
final anchorRect = Rect.fromPoints(topLeft, bottomRight);
```

Use `anchorRect` and `overlayBox.size` together. Do not calculate the trigger in
screen/global coordinates and position its child in a route-local or nested
overlay coordinate system.

### Mandatory regression gate

Analyzer success and a screenshot are not sufficient for an anchored surface.
Before marking it complete:

- open it through the real widget interaction in a widget test;
- assert its gap/alignment to the trigger, horizontal clamp, and vertical flip
  near the left, right, top, and bottom edges;
- exercise a normal desktop host, the real compact host, a short viewport, and
  the ERP's transformed/zoomed host;
- hover long enough to open every nested tooltip/menu and assert
  `tester.takeException()` remains `null` after each overlay transition;
- verify inside selection, cancel, outside click, `Escape`, focus restoration,
  scroll/resize policy, and disposal without orphaned entries;
- give the trigger and surface stable semantic labels/keys and test the keyboard
  path where applicable;
- inspect the debug runtime log for layout, semantics, follower-layer, or
  overflow exceptions from the interaction.

Current compact-popover reference:

- implementation: `lib/shared/widgets/notifications_panel.dart`;
- geometry and nested-overlay regression:
  `test/widget/notification_period_popover_position_test.dart`.

## 12. Accessibility and input

Accessibility is part of the component contract:

- visible keyboard focus and logical traversal;
- semantic labels, roles, values, selected state, and live feedback;
- sufficient contrast in every interaction state;
- targets appropriate to the active input mode and the mobile minimums in the
  companion guide;
- no required command available only through hover, color, drag, secondary
  click, or gesture;
- text scaling without clipping, hidden controls, or lost reading order;
- reduced-motion behavior;
- screen-reader and system Back behavior appropriate to the platform.

Pointer and keyboard efficiency must not reduce touch usability, and touch
composition must not remove keyboard-accessible commands from desktop.

## 13. Validation and living learning

Validate behavior through the real host, not an isolated screenshot:

- inspect the existing desktop, tablet, and phone compositions before changing
  a shared workflow;
- interact through the actual entry points, return paths, editing commands,
  overlays, and error states;
- verify macOS and Windows desktop conventions where relevant;
- verify iOS and Android touch, Back, SafeArea, and keyboard behavior where
  relevant;
- test resizing, text scale, focus traversal, semantics, reduced motion,
  loading, empty, error, and offline states;
- confirm the same canonical command and permission path is used by every
  registered routed, embedded, pane, inline, and quick-action surface;
- add the smallest behavioral regression that would fail if the validated
  interaction regressed.

### Reusable learning rule

When a UI requires several iterations to reach a satisfactory result, document
the final reusable lesson rather than the experiments. Record:

- problem observed;
- technical or UX cause;
- approved pattern and the conditions that justified it;
- anti-pattern that must not be repeated;
- currently validated implementation reference;
- minimum mandatory test.

The conditions are essential. A validated split pane, action rail, popover, or
card composition is evidence for a class of task, not a universal template.
References must identify the viewport/host and validation date or test. Remove
their reference status when they no longer satisfy the guides.

## Review checklist

Before approving UI work, confirm:

- [ ] The result is contemporary and intentional without becoming playful or
      sterile.
- [ ] Feature code uses shared visual roles rather than literal palette choices.
- [ ] Color, typography, surface tone, spacing, depth, and motion form one
      coherent hierarchy.
- [ ] Chips, cards, icons, outlines, and metrics exist only where they improve
      the task.
- [ ] The interaction surface was chosen from task evidence, not a module-wide
      recipe.
- [ ] Back, close, cancel, save, filters, selection, drafts, and scroll preserve
      the intended context.
- [ ] Desktop remains operationally efficient and compact surfaces are
      dedicated compositions.
- [ ] Keyboard, touch, semantics, text scale, contrast, and reduced motion were
      verified.
- [ ] Loading, empty, error, partial, and offline behavior were designed.
- [ ] Real interaction tests cover the changed behavior and registered hosts.

The desired UI feels calm, capable, distinctive, and alive. It does not look
like a toy, a generic component catalog, or a legacy monochrome database form.
