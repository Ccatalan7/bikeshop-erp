# Codex + Claude collaboration

This document applies when the owner explicitly asks Codex to collaborate with
Claude. Normal product work does not require a Claude session. When that
optional collaboration is active, the two agents remain independent reviewers
whose goal is to expose different failure modes before they reach the
application.

## Ownership

| Work | Lead | Required cross-review |
|---|---|---|
| Product workflow, information architecture, visual hierarchy, layout and responsive composition | Codex | Claude may provide an independent proposal or visual review only when explicitly requested |
| Domain logic, database, accounting, inventory, auth, concurrency | Codex | Claude may independently challenge assumptions when explicitly requested |
| Mixed feature | Split by layer and explicit files | Both reviewers; never concurrent edits to the same file |
| Verification infrastructure and release safety | Codex | Claude tries the real workflow and reports usability/friction |

Leadership is not veto power. Claude may reject a Codex implementation or
constraint with evidence; Codex may reject a visually strong design that
breaks business truth, accessibility, canonical actions, or responsive
contracts. Preserve both hypotheses until a test or the running app resolves
the disagreement.

## Mandatory Claude session preflight

Every Claude session used for diagnosis, proposals, implementation, or review
in this repository must pass this visible preflight **before the first prompt
is sent**:

1. The selected surface says **Code**, not Home.
2. The selected repository says `bikeshop-erp`.
3. The model is **Fable 5** (preferred) or **Opus 5**.
4. The effort label says **Effort: Ultracode** while workflows/subagents are
   enabled. While the owner has them suspended, it says **Effort: xhigh**.

Re-run the four checks after navigating to another chat because model, effort,
surface, and repository are session UI state and must not be inferred from a
previous conversation or a saved default. When the effort control is presented
as a slider, move it to the far-right detent, then read the rendered label; the
knob position alone is not evidence. Do not send a split or partial prompt
while changing Home/Code or chat state. Immediately before pressing Send,
confirm the intended chat title or URL as well as all four preflight signals;
changing a selector can move focus to another conversation.

**Correction 2026-08-08 — shared Claude task collision.** The Claude desktop
window is shared mutable UI: another Codex task can change the selected chat
after this task has inspected it, or even between filling the composer and
pressing Send. That race twice redirected supplier-design follow-ups into an
unrelated Website Builder chat and cost a full recovery round each time. Treat
chat identity and composer identity as one short-lived lease: immediately
before filling, read the exact selected task title or URL; immediately after
filling, read the same task and the filled composer again; locate Send from
that same composer rather than from a previously captured coordinate; and do
not send while the target task reports Running. If any identity changes, stop
and reacquire the intended task instead of trying to repair the prompt in the
new chat.

Extra and every effort below `xhigh` are below the acceptance boundary for this
ERP. Anthropic defines Ultracode as `xhigh` plus automatic workflow
orchestration: do not re-enable workflows merely to obtain that label while a
zero-subagent suspension is active. When the suspension is lifted, Claude
subagents use `model: inherit` and start only from a parent session that already
passed the Ultracode preflight.

## Product-design authority and optional Claude review

The Claude desktop app exposes two separate windows in the macOS Dock:
**Claude** and **Design**. `Home` and `Code` are surfaces inside the Claude
window; they are not the Design window. Select the intended Dock window and
confirm its visible title before typing. Never begin a prompt in one window and
continue it in the other.

**Correction 2026-08-09.** Codex leads module product design: information
architecture, workflow, hierarchy, layout, responsive composition and final
integration. It begins from the operator's next useful decision and preserves
proven workflow behavior even when the legacy container or styling is
discarded. Claude collaboration is opt-in and starts only when the owner asks
for it; it supplies an independent proposal or visual review, not mandatory
layout authority.

The Claude Design project **ERP Bikeshop UI Mockups**
(`a0fa3196-6315-4b96-bde7-7cc801e7a74e`) remains a source of optional module
concepts. The shared `GUÍA GENERAL Viñabike - Componentes` remains the standing
source of visual grammar and component anatomy through `DesignSync`. Using the
grammar does not require asking Claude to design the module or creating a new
module canvas.

**Binding on both agents.** Visual values are read from Design files, never
reproduced from a capture of the Design window and never estimated. Shared
controls come from **`GUÍA GENERAL Viñabike - Componentes`** under their
component id, with values bound to theme roles. A dedicated module canvas is
optional reference material, never a prerequisite or layout authority. The full
rule, including how to grep a 260 KB canvas cheaply, is in
[`DESIGN_HANDOFF_SYNC_CONTRACT.md`](DESIGN_HANDOFF_SYNC_CONTRACT.md).

A reviewer who cannot trace a visual value to a Design file rejects it as
unsourced — that is a defect of the same class as a missing `tenant_id` filter,
not a matter of taste.

Codex has explicit freedom to recompose a module from first principles. The
real application and repository are inspected for operator workflow,
domain states, canonical actions, permissions, navigation and return behavior,
real data extremes, platform capabilities, responsive hosts, and global-shell
ownership. They are not a demand to preserve, restyle, or build on top of the
legacy visual composition.

When optional Claude visual review is requested, Codex supplies a bounded
design-input packet that
separates:

1. mandatory domain and UX invariants;
2. proven behavioral primitives, such as adaptive `min`/`max`/`flex` sizing,
   state preservation, overlay geometry, and accessible input contracts; and
3. optional implementation suggestions that Design may discard.

The packet also inventories the real owners of brand, workspace tabs, global
navigation, tools, notifications, and persistent chrome. This protects the
workflow without making existing widgets a visual cage or duplicating shell UI
inside a module.

The component guide is the living source for Vinabike's visual direction and
shared control language. Its current validated grammar is:

- navy communicates record or product identity; a restrained light stage band
  communicates process or navigation state; the body concentrates on the
  current task;
- each zone has one dominant job, completed information collapses to useful
  summaries, future information stays quiet, and equal-weight card walls are
  avoided;
- one action accent carries primary interaction; cyan is reserved for
  high-contrast use on navy; statuses remain tonal and semantic;
- persistent totals and primary actions stay available without duplicating or
  competing with the task;
- desktop density, tablet adaptation and phone task flow are designed
  deliberately; mobile is not a shrunken desktop ERP;
- typography, spacing, radii and shell/navigation behavior form one shared
  Vinabike system rather than module-specific themes.

The rebuilt Payroll experience in the running application is the current
product-wide visual north star and quality bar. What transfers is its visual
language: navy identity against a cool neutral work canvas, a deliberate
surface ladder, restrained interaction and semantic colors, the shared
Poppins/IBM Plex/monospaced-number relationship, compact calm density, modest
geometry and depth, clear action hierarchy, legible states, and polished
interaction feedback.

Payroll is not a product-wide layout template. Its week strip, table, columns,
headers, rails, block arrangement, navigation placement, and payment workflow
must be justified independently in every module. Literal integration defects
also do not become precedent, including duplicated branding, a light control
island inside dark global chrome, or fixed proportions that compress status
and action.

For a shared component or foundation, the canonical Design source must provide the complete
visual cascade from foundation values to semantic roles to component roles.
Roles are named by purpose and host relationship, never by the current hue or
feature (`actionPrimaryOnShell`, not `cyanButton` or `payrollBlue`). The
source includes a component-to-role map and demonstrates that changing one
semantic role updates every intended consumer without recoloring unrelated
success, warning, information, selection, or focus states. Codex then owns the
central Flutter theme/API boundary and the guard against feature-local visual
overrides. Claude may review the catalog and running app when the owner asks.

Optional Design proposals supply reference material, not business facts. Mock data, labels, statuses,
literal colors or dimensions in an old concept are not automatically
canonical. Codex reconciles the concept with the current domain model,
tenant configuration, accessibility, responsive behavior and the repository
GUI guides. If they conflict, Codex rejects or adapts the proposal and records
the reason. Removing duplicate global chrome or replacing a fixed mockup
proportion with an adaptive sizing contract is product design, not a competing
visual direction. Optional Claude review never changes that ownership. Once a
pattern is validated in the running app, record its reusable contract in the
owning repository GUI guide so future agents can apply it without relying on
an inaccessible screenshot.

## Dual diagnosis gate

P0/P1 findings and seams involving financial integrity, security, tenant
isolation, concurrency, navigation ownership or another broad invariant receive
an independent diagnosis from a Codex subagent by default. If the owner has
explicitly requested Claude collaboration, Claude may be the independent
reviewer. The first agent shares only a neutral evidence packet
(symptom, reproduction, affected boundary and relevant files), not its
conclusion, so the second agent does not merely ratify it. Each response must
state:

- reproduced fact versus hypothesis;
- likely root cause and affected invariant;
- severity and blast radius;
- proposed correction, alternatives and important trade-offs;
- minimum regression evidence and remaining uncertainty.

Codex then reconciles the two proposals against repository contracts, tests and
the running app. Agreement is useful but not required: the final decision must
record why one option or a synthesized option won and preserve any material
dissent as an explicit risk. No Claude session is implied by this gate.

Batch related findings into one bounded evidence packet and review them at a
coherent feature/block boundary. Do not start one review session per defect.
Local layout, copy, formatting, syntax and other mechanical defects are repaired
by the active lead and included in the next checkpoint; they do not stop the
feature for a separate dual-diagnosis round. If a local repair reveals one of
the broad invariants above, promote it to this gate.

## Working loop

1. **Baseline:** record branch, HEAD, relevant dirty paths, active processes,
   and the user's actual outcome. Never clean a shared checkout.
2. **Independent diagnosis:** give the lead and chosen independent reviewer the
   same neutral evidence. Each reconstructs the contract and proposes a
   correction before seeing the other's conclusion.
3. **Reconcile design/contract:** Codex compares available diagnoses and proposals,
   names the mandatory invariants, proven behavioral primitives, optional
   suggestions, discardable legacy composition, and global-shell owners, then
   records any material disagreement. For UI, Codex owns from-scratch product
   composition and the final reading of the real app; Claude participates only
   when the owner explicitly requested that collaboration.
4. **Partition:** assign exact files. Do not run simultaneous writers on the
   same file or migration.
5. **Implement:** the lead makes the smallest coherent change that fully
   realizes the approved direction and records what it deliberately left
   untouched. “Smallest” limits unrelated scope; it does not force an
   incremental restyle when a from-scratch composition is the coherent change.
6. **Cross-review:** use an independent Codex subagent by default. If the owner
   explicitly requested Claude, give it enough context to inspect the agreed
   seam. Findings require evidence, not taste, deference, or an arbitrary
   call-count cutoff.
7. **Reconcile:** reproduce disagreements, fix confirmed issues, and have the
   non-author recheck the seam.
8. **Verify:** format, focused analyzer/tests, relevant broader gates, and the
   real app at affected responsive states. A source assertion alone is not UI
   verification.
9. **Handoff:** report exact files, behavior, evidence, known uncertainty, and
   explicitly distinguish local code from commit, push, deployment, or
   production data changes.

## Safety boundary

- Read-only production evidence is gathered through the guarded repository
  workflow. For an implementation, fix, finish, ship, or deploy request, Codex
  also owns the reviewed non-destructive production write/deployment,
  read-back, registration, and smoke needed to make the result active; Claude
  hands that rollout to Codex without asking the owner again. Analysis-only,
  diagnosis-only, draft, and local-only tasks remain read-only. Destructive
  repair, credential rotation, ambiguous targets, unrelated pending changes,
  messages sent on the owner's behalf, and materially broader publication
  still require an explicit owner decision.
- Never print credential values or place them in prompts, settings, MCP files,
  logs, or handoffs.
- Do not add direct Supabase/database MCP access. It bypasses the repository's
  audited database contract.
- **Correction 2026-08-01:** this workspace now uses Claude **Auto mode** by
  default. `bypassPermissions` is exceptional and is not the normal launch
  contract. The project `PreToolUse` guard still runs in either mode. Today it
  blocks production writes, deployment
  (`firebase deploy`, `supabase functions deploy`, `scripts/deploy.sh`),
  `supabase db|migration`, history rewrites, open-scope `git restore`, generic
  process signaling and recursive deletion. It **no longer** blocks
  `git add/commit/push` or `scripts/publish_*` / `scripts/releases/*`.
- **Correction 2026-08-09:** the guard measures **routing and capability, not a
  second permission ceremony**. Claude still does not bypass a denied deploy;
  it hands an in-scope rollout to Codex, which executes the guarded repository
  path under the task authorization defined above. A stale `local-only` or `no
  production writes` handoff stops applying when a later owner instruction asks
  to implement, fix, finish, ship, or deploy the same result. The guard remains
  a hard stop for bypass paths and destructive or ambiguous effects.
- Do not pattern-kill Flutter, Dart, browser, or preview processes. Use the
  canonical preview owner and verified process identity.
- **Sin techo de herramientas** (decisión del owner, 2026-07-31): Workflows,
  agent teams y subagentes anidados quedan disponibles sin aprobación previa.
  - **Suspensión temporal (2026-08-01, tarea de migración visual de Nóminas):**
    el owner pidió **no lanzar subagentes, agent teams ni Workflows** mientras
    dure esa tarea, tras dos corridas que se estancaron. Es una suspensión
    **acotada a esa tarea, no una derogación** de la regla de arriba: quien
    trabaje en otra tarea, o cuando el owner la levante, vuelve al techo
    abierto. Mientras rija, los settings lo hacen fail-closed con
    `disableWorkflows: true` y `permissions.deny: ["Agent"]`; se trabaja
    secuencialmente en una sola sesión, con esfuerzo `xhigh`, y no se persigue
    la etiqueta Ultracode reactivando aquello que el owner suspendió.
  El agente elige la herramienta que el problema pide y usa criterio para no
  gastar de más.
- Start with one Claude session and a coherent evidence packet, but budget by
  unresolved risk rather than a small fixed tool count. Claude may inspect the
  running app, follow relevant code/data paths and execute focused tests until
  it can support the diagnosis. Codex may authorize another sequential
  specialist when the first pass exposes a distinct uncovered seam; state that
  expansion and its reason at the next owner checkpoint.
- Do not impose a project-level thinking-token or tool-call ceiling on the
  primary Claude session. Let the selected effort mode adapt to the problem;
  cost control applies to fan-out and repetitive exploration, not to truncating
  a coherent investigation before it can synthesize.
- Anidar agentes está permitido. El efecto real se rige por el alcance vigente:
  una implementación/fix/ship incluye su rollout normal no destructivo; una
  reparación destructiva, target ambiguo, mensaje en nombre del dueño o
  expansión ajena al resultado sigue requiriendo su decisión.
- Reviewers reserve capacity for synthesis. When a reviewer is already near its
  conclusion, let it finish; if exploration is becoming repetitive, request a
  conclusion with current evidence instead of interrupting or enforcing an
  arbitrary low ceiling.
- The parent performs the final synthesis without tools or additional agents.
  More review rounds need a newly stated evidence gap and cost checkpoint.

## Continuity and compaction

The handoff is a recovery mechanism, not a routine phase of each implementation
round. Continue in the same primary chat while it remains healthy. Automatic
compaction starts at the configured 70% threshold; use `/compact` with the
current feature focus if a manual boundary is useful. Open a new chat only when
compaction fails, the session is unusable, or ownership crosses a real work
boundary. Never pause an otherwise active implementation merely to prepare a
handoff. Durable discoveries still go into their owning repository document in
the same round.

## Handoff packet

Every agent-to-agent handoff contains:

- outcome requested and acceptance criteria;
- branch/HEAD and relevant dirty files;
- exact files owned and files that must not be touched;
- canonical documents already read;
- for UI work, the shared component ids and visual roles used; when optional
  Claude/Design input was requested, also the Design page/concept; global-shell owners, workflow,
  navigation and state truths, proven behavioral primitives, discardable
  legacy composition, and the Payroll visual traits that transfer without its
  layout;
- implementation summary and important state transitions;
- commands/tests with real outcomes;
- screenshots or viewports/states observed for UI work;
- confirmed defects, competing hypotheses, and remaining uncertainty;
- external actions not taken.

## Claude session starter

Use this prompt for a new Claude session in this checkout:

> Confirma primero que esta sesión está en Code, repo `bikeshop-erp`,
> Fable 5 (preferido; Opus 5 permitido) y el esfuerzo máximo permitido por la
> política activa: Ultracode con workflows habilitados; xhigh durante una
> suspensión de subagentes. Si no ves esas cuatro señales, no empieces el
> trabajo. Trabaja como par independiente de
> Codex en Vinabike ERP. Antes de editar,
> lee `CLAUDE.md`, `AGENTS.md` y
> `docs/development/CODEX_CLAUDE_COLLABORATION.md`; registra branch, HEAD y
> archivos sucios sin limpiar nada. Si el trabajo incluye rediseño visual,
> actúa como revisor independiente de la composición que Codex posee; usa la
> `GUÍA GENERAL Viñabike - Componentes` como lenguaje visual y abre un concepto
> específico de Design sólo si el owner lo pidió. Inspecciona la app,
> el repo y los datos reales para conocer flujo, acciones, estados, navegación,
> extremos de datos y ownership del shell, no para conservar o maquillar la
> composición visual heredada. Propón una alternativa from scratch cuando
> encuentres un problema, sin asumir autoridad sobre el layout final. Usa
> Nóminas como lenguaje visual y estándar de calidad, nunca como
> plantilla obligatoria de layout. Trata los componentes existentes que Codex
> entregue como evidencia de comportamiento salvo que la guía los haya
> promovido explícitamente al sistema visual compartido. Si el concepto está
> obsoleto o contradice el dominio, refínalo antes de implementar. Si el
> trabajo es lógico, reconstruye el contrato y desafía explícitamente las
> hipótesis de Codex. Para cada problema nuevo recibe sólo evidencia neutral y
> entrega tu propio diagnóstico, causa raíz, severidad, propuesta, alternativas
> y regresión mínima antes de leer la conclusión de Codex; Codex hará lo mismo
> de forma independiente antes de implementar. Divide ownership por archivos,
> nunca escribas a la vez en
> los mismos archivos que otro agente. Mientras siga la suspensión de Nóminas,
> no uses Workflow, agent teams ni subagentes; realiza el cross-review directo
> con Codex al cierre de cada bloque coherente. Cuando el owner levante esa
> suspensión vuelve a regir el techo abierto de herramientas. No rodees el
> guard para ejecutar efectos externos: entrega a Codex todo rollout normal,
> no destructivo e in-scope que complete una implementación/fix/ship, sin pedir
> otra confirmación al dueño. Mantén read-only un análisis o `local-only`, y
> escala sólo destrucción, credenciales, target ambiguo, mensajes o expansión de
> alcance. Entrega evidencia real y desacuerdos pendientes; no respondas por
> deferencia.

For a review-only continuation, append:

> Permanece read-only en la primera pasada. Revisa el diff y la app sin leer la
> conclusión del otro agente; por cada hallazgo entrega evidencia, diagnóstico,
> causa raíz, severidad, propuesta de solución, alternativas, regresión mínima
> y líneas. Después agrega fortalezas verificadas.
