# Bike Workshop Intelligence Plan - 2026-04-08

## Handoff Signatures

- Planning updates and Phase A record-mode groundwork notes added in this handoff cycle: GPT-5.4
- The agent implementing the dedicated client-logbook record-mode UI from this handoff should sign as: Gemini 3.1 Pro
- Client-logbook record-mode UI, bike data rendering, and job-context summary hardening: GitHub Copilot (GPT-5.4)

## Purpose

This document defines the product and architecture plan for turning the workshop flow into a connected, bike-centered technical memory system.

The goal is not to create an AI mechanic and not to bury the team under rigid forms. The goal is to make the ERP remember the right things, surface them at the right moment, and keep the mechanic in control of the conclusion.

This plan is based on the current repo reality:

- the bike form has now been reworked into a guided wizard, but the deeper product model still needs to stay disciplined
- mechanic jobs already have a dedicated narrative workspace for customer request, diagnosis, work performed, and notes
- the product technical specs engine already exists as a structured data island
- the service wizard already exists as another structured data island
- wheel building already contains a specialized compatibility engine
- the bike encyclopedia already exists, but it is not yet part of the real workshop intake flow

The problem is not lack of data. The problem is that the data is fragmented into separate smart islands with no unified bike-centered workflow.

## Central System Principle

This initiative must be treated as one centralized bike memory system.

That is the foundation.

Everything else is a surface or a workflow around that center.

The center is not:

- a standalone wizard
- a standalone job form
- a standalone event feed
- a standalone component tracker

The center is the bike as a technical memory anchor.

That center must be connected to the same business objects already used in jobs and invoices.

That means:

- the specific bike being serviced in a job
- the part/service lines attached to that bike in the job
- the real catalog product used as the installed component
- the real service product used as the performed workflow
- the same technical concepts used by product ficha tecnica and the bike encyclopedia

That central memory must connect:

- universal bike facts
- current system status
- current installed components
- historical observations and measurements
- interventions and replacements
- visit-specific diagnosis and work narrative

If the bike-memory model ignores job items, product IDs, service product IDs, or the shared technical concepts behind the encyclopedia/product ficha tecnica, it is drifting back into the same fragmentation problem.

If any future implementation only solves one of those in isolation, it is incomplete by definition.

## Simplicity Contract

The centralized model must stay simple enough for workshop reality.

That means:

- do not model every possible component from day one
- do not force mechanics to fill giant structured forms every visit
- do not require perfect completeness before the system becomes useful
- do not split the model into so many tables and concepts that no one knows where truth lives

But simplicity does NOT mean reducing the system to a generic event rail.

The right simplicity is:

- a small number of important systems
- a small number of important tracked component slots
- a small number of important repeated measurements
- one clear separation between bike memory and visit-specific narrative

## Central Bike Memory Kernel

The simplest correct model is a unified kernel with five connected layers.

Critical rule:

This kernel must not invent a second disconnected component universe.

Tracked parts should prefer the same `products` that the shop already stocks, installs, and invoices.

Tracked workflows should prefer the same service products that the shop already bills through jobs/invoices.

### 1. Bike Core Identity

This remains the durable `bikes` record.

It answers:

- what bike is this
- whose bike is it
- what are the stable identity facts

### 2. Bike Current Baseline

This remains `bike_profiles`.

It answers the current known truth about:

- background context
- technical baseline
- current recap for quick UI reading

This is the summary layer, not the historical layer.

### 3. Bike Systems State

This is the missing central layer that should organize the workshop's technical reasoning.

The bike should be understandable by a small set of systems first:

- drivetrain
- front brake
- rear brake
- front wheel
- rear wheel
- frame / cockpit
- suspension

For each system, the central model should be able to answer:

- what is the current known state
- what is unknown
- what is warning-level or urgent
- when it was last reviewed
- what the most relevant recent interventions were

### 4. Bike Component Slots

The system should know the important currently installed parts without trying to catalog the entire bicycle at once.

Recommended first tracked slots:

