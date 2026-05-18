import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/window_zoom_service.dart';

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

  InAppWebViewController? _controller;
  WebViewEnvironment? _webViewEnvironment;
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();
  bool _selectAllOnNextFocus = false;

  Uri? _initialUri;
  bool _isInitializing = true;
  bool _isLoading = true;
  int _loadingProgress = 0;
  String _currentUrl = '';
  String? _pageTitle;
  String? _platformMessage;
  String? _lastErrorMessage;
  bool _canGoBack = false;
  bool _canGoForward = false;
  double? _lastAppliedBrowserZoom;
  double? _pendingBrowserZoom;

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
        databaseEnabled: true,
        domStorageEnabled: true,
        geolocationEnabled: true,
        hardwareAcceleration: true,
        horizontalScrollBarEnabled: true,
        iframeAllow:
            'camera; microphone; geolocation; clipboard-read; clipboard-write; fullscreen; payment',
        iframeAllowFullscreen: true,
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
    unawaited(_prepareBrowser());
  }

  @override
  void dispose() {
    unawaited(_webViewEnvironment?.dispose());
    _addressController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
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

    if (!_usesNativeBrowser) {
      _finishInitialization(loading: false);
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

        _webViewEnvironment = await WebViewEnvironment.create();
      }

      _finishInitialization(loading: true);
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

  Future<void> _goBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
    }
  }

  Future<void> _goForward() async {
    final controller = _controller;
    if (controller != null && await controller.canGoForward()) {
      await controller.goForward();
    }
  }

  Future<void> _reload() async {
    await _controller?.reload();
  }

  Future<void> _goHome() async {
    final uri = _initialUri ?? _normalizeAddress(widget.url);
    if (uri == null) return;
    await _loadUri(uri);
  }

  Future<void> _loadAddress(String input) async {
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
    if (!_canLoadInsideWebView(uri)) {
      await _openExternalUrl(uri.toString());
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingProgress = 0;
      _lastErrorMessage = null;
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

  void _setCurrentUrl(WebUri? url) {
    if (url == null) return;
    final value = url.toString();
    if (value.isEmpty) return;
    setState(() {
      _currentUrl = value;
    });
    _syncAddressField(value);
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
        description.contains('error -999');
  }

  Future<NavigationActionPolicy> _handleNavigation(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    final url = navigationAction.request.url;
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

    final initialUri = _initialUri;
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

    return _buildEmbeddedView(
      context,
      child: _NativeBrowserZoomBoundary(
        appScale: browserZoom,
        child: InAppWebView(
          key: ValueKey('browser-${widget.url}'),
          webViewEnvironment: _webViewEnvironment,
          initialUrlRequest: _urlRequest(initialUri),
          initialSettings: _browserSettings(browserZoom),
          onWebViewCreated: (controller) {
            _controller = controller;
            unawaited(_applyBrowserZoom(browserZoom));
            unawaited(_refreshNavigationState());
          },
          onLoadStart: (controller, url) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _loadingProgress = 0;
              _lastErrorMessage = null;
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
            if (mounted) setState(() {});
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
            unawaited(_openExternalUrl(request.url.toString()));
          },
          onConsoleMessage: (controller, consoleMessage) {
            debugPrint('🌐 Web workspace: ${consoleMessage.message}');
          },
        ),
      ),
    );
  }

  Widget _buildEmbeddedView(
    BuildContext context, {
    required Widget child,
  }) {
    return Column(
      children: [
        _buildTopBar(context),
        if (_lastErrorMessage != null) _buildErrorBanner(context),
        Expanded(child: child),
      ],
    );
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
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapDown: (details) {
                        // If field not focused, request focus and mark to select-all
                        if (!_addressFocusNode.hasFocus) {
                          _selectAllOnNextFocus = true;
                          _addressFocusNode.requestFocus();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_selectAllOnNextFocus &&
                                _addressFocusNode.hasFocus) {
                              _addressController.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: _addressController.text.length,
                              );
                              _selectAllOnNextFocus = false;
                            }
                          });
                        }
                      },
                      child: TextField(
                        controller: _addressController,
                        focusNode: _addressFocusNode,
                        enabled: canUseWebView,
                        selectAllOnFocus: true,
                        textInputAction: TextInputAction.go,
                        keyboardType: TextInputType.url,
                        onTap: () {
                          // Ensure select-all wins if focus was just given
                          if (_selectAllOnNextFocus) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_addressFocusNode.hasFocus) {
                                _addressController.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset: _addressController.text.length,
                                );
                              }
                              _selectAllOnNextFocus = false;
                            });
                          }
                        },
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
                                  icon:
                                      const Icon(Icons.arrow_forward, size: 18),
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
