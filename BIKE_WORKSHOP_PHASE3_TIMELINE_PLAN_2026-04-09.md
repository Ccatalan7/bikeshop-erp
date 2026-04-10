# Bike Workshop Phase 3 Timeline Plan - 2026-04-09

## Correction Notice - 2026-04-09

This document describes a valid first-layer bike chronology, but it is not sufficient as the final Phase 3 product target.

If read alone, it can mislead an implementation agent into shipping a generic event rail and stopping there.

That would be too weak.

Use this document together with [BIKE_WORKSHOP_PHASE3_COMPONENT_INTELLIGENCE_SPEC_2026-04-09.md](BIKE_WORKSHOP_PHASE3_COMPONENT_INTELLIGENCE_SPEC_2026-04-09.md).

The corrected interpretation is:

- `bike_events` chronology is the macro history rail
- the real intelligence layer must also include component lifecycle tracking, measurement series, and a clickable systems surface

## Handoff Signatures

- Product logic, planning, event model direction, and implementation sequencing: GPT-5.4
- Timeline UI implementation handoff target: Gemini 3.1 Pro

## Purpose

This document defines Phase 3 of the bike workshop roadmap: the bike history and evidence timeline.

Phase 1 established the guided intake flow.
Phase 2 established the persistent bike profile.
Phase 3 makes the bike cumulative and time-aware.

The goal is simple:

- the bike profile should show what the bike is now
- the bike timeline should show what has happened to the bike over time

This is the layer that turns the bike from a static asset into workshop memory.

## Core Product Decision

The bike timeline belongs on the bike profile as a product surface.

It does NOT belong inside the `bike_profiles` row as embedded history.

The correct split is:

- `bikes`: durable bike identity
- `bike_profiles`: latest known intake and technical baseline
- `bike_events`: chronological evidence and history for the bike

This preserves a clean separation between current state and historical evidence.

## Why This Is The Correct Next Step

This step comes before the diagnosis workspace refactor for a reason.

If the diagnosis workspace is redesigned before the bike has a real timeline, the mechanic still writes in a context-poor environment.

Once the bike has a usable chronology, the later diagnosis workspace can pull from:

- prior jobs
- confirmed spec updates
- reported incidents
- replaced components
- recurring measurements

That makes the future diagnosis refactor much more valuable.

## Current Repo Reality

The repo already has:

- `bikes` as the durable identity record
- `bike_profiles` as the persisted intake + technical baseline
- `BikeRecordSnapshot` as the read model for persisted presentation
- `BikeRecordPanel` as the current bike-profile surface in the client logbook

The repo does NOT yet have:

- a dedicated bike event log
- a bike timeline read model
- a timeline section inside the bike record UI
- automatic logging rules for bike-profile and bike-job history

## Product Boundary

Two timelines should exist and remain distinct:

### 1. Job Timeline

This is the chronology for one specific service visit.

It answers:

- what happened during this job
- what status changes occurred
- what the mechanic recorded during this visit

### 2. Bike Timeline

This is the chronology for the bike across visits.

It answers:

- what important things have happened to this bike over time
- what facts changed
- what interventions matter later

These must not be collapsed into one generic list.

## Scope Of Phase 3

Phase 3 should deliver:

1. a dedicated bike event model
2. a tenant-safe event log in the database
3. a bike-profile timeline surface in the UI
4. a narrow first batch of useful event types
5. a read model that can render a calm, mechanic-readable chronology

## What The Timeline Should Capture First

The first version should stay narrow and useful.

Recommended first event types:

- `bike_registered`
- `profile_created`
- `profile_updated`
- `job_created`
- `job_completed`
- `incident_reported`
- `component_replaced`
- `measurement_recorded`

The first version should prioritize events that are:

- durable
- meaningful across visits
- likely to matter later in diagnosis or compatibility work

## What Should Not Be In Phase 3 V1

Do not build these yet:

- a giant freeform timeline of every tiny edit
- automatic symptom diagnosis
- twenty measurement types on day one
- a full forensic audit viewer for all bike changes
- broad parts intelligence logic in the same iteration

Phase 3 should establish the right history architecture, not solve every future workflow immediately.

## Event Categories

The event model should support a few conceptual categories.

### State Events

Examples:

- bike registered
- profile created
- profile updated
- technical baseline confirmed

### Visit Events

Examples:

- job created
- bike received for service
- job completed
- follow-up recommended

### Evidence Events

Examples:

- chain wear recorded
- rotor thickness recorded
- brake pad wear recorded
- wheel true / spoke condition recorded

### Incident Events

Examples:

- crash reported
- transport damage reported
- prolonged outdoor storage reported

### Component Events

Examples:

- chain replaced
- cassette replaced
- derailleur hanger replaced
- tire replaced

## Source Of Truth Rules

Every event should have a clear source.

Allowed event sources:

- manual mechanic entry
- derived from bike profile save
- derived from job lifecycle transition
- derived from future measurement capture workflows

The app should never create fake mechanic conclusions.

The system may log:

- that a drivetrain speed was confirmed
- that a rear rotor size changed from unknown to 160 mm
- that a crash was reported

The system should not log:

- probable root cause guesses
- speculative failure interpretations

## Where The Timeline Lives In The Product

The timeline should render inside the bike profile / bike record view.

This means:

- client logbook bike record panel is the primary surface
- the bike timeline is part of the saved-bike experience
- it is not buried inside the job form as the main owner surface

Later, compact timeline summaries can also appear in the mechanic job screen, but the canonical owner surface is the bike profile.

## Recommended UI Structure

The bike profile should evolve into three layers:

1. identity and current status
2. current baseline sections
3. historical timeline

That timeline can be implemented as:

- a third tab inside `BikeRecordPanel`
- or a lower section if the UI agent believes the current two-tab structure should become three-tab

Current recommendation:

- keep `General y Notas`
- keep `Ficha Técnica`
- add `Historial`

This is the cleanest handoff target for Gemini 3.1 Pro.

## First Version Timeline UX Rules

The timeline should be calm and readable.

Each row should show:

- event date
- event title
- compact summary
- optional reference chip such as job number
- optional severity / info tone only when meaningful

The UI should prefer clarity over decoration.

It should feel like a workshop record, not a social feed.

## Recommended Implementation Order

### Phase 3A. Event Model And Read Path

- define database shape
- define event types
- add Flutter model(s)
- add service methods

### Phase 3B. First Auto-Generated Events

- bike registered
- profile created / updated
- job created / completed

### Phase 3C. Timeline UI In Bike Profile

- render timeline on bike profile
- support loading, empty state, and chronology ordering

### Phase 3D. Manual High-Value Evidence Events

- incident reported
- component replaced
- measurement recorded

Only after this is stable should the roadmap advance to diagnosis workspace refactor.

## Relationship To Diagnosis Refactor

Diagnosis remains in the roadmap and remains important.

But it should come after the bike timeline exists.

Why:

- diagnosis needs context to become meaningfully smarter
- the timeline gives that context
- otherwise the refactor is visual only and loses the strategic benefit of the bike-memory model

## Definition Of Done For Phase 3

Phase 3 is complete when all of these are true:

1. every bike can have a tenant-scoped event chronology
2. the bike profile UI can render that chronology clearly
3. the first event batch covers bike registration, profile updates, and job lifecycle
4. the history is separate from current profile state
5. the later diagnosis workspace can consume that history as context

## Final Recommendation

The timeline should be treated as the bike's long-term memory surface.

The bike profile should show the current truth.
The bike timeline should show how that truth evolved.

That is the right bridge between the existing bike-profile work and the later diagnosis workspace redesign.