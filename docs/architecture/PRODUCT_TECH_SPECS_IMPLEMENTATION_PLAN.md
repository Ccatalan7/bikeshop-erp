# Product Tech Specs Implementation Plan

## Goal

Implement a category-driven technical spec system for products that also powers:

- guided service selection in jobs and invoices
- compatibility checks and suggestions
- printable customer and mechanic documents
- AI assistant actions based on structured data

The system must be technically powerful, but the day-to-day interaction must stay easy for staff creating products, diagnostics, jobs, and invoices.

## Core Decisions

1. `Ficha Tecnica` must be a top-level tab in the product form.
2. Product classification should be driven by technical family and technical template, not primarily by discipline.
3. Discipline tags like `mtb`, `road`, `bmx`, `gravel`, `urban`, `ebike` should be secondary filters, not the main schema driver.
4. Technical specs should use a hybrid storage model:
   - normalized relational tables as source of truth
   - JSON snapshot on `products.specifications` for fast reads, PDF, AI, and backwards compatibility
5. Services should remain billable products with `product_type = service`, but gain a service profile layer for guided workflows.
6. Jobs and invoices must evolve into structured operational documents, not just simple accounting lines.
7. New categories and new services created in the future should be handled mostly by configuration and mapping, not by new code.

## Design Principles

### Power without friction

- show only relevant fields for the selected product template
- ask only the minimum relevant service questions first
- keep advanced details collapsible
- generate readable summaries automatically

### Progressive disclosure

- basic users see commercial and operational essentials
- advanced users can access deeper technical and compatibility fields

### One source, multiple outputs

The same structured data should power:

- product ficha técnica
- guided service workflows
- printed customer summary
- printed mechanic instructions
- compatibility filtering
- AI assistant reasoning

### Safe fallback behavior

Operations must not be blocked if a category or service has not been fully modeled yet.

## Current State Audit

### Current product category system

The real category backbone already exists in `product_categories` and is already used by the product form.

Live tenant data currently has:

- `133` categories
- `8` root categories
- max depth `4`

Current root categories:

- `Accesorios`
- `BMX`
- `Componentes`
- `Herramientas`
- `Mantenimiento`
- `Otros`
- `Servicio`
- `Viñabike`

The live tree already contains technically meaningful branches such as:

- `Componentes / Frenos / Pastillas`
- `Componentes / Frenos / Rotores`
- `Componentes / Frenos / V-Brake`
- `Componentes / Ruedas / Mazas / Maza`
- `Componentes / Ruedas / Rayos`
- `Componentes / Ruedas / Llantas`
- `Componentes / Ruedas / Neumáticos`
- `Componentes / Transmisión / Cadenas`
- `Componentes / Transmisión / Piñones / Cassette`
- `Componentes / Dirección / Juego de dirección`

Conclusion:

- the current category tree should be audited and mapped to technical templates
- it should not be rebuilt from scratch

### Current category mismatch in code

There is still an old coarse enum in code with categories like `bicycle`, `parts`, `accessories`, `tools`, etc.

Conclusion:

- that enum is too generic for ficha técnica
- the relational `product_categories` tree must become the real backbone for product classification

### Current service model

Two service concepts exist in the codebase:

- service products with `product_type = service`
- `service_packages`

Live tenant data shows:

- `58` service products
- `0` service packages in use
- `50` service products uncategorized
- `8` service products categorized
- categorized services only use the generic category `Servicio`
- `0` service products currently have technical data in `specifications`

Examples already in use:

- `Regulación de frenos`
- `Purgado de Freno Hidráulicos`
- `Servicio de Mazas (C/U)`
- `Centrado de rueda (C/U)`
- `Enrayado + Centrado`
- `Cambio de cámara (no incluye cámara)`
- `Instalación Juego de Dirección`
- `Regulación de Cambios`
- `Mantención de Freno`

Conclusion:

- real business usage is centered on service products, not `service_packages`
- guided workflows should be built on top of service products

## UX Strategy

## Product Form

Recommended tab order:

1. `Detalles Generales`
2. `Ficha Tecnica`
3. `Tienda Online`

### Detalles Generales

Keep this tab commercial and operational:

- product name
- SKU
- supplier code
- category
- product type
- supplier
- brand
- model
- price
- cost
- inventory
- state and visibility
- images
- basic description

### Ficha Tecnica

This becomes the structured technical workspace.

Suggested layout:

1. technical identity card
2. dynamic field sections
3. completeness indicator
4. compatibility summary preview
5. printable technical summary preview

Suggested sections:

- technical identity
- dimensions and measurements
- standards and interfaces
- compatibility attributes
- use and discipline
- mechanic notes
- printable summary

Behavior:

- the tab should auto-resolve the template from the selected category
- the user should not start from a blank technical form
- advanced sections should stay collapsed by default

### Job and Invoice Interaction

The user should start as they do today: select a service or product from autocomplete.

