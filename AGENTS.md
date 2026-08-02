# Codex Agent Instructions (Repo-Wide)

- Before making changes, read `.github/copilot-instructions.md` and follow it.
- For any UI/frontend work, read `.github/GUI_DESIGN_PRINCIPLES.md` first and
  follow it.
- For shared visual tokens, component families, app palettes/themes, or
  migration from a legacy control, also read
  `docs/architecture/universal-ui-component-system.md`. Reuse the canonical
  component owner and semantic role; do not add a feature-local visual variant.
- For mobile, tablet, compact, adaptive, or responsive UI work, read and follow
  both `.github/GUI_DESIGN_PRINCIPLES.md` and
  `.github/GUI_MOBILE_DESIGN_PRINCIPLES.md`.
- For business-workflow UI changes, read
  `docs/architecture/canonical-ui-surfaces.md`, update its registry when a
  surface changes, and verify the shared action on every registered routed,
  embedded, inline, split-pane, quick-action, desktop, tablet, and phone
  surface.
- Any routed detail, form, or editor must close through
  `ReturnNavigation.close` and be opened with `push`, never closed with
  `context.go('<list route>')`. See the return contract in
  `.github/GUI_DESIGN_PRINCIPLES.md` section 6; the guard is
  `test/unit/navigation_return_contract_test.dart`.
- **Para probar la app y compararla con los diseños de Design, sigue
  `docs/development/AGENT_VISUAL_WORKFLOW.md`.** Es el procedimiento
  completo y sin ambigüedad: sesión de debug, tocar por identidad (una
  coordenada sólo sirve para un objetivo sin identidad, desde el frame actual
  y sin reutilizarla: la app corre contra producción), leer la pantalla por
  semántica, traer un frame y compararlo visual y estructuralmente.
- To see a UI change in a real browser, use `scripts/dev/web_preview.sh` — the
  single owner of preview lifecycle (debug and `--release` modes) — and
  read `docs/development/WEB_PREVIEW.md` first. Open only the URL that script
  prints: after a server restart a tab holding the previous bootstrap never
  finishes loading and looks identical to a slow compile, so waiting on it
  burns whole verification rounds. The `web-server` device has no hot restart —
  batch edits, run the analyzer and tests, then restart once per round.
- For native macOS iteration, preserve one canonical
  `fvm flutter run -d macos -t lib/main.dart` session and use its terminal for
  `r`/`R`. Before every launch, inspect for an existing matching Flutter process
  and `vinabike_erp.app`; never start a second session while either is alive. If
  the terminal handle is unavailable, do not silently kill or replace the live
  session: report it and recover control deliberately.
- An agent can own that session end to end — start it, hot reload in 2-5 s,
  click and type in the running app, screenshot the exact rendered frame, and
  capture the Claude **Design** window (only to see what the file API truncates,
  or to confirm a built result — never to read values) — with the versioned
  tooling in
  `scripts/dev/native_session.sh`, `scripts/dev/app_control.sh` and
  `scripts/dev/design_window.sh`. Read
  `docs/development/AGENT_MACOS_APP_CONTROL.md` before using them: it encodes
  the traps that otherwise cost a full round each (piping `flutter run` kills
  its key commands, `screen` needs `-p 0`, an installed old build steals the
  clicks, and the two Accessibility entries macOS requires). Phone layouts are
  verified in the iOS Simulator through the same runbook.
- Historical prompts, screenshots, feature plans, existing widgets, and
  aesthetic snapshot tests do not override the two canonical GUI guides. Do
  not copy their literal colors, dimensions, containers, or modal/layout
  choices as visual precedent.
- **Every visual value is read from a Design file with the `DesignSync` tool** —
  colour, radius, shadow, border, spacing, font, height. Estimating a value, or
  reproducing it from a screenshot of the Design window, is prohibited for both
  agents. A value that cannot be read is reported as unreadable, not replaced
  with a plausible one. See
  `docs/development/DESIGN_HANDOFF_SYNC_CONTRACT.md`, which also documents how
  to grep a 260 KB canvas without loading it into context.
- **Shared components come from `GUÍA GENERAL Viñabike - Componentes`** in
  project `ERP Bikeshop UI Mockups`. Look the control up before writing one,
  implement it under its id (`S-05`, `O-02`, `I-01`…), and bind its values to
  theme roles — the guide's own first rule bans literal hex in widgets. A
  module's screens get their own Design canvas; the guide is not edited to suit
  one module.
- **Un frame de Design es una propuesta sobre el aspecto, no una orden sobre
  el producto.** Antes de implementarlo se evalúa contra seis dimensiones —si
  existe en este negocio, si la palabra es la correcta, si el backend lo
  permite, si la navegación calza con el ERP, si aguanta claro/oscuro/compacto
  y si no reinventa un control canónico— y se registra qué se copia, qué se
  descarta y qué se agrega, con su razón. Ver
  `docs/development/AGENT_VISUAL_WORKFLOW.md` §5.b.
- Claude leads every visual and interaction redesign, reconciling that direction
  with the real app, domain truth and the canonical GUI guides. The handoff must
  name the Design page, turn and component ids used; Codex must not
  independently invent a competing visual direction.
- **Cada ronda que descubre algo, lo escribe antes de cerrar.** Una trampa de
  una herramienta, una preferencia del dueño, un documento que resultó falso, o
  una regla de dominio que sólo aparece con datos reales: se documenta en la
  misma tarea, no al final del proyecto.
  `.github/copilot-instructions.md` es el documento padre y tiene la tabla de
  qué aprendizaje va a qué archivo; si el proceso descrito ahí resulta
  equivocado o mejorable, se corrige ahí en vez de rodearlo. Escribe la causa y
  no el síntoma, fecha lo que corrige algo anterior, y di el costo real cuando
  lo hubo. No documentes el relato de la sesión ni lo que ya se ve en git.
- When repeated UI iteration reveals a reusable lesson, record the final
  validated conditions and minimum regression in the owning GUI guide. A
  successful pattern remains contextual; never turn it into a universal
  module-to-widget recipe.
- For bike workshop architecture work, read `BIKE_WORKSHOP_MASTER_SCHEMA.md` first and update it in the same task when behavior/schema/data-flow changes.
- For Supabase/database work, follow `docs/development/AGENT_DATABASE_CONTRACT.md`.
  It is the single entry point for every agent and points to the two
  authoritative documents. Do not restate database policy or command paths in
  this file.
- For non-trivial Codex/Claude collaboration, read
  `docs/development/CODEX_CLAUDE_COLLABORATION.md`. Claude leads visual and
  interaction redesign; Codex leads contracts, data integrity, concurrency,
  security, and final integration. Both remain independent reviewers, and
  neither may edit the same files concurrently with the other.
- Every Claude collaboration session must visibly use **Code** mode for this
  repository and **Fable 5** (preferred) or **Opus 5**. Use
  **Effort: Ultracode** only while dynamic workflows/subagents are enabled.
  Anthropic defines Ultracode as `xhigh` plus automatic workflow orchestration;
  when the owner suspends workflows/subagents (as in the current Payroll
  migration), **Effort: xhigh** is the accepted maximum and is required instead.
  Re-check the visible selectors and intended chat title or URL after changing
  chats and immediately before Send; see the collaboration guide for the exact
  preflight.
