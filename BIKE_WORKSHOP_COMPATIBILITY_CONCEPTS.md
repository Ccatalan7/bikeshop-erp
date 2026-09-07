# Bike Workshop Compatibility Concepts

Last updated: 2026-09-06 (versioned ficha baseline and scoped chain evaluation)
Status: Living technical doctrine companion
Scope: canonical compatibility semantics for bike profile truth, product ficha truth, diagnosis and service gating, and compatibility scoring

**2026-09-06, identity ownership:** commercial category is a fallback, not the
owner of a product's technical class. The pending product-template binding
contract gives all readers the same resolved family and active facts. Facts
preserved outside that template remain evidence for review; they cannot satisfy
technical filters or produce a compatible recommendation. An unavailable
explicit binding yields caution, never a fallback to a different category
family. Numeric validity, nominal identity, completeness of purchase criteria
and OEM mechanical approval are separate conclusions. Global sanitation of all
catalogue families precedes product fill; see
[the audited scope](docs/development/product-specs-research-2026-09-05/global-audit-and-sanitation-2026-09-06.md).

## Why This File Exists

This file is the technical compatibility companion to `BIKE_WORKSHOP_MASTER_SCHEMA.md`.

The master schema owns the backbone:

- which layer stores which truth
- how truth flows from intake to diagnosis to memory
- which upstream and downstream systems must stay aligned

This file owns the compatibility doctrine:

- which technical seams are real compatibility seams
- which fields are broad anchors versus downstream refinements
- which matches are safe, weak, or invalid
- which product ficha values are canonical truth versus commercial metadata
- which unresolved gaps must stay in caution territory instead of being guessed away

If compatibility behavior changes in code or schema and this file is not updated, the implementation is semantically undocumented.

## Relationship To The Master Schema

Use `BIKE_WORKSHOP_MASTER_SCHEMA.md` for backbone architecture and layer ownership.

Use this file for technical and conceptual compatibility knowledge.

When a task changes compatibility semantics, product ficha meaning, diagnosis or wizard gating, or compatibility scoring doctrine, update both files in the same task.

## Evidence Standard

**Correction, 2026-09-05:** mechanical validity and software behavior have
different evidence. Production/schema/code prove what the ERP currently does;
they cannot overrule a physical interface or manufacturer restriction. Tests
prove the implemented interpretation only when their fixtures have independent
domain evidence. An old test is not proof that a combination works on a bike.

Use Sheldon Brown and Park Tool as the owner's required workshop foundations,
and model/generation-specific manufacturer manuals and compatibility tables
for exact claims. Compare scope and revision before resolving disagreement;
do not promote a historical interchangeability tip into universal approval.

The current source-backed learning is
[bicycle compatibility knowledge](docs/architecture/bicycle-compatibility-knowledge.md).
The [ficha architecture](docs/architecture/product-technical-specifications-contract.md)
and [family matrix](docs/architecture/product-spec-family-matrix.md) define the
target contract. They supersede older universal singular-ecosystem and
width-derived-speed doctrine in this file. KMC may support multiple brands;
store the supported combinations and conditions without inventing cross-products.
Unknown coverage stays unknown. Delivered scope and runtime proof are recorded
in the [implementation result](docs/development/product-specs-research-2026-09-05/implementation-result.md).

Generic search snippets, reseller copy and forum reports do not establish a
confirmed mechanical rule. Preserve source, scope, limitations and unresolved
conflicts. Re-audit live schema and writers before extending the target.

### Implemented distinctions — 2026-09-06

- Missing prerequisite: pending knowledge. The editor explains the prerequisite;
  existing known facts remain public and writable. A missing mode is not proof
  that eighteen previously published chain fichas are contradictory.
- Explicit false condition, invalid vocabulary/type or contradiction with a
  selected exact reference: blocking issue, including at the server boundary.
- Unmapped technical family: no assessment; do not label a tool or accessory as
  needing a compatibility repair merely because it has no template.