- chain
- cassette
- chainring
- front rotor
- rear rotor
- front pads
- rear pads
- front tire
- rear tire
- derailleur hanger

This is the minimum useful layer for lifecycle and reset behavior.

When possible, those tracked slots must point to real catalog products.

Examples:

- chain slot -> real chain `product_id`
- front rotor slot -> real rotor `product_id`
- rear rotor slot -> real rotor `product_id`
- brake pad slots -> real pad `product_id`

Manual text-only fallback is acceptable only when the part is not yet represented in the product catalog.

### 5. Bike Observations And Interventions

This is the historical evidence layer.

It should capture:

- measurements
- diagnoses or condition assessments linked to a system
- interventions and replacements
- incidents and follow-up outcomes
- profile confirmations and meaningful state changes

This is where chronology comes from, but chronology is an output of the kernel, not the kernel itself.

Observations and interventions should be able to point back to the actual operational rows that produced them:

- the job
- the specific serviced bike inside the job
- the job item
- the real product or service product used on that row

## Living Handoff Rule

From this point forward, this document is not just a vision note. It is a living handoff document.

Any agent continuing this initiative should follow this rule:

1. mark clearly what has already been completed
2. mark clearly what is currently true in the product and codebase
3. write down the next concrete steps before starting new work
4. update this file again after meaningful progress so a new chat tab or a new agent can continue without reverse-engineering the state

If implementation and planning ever diverge, update this document so it reflects the real system logic.

## Current Implemented State

The following is already accomplished in the repo as of 2026-04-08:

- a dedicated `bike_profiles` layer exists for structured bike intake and technical baseline persistence
- the source of truth schema has been updated in `supabase/sql/core_schema.sql`
- a deployable migration exists at `supabase/migrations/20260408184500_add_bike_profiles.sql`
- the Flutter domain model includes `BikeProfile`
- the bikeshop service already supports bike profile fetch and upsert
- the bike form has been converted into a guided wizard with step navigation
- the intake section is conversational and client-facing
- the catalog lookup is embedded into the identity/base step
- the bike form no longer stores job-specific concern data as part of bike intake
- the mechanic job form already loads and displays a bike context summary card
- Phase A groundwork for client-logbook record mode now exists:
	- explicit bike pane mode separation (`none`, `record`, `creating`, `editing`)
	- shared `BikeRecordSnapshot` read model
	- shared summary builder extracted out of the wizard page
	- `BikeshopService.getBikeRecordSnapshot(...)` read path
	- dedicated `BikeRecordPanel` now renders the saved-bike view in the client logbook
	- job-side bike context card now falls back to core bike facts even before a full structured profile exists

What is still NOT done:

- V1 still needs end-to-end validation of create, quick-save, edit, and refresh loops
- the mechanic-job bike context card refresh behavior still needs explicit workflow validation after edits
- the history / event model is still not defined

## Critical Correction - 2026-04-09

The first `bike_events` + `Historial` implementation produced a generic chronological feed.

That is acceptable only as temporary scaffolding for transport-level history.

It is NOT the real Phase 3 target.

The actual product target is a component-centered technical memory surface where the mechanic can answer questions like:

- what happened to the drivetrain over time
- what chain wear values have been recorded and how they evolved toward replacement threshold
- what the front and rear brake system history looks like independently
- when a rotor, chain, cassette, pad set, tire, or hanger was replaced
- which measurements should automatically reset because a replacement job/invoice confirmed a new installed part

In other words:

- a generic event feed is not enough
- a bike-level historical rail is only one secondary surface
- the primary intelligence surface should become a clickable bicycle systems map plus per-component lifecycle and measurement history

Phase 3 handoff set created on 2026-04-09:

- [BIKE_WORKSHOP_PHASE3_TIMELINE_PLAN_2026-04-09.md](BIKE_WORKSHOP_PHASE3_TIMELINE_PLAN_2026-04-09.md)
- [BIKE_WORKSHOP_PHASE3_TIMELINE_SQL_SPEC_2026-04-09.md](BIKE_WORKSHOP_PHASE3_TIMELINE_SQL_SPEC_2026-04-09.md)
- [Bike Workshop Phase 3 timeline UX handoff](../archive/2026-04/BIKE_WORKSHOP_PHASE3_TIMELINE_UX_HANDOFF_2026-04-09.md)

Corrective component-intelligence handoff set created on 2026-04-09:

- [BIKE_WORKSHOP_PHASE3_COMPONENT_INTELLIGENCE_SPEC_2026-04-09.md](BIKE_WORKSHOP_PHASE3_COMPONENT_INTELLIGENCE_SPEC_2026-04-09.md)

## Current Logic That Must Be Preserved

This is the active logic of the system and should be treated as the current contract unless deliberately changed:

- bike identity lives on the core `bikes` record
- stable background context lives on `bike_profiles.intake_profile`
- technical baseline lives on `bike_profiles.technical_profile`
- compact UI-ready recap lives on `bike_profiles.summary_snapshot`
- job-specific concern, diagnosis, work performed, and visit narrative stay on the mechanic job side
- encyclopedia/catalog data is a suggestion layer, not authoritative truth
- the bike form is now a wizard, not a flat CRUD dialog
- the wizard prioritizes client-facing intake before mechanic-only technical detail
- the final save action remains the canonical full-save path, while quick-save exists to let staff exit early during intermediate steps
- job diagnosis remains critically important and stays on the mechanic job side as visit-specific narrative
- bike profile work must move around a centralized bike memory model, not around isolated UI surfaces

## Completed Work

### Data and persistence

- added `bike_profiles` table, indexes, trigger, and RLS policies
- added one-to-one bike profile persistence shape tied to `bike_id`
- added deployable migration file for the profile layer

### Flutter domain and service layer

- added `BikeProfile` model and summary helpers
- added `getBikeProfile(...)` and `upsertBikeProfile(...)` to the bikeshop service

### Bike form

- converted the bike form into a guided wizard
- reordered the flow to support real workshop intake
- integrated catalog search inside the identity/base step
- rewrote intake prompts as conversational client-facing questions
- removed the incorrect bike-level `mainConcern` idea from the actual bike intake flow

### Mechanic job flow

- added a bike context summary card to the mechanic job form
- preserved the current narrative job workspace instead of replacing it

## What Is Next

The next work should build on the current model instead of redefining it.

Priority order:

1. stabilize the wizard UX
2. validate the full bike create/edit flow end-to-end
3. tighten the bike context card and bike/profile editing loop from the job flow
4. lock the central bike memory kernel before more UI drift happens
5. begin the history/timeline layer only as one output of that kernel after the intake/profile flow is stable

Concrete next tasks:

- smoke test bike creation, quick-save, and full-save from real workshop entry points
- verify editing an existing bike preserves and rehydrates intake + technical profile correctly
- ensure the job form summary card stays synchronized after editing a bike/profile
- remove or resolve the remaining bikeshop analyzer warnings that are now just cleanup noise
- add the explicit edit shortcut from the job-side bike context card if not already present
- resolve remaining non-blocking analyzer/lint cleanup in the bike form when convenient
- define the central system/state/component/observation model explicitly before more Phase 3 UI work
- after the active V1 validation loop is intentionally closed, DO NOT stop at a generic bike event feed
- use the corrective component-intelligence handoff as the actual Phase 3 target
- treat the simple `bike_events` rail as fallback scaffolding only, not the destination product

Central-model reset handoff created on 2026-04-09:

- [BIKE_WORKSHOP_CENTRAL_MEMORY_MODEL_2026-04-09.md](BIKE_WORKSHOP_CENTRAL_MEMORY_MODEL_2026-04-09.md)

## North Star

The bike becomes the long-lived technical anchor.

Every workshop interaction should answer one of these questions clearly:

1. What is this bike?
2. What do we know about its background?
3. What do we know technically, and how sure are we?
4. What happened on this visit?
5. What changed over time?
6. Which parts and services are compatible based on hard facts, not guesses?

