# Compatibility Engine Master Plan

_Last updated: 2025-11-23 (Comprehensive Audit & Expansion)_

This is the authoritative, end-to-end playbook for the Smart Catalog & Compatibility Engine. It aligns `.github/compatibilityEngine.md`, **`supabase/sql/core_schema_compat.sql`** (SQL source of truth), and the Flutter apps into one execution plan covering metadata, evaluation logic, workflow integrations, deployment, and QA. Treat this as the single source of truth for engineering, product, operations, and Copilot/Sonnet agents.

---

## ⚠️ CRITICAL: SQL Source of Truth

**ALL compatibility engine database changes MUST be made in `supabase/sql/core_schema_compat.sql`**

- ✅ **DO**: Edit `core_schema_compat.sql` → Deploy to staging (`kyvgmapifacpzuyreasy`)
- ❌ **DO NOT**: Touch `core_schema.sql` during compatibility engine development
- ✅ **WORKFLOW**: Develop in compat → Test on staging → Validate → Merge to production schema LATER (after full testing)

**Why this matters:**
- `core_schema.sql` = Production master (17,303 lines, live customer data)
- `core_schema_compat.sql` = Staging/development copy (18,702 lines, safe experimentation)
- Compatibility engine is being built on staging project first
- Only after complete validation will changes be promoted to production

**Every database section in this document references `core_schema_compat.sql` line numbers.**

---

## 1. Vision & Success Metrics

### 1.1 Vision Statement
Deliver a **BikeMatrix-grade compatibility brain** embedded directly into Vinabike ERP so every workflow (inventory, maintenance, sales, procurement, analytics) becomes compatibility-aware, explainable, and automated. This is not just a compatibility checker—it's an **intelligent business engine** that:

1. **Understands the full bike ecosystem** – modern, vintage, OEM, aftermarket, adapters, rare standards.
2. **Recommends parts, upgrades, jobs, and budgets** with complete traceability and financial transparency.
3. **Closes the loop** with inventory, purchasing, invoices, jobs, and analytics—enabling **full business workflow automation**.
4. **Generates revenue-optimized quotes** (Good/Better/Best tiers) based on customer bikes, inventory availability, profit margins, and budget constraints.
5. **Creates actionable purchase orders** when compatible parts are out of stock, linked back to customer jobs.
6. **Tracks compatibility decisions** in audit logs for continuous learning and mechanic training.

**Unique Differentiators vs BikeMatrix:**
- **ERP-native**: Compatibility directly wired into inventory, invoicing, POS, procurement—not a separate tool.
- **Budget-aware**: Generate quotes respecting customer budget limits with dynamic tier pricing.
- **Inventory-driven**: Automatically flag missing parts, create purchase lists, suggest supplier orders.
- **Multi-tenant SaaS**: Each bike shop gets isolated compatibility profiles, custom adapters, shop-specific rules.
- **Mechanic-centric UX**: Smart pegas (jobs) auto-generated from compatibility evaluations with reasoning visible to technicians.
- **Financial integration**: Every recommendation flows into invoices, payments, accounting, margin tracking.

### 1.2 Success Metrics
| Metric | Target | Measurement | Notes |
|--------|--------|-------------|-------|
| Compatibility accuracy | ≥95% vs expert verdict | QA suites + mechanic validation | Compare engine recommendations to expert mechanic decisions on test cases |
| Recommendation explainability | 100% include reasoning & adapter plan | Data from `compat_rule_audit_log` | Every "compatible" or "needs adapter" includes human-readable why |
| Smart pegas auto-generated | ≥70% of jobs originate via compatibility wizard | Adoption KPI | Track `mechanic_jobs.compatibility_session_id IS NOT NULL` |
| Quote acceptance uplift | +20% vs baseline | Sales conversion rate | Compare quote acceptance before/after compatibility engine |
| Inventory gap prediction | 90% flagged ≥7 days in advance | Procurement lead time | Parts needed for pending evaluations show in purchase list |
| Schema completeness | 100% of compatibility categories | Enforced by validation & imports | All products have required compatibility attributes for their component type |
| Average evaluation time | <2 seconds | Performance monitoring | Time from `compat_run_evaluation()` call to result |
| Adapter usage rate | 20-30% of recommendations | Telemetry dashboard | Track how often adapters enable compatibility (sweet spot: useful but not overused) |
| Revenue per recommendation | +15% vs manual quoting | Financial analytics | Track sale value of compatibility-generated quotes vs manual |

---

## 2. Current State Audit (2025-11-23)

### 2.1 Delivered ✅

**Database Schema (Source: `supabase/sql/core_schema_compat.sql` → Deployed to Staging: `kyvgmapifacpzuyreasy`):**
- ✅ **Global Component Library** (`compat_component_library`) – 30+ component types seeded with metadata JSON (wheel, frame, drivetrain, brake systems)
  - **Location:** `core_schema_compat.sql` lines 2190-2393
- ✅ **Category Mapping** (`product_categories.component_type_code`) – FK column allowing user to map categories to component types
  - **Location:** `core_schema_compat.sql` lines 2256-2261
- ✅ **View for Dropdowns** (`v_component_type_catalog`) – Pre-computed attribute counts for UI
  - **Location:** `core_schema_compat.sql` lines 2325-2341
- ✅ **RPC Function** (`get_category_with_component_metadata(uuid)`) – Efficient LEFT JOIN returning category + component metadata in one call
  - **Location:** `core_schema_compat.sql` lines 2343-2366
- ✅ **Auto-Seeding** (`seed_component_library()`) – Runs on tenant bootstrap, populates library
  - **Location:** `core_schema_compat.sql` lines 2368-2393
- ✅ **RLS Policies** – Global library readable by all authenticated users, categories filtered by tenant_id
  - **Location:** `core_schema_compat.sql` lines 2317-2323
- ✅ **Flexible Metadata Schema** – JSON with `attributes` array (key, label, type, enum_values, required, min, max, units)
  - **Location:** `core_schema_compat.sql` lines 2199-2208 (example metadata)

**Flutter Implementation:**
- ✅ **Category Model Updated** (`category_models.dart`) – Added `componentTypeCode` field with fromJson/toJson serialization
- ✅ **Category Form** (`category_form_page.dart`) – Component type dropdown with icons, attribute count badges, "Ninguno" option
  - Loads from `v_component_type_catalog` view
  - Saves `componentTypeCode` to database
  - Validates selection exists in loaded items
  - Proper mounted checks preventing rendering loops
- ✅ **Icon Mapping** – Helper function maps database icon names to Material Icons
- ✅ **Category Service** (`category_service.dart`) – Handles category CRUD, auto-injects tenant_id
- ⚠️ **Product Form** (`product_form_page.dart`) – Exists but NOT yet updated to use component type metadata (still uses OLD JSONB approach)

**Docs:**
- ✅ `.github/compatibilityEngine.md` – Conceptual spec with attribute examples
- ✅ `.github/compatibility_engine_master_plan.md` – **THIS DOCUMENT** (comprehensive blueprint)
- ✅ `supabase/sql/core_schema_compat.sql` – **SQL SOURCE OF TRUTH** (staging schema, 18,702 lines)
- ⚠️ `supabase/sql/core_schema.sql` – **DO NOT EDIT** (production schema, 17,303 lines, will be updated AFTER staging validation)

### 2.2 In Progress ⏳

**Product Form Dynamic Fields:**
- Category form complete, but product form needs to:
  1. Check if selected category has `componentTypeCode`
  2. Call `get_category_with_component_metadata(category_id)` RPC
  3. Parse returned `component_metadata.attributes` JSON
  4. Build dynamic form fields (enum→dropdown, number→TextField, text→TextField, boolean→Switch)
  5. Store filled values in `products.compatibility_attributes` JSONB column

**Missing Database Elements (to be added to `core_schema_compat.sql`):**
- `products.compatibility_attributes` JSONB column (for storing filled attribute values)
  - **Action:** Add `ALTER TABLE products ADD COLUMN IF NOT EXISTS compatibility_attributes JSONB;` to `core_schema_compat.sql`
- Validation trigger ensuring required compatibility attributes are present
  - **Action:** Create `validate_product_compatibility_attributes()` trigger in `core_schema_compat.sql`
- Search/filter functions for compatibility queries (e.g., "find all hubs with spoke_holes=32")
  - **Action:** Create `search_products_by_compatibility(jsonb)` RPC in `core_schema_compat.sql`

### 2.3 Remaining (Not Started) ❌

**Metadata Expansion (all in `core_schema_compat.sql`):**
- Full attribute dictionary for ALL component types (currently only ~30% complete)
  - **Action:** Update `seed_component_library()` function with complete metadata for 25 component types
- Drivetrain system complete taxonomy (crankset, cassette, chain, derailleurs, etc.)
  - **Action:** Add to `seed_component_library()` lines 2368-2393
- Cockpit system (handlebars, stems, grips)
  - **Action:** Add to `seed_component_library()`
- Brake system complete (calipers, rotors, adapters, hoses)
  - **Action:** Add to `seed_component_library()`
- Frame geometry attributes (reach, stack, bb_drop, chainstay_length)
  - **Action:** Add to `seed_component_library()` under `frame` component type
- Discipline-specific rules graphs
  - **Action:** Create `compat_discipline_rules` table in `core_schema_compat.sql`
- Conversion/adapter catalog
  - **Action:** Create `compat_adapters` table in `core_schema_compat.sql`

**Evaluation Engine (all in `core_schema_compat.sql`):**
- Core RPC functions: `compat_start_session()`, `compat_run_evaluation()`, `compat_generate_recommendation()`
  - **Action:** Add functions after line 2393 in `core_schema_compat.sql`
- Scoring algorithm (Mode 1/2/3 evaluation strategies)
  - **Action:** Implement in `compat_run_evaluation()` function
- Adapter planner logic
  - **Action:** Create `compat_find_adapters()` helper function
- Budget constraint handling
  - **Action:** Implement in `compat_generate_recommendation()` function
- Multi-component evaluations (wheel build: hubs+rims+spokes together)
  - **Action:** Create `compat_evaluate_wheel_build()` function

**Database Tables (all in `core_schema_compat.sql`):**
- `compat_sessions` – Track evaluation sessions
- `compat_evaluations` – Store evaluation results
- `compat_evaluation_items` – Individual product scores per evaluation
- `compat_rule_audit_log` – Log every compatibility rule decision
- `bike_catalog` – Template bikes (brand, model, year, specs)
- `bike_instances` – Customer bikes (links to catalog + overrides)
- `bike_instance_components` – Installed components per customer bike

**Workflow Integrations (Flutter + Database):**
- Wheel builder workspace UI (Flutter)
- Smart pegas wizard (Flutter + `core_schema_compat.sql` RPC integration)
- Quote/budget builder with tiered recommendations (Flutter)
- Inventory demand aggregation (RPC in `core_schema_compat.sql`)
- Purchase list auto-generation (trigger in `core_schema_compat.sql`)
- Customer bike profile management (Flutter + `bike_instances` table)

**Telemetry & Governance (in `core_schema_compat.sql`):**
- `compat_rule_audit_log` table + population
- Analytics dashboards (queries/views in `core_schema_compat.sql`)
- Validation scripts (PL/pgSQL functions)
- QA test harnesses (Flutter integration tests)
- Import enforcement (trigger functions in `core_schema_compat.sql`)

---

## 3. Architecture Blueprint

### 3.1 Layered Model
1. **Metadata/Taxonomy Layer** – `core_schema_compat.sql` tables, seeds, discipline graphs, adapters
   - Global component library (no tenant_id, shared catalog) – Lines 2190-2256
   - Per-tenant category mappings (user-configured)
   - Attribute definitions with validation rules
   - Conversion rules and adapter kits

2. **Evaluation Engine Layer** – PL/pgSQL + RPC orchestrations
   - Session management (track evaluations per customer/bike/job)
   - Scoring algorithms (Mode 1/2/3 strategies)
   - Adapter planning (when direct match fails, find conversion path)
   - Budget optimization (tier generation respecting financial constraints)
   - Multi-component orchestration (wheel build, drivetrain conversion)

