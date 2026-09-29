import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Un archivo del ERP listo para entregarlo al menú «Compartir» del sistema.
@immutable
class ShareableFile {
  const ShareableFile({
    required this.bytes,
    required this.fileName,
    this.mimeType,
  });

  final Uint8List bytes;
  final String fileName;
  final String? mimeType;
}

/// Qué pasó con el menú Compartir. Cerrarlo no es un error: se informa como
/// decisión del operador, igual que cerrar el panel de guardado.
enum FileShareOutcome { shared, dismissed, unavailable }

/// Rectángulo del control que abrió el menú. En Mac y iPad el menú sale
/// anclado a él; sin rectángulo AppKit lo pone en una esquina.
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Fija si hay menú Compartir, sólo para pruebas. El gate corre en Linux, que no
/// tiene menú del sistema: una prueba que dependa del sistema anfitrión pasa en
/// el Mac y falla en CI (le pasó al visor de adjuntos, 2026-09-29). La leen
/// `file_share_io.dart` y `file_share_web.dart`; el código de la app no la toca.
bool? debugCanShareFilesOverride;
