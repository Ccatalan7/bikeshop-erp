import 'package:flutter/material.dart';

import '../services/network/transport_failure.dart';
import '../themes/vinabike_theme_roles.dart';

/// El aviso de un guardado que no terminó, igual en todos los formularios.
///
/// **Por qué existe (2026-11-04).** Cuando la conexión se corta, lo que la
/// persona guardó queda en la bandeja del equipo
/// ([ErpConnectionException.kept]) y muchas veces se envía solo. Pero cada
/// formulario armaba su aviso en rojo con su propio prefijo: «Error guardando
/// cliente: Sin conexión: quedó en este equipo y se envía solo…». Un rojo que
/// dice «error» a algo que está a salvo invita a repetirlo, o a darlo por
/// perdido, que es justo lo que el taller reclamaba.
///
/// - **Quedó en el equipo:** el mensaje del transporte tal cual (dice dónde
///   está y si se envía solo), en el tono de atención y más tiempo en
///   pantalla.
/// - **Falló de verdad:** `«$failed: $error»` en el tono de peligro, como
///   antes. [ErpConnectionException] ya se lee como frase.
void showSaveFailure(
  BuildContext context,
  Object error, {
  required String failed,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final kept = error is ErpConnectionException && error.kept;
  final tone = _toneFor(context, kept: kept);
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        kept ? error.message : '$failed: $error',
        style: TextStyle(color: tone.foreground),
      ),
      backgroundColor: tone.background,
      duration: kept ? const Duration(seconds: 8) : const Duration(seconds: 6),
    ),
  );
}

/// El texto que [showSaveFailure] muestra, para quien lo pone en otro lugar
/// (un aviso dentro del formulario, un diálogo).
String describeSaveFailure(Object error, {required String failed}) =>
    error is ErpConnectionException && error.kept
        ? error.message
        : '$failed: $error';

({Color background, Color foreground}) _toneFor(
  BuildContext context, {
  required bool kept,
}) {
  final roles = Theme.of(context).extension<VinabikeThemeRoles>();
  if (roles == null) {
    final scheme = Theme.of(context).colorScheme;
    return kept
        ? (
            background: scheme.tertiaryContainer,
            foreground: scheme.onTertiaryContainer,
          )
        : (background: scheme.error, foreground: scheme.onError);
  }
  final tone = kept ? roles.warning : roles.danger;
  return kept
      ? (background: tone.container, foreground: tone.onContainer)
      : (background: tone.accent, foreground: tone.onAccent);
}
