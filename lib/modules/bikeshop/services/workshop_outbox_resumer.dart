import 'dart:async';

import 'package:flutter/foundation.dart';

import 'workshop_command_notices.dart';
import 'workshop_command_outbox.dart';

/// Reenvía lo que quedó en la bandeja del equipo sin que nadie abra la bici o
/// el trabajo: al abrir la sesión (y ahí también barre las fotos que nadie
/// reclama), al volver la app al frente y cada cinco minutos. Avisa sólo lo
/// definitivo; lo que sigue sin red no se repite en cada vuelta. Al abrir la
/// sesión reenvía todo; las vueltas siguientes esperan más después de cada
/// intento (`WorkshopCommandOutbox.backoffAfter`).
class WorkshopOutboxResumer {
  WorkshopOutboxResumer({
    WorkshopCommandOutbox? outbox,
    this.interval = const Duration(minutes: 5),
  }) : _outbox = outbox;

  final WorkshopCommandOutbox? _outbox;
  final Duration interval;

  WorkshopCommandScope? _scope;
  void Function(String message)? _notify;
  Timer? _timer;
  bool _running = false;

  /// Otra sesión arrancó mientras corría la anterior: al terminar, se reanuda
  /// la nueva sin esperar la vuelta periódica (revisión de Codex, 2026-09-28).
  bool _restartRequested = false;

  WorkshopCommandOutbox get _box => _outbox ?? WorkshopCommandOutbox.shared;

  void start({
    required String tenantId,
    required String userId,
    required void Function(String message) notify,
  }) {
    stop();
    _scope = WorkshopCommandScope(tenantId: tenantId, userId: userId);
    _notify = notify;
    unawaited(resumeNow(sweepImages: true, respectBackoff: false));
    _timer = Timer.periodic(interval, (_) => unawaited(resumeNow()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _scope = null;
    _notify = null;
  }

  Future<void> resumeNow({
    bool sweepImages = false,
    bool respectBackoff = true,
  }) async {
    final scope = _scope;
    if (scope == null) return;
    if (_running) {
      if (sweepImages) _restartRequested = true;
      return;
    }
    _running = true;
    try {
      final runs = await _box.resume(
        scope,
        sweepImages: sweepImages,
        respectBackoff: respectBackoff,
      );
      if (runs.isNotEmpty) {
        debugPrint(
            '🧰 Bandeja del taller: ${runs.map((run) => '${run.command.kind.wireName}:${run.outcome.name}').join(', ')}');
      }
      // La sesión pudo cambiar mientras tanto: no se avisa a otra persona.
      if (!identical(scope, _scope)) return;
      for (final run in runs) {
        final message = workshopCommandNotice(run);
        if (message != null) _notify?.call(message);
      }
    } catch (error, stackTrace) {
      debugPrint(
          'No se pudo retomar la bandeja del taller: $error\n$stackTrace');
    } finally {
      _running = false;
      if (_restartRequested && _scope != null) {
        _restartRequested = false;
        unawaited(resumeNow(sweepImages: true, respectBackoff: false));
      }
    }
  }
}
