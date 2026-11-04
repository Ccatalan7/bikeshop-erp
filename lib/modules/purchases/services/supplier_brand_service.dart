import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/supplier_brand.dart';

/// Las marcas de los proveedores (`supplier_brands`, 20261103090000): leer
/// las de un proveedor, quién trae una marca, el índice para el buscador del
/// directorio, y agregar, marcar como representante oficial o quitar. La tabla
/// no se escribe directo: todo pasa por sus comandos.
class SupplierBrandService {
  SupplierBrandService({SupabaseClient? client, TenantService? tenantService})
      : _client = client ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService();

  final SupabaseClient _client;
  final TenantService _tenantService;

  Future<String> _tenantId() async {
    final tenantId =
        _tenantService.currentTenantId ?? await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('Sin taller activo');
    }
    return tenantId;
  }

  Future<List<SupplierBrand>> listBrands(String supplierId) async {
    final result = await _client.rpc('supplier_brands_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_supplier_id': supplierId,
    });
    return SupplierBrand.listFromJson(result);
  }

  Future<List<SupplierBrand>> saveBrand(
    String supplierId,
    String brandId, {
    bool? official,
  }) async {
    final result = await _client.rpc('save_supplier_brand_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_supplier_id': supplierId,
      'p_brand_id': brandId,
      'p_official': official,
    });
    return SupplierBrand.listFromJson(result);
  }

  Future<List<SupplierBrand>> removeBrand(
    String supplierId,
    String brandId,
  ) async {
    final result = await _client.rpc('remove_supplier_brand_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_supplier_id': supplierId,
      'p_brand_id': brandId,
    });
    return SupplierBrand.listFromJson(result);
  }

  Future<List<BrandSupplier>> suppliersOf(String brandId) async {
    final result = await _client.rpc('brand_suppliers_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_brand_id': brandId,
    });
    return BrandSupplier.listFromJson(result);
  }

  Future<SupplierBrandIndex> index() async {
    final result = await _client.rpc('supplier_brand_index_v1', params: {
      'p_tenant_id': await _tenantId(),
    });
    return SupplierBrandIndex.fromJson(result);
  }

  /// Las marcas que se pueden asignar: las del taller y las del catálogo
  /// compartido, activas, por nombre. Sin las que no nombran a un fabricante,
  /// que la base rechaza (`product_brand_is_placeholder_internal`).
  Future<List<SupplierBrandOption>> brandOptions() async {
    final tenantId = await _tenantId();
    final rows = await _client
        .from('product_brands')
        .select('id,name')
        .eq('is_active', true)
        .or('tenant_id.is.null,tenant_id.eq.$tenantId')
        .order('name');
    return [
      for (final row in rows as List)
        if (row is Map && !isPlaceholderBrandName(row['name']?.toString()))
          SupplierBrandOption(
            id: row['id'].toString(),
            name: row['name'].toString(),
          ),
    ];
  }

  /// Crea una marca del taller, como Inventario › Marcas › Nueva. Quien llama
  /// ya buscó el nombre en [brandOptions] sin distinguir mayúsculas; si igual
  /// existe (el nombre es único en el catálogo), devuelve esa.
  Future<SupplierBrandOption> createBrand(String name) async {
    final tenantId = await _tenantId();
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) throw ArgumentError('Nombre vacío');
    try {
      final created = await _client
          .from('product_brands')
          .insert({'tenant_id': tenantId, 'name': clean, 'is_active': true})
          .select('id,name')
          .single();
      return SupplierBrandOption(
        id: created['id'].toString(),
        name: created['name'].toString(),
      );
    } on PostgrestException catch (error) {
      if (error.code != '23505') rethrow;
      final existing = await _client
          .from('product_brands')
          .select('id,name')
          .eq('name', clean)
          .single();
      return SupplierBrandOption(
        id: existing['id'].toString(),
        name: existing['name'].toString(),
      );
    }
  }
}

/// La misma lista que `product_brand_is_placeholder_internal`: Genérico, Sin
/// marca, un país o la tienda donde se compró no nombran a un fabricante.
bool isPlaceholderBrandName(String? name) {
  final normalized = (name ?? '').trim().toLowerCase();
  return const {
    '',
    'genérico',
    'generico',
    'genérica',
    'generica',
    'sin marca',
    'china',
    'taiwán',
    'taiwan',
    'aliexpress',
  }.contains(normalized);
}

/// Lo que el operador lee cuando un cambio de marcas no se pudo hacer.
String supplierBrandErrorMessage(Object error) {
  if (error is PostgrestException) {
    switch (error.hint) {
      case 'supplier_brand_placeholder':
        return 'Esa no es una marca: es un genérico, un país o una tienda.';
      case 'supplier_brand_inactive':
        return 'Esa marca está desactivada en Inventario › Marcas.';
      case 'supplier_brand_not_found':
        return 'No encontramos esa marca en el catálogo.';
      case 'supplier_not_found':
        return 'No encontramos este proveedor.';
    }
    if (error.code == '42501') {
      return 'Tu cuenta no puede cambiar las marcas de este proveedor.';
    }
  }
  return 'No se pudo guardar. Revisa la conexión e inténtalo de nuevo.';
}
