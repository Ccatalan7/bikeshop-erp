import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../ai_assistant/models/ai_assistant_turn_contracts.dart';
import '../models/intelligent_purchasing_models.dart';

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

    final rows = <Map<String, dynamic>>[];
    const chunkSize = 100;
    for (var offset = 0; offset < ids.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, ids.length);
      final response = await _client
          .from('mechanic_job_supply_attention_v1')
          .select()
          .inFilter('mechanic_job_id', ids.sublist(offset, end));
      rows.addAll(
        (response as List)
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row)),
      );
    }

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
      'create_supply_need_batch_v1',
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
    return items
        .whereType<Map>()
        .map((row) =>
            PurchasePrioritySuggestion.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
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

  Future<SupplyInventorySnapshot> inventorySnapshot(String needId) async {
    final response = await _client.rpc(
      'get_supply_need_inventory_snapshot_v1',
      params: {'p_need_id': needId},
    );
    return SupplyInventorySnapshot.fromJson(_map(response));
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
  }) async {
    final response = await _client.rpc(
      'prepare_purchase_plan_line_v1',
      params: {
        'p_plan_id': plan?.id,
        'p_expected_plan_version': plan?.version,
        'p_source_need_id': need.id,
        'p_candidate_id': candidate.candidateId,
        'p_quantity': need.quantity,
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
      final rawProducts = await _client
          .from('products')
          .select('id,name')
          .inFilter('id', productIds);
      final names = <String, String>{
        for (final row in (rawProducts as List).whereType<Map>())
          if (row['id'] != null && row['name'] != null)
            row['id'].toString(): row['name'].toString(),
      };
      lines = lines
          .map((line) => line.withProductName(names[line.productId]))
          .toList(growable: false);
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

  Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const FormatException('Respuesta inesperada del servidor.');
  }
}
