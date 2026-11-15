import 'package:flutter/material.dart';

import '../../../modules/messaging/services/messaging_attachment_service.dart';
import '../../../modules/messaging/widgets/chat_attachment_viewer.dart';
import '../../services/global_search/global_search_entry.dart';

/// Muestra un archivo que llegó por una conversación con el **mismo visor del
/// chat**, sin montar el módulo de mensajería: lo usan el buscador y la página
/// de una marca («Archivos recibidos»).
///
/// La autorización se pide en el momento y dura minutos: un resultado no
/// puede llevar guardada una URL que abra un archivo privado.
Future<void> showReceivedAttachment(
  BuildContext hostContext,
  GlobalSearchAttachment attachment,
) async {
  String? url;
  try {
    url = await MessagingAttachmentService()
        .createSignedUrlForPath(attachment.storagePath);
  } catch (error) {
    debugPrint('[received-attachment] no se pudo autorizar: $error');
  }
  if (!hostContext.mounted) return;
  if (url == null || url.isEmpty) {
    ScaffoldMessenger.maybeOf(hostContext)?.showSnackBar(
      const SnackBar(content: Text('No se pudo abrir este archivo.')),
    );
    return;
  }
  await ChatAttachmentViewer.show(
    hostContext,
    url: url,
    fileName: attachment.fileName,
    extension: attachment.extension,
    contentType: attachment.contentType,
    isImage: attachment.isImage,
  );
}
