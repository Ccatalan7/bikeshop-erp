import 'package:supabase_flutter/supabase_flutter.dart';

/// Run this script from Flutter to seed wheel building demo data
/// This bypasses RLS issues since it runs as an authenticated user
Future<void> seedWheelBuildingData() async {
  final supabase = Supabase.instance.client;
  
  print('🔧 Starting wheel building demo data seed...');
  
  try {
    // Get current user's tenant_id
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No user logged in!');
    }
    
    print('📋 Fetching tenant_id for user: $userId');
    final userProfile = await supabase
        .from('user_profiles')
        .select('tenant_id')
        .eq('user_id', userId)
        .single();
    
    final tenantId = userProfile['tenant_id'] as String;
    print('✅ Found tenant_id: $tenantId');
    
    // ============================================================================
    // 0. CLEANUP - Delete existing demo data to prevent duplicates
    // ============================================================================
    
    print('🧹 Cleaning up existing demo data...');
    
    // Delete in correct order (builds → spokes → rims → hubs)
    await supabase.from('wheel_builds').delete().eq('tenant_id', tenantId);
    await supabase.from('wheel_spokes').delete().eq('tenant_id', tenantId);
    await supabase.from('wheel_rims').delete().eq('tenant_id', tenantId);
    await supabase.from('wheel_hubs').delete().eq('tenant_id', tenantId);
    
    print('✅ Cleanup complete');
    
    // ============================================================================
    // 1. HUBS - Front and Rear for different standards
    // ============================================================================
    
    print('📦 Adding hubs...');
    
    final hubsData = [
      // Shimano Deore Front Hub - 32H (Disc brake = asymmetric!)
      {
        'tenant_id': tenantId,
        'name': 'Shimano Deore M6010 Front 32H',
        'manufacturer': 'Shimano',
        'model': 'M6010',
        'hub_type': 'front',
        'old_mm': 100.0,
        'spoke_holes': 32,
        'left_flange_diameter_mm': 50.0,
        'right_flange_diameter_mm': 50.0,
        'center_to_left_flange_mm': 32.5, // Non-rotor side (farther)
        'center_to_right_flange_mm': 22.5, // Rotor side (closer)
        'brake_type': 'disc_6bolt',
        'driver_type': 'none',
        'axle_type': 'quick_release',
        'is_active': true,
      },
      // Shimano Deore Rear Hub - 32H (Flange-to-center measurements)
      {
        'tenant_id': tenantId,
        'name': 'Shimano Deore M6010 Rear 32H',
        'manufacturer': 'Shimano',
        'model': 'M6010',
        'hub_type': 'rear',
        'old_mm': 135.0,
        'spoke_holes': 32,
        'left_flange_diameter_mm': 50.0,
        'right_flange_diameter_mm': 50.0,
        'center_to_left_flange_mm': 30.0, // Flange-to-center (used in formula)
        'center_to_right_flange_mm': 18.0, // Flange-to-center (used in formula)
        'brake_type': 'disc_6bolt',
        'driver_type': 'cassette',
        'axle_type': 'quick_release',
        'is_active': true,
      },
      // Shimano Deore Front Hub - 28H (Disc brake = asymmetric!)
      {
        'tenant_id': tenantId,
        'name': 'Shimano Deore M6010 Front 28H',
        'manufacturer': 'Shimano',
        'model': 'M6010',
        'hub_type': 'front',
        'old_mm': 100.0,
        'spoke_holes': 28,
        'left_flange_diameter_mm': 50.0,
        'right_flange_diameter_mm': 50.0,
        'center_to_left_flange_mm': 32.5, // Non-rotor side (farther)
        'center_to_right_flange_mm': 22.5, // Rotor side (closer)
        'brake_type': 'disc_6bolt',
        'driver_type': 'none',
        'axle_type': 'quick_release',
        'is_active': true,
      },
      // Hope Pro 4 Front Hub - 32H (Disc brake = asymmetric!)
      {
        'tenant_id': tenantId,
        'name': 'Hope Pro 4 Front 32H',
        'manufacturer': 'Hope',
        'model': 'Pro 4',
        'hub_type': 'front',
        'old_mm': 110.0,
        'spoke_holes': 32,
        'left_flange_diameter_mm': 52.0,
        'right_flange_diameter_mm': 52.0,
        'center_to_left_flange_mm': 33.0, // Non-rotor side (farther)
        'center_to_right_flange_mm': 22.0, // Rotor side (closer)
        'brake_type': 'disc_6bolt',
        'driver_type': 'none',
        'axle_type': 'thru_axle_15mm',
        'is_active': true,
      },
      // Hope Pro 4 Rear Hub - 32H
      {
        'tenant_id': tenantId,
        'name': 'Hope Pro 4 Rear 32H',
        'manufacturer': 'Hope',
        'model': 'Pro 4',
        'hub_type': 'rear',
        'old_mm': 142.0,
        'spoke_holes': 32,
        'left_flange_diameter_mm': 52.0,
        'right_flange_diameter_mm': 52.0,
        'center_to_left_flange_mm': 31.0,
        'center_to_right_flange_mm': 17.0, // Asymmetric!
        'brake_type': 'disc_6bolt',
        'driver_type': 'cassette',
        'axle_type': 'thru_axle_12mm',
        'is_active': true,
      },
      // Hope Pro 4 Rear Hub - 28H (for testing filtering)
      {
        'tenant_id': tenantId,
        'name': 'Hope Pro 4 Rear 28H',
        'manufacturer': 'Hope',
        'model': 'Pro 4',
        'hub_type': 'rear',
        'old_mm': 142.0,
        'spoke_holes': 28,
        'left_flange_diameter_mm': 52.0,
        'right_flange_diameter_mm': 52.0,
        'center_to_left_flange_mm': 31.0,
        'center_to_right_flange_mm': 17.0,
        'brake_type': 'disc_6bolt',
        'driver_type': 'cassette',
        'axle_type': 'thru_axle_12mm',
        'is_active': true,
      },
      // DT Swiss 350 Front Hub - 24H (road bike, disc = asymmetric!)
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss 350 Front 24H',
        'manufacturer': 'DT Swiss',
        'model': '350',
        'hub_type': 'front',
        'old_mm': 100.0,
        'spoke_holes': 24,
        'left_flange_diameter_mm': 51.0,
        'right_flange_diameter_mm': 51.0,
        'center_to_left_flange_mm': 32.8, // Non-rotor side (farther)
        'center_to_right_flange_mm': 22.8, // Rotor side (closer)
        'brake_type': 'disc_centerlock',
        'driver_type': 'none',
        'axle_type': 'quick_release',
        'is_active': true,
      },
      // DT Swiss 350 Rear Hub - 32H
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss 350 Rear 32H',
        'manufacturer': 'DT Swiss',
        'model': '350',
        'hub_type': 'rear',
        'old_mm': 142.0,
        'spoke_holes': 32,
        'left_flange_diameter_mm': 51.0,
        'right_flange_diameter_mm': 51.0,
        'center_to_left_flange_mm': 29.5,
        'center_to_right_flange_mm': 17.5, // Asymmetric!
        'brake_type': 'disc_centerlock',
        'driver_type': 'cassette',
        'axle_type': 'thru_axle_12mm',
        'is_active': true,
      },
      // Chris King R45 Front - 28H (premium road hub, disc = asymmetric!)
      {
        'tenant_id': tenantId,
        'name': 'Chris King R45 Front 28H',
        'manufacturer': 'Chris King',
        'model': 'R45',
        'hub_type': 'front',
        'old_mm': 100.0,
        'spoke_holes': 28,
        'left_flange_diameter_mm': 48.0,
        'right_flange_diameter_mm': 48.0,
        'center_to_left_flange_mm': 31.0, // Non-rotor side (farther)
        'center_to_right_flange_mm': 21.0, // Rotor side (closer)
        'brake_type': 'disc_6bolt',
        'driver_type': 'none',
        'axle_type': 'quick_release',
        'is_active': true,
      },
      // Industry Nine Hydra Rear - 32H (high-end MTB)
      {
        'tenant_id': tenantId,
        'name': 'Industry Nine Hydra Rear 32H',
        'manufacturer': 'Industry Nine',
        'model': 'Hydra',
        'hub_type': 'rear',
        'old_mm': 148.0,
        'spoke_holes': 32,
        'left_flange_diameter_mm': 54.0,
        'right_flange_diameter_mm': 54.0,
        'center_to_left_flange_mm': 32.0,
        'center_to_right_flange_mm': 19.0, // Asymmetric!
        'brake_type': 'disc_6bolt',
        'driver_type': 'cassette',
        'axle_type': 'thru_axle_12mm',
        'is_active': true,
      },
    ];
    
    final hubIds = <String, String>{};
    for (final hub in hubsData) {
      final result = await supabase.from('wheel_hubs').insert(hub).select('id, name').single();
      hubIds[hub['name'] as String] = result['id'] as String;
      print('  ✓ ${hub['name']}');
    }
    
    // ============================================================================
    // 2. RIMS - Various wheel sizes with accurate ERD values
    // ============================================================================
    
    print('📦 Adding rims...');
    
    final rimsData = [
      // 29" RIMS
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss XM421 29" (ERD 602mm) 32H',
        'manufacturer': 'DT Swiss',
        'model': 'XM421',
        'wheel_size': '29"',
        'erd_mm': 602.0,
        'spoke_holes': 32,
        'internal_width_mm': 21.0,
        'external_width_mm': 25.0,
        'rim_depth_mm': 20.0,
        'brake_type': 'disc',
        'rim_type': 'tubeless_ready',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss XM421 29" (ERD 602mm) 28H',
        'manufacturer': 'DT Swiss',
        'model': 'XM421',
        'wheel_size': '29"',
        'erd_mm': 602.0,
        'spoke_holes': 28,
        'internal_width_mm': 21.0,
        'external_width_mm': 25.0,
        'rim_depth_mm': 20.0,
        'brake_type': 'disc',
        'rim_type': 'tubeless_ready',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'name': 'Stan\'s Flow S2 29" (ERD 601mm) 32H',
        'manufacturer': 'Stan\'s NoTubes',
        'model': 'Flow S2',
        'wheel_size': '29"',
        'erd_mm': 601.0,
        'spoke_holes': 32,
        'internal_width_mm': 27.0,
        'external_width_mm': 32.0,
        'rim_depth_mm': 25.0,
        'brake_type': 'disc',
        'rim_type': 'tubeless_ready',
        'is_active': true,
      },
      // 700C RIMS (Road)
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss R460 700c (ERD 622mm) 24H',
        'manufacturer': 'DT Swiss',
        'model': 'R460',
        'wheel_size': '700c',
        'erd_mm': 622.0,
        'spoke_holes': 24,
        'internal_width_mm': 19.0,
        'external_width_mm': 23.0,
        'rim_depth_mm': 18.0,
        'brake_type': 'disc',
        'rim_type': 'tubeless_ready',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss R460 700c (ERD 622mm) 32H',
        'manufacturer': 'DT Swiss',
        'model': 'R460',
        'wheel_size': '700c',
        'erd_mm': 622.0,
        'spoke_holes': 32,
        'internal_width_mm': 19.0,
        'external_width_mm': 23.0,
        'rim_depth_mm': 18.0,
        'brake_type': 'disc',
        'rim_type': 'tubeless_ready',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'name': 'Mavic Open Pro 700c (ERD 622mm) 28H',
        'manufacturer': 'Mavic',
        'model': 'Open Pro',
        'wheel_size': '700c',
        'erd_mm': 622.0,
        'spoke_holes': 28,
        'internal_width_mm': 15.0,
        'external_width_mm': 19.0,
        'rim_depth_mm': 17.0,
        'brake_type': 'rim',
        'rim_type': 'clincher',
        'is_active': true,
      },
      // 27.5" RIMS
      {
        'tenant_id': tenantId,
        'name': 'Mavic XM319 27.5" (ERD 584mm) 32H',
        'manufacturer': 'Mavic',
        'model': 'XM319',
        'wheel_size': '27.5"',
        'erd_mm': 584.0,
        'spoke_holes': 32,
        'internal_width_mm': 19.0,
        'external_width_mm': 23.0,
        'rim_depth_mm': 19.0,
        'brake_type': 'disc',
        'rim_type': 'clincher',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'name': 'WTB KOM i25 27.5" (ERD 582mm) 28H',
        'manufacturer': 'WTB',
        'model': 'KOM i25',
        'wheel_size': '27.5"',
        'erd_mm': 582.0,
        'spoke_holes': 28,
        'internal_width_mm': 25.0,
        'external_width_mm': 29.0,
        'rim_depth_mm': 22.0,
        'brake_type': 'disc',
        'rim_type': 'tubeless_ready',
        'is_active': true,
      },
      // 26" RIMS (Classic MTB)
      {
        'tenant_id': tenantId,
        'name': 'Sun Ringle MTX33 26" (ERD 559mm) 32H',
        'manufacturer': 'Sun Ringle',
        'model': 'MTX33',
        'wheel_size': '26"',
        'erd_mm': 559.0,
        'spoke_holes': 32,
        'internal_width_mm': 20.0,
        'external_width_mm': 24.0,
        'rim_depth_mm': 18.0,
        'brake_type': 'disc',
        'rim_type': 'clincher',
        'is_active': true,
      },
      {
        'tenant_id': tenantId,
        'name': 'Alex DM24 26" (ERD 557mm) 36H',
        'manufacturer': 'Alex',
        'model': 'DM24',
        'wheel_size': '26"',
        'erd_mm': 557.0,
        'spoke_holes': 36,
        'internal_width_mm': 19.0,
        'external_width_mm': 23.0,
        'rim_depth_mm': 20.0,
        'brake_type': 'disc',
        'rim_type': 'clincher',
        'is_active': true,
      },
    ];
    
    final rimIds = <String, String>{};
    for (final rim in rimsData) {
      final result = await supabase.from('wheel_rims').insert(rim).select('id, name').single();
      rimIds[rim['name'] as String] = result['id'] as String;
      print('  ✓ ${rim['name']}');
    }
    
    // ============================================================================
    // 3. SPOKES - Common lengths with stock quantities
    // ============================================================================
    
    print('📦 Adding spokes...');
    
    final spokesData = [
      // DT Swiss Competition series (Butted 2.0/1.8mm)
      {'tenant_id': tenantId, 'name': 'DT Swiss Competition 290mm', 'manufacturer': 'DT Swiss', 'model': 'Competition', 'length_mm': 290, 'gauge': 2.0, 'is_butted': true, 'material': 'stainless_steel', 'finish': 'plain', 'head_type': 'j_bend', 'tensile_strength_n': 1200, 'weight_grams': 5.3, 'is_active': true},
      {'tenant_id': tenantId, 'name': 'DT Swiss Competition 292mm', 'manufacturer': 'DT Swiss', 'model': 'Competition', 'length_mm': 292, 'gauge': 2.0, 'is_butted': true, 'material': 'stainless_steel', 'finish': 'plain', 'head_type': 'j_bend', 'tensile_strength_n': 1200, 'weight_grams': 5.4, 'is_active': true},
      {'tenant_id': tenantId, 'name': 'DT Swiss Competition 294mm', 'manufacturer': 'DT Swiss', 'model': 'Competition', 'length_mm': 294, 'gauge': 2.0, 'is_butted': true, 'material': 'stainless_steel', 'finish': 'plain', 'head_type': 'j_bend', 'tensile_strength_n': 1200, 'weight_grams': 5.5, 'is_active': true},
      {'tenant_id': tenantId, 'name': 'DT Swiss Competition 296mm', 'manufacturer': 'DT Swiss', 'model': 'Competition', 'length_mm': 296, 'gauge': 2.0, 'is_butted': true, 'material': 'stainless_steel', 'finish': 'plain', 'head_type': 'j_bend', 'tensile_strength_n': 1200, 'weight_grams': 5.6, 'is_active': true},
      {'tenant_id': tenantId, 'name': 'DT Swiss Competition 298mm', 'manufacturer': 'DT Swiss', 'model': 'Competition', 'length_mm': 298, 'gauge': 2.0, 'is_butted': true, 'material': 'stainless_steel', 'finish': 'plain', 'head_type': 'j_bend', 'tensile_strength_n': 1200, 'weight_grams': 5.7, 'is_active': true},
      // Sapim Race series (Straight gauge 2.0mm)
      {'tenant_id': tenantId, 'name': 'Sapim Race 290mm', 'manufacturer': 'Sapim', 'model': 'Race', 'length_mm': 290, 'gauge': 2.0, 'is_butted': false, 'material': 'stainless_steel', 'finish': 'plain', 'head_type': 'j_bend', 'tensile_strength_n': 1100, 'weight_grams': 5.8, 'is_active': true},
      {'tenant_id': tenantId, 'name': 'Sapim Race 292mm', 'manufacturer': 'Sapim', 'model': 'Race', 'length_mm': 292, 'gauge': 2.0, 'is_butted': false, 'material': 'stainless_steel', 'finish': 'plain', 'head_type': 'j_bend', 'tensile_strength_n': 1100, 'weight_grams': 5.9, 'is_active': true},
      {'tenant_id': tenantId, 'name': 'Sapim Race 294mm', 'manufacturer': 'Sapim', 'model': 'Race', 'length_mm': 294, 'gauge': 2.0, 'is_butted': false, 'material': 'stainless_steel', 'finish': 'plain', 'head_type': 'j_bend', 'tensile_strength_n': 1100, 'weight_grams': 6.0, 'is_active': true},
      {'tenant_id': tenantId, 'name': 'Sapim Race 296mm', 'manufacturer': 'Sapim', 'model': 'Race', 'length_mm': 296, 'gauge': 2.0, 'is_butted': false, 'material': 'stainless_steel', 'finish': 'plain', 'head_type': 'j_bend', 'tensile_strength_n': 1100, 'weight_grams': 6.1, 'is_active': true},
      // Pillar PSR 1432 (1.8mm lightweight)
      {'tenant_id': tenantId, 'name': 'Pillar PSR 1432 292mm', 'manufacturer': 'Pillar', 'model': 'PSR 1432', 'length_mm': 292, 'gauge': 1.8, 'is_butted': false, 'material': 'stainless_steel', 'finish': 'black', 'head_type': 'j_bend', 'tensile_strength_n': 950, 'weight_grams': 4.8, 'is_active': true},
    ];
    
    final spokeIds = <String, String>{};
    for (final spoke in spokesData) {
      final result = await supabase.from('wheel_spokes').insert(spoke).select('id, name').single();
      spokeIds[spoke['name'] as String] = result['id'] as String;
      print('  ✓ ${spoke['name']}');
    }
    
    // ============================================================================
    // 4. SAMPLE WHEEL BUILDS (Pre-calculated for reference)
    // ============================================================================
    
    print('📦 Adding sample wheel builds...');
    
    final buildsData = [
      // Sample Build 1: 29" MTB Front Wheel (Shimano + DT Swiss XM421)
      {
        'tenant_id': tenantId,
        'build_name': '29" MTB Front Wheel (Shimano Deore 32H)',
        'wheel_position': 'front',
        'hub_id': hubIds['Shimano Deore M6010 Front 32H'],
        'rim_id': rimIds['DT Swiss XM421 29" (ERD 602mm) 32H'],
        'spoke_count': 32,
        'lacing_pattern': '3-cross',
        'left_spoke_length_mm': 295.8,
        'right_spoke_length_mm': 295.8, // Symmetric front wheel
        'is_template': true,
        'notes': 'Standard 29" MTB front wheel with Shimano Deore 32H hub and DT Swiss XM421 rim. 3-cross lacing for durability. Recommended spoke: DT Swiss Competition 296mm (both sides).',
      },
      // Sample Build 2: 29" MTB Rear Wheel (Shimano + DT Swiss XM421)
      {
        'tenant_id': tenantId,
        'build_name': '29" MTB Rear Wheel (Shimano Deore 32H)',
        'wheel_position': 'rear',
        'hub_id': hubIds['Shimano Deore M6010 Rear 32H'],
        'rim_id': rimIds['DT Swiss XM421 29" (ERD 602mm) 32H'],
        'spoke_count': 32,
        'lacing_pattern': '3-cross',
        'left_spoke_length_mm': 297.2,
        'right_spoke_length_mm': 293.4, // Asymmetric rear wheel!
        'is_template': true,
        'notes': 'Standard 29" MTB rear wheel with Shimano Deore 32H hub (asymmetric). Left side uses ~298mm, right (drive) side uses ~294mm.',
      },
      // Sample Build 3: 700c Road Wheel (DT Swiss + DT Swiss R460)
      {
        'tenant_id': tenantId,
        'build_name': '700c Road Rear Wheel (DT Swiss 350 32H)',
        'wheel_position': 'rear',
        'hub_id': hubIds['DT Swiss 350 Rear 32H'],
        'rim_id': rimIds['DT Swiss R460 700c (ERD 622mm) 32H'],
        'spoke_count': 32,
        'lacing_pattern': '3-cross',
        'left_spoke_length_mm': 296.5,
        'right_spoke_length_mm': 292.8, // Asymmetric rear wheel
        'is_template': true,
        'notes': 'High-quality 700c road rear wheel with DT Swiss 350 32H hub and R460 rim. Perfect for road bikes and gravel bikes. Recommended: 296mm left, 292mm right.',
      },
    ];
    
    for (final build in buildsData) {
      await supabase.from('wheel_builds').insert(build);
      print('  ✓ ${build['build_name']}');
    }
    
    // ============================================================================
    // SUCCESS MESSAGE
    // ============================================================================
    
    print('');
    print('✅ Demo data seeded successfully!');
    print('');
    print('📊 Summary:');
    print('   - 10 Hubs: 5×32H, 3×28H, 1×24H, 1×32H MTB (diverse compatibility)');
    print('   - 10 Rims: 29"×3, 700c×3, 27.5"×2, 26"×2 (24H, 28H, 32H, 36H)');
    print('   - 10 Spokes added (290-298mm range)');
    print('   - 3 Sample builds added (templates)');
    print('');
    print('🔧 Test the Wheel Builder Wizard now!');
    print('   1. Go to Taller → Wheel Builder');
    print('   2. Select "Shimano Deore M6010 Rear 32H" hub');
    print('   3. Watch rim list FILTER to show only 32H rims!');
    print('   4. Should see: DT Swiss XM421 32H, DT Swiss R460 32H, Mavic XM319 32H, Sun Ringle 32H');
    print('   5. Should NOT see: 24H, 28H, or 36H rims');
    print('   6. Try selecting a 28H hub → rim list changes!');
    print('');
    print('💡 Expected results:');
    print('   Left (non-drive): ~297mm');
    print('   Right (drive): ~293mm');
    print('   Recommended: DT Swiss 298mm + 294mm');
    
  } catch (e, stackTrace) {
    print('❌ Error seeding data: $e');
    print(stackTrace);
    rethrow;
  }
}
