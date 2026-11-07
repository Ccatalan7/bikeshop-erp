import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/vb_segmented.dart';

/// Los dos modos del correo (dueño, 2026-11-07: «un toggle para cambiar el
/// email entre "smart" y normal mode»).
///
/// Inteligente es «Correo que trabaja» (`/mail`): «Para hoy», Esperando y el
/// botón de cada correo. Normal es la bandeja de Gmail y Zoho de siempre
/// (`/mail/bandeja`): carpetas, no leídos y adjuntos.
enum MailMode { smart, normal }

/// El modo que eligió cada persona en este equipo.
///
/// Decide a dónde abre «Correo» del menú y qué cuenta su número: lo de «Para
/// hoy» en el inteligente, los no leídos en el normal (como antes de la
/// 1.0.50). La clave lleva el usuario, así que en un Mac compartido cada uno
/// tiene el suyo. Hasta que se carga vale el inteligente.
class MailModePreference extends ChangeNotifier {
  MailModePreference._();

  static final MailModePreference instance = MailModePreference._();

  static const String _keyPrefix = 'mail_mode_v1';

  SharedPreferences? _preferences;
  Future<void>? _loading;

  /// La clave de una persona.
  @visibleForTesting
  static String keyFor(String? userId) =>
      '$_keyPrefix:${userId == null || userId.isEmpty ? 'sin-sesion' : userId}';

  static String? _currentUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      // Sin Supabase (pruebas, arranque): la clave sin sesión.
      return null;
    }
  }

  MailMode get mode =>
      _preferences?.getString(keyFor(_currentUserId())) == MailMode.normal.name
          ? MailMode.normal
          : MailMode.smart;

  bool get isNormal => mode == MailMode.normal;

  /// Se carga con el cromo, antes de que alguien toque «Correo».
  Future<void> ensureLoaded() {
    return _loading ??= SharedPreferences.getInstance().then(
      (preferences) {
        _preferences = preferences;
        notifyListeners();
      },
      onError: (Object _) {
        // Sin preferencias guardadas se queda en el inteligente; se reintenta
        // en la próxima carga.
        _loading = null;
      },
    );
  }

  /// Guarda el modo antes de navegar: la redirección de `/mail` lo lee al
  /// tiro.
  Future<void> set(MailMode value) async {
    final preferences = _preferences ??= await SharedPreferences.getInstance();
    if (mode == value) return;
    await preferences.setString(keyFor(_currentUserId()), value.name);
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _preferences = null;
    _loading = null;
  }
}

/// La ruta de un modo, con el correo abierto si lo hay para seguir en él.
String mailModeRoute(
  MailMode mode, {
  String? providerId,
  String? messageId,
  String? openRequest,
}) {
  final query = <String, String>{
    if (providerId != null && providerId.isNotEmpty) 'providerId': providerId,
    if (messageId != null && messageId.isNotEmpty) 'messageId': messageId,
    if (openRequest != null && openRequest.isNotEmpty)
      'openRequest': openRequest,
  };
  return Uri(
    path: mode == MailMode.normal ? '/mail/bandeja' : '/mail',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

/// A dónde va `/mail` según el modo. En el normal, «Correo» abre la bandeja
/// y el aviso de un correo nuevo (`providerId` + `messageId`) lo abre ahí.
/// `?mail=<id>` (la historia de un registro) se queda en el inteligente, el
/// único que conoce ese id.
String? mailModeRedirect(Uri location, MailMode mode) {
  if (mode != MailMode.normal) return null;
  final query = location.queryParameters;
  if ((query['mail'] ?? '').isNotEmpty) return null;
  return mailModeRoute(
    MailMode.normal,
    providerId: query['providerId'],
    messageId: query['messageId'],
    openRequest: query['openRequest'],
  );
}

/// Cambia de modo: lo guarda y abre la otra vista en la misma pestaña, con el
/// correo que estaba abierto.
Future<void> switchMailMode(
  BuildContext context,
  MailMode mode, {
  String? providerId,
  String? messageId,
}) async {
  await MailModePreference.instance.set(mode);
  if (!context.mounted) return;
  context.go(mailModeRoute(mode, providerId: providerId, messageId: messageId));
}

/// El selector «Inteligente | Normal», arriba a la izquierda en las dos
/// vistas del correo. Muestra elegida la vista en la que está.
class MailModeSwitch extends StatelessWidget {
  const MailModeSwitch({
    super.key,
    required this.current,
    this.providerId,
    this.messageId,
    this.expand = false,
  });

  /// La vista que lo muestra.
  final MailMode current;

  /// El correo abierto, para seguir en él en la otra vista.
  final String? providerId;
  final String? messageId;

  /// En teléfono ocupa el ancho; en escritorio, lo justo.
  final bool expand;

  static const double width = 210;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: expand ? double.infinity : width,
      child: VbSegmented<MailMode>(
        groupLabel: 'Modo del correo',
        // En escritorio, a la altura de la casilla y del buscador que tiene
        // al lado; en teléfono el control resuelve su altura táctil.
        density: expand ? null : VbDensity.comfortable,
        options: const [
          VbSegmentedOption(value: MailMode.smart, label: 'Inteligente'),
          VbSegmentedOption(value: MailMode.normal, label: 'Normal'),
        ],
        value: current,
        onChanged: (mode) => unawaited(switchMailMode(
          context,
          mode,
          providerId: providerId,
          messageId: messageId,
        )),
      ),
    );
  }
}
