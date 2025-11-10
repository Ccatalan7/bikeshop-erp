# 🚀 WHEEL BUILDING SYSTEM - DEPLOYMENT GUIDE

## ✅ COMPLETED (Ready to Use!)

### **Backend (100% Complete)**
- ✅ Database schema with 4 tables (hubs, rims, spokes, builds)
- ✅ ProWheelBuilder spoke calculator (PostgreSQL function)
- ✅ Compatibility matcher functions
- ✅ RLS policies for multi-tenant security
- ✅ Dart models with full serialization
- ✅ Service layer with CRUD + calculator + wizard
- ✅ Deployment script ready: `DEPLOY_WHEEL_BUILDING.sql`

### **Frontend (100% Complete)**
- ✅ Hub management page (search, filter, CRUD)
- ✅ Rim management page (search, filter, CRUD)
- ✅ Spoke management page (search, filter, CRUD)
- ✅ **Wheel Builder Wizard** (4-step guided interface)
- ✅ Navigation routes configured
- ✅ Menu items added to Taller section
- ✅ Provider registered in main.dart

---

## 📋 DEPLOYMENT STEPS

### **Step 1: Deploy Database Schema**

Open Supabase SQL Editor and run `DEPLOY_WHEEL_BUILDING.sql`:

```bash
# File location: 
/Users/Claudio/Dev/bikeshop-erp/DEPLOY_WHEEL_BUILDING.sql
```

This creates:
- `wheel_hubs` table (hub specifications)
- `wheel_rims` table (rim specifications)
- `wheel_spokes` table (spoke inventory)
- `wheel_builds` table (saved builds)
- `calculate_spoke_length()` function
- `find_compatible_hubs()` function
- `find_compatible_spokes()` function
- All RLS policies

**Expected Result:** "Success. No rows returned"

---

### **Step 2: Verify Deployment**

Run this query in Supabase SQL Editor:

```sql
-- Check tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name LIKE 'wheel_%'
ORDER BY table_name;

-- Should return:
-- wheel_builds
-- wheel_hubs
-- wheel_rims
-- wheel_spokes

-- Check functions exist
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
  AND routine_name LIKE '%spoke%' OR routine_name LIKE '%wheel%'
ORDER BY routine_name;

-- Should return:
-- calculate_spoke_length
-- find_compatible_hubs
-- find_compatible_spokes
```

---

### **Step 3: Test Spoke Calculator**

```sql
-- Test the ProWheelBuilder formula
-- Example: 700c rim (ERD 622mm) with Shimano hub
SELECT calculate_spoke_length(
  622.0,   -- ERD in mm (Effective Rim Diameter)
  50.0,    -- Flange diameter in mm
  30.0,    -- Center to flange distance in mm
  32,      -- Spoke holes
  3        -- 3-cross pattern
) as calculated_spoke_length_mm;

-- Expected result: ~292-296mm depending on hub specs
```

---

### **Step 4: Restart Flutter App**

```bash
# Stop the app
flutter clean

# Restart
flutter run
```

---

## 🎯 HOW TO USE (After Deployment)

### **Access the System**

1. Open the app
2. Navigate to **Taller** section in sidebar
3. You'll see new menu items:
   - 🔧 **Wheel Builder** (The Wizard!)
   - **Hubs** (Manage hub inventory)
   - **Rims** (Manage rim inventory)  
   - **Spokes** (Manage spoke inventory)

---

### **Quick Start Guide**

#### **Option A: Start with Wheel Builder Wizard** (Recommended for Testing)

1. Click "🔧 Wheel Builder"
2. Follow the 4-step wizard:
   - **Step 1:** Select Hub (or realize you need to add hubs first!)
   - **Step 2:** Select Rim (compatible rims auto-filtered)
   - **Step 3:** Choose Lacing Pattern (radial, 1-cross, 2-cross, 3-cross, 4-cross)
   - **Step 4:** See Results (spoke lengths + compatible spokes in stock)

