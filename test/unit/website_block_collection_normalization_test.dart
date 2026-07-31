import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

void main() {
  late SupabaseClient supabase;
  late WebsiteService service;

  setUp(() {
    supabase = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
    service = WebsiteService(
      supabase: supabase,
      tenantService: TenantService.testing(
        currentUserId: () => null,
        profileLookup: (_) async => const [],
      ),
      httpClient: MockClient((_) async => http.Response('{}', 200)),
    );
  });

  tearDown(() {
    service.dispose();
    supabase.dispose();
  });

  test('legacy-only collection is not hidden by an empty canonical default',
      () {
    final normalized = service.normalizeBlockDataForTesting(
      blockType: 'features',
      blockData: const {
        'items': [
          {
            'icon': 'verified',
            'title': 'Persistida',
            'description': 'No se pierde',
          },
        ],
      },
    );

    expect(normalized['features'], normalized['items']);
    expect((normalized['features'] as List).single['title'], 'Persistida');
  });

  test('explicit canonical empty list wins over a stale collection alias', () {
    final normalized = service.normalizeBlockDataForTesting(
      blockType: 'stats',
      blockData: const {
        'metrics': <Map<String, dynamic>>[],
        'stats': [
          {'value': '99', 'label': 'Stale'},
        ],
      },
    );

    expect(normalized['metrics'], isEmpty);
    expect(normalized['stats'], isEmpty);
    expect(normalized['items'], isEmpty);
  });

  test('testimonial comment aliases normalize in both directions', () {
    final normalized = service.normalizeBlockDataForTesting(
      blockType: 'testimonials',
      blockData: const {
        'items': [
          {'name': 'Ana', 'quote': 'Excelente', 'rating': 5},
        ],
      },
    );

    final item = (normalized['testimonials'] as List).single as Map;
    expect(item['comment'], 'Excelente');
    expect(item['quote'], 'Excelente');
    expect(item['text'], 'Excelente');
    expect(normalized['items'], normalized['testimonials']);
  });

  test('pricing normalizes collection, fields and structured action aliases',
      () {
    final normalized = service.normalizeBlockDataForTesting(
      blockType: 'pricing',
      blockData: const {
        'items': [
          {
            'name': 'Legacy',
            'price': '10.000',
            'buttonText': 'Elegir',
            'buttonLink': '/legacy',
            'isFeatured': true,
          },
        ],
      },
    );

    final plan = (normalized['plans'] as List).single as Map;
    expect(plan['ctaText'], 'Elegir');
    expect(plan['buttonText'], 'Elegir');
    expect(plan['ctaLink'], '/legacy');
    expect(plan['buttonLink'], '/legacy');
    expect(plan['highlighted'], isTrue);
    expect(plan['isFeatured'], isTrue);
    expect(plan['actions'], isA<List>());
    expect(normalized['items'], normalized['plans']);
  });

  test('team legacy payload beats defaults and synchronizes nested media', () {
    final normalized = service.normalizeBlockDataForTesting(
      blockType: 'team',
      blockData: const {
        'subtitle': 'Equipo persistido',
        'team': [
          {
            'name': 'Claudio',
            'role': 'Mecánico',
            'image': 'https://cdn.example.com/avatar.png',
          },
        ],
      },
    );

    expect(normalized['description'], 'Equipo persistido');
    expect(normalized['subtitle'], 'Equipo persistido');
    final member = (normalized['members'] as List).single as Map;
    expect(member['name'], 'Claudio');
    expect(member['avatarUrl'], 'https://cdn.example.com/avatar.png');
    expect(member['image'], 'https://cdn.example.com/avatar.png');
    expect(normalized['team'], normalized['members']);
    expect(normalized['items'], normalized['members']);
  });
}
