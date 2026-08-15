import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mail_folder.dart';
import 'email_provider.dart';
import 'gmail_provider.dart';
import 'zoho_provider.dart';
import '../services/email_cache_service.dart';
import '../../../shared/services/mail_notification_gate.dart';

/// Singleton manager for multiple email providers with unified inbox view.
/// Persists across navigation to avoid refetching emails.
class MailAccountManager extends ChangeNotifier {
  static const int inboxPageSize = 50;
  static const int _searchWarmPageLimit = 5;
  static const int _searchWarmTargetResults = 25;
  static const Duration _startupStepTimeout = Duration(seconds: 8);
  static const List<Duration> _transientReadRetryDelays = [
    Duration(milliseconds: 400),
    Duration(milliseconds: 1200),
  ];
  static const String _cacheUserScopePreference = 'mail_cache_user_scope';

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

  /// La bandeja de entrada unificada. Es una lista con nombre propio y no una
  /// entrada más de [_folderEmails] porque cuatro consumidores dependen de que
  /// SIEMPRE sea la bandeja de entrada, sin importar qué carpeta esté mirando
  /// el usuario: el badge del sidebar, el resumen del panel de notificaciones,
  /// el stream de correo nuevo y la caché persistente.
  List<Email> _unifiedEmails = [];

  /// Las demás carpetas canónicas, sólo en memoria: se cargan al entrar y no
  /// participan de push, polling, notificaciones ni caché.
  final Map<MailFolder, List<Email>> _folderEmails = {};
  MailFolder _activeFolder = MailFolder.inbox;
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
  Future<void>? _refreshInboxFuture;
  final Map<String, Future<void>> _readMutationTails = {};
  final Map<String, int> _readMutationVersions = {};
  final Map<String, bool> _confirmedReadStatus = {};
  final Map<String, bool> _pendingReadStatus = {};
  final Map<String, DateTime> _providerReadCooldownUntil = {};
  final Map<String, DateTime> _providerLastSuccessfulInboxFetch = {};
  String? _readStatusFailureKey;
  final EmailCacheService _cache = EmailCacheService();
  final StreamController<Email> _newEmailController =
      StreamController<Email>.broadcast();

  // Push notification subscription
  RealtimeChannel? _pushChannel;
  bool _isPushEnabled = false;
  Future<void>? _initializingFuture;
  String? _initializingUserId;
  int? _initializingEpoch;
  String? _sessionUserId;
  bool _isSessionScopeReady = false;
  int _lifecycleEpoch = 0;
  Future<void>? _sessionTransitionFuture;
  String? _pendingSessionUserId;

