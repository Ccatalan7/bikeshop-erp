# 🔧 FLEXIBLE COMPATIBILITY SYSTEM - Implementation Guide

**Status:** ✅ Database schema updated, ready for Flutter integration  
**Date:** November 22, 2025

---

## 🎯 GOAL

Allow users to **manually map** their existing product categories to a **predefined catalog of component types** that define compatibility metadata fields. This system is:

- ✅ **Flexible**: Add/modify component types without schema changes
- ✅ **Simple**: User maps categories via dropdown (no scripts needed)
- ✅ **Open to change**: JSON-based metadata allows easy expansion
- ✅ **Tenant-safe**: Global catalog, per-tenant mappings

---

## 🏗️ ARCHITECTURE

### 1. **Global Component Library** (`compat_component_library`)
- **Purpose**: Centralized catalog of component types (like a template library)
- **Scope**: GLOBAL (no `tenant_id` - shared across all shops)
- **Structure**:
  - `code` (PK): Unique identifier (e.g., `'hub'`, `'frame'`, `'cassette'`)
  - `display_name`: User-friendly name (e.g., "Maza", "Cuadro")
  - `parent_code`: Hierarchical grouping (optional)
  - `discipline_scope`: Bike types (e.g., `['road', 'mtb', 'gravel']`)
  - `metadata` (JSONB): Attribute definitions, validation rules, UI hints
  - `icon_name`: Material Icon for Flutter UI

### 2. **Category Mapping** (`product_categories.component_type_code`)
- **Purpose**: Link user's categories to component types
- **Type**: Simple foreign key (nullable)
- **Example**:
  - Category: "Mazas Traseras" → `component_type_code = 'hub'`
  - Category: "Cuadros MTB" → `component_type_code = 'frame'`
  - Category: "Accesorios" → `component_type_code = NULL` (no compatibility)

### 3. **Flutter Integration**
- **Category Form**: Dropdown to select component type (or "None")
- **Product Form**: Reads `component_type_code` → fetches metadata → builds dynamic fields

---

## 📊 DATABASE CHANGES

### New Table: `compat_component_library`
```sql
create table compat_component_library (
  code text primary key,
  display_name text not null,
  parent_code text references compat_component_library(code),
  discipline_scope text[],
  description text,
  icon_name text,
  metadata jsonb not null default '{}',
  is_active boolean not null default true,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
);
```

### New Column: `product_categories.component_type_code`
```sql
alter table product_categories 
  add column component_type_code text 
  references compat_component_library(code) on delete set null;
```

### New View: `v_component_type_catalog`
```sql
create view v_component_type_catalog as
select 
  code,
  display_name,
  parent_code,
  discipline_scope,
  description,
  icon_name,
  metadata,
  is_active,
  jsonb_array_length(metadata->'attributes') as attribute_count
from compat_component_library
where is_active = true
order by display_name;
```

### New Function: `get_category_with_component_metadata(category_id)`
Returns category + component type metadata in one query for product form.

---

## 🌱 SEEDED COMPONENT TYPES (30+)

**Component library includes:**

### Wheel System (5 types)
- `hub` - Maza (5 attributes: spoke holes, OLD, axle type, brake, freehub)
- `rim` - Aro / Rin (5 attributes: spoke holes, ERD, width, wheel size, brake)
- `spoke` - Rayo (3 attributes: length, gauge, material)
- `tire` - Neumático (2 attributes: wheel size, width)
- `tube` - Cámara (2 attributes: wheel size, valve type)

### Frame System (7 types)
- `frame` - Cuadro (8 attributes: wheel size, tire clearance, seatpost, headset, BB, chainline, etc.)
- `fork` - Horquilla (5 attributes: wheel size, travel, steerer, axle, brake mount)
- `headset` - Juego de Dirección (2 attributes: standard, steerer diameter)
- `seatpost` - Tubo de Asiento (3 attributes: diameter, length, dropper travel)
- `handlebar` - Manubrio (3 attributes: width, clamp diameter, type)
- `stem` - Stem / Tee (4 attributes: length, handlebar clamp, steerer, angle)
- `saddle` - Asiento (2 attributes: width, rail material)

### Drivetrain System (7 types)
- `crankset` - Bielas (4 attributes: BB compatibility, arm length, BCD, chainline)
- `chainring` - Plato (2 attributes: teeth, BCD)
- `bottom_bracket` - Caja Centro (2 attributes: BB type, shell width)
- `cassette` - Cassette (4 attributes: freehub type, speeds, min/max teeth)
- `chain` - Cadena (2 attributes: speeds, width)
- `rear_derailleur` - Cambio Trasero (4 attributes: speeds, cage length, capacity, mount)
- `pedal` - Pedales (2 attributes: type, thread size)