- Exact exclusive claim with an unknown bike platform: caution naming that
  platform. eGlide's 9/10/11 LINKGLIDE scope survives even without bike platform
  data. A known contrary platform is incompatible with that claim.
- Chain speed count or nominal/pin width alone: no green installation result.
  Manual KMC 6/7/8 plus 11/128 raises a request to verify the exact model/source,
  not a made-up universal physical prohibition. Binding the documented X8 EU
  edition makes a contradictory declared width a reference conflict.

The consumer uses `get_product_spec_contexts_v1`, normalized facts and scoped
reference claims. Historical ecosystem/profile fields no longer determine chain
compatibility. The initial three manufacturer editions are explicitly bounded;
other model coverage remains unknown until supported by its own evidence.

The chain/connector extension (`20260906103000`, verified 2026-09-06) treats
a connector's declared chain class separately from the bicycle's cog count.
Its consumer names documented target chains and exclusions and asks for the
installed chain identity; missing identity cannot produce a green fit result.
Model-specific reuse/direction and complete connector counts are separate facts.
Linking a reference preserves independent matching observations and evidence;
it must not reattribute them to catalog and erase them on later detach. See the
[second delivery](docs/development/product-specs-research-2026-09-05/chain-connector-implementation-2026-09-06.md).

## Core Doctrine

### 1. Upstream truth before downstream questioning

If a durable technical fact can live upstream, downstream diagnosis and service flows should consume it instead of repeatedly asking for it.

Examples:

- `bike_profiles.technical_profile.values.brakeType`
- `bike_profiles.technical_profile.values.freehubType`
- `bike_profiles.technical_profile.values.drivetrainConfig`
- `bike_profiles.technical_profile.values.drivetrainSpeeds`
- `bike_profiles.technical_profile.values.bottomBracketFamily`

### 2. One canonical vocabulary across the backbone

Bike profile truth, product ficha truth, diagnosis gating, service wizard logic, and compatibility scoring must reuse the same canonical keys whenever they refer to the same real compatibility seam.

Do not create one vocabulary for bikes and another one for products.

### 3. Commercial metadata is not technical truth

The following are not allowed to become runtime ficha truth or compatibility truth by themselves:

- `products.brand`
- product name text
- product description text
- weak commercial categories such as `products.category_name`

If a compatibility concept matters, it must exist as a first-class persisted structured field.

### 4. Broad anchors and exact seams must stay separate

Broad family or ecosystem claims are not the same thing as exact downstream platform truth.

The 2026-09-05 target separates identity/variant, intrinsic interfaces and scoped
compatibility relationships. Each family decides its prerequisites. A broad
ecosystem may summarize a documented relationship; it is not a mandatory owner
for every component or an input that creates exact platform compatibility.

Do not silently expand a broad claim into an exact one.

### 5. Coarse-to-fine matching is the right order

Compatibility should usually work in this order:

1. obvious hard split or family mismatch
2. coarse family-level gate
3. downstream structured refinement
4. final compatibility badge only when the true seam is explicit

### 6. Unknown is a valid state

Blank and unknown are not the same thing.

When the workflow needs to distinguish "not reviewed yet" from "confirmed but unresolved," the ficha or bike profile should expose an explicit `unknown` state instead of silently staying empty.

### 7. Conservative scoring beats guessed confidence

Nominal similarity is not enough for a full-compatible result.

If the true compatibility seam is still unresolved, the scorer should stay in `caution` territory even when a coarse match looks promising.

### 8. Runtime inference must stay structured-only

Live Dart-side inference may use already-structured signals, but it must not mine commercial prose during normal editing.

If packaging text later needs to backfill canonical fields, that belongs in an explicit reviewed DB fulfillment or migration workflow.

### 9. Diagnosis truth is not execution history

Diagnosis-linked compatibility logic must be based on present state, measured condition, or observed symptom.

