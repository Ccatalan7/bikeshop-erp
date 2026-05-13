import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'email_provider.dart';

/// Gmail implementation of EmailProvider
class GmailProvider extends EmailProvider {
  static const String _providerId = 'gmail';
  static const String _scopes =
      'https://www.googleapis.com/auth/gmail.readonly '
      'https://www.googleapis.com/auth/gmail.send '
      'https://www.googleapis.com/auth/gmail.modify';

  static const String _apiBase = 'https://www.googleapis.com/gmail/v1/users/me';

  String? _email;

  List<Email> _emails = [];
  Email? _selectedEmail;
  bool _isLoading = false;
  String? _error;
  String? _nextPageToken;
  String? _lastSearchQuery;

  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  String get providerId => _providerId;

  @override
  String get displayName => 'Gmail';

  @override
  String get iconAsset => 'assets/icons/gmail.png';

  @override
  String? get accountEmail => _email;

  @override
  bool get isAuthenticated => _email != null;

  @override
  bool get isLoading => _isLoading;

  @override
  String? get error => _error;

  @override
  List<Email> get emails => _emails;

  @override
  Email? get selectedEmail => _selectedEmail;

  @override
  bool get canLoadMore => _nextPageToken != null;

  @override
  Future<void> initialize() async {
    try {
      await _clearLegacyLocalTokens();
      final response = await _supabase.functions.invoke(
        'gmail-oauth',
        body: {'action': 'status'},
      );

      if (response.status == 200) {
        final data = response.data as Map<String, dynamic>;
        final account = data['account'] as Map<String, dynamic>?;
        _email = data['connected'] == true && account != null
            ? account['account_email'] as String?
            : null;
        debugPrint('🔐 [Gmail] Server connection loaded for $_email');
      }
    } catch (e) {
      debugPrint('🔐 [Gmail] Error loading server connection: $e');
    }
    notifyListeners();
  }

  @override
  Future<String> getAuthorizationUrl({
    required String redirectUri,
    String? state,
  }) async {
    final response = await _supabase.functions.invoke(
      'gmail-oauth',
      body: {
        'action': 'authorization_url',
        'redirect_uri': redirectUri,
        'scope': _scopes,
        if (state != null) 'state': state,
      },
    );

    if (response.status != 200) {
      throw Exception('Could not create Gmail authorization URL');
    }

    final data = response.data as Map<String, dynamic>;
    final authorizationUrl = data['authorization_url']?.toString();
    if (authorizationUrl == null || authorizationUrl.isEmpty) {
      throw Exception('Gmail authorization URL was empty');
    }
    return authorizationUrl;
  }

  @override
  Future<bool> exchangeCodeForTokens({
    required String code,
    required String redirectUri,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      debugPrint('🔐 [Gmail] Exchanging code for tokens...');

      final response = await _supabase.functions.invoke(
        'gmail-oauth',
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
        },
      );

      if (response.status != 200) {
        throw Exception('Token exchange failed: ${response.data}');
      }

      final data = response.data as Map<String, dynamic>;

      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      final account = data['account'] as Map<String, dynamic>?;
      _email = account?['account_email'] as String?;
      debugPrint('🔐 [Gmail] Token exchange successful for $_email');

      return true;
    } catch (e) {
      debugPrint('🔐 [Gmail] Token exchange error: $e');
      _error = _friendlyGmailConnectionError(e);
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  Future<void> disconnect() async {
    try {
      await _supabase.functions.invoke(
        'gmail-oauth',
        body: {'action': 'disconnect'},
      );
    } catch (e) {
      debugPrint('🔐 [Gmail] Server disconnect error: $e');
    }

    await _clearLegacyLocalTokens();
    _email = null;
    _emails = [];
    _selectedEmail = null;

    debugPrint('🔐 [Gmail] Disconnected');
    notifyListeners();
  }

  @override
  Future<String?> refreshAccessToken() async {
    if (!isAuthenticated) return null;

    try {
      debugPrint('🔐 [Gmail] Refreshing server-managed access token...');

      final response = await _supabase.functions.invoke(
        'gmail-oauth',
        body: {
          'action': 'refresh',
        },
      );

      if (response.status != 200) {
        throw Exception('Token refresh failed');
      }

      final data = response.data as Map<String, dynamic>;
      final account = data['account'] as Map<String, dynamic>?;
      _email = account?['account_email'] as String? ?? _email;
      return 'server-managed';
    } catch (e) {
      debugPrint('🔐 [Gmail] Refresh error: $e');
      return null;
    }
  }

  @override
  Future<String?> getValidAccessToken() async {
    return isAuthenticated ? 'server-managed' : null;
  }

  Future<void> _clearLegacyLocalTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('gmail_tokens');
  }

  /// Set up push notifications for new emails via Google Cloud Pub/Sub.
  /// This calls the Gmail API users.watch method to subscribe to inbox changes.
  /// The subscription lasts 7 days and should be renewed before expiry.
  Future<bool> setupPushNotifications() async {
    if (!isAuthenticated || _email == null) {
      debugPrint('📧 [Gmail Push] Not authenticated, skipping push setup');
      return false;
    }

    try {
      debugPrint('📧 [Gmail Push] Setting up push notifications...');

      // The Pub/Sub topic must be created in Google Cloud Console first
      // Format: projects/{project-id}/topics/{topic-name}
      // You need to grant gmail-api-push@system.gserviceaccount.com publish rights
      const topicName = 'projects/vinabikeapp/topics/gmail-push-notifications';

      final response = await _proxyRequest(
        method: 'POST',
        url: '$_apiBase/watch',
        body: {
          'topicName': topicName,
          'labelIds': ['INBOX'],
        },
      );

      final historyId = response['historyId']?.toString();
      final expiration = response['expiration']?.toString();

      debugPrint('📧 [Gmail Push] ✅ Watch set up!');
      debugPrint('📧 [Gmail Push] History ID: $historyId');
      debugPrint('📧 [Gmail Push] Expires: $expiration');

      // Store the subscription info in Supabase for renewal tracking
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        await _supabase.from('email_push_subscriptions').upsert({
          'user_id': userId,
          'tenant_id': await _getTenantId(),
          'provider': 'gmail',
          'email_address': _email, // Added for lookup
          'gmail_history_id': historyId,
          'gmail_expiration': expiration != null
              ? DateTime.fromMillisecondsSinceEpoch(int.parse(expiration))
                  .toIso8601String()
              : null,
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,provider');

        debugPrint('📧 [Gmail Push] Subscription saved to database');
      }

      return true;
    } catch (e) {
      debugPrint('📧 [Gmail Push] ❌ Error setting up push: $e');
      // Don't throw - push is optional, polling is fallback
      return false;
    }
  }

  /// Stop push notifications (e.g., when disconnecting)
  Future<void> stopPushNotifications() async {
    try {
      debugPrint('📧 [Gmail Push] Stopping push notifications...');
      await _proxyRequest(
        method: 'POST',
        url: '$_apiBase/stop',
        body: {},
      );
      debugPrint('📧 [Gmail Push] ✅ Push stopped');
    } catch (e) {
      debugPrint('📧 [Gmail Push] Error stopping push: $e');
    }
  }

  Future<String?> _getTenantId() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final result = await _supabase
        .from('user_profiles')
        .select('tenant_id')
        .eq('user_id', userId)
        .limit(1)
        .maybeSingle();

    return result?['tenant_id'] as String?;
  }

  Future<dynamic> _proxyRequest({
    required String method,
    required String url,
    Map<String, dynamic>? body,
  }) async {
    if (!isAuthenticated) throw Exception('Gmail account is not connected');

    final response = await _supabase.functions.invoke(
      'gmail-oauth',
      body: {
        'proxy_url': url,
        'method': method,
        'body': body,
      },
    );

    if (response.status != 200 && response.status != 204) {
      throw Exception('Gmail API error: ${response.data}');
    }

    return response.data;
  }

