import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as windows_webview;

/// Persistent WebView Page - Loads a website as a permanent module.
///
/// Platform support:
/// - Android, iOS, macOS: webview_flutter
/// - Windows: webview_windows (WebView2)
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
  static const _defaultUserAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const _windowsRuntimeUrl =
      'https://developer.microsoft.com/en-us/microsoft-edge/webview2/';

  WebViewController? _controller;
  windows_webview.WebviewController? _windowsController;
  final List<StreamSubscription<dynamic>> _windowsSubscriptions = [];

  bool _isLoading = true;
  String _currentUrl = '';
  String? _pageTitle;
  String? _platformMessage;
  bool _canGoBack = false;
  bool _canGoForward = false;

  @override
  bool get wantKeepAlive => true;

  bool get _usesFlutterWebView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  bool get _usesWindowsWebView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows;
  }

  @override
  void initState() {
    super.initState();
    if (_usesFlutterWebView) {
      _initializeFlutterWebView();
    } else if (_usesWindowsWebView) {
      unawaited(_initializeWindowsWebView());
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    for (final subscription in _windowsSubscriptions) {
      subscription.cancel();
    }
    if (_windowsController != null) {
      unawaited(_windowsController!.dispose());
    }
    super.dispose();
  }

  void _initializeFlutterWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_defaultUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (progress == 100 && mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });

            _controller?.runJavaScript('''
              Object.defineProperty(navigator, 'userAgent', {
                get: function() {
                  return '$_defaultUserAgent';
                }
              });
            ''');
          },
          onPageFinished: (url) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });

            _controller?.runJavaScript('''
              Object.defineProperty(navigator, 'userAgent', {
                get: function() {
                  return '$_defaultUserAgent';
                }
              });
            ''');

            _controller?.getTitle().then((title) {
              if (title != null && mounted) {
                setState(() {
                  _pageTitle = title;
                });
              }
            });
          },
          onWebResourceError: (error) {
            debugPrint('❌ WebView Error: ${error.description}');
          },
          onNavigationRequest: (_) => NavigationDecision.navigate,
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _initializeWindowsWebView() async {
    try {
      final runtimeVersion =
          await windows_webview.WebviewController.getWebViewVersion();

      if (!mounted) return;

      if (runtimeVersion == null) {
        setState(() {
          _platformMessage =
              'Microsoft Edge WebView2 Runtime no está instalado en este equipo.';
          _isLoading = false;
        });
        return;
      }

      final controller = windows_webview.WebviewController();
      await controller.initialize();
      await controller.setBackgroundColor(Colors.white);
      await controller.setPopupWindowPolicy(
        windows_webview.WebviewPopupWindowPolicy.sameWindow,
      );
      await controller.setUserAgent(_defaultUserAgent);

      _windowsSubscriptions.addAll([
        controller.url.listen((url) {
          if (!mounted) return;
          setState(() {
            _currentUrl = url;
          });
        }),
        controller.title.listen((title) {
          if (!mounted) return;
          setState(() {
            _pageTitle = title;
          });
        }),
        controller.loadingState.listen((state) {
          if (!mounted) return;
          setState(() {
            _isLoading = state == windows_webview.LoadingState.loading;
          });
        }),
        controller.historyChanged.listen((history) {
          if (!mounted) return;
          setState(() {
            _canGoBack = history.canGoBack;
            _canGoForward = history.canGoForward;
          });
        }),
        controller.onLoadError.listen((error) {
          debugPrint('❌ Windows WebView Error: $error');
        }),
      ]);

      await controller.loadUrl(widget.url);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _windowsController = controller;
        _platformMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _platformMessage =
            'No se pudo inicializar el portal embebido en Windows: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _goBack() async {
    if (_usesWindowsWebView) {
      if (_windowsController != null && _canGoBack) {
        await _windowsController!.goBack();
      }
      return;
    }

    if (_controller != null && await _controller!.canGoBack()) {
      await _controller!.goBack();
    }
  }

  Future<void> _goForward() async {
    if (_usesWindowsWebView) {
      if (_windowsController != null && _canGoForward) {
        await _windowsController!.goForward();
      }
      return;
    }

    if (_controller != null && await _controller!.canGoForward()) {
      await _controller!.goForward();
    }
  }

  Future<void> _reload() async {
    if (_usesWindowsWebView) {
      await _windowsController?.reload();
      return;
    }

    await _controller?.reload();
  }

  Future<void> _goHome() async {
    if (_usesWindowsWebView) {
      await _windowsController?.loadUrl(widget.url);
      return;
    }

    await _controller?.loadRequest(Uri.parse(widget.url));
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

    if (_usesFlutterWebView) {
      return _buildEmbeddedView(
        context,
        child: _controller == null
            ? const SizedBox.shrink()
            : WebViewWidget(controller: _controller!),
      );
    }

    if (_usesWindowsWebView) {
      if (_windowsController != null) {
        return _buildEmbeddedView(
          context,
          child: windows_webview.Webview(_windowsController!),
        );
      }

      if (_isLoading && _platformMessage == null) {
        return _buildLoadingPlaceholder(context, 'Inicializando portal...');
      }

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

    return _buildFallbackView(context);
  }

  Widget _buildEmbeddedView(
    BuildContext context, {
    required Widget child,
  }) {
    return Column(
      children: [
        _buildTopBar(context),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(child: child),
              if (_isLoading)
                Container(
                  color: Colors.white,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: widget.iconColor ??
                              Theme.of(context).primaryColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Cargando ${widget.title}...',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
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
        : defaultTargetPlatform == TargetPlatform.windows
            ? 'Windows'
            : defaultTargetPlatform == TargetPlatform.linux
                ? 'Linux'
                : 'esta plataforma';

    final effectiveActionUrl = actionUrl ?? widget.url;
    final effectiveMessage = message ??
        'Los módulos WebView no están disponibles en $unsupportedPlatformLabel.';

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
                Text(
                  _usesWindowsWebView
                      ? 'Si instalas WebView2, este portal quedará embebido también en Windows. En macOS se mantiene el WebView nativo actual.'
                      : 'Con la implementación actual, el portal embebido funciona en macOS, Android, iOS y Windows.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse(effectiveActionUrl);
                    if (await canLaunchUrl(uri)) {
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

  Widget _buildTopBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            widget.icon,
            color: widget.iconColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _pageTitle ?? widget.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_currentUrl.isNotEmpty)
                  Text(
                    _displayHost(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: (_usesWindowsWebView && !_canGoBack) ||
                        (!_usesWindowsWebView && _controller == null)
                    ? null
                    : _goBack,
                tooltip: 'Atrás',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: (_usesWindowsWebView && !_canGoForward) ||
                        (!_usesWindowsWebView && _controller == null)
                    ? null
                    : _goForward,
                tooltip: 'Adelante',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _controller == null && _windowsController == null
                    ? null
                    : _reload,
                tooltip: 'Recargar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.home, size: 20),
                onPressed: _controller == null && _windowsController == null
                    ? null
                    : _goHome,
                tooltip: 'Inicio',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