  /// Reemplaza solamente la espera de reintentos de lectura en pruebas. La
  /// política y el número de intentos siguen siendo los de producción.
  @visibleForTesting
  Future<void> Function(Duration delay)? debugTransientReadRetryWaitOverride;

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
    if (isSearchActive) {
      return providersToCheck.any((provider) => provider.canLoadMore);
    }
    return providersToCheck.any(
      (provider) => provider.hasMoreIn(_activeFolder),
    );
  }

  MailFolder get activeFolder => _activeFolder;

  Stream<Email> get newEmailStream => _newEmailController.stream;

  /// Check if we have cached emails
  bool get hasCachedEmails => _unifiedEmails.isNotEmpty;

  /// Get unified email list (merged from all providers, sorted by date)
  List<Email> get emails {
    final source = isSearchActive
        ? _searchResults
        : _activeFolder == MailFolder.inbox
            ? _unifiedEmails
            : _folderEmails[_activeFolder] ?? const <Email>[];
    if (_providerFilter != null) {
      return source.where((e) => e.providerId == _providerFilter).toList();
    }
    return source;
  }

  /// Stable cross-provider projection for summaries outside the mail module.
  ///
  /// The inbox owns temporary search/account filters. Operational briefings
  /// must not silently inherit those controls when the user visits Mail.
  List<Email> get briefingEmails => List<Email>.unmodifiable(_unifiedEmails);

  /// Initialize manager and all providers
  Future<void> initialize() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return _initializeForUser(userId);
  }

  Future<void> _initializeForUser(String? userId) async {
    await prepareSession(userId);
    if (userId == null ||
        !_isSessionScopeReady ||
        _sessionUserId != userId ||
        Supabase.instance.client.auth.currentUser?.id != userId) {
      return;
    }
    if (_isInitialized) return;

    final epoch = _lifecycleEpoch;
    final inFlight = _initializingFuture;
    if (inFlight != null &&
        _initializingUserId == userId &&
        _initializingEpoch == epoch) {
      return inFlight;
    }

    final operation = _initializeInternal(
      expectedUserId: userId,
      epoch: epoch,
    );
    _initializingFuture = operation;
    _initializingUserId = userId;
    _initializingEpoch = epoch;
    return operation.whenComplete(() {
      if (identical(_initializingFuture, operation)) {
        _initializingFuture = null;
        _initializingUserId = null;
        _initializingEpoch = null;
      }
    });
  }

  Future<void> prepareSession(String? userId) {
    if (_isSessionScopeReady &&
        _sessionUserId == userId &&
        _sessionTransitionFuture == null) {
      return Future<void>.value();
    }
    final existing = _sessionTransitionFuture;
    if (existing != null && _pendingSessionUserId == userId) return existing;

    late final Future<void> operation;
    operation = () async {
      if (existing != null) await existing;
      if (!_isSessionScopeReady || _sessionUserId != userId) {
        await _resetInternal(nextUserId: userId);
      }
    }();
    _sessionTransitionFuture = operation;
    _pendingSessionUserId = userId;
    return operation.whenComplete(() {
      if (identical(_sessionTransitionFuture, operation)) {
        _sessionTransitionFuture = null;
        _pendingSessionUserId = null;
      }
    });
  }

  Future<void> _initializeInternal({
    required String? expectedUserId,
    required int epoch,
  }) async {
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
    if (!_isCurrentLifecycle(epoch, expectedUserId)) return;

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
      if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
    }
    _isInitialized = true;
    notifyListeners();

    // Set up push notifications (instant updates)
    await _runStartupStep(
      label: 'push subscription',
      action: () => _setupPushSubscription(
        epoch: epoch,
        expectedUserId: expectedUserId,
      ),
    );
    if (!_isCurrentLifecycle(epoch, expectedUserId)) return;

    // Keep polling as fallback (5 min instead of 3 min when push is enabled)
    _startPolling(epoch: epoch, expectedUserId: expectedUserId);

    // INSTANT LOAD: Load from SQLite cache first (no network wait)
    if (connectedProviders.isNotEmpty) {
      final cached = await _cache.getCachedEmails();
      if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
      if (cached.isNotEmpty) {
        _unifiedEmails = cached;
        debugPrint(
            '📧 [MailManager] Loaded ${cached.length} emails from cache');
        notifyListeners();

        // Then refresh in background
        unawaited(refreshInbox(background: true));
      } else {
        // No cache, load normally (with loading indicator)
        await _runStartupStep(
          label: 'initial inbox refresh',
          action: refreshInbox,
          timeout: const Duration(seconds: 12),
        );
        if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
      }
    }

    if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
    notifyListeners();
  }

  /// Resolutor de identidad Auth, sustituible sólo en pruebas: el guard de
  /// ciclo de vida debe seguir ejerciéndose (época y usuario) sin exigir un
  /// Supabase real en un test unitario.
  @visibleForTesting
  String? Function()? debugAuthUserIdOverride;

  String? get _currentAuthUserId => debugAuthUserIdOverride != null
      ? debugAuthUserIdOverride!()
      : Supabase.instance.client.auth.currentUser?.id;

  bool _isCurrentLifecycle(int epoch, String? expectedUserId) {
    return _isSessionScopeReady &&
        expectedUserId != null &&
        epoch == _lifecycleEpoch &&
        expectedUserId == _sessionUserId &&
        _currentAuthUserId == expectedUserId;
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

  /// Refreshes provider-confirmed From identities without reconnecting OAuth.
  Future<void> refreshSenderIdentities({String? providerId}) async {
    final hadSenderIdentityFailure =
        _error?.startsWith('No se pudieron verificar') == true &&
            _error!.contains('remitentes');
    final providersToRefresh = providerId == null
        ? connectedProviders
        : connectedProviders
            .where((provider) => provider.providerId == providerId)
            .toList(growable: false);

    final failedProviders = <EmailProvider>[];
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final provider in providersToRefresh) {
      try {
        await provider.refreshSenderIdentities();
      } catch (error, stackTrace) {
        failedProviders.add(provider);
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (failedProviders.isNotEmpty) {
      _error = _providerFailureMessage(
        failedProviders,
        singleAction: 'No se pudieron verificar los remitentes de',
        multiAction: 'No se pudieron verificar algunos remitentes',
      );
      notifyListeners();
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }

    if (hadSenderIdentityFailure) {
      _error = null;
      notifyListeners();
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
    _providerReadCooldownUntil.remove(providerId);
    _providerLastSuccessfulInboxFetch.remove(providerId);
    _unifiedEmails.removeWhere((e) => e.providerId == providerId);
    notifyListeners();
  }

  /// Refresh inbox from all connected providers
  /// If background is true, don't show loading state (for background refresh)
  Future<void> refreshInbox({bool background = false}) {
    final inFlight = _refreshInboxFuture;
    if (inFlight != null) return inFlight;

    final epoch = _lifecycleEpoch;
    final userId = _sessionUserId;
    final operation = _refreshInbox(
      background: background,
      epoch: epoch,
      expectedUserId: userId,
    );
    _refreshInboxFuture = operation;
    return operation.whenComplete(() {
      if (identical(_refreshInboxFuture, operation)) {
        _refreshInboxFuture = null;
      }
    });
  }

  Future<void> _refreshInbox({
    required bool background,
    required int epoch,
    required String? expectedUserId,
  }) async {
    if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
    final previousKeys = _unifiedEmails.map(_emailKey).toSet();
    final previousNewestByProvider = _newestReceivedByProvider(_unifiedEmails);
    MailNotificationGate.shared.rememberInboxBaseline(previousKeys);
    final shouldNotifyNewMail = background && previousKeys.isNotEmpty;

    if (!background) {
      _isLoading = true;
      notifyListeners();
    }
    _error = null;

    try {
      final allEmails = <Email>[];
      final failedProviders = <EmailProvider>[];
      var hasDeferredProvider = false;
      final refreshStartedAt = DateTime.now();
      final hasActiveProviderCooldownAtStart = connectedProviders.any(
        (provider) =>
            _providerReadCooldownUntil[provider.providerId]
                ?.isAfter(refreshStartedAt) ??
            false,
      );

      for (final provider in connectedProviders) {
        final knownEmails = _unifiedEmails
            .where((email) => email.providerId == provider.providerId)
            .toList(growable: false);
        final cooldownUntil = _providerReadCooldownUntil[provider.providerId];
        if (cooldownUntil != null && cooldownUntil.isAfter(refreshStartedAt)) {
          if (knownEmails.isEmpty) {
            failedProviders.add(provider);
          } else {
            hasDeferredProvider = true;
          }
          allEmails.addAll(knownEmails);
          debugPrint(
            '📧 [MailManager] Skipping ${provider.providerId} until '
            '${cooldownUntil.toUtc().toIso8601String()} (provider cooldown)',
          );
          continue;
        }
        _providerReadCooldownUntil.remove(provider.providerId);
        final lastProviderFetch =
            _providerLastSuccessfulInboxFetch[provider.providerId];
        if (background &&
            hasActiveProviderCooldownAtStart &&
            lastProviderFetch != null &&
            refreshStartedAt.difference(lastProviderFetch).inSeconds < 30) {
          allEmails.addAll(knownEmails);
          debugPrint(
            '📧 [MailManager] Skipping ${provider.providerId}; its last '
            'authoritative fetch is still fresh',
          );
          continue;
        }

        try {
          final emails = await _fetchInboxForRefresh(
            provider: provider,
            knownEmails: knownEmails,
            epoch: epoch,
            expectedUserId: expectedUserId,
          );
          if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
          _providerReadCooldownUntil.remove(provider.providerId);
          _providerLastSuccessfulInboxFetch[provider.providerId] =
              DateTime.now();
          allEmails.addAll(
            background
                ? _reconcileProviderFetchedWindow(
                    provider: provider,
                    fetched: emails,
                  )
                : emails,
          );
        } catch (e) {
          final rateLimit = EmailProviderRateLimitException.tryParse(
            provider.providerId,
            e,
          );
          if (rateLimit != null) {
            _providerReadCooldownUntil[provider.providerId] = rateLimit.retryAt;
            allEmails.addAll(knownEmails);
            if (knownEmails.isEmpty) {
              failedProviders.add(provider);
            } else {
              hasDeferredProvider = true;
            }
            debugPrint(
              '📧 [MailManager] ${provider.providerId} deferred until '
              '${rateLimit.retryAt.toUtc().toIso8601String()}',
            );
            continue;
          }
          debugPrint('Error fetching ${provider.providerId} inbox: $e');
          failedProviders.add(provider);
          allEmails.addAll(
            _unifiedEmails
                .where((email) => email.providerId == provider.providerId),
          );
        }
      }

      if (!_isCurrentLifecycle(epoch, expectedUserId)) return;

      _unifiedEmails = _preservePendingReadStatuses(
        _dedupeAndSort(allEmails),
      );
      if (failedProviders.isEmpty && !hasDeferredProvider) {
        _lastFetch = DateTime.now();
      }

      if (shouldNotifyNewMail) {
        _emitNewEmailNotifications(
          _unifiedEmails,
          previousKeys,
          previousNewestByProvider,
        );
      }
      MailNotificationGate.shared.rememberInboxBaseline(
        _unifiedEmails.map(_emailKey),
      );

      if (failedProviders.isNotEmpty) {
        _error = _providerFailureMessage(
          failedProviders,
          singleAction: 'No se pudo actualizar',
          multiAction: 'No se pudieron actualizar algunas cuentas',
          suffix: 'Mostrando correos guardados.',
        );
      } else {
        final permissionWarnings = connectedProviders.where((provider) {
          final detail = provider.error?.toLowerCase() ?? '';
          return detail.contains('permisos zoho') ||
              detail.contains('organization.groups.read');
        }).toList(growable: false);
        if (permissionWarnings.isNotEmpty) {
          _error = _providerFailureMessage(
            permissionWarnings,
            singleAction: 'No se pudieron verificar los remitentes de',
            multiAction: 'No se pudieron verificar algunos remitentes',
          );
        }
      }

      // Save to SQLite cache for next app launch
      await _cache.cacheEmails(_unifiedEmails);
    } catch (e) {
      if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
      _error = e.toString();
    } finally {
      if (_isCurrentLifecycle(epoch, expectedUserId)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Every refresh reconciles at least the number of rows already loaded for
  /// the provider. Read/unread is provider-owned state: limiting background
  /// refreshes to the newest page leaves older cached rows permanently stale
  /// on a second device. The fetched window may grow to a page boundary; rows
  /// genuinely older than that window remain preserved by
  /// [_reconcileProviderFetchedWindow].
  Future<List<Email>> _fetchInboxForRefresh({
    required EmailProvider provider,
    required List<Email> knownEmails,
    required int epoch,
    required String? expectedUserId,
  }) async {
    final knownKeys = knownEmails.map(_emailKey).toSet();
    final oldestKnown = knownEmails.isEmpty
        ? null
        : knownEmails
            .map((email) => email.receivedTime)
            .reduce((left, right) => left.isBefore(right) ? left : right);
    final fetched = <Email>[];

    while (true) {
      final page = await _getInboxPageWithRetry(
        provider: provider,
        start: fetched.length,
        knownEmails: knownEmails,
        epoch: epoch,
        expectedUserId: expectedUserId,
      );
      if (!_isCurrentLifecycle(epoch, expectedUserId)) return fetched;
      fetched.addAll(page);

      final fetchedKeys = fetched.map(_emailKey).toSet();
      final allKnownRowsSeen = knownKeys.isNotEmpty &&
          knownKeys.every((knownKey) => fetchedKeys.contains(knownKey));
      final oldestFetched = fetched.isEmpty
          ? null
          : fetched
              .map((email) => email.receivedTime)
              .reduce((left, right) => left.isBefore(right) ? left : right);
      final crossedKnownWindow = oldestKnown != null &&
          oldestFetched != null &&
          oldestFetched.isBefore(oldestKnown);
      final coveredRequestedWindow = knownKeys.isEmpty
          ? fetched.length >= inboxPageSize
          : allKnownRowsSeen || crossedKnownWindow;

      if (page.isEmpty ||
          coveredRequestedWindow ||
          !provider.hasMoreIn(MailFolder.inbox)) {
        break;
      }
    }

    return _dedupeAndSort(fetched);
  }

  Future<List<Email>> _getInboxPageWithRetry({
    required EmailProvider provider,
    required int start,
    required List<Email> knownEmails,
    required int epoch,
    required String? expectedUserId,
  }) async {
    for (var attempt = 0;; attempt++) {
      try {
        return await provider.getMessages(
          folder: MailFolder.inbox,
          limit: inboxPageSize,
          start: start,
          knownEmails: knownEmails,
        );
      } catch (error) {
        final canRetry = attempt < _transientReadRetryDelays.length &&
            _isCurrentLifecycle(epoch, expectedUserId) &&
            _isTransientProviderReadFailure(provider, error);
        if (!canRetry) rethrow;

        final delay = _transientReadRetryDelays[attempt];
        debugPrint(
          '📧 [MailManager] Retrying ${provider.providerId} inbox page '
          '${attempt + 1}/${_transientReadRetryDelays.length} after a '
          'transient network failure',
        );
        final waitOverride = debugTransientReadRetryWaitOverride;
        if (waitOverride == null) {
          await Future<void>.delayed(delay);
        } else {
          await waitOverride(delay);
        }
        if (!_isCurrentLifecycle(epoch, expectedUserId)) rethrow;
      }
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

  /// Switches the folder the unified list shows.
  ///
  /// Search state never survives the switch: a query typed in the inbox
  /// silently filtering the trash would look like lost mail. The inbox keeps
  /// its data warm; any other folder refreshes on entry because nothing else
  /// (push, polling) keeps it honest.
  Future<void> setActiveFolder(MailFolder folder) async {
    if (_activeFolder == folder) return;
    _activeFolder = folder;
    clearSearch();
    clearSelection();
    if (folder != MailFolder.inbox) {
      await _loadFolder(folder);
    } else {
      notifyListeners();
      unawaited(backgroundRefresh());
    }
  }

  /// Refreshes whatever folder the user is looking at.
  Future<void> refreshActiveFolder() {
    if (_activeFolder == MailFolder.inbox) return refreshInbox();
    return _loadFolder(_activeFolder);
  }

  Future<void> _loadFolder(MailFolder folder) async {
    final epoch = _lifecycleEpoch;
    final expectedUserId = _sessionUserId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final collected = <Email>[];
      final failedProviders = <EmailProvider>[];
      final previous = _folderEmails[folder] ?? const <Email>[];

      for (final provider in connectedProviders) {
        try {
          final knownEmails = previous
              .where((email) => email.providerId == provider.providerId)
              .toList(growable: false);
          final emails = await provider.getMessages(
            folder: folder,
            limit: inboxPageSize,
            start: 0,
            knownEmails: knownEmails,
          );
          if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
          collected.addAll(emails);
        } catch (e) {
          debugPrint('Error fetching ${provider.providerId} $folder: $e');
          failedProviders.add(provider);
          collected.addAll(
            previous.where(
              (email) => email.providerId == provider.providerId,
            ),
          );
        }
      }

      if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
      _folderEmails[folder] = _dedupeAndSort(collected);

      if (failedProviders.isNotEmpty) {
        _error = _providerFailureMessage(
          failedProviders,
          singleAction: 'No se pudo cargar ${folder.label} de',
          multiAction: 'No se pudo cargar ${folder.label} en algunas cuentas',
        );
      }
    } catch (e) {
      if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
      _error = e.toString();
    } finally {
      if (_isCurrentLifecycle(epoch, expectedUserId)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Load the next page from the active provider filter, or all providers.
  Future<void> loadMore() async {
    if (_isLoadingMore || connectedProviders.isEmpty) return;

    final providersToLoad = _providersForActiveFilter()
        .where((provider) => isSearchActive
            ? provider.canLoadMore
            : provider.hasMoreIn(_activeFolder))
        .toList(growable: false);

    if (providersToLoad.isEmpty) return;

    _isLoadingMore = true;
    _error = null;
    notifyListeners();

    try {
      final fetched = <Email>[];

      final folder = _activeFolder;
      for (final provider in providersToLoad) {
        final source = isSearchActive
            ? _searchResults
            : folder == MailFolder.inbox
                ? _unifiedEmails
                : _folderEmails[folder] ?? const <Email>[];
        final knownEmails = source
            .where((email) => email.providerId == provider.providerId)
            .toList(growable: false);
        final page = await provider.getMessages(
          folder: folder,
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
        } else if (folder == MailFolder.inbox) {
          _unifiedEmails = _dedupeAndSort([..._unifiedEmails, ...fetched]);
          await _cache.cacheEmails(_unifiedEmails);
        } else {
          _folderEmails[folder] = _dedupeAndSort(
            [...?_folderEmails[folder], ...fetched],
          );
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
            final emails = await provider.getMessages(
              folder: _activeFolder,
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

  List<Email> _reconcileProviderFetchedWindow({
    required EmailProvider provider,
    required List<Email> fetched,
  }) {
    if (!provider.hasMoreIn(MailFolder.inbox)) {
      return fetched;
    }
    if (fetched.isEmpty) {
      return _unifiedEmails
          .where((email) => email.providerId == provider.providerId)
          .toList(growable: false);
    }

    final fetchedKeys = fetched.map(_emailKey).toSet();
    final oldestFetched = fetched
        .map((email) => email.receivedTime)
        .reduce((left, right) => left.isBefore(right) ? left : right);
    final olderLoaded = _unifiedEmails.where(
      (email) =>
          email.providerId == provider.providerId &&
          email.receivedTime.isBefore(oldestFetched) &&
          !fetchedKeys.contains(_emailKey(email)),
    );
    return _dedupeAndSort([...fetched, ...olderLoaded]);
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

  List<Email> _preservePendingReadStatuses(List<Email> emails) {
    if (_pendingReadStatus.isEmpty) return emails;
    return emails.map((email) {
      final pending = _pendingReadStatus[_emailKey(email)];
      return pending == null ? email : email.copyWith(isRead: pending);
    }).toList(growable: false);
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
      final detail = _providerErrorDetailForUser(provider);
      if (detail == null || detail.isEmpty) return provider.displayName;
      return '${provider.displayName}: $detail';
    }

    if (providers.length == 1) {
      final provider = providers.first;
      final detail = _providerErrorDetailForUser(provider);
      if (detail == null || detail.isEmpty) {
        return withSuffix('$singleAction ${provider.displayName}.');
      }
      return withSuffix('$singleAction ${provider.displayName}: $detail');
    }

    final details = providers.map(providerDetail).join(' · ');
    return withSuffix('$multiAction. $details');
  }

  bool _isTransientProviderReadFailure(
    EmailProvider provider,
    Object error,
  ) {
    final text = '$error ${provider.error ?? ''}'.toLowerCase();
    return _containsTransientNetworkMarker(text);
  }

  bool _containsTransientNetworkMarker(String text) {
    return const [
      'timeout',
      'socket',
      'network',
      'failed host',
      'host lookup',
      'dns',
      'connection refused',
      'connection reset',
      'clientexception',
      'status: 502',
      'status: 503',
      'status: 504',
      ' 502',
      ' 503',
      ' 504',
    ].any(text.contains);
  }

  String? _providerErrorDetailForUser(EmailProvider provider) {
    final detail = provider.error?.trim();
    if (detail == null || detail.isEmpty) return detail;
    if (_containsTransientNetworkMarker(detail.toLowerCase())) {
      return 'Red/API: la conexión falló temporalmente.';
    }
    return detail;
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
      unawaited(_setReadStatus(email, read: true));
    }
    notifyListeners();

    try {
      cachedContent = await _cache.getCachedContent(
        email.providerId,
        email.id,
      );
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
        await _cache.cacheContent(
          loadedEmail.providerId,
          loadedEmail.id,
          loadedContent,
        );
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

  /// Opens a concrete message already present in the unified read model.
  ///
  /// Filter/search state is normalized before selection so the canonical
  /// inbox can never display a message excluded by its active provider scope.
  Future<void> openKnownEmail(Email email) async {
    clearSearch();
    if (_providerFilter != email.providerId) {
      setProviderFilter(email.providerId);
    }
    await selectEmail(email);
  }

  /// Resolves a durable provider/message deep link into the canonical inbox.
  Future<bool> openEmailByIdentity({
    required String providerId,
    required String messageId,
    bool Function()? isRequestCurrent,
  }) async {
    final normalizedProviderId = providerId.trim();
    final normalizedMessageId = messageId.trim();
    if (normalizedProviderId.isEmpty || normalizedMessageId.isEmpty) {
      return false;
    }

    await initialize();
    if (isRequestCurrent?.call() == false) return false;

    Email? email = _findEmailByIdentity(
      normalizedProviderId,
      normalizedMessageId,
    );
    if (email == null) {
      await refreshInbox(background: true);
      if (isRequestCurrent?.call() == false) return false;
      email = _findEmailByIdentity(
        normalizedProviderId,
        normalizedMessageId,
      );
    }
    if (email == null) return false;
    if (isRequestCurrent?.call() == false) return false;

    await openKnownEmail(email);
    return true;
  }

  Email? _findEmailByIdentity(String providerId, String messageId) {
    for (final email in _unifiedEmails) {
      if (email.providerId == providerId && email.id == messageId) {
        return email;
      }
    }
    return null;
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
        await _cache.cacheContent(
          hydratedEmail.providerId,
          hydratedEmail.id,
          hydratedContent,
        );
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

  void _applyReadStatusLocally(Email email, bool read) {
    _replaceEmailReadStatus(_unifiedEmails, email, read);
    _replaceEmailReadStatus(_searchResults, email, read);
    for (final folderList in _folderEmails.values) {
      _replaceEmailReadStatus(folderList, email, read);
    }

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

  Map<String, DateTime> _newestReceivedByProvider(Iterable<Email> emails) {
    final newest = <String, DateTime>{};
    for (final email in emails) {
      final current = newest[email.providerId];
      if (current == null || email.receivedTime.isAfter(current)) {
        newest[email.providerId] = email.receivedTime;
      }
    }
    return newest;
  }

  void _emitNewEmailNotifications(
    List<Email> emails,
    Set<String> previousKeys,
    Map<String, DateTime> previousNewestByProvider,
  ) {
    final newUnreadEmails = emails.where((email) {
      final previousNewest = previousNewestByProvider[email.providerId];
      return !email.isRead &&
          !previousKeys.contains(_emailKey(email)) &&
          previousNewest != null &&
          email.receivedTime.isAfter(previousNewest);
    }).toList(growable: false);

    if (newUnreadEmails.isEmpty) return;

    newUnreadEmails.sort((a, b) => b.receivedTime.compareTo(a.receivedTime));
    var emitted = 0;
    for (final email in newUnreadEmails) {
      final isFirstDiscovery =
          MailNotificationGate.shared.claimInboxEvent(_emailKey(email));
      if (!isFirstDiscovery || emitted >= 3) continue;
      _newEmailController.add(email);
      emitted++;
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
    if (providerId != null && _selectedEmail?.providerId != providerId) {
      _selectedEmail = null;
      _selectedProvider = null;
      _selectedEmailError = null;
      _isLoadingSelectedEmail = false;
      _selectionRequestId++;
    }
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
    String? fromAddress,
    String? cc,
    String? bcc,
  }) async {
    final provider = getProvider(providerId);
    if (provider == null) return false;

    return provider.sendEmail(
      to: to,
      subject: subject,
      content: content,
      fromAddress: fromAddress,
      cc: cc,
      bcc: bcc,
    );
  }

  /// Reply to an email
  Future<bool> replyToEmail({
    required Email originalEmail,
    required String content,
    required String to,
    required String subject,
    String? fromAddress,
    String? cc,
    String? bcc,
    bool replyAll = false,
  }) async {
    final provider = getProvider(originalEmail.providerId);
    if (provider == null) return false;

    return provider.replyToEmail(
      emailId: originalEmail.id,
      content: content,
      to: to,
      subject: subject,
      fromAddress: fromAddress,
      cc: cc,
      bcc: bcc,
      threadId: originalEmail.threadId,
      rfcMessageId: originalEmail.rfcMessageId,
      references: originalEmail.references,
      replyAll: replyAll,
    );
  }

  /// Delete/trash selected email
  Future<bool> deleteSelectedEmail() {
    return _actOnSelectedEmail(
      (provider, emailId) => provider.moveToTrash(emailId),
    );
  }

  /// Devuelve el correo seleccionado desde la papelera a la bandeja de
  /// entrada.
  Future<bool> restoreSelectedEmail() {
    return _actOnSelectedEmail(
      (provider, emailId) => provider.restoreFromTrash(emailId),
    );
  }

  /// Reporta el correo seleccionado como spam y lo saca de la vista actual.
  Future<bool> markSelectedAsSpam() {
    return _actOnSelectedEmail(
      (provider, emailId) => provider.markAsSpam(emailId),
    );
  }

  /// Rescata de spam el correo seleccionado y lo devuelve a la bandeja.
  Future<bool> markSelectedAsNotSpam() {
    return _actOnSelectedEmail(
      (provider, emailId) => provider.markAsNotSpam(emailId),
    );
  }

  /// Toda acción que saca al correo de su carpeta comparte el mismo cierre:
  /// si el proveedor confirma, el mensaje desaparece de las listas locales y
  /// la selección se limpia. Las carpetas destino no se actualizan en local a
  /// ciegas — se recargan al entrar, que es su contrato general.
  Future<bool> _actOnSelectedEmail(
    Future<bool> Function(EmailProvider provider, String emailId) action,
  ) async {
    final email = _selectedEmail;
    final provider = _selectedProvider;
    if (email == null || provider == null) return false;

    final success = await action(provider, email.id);
    if (success) {
      bool matches(Email candidate) =>
          candidate.id == email.id && candidate.providerId == email.providerId;
      _unifiedEmails.removeWhere(matches);
      _searchResults.removeWhere(matches);
      for (final folderList in _folderEmails.values) {
        folderList.removeWhere(matches);
      }
      _selectedEmail = null;
      _selectedProvider = null;
      notifyListeners();
    }
    return success;
  }

  /// Mark email as read/unread
  Future<bool> markAsRead(Email email, {bool read = true}) =>
      _setReadStatus(email, read: read);

  /// Serializes provider mutations per message while keeping the UI immediate.
  ///
  /// The old open path persisted the optimistic flag before Gmail/Zoho had
  /// confirmed it and ignored a failed provider call. That made this session
  /// look correct while every other device retained the unread message. The
  /// queue also prevents a rapid read -> unread toggle from reaching the
  /// provider out of order.
  Future<bool> _setReadStatus(Email email, {required bool read}) {
    final provider = getProvider(email.providerId);
    if (provider == null) return Future<bool>.value(false);

    final key = _emailKey(email);
    final epoch = _lifecycleEpoch;
    final expectedUserId = _sessionUserId;
    final predecessor = _readMutationTails[key];
    if (predecessor == null) {
      _confirmedReadStatus[key] = _currentReadStatus(email) ?? email.isRead;
    }
    final version = (_readMutationVersions[key] ?? 0) + 1;
    _readMutationVersions[key] = version;
    _pendingReadStatus[key] = read;

    _applyReadStatusLocally(email, read);
    notifyListeners();

    late final Future<bool> operation;
    operation = () async {
      if (predecessor != null) await predecessor;
      if (!_isCurrentLifecycle(epoch, expectedUserId)) return false;

      var success = false;
      try {
        success = await provider.markAsRead(email.id, read: read);
      } catch (error) {
        debugPrint(
          '📧 [MailManager] Read status mutation threw for $key: $error',
        );
      }

      if (!_isCurrentLifecycle(epoch, expectedUserId)) return false;
      final isLatest = _readMutationVersions[key] == version;
      if (success) {
        _confirmedReadStatus[key] = read;
        if (isLatest) {
          await _updateCachedReadStatus(email, read);
          if (!_isCurrentLifecycle(epoch, expectedUserId)) return true;
          if (_readStatusFailureKey == key) {
            _readStatusFailureKey = null;
            _error = null;
            notifyListeners();
          }
        }
        return true;
      }

      debugPrint('📧 [MailManager] Could not sync read status for $key');
      if (isLatest) {
        final confirmed = _confirmedReadStatus[key] ?? email.isRead;
        _pendingReadStatus.remove(key);
        _applyReadStatusLocally(email, confirmed);
        await _updateCachedReadStatus(email, confirmed);
        if (!_isCurrentLifecycle(epoch, expectedUserId)) return false;
        _readStatusFailureKey = key;
        _error = _readStatusFailureMessage(provider, read: read);
        notifyListeners();
      }
      return false;
    }();

    final tail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
            '📧 [MailManager] Read mutation queue error for $key: $error');
      },
    );
    _readMutationTails[key] = tail;
    unawaited(tail.whenComplete(() {
      if (!identical(_readMutationTails[key], tail)) return;
      _readMutationTails.remove(key);
      _readMutationVersions.remove(key);
      _confirmedReadStatus.remove(key);
      _pendingReadStatus.remove(key);
    }));

    return operation;
  }

  bool? _currentReadStatus(Email identity) {
    for (final source in <List<Email>>[
      _unifiedEmails,
      _searchResults,
      ..._folderEmails.values,
    ]) {
      for (final email in source) {
        if (_emailKey(email) == _emailKey(identity)) return email.isRead;
      }
    }
    return null;
  }

  Future<void> _updateCachedReadStatus(Email email, bool read) async {
    try {
      await _cache.updateReadStatus(email.providerId, email.id, read);
    } catch (error) {
      // Provider truth already won. A cache write failure must not turn a
      // successful mailbox mutation into a false failure; the next refresh
      // rewrites the metadata cache.
      debugPrint('📧 [MailManager] Could not cache read status: $error');
    }
  }

  String _readStatusFailureMessage(
    EmailProvider provider, {
    required bool read,
  }) {
    final action = read ? 'marcar como leído' : 'marcar como no leído';
    final detail = _providerErrorDetailForUser(provider);
    final suffix = detail == null || detail.isEmpty ? '' : ' $detail';
    return 'No se pudo $action en ${provider.displayName}. '
        'Se restauró el estado confirmado.$suffix';
  }

  /// Override dispose but do nothing - singleton should persist.
  /// Use reset() for actual cleanup (logout, etc.)
  @override
  // ignore: must_call_super
  void dispose() {
    debugPrint('📧 [MailManager] dispose called (no-op for singleton)');
  }

  /// Attaches a scripted provider without Supabase. The unified read model —
  /// carpetas, paginación por carpeta, invariantes de bandeja de entrada — no
  /// tenía ninguna costura comprobable antes de esto.
  @visibleForTesting
  void debugAttachProvider(EmailProvider provider) {
    _providers.add(provider);
    provider.addListener(_onProviderChange);
  }

  /// Publica un alcance de sesión ficticio para pruebas del modelo de
  /// lectura. Debe usarse junto con [debugAuthUserIdOverride].
  @visibleForTesting
  void debugCommitSessionScope(String userId) {
    _sessionUserId = userId;
    _isSessionScopeReady = true;
  }

  /// Returns the singleton to a virgin in-memory state between tests.
  ///
  /// No sustituye a [reset]: no toca sesión, transporte ni caché persistente,
  /// que en pruebas unitarias no existen.
  @visibleForTesting
  void debugResetInMemoryState() {
    for (final provider in _providers) {
      provider.removeListener(_onProviderChange);
    }
    _providers.clear();
    _unifiedEmails.clear();
    _folderEmails.clear();
    _activeFolder = MailFolder.inbox;
    _searchResults.clear();
    _searchQuery = '';
    _isSearching = false;
    _searchRequestId++;
    _selectedEmail = null;
    _selectedProvider = null;
    _selectedEmailError = null;
    _isLoadingSelectedEmail = false;
    _selectionRequestId++;
    _providerFilter = null;
    _error = null;
    _isLoading = false;
    _isLoadingMore = false;
    _lastFetch = null;
    _readMutationTails.clear();
    _readMutationVersions.clear();
    _confirmedReadStatus.clear();
    _pendingReadStatus.clear();
    _providerReadCooldownUntil.clear();
    _providerLastSuccessfulInboxFetch.clear();
    _readStatusFailureKey = null;
    debugTransientReadRetryWaitOverride = null;
    _sessionUserId = null;
    _isSessionScopeReady = false;
    debugAuthUserIdOverride = null;
  }

  /// Resets every user-scoped resource without closing the process-wide event
  /// stream. A later authenticated shell can safely subscribe and initialize
  /// the same singleton again.
  Future<void> reset() => prepareSession(null);

  Future<void> _resetInternal({required String? nextUserId}) async {
    RealtimeChannel? pushChannel;
    await MailSessionTransition.run(
      nextUserId: nextUserId,
      invalidateSession: () {
        _lifecycleEpoch++;
        _sessionUserId = null;
        _isSessionScopeReady = false;
        _pollingTimer?.cancel();
        _pollingTimer = null;
        _refreshDebounceTimer?.cancel();
        _refreshDebounceTimer = null;
        _refreshInboxFuture = null;
        _readMutationTails.clear();
        _readMutationVersions.clear();
        _confirmedReadStatus.clear();
        _pendingReadStatus.clear();
        _providerReadCooldownUntil.clear();
        _providerLastSuccessfulInboxFetch.clear();
        _readStatusFailureKey = null;
        _initializingFuture = null;
        _initializingUserId = null;
        _initializingEpoch = null;
        _isLoading = false;
        _isLoadingMore = false;
        for (final provider in _providers) {
          provider.removeListener(_onProviderChange);
        }
        _providers.clear();
        _unifiedEmails.clear();
        _folderEmails.clear();
        _activeFolder = MailFolder.inbox;
        _searchResults.clear();
        _searchQuery = '';
        _isSearching = false;
        _searchRequestId++;
        _selectedEmail = null;
        _selectedProvider = null;
        _selectedEmailError = null;
        _isLoadingSelectedEmail = false;
        _selectionRequestId++;
        _providerFilter = null;
        _error = null;
        _isInitialized = false;
        _lastFetch = null;
        pushChannel = _pushChannel;
        _pushChannel = null;
        _isPushEnabled = false;
        MailNotificationGate.shared.clearScope();
        notifyListeners();
      },
      unsubscribeTransport: () async {
        final channel = pushChannel;
        if (channel == null) return;
        await channel.unsubscribe().timeout(const Duration(seconds: 3));
      },
      invalidateCache: () => _invalidateCacheForSession(nextUserId),
      commitSession: (userId) {
        _sessionUserId = userId;
        _isSessionScopeReady = true;
      },
      onTransportError: (error, _) {
        debugPrint(
          '📧 [MailManager] Push teardown skipped during session change: '
          '$error',
        );
      },
    );
    notifyListeners();
  }

  Future<void> _invalidateCacheForSession(String? nextUserId) async {
    await _cache.initialize();
    if (!_cache.isAvailableForSessionIsolation) {
      throw StateError(
        'The local mail cache could not be opened for session isolation.',
      );
    }
    final preferences = await SharedPreferences.getInstance();
    final cachedUserId = preferences.getString(_cacheUserScopePreference);
    if (nextUserId == null || cachedUserId != nextUserId) {
      await _cache.clearCache();
    }

    final scopePersisted = nextUserId == null
        ? await preferences.remove(_cacheUserScopePreference)
        : await preferences.setString(
            _cacheUserScopePreference,
            nextUserId,
          );
    if (!scopePersisted) {
      throw StateError('Could not persist the mail cache user scope.');
    }
  }

  /// Set up realtime subscription to listen for push notifications
  Future<void> _setupPushSubscription({
    required int epoch,
    required String? expectedUserId,
  }) async {
    final supabase = Supabase.instance.client;
    final userId = expectedUserId;

    if (userId == null || !_isCurrentLifecycle(epoch, expectedUserId)) {
      debugPrint('📧 [MailManager] No user ID, skipping push setup');
      return;
    }

    try {
      // A Realtime channel and a renewed Gmail watch prove transport setup,
      // not end-to-end Pub/Sub delivery. Keep the shorter fallback until this
      // session actually receives a new-mail flag.
      _isPushEnabled = false;

      // Subscribe to changes on email_push_subscriptions for this user
      final previousChannel = _pushChannel;
      _pushChannel = null;
      if (previousChannel != null) await previousChannel.unsubscribe();
      if (!_isCurrentLifecycle(epoch, expectedUserId)) return;

      late final RealtimeChannel channel;
      channel = supabase
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
              if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
              debugPrint('📧 [MailManager] 🔔 Push notification received!');
              debugPrint('📧 [MailManager] Payload: ${payload.newRecord}');

              // Check if this is a new mail notification
              final newMailNotification =
                  payload.newRecord['new_mail_notification'] as bool? ?? false;

              if (newMailNotification) {
                if (!_isPushEnabled) {
                  _isPushEnabled = true;
                  debugPrint(
                    '📧 [MailManager] ✅ End-to-end push delivery verified',
                  );
                  _startPolling(
                    epoch: epoch,
                    expectedUserId: expectedUserId,
                  );
                }

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
                  if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
                  debugPrint(
                      '📧 [MailManager] Debounce complete. Refreshing inbox...');
                  refreshInbox(background: true);
                });
              }
            },
          )
          .subscribe();

      if (!_isCurrentLifecycle(epoch, expectedUserId)) {
        await channel.unsubscribe();
        return;
      }
      _pushChannel = channel;

      debugPrint(
        '📧 [MailManager] Realtime listener active; awaiting a provider event',
      );

      // Set up push for each connected provider
      for (final provider in connectedProviders) {
        if (provider is GmailProvider) {
          final success = await provider.setupPushNotifications();
          if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
          debugPrint(
            '📧 [MailManager] Gmail watch setup: '
            '${success ? "✅ (delivery not yet verified)" : "❌ (using polling)"}',
          );
        }
        // TODO: Add Zoho push setup when implemented
      }
    } catch (e) {
      debugPrint('📧 [MailManager] Push setup error: $e');
      // Push is optional, polling is the fallback
    }
  }

  void _startPolling({
    required int epoch,
    required String? expectedUserId,
  }) {
    _pollingTimer?.cancel();
    // Only a provider event observed in this session earns the slower 5-minute
    // safety poll. A configured watch that never reaches the webhook remains
    // on the 3-minute fallback.
    final pollInterval = _isPushEnabled ? 300 : 180;
    debugPrint(
        '📧 [MailManager] Starting fallback polling (${pollInterval}s, push: $_isPushEnabled)');
    _pollingTimer = Timer.periodic(Duration(seconds: pollInterval), (_) async {
      if (!_isCurrentLifecycle(epoch, expectedUserId)) return;
      // Only refresh if we have listeners (Active UI)
      if (!hasListeners) return;

      if (connectedProviders.isEmpty) return;
      debugPrint('📧 [MailManager] Polling: Auto-refreshing inbox...');
      await refreshInbox(background: true);
    });
  }
}

/// Coordinates the security boundary between two authenticated mail sessions.
///
/// The old scope is invalidated synchronously. Cache invalidation and transport
/// teardown may then run concurrently, but the next scope is committed only
/// after both have completed. Transport teardown is best-effort because every
/// callback is independently guarded by the manager lifecycle epoch; cache
/// invalidation remains mandatory and its failure keeps the manager closed.
@visibleForTesting
class MailSessionTransition {
  const MailSessionTransition._();

  static Future<void> run({
    required String? nextUserId,
    required VoidCallback invalidateSession,
    required Future<void> Function() unsubscribeTransport,
    required Future<void> Function() invalidateCache,
    required ValueChanged<String?> commitSession,
    void Function(Object error, StackTrace stackTrace)? onTransportError,
  }) async {
    invalidateSession();

    final transportTeardown = () async {
      try {
        await unsubscribeTransport();
      } catch (error, stackTrace) {
        onTransportError?.call(error, stackTrace);
      }
    }();

    await invalidateCache();
    await transportTeardown;
    commitSession(nextUserId);
  }
}
