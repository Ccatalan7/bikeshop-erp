import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tenant_broadcast_channel.dart';

/// Revives the Realtime socket when the SDK can no longer do it alone.
///
/// **Por qué existe (2026-10-08).** `RealtimeClient` reconecta solo cuando el
/// socket se cierra, pero esa reconexión se programa DESPUÉS de recorrer los
/// canales avisándoles el error. Si cualquier oyente quita o crea un canal en
/// ese recorrido, el SDK lanza «Concurrent modification during iteration», la
/// reconexión nunca se programa y `connect()` sale sin hacer nada porque el
/// socket viejo sigue asignado. Desde ahí cada `subscribe` espera para siempre:
/// en el Mac del dueño la bandeja estuvo sorda horas (los registros del
/// servidor decían «Tenant has no connected users» con dos apps abiertas) y el
/// mensaje de un proveedor llegó sólo al teléfono.
///
/// El hub ya no toca canales dentro de ese recorrido, pero un SDK que puede
/// quedar así necesita un vigilante: cada pocos segundos —y al volver la app al
/// frente— mira si hay canales y el socket no está abierto ni abriéndose. Dos
/// miradas seguidas así, o una al volver al frente, y lo revive: marca en error
/// los canales que creían estar unidos (así el SDK los vuelve a unir), programa
/// la reconexión del socket y vuelve a unir los temas del hub. Sólo usa la API
/// pública del SDK.
class RealtimeHealth {
  RealtimeHealth._();

  static final RealtimeHealth instance = RealtimeHealth._();

  static const Duration checkInterval = Duration(seconds: 15);

  SupabaseClient? _client;
  Timer? _timer;
  int _downChecks = 0;
  bool _recovering = false;
  final StreamController<void> _recoveries = StreamController<void>.broadcast();

  /// Emits after the socket was revived, so owners re-read what they show:
  /// nothing sent while the socket was dead will be replayed.
  Stream<void> get recoveries => _recoveries.stream;

  /// Starts watching [client]. Idempotent; the first attach wins.
  void attach(SupabaseClient client) {
    if (_client != null) return;
    _client = client;
    _timer = Timer.periodic(checkInterval, (_) => unawaited(check()));
  }

  /// Checks now. [appResumed] revives on the first bad look: the OS often
  /// kills sockets of a backgrounded app without the SDK noticing in time.
  Future<void> check({bool appResumed = false}) async {
    final client = _client;
    if (client == null || _recovering) return;
    final realtime = client.realtime;
    if (realtime.getChannels().isEmpty) {
      _downChecks = 0;
      return;
    }
    final state = realtime.connState;
    final alive =
        state == SocketStates.open || state == SocketStates.connecting;
    if (alive) {
      _downChecks = 0;
      return;
    }
    _downChecks += 1;
    if (!appResumed && _downChecks < 2) return;
    await _revive(client, state);
  }

  Future<void> _revive(SupabaseClient client, SocketStates? state) async {
    _recovering = true;
    _downChecks = 0;
    try {
      final realtime = client.realtime;
      debugPrint(
        '🩺 [RealtimeHealth] socket ${state?.name ?? 'never opened'} with '
        '${realtime.getChannels().length} channels; reviving',
      );
      await realtime.setAuth(client.auth.currentSession?.accessToken);
      // A channel that never heard the error still believes it is joined and
      // would never ask the new socket to join it again. The SDK's own error
      // handler ignores channels that are leaving or closed.
      for (final channel in List.of(realtime.getChannels())) {
        channel.trigger('phx_error', 'socket revived by RealtimeHealth');
      }
      // Drops the dead socket so the next join can open a new one. A closed
      // socket is not closed again: this only forgets it.
      await realtime.disconnect();
      // The hub's joins open the socket right away; without hub topics the
      // SDK's own timer does it. Whichever opens first cancels the other.
      realtime.reconnectTimer.scheduleTimeout();
      await TenantBroadcastHub.instance.rejoinAll();
      _recoveries.add(null);
    } catch (error) {
      debugPrint('⚠️ [RealtimeHealth] revive failed: $error');
    } finally {
      _recovering = false;
    }
  }

  @visibleForTesting
  void detachForTest() {
    _timer?.cancel();
    _timer = null;
    _client = null;
    _downChecks = 0;
  }
}
