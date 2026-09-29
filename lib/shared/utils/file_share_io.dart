import 'dart:io';
import 'dart:ui';

import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'file_share_types.dart';

/// Android, iPhone/iPad y Mac tienen un menú Compartir del sistema al que el
/// ERP le entrega el archivo, como cualquier app. Windows se queda con
/// «Descargar»: su panel de compartir no es lo que un operador espera ahí.
bool get canShareFiles =>
    Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

/// Entrega [files] al menú Compartir del sistema.
///
/// Los bytes se escriben en `tmp/vinabike_share/`, que se vacía al empezar
/// cada envío: cuando alguien comparte otra cosa, el envío anterior ya
/// terminó. Así la caché no crece con cada archivo compartido.
Future<FileShareOutcome> shareFiles({
  required List<ShareableFile> files,
  Rect? origin,
  String? subject,
}) async {
  if (!canShareFiles || files.isEmpty) return FileShareOutcome.unavailable;

  final staging = Directory(
    '${(await getTemporaryDirectory()).path}/vinabike_share',
  );
  if (await staging.exists()) {
    await staging.delete(recursive: true);
  }

  final shared = <XFile>[];
  for (var index = 0; index < files.length; index++) {
    final file = files[index];
    // Una carpeta por archivo: dos adjuntos con el mismo nombre no se pisan y
    // el nombre que ve quien recibe es el original, sin prefijos.
    final directory = Directory('${staging.path}/$index');
    await directory.create(recursive: true);
    final name = _safeFileName(file.fileName);
    final path = '${directory.path}/$name';
    await File(path).writeAsBytes(file.bytes, flush: true);
    shared.add(
      XFile(
        path,
        name: name,
        mimeType:
            file.mimeType ?? lookupMimeType(name) ?? 'application/octet-stream',
      ),
    );
  }

  final result = await SharePlus.instance.share(
    ShareParams(
      files: shared,
      subject: subject,
      sharePositionOrigin: origin,
    ),
  );
  return switch (result.status) {
    ShareResultStatus.success => FileShareOutcome.shared,
    ShareResultStatus.dismissed => FileShareOutcome.dismissed,
    ShareResultStatus.unavailable => FileShareOutcome.unavailable,
  };
}

String _safeFileName(String value) {
  final cleaned = value
      .trim()
      .split(RegExp(r'[\\/]'))
      .last
      .replaceAll(RegExp(r'[\x00-\x1F:*?"<>|]'), '_')
      .trim();
  return cleaned.isEmpty || cleaned.startsWith('.')
      ? 'archivo$cleaned'
      : cleaned;
}
