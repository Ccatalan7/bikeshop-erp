import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/shared/services/realtime_health.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 2026-10-31: el 30 de octubre cada reconexión del computador del taller
/// venía seguida de una conexión de 26,5 s. Si el socket se cae con una señal
/// de vida en camino, `RealtimeClient` se la pasa a la conexión siguiente, que
/// en su primer latido la da por vencida y se corta sola. El servidor falso de
/// abajo reproduce esa caída: no contesta la primera señal y corta.
void main() {
  test('una conexión nueva no hereda la señal de vida sin respuesta', () async {
    final server = _FakeRealtimeServer();
    final realtime = server.client();
    RealtimeHealth.clearStaleHeartbeatOnOpen(realtime);

    await server.dropAfterFirstHeartbeat(realtime);

    expect(server.connections, hasLength(2),
        reason: 'después de la caída basta una reconexión');
    expect(server.connections.last.closedByClient, isFalse);
    expect(server.connections.last.heartbeatsAnswered, greaterThanOrEqualTo(2),
        reason: 'la conexión nueva sigue latiendo');
    await realtime.disconnect();
  });

  test('sin esa limpieza el SDK todavía corta la conexión nueva', () async {
    // Si este caso falla, el SDK ya olvida la señal al reconectar y
    // RealtimeHealth.clearStaleHeartbeatOnOpen puede salir.
    final server = _FakeRealtimeServer();
    final realtime = server.client();

    await server.dropAfterFirstHeartbeat(realtime);

    expect(server.connections.length, greaterThanOrEqualTo(2));
    expect(server.connections[1].closedByClient, isTrue);
    expect(server.connections[1].closeReason, 'heartbeat timeout');
    await realtime.disconnect();
  });
}

class _FakeRealtimeServer {
  final List<_FakeConnection> connections = [];

  RealtimeClient client() => RealtimeClient(
        'ws://localhost/realtime/v1',
        transport: (url, headers) {
          final connection =
              _FakeConnection(answersHeartbeats: connections.isNotEmpty);
          connections.add(connection);
          return connection;
        },
        heartbeatIntervalMs: 40,
        reconnectAfterMs: (_) => 5,
      );

  /// Opens a connection, lets the first heartbeat go out unanswered, drops
  /// the socket from the server side and watches the next connection beat.
  Future<void> dropAfterFirstHeartbeat(RealtimeClient realtime) async {
    realtime.channel('salud').subscribe();
    await _until(() => connections.isNotEmpty && connections[0].heartbeats > 0);
    connections[0].dropFromServer();
    await _until(() => connections.length >= 2);
    await Future<void>.delayed(const Duration(milliseconds: 220));
  }

  Future<void> _until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('the fake Realtime server never saw the expected traffic');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

class _FakeConnection implements WebSocketChannel {
  _FakeConnection({required this.answersHeartbeats});

  final bool answersHeartbeats;
  final StreamController<dynamic> _toClient = StreamController<dynamic>();
  late final _FakeSink _sink = _FakeSink(this);
  int heartbeats = 0;
  int heartbeatsAnswered = 0;
  bool closedByClient = false;

  @override
  int? closeCode;

  @override
  String? closeReason;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<dynamic> get stream => _toClient.stream;

  @override
  WebSocketSink get sink => _sink;

  void _fromClient(Object? frame) {
    if (frame is! String) return;
    // Protocol 2.0.0 text frames are [join_ref, ref, topic, event, payload].
    final message = jsonDecode(frame);
    if (message is! List || message[2] != 'phoenix') return;
    if (message[3] != 'heartbeat') return;
    heartbeats += 1;
    if (!answersHeartbeats || _toClient.isClosed) return;
    heartbeatsAnswered += 1;
    _toClient.add(jsonEncode([
      null,
      message[1],
      'phoenix',
      'phx_reply',
      {'status': 'ok', 'response': <String, dynamic>{}},
    ]));
  }

  void dropFromServer() {
    closeCode = 1006;
    unawaited(_toClient.close());
  }

  void _closeFromClient(int? code, String? reason) {
    if (_toClient.isClosed) return;
    closedByClient = true;
    closeCode = code;
    closeReason = reason;
    unawaited(_toClient.close());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._connection);

  final _FakeConnection _connection;

  @override
  void add(Object? data) => _connection._fromClient(data);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async =>
      _connection._closeFromClient(closeCode, closeReason);

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
