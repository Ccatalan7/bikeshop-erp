# Bike Workshop V1 Implementation Spec

## Handoff Signatures

- Planning updates, architecture notes, and non-visual groundwork handoff in this cycle: GPT-5.4
- The agent implementing or refining the UI from this handoff should sign as: Gemini 3.1 Pro
- Record-mode UI integration and job-context summary hardening: GitHub Copilot (GPT-5.4)

## Why This Is The Best Next Step

The best next step is not a full schema redesign and not immediate broad coding across the whole workshop module.

The best next step is a tightly scoped V1 that delivers visible mechanic value fast while preserving room to evolve:

1. guided bike intake instead of flat bike CRUD
2. structured bike profile storage for first-time intake and technical baseline
3. encyclopedia-assisted suggestions
4. bike context summary inside the mechanic job flow

This is the highest-value slice because it fixes the user experience at the exact point where information enters the system, and it makes that information visible later when it matters.

## Living Handoff Rule

From now on, this file should be treated as an execution handoff, not just a one-time spec.

Any agent continuing this V1 must update this document using this order:

1. what is already done
2. what remains in progress or partially validated
3. what should happen next in concrete execution order

This is the rule for continuing the bike workshop initiative in future chat tabs.

## V1 Status Snapshot

### Already accomplished

- `bike_profiles` persistence layer exists in schema and migration form
- `BikeProfile` model exists in Flutter
- bikeshop service supports fetch and upsert for bike profiles
- mechanic job form already renders a bike context summary card
- the mechanic job context card now shows fallback core bike facts even when no full structured profile exists yet
- bike entry has already been transformed from a flat dialog into a step-based wizard
- wizard step order now reflects workshop reality: identity/base first, intake second, technical third, notes/photos last
- conversational intake prompts are in place
- inline catalog lookup is in place in the identity/base step
- bike intake no longer stores job-specific concern data
- the client logbook now opens saved bikes in a dedicated record-mode panel instead of defaulting to the wizard

### Still to accomplish next

- stabilize the current wizard behavior through real workflow testing
- verify quick-save and full-save semantics from real entry points
- verify edit/reopen flows for existing bikes with existing profiles
- harden and explicitly validate the job-side edit/view loop around the bike context card
- clean the remaining bikeshop analyzer warnings so validation noise is reduced
- decide and document the next layer after V1 stabilization: bike history/events

Phase 3 timeline handoff set prepared on 2026-04-09:

- [BIKE_WORKSHOP_PHASE3_TIMELINE_PLAN_2026-04-09.md](BIKE_WORKSHOP_PHASE3_TIMELINE_PLAN_2026-04-09.md)
- [BIKE_WORKSHOP_PHASE3_TIMELINE_SQL_SPEC_2026-04-09.md](BIKE_WORKSHOP_PHASE3_TIMELINE_SQL_SPEC_2026-04-09.md)
- [BIKE_WORKSHOP_PHASE3_TIMELINE_UX_HANDOFF_2026-04-09.md](BIKE_WORKSHOP_PHASE3_TIMELINE_UX_HANDOFF_2026-04-09.md)

## Current V1 Logic Contract

This is the current intended contract of the system and future work must preserve it unless explicitly redesigned:

- bike intake captures stable bike background only
- job diagnosis captures visit-specific concern and work narrative only
- technical profile is suggestible by catalog but confirmable by humans
- wizard UX is the correct direction for bike intake
- quick-save is an intermediate escape hatch, not a replacement for final save
- the summary card in mechanic jobs is the bridge between bike memory and visit-specific work

## V1 Goal

When a bike is registered for the first time, staff should be able to:

- identify the bike quickly
- optionally match it to the encyclopedia
- capture first-time intake context once
- capture a minimal technical baseline once
- save that data in a structured profile

When a mechanic opens a job for that bike, they should be able to:

- immediately see the bike context summary
- keep using the existing narrative job editor for the current visit
- avoid re-asking the full intake questionnaire unless something changed

Status:

- largely achieved in code
- remaining work is validation, cleanup, and workflow hardening before history/events begin

## V1 In Scope

### Product scope

- redesign the bike form into clear sections
- add a one-to-one bike profile layer
- support encyclopedia suggestions in the bike form
- store intake baseline and technical baseline structurally
- show a read-friendly bike summary card in the mechanic job form
- preserve current job narrative fields unchanged