### Brake System (2 types)
- `brake_caliper` - Caliper (2 attributes: mount type, fluid type)
- `brake_rotor` - Rotor / Disco (2 attributes: size, mount type)

---

## 📋 METADATA STRUCTURE

Each component type has a `metadata` JSONB field:

```json
{
  "attributes": [
    {
      "key": "spoke_holes",
      "label": "Número de Rayos",
      "type": "enum",
      "required": true,
      "enum_values": ["16", "20", "24", "28", "32", "36", "40", "48"]
    },
    {
      "key": "hub_spacing_mm",
      "label": "Ancho OLD (mm)",
      "type": "enum",
      "required": true,
      "enum_values": ["100", "110", "130", "135", "142", "148", "157"]
    },
    {
      "key": "erd_mm",
      "label": "ERD (mm)",
      "type": "number",
      "required": true,
      "min": 250,
      "max": 700
    }
  ]
}
```

**Attribute Types:**
- `enum`: Dropdown with predefined options
- `number`: Numeric input with min/max validation
- `text`: Free-form text input
- `boolean`: Checkbox

---

## 🔄 USER WORKFLOW

### 1. **Category Configuration** (Admin)
1. Go to Settings → Categories
2. Edit category (e.g., "Mazas Traseras")
3. Select component type from dropdown: "Maza"
4. Save

### 2. **Product Creation** (Daily Use)
1. Create new product
2. Select category: "Mazas Traseras"
3. **Automatically shows compatibility fields:**
   - Número de Rayos (dropdown)
   - Ancho OLD (dropdown)
   - Tipo de Eje (dropdown)
   - Interface de Freno (dropdown, optional)
   - Cuerpo de Cassette (dropdown, optional)
4. Fill in values
5. Save product

### 3. **Compatibility Matching** (Future)
- System can match products based on compatibility attributes
- Example: "Which hubs fit this rim?" → Match by spoke holes + brake interface
- Example: "Which cassettes fit this hub?" → Match by freehub type

---

## 🛠️ FLUTTER IMPLEMENTATION

### Step 1: Category Form Dropdown

**File:** `lib/modules/inventory/pages/category_form_page.dart`

```dart
// Fetch component types
final componentTypes = await Supabase.instance.client
  .from('v_component_type_catalog')
  .select()
  .order('display_name');

// Dropdown widget
DropdownButtonFormField<String?>(
  value: _selectedComponentTypeCode,
  decoration: InputDecoration(
    labelText: 'Tipo de Componente (Compatibilidad)',
    hintText: 'Seleccionar o dejar en blanco',
  ),
  items: [
    DropdownMenuItem(value: null, child: Text('Ninguno')),
    ...componentTypes.map((ct) => DropdownMenuItem(
      value: ct['code'],
      child: Row(
        children: [
          Icon(Icons.${ct['icon_name']}),
          SizedBox(width: 8),
          Text(ct['display_name']),
          SizedBox(width: 8),
          Chip(label: Text('${ct['attribute_count']} campos')),
        ],
      ),
    )),
  ],
  onChanged: (value) {
    setState(() => _selectedComponentTypeCode = value);
  },
)

// On save
final categoryData = {
  'name': _nameController.text,
  'component_type_code': _selectedComponentTypeCode, // Can be null
  // ... other fields
};
```

### Step 2: Product Form Dynamic Fields

**File:** `lib/modules/inventory/pages/product_form_page.dart`

```dart
// Fetch category with component metadata
final categoryData = await Supabase.instance.client
  .rpc('get_category_with_component_metadata', {
    'p_category_id': selectedCategoryId,
  })
  .single();

if (categoryData['component_type_code'] != null) {
  final metadata = categoryData['component_metadata'];
  final attributes = metadata['attributes'] as List;
  
  // Build dynamic form fields
  return Column(
    children: attributes.map((attr) {
      final key = attr['key'];
      final label = attr['label'];
      final type = attr['type'];
      final required = attr['required'] ?? false;
      
      if (type == 'enum') {
        return DropdownButtonFormField<String>(
          decoration: InputDecoration(
            labelText: label,
            suffixText: required ? '*' : '',
          ),
          items: (attr['enum_values'] as List).map((v) => 
            DropdownMenuItem(value: v, child: Text(v))
          ).toList(),
          onChanged: (value) {
            setState(() {
              _compatibilityData[key] = value;
            });
          },
          validator: required ? (v) => v == null ? 'Requerido' : null : null,
        );
      } else if (type == 'number') {
        return TextFormField(
          decoration: InputDecoration(
            labelText: label,
            suffixText: required ? '*' : '',
          ),
          keyboardType: TextInputType.number,
          onChanged: (value) {
            _compatibilityData[key] = double.tryParse(value);
          },
          validator: required 
            ? (v) => v == null || v.isEmpty ? 'Requerido' : null 
            : null,
        );
      }
      // ... other types
    }).toList(),
  );
} else {
  return Text('Esta categoría no requiere especificaciones de compatibilidad');
}

// On save, store compatibility data in products.compatibility_attributes JSONB
final productData = {
  'name': _nameController.text,
  'category_id': _selectedCategoryId,
  'compatibility_attributes': jsonEncode(_compatibilityData), // Store all compat fields
  // ... other fields
};
```

---

## ➕ ADDING NEW COMPONENT TYPES

**No schema changes needed!** Just INSERT into `compat_component_library`:

```sql
insert into compat_component_library (
  code, 
  display_name, 
  parent_code, 
  discipline_scope, 
  description, 
  icon_name, 
  metadata
) values (
  'shock',
  'Amortiguador Trasero',
  'frame_system',
  '{mtb}',
  'Amortiguadores traseros para suspensión',
  'settings_input_composite',
  '{
    "attributes": [
      {
        "key": "eye_to_eye_mm",
        "label": "Eye to Eye (mm)",
        "type": "number",
        "required": true,
        "min": 150,
        "max": 250
      },
      {
        "key": "stroke_mm",
        "label": "Recorrido (mm)",
        "type": "number",
        "required": true,
        "min": 40,
        "max": 80
      },
      {
        "key": "mounting_hardware",
        "label": "Hardware de Montaje",
        "type": "enum",
        "required": false,
        "enum_values": ["Metric", "Imperial", "Trunnion"]
      }
    ]
  }'
);
```

Flutter UI will automatically show new component type in category dropdown!

---

## 🚀 DEPLOYMENT

### SQL File Generated:
- **File:** `DEPLOY_FLEXIBLE_COMPATIBILITY_SYSTEM.sql`
- **Target:** Staging database (`kyvgmapifacpzuyreasy`)

### Deployment Steps:
1. Open Supabase SQL Editor: https://supabase.com/dashboard/project/kyvgmapifacpzuyreasy/sql
2. Paste contents of `DEPLOY_FLEXIBLE_COMPATIBILITY_SYSTEM.sql`
3. Run SQL (creates table, seeds 30+ component types)
4. Verify: `SELECT count(*) FROM compat_component_library;` → Should return ~30

### Integrated into Core Schema:
- **File:** `supabase/sql/core_schema_compat.sql`
- **Lines:** ~2190-2390 (after product_categories section)
- **Auto-seeded:** `seed_component_library()` function runs on schema deployment

---

## ✅ BENEFITS OVER OLD SYSTEM

### Old System (Python Mapping Script)
❌ Required Python script execution  
❌ Hardcoded category name matching  
❌ Breaks when category names change  
❌ No UI for mapping management  
❌ Script must be re-run after imports  

### New System (Flexible Mapping)
✅ User maps categories directly in Flutter UI  
✅ Works with ANY category name  
✅ Survives category renames (ID-based FK)  
✅ Admin-friendly dropdown interface  
✅ No scripts needed after initial seed  

---

## 📝 NEXT STEPS

### Immediate (High Priority)
1. ✅ Database schema updated
2. ✅ Component library seeded with 30+ types
3. ⏳ **Flutter Category Form:** Add component type dropdown
4. ⏳ **Flutter Product Form:** Read component metadata, build dynamic fields
5. ⏳ **Test with "Cuadro" category:** Map to `frame` component type, verify 8 fields appear

### Near-Term
- Add `products.compatibility_attributes` JSONB column (store filled values)
- Create compatibility matching queries/functions
- Build "Find Compatible Products" feature

### Long-Term
- Add more component types (shocks, grips, cleats, etc.)
- Implement advanced matching rules (e.g., "Hub spacing +/-5mm tolerance")
- Create compatibility reports/dashboards

---

## 🔍 QUICK REFERENCE

**Query all component types:**
```sql
SELECT * FROM v_component_type_catalog;
```

**Get category with metadata:**
```sql
SELECT * FROM get_category_with_component_metadata('category-uuid-here');
```

**Map category to component type:**
```sql
UPDATE product_categories 
SET component_type_code = 'frame' 
WHERE id = 'category-uuid' AND tenant_id = user_tenant_id();
```

**Add new component type:**
```sql
INSERT INTO compat_component_library (code, display_name, metadata, ...)
VALUES ('new_type', 'Display Name', '{"attributes": [...]}', ...);
```

---

**System ready for Flutter integration!** 🚀
