import '../models/message.dart';

Map<String, dynamic> _mapValue(dynamic value) {
  if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
  if (value is Map) return Map<String, dynamic>.from(value);
  return {};
}

String? _metadataText(Map<String, dynamic> metadata, String key) {
  final value = metadata[key]?.toString().trim();
  if (value == null || value.isEmpty || value == 'null') return null;
  return value;
}

bool _hasWhatsAppProvider(Map<String, dynamic> metadata) {
  final provider = (_metadataText(metadata, 'external_provider') ??
          _metadataText(metadata, 'provider') ??
          _metadataText(metadata, 'channel'))
      ?.toLowerCase();
  final externalMessageId = _metadataText(metadata, 'external_message_id');

  return provider == 'whatsapp' ||
      (externalMessageId != null && externalMessageId.startsWith('wamid.'));
}

bool _isUnsupportedWhatsAppCompanion({
  required String type,
  required String content,
  required Map<String, dynamic> metadata,
}) {
  if (type != 'text') return false;
  if (content.trim().toLowerCase() != 'unsupported') return false;
  if (!_hasWhatsAppProvider(metadata)) return false;

  final messageType = _metadataText(metadata, 'message_type')?.toLowerCase();
  final rawPayload = _mapValue(metadata['raw_payload']);
  final rawMessage = _mapValue(rawPayload['message']);
  final rawType = rawMessage['type']?.toString().trim().toLowerCase();

  return messageType == 'unsupported' || rawType == 'unsupported';
}

bool isUnsupportedWhatsAppCompanionMessage(Message message) {
  return _isUnsupportedWhatsAppCompanion(
    type: message.type,
    content: message.content,
    metadata: message.metadata,
  );
}

bool isUnsupportedWhatsAppCompanionRow(Map<String, dynamic> row) {
  final metadata = _mapValue(row['metadata']);
  final externalProvider = row['external_provider'];
  if (externalProvider != null) {
    metadata['external_provider'] = externalProvider;
  }
  final externalMessageId = row['external_message_id'];
  if (externalMessageId != null) {
    metadata['external_message_id'] = externalMessageId;
  }

  return _isUnsupportedWhatsAppCompanion(
    type: row['type']?.toString() ?? 'text',
    content: row['content']?.toString() ?? '',
    metadata: metadata,
  );
}
