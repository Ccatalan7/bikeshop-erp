/// Zoho Mail folder model
class ZohoFolder {
  final String folderId;
  final String folderName;
  final String folderPath;
  final int messageCount;
  final int unreadCount;

  ZohoFolder({
    required this.folderId,
    required this.folderName,
    required this.folderPath,
    required this.messageCount,
    required this.unreadCount,
  });

  factory ZohoFolder.fromJson(Map<String, dynamic> json) {
    return ZohoFolder(
      folderId: json['folderId'] ?? '',
      folderName: json['folderName'] ?? '',
      folderPath: json['folderPath'] ?? '',
      messageCount: json['messageCount'] ?? 0,
      unreadCount: json['unreadCount'] ?? 0,
    );
  }

  /// Standard folder identifiers
  static const String inbox = 'INBOX';
  static const String sent = 'SENT';
  static const String drafts = 'DRAFTS';
  static const String trash = 'TRASH';
  static const String spam = 'SPAM';
}
