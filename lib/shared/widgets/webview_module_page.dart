import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Persistent WebView Page - Loads a website as a permanent module
/// Perfect for WhatsApp Web, dashboards, web tools, etc.
/// 
/// **Platform Support:**
/// - ✅ Windows, macOS, Linux: Native WebView
/// - ✅ Android, iOS: Native WebView
/// - ⚠️ Web: Shows link to open in new tab (WebView not supported)
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
  WebViewController? _controller; // Nullable - only initialized on non-web platforms
  bool _isLoading = true;
  String _currentUrl = '';
  String? _pageTitle;

  // Keep the WebView alive when switching tabs
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Only initialize WebView on non-web platforms
    if (!kIsWeb) {
      _initializeWebView();
    }
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Skip setBackgroundColor on macOS - setOpaque() not implemented
      // ..setBackgroundColor(const Color(0x00000000))
      // Set Chrome user agent for WhatsApp Web compatibility
      ..setUserAgent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
            });
            
            // Force Chrome user agent via JavaScript injection
            _controller?.runJavaScript('''
              Object.defineProperty(navigator, 'userAgent', {
                get: function() { 
                  return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
                }
              });
            ''');
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
            });
            
            // Also inject after page loads (double insurance)
            _controller?.runJavaScript('''
              Object.defineProperty(navigator, 'userAgent', {
                get: function() { 
                  return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
                }
              });
            ''');
            
            // Get page title
            _controller?.getTitle().then((title) {
              if (title != null && mounted) {
                setState(() {
                  _pageTitle = title;
                });
              }
            });
          },
          onWebResourceError: (WebResourceError error) {
            print('❌ WebView Error: ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            // Allow all navigation
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    // ⚠️ WebView doesn't work on web platform
    if (kIsWeb) {
      return _buildWebPlatformAlternative(context);
    }
    
    return Column(
      children: [
        // Top bar with controls
        _buildTopBar(context),
        // WebView
        Expanded(
          child: Stack(
            children: [
              if (_controller != null) WebViewWidget(controller: _controller!),
              // Loading indicator
              if (_isLoading)
                Container(
                  color: Colors.white,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: widget.iconColor ?? Theme.of(context).primaryColor,
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

  /// Alternative UI for web platform (WebView not supported)
  Widget _buildWebPlatformAlternative(BuildContext context) {
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
                const Text(
                  'Los módulos WebView no están disponibles en la versión web de la aplicación.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Para usar esta función, ejecuta la aplicación en Windows, macOS, o descarga la app móvil.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'Mientras tanto, puedes abrir este sitio en una nueva pestaña:',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    final url = Uri.parse(widget.url);
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Abrir en Nueva Pestaña'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  widget.url,
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
          // Website icon
          Icon(
            widget.icon,
            color: widget.iconColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          // Page title or URL
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
                    Uri.parse(_currentUrl).host,
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
          // Navigation buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Back button
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: _controller == null ? null : () async {
                  if (await _controller!.canGoBack()) {
                    _controller!.goBack();
                  }
                },
                tooltip: 'Atrás',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              // Forward button
              IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: _controller == null ? null : () async {
                  if (await _controller!.canGoForward()) {
                    _controller!.goForward();
                  }
                },
                tooltip: 'Adelante',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              // Reload button
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                onPressed: _controller == null ? null : () {
                  _controller!.reload();
                },
                tooltip: 'Recargar',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              // Home button (go back to initial URL)
              IconButton(
                icon: const Icon(Icons.home, size: 20),
                onPressed: _controller == null ? null : () {
                  _controller!.loadRequest(Uri.parse(widget.url));
                },
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
