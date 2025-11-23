# Smart Catalog & Compatibility System — Full Implementation Spec (Unified File)

> **This is the complete, unified master document** requested.
> It includes: field dictionary, component schema, compatibility rules, discipline logic, BikeMatrix reference logic, your catalogue-as-template system, product specs, dynamic forms, UI/UX architecture, and integration instructions for your GitHub Copilot agent — **all in ONE file**.

---

## 0. Purpose of This Document

This `.md` serves as the **central blueprint** for building the Smart Catalog & Compatibility System inside your existing codebase (referencing `core_schema.sql`).

It includes:

* Full compatibility metadata dictionary
* Discipline → Component logic
* Component → Required spec fields
* Dynamic product advanced spec architecture
* Bike catalog with factory components
* Customer bikes with overrides & upgrades
* Compatibility rule engine (multi-mode)
* Diagram UI logic
* Integration instructions for GitHub Copilot agent

This is the **single file** Copilot will follow while referencing your real DB.

---

# 1. System Overview

The Smart Catalog System turns your ERP into a **bike encyclopedia + compatibility engine**.

Core components:

1. **Global Bike Catalog** (brand, model, year, full component list)
2. **Customer Bikes** (instances with upgrades & spec overrides)
3. **Product Catalog** (with dynamic advanced specs)
4. **Compatibility Engine**
5. **Dynamic Forms + UI** (discipline + component-based)
6. **Rule Engine** (frame rules, component rules, conversion rules)

---

# 2. Bike Catalog (Template-Based With Full Parts)

## 2.1 Catalog Entry Structure

A bike in the catalog contains:

* brand
* model
* year
* discipline (mtb / road / gravel / hybrid / bmx / vintage)
* frame geometry & standards
* **factory components list** (links to products OR embedded specs)

### 2.2 Fields Required For Bike Catalog

### Frame Specs

* rear_hub_spacing_mm (OLD)
* rear_axle_type
* front_hub_spacing_mm
* front_axle_type
* bb_type
* bb_width_mm
* bb_thread_pitch
* headset_standard
* headtube_type
* steerer_type
* front_rotor_max
* rear_rotor_max
* brake_mount_front
* brake_mount_rear
* wheel_size_front
* wheel_size_rear
* max_tire_width_mm
* seatpost_diameter_mm
* seatpost_type

### Factory Components

Each bike catalog entry references a list:

```
components: [
  { "type": "fork", "product_id": ... },
  { "type": "rear_derailleur", "specs": {...} },
  { "type": "cassette", "product_id": ... }
]
```

Customer bikes copy these into:

```
bike_instance_components
```

Where the mechanic can:

* replace
* upgrade
* override specs

---

# 3. Customer Bikes

## 3.1 Structure

Each customer bike:

* references catalog bike
* has local overrides (live specs)
* has installed & removed parts tracked historically

## 3.2 Why Local Overrides Are Needed

Because a customer might:

* upgrade from 3×9 → 1×12
* replace their fork
* install a wider cockpit
* replace wheels
* change BB and crank
* convert to tubeless

The compatibility engine must consider ALL of this.

---

# 4. Product Catalog With Dynamic Advanced Specs

## 4.1 How Dynamic Specs Work

Every product belongs to:

* discipline (optional)
* component_type (required)

Product category stores the `spec_schema` which drives the UI.

Example:

```
product_categories.spec_schema
```

When creating/editing product:

* User chooses discipline (mtb / road / etc)
* User chooses component_type (cassette, hub, tire, stem, etc)
* Advanced Specs Tab auto-populates with correct fields.

## 4.2 Example UI Flow

1. User selects **MTB**
2. User selects **rear derailleur**
3. System loads MTB derailleur spec schema
4. Fields appear:

   * speeds
   * max_teeth
   * cage_length
   * clutch
   * mount_type

---

# 5. The FULL FIELD DICTIONARY (Component Metadata Master List)

This is the **core** of the compatibility system.
It includes every field existing modern AND vintage bicycles may need.

## 5.1 Frame Metadata

* rear_hub_spacing_mm (120 / 126 / 130 / 135 / 142 / 148 / 150 / 157)
* front_hub_spacing_mm
* rear_axle_type (QR / bolt-on / thru-10 / thru-12 / thru-15)
* front_axle_type
* dropout_standard (UDH / standard hanger / direct mount / horizontal / BMX)
* brake_mount_front (post / flat / IS / none)
* brake_mount_rear
* frame_tire_max_width_mm
* frame_wheel_size
* bb_type (BSA / ITA / PF30 / BB86 / T47 / BMX)
* bb_width_mm
* bb_thread_pitch
* seatpost_diameter_mm
* seatpost_type (rigid / dropper)
* headset_standard (ZS44/ZS56, IS41, EC34, threaded 1 1/8, etc)
* headtube_length

