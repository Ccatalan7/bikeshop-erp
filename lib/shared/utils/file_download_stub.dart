// Stub implementation for non-web platforms
// This file is used when dart:html is not available

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'android_public_downloads.dart';
import 'file_download_result.dart';

/// Guarda [bytes] donde el dueño del equipo pueda encontrarlo y **dice dónde
/// quedó**.
///
/// Decir dónde quedó no es un detalle: esto devolvía `void`, y la cadena de
/// respaldo terminaba escribiendo dentro del contenedor sandbox de la app,
/// donde nadie entra. El botón decía «descargado», el archivo existía, y en
/// `~/Descargas` no había nada — durante diez días. Quien avisa tiene que poder
/// decir **dónde**; si no puede, no debería afirmar que descargó.
///
/// En macOS la carpeta Descargas del usuario requiere
/// `com.apple.security.files.downloads.read-write` en los entitlements; sin ese
/// permiso el sandbox rechaza la escritura y sólo queda el contenedor.
///
/// Con [promptForLocation] en escritorio se abre el panel de guardado del
/// sistema, con Descargas ya seleccionada: guardar donde uno quiere es lo que
/// hace un escritorio, y la carpeta por defecto evita cobrarle una decisión a
/// quien sólo quería el archivo. En teléfono no hay panel que abrir y se
/// ignora.
///
/// En Android el archivo va a «Descargas», la carpeta pública que abre
/// «Archivos» (`AndroidPublicDownloads`). `getDownloadsDirectory()` devuelve ahí
/// una carpeta propia de la app que «Archivos» no muestra: el aviso decía la
/// ruta y nadie podía llegar a ella (2026-11-13). Si la carpeta pública no está
/// —antes de Android 10, o si el sistema la niega— queda la carpeta de la app,
/// como antes, y el aviso sigue diciendo dónde.
Future<FileDownloadResult> downloadFile({
  required List<int> bytes,
  required String fileName,
  required String mimeType,
  bool promptForLocation = false,
}) async {
  final safeName = _safeFileName(fileName);
  final downloadsDirectory = await getDownloadsDirectory();

  if (promptForLocation && _isDesktop) {
    final chosen = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar archivo',
      fileName: safeName,
      initialDirectory: downloadsDirectory?.path,
    );
    // Cerrar el panel es una decisión, no un error: se informa como tal y no se
    // guarda nada a escondidas «por si acaso».
    if (chosen == null) return const FileDownloadResult.cancelled();
    final file = File(chosen);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return FileDownloadResult.saved(file.path);
  }

  if (Platform.isAndroid) {
    final published = await _saveToAndroidDownloads(bytes, safeName, mimeType);
    if (published != null) return FileDownloadResult.saved(published);
  }

  final documentsDirectory = await getApplicationDocumentsDirectory();
  final candidates = <Directory>[
    if (downloadsDirectory != null) downloadsDirectory,
    Directory('${documentsDirectory.path}/Downloads'),
    documentsDirectory,
  ];

  Object? lastError;
  StackTrace? lastStackTrace;

  for (final directory in candidates) {
    try {
      await directory.create(recursive: true);
      final file = File('${directory.path}/$safeName');
      await file.writeAsBytes(bytes, flush: true);
      return FileDownloadResult.saved(file.path);
    } catch (error, stackTrace) {
      lastError = error;
      lastStackTrace = stackTrace;
    }
  }

  Error.throwWithStackTrace(
    FileSystemException(
      'No se pudo guardar la descarga localmente',
      safeName,
      lastError is OSError ? lastError : null,
    ),
    lastStackTrace ?? StackTrace.current,
  );
}

bool get _isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// La ruta en «Descargas» del teléfono, o `null` si hay que quedarse con la
/// carpeta de la app. Un fallo aquí nunca le quita la descarga al operador: la
/// cadena de respaldo de [downloadFile] sigue después.
Future<String?> _saveToAndroidDownloads(
  List<int> bytes,
  String fileName,
  String mimeType,
) async {
  try {
    return await const AndroidPublicDownloads().save(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
  } on MissingPluginException catch (error) {
    debugPrint('Descargas públicas no disponibles: $error');
  } on PlatformException catch (error) {
    debugPrint('Descargas públicas: ${error.code} ${error.message}');
  } on FileSystemException catch (error) {
    debugPrint('Descargas públicas: no se pudo preparar el archivo: $error');
  }
  return null;
}

String _safeFileName(String value) {
  final cleaned = value
      .trim()
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_')
      .replaceAll(RegExp(r'_+'), '_');
  return cleaned.isEmpty ? 'descarga' : cleaned;
}