3. **Application Services Layer** – Flutter/Dart business logic
   - `CompatibilityService` – Orchestrates RPC calls, caching, error handling
   - `SpecSchemaProvider` – Fetches component schemas for dynamic forms
   - `AdapterPlanner` – Formats adapter JSON into human-readable steps
   - `CompatibilitySessionStore` – Local state management
   - `BudgetOptimizer` – Client-side budget slider logic

4. **Workflow Integration Layer** – Connects compatibility to business processes
   - Wheel Builder Workspace (dedicated UI module)
   - Smart Pegas Wizard (mechanic job generation)
   - Quote/Budget Builder (Good/Better/Best tiers)
   - Inventory Demand Aggregator (procurement trigger)
   - Customer Bike Profiles (compatibility baselines)
   - Analytics Dashboards (telemetry visualization)

5. **Telemetry & Governance Layer** – Quality assurance and monitoring
   - Audit logs (every rule decision persisted)
   - Validation scripts (nightly completeness checks)
   - QA test harnesses (golden datasets)
   - Performance monitoring (evaluation timing, RPC latency)
   - Revenue tracking (margin per recommendation mode)

### 3.2 Data Flow

**Complete End-to-End Flow:**

```
1. PRODUCT METADATA CAPTURE
   ↓
   User maps category "Cuadros" → component type "frame" (via category form dropdown)
   ↓
   Product form detects category has component_type_code
   ↓
   Calls get_category_with_component_metadata(category_id) RPC
   ↓
   Renders 8 dynamic fields: wheel_size, tire_clearance, seatpost_diameter, headset_standard, bb_type, bb_shell_width, rear_spacing, chainline
   ↓
   User fills fields → saves to products.compatibility_attributes JSONB
   ↓

2. CUSTOMER JOB INTAKE
   ↓
   Customer brings bike (either in bike_catalog or bike_instance_components)
   ↓
   Mechanic opens Smart Pega Wizard → selects bike + service template (e.g., "Wheel Rebuild")
   ↓
   Wizard calls compat_start_session(tenant_id, bike_id, context='wheel_rebuild')
   ↓
   Session ID returned, stored in mechanic_jobs.compatibility_session_id
   ↓

3. COMPATIBILITY EVALUATION
   ↓
   Wizard calls compat_run_evaluation(session_id, component_code='rear_hub', mode=2, budget=150000)
   ↓
   Engine loads bike specs (frame rear_spacing_mm=142, axle_type='thru_12x142', spoke_holes=32)
   ↓
   Queries products WHERE tenant_id=X AND component_type_code='rear_hub' AND stock_quantity>0
   ↓
   Scores each candidate:
     - spoke_holes match? +5.0
     - hub_spacing_mm match? +4.5
     - axle_type match? +4.0
   ↓
   Found: Hub A (perfect match, score 13.5), Hub B (needs adapter, score 9.0)
   ↓
   For Hub B, consults compat_conversion_rules:
     - "Boost 148→142" requires axle kit (SKU: AXLE-KIT-001, cost $15, labor 15min)
   ↓
   Persists results to compat_evaluations, compat_evaluation_items
   ↓
   Logs decision to compat_rule_audit_log (attribute comparison, adapter reasoning, warnings)
   ↓

4. RECOMMENDATION GENERATION
   ↓
   Wizard calls compat_generate_recommendation(evaluation_id, quote_mode='tiered', target_budget=150000)
   ↓
   Engine builds 3 tiers:
     - Good: Hub A ($120) + spokes ($30) + nipples ($10) + labor ($25) = $185 [within budget ✅]
     - Better: Hub B ($100) + adapter ($15) + spokes ($35) + nipples ($12) + labor ($40) = $202 [over budget ⚠️]
     - Best: Hub C ($180) + spokes ($45) + nipples ($15) + labor ($30) = $270 [premium option]
   ↓
   Returns JSON with part SKUs, quantities, prices, adapter steps, warnings, margin calculations
   ↓

5. OPERATIONAL ACTIONS
   ↓
   User selects "Good" tier → Wizard creates:
     - mechanic_jobs entry with job_number, customer, bike
     - job_tasks entries (labor line items with minutes)
     - job_items entries (parts: Hub A, spokes, nipples with product_id references)
     - Optional: sales_invoice (quote mode) or confirms job (work mode)
   ↓
   IF parts not in stock:
     - Creates smart_purchase_list entries referencing component_type_code + spec filters
     - Procurement dashboard shows: "Need Hub A (spoke_holes=32, spacing=142mm) x1 for Job #1234"
   ↓
   Job completes → invoice posted → accounting entries created → revenue tracked
   ↓

6. TELEMETRY FEEDBACK LOOP
   ↓
   Analytics dashboard aggregates:
     - Evaluation volume by component type
     - Success rate (perfect match vs needs adapter vs no match)
     - Adapter usage frequency (which conversions most common?)
     - Revenue per recommendation mode (Mode 2 → avg $250, Mode 3 → avg $420)
     - Top failure reasons ("missing freehub_standard attribute on 45% of hubs")
   ↓
   Alerts fire if:
     - >10% evaluations failing due to missing metadata → create tasks for data entry
     - Evaluation time >5 seconds → index tuning needed
     - Adapter usage >50% → may indicate poor product selection
```

### 3.3 Key Design Patterns

**Pattern 1: Global Catalog + Per-Tenant Mapping**
- Component library is global (shared definitions, no tenant_id)
- Category→component mapping is per-tenant (user configures)
- Benefits: Easy updates to component specs, tenant customization, no data duplication

**Pattern 2: Metadata-Driven UI**
- Product form fields generated from `component_metadata.attributes` JSON
- Adding new component type = just INSERT into `compat_component_library`
- No Flutter code changes needed for new attributes
- Schema versioning tracked in metadata

**Pattern 3: Session-Based Evaluations**
- All evaluations grouped under session (tracks customer, bike, budget, context)
- Enables multi-component evaluations (wheel: hub+rim+spoke together)
- Provides traceability (which job triggered this evaluation?)
- Supports re-evaluation (budget slider → re-run with new ceiling)

**Pattern 4: Adapter Cascades**
- When no direct match, engine consults conversion rules
- Adapter plan includes: required parts, labor minutes, warnings, cost impact
- Adapters can chain (e.g., QR→Thru-Axle→Boost requires 2 kits)
- Each step logged in audit trail

**Pattern 5: Budget-Aware Tiering**
- Recommendations always include 3 tiers (Good/Better/Best)
- "Good" respects budget ceiling, "Better" slight overage, "Best" premium option
- Each tier shows margin (cost vs sell price)
- If all options exceed budget, flag "needs increase" + show cheapest option

**Pattern 6: Inventory-Driven Recommendations**
- Evaluation prioritizes in-stock products (stock_quantity > 0)
- Out-of-stock products included but flagged "requires order"
- When selected, auto-creates purchase list entry
- Procurement dashboard aggregates demand across pending jobs

### 3.4 System Wiring & Data Relationships

**This section defines HOW all components connect through foreign keys, triggers, and shared attribute schemas.**

#### 3.4.1 Core Table Relationships

```
┌─────────────────────────────────────────────────────────────────┐
│                    METADATA LAYER (Global)                       │
├─────────────────────────────────────────────────────────────────┤
│  compat_component_library (no tenant_id)                        │
│  ├─ code (PK): "rear_hub", "cassette", "frame"                 │
│  ├─ display_name: "Rear Hub", "Cassette", "Frame"              │
│  ├─ metadata JSONB: {attributes: [...]} ← SHARED SCHEMA         │
│  └─ parent_code: "wheel_system", "drivetrain_system"           │
└─────────────────────────────────────────────────────────────────┘
                              ↓ FK: component_type_code
┌─────────────────────────────────────────────────────────────────┐
│                  CATALOG LAYER (Per-Tenant)                      │
├─────────────────────────────────────────────────────────────────┤
│  product_categories (tenant_id)                                 │
│  ├─ id (PK)                                                     │
│  ├─ name: "Cubos Traseros", "Cassettes", "Cuadros"            │
│  └─ component_type_code → compat_component_library.code        │
│                                                                  │
│  products (tenant_id)                                           │
│  ├─ id (PK)                                                     │
│  ├─ category_id → product_categories.id                        │
│  ├─ compatibility_attributes JSONB ← FILLED FROM SCHEMA         │
│  │    {                                                         │
│  │      "spoke_holes": 32,                                     │
│  │      "spacing_mm": 148,                                     │
│  │      "axle_type": "thru_12x148",                           │
│  │      "freehub_standard": "sram_xd"                         │
│  │    }                                                         │
│  └─ stock_quantity, price, cost                                │
└─────────────────────────────────────────────────────────────────┘
                              ↓ FK: catalog_bike_id
┌─────────────────────────────────────────────────────────────────┐
│                   BIKE CATALOG (Template Layer)                  │
├─────────────────────────────────────────────────────────────────┤
│  bike_catalog (tenant_id)                                       │
│  ├─ id (PK)                                                     │
│  ├─ brand, model, year, discipline                             │
│  ├─ frame_specs JSONB ← USES SAME ATTRIBUTES AS PRODUCTS       │
│  │    {                                                         │
│  │      "rear_hub_spacing_mm": 148,                           │
│  │      "rear_axle_type": "thru_12x148",                      │
│  │      "bb_type": "bsa_73",                                   │
│  │      "wheel_size": "29er"                                   │
│  │    }                                                         │
│  ├─ factory_components JSONB ← ARRAY OF COMPONENTS             │
│  │    [                                                         │
│  │      {                                                       │
│  │        "type": "fork",                                      │
│  │        "product_id": "uuid-or-null",                       │
│  │        "specs": {...} ← SAME ATTRIBUTES AS PRODUCTS        │
│  │      },                                                      │
│  │      {                                                       │
│  │        "type": "cassette",                                  │
│  │        "product_id": "uuid",                               │
│  │        "specs": {                                           │
│  │          "speeds": 12,                                      │
│  │          "freehub_standard": "sram_xd"                     │
│  │        }                                                     │
│  │      }                                                       │
│  │    ]                                                         │
│  └─ diagram_svg: SVG with clickable component hotspots         │
└─────────────────────────────────────────────────────────────────┘
                              ↓ FK: catalog_bike_id
┌─────────────────────────────────────────────────────────────────┐
│                 CUSTOMER BIKES (Instance Layer)                  │
├─────────────────────────────────────────────────────────────────┤
│  bike_instances (tenant_id)                                     │
│  ├─ id (PK)                                                     │
│  ├─ customer_id → customers.id                                 │
│  ├─ catalog_bike_id → bike_catalog.id (nullable)              │
│  ├─ bike_compatibility_profile JSONB ← AUTO-UPDATED            │
│  │    {                                                         │
│  │      "frame_specs": {...}, ← COPY FROM CATALOG             │
│  │      "components": [       ← CURRENT INSTALLED PARTS       │
│  │        {                                                     │
│  │          "type": "cassette",                                │
│  │          "product_id": "uuid-upgraded-cassette",           │
│  │          "specs": {                                         │
│  │            "speeds": 12,   ← UPGRADED FROM 11s             │
│  │            "range_max": 52 ← NEW VALUE                     │
│  │          }                                                   │
│  │        }                                                     │
│  │      ]                                                       │
│  │    }                                                         │
│  │                                                              │
│  bike_instance_components (tenant_id)                          │
│  ├─ id (PK)                                                     │
│  ├─ bike_instance_id → bike_instances.id                      │
│  ├─ component_type_code → compat_component_library.code       │
│  ├─ product_id → products.id (nullable)                       │
│  ├─ installed_date, removed_date                               │
│  ├─ specs JSONB ← OVERRIDE if product lacks attributes        │
│  └─ TRIGGER: update_bike_compatibility_profile()              │
│       ON INSERT/UPDATE/DELETE                                   │
│       → Rebuilds bike_instances.bike_compatibility_profile    │
└─────────────────────────────────────────────────────────────────┘
                              ↓ FK: bike_id
┌─────────────────────────────────────────────────────────────────┐
│               EVALUATION ENGINE (Runtime Layer)                  │
├─────────────────────────────────────────────────────────────────┤
│  compat_sessions (tenant_id)                                    │
│  ├─ id (PK)                                                     │
│  ├─ bike_id → bike_instances.id (nullable)                    │
│  ├─ customer_id, job_id, budget_max                           │
│  └─ context JSONB: {discipline, purpose, technician}           │
│                                                                  │
│  compat_evaluations (tenant_id)                                │
│  ├─ id (PK)                                                     │
│  ├─ session_id → compat_sessions.id                           │
│  ├─ component_type_code → compat_component_library.code       │
│  ├─ mode: 1/2/3                                                │
│  ├─ bike_specs_snapshot JSONB ← FROM bike_compatibility_profile│
│  │                                                              │
│  compat_evaluation_items (tenant_id)                           │
│  ├─ id (PK)                                                     │
│  ├─ evaluation_id → compat_evaluations.id                     │
│  ├─ product_id → products.id                                  │
│  ├─ compatibility_score: 0-100                                 │
│  ├─ match_details JSONB: {attribute_scores: [...]}            │
│  ├─ adapters_required JSONB: [{type, cost, labor}]            │
│  └─ warnings: ["Requires freehub swap", "Low stock"]          │
│                                                                  │
│  compat_rule_audit_log (tenant_id)                            │
│  ├─ id (PK)                                                     │
│  ├─ evaluation_id → compat_evaluations.id                     │
│  ├─ product_id → products.id                                  │
│  ├─ rule_name: "spoke_holes_exact_match"                      │
│  ├─ bike_value: {"spoke_holes": 32}                           │
│  ├─ product_value: {"spoke_holes": 32}                        │
│  ├─ match_result: "pass" / "fail" / "partial_with_adapter"   │
│  └─ score_contribution: 5.0                                    │
└─────────────────────────────────────────────────────────────────┘
```

