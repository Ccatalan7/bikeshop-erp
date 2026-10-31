import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Realtime options for widget tests whose Supabase points at a dead local URL.
///
/// `supabase` 2.16 closes a socket with a 6 s timeout and keeps an emptied
/// socket open for a grace period, so a widget that opens a channel against a
/// server that is not there leaves fake timers behind the test. Here the
/// socket never opens, closes at once, and the client lets it go as soon as
/// its last channel leaves.
const RealtimeClientOptions silentRealtimeOptions = RealtimeClientOptions(
  transport: silentRealtimeTransport,
  disconnectOnEmptyChannelsAfter: Duration.zero,
);

/// A socket that never connects: joins wait in the client's buffer.
WebSocketChannel silentRealtimeTransport(
  String url,
  Map<String, String> headers,
) =>
    _SilentSocket();

class _SilentSocket implements WebSocketChannel {
  final Completer<void> _ready = Completer<void>();
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  late final _SilentSink _sink = _SilentSink(_incoming);

  @override
  Future<void> get ready => _ready.future;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SilentSink implements WebSocketSink {
  _SilentSink(this._incoming);

  final StreamController<dynamic> _incoming;

  @override
  void add(Object? data) {}

  /// Completes at once: nobody listens to a socket that never opened, so
  /// waiting for its stream to finish would wait forever.
  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    if (!_incoming.isClosed) unawaited(_incoming.close());
    return Future<void>.value();
  }

  @override
  Future<void> get done => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
