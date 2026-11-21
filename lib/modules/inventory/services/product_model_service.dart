import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/product_model_draft.dart';

/// Un guardado del modelo que la base se negó a hacer, en palabras del
/// taller ([message]) y con su código (`product_model_*`).
class ProductModelException implements Exception {
  const ProductModelException(this.code, this.message, {this.productId});

  final String code;
  final String message;

  /// El producto que causó el problema, si fue uno.
  final String? productId;

  @override
  String toString() => message;
}

/// Lee y guarda los modelos con tallas y colores (20261120230000) por sus
/// comandos: las tablas son privadas.
class ProductModelService {
  ProductModelService({SupabaseClient? client, TenantService? tenantService})
      : _client = client ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService();

  final SupabaseClient _client;
  final TenantService _tenantService;

  Future<String> _tenantId() async {
    final tenantId =
        _tenantService.currentTenantId ?? await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No hay una tienda activa en la sesión.');
    }
    return tenantId;
  }

  /// El modelo del producto, o null si está suelto.
  Future<ProductModel?> fetchForProduct(String productId) async {
    final result = await _client.rpc(
      'product_model_for_product_v1',
      params: {'p_tenant_id': await _tenantId(), 'p_product_id': productId},
    );
    return ProductModel.fromJson(result);
  }

  /// Los productos que se pueden sumar: sin [query], los que más se parecen
  /// por nombre a [productId]; con [query], los que lo contienen en el nombre
  /// o el SKU.
  Future<List<ProductModelCandidate>> candidates(
    String productId, {
    String? query,
    int limit = 12,
  }) async {
    final rows = await _client.rpc(
      'product_model_candidates_v1',
      params: {
        'p_tenant_id': await _tenantId(),
        'p_product_id': productId,
        'p_query': (query ?? '').trim(),
        'p_limit': limit,
      },
    );
    return [
      if (rows is List)
        for (final row in rows)
          if (row is Map)
            ProductModelCandidate.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  /// Guarda el modelo entero. Devuelve el guardado, o null si quedó sin
  /// variantes y se borró.
  Future<ProductModel?> save(ProductModelDraft draft) async {
    try {
      final result = await _client.rpc(
        'product_model_save_v1',
        params: {'p_tenant_id': await _tenantId(), 'p_model': draft.toJson()},
      );
      return ProductModel.fromJson(result);
    } on PostgrestException catch (error) {
      throw explain(error, draft);
    }
  }

  /// Desarma el modelo: sus productos quedan sueltos.
  Future<void> delete(String modelId) async {
    try {
      await _client.rpc(
        'product_model_delete_v1',
        params: {'p_tenant_id': await _tenantId(), 'p_model_id': modelId},
      );
    } on PostgrestException catch (error) {
      throw explain(error, null);
    }
  }

  /// Lo que la base dijo, en palabras del taller.
  static ProductModelException explain(
    PostgrestException error,
    ProductModelDraft? draft,
  ) {
    final code = error.message.trim();
    final productId = (error.details ?? '').toString().trim();
    String nameOf(String id) {
      for (final member in draft?.members ?? const <ProductModelMember>[]) {
        if (member.productId == id) return '«${member.name}»';
      }
      return 'un producto';
    }

    return switch (code) {
      'product_model_member_taken' => ProductModelException(
          code,
          '${nameOf(productId)} ya está en otro modelo. Quítalo de ese '
          'modelo primero.',
          productId: productId,
        ),
      'product_model_member_invalid' => ProductModelException(
          code,
          '${nameOf(productId)} no puede ser variante: revisa que sea un '
          'producto de la tienda y que tenga un valor de cada eje.',
          productId: productId,
        ),
      'product_model_duplicate_options' => const ProductModelException(
          'product_model_duplicate_options',
          'Dos variantes tienen la misma combinación.',
        ),
      'product_model_stale' => const ProductModelException(
          'product_model_stale',
          'Otra persona cambió este modelo mientras lo editabas. Vuelve a '
              'abrirlo para ver lo último.',
        ),
      'product_model_not_found' => const ProductModelException(
          'product_model_not_found',
          'Este modelo ya no existe.',
        ),
      'product_model_invalid' => ProductModelException(
          code,
          switch (productId) {
            'name' => 'El nombre del modelo va de 1 a 160 letras.',
            'axes' =>
              'Revisa los ejes: de uno a tres, cada uno con sus valores sin '
                  'repetir.',
            _ => 'Un modelo junta productos: agrega al menos uno.',
          },
        ),
      'catalog_edit_forbidden' ||
      'catalog_tenant_forbidden' =>
        const ProductModelException(
          'forbidden',
          'Tu usuario no puede cambiar el catálogo.',
        ),
      _ => ProductModelException(
          'unknown',
          'No se pudo guardar el modelo: ${error.message}',
        ),
    };
  }
}
