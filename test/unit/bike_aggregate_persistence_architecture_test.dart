import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';

void main() {
  test('bike aggregate response parses identity and optional profile together',
      () {
    final aggregate = BikeAggregate.fromJson({
      'bike': {
        'id': 'bike-1',
        'tenant_id': 'tenant-1',
        'customer_id': 'customer-1',
        'brand': 'Example',
        'model': 'Trail',
        'image_urls': <String>[],
        'created_at': '2026-07-14T12:00:00Z',
        'updated_at': '2026-07-14T12:00:00Z',
      },
      'profile': {
        'id': 'profile-1',
        'tenant_id': 'tenant-1',
        'bike_id': 'bike-1',
        'intake_profile': <String, dynamic>{},
        'technical_profile': {
          'values': {'brakeType': 'rim'},
          'sources': {'brakeType': 'mechanic'},
          'confirmed': {'brakeType': true},
        },
        'summary_snapshot': <String, dynamic>{},
        'created_at': '2026-07-14T12:00:00Z',
        'updated_at': '2026-07-14T12:00:00Z',
      },
    });

    expect(aggregate.bike.id, 'bike-1');
    expect(aggregate.profile?.technicalValues['brakeType'], 'rim');
    expect(aggregate.profile?.technicalConfirmed['brakeType'], isTrue);
  });

  test('malformed aggregate profile cannot masquerade as an absent ficha', () {
    expect(
      () => BikeAggregate.fromJson({
        'bike': {
          'id': 'bike-1',
          'tenant_id': 'tenant-1',
          'customer_id': 'customer-1',
          'image_urls': <String>[],
          'created_at': '2026-07-14T12:00:00Z',
          'updated_at': '2026-07-14T12:00:00Z',
        },
        'profile': <String>['invalid'],
      }),
      throwsFormatException,
    );
  });

  test('malformed profile maps force aggregate load failure', () {
    expect(
      () => BikeAggregate.fromJson({
        'bike': {
          'id': 'bike-1',
          'tenant_id': 'tenant-1',
          'customer_id': 'customer-1',
          'image_urls': <String>[],
          'created_at': '2026-07-14T12:00:00Z',
          'updated_at': '2026-07-14T12:00:00Z',
        },
        'profile': {
          'intake_profile': <String, dynamic>{},
          'technical_profile': <String>['invalid'],
          'summary_snapshot': <String, dynamic>{},
        },
      }),
      throwsFormatException,
    );
  });

  test('save response requires durable operation metadata', () {
    final response = {
      'bike': {
        'id': 'bike-1',
        'tenant_id': 'tenant-1',
        'customer_id': 'customer-1',
        'image_urls': <String>[],
        'created_at': '2026-07-14T12:00:00Z',
        'updated_at': '2026-07-14T12:00:00Z',
      },
      'profile': null,
      'replayed': false,
    };

    expect(
      () => BikeAggregateSaveResult.fromJson(response),
      throwsFormatException,
    );
  });

  test('canonical bike form consumes only the atomic aggregate command', () {
    final source = File(
      'lib/modules/bikeshop/pages/bike_form_dialog.dart',
    ).readAsStringSync();

    expect(source, contains('saveBikeAggregate('));
    expect(source, contains('getBikeAggregate('));
    expect(source, contains('getBikeAggregateSaveOperation('));
    expect(source, contains('_hydrateBikeIdentity(aggregate.bike)'));
    expect(source, isNot(contains('bikeshopService.createBike(')));
    expect(source, isNot(contains('bikeshopService.updateBike(')));
    expect(source, isNot(contains('service.upsertBikeProfile(')));
  });

  test('failed aggregate reads cannot masquerade as an editable empty ficha',
      () {
    final source = File(
      'lib/modules/bikeshop/pages/bike_form_dialog.dart',
    ).readAsStringSync();

    expect(source, contains('_BikeAggregateLoadState.failed'));
    expect(source, contains('_BikeAggregateLoadState.outcomeUnknown'));
    expect(source, contains('_loadNewBikeReferences'));
    expect(source, contains('No se pudo cargar la ficha técnica'));
    expect(source, contains('absorbing: _aggregateLoadBlocksEditing'));
    expect(source, contains('_isSaving || _aggregateLoadBlocksEditing'));
    expect(source, contains('Reintentar'));
    expect(source, contains('Confirmar guardado'));
    expect(source, contains('canPop:'));
    expect(source, contains('_confirmConflictReload'));
  });

  test('technical bike wizard isolates dropdown state and scrolls its map', () {
    final source = File(
      'lib/modules/bikeshop/pages/bike_form_dialog.dart',
    ).readAsStringSync();

    expect(source, contains("'code-dropdown:\$label:"));
    expect(source, contains("'string-dropdown:\$label:"));
    expect(source, contains("'int-dropdown:\$label:"));
    expect(source, contains('isExpanded: true'));
    expect(
      source,
      contains(
        'SingleChildScrollView(\n'
        '                    child: _buildTechnicalSchemaNavigator(',
      ),
    );
  });

  test('database snapshot and service expose the shared atomic contract', () {
    final service = File(
      'lib/modules/bikeshop/services/bikeshop_service.dart',
    ).readAsStringSync();
    final schema = File('supabase/sql/core_schema.sql').readAsStringSync();
    final migration = File(
      'supabase/migrations/20260714120000_add_atomic_bike_aggregate_save.sql',
    ).readAsStringSync();

    expect(service, contains("'save_bike_aggregate'"));
    expect(service, contains("'get_bike_aggregate'"));
    expect(
      schema,
      contains(
        r'\ir ../migrations/20260714120000_add_atomic_bike_aggregate_save.sql',
      ),
    );
    expect(migration, contains('bike_aggregate_save_operations'));
    expect(migration, contains('pg_advisory_xact_lock'));
    expect(migration, contains('p_expected_profile_updated_at'));
    expect(migration, contains('v_effective_model_id'));
    expect(migration, contains("'profile', p_profile_payload"));
    expect(migration, contains('v_operation.result_snapshot'));
    expect(
      migration,
      contains('Bicycle customer cannot be reassigned'),
    );
    expect(
      migration,
      contains("p_profile_payload ? 'intake_profile'"),
    );
    expect(
      migration,
      contains('Exactly one active employee tenant is required'),
    );
    expect(migration, contains("'replayed', true"));
    expect(
      File(
        'lib/modules/bikeshop/pages/bike_form_dialog.dart',
      ).readAsStringSync(),
      contains('_pendingSaveConfirmedAt'),
    );
  });

  test('every bicycle editor host is registered on the shared contract', () {
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(registry, contains('## Bicycle And Technical-Profile Surfaces'));
    expect(registry, contains('mechanic_job_form_page.dart'));
    expect(registry, contains('client_logbook_page.dart'));
    expect(registry, contains('pegas_table_page.dart'));
    expect(registry, contains('pegas_calendar_widget.dart'));
    expect(registry, contains('saveBikeAggregate'));
  });

  test('debug fixture cannot recreate the paired bike and profile write', () {
    final source = File(
      'lib/modules/bikeshop/pages/pegas_table_page.dart',
    ).readAsStringSync();

    expect(source, contains('saveBikeAggregate('));
    expect(source, isNot(contains('_ensureDebugBikeProfile(')));
    expect(source, isNot(contains('_bikeshopService.createBike(desiredBike)')));
    expect(
      source,
      isNot(contains('_bikeshopService.upsertBikeProfile(profile)')),
    );
  });
}
