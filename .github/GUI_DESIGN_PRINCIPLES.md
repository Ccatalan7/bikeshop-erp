# GUI Design Principles — Viñabike ERP

## Where visual values come from (read this before writing any)

This guide owns the **reasoning**: hierarchy, density, composition, when a
control is the right one. It does not own the **numbers**.

Every visual value shipped in this repository — colour, radius, shadow, border,
spacing, font, height — is read from a Claude Design file with the **`DesignSync`**
tool, which returns literal values. Two consequences, both binding:

- **Estimating is prohibited.** Reproducing a value from a screenshot of the
  Design window, or picking one that looks right, is a defect regardless of how
  good the result looks. A value that cannot be read is reported as unreadable;
  anything that must ship unsourced is marked at its line in the code.
- **Shared controls already exist.** Selects, popovers, menus, inputs, sheets,
  dialogs, date pickers, tables and chips are defined in
  `GUÍA GENERAL Viñabike - Componentes` under component ids (`S-05`, `O-02`,
  `I-01`…), each with its limits and anti-patterns. Look the control up before
  writing one, and bind its values to theme roles — that guide bans literal hex
  in widgets. A module's own screens get their own Design canvas.

The mechanics, including how to grep a 260 KB canvas without loading it into
context, are in
[`../docs/development/DESIGN_HANDOFF_SYNC_CONTRACT.md`](../docs/development/DESIGN_HANDOFF_SYNC_CONTRACT.md).

## Las palabras son parte del diseño

El dueño de este ERP es el dueño del taller, no un contador ni un
desarrollador. Una etiqueta que él no entiende es un defecto, del mismo tipo
que un contraste insuficiente.

**Prohibido en la UI** (todas corregidas ya una vez; no vuelvan):

| No | Sí | Por qué |
|---|---|---|
| `imputar` / `imputación` | `aplicar` | En chileno es acusar a alguien de un delito |
| `comprometer semana` | `confirmar semana` | Suena a poner algo en riesgo; el RPC ya se llama `confirm_*` |
| `obligaciones` | `sueldos por pagar` | Jerga contable |
| `GANADO` | `TOTAL` | Un sueldo no se "gana" como un premio |
| `DINERO NUEVO` | `A PAGAR` | Nombra lo que la columna contiene |
| `huella …4821` | `termina en …4821` | Jerga técnica |
| `MANUAL 100%` | `TÚ LO DECIDISTE` | Un porcentaje que no mide nada |

**Se quedan**: `cartola`, `conciliación`, `anticipo`, `nómina`. No son jerga —
son las palabras correctas en Chile y las que usa el dueño.

Tres reglas que generan el resto:

- **Nombra la acción por lo que hace, no por su categoría contable.** Si el
  botón dispara `confirm_payroll_voucher_v2`, se llama "Confirmar", no
  "Comprometer".
- **Un verbo por intención.** `Pagar` para efectivo y para transferencia: desde
  el lado del operador es el mismo acto. Lo que cambia (qué evidencia queda) se
  explica dentro del flujo, no en el rótulo del botón.
- **Nunca un número que finge ser una medición.** Un `61%` que en realidad es
  una heurística de nombre × monto × fecha afirma una precisión que nadie
  midió, e invita a aprobar por umbral. Se dice en palabras lo que el sistema
  honestamente sabe.

### Un estado se deriva del PORQUÉ, no de un número

`balance == 0` no significa "pagado": puede significar que no había nada que
pagar. La app llegó a mostrar `Pagado` en verde sobre alguien que entró a una
semana sin horas — afirmando un pago que nunca ocurrió.

Antes de mapear un valor a un estado, pregunta qué lo produjo. Dos causas
distintas con el mismo número son dos estados distintos.

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

### Current visual north star: Payroll is a language, not a template

The rebuilt Payroll experience rendered by `/hr/payroll` is the current
approved runtime reference for Viñabike's product-wide visual character and
quality bar. Future UI refactors must feel like the same product through the
relationships it demonstrates:

- a deep navy identity/chrome layer against a cool neutral work canvas;
- a deliberate ladder of white, sunken, selected, bordered, and raised
  surfaces instead of either flat white or card walls;
- restrained cyan/blue interaction accents and quiet semantic success,
  warning, danger, information, and neutral treatments;
