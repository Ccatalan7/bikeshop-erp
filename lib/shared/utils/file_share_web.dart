import 'dart:ui';

import 'file_share_types.dart';

/// En el navegador el ERP descarga; el menú Compartir es del sistema del
/// teléfono o del Mac, no de la página.
bool get canShareFiles => false;

Future<FileShareOutcome> shareFiles({
  required List<ShareableFile> files,
  Rect? origin,
  String? subject,
}) async =>
    FileShareOutcome.unavailable;
