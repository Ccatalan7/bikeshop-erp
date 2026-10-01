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
- **Para probar la app, sigue `docs/development/AGENT_VISUAL_WORKFLOW.md`.**
  Es el procedimiento completo: sesión de debug, tocar por identidad (una
  coordenada sólo sirve para un objetivo sin identidad, desde el frame actual
  y sin reutilizarla: la app corre contra producción), leer la pantalla por
  semántica y capturar el frame real.
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
  and Debug `vinabike_erp.app`; never start a second debug session while either
  is alive. The installed Release app may coexist: Debug owns the distinct
  `com.vinabike.vinabikeErp.debug` identity/container, while tools still target
  the exact debug executable path and PID because both executables share the
  same name. If the terminal handle is unavailable, do not silently kill or
  replace the live session: report it and recover control deliberately.
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
- **El diseño del ERP es abierto (dueño, 2026-09-27):** «necesito que dejes
  abierto el diseño del ERP, no más guías que aseguran resultados outdated y
  horribles; los que estás creando con Design son mucho más modernos y
  bonitos». Corrige la regla anterior (valores sólo desde `GUÍA GENERAL
  Viñabike - Componentes` vía `DesignSync`, compuerta de seis dimensiones por
  frame, Codex como único líder de diseño). Ahora, igual que el sitio público
  desde el 2026-09-24:
  - El aspecto —color, radio, sombra, borde, espaciado, tipografía, alto,
    contenedores, anatomía de cada control— y la dirección visual y la
    composición los decide el agente que hace el trabajo, Claude o Codex. No
    se leen de la guía ni con `DesignSync`, no se reportan como «ilegibles» y
    nadie espera un `/design-login`. La vara: moderno, serio y con
    personalidad; nunca anticuado ni «AI'ish».
  - Proponer en un lienzo de Claude Design antes de un cambio grande es
    bienvenido; se arma con datos reales y se construye en la app. Un frame o
    lienzo es entrada, nunca requisito.
  - El flujo, la jerarquía, las palabras y qué bloques existen salen de la
    siguiente decisión del operador y del dominio real, lo trabaje quien lo
    trabaje.
  - Sigue valiendo el funcionamiento: retorno de navegación, registro de
    superficies canónicas, estados, accesibilidad, teléfono y tableta, claro
    y oscuro. Los colores pasan por los roles del tema para que el oscuro
    funcione (cambiar el tema para modernizarlo está permitido) y un control
    compartido se mejora en su dueño, no se copia suelto.
  - Se demuestra con capturas reales de la app (escritorio y teléfono, claro y
    oscuro) antes de darlo por listo.
  - Las dos guías del repo quedan como contrato de funcionamiento; lo que
    prescriben del aspecto es historia. Tampoco son precedente los prompts
    antiguos, capturas, planes, widgets existentes ni tests de aspecto.
  - El proyecto de Design `ERP Bikeshop UI Mockups`
    (`projectId = a0fa3196-6315-4b96-bde7-7cc801e7a74e`) queda como consulta
    opcional; `list_projects` devuelve `[]` por diseño, así que el id va
    explícito (`docs/development/DESIGN_HANDOFF_SYNC_CONTRACT.md`).
- **Cada ronda limpia lo que generó, antes de cerrar.** El Mac del dueño se
  llena una y otra vez con basura de agentes (2026-09-18: 28 GB libres de 460).
  Capturas, PDFs, renders, descargas y archivos de prueba fuera del repo van a
  `~/.Trash/limpieza-<fecha>/`; tras correr pruebas, también
  `build/test_cache/` (15 GB ese día, crece con cada corrida). Bajo 50 GB
  libres (`df -h /System/Volumes/Data`) se aplica «Local Storage Hygiene» de
  `.github/copilot-instructions.md` sin que el dueño lo pida. Se mueve a la
  Papelera, no se borra; el dueño la vacía.
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
- For duplicate detection, catalog matching or anything that answers «¿este
  producto ya existe?», read
  `docs/architecture/product-identity-matching-contract.md` first. It owns the
  eliminate-then-rank order, the identity/fitment split, and why a measurement
  is never a model.
- For bike workshop architecture work, read `BIKE_WORKSHOP_MASTER_SCHEMA.md` first and update it in the same task when behavior/schema/data-flow changes.
- For an implementation that will ship, author its reviewed release change in
  `docs/releases/changes/` alongside the verified source. Follow
  `docs/development/RELEASES.md`: concrete before/after behavior, actual
  platforms, explicit Release/Debug/internal scope, and exact source hashes.
  Publication assembles these records verbatim; filenames or green tests do
  not establish a user benefit. Preparation advances the visible version for
  new source; internal native build counters are separate.
- For Supabase/database work, follow `docs/development/AGENT_DATABASE_CONTRACT.md`.
  It is the single entry point for every agent and points to the two
  authoritative documents. Do not restate database policy or command paths in
  this file.
- For non-trivial Codex/Claude collaboration, read
  `docs/development/CODEX_CLAUDE_COLLABORATION.md`. Collaboration is opt-in;
  Codex remains the product/layout owner and leads contracts, data integrity,
  concurrency, security and final integration. When Claude is explicitly
  requested, it supplies an independent proposal/review and never edits the
  same files concurrently.
- Every Claude collaboration session must visibly use **Code** mode for this
  repository and **Fable 5** (preferred) or **Opus 5**. Use
  **Effort: Ultracode** only while dynamic workflows/subagents are enabled.
  Anthropic defines Ultracode as `xhigh` plus automatic workflow orchestration;
  when the owner suspends workflows/subagents (as in the current Payroll
  migration), **Effort: xhigh** is the accepted maximum and is required instead.
  Re-check the visible selectors and intended chat title or URL after changing
  chats and immediately before Send; see the collaboration guide for the exact
  preflight.
