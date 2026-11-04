import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'connection_status.dart';
import 'request_safety.dart';
import 'transport_failure.dart';
import 'unsaved_changes_journal.dart';

/// Cuánto se espera y cuántas veces se intenta.
@immutable
class ResilientHttpPolicy {
  const ResilientHttpPolicy({
    this.maxAttempts = 6,
    this.retryBudget = const Duration(seconds: 40),
    this.backoff = const [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
    this.readTimeout = const Duration(seconds: 45),
    this.writeTimeout = const Duration(seconds: 60),
    this.functionTimeout = const Duration(seconds: 180),
    this.idleTimeout = const Duration(seconds: 60),
    this.maxReplayableBody = 64 * 1024 * 1024,
  });

  final int maxAttempts;

  /// Tiempo total para reintentar una petición antes de rendirse.
  final Duration retryBudget;
  final List<Duration> backoff;
  final Duration readTimeout;
  final Duration writeTimeout;

  /// Las funciones del borde (Gemini corta a los 150 s) esperan más.
  final Duration functionTimeout;
  final Duration idleTimeout;

  /// Cuerpo máximo que se guarda en memoria para poder reintentar.
  final int maxReplayableBody;

  Duration headerTimeoutFor(RequestSafety safety) => switch (safety.effect) {
        RequestEffect.function => functionTimeout,
        RequestEffect.read => readTimeout,
        _ => writeTimeout,
      };

  Duration delayBefore(int attempt, math.Random random) {
    final base = backoff[(attempt - 1).clamp(0, backoff.length - 1)];
    // ±20 % para que dos equipos no reintenten al mismo tiempo.
    final jitter = 0.8 + random.nextDouble() * 0.4;
    return Duration(milliseconds: (base.inMilliseconds * jitter).round());
  }
}

/// El cliente HTTP de todo el ERP: tiempo límite, reintentos seguros y la
/// bandeja de lo que no llegó.
///
/// Reemplaza al cliente de fábrica de Supabase, que mandaba cada petición una
/// sola vez y sin tiempo límite (ver [classifyRequest] para el porqué). Para
/// cada petición:
///
/// 1. **Tiempo límite** por intento: 45 s una lectura, 60 s un guardado,
///    180 s una función del borde. Nada queda colgado para siempre.
/// 2. **Si no salió** ([TransportFailure.notSent]: sin red, sin conexión),
///    se reintenta cualquier cosa: el servidor no recibió nada.
/// 3. **Si salió y se cortó**, sólo se reintenta lo que no puede quedar dos
///    veces ([RequestSafety.replayIsHarmless]): lecturas, comandos con llave
///    de operación y cambios repetibles. Un alta sin llave no se repite.
/// 4. **503 y 429** (el servidor no lo procesó) se reintentan siempre;
///    502, 504 y 520–524 sólo si es repetible.
/// 5. Si se agota el plazo, el guardado queda en [UnsavedChangesJournal]
///    («Sin guardar») y quien llamó recibe el mismo error que antes.
///
/// [ConnectionStatus] se entera de cada resultado: es lo que dice «Sin
/// conexión · reintentando» y «Guardando… la conexión está lenta».
class ResilientHttpClient extends http.BaseClient {
  ResilientHttpClient({
    required StageAwareSender sender,
    ConnectionStatus? status,
    UnsavedChangesJournal? journal,
    this.policy = const ResilientHttpPolicy(),
    Future<void> Function(Duration delay)? delay,
    math.Random? random,
  })  : _sender = sender,
        _status = status,
        _journal = journal,
        _delay = delay ?? Future<void>.delayed,
        _random = random ?? math.Random();

  final StageAwareSender _sender;
  final ConnectionStatus? _status;
  final UnsavedChangesJournal? _journal;
  final ResilientHttpPolicy policy;
  final Future<void> Function(Duration delay) _delay;
  final math.Random _random;

  /// Corte simulado para probar la app real sin cortar la red del equipo (la
  /// app de depuración trabaja contra producción): con él nada sale del
  /// equipo. Sólo en depuración; se arma con
  /// `ext.vinabike.network.simulateOffline?enabled=true`.
  static bool _debugOffline = false;
  static bool _debugExtensionRegistered = false;

  static bool get debugSimulatingOffline => kDebugMode && _debugOffline;

