import 'package:supabase_flutter/supabase_flutter.dart';

import 'supplier_portal_reading.dart';

/// Un producto que vale la pena confirmar con ese proveedor.
class SupplierAvailabilityTarget {
  const SupplierAvailabilityTarget({
    required this.productId,
    required this.name,
    required this.supplierCode,
  });

  final String productId;
  final String name;
  final String supplierCode;
}

/// Lee la configuración del portal, qué preguntar, y anota lo que contestó.
///
/// Guarda **siempre**, también cuando la respuesta fue una sesión caída o una
/// página ilegible: saber que el chequeo no pudo concluir es información, y
/// borrarla haría que el mismo problema se descubra otra vez mañana.
class SupplierAvailabilityService {
  SupplierAvailabilityService(this._client);

  final SupabaseClient _client;

  /// La sonda del proveedor, sólo si está habilitada. Configurar un portal no
  /// autoriza a consultarlo: son dos decisiones distintas.
  Future<SupplierPortalProbe?> enabledProbe(String supplierId) async {
    final rows = await _client
        .from('supplier_portal_probes')
        .select(
          'search_url_template,logged_out_pattern,not_found_pattern,'
          'price_pattern,stock_pattern,out_of_stock_pattern',
        )
        .eq('supplier_id', supplierId)
        .eq('is_enabled', true)
        .limit(1);
    if (rows.isEmpty) return null;
    final row = Map<String, dynamic>.from(rows.first);
    final template = row['search_url_template']?.toString();
    if (template == null || !template.contains('{code}')) return null;
    String? pattern(String key) {
      final value = row[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    return SupplierPortalProbe(
      searchUrlTemplate: template,
      loggedOutPattern: pattern('logged_out_pattern'),
      notFoundPattern: pattern('not_found_pattern'),
      pricePattern: pattern('price_pattern'),
      stockPattern: pattern('stock_pattern'),
      outOfStockPattern: pattern('out_of_stock_pattern'),
    );
  }

  Future<List<SupplierAvailabilityTarget>> targets(
    String supplierId, {
    int limit = 12,
  }) async {
    final response = await _client.rpc(
      'supplier_availability_targets_v1',
      params: {'p_supplier_id': supplierId, 'p_limit': limit},
    );
    final envelope = response is Map
        ? Map<String, dynamic>.from(response)
        : const <String, dynamic>{};
    final items = envelope['items'];
    if (items is! List) return const <SupplierAvailabilityTarget>[];
    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) =>
            (item['supplierCode']?.toString().trim() ?? '').isNotEmpty)
        .map((item) => SupplierAvailabilityTarget(
              productId: item['productId']?.toString() ?? '',
              name: item['name']?.toString() ?? 'Producto',
              supplierCode: item['supplierCode'].toString().trim(),
            ))
        .toList(growable: false);
  }

  /// Lo último que dijo el portal, para pintarlo junto al historial.
  ///
  /// `productIds` **acota el recuento a los productos de los que se está
  /// hablando**. Sin él sale el barrido completo de reposición del proveedor, y
  /// ese número no tiene nada que ver con la fila: en RBX decía «12 de 12» —
  /// cámaras de 16", 20", 24", 26" y hasta una biela— sobre una necesidad de
  /// cámaras 29. El dueño lo vio y no pudo relacionar el 12 con nada.
  Future<Map<String, dynamic>> lastAvailability(
    String supplierId, {
    List<String>? productIds,
  }) async {
    final response = await _client.rpc(
      'supplier_last_availability_v1',
      params: {
        'p_supplier_id': supplierId,
        'p_limit': 8,
        // **Una lista vacía NO es «sin alcance».** Significa que nada de esta
        // línea se le consultó, y el servidor tiene que contestar eso: cero
        // confirmado, y el barrido aparte. Mandar `null` acá era volver a
        // contar el barrido entero como si fuera la respuesta de la fila —el
        // «12 de 12» que no se podía relacionar con nada—.
        'p_product_ids': productIds,
      },
    );
    return response is Map
        ? Map<String, dynamic>.from(response)
        : <String, dynamic>{};
  }

  Future<void> record({
    required String supplierId,
    required SupplierAvailabilityTarget target,
    required SupplierPortalReading reading,
    required String sourceUrl,
    required String evidenceSample,
  }) async {
    await _client.rpc(
      'record_supplier_availability_check_v1',
      params: {
        'p_supplier_id': supplierId,
        'p_product_id': target.productId,
        'p_supplier_code': target.supplierCode,
        'p_status': reading.status.wireName,
        // Los estados sin prueba viajan sin números, y la base lo exige
        // además: un cero que nadie demostró no puede entrar por acá.
        'p_price_net': reading.carriesNumbers ? reading.priceNet : null,
        'p_stock_quantity':
            reading.carriesNumbers ? reading.stockQuantity : null,
        'p_source_url': sourceUrl,
        'p_evidence': {
          // Un trozo de la página tal como se leyó: es lo que permite
          // corregir la sonda después sin volver a entrar al portal.
          'sample': evidenceSample.length > 1200
              ? evidenceSample.substring(0, 1200)
              : evidenceSample,
        },
      },
    );
  }
}