If the selected line has a service profile:

1. open a compact guided panel
2. ask the 2 to 5 highest-value questions first
3. show advanced questions only if necessary
4. suggest parts and consumables
5. generate a readable summary card
6. allow quick edit without reopening a giant form

### Operational Document Principle

One data source should generate two outputs:

- customer-friendly summary
- mechanic-friendly technical detail

The same line should be readable in under 3 seconds by diagnosis staff, client, and mechanic.

## Target Product Model

### Primary classification

- technical family: `hub`, `tire`, `rim`, `rotor`, `brake_pad`, `complete_brake`, `chain`, `cassette`, `rear_derailleur`, `bottom_bracket`, `fork`, `frame`, etc.
- technical template: `front_hub`, `rear_hub`, `tire`, `hydraulic_disc_brake`, `mechanical_disc_brake`, `rim_brake`, etc.

### Secondary classification

- discipline and use tags: `mtb`, `road`, `bmx`, `gravel`, `urban`, `ebike`, etc.

### Why this is the right model

- a hub is a hub first, not an MTB product first
- a tire is a tire first, not a road product first
- discipline matters, but mainly for defaults, filtering, and applicability

## Storage Model

### Source of truth

- `spec_definitions`
- `spec_templates`
- `spec_template_fields`
- `category_tech_mappings`
- `product_spec_values`

### Cached projection

- `products.specifications` remains as JSON summary for:
  - fast reads
  - PDF snapshotting
  - AI context
  - backwards compatibility

## Architecture Decisions — Resolved

### Decision 1: Spec Definitions — System-Level vs Tenant-Level

**Resolution: `tenant_id = NULL` for system definitions, `tenant_id = UUID` for tenant custom definitions.**

- System definitions (e.g. `rotor_diameter_mm`, `pad_shape_code`) have `tenant_id = NULL` and are readable by all tenants.
- Tenants can create custom definitions with their own `tenant_id`.
- RLS select policy: `tenant_id IS NULL OR tenant_id = user_tenant_id()`.
- RLS insert/update/delete: only `tenant_id = user_tenant_id()` — tenants cannot modify system definitions.
- Unique indexes use partial index pattern: `WHERE tenant_id IS NULL` for system keys, `(tenant_id, key) WHERE tenant_id IS NOT NULL` for tenant keys.
- Same pattern applies to `spec_templates`, `service_profiles`, `service_profile_questions`, `service_profile_targets`, `service_profile_task_templates`.
- Seed ~100 system-level spec definitions covering universal bike fields; tenants never need to recreate them.

### Decision 2: Job/Invoice Line Evolution — ALTER vs Parallel Table

**Resolution: ALTER the existing line tables, adding nullable columns.**

- New columns go directly on `mechanic_job_parts` and `sales_invoice_items`.
- All new columns are `NULLABLE` so existing rows are completely unaffected.
- No JOINs to a parallel context table needed on every query.
- New columns: `service_profile_id`, `target_family`, `target_position`, `context_answers_json`, `customer_summary`, `mechanic_summary`, `display_group_key`.
- Migration adds columns with `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`.
- Deferred to Milestone 5 — no changes to line tables until the guided wizard is being built.

### Decision 3: Visibility Rules — Minimal Condition Format

**Resolution: flat array of `{field, operator, value}` conditions. ALL must be true (AND logic). No nested logic in v1.**

```json
[
  {"field": "caliper_hydraulic", "operator": "eq",  "value": true},
  {"field": "brake_system",      "operator": "in",  "value": ["shimano", "magura"]}
]
```

- Applies to both `spec_template_fields.visibility_rules` (references `spec_definition.key`) and `service_profile_questions.visibility_rules` (references `question.key`).
- Supported operators: `eq`, `neq`, `in`, `not_in`.
- If `visibility_rules` is `[]`, the field is always shown.
- OR logic and nested conditions are deferred to v2.
- Use `is_advanced: true` to collapse a field instead of writing complex conditions for it.

### Implementation Order

Start with brakes as the first full-cycle domain:
1. Schema (tables + RLS + indexes)
2. Seed system spec definitions (brake fields)
3. Create brake-domain spec templates and link fields
4. Map Viñabike's live brake categories to templates
5. Create brake service profiles with guided questions, part rules, task templates
6. Map Viñabike's live brake service products to profiles

Once brakes work end-to-end, every other domain (wheels, drivetrain, steering) is configuration only — no new code.

## Database Schema Draft

### `spec_definitions`

Defines every reusable technical field.

Suggested columns:

- `id`
- `tenant_id`
- `key`
- `label`
- `description`
- `data_type` (`text`, `number`, `boolean`, `single_select`, `multi_select`, `range`, `json`)
- `unit`
- `allowed_values` JSONB
- `validation_rules` JSONB
- `is_filterable`
- `is_required_by_default`
- `is_compatibility_relevant`
- `is_customer_visible`
- `is_mechanic_visible`
- `group_name`
- `sort_order`
- `created_at`
- `updated_at`

