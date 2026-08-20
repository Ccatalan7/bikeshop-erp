# Appearance palette contract

One cascade owns every color in the app. A module never invents visual
language; it consumes roles that the mounted theme resolved from the user's
preset. Payroll is the reference implementation, not a private theme.

## The cascade (single direction, no side doors)

```
AppearancePreset (user choice, persisted by AppearanceService)
  └─ foundation seeds: shell seed + light content seed + dark content seed
       └─ VinabikeThemeResolver.resolve(preset, brightness)
            ├─ ColorScheme            (Material role surface for built-ins)
            ├─ VinabikeThemeRoles     (ThemeExtension: semantic roles by NAME)
            └─ ThemeData              (scaffoldBackgroundColor == canvas role,
                                       component themes, typography)
                 └─ WorkspaceChromeTheme (global shell chrome derives from
                                          roles.shell — never from a feature)
                      └─ consumers: shared components, module vocabularies
                         (e.g. PayrollVisualTokens.of(context)), overlays,
                         popovers, dialogs, pickers, banners, bottom bars
```

- Every preset produces **two complete, deliberately designed role sets**:
  LIGHT and DARK. Dark is a designed layer system (preset-tinted
  `surfaceContainerLowest` canvas upward), never pure black and never an
  automatic inversion of light. Light keeps the cool Claude Design neutrals.
- Switching preset re-resolves everything — canvas, shell, surfaces, raised
  surfaces, text, borders, focus, selection and action accents move together.
- Switching brightness preserves the preset's identity with contrast designed
  for that brightness.

## Roles are named by FUNCTION, never by color

From `VinabikeThemeRoles` (authoritative list in
`lib/shared/themes/vinabike_theme_roles.dart`):

| Role | Meaning |
|---|---|
| `shell.canvas / raised / edge / foreground / mutedForeground / accent / onAccent / dirty / attention` | Global chrome (navy band, workspace strip, rails) |
| `success / warning / info / neutral` (`accent, onAccent, container, onContainer, border`) | Semantic state tones. They are designed per preset-brightness; they are **not** blindly recolored by the brand accent |
| `selectionContainer / onSelectionContainer` | Selected rows, cards, options |
| `focusRing` | Keyboard/focus affordance |
| `disabledForeground` | Disabled content |
| `scrim / shadow` | Overlays and elevation |
| `avatarA…D / onAvatarA…D` | Identity avatar fill/initial pairs; every pair keeps text contrast ≥ 4.5:1 |

`ColorScheme` carries the content roles the resolver designed: `primary` is
the preset's **action accent** (parameterizable per preset), `onPrimary` its
on-accent foreground, `surface*` the layer ladder, `onSurface(Variant)` ink.
`ThemeData.scaffoldBackgroundColor` **is** the canvas role.

## Consumption rules

1. Consume roles from the mounted theme (`Theme.of`, roles extension, or a
   module vocabulary like `PayrollVisualTokens.of(context)` that only maps
   mounted roles). Never import another module's vocabulary.
2. **No local literals.** A hex value outside the resolver/seed layer is a
   defect (Payroll enforces this with `payroll_theme_architecture_test.dart`;
   its frozen `PayrollTokens` statics are Design-reference geometry only).
3. **No opacity hacks.** The only permitted alpha derivations are interaction
   overlays derived from the role they decorate at fixed alphas (hover ≈
   .06–.12, focus ≈ .12–.16, busy dim ≈ .55), exemplified by
   `PayrollAccentAction`. Everything else uses a designed role.
4. Accent-filled interactive controls have ONE owner per module family
   (Payroll: `PayrollAccentAction`); content over accent uses the on-accent
   role, never `surface`/`onSurface`.
5. Selected ≠ expanded ≠ applied: selection uses `selectionContainer`,
   disclosure uses the sunken surface layer, applied states use their
   semantic tone. The meanings never collapse into one tint.
6. Dropdowns, popovers, tables, selected/expanded rows, dialogs, date
   pickers, inputs, chips, banners, bottom bars and overlays inherit from the
   same `ThemeData`/roles — a component that needs a different look asks for
   a new ROLE in the resolver, never paints locally.

7. **Un tema derivado tiene que reemplazar los temas de COMPONENTE, no sólo
   el `colorScheme`.** `SegmentedButtonThemeData`, `MenuThemeData`,
   `PopupMenuThemeData` y compañía resuelven sus colores contra el `scheme` y
   los `roles` capturados **en un closure** cuando se construyó el tema de la
   app. `baseTheme.copyWith(colorScheme: otro)` **no** los alcanza: siguen
   pintando con los colores viejos.

   Se vio el 2026-08-20 en `WorkspaceChromeTheme.sidebarTheme`: dentro de la
   barra lateral y del riel, un `SegmentedButton` salía claro sobre el navy y
   los desplegables salían con fondo blanco — y, una vez que el texto sí heredó
   el chrome, con letra clara sobre blanco: ilegible. No era un caso nuevo, el
   selector de tema ya venía así y nadie lo había mirado.

   Un tema derivado reemplaza explícitamente cada tema de componente que
   quiera respetar la paleta. La regla 6 dice de dónde hereda un componente;
   ésta dice que heredar **no ocurre solo** cuando el tema se deriva.

## Verification gates (what "supports appearance" means)

- Rendered matrix over **all presets × light/dark** for the surface family
  (Payroll: routed host + overlays in `payroll_redesign_dark_host_test.dart`,
  reconciliation in `payroll_reconciliation_page_theme_test.dart`, tokens in
  `payroll_visual_tokens_test.dart`, on-accent owner in
  `payroll_accent_action_contract_test.dart`).
- At least two materially distinct presets asserted in light AND dark, plus
  desktop and compact hosts.
- Dark cells prove no legacy-light literal and no pure-black/white collapse.
- Contrast: ink over surface and each tone's foreground over its container
  hold ≥ 4.5:1 in every cell.
- Source guards keep literals/on-accent misuse from re-entering.

## Extending

- **New preset**: add seeds to `AppearancePresets`; the resolver derives both
  role sets; the existing matrices pick it up automatically.
- **New module**: build a small mounted vocabulary (pattern:
  `PayrollVisualTokens`), assign every component to a role from this
  contract, add the module's rendered matrix + source guard. Do not copy
  Payroll's geometry tokens; only the pipeline pattern.
- **New need**: if no role expresses it, extend `VinabikeThemeRoles` (with
  both brightness designs and every preset) — never a feature-local color.

Registry status per surface family lives in
[`canonical-ui-surfaces.md`](canonical-ui-surfaces.md) ("Appearance migration
readiness"); the universal component gate is
[`universal-ui-component-system.md`](universal-ui-component-system.md).
