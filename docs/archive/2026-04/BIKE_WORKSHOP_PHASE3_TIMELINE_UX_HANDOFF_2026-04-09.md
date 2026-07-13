# Bike Workshop Phase 3 Timeline UX Handoff - 2026-04-09

## Correction Notice - 2026-04-09

This handoff describes the overview chronology surface only.

It should not be treated as the full UX target for workshop intelligence.

The stronger target is a `Sistemas`-style surface with clickable bicycle systems, current installed parts, and measurement evolution per system.

Use this handoff together with [BIKE_WORKSHOP_PHASE3_COMPONENT_INTELLIGENCE_SPEC_2026-04-09.md](BIKE_WORKSHOP_PHASE3_COMPONENT_INTELLIGENCE_SPEC_2026-04-09.md).

## Handoff Signatures

- Product UX direction, surface ownership, and non-visual interaction rules: GPT-5.4
- Timeline UI implementation handoff target: Gemini 3.1 Pro

## Purpose

This document hands off the bike timeline UI implementation.

The bike timeline is the new historical layer of the bike profile.
It should make the bike feel cumulative, workshop-specific, and evidence-based.

This is not a social feed.
This is not a generic activity log.
This is the bike's long-term workshop memory.

## Canonical Owner Surface

The bike timeline belongs on the bike profile / bike record surface.

Primary owner surface:

- `BikeRecordPanel` in the client logbook

This means:

- the bike profile is where the full timeline is read
- the job form may later show compact references or recent history
- the bike profile is the canonical timeline home

## Structural Recommendation

The current bike record UI already has a tabbed layout.

Recommended evolution:

- `General y Notas`
- `Ficha Técnica`
- `Historial`

The new `Historial` tab should become the bike timeline surface.

This is preferable to burying history at the bottom of an existing tab, because the timeline is a first-class product layer, not a leftover notes section.

## UX Goal

When a mechanic opens a saved bike, they should quickly understand:

1. what the bike is now
2. what is known about it
3. what has happened to it over time

The timeline must help answer the third question without overwhelming the first two.

## Desired Feel

The visual language should feel:

- calm
- chronological
- trustworthy
- workshop-professional

Avoid:

- chat-like bubbles
- social-media card stacks
- oversized color blocks
- decorative timeline gimmicks

This is an ERP/workshop record, not a lifestyle app.

## Event Row Structure

Each timeline row should show:

- event date
- event title
- compact summary
- optional reference chip such as job number
- optional event icon
- optional severity styling only when genuinely relevant

Good examples:

- `09/04/2026` `Perfil actualizado` `Se confirmó freno hidráulico y rotor delantero 160 mm`
- `08/04/2026` `Trabajo completado` `Cambio de transmisión y ajuste general` `PEGA-00421`
- `07/04/2026` `Incidente reportado` `Cliente reporta choque lateral leve`

## Information Hierarchy

### Strongest signal

- title
- date

### Secondary signal

- summary
- job reference

### Weakest signal

- source
- metadata details

Do not let metadata overpower the event itself.

## Suggested Visual Pattern

Recommended layout:

- left timeline rail or subtle vertical guide
- compact circular markers / icons
- right content area with title and summary
- chips for reference and category if useful

This should be restrained and dense enough for real use.

## States To Design

The UI agent should implement all of these explicitly.

### 1. Empty State

When no bike events exist yet:

- show that this bike has no history recorded yet
- explain that future jobs, profile updates, and evidence events will appear here
- do not make the empty state feel broken

### 2. Loading State

- skeleton rows or compact loader
- avoid blocking the whole bike profile with a giant spinner if the other tabs are already usable

### 3. Normal Chronology State

- descending chronology by business date
- recent events first

### 4. Mixed Event Types

- rows should remain visually coherent even when event types differ
- do not create totally different layouts for each event type in V1

### 5. Long History State

- support scroll
- consider lazy rendering if needed later
- no need for grouping by year/month in V1 unless the data volume already demands it

## V1 Event Types To Visualize

The first UI version should visually support:

- bike registration
- profile creation and updates
- job creation and completion
- incident reported
- component replaced
- measurement recorded

The row UI should tolerate event payload differences without becoming custom-designed for every single type.

## Interaction Rules

V1 should stay read-first.

That means:

- timeline rows are primarily for reading
- reference chip or job link can be clickable when relevant
- do not turn V1 into an inline timeline editor

If a row links to a job, the interaction should be obvious but quiet.

## Integration With Existing Bike Record UI

The existing `BikeRecordPanel` already handles:

- identity / hero surface
- general notes and current state
- technical baseline

The timeline should complement this.

It should not repeat the current-state content endlessly.

Examples:

- `Perfil actualizado` is good
- dumping every current technical spec as a timeline row is bad

The timeline should emphasize meaningful change and visit-level evidence.

## Relationship To Job Form

The full timeline should not migrate into the mechanic job form as the main owner surface.

What may happen later:

- recent bike events shown in compact form near the diagnosis workspace
- quick links from job form to relevant bike history

But that is later.

In Phase 3, the full implementation target is the bike profile.

## Responsive Guidance

Desktop:

- normal event list with timeline rail and compact metadata chips

Tablet/mobile:

- vertically stacked event cards are acceptable
- preserve chronology and readability over decorative timeline structure

Do not force desktop timeline ornamentation onto narrow screens.

## Suggested Empty-State Copy Direction

Keep copy practical.

Examples:

- `Aún no hay historial registrado para esta bicicleta.`
- `Los trabajos, cambios de ficha y eventos relevantes aparecerán aquí.`

## Future-Proofing For Diagnosis Refactor

The timeline UI should be built in a way that later allows selective reuse inside the diagnosis workspace.

This means:

- use reusable event row widgets where practical
- separate timeline row rendering from the bike-profile shell
- avoid hardcoding assumptions that only make sense in one page

## Non-Goals For This Handoff

Do not add now:

- inline timeline editing
- dense analytics charts inside the timeline tab
- automatic diagnosis suggestions
- giant expand/collapse logic for every event type
- a complex filter system before the basic chronology is proven useful

## Definition Of Done For UI Phase

The timeline UI handoff is complete when Gemini 3.1 Pro can implement a `Historial` surface that:

1. lives on the bike profile
2. clearly renders bike events in descending chronology
3. supports empty and loading states
4. stays visually consistent across event types
5. feels like a workshop record rather than a generic activity feed

## Final Recommendation

The best UI direction is a restrained, high-signal bike history tab.

The bike profile should tell the mechanic:

- this is the bike
- this is what we know now
- this is what has happened before

That is the correct UI bridge between the completed bike-profile work and the later diagnosis workspace redesign.