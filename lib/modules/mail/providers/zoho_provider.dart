import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'email_provider.dart';

/// Zoho Mail implementation of EmailProvider
class ZohoProvider extends EmailProvider {
  static const String _providerId = 'zoho';
  static const String _tokenKey = 'zoho_tokens';
  static const String _clientId = '1000.23SML89U5VKEOKXT0GW12J0SAPQYRQ';
  static const String _scopes = 'ZohoMail.messages.READ,'
      'ZohoMail.messages.CREATE,'
      'ZohoMail.messages.UPDATE,'
      'ZohoMail.accounts.READ,'
      'ZohoMail.folders.READ';

  static const String _authUrl = 'https://accounts.zoho.com/oauth/v2/auth';
  static const String _apiBase = 'https://mail.zoho.com/api';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;
  String? _email;
  String? _accountId;
  String? _inboxFolderId;

  List<Email> _emails = [];
  Email? _selectedEmail;
  bool _isLoading = false;
  String? _error;

  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  String get providerId => _providerId;

  @override
  String get displayName => 'Zoho Mail';

  @override
  String get iconAsset => 'assets/icons/zoho.png';

  @override
  String? get accountEmail => _email;

  @override
  bool get isAuthenticated => _accessToken != null && _accountId != null;

  @override
  bool get isLoading => _isLoading;

  @override
  String? get error => _error;

  @override
  List<Email> get emails => _emails;

  @override
  Email? get selectedEmail => _selectedEmail;