- the typographic relationship currently expressed by Poppins for identity and
  headings, IBM Plex Sans for operational reading, and IBM Plex Mono with
  tabular figures for codes and comparable numbers;
- compact but calm density, crisp hierarchy, modest geometry, restrained
  depth, and one unmistakable action hierarchy; and
- polished selected, hover, focus, disabled, loading, and transition states.

These relationships must move into shared theme and component roles as the
application is modernized. Do not make other modules import feature-owned
`PayrollTokens` or copy its literal values indefinitely.

Payroll is **not** a universal layout, shell, or widget template. Its week
strip, table, column proportions, block arrangement, navigation placement,
right rail, headers, disclosures, and payment sequence apply only where the
task independently justifies them. Current integration artifacts are also not
precedent: duplicated shell/module branding, a light tool island inside dark
chrome, fixed proportions that compress status and action, or any literal
handoff element that conflicts with the real host must be corrected rather
than propagated.

### Creative freedom grounded by operational truth

A redesign may start from first principles and discard the legacy visual
composition completely. Inspecting the current application is mandatory, but
its purpose is to learn the operator's workflow, business states, canonical
commands, permissions, navigation and return paths, real data extremes,
platform capabilities, responsive hosts, and ownership of global chrome. It
is not a requirement to restyle the existing screen or preserve its component
tree.

Before visual exploration, separate design inputs into three classes:

1. **Mandatory domain and UX invariants:** workflow sequence, state truth,
   permissions, canonical actions, persistence, return behavior, and shell
   ownership.
2. **Proven behavioral primitives:** adaptive `min`/`max`/`flex` sizing,
   accessible targets, overlay geometry, state preservation, keyboard/touch
   behavior, and other patterns validated in the real app.
3. **Optional implementation suggestions:** existing widgets, packages, and
   compositions that may be replaced when a better design preserves the first
   two classes.

A proven component contributes its behavior and lessons; it does not
automatically prescribe its current appearance. Design remains free to
recompose, restyle, or replace it. Conversely, creative freedom does not permit
duplicating a shell-owned logo, workspace control, navigation surface, or
global tool merely because a standalone concept needed one. Record shell
ownership before drawing the module, then design the module around the real
workflow with its own most effective information architecture.

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

### Global token cascade and component ownership

The visual system must make a product-wide change a single owned edit, not a
search-and-replace across features. Every reusable visual decision follows this
cascade:

1. **Foundation values:** the private palette, type families, spacing scale,
   geometry, depth, and motion values.
2. **Semantic roles:** purpose and host relationships such as
   `actionPrimaryOnSurface`, `actionPrimaryOnShell`, `selectionAccent`,
   `focusRing`, `surfaceSunken`, `inkMuted`, and the semantic status families.
3. **Component roles:** the button, field, search, selector, chip, notice,
   menu, popover, dialog, table, and pane treatments that consume semantic
   roles.
4. **Canonical components:** shared implementations that expose behavior and
   variants without accepting arbitrary visual overrides from a feature.

Name tokens by meaning, never by their current hue or by a module:
`actionPrimaryOnShell`, not `cyanButton` or `payrollBlue`. Cyan on navy and
blue on a light surface may be two intentional contrast roles even when both
communicate a primary action. If the product later changes the first role to
orange, every component using that role must update through the central theme
without modifying feature code. The change must not recolor success, warning,
information, selection, or focus unless those independent roles are also
deliberately changed.

Feature code must not bypass the cascade with literal colors, copied token
values, local `ButtonStyle`/`InputDecoration` families, or imports from another
feature's theme. A new visual variant requires a demonstrated semantic or
interaction distinction; preference is not a new role.

Every global token or component-role change must be reviewed in the visual
catalog across light/dark hosts, compact/comfortable density, pointer/touch,
all supported interaction states, and contrast requirements. Representative
goldens protect the relationship; they do not freeze the current hue forever.

The root resolver's minimum component family includes actions, fields/search,
chips and selection controls, tables/cards/lists, dialogs/sheets/menus,
searchable dropdowns, snackbars/banners, date/time pickers, tooltips, tabs,
segmented controls, badges, sliders, scrollbars and adaptive navigation.
Adding only a `ColorScheme` is incomplete: every family must be mapped to the
resolved roles for all persisted presets in light and dark mode. A resolver
test proves the mapping; a rendered host test must still open representative
overlays because nested shell themes can leak after token-only tests pass.