### `spec_templates`

Defines each ficha técnica schema.

Suggested columns:

- `id`
- `tenant_id`
- `key`
- `name`
- `technical_family`
- `description`
- `default_tags` JSONB
- `is_active`
- `created_at`
- `updated_at`

### `spec_template_fields`

Defines which fields belong to which template.

Suggested columns:

- `id`
- `tenant_id`
- `template_id`
- `spec_definition_id`
- `is_required`
- `section_key`
- `sort_order`
- `default_value_json`
- `visibility_rules` JSONB
- `helper_text`
- `created_at`
- `updated_at`

### `category_tech_mappings`

Maps existing business categories to technical behavior.

Suggested columns:

- `id`
- `tenant_id`
- `category_id`
- `technical_family`
- `template_id`
- `default_tags` JSONB
- `status` (`active`, `pending`)
- `created_at`
- `updated_at`

### `product_spec_values`

Stores the actual product values.

Suggested columns:

- `id`
- `tenant_id`
- `product_id`
- `spec_definition_id`
- `value_text`
- `value_number`
- `value_boolean`
- `value_option`
- `value_json`
- `display_value`
- `created_at`
- `updated_at`

Recommended rule:

- unique on `tenant_id, product_id, spec_definition_id`

### `service_profiles`

Defines the operational behavior of a billable service product.

Suggested columns:

- `id`
- `tenant_id`
- `key`
- `name`
- `service_family`
- `description`
- `customer_summary_template`
- `mechanic_summary_template`
- `is_active`
- `created_at`
- `updated_at`

### `service_product_profile_mappings`

Maps current service products to service profiles.

Suggested columns:

- `id`
- `tenant_id`
- `product_id`
- `service_profile_id`
- `status` (`active`, `pending`)
- `created_at`
- `updated_at`

### `service_profile_targets`

Defines what a service can target.

Suggested columns:

- `id`
- `tenant_id`
- `service_profile_id`
- `target_family`
- `target_position_mode` (`none`, `front_rear`, `left_right`, `both_allowed`)
- `target_rules` JSONB

### `service_profile_questions`

Defines the wizard.

Suggested columns:

- `id`
- `tenant_id`
- `service_profile_id`
- `key`
- `label`
- `question_type`
- `required`
- `sort_order`
- `options_json`
- `visibility_rules` JSONB
- `default_answer_json`

### `service_profile_part_rules`

Defines suggested or required parts based on answers.

Suggested columns:

- `id`
- `tenant_id`
- `service_profile_id`
- `rule_name`
- `conditions_json`
- `suggested_category_ids` JSONB
- `suggested_product_ids` JSONB
- `default_quantity`
- `is_required`

### `service_profile_task_templates`

Defines generated mechanic tasks.

Suggested columns:

- `id`
- `tenant_id`
- `service_profile_id`
- `task_name`
- `task_description`
- `sort_order`
- `conditions_json`

## Live Category to Technical Template Mapping Draft

### Mapping strategy

- use the existing category tree as the business taxonomy
- add a technical mapping layer on top of it
- do not force every category to become a new technical template
- many categories should share the same template with different defaults

### Wheels

- `Componentes / Ruedas / Mazas / Maza` -> family `hub`, template `hub_generic`
- `Componentes / Ruedas / Mazas / Ejes` -> family `hub_axle`, template `hub_axle`
- `Componentes / Ruedas / Mazas / Ejes / Conos` -> family `hub_small_part`, template `hub_cone`
- `Componentes / Ruedas / Mazas / Ejes / Contratuerca` -> family `hub_small_part`, template `hub_locknut`
- `Componentes / Ruedas / Llantas` -> family `rim`, template `rim`
- `Componentes / Ruedas / Rayos` -> family `spoke`, template `spoke`
- `Componentes / Ruedas / Agujas` -> family `spoke`, template `spoke`
- `Componentes / Ruedas / Niples` -> family `nipple`, template `nipple`
- `Componentes / Ruedas / Cámaras` -> family `tube`, template `tube`
- `Componentes / Ruedas / Cámaras Anti-Pinchazo` -> family `tube`, template `tube_anti_pinchazo`
- `Componentes / Ruedas / Cubre Cámara` -> family `rim_strip`, template `rim_strip`
- `Componentes / Ruedas / Neumáticos` -> family `tire`, template `tire`
- `Componentes / Ruedas / Rodamientos` -> family `bearing`, template `bearing`
- `Componentes / Ruedas / Tubeless / Líquido Tubeless` -> family `tubeless_consumable`, template `tubeless_sealant`
- `Componentes / Ruedas / Tubeless / Válvula Tubeless` -> family `tubeless_valve`, template `tubeless_valve`
- `Componentes / Ruedas / Tubeless / O'rings` -> family `small_part`, template `o_ring`

### Brakes

