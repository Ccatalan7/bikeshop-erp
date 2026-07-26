import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<void> saveAndroidApk({
  required String fileName,
  required List<Uint8List> parts,
}) async {
  final blob = web.Blob(
    [for (final part in parts) part.toJS].toJS,
    web.BlobPropertyBag(
      type: 'application/vnd.android.package-archive',
    ),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = objectUrl
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(
    const Duration(minutes: 1),
    () => web.URL.revokeObjectURL(objectUrl),
  );
}
