import 'package:supabase_flutter/supabase_flutter.dart';

/// Why an operation cannot run right now.
enum WebsiteSeoOperationBlocker {
  /// Search Console has never been connected for this tenant.
  notConnected,

  /// The saved grant exists but no longer authorizes the write scope.
  reconnectRequired,

  /// The backend reports the integration is not configured for this tenant.
  notConfigured,

  /// The signed-in user lacks the website SEO editor authorization.
  notAuthorized,
}

extension WebsiteSeoOperationBlockerCopy on WebsiteSeoOperationBlocker {
  String get explanation => switch (this) {
        WebsiteSeoOperationBlocker.notConnected =>
          'Conecta Search Console para habilitar esta acción.',
        WebsiteSeoOperationBlocker.reconnectRequired =>
          'La autorización de Google caducó o no cubre el envío. Reconecta '
              'Search Console una vez.',
        WebsiteSeoOperationBlocker.notConfigured =>
          'Esta integración no está configurada en el servidor para tu '
              'tienda.',
        WebsiteSeoOperationBlocker.notAuthorized =>
          'Tu cuenta no tiene permiso para operar el SEO de la tienda.',
      };
}

/// Outcome of a Google operation, reported exactly as the backend described it.
///
/// The client never infers success. A non-2xx response, a missing `ok`, or a
/// thrown error all produce [succeeded] == false with the server's own message.
class WebsiteSeoOperationResult {
  const WebsiteSeoOperationResult({
    required this.succeeded,
    required this.observedAt,
    this.message = '',
    this.blocker,
    this.details = const {},
  });

  factory WebsiteSeoOperationResult.failure({
    required DateTime observedAt,
    required String message,
    WebsiteSeoOperationBlocker? blocker,
  }) {
    return WebsiteSeoOperationResult(
      succeeded: false,
      observedAt: observedAt,
      message: message,
      blocker: blocker,
    );
  }

  final bool succeeded;
  final DateTime observedAt;
  final String message;
  final WebsiteSeoOperationBlocker? blocker;
  final Map<String, dynamic> details;

  /// The wording shown next to the action. Never promises indexing.
  String get humanMessage {
    final trimmed = message.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final blockerText = blocker?.explanation ?? '';
    if (blockerText.isNotEmpty) return blockerText;
    return succeeded
        ? 'Google aceptó la solicitud. No garantiza rastreo ni indexación.'
        : 'La operación no se completó.';
  }
}

/// Whether Search Console is currently connected for this tenant.
class WebsiteSeoConnectionStatus {
  const WebsiteSeoConnectionStatus({
    required this.connected,
    required this.observedAt,
    this.accountEmail = '',
    this.siteUrl = '',
    this.error = '',
    this.blocker,
  });

  const WebsiteSeoConnectionStatus.unknown({required this.observedAt})
      : connected = false,
        accountEmail = '',
        siteUrl = '',
        error = '',
        blocker = null;

  final bool connected;
  final DateTime observedAt;
  final String accountEmail;

  /// The Search Console property resolved **by the backend** from this
  /// tenant's `store_url`. It is never composed in the client.
  final String siteUrl;
  final String error;
  final WebsiteSeoOperationBlocker? blocker;

  bool get isAvailable => error.isEmpty && blocker == null;

  /// The reason to show when the status itself could not be read. Prefers the
  /// typed blocker over a transport string so the operator sees an action.
  String get unavailableReason {
    final blockerText = blocker?.explanation ?? '';
    if (blockerText.isNotEmpty) return blockerText;
    return error.trim();
  }
}

/// A consent URL minted by the backend, or the typed reason it was refused.
///
/// `startConnection` never throws a raw transport error at the UI: an operator
/// needs "no disponible y por qué", not a stack-shaped string.
class WebsiteSeoConnectionStart {
  const WebsiteSeoConnectionStart({
    this.authUrl,
    this.message = '',
    this.blocker,
  });

  final Uri? authUrl;
  final String message;
  final WebsiteSeoOperationBlocker? blocker;

  bool get isReady => authUrl != null;

  String get humanMessage {
    final trimmed = message.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final blockerText = blocker?.explanation ?? '';
    if (blockerText.isNotEmpty) return blockerText;
    return 'Google no devolvió una URL de autorización.';
  }
}

typedef WebsiteSeoFunctionInvoker = Future<({int status, Object? data})>
    Function(String function, Map<String, dynamic> body);

typedef WebsiteSeoOperationsClock = DateTime Function();

/// Typed client for the tenant-scoped Google operations the backend already
/// exposes.
///
/// Design rules this service enforces:
///
/// * every target (store origin, Search Console property, sitemap URL,
///   Merchant account) is resolved **server side** from tenant settings, so no
///   domain, project reference or account id is ever written in the client;
/// * no credential, token or secret crosses this boundary; and
/// * an unavailable or unauthorized action is reported as unavailable with the
///   server's explanation, never as a silent success.
class WebsiteSeoOperationsService {
  WebsiteSeoOperationsService({
    WebsiteSeoFunctionInvoker? invoke,
    WebsiteSeoOperationsClock? clock,
  })  : _invoke = invoke ?? _defaultInvoke,
        _clock = clock ?? DateTime.now;

  static const String diagnosticsFunction = 'google-product-diagnostics';
  static const String oauthFunction = 'google-oauth-callback';

  final WebsiteSeoFunctionInvoker _invoke;
  final WebsiteSeoOperationsClock _clock;

  Future<WebsiteSeoConnectionStatus> connectionStatus() async {
    final observedAt = _clock().toUtc();
    try {
      final response = await _invoke(oauthFunction, {'action': 'status'});
      final data = _asMap(response.data);
      if (!_isOk(response.status)) {
        return WebsiteSeoConnectionStatus(
          connected: false,
          observedAt: observedAt,
          error: _errorText(data, 'No se pudo leer el estado de conexión.'),
          blocker: _blockerFor(response.status, data),
        );
      }
      final connection = _asMap(data['connection']);
      return WebsiteSeoConnectionStatus(
        connected: data['connected'] == true,
        observedAt: observedAt,
        accountEmail: _text(connection['account_email']),
        siteUrl: _text(connection['site_url']),
      );
    } catch (error) {
      return WebsiteSeoConnectionStatus(
        connected: false,
        observedAt: observedAt,
        error: _transportMessage(error),
      );
    }
  }

  /// Returns the Google consent URL to open in an external browser.
  ///
  /// The URL is minted by the backend together with a single-use state row;
  /// the client only opens it.
  Future<WebsiteSeoConnectionStart> startConnection() async {
    try {
      final response = await _invoke(oauthFunction, {'action': 'start'});
      final data = _asMap(response.data);
      if (!_isOk(response.status)) {
        return WebsiteSeoConnectionStart(
          message: _errorText(data, 'No se pudo iniciar la autorización.'),
          blocker: _blockerFor(response.status, data),
        );
      }
      final uri = Uri.tryParse(_text(data['authUrl']));
      if (uri == null || !uri.isScheme('https')) {
        return const WebsiteSeoConnectionStart(
          message: 'Google no devolvió una URL de autorización válida.',
        );
      }
      return WebsiteSeoConnectionStart(authUrl: uri);
    } catch (error) {
      return WebsiteSeoConnectionStart(message: _transportMessage(error));
    }
  }

  Future<WebsiteSeoOperationResult> submitSitemap() {
    return _runAction('submit_sitemap');
  }

  Future<WebsiteSeoOperationResult> refreshMerchantFeed() {
    return _runAction('refresh_merchant_feed');
  }

  Future<WebsiteSeoOperationResult> _runAction(String action) async {
    final observedAt = _clock().toUtc();
    try {
      final response = await _invoke(diagnosticsFunction, {'action': action});
      final data = _asMap(response.data);
      if (!_isOk(response.status)) {
        return WebsiteSeoOperationResult.failure(
          observedAt: observedAt,
          message: _errorText(data, 'La acción no está disponible.'),
          blocker: _blockerFor(response.status, data),
        );
      }
      // A 200 with `ok: false` is a real, described failure. Treating it as
      // success is exactly the "invented success" this service must prevent.
      final succeeded = data['ok'] == true;
      return WebsiteSeoOperationResult(
        succeeded: succeeded,
        observedAt: observedAt,
        message: _text(data['error']),
        blocker: succeeded ? null : _blockerFor(200, data),
        details: data,
      );
    } catch (error) {
      return WebsiteSeoOperationResult.failure(
        observedAt: observedAt,
        message: _transportMessage(error),
      );
    }
  }

  static bool _isOk(int status) => status >= 200 && status < 300;

  /// Wording for a failure that never reached the function contract at all.
  ///
  /// A [FunctionException] is translated by [_defaultInvoke] before it gets
  /// here, so anything arriving is a transport/decoding problem. Its raw
  /// `toString()` is not shown: it can embed the whole response body.
  static String _transportMessage(Object error) {
    if (error is FunctionException) {
      // Defensive: a caller-supplied invoker may still surface it untranslated.
      return _errorText(
        _asMap(error.details),
        'Google respondió con el estado ${error.status}.',
      );
    }
    return 'No se pudo contactar el servicio de Google.';
  }

  static WebsiteSeoOperationBlocker? _blockerFor(
    int status,
    Map<String, dynamic> data,
  ) {
    if (status == 401 || status == 403) {
      return WebsiteSeoOperationBlocker.notAuthorized;
    }
    if (data['reconnectRequired'] == true) {
      return WebsiteSeoOperationBlocker.reconnectRequired;
    }
    if (data['connectRequired'] == true || data['configured'] == false) {
      return WebsiteSeoOperationBlocker.notConnected;
    }
    if (data['skipped'] == true) {
      return WebsiteSeoOperationBlocker.notConfigured;
    }
    return null;
  }

  static Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return const {};
  }

  static String _text(Object? raw) => raw?.toString().trim() ?? '';

  static String _errorText(Map<String, dynamic> data, String fallback) {
    final message = _text(data['error']);
    return message.isEmpty ? fallback : message;
  }

  /// Production invoker.
  ///
  /// `functions_client` **throws** [FunctionException] for every non-2xx
  /// response instead of returning it. Without this translation the typed
  /// `notAuthorized` / `notConnected` blockers would be unreachable and a 403
  /// from `requireWebsiteSeoEditor` would reach the operator as a raw
  /// exception string carrying the response body.
  static Future<({int status, Object? data})> _defaultInvoke(
    String function,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        function,
        body: body,
      );
      return (status: response.status, data: response.data);
    } on FunctionException catch (error) {
      return (status: error.status, data: error.details);
    }
  }
}
