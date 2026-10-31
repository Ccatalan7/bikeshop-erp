import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-10-31: el ciclo anterior gastó 20,8 GB de tráfico de Supabase para un
/// taller con un puñado de usuarios. No eran visitas: avisos releídos cada
/// 20 s, la bandeja de tareas cada 30 s y el chat cada 90 s con Realtime vivo,
/// y otra vez en cada reconexión de un socket que se cortaba cada 51 s. Con
/// Realtime vivo, releer es la red de seguridad y no el transporte
/// (`docs/architecture/async-data-loading-contract.md`).
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('los avisos se releen cada cinco minutos con el tema vivo', () {
    final shell = read('lib/main.dart');
    expect(
      shell,
      contains(
        'static const Duration _erpNotificationsLiveReadEvery = '
        'Duration(minutes: 5);',
      ),
    );
    expect(shell, contains('void _refreshErpNotificationsWhenDue('));
    expect(shell, contains('every: _erpNotificationsLiveReadEvery,'));
    expect(
      shell,
      isNot(
          contains('const Duration(seconds: 20),\n        (_) => unawaited(')),
      reason: 'el temporizador mira el reloj; no relee cada 20 s',
    );
  });

  test('la bandeja de tareas no relee con el canal suscrito', () {
    final tasks = read('lib/modules/tasks/services/task_service.dart');
    expect(
      tasks,
      contains(
        'static const Duration _tasksLiveReadEvery = Duration(minutes: 30);',
      ),
    );
    expect(tasks, contains('_refreshTasksWhenDue(_tasksRejoinReadEvery);'));
    expect(
      tasks,
      isNot(contains('(_) => unawaited(fetchTasks()),')),
      reason: 'ningún temporizador relee la bandeja entera por sí solo',
    );
  });

  test('el chat espacia la red de seguridad y las reuniones del tema', () {
    final chat = read('lib/modules/messaging/providers/chat_provider.dart');
    expect(
      chat,
      contains(
        'static const Duration liveSafetyRefreshInterval = '
        'Duration(minutes: 5);',
      ),
    );
    expect(chat, contains('topicRejoinResyncSpacing)'));
    expect(chat, contains('_messagingTopicLive = status =='));
  });

  test('las garantías de la lista se piden en páginas y por taller', () {
    final service = read('lib/modules/bikeshop/services/bikeshop_service.dart');
    final hydrate = service.substring(
      service.indexOf('Future<List<MechanicJob>> _hydrateServiceWarranties('),
      service.indexOf('Future<List<MechanicJob>> _hydrateJobTimeMetrics('),
    );
    expect(hydrate, contains('start += _warrantyJobIdsPerRead'));
    expect(hydrate, contains(".inFilter('tenant_id', tenantIds)"));
    expect(hydrate, contains('.select(_listWarrantyColumns)'));
  });
}
