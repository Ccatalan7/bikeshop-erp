import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 2026-10-08: el escritorio dejó de recibir mensajes porque un oyente de
/// estado quitó y creó canales mientras `RealtimeClient` los recorría; el SDK
/// lanzó «Concurrent modification during iteration» antes de programar la
/// reconexión y el socket quedó muerto hasta cerrar la app. Estas reglas son de
/// forma: el SDK no se puede ejercitar sin un servidor, pero sí se puede
/// impedir que vuelva el patrón que lo rompió.
void main() {
  String read(String path) => File(path).readAsStringSync();
  final hub = read('lib/shared/services/tenant_broadcast_channel.dart');
  final health = read('lib/shared/services/realtime_health.dart');
  final chat = read('lib/modules/messaging/providers/chat_provider.dart');
  final notifications = read('lib/shared/services/notification_service.dart');

  test('el hub nunca entrega un estado dentro del callback del SDK', () {
    final dispatch = hub.substring(
      hub.indexOf('void dispatch('),
      hub.indexOf('Future<void> remove('),
    );
    expect(RegExp(r'Timer\.run\(').allMatches(dispatch).length, 2,
        reason: 'eventos y estados se entregan en otro turno');
    expect(hub, contains('if (!identical(entry.channel, joined)) return;'),
        reason: 'un canal reemplazado no habla por el actual');
  });

  test('el hub vuelve a unir un tema cerrado por el servidor', () {
    expect(hub,
        contains("_scheduleRejoin(entry, reason: 'closed by the server')"));
    expect(hub, contains('Future<void> rejoinAll()'));
  });

  test('el vigilante revive el socket sólo con API pública', () {
    expect(health, contains("channel.trigger('phx_error'"));
    expect(health, contains('await realtime.disconnect();'));
    expect(health, contains('realtime.reconnectTimer.scheduleTimeout();'));
    expect(health, contains('TenantBroadcastHub.instance.rejoinAll()'));
    expect(health, isNot(contains('.rejoin(')),
        reason: 'rejoin() es interno del SDK');
    expect(hub, contains('RealtimeHealth.instance.attach(client)'));
  });

  test('la bandeja relee lo que se perdió al volver', () {
    expect(
        chat,
        contains(
            "resyncAfterRealtimeGap(reason: 'messaging topic joined again')"));
    expect(chat, contains("resyncAfterRealtimeGap(reason: 'socket revived')"));
    expect(chat,
        contains("resyncAfterRealtimeGap(reason: 'application foreground')"));
    expect(chat, contains('RealtimeHealth.instance.check(appResumed: true)'));
    expect(chat, contains('Timer.periodic(safetyRefreshInterval'));
  });

  test('una caída de red no cambia el transporte de la bandeja', () {
    final fallback = chat.substring(
      chat.indexOf('Future<void> _initTenantBroadcastListener('),
      chat.indexOf('void applyIncomingNotification('),
    );
    expect(fallback, contains('isRefusedRealtimeJoin(error)'));
    expect(fallback, contains('!everSubscribed'));
  });

  test('la señal de leído sólo va a apps que la entienden', () {
    // 2026-10-08: la app publicada anunciaba la señal como «Nuevo mensaje
    // recibido», y un navegador debe mostrar algo por cada aviso push.
    final push = read('supabase/functions/push-notification/index.ts');
    final readHandler = push.substring(
      push.indexOf('async function handleConversationRead('),
    );
    expect(readHandler, contains('.in("device_type", ["android", "ios"])'));
    expect(notifications, contains("'device_type': fcmDeviceType(),"));
    final policy =
        read('supabase/functions/push-notification/recipient_policy.ts');
    final readData = policy.substring(
      policy.indexOf('export function buildConversationReadPushData('),
    );
    expect(readData.substring(0, readData.indexOf('\n}\n')),
        isNot(matches(RegExp(r'^\s+conversation_id:', multiLine: true))));
  });

  test('el aviso de escritorio no desarma el tema en cada error', () {
    final status = notifications.substring(
      notifications.indexOf('void _handleDesktopMessageRealtimeStatus('),
      notifications.indexOf('String _describeDesktopRealtimeIssue('),
    );
    expect(status, isNot(contains('_scheduleDesktopMessageRealtimeReconnect')));
  });
}
