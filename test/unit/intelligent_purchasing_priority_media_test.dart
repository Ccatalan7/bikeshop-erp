import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/services/intelligent_purchasing_service.dart';

const _productA = '92000000-0000-4000-8000-000000000201';
const _productB = '92000000-0000-4000-8000-000000000202';

http.Response _json(Object? body, http.BaseRequest request) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );

({IntelligentPurchasingService service, List<Uri> requests}) _service() {
  final requests = <Uri>[];
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      requests.add(request.url);
      final path = request.url.path;
      if (path.endsWith('/rpc/purchase_priority_feed_v1')) {
        return _json({
          'items': [
            {
              'rank': 1,
              'source': 'workshop',
              'entityId': 'need-a',
              'productId': _productA,
              'title': 'Pastillas ZTTO',
              'suggestedQuantity': 1,
              'unit': 'unit',
              'reason': 'Un trabajo de taller lo está esperando',
              'jobContext': {
                'mechanicJobId': 'job-a',
                'jobNumber': 'PG-00525',
                'jobBikeId': 'job-bike-a',
                'bikeId': 'bike-a',
                'bikeBrand': 'Best',
                'bikeModel': 'Otis 29',
                'scope': 'bike',
              },
            },
            {
              'rank': 2,
              'source': 'stockout',
              'entityId': 'stock-b',
              'productId': _productB,
              'title': 'Neumático Maxxis',
              'suggestedQuantity': 2,
              'unit': 'unit',
              'reason': 'Se agotó y se vende',
            },
          ],
        }, request);
      }
      if (path.endsWith('/products')) {
        return _json([
          {
            'id': _productA,
            'image_url_optimized': ' https://cdn/a.webp ',
            'image_url': 'https://cdn/a.jpg',
            'image_urls': ['https://cdn/a.jpg', 'https://cdn/a-extra.jpg'],
          },
          {
            'id': _productB,
            'image_url': 'https://cdn/b.jpg',
          },
        ], request);
      }
      throw StateError('Petición inesperada: ${request.url}');
    }),
  );
  addTearDown(client.dispose);
  return (
    service: IntelligentPurchasingService(client: client),
    requests: requests,
  );
}

class _PriorityActionService extends IntelligentPurchasingService {
  _PriorityActionService({
    required SupabaseClient client,
    required this.workshopNeed,
  }) : super(client: client);

  final SupplyNeed workshopNeed;
  int fetched = 0;
  int created = 0;

  @override
  Future<SupplyNeed?> fetchNeed(String needId) async {
    fetched += 1;
    return needId == workshopNeed.id ? workshopNeed : null;
  }

  @override
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
    created += 1;
    return SupplyNeed.fromJson({
      'id': 'created-need',
      'origin_kind': originKind,
      'original_description': description,
      'product_id': productId,
      'quantity': quantity,
      'unit': unit,
      'identity_state': productId == null ? 'unresolved' : 'confirmed',
      'supply_state': 'open',
      'usage_state': 'pending',
      'version': 1,
      'created_at': '2026-08-25T12:00:00Z',
      'updated_at': '2026-08-25T12:00:00Z',
    });
  }
}

SupplyNeed _workshopNeed() => SupplyNeed.fromJson({
      'id': 'need-a',
      'origin_kind': 'mechanic_job',
      'mechanic_job_id': 'job-a',
      'job_bike_id': 'job-bike-a',
      'original_description': 'Pastillas ZTTO',
      'product_id': _productA,
      'quantity': 1,
      'unit': 'unit',
      'identity_state': 'confirmed',
      'supply_state': 'open',
      'usage_state': 'pending',
      'version': 1,
      'created_at': '2026-08-24T15:16:54Z',
      'updated_at': '2026-08-24T15:16:54Z',
    });

PurchasePrioritySuggestion _prioritySuggestion({
  String source = 'workshop',
  PurchasePriorityJobContext? jobContext,
}) {
  return PurchasePrioritySuggestion(
    rank: 1,
    source: source,
    entityId: source == 'workshop' ? 'need-a' : _productA,
    productId: _productA,
    title: 'Pastillas ZTTO',
    suggestedQuantity: 1,
    unit: 'unit',
    reason: 'Un trabajo de taller lo está esperando',
    jobContext: jobContext,
  );
}

