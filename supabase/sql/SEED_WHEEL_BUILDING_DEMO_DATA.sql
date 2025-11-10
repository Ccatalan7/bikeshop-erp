-- ============================================================================
-- WHEEL BUILDING SYSTEM - DEMO DATA SEED SCRIPT
-- ============================================================================
-- This script adds realistic demo data for testing the wheel building system
-- Run this AFTER deploying DEPLOY_WHEEL_BUILDING.sql
-- ============================================================================

-- ============================================================================
-- WHEEL BUILDING DEMO DATA SEED
-- ============================================================================
-- IMPORTANT: Run this in Supabase SQL Editor with service_role permissions
-- ============================================================================

-- Find your tenant_id first (run this separately if needed):
-- SELECT id, name, subdomain FROM tenants LIMIT 5;

-- Temporarily disable RLS for seeding (service_role should bypass anyway)
DO $$
DECLARE
  v_tenant_id uuid;
  v_hub_id_front_shimano uuid;
  v_hub_id_rear_shimano uuid;
  v_hub_id_front_hope uuid;
  v_hub_id_rear_hope uuid;
  v_hub_id_front_dt uuid;
  v_hub_id_rear_dt uuid;
  v_rim_id_700c_dt uuid;
  v_rim_id_29_dt uuid;
  v_rim_id_27_5_mavic uuid;
  v_rim_id_26_sun uuid;
  v_spoke_id_290 uuid;
  v_spoke_id_292 uuid;
  v_spoke_id_294 uuid;
  v_spoke_id_296 uuid;
  v_spoke_id_298 uuid;
