import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey, rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../modules/purchases/services/purchase_service.dart';
import '../../modules/storage/models/app_stored_file.dart';
import '../../modules/storage/services/app_file_storage_service.dart';
import '../services/auth_service.dart';
import '../services/aliexpress_daily_invoice_service.dart';
import '../services/aliexpress_pending_days_service.dart';
import '../services/browser_credential_vault.dart';
import '../services/browser_profile_service.dart';
import '../services/browser_site_memory_service.dart';
import '../services/browser_supplier_credential_resolver.dart';
import '../services/browser_supplier_portal_catalog.dart';
import '../services/document_relay_service.dart';
import '../services/ocr_file_handoff_service.dart';
import '../services/smart_screenshot_service.dart';
import '../services/window_zoom_service.dart';
import '../services/workspace_manager.dart';
import '../utils/browser_omnibox.dart';
import '../utils/responsive_viewport.dart';
import '../utils/browser_credential_autofill.dart';
import '../utils/file_download.dart';
import 'vb_notice.dart';

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
  static const _windowsRuntimeUrl =
      'https://developer.microsoft.com/en-us/microsoft-edge/webview2/';
  static const _historyPrefsKey = 'vinabike_browser_history_v1';
  static const _bookmarkPrefsKey = 'vinabike_browser_bookmarks_v1';
  static const _permissionPrefsKey = 'vinabike_browser_permissions_v1';
  static const _pageInteractionHandlerName = 'VinabikeBrowserPageInteraction';
  static const _maxHistoryEntries = 120;
  static const _maxBookmarkEntries = 80;
  static final Map<String, Future<void>> _historyWriteTails = {};
  static const _suggestionDelay = Duration(milliseconds: 180);
  static const _suggestionTimeout = Duration(milliseconds: 1200);
  static const _downloadTimeout = Duration(seconds: 45);
  static final _credentialAutofillUserScripts =
      UnmodifiableListView<UserScript>([
    UserScript(
      groupName: 'VinabikeCredentialCapture',
      source: browserCredentialCaptureUserScript,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
      forMainFrameOnly: true,
    ),
  ]);

  InAppWebViewController? _controller;
  WebViewEnvironment? _webViewEnvironment;
  final GlobalKey _browserViewportKey =
      GlobalKey(debugLabel: 'browser viewport');
  final DocumentRelayService _documentRelayService = DocumentRelayService();
  final BrowserCredentialVault _credentialVault =
      BrowserCredentialVault.instance;
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();
  bool _didSelectAddressForFocus = false;
  TextEditingValue _lastAddressEditingValue = TextEditingValue.empty;
  String? _inlineCompletionQuery;
  TextRange? _inlineCompletionRange;
  String? _inlineCompletionNavigationUrl;
  bool _isApplyingInlineCompletion = false;

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
  List<BrowserSiteMemoryEntry> _siteEntries = const [];
  List<BrowserSupplierPortalEntry> _supplierPortalEntries = const [];
  List<_BrowserBookmarkEntry> _bookmarkEntries = const [];
  List<String> _searchSuggestions = const [];
  String _activeSuggestionQuery = '';
  bool _isFetchingSuggestions = false;
  bool _showAddressSuggestions = false;
  int? _highlightedSuggestionIndex;
  bool _transientMenuOpen = false;
  List<_BrowserAddressSuggestion> _visibleSuggestions = const [];
  bool _showFavoritesBar = true;
  static const _favoritesBarPrefsKey = 'vinabike_browser_favorites_bar_v1';
  final Set<String> _automaticCredentialSubmitAttempts = {};
  final Set<String> _credentialAutofillInFlight = {};
  final Set<String> _credentialSavedFeedbackOrigins = {};
  final Set<String> _insecureCredentialFeedbackOrigins = {};
  String? _registeredScreenshotWorkspaceId;
  late final String _browserProfileIdentity;
  Completer<void>? _aliExpressNavigationCompleter;
  String? _aliExpressBridgeSource;
  bool _isAliExpressImportRunning = false;
  final Map<String, String> _aliExpressInvoiceImageDataCache = {};

  @override
  bool get wantKeepAlive => true;

  bool get _usesNativeBrowser {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
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
        // Sin esto, WKWebView se presenta con el user agent genérico de app
        // embebida («…AppleWebKit/605.1.15 (KHTML, like Gecko)», sin sufijo
        // Safari) y Google/YouTube/muchos sitios sirven su página de respaldo
        // de HTML básico — el «look 1999». Verificado con la sonda de
        // onLoadStop el 2026-08-05: `applicationNameForUserAgent` NO se
        // aplica en la implementación macOS del plugin, así que va el UA
        // completo, calcado del default real de WKWebView + el sufijo
        // Safari. El token AppleWebKit/605.1.15 lleva años congelado por
        // Apple, por lo que fijarlo no envejece en la práctica. Android no lo
        // necesita: su UA por defecto ya declara Chrome. iOS se deja por
        // defecto a propósito: un UA de escritorio forzaría sitios desktop en
        // un teléfono.
        userAgent: defaultTargetPlatform == TargetPlatform.macOS
            ? 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                'AppleWebKit/605.1.15 (KHTML, like Gecko) '
                'Version/18.5 Safari/605.1.15'
            : null,
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
        saveFormData: true,
        sharedCookiesEnabled: true,
        thirdPartyCookiesEnabled: true,
        textZoom: (browserZoom * 100).round(),
        transparentBackground: false,
        useHybridComposition: true,
        useOnDownloadStart: true,
        useWideViewPort: true,
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
    _browserProfileIdentity =
        context.read<AuthService>().currentUser?.id ?? 'anonymous';
    _lastAddressEditingValue = _addressController.value;
    _addressController.addListener(_handleAddressTextChanged);
    _addressFocusNode.addListener(_handleAddressFocusChanged);
    unawaited(_loadBrowserHistory());
    unawaited(_loadSupplierPortalCatalog());
    unawaited(_loadBrowserBookmarks());
    unawaited(_loadDocumentRelayAvailability());
    unawaited(_prepareBrowser());
    unawaited(_restoreAliExpressOrderDates());
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
    final navigationCompleter = _aliExpressNavigationCompleter;
    if (navigationCompleter != null && !navigationCompleter.isCompleted) {
      navigationCompleter.complete();
    }
    _addressController.removeListener(_handleAddressTextChanged);
    _addressFocusNode.removeListener(_handleAddressFocusChanged);
    _addressController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  String _profilePrefsKey(String baseKey) =>
      '$baseKey::$_browserProfileIdentity';

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

  void _publishBrowserWorkspaceState({
    required String url,
    String? title,
  }) {
    final workspaceId = _registeredScreenshotWorkspaceId;
    if (workspaceId == null || !mounted) return;
    try {
      context.read<WorkspaceManager>().updateBrowserWorkspaceState(
            workspaceId,
            url: url,
            title: title,
          );
    } catch (_) {
      // The workspace provider can disappear during app shutdown.
    }
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
    final bottomRight = box.localToGlobal(
      Offset(box.size.width, box.size.height),
    );
    return Rect.fromPoints(topLeft, bottomRight);
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
        _webViewEnvironment = await BrowserProfileService.environmentForUser(
          _browserProfileIdentity,
        );
        if (_webViewEnvironment == null) {
          _finishInitialization(
            message:
                'Microsoft Edge WebView2 Runtime no está instalado en este equipo.',
            loading: false,
          );
          return;
        }
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
    final inlineNavigationUrl = _inlineCompletionQuery != null &&
            _inlineCompletionNavigationUrl != null &&
            input.trim() == _addressController.text.trim()
        ? _inlineCompletionNavigationUrl
        : null;
    _clearInlineAddressCompletion();
    _hideAddressSuggestions();

    final uri = _normalizeAddress(inlineNavigationUrl ?? input);
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

  bool get _isAliExpressPage => AliExpressDailyInvoiceService.isTrustedUri(
        Uri.tryParse(_currentUrl),
      );

  /// Días en los que esta cuenta tiene pedidos, aprendidos de la última
  /// consulta a la API. Alimentan la marca del calendario para no elegir a
  /// ciegas un día sin compras.
  final Set<String> _aliExpressOrderDates = <String>{};

  /// Días de compra que ya tienen factura emitida en el ERP.
  final Set<String> _aliExpressInvoicedDates = <String>{};

  void _rememberAliExpressOrderDates(Iterable<String> dates) {
    final added = _aliExpressOrderDates.addAll.call;
    added(dates.where((date) => date.trim().isNotEmpty));
    if (mounted) setState(() {});
    unawaited(_persistAliExpressOrderDates());
    unawaited(_refreshAliExpressInvoicedDates());
  }

  /// Marca qué días ya fueron facturados, contrastando el índice de compras
  /// con las facturas del ERP. Es lo que convierte «hubo compras ese día» en
  /// la información accionable: «esta compra todavía no está registrada».
  Future<void> _refreshAliExpressInvoicedDates() async {
    if (!mounted || _aliExpressOrderDates.isEmpty) return;
    try {
      final purchaseService = context.read<PurchaseService>();
      final invoiced = <String>{};
      for (final day in _aliExpressOrderDates) {
        final date = DateTime.tryParse(day);
        if (date == null) continue;
        final number = AliExpressPendingDaysService.invoiceNumberForDate(date);
        if (await purchaseService.checkInvoiceNumberExists(number) != null) {
          invoiced.add(day);
        }
      }
      if (!mounted) return;
      setState(() {
        _aliExpressInvoicedDates
          ..clear()
          ..addAll(invoiced);
      });
      _announceAliExpressPendingDays();
    } catch (error) {
      // Es una pista de conveniencia: si no se puede resolver, el diálogo
      // simplemente no afirma nada sobre facturas ya emitidas.
      debugPrint('⚠️ [AliExpress] No se pudo revisar facturas del día: $error');
    }
  }

  static const _aliExpressOrderDatesPrefsKey = 'browser.aliexpress.orderDates';

  Future<void> _persistAliExpressOrderDates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Sólo los días recientes: el calendario mira meses, no años.
      final recent = _aliExpressOrderDates.toList()..sort();
      await prefs.setStringList(
        _profilePrefsKey(_aliExpressOrderDatesPrefsKey),
        recent.length > 400 ? recent.sublist(recent.length - 400) : recent,
      );
    } catch (_) {
      // Un caché de conveniencia que no se pudo guardar no rompe el flujo.
    }
  }

  Future<void> _restoreAliExpressOrderDates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored =
          prefs.getStringList(_profilePrefsKey(_aliExpressOrderDatesPrefsKey));
      if (stored == null || stored.isEmpty || !mounted) return;
      setState(() => _aliExpressOrderDates.addAll(stored));
      // Los días restaurados también necesitan saberse facturados o no: sin
      // esto, un día ya registrado reaparecía como pendiente tras reiniciar.
      unawaited(_refreshAliExpressInvoicedDates());
    } catch (_) {
      // Idem: es caché, no verdad.
    }
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Días ya anunciados, para no repetir el aviso en cada consulta.
  static final Set<String> _announcedAliExpressPendingDays = <String>{};

  /// Avisa cuando hay compras sin factura, incluidas las hechas fuera del ERP.
  ///
  /// El aviso nace del contraste entre la cuenta del proveedor y las facturas
  /// del ERP, así que cubre la compra hecha desde el teléfono o desde otro
  /// navegador —el caso que motivó esto—; no depende de que el pedido haya
  /// pasado por este navegador ni de un correo de confirmación que AliExpress
  /// no envía.
  void _announceAliExpressPendingDays() {
    if (!mounted) return;
    final pending = AliExpressPendingDaysService.pendingDays(
      daysWithOrders: _aliExpressOrderDates,
      invoiceNumbers: _aliExpressInvoicedDates.map(
        (day) => AliExpressPendingDaysService.invoiceNumberForDate(
          DateTime.parse(day),
        ),
      ),
    );
    final fresh = pending
        .where((day) => _announcedAliExpressPendingDays.add(day))
        .toList();
    if (fresh.isEmpty) return;

    final newest = fresh.first;
    final parsed = DateTime.parse(newest);
    final label = '${parsed.day.toString().padLeft(2, '0')}/'
        '${parsed.month.toString().padLeft(2, '0')}';
    _showBrowserSnack(
      fresh.length == 1
          ? 'Compras del $label sin factura registrada. Ábrelas desde «Compras del día».'
          : '${fresh.length} días con compras sin factura, el más reciente el $label.',
    );
  }

  /// Pista sobre qué días tienen compras, para no elegir a ciegas.
  ///
  /// Se apoya en el índice que la consulta a la API deja como subproducto. No
  /// bloquea ningún día: la ausencia de marca significa «no consta», no «no
  /// hubo compras» — afirmar lo segundo con datos parciales sería mentirle al
  /// usuario.
  Widget _buildAliExpressDayHint(
    BuildContext context, {
    required DateTime selectedDate,
    required ValueChanged<DateTime> onPickDate,
  }) {
    if (_aliExpressOrderDates.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final selectedKey = _dateKey(selectedDate);
    final hasOrders = _aliExpressOrderDates.contains(selectedKey);
    final alreadyInvoiced = _aliExpressInvoicedDates.contains(selectedKey);
    // Lo accionable es el día comprado que aún no está registrado; los ya
    // facturados sólo estorbarían la lista.
    final pending = AliExpressPendingDaysService.pendingDays(
      daysWithOrders: _aliExpressOrderDates,
      invoiceNumbers: _aliExpressInvoicedDates.map(
        (day) => AliExpressPendingDaysService.invoiceNumberForDate(
          DateTime.parse(day),
        ),
      ),
    );
    final recent =
        pending.where((date) => date != selectedKey).take(4).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // E-04 `VbNotice` de la guía de componentes: el estado del día es un
          // aviso de la superficie, no una fila de texto propia. Usar el
          // componente canónico da el tono, el ícono y la región viva ya
          // resueltos, en vez de una variante local del mismo aviso.
          VbNotice(
            key: const ValueKey('aliexpress-day-state-notice'),
            tone: alreadyInvoiced
                ? VbNoticeTone.success
                : hasOrders
                    ? VbNoticeTone.warning
                    : VbNoticeTone.info,
            title: alreadyInvoiced
                ? 'Día ya facturado'
                : hasOrders
                    ? 'Compras sin factura'
                    : 'Sin compras este día',
            body: alreadyInvoiced
                ? 'Ya existe una factura registrada para esta fecha.'
                : hasOrders
                    ? 'Las compras de este día aún no se registran en el ERP.'
                    : null,
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Compras sin factura',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final date in recent)
                  ActionChip(
                    key: ValueKey('aliexpress-day-hint-$date'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    label: Text(
                      '${date.substring(8)}/${date.substring(5, 7)}',
                      style: theme.textTheme.labelSmall,
                    ),
                    onPressed: () => onPickDate(DateTime.parse(date)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<_AliExpressImportRequest?> _pickAliExpressImportRequest() async {
    var selectedDate = DateTime.now();
    return showDialog<_AliExpressImportRequest>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.receipt_long_outlined, size: 22),
              SizedBox(width: 10),
              Text('Compras AliExpress'),
            ],
          ),
          content: SizedBox(
            width: 390,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'El ERP reunirá todos los pedidos del día, abrirá cada detalle '
                  'y preparará una sola factura. Puedes revisar el PDF primero '
                  'o abrir directamente la revisión OCR.',
                ),
                const SizedBox(height: 16),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Día de compra',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      '${selectedDate.day.toString().padLeft(2, '0')}/'
                      '${selectedDate.month.toString().padLeft(2, '0')}/'
                      '${selectedDate.year}',
                    ),
                  ),
                ),
                _buildAliExpressDayHint(
                  context,
                  selectedDate: selectedDate,
                  onPickDate: (date) =>
                      setDialogState(() => selectedDate = date),
                ),
                const SizedBox(height: 10),
                Text(
                  'No se guardará la factura ni se crearán productos hasta tu confirmación.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(
                _AliExpressImportRequest(
                  date: selectedDate,
                  mode: _AliExpressImportMode.preview,
                ),
              ),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text('Generar preview'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(
                _AliExpressImportRequest(
                  date: selectedDate,
                  mode: _AliExpressImportMode.directToOcr,
                ),
              ),
              icon: const Icon(Icons.auto_awesome, size: 17),
              label: const Text('Preparar factura'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startAliExpressDailyImport() async {
    if (_isAliExpressImportRunning) return;
    final request = await _pickAliExpressImportRequest();
    if (request == null || !mounted) return;
    final date = request.date;

    final progress = ValueNotifier<String>('Abriendo tus pedidos...');
    NavigatorState? progressNavigator;
    final progressTitle = request.mode == _AliExpressImportMode.preview
        ? 'Generando preview AliExpress'
        : 'Preparando factura AliExpress';
    setState(() => _isAliExpressImportRunning = true);
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (dialogContext) {
          progressNavigator = Navigator.of(dialogContext);
          return AlertDialog(
            content: SizedBox(
              width: 390,
              child: Row(
                children: [
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: progress,
                      builder: (_, message, __) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            progressTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(message),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    await Future<void>.delayed(Duration.zero);

    void closeProgressDialog() {
      final navigator = progressNavigator;
      if (navigator != null && navigator.mounted && navigator.canPop()) {
        navigator.pop();
      }
      progressNavigator = null;
    }

    try {
      final invoice = await _collectAliExpressDailyInvoice(
        date,
        onProgress: (message) => progress.value = message,
      );
      if (!mounted) return;

      final dateText = '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      final fileName = 'aliexpress-$dateText.pdf';
      final bytes = await _buildAliExpressInvoicePdf(invoice);
      if (!mounted) return;
      closeProgressDialog();

      if (request.mode == _AliExpressImportMode.preview) {
        final sendToOcr = await _showAliExpressInvoicePreview(
          bytes: bytes,
          fileName: fileName,
          invoice: invoice,
        );
        if (!sendToOcr || !mounted) return;
      }

      final workspaceManager = context.read<WorkspaceManager>();
      if (workspaceManager.workspaces.length >=
          WorkspaceManager.maxWorkspaces) {
        throw StateError(
          'No hay espacio para abrir la revisión OCR. Cierra una pestaña del ERP e inténtalo nuevamente.',
        );
      }
      workspaceManager.addWorkspace(
        title: 'Factura AliExpress · $dateText',
        initialRoute: '/purchases/new',
      );
      context.read<OcrFileHandoffService>().queue(
            target: OcrFileHandoffTarget.purchaseInvoice,
            fileName: fileName,
            mimeType: 'application/pdf',
            bytes: bytes,
            extension: 'pdf',
            sourceLabel: 'Navegador ERP · AliExpress · $dateText',
            sourceSupplierName: 'AliExpress Marketplace',
            sourceSupplierWebsite: 'https://www.aliexpress.com',
            structuredInvoiceData: invoice,
          );
    } catch (error) {
      closeProgressDialog();
      _showBrowserSnack(_friendlyAliExpressImportError(error));
    } finally {
      progress.dispose();
      // El recorrido diario carga decenas de páginas de pedidos con todas sus
      // imágenes y la caché en memoria del WebView las retiene indefinidamente
      // (parte del incidente de 41 GB del 2026-08-05). Liberarla aquí no toca
      // cookies ni sesiones: sólo recursos re-descargables.
      unawaited(
        InAppWebViewController.clearAllCache(includeDiskFiles: false)
            .catchError((_) {}),
      );
      if (mounted) setState(() => _isAliExpressImportRunning = false);
    }
  }

  Future<bool> _showAliExpressInvoicePreview({
    required Uint8List bytes,
    required String fileName,
    required Map<String, dynamic> invoice,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (dialogContext) => _AliExpressInvoicePreviewDialog(
        bytes: bytes,
        fileName: fileName,
        invoice: invoice,
      ),
    );
    return result == true;
  }

  Future<Map<String, dynamic>> _collectAliExpressDailyInvoice(
    DateTime date, {
    required ValueChanged<String> onProgress,
  }) async {
    final controller = _controller;
    if (controller == null) {
      throw StateError('El navegador todavía no está listo.');
    }

    final dateText = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final ordersUri = Uri.parse(AliExpressDailyInvoiceService.ordersUri);
    // Página fresca SIEMPRE, aunque ya estemos en la URL correcta: si una
    // corrida anterior murió ahí (timers congelados por oclusión de ventana,
    // timeout del bridge), el contexto JavaScript queda envenenado y en él ni
    // el bridge vuelve a instalarse (2026-08-06). Recargar cuesta ~2 s y
    // garantiza un mundo limpio por corrida.
    await _navigateAliExpressAndWait(ordersUri);

    onProgress('Buscando todos los pedidos del $dateText...');
    await _installAliExpressBridge(controller);
    final listResult = await _collectAliExpressOrdersList(
      controller,
      dateText: dateText,
      onProgress: onProgress,
    );
    final rawOrders = listResult['orders'];
    final orders = <Map<String, dynamic>>[
      if (rawOrders is List)
        for (final order in rawOrders)
          if (order is Map) Map<String, dynamic>.from(order),
    ];
    _aliExpressDebug('list.extracted', <String, dynamic>{
      'date': dateText,
      'scannedCount': listResult['scannedCount'],
      'returnedCount': orders.length,
      'duplicateOrderNumbers': _aliExpressDuplicateOrderNumbers(orders),
      'warnings': listResult['warnings'],
      'preload': listResult['preload'],
      'orders': orders.map(_aliExpressOrderDebugSummary).toList(),
    });
    if (orders.isEmpty) {
      final warnings = (listResult['warnings'] as List? ?? const [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .join(' ');
      throw StateError(
        warnings.isEmpty
            ? 'No encontré pedidos para $dateText. Verifica la sesión y la fecha.'
            : warnings,
      );
    }
    if (orders.length > 100) {
      throw StateError(
        'Encontré más de 100 pedidos para un solo día; revisa el filtro antes de continuar.',
      );
    }

    final enriched = <Map<String, dynamic>>[];
    for (var index = 0; index < orders.length; index++) {
      final listOrder = orders[index];
      final detailUri =
          AliExpressDailyInvoiceService.resolveOrderDetailUri(listOrder);
      if (detailUri == null) {
        throw StateError(
          'El pedido ${listOrder['orderNumber'] ?? index + 1} no tiene un enlace válido.',
        );
      }
      onProgress(
        'Leyendo pedido ${index + 1} de ${orders.length} '
        '(${listOrder['orderNumber'] ?? ''})...',
      );
      _aliExpressDebug('detail.navigation.start', <String, dynamic>{
        'index': index + 1,
        'totalOrders': orders.length,
        'listOrder': _aliExpressOrderDebugSummary(listOrder),
        'detailUrl': _aliExpressSafeDebugUrl(detailUri.toString()),
      });
      await _navigateAliExpressAndWait(detailUri);
      await _installAliExpressBridge(controller);
      final detail = await _runAliExpressBridge(
        controller,
        method: 'extractOrder',
      );
      _aliExpressDebug('detail.extracted', <String, dynamic>{
        'index': index + 1,
        'listOrderNumber': listOrder['orderNumber'],
        'detailOrderNumber': detail['orderNumber'],
        'orderNumberMatches': listOrder['orderNumber'] == detail['orderNumber'],
        'detail': _aliExpressOrderDebugSummary(detail),
        'expandDebug': detail['__expandDebug'],
      });
      final merged = AliExpressDailyInvoiceService.mergeListAndDetailOrder(
        listOrder,
        detail,
        detailUri,
      );
      _aliExpressDebug('detail.merged', <String, dynamic>{
        'index': index + 1,
        'listOrderNumber': listOrder['orderNumber'],
        'detailOrderNumber': detail['orderNumber'],
        'merged': _aliExpressOrderDebugSummary(merged),
      });
      enriched.add(merged);
    }

    onProgress('Consolidando ${orders.length} pedidos y generando el PDF...');
    final invoice = AliExpressDailyInvoiceService.buildDailyInvoice(
      date: date,
      orders: enriched,
      sourcePageUrl: listResult['pageUrl']?.toString(),
    );
    _aliExpressDebug('invoice.combined', <String, dynamic>{
      'inputOrderCount': enriched.length,
      'duplicateOrderNumbers': _aliExpressDuplicateOrderNumbers(enriched),
      'invoice': _aliExpressOrderDebugSummary(invoice),
      'componentDifference': invoice['componentDifference'],
      'bulkMath': invoice['bulkMath'],
    });
    return invoice;
  }

  void _aliExpressDebug(String event, Map<String, dynamic> details) {
    if (!kDebugMode) return;
    try {
      debugPrint(
        '[AE-DEBUG][erp] ${jsonEncode(<String, dynamic>{
              'event': event,
              'at': DateTime.now().toUtc().toIso8601String(),
              ...details,
            })}',
      );
    } catch (error) {
      debugPrint('[AE-DEBUG][erp] $event serialization failed: $error');
    }
  }

  String _aliExpressSafeDebugUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) return value.split('?').first;
    const allowedKeys = <String>{
      'orderId',
      'orderIdList',
      'orderNo',
      'orderNumber',
      'itemId',
      'productId',
    };
    return uri.replace(
      queryParameters: <String, String>{
        for (final entry in uri.queryParameters.entries)
          if (allowedKeys.contains(entry.key)) entry.key: entry.value,
      },
      fragment: '',
    ).toString();
  }

  Map<String, int> _aliExpressDuplicateOrderNumbers(
    List<Map<String, dynamic>> orders,
  ) {
    final counts = <String, int>{};
    for (final order in orders) {
      final number = order['orderNumber']?.toString().trim() ?? '';
      if (number.isNotEmpty) counts[number] = (counts[number] ?? 0) + 1;
    }
    counts.removeWhere((_, count) => count < 2);
    return counts;
  }

  Map<String, dynamic> _aliExpressOrderDebugSummary(
    Map<String, dynamic> order,
  ) {
    final rawItems = order['items'];
    final items = <Map<String, dynamic>>[
      if (rawItems is List)
        for (final item in rawItems)
          if (item is Map) Map<String, dynamic>.from(item),
    ];
    final itemSummaries = items.map((item) {
      final description = item['description']?.toString() ?? '';
      final productUrl = item['productUrl']?.toString() ?? '';
      final placeholder =
          RegExp(r'^AliExpress order\s+\d+$', caseSensitive: false)
                  .hasMatch(description.trim()) ||
              (productUrl.contains('/p/message/') &&
                  (item['itemId']?.toString().isEmpty ?? true));
      return <String, dynamic>{
        'sku': item['sku'],
        'itemId': item['itemId'],
        'description': description.length > 160
            ? description.substring(0, 160)
            : description,
        'quantity': item['quantity'],
        'sourcePurchaseQuantity': item['sourcePurchaseQuantity'],
        'unitsPerPurchase': item['unitsPerPurchase'],
        'sourceTotal': item['sourceTotal'],
        'total': item['total'],
        'hasImage': (item['imageUrl']?.toString().isNotEmpty ?? false),
        'productUrl': _aliExpressSafeDebugUrl(productUrl),
        'placeholder': placeholder,
      };
    }).toList();
    return <String, dynamic>{
      'orderNumber': order['orderNumber'],
      'orderDate': order['orderDate'],
      'pageUrl': _aliExpressSafeDebugUrl(order['pageUrl']?.toString() ?? ''),
      'itemCount': items.length,
      'placeholderCount':
          itemSummaries.where((item) => item['placeholder'] == true).length,
      'subtotal': order['subtotal'],
      'shipping': order['shipping'],
      'tax': order['tax'],
      'discount': order['discount'],
      'total': order['total'],
      'warnings': order['warnings'],
      'items': itemSummaries,
    };
  }

  /// Recorre el listado de pedidos con el reloj en Dart.
  ///
  /// WebKit suspende los timers de la página cuando la ventana de la app no
  /// está visible en macOS. Mientras el recorrido esperaba con `setTimeout`
  /// dentro del WebView, dejar la ventana atrás congelaba la extracción para
  /// siempre —el diálogo giraba y sólo «revivía» al volver a mirar la
  /// pantalla— (verificado el 2026-08-06: un latido `setInterval` no emitió un
  /// solo tick durante el cuelgue). Aquí cada llamada a JavaScript es corta y
  /// síncrona, y las pausas las cuenta Dart, que no depende de la visibilidad.
  /// Pide los pedidos a la API que la propia página usa.
  ///
  /// Es la vía correcta y la que se intenta primero: trae fecha, total y cada
  /// línea con su imagen tal como los tiene AliExpress, pagina por número de
  /// página y no depende del scroll, de la lista virtualizada, del rótulo del
  /// botón «View orders» ni del carrusel de recomendaciones. El recorrido del
  /// DOM queda sólo como respaldo para cuando la página no exponga su cliente
  /// de API.
  Future<Map<String, dynamic>?> _collectAliExpressOrdersViaApi(
    InAppWebViewController controller, {
    required String dateText,
    required ValueChanged<String> onProgress,
  }) async {
    try {
      await _runAliExpressBridge(controller, method: 'ordersApiProbeInstall');
      // La plantilla de la petición se toma de una llamada real de esta misma
      // sesión: los identificadores de módulo cambian por cuenta y versión, y
      // reconstruirlos a mano sería adivinar. Pedir la página siguiente
      // provoca esa llamada.
      final clicked = await _runAliExpressBridge(
        controller,
        method: 'ordersListClickLoadMore',
      );
      if (clicked['clicked'] != true) return null;
      await Future<void>.delayed(const Duration(seconds: 6));

      onProgress('Consultando pedidos del $dateText en AliExpress...');
      final result = await _runAliExpressBridge(
        controller,
        method: 'ordersApiCollect',
        arguments: <String, dynamic>{
          'filters': <String, dynamic>{'exactDate': dateText, 'maxPages': 30},
        },
      );
      if (result['ok'] != true) {
        _aliExpressDebug('orders.api.unavailable', result);
        return null;
      }

      final orders = <Map<String, dynamic>>[
        for (final order in (result['orders'] as List? ?? const []))
          if (order is Map) Map<String, dynamic>.from(order),
      ];
      final datesWithOrders = <String>[
        for (final date in (result['datesWithOrders'] as List? ?? const []))
          date.toString(),
      ];
      if (datesWithOrders.isNotEmpty) {
        _rememberAliExpressOrderDates(datesWithOrders);
      }
      _aliExpressDebug('orders.api.collected', <String, dynamic>{
        'date': dateText,
        'orderCount': orders.length,
        'pagesRead': result['pagesRead'],
        'reason': result['reason'],
        'datesWithOrders': datesWithOrders.length,
      });

      return <String, dynamic>{
        'orders': orders,
        'scannedCount': orders.length,
        'pageUrl': _currentUrl,
        'warnings': const <String>[],
        'preload': <String, dynamic>{
          'source': 'api',
          'pagesRead': result['pagesRead'],
          'terminationReason': result['reason'],
        },
      };
    } catch (error) {
      _aliExpressDebug('orders.api.failed', <String, dynamic>{
        'error': error.toString(),
      });
      return null;
    }
  }

  Future<Map<String, dynamic>> _collectAliExpressOrdersList(
    InAppWebViewController controller, {
    required String dateText,
    required ValueChanged<String> onProgress,
  }) async {
    final apiResult = await _collectAliExpressOrdersViaApi(
      controller,
      dateText: dateText,
      onProgress: onProgress,
    );
    if (apiResult != null) return apiResult;
    onProgress('Recorriendo el listado de pedidos del $dateText...');

    const maxPasses = 40;
    const maxLoadMoreClicks = 24;
    final filters = <String, dynamic>{
      'dateMode': 'day',
      'exactDate': dateText,
      'fromDate': dateText,
      'toDate': dateText,
    };

    var state = await _runAliExpressBridge(
      controller,
      method: 'ordersListBeginSteppedRun',
    );
    _aliExpressDebug('list.stepped.begin', state);

    var loadMoreClicks = 0;
    var passesWithoutProgress = 0;
    var lastHarvested = _asInt(state['harvested']);
    var terminationReason = 'max-passes';

    for (var pass = 0; pass < maxPasses; pass++) {
      final viewportHeight = _asInt(state['viewportHeight'], fallback: 800);
      final bottom = _asInt(state['bottom']);
      final scrollY = _asInt(state['scrollY']);
      // Techo: el final de la LISTA, nunca el del documento. Debajo vive un
      // carrusel de recomendaciones con scroll infinito que, si se toca,
      // crece sin límite y ralentiza cada medición de la página.
      final ceiling = math.max(0, bottom - viewportHeight + 320);
      final step = math.max(420, (viewportHeight * 0.78).round());

      if (scrollY < ceiling) {
        await _runAliExpressBridge(
          controller,
          method: 'ordersListScrollTo',
          arguments: <String, dynamic>{
            'filters': math.min(ceiling, scrollY + step),
          },
        );
        // La lista está virtualizada: hay que dejarla montar las tarjetas
        // nuevas antes de cosecharlas, y cosechar en cada paso porque al
        // salir de pantalla se desmontan.
        await Future<void>.delayed(const Duration(milliseconds: 420));
        state = await _runAliExpressBridge(
          controller,
          method: 'ordersListHarvestStep',
        );
      } else if (_asBool(state['hasLoadMore']) &&
          loadMoreClicks < maxLoadMoreClicks) {
        final click = await _runAliExpressBridge(
          controller,
          method: 'ordersListClickLoadMore',
        );
        loadMoreClicks++;
        _aliExpressDebug('list.stepped.load-more', <String, dynamic>{
          'clicks': loadMoreClicks,
          'clicked': click['clicked'],
        });
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        state = await _runAliExpressBridge(
          controller,
          method: 'ordersListHarvestStep',
        );
      } else {
        terminationReason = 'end-of-list';
        if (kDebugMode) {
          _aliExpressDebug(
            'list.stepped.tail',
            await _runAliExpressBridge(
              controller,
              method: 'ordersListDebugTail',
            ),
          );
        }
        break;
      }

      final harvested = _asInt(state['harvested']);
      onProgress(
        'Buscando pedidos del $dateText... $harvested encontrados',
      );
      if (harvested > lastHarvested) {
        lastHarvested = harvested;
        passesWithoutProgress = 0;
      } else if (_asInt(state['scrollY']) >= ceiling &&
          !_asBool(state['hasLoadMore'])) {
        passesWithoutProgress++;
        if (passesWithoutProgress >= 3) {
          terminationReason = 'no-progress';
          break;
        }
      }
    }

    final finished = await _runAliExpressBridge(
      controller,
      method: 'ordersListFinishSteppedRun',
      arguments: <String, dynamic>{'filters': filters},
    );
    _aliExpressDebug('list.stepped.end', <String, dynamic>{
      'terminationReason': terminationReason,
      'loadMoreClicks': loadMoreClicks,
      'harvestedCount': (finished['orders'] as List?)?.length ?? 0,
      'diagnostics': finished['diagnostics'],
    });

    final harvestedOrders = <Map<String, dynamic>>[
      for (final order in (finished['orders'] as List? ?? const []))
        if (order is Map) Map<String, dynamic>.from(order),
    ];
    final matchingOrders = harvestedOrders
        .where((order) => order['orderDate']?.toString() == dateText)
        .toList();

    return <String, dynamic>{
      'orders': matchingOrders,
      'scannedCount': harvestedOrders.length,
      'pageUrl': _currentUrl,
      'warnings': matchingOrders.isEmpty && harvestedOrders.isNotEmpty
          ? <String>[
              'Recorrí ${harvestedOrders.length} pedidos y ninguno es del $dateText.',
            ]
          : const <String>[],
      'preload': <String, dynamic>{
        'terminationReason': terminationReason,
        'loadMoreClicks': loadMoreClicks,
      },
    };
  }

  static int _asInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static bool _asBool(dynamic value) => value == true || value == 'true';

  Future<void> _navigateAliExpressAndWait(Uri uri) async {
    if (!AliExpressDailyInvoiceService.isTrustedUri(uri)) {
      throw StateError('AliExpress intentó abrir una dirección no confiable.');
    }
    final controller = _controller;
    if (controller == null) throw StateError('El navegador no está listo.');
    final completer = Completer<void>();
    _aliExpressNavigationCompleter = completer;
    await controller.loadUrl(urlRequest: _urlRequest(uri));
    await completer.future.timeout(
      const Duration(seconds: 35),
      onTimeout: () =>
          throw TimeoutException('AliExpress tardó demasiado en cargar.'),
    );
  }

  Future<void> _installAliExpressBridge(
    InAppWebViewController controller,
  ) async {
    if (!AliExpressDailyInvoiceService.isTrustedUri(
        Uri.tryParse(_currentUrl))) {
      throw StateError(
          'La extracción solo puede ejecutarse dentro de AliExpress.');
    }
    _aliExpressBridgeSource ??= await rootBundle.loadString(
      'assets/browser/aliexpress_invoice_content.js',
    );
    await controller.evaluateJavascript(source: _aliExpressBridgeSource!);
  }

  Future<Map<String, dynamic>> _runAliExpressBridge(
    InAppWebViewController controller, {
    required String method,
    Map<String, dynamic> arguments = const {},
  }) async {
    const allowedMethods = {
      'extractOrdersList',
      'extractOrder',
      'ordersListBeginSteppedRun',
      'ordersApiProbeInstall',
      'ordersApiProbeRead',
      'ordersApiShapeProbe',
      'ordersApiCollect',
      'ordersListDebugTail',
      'ordersListScrollTo',
      'ordersListHarvestStep',
      'ordersListClickLoadMore',
      'ordersListFinishSteppedRun',
    };
    if (!allowedMethods.contains(method)) {
      throw ArgumentError.value(method, 'method');
    }
    // Un promise perdido (proceso de contenido reiniciado, contexto de página
    // reemplazado) dejaba este await colgado PARA SIEMPRE con el diálogo de
    // progreso girando (2026-08-05). El recorrido largo de la lista puede
    // tardar minutos legítimos; el detalle de un pedido, no.
    final bridgeTimeout = method == 'extractOrdersList'
        ? const Duration(minutes: 8)
        : const Duration(seconds: 60);
    final result = await controller.callAsyncJavaScript(
      functionBody: '''
        const bridge = globalThis.__ALIEXPRESS_INVOICE_BRIDGE__;
        if (!bridge || typeof bridge[method] !== 'function') {
          throw new Error('Extractor AliExpress no disponible.');
        }
        return await bridge[method](filters !== null && filters !== undefined ? filters : undefined);
      ''',
      arguments: <String, dynamic>{
        'method': method,
        'filters': arguments['filters'],
      },
    ).timeout(
      bridgeTimeout,
      onTimeout: () => throw TimeoutException(
        'La extracción de AliExpress no respondió en '
        '${bridgeTimeout.inMinutes > 0 ? '${bridgeTimeout.inMinutes} min' : '${bridgeTimeout.inSeconds} s'}; '
        'el navegador pudo reiniciar la página. Inténtalo nuevamente.',
      ),
    );
    if (result == null) {
      throw StateError('AliExpress no devolvió información.');
    }
    if (result.error != null) throw StateError(result.error!);
    final value = result.value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw StateError('AliExpress devolvió un formato inesperado.');
  }

  String _friendlyAliExpressImportError(Object error) {
    final message =
        error.toString().replaceFirst(RegExp(r'^\w+(?:Error)?:\s*'), '');
    return 'No pude preparar la factura: $message';
  }

  Future<Uint8List> _buildAliExpressInvoicePdf(
    Map<String, dynamic> invoice,
  ) async {
    try {
      final printingInfo = await Printing.info();
      if (!printingInfo.canConvertHtml) {
        throw UnsupportedError(
          'Este equipo no puede convertir la plantilla HTML de AliExpress.',
        );
      }
      final html = await _buildAliExpressInvoiceHtml(invoice);
      // The extension invoice is HTML-first. Converting that same renderer
      // keeps the ERP preview and Chrome document on one visual contract.
      // ignore: deprecated_member_use
      return await Printing.convertHtml(
        html: html,
        format: PdfPageFormat.letter,
      );
    } catch (error) {
      _aliExpressDebug('invoice.canonical-renderer.failed', <String, dynamic>{
        'error': error.toString(),
        'fallback': 'disabled',
      });
      throw StateError(
        'No pude generar el PDF con la plantilla real de Chrome. '
        'No se usó una vista simplificada para evitar un preview engañoso. '
        'Detalle: $error',
      );
    }
  }

  Future<String> _buildAliExpressInvoiceHtml(
    Map<String, dynamic> invoice,
  ) async {
    final assets = await Future.wait<dynamic>([
      rootBundle.loadString('assets/browser/aliexpress_invoice.css'),
      rootBundle.loadString('assets/browser/aliexpress_invoice.js'),
      rootBundle.load('assets/images/loading_logo.png'),
      _inlineAliExpressInvoiceImages(invoice),
    ]);
    final css = assets[0] as String;
    final rendererSource = (assets[1] as String).replaceAll(
      RegExp('</script', caseSensitive: false),
      r'<\/script',
    );
    final logoData = assets[2] as ByteData;
    final logoBytes = logoData.buffer.asUint8List(
      logoData.offsetInBytes,
      logoData.lengthInBytes,
    );
    final preparedInvoice = assets[3] as Map<String, dynamic>;
    final invoiceLiteral = _safeAliExpressInvoiceJavascriptLiteral(
      preparedInvoice,
    );
    final logoLiteral = jsonEncode(
      'data:image/png;base64,${base64Encode(logoBytes)}',
    );

    return '''<!doctype html>
<html lang="es">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>AliExpress OCR Invoice</title>
    <style>$css</style>
    <style>
      .toolbar { display: none !important; }
      body { background: #fff !important; }
      .paper { margin: 0; box-shadow: none; }
    </style>
  </head>
  <body>
    <div class="toolbar">
      <div>
        <strong>Factura OCR AliExpress</strong>
        <span id="toolbarMeta"></span>
      </div>
      <div class="toolbar-actions">
        <button id="copyTextButton" type="button">Copiar texto OCR</button>
        <button id="downloadHtmlButton" type="button">Descargar HTML</button>
        <button id="downloadJsonButton" type="button">Descargar JSON</button>
        <button id="printButton" type="button" class="primary">Imprimir / Guardar PDF</button>
      </div>
    </div>
    <main id="invoiceRoot" class="paper" aria-live="polite"></main>
    <script>
      globalThis.__ALIEXPRESS_INVOICE_DATA__ = $invoiceLiteral;
      globalThis.__ALIEXPRESS_INVOICE_LOGO_URL__ = $logoLiteral;
    </script>
    <script>$rendererSource</script>
  </body>
</html>''';
  }

  Future<Map<String, dynamic>> _inlineAliExpressInvoiceImages(
    Map<String, dynamic> invoice,
  ) async {
    final rawItems = invoice['items'];
    final items = <Map<String, dynamic>>[
      if (rawItems is List)
        for (final rawItem in rawItems)
          if (rawItem is Map) Map<String, dynamic>.from(rawItem),
    ];
    final preparedItems = await Future.wait(
      items.map((item) async {
        final imageUrl = item['imageUrl']?.toString().trim() ?? '';
        if (imageUrl.isEmpty) return item;
        return <String, dynamic>{
          ...item,
          'embeddedImageUrl': await _inlineAliExpressInvoiceImage(imageUrl),
        };
      }),
    );
    return <String, dynamic>{
      ...invoice,
      'items': preparedItems,
    };
  }

  Future<String> _inlineAliExpressInvoiceImage(String value) async {
    if (value.startsWith('data:image/')) return value;
    final cached = _aliExpressInvoiceImageDataCache[value];
    if (cached != null) return cached;

    final normalized = value.startsWith('//') ? 'https:$value' : value;
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme != 'https' ||
        !_isTrustedAliExpressImageHost(uri.host)) {
      return '';
    }

    try {
      final response = await http.get(
        uri,
        headers: const <String, String>{
          'Referer': 'https://www.aliexpress.com/',
          'User-Agent':
              'Mozilla/5.0 AppleWebKit/537.36 Chrome/136 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 8));
      final mimeType = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      if (response.statusCode == 200 &&
          mimeType.startsWith('image/') &&
          response.bodyBytes.isNotEmpty &&
          response.bodyBytes.length <= 8 * 1024 * 1024) {
        final dataUri =
            'data:$mimeType;base64,${base64Encode(response.bodyBytes)}';
        _aliExpressInvoiceImageDataCache[value] = dataUri;
        return dataUri;
      }
    } catch (_) {
      // The canonical renderer keeps the trusted remote URL as a last resort;
      // its own image fallback removes it cleanly if WebKit cannot load it.
    }
    return uri.toString();
  }

  bool _isTrustedAliExpressImageHost(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'alicdn.com' ||
        normalized.endsWith('.alicdn.com') ||
        normalized == 'aliexpress-media.com' ||
        normalized.endsWith('.aliexpress-media.com') ||
        normalized == 'aliexpress.com' ||
        normalized.endsWith('.aliexpress.com');
  }

  String _safeAliExpressInvoiceJavascriptLiteral(Object? value) {
    return jsonEncode(value)
        .replaceAll('&', r'\u0026')
        .replaceAll('<', r'\u003c')
        .replaceAll('>', r'\u003e')
        .replaceAll('\u2028', r'\u2028')
        .replaceAll('\u2029', r'\u2029');
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
      // Las cuatro primeras son las que en compacto salieron de la barra.
      case _BrowserMenuAction.reload:
        _reload();
        return;
      case _BrowserMenuAction.forward:
        _goForward();
        return;
      case _BrowserMenuAction.home:
        _goHome();
        return;
      case _BrowserMenuAction.toggleBookmark:
        await _toggleCurrentBookmark();
        return;
      case _BrowserMenuAction.recent:
        await _showBrowserLibraryDialog(_BrowserLibraryKind.recent);
      case _BrowserMenuAction.favoritesBar:
        await _toggleFavoritesBar();
        break;
      case _BrowserMenuAction.bookmarks:
        await _showBrowserLibraryDialog(_BrowserLibraryKind.bookmarks);
      case _BrowserMenuAction.clearData:
        await _confirmClearBrowserData();
      case _BrowserMenuAction.forgetSiteCredentials:
        await _confirmForgetCurrentSiteCredentials();
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
    _clearInlineAddressCompletion();
    _addressController.text = url;
  }

  void _handleAddressFocusChanged() {
    if (!mounted) return;
    if (_addressFocusNode.hasFocus) {
      _hideSuggestionsTimer?.cancel();
      _didSelectAddressForFocus = false;
      unawaited(_loadBrowserHistory());
      unawaited(_loadSupplierPortalCatalog());
      _queueAddressSuggestions(_addressController.text);
      _selectAddressTextAfterFocus();
      setState(() => _showAddressSuggestions = true);
    } else {
      _suggestionTimer?.cancel();
      _hideSuggestionsTimer?.cancel();
      _clearInlineAddressCompletion();
      _hideSuggestionsTimer = Timer(const Duration(milliseconds: 160), () {
        if (!mounted || _addressFocusNode.hasFocus) return;
        setState(() => _showAddressSuggestions = false);
      });
      setState(() {});
    }
  }

  void _handleAddressTextChanged() {
    final currentValue = _addressController.value;
    final previousValue = _lastAddressEditingValue;
    _lastAddressEditingValue = currentValue;

    if (_isApplyingInlineCompletion) return;
    if (!_addressFocusNode.hasFocus) {
      _clearInlineAddressCompletion();
      return;
    }

    final previousInlineQuery = _inlineCompletionQuery;
    final removedSelectedCompletion = previousInlineQuery != null &&
        _hasActiveInlineCompletion(previousValue) &&
        currentValue.text == previousInlineQuery &&
        currentValue.selection.isCollapsed &&
        currentValue.selection.extentOffset == currentValue.text.length;
    final textChanged = currentValue.text != previousValue.text;

    if (!textChanged) {
      if (!_hasActiveInlineCompletion(currentValue)) {
        _clearInlineAddressCompletion();
      }
      if (mounted) setState(() => _showAddressSuggestions = true);
      return;
    }

    final userQuery = currentValue.text;
    _clearInlineAddressCompletion();

    final selectionAtEnd = currentValue.selection.isCollapsed &&
        currentValue.selection.extentOffset == currentValue.text.length;
    final editCanComplete = !removedSelectedCompletion &&
        selectionAtEnd &&
        (!previousValue.selection.isCollapsed ||
            currentValue.text.length >= previousValue.text.length);
    if (editCanComplete) {
      _applyInlineAddressCompletion(userQuery);
    }

    _queueAddressSuggestions(userQuery);
    if (mounted) {
      setState(() {
        _showAddressSuggestions = true;
        // Escribir invalida el resaltado: la lista que se ve cambia.
        _highlightedSuggestionIndex = null;
      });
    }
  }

  bool _hasActiveInlineCompletion(TextEditingValue value) {
    final query = _inlineCompletionQuery;
    final range = _inlineCompletionRange;
    if (query == null || range == null || !range.isValid) return false;
    return value.text.toLowerCase().startsWith(query.toLowerCase()) &&
        value.selection.start == range.start &&
        value.selection.end == range.end;
  }

  void _clearInlineAddressCompletion() {
    _inlineCompletionQuery = null;
    _inlineCompletionRange = null;
    _inlineCompletionNavigationUrl = null;
  }

  String get _addressSuggestionQuery =>
      (_inlineCompletionQuery ?? _addressController.text).trim();

  bool _applyInlineAddressCompletion(String query) {
    if (!_addressFocusNode.hasFocus ||
        !_addressController.selection.isCollapsed ||
        _addressController.selection.extentOffset !=
            _addressController.text.length) {
      return false;
    }

    final normalizedQuery = normalizeBrowserHostForMatch(query);
    final rankedPrefixSites =
        _rankedAddressSiteMatches(normalizedQuery).where((site) {
      final normalizedHost = normalizeBrowserHostForMatch(site.host);
      return normalizedHost.startsWith(normalizedQuery);
    }).toList(growable: false);
    final completion = browserInlineHostCompletion(
      query: query,
      rankedHosts: rankedPrefixSites.map((site) => site.host),
    );
    if (completion == null || rankedPrefixSites.isEmpty) return false;

    final selection = TextSelection(
      baseOffset: completion.selectionStart,
      extentOffset: completion.selectionEnd,
    );
    _inlineCompletionQuery = query;
    _inlineCompletionRange = TextRange(
      start: completion.selectionStart,
      end: completion.selectionEnd,
    );
    _inlineCompletionNavigationUrl = rankedPrefixSites.first.url;
    _isApplyingInlineCompletion = true;
    try {
      final completedValue = TextEditingValue(
        text: completion.value,
        selection: selection,
      );
      _addressController.value = completedValue;
      _lastAddressEditingValue = completedValue;
    } finally {
      _isApplyingInlineCompletion = false;
    }
    return true;
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
          _addressSuggestionQuery != query) {
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
      final storageKey = _profilePrefsKey(_historyPrefsKey);
      await (_historyWriteTails[storageKey] ?? Future<void>.value());
      final prefs = await SharedPreferences.getInstance();
      final encoded = prefs.getStringList(storageKey) ?? const [];
      final entries = <_BrowserHistoryEntry>[];
      for (final item in encoded) {
        final entry = _BrowserHistoryEntry.tryDecode(item);
        if (entry != null) entries.add(entry);
      }
      entries.sort((a, b) => b.visitedAt.compareTo(a.visitedAt));

      var sites = await BrowserSiteMemoryService.load(
        _browserProfileIdentity,
      );
      final hasLegacyRootOnlySite = sites.any(
        (site) => site.lastUrl == site.origin,
      );
      if (entries.isNotEmpty && (sites.isEmpty || hasLegacyRootOnlySite)) {
        sites = await BrowserSiteMemoryService.mergeFromHistory(
          userId: _browserProfileIdentity,
          history: entries
              .map(
                (entry) => BrowserVisitedPage(
                  url: entry.url,
                  title: entry.title,
                  visitedAt: entry.visitedAt,
                ),
              )
              .toList(growable: false),
        );
      }
      if (!mounted) return;
      setState(() {
        _historyEntries = entries.take(_maxHistoryEntries).toList();
        _siteEntries = sites;
      });
      if (_addressFocusNode.hasFocus &&
          _inlineCompletionQuery == null &&
          _addressController.selection.isCollapsed &&
          _addressController.selection.extentOffset ==
              _addressController.text.length &&
          _applyInlineAddressCompletion(_addressController.text)) {
        setState(() => _showAddressSuggestions = true);
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser history load skipped: $error');
      }
    }
  }

  Future<void> _loadSupplierPortalCatalog() async {
    if (!mounted) return;
    try {
      final suppliers = await context.read<PurchaseService>().getSuppliers(
            activeOnly: true,
          );
      final entries = buildBrowserSupplierPortalCatalog(suppliers);
      if (!mounted) return;
      setState(() => _supplierPortalEntries = entries);
      if (_addressFocusNode.hasFocus &&
          _inlineCompletionQuery == null &&
          _addressController.selection.isCollapsed &&
          _addressController.selection.extentOffset ==
              _addressController.text.length &&
          _applyInlineAddressCompletion(_addressController.text)) {
        setState(() => _showAddressSuggestions = true);
      }
    } on ProviderNotFoundException {
      // Some isolated browser hosts do not install the purchases provider.
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '🌐 Supplier portal catalog load skipped: ${error.runtimeType}',
        );
      }
    }
  }

  Future<void> _recordBrowserHistory(WebUri? url, {String? title}) async {
    if (url == null) return;
    final uri = Uri.tryParse(url.toString());
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }

    final value = uri.toString();
    final cleanTitle = title?.trim() ?? '';
    final entry = _BrowserHistoryEntry(
      url: value,
      title: cleanTitle.isEmpty ? uri.host : cleanTitle,
      visitedAt: DateTime.now(),
    );

    final storageKey = _profilePrefsKey(_historyPrefsKey);
    final previousWrite =
        _historyWriteTails[storageKey] ?? Future<void>.value();
    final write = previousWrite.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final storedEntries = <_BrowserHistoryEntry>[];
        for (final item
            in prefs.getStringList(storageKey) ?? const <String>[]) {
          final storedEntry = _BrowserHistoryEntry.tryDecode(item);
          if (storedEntry != null) storedEntries.add(storedEntry);
        }
        final nextEntries = <_BrowserHistoryEntry>[
          entry,
          ...storedEntries.where((candidate) => candidate.url != value),
        ].take(_maxHistoryEntries).toList(growable: false);

        await prefs.setStringList(
          storageKey,
          nextEntries.map((entry) => entry.encode()).toList(growable: false),
        );
        final nextSites = await BrowserSiteMemoryService.recordVisit(
          userId: _browserProfileIdentity,
          url: value,
          title: entry.title,
          visitedAt: entry.visitedAt,
        );
        if (mounted) {
          setState(() {
            _historyEntries = nextEntries;
            _siteEntries = nextSites;
          });
        } else {
          _historyEntries = nextEntries;
          _siteEntries = nextSites;
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('🌐 Browser history save skipped: $error');
        }
      }
    });
    _historyWriteTails[storageKey] = write;
    await write;
    if (identical(_historyWriteTails[storageKey], write)) {
      _historyWriteTails.remove(storageKey);
    }
  }

  Future<void> _toggleFavoritesBar() async {
    setState(() => _showFavoritesBar = !_showFavoritesBar);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        _profilePrefsKey(_favoritesBarPrefsKey),
        _showFavoritesBar,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Favorites bar preference skipped: $error');
      }
    }
  }

  Future<void> _loadBrowserBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final visible = prefs.getBool(_profilePrefsKey(_favoritesBarPrefsKey));
      if (visible != null && mounted && visible != _showFavoritesBar) {
        setState(() => _showFavoritesBar = visible);
      }
      final encoded =
          prefs.getStringList(_profilePrefsKey(_bookmarkPrefsKey)) ?? const [];
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
        _profilePrefsKey(_bookmarkPrefsKey),
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

  Future<void> _removeBookmarkEntry(_BrowserBookmarkEntry bookmark) async {
    final nextEntries = _bookmarkEntries
        .where((entry) => entry.url != bookmark.url)
        .toList(growable: false);
    if (mounted) {
      setState(() => _bookmarkEntries = nextEntries);
      _showBrowserSnack('Marcador eliminado.');
    } else {
      _bookmarkEntries = nextEntries;
    }
    await _saveBrowserBookmarks(nextEntries);
  }

  Future<void> _toggleCurrentBookmark() async {
    final value = _currentBookmarkableUrl();
    if (value == null) return;
    await _loadBrowserBookmarks();
    if (!mounted) return;

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
    if (isBookmarks) {
      await _loadBrowserBookmarks();
    } else {
      await _loadBrowserHistory();
    }
    if (!mounted) return;

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

  Future<PermissionResponse> _requestSitePermission(
    PermissionRequest request,
  ) async {
    if (request.resources.isEmpty) {
      return PermissionResponse(action: PermissionResponseAction.DENY);
    }

    final origin = request.origin.toString();
    final stored = await _loadSitePermissionDecisions();
    final resourceKeys = request.resources
        .map((resource) => '$origin|${resource.toString()}')
        .toList(growable: false);
    final storedDecisions = resourceKeys
        .map((key) => stored[key])
        .whereType<String>()
        .toList(growable: false);

    if (storedDecisions.contains('deny')) {
      return PermissionResponse(
        resources: const [],
        action: PermissionResponseAction.DENY,
      );
    }

    if (storedDecisions.length == resourceKeys.length) {
      return PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.GRANT,
      );
    }

    if (!mounted) {
      return PermissionResponse(action: PermissionResponseAction.DENY);
    }

    final decision = await showDialog<_BrowserPermissionDecision>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final originUri = Uri.tryParse(origin);
        final site =
            originUri?.host.isNotEmpty == true ? originUri!.host : origin;
        final resources =
            request.resources.map(_permissionResourceLabel).toSet().join(', ');
        return AlertDialog(
          title: const Text('Permiso del sitio'),
          content: Text(
            '$site solicita acceso a $resources. '
            'Los permisos permanentes se guardan sólo en este perfil del ERP.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _BrowserPermissionDecision.denyAlways,
              ),
              child: const Text('Bloquear'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _BrowserPermissionDecision.allowOnce,
              ),
              child: const Text('Permitir una vez'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _BrowserPermissionDecision.allowAlways,
              ),
              child: const Text('Permitir siempre'),
            ),
          ],
        );
      },
    );

    final resolved = decision ?? _BrowserPermissionDecision.denyOnce;
    if (resolved == _BrowserPermissionDecision.allowAlways ||
        resolved == _BrowserPermissionDecision.denyAlways) {
      final storedValue =
          resolved == _BrowserPermissionDecision.allowAlways ? 'allow' : 'deny';
      for (final key in resourceKeys) {
        stored[key] = storedValue;
      }
      await _saveSitePermissionDecisions(stored);
    }

    final allow = resolved == _BrowserPermissionDecision.allowAlways ||
        resolved == _BrowserPermissionDecision.allowOnce;
    return PermissionResponse(
      resources: allow ? request.resources : const [],
      action: allow
          ? PermissionResponseAction.GRANT
          : PermissionResponseAction.DENY,
    );
  }

  Future<Map<String, String>> _loadSitePermissionDecisions() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded =
        prefs.getString(_profilePrefsKey(_permissionPrefsKey)) ?? '';
    if (encoded.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return <String, String>{};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _saveSitePermissionDecisions(
    Map<String, String> decisions,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilePrefsKey(_permissionPrefsKey),
      jsonEncode(decisions),
    );
  }

  String _permissionResourceLabel(PermissionResourceType resource) {
    switch (resource.toString()) {
      case 'CAMERA':
        return 'la cámara';
      case 'MICROPHONE':
        return 'el micrófono';
      case 'CAMERA_AND_MICROPHONE':
        return 'la cámara y el micrófono';
      case 'GEOLOCATION':
        return 'tu ubicación';
      case 'CLIPBOARD_READ':
        return 'el portapapeles';
      case 'NOTIFICATIONS':
        return 'las notificaciones';
      case 'MIDI_SYSEX':
        return 'dispositivos MIDI';
      case 'FILE_READ_WRITE':
        return 'archivos y carpetas';
      case 'LOCAL_FONTS':
        return 'las fuentes locales';
      case 'AUTOPLAY':
        return 'la reproducción automática';
      default:
        return 'recursos protegidos';
    }
  }

  Future<void> _confirmClearBrowserData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Limpiar datos del navegador'),
          content: const Text(
            'Esto borra caché, cookies, inicios de sesión, credenciales '
            'guardadas localmente y permisos de sitios. Tus marcadores, '
            'recientes y las credenciales de fichas de proveedores se '
            'mantienen.',
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
      await BrowserProfileService.clearWebsiteData(
        userId: _browserProfileIdentity,
      );
      try {
        await _credentialVault.clearUser(_browserProfileIdentity);
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '🌐 Local credential vault unavailable: ${error.runtimeType}',
          );
        }
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_profilePrefsKey(_permissionPrefsKey));
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
    final headers = <String, String>{};
    final requestUserAgent = request.userAgent?.trim();
    if (requestUserAgent?.isNotEmpty == true) {
      headers['User-Agent'] = requestUserAgent!;
    }

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

  /// Navegación por teclado del omnibox, como en un navegador real: ↓/↑
  /// recorren las sugerencias visibles, Enter abre la resaltada (o navega lo
  /// escrito si no hay resaltado) y Esc cierra el panel.
  KeyEventResult _handleOmniboxKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final suggestions = _visibleSuggestions;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape) {
      if (!_showAddressSuggestions) return KeyEventResult.ignored;
      setState(() {
        _showAddressSuggestions = false;
        _highlightedSuggestionIndex = null;
      });
      return KeyEventResult.handled;
    }

    if (suggestions.isEmpty) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _highlightedSuggestionIndex = nextOmniboxHighlight(
          current: _highlightedSuggestionIndex,
          count: suggestions.length,
          delta: key == LogicalKeyboardKey.arrowDown ? 1 : -1,
        );
      });
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final index = _highlightedSuggestionIndex;
      if (index == null || index < 0 || index >= suggestions.length) {
        // Sin resaltado: el TextField ejecuta su onSubmitted normal.
        return KeyEventResult.ignored;
      }
      unawaited(_openAddressSuggestion(suggestions[index]));
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _submitOmnibox(String input) {
    _highlightedSuggestionIndex = null;
    unawaited(_loadAddress(input));
  }

  List<_BrowserAddressSuggestion> _addressSuggestions() {
    if (!_showAddressSuggestions) return const [];

    final query = _addressSuggestionQuery;
    final normalizedQuery = query.toLowerCase();
    final suggestions = <_BrowserAddressSuggestion>[];
    final seen = <String>{};

    void add(_BrowserAddressSuggestion suggestion) {
      final key =
          suggestion.value.toLowerCase().replaceFirst(RegExp(r'/$'), '');
      if (seen.add(key)) suggestions.add(suggestion);
    }

    if (query.isEmpty) {
      for (final site in _rankedAddressSiteMatches('').take(8)) {
        add(_BrowserAddressSuggestion.addressSite(site));
      }
      for (final entry in _historyEntries.take(8)) {
        add(_BrowserAddressSuggestion.history(entry));
      }
      return suggestions.take(10).toList(growable: false);
    }

    final siteMatches = _rankedAddressSiteMatches(query);
    for (final site in siteMatches.take(6)) {
      add(_BrowserAddressSuggestion.addressSite(site));
    }

    final historyMatches = _historyEntries.where((entry) {
      return entry.title.toLowerCase().contains(normalizedQuery) ||
          entry.host.toLowerCase().contains(normalizedQuery) ||
          entry.url.toLowerCase().contains(normalizedQuery);
    });

    for (final entry in historyMatches.take(4)) {
      add(_BrowserAddressSuggestion.history(entry));
    }

    if (!_looksLikeDirectAddress(query)) {
      add(_BrowserAddressSuggestion.search(query));
      for (final suggestion in _searchSuggestions) {
        add(_BrowserAddressSuggestion.search(suggestion));
      }
    }

    return suggestions.take(10).toList(growable: false);
  }

  List<_BrowserAddressSiteCandidate> _rankedAddressSiteMatches(String query) {
    final sitesByHost = <String, _BrowserAddressSiteCandidate>{};

    for (final portal in _supplierPortalEntries) {
      sitesByHost[normalizeBrowserHostForMatch(portal.host)] =
          _BrowserAddressSiteCandidate.supplier(portal);
    }
    for (final site in _siteEntries) {
      final key = normalizeBrowserHostForMatch(site.host);
      final supplierCandidate = sitesByHost[key];
      final visitedCandidate = _BrowserAddressSiteCandidate.visited(site);
      if (supplierCandidate != null &&
          !_hasUsefulBrowserPath(visitedCandidate.url) &&
          _hasUsefulBrowserPath(supplierCandidate.url)) {
        continue;
      }
      sitesByHost[key] = visitedCandidate;
    }

    final siteMatches = sitesByHost.values.where((site) {
      return browserSiteMatchRank(
            query: query,
            host: site.host,
            title: site.title,
            url: site.url,
          ) >=
          0;
    }).toList(growable: false);
    siteMatches.sort((a, b) {
      final rankA = browserSiteMatchRank(
        query: query,
        host: a.host,
        title: a.title,
        url: a.url,
      );
      final rankB = browserSiteMatchRank(
        query: query,
        host: b.host,
        title: b.title,
        url: b.url,
      );
      final rankComparison = rankA.compareTo(rankB);
      if (rankComparison != 0) return rankComparison;
      final sourceComparison = a.source.index.compareTo(b.source.index);
      if (sourceComparison != 0) return sourceComparison;
      final visitComparison = b.visitCount.compareTo(a.visitCount);
      if (visitComparison != 0) return visitComparison;
      final recentComparison = b.lastVisitedAt.compareTo(a.lastVisitedAt);
      if (recentComparison != 0) return recentComparison;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return siteMatches;
  }

  bool _hasUsefulBrowserPath(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.path.isNotEmpty && uri.path != '/';
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

  /// Un clic dentro de la página cae en la capa nativa del WebView y jamás
  /// llega a la barrera modal de Flutter, así que el menú ⋮ o un menú
  /// contextual quedaban abiertos. El puente JS reporta ese clic y aquí se
  /// cierra el menú transitorio, igual que ya se des-enfoca el omnibox.
  void _dismissTransientMenuFromPageInteraction() {
    if (!_transientMenuOpen || !mounted) return;
    _transientMenuOpen = false;
    Navigator.of(context).maybePop();
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

  Future<bool> _saveSubmittedBrowserCredential(List<dynamic> arguments) async {
    if (arguments.isEmpty || arguments.first is! Map) return false;
    final payload = arguments.first as Map;
    final origin = BrowserCredentialVault.normalizeOrigin(
      payload['origin']?.toString(),
    );
    final username = payload['username']?.toString() ?? '';
    final password = payload['password']?.toString() ?? '';
    final currentOrigin = BrowserCredentialVault.normalizeOrigin(_currentUrl);
    if (origin == null ||
        currentOrigin != origin ||
        username.trim().isEmpty ||
        username.length > 512 ||
        password.isEmpty ||
        password.length > 4096) {
      return false;
    }

    try {
      final supplierCredential = await _supplierCredentialForOrigin(origin);
      if (supplierCredential != null &&
          supplierCredential.username == username.trim() &&
          supplierCredential.password == password) {
        await _deleteLocalCredential(origin);
        return true;
      }

      await _credentialVault.save(
        userId: _browserProfileIdentity,
        origin: origin,
        username: username,
        password: password,
      );
      if (mounted && _credentialSavedFeedbackOrigins.add(origin)) {
        final host = Uri.parse(origin).host;
        _showBrowserSnack(
          'Credenciales de $host guardadas de forma segura.',
        );
      }
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser credential save skipped: $error');
      }
      return false;
    }
  }

  Future<void> _autofillSavedBrowserCredential(
    InAppWebViewController controller,
    WebUri? loadedUrl,
  ) async {
    final origin = normalizeSupplierBrowserOrigin(
      loadedUrl?.toString(),
    );
    if (origin == null || !_credentialAutofillInFlight.add(origin)) return;

    try {
      final liveUrlBeforeDetection = await controller.getUrl();
      if (normalizeSupplierBrowserOrigin(
            liveUrlBeforeDetection?.toString(),
          ) !=
          origin) {
        return;
      }
      final loginFormResult = await controller.evaluateJavascript(
        source: browserLoginFormDetectionScript,
      );
      final hasLoginForm = loginFormResult == true ||
          loginFormResult?.toString().toLowerCase() == 'true';
      if (!hasLoginForm) return;

      final supplierCredential = await _supplierCredentialForOrigin(origin);
      final secureOrigin = BrowserCredentialVault.normalizeOrigin(origin);
      if (supplierCredential == null && secureOrigin == null) return;
      // The supplier record is the primary source and must keep working even
      // when a native secure-storage plugin is temporarily unavailable after
      // hot reload/restart. The local vault is an optional fallback only.
      final vaultCredential = secureOrigin == null
          ? null
          : await _localCredentialForOrigin(secureOrigin);
      final useVault = vaultCredential != null &&
          (supplierCredential == null ||
              vaultCredential.updatedAt.isAfter(
                supplierCredential.updatedAt,
              ));
      final username =
          useVault ? vaultCredential.username : supplierCredential?.username;
      final password =
          useVault ? vaultCredential.password : supplierCredential?.password;
      if (username == null || password == null) return;

      final liveUrl = await controller.getUrl();
      if (normalizeSupplierBrowserOrigin(liveUrl?.toString()) != origin) {
        return;
      }

      final mayAutoSubmit =
          !_automaticCredentialSubmitAttempts.contains(origin);
      final result = await controller.evaluateJavascript(
        source: browserCredentialFillScript(
          expectedOrigin: origin,
          username: username,
          password: password,
          autoSubmit: mayAutoSubmit,
          allowInsecureSupplierOrigin:
              secureOrigin == null && supplierCredential != null,
        ),
      );
      if (result?.toString().contains('filled-insecure') == true &&
          mounted &&
          _insecureCredentialFeedbackOrigins.add(origin)) {
        _showBrowserSnack(
          'Credenciales completadas. Este portal envía el acceso por HTTP; '
          'confirma el ingreso manualmente.',
        );
      }
      if (mayAutoSubmit &&
          result?.toString().contains('filled-and-submitted') == true) {
        _automaticCredentialSubmitAttempts.add(origin);
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Browser credential autofill skipped: $error');
      }
    } finally {
      _credentialAutofillInFlight.remove(origin);
    }
  }

  Future<BrowserSupplierCredential?> _supplierCredentialForOrigin(
    String origin,
  ) async {
    if (!mounted) return null;
    try {
      final suppliers = await context.read<PurchaseService>().getSuppliers(
            activeOnly: true,
          );
      return resolveSupplierCredentialForOrigin(
        suppliers: suppliers,
        origin: origin,
      );
    } on ProviderNotFoundException {
      return null;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '🌐 Supplier credential lookup skipped: ${error.runtimeType}',
        );
      }
      return null;
    }
  }

  Future<BrowserSavedCredential?> _localCredentialForOrigin(
    String origin,
  ) async {
    try {
      return await _credentialVault.load(
        userId: _browserProfileIdentity,
        origin: origin,
      );
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '🌐 Local credential vault unavailable: ${error.runtimeType}',
        );
      }
      return null;
    }
  }

  Future<bool> _deleteLocalCredential(String origin) async {
    try {
      await _credentialVault.delete(
        userId: _browserProfileIdentity,
        origin: origin,
      );
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '🌐 Local credential vault unavailable: ${error.runtimeType}',
        );
      }
      return false;
    }
  }

  Future<void> _confirmForgetCurrentSiteCredentials() async {
    final origin = normalizeSupplierBrowserOrigin(_currentUrl);
    if (origin == null) {
      _showBrowserSnack('Este sitio no admite credenciales guardadas.');
      return;
    }
    final supplierCredential = await _supplierCredentialForOrigin(origin);
    if (supplierCredential != null) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Credenciales del proveedor'),
          content: Text(
            'El acceso para ${supplierCredential.supplierName} proviene de '
            'su ficha de proveedor. Para detener el ingreso automático, '
            'elimina allí el usuario o la contraseña del portal.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }
    final credential = await _localCredentialForOrigin(origin);
    if (credential == null) {
      _showBrowserSnack('No hay credenciales guardadas para este sitio.');
      return;
    }
    if (!mounted) return;

    final host = Uri.parse(origin).host;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Olvidar credenciales'),
        content: Text(
          'Se eliminarán del llavero el usuario y la contraseña guardados '
          'para $host.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Olvidar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final deleted = await _deleteLocalCredential(origin);
    if (!deleted) {
      _showBrowserSnack('No pude acceder al llavero del sistema.');
      return;
    }
    _automaticCredentialSubmitAttempts.remove(origin);
    _credentialSavedFeedbackOrigins.remove(origin);
    _showBrowserSnack('Credenciales de $host eliminadas.');
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
    _publishBrowserWorkspaceState(url: displayValue, title: _pageTitle);
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

    final requestMethod = createWindowAction.request.method?.toUpperCase();
    final canRecreateAsNavigation =
        (requestMethod == null || requestMethod == 'GET') &&
            createWindowAction.request.body == null;
    if ((url.scheme == 'http' || url.scheme == 'https') &&
        canRecreateAsNavigation) {
      final workspaceId = context.read<WorkspaceManager>().openBrowserWorkspace(
            url.toString(),
            title: url.host,
          );
      if (workspaceId == null) {
        _showBrowserSnack(
          'No se pudo abrir otra pestaña. Cierra una pestaña e inténtalo de nuevo.',
        );
      }
    } else if (_canLoadInsideWebView(url)) {
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
              initialUserScripts: _credentialAutofillUserScripts,
              initialUrlRequest: _urlRequest(initialUri),
              initialSettings: _browserSettings(browserZoom),
              onWebViewCreated: (controller) {
                _controller = controller;
                controller.addJavaScriptHandler(
                  handlerName: _pageInteractionHandlerName,
                  callback: (_) {
                    _clearAddressFocusFromPageInteraction();
                    _dismissTransientMenuFromPageInteraction();
                    return null;
                  },
                );
                controller.addJavaScriptHandler(
                  handlerName: browserCredentialCaptureHandlerName,
                  callback: _saveSubmittedBrowserCredential,
                );
                unawaited(_installPageInteractionBridge(controller));
                unawaited(_applyBrowserZoom(browserZoom));
                unawaited(_refreshNavigationState());
              },
              onWebContentProcessDidTerminate: (controller) {
                // WebKit reinicia su proceso de contenido tras un crash u
                // OOM sin avisar visualmente: los promises de JavaScript en
                // vuelo mueren con él. Registrarlo y soltar la navegación en
                // curso es lo que convierte un cuelgue eterno en un error
                // diagnosticable (2026-08-05).
                debugPrint(
                  '⚠️ Browser: el proceso de contenido del WebView terminó '
                  '(crash/OOM) en $_currentUrl',
                );
                final navigationCompleter = _aliExpressNavigationCompleter;
                if (navigationCompleter != null &&
                    !navigationCompleter.isCompleted) {
                  navigationCompleter.completeError(
                    StateError(
                        'El navegador reinició la página de AliExpress.'),
                  );
                }
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
                if (kDebugMode) {
                  // Sonda de identidad: la captura de pantalla del agente no
                  // ve la capa nativa del WebView, así que la verificación del
                  // user agent y del render moderno sale por el log.
                  unawaited(() async {
                    final ua = await controller.evaluateJavascript(
                      source: 'navigator.userAgent',
                    );
                    final modernSignal = await controller.evaluateJavascript(
                      source:
                          "document.querySelector('[jscontroller]') != null",
                    );
                    debugPrint('🌐 [BrowserProbe] url=$url');
                    debugPrint('🌐 [BrowserProbe] ua=$ua');
                    debugPrint(
                      '🌐 [BrowserProbe] modernGoogleMarkup=$modernSignal',
                    );
                  }());
                }
                setState(() {
                  _isLoading = false;
                  _loadingProgress = 100;
                });
                _setCurrentUrl(url);
                _pageTitle = await controller.getTitle();
                _publishBrowserWorkspaceState(
                  url: _currentUrl,
                  title: _pageTitle,
                );
                unawaited(_recordBrowserHistory(url, title: _pageTitle));
                if (mounted) setState(() {});
                unawaited(
                  _autofillSavedBrowserCredential(controller, url),
                );
                unawaited(_installPageInteractionBridge(controller));
                unawaited(_applyBrowserZoom(browserZoom));
                unawaited(_refreshNavigationState());
                final navigationCompleter = _aliExpressNavigationCompleter;
                if (navigationCompleter != null &&
                    !navigationCompleter.isCompleted) {
                  navigationCompleter.complete();
                }
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
                if (_currentUrl.isNotEmpty) {
                  _publishBrowserWorkspaceState(
                    url: _currentUrl,
                    title: title,
                  );
                }
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
                final navigationCompleter = _aliExpressNavigationCompleter;
                if (navigationCompleter != null &&
                    !navigationCompleter.isCompleted) {
                  navigationCompleter.completeError(
                    StateError(error.description),
                  );
                }
                if (canRecoverThroughRelay) {
                  unawaited(_recoverCurrentDocumentThroughRelay(failedUrl));
                }
              },
              onPermissionRequest: (controller, request) =>
                  _requestSitePermission(request),
              shouldOverrideUrlLoading: _handleNavigation,
              onCreateWindow: _handleCreateWindow,
              onDownloadStartRequest: (controller, request) {
                unawaited(_handleDownloadStart(request));
              },
              onConsoleMessage: (controller, consoleMessage) {
                if (kDebugMode) {
                  debugPrint('🌐 Web workspace: ${consoleMessage.message}');
                }
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
    // El manejador de teclado necesita exactamente la lista que se pinta.
    _visibleSuggestions = addressSuggestions;
    if (_highlightedSuggestionIndex != null &&
        _highlightedSuggestionIndex! >= addressSuggestions.length) {
      _highlightedSuggestionIndex =
          addressSuggestions.isEmpty ? null : addressSuggestions.length - 1;
    }
    final isBookmarked = _isCurrentBookmarked;
    // Misma frontera que el resto del shell: bajo 900px la barra se recompone,
    // no se encoge.
    final compactBrowserChrome = ResponsiveViewport.usesCompactShell(context);

    return TooltipTheme(
      // El toolbar vive pegado al borde superior de la ventana: un tooltip
      // hacia arriba se recorta contra el marco. Todos hacia abajo.
      data: TooltipTheme.of(context).copyWith(preferBelow: true),
      child: DecoratedBox(
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
                  if (_isAliExpressPage) ...[
                    Tooltip(
                      message: 'Reunir las compras de un día en una factura',
                      child: FilledButton.tonalIcon(
                        onPressed: canUseWebView && !_isAliExpressImportRunning
                            ? _startAliExpressDailyImport
                            : null,
                        icon: _isAliExpressImportRunning
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.receipt_long_outlined, size: 17),
                        label: const Text('Compras del día'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  // En compacto sólo sobrevive «Atrás»: es el control que se
                  // usa a cada rato y el único que no tiene equivalente obvio
                  // dentro del menú. Adelante, recargar e inicio se van al
                  // menú «⋮». Meter los nueve controles de escritorio en 420px
                  // dejaba la dirección reducida a un candado ilegible y sin
                  // forma de saber en qué sitio estabas (2026-08-06).
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: _canGoBack ? _goBack : null,
                    tooltip: 'Atrás',
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(
                      minWidth: compactBrowserChrome ? 48 : 36,
                      minHeight: compactBrowserChrome ? 48 : 36,
                    ),
                  ),
                  if (!compactBrowserChrome) ...[
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
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: Focus(
                        onKeyEvent: _handleOmniboxKey,
                        child: TextField(
                          key: const ValueKey('browser-omnibox-field'),
                          controller: _addressController,
                          focusNode: _addressFocusNode,
                          enabled: canUseWebView,
                          textInputAction: TextInputAction.go,
                          keyboardType: TextInputType.url,
                          onSubmitted: _submitOmnibox,
                          style: theme.textTheme.bodyMedium,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor:
                                theme.colorScheme.surfaceContainerHighest,
                            // Indicador de seguridad del sitio cargado, como en
                            // cualquier navegador: candado en HTTPS, aviso en
                            // HTTP plano. Refleja la página actual, no lo que se
                            // está escribiendo.
                            prefixIcon: Tooltip(
                              message: switch (
                                  Uri.tryParse(_currentUrl)?.scheme) {
                                'https' => 'Conexión segura (HTTPS)',
                                'http' => 'Conexión NO segura (HTTP)',
                                _ => 'Dirección o búsqueda',
                              },
                              child: Icon(
                                switch (Uri.tryParse(_currentUrl)?.scheme) {
                                  'https' => Icons.lock_outline,
                                  'http' => Icons.no_encryption_gmailerrorred,
                                  _ => Icons.language,
                                },
                                size: 18,
                                color:
                                    Uri.tryParse(_currentUrl)?.scheme == 'http'
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurfaceVariant,
                              ),
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
                                    icon: const Icon(Icons.arrow_forward,
                                        size: 18),
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
                  ),
                  const SizedBox(width: 8),
                  // El marcador se guarda desde el menú en compacto: la
                  // dirección necesita ese ancho más que una estrella.
                  if (!compactBrowserChrome)
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
                    onOpened: () => _transientMenuOpen = true,
                    onCanceled: () => _transientMenuOpen = false,
                    onSelected: (action) {
                      _transientMenuOpen = false;
                      unawaited(_handleBrowserMenuAction(action));
                    },
                    itemBuilder: (context) => [
                      // Lo que en escritorio son botones propios, en compacto
                      // entra acá arriba: no desaparece ninguna acción, sólo
                      // cambia de sitio para que la dirección sea legible.
                      if (compactBrowserChrome) ...[
                        const PopupMenuItem(
                          value: _BrowserMenuAction.reload,
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.refresh),
                            title: Text('Recargar'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _BrowserMenuAction.forward,
                          enabled: _canGoForward,
                          child: const ListTile(
                            dense: true,
                            leading: Icon(Icons.arrow_forward),
                            title: Text('Adelante'),
                          ),
                        ),
                        const PopupMenuItem(
                          value: _BrowserMenuAction.home,
                          child: ListTile(
                            dense: true,
                            leading: Icon(Icons.home_outlined),
                            title: Text('Inicio'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _BrowserMenuAction.toggleBookmark,
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              isBookmarked ? Icons.star : Icons.star_border,
                              color:
                                  isBookmarked ? Colors.amber.shade700 : null,
                            ),
                            title: Text(
                              isBookmarked
                                  ? 'Quitar marcador'
                                  : 'Guardar marcador',
                            ),
                          ),
                        ),
                        const PopupMenuDivider(),
                      ],
                      const PopupMenuItem(
                        value: _BrowserMenuAction.recent,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.history),
                          title: Text('Recientes'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _BrowserMenuAction.bookmarks,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.star_border),
                          title: Text('Marcadores'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _BrowserMenuAction.favoritesBar,
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            _showFavoritesBar
                                ? Icons.check_box_outlined
                                : Icons.check_box_outline_blank,
                          ),
                          title: const Text('Barra de favoritos'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _BrowserMenuAction.forgetSiteCredentials,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.key_off_outlined),
                          title: Text('Olvidar credenciales del sitio'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _BrowserMenuAction.clearData,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.cleaning_services_outlined),
                          title: Text('Limpiar datos'),
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: _BrowserMenuAction.openInChrome,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.person_outline),
                          title: Text('Abrir en Chrome'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: _BrowserMenuAction.openExternal,
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.open_in_new),
                          title: Text('Abrir afuera'),
                        ),
                      ),
                    ],
                  ),
                  // En compacto esta acción ya vive en el menú («Abrir
                  // afuera»); repetirla en la barra sólo robaba ancho.
                  if (!compactBrowserChrome)
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
            if (_showFavoritesBar && _bookmarkEntries.isNotEmpty)
              _buildFavoritesBar(context),
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
      ),
    );
  }

  /// Barra de favoritos al estilo de un navegador de escritorio: los
  /// marcadores existentes, visibles bajo la barra de direcciones. Clic
  /// navega; clic secundario ofrece quitar. Se oculta desde el menú ⋮ y la
  /// preferencia persiste por perfil.
  Widget _buildFavoritesBar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('browser-favorites-bar'),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _bookmarkEntries.length,
          separatorBuilder: (_, __) => const SizedBox(width: 2),
          itemBuilder: (context, index) {
            final bookmark = _bookmarkEntries[index];
            final title =
                bookmark.title.trim().isEmpty ? bookmark.host : bookmark.title;
            return Tooltip(
              message: bookmark.url,
              waitDuration: const Duration(milliseconds: 600),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => unawaited(_loadAddress(bookmark.url)),
                onSecondaryTapDown: (details) => unawaited(
                  _showFavoriteContextMenu(context, details, bookmark),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.public,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showFavoriteContextMenu(
    BuildContext context,
    TapDownDetails details,
    _BrowserBookmarkEntry bookmark,
  ) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    _transientMenuOpen = true;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'open', child: Text('Abrir')),
        PopupMenuItem(value: 'remove', child: Text('Quitar de favoritos')),
      ],
    );
    _transientMenuOpen = false;
    switch (action) {
      case 'open':
        await _loadAddress(bookmark.url);
      case 'remove':
        await _removeBookmarkEntry(bookmark);
    }
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
          final isHighlighted = index == _highlightedSuggestionIndex;
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => unawaited(_openAddressSuggestion(suggestion)),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: isHighlighted
                      ? theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.45)
                      : null,
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

enum _AliExpressImportMode { preview, directToOcr }

class _AliExpressImportRequest {
  const _AliExpressImportRequest({
    required this.date,
    required this.mode,
  });

  final DateTime date;
  final _AliExpressImportMode mode;
}

class _AliExpressInvoicePreviewDialog extends StatelessWidget {
  const _AliExpressInvoicePreviewDialog({
    required this.bytes,
    required this.fileName,
    required this.invoice,
  });

  final Uint8List bytes;
  final String fileName;
  final Map<String, dynamic> invoice;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = (screen.width - 32).clamp(0.0, 1180.0).toDouble();
    final dialogHeight = (screen.height - 32).clamp(0.0, 900.0).toDouble();
    final rawOrders = invoice['sourceOrders'];
    final rawItems = invoice['items'];
    final orderCount = rawOrders is List ? rawOrders.length : 0;
    final itemCount = rawItems is List ? rawItems.length : 0;
    final total = invoice['total'] is num
        ? (invoice['total'] as num).round()
        : num.tryParse('${invoice['total']}')?.round() ?? 0;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Container(
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.picture_as_pdf_outlined,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preview de factura AliExpress',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$orderCount pedidos · $itemCount líneas · \$$total CLP',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar preview',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Expanded(
              child: PdfPreview(
                build: (_) async => bytes,
                useActions: false,
                allowPrinting: false,
                allowSharing: false,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                pdfFileName: fileName,
                maxPageWidth: 1500,
                scrollViewDecoration: const BoxDecoration(
                  color: Color(0xFFE5E7EB),
                ),
                loadingWidget: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Container(
              color: theme.colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final actions = Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Volver a AliExpress'),
                      ),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.document_scanner_outlined,
                            size: 18),
                        label: const Text('Enviar al OCR'),
                      ),
                    ],
                  );
                  final status = Text(
                    'Solo se enviará al OCR cuando lo confirmes.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                  if (constraints.maxWidth < 620) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        status,
                        const SizedBox(height: 10),
                        actions,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: status),
                      const SizedBox(width: 16),
                      actions,
                    ],
                  );
                },
              ),
            ),
          ],
        ),
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