### User scope

- workshop staff creating or editing bikes
- mechanics opening and editing jobs

### Data scope

- first-time intake baseline
- minimal technical baseline
- catalog suggestion reference
- summary-friendly structured data

## V1 Out Of Scope

These should not be built in the first slice:

- full historical timeline UI
- recurring measurement engine
- AI diagnosis or symptom inference
- broad compatibility automation across all categories
- deep normalization of every technical dimension into separate tables
- replacing the current job narrative editor

## Current Repo Anchors

### Existing bike entry surface

- [lib/modules/bikeshop/pages/bike_form_dialog.dart](lib/modules/bikeshop/pages/bike_form_dialog.dart)

Current reality:

- a guided wizard is now in place using step navigation and PageView
- identity, intake, technical baseline, and notes are separated into distinct steps
- catalog lookup is now embedded directly into the identity/base step
- the remaining work is about stabilizing the interaction model and keeping the data boundaries correct

### Existing mechanic job writing surface

- [lib/modules/bikeshop/widgets/smart_job_details_editor.dart](lib/modules/bikeshop/widgets/smart_job_details_editor.dart)

Current reality:

- good current-visit narrative workspace
- should remain the main writing surface for request, diagnosis, work, and notes

### Existing job integration surface

- [lib/modules/bikeshop/pages/mechanic_job_form_page.dart](lib/modules/bikeshop/pages/mechanic_job_form_page.dart)

Current reality:

- already selects bikes and opens the bike form
- already includes a compact bike context summary in the working area
- still needs final UX polishing and edit-loop validation

### Existing encyclopedia data

- [lib/shared/models/bike_catalog_models.dart](lib/shared/models/bike_catalog_models.dart)
- [lib/shared/services/bike_catalog_service.dart](lib/shared/services/bike_catalog_service.dart)

Current reality:

- strong suggestion source for likely technical facts
- exists as a separate demo/search experience
- not connected to the actual intake workflow yet

### Existing bike schema

- [supabase/sql/core_schema.sql](supabase/sql/core_schema.sql)

Current reality:

- `bikes` already stores core identity fields and a few technical fields
- it should not absorb every future intake and technical fact as more raw columns

## V1 Product Design

## 1. Bike Form Restructure

The bike form should behave as a guided wizard workspace, not a flat form.

> **[Gemini 3.1 Pro Update - 2026-04-08]**: We have implemented this as a functional, responsive Guided Wizard (`PageView`). To prevent slowing down the intake process in front of clients, we have added a **Guardar Rápido** feature across the intermediate steps, and reorganized the tab order to group client-facing actions (Identity + Intake) first, followed by technical specs for the mechanic. The last step retains the normal final save action.

### Section A. Identidad (and Inline Catalog Match)

Fields:

- marca
- modelo
- año
- tipo de bicicleta
- talla de cuadro (Implemented via `Autocomplete` with predefined sizes)
- aro (Implemented via `Autocomplete` with predefined sizes)
- color
- número de serie

Behavior:

- keep current quick-add brand and model flows
- use this section to build the encyclopedia search seed
- **[Gemini 3.1 Pro Update]**: The Catalog search has been integrated directly into this tab below the "Año" field. The mechanic can click "Buscar" to instantly pre-fill technical dimensions on the spot without ever navigating to a separate tab.

### Section B. Ingreso inicial (Conversational Intake)

> **[Gemini 3.1 Pro Update]**: This section was moved to Step 2 to closely follow Identidad. The labels have been rewritten as direct conversational questions so mechanical staff know exactly how to guide the dialogue with the client.

V1 fields:

- ¿Fue comprada nueva o usada? (acquisition condition)
- ¿Se le han hecho mantenciones? (declared maintenance history)
- ¿Para qué la usas principalmente? (primary use)
- ¿Con qué frecuencia la usas? (frequency of use)
- ¿Ha tenido choques fuertes? (accident or impact history)
- ¿Dónde se guarda habitualmente? (storage condition)
- ¿Se expone a lluvia o sol? (weather exposure)
- ¿Cómo la transportas usualmente? (transport method)

V1 UX rules:

- mostly choice inputs, not raw text
- one optional detail text area at most for the section
- all fields support `unknown`
- this section should feel fast to complete before the client leaves

