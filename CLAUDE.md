# Claude Code Instructions (Repo-Wide)

@AGENTS.md

Vinabike ERP — Flutter client, Supabase backend, accounting-first business
logic with strict multi-tenant isolation.

`.github/copilot-instructions.md` is the repository source of truth. Read it
before making changes. The pointers below exist so the right section is loaded
before the first command of a task, not to restate it.

## Routing

| Work | Read first |
|---|---|
| Supabase / database / SQL / pgTAP | `docs/development/AGENT_DATABASE_CONTRACT.md` |
| Any UI or frontend | `.github/GUI_DESIGN_PRINCIPLES.md` |
| Mobile, tablet, compact, adaptive, responsive UI | the GUI guide **and** `.github/GUI_MOBILE_DESIGN_PRINCIPLES.md` |
| Business-workflow UI | `docs/architecture/canonical-ui-surfaces.md`, and update its registry when a surface changes |
| **Probar la app y compararla con Design** (sesión de debug, clics, lectura de pantalla, frames) | `docs/development/AGENT_VISUAL_WORKFLOW.md` — es el procedimiento; el runbook macOS es la referencia de cada herramienta |
| Running, clicking and screenshotting the app; reading the Design window | `docs/development/AGENT_MACOS_APP_CONTROL.md` |
| Palettes, light/dark, semantic roles | `docs/architecture/appearance-palette-contract.md` |
| **Any visual value, or any shared component** | `docs/development/DESIGN_HANDOFF_SYNC_CONTRACT.md` — read it through `DesignSync`, never off a screenshot |
| Bike workshop architecture | `BIKE_WORKSHOP_MASTER_SCHEMA.md`, updated in the same task when behavior/schema/data-flow changes |

**Un frame de Design no se acepta a ciegas.** Design manda el *look*; que
funcione, que se entienda, que se navegue, las palabras y la armonía con el
resto del ERP los aporta el agente — en escritorio y en móvil. La compuerta de
seis dimensiones y cómo se registra están en
`docs/development/AGENT_VISUAL_WORKFLOW.md` §5.b, y es obligatoria por frame.

Historical prompts, screenshots, feature plans, existing widgets, and aesthetic
snapshot tests do not override the two canonical GUI guides. Do not treat their
literal colors, dimensions, containers, or modal/layout choices as precedent.

For every visual or interaction redesign, Claude is the design lead and reads
the visual truth from Design project `ERP Bikeshop UI Mockups`
(`a0fa3196-6315-4b96-bde7-7cc801e7a74e`) **through the `DesignSync` tool**.

- **Every visual value comes from a Design file, read with `DesignSync`.**
  Colour, radius, shadow, border, spacing, font, height. Reading them off a
  screenshot of the Design window, or estimating them, is prohibited. A value
  that cannot be read is reported as unreadable — never replaced with a
  plausible one.
- **Shared components come from `GUÍA GENERAL Viñabike - Componentes`.** Look
  up the control before writing one, implement it under its id (`S-05`, `O-02`,
  `I-01`…), and bind its values to theme roles — the guide bans literal hex in
  widgets.
- **A module's own screens get their own Design canvas**, not an edit to the
  guide. The guide holds the shared vocabulary; a module page composes it.
- Reconcile that direction with the real domain and the canonical GUI guides,
  and name the page, the turn and the component ids in the handoff. Do not
  invent a competing visual direction in Code or literal-copy stale mock data.

The Design **window** is for two things only: reading what falls past the
256 KiB file cap, and confirming the built result. Not for reading values.

## Database work in one line

