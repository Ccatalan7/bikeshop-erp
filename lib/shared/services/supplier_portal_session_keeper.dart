import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef SupplierPortalSessionPing = Future<void> Function(String url);
typedef SupplierPortalSessionUserReader = String? Function();

/// Mantiene vivas las sesiones de proveedor que la app ya demostró activas.
///
/// No inicia sesión, no lee credenciales y no inventa una URL: repite, a baja
/// frecuencia, una navegación GET que acaba de responder autenticada. Esto es
/// especialmente importante para portales legacy con expiración por
/// inactividad. Un cambio de usuario vacía inmediatamente el registro.
class SupplierPortalSessionKeeper {
  SupplierPortalSessionKeeper({
    SupplierPortalSessionPing? ping,
    SupplierPortalSessionUserReader? currentUserId,
    Duration interval = const Duration(minutes: 8),
    bool scheduleAutomatically = true,
  })  : _ping = ping ?? _pingWithHeadlessWebView,
        _currentUserId = currentUserId ??
            (() => Supabase.instance.client.auth.currentUser?.id),
        _interval = interval,
        _scheduleAutomatically = scheduleAutomatically;

  static final SupplierPortalSessionKeeper shared =
      SupplierPortalSessionKeeper();

  static const Duration _loadTimeout = Duration(seconds: 25);

  final SupplierPortalSessionPing _ping;
  final SupplierPortalSessionUserReader _currentUserId;
  final Duration _interval;
  final bool _scheduleAutomatically;
  final Map<String, String> _activeUrls = <String, String>{};

  Timer? _timer;
  String? _userId;
  bool _inFlight = false;

  /// Activa el mantenimiento sólo después de una respuesta autenticada.
  void activate({
    required String supplierId,
    required String url,
  }) {
    final currentUser = _currentUserId()?.trim() ?? '';
    final normalizedSupplierId = supplierId.trim();
    final parsed = Uri.tryParse(url.trim());
    if (currentUser.isEmpty ||
        normalizedSupplierId.isEmpty ||
        parsed == null ||
        !parsed.hasAuthority ||
        parsed.userInfo.isNotEmpty ||
        (parsed.scheme != 'https' && parsed.scheme != 'http')) {
      return;
    }

    if (_userId != currentUser) {
      _reset(currentUser);
    }
    _activeUrls[normalizedSupplierId] = parsed.toString();
    if (_scheduleAutomatically) {
      _timer ??= Timer.periodic(_interval, (_) => unawaited(keepAliveNow()));
    }
  }

  @visibleForTesting
  int get activeSessionCount => _activeUrls.length;

  /// Ejecuta una ronda serial. Es público para una verificación dirigida y
  /// para no esconder el comportamiento detrás de un reloj en las pruebas.
  @visibleForTesting
  Future<void> keepAliveNow() async {
    if (_inFlight || _activeUrls.isEmpty) return;
    final currentUser = _currentUserId()?.trim() ?? '';
    if (currentUser.isEmpty || currentUser != _userId) {
      _reset(currentUser.isEmpty ? null : currentUser);
      return;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;

    _inFlight = true;
    try {
      final urls = List<String>.unmodifiable(_activeUrls.values);
      for (final url in urls) {
        try {
          await _ping(url);
        } catch (error) {
          if (kDebugMode) {
            debugPrint(
              '🛒 Keep-alive de proveedor omitido: ${error.runtimeType}',
            );
          }
        }
      }
    } finally {
      _inFlight = false;
    }
  }

  @visibleForTesting
  void stop() => _reset(null);

  void _reset(String? nextUserId) {
    _timer?.cancel();
    _timer = null;
    _activeUrls.clear();
    _userId = nextUserId;
  }

  static Future<void> _pingWithHeadlessWebView(String url) async {
    Completer<void>? loaded;
    final webView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        incognito: false,
        cacheEnabled: true,
        clearCache: false,
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
      ),
      onLoadStop: (_, __) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
      onReceivedError: (_, __, ___) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
      onReceivedHttpError: (_, __, ___) {
        final pending = loaded;
        if (pending != null && !pending.isCompleted) pending.complete();
      },
    );
    try {
      await webView.run();
      final controller = webView.webViewController;
      if (controller == null) return;
      final pending = Completer<void>();
      loaded = pending;
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      await pending.future.timeout(_loadTimeout);
    } finally {
      await webView.dispose();
    }
  }
}