  @override
  Future<List<Email>> getInbox({
    int limit = 50,
    int start = 0,
    String? pageToken,
    String? searchQuery,
    List<Email> knownEmails = const [],
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final knownById = {
        for (final email
            in knownEmails.where((e) => e.providerId == _providerId))
          email.id: email,
      };

      final normalizedSearch = searchQuery?.trim();
      final effectiveSearch =
          normalizedSearch?.isEmpty ?? true ? null : normalizedSearch;
      if (start == 0 || effectiveSearch != _lastSearchQuery) {
        _nextPageToken = null;
      }
      _lastSearchQuery = effectiveSearch;

      debugPrint(
        '📧 [Gmail] Fetching inbox (limit: $limit, start: $start, search: ${effectiveSearch ?? "none"}, known: ${knownById.length})...',
      );
      final effectivePageToken =
          pageToken ?? (start > 0 ? _nextPageToken : null);
      final response = await _supabase.functions.invoke(
        'gmail-oauth',
        body: {
          'action': 'list_inbox',
          'limit': limit,
          'start': start,
          if (effectiveSearch != null) 'search_query': effectiveSearch,
          if (effectivePageToken != null && effectivePageToken.isNotEmpty)
            'page_token': effectivePageToken,
          if (knownById.isNotEmpty) 'known_ids': knownById.keys.toList(),
        },
      );

      if (response.status != 200) {
        throw Exception('Gmail API error: ${response.data}');
      }

      final data = response.data as Map<String, dynamic>? ?? {};
      _nextPageToken = data['nextPageToken']?.toString();
      if (_nextPageToken?.isEmpty ?? false) _nextPageToken = null;
      final messages = data['messages'] as List? ?? [];
      _emails = messages.whereType<Map>().map((message) {
        final typedMessage = Map<String, dynamic>.from(message);
        final id = typedMessage['id']?.toString() ?? '';
        if (typedMessage['known'] == true && knownById.containsKey(id)) {
          return knownById[id]!;
        }
        return _parseGmailMessage(typedMessage);
      }).toList();

      return _emails;
    } catch (e) {
      debugPrint('getInbox error: $e');
      _error = _friendlyGmailError(e);
      throw Exception(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Email _parseGmailMessage(Map<String, dynamic> data) {
    final headers = data['payload']?['headers'] as List? ?? [];
    String getHeader(String name) {
      final header = headers.firstWhere(
        (h) => h['name'].toString().toLowerCase() == name.toLowerCase(),
        orElse: () => {'value': ''},
      );
      return header['value'] ?? '';
    }

    final labelIds = data['labelIds'] as List? ?? [];
    final isUnread = labelIds.contains('UNREAD');

    return Email(
      id: data['id'] ?? '',
      providerId: _providerId,
      folderId: 'INBOX',
      subject:
          getHeader('Subject').isEmpty ? '(Sin asunto)' : getHeader('Subject'),
      fromAddress: getHeader('From'),
      toAddress: getHeader('To'),
      receivedTime: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(data['internalDate'] ?? '0') ?? 0,
      ),
      isRead: !isUnread,
      hasAttachment: (data['payload']?['parts'] as List?)?.any(
            (p) => p['filename'] != null && p['filename'].toString().isNotEmpty,
          ) ??
          false,
      summary: data['snippet'],
      threadId: data['threadId'],
    );
  }

  @override
  Future<Email> getEmailContent(Email email) async {
    _isLoading = true;
    notifyListeners();

    try {
      final url = '$_apiBase/messages/${email.id}?format=full';
      final data = await _proxyRequest(method: 'GET', url: url);

      final payload = data['payload'];
      String content = '';

      if (payload != null) {
        // 1. Extract HTML body
        content = _extractBody(payload);

        // Inline CID images are hydrated after first paint by MailAccountManager.
        // Blocking on every image here makes rich emails feel much slower than
        // native mail clients.
      }

      _selectedEmail = email.copyWith(content: content);
      return _selectedEmail!;
    } catch (e) {
      debugPrint('getEmailContent error: $e');
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Email> hydrateInlineImages(Email email) async {
    final content = email.content;
    if (content == null || !content.contains('cid:')) return email;

    final url = '$_apiBase/messages/${email.id}?format=full';
    final data = await _proxyRequest(method: 'GET', url: url);
    final payload = data['payload'];
    if (payload is! Map<String, dynamic>) return email;

    final resolvedContent = await _resolveInlineImages(
      content,
      payload,
      email.id,
    );
    if (resolvedContent == content) return email;

    return email.copyWith(content: resolvedContent);
  }

  Future<String> _resolveInlineImages(
    String htmlContent,
    Map<String, dynamic> payload,
    String messageId,
  ) async {
    final inlineParts = <Map<String, dynamic>>[];
    _collectInlineParts(payload, inlineParts);

    if (inlineParts.isEmpty) return htmlContent;
    debugPrint('📧 [Gmail] Hydrating ${inlineParts.length} inline images...');

    final replacements = await _mapWithConcurrency<Map<String, dynamic>,
        _InlineImageReplacement?>(
      inlineParts,
      6,
      (part) async {
        final headers = part['headers'] as List?;
        final contentIdHeader = headers?.firstWhere(
          (h) => h['name']?.toString().toLowerCase() == 'content-id',
          orElse: () => null,
        );

        if (contentIdHeader == null) return null;

        var contentId = contentIdHeader['value'].toString();
        contentId = contentId.replaceAll('<', '').replaceAll('>', '');

        if (!htmlContent.contains('cid:$contentId')) return null;

        try {
          final body = part['body'];
          String? base64Data;

          if (body['data'] != null) {
            base64Data = body['data'];
          } else if (body['attachmentId'] != null) {
            base64Data = await _fetchAttachment(
              messageId,
              body['attachmentId'],
            );
          }

          if (base64Data == null) return null;

          final normalized =
              base64Data.replaceAll('-', '+').replaceAll('_', '/');
          final mimeType = part['mimeType'] ?? 'image/jpeg';
          return _InlineImageReplacement(
            contentId,
            'data:$mimeType;base64,$normalized',
          );
        } catch (e) {
          debugPrint('Error resolving CID $contentId: $e');
          return null;
        }
      },
    );

    var resolvedContent = htmlContent;
    for (final replacement
        in replacements.whereType<_InlineImageReplacement>()) {
      resolvedContent = resolvedContent.replaceAll(
        'cid:${replacement.contentId}',
        replacement.dataUri,
      );
    }
    return resolvedContent;
  }

  Future<List<R?>> _mapWithConcurrency<T, R>(
    List<T> items,
    int concurrency,
    Future<R?> Function(T item) mapper,
  ) async {
    final results = List<R?>.filled(items.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < items.length) {
        final currentIndex = nextIndex;
        nextIndex += 1;
        results[currentIndex] = await mapper(items[currentIndex]);
      }
    }

    final workerCount = items.length < concurrency ? items.length : concurrency;
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results;
  }

  Future<String?> _fetchAttachment(
      String messageId, String attachmentId) async {
    try {
      final url = '$_apiBase/messages/$messageId/attachments/$attachmentId';
      final data = await _proxyRequest(method: 'GET', url: url);
      return data['data'];
    } catch (e) {
      debugPrint('Error fetching attachment: $e');
      return null;
    }
  }

  void _collectInlineParts(
    Map<String, dynamic> part,
    List<Map<String, dynamic>> collected,
  ) {
    final headers = part['headers'] as List?;
    if (headers != null) {
      final hasContentId = headers.any(
        (h) => h['name']?.toString().toLowerCase() == 'content-id',
      );
      if (hasContentId) collected.add(part);
    }

    if (part['parts'] != null) {
      for (final nestedPart in part['parts']) {
        _collectInlineParts(nestedPart, collected);
      }
    }
  }

  String _extractBody(Map<String, dynamic> payload) {
    final htmlBody = _extractMimeBody(payload, 'text/html');
    if (htmlBody != null && htmlBody.trim().isNotEmpty) return htmlBody;

    final plainBody = _extractMimeBody(payload, 'text/plain');
    if (plainBody != null && plainBody.trim().isNotEmpty) {
      return _plainTextToHtml(plainBody);
    }

    final body = payload['body'];
    if (body is Map && body['data'] is String) {
      final decoded = _decodeBase64Url(body['data'] as String);
      if (_looksLikeHtml(decoded)) return decoded;
      return _plainTextToHtml(decoded);
    }

    return '';
  }

  String? _extractMimeBody(Map<String, dynamic> part, String targetMimeType) {
    if (_isAttachmentPart(part)) return null;

    final mimeType = part['mimeType']?.toString().toLowerCase();
    final body = part['body'];
    if (mimeType == targetMimeType && body is Map && body['data'] is String) {
      return _decodeBase64Url(body['data'] as String);
    }

    final nestedParts = part['parts'];
    if (nestedParts is List) {
      for (final nestedPart in nestedParts) {
        if (nestedPart is Map<String, dynamic>) {
          final nestedBody = _extractMimeBody(nestedPart, targetMimeType);
          if (nestedBody != null && nestedBody.trim().isNotEmpty) {
            return nestedBody;
          }
        }
      }
    }

    return null;
  }

  bool _isAttachmentPart(Map<String, dynamic> part) {
    final filename = part['filename']?.toString().trim();
    if (filename != null && filename.isNotEmpty) return true;

    final headers = part['headers'];
    if (headers is List) {
      return headers.any((header) {
        if (header is! Map) return false;
        final name = header['name']?.toString().toLowerCase();
        final value = header['value']?.toString().toLowerCase() ?? '';
        return name == 'content-disposition' && value.contains('attachment');
      });
    }

    return false;
  }

  String _plainTextToHtml(String text) {
    final escaped = const HtmlEscape().convert(text);
    return '<pre style="margin:0;white-space:pre-wrap;word-wrap:break-word;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;font-size:14px;line-height:1.45">$escaped</pre>';
  }

  bool _looksLikeHtml(String value) {
    return RegExp(r'<(html|body|table|div|p|span|br|style|img)\b',
            caseSensitive: false)
        .hasMatch(value);
  }

  String _decodeBase64Url(String data) {
    try {
      // Gmail uses URL-safe base64
      var normalized = data.replaceAll('-', '+').replaceAll('_', '/');
      final padding = normalized.length % 4;
      if (padding > 0) {
        normalized = normalized.padRight(normalized.length + 4 - padding, '=');
      }
      return utf8.decode(base64.decode(normalized), allowMalformed: true);
    } catch (e) {
      return data;
    }
  }

  @override
  Future<bool> sendEmail({
    required String to,
    required String subject,
    required String content,
    String? cc,
    String? bcc,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Build RFC 2822 message
      final message = StringBuffer();
      message.writeln('To: $to');
      message.writeln('From: $_email');
      if (cc != null && cc.isNotEmpty) message.writeln('Cc: $cc');
      if (bcc != null && bcc.isNotEmpty) message.writeln('Bcc: $bcc');
      message.writeln('Subject: $subject');
      message.writeln('Content-Type: text/html; charset=utf-8');
      message.writeln();
      message.write(content);

      // Base64 URL encode
      final raw =
          base64Url.encode(utf8.encode(message.toString())).replaceAll('=', '');

      await _proxyRequest(
        method: 'POST',
        url: '$_apiBase/messages/send',
        body: {'raw': raw},
      );

      return true;
    } catch (e) {
      debugPrint('sendEmail error: $e');
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  Future<bool> replyToEmail({
    required String emailId,
    required String content,
    bool replyAll = false,
  }) async {
    // TODO: Implement proper reply with threading
    return false;
  }

  @override
  Future<bool> moveToTrash(String emailId) async {
    try {
      await _proxyRequest(
          method: 'POST', url: '$_apiBase/messages/$emailId/trash');
      _emails.removeWhere((e) => e.id == emailId);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('moveToTrash error: $e');
      _error = e.toString();
      return false;
    }
  }

  @override
  Future<bool> markAsRead(String emailId, {bool read = true}) async {
    try {
      await _proxyRequest(
        method: 'POST',
        url: '$_apiBase/messages/$emailId/modify',
        body: {
          if (read) 'removeLabelIds': ['UNREAD'] else 'addLabelIds': ['UNREAD'],
        },
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('markAsRead error: $e');
      return false;
    }
  }

  @override
  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _friendlyGmailError(Object error) {
    final raw = error.toString();
    if (raw.contains('status: 400') ||
        raw.contains('Bad Request') ||
        raw.contains('INVALID_ARGUMENT')) {
      return 'Gmail rechazó la solicitud de actualización. Intenta actualizar nuevamente.';
    }
    if (raw.contains('status: 401') || raw.contains('Unauthorized')) {
      return 'La conexión con Gmail venció. Vuelve a conectar la cuenta.';
    }
    if (raw.contains('status: 403') || raw.contains('insufficient')) {
      return 'Gmail no autorizó esta operación. Revisa los permisos de la cuenta.';
    }
    return 'No se pudo actualizar Gmail en este momento.';
  }

  String _friendlyGmailConnectionError(Object error) {
    final raw = error.toString();
    if (raw.contains('status: 400') || raw.contains('Bad Request')) {
      return 'El código de conexión de Gmail ya venció. Inicia la conexión nuevamente.';
    }
    if (raw.contains('status: 401') || raw.contains('Unauthorized')) {
      return 'No se pudo autorizar Gmail. Vuelve a conectar la cuenta.';
    }
    return 'No se pudo conectar Gmail en este momento.';
  }

  @override
  void clearSelectedEmail() {
    _selectedEmail = null;
    notifyListeners();
  }
}

class _InlineImageReplacement {
  final String contentId;
  final String dataUri;

  const _InlineImageReplacement(this.contentId, this.dataUri);
}
