# Codex + Claude collaboration

This repository uses the two agents as independent peers with different
leadership domains. The goal is not consensus; it is to expose different
failure modes before they reach the application.

## Ownership

| Work | Lead | Required cross-review |
|---|---|---|
| Visual hierarchy, interaction redesign, responsive composition | Claude | Codex checks contracts, state truth, navigation, data and integration; Claude performs the final visual pass |
| Domain logic, database, accounting, inventory, auth, concurrency | Codex | Claude independently challenges assumptions and missing cases |
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
4. The effort label says exactly **Effort: Ultracode**.

Re-run the four checks after navigating to another chat because model, effort,
surface, and repository are session UI state and must not be inferred from a
previous conversation or a saved default. When the effort control is presented
as a slider, move it to the far-right detent, then read the rendered label; the
knob position alone is not evidence. Do not send a split or partial prompt
while changing Home/Code or chat state. Immediately before pressing Send,
confirm the intended chat title or URL as well as all four preflight signals;
changing a selector can move focus to another conversation.

Extra and every lower effort are below the acceptance boundary for this ERP.
If any material work was produced there, stop using that result as accepted
evidence and have Fable 5 or Opus 5 independently re-review it in Ultracode.
Claude subagents use `model: inherit`; start them only from a parent session
that already passed this preflight.

## Claude Design authority

The Claude desktop app exposes two separate windows in the macOS Dock:
**Claude** and **Design**. `Home` and `Code` are surfaces inside the Claude
window; they are not the Design window. Select the intended Dock window and
confirm its visible title before typing. Never begin a prompt in one window and
continue it in the other.

Claude leads every visual or interaction redesign. Before proposing or
implementing one, Claude reads the latest relevant concept from the Claude
Design project **ERP Bikeshop UI Mockups**
(`a0fa3196-6315-4b96-bde7-7cc801e7a74e`) **with the `DesignSync` tool**, then
inspects the real application and its canonical data/workflow. The handoff
names the Design page, turn and component ids used so the implementation and
final review share the same visual reference.

**Binding on both agents.** Visual values are read from Design files, never
reproduced from a capture of the Design window and never estimated. Shared
controls come from **`GUÍA GENERAL Viñabike - Componentes`** under their
component id, with values bound to theme roles. A module's screens are designed
on their own Design canvas rather than by editing the shared guide. The full
rule, including how to grep a 260 KB canvas cheaply, is in
[`DESIGN_HANDOFF_SYNC_CONTRACT.md`](DESIGN_HANDOFF_SYNC_CONTRACT.md).

A reviewer who cannot trace a visual value to a Design file rejects it as
unsourced — that is a defect of the same class as a missing `tenant_id` filter,
not a matter of taste.

Claude Design has explicit freedom to recompose a module from first principles.
The real application and repository are inspected for operator workflow,
domain states, canonical actions, permissions, navigation and return behavior,
real data extremes, platform capabilities, responsive hosts, and global-shell
ownership. They are not a demand to preserve, restyle, or build on top of the
legacy visual composition.

Before visual exploration, Codex supplies a bounded design-input packet that
separates:

1. mandatory domain and UX invariants;
2. proven behavioral primitives, such as adaptive `min`/`max`/`flex` sizing,
   state preservation, overlay geometry, and accessible input contracts; and
3. optional implementation suggestions that Design may discard.

The packet also inventories the real owners of brand, workspace tabs, global
navigation, tools, notifications, and persistent chrome. This protects the
workflow without making existing widgets a visual cage or duplicating shell UI
inside a module.

The Design project is the living source for Vinabike's visual direction and
interaction language. Its current validated grammar is:

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

For a shared component or foundation, Claude Design must provide the complete
visual cascade from foundation values to semantic roles to component roles.
Roles are named by purpose and host relationship, never by the current hue or
feature (`actionPrimaryOnShell`, not `cyanButton` or `payrollBlue`). The
handoff includes a component-to-role map and demonstrates that changing one
semantic role updates every intended consumer without recoloring unrelated
success, warning, information, selection, or focus states. Codex then owns the
central Flutter theme/API boundary and the guard against feature-local visual
overrides; Claude performs the catalog and running-app visual review.

Design supplies direction, not business facts. Mock data, labels, statuses,
literal colors or dimensions in an old concept are not automatically
canonical. Claude must reconcile the concept with the current domain model,
tenant configuration, accessibility, responsive behavior and the repository
GUI guides. If they conflict, Claude refines the Design concept first or
records the deliberate divergence. Codex may adapt implementation within the
agreed visual direction when required by shell ownership, canonical navigation
or actions, real data, accessibility, responsive behavior, or a validated
behavioral primitive. Removing duplicate global chrome or replacing a fixed
mockup proportion with an adaptive sizing contract is integration work, not a
competing visual direction. Claude performs the final visual review. Once a
pattern is validated in the running app, record its reusable contract in the
owning repository GUI guide so future agents can apply it without relying on
an inaccessible screenshot.

## Dual diagnosis gate

Every newly identified non-trivial defect must receive an independent diagnosis
and solution proposal from **both Codex and Claude before implementation**. The
first agent shares only a neutral evidence packet (symptom, reproduction,
affected boundary and relevant files), not its conclusion, so the second agent
does not merely ratify it. Each response must state:

- reproduced fact versus hypothesis;
- likely root cause and affected invariant;
- severity and blast radius;
- proposed correction, alternatives and important trade-offs;
- minimum regression evidence and remaining uncertainty.

Codex then reconciles the two proposals against repository contracts, tests and
the running app. Agreement is useful but not required: the final decision must
record why one option or a synthesized option won and preserve any material
dissent as an explicit risk. Neither agent may skip the other's diagnostic
because it is the domain lead.

