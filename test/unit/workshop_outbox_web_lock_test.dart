@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/services/workshop_command_outbox.dart';
import 'package:vinabike_erp/public_store/services/cart_lock.dart';

/// El almacenamiento del navegador, compartido por las pestañas: cede el turno
/// en cada lectura y escritura, así dos pestañas pueden leer antes de que una
/// escriba.
class _SharedStorage implements WorkshopOutboxStore {
  final Map<String, String> values = {};

  @override
  Future<Map<String, String>> readAll(String prefix) async {
    await Future<void>.delayed(Duration.zero);
    return {
      for (final entry in values.entries)
        if (entry.key.startsWith(prefix)) entry.key: entry.value,
    };
  }

  @override
  Future<void> write(String key, String value) async {
    await Future<void>.delayed(Duration.zero);
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async => values.remove(key);
}

/// Sin red: ninguna alta llega al servidor, que es el caso que protege la
/// bandeja.
class _Offline implements WorkshopCommandTransport {
  @override
  bool isCurrent(WorkshopCommandScope scope) => true;

  @override
  Future<Map<String, dynamic>> send(
    WorkshopCommandKind kind,
    Map<String, dynamic> params,
  ) async =>
      throw const WorkshopCommandTransportException('sin red');

  @override
  Future<Map<String, dynamic>?> probe(
    WorkshopCommandScope scope,
    PendingWorkshopCommand command,
  ) async =>
      throw const WorkshopCommandTransportException('sin red');

  @override
  Future<void> recordAttempts(List<Map<String, dynamic>> attempts) async =>
      throw const WorkshopCommandTransportException('sin red');

  @override
  Future<Set<String>> referencedImageUrls(
    WorkshopCommandScope scope,
    List<String> urls,
  ) async =>
      const {};

  @override
  Future<void> removeImages(String bucket, List<String> objectPaths) async {}
}

PendingWorkshopCommand _creation(String key) => PendingWorkshopCommand(
      operationKey: key,
      kind: WorkshopCommandKind.bikeAggregateSave,
      params: {
        'p_operation_key': key,
        'p_bike_id': 'bici-$key',
        'p_customer_id': 'cliente-1',
        'p_expected_bike_updated_at': null,
        'p_bike_payload': const {'brand': 'Trek'},
      },
      createdAt: DateTime.utc(2026, 9, 28, 10),
      bikeId: 'bici-$key',
      label: 'Trek $key',
    );

void main() {
  test('la bandeja espera el Web Lock que tiene otra pestaña', () async {
    // Otra pestaña tiene la bandeja tomada: el mismo nombre en el Web Lock
    // del origen. Una cola del proceso no la vería y seguiría de largo.
    final otherTab = createCartLockCoordinator();
    final held = Completer<void>();
    final release = Completer<void>();
    final holding = otherTab.synchronized('workshop-command-outbox', () async {
      held.complete();
      await release.future;
    });
    await held.future;

    final outbox = WorkshopCommandOutbox(
      store: _SharedStorage(),
      transport: _Offline(),
      clientPlatform: 'web-test',
      appVersion: 'test',
    );
    var read = false;
    final reading = outbox
        .pending(const WorkshopCommandScope(tenantId: 't', userId: 'u'))
        .then((_) => read = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(read, isFalse, reason: 'espera a la otra pestaña');

    release.complete();
    await Future.wait([holding, reading]);
    expect(read, isTrue);
  });

  test('dos bandejas del mismo origen respaldan una sola alta a la vez',
      () async {
    const scope = WorkshopCommandScope(tenantId: 'taller', userId: 'mecanico');
    const nothingSeen = WorkshopCreationGuard(
      customerId: 'cliente-1',
      acknowledgedBikeIds: {},
    );
    final storage = _SharedStorage();
    // Dos instancias, cada una con su propio coordinador, como dos pestañas:
    // lo único que comparten es el origen, y con él los Web Locks.
    WorkshopCommandOutbox tab() => WorkshopCommandOutbox(
          store: storage,
          transport: _Offline(),
          clientPlatform: 'web-test',
          appVersion: 'test',
        );
    final tabA = tab();
    final tabB = tab();

    final results = await Future.wait([
      tabA
          .submit(scope, _creation('op-a'), creationGuard: nothingSeen)
          .then<Object>((run) => run, onError: (Object error) => error),
      tabB
          .submit(scope, _creation('op-b'), creationGuard: nothingSeen)
          .then<Object>((run) => run, onError: (Object error) => error),
    ]);

    expect(
      results.whereType<WorkshopPendingCreationException>(),
      hasLength(1),
    );
    expect(
      (await tabA.pendingCreationsFor(scope, 'cliente-1')).creations,
      hasLength(1),
    );
  });
}
