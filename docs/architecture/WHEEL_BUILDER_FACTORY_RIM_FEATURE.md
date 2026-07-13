# Wheel Builder: Factory Rim Pre-Selection Feature

**Date:** November 9, 2025  
**Status:** ✅ IMPLEMENTED - Ready for Testing  
**Module:** Pegas (Bikeshop) → Wheel Builder Wizard

---

## 📋 Feature Summary

When user selects **"Replace Hub Only"** build type, the wizard now pre-selects the bike's **exact factory rim** instead of a random matching rim. This ensures accurate spoke length calculations since different rims with same specs have different ERDs (Effective Rim Diameter).

**Critical Issue Solved:**  
- DT Swiss XM421 29" 32H: ERD = 602mm
- Stan's NoTubes Arch MK4 29" 32H: ERD = 605mm
- **3mm difference = WRONG spoke length!**

---

## ✅ What Was Completed

### 1. Database Schema (Deployed ✅)
**File:** `supabase/sql/core_schema.sql` (lines 752-755)

```sql
-- Added to bikes table
factory_rim_id uuid references wheel_rims(id) on delete set null,
```

**Migration Script:** `DEPLOY_factory_rim.sql` (already deployed to Supabase)

**Additional Schema Updates:**
- `bikes.front_hub_spacing_mm` - 100mm (standard), 110mm (Boost)
- `bikes.rear_hub_spacing_mm` - 130mm, 135mm, 142mm, 148mm (Boost)
- `bikes.spoke_count` - 24, 28, 32, 36, 40

---

### 2. Flutter Model Updates (Complete ✅)
**File:** `lib/modules/bikeshop/models/bikeshop_models.dart`

- Added `String? factoryRimId` field to `Bike` class
- Updated `fromJson()` to parse factory_rim_id
- Updated `toJson()` to serialize factory_rim_id
- Updated `copyWith()` to support factory_rim_id

---

### 3. Wizard Logic (Implemented ✅)
**File:** `lib/modules/bikeshop/pages/wheel_builder_wizard_page.dart`

#### Hub Filtering (Lines 128-149)
- Filters hubs by **EXACT OLD measurement** (148mm vs 142mm)
- No longer shows incompatible hubs for a bike

```dart
List<WheelHub> get _filteredHubs {
  return _allHubs.where((h) {
    bool matchesPosition = h.position == _hubPosition;
    bool matchesSpokeCount = h.spokeHoles == _spokeCount;
    bool matchesOLD = (h.position == 'front' && h.old == _frontHubSpacing) ||
                      (h.position == 'rear' && h.old == _rearHubSpacing);
    return matchesPosition && matchesSpokeCount && matchesOLD;
  }).toList();
}
```

#### Rim Filtering (Lines 116-126)
- **ALWAYS** filters by wheel size AND spoke count
- Previously showed all rims for "Replace Hub Only" (bug)

```dart
List<WheelRim> get _filteredRims {
  return _allRims.where((r) {
    bool matchesSize = _wheelSize == null || r.wheelSize == _wheelSize;
    bool matchesSpokes = r.spokeHoles == _spokeCount;
    return matchesSize && matchesSpokes;  // ALWAYS filter
  }).toList();
}
```

#### Factory Rim Auto-Selection (Lines 186-203)
```dart
if (_currentStep == 1 && _buildType == BuildType.replaceHub && _selectedRim == null) {
  if (_selectedBike?.factoryRimId != null) {
    _selectedRim = _allRims.firstWhere(
      (r) => r.id == _selectedBike!.factoryRimId,
      orElse: () => _filteredRims.first,
    );
    debugPrint('🎯 Auto-selected FACTORY rim: ${_selectedRim?.name}');
  } else {
    _selectedRim = _filteredRims.first;
    debugPrint('⚠️ No factory rim defined, using first match');
  }
}
```

---

### 4. Seed Data (Complete ✅)
**File:** `lib/scripts/seed_bikes_and_wheels.dart`

**New Structure (CRITICAL ORDER):**
1. **Step 2:** Insert RIMS first (lines 79-138) → Capture rim IDs
2. **Step 3:** Insert BIKES with factory_rim_id links (lines 145-188)
3. **Step 4:** Insert HUBS (lines 267-517)
4. **Step 5:** Insert SPOKES (lines 524-761)

**Bike-Rim Links:**
```dart
final bikesData = [
  {
    'brand': 'Trek',
    'model': 'X-Caliber 8',
    'spoke_count': 32,
    'front_hub_spacing_mm': 110.0,  // Boost
    'rear_hub_spacing_mm': 148.0,   // Boost
    'factory_rim_id': dtSwissXM421Id,  // ERD 602mm
  },
  {
    'brand': 'Specialized',
    'model': 'Rockhopper Comp 29',
    'spoke_count': 32,
    'front_hub_spacing_mm': 100.0,
    'rear_hub_spacing_mm': 142.0,
    'factory_rim_id': stansArchId,  // ERD 605mm
  },
];
```

---

## 🧪 Testing Steps

1. **Login to app** (Chrome: `flutter run -d chrome`)
2. **Navigate:** Pegas → Wheel Builder Wizard
3. **Seed Database:** Click "Seed Test Data" button
4. **Test Flow:**
   - Select: **Trek X-Caliber 8**
   - Build Type: **Replace Hub Only**
   - Select: Any 32H rear hub (e.g., DT Swiss 350)
   - Click: **Next**
   - **Expected:** DT Swiss XM421 29" 32H pre-selected
   - **Console:** `🎯 Auto-selected FACTORY rim: DT Swiss XM421...`
5. **Test Different Bike:**
   - Select: **Specialized Rockhopper Comp 29**
   - Same flow → Should pre-select **Stan's Arch MK4** (ERD 605mm)

---

## ⏳ What's Left To Do

### 1. Test Factory Rim Feature (HIGH PRIORITY)
- [ ] Run wizard with Trek X-Caliber → Verify DT Swiss rim selected
- [ ] Run wizard with Specialized → Verify Stan's Arch selected
- [ ] Verify spoke length calculations use correct ERD
- [ ] Test with bike that has NO factory_rim_id → Should fallback gracefully

### 2. Add More Bikes with Factory Rims (MEDIUM)
- [ ] Add 8 more bikes to seed script (currently only 2 have factory_rim_id)
- [ ] Link each bike to appropriate rim from seed data
- [ ] Ensure diverse spoke counts (28H, 32H, 36H)

### 3. UI Indicator (LOW)
- [ ] Show "Factory Rim" badge/icon next to pre-selected rim
- [ ] Add tooltip: "This is the original rim that came with your bike"

---

## 🚀 Recommended Enhancements

### Phase 1: Data Quality
1. **Import Real Bike Database**
   - Scrape manufacturer websites for factory specs
   - CSV import: Brand, Model, Year, Wheel Size, Hub Spacing, Spoke Count, Factory Rim
   - Target: 50+ common bikes

2. **Rim Database Expansion**
   - Add 20+ more rims (current: 12 rims)
   - Include budget options (Alexrims, WTB entry-level)
   - Include premium carbon (Enve, Reynolds, Zipp)

3. **Hub Database Expansion**
   - Add J-bend vs straight-pull distinction
   - Add hub engagement info (3-pawl, 6-pawl, star ratchet)
   - Add weight specifications

---

### Phase 2: Smart Features
1. **"Similar Rim" Suggestions**
   - If factory rim not available, suggest alternatives with same ERD ±2mm
   - Show ERD difference warning: "⚠️ ERD differs by 3mm, spoke length may vary"

2. **Price Calculator**
   - Add `price` field to hubs, rims, spokes
   - Show total build cost in wizard summary
   - Compare "Factory Rebuild" vs "Upgrade Build" cost

3. **Spoke Length Verification**
   - After calculation, show: "Recommended: 292mm, Available: 290mm, 292mm, 294mm"
   - Highlight available lengths in green
   - Warn if no exact match available

---

### Phase 3: Advanced Wizard
1. **"Replace Rim Only" Build Type**
   - Keep original hub, select new rim
   - Pre-populate hub specs from bike

2. **"Full Custom Build" Mode**
   - No bike selection
   - Manual entry: ERD, OLD, spoke count, hub flange dimensions
   - For custom/exotic builds

3. **Build History & Templates**
   - Save completed builds: "Trek X-Caliber - DT Swiss 350 + XM421"
   - Quick-rebuild: Select saved build, auto-populate all fields
   - Export build sheet as PDF for workshop

4. **Multi-Wheel Builder**
   - Build front + rear wheels simultaneously
   - Track left/right side spoke lengths
   - Generate parts list for both wheels

---

### Phase 4: Integration
1. **Link to Inventory Module**
   - Check if spokes in stock before recommending
   - Show "In Stock: 12 pcs" vs "Order Required"
   - Auto-add build to shopping cart

2. **Link to Pegas (Mechanic Jobs)**
   - "Create Wheel Build" button in pega form
   - Auto-add wheel build to parts list
   - Track wheel build status (ordered, built, installed)

3. **Customer Portal**
   - Customer enters bike model → See suggested upgrades
   - "My Bike" profile with factory specs
   - "Build Your Wheel" public wizard (no login required)

---

## 🐛 Known Issues

### Critical (Block Feature)
- None currently

### Major (Affects UX)
- None currently

### Minor (Polish)
1. **Dropdown width inconsistency**
   - Product autocomplete: 300px min
   - Bike dropdown: Uses field width (can be narrow)
   - **Fix:** Set minWidth: 350px for bike dropdown

2. **No loading state during seed**
   - User clicks "Seed Test Data" → No feedback until complete
   - **Fix:** Show CircularProgressIndicator during seeding

---

## 📝 Code Quality Notes

### What Works Well ✅
- **CompositedTransformFollower** for dropdown positioning (follows on scroll)
- **200ms delay** before closing overlay (prevents tap loss)
- **InkWell** wrapping ListTile (more reliable than onTap)
- **StatefulBuilder** for per-row hover state (efficient rebuilds)

### What Needs Refactoring 🔄
1. **Duplicate filtering logic**
   - `_filteredHubs` and `_filteredRims` use similar patterns
   - **Refactor:** Extract generic `filterBySpecs<T>()` helper

2. **Magic numbers**
   - Spoke lengths: 290, 292, 294, 296 hardcoded
   - **Refactor:** Extract to constants with comments

3. **Seed script size**
   - 761 lines (too large for single file)
   - **Refactor:** Split into: `seed_bikes.dart`, `seed_rims.dart`, `seed_hubs.dart`, `seed_spokes.dart`

---

## 🔗 Related Files

**Database:**
- `supabase/sql/core_schema.sql` (lines 752-755, 963-1010)
- `DEPLOY_factory_rim.sql` (migration script)

**Flutter:**
- `lib/modules/bikeshop/models/bikeshop_models.dart` (Bike model)
- `lib/modules/bikeshop/pages/wheel_builder_wizard_page.dart` (wizard logic)
- `lib/scripts/seed_bikes_and_wheels.dart` (seed data)

**Documentation:**
- `.github/GUI_DESIGN_PRINCIPLES.md` (dropdown/overlay patterns)
- `.github/copilot-instructions.md` (project guidelines)

---

## 💡 Tips for Next Agent

1. **Multi-tenant is CRITICAL:** Every table needs `tenant_id`, every query needs `.eq('tenant_id', tenantId)`
2. **Use DatabaseService:** Auto-injects tenant_id for inserts (don't use Supabase client directly)
3. **Spoke count MUST match:** Can't lace 32H hub to 28H rim (constraint in business logic)
4. **ERD precision matters:** 2-3mm difference = different spoke length (critical for feature)
5. **Seed order matters:** RIMS first (get IDs) → BIKES (link to rims) → HUBS → SPOKES
6. **Test with multiple tenants:** Verify data isolation (Trek for Tenant A shouldn't show for Tenant B)

---

**Feature Ready for Production Testing! 🎉**
