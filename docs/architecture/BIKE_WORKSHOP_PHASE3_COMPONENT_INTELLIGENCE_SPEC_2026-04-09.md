# Bike Workshop Phase 3 Component Intelligence Spec - 2026-04-09

## Handoff Signatures

- Product correction, architecture direction, and scope reset: GPT-5.4
- Implementation target for the next UI / schema iteration: Gemini 3.1 Pro

## Purpose

This document corrects the direction of Phase 3.

The bike should not stop at a generic event feed.

The real target is a component-centered technical memory system.

The mechanic should be able to inspect the bike by system or component and answer questions such as:

- how has chain wear evolved over time
- when was the current chain installed
- when were the front and rear rotors last measured
- whether the front brake and rear brake histories differ materially
- whether a recorded measurement should have reset because a replacement was confirmed

## Problem With The Generic Feed

The current `bike_events` rail can show chronology.

That is useful for macro context, but insufficient for actual workshop intelligence.

Why it is insufficient:

- it mixes bike-level and component-level facts into one flat rail
- it does not model installed-part lifecycle
- it does not model front/rear separation well enough for brakes, wheels, tires, and rotors
- it cannot answer wear-trend questions cleanly
- it cannot automatically reset measurement state when the relevant part is replaced
- it does not match the mechanic's mental model of the bicycle as systems and components

## Correct Product Shape

Phase 3 should have four connected surfaces.

### 1. Bike Macro Timeline

This is the existing high-level chronology.

Keep it for:

- profile changes
- bike-level incidents
- job open / complete
- major component interventions

But treat it as the overview rail, not the main intelligence surface.

### 2. Interactive Bike Systems Surface

The UI should render a simplified clickable bicycle systems map.

First version can be an interactive systems panel if the full SVG bike schema is too much for one pass.

Recommended selectable systems:

- drivetrain
- front brake
- rear brake
- front wheel
- rear wheel
- frame and cockpit
- suspension

Clicking a system should open:

- current known configuration
- installed components
- last known measurements
- trend / history entries
- related jobs and parts changes

### 3. Component Lifecycle Surface

The system should track important installed components as living records.

Examples:

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

Each lifecycle record should support:

- component type
- side / location when relevant
- installed product id or manual component description
- installed_at
- removed_at
- source job_id
- source invoice_line_id or job item id when available
- removal_reason: worn, damaged, upgraded, unknown
- status: installed, removed, superseded

## 4. Measurement Series Surface

This is where the most valuable workshop memory sits.

Recommended first measurements:

- chain wear ratio
- front rotor thickness
- rear rotor thickness
- front pad wear
- rear pad wear
- front tire wear
- rear tire wear
- wheel true / spoke tension status snapshots

Each measurement record should support:

- measurement_type
- system_key
- component_key or lifecycle_id when relevant
- side / location
- value_numeric
- unit
- measured_at
- job_id
- source
- notes

## Core Behavior Rules

### Rule 1. Job-level narrative stays on the job

Do not move diagnosis, customer request, or work narrative into the bike intelligence tables.

### Rule 2. Current state and historical evidence remain separate

- `bike_profiles` remains current baseline
- lifecycle + measurement tables become historical technical evidence

### Rule 3. Component replacement should reset the right measurements

Example:

- if a job confirms a new front rotor was installed, the current front rotor lifecycle closes the old record and creates a new installed record
- the new front rotor history should not inherit the wear progression of the old rotor
- any rotor thickness view should clearly show a reset point because it is now a different installed component

Example:

- if a chain replacement is confirmed, the chain wear progression must reset for the new chain

### Rule 4. Front and rear must be modeled separately where mechanics think separately

At minimum:

- brakes
- rotors
- pads
- tires
- wheels

### Rule 5. Manual entry and derived entry can coexist

Measurements may be entered explicitly.

Lifecycle changes may be derived from confirmed job items or invoice lines.

The system should store the source, not pretend all data was manually measured.

## Proposed Data Model

### Table 1. `bike_component_lifecycles`

Purpose:

- tracks which important component is or was installed on the bike

Suggested fields:

- `id`
- `tenant_id`
- `bike_id`
- `job_id`
- `source_invoice_line_id` nullable
- `component_type` text
- `system_key` text
- `location_key` text nullable
- `product_id` nullable
- `component_label` text
- `installed_at` timestamptz
- `removed_at` timestamptz nullable
- `removal_reason` text nullable
- `status` text not null default 'installed'
- `payload` jsonb default '{}'
- `created_by`
- `created_at`
- `updated_at`

