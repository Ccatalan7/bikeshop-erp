# 🧠 Project Overview

This is a **MULTI-TENANT SaaS ERP** for managing bikeshops. Multiple independent businesses use the same app with **COMPLETE DATA ISOLATION**. It includes accounting, inventory, POS, customer management, maintenance tracking, HR, website builder, marketing, and analytics. Built in **Flutter/Dart**, targeting **Windows, Android, Web**, and optionally macOS/iOS.

The backend uses Supabase exclusively, with PostgreSQL as the relational database, Supabase Auth for authentication (including OAuth2 support like Google login), and Supabase Storage for file management. All business logic follows an accounting-first approach, with audit-ready data structures and strong relational integrity across modules.

---

# Product Language

- User-facing workshop copy must call mechanic jobs `trabajo` / `trabajos`, not `pega` / `pegas`.
- User-facing HR copy must call staff `trabajador` / `trabajadores`, not `empleado` / `empleados`.
- Legacy route names, database enum values, table/function names, and historical file names may still contain `pegas`, `pega`, or `employee` for compatibility. Do not surface those legacy terms in labels, headings, empty states, toasts, PDFs, AI responses, or new documentation unless explicitly explaining the legacy internal identifier.

---

# Platform Priority And Cross-Platform Usability

The primary product experience is **macOS desktop**. For every task, agents should prioritize macOS desktop usability first when deciding layout density, keyboard/mouse workflows, panel behavior, window sizing, shortcuts, native integrations, and performance expectations.

This does **not** mean other platforms are optional. Every implementation must still consider:

- Windows desktop usability, because the ERP is actively used on Windows.
- iOS and Android usability, especially for workflows that may be used on phones/tablets.
- ERP web usability, including browser constraints, responsive layout, and deploy behavior.
- Public store web usability, including mobile storefront behavior, SEO, performance, and clean routing.

## Practical Rule

Design and implement the best macOS desktop workflow first, then deliberately adapt it for the other supported surfaces instead of assuming the desktop UI will automatically work everywhere.

For UI/UX work:

- Start from a dense, professional desktop ERP layout optimized for mouse, keyboard, large tables, side panels, and repeated operational use.
- Check how the same workflow behaves on Windows desktop before treating it as complete.
- Provide responsive/mobile behavior when the route or feature can be reached on iOS, Android, ERP web, or public store web.
- Avoid macOS-only assumptions in shared business logic, services, database flows, Supabase integrations, route handling, auth/OAuth, notifications, email/messaging, inventory/accounting logic, and data sync.
- Native platform code may diverge when necessary, but shared domain behavior must remain consistent across platforms.

## Verification Expectations

When a task changes UI, UX, integrations, build behavior, routing, auth, notifications, messaging, files, printing/PDFs, scanning, or platform-specific plugins:

1. Verify the macOS desktop path first when available.
2. Identify which other supported surfaces are affected: Windows, iOS, Android, ERP web, public store web.
3. Run or document the relevant cross-platform checks for those surfaces.
4. If a platform cannot be tested in the current environment, say so explicitly and keep the implementation structured so that platform can be tested cleanly later.

Do not mark a feature complete just because it works on macOS if the same code path obviously affects Windows, mobile, ERP web, or public store web.

## Native WebViews And App Zoom

The ERP uses `WindowZoomScope` to implement browser-style app zoom. The default desktop scale is currently `0.8`, so native platform views are usually rendered inside a transformed Flutter tree.

Native WebViews do **not** automatically inherit Flutter's transformed coordinate space in a trustworthy way. If a `WebViewWidget`, `InAppWebView`, WebView2 surface, or similar native platform view is placed directly inside the zoomed tree, the content can look correct while hit testing is wrong. The symptom is classic: links/buttons work at 100% zoom but click targets are offset at 80%.

Required pattern for native WebViews inside the zoomed app:

- Read `WindowZoomService.scale` on desktop.
- Wrap the native WebView in a zoom boundary like `_NativeBrowserZoomBoundary`: lay the native view out at `constraints * appScale`, then apply `Transform.scale(scale: 1 / appScale, alignment: Alignment.topLeft)` inside a clipped, top-left aligned box.
- Also sync the web content zoom to the app scale when the WebView API supports it (`pageZoom`, `textZoom`, `initialScale`, or equivalent). For simple HTML mail/content WebViews, inject a CSS/JS content scale when no native page zoom API exists.
- Do not fix this class of bug by adding click-coordinate offsets, nearby-link guessing, enlarged invisible hit targets, or JS "rescue" clicks. Those are fragile and will break again at another scale or layout.
- Verify native WebView interactions at both `100%` and the default `80%` app zoom before calling the fix complete.

Current reference implementations:

- Browser workspaces: `lib/shared/widgets/webview_module_page.dart`
- Mail reader WebView: `lib/modules/mail/widgets/email_detail_view_unified.dart`

---

# Build And Dependency Hygiene

This repo is used from multiple machines: macOS laptops/desktops and Windows laptops. Build behavior must be deterministic across those machines.

## Never Commit Installed Dependencies Or Build Caches

Do **not** commit installed/generated folders:

- `node_modules/` or `**/node_modules/`
- `.dart_tool/` or `**/.dart_tool/`
- `build/` or `**/build/`
- `Pods/` or `**/Pods/`
- Flutter/Xcode ephemeral caches such as `macos/Flutter/ephemeral/` and `ios/Flutter/ephemeral/`
- tool caches such as `.firebase/`

Commit the manifests and lockfiles instead:

- `pubspec.yaml` + `pubspec.lock`
- root `package.json` + `package-lock.json`
- `cloudflare-worker/package.json` + `cloudflare-worker/package-lock.json`
- `ios/Podfile` + `ios/Podfile.lock`
- `macos/Podfile` + `macos/Podfile.lock`

If a dependency folder is accidentally tracked, remove it from git tracking with `git rm --cached` and keep the local folder on disk. Do not delete another developer's local dependency/cache folder unless they explicitly ask for a clean rebuild.

## Pull / Build Baseline

After pulling changes on any machine:

1. Run `flutter pub get` at the repo root.
2. If working on the mobile scanner app, run `flutter pub get` in `mobile_scanner_app/`.
3. If root Node scripts are needed, run `npm ci` at the repo root.
4. If Cloudflare Worker scripts are needed, run `npm ci` in `cloudflare-worker/`.
5. For macOS/iOS native dependency changes, let Flutter run CocoaPods or run `pod install` in the relevant `macos/` or `ios/` folder.

Use lockfiles for repeatability. Do not use `npm install`, `flutter pub upgrade`, or broad package upgrades as a default fix for machine-specific build problems.

## Local Storage Hygiene And Build Cache Balance

This project is developed across multiple machines, including macOS laptops/desktops such as the MacBook Pro and Mac mini in Chile, plus a Windows laptop. Keep every machine clean enough to avoid emergency disk pressure, but do **not** routinely wipe all caches just because they are rebuildable. Many "junk" folders exist to keep Flutter, Xcode, Android, Gradle, CocoaPods, npm, and Supabase workflows fast.

The target balance is:

- Active development machines should keep enough warm caches for decent build times.
- Low-space machines should aggressively remove stale generated output and duplicate platform images.
- Cleanup must never delete source code, lockfiles, local database volumes, secrets, personal files, or another developer's local state unless explicitly requested.
- Agents should explain the first-build cost after cache cleanup: the next build may re-download dependencies, recreate Pods, rebuild Xcode DerivedData, re-pull Docker images, or cold-boot/download emulators.

### Safe Repo Cleanup Targets

These are safe to remove when disk space is low because they are regenerated from committed manifests, lockfiles, or tool state:

- root `build/` and `mobile_scanner_app/build/`
- root `.dart_tool/` and `mobile_scanner_app/.dart_tool/`
- Android Gradle intermediates such as `android/.gradle/` and `mobile_scanner_app/android/.gradle/`
- Flutter ephemeral folders such as `macos/Flutter/ephemeral/`, `ios/Flutter/ephemeral/`, and their `mobile_scanner_app/` equivalents
- local dependency installs such as root `node_modules/`, `cloudflare-worker/node_modules/`, `ios/Pods/`, `macos/Pods/`, and mobile scanner Pods when the relevant lockfiles are present

Do **not** use broad recursive cleanup such as deleting every folder named `build` anywhere under the repo. Some vendored or tracked dependency trees may legitimately contain a directory named `build`. Prefer explicit known generated paths, and check `git status --short` after cleanup. If tracked files were removed by mistake, restore only those files.

### Safe Machine-Level Cleanup Targets

On macOS, it is generally safe to clear these when space is tight, with the tradeoff that the next build may be slower:

- Xcode DerivedData: `~/Library/Developer/Xcode/DerivedData`
- old iOS DeviceSupport symbols: `~/Library/Developer/Xcode/iOS DeviceSupport`
- unavailable or erased simulator data through `xcrun simctl delete unavailable` or `xcrun simctl erase all`
- CocoaPods, Homebrew, npm, pub, pip, and Gradle caches
- editor workspace caches such as VS Code/Cursor/Antigravity `workspaceStorage`, `CachedData`, `Cache`, `Code Cache`, old logs, and crash reports
- downloaded installers in `~/Downloads` such as old `.dmg`, `.pkg`, `.zip`, and app installer files
- unused Docker images through normal prune commands

On Windows, the equivalent cleanup targets are usually:

- repo `build\`, `.dart_tool\`, `android\.gradle\`, `node_modules\`, and generated Windows build folders
- Gradle cache under `%USERPROFILE%\.gradle\caches`
- Flutter/Dart pub cache under `%LOCALAPPDATA%\Pub\Cache`
- npm cache under `%LOCALAPPDATA%\npm-cache`
- Android SDK and emulator images under `%LOCALAPPDATA%\Android\Sdk` and AVD data under `%USERPROFILE%\.android\avd`
- VS Code/Cursor workspace storage under `%APPDATA%\Code\User\workspaceStorage` or the equivalent editor profile folder
- old installers in Downloads

### Keep These For Decent Build Times

Do not wipe these routinely on active machines:

- the Android SDK platform/build-tools versions currently used by the repo
- the Android NDK version expected by Flutter's current `flutter.ndkVersion`; check the local Flutter tool before deleting duplicate NDK folders
- at least one Android emulator system image if Android emulator testing is done frequently on that machine
- the iOS simulator devices/runtimes actually used on macOS machines
- Gradle, pub, npm, CocoaPods, and Xcode caches on machines with comfortable free space
- Docker images for actively used local services when avoiding re-pulls matters

For remote or slower-network machines, especially the Mac mini in Chile, prefer keeping one warmed set of Android/iOS/Flutter caches unless free space is already becoming a problem.

### Never Delete Without Explicit Approval

These can contain important local state and must not be removed during routine cleanup:

- Supabase/Postgres Docker volumes or bind-mounted data
- Colima/Docker Desktop VM disks
- Docker volumes, especially when local databases may live there
- `.env` files, secrets, credentials, certificates, keystores, signing keys, and provisioning profiles
- user documents, photos, messages, mail, browser profiles, password stores, and app profile data
- Git history or working-tree changes
- local database dumps unless the user explicitly identifies them as disposable

Avoid `docker system prune --volumes` unless the user explicitly wants to delete local Docker volumes and understands that local database data may be lost.

### Recommended Cleanup Rhythm

- Normal day-to-day work: keep caches warm; do not run full cleans unless a build is broken or disk is low.
- When free space drops below roughly 30-50 GB: remove repo build outputs, stale editor workspace caches, old installers, and stale platform caches first.
- Monthly or before travel/remote work: clean old Android emulator images, old iOS DeviceSupport, old Xcode DerivedData, and duplicate NDK/system images, while keeping one current working set.
- After a major Flutter/Xcode/Android Studio upgrade: remove old platform versions and stale generated outputs once the new toolchain is confirmed working.

After any large cleanup, document the expected rebuild cost and run or request the minimal dependency warmup needed for the next task: `flutter pub get`, `npm ci`, `pod install`, Android SDK image download, or a first local build.

## Native Build Slowness Triage

When a build suddenly gets slower after recent commits, inspect dependency/platform changes first:

- `pubspec.yaml` / `pubspec.lock`
- `macos/Podfile.lock`
- `ios/Podfile.lock`
- `windows/flutter/generated_plugins.cmake`
- platform project files under `macos/`, `ios/`, `windows/`, and `android/`

Native plugins such as Firebase, in-app web views, ML Kit, WebView, Bluetooth, and notification plugins can make the first build after pull slower because Xcode/MSBuild/CocoaPods recompiles native code. Document this when introducing or upgrading them.

For cross-device inconsistency, compare toolchain versions before changing app code:

- `flutter --version`
- `dart --version`
- `xcodebuild -version` on macOS
- `pod --version` on macOS/iOS work
- `node --version` and `npm --version` for JS/Cloudflare work

## macOS `MallocStackLogging` Warning

The terminal warning:

```text
MallocStackLogging: can't turn off malloc stack logging because it was not enabled.
```

is a macOS allocator/debug-environment warning from the local shell/tool process. It is not, by itself, a Flutter build failure if the build already says `Built ... .app`.

When this appears:

- First confirm whether the build succeeded.
- Check local shell/Xcode environment variables such as `MallocStackLogging`, `MallocStackLoggingNoCompact`, `MallocScribble`, and `MallocGuardEdges`.
- Treat it as machine-local unless the repo explicitly sets those variables.
- Do not add repo code workarounds for this warning without evidence that it affects the app binary or causes a real build failure.

---

# 🚴 CRITICAL: BIKE WORKSHOP MASTER SCHEMA (ALWAYS UPDATE)

**Canonical living document:** `BIKE_WORKSHOP_MASTER_SCHEMA.md`

**Compatibility concepts companion:** `BIKE_WORKSHOP_COMPATIBILITY_CONCEPTS.md`

For ANY substantive work on the bike workshop architecture, agents MUST read `BIKE_WORKSHOP_MASTER_SCHEMA.md` first.

For ANY substantive work on compatibility semantics, product ficha meaning, canonical compatibility vocabularies, or the compatibility engine, agents MUST read `BIKE_WORKSHOP_COMPATIBILITY_CONCEPTS.md` immediately after the master schema and update it in the same task when the technical doctrine changes.

This includes changes to:
- bike encyclopedia / `bike_catalog`
- bike form dialog / bike creation flow
- bike creation wizard / intake wizard as the upstream data-entry layer
- `bike_profiles`
- `mechanic_job_bikes`
- diagnosis sheet templates or fields
- `mechanic_job_items` target metadata
- service wizard profiles/questions/mappings
- bike memory sync or derived kernel tables
- bike record / technical history UI

## The Backbone Starts Upstream

The bike workshop architecture does **NOT** start at diagnosis or service wizard questions.

The bike creation/edit wizard is part of the backbone.

It is the upstream intake layer that writes the first canonical bike and bike-profile truth, not a disconnected convenience UI.

It starts here:

1. `bikes.id` = durable tenant bike identity
2. bike creation/edit wizard = upstream intake UI that must populate canonical bike truth
3. `bike_profiles.catalog_bike_id` = link from that real bike to the shared encyclopedia model in `bike_catalog`
4. `bike_profiles.technical_profile.values` = confirmed technical truth for that bike
5. `mechanic_job_bikes.diagnosis_sheet_data` = visit-specific structured findings
6. `mechanic_job_items` = executed actions and target metadata
7. bike memory kernel tables = cross-visit derived outputs

**This is the non-negotiable rule:** downstream diagnosis and service UI must consume upstream bike profile truth instead of repeatedly asking for the same technical facts.

Examples:
- If bike profile already knows brake type, wizard should not ask brake type again unless explicitly confirming/correcting it.
- If the service row already knows Del./Tras., the wizard should not ask wheel/position again, and if the bike profile already resolves rotor size or rim-brake status for that target, the wizard should consume that upstream truth instead of re-asking it.
- If the bike is rim-brake, rotor thickness fields should not appear in diagnosis.
- If the bike is a known model like `Marlin 5 2025`, centralized profile data should irrigate downstream diagnosis and service flows.

This rule is universal across workshop systems, not a brake-only exception.

If a durable technical spec becomes important for products, services, diagnosis gating, or compatibility, that spec must grow through the same upstream backbone:

- shared suggestion truth in `bike_catalog` when known globally
- confirmed tenant-bike truth in `bike_profiles.technical_profile.values`
- future component-backed truth may be mixed-source: some installed parts may map to sellable `products`, while others may be OEM/reference components that are not inventory sale rows
- the same canonical compatibility key reused by products and services when matching depends on it
- downstream diagnosis and service wizard behavior that consumes that truth instead of becoming the first place where it is stored

Do not trap new durable specs in wizard-answer JSON, service-row notes, or diagnosis-only hacks.

Do not force every installed bike component into inventory just to make the bike technically representable. During the transition toward richer component-backed bikes, the current bike/profile kernel remains the active upstream bridge, and future component identity must stay open to both inventory products and non-sellable reference/OEM parts.

This applies to all systems: brakes, drivetrain, wheels, hubs, suspension, steering, tires, frame interfaces, e-bike systems, and future component families.

The v1 kernel may stay intentionally small, but when richer detail is added later, bike profile truth, product compatibility, and service taxonomy must grow together through the same backbone.

Diagnosis and service customization must follow the same backbone:
- diagnosis is the shared visit-truth layer for component state
- visit narrative may be AI-assisted, but only as an editable human-readable projection of the already-defined structured diagnosis for that visit; it must not become a parallel diagnosis truth store and it must omit undefined fields instead of narrating placeholders
- service wizards should be service-aware views over that same diagnosis target, plus a narrow set of service-execution-only fields
- service-execution-only structured answers must persist on `mechanic_job_items.service_configuration_data`; do not strand them only in row notes or transient UI state
- user-customized fields may propagate across wizards, product suggestions, bike profile promotion, or bike timeline automation only when mapped to a known semantic role from a controlled catalog
- arbitrary local custom fields must remain diagnosis-only and must not silently affect the rest of the workflow
- diagnosis-linked fields are not allowed to use vague, action-oriented, or history-oriented answer values as technical truth; answer options must describe present component state, a measured condition, or a directly observed symptom
- labels or values such as `ok`, `correcto`, `normal`, `replace`, `ya_reemplazados`, `ajustado`, or `lubricado` are not valid diagnosis truth by themselves unless a shared canonical field definition explicitly anchors their semantics
- diagnosis-linked wizard questions must reuse one centralized field-definition layer for canonical key, labels, allowed values, render type, and diagnosis-mapping policy; if a live profile only has weak or execution/history-oriented options, keep that question execution-only until the profile is normalized
- coarse wizard buckets must not silently degrade a more precise structured measurement when round-tripping between wizard answers and diagnosis truth

Service taxonomy must follow the same backbone too:
- structured services should not be modeled only as flat billable product names
- use a small top-level system taxonomy first, then component slot, then service profile / operation
- reuse the same canonical targeting vocabulary across services, diagnosis, products, and bike memory instead of inventing a second category model
- treat weak product display categories like `category_name` as presentation/catalog metadata, not as the technical source of truth for workshop workflow
- the service creation/edit form must treat `service_product_profile_mappings` as the primary workshop linkage for service rows; regular product categories may remain optional display metadata, but they must not be the main control that decides service semantics
- when a service is linked to a `service_profile`, the form should expose that backbone explicitly at creation time: profile, target family / position mode, and concise client-facing summary guidance should be visible instead of staying hidden behind opaque mappings

## Mandatory Base Kernel First

Bike workshop compatibility must be implemented in two layers:

1. a **small mandatory base kernel** that unlocks common workshop decisions immediately
2. a **larger extended detail layer** that can grow progressively over time

Do **not** try to model the full component universe in the first pass.

Do **not** create a second "simple" compatibility system beside the backbone.

The mandatory base kernel is the set of upstream facts that bike creation/edit flow should actively fill, confirm, or explicitly leave unknown:

- `bikes.bike_type`
- `bikes.wheel_size`
- `bikes.front_hub_spacing_mm`
- `bikes.rear_hub_spacing_mm`
- `bike_profiles.technical_profile.values.brakeType`
- `bike_profiles.technical_profile.values.suspensionLayout`
- `bike_profiles.technical_profile.values.drivetrainSpeeds`
- `bike_profiles.technical_profile.values.drivetrainConfig`
- `bike_profiles.technical_profile.values.freehubType`
- `bike_profiles.technical_profile.values.frontSpokeHoles`
- `bike_profiles.technical_profile.values.rearSpokeHoles`
- `bike_profiles.technical_profile.values.valveType`
- `bike_profiles.technical_profile.values.bottomBracketFamily`

At the intake/UI layer, the bike form should actively capture these profile-side keys instead of leaving them implicit in freeform notes. If only a legacy single `spokeCount` is available, treat it as a fallback compatibility hint rather than the final front/rear spoke-hole model.

At the intake/UI layer, canonical compatibility values should also be captured through the right control shape:
- rotor diameters should come from standardized values, not arbitrary text
- rotor inputs should remain hidden until `brakeType` is explicitly confirmed as a disc system
- when `brakeType = rim`, the intake should capture a standardized `rimBrakeFamily` value instead of collapsing V-Brake, Cantilever, and road caliper systems into one generic label
- special brake platforms like `roller_brake`, `drum_brake`, `coaster_brake`, and `band_brake` should stay explicit at the top brake-platform layer instead of being forced into fake rim/disc categories
- default brake service profiles and seeded `service_profile_questions` must expose compatible vocabulary for those same brake platforms and rim subtypes; otherwise the wizard becomes a lossy downstream layer even when upstream bike profile truth is correct
- diagnosis-linked wizard fields must reuse the same canonical vocabulary and labels as `mechanic_job_bikes.diagnosis_sheet_data`; brake symptom wording must not fork into a second synonym set just because a legacy service profile still exists
- when the upstream bike profile already confirms the top-level brake platform, the wizard UI should lock that platform visually and ask only for the unresolved refinement that is still missing; a legacy rim bike may still need `rimBrakeFamily`, but the mechanic should not see the entire mixed brake-platform list vomited back into the flow
- if the wizard resolves that missing `rimBrakeFamily` refinement for a bike already confirmed as `brakeType = rim`, saving the job must promote that confirmation back into `bike_profiles.technical_profile.values` so the same bike does not keep getting asked again on later brake services
- diagnosis-linked brake fields must be driven from one shared field-definition layer in code, including option labels and render style, so the bike intake, diagnosis sheet, and guided service wizard do not fork into separate local widget logic for the same centralized truth
- any bike-system map/controller used in diagnosis, bike record/history, bike profile, or future workshop UI must come from one shared code-side widget + registry; do not keep separate local pin/spec lists or duplicated bike-map implementations per screen
- the shared `BikeSystemController` now owns exploded-detail gating and hover preview state internally; parent widgets must treat `selectedSystemKey` as highlight-only, treat `onClearSelection` as notification-only, and must not lift hover/detail state out of the controller or reintroduce parent-driven `MouseRegion` rebuild loops
- if the current diagnosis template models fewer systems than the shared controller can display, keep one shared controller anyway and show explicit unavailable/placeholder inspector states for unmodeled systems instead of forking a reduced second controller
- the bike creation/edit wizard technical step should reuse that same shared controller as its upstream system navigator; unresolved systems like `cockpit` should stay explicit placeholder states there too instead of spawning a second local bike-map implementation
- when global brake service profiles drift back to legacy keys or wording, the schema seed and migration path must clean obsolete alias keys such as `position`, `includes_cable_housing`, `rotor_diameter`, `num_pistons`, or `deviation_severity` when the canonical meanings are already `which_wheel`, `rotor_size`, `piston_count`, and `damage_level`; keep real canonical brake fields like `pad_contaminated` instead of replacing them with local one-off synonyms
- `include_housing` remains a legitimate execution-only field for cable-replacement flows; do not sweep it out together with the obsolete alias `includes_cable_housing`, but do force those profiles to use the same canonical `which_wheel` targeting key as the rest of the brake family
- `drivetrainConfig` and `drivetrainSpeeds` should be derived from front-chainring count x rear-cog count when the mechanic is confirming drivetrain layout, not typed manually as free text
- `freehubType` should be treated as the rear-driver family field, not as a cassette-only label, so singlespeed/BMX/fixed cases are not forced into the wrong vocabulary
- `freehubType` must support an explicit `unknown` state in the intake UI instead of staying blank, because drivetrain compatibility and wizard routing need to distinguish “not yet confirmed” from “never reviewed”
- the bike form must not let quick-save bypass drivetrain kernel review before the technical step; when the mechanic saves early with unresolved transmission basics, route them back into the technical section instead of silently persisting another empty drivetrain profile
- wheel size, hub spacing, and spoke-hole counts should use standardized selectors where possible instead of open numeric/text entry by default

Extended detail is allowed later, but it must enrich the same backbone instead of replacing or bypassing it.

## Bike Type Must Gate Specs

`bike_type` must drive more than the illustration.

It must drive:

- which technical fields are visible
- which fields are hidden because they are impossible or irrelevant
- which defaults are prefilled
- which combinations require explicit confirmation

Examples:

- `mountain_hardtail` should suppress rear-shock-specific fields
- BMX and fixie-like bikes should default to rigid / singlespeed-style expectations and suppress front-derailleur-specific fields
- rim-brake bikes should suppress rotor-specific diagnosis fields

At minimum, the intake form should apply bike-type defaults for `suspensionLayout`, BMX-style drivetrain bias, derive `drivetrainConfig` / `drivetrainSpeeds` from front x rear drivetrain counts, and hide rotor-size inputs when `brakeType = rim`.

Do not leave bike creation as a single static technical block if the selected bike type already narrows the real compatibility space.

## Product Compatibility Must Reuse Bike Keys

The product spec engine must reuse the same canonical compatibility vocabulary as the bike profile.

Do **not** create one set of compatibility keys for bikes and a different set for products.

The coarse product-side technical-family bridge already exists and should be reused deliberately:

- `category_tech_mappings.technical_family` is the controlled coarse fallback between business categories and workshop compatibility meaning
- `spec_templates.technical_family` is the ficha-template side of that same vocabulary
- raw `products.category_name` remains weak display metadata and must not be promoted into the compatibility engine directly

Phase-one matching should focus on high-leverage workshop categories such as:

- rims
- hubs
- cassettes / freewheels
- chains
- bottom brackets
- brake pads
- rotors
- complete brake sets

Phase-one behavior should:

- hard-block only obvious base incompatibilities
- soft-warn when compatibility data is incomplete
- prefer ranked suggestions over heavy validation when the dataset is still immature
- when detailed product specs are missing, the compatibility layer may still use `category_tech_mappings.technical_family` for obvious family-level mismatches such as `rotor` on a rim-brake bike
- after that coarse gate, detailed `product_spec_values` should remain the stronger source for within-family refinement such as rotor size, thickness, material, or floating status
- ficha controls for finite workshop vocabularies must use standardized selectors or bounded numeric ranges, not arbitrary free text when the bike world already uses known counts, diameters, widths, tooth ranges, and driver families
- when one product-spec field is downstream of stronger upstream selections such as chain width, drivetrain speeds, declared profile, brand family, or freehub family, the ficha UI must filter, lock, or suppress incompatible options instead of leaving contradictory combinations available to save
- `products.brand` is commercial brand data, not technical compatibility truth by itself; if ecosystem-family matching matters, the ficha must expose a first-class visible compatibility-family field instead of hiding that logic in helper text or generic brand inference
- for drivetrain products specifically, do not keep treating one overloaded broad field as if it solved the whole hierarchy. The correct target split is: mandatory drivetrain mode branch, mandatory singular primary ecosystem anchor for modern derailleur products, optional explicit compatible-ecosystems claims, then downstream `drivetrain_platform`, `shift_actuation_family`, and `chain_profile_family` refinements
- commercial metadata is not allowed to drive runtime ficha truth: `products.brand`, `products.category_name`, product name, and description text must not autofill, hint, or silently constrain drivetrain tech-spec answers during normal product editing
- compatibility scoring is not allowed to auto-expand those broad ecosystem fields into exact HG+/Linkglide/Eagle/T-Type platform truth. Broad ecosystem claims may gate obvious mismatch or keep the result in caution territory, but exact platform matching must still come from `drivetrain_platform`, `chain_profile_family`, or other true downstream structured fields
- the same guard applies to dirty legacy values stored in the wrong field: if `drivetrain_platform` contains only a broad brand/ecosystem claim such as `Shimano`, `SRAM`, `Ecosistema Shimano`, or `Compatible SRAM`, the app must refuse to reinterpret that as exact HG/SIS, Eagle, or other downstream platform truth at runtime
- the same guard applies to `shift_actuation_family`: this field is a refinement-level indexing / cable-pull signal, not the primary ecosystem anchor. Broad values such as `Shimano` or `SRAM` stranded there must not be promoted into ecosystem truth unless the value actually carries actuation semantics like SIS, Dynasys, Linkglide/CUES, Exact Actuation, X-Actuation, AXS, or equivalent real refinement detail
- drivetrain compatibility scoring must also stay conservative for derailleurs, shifters, and drivetrain kits after a nominal match. Rear derailleurs are not fully compatible from speed alone; actuation family, max-cog support, cage / total-capacity expectations, and mounting still matter. Front derailleurs are not fully compatible from `2x` / `3x` count alone; mount style, pull direction, big-ring size/cage curvature, and road-vs-MTB front indexing still matter. Shifters should only move to full-compatible when the relevant side and exact indexing/actuation seam are actually resolved in structured data. Drivetrain kits should not move to full-compatible from front-side crankset/pedalier facts alone when the rear-side content of the kit is still unresolved; otherwise keep the result in caution territory.
- cassette / freewheel scoring must also stay conservative after a nominal speed and freehub match. Threaded freewheel vs cassette body remains a hard split, but even when speed and driver family line up the scorer should usually remain in caution territory until the structured range/body-generation/spacer seam is actually resolved, because real hub-body exceptions still exist.
- cassette / freewheel ficha UI must follow the same rule upstream: `freehub_type` cannot remain implicit, freewheel templates must keep that field as an explicit ficha confirmation instead of auto-deriving it from category/template semantics, and rear-cog templates should expose range fields like `largest_cog_teeth` so the app does not keep speaking as if speed were the only meaningful seam.
- rear-cog templates (`cassette`, `freewheel`, `fixed_cog`) must not surface `drivetrain_primary_ecosystem`, `drivetrain_declared_compatible_ecosystems`, or `drivetrain_platform` in the runtime ficha flow; those broad semantics are not the real rear-cog seams compared with mount/body family, speeds, and range
- `chainring` and `crankset` templates must not surface broad ecosystem-anchor fields in the runtime ficha flow; use teeth, mount, chainline, bottom-bracket interface, and exact downstream profile/platform truth instead of a coarse Shimano/SRAM-style anchor.
- `chain_guide` templates must not surface broad ecosystem-anchor fields or `drivetrain_platform` in the runtime ficha flow; their real seams are mount standard, supported chainring teeth, and chainline.
- `shifter` runtime ficha flow must gate front-vs-rear semantics by `shifter_position`: left/front shifters suppress rear-side seams such as `drivetrain_speeds`, `rear_cog_count`, `shift_actuation_family`, and `drivetrain_platform`, while right/rear shifters suppress front-chainring-count fields; only pair/universal cases may keep both sides visible.
- shifter scoring must treat `universal` the same as `pair`: keep both structured sides visible when present, but leave pair/universal in `caution` until the front pull/indexing seam is modeled explicitly. Only exact right/rear matches may reach `compatible`.
- `front_derailleur` runtime ficha flow must constrain `front_chainring_count` to real multi-ring systems only; `1x` is not a valid front-derailleur ficha state and must not remain available as if a front derailleur applied there.
- `front_derailleur` runtime ficha flow must also suppress 1x-only ecosystem/platform claims such as `Single speed / BMX`, `SRAM Eagle`, or `SRAM T-Type Transmission`; those claims do not belong on a multi-ring front-derailleur ficha.
- `front_derailleur` runtime ficha flow must gate clamp diameter by mount style: `front_derailleur_clamp_mm` is only valid for clamp-mount units and must stay hidden for `braze-on`, `direct mount`, or `E-type` entries.
- cassette-spacer ficha UI must follow the same rear-body rule: keep `freehub_type` explicit, restrict it to cassette-body families instead of freewheel/fixed mounts, and keep `spacer_thickness_mm` as explicit measured data because these parts solve body-length/generation exceptions, not a vague universal compatibility claim.
- rear-hub and rear-cog vocabulary must also preserve the finer cassette-body families when they matter: `Shimano HG`, `Shimano HG Road 11`, `Micro Spline`, `SRAM XD`, `SRAM XDR`, `Campagnolo`, and `Campagnolo N3W` are not interchangeable labels and must not collapse back into one coarse freehub bucket in ficha UI, helper text, or scorer wording.
- generic hub ficha UI must also gate by wheel position upstream: front hubs should suppress rear-only `freehub_type`, and `hub_spacing_mm` should use standardized front/rear OLD choices instead of one mixed field that silently blends front and rear spacing vocabularies.
- width-family (`chain_width_family`) is a coarse physical constraint and remains top-level only for true single-speed / BMX / derailerless chains; it must not stay above speed and platform truth for modern derailleur chains
- for chain products specifically, `chain_outer_width_mm` is the bounded numeric refinement below `chain_width_family`; do not keep auto-speaking as if `11/128` by itself means universal `9-11v`, and do not leave this as free text because real narrow-chain compatibility depends on the actual external body width
- for chain-family ficha UI, `drivetrain_mode` remains part of the semantic model but should stay implicit when stronger chain signals already prove the branch; do not re-show it as a locked pseudo-manual field when width, speeds, platform, or anchored profile already fix `single_speed_bmx_igh` vs `derailleur`
- helper text is not allowed to speak as if a compatibility-family answer already exists when the ficha cannot actually display, edit, and persist that answer as a first-class field
- if the UI can show a suggestion such as "desde marca" or "familia detectada", that same concept must already be representable as a persisted first-class field somewhere in the backbone; otherwise the helper is outrunning the schema and the implementation is drifting

## Maintenance Protocol

Whenever bike workshop implementation changes in a way that affects architecture, data flow, schema, UI gating, or sync behavior:

1. Update `BIKE_WORKSHOP_MASTER_SCHEMA.md` in the same task.
2. Update `BIKE_WORKSHOP_COMPATIBILITY_CONCEPTS.md` in the same task when the change affects compatibility semantics, ficha meaning, or scorer doctrine.
3. Update this section in `copilot-instructions.md` if the architectural rules or priorities changed.
4. Document whether the change strengthens or weakens centralization around bike profile truth.

## Master Schema Order Is Mandatory

`BIKE_WORKSHOP_MASTER_SCHEMA.md` is not just a reference doc.

It is the primary ordered ledger for bike workshop work: what already landed, what is still open, what is intentionally deferred, and what the next queue is.

For any substantive bike workshop continuation:

1. Read `BIKE_WORKSHOP_MASTER_SCHEMA.md` first and treat its queue as the default ordered worklist.
2. Reconcile the current task against that queue before proposing or continuing a next step.
3. Update the master schema in the same task so it records the new current reality and the reordered next queue.
4. If this file's continuity snapshot or immediate queue drifts from the master schema, the master schema wins and this file must be updated in the same task.

Do not continue from memory alone, and do not jump to a new compatibility-population step just because one local slice improved if the master schema still shows unresolved upstream/scoring seams.

## Whole-Backbone Inspection Rule

Any substantive change to one bike-workshop layer must trigger an inspection of the rest of the backbone in the same task.

Do not patch diagnosis, profile, wizard, catalog, item targeting, or bike-memory sync in isolation and then discover later that the other layers cannot represent the same concept.

For any changed concept, inspect at minimum:

1. `bike_catalog` / encyclopedia support for the concept.
2. `bike_profiles.technical_profile.values` as durable upstream bike truth.
3. `mechanic_job_bikes.diagnosis_sheet_data` as visit-specific structured truth.
4. `service_profiles`, `service_profile_questions`, and wizard mappings for matching question/answer vocabulary.
5. `service_product_profile_mappings` / `mechanic_job_items` so executed work targets the same system/component semantics.
6. bike-memory sync + read models if the concept should survive across visits.

If a diagnosis/service/profile/catalog change is made without checking the rest of that chain, the task is incomplete.

Concrete example:
- if hydraulic-brake purge semantics are added to diagnosis, inspect whether catalog truth, bike profile truth, wizard questions/options, service mappings/items, and bike-memory projection are all wired to the same centralized hydraulic-brake semantics.

If code changes in this area are shipped without updating the master schema and these instructions, the task is incomplete.

## Mandatory Verification Before Changes

Before editing bike workshop architecture, agents must verify the current real system state using the already-documented access methods in this file:

- service-role REST inspection
- direct `psql` inspection when exact SQL is needed

When the task touches bike technical data modeling, workshop compatibility semantics, ficha value vocabularies, or the compatibility engine, agents must also do external technical research before implementing:

- inspect the relevant Sheldon Brown pages
- inspect the relevant Park Tool pages
- use browser tools to study the real page context, diagrams, tables, and edge-case wording instead of relying on memory or guessed bike-tech assumptions

This external research step is mandatory for changes such as:

- new or changed bike technical fields
- new compatibility keys or option vocabularies
- drivetrain / brake / wheel / hub / bottom-bracket compatibility logic
- ficha dropdown/range decisions where workshop standards matter

This does not replace live production inspection. The rule is: inspect live data first and inspect trusted external workshop references too, then reconcile both before deciding the implementation.

At minimum, inspect the live shape of the relevant records for the target tenant before making architecture decisions, especially:

- `bike_profiles`
- `mechanic_job_bikes`
- `mechanic_job_items`
- `service_profiles`
- `service_product_profile_mappings`
- `service_profile_questions`

This rule exists because live production mappings have already differed from assumptions in code.

## Anti-Redundancy Rule

Agents must not create redundant bike workshop structures without first proving the current layers are insufficient.

This is a safeguard against drift, not a ban on progressive improvement.

If an improvement really requires extending or evolving the current architecture, the agent should do it explicitly and update both `BIKE_WORKSHOP_MASTER_SCHEMA.md` and this section in the same task.

Specifically, do NOT create:

- a parallel bike truth store outside `bike_profiles`
- a parallel diagnosis store outside `mechanic_job_bikes.diagnosis_sheet_data`
- new targeting fields when `system_key`, `component_slot_key`, and `location_key` already cover the case
- new cross-visit summary/history tables when the bike memory kernel already models the problem
- wizard-based technical truth that bypasses upstream bike profile truth

Search first in the schema and existing workshop files before adding anything new.

Preferred rule: improve the backbone deliberately, do not build a second backbone beside it.

## Fresh-Agent Continuity Snapshot (2026-04-28)

For a fresh chat, the current code-side state is:

- that same bike intake dialog now also owns the richer pedalier kernel upstream: `bottomBracketFamily`, `bbShellWidthMm`, `bbShellDiameterMm`, and `spindleInterface` are captured through one shared canonical helper in `lib/modules/bikeshop/config/bottom_bracket_canonical_data.dart`, and the dialog only exposes shell-diameter input for the families that actually use bore diameter.
- `lib/modules/bikeshop/models/bikeshop_models.dart` and `lib/modules/bikeshop/widgets/bike_record_panel.dart` now surface that richer bottom-bracket truth back out through the bike profile summary and the technical record panel instead of collapsing pedalier visibility back to family-only copy.
- `lib/modules/bikeshop/widgets/bike_system_controller.dart` is now a backbone widget, not a local screen helper. It is the shared bike-system controller for mechanic-job diagnosis, bike record/history, and the bike record technical read model.
- the current shared controller registry is `cockpit`, `suspension`, `front_brake`, `front_wheel`, `drivetrain`, `bottom_bracket`, `rear_wheel`, and `rear_brake`.
- `front_wheel` and `rear_wheel` are now the primary interactive wheel units; legacy aggregate `wheels` survives only as a family/history compatibility alias and should not keep driving new UI or targeting decisions.
- `bottom_bracket` is now a dedicated shared-controller system so pedalier bearings are not buried inside drivetrain copy.
- `cockpit` now explicitly covers steering/headset semantics even though that system still lacks a dedicated structured editor.
- `lib/modules/bikeshop/pages/mechanic_job_form_page.dart` now exposes structured editable diagnosis inspectors for every shared-controller system except the legacy aggregate alias `wheels`: `drivetrain`, `front_brake`, `rear_brake`, `front_wheel`, `rear_wheel`, `bottom_bracket`, `cockpit`, and `suspension` all round-trip through `MechanicJobDiagnosisSheet`, the diagnosis summary/narrative layer now consumes those same structured sheets instead of dropping them back to placeholder cards, and save/edit flows now normalize each system's `overallStatus` from the structured component fields so restored editors do not persist as `unknown` by default after real findings are entered.
- `lib/modules/bikeshop/widgets/bike_record_panel.dart` now uses a bike-first split shell like the intake wizard: keep the bike persistently visible in the left preview pane, and do not regress to the old top-cover / tabs-below shell.
- `lib/modules/bikeshop/widgets/bike_record_panel.dart` now uses the same shared controller both in the history workbench and in the technical specs tab's upstream kernel read model, with those maps anchored in the left preview pane; do not fork a second bike map for record visibility.
- `lib/modules/bikeshop/pages/bike_form_dialog.dart` now uses the same shared controller as the upstream technical-step navigator, with system-by-system profile panels and explicit placeholder handling for unmodeled intake systems such as `cockpit`.
- brake canonical alias normalization now lives in `lib/modules/bikeshop/config/brake_canonical_data.dart` and `lib/modules/bikeshop/services/service_wizard_service.dart`, not in ad hoc page-local branches.
- live brake validation on 2026-04-27 against production `service_profiles`, `service_profile_questions`, `service_product_profile_mappings`, and recent `mechanic_job_bikes.diagnosis_sheet_data` confirmed that the brake prototype is directionally correct but that some live wizard rows still emit legacy brake-type value spellings such as `disco_mec` and `v-brake`.
- the shared brake canonical layer now normalizes those legacy live spellings back into the backbone brake vocabulary before wizard rendering, answer persistence, and summary/diagnosis mapping, so the app layer no longer depends on the database rows already being clean.
- `supabase/sql/core_schema.sql` now also seeds canonical `brake_type_mech` values for `brake_cable_replace_adjust`, and `supabase/migrations/20260427235900_normalize_brake_type_mech_options.sql` has already been applied to production so the live row no longer emits `disco_mec` / `v-brake`.
- global drivetrain service profiles `chain_lube` and `derailleur_adjustment` now have explicit `service_profile_targets` rows with `target_family = drivetrain` and `target_position_mode = none`; do not reintroduce fake front/rear targeting for drivetrain-level services.
- `lib/modules/bikeshop/services/service_wizard_service.dart` now loads `service_profile_targets` with a tenant-specific-or-global fallback, because live workshop profiles such as drivetrain, wheels, cockpit, and bottom-bracket currently store those target rows globally (`tenant_id = null`) in production.
- `lib/modules/bikeshop/pages/mechanic_job_form_page.dart` now consumes that target metadata when hydrating service rows so `target_position_mode = none` workflows like drivetrain, headset/cockpit, and bottom-bracket stay pinned to `location = none` instead of exposing fake front/rear row targeting in the job editor.
- first-wave Viñabike drivetrain mappings now exist for `Regulación de Cambios`, `Reemplazo de fundas y piolas + regulación de cambios`, `Mantención de Cambio`, `Limpieza/Cepillado de Cadena`, and `Limpieza sistema transmisión`; upstream drivetrain wizard reuse is now live for those services, drivetrain kernel questions now prefill/hide only from confirmed bike-profile truth, and `derailleurs` no longer auto-collapses from weak upstream profile values while `service_wizard_dialog.dart` still handles the narrow rear-only `front_chainring_count = 1` case inside the wizard.
- drivetrain diagnosis-linked wizard answers `chain_wear` and `cable_condition` now round-trip with the structured diagnosis sheet: `chain_wear` prefills from and writes back to `DrivetrainDiagnosisSheet.chainWearPercent`, while `cable_condition` is stored explicitly as `DrivetrainDiagnosisSheet.cableCondition` inside the shifter slice instead of being left in guided-note text.
- the first shared diagnosis-field definition layer now exists in `lib/modules/bikeshop/config/diagnosis_field_definitions.dart`, and `mechanic_job_form_page.dart` only marks wizard questions as diagnosis-linked when their normalized key, question type, and option set match that registry.
- drivetrain diagnosis-linked normalization now also lives in `lib/modules/bikeshop/config/drivetrain_canonical_data.dart` plus `lib/modules/bikeshop/services/service_wizard_service.dart`, so `cable_condition` uses anchored present-state labels in the app layer instead of inheriting weak service-history wording from live profile rows.
- `supabase/sql/core_schema.sql` now also seeds canonical `derailleur_adjustment.cable_condition` options, and `supabase/migrations/20260427235930_normalize_drivetrain_cable_condition_options.sql` has already been applied to production so that live row no longer emits `Ya reemplazados` / `Deshilachados - reemplazar` wording.
- the global `derailleur_adjustment` profile now also exposes `front_chainring_count`, `rear_cog_count`, and `freehub_type` as the upstream drivetrain-kernel review seam; when those answers are captured for a bike with missing drivetrain truth, `mechanic_job_form_page.dart` promotes canonical `drivetrainConfig`, `drivetrainSpeeds`, and `freehubType` back into `bike_profiles.technical_profile.values` on job save.
- live production inspection on 2026-04-27 confirmed that Viñabike still has `0` historical `mechanic_job_items.service_configuration_data` rows, so there is no safe historical drivetrain backfill to run yet; do not invent one until real structured service rows exist.
- `lib/modules/bikeshop/pages/mechanic_job_form_page.dart` now also creates a base `bike_profile` on demand during service-wizard promotion when the selected bike has none yet, so explicit drivetrain/brake/bottom-bracket confirmations from real service flows are no longer blocked on pre-existing profile rows.
- `lib/modules/bikeshop/pages/pegas_table_page.dart` now hides the `Tests` filter/tab from non-debug sessions and exposes a debug-only `Prueba rápida` launcher that creates explicit DB-backed workshop fixtures for compatibility/backbone validation. Built-in scenarios currently cover a fresh `drivetrain_no_profile` bike plus reusable `rim_brake_city`, `hydraulic_disc_mtb`, `pressfit_trail_dub`, and `bmx_single_speed` bikes across `intake`, `diagnostic`, `in_progress`, `completed`, and `delivered` stages; use that harness instead of ad hoc manual setup when validating compatibility/backbone changes.
- `derailleurs` remains a service-execution field rather than the primary upstream drivetrain truth source; keep its suppression conservative and do not infer exact drivetrain layout from it when the explicit kernel questions are absent, except for the narrow wizard-local case where `front_chainring_count = 1` already proves a rear-only derailleur layout and the redundant `derailleurs` prompt should collapse automatically.
- `mechanic_job_items.service_configuration_data` now persists structured service wizard answers for executed service rows; `notes` remains the editable human-readable summary, while diagnosis-linked truths still round-trip through `mechanic_job_bikes.diagnosis_sheet_data`.
- `lib/modules/bikeshop/widgets/service_wizard_dialog.dart` now treats regular `single_select` questions as compact dropdown fields and `multi_select` questions as picker fields; do not reintroduce chip walls for ordinary wizard answer sets. Keep pill-style controls only for small binary toggles such as yes/no when the UI remains compact and obvious.
- the same dialog now blocks confirm when required wizard questions are still empty and shows inline field-level errors instead of silently saving rows with red-asterisk fields unanswered.
- `lib/modules/bikeshop/pages/mechanic_job_form_page.dart` now stages missing rim-brake-family confirmations from brake service wizards into the selected bike profile immediately in local state and promotes them into `bike_profiles.technical_profile.values` through `BikeshopService.upsertBikeProfile()` when the job is saved, so later brake services stop re-asking the same refinement.
- the same mechanic-job wizard flow now also treats the richer bottom-bracket kernel as upstream truth for bottom-bracket services: when the bike profile already confirms `bottomBracketFamily`, `bbShellWidthMm`, `bbShellDiameterMm`, or `spindleInterface`, the wizard consumes and hides those seams; when the mechanic confirms them during `Ajuste de motor` / `Mantención de Motor`, the answers are promoted back into `bike_profiles.technical_profile.values` on save instead of staying trapped in service notes.
- `lib/modules/bikeshop/pages/bike_form_dialog.dart` now treats `freehubType` as an explicit review field with an `unknown` option, applies the safe BMX `bmx_driver` default upstream, defaults new bikes to `mountain_hardtail`, and still allows `Guardar rápido` to create the bike from the minimum upstream identity set (bike type, brand, model) before the technical kernel has been reviewed.
- `lib/modules/inventory/pages/product_form_page.dart` now gives `ProductType.service` a profile-first workflow form: regular product categories are suppressed, service codes can be generated as `SRV-<family>-<operation>-NNN`, and saving the form updates `service_product_profile_mappings` so the service catalog irrigates the workshop backbone directly instead of behaving like an almost-normal stock product.
- `supabase/sql/core_schema.sql` now seeds the missing global `service_profile_targets` row for `wheel_truing`, and `DEPLOY_VINABIKE_WHEEL_TRUING_MAPPING.sql` maps only the clearly matching service `Centrado de rueda (C/U)` to that profile; keep `Centrado Express` and `Enrayado + Centrado` intentionally unmapped until their distinct wheel profiles exist.
- `supabase/sql/core_schema.sql` now also seeds the next wheel/steering service workflow profiles `wheel_build_and_true`, `hub_service`, `tube_replacement`, `tubeless_conversion`, and `headset_service`, with `wheels` / `cockpit` target families aligned to the shared controller backbone.
- `DEPLOY_VINABIKE_WHEEL_HUB_HEADSET_MAPPINGS.sql` maps the clearly matching Viñabike services `Enrayado + Centrado`, `Servicio de Mazas (C/U)`, `Mantención Maza`, `Cambio de cámara (no incluye cámara)`, `Tubeless Viñabike`, `Tubeless Bettabikes`, and `Mantención De Dirección`; keep `Ajuste de dirección` and `Instalación Juego de Dirección` intentionally deferred until the dedicated `headset_adjustment` / `headset_install` profiles exist.
- `supabase/sql/core_schema.sql` now also seeds the bottom-bracket workflow profiles `bottom_bracket_adjustment` and `bottom_bracket_service`, both targeted to `bottom_bracket` with canonical `bottom_bracket_family`, `bb_shell_width_mm`, `bb_shell_diameter_mm`, and `spindle_interface` question values aligned to the bike intake vocabulary.
- `DEPLOY_VINABIKE_BOTTOM_BRACKET_WORKFLOW.sql` maps the live Viñabike services `Ajuste de motor`, `Limpieza y engrase de caja de motor`, and `Mantención De Motor`, and bridges the stocked `Motor`, `Ejes de motor`, and `Rodamientos Motor` categories into `category_tech_mappings.technical_family = bottom_bracket` so the existing compatibility scorer can finally rank pedalier stock against upstream bike truth.
- live audit on 2026-04-20 also confirmed that the coarse product-side technical-family bridge was still effectively brake-only in production; stocked wheel/headset categories had no active `category_tech_mappings` coverage yet despite meaningful populations in `Maza`, `Mazas`, `Llantas`, `Rayos`, `Cámaras`, `Juego de dirección`, and `Rodamientos`.
- `DEPLOY_VINABIKE_WHEEL_CATEGORY_TECH_FAMILIES.sql` is now live for those unambiguous wheel/headset categories (`hub`, `rim`, `spoke`, `tube`, `rim_strip`, `tubeless_valve`, `tubeless_consumable`, `headset`, `bearing`) while mixed buckets like `Tubeless` / `Tripas Tubeless` remain intentionally deferred for a later template split.
- `supabase/sql/core_schema.sql` now also seeds the first real wheel/headset product ficha layer with system `spec_definitions`, `spec_templates`, and `spec_template_fields` for `hub`, `rim`, `spoke`, `tube`, `rim_strip`, `tubeless_valve`, `tubeless_consumable`, `headset`, and `bearing`, aligned to the current bike kernel fields such as `wheel_size`, `hub_spacing_mm`, `spoke_holes`, `freehub_type`, and `valve_type`.
- `DEPLOY_VINABIKE_WHEEL_SPEC_TEMPLATES.sql` is now live and attaches those system templates to the existing Viñabike category bridge, so the product form no longer treats those wheel/headset categories as ficha-less rows.
- the `rim` template has already been expanded beyond the first thin bridge layer: the ficha now exposes workshop-useful rim detail fields such as `rim_tubeless_ready`, internal/external width, ETRTO text, ERD, material, eyelet type, wall construction, symmetry, and asymmetric offset. Do not collapse rim ficha back to just wheel size + holes + valve.
- `DEPLOY_VINABIKE_SAFE_WHEEL_PRODUCT_SPECS.sql` is live as the first conservative product-value seed for this slice. It writes only explicit truths present in product names and should stay that way until richer product data sources exist; do not bulk-guess missing widths, ERD, eyelet subtypes, or other fine rim measurements from category alone.
- chain-related drivetrain ficha in `lib/modules/inventory/pages/product_form_page.dart` is now inference-aware: `lib/modules/inventory/services/spec_engine_service.dart` passes through `spec_template_fields.helper_text`, and shared helpers in `lib/modules/bikeshop/config/drivetrain_canonical_data.dart` can auto-fill missing `chain_speeds`, suggest `chain_profile_family`, and infer `drivetrain_platform` for `chain` / `chain_link` templates only from structured width-family, speed, platform, profile, and indexing signals. Manual edits still win, stale auto-derived values are cleared when the template/category changes, and commercial brand/category/name metadata is no longer allowed into that runtime inference path.
- the same chain ficha layer now also needs `chain_outer_width_mm` as the precision seam below `chain_width_family`: internal width alone is too coarse for modern derailleur chains, so inference and compatibility must use standardized outer-width values before collapsing a narrow chain into a broad `9-11v` claim.
- do not add live Dart-side parsing of product name or description to auto-fill drivetrain ficha truth. If packaging text later needs to backfill chain/drivetrain specs, do it as an explicit DB fulfillment or migration workflow, not as runtime UI logic.
- production drivetrain ficha now uses the explicit ecosystem split through `drivetrain_primary_ecosystem` and `drivetrain_declared_compatible_ecosystems`, and the product form treats commercial brand only as a suggestion source for the explicit split fields. The legacy `drivetrain_compatibility_family` field was removed from the active production schema on 2026-04-27 after a zero-usage audit; runtime code may still tolerate it as historical migration input, but it is no longer an active ficha field.
- live verification on 2026-04-27 confirmed two things at once: the safe structured-only backfill inserted `0` product rows in production, and the live catalog still declares speed first, width sometimes, and platform/compatibility claims only occasionally in product names. The next schema/UI step is therefore to populate and consume the explicit ecosystem split more reliably from real packaging evidence, instead of reviving or densifying the legacy interim field.
- that 2026-04-27 verification is **not** a green light for broad compatibility population yet. Population remains intentionally blocked while shifter and bottom-bracket/crankset seams stay incomplete.
- current shifter compatibility is still intentionally conservative: exact right/rear matches can rank `compatible`, but left/front and pair/universal cases must remain in `caution` until the front pull/indexing seam is modeled and tested better.
- the detailed shifter scorer now also routes `shifter_position = universal` through the same conservative two-sided path as `pair`, so live/seeded schema options no longer skip the speed/front-count checks while broad population remains blocked.
- the detailed bottom-bracket and crankset scorer now also stays conservative on nominal matches: matching family/shell/spindle or front-count facts no longer upgrades those families to `compatible`, because chainline, mounting, crank-length, and exact shell/adapter semantics are still incomplete.
- bottom-bracket ficha behavior now also gates from `bottom_bracket_family`: pressfit/BB30 families hide `bb_thread_standard` but keep `bb_shell_diameter_mm` visible as the bore seam, threaded/external-cup families suppress that raw shell-diameter field, square-cartridge families narrow `spindle_interface` to JIS/ISO, and `Hollowtech / 24mm externo` locks the interface and hides loose spindle-length/diameter fields so the product form stops allowing obviously contradictory cartridge-style combinations.
- current bottom-bracket and crankset compatibility is also intentionally incomplete: family/shell/interface seams exist, but chainline, mounting, crank-length, and related crankset-standard seams are not finished enough for broad catalog population.
- `lib/modules/bikeshop/services/bike_product_compatibility_service.dart` now provides the brake-first product compatibility scorer, `lib/shared/widgets/product_autocomplete_field.dart` can surface optional compatibility ranking/badges when a caller provides bike context, and `lib/shared/widgets/smart_product_field.dart` now forwards that context so the mechanic-job line editor no longer bypasses the same compatibility-aware search path.
- `lib/modules/bikeshop/widgets/tasks_tab_view.dart` now also resolves the current job's primary bike/profile and forwards that same compatibility context into its legacy add/edit catalog dialogs, so the older detail/calendar task surfaces do not keep bypassing the current bike-aware ranking path.
- the same scorer now also emits first-wave coarse family hints for the newly bridged wheel/headset families (`hub`, `rim`, `spoke`, `tube`, `rim_strip`, `tubeless_valve`, `tubeless_consumable`, `headset`, `bearing`, `bottom_bracket`), and when a product actually has the new wheel ficha rows it now upgrades to detailed spec-driven checks for `hub`, `rim`, `tube`, `rim_strip`, and `tubeless_valve`. `headset`, `bearing`, and `tubeless_consumable` remain advisory until upstream bike/profile truth grows beyond the current kernel.
- live inspection on 2026-04-20 confirmed that Viñabike production already uses the coarse technical-family bridge through `category_tech_mappings` + `spec_templates`: mapped brake product populations include `Pastillas` (`brake_pad`), `Calipers` (`brake_caliper`), `Manillas` (`brake_lever`), `Herraduras` (`rim_brake`), `Rotores` / `Rotor BMX` (`rotor`), and `Frenos hidráulicos completos` (`hydraulic_disc_brake` via template key).
- the current brake-first compatibility scorer now consumes that controlled bridge as the coarse fallback before detailed `product_spec_values`, so obvious family-level mismatches no longer depend entirely on ficha coverage; detailed specs still remain the stronger within-family refinement layer.
- a first live rotor-spec enrichment pass on 2026-04-18 seeded canonical rotor fields on explicit 160/180/203 mm rotor rows in Viñabike production, improving brake-spec coverage but not replacing the need for the coarse technical-family fallback.

Before continuing this implementation in a fresh chat, also read:

- `lib/modules/bikeshop/pages/pegas_table_page.dart`
- `lib/modules/bikeshop/widgets/bike_system_controller.dart`
- `lib/modules/bikeshop/config/brake_canonical_data.dart`
- `/memories/repo/bike-workshop-component-intelligence-correction.md`
- `/memories/repo/bike-workshop-memory-reconciliation.md`
- `/memories/repo/bike-workshop-service-taxonomy-audit.md`
- `/memories/repo/bike-workshop-service-wizard-profile-gating.md`
- `/memories/repo/bike-workshop-fresh-agent-handoff-2026-04-16.md`

Immediate next queue:

Validation rule for every queue item below: use the debug-only `Prueba rápida` harness in `lib/modules/bikeshop/pages/pegas_table_page.dart` and extend it if the nearest built-in scenario is insufficient.

1. Improve upstream `bike_profiles.technical_profile.values` coverage for drivetrain (`drivetrainConfig`, `drivetrainSpeeds`, `freehubType`) only through real service/profile flows, with caution around the `derailleurs` multi-select template behavior. Historical backfill stays blocked until live structured `service_configuration_data` rows exist.
2. Finish the next bottom-bracket / crankset seam before population: the bike form/read model/debug harness and bottom-bracket service flows now cover `bottomBracketFamily`, shell width, shell diameter, and spindle interface, but the broader chainline, mounting, crank-length, and exact shell/adapter seams still need tighter doctrine and scorer behavior.
3. Do not start broad compatibility population yet. Only after those bottom-bracket/crankset seams are tighter should the catalog move into cautious packaging-backed population of explicit compatibility fields.

---

# 🗄️ SUPABASE PROJECT CONFIGURATION

**⚠️ NEVER GUESS THESE VALUES - THEY ARE DOCUMENTED HERE!**

## Project Details

| Field | Value |
|-------|-------|
| **Project URL** | `https://xzdvtzdqjeyqxnkqprtf.supabase.co` |
| **Project ID** | `xzdvtzdqjeyqxnkqprtf` |
| **Region** | AWS US West 1 |
| **Database Host** | `aws-0-us-west-1.pooler.supabase.com` |
| **Database Port** | `6543` (pooler) / `5432` (direct) |

## Connection Strings

**Pooler Connection (recommended for most operations):**
```
postgresql://postgres.xzdvtzdqjeyqxnkqprtf:[PASSWORD]@aws-0-us-west-1.pooler.supabase.com:6543/postgres
```

**Direct Connection (for migrations/schema changes):**
```
postgresql://postgres:[PASSWORD]@db.xzdvtzdqjeyqxnkqprtf.supabase.co:5432/postgres
```

## 🚀 Correct Use of Supabase CLI (CRITICAL FOR AGENTS)

When interacting with the Supabase project using the terminal, NEVER guess or invent commands. Always use the explicit `--project-ref` flag pointing to our project `xzdvtzdqjeyqxnkqprtf`.

**1. Managing Secrets for Edge Functions:**
To set secrets that Edge Functions will read via `Deno.env.get()`:
```bash
# Correct syntax for setting multiple secrets:
supabase secrets set --project-ref xzdvtzdqjeyqxnkqprtf KEY_NAME="value" ANOTHER_KEY="value2"

# To list current secrets constraints:
supabase secrets list --project-ref xzdvtzdqjeyqxnkqprtf
```

**2. Deploying Edge Functions:**
```bash
# Correct syntax to deploy a single edge function:
supabase functions deploy my-function-name --project-ref xzdvtzdqjeyqxnkqprtf

# If the function handles its own auth (like webhooks), use --no-verify-jwt:
supabase functions deploy whatsapp-webhook --project-ref xzdvtzdqjeyqxnkqprtf --no-verify-jwt
```
**⚠️ ALWAYS set `--project-ref xzdvtzdqjeyqxnkqprtf` or the command will fail or deploy to the wrong place.**

## Important Tenant IDs

| Tenant | UUID | Description |
|--------|------|-------------|
| **Viñabike (Production)** | `5443b130-cc28-45af-a420-cd500b288890` | Primary business account, used for testing and production |

## Viñabike Business Info (for SEO/index.html)

| Field | Value |
|-------|-------|
| **Business Name** | Vinabike |
| **Address** | Álvarez 32, Local 17, Viña del Mar, Chile |
| **Phone** | +56998357797 |
| **Email** | vinabikechile@gmail.com |
| **Website** | https://vinabike.cl |

**⚠️ NEVER use placeholder data (like "contacto", "XXXX", "test") in index.html SEO content!**

## Storage Buckets

- `products` - Product images
- `website` - Website builder assets (blocks, logos, banners)
- `documents` - Business documents (invoices, reports)

## API Endpoints

- **REST API:** `https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/`
- **Auth API:** `https://xzdvtzdqjeyqxnkqprtf.supabase.co/auth/v1/`
- **Storage API:** `https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/`
- **Realtime:** `wss://xzdvtzdqjeyqxnkqprtf.supabase.co/realtime/v1/`

## When Running Database Queries

**⚠️ IMPORTANT: Use the right tool for the query type. Do not confuse disabled migrations with disabled SQL access.**

This repo intentionally has `[db.migrations].enabled = false` in `supabase/config.toml`, so `supabase db push` can report "Skipping migrations because it is disabled". That only means the migration pipeline is disabled. It does **not** mean agents cannot run standalone SQL.

### Standalone SQL / Arbitrary SQL Against Production

Use `supabase db query --linked` for standalone SQL files, DDL, function replacement, cleanup SQL, and verification queries against the linked production project.

```bash
# ✅ Deploy a standalone SQL file to the linked Supabase project
supabase db query --linked --file supabase/migrations/YYYYMMDD_name.sql --output table

# ✅ Run one verification query
supabase db query --linked --output table "select now();"
```

Rules for agents:

- Run linked DB queries **sequentially**, never in parallel. Parallel `supabase db query --linked` calls can trigger Supabase temp-login auth failures or circuit breaker throttling.
- If a linked query hits temp login throttling, stop starting new linked queries and wait before retrying.
- Do not treat `supabase db push` skipping migrations as a blocker. Use `supabase db query --linked --file ...` for standalone deployment SQL.
- Keep standalone SQL files idempotent and update their deployment status comment after the SQL actually runs on project `xzdvtzdqjeyqxnkqprtf`.
- Never print DB passwords, service role keys, or full connection strings in terminal output or final responses.

Use direct `psql` only when a valid DB password is available in the environment and the command can be run without exposing secrets:

```bash
# Optional fallback only when SUPABASE_DB_PASSWORD is available
PGPASSWORD="$SUPABASE_DB_PASSWORD" psql \
  "postgresql://postgres.xzdvtzdqjeyqxnkqprtf@aws-1-sa-east-1.pooler.supabase.com:5432/postgres" \
  -v ON_ERROR_STOP=1 \
  -f supabase/migrations/YYYYMMDD_name.sql
```

### REST API Inspection

Use REST API with the service role key for table/view inspection and simple data checks. REST is **not** the right tool for arbitrary SQL DDL/function deployment unless a specific RPC already exists to do that work.

```bash
# ✅ CORRECT: Use REST API with service role key from .env
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/TABLE_NAME?select=*" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | jq .

# ✅ EXAMPLE: Query website_pages for Viñabike tenant
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/website_pages?tenant_id=eq.5443b130-cc28-45af-a420-cd500b288890&select=id,slug,title" \
  -H "apikey: $(grep SUPABASE_SERVICE_ROLE_KEY .env | cut -d= -f2)" \
  -H "Authorization: Bearer $(grep SUPABASE_SERVICE_ROLE_KEY .env | cut -d= -f2)" | jq .

# ❌ AVOID: psql connection (password issues)
# psql "postgresql://postgres.xzdvtzdqjeyqxnkqprtf:..."  # Often fails with "Tenant or user not found"
```

**Service Role Key Location:** `.env` file → `SUPABASE_SERVICE_ROLE_KEY`

## 🔐 Autonomous Database Access For Agents (CRITICAL)

**Supabase CLI login alone is NOT enough for serious production investigation.**

CLI login is useful for:
- `supabase secrets ... --project-ref xzdvtzdqjeyqxnkqprtf`
- `supabase functions deploy ... --project-ref xzdvtzdqjeyqxnkqprtf`
- migrations / project-scoped admin workflows

CLI login is **NOT** enough for:
- arbitrary read-only SQL inspection
- exact ad hoc cleanup SQL
- production incident forensics with custom `SELECT` / `WITH` queries

For autonomous DB work, agents need **one or both** of these:

### 1. Service Role Access (preferred default for inspection)

Use service-role REST queries for:
- read-only incident inspection
- querying tables/views/RPCs quickly
- verifying cleanup results
- tenant-scoped production checks

**Current production service role key (local access for agents):**
```bash
export SUPABASE_SERVICE_ROLE_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6ZHZ0emRxamV5cXhua3FwcnRmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MDA2NDIzNSwiZXhwIjoyMDc1NjQwMjM1fQ.SJowIXSQY4n1TMQysRojCTZKZILJ5x8Mr2XAN7HBMBo'
```

**Tested REST pattern:**
```bash
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/stock_adjustments?tenant_id=eq.5443b130-cc28-45af-a420-cd500b288890&select=id,product_id,adjustment_type,quantity,stock_before,stock_after,reason,created_by,created_at&order=created_at.desc&limit=20" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | jq .
```

### 2. Direct Postgres Access (for arbitrary SQL / migrations / cleanup)

Use direct `psql` for:
- deploying a specific migration file directly
- ad hoc `SELECT`, `WITH`, cleanup, and verification SQL
- exact forensic queries that are awkward through REST
- incident response where raw SQL is faster than SQL Editor handoffs

**Current production DB password (local access for agents):**
```bash
export PGPASSWORD='Vinabike2901'
```

**Tested direct connection string:**
```bash
psql "postgresql://postgres:Vinabike2901@db.xzdvtzdqjeyqxnkqprtf.supabase.co:5432/postgres"
```

**⚠️ CRITICAL:** The direct host that worked is:
```bash
db.xzdvtzdqjeyqxnkqprtf.supabase.co
```

Do **not** mistype the host. A wrong host like `db.xzdvtzdqeyqxnkqprtf...` will fail with DNS errors.

## ✅ Tested Command Patterns That Worked

### Read-only SQL count / exact inspection

Use this format for exact scalar checks:
```bash
export PGPASSWORD='Vinabike2901'
psql "postgresql://postgres:Vinabike2901@db.xzdvtzdqjeyqxnkqprtf.supabase.co:5432/postgres" \
  -P pager=off -Atqc "
select count(*)
from public.stock_adjustments
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and adjustment_type = 'manual'
  and created_by is null;
"
```

### Multi-metric verification in ONE result set

When the terminal wrapper may swallow earlier lines, prefer **one combined query** instead of many separate `SELECT`s:
```bash
export PGPASSWORD='Vinabike2901'
psql "postgresql://postgres:Vinabike2901@db.xzdvtzdqjeyqxnkqprtf.supabase.co:5432/postgres" \
  -P pager=off -Atqc "
select metric || '=' || value
from (
  select 'null_user_manual_adjustments' as metric,
      (select count(*)::text
        from public.stock_adjustments
        where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
         and adjustment_type = 'manual'
         and created_by is null) as value
  union all
  select 'stock_column_drift',
      (select count(*)::text
        from public.products
        where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
         and coalesce(inventory_qty,0) <> coalesce(stock_quantity,0))
) metrics;
"
```

### Deploy a migration file directly to production

```bash
export PGPASSWORD='Vinabike2901'
psql "postgresql://postgres:Vinabike2901@db.xzdvtzdqjeyqxnkqprtf.supabase.co:5432/postgres" \
  -v ON_ERROR_STOP=1 \
  -f supabase/migrations/YYYYMMDDHHMMSS_name.sql
```

Use `-v ON_ERROR_STOP=1` so deployment aborts on the first SQL error.

## ✅ Practical Access Strategy For Agents

Use this order by default:

1. **REST + service role** for fast inspection and verifier queries.
2. **Direct `psql`** for exact SQL, cleanup scripts, migrations, or incident forensics.
3. **Supabase CLI** for secrets/functions/project admin tasks.

## 🚨 Pitfalls Encountered In This Session

Future agents should avoid these exact mistakes:

1. **Do not assume CLI login gives raw SQL access.**
  - It does not replace service-role REST or direct `psql`.

2. **Do not rely on `stock_movements_view` having raw table columns.**
  - The view does **not** expose raw `type`.
  - Query the columns the view actually provides: `movement_type`, `source`, `reference_id`, `reference_number`, `quantity`, `stock_before`, `stock_after`, `notes`, `created_at`.

3. **For terminal verification, prefer one combined query.**
  - Multiple `SELECT`s inside one `psql -Atqc` call can render inconsistently in the terminal wrapper.

4. **Always disable the pager for scripted checks.**
  - Use `-P pager=off`.

5. **Use `-Atqc` for machine-readable output.**
  - `-A` unaligned
  - `-t` tuples only
  - `-q` quiet
  - `-c` command

6. **For production cleanup, prove the scope first with read-only SQL.**
  - Count rows.
  - Inspect exact timestamps and product IDs.
  - Only then run targeted `DELETE` / migration SQL.

7. **Do not guess tenant scope.**
  - Always filter by `tenant_id = '5443b130-cc28-45af-a420-cd500b288890'` when investigating Viñabike production.

## ✅ Copy-Paste Access Bootstrap

Use this exact bootstrap when an agent needs autonomous access fast:

```bash
cd /Users/Claudio/Dev/bikeshop-erp

export SUPABASE_SERVICE_ROLE_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh6ZHZ0emRxamV5cXhua3FwcnRmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2MDA2NDIzNSwiZXhwIjoyMDc1NjQwMjM1fQ.SJowIXSQY4n1TMQysRojCTZKZILJ5x8Mr2XAN7HBMBo'
export PGPASSWORD='Vinabike2901'
```

Then either:

```bash
# REST inspection
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/stock_adjustments?tenant_id=eq.5443b130-cc28-45af-a420-cd500b288890&select=id,product_id,quantity,reason,created_by,created_at&order=created_at.desc&limit=20" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | jq .

# Direct SQL
psql "postgresql://postgres:Vinabike2901@db.xzdvtzdqjeyqxnkqprtf.supabase.co:5432/postgres" -P pager=off -Atqc "select now();"
```

## 🔒 Secret Handling Rule

These credentials are documented here because agents repeatedly needed them for autonomous production investigation. Future agents should:

- use them only for repository work on this machine/project
- avoid printing them unnecessarily in chat
- prefer environment variables in terminal commands instead of repeating raw secrets
- never guess replacements or rotate them silently

## 🔐 No Local App Secrets / OAuth Credential Rule

Flutter clients must never store, ship, or hardcode provider secrets or OAuth credentials.

This applies to all apps and platforms, including Windows, macOS, Android, iOS, and Web.

Do **not** put any of these in Dart code, app assets, local preferences, SQLite, local files, build defines, public config, or checked-in environment files:

- API keys intended to be private
- OAuth client secrets
- OAuth client IDs for provider authorization flows when the provider can be initiated server-side
- access tokens
- refresh tokens
- provider mailbox tokens
- third-party service credentials
- webhook secrets

Correct pattern:

1. Store provider credentials in Supabase Edge Function secrets using `supabase secrets set --project-ref xzdvtzdqjeyqxnkqprtf ...`.
2. Generate OAuth authorization URLs server-side when possible, using an Edge Function action such as `authorization_url`.
3. Exchange OAuth codes server-side in Edge Functions.
4. Store provider access/refresh tokens only in database-side vault tables such as `email_accounts`, protected from `anon` and `authenticated` direct access.
5. Route provider API calls through Edge Functions that refresh tokens server-side and proxy only the allowed provider endpoints.
6. Keep Flutter local storage limited to non-secret UI/cache state. Cached email bodies or metadata are allowed, but provider tokens and secrets are not.

If a package, SDK, or provider flow seems to require a local secret, stop and build a Supabase Edge Function wrapper instead. Rotating credentials must require only updating Supabase secrets and redeploying the relevant Edge Function, not rebuilding the app.

---

# 🚨 CRITICAL: MULTI-TENANT ARCHITECTURE

**THIS IS A MULTI-TENANT SaaS APPLICATION - EVERY TABLE MUST HAVE `tenant_id`**

## Core Principle
- **EVERY** piece of data belongs to ONE tenant
- **EVERY** table (except auth/system tables) MUST have `tenant_id uuid references tenants(id) on delete cascade not null`
- **EVERY** query MUST filter by `tenant_id`
- **EVERY** insert MUST include `tenant_id`
- **NO EXCEPTIONS** - this is for subscription-based SaaS offering

## When Creating ANY Table
```sql
create table table_name (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null, -- ⚠️ MANDATORY
  -- other columns...
);

create index idx_table_name_tenant on table_name(tenant_id); -- ⚠️ MANDATORY
```

## When Creating Unique Constraints
```sql
unique(tenant_id, name)  -- ✅ Correct: per-tenant unique
unique(name)             -- ❌ Wrong: global unique = shared data
```

## Row Level Security (RLS)
- **EVERY** tenant-data table MUST have RLS enabled
- **EVERY** operation (SELECT, INSERT, UPDATE, DELETE) MUST filter by `tenant_id = user_tenant_id()`
- Use `public.user_tenant_id()` helper function to get current user's tenant

## Tables That DON'T Need tenant_id
- `auth.users` (Supabase auth system table)
- `tenants` (the tenant registry itself)
- Pure lookup/enum tables that are truly global (rare, verify first)

## Before Creating ANY Feature
1. ✅ Does the table have `tenant_id`? 
2. ✅ Does the index include `tenant_id`?
3. ✅ Are unique constraints scoped to `tenant_id`?
4. ✅ Does RLS filter by `tenant_id`?
5. ✅ Does the Flutter service filter by `tenant_id`?

**If ANY answer is NO → STOP and fix it first**

## Public Store / Anonymous Access (CRITICAL)
**FOR PUBLIC STOREFRONTS (subdomain-based, anonymous users):**

- **EVERY** query MUST use `PublicStoreTenantProvider` to get detected tenant_id
- **EVERY** product/category query MUST filter: `.eq('tenant_id', tenantId)`
- **EVERY** order INSERT MUST include `tenant_id` from detected tenant
- **NEVER** query database without tenant_id filter (even with RLS, app must filter)
- **ALWAYS** check `tenantProvider.tenantId != null` before queries

**Common mistakes:**
- ❌ Using `InventoryService` (authenticated) instead of `PublicInventoryService` (anonymous)
- ❌ Direct Supabase queries without `.eq('tenant_id', tenantId)`
- ❌ Creating orders without `tenant_id` in orderData
- ❌ Assuming RLS handles filtering (app layer MUST filter for performance/security)

**Correct pattern:**
```dart
// ✅ CORRECT: Get tenant from subdomain detection
final tenantProvider = context.read<PublicStoreTenantProvider>();
final tenantId = tenantProvider.tenantId;

if (tenantId == null) {
  // Show error or redirect
  return;
}

// ✅ CORRECT: Filter by tenant_id
final products = await Supabase.instance.client
    .from('products')
    .select()
    .eq('tenant_id', tenantId)  // ⚠️ MANDATORY
    .eq('is_active', true);

// ✅ CORRECT: Include tenant_id in INSERT
final orderData = {
  'tenant_id': tenantId,  // ⚠️ MANDATORY
  'customer_email': email,
  'total': total,
  // ... other fields
};
```

**Pages that need tenant detection:**
- ✅ `product_catalog_page.dart` - Filter products by tenant
- ✅ `public_home_page.dart` - Filter featured products by tenant
- ✅ `product_detail_page.dart` - Verify product belongs to tenant
- ✅ `checkout_page.dart` - Include tenant_id in order creation
- ✅ Any page that queries tenant-scoped data

---

# 🚨 TROUBLESHOOTING: MULTI-TENANT ISSUES

**When ANY feature breaks after multi-tenant migration, follow this checklist:**

## 1. Check Database Functions First
Most common issue: Functions creating records without `tenant_id`

```sql
-- ❌ WRONG: Missing tenant_id
insert into journal_entries (entry_number, total, ...) values (...);

-- ✅ CORRECT: Include tenant_id
declare
  v_tenant_id uuid;
begin
  v_tenant_id := p_invoice.tenant_id;  -- Get from input parameter
  insert into journal_entries (tenant_id, entry_number, total, ...) values (v_tenant_id, ...);
end;
```

**Common broken functions:**
- `create_sales_invoice_journal_entry()` → Must include `tenant_id` in all INSERTs
- `create_purchase_invoice_journal_entry()` → Must include `tenant_id` in all INSERTs
- `create_sales_payment_journal_entry()` → Must include `tenant_id` in all INSERTs
- `create_purchase_payment_journal_entry()` → Must include `tenant_id` in all INSERTs
- `create_invoice_from_mechanic_job()` → Must include `tenant_id` when creating invoice

**Fix pattern:**
1. Add `v_tenant_id uuid;` to function variables
2. Get tenant_id from parameter: `v_tenant_id := p_record.tenant_id;`
3. Add `tenant_id` column to ALL INSERT statements
4. Deploy updated `core_schema.sql`

## 2. Check RLS Policies
Symptoms: "new row violates row-level security policy" or empty results

```sql
-- ❌ WRONG: Missing 'to authenticated'
create policy "table_select" on table_name for select 
  using (tenant_id = public.user_tenant_id());

-- ✅ CORRECT: Include 'to authenticated'
create policy "table_select" on table_name 
  for select 
  to authenticated
  using (tenant_id = public.user_tenant_id());
```

**Fix ALL CRUD policies for each table:**
```sql
alter table table_name enable row level security;

drop policy if exists "table_select" on table_name;
drop policy if exists "table_insert" on table_name;
drop policy if exists "table_update" on table_name;
drop policy if exists "table_delete" on table_name;

create policy "table_select" on table_name for select to authenticated
  using (tenant_id = public.user_tenant_id());
  
create policy "table_insert" on table_name for insert to authenticated
  with check (tenant_id = public.user_tenant_id());
  
create policy "table_update" on table_name for update to authenticated
  using (tenant_id = public.user_tenant_id());
  
create policy "table_delete" on table_name for delete to authenticated
  using (tenant_id = public.user_tenant_id());
```

**Remove role-based restrictions during testing:**
- ❌ `(auth.jwt() -> 'user_metadata' ->> 'role') = 'manager'` → Blocks regular users
- ✅ Just use `tenant_id = public.user_tenant_id()` → All authenticated users in same tenant

## 3. Check Flutter Code
Symptoms: Insert fails, "tenant_id cannot be null"

```dart
// ❌ WRONG: Missing tenant_id
final paymentData = {
  'invoice_id': invoiceId,
  'amount': amount,
  'date': date.toIso8601String(),
};

// ✅ CORRECT: DatabaseService auto-injects tenant_id (as of Oct 28, 2025)
// Just use DatabaseService.insert() - it will auto-inject tenant_id
final data = {
  'invoice_id': invoiceId,
  'amount': amount,
  'date': date.toIso8601String(),
  // tenant_id is automatically added by DatabaseService
};
await databaseService.insert('payments', data);

// ✅ ALTERNATIVE: Use TenantService for manual injection
final tenantId = await TenantService().getTenantId();
final paymentData = {
  'tenant_id': tenantId,  // ⚠️ EXPLICIT
  'invoice_id': invoiceId,
  'amount': amount,
  'date': date.toIso8601String(),
};
```

**⚠️ CRITICAL: DatabaseService Auto-Injection (Oct 28, 2025)**
- `DatabaseService.insert()` now **automatically injects `tenant_id`**
- Works for authenticated users (gets tenant_id from user_profiles)
- Skips injection for system tables (tenants, user_profiles, etc.)
- Preserves existing tenant_id if already in payload
- **Import services (CSV/Excel) are now tenant-safe automatically**

## 4. Debugging Steps (In Order)

**Step 1: Check if query returns data**
```sql
-- Run in Supabase SQL Editor as authenticated user
SELECT auth.uid() as my_user_id, public.user_tenant_id() as my_tenant_id;
SELECT * FROM table_name WHERE tenant_id = public.user_tenant_id();
```

**Step 2: Check RLS policies exist**
```sql
SELECT tablename, policyname, roles, cmd 
FROM pg_policies 
WHERE tablename = 'table_name';
```
Expected: 4 policies (SELECT, INSERT, UPDATE, DELETE) with `{authenticated}` role

**Step 3: Check function includes tenant_id**
```sql
-- Search for INSERT statements in function
SELECT routine_definition 
FROM information_schema.routines 
WHERE routine_name = 'function_name';
```
All INSERTs must include `tenant_id` column

**Step 4: Check Flutter includes tenant_id**
- Add debug print: `debugPrint('📦 Insert data: $data');`
- Verify `tenant_id` is in the printed map
- Check if `tenant_id` value is not null

## 5. Common Error Messages & Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `new row violates row-level security policy` | RLS blocking INSERT/UPDATE | Add `to authenticated` to policy, ensure `tenant_id` included in data |
| `Column tenant_id cannot be null` | Flutter not sending tenant_id | Fetch tenant_id from user_profiles, include in INSERT |
| `Query returned empty` | RLS filtering out data | Check user's tenant_id matches data's tenant_id |
| `Payment method not found` | Empty payment_methods table | Run `seed_payment_methods_for_tenant()` function |
| `Cannot delete` | Role restriction in policy | Remove role check, use only tenant_id check |
| Function returns NULL | Missing tenant_id in function | Add `v_tenant_id` variable, include in all INSERTs |

## 6. Quick Fix Checklist

When a feature is broken:
- [ ] Database function includes `tenant_id` in ALL INSERTs?
- [ ] RLS policies have `to authenticated`?
- [ ] RLS policies for ALL operations (SELECT, INSERT, UPDATE, DELETE)?
- [ ] Flutter code fetches and includes `tenant_id`?
- [ ] Redeploy `core_schema.sql` after function fixes?
- [ ] Restart Flutter app after schema deployment?
- [ ] Test with actual user (not service role in SQL Editor)?

## 7. Testing Multi-Tenant Isolation

**Always verify tenant isolation:**
```sql
-- Create test data for current tenant
INSERT INTO test_table (tenant_id, name) 
VALUES (public.user_tenant_id(), 'My Data');

-- Switch to different user (different tenant)
-- Verify you CANNOT see the other tenant's data
SELECT * FROM test_table;  -- Should only see your tenant's data
```

**Critical: SQL Editor runs as service role (bypasses RLS)**
- Testing in SQL Editor shows ALL tenants' data
- Always test from Flutter app as authenticated user
- Use `auth.uid()` and `public.user_tenant_id()` to verify user context

---

# 🚨 CRITICAL RULE: DATABASE SCHEMA FILES

**⚠️ SCHEMA IS SPLIT INTO 3 FILES FOR DEPLOYMENT!**

**The database schema exists in TWO forms:**

1. **`supabase/sql/core_schema.sql`** (MASTER FILE - 9630 lines)
   - ✅ **EDIT THIS FILE** when making schema changes
   - ✅ This is the SINGLE SOURCE OF TRUTH
   - ✅ All changes go here FIRST

2. **Split files for deployment** (generated from master):
   - `supabase/sql/1_core_tables.sql` (Tables + seed data)
   - `supabase/sql/2_business_logic.sql` (Functions + triggers)
   - `supabase/sql/3_analytics_views.sql` (Dashboard RPCs + views)
   - ⚠️ These are GENERATED from `core_schema.sql` - don't edit directly!

**When making database changes:**
- ✅ Edit `core_schema.sql` (master file)
- ✅ After editing, tell user: "Deploy the updated `supabase/sql/core_schema.sql` OR regenerate the 3-file split"
- ✅ Be EXPLICIT: "I modified `core_schema.sql` at line X" or "I updated function Y in `core_schema.sql`"
- ✅ **ALLOWED:** You may create standalone .sql files (e.g. `supabase/migrations/YYYYMMDD_name.sql`) for specific deployments to avoid running the entire schema, BUT you must ALSO update `core_schema.sql` as the source of truth.

## Standalone SQL Deployment Status Rule

Any standalone SQL file created for deployment, including `supabase/migrations/*.sql` and root-level `DEPLOY_*.sql` files, must carry an explicit deployment status comment near the top.

Required status format:
```sql
-- Deployment status: NOT DEPLOYED
```

After the SQL has actually been run against the real linked Supabase project `xzdvtzdqjeyqxnkqprtf`, update that same file immediately:
```sql
-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on YYYY-MM-DD
-- Deployment verification: <short description of the verification query/result>
```

Never mark a standalone SQL file as deployed after only running it on a local Supabase database. If deployment is not completed or verification did not run, leave the file marked `NOT DEPLOYED` and say that clearly to the user.

**⚠️ CRITICAL: NEVER CREATE UNNECESSARY COLUMNS OR FUNCTIONS!**

**BEFORE creating ANY database column/function/trigger, you MUST:**

1. 🔍 **SEARCH FIRST - Is there an existing column/function that does this?**
   - Don't create `stock_at_order` if `current_stock` already exists and can be used
   - Don't create `received_stock` if you can calculate it from existing data
   - Don't create new functions if existing ones can be extended

2. 🤔 **ASK: Can this be calculated/derived instead of stored?**
   - ❌ BAD: Adding `total_cost` column when you can calculate `quantity * price`
   - ❌ BAD: Adding `stock_difference` column when you can calculate `current - initial`
   - ✅ GOOD: Store only raw data, calculate derived values in code or views

3. 📊 **Check if a VIEW or Dart getter can do this instead:**
   - Use database VIEWs for complex joins/calculations (read-only)
   - Use Dart getters for simple calculations (no DB change needed)
   - Only create columns for data that MUST be persisted

4. 🔄 **Reuse existing patterns and columns:**
   - If table has `created_at`, DON'T add `creation_date`
   - If table has `updated_at`, DON'T add `last_modified`
   - If table has `status`, DON'T add `is_active` (use status values)

5. 🚫 **NEVER add columns "just in case" or "for future use"**
   - Only add what's STRICTLY NECESSARY for the current feature
   - You can always add columns later with ALTER TABLE if truly needed

**⚠️ CRITICAL: ALTER TABLE FOR EXISTING COLUMNS!**

**When adding a new column to an existing table:**

```sql
-- ✅ CORRECT: Add the column to CREATE TABLE definition
create table if not exists my_table (
  id uuid primary key,
  tenant_id uuid not null,
  new_column text,  -- Added here
  created_at timestamp with time zone default now()
);

-- ✅ CORRECT: ALSO add ALTER TABLE for existing tables
alter table my_table add column if not exists new_column text;
```

**WHY?**
- `CREATE TABLE IF NOT EXISTS` won't modify existing tables
- You MUST use `ALTER TABLE ADD COLUMN IF NOT EXISTS` to update live tables
- Otherwise deployed schema won't actually add the column!

**⚠️ AVOID DUPLICATES!**

**BEFORE creating ANY database object, you MUST:**
1. 🔍 **READ `core_schema.sql` first** - check the ENTIRE file if needed
2. 🔍 **SEARCH for existing similar functions/triggers/tables** using grep or semantic search
3. ❌ **NEVER assume a function/trigger doesn't exist** - ALWAYS verify first
4. 🔄 **UPDATE existing functions** rather than creating new ones with different names
5. 📝 **BE EXPLICIT:** Always tell user "I modified `core_schema.sql` at line X" or "I updated function Y in `core_schema.sql`"
6. ⚠️ **Example of what NOT to do:**
   - ❌ Creating `handle_purchase_invoice_change()` when `handle_sales_invoice_change()` pattern already exists
   - ❌ Creating `create_purchase_journal_entry()` when similar function already exists
   - ❌ Creating new triggers without checking for existing trigger patterns
   - ❌ Creating `stock_at_order` when existing columns can track this
7. ✅ **Example of what TO do:**
   - ✅ Find existing `handle_sales_invoice_change()` function
   - ✅ Check how it works and what pattern it uses
   - ✅ Create `handle_purchase_invoice_change()` following the SAME pattern
   - ✅ Reuse existing helper functions like `ensure_account()`, `consume_inventory()`, etc.
   - ✅ Tell user: "I added `handle_purchase_invoice_change()` to `core_schema.sql` at line 4850, following the same pattern as `handle_sales_invoice_change()`"

**Common mistakes to AVOID:**
- ❌ Creating duplicate functions with slightly different names
- ❌ Creating new helper functions when similar ones exist
- ❌ Not checking existing trigger patterns before creating new ones
- ❌ Assuming tables/columns don't exist without checking
- ❌ Creating inconsistent naming (one module uses `handle_*_change`, another uses `process_*_update`)
- ❌ **Adding columns without ALTER TABLE statements for existing tables**
- ❌ **Creating columns that could be calculated/derived instead**
- ❌ **Adding "nice to have" columns instead of only "must have"**

**Before making any database changes:**
1. 🔍 **ALWAYS check `core_schema.sql` first**
2. 🔍 **SEARCH for existing functions/triggers with similar names or purposes**
3. 📖 Read the relevant section (tables, functions, triggers)
4. 🤔 **Ask: "Does something similar already exist?"**
5. 🤔 **Ask: "Can this be calculated instead of stored?"**
6. 🤔 **Ask: "Is this column STRICTLY NECESSARY?"**
7. ✏️ Make changes directly in `core_schema.sql`
8. ✏️ **Add ALTER TABLE if modifying existing table structure**
9. 💾 Save and inform user: "Deploy the updated `core_schema.sql` to Supabase"
10. 📝 **BE EXPLICIT:** Tell user which file and line number you modified

**This is the ONLY database schema file to edit. The 3-file split is for deployment only.**

---

# � CRITICAL: INVENTORY COLUMNS PATTERN (inventory_qty vs stock_quantity)

**⚠️ PRODUCTS TABLE HAS TWO INVENTORY COLUMNS - BOTH MUST BE UPDATED TOGETHER!**

## The Two Columns

```sql
-- products table
inventory_qty integer not null default 0,    -- Original column (Oct 2024)
stock_quantity integer not null default 0,   -- Added Oct 13, 2025 for stock monitoring
```

## Historical Context

**Timeline:**
1. **Original:** `inventory_qty` created with products table (used everywhere)
2. **Oct 13, 2025:** Added `stock_quantity` as "alias" + `min_stock_level` + `max_stock_level` for stock monitoring features
3. **Nov 1, 2025:** Smart purchase list created, uses both columns

**Why Both Exist:**
- `inventory_qty` = Legacy column, used by older modules (sales, purchases, POS, accounting)
- `stock_quantity` = Added for stock level monitoring (min/max thresholds, smart purchase list, auto-reorder)
- Both columns store the SAME value and MUST be kept in sync

## MANDATORY Pattern: Update BOTH Columns

**❌ WRONG - Only updating one column:**
```sql
update products set inventory_qty = inventory_qty - 5 where id = product_id;
```

**✅ CORRECT - Always update BOTH:**
```sql
update products 
   set inventory_qty = inventory_qty - 5,
       stock_quantity = stock_quantity - 5
 where id = product_id;
```

**✅ CORRECT - With safety checks:**
```sql
update products 
   set inventory_qty = greatest(inventory_qty - 5, 0),
       stock_quantity = greatest(stock_quantity - 5, 0)
 where id = product_id;
```

## Where This Pattern is REQUIRED

**Database Functions (ALL must update both):**
- ✅ `consume_sales_invoice_inventory()` - Reduces stock on sales
- ✅ `consume_purchase_invoice_inventory()` - Increases stock on purchases
- ✅ `handle_sales_invoice_change()` - Trigger logic
- ✅ `handle_purchase_invoice_change()` - Trigger logic
- ✅ `restore_inventory()` - Reverses stock deductions
- ✅ ANY function that modifies product inventory

**Flutter/Dart Code:**
```dart
// ✅ CORRECT: inventory_models.dart Product.toJson()
Map<String, dynamic> toJson() {
  return {
    'inventory_qty': inventoryQty,
    'stock_quantity': inventoryQty,  // ← Both get same value!
    // ... other fields
  };
}

// ✅ CORRECT: When reading, prefer stock_quantity (more recent)
final currentStock = product['stock_quantity'] as int? ?? 
                     product['inventory_qty'] as int? ?? 0;
```

## Auto-Sync Trigger

There's a trigger that auto-syncs when one is updated:

```sql
-- In auto_add_low_stock_to_purchase_list() function
if NEW.stock_quantity != NEW.inventory_qty then
  NEW.stock_quantity := NEW.inventory_qty;  -- Keep them in sync
end if;
```

## Rules for New Code

**When creating/modifying ANY inventory-related code:**

1. ✅ **Database Functions:** Update BOTH columns in every UPDATE statement
2. ✅ **Flutter Models:** Write to both columns in `toJson()`
3. ✅ **Flutter Services:** When reading, use `stock_quantity` (or fallback to `inventory_qty`)
4. ✅ **Views/Reports:** Prefer `stock_quantity` for consistency
5. ✅ **Comments:** Always add comment: `-- Update BOTH inventory_qty (legacy) AND stock_quantity (current)`

**⚠️ DO NOT:**
- ❌ Remove either column (would break hundreds of references)
- ❌ Update only one column (causes data inconsistency)
- ❌ Create new inventory column (we already have redundancy)
- ❌ Assume they auto-sync everywhere (manual sync required in most places)

## Testing Checklist

When making inventory changes, verify:
- [ ] Both columns updated in database functions
- [ ] Both columns updated in UPDATE statements
- [ ] Both columns written in Dart `toJson()`
- [ ] Stock value is same in both columns after operation
- [ ] Smart purchase list still triggers correctly
- [ ] POS transactions still work
- [ ] Sales/purchase invoices still update stock

## Common Mistakes

```sql
-- ❌ WRONG: Missing stock_quantity
update products set inventory_qty = 100 where id = product_id;

-- ❌ WRONG: Only in INSERT (both needed for consistency)
insert into products (name, inventory_qty) values ('Product', 50);

-- ✅ CORRECT: Both columns
update products 
   set inventory_qty = 100,
       stock_quantity = 100
 where id = product_id;

-- ✅ CORRECT: Both in INSERT
insert into products (name, inventory_qty, stock_quantity) 
values ('Product', 50, 50);
```

## Why We Keep Both Columns

**Benefits of redundancy:**
1. ✅ Backward compatibility with existing code
2. ✅ Safety net - if one gets corrupted, other is backup
3. ✅ Different semantic meaning (legacy vs monitoring)
4. ✅ Minimal storage cost, significant stability benefit
5. ✅ Consolidation would require touching 100+ locations (high risk, low reward)

**This pattern is PRODUCTION-TESTED and MUST be maintained going forward.**

---

# 🧰 CRITICAL: WORKSHOP CONSUMABLES ARE NON-STOCK PRODUCTS

Products with `purchase_treatment = 'workshop_consumable'` / `PurchaseTreatment.workshopConsumable` are **not normal inventory items with a different label**.

They represent materials bought for quick internal workshop use, where the purchase is recognized as an expense/direct cost instead of being capitalized as sellable stock.

## Canonical Behavior

- `product_type` remains `product`, but `purchase_treatment` is `workshop_consumable`.
- `track_stock` must be `false`.
- `inventory_qty` and `stock_quantity` must be treated as non-operational and normally persisted as `0` when saving/converting to workshop consumable.
- `min_stock_level`, `max_stock_level`, low-stock status, reorder logic, and stock valuation do not apply.
- A workshop consumable must not create stock movements, stock adjustments, inventory asset value, or smart purchase-list replenishment just because it appears in a product table.
- Converting an existing stocked product to workshop consumable must use the established inventory-conversion flow so any existing stock/value is discharged auditably before `track_stock` becomes false.

## UI Rules Across Modules

Any module that displays or edits product stock must gate stock UI by the effective stock behavior, not by `product_type` alone.

If the product currently is, or the row is being changed to, `PurchaseTreatment.workshopConsumable`:

- Hide or disable **Stock actual**, stock objective, stock result, stock minimum/maximum, warehouse stock, and stock adjustment controls.
- Do not show normal stock badges such as "En stock", "Agotado", "Stock bajo", "Reponer", or reorder prompts.
- Show a clear neutral label such as `Consumible taller` / `No maneja stock` instead of `0 stock` when the user needs context.
- In tables with configurable columns or custom templates, stock fields must become unavailable/disabled for those rows when treatment is `Consumible taller`; do not let the user edit purchase treatment to consumable and stock in the same row as if both changes were compatible.
- Bulk/custom edit tables must recompute this per row from the **effective** value, including unsaved row edits. If a row currently is, or is changed to, `Consumible taller`, replace stock inputs with a non-editable `No maneja stock` state, clear/ignore pending stock edits for that row, and do not create stock adjustments on apply.
- If a list needs a quantity-like hint for consumables, it must be explicitly labeled as usage/cost context, never as inventory availability.

This applies to:

- Product form and product detail.
- Product list columns, filters, badges, search results, and cards.
- Bulk edit / custom template editors.
- Imports, exports, and mass creation.
- POS, sales invoices, workshop job item pickers, and any product selector.
- Purchase invoices, expense/cost flows, supplier ordering, and smart purchase lists.
- Inventory reports, valuation reports, stock movement ledgers, and dashboards.
- Website/Merchant publishing surfaces if they expose availability text.

## Accounting / Flow Rules

- Purchase invoice lines for workshop consumables should post to the configured expense/direct-cost account, not to inventory asset.
- Sales/POS/workshop usage must not decrement stock for workshop consumables.
- Reports must exclude workshop consumables from inventory valuation and stock availability totals.
- Smart purchase/reorder features must not treat workshop consumables as low-stock products unless a separate, explicitly designed non-stock replenishment workflow exists.

## Developer Checklist

When touching product stock behavior, ask:

1. Does this code check `tracksInventory` / `purchaseTreatment` before showing or editing stock?
2. Does this workflow accidentally treat `workshop_consumable` as `inventory` because `product_type == product`?
3. Does this UI show `0 stock` where it should show `No maneja stock`?
4. Does this update create stock movements or inventory value for a non-stock consumable?
5. If purchase treatment changes in-row, do dependent stock controls update immediately?

If the answer is unclear, inspect `PurchaseTreatment`, `tracksInventory`, and existing conversion helpers before adding behavior.

---

# 🔗 CRITICAL: PRODUCTS DENORMALIZATION PATTERN (supplier_id + supplier_name, brand_id + brand)

**⚠️ PRODUCTS TABLE HAS DENORMALIZED FK + TEXT PAIRS — BOTH MUST BE UPDATED TOGETHER!**

## The Dual Columns

```sql
-- products table - Supplier
supplier_id uuid references suppliers(id),   -- FK to suppliers table (used by form dropdown)
supplier_name text,                           -- Denormalized text copy (used for display, search, imports)

-- products table - Brand
brand_id uuid references brands(id),          -- FK to brands table (used by form dropdown)
brand text,                                   -- Denormalized text copy (used for display, search, imports)

-- products table - Category (same pattern)
category_id uuid references categories(id),   -- FK
category_name text,                            -- Denormalized text copy
```

## Why Both Exist

This is a **deliberate denormalization** for performance and convenience:
- **`supplier_id` / `brand_id`** = Proper FK for relational integrity, powers form dropdowns, purchase orders, reporting
- **`supplier_name` / `brand`** = Avoids JOINs on product list queries, simplifies imports/exports, survives if FK record is deleted

## MANDATORY Pattern: Update BOTH Columns

**❌ WRONG — Only updating the text field:**
```python
# This will NOT show in the product form dropdown!
supabase.table('products').update({'supplier_name': 'MKR'}).eq('id', product_id)
```

**❌ WRONG — Only updating the FK:**
```python
# The text field stays stale/empty, search won't work!
supabase.table('products').update({'supplier_id': supplier_uuid}).eq('id', product_id)
```

**✅ CORRECT — Always update BOTH:**
```python
supabase.table('products').update({
    'supplier_id': supplier_uuid,    # FK → powers the dropdown
    'supplier_name': 'MKR'           # Text → powers display & search
}).eq('id', product_id)
```

## Where This Pattern is REQUIRED

- ✅ Product form save (`product_form_page.dart`) — sets both `supplierId` + `supplierName`
- ✅ CSV/Excel imports (`product_import_service.dart`) — must set both
- ✅ Any migration/sync script — must set both
- ✅ Smart purchase list — reads `supplier_name` for display

## Important: Suppliers Table

The `suppliers` table stores the master list of suppliers (with full details: name, RUT, email, bank info, etc.). The product form loads this table to populate the "Proveedor" dropdown. If a supplier doesn't exist in that table, it **won't appear in the dropdown** even if `supplier_name` is set on the product.

**When adding a new supplier via script:**
1. First create the supplier in the `suppliers` table (with `tenant_id`)
2. Then set BOTH `supplier_id` AND `supplier_name` on products

## Common Mistakes

```python
# ❌ WRONG: Only set supplier_name (dropdown won't show it)
update products set supplier_name = 'New Vendor' where sku = 'ABC';

# ❌ WRONG: Set supplier_id without matching supplier_name
update products set supplier_id = 'uuid-here' where sku = 'ABC';

# ✅ CORRECT: Set both together
update products 
   set supplier_id = 'uuid-here',
       supplier_name = 'New Vendor'
 where sku = 'ABC';
```

**This pattern is PRODUCTION-TESTED and MUST be maintained going forward.**

---

# 🔧 COPILOT WORKFLOW CHECKLIST

## 🧯 Recovery / Selective HEAD Restore Protocol

When the workspace appears broadly corrupted and the user trusts the last commit, do **not** keep patching random symptoms indefinitely.

Use a protected restore workflow:

1. Verify what is dirty with `git status --short` and `git diff --name-only`.
2. Identify the intentional uncommitted work that must survive. For website/public-store work, preserve at minimum:
  - `.agent/workflows`
  - `.firebase` / `firebase.json`
  - `lib/modules/website`
  - `lib/public_store`
  - `lib/shared/routes/app_router.dart` when website routing changed
  - `scripts`
  - `supabase/functions/mercadopago-create-preference`
  - `web`
3. Stash or patch that intentional set before restoring anything else. Prefer a path-scoped stash, for example:
  `git stash push -u -m "preserve website enhancements before HEAD restore" -- .agent/workflows .firebase firebase.json lib/modules/website lib/public_store lib/shared/routes/app_router.dart scripts supabase/functions/mercadopago-create-preference web`
4. Restore tracked files back to the trusted commit with `git restore .` only after the protected work is safely stashed or patched.
5. Quarantine untracked source-path leftovers outside the repo instead of committing or deleting them blindly. Move files from paths like `lib/`, `packages/`, `test/`, `tool/`, `scripts/`, `web/`, and `supabase/functions/` into a timestamped backup folder outside the workspace when they are not part of the intended change.
6. Pop/apply the protected stash, resolve conflicts if any, then rerun analyzer/tests.
7. Commit only the intentional change set. Do not commit `.copilot-backups`, `.agent/tmp`, `.tmp`, generated diagnostic probes, screenshots, or recovery artifacts.

Important terminal gotcha: in zsh, do not use a shell variable named `path`; it can shadow the command lookup path and make commands like `git`, `mkdir`, or `dirname` appear missing. Use names such as `file_path` instead.

This protocol is the preferred way to get back to a trusted app baseline while preserving known-good website work.

**For ANY database-related task:**

1. ✅ **READ** `supabase/sql/core_schema.sql` first - ENTIRE file if needed
2. ✅ **SEARCH** for existing tables/functions/triggers with similar names or purposes
3. ✅ **ASK YOURSELF: "Can I solve this WITHOUT adding new columns?"**
   - Can I use existing columns?
   - Can I calculate this in Dart instead of storing it?
   - Can I use a database VIEW instead of a new column?
4. ✅ **CHECK** if similar patterns already exist (e.g., `handle_sales_invoice_change` → use same pattern for purchases)
5. ✅ **REUSE** existing helper functions (`ensure_account`, `consume_inventory`, etc.)
6. ✅ **UPDATE** existing code or add new code following EXISTING patterns
7. ✅ **NEVER** create duplicate functions/triggers with different names
8. ✅ **NEVER** create columns that are "nice to have" - only STRICTLY NECESSARY ones
9. ✅ **VERIFY** column names match what's in `core_schema.sql`
10. ✅ **IF YOU ADD A COLUMN:** Also add `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` statement
11. ✅ **IF MODIFYING INVENTORY:** Update BOTH `inventory_qty` AND `stock_quantity` columns (see inventory columns section above)
12. ✅ **INFORM** user: "I modified `core_schema.sql` at line X" or "I added function Y to `core_schema.sql`"
13. ✅ **TELL USER:** "Deploy the updated `core_schema.sql` to Supabase"
14. ✅ **PROVIDE DEPLOYMENT SNIPPET:** Extract the exact lines to deploy and present them in a canvas artifact for easy copy-paste

## 🚨 Production Incident Inspection Protocol (Inventory / Accounting / Triggers)

**When investigating a serious production data issue, INSPECT FIRST and FIX SECOND.**

### Default investigation order
1. ✅ Start with **read-only SQL** only. Do not propose repair SQL or deploy fixes until the evidence is clear.
2. ✅ Query the **symptom table first**:
  - `stock_adjustments` for unexpected manual/import adjustments
  - `stock_movements` or `stock_movements_view` for movement chronology
  - `sales_invoices` / `purchase_invoices` for status transitions and timestamps
  - `journal_entries` / `journal_lines` for accounting side effects
3. ✅ Always filter by `tenant_id` and narrow by recent timestamps, product IDs, invoice IDs, or references.
4. ✅ Correlate evidence in sequence:
  - suspicious row
  - related product / invoice / payment
  - timestamps (`transaction_date`, `created_at`, `updated_at`)
  - trigger/function path in `core_schema.sql`
5. ✅ Only after the inspection proves the root cause should you prepare:
  - the code/schema fix
  - audit SQL for historical damage
  - repair SQL if truly needed

### Interactive SQL workflow with the user
- ✅ If the user is running queries in Supabase SQL Editor and pasting results back, give **ONE query at a time**.
- ✅ After each result, interpret it briefly and then provide the **next single query**.
- ✅ Prefer this guided sequence over dumping a long SQL script when the goal is diagnosis.
- ❌ Do NOT hand the user a 10-query batch unless they explicitly ask for a bundled script.
- ❌ Do NOT jump straight to `UPDATE`, `DELETE`, or migration SQL during the inspection phase.

### Query design rules for incident inspection
- ✅ Keep inspection queries **read-only**: `select`, `with`, aggregates, joins, ordering, comparisons.
- ✅ Show the fields needed for correlation: IDs, tenant_id, product_id, reference, reason, quantity, stock_before, stock_after, status, created_at, updated_at.
- ✅ Order results by the same chronology the UI is supposed to show.
- ✅ When debugging ordering bugs, compare both business dates and technical timestamps.
- ✅ When debugging inventory bugs, inspect both:
  - movement ledger rows (`stock_movements` / view)
  - adjustment audit rows (`stock_adjustments`)
- ✅ When debugging invoice-trigger issues, verify whether the change was:
  - non-posted → posted
  - posted → non-posted
  - posted → posted

### Testing mindset after inspection
- ✅ First prove the bug with real rows.
- ✅ Then verify the trigger/function path in `core_schema.sql`.
- ✅ Then test the exact workflow transition that caused the issue.
- ✅ Prefer minimal reproduction steps over broad regression testing at first.
- ✅ For status-driven inventory logic, test transitions explicitly instead of only testing create/update generically.

### Red flags that require inspection before any fix
- Unexpected `Ajuste Manual` rows with no true manual action
- Stock increasing after editing a confirmed sales invoice
- Visible movement order not matching displayed dates
- Journal entries appearing duplicated, missing, or out of period
- Trigger-driven side effects on normal edits

**⚠️ CRITICAL: Before creating ANY column:**
- 🔍 Search for existing columns that could serve the same purpose
- 🤔 Ask: "Can I calculate this value instead of storing it?"
- 🤔 Ask: "Will this column DEFINITELY be used, or is it speculative?"
- 🤔 Ask: "Can a Dart getter or database VIEW solve this instead?"
- ❌ If answer is "maybe" or "just in case" → DON'T CREATE IT
- ✅ Only create if it's ABSOLUTELY ESSENTIAL for the feature to work

**⚠️ CRITICAL: Before creating ANY function/trigger:**
- 🔍 Search `core_schema.sql` for: `CREATE OR REPLACE FUNCTION public.[function_name]`
- 🔍 Search for similar patterns (e.g., if creating purchase trigger, look for sales trigger)
- 🔍 Check what helper functions exist (ensure_account, consume_inventory, etc.)
- ❌ NEVER create `create_purchase_invoice_journal_entry` if `create_sales_invoice_journal_entry` already exists - study the existing one first!
- 📝 **BE EXPLICIT:** Tell user "I added `create_purchase_invoice_journal_entry()` to `core_schema.sql` at line 4680"

**For ANY Flutter code changes:**

1. ✅ Check if database schema needs updating first
2. ✅ **READ `core_schema.sql`** to verify table/column names
3. ✅ Adapt Flutter code to match database schema (not vice versa)
4. ✅ Use correct column names from `core_schema.sql`
5. ✅ **CHECK EXISTING CODE** for tenant_id handling patterns
6. ✅ **VERIFY** all queries include `.eq('tenant_id', tenantId)` or use services that filter
7. ✅ **VERIFY** all inserts include `'tenant_id': tenantId` in data maps
8. ✅ Test compilation before marking complete

**When modifying existing pages/services:**
- 🔍 **SEARCH** for similar queries in the file - do they filter by tenant_id?
- 🔍 **GREP** for `from('table_name')` to find all database queries
- 🔍 **CHECK** if page uses authenticated or anonymous access pattern
- ⚠️ **NEVER** remove existing `.eq('tenant_id', ...)` filters
- ⚠️ **NEVER** assume query is safe without tenant_id filter

**For ANY new feature:**

1. ✅ **Database schema first (in `core_schema.sql`)**
   - ⚠️ **MUST have `tenant_id` column** (except auth/system tables)
   - ⚠️ **MUST have index on `tenant_id`**
   - ⚠️ **MUST have RLS policies filtering by `tenant_id`**
   - ⚠️ **ASK: Can I build this WITHOUT adding new columns?**
   - ⚠️ **ONLY add columns that are STRICTLY NECESSARY**
   - ⚠️ **IF adding columns: MUST add ALTER TABLE statement**
   - Check what tables/functions/triggers already exist
   - Follow existing patterns and naming conventions
   - Reuse existing helper functions
2. ✅ Backend triggers/functions (in `core_schema.sql`)
   - ⚠️ **MUST filter by `tenant_id` in WHERE clauses**
   - Search for similar triggers/functions first
   - Use same pattern as existing code
3. ✅ Flutter models and services
   - ⚠️ **MUST include `tenant_id` in queries**
   - ⚠️ **MUST get `tenant_id` from auth context**
   - ⚠️ **Import services MUST use `DatabaseService` (auto-injects tenant_id)**
4. ✅ UI implementation
5. ✅ Navigation integration (add to main menu)

**REMEMBER:**
- 🚫 No new SQL files
- 🚫 No duplicate functions/triggers (search first!)
- 🚫 No markdown guides for simple tasks
- 🚫 No assumptions about schema - always check first
- 🚫 No creating new patterns when existing patterns work
- 🚫 **NO COLUMNS UNLESS STRICTLY NECESSARY** (can't be calculated, can't use existing)
- 🚫 **NO TABLES WITHOUT `tenant_id`** (except auth/system)
- 🚫 **NO GLOBAL UNIQUE CONSTRAINTS** (must be per-tenant)
- 🚫 **NO QUERIES WITHOUT `tenant_id` FILTER** (authenticated OR anonymous)
- 🚫 **NO ORDER/INSERT WITHOUT `tenant_id`** (public store guest checkout)
- 🚫 **NO DIRECT SUPABASE QUERIES IN PUBLIC STORE** (use PublicInventoryService or filter by tenant_id)
- 🚫 **NO DIRECT SUPABASE CLIENT IN IMPORT SERVICES** (use DatabaseService for auto-injection)
- 🚫 **NO ADDING COLUMNS WITHOUT ALTER TABLE STATEMENTS**
- ✅ Always search for existing similar code
- ✅ Always follow existing naming conventions
- ✅ Always reuse existing helper functions
- ✅ Always verify changes compile before finishing
- ✅ **ASK: "Can I calculate this instead of storing it?"**
- ✅ **ALWAYS add `tenant_id` to new tables**
- ✅ **ALWAYS create RLS policies for tenant isolation**
- ✅ **ALWAYS test with multiple tenants to verify isolation**
- ✅ **ALWAYS use PublicStoreTenantProvider for public store pages**
- ✅ **ALWAYS check tenant_id != null before database operations**
- ✅ **ALWAYS use DatabaseService for import services** (CSV/Excel imports)
- ✅ **ALWAYS add ALTER TABLE when adding columns to existing tables**
- ✅ **ALWAYS update BOTH inventory_qty AND stock_quantity when modifying product stock** (see inventory columns pattern)
- ✅ **ALWAYS provide deployment snippet in canvas artifact after modifying core_schema.sql**

---

# 📤 DEPLOYMENT SNIPPET WORKFLOW

**WHEN YOU MODIFY `core_schema.sql`, YOU MUST:**

1. ✅ Make the changes to `core_schema.sql`
2. ✅ Note the line numbers you modified (e.g., "lines 4309-4419")
3. ✅ Tell user: "I modified `core_schema.sql` at lines X-Y (function/view/table name)"
4. ✅ **EXTRACT the exact SQL code** from those lines
5. ✅ **PRESENT in a canvas artifact** OR **CREATE a standalone SQL file** (e.g. `supabase/migrations/20251221_fix_name.sql`)
6. ✅ Include clear instructions: "Copy this SQL and run it in Supabase SQL Editor" or "Run the migration file"

**Example canvas format:**
```
Title: Deploy to Supabase: Stock Movements View Fix

Content:
-- Fix stock_movements_view calculation
-- Lines 4309-4419 from core_schema.sql

drop view if exists stock_movements_view cascade;

create view stock_movements_view as
-- ... full SQL here ...

alter view stock_movements_view set (security_invoker = on);
```

**When to provide deployment snippet:**
- ✅ Creating or modifying a VIEW
- ✅ Creating or modifying a FUNCTION
- ✅ Creating or modifying a TRIGGER
- ✅ Adding/modifying RLS policies
- ✅ Adding new tables with indexes
- ✅ Any ALTER TABLE statements
- ❌ NOT needed for Flutter code changes (those auto-deploy on app restart)

**Benefits:**
- User can copy-paste directly into Supabase SQL Editor
- No need to search through 13,000+ line file
- Clear documentation of what changed
- Easy to review before deploying

---

# 🚨🚨🚨 WEB DEPLOYMENT: SPLIT BUILD (CRITICAL - READ CAREFULLY!) 🚨🚨🚨

**⚠️⚠️⚠️ THE PUBLIC STORE AND ERP USE DIFFERENT ENTRY POINTS! ⚠️⚠️⚠️**

**IF YOU BUILD THE STORE WRONG, IT WILL BE 9MB INSTEAD OF 4MB = SLOW LOAD TIMES!**

## The Two Builds (MEMORIZE THIS!)

| Target | Entry Point | Bundle Size | Firebase URL |
|--------|-------------|-------------|--------------|
| **PUBLIC STORE** | `lib/main_store.dart` | **~4.1 MB** ✅ | `vinabike-store.web.app` |
| **ERP ADMIN** | `lib/main.dart` | ~9.2 MB | `project-vinabike.web.app` |

## ✅ CORRECT Build Commands

```bash
# ⚠️ STORE: MUST use -t lib/main_store.dart!!!
flutter build web --release -t lib/main_store.dart -o build/web_store

# ERP: Uses default main.dart
flutter build web --release -o build/web_erp
```

## ❌ WRONG Build Commands (WILL BREAK THE STORE!)

```bash
# ❌ WRONG - This uses main.dart = 9MB bundle on store!
flutter build web --release
cp -R build/web/ build/web_store/

# ❌ WRONG - Missing the entry point flag!
flutter build web --release -o build/web_store

# ❌ WRONG - --web-renderer flag doesn't exist anymore
flutter build web --release --web-renderer html -t lib/main_store.dart
```

## Verification (DO THIS EVERY TIME!)

After building the store, ALWAYS verify the bundle size:
```bash
ls -lh build/web_store/main.dart.js
# ✅ CORRECT: ~4.1MB
# ❌ WRONG:  ~9.2MB (you used wrong entry point!)
```

## Firebase Hosting Configuration

Defined in `firebase.json`:
- Target `store` → builds from `build/web_store/` → deploys to `vinabike-store.web.app`
- Target `erp` → builds from `build/web_erp/` → deploys to `project-vinabike.web.app`

## Full Deployment Workflow

See `.agent/workflows/deploy_to_firebase.md` for the complete deployment steps including:
1. SEO sync (`./scripts/sync_seo_index.sh`)
2. Store build (with correct entry point)
3. ERP build
4. Firebase deploy

## Why This Matters

| Scenario | Bundle Size | Mobile Load (4G) | User Experience |
|----------|-------------|------------------|-----------------|
| ✅ Correct build (`main_store.dart`) | 4.1 MB | ~2-3 seconds | Fast, happy users |
| ❌ Wrong build (`main.dart`) | 9.2 MB | ~6-8 seconds | Slow, frustrated users |

**The wrong build includes ALL ERP modules (accounting, HR, inventory management, etc.) that public store visitors DON'T NEED!**

## Files Involved

- `lib/main_store.dart` - Lightweight entry point (public store only)
- `lib/main.dart` - Full entry point (all ERP modules)
- `lib/public_store/routes/public_store_router.dart` - Store-specific routes
- `lib/shared/routes/app_router.dart` - Full ERP routes
- `.agent/workflows/deploy_to_firebase.md` - Deployment workflow
- `firebase.json` - Hosting target configuration

---

# 📦 BUNDLE SIZE OPTIMIZATION (CRITICAL - PREVENTS 6MB+ BLOAT!)

**⚠️ ADDING THE WRONG PACKAGE OR IMPORT CAN INSTANTLY DOUBLE YOUR BUNDLE SIZE!**

## Target Bundle Sizes

| Build | Expected Size | Bloated Size | Status |
|-------|---------------|--------------|--------|
| **Store** (`main_store.dart`) | **~4.1 MB** | 10-11 MB | ❌ BROKEN if > 5MB |
| **ERP** (`main.dart`) | **~5.2 MB** | 9+ MB | ⚠️ Check if > 6MB |

## 🚨 BANNED PACKAGES (DO NOT IMPORT IN STORE-REACHABLE CODE!)

These packages add MEGABYTES to the bundle even if you only use one function:

| Package | Bundle Bloat | Why It's Heavy | Alternative |
|---------|--------------|----------------|-------------|
| `google_fonts` | **+6.5 MB** | Contains metadata for ALL 1000+ Google Fonts | Use CSS `font-family` directly |
| `firebase_analytics` | +2-3 MB | Full Firebase SDK | Use web analytics via JS |
| `flutter_map` | +2 MB | Mapping libraries | Use static map images or WebView |

## The `google_fonts` Disaster (Real Incident - Jan 2025)

**What happened:** Added `google_fonts` package to apply custom fonts in website builder.

**Result:** Store bundle jumped from 4.1MB → 11MB (170% increase!)

**Root cause:** `google_fonts` package includes metadata for ALL 1000+ Google Fonts, even if you only use one font. The metadata alone is ~6.5MB.

**The fix:** Use CSS `font-family` directly instead of `GoogleFonts.getFont()`:

```dart
// ❌ WRONG - Adds 6.5MB to bundle!
import 'package:google_fonts/google_fonts.dart';

TextStyle getStyle(String fontFamily) {
  return GoogleFonts.getFont(fontFamily);  // Pulls in ALL font metadata
}

// ✅ CORRECT - Zero bundle impact!
TextStyle getStyle(String fontFamily, TextStyle base) {
  return base.copyWith(fontFamily: fontFamily);  // CSS font-family applied
}

// ✅ CORRECT for TextTheme
TextTheme getTextTheme(String fontFamily, TextTheme base) {
  return base.apply(fontFamily: fontFamily);  // CSS font-family applied
}
```

**How fonts still work:** Browser loads fonts from Google Fonts CDN via `<link>` tags in `index.html` or `@font-face` CSS rules. The font NAME is applied via CSS `font-family`, not the Dart package.

## Files That MUST NOT Import Heavy Packages

These files are in the store's dependency tree. Heavy imports here bloat the store:

```
lib/modules/website/widgets/website_block_renderer.dart     ← Renders store blocks
lib/modules/website/widgets/editable_block_renderer.dart    ← Edit mode blocks
lib/modules/website/theme/website_theme_builder.dart        ← Theme application
lib/public_store/widgets/public_store_layout.dart           ← Store layout wrapper
lib/public_store/pages/*.dart                               ← All store pages
```

## Before Adding ANY New Package

**MANDATORY CHECKLIST:**

1. ✅ **Check package size:** Look at pub.dev for package size indicators
2. ✅ **Check if store needs it:** If only ERP uses it, import ONLY in ERP files
3. ✅ **Test bundle size BEFORE committing:**
   ```bash
   flutter build web --release -t lib/main_store.dart -o build/web_test
   ls -lh build/web_test/main.dart.js
   # Must be ~4.1MB, not higher!
   ```
4. ✅ **Consider alternatives:**
   - Can you use a web-only solution (CSS, JS)?
   - Can you use a lighter package?
   - Can you implement it yourself in <100 lines?

## Import Hygiene Rules

### Rule 1: Never import ERP modules in store code

```dart
// ❌ WRONG - Pulls ALL ERP modules into store bundle!
import '../../shared/routes/erp_routes_barrel.dart';

// ✅ CORRECT - Navigate to ERP via URL, don't import
context.go('/erp/some-page');
```

### Rule 2: Use conditional/deferred imports for heavy features

```dart
// ✅ Deferred import - only loads when actually used
import 'heavy_feature.dart' deferred as heavy;

Future<void> useHeavyFeature() async {
  await heavy.loadLibrary();
  heavy.doSomething();
}
```

### Rule 3: Check what your imports import

A single import can cascade into hundreds of files. Before adding an import:
```bash
# Check what a file imports
grep -r "^import" lib/path/to/file.dart

# Check if a package is used in store-reachable code
grep -r "package:heavy_package" lib/public_store/ lib/modules/website/
```

## Bundle Size Regression Testing

**After ANY change to website or public_store modules:**

```bash
# Quick bundle size check
flutter build web --release -t lib/main_store.dart -o build/web_check
ls -lh build/web_check/main.dart.js

# Expected output:
# -rw-r--r--  4.1M  main.dart.js  ✅ GOOD
# -rw-r--r--  10.8M main.dart.js  ❌ REGRESSION! Find and remove heavy import
```

## Debugging Bundle Size Increases

If bundle size suddenly increases:

1. **Find the commit that broke it:**
   ```bash
   git log --oneline -20
   # Binary search through commits, building and checking size
   ```

2. **Check for new imports:**
   ```bash
   git diff HEAD~5 --stat | grep -E "\.dart$"
   # Look at changed files for new imports
   ```

3. **Check for new packages:**
   ```bash
   git diff HEAD~5 pubspec.yaml
   # Look for added dependencies
   ```

4. **Use bundle analyzer (advanced):**
   ```bash
   flutter build web --release -t lib/main_store.dart --source-maps
   # Analyze with source-map-explorer or similar tool
   ```

## Summary: The Golden Rules

1. ⛔ **NEVER** use `google_fonts` package - use CSS `font-family` instead
2. ⛔ **NEVER** import ERP barrels in store code
3. ✅ **ALWAYS** check bundle size after modifying website/store code
4. ✅ **ALWAYS** verify store is ~4.1MB before deploying
5. 🔍 **INVESTIGATE** immediately if bundle exceeds 5MB

---


# 🔍 SEO & WEBSITE ARCHITECTURE (CRITICAL FOR GOOGLE MERCHANT CENTER)

**⚠️ UNDERSTANDING THIS ARCHITECTURE IS CRITICAL FOR GOOGLE MERCHANT CENTER APPROVAL!**

## Overview: 3 Data Layers

The website has THREE layers of data that must stay in sync:

```
┌─────────────────────────────────────────────────────────────────┐
│                     1. STATIC INDEX.HTML                        │
│  (What Google bot sees BEFORE Flutter loads - ~500ms window)   │
├─────────────────────────────────────────────────────────────────┤
│  Location: web/index.html                                       │
│  Synced via: scripts/sync_seo_index.sh (runs before deploy)    │
│  Contains: meta tags, JSON-LD schema, contact info, legal links│
│  ⚠️ MUST match database values or Google rejects!              │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │ sync_seo_index.sh
                              │
┌─────────────────────────────────────────────────────────────────┐
│                 2. WEBSITE_SETTINGS TABLE (DB)                  │
│         (Central source of truth for site-wide settings)       │
├─────────────────────────────────────────────────────────────────┤
│  Key Settings:                                                  │
│  - contact_email, contact_phone, contact_address                │
│  - store_name, store_description                                │
│  - meta_title, meta_description, meta_keywords                  │
│  - facebook, instagram, twitter, youtube, whatsapp              │
│  - theme_*, header_*, logo_url                                  │
│                                                                 │
│  Accessed via: WebsiteService.getSetting('key', 'default')      │
│  Saved via: WebsiteService.saveSettings({'key': 'value'})       │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────────────────────────────────────────┐
│                3. WEBSITE_PAGES TABLE (DB)                      │
│             (Per-page SEO - each page has its own!)             │
├─────────────────────────────────────────────────────────────────┤
│  Per-Page Fields:                                               │
│  - slug (URL path: 'productos', 'devoluciones', etc.)          │
│  - title (browser tab title)                                    │
│  - meta_title (SEO title - can differ from title)               │
│  - meta_description (SEO description for this page)             │
│  - meta_keywords (page-specific keywords)                       │
│  - og_image_url (social sharing image for this page)           │
│  - is_published (whether page is live)                          │
│                                                                 │
│  ⚠️ ALL 9 pages need SEO configured, not just home!            │
└─────────────────────────────────────────────────────────────────┘
```

## Current Pages (Viñabike)

| Page | Slug | SEO Status | Notes |
|------|------|------------|-------|
| Inicio | `inicio` | NEEDS CHECK | Home page, uses site-wide meta |
| Productos | `productos` | NEEDS CHECK | Product catalog |
| Contacto | `contacto` | NEEDS CHECK | Contact page |
| Sobre Nosotros | `nosotros` | NEEDS CHECK | About page |
| Términos y Condiciones | `terminos` | NEEDS META | Legal page |
| Política de Privacidad | `privacidad` | NEEDS META | Legal page |
| Política de Devoluciones | `devoluciones` | NEEDS META | Legal page (refund) |
| Información de Envíos | `envios` | NEEDS META | Legal page (shipping) |

## Where Data Flows

### Website Footer/Header (LIVE)
- **Source:** `website_settings` table
- **Read by:** `public_store_layout.dart` lines 167-179
- **Keys used:**
  ```dart
  contactEmail = websiteService.getSetting('contact_email', '');
  contactPhone = websiteService.getSetting('contact_phone', '');
  contactAddress = websiteService.getSetting('contact_address', '');
  ```

### Editor Footer Controls (ERP)
- **Location:** `lib/modules/website/widgets/website_editor_panel.dart` (lines ~9198-9410)
- **Source:** Same `website_settings` table
- **Wiring:** `_FooterBlockControlsState._loadSettings()` reads, `_saveSettings()` writes
- **Keys:** Same `contact_email`, `contact_phone`, `contact_address`
- ✅ **NOT mock data** - Editor IS properly wired to database!

### Static index.html (for Google Bot)
- **Location:** `web/index.html`
- **Synced by:** `scripts/sync_seo_index.sh`
- **When synced:** Before every `flutter build web` (in deploy workflow)
- **Contains:**
  - Phone, email, address in hidden SEO div
  - JSON-LD LocalBusiness schema
  - Open Graph meta tags
  - Legal page links (refund, terms, privacy, shipping)

## The Sync Script

**File:** `scripts/sync_seo_index.sh`

**What it does:**
1. Fetches settings from Supabase `website_settings` table
2. Regenerates `web/index.html` with correct values
3. Injects JSON-LD schema, Open Graph, Twitter Cards
4. Adds legal page links

**When it runs:**
- Step 1 of `/deploy_to_firebase` workflow
- Must run BEFORE `flutter build web`

**API used:**
```bash
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/website_settings?tenant_id=eq.${TENANT_ID}&select=key,value"
```

## Business Profile Data Truth (Google Maps / Google Business)

Public storefront business facts must come from connected business data, not page-local placeholders.

This applies to:
- opening / working hours
- address and map links
- phone numbers and WhatsApp numbers
- business name
- review links / Google review metadata
- any future storefront trust data that Google Business Profile or Google Places can provide

**Source-of-truth rule:**
1. Prefer synced Google Business Profile / Google Maps / Google Places data when available.
2. Persist the synced result into `website_settings` so Flutter, SEO sync, and static `index.html` all read the same truth.
3. Render public pages from `WebsiteService.getSetting(...)` / normalized `website_settings` values, not from hardcoded strings.
4. If the data is missing, show an honest fallback such as a Google Maps CTA or an empty state. Never invent schedules, addresses, phone numbers, emails, or other business facts.

**Canonical settings currently used:**
- Business/Profile hours: `google_business_regular_hours`
- Google Places hours fallback: `business_hours_json`
- Google Maps place id: `google_maps_place_id`
- Maps URLs: `seo_google_maps_url`, `business_google_maps_url`, `google_maps_url`
- Review URL: `business_google_review_url`
- Google reviews: `google_reviews_data`, `google_reviews_rating`, `google_reviews_total`, `google_reviews_last_synced_at`, `google_reviews_auto_sync_status`, `google_reviews_auto_sync_error`, `google_reviews_source`
- Contact identity: `store_name`, `business_name`, `contact_address`, `contact_phone`, `business_phone`, `seo_phone`, `contact_email`, `whatsapp`

**Implementation pattern:**
- Google Business Profile sync lives in `lib/modules/website/services/google_business_service.dart` and the website editor sync UI in `lib/modules/website/widgets/website_editor_panel.dart`.
- The `google-business-reviews` Edge Function already fetches Business Profile location data including `regularHours` and `metadata`.
- The `google-places-proxy` Edge Function is the correct server-side path for Google Places details such as `opening_hours`, `place_id`, and canonical Maps URL. Do not expose or call the Places API key directly from public Flutter code.
- The `google-public-data-refresh` Edge Function is the automatic refresh path for public Google review/rating data. It reads saved `google_maps_place_id` + tenant `google_places_api_key`, writes normalized reviews/rating totals back to `website_settings`, and is scheduled in production through `pg_cron` + `pg_net` using a private `GOOGLE_PUBLIC_DATA_REFRESH_SECRET` header. Manual Business Profile review sync may still exist for editor workflows, but public storefront freshness should not depend on a browser session or temporary OAuth provider token.
- Public renderers such as `lib/public_store/pages/contact_page.dart` should support both Google Business Profile `regularHours` and Google Places `opening_hours` payload shapes when displaying hours.