The application palette preference follows the same ownership rule.
`AppearanceService` owns selection and persistence, while the root
`MaterialApp` resolves the selected preset into the complete semantic theme and
its component roles. `MainLayout`, the workspace chrome, right toolbar, and
feature surfaces are consumers; none may maintain a competing palette. The
existing sidebar palettes are migration input, not a permanent sidebar-only
boundary. A Slack-like preset may change the shell and interaction personality
product-wide, but it must preserve semantic distinctions, contrast, and the
single component anatomy defined by this system.

Global utility chrome must still use the correct semantic surface family. The
desktop right toolbar is a content utility rail, not a continuation of the
navigation canvas: it consumes the application neutral surface ladder, spans
the full height available below the workspace strip regardless of icon count,
and adapts that same role through palette-aware light and dark themes. In light
mode both the collapsed rail and expanded utility panel use the root
near-white `surface`; container tones belong inside the tool content, not
across the whole toolbar. Dark mode may use adjacent palette-derived container
levels to preserve layer contrast. Shell accent roles may style selection and
focus, but must not repaint the rail as a navigation column.

The detailed component hierarchy, foundation kit, selection matrix, stability
contract, and migration order live in
`docs/architecture/universal-ui-component-system.md`.

#### A scheme must actually define the roles features consume

"Consume theme roles" is only correct guidance while the theme defines them.
Material 3 silently resolves an undeclared role to a coarser one — in Flutter,
every `surfaceContainer*` role falls back to `surface` and `onSurfaceVariant`
falls back to `onSurface`. A `ColorScheme` that declares only primary,
secondary, surface and error therefore renders every panel in the application
at exactly the canvas colour and every secondary label at full text weight.
The result is the sterile extreme this guide forbids, produced by feature code
that followed the rule correctly.

When a surface looks flat, undifferentiated, or hierarchy-free, inspect the
resolved scheme before redesigning the feature. Declare the neutral ladder
(surface, the container steps, dim/bright), the secondary text role, both
outline roles, and the container/inverse roles centrally, and verify a rendered
screen rather than the analyzer. Never repair a collapsed role with a literal
colour inside a feature.

#### A chromatic shell must contain the outer application theme

A dark or chromatic shell mounted inside a light or dark application theme is
a complete theme boundary, not a partial `ColorScheme.copyWith`. It owns every
surface/container step, text and icon role, outline, selection, focus, disabled
and semantic status container used by its descendants. It also owns the
component themes for fields/search, navigation rows, mode selectors, buttons,
toggles and disclosures. Otherwise any new control can silently inherit a
white light-mode fill or an unrelated graphite dark-mode role.

Shell controls consume those scoped semantic/component roles; they do not
repair leakage with local `fillColor`, borders or literal colours. The same
resolved component-theme builder must serve the expanded sidebar, compact
drawer and palette-aware tool chrome so there is no second partial palette
path. Overlays that are application surfaces — menus, dialogs, sheets and
popovers — deliberately resolve the outer application theme instead of
accidentally capturing the shell theme.

The minimum regression crosses every supported palette with both global light
and dark hosts. It renders the real compact header, drawer, mode selector,
search field, navigation/tool selection, badges, pinned actions and scrim; a
token-only comparison cannot prove this boundary. It asserts that resolved
roles and interactive states remain palette-owned and contrast-safe, and that
switching the outer mode does not recolour an already-mounted shell.
`ThemeMode.system` must be resolved from the platform brightness outside the
nested shell theme, otherwise the shell's deliberately dark `Theme` can make
the entire application report dark mode even on a light system. Selected
controls, status badges and the scrim consume explicit semantic roles; do not
recreate those states with a feature-local alpha or literal colour.

The compact application header accepts semantic content — title, context line
and the shell-owned search contract — rather than an arbitrary pre-styled
widget. A module must not build a `Text`, `Column` or `TextField` from its
content `Theme` and inject it onto chromatic chrome; explicit styles bypass
inherited defaults and reintroduce dark text or light fills. The shell owns
title typography, search anatomy, contrast and focus while the module owns the
query and callbacks.

