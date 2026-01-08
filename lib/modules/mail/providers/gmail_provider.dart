import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'email_provider.dart';

/// Gmail implementation of EmailProvider
class GmailProvider extends EmailProvider {
  static const String _providerId = 'gmail';
  static const String _tokenKey = 'gmail_tokens';
  static const String _scopes =
      'https://www.googleapis.com/auth/gmail.readonly '
      'https://www.googleapis.com/auth/gmail.send '
      'https://www.googleapis.com/auth/gmail.modify';

  // OAuth URLs
  static const String _authUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const String _apiBase = 'https://www.googleapis.com/gmail/v1/users/me';

  // Client ID (safe to embed, secret is server-side only)
  static const String _clientId =
      '599064625399-09i16kv6n8tlp07rb1bug08kgp6d4gmj.apps.googleusercontent.com';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;
  String? _email;

  List<Email> _emails = [];
  Email? _selectedEmail;
  bool _isLoading = false;
  String? _error;

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
  bool get isAuthenticated => _accessToken != null && _email != null;

  @override
  bool get isLoading => _isLoading;

  @override
  String? get error => _error;

  @override
  List<Email> get emails => _emails;

  @override
  Email? get selectedEmail => _selectedEmail;

  @override
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tokenData = prefs.getString(_tokenKey);

      if (tokenData != null) {
        final data = jsonDecode(tokenData);
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];
        _email = data['email'];
        if (data['expiry'] != null) {
          _tokenExpiry = DateTime.parse(data['expiry']);
        }
        debugPrint('🔐 [Gmail] Loaded tokens for $_email');
      }
    } catch (e) {
      debugPrint('🔐 [Gmail] Error loading tokens: $e');
    }
    notifyListeners();
  }

  @override
  String getAuthorizationUrl({required String redirectUri}) {
    final params = {
      'client_id': _clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scopes,
      'access_type': 'offline',
      'prompt': 'consent', // Force consent to get refresh token
    };
    return '$_authUrl?${Uri(queryParameters: params).query}';
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

      _accessToken = data['access_token'];
      _refreshToken = data['refresh_token'];
      _tokenExpiry = DateTime.now().add(
        Duration(seconds: data['expires_in'] ?? 3600),
      );

      // Get email from user_info
      if (data['user_info'] != null) {
        _email = data['user_info']['emailAddress'];
      }

      await _saveTokens();
      debugPrint('🔐 [Gmail] Token exchange successful for $_email');

      return true;
    } catch (e) {
      debugPrint('🔐 [Gmail] Token exchange error: $e');
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  Future<void> disconnect() async {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;
    _email = null;
    _emails = [];
    _selectedEmail = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);

    debugPrint('🔐 [Gmail] Disconnected');
    notifyListeners();
  }

  @override
  Future<String?> refreshAccessToken() async {
    if (_refreshToken == null) return null;

    try {
      debugPrint('🔐 [Gmail] Refreshing access token...');

      final response = await _supabase.functions.invoke(
        'gmail-oauth',
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
        },
      );

      if (response.status != 200) {
        throw Exception('Token refresh failed');
      }

      final data = response.data as Map<String, dynamic>;
      _accessToken = data['access_token'];
      _tokenExpiry = DateTime.now().add(
        Duration(seconds: data['expires_in'] ?? 3600),
      );

      await _saveTokens();
      return _accessToken;
    } catch (e) {
      debugPrint('🔐 [Gmail] Refresh error: $e');
      return null;
    }
  }

  @override
  Future<String?> getValidAccessToken() async {
    if (_accessToken == null) return null;

    if (_tokenExpiry != null &&
        DateTime.now()
            .isAfter(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      return await refreshAccessToken();
    }

    return _accessToken;
  }

  Future<void> _saveTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _tokenKey,
      jsonEncode({
        'access_token': _accessToken,
        'refresh_token': _refreshToken,
        'email': _email,
        'expiry': _tokenExpiry?.toIso8601String(),
      }),
    );
  }

  Future<dynamic> _proxyRequest({
    required String method,
    required String url,
    Map<String, dynamic>? body,
  }) async {
    final token = await getValidAccessToken();
    if (token == null) throw Exception('No valid access token');

    final response = await _supabase.functions.invoke(
      'gmail-oauth',
      body: {
        'proxy_url': url,
        'method': method,
        'gmail_token': token,
        'body': body,
      },
    );

    if (response.status != 200 && response.status != 204) {
      throw Exception('Gmail API error: ${response.data}');
    }

    return response.data;
  }

  @override
  Future<List<Email>> getInbox({int limit = 30, int start = 0}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // List messages
      final listUrl = '$_apiBase/messages?maxResults=$limit&labelIds=INBOX';
      final listData = await _proxyRequest(method: 'GET', url: listUrl);

      final messages = listData['messages'] as List? ?? [];

      // Fetch each message's metadata
      _emails = [];
      for (final msg in messages) {
        try {
          final msgUrl =
              '$_apiBase/messages/${msg['id']}?format=metadata&metadataHeaders=From&metadataHeaders=To&metadataHeaders=Subject&metadataHeaders=Date';
          final msgData = await _proxyRequest(method: 'GET', url: msgUrl);
          _emails.add(_parseGmailMessage(msgData));
        } catch (e) {
          debugPrint('Error fetching message ${msg['id']}: $e');
        }
      }

      return _emails;
    } catch (e) {
      debugPrint('getInbox error: $e');
      _error = e.toString();
      rethrow;
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

      // Extract body content
      String content = '';
      final payload = data['payload'];

      if (payload != null) {
        content = _extractBody(payload);
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

  String _extractBody(Map<String, dynamic> payload) {
    // Check for direct body
    final body = payload['body'];
    if (body != null && body['data'] != null) {
      return _decodeBase64Url(body['data']);
    }

    // Check parts for multipart messages
    final parts = payload['parts'] as List?;
    if (parts != null) {
      // Prefer HTML
      for (final part in parts) {
        if (part['mimeType'] == 'text/html') {
          final partBody = part['body'];
          if (partBody != null && partBody['data'] != null) {
            return _decodeBase64Url(partBody['data']);
          }
        }
      }
      // Fallback to plain text
      for (final part in parts) {
        if (part['mimeType'] == 'text/plain') {
          final partBody = part['body'];
          if (partBody != null && partBody['data'] != null) {
            return '<pre>${_decodeBase64Url(partBody['data'])}</pre>';
          }
        }
      }
      // Recursive check for nested parts
      for (final part in parts) {
        if (part['parts'] != null) {
          final nested = _extractBody(part);
          if (nested.isNotEmpty) return nested;
        }
      }
    }

    return '';
  }

  String _decodeBase64Url(String data) {
    try {
      // Gmail uses URL-safe base64
      final normalized = data.replaceAll('-', '+').replaceAll('_', '/');
      return utf8.decode(base64.decode(normalized));
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

  @override
  void clearSelectedEmail() {
    _selectedEmail = null;
    notifyListeners();
  }
}