## 5.2 Fork Metadata

* travel_mm
* offset_mm
* axle_type
* spacing_mm
* brake_mount
* steerer_type
* max_tire_width_mm

## 5.3 Wheel Metadata

* wheel_size
* rim_inner_width_mm
* rim_outer_width_mm
* tubeless_ready
* spoke_holes
* freehub_standard
* rotor_mount

## 5.4 Tire Metadata

**BSD Diameter** must be separated:

* bsd_diameter_mm (406, 507, 559, 584, 622, etc)
* width_mm (23–80)
* casing
* tubeless_ready

## 5.5 Hub Metadata

* position (front/rear)
* spoke_holes
* spacing_mm (OLD)
* axle_type
* freehub_standard
* disc_mount
* bearing_type

## 5.6 Drivetrain Metadata

### Cassette

* speeds
* range_min
* range_max
* freehub_standard

### Rear Derailleur

* speeds
* max_teeth
* cage_length
* clutch
* mount_type

### Chain

* speeds
* type (HG, HG+, Eagle, T-Type, road11s, etc)

### Crankset

* chainline_mm
* q_factor
* spindle_type
* chainring_mount (BCD, direct mount pattern)

### Chainrings

* teeth_count
* bcd
* offset
* wide_narrow

## 5.7 Cockpit

### Handlebar

* clamp_diameter_mm
* width_mm
* rise_mm

### Stem

* clamp_diameter_mm
* steerer
* length_mm
* angle_deg

### Seatpost

* diameter_mm
* length_mm
* type (dropper/rigid)

## 5.8 Brakes

* brake_type
* rotor_mount
* rotor_size_mm
* caliper_mount
* hose_type
* lever_pull_ratio

## 5.9 VHS Misc

* pedals: thread size (9/16, 1/2)
* tubes: bsd + width range + valve type
* saddle: rail type

---

# 6. Compatibility Engine (Multi-Mode)

Your system supports **3 modes**:

### Mode 1 — Strict (Factory)

* Only parts identical to factory specs compatible.

### Mode 2 — Realistic Shop Compatibility

* Matches parts based on:

  * frame specs
  * current upgrades
  * acceptable industry standards
  * adapters allowed

### Mode 3 — Upgrade Suggestions

* Suggests possible upgrades
* Offers required adapters
* Offers warnings
* Allows drivetrain conversions

---

# 7. Compatibility Rule Structure

## 7.1 How Rules Work

Each component type has a rule set:

```
compatibility_rules["rear_hub"] = {
  "compare": ["spacing_mm", "axle_type", "freehub_standard", "spoke_holes", "disc_mount"]
}
```

Each rule:

* is discipline-aware (MTB vs Road vs Vintage)
* supports adapters
* supports warnings

## 7.2 Example Rule — Cassette

```
IF bike.speeds == product.speeds
  AND bike.freehub_standard == product.freehub_standard
  AND product.max_teeth <= derailleur.max_teeth
THEN compatible
ELSE incompatible / partial
```

---

# 8. UI/UX Specification

## 8.1 Product Form — Advanced Specs Tab

Dynamic fields loaded from:

```
product_categories.spec_schema
```

## 8.2 Bike Diagram

Interactive SVG:

* click wheel → show wheel/hub/tire compatibility
* click cassette → show cassette options
* click derailleur → show compatible derailleurs

## 8.3 Compatibility Modal

Shows:

* compatible parts list
* partial compatibility (mode 3)
* required adapters
* warnings
* explanations

---

# 9. BikeMatrix Reverse Engineering (For Inspiration Only)

Included because you requested it.
This is NOT to be copied; only to learn patterns.

### What BikeMatrix Does:

* massive bike database (~150k entries)
* component matching by category
* supports EAN/UPCs
* strict component-field comparison
* adapter logic
* explanation engine

### What YOU do BETTER:

* dynamic product specs
* vintage support
* drivetrain upgrades
* mechanic workflows
* customer bike modifications
* service jobs

---

# 10. GitHub Copilot Agent Instructions

1. Read **core_schema.sql** fully before writing code.
2. Use THIS `.md` as the master blueprint.
3. Create metadata tables for disciplines, components, and spec schemas.
4. Do NOT modify existing tables UNLESS strictly necessary.
5. Create JSON schemas for product categories.
6. Implement dynamic advanced specs UI.
7. Implement compatibility engine in Dart.
8. Implement bike diagram UI using SVG → clickable hotspots.
9. Add adapters, warnings, multi-mode compatibility.
10. Ensure EVERY component field from the dictionary is wired.

---

# End of Unified Spec

This is the single file required to implement the entire Smart Catalog & Compatibility System.
