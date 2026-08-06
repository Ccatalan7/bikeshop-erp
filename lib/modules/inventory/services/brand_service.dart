import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/authority_scoped_cache.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../models/brand_models.dart';

class BrandService extends ChangeNotifier {
  final DatabaseService _db;
  final TenantService _tenantService;

  // ============================================================
  // CACHING - Avoid refetching on every page navigation
  // ============================================================
  List<ProductBrand>? _cachedBrands;
  DateTime? _brandsCacheTime;
  static const Duration _cacheMaxAge = Duration(minutes: 5);
  final AuthorityCacheScope _cacheScope = AuthorityCacheScope();
  late final AuthorityScopedLoad<List<ProductBrand>> _brandsLoad =
      AuthorityScopedLoad<List<ProductBrand>>(_cacheScope);

  // Public getters for cached data (instant access)
  List<ProductBrand> get cachedBrands => _cachedBrands ?? [];
  bool get hasBrandsCache => _cachedBrands != null;
  ErpAuthorityScopeKey? get authorityScope => _cacheScope.key;

  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheMaxAge;
  }

  void invalidateBrandsCache() {
    _cacheScope.invalidate();
    _brandsLoad.detach();
    _cachedBrands = null;
    _brandsCacheTime = null;
  }

  BrandService(
    this._db, {
    TenantService? tenantService,
  }) : _tenantService = tenantService ?? TenantService();

  void bindAuthorityScope({
    required String? userId,
    required String? tenantId,
  }) {
    if (!_cacheScope.bind(userId: userId, tenantId: tenantId)) return;
    _clearAuthorityOwnedState();
  }

  AuthorityScopeResolution _resolveAuthorityScope({
    required String? userId,
    required String? tenantId,
  }) {
    final resolution = _cacheScope.resolve(
      userId: userId,
      tenantId: tenantId,
    );
    if (resolution.didChange) _clearAuthorityOwnedState();
    return resolution;
  }

  void _clearAuthorityOwnedState() {
    final hadCache = _cachedBrands != null;
    _brandsLoad.detach();
    _cachedBrands = null;
    _brandsCacheTime = null;
    if (hadCache) notifyListeners();
  }

  Future<bool> _ensureAuthorityScope() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _resolveAuthorityScope(userId: null, tenantId: null);
      return false;
    }

    final tenantId = await _tenantService.getTenantId();
    if (Supabase.instance.client.auth.currentUser?.id != userId) return false;
    if (tenantId == null || tenantId.isEmpty) {
      _resolveAuthorityScope(userId: null, tenantId: null);
      return false;
    }
    final resolution = _resolveAuthorityScope(
      userId: userId,
      tenantId: tenantId,
    );
    if (resolution == AuthorityScopeResolution.rejectedTenantChange) {
      throw const AuthorityScopeChangedException();
    }
    return resolution.isAccepted;
  }

  Future<List<ProductBrand>> getBrands({
    String? searchTerm,
    bool? activeOnly,
    bool forceRefresh = false,
  }) async {
    if (!await _ensureAuthorityScope()) {
      throw const AuthorityScopeChangedException();
    }
    final isFilteredQuery =
        (searchTerm != null && searchTerm.trim().isNotEmpty) ||
            activeOnly == true;

    if (!forceRefresh &&
        !isFilteredQuery &&
        _isCacheValid(_brandsCacheTime) &&
        _cachedBrands != null) {
      return _cachedBrands!;
    }

    if (isFilteredQuery) {
      final lease = _cacheScope.capture();
      if (lease == null) throw const AuthorityScopeChangedException();
      final brands = await _loadBrands(
        searchTerm: searchTerm,
        activeOnly: activeOnly,
        expectedTenantId: lease.scope.tenantId,
      );
      if (!_cacheScope.owns(lease)) {
        throw const AuthorityScopeChangedException();
      }
      return brands;
    }

    return _brandsLoad.run(
      load: (lease) => _loadBrands(
        expectedTenantId: lease.scope.tenantId,
      ),
      publish: (brands, _) {
        _cachedBrands = brands;
        _brandsCacheTime = DateTime.now();
      },
    );
  }

  Future<List<ProductBrand>> _loadBrands({
    String? searchTerm,
    bool? activeOnly,
    required String expectedTenantId,
  }) async {
    List<Map<String, dynamic>> data;
    if (searchTerm != null && searchTerm.trim().isNotEmpty) {
      final normalizedTerm = searchTerm.trim();
      final nameResults =
          await _db.searchRecords('product_brands', 'name', normalizedTerm);
      final descResults = await _db.searchRecords(
        'product_brands',
        'description',
        normalizedTerm,
      );
      final ids = <String>{};
      data = [...nameResults, ...descResults]
          .where((item) {
            final id = item['id']?.toString();
            return id != null && ids.add(id);
          })
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } else {
      data = (await _db.select('product_brands'))
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }

    var brands = data.map(ProductBrand.fromJson).toList();
    // Una marca sin tenant es catálogo compartido, no una fuga de otro
    // tenant: el listado sembrado (Shimano, Bucklos, Zoom…) nace así y son
    // 137 de las 146 marcas en producción. Exigirles tenant hacía fallar la
    // carga completa y con ella la creación de productos desde OCR —el panel
    // no abría y parecía que el botón no respondía— (2026-08-06). Lo que sí
    // es un defecto de aislamiento, y sigue fallando cerrado, es una marca
    // que pertenece a OTRO tenant.
    // `ProductBrand.tenantId` es cadena vacía cuando la fila no trae tenant.
    final hasForeignBrand = brands.any(
      (brand) =>
          brand.tenantId.isNotEmpty && brand.tenantId != expectedTenantId,
    );
    if (hasForeignBrand) {
      throw StateError(
        'Brand query returned data outside the authority tenant',
      );
    }
    if (activeOnly == true) {
      brands = brands.where((brand) => brand.isActive).toList();
    }
    brands.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return brands;
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
      invalidateBrandsCache();
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
      invalidateBrandsCache();
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
      invalidateBrandsCache();
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