Performed work and historical intervention belong to executed work and memory layers, not to diagnosis truth.

## Current Base Compatibility Kernel

These are the minimum upstream facts that already unlock real compatibility work and should remain the shared kernel across bike truth and product matching.

| Canonical field | Primary upstream home | Compatibility role |
|---|---|---|
| `bike_type` | `bikes.bike_type` | Gates impossible systems and default expectations |
| `wheel_size` | `bikes.wheel_size` | Drives wheel, rim, tire, and tube matching |
| `front_hub_spacing_mm` | `bikes.front_hub_spacing_mm` | Front hub and wheel fit |
| `rear_hub_spacing_mm` | `bikes.rear_hub_spacing_mm` | Rear hub, wheel, and frame fit |
| `brakeType` | `bike_profiles.technical_profile.values.brakeType` | Top brake-platform gate |
| `rimBrakeFamily` | `bike_profiles.technical_profile.values.rimBrakeFamily` | Required refinement when rim brakes are confirmed |
| `suspensionLayout` | `bike_profiles.technical_profile.values.suspensionLayout` | Gates shock and fork relevance |
| `freehubType` | `bike_profiles.technical_profile.values.freehubType` | Rear driver family for cassette, freewheel, BMX driver, and fixed cases |
| `drivetrainSpeeds` | `bike_profiles.technical_profile.values.drivetrainSpeeds` | Chain, cassette, shifter, and derailleur compatibility |
| `drivetrainConfig` | `bike_profiles.technical_profile.values.drivetrainConfig` | Upstream front-vs-rear drivetrain layout truth |
| `frontSpokeHoles` | `bike_profiles.technical_profile.values.frontSpokeHoles` | Front rim and hub matching |
| `rearSpokeHoles` | `bike_profiles.technical_profile.values.rearSpokeHoles` | Rear rim and hub matching |
| `valveType` | `bike_profiles.technical_profile.values.valveType` | Tube, rim, and tubeless valve compatibility |
| `bottomBracketFamily` | `bike_profiles.technical_profile.values.bottomBracketFamily` | Bottom bracket and crank interface matching |

## System-Specific Compatibility Knowledge

### Drivetrain

#### Drivetrain semantic stack

For the next drivetrain ficha contract, resolve type/function and identity as
far as evidence allows, then ask the component's actual interface questions.
Keep drivetrain mode, exact platform, control actuation and chain geometry
distinct. A supported combination binds system, generations/speeds and
conditions together; independent multi-selects must not create their cross-product.
The [family matrix](docs/architecture/product-spec-family-matrix.md) defines
family-specific prerequisites. There is no universal ecosystem-first stack.

#### Core drivetrain rules

- `freehubType` is the rear driver family field, not a cassette-only label.
- `freehubType` must support real body families such as `Shimano HG`, `Shimano HG Road 11`, `Micro Spline`, `SRAM XD`, `SRAM XDR`, `Campagnolo`, and `Campagnolo N3W` when the template actually needs those seams.
- rear-cog compatibility is not solved by speed alone; body family, range, spacer needs, and body-generation exceptions still matter.
- `cassette`, `freewheel`, and `fixed_cog` templates must not expose broad ecosystem-anchor fields as if they were the real rear-cog seam.
- cassette spacers must keep `freehub_type` explicit and keep `spacer_thickness_mm` as measured truth.
- chain width is an intrinsic measurement with a defined method and provenance. Distinguish nominal inner width, measured outer width and pin length. An outer measurement can inform an investigation but cannot certify supported speeds/profile or require an arbitrary closed list of dimensions. Use the identity and declared relationships for compatibility; retain measurements when available.
- `shifter` ficha behavior must gate by `shifter_position`.
- left or front shifters hide rear-side seams such as `drivetrain_speeds`, `rear_cog_count`, `shift_actuation_family`, and `drivetrain_platform`.
- right or rear shifters hide front-chainring-count semantics.
- pair or universal shifters may keep both sides visible.
- pair and universal shifters still stay in `caution` scoring territory until the front pull/indexing seam is modeled explicitly; only an exact right or rear shifter match may rise to `compatible`.
- `front_derailleur` ficha behavior must constrain `front_chainring_count` to real multi-ring values only.
- `front_derailleur` ficha behavior must suppress 1x-only ecosystem and platform claims such as `Single speed / BMX`, `SRAM Eagle`, and `SRAM T-Type Transmission`.
- `front_derailleur_clamp_mm` is only meaningful for clamp-mount front derailleurs.
- rear derailleur compatibility is not speed-only; actuation family, max-cog support, total capacity, cage expectations, and mounting still matter.
- drivetrain kits must stay in caution territory when only the front-side crankset or pedalier facts are explicit and the rear-side content of the kit is still unresolved.

