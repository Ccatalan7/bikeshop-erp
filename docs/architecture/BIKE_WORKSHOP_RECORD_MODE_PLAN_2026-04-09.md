# Bike Workshop Record Mode Plan - 2026-04-09

## Handoff Signatures

- Phase A architecture / non-visual groundwork plan and implementation: GPT-5.4
- Phase B record-mode UI implementation and visual handoff target: Gemini 3.1 Pro
- Phase B compilation fixes and data binding completion: GitHub Copilot (Gemini 3.1 Pro Preview)

## Purpose

This document defines the implementation plan for separating:

- capture mode: the bike wizard used for create/edit
- record mode: the persisted bike view shown inside the client logbook

The current problem is not that the wizard is bad.
The wizard is good.

The problem is that the client logbook currently reuses the same wizard as the default right-side bike presentation, which makes a saved bike feel like an unfinished intake flow instead of a stable workshop asset.

## Current Repo Reality

### What is happening now

The client logbook mounts the embedded bike wizard directly as the right pane when a bike is selected.

Current seam:

- [client_logbook_page.dart](lib/modules/bikeshop/pages/client_logbook_page.dart) uses `BikeFormDialog` inside `_buildBikesTab()` for the desktop right pane.
- [bike_form_dialog.dart](lib/modules/bikeshop/pages/bike_form_dialog.dart) is a guided wizard optimized for capture/edit.
- [mechanic_job_form_page.dart](lib/modules/bikeshop/pages/mechanic_job_form_page.dart) already points in the right direction by showing a compact read-first bike context summary instead of the full wizard.
- [bikeshop_models.dart](lib/modules/bikeshop/models/bikeshop_models.dart) already has `BikeProfile` and `summarySnapshot`, which gives us a good foundation for a record-mode read model.

### Diagnosis

The system currently has a strong capture UI but no dedicated persisted presentation layer for a saved bike.

That means the product is missing a mode boundary:

- creating/editing a bike
- viewing a saved bike as an asset in the client record

## Product Decision

The correct product model is:

1. The wizard remains the canonical create/edit flow.
2. The client logbook should default to a record-mode bike view, not the wizard.
3. The wizard should only appear when the user explicitly creates a bike or clicks edit.

This preserves the value of the wizard while preventing it from becoming the permanent face of saved bike data.

## Can This Be Implemented Without UI Work First?

Yes, mostly.

The underlying architecture can be implemented before the visual redesign. That work can prepare almost everything the UI agent needs:

- stable read model for persisted bike presentation
- explicit mode separation in state
- summary and display data derived outside widgets
- clear entry points for create, view, and edit

But one limitation is real:

The user-facing problem is only fully solved once the client logbook stops rendering `BikeFormDialog` as the default right pane.

So the answer is:

- yes, the structural and behavioral groundwork can be implemented first without doing visual design work
- no, the final product fix is not complete until another agent swaps the persisted bike view from wizard mode to record mode

## Recommended Split Of Work

### Phase A: Non-visual implementation groundwork

This can be done first.

### Phase B: Record-mode UI implementation

This can be handed to another agent once the groundwork exists.

## Phase A - What To Implement Without UI Redesign

### 1. Introduce an explicit bike panel mode model

Replace the current implicit flow based on `_isEditingBike` and `_selectedBikeId` with a more explicit state model.

Recommended state enum:

```dart
enum ClientBikePanelMode {
  none,
  record,
  creating,
  editing,
}
```

Intent:

- `record` means a saved bike is being viewed as a persisted asset
- `creating` means the wizard is open for a new bike
- `editing` means the wizard is open for an existing bike

This is not visual work. It is flow architecture.

### 2. Add a dedicated read model for persisted bike presentation

Current `Bike` and `BikeProfile` are storage/domain models.

They should not force the UI layer to assemble presentation text ad hoc.

Add a read model such as:

```dart
class BikeRecordSnapshot {
  final Bike bike;
  final BikeProfile? profile;
  final String identityTitle;
  final String? identitySubtitle;
  final List<String> intakeLines;
  final List<String> technicalLines;
  final List<String> notesLines;
  final List<String> warnings;
  final DateTime? lastConfirmedAt;
  final bool isProfileComplete;
}
```

Intent:

- one stable payload for record-mode rendering
- widget layer receives display-ready sections instead of reconstructing them repeatedly
- summary formatting moves out of the page/widget layer

### 3. Move bike summary derivation out of widgets

Right now the summary behavior is partially embedded in widgets and `summarySnapshot` accessors.

Create a mapper/helper responsible for converting:

- `Bike`
- `BikeProfile`
- optional job stats or service stats

into a `BikeRecordSnapshot`.

Possible location:

- `lib/modules/bikeshop/models/bikeshop_models.dart`
- or a new formatter/helper file under `lib/modules/bikeshop/services/` or `lib/modules/bikeshop/utils/`

Design rule:

- page widgets should not decide how persisted bike data is summarized
- they should consume a normalized record snapshot

### 4. Add a service method dedicated to record-mode data

Current service methods:

- `getBikeProfile(...)`
- bike CRUD methods

Add a dedicated method for record-mode reads, for example:

```dart
Future<BikeRecordSnapshot?> getBikeRecordSnapshot(String bikeId)
```

Responsibilities:

- load bike
- load profile
- build normalized read snapshot
- optionally include lightweight derived metadata if needed later

This keeps the future UI implementation simple and prevents the client logbook from becoming the place where all read-side composition logic lives.

### 5. Define record completeness rules

The new record mode should know whether a bike is:

- identity only
- partially profiled
- sufficiently profiled

This should be implemented as logic, not styling.

Examples:

- no `BikeProfile` => incomplete profile
- profile exists but no intake/technical highlights => partial
- enough summary lines and no blocking warnings => complete enough

This allows the UI agent to render calm prompts like “Completar ficha” without inventing new business logic.

### 6. Define record-mode actions contract

Before the UI agent starts, the app should already know what actions a saved bike supports in record mode.

Recommended actions:

- edit bike/profile
- create new job for this bike
- view bike-related history
- optionally quick duplicate or attach image later

These actions should be defined as behavior and state transitions first, even if the final buttons are implemented later by another agent.

### 7. Keep `BikeFormDialog` scoped to capture mode only

No redesign needed yet.

But the architectural rule should become explicit:

- `BikeFormDialog` is not the persisted record view
- `BikeFormDialog` is only for create/edit

That rule should drive all future wiring in the client logbook and other bike-entry surfaces.

## Phase B - What The UI Agent Should Implement Later

This is the part to hand off.

### Goal

Create a dedicated record-mode bike panel for the client logbook right pane.

### UX direction

Keep this high-level only:

- read-first, not form-first
- calm, stable, asset-like presentation
- fast scan of identity, intake, technical baseline, and notes
- clear edit action that re-opens the wizard intentionally
- feels like a saved bike record, not a draft process

### Required behavior

When the user selects a saved bike in the client logbook:

- show record mode by default

When the user clicks edit:

- open the wizard in edit mode

When the user clicks add bike:

- open the wizard in create mode

When the user saves from the wizard:

- return to record mode for that saved bike
- refresh the record snapshot

### Minimal UI agent handoff target

The UI agent should replace this current coupling:

- desktop right pane -> `BikeFormDialog`

with this:

- desktop right pane -> `BikeRecordPanel` by default
- explicit create/edit states -> `BikeFormDialog`

## No Database Redesign Required For This Step

This separation does not require a new schema redesign.

The existing profile layer is already enough:

- `bike_profiles.intake_profile`
- `bike_profiles.technical_profile`
- `bike_profiles.summary_snapshot`

At most, we may refine the summary-building logic so record mode gets better display-ready data, but the persistence model itself already supports this direction.

## Suggested Execution Order

1. Add `ClientBikePanelMode` flow state in the client logbook.
2. Add `BikeRecordSnapshot` read model.
3. Add service/helper mapping from `Bike` + `BikeProfile` to `BikeRecordSnapshot`.
4. Refactor summary derivation out of widgets.
5. Ensure save/cancel transitions resolve back to explicit panel modes.
6. Hand off record-mode panel UI implementation to another agent.

## Acceptance Criteria For Phase A

Phase A is done when all of these are true:

1. The app has an explicit conceptual separation between bike record mode and bike wizard mode.
2. The client logbook state no longer depends only on a boolean editing flag to infer presentation intent.
3. Persisted bike display data can be loaded through a dedicated read model.
4. Summary formatting logic lives outside the visual page widgets.
5. Another agent can implement the record-mode panel mostly as UI work instead of rethinking domain flow.

## Acceptance Criteria For Final Completion

The full feature is complete when all of these are true:

1. Saved bikes in the client logbook open in record mode by default.
2. The wizard appears only for create/edit.
3. Saving a bike returns to the persisted record presentation instead of leaving the user in wizard framing.
4. The bike feels like a stable workshop asset, not an unfinished intake process.

## Final Recommendation

Yes, this can be split cleanly.

I can do the non-visual architecture work first so another agent receives a clean target:

- one explicit mode model
- one stable record snapshot
- one service/read path for persisted bike presentation
- one clear rule that the wizard is capture UI only

After that, the UI agent can focus on designing and implementing the actual record-mode panel without having to invent the product logic.

## Signature

- This handoff document was prepared and updated by: GPT-5.4
- The UI implementation agent working from this handoff should sign as: Gemini 3.1 Pro