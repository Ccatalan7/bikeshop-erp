import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/bikeshop/services/service_wizard_service.dart';

void main() {
  test('loads many product profiles with one mapping/target/question read',
      () async {
    final requestedTables = <String>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      httpClient: MockClient((request) async {
        final table = request.url.pathSegments.last;
        requestedTables.add(table);

        final rows = switch (table) {
          'service_product_profile_mappings' => [
              {
                'product_id': 'product-1',
                'tenant_id': 'tenant-1',
                'service_profile_id': 'profile-1',
                'service_profiles': {
                  'id': 'profile-1',
                  'name': 'Centrado de rueda',
                  'service_family': 'wheels',
                  'customer_summary_template': null,
                },
              },
              {
                'product_id': 'product-2',
                'tenant_id': 'tenant-1',
                'service_profile_id': 'profile-1',
                'service_profiles': {
                  'id': 'profile-1',
                  'name': 'Centrado de rueda',
                  'service_family': 'wheels',
                  'customer_summary_template': null,
                },
              },
            ],
          'service_profile_targets' => [
              {
                'tenant_id': null,
                'service_profile_id': 'profile-1',
                'target_family': 'legacy-wheels',
                'target_position_mode': 'none',
              },
              {
                'tenant_id': 'tenant-1',
                'service_profile_id': 'profile-1',
                'target_family': 'wheels',
                'target_position_mode': 'front_rear',
              },
            ],
          // Desde el 2026-08-21 el wizard lee la vista, no la tabla: resuelve
          // las opciones contra el registro de vocabulario cuando la pregunta
          // es un campo de ficha. Sigue siendo UNA lectura para todo el lote,
          // que es lo que esta prueba cuida.
          'service_profile_questions_resolved_v1' => [
              {
                'id': 'question-2',
                'service_profile_id': 'profile-1',
                'key': 'notes',
                'label': 'Notas',
                'question_type': 'text',
                'is_required': false,
                'is_advanced': true,
                'options_json': <dynamic>[],
                'sort_order': 2,
              },
              {
                'id': 'question-1',
                'service_profile_id': 'profile-1',
                'key': 'damage',
                'label': 'Daño observado',
                'question_type': 'single_select',
                'is_required': true,
                'is_advanced': false,
                'options_json': [
                  {'value': 'none', 'label': 'Sin daño'},
                ],
                'sort_order': 1,
              },
            ],
          _ => throw StateError('Unexpected table request: $table'),
        };

        return http.Response(
          jsonEncode(rows),
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    final service = ServiceWizardService(client: client);
    final profiles = await service.getProfilesForProducts(
      const ['product-1', 'product-2', 'product-unmapped', 'product-1'],
    );

    expect(profiles.keys, hasLength(3));
    expect(profiles['product-unmapped'], isNull);
    expect(profiles['product-1']?.id, 'profile-1');
    expect(profiles['product-2']?.id, 'profile-1');
    expect(profiles['product-1']?.targetFamily, 'wheels');
    expect(profiles['product-1']?.targetPositionMode, 'front_rear');
    expect(
      profiles['product-1']?.questions.map((question) => question.key),
      ['damage', 'notes'],
    );
    expect(
      requestedTables
          .where((table) => table == 'service_product_profile_mappings'),
      hasLength(1),
    );
    expect(
      requestedTables.where((table) => table == 'service_profile_targets'),
      hasLength(1),
    );
    expect(
      requestedTables.where(
        (table) => table == 'service_profile_questions_resolved_v1',
      ),
      hasLength(1),
    );
  });
}
