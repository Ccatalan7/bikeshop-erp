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
writes need the owner's go-ahead. The full contract, including the autonomy
boundary and the guarded-read defaults, is in
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
  with **Fable 5** (preferred) or **Opus 5** and **Effort: Ultracode**.
  Before the first prompt, and again after switching chats, verify those visible
  labels plus the `bikeshop-erp` repository. If the effort control is a slider,
  move it to the far-right detent and confirm that the rendered label says
  `Effort: Ultracode`; never infer the value from the knob position. Work
  produced in Extra or a lower effort must be re-reviewed in Ultracode before
  it can be accepted. Immediately before Send, re-check the intended chat
  title or URL because changing a selector can move focus to another chat.
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
- Every newly identified non-trivial defect passes the dual diagnosis gate:
  Claude and Codex independently state evidence, root cause, severity, proposed
  correction, alternatives, minimum regression and uncertainty before either
  implements it. Work from a neutral evidence packet and do not read or ratify
  the other agent's conclusion on the first pass. Batch related defects into one
  bounded review instead of starting a session per defect.
- Invoke the `cross-review` skill before declaring shared work complete. Use
  `ui-design-lead` for visual redesign, `logic-cross-reviewer` for independent
  contract review, and `ui-cross-reviewer` for a final visual review. Start
  with one coherent reviewer, but let it use enough tools to resolve the
  evidence; Codex may add a sequential specialist for a distinct uncovered
  seam and must report the reason at the next cost checkpoint.
- **Sin techo de herramientas** (decisión del owner, 2026-07-31, reemplaza la
  restricción anterior): el agente elige libremente Workflow, agent teams,
  subagentes anidados, Browser y cuantas sesiones necesite. Usa el criterio
  para no gastar de más, pero no pidas permiso para elegir una herramienta.
  Lo que sigue requiriendo autorización es lo que TOCA ALGO REAL: commit,
  push, deploy, publicación y escrituras en producción.