#### Current scoring doctrine for drivetrain controls

- mark `incompatible` when there is a hard physical contradiction
- keep `caution` when the match is only nominal and the exact seam is unresolved
- allow `compatible` only when the real structured seam has actually been resolved

This conservative rule currently applies especially to:

- rear derailleurs
- front derailleurs
- shifters
- drivetrain kits
- cassette and freewheel families

### Brakes

- `brakeType` is the top brake-platform gate.
- `rimBrakeFamily` is a required refinement when `brakeType = rim`.
- rim, disc, roller, drum, coaster, and band brakes must stay explicit instead of being collapsed into fake binary categories.
- live service-profile rows may still drift back to legacy brake-type value spellings such as `disco_mec` or `v-brake`; the shared brake canonical layer must normalize those back into the backbone values before wizard rendering, answer persistence, diagnosis mapping, or upstream bike-truth promotion.
- rotor-size truth must use standardized values, not arbitrary text.
- rotor-specific fields should stay hidden until a disc platform is confirmed.
- rim-brake bikes should suppress rotor-specific diagnosis and compatibility flows.
- diagnosis-linked brake semantics must use one shared field-definition layer so the intake, diagnosis, and wizard layers do not fork the vocabulary.
- coarse brake wizard keys such as `pad_condition` and `rotor_condition` are only acceptable when their option sets are centrally anchored and the app-layer translator maps them into the split brake diagnosis model (`padWearPercent`, `padContaminationStatus`, `rotorTruenessStatus`, `rotorContaminationStatus`) instead of inventing local page semantics.
- if a brake wizard resolves missing upstream brake truth, that refinement should promote back into `bike_profiles.technical_profile.values` instead of staying trapped in wizard-only answers.

### Wheels, hubs, and valves

- `front_wheel` and `rear_wheel` are the real interactive wheel units; `wheels` may survive only as a compatibility alias or history fallback.
- hub ficha behavior must gate by wheel position.
- front hubs should suppress rear-only driver-family fields such as `freehub_type`.
- hub spacing should use standardized front and rear OLD values instead of one mixed free-text lane.
- front and rear spoke-hole counts are separate compatibility seams and must not collapse into one generic count field.
- `valveType` is a first-class compatibility seam for tubes, rims, and tubeless valves.

### Bottom bracket and crank interface

