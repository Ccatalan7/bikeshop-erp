import 'package:flutter/foundation.dart';

/// Qué pasó con una descarga, dicho de manera que el aviso no pueda mentir.
///
/// Un `bool` no alcanza y un `String?` tampoco: **cancelar no es fallar**, y
/// «el navegador se lo llevó» no es «quedó en esta ruta». Los tres casos se
/// anuncian distinto, y quien avisa necesita poder distinguirlos.
@immutable
class FileDownloadResult {
  const FileDownloadResult._(this.path, this.cancelled);

  /// Quedó en [path], una ruta que el operador puede abrir.
  const FileDownloadResult.saved(String path) : this._(path, false);

  /// El navegador se encargó y no dice dónde lo dejó.
  const FileDownloadResult.handedToBrowser() : this._(null, false);

  /// El operador cerró el panel de guardado. No hay archivo y **no hay error**:
  /// anunciarlo como fallo culpa al usuario de una decisión suya.
  const FileDownloadResult.cancelled() : this._(null, true);

  final String? path;
  final bool cancelled;

  bool get didSave => !cancelled;
}
