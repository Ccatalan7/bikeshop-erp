import '../../../shared/services/route_share_service.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';

/// The last line of a conversation as every surface shows it: the inbox tile
/// and the daily summary say the same words for the same message.
///
/// On 2026-10-14 the inbox said «Claudio: Foto» and the summary «Tú: Imagen
/// enviada» for one photo a colleague sent: the summary called every outbound
/// message «Tú» and printed the media placeholder as text. One owner now.
String conversationPreviewLine(
  Conversation conv,
  ChatProvider chat, {
  String fallback = '',
}) {
  final metadata = conv.lastMessageMetadata;
  final title = metadata['title']?.toString().trim();
  String preview;

  if (metadata['share_kind'] == 'route' || metadata['route'] != null) {
    preview = title == null || title.isEmpty
        ? 'Página compartida del ERP'
        : 'Página compartida: $title';
  } else {
    final content = conv.lastMessageContent?.trim() ?? '';
    final caption = metadata['caption']?.toString().trim() ?? '';
    preview = switch (conv.lastMessageType) {
      // Una foto con texto muestra el texto: es lo que el contacto dijo.
      'image' => caption.isNotEmpty
          ? caption
          : content.isNotEmpty && !_genericMediaTexts.contains(content)
              ? content
              : 'Foto',
      'file' => metadata['filename']?.toString().trim().isNotEmpty == true
          ? 'Archivo: ${metadata['filename']}'
          : 'Archivo adjunto',
      'action_request' =>
        title == null || title.isEmpty ? 'Solicitud interactiva' : title,
      'system' => conv.lastMessageContent?.trim() ?? 'Actualización del chat',
      _ => conv.lastMessageContent?.trim() ?? '',
    };
  }

  preview = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (preview.isEmpty) preview = fallback;
  if (preview.contains('vinabike://app/open') ||
      preview.contains('${RouteShareService.publicHost}'
          '${RouteShareService.publicOpenPath}') ||
      RouteShareService.isShareLink(preview)) {
    preview = 'Página compartida del ERP';
  }
  if (conv.lastMessageIsMine && preview.isNotEmpty) {
    return 'Tú: $preview';
  }
  if (preview.isNotEmpty && conversationLastMessageIsFromBusiness(conv, chat)) {
    final senderId = conv.lastMessageSenderId;
    final name = senderId == null ? null : chat.tenantUserDisplayName(senderId);
    final first = name?.trim().split(RegExp(r'\s+')).first;
    return '${first?.isNotEmpty == true ? first : 'Viñabike'}: $preview';
  }
  return preview;
}

/// La última línea la escribió Viñabike —yo o un compañero—: lleva sus
/// checks y su firma, no se lee como si la hubiera escrito el contacto.
bool conversationLastMessageIsFromBusiness(
  Conversation conv,
  ChatProvider chat,
) {
  if (conv.lastMessageIsMine) return true;
  if (!conv.isSupport || conv.lastMessageType == 'system') return false;
  final direction = conv.lastMessageDirection;
  if (direction == 'outbound') return true;
  if (direction == 'inbound') return false;
  final senderId = conv.lastMessageSenderId;
  return senderId != null && chat.isTenantStaffUser(senderId);
}

const Set<String> _genericMediaTexts = {
  'Imagen enviada',
  'Imagen adjunta',
  'Foto',
};
