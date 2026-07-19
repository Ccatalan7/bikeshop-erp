import 'package:flutter/foundation.dart';

/// A provider-confirmed address that can be used in the From field.
///
/// This contains presentation metadata only. OAuth credentials remain owned by
/// the server-side provider connection.
@immutable
class EmailSenderIdentity {
  final String address;
  final String? displayName;

  const EmailSenderIdentity({
    required this.address,
    this.displayName,
  });

  String get normalizedAddress => address.trim().toLowerCase();

  String get menuLabel {
    final name = displayName?.trim();
    if (name == null ||
        name.isEmpty ||
        name.toLowerCase() == normalizedAddress) {
      return address;
    }
    return '$name · $address';
  }
}

/// Resolves a requested sender against provider-confirmed identities.
///
/// The canonical address returned by the provider is preserved in the result;
/// callers never pass arbitrary user input through to a mail API.
EmailSenderIdentity? resolveEmailSenderIdentity(
  Iterable<EmailSenderIdentity> identities, {
  String? requestedAddress,
  String? defaultAddress,
}) {
  final available = identities.toList(growable: false);
  if (available.isEmpty) return null;

  final requested = requestedAddress?.trim().toLowerCase();
  if (requested != null && requested.isNotEmpty) {
    for (final identity in available) {
      if (identity.normalizedAddress == requested) return identity;
    }
    return null;
  }

  final preferred = defaultAddress?.trim().toLowerCase();
  if (preferred != null && preferred.isNotEmpty) {
    for (final identity in available) {
      if (identity.normalizedAddress == preferred) return identity;
    }
  }

  return available.first;
}

/// Provider-neutral attachment metadata for an email.
class EmailAttachment {
  final String id;
  final String fileName;
  final String mimeType;
  final int? sizeBytes;
  final String? attachmentId;
  final String? contentId;
  final bool isInline;

  const EmailAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    this.sizeBytes,
    this.attachmentId,
    this.contentId,
    this.isInline = false,
  });

  String get displayName => fileName.trim().isEmpty ? 'archivo' : fileName;

  String get extension {
    final name = displayName;
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  String get displaySize {
    final bytes = sizeBytes;
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  bool get isPdf =>
      extension == 'pdf' || mimeType.toLowerCase().contains('application/pdf');

  bool get isImage =>
      mimeType.toLowerCase().startsWith('image/') ||
      const {'jpg', 'jpeg', 'png', 'gif', 'webp'}.contains(extension);

  bool get isTextLike {
    final lowerMime = mimeType.toLowerCase();
    return lowerMime.startsWith('text/') ||
        const {'txt', 'csv', 'json', 'log', 'xml'}.contains(extension);
  }
}

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
  final List<EmailAttachment> attachments;

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
    this.attachments = const [],
  });

  int get attachmentCount => attachments.length;

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
    List<EmailAttachment>? attachments,
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
      attachments: attachments ?? this.attachments,
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

  /// Provider-confirmed identities available for the From field.
  ///
  /// Providers with one mailbox inherit the connected account as their only
  /// identity. Providers that support aliases or group senders can override
  /// this with the addresses returned by their own API.
  List<EmailSenderIdentity> get senderIdentities {
    final address = accountEmail?.trim();
    if (address == null || address.isEmpty) {
      return const <EmailSenderIdentity>[];
    }
    return <EmailSenderIdentity>[EmailSenderIdentity(address: address)];
  }

  EmailSenderIdentity? get defaultSenderIdentity => resolveEmailSenderIdentity(
        senderIdentities,
        defaultAddress: accountEmail,
      );

  /// Refreshes From identities from the provider when it supports aliases.
  Future<void> refreshSenderIdentities() async {}

  EmailSenderIdentity? resolveSenderIdentity(String? requestedAddress) =>
      resolveEmailSenderIdentity(
        senderIdentities,
        requestedAddress: requestedAddress,
        defaultAddress: accountEmail,
      );

  /// Whether the user is authenticated with this provider
  bool get isAuthenticated;

  /// Whether an operation is in progress
  bool get isLoading;

  /// Current error message (null if no error)
  String? get error;

  /// List of emails in the current folder
  List<Email> get emails;

  /// Whether the provider has another inbox page available.
  bool get canLoadMore => false;

  /// Currently selected email with full content
  Email? get selectedEmail;

  /// Initialize the provider (load tokens from storage)
  Future<void> initialize();

  /// Get the OAuth authorization URL (state is passed for mobile deep link handling)
  Future<String> getAuthorizationUrl({
    required String redirectUri,
    String? state,
  });

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
  Future<List<Email>> getInbox({
    int limit = 50,
    int start = 0,
    String? pageToken,
    String? searchQuery,
    List<Email> knownEmails = const [],
  });

  /// Get full email content
  Future<Email> getEmailContent(Email email);

  /// Download an email attachment into memory for preview or saving.
  Future<Uint8List> downloadAttachment(
    Email email,
    EmailAttachment attachment,
  );

  /// Send a new email
  Future<bool> sendEmail({
    required String to,
    required String subject,
    required String content,
    String? fromAddress,
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
