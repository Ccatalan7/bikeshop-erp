# Bike Workshop Phase 3 Timeline SQL Spec - 2026-04-09

## Correction Notice - 2026-04-09

This SQL spec is only the macro chronology layer.

It should not be interpreted as the full database target for bike intelligence.

Future agents must pair it with [BIKE_WORKSHOP_PHASE3_COMPONENT_INTELLIGENCE_SPEC_2026-04-09.md](BIKE_WORKSHOP_PHASE3_COMPONENT_INTELLIGENCE_SPEC_2026-04-09.md), which defines the missing component lifecycle and measurement-series layers.

## Handoff Signatures

- Schema direction, event-log structure, tenant/RLS rules, and rollout sequencing: GPT-5.4
- SQL implementation and schema-connected UI handoff target: Gemini 3.1 Pro

## Purpose

This document defines the recommended database and backend shape for the bike timeline / bike events layer.

The main rule is:

- render the timeline on the bike profile
- store the timeline in a dedicated event log

Do not store the bike history as embedded JSON inside `bike_profiles`.

## Core Decision

Create a dedicated tenant-scoped `bike_events` table.

Do not overload:

- `bikes`
- `bike_profiles`
- `mechanic_jobs`

The bike timeline is a separate concern: historical evidence.

## Why A Dedicated Event Table Is Correct

It gives us:

- tenant-safe querying by `bike_id`
- clean chronology ordering
- filtering by event type
- linkage to jobs where relevant
- future support for measurements and components without schema chaos

It also preserves the existing architecture:

- `bikes` = identity
- `bike_profiles` = current baseline state
- `bike_events` = historical evidence

## Recommended Table

```sql
create table if not exists public.bike_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references public.tenants(id) on delete cascade not null,
  bike_id uuid references public.bikes(id) on delete cascade not null,
  job_id uuid references public.mechanic_jobs(id) on delete set null,
  event_type text not null,
  event_category text not null,
  event_date timestamptz not null default now(),
  title text not null,
  summary text,
  source text not null default 'manual',
  reference_number text,
  severity text,
  payload jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

## Mandatory Multi-Tenant Rules

This is a tenant-data table.

It MUST have:

- `tenant_id`
- tenant index
- RLS enabled
- CRUD policies scoped to `public.user_tenant_id()`

Recommended indexes:

```sql
create index if not exists idx_bike_events_tenant
  on public.bike_events(tenant_id);

create index if not exists idx_bike_events_bike
  on public.bike_events(bike_id);

create index if not exists idx_bike_events_bike_date_desc
  on public.bike_events(bike_id, event_date desc, created_at desc);

create index if not exists idx_bike_events_job
  on public.bike_events(job_id)
  where job_id is not null;

create index if not exists idx_bike_events_type
  on public.bike_events(event_type);
```

## RLS Policies

```sql
alter table public.bike_events enable row level security;

drop policy if exists "bike_events_select" on public.bike_events;
drop policy if exists "bike_events_insert" on public.bike_events;
drop policy if exists "bike_events_update" on public.bike_events;
drop policy if exists "bike_events_delete" on public.bike_events;

create policy "bike_events_select" on public.bike_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_events_insert" on public.bike_events
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "bike_events_update" on public.bike_events
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "bike_events_delete" on public.bike_events
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());
```

## Recommended Domain Vocabulary

### `event_category`

Keep this broad and stable:

- `state`
- `visit`
- `evidence`
- `incident`
- `component`

### `event_type`

Keep the first version narrow:

- `bike_registered`
- `profile_created`
- `profile_updated`
- `job_created`
- `job_completed`
- `incident_reported`
- `component_replaced`
- `measurement_recorded`

Recommended constraint pattern:

```sql
alter table public.bike_events
  add constraint bike_events_category_check
  check (event_category in ('state', 'visit', 'evidence', 'incident', 'component'));

alter table public.bike_events
  add constraint bike_events_severity_check
  check (severity is null or severity in ('info', 'warning', 'critical'));
