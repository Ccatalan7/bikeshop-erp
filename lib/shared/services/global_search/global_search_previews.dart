import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../../../modules/messaging/services/messaging_attachment_service.dart';
import 'global_search_entry.dart';

/// Las miniaturas de los archivos recibidos, resueltas **cuando se muestran**.
///
/// Un archivo de una conversación es privado: no tiene una URL que se pueda
/// guardar en el índice, hay que pedir una autorización que dura minutos. Y un
/// PDF no tiene miniatura en ninguna parte: su primera página hay que
/// dibujarla, lo que obliga a bajar el archivo entero.
///
/// Por eso esto no vive en el índice sino acá, y se pide fila por fila:
///
/// - **Sólo lo que está a la vista.** La lista muestra cinco por grupo; el
///   resto no cuesta nada mientras nadie lo mire.
/// - **Una sola vez.** El resultado —incluido el fracaso— queda en memoria,
///   así que volver a escribir la misma consulta no vuelve a pedir nada.
/// - **Un PDF grande no se dibuja.** Bajar ocho megas para una miniatura de
///   26 px es cambiar velocidad por adorno, y la velocidad es el producto. Ese
///   archivo muestra su icono, que es inmediato y no miente.
class GlobalSearchPreviews {
  GlobalSearchPreviews({
    Future<String?> Function(String storagePath)? authorize,
    Future<Uint8List?> Function(String url)? download,
  })  : _authorize = authorize ?? _signedUrl,
        _download = download ?? _downloadBytes;

  /// Cómo se pide la autorización de un archivo privado. Se inyecta por la
  /// misma razón que la descarga: una prueba no debería necesitar Supabase.
  final Future<String?> Function(String storagePath) _authorize;

  static Future<String?> _signedUrl(String storagePath) =>
      MessagingAttachmentService().createSignedUrlForPath(storagePath);

  /// Cómo se bajan los bytes. Se inyecta para que una prueba no dependa de la
  /// red ni de un archivo real.
  final Future<Uint8List?> Function(String url) _download;

  static Future<Uint8List?> _downloadBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;
    return response.bodyBytes;
  }

  /// Tope para rasterizar un PDF. Medido en producción el 2026-09-17: los ocho
  /// PDF recibidos promedian 1,3 MB y el mayor pesa 8,7 MB.
  static const int maxPdfBytes = 4 * 1024 * 1024;

  /// Tope del caché. Una consulta muestra decenas de filas, no cientos.
  static const int maxEntries = 80;

  final Map<String, Future<Uint8List?>> _pending =
      <String, Future<Uint8List?>>{};
  final Map<String, Uint8List?> _done = <String, Uint8List?>{};

  /// `true` cuando vale la pena intentar una miniatura para [attachment].
  static bool canPreview(GlobalSearchAttachment attachment) {
    if (attachment.isImage) return true;
    if (!attachment.isPdf) return false;
    final size = attachment.sizeBytes;
    return size != null && size > 0 && size <= maxPdfBytes;
  }

  /// Los bytes de la miniatura, o `null` si no se pudo. Nunca lanza: una
  /// miniatura que falla deja el icono, no rompe la búsqueda.
  Future<Uint8List?> thumbnail(GlobalSearchAttachment attachment) {
    final key = attachment.storagePath;
    if (_done.containsKey(key)) return Future<Uint8List?>.value(_done[key]);
    return _pending[key] ??= _resolve(attachment).then((bytes) {
      _remember(key, bytes);
      _pending.remove(key);
      return bytes;
    });
  }

  void _remember(String key, Uint8List? bytes) {
    if (_done.length >= maxEntries) {
      _done.remove(_done.keys.first);
    }
    _done[key] = bytes;
  }

  Future<Uint8List?> _resolve(GlobalSearchAttachment attachment) async {
    if (!canPreview(attachment)) return null;
    try {
      final url = await _authorize(attachment.storagePath);
      if (url == null || url.isEmpty) return null;
      // `await`, no `return` pelado: sin esperar acá, un fallo de red se
      // escapa del try y rompe la promesa de que esto nunca lanza —además de
      // no quedar recordado, así que cada repintado lo reintentaba.
      if (attachment.isImage) return await _download(url);

      final pdf = await _download(url);
      if (pdf == null || pdf.isEmpty) return null;
      // La primera página a 48 dpi: una hoja carta queda en ~400 px de ancho,
      // de sobra para 26 y barata de dibujar.
      final page = await Printing.raster(
        pdf,
        pages: const <int>[0],
        dpi: 48,
      ).first;
      return await page.toPng();
    } catch (error) {
      debugPrint('[global-search] sin miniatura para '
          '${attachment.fileName}: $error');
      return null;
    }
  }

  /// Se descarta al cambiar de usuario o de tenant: las autorizaciones y los
  /// archivos son de esa sesión.
  void clear() {
    _pending.clear();
    _done.clear();
  }
}