**Before displaying or changing business facts:**
1. Inspect production `website_settings` for the relevant tenant and keys.
2. If synced data is missing, fix the sync/backfill path first instead of adding constants to a page.
3. If Edge Function behavior changes, deploy it with `supabase functions deploy <function-name> --project-ref xzdvtzdqjeyqxnkqprtf`.
4. If Flutter public-store rendering changes, deploy the storefront build so the live site uses the updated parser/UI.
5. Re-check the live page after cache revalidation or hard refresh.

## SEO Settings Page

**Location:** `lib/modules/website/pages/seo_settings_page.dart`

**Route:** `/website/seo`

**What it manages:**
1. Business Info (name, phone, email, full address)
2. Meta Tags (title, description, keywords)
3. Legal Pages (URLs for refund, terms, shipping, privacy)
4. Open Graph (social sharing)
5. Twitter Cards
6. Structured Data (JSON-LD toggles)
7. Analytics (GA, FB Pixel, GTM IDs)

**Key sync behavior:**
- Writes to BOTH `seo_*` prefixed keys AND legacy keys
- Example: Saves `seo_phone` AND `contact_phone` for backward compatibility

## Critical Sync Rules

### ✅ DO
1. Always run sync script before deploy
2. Check ALL pages have SEO configured (not just home)
3. Use SEO Settings page (`/website/seo`) as primary editor
4. Verify legal pages are published AND have meta descriptions

### ❌ DON'T
1. Edit `web/index.html` directly (will be overwritten by sync script)
2. Assume changes are live without deploying
3. Forget that legal pages ALSO need SEO (meta_title, meta_description)
4. Use placeholder data ("+56 9 contacto", "test@test.com")

## Debugging SEO Issues

**If Google Merchant Center rejects:**
1. Check `web/index.html` has correct phone/email (not placeholders)
2. Check ALL 4 legal page links exist in index.html
3. Check legal pages are published (`is_published: true`)
4. Run sync script and redeploy
5. Test with Google Rich Results Test

**If footer shows wrong info:**
1. Check `website_settings` table for `contact_email`, `contact_phone`
2. Verify WebsiteService loaded settings correctly
3. Check for cached data (hard refresh browser)

**If editor changes don't reflect:**
1. Editor DOES save to database (verified)
2. Check save confirmation (green snackbar)
3. Hard refresh the public store page
4. Check browser console for errors

## Per-Page SEO Checklist

For EACH page in `website_pages`, verify:
- [ ] `meta_title` is set (max 60 chars)
- [ ] `meta_description` is set (max 160 chars)
- [ ] `meta_keywords` has relevant terms
- [ ] `og_image_url` has a social sharing image
- [ ] `is_published` is `true`

**Command to check per-page SEO:**
```bash
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/website_pages?tenant_id=eq.5443b130-cc28-45af-a420-cd500b288890&select=slug,meta_title,meta_description,is_published" \
  -H "apikey: $(grep SUPABASE_ANON_KEY lib/shared/config/supabase_config.dart | cut -d\"'\" -f2)" | jq '.'
```

---

# 🔐 AUTHENTICATION, ROLES & PERMISSIONS

**Traceability and granular access control are core to this ERP.**

## 1. Role System (`user_profiles`)
Users are assigned roles in the `user_profiles` table. Logic must respect these hierarchies:
- **`owner`**: Full access to everything in tenant. Can manage subscription.
- **`admin`**: Full access to tenant operations.
- **`manager`**: Can override limits, approve voids, view sensitive financial reports.
- **`employee`**: Standard operational access (POS, Workshops, CRM).
- **`mechanic`**: specialized access for Work Orders and Maintenance.

**Checking Roles:**
- In SQL: `EXISTS (SELECT 1 FROM user_profiles WHERE user_id = auth.uid() AND role IN ('admin', 'manager'))`
- In Flutter: `context.read<AuthProvider>().role`

## 2. Traceability Requirements (Audit Trail)
Every action must be traceable to a specific user. Anonymous operations are forbidden for business data.

### Database Columns
**ALL** transactional and business logic tables (invoices, payments, work_orders, stock_movements, chats) MUST have:
- `created_by uuid references auth.users(id) default auth.uid()`
- `updated_by uuid references auth.users(id)` (if mutable)

### Performance & Metrics
We key analytics off these columns. When building features:
- **Sales by User**: Aggregated from `sales_invoices.created_by`.
- **Productivity**: Tasks/Work Orders completed by user.
- **Commissions**: Calculated based on `created_by` or dedicated `sales_rep_id` column.

## 3. Permission Implementation Layers
1. **RLS (Row Level Security)**:
   - **MANDATORY** for Tenant Isolation (`tenant_id`).
   - Used for basic "Employee vs Customer" data visibility.
2. **RPC / Database Functions** (`SECURITY DEFINER`):
   - **CRITICAL**: Checks roles explicitly inside the function.
   - Example: `delete_conversation` allows Participants OR Admins.
   - *Never rely on RLS alone for destructive RPCs.*
3. **UI State (Flutter)**:
   - Hide/Disable buttons based on role.
   - Use `PermissionGate` widgets where available.

## 4. Best Practices for New Features
1. **Never trust the client**: Verify permissions in the backend (RLS or Function).
2. **Auto-fill User**: Use `default auth.uid()` for `created_by` in new tables.
3. **Log Destructive Actions**: Deleting invoices, voiding payments, or changing critical configs must be logged to `activity_logs`.
4. **Explicit Overrides**: If a regular user needs to perform a Manager action, implement an "Admin Override" flow (ask for admin PIN/Credentials).

---

# 🧱 Modular Architecture

Each module is independent but shares a unified data layer. Modules include:

- **Sales**: Invoices, payments, discounts
- **Purchases**: Purchase orders, supplier credits, receipts
- **Inventory**: Products, stock movements, warehouses
- **Maintenance**: Work orders, parts used, labor cost
- **CRM**: Customer profiles, bike history, loyalty
- **Accounting**: Chart of accounts, journal entries, tax rules
- **HR (RRHH)**: Employees, contracts, attendance, payroll, planning
- **Website Builder**: Product catalog, online orders, CMS
- **Marketing**: Campaigns, email/SMS, customer segmentation
- **Analytics**: Dashboards, KPIs, sales trends, inventory turnover
- **Settings**: Company info, currency, theme, language, timezone

---

# 🔗 Integration Logic

- Online orders from Website Builder deduct inventory and generate invoices
- Marketing campaigns use CRM data and feed into Analytics
- POS, Website, and Maintenance all sync with Inventory and Accounting
- HR data (attendance, payroll) flows into Accounting
- Analytics pulls from all modules for unified dashboards

---

# 💬 Internal Messaging / WhatsApp-Backed Support Inbox

The customer communication platform inside the ERP should be called **Internal Messaging** or the **WhatsApp-backed support inbox**. In Spanish UI/context, use **Mensajería interna** when naming the module concept.

Architecture rule:
- `WhatsAppService` is a transport layer for WhatsApp Cloud API/manual fallback. It is not the screen-level workflow entrypoint for ERP modules.
- ERP actions such as online order coordination, job updates, invoice follow-up, or customer support handoff must create or resolve an internal support conversation and route staff into `/chat?conversation=<conversation_id>`.
- Use `MessagingService`, `ChatProvider`, `EmployeeChatPage`, and `ChatWindow` as the workflow surface. `ChatWindow` is where staff composes/sends the WhatsApp message through the internal UI.
- Preserve business context with `conversation_contexts` / `ensure_whatsapp_conversation_binding` using the existing checked `context_type` vocabulary (`order`, `job`, `invoice`, `bike`, `product`, `customer`) and `context_id`; website online orders use `context_type = 'order'`.
- Do not add direct `WhatsAppService.sendMessage(...)` calls to operational pages just because an action says WhatsApp. If the user should review, edit, or initiate a client conversation, open the internal inbox and optionally prefill a draft there.

Direct transport sends are only appropriate inside the messaging workflow itself or for explicitly approved automated notifications where no staff review is expected.

---

# 🧮 Database Schema (PostgreSQL)

Use normalized tables with foreign keys and constraints. Example:

`sql
CREATE TABLE products (
  id SERIAL PRIMARY KEY,
  name TEXT,
  sku TEXT UNIQUE,
  price NUMERIC,
  cost NUMERIC,
  inventory_qty INTEGER
);

CREATE TABLE orders (
  id SERIAL PRIMARY KEY,
  customer_id INTEGER REFERENCES customers(id),
  source TEXT CHECK (source IN ('POS', 'Website')),
  date TIMESTAMP,
  total NUMERIC
);

CREATE TABLE order_items (
  id SERIAL PRIMARY KEY,
  order_id INTEGER REFERENCES orders(id),
  product_id INTEGER REFERENCES products(id),
  quantity INTEGER,
  price NUMERIC
);
`

Use triggers or service logic to update inventory and accounting entries.

---

# 🔐 Authentication

Use Supabase Auth with OAuth2 (Google, GitHub, etc.) for secure login. Supports:

- Email/password
- Social login
- Role-based access control via Row Level Security (RLS)
- Token expiration and automatic refresh
- Seamless integration with PostgreSQL user tables

---

# 🧭 Navigation Design Rules

- Use minimalistic menu structure with one entry per module
- Avoid redundant submenus like “New Purchase Invoice”
- Use in-page navigation for actions (e.g., “+ New Invoice” button)
- Maintain consistent drawer/sidebar layout across all modules
- Use local routing (Navigator.push, GoRouter) for transitions
- Role-based menu visibility (admin, cashier, mechanic, accountant)

---

## 🔗 Module Integration Rules
- Every new module must:
  - Be imported into `main.dart` (or the central navigation file).
  - Add its main ListPage (e.g., CustomerListPage, InventoryListPage) to the sidebar/drawer.
  - Add a dashboard shortcut if relevant (e.g., “Clientes”, “Inventario”).
  - Ensure navigation works end-to-end: Dashboard → Module → Detail/Form pages.
- No module is considered “done” until it is visible and accessible from the main navigation.


---

# 🎨 GUI Design System

**📘 CRITICAL: Read `.github/GUI_DESIGN_PRINCIPLES.md` for complete design guidelines**

**Core Principles:**
- **Minimalism:** Professional, clean, data-dense (no circus colors/excessive icons)
- **Typography:** 14px body, 13px labels, 18-24px headers
- **Colors:** Neutrals first, one restrained accent only when justified, semantic colors sparingly
- **Tables:** Subtle borders, compact spacing (48px rows), right-align numbers
- **Buttons:** 1 primary (filled), 2-3 secondary (outlined/text), strategic icons only
- **Forms:** Two-column layout (desktop), grouped fields, 12-16px spacing

**Desired tone:** serious ERP clarity first, with a restrained premium/performance edge. The app may feel modern, technical, and polished, but it must not feel playful, childish, or visually noisy.

**⚠️ CRITICAL: Avoid "AI-ish" UI Redesigns**

For ERP/admin screens, default to a restrained business application aesthetic.

- ✅ Prefer calm hierarchy, spacing, typography, and alignment over decorative elements
- ✅ Prefer structure and readability: thumbnail + text + metrics, clean headers, subtle dividers, quiet selected states
- ✅ Use color only to communicate state or priority, not to "make it pop"
- ✅ Keep lists, tables, filters, and detail panes compact, sober, and information-first
- ✅ Make actions obvious through placement, iconography, and contrast, not through visual noise
- ✅ When a screen needs personality, express it through typography, composition, contrast, imagery, and material feel rather than flooding the UI with accent colors
- ✅ Dashboard and summary surfaces should default to restrained tables, compact metrics, and calm status treatments before reaching for colored KPI cards
- ✅ If taking inspiration from premium outdoor/performance brands, translate that into precision, restraint, and technical confidence, not literal sports-marketing styling

- ❌ Do not add colorful chips, gradient cards, glow effects, oversized pills, dashboard-style badges, or random accent blocks unless the screen already uses them consistently
- ❌ Do not turn ERP modules into marketing pages, Dribbble shots, or flashy analytics dashboards
- ❌ Do not solve weak hierarchy by adding more color, more icons, or more containers
- ❌ Do not redesign stable screens into "modern" card soup when a table/list layout is the correct tool
- ❌ Do not introduce visual styles that feel autogenerated, trendy, or detached from the existing desktop ERP language
- ❌ Do not default to bright blue/green accents across unrelated modules just because they feel "safe" or "modern"
- ❌ Do not build rainbow KPI walls, multicolor dashboard cards, or candy-like button systems that make the ERP feel unserious

**Practical rule:** if a UI change would look normal in an accounting system, ERP, POS backoffice, or inventory control app, it is probably on the right track. If it looks like a startup landing page or an AI-generated concept shot, it is wrong.

**When refactoring existing admin UI:**
- Start by improving information hierarchy, spacing, labels, and affordances.
- Reuse existing shared components and page patterns before inventing a new visual language.
- Keep selection states, hover states, and summaries subtle and functional.
- Only add emphasis where it helps users scan faster or avoid mistakes.

**⚠️ CRITICAL: Split-Pane Layout - When to Use**

**Use split-pane ONLY for these specific scenarios:**
- ✅ **List+Detail modules** where user frequently switches between items (invoices, customers, products, accounts)
- ✅ **High-frequency editing** where keeping context visible speeds up workflow
- ✅ **Desktop-focused** modules with complex detail panels

**DO NOT use split-pane for:**
- ❌ **CRUD forms** with create/edit dialogs (medical leaves, contracts, employees, attendance)
- ❌ **Dashboards** or analytics pages
- ❌ **Reports** or read-only views (F29, financial reports)
- ❌ **Settings** or configuration pages
- ❌ **Simple list pages** where detail view doesn't need persistent visibility
- ❌ **Wizards** or multi-step forms

**Reference Implementations:**
- **With split-pane:** `lib/modules/sales/pages/invoice_list_page.dart` (list+detail pattern)
- **Without split-pane:** `lib/modules/hr/pages/medical_leaves_page.dart` (CRUD with dialogs)

**Reference Implementations:**
- **With split-pane:** `lib/modules/sales/pages/invoice_list_page.dart` (list+detail pattern)
- **Without split-pane:** `lib/modules/hr/pages/medical_leaves_page.dart` (CRUD with dialogs)

**Reference Implementation:** `lib/modules/sales/pages/invoice_list_page.dart`

**⚠️ MANDATORY: All pages MUST use `MainLayout` to preserve navigation pane!**

Use a unified widget set across all screens:

- Buttons: consistent style (primary, secondary, danger)
- Forms: reusable components with validation
- Lists: paginated, searchable, filterable
- Modals: consistent layout and behavior
- Icons: use Material Icons or custom SVGs

Support:

- Dark mode toggle (global)
- Language selector (i18n)
- Time zone sync (auto-detect or manual)

---

# � CRITICAL: REALTIME SERVICE INITIALIZATION

**⚠️ NEVER use `async void` in constructor-called methods - causes UI freezing!**

## The Problem

Service constructors calling `async void` methods block UI thread during Supabase realtime subscription setup.

**❌ WRONG - Blocks UI:**
```dart
class CustomerService extends ChangeNotifier {
  CustomerService() {
    _setupCustomersRealtime(); // Freezes app until complete
  }
  
  async void _setupCustomersRealtime() { // ❌ Blocks!
    await Supabase.instance.client.from('customers').stream(...).listen(...);
  }
}
```

**✅ CORRECT - Non-blocking:**
```dart
class CustomerService extends ChangeNotifier {
  CustomerService() {
    _setupCustomersRealtime(); // Returns immediately
  }
  
  Future<void> _setupCustomersRealtime() async { // ✅ Non-blocking!
    await Supabase.instance.client.from('customers').stream(...).listen(...);
  }
}
```

## The Rule

**When creating ANY service with realtime subscriptions:**
- ✅ Use `Future<void>` for setup methods (NOT `async void`)
- ✅ Constructor calls setup method as fire-and-forget
- ✅ Test navigation - should be instant, no freeze

**Why:** `async void` = synchronous blocking call | `Future<void>` = async non-blocking

**See:** `.github/REALTIME_SERVICE_BLOCKING_FIX.md` for detailed documentation

---

# 🚀 PERFORMANCE OPTIMIZATION: SERVICE-LEVEL CACHING

**CRITICAL: Implemented Dec 1, 2025 for Taller module - APPLY TO ALL MODULES**

## The Problem

Navigation between pages in the same module feels slow because:
- Every page calls `_loadData()` on init
- Every `_loadData()` fetches from database
- Even switching between tabs/pages in same module causes full reload
- Users see loading spinners constantly

## The Solution: Service-Level Caching

Cache data at the **service layer** so pages can:
1. Show cached data **instantly** (no loading spinner)
2. Fetch fresh data in background
3. Invalidate cache only when data actually changes

## Implementation Pattern

### 1. Add Caching Infrastructure to Service

```dart
class YourModuleService extends ChangeNotifier {
  // ============================================================
  // CACHING - Avoid refetching on every page navigation
  // ============================================================
  List<YourModel>? _cachedItems;
  DateTime? _itemsCacheTime;
  static const Duration _cacheMaxAge = Duration(minutes: 5);
  
  // Loading state flag to prevent concurrent fetches
  bool _isLoadingItems = false;
  
  // Public getters for cached data (instant access)
  List<YourModel> get cachedItems => _cachedItems ?? [];
  bool get hasItemsCache => _cachedItems != null;
  
  /// Check if cache is still valid
  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheMaxAge;
  }
  
  /// Invalidate cache (call after create/update/delete)
  void invalidateItemsCache() {
    _cachedItems = null;
    _itemsCacheTime = null;
  }
}
```

### 2. Update Fetch Methods to Use Cache

```dart
Future<List<YourModel>> getItems({
  String? filterParam,
  bool forceRefresh = false,
}) async {
  // Check if this is a filtered query (don't use cache for filtered results)
  final isFilteredQuery = filterParam != null && filterParam.isNotEmpty;
  
  // Return cached data if valid and not a filtered query
  if (!forceRefresh && !isFilteredQuery && _isCacheValid(_itemsCacheTime) && _cachedItems != null) {
    debugPrint('📦 [YourService] Using cached items (${_cachedItems!.length} items)');
    return _cachedItems!;
  }
  
  // Prevent concurrent fetches
  if (_isLoadingItems && !isFilteredQuery) {
    debugPrint('⏳ [YourService] Already loading items, waiting...');
    while (_isLoadingItems) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (_cachedItems != null && !isFilteredQuery) return _cachedItems!;
  }
  
  try {
    if (!isFilteredQuery) _isLoadingItems = true;
    
    // Fetch from database...
    final data = await _fetchFromDatabase(filterParam);
    
    // Cache only unfiltered results
    if (!isFilteredQuery) {
      _cachedItems = data;
      _itemsCacheTime = DateTime.now();
      debugPrint('✅ [YourService] Cached ${data.length} items');
    }
    
    return data;
  } finally {
    if (!isFilteredQuery) _isLoadingItems = false;
  }
}
```

### 3. Add Cache Invalidation to ALL CRUD Methods

```dart
Future<YourModel> createItem(YourModel item) async {
  final data = await _db.insert('your_table', item.toJson());
  invalidateItemsCache();  // ⚠️ CRITICAL: Invalidate after mutation
  notifyListeners();
  return YourModel.fromJson(data);
}

Future<YourModel> updateItem(YourModel item) async {
  final data = await _db.update('your_table', item.id!, item.toJson());
  invalidateItemsCache();  // ⚠️ CRITICAL: Invalidate after mutation
  notifyListeners();
  return YourModel.fromJson(data);
}

Future<void> deleteItem(String id) async {
  await _db.delete('your_table', id);
  invalidateItemsCache();  // ⚠️ CRITICAL: Invalidate after mutation
  notifyListeners();
}
```

### 4. Update Page `_loadData()` to Use Cache for Instant Render

```dart
Future<void> _loadData() async {
  // 🚀 INSTANT RENDER: Show cached data immediately if available
  if (_yourService.hasItemsCache && _items.isEmpty) {
    setState(() {
      _items = _yourService.cachedItems;
      _filteredItems = _items;
      _isLoading = false;  // No loading spinner!
    });
    _applyFiltersAndSort();
  } else {
    setState(() => _isLoading = true);
  }
  
  try {
    // Fetch fresh data (will use cache if still valid)
    final items = await _yourService.getItems();
    
    if (mounted) {
      setState(() {
        _items = items;
        _filteredItems = items;
        _isLoading = false;
      });
      _applyFiltersAndSort();
    }
  } catch (e) {
    if (mounted) {
      setState(() => _isLoading = false);
      // Show error...
    }
  }
}
```

## Reference Implementation

**Services WITH Caching (Production-Ready as of Dec 1, 2025):**

| Service | Cache Variables | Preloaded on Login |
|---------|-----------------|---------------------|
| `BikeshopService` | `_cachedJobs`, `_cachedBikes` | ✅ Yes |
| `CustomerService` | `_customersCache` | ✅ Yes |
| `InventoryService` | `_productsCache` | ✅ Yes |
| `CategoryService` | `_categoriesCache` | ✅ Yes |
| `BrandService` | `_brandsCache` | ✅ Yes |
| `SalesService` | `_invoices`, `_payments` | ✅ Yes |
| `PurchaseService` | `_invoiceCache`, `_supplierCache` | ✅ Yes |
| `HRService` | `_employeesCache`, `_departmentsCache` | ✅ Yes |

**Pages WITH Instant Render:**
- `pegas_list_page.dart` - Shows cached jobs instantly
- `pegas_table_page.dart` - Shows cached jobs instantly
- `customer_list_page.dart` - Shows cached customers instantly
- `product_list_page.dart` - Shows cached products instantly
- `category_list_page.dart` - Shows cached categories instantly
- `brand_list_page.dart` - Shows cached brands instantly
- `invoice_list_page.dart` - Uses Provider.watch pattern with cached data
- `purchase_invoice_list_page.dart` - Uses Provider.watch with cached data
- `employee_list_page.dart` - Shows cached employees instantly
- `supplier_list_page.dart` - Shows cached suppliers instantly

**DataPreloadService** (`lib/shared/services/data_preload_service.dart`):
- Initializes after authentication
- Preloads ALL cached data in parallel on login
- Reduces first navigation time from ~500ms to ~50ms

## Cache Configuration

| Setting | Value | Reason |
|---------|-------|--------|
| `_cacheMaxAge` | 5 minutes | Balance between freshness and performance |
| Concurrent fetch wait | 50ms polling | Prevent duplicate requests |
| Filtered queries | Always fetch | Filters may not match cache |

## When to Apply This Pattern

**APPLY TO:**
- ✅ Any module with list pages (inventory, sales, purchases, CRM, HR)
- ✅ Services that are called frequently during navigation
- ✅ Data that doesn't change every second

**DO NOT APPLY TO:**
- ❌ Realtime data (use Supabase realtime subscriptions instead)
- ❌ Dashboard/analytics (always show fresh data)
- ❌ Single-record fetches (getById) - no benefit

## Checklist for New Modules

When creating a new module:

1. ✅ **Add cache variables** to service: `_cachedItems`, `_itemsCacheTime`, `_isLoadingItems`
2. ✅ **Add public getters**: `cachedItems`, `hasItemsCache`
3. ✅ **Add invalidation method**: `invalidateItemsCache()`
4. ✅ **Update fetch method** with cache logic (see pattern above)
5. ✅ **Add invalidation calls** to ALL CRUD methods (create, update, delete, softDelete, restore)
6. ✅ **Update page `_loadData()`** to show cached data instantly
7. ✅ **Add service to DataPreloadService** for preloading on login
8. ✅ **Test navigation** - should feel instant, no loading spinners on second visit

## Services Pending Optimization

These services may benefit from caching if frequently used:

- ⏳ `AccountingService` → Chart of accounts, Journal entries (large datasets)
- ⏳ `StockMovementsService` → Stock movement history
- ⏳ `SmartTaskService` → Task templates

## Debugging Cache

Add these debug prints to track cache behavior:

```dart
debugPrint('📦 Using cached items');      // Cache hit
debugPrint('⏳ Already loading, waiting'); // Concurrent fetch prevented
debugPrint('✅ Cached ${items.length}');   // Cache stored
debugPrint('🗑️ Cache invalidated');        // After mutation
```

---

# 🖼️ SPACE MANAGEMENT & RESPONSIVE UI PATTERNS

**CRITICAL LESSONS LEARNED FROM PRODUCTION TESTING (Oct 31, 2025)**

## 1. Resizable Navigation Pane

**Pattern:** User-adjustable sidebar width with persistence

**Implementation:**
```dart
// NavigationService (shared/services/navigation_service.dart)
class NavigationService extends ChangeNotifier {
  static const double _minDrawerWidth = 200;
  static const double _maxDrawerWidth = 400;
  static const double _defaultDrawerWidth = 280;
  double _drawerWidth = _defaultDrawerWidth;
  
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _drawerWidth = prefs.getDouble('navigation_drawer_width') ?? _defaultDrawerWidth;
    notifyListeners();
  }
  
  void updateDrawerWidth(double newWidth) {
    _drawerWidth = newWidth.clamp(_minDrawerWidth, _maxDrawerWidth);
    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble('navigation_drawer_width', _drawerWidth);
    });
    notifyListeners();
  }
}

// MainLayout (shared/widgets/main_layout.dart)
Row(
  children: [
    // Sidebar with dynamic width
    AnimatedContainer(
      width: navigationService.drawerWidth,
      child: AppSidebar(),
    ),
    // Main content area with left border (serves as resize handle)
    Expanded(
      child: Container(
        decoration: navigationService.isDrawerVisible
            ? BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              )
            : null,
        child: MouseRegion(
          cursor: navigationService.isDrawerVisible 
              ? SystemMouseCursors.resizeColumn 
              : MouseCursor.defer,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: navigationService.isDrawerVisible
                ? (details) {
                    navigationService.updateDrawerWidth(
                      navigationService.drawerWidth + details.delta.dx,
                    );
                  }
                : null,
            child: Column(
              children: [
                // App bar and content...
              ],
            ),
          ),
        ),
      ),
    ),
  ],
)
```

**Key Principles:**
- ✅ Use `SharedPreferences` to persist user preference
- ✅ Clamp width to reasonable min/max (200-400px)
- ✅ Use `MouseRegion` with `SystemMouseCursors.resizeColumn` for visual feedback
- ✅ Use `GestureDetector.onHorizontalDragUpdate` for drag handling
- ✅ **CRITICAL:** The 1px border IS the visual divider - no separate resize handle
- ✅ **CRITICAL:** Wrap the entire content Column with MouseRegion + GestureDetector, not a separate widget
- ✅ **CRITICAL:** Border must be on the Container wrapping the content, not on a separate resize handle
- ✅ This ensures horizontal lines extend fully without gaps
- ✅ `notifyListeners()` for real-time UI updates

**Common Mistakes to AVOID:**
- ❌ Creating a separate resize handle widget between sidebar and content
- ❌ Adding extra width for the resize handle (creates gaps in horizontal dividers)
- ❌ Putting the border on the resize handle instead of the content area
- ❌ Using a thick transparent area for dragging (makes UI look broken)

**Apply To:** Any resizable panel (sidebar, detail panels, split views)

---

## 2. Responsive Table Layout with Horizontal Scroll

**Pattern:** Tables that shrink to minimum width but use available space

**Implementation:**
```dart
// Sales Invoice Line Items (modules/sales/pages/invoice_form_page.dart)
// Column width constants
static const double _colIndexWidth = 40;
static const double _colQuantityWidth = 120;
static const double _colPriceWidth = 130;
static const double _colDiscountWidth = 130;
static const double _colTotalWidth = 130;
static const double _colActionsWidth = 48;

Widget _buildLineItemsSection() {
  return LayoutBuilder(
    builder: (context, constraints) {
      const minTableWidth = 800.0; // Reduced from 900
      final tableWidth = constraints.maxWidth > minTableWidth 
          ? constraints.maxWidth 
          : minTableWidth;
      
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: Column(
            children: [
              _buildTableHeader(),
              ..._lineItems.map((item, index) => _buildLineRow(item, index)),
            ],
          ),
        ),
      );
    },
  );
}

// Product column with minimum width
Container(
  constraints: BoxConstraints(
    minWidth: 250, // Reduced from 300
    maxWidth: tableWidth - fixedColumnsWidth,
  ),
  child: ProductAutocompleteField(...),
)
```

**Key Principles:**
- ✅ Use `LayoutBuilder` to detect available width
- ✅ Define minimum table width (typically 800px for complex tables)
- ✅ Use `constraints.maxWidth` when available space > minimum
- ✅ Wrap in `SingleChildScrollView` with `Axis.horizontal` for overflow
- ✅ Set `minWidth` on flexible columns (e.g., product name 250px)
- ✅ Fixed columns use exact widths (e.g., index 40px, actions 48px)
- ✅ Flexible column takes remaining space: `maxWidth: tableWidth - fixedColumnsWidth`

**Apply To:** Any data table, invoice line items, product lists, grid views

---

## 3. Overlay Dropdowns with Scroll Tracking

**Pattern:** Dropdown that follows parent widget when page scrolls

**Problem:** Absolute positioning (`Positioned` with `localToGlobal`) doesn't update on scroll

**Solution:** Use `CompositedTransformFollower` with `LayerLink`

**Implementation:**
```dart
// ProductAutocompleteField (shared/widgets/product_autocomplete_field.dart)
class _ProductAutocompleteFieldState extends State<ProductAutocompleteField> {
  final LayerLink _layerLink = LayerLink();
  
  void _showOverlay() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    
    // Minimum 300px width for dropdown (even if field is narrow)
    final dropdownWidth = size.width < 300 ? 300.0 : size.width;
    
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: dropdownWidth, // Fixed minimum width
        child: CompositedTransformFollower(
          link: _layerLink, // Tracks target position
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4), // 4px gap below field
          child: Material(
            elevation: 8,
            child: _buildDropdownContent(),
          ),
        ),
      ),
    );
    
    Overlay.of(context).insert(_overlayEntry!);
  }
  
  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink, // Links target to follower
      child: TextField(...),
    );
  }
}
```

**Key Principles:**
- ✅ Use `LayerLink` to connect target widget and overlay
- ✅ Wrap target in `CompositedTransformTarget`
- ✅ Use `CompositedTransformFollower` for overlay (NOT `Positioned` with absolute coordinates)
- ✅ Set minimum width for dropdown content (e.g., 300px for product search)
- ✅ Dropdown automatically follows target when scrolling
- ✅ Add small offset (4px) for visual separation

**Apply To:** Autocomplete fields, custom dropdowns, context menus, tooltips

---

## 4. Overlay Click Handling with Focus Delay

**Pattern:** Prevent overlay from closing before tap events register

**Problem:** Focus loss triggers overlay removal before tap completes

**Solution:** 200ms delay before removing overlay

**Implementation:**
```dart
_focusNode.addListener(() {
  if (_focusNode.hasFocus) {
    _showOverlay();
  } else {
    // Add delay to allow tap events to complete
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!_focusNode.hasFocus && mounted) {
        _removeOverlay();
      }
    });
  }
});

// Wrap dropdown items in InkWell for better tap detection
MouseRegion(
  child: ListView.builder(
    itemBuilder: (context, index) {
      return InkWell( // Better than ListTile onTap
        onTap: () => _onProductSelected(product),
        child: ListTile(
          title: Text(product.name),
          subtitle: Text('SKU: ${product.sku}'),
        ),
      );
    },
  ),
)
```

**Key Principles:**
- ✅ Use `Future.delayed(Duration(milliseconds: 200))` before removing overlay
- ✅ Check `mounted` before removing overlay (widget may be disposed)
- ✅ Wrap list items in `InkWell` (more reliable than `ListTile.onTap`)
- ✅ Use `MouseRegion` to keep overlay open when mouse hovers
- ✅ 200ms is the sweet spot (100ms too fast, 300ms feels sluggish)

**Apply To:** Any overlay with clickable content (autocomplete, menus, pickers)

---

## 5. Hover-Based UI Elements (Desktop)

**Pattern:** Show actions/controls only when hovering over specific areas

**Implementation:**
```dart
// Sales Invoice Line Items - Hover-based reorder arrows
Widget _buildLineRow(LineItem item, int index) {
  return StatefulBuilder(
    builder: (context, setState) {
      bool isHovered = false;
      
      return MouseRegion(
        onEnter: (_) => setState(() => isHovered = true),
        onExit: (_) => setState(() => isHovered = false),
        child: Row(
          children: [
            // Index column
            SizedBox(
              width: _colIndexWidth,
              child: Text('${index + 1}'),
            ),
            // Product column
            Expanded(child: ProductField(...)),
            // Actions column with conditional arrows
            SizedBox(
              width: _colActionsWidth,
              child: Row(
                children: [
                  if (isHovered && index > 0)
                    IconButton(
                      icon: Icon(Icons.arrow_upward, size: 16),
                      onPressed: () => _moveLineUp(index),
                    ),
                  if (isHovered && index < _lineItems.length - 1)
                    IconButton(
                      icon: Icon(Icons.arrow_downward, size: 16),
                      onPressed: () => _moveLineDown(index),
                    ),
                  IconButton(
                    icon: Icon(Icons.delete, size: 16),
                    onPressed: () => _removeLine(index),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
```

**Key Principles:**
- ✅ Use `StatefulBuilder` for per-row hover state (not setState on whole list)
- ✅ Use `MouseRegion` with `onEnter`/`onExit` callbacks
- ✅ Conditional rendering: `if (isHovered) Widget(...)`
- ✅ Keep hover state local to the widget (not global state)
- ✅ Use small icons (size: 16) for compact inline actions
- ✅ Always show critical actions (delete), hide secondary actions (reorder)

