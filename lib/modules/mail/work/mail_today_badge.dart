import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mail_work_service.dart';

/// El número del menú en Correo: lo que está «Para hoy» (lo que pide algo),
/// no los no leídos de una bandeja. La pantalla del correo lo actualiza al
/// cargar; fuera de ella se lee cada 3 minutos. Una cuenta sin acceso al
/// correo (el servidor lo niega) deja de preguntar.
class MailTodayBadge extends ValueNotifier<int> {
  MailTodayBadge._() : super(0);

  static final MailTodayBadge instance = MailTodayBadge._();

  Timer? _timer;
  bool _denied = false;

  void ensureStarted() {
    if (_timer != null || _denied || !_signedIn()) return;
    unawaited(_poll());
    _timer =
        Timer.periodic(const Duration(minutes: 3), (_) => unawaited(_poll()));
  }

  /// Sin Supabase inicializado ni una sesión (una prueba que monta el menú,
  /// la pantalla de ingreso) no hay a quién preguntarle: no se lee ni se deja
  /// un temporizador corriendo.
  static bool _signedIn() {
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  void set(int count) {
    if (value != count) value = count;
  }

  Future<void> _poll() async {
    try {
      final counts = await MailWorkService().counts();
      set(counts.today);
    } catch (error) {
      if ('$error'.contains('mail_forbidden')) {
        _denied = true;
        _timer?.cancel();
        _timer = null;
        set(0);
      }
    }
  }

  /// Al cerrar sesión: otra cuenta no hereda el número.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _denied = false;
    set(0);
  }
}
