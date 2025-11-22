# Smart Catalog & Compatibility System — AI Implementation Guide

## Purpose

This guide is for a GitHub Copilot agent to implement the full Smart Catalog & Compatibility System, fully wired to the existing `core_schema.sql` database. It includes dynamic product forms, advanced specs, the compatibility engine, and all necessary metadata for bicycle parts.

**Key Principles:**

* Reference `core_schema.sql` for tables, columns, and triggers.
* Metadata tables define discipline-specific fields and compatibility rules.
* The system must handle both modern and vintage bikes.
* Product advanced specs are dynamic, dependent on discipline (MTB, Road, Hybrid, BMX) and component type.

---

## 1. Architecture Overview

### 1.1 Bike Catalog

* Table: `bike_catalog` (from core schema)
* Stores: brand, model, year, discipline, frame specs (rear OLD, bottom bracket, headset type), max tire clearance
* Factory components reference products in `products` table
* Customer bikes copy catalog components but can have custom upgrades or replacements

### 1.2 Customer Bikes

* Table: `bikes` (existing)
* Column: `catalog_bike_id` references `bike_catalog`
* Table: `bike_instance_components`

  * `component_type`, `product_id`, `specs jsonb`, `is_original`, `installed_at`, `removed_at`
* `live_specs jsonb` for overrides (upgrades, drivetrain conversions)

### 1.3 Products & Categories

* Table: `products`
* Column: `specifications jsonb` (atomic component data)
* `category_id` → `product_categories`
* Generated columns for fast queries: `speeds`, `freehub_standard`, `hub_spacing_mm`, `holes`, `axle_type`, `tire_bsd_diameter_mm`, `tire_width_mm`, `max_teeth`
* Product categories contain `spec_schema jsonb` for dynamic forms

### 1.4 Compatibility Engine

* Stateless service
* Inputs: `bike_instance_id` or `catalog_bike_id` + `component_type`
* Steps:

  1. Load frame specs + live overrides + installed components
  2. Quick SQL filter using generated columns
  3. Rule evaluation via `discipline_component_rules` and `conversion_rules`
  4. Score with `compatibility_weights`
  5. Output compatible products, warnings, adapters, and upgrade instructions

### 1.5 UI Overview

* Bike diagram view: interactive, clickable parts
* Part card: shows product image, name, specs, stock, compatibility button
* List view: table format
* Exploded view: optional for drivetrain, brakes, wheels
* Compatibility modal: shows Mode 1/2/3 with warnings and adapters

---

## 2. Metadata Examples

### 2.1 Bike Disciplines

```json
[
  {"token":"mtb","display_name":"Mountain Bike"},
  {"token":"road","display_name":"Road Bike"},
  {"token":"gravel","display_name":"Gravel/Adventure"},
  {"token":"bmx","display_name":"BMX"},
  {"token":"track","display_name":"Track"},
  {"token":"commuter","display_name":"Commuter/Hybrid"},
  {"token":"ebike","display_name":"E-Bike"},
  {"token":"vintage","display_name":"Vintage"}
]
```

### 2.2 Discipline Component Rules (examples)

```json
{
  "discipline_token": "mtb",
  "component_type": "rear_hub",
  "fields": ["position","holes","hub_spacing_mm","axle_type","freehub_standard","disc_mount","tubeless_ready"],
  "allowed_values": {
    "hub_spacing_mm": [135,142,148,150,157],
    "axle_type": ["QR","bolt","thru_12","thru_15","thru_20"],
    "disc_mount": ["centerlock","6-bolt","none"],
    "freehub_standard": ["shimano_hg","sram_xd","microspline","campagnolo","threaded_freewheel"]
  }
}
```

### 2.3 Product Categories Spec Schema (rear_hub)

```json
{
  "component_type":"rear_hub",
  "spec_schema":{
    "fields":[
      {"name":"position","type":"select","label":"Position","options":["rear"],"required":true},
      {"name":"holes","type":"select","label":"Spoke Holes","options":[20,24,28,32,36,40],"required":true},
      {"name":"hub_spacing_mm","type":"select","label":"Hub Spacing (O.L.D.)","options":[120,126,130,135,142,148,150,157],"required":true},
      {"name":"axle_type","type":"select","label":"Axle Type","options":["QR","bolt","thru_9","thru_12","thru_15","thru_20","thru_24"],"required":true},
      {"name":"freehub_standard","type":"select","label":"Freehub Standard","options":["shimano_hg","sram_xd","microspline","campagnolo","threaded_freewheel"],"required":true},
      {"name":"disc_mount","type":"select","label":"Disc Mount","options":["centerlock","6-bolt","none"],"required":false},
      {"name":"tubeless_ready","type":"boolean","label":"Tubeless Ready"}
    ]
  },
  "matching_fields":["holes","hub_spacing_mm","axle_type","freehub_standard","disc_mount"]
}
```

### 2.4 Other Component Examples

* **Cassette**: `speeds`, `range`, `freehub_standard`, `max_teeth`, `chain_compat`
* **Rear Derailleur**: `speeds`, `max_teeth`, `mount_type`, `cage_length`, `clutch`
* **Chainring / Crankset**: `teeth_count`, `BCD`, `spindle_type`, `material`
* **Tires**: `wheel_bsd_diameter_mm`, `width_mm`, `tubeless_ready`, `pattern`
* **Brakes / Rotors**: `type`, `mount_type`, `rotor_size_mm`, `hydraulic_or_mechanical`
* **Headset**: `type`, `bearing_size`, `tapered`, `integrated_or_threaded`
* **Seatpost**: `diameter_mm`, `length_mm`, `material`
* **Fork**: `travel_mm`, `axle_type`, `steerer_diameter`, `disc_mount`
* **Wheelset**: `rim_inner_mm`, `rim_outer_mm`, `hub_spacing_front`, `hub_spacing_rear`, `hole_count`
* **Shifters**: `speeds`, `mount_type`, `brand_compatibility`
* **Pedals**: `axle_type`, `clipless_or_platform`, `thread_size`

> These fields should drive the **advanced specs tab** dynamically.

---

## 3. Compatibility Engine Pseudocode

```
function findCompatibleParts(bikeInstance, componentType, mode='mode2'):
    bikeFrame = loadBikeCatalog(bikeInstance.catalog_bike_id)
    live = bikeInstance.live_specs
    discipline = bikeFrame.discipline
    rules = loadDisciplineComponentRules(discipline, componentType)

    candidates = queryProductsByCategory(componentType)
    candidates = filterByGeneratedColumns(candidates, live, rules.matching_fields)

    for candidate in candidates:
        score, warnings, adapters = evaluateCompatibility(candidate, bikeInstance, rules)
        classification = classifyByScore(score, mode)
        append results

    return sortAndPaginate(results)
```

---

## 4. UI & Flutter Notes

* `bike_diagram.dart` → interactive SVG bike diagram with clickable parts
* `advanced_specs_tab.dart` → builds dynamic form from `spec_schema`
* `compatibility_modal.dart` → displays results with Modes 1/2/3
* API endpoints:

  * `/compatibility/find`
  * `/products/{id}/specs`
* Flow: click part → open modal → show compatible replacements, warnings, adapters
* Support modern & vintage bikes, drivetrain upgrades, 1x conversions, etc.

---

## 5. Copilot Instructions

1. Reference `core_schema.sql` for all tables, columns, and triggers
2. Seed discipline/component metadata from JSON examples
3. Implement compatibility engine using pseudocode
4. Render advanced specs dynamically using `product_categories.spec_schema`
5. Integrate Flutter UI for diagram, advanced specs, and modal
6. Add logging, unit tests, and seed data
7. Maintain modular design; only modify existing tables/functions if strictly necessary
8. Ensure upgrade paths (speed changes, 1x conversions, hub adapters) are handled
9. Ensure support for vintage & modern bikes

---

**Reference schema file**: [core_schema.sql](file:///mnt/data/core_schema.sql)