- `bottomBracketFamily` is upstream bike truth, not a service-note detail.
- crankset and chainring ficha semantics should depend on teeth, chainring count, mount, chainline, spindle interface, and bottom-bracket interface.
- crankset and chainring templates must not depend on broad ecosystem-anchor fields as if they were the main truth source.
- bottom-bracket and crankset scoring should stay in `caution` even when family, shell, or spindle-interface facts line up, until chainline, mounting, crank-length, and the exact shell/adapter standard seams are modeled more completely.
- bottom-bracket ficha behavior should also gate by `bottom_bracket_family`: pressfit-style families should not keep asking for threaded-cup standards and should keep `bb_shell_diameter_mm` visible as the real bore seam, while threaded/external-cup families should suppress that raw shell-diameter field; square-cartridge families should narrow spindle-interface choices to square variants, and `Hollowtech / 24mm externo` should not keep exposing loose spindle-length/diameter fields as if it were a cartridge spindle system.
- bottom-bracket service wizards should follow that same family-first gating upstream: `bottom_bracket_family` resolves first, then the wizard may expose `bb_shell_width_mm`, `bb_shell_diameter_mm`, and `spindle_interface` only when those seams are still unresolved and relevant for the chosen family.
- when service flows confirm missing bottom-bracket truth, those answers should promote back into `bike_profiles.technical_profile.values` instead of staying trapped in wizard-only notes or execution summaries.

## Product Ficha Boundaries

Product ficha must be able to show, edit, and persist the exact compatibility concept it relies on.

If the UI can only hint a concept but cannot actually persist it as a first-class field, that helper is outrunning the schema.

The product-side technical-family bridge should be used deliberately:

- `category_tech_mappings.technical_family` for coarse family meaning
- `spec_templates.technical_family` for the ficha/template family contract
- `product_spec_values` for fine structured truth

Do not promote `products.category_name` into runtime compatibility truth.

## Scoring Rules Across The Engine

Use this mental model:

- `incompatible` = a true hard split or contradiction is already explicit
- `caution` = there is a plausible or nominal match, but one of the real seams is still unresolved
- `compatible` = the real structured seam has been resolved strongly enough to support a confident match

Typical reasons to stay in `caution` territory include:

- speed matches but actuation does not
- body family matches but range or spacer generation is unresolved
- front-side crank facts match but rear-side kit content is still unknown
- broad ecosystem claims exist but exact platform truth does not
- product family fits but detailed ficha coverage is still sparse

## Current Known Gaps And Interim Rules

- `drivetrain_compatibility_family` was removed from the active production schema on 2026-04-27. Treat it only as historical migration input if it appears in old data or pre-cleanup environments; current drivetrain ficha flows must not render or persist it.
- `kit_contents` on drivetrain kits is currently unstructured text and is not strong enough to drive exact runtime gating by itself.
- some live service-profile vocabularies are still weak or action-oriented, such as values like `ok` or `replace`; those must not spread as canonical diagnosis truth.
- live catalog coverage for many drivetrain compatibility fields is still sparse, so conservative scoring is currently safer than dense optimistic matching.

## Alignment Checklist For Future Work

When a task changes compatibility behavior, verify alignment across all of these:

1. `bike_catalog` and any shared reference semantics.
2. `bike_profiles.technical_profile.values` and the upstream bike kernel.
3. `spec_definitions`, `spec_templates`, and `product_spec_values`.
4. diagnosis field definitions and diagnosis-linked wizard mappings.
5. service-profile question semantics and execution-only answer boundaries.
6. compatibility scoring code and focused regression tests.
7. `BIKE_WORKSHOP_MASTER_SCHEMA.md` and `.github/copilot-instructions.md`.

## Primary Implementation Surfaces

The current main implementation surfaces that should stay aligned with this document are:

- `supabase/sql/core_schema.sql`
- `lib/modules/bikeshop/config/drivetrain_canonical_data.dart`
- `lib/modules/bikeshop/config/brake_canonical_data.dart`
- `lib/modules/bikeshop/services/bike_product_compatibility_service.dart`
- `lib/modules/inventory/pages/product_form_page.dart`
- `lib/modules/inventory/services/spec_engine_service.dart`
- `lib/modules/bikeshop/pages/bike_form_dialog.dart`
- `lib/modules/bikeshop/pages/mechanic_job_form_page.dart`
- `lib/modules/bikeshop/services/service_wizard_service.dart`

This file should grow over time as the compatibility engine becomes more exact, but each new rule should remain anchored in real structured fields, real workshop seams, and real validation.
