/// Email message model for Zoho Mail API
class ZohoEmail {
  final String messageId;
  final String folderId;
  final String subject;
  final String fromAddress;
  final String toAddress;
  final String? ccAddress;
  final DateTime receivedTime;
  final DateTime? sentTime;
  final bool isRead;
  final bool hasAttachment;
  final String? summary; // Preview text
  final String? content; // Full HTML content (loaded on demand)

  ZohoEmail({
    required this.messageId,
    required this.folderId,
    required this.subject,
    required this.fromAddress,
    required this.toAddress,
    this.ccAddress,
    required this.receivedTime,
    this.sentTime,
    required this.isRead,
    required this.hasAttachment,
    this.summary,
    this.content,
  });

  /// Parse from Zoho API response
  factory ZohoEmail.fromJson(Map<String, dynamic> json) {
    return ZohoEmail(
      messageId: json['messageId']?.toString() ?? '',
      folderId: json['folderId']?.toString() ?? '',
      subject: json['subject'] ?? '(Sin asunto)',
      fromAddress: json['fromAddress'] ?? json['sender'] ?? '',
      toAddress: json['toAddress'] ?? '',
      ccAddress: json['ccAddress'],
      receivedTime: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(json['receivedTime']?.toString() ?? '0') ?? 0,
      ),
      sentTime: json['sentDateInGMT'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(json['sentDateInGMT']?.toString() ?? '0') ?? 0)
          : null,
      isRead: json['status'] == 'READ' || json['flagid']?.toString() != '1',
      hasAttachment: json['hasAttachment'] == true ||
          json['hasAttachment'] == 1 ||
          json['hasAttachment'] == '1',
      summary: json['summary'],
      content: json['content'],
    );
  }

  /// Create a copy with updated fields
  ZohoEmail copyWith({
    String? messageId,
    String? folderId,
    String? subject,
    String? fromAddress,
    String? toAddress,
    String? ccAddress,
    DateTime? receivedTime,
    DateTime? sentTime,
    bool? isRead,
    bool? hasAttachment,
    String? summary,
    String? content,
  }) {
    return ZohoEmail(
      messageId: messageId ?? this.messageId,
      folderId: folderId ?? this.folderId,
      subject: subject ?? this.subject,
      fromAddress: fromAddress ?? this.fromAddress,
      toAddress: toAddress ?? this.toAddress,
      ccAddress: ccAddress ?? this.ccAddress,
      receivedTime: receivedTime ?? this.receivedTime,
      sentTime: sentTime ?? this.sentTime,
      isRead: isRead ?? this.isRead,
      hasAttachment: hasAttachment ?? this.hasAttachment,
      summary: summary ?? this.summary,
      content: content ?? this.content,
    );
  }

  /// Get sender display name (extract from "Name <email>" format)
  String get senderName {
    final match = RegExp(r'^"?([^"<]+)"?\s*<').firstMatch(fromAddress);
    if (match != null) {
      return match.group(1)?.trim() ?? fromAddress;
    }
    return fromAddress.split('@').first;
  }

  /// Get sender email only
  String get senderEmail {
    final match = RegExp(r'<(.+@.+)>').firstMatch(fromAddress);
    if (match != null) {
      return match.group(1) ?? fromAddress;
    }
    return fromAddress;
  }
}
