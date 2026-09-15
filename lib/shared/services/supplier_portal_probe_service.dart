import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Reconocer el portal de un proveedor desde adentro de la sesión del taller.
///
/// Un portal mayorista no muestra su catálogo sin login, así que su buscador,
/// su precio y su stock sólo se pueden leer con la sesión abierta. Esta clase
/// inyecta la sonda en la página que el operador ya tiene delante y guarda lo
/// que vio, para poder configurar ese portal después sin volver a entrar.
///
/// **No toca credenciales.** El login lo hace el autocompletado del navegador
/// con lo que el ERP ya guarda; acá sólo se lee la página resultante.
class SupplierPortalProbeService {
  SupplierPortalProbeService(this._client);

  final SupabaseClient _client;

  /// Guarda el reconocimiento. Devuelve el nombre del proveedor al que quedó
  /// atribuido, o `null` si el origen no corresponde a ninguno conocido —lo que
  /// también es una respuesta: significa que esa pestaña no es un portal
  /// nuestro y no debe escribir evidencia.
  Future<String?> recordDiscovery({
    required String originUrl,
    required Map<String, dynamic> report,
  }) async {
    final response = await _client.rpc(
      'record_supplier_portal_discovery_v1',
      params: {
        'p_origin_url': originUrl,
        'p_payload': report,
      },
    );
    final envelope = response is Map<String, dynamic>
        ? response
        : response is Map
            ? Map<String, dynamic>.from(response)
            : const <String, dynamic>{};
    if (envelope['status'] != 'recorded') return null;
    final name = envelope['supplierName'];
    return name is String && name.trim().isNotEmpty ? name.trim() : 'proveedor';
  }

  /// A qué proveedor pertenece la página abierta. Sólo pregunta: no escribe
  /// evidencia, porque un chequeo que quiere saber con quién habla no puede
  /// dejar una fila de reconocimiento por cada producto.
  Future<String?> supplierForOrigin(String originUrl) async {
    final response = await _client.rpc(
      'supplier_for_origin_v1',
      params: {'p_origin_url': originUrl},
    );
    final envelope = response is Map
        ? Map<String, dynamic>.from(response)
        : const <String, dynamic>{};
    if (envelope['status'] != 'found') return null;
    final id = envelope['supplierId']?.toString();
    return id == null || id.isEmpty ? null : id;
  }

  /// El resultado de `evaluateJavascript` llega como texto en algunas
  /// plataformas y como estructura en otras. Se normaliza acá para que quien
  /// llama no tenga que saberlo.
  static Map<String, dynamic>? decodeReport(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed == 'null') return null;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