The ERP should structure evidence and history. The mechanic should still diagnose.

## Core Decisions

### 1. First-time intake belongs to the bike, not to each job

Questions like these are bike-level background context:

- was the bike bought new or used
- does the owner know its maintenance history
- what type of use is common
- has it suffered crashes, impacts, or transport damage
- where and how is it stored
- how exposed is it to rain, mud, salt, or long inactivity

These answers should be captured when the bike first enters the registry and then remain easily accessible in future jobs.

They should not be re-asked every time a mechanic opens a new service order.

### 2. Job diagnosis remains visit-specific

The current mechanic job narrative fields still have an important role:

- customer request
- diagnosis
- work performed
- notes

Those fields are about this visit, not the bike's lifelong background.

They should remain, but they should be supported by a visible bike context summary so the mechanic can write with context instead of starting from zero.

### 3. The ERP stores evidence, not mechanical conclusions

The system can help with structure, recall, suggestions, and compatibility filtering.

The system should not say things like:

- probably the cassette is worn
- likely the hub is damaged
- this symptom means the rear derailleur is bent

The system can say:

- last known chain wear was 0.75
- rear derailleur hanger was replaced three months ago
- bike is confirmed as 11-speed HG with 142 rear spacing
- declared crash history exists

That is useful and safe.

### 4. Encyclopedia data is a suggestion layer, not truth

The bike catalog can accelerate intake by pre-filling probable specs such as:

- bike type
- wheel size
- frame material
- drivetrain speeds
- brake type
- rotor size
- hub spacing
- spoke count

But those values must be treated as suggested until confirmed.

The system should distinguish provenance such as:

- catalog suggested
- mechanic confirmed
- customer reported
- unknown

### 5. Progressive disclosure is mandatory

The most important UX constraint is simplicity.

The mechanic should not face a giant technical questionnaire on every bike.

The right pattern is:

- ask a small set of high-value questions first
- prefill what can be reasonably inferred
- keep advanced details collapsible
- store the answers in a structured way
- always preserve one large comfortable narrative field for human writing

## The Target Product Model

The future model should have five connected layers.

### Layer 1. Bike Core Record

This is the durable identity of the bike.

It includes:

- customer ownership link
- brand and model
- year
- serial number
- color
- frame size
- wheel size
- bike type
- core images
- quick operational notes

This is what the existing bike record already partially does today.

### Layer 2. Bike Intake Baseline

This is the first-time contextual snapshot taken when the bike enters the registry.

It should answer the background questions that mechanics want to know later, without forcing them to re-ask everything every visit.

Recommended fields for the first version:

- acquisition condition: new, used, rebuilt, unknown
- declared maintenance history: regular, occasional, poor, unknown
- primary use: urban, commute, sport, trail, downhill, gravel, delivery, mixed, unknown
- frequency of use: daily, weekly, occasional, inactive, unknown
- accident or impact history: yes, no, unknown
- storage condition: indoor, covered outdoor, outdoor, unknown
- weather exposure: low, medium, high, unknown
- transport method: none, car rack, truck, public transport, mixed, unknown
- date last confirmed

This is not the same as the active job diagnosis. It is the bike's background context.

### Layer 3. Bike Technical Baseline

This is the bike's structured technical identity.

It includes objective facts that matter for compatibility and later service work.

Examples:

- drivetrain speed family
- drivetrain configuration if known
- brake type
- front and rear rotor size
- axle type
- front and rear hub spacing
- freehub type
- spoke count
- tire and wheel standard
- frame material
- cockpit type where relevant

Important rule:

Only store technical facts that are either:

- operationally useful for compatibility and workflow
- stable enough to be worth remembering
- realistic for the workshop to know or confirm

Do not build a museum catalog for its own sake.

### Layer 4. Job Diagnosis Workspace

This remains the mechanic's current-visit workspace.

It should continue to support:

- customer request
- diagnosis
- work performed
- technician notes

But this workspace should gain context around it, not be replaced.

The mechanic should see the bike's intake and technical summary next to or above the narrative editor so they know what they are working with.

Important clarification:

The job diagnosis workspace is not a side note.

It is the canonical place for visit-specific reasoning.

The centralized bike memory model exists to support that reasoning with context, current status, prior interventions, and recurring observations.

The system should never force mechanics to choose between:

- structured bike memory
- useful narrative diagnosis

Both must coexist cleanly.

### Layer 5. Bike History Timeline

This is where the system starts to feel intelligent.

The bike should accumulate a readable chronology of:

- jobs
- relevant measurements
- confirmed spec updates
- replaced components
- notable incidents or owner-reported changes
- follow-up outcomes

This turns the bike into a real long-term technical memory instead of a static customer asset.

Important correction:

This layer should not be interpreted as a single flat list of generic events.

The stronger product shape is:

- bike-level chronology for macro context
- system-level history for real workshop reasoning
- component lifecycle records for installed / removed / replaced parts
- measurement series for wear and serviceability values over time

Examples:

- drivetrain timeline with chain wear progression and cassette/chain replacements
- brake timeline separated into front and rear sides with rotor thickness and pad wear history
- wheel timeline with spoke, true, rim, and hub-related interventions
- suspension timeline with service intervals and seal / oil service records

## What Belongs Where

| Concern | Belongs To | Why |
|---|---|---|
| Brand, model, year, serial, color | Bike core record | Identity and lookup |
| Wheel size, axle type, brake type, hub spacing | Bike technical baseline | Compatibility and workshop decisions |
| New vs used, maintenance history, storage, use type | Bike intake baseline | Long-lived context, asked mainly once |
| Customer request on this visit | Job diagnosis workspace | Current visit only |
| Mechanic diagnosis on this visit | Job diagnosis workspace | Current visit only |
| Work performed on this visit | Job diagnosis workspace | Current visit only |
| Chain wear measured today | Bike history timeline | Time-based technical evidence |
| Crash reported after intake | Bike history timeline and intake baseline update | It changes the known context |

## UX Plan

## 1. Replace the flat bike form with a guided intake wizard

The current bike form should operate as a guided intake wizard, not a flat CRUD dialog.

> **[Gemini 3.1 Pro Update - 2026-04-08]**: The flat dialog has been successfully rewritten into a multi-step Guided Wizard (using `PageView` and adaptive Navigation Rails). To accommodate the reality of a busy workshop, the step order has been strategically re-organized to prioritize client-facing questions first, ensuring the client isn't awkwardly waiting while the mechanic fills out technical specs.
>
> A **"Guardar Rápido" (Quick Save)** action is now available throughout the intermediate wizard steps, allowing the mechanic to immediately break off from the form once the core base fields are met, saving the rest for later. The final step keeps the standard confirm/save action.

Implemented section order:

1. **Identidad y Base** (Customer + bike identity + inline Catalog match)
2. **Ingreso** (First-time intake via conversational questions)
3. **Ficha Técnica** (Technical baseline)
4. **Notas y fotos**

### Section 1. Customer + bike identity (with inline Catalog match)

Fast essentials:

- marca
- modelo
- año
- tipo de bicicleta
- talla de cuadro (Implemented via Smart Autocomplete)
- aro (Implemented via Smart Autocomplete)
- serial number
- color

> **[Gemini 3.1 Pro Update]**: Instead of dedicating an entire wizard step to the Catalog, the Catalog search has been tightly integrated as an **Inline Smart Tool** directly beneath the Marca, Modelo, and Año inputs. Once a match is made, a success card appears and automatically prefills the rest of the Identity and Technical forms without forcing the user to switch tabs.

### Section 3. Technical baseline

Show a small set of high-value technical facts first.

Recommended first-pass fields:

- wheel size
- brake type
- front rotor size
- rear rotor size
- drivetrain speeds
- front hub spacing
- rear hub spacing
- freehub type
- spoke count

Advanced technical details should remain collapsible.

### Section 2. First-time intake (Ingreso)

> **[Gemini 3.1 Pro Update]**: Placed immediately after "Identidad", this section represents the brief interview with the client at drop-off. The UI labels have been explicitly converted from technical nouns into conversational questions to intuitively guide the mechanic's dialogue.

V1 conversational fields:

- ¿Fue comprada nueva o usada?
- ¿Se le han hecho mantenciones?
- ¿Para qué la usas principalmente?
- ¿Con qué frecuencia la usas?
- ¿Ha tenido choques fuertes?
- ¿Dónde se guarda habitualmente?
- ¿Se expone a lluvia o sol?
- ¿Cómo la transportas usualmente?

The mechanic should be able to complete this section quickly before the client leaves. The system supports partial completion (Unknown).

### Section 5. Notes and photos

This section should include:

- one large narrative notes field for the bike itself
- damage or condition photos
- optional shop-only comments

This is where the human memory remains comfortable.

## 2. Add a bike context summary everywhere the bike is used

When a mechanic opens a job, they should immediately see a compact bike summary card.

The summary should include:

- bike identity
- intake context
- top technical facts
- last confirmed date
- open warnings or unknowns

Example summary content:

- Uso principal: urbano diario
- Historial declarado: mantenciones esporádicas
- Accidentes declarados: sí
- Frenos: disco hidráulico
- Transmisión: 1x11 confirmada
- Eje trasero: 148 Boost confirmado
- Última confirmación: enero 2026

This is the bridge between the bike record and the current job.

## 3. Keep one rich narrative job workspace

Mechanics still need a comfortable place to think and write.

The existing job narrative editor should remain the main human workspace for the current visit.

What changes is the surrounding context:

- visible bike summary
- quick access to history
- visible prior interventions
- optional structured observation shortcuts

That preserves usability.

## 4. Make updates lightweight on later visits

The first-time intake should not become a recurring burden.

On future visits, the system should behave like this:

- show the current bike summary
- ask whether any background info changed
- allow quick updates to intake and technical baseline
- log those updates in the bike history

This keeps the bike record alive without re-running intake every time.

## Data Model Plan

The implementation should avoid turning the `bikes` table into a dumping ground of dozens of speculative columns.

The right shape is a hybrid model.

That hybrid model must remain connected to the catalog and job-item backbone.

This is mandatory:

- `mechanic_job_items.job_bike_id` is the link from a row to the specific serviced bike in the job
- `mechanic_job_items.product_id` is the link to a real installed catalog product when a part was used
- `mechanic_job_items.service_product_id` is the link to a real service product when a service workflow was used
- the bike encyclopedia and product ficha tecnica should follow the same technical-family/template concepts so suggested bike facts, tracked installed parts, and compatibility logic speak the same language

Do NOT create:

- a disconnected bike-only part identity layer that ignores `products`
- a disconnected bike-only service action system that ignores service products
- a bike encyclopedia schema that uses different core concepts from the product tech-spec engine

The hybrid model should be understood as one centralized memory model, not a random collection of separate features.

### Keep `bikes` for identity and quick operational fields

The existing bike record should remain responsible for core identity and a few high-value quick filters.

That includes things like:

- ownership
- brand and model
- year
- serial number
- core bike type fields already in use
- currently useful workshop dimensions already present

### Add a dedicated bike profile layer

Recommended new profile concept:

- one bike profile per bike
- stores intake baseline
- stores technical snapshot
- stores provenance and confidence
- stores catalog match reference if one exists
- stores last confirmed metadata

Recommended structure for the first implementation:

- a relational parent table for one-to-one bike profile metadata
- structured JSON sections for intake and technical snapshot
- provenance markers inside the structured payload

This avoids schema explosion while still supporting structured behavior.

### Add a bike systems state layer

This is the coordination layer that prevents the whole feature from fragmenting.

It should not try to replace all historical records.

It should answer current-state questions like:

- drivetrain overall status
- front brake overall status
- rear brake overall status
- front wheel overall status
- rear wheel overall status

Each system state should be allowed to be simple:

- `ok`
- `attention`
- `critical`
- `unknown`

with optional structured notes, last-reviewed date, and links to the latest observations that justify that state.

This gives mechanics a simple current-status layer without making them parse raw timelines to know what matters now.

### Add a history/events layer

The system also needs a bike history/event log.

This layer should capture:

- intake created
- intake updated
- technical baseline confirmed
- measurement recorded
- notable part replaced
- customer-reported incident added
- job closed

This is what will make the bike timeline valuable.

But that event log should become only one layer of the broader intelligence model, not the entire UI contract.

It should support the richer surfaces below instead of replacing them.

### Add a component lifecycle layer

The system should know what important component is currently installed on the bike and when that became true.

Examples:

- current chain
- current cassette
- current front rotor
- current rear rotor
- current brake pads front/rear
- current tires front/rear
- derailleur hanger

Each lifecycle record should support:

- installed date
- source job / invoice / manual confirmation
- removed / replaced date
- removed because worn / damaged / upgrade / unknown
- links to the product or service line when available

This should start with the smallest slot list that unlocks real value, not with every part on the bike.

### Add a measurement-series layer

This is where the useful workshop intelligence actually lives.

High-value first measurements:

- chain wear (0.00 to 1.00)
- rotor thickness front
- rotor thickness rear
- brake pad wear front
- brake pad wear rear
- tire wear front
- tire wear rear
- wheel true / spoke condition snapshots

Each measurement should support:

- measured value
- unit
- side / location
- component linkage when relevant
- confidence / source
- job linkage
- measured_at

Measurements should be linked to systems and, when possible, to the current lifecycle of the measured component.

That is what allows measurement history to reset correctly when a component is replaced.

### Interactive bicycle schema / systems surface

The bike UI should eventually expose a clickable bicycle diagram or systems map.

Selecting a system or component should open the relevant history, current installed part, and measurement trend.

Recommended first systems:

- drivetrain
- front brake
- rear brake
- front wheel
- rear wheel
- frame / cockpit
- suspension

This is much closer to the actual workshop mental model than a single undifferentiated feed.

The first version does not need a perfect full bicycle illustration.

A systems-first panel is acceptable if it preserves the same mental model and keeps implementation realistic.

### Add structured observations only when they become truly operational

Do not create twenty measurement tables up front.

Start with a narrow pattern for high-value technical observations that genuinely matter over time, such as:

- chain wear
- rotor thickness
- brake pad condition
- tire condition
- spoke tension or wheel status when relevant

Only formalize more of these once the first flow is working and used.

## Compatibility Strategy

Compatibility should be evidence-based.

The system should use hard facts from the bike technical baseline to help filter parts and services.

Examples:

- chain options filtered by confirmed chain speed family
- cassette options filtered by confirmed freehub type and speed family
- rotor suggestions filtered by confirmed brake standard and rotor size
- wheel and hub suggestions filtered by spacing, axle, and spoke count

What the system should not do:

- infer a failure cause from symptoms
- treat weak catalog suggestions as confirmed fitment
- hide alternatives just because the data is incomplete

The safe rule is:

- confirmed facts narrow the list
- suggested facts can help rank the list
- unknown facts keep the list broader

## Phased Rollout

## Phase 1. UX restructure without heavy intelligence

Goal:

Make the bike form and mechanic job flow feel connected before adding deeper modeling.

Deliverables:

- redesign the bike form into sections
- add the first-time intake section
- add catalog match suggestion UI
- add bike summary card inside the job flow
- keep current job narrative editor intact

Status:

- completed in principle
- remaining work is stabilization and validation, not redesign from scratch

Success condition:

Mechanics can register a bike once, answer the background questions once, and see that context later while working.

## Phase 2. Persistent bike profile layer

Goal:

Give the system a real place to store structured intake and technical baseline data.

Deliverables:

- introduce bike profile persistence
- store intake answers structurally
- store technical baseline structurally
- store provenance and last-confirmed metadata
- persist encyclopedia match when used

Status:

- completed in principle
- remaining work is production validation and refinement of the UX around it

Success condition:

The system stops depending on scattered free text for bike background and core facts.

## Phase 3. History and evidence timeline

Goal:

Make the bike record cumulative and time-aware.

But do it around the central bike memory kernel, not around a standalone timeline abstraction.

Deliverables:

- history/event log for bike changes
- bike-level chronology UI on bike profile and job context
- component lifecycle tracking for important installed parts
- measurement-series tracking for wear and serviceability values
- interactive bike systems surface for drilling into component evolution
- structured logging of important technical updates
- ability to see what changed and when
- automatic reset / rollover logic when replacements are confirmed by jobs or invoice lines

Success condition:

The bike becomes a real long-term technical memory, not a static master record or a generic audit feed.

Status:

- partially scaffolded in the wrong abstraction
- the current `bike_events` rail is not sufficient as the final Phase 3 deliverable
- next work must redirect toward component intelligence instead of extending the generic feed endlessly

## Phase 4. Compatibility-powered workflow

Goal:

Use confirmed bike facts to improve part and service selection without acting like an AI mechanic.

Deliverables:

- evidence-based compatibility filtering
- ranked suggestions based on confirmed versus suggested facts
- better service profile routing using the bike baseline
- better parts suggestion inside jobs and invoices

Success condition:

Mechanics spend less time manually filtering obvious incompatible options.

Status:

- not started
- blocked on having stable confirmed technical baseline data and later history evidence

## Phase 5. Deeper structured observations

Goal:

Introduce recurring measurements and technical observations only after the core flow is working.

Deliverables:

- high-value measurement patterns
- history of recurring measurements over time
- lightweight recording UX in jobs

Success condition:

Measurements become useful evidence in the bike history instead of isolated notes.

Status:

- not started
- should wait until bike history/timeline design is defined

## Anti-Goals

This plan explicitly rejects these wrong directions.

### 1. One giant diagnosis field for everything

That would feel simple at first, but it destroys structure, searchability, compatibility filtering, and timeline value.

### 2. A giant mandatory technical form on every bike

That would create resistance and bad data.

The system must support partial truth, unknown values, and progressive confirmation.

### 3. AI-style automatic diagnosis

This is not the role of the ERP and would be risky.

### 4. Silent catalog truth

Catalog data must not overwrite reality without confirmation.

### 5. Adding dozens of columns without proven operational value

The system should add structure carefully and only for fields that improve workflow.

## Recommended First Implementation Slice

The best first slice is not the deepest schema work. It is the smallest change that makes the workshop feel smarter immediately.

Recommended first slice:

1. redesign bike form into sections
2. add first-time intake section
3. connect the encyclopedia as a suggestion layer
4. show bike summary card in mechanic job flow
5. keep current diagnosis editor as the current-visit writing surface

Why this slice first:

- immediate UX improvement
- visible mechanic value
- low conceptual risk
- creates the right product shape before deeper data modeling

## Definition of Done

This initiative should be considered successful when these statements are true:

1. A new bike can be registered with guided intake instead of raw CRUD.
2. The first-time background questions are captured once and remain easy to review later.
3. The mechanic can see bike context inside a job without opening multiple screens.
4. Technical facts are stored with clear provenance.
5. The bike accumulates meaningful history over time.
6. Compatibility assistance is based on confirmed evidence, not fuzzy guesses.
7. The workflow still feels lighter, not heavier, for real workshop staff.

## Final Recommendation

Treat this initiative as a workshop operating system built around the bike, not as a form redesign.

The bike is the anchor.
The first-time intake is the background memory.
The technical baseline is the compatibility memory.
The job editor is the current-visit workspace.
The timeline is the long-term intelligence.

If implementation stays faithful to those roles, the system will become meaningfully smarter without becoming annoying or fake.
