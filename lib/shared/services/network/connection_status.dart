import 'dart:async';

import 'package:flutter/foundation.dart';

/// Cómo está la conexión con el servidor, visto por lo que de verdad se mandó.
enum ConnectionHealth {
  /// Lo último llegó.
  online,

  /// Hay un guardado esperando respuesta hace más de [ConnectionStatus.slowAfter].
  slow,

  /// Lo último no llegó: se reintenta y se prueba el servidor hasta que vuelva.
  offline,
}

/// El estado de la conexión que ve todo el ERP.
///
/// No pregunta al sistema operativo si «hay wifi»: en el taller el wifi sigue
/// conectado cuando VTR se corta. Mira lo que pasa con las peticiones reales
/// (las informa [ResilientHttpClient]) y, mientras está sin conexión, prueba el
/// servidor con una petición mínima cada vez más espaciada (3, 6, 12, 20 s).
class ConnectionStatus extends ChangeNotifier {
  ConnectionStatus({
    Future<bool> Function()? probe,
    this.slowAfter = const Duration(seconds: 6),
    List<Duration>? probeDelays,
  })  : _probe = probe,
        _probeDelays = probeDelays ??
            const [
              Duration(seconds: 3),
              Duration(seconds: 6),
              Duration(seconds: 12),
              Duration(seconds: 20),
            ];

  /// El que usa la app. [main] lo reemplaza por uno con su sonda.
  static ConnectionStatus instance = ConnectionStatus();

  final Duration slowAfter;
  final List<Duration> _probeDelays;
  Future<bool> Function()? _probe;

  bool _offline = false;
  bool _slow = false;
  int _retrying = 0;
  int _probeIndex = 0;
  DateTime? _offlineSince;
  DateTime? _lastReachableAt;
  Timer? _probeTimer;
  bool _probing = false;
  bool _disposed = false;
  final Map<Object, Timer> _writesInFlight = {};
  final Set<Object> _slowWrites = {};
  final StreamController<void> _reconnections =
      StreamController<void>.broadcast();

  ConnectionHealth get health => _offline
      ? ConnectionHealth.offline
      : _slow
          ? ConnectionHealth.slow
          : ConnectionHealth.online;

  bool get isOffline => _offline;

  /// Peticiones que esperan su próximo intento.
  int get retrying => _retrying;

  int get writesInFlight => _writesInFlight.length;

  DateTime? get offlineSince => _offlineSince;
  DateTime? get lastReachableAt => _lastReachableAt;

  /// Emite cada vez que la conexión vuelve después de un corte.
  Stream<void> get reconnections => _reconnections.stream;

  /// La sonda que se usa mientras no hay conexión. Se puede fijar después de
  /// crear el estado, cuando ya existe el cliente.
  set probe(Future<bool> Function()? value) => _probe = value;

  /// Un guardado empezó. Devuelve la ficha que se entrega en [endWrite].
  Object beginWrite() {
    final token = Object();
    _writesInFlight[token] = Timer(slowAfter, () {
      if (_disposed || !_writesInFlight.containsKey(token)) return;
      _slowWrites.add(token);
      _refreshSlow();
    });
    return token;
  }

  void endWrite(Object token) {
    _writesInFlight.remove(token)?.cancel();
    if (_slowWrites.remove(token)) _refreshSlow();
  }

  void retryStarted() {
    _retrying += 1;
    _notify();
  }

  void retryEnded() {
    if (_retrying > 0) _retrying -= 1;
    _notify();
  }

  /// Algo llegó al servidor y volvió con respuesta (cualquier código).
  void reportReachable() {
    _lastReachableAt = DateTime.now();
    if (!_offline) return;
    _offline = false;
    _offlineSince = null;
    _probeIndex = 0;
    _probeTimer?.cancel();
    _probeTimer = null;
    _notify();
    if (!_reconnections.isClosed) _reconnections.add(null);
  }

  /// Una petición no recibió respuesta: sin red, cortada o sin tiempo.
  void reportUnreachable() {
    if (_offline) return;
    _offline = true;
    _offlineSince = DateTime.now();
    _probeIndex = 0;
    _notify();
    _scheduleProbe();
  }

  /// Prueba el servidor ahora (al volver la app al frente, o con «Reintentar»).
  Future<void> checkNow() async {
    if (!_offline) return;
    _probeTimer?.cancel();
    await _runProbe();
  }

  void _scheduleProbe() {
    if (_disposed || !_offline || _probe == null) return;
    _probeTimer?.cancel();
    final delay = _probeDelays[_probeIndex.clamp(0, _probeDelays.length - 1)];
    _probeTimer = Timer(delay, () => unawaited(_runProbe()));
  }

  Future<void> _runProbe() async {
    final probe = _probe;
    if (_disposed || !_offline || probe == null || _probing) return;
    _probing = true;
    var reached = false;
    try {
      reached = await probe();
    } catch (_) {
      reached = false;
    } finally {
      _probing = false;
    }
    if (_disposed) return;
    if (reached) {
      reportReachable();
    } else {
      _probeIndex += 1;
      _scheduleProbe();
    }
  }

  void _refreshSlow() {
    final slow = _slowWrites.isNotEmpty;
    if (slow == _slow) return;
    _slow = slow;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _probeTimer?.cancel();
    for (final timer in _writesInFlight.values) {
      timer.cancel();
    }
    _writesInFlight.clear();
    unawaited(_reconnections.close());
    super.dispose();
  }
}
