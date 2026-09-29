import 'dart:typed_data';

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
