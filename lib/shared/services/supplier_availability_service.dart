import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supplier_need_portal_search.dart';
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
          'price_pattern,stock_pattern,out_of_stock_pattern,'
          'need_search_url_template,need_search_term_limit,'
          'need_search_adapter,session_login_url',
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

    String? sessionLoginUrl() {
      final value = pattern('session_login_url');
      final parsed = Uri.tryParse(value ?? '');
      if (parsed == null ||
          parsed.scheme.toLowerCase() != 'https' ||
          parsed.host.isEmpty ||
          parsed.userInfo.isNotEmpty) {
        return null;
      }
      return parsed.toString();
    }

    SupplierNeedPortalAdapter? needSearchAdapter;
    final rawNeedSearchAdapter = row['need_search_adapter'];
    if (rawNeedSearchAdapter is Map) {
      try {
        needSearchAdapter = SupplierNeedPortalAdapter.fromJson(
          Map<String, dynamic>.from(rawNeedSearchAdapter),
        );
      } on FormatException {
        // Una configuración incompleta deshabilita la capacidad. Nunca se
        // reemplaza por heurísticas Dart que sólo funcionen para un producto.
      }
    }

    return SupplierPortalProbe(
      searchUrlTemplate: template,
      sessionLoginUrl: sessionLoginUrl(),
      needSearchUrlTemplate: pattern('need_search_url_template'),
      needSearchTermLimit:
          (row['need_search_term_limit'] as num?)?.round() ?? 40,
      needSearchAdapter: needSearchAdapter,
      catalogTaxonomy: await _catalogTaxonomy(supplierId),
      loggedOutPattern: pattern('logged_out_pattern'),
      notFoundPattern: pattern('not_found_pattern'),
      pricePattern: pattern('price_pattern'),
      stockPattern: pattern('stock_pattern'),
      outOfStockPattern: pattern('out_of_stock_pattern'),
    );
  }

  /// La taxonomía guardada del portal, si la base ya la tiene.
  ///
  /// **Va en su propia consulta a propósito.** Pedir una columna que todavía
  /// no existe hace fallar el `select` entero, y eso apagaría la búsqueda por
  /// necesidad completa mientras la migración espera revisión. El costo es un
  /// viaje más por operación, no por fila.
  Future<SupplierPortalCatalogTaxonomy?> _catalogTaxonomy(
    String supplierId,
  ) async {
    try {
      final rows = await _client
          .from('supplier_portal_probes')
          .select('catalog_taxonomy,catalog_taxonomy_discovered_at')
          .eq('supplier_id', supplierId)
          .eq('is_enabled', true)
          .limit(1);
      if (rows.isEmpty) return null;
      final row = Map<String, dynamic>.from(rows.first);
      final raw = row['catalog_taxonomy'];
      if (raw is! Map) return null;
      final taxonomy = SupplierPortalCatalogTaxonomy.fromJson(
        Map<String, dynamic>.from(raw),
      );
      if (taxonomy.isEmpty) return null;
      // **La frescura la fecha el servidor, no la fila.** La columna la
      // estampa el recibo; el `discoveredAt` de adentro del jsonb es dato que
      // alguna vez viajó. Creerle al payload permitiría fechar el caché en el
      // futuro y apagar el redescubrimiento para siempre.
      return taxonomy.withServerDiscoveredAt(
        DateTime.tryParse('${row['catalog_taxonomy_discovered_at'] ?? ''}'),
      );
    } catch (_) {
      // Sin columna todavía: se descubre en vivo y se cachea en memoria.
      return null;
    }
  }

  /// Guarda la taxonomía descubierta. Best-effort por diseño: si la base aún
  /// no tiene dónde ponerla, la búsqueda igual funciona con la caché en
  /// memoria. Nunca puede tumbar una consulta que ya salió bien.
  Future<void> recordCatalogTaxonomy({
    required String supplierId,
    required SupplierPortalCatalogTaxonomy taxonomy,
  }) async {
    if (taxonomy.isEmpty) return;
    try {
      await _client.rpc(
        'record_supplier_portal_catalog_taxonomy_v1',
        params: <String, dynamic>{
          'p_supplier_id': supplierId,
          'p_taxonomy': taxonomy.toJson(),
        },
      );
    } catch (_) {
      // La función puede no estar desplegada todavía.
    }
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

  /// La última búsqueda hecha por ESTA necesidad en ESTE proveedor.
  ///
  /// No se deriva de `supplier_availability_checks`: ese historial responde
  /// por SKUs conocidos. Una necesidad todavía puede no tener producto ni SKU,
  /// y mezclar ambos caminos fue precisamente lo que hizo aparecer cámaras y
  /// bielas mientras se buscaba un motor.
  Future<SupplierNeedPortalSearchSnapshot?> lastNeedSearch({
    required String supplierId,
    required String needId,
  }) async {
    final response = await _client.rpc(
      'supplier_last_need_portal_search_v1',
      params: <String, dynamic>{
        'p_supplier_id': supplierId,
        'p_supply_need_id': needId,
      },
    );
    if (response is! Map || response.isEmpty) return null;
    final json = Map<String, dynamic>.from(response);
    if (json['status'] == 'never_searched') return null;
    return SupplierNeedPortalSearchSnapshot.fromJson(json);
  }

  Future<void> recordNeedSearch({
    required String supplierId,
    required SupplierNeedSearchRequest request,
    required SupplierNeedPortalSearchSnapshot snapshot,
    required String evidenceSample,
  }) async {
    final operationKey = snapshot.operationKey;
    final base = <String, dynamic>{
      'p_supplier_id': supplierId,
      'p_supply_need_id': request.needId,
      'p_search_query': snapshot.query,
      'p_status': snapshot.status.wireName,
      'p_source_url': snapshot.sourceUrl,
      'p_results': snapshot.matches
          .map((match) => match.toJson())
          .toList(growable: false),
      'p_evidence': <String, dynamic>{
        // Sólo señales estructurales del adaptador. Nunca texto bruto de una
        // página autenticada, campos, cookies ni identidad de la cuenta.
        'sample': evidenceSample.length > 1200
            ? evidenceSample.substring(0, 1200)
            : evidenceSample,
        // La cobertura viaja también acá para que quede registrada aunque el
        // recibo todavía no tenga su propia columna.
        'coverage': snapshot.coverage.toJson(),
      },
    };
    // **El reintento es el recibo ANTERIOR, no éste con menos campos.** La
    // firma vigente pide la cobertura y la estampa de interpretación; mandarle
    // esos parámetros a una base sin migrar no cae en «función no encontrada»,
    // cae en una llamada que nunca va a existir. El degradado tiene que ser
    // exactamente el contrato viejo.
    final current = <String, dynamic>{
      ...base,
      'p_coverage': snapshot.coverage.toJson(),
      // La capturó quien inició el recorrido. El servidor la valida contra la
      // revisión vigente y RECHAZA la lectura que quedó vieja mientras corría,
      // en vez de reetiquetarla.
      'p_expected_need_version': request.needVersion,
      'p_expected_revision_no': request.revisionNo,
      'p_expected_category_id': request.categoryId,
      'p_expected_technical_family': request.technicalFamily,
      if (operationKey != null) 'p_operation_key': operationKey,
    };
    final reloj = Stopwatch()..start();
    final bytes = utf8.encode(jsonEncode(current)).length;
    try {
      await _client.rpc(
        'record_supplier_need_portal_search_v1',
        params: current,
      );
      debugPrint('📮 recibo guardado en ${reloj.elapsedMilliseconds} ms '
          '($bytes bytes)');
    } on PostgrestException catch (error) {
      // **Cuánto tardó en fallar distingue un timeout de un rechazo.** Un 504
      // a los pocos ms es un proxy que rechaza; a los 60 s es una espera.
      debugPrint('📮 recibo falló tras ${reloj.elapsedMilliseconds} ms '
          '($bytes bytes) — ${error.code}: ${error.message}');
      // **Un transporte caído deja el resultado DESCONOCIDO.** Un 502/503/504
      // del gateway no dice si la escritura entró: puede haber quedado
      // guardada y la respuesta perdida. Medido el 2026-08-30, cuatro corridas
      // seguidas contra RBX murieron así con el portal ya recorrido. Con la
      // clave de operación se puede preguntar —sin escribir— si esa misma
      // corrida ya quedó registrada, y sólo si no está se reintenta. Sin
      // clave no se reintenta nada: duplicar un recibo es peor que perderlo.
      // **Un pool agotado no se reintenta acá.** Reintentar en el acto pide
      // otra conexión del mismo pool que acaba de negarla, y encima la página
      // vuelve a reintentar después: dos capas apretando a la vez es cómo se
      // llega a quince llamadas simultáneas de esta misma RPC. `PGRST003` sube
      // tal cual y lo toma el reintento único con espera creciente.
      if (_connectionNeverAcquired(error)) rethrow;
      if (operationKey != null && _isUnknownOutcome(error)) {
        // Acá el resultado sí es desconocido —la sentencia pudo haber
        // corrido—, así que se resuelve por clave antes de escribir de nuevo.
        if (await needSearchWasRecorded(operationKey)) return;
        await _client.rpc(
          'record_supplier_need_portal_search_v1',
          params: current,
        );
        return;
      }
      // **El reintento es sólo para una firma que todavía no existe.** Si el
      // recibo rechazó la cobertura por inválida —una completitud que nadie
      // demostró, por ejemplo—, reintentar sin ella guardaría la fila igual y
      // taparía justo el defecto que esa validación existe para encontrar.
      if (!_isMissingFunctionSignature(error)) rethrow;
      await _client.rpc(
        'record_supplier_need_portal_search_v1',
        params: base,
      );
    }
  }

  /// Si esta corrida ya quedó registrada. **No escribe nada.**
  ///
  /// Es lo primero que se pregunta ante un resultado desconocido: una lectura
  /// no puede empeorar un estado que no se conoce, y una escritura sí.
  Future<bool> needSearchWasRecorded(String operationKey) async {
    try {
      final raw = await _client.rpc(
        'supplier_need_portal_search_by_operation_key_v1',
        params: <String, dynamic>{'p_operation_key': operationKey},
      );
      return raw is Map && raw['status'] == 'recorded';
    } catch (_) {
      // Si tampoco se puede preguntar, el estado sigue desconocido y no se
      // reintenta: la corrida se reporta sin registrar y no se duplica nada.
      return false;
    }
  }

  /// La escritura **no ocurrió** y se puede reintentar sin más trámite.
  ///
  /// `PGRST003` es «Timed out acquiring connection from connection pool»: la
  /// sentencia nunca llegó a Postgres porque PostgREST no consiguió conexión,
  /// así que no hay nada que resolver. Medido en producción el 2026-08-30: es
  /// **el** error detrás de cada `504 Gateway Timeout` de esta corrida, con la
  /// RPC respondiendo en 7 ms y `authenticator` con 19 conexiones —varias
  /// `idle in transaction`— sobre un tope de 60.
  @visibleForTesting
  static bool connectionNeverAcquired(PostgrestException error) =>
      _connectionNeverAcquired(error);

  @visibleForTesting
  static bool isUnknownOutcome(PostgrestException error) =>
      _isUnknownOutcome(error);

  static bool _connectionNeverAcquired(PostgrestException error) =>
      (error.code ?? '').trim() == 'PGRST003';

  /// Códigos en los que el resultado de la escritura no se puede afirmar.
  ///
  /// Son fallas de transporte —el gateway no llegó a contarnos qué pasó—, no
  /// rechazos del negocio. Un `23505` o un `22023` sí son respuestas y no
  /// entran acá.
  ///
  /// **El mensaje dice «Timed out», no «timeout».** Buscar la segunda forma
  /// dejaba este camino muerto: el reintento nunca corría y la corrida se
  /// perdía igual, que es justo lo que parecía «el segundo intento también
  /// falla».
  static bool _isUnknownOutcome(PostgrestException error) {
    const transporte = <String>{'502', '503', '504', '408', '429'};
    final code = (error.code ?? '').trim();
    if (transporte.contains(code) || _connectionNeverAcquired(error)) {
      return true;
    }
    final message = error.message.toLowerCase();
    return message.contains('timed out') ||
        message.contains('timeout') ||
        message.contains('gateway') ||
        message.contains('connection pool') ||
        message.contains('temporarily unavailable');
  }

  bool _isMissingFunctionSignature(PostgrestException error) {
    final code = error.code ?? '';
    if (code == 'PGRST202' || code == '42883') return true;
    final message = error.message.toLowerCase();
    return message.contains('p_coverage') ||
        message.contains('could not find the function') ||
        message.contains('does not exist');
  }
}
