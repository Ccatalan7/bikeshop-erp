import 'dart:async';
import 'package:flutter/foundation.dart';
import 'email_provider.dart';
import 'gmail_provider.dart';
import 'zoho_provider.dart';
import '../services/email_cache_service.dart';

/// Singleton manager for multiple email providers with unified inbox view.
/// Persists across navigation to avoid refetching emails.
class MailAccountManager extends ChangeNotifier {
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
  Email? _selectedEmail;
  EmailProvider? _selectedProvider;
  bool _isLoading = false;
  bool _isInitialized = false;
  String? _error;
  DateTime? _lastFetch;
  Timer? _pollingTimer;
  final EmailCacheService _cache = EmailCacheService();

  /// Filter: null = all, 'gmail' = only gmail, 'zoho' = only zoho
  String? _providerFilter;

  List<EmailProvider> get providers => _providers;
  List<EmailProvider> get connectedProviders =>
      _providers.where((p) => p.isAuthenticated).toList();

  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  String? get error => _error;
  Email? get selectedEmail => _selectedEmail;
  EmailProvider? get selectedProvider => _selectedProvider;
  String? get providerFilter => _providerFilter;
  DateTime? get lastFetch => _lastFetch;

  /// Check if we have cached emails
  bool get hasCachedEmails => _unifiedEmails.isNotEmpty;

  /// Get unified email list (merged from all providers, sorted by date)
  List<Email> get emails {
    if (_providerFilter != null) {
      return _unifiedEmails
          .where((e) => e.providerId == _providerFilter)
          .toList();
    }
    return _unifiedEmails;
  }

  /// Initialize manager and all providers
  Future<void> initialize() async {
    // Initialize SQLite cache
    await _cache.initialize();

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
      await provider.initialize();
    }

    // Skip if already initialized with emails
    if (_isInitialized && _unifiedEmails.isNotEmpty) {
      debugPrint('📧 [MailManager] Already initialized, using memory cache');
      notifyListeners();
      return;
    }

    debugPrint('📧 [MailManager] Initializing...');
    _isInitialized = true;
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
        await refreshInbox();
      }
    }

    notifyListeners();
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
  String getAuthorizationUrl(String providerId,
      {required String redirectUri, String? state}) {
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
    if (!background) {
      _isLoading = true;
      notifyListeners();
    }
    _error = null;

    try {
      final allEmails = <Email>[];

      for (final provider in connectedProviders) {
        try {
          final emails = await provider.getInbox();
          allEmails.addAll(emails);
        } catch (e) {
          debugPrint('Error fetching ${provider.providerId} inbox: $e');
          // Continue with other providers
        }
      }

      // Sort by date (newest first)
      allEmails.sort((a, b) => b.receivedTime.compareTo(a.receivedTime));
      _unifiedEmails = allEmails;
      _lastFetch = DateTime.now();

      // Save to SQLite cache for next app launch
      await _cache.cacheEmails(allEmails);
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

  /// Select an email and load its content
  Future<void> selectEmail(Email email) async {
    final provider = getProvider(email.providerId);
    if (provider == null) return;

    _selectedProvider = provider;
    _selectedEmail = email;
    notifyListeners();

    try {
      _selectedEmail = await provider.getEmailContent(email);

      // Mark as read
      if (!email.isRead) {
        await provider.markAsRead(email.id);
        // Update the email in the list
        final index = _unifiedEmails.indexWhere((e) => e.id == email.id);
        if (index != -1) {
          _unifiedEmails[index] = _unifiedEmails[index].copyWith(isRead: true);
        }
      }
    } catch (e) {
      _error = e.toString();
    }

    notifyListeners();
  }

  /// Clear selected email
  void clearSelection() {
    _selectedEmail = null;
    _selectedProvider = null;
    notifyListeners();
  }

  /// Set provider filter
  void setProviderFilter(String? providerId) {
    _providerFilter = providerId;
    notifyListeners();
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
      _unifiedEmails.removeWhere((e) => e.id == _selectedEmail!.id);
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
      final index = _unifiedEmails.indexWhere((e) => e.id == email.id);
      if (index != -1) {
        _unifiedEmails[index] = _unifiedEmails[index].copyWith(isRead: read);
        notifyListeners();
      }
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
    _selectedEmail = null;
    _selectedProvider = null;
    _isInitialized = false;
    _lastFetch = null;
    _instance = null;
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    debugPrint('📧 [MailManager] Starting auto-refresh polling (60s)');
    _pollingTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      // Only refresh if we have listeners (Active UI)
      if (!hasListeners) return;

      if (connectedProviders.isEmpty) return;
      debugPrint('📧 [MailManager] Polling: Auto-refreshing inbox...');
      await refreshInbox(background: true);
    });
  }
}