void main() {
  test('el feed pide la terna de imagen en un solo viaje para sus productos',
      () async {
    final harness = _service();

    final suggestions = await harness.service.fetchPurchasePriority();

    expect(suggestions, hasLength(2));
    final productRequests = harness.requests
        .where((uri) => uri.path.endsWith('/products'))
        .toList(growable: false);
    expect(productRequests, hasLength(1));
    final select = productRequests.single.queryParameters['select'];
    for (final column in const [
      'id',
      'image_url_optimized',
      'image_url',
      'image_urls',
    ]) {
      expect(select, contains(column), reason: 'falta la columna $column');
    }
  });

  test('cada sugerencia conserva el orden de resolución de la ficha', () async {
    final harness = _service();

    final suggestions = await harness.service.fetchPurchasePriority();

    expect(suggestions.first.media.resolutionChain, const [
      'https://cdn/a.webp',
      'https://cdn/a.jpg',
      'https://cdn/a-extra.jpg',
    ]);
    expect(suggestions.last.media.primaryUrl, 'https://cdn/b.jpg');
  });

  test('el contexto de taller conserva trabajo y bicicleta exactos', () async {
    final harness = _service();

    final suggestion = (await harness.service.fetchPurchasePriority()).first;

    expect(suggestion.jobContext?.mechanicJobId, 'job-a');
    expect(suggestion.jobContext?.jobBikeId, 'job-bike-a');
    expect(suggestion.jobContext?.displayLabel, 'PG-00525 · Best Otis 29');
  });

  test('tomar una fila de taller abre su necesidad sin crear otra', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async => _json({}, request)),
    );
    addTearDown(client.dispose);
    final service = _PriorityActionService(
      client: client,
      workshopNeed: _workshopNeed(),
    );
    final suggestion = _prioritySuggestion(
      jobContext: const PurchasePriorityJobContext(
        mechanicJobId: 'job-a',
        jobNumber: 'PG-00525',
        scope: 'bike',
        jobBikeId: 'job-bike-a',
        bikeId: 'bike-a',
        bikeBrand: 'Best',
        bikeModel: 'Otis 29',
      ),
    );

    final result = await service.takePrioritySuggestion(suggestion);

    expect(result.id, 'need-a');
    expect(result.mechanicJobId, 'job-a');
    expect(result.jobBikeId, 'job-bike-a');
    expect(service.fetched, 1);
    expect(service.created, 0);
  });

  test('tomar un quiebre sí crea una nueva necesidad directa', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async => _json({}, request)),
    );
    addTearDown(client.dispose);
    final service = _PriorityActionService(
      client: client,
      workshopNeed: _workshopNeed(),
    );

    final result = await service.takePrioritySuggestion(
      _prioritySuggestion(source: 'stockout'),
    );

    expect(result.originKind, 'ad_hoc');
    expect(service.fetched, 0);
    expect(service.created, 1);
  });

  test('la búsqueda conjunta manda sólo identidades y conserva el orden',
      () async {
    Map<String, dynamic>? command;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/rpc/take_purchase_priority_batch_v1')) {
          command = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          return _json({
            'needs': [
              {
                'id': 'need-a',
                'origin_kind': 'mechanic_job',
                'mechanic_job_id': 'job-a',
                'job_bike_id': 'job-bike-a',
                'original_description': 'Pastillas ZTTO',
                'product_id': _productA,
                'quantity': 1,
                'unit': 'unit',
                'identity_state': 'confirmed',
                'supply_state': 'open',
                'usage_state': 'pending',
                'version': 1,
              },
              {
                'id': 'need-b',
                'origin_kind': 'ad_hoc',
                'original_description': 'Neumático Maxxis',
                'product_id': _productB,
                'quantity': 2,
                'unit': 'unit',
                'identity_state': 'confirmed',
                'supply_state': 'open',
                'usage_state': 'not_applicable',
                'version': 1,
              },
            ],
          }, request);
        }
        if (request.url.path.endsWith('/products')) {
          return _json([
            {'id': _productA},
            {'id': _productB},
          ], request);
        }
        throw StateError('Petición inesperada: ${request.url}');
      }),
    );
    addTearDown(client.dispose);
    final service = IntelligentPurchasingService(client: client);
    final suggestions = [
      _prioritySuggestion(
        jobContext: const PurchasePriorityJobContext(
          mechanicJobId: 'job-a',
          jobNumber: 'PG-00525',
          scope: 'bike',
          jobBikeId: 'job-bike-a',
        ),
      ),
      const PurchasePrioritySuggestion(
        rank: 2,
        source: 'stockout',
        entityId: _productB,
        productId: _productB,
        title: 'Neumático Maxxis',
        suggestedQuantity: 2,
        unit: 'unit',
        reason: 'Se agotó y se vende',
      ),
    ];

    final needs = await service.takePriorityBatch(
      suggestions: suggestions,
      operationKey: 'priority-batch-test-key',
    );

    expect(needs.map((need) => need.id), ['need-a', 'need-b']);
    expect(command?['p_operation_key'], 'priority-batch-test-key');
    expect(command?['p_rotation_days'], 120);
    expect(command?['p_items'], [
      {'source': 'workshop', 'entityId': 'need-a'},
      {'source': 'stockout', 'entityId': _productB},
    ]);
    expect(command.toString(), isNot(contains('suggestedQuantity')));
    expect(command.toString(), isNot(contains('Pastillas ZTTO')));
  });

  test('la búsqueda conjunta exige al menos dos filas', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async => _json({}, request)),
    );
    addTearDown(client.dispose);
    final service = IntelligentPurchasingService(client: client);

    await expectLater(
      service.takePriorityBatch(
        suggestions: [_prioritySuggestion()],
        operationKey: 'priority-batch-too-short',
      ),
      throwsArgumentError,
    );
  });
}