### Section C. Línea base técnica

### Section E. Notas y fotos

Keep:

- current bike notes field
- current bike image management

Intent:

- preserve the mechanic's need for freeform human memory
- keep condition photos attached to the bike

## 2. Mechanic Job Context Card

Add a read-only bike context card to the mechanic job form.

Target surface:

- [lib/modules/bikeshop/pages/mechanic_job_form_page.dart](lib/modules/bikeshop/pages/mechanic_job_form_page.dart)

Purpose:

- show bike identity and baseline context without reopening the bike form

V1 card content:

- bike identity summary
- intake summary
- technical summary
- last confirmed date
- quick action: edit bike profile

Example content:

- Uso principal: Gravel / urbano mixto
- Historial declarado: mantención ocasional
- Accidentes: sí
- Frenos: disco hidráulico
- Transmisión: 1x11
- Eje trasero: 142 mm
- Última confirmación: 08/04/2026

This card should sit near the bike selection / bike tab area so it feels like working context, not buried metadata.

## 3. Job Narrative Stays As-Is In V1

The current job writing model should remain intact.

Keep using:

- customer request
- diagnosis
- work performed
- notes

Do not replace that with a new structured diagnosis engine in V1.

The right V1 move is to enrich the mechanic's context, not to disrupt the mechanic's writing flow.

## V1 Data Model

## Guiding rule

Do not overload `bikes` with many speculative columns.

Use a dedicated one-to-one profile table for structured profile data.

## Recommended table: `bike_profiles`

Add a new tenant-scoped one-to-one profile table.

Suggested columns:

- `id uuid primary key default gen_random_uuid()`
- `tenant_id uuid references tenants(id) on delete cascade not null`
- `bike_id uuid references bikes(id) on delete cascade not null`
- `catalog_bike_id uuid references bike_catalog(id) on delete set null`
- `intake_profile jsonb not null default '{}'::jsonb`
- `technical_profile jsonb not null default '{}'::jsonb`
- `summary_snapshot jsonb not null default '{}'::jsonb`
- `last_confirmed_at timestamptz`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`
- `unique(bike_id)`

Why this shape is right for V1:

- keeps core bike identity in `bikes`
- gives structured persistence for intake and technical baseline
- avoids a premature explosion of columns
- supports fast UI reads with `summary_snapshot`
- leaves room to evolve later into more normalized data if proven necessary

## JSON contract for `intake_profile`

Suggested V1 keys:

- `acquisitionCondition`
- `declaredMaintenanceHistory`
- `primaryUse`
- `usageFrequency`
- `accidentHistory`
- `storageCondition`
- `weatherExposure`
- `transportMethod`

## JSON contract for `technical_profile`

Suggested V1 keys:

- `brakeType`
- `frontRotorSizeMm`
- `rearRotorSizeMm`
- `drivetrainSpeeds`
- `drivetrainConfig`
- `frontHubSpacingMm`
- `rearHubSpacingMm`
- `freehubType`
- `spokeCount`
- `wheelSize`
- `bikeType`

For fields that come from suggestion or manual confirmation, support a nested shape when needed, for example:

```json
{
  "brakeType": {
    "value": "hydraulic_disc",
    "source": "catalog",
    "confirmed": false
  }
}
```

If the team wants to keep V1 simpler, it can start with flat values plus a companion provenance map:

```json
{
  "values": {
    "brakeType": "hydraulic_disc"
  },
  "sources": {
    "brakeType": "catalog"
  },
  "confirmed": {
    "brakeType": false
  }
}
```

The second option is easier to implement incrementally in Flutter.

## JSON contract for `summary_snapshot`

Purpose:

- provide a compact, UI-ready summary for job context cards and bike chips

Suggested keys:

- `identityLine`
- `intakeHighlights`
- `technicalHighlights`
- `warnings`
- `lastConfirmedAt`

## V1 Schema Rules

- `bike_profiles` must include `tenant_id`
- add index on `tenant_id`
- add index on `bike_id`
- enable RLS
- create standard CRUD policies scoped to `public.user_tenant_id()`
- update `supabase/sql/core_schema.sql` as source of truth

## Flutter Implementation Targets

## 1. New model layer

Add a bike profile model near the existing bikeshop models.

Likely file target:

- [lib/modules/bikeshop/models/bikeshop_models.dart](lib/modules/bikeshop/models/bikeshop_models.dart)

Recommended additions:

- `BikeProfile`
- intake enums or constants
- technical enum sets where helpful
- summary helpers for rendering chips or compact lines

## 2. Service layer additions

Extend the bikeshop service to support:

- fetch bike profile by bike id
- upsert bike profile
- fetch bike + profile summary for job use
- apply catalog suggestion to draft bike profile

Likely file target:

- [lib/modules/bikeshop/services/bikeshop_service.dart](lib/modules/bikeshop/services/bikeshop_service.dart)

## 3. Bike form refactor

Refactor the current dialog into sectioned blocks.

Primary target:

- [lib/modules/bikeshop/pages/bike_form_dialog.dart](lib/modules/bikeshop/pages/bike_form_dialog.dart)

V1 implementation strategy:

- keep existing dialog shell and actions
- implement the flow as a multi-step wizard with PageView and adaptive step navigation
- add lightweight draft state for profile data
- save core bike and profile together in one workflow

## 4. Encyclopedia hookup

Use the existing catalog service directly in the bike form.

Targets:

- [lib/shared/services/bike_catalog_service.dart](lib/shared/services/bike_catalog_service.dart)
- [lib/modules/bikeshop/pages/bike_form_dialog.dart](lib/modules/bikeshop/pages/bike_form_dialog.dart)

V1 behavior:

- search with brand, model, year
- show top candidate list
- on select, prefill draft technical profile
- user confirms or overrides

## 5. Job form summary card

Target:

- [lib/modules/bikeshop/pages/mechanic_job_form_page.dart](lib/modules/bikeshop/pages/mechanic_job_form_page.dart)

V1 behavior:

- when a bike is selected, load profile summary
- show read-only context card
- provide edit shortcut to reopen bike dialog

## Rollout Order

## Step 1. Schema and model groundwork

- add `bike_profiles` to [supabase/sql/core_schema.sql](supabase/sql/core_schema.sql)
- add RLS and indexes
- add Flutter model(s)
- add service methods

Status:

- completed

## Step 2. Bike form refactor

- restructure existing form into sections
- add intake draft fields
- add technical baseline draft fields
- keep current image and notes behavior

Status:

- completed in implementation
- follow-up work is testing and UX hardening

## Step 3. Encyclopedia suggestion workflow

- add candidate search panel
- add prefill behavior
- add simple provenance handling

Status:

- completed in implementation
- follow-up work is validating real-world matching behavior

## Step 4. Job form context card

- load and render bike profile summary in the job flow
- keep current job narrative editor unchanged

Status:

- completed in implementation
- follow-up work is edit shortcut and synchronization validation

## Step 5. Validation and UX cleanup

- test bike creation from client logbook and mechanic job form
- test bike editing from existing job contexts
- ensure profile save/update remains tenant-safe
- ensure job flow remains fast and non-blocking

Status:

- next active step

## Immediate Next Actions

The next agent should do these in order:

1. test bike creation with full save
2. test bike creation with quick save from intermediate steps
3. test re-opening and editing an existing bike/profile
4. test job form summary card refresh after bike/profile edits
5. patch UX bugs found during those flows
6. only after that, define the bike history/event model for Phase 3

## Acceptance Criteria

V1 is complete when all of these are true:

1. A bike can be created with identity, first-time intake, and technical baseline in one guided flow.
2. Staff can optionally match the bike to an encyclopedia entry and accept or override suggested values.
3. The structured bike profile persists separately from the core bike record.
4. The mechanic job form shows a useful read-only bike context summary.
5. The current narrative diagnosis editor still works exactly as before.
6. The solution introduces real value without forcing mechanics to fill heavy technical forms every time.

## Explicit Non-Goals For V1

To keep this implementation strong, do not add these now:

- timeline builder UI
- measurement trend charts
- full compatibility engine integration for all parts
- auto-generated diagnosis text
- giant universal bike technical schema with dozens of low-value fields

## Recommended Decision

Build this exact V1 before touching broader workshop intelligence.

This gives the project:

- a real bike-centered data entry model
- a real bike-centered context surface in jobs
- a structured home for the one-time intake questions
- a clean bridge between encyclopedia suggestions and workshop reality

That is the right foundation for every later step.