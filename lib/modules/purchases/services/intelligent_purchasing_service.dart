import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../ai_assistant/models/ai_assistant_turn_contracts.dart';
import '../models/intelligent_purchasing_models.dart';
import '../models/supplier_catalog.dart';

class IntelligentPurchasingService {
  IntelligentPurchasingService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, JobSupplyAttention>> fetchJobSupplyAttention(
    Iterable<String> jobIds,
  ) async {
    final ids = jobIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const {};

    const chunkSize = 100;
    final chunks = <List<String>>[
      for (var offset = 0; offset < ids.length; offset += chunkSize)
        ids.sublist((offset), (offset + chunkSize).clamp(0, ids.length)),
    ];
    final responses = await Future.wait<List<dynamic>>(
      chunks.map(
        (chunk) async => await _client
            .from('mechanic_job_supply_attention_v1')
            .select()
            .inFilter('mechanic_job_id', chunk) as List<dynamic>,
      ),
    );
    final rows = responses
        .expand((response) => response)
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row));

    return {
      for (final row in rows)
        if (row['mechanic_job_id'] != null)
          row['mechanic_job_id'].toString(): JobSupplyAttention.fromJson(row),
    };
  }

  Future<SupplyNeed> createNeed({
    required String description,
    required double quantity,
    String unit = 'unit',
    String originKind = 'ad_hoc',
    String? mechanicJobId,
    String? jobBikeId,
    String? productId,
    String? assistantThreadId,
    String? operationKey,
  }) async {
    final response = await _client.rpc(
      'create_supply_need_v1',
      params: {
        'p_origin_kind': originKind,
        'p_mechanic_job_id': mechanicJobId,
        'p_job_bike_id': jobBikeId,
        'p_description': description.trim(),
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_unit': unit,
        'p_assistant_thread_id': assistantThreadId,
        'p_operation_key': operationKey ?? const Uuid().v4(),
      },
    );
    final envelope = _map(response);
    final need = envelope['need'];
    if (need is! Map) {
      throw const FormatException(
        'El servidor no devolvió la necesidad creada.',
      );
    }
    return SupplyNeed.fromJson(Map<String, dynamic>.from(need));
  }

  Future<List<SupplyNeed>> createNeedBatch({
    required String originalRequest,
    required AIAssistantSupplyNeedDraft draft,
    required String operationKey,
    String? assistantThreadId,
  }) async {
    final response = await _client.rpc(
      // v3 crea la necesidad y su primer objetivo comercial de forma atómica,
      // delegando todas las reglas de la necesidad en v2, que queda intacta.
      //
      // Una línea sin objetivo accionable **no** escribe una revisión vacía, así
      // que hasta que el borrador de la IA lo traiga esto se comporta igual que
      // v2. El cambio va antes y no después: el recibo de v3 vive en el mismo
      // espacio de nombres que el de v2 —una clave usada por cualquiera de los
      // dos bloquea al otro—, de modo que migrar el llamador cuando ya hubiera
      // objetivos en vuelo obligaría a razonar sobre dos escritores del mismo
      // lote conviviendo.
      //
      // La categoría resuelta la sigue trayendo la línea desde la tarjeta
      // cerrada; el cliente no la inventa.
      'create_supply_need_batch_v3',
      params: {
        'p_original_request': originalRequest.trim(),
        'p_items': draft.lines
            .map((line) => line.toCommandJson())
            .toList(growable: false),
        'p_profile': switch (draft.profile) {
          AIAssistantSupplyNeedProfile.balanced => 'balanced',
          AIAssistantSupplyNeedProfile.profitability => 'profitability',
          AIAssistantSupplyNeedProfile.urgentLocal => 'urgent_local',
        },
        'p_assistant_thread_id': assistantThreadId,
        'p_operation_key': operationKey,
      },
    );
    final envelope = _map(response);
    final rawNeeds = envelope['needs'];
    if (rawNeeds is! List || rawNeeds.length != draft.lines.length) {
      throw const FormatException(
        'El servidor no confirmó todas las necesidades del borrador.',
      );
    }
    final needs = rawNeeds
        .whereType<Map>()
        .map((row) => SupplyNeed.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    if (needs.length != draft.lines.length ||
        needs.any((need) => need.id.isEmpty)) {
      throw const FormatException(
        'El servidor no confirmó todas las necesidades del borrador.',
      );
    }
    return _enrichProducts(needs);
  }

  /// Qué hay que comprar, levantado por el sistema.
  ///
  /// El módulo abre con esto, no con un campo vacío: alguien sin experiencia no
  /// sabe **que hay que comprar**, y pedirle que lo escriba es pedirle justo lo
  /// que no tiene.
  Future<List<PurchasePrioritySuggestion>> fetchPurchasePriority({
    int limit = 40,
    int rotationDays = 120,
  }) async {
    final response = await _client.rpc(
      'purchase_priority_feed_v1',
      params: {'p_limit': limit, 'p_rotation_days': rotationDays},
    );
    final payload = _map(response);
    final items = payload['items'];
    if (items is! List) return const [];
    final suggestions = items
        .whereType<Map>()
        .map((row) =>
            PurchasePrioritySuggestion.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    return _enrichPriorityMedia(suggestions);
  }

  /// Opens an existing workshop need or creates a new ad-hoc need for a stock
  /// signal. Workshop suggestions are already durable demand: recreating one
  /// would sever its job and bicycle attribution and duplicate the purchase
  /// requirement.
  Future<SupplyNeed> takePrioritySuggestion(
    PurchasePrioritySuggestion suggestion,
  ) async {
    if (!suggestion.isWorkshop) {
      return createNeed(
        description: suggestion.title,
        quantity: suggestion.suggestedQuantity,
        unit: suggestion.unit,
        productId: suggestion.productId,
      );
    }

    final need = await fetchNeed(suggestion.entityId);
    if (need == null ||
        need.originKind != 'mechanic_job' ||
        need.mechanicJobId == null ||
        need.supplyState != 'open') {
      throw StateError('La necesidad del trabajo ya no está pendiente.');
    }
    final context = suggestion.jobContext;
    if (context != null &&
        (context.mechanicJobId != need.mechanicJobId ||
            context.jobBikeId != need.jobBikeId)) {
      throw StateError('La bicicleta asignada cambió; vuelve a cargar.');
    }
    return need;
  }

  /// Takes 2..8 priority rows as one replay-safe purchasing basket.
  ///
  /// The server re-reads every opaque feed identity before doing anything:
  /// workshop rows return their existing durable need, while current stock
  /// signals create canonical ad-hoc needs. The public [operationKey] belongs
  /// to the whole selection, so a lost response can be retried without
  /// duplicating one of the stock rows midway through the basket.
  Future<List<SupplyNeed>> takePriorityBatch({
    required List<PurchasePrioritySuggestion> suggestions,
    required String operationKey,
    int rotationDays = 120,
  }) async {
    if (suggestions.length < 2 || suggestions.length > 8) {
      throw ArgumentError.value(
        suggestions.length,
        'suggestions',
        'La búsqueda conjunta admite entre 2 y 8 filas.',
      );
    }
    final response = await _client.rpc(
      'take_purchase_priority_batch_v1',
      params: {
        'p_items': [
          for (final suggestion in suggestions)
            {
              'source': suggestion.source,
              'entityId': suggestion.entityId,
            },
        ],
        'p_rotation_days': rotationDays,
        'p_operation_key': operationKey,
      },
    );
    final envelope = _map(response);
    final rawNeeds = envelope['needs'];
    if (rawNeeds is! List || rawNeeds.length != suggestions.length) {
      throw const FormatException(
        'El servidor no confirmó todas las prioridades seleccionadas.',
      );
    }
    final needs = rawNeeds
        .whereType<Map>()
        .map((row) => SupplyNeed.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    if (needs.length != suggestions.length ||
        needs.any((need) => need.id.isEmpty)) {
      throw const FormatException(
        'El servidor no confirmó todas las prioridades seleccionadas.',
      );
    }
    return _enrichProducts(needs);
  }

  Future<List<SupplyNeed>> fetchOpenNeeds({String? mechanicJobId}) async {
    dynamic query =
        _client.from('supply_needs').select().inFilter('supply_state', const [
      'open',
      'committed',
      'in_purchase',
      'received',
    ]);
    if (mechanicJobId != null) {
      query = query.eq('mechanic_job_id', mechanicJobId);
    }
    final response = await query.order('updated_at', ascending: false);
    final rows = (response as List)
        .whereType<Map>()
        .map((row) => SupplyNeed.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    return _enrichProducts(rows);
  }

  /// Complete workshop trace for one job, newest decision first.
  ///
  /// Unlike [fetchOpenNeeds], this deliberately keeps covered and cancelled
  /// rows: Jobs is the origin surface and must be able to explain what was
  /// requested even after Purchasing closes it. The global Purchasing inbox
  /// remains active-only.
  Future<List<SupplyNeed>> fetchJobNeeds(String mechanicJobId) async {
    final jobId = mechanicJobId.trim();
    if (jobId.isEmpty) return const [];
    final response = await _client
        .from('supply_needs')
        .select()
        .eq('mechanic_job_id', jobId)
        .order('updated_at', ascending: false);
    final rows = (response as List)
        .whereType<Map>()
        .map((row) => SupplyNeed.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    return _enrichProducts(rows);
  }

  /// Los criterios con que se interpretó una necesidad, de su última revisión.
  ///
  /// **Un viaje por necesidad seleccionada, no por lista.** La barra muestra
  /// una necesidad a la vez, así que traer las revisiones de las diez abiertas
  /// sería pagar nueve lecturas que nadie mira. Se lee al abrir la necesidad,
  /// junto al resto de su decisión.
  ///
  /// La tabla ya es legible por el cliente con RLS por taller (`SELECT` a
  /// `authenticated`), así que esto no necesita RPC ni migración.
  ///
  /// Un fallo devuelve criterios vacíos en vez de propagar: la barra se dibuja
  /// igual sin resumen, y perder el recorrido por una glosa sería peor.
  Future<SupplyNeedCriteria> fetchNeedCriteria(String needId) async {
    try {
      final revision = await _client
          .from('supply_need_interpretation_revisions')
          .select('constraints, category_id')
          .eq('supply_need_id', needId)
          .order('revision_no', ascending: false)
          .limit(1)
          .maybeSingle();
      if (revision == null) return SupplyNeedCriteria.empty;
      final row = Map<String, dynamic>.from(revision as Map);
      final categoryId = row['category_id']?.toString();
      String? categoryPath;
      if (categoryId != null && categoryId.isNotEmpty) {
        final category = await _client
            .from('product_categories')
            .select('full_path, name')
            .eq('id', categoryId)
            .maybeSingle();
        if (category != null) {
          final map = Map<String, dynamic>.from(category as Map);
          categoryPath = (map['full_path'] ?? map['name'])?.toString();
        }
      }
      return SupplyNeedCriteria.fromConstraints(
        row['constraints'],
        categoryPath: categoryPath,
      );
    } catch (_) {
      return SupplyNeedCriteria.empty;
    }
  }

  Future<SupplyNeed?> fetchNeed(String needId) async {
    final response = await _client
        .from('supply_needs')
        .select()
        .eq('id', needId)
        .maybeSingle();
    if (response == null) return null;
    final enriched = await _enrichProducts([
      SupplyNeed.fromJson(Map<String, dynamic>.from(response)),
    ]);
    return enriched.single;
  }

  Future<SupplyNeed> updateNeed(
    SupplyNeed need, {
    required String description,
    required String? productId,
    double? quantity,
    String? unit,
  }) async {
    final response = await _client.rpc(
      'update_supply_need_v1',
      params: {
        'p_need_id': need.id,
        'p_expected_version': need.version,
        'p_description': description.trim(),
        'p_product_id': productId,
        'p_quantity': quantity ?? need.quantity,
        'p_unit': unit ?? need.unit,
        'p_operation_key': const Uuid().v4(),
      },
    );
    final updated = _needFromCommand(response);
    final enriched = await _enrichProducts([updated]);
    return enriched.single;
  }

  /// Edits a need from its workshop origin, including its bicycle scope.
  ///
  /// Purchasing's generic editor intentionally cannot move workshop context.
  /// This command exists for Jobs, where the operator can verify which bike in
  /// a multi-bike job will receive the part. The server validates that the
  /// selected link belongs to the same job and applies optimistic concurrency.
  Future<SupplyNeed> updateWorkshopNeed(
    SupplyNeed need, {
    required String description,
    required String? productId,
    required String? jobBikeId,
    double? quantity,
    String? unit,
  }) async {
    final response = await _client.rpc(
      'update_workshop_supply_need_v1',
      params: {
        'p_need_id': need.id,
        'p_expected_version': need.version,
        'p_description': description.trim(),
        'p_product_id': productId,
        'p_quantity': quantity ?? need.quantity,
        'p_unit': unit ?? need.unit,
        'p_job_bike_id': jobBikeId,
        'p_operation_key': const Uuid().v4(),
      },
    );
    final updated = _needFromCommand(response);
    final enriched = await _enrichProducts([updated]);
    return enriched.single;
  }

  Future<SupplyInventorySnapshot> inventorySnapshot(String needId) async {
    final response = await _client.rpc(
      'get_supply_need_inventory_snapshot_v1',
      params: {'p_need_id': needId},
    );
    return SupplyInventorySnapshot.fromJson(_map(response));
  }

  /// Lo que hay en bodega que se parece a la descripción, cuando todavía no
  /// hay producto exacto confirmado. No asigna ni reserva nada.
  Future<StockCandidateReport> stockCandidates(String needId) async {
    final response = await _client.rpc(
      'supply_need_stock_candidates_v1',
      params: {'p_need_id': needId, 'p_limit': 8},
    );
    return StockCandidateReport.fromJson(_map(response));
  }

  Future<SupplyNeed> assignFromStock(SupplyNeed need) async {
    final response = await _client.rpc(
      'assign_supply_need_from_stock_v1',
      params: {
        'p_need_id': need.id,
        'p_expected_version': need.version,
        'p_operation_key': const Uuid().v4(),
      },
    );
    return _needFromCommand(response);
  }

  Future<SupplyNeed> rejectInternalStock(
    SupplyNeed need, {
    required String reason,
  }) async {
    final response = await _client.rpc(
      'reject_supply_need_internal_stock_v1',
      params: {
        'p_need_id': need.id,
        'p_expected_version': need.version,
        'p_reason': reason.trim(),
        'p_operation_key': const Uuid().v4(),
      },
    );
    return _needFromCommand(response);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Fase B1/B2 — el carril familia, de punta a punta.
  //
  // Las cuatro lecturas y los tres comandos que el flujo guiado necesita. Cada
  // comando exige la **versión** de la necesidad y la **revisión** que la
  // gobierna, y ninguno de los dos números sale de `supply_needs`: vienen del
  // envelope autocontenido de la lectura inmediatamente anterior.
  // ─────────────────────────────────────────────────────────────────────────

  /// Stock interno del conjunto elegible, en cualquiera de los dos carriles.
  Future<SupplyStockResolution> stockResolution(
    String needId, {
    int limit = 12,
    int offset = 0,
  }) async {
    final response = await _client.rpc(
      // v3 conserva el envelope y agrega la referencia de costo de catálogo y
      // si existe una consulta automática para ESE producto/proveedor. La
      // referencia sigue separada del costo pagado o aterrizado.
      'get_supply_need_stock_resolution_v3',
      params: {
        'p_need_id': needId,
        'p_limit': limit,
        'p_offset': offset,
      },
    );
    return SupplyStockResolution.fromJson(_map(response));
  }

  /// Registra por qué el stock interno no sirve, en el carril que corresponda.
  ///
  /// v2 y no v1: v1 exige un producto confirmado, así que una necesidad de
  /// familia nunca podía registrar su rechazo — el nudo que dejaba la
  /// necesidad encerrada entre stock y compra.
  Future<void> rejectInternalStockForLane({
    required SupplyStockResolution resolution,
    required String reason,
  }) async {
    await _runNeedCommand(
      needId: resolution.needId,
      rpc: 'reject_supply_need_internal_stock_v2',
      params: {
        'p_need_id': resolution.needId,
        'p_expected_version': resolution.needVersion,
        'p_expected_revision_no': resolution.revisionNo,
        'p_reason': reason.trim(),
        'p_operation_key': const Uuid().v4(),
      },
    );
  }

  /// Converge el carril familia a un producto exacto.
  ///
  /// Es un comando propio y no `update_supply_need_v1` porque ese writer deja
  /// la revisión sin categoría ni criterios: converger por ahí borraría la
  /// procedencia y el siguiente cálculo quedaría ciego.
  Future<void> confirmFamilyChoice({
    required String needId,
    required int expectedVersion,
    required int expectedRevisionNo,
    required String productId,
  }) async {
    await _runNeedCommand(
      needId: needId,
      rpc: 'confirm_supply_need_family_choice_v1',
      params: {
        'p_need_id': needId,
        'p_expected_version': expectedVersion,
        'p_expected_revision_no': expectedRevisionNo,
        'p_product_id': productId,
        'p_operation_key': const Uuid().v4(),
      },
    );
  }

  /// Candidatos externos del conjunto elegible, con sus dos grupos paginados
  /// por separado.
  ///
  /// Levanta [SupplyStockFirstRequired] cuando el servidor exige decidir
  /// primero el stock interno. Ese caso es un estado del flujo, no un fallo.
  Future<SupplyExternalCandidates> externalCandidates(
    String needId, {
    int limit = 10,
    int offset = 0,
    int unverifiedLimit = 5,
    int unverifiedOffset = 0,
  }) async {
    try {
      final response = await _client.rpc(
        'get_supply_need_external_candidates_v1',
        params: {
          'p_need_id': needId,
          'p_limit': limit,
          'p_offset': offset,
          'p_unverified_limit': unverifiedLimit,
          'p_unverified_offset': unverifiedOffset,
        },
      );
      return SupplyExternalCandidates.fromJson(_map(response));
    } on PostgrestException catch (error) {
      throw _translateSupplyError(needId, error);
    }
  }

  /// Objetivo comercial vigente.
  Future<SupplyCommercialTarget> commercialTarget(String needId) async {
    final response = await _client.rpc(
      'get_supply_need_commercial_target_v1',
      params: {'p_need_id': needId},
    );
    return SupplyCommercialTarget.fromJson(_map(response));
  }

  /// Fija o limpia el objetivo comercial.
  ///
  /// El parche es explícito: una clave ausente conserva, una clave en `null`
  /// limpia ese campo y `values` nulo limpia todo. La moneda **no** se envía:
  /// el servidor la posee y una carga que la traiga se rechaza.
  Future<void> setCommercialTarget({
    required SupplyCommercialTarget current,
    required Map<String, Object?>? values,
  }) async {
    await _runNeedCommand(
      needId: current.needId,
      rpc: 'set_supply_need_commercial_target_v1',
      params: {
        'p_need_id': current.needId,
        'p_expected_version': current.needVersion,
        'p_expected_target_revision_no': current.targetRevisionNo,
        'p_target': values,
        'p_operation_key': const Uuid().v4(),
      },
    );
  }

  Future<void> _runNeedCommand({
    required String needId,
    required String rpc,
    required Map<String, Object?> params,
  }) async {
    try {
      await _client.rpc(rpc, params: params);
    } on PostgrestException catch (error) {
      throw _translateSupplyError(needId, error);
    }
  }

  /// `P0001 stock_first_required` es un paso pendiente y `40001` es una lectura
  /// vencida; cualquier otro error sigue siendo lo que era y sube tal cual.
  /// La regla vive en el modelo, donde una prueba puede afirmarla sin red.
  Object _translateSupplyError(String needId, PostgrestException error) {
    return supplyCommandFailure(
          needId,
          code: error.code,
          message: error.message,
        ) ??
        error;
  }

  Future<PurchaseRanking> rankCandidates({
    String? query,
    String? productId,
    String? categoryId,
    String profile = 'balanced',
    int limit = 10,

    /// `economica` · `media` · `alta`. Ordena el resultado, nunca lo recorta:
    /// una gama no preferida baja de puesto, no desaparece.
    String? gama,
  }) async {
    final response = await _client.rpc(
      'rank_purchase_candidates_v1',
      params: {
        'p_query': query,
        'p_product_id': productId,
        'p_category_id': categoryId,
        'p_profile': profile,
        'p_limit': limit,
        'p_gama': gama,
      },
    );
    return PurchaseRanking.fromJson(_map(response));
  }

  /// A quién le compramos este tipo de producto, según las facturas.
  ///
  /// La frase del operador viaja COMPLETA: el servidor la traduce contra el
  /// vocabulario real de fichas y contra las bandas de gama. Descomponerla aquí
  /// es lo que rompía el módulo — «gama media» no es el nombre de ningún
  /// producto, pero sí es una banda que el análisis sabe leer.
  Future<SupplierConcentrationReport> rankSuppliers({
    String? query,
    String? category,
    String? brand,
    int limit = 4,
  }) async {
    final response = await _client.rpc(
      'rank_purchase_suppliers_v1',
      params: {
        'p_query': query,
        'p_category': category,
        'p_brand': brand,
        'p_limit': limit,
      },
    );
    return SupplierConcentrationReport.fromJson(_map(response));
  }

  /// A quién le pedimos la lista entera, y si conviene repartirla en dos.
  ///
  /// Una llamada por la lista completa, no una por línea: la cobertura y el
  /// reparto son una decisión sobre el conjunto y ninguna consulta por línea
  /// la contiene.
  Future<BasketCoverageReport> rankBasketSuppliers({
    required List<String> queries,
    int limit = 4,
  }) async {
    final lines = queries
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(6)
        .toList(growable: false);
    if (lines.length < 2) {
      throw ArgumentError('La canasta necesita al menos dos líneas.');
    }
    final response = await _client.rpc(
      'rank_basket_suppliers_v1',
      params: {'p_queries': lines, 'p_limit': limit},
    );
    return BasketCoverageReport.fromJson(_map(response));
  }

  /// Por qué ese proveedor quedó donde quedó: sus compras que calzan con lo
  /// pedido, con factura y fecha, y las métricas que lo pusieron ahí.
  Future<SupplierEvidence> supplierEvidence({
    required String supplierId,
    required List<String> queries,
    int limit = 6,
  }) async {
    final lines = queries
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(6)
        .toList(growable: false);
    if (lines.isEmpty) {
      throw ArgumentError('Se necesita al menos una línea para explicar.');
    }
    final response = await _client.rpc(
      'purchase_supplier_evidence_v1',
      params: {
        'p_supplier_id': supplierId,
        'p_queries': lines,
        'p_limit': limit,
      },
    );
    return SupplierEvidence.fromJson(_map(response));
  }

  /// La ficha del proveedor: quién es, sus métricas y su catálogo paginado.
  ///
  /// No recibe la necesidad activa a propósito. La evidencia explica un puesto
  /// en el ranking; esto abre al proveedor entero para poder armarle un pedido
  /// sin salir del bloque.
  Future<SupplierCatalogPage> supplierCatalogPage({
    required String supplierId,
    String? search,
    int limit = 40,
    int offset = 0,

    /// Lo que el operador venía buscando. Sube al servidor para que lo que
    /// coincide encabece la lista: se entra a la ficha desde una necesidad
    /// concreta, y abrirla con otra cosa obliga a buscar de nuevo a mano.
    String? needPhrase,
  }) async {
    final response = await _client.rpc(
      'supplier_catalog_page_v1',
      params: {
        'p_supplier_id': supplierId,
        'p_search': (search ?? '').trim().isEmpty ? null : search!.trim(),
        'p_limit': limit,
        'p_offset': offset,
        'p_need_phrase':
            (needPhrase ?? '').trim().isEmpty ? null : needPhrase!.trim(),
      },
    );
    return SupplierCatalogPage.fromJson(_map(response));
  }

  Future<PurchaseScenarioResult> buildScenarios({
    required List<SupplyNeed> needs,
    String profile = 'balanced',
    int maxSuppliers = 2,
    int limit = 3,
  }) async {
    if (needs.isEmpty || needs.length > 8) {
      throw ArgumentError.value(
        needs.length,
        'needs',
        'La comparación admite entre 1 y 8 necesidades.',
      );
    }
    if (needs.any((need) => !need.hasConfirmedProduct)) {
      throw ArgumentError('Cada necesidad debe tener un producto confirmado.');
    }
    final response = await _client.rpc(
      'build_purchase_scenarios_v1',
      params: {
        'p_items': needs
            .map((need) => {
                  'lineRef': need.id,
                  'productId': need.productId,
                  'quantity': need.quantity,
                  'sourcingMode': need.internalStockRejectionReason == null
                      ? 'stock_first'
                      : 'external_only',
                })
            .toList(growable: false),
        'p_profile': profile,
        'p_max_suppliers': maxSuppliers,
        'p_limit': limit,
      },
    );
    return PurchaseScenarioResult.fromJson(_map(response));
  }

  Future<PurchasePlanDraft> preparePlanLine({
    required SupplyNeed need,
    required PurchaseCandidate candidate,
    required String profile,
    PurchasePlanDraft? plan,

    /// Cantidad elegida en el pie del inspector. La RPC ya la recibía; el
    /// cliente mandaba siempre la de la necesidad, así que llevar tres de algo
    /// obligaba a agregar y corregir después en la línea del plan.
    double? quantity,
  }) async {
    final response = await _client.rpc(
      'prepare_purchase_plan_line_v1',
      params: {
        'p_plan_id': plan?.id,
        'p_expected_plan_version': plan?.version,
        'p_source_need_id': need.id,
        'p_candidate_id': candidate.candidateId,
        'p_quantity': quantity ?? need.quantity,
        'p_profile': profile,
        'p_operation_key': const Uuid().v4(),
      },
    );
    final planId = _map(response)['plan_id']?.toString();
    if (planId == null || planId.isEmpty) {
      throw const FormatException('El servidor no devolvió el plan borrador.');
    }
    final prepared = await fetchPlan(planId);
    if (prepared == null) {
      throw const FormatException('No se pudo leer el plan recién guardado.');
    }
    return prepared;
  }

  /// Lleva al plan un producto exacto que todavía no tiene compras en este
  /// ERP. Queda explícitamente "Por cotizar": no fabrica candidato, costo ni
  /// disponibilidad. Si apareció historia entre la lectura y el toque, el
  /// servidor responde conflicto para releerlo por el carril histórico.
  Future<PurchasePlanDraft> prepareProductQuoteLine({
    required SupplyNeed need,
    required SupplyStockOption product,
    required String profile,
    PurchasePlanDraft? plan,
    double? quantity,
  }) async {
    final response = await _client.rpc(
      'prepare_purchase_plan_product_v1',
      params: {
        'p_plan_id': plan?.id,
        'p_expected_plan_version': plan?.version,
        'p_source_need_id': need.id,
        'p_product_id': product.productId,
        'p_quantity': quantity ?? need.quantity,
        'p_profile': profile,
        'p_operation_key': const Uuid().v4(),
      },
    );
    final planId = _map(response)['plan_id']?.toString();
    if (planId == null || planId.isEmpty) {
      throw const FormatException('El servidor no devolvió el plan borrador.');
    }
    final prepared = await fetchPlan(planId);
    if (prepared == null) {
      throw const FormatException('No se pudo leer el plan recién guardado.');
    }
    return prepared;
  }

  Future<PurchasePlanDraft> prepareScenario({
    required PurchaseScenario scenario,
    required Iterable<SupplyNeed> needs,
    required String profile,
    PurchasePlanDraft? plan,
  }) async {
    final needsById = <String, SupplyNeed>{
      for (final need in needs) need.id: need,
    };
    final lines = scenario.externalCandidates.map((line) {
      final need = needsById[line.lineRef];
      if (need == null || line.candidateId == null) {
        throw const FormatException(
          'El escenario ya no corresponde a las necesidades visibles.',
        );
      }
      return {
        'sourceNeedId': need.id,
        'candidateId': line.candidateId,
        'quantity': line.requestedQuantity,
      };
    }).toList(growable: false);
    if (lines.isEmpty) {
      throw const FormatException(
        'El escenario no contiene alternativas externas para el plan.',
      );
    }

    final response = await _client.rpc(
      'prepare_purchase_plan_scenario_v1',
      params: {
        'p_plan_id': plan?.id,
        'p_expected_plan_version': plan?.version,
        'p_lines': lines,
        'p_profile': profile,
        'p_operation_key': const Uuid().v4(),
      },
    );
    final planId = _map(response)['plan_id']?.toString();
    if (planId == null || planId.isEmpty) {
      throw const FormatException('El servidor no devolvió el plan borrador.');
    }
    final prepared = await fetchPlan(planId);
    if (prepared == null) {
      throw const FormatException('No se pudo leer el plan recién guardado.');
    }
    return prepared;
  }

  /// El plan borrador que el taller dejó abierto, si lo hay.
  ///
  /// **El defecto que cierra.** `_plan` sólo se llenaba con lo que el operador
  /// agregaba **en esa sesión**: nadie releía un plan guardado. Y
  /// `prepare_purchase_plan_line_v1` crea uno nuevo cada vez que recibe
  /// `p_plan_id` nulo. Las dos cosas juntas producen el bucle que se ve en
  /// producción: el operador arma un plan, cierra, vuelve, no lo ve, agrega
  /// otra línea y **abre un segundo borrador**. El 2026-08-18 quedaron dos
  /// planes del mismo día por esa razón, con sus líneas activas invisibles.
  ///
  /// **Por qué el más reciente y no «el de hoy».** El título lo escribe el
  /// servidor como `Plan de compra <tenant_business_date>`, y esa fecha de
  /// negocio no viaja hasta el cliente: filtrar por ella acá exigiría
  /// reconstruirla con el reloj local, que es la segunda definición que este
  /// módulo ya decidió no tener. El borrador más reciente **es** el de hoy
  /// cuando existe, y si no, es el trabajo sin terminar de ayer, que mostrarlo
  /// es mejor que esconderlo.
  ///
  /// Queda una decisión de producto que no es de esta capa: qué hacer con los
  /// borradores viejos que se acumularon —listarlos, archivarlos o fundirlos—.
  /// Acá sólo se deja de crear uno nuevo encima.
  Future<PurchasePlanDraft?> fetchOpenDraftPlan() async {
    final rawPlan = await _client
        .from('purchase_plans')
        .select('id')
        .eq('state', 'draft')
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final planId = (rawPlan as Map?)?['id']?.toString();
    if (planId == null || planId.isEmpty) return null;
    return fetchPlan(planId);
  }

  Future<PurchasePlanDraft?> fetchPlan(String planId) async {
    final rawPlan = await _client
        .from('purchase_plans')
        .select()
        .eq('id', planId)
        .maybeSingle();
    if (rawPlan == null) return null;

    final rawLines = await _client
        .from('purchase_plan_lines')
        .select()
        .eq('plan_id', planId)
        .eq('state', 'active')
        .order('created_at');
    var lines = (rawLines as List)
        .whereType<Map>()
        .map((row) => PurchasePlanLine.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);

    final productIds = lines
        .map((line) => line.productId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (productIds.isNotEmpty) {
      // **Mismo viaje, proyección ampliada.** La consulta a `products` ya
      // existía para resolver el nombre; acá se le agregan tres columnas que la
      // tabla ya publica —`image_url_optimized`, `image_url`, `image_urls`—,
      // que son exactamente las que `ProductMedia` sabe encadenar. Lo que no
      // cambia es el número de consultas: sigue siendo una sola para todas las
      // líneas del plan, no una por fila.
      final rawProducts = await _client
          .from('products')
          .select('id,name,image_url_optimized,image_url,image_urls')
          .inFilter('id', productIds);
      final products = <String, Map<String, dynamic>>{
        for (final row in (rawProducts as List).whereType<Map>())
          if (row['id'] != null)
            row['id'].toString(): Map<String, dynamic>.from(row),
      };
      lines = lines.map((line) {
        final product = products[line.productId];
        if (product == null) return line;
        return line.withProduct(
          name: product['name']?.toString(),
          media: ProductMedia.fromJson(product),
        );
      }).toList(growable: false);
    }

    final rawGroups = await _client
        .from('purchase_plan_supplier_groups_v1')
        .select()
        .eq('plan_id', planId)
        .order('supplier_name')
        .order('currency_code');
    final groups = (rawGroups as List)
        .whereType<Map>()
        .map((row) => PurchasePlanSupplierGroup.fromJson(
              Map<String, dynamic>.from(row),
            ))
        .toList(growable: false);

    return PurchasePlanDraft.fromParts(
      plan: Map<String, dynamic>.from(rawPlan),
      lines: lines,
      supplierGroups: groups,
    );
  }

  Future<PurchasePlanDraft> removePlanLine({
    required PurchasePlanDraft plan,
    required PurchasePlanLine line,
  }) async {
    final response = await _client.rpc(
      'remove_purchase_plan_line_v1',
      params: {
        'p_plan_id': plan.id,
        'p_expected_plan_version': plan.version,
        'p_line_id': line.id,
        'p_operation_key': const Uuid().v4(),
      },
    );
    final planId = _map(response)['plan_id']?.toString();
    if (planId == null || planId.isEmpty) {
      throw const FormatException('El servidor no devolvió el plan editado.');
    }
    final updated = await fetchPlan(planId);
    if (updated == null) {
      throw const FormatException('No se pudo releer el plan editado.');
    }
    return updated;
  }

  Future<PurchasePlanDraft> updatePlanLineQuantity({
    required PurchasePlanDraft plan,
    required PurchasePlanLine line,
    required double quantity,
  }) async {
    final response = await _client.rpc(
      'update_purchase_plan_line_quantity_v1',
      params: {
        'p_plan_id': plan.id,
        'p_expected_plan_version': plan.version,
        'p_line_id': line.id,
        'p_quantity': quantity,
        'p_operation_key': const Uuid().v4(),
      },
    );
    final planId = _map(response)['plan_id']?.toString();
    if (planId == null || planId.isEmpty) {
      throw const FormatException('El servidor no devolvió el plan editado.');
    }
    final updated = await fetchPlan(planId);
    if (updated == null) {
      throw const FormatException('No se pudo releer el plan editado.');
    }
    return updated;
  }

  /// Deja o borra la nota de una línea del plan.
  ///
  /// `frames[plan].with_lines.line_disclosure`: «Alternativa y **nota**». Una
  /// nota en blanco la borra —eso lo normaliza el comando, no el cliente— y el
  /// mismo texto dos veces no mueve la versión del plan pero sí consume su
  /// clave, igual que el resto de los comandos de este dominio.
  Future<PurchasePlanDraft> setPlanLineNote({
    required PurchasePlanDraft plan,
    required PurchasePlanLine line,
    required String? note,
  }) async {
    final response = await _client.rpc(
      'set_purchase_plan_line_note_v1',
      params: {
        'p_plan_id': plan.id,
        'p_expected_plan_version': plan.version,
        'p_line_id': line.id,
        'p_note': note,
        'p_operation_key': const Uuid().v4(),
      },
    );
    final planId = _map(response)['plan_id']?.toString();
    if (planId == null || planId.isEmpty) {
      throw const FormatException('El servidor no devolvió el plan editado.');
    }
    final updated = await fetchPlan(planId);
    if (updated == null) {
      throw const FormatException('No se pudo releer el plan editado.');
    }
    return updated;
  }

  SupplyNeed _needFromCommand(Object? response) {
    final envelope = _map(response);
    final need = envelope['need'];
    if (need is! Map) {
      throw const FormatException(
        'El servidor no devolvió la necesidad actualizada.',
      );
    }
    return SupplyNeed.fromJson(Map<String, dynamic>.from(need));
  }

  Future<List<SupplyNeed>> _enrichProducts(List<SupplyNeed> needs) async {
    final ids = needs
        .map((need) => need.productId)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return needs;

    final response = await _client
        .from('products')
        .select('id,name,sku')
        .inFilter('id', ids);
    final products = <String, Map<String, dynamic>>{
      for (final row in (response as List).whereType<Map>())
        if (row['id'] != null)
          row['id'].toString(): Map<String, dynamic>.from(row),
    };
    return needs.map((need) {
      final product = products[need.productId];
      if (product == null) return need;
      return need.withProduct(
        name: product['name']?.toString(),
        sku: product['sku']?.toString(),
      );
    }).toList(growable: false);
  }

  Future<List<PurchasePrioritySuggestion>> _enrichPriorityMedia(
    List<PurchasePrioritySuggestion> suggestions,
  ) async {
    final ids = suggestions
        .map((suggestion) => suggestion.productId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return suggestions;

    try {
      // Una sola consulta para toda la portada. La imagen es enriquecimiento:
      // si falla su lectura, las necesidades siguen siendo accionables y el
      // tile conserva el monograma canónico en vez de ocultar el feed entero.
      final response = await _client
          .from('products')
          .select('id,image_url_optimized,image_url,image_urls')
          .inFilter('id', ids);
      final products = <String, ProductMedia>{
        for (final row in (response as List).whereType<Map>())
          if (row['id'] != null)
            row['id'].toString():
                ProductMedia.fromJson(Map<String, dynamic>.from(row)),
      };
      return suggestions.map((suggestion) {
        final media = products[suggestion.productId];
        return media == null ? suggestion : suggestion.withMedia(media);
      }).toList(growable: false);
    } catch (_) {
      return suggestions;
    }
  }

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('Respuesta inesperada del servidor.');
  }
}
