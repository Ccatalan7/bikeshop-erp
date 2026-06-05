import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'email_provider.dart';
import 'gmail_provider.dart';
import 'zoho_provider.dart';
import '../services/email_cache_service.dart';

/// Singleton manager for multiple email providers with unified inbox view.
/// Persists across navigation to avoid refetching emails.
class MailAccountManager extends ChangeNotifier {
  static const int inboxPageSize = 50;
  static const int _searchWarmPageLimit = 5;
  static const int _searchWarmTargetResults = 25;
  static const Duration _startupStepTimeout = Duration(seconds: 8);

  // Singleton pattern
  static MailAccountManager? _instance;
  static MailAccountManager get instance {
    _instance ??= MailAccountManager._internal();
    return _instance!;
  }

  MailAccountManager._internal();

  // For testing or reset purposes
  factory MailAccountManager() => instance;

  final List<EmailProvider> _providers = [];
  List<Email> _unifiedEmails = [];
  List<Email> _searchResults = [];
  Email? _selectedEmail;
  EmailProvider? _selectedProvider;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isSearching = false;
  bool _isLoadingSelectedEmail = false;
  bool _isInitialized = false;
  String? _error;
  String? _selectedEmailError;
  String _searchQuery = '';
  int _searchRequestId = 0;
  int _selectionRequestId = 0;
  DateTime? _lastFetch;
  Timer? _pollingTimer;
  Timer? _refreshDebounceTimer;
  final EmailCacheService _cache = EmailCacheService();
  final StreamController<Email> _newEmailController =
      StreamController<Email>.broadcast();

  // Push notification subscription
  RealtimeChannel? _pushChannel;
  bool _isPushEnabled = false;
  Future<void>? _initializingFuture;

  /// Filter: null = all, 'gmail' = only gmail, 'zoho' = only zoho
  String? _providerFilter;

  List<EmailProvider> get providers => _providers;
  List<EmailProvider> get connectedProviders =>
      _providers.where((p) => p.isAuthenticated).toList();

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSearching => _isSearching;
  bool get isSearchActive => _searchQuery.isNotEmpty;
  bool get isLoadingSelectedEmail => _isLoadingSelectedEmail;
  bool get isInitialized => _isInitialized;
  String? get error => _error;
  String? get selectedEmailError => _selectedEmailError;
  Email? get selectedEmail => _selectedEmail;
  EmailProvider? get selectedProvider => _selectedProvider;
  String? get providerFilter => _providerFilter;
  DateTime? get lastFetch => _lastFetch;
  int get unreadCount => _unifiedEmails.where((email) => !email.isRead).length;
  int get loadedCount => emails.length;
  bool get canLoadMore {
    final providersToCheck = _providersForActiveFilter();
    return providersToCheck.any((provider) => provider.canLoadMore);
  }

  Stream<Email> get newEmailStream => _newEmailController.stream;

  /// Check if we have cached emails
  bool get hasCachedEmails => _unifiedEmails.isNotEmpty;

  /// Get unified email list (merged from all providers, sorted by date)
  List<Email> get emails {
    final source = isSearchActive ? _searchResults : _unifiedEmails;
    if (_providerFilter != null) {
      return source.where((e) => e.providerId == _providerFilter).toList();
    }
    return source;
  }

  /// Initialize manager and all providers
  Future<void> initialize() {
    _initializingFuture ??= _initializeInternal().whenComplete(() {
      _initializingFuture = null;
    });
    return _initializingFuture!;
  }

  Future<void> _initializeInternal() async {
    if (_isInitialized) {
      debugPrint('📧 [MailManager] Already initialized');
      return;
    }

    debugPrint('📧 [MailManager] Initializing...');

    // Initialize SQLite cache when supported. Cache failures must never block
    // the mail module from drawing its connect/inbox UI.
    await _runStartupStep(
      label: 'cache',
      action: _cache.initialize,
      timeout: const Duration(seconds: 3),
    );

    // Ensure providers are registered
    if (_providers.isEmpty) {
      _providers.add(ZohoProvider());
      _providers.add(GmailProvider());

      // Add listeners only on first registration
      for (final provider in _providers) {
        provider.addListener(_onProviderChange);
      }
    }

    // Always initialize providers to load tokens from storage
    for (final provider in _providers) {
      await _runStartupStep(
        label: '${provider.providerId} provider',
        action: provider.initialize,
      );
    }
    _isInitialized = true;
    notifyListeners();

    // Set up push notifications (instant updates)
    await _runStartupStep(
      label: 'push subscription',
      action: _setupPushSubscription,
    );

    // Keep polling as fallback (5 min instead of 3 min when push is enabled)
    _startPolling();

    // INSTANT LOAD: Load from SQLite cache first (no network wait)
    if (connectedProviders.isNotEmpty) {
      final cached = await _cache.getCachedEmails();
      if (cached.isNotEmpty) {
        _unifiedEmails = cached;
        _lastFetch = DateTime.now();
        debugPrint(
            '📧 [MailManager] Loaded ${cached.length} emails from cache');
        notifyListeners();

        // Then refresh in background
        refreshInbox(background: true);
      } else {
        // No cache, load normally (with loading indicator)
        await _runStartupStep(
          label: 'initial inbox refresh',
          action: refreshInbox,
          timeout: const Duration(seconds: 12),
        );
      }
    }

    notifyListeners();
  }

  Future<void> _runStartupStep({
    required String label,
    required Future<void> Function() action,
    Duration timeout = _startupStepTimeout,
  }) async {
    try {
      await action().timeout(timeout);
    } catch (e) {
      debugPrint('📧 [MailManager] Startup step "$label" skipped: $e');
      _error ??= 'No se pudo completar "$label".';
    }
  }

  void _onProviderChange() {
    notifyListeners();
  }

  /// Get a specific provider by ID
  EmailProvider? getProvider(String providerId) {
    try {
      return _providers.firstWhere((p) => p.providerId == providerId);
    } catch (e) {
      return null;
    }
  }

  /// Start OAuth flow for a provider
  Future<String> getAuthorizationUrl(
    String providerId, {
    required String redirectUri,
    String? state,
  }) {
    final provider = getProvider(providerId);
    if (provider == null) throw Exception('Provider not found: $providerId');
    return provider.getAuthorizationUrl(redirectUri: redirectUri, state: state);
  }

  /// Complete OAuth for a provider
  Future<bool> exchangeCodeForTokens(
    String providerId, {
    required String code,
    required String redirectUri,
  }) async {
    final provider = getProvider(providerId);
    if (provider == null) return false;

    final success = await provider.exchangeCodeForTokens(
      code: code,
      redirectUri: redirectUri,
    );

    if (success) {
      await refreshInbox();
    }

    return success;
  }

  /// Disconnect a provider
  Future<void> disconnectProvider(String providerId) async {
    final provider = getProvider(providerId);
    if (provider == null) return;

    await provider.disconnect();
    _unifiedEmails.removeWhere((e) => e.providerId == providerId);
    notifyListeners();
  }

  /// Refresh inbox from all connected providers
  /// If background is true, don't show loading state (for background refresh)
  Future<void> refreshInbox({bool background = false}) async {
    final previousKeys = _unifiedEmails.map(_emailKey).toSet();
    final shouldNotifyNewMail = background && previousKeys.isNotEmpty;

    if (!background) {
      _isLoading = true;
      notifyListeners();
    }
    _error = null;

    try {
      final allEmails = <Email>[];
      final failedProviders = <EmailProvider>[];

      for (final provider in connectedProviders) {
        try {
          final knownEmails = _unifiedEmails
              .where((email) => email.providerId == provider.providerId)
              .toList(growable: false);
          final emails = await provider.getInbox(
            limit: inboxPageSize,
            start: 0,
            knownEmails: knownEmails,
          );
          allEmails.addAll(_mergeProviderEmails(provider.providerId, emails));
        } catch (e) {
          debugPrint('Error fetching ${provider.providerId} inbox: $e');
          failedProviders.add(provider);
          allEmails.addAll(
            _unifiedEmails
                .where((email) => email.providerId == provider.providerId),
          );
        }
      }

      if (allEmails.isEmpty && _unifiedEmails.isNotEmpty) {
        allEmails.addAll(_unifiedEmails);
      }

      _unifiedEmails = _dedupeAndSort(allEmails);
      _lastFetch = DateTime.now();

      if (shouldNotifyNewMail) {
        _emitNewEmailNotifications(_unifiedEmails, previousKeys);
      }

      if (failedProviders.isNotEmpty) {
        _error = _providerFailureMessage(
          failedProviders,
          singleAction: 'No se pudo actualizar',
          multiAction: 'No se pudieron actualizar algunas cuentas',
          suffix: 'Mostrando correos guardados.',
        );
      }

      // Save to SQLite cache for next app launch
      await _cache.cacheEmails(_unifiedEmails);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh in background (for when returning to mail page)
  Future<void> backgroundRefresh() async {
    // Only refresh if last fetch was more than 30 seconds ago
    if (_lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inSeconds < 30) {
      debugPrint('📧 [MailManager] Skipping refresh, last fetch was recent');
      return;
    }
    await refreshInbox(background: true);
  }

  /// Load the next page from the active provider filter, or all providers.
  Future<void> loadMore() async {
    if (_isLoadingMore || connectedProviders.isEmpty) return;

    final providersToLoad = _providersForActiveFilter()
        .where((provider) => provider.canLoadMore)
        .toList(growable: false);

    if (providersToLoad.isEmpty) return;

    _isLoadingMore = true;
    _error = null;
    notifyListeners();

    try {
      final fetched = <Email>[];

      for (final provider in providersToLoad) {
        final source = isSearchActive ? _searchResults : _unifiedEmails;
        final knownEmails = source
            .where((email) => email.providerId == provider.providerId)
            .toList(growable: false);
        final page = await provider.getInbox(
          limit: inboxPageSize,
          start: knownEmails.length,
          searchQuery: isSearchActive ? _searchQuery : null,
          knownEmails: knownEmails,
        );
        fetched.addAll(page);
      }

      if (fetched.isNotEmpty) {
        if (isSearchActive) {
          _searchResults = _dedupeAndSort([..._searchResults, ...fetched]);
        } else {
          _unifiedEmails = _dedupeAndSort([..._unifiedEmails, ...fetched]);
          await _cache.cacheEmails(_unifiedEmails);
        }
      }
    } catch (e) {
      debugPrint('Error loading more mail: $e');
      _error = 'No se pudieron cargar más correos.';
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> searchInbox(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      clearSearch();
      return;
    }

    final requestId = ++_searchRequestId;
    _searchQuery = normalizedQuery;
    _isSearching = true;
    _error = null;
    notifyListeners();

    try {
      final results = <Email>[];
      final failedProviders = <EmailProvider>[];

      for (final provider in _providersForActiveFilter()) {
        try {
          final providerResults = <Email>[];
          for (var pageIndex = 0;
              pageIndex < _searchWarmPageLimit;
              pageIndex++) {
            final emails = await provider.getInbox(
              limit: inboxPageSize,
              start: providerResults.length,
              searchQuery: normalizedQuery,
              knownEmails: providerResults,
            );
            providerResults.addAll(emails);
            if (!provider.canLoadMore ||
                providerResults.length >= _searchWarmTargetResults) {
              break;
            }
          }
          results.addAll(providerResults);
        } catch (e) {
          debugPrint('Error searching ${provider.providerId} inbox: $e');
          failedProviders.add(provider);
        }
      }

      if (requestId != _searchRequestId) return;

      _searchResults = _dedupeAndSort(results);

      if (failedProviders.isNotEmpty) {
        _error = _providerFailureMessage(
          failedProviders,
          singleAction: 'No se pudo buscar en',
          multiAction: 'No se pudo buscar en algunas cuentas',
        );
      }
    } catch (e) {
      if (requestId != _searchRequestId) return;
      _error = 'No se pudo buscar correos.';
    } finally {
      if (requestId == _searchRequestId) {
        _isSearching = false;
        notifyListeners();
      }
    }
  }

  void clearSearch() {
    if (_searchQuery.isEmpty && _searchResults.isEmpty && !_isSearching) {
      return;
    }
    _searchRequestId++;
    _searchQuery = '';
    _searchResults = [];
    _isSearching = false;
    notifyListeners();
  }

  List<EmailProvider> _providersForActiveFilter() {
    if (_providerFilter == null) return connectedProviders;
    return connectedProviders
        .where((provider) => provider.providerId == _providerFilter)
        .toList(growable: false);
  }

  List<Email> _mergeProviderEmails(String providerId, List<Email> fetched) {
    final existing = _unifiedEmails.where(
      (email) => email.providerId == providerId,
    );
    return _dedupeAndSort([...existing, ...fetched]);
  }

  List<Email> _dedupeAndSort(Iterable<Email> emails) {
    final byKey = <String, Email>{};
    for (final email in emails) {
      final key = _emailKey(email);
      final existing = byKey[key];
      byKey[key] = existing == null ? email : _mergeEmail(existing, email);
    }

    final sorted = byKey.values.toList()
      ..sort((a, b) => b.receivedTime.compareTo(a.receivedTime));
    return sorted;
  }

  Email _mergeEmail(Email existing, Email incoming) {
    return incoming.copyWith(
      content: incoming.content ?? existing.content,
      hasAttachment: incoming.hasAttachment || existing.hasAttachment,
      attachments: incoming.attachments.isNotEmpty
          ? incoming.attachments
          : existing.attachments,
    );
  }

  String _emailKey(Email email) => '${email.providerId}:${email.id}';

  String _providerFailureMessage(
    List<EmailProvider> providers, {
    required String singleAction,
    required String multiAction,
    String? suffix,
  }) {
    String withSuffix(String value) {
      final trimmedSuffix = suffix?.trim();
      if (trimmedSuffix == null || trimmedSuffix.isEmpty) return value;
      return '$value $trimmedSuffix';
    }

    String providerDetail(EmailProvider provider) {
      final detail = provider.error?.trim();
      if (detail == null || detail.isEmpty) return provider.displayName;
      return '${provider.displayName}: $detail';
    }

    if (providers.length == 1) {
      final provider = providers.first;
      final detail = provider.error?.trim();
      if (detail == null || detail.isEmpty) {
        return withSuffix('$singleAction ${provider.displayName}.');
      }
      return withSuffix('$singleAction ${provider.displayName}: $detail');
    }

    final details = providers.map(providerDetail).join(' · ');
    return withSuffix('$multiAction. $details');
  }

  /// Select an email and load its content
  Future<void> selectEmail(Email email) async {
    final provider = getProvider(email.providerId);
    if (provider == null) return;

    final requestId = ++_selectionRequestId;
    final shouldMarkReadOnOpen = !email.isRead;
    final visibleEmail =
        shouldMarkReadOnOpen ? email.copyWith(isRead: true) : email;
    String? cachedContent;

    _selectedProvider = provider;
    _selectedEmail = visibleEmail;
    _selectedEmailError = null;
    _isLoadingSelectedEmail = email.content == null;
    if (shouldMarkReadOnOpen) {
      _applyReadStatusLocally(email, true);
      unawaited(_cache.updateReadStatus(email.id, true));
      unawaited(_syncReadStatusForOpenedEmail(provider, email, requestId));
    }
    notifyListeners();

    try {
      cachedContent = await _cache.getCachedContent(email.id);
      if (!_isCurrentSelection(requestId, email.id)) return;

      final hasCachedContent =
          cachedContent != null && cachedContent.trim().isNotEmpty;
      final isPlainGmailFallback = hasCachedContent &&
          provider is GmailProvider &&
          _isPlainTextFallback(cachedContent);

      if (hasCachedContent) {
        _selectedEmail = visibleEmail.copyWith(content: cachedContent);
        _isLoadingSelectedEmail = isPlainGmailFallback;
        notifyListeners();
      }

      final loadedEmail = await provider.getEmailContent(email);
      if (!_isCurrentSelection(requestId, email.id)) return;

      final loadedVisibleEmail = shouldMarkReadOnOpen
          ? loadedEmail.copyWith(isRead: true)
          : loadedEmail;
      _selectedEmail = loadedVisibleEmail;
      _isLoadingSelectedEmail = false;
      await _mergeLoadedEmailMetadata(loadedVisibleEmail);

      final loadedContent = loadedEmail.content;
      if (loadedContent != null && loadedContent.trim().isNotEmpty) {
        await _cache.cacheContent(loadedEmail.id, loadedContent);
      }

      if (provider is GmailProvider &&
          loadedContent?.contains('cid:') == true) {
        _isLoadingSelectedEmail = true;
        notifyListeners();
        unawaited(_hydrateSelectedGmailInlineImages(
          provider: provider,
          email: loadedVisibleEmail,
          requestId: requestId,
        ));
      }
    } catch (e) {
      if (!_isCurrentSelection(requestId, email.id)) return;
      debugPrint('Error loading email content: $e');
      _isLoadingSelectedEmail = false;
      final fallbackContent = _fallbackContentForEmail(
        email,
        cachedContent: cachedContent,
        currentContent: _selectedEmail?.content,
      );
      if (fallbackContent != null) {
        _selectedEmail = (_selectedEmail ?? email).copyWith(
          content: fallbackContent,
        );
      }

      final hasLoadedBody = _selectedEmail?.content?.trim().isNotEmpty ?? false;
      if (!hasLoadedBody) {
        final detail = provider.error?.trim();
        _selectedEmailError = detail == null || detail.isEmpty
            ? 'No se pudo cargar el contenido del mensaje.'
            : 'No se pudo cargar el contenido del mensaje. $detail';
      }
    }

    notifyListeners();
  }

  Future<void> _hydrateSelectedGmailInlineImages({
    required GmailProvider provider,
    required Email email,
    required int requestId,
  }) async {
    try {
      final hydratedEmail = await provider.hydrateInlineImages(email);
      if (!_isCurrentSelection(requestId, email.id)) return;

      _selectedEmail = hydratedEmail;
      _isLoadingSelectedEmail = false;

      final hydratedContent = hydratedEmail.content;
      if (hydratedContent != null && hydratedContent.trim().isNotEmpty) {
        await _cache.cacheContent(hydratedEmail.id, hydratedContent);
      }
    } catch (e) {
      debugPrint('Error hydrating Gmail inline images: $e');
      if (!_isCurrentSelection(requestId, email.id)) return;
      _isLoadingSelectedEmail = false;
    }

    notifyListeners();
  }

  bool _isCurrentSelection(int requestId, String emailId) {
    return requestId == _selectionRequestId && _selectedEmail?.id == emailId;
  }

  Future<void> _syncReadStatusForOpenedEmail(
    EmailProvider provider,
    Email email,
    int requestId,
  ) async {
    final success = await provider.markAsRead(email.id);
    if (!success) {
      debugPrint(
        '📧 [MailManager] Could not sync read status for ${email.providerId}:${email.id}',
      );
      return;
    }
    if (!_isCurrentSelection(requestId, email.id)) return;
    notifyListeners();
  }

  void _applyReadStatusLocally(Email email, bool read) {
    _replaceEmailReadStatus(_unifiedEmails, email, read);
    _replaceEmailReadStatus(_searchResults, email, read);

    final selected = _selectedEmail;
    if (selected != null &&
        selected.id == email.id &&
        selected.providerId == email.providerId) {
      _selectedEmail = selected.copyWith(isRead: read);
    }
  }

  bool _replaceEmailReadStatus(List<Email> emails, Email email, bool read) {
    final index = emails.indexWhere(
      (candidate) =>
          candidate.id == email.id && candidate.providerId == email.providerId,
    );
    if (index == -1 || emails[index].isRead == read) return false;
    emails[index] = emails[index].copyWith(isRead: read);
    return true;
  }

  Future<void> _mergeLoadedEmailMetadata(Email loadedEmail) async {
    final index = _unifiedEmails.indexWhere(
      (email) =>
          email.id == loadedEmail.id &&
          email.providerId == loadedEmail.providerId,
    );
    if (index == -1) return;

    final existing = _unifiedEmails[index];
    final merged = existing.copyWith(
      hasAttachment: existing.hasAttachment || loadedEmail.hasAttachment,
      attachments: loadedEmail.attachments.isNotEmpty
          ? loadedEmail.attachments
          : existing.attachments,
    );
    _unifiedEmails[index] = merged;
    await _cache.cacheEmails([merged]);
  }

  String? _fallbackContentForEmail(
    Email email, {
    required String? cachedContent,
    required String? currentContent,
  }) {
    final current = currentContent?.trim();
    if (current != null && current.isNotEmpty) return currentContent;

    final cached = cachedContent?.trim();
    if (cached != null && cached.isNotEmpty) return cachedContent;

    final summary = email.summary?.trim();
    if (summary != null && summary.isNotEmpty) {
      return _plainTextToHtml(summary);
    }

    return null;
  }

  String _plainTextToHtml(String text) {
    final escaped = const HtmlEscape().convert(text);
    return '<pre style="margin:0;white-space:pre-wrap;word-wrap:break-word;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;font-size:14px;line-height:1.45">$escaped</pre>';
  }

  bool _isPlainTextFallback(String content) {
    final trimmed = content.trimLeft().toLowerCase();
    if (!trimmed.startsWith('<pre')) return false;
    return !RegExp(r'<(html|body|table|div|style|img)\b', caseSensitive: false)
        .hasMatch(content);
  }

  void _emitNewEmailNotifications(
      List<Email> emails, Set<String> previousKeys) {
    final newUnreadEmails = emails
        .where((email) =>
            !email.isRead && !previousKeys.contains(_emailKey(email)))
        .toList(growable: false);

    if (newUnreadEmails.isEmpty) return;

    newUnreadEmails.sort((a, b) => b.receivedTime.compareTo(a.receivedTime));
    for (final email in newUnreadEmails.take(3)) {
      _newEmailController.add(email);
    }
  }

  /// Clear selected email
  void clearSelection() {
    _selectedEmail = null;
    _selectedProvider = null;
    _selectedEmailError = null;
    _isLoadingSelectedEmail = false;
    _selectionRequestId++;
    notifyListeners();
  }

  /// Set provider filter
  void setProviderFilter(String? providerId) {
    _providerFilter = providerId;
    notifyListeners();
    if (_searchQuery.isNotEmpty) {
      unawaited(searchInbox(_searchQuery));
    }
  }

  /// Send email from a specific provider
  Future<bool> sendEmail(
    String providerId, {
    required String to,
    required String subject,
    required String content,
    String? cc,
    String? bcc,
  }) async {
    final provider = getProvider(providerId);
    if (provider == null) return false;

    return provider.sendEmail(
      to: to,
      subject: subject,
      content: content,
      cc: cc,
      bcc: bcc,
    );
  }

  /// Reply to an email
  Future<bool> replyToEmail({
    required Email originalEmail,
    required String content,
    bool replyAll = false,
  }) async {
    final provider = getProvider(originalEmail.providerId);
    if (provider == null) return false;

    // Build reply subject
    String replySubject = originalEmail.subject;
    if (!replySubject.toLowerCase().startsWith('re:')) {
      replySubject = 'Re: $replySubject';
    }

    // Build reply with quoted content
    // Get recipients first (needed for string interpolation)
    String to = originalEmail.senderEmail;
    String? cc;

    // Build reply with quoted content - Outlook style
    final quotedContent = '''
$content

<br>
<hr style="border:0; border-top:1px solid #e1e1e1;">
<div style="font-family: sans-serif; font-size: 13px; color: #333;">
<b>De:</b> ${originalEmail.senderName} &lt;${originalEmail.senderEmail}&gt;<br>
<b>Enviado:</b> ${_formatDateFull(originalEmail.receivedTime)}<br>
<b>Para:</b> ${originalEmail.toAddress}<br>
<b>Asunto:</b> ${originalEmail.subject}<br>
</div>
<br>
${originalEmail.content ?? originalEmail.summary ?? ''}
''';

    if (replyAll && originalEmail.ccAddress != null) {
      cc = originalEmail.ccAddress;
    }

    return provider.sendEmail(
      to: to,
      subject: replySubject,
      content: quotedContent,
      cc: cc,
    );
  }

  String _formatDateFull(DateTime date) {
    // Format: "Wednesday, January 7, 2026 4:51 PM"
    // Using simple format for now if intl date formatting is complex
    final days = [
      'Lunes',
      'Martes',
      'Miércoles',
      'Jueves',
      'Viernes',
      'Sábado',
      'Domingo'
    ];
    final months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre'
    ];

    final dayName = days[date.weekday - 1];
    final monthName = months[date.month - 1];
    final hour =
        date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour);
    final ampm = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');

    return '$dayName, ${date.day} de $monthName de ${date.year} $hour:$minute $ampm';
  }

  /// Delete/trash selected email
  Future<bool> deleteSelectedEmail() async {
    if (_selectedEmail == null || _selectedProvider == null) return false;

    final success = await _selectedProvider!.moveToTrash(_selectedEmail!.id);
    if (success) {
      _unifiedEmails.removeWhere(
        (e) =>
            e.id == _selectedEmail!.id &&
            e.providerId == _selectedEmail!.providerId,
      );
      _selectedEmail = null;
      _selectedProvider = null;
      notifyListeners();
    }
    return success;
  }

  /// Mark email as read/unread
  Future<bool> markAsRead(Email email, {bool read = true}) async {
    final provider = getProvider(email.providerId);
    if (provider == null) return false;

    final success = await provider.markAsRead(email.id, read: read);
    if (success) {
      _applyReadStatusLocally(email, read);
      await _cache.updateReadStatus(email.id, read);
      notifyListeners();
    }
    return success;
  }

  /// Override dispose but do nothing - singleton should persist.
  /// Use reset() for actual cleanup (logout, etc.)
  @override
  // ignore: must_call_super
  void dispose() {
    debugPrint('📧 [MailManager] dispose called (no-op for singleton)');
  }

  /// Actually reset the manager (for logout, etc.)
  void reset() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    for (final provider in _providers) {
      provider.removeListener(_onProviderChange);
    }
    _providers.clear();
    _unifiedEmails.clear();
    _searchResults.clear();
    _searchQuery = '';
    _isSearching = false;
    _searchRequestId++;
    _selectedEmail = null;
    _selectedProvider = null;
    _isInitialized = false;
    _lastFetch = null;
    _pushChannel?.unsubscribe();
    _pushChannel = null;
    _isPushEnabled = false;
    _newEmailController.close();
    _instance = null;
  }

  /// Set up realtime subscription to listen for push notifications
  Future<void> _setupPushSubscription() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;

    if (userId == null) {
      debugPrint('📧 [MailManager] No user ID, skipping push setup');
      return;
    }

    try {
      // Subscribe to changes on email_push_subscriptions for this user
      _pushChannel?.unsubscribe();
      _pushChannel = supabase
          .channel('email-push-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'email_push_subscriptions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              debugPrint('📧 [MailManager] 🔔 Push notification received!');
              debugPrint('📧 [MailManager] Payload: ${payload.newRecord}');

              // Check if this is a new mail notification
              final newMailNotification =
                  payload.newRecord['new_mail_notification'] as bool? ?? false;

              if (newMailNotification) {
                // Reset flag asynchronously (fire and forget)
                supabase
                    .from('email_push_subscriptions')
                    .update({'new_mail_notification': false})
                    .eq('user_id', userId)
                    .eq('provider', payload.newRecord['provider'])
                    .then((_) {});

                // Debounce refresh to handle bursts (wait 2s before fetching)
                if (_refreshDebounceTimer?.isActive ?? false) {
                  _refreshDebounceTimer!.cancel();
                }
                _refreshDebounceTimer = Timer(const Duration(seconds: 2), () {
                  debugPrint(
                      '📧 [MailManager] Debounce complete. Refreshing inbox...');
                  refreshInbox(background: true);
                });
              }
            },
          )
          .subscribe();

      _isPushEnabled = true;
      debugPrint('📧 [MailManager] ✅ Push notification listener active');

      // Set up push for each connected provider
      for (final provider in connectedProviders) {
        if (provider is GmailProvider) {
          final success = await provider.setupPushNotifications();
          debugPrint(
              '📧 [MailManager] Gmail push setup: ${success ? "✅" : "❌ (will use polling)"}');
        }
        // TODO: Add Zoho push setup when implemented
      }
    } catch (e) {
      debugPrint('📧 [MailManager] Push setup error: $e');
      // Push is optional, polling is the fallback
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    // Use 300s (5 min) polling as fallback when push is enabled
    // If push fails, this ensures we still get emails
    final pollInterval = _isPushEnabled ? 300 : 180;
    debugPrint(
        '📧 [MailManager] Starting fallback polling (${pollInterval}s, push: $_isPushEnabled)');
    _pollingTimer = Timer.periodic(Duration(seconds: pollInterval), (_) async {
      // Only refresh if we have listeners (Active UI)
      if (!hasListeners) return;

      if (connectedProviders.isEmpty) return;
      debugPrint('📧 [MailManager] Polling: Auto-refreshing inbox...');
      await refreshInbox(background: true);
    });
  }
}
