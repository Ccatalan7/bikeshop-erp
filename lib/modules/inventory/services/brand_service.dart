import 'package:flutter/foundation.dart';

import '../../../shared/services/database_service.dart';
import '../models/brand_models.dart';

class BrandService extends ChangeNotifier {
  final DatabaseService _db;

  BrandService(this._db);

  Future<List<ProductBrand>> getBrands({
    String? searchTerm,
    bool? activeOnly,
  }) async {
    try {
      List<Map<String, dynamic>> data;

      if (searchTerm != null && searchTerm.trim().isNotEmpty) {
        final normalizedTerm = searchTerm.trim();
        final nameResults =
            await _db.searchRecords('product_brands', 'name', normalizedTerm);
        final descResults = await _db.searchRecords(
            'product_brands', 'description', normalizedTerm);

        final ids = <String>{};
        data = [...nameResults, ...descResults]
            .where((item) {
              final id = item['id']?.toString();
              if (id == null) return false;
              return ids.add(id);
            })
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      } else {
    data = (await _db.select('product_brands'))
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
      }

      var brands = data.map(ProductBrand.fromJson).toList();

      if (activeOnly == true) {
        brands = brands.where((brand) => brand.isActive).toList();
      }

      brands.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return brands;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching brands: $e');
      }
      rethrow;
    }
  }

  Future<ProductBrand?> getBrandById(String id) async {
    try {
      final data = await _db.selectById('product_brands', id);
      return data != null ? ProductBrand.fromJson(data) : null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching brand by id: $e');
      }
      rethrow;
    }
  }

  Future<ProductBrand?> getBrandByName(String name) async {
    try {
      final normalized = name.trim();
      if (normalized.isEmpty) return null;

      final directMatches = await _db.select(
        'product_brands',
        where: 'name=$normalized',
      );
      if (directMatches.isNotEmpty) {
        return ProductBrand.fromJson(
          Map<String, dynamic>.from(directMatches.first),
        );
      }

      final candidates = await getBrands(searchTerm: normalized);
      for (final brand in candidates) {
        if (brand.name.toLowerCase() == normalized.toLowerCase()) {
          return brand;
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error fetching brand by name: $e');
      }
      rethrow;
    }
  }

  Future<ProductBrand> createBrand(ProductBrand brand) async {
    try {
      final existing = await getBrandByName(brand.name);
      if (existing != null) {
        throw Exception('Ya existe una marca con este nombre');
      }

    final payload = brand.copyWith(
    name: brand.name.trim(),
    description: (brand.description?.trim().isEmpty ?? true)
      ? null
      : brand.description!.trim(),
    website: (brand.website?.trim().isEmpty ?? true)
      ? null
      : brand.website!.trim(),
    country: (brand.country?.trim().isEmpty ?? true)
      ? null
      : brand.country!.trim(),
    );

      final data = await _db.insert('product_brands', payload.toJson());
      final created = ProductBrand.fromJson(data);
      notifyListeners();
      return created;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error creating brand: $e');
      }
      rethrow;
    }
  }

  Future<ProductBrand> updateBrand(ProductBrand brand) async {
    if (brand.id == null) {
      throw Exception('Brand ID is required for update');
    }

    try {
      final existing = await getBrandByName(brand.name);
      if (existing != null && existing.id != brand.id) {
        throw Exception('Ya existe una marca con este nombre');
      }

    final payload = brand.copyWith(
    name: brand.name.trim(),
    description: (brand.description?.trim().isEmpty ?? true)
      ? null
      : brand.description!.trim(),
    website: (brand.website?.trim().isEmpty ?? true)
      ? null
      : brand.website!.trim(),
    country: (brand.country?.trim().isEmpty ?? true)
      ? null
      : brand.country!.trim(),
    updatedAt: DateTime.now(),
    );

      final updated = await _db.update(
        'product_brands',
        brand.id!,
        payload.toJson(),
      );
      notifyListeners();
      return ProductBrand.fromJson(updated);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error updating brand: $e');
      }
      rethrow;
    }
  }

  Future<void> deleteBrand(String id) async {
    try {
      final productsUsingBrand =
          await _db.select('products', where: 'brand_id=$id');
      if (productsUsingBrand.isNotEmpty) {
        throw Exception(
          'No se puede eliminar la marca porque está asociada a ${productsUsingBrand.length} producto(s)',
        );
      }

      await _db.delete('product_brands', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error deleting brand: $e');
      }
      rethrow;
    }
  }

  Future<void> toggleBrandStatus(String id) async {
    try {
      final brand = await getBrandById(id);
      if (brand == null) {
        throw Exception('Marca no encontrada');
      }

      final updated = brand.copyWith(
        isActive: !brand.isActive,
        updatedAt: DateTime.now(),
      );

      await updateBrand(updated);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error toggling brand status: $e');
      }
      rethrow;
    }
  }
}