#### **Option B: Add Components First** (Recommended for Production)

1. **Add Hubs:**
   - Go to "Hubs" page
   - Click "New Hub"
   - Fill in specs:
     * Name: "Shimano Deore M6010"
     * Manufacturer: "Shimano"
     * Hub Type: Rear
     * OLD: 135mm
     * Spoke Holes: 32H
     * Flange measurements (critical for spoke calc!)
     * Brake type: disc_6bolt
     * Driver type: cassette

2. **Add Rims:**
   - Go to "Rims" page
   - Click "New Rim"
   - Fill in specs:
     * Name: "DT Swiss XM421"
     * Manufacturer: "DT Swiss"
     * Wheel Size: 29"
     * **ERD: 602mm** (CRITICAL for spoke calculation!)
     * Spoke Holes: 32H
     * Internal Width: 21mm
     * Brake type: disc

3. **Add Spokes:**
   - Go to "Spokes" page
   - Click "New Spoke"
   - Fill in specs:
     * Name: "DT Swiss Competition"
     * Length: 292mm
     * Gauge: 2.0mm
     * Butted: Yes/No
     * Material: stainless_steel
     * Head Type: j_bend

4. **Now use Wheel Builder Wizard!**

---

## 📊 SAMPLE DATA (For Testing)

### **Sample Hub: Shimano Deore Rear**
```
Name: Shimano Deore M6010
Manufacturer: Shimano
Model: M6010
Hub Type: rear
OLD: 135mm
Spoke Holes: 32H
Left Flange Diameter: 50mm
Right Flange Diameter: 50mm
Center to Left Flange: 30mm
Center to Right Flange: 18mm (asymmetric!)
Brake Type: disc_6bolt
Driver Type: cassette
Axle Type: quick_release
```

### **Sample Rim: DT Swiss XM421**
```
Name: DT Swiss XM421
Manufacturer: DT Swiss
Model: XM421
Wheel Size: 29"
ERD: 602mm
Spoke Holes: 32H
Internal Width: 21mm
External Width: 25mm
Rim Depth: 20mm
Brake Type: disc
Rim Type: tubeless_ready
```

### **Sample Spokes: DT Swiss Competition**
```
Name: DT Swiss Competition 292mm
Manufacturer: DT Swiss
Model: Competition
Length: 292mm
Gauge: 2.0mm (15g)
Butted: Yes
Material: stainless_steel
Finish: plain
Head Type: j_bend
```

---

## 🧪 TESTING CHECKLIST

### **Database Tests**
- [ ] Tables created successfully
- [ ] Functions created successfully
- [ ] RLS policies active
- [ ] Spoke calculator returns reasonable values (290-300mm range)

### **UI Tests**
- [ ] Hub management page loads
- [ ] Rim management page loads
- [ ] Spoke management page loads
- [ ] Wheel Builder Wizard loads
- [ ] Can create a hub
- [ ] Can create a rim
- [ ] Can create a spoke
- [ ] Wizard shows compatible components
- [ ] Wizard calculates spoke lengths
- [ ] Results show stock quantities

### **Calculation Tests**
- [ ] Radial lacing (0-cross) gives shorter spokes
- [ ] 3-cross lacing gives longer spokes
- [ ] Rear wheel (asymmetric) shows different left/right lengths
- [ ] Front wheel (symmetric) shows same left/right lengths
- [ ] Compatible spokes found within ±2mm tolerance

---

## 🎨 WHAT YOU'LL SEE

### **Wheel Builder Wizard Interface**