- `Componentes / Frenos / Pastillas` -> family `brake_pad`, template `brake_pad`
- `Componentes / Frenos / Rotores` -> family `rotor`, template `rotor`
- `Componentes / Frenos / Rotor BMX` -> family `gyro_rotor`, template `bmx_rotor`
- `Componentes / Frenos / Calipers` -> family `brake_caliper`, template `brake_caliper`
- `Componentes / Frenos / Manillas` -> family `brake_lever`, template `brake_lever`
- `Componentes / Frenos / Adaptadores` -> family `brake_adapter`, template `brake_adapter`
- `Componentes / Frenos / Regulador tensión frenos` -> family `brake_small_part`, template `barrel_adjuster`
- `Componentes / Frenos / Frenos Hidráulicos / Frenos hidráulicos completos` -> family `complete_brake`, template `hydraulic_disc_brake`
- `Componentes / Frenos / Frenos Hidráulicos / Fittings Hidráulicos` -> family `hydraulic_fitting`, template `hydraulic_fitting`
- `Componentes / Frenos / V-Brake / Herraduras` -> family `rim_brake`, template `v_brake_arm`
- `Componentes / Frenos / V-Brake / Gomas V-Brake` -> family `rim_brake_pad`, template `rim_brake_pad`
- `Componentes / Frenos / V-Brake / Noodles` -> family `brake_small_part`, template `brake_noodle`

### Drivetrain

- `Componentes / Cambios / Desviadores / Desviador Trasero` -> family `rear_derailleur`, template `rear_derailleur`
- `Componentes / Cambios / Desviadores / Desviadores delanteros` -> family `front_derailleur`, template `front_derailleur`
- `Componentes / Cambios / Shifters` -> family `shifter`, template `shifter`
- `Componentes / Cambios / Roldanas` -> family `pulley`, template `derailleur_pulley`
- `Componentes / Cambios / Postiza` -> family `hanger`, template `hanger`
- `Componentes / Cambios / Regulador tensión` -> family `small_part`, template `barrel_adjuster`
- `Componentes / Transmisión / Cadenas` -> family `chain`, template `chain`
- `Componentes / Transmisión / Cadenas / Guias de cadena` -> family `chain_guide`, template `chain_guide`
- `Componentes / Transmisión / Piñones / Cassette` -> family `cassette`, template `cassette`
- `Componentes / Transmisión / Piñones / Freewheel` -> family `freewheel`, template `freewheel`
- `Componentes / Transmisión / Piñones / Espaciadores de Cassette` -> family `cassette_small_part`, template `cassette_spacer`
- `Componentes / Transmisión / Volantes / Volante` -> family `crankset`, template `crankset`
- `Componentes / Transmisión / Volantes / Biela Americana` -> family `crank_arm`, template `crank_arm`
- `Componentes / Transmisión / Volantes / Biela Izquierda` -> family `crank_arm`, template `crank_arm_left`
- `Componentes / Transmisión / Volantes / Catalina` -> family `chainring`, template `chainring`
- `Componentes / Transmisión / Volantes / Coronas` -> family `chainring`, template `chainring`

### Steering and cockpit

- `Componentes / Dirección / Horquillas` -> family `fork`, template `fork`
- `Componentes / Dirección / Juego de dirección` -> family `headset`, template `headset`
- `Componentes / Dirección / Rodamientos` -> family `bearing`, template `bearing`
- `Componentes / Dirección / Manubrios` -> family `handlebar`, template `handlebar`
- `Componentes / Dirección / Tee` -> family `stem`, template `stem`
- `Componentes / Dirección / Espaciadores` -> family `headset_small_part`, template `spacer`
- `Componentes / Dirección / Araña` -> family `headset_small_part`, template `star_nut`

### Cables and maintenance products

- `Componentes / Fundas y piolas / Cambios` -> family `cable_housing`, template `shift_cable_or_housing`
- `Componentes / Fundas y piolas / Frenos` -> family `cable_housing`, template `brake_cable_or_housing`
- `Mantenimiento / Líquido Frenos` -> family `brake_fluid`, template `brake_fluid`
- `Mantenimiento / Lubricantes` -> family `lubricant`, template `lubricant`
- `Mantenimiento / Grasa` -> family `grease`, template `grease`
- `Mantenimiento / Desengrasantes` -> family `cleaner`, template `degreaser`
- `Mantenimiento / Parches` -> family `repair_kit`, template `patch_kit`

### Categories that should remain commercial, not technical drivers

- `Accesorios`
- `Viñabike`
- `Otros`
- merchandising and apparel branches

These categories can still exist, but ficha técnica should stay light or generic for them.

## First-Wave Technical Templates and Fields

### `hub_generic`

Core fields:

- hub position
- wheel size compatibility
- OLD mm
- axle type
- axle diameter mm
- brake interface
- spoke hole count
- bearing system
- hub shell material

Advanced fields:

- left flange diameter mm
- right flange diameter mm
- left flange to center mm
- right flange to center mm
- PCD notes
- end cap standard

Conditional fields:

- if rear hub: freehub body, cassette compatibility, engagement notes
- if front hub: symmetry flag, dynamo flag

### `hub_axle`

- axle type
- axle diameter
- overall length
- usable length
- threading
- cone compatibility
- locknut compatibility

### `rim`

- wheel size
- ETRTO
- ERD mm
- spoke hole count
- inner width mm
- outer width mm
- rim depth mm
- material
- tubeless ready
- brake type

### `spoke`

- spoke type
- length mm
- diameter or gauge
- material
- butted type
- thread standard
- color

### `nipple`

- nipple type
- length mm
- material
- color
- spoke compatibility

### `tire`

- wheel size
- ETRTO
- width mm
- width inches
- bead type (`wire`, `kevlar`)
- tubeless ready
- tube type compatibility
- casing TPI
- compound
- recommended pressure range
- intended surface
- directionality

### `tube`

- wheel size range
- tire width range
- valve type
- valve length
- anti-pinchazo flag
- material

### `tubeless_valve`

- valve type
- valve length
- rim compatibility
- includes core remover

### `tubeless_sealant`

- volume ml
- latex based flag
- temperature suitability
- service interval suggestion

### `rotor`

- diameter mm
- mount type (`6bolt`, `centerlock`)
- thickness mm
- material
- floating flag
- pad compatibility notes

### `brake_pad`

- pad shape code
- brake family compatibility
- compound
- spring included
- backing plate type
- finned flag

### `brake_caliper`

- brake system
- hydraulic or mechanical
- mount standard
- piston count
- hose interface
- pad shape code
- front/rear compatibility

### `hydraulic_disc_brake`

- brake system
- front or rear or both
- fluid family (`mineral`, `dot`)
- hose length
- mount standard
- piston count
- brake pad shape
- rotor compatibility range

### `rear_derailleur`

- speed compatibility
- cage length
- max cassette tooth
- drivetrain family
- clutch flag
- mount type

### `front_derailleur`

- speed compatibility
- pull type
- mount type
- top swing or down swing
- max chainring range

### `shifter`

- speed compatibility
- left or right
- actuation family
- clamp compatibility
- brake integration flag

### `chain`

- speed compatibility
- length links
- e-bike rated flag
- chain treatment
- quick link included

### `cassette`

- speed compatibility
- tooth range
- freehub compatibility
- material notes
- intended use

### `freewheel`

- speed compatibility
- thread standard
- tooth range

### `chainring`

- tooth count
- BCD
- offset
- chain compatibility
- narrow-wide flag
- mount standard

### `crankset`

- crank length
- chainring setup
- spindle standard
- BB compatibility
- intended drivetrain

### `fork`

- rigid or suspension
- wheel size compatibility
- travel mm
- axle standard
- brake mount
- steerer type
- steerer length
- offset

### `headset`

- headset standard
- upper bearing spec
- lower bearing spec
- integrated or external
- crown race compatibility

### `handlebar`

- handlebar type
- clamp diameter
- width
- rise
- backsweep
- upsweep
- material

### `stem`

- clamp diameter
- steerer diameter
- length
- rise
- material

## Live Service Family and Profile Mapping Draft

### Mapping strategy

- keep current service products as billable identities
- add a service-family layer for reporting and organization
- add a service-profile layer for guided behavior
- not every service needs a deep wizard; some can stay simple package services

### Brake services

- `Regulación de frenos` -> profile `brake_adjustment`
- `Mantención de Freno` -> profile `brake_service_general`
- `Mantención Caliper de Freno` -> profile `caliper_service`
- `Purgado de Freno Hidráulicos` -> profile `hydraulic_brake_bleed`
- `Sangrado de Freno Hidráulicos` -> profile `hydraulic_brake_bleed`
- `Centrado Rotor de Freno` -> profile `rotor_truing`
- `Reemplazo de fundas y piolas + Regulación de frenos` -> profile `brake_cable_replacement_and_adjustment`
- `Limpieza y Elongación de Pistones` -> profile `piston_clean_and_reset`

### Wheel and hub services

- `Centrado de rueda (C/U)` -> profile `wheel_truing`
- `Centrado Express` -> profile `wheel_truing_quick`
- `Enrayado + Centrado` -> profile `wheel_build_and_true`
- `Cambio de Maza` -> profile `hub_replacement`
- `Servicio de Mazas (C/U)` -> profile `hub_service`
- `Mantención Maza` -> profile `hub_service`
- `Ajuste Maza` -> profile `hub_adjustment`
- `Cambio de cámara (no incluye cámara)` -> profile `tube_replacement`
- `Instalación de cámara` -> profile `tube_install`
- `Inflado de Rueda` -> profile `tire_inflation`
- `Presión de neumáticos` -> profile `tire_pressure_adjustment`
- `Recarga Tubeless` -> profile `tubeless_refill`
- `Tubeless Viñabike` -> profile `tubeless_conversion`
- `Tubeless Bettabikes` -> profile `tubeless_conversion`