  String get _accountUrl => '$_apiBase/accounts/$_accountId';

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
        _accountId = data['account_id'];
        if (data['expiry'] != null) {
          _tokenExpiry = DateTime.parse(data['expiry']);
        }
        debugPrint('🔐 [Zoho] Loaded tokens for $_email');
      }
    } catch (e) {
      debugPrint('🔐 [Zoho] Error loading tokens: $e');
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
      'prompt': 'consent',
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
      debugPrint('🔐 [Zoho] Exchanging code for tokens...');

      final response = await _supabase.functions.invoke(
        'zoho-oauth',
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
      debugPrint('🔐 [Zoho] Token response: $data');

      if (data['error'] != null) {
        throw Exception(data['error']);
      }

      _accessToken = data['access_token'];
      _refreshToken = data['refresh_token'];
      _tokenExpiry = DateTime.now().add(
        Duration(seconds: data['expires_in'] ?? 3600),
      );

      // Get account info - Zoho returns accountId directly
      final accountInfo = data['account_info'];
      debugPrint('🔐 [Zoho] Account info: $accountInfo');

      if (accountInfo != null) {
        // Try different possible field names
        _accountId = (accountInfo['accountId'] ??
                accountInfo['account_id'] ??
                accountInfo['ACCOUNT_ID'])
            ?.toString();

        // Email might be in different formats
        final emailAddresses = accountInfo['emailAddress'];
        if (emailAddresses is List && emailAddresses.isNotEmpty) {
          final firstEmail = emailAddresses[0];
          if (firstEmail is Map) {
            _email = firstEmail['mailId'] ?? firstEmail['email'];
          } else if (firstEmail is String) {
            _email = firstEmail;
          }
        } else if (accountInfo['mailId'] != null) {
          _email = accountInfo['mailId'];
        } else if (accountInfo['primaryEmailAddress'] != null) {
          _email = accountInfo['primaryEmailAddress'];
        }
      }

      debugPrint('🔐 [Zoho] Extracted accountId: $_accountId, email: $_email');

      await _saveTokens();
      debugPrint('🔐 [Zoho] Token exchange successful for $_email');

      return true;
    } catch (e) {
      debugPrint('🔐 [Zoho] Token exchange error: $e');
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
    _accountId = null;
    _emails = [];
    _selectedEmail = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);

    debugPrint('🔐 [Zoho] Disconnected');
    notifyListeners();
  }

  @override
  Future<String?> refreshAccessToken() async {
    if (_refreshToken == null) return null;

    try {
      debugPrint('🔐 [Zoho] Refreshing access token...');

      final response = await _supabase.functions.invoke(
        'zoho-oauth',
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
      debugPrint('🔐 [Zoho] Refresh error: $e');
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
        'account_id': _accountId,
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
      'zoho-oauth',
      body: {
        'proxy_url': url,
        'method': method,
        'zoho_token': token,
        'body': body,
      },
    );

    if (response.status != 200 && response.status != 204) {
      throw Exception('Zoho API error: ${response.data}');
    }

    return response.data;
  }

  @override
  Future<List<Email>> getInbox({int limit = 30, int start = 0}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    debugPrint('📬 [Zoho] getInbox called, accountId: $_accountId');

    try {
      // Get inbox folder ID if not cached
      if (_inboxFolderId == null) {
        final foldersUrl = '$_accountUrl/folders';
        debugPrint('📬 [Zoho] Fetching folders from: $foldersUrl');
        final folderData = await _proxyRequest(method: 'GET', url: foldersUrl);
        final folders = folderData['data'] as List? ?? [];
        final inbox = folders.firstWhere(
          (f) => f['folderName'] == 'Inbox' || f['folderName'] == 'INBOX',
          orElse: () => null,
        );
        _inboxFolderId = inbox?['folderId']?.toString();
        debugPrint('📬 [Zoho] Found inbox folderId: $_inboxFolderId');
      }

      if (_inboxFolderId == null) throw Exception('Inbox folder not found');

      // Note: Zoho uses folderId as query param, not path
      final url =
          '$_accountUrl/messages/view?folderId=$_inboxFolderId&limit=$limit&start=$start';
      debugPrint('📬 [Zoho] Fetching messages from: $url');
      final data = await _proxyRequest(method: 'GET', url: url);
      final messages = data['data'] as List? ?? [];

      _emails = messages.map((m) => _parseZohoMessage(m)).toList();
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

  Email _parseZohoMessage(Map<String, dynamic> json) {
    return Email(
      id: json['messageId']?.toString() ?? '',
      providerId: _providerId,
      folderId: json['folderId']?.toString() ?? _inboxFolderId ?? '',
      subject: json['subject'] ?? '(Sin asunto)',
      fromAddress: json['fromAddress'] ?? json['sender'] ?? '',
      toAddress: json['toAddress'] ?? '',
      ccAddress: json['ccAddress'],
      receivedTime: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(json['receivedTime']?.toString() ?? '0') ?? 0,
      ),
      // status: 0=Unread, 1=Read (Zoho API v1 usually)
      // Check for explicit "Unread" indicators, default to true if ambiguous to avoid noise
      isRead: json['status']?.toString() != '0' && json['status'] != 'UNREAD',
      hasAttachment: json['hasAttachment'] == true ||
          json['hasAttachment'] == 1 ||
          json['hasAttachment'] == '1',
      summary: json['summary'],
    );
  }

  @override
  Future<Email> getEmailContent(Email email) async {
    _isLoading = true;
    notifyListeners();

    try {
      final url =
          '$_accountUrl/folders/${email.folderId}/messages/${email.id}/content';
      final data = await _proxyRequest(method: 'GET', url: url);
      final emailData = data['data'] as Map<String, dynamic>? ?? {};
      final content = emailData['content'] as String? ?? email.summary ?? '';

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
      final url = '$_accountUrl/messages';
      await _proxyRequest(
        method: 'POST',
        url: url,
        body: {
          'fromAddress': _email,
          'toAddress': to,
          'subject': subject,
          'content': content,
          if (cc != null && cc.isNotEmpty) 'ccAddress': cc,
          if (bcc != null && bcc.isNotEmpty) 'bccAddress': bcc,
        },
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
    // TODO: Implement
    return false;
  }

  @override
  Future<bool> moveToTrash(String emailId) async {
    try {
      // Move to trash folder
      final url = '$_accountUrl/messages/$emailId/move';
      await _proxyRequest(
        method: 'PUT',
        url: url,
        body: {'destfolderId': 'trash'},
      );
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
      final url = '$_accountUrl/messages/$emailId';
      await _proxyRequest(
        method: 'PUT',
        url: url,
        body: {'mode': read ? 'markAsRead' : 'markAsUnread'},
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
