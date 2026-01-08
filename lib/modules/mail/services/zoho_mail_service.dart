import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/zoho_email.dart';
import '../models/zoho_folder.dart';
import 'zoho_auth_service.dart';

/// Zoho Mail API Service
/// Handles all mail operations: fetch, send, reply, delete
class ZohoMailService with ChangeNotifier {
  static const String _baseUrl = 'https://mail.zoho.com/api/accounts';

  final ZohoAuthService _authService;

  List<ZohoEmail> _emails = [];
  List<ZohoFolder> _folders = [];
  ZohoEmail? _selectedEmail;
  bool _isLoading = false;
  String? _error;

  // Getters
  List<ZohoEmail> get emails => _emails;
  List<ZohoFolder> get folders => _folders;
  ZohoEmail? get selectedEmail => _selectedEmail;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isConnected => _authService.isAuthenticated;

  ZohoMailService(this._authService);

  final SupabaseClient _supabase = Supabase.instance.client;

  /// Proxy request through Supabase Edge Function
  Future<dynamic> _proxyRequest({
    required String method,
    required String url,
    Map<String, dynamic>? body,
  }) async {
    final token = await _authService.getValidAccessToken();
    if (token == null) {
      throw Exception('No valid access token available');
    }

    try {
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
        throw Exception('Proxy error: ${response.data}');
      }

      return response.data;
    } catch (e) {
      debugPrint('Proxy request failed: $e');
      rethrow;
    }
  }

  String get _accountUrl => '$_baseUrl/${_authService.accountId}';

  String? _inboxFolderId;

  /// Fetch inbox messages
  Future<List<ZohoEmail>> getInbox({
    int limit = 30,
    int start = 0,
    String folderId = 'INBOX',
  }) async {
    if (_authService.accountId == null) {
      throw Exception('Account ID not available');
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Resolve 'INBOX' to actual numeric ID if needed
      String actualFolderId = folderId;
      if (folderId == 'INBOX') {
        if (_inboxFolderId == null) {
          // Fetch folders to find Inbox ID
          await getFolders();
          try {
            final inbox = _folders.firstWhere(
              (f) =>
                  f.folderName.toLowerCase() == 'inbox' ||
                  f.folderPath.toLowerCase() == 'inbox' ||
                  f.folderPath == '/',
              orElse: () => _folders.first,
            );
            _inboxFolderId = inbox.folderId;
          } catch (e) {
            // Should not happen if getFolders succeeds and returns list
            debugPrint('Warning: Could not identify Inbox folder');
          }
        }
        actualFolderId = _inboxFolderId ?? folderId;
      }

      final url =
          '$_accountUrl/messages/view?folderId=$actualFolderId&limit=$limit&start=$start';

      final data = await _proxyRequest(method: 'GET', url: url);
      final messageList = data['data'] as List? ?? [];

      _emails = messageList
          .map((m) => ZohoEmail.fromJson(m as Map<String, dynamic>))
          .toList();

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

  /// Get full email content and merge it into the existing email
  Future<ZohoEmail> getEmailContent(ZohoEmail email) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Zoho API requires: /accounts/{accountId}/folders/{folderId}/messages/{messageId}/content
      final url =
          '$_accountUrl/folders/${email.folderId}/messages/${email.messageId}/content';

      final data = await _proxyRequest(method: 'GET', url: url);
      final emailData = data['data'] as Map<String, dynamic>? ?? {};

      // Extract content from response and merge with existing email metadata
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

  /// Send a new email
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

      final body = {
        'fromAddress': 'contacto@vinabike.cl',
        'toAddress': to,
        'subject': subject,
        'content': content,
        'mailFormat': 'html',
      };

      if (cc != null && cc.isNotEmpty) body['ccAddress'] = cc;
      if (bcc != null && bcc.isNotEmpty) body['bccAddress'] = bcc;

      await _proxyRequest(method: 'POST', url: url, body: body);
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

  /// Reply to an email
  Future<bool> replyToEmail({
    required String messageId,
    required String content,
    bool replyAll = false,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final action = replyAll ? 'replyall' : 'reply';
      final url = '$_accountUrl/messages/$messageId/$action';

      await _proxyRequest(method: 'POST', url: url, body: {
        'content': content,
        'mailFormat': 'html',
      });

      return true;
    } catch (e) {
      debugPrint('replyToEmail error: $e');
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Move email to trash
  Future<bool> moveToTrash(String messageId) async {
    try {
      final url = '$_accountUrl/messages/$messageId/moveto?folderId=TRASH';
      await _proxyRequest(method: 'PUT', url: url);

      // Remove from local list
      _emails.removeWhere((e) => e.messageId == messageId);
      notifyListeners();

      return true;
    } catch (e) {
      debugPrint('moveToTrash error: $e');
      _error = e.toString();
      return false;
    }
  }

  /// Mark email as read/unread
  Future<bool> markAsRead(String messageId, {bool read = true}) async {
    try {
      final action = read ? 'markAsRead' : 'markAsUnread';
      final url = '$_accountUrl/messages/$messageId/$action';

      await _proxyRequest(method: 'PUT', url: url);

      // Update local list
      final index = _emails.indexWhere((e) => e.messageId == messageId);
      if (index >= 0) {
        notifyListeners();
      }

      return true;
    } catch (e) {
      debugPrint('markAsRead error: $e');
      return false;
    }
  }

  /// Get mail folders
  Future<List<ZohoFolder>> getFolders() async {
    try {
      final url = '$_accountUrl/folders';

      final data = await _proxyRequest(method: 'GET', url: url);
      final folderList = data['data'] as List? ?? [];

      _folders = folderList
          .map((f) => ZohoFolder.fromJson(f as Map<String, dynamic>))
          .toList();

      return _folders;
    } catch (e) {
      debugPrint('getFolders error: $e');
      _error = e.toString();
      rethrow;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearSelectedEmail() {
    _selectedEmail = null;
    notifyListeners();
  }
}