  static void registerDebugExtension() {
    if (!kDebugMode || _debugExtensionRegistered) return;
    _debugExtensionRegistered = true;
    developer.registerExtension('ext.vinabike.network.simulateOffline',
        (_, params) async {
      _debugOffline = params['enabled'] == 'true';
      if (!_debugOffline) unawaited(ConnectionStatus.instance.checkNow());
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'result': 'corte simulado: $_debugOffline'}),
      );
    });
  }

  ConnectionStatus get _connection => _status ?? ConnectionStatus.instance;
  UnsavedChangesJournal get _unsaved =>
      _journal ?? UnsavedChangesJournal.instance;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final replayOf = request.headers.remove(UnsavedChangesJournal.replayHeader);
    final body = await _bufferBody(request);
    final safety = classifyRequest(
      request.method,
      request.url,
      headers: request.headers,
      body: body ?? const [],
    );
    final writeToken = safety.isWrite ? _connection.beginWrite() : null;
    final started = DateTime.now();
    var attempt = 0;
    try {
      while (true) {
        attempt += 1;
        final outgoing = body == null ? request : _copy(request, body);
        try {
          if (debugSimulatingOffline) {
            throw TransportFailure(
              uri: request.url,
              cause: 'Sin red (corte simulado en depuración)',
              notSent: true,
            );
          }
          final response = await _sender.send(
            outgoing,
            headerTimeout: policy.headerTimeoutFor(safety),
            idleTimeout: policy.idleTimeout,
            freshConnection: !safety.replayIsHarmless,
          );
          _connection.reportReachable();
          if (_shouldRetryStatus(response.statusCode, safety) &&
              body != null &&
              _hasRoomFor(attempt, started)) {
            await _drain(response);
            await _wait(attempt);
            continue;
          }
          if (safety.isWrite &&
              response.statusCode >= 200 &&
              response.statusCode < 300) {
            _unsaved.noteSuccess(
              safety,
              body == null ? null : UnsavedChangesJournal.bodyHashOf(body),
            );
          }
          return response;
        } on TransportFailure catch (failure) {
          _connection.reportUnreachable();
          final retryable = body != null &&
              (failure.notSent ||
                  (safety.replayIsHarmless &&
                      safety.effect != RequestEffect.auth &&
                      safety.effect != RequestEffect.function));
          if (retryable && _hasRoomFor(attempt, started)) {
            await _wait(attempt);
            continue;
          }
          final kept = safety.belongsInJournal && replayOf == null;
          if (kept) {
            unawaited(_unsaved.record(
              request: request,
              safety: safety,
              body: body,
              notSent: failure.notSent,
              error: failure.cause,
            ));
          }
          debugPrint('🌐 [Red] ${request.method} ${safety.technicalName} '
              'tras $attempt intento(s): $failure');
          throw failure.toClientException(kept: kept);
        }
      }
    } finally {
      if (writeToken != null) _connection.endWrite(writeToken);
    }
  }

  bool _hasRoomFor(int attempt, DateTime started) =>
      attempt < policy.maxAttempts &&
      DateTime.now().difference(started) < policy.retryBudget;

  Future<void> _wait(int attempt) async {
    _connection.retryStarted();
    try {
      await _delay(policy.delayBefore(attempt, _random));
    } finally {
      _connection.retryEnded();
    }
  }

  static bool _shouldRetryStatus(int status, RequestSafety safety) {
    if (status == 503 || status == 429) return true;
    final gateway =
        status == 502 || status == 504 || (status >= 520 && status <= 524);
    return gateway &&
        safety.replayIsHarmless &&
        safety.effect != RequestEffect.auth;
  }

  /// El cuerpo en memoria, para poder mandarlo otra vez. `null` sólo si se
  /// sabe de antemano que es tan grande que no conviene: entonces sale una
  /// sola vez, como antes (leerlo para medirlo ya lo consumiría).
  Future<List<int>?> _bufferBody(http.BaseRequest request) async {
    if (request is http.Request) return request.bodyBytes;
    final length = request.contentLength;
    if (length != null && length > policy.maxReplayableBody) return null;
    return request.finalize().toBytes();
  }

  static http.Request _copy(http.BaseRequest original, List<int> body) {
    final copy = http.Request(original.method, original.url)
      ..followRedirects = original.followRedirects
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection;
    copy.headers.addAll(original.headers);
    copy.bodyBytes = body;
    // `bodyBytes` no toca el content-type, pero sí lo conserva si venía.
    return copy;
  }

  static Future<void> _drain(http.StreamedResponse response) async {
    try {
      await response.stream.drain<void>();
    } catch (_) {
      // Un cuerpo que no se pudo leer no cambia que haya que reintentar.
    }
  }

  @override
  void close() => _sender.close();
}
