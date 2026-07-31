# Handoff: complete Payroll end to end

Date: 2026-07-30  
Repository: `/Users/Claudio/Dev/bikeshop-erp`  
Branch: `smartpegas1.0`  
Baseline HEAD: `32404d36bcae026a1560cf0080f85f6ac7cdf157`

## Required outcome

Take over the unfinished Payroll work and deliver one coherent, usable module:

1. the Claude Design visual language is reproduced faithfully on desktop,
   tablet and phone;
2. light and dark mode are complete across every Payroll surface, state,
   overlay, background and empty remainder;
3. bank-statement import works end to end: choose PDF/image/camera where
   supported, extract, match, review every transfer, answer cash payments,
   apply the reviewed batch atomically and show durable evidence;
4. weeks, History, Advances, manual payment, cash, evidence and reconciliation
   are complete and contain no "coming later" placeholders;
5. shell integration does not duplicate branding or workspace/global controls;
6. focused analyzer, Flutter tests, database gates and the native macOS
   workflow provide real evidence.

Do not call the module complete while the visible OCR action is blocked or any
registered Payroll surface is only partially dark-mode compatible.

## Mandatory first artifact and checkpoint

Before editing any source file:

1. perform the repository/session preflight below;
2. inspect the relevant Claude Design concepts, real source and dirty state;
3. create `docs/development/PAYROLL_COMPLETION_PLAN.md`;
4. make that plan exhaustive, ordered and checkable, covering visual,
   responsive, workflow, backend activation, tests and real-app validation;
5. present the plan in the Claude chat and wait for the owner to approve or
   explicitly tell you to continue.

Keep the plan current as work progresses. A punctual user correction must be
fixed without abandoning the remaining plan.

## Claude session preflight

Do not start unless the visible Claude UI shows all four:

- **Code**, never Home;
- repository **bikeshop-erp**;
- model **Fable 5**;
- **Effort: Ultracode** exactly.

Read completely before editing:

- `CLAUDE.md`
- `AGENTS.md`
- `.github/copilot-instructions.md`
- `.github/GUI_DESIGN_PRINCIPLES.md`
- `.github/GUI_MOBILE_DESIGN_PRINCIPLES.md`
- `docs/architecture/canonical-ui-surfaces.md`
- `docs/architecture/universal-ui-component-system.md`
- `docs/development/CODEX_CLAUDE_COLLABORATION.md`
- `docs/development/AGENT_DATABASE_CONTRACT.md`

Record current branch, HEAD, dirty paths and active processes. Never clean,
reset, stash, overwrite or otherwise discard the shared checkout.

## Visual authority and Design reference

Visual authority belongs strictly to Claude Design. Use the separate Design
window and inspect the latest Payroll work in project **ERP Bikeshop UI
Mockups**, page **Nóminas - Rediseño**, including frames/concepts **2a-2e** and
**3a-3c**.

The existing exact Payroll Design tokens remain visible in
`lib/modules/hr/payroll/theme/payroll_tokens.dart`. Do not replace their cool
neutral language with generic warm Material greys or invent colors/opacities
by eye.

Claude may improve dimensions, adaptive distribution, information density,
responsive recomposition, accessibility and UX when real data or shell
ownership requires it. The looking itself - palette relationships,
typography, surfaces, borders, shadows, radii, icon treatment and component
states - must come from Claude Design. If Design did not define a visual state,
identify the missing state and resolve it coherently from the same Design
system before implementing it.

Important integration rule: Payroll is the visual north star, not a universal
layout template. Preserve one global brand mark, real workspace behavior,
adaptive columns, canonical actions and return navigation.

### Palette and brightness architecture — mandatory

Viñabike already has selectable appearance palettes/presets, including the
MainLayout palette chosen by the owner. The target is a Slack-like theme
system: the selected preset must drive the whole application coherently in
both light and dark mode, not merely recolor the left navigation.

Trace and use the existing canonical pipeline before adding any visual value:

- `AppearancePreset` / the persisted selected palette;
- `VinabikeThemeResolver`;
- `VinabikeThemeRoles`;
- `WorkspaceChromeTheme`;
- `ThemeData.colorScheme` and semantic component roles consumed by Payroll.