**Apply To:** List items, table rows, cards, inline editing

---

## 6. Duplicate Items Handling in Lists

**Pattern:** Allow same product/item on multiple lines (no auto-merge)

**Problem:** Users expect e-commerce behavior (same product = separate lines, each customizable)

**Implementation:**
```dart
// DON'T merge duplicates
void _addProductLine(ProductSelection selection) {
  // ❌ OLD: Check for duplicates and increment quantity
  // final existingIndex = _lineItems.indexWhere((item) => 
  //     item.productId == selection.product?.id);
  // if (existingIndex >= 0) {
  //   _lineItems[existingIndex].quantity += 1;
  //   return;
  // }
  
  // ✅ NEW: Always create new line
  setState(() {
    _lineItems.add(LineItem(
      productId: selection.product?.id,
      productName: selection.displayText,
      quantity: 1,
      price: selection.product?.price ?? 0,
    ));
  });
}
```

**Key Principles:**
- ✅ Each line is independent (separate quantity, discount, notes)
- ✅ User can manually adjust quantities if they want consolidation
- ✅ Matches e-commerce UX (Amazon, Shopify, etc.)
- ✅ Allows different discounts per line for same product
- ✅ Simpler code (no duplicate detection logic)

**Apply To:** Invoice line items, cart items, order items, parts lists

---

## 7. Grid Table Layout Guidelines

**When to use Grid Tables:**
- Invoice line items (5+ columns)
- Product lists with multiple attributes
- Financial tables (journals, ledgers)
- Any table with mixed input types (text, numbers, dropdowns)

**Column Width Strategy:**
```dart
// Fixed columns (exact widths)
const double _colIndexWidth = 40;      // Row number
const double _colActionsWidth = 48;    // Icon buttons
const double _colQuantityWidth = 120;  // Number inputs
const double _colPriceWidth = 130;     // Currency values
const double _colDiscountWidth = 130;  // Percentage/amount

// Flexible column (takes remaining space)
// Product name, description, notes
final productColumnWidth = tableWidth - (
  _colIndexWidth + _colQuantityWidth + _colPriceWidth + 
  _colDiscountWidth + _colTotalWidth + _colActionsWidth
);
```

**Column Sizing Rules:**
- **Index/Row#:** 40px (max 2-digit numbers)
- **Actions (icons):** 48px (Material design touch target)
- **Numeric inputs:** 120-130px (fits 6-8 digits)
- **Text/Description:** Flexible (minWidth: 250px, takes remaining space)
- **Checkbox:** 48px (touch target)

**Apply To:** Any complex data table with multiple column types

---

## 8. Common GUI Mistakes to AVOID

❌ **Using absolute positioning for scrollable content**
- Overlays detach from parent when scrolling
- Use `CompositedTransformFollower` instead

❌ **Fixed widths on flexible content**
- Product names, descriptions need to expand
- Use `minWidth` constraints, not fixed `width`

❌ **No minimum width on dropdowns**
- Narrow fields create unreadable dropdowns
- Always set minimum (e.g., 300px for product search)

❌ **Auto-merging duplicate items**
- Users expect separate lines for flexibility
- Let users manually consolidate if needed

❌ **Removing overlays immediately on focus loss**
- Tap events don't have time to register
- Add 200ms delay before removal

❌ **Global hover state for lists**
- Causes entire list to rebuild on hover
- Use `StatefulBuilder` for per-row state

❌ **Non-resizable panels on desktop**
- Different workflows need different layouts
- Add drag handles with `SharedPreferences` persistence

❌ **Tables that don't use available space**
- Wasted whitespace on large screens
- Use `LayoutBuilder` + `constraints.maxWidth`

---

## 9. Quick Reference: Apply These Patterns

When creating **any form with line items** (invoices, orders, carts):
1. Use grid table layout with fixed + flexible columns
2. Set minTableWidth to 800px (or appropriate for your columns)
3. Wrap in `LayoutBuilder` + `SingleChildScrollView(horizontal)`
4. Allow duplicate products on separate lines
5. Add hover-based reorder arrows (desktop only)

When creating **any autocomplete/search field**:
1. Use `CompositedTransformFollower` + `LayerLink` for overlay
2. Set minimum dropdown width (300px for product search)
3. Add 200ms delay before removing overlay on focus loss
4. Wrap items in `InkWell` for reliable tap detection
5. Use `MouseRegion` to keep overlay open on hover

When creating **any resizable panel**:
1. Add width management to service (`ChangeNotifier`)
2. Use `SharedPreferences` to persist user preference
3. Add `MouseRegion` with resize cursor
4. Use `GestureDetector.onHorizontalDragUpdate` for dragging
5. Clamp width to reasonable min/max

**These patterns are PRODUCTION-TESTED and should be reused across ALL modules.**

---

# 🌍 Localization & Regional Context

App is primarily used in Chile

- Currency: CLP (Chilean Peso)
- Tax: IVA (19%), applied to invoices and purchases
- Language: Spanish (default), English (optional)
- Date format: DD/MM/YYYY
- Time zone: America/Santiago

---

# 🏪 BUSINESS DATA - VIÑABIKE (Primary Tenant)

**Use this data whenever creating content, policies, or UI that references the business:**

| Campo | Valor |
|-------|-------|
| **Nombre comercial** | Viñabike |
| **Dirección** | Álvarez 32, Local 17 |
| **Código postal** | 2520000 |
| **Ciudad** | Viña del Mar |
| **Región** | Valparaíso |
| **País** | Chile |
| **Teléfono** | +56 9 9835 7797 |
| **Email** | vinabikechile@gmail.com |
| **Métodos de pago web** | Mercado Pago, Transferencia bancaria |
| **Horario** | Lunes a Viernes 10:00 - 19:00, Sábado 10:00 - 14:00 |
| **Subdomain** | vinabike |

**⚠️ IMPORTANT:**
- Use Spanish terminology: "Región" (not "Estado"), "Código postal" (not "ZIP code")
- Format phone as `+56 9 XXXX XXXX` (Chilean mobile format)
- Currency always in CLP with proper thousand separators: `$49.990`

---

# 👥 HR & Workforce Management (RRHH)

Include the following modules:

- Employees: personal data, job title, department
- Contracts: salary, working hours, legal terms
- Attendance: clock-in/out, calendar view, kiosk mode
- Payroll: salary computation, tax, payment status
- Planning: shift scheduling, technician availability
- Leaves: vacation, sick leave, approval workflows
- Timesheets: logged hours per task/project
- Roles & Permissions: access control per module

---

# 🌐 Website Builder - COMPLETE ARCHITECTURE

**CRITICAL: The Website Builder is a visual, block-based CMS. ALL content must be editable through the UI - NEVER hardcode content in code or SQL!**

## 🏆 Public Store Quality Bar (April 2026)

The public storefront is not a demo surface.

It is a revenue, trust, and brand surface, and it must be held to the standard of a professional commerce website.

Agents working on the website must optimize for broad product quality principles, not one-off local styling preferences.

**This section is intentionally about general doctrine, not component-specific mandates.**

Use concrete examples such as sticky headers, compact checkout chrome, or trust badges only to justify a larger UX rule, never as the rule itself.

### 1. UX Standard: reduce friction, preserve orientation, make actions obvious

- Primary journeys must feel simple and reliable: discover products, understand the offer, add to cart, check out, and find support.
- Navigation must stay predictable across the whole storefront. If the same concept exists in multiple places, it must behave the same way.
- The UI should minimize cognitive load: clear hierarchy, clear labels, clear next step, and no unnecessary distractions in task-focused flows.
- Browsing flows and transactional flows may differ in chrome density, but that difference must be intentional and user-task-driven, not accidental drift.
- Checkout, login, account, cart, and order confirmation must feel trustworthy and calm, not like marketing pages or admin leftovers.
- Do not ship flows that require the user to infer system state from subtle visual quirks. State, errors, required fields, loading, and success outcomes must be explicit.

### 2. UI Standard: premium, restrained, and consistent

- Default to a polished ecommerce aesthetic: strong hierarchy, measured spacing, disciplined typography, and consistent alignment.
- Use emphasis intentionally. Visual weight should come from layout, contrast, and typography before it comes from color or decoration.
- Avoid noisy or cheap-looking UI: random gradients, crowded badges, inconsistent iconography, oversized pills, decorative clutter, or visibly hacked-together route-specific layouts.
- Shared surfaces must look shared. Header, footer, navigation, cards, filters, forms, product media, and trust messaging must use one cohesive visual language.
- Responsiveness must preserve intent, not just avoid overflow. Mobile, tablet, and desktop should feel like the same site with the same information architecture.

### 3. Trust and Security Standard: never erode buyer confidence

- The storefront must never leak admin/editor affordances, internal tools, debug remnants, or implementation artifacts into public-facing flows.
- Authentication state must be explicit and intentional. Do not let stale local state, cached sessions, or debug-only leftovers masquerade as real storefront truth.
- Payment and checkout flows must communicate legitimacy: secure handling, clear totals, clear fulfillment expectations, and no ambiguous or contradictory messaging.
- Use conservative defaults around security-sensitive UX. If a state could confuse users about who is signed in, what they are paying, or whether a flow is official, treat that as a quality bug.
- Public-store validation and data access must remain tenant-safe and production-safe. Do not relax tenant boundaries, auth semantics, or sensitive-data protections for convenience.

### 4. Engineering Standard for Website Work

- Prefer systemic fixes over page-local hacks. If a website inconsistency is caused by shared shell, navigation, cache, auth bootstrapping, or renderer drift, fix it at the shared layer.
- Keep debug and preview environments deterministic. Local validation should resemble production behavior closely enough to be trustworthy.
- When a local debug surface intentionally differs from production, make that difference explicit and controlled through configuration rather than hidden browser/session residue.
- Performance is part of UX quality. Protect bundle size, first render, navigation responsiveness, and image/media loading behavior.
- Treat website regressions as product-quality issues, not cosmetic issues, when they affect orientation, trust, checkout confidence, or perceived legitimacy.

### 5. Decision Rule for Future Website Changes

When choosing between alternatives, prefer the option that best satisfies all of these together:

1. clearer user intent
2. lower friction in key sales flows
3. stronger trust and perceived legitimacy
4. more consistent behavior across pages and breakpoints
5. less architectural drift in shared website systems

If a change improves one page while making the overall storefront less coherent, less trustworthy, or harder to reason about, it is not the right change.

## ⚡ Public Store Performance & Freshness Doctrine (May 2026)

The public storefront uses a deliberate fast-first-render / fast-revalidation model. Do not replace it with sticky caches that make website-editor changes slow to appear.

The current intended architecture is:

- `lib/main_store.dart` initializes `SharedPreferences` before the app starts and injects it into `WebsiteService`.
- `PublicStoreBootstrap` detects the tenant, optionally hydrates a synchronous local cache, renders the storefront quickly, then revalidates in the background.
- `WebsiteService.preloadPublicStoreFromSynchronousCache()` may hydrate settings, blocks, and navigation only when the local cache is fresh according to `website_public_store_last_refresh_<tenantId>`.
- `WebsiteService.loadPublicStoreDataUnified(forceRefresh: true)` must bypass JS prefetch and edge cache, reading origin data directly so editor changes repair the first paint quickly.
- The normal fast path may use JS prefetch / edge cache, but the origin revalidation after first paint is mandatory.

Deployment/cache rules:

- Store builds must keep using `flutter build web --release --pwa-strategy=none -t lib/main_store.dart -o build/web_store` unless a replacement invalidation strategy is explicitly designed and tested.
- Firebase headers for `index.html`, `flutter_bootstrap.js`, `flutter.js`, `main.dart.js`, manifest/version files, asset manifests, and service-worker files must remain `Cache-Control: public, max-age=0, must-revalidate` or equally fresh.
- Long-lived caching is acceptable for immutable/static media assets such as product images, optimized images, icons, and generated snapshots, not for Flutter boot/runtime files or website JSON truth.
- Do not increase the public-store bootstrap TTL or add service-worker/CDN persistence without proving that website block/theme/navigation edits still appear within one post-paint origin refresh.
- Debug reset flags such as `PUBLIC_STORE_DEBUG_RESET_LOCAL_STATE` must stay local/debug-only and must never be required for normal production freshness.

When optimizing first-load speed, improve parallelism, bundle size, image payloads, or edge warm-up first. Treat slower website-editor reflection as a regression, even if Lighthouse improves.

---

## 🚨 CRITICAL: EDITOR ARCHITECTURE (Dec 2025)

**There is ONE editor system - the INLINE EDITOR. No other editor exists.**

### The Inline Editor System

The website is edited **inline** - users see the actual website preview and click elements to edit them. A side panel provides additional editing tools.

**Core Components:**

| File | Purpose | Lines |
|------|---------|-------|
| `lib/public_store/widgets/public_store_layout.dart` | Layout wrapper, shows edit button, renders panel | ~1600 |
| `lib/modules/website/widgets/website_editor_panel.dart` | Side panel with tabs: Agregar/Editar/Tema | ~6600 |
| `lib/modules/website/providers/website_edit_mode_provider.dart` | State management for edit mode | ~560 |
| `lib/modules/website/widgets/editable_block_renderer.dart` | Makes blocks clickable/selectable | ~2800 |
| `lib/public_store/pages/public_home_page.dart` | HOME page with full editing support | ~800 |

### How It Works

```
User clicks "Editar Sitio" button
         ↓
public_store_layout.dart calls editProvider.enterPreviewMode()
         ↓
Top bar appears with "Editar" button
         ↓
User clicks "Editar" → editProvider.switchToEditMode()
         ↓
WebsiteEditorPanel appears on right side (dark panel)
         ↓
Blocks become clickable via EditableBlockRenderer
         ↓
Selected block shows in "Editar" tab with field editors
         ↓
User saves → WebsiteService.saveBlocks()
```

### Edit Modes

1. **Normal Mode** (`isEditMode = false`, `isPreviewMode = false`)
   - Regular visitor view
   - "Editar Sitio" floating button visible for logged-in admins

2. **Preview Mode** (`isPreviewMode = true`)
   - Top bar appears with "Editar" button
   - Site looks normal but ready to edit
   - **Activated by:** `/tienda?preview=true` or clicking "Vista Previa" button

3. **Edit Mode** (`isEditMode = true`)
   - Side panel visible (WebsiteEditorPanel)
   - Blocks are clickable/selectable
   - Changes tracked for save
   - **Activated by:** `/tienda?edit=true` or clicking "Abrir Editor" button

### URL Parameters (Dec 2025)

| URL | Mode | What User Sees |
|-----|------|----------------|
| `/tienda` | Normal | Store with "Editar Sitio" FAB (if logged in) |
| `/tienda?preview=true` | Preview | Store with elegant top bar (Publicado toggle, Editar button) |
| `/tienda?edit=true` | Edit | Store with side panel editor (full editing capability) |

### Entry Points from Website Management Page

| Button | Action | Result |
|--------|--------|--------|
| "Vista Previa" | `context.go('/tienda?preview=true')` | Preview mode with top bar |
| "Abrir Editor" | `context.go('/tienda?edit=true')` | Edit mode with side panel |
| "Nueva Pestaña" | `launchUrl('/tienda')` | Opens in new browser tab (no editor) |

---

## ⚠️ KNOWN LIMITATION: Multi-Page Editing (Dec 2025)

**CURRENT STATE: Only HOME page supports inline editing!**

### The Problem

| Page Type | Editing Support | Why |
|-----------|-----------------|-----|
| Home Page (`/tienda`) | ✅ Full editing | Uses `public_home_page.dart` with `EditableBlockRenderer` |
| Policy Pages (`/pagina/:slug`) | ❌ READ ONLY | Uses `dynamic_website_page.dart` with `WebsiteBlockRenderer` (no edit support) |

### Root Cause

`DynamicWebsitePage` (used for `/pagina/:slug` routes) does NOT:
- Import `WebsiteEditModeProvider`
- Use `EditableBlockRenderer`
- Connect to the inline editor system

It only uses `WebsiteBlockRenderer` which is **read-only**.

### Future Implementation Required

To enable editing on ALL pages:

1. **Modify `DynamicWebsitePage`:**
   - Import and watch `WebsiteEditModeProvider`
   - When `isEditMode = true`, use `EditableBlockRenderer` instead of `WebsiteBlockRenderer`
   - Load page-specific blocks into `editProvider` when entering edit mode

2. **Modify `public_store_layout.dart`:**
   - Detect current page slug from route
   - Pass current page ID to `WebsiteEditorPanel`
   - Load correct blocks for current page (not just home page)

3. **Modify `WebsiteService`:**
   - Track "current editing page" in state
   - `saveBlocks()` should save to correct page_id

**For now:** Edit policy pages via SQL or create a dedicated page editor (not inline).

---

## 🗑️ DELETED FILES (Dec 2025)

The following files were REMOVED because they caused confusion:

| Deleted File | Reason |
|--------------|--------|
| `odoo_style_editor_page.dart` | Standalone editor that was NEVER used - caused massive confusion |
| `website_editor_page.dart` | Wrapper that just returned OdooStyleEditorPage |

**The `/website/editor` route has been removed.** All editing happens inline via the public store.

---

## Core Architecture

### Database Tables
```sql
-- Pages (multi-page support)
website_pages (
  id, tenant_id, slug, title, is_published, is_home, is_system, template, meta_description, created_at, updated_at
)

-- Blocks (visual components)
website_blocks (
  id, tenant_id, page_id, block_type, order_index, is_visible, block_data JSONB, created_at, updated_at
)

-- Settings (theme, contact info, etc)
website_settings (
  id, tenant_id, key, value, created_at, updated_at
)
```

### Block System

**Block Types Available** (`lib/modules/website/models/website_block_type.dart`):
```dart
enum WebsiteBlockType {
  hero,           // Banner with title, subtitle, CTA button, background image
  carousel,       // Multi-slide hero with navigation
  products,       // Product grid from inventory
  services,       // Service cards with icons
  about,          // Company info with image
  testimonials,   // Customer reviews
  features,       // Feature/benefit grid
  cta,            // Call-to-action section
  gallery,        // Image gallery
  contact,        // Contact form
  faq,            // Accordion FAQ
  pricing,        // Pricing plans
  team,           // Team member cards
  stats,          // Statistics/metrics
  footer,         // Page footer
  categoryGrid,   // Category cards with images
  videoBanner,    // Video background section
  partnersBanner, // Partners/sponsors
  brandLogos,     // Brand logo carousel
}
```

### Block Data Structure

Each block stores its configuration in `block_data` JSONB:
```json
{
  "title": "Welcome to Vinabike",
  "subtitle": "Your cycling partner",
  "buttonText": "Shop Now",
  "buttonLink": "/productos",
  "backgroundImage": "https://...",
  "overlayColor": "#000000",
  "overlayOpacity": 0.35,
  "visibility": {
    "desktop": true,
    "tablet": true,
    "mobile": true
  }
}
```

---

## 🎨 Visual Editor Features (MUST PRESERVE)

### 1. Inline Text Editing
**Location:** `lib/modules/website/widgets/inline_editable_text.dart`

Users can click on ANY text element and edit it directly in the preview:
```dart
InlineEditableText(
  text: data['title'] ?? '',
  isEditMode: true,  // Enable inline editing
  onChanged: (newText) => _updateBlockData(block, 'title', newText),
  style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
)
```

**RULE:** Every text field in a block MUST use `InlineEditableText` for direct editing.

### 2. Inline Image Editing
**Location:** `lib/modules/website/widgets/inline_editable_image.dart`

Users can click on images to upload/replace:
```dart
InlineEditableImage(
  imageUrl: data['backgroundImage'],
  isEditMode: true,
  onChanged: (newUrl) => _updateBlockData(block, 'backgroundImage', newUrl),
  width: double.infinity,
  height: 400,
)
```

**RULE:** Every image in a block MUST use `InlineEditableImage` for click-to-upload.

### 3. Block Field Schema System
**Location:** `lib/modules/website/models/website_block_definition.dart`

Every block defines its editable fields:
```dart
WebsiteBlockDefinition(
  type: WebsiteBlockType.hero,
  title: 'Hero / Banner',
  fields: [
    WebsiteBlockFieldSchema(
      key: 'title',
      label: 'Título',
      type: WebsiteBlockFieldType.text,
    ),
    WebsiteBlockFieldSchema(
      key: 'buttonText',
      label: 'Texto del botón',
      type: WebsiteBlockFieldType.text,
    ),
    WebsiteBlockFieldSchema(
      key: 'buttonLink',
      label: 'Enlace del botón',
      type: WebsiteBlockFieldType.text,
    ),
    WebsiteBlockFieldSchema(
      key: 'backgroundImage',
      label: 'Imagen de fondo',
      type: WebsiteBlockFieldType.image,
    ),
  ],
)
```

### 4. Field Types Available
```dart
enum WebsiteBlockFieldType {
  text,      // Single line text
  textarea,  // Multi-line text
  richtext,  // Rich text editor (HTML)
  color,     // Color picker
  image,     // Image upload
  number,    // Numeric input
  toggle,    // Boolean switch
  select,    // Dropdown options
  chips,     // Tag/chip list
  repeater,  // Repeatable items (testimonials, team members, etc.)
}
```

### 5. Repeater Fields (Lists)
For blocks with multiple items (testimonials, services, team):
```dart
WebsiteBlockFieldSchema(
  key: 'services',
  label: 'Servicios',
  type: WebsiteBlockFieldType.repeater,
  itemLabel: 'Servicio',
  minItems: 1,
  itemFields: [
    WebsiteBlockFieldSchema(key: 'icon', label: 'Ícono', type: WebsiteBlockFieldType.select),
    WebsiteBlockFieldSchema(key: 'title', label: 'Título', type: WebsiteBlockFieldType.text),
    WebsiteBlockFieldSchema(key: 'description', label: 'Descripción', type: WebsiteBlockFieldType.textarea),
  ],
)
```

---

## 🚨 CRITICAL RULES FOR WEBSITE DEVELOPMENT

### ❌ NEVER DO THIS:
```sql
-- WRONG: Hardcoding content in SQL
INSERT INTO website_blocks (block_data) VALUES ('{
  "content": "<h1>Hardcoded Title</h1><p>Hardcoded paragraph...</p>"
}');
```

```dart
// WRONG: Hardcoding content in Dart
Widget build(context) {
  return Text('Welcome to Vinabike'); // Hardcoded!
}
```

### ✅ ALWAYS DO THIS:
```dart
// CORRECT: Read from block_data, editable through UI
Widget build(context) {
  final title = data['title'] ?? 'Default Title';
  return InlineEditableText(
    text: title,
    isEditMode: isEditMode,
    onChanged: (v) => onUpdateBlock('title', v),
  );
}
```

---

## 📦 Creating New Block Types

When adding a NEW block type, you MUST:

### 1. Add Enum Value
```dart
// lib/modules/website/models/website_block_type.dart
enum WebsiteBlockType {
  // ... existing types
  myNewBlock,  // Add new type
}
```

### 2. Add Icon
```dart
// In WebsiteBlockTypeX extension
IconData get icon => switch (this) {
  // ...
  WebsiteBlockType.myNewBlock => Icons.my_icon,
};
```

### 3. Register Block Definition
```dart
// lib/modules/website/models/website_block_registry.dart
WebsiteBlockType.myNewBlock: WebsiteBlockDefinition(
  type: WebsiteBlockType.myNewBlock,
  title: 'Mi Nuevo Bloque',
  description: 'Descripción del bloque',
  defaultData: {
    'title': 'Título por defecto',
    'content': 'Contenido por defecto',
    'imageUrl': null,
    'buttonText': null,
    'buttonLink': null,
  },
  fields: [
    // Define ALL editable fields
    WebsiteBlockFieldSchema(key: 'title', label: 'Título', type: WebsiteBlockFieldType.text),
    WebsiteBlockFieldSchema(key: 'content', label: 'Contenido', type: WebsiteBlockFieldType.textarea),
    WebsiteBlockFieldSchema(key: 'imageUrl', label: 'Imagen', type: WebsiteBlockFieldType.image),
    WebsiteBlockFieldSchema(key: 'buttonText', label: 'Texto del Botón', type: WebsiteBlockFieldType.text),
    WebsiteBlockFieldSchema(key: 'buttonLink', label: 'Enlace', type: WebsiteBlockFieldType.text),
  ],
),
```

### 4. Add Renderer
```dart
// lib/modules/website/widgets/website_block_renderer.dart
case WebsiteBlockType.myNewBlock:
  return _buildMyNewBlock(
    context: context,
    data: data,
    primaryColor: primaryColor,
    // ... other params
  );

static Widget _buildMyNewBlock({
  required BuildContext context,
  required Map<String, dynamic> data,
  required Color primaryColor,
  // ...
}) {
  final title = data['title'] as String? ?? 'Default';
  final content = data['content'] as String? ?? '';
  final imageUrl = data['imageUrl'] as String?;
  final buttonText = data['buttonText'] as String?;
  final buttonLink = data['buttonLink'] as String?;
  
  return Container(
    // Build UI using data from block_data
    // ALL content comes from editable fields!
  );
}
```

### 5. Add to Editor Preview
The Odoo-style editor automatically handles preview if block is registered properly.

---

## 🔗 Website Link System (STANDARD - Jan 2026)

**The Website Editor is the ONLY source of truth for navigation.**

If a UI element can navigate (button, card, menu item, footer link, banner CTA, “ver todos”, etc.), it MUST:
1) Be configurable in the editor UI.
2) Be saved to the database.
3) Be rendered and navigated EXACTLY as saved.

### Why we need a standard
`block_data` is stored as `jsonb` and Flutter treats it as `Map<String, dynamic>`.
That means saving the “wrong key” (e.g. `link` vs `ctaLink`) will not error at save-time: it’s valid JSON.
If the renderer reads a different key, it can silently navigate to an old/stale value.

### Canonical UX (one picker everywhere)
All link-capable fields MUST use the same editor widget and UX:
- Use `WebsiteLinkValueEditor` for every “destination” field.
- Do NOT use raw text fields for links (no manual URL typing-only UX).
- The UI must support:
  - Picking an internal website page
  - Picking common internal routes (Inicio, Productos, Contacto, etc.)
  - Entering an external URL

### Canonical stored value format
We standardize on a **single string href** (stored in whatever field key the block schema defines), with consistent rules:
- **Internal links:** store clean public-store paths (preferred):
  - `/` (home)
  - `/productos`
  - `/productos?q=botellas%20de%20agua` (search term)
  - `/productos?type=service` (services view)
  - `/pagina/<slug>` (custom pages)
- **External links:** store full absolute URL: `https://...`
- **Legacy links:** `/tienda/...` may exist in old data; editor/save logic SHOULD normalize to clean paths.
- **Avoid legacy params:** do NOT generate `?categoria=mtb`. Prefer `q=` for tokens or `category=<uuid>` when we truly mean category ID.

### Data model rules (prevent “Frankenstein” drift)
- For a given clickable element, there MUST be exactly one destination field.
  - Example: a Category Grid card must not have both `ctaLink` and `link` with different meanings.
- If we must support legacy aliases temporarily:
  - The editor MUST keep aliases in sync on save.
  - `WebsiteService` MUST normalize on load.
  - The renderer MUST read the canonical value (or explicitly resolve compat until migration is done).
- Never introduce a new “alias” key casually. If you rename a field, treat it as a migration.

### Renderer rules
- The renderer must not hardcode destinations.
- For internal navigation, always call the provided `onNavigate?.call(href)` (it routes through the store’s navigation normalization layer).
- Only use safe fallbacks (`/productos`, `/`) when a destination is truly missing.

### Schema rule for block definitions
Any destination field in a block definition MUST use `WebsiteBlockFieldType.link`.
Never define link fields as plain `text`.

### Navigation Management (menus/footer)
Navigation editor screens must reuse the same `WebsiteLinkValueEditor` so menu links behave exactly like block links.
This keeps UX consistent and eliminates special-case pickers.

---

## 🧱 Website Editor Standardization (NORTH STAR - Jan 2026)

The real enemy is not “a single bug” — it’s **drift**. The Website Builder stores configuration in `jsonb`, so schema mismatches and inconsistent UX can silently persist in production data.

### What we learned (root cause)
- The editor can save any JSON keys without errors; “wrong key” data is still valid.
- If a renderer reads a different key (or has hardcoded fallbacks), the UI becomes a **Frankenstein**: user edits appear to “not work”, old values “win”, and behavior differs across blocks.
- Fixing one block at a time doesn’t scale. We need **shared capability systems** that every block uses.

### The solution direction (capability systems)
When multiple blocks share the same capability, they MUST share the same widgets, data rules, and behavior.

**Capability: Links**
- Use the Link System standard above (single href string, `WebsiteLinkValueEditor`, normalize legacy `/tienda/*` + legacy query params).
- Renderer must always route via `onNavigate?.call(href)` (no direct hardcoded route logic inside blocks).

**Capability: Inline Text Editing**
- Use `InlineEditableTextV2` for any inline-editable text going forward.
- Toolbars must be consistent via a preset (e.g. `TextToolbarPreset.textOnly/minimal/basic/full`) rather than ad-hoc per block.
- Do not introduce new “simple” text editors for convenience; migrate older ones when touching a block.

**Capability: Inline Images / Media Controls**
- Use `InlineEditableImage` for click-to-replace everywhere.
- If a block renders a cover/background image (hero, carousel, banners, cards), it should support the same **mobile focal point / background positioning** data model and editor controls.
- Do not implement per-block image alignment UX; use shared controls and shared stored keys.

**Capability: Navigation Normalization**
- Any href coming from the editor may be legacy (`/tienda/...`) or historically inconsistent (old params like `categoria=`).
- Normalize at load/save boundaries (service layer) and navigate through the store’s normalization layer.

### Data discipline rules (how we stop drift)
- **Defaults live in block definitions/registry**, not in renderers.
- **Editor writes canonical keys** only. If legacy aliases exist, keep them in sync until migration is complete.
- **WebsiteService must normalize** blocks on load/save so persisted data becomes more correct over time.
- **Never add a second key for the same meaning** (e.g. avoid `link` + `ctaLink` unless explicitly in a compatibility window).

### Migration philosophy (future-proof, no surprises)
- Prefer “compat + normalize + converge” over one-off hacks.
- If production data already contains legacy keys/values, fix it by:
  1) Normalizing on load (so the UI behaves correctly immediately)
  2) Normalizing on save (so edits permanently repair the data)
  3) Optionally running a one-time data cleanup for the tenant

### Definition of done (for any website editor change)
- The same capability behaves the same across blocks (UX + stored keys + navigation).
- Editor-assigned values always win over old/hardcoded behavior.
- If legacy data exists, it is handled (and ideally normalized) so we don’t regress later.

---

## 🖼️ Media System

### Image Fields
```dart
WebsiteBlockFieldSchema(
  key: 'imageUrl',
  label: 'Imagen',
  type: WebsiteBlockFieldType.image,
)
```

Images are:
1. Uploaded to Supabase Storage (`website/blocks/` folder)
2. URL stored in `block_data.imageUrl`
3. Rendered with `InlineEditableImage` for click-to-replace

### Video Fields (VideoBanner block)
```dart
defaultData: {
  'videoUrl': null,  // YouTube/Vimeo URL
  'posterImage': null,  // Fallback image
  'autoplay': true,
  'loop': true,
  'muted': true,
}
```

---

## 📄 Multi-Page System

### Page Templates
```dart
enum PageTemplate {
  defaultTemplate,  // General purpose
  landing,          // Marketing landing page
  productList,      // Product catalog
  blog,             // Blog/article page
}
```

### Creating Pages
Pages are created in the Website Editor:
1. Click "Nueva Página" button
2. Enter title and slug
3. Select template (determines default blocks)
4. Add/edit blocks
5. Publish

### Route Structure
```
/tienda                    - Home page (is_home = true)
/tienda/productos          - Product catalog
/tienda/producto/:id       - Product detail
/pagina/:slug              - Custom pages (nosotros, terminos, etc.)
/cuenta                    - Customer account
```

### Policy Pages Routing (Dec 2025 fix)
- Use `StaticPolicyPage` (in `lib/public_store/pages/static_policy_page.dart`) for policy/info slugs like `/nosotros`, `/terminos`, `/privacidad`, `/devoluciones`, `/envios`.
- Wrap it in `PublicStoreWrapper` in `app_router.dart`; do **not** route these to `DynamicWebsitePage` (causes redirect loops and loses inline editing).
- `StaticPolicyPage` already wires `WebsiteEditModeProvider` + `EditableBlockRenderer`, so `?edit=true` / `?preview=true` keep inline editing on these pages.
- Provide a `fallbackTitle` per slug to avoid null titles when the page row is missing or unpublished.

---

## 🎨 Theme System

Theme settings stored in `website_settings`:
```
theme_primary_color     - Main brand color
theme_accent_color      - Secondary/highlight color
theme_background_color  - Page background
theme_text_color        - Default text color
theme_heading_font      - Font family for titles
theme_body_font         - Font family for body text
theme_heading_size      - Base heading size (px)
theme_body_size         - Base body size (px)
theme_section_spacing   - Gap between blocks (px)
theme_container_padding - Content padding (px)
```

All blocks inherit theme settings automatically.

---

## ⚠️ Checklist for Website Features

When creating ANY website feature:

- [ ] **Is all content editable?** (No hardcoded text/images)
- [ ] **Does it use InlineEditableText?** (For text fields)
- [ ] **Does it use InlineEditableImage?** (For images)
- [ ] **Is there a block definition?** (In website_block_registry.dart)
- [ ] **Are all fields defined?** (With proper types)
- [ ] **Does it support buttons/links?** (buttonText + buttonLink)
- [ ] **Does it respect theme settings?** (Colors, fonts)
- [ ] **Is it responsive?** (desktop/tablet/mobile visibility)
- [ ] **Is there a renderer?** (In website_block_renderer.dart)
- [ ] **Is the default data sensible?** (Placeholder content, not real data)
- [ ] **Does the editable block use LayoutBuilder?** (For vertical centering when resized)
- [ ] **Does the GestureDetector have HitTestBehavior.opaque?** (For click-anywhere selection)

---

## 🎯 CRITICAL: Editable Block Rendering Patterns (Dec 2025)

**Location:** `lib/modules/website/widgets/editable_block_renderer.dart`

### Block Selection Architecture

The `EditableBlockRenderer` widget wraps each block with:
1. **GestureDetector** - For tap-to-select functionality
2. **Stack** - For overlay elements (selection border, resize handles, action bar)
3. **ConstrainedBox** - For enforcing custom block heights when resized

**CRITICAL:** The GestureDetector MUST have `behavior: HitTestBehavior.opaque` to capture taps on empty areas within the block bounds.

```dart
return GestureDetector(
  behavior: HitTestBehavior.opaque, // ⚠️ CRITICAL: Captures taps on empty space
  onTap: () => editProvider.selectBlock(widget.blockId),
  child: Stack(
    clipBehavior: Clip.none,
    children: [
      // Block content
      // Selection border (Positioned.fill)
      // Resize handles (if selected)
      // Action bar (if selected)
    ],
  ),
);
```

### Block Height Categories

Blocks are categorized into two types based on how they handle custom heights:

#### 1. Full-Bleed Blocks (Media fills entire height)
These blocks stretch their media (images/videos) to fill the entire block height:
- `hero` - Background image fills block
- `carousel` - Slides fill block height
- `videoBanner` - Video fills block

**Pattern:** Pass `blockHeight` to the block builder and use it directly:
```dart
final fullBleedBlocks = {'hero', 'carousel', 'videoBanner'};

// In hero/carousel/videoBanner builders:
final blockHeight = (data['blockHeight'] as num?)?.toDouble() ?? 480;
return SizedBox(
  height: blockHeight,
  child: Stack(
    fit: StackFit.expand, // Image/video fills entire space
    children: [
      // Background media
      // Overlay content (centered)
    ],
  ),
);
```

#### 2. Content Blocks (Content centers vertically)
These blocks center their content vertically within the constrained height:
- `services`, `features`, `about`, `cta`, `faq`
- `contact`, `pricing`, `testimonials`, `stats`, `team`
- `gallery`, `categoryGrid`, `partnersBanner`, `brandLogos`

**Pattern:** Use `LayoutBuilder` to detect constrained height and center content:
```dart
Widget _buildEditableServices(BuildContext context) {
  // ... parse data, create content Column ...
  
  final content = Column(
    mainAxisSize: MainAxisSize.min, // ⚠️ CRITICAL: Don't expand unnecessarily
    children: [
      // Title, subtitle, items, etc.
    ],
  );

  return LayoutBuilder(
    builder: (context, constraints) {
      final hasFixedHeight = constraints.maxHeight.isFinite;
      
      return Container(
        width: double.infinity, // ⚠️ Fill horizontal space for click detection
        height: hasFixedHeight ? constraints.maxHeight : null,
        padding: hasFixedHeight
            ? const EdgeInsets.symmetric(horizontal: 24) // No vertical padding when constrained
            : const EdgeInsets.symmetric(vertical: 64, horizontal: 24), // Normal padding
        child: Center( // ⚠️ Centers content vertically AND horizontally
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: content,
          ),
        ),
      );
    },
  );
}
```

### Why LayoutBuilder Pattern is Required

1. **Resize Feature:** Users can drag the bottom edge of blocks to resize them
2. **Height Constraint:** The wrapper passes `ConstrainedBox` with `minHeight`/`maxHeight` to the block
3. **Vertical Centering:** Without `LayoutBuilder`, content would stick to top of block
4. **Click Detection:** Without `width: double.infinity`, empty areas won't register taps

### Common Mistakes to AVOID

❌ **Missing HitTestBehavior.opaque on GestureDetector:**
```dart
// WRONG: Taps on empty space don't select block
GestureDetector(
  onTap: () => selectBlock(id),
  child: ...
)

// CORRECT: Taps anywhere in bounds select block
GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: () => selectBlock(id),
  child: ...
)
```

❌ **Not using LayoutBuilder for content blocks:**
```dart
// WRONG: Content sticks to top when block is resized
return Container(
  padding: EdgeInsets.all(64),
  child: Column(children: [...]),
);

// CORRECT: Content centers vertically when height is constrained
return LayoutBuilder(
  builder: (context, constraints) {
    final hasFixedHeight = constraints.maxHeight.isFinite;
    return Container(
      height: hasFixedHeight ? constraints.maxHeight : null,
      child: Center(child: content),
    );
  },
);
```

❌ **Missing mainAxisSize: MainAxisSize.min on Column:**
```dart
// WRONG: Column expands to fill all space, breaks centering
Column(
  children: [...]
)

// CORRECT: Column only takes needed space
Column(
  mainAxisSize: MainAxisSize.min,
  children: [...]
)
```

❌ **Missing width: double.infinity on Container:**
```dart
// WRONG: Click area only covers content width
Container(
  child: Center(child: content),
)

// CORRECT: Click area covers full block width
Container(
  width: double.infinity,
  child: Center(child: content),
)
```

### Adding a New Editable Block

When creating a new editable block in `editable_block_renderer.dart`:

1. **Add case to switch statement:**
```dart
case WebsiteBlockType.myNewBlock:
  return _buildEditableMyNewBlock(context);
```

2. **Create builder method following the pattern:**
```dart
Widget _buildEditableMyNewBlock(BuildContext context) {
  final editProvider = context.read<WebsiteEditModeProvider>();
  final theme = Theme.of(context);
  
  // 1. Parse data from widget.data
  final title = (widget.data['title'] ?? 'Default Title').toString();
  final items = widget.data['items'] as List? ?? [];
  
  // 2. Define styles
  final headingStyle = theme.textTheme.displaySmall?.copyWith(
    fontFamily: widget.headingFont,
  );
  
  // 3. Build content with mainAxisSize: MainAxisSize.min
  final content = Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      InlineEditableTextV2(
        text: title,
        baseStyle: headingStyle,
        textAlign: TextAlign.center,
        isEditMode: true,
        placeholder: 'Título',
        fieldKey: '${widget.blockId}_title',
        onTextChanged: (value) =>
            editProvider.updateBlockData(widget.blockId, 'title', value),
      ),
      // ... more content
    ],
  );
  
  // 4. Wrap with LayoutBuilder for vertical centering
  return LayoutBuilder(
    builder: (context, constraints) {
      final hasFixedHeight = constraints.maxHeight.isFinite;
      
      return Container(
        width: double.infinity,
        height: hasFixedHeight ? constraints.maxHeight : null,
        padding: hasFixedHeight
            ? const EdgeInsets.symmetric(horizontal: 24)
            : const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
        color: Colors.white, // Optional background
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: content,
          ),
        ),
      );
    },
  );
}
```

3. **For full-bleed blocks (with background images/videos):**
```dart
Widget _buildEditableMyMediaBlock(BuildContext context) {
  final blockHeight = (widget.data['blockHeight'] as num?)?.toDouble() ?? 480;
  
  return SizedBox(
    height: blockHeight,
    width: double.infinity,
    child: Stack(
      fit: StackFit.expand,
      children: [
        // Background image/video (fills entire space)
        InlineEditableImage(
          imageUrl: widget.data['backgroundImage'],
          fit: BoxFit.cover,
          isEditMode: true,
          onChanged: (url) => editProvider.updateBlockData(
              widget.blockId, 'backgroundImage', url),
        ),
        // Overlay content (centered)
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [/* Title, subtitle, button */],
          ),
        ),
      ],
    ),
  );
}
```

### Block Rendering Checklist (New Blocks)

When adding a new editable block:

- [ ] Added case to `_buildEditableBlock()` switch statement
- [ ] Created `_buildEditableMyBlock()` method
- [ ] Used `InlineEditableTextV2` for all text fields
- [ ] Used `InlineEditableImage` for all images
- [ ] Set `mainAxisSize: MainAxisSize.min` on all Columns
- [ ] Wrapped return with `LayoutBuilder` (for content blocks)
- [ ] Set `width: double.infinity` on Container
- [ ] Used `Center` widget for vertical centering
- [ ] Used `ConstrainedBox` with appropriate maxWidth
- [ ] Tested click-anywhere-to-select behavior
- [ ] Tested resize behavior (content centers vertically)
- [ ] Tested with both short and tall content

---

## 🔍 Reference Files

| File | Purpose |
|------|---------|
| `lib/public_store/widgets/public_store_layout.dart` | Main layout with edit button & panel integration |
| `lib/modules/website/widgets/website_editor_panel.dart` | Side panel editor (6600 lines) |
| `lib/modules/website/providers/website_edit_mode_provider.dart` | Edit state management |
| `lib/modules/website/widgets/editable_block_renderer.dart` | **CRITICAL:** Makes blocks clickable/selectable/resizable in edit mode. Contains all `_buildEditable*` methods |
| `lib/public_store/pages/public_home_page.dart` | Home page with full editing support |
| `lib/public_store/pages/dynamic_website_page.dart` | Other pages (READ-ONLY, no editing yet) |
| `lib/modules/website/models/website_block_type.dart` | Block type enum |
| `lib/modules/website/models/website_block_definition.dart` | Field schema definitions |
| `lib/modules/website/models/website_block_registry.dart` | Block registration & defaults |
| `lib/modules/website/widgets/website_block_renderer.dart` | Renders blocks (read-only, for public view) |
| `lib/modules/website/widgets/inline_editable_text.dart` | Inline text editing widget (V1) |
| `lib/modules/website/widgets/inline_editable_text_v2.dart` | Inline text editing widget (V2 with formatting) |
| `lib/modules/website/widgets/inline_editable_image.dart` | Inline image editing/upload widget |
| `lib/modules/website/services/website_service.dart` | Database operations for blocks/pages (**includes page_id in saves**) |

---

# 📣 Marketing Module

- Campaign builder (email, SMS, push)
- Customer segmentation based on CRM data
- Promotion rules (discounts, bundles)
- Scheduled and triggered campaigns
- Integration with Analytics for performance tracking

---

# 📊 Analytics Dashboard

- Sales by product/category/date
- Inventory turnover and valuation
- Customer lifetime value
- Maintenance cost breakdown
- HR metrics (attendance, payroll trends)
- Campaign performance (open rate, conversion)

---

# 📦 Suggested Folder Structure

`plaintext
lib/
├── modules/
│   ├── sales/
│   ├── purchases/
│   ├── inventory/
│   ├── maintenance/
│   ├── accounting/
│   ├── crm/
│   ├── hr/
│   ├── website/
│   ├── marketing/
│   ├── analytics/
│   └── settings/
├── shared/
│   ├── models/
│   ├── services/
│   ├── widgets/
│   └── themes/
`

Each module:

- Has its own routes (GoRouter)
- Uses shared models (e.g. Product, Order, Customer, Employee)
- Follows the same UI design system

---

# 🧠 Copilot Expectations

Copilot must:

- Maintain consistent naming across modules
- Reuse shared models and widgets
- Respect business rules (e.g. inventory deduction, tax calculation)
- Avoid GUI fragmentation (no random button styles)
- Handle dark mode, language, and time zone globally
- Generate audit-ready accounting logic
- Use PostgreSQL syntax and constraints
- Avoid hardcoded values—use config or constants
- Use modular architecture with clean separation of concerns

---

# 🖼️ Image Handling Rules

- All modules that involve products, customers, employees, or marketing must support images.
- Use a unified image service (`ImageService`) in `lib/shared/services/` for:
  - Uploading images (to Supabase storage or Firebase storage).
  - Fetching images with caching (use `CachedNetworkImage`).
  - Handling placeholders (default icon if no image).
  - Handling errors (broken link → fallback image).
- Store only the image URL/path in the database, not the binary.
- Organize assets in `assets/images/` for static icons, logos, and placeholders.
- For product images:
  - Support multiple images per product.
  - Use thumbnails in lists, full-size in detail pages.
- For employee/customer profile pictures:
  - Circular avatar style, consistent sizing.
- For marketing/website:
  - Support banners and campaign images with responsive scaling.
- Always optimize for performance:
  - Use lazy loading for lists.
  - Use compressed formats (WebP/optimized JPEG).
- Respect dark mode (ensure images/icons adapt or remain visible).

---

# 🔍 Search & Filtering Rules

- Any list or dropdown with more than ~10 possible items must include a search bar at the top.
- Examples:
  - Chart of Accounts → searchable by code and name.
  - Customer/Supplier selection → searchable by name, RUT, or email.
  - Product selection → searchable by SKU, name, or category.
- Use a consistent search widget across modules:
  - TextField with prefix search icon.
  - Real-time filtering as the user types.
  - Case-insensitive matching.
- For very large datasets (100+ items), implement pagination or lazy loading with search.
- Always place the search bar **above the list** (not hidden in a menu).
- Respect localization: search must work with Spanish characters (ñ, á, é, í, ó, ú).

---

# 📦 Import Services (CSV/Excel/Zoho) - Stock Tracking Pattern

**ALL import services that modify stock MUST use single-transaction RPC pattern.**

## ✅ Automatic Protection (Oct 28, 2025 → Enhanced Nov 8, 2025)

### Background: Why Transaction Scope Matters

**The Problem (Discovered Nov 8, 2025):**
- Supabase Python client treats each RPC call as a separate HTTP request
- Each HTTP request = separate database transaction
- Session variables only persist WITHIN a transaction
- Setting context in one call, then updating in another call = context lost!

**The Solution:**
- Create RPC functions that bundle context-setting AND data-update in ONE function
- ONE function call = ONE HTTP request = ONE database transaction
- Trigger fires within same transaction → sees session variables → labels import correctly

### Pattern: Single-Transaction RPC Functions

**Database RPC Template** (add to `core_schema.sql`):
```sql
create or replace function public.import_{table}_with_context(
  p_tenant_id uuid,
  p_unique_id text,              -- SKU, email, invoice_number, etc.
  p_{table}_data jsonb,
  p_import_reference text,
  p_import_reason text default 'Import'
)
returns jsonb
security definer
language plpgsql
as $$
declare
  v_updated_count integer := 0;
begin
  -- Set import context (transaction-scoped)
  perform pg_catalog.set_config('app.stock_adjustment_context', 'import', true);
  perform pg_catalog.set_config('app.import_reference', p_import_reference, true);
  perform pg_catalog.set_config('app.import_reason', p_import_reason, true);
  
  -- Update record (trigger sees context in same transaction)
  update {table}
  set
    column1 = coalesce((p_{table}_data->>'column1')::type, column1),
    column2 = coalesce((p_{table}_data->>'column2')::type, column2),
    updated_at = now()
  where tenant_id = p_tenant_id and unique_column = p_unique_id;
  
  get diagnostics v_updated_count = row_count;
  
  -- Clear context
  perform pg_catalog.set_config('app.stock_adjustment_context', '', true);
  perform pg_catalog.set_config('app.import_reference', '', true);
  perform pg_catalog.set_config('app.import_reason', '', true);
  
  return jsonb_build_object('success', true, 'updated_count', v_updated_count);
end;
$$;

grant execute on function public.import_{table}_with_context(uuid, text, jsonb, text, text) to authenticated;
```

**Python Import Script Pattern**:
```python
# ✅ CORRECT: Single RPC = single transaction
import_ref = f"import_{int(time.time() * 1000)}"

result = client.rpc('import_product_with_context', {
    'p_tenant_id': tenant_id,
    'p_sku': sku,
    'p_product_data': {
        'name': product_name,
        'price': price,
        'stock_quantity': new_stock
    },
    'p_import_reference': import_ref,
    'p_import_reason': f'Import: {sku}'
}).execute()

# ❌ WRONG: Separate calls = separate transactions (context lost)
client.rpc('set_config', {...}).execute()  # Transaction 1
client.table('products').update({...}).execute()  # Transaction 2 (no context!)
```

## 🚨 Import Service Checklist

When creating ANY import service (products, categories, customers, suppliers, etc.):

1. ✅ **Check if RPC function exists** in `core_schema.sql`
   - Search for: `import_{table}_with_context`
   - If missing, create using template above
   
2. ✅ **Use single-transaction RPC pattern** in Python/Dart
   - ONE `client.rpc()` call bundles context + update
   - Generate `import_reference` once per import batch
   
3. ✅ **Authenticate and get tenant_id**
   - Sign in with email/password
   - Fetch tenant_id from `user_profiles` table
   
4. ✅ **Handle errors gracefully**
   - Show which rows failed
   - Don't stop entire import on single error
   
5. ✅ **Support both CSV and Excel formats**
   - Use pandas for parsing
   - Validate data before inserting
   
6. ✅ **Show progress indicator during bulk imports**
   - Print/log each item processed
   - Display summary at end
   
7. ✅ **Test with multiple tenants to verify isolation**
   - Import same SKU for different tenants
   - Verify data doesn't leak between tenants

## 📋 Existing Import Infrastructure

**Database Functions** (in `core_schema.sql`):
- `set_config(text, text, boolean)` - Exposes PostgreSQL session variables (lines 1629-1654)
- `import_product_with_context(uuid, text, jsonb, text, text)` - Products import (lines 1656-1720)
- `track_product_stock_changes()` - Trigger that detects import context (lines 863-958)

**Stock Adjustments Table**:
- `adjustment_type` includes `'import'` value (line 802)
- `reference` column stores import batch ID (line 815)

**Test Scripts**:
- `scripts/zoho_import/test_import_with_tracking.py` - Working example (469 lines)
- `scripts/zoho_import/test_products.csv` - Sample test data

**Documentation**:
- `.github/IMPORT_STOCK_TRACKING_GUIDE.md` - Complete implementation guide
- `.github/ZOHO_IMPORT_QUICKREF.md` - One-page cheat sheet for AI agents

## 🎯 Production Verification

✅ **Verified working Nov 8, 2025:**
- Stock adjustments created with `type='import'`
- Reference column populated with `import_TIMESTAMP`
- UI displays "Importación" origin label (not "Ajuste Manual")
- No ghost records (only actual stock changes logged)
- Multi-tenant isolation working correctly

---

# � Import Services (CSV/Excel) - Multi-Tenant Rules (LEGACY - SUPERSEDED BY ABOVE)

**ALL import services MUST follow these rules:**

## ✅ Automatic Protection (Oct 28, 2025)

- **Import services are NOW tenant-safe automatically** via `DatabaseService.insert()`
- No manual tenant_id injection needed - it's handled at database layer
- Works for ALL authenticated users across ALL modules

## 🔧 When Creating Import Services

**ALWAYS use DatabaseService for imports:**

```dart
// ✅ CORRECT: DatabaseService auto-injects tenant_id
class ProductImportService {
  final DatabaseService _db = DatabaseService();
  
  Future<void> _upsertProduct(Map<String, dynamic> productData) async {
    // Just use DatabaseService.insert() - tenant_id added automatically
    await _db.insert('products', productData);
  }
}

// ❌ WRONG: Direct Supabase client bypasses auto-injection
class ProductImportService {
  Future<void> _upsertProduct(Map<String, dynamic> productData) async {
    // This bypasses DatabaseService - tenant_id NOT added!
    await Supabase.instance.client.from('products').insert(productData);
  }
}
```

## 🚨 Import Service Checklist

When creating ANY import service (products, categories, customers, suppliers, etc.):

1. ✅ Use `DatabaseService` for ALL inserts/updates (NOT direct Supabase client)
2. ✅ Import service class extends `ChangeNotifier` for UI updates
3. ✅ Handle errors gracefully (show which rows failed)
4. ✅ Support both CSV and Excel formats
5. ✅ Validate data before inserting (SKU/name required, prices > 0, etc.)
6. ✅ Show progress indicator during bulk imports
7. ✅ Test with multiple tenants to verify isolation

## 🔍 How Auto-Injection Works

- `DatabaseService.insert()` checks if table needs tenant_id
- Fetches current user's tenant_id from `user_profiles` table
- Injects tenant_id into payload before INSERT
- Skips system tables: `tenants`, `user_profiles`, `reserved_subdomains`, `user_invitations`
- Logs injection activity: `✅ Auto-injected tenant_id: [uuid] into [table]`

## 📦 Existing Import Services (All Protected)

- ✅ `ProductImportService` → Products
- ✅ `CategoryImportService` → Product categories
- ✅ `CustomerImportService` → Customers
- ✅ `SupplierImportService` → Suppliers
- ✅ `EmployeeImportService` → Employees (if exists)

**All use DatabaseService → All tenant-safe automatically!**

---

# �🚀 Multi-Tenant Onboarding System (AUTO-INITIALIZATION)

**Location:** `supabase/sql/core_schema.sql` lines 1608-2091, 11221-11345

## Automated Flow

When a user signs up, the system **automatically creates**:

1. **Tenant** (shop, subdomain, currency CLP, timezone America/Santiago)
2. **User Profile** (links user to tenant with 'admin' role)
3. **30 Chilean Accounting Accounts** (Assets, Liabilities, Equity, Income, Expenses, Tax)
4. **4 Payment Methods** (Efectivo→Caja, Transferencia→Banco, Cheque, Tarjeta)
5. **8 Company Settings** (IVA 19%, currency, fiscal year, invoice/purchase prefixes)
6. **7 Website Settings** (e-commerce defaults, theme, currency)

**Trigger Chain:**
```
User signup → on_auth_user_created → handle_new_user() 
                                           ↓
                                    Creates tenant
                                           ↓
                            trg_tenant_initialization → handle_new_tenant()
                                                              ↓
                                                    seed_chart_of_accounts()
                                                    seed_payment_methods_for_tenant()
                                                    seed_company_settings()
                                                    seed_website_settings()
```

## User Invitation Flow

- If user has pending invitation → joins existing tenant with invited role
- Otherwise → creates new tenant and becomes admin
- Subdomain auto-generated from email (handles collisions with counter)

## Manual Seeding (Existing Tenants)

```sql
-- Seed all foundation data for existing tenant
DO $$
DECLARE tenant_rec RECORD;
BEGIN
  FOR tenant_rec IN SELECT id FROM tenants LOOP
    PERFORM public.seed_chart_of_accounts(tenant_rec.id);
    PERFORM public.seed_payment_methods_for_tenant(tenant_rec.id);
    PERFORM public.seed_company_settings(tenant_rec.id);
    PERFORM public.seed_website_settings(tenant_rec.id);
  END LOOP;
END $$;
```

---

# 📦 Barcode Scanner Support

The app supports **3 types of barcode scanners**:

## 1. USB/Keyboard Scanners (Recommended for Desktop/POS)
- Works on all platforms (Windows, macOS, Linux, Web)
- No drivers needed - plug and play
- Scanner emulates keyboard input
- Most economical option
- Examples: Symbol LS2208, Honeywell Voyager, Inateck BCST-70

## 2. Bluetooth Scanners (Mobile/Tablet)
- For Windows, Android, iOS
- Wireless freedom
- Requires Bluetooth pairing
- Examples: Socket Mobile, Honeywell Voyager 1602g

## 3. Mobile Phone as Scanner (NEW)
- Use phone camera as wireless scanner
- No additional hardware needed
- Perfect for inventory/warehouse
- Cross-platform (any phone with camera)

**Implementation:** `lib/modules/settings/pages/barcode_scanner_config_page.dart`

---

# 🔄 Key Business Logic Patterns

## Expense Account vs Expense Category

- Expense accounts are ledger-level posting destinations. They may be specific, for example `Agua` and `Luz` as subaccounts under `Servicios Básicos`.
- Expense categories are operational/reporting buckets for UI filters, templates, OCR defaults, and expense review. They should encompass a broader set of related accounts, not mirror every account one-to-one.
- Do not create a new expense category every time a new account is added. Add a category only when it creates a useful reporting/review bucket that users would naturally filter by.
- Utility subaccounts such as water, electricity, gas, sanitation, or provider-specific accounts like Esval should normally categorize as `Servicios Básicos` while posting to the precise account.
- When adding OCR or quick-expense automation, prefer broad categories first and precise accounts second. Example: Esval receipt → category `Servicios Básicos`, account `Agua`.

## Invoice → Journal Entry Flow

**Sales Invoice:**
1. User creates invoice → `sales_invoices` INSERT
2. Trigger `trg_sales_invoices_change` fires
3. Calls `handle_sales_invoice_change()`
4. If posted → creates journal entry with:
   - DEBIT: Cuentas por Cobrar (1130)
   - CREDIT: Ventas (4101) + IVA Débito (2110)
5. Deducts inventory via `consume_sales_invoice_inventory()`

**Purchase Invoice:**
1. User creates invoice → `purchase_invoices` INSERT
2. Trigger `trg_purchase_invoices_change` fires
3. If posted → creates journal entry with:
   - DEBIT: Expense account + IVA Crédito (2120)
   - CREDIT: Cuentas por Pagar (2101)
4. Increases inventory via `consume_purchase_invoice_inventory()`

**Payment Recording:**
- Trigger on `sales_payments`/`purchase_payments` INSERT
- Creates journal entry:
  - DEBIT: Payment method account (Caja/Banco)
  - CREDIT: Cuentas por Cobrar/Pagar
- Updates invoice `paid_amount` and `status`

## Mechanic Job (Trabajo) → Invoice Flow

**Location:** `lib/modules/bikeshop/services/bikeshop_service.dart`

1. Mechanic completes job with parts + labor
2. Job status = 'completed' or 'ready_for_delivery'
3. User clicks "Generate Invoice"
4. System creates `sales_invoice` with:
   - Line items from `mechanic_job_parts` (products used)
   - Labor line item from `mechanic_jobs.labor_cost`
   - Customer from `mechanic_jobs.customer_id`
   - Links invoice back: `mechanic_jobs.invoice_id = invoice.id`
5. Invoice posting triggers accounting entries (see above)

**Bidirectional Cascade Delete:**
- Deleting trabajo → deletes invoice (trigger: `cascade_delete_pega_invoice`)
- Deleting invoice → deletes trabajo (same trigger)
- Prevents orphaned records

---

# 💰 Tax Treatment (IVA 19%) - CRITICAL DIFFERENCES

## Sales Invoices: Tax is INCLUDED in Price

**Concept:** Customer sees final price on shelf/website. Tax is embedded.

**Example:** Selling a bicycle for $119,000 CLP
- Display price: $119,000 (what customer pays)
- When "IVA Incluido" selected:
  - Neto (Net): $100,000 (calculated: $119,000 ÷ 1.19)
  - IVA (19%): $19,000 (calculated: $119,000 - $100,000)
  - Total: $119,000 (unchanged - customer pays this amount)

**Calculation Logic:**
```dart
// Sales Invoice (lib/modules/sales/pages/invoice_form_page.dart)
double get _netAmount {
  if (_taxTreatment == TaxTreatment.taxIncluded) {
    return _subtotal / 1.19;  // Extract net by dividing
  } else {
    return _subtotal;
  }
}

double get _iva {
  if (_taxTreatment == TaxTreatment.taxIncluded) {
    return _subtotal - _netAmount;  // Tax is difference
  } else {
    return 0;
  }
}

double get _total => _subtotal;  // Total stays the same (what customer sees)
```

**Use Cases:**
- POS sales (retail)
- Service invoices (Trabajos module)
- Customer-facing transactions
- E-commerce product prices

---

## Purchase Invoices: Tax is ADDED on Top

**Concept:** Supplier quotes net price. We add tax on top to calculate total.