BEGIN
  -- Get the first tenant (automatic for testing)
  SELECT id INTO v_tenant_id FROM tenants LIMIT 1;
  
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'No tenant found! Please create a tenant first.';
  END IF;
  
  RAISE NOTICE '🔧 Seeding wheel building demo data for tenant: %', v_tenant_id;
  
  -- ============================================================================
  -- 1. HUBS - Front and Rear for different standards
  -- ============================================================================
  
  RAISE NOTICE '📦 Adding hubs...';
  
  -- Shimano Deore Front Hub (QR, Disc 6-bolt)
  INSERT INTO wheel_hubs (
    tenant_id, name, manufacturer, model, hub_type,
    old_mm, spoke_holes,
    left_flange_diameter_mm, right_flange_diameter_mm,
    center_to_left_flange_mm, center_to_right_flange_mm,
    brake_type, driver_type, axle_type, is_active
  ) VALUES (
    v_tenant_id, 'Shimano Deore M6010 Front', 'Shimano', 'M6010',
    'front', 100.0, 32,
    50.0, 50.0, 27.5, 27.5,
    'disc_6bolt', 'none', 'quick_release', true
  ) RETURNING id INTO v_hub_id_front_shimano;
  
  -- Shimano Deore Rear Hub (QR, Disc 6-bolt, Cassette)
  INSERT INTO wheel_hubs (
    tenant_id, name, manufacturer, model, hub_type,
    old_mm, spoke_holes,
    left_flange_diameter_mm, right_flange_diameter_mm,
    center_to_left_flange_mm, center_to_right_flange_mm,
    brake_type, driver_type, axle_type, is_active
  ) VALUES (
    v_tenant_id, 'Shimano Deore M6010 Rear', 'Shimano', 'M6010',
    'rear', 135.0, 32,
    50.0, 50.0, 30.0, 18.0, -- Asymmetric!
    'disc_6bolt', 'cassette', 'quick_release', true
  ) RETURNING id INTO v_hub_id_rear_shimano;
  
  -- Hope Pro 4 Front Hub (15mm Thru-axle, Disc 6-bolt)
  INSERT INTO wheel_hubs (
    tenant_id, name, manufacturer, model, hub_type,
    old_mm, spoke_holes,
    left_flange_diameter_mm, right_flange_diameter_mm,
    center_to_left_flange_mm, center_to_right_flange_mm,
    brake_type, driver_type, axle_type, is_active
  ) VALUES (
    v_tenant_id, 'Hope Pro 4 Front', 'Hope', 'Pro 4',
    'front', 110.0, 32,
    52.0, 52.0, 28.0, 28.0,
    'disc_6bolt', 'none', 'thru_axle_15mm', true
  ) RETURNING id INTO v_hub_id_front_hope;
  
  -- Hope Pro 4 Rear Hub (12mm Thru-axle, Disc 6-bolt, Cassette)
  INSERT INTO wheel_hubs (
    tenant_id, name, manufacturer, model, hub_type,
    old_mm, spoke_holes,
    left_flange_diameter_mm, right_flange_diameter_mm,
    center_to_left_flange_mm, center_to_right_flange_mm,
    brake_type, driver_type, axle_type, is_active
  ) VALUES (
    v_tenant_id, 'Hope Pro 4 Rear', 'Hope', 'Pro 4',
    'rear', 142.0, 32,
    52.0, 52.0, 31.0, 17.0, -- Asymmetric!
    'disc_6bolt', 'cassette', 'thru_axle_12mm', true
  ) RETURNING id INTO v_hub_id_rear_hope;
  
  -- DT Swiss 350 Front Hub (15mm Thru-axle, Disc Centerlock)
  INSERT INTO wheel_hubs (
    tenant_id, name, manufacturer, model, hub_type,
    old_mm, spoke_holes,
    left_flange_diameter_mm, right_flange_diameter_mm,
    center_to_left_flange_mm, center_to_right_flange_mm,
    brake_type, driver_type, axle_type, is_active
  ) VALUES (
    v_tenant_id, 'DT Swiss 350 Front', 'DT Swiss', '350',
    'front', 110.0, 32,
    51.0, 51.0, 27.8, 27.8,
    'disc_centerlock', 'none', 'thru_axle_15mm', true
  ) RETURNING id INTO v_hub_id_front_dt;
  
  -- DT Swiss 350 Rear Hub (12mm Thru-axle, Disc Centerlock, Cassette)
  INSERT INTO wheel_hubs (
    tenant_id, name, manufacturer, model, hub_type,
    old_mm, spoke_holes,
    left_flange_diameter_mm, right_flange_diameter_mm,
    center_to_left_flange_mm, center_to_right_flange_mm,
    brake_type, driver_type, axle_type, is_active
  ) VALUES (
    v_tenant_id, 'DT Swiss 350 Rear', 'DT Swiss', '350',
    'rear', 142.0, 32,
    51.0, 51.0, 29.5, 17.5, -- Asymmetric!
    'disc_centerlock', 'cassette', 'thru_axle_12mm', true
  ) RETURNING id INTO v_hub_id_rear_dt;
  
  -- ============================================================================
  -- 2. RIMS - Various wheel sizes with accurate ERD values
  -- ============================================================================
  
  RAISE NOTICE '📦 Adding rims...';
  
  -- DT Swiss XM421 (29" / 700c MTB rim)
  INSERT INTO wheel_rims (
    tenant_id, name, manufacturer, model, wheel_size,
    erd_mm, spoke_holes, internal_width_mm, external_width_mm, rim_depth_mm,
    brake_type, rim_type, is_active
  ) VALUES (
    v_tenant_id, 'DT Swiss XM421', 'DT Swiss', 'XM421', '29"',
    602.0, 32, 21.0, 25.0, 20.0,
    'disc', 'tubeless_ready', true
  ) RETURNING id INTO v_rim_id_29_dt;
  
  -- DT Swiss R460 (700c Road rim)
  INSERT INTO wheel_rims (
    tenant_id, name, manufacturer, model, wheel_size,
    erd_mm, spoke_holes, internal_width_mm, external_width_mm, rim_depth_mm,
    brake_type, rim_type, is_active
  ) VALUES (
    v_tenant_id, 'DT Swiss R460', 'DT Swiss', 'R460', '700c',
    622.0, 32, 19.0, 23.0, 18.0,
    'disc', 'tubeless_ready', true
  ) RETURNING id INTO v_rim_id_700c_dt;
  
  -- Mavic XM319 (27.5" / 650b MTB rim)
  INSERT INTO wheel_rims (
    tenant_id, name, manufacturer, model, wheel_size,
    erd_mm, spoke_holes, internal_width_mm, external_width_mm, rim_depth_mm,
    brake_type, rim_type, is_active
  ) VALUES (
    v_tenant_id, 'Mavic XM319', 'Mavic', 'XM319', '27.5"',
    584.0, 32, 19.0, 23.0, 19.0,
    'disc', 'clincher', true
  ) RETURNING id INTO v_rim_id_27_5_mavic;
  
  -- Sun Ringle MTX33 (26" Classic MTB rim)
  INSERT INTO wheel_rims (
    tenant_id, name, manufacturer, model, wheel_size,
    erd_mm, spoke_holes, internal_width_mm, external_width_mm, rim_depth_mm,
    brake_type, rim_type, is_active
  ) VALUES (
    v_tenant_id, 'Sun Ringle MTX33', 'Sun Ringle', 'MTX33', '26"',
    559.0, 32, 20.0, 24.0, 18.0,
    'disc', 'clincher', true
  ) RETURNING id INTO v_rim_id_26_sun;
  
  -- ============================================================================
  -- 3. SPOKES - Common lengths with stock quantities
  -- ============================================================================
  
  RAISE NOTICE '📦 Adding spokes...';
  
  -- DT Swiss Competition 290mm (Butted 2.0/1.8mm)
  INSERT INTO wheel_spokes (
    tenant_id, name, manufacturer, model,
    length_mm, gauge, is_butted, material, finish, head_type,
    tensile_strength_n, weight_grams, is_active
  ) VALUES (
    v_tenant_id, 'DT Swiss Competition 290mm', 'DT Swiss', 'Competition',
    290, 2.0, true, 'stainless_steel', 'plain', 'j_bend',
    1200, 5.3, true
  ) RETURNING id INTO v_spoke_id_290;
  
  -- DT Swiss Competition 292mm (Butted 2.0/1.8mm)
  INSERT INTO wheel_spokes (
    tenant_id, name, manufacturer, model,
    length_mm, gauge, is_butted, material, finish, head_type,
    tensile_strength_n, weight_grams, is_active
  ) VALUES (
    v_tenant_id, 'DT Swiss Competition 292mm', 'DT Swiss', 'Competition',
    292, 2.0, true, 'stainless_steel', 'plain', 'j_bend',
    1200, 5.4, true
  ) RETURNING id INTO v_spoke_id_292;
  
  -- DT Swiss Competition 294mm (Butted 2.0/1.8mm)
  INSERT INTO wheel_spokes (
    tenant_id, name, manufacturer, model,
    length_mm, gauge, is_butted, material, finish, head_type,
    tensile_strength_n, weight_grams, is_active
  ) VALUES (
    v_tenant_id, 'DT Swiss Competition 294mm', 'DT Swiss', 'Competition',
    294, 2.0, true, 'stainless_steel', 'plain', 'j_bend',
    1200, 5.5, true
  ) RETURNING id INTO v_spoke_id_294;
  
  -- DT Swiss Competition 296mm (Butted 2.0/1.8mm)
  INSERT INTO wheel_spokes (
    tenant_id, name, manufacturer, model,
    length_mm, gauge, is_butted, material, finish, head_type,
    tensile_strength_n, weight_grams, is_active
  ) VALUES (
    v_tenant_id, 'DT Swiss Competition 296mm', 'DT Swiss', 'Competition',
    296, 2.0, true, 'stainless_steel', 'plain', 'j_bend',
    1200, 5.6, true
  ) RETURNING id INTO v_spoke_id_296;
  
  -- DT Swiss Competition 298mm (Butted 2.0/1.8mm)
  INSERT INTO wheel_spokes (
    tenant_id, name, manufacturer, model,
    length_mm, gauge, is_butted, material, finish, head_type,
    tensile_strength_n, weight_grams, is_active
  ) VALUES (
    v_tenant_id, 'DT Swiss Competition 298mm', 'DT Swiss', 'Competition',
    298, 2.0, true, 'stainless_steel', 'plain', 'j_bend',
    1200, 5.7, true
  ) RETURNING id INTO v_spoke_id_298;
  
  -- Sapim Race 290mm (Straight gauge 2.0mm)
  INSERT INTO wheel_spokes (
    tenant_id, name, manufacturer, model,
    length_mm, gauge, is_butted, material, finish, head_type,
    tensile_strength_n, weight_grams, is_active
  ) VALUES (
    v_tenant_id, 'Sapim Race 290mm', 'Sapim', 'Race',
    290, 2.0, false, 'stainless_steel', 'plain', 'j_bend',
    1100, 5.8, true
  );
  
  -- Sapim Race 292mm (Straight gauge 2.0mm)
  INSERT INTO wheel_spokes (
    tenant_id, name, manufacturer, model,
    length_mm, gauge, is_butted, material, finish, head_type,
    tensile_strength_n, weight_grams, is_active
  ) VALUES (
    v_tenant_id, 'Sapim Race 292mm', 'Sapim', 'Race',
    292, 2.0, false, 'stainless_steel', 'plain', 'j_bend',
    1100, 5.9, true
  );
  
  -- Sapim Race 294mm (Straight gauge 2.0mm)
  INSERT INTO wheel_spokes (
    tenant_id, name, manufacturer, model,
    length_mm, gauge, is_butted, material, finish, head_type,
    tensile_strength_n, weight_grams, is_active
  ) VALUES (
    v_tenant_id, 'Sapim Race 294mm', 'Sapim', 'Race',
    294, 2.0, false, 'stainless_steel', 'plain', 'j_bend',
    1100, 6.0, true
  );
  
  -- Sapim Race 296mm (Straight gauge 2.0mm)
  INSERT INTO wheel_spokes (
    tenant_id, name, manufacturer, model,
    length_mm, gauge, is_butted, material, finish, head_type,
    tensile_strength_n, weight_grams, is_active
  ) VALUES (
    v_tenant_id, 'Sapim Race 296mm', 'Sapim', 'Race',
    296, 2.0, false, 'stainless_steel', 'plain', 'j_bend',
    1100, 6.1, true
  );
  
  -- Pillar PSR 1432 292mm (1.8mm lightweight)
  INSERT INTO wheel_spokes (
    tenant_id, name, manufacturer, model,
    length_mm, gauge, is_butted, material, finish, head_type,
    tensile_strength_n, weight_grams, is_active
  ) VALUES (
    v_tenant_id, 'Pillar PSR 1432 292mm', 'Pillar', 'PSR 1432',
    292, 1.8, false, 'stainless_steel', 'black', 'j_bend',
    950, 4.8, true
  );
  
  -- ============================================================================
  -- 4. SAMPLE WHEEL BUILDS (Pre-calculated for reference)
  -- ============================================================================
  
  RAISE NOTICE '📦 Adding sample wheel builds...';
  
  -- Sample Build 1: 29" MTB Front Wheel (Shimano + DT Swiss XM421)
  INSERT INTO wheel_builds (
    tenant_id, build_name, wheel_position,
    hub_id, rim_id,
    spoke_count, lacing_pattern,
    left_spoke_length_mm, right_spoke_length_mm,
    left_spoke_product_id, right_spoke_product_id,
    is_template, notes
  ) VALUES (
    v_tenant_id, '29" MTB Front Wheel (Shimano Deore)', 'front',
    v_hub_id_front_shimano, v_rim_id_29_dt,
    32, '3-cross',
    295.8, 295.8, -- Symmetric front wheel
    v_spoke_id_296, v_spoke_id_296,
    true, 'Standard 29" MTB front wheel with Shimano Deore hub and DT Swiss XM421 rim. 3-cross lacing for durability.'
  );
  
  -- Sample Build 2: 29" MTB Rear Wheel (Shimano + DT Swiss XM421)
  INSERT INTO wheel_builds (
    tenant_id, build_name, wheel_position,
    hub_id, rim_id,
    spoke_count, lacing_pattern,
    left_spoke_length_mm, right_spoke_length_mm,
    left_spoke_product_id, right_spoke_product_id,
    is_template, notes
  ) VALUES (
    v_tenant_id, '29" MTB Rear Wheel (Shimano Deore)', 'rear',
    v_hub_id_rear_shimano, v_rim_id_29_dt,
    32, '3-cross',
    297.2, 293.4, -- Asymmetric rear wheel!
    v_spoke_id_298, v_spoke_id_294,
    true, 'Standard 29" MTB rear wheel with Shimano Deore hub (asymmetric). Left side uses 298mm, right (drive) side uses 294mm.'
  );
  
  -- Sample Build 3: 700c Road Wheel (DT Swiss + DT Swiss R460)
  INSERT INTO wheel_builds (
    tenant_id, build_name, wheel_position,
    hub_id, rim_id,
    spoke_count, lacing_pattern,
    left_spoke_length_mm, right_spoke_length_mm,
    left_spoke_product_id, right_spoke_product_id,
    is_template, notes
  ) VALUES (
    v_tenant_id, '700c Road Rear Wheel (DT Swiss 350)', 'rear',
    v_hub_id_rear_dt, v_rim_id_700c_dt,
    32, '3-cross',
    296.5, 292.8, -- Asymmetric rear wheel
    v_spoke_id_296, v_spoke_id_292,
    true, 'High-quality 700c road rear wheel with DT Swiss 350 hub and R460 rim. Perfect for road bikes and gravel bikes.'
  );
  
  -- ============================================================================
  -- SUCCESS MESSAGE
  -- ============================================================================
  
  RAISE NOTICE '✅ Demo data seeded successfully!';
  RAISE NOTICE '';
  RAISE NOTICE '📊 Summary:';
  RAISE NOTICE '   - 6 Hubs added (3 front, 3 rear)';
  RAISE NOTICE '   - 4 Rims added (26", 27.5", 29", 700c)';
  RAISE NOTICE '   - 10 Spokes added (290-298mm range)';
  RAISE NOTICE '   - 3 Sample builds added (templates)';
  RAISE NOTICE '';
  RAISE NOTICE '🔧 Test the Wheel Builder Wizard now!';
  RAISE NOTICE '   1. Go to Taller → Wheel Builder';
  RAISE NOTICE '   2. Select "Shimano Deore M6010 Rear" hub';
  RAISE NOTICE '   3. Select "DT Swiss XM421" rim (29")';
  RAISE NOTICE '   4. Choose "3-cross" lacing';
  RAISE NOTICE '   5. See calculated spoke lengths!';
  RAISE NOTICE '';
  RAISE NOTICE '💡 Expected results:';
  RAISE NOTICE '   Left (non-drive): ~297mm';
  RAISE NOTICE '   Right (drive): ~293mm';
  RAISE NOTICE '   Recommended: DT Swiss 298mm + 294mm';
  
END $$;

-- ============================================================================
-- VERIFICATION QUERIES
-- ============================================================================

-- Check what was added (run these separately after seeding)
/*

-- Count components by type
SELECT 
  'Hubs' as component,
  COUNT(*) as count,
  COUNT(CASE WHEN hub_type = 'front' THEN 1 END) as front,
  COUNT(CASE WHEN hub_type = 'rear' THEN 1 END) as rear
FROM wheel_hubs 
WHERE tenant_id = public.user_tenant_id()

UNION ALL

SELECT 
  'Rims' as component,
  COUNT(*) as count,
  string_agg(DISTINCT wheel_size, ', ') as sizes,
  NULL
FROM wheel_rims 
WHERE tenant_id = public.user_tenant_id()

UNION ALL

SELECT 
  'Spokes' as component,
  COUNT(*) as count,
  MIN(length_mm)::text || '-' || MAX(length_mm)::text || 'mm' as range,
  NULL
FROM wheel_spokes 
WHERE tenant_id = public.user_tenant_id()

UNION ALL

SELECT 
  'Builds' as component,
  COUNT(*) as count,
  COUNT(CASE WHEN is_template THEN 1 END)::text as templates,
  NULL
FROM wheel_builds 
WHERE tenant_id = public.user_tenant_id();

-- View all hubs
SELECT 
  name,
  hub_type,
  old_mm || 'mm' as old,
  spoke_holes || 'H' as holes,
  brake_type,
  driver_type
FROM wheel_hubs 
WHERE tenant_id = public.user_tenant_id()
ORDER BY hub_type, manufacturer;

-- View all rims
SELECT 
  name,
  wheel_size,
  erd_mm || 'mm' as erd,
  spoke_holes || 'H' as holes,
  internal_width_mm || 'mm' as width
FROM wheel_rims 
WHERE tenant_id = public.user_tenant_id()
ORDER BY wheel_size;

-- View all spokes
SELECT 
  name,
  length_mm || 'mm' as length,
  gauge || 'mm' as gauge,
  CASE WHEN is_butted THEN 'Butted' ELSE 'Straight' END as type,
  material
FROM wheel_spokes 
WHERE tenant_id = public.user_tenant_id()
ORDER BY length_mm;

-- View sample builds
SELECT 
  build_name,
  wheel_position,
  spoke_count || 'H' as spokes,
  lacing_pattern as lacing,
  left_spoke_length_mm || 'mm' as left_length,
  right_spoke_length_mm || 'mm' as right_length
FROM wheel_builds 
WHERE tenant_id = public.user_tenant_id()
  AND is_template = true
ORDER BY build_name;

*/