### Drivetrain services

- `Regulación de Cambios` -> profile `drivetrain_adjustment`
- `Mantención de Cambio` -> profile `derailleur_service`
- `Reemplazo de fundas y piolas + regulación de cambios` -> profile `shift_cable_replacement_and_adjustment`
- `Mantención De Sistema De Transmisión` -> profile `drivetrain_service`
- `Limpieza sistema transmisión` -> profile `drivetrain_cleaning`
- `Limpieza/Cepillado de Cadena` -> profile `chain_cleaning`
- `Reparación de cadena` -> profile `chain_repair`

### Steering and cockpit services

- `Ajuste de dirección` -> profile `headset_adjustment`
- `Mantención De Dirección` -> profile `headset_service`
- `Instalación Juego de Dirección` -> profile `headset_install`
- `Cambio Cinta de Manillar` -> profile `bar_tape_replacement`

### Suspension and motor services

- `Mantención de Suspensión Delantera` -> profile `fork_service`
- `Ajuste de motor` -> profile `motor_adjustment`
- `Mantención De Motor` -> profile `motor_service`
- `Limpieza y engrase de caja de motor` -> profile `motor_case_service`

### General maintenance and package services

- `Mantención Básica` -> profile `maintenance_package_basic`
- `Mantención Semi` -> profile `maintenance_package_semi`
- `Mantención Full Bicicleta Rígida Frenos Mecánicos` -> profile `maintenance_package_full_mechanical_rigid`
- `Mecánica Básica` -> profile `general_mechanics_basic`
- `Mecánica Media` -> profile `general_mechanics_medium`
- `Mecánica Mayor` -> profile `general_mechanics_major`
- `Ajustes Generales` -> profile `general_adjustments`
- `Regulación General` -> profile `general_adjustments`
- `Limpieza General` -> profile `general_cleaning`
- `Limpieza Profunda de Bicicleta` -> profile `deep_cleaning`
- `Lavado de bicicleta + Lubricación sistema de transmisión` -> profile `wash_and_drivetrain_lube`
- `Lubricación` -> profile `basic_lubrication`
- `Armado de Bicicleta` -> profile `bike_assembly`
- `Arriendo de Bicicleta` -> profile `bike_rental`

### Miscellaneous or low-priority services

- `Instalación de piezas/partes` -> temporary profile `generic_install`
- `Instalación rueda scooter` -> temporary profile `non_bike_install`
- `Rectificación de Postiza` -> profile `hanger_alignment_or_repair`
- `Pendiente` -> should be cleaned or deactivated before guided rollout

## Detailed Guided Service Flows

### `brake_adjustment`

Minimum questions:

- brake type
- front or rear
- symptom (`roza`, `frena poco`, `maneta blanda`, `desalineado`)

Advanced questions:

- hydraulic or mechanical
- rotor size
- pad wear state
- cable or hose state
- include part replacement

Suggested parts:

- brake pads
- brake cable
- housing
- hose fittings
- brake fluid
- adapter

Generated summary example:

- customer: `Regulación de freno hidráulico delantero`
- mechanic: `Freno delantero hidráulico, revisar centrado de cáliper, desgaste de pastillas y posible contaminación del rotor`

### `hydraulic_brake_bleed`

Minimum questions:

- front or rear
- fluid family
- symptom severity

Advanced questions:

- hose condition
- fitting condition
- pad contamination

Suggested parts:

- mineral oil or DOT fluid
- olive and barb
- hose kit
- pads if contaminated

### `wheel_truing`

Minimum questions:

- front or rear
- wheel size
- severity (`leve`, `media`, `alta`)

Advanced questions:

- spoke replacement needed
- nipple condition
- hub play present
- rim damage present

Suggested parts:

- spokes
- nipples
- rim tape

Generated summary example:

- customer: `Centrado de rueda trasera 29`
- mechanic: `Rueda trasera 29 con desvío lateral medio, revisar tensión lado transmisión y estado de niple`

### `wheel_build_and_true`

Minimum questions:

- front or rear
- wheel size
- hole count
- brake type

Advanced questions:

- hub selected
- rim selected
- spoke model selected
- build pattern

Suggested parts:

- hub
- rim
- spokes
- nipples

### `hub_service`

Minimum questions:

- front or rear
- axle type
- symptom (`juego`, `ruido`, `dureza`, `mantención preventiva`)

Advanced questions:

- cone system or bearing cartridge
- freehub service needed
- bearing replacement needed

Suggested parts:

- bearings
- cones
- locknuts
- axle
- grease

### `tube_replacement`

Minimum questions:

- front or rear
- wheel size
- valve type

Advanced questions:

- tire condition
- rim tape condition
- puncture cause

Suggested parts:

- tube
- rim strip
- tire if damaged