Appearance mode is an explicit three-state preference: system, light and dark.
Do not project it into a binary switch derived from effective brightness,
because touching that switch silently destroys the saved `system` intent. The
control shows all three states, while effective brightness remains a separate
resolved value.

#### Do not dilute a semantic role with alpha

A role already encodes its intended weight. `outlineVariant` *is* the hairline
colour; writing `outlineVariant.withValues(alpha: 0.2)` does not make a
boundary "more subtle", it makes the surface depend on the role's exact
luminance. Those multipliers accumulate silently: this repository reached
roughly 160 of them, every one calibrated while the role resolved to near
black. Correcting the scheme then erased them all at once and a 1500-row
product table rendered as a single undivided block.

Use the role directly for the thing it names. Reach for alpha only when the
element is genuinely secondary to another boundary in the same composition, and
never for the primary separator between records. When a whole family of call
sites already dilutes a role, recalibrating that role centrally is the fix —
not adding another multiplier at the call site.

Record separation is load-bearing, not decoration: a table exists so rows can
be scanned and compared. Verify a long list at real density after any change to
outline, divider, or surface roles.

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

### The return contract is a mechanism, not an intention

This rule was documented long before it was followed, and stating it again is
not what makes it hold. It was broken the same way every time, so recognise the
shape rather than the principle.

A routed detail is reachable from its own list, a dashboard card, a search
result, a related record, or another module. Closing it with
`context.go('<some list route>')` is not navigating back. `go` **replaces** the
location: it discards the history entry the host occupied and disposes that
route along with its query, filters, scope, selection, expanded rows and scroll
offset. The operator lands on a freshly built list and has to reconstruct the
work they were doing. This is the single cause behind "Back sent me to the
employee list", "my search was lost", and "it jumped to page one".

Consequences that follow from the same cause:

- open a detail with `push`, never `go`, whenever the host must survive;
- close it through `ReturnNavigation.close(context, fallbackRoute: …)` in
  `lib/shared/services/return_navigation.dart`, which pops the real history
  entry and uses the fallback only when a deep link left nothing to return to;
- a `referrer`/`returnTo` query parameter reconstructs a *route*, not a *state*.
  It is a deep-link fallback, never the primary return path;
- keep list state with the list owner, so a preserved route is enough to
  restore it. Do not rebuild it from a child or from visible labels;
- a back arrow that carries an explicit destination label ("Volver al inicio")
  is a navigation link, not a return. Declare it at the call site with a
  `// return-contract: explicit-destination` comment so the choice stays
  deliberate.

The regression that must exist:
`test/unit/navigation_return_contract_test.dart` fails when a back affordance is
wired to a fixed route. Extract non-trivial handlers into a named method so the
guard can see the affordance clearly. When you fix a context-loss bug, also add
the interaction test that would have caught it: open the host, apply a query or
filter, enter the detail, return, and assert the query, selection and scroll
survived.

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

The root zoom scope is also the sole owner of display scale. Desktop scale is a
user-controlled application preference, not a route generation or feature
classification. A module must never force itself to `1.0` merely because it is
new, switch the application scale when its workspace becomes active, or add a
second inverse `Transform.scale`. Those approaches leave navigator overlays,
scroll extents, hit testing, or shared chrome in another coordinate space and
make the same application change size while the operator moves between tasks.

Design and test rebuilt surfaces at the supported desktop scales, especially
the configured `0.8` baseline and `1.0`, without rewriting their typography or
geometry at runtime. Responsive composition uses the unzoomed viewport owner;
scale and density remain separate decisions. Compact widths below `900px` keep
an applied scale of `1.0` so declared touch targets retain their physical size.
Regressions must switch between old and rebuilt workspaces without remounting
route state and must open dialogs, sheets, and popovers through the same root
scale.

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
- [ ] The result belongs to the Payroll-derived Viñabike visual language and
      quality bar without copying Payroll's layout or feature widgets.
- [ ] The composition was designed from the module's real operating loop, and
      legacy UI was inspected for domain/UX truth rather than used as its
      visual base.
- [ ] Global brand, workspace navigation, and tool chrome each have one owner
      and are not duplicated inside the module.
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
