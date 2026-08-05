import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mail_folder.dart';
import 'email_provider.dart';

@visibleForTesting
List<EmailSenderIdentity> parseZohoSenderIdentities(
  Object? payload, {
  required String? accountEmail,
}) {
  final root = _stringKeyedMap(payload);
  final data = _stringKeyedMap(root?['data']);
  final rawDetails = root?['sender_identities'] ?? data?['sender_identities'];
  final byAddress = <String, EmailSenderIdentity>{};

  if (rawDetails is List) {
    for (final rawDetail in rawDetails) {
      final detail = _stringKeyedMap(rawDetail);
      if (detail == null) continue;

      final address = detail['address']?.toString().trim() ?? '';
      if (!_looksLikeEmailAddress(address)) continue;

      final displayName =
          (detail['display_name'] ?? detail['displayName'])?.toString().trim();
      final normalized = address.toLowerCase();
      byAddress.putIfAbsent(
        normalized,
        () => EmailSenderIdentity(
          address: address,
          displayName:
              displayName == null || displayName.isEmpty ? null : displayName,
        ),
      );
    }
  }

  final primaryAddress = accountEmail?.trim() ?? '';
  final primaryKey = primaryAddress.toLowerCase();
  final primaryFromZoho = byAddress.remove(primaryKey);
  final identities = <EmailSenderIdentity>[
    if (_looksLikeEmailAddress(primaryAddress))
      primaryFromZoho ?? EmailSenderIdentity(address: primaryAddress),
    ...byAddress.values,
  ];

  return List<EmailSenderIdentity>.unmodifiable(identities);
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is! Map) return null;
  return value.map(
    (key, mapValue) => MapEntry(key.toString(), mapValue),
  );
}

bool _looksLikeEmailAddress(String value) =>
    RegExp(r'^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$').hasMatch(value);

/// Zoho Mail implementation of EmailProvider
class ZohoProvider extends EmailProvider {
  static const String _providerId = 'zoho';
  static const String _apiBase = 'https://mail.zoho.com/api';

  String? _email;
  String? _accountId;
  String? _inboxFolderId;
  final Map<MailFolder, String> _systemFolderIds = {};
  List<EmailSenderIdentity> _senderIdentities = const <EmailSenderIdentity>[];
  String? _senderIdentityError;

  List<Email> _emails = [];
  Email? _selectedEmail;
  bool _isLoading = false;
  String? _error;
  bool _searchCanLoadMore = false;
  final Map<MailFolder, bool> _folderHasMore = {};

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
  List<EmailSenderIdentity> get senderIdentities => _senderIdentities;

  @override
  EmailSenderIdentity? get defaultSenderIdentity => resolveEmailSenderIdentity(
        _senderIdentities,
        defaultAddress: _email,
      );

  @override
  bool get isAuthenticated => _email != null && _accountId != null;

  @override
  bool get isLoading => _isLoading;

  @override
  String? get error => _senderIdentityError ?? _error;

  @override
  List<Email> get emails => _emails;

  @override
  Email? get selectedEmail => _selectedEmail;

  @override
  bool get canLoadMore => _searchCanLoadMore;

  @override
  bool hasMoreIn(MailFolder folder) => _folderHasMore[folder] ?? false;

  String get _accountUrl => '$_apiBase/accounts/$_accountId';

  @override
  Future<void> initialize() async {
    try {
      await _clearLegacyLocalTokens();
      final response = await _supabase.functions.invoke(
        'zoho-oauth',
        body: {'action': 'status'},
      );

      if (response.status == 200) {
        final data = response.data as Map<String, dynamic>;
        final account = data['account'] as Map<String, dynamic>?;
        if (data['connected'] == true && account != null) {
          _email = account['account_email'] as String?;
          _accountId = account['provider_account_id']?.toString();
          await _loadSenderIdentities(notify: false);
        } else {
          _email = null;
          _accountId = null;
          _senderIdentities = const <EmailSenderIdentity>[];
        }
        debugPrint('🔐 [Zoho] Server connection loaded for $_email');
      }
    } catch (e) {
      debugPrint('🔐 [Zoho] Error loading server connection: $e');
    }
    notifyListeners();
  }

  @override
  Future<String> getAuthorizationUrl({
    required String redirectUri,
    String? state,
  }) async {
    final response = await _supabase.functions.invoke(
      'zoho-oauth',
      body: {
        'action': 'authorization_url',
        'redirect_uri': redirectUri,
        if (state != null) 'state': state,
      },
    );

    if (response.status != 200) {
      throw Exception('Could not create Zoho authorization URL');
    }

    final data = response.data as Map<String, dynamic>;
    final authorizationUrl = data['authorization_url']?.toString();
    if (authorizationUrl == null || authorizationUrl.isEmpty) {
      throw Exception('Zoho authorization URL was empty');
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

      final account = data['account'] as Map<String, dynamic>?;
      _email = account?['account_email'] as String?;
      _accountId = account?['provider_account_id']?.toString();
      await _loadSenderIdentities(notify: false);

      debugPrint('🔐 [Zoho] Extracted accountId: $_accountId, email: $_email');
      debugPrint('🔐 [Zoho] Token exchange successful for $_email');

      return true;
    } catch (e) {
      debugPrint('🔐 [Zoho] Token exchange error: $e');
      _error = _friendlyZohoConnectionError(e);
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
        'zoho-oauth',
        body: {'action': 'disconnect'},
      );
    } catch (e) {
      debugPrint('🔐 [Zoho] Server disconnect error: $e');
    }

    await _clearLegacyLocalTokens();
    _email = null;
    _accountId = null;
    _senderIdentities = const <EmailSenderIdentity>[];
    _senderIdentityError = null;
    _emails = [];
    _selectedEmail = null;

    debugPrint('🔐 [Zoho] Disconnected');
    notifyListeners();
  }

  @override
  Future<String?> refreshAccessToken() async {
    if (!isAuthenticated) return null;

    try {
      debugPrint('🔐 [Zoho] Refreshing server-managed access token...');

      final response = await _supabase.functions.invoke(
        'zoho-oauth',
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
      _accountId = account?['provider_account_id']?.toString() ?? _accountId;
      return 'server-managed';
    } catch (e) {
      debugPrint('🔐 [Zoho] Refresh error: $e');
      return null;
    }
  }

  @override
  Future<String?> getValidAccessToken() async {
    return isAuthenticated ? 'server-managed' : null;
  }

  @override
  Future<void> refreshSenderIdentities() => _loadSenderIdentities(
        notify: true,
        propagateError: true,
      );

  Future<void> _loadSenderIdentities({
    required bool notify,
    bool propagateError = false,
  }) async {
    _senderIdentities = parseZohoSenderIdentities(
      null,
      accountEmail: _email,
    );

    if (isAuthenticated) {
      try {
        final response = await _supabase.functions.invoke(
          'zoho-oauth',
          body: {'action': 'sender_identities'},
        );

        if (response.status != 200) {
          throw Exception(_zohoSenderIdentityErrorMessage(
            response.data,
            status: response.status,
          ));
        }

        _senderIdentities = parseZohoSenderIdentities(
          response.data,
          accountEmail: _email,
        );
        _senderIdentityError = null;
      } catch (error) {
        debugPrint('📤 [Zoho] Could not refresh sender identities: $error');
        _senderIdentityError = _zohoSenderIdentityErrorMessage(error);
        if (propagateError) rethrow;
      }
    }

    if (notify) notifyListeners();
  }

  String _zohoSenderIdentityErrorMessage(Object? error, {int? status}) {
    final raw = error?.toString() ?? '';
    final normalized = raw.toLowerCase();
    if (status == 403 ||
        normalized.contains('organization.groups.read') ||
        normalized.contains('insufficient') ||
        normalized.contains('permisos zoho') ||
        normalized.contains('scope')) {
      return 'Permisos Zoho insuficientes: falta autorizar grupos para usar '
          'remitentes compartidos. Reconecta Zoho.';
    }
    return 'Zoho no pudo verificar los remitentes autorizados. '
        'Se mantuvo solamente la cuenta principal. Detalle: $raw';
  }

  Future<void> _clearLegacyLocalTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('zoho_tokens');
  }

  Future<dynamic> _proxyRequest({
    required String method,
    required String url,
    Map<String, dynamic>? body,
    String? accept,
    String? responseType,
  }) async {
    if (!isAuthenticated) throw Exception('Zoho account is not connected');

    final response = await _supabase.functions.invoke(
      'zoho-oauth',
      body: {
        'proxy_url': url,
        'method': method,
        'body': body,
        if (accept != null) 'accept': accept,
        if (responseType != null) 'response_type': responseType,
      },
    );

    if (response.status != 200 && response.status != 204) {
      throw Exception('Zoho API error: ${response.data}');
    }

    return response.data;
  }

  @override
  Future<List<Email>> getMessages({
    MailFolder folder = MailFolder.inbox,
    int limit = 50,
    int start = 0,
    String? pageToken,
    String? searchQuery,
    List<Email> knownEmails = const [],
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    debugPrint(
      '📬 [Zoho] getMessages(${folder.name}) called, accountId: $_accountId',
    );

    try {
      final folderId = await _resolveSystemFolderId(folder);
      if (folderId == null) {
        throw Exception('${folder.label} folder not found');
      }

      final normalizedSearch = searchQuery?.trim();
      final effectiveSearch =
          normalizedSearch?.isEmpty ?? true ? null : normalizedSearch;
      final page = await _fetchZohoMessagePage(
        folderId: folderId,
        limit: limit,
        start: start,
        searchQuery: effectiveSearch,
      );
      final messages = page.messages;
      if (effectiveSearch != null) {
        _searchCanLoadMore = messages.length >= limit;
      } else {
        _folderHasMore[folder] = messages.length >= limit;
      }

      _emails = messages
          .whereType<Map>()
          .map((m) => _parseZohoMessage(
                Map<String, dynamic>.from(m),
                fallbackFolderId: folderId,
              ))
          .where((email) =>
              effectiveSearch == null ||
              _matchesLocalSearch(email, effectiveSearch))
          .toList();
      return _emails;
    } catch (e) {
      debugPrint('getMessages error: $e');
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Resolves and caches the Zoho folderId of a canonical system folder.
  ///
  /// One folders request fills the whole map, so switching between folders
  /// costs a single extra round trip for the lifetime of the session.
  Future<String?> _resolveSystemFolderId(MailFolder folder) async {
    final cached = _systemFolderIds[folder];
    if (cached != null) return cached;

    final foldersUrl = '$_accountUrl/folders';
    debugPrint('📬 [Zoho] Fetching folders from: $foldersUrl');
    final folderData = await _proxyRequest(method: 'GET', url: foldersUrl);
    final folders = folderData['data'] as List? ?? [];
    for (final raw in folders.whereType<Map>()) {
      final resolved = resolveZohoSystemFolder(
        folderType: raw['folderType']?.toString(),
        folderName: raw['folderName']?.toString(),
      );
      final folderId = raw['folderId']?.toString();
      if (resolved != null && folderId != null && folderId.isNotEmpty) {
        _systemFolderIds.putIfAbsent(resolved, () => folderId);
      }
    }
    _inboxFolderId = _systemFolderIds[MailFolder.inbox] ?? _inboxFolderId;
    debugPrint('📬 [Zoho] Resolved system folders: $_systemFolderIds');
    return _systemFolderIds[folder];
  }

  Future<({List<dynamic> messages, bool usedProviderSearch})>
      _fetchZohoMessagePage({
    required String folderId,
    required int limit,
    required int start,
    String? searchQuery,
  }) async {
    // Note: Zoho uses folderId as query param, not path.
    final listUrl =
        '$_accountUrl/messages/view?folderId=$folderId&limit=$limit&start=$start';

    if (searchQuery == null) {
      debugPrint('📬 [Zoho] Fetching messages from: $listUrl');
      final data = await _proxyRequest(method: 'GET', url: listUrl);
      return (messages: _extractZohoMessages(data), usedProviderSearch: true);
    }

    final encodedSearch = Uri.encodeQueryComponent(searchQuery);
    final searchUrls = [
      '$_accountUrl/messages/search?folderId=$folderId&searchKey=$encodedSearch&limit=$limit&start=$start',
      '$listUrl&searchKey=$encodedSearch',
    ];

    for (final url in searchUrls) {
      try {
        debugPrint('📬 [Zoho] Searching messages from: $url');
        final data = await _proxyRequest(method: 'GET', url: url);
        return (
          messages: _extractZohoMessages(data),
          usedProviderSearch: true,
        );
      } catch (e) {
        debugPrint('📬 [Zoho] Search URL failed, trying fallback: $e');
      }
    }

    debugPrint('📬 [Zoho] Falling back to local filtering for search page.');
    final data = await _proxyRequest(method: 'GET', url: listUrl);
    return (messages: _extractZohoMessages(data), usedProviderSearch: false);
  }

  List<dynamic> _extractZohoMessages(dynamic data) {
    if (data is! Map) return const [];
    final root = data['data'];
    if (root is List) return root;
    if (root is Map) {
      for (final key in ['messages', 'messageList', 'searchResults']) {
        final value = root[key];
        if (value is List) return value;
      }
    }
    return const [];
  }

  bool _matchesLocalSearch(Email email, String query) {
    final loweredQuery = query.toLowerCase();
    final searchable = [
      email.subject,
      email.senderName,
      email.senderEmail,
      email.fromAddress,
      email.toAddress,
      email.summary ?? '',
    ].join(' ').toLowerCase();
    return searchable.contains(loweredQuery);
  }

  Email _parseZohoMessage(
    Map<String, dynamic> json, {
    String? fallbackFolderId,
  }) {
    final messageId = json['messageId']?.toString() ?? '';
    final folderId =
        json['folderId']?.toString() ?? fallbackFolderId ?? _inboxFolderId ?? '';
    final attachments = _extractZohoAttachments(json, messageId: messageId);
    final hasAttachment = attachments.isNotEmpty ||
        _isTruthyAttachmentFlag(json['hasAttachment']) ||
        _isTruthyAttachmentFlag(json['attachment']) ||
        _isTruthyAttachmentFlag(json['isAttachmentAvailable']) ||
        (int.tryParse(json['attachmentCount']?.toString() ?? '0') ?? 0) > 0;

    return Email(
      id: messageId,
      providerId: _providerId,
      folderId: folderId,
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
      hasAttachment: hasAttachment,
      summary: json['summary'],
      attachments: attachments,
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
      final contentAttachments =
          _extractZohoAttachments(emailData, messageId: email.id);
      final attachments = contentAttachments.isNotEmpty
          ? contentAttachments
          : (email.hasAttachment
              ? await _fetchAttachmentInfo(email)
              : const <EmailAttachment>[]);

      _selectedEmail = email.copyWith(
        content: content,
        hasAttachment: email.hasAttachment || attachments.isNotEmpty,
        attachments: attachments,
      );
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

  Future<List<EmailAttachment>> _fetchAttachmentInfo(Email email) async {
    try {
      final url =
          '$_accountUrl/folders/${email.folderId}/messages/${email.id}/attachmentinfo?includeInline=false';
      final data = await _proxyRequest(method: 'GET', url: url);
      final root = data is Map ? data['data'] : null;
      if (root is! Map) return const [];
      return _extractZohoAttachments(
        Map<String, dynamic>.from(root),
        messageId: email.id,
      );
    } catch (e) {
      debugPrint('📬 [Zoho] Could not load attachment info: $e');
      return const [];
    }
  }

  List<EmailAttachment> _extractZohoAttachments(
    Map<String, dynamic> json, {
    required String messageId,
  }) {
    final rawAttachments = <dynamic>[];

    void addFrom(dynamic value) {
      if (value is List) rawAttachments.addAll(value);
    }

    addFrom(json['attachments']);
    addFrom(json['attachmentInfo']);
    addFrom(json['attachmentList']);

    final data = json['data'];
    if (data is Map) {
      addFrom(data['attachments']);
      addFrom(data['attachmentInfo']);
      addFrom(data['attachmentList']);
    }

    final attachments = <EmailAttachment>[];
    for (final raw in rawAttachments.whereType<Map>()) {
      final item = Map<String, dynamic>.from(raw);
      final fileName = (item['attachmentName'] ??
              item['fileName'] ??
              item['name'] ??
              item['filename'] ??
              '')
          .toString()
          .trim();
      final id = (item['attachmentId'] ?? item['id'] ?? '').toString().trim();
      if (fileName.isEmpty && id.isEmpty) continue;

      final size = int.tryParse(
        (item['attachmentSize'] ?? item['size'] ?? item['fileSize'] ?? '')
            .toString(),
      );
      final mimeType = (item['contentType'] ??
              item['mimeType'] ??
              _mimeTypeForFileName(fileName))
          .toString();

      attachments.add(
        EmailAttachment(
          id: id.isEmpty ? '${messageId}_${attachments.length}' : id,
          fileName:
              fileName.isEmpty ? 'adjunto-${attachments.length + 1}' : fileName,
          mimeType: mimeType,
          sizeBytes: size,
          attachmentId: id.isEmpty ? null : id,
          isInline: false,
        ),
      );
    }

    return attachments;
  }

  bool _isTruthyAttachmentFlag(dynamic value) {
    if (value == true) return true;
    if (value is num) return value > 0;
    final normalized = value?.toString().toLowerCase().trim();
    return normalized == '1' ||
        normalized == 'true' ||
        normalized == 'yes' ||
        normalized == 'y';
  }

  String _mimeTypeForFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.txt') || lower.endsWith('.log')) {
      return 'text/plain';
    }
    if (lower.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }

  @override
  Future<Uint8List> downloadAttachment(
    Email email,
    EmailAttachment attachment,
  ) async {
    final attachmentId = attachment.attachmentId;
    if (attachmentId == null || attachmentId.isEmpty) {
      throw Exception('Este adjunto de Zoho no tiene ID descargable.');
    }

    final url =
        '$_accountUrl/folders/${email.folderId}/messages/${email.id}/attachments/$attachmentId';
    final data = await _proxyRequest(
      method: 'GET',
      url: url,
      accept: 'application/octet-stream',
      responseType: 'base64',
    );
    if (data is! Map || data['base64'] == null) {
      throw Exception('Zoho no devolvió el archivo adjunto.');
    }

    return base64Decode(data['base64'].toString());
  }

  @override
  Future<bool> sendEmail({
    required String to,
    required String subject,
    required String content,
    String? fromAddress,
    String? cc,
    String? bcc,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Re-read the account immediately before sending so a removed alias or
      // group permission cannot remain usable from stale UI state.
      await _loadSenderIdentities(notify: false);
      final sender = resolveSenderIdentity(fromAddress);
      if (sender == null) {
        throw StateError('El remitente no está autorizado por Zoho.');
      }

      final url = '$_accountUrl/messages';
      await _proxyRequest(
        method: 'POST',
        url: url,
        body: {
          'fromAddress': sender.address,
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
  Future<bool> restoreFromTrash(String emailId) async =>
      _moveToSystemFolder(emailId, MailFolder.inbox, action: 'restore');

  @override
  Future<bool> markAsSpam(String emailId) async =>
      _moveToSystemFolder(emailId, MailFolder.spam, action: 'markAsSpam');

  @override
  Future<bool> markAsNotSpam(String emailId) async =>
      _moveToSystemFolder(emailId, MailFolder.inbox, action: 'markAsNotSpam');

  /// Zoho no versiona spam como label sino como carpeta: reportar, rescatar y
  /// restaurar son la misma operación de mover hacia una carpeta de sistema
  /// resuelta por id real — nunca por nombre literal, que puede venir
  /// localizado.
  Future<bool> _moveToSystemFolder(
    String emailId,
    MailFolder destination, {
    required String action,
  }) async {
    try {
      final folderId = await _resolveSystemFolderId(destination);
      if (folderId == null) {
        throw Exception('${destination.label} folder not found');
      }
      await _proxyRequest(
        method: 'PUT',
        url: '$_accountUrl/messages/$emailId/move',
        body: {'destfolderId': folderId},
      );
      _emails.removeWhere((e) => e.id == emailId);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('$action error: $e');
      _error = e.toString();
      return false;
    }
  }

  @override
  Future<bool> markAsRead(String emailId, {bool read = true}) async {
    try {
      // Zoho API requires /updatemessage endpoint with messageId array
      final url = '$_accountUrl/updatemessage';
      await _proxyRequest(
        method: 'PUT',
        url: url,
        body: {
          'mode': read ? 'markAsRead' : 'markAsUnread',
          'messageId': [emailId],
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
    _senderIdentityError = null;
    notifyListeners();
  }

  String _friendlyZohoConnectionError(Object error) {
    final raw = error.toString();
    if (raw.contains('status: 400') || raw.contains('Bad Request')) {
      return 'El código de conexión de Zoho ya venció. Inicia la conexión nuevamente.';
    }
    if (raw.contains('status: 401') || raw.contains('Unauthorized')) {
      return 'No se pudo autorizar Zoho. Vuelve a conectar la cuenta.';
    }
    return 'No se pudo conectar Zoho en este momento.';
  }

  @override
  void clearSelectedEmail() {
    _selectedEmail = null;
    notifyListeners();
  }
}