### `tubeless_conversion`

Minimum questions:

- front or rear or both
- wheel size
- tire tubeless-ready yes or no

Advanced questions:

- valve length
- sealant volume
- rim tape width

Suggested parts:

- tubeless valve
- sealant
- rim tape
- tire if current one is incompatible

### `drivetrain_adjustment`

Minimum questions:

- transmission type
- speed count
- symptom (`salta`, `no sube`, `no baja`, `ruido`)

Advanced questions:

- hanger alignment suspected
- cable condition
- cassette wear
- chain wear

Suggested parts:

- cable
- housing
- hanger
- chain
- cassette

### `chain_repair`

Minimum questions:

- broken link or stiff link
- speed count

Advanced questions:

- chain wear state
- cassette condition

Suggested parts:

- quick link
- full chain replacement

### `headset_service`

Minimum questions:

- symptom (`juego`, `dureza`, `ruido`, `mantención`)

Advanced questions:

- bearing replacement needed
- crown race condition

Suggested parts:

- bearings
- spacers
- star nut
- grease

## Job and Invoice Line Model Evolution

Current line data is not enough. The operational line must support:

- `item_type` (`product`, `service`, `adhoc`)
- `service_profile_id`
- `target_family`
- `target_position`
- `context_answers_json`
- `customer_summary`
- `mechanic_summary`
- `print_notes`
- `is_customer_visible`
- `linked_parent_item_id`
- `display_group_key`

This can live either directly on richer line records or as related context tables, but the document layer must be able to reconstruct the service flow cleanly.

## Future Category and Service Creation Rules

### New categories

When a new category is created, the system should allow or require mapping it to:

- technical family
- technical template
- optional default discipline tags

Decision rule:

1. if the category is only a commercial subdivision of an existing technical domain, map it to an existing template
2. if it is a technical variation of an existing domain, clone and extend an existing template
3. only create a brand new technical template when the mechanical domain is genuinely new

Fallback:

- allow creation
- mark as `technical mapping pending`
- ficha técnica falls back to a generic template with warning state

### New services

When a new service is created, the system should allow or require mapping it to:

- service family
- service profile
- applicable target family
- optional guided questions
- optional suggested parts rules
- optional mechanic task templates

Decision rule:

1. if the service is only a pricing or naming variation of an existing workflow, map it to an existing service profile
2. if it is a variation with slightly different questions or part suggestions, clone and extend an existing profile
3. only create a brand new service profile when the workflow is genuinely new

Fallback:

- allow creation
- mark as `guided profile pending`
- service can still be billed as a plain service line
- advanced workflow remains disabled until a profile is assigned

### Governance

The implementation should include three maintenance layers:

1. category tree management
2. technical template management
3. service profile management

### Versioning rule

Do not mutate technical templates or service profiles recklessly once they are in use.

Preferred strategy:

- clone
- version
- migrate deliberately

This protects historical products, jobs, invoices, and printed documents from accidental behavior changes.

## Session Progress Log

### Session: 2026-03-19 — Service Wizard First Pass (Milestone 4 partial)

#### What was built

**Database: Service profile tables deployed**

All three core service-profile tables are live in Supabase and functional:
- `service_profiles` — system-level profiles (`tenant_id = NULL`)
- `service_profile_questions` — questions per profile
- `service_product_profile_mappings` — links tenant products to system profiles

Migration file: `supabase/migrations/20260319_service_wizard_profiles.sql` (334 lines, fully idempotent — safe to re-run).

**8 system service profiles seeded:**

| key | name | family |
|-----|------|--------|
| `hydraulic_brake_bleed` | Sangrado de Freno Hidráulico | brakes |
| `chain_lube` | Limpieza y Lubricación de Cadena | drivetrain |
| `derailleur_adjustment` | Ajuste de Cambios | drivetrain |
| `wheel_truing` | Centrado de Rueda | wheels |
| `piston_clean_and_reset` | Limpieza y Elongación de Pistones | brakes |
| `brake_adjustment` | Regulación de Freno | brakes |
| `brake_service_general` | Mantención de Freno | brakes |
| `rotor_truing` | Centrado de Rotor | brakes |

**9 Viñabike brake service products mapped (live in DB):**

| SKU | Profile |
|-----|---------|
| NNV78 | piston_clean_and_reset |
| M003 | brake_adjustment |
| SKU-3DC8D9D7 | hydraulic_brake_bleed |
| NNV91 | brake_service_general |
| NNV88 | brake_service_general |
| M006 | brake_adjustment |
| NNV165 | hydraulic_brake_bleed |
| NNV38 | rotor_truing |
| M002 | brake_service_general |

**Flutter service wizard — working end-to-end:**