For every selected preset, define/verify a complete **light role set** and a
complete **dark role set**. Dark mode is not “make everything black”; it must
derive tinted dark canvas, surface and raised-surface layers from the selected
palette, with deliberate contrast. Light mode must retain Claude Design's cool
neutral surface ladder and must not drift into warm/pink Material greys.

Buttons, inputs, search fields, dropdowns, popovers, date pickers, chips,
banners, tables, selected/expanded rows, focus/hover/pressed/disabled states,
dividers, overlays, toolbars and navigation chrome must consume semantic theme
roles. Do not embed module-specific literal colors or ad-hoc opacity blends.
Changing a preset's primary action hue (for example cyan to orange) should
update every component assigned that semantic role without editing individual
screens. Semantic success/warning/error/information colors remain distinct and
contrast-safe rather than being blindly recolored by the brand accent.

Payroll must prove this architecture, not introduce a private Payroll-only
theme. If a required role is missing, add it once at the canonical theme
boundary with light/dark and preset-aware definitions, then migrate Payroll
consumers to it. Before changing shared theme files, audit their non-Payroll
consumers and add regression coverage for at least two materially different
presets in both brightness modes.

## Current state: do not assume it is finished

### Working or substantially implemented

- New Payroll shell, week queue, History, payment composer, evidence surfaces,
  reconciliation review, compact person cards and responsive tests exist.
- The real bank PDF was validated locally through current extraction/parser:
  embedded PDF text, five pages, 96 parsed movements and no parser warnings.
- The real statement includes regular salary transfers, an intentionally
  unrelated manager transfer and one small bounded variance. The matcher must
  keep the unrelated transfer manual/unmatched and must not require exact
  equality.
- Upload/extraction/parser/matcher/review/apply code paths exist.
- History pagination UI and stale-response protections were added.
- Advances surface now exposes optional paginated states
  (`hasMore`, `isLoadingMore`, `paginationError`, `onLoadMore`) with focused
  tests, but the coordinating page does not yet consume the ledger read model.

### Confirmed blockers and incomplete work

1. **OCR is not usable in the running app.** The visible action returns before
   navigation when versioned Payroll capability is absent.
2. Guarded read-only production evidence shows the versioned Payroll backend
   is not installed: `reconciliation_version`, reconciliation/evidence/alias
   tables and create/apply/v2 RPCs are absent.
3. Do not bypass that gate with legacy per-voucher writes. The legacy command
   is not atomic or idempotent for a reviewed multi-week bank batch and cannot
   preserve row fingerprints/decisions/evidence safely.
4. Preparing a read-only preview also needs a graceful missing-backend path:
   the prior-decision read currently assumes a reconciliation table exists.
5. The minimum safe backend dependency chain is explicit and must not be
   shortened:
   1. `20260728010000_harden_hr_payroll_authorization.sql`
   2. `20260728020000_include_employee_advances_in_expense_trace.sql`
   3. `20260728213000_add_payroll_statement_reconciliation.sql`
   The reconciliation migration intentionally aborts if the advance expense
   trace invariant/index from step 2 is absent. Do **not** apply step 3 alone.
   Complete the production feature with, in order:
   4. `20260729173000_add_payroll_settlement_evidence_read_model.sql`
   5. `20260729190000_learn_payroll_beneficiary_alias.sql`
   6. `20260729210000_prepare_payroll_voucher_draft_v2.sql`
   7. `20260729220000_add_payroll_audit_pagination_read_models.sql`
   The current hashes of all seven files match an existing production-derived
   validation capture. Focused reconciliation and audit-pagination suites are
   green there. The remaining SQL gate defect is a stale authorization test
   that still calls the intentionally revoked legacy draft generator; update
   that test to exercise the v2 contract, rerun the full relevant gate, and
   only then prepare guarded deployment/read-back/version registration.
6. Production writes or migration deployment are **not authorized** by this
   handoff. Prepare, validate and request explicit owner authorization at the
   actual deployment boundary.
7. Advances ledger state/pagination is not wired into
   `payroll_redesign_page.dart`; inactive people with historical advances also
   need an authoritative discoverable read model.
8. Several legacy static `PayrollTokens` colors still leak into live
   brightness-aware surfaces, especially page-level backgrounds, dialogs,
   Advances and compact states. This caused a light canvas to remain visible
   in dark Week view while History happened to render dark correctly.
