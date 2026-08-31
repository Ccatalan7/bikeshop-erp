import 'package:supabase_flutter/supabase_flutter.dart';

/// Comprehensive seed script for bikes and wheel building demo data
/// Run this from Flutter to populate the app with testing data
Future<void> seedBikesAndWheels() async {
  final supabase = Supabase.instance.client;

  print('🚀 Starting comprehensive bike & wheel building data seed...');

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

    // Delete in correct order (builds → spokes → rims → hubs → bikes)
    await supabase.from('wheel_builds').delete().eq('tenant_id', tenantId);
    await supabase.from('wheel_spokes').delete().eq('tenant_id', tenantId);
    await supabase
        .from('bikes')
        .delete()
        .eq('tenant_id', tenantId); // Delete bikes before rims
    await supabase.from('wheel_rims').delete().eq('tenant_id', tenantId);
    await supabase.from('wheel_hubs').delete().eq('tenant_id', tenantId);

    print('✅ Cleanup complete');

    // ============================================================================
    // 1. CREATE INVENTORY CUSTOMER (bikes require customer_id)
    // ============================================================================

    print('📦 Creating shop inventory customer...');

    // Check if inventory customer exists
    final existingCustomer = await supabase
        .from('customers')
        .select('id')
        .eq('tenant_id', tenantId)
        .eq('email', 'inventory@shop.local')
        .maybeSingle();

    String inventoryCustomerId;
    if (existingCustomer != null) {
      inventoryCustomerId = existingCustomer['id'] as String;
      print('✅ Using existing inventory customer: $inventoryCustomerId');
    } else {
      final newCustomer = await supabase
          .from('customers')
          .insert({
            'tenant_id': tenantId,
            'name': 'Shop Inventory',
            'email': 'inventory@shop.local',
            'phone': '000000000',
            'rut': '00000000-0',
            'notes': 'Default customer for shop inventory bikes',
          })
          .select()
          .single();

      inventoryCustomerId = newCustomer['id'] as String;
      print('✅ Created inventory customer: $inventoryCustomerId');
    }

    // ============================================================================
    // 2. RIMS FIRST - We need rim IDs to link to bikes
    // ============================================================================

    print('📦 Adding rims...');

    final rimsData = [
      // 29" Rims
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss XM421 29" (ERD 602mm) 32H',
        'manufacturer': 'DT Swiss',
        'wheel_size': '29"',
        'erd_mm': 602.0,
        'spoke_holes': 32,
        'internal_width_mm': 25.0,
        'external_width_mm': 30.0,
        'brake_type': 'disc',
        'rim_type': 'tubeless_ready',
        'material': 'aluminum',
        'notes': 'Trail/All-Mountain rim, tubeless ready',
      },
      {
        'tenant_id': tenantId,
        'name': 'Stan\'s NoTubes Arch MK4 29" (ERD 605mm) 32H',
        'manufacturer': 'Stan\'s NoTubes',
        'wheel_size': '29"',
        'erd_mm': 605.0,
        'spoke_holes': 32,
        'internal_width_mm': 26.0,
        'external_width_mm': 30.0,
        'brake_type': 'disc',
        'rim_type': 'tubeless_ready',
        'material': 'aluminum',
        'notes': 'Wide trail rim for 2.3-2.6" tires',
      },
      {
        'tenant_id': tenantId,
        'name': 'WTB KOM Light i25 29" (ERD 601mm) 28H',
        'manufacturer': 'WTB',
        'wheel_size': '29"',
        'erd_mm': 601.0,
        'spoke_holes': 28,
        'internal_width_mm': 25.0,
        'external_width_mm': 29.0,
        'brake_type': 'disc',
        'rim_type': 'tubeless_ready',
        'material': 'aluminum',
        'notes': 'XC race rim, lightweight',
      },
    ];

    final insertedRims =
        await supabase.from('wheel_rims').insert(rimsData).select();

    print('✅ Added ${insertedRims.length} rims');

    // Get rim IDs by name for linking to bikes
    final dtSwissXM421Id = insertedRims
        .firstWhere((r) => r['name'].contains('DT Swiss XM421'))['id'];
    final stansArchId = insertedRims
        .firstWhere((r) => r['name'].contains('Stan\'s NoTubes Arch'))['id'];
    final wtbKomId =
        insertedRims.firstWhere((r) => r['name'].contains('WTB KOM'))['id'];

    print(
        '📋 Rim IDs: DT Swiss=$dtSwissXM421Id, Stan\'s=$stansArchId, WTB=$wtbKomId');

    // ============================================================================
    // 3. BIKES - Link to specific factory rims
    // ============================================================================

    print('🚴 Adding bikes...');

    final bikesData = [
      // Mountain Bikes - 29" (Boost spacing: 110mm front, 148mm rear)
      {
        'tenant_id': tenantId,
        'customer_id': inventoryCustomerId,
        'brand': 'Trek',
        'model': 'X-Caliber 8',
        'year': 2024,
        'serial_number': 'TRK29001',
        'wheel_size': '29"',
        'frame_size': 'L',
        'color': 'Matte Black',
        'bike_type': 'mountain',
        'front_hub_spacing_mm': 110.0,
        'rear_hub_spacing_mm': 148.0,
        'spoke_count': 32,
        'factory_rim_id': dtSwissXM421Id, // EXACT factory rim
        'purchase_price': 650000,
        'notes':
            'Cross-country hardtail, 29" wheels with Boost spacing (110/148mm)',
      },
      {
        'tenant_id': tenantId,
        'customer_id': inventoryCustomerId,
        'brand': 'Specialized',
        'model': 'Rockhopper Comp 29',
        'year': 2024,
        'serial_number': 'SPZ29002',
        'wheel_size': '29"',
        'frame_size': 'M',
        'color': 'Gloss Red',
        'bike_type': 'mountain',
        'front_hub_spacing_mm': 110.0,
        'rear_hub_spacing_mm': 148.0,
        'spoke_count': 32,
        'factory_rim_id': stansArchId, // EXACT factory rim
        'purchase_price': 580000,
        'notes': 'Trail bike with 29" wheels, great for all-terrain',
      },
      {
        'tenant_id': tenantId,
        'customer_id': inventoryCustomerId,
        'brand': 'Giant',
        'model': 'Talon 29 2',
        'year': 2023,
        'serial_number': 'GNT29003',
        'wheel_size': '29"',
        'frame_size': 'M',
        'color': 'Metallic Blue',
        'bike_type': 'mountain',
        'front_hub_spacing_mm': 110.0,
        'rear_hub_spacing_mm': 148.0,
        'spoke_count': 32,
        'purchase_price': 450000,
        'notes': 'Entry-level trail bike, Boost spacing (110/148mm)',
      },

      // Mountain Bikes - 27.5" (28H hubs, 142mm rear for XC)
      {
        'tenant_id': tenantId,
        'customer_id': inventoryCustomerId,
        'brand': 'Scott',
        'model': 'Scale 970',
        'year': 2024,
        'serial_number': 'SCT275004',
        'wheel_size': '27.5"',
        'frame_size': 'M',
        'color': 'Green/Black',
        'bike_type': 'mountain',
        'front_hub_spacing_mm': 100.0,
        'rear_hub_spacing_mm': 142.0,
        'spoke_count': 28,
        'purchase_price': 720000,
        'notes': 'Lightweight XC race bike, 27.5" standard spacing (100/142mm)',
      },
      {
        'tenant_id': tenantId,
        'customer_id': inventoryCustomerId,
        'brand': 'Cannondale',
        'model': 'Trail 6',
        'year': 2023,
        'serial_number': 'CND275005',
        'wheel_size': '27.5"',
        'frame_size': 'S',
        'color': 'Purple',
        'bike_type': 'mountain',
        'front_hub_spacing_mm': 100.0,
        'rear_hub_spacing_mm': 142.0,
        'spoke_count': 28,
        'purchase_price': 520000,
        'notes': 'Women\'s trail bike, standard spacing (100/142mm)',
      },

      // Mountain Bikes - 26" (vintage - QR spacing 135mm rear)
      {
        'tenant_id': tenantId,
        'customer_id': inventoryCustomerId,
        'brand': 'GT',
        'model': 'Aggressor Pro',
        'year': 2019,
        'serial_number': 'GT26006',
        'wheel_size': '26"',
        'frame_size': 'S',
        'color': 'Silver',
        'bike_type': 'mountain',
        'front_hub_spacing_mm': 100.0,
        'rear_hub_spacing_mm': 135.0,
        'spoke_count': 32,
        'purchase_price': 280000,
        'notes': 'Classic 26" MTB with QR spacing (100/135mm)',
      },

      // Road Bikes - 700c (100mm front, 142mm rear disc)
      {
        'tenant_id': tenantId,
        'customer_id': inventoryCustomerId,
        'brand': 'Cervélo',
        'model': 'R3 Ultegra',
        'year': 2024,
        'serial_number': 'CRV700007',
        'wheel_size': '700c',
        'frame_size': '54cm',
        'color': 'Matte Carbon',
        'bike_type': 'road',
        'front_hub_spacing_mm': 100.0,
        'rear_hub_spacing_mm': 142.0,
        'spoke_count': 28,
        'purchase_price': 2800000,
        'notes': 'High-performance road bike, disc brake spacing (100/142mm)',
      },
      {
        'tenant_id': tenantId,
        'customer_id': inventoryCustomerId,
        'brand': 'Bianchi',
        'model': 'Via Nirone 7',
        'year': 2023,
        'serial_number': 'BNC700008',
        'wheel_size': '700c',
        'frame_size': '55cm',
        'color': 'Celeste',
        'bike_type': 'road',
        'front_hub_spacing_mm': 100.0,
        'rear_hub_spacing_mm': 130.0,
        'spoke_count': 28,
        'purchase_price': 980000,
        'notes': 'Classic Italian road bike, rim brake spacing (100/130mm)',
      },
      {
        'tenant_id': tenantId,
        'customer_id': inventoryCustomerId,
        'brand': 'Canyon',
        'model': 'Endurace CF SL 7',
        'year': 2024,
        'serial_number': 'CNY700009',
        'wheel_size': '700c',
        'frame_size': '56cm',
        'color': 'Stealth Grey',
        'bike_type': 'road',
        'front_hub_spacing_mm': 100.0,
        'rear_hub_spacing_mm': 142.0,
        'spoke_count': 28,
        'purchase_price': 1600000,
        'notes': 'Endurance road bike with disc brakes (100/142mm)',
      },

      // Gravel Bike - 700c (32H for durability, 142mm rear)
      {
        'tenant_id': tenantId,
        'customer_id': inventoryCustomerId,
        'brand': 'Specialized',
        'model': 'Diverge E5 Comp',
        'year': 2024,
        'serial_number': 'SPZ700010',
        'wheel_size': '700c',
        'frame_size': '54cm',
        'color': 'Forest Green',
        'bike_type': 'gravel',
        'front_hub_spacing_mm': 100.0,
        'rear_hub_spacing_mm': 142.0,
        'spoke_count': 32,
        'purchase_price': 1350000,
        'notes': 'Gravel/adventure bike, disc brake spacing (100/142mm)',
      },
    ];

    await supabase.from('bikes').insert(bikesData);

    print('✅ Added ${bikesData.length} bikes');

    // ============================================================================
    // 2. HUBS - Front and Rear for different standards
    // ============================================================================

    print('📦 Adding hubs...');

    final hubsData = [
      // 32H Hubs (most common for MTB)
      {
        'tenant_id': tenantId,
        'name': 'Shimano Deore M6010 Front 32H',
        'manufacturer': 'Shimano',
        'spoke_holes': 32,
        'hub_type': 'front',
        'old_mm': 110.0,
        'left_flange_diameter_mm': 50.0,
        'right_flange_diameter_mm': 50.0,
        'center_to_left_flange_mm': 28.0,
        'center_to_right_flange_mm': 20.0,
        'axle_type': 'thru_axle_15mm',
        'brake_type': 'disc_6bolt',
        'driver_type': 'none',
        'notes': 'Asymmetric front hub for disc brakes, Boost spacing',
      },
      {
        'tenant_id': tenantId,
        'name': 'Shimano Deore M6010 Rear 32H',
        'manufacturer': 'Shimano',
        'spoke_holes': 32,
        'hub_type': 'rear',
        'old_mm': 148.0,
        'left_flange_diameter_mm': 53.0,
        'right_flange_diameter_mm': 53.0,
        'center_to_left_flange_mm': 30.0,
        'center_to_right_flange_mm': 18.0,
        'axle_type': 'thru_axle_12mm',
        'brake_type': 'disc_6bolt',
        'driver_type': 'cassette',
        'notes': 'Asymmetric rear hub for Boost spacing (12x148mm)',
      },
      {
        'tenant_id': tenantId,
        'name': 'Hope Pro 4 Front 32H',
        'manufacturer': 'Hope',
        'spoke_holes': 32,
        'hub_type': 'front',
        'old_mm': 110.0,
        'left_flange_diameter_mm': 58.0,
        'right_flange_diameter_mm': 58.0,
        'center_to_left_flange_mm': 28.0,
        'center_to_right_flange_mm': 21.0,
        'axle_type': 'thru_axle_15mm',
        'brake_type': 'disc_centerlock',
        'driver_type': 'none',
        'notes': 'Premium British hub with loud engagement, Boost',
      },
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss 350 Rear 32H',
        'manufacturer': 'DT Swiss',
        'spoke_holes': 32,
        'hub_type': 'rear',
        'old_mm': 142.0,
        'left_flange_diameter_mm': 55.0,
        'right_flange_diameter_mm': 55.0,
        'center_to_left_flange_mm': 31.0,
        'center_to_right_flange_mm': 17.5,
        'axle_type': 'thru_axle_12mm',
        'brake_type': 'disc_centerlock',
        'driver_type': 'cassette',
        'notes': 'Swiss precision, reliable workhorse (12x142mm)',
      },
      {
        'tenant_id': tenantId,
        'name': 'Industry Nine Hydra Rear 32H',
        'manufacturer': 'Industry Nine',
        'spoke_holes': 32,
        'hub_type': 'rear',
        'old_mm': 148.0,
        'left_flange_diameter_mm': 56.0,
        'right_flange_diameter_mm': 56.0,
        'center_to_left_flange_mm': 29.5,
        'center_to_right_flange_mm': 18.5,
        'axle_type': 'thru_axle_12mm',
        'brake_type': 'disc_6bolt',
        'driver_type': 'cassette',
        'notes': 'Instant engagement, USA-made premium hub, Boost',
      },

      // 28H Hubs (common for road/gravel)
      {
        'tenant_id': tenantId,
        'name': 'Shimano Ultegra R8170 Front 28H',
        'manufacturer': 'Shimano',
        'spoke_holes': 28,
        'hub_type': 'front',
        'old_mm': 100.0,
        'left_flange_diameter_mm': 45.0,
        'right_flange_diameter_mm': 45.0,
        'center_to_left_flange_mm': 26.0,
        'center_to_right_flange_mm': 19.0,
        'axle_type': 'thru_axle_12mm',
        'brake_type': 'disc_centerlock',
        'driver_type': 'none',
        'notes': 'Road disc brake hub, asymmetric (12x100mm)',
      },
      {
        'tenant_id': tenantId,
        'name': 'Hope Pro 4 Rear 28H',
        'manufacturer': 'Hope',
        'spoke_holes': 28,
        'hub_type': 'rear',
        'old_mm': 142.0,
        'left_flange_diameter_mm': 56.0,
        'right_flange_diameter_mm': 56.0,
        'center_to_left_flange_mm': 28.0,
        'center_to_right_flange_mm': 19.0,
        'axle_type': 'thru_axle_12mm',
        'brake_type': 'disc_centerlock',
        'driver_type': 'cassette',
        'notes': 'Road/gravel rear hub (12x142mm)',
      },
      {
        'tenant_id': tenantId,
        'name': 'Chris King R45D Rear 28H',
        'manufacturer': 'Chris King',
        'spoke_holes': 28,
        'hub_type': 'rear',
        'old_mm': 142.0,
        'left_flange_diameter_mm': 54.0,
        'right_flange_diameter_mm': 54.0,
        'center_to_left_flange_mm': 27.5,
        'center_to_right_flange_mm': 18.5,
        'axle_type': 'thru_axle_12mm',
        'brake_type': 'disc_6bolt',
        'driver_type': 'cassette',
        'notes': 'Legendary durability, made in USA (12x142mm)',
      },

      // 24H Hubs (lightweight road)
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss 350 Front 24H',
        'manufacturer': 'DT Swiss',
        'spoke_holes': 24,
        'hub_type': 'front',
        'old_mm': 100.0,
        'left_flange_diameter_mm': 43.0,
        'right_flange_diameter_mm': 43.0,
        'center_to_left_flange_mm': 25.0,
        'center_to_right_flange_mm': 18.0,
        'axle_type': 'thru_axle_12mm',
        'brake_type': 'disc_centerlock',
        'driver_type': 'none',
        'notes': 'Lightweight road front hub (12x100mm)',
      },
      {
        'tenant_id': tenantId,
        'name': 'Campagnolo Shamal Ultra Rear 24H',
        'manufacturer': 'Campagnolo',
        'spoke_holes': 24,
        'hub_type': 'rear',
        'old_mm': 142.0,
        'left_flange_diameter_mm': 51.0,
        'right_flange_diameter_mm': 51.0,
        'center_to_left_flange_mm': 26.0,
        'center_to_right_flange_mm': 17.0,
        'axle_type': 'thru_axle_12mm',
        'brake_type': 'disc_centerlock',
        'driver_type': 'cassette',
        'notes': 'Italian racing hub, ultra-light (12x142mm)',
      },
    ];

    await supabase.from('wheel_hubs').insert(hubsData);

    print('✅ Added ${hubsData.length} hubs');

    // ============================================================================
    // 4. SPOKES - Common lengths
    // ============================================================================

    print('📦 Adding spokes...');

    final spokesData = [
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss Competition 2.0/1.8mm 290mm Black',
        'manufacturer': 'DT Swiss',
        'length_mm': 290,
        'gauge': 2.0,
        'is_butted': true,
        'material': 'stainless_steel',
        'finish': 'black',
        'head_type': 'j_bend',
        'notes': 'Butted 2.0/1.8mm, lightweight race spoke',
      },
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss Competition 2.0/1.8mm 292mm Black',
        'manufacturer': 'DT Swiss',
        'length_mm': 292,
        'gauge': 2.0,
        'is_butted': true,
        'material': 'stainless_steel',
        'finish': 'black',
        'head_type': 'j_bend',
        'notes': 'Butted 2.0/1.8mm, lightweight race spoke',
      },
      {
        'tenant_id': tenantId,
        'name': 'Sapim Race 2.0/1.8mm 294mm Silver',
        'manufacturer': 'Sapim',
        'length_mm': 294,
        'gauge': 2.0,
        'is_butted': true,
        'material': 'stainless_steel',
        'finish': 'silver',
        'head_type': 'j_bend',
        'notes': 'Butted 2.0/1.8mm, Belgian quality',
      },
      {
        'tenant_id': tenantId,
        'name': 'Sapim Race 2.0/1.8mm 296mm Silver',
        'manufacturer': 'Sapim',
        'length_mm': 296,
        'gauge': 2.0,
        'is_butted': true,
        'material': 'stainless_steel',
        'finish': 'silver',
        'head_type': 'j_bend',
        'notes': 'Butted 2.0/1.8mm, Belgian quality',
      },
      {
        'tenant_id': tenantId,
        'name': 'Pillar PSR 1432 2.0/1.4/2.0mm 298mm Black',
        'manufacturer': 'Pillar',
        'length_mm': 298,
        'gauge': 2.0,
        'is_butted': true,
        'material': 'stainless_steel',
        'finish': 'black',
        'head_type': 'j_bend',
        'notes': 'Triple butted 2.0/1.4/2.0mm, very lightweight',
      },
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss Champion 2.0mm 290mm Silver',
        'manufacturer': 'DT Swiss',
        'length_mm': 290,
        'gauge': 2.0,
        'is_butted': false,
        'material': 'stainless_steel',
        'finish': 'silver',
        'head_type': 'j_bend',
        'notes': 'Straight gauge 2.0mm, affordable workhorse',
      },
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss Champion 2.0mm 292mm Silver',
        'manufacturer': 'DT Swiss',
        'length_mm': 292,
        'gauge': 2.0,
        'is_butted': false,
        'material': 'stainless_steel',
        'finish': 'silver',
        'head_type': 'j_bend',
        'notes': 'Straight gauge 2.0mm, affordable workhorse',
      },
      {
        'tenant_id': tenantId,
        'name': 'Sapim Strong 2.3mm 294mm Black',
        'manufacturer': 'Sapim',
        'length_mm': 294,
        'gauge': 2.3,
        'is_butted': false,
        'material': 'stainless_steel',
        'finish': 'black',
        'head_type': 'j_bend',
        'notes': 'Thick 2.3mm for tandem/DH use',
      },
      {
        'tenant_id': tenantId,
        'name': 'Sapim Strong 2.3mm 296mm Black',
        'manufacturer': 'Sapim',
        'length_mm': 296,
        'gauge': 2.3,
        'is_butted': false,
        'material': 'stainless_steel',
        'finish': 'black',
        'head_type': 'j_bend',
        'notes': 'Thick 2.3mm for tandem/DH use',
      },
      {
        'tenant_id': tenantId,
        'name': 'DT Swiss Aerolite 2.0/1.5mm 298mm Black',
        'manufacturer': 'DT Swiss',
        'length_mm': 298,
        'gauge': 2.0,
        'is_butted': true,
        'material': 'stainless_steel',
        'finish': 'black',
        'head_type': 'straight_pull',
        'notes': 'Ultra-light butted 2.0/1.5mm, straight-pull',
      },
    ];

    await supabase.from('wheel_spokes').insert(spokesData);

    print('✅ Added ${spokesData.length} spokes');

    // ============================================================================
    // 5. SUMMARY
    // ============================================================================

    print('\n✨ Seed complete! Summary:');
    print('  🚴 Bikes: ${bikesData.length}');
    print('     - 3x 29" MTB');
    print('     - 2x 27.5" MTB');
    print('     - 1x 26" MTB');
    print('     - 3x 700c Road');
    print('     - 1x 700c Gravel');
    print('  📦 Hubs: ${hubsData.length}');
    print('     - 5x 32H (MTB common)');
    print('     - 3x 28H (Road/Gravel)');
    print('     - 2x 24H (Lightweight road)');
    print('  📦 Rims: ${rimsData.length}');
    print('     - 3x 29" (28H, 32H options)');
    print('     - 2x 27.5" (28H, 32H)');
    print('     - 2x 26" (32H, 36H)');
    print('     - 3x 700c (24H, 28H, 32H)');
    print('  📦 Spokes: ${spokesData.length}');
    print('     - Range: 290-298mm');
    print('     - Brands: DT Swiss, Sapim, Pillar');
    print('\n🎯 Ready to test the Smart Wizard!');
    print('   Navigate to Taller → Wheel Builder Wizard');
    print('   1. Select a bike (e.g., Trek X-Caliber 8 29")');
    print('   2. Choose build type (Full/Replace Hub/Replace Rim)');
    print('   3. See automatic filtering in action!');
  } catch (e, stackTrace) {
    print('❌ Error seeding data: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
}
