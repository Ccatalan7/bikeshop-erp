import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/bike_catalog_models.dart';

/// Service for accessing Bike Catalog (Encyclopedia)
/// This is GLOBAL data - no tenant filtering needed
class BikeCatalogService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  /// Search bikes by brand and/or model
  Future<List<BikeCatalogEntry>> searchBikes({
    String? brand,
    String? model,
    int? year,
    String? bikeType,
  }) async {
    try {
      var query = _supabase.from('bike_catalog').select();
      
      if (brand != null && brand.isNotEmpty) {
        query = query.ilike('brand', '%$brand%');
      }
      
      if (model != null && model.isNotEmpty) {
        query = query.ilike('model_name', '%$model%');
      }
      
      if (year != null) {
        query = query.eq('model_year', year);
      }
      
      if (bikeType != null && bikeType.isNotEmpty) {
        query = query.eq('bike_type', bikeType);
      }
      
      final response = await query
          .order('brand')
          .order('model_name')
          .order('model_year', ascending: false);
      
      final data = response as List;
      
      return data.map((json) => BikeCatalogEntry.fromJson(json)).toList();
    } catch (e) {
      print('Error searching bikes: $e');
      rethrow;
    }
  }
  
  /// Get bike by ID
  Future<BikeCatalogEntry?> getBikeById(String id) async {
    try {
      final response =
          await _supabase.from('bike_catalog').select().eq('id', id).single();
      
      return BikeCatalogEntry.fromJson(response);
    } catch (e) {
      print('Error fetching bike: $e');
      return null;
    }
  }
  
  /// Get all bikes (paginated)
  Future<List<BikeCatalogEntry>> getAllBikes({
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _supabase
          .from('bike_catalog')
          .select()
          .order('brand')
          .order('model_name')
          .order('model_year', ascending: false)
          .range(offset, offset + limit - 1);
      
      final data = response as List;
      return data.map((json) => BikeCatalogEntry.fromJson(json)).toList();
    } catch (e) {
      print('Error fetching bikes: $e');
      rethrow;
    }
  }
  
  /// Get distinct brands
  Future<List<String>> getBrands() async {
    try {
      final response =
          await _supabase.from('bike_catalog').select('brand').order('brand');
      
      final data = response as List;
      final brands =
          data.map((item) => item['brand'] as String).toSet().toList();
      brands.sort();
      return brands;
    } catch (e) {
      print('Error fetching brands: $e');
      rethrow;
    }
  }
  
  /// Get available years
  Future<List<int>> getYears() async {
    try {
      final response = await _supabase
          .from('bike_catalog')
          .select('model_year')
          .order('model_year', ascending: false);
      
      final data = response as List;
      final years =
          data.map((item) => item['model_year'] as int).toSet().toList();
      years.sort((a, b) => b.compareTo(a)); // Descending
      return years;
    } catch (e) {
      print('Error fetching years: $e');
      rethrow;
    }
  }
  
  /// Get total count
  Future<int> getTotalCount() async {
    try {
      final response = await _supabase.from('bike_catalog').select('id');
      
      final data = response as List;
      return data.length;
    } catch (e) {
      print('Error fetching count: $e');
      return 0;
    }
  }
}
