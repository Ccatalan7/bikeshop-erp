import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/wheel_building_models.dart';

/// Professional Wheel Building Service
/// Implements spoke length calculation and component compatibility checking
class WheelBuildingService extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final _supabase = Supabase.instance.client;

  // ============================================================================
  // SPOKE LENGTH CALCULATOR - ProWheelBuilder Algorithm
  // ============================================================================

  /// Calculate spoke length using the ProWheelBuilder formula
  ///
  /// Formula: L = √(R² + H² + D² - 2*R*H*cos(α))
  /// Where:
  ///   R = Rim radius (ERD/2)
  ///   H = Flange radius (Flange Diameter/2)
  ///   D = Distance from wheel center to flange
  ///   α = Spoke angle based on lacing pattern
  double calculateSpokeLength({
    required double erdMm,
    required double flangeDiameterMm,
    required double centerToFlangeMm,
    required int spokeHoles,
    required int crossPattern, // 0=radial, 1-4=cross
    double spokeHoleDiameterMm = 2.6, // Standard spoke hole diameter
  }) {
    // Validate inputs
    if (erdMm <= 0) throw ArgumentError('Invalid ERD: $erdMm');
    if (spokeHoles != 24 &&
        spokeHoles != 28 &&
        spokeHoles != 32 &&
        spokeHoles != 36 &&
        spokeHoles != 40) {
      throw ArgumentError(
          'Invalid spoke hole count: $spokeHoles. Must be 24, 28, 32, 36, or 40');
    }
    if (crossPattern < 0 || crossPattern > 4) {
      throw ArgumentError('Invalid cross pattern: $crossPattern. Must be 0-4');
    }

    // Pro Wheel Builder Formula (from official documentation)
    // L = √(R² + F² + C² - 2RF×cos(θ)) - (spoke_hole_diameter / 2)

    // Step 1: Compute radii
    final R = erdMm / 2.0; // Rim radius
    final F = flangeDiameterMm / 2.0; // Flange radius (NOT adjusted)
    final C = centerToFlangeMm; // Flange-to-center distance

    // Step 2: Compute spoke angle (θ)
    // θ = 360° × crossPattern / (spokeHoles / 2)
    // This is the angle between spokes on the SAME flange side
    final spokesPerSide = spokeHoles / 2.0;
    final thetaDegrees = (360.0 * crossPattern) / spokesPerSide;
    final theta = thetaDegrees * (math.pi / 180.0); // Convert to radians

    // Step 3: Apply law of cosines
    final uncorrectedLength = math
        .sqrt((R * R) + (F * F) + (C * C) - (2.0 * R * F * math.cos(theta)));

    // Step 4: Apply spoke hole offset correction
    // Subtract half the spoke hole diameter because the spoke sits at the hole edge
    final spokeHoleCorrection = spokeHoleDiameterMm / 2.0;
    final spokeLength = uncorrectedLength - spokeHoleCorrection;

    // Round to 0.1mm precision
    return (spokeLength * 10).round() / 10.0;
  }

  /// Calculate spoke lengths for both sides of a wheel (asymmetric rear hub)
  Map<String, double> calculateAsymmetricSpokeLength({
    required double erdMm,
    required double leftFlangeDiameterMm,
    required double rightFlangeDiameterMm,
    required double centerToLeftFlangeMm,
    required double centerToRightFlangeMm,
    required int spokeHoles,
    required int crossPattern,
  }) {
    final leftLength = calculateSpokeLength(
      erdMm: erdMm,
      flangeDiameterMm: leftFlangeDiameterMm,
      centerToFlangeMm: centerToLeftFlangeMm,
      spokeHoles: spokeHoles,
      crossPattern: crossPattern,
    );

    final rightLength = calculateSpokeLength(
      erdMm: erdMm,
      flangeDiameterMm: rightFlangeDiameterMm,
      centerToFlangeMm: centerToRightFlangeMm,
      spokeHoles: spokeHoles,
      crossPattern: crossPattern,
    );

    return {
      'left': leftLength,
      'right': rightLength,
    };
  }

  // ============================================================================
  // HUB CRUD OPERATIONS
  // ============================================================================

  Future<List<WheelHub>> getHubs(
      {String? hubType, bool activeOnly = true}) async {
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) throw Exception('No tenant ID');

      var query =
          _supabase.from('wheel_hubs').select().eq('tenant_id', tenantId);

      if (activeOnly) {
        query = query.eq('is_active', true);
      }

      if (hubType != null) {
        query = query.eq('hub_type', hubType);
      }

      final response = await query.order('name');
      return (response as List).map((json) => WheelHub.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting hubs: $e');
      rethrow;
    }
  }

  Future<WheelHub> createHub(WheelHub hub) async {
    try {
      final data = hub.toJson();
      final response = await _db.insert('wheel_hubs', data);
      notifyListeners();
      return WheelHub.fromJson(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error creating hub: $e');
      rethrow;
    }
  }

  Future<WheelHub> updateHub(WheelHub hub) async {
    try {
      final data = hub.toJson();
      final response = await _supabase
          .from('wheel_hubs')
          .update(data)
          .eq('id', hub.id!)
          .select()
          .single();
      notifyListeners();
      return WheelHub.fromJson(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error updating hub: $e');
      rethrow;
    }
  }

  Future<void> deleteHub(String id) async {
    try {
      await _supabase.from('wheel_hubs').delete().eq('id', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting hub: $e');
      rethrow;
    }
  }

  // ============================================================================
  // RIM CRUD OPERATIONS
  // ============================================================================

  Future<List<WheelRim>> getRims(
      {String? wheelSize, bool activeOnly = true}) async {
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) throw Exception('No tenant ID');

      var query =
          _supabase.from('wheel_rims').select().eq('tenant_id', tenantId);

      if (activeOnly) {
        query = query.eq('is_active', true);
      }

      if (wheelSize != null) {
        query = query.eq('wheel_size', wheelSize);
      }

      final response = await query.order('name');
      return (response as List).map((json) => WheelRim.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting rims: $e');
      rethrow;
    }
  }

  Future<WheelRim> createRim(WheelRim rim) async {
    try {
      final data = rim.toJson();
      final response = await _db.insert('wheel_rims', data);
      notifyListeners();
      return WheelRim.fromJson(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error creating rim: $e');
      rethrow;
    }
  }

  Future<WheelRim> updateRim(WheelRim rim) async {
    try {
      final data = rim.toJson();
      final response = await _supabase
          .from('wheel_rims')
          .update(data)
          .eq('id', rim.id!)
          .select()
          .single();
      notifyListeners();
      return WheelRim.fromJson(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error updating rim: $e');
      rethrow;
    }
  }

  Future<void> deleteRim(String id) async {
    try {
      await _supabase.from('wheel_rims').delete().eq('id', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting rim: $e');
      rethrow;
    }
  }

  // ============================================================================
  // SPOKE CRUD OPERATIONS
  // ============================================================================

  Future<List<WheelSpoke>> getSpokes(
      {int? lengthMm, bool activeOnly = true}) async {
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) throw Exception('No tenant ID');

      var query =
          _supabase.from('wheel_spokes').select().eq('tenant_id', tenantId);

      if (activeOnly) {
        query = query.eq('is_active', true);
      }

      if (lengthMm != null) {
        query = query.eq('length_mm', lengthMm);
      }

      final response = await query.order('length_mm');
      return (response as List)
          .map((json) => WheelSpoke.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting spokes: $e');
      rethrow;
    }
  }

  Future<WheelSpoke> createSpoke(WheelSpoke spoke) async {
    try {
      final data = spoke.toJson();
      final response = await _db.insert('wheel_spokes', data);
      notifyListeners();
      return WheelSpoke.fromJson(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error creating spoke: $e');
      rethrow;
    }
  }

  Future<WheelSpoke> updateSpoke(WheelSpoke spoke) async {
    try {
      final data = spoke.toJson();
      final response = await _supabase
          .from('wheel_spokes')
          .update(data)
          .eq('id', spoke.id!)
          .select()
          .single();
      notifyListeners();
      return WheelSpoke.fromJson(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error updating spoke: $e');
      rethrow;
    }
  }

  Future<void> deleteSpoke(String id) async {
    try {
      await _supabase.from('wheel_spokes').delete().eq('id', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting spoke: $e');
      rethrow;
    }
  }

  // ============================================================================
  // COMPATIBILITY FINDER - The Magic Sauce
  // ============================================================================

  /// Find compatible hubs for a given rim
  Future<List<Map<String, dynamic>>> findCompatibleHubs({
    required String rimId,
    String? bikeOldMm,
    String hubType = 'rear',
  }) async {
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) throw Exception('No tenant ID');

      final response = await _supabase.rpc(
        'find_compatible_hubs',
        params: {
          'p_tenant_id': tenantId,
          'p_rim_id': rimId,
          if (bikeOldMm != null) 'p_bike_old_mm': double.parse(bikeOldMm),
          'p_hub_type': hubType,
        },
      );

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('❌ Error finding compatible hubs: $e');
      rethrow;
    }
  }

  /// Find compatible spokes for a required spoke length
  Future<List<Map<String, dynamic>>> findCompatibleSpokes({
    required double requiredLengthMm,
    double toleranceMm = 2.0,
  }) async {
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) throw Exception('No tenant ID');

      final response = await _supabase.rpc(
        'find_compatible_spokes',
        params: {
          'p_tenant_id': tenantId,
          'p_required_length_mm': requiredLengthMm,
          'p_tolerance_mm': toleranceMm,
        },
      );

      return (response as List).cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('❌ Error finding compatible spokes: $e');
      rethrow;
    }
  }

  // ============================================================================
  // WHEEL BUILD OPERATIONS
  // ============================================================================

  Future<List<WheelBuild>> getWheelBuilds(
      {String? bikeId, bool templatesOnly = false}) async {
    try {
      final tenantId = await TenantService().getTenantId();
      if (tenantId == null) throw Exception('No tenant ID');

      var query =
          _supabase.from('wheel_builds').select().eq('tenant_id', tenantId);

      if (bikeId != null) {
        query = query.eq('bike_id', bikeId);
      }

      if (templatesOnly) {
        query = query.eq('is_template', true);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List)
          .map((json) => WheelBuild.fromJson(json))
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error getting wheel builds: $e');
      rethrow;
    }
  }

  Future<WheelBuild> createWheelBuild(WheelBuild build) async {
    try {
      final data = build.toJson();
      final response = await _db.insert('wheel_builds', data);
      notifyListeners();
      return WheelBuild.fromJson(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error creating wheel build: $e');
      rethrow;
    }
  }

  Future<WheelBuild> updateWheelBuild(WheelBuild build) async {
    try {
      final data = build.toJson();
      final response = await _supabase
          .from('wheel_builds')
          .update(data)
          .eq('id', build.id!)
          .select()
          .single();
      notifyListeners();
      return WheelBuild.fromJson(response);
    } catch (e) {
      if (kDebugMode) print('❌ Error updating wheel build: $e');
      rethrow;
    }
  }

  Future<void> deleteWheelBuild(String id) async {
    try {
      await _supabase.from('wheel_builds').delete().eq('id', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Error deleting wheel build: $e');
      rethrow;
    }
  }

  // ============================================================================
  // WIZARD - Complete Wheel Build Workflow
  // ============================================================================

  /// Calculate complete wheel build with spoke recommendations
  Future<Map<String, dynamic>> calculateWheelBuild({
    required WheelHub hub,
    required WheelRim rim,
    required int crossPattern,
  }) async {
    try {
      // Validate compatibility
      if (hub.spokeHoles != rim.spokeHoles) {
        throw Exception(
            'Hub and rim spoke hole count must match! Hub: ${hub.spokeHoles}, Rim: ${rim.spokeHoles}');
      }

      // Calculate spoke lengths
      final spokeLengths = calculateAsymmetricSpokeLength(
        erdMm: rim.erdMm,
        leftFlangeDiameterMm: hub.leftFlangeDiameterMm,
        rightFlangeDiameterMm: hub.rightFlangeDiameterMm,
        centerToLeftFlangeMm: hub.centerToLeftFlangeMm,
        centerToRightFlangeMm: hub.centerToRightFlangeMm,
        spokeHoles: hub.spokeHoles,
        crossPattern: crossPattern,
      );

      // Find compatible spokes in inventory
      final leftSpokes = await findCompatibleSpokes(
        requiredLengthMm: spokeLengths['left']!,
      );

      final rightSpokes = await findCompatibleSpokes(
        requiredLengthMm: spokeLengths['right']!,
      );

      return {
        'hub': hub,
        'rim': rim,
        'spoke_holes': hub.spokeHoles,
        'cross_pattern': crossPattern,
        'left_spoke_length_mm': spokeLengths['left']!,
        'right_spoke_length_mm': spokeLengths['right']!,
        'compatible_left_spokes': leftSpokes,
        'compatible_right_spokes': rightSpokes,
        'total_spokes_needed': hub.spokeHoles,
        'lacing_pattern': _getCrossPatternName(crossPattern),
      };
    } catch (e) {
      if (kDebugMode) print('❌ Error calculating wheel build: $e');
      rethrow;
    }
  }

  String _getCrossPatternName(int pattern) {
    switch (pattern) {
      case 0:
        return 'Radial';
      case 1:
        return '1-Cross';
      case 2:
        return '2-Cross';
      case 3:
        return '3-Cross';
      case 4:
        return '4-Cross';
      default:
        return '$pattern-Cross';
    }
  }
}