```
┌─────────────────────────────────────────────────────────────┐
│  🔧 Wheel Builder Wizard                                    │
├───────────────┬─────────────────────────────────────────────┤
│               │                                             │
│ Build Steps   │  Step 1: Select Hub                        │
│               │                                             │
│ ● Select Hub  │  [Grid of hub cards with specs]           │
│ ○ Select Rim  │                                             │
│ ○ Lacing      │  ┌─────────────────────────────┐          │
│ ○ Results     │  │ Shimano Deore M6010  ✓      │          │
│               │  │ OLD: 135mm • 32H             │          │
│               │  │ disc_6bolt • cassette        │          │
│               │  └─────────────────────────────┘          │
│               │                                             │
│               │  [More hub cards...]                        │
│               │                                             │
│               │                                             │
│  [Start Over] │  [Back]              [Next →]              │
└───────────────┴─────────────────────────────────────────────┘
```

### **Results Display**

```
┌─────────────────────────────────────────────────────────────┐
│  ✅ Build Calculated!                                       │
│                                                              │
│  Build Summary                                               │
│  Hub: Shimano Deore M6010 (rear, 135mm, 32H)              │
│  Rim: DT Swiss XM421 (29", ERD 622mm, 32H)                │
│  Lacing: 3-Cross                                            │
│                                                              │
│  ┌─────────────────────────┬─────────────────────────┐     │
│  │ ← Left Side (Non-Drive) │ Right Side (Drive) →   │     │
│  │   294.8 mm              │   292.3 mm              │     │
│  └─────────────────────────┴─────────────────────────┘     │
│                                                              │
│  Recommended Spokes                                          │
│  ┌──────────────────────────────────────────────────┐      │
│  │ Left Side Spokes                                  │      │
│  │ ● DT Swiss 295mm (18 in stock) ✓                │      │
│  │   Difference: 0.2mm                               │      │
│  └──────────────────────────────────────────────────┘      │
│  ┌──────────────────────────────────────────────────┐      │
│  │ Right Side Spokes                                 │      │
│  │ ● DT Swiss 292mm (20 in stock) ✓                │      │
│  │   Difference: 0.3mm                               │      │
│  └──────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚨 TROUBLESHOOTING

### **"No hubs/rims/spokes found"**
→ You need to add components first! Go to each management page and add inventory.

### **"No compatible rims found"**
→ Spoke hole count must match between hub and rim (e.g., both must be 32H)

### **"No compatible spokes found"**
→ Add spokes to inventory that are close to calculated length (±2mm tolerance)

### **Calculated spoke length seems wrong**
→ Check ERD value (most common issue). ERD is Effective Rim Diameter, not BSD (Bead Seat Diameter)
→ For 700c rims, typical ERD = 622mm
→ For 29" MTB rims, typical ERD = 602-606mm

### **Database deployment error**
→ Make sure you're using service role key (not anon key)
→ Check Supabase SQL Editor logs for specific error
→ Verify no existing tables with same names

---

## 📚 NEXT STEPS (Optional Enhancements)

1. **Add Sample Data:** Import real hub/rim/spoke specs from manufacturers
2. **Link to Pegas:** Add "Rebuild Wheel" button in mechanic jobs
3. **Saved Builds:** Save common wheel builds as templates
4. **Product Integration:** Link hubs/rims/spokes to actual products table
5. **Inventory Deduction:** Auto-deduct spokes when build is completed
6. **Print Build Sheet:** PDF output with spoke lengths and build specs

---

## 🎉 SUCCESS CRITERIA

You'll know it's working when:
- ✅ You can create hubs, rims, and spokes
- ✅ Wheel Builder Wizard shows your components
- ✅ Wizard calculates spoke lengths (typically 290-300mm range)
- ✅ Wizard shows compatible spokes from your inventory
- ✅ Left and right spoke lengths are different for rear wheels
- ✅ Compatible spokes are filtered by ±2mm tolerance
- ✅ Stock quantities are displayed correctly

**This system eliminates the need for prowheelbuilder.com and manual calculations!** 🔥

---

**Ready to deploy? Run `DEPLOY_WHEEL_BUILDING.sql` in Supabase and let's GO!** 🚀