Examples:

- `component_type = 'chain'`
- `system_key = 'drivetrain'`
- `location_key = null`

- `component_type = 'rotor'`
- `system_key = 'brake'`
- `location_key = 'front'`

### Table 2. `bike_measurements`

Purpose:

- records the observed numeric or discrete condition values over time

Suggested fields:

- `id`
- `tenant_id`
- `bike_id`
- `job_id`
- `lifecycle_id` nullable
- `measurement_type` text
- `system_key` text
- `location_key` text nullable
- `value_numeric` numeric nullable
- `value_text` text nullable
- `unit` text nullable
- `measured_at` timestamptz not null default now()
- `source` text not null default 'manual'
- `notes` text nullable
- `created_by`
- `created_at`

Examples:

- `measurement_type = 'chain_wear'`, `value_numeric = 0.75`, `unit = 'ratio'`
- `measurement_type = 'rotor_thickness'`, `location_key = 'front'`, `value_numeric = 1.68`, `unit = 'mm'`

### Table 3. `bike_system_state_views` or read-model RPC

Purpose:

- serves the UI with the current state per system without asking Flutter to reconstruct everything manually

Read-model outputs should include:

- current installed components by system
- last recorded measurements by type and side
- warning thresholds crossed
- recent jobs touching that system

## Integration With Jobs and Invoices

This part is mandatory if the feature is to feel intelligent instead of bureaucratic.

### Replacement detection

When a confirmed job or invoice line represents an installed replacement part:

- close the prior lifecycle record for that component type and side
- create the new lifecycle record
- stamp the source job and invoice line

### Measurement resets

When the replaced part is the measured object, the UI should start a new series for the new lifecycle.

Examples:

- new chain installed -> chain wear series resets
- new front rotor installed -> front rotor thickness series resets
- new rear pads installed -> rear pad wear state resets

### No fake automation

Do not invent measurements automatically.

The reset is structural, not fabricated.

That means:

- we create a new lifecycle
- we do not pretend the new chain was measured at `0.00` unless someone explicitly records that measurement or the business decides to create a deterministic baseline record

## UI Direction

### Tab strategy

The bike profile should not rely on one flat `Historial` tab only.

Recommended tabs:

- `General y Notas`
- `Ficha Técnica`
- `Sistemas`
- `Historial`

Where:

- `Sistemas` is the component intelligence home
- `Historial` remains the bike-level overview rail

### `Sistemas` tab content

Desktop:

- left: interactive bike or systems list
- right: selected system detail pane

Selected system detail pane should show:

- current setup
- latest measurements
- trend / progression list or sparkline
- component replacements
- related jobs

### Example detail states

For drivetrain:

- current chain: KMC X11 installed 12/01/2026
- latest chain wear: 0.50 on 08/03/2026
- prior chain replaced on 12/01/2026 at wear 0.90
- cassette replaced together with chain: no

For front brake:

- current front rotor: Shimano RT66 160mm
- latest rotor thickness: 1.72 mm
- warning if threshold near minimum
- front pads replaced two jobs ago

## Recommended Implementation Order

### Phase 3 Reset A. Keep the current event rail as scaffolding only

- do not throw it away immediately
- stop treating it as the end-state

### Phase 3 Reset B. Define the component lifecycle schema

- add `bike_component_lifecycles`
- add RLS and tenant-safe indexes
- add read/write service layer

### Phase 3 Reset C. Define the measurement schema

- add `bike_measurements`
- start with chain wear and rotor thickness front/rear

### Phase 3 Reset D. Build the `Sistemas` surface

- render selectable systems
- show current state + measurements + history per system

### Phase 3 Reset E. Add replacement linkage from jobs / invoices

- connect confirmed parts replacement to lifecycle rollover
- connect replacement lifecycle creation to measurement reset behavior

## Definition Of Done

Phase 3 is only truly complete when:

1. the bike profile can be inspected by system or component
2. chain wear and rotor wear can be tracked as real historical series
3. front and rear component histories are separated where needed
4. confirmed replacement work closes old lifecycle records and starts new ones
5. the macro bike timeline still exists, but no longer carries the full intelligence burden alone

## Final Recommendation

Treat the current generic timeline as the first 15 percent of the feature, not the feature itself.

The real product is not “a history tab.”

The real product is a workshop memory model where the bike can be understood by system, by component, and by wear progression over time.