/// Los adjuntos del trabajo (fotos y PDF) desde `20260928090000`: cada uno en
/// `job-images/<taller>/<trabajo>/<archivo al azar>`, anotado en la bandeja del
/// equipo antes de subirse. Los anteriores siguen en `vinabike-assets`, con su
/// URL.
const String jobAttachmentsBucket = 'job-images';

/// La extensión con que se guarda [fileName], o null si no es una foto ni un
/// PDF (el bucket no lo acepta). Antes todo adjunto se nombraba `.jpg`,
/// también un PDF, y la ficha lo mostraba como foto rota.
String? jobAttachmentExtension(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return const {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', 'gif', 'pdf'}
          .contains(extension)
      ? '.$extension'
      : null;
}

/// Un adjunto que el taller no guarda (ni foto ni PDF).
class JobAttachmentNotAcceptedException implements Exception {
  const JobAttachmentNotAcceptedException(this.fileName);

  final String fileName;

  @override
  String toString() =>
      'El adjunto $fileName no es una foto ni un PDF. Quítalo para guardar.';
}
