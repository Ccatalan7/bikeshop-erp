import 'package:http/http.dart' as http;

/// Un envío que no terminó con una respuesta del servidor.
///
/// [notSent] es la única certeza que tiene el equipo: la conexión nunca se
/// abrió (sin red, sin nombre del servidor, conexión rechazada, el apretón de
/// manos TLS no terminó). Entonces el servidor no recibió nada y mandarlo de
/// nuevo es siempre seguro. Si la conexión se abrió y después se cortó, o la
/// respuesta no llegó a tiempo, no se sabe si el servidor lo aplicó.
class TransportFailure implements Exception {
  const TransportFailure({
    required this.uri,
    required this.cause,
    required this.notSent,
    this.timedOut = false,
  });

  final Uri uri;
  final Object cause;
  final bool notSent;
  final bool timedOut;

  /// Lo que recibe quien llamó: el mismo tipo que lanza el cliente de fábrica
  /// (`ClientException`, para quien lo atrapa por tipo), con un texto que la
  /// persona entiende cuando una pantalla lo muestra tal cual (`'Error…: $e'`).
  ///
  /// [kept] dice si el cambio quedó en la bandeja del equipo: entonces el texto
  /// dice dónde está, para que nadie lo dé por perdido ni lo repita a ciegas.
  ErpConnectionException toClientException({bool kept = false}) =>
      ErpConnectionException(
        _sayWhatHappened(kept),
        uri,
        cause: cause,
        notSent: notSent,
        timedOut: timedOut,
        kept: kept,
      );

  String _sayWhatHappened(bool kept) {
    if (kept) {
      return notSent
          ? 'Sin conexión: no se guardó. Quedó en este equipo; revísalo en el '
              'aviso de abajo.'
          : 'La conexión se cortó y no se sabe si se guardó. Quedó en este '
              'equipo: revísalo en el aviso de abajo antes de repetirlo.';
    }
    if (notSent) {
      return 'Sin conexión con el servidor. Revisa internet e intenta de nuevo.';
    }
    if (timedOut) return 'El servidor no respondió a tiempo. Intenta de nuevo.';
    return 'La conexión se cortó. Intenta de nuevo.';
  }

  @override
  String toString() =>
      'TransportFailure(${notSent ? 'no salió' : timedOut ? 'sin respuesta a tiempo' : 'cortada'}: $cause)';
}

/// Manda una petición e informa en qué etapa falló.
abstract class StageAwareSender {
  /// [headerTimeout] es el plazo para que lleguen los encabezados de la
  /// respuesta; [idleTimeout], el máximo silencio mientras llega el cuerpo.
  /// [freshConnection] pide una conexión nueva: una reusada puede estar muerta
  /// y entonces el fallo aparece después de haber salido.
  Future<http.StreamedResponse> send(
    http.BaseRequest request, {
    required Duration headerTimeout,
    required Duration idleTimeout,
    bool freshConnection = false,
  });

  void close();
}

/// El `ClientException` del ERP: se lee como frase, no como traza.
///
/// La causa técnica sigue en [cause] (y en [technical]) para el registro de
/// depuración y la bandeja de cambios sin guardar.
class ErpConnectionException extends http.ClientException {
  ErpConnectionException(
    super.message,
    Uri super.uri, {
    required this.cause,
    required this.notSent,
    this.timedOut = false,
    this.kept = false,
  });

  final Object cause;
  final bool notSent;
  final bool timedOut;

  /// Quedó en la bandeja del equipo.
  final bool kept;

  String get technical =>
      '${notSent ? 'no salió' : timedOut ? 'sin respuesta a tiempo' : 'cortada'}: $cause';

  @override
  String toString() => message;
}
