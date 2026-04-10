# Bike Workshop Central Memory Model - 2026-04-09

## Handoff Signatures

- Central architecture reset and simplification direction: GPT-5.4
- Next implementation target for schema/UI execution: Gemini 3.1 Pro

## Why This Doc Exists

The initiative drifted toward treating the bike timeline as the main feature.

That is not the real product.

The real product is one centralized bike memory model that connects:

- bike identity
- current baseline
- systems current status
- installed components
- recurring observations and measurements
- interventions and replacements
- visit-specific diagnosis in jobs
- the same product/service identities and technical concepts already used by the business

This document defines the simplest correct version of that model.

## One Sentence Definition

The bike is the permanent technical memory anchor; jobs are the visit-specific reasoning workspace; systems, components, observations, and interventions connect the two.

## Core Boundary Rules

### What belongs on the bike memory side

- stable bike identity
- intake background context
- technical baseline
- current system statuses
- current installed important components
- historical measurements and interventions
- cross-visit incidents and notable outcomes

### What belongs on the job side

- customer request for this visit
- mechanic diagnosis for this visit
- work performed for this visit
- notes about this visit

### What connects them

- structured observations captured during jobs
- interventions / replacements confirmed during jobs
- links from observations and replacements back to the job
- links from observations and replacements back to the specific bike in the job, the job item, and the real product/service identity

### What must stay shared across the whole ERP

- tracked installed parts should use real `products` when available
- tracked service workflows should use real service products when available
- product ficha tecnica should provide the technical identity of installable tracked parts
- bike encyclopedia suggestions should use the same technical concepts, not a separate schema philosophy

## The Simplest Correct Central Model

### Object 1. `Bike`

Purpose:

- durable identity record

Already covered by:

- `bikes`

### Object 2. `BikeProfile`

Purpose:

- current long-lived background and technical baseline

Already covered by:

- `bike_profiles`

### Object 3. `BikeSystemState`

Purpose:

- the current high-level status per important system

Recommended first systems:

- drivetrain
- front_brake
- rear_brake
- front_wheel
- rear_wheel
- frame_cockpit
- suspension

Recommended first fields:

- `system_key`
- `overall_status` = `ok | attention | critical | unknown`
- `status_note`
- `last_reviewed_at`
- `last_job_id`
- `payload`

This is the current-state layer for quick mechanic reading.

### Object 4. `BikeComponentSlot`

Purpose:

- the currently installed important parts that need lifecycle awareness

Recommended first slots:

- chain
- cassette
- chainring
- front_rotor
- rear_rotor
- front_pads
- rear_pads
- front_tire
- rear_tire
- derailleur_hanger

Each slot should be able to point to the current lifecycle record.

This avoids asking mechanics to reconstruct the current bike from old jobs.

Each tracked slot should also prefer a real `product_id` from the catalog.

That product is not just for billing. It is also the authoritative installed-part identity whenever the catalog supports it.

### Object 5. `BikeObservation`

Purpose:

- a typed technical fact recorded at a point in time

Observation categories:

- measurement
- condition_assessment
- diagnosis_snapshot
- incident
- confirmation

Examples:

- chain wear = 0.75
- front rotor thickness = 1.72 mm
- rear brake overall condition = attention
- drivetrain skipping under load reported

Those observations should be able to retain the job/service context that produced them.

### Object 6. `BikeIntervention`

Purpose:

- a historical action that changed the bike state

Intervention categories:

- replacement
- adjustment
- service
- installation
- removal

Examples:

- chain replaced
- front rotor replaced
- rear brake bled
- rear wheel trued

Interventions should support linkage to:

- the job
- the specific bike inside that job
- the exact `mechanic_job_item`
- the real `product_id` and/or `service_product_id`

### Object 7. `BikeMacroEvent`

Purpose:

- a read-oriented chronology rail for overview only

This is where the current `bike_events` fit.

Important:

- this is not the primary model
- it is an output or companion view of the central model

## Simplicity Strategy

The system becomes unusable if it tries to model the entire bicycle at once.

So the first version should start with:

### First systems

- drivetrain
- front_brake
- rear_brake

### First component slots

- chain
- front_rotor
- rear_rotor
- front_pads
- rear_pads

### First repeated measurements

- chain_wear
- rotor_thickness_front
- rotor_thickness_rear
- pad_wear_front
- pad_wear_rear

### First current statuses

- drivetrain overall status
- front brake overall status
- rear brake overall status

This is enough to create real value without overwhelming staff.

It also keeps the first slice grounded in business reality because these tracked parts and services already map naturally to real products and service products.

## How Diagnosis Fits Without Being Replaced

Diagnosis remains a core part of the mechanic job form.

The system should not replace diagnosis with a structured diagnosis engine.

Instead:

- the mechanic writes the visit diagnosis in the job narrative fields
- the mechanic may also attach a few structured observations to systems/components
- those structured observations update bike memory across visits

Example:

- Job diagnosis text: "salta bajo carga, posible desgaste avanzado del tren trasero"
- Structured observation: `chain_wear = 0.75`, linked to drivetrain
- Structured intervention later: `chain replaced`, linked to the actual chain product installed on the job

That is the correct coexistence.

## Current State vs Historical Evidence

This distinction is mandatory.

### Current state

- `BikeProfile`
- `BikeSystemState`
- current component slot mapping

### Historical evidence

- observations
- interventions
- lifecycle records
- macro events

Current state answers:

- what is true now

Historical evidence answers:

- how did we get here

## Replacement Reset Rule

This is one of the most important rules in the whole system.

If a measured part is replaced, the old measurement history should remain historically visible but should no longer define the current part.

Examples:

- new chain installed -> previous chain wear history remains attached to the old chain lifecycle; current chain starts a new lifecycle
- new front rotor installed -> previous rotor thickness series remains historical; current front rotor starts its own series

The system must represent replacement as:

1. close old lifecycle
2. create new lifecycle
3. repoint current component slot
4. preserve old measurements under the old lifecycle

## UI Consequence

The bike profile should eventually expose four reading layers:

- General
- Ficha Técnica
- Sistemas
- Historial

Where:

- `Sistemas` is the real intelligence home
- `Historial` is the overview chronology rail

## Recommended Implementation Order

Before new schema is created, the architecture must explicitly preserve the existing operational seam already present in code:

- `mechanic_job_bikes` identifies which bike in the job was serviced
- `mechanic_job_items.job_bike_id` identifies which bike a row belongs to
- `mechanic_job_items.product_id` and `service_product_id` identify the actual commercial/catalog objects involved

### Step 1. Preserve what is already valid

- keep `bikes`
- keep `bike_profiles`
- keep job diagnosis narrative as-is

### Step 2. Add the central current-state layer

- define `BikeSystemState`
- define the first component slots

### Step 2.5. Bind the model to the real product/service backbone

- use `products` as the preferred identity for tracked installable parts
- use service products as the preferred identity for tracked service workflows
- use product ficha tecnica as the technical identity layer for tracked parts
- make the bike encyclopedia follow the same technical concepts so suggestion and current installed truth are compatible

### Step 3. Add the evidence layer that matters first

- measurements for chain wear and rotor thickness front/rear
- interventions for chain / rotor / pad replacement

### Step 4. Add the UI around systems, not around a feed

- systems list or clickable schema
- selected system shows current state + measurements + interventions

### Step 5. Keep the macro timeline as a companion view only

- useful for chronology
- insufficient as the main surface

## Definition Of Correct Direction

The architecture is on the right track only if a mechanic can answer all of these without digging through raw job notes:

1. what is the current status of the drivetrain
2. what parts are currently installed in the tracked slots
3. what is the latest measured wear of the tracked parts
4. what changed recently and in which job
5. what remains visit-specific diagnosis versus stable bike memory

## Final Rule

Future implementation must move around the centralized bike memory model.

If a new feature does not clearly plug into that center, it is probably another disconnected island and should be challenged before implementation.