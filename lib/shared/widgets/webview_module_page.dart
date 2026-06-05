import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../modules/storage/models/app_stored_file.dart';
import '../../modules/storage/services/app_file_storage_service.dart';
import '../services/document_relay_service.dart';
import '../services/smart_screenshot_service.dart';
import '../services/window_zoom_service.dart';
import '../services/workspace_manager.dart';
import '../utils/file_download.dart';

/// Persistent browser workspace - loads a website as a first-class workspace.
///
/// Uses flutter_inappwebview for the richest native WebView surface available
/// across the app targets:
/// - Android, iOS, macOS: platform native WebView/WKWebView
/// - Windows: WebView2
/// - Linux, Web: fallback UI with external-browser action
class WebViewModulePage extends StatefulWidget {
  final String url;
  final String title;
  final IconData icon;
  final Color? iconColor;

  const WebViewModulePage({
    super.key,
    required this.url,
    required this.title,
    this.icon = Icons.web,
    this.iconColor,
  });

  @override
  State<WebViewModulePage> createState() => _WebViewModulePageState();
}

class _WebViewModulePageState extends State<WebViewModulePage>
    with AutomaticKeepAliveClientMixin {
  static const _webkitUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.0 Safari/605.1.15';
  static const _iosUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';
  static const _androidUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  static const _edgeUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0';
  static const _windowsRuntimeUrl =
      'https://developer.microsoft.com/en-us/microsoft-edge/webview2/';
  static const _historyPrefsKey = 'vinabike_browser_history_v1';
  static const _bookmarkPrefsKey = 'vinabike_browser_bookmarks_v1';
  static const _pageInteractionHandlerName = 'VinabikeBrowserPageInteraction';
  static const _maxHistoryEntries = 120;
  static const _maxBookmarkEntries = 80;
  static const _suggestionDelay = Duration(milliseconds: 180);
  static const _suggestionTimeout = Duration(milliseconds: 1200);
  static const _downloadTimeout = Duration(seconds: 45);

  InAppWebViewController? _controller;
  WebViewEnvironment? _webViewEnvironment;
  final GlobalKey _browserViewportKey =
      GlobalKey(debugLabel: 'browser viewport');
  final DocumentRelayService _documentRelayService = DocumentRelayService();
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();
  bool _didSelectAddressForFocus = false;

  Uri? _initialUri;
  Uri? _nativeInitialUri;
  bool _isInitializing = true;
  bool _isLoading = true;
  int _loadingProgress = 0;
  String _currentUrl = '';
  String? _pageTitle;
  String? _platformMessage;
  String? _lastErrorMessage;
  String? _relayPreviewSourceUrl;
  _RelayDocumentPreview? _relayDocumentPreview;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _isDownloading = false;
  bool _isFetchingDocumentViaRelay = false;
  bool _isPrintingRelayPreview = false;
  bool _documentRelayAvailable = false;
  double _relayPreviewZoom = 1.0;
  double? _lastAppliedBrowserZoom;
  double? _pendingBrowserZoom;
  Offset _pendingWindowsTrackpadScroll = Offset.zero;
  Offset? _lastWindowsTrackpadPosition;
  Timer? _windowsTrackpadScrollTimer;
  Timer? _suggestionTimer;
  Timer? _hideSuggestionsTimer;
  List<_BrowserHistoryEntry> _historyEntries = const [];
  List<_BrowserBookmarkEntry> _bookmarkEntries = const [];
  List<String> _searchSuggestions = const [];
  String _activeSuggestionQuery = '';
  bool _isFetchingSuggestions = false;
  bool _showAddressSuggestions = false;
  String? _registeredScreenshotWorkspaceId;

  @override
  bool get wantKeepAlive => true;

  bool get _usesNativeBrowser {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  String get _userAgent {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return _androidUserAgent;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _iosUserAgent;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      return _edgeUserAgent;
    }
    return _webkitUserAgent;
  }

  double _browserZoom(BuildContext context) {
    if (!WindowZoomService.isDesktop) return 1.0;
    try {
      final scale = context.watch<WindowZoomService>().scale;
      return scale.clamp(0.5, 3.0).toDouble();
    } on ProviderNotFoundException {
      return 1.0;
    }
  }

  InAppWebViewSettings _browserSettings(double browserZoom) =>
      InAppWebViewSettings(
        useShouldOverrideUrlLoading: true,
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: true,
        supportMultipleWindows: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        allowsBackForwardNavigationGestures: true,
        allowsLinkPreview: true,
        cacheEnabled: true,
        cacheMode: CacheMode.LOAD_DEFAULT,
        clearCache: false,
        clearSessionCache: false,
        databaseEnabled: true,
        domStorageEnabled: true,
        geolocationEnabled: true,
        hardwareAcceleration: true,
        horizontalScrollBarEnabled: true,
        iframeAllow:
            'camera; microphone; geolocation; clipboard-read; clipboard-write; fullscreen; payment',
        iframeAllowFullscreen: true,
        incognito: false,
        isInspectable: kDebugMode,
        initialScale: (browserZoom * 100).round(),
        mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
        needInitialFocus: true,
        pageZoom: browserZoom,
        safeBrowsingEnabled: true,
        sharedCookiesEnabled: true,
        thirdPartyCookiesEnabled: true,
        textZoom: (browserZoom * 100).round(),
        transparentBackground: false,
        useHybridComposition: true,
        useOnDownloadStart: true,
        useWideViewPort: true,
        userAgent: _userAgent,
        verticalScrollBarEnabled: true,
      );

  void _scheduleBrowserZoom(double browserZoom) {
    final controller = _controller;
    if (controller == null) return;
    if (_pendingBrowserZoom != null &&
        (_pendingBrowserZoom! - browserZoom).abs() < 0.001) {
      return;
    }
    if (_lastAppliedBrowserZoom != null &&
        (_lastAppliedBrowserZoom! - browserZoom).abs() < 0.001) {
      return;
    }

    _pendingBrowserZoom = browserZoom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = _pendingBrowserZoom;
      _pendingBrowserZoom = null;
      if (pending == null) return;
      unawaited(_applyBrowserZoom(pending));
    });
  }

  Future<void> _applyBrowserZoom(double browserZoom) async {
    final controller = _controller;
    if (controller == null) return;
    if (_lastAppliedBrowserZoom != null &&
        (_lastAppliedBrowserZoom! - browserZoom).abs() < 0.001) {
      return;
    }

    final previousZoom = _lastAppliedBrowserZoom ?? 1.0;

    try {
      final settings =
          await controller.getSettings() ?? _browserSettings(browserZoom);
      settings
        ..initialScale = (browserZoom * 100).round()
        ..pageZoom = browserZoom
        ..textZoom = (browserZoom * 100).round();
      await controller.setSettings(settings: settings);

      if (defaultTargetPlatform == TargetPlatform.windows) {
        final relativeZoom = browserZoom / previousZoom;
        if (relativeZoom.isFinite && (relativeZoom - 1.0).abs() > 0.001) {
          await controller.zoomBy(zoomFactor: relativeZoom);
        }
      }

      _lastAppliedBrowserZoom = browserZoom;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Web workspace zoom sync skipped: $error');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _addressController.addListener(_handleAddressTextChanged);
    _addressFocusNode.addListener(_handleAddressFocusChanged);
    unawaited(_loadBrowserHistory());
    unawaited(_loadBrowserBookmarks());
    unawaited(_loadDocumentRelayAvailability());
    unawaited(_prepareBrowser());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registerScreenshotContext();
  }

  @override
  void dispose() {
    _unregisterScreenshotContext();
    _suggestionTimer?.cancel();
    _hideSuggestionsTimer?.cancel();
    _windowsTrackpadScrollTimer?.cancel();
    unawaited(_webViewEnvironment?.dispose());
    _addressController.removeListener(_handleAddressTextChanged);
    _addressFocusNode.removeListener(_handleAddressFocusChanged);
    _addressController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  void _registerScreenshotContext() {
    Workspace? workspace;
    try {
      workspace = Provider.of<Workspace>(context, listen: false);
    } catch (_) {
      return;
    }

    if (_registeredScreenshotWorkspaceId != null &&
        _registeredScreenshotWorkspaceId != workspace.id) {
      context
          .read<SmartScreenshotService>()
          .unregisterBrowserContext(_registeredScreenshotWorkspaceId!);
    }

    _registeredScreenshotWorkspaceId = workspace.id;
    context.read<SmartScreenshotService>().registerBrowserContext(
          workspace.id,
          BrowserScreenshotContext(
            capturePng: _takeBrowserScreenshot,
            currentUrl: () => _currentUrl.isEmpty ? widget.url : _currentUrl,
            pageTitle: () => _pageTitle ?? widget.title,
            viewportGlobalRect: _browserViewportGlobalRect,
          ),
        );
  }

  void _unregisterScreenshotContext() {
    final workspaceId = _registeredScreenshotWorkspaceId;
    if (workspaceId == null) return;
    try {
      context.read<SmartScreenshotService>().unregisterBrowserContext(
            workspaceId,
          );
    } catch (_) {
      // The provider tree can be gone during app shutdown.
    }
    _registeredScreenshotWorkspaceId = null;
  }

  Future<Uint8List?> _takeBrowserScreenshot() async {
    if (_relayDocumentPreview != null) return null;
    final controller = _controller;
    if (controller == null) return null;
    try {
      return controller.takeScreenshot();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser screenshot skipped: $error');
      }
      return null;
    }
  }

  Rect? _browserViewportGlobalRect() {
    final context = _browserViewportKey.currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  Future<void> _prepareBrowser() async {
    final initialUri = _normalizeAddress(widget.url);
    if (initialUri == null) {
      _finishInitialization(
        message: 'La URL inicial no es válida.',
        loading: false,
      );
      return;
    }

    _initialUri = initialUri;
    _currentUrl = initialUri.toString();
    _syncAddressField(_currentUrl);
    final shouldLoadThroughRelay =
        await _shouldOpenDocumentThroughRelay(initialUri);
    _nativeInitialUri =
        shouldLoadThroughRelay ? Uri.parse('about:blank') : initialUri;

    if (!_usesNativeBrowser) {
      _finishInitialization(loading: false);
      if (shouldLoadThroughRelay) {
        unawaited(_startDocumentRelayForUrl(initialUri.toString()));
      }
      return;
    }

    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await InAppWebViewController.setWebContentsDebuggingEnabled(
          kDebugMode,
        );
      }

      if (defaultTargetPlatform == TargetPlatform.windows) {
        final runtimeVersion = await WebViewEnvironment.getAvailableVersion();
        if (runtimeVersion == null) {
          _finishInitialization(
            message:
                'Microsoft Edge WebView2 Runtime no está instalado en este equipo.',
            loading: false,
          );
          return;
        }

        _webViewEnvironment = await WebViewEnvironment.create(
          settings: WebViewEnvironmentSettings(
            allowSingleSignOnUsingOSPrimaryAccount: true,
          ),
        );
      }

      _finishInitialization(loading: !shouldLoadThroughRelay);
      if (shouldLoadThroughRelay) {
        unawaited(_startDocumentRelayForUrl(initialUri.toString()));
      }
    } catch (error) {
      _finishInitialization(
        message: 'No se pudo inicializar el navegador embebido: $error',
        loading: false,
      );
    }
  }

  void _finishInitialization({String? message, required bool loading}) {
    if (!mounted) return;
    setState(() {
      _platformMessage = message;
      _isInitializing = false;
      _isLoading = loading;
    });
  }

  URLRequest _urlRequest(Uri uri) => URLRequest(url: WebUri.uri(uri));

  Future<bool> _loadDocumentRelayAvailability() async {
    try {
      final config = await _documentRelayService.loadConfig();
      final isConfigured = config.isConfigured;
      if (!mounted) return isConfigured;
      setState(() => _documentRelayAvailable = isConfigured);
      return isConfigured;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Document relay availability skipped: $error');
      }
      return false;
    }
  }

  Future<bool> _shouldOpenDocumentThroughRelay(Uri uri) async {
    if (!DocumentRelayService.isLikelyRelayCandidate(uri)) return false;
    if (_documentRelayAvailable) return true;
    return _loadDocumentRelayAvailability();
  }

  Future<bool> _tryOpenDocumentThroughRelay(String sourceUrl) async {
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || !await _shouldOpenDocumentThroughRelay(uri)) {
      return false;
    }

    unawaited(_startDocumentRelayForUrl(sourceUrl));
    return true;
  }

  Future<void> _startDocumentRelayForUrl(String sourceUrl) async {
    if (_isFetchingDocumentViaRelay) return;
    if (!mounted) return;

    setState(() {
      _relayPreviewSourceUrl = sourceUrl;
      _relayDocumentPreview = null;
      _currentUrl = sourceUrl;
      _pageTitle = 'Documento web';
      _lastErrorMessage = null;
      _isLoading = false;
      _loadingProgress = 100;
    });
    _syncAddressField(sourceUrl);

    await _fetchCurrentDocumentThroughRelay(sourceUrlOverride: sourceUrl);
  }

  Future<void> _goBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      if (mounted) {
        setState(_clearRelayPreviewState);
      } else {
        _clearRelayPreviewState();
      }
      await controller.goBack();
    }
  }

  Future<void> _goForward() async {
    final controller = _controller;
    if (controller != null && await controller.canGoForward()) {
      if (mounted) {
        setState(_clearRelayPreviewState);
      } else {
        _clearRelayPreviewState();
      }
      await controller.goForward();
    }
  }

  Future<void> _reload() async {
    if (_relayDocumentPreview != null) {
      await _fetchCurrentDocumentThroughRelay();
      return;
    }
    await _controller?.reload();
  }

  Future<void> _goHome() async {
    final uri = _initialUri ?? _normalizeAddress(widget.url);
    if (uri == null) return;
    await _loadUri(uri);
  }

  Future<void> _loadAddress(String input) async {
    _hideAddressSuggestions();

    final uri = _normalizeAddress(input);
    if (uri == null) {
      setState(() {
        _lastErrorMessage = 'No pude entender esa dirección web.';
      });
      return;
    }

    FocusScope.of(context).unfocus();
    await _loadUri(uri);
  }

  Future<void> _loadUri(Uri uri) async {
    if (await _tryOpenDocumentThroughRelay(uri.toString())) {
      return;
    }

    if (!_canLoadInsideWebView(uri)) {
      await _openExternalUrl(uri.toString());
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingProgress = 0;
      _lastErrorMessage = null;
      _relayPreviewSourceUrl = null;
      _relayDocumentPreview = null;
    });

    await _controller?.loadUrl(urlRequest: _urlRequest(uri));
  }

  Future<void> _openCurrentExternal() async {
    final url = _currentUrl.isEmpty ? widget.url : _currentUrl;
    await _openExternalUrl(url);
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openCurrentInChrome() async {
    final url = _currentUrl.isEmpty ? widget.url : _currentUrl;
    final chromeUri = _chromeUriFor(url);
    if (chromeUri != null && await canLaunchUrl(chromeUri)) {
      await launchUrl(chromeUri, mode: LaunchMode.externalApplication);
      return;
    }

    await _openExternalUrl(url);
  }

  Uri? _chromeUriFor(String url) {
    if (url.startsWith('https://')) {
      return Uri.tryParse(url.replaceFirst('https://', 'googlechromes://'));
    }
    if (url.startsWith('http://')) {
      return Uri.tryParse(url.replaceFirst('http://', 'googlechrome://'));
    }
    return null;
  }

  Future<void> _handleBrowserMenuAction(_BrowserMenuAction action) async {
    switch (action) {
      case _BrowserMenuAction.recent:
        await _showBrowserLibraryDialog(_BrowserLibraryKind.recent);
      case _BrowserMenuAction.bookmarks:
        await _showBrowserLibraryDialog(_BrowserLibraryKind.bookmarks);
      case _BrowserMenuAction.clearData:
        await _confirmClearBrowserData();
      case _BrowserMenuAction.openInChrome:
        await _openCurrentInChrome();
      case _BrowserMenuAction.openExternal:
        await _openCurrentExternal();
    }
  }

  Future<void> _refreshNavigationState() async {
    final controller = _controller;
    if (controller == null) return;

    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();
    if (!mounted) return;
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  void _syncAddressField(String url) {
    if (_addressFocusNode.hasFocus) return;
    if (_addressController.text == url) return;
    _addressController.text = url;
  }

  void _handleAddressFocusChanged() {
    if (!mounted) return;
    if (_addressFocusNode.hasFocus) {
      _hideSuggestionsTimer?.cancel();
      _didSelectAddressForFocus = false;
      _queueAddressSuggestions(_addressController.text);
      _selectAddressTextAfterFocus();
      setState(() => _showAddressSuggestions = true);
    } else {
      _suggestionTimer?.cancel();
      _hideSuggestionsTimer?.cancel();
      _hideSuggestionsTimer = Timer(const Duration(milliseconds: 160), () {
        if (!mounted || _addressFocusNode.hasFocus) return;
        setState(() => _showAddressSuggestions = false);
      });
      setState(() {});
    }
  }

  void _handleAddressTextChanged() {
    if (!_addressFocusNode.hasFocus) return;
    _queueAddressSuggestions(_addressController.text);
    if (mounted) {
      setState(() => _showAddressSuggestions = true);
    }
  }

  void _selectAddressTextAfterFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_addressFocusNode.hasFocus ||
          _didSelectAddressForFocus) {
        return;
      }

      _addressController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _addressController.text.length,
      );
      _didSelectAddressForFocus = true;
    });
  }

  void _queueAddressSuggestions(String input) {
    _suggestionTimer?.cancel();

    final query = input.trim();
    if (query.length < 2 || _looksLikeDirectAddress(query)) {
      if (_searchSuggestions.isNotEmpty || _activeSuggestionQuery.isNotEmpty) {
        setState(() {
          _searchSuggestions = const [];
          _activeSuggestionQuery = '';
          _isFetchingSuggestions = false;
        });
      }
      return;
    }

    _suggestionTimer = Timer(_suggestionDelay, () {
      unawaited(_fetchSearchSuggestions(query));
    });
  }

  bool _looksLikeDirectAddress(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return true;
    }
    if (trimmed.contains('://')) return true;
    if (trimmed.startsWith('localhost') ||
        trimmed.startsWith('127.0.0.1') ||
        trimmed.startsWith('[::1]')) {
      return true;
    }
    return !trimmed.contains(' ') && trimmed.contains('.');
  }

  Future<void> _fetchSearchSuggestions(String query) async {
    if (!mounted || !_addressFocusNode.hasFocus) return;
    if (_activeSuggestionQuery == query && _searchSuggestions.isNotEmpty) {
      return;
    }

    setState(() => _isFetchingSuggestions = true);

    try {
      final uri = Uri.https(
        'suggestqueries.google.com',
        '/complete/search',
        {
          'client': 'firefox',
          'q': query,
        },
      );
      final response = await http.get(uri).timeout(_suggestionTimeout);
      if (!mounted ||
          !_addressFocusNode.hasFocus ||
          _addressController.text.trim() != query) {
        return;
      }

      final decoded = jsonDecode(response.body);
      final rawSuggestions =
          decoded is List && decoded.length > 1 ? decoded[1] : null;
      final suggestions = rawSuggestions is List
          ? rawSuggestions
              .whereType<String>()
              .where((value) => value.trim().isNotEmpty)
              .take(6)
              .toList(growable: false)
          : const <String>[];

      setState(() {
        _activeSuggestionQuery = query;
        _searchSuggestions = suggestions;
        _isFetchingSuggestions = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('🌐 Browser suggestions skipped: $error');
      }
      setState(() {
        _activeSuggestionQuery = query;
        _searchSuggestions = const [];
        _isFetchingSuggestions = false;
      });
    }
  }

  void _hideAddressSuggestions() {
    _suggestionTimer?.cancel();
    _hideSuggestionsTimer?.cancel();
    if (!_showAddressSuggestions &&
        _searchSuggestions.isEmpty &&
        _activeSuggestionQuery.isEmpty) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _showAddressSuggestions = false;
      _searchSuggestions = const [];
      _activeSuggestionQuery = '';
      _isFetchingSuggestions = false;
    });
  }

  Future<void> _loadBrowserHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getStringList(_historyPrefsKey) ?? const [];
      final entries = <_BrowserHistoryEntry>[];
      for (final item in encoded) {
        final entry = _BrowserHistoryEntry.tryDecode(item);
        if (entry != null) entries.add(entry);
      }
      entries.sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
      if (!mounted) return;
      setState(() {
        _historyEntries = entries.take(_maxHistoryEntries).toList();
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser history load skipped: $error');
      }
    }
  }

  Future<void> _recordBrowserHistory(WebUri? url, {String? title}) async {
    if (url == null) return;
    final uri = Uri.tryParse(url.toString());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }

    final value = uri.toString();
    final cleanTitle = title?.trim() ?? '';
    final entry = _BrowserHistoryEntry(
      url: value,
      title: cleanTitle.isEmpty ? uri.host : cleanTitle,
      visitedAt: DateTime.now(),
    );

    final nextEntries = <_BrowserHistoryEntry>[
      entry,
      ..._historyEntries.where((candidate) => candidate.url != value),
    ].take(_maxHistoryEntries).toList(growable: false);

    if (mounted) {
      setState(() => _historyEntries = nextEntries);
    } else {
      _historyEntries = nextEntries;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _historyPrefsKey,
        nextEntries.map((entry) => entry.encode()).toList(growable: false),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser history save skipped: $error');
      }
    }
  }

  Future<void> _loadBrowserBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getStringList(_bookmarkPrefsKey) ?? const [];
      final entries = <_BrowserBookmarkEntry>[];
      for (final item in encoded) {
        final entry = _BrowserBookmarkEntry.tryDecode(item);
        if (entry != null) entries.add(entry);
      }
      entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      if (!mounted) return;
      setState(() {
        _bookmarkEntries = entries.take(_maxBookmarkEntries).toList();
      });
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser bookmarks load skipped: $error');
      }
    }
  }

  Future<void> _saveBrowserBookmarks(
    List<_BrowserBookmarkEntry> entries,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _bookmarkPrefsKey,
        entries.map((entry) => entry.encode()).toList(growable: false),
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser bookmarks save skipped: $error');
      }
    }
  }

  bool get _isCurrentBookmarked {
    final url = _currentBookmarkableUrl();
    if (url == null) return false;
    return _bookmarkEntries.any((entry) => entry.url == url);
  }

  String? _currentBookmarkableUrl() {
    final uri = Uri.tryParse(_currentUrl.isEmpty ? widget.url : _currentUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return uri.toString();
  }

  Future<void> _toggleCurrentBookmark() async {
    final value = _currentBookmarkableUrl();
    if (value == null) return;

    final existingIndex =
        _bookmarkEntries.indexWhere((entry) => entry.url == value);
    late final List<_BrowserBookmarkEntry> nextEntries;
    late final String message;

    if (existingIndex >= 0) {
      nextEntries = [
        for (var i = 0; i < _bookmarkEntries.length; i++)
          if (i != existingIndex) _bookmarkEntries[i],
      ];
      message = 'Marcador eliminado.';
    } else {
      final uri = Uri.parse(value);
      final title = (_pageTitle?.trim().isNotEmpty == true)
          ? _pageTitle!.trim()
          : uri.host;
      nextEntries = [
        _BrowserBookmarkEntry(
          url: value,
          title: title,
          savedAt: DateTime.now(),
        ),
        ..._bookmarkEntries.where((entry) => entry.url != value),
      ].take(_maxBookmarkEntries).toList(growable: false);
      message = 'Marcador guardado.';
    }

    if (mounted) {
      setState(() => _bookmarkEntries = nextEntries);
      _showBrowserSnack(message);
    } else {
      _bookmarkEntries = nextEntries;
    }
    await _saveBrowserBookmarks(nextEntries);
  }

  Future<void> _showBrowserLibraryDialog(_BrowserLibraryKind kind) async {
    final isBookmarks = kind == _BrowserLibraryKind.bookmarks;
    final entries = isBookmarks
        ? _bookmarkEntries
            .map(
              (entry) => _BrowserPlaceEntry(
                url: entry.url,
                title: entry.title,
                subtitle: entry.host,
                icon: Icons.star,
              ),
            )
            .toList(growable: false)
        : _historyEntries
            .map(
              (entry) => _BrowserPlaceEntry(
                url: entry.url,
                title: entry.title,
                subtitle: entry.host,
                icon: Icons.history,
              ),
            )
            .toList(growable: false);

    final selected = await showDialog<_BrowserPlaceEntry>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return Dialog(
          insetPadding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                  child: Row(
                    children: [
                      Icon(
                        isBookmarks ? Icons.star : Icons.history,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isBookmarks ? 'Marcadores' : 'Recientes',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (entries.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      isBookmarks
                          ? 'Todavía no hay marcadores.'
                          : 'Todavía no hay páginas recientes.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: theme.dividerColor.withValues(alpha: 0.55),
                      ),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          leading: Icon(entry.icon),
                          title: Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            entry.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.of(dialogContext).pop(entry),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;
    final uri = _normalizeAddress(selected.url);
    if (uri != null) await _loadUri(uri);
  }

  Future<void> _confirmClearBrowserData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Limpiar datos del navegador'),
          content: const Text(
            'Esto borra cache, cookies e inicios de sesión del navegador interno. '
            'Tus marcadores y recientes se mantienen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Limpiar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await _clearBrowserData();
  }

  Future<void> _clearBrowserData() async {
    try {
      await InAppWebViewController.clearAllCache(includeDiskFiles: true);
      await CookieManager.instance().deleteAllCookies();
      await WebStorageManager.instance().deleteAllData();
      await _controller?.reload();
      _showBrowserSnack('Datos del navegador interno limpiados.');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser clear data skipped: $error');
      }
      _showBrowserSnack('No pude limpiar todos los datos del navegador.');
    }
  }

  Future<void> _handleDownloadStart(DownloadStartRequest request) async {
    final url = request.url.toString();
    if (_isDownloading) {
      _showBrowserSnack('Ya hay una descarga en curso.');
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      await _openExternalUrl(url);
      return;
    }

    final fileName = _downloadFileName(request);
    final mimeType = _cleanMimeType(request.mimeType) ??
        _mimeTypeFromFileName(fileName) ??
        'application/octet-stream';

    if (mounted) {
      setState(() => _isDownloading = true);
      _showBrowserSnack('Descargando $fileName...');
    }

    try {
      final bytes = await _downloadUrlBytes(uri, request);
      final supplierMatch = await AppFileStorageService.instance
          .matchSupplierForUrl(uri.toString());
      var savedInternally = false;
      var savedLocalCopy = false;

      try {
        await AppFileStorageService.instance.saveFile(
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
          context: AppFileContext(
            sourceType: 'browser_download',
            sourceId: supplierMatch?.id,
            sourceProvider: uri.host,
            sourceRoute: '/tools/web',
            contextType: supplierMatch == null ? 'browser' : 'supplier',
            contextId: supplierMatch?.id,
            contextTitle: supplierMatch?.name ??
                (_pageTitle?.trim().isNotEmpty == true
                    ? _pageTitle!.trim()
                    : uri.host),
            contextSubtitle:
                supplierMatch == null ? uri.toString() : 'Portal proveedor',
            tags: [
              'navegador',
              'descarga',
              if (supplierMatch != null) 'proveedor',
            ],
            metadata: {
              'url': uri.toString(),
              'current_page': _currentUrl,
              'content_disposition': request.contentDisposition,
              'suggested_filename': request.suggestedFilename,
              'reported_size_bytes': request.contentLength,
              if (supplierMatch != null) ...{
                'supplier_id': supplierMatch.id,
                'supplier_name': supplierMatch.name,
                'supplier_website': supplierMatch.website,
                'smart_folder': 'supplier:${supplierMatch.id}',
              },
            },
          ),
        );
        savedInternally = true;
      } catch (error) {
        if (kDebugMode) {
          debugPrint('🌐 Browser internal file save skipped: $error');
        }
      }

      try {
        await downloadFile(
          bytes: bytes,
          fileName: fileName,
          mimeType: mimeType,
        );
        savedLocalCopy = true;
      } catch (error) {
        if (kDebugMode) {
          debugPrint('🌐 Browser local file copy skipped: $error');
        }
      }

      if (!savedInternally && !savedLocalCopy) {
        throw StateError('Download bytes loaded but no save target succeeded.');
      }

      if (savedInternally && savedLocalCopy) {
        _showBrowserSnack('Descarga guardada en Archivos.');
      } else if (savedInternally) {
        _showBrowserSnack(
          'Descarga guardada en Archivos. No pude crear copia local.',
        );
      } else {
        _showBrowserSnack('Descarga guardada como copia local.');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser download fallback: $error');
      }
      _showBrowserSnack('No pude guardar esa descarga aquí; la abrí afuera.');
      await _openExternalUrl(url);
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  bool get _canOfferDocumentRelay {
    final sourceUrl = _documentRelaySourceUrl();
    return _documentRelayAvailable &&
        DocumentRelayService.isLikelyRelayCandidate(
          Uri.tryParse(sourceUrl),
        );
  }

  String _documentRelaySourceUrl() {
    final previewSource = _relayPreviewSourceUrl;
    if (previewSource != null && previewSource.trim().isNotEmpty) {
      return previewSource;
    }
    return _currentUrl.isNotEmpty ? _currentUrl : widget.url;
  }

  void _clearRelayPreviewState() {
    _relayPreviewSourceUrl = null;
    _relayDocumentPreview = null;
  }

  Future<void> _fetchCurrentDocumentThroughRelay({
    String? sourceUrlOverride,
  }) async {
    if (_isFetchingDocumentViaRelay) return;

    final sourceUrl = sourceUrlOverride ?? _documentRelaySourceUrl();
    final sourceUri = Uri.tryParse(sourceUrl);
    if (!DocumentRelayService.isLikelyRelayCandidate(sourceUri)) {
      _showBrowserSnack('Este enlace no parece ser un documento compatible.');
      return;
    }

    if (mounted) {
      setState(() {
        _isFetchingDocumentViaRelay = true;
        _lastErrorMessage = null;
      });
      _showBrowserSnack('Trayendo documento desde Chile...');
    }

    try {
      final result = await _documentRelayService.fetchDocument(sourceUrl);
      final supplierMatch = await AppFileStorageService.instance
          .matchSupplierForUrl(result.sourceUrl);
      var savedInternally = false;

      try {
        await AppFileStorageService.instance.saveFile(
          bytes: result.bytes,
          fileName: result.fileName,
          mimeType: result.mimeType,
          context: AppFileContext(
            sourceType: 'browser_document_relay',
            sourceId: supplierMatch?.id,
            sourceProvider: sourceUri?.host,
            sourceRoute: '/tools/web',
            contextType: supplierMatch == null ? 'browser' : 'supplier',
            contextId: supplierMatch?.id,
            contextTitle: supplierMatch?.name ?? 'Documento web',
            contextSubtitle:
                supplierMatch == null ? result.sourceUrl : 'Portal proveedor',
            tags: [
              'navegador',
              'documento',
              'relay-chile',
              if (supplierMatch != null) 'proveedor',
            ],
            metadata: {
              'url': result.sourceUrl,
              'relay': 'chile-document-relay',
              'remote_status_code': result.remoteStatusCode,
              if (supplierMatch != null) ...{
                'supplier_id': supplierMatch.id,
                'supplier_name': supplierMatch.name,
                'supplier_website': supplierMatch.website,
                'smart_folder': 'supplier:${supplierMatch.id}',
              },
            },
          ),
        );
        savedInternally = true;
      } catch (error) {
        if (kDebugMode) {
          debugPrint('🌐 Relay document internal save skipped: $error');
        }
      }

      final previewMime = _cleanMimeType(result.mimeType) ?? 'application/pdf';
      if (!_isPdfDocument(previewMime, result.fileName)) {
        await downloadFile(
          bytes: result.bytes,
          fileName: result.fileName,
          mimeType: result.mimeType,
        );
        if (mounted) {
          _showBrowserSnack('Documento guardado en Archivos.');
        }
        return;
      }

      if (mounted) {
        setState(() {
          _relayPreviewSourceUrl = result.sourceUrl;
          _relayDocumentPreview = _RelayDocumentPreview(
            bytes: result.bytes,
            fileName: result.fileName,
            sourceUrl: result.sourceUrl,
            savedInternally: savedInternally,
          );
          _relayPreviewZoom = 1.0;
          _currentUrl = result.sourceUrl;
          _pageTitle = result.fileName;
          _lastErrorMessage = null;
          _isLoading = false;
          _loadingProgress = 100;
        });
        _syncAddressField(result.sourceUrl);
        unawaited(
          _recordBrowserHistory(
            WebUri(result.sourceUrl),
            title: result.fileName,
          ),
        );
        _showBrowserSnack(
          savedInternally
              ? 'Documento abierto y guardado en Archivos.'
              : 'Documento abierto; no pude guardarlo en Archivos.',
        );
      }
    } on DocumentRelayNotConfiguredException {
      if (mounted) {
        const message =
            'El servicio chileno para rescatar este PDF todavia no esta activo.';
        setState(() {
          _documentRelayAvailable = false;
          _lastErrorMessage = message;
        });
        _showBrowserSnack(message);
      }
    } catch (error) {
      final message = _documentRelayErrorMessage(error);
      if (mounted) {
        setState(() => _lastErrorMessage = message);
        _showBrowserSnack(message);
      }
    } finally {
      if (mounted) setState(() => _isFetchingDocumentViaRelay = false);
    }
  }

  Future<void> _downloadRelayPreviewDocument(
    _RelayDocumentPreview preview,
  ) async {
    if (_isDownloading) {
      _showBrowserSnack('Ya hay una descarga en curso.');
      return;
    }

    if (mounted) setState(() => _isDownloading = true);
    try {
      await downloadFile(
        bytes: preview.bytes,
        fileName: preview.fileName,
        mimeType: 'application/pdf',
      );
      _showBrowserSnack('Documento descargado.');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Relay preview download skipped: $error');
      }
      _showBrowserSnack('No pude descargar el documento.');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _printRelayPreviewDocument(
    _RelayDocumentPreview preview,
  ) async {
    if (_isPrintingRelayPreview) return;

    if (mounted) setState(() => _isPrintingRelayPreview = true);
    try {
      final printed = await Printing.layoutPdf(
        name: preview.fileName,
        dynamicLayout: false,
        onLayout: (_) async => preview.bytes,
      );
      if (printed) {
        _showBrowserSnack('Documento enviado a impresión.');
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Relay preview print skipped: $error');
      }
      _showBrowserSnack('No pude imprimir el documento.');
    } finally {
      if (mounted) setState(() => _isPrintingRelayPreview = false);
    }
  }

  void _setRelayPreviewZoom(double zoom) {
    final nextZoom = zoom.clamp(0.65, 2.0).toDouble();
    if (!mounted) return;
    setState(() => _relayPreviewZoom = nextZoom);
  }

  void _resetRelayPreviewZoom() {
    if (!mounted) return;
    setState(() => _relayPreviewZoom = 1.0);
  }

  Future<Uint8List> _buildCurrentRelayPreviewPdf(PdfPageFormat _) async {
    return _relayDocumentPreview?.bytes ?? Uint8List(0);
  }

  Future<void> _recoverCurrentDocumentThroughRelay(String sourceUrl) async {
    if (_isFetchingDocumentViaRelay || _relayDocumentPreview != null) return;

    if (!_documentRelayAvailable) {
      await _loadDocumentRelayAvailability();
    }
    if (!mounted || !_documentRelayAvailable) return;

    await _fetchCurrentDocumentThroughRelay(sourceUrlOverride: sourceUrl);
  }

  String _documentRelayErrorMessage(Object error) {
    if (error is DocumentRelayException) {
      return error.message;
    }
    return 'No pude traer el documento desde Chile.';
  }

  Future<Uint8List> _downloadUrlBytes(
    Uri uri,
    DownloadStartRequest request,
  ) async {
    final headers = <String, String>{
      'User-Agent': request.userAgent?.trim().isNotEmpty == true
          ? request.userAgent!.trim()
          : _userAgent,
    };

    final cookieHeader = await _cookieHeaderFor(WebUri.uri(uri));
    if (cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }

    final response = await http.get(uri, headers: headers).timeout(
          _downloadTimeout,
        );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Download returned HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<String> _cookieHeaderFor(WebUri url) async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: url,
        webViewController: _controller,
      );
      return cookies
          .where((cookie) => cookie.name.trim().isNotEmpty)
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser download cookies skipped: $error');
      }
      return '';
    }
  }

  String _downloadFileName(DownloadStartRequest request) {
    final dispositionName =
        _fileNameFromContentDisposition(request.contentDisposition);
    final suggested = request.suggestedFilename?.trim();
    final urlPathName = _lastUrlPathSegment(request.url.toString());
    final rawName = dispositionName ??
        (suggested?.isNotEmpty == true ? suggested : null) ??
        urlPathName ??
        'descarga';

    final cleanName = rawName
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9._ -]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    return cleanName.isEmpty ? 'descarga' : cleanName;
  }

  String? _lastUrlPathSegment(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    for (final segment in uri.pathSegments.reversed) {
      if (segment.trim().isNotEmpty) return segment.trim();
    }
    return null;
  }

  String? _fileNameFromContentDisposition(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final utfMatch = RegExp(
      r'''filename\*=UTF-8''([^;]+)''',
      caseSensitive: false,
    ).firstMatch(value);
    if (utfMatch != null) {
      return Uri.decodeFull(utfMatch.group(1)!.replaceAll('"', '').trim());
    }
    final match = RegExp(
      r'''filename="?([^";]+)"?''',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1)?.trim();
  }

  String? _cleanMimeType(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.split(';').first.trim();
  }

  bool _isPdfDocument(String mimeType, String fileName) {
    return mimeType.toLowerCase().contains('pdf') ||
        fileName.toLowerCase().endsWith('.pdf');
  }

  String? _mimeTypeFromFileName(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'csv':
        return 'text/csv';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'zip':
        return 'application/zip';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return null;
    }
  }

  void _showBrowserSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<_BrowserAddressSuggestion> _addressSuggestions() {
    if (!_showAddressSuggestions) return const [];

    final query = _addressController.text.trim();
    final normalizedQuery = query.toLowerCase();
    final suggestions = <_BrowserAddressSuggestion>[];
    final seen = <String>{};

    void add(_BrowserAddressSuggestion suggestion) {
      final key = suggestion.value.toLowerCase();
      if (seen.add(key)) suggestions.add(suggestion);
    }

    if (query.isEmpty) {
      for (final entry in _historyEntries.take(8)) {
        add(_BrowserAddressSuggestion.history(entry));
      }
      return suggestions;
    }

    if (!_looksLikeDirectAddress(query)) {
      add(_BrowserAddressSuggestion.search(query));
      for (final suggestion in _searchSuggestions) {
        add(_BrowserAddressSuggestion.search(suggestion));
      }
    }

    final historyMatches = _historyEntries.where((entry) {
      return entry.title.toLowerCase().contains(normalizedQuery) ||
          entry.host.toLowerCase().contains(normalizedQuery) ||
          entry.url.toLowerCase().contains(normalizedQuery);
    });

    for (final entry in historyMatches.take(8)) {
      add(_BrowserAddressSuggestion.history(entry));
    }

    return suggestions.take(10).toList(growable: false);
  }

  Future<void> _openAddressSuggestion(
    _BrowserAddressSuggestion suggestion,
  ) async {
    _suggestionTimer?.cancel();
    _hideSuggestionsTimer?.cancel();
    FocusScope.of(context).unfocus();
    _hideAddressSuggestions();
    _addressController.text = suggestion.value;
    _addressController.selection = TextSelection.collapsed(
      offset: suggestion.value.length,
    );

    final uri = _normalizeAddress(suggestion.value);
    if (uri == null) {
      setState(() {
        _lastErrorMessage = 'No pude entender esa dirección web.';
      });
      return;
    }

    await _loadUri(uri);
  }

  void _clearAddressFocusFromPageInteraction() {
    if (!mounted) return;
    if (!_addressFocusNode.hasFocus && !_showAddressSuggestions) return;

    _addressFocusNode.unfocus();
    _hideAddressSuggestions();
  }

  Future<void> _installPageInteractionBridge(
    InAppWebViewController controller,
  ) async {
    try {
      await controller.evaluateJavascript(source: '''
(() => {
  if (window.__vinabikeBrowserPageInteractionBridge) return;
  window.__vinabikeBrowserPageInteractionBridge = true;

  let lastSentAt = 0;
  const notifyFlutter = () => {
    const now = Date.now();
    if (now - lastSentAt < 120) return;
    lastSentAt = now;
    if (!window.flutter_inappwebview ||
        !window.flutter_inappwebview.callHandler) {
      return;
    }
    window.flutter_inappwebview.callHandler('$_pageInteractionHandlerName');
  };

  document.addEventListener('pointerdown', notifyFlutter, true);
  document.addEventListener('mousedown', notifyFlutter, true);
  document.addEventListener('touchstart', notifyFlutter, true);
})();
''');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser page focus bridge skipped: $error');
      }
    }
  }

  void _setCurrentUrl(WebUri? url) {
    if (url == null) return;
    final value = url.toString();
    if (value.isEmpty) return;
    final displayValue =
        value.startsWith('data:') && _relayPreviewSourceUrl != null
            ? _relayPreviewSourceUrl!
            : value;
    setState(() {
      _currentUrl = displayValue;
    });
    _syncAddressField(displayValue);
  }

  Uri? _normalizeAddress(String input, {String? baseUrl}) {
    final value = input.trim();
    if (value.isEmpty) return null;

    if (value.startsWith('http://') || value.startsWith('https://')) {
      return Uri.tryParse(value);
    }

    if (baseUrl != null && value.startsWith('/')) {
      final base = Uri.tryParse(baseUrl);
      return base?.resolve(value);
    }

    if (value.contains('://')) {
      return Uri.tryParse(value);
    }

    final isLocalHost = value.startsWith('localhost') ||
        value.startsWith('127.0.0.1') ||
        value.startsWith('[::1]');
    if (isLocalHost) {
      return Uri.tryParse('http://$value');
    }

    final looksLikeSearch = value.contains(' ') || !value.contains('.');
    if (looksLikeSearch) {
      return Uri.https('www.google.com', '/search', {'q': value});
    }

    return Uri.tryParse('https://$value');
  }

  bool _canLoadInsideWebView(Uri uri) {
    if (!uri.hasScheme) return true;
    return uri.scheme == 'http' ||
        uri.scheme == 'https' ||
        uri.scheme == 'about' ||
        uri.scheme == 'data' ||
        uri.scheme == 'file' ||
        uri.scheme == 'blob' ||
        uri.scheme == 'javascript' ||
        uri.scheme == 'chrome';
  }

  bool _isBenignNavigationError(WebResourceError error) {
    final description = error.description.toLowerCase();
    return description.contains('nsurlerrordomain error -999') ||
        description.contains('error -999') ||
        (description.contains('webkiterrordomain') &&
            description.contains('code=102') &&
            description.contains('frame load interrupted')) ||
        (description.contains('frame load interrupted') && _isDownloading);
  }

  Future<NavigationActionPolicy> _handleNavigation(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    final url = navigationAction.request.url;
    if (url != null && await _tryOpenDocumentThroughRelay(url.toString())) {
      return NavigationActionPolicy.CANCEL;
    }

    if (url == null || _canLoadInsideWebView(url)) {
      return NavigationActionPolicy.ALLOW;
    }

    await _openExternalUrl(url.toString());
    return NavigationActionPolicy.CANCEL;
  }

  Future<bool> _handleCreateWindow(
    InAppWebViewController controller,
    CreateWindowAction createWindowAction,
  ) async {
    final url = createWindowAction.request.url;
    if (url == null) return false;

    if (_canLoadInsideWebView(url)) {
      await controller.loadUrl(urlRequest: createWindowAction.request);
    } else {
      await _openExternalUrl(url.toString());
    }

    return false;
  }

  String _displayHost() {
    if (_currentUrl.isEmpty) return '';

    try {
      final uri = Uri.parse(_currentUrl);
      return uri.host.isNotEmpty ? uri.host : _currentUrl;
    } catch (_) {
      return _currentUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (!_usesNativeBrowser) {
      return _buildFallbackView(context);
    }

    if (_isInitializing) {
      return _buildLoadingPlaceholder(context, 'Inicializando navegador...');
    }

    if (_platformMessage != null) {
      final needsRuntime =
          _platformMessage?.contains('WebView2 Runtime') == true;
      return _buildFallbackView(
        context,
        message: _platformMessage,
        actionLabel:
            needsRuntime ? 'Instalar WebView2 Runtime' : 'Abrir en Navegador',
        actionUrl: needsRuntime ? _windowsRuntimeUrl : widget.url,
      );
    }

    final initialUri = _nativeInitialUri ?? _initialUri;
    if (initialUri == null) {
      return _buildFallbackView(
        context,
        message: 'La URL inicial no es válida.',
        actionLabel: 'Abrir en Navegador',
        actionUrl: widget.url,
      );
    }

    final browserZoom = _browserZoom(context);
    _scheduleBrowserZoom(browserZoom);

    final webViewContent = KeyedSubtree(
      key: _browserViewportKey,
      child: _buildPageInteractionFocusBridge(
        child: _buildWindowsTrackpadScrollBridge(
          child: _NativeBrowserZoomBoundary(
            appScale: browserZoom,
            child: InAppWebView(
              key: ValueKey('browser-${widget.url}'),
              webViewEnvironment: _webViewEnvironment,
              initialUrlRequest: _urlRequest(initialUri),
              initialSettings: _browserSettings(browserZoom),
              onWebViewCreated: (controller) {
                _controller = controller;
                controller.addJavaScriptHandler(
                  handlerName: _pageInteractionHandlerName,
                  callback: (_) {
                    _clearAddressFocusFromPageInteraction();
                    return null;
                  },
                );
                unawaited(_installPageInteractionBridge(controller));
                unawaited(_applyBrowserZoom(browserZoom));
                unawaited(_refreshNavigationState());
              },
              onLoadStart: (controller, url) {
                if (!mounted) return;
                final loadingUrl = url?.toString() ?? '';
                setState(() {
                  _isLoading = true;
                  _loadingProgress = 0;
                  _lastErrorMessage = null;
                  if (!loadingUrl.startsWith('data:')) {
                    _relayPreviewSourceUrl = null;
                    _relayDocumentPreview = null;
                  }
                });
                _setCurrentUrl(url);
              },
              onLoadStop: (controller, url) async {
                if (!mounted) return;
                setState(() {
                  _isLoading = false;
                  _loadingProgress = 100;
                });
                _setCurrentUrl(url);
                _pageTitle = await controller.getTitle();
                unawaited(_recordBrowserHistory(url, title: _pageTitle));
                if (mounted) setState(() {});
                unawaited(_installPageInteractionBridge(controller));
                unawaited(_applyBrowserZoom(browserZoom));
                unawaited(_refreshNavigationState());
              },
              onProgressChanged: (controller, progress) {
                if (!mounted) return;
                setState(() {
                  _loadingProgress = progress;
                  _isLoading = progress < 100;
                });
              },
              onTitleChanged: (controller, title) {
                if (!mounted) return;
                setState(() {
                  _pageTitle = title;
                });
              },
              onUpdateVisitedHistory: (controller, url, isReload) {
                if (!mounted) return;
                _setCurrentUrl(url);
                unawaited(_refreshNavigationState());
              },
              onReceivedError: (controller, request, error) {
                if (!mounted || request.isForMainFrame == false) return;
                final failedUrl = request.url.toString();
                final canRecoverThroughRelay =
                    DocumentRelayService.isLikelyRelayCandidate(
                  Uri.tryParse(failedUrl),
                );
                if (_isBenignNavigationError(error)) {
                  if (kDebugMode) {
                    debugPrint(
                      '🌐 Web workspace ignored cancelled navigation: '
                      '${error.description}',
                    );
                  }
                  return;
                }
                setState(() {
                  _lastErrorMessage = error.description;
                  _isLoading = false;
                });
                if (canRecoverThroughRelay) {
                  unawaited(_recoverCurrentDocumentThroughRelay(failedUrl));
                }
              },
              onPermissionRequest: (controller, request) async {
                return PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                );
              },
              shouldOverrideUrlLoading: _handleNavigation,
              onCreateWindow: _handleCreateWindow,
              onDownloadStartRequest: (controller, request) {
                unawaited(_handleDownloadStart(request));
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint('🌐 Web workspace: ${consoleMessage.message}');
              },
            ),
          ),
        ),
      ),
    );

    final relayPreview = _relayDocumentPreview;
    return _buildEmbeddedView(
      context,
      child: Stack(
        children: [
          Positioned.fill(child: webViewContent),
          if (_isFetchingDocumentViaRelay && relayPreview == null)
            Positioned.fill(child: _buildRelayLoadingOverlay(context)),
          if (relayPreview != null)
            Positioned.fill(
              child: _buildRelayDocumentPreview(context, relayPreview),
            ),
        ],
      ),
    );
  }

  Widget _buildPageInteractionFocusBridge({required Widget child}) {
    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: (_) => _clearAddressFocusFromPageInteraction(),
      child: child,
    );
  }

  Widget _buildRelayLoadingOverlay(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  'Trayendo documento desde Chile...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRelayDocumentPreview(
    BuildContext context,
    _RelayDocumentPreview preview,
  ) {
    final theme = Theme.of(context);
    final sourceHost =
        Uri.tryParse(preview.sourceUrl)?.host.trim().isNotEmpty == true
            ? Uri.parse(preview.sourceUrl).host
            : preview.sourceUrl;

    return ColoredBox(
      color: const Color(0xFFE5E7EB),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.picture_as_pdf_outlined,
                      size: 19,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          preview.fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sourceHost,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (preview.savedInternally)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(
                        'Archivos',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF1D4ED8),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Alejar',
                    onPressed: _relayPreviewZoom <= 0.65
                        ? null
                        : () => _setRelayPreviewZoom(_relayPreviewZoom - 0.15),
                    icon: const Icon(Icons.zoom_out_outlined, size: 18),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(_relayPreviewZoom * 100).round()}%',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Acercar',
                    onPressed: _relayPreviewZoom >= 2.0
                        ? null
                        : () => _setRelayPreviewZoom(_relayPreviewZoom + 0.15),
                    icon: const Icon(Icons.zoom_in_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Ajustar',
                    onPressed: (_relayPreviewZoom - 1.0).abs() < 0.01
                        ? null
                        : _resetRelayPreviewZoom,
                    icon: const Icon(Icons.fit_screen_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Imprimir',
                    onPressed: _isPrintingRelayPreview
                        ? null
                        : () => _printRelayPreviewDocument(preview),
                    icon: _isPrintingRelayPreview
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Descargar',
                    onPressed: _isDownloading
                        ? null
                        : () => _downloadRelayPreviewDocument(preview),
                    icon: _isDownloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Recargar documento',
                    onPressed: _isFetchingDocumentViaRelay
                        ? null
                        : _fetchCurrentDocumentThroughRelay,
                    icon: _isFetchingDocumentViaRelay
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Abrir afuera',
                    onPressed: _openCurrentExternal,
                    icon: const Icon(Icons.open_in_new_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Cerrar vista previa',
                    onPressed: () {
                      setState(_clearRelayPreviewState);
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: PdfPreview.builder(
              key: ValueKey(preview.sourceUrl),
              build: _buildCurrentRelayPreviewPdf,
              pagesBuilder: _buildRelayPdfPages,
              useActions: false,
              allowPrinting: false,
              allowSharing: false,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              maxPageWidth: 1600,
              pdfFileName: preview.fileName,
              scrollViewDecoration: const BoxDecoration(
                color: Color(0xFFE5E7EB),
              ),
              loadingWidget: const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelayPdfPages(
    BuildContext context,
    List<PdfPreviewPageData> pages,
  ) {
    if (pages.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final baseWidth = (availableWidth - 96).clamp(560.0, 1080.0);
        final pageWidth = (baseWidth * _relayPreviewZoom).clamp(360.0, 1900.0);
        final contentWidth = math.max(availableWidth, pageWidth + 72);

        return ColoredBox(
          color: const Color(0xFFE5E7EB),
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final page in pages)
                        _RelayPreviewPage(
                          page: page,
                          width: pageWidth,
                          shadowColor: theme.shadowColor,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWindowsTrackpadScrollBridge({required Widget child}) {
    if (defaultTargetPlatform != TargetPlatform.windows || kIsWeb) {
      return child;
    }

    return Listener(
      behavior: HitTestBehavior.deferToChild,
      onPointerPanZoomUpdate: _queueWindowsTrackpadScroll,
      child: child,
    );
  }

  void _queueWindowsTrackpadScroll(PointerPanZoomUpdateEvent event) {
    if (_controller == null) return;

    // Pinch gestures arrive through the same pan/zoom channel. Let WebView2
    // handle those natively and only smooth two-finger scroll deltas here.
    if ((event.scale - 1).abs() > 0.001 || event.rotation.abs() > 0.001) {
      return;
    }

    final panDelta = event.localPanDelta;
    if (panDelta == Offset.zero) return;

    _lastWindowsTrackpadPosition = event.localPosition;
    _pendingWindowsTrackpadScroll += Offset(-panDelta.dx, -panDelta.dy);
    _windowsTrackpadScrollTimer ??= Timer(
      const Duration(milliseconds: 16),
      _flushWindowsTrackpadScroll,
    );
  }

  void _flushWindowsTrackpadScroll() {
    _windowsTrackpadScrollTimer = null;

    final delta = _pendingWindowsTrackpadScroll;
    final position = _lastWindowsTrackpadPosition;
    _pendingWindowsTrackpadScroll = Offset.zero;

    if (delta.distanceSquared < 0.01) return;
    unawaited(_applyWindowsTrackpadScroll(delta, position));
  }

  Future<void> _applyWindowsTrackpadScroll(
    Offset delta,
    Offset? position,
  ) async {
    final controller = _controller;
    if (controller == null) return;

    final dx = _jsNumber(_clampTrackpadDelta(delta.dx));
    final dy = _jsNumber(_clampTrackpadDelta(delta.dy));
    final x = _jsNumber(position?.dx ?? 0);
    final y = _jsNumber(position?.dy ?? 0);

    try {
      await controller.evaluateJavascript(source: '''
(() => {
  const dx = $dx;
  const dy = $dy;
  const x = $x;
  const y = $y;
  const overflowAllowsScroll = (value) =>
    value === 'auto' || value === 'scroll' || value === 'overlay';

  let element = document.elementFromPoint(x, y);
  while (element && element !== document.body &&
      element !== document.documentElement) {
    const style = window.getComputedStyle(element);
    const canScrollY = dy !== 0 &&
      element.scrollHeight > element.clientHeight &&
      overflowAllowsScroll(style.overflowY);
    const canScrollX = dx !== 0 &&
      element.scrollWidth > element.clientWidth &&
      overflowAllowsScroll(style.overflowX);

    if (canScrollX || canScrollY) {
      const beforeLeft = element.scrollLeft;
      const beforeTop = element.scrollTop;
      element.scrollBy({
        left: canScrollX ? dx : 0,
        top: canScrollY ? dy : 0,
        behavior: 'auto',
      });

      if (element.scrollLeft !== beforeLeft ||
          element.scrollTop !== beforeTop) {
        return;
      }
    }

    element = element.parentElement;
  }

  window.scrollBy({left: dx, top: dy, behavior: 'auto'});
})();
''');
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Web workspace trackpad scroll sync skipped: $error');
      }
    }
  }

  double _clampTrackpadDelta(double value) {
    if (!value.isFinite) return 0;
    return value.clamp(-240.0, 240.0).toDouble();
  }

  String _jsNumber(double value) {
    if (!value.isFinite) return '0';
    return value.toStringAsFixed(2);
  }

  Widget _buildEmbeddedView(
    BuildContext context, {
    required Widget child,
  }) {
    return Column(
      children: [
        _buildTopBar(context),
        _buildErrorBannerSlot(context),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildErrorBannerSlot(BuildContext context) {
    if (_lastErrorMessage == null) return const SizedBox.shrink();
    return _buildErrorBanner(context);
  }

  Widget _buildLoadingPlaceholder(BuildContext context, String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: widget.iconColor ?? Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackView(
    BuildContext context, {
    String? message,
    String actionLabel = 'Abrir en Nueva Pestaña',
    String? actionUrl,
  }) {
    final unsupportedPlatformLabel = kIsWeb
        ? 'la versión web'
        : defaultTargetPlatform == TargetPlatform.linux
            ? 'Linux'
            : 'esta plataforma';

    final effectiveActionUrl = actionUrl ?? widget.url;
    final effectiveMessage = message ??
        'El navegador embebido avanzado no está disponible en $unsupportedPlatformLabel.';

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(32),
        child: Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 64,
                  color: widget.iconColor ?? Theme.of(context).primaryColor,
                ),
                const SizedBox(height: 24),
                Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  effectiveMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'En macOS, Windows, Android e iOS usamos un WebView nativo avanzado. Si un sitio bloquea navegación embebida, puedes abrirlo afuera desde aquí.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(effectiveActionUrl);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: Text(actionLabel),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  effectiveActionUrl,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    final theme = Theme.of(context);
    final canOfferRelay = _canOfferDocumentRelay;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.18),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _lastErrorMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (canOfferRelay)
            TextButton.icon(
              onPressed: _isFetchingDocumentViaRelay
                  ? null
                  : _fetchCurrentDocumentThroughRelay,
              icon: _isFetchingDocumentViaRelay
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined, size: 16),
              label: Text(
                _isFetchingDocumentViaRelay
                    ? 'Trayendo...'
                    : 'Traer desde Chile',
              ),
            ),
          TextButton.icon(
            onPressed: _openCurrentExternal,
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Abrir afuera'),
          ),
          IconButton(
            tooltip: 'Ocultar aviso',
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => setState(() => _lastErrorMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final canUseWebView = _controller != null;
    final progressValue = _loadingProgress <= 0
        ? null
        : (_loadingProgress / 100).clamp(0.0, 1.0).toDouble();
    final addressSuggestions = _addressSuggestions();
    final isBookmarked = _isCurrentBookmarked;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Tooltip(
                  message: _pageTitle ?? widget.title,
                  child: Icon(
                    widget.icon,
                    color: widget.iconColor ?? theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: _canGoBack ? _goBack : null,
                  tooltip: 'Atrás',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  onPressed: _canGoForward ? _goForward : null,
                  tooltip: 'Adelante',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: canUseWebView ? _reload : null,
                  tooltip: 'Recargar',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.home_outlined, size: 20),
                  onPressed: canUseWebView ? _goHome : null,
                  tooltip: 'Inicio',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _addressController,
                      focusNode: _addressFocusNode,
                      enabled: canUseWebView,
                      textInputAction: TextInputAction.go,
                      keyboardType: TextInputType.url,
                      onSubmitted: _loadAddress,
                      style: theme.textTheme.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        prefixIcon: Icon(
                          Icons.language,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        suffixIcon: _isLoading
                            ? Padding(
                                padding: const EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    value: progressValue,
                                  ),
                                ),
                              )
                            : IconButton(
                                tooltip: 'Ir',
                                icon: const Icon(Icons.arrow_forward, size: 18),
                                onPressed: canUseWebView
                                    ? () => _loadAddress(
                                          _addressController.text,
                                        )
                                    : null,
                              ),
                        hintText: 'Buscar o escribir URL',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: theme.dividerColor,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: theme.dividerColor,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 1.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    isBookmarked ? Icons.star : Icons.star_border,
                    size: 20,
                  ),
                  color: isBookmarked
                      ? Colors.amber.shade700
                      : theme.colorScheme.onSurfaceVariant,
                  onPressed: canUseWebView ? _toggleCurrentBookmark : null,
                  tooltip:
                      isBookmarked ? 'Quitar marcador' : 'Guardar marcador',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
                PopupMenuButton<_BrowserMenuAction>(
                  enabled: canUseWebView,
                  tooltip: 'Opciones del navegador',
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (action) {
                    unawaited(_handleBrowserMenuAction(action));
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _BrowserMenuAction.recent,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.history),
                        title: Text('Recientes'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _BrowserMenuAction.bookmarks,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.star_border),
                        title: Text('Marcadores'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _BrowserMenuAction.clearData,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.cleaning_services_outlined),
                        title: Text('Limpiar datos'),
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: _BrowserMenuAction.openInChrome,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.person_outline),
                        title: Text('Abrir en Chrome'),
                      ),
                    ),
                    PopupMenuItem(
                      value: _BrowserMenuAction.openExternal,
                      child: ListTile(
                        dense: true,
                        leading: Icon(Icons.open_in_new),
                        title: Text('Abrir afuera'),
                      ),
                    ),
                  ],
                ),
                Tooltip(
                  message: _displayHost().isEmpty
                      ? 'Abrir en navegador externo'
                      : _displayHost(),
                  child: IconButton(
                    icon: const Icon(Icons.open_in_new, size: 20),
                    onPressed: canUseWebView ? _openCurrentExternal : null,
                    tooltip: 'Abrir en navegador externo',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (addressSuggestions.isNotEmpty)
            _buildAddressSuggestions(context, addressSuggestions),
          if (_isLoading)
            LinearProgressIndicator(
              value: progressValue,
              minHeight: 2,
              color: widget.iconColor ?? theme.colorScheme.primary,
              backgroundColor: Colors.transparent,
            ),
        ],
      ),
    );
  }

  Widget _buildAddressSuggestions(
    BuildContext context,
    List<_BrowserAddressSuggestion> suggestions,
  ) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          final suggestion = suggestions[index];
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => unawaited(_openAddressSuggestion(suggestion)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Icon(
                          suggestion.icon,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              suggestion.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (suggestion.subtitle.isNotEmpty)
                              Text(
                                suggestion.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (suggestion.badge != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, right: 8),
                          child: Text(
                            suggestion.badge!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else if (_isFetchingSuggestions && index == 0)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BrowserHistoryEntry {
  const _BrowserHistoryEntry({
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  final String url;
  final String title;
  final DateTime visitedAt;

  String get host {
    final uri = Uri.tryParse(url);
    return uri?.host.isNotEmpty == true ? uri!.host : url;
  }

  String encode() => jsonEncode({
        'url': url,
        'title': title,
        'visitedAt': visitedAt.toIso8601String(),
      });

  static _BrowserHistoryEntry? tryDecode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return null;
      final url = decoded['url'];
      if (url is! String || url.trim().isEmpty) return null;
      final title = decoded['title'];
      final visitedAt = DateTime.tryParse('${decoded['visitedAt']}');
      return _BrowserHistoryEntry(
        url: url,
        title: title is String && title.trim().isNotEmpty ? title : url,
        visitedAt: visitedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }
}

class _BrowserBookmarkEntry {
  const _BrowserBookmarkEntry({
    required this.url,
    required this.title,
    required this.savedAt,
  });

  final String url;
  final String title;
  final DateTime savedAt;

  String get host {
    final uri = Uri.tryParse(url);
    return uri?.host.isNotEmpty == true ? uri!.host : url;
  }

  String encode() => jsonEncode({
        'url': url,
        'title': title,
        'savedAt': savedAt.toIso8601String(),
      });

  static _BrowserBookmarkEntry? tryDecode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return null;
      final url = decoded['url'];
      if (url is! String || url.trim().isEmpty) return null;
      final title = decoded['title'];
      final savedAt = DateTime.tryParse('${decoded['savedAt']}');
      return _BrowserBookmarkEntry(
        url: url,
        title: title is String && title.trim().isNotEmpty ? title : url,
        savedAt: savedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }
}

class _RelayDocumentPreview {
  const _RelayDocumentPreview({
    required this.bytes,
    required this.fileName,
    required this.sourceUrl,
    required this.savedInternally,
  });

  final Uint8List bytes;
  final String fileName;
  final String sourceUrl;
  final bool savedInternally;
}

class _RelayPreviewPage extends StatelessWidget {
  const _RelayPreviewPage({
    required this.page,
    required this.width,
    required this.shadowColor,
  });

  final PdfPreviewPageData page;
  final double width;
  final Color shadowColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD1D5DB)),
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: page.aspectRatio,
        child: Image(
          image: page.image,
          fit: BoxFit.fill,
        ),
      ),
    );
  }
}

class _BrowserPlaceEntry {
  const _BrowserPlaceEntry({
    required this.url,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String url;
  final String title;
  final String subtitle;
  final IconData icon;
}

enum _BrowserLibraryKind { recent, bookmarks }

enum _BrowserMenuAction {
  recent,
  bookmarks,
  clearData,
  openInChrome,
  openExternal,
}

class _BrowserAddressSuggestion {
  const _BrowserAddressSuggestion._({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.icon,
    this.badge,
  });

  final String label;
  final String subtitle;
  final String value;
  final IconData icon;
  final String? badge;

  factory _BrowserAddressSuggestion.search(String query) {
    return _BrowserAddressSuggestion._(
      label: query,
      subtitle: 'Buscar en Google',
      value: query,
      icon: Icons.search,
      badge: 'Google',
    );
  }

  factory _BrowserAddressSuggestion.history(_BrowserHistoryEntry entry) {
    return _BrowserAddressSuggestion._(
      label: entry.title,
      subtitle: entry.host,
      value: entry.url,
      icon: Icons.history,
    );
  }
}

class _NativeBrowserZoomBoundary extends StatelessWidget {
  const _NativeBrowserZoomBoundary({
    required this.appScale,
    required this.child,
  });

  final double appScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!WindowZoomService.isDesktop || (appScale - 1.0).abs() < 0.001) {
      return child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
          return child;
        }

        final nativeWidth = constraints.maxWidth * appScale;
        final nativeHeight = constraints.maxHeight * appScale;

        return ClipRect(
          child: SizedBox.expand(
            child: Align(
              alignment: Alignment.topLeft,
              child: Transform.scale(
                scale: 1 / appScale,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: nativeWidth,
                  height: nativeHeight,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