enum _BrowserPermissionDecision {
  denyOnce,
  denyAlways,
  allowOnce,
  allowAlways,
}

enum _BrowserMenuAction {
  // Sólo aparecen en compacto: en escritorio son botones propios de la barra.
  reload,
  forward,
  home,
  toggleBookmark,
  recent,
  bookmarks,
  favoritesBar,
  forgetSiteCredentials,
  clearData,
  openInChrome,
  openExternal,
}

enum _BrowserAddressSiteSource { visited, supplier }

class _BrowserAddressSiteCandidate {
  const _BrowserAddressSiteCandidate({
    required this.host,
    required this.title,
    required this.url,
    required this.source,
    required this.visitCount,
    required this.lastVisitedAt,
  });

  factory _BrowserAddressSiteCandidate.visited(
    BrowserSiteMemoryEntry entry,
  ) {
    return _BrowserAddressSiteCandidate(
      host: entry.host,
      title: entry.title,
      url: entry.lastUrl,
      source: _BrowserAddressSiteSource.visited,
      visitCount: entry.visitCount,
      lastVisitedAt: entry.lastVisitedAt,
    );
  }

  factory _BrowserAddressSiteCandidate.supplier(
    BrowserSupplierPortalEntry entry,
  ) {
    return _BrowserAddressSiteCandidate(
      host: entry.host,
      title: entry.supplierName,
      url: entry.url,
      source: _BrowserAddressSiteSource.supplier,
      visitCount: 0,
      lastVisitedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String host;
  final String title;
  final String url;
  final _BrowserAddressSiteSource source;
  final int visitCount;
  final DateTime lastVisitedAt;
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

  factory _BrowserAddressSuggestion.addressSite(
    _BrowserAddressSiteCandidate entry,
  ) {
    final isSupplier = entry.source == _BrowserAddressSiteSource.supplier;
    return _BrowserAddressSuggestion._(
      label: normalizeBrowserHostForMatch(entry.host),
      subtitle: entry.title,
      value: entry.url,
      icon: isSupplier ? Icons.storefront_outlined : Icons.language,
      badge: isSupplier
          ? 'Proveedor'
          : entry.visitCount > 1
              ? 'Visitado ${entry.visitCount}×'
              : 'Visitado',
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