- `lib/modules/bikeshop/services/service_wizard_service.dart` — `ServiceWizardService`, models (`ServiceWizardProfile`, `ServiceProfileQuestion`, `ServiceQuestionOption`, `ServiceWizardResult`)
- `lib/modules/bikeshop/widgets/service_wizard_dialog.dart` — dialog UI with `single_select`, `multi_select`, `boolean`, `number`, `text` question renderers
- `lib/modules/bikeshop/pages/mechanic_job_form_page.dart` — already calls `showServiceWizardDialog` when a mapped service product is added to a job
- Dialog opens automatically when a mapped service is added to a job line

**Bug fixed: boolean questions (2026-03-19)**

Old behavior: the entire boolean question card turned blue/primary when tapped (one big `AnimatedContainer` was the tap target).

Fix: boolean questions now render as two pills (Sí / No) matching the `single_select` visual pattern. State starts as `null` (nothing selected) instead of defaulting to `false`.

---

#### What is still broken / needs work

**LOW — No summary template rendering**

`service_profiles.customer_summary_template` contains mustache-style templates like:
```
Sangrado {{which_wheel}}, fluido {{fluid_type}}
```
These are never used. `buildSummary` ignores them and just concatenates all answered questions.

Future improvement: when a `customerSummaryTemplate` is available, use it to build a shorter, more natural summary. Fall back to the full question concatenation only when no template is set.

---

#### What was fixed in the latest session

1. **Fixed `buildSummary` to resolve option values → labels:** The summary now correctly outputs human-readable labels and boolean Yes/No values instead of raw keys.
2. **Added pre-fill support to the wizard dialog:** Re-opening the wizard for an already configured service line now restores the previous answers.
3. **Improved service line card display (Contextual Sidebar):** Instead of cluttering the main part table with inline chips, the table row reverted to a clean `SmartProductField`. A new "Detalle de Servicio" panel was added to the right sidebar, which dynamically displays the configured answers of the *currently selected* service line with readable typography and an edit button.

---

#### Next actions for the next agent (priority order)

1. **Seed remaining service profiles** (non-brake domains) — see the Live Service Family and Profile Mapping Draft section below for the full target list. Brake domain is done. Next up: wheels, drivetrain, steering, general maintenance.

2. **Map remaining Viñabike service products** — only 9 brake products are mapped. The remaining ~49 unmapped service products need profiles created and mapped.

3. **Implement summary template rendering (Optional)** — utilize `customer_summary_template` if present to build shorter, more natural summaries rather than appending all variables.

---

## Delivery Backlog and Milestones

### Milestone 1: Domain foundation

Deliverables:

- `spec_definitions`
- `spec_templates`
- `spec_template_fields`
- `category_tech_mappings`
- admin UI for mapping categories to templates

Outcome:

- products can resolve which ficha técnica schema they should use

### Milestone 2: Product ficha técnica UI

Deliverables:

- `Ficha Tecnica` tab in product form
- dynamic field renderer
- completeness indicator
- technical summary card
- JSON snapshot sync to `products.specifications`

Outcome:

- users can maintain structured technical data without code changes

### Milestone 3: First-wave technical templates

Deliverables:

- hub templates
- tire templates
- rim templates
- brake pad and rotor templates
- drivetrain templates for chain, cassette, rear derailleur

Outcome:

- highest-value workshop parts become structurally searchable and compatible

### Milestone 4: Service profile engine

Deliverables:

- `service_profiles`
- `service_profile_questions`
- `service_profile_targets`
- `service_profile_part_rules`
- `service_profile_task_templates`
- mapping existing service products to profiles

Outcome:

- service lines gain guided behavior without replacing current billing flow

### Milestone 5: Guided job and invoice interaction

Deliverables:

- guided panel or wizard for service lines
- linked parts workflow
- front/rear and component-context support
- operational summary cards

Outcome:

- jobs and invoices become workshop-ready operational documents

### Milestone 6: Print and AI layers

Deliverables:

- customer summary renderer
- mechanic summary renderer
- compatibility suggestion layer
- AI assistant consumption of structured specs and service answers

Outcome:

- the same structured data powers human workflow, PDFs, and AI actions

## Rollout Plan

### Phase 1

- create the spec engine tables
- map current live categories to technical templates
- clean only obvious duplicate or low-value categories when necessary

### Phase 2

- add `Ficha Tecnica` tab to the product form
- implement dynamic technical fields for the first product families
- keep `products.specifications` synced as JSON summary

### Phase 3

- create the service profile engine
- cluster current services into service families
- connect guided questions to existing service products

### Phase 4

- enrich job and invoice line items with operational context
- support linked parts inside service flows
- add clean summary cards for operational readability

### Phase 5

- build printable customer and mechanic summaries
- add compatibility suggestions and AI assistant integration
- add admin flows for future category and service mapping

## Success Criteria

- products have category-specific technical schemas
- service selection asks the right questions automatically
- jobs and invoices become usable workshop documents
- linked parts can be added within service flows
- compatibility can be queried from structured data
- AI can reason on technical and service context reliably
- the interaction remains fast, readable, and simple for staff under daily shop pressure