Batch related findings into one bounded evidence packet and one response per
agent. Do not start one Claude session per defect. A purely mechanical failure
discovered while running an already-approved correction (formatting, syntax or
an expectation made obsolete by the test's own new fixture) may be repaired
locally, but it must be included in the next shared review packet if it changes
behavior or the proposed design.

## Working loop

1. **Baseline:** record branch, HEAD, relevant dirty paths, active processes,
   and the user's actual outcome. Never clean a shared checkout.
2. **Independent diagnosis:** give both agents the same neutral evidence. Each
   reconstructs the contract and proposes a correction before seeing the
   other's conclusion.
3. **Reconcile design/contract:** Codex compares both diagnoses and proposals,
   names the mandatory invariants, proven behavioral primitives, optional
   suggestions, discardable legacy composition, and global-shell owners, then
   records any material disagreement. For UI, Claude owns from-scratch design
   exploration and the final visual reading of the real app.
4. **Partition:** assign exact files. Do not run simultaneous writers on the
   same file or migration.
5. **Implement:** the lead makes the smallest coherent change that fully
   realizes the approved direction and records what it deliberately left
   untouched. “Smallest” limits unrelated scope; it does not force an
   incremental restyle when a from-scratch composition is the coherent change.
6. **Cross-review:** give Claude enough tools and context to inspect every
   relevant high-risk seam and have Codex audit the complementary seams. Start
   with one coherent reviewer/session, then add a specialized pass when new
   evidence exposes a genuinely different domain. Findings require evidence,
   not taste, deference, or an arbitrary call-count cutoff.
7. **Reconcile:** reproduce disagreements, fix confirmed issues, and have the
   non-author recheck the seam.
8. **Verify:** format, focused analyzer/tests, relevant broader gates, and the
   real app at affected responsive states. A source assertion alone is not UI
   verification.
9. **Handoff:** report exact files, behavior, evidence, known uncertainty, and
   explicitly distinguish local code from commit, push, deployment, or
   production data changes.

## Safety boundary

- Read-only production evidence may be gathered through the guarded repository
  workflow. Production writes, deployment, publication, messages, commits, and
  pushes require the owner's explicit authorization.
- Never print credential values or place them in prompts, settings, MCP files,
  logs, or handoffs.
- Do not add direct Supabase/database MCP access. It bypasses the repository's
  audited database contract.
- Claude Desktop currently launches its local agent in `bypassPermissions`.
  The project `PreToolUse` guard therefore blocks production writes, deployment,
  publication, commit/push/PR operations, destructive Git cleanup, generic
  process signaling, and recursive deletion even when ordinary permission
  prompts are skipped. An owner-authorized external mutation is handed back to
  Codex or performed from a fresh non-bypass session with the guard deliberately
  reviewed for that exact action.
- Do not pattern-kill Flutter, Dart, browser, or preview processes. Use the
  canonical preview owner and verified process identity.
- **Sin techo de herramientas** (decisión del owner, 2026-07-31): Workflows,
  agent teams y subagentes anidados quedan disponibles sin aprobación previa.
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
- Anidar agentes está permitido. Lo que sigue requiriendo autorización no es
  la herramienta sino el EFECTO REAL: commit, push, deploy, publicación y
  escrituras en producción.
- Reviewers reserve capacity for synthesis. When a reviewer is already near its
  conclusion, let it finish; if exploration is becoming repetitive, request a
  conclusion with current evidence instead of interrupting or enforcing an
  arbitrary low ceiling.
- The parent performs the final synthesis without tools or additional agents.
  More review rounds need a newly stated evidence gap and cost checkpoint.

## Handoff packet

Every agent-to-agent handoff contains:

- outcome requested and acceptance criteria;
- branch/HEAD and relevant dirty files;
- exact files owned and files that must not be touched;
- canonical documents already read;
- for UI work, the Design page/concept, global-shell owners, workflow,
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
> Fable 5 (preferido; Opus 5 permitido) y Effort: Ultracode. Si no ves esas
> cuatro señales, no empieces el trabajo. Trabaja como par independiente de
> Codex en Vinabike ERP. Antes de editar,
> lee `CLAUDE.md`, `AGENTS.md` y
> `docs/development/CODEX_CLAUDE_COLLABORATION.md`; registra branch, HEAD y
> archivos sucios sin limpiar nada. Si el trabajo incluye rediseño visual,
> asume liderazgo creativo: abre la ventana separada Design, inspecciona el
> concepto relevante más reciente de `ERP Bikeshop UI Mockups`, nombra la
> página/concepto usado y valida desktop, tablet y teléfono. Inspecciona la app,
> el repo y los datos reales para conocer flujo, acciones, estados, navegación,
> extremos de datos y ownership del shell, no para conservar o maquillar la
> composición visual heredada. Recompón from scratch cuando sea la mejor
> solución. Usa Nóminas como lenguaje visual y estándar de calidad, nunca como
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
> los mismos archivos que otro agente. Usa un solo revisor para el riesgo
> principal, y elige libremente Workflow, agent teams o agentes anidados si el
> problema los pide: no hay techo de herramientas. Ejecuta el
> skill `cross-review` antes de declarar terminado. No hagas commit, push,
> deploy, publicación ni escritura en producción sin autorización explícita.
> Entrega evidencia real y desacuerdos pendientes; no respondas por deferencia.

For a review-only continuation, append:

> Permanece read-only en la primera pasada. Revisa el diff y la app sin leer la
> conclusión del otro agente; por cada hallazgo entrega evidencia, diagnóstico,
> causa raíz, severidad, propuesta de solución, alternativas, regresión mínima
> y líneas. Después agrega fortalezas verificadas.