9. A recent Codex attempt changed the shared light surface ladder and then
   partially restored the exact cool Design values. Treat the following files
   as unverified, not as accepted visual truth:
   - `lib/shared/themes/app_theme.dart`
   - `lib/shared/themes/vinabike_theme_resolver.dart`
   - `lib/modules/hr/payroll/theme/payroll_tokens.dart`
   - `lib/modules/hr/payroll/payroll_redesign_page.dart`
10. The selected/expanded Payroll surface currently conflates three meanings:
    expanded disclosure, selected History week and applied advance. Split
    semantics, but obtain/confirm the visual states from Design rather than
    inventing opacities.
11. The latest Codex test run was interrupted for this handoff. Do not claim
    those concurrent theme edits are green.

## File ownership

Claude owns the following scope for this continuation after the plan is
approved:

- `lib/modules/hr/pages/payroll_reconciliation_page.dart`
- `lib/modules/hr/payroll/**`
- `lib/modules/hr/services/payroll_*`
- `lib/modules/hr/models/payroll_*`
- focused Payroll tests under `test/unit/` and `test/widgets/`
- the Payroll migrations listed above
- `docs/development/PAYROLL_COMPLETION_PLAN.md`
- Payroll entries in `docs/architecture/canonical-ui-surfaces.md`

Shared theme files may be edited only after first tracing their non-Payroll
consumers and covering the blast radius:

- `lib/shared/themes/app_theme.dart`
- `lib/shared/themes/vinabike_theme_resolver.dart`
- `lib/shared/themes/vinabike_theme_roles.dart`

Do not edit Website Builder/storefront files, unrelated migrations or another
task's files. If shared ownership is unclear, stop and report the overlap.
Codex will not edit the Payroll scope while this handoff is active.

## Canonical workflow and invariants

- Attendance owns hours and rates. Payroll settles what Attendance closed; it
  does not silently correct attendance.
- Each bank row requires an explicit reviewed outcome. Extra transfers must
  not become payroll merely because the beneficiary name matches.
- Date matching must tolerate normal payment timing around the weekly period,
  including several days after week close.
- Amount matching must support bounded variance and partial payments without
  treating an unrelated small transfer as salary.
- Cash never appears in the statement; ask explicitly whether it was paid,
  date, actor and any advance allocation.
- Payments, advances, ignored rows and holds preserve durable audit evidence.
- One reviewed batch applies atomically and idempotently.
- No raw statement text, bank account number or other sensitive statement
  content may be logged.
- Routed detail/editor closure uses `ReturnNavigation.close`.
- Desktop, tablet and phone use one state owner; mobile is a deliberate task
  flow, not a squeezed table.

## Running-app constraint

There is one canonical native macOS debug session already running:

- Flutter owner PID observed at handoff: `5412`
- app PID observed at handoff: `6800`
- target: `lib/main.dart`, device `macos`

Do **not** start another Flutter session. Do **not** run the Claude browser,
Chrome preview or Claude computer-use browser; the owner explicitly prohibited
that for this work because it overheats and slows the Mac. Batch changes and
coordinate hot reload/restart through the existing native session only when
needed. Never pattern-kill Flutter or Dart processes.

## Verification expectations

At minimum:

- format and focused analyzer;
- extraction, parser, matcher, reconciliation service and page tests;
- Payroll queue, History, Advances, payment, evidence, light/dark and
  responsive widget tests;
- migration/pgTAP gates according to the database contract;
- real native app review at desktop and compact widths in light and dark;
- one real statement smoke test after backend activation is explicitly
  authorized;
- final `cross-review` before declaring complete.

Known prior evidence:

- focused parser/extraction/matcher/service/responsive workflow tests passed;
- the real PDF extraction/parser path works;
- a local database Payroll suite previously reported 235 passing checks;
- the authorization hardening suite still had three failures around a revoked
  legacy draft-generation call and its cascades;
- seven recent Flutter failures were light-theme expectations during concurrent
  theme edits, not parser/matcher failures.

Re-run everything from the current checkout. Do not quote these historical
outcomes as current green evidence.

## External actions not taken

- no commit;
- no push or pull request;
- no deployment;
- no production database write;
- no migration installation;
- no payroll payment or reconciliation applied.
