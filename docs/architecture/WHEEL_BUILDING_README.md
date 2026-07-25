# 🔧 Professional Wheel Building System - DEMO

## 🎯 What This Does

This is a **professional spoke length calculator** and wheel building management system that solves the real-world problem mechanics face when rebuilding wheels.

### **The Problem (Manual Way):**
1. ❌ Customer brings bike with broken wheel
2. ❌ Mechanic measures OLD manually (dropout width)
3. ❌ Counts spoke holes manually
4. ❌ Checks brake type visually  
5. ❌ Checks freewheel vs cassette
6. ❌ Goes to prowheelbuilder.com
7. ❌ Inputs all measurements
8. ❌ Gets spoke length
9. ❌ Searches inventory hoping something matches

### **The Solution (Smart Way):**
1. ✅ Open bike record → System knows OLD, spoke count, brake type
2. ✅ Select hub from inventory
3. ✅ Select rim
4. ✅ **System calculates spoke length automatically** (prowheelbuilder algorithm!)
5. ✅ Shows compatible spokes in stock: "DT Swiss 292mm (24 available)"
6. ✅ Click "Add to Pega" → Done!

---

## 🚀 What's Been Built

### **Database Tables (4 tables)**
- `wheel_hubs` - Hub technical specs (OLD, flange measurements, spoke holes)
- `wheel_rims` - Rim specs (ERD, spoke holes, wheel size)
- `wheel_spokes` - Spoke inventory (length, gauge, material)
- `wheel_builds` - Saved wheel build configurations

### **Spoke Calculator (ProWheelBuilder Algorithm)**
```dart
// Implements the actual formula: L = √(R² + H² + D² - 2*R*H*cos(α))
double calculateSpokeLength({
  required double erdMm,              // Rim diameter
  required double flangeDiameterMm,   // Hub flange size
  required double centerToFlangeMm,   // Hub offset
  required int spokeHoles,            // 24, 28, 32, 36
  required int crossPattern,          // 0=radial, 1-4=cross
})
```

### **Compatibility Engine**
- `findCompatibleHubs()` - Matches hubs to rims based on spoke holes, brake type, OLD
- `findCompatibleSpokes()` - Finds spokes in inventory within ±2mm tolerance
- `calculateWheelBuild()` - Complete wizard: hub + rim → spoke recommendations

### **Smart Features**
- ✅ Asymmetric hub support (different left/right spoke lengths for rear wheels)
- ✅ Multiple lacing patterns (radial, 1-cross, 2-cross, 3-cross, 4-cross)
- ✅ Inventory integration (shows stock quantity)
- ✅ Saved builds (reusable templates for common wheels)
- ✅ Multi-tenant safe (each bike shop has their own data)

---

## 📊 Database Schema Highlights

### **wheel_hubs**
```sql
create table wheel_hubs (
  old_mm numeric(5,1) not null,                -- 130, 135, 142, 148mm
  spoke_holes integer,                          -- 24, 28, 32, 36, 40
  left_flange_diameter_mm numeric(5,2),        -- For spoke calc
  right_flange_diameter_mm numeric(5,2),       -- For spoke calc
  center_to_left_flange_mm numeric(5,2),       -- Hub offset left
  center_to_right_flange_mm numeric(5,2),      -- Hub offset right
  brake_type text,                              -- rim, disc_6bolt, disc_centerlock
  driver_type text,                             -- freewheel, cassette, fixed
  axle_type text                                -- quick_release, thru_axle
);
```

### **wheel_rims**
```sql
create table wheel_rims (
  erd_mm numeric(5,2) not null,      -- ⚠️ CRITICAL for spoke calculation!
  spoke_holes integer,                -- Must match hub
  internal_width_mm numeric(4,1),    -- Tire compatibility
  wheel_size text,                    -- '26"', '27.5"', '29"', '700c'
  brake_type text,                    -- Must match hub
  rim_type text                       -- clincher, tubular, tubeless_ready
);
```

### **wheel_spokes**
```sql
create table wheel_spokes (
  length_mm integer not null,        -- 290, 292, 294, 296...
  gauge numeric(3,2),                 -- 2.0, 1.8, 2.0-1.8 (butted)
  head_type text,                     -- j_bend, straight_pull
  product_id uuid                     -- Links to inventory!
);
```

---

## 🔬 Algorithm Explained

### **ProWheelBuilder Formula**

The spoke length calculation uses this formula:

```
L = √(R² + H² + D² - 2*R*H*cos(α))

Where:
  L = Spoke length
  R = Rim radius (ERD ÷ 2)
  H = Flange radius (Flange Diameter ÷ 2)
  D = Distance from wheel center to flange
  α = Spoke angle based on lacing pattern

Spoke angle α = (2π × crossings) ÷ spoke_holes

Example for 3-cross on 32H wheel:
α = (2 × 3.14159 × 3) ÷ 32 = 0.589 radians
```

### **Why This Matters**

**Rear wheels are asymmetric!**
- Drive side (right): Shorter spoke (cassette pushes flange outward)
- Non-drive side (left): Longer spoke
- Same wheel needs TWO different spoke lengths!

---

## 🎮 How to Use (When UI is Built)

### **Scenario: Customer needs rear wheel rebuild**

1. **Select Bike**
   - App shows: Trek Marlin 5, OLD: 135mm, 32H, Disc, Cassette

2. **Pick Hub**
   - Filter shows only compatible 135mm, 32H, disc hubs
   - Select: Shimano Deore M6010

3. **Pick Rim**
   - Filter shows 32H rims
   - Select: DT Swiss XM421, ERD: 602mm

4. **Choose Lacing**
   - Select: 3-cross (standard MTB)

5. **System Calculates**
   ```
   ✅ Drive side spoke: 292.3mm
   ✅ Non-drive side spoke: 294.8mm
   
   📦 In Stock:
   Drive: DT Swiss 292mm (20 available) - ±0.3mm ✅
   Non-drive: DT Swiss 295mm (18 available) - ±0.2mm ✅
   ```

6. **Save Build**
   - Saved as "Trek Marlin Rear 29er" template
   - Next time = instant lookup!

---

## 📈 Next Steps (UI Development)

### **Phase 1: Management Pages** (Next Session)
- Hubs management page (CRUD for wheel_hubs)
- Rims management page (CRUD for wheel_rims)
- Spokes management page (CRUD for wheel_spokes)

### **Phase 2: Wheel Builder Wizard** (Priority!)
```
┌─────────────────────────────────────┐
│  🔧 Wheel Builder Wizard            │
├─────────────────────────────────────┤
│  Step 1: Select Hub                 │
│  [Shimano Deore M6010 ▼]           │
│    OLD: 135mm | 32H | Disc          │
│                                     │
│  Step 2: Select Rim                 │
│  [DT Swiss XM421 ▼]                │
│    ERD: 602mm | 32H | 29"           │
│                                     │
│  Step 3: Lacing Pattern             │
│  ○ Radial  ○ 2-Cross  ● 3-Cross    │
│                                     │
│  ────────────────────────────────  │
│  📐 Calculated Spoke Lengths:      │
│    Drive side: 292.3mm             │
│    Non-drive: 294.8mm              │
│                                     │
│  📦 Recommended Spokes:            │
│    ✅ DT Swiss 292mm (20 in stock) │
│    ✅ DT Swiss 295mm (18 in stock) │
│                                     │
│  [Cancel] [💾 Save Build]          │
└─────────────────────────────────────┘
```

### **Phase 3: Integration with Pegas**
- "Rebuild Wheel" button on mechanic job
- Auto-populates with bike specs
- Auto-adds parts to job inventory
- Deducts spokes from inventory

---

## 🧪 Testing the Calculator

### **Test Case 1: Road Wheel (Symmetric)**
```dart
// Campagnolo Record hub + Mavic Open Pro rim
final length = service.calculateSpokeLength(
  erdMm: 622.0,              // Mavic Open Pro ERD
  flangeDiameterMm: 58.0,    // Campagnolo flange
  centerToFlangeMm: 35.0,    // Symmetric hub
  spokeHoles: 32,
  crossPattern: 3,
);

// Expected: ~290mm (radial) to ~296mm (3-cross)
```

### **Test Case 2: MTB Wheel (Asymmetric)**
```dart
// Shimano Deore hub (asymmetric rear) + DT Swiss rim
final lengths = service.calculateAsymmetricSpokeLength(
  erdMm: 602.0,                      // DT Swiss XM421 ERD
  leftFlangeDiameterMm: 50.0,        // Non-drive side
  rightFlangeDiameterMm: 50.0,       // Drive side
  centerToLeftFlangeMm: 30.0,        // Offset left
  centerToRightFlangeMm: 18.0,       // Offset right (cassette side)
  spokeHoles: 32,
  crossPattern: 3,
);

// Expected: left > right (by ~2-3mm)
```

---

## 💾 Deployment

Treat `supabase/sql/DEPLOY_WHEEL_BUILDING.sql` as historical source material.
For any current deployment, first produce a unique idempotent forward migration,
mirror it in `supabase/sql/core_schema.sql`, and follow
`docs/development/SUPABASE_WORKFLOW.md` through production-derived validation,
guarded deployment, and exact read-back. Do not paste this file into the SQL
Editor. The intended objects are:
- 4 tables (hubs, rims, spokes, builds)
- 3 functions (calculator, hub matcher, spoke finder)
- All RLS policies
- All indexes

---

## 🎯 Success Criteria

✅ **Backend Complete:**
- [x] Database tables with proper relationships
- [x] Spoke length calculator function (ProWheelBuilder algorithm)
- [x] Compatibility matcher functions
- [x] Dart models for all entities
- [x] Service layer with CRUD + calculator
- [x] Multi-tenant safe (RLS policies)

🔄 **UI Pending:**
- [ ] Hub/Rim/Spoke management pages
- [ ] Wheel builder wizard
- [ ] Integration with Pegas module
- [ ] Saved builds/templates page

---

## 🚴‍♂️ Why This is AWESOME

1. **Solves Real Problem**: No more manual measurements + prowheelbuilder.com lookup
2. **Professional Algorithm**: Same math as industry-standard tools
3. **Inventory Integration**: Shows what you have in stock
4. **Time Savings**: 10 minutes → 30 seconds
5. **Accuracy**: No human calculation errors
6. **Reusable**: Save builds as templates
7. **Multi-Tenant**: Each shop has their own data

**This is the kind of feature that makes your ERP system INVALUABLE to mechanics!** 🔥

---

## 📚 References

- ProWheelBuilder spoke calculator formula
- Sheldon Brown wheel building guide
- Shimano technical documentation
- DT Swiss hub specifications

---

**Ready to build the UI and make this REAL!** 🚀