```

For `event_type`, either:

- use a check constraint if the list is intentionally strict in V1
- or keep it open text and enforce known values at app/service level

Recommended V1 approach:

- use open text for `event_type`
- keep `event_category` constrained

This leaves room for future timeline expansion without immediate migration churn.

## Business Date vs Technical Timestamp

Store both concepts separately:

- `event_date` = business chronology shown in timeline
- `created_at` = when the row was actually written

This matters because bike history is product-facing chronology, not just raw insertion order.

The timeline should order primarily by:

1. `event_date desc`
2. `created_at desc`

## `payload` Contract

The `payload` JSON should store structured details specific to each event without exploding columns.

Examples:

### `profile_updated`

```json
{
  "changedSections": ["intake_profile", "technical_profile"],
  "lastConfirmedAt": "2026-04-09T20:00:00Z"
}
```

### `job_completed`

```json
{
  "jobStatus": "completed",
  "invoiceId": "...",
  "followUpRecommended": true
}
```

### `measurement_recorded`

```json
{
  "measurementType": "chain_wear",
  "value": 0.75,
  "unit": "ratio",
  "location": "rear drivetrain"
}
```

### `component_replaced`

```json
{
  "componentType": "chain",
  "oldPart": "11-speed chain worn",
  "newPart": "KMC X11"
}
```

## Source Rules

Recommended `source` values:

- `manual`
- `profile_save`
- `job_lifecycle`
- `measurement`
- `migration`

This helps later debugging and trust.

## Automatic Event Creation Strategy

Start with the smallest reliable set.

### V1 automatic events

- create `bike_registered` when a bike is first created
- create `profile_created` when a bike profile appears for the first time
- create `profile_updated` when the profile is edited later
- create `job_created` when a mechanic job is created for a bike
- create `job_completed` when a job transitions to completed / delivered state

### V1 manual events

- `incident_reported`
- `component_replaced`
- `measurement_recorded`

This avoids prematurely coupling too much logic into triggers.

## Triggers vs Service-Layer Logging

Recommended split:

### Use service-layer logging first for:

- profile save flows
- explicit manual event creation
- app-controlled lifecycle actions

### Use triggers carefully for:

- stable lifecycle transitions on tables already governed by database-side status logic

Reason:

- service-layer logging is easier to evolve during product shaping
- triggers are better once event semantics are proven stable

## Optional Read View

If timeline rendering later wants a stable UI-oriented shape, a view can be added:

```sql
create or replace view public.bike_events_view as
select
  be.id,
  be.tenant_id,
  be.bike_id,
  be.job_id,
  be.event_type,
  be.event_category,
  be.event_date,
  be.title,
  be.summary,
  be.source,
  be.reference_number,
  be.severity,
  be.payload,
  be.created_by,
  be.created_at,
  up.full_name as created_by_name,
  mj.job_number
from public.bike_events be
left join public.user_profiles up on up.user_id = be.created_by
left join public.mechanic_jobs mj on mj.id = be.job_id;
```

This is optional for V1 of Phase 3, not mandatory on day one.

## Flutter / Service Targets

Expected additions later:

- `BikeEvent` model in `bikeshop_models.dart`
- service methods such as:
  - `getBikeEvents(String bikeId)`
  - `createBikeEvent(BikeEvent event)`
  - helper methods for auto-logging profile/job events

## Source Of Truth Rule

If implemented, the schema source of truth must be updated in:

- `supabase/sql/core_schema.sql`

If a focused deployment file is created, it should also exist as a migration, but `core_schema.sql` remains the master file.

## Recommended Rollout

1. add `bike_events` table and RLS
2. add Flutter model and service read path
3. render empty / populated timeline in the bike profile UI
4. add first automatic event creation for profile and job lifecycle
5. add manual evidence event creation later

## Definition Of Done

The schema layer is ready when:

1. bike history is stored in a dedicated tenant-safe table
2. events can be queried by `bike_id` in correct chronology order
3. the model supports both automatic and manual event creation
4. the table shape is narrow enough for V1 but extensible enough for later evidence capture

## Final Recommendation

Do not over-normalize Phase 3.

One strong `bike_events` table with clear event semantics is the right start.

That gives the product a real bike timeline now, while leaving room for more specialized evidence structures later if the workshop truly needs them.