#### 3.4.2 Attribute Schema Propagation (THE KEY WIRING!)

**⚠️ CRITICAL: All three systems use THE SAME attribute schema from `compat_component_library.metadata`**

```
Flow of attribute definitions:

1. METADATA DEFINITION (Source of Truth)
   compat_component_library.metadata = {
     "attributes": [
       {
         "key": "spoke_holes",
         "label": "Número rayos",
         "type": "integer",
         "required": true,
         "enum_values": [12, 16, 20, 24, 28, 32, 36, 40, 48]
       },
       {
         "key": "spacing_mm",
         "label": "OLD",
         "type": "numeric",
         "units": "mm",
         "required": true,
         "min": 110,
         "max": 210
       }
     ]
   }

2. PRODUCT FORM (Consumer #1)
   Flutter product form calls:
     get_category_with_component_metadata(category_id)
   ↓
   Receives metadata.attributes array
   ↓
   Builds dynamic form fields:
     - spoke_holes → DropdownButtonFormField<int>(items: [12,16,20...])
     - spacing_mm → TextFormField(keyboardType: number, validator: 110-210)
   ↓
   Saves to products.compatibility_attributes = {
     "spoke_holes": 32,
     "spacing_mm": 148
   }

3. BIKE CATALOG (Consumer #2)
   Bike catalog admin form uses SAME metadata:
     get_component_metadata('frame')
   ↓
   Renders fields for bike_catalog.frame_specs:
     - rear_hub_spacing_mm → TextFormField (110-210)
     - rear_axle_type → DropdownButtonFormField (enum values)
   ↓
   Saves to bike_catalog.frame_specs = {
     "rear_hub_spacing_mm": 148,
     "rear_axle_type": "thru_12x148"
   }
   ↓
   Also renders factory_components editor:
     - User adds "Fork" component
     - Form fetches get_component_metadata('fork')
     - Renders travel_mm, offset_mm, axle_type fields
     - Saves to factory_components = [{type: "fork", specs: {...}}]

4. CUSTOMER BIKE (Consumer #3)
   When customer bike created from catalog:
     INSERT INTO bike_instances (
       catalog_bike_id = 'uuid-trek-fuel-ex',
       bike_compatibility_profile = (
         SELECT jsonb_build_object(
           'frame_specs', frame_specs,  ← COPY ATTRIBUTES
           'components', factory_components ← COPY ATTRIBUTES
         )
         FROM bike_catalog WHERE id = 'uuid-trek-fuel-ex'
       )
     )
   ↓
   When mechanic upgrades cassette:
     INSERT INTO bike_instance_components (
       bike_instance_id = 'uuid-johns-bike',
       component_type_code = 'cassette',
       product_id = 'uuid-new-12s-cassette',
       specs = (
         SELECT compatibility_attributes ← SAME ATTRIBUTES!
         FROM products WHERE id = 'uuid-new-12s-cassette'
       )
     )
   ↓
   TRIGGER fires → updates bike_compatibility_profile
   ↓
   Now bike has upgraded specs using SAME attribute schema

5. EVALUATION ENGINE (Consumer #4)
   compat_run_evaluation(session_id, 'rear_hub', mode=2)
   ↓
   Loads bike specs:
     bike_compatibility_profile.frame_specs.rear_hub_spacing_mm = 148
   ↓
   Loads component metadata:
     compat_component_library WHERE code='rear_hub'
     → metadata.attributes = [{key: "spoke_holes", ...}, {key: "spacing_mm", ...}]
   ↓
   Queries products:
     SELECT compatibility_attributes FROM products
     WHERE component_type_code = 'rear_hub'
   ↓
   Compares attributes (SAME KEYS!):
     bike: {"spacing_mm": 148}
     product: {"spacing_mm": 142}
     → Difference: 6mm → Check adapter rules → Partial match
```

#### 3.4.3 Bike Diagram Interactive Wiring

**Bike Catalog → Diagram → Component Selection**

```
1. DIAGRAM STORAGE
   bike_catalog.diagram_svg = 'https://storage.supabase.co/diagrams/trek_fuel_ex.svg'
   bike_catalog.hotspots JSONB = [
     {
       "component_type": "cassette",
       "label": "Cassette",
       "x": 520, "y": 280, "width": 45, "height": 45,
       "current_specs": {
         "speeds": 11,
         "range": "11-50t",
         "freehub_standard": "shimano_hg"
       }
     },
     {
       "component_type": "rear_derailleur",
       "label": "Cambio",
       "x": 530, "y": 320, "width": 40, "height": 70,
       "current_product_id": "uuid-sram-gx"
     }
   ]

2. UI RENDERING (Flutter)
   BikeProfilePage → loads bike_catalog entry
   ↓
   Displays SVG via flutter_svg package
   ↓
   Overlays clickable regions as Stack > Positioned widgets:
     for (hotspot in bike.hotspots) {
       Positioned(
         left: hotspot.x,
         top: hotspot.y,
         child: GestureDetector(
           onTap: () => _showCompatibilityModal(hotspot.component_type),
           child: Container(
             decoration: BoxDecoration(
               border: Border.all(
                 color: _getCompatibilityColor(hotspot), // Green/Yellow/Red
                 width: 2
               )
             ),
             child: Badge(label: _getCompatibilityIcon(hotspot)) // ✅⚠️❌
           )
         )
       )
     }

3. USER INTERACTION
   User taps "Cassette" hotspot
   ↓
   _showCompatibilityModal('cassette')
   ↓
   Calls: compat_run_evaluation(
     session_id: current_session,
     component_type_code: 'cassette',
     mode: 3, // Upgrade Explorer
     bike_id: bike_instance.id
   )
   ↓
   Modal shows:
     - Current: Shimano XT 11-50t (11s, HG freehub)
     - Compatible Upgrades:
       ✅ SRAM GX Eagle 10-52t (12s, XD) - $145k + freehub swap ($45k)
       ✅ Shimano XT M8100 11-51t (12s, Microspline) - $135k + freehub swap ($50k)
       ⭐ SRAM XX1 Eagle 10-52t (12s, XD) - $320k [Premium]
   ↓
   User selects upgrade
   ↓
   Creates mechanic_job with job_items (cassette + freehub body) + labor
   ↓
   On job completion:
     INSERT INTO bike_instance_components (
       bike_instance_id, 
       component_type_code = 'cassette',
       product_id = selected_product_id,
       installed_date = now()
     )
   ↓
   Trigger updates bike_compatibility_profile
   ↓
   Diagram hotspot color changes: Yellow (needs upgrade) → Green (upgraded)
```

#### 3.4.4 Compatibility Badge Logic

**How diagram knows what color to show:**

```sql
-- RPC function for diagram badge calculation
create or replace function get_bike_compatibility_badges(p_bike_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_bike_profile jsonb;
  v_badges jsonb := '[]'::jsonb;
  v_component record;
begin
  -- Load bike profile
  select bike_compatibility_profile into v_bike_profile
  from bike_instances where id = p_bike_id;
  
  -- For each component in profile
  for v_component in 
    select * from jsonb_array_elements(v_bike_profile->'components')
  loop
    -- Check if component has product_id (linked to inventory)
    if v_component->>'product_id' is not null then
      -- Check stock status
      if exists(
        select 1 from products 
        where id = (v_component->>'product_id')::uuid 
        and stock_quantity > 0
      ) then
        v_badges := v_badges || jsonb_build_object(
          'component_type', v_component->>'type',
          'status', 'compatible', -- ✅ Green
          'icon', 'check_circle',
          'message', 'Compatible y en stock'
        );
      else
        v_badges := v_badges || jsonb_build_object(
          'component_type', v_component->>'type',
          'status', 'warning', -- ⚠️ Yellow
          'icon', 'warning',
          'message', 'Sin stock, requiere pedido'
        );
      end if;
    else
      -- No product linked, needs attention
      v_badges := v_badges || jsonb_build_object(
        'component_type', v_component->>'type',
        'status', 'error', -- ❌ Red
        'icon', 'error',
        'message', 'Componente no catalogado'
      );
    end if;
  end loop;
  
  return jsonb_build_object('badges', v_badges);
end;
$$;
```

**Flutter integration:**
```dart
// In BikeProfilePage
Future<void> _loadCompatibilityBadges() async {
  final result = await Supabase.instance.client
    .rpc('get_bike_compatibility_badges', params: {'p_bike_id': widget.bikeId});
  
  setState(() {
    _badges = (result['badges'] as List)
      .map((b) => CompatibilityBadge.fromJson(b))
      .toList();
  });
}

// Badge color mapping
Color _getCompatibilityColor(String status) {
  switch (status) {
    case 'compatible': return Colors.green;
    case 'warning': return Colors.orange;
    case 'error': return Colors.red;
    case 'upgrade_pending': return Colors.blue;
    default: return Colors.grey;
  }
}
```

---

## 4. Metadata & Dictionary Expansion

### 4.1 Component Taxonomy
Expand `compat_component_types` to cover:
- **Frame system**: frame, fork, headset, seatpost, dropper, seatclamp, handlebar, stem, saddle.
- **Wheel system**: wheelset, front hub, rear hub, rim, spoke, nipple, tire, tube, rotor, axle.
- **Drivetrain**: crankset, bottom bracket, chainring, chain, cassette, rear derailleur, front derailleur, shifter, pedal, chainguide, freehub body.
- **Braking**: caliper, lever, hose, master cylinder, rotor, adapter.
- **Conversion/Accessory**: hanger kits, dropout kits, spacer kits, torque arms, rotor spacers, cassette conversion kits.
Include display names, icons, parent-child relations, discipline applicability, and default scoring profiles.

### 4.2 Attribute Dictionary (Complete Field Metadata)

**This is the master list of ALL compatibility attributes across ALL component types.**

Each attribute includes: key, label, type, units, components that use it, range/enum values, validation rules, and notes.

#### 4.2.1 Frame System Attributes

| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| rear_hub_spacing_mm | OLD trasero | numeric | mm | frames, rear hubs | 110–210 (0.5 step) | ✅ | 120=track, 126=vintage, 130=road, 135=MTB, 142/148=boost, 150=DH, 157=super-boost |
| front_hub_spacing_mm | OLD delantero | numeric | mm | frames, forks, front hubs | 90–158 | ✅ | 90=BMX, 100=road/MTB, 110=boost, 130/135=fatbike |
| rear_axle_type | Tipo eje trasero | enum | — | frames, rear hubs | {qr_9x100, qr_9x130, qr_10x135, thru_10x135, thru_12x135, thru_12x142, thru_12x148, bolt_on, bmx_14mm} | ✅ | Maps to adapter kits for conversions |
| front_axle_type | Tipo eje delantero | enum | — | frames, forks, front hubs | {qr_9x100, thru_12x100, thru_12x110, thru_15x100, thru_15x110, thru_20x110, bolt_on, bmx_10mm} | ✅ | |
| dropout_standard | Norma patilla | enum | — | frames, rear derailleurs | {udh, standard_hanger, direct_mount, horizontal, bmx, track} | ✅ | UDH = Universal Derailleur Hanger (SRAM) |
| brake_mount_front | Montaje freno delantero | enum | — | frames, forks, calipers | {post_mount, flat_mount, is_mount, v_brake, cantilever, none} | ✅ | Post = 6-bolt pattern, Flat = road standard |
| brake_mount_rear | Montaje freno trasero | enum | — | frames, calipers | {post_mount, flat_mount, is_mount, v_brake, cantilever, roller_brake, none} | ✅ | |
| frame_tire_max_width_mm | Ancho máx neumático | numeric | mm | frames | 20–80 | ⚠️ discipline | Critical for wheel upgrades |
| frame_wheel_size | Tamaño rueda | enum | — | frames, forks, wheels | {700c, 650b_27_5, 29er, 26in, 24in, 20in, 18in, 16in, 12in} | ✅ | Can mix front/rear (mullet setups) |
| bb_type | Tipo caja pedalier | enum | — | frames, bottom brackets | {bsa_68, bsa_73, ita_70, pf30, bb86, bb92, bb30, t47, bb386, pressfit_41, bmx_19mm, bmx_22mm, bmx_24mm} | ✅ | BSA = threaded English, PF = press-fit |
| bb_width_mm | Ancho caja | numeric | mm | frames, bottom brackets | 68, 73, 83, 86, 89.5, 92, 100, 120 | ✅ | Affects spindle length selection |
| bb_thread_pitch | Paso hilo caja | text | — | frames, bottom brackets | 1.37x24, 1.375x24, M36x24, 36x24 | ⚠️ threaded only | BSA = 1.37x24 TPI (English) |
| seatpost_diameter_mm | Diámetro tija | numeric | mm | frames, seatposts | 22.2, 25.4, 26.8, 27.2, 28.6, 30.4, 30.9, 31.6, 31.8, 34.9 | ✅ | Common: 27.2 (road vintage), 31.6 (MTB) |
| seatpost_type | Tipo tija | enum | — | frames, seatposts | {rigid, dropper} | ⚠️ discipline | MTB allows both, road typically rigid only |
| headset_standard | Norma dirección | enum | — | frames, headsets | {zs44_zs56, zs44_ec44, is41_is52, ec34_ec34, threaded_1_1_8, tapered_integrated, bmx_integrated} | ✅ | ZS = zero stack, EC = external cup, IS = integrated |
| headtube_length_mm | Largo tubo dirección | numeric | mm | frames | 90–220 | Optional | Affects stack height |
| steerer_type | Tipo horquilla | enum | — | frames, forks, stems | {straight_1_1_8, tapered_1_1_8_to_1_5, straight_1in, threaded_1in, threaded_1_1_8, bmx_integral} | ✅ | Tapered = modern standard |
| front_rotor_max_mm | Disco máx delantero | integer | mm | frames, forks | 140, 160, 180, 203, 220 | ⚠️ discipline | Road: 140-160, MTB: 160-203, DH: 203-220 |
| rear_rotor_max_mm | Disco máx trasero | integer | mm | frames | 140, 160, 180, 203, 220 | ⚠️ discipline | |
| chainline_mm | Línea de cadena | numeric | mm | frames, cranksets | 42–58 | ✅ | Road: 43.5, MTB 1x: 49-52, 2x: 48.8 |

#### 4.2.2 Fork Attributes

| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| travel_mm | Recorrido | numeric | mm | forks | 0–250 | ✅ | Rigid = 0, XC = 80-120, Trail = 130-160, Enduro/DH = 170-250 |
| offset_mm | Offset | numeric | mm | forks | 37–58 | ✅ | Road: 43-50, MTB: 37-51 (affects handling) |
| axle_type | Tipo eje | enum | — | forks, hubs | {qr_9x100, thru_12x100, thru_12x110, thru_15x100, thru_15x110, thru_20x110} | ✅ | Modern MTB = 15mm thru |
| spacing_mm | OLD horquilla | numeric | mm | forks, front hubs | 90–150 | ✅ | 100 = standard, 110 = boost, 150 = DH |
| brake_mount | Montaje freno | enum | — | forks, calipers | {post_mount, flat_mount, is_mount, v_brake, cantilever, none} | ✅ | |
| steerer_type | Tipo pivote | enum | — | forks, stems, headsets | {straight_1_1_8, tapered_1_1_8_to_1_5, straight_1in, threaded_1in} | ✅ | Tapered requires compatible headset |
| steerer_length_mm | Largo pivote | numeric | mm | forks | 180–320 | Optional | Can be cut shorter |
| max_tire_width_mm | Ancho neumático máx | numeric | mm | forks | 20–90 | ✅ | Gravel: 40-50, MTB: 2.3-2.6in (58-66mm) |
| crown_to_axle_mm | Corona a eje | numeric | mm | forks | 400–600 | Optional | Affects geometry when changing forks |

#### 4.2.3 Wheel System Attributes

| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| wheel_size | Tamaño rueda | enum | — | wheels, tires, tubes, frames | {700c, 650b_27_5, 29er, 26in, 24in, 20in, 16in} | ✅ | 700c = road, 29er = MTB large, 27.5 = MTB mid |
| bsd_diameter_mm | Diámetro BSD | integer | mm | rims, tires, tubes | 203, 305, 349, 406, 451, 507, 540, 559, 571, 584, 622 | ✅ | BSD = Bead Seat Diameter (ISO standard) |
| rim_internal_width_mm | Ancho interno aro | numeric | mm | rims | 13–45 | ✅ | Road: 15-21, Gravel: 19-25, MTB: 25-35 |
| rim_external_width_mm | Ancho externo aro | numeric | mm | rims | 18–60 | Optional | For aerodynamics calculations |
| rim_depth_mm | Profundidad aro | numeric | mm | rims | 15–90 | Optional | Aero wheels: 40-90mm |
| tubeless_ready | Compatible tubeless | boolean | — | rims, tires | true/false | ✅ | Requires sealant + compatible rim tape |
| spoke_holes | Número rayos | integer | holes | hubs, rims | 12, 16, 20, 24, 28, 32, 36, 40, 48 | ✅ | MUST match exactly (hub holes = rim holes) |
| erd_mm | ERD | numeric | mm | rims | 500–650 | Optional | Effective Rim Diameter for spoke length calculation |
| freehub_standard | Cuerpo cassette | enum | — | rear hubs, cassettes | {shimano_hg, microspline, sram_xd, sram_xdr, campagnolo_11s, t_type, hg_5s_vintage, hg_7s_vintage} | ✅ | Modern: HG (8-11s), Microspline (12s), XD (10-52t) |
| rotor_mount | Montaje disco | enum | — | hubs, rotors | {6_bolt, centerlock, none} | ✅ | Adapter: 6-bolt → Centerlock exists |
| hub_bearing_type | Tipo rodamiento | enum | — | hubs | {cartridge, cup_and_cone, ceramic} | Optional | Affects maintenance |
| hub_position | Posición | enum | — | hubs | {front, rear} | ✅ | Some hubs work both positions |
| flange_diameter_left_mm | Diámetro brida izq | numeric | mm | hubs | 30–80 | Optional | For spoke length calculations |
| flange_diameter_right_mm | Diámetro brida der | numeric | mm | hubs | 30–80 | Optional | |
| center_to_flange_left_mm | Centro a brida izq | numeric | mm | hubs | 15–50 | Optional | |
| center_to_flange_right_mm | Centro a brida der | numeric | mm | hubs | 15–50 | Optional | |

#### 4.2.4 Tire & Tube Attributes

| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| bsd_diameter_mm | Diámetro BSD | integer | mm | tires, tubes | 203–622 | ✅ | MUST match rim BSD exactly |
| width_mm | Ancho | numeric | mm | tires, tubes | 18–120 | ✅ | Road: 23-32, Gravel: 32-50, MTB: 50-75 (2.0-3.0in) |
| tire_width_inch | Ancho (pulgadas) | numeric | inch | tires | 0.7–5.0 | Optional | Alternative to mm (MTB: 2.1, 2.3, 2.5, etc.) |
| casing | Carcasa | enum | — | tires | {folding, wire_bead, tubular} | Optional | Folding lighter, wire cheaper |
| tpi | TPI | integer | threads/inch | tires | 30–320 | Optional | Higher TPI = suppler, faster (road: 120-320, MTB: 60-120) |
| tubeless_ready | Compatible tubeless | boolean | — | tires | true/false | ✅ | Requires compatible rim + sealant |
| compound | Compuesto | enum | — | tires | {single, dual, triple, graphene} | Optional | Dual = center fast, sides grippy |
| tread_pattern | Patrón | enum | — | tires | {slick, semi_slick, file_tread, knobby, aggressive, mud} | Optional | Slick = road, knobby = MTB |
| puncture_protection | Protección | enum | — | tires | {none, standard, reinforced, aramid, kevlar} | Optional | |
| valve_type | Tipo válvula | enum | — | tubes | {presta, schrader, dunlop} | ✅ | Presta = road/MTB, Schrader = city/kids |
| valve_length_mm | Largo válvula | numeric | mm | tubes | 32–80 | ⚠️ deep rims | Deep aero rims need 60-80mm valves |

#### 4.2.5 Drivetrain Attributes

**Cassette:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| speeds | Velocidades | integer | — | cassettes, chains, derailleurs, shifters | 5–13 | ✅ | Modern: 8-13, Vintage: 5-7 |
| range_min_teeth | Mín dientes | integer | teeth | cassettes | 9–15 | ✅ | Road: 11-12, MTB: 10-11 |
| range_max_teeth | Máx dientes | integer | teeth | cassettes, rear derailleurs | 21–60 | ✅ | Road: 25-34, MTB 1x: 42-52 |
| freehub_standard | Cuerpo | enum | — | cassettes, hubs | {shimano_hg, microspline, sram_xd, sram_xdr, campagnolo, t_type} | ✅ | XD = 10t small cog, HG = 11t min |

**Rear Derailleur:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| speeds | Velocidades | integer | — | rear derailleurs | 5–13 | ✅ | Must match cassette + shifter |
| max_teeth | Máx dientes | integer | teeth | rear derailleurs | 24–60 | ✅ | Cassette max MUST be ≤ derailleur max |
| cage_length | Largo jaula | enum | — | rear derailleurs | {short, medium, long, extra_long} | ✅ | Long = wide range cassettes (11-50t) |
| clutch | Clutch | boolean | — | rear derailleurs | true/false | ⚠️ MTB | Reduces chain slap, MTB only |
| mount_type | Montaje | enum | — | rear derailleurs | {standard_hanger, direct_mount, udh, vintage_claw} | ✅ | UDH = SRAM universal, Direct = road electronic |
| pull_ratio | Ratio cable | enum | — | rear derailleurs, shifters | {shimano, sram_1_1, campagnolo, sram_exact_actuation} | ✅ | MUST match shifter brand |

**Chain:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| speeds | Velocidades | integer | — | chains | 5–13 | ✅ | Must match cassette + derailleur |
| chain_standard | Norma | enum | — | chains | {shimano_hg, shimano_hg_plus, sram_eagle, sram_t_type, campagnolo_11s, single_speed} | ✅ | Eagle = 12s MTB, T-Type = 13s (no shifter cable) |
| width_mm | Ancho | numeric | mm | chains | 5.5–11.0 | Optional | Narrower for 11-13s |

**Crankset:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| chainline_mm | Línea cadena | numeric | mm | cranksets | 42–58 | ✅ | Must match frame chainline ±2mm |
| q_factor_mm | Factor Q | numeric | mm | cranksets | 130–200 | Optional | Width between pedal mounting holes |
| spindle_type | Tipo eje | enum | — | cranksets, bottom brackets | {square_taper, octalink, isis, hollowtech_ii, bb30, pf30, gxp, dub, t47, bsa} | ✅ | Modern: Hollowtech II (Shimano), GXP/DUB (SRAM) |
| spindle_diameter_mm | Diámetro eje | numeric | mm | cranksets, bottom brackets | 16–30 | ✅ | Square taper: 16mm, Hollowtech: 24mm, DUB: 28.99mm |
| chainring_mount | Montaje plato | enum | — | cranksets, chainrings | {bcd_110_5bolt, bcd_104_4bolt, bcd_64_4bolt, direct_mount_sram, direct_mount_shimano, single_speed} | ✅ | BCD = Bolt Circle Diameter |
| arm_length_mm | Largo biela | numeric | mm | cranksets | 150–180 | Optional | Road: 170-175, MTB: 170-175, Kids: 150-165 |

**Chainrings:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| teeth_count | Dientes | integer | teeth | chainrings | 20–60 | ✅ | 1x MTB: 28-36t, Road compact: 50/34t |
| bcd_mm | BCD | numeric | mm | chainrings | 58–144 | ⚠️ bolt-on | Bolt Circle Diameter (110/130 road, 104 MTB) |
| mount_pattern | Patrón montaje | enum | — | chainrings | {bcd_5bolt, bcd_4bolt, direct_mount_sram, direct_mount_shimano} | ✅ | Direct mount = integrated spider |
| offset_mm | Offset | numeric | mm | chainrings | 0–6 | Optional | For chainline tuning |
| wide_narrow | Wide-Narrow | boolean | — | chainrings | true/false | ⚠️ 1x only | Alternating tooth width prevents chain drop |

**Front Derailleur (Road/Vintage):**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| speeds | Velocidades | integer | — | front derailleurs | 2–3 | ✅ | 2x = modern, 3x = vintage/touring |
| mount_type | Montaje | enum | — | front derailleurs | {clamp_31_8, clamp_34_9, braze_on, e_type, direct_mount} | ✅ | Clamp = seat tube, E-type = BB mount |
| capacity_teeth | Capacidad | integer | teeth | front derailleurs | 10–22 | Optional | Max difference between chainrings (e.g., 50-34 = 16t) |

**Shifters:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| speeds_rear | Velocidades traseras | integer | — | shifters | 5–13 | ✅ | Must match cassette + derailleur |
| speeds_front | Velocidades delanteras | integer | — | shifters | 0, 2, 3 | Optional | 0 = 1x (no front derailleur) |
| shifter_type | Tipo | enum | — | shifters | {trigger, grip_shift, bar_end, integrated_brake, electronic, friction} | ✅ | Trigger = MTB, Integrated = road brifters |
| pull_ratio | Ratio cable | enum | — | shifters, derailleurs | {shimano, sram_1_1, campagnolo, sram_exact_actuation} | ✅ | MUST match derailleur brand |
| brake_lever_type | Tipo palanca freno | enum | — | shifters | {none, road_dual_pivot, road_hydraulic, flat_bar_v_brake, flat_bar_hydraulic} | ⚠️ integrated | Brifters include brake levers |

**Bottom Bracket:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| bb_type | Tipo caja | enum | — | bottom brackets, frames | {bsa_68, bsa_73, ita_70, pf30, bb86, bb92, t47} | ✅ | Must match frame bb_type |
| spindle_compatibility | Compatibilidad eje | enum | — | bottom brackets, cranksets | {square_taper, hollowtech_ii, bb30, gxp, dub} | ✅ | Adapter BBs exist (e.g., GXP in BSA frame) |
| width_mm | Ancho | numeric | mm | bottom brackets | 68, 73, 83, 86, 92, 100 | ✅ | Must match frame bb_width_mm |

#### 4.2.6 Cockpit Attributes

**Handlebars:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| clamp_diameter_mm | Diámetro abrazadera | numeric | mm | handlebars, stems | 25.4, 31.8, 35.0 | ✅ | 25.4 = vintage/city, 31.8 = modern, 35 = DH |
| width_mm | Ancho | numeric | mm | handlebars | 340–840 | ✅ | Road: 380-460, MTB: 700-800 |
| rise_mm | Rise | numeric | mm | handlebars | -20–80 | Optional | Flat = 0, riser = 15-40mm |
| sweep_deg | Sweep | numeric | degrees | handlebars | 0–25 | Optional | Backwards angle for comfort |
| grip_diameter_mm | Diámetro puño | numeric | mm | handlebars, grips | 20–32 | Optional | Standard: 22.2mm |
| bar_type | Tipo manubrio | enum | — | handlebars | {flat, riser, drop, bullhorn, aero, bmx, cruiser} | ✅ | Drop = road, flat/riser = MTB |

**Stems:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| clamp_diameter_mm | Diámetro abrazadera | numeric | mm | stems, handlebars | 25.4, 31.8, 35.0 | ✅ | Must match handlebar clamp |
| steerer_type | Tipo horquilla | enum | — | stems, forks | {straight_1_1_8, tapered, threaded_1in, threaded_1_1_8} | ✅ | Threadless = modern, threaded = vintage |
| length_mm | Largo | numeric | mm | stems | 35–150 | ✅ | Road: 80-130, MTB: 35-90 (shorter = more control) |
| angle_deg | Ángulo | integer | degrees | stems | -17–+45 | ✅ | Negative = drops bars, positive = raises |

**Seatposts:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| diameter_mm | Diámetro | numeric | mm | seatposts, frames | 22.2–34.9 | ✅ | Must match frame seatpost_diameter_mm exactly |
| length_mm | Largo | numeric | mm | seatposts | 250–500 | ✅ | Dropper: 125-200mm travel + stack height |
| type | Tipo | enum | — | seatposts | {rigid, dropper} | ✅ | Dropper requires internal/external cable routing |
| travel_mm | Recorrido | numeric | mm | seatposts (dropper) | 100–240 | ⚠️ dropper | MTB: 125-200mm common |
| actuation | Actuación | enum | — | seatposts (dropper) | {cable, hydraulic, electronic} | ⚠️ dropper | Electronic = wireless (AXS, Di2) |

**Saddles:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| rail_type | Tipo rieles | enum | — | saddles, seatposts | {round_7mm, oval_7x9, carbon_7x10} | ✅ | Standard: round 7mm, carbon lighter but requires compatible clamp |
| width_mm | Ancho | numeric | mm | saddles | 130–175 | Optional | Narrow (130-143) = road, wide (155-175) = MTB/comfort |

#### 4.2.7 Brake System Attributes

**Calipers:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| brake_type | Tipo freno | enum | — | calipers, levers | {mechanical_disc, hydraulic_disc, rim_v_brake, rim_cantilever, rim_dual_pivot, rim_single_pivot, coaster} | ✅ | Hydraulic = better modulation, mechanical = easier service |
| rotor_mount | Montaje disco | enum | — | calipers, hubs, rotors | {6_bolt, centerlock, none} | ⚠️ disc only | |
| caliper_mount | Montaje pinza | enum | — | calipers, frames, forks | {post_mount, flat_mount, is_mount, v_brake_bosses, cantilever_studs} | ✅ | Post = MTB, flat = road |
| piston_count | Pistones | integer | — | calipers | 1, 2, 4, 6 | Optional | More pistons = more power (DH: 4-6, XC: 2) |
| pad_type | Tipo pastilla | enum | — | calipers, brake pads | {organic, sintered, semi_metallic} | Optional | Organic = quiet, sintered = long-lasting |

**Rotors:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| size_mm | Tamaño | integer | mm | rotors | 140, 160, 180, 200, 203, 220 | ✅ | Must be ≤ frame/fork rotor_max |
| mount_type | Montaje | enum | — | rotors, hubs | {6_bolt, centerlock} | ✅ | Adapter: 6-bolt hub → centerlock rotor exists |
| rotor_type | Tipo | enum | — | rotors | {floating, one_piece} | Optional | Floating reduces heat transfer to hub |

**Brake Levers:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| brake_type | Tipo freno | enum | — | levers, calipers | {mechanical_disc, hydraulic_disc, v_brake, cantilever, dual_pivot} | ✅ | Must match caliper type |
| lever_reach_adjustable | Ajuste alcance | boolean | — | levers | true/false | Optional | Important for small hands / kids |
| pull_ratio | Ratio cable | enum | — | levers (mechanical), calipers | {standard, long_pull, short_pull} | ⚠️ mechanical | Long pull = V-brakes, short = calipers |

#### 4.2.8 Miscellaneous Attributes

**Pedals:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| thread_size | Rosca | enum | — | pedals, cranks | {9_16_inch, 1_2_inch} | ✅ | 9/16" = adult, 1/2" = kids/BMX |
| pedal_type | Tipo | enum | — | pedals | {platform, clipless_mtb, clipless_road, cage, bmx} | Optional | Clipless = cleated shoes |

**Grips:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| diameter_mm | Diámetro | numeric | mm | grips, handlebars | 20–32 | Optional | Standard: 22.2mm |
| length_mm | Largo | numeric | mm | grips | 90–140 | Optional | Lock-on grips = fixed length |

**Hoses:**
| Key | Label | Type | Units | Components | Range/Enum | Required | Notes |
|-----|-------|------|-------|------------|------------|----------|-------|
| hose_type | Tipo manguera | enum | — | hoses, calipers, levers | {dot_fluid, mineral_oil} | ⚠️ hydraulic | DOT = Avid/SRAM, Mineral = Shimano (NOT interchangeable) |
| fitting_standard | Norma conexión | enum | — | hoses | {shimano_banjo, sram_dot, hope, magura} | ⚠️ hydraulic | Brand-specific fittings |

---

**Implementation Notes:**
1. ✅ Required = MUST be filled for compatibility evaluation
2. ⚠️ Conditional = Required based on component type or discipline
3. Optional = Improves recommendations but not blocking
4. All numeric fields support min/max validation
5. All enum fields use standardized keys (no free text)
6. Units explicitly defined (mm, inch, teeth, threads/inch, etc.)
7. Cross-component validation (e.g., cassette.max_teeth ≤ derailleur.max_teeth)

### 4.3 Attribute Schema Mapping
For each component type, define required vs optional fields, match weights, UI groups, and validation hints. Example (rear hub):

| Attribute | Required | Match Weight | UI Group | Notes |
|-----------|----------|--------------|----------|-------|
| spoke_holes | ✅ | 5.0 | Core | Must match rim exactly |
| hub_spacing_mm | ✅ | 4.5 | Core | Allow ±3mm with adapter |
| axle_type | ✅ | 4.0 | Mounting | Suggest adapter if mismatch |
| freehub_standard | ✅ | 4.0 | Drivetrain | Enable conversions |
| brake_interface | ⚠ discipline | 3.5 | Mounting | |
| flange_diameter_left/right | Optional | 3.0 | Calculations | Needed for spoke length |
| center_to_flange_left/right | Optional | 3.0 | Calculations | |

Repeat tables for every component. Store canonical copy in this document’s appendix and sync with Supabase seeds.

### 4.4 Conversion & Adapter Metadata
- `compat_conversion_rules`: define from/to component type, requirements JSON, allowed disciplines, labor minutes, cost, warnings.
- `compat_adapter_catalog`: catalog of adapter SKUs or virtual kits; reference actual products for procurement.
- `compat_adapter_components`: breakdown of sub-parts per adapter kit.
- Example entry: "Boost 148 → Non-boost 142" requires axle kit + rotor spacers, 15 minutes labor, flag rotor alignment warning.

### 4.5 Discipline Rule Graphs
- `compat_disciplines`: register MTB Trail, DH, Gravel, Road Aero, City, BMX, Vintage.
- `compat_discipline_component_rules`: JSON rule sets covering mandatory matches, tolerances, forbidden combos, preferred upgrades, adapter allowances per discipline.
- Use these rules during evaluations to produce warnings and suggestions.

### 4.6 Bike Catalog & Customer Bikes

**CRITICAL INFRASTRUCTURE: The bike catalog is the template system that powers compatibility evaluations.**

#### 4.6.1 Bike Catalog Structure (`bike_catalog` table)

A bike catalog entry is a **complete factory specification** that serves as the baseline for compatibility checks:

**Core Fields:**
- `id` uuid primary key
- `tenant_id` uuid (multi-tenant isolation)
- `brand` text (e.g., Trek, Specialized, Cannondale, Santa Cruz)
- `model` text (e.g., Fuel EX 8, Stumpjumper Comp, Synapse Carbon)
- `year` integer (model year: 2020-2025)
- `discipline` enum (mtb_trail, mtb_dh, mtb_xc, road_endurance, road_aero, gravel, hybrid, city, bmx, vintage)
- `msrp` numeric (manufacturer suggested retail price - for upgrade comparisons)
- `image_url` text (bike photo for UI)
- `diagram_svg` text (interactive diagram data - clickable component hotspots)
- `is_active` boolean (for discontinued models)

**Frame Specifications (embedded in bike_catalog):**
```json
{
  "frame_specs": {
    "rear_hub_spacing_mm": 148,
    "rear_axle_type": "thru_12x142",
    "front_hub_spacing_mm": 110,
    "front_axle_type": "thru_15x110",
    "bb_type": "bsa_73",
    "bb_width_mm": 73,
    "bb_thread_pitch": "1.37x24",
    "headset_standard": "zs44_ec44",
    "steerer_type": "tapered_1_1_8_to_1_5",
    "front_rotor_max": 203,
    "rear_rotor_max": 203,
    "brake_mount_front": "flat_mount",
    "brake_mount_rear": "flat_mount",
    "wheel_size_front": "29er",
    "wheel_size_rear": "29er",
    "max_tire_width_mm": 62,
    "seatpost_diameter_mm": 31.6,
    "seatpost_type": "dropper",
    "dropout_standard": "udh"
  }
}
```

**Factory Components List (JSONB array):**
```json
{
  "factory_components": [
    {
      "type": "fork",
      "product_id": "uuid-or-null",
      "specs": {
        "brand": "RockShox",
        "model": "Pike Ultimate",
        "travel_mm": 150,
        "offset_mm": 44,
        "axle_type": "thru_15x110",
        "brake_mount": "post_mount",
        "steerer_type": "tapered"
      }
    },
    {
      "type": "rear_derailleur",
      "product_id": "uuid-or-null",
      "specs": {
        "brand": "SRAM",
        "model": "GX Eagle",
        "speeds": 12,
        "max_teeth": 52,
        "cage_length": "long",
        "clutch": true
      }
    },
    {
      "type": "cassette",
      "product_id": "uuid",
      "specs": {
        "brand": "SRAM",
        "model": "XG-1275",
        "speeds": 12,
        "range_min": 10,
        "range_max": 52,
        "freehub_standard": "sram_xd"
      }
    }
    // ... all components
  ]
}
```

**Why Product ID Can Be Null:**
- Catalog may reference OEM parts not in inventory
- Allows compatibility engine to suggest equivalent aftermarket parts
- When `product_id` exists, direct link to inventory for pricing/availability

#### 4.6.2 Customer Bikes (`bike_instances` table)

Customer bikes are **live, modifiable copies** of catalog bikes:

**Core Fields:**
- `id` uuid primary key
- `tenant_id` uuid
- `customer_id` uuid (FK to customers table)
- `catalog_bike_id` uuid (FK to bike_catalog - optional, null for custom builds)
- `nickname` text (e.g., "My Trail Bike", "Red Rocket")
- `serial_number` text
- `purchase_date` date
- `current_value` numeric (for insurance, depreciation tracking)
- `notes` text (service history, modifications, issues)

**Live Specifications (`bike_compatibility_profile` JSONB):**
- Starts as copy of `bike_catalog.frame_specs` + `factory_components`
- Updated via trigger whenever `bike_instance_components` changes
- Serves as **cached baseline** for evaluations (fast lookups)

**Component Override System (`bike_instance_components` table):**
```sql
create table bike_instance_components (
  id uuid primary key,
  tenant_id uuid not null,
  bike_instance_id uuid references bike_instances(id) on delete cascade,
  component_type text not null, -- "fork", "cassette", "rear_derailleur", etc.
  product_id uuid references products(id) on delete set null,
  installed_date date not null default current_date,
  removed_date date, -- null = currently installed
  installation_notes text,
  specs jsonb, -- override specs if product_id null or product lacks compatibility_attributes
  created_at timestamp default now()
);
```

**Upgrade Tracking:**
- Customer upgrades cassette 11-speed → 12-speed
- Mechanic creates new `bike_instance_components` entry:
  - `component_type = 'cassette'`
  - `product_id = <new_12s_cassette>`
  - `installed_date = today`
- Old cassette entry updated:
  - `removed_date = today`
- Trigger fires → updates `bike_compatibility_profile`:
  - `cassette.speeds = 12`
  - `cassette.freehub_standard = sram_xd`
  - `cassette.range_max = 52`

**Why This Matters for Compatibility:**
- Engine must check **current** bike state, not factory specs
- Customer may have incompatible upgrades that need resolution
- Historical tracking enables "undo" recommendations
- Enables "what broke when" diagnostics

#### 4.6.3 Compatibility Profile Auto-Update Trigger

```sql
create or replace function update_bike_compatibility_profile()
returns trigger
language plpgsql
as $$
begin
  -- Rebuild profile from current components
  update bike_instances
  set bike_compatibility_profile = (
    select jsonb_build_object(
      'frame_specs', bi.frame_specs, -- from catalog or custom
      'components', jsonb_agg(
        jsonb_build_object(
          'type', bic.component_type,
          'product_id', bic.product_id,
          'specs', coalesce(
            (select compatibility_attributes from products where id = bic.product_id),
            bic.specs
          )
        )
      )
    )
    from bike_instances bi
    left join bike_instance_components bic 
      on bic.bike_instance_id = bi.id 
      and bic.removed_date is null
    where bi.id = NEW.bike_instance_id
  )
  where id = NEW.bike_instance_id;
  
  return NEW;
end;
$$;

create trigger trg_update_bike_profile
after insert or update or delete on bike_instance_components
for each row
execute function update_bike_compatibility_profile();
```

#### 4.6.4 Use Cases

**Use Case 1: Customer brings factory bike for service**
1. Mechanic looks up bike in catalog (brand + model + year)
2. Creates `bike_instance` linked to `catalog_bike_id`
3. Profile auto-populated from catalog
4. Compatibility engine runs evaluation using catalog specs

**Use Case 2: Customer with upgraded bike**
1. Bike instance exists with modifications
2. Mechanic opens compatibility wizard
3. Engine loads `bike_compatibility_profile` (includes upgrades)
4. Recommends parts compatible with **current** config

**Use Case 3: Drivetrain conversion (9-speed → 12-speed)**
1. Engine evaluates in Mode 3 (Upgrade Explorer)
2. Detects: cassette, derailleur, shifter, chain must change together
3. Checks: freehub compatible? (Shimano HG → SRAM XD requires freehub body swap)
4. Generates adapter plan:
   - New freehub body (SKU: XD-CONV-001, $45, 20min labor)
   - 12s cassette (compatible with frame spacing)
   - 12s derailleur (compatible with dropout standard)
   - 12s shifter + chain
5. Creates quote with Good/Better/Best options
6. On approval: updates `bike_instance_components`, profile auto-updates

**Use Case 4: Warranty repair (must match OEM)**
1. Engine runs in Mode 1 (OEM Strict)
2. Compares current vs catalog factory specs
3. Flags deviations: "Customer installed aftermarket derailleur"
4. Recommends exact factory part for warranty compliance
5. Links to supplier if not in stock

### 4.7 Data Quality & Telemetry
- Nightly script verifying every product mapped to compatibility component type has required attributes.
- CLI report (CSV) for missing specs; auto-create remedial tasks.
- Use `compat_rule_audit_log` for dashboards showing rule hits, warnings, adapter usage frequency.

---

## 5. Evaluation & Recommendation Engine

### 5.1 Modes

The system supports **3 evaluation modes** to match different use cases:

| Mode | Name | Description | Use Case | Adapter Allowance | Tolerance |
|------|------|-------------|----------|-------------------|-----------|
| **1** | OEM Strict | Exact factory match, no adapters, zero tolerance | Warranty repairs, restoration projects, insurance claims | ❌ None | 0mm |
| **2** | Service-Compatible | Shop tolerances + vetted adapters, industry best practices | Day-to-day service desk, maintenance, standard upgrades | ✅ Approved only | ±3mm spacing, ±2mm chainline |
| **3** | Upgrade Explorer | Encourage conversions/upgrades, include labor & adapter costs, show alternatives | Upsell programs, budgeting, "what if" scenarios, custom builds | ✅ All available | ±5mm spacing, warn if >±3mm |

**Mode Selection Rules:**
- Warranty work → Mode 1 (customer invoice references warranty claim)
- Regular maintenance → Mode 2 (default for most jobs)
- Quote generation → Mode 3 (show customer upgrade paths)
- Custom builds → Mode 3 (exploratory, no bike baseline)

### 5.2 Compatibility Rule Structure

Each component type has a **rule set** defining how to evaluate compatibility. Rules include:

**Rule Types:**
- `exact` - Must be identical (spoke holes, BSD diameter)
- `tolerance` - Numeric range allowed (spacing ±3mm, chainline ±2mm)
- `enum_map` - Defined compatible enum pairs (axle types, freehub standards)
- `range_overlap` - Ranges must overlap (tire width vs rim width)
- `less_than_or_equal` - Product value ≤ bike value (cassette max teeth ≤ derailleur max teeth)
- `greater_than_or_equal` - Product value ≥ bike value (fork travel ≥ frame min)

**Example: Cassette Compatibility Rule**
```
IF bike.speeds == product.speeds (exact match, weight 5.0)
  AND bike.freehub_standard == product.freehub_standard (exact match, weight 4.0)
  AND product.max_teeth <= derailleur.max_teeth (less_than_or_equal, weight 4.5)
THEN compatible (score 13.5/13.5 = 100%)
ELSE incompatible or partial match
```

**Example: Hub Compatibility Rule (Mode 2 - With Adapter)**
```
Bike: Frame OLD 148mm (boost), thru-axle 12x148, 32-hole rims
Product: DT Swiss 350 rear hub (142mm, thru-12x142, 32-hole)

Rule Checks:
1. spoke_holes: 32 == 32 ✅ (exact match, weight 5.0)
2. spacing_mm: 142mm vs 148mm ⚠️ (off by 6mm, tolerance mode 2 = 3mm)
   → Check adapters: boost_142_to_148 available ✅
   → Partial match (weight 4.5 * 0.8 = 3.6)
3. axle_type: thru_12x142 compatible with thru_12x148 ✅ (enum_map, weight 4.0)

Result: COMPATIBLE WITH ADAPTER (score 12.6/13.5 = 93%)
Adapter: Boost spacing kit (6mm spacers + longer axle, $25, 15min labor)
```

### 5.3 Pipeline (Step-by-Step Execution Flow)

#### 5.3.1 Session Creation
```sql
-- Start evaluation session
SELECT * FROM compat_start_session(
  p_tenant_id := current_tenant_id,
  p_bike_id := 'uuid-bike-instance',
  p_customer_id := 'uuid-customer',
  p_context := jsonb_build_object(
    'job_id', 'uuid-mechanic-job',
    'technician_id', 'uuid-employee',
    'budget_max', 500000, -- CLP
    'discipline', 'mtb_trail',
    'purpose', 'wheel_rebuild'
  )
);
```

**Session Benefits:**
- Groups related evaluations (wheel rebuild = hub + rim + spokes together)
- Tracks budget across multiple component evaluations
- Maintains technician context for audit trail
- Enables re-evaluation (budget slider → re-run with new ceiling)

#### 5.3.2 Orchestrator (Main Evaluation Function)

```sql
-- Run compatibility evaluation
SELECT * FROM compat_run_evaluation(
  p_session_id := 'uuid-session',
  p_component_type_code := 'rear_hub',
  p_mode := 2, -- Service-Compatible
  p_target_budget := 150000, -- CLP (optional, filters results)
  p_bike_id := 'uuid-bike-instance' -- loads bike specs as baseline
);
```

**Execution Steps:**
1. Load bike baseline specs from `bike_compatibility_profile`
2. Load component type metadata + rules from `compat_component_library`
3. Query products WHERE `category.component_type_code = 'rear_hub'`
4. For each product:
   - Load `product.compatibility_attributes`
   - Apply rule set (attribute by attribute)
   - Calculate compatibility score (weighted sum)
   - Check adapter availability if partial match
   - Apply discipline filters (MTB product for MTB bike)
   - Check inventory (`stock_quantity > 0` preferred)
   - Calculate margin (sell price - cost)
5. Sort results by: Score DESC → Stock availability → Price ASC
6. Persist results in `compat_evaluation_items` table
7. Log all rule decisions in `compat_rule_audit_log`
8. Return `evaluation_id` + item count

**Performance Optimizations:**
- Use indexed queries on `product_categories.component_type_code`
- Cache bike specs in `bike_compatibility_profile` (trigger-maintained)
- Pre-filter by discipline before rule evaluation
- Limit to top 100 results per evaluation

#### 5.3.3 Recommendation Generator

```sql
-- Generate tiered recommendations (Good/Better/Best)
SELECT * FROM compat_generate_recommendation(
  p_evaluation_id := 'uuid-evaluation',
  p_quote_mode := 'tiered', -- 'tiered' or 'single_best'
  p_target_budget := 150000, -- CLP
  p_profit_margin_floor := 0.20 -- 20% minimum margin
);
```

**Tiering Logic:**
- **Good**: Highest-scoring option ≤ budget, minimum margin met
- **Better**: Mid-range price (~30% over Good), significant quality/feature upgrade
- **Best**: Top-scoring option regardless of budget, premium features

**Budget Handling:**
- If all options > budget: return cheapest + flag "needs_increase"
- If Good within budget: show Better as slight upsell, Best as aspirational
- If Better within budget: show Good as save-money option, Best as premium

### 5.4 Multi-Component Evaluations

**Scenario: Wheel Rebuild (Hub + Rim + Spokes + Nipples)**

```sql
-- Run evaluations for all components
SELECT compat_run_evaluation(session_id, 'rear_hub', 2, budget, bike_id);
SELECT compat_run_evaluation(session_id, 'rim', 2, budget, bike_id);
SELECT compat_run_evaluation(session_id, 'spoke', 2, budget, bike_id);
SELECT compat_run_evaluation(session_id, 'nipple', 2, budget, bike_id);

-- Cross-component validation
SELECT * FROM compat_validate_wheel_build(
  p_session_id := 'uuid-session',
  p_hub_product_id := 'uuid-hub',
  p_rim_product_id := 'uuid-rim'
);
```

**Cross-Component Checks:**
1. `hub.spoke_holes == rim.spoke_holes` (MUST match exactly)
2. Calculate spoke length: ERD + flange dimensions
3. Validate: `hub.spacing_mm` fits `frame.rear_hub_spacing_mm`
4. Validate: `rim.wheel_size == frame.wheel_size`
5. Validate: `hub.freehub_standard` compatible with current cassette
6. Calculate total cost: hub + rim + (spoke_count × spoke_price) + nipples + labor
7. Return: `compatible` (boolean), `spoke_length_mm`, `total_cost`, `warnings[]`

**Drivetrain Conversion Example (9-speed → 12-speed):**

```sql
-- Evaluate components together
SELECT compat_run_evaluation(session_id, 'cassette', 3, budget, bike_id); -- Mode 3 (upgrade)
SELECT compat_run_evaluation(session_id, 'rear_derailleur', 3, budget, bike_id);
SELECT compat_run_evaluation(session_id, 'shifter', 3, budget, bike_id);
SELECT compat_run_evaluation(session_id, 'chain', 3, budget, bike_id);

-- Cross-component validation
SELECT * FROM compat_validate_drivetrain_conversion(
  p_session_id := 'uuid-session',
  p_cassette_id := 'uuid',
  p_derailleur_id := 'uuid',
  p_shifter_id := 'uuid',
  p_chain_id := 'uuid'
);
```

**Drivetrain Checks:**
1. All components same speed count (12s)
2. `derailleur.max_teeth >= cassette.max_teeth`
3. Freehub compatible with cassette (may require freehub body swap)
4. `shifter.pull_ratio` matches `derailleur` brand
5. Chain standard matches cassette standard (HG+ vs Eagle)
6. Chainline compatible with frame (±2mm tolerance)
7. Return: `compatible` (boolean), `required_adapters[]`, `warnings[]`, `total_cost`

### 5.5 Budget & Profit Controls

**Budget Slider Workflow:**
```
1. User sets initial budget: $150,000 CLP
2. System runs evaluation, generates tiers
3. User sees: Good ($89k ✅), Better ($145k ✅), Best ($320k ❌ exceeds)
4. User adjusts slider to $200,000 CLP
5. System re-runs: compat_generate_recommendation(evaluation_id, 'tiered', 200000, 0.20)
6. New tiers: Good ($89k), Better ($145k), Best ($185k) ✅ now fits!
7. UI updates instantly (cached evaluation, just re-filters by new budget)
```

**Profit Margin Floor:**
- Shop sets minimum margin: 20% (configurable per tenant)
- System excludes products where `(price - cost) / price < 0.20`
- Exception: if NO products meet margin, show best available + warn "low margin"
- Use case: clearance items, warranty replacements (customer pays cost only)

### 5.6 Telemetry & Monitoring

**Audit Log Structure (`compat_rule_audit_log` table):**
```sql
create table compat_rule_audit_log (
  id uuid primary key,
  tenant_id uuid not null,
  evaluation_id uuid references compat_evaluations(id),
  product_id uuid references products(id),
  rule_name text, -- "spoke_holes_exact_match"
  attribute_key text, -- "spoke_holes"
  bike_value jsonb, -- {"spoke_holes": 32}
  product_value jsonb, -- {"spoke_holes": 32}
  match_result text, -- "pass", "fail", "partial_with_adapter"
  score_contribution numeric, -- 5.0 (weight of this rule)
  adapter_suggested jsonb, -- {"type": "boost_142_to_148", "cost": 15000}
  warning_message text,
  created_at timestamp default now()
);
```

**Dashboard Metrics:**
- **Evaluation Volume**: Count per day/week/month (track adoption)
- **Success Rate**: % of evaluations resulting in sale (conversion funnel)
- **Adapter Usage**: % of recommendations requiring adapters (target 20-30%)
- **Top Failure Reasons**: `GROUP BY rule_name WHERE match_result = 'fail'` (fix data gaps)
- **Revenue Per Mode**: `SUM(sale_value) GROUP BY mode` (1/2/3) - which mode drives sales?
- **Avg Evaluation Time**: Measure RPC execution time (target <2s)
- **Missing Metadata**: Count products lacking required `compatibility_attributes`

**Alert Triggers:**
- Evaluation failure rate >10% → check data quality
- Avg evaluation time >5s → index tuning needed
- Zero adapters used in 7 days → adapter catalog incomplete
- Missing metadata >5% → import validation failing

---

## 6. Workflow Integrations

### 6.1 Wheel Builder
- **UI**: multi-pane workspace (config selectors, suggestions list, adapter plan, history/logs).
- **Flow**: select bike/session → load spec → run evaluation for hubs/rims/spokes/nipples → allow overrides → commit plan.
- **Outputs**: wheel build record with `compatibility_session_id`, peg tasks, invoice/quote lines, purchase list entries (if parts missing), PDF summary for customer.

### 6.2 Smart Pegas
- Templates referencing component types + service packages (wheel rebuild, brake upgrade, drivetrain conversion).
- Wizard: choose bike + template → engine injects parts/adapters/labor → user confirms → creates `mechanic_jobs`, `job_tasks`, `job_items`, optional `sales_invoice` (quote).
- Peg detail view displays compatibility reasoning + adapter steps.

### 6.3 Quotes & Budgets
- Recommendation payload populates quote builder with Good/Better/Best tiers.
- Budget slider re-runs evaluation under new ceiling; show margin and availability per tier.
- Quote lines remain linked to evaluation items for traceability/re-run.

### 6.4 Inventory & Procurement
- When evaluation finds zero in-stock matches, create entries in `smart_purchase_list` referencing component type + spec filters + quantity needed.
- Procurement dashboard aggregates demand, suggests supplier PO lines, links back to originating session/job.
- Import process ensures supplier catalogs include compatibility attributes for accurate matching.

### 6.5 Customer Bikes & Portal
- Compatibility runs update `bike_compatibility_profile` plus recommended upgrades list.
- Customer portal (future) shows recommended upgrades with pricing, adapter plan, lead time.
- Provide PDF export for service desk.

### 6.6 Imports & Data Hygiene
- Zoho/CSV imports use DatabaseService wrappers (auto tenant_id) + spec validation before inserts.
- CLI audit surfaces products missing mandatory compatibility metadata; assign tasks to teams.

---

## 7. Flutter/Dart Implementation

### 7.1 Shared Services
- `CompatibilityService`: orchestrates RPC calls, caching, error handling, mode selection.
- `SpecSchemaProvider`: fetches component schema + discipline rules for forms and UI.
- `AdapterPlanner`: formats adapter JSON into human-readable steps and costing.
- `CompatibilitySessionStore`: local state for sessions, budgets, evaluation history.

### 7.2 UI Modules

1. **Product Form Advanced Specs** – schema-driven inputs, validation, context warnings.
2. **Wheel Builder Workspace** – reuses MainLayout split panes, resizable columns, advanced tables for line items.
3. **Bike Diagram UI** – interactive SVG/canvas with component hotspots and compatibility badges.
4. **Smart Pegas Wizard** – multi-step flow with compatibility results, adjustments, job creation.
5. **Quote/Budget Builder** – tiered recommendations, budget slider, margin view.
6. **Inventory Demand View** – filter by component type/standard, show pending evaluations generating demand.

#### 7.2.1 Product Form - Advanced Specs Tab

**Dynamic Field Generation:**
```dart
// In product_form_page.dart
Widget _buildCompatibilityFields() {
  if (selectedCategory?.componentTypeCode == null) {
    return Text('Select category with component type to enable compatibility fields');
  }
  
  // Call RPC to get metadata + attributes
  final metadata = await CompatibilityService.getComponentMetadata(
    selectedCategory!.componentTypeCode!
  );
  
  // Build dynamic fields from metadata.attributes
  return Column(
    children: metadata.attributes.map((attr) {
      switch (attr.type) {
        case 'enum':
          return DropdownButtonFormField(
            decoration: InputDecoration(labelText: attr.label),
            items: attr.enumValues.map((e) => DropdownMenuItem(...)),
            validator: attr.required ? (v) => v == null ? 'Required' : null : null,
          );
        case 'number':
          return TextFormField(
            decoration: InputDecoration(
              labelText: attr.label,
              suffixText: attr.units,
              helperText: '${attr.min} - ${attr.max} ${attr.units}',
            ),
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            validator: (v) => validateNumber(v, attr.min, attr.max, attr.required),
          );
        case 'text':
          return TextFormField(
            decoration: InputDecoration(labelText: attr.label),
            validator: attr.required ? (v) => v?.isEmpty ? 'Required' : null : null,
          );
        case 'boolean':
          return SwitchListTile(
            title: Text(attr.label),
            value: _compatAttributes[attr.key] ?? false,
            onChanged: (v) => setState(() => _compatAttributes[attr.key] = v),
          );
      }
    }).toList(),
  );
}

// Save to products.compatibility_attributes JSONB
await ProductService.save(product.copyWith(
  compatibilityAttributes: _compatAttributes, // Map<String, dynamic>
));
```

**UI Behavior:**
- Load schema when category changes
- Show/hide section based on `category.componentTypeCode != null`
- Group fields by category (Core, Drivetrain, Mounting, etc.)
- Inline validation (red border + error text)
- Tooltip icons with examples (e.g., "QR = Quick Release, Thru = Thru-Axle")

#### 7.2.2 Bike Diagram - Interactive Component Selection

**Architecture:**
```
bike_catalog.diagram_svg (text) stores:
- SVG path with clickable hotspots
- Component positions (x, y, width, height)
- Component type mapping

UI Rendering:
- Load SVG as InteractiveViewer (zoom/pan)
- Overlay clickable regions as Positioned widgets
- On tap: highlight component + open compatibility modal
```

**Diagram Structure:**
```json
{
  "svg_url": "https://storage.supabase.co/diagrams/trek_fuel_ex_8_2023.svg",
  "hotspots": [
    {
      "component_type": "fork",
      "label": "Horquilla",
      "x": 120, "y": 85, "width": 60, "height": 180,
      "current_product_id": "uuid-rockshox-pike"
    },
    {
      "component_type": "cassette",
      "label": "Cassette",
      "x": 520, "y": 280, "width": 45, "height": 45,
      "current_product_id": "uuid-sram-xg1275"
    },
    {
      "component_type": "rear_derailleur",
      "label": "Cambio",
      "x": 530, "y": 320, "width": 40, "height": 70,
      "current_product_id": "uuid-sram-gx-eagle"
    }
    // ... all components
  ]
}
```

**Interaction Flow:**
1. User taps "Cassette" hotspot
2. System highlights hotspot (green border)
3. Modal opens showing:
   - Current: SRAM XG-1275 (12s, 10-52t, XD freehub)
   - Compatible Upgrades: [list with scores]
   - Required Adapters: None
   - Budget Impact: $0 (same), +$45 (better), +$120 (best)
4. User selects upgrade → adds to cart/quote
5. Diagram updates: hotspot badge shows "🔄 Upgrade pending"

**Compatibility Badges:**
- ✅ Green checkmark = currently compatible
- ⚠️ Yellow warning = partial compatibility (adapter needed)
- ❌ Red X = incompatible (needs replacement)
- 🔄 Blue sync = upgrade pending in current quote

#### 7.2.3 Compatibility Modal - Component Selection

**Modal Layout:**
```
┌─────────────────────────────────────────┐
│ Compatible Cassettes for Trek Fuel EX 8 │
├─────────────────────────────────────────┤
│ Current: SRAM XG-1275 (12s, 10-52t, XD) │
│ Frame: 148mm boost, thru-12x148          │
│ Derailleur: GX Eagle (12s, max 52t)     │
├─────────────────────────────────────────┤
│ Budget: $150,000 CLP [────────●─] Max   │
├─────────────────────────────────────────┤
│ ✅ Perfect Match (Score 100%)            │
│   SRAM XG-1275 (current)        $145,000│
│   In Stock: 2  |  Margin: 28%           │
│                                          │
│ ✅ Perfect Match (Score 100%)            │
│   Shimano XT M8100 (11-51t)     $135,000│
│   Requires: XD→HG freehub swap ($45k)   │
│   In Stock: 1  |  Margin: 25%           │
│   [ Add to Quote ]                       │
│                                          │
│ ⚠️ Partial Match (Score 92%)             │
│   Sunrace MZ90 (11-50t)          $68,000│
│   Warning: Lower quality bearings        │
│   In Stock: 3  |  Margin: 32%           │
│   [ Add to Quote ]                       │
│                                          │
│ ⭐ Premium Upgrade (Score 98%)           │
│   SRAM XX1 Eagle (10-52t)       $320,000│
│   ❌ Exceeds budget by $170,000          │
│   Requires Order (7 days)               │
│   [ Add to Quote Anyway ]                │
└─────────────────────────────────────────┘
```

**Features:**
- Real-time budget slider (filters results as you drag)
- Color-coded scores (green ≥95%, yellow 85-94%, red <85%)
- Adapter cost breakdown (expand/collapse)
- Warning tooltips (hover over ⚠️)
- Stock availability badges (In Stock vs Order Required)
- Margin visibility for managers (hidden for cashiers)

### 7.3 UX Rules

**Desktop (>900px width):**
- Persistent navigation sidebar (resizable 200-400px)
- Split panes for list+detail views (invoice lines, product catalog)
- Skeleton loaders during RPC calls
- Asynchronous compatibility badges (load after page render)
- Hover states on list items (show reorder arrows, quick actions)

**Tablet/Mobile (<900px width):**
- Collapsible drawer navigation
- Stepper dialogs for multi-step flows (smart pega wizard)
- Cache schema data offline (IndexedDB/SharedPreferences)
- Highlight warnings with icons + text (no hover tooltips)
- Bottom sheets for component selection (not modals)

**Accessibility:**
- Keyboard navigation (Tab, Enter, Esc)
- Color-safe badges (not just color - also icons/text)
- Textual warnings (not just colored borders)
- Screen reader support (ARIA labels on interactive elements)
- Minimum touch target 48x48px (Material Design standard)

---

## 8. Operational Playbook

### 8.1 Deployment Workflow

**⚠️ CRITICAL: All compatibility engine work happens in `core_schema_compat.sql` first!**

**Development Cycle:**
1. ✅ **Edit** `supabase/sql/core_schema_compat.sql` (add tables, functions, triggers, seeds)
2. ✅ **Deploy** to staging Supabase project: https://supabase.com/dashboard/project/kyvgmapifacpzuyreasy/sql
   - Copy entire `core_schema_compat.sql` → Paste in SQL Editor → Run
3. ✅ **Seed** staging tenants: `SELECT public.seed_component_library();`
4. ✅ **Test** with Flutter app pointing to staging URL:
   - Run SQL queries in Supabase SQL Editor
   - Test Flutter UI forms (category dropdown, product form dynamic fields)
   - Verify RPC calls return expected data
5. ✅ **Validate** multi-tenant isolation:
   - Create test tenants
   - Verify data doesn't leak between tenants
   - Test RLS policies

**Production Promotion (LATER, after full validation):**
1. ⏳ **Merge** validated changes from `core_schema_compat.sql` into `core_schema.sql`
2. ⏳ **Review** all changes (diff between files)
3. ⏳ **Deploy** to production Supabase: https://supabase.com/dashboard/project/xzdvtzdqjeyqxnkqprtf/sql
4. ⏳ **Seed** production tenants
5. ⏳ **Monitor** telemetry dashboards + logs

**DO NOT touch `core_schema.sql` until compatibility engine is fully tested on staging!**

### 8.2 QA Strategy
- SQL unit tests (pgTAP/custom) for evaluation logic, adapter decisions, budgeting.
- Dart integration tests for RPC workflows, UI widget tests for forms/wizards.
- Golden datasets (canonical bikes + parts) to verify deterministic results.
- Load testing for concurrent evaluations (goal: 100+ simultaneous sessions).

### 8.3 Data Governance
- Nightly job verifying spec completeness by component type; send report or create tasks.
- Import validators block incomplete rows; provide CSV of issues.
- Schema versioning/migrations logged in repo; include upgrade scripts for tenants.

### 8.4 Monitoring & Analytics
- Dashboards for evaluation count, success rate, adapter usage, revenue per recommendation, labor booked.
- Alerts for spikes in missing metadata or RPC errors.
- Track ROI (margin per upgrade, labor revenue, inventory turnover improvements).

---

## 9. Phasing & Deliverables

| Phase | Focus | Deliverables | Target |
|-------|-------|-------------|--------|
| 0 (Done) | Foundation | Schema tables, RPC scaffolding, base seed, tenant hook | ✅ |
| 1 | Metadata Expansion | Full dictionary, schema enforcement, advanced spec UI, import validation | Dec 2025 |
| 2 | Evaluation Engine | Mode 1/2/3 runner, adapter planner, budgeting, telemetry dashboards | Jan 2026 |
| 3 | Workflow Integrations | Wheel builder, smart peg wizard, quote builder, customer bike sync | Feb–Mar 2026 |
| 4 | Inventory/Purchasing | Demand aggregation, supplier integrations, predictive stocking | Apr 2026 |
| 5 | Advanced Analytics & Portal | Customer-facing reports, AI upgrade suggestions, training simulator | May–Jun 2026 |

---

## 10. Risk Register

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Incomplete product specs | Evaluation failures | Enforce validation, nightly audits, task queues |
| Adapter rule inaccuracies | Wrong conversions | Curated catalog, human approval workflow, telemetry review |
| Performance bottlenecks | Slow UI/timeouts | Index tuning, caching, async evaluation queue |
| RLS misconfiguration | Tenant data leakage | Strict filters, tests, security reviews |
| Scope creep | Delays | Phase gating, clear DOD, design reviews |

---

## 11. Appendices & References

### 11.1 Glossary
- **Mode 1/2/3** – Strict / Service-compatible / Upgrade evaluation strategies.
- **Adapter Plan** – JSON describing conversion steps, parts, labor, warnings.
- **Smart Pegas** – Mechanic jobs auto-generated from compatibility output.
- **Good/Better/Best** – Tiered quote options respecting budgets.

### 11.2 Reference Assets

**Database:**
- ✅ **`supabase/sql/core_schema_compat.sql`** – **SQL SOURCE OF TRUTH** for compatibility engine (18,702 lines)
  - All compatibility tables, functions, triggers, seeds defined here
  - Deploy to staging project: `kyvgmapifacpzuyreasy`
  - Lines 2190-2393: Flexible compatibility system
- ⚠️ **`supabase/sql/core_schema.sql`** – **DO NOT EDIT** during compatibility development (17,303 lines)
  - Production master schema
  - Will be updated AFTER staging validation complete

**Documentation:**
- `.github/compatibilityEngine.md` – Conceptual spec + attribute descriptions
- `.github/compatibility_engine_master_plan.md` – **THIS DOCUMENT** (comprehensive blueprint)

**Flutter Code:**
- `lib/modules/inventory/pages/category_form_page.dart` – Component type dropdown (COMPLETE ✅)
- `lib/modules/inventory/pages/product_form_page.dart` – Dynamic compatibility fields (TODO ⏳)
- `lib/modules/wheel_builder/` – Wheel builder workspace (TODO ⏳)
- `lib/modules/maintenance/pages/mechanic_job_form_page.dart` – Smart pegas wizard (TODO ⏳)
- `lib/modules/sales/pages/quote_builder_page.dart` – Quote/budget builder (TODO ⏳)

**Import Scripts:**
- `scripts/` – Zoho, CSV import templates (ensure spec enforcement)

---

**Owner**: Compatibility Task Force (Claudio + Supabase + Flutter leads). Update this file after each major compatibility milestone so all teams (and AI copilots) stay aligned.
