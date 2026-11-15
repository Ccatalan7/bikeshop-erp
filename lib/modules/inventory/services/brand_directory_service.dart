import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/brand_directory.dart';

/// De dónde leen la lista de marcas y la página de una marca. Las pruebas
/// ponen la suya; la app lee las dos funciones de la base.
abstract class BrandDirectorySource {
  Future<List<BrandDirectoryEntry>> directory();

  /// `null` cuando el taller no ve esa marca (borrada o de otro taller).
  Future<BrandPageData?> page(String brandId);
}

/// `brand_directory_v1` y `brand_page_v1` (20261115101500): cada una trae lo
/// suyo en un solo viaje, con el taller del usuario y su membresía comprobada
/// en la base.
class BrandDirectoryService implements BrandDirectorySource {
  BrandDirectoryService({SupabaseClient? client, TenantService? tenantService})
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

  @override
  Future<List<BrandDirectoryEntry>> directory() async {
    final result = await _client.rpc('brand_directory_v1', params: {
      'p_tenant_id': await _tenantId(),
    });
    return BrandDirectoryEntry.listFromJson(result);
  }

  @override
  Future<BrandPageData?> page(String brandId) async {
    final result = await _client.rpc('brand_page_v1', params: {
      'p_tenant_id': await _tenantId(),
      'p_brand_id': brandId,
    });
    if (result is! Map || result['brand'] is! Map) return null;
    return BrandPageData.fromJson(Map<String, dynamic>.from(result));
  }
}