**Example:** Buying inventory for $100,000 CLP net
- Supplier quotes: $100,000 net
- When "IVA Incluido" selected:
  - Subtotal (Neto): $100,000 (supplier's quoted price)
  - IVA (19%): $19,000 (calculated: $100,000 × 0.19)
  - Total: $119,000 (calculated: $100,000 + $19,000)

**Calculation Logic:**
```dart
// Purchase Invoice (lib/modules/purchases/pages/purchase_invoice_form_page.dart)
double get _netAmount {
  return _subtotal;  // Net is always the subtotal for purchases
}

double get _iva {
  if (_taxTreatment == TaxTreatment.taxIncluded) {
    return _subtotal * 0.19;  // Add 19% tax
  } else {
    return 0;
  }
}

double get _total {
  if (_taxTreatment == TaxTreatment.taxIncluded) {
    return _subtotal + _iva;  // Add tax to get total
  } else {
    return _subtotal;
  }
}
```

**Use Cases:**
- Purchasing inventory from suppliers
- Buying parts/components
- Import costs
- Service provider invoices

---

## Why the Difference?

**Sales (Tax Included):**
- Retail customers see **final prices** (tax already embedded)
- We **extract** the tax component for accounting: `net = total ÷ 1.19`
- Customer pays the displayed amount (no surprise at checkout)

**Purchases (Tax Added):**
- Suppliers quote **net prices** (before tax)
- We **add** tax on top to get total: `total = net + (net × 0.19)`
- Common in B2B transactions where tax is itemized separately

## Accounting Impact

**Sales IVA (Débito Fiscal):**
- Credit account (liability)
- We owe this to SII (Chilean tax authority)
- Account code: 2110

**Purchase IVA (Crédito Fiscal):**
- Debit account (asset)
- We can claim this back from SII
- Account code: 2120

**Net IVA Payable:**
```
Sales IVA - Purchase IVA = Amount owed to tax authority
```

**Example:**
- Sold $1,190,000 with IVA → Sales IVA = $190,000 (liability)
- Bought $595,000 with IVA → Purchase IVA = $95,000 (asset)
- Net IVA Payable = $190,000 - $95,000 = $95,000 owed to SII

---

**⚠️ CRITICAL FOR COPILOT:**
- **NEVER** use the same calculation for sales and purchases
- **ALWAYS** check if you're in sales or purchases module
- Sales: Divide by 1.19 to extract tax
- Purchases: Multiply by 0.19 to add tax
- This is Chilean tax law compliance - incorrect calculations = legal issues

---

**Bidirectional Cascade Delete:**

# 🎨 UI/UX Standards

## Calendar/Timeline Views

- Use **flutter_calendar_carousel** for month view
- Color coding by status (pending, in_progress, completed)
- Click event → detail panel (split view on desktop, modal on mobile)
- Show bike brand/model instead of internal codes
- Timeline items sorted by date DESC

## Form Validation

- Required fields marked with red asterisk (*)
- Real-time validation on blur
- Error messages below field (red text)
- Success messages via SnackBar (green)
- Prevent submit if validation fails

## Responsive Design

- Desktop (>900px): Sidebar + content area
- Tablet (600-900px): Collapsible drawer
- Mobile (<600px): Bottom navigation + hamburger menu
- Tables adapt to cards on mobile
- Forms stack vertically on narrow screens

## Loading States

- Show CircularProgressIndicator while fetching data
- Skeleton loaders for lists (shimmer effect)
- Disable buttons during async operations
- Display "No data" message if results empty

---

# 🔐 Row Level Security (RLS) Best Practices

## Policy Template (Copy-Paste for New Tables)

```sql
-- Enable RLS
alter table table_name enable row level security;

-- Drop old policies
drop policy if exists "table_select" on table_name;
drop policy if exists "table_insert" on table_name;
drop policy if exists "table_update" on table_name;
drop policy if exists "table_delete" on table_name;

-- Create new policies
create policy "table_select" on table_name
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "table_insert" on table_name
  for insert to authenticated
  with check (tenant_id = public.user_tenant_id());

create policy "table_update" on table_name
  for update to authenticated
  using (tenant_id = public.user_tenant_id());

create policy "table_delete" on table_name
  for delete to authenticated
  using (tenant_id = public.user_tenant_id());
```

**CRITICAL:** Always include `to authenticated` or policy defaults to public role (bypasses RLS)!

---

# 📝 Naming Conventions

## Database

- Tables: `snake_case` plural (e.g., `sales_invoices`, `mechanic_jobs`)
- Columns: `snake_case` (e.g., `invoice_number`, `total_amount`)
- Functions: `snake_case` (e.g., `create_sales_invoice_journal_entry`)
- Triggers: `trg_<table>_<action>` (e.g., `trg_sales_invoices_change`)
- Indexes: `idx_<table>_<column>` (e.g., `idx_products_tenant`)
- Foreign keys: `<table_singular>_id` (e.g., `customer_id`, `product_id`)

## Flutter/Dart

- Classes: `PascalCase` (e.g., `SalesInvoice`, `BikeshopService`)
- Files: `snake_case` (e.g., `sales_invoice.dart`, `bikeshop_service.dart`)
- Variables/functions: `camelCase` (e.g., `getTenantId()`, `invoiceNumber`)
- Constants: `lowerCamelCase` (e.g., `defaultCurrency = 'CLP'`)
- Private members: prefix with `_` (e.g., `_tenantId`, `_loadData()`)

## SQL Variables

- Prefix with `v_` for local variables (e.g., `v_tenant_id`, `v_total`)
- Prefix with `p_` for parameters (e.g., `p_invoice_id`, `p_tenant_id`)

---

# 🛒 GOOGLE MERCHANT CENTER INTEGRATION

**Complete guide for feeding products to Google Merchant Center and getting approved.**

## Architecture Overview

```
Products Table (with is_google_merchant=true)
         ↓
Supabase Edge Function (google-merchant-feed)
         ↓
XML RSS 2.0 Feed (https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-merchant-feed?tenant=vinabike)
         ↓
Google Merchant Center (fetches feed every 24h)
         ↓
Google Shopping / Free Listings
```

**Feed URL Pattern:**
- By subdomain: `https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-merchant-feed?tenant={subdomain}`
- By custom domain: `https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-merchant-feed?domain={custom_domain}`

**Feed Location:** `supabase/functions/google-merchant-feed/index.ts`

---

## 🚨 CRITICAL: Product Approval Requirements

### Mandatory Fields (Google WILL Reject Without These)

| Field | Database Column | Description | Example |
|-------|-----------------|-------------|---------|
| **ID** | `id` (UUID) | Unique product identifier | `775815ba-4c04-4ad8-b037-33d9ed70f06a` |
| **Title** | `name` | Product name (150 char max) | `Aceite Mineral Shimano SM-DBOIL 1 Litro` |
| **Description** | `description` | Min 150 chars! | Detailed product description |
| **Link** | Generated | Product URL | `https://vinabike.cl/productos/{id}` |
| **Image Link** | `image_url` | Main product image | Must be HTTPS, min 100x100px |
| **Price** | `price` + `price_currency` | With currency | `15990 CLP` |
| **Availability** | `stock_quantity` | In stock / Out of stock | Based on stock > 0 |
| **Brand** | `brand_id` → `product_brands.name` | Manufacturer | `Shimano`, `KMC` |
| **Condition** | Hardcoded | Always `new` | `new` |

### Product Identifiers: GTIN vs MPN vs identifier_exists

**🚨 THE #1 REJECTION REASON: Incorrect identifier setup!**

Google requires ONE of these combinations:
1. ✅ **GTIN** (preferred) - Universal Product Code (UPC/EAN/ISBN)
2. ✅ **Brand + MPN** - Manufacturer Part Number
3. ✅ **identifier_exists=false** - For custom/handmade products only

**Database Columns:**
- `gtin` → `<g:gtin>` tag (12-14 digits)
- `sku` → `<g:mpn>` tag (Manufacturer Part Number)

---

## 📋 REAL-WORLD EXAMPLE: Fixing Rejected Products

### Case Study: Shimano SM-DBOIL Mineral Oil

**Initial State (REJECTED):**
```json
{
  "name": "ACEITE MINERAL SHIMANO SM-DBOIL 1 LITRO",
  "sku": "S56467",
  "gtin": null,           // ❌ EMPTY!
  "mpn": "022255354042"   // ❌ WRONG FIELD! This is a UPC, not MPN
}
```

**Google's Rejection Reason:** "Missing GTIN for this product"

**The Problem:** The UPC barcode `022255354042` was stored in the wrong field (`mpn` instead of `gtin`).

**The Fix:**
```sql
UPDATE products 
SET gtin = '022255354042', 
    mpn = null  -- Clear the wrong field
WHERE id = '775815ba-4c04-4ad8-b037-33d9ed70f06a';
```

**Corrected State (APPROVED):**
```json
{
  "name": "Aceite Mineral Shimano SM-DBOIL 1 Litro",
  "sku": "S56467",
  "gtin": "022255354042",  // ✅ CORRECT! UPC in GTIN field
  "mpn": null
}
```

**Feed Output After Fix:**
```xml
<item>
  <g:id>775815ba-4c04-4ad8-b037-33d9ed70f06a</g:id>
  <g:title>Aceite Mineral Shimano SM-DBOIL 1 Litro</g:title>
  <g:gtin>022255354042</g:gtin>  <!-- ✅ Now in correct tag -->
  <g:mpn>S56467</g:mpn>          <!-- SKU becomes MPN -->
  <g:brand>Shimano</g:brand>
  ...
</item>
```

---

## 🔤 UNDERSTANDING GTIN, MPN, SKU, and BARCODE

### Field Definitions

| Field | What It Is | Who Assigns It | Format | Example |
|-------|-----------|----------------|--------|---------|
| **GTIN** | Global Trade Item Number | Manufacturer | 8-14 digits (UPC/EAN) | `022255354042` |
| **MPN** | Manufacturer Part Number | Manufacturer | Alphanumeric | `SM-DBOIL-1L` |
| **SKU** | Stock Keeping Unit | Retailer (YOU) | Any format | `S56467` |
| **Barcode** | Physical barcode on product | Usually = GTIN | Numeric | `022255354042` |

### How to Identify a GTIN

**GTIN is a UPC, EAN, or ISBN barcode number:**
- **UPC-A** (USA/Canada): 12 digits, starts with 0-1 → `022255354042`
- **EAN-13** (International): 13 digits → `4715575883212`
- **ISBN** (Books): 13 digits, starts with 978/979 → `9780123456789`

**To find GTIN:**
1. Look at product barcode → that number IS the GTIN
2. Search manufacturer's website for product specs
3. Use barcode lookup sites: `https://www.barcodelookup.com/`

### Database Column Mapping

| Database Column | Feed Tag | What to Store |
|-----------------|----------|---------------|
| `gtin` | `<g:gtin>` | UPC/EAN barcode number (12-14 digits) |
| `sku` | `<g:mpn>` | Your internal SKU (retailer code) |
| `barcode` | Fallback for gtin | If gtin is empty, feed uses barcode |

**⚠️ CRITICAL: `sku` maps to `<g:mpn>`, NOT the other way around!**

Our feed logic:
```typescript
// GTIN: prefer gtin field, fallback to barcode
const gtin = product.gtin || product.barcode || ''

// MPN: use SKU (our internal code)
const mpn = product.sku || ''
```

---

## 🏷️ Products WITHOUT GTIN (identifier_exists=false)

For products that genuinely don't have a GTIN:
- Custom/handmade products
- Local/artisan products
- Very old products without barcodes
- Store-branded items

**Feed Logic:**
```typescript
if (gtin && gtin.length >= 8) {
  itemXml += `<g:gtin>${gtin}</g:gtin>`
} else {
  // No valid GTIN - must explicitly mark
  itemXml += `<g:identifier_exists>false</g:identifier_exists>`
}
```

**⚠️ WARNING:** Google scrutinizes products with `identifier_exists=false`. Only use for genuinely unique products!

---

## 📝 Product Data Quality Checklist

### Before Enabling Google Merchant for a Product:

- [ ] **Title:** Clear, descriptive, NO ALL CAPS (feed auto-fixes excessive caps)
- [ ] **Description:** Minimum 150 characters (feed auto-expands if shorter)
- [ ] **Image:** At least 100x100px, HTTPS URL, white/clean background preferred
- [ ] **Price:** Greater than 0, correct currency (CLP for Chile)
- [ ] **Brand:** Must be set (either brand_id or brand text field)
- [ ] **GTIN:** If product has barcode, enter the barcode number here
- [ ] **SKU:** Your internal stock code (becomes MPN in feed)
- [ ] **Stock:** Set accurate inventory (affects availability status)
- [ ] **Category:** Assigned to a product category

### Enable in Product Form:

1. Set `is_published = true` (required for website)
2. Set `is_google_merchant = true` (enables in feed)
3. Set `lifecycle_status = 'active'`

---

## 🔧 Database Fields for Google Merchant

### Products Table Columns (Relevant to Feed)

```sql
-- Core product data
name text not null,
sku text,                    -- Becomes <g:mpn>
description text,
price numeric not null,
price_currency text default 'CLP',
stock_quantity integer,

-- Images
image_url text,              -- Main image → <g:image_link>
image_urls text[],           -- Gallery → <g:additional_image_link>

-- Identifiers
gtin text,                   -- UPC/EAN → <g:gtin>
barcode text,                -- Fallback for GTIN

-- Brand & Category
brand_id uuid references product_brands(id),
brand text,                  -- Fallback if no brand_id
category_id uuid references product_categories(id),
category_name text,          -- Fallback for category

-- Visibility flags
is_active boolean default true,
is_published boolean default false,      -- Must be true for website
is_google_merchant boolean default false, -- Must be true for feed
lifecycle_status text default 'active',
```

### Updating GTIN via API

```bash
# Get product current state
source .env && curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/products?id=eq.{PRODUCT_ID}" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | jq '.[0] | {name, sku, gtin, mpn, barcode}'

# Update GTIN
source .env && curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/rest/v1/products?id=eq.{PRODUCT_ID}" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -X PATCH \
  -d '{"gtin": "YOUR_BARCODE_NUMBER"}' | jq '.[0] | {name, sku, gtin}'
```

---

## 🔄 Feed Refresh & Troubleshooting

### Google Merchant Center Re-fetch

After fixing product data:
1. Wait 1-4 hours for feed cache to expire (Cache-Control: 1 hour)
2. Or manually trigger re-fetch in Google Merchant Center:
   - Products → Feeds → Your Feed → Fetch Now
3. Products re-index within 24-48 hours

### Common Rejection Reasons & Fixes

| Rejection | Cause | Fix |
|-----------|-------|-----|
| "Missing GTIN" | GTIN field empty for branded product | Add barcode to `gtin` column |
| "Invalid GTIN" | Wrong format or checksum | Verify barcode, use valid UPC/EAN |
| "Mismatched identifiers" | GTIN doesn't match product | Double-check barcode matches product |
| "Description too short" | Less than ~100 chars | Add more detail (feed auto-expands) |
| "Image too small" | Less than 100x100px | Upload larger image |
| "Price missing" | price = 0 or null | Set valid price > 0 |
| "Generic image" | Product image shows brand logo only | Use actual product photo |

### Testing Feed Locally

```bash
# Fetch feed and check product output
curl "https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-merchant-feed?tenant=vinabike" | head -100

# Count products in feed
curl -s "https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-merchant-feed?tenant=vinabike" | grep -c "<item>"
```

---

## 🛠️ Flutter Product Form: Google Merchant Fields

**Location:** `lib/modules/inventory/pages/product_form_page.dart`

The product form includes these Google Merchant-relevant fields:

1. **Basic Info Tab:**
   - Name (becomes title)
   - SKU (becomes MPN)
   - Description (needs 150+ chars)
   - Price & Currency

2. **Details Tab:**
   - Brand (dropdown from product_brands)
   - GTIN field (for barcode)
   - Category (for product_type)

3. **Publishing Section:**
   - `is_published` toggle → Required for website
   - `is_google_merchant` toggle → Enables in feed

---

## 📊 Google Merchant Category (google_product_category)

The feed uses numeric category IDs from Google's taxonomy:

```typescript
// Current hardcoded: Cycling Accessories
itemXml += `<g:google_product_category>3618</g:google_product_category>`
```

**Common Cycling Categories:**
- `1085` - Bicycles
- `3618` - Bicycle Parts & Accessories
- `3636` - Bicycle Tires & Tubes
- `3612` - Bicycle Frames

**Future Enhancement:** Map `product_categories` to Google taxonomy IDs.

---

## ✅ Copilot Checklist: Adding Products to Google Merchant

When enabling a product for Google Merchant:

1. ✅ **Verify product has GTIN or set `identifier_exists=false`**
   - If barcode exists → Put it in `gtin` column
   - If no barcode → Product needs `identifier_exists=false` (auto-handled by feed)

2. ✅ **Check description length** → Must be 150+ characters

3. ✅ **Verify image exists** → `image_url` must be set, HTTPS

4. ✅ **Confirm price > 0** → Feed filters out $0 products

5. ✅ **Set brand** → Either `brand_id` or `brand` text must be set

6. ✅ **Enable flags:**
   ```sql
   UPDATE products SET
     is_active = true,
     is_published = true,
     is_google_merchant = true,
     lifecycle_status = 'active'
   WHERE id = 'product-uuid';
   ```

7. ✅ **Test in feed** → Check XML output for correct tags

---

# 🧪 Testing Multi-Tenant Isolation

```sql
-- Verify RLS is working
SELECT 
  schemaname, 
  tablename, 
  rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename NOT LIKE 'pg_%'
ORDER BY tablename;
-- All tenant tables should have rowsecurity = true

-- Check policies exist
SELECT tablename, policyname, roles, cmd 
FROM pg_policies 
WHERE tablename = 'your_table_name';
-- Should show 4 policies (SELECT, INSERT, UPDATE, DELETE) with {authenticated} role

-- Test data isolation
SELECT * FROM your_table WHERE tenant_id = public.user_tenant_id();
-- Should only return current user's tenant data
```

**Never test in SQL Editor with service role** - it bypasses RLS! Always test from Flutter app as authenticated user.

---

# 💰 PAYROLL SYSTEM ARCHITECTURE (Dec 2025)

**Complete documentation of the Payroll Voucher system and its integration with Accounting.**

## Overview

The Payroll system automates:
1. Salary calculations based on attendance/hours worked
2. Expense creation for each employee payment
3. Journal entry generation for proper accounting

## Database Tables

| Table | Purpose |
|-------|---------|
| `payroll_vouchers` | Header record for each payroll period (weekly/monthly) |
| `payroll_voucher_lines` | One line per employee with hours, rates, totals |
| `employees.salary_account_id` | FK to personal expense account (6101-XX) |

## Account Structure (6101-XX Hierarchy)

```
6101 - Sueldos y Salarios (Parent)
├── 6101-01 - Salario - [Employee 1]
├── 6101-02 - Salario - [Employee 2]
└── 6101-XX - Salario - [Employee N]
```

**Auto-creation:** When an employee is created, trigger `trg_create_employee_salary_account` automatically creates a sub-account under 6101.

## Key Fields for Payment Tracking

**In `payroll_voucher_lines`:**
```sql
payment_method_id UUID REFERENCES payment_methods(id)  -- FK to payment method
payment_account_id UUID REFERENCES accounts(id)        -- FK to Bank/Cash account (source)
salary_account_id UUID REFERENCES accounts(id)         -- FK to expense account (destination)
```

**⚠️ CRITICAL:** Both `payment_method_id` AND `payment_account_id` must be populated for correct journal entries!

## RPC Functions

### `generate_payroll_voucher_draft(period_start, period_end, period_label)`
- Creates voucher header and line items from attendance summary
- Pre-fills hours, rates, and calculated amounts
- Status: `draft`

### `pay_payroll_voucher(voucher_id)`
- Creates an `expense` record for each employee line
- Creates `expense_lines` with proper account references
- Triggers `create_expense_journal_entry()` via database triggers
- Status: `paid`

## Journal Entry Flow

When `pay_payroll_voucher` is called:

```
1. INSERT expenses (payment_status='paid', balance=0, posting_status='posted')
      ↓
2. INSERT expense_lines (account_id = salary_account_id from employee)
      ↓
3. TRIGGER: trg_expense_lines_change fires handle_expense_line_change()
      ↓
4. TRIGGER calls: create_expense_journal_entry(expense_id)
      ↓
5. JE Created with:
   - DEBIT: 6101-XX (Salary Expense)
   - CREDIT: 1102 (Bank) or 1101 (Cash)
```

## Income Statement Visibility

**Accrual Mode (Devengado):** Queries `journal_entries` + `journal_lines` by account type

**Cash Flow Mode (Efectivo):** Queries:
1. `sales_payments` for income
2. `purchase_payments` for supplier payments
3. `expenses` (where `payment_status='paid'`) for operating expenses including payroll

**⚠️ If payroll doesn't appear in Cash Flow mode, check:**
- `expenses.paid_at` is within date range
- `expenses.payment_status = 'paid'`
- `expenses.balance = 0`
- The `get_income_statement_data` function has the UNION for paid expenses

---

# 🔢 ACCOUNTING CONSISTENCY RULES (CRITICAL!)

**Common bugs and how to prevent them when creating accounting-related features.**

## Rule 1: Journal Entries Must Balance

```sql
-- ✅ Every JE must have: SUM(debits) = SUM(credits)
-- Verify with:
SELECT je.entry_number, 
       SUM(jl.debit_amount) as total_debit,
       SUM(jl.credit_amount) as total_credit
FROM journal_entries je
JOIN journal_lines jl ON jl.entry_id = je.id
GROUP BY je.id, je.entry_number
HAVING SUM(jl.debit_amount) <> SUM(jl.credit_amount);
-- Should return NO ROWS if balanced
```

## Rule 2: Expense JE Requires `balance = 0` AND `payment_status = 'paid'`

See `create_expense_journal_entry()` lines 7412-7414:
```sql
if payment_status = 'paid'
   AND balance <= 0.01
   AND v_cash_account.id IS NOT NULL then
   -- Creates CREDIT to Bank/Cash
```

**⚠️ If you create expenses via RPC, include:**
```sql
payment_status := 'paid',
balance := 0,
payment_account_id := [valid bank/cash account UUID],
payment_method_id := [valid payment method UUID],
```

## Rule 3: Account Types Must Be Correct

| Account Code Range | Type | Category | Shows In |
|--------------------|------|----------|----------|
| 4000-4999 | `income` | `operatingIncome` | Income Statement (Ingresos) |
| 5000-5199 | `expense` | `costOfGoodsSold` | Income Statement (Costo de Ventas) |
| 6000-6999 | `expense` | `operatingExpense` | Income Statement (Gastos Operacionales) |
| 1000-1999 | `asset` | varies | Balance Sheet (Activos) |
| 2000-2999 | `liability` | varies | Balance Sheet (Pasivos) |

**⚠️ If expenses don't appear in reports, verify:**
```sql
SELECT code, name, type, category, is_active 
FROM accounts WHERE code LIKE '6%';
-- Must have: type='expense', category='operatingExpense', is_active=true
```

## Rule 4: Cash Flow Reports Need Specific Tables

**Cash Flow Mode reads from:**
- `sales_payments` - for realized income
- `purchase_payments` - for supplier payments
- `expenses` (paid) - for direct expenses (payroll, operating)

**⚠️ If you create a new payment type, update `get_income_statement_data` to include it!**

## Rule 5: Always Set `is_active = true` for New Accounts

The Income Statement filter includes:
```sql
WHERE a.is_active = true
```

If accounts are created without `is_active` or with `false`, they won't appear.

## Debugging Checklist

When a transaction doesn't appear in financial reports:

1. ✅ Does the journal entry exist? (`SELECT * FROM journal_entries WHERE source_reference = ...`)
2. ✅ Does it have journal lines? (`SELECT * FROM journal_lines WHERE entry_id = ...`)
3. ✅ Is `status = 'posted'`? (Draft entries don't count)
4. ✅ Is `entry_date` within the report's date range?
5. ✅ Do the accounts have correct `type` and `category`?
6. ✅ Are the accounts `is_active = true`?
7. ✅ For Cash Flow: is `paid_at` within the date range?
8. ✅ For Cash Flow: is `payment_status = 'paid'` and `balance = 0`?

---

# 🔧 PAYROLL DEPLOYMENT CHECKLIST

**When deploying payroll changes:**

1. ✅ **Schema:** `payroll_vouchers`, `payroll_voucher_lines` tables exist
2. ✅ **Columns:** `payment_method_id`, `payment_account_id` on lines table
3. ✅ **Employee Accounts:** All employees have `salary_account_id` populated
4. ✅ **Account 6101:** Parent account exists with correct structure
5. ✅ **RPC:** `pay_payroll_voucher` includes `balance = 0` in expense INSERT
6. ✅ **RPC:** Uses explicit `payment_account_id` and `payment_method_id` from lines
7. ✅ **Cash Flow:** `get_income_statement_data` has UNION for paid expenses

**Quick Fix SQL if payroll expenses are missing from Cash Flow:**

```sql
-- Verify expenses exist and are paid
SELECT expense_number, payment_status, balance, paid_at 
FROM expenses WHERE reference LIKE 'Semana%';

-- If balance is NULL or > 0, fix:
UPDATE expenses SET balance = 0 
WHERE payment_status = 'paid' AND (balance IS NULL OR balance > 0);

-- Regenerate journal entries if needed
UPDATE expenses SET updated_at = NOW() 
WHERE reference LIKE 'Semana%' AND payment_status = 'paid';
```

---

# 📊 ACCOUNTING FUNDAMENTALS (IFRS/GAAP COMPLIANT)

**THIS SECTION IS CRITICAL FOR ANYONE WORKING ON FINANCIAL FEATURES.**

This ERP follows international accounting standards (IFRS/GAAP). Understanding these principles is **mandatory** before making changes to accounting-related code.

---

## 1️⃣ The Two Financial Statements

| Statement | Spanish Name | Purpose | Accounting Method |
|-----------|--------------|---------|-------------------|
| **Income Statement** | Estado de Resultados | Shows profitability (Did we make money?) | **Accrual** |
| **Cash Flow Statement** | Estado de Flujo de Efectivo | Shows liquidity (Do we have money?) | **Cash** |

### Key Mental Model:
- **Income Statement:** *Did we make money?* (Profitability)
- **Cash Flow Statement:** *Do we have money?* (Liquidity)

**⚠️ CRITICAL: A profitable business can fail if it runs out of cash. These are DIFFERENT concepts!**

---

## 2️⃣ Accrual vs Cash Basis Accounting

| Aspect | Accrual Basis (Devengado) | Cash Basis (Efectivo) |
|--------|---------------------------|------------------------|
| **Revenue recognition** | When earned (sale made) | When cash received |
| **Expense recognition** | When incurred (obligation exists) | When cash paid |
| **Primary focus** | Profitability | Liquidity |
| **Used for** | Income Statement | Cash Flow Statement |

### Example:
You sell a bike on December 15 for $1,000, customer pays on January 5.

- **Income Statement (December):** Shows $1,000 revenue ✅
- **Cash Flow Statement (December):** Shows $0 from this sale ❌
- **Cash Flow Statement (January):** Shows $1,000 received ✅

---

## 3️⃣ COGS: The Most Common Misunderstanding

> **COGS measures cost recognition; cash flow measures cash movement — the difference is inventory and payables.**

### ❌ Common Mistake:
*"COGS equals cash spent on inventory"* — **WRONG**

### ✅ Correct Understanding:

| Concept | What It Is | When Recorded | Which Report |
|---------|------------|---------------|--------------|
| **COGS** | Cost of goods **SOLD** | When sale happens | Income Statement |
| **Payments to Suppliers** | Cash paid for inventory | When cash is paid | Cash Flow Statement |

### Example:
You buy 100 bikes in January for $500 each ($50,000 total).
You sell 80 bikes in March.

- **Income Statement (January):** COGS = $0 (nothing sold yet)
- **Income Statement (March):** COGS = $40,000 (80 bikes × $500)
- **Cash Flow Statement (January):** Payments to Suppliers = -$50,000

### The Formula:
```
Cash Paid to Suppliers = COGS + Increase in Inventory − Increase in Accounts Payable
```

**High COGS with low cash outflow** → You're buying on credit
**Low COGS with high cash outflow** → You're paying down old supplier bills

---

## 4️⃣ Journal Entry Rules

### Double-Entry Accounting:
Every transaction has **two sides** that must balance:
```
DEBIT = CREDIT (always!)
```

### The Nature of Accounts:

| Account Type | Normal Balance | To Increase | To Decrease |
|--------------|----------------|-------------|-------------|
| **Asset** (1xxx) | Debit | Debit | Credit |
| **Liability** (2xxx) | Credit | Credit | Debit |
| **Equity** (3xxx) | Credit | Credit | Debit |
| **Revenue** (4xxx) | Credit | Credit | Debit |
| **Expense** (5xxx-6xxx) | Debit | Debit | Credit |

### Common Journal Entries:

**Sale (Invoice Created):**
```
DEBIT:  1200 Accounts Receivable     $1,000
CREDIT: 4100 Sales Revenue                   $1,000
DEBIT:  5100 Cost of Goods Sold      $600
CREDIT: 1300 Inventory                       $600
```

**Sale Payment Received:**
```
DEBIT:  1102 Bank                    $1,000
CREDIT: 1200 Accounts Receivable             $1,000
```

**Purchase (Invoice Created):**
```
DEBIT:  1300 Inventory               $500
CREDIT: 2100 Accounts Payable                $500
```

**Purchase Payment Made:**
```
DEBIT:  2100 Accounts Payable        $500
CREDIT: 1102 Bank                            $500
```

**Payroll Expense:**
```
DEBIT:  6101-XX Salary - [Employee]  $5,000
CREDIT: 1102 Bank                            $5,000
```

---

## 5️⃣ Account Code Structure (Chile SII Aligned)

```
1xxx - ASSETS (Activos)
  1100 - Cash & Bank
    1101 - Caja General
    1102 - Bancos - Cuenta Corriente
  1200 - Accounts Receivable
  1300 - Inventory (Inventario)

2xxx - LIABILITIES (Pasivos)
  2100 - Accounts Payable (Proveedores)
  2200 - Taxes Payable

3xxx - EQUITY (Patrimonio)
  3100 - Capital
  3200 - Retained Earnings

4xxx - REVENUE (Ingresos)
  4100 - Sales Revenue (Ventas)

5xxx - COST OF GOODS SOLD (Costo de Ventas)
  5100 - COGS (calculated when inventory is sold)

6xxx - OPERATING EXPENSES (Gastos Operacionales)
  6100 - Payroll & HR
    6101 - Sueldos y Salarios
      6101-01 - Salario - [Employee 1]
      6101-02 - Salario - [Employee 2]
  6200 - Rent & Utilities
  6300 - Marketing & Advertising
  6400 - Office Expenses
```

---

## 6️⃣ Report Implementation in This ERP

### Income Statement (Devengado) - `get_income_statement_data(is_cash_flow=false)`

Queries **journal entries** and **journal lines** to show:
- Revenue (when earned)
- COGS (when sold)
- Operating Expenses (when incurred)

```sql
-- Uses journal entries grouped by account
FROM accounts a
JOIN journal_lines jl ON jl.account_id = a.id
JOIN journal_entries je ON je.id = jl.entry_id
WHERE je.entry_date BETWEEN start_date AND end_date
  AND je.status = 'posted'
```

### Cash Flow Statement (Efectivo) - `get_income_statement_data(is_cash_flow=true)`

Queries **payment tables** to show actual cash movements:
- Cash IN: `sales_payments` (customer payments)
- Cash OUT: `purchase_payments` (supplier payments)
- Cash OUT: `expenses` where `payment_status='paid'` (operating expenses)

```sql
-- Uses payment tables directly
FROM sales_payments WHERE date BETWEEN start_date AND end_date
UNION ALL
FROM purchase_payments WHERE date BETWEEN start_date AND end_date
UNION ALL
FROM expenses WHERE paid_at BETWEEN start_date AND end_date
```

---

## 7️⃣ Common Accounting Bugs and Prevention

### Bug: Expenses don't appear in Cash Flow
**Cause:** Missing `payment_status = 'paid'` or `paid_at` is NULL
**Fix:** Set both when paying an expense

### Bug: COGS shows on wrong report
**Cause:** Confusing "payments to suppliers" with COGS
**Fix:** Purchase payments → Cash Flow; COGS from sales → Income Statement

### Bug: Journal entry doesn't balance
**Cause:** Only created debit side, forgot credit
**Fix:** Every INSERT into journal_lines must have matching debit/credit

### Bug: Transaction appears in wrong period
**Cause:** Using `created_at` instead of `entry_date` or `paid_at`
**Fix:** Always use the proper date field for the report type

### Bug: Account shows $0 in reports
**Cause:** `is_active = false` or wrong `type`/`category`
**Fix:** Verify account configuration

---

## 8️⃣ Before Creating Any Accounting Feature

**Mandatory Questions:**

1. ✅ Is this going on the Income Statement or Cash Flow Statement?
2. ✅ Am I using accrual (journal entries) or cash (payment tables)?
3. ✅ Does every journal entry balance (debits = credits)?
4. ✅ Am I using the correct account codes and types?
5. ✅ Is the timing correct (entry_date for accrual, paid_at for cash)?

**⚠️ DO NOT:**
- ❌ Confuse COGS with payments to suppliers
- ❌ Put cash transactions in journal entries (use payment tables)
- ❌ Create unbalanced journal entries
- ❌ Forget to set `is_active = true` on new accounts
- ❌ Use wrong account types/categories

**✅ ALWAYS:**
- ✅ Understand the difference between profitability and liquidity
- ✅ Use proper account codes from the chart of accounts
- ✅ Test reports in both Devengado AND Efectivo modes
- ✅ Verify journal entries balance
- ✅ Check that transactions appear in correct periods

---

# 🧭 Public Store Routing & Animations (Jan 2026)

This section documents the **routing + navigation layer changes** done to make route transitions reliably visible (and debuggable) while keeping the public store stable across **desktop + mobile** and across environments (**vinabike.cl** public domain vs ERP host).

## Goals

- Make navigation transitions **actually animate** (instead of feeling instant).
- Avoid route regressions like `GoException: no routes for location: /<uuid>`.
- Keep **ERP-mounted** store routes (`/tienda/*`) and **public store** routes (`/*`) consistent.
- Ensure the behavior is consistent on **desktop and mobile**.

## What’s safe / unchanged

- The route map and redirects in `lib/public_store/routes/public_store_router.dart` remain the source of truth for store URLs (clean paths + legacy `/tienda/*` support).
- No changes to `web/index.html`, SEO sync (`scripts/sync_seo_index.sh`), JSON-LD, snapshots, or the Firebase deploy workflow.
- Edit/preview entry rules remain: `?preview=true` and `?edit=true` are still honored.
- The bridging helper `_routeForPublicStore()` is still the canonical way to translate between legacy `/tienda/*` and clean store routes.

## What changed (scoped + reversible)

All behavioral changes are intentionally scoped to the public store layout navigation layer:

### 1) Navigation normalization happens in one place

- Use `PublicStoreLayout._navigateToHref(...)` as the single entry-point for internal navigation from menus, logo, footer links, block buttons, etc.
- This prevents mismatched behavior from direct `context.go(...)` calls scattered across UI.

### 2) UUID href normalization (page-first, product fallback)

Problem observed: some links coming from website navigation/blocks were bare UUIDs, but those UUIDs were often `website_pages.id` (not product ids). That caused:

- `/<uuid>` → router had no match → crash
- Or treating UUID as product → “Producto no encontrado”

Fix:

- If an href is a bare UUID, navigation now tries to resolve it as `website_pages.id` first (route by slug) before treating it as a product id.
- If pages aren’t loaded yet at click time, the resolution lazily loads pages for the tenant and/or falls back to `getPageById(uuid)`.

### 3) `push()` vs `go()` strategy to preserve animations and stability

- Use `push()` for normal navigation so `CustomTransitionPage` animations are visible.
- Use `go()` only for “home-like” targets (`/`, `/tienda`) to avoid stacking redirect/history states that can create “blank” browser history situations.

### 4) Mobile menu fix: never navigate with a disposed bottom-sheet context

On mobile web, the drawer/bottom-sheet menu items could appear “broken” because they did:

- `Navigator.pop(sheetContext);`
- then tried to navigate using that same `sheetContext`

Fix:

- Capture the parent page `BuildContext` before opening the sheet (e.g., `navContext`).
- Pop the sheet with `sheetContext`, but always call `_navigateToHref(navContext, ...)` for navigation.

This is required for consistent behavior on mobile.

## Animations implemented (and how to keep doing it)

### Router-level transitions (primary)

- Store router pages use `CustomTransitionPage` (fade + slide) with durations tuned to be visible.
- Reduced-motion is respected:
  - If `MediaQuery.disableAnimations` or `MediaQuery.accessibleNavigation` is true, fall back to `NoTransitionPage`.

### Content-level transitions (fallback for “hard to notice” route changes)

Some route changes can still feel instant (same layout shell, sticky header, etc.). To make navigation perceptible:

- The store layout wraps its body content in an `AnimatedSwitcher` keyed by the current URI.
- This is disabled in editor contexts (`edit/preview`) and when reduced motion is enabled.
- Be careful to apply the switcher in all layout variants (e.g., sticky header path), otherwise transitions may “disappear” depending on breakpoint.

### Hover micro-animations (desktop-only)

- Hover effects (e.g., subtle scale) are desktop UX sugar; they must not be required for correctness.
- Ensure hover widgets are not used in a way that breaks touch/semantics on mobile.

## Guardrails for future changes

### ✅ Always do this

- Use `_navigateToHref(...)` for UI-driven navigation inside the public store.
- Route legacy paths through `_routeForPublicStore(...)` (never hardcode `/tienda/...` or assume clean paths).
- Prefer `push()` for animated transitions; reserve `go()` for “home-like” navigations.
- Keep behavior identical across desktop/mobile:
  - Don’t rely on `kIsWeb` host heuristics alone.
  - Don’t use disposable overlay contexts for routing.
- When adding new routes, add both:
  - clean path (public store)
  - legacy `/tienda/*` redirect (ERP mounted)

### ❌ Avoid this

- Direct `context.go('/tienda/...')` in the public store UI.
- Using a bottom-sheet/dialog context for routing after popping the overlay.
- Introducing routes that exist only in one environment (ERP host vs public store) unless there is a redirect/bridge.
- Making transitions depend on `go()` navigations (they often won’t animate).

## Practical verification checklist (5 minutes)

### Public domain mode (vinabike.cl)

- Open the mobile menu and tap: Iniciar Sesión / Inicio / Productos / Contacto.
- Confirm URLs are clean (`/cuenta/login`, `/`, `/productos`, `/contacto`).
- Tap a product card → `/productos/<id>` loads.

### ERP host mode (project-vinabike…)

- Open `/tienda?preview=true` and `/tienda?edit=true`.
- Navigate via menu/logo/footer and confirm you remain under `/tienda/*`.
- Confirm edit/preview state doesn’t “bounce” due to stale query params.

### Deep links

- Directly open: `/productos`, `/contacto`, `/nosotros`, `/pagina/<slug>`.
