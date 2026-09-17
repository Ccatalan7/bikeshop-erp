// Web implementation using package:web
// This file is only used on web platform

import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

import 'file_download_result.dart';

/// El navegador decide dónde cae el archivo y no se lo dice a la página: por eso
/// acá nunca hay ruta que devolver, y tampoco hay panel de guardado que abrir
/// ([promptForLocation] se acepta para que la firma sea una sola, y se ignora).
Future<FileDownloadResult> downloadFile({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
  bool promptForLocation = false,
}) async {
  final uint8List = Uint8List.fromList(bytes);
  final blob = web.Blob(
    [uint8List.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );

  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.download = fileName;
  anchor.click();

  web.URL.revokeObjectURL(url);
  return const FileDownloadResult.handedToBrowser();
}
