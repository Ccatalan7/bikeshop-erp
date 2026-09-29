// Menú «Compartir» del sistema para archivos del ERP.
// Nativo en Android, iOS y macOS; en web no se ofrece.

export 'file_share_types.dart';
export 'file_share_io.dart' if (dart.library.js_interop) 'file_share_web.dart';
