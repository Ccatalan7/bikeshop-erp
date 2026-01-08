import 'package:flutter/foundation.dart';

/// Unified email model for all providers
class Email {
  final String id;
  final String providerId; // 'zoho', 'gmail'
  final String folderId;
  final String subject;
  final String fromAddress;
  final String toAddress;
  final String? ccAddress;
  final DateTime receivedTime;
  final DateTime? sentTime;
  final bool isRead;
  final bool hasAttachment;
  final String? summary;
  final String? content;
  final String? threadId; // Gmail specific

  Email({
    required this.id,
    required this.providerId,
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
    this.threadId,
  });

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

  Email copyWith({
    String? id,
    String? providerId,
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
    String? threadId,
  }) {
    return Email(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
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
      threadId: threadId ?? this.threadId,
    );
  }
}

/// Abstract interface for email providers
abstract class EmailProvider with ChangeNotifier {
  /// Unique identifier for this provider type
  String get providerId;

  /// Display name (e.g., "Zoho Mail", "Gmail")
  String get displayName;

  /// Icon for this provider
  String get iconAsset;

  /// The connected email address (null if not authenticated)
  String? get accountEmail;

  /// Whether the user is authenticated with this provider
  bool get isAuthenticated;

  /// Whether an operation is in progress
  bool get isLoading;

  /// Current error message (null if no error)
  String? get error;

  /// List of emails in the current folder
  List<Email> get emails;

  /// Currently selected email with full content
  Email? get selectedEmail;

  /// Initialize the provider (load tokens from storage)
  Future<void> initialize();

  /// Get the OAuth authorization URL
  String getAuthorizationUrl({required String redirectUri});

  /// Exchange auth code for tokens
  Future<bool> exchangeCodeForTokens({
    required String code,
    required String redirectUri,
  });

  /// Disconnect and clear tokens
  Future<void> disconnect();

  /// Refresh the access token
  Future<String?> refreshAccessToken();

  /// Get valid access token (refresh if needed)
  Future<String?> getValidAccessToken();

  /// Fetch inbox emails
  Future<List<Email>> getInbox({int limit = 30, int start = 0});

  /// Get full email content
  Future<Email> getEmailContent(Email email);

  /// Send a new email
  Future<bool> sendEmail({
    required String to,
    required String subject,
    required String content,
    String? cc,
    String? bcc,
  });

  /// Reply to an email
  Future<bool> replyToEmail({
    required String emailId,
    required String content,
    bool replyAll = false,
  });

  /// Move email to trash
  Future<bool> moveToTrash(String emailId);

  /// Mark email as read/unread
  Future<bool> markAsRead(String emailId, {bool read = true});

  /// Clear error state
  void clearError();

  /// Clear selected email
  void clearSelectedEmail();
}
