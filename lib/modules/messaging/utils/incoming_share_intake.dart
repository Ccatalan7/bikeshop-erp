import '../../../shared/services/incoming_share_service.dart';
import '../services/messaging_attachment_service.dart';

/// Un archivo compartido desde el teléfono y si puede salir por WhatsApp.
class IncomingShareItem {
  const IncomingShareItem({
    required this.file,
    this.validation,
    this.whatsAppProblem,
    this.compression,
  });

  final IncomingSharedFile file;
  final MessagingAttachmentValidation? validation;

  /// Por qué no sale por WhatsApp, dicho con las mismas palabras que usa el
  /// chat al adjuntar. Igual se puede guardar en Archivos.
  final String? whatsAppProblem;

  /// Si no va tal cual pero se puede achicar hasta el tope: foto (en cualquier
  /// equipo) o video (Android). `null` si va tal cual o no tiene arreglo.
  final IncomingShareCompression? compression;

  bool get canSendByWhatsApp => validation != null;
  bool get needsCompression => validation == null && compression != null;
}

enum IncomingShareCompression { image, video }

/// Reglas de la pantalla «Compartir en el ERP», separadas de la vista para
/// probarlas sin un teléfono.
abstract final class IncomingShareIntake {
  /// Misma validación que un adjunto elegido dentro del chat: formato y tope
  /// por tipo. No hay una segunda lista de lo que WhatsApp acepta.
  static List<IncomingShareItem> classify(
    List<IncomingSharedFile> files, {
    bool canCompressVideo = false,
  }) =>
      [
        for (final file in files)
          _classify(file, canCompressVideo: canCompressVideo),
      ];

  static IncomingShareItem _classify(
    IncomingSharedFile file, {
    required bool canCompressVideo,
  }) {
    try {
      return IncomingShareItem(
        file: file,
        validation: MessagingAttachmentService.validateBeforeRead(
          fileName: file.name,
          sizeBytes: file.sizeBytes,
        ),
      );
    } on FormatException catch (error) {
      // Una foto o un video que no va tal cual —por peso, o un video en otro
      // formato (.mov, .webm)— sale re-codificado en JPEG o MP4.
      final compression = file.isImage
          ? IncomingShareCompression.image
          : file.mimeType.startsWith('video/') && canCompressVideo
              ? IncomingShareCompression.video
              : null;
      return IncomingShareItem(
        file: file,
        whatsAppProblem: error.message,
        compression: compression,
      );
    }
  }

  /// El mismo archivo después de comprimirlo, validado de nuevo. Si aun así
  /// no va, no se ofrece comprimirlo otra vez.
  static IncomingShareItem compressed({
    required String path,
    required String name,
    required String mimeType,
    required int sizeBytes,
  }) {
    final item = _classify(
      IncomingSharedFile(
        path: path,
        name: name,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
      ),
      canCompressVideo: false,
    );
    return item.canSendByWhatsApp
        ? item
        : IncomingShareItem(
            file: item.file, whatsAppProblem: item.whatsAppProblem);
  }
}