All SQL — local and hosted — goes through `scripts/db/query.sh`; the Supabase
CLI never runs SQL and is invoked through `scripts/supabase_cli.sh` for
control-plane work only. Start with `just db-preflight`. Reads are autonomous;
guarded writes are agent-run too since 2026-08-05 («los agentes deben correr
los querys siempre, sin pedir confirmación» — el dueño; corrige «writes need
the owner's go-ahead»). The full contract, including the autonomy boundary and
the guarded-read defaults, is in
`docs/development/AGENT_DATABASE_CONTRACT.md`.

Never use `supabase db query`, `supabase db push`, ad hoc hosted `psql`, or the
hosted SQL Editor.

## Escribe lo que aprendes, antes de cerrar la ronda

Si esta ronda descubrió algo que le habría ahorrado tiempo a quien venga
después —una trampa de una herramienta, una preferencia tuya del dueño, un
documento que resultó falso, una regla de dominio que sólo aparece con datos
reales— **se escribe en la misma tarea**, no al final del proyecto.

`.github/copilot-instructions.md` es el documento padre y tiene la tabla de
qué aprendizaje va a qué archivo. Si el proceso descrito ahí resulta
equivocado o mejorable, **se corrige ahí**: no se rodea ni se documenta la
excepción en otro lado.

Escribe la **causa**, no el síntoma; fecha la corrección cuando contradice algo
anterior; y di el costo real cuando lo hubo — eso es lo que hace que el
siguiente lo lea.

No escribas el relato de la sesión, ni lo que ya se ve en el código o en git.

## Working agreements

- This repository accepts collaborative Claude work only from **Code** mode
  with **Fable 5** (preferred) or **Opus 5**. Use **Effort: Ultracode** when
  workflows/subagents are enabled; use **Effort: xhigh** while the owner has
  them suspended. This is not a quality downgrade: Anthropic defines
  Ultracode as `xhigh` plus automatic workflow orchestration, so the two modes
  cannot truthfully coexist with a zero-subagent rule. Before the first prompt,
  and again after switching chats, verify the visible model, effort,
  `bikeshop-erp` repository and intended chat title/URL immediately before
  Send.
- Never print credential values, full connection strings, or credential-bearing
  commands. Check presence only.
- Multi-tenant: every tenant-scoped query filters `tenant_id`. A missing filter
  is a defect, not a style issue.
- Run the affected tests yourself and report real output. A local pass is not a
  production deployment.
- For non-trivial changes shared with Codex, follow
  `docs/development/CODEX_CLAUDE_COLLABORATION.md`. Claude is the creative lead
  for visual and interaction redesign, while remaining an independent peer
  reviewer of logic. Do not silently agree with Codex: test its assumptions and
  report evidence. Never edit the same files concurrently with another agent.
- The dual-diagnosis gate is for P0/P1 findings and seams involving financial
  integrity, security, tenant isolation, concurrency, navigation ownership or
  another broad invariant. Local visual/mechanical defects are corrected by
  the active lead and bundled into the next block checkpoint; do not stop a
  feature for one review session per control.
- Invoke the `cross-review` skill at a coherent feature/block boundary, not
  after every widget. While subagents are suspended, Claude and Codex perform
  that review directly in the existing primary sessions; do not launch the
  `ui-design-lead`, `logic-cross-reviewer` or `ui-cross-reviewer` agents.
- **Sin techo de herramientas** remains the general project rule, but the owner
  suspended Workflow, agent teams and subagents for the current Payroll
  migration after repeated stalls. The current user settings enforce that
  suspension. Work sequentially in one session until the owner lifts it.
  Browser, Computer Use, DesignSync and the native debug tooling remain
  available.
  **Commit, push, PR, deploy, publicación y escrituras en producción requieren
  autorización explícita del dueño, por acción** (2026-08-01, corrige la
  redacción del 31/07 que decía «commit y push pasan al agente»). El guard
  mecánico dejó de denegar los tres primeros, pero eso mide **capacidad, no
  permiso**: manda `CODEX_CLAUDE_COLLABORATION.md` §Safety boundary — «commits,
  and pushes require the owner's explicit authorization». Una autorización
  puntual **no** se convierte en permiso permanente. Cuando la haya, antes de
  mover `origin` se comprueba que Codex no esté publicando desde este mismo
  checkout —árbol limpio, sin procesos de gate y `HEAD == origin`—: el 31/07 un
  push a destiempo le habría roto el suyo.
