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
| Duplicados, matching de catálogo, «¿ya existe este producto?» | `docs/architecture/product-identity-matching-contract.md` |
| Bike workshop architecture | `BIKE_WORKSHOP_MASTER_SCHEMA.md`, updated in the same task when behavior/schema/data-flow changes |

**Un frame de Design no se acepta a ciegas.** La guía manda la gramática
visual; Codex posee flujo, jerarquía, layout, responsive, funcionamiento,
navegación y palabras. La compuerta de
seis dimensiones y cómo se registra están en
`docs/development/AGENT_VISUAL_WORKFLOW.md` §5.b, y es obligatoria por frame.

Historical prompts, screenshots, feature plans, existing widgets, and aesthetic
snapshot tests do not override the two canonical GUI guides. Do not treat their
literal colors, dimensions, containers, or modal/layout choices as precedent.

For every visual or interaction redesign, Codex is the product-design lead.
Shared visual truth comes from `GUÍA GENERAL Viñabike - Componentes` in Design
project `ERP Bikeshop UI Mockups` through `DesignSync`. Claude participates
only when the owner explicitly requests an independent proposal or review.

### Abrir DesignSync: el id va explícito, `list_projects` NO sirve

**`projectId = a0fa3196-6315-4b96-bde7-7cc801e7a74e`** (`ERP Bikeshop UI
Mockups`). Pásalo a `get_file` / `list_files` **siempre**.

`DesignSync list_projects` devuelve `[]` **por diseño**: lista sólo proyectos de
tipo *design-system*, y éste es `PROJECT_TYPE_PROJECT`. **Un `[]` no significa
que falte autorización.** Ya costó dos sesiones bloqueadas concluyendo que el
dueño tenía que aprobar algo; no hay nada que aprobar. Si dudas, compruébalo con
`get_project` sobre ese id: devuelve `canEdit: true`.

Las tres rutas que se usan casi siempre:

- `GUÍA GENERAL Viñabike - Componentes.dc.html` — componentes compartidos.
- `Arquitectura de Paletas - Viñabike.dc.html` — roles y modo oscuro.
- `<módulo>.dc.html` (p. ej. `Compras · Asistente inteligente navegable.dc.html`)
  — la composición, que el `spec.json` **no** trae.

`get_file` sobre >50 KB guarda a disco y sólo te entra un preview: se greppea,
no se carga. La guía **ya pasó el cap de 256 KiB** y se corta en 262 144 bytes
**sin avisar** — si un rol no aparece, puede estar fuera del corte, no ausente.
Procedimiento completo en `docs/development/DESIGN_HANDOFF_SYNC_CONTRACT.md`.

- **Every visual value comes from a Design file, read with `DesignSync`.**
  Colour, radius, shadow, border, spacing, font, height. Reading them off a
  screenshot of the Design window, or estimating them, is prohibited. A value
  that cannot be read is reported as unreadable — never replaced with a
  plausible one.
- **Shared components come from `GUÍA GENERAL Viñabike - Componentes`.** Look
  up the control before writing one, implement it under its id (`S-05`, `O-02`,
  `I-01`…), and bind its values to theme roles — the guide bans literal hex in
  widgets.
- **A module canvas is optional.** The guide holds the shared vocabulary;
  Codex composes it from the operator workflow and the real application.
- Reconcile any optional proposal with the real domain and canonical GUI
  guides. Name a page/turn only when that optional source was actually used;
  always name the shared component ids.

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
- When the owner explicitly requests collaboration with Codex, follow
  `docs/development/CODEX_CLAUDE_COLLABORATION.md`. Claude remains an
  independent reviewer; Codex retains product/layout ownership. Do not silently
  agree with Codex: test its assumptions and report evidence. Never edit the
  same files concurrently with another agent.
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
  **Corrección del dueño, 2026-08-09, precisada el 2026-08-20:** una tarea de
  implementar, arreglar, terminar, ship o deploy incluye el rollout productivo
  normal, no destructivo y ya revisado, y **Claude lo corre**. Migraciones
  in-scope van por `scripts/db/deploy_migration.sh` con
  `VINABIKE_DB_WRITE_CONFIRM=production` y su archivo `--verify`; el hook no las
  deniega —verificado corriendo, no leyendo, el 2026-08-20—. No se le entrega el
  SQL a Codex ni se le devuelve al dueño una confirmación rutinaria, y no se
  conserva un `no production writes` de un subtask anterior después de una
  instrucción posterior de terminar. Lo que se reporta es el read-back. Análisis,
  diagnóstico, draft y `local-only` siguen read-only mientras sean la
  instrucción vigente. Reparaciones destructivas, rotación de credenciales,
  targets ambiguos, publicación más amplia y cambios ajenos al alcance sí
  requieren una decisión explícita. Antes de mover `origin` se comprueba que
  Codex no esté publicando desde este mismo checkout —árbol limpio, sin procesos
  de gate y `HEAD == origin`—.
