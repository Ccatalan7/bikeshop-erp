import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:io' show Platform;

/// WhatsApp Web Viewer - Opens WhatsApp Web in a WebView
/// Allows sending messages without leaving the app
class WhatsAppWebViewer extends StatefulWidget {
  final String phoneNumber; // Chilean format: 56912345678
  final String message; // Pre-filled message

  const WhatsAppWebViewer({
    super.key,
    required this.phoneNumber,
    required this.message,
  });

  @override
  State<WhatsAppWebViewer> createState() => _WhatsAppWebViewerState();
}

class _WhatsAppWebViewerState extends State<WhatsAppWebViewer> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    final encodedMessage = Uri.encodeComponent(widget.message);
    final whatsappUrl =
        'https://web.whatsapp.com/send?phone=${widget.phoneNumber}&text=$encodedMessage';
    final backgroundColor =
        Platform.isMacOS ? Colors.white : const Color(0x00000000);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(backgroundColor)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading state
            if (progress == 100) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            print('❌ WebView Error: ${error.description}');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${error.description}')),
            );
          },
          onNavigationRequest: (NavigationRequest request) {
            // Allow all navigation within WhatsApp Web
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(whatsappUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp'),
        backgroundColor: const Color(0xFF25D366), // WhatsApp green
        foregroundColor: Colors.white,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _controller.reload();
            },
            tooltip: 'Recargar',
          ),
          // Help button
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              _showHelpDialog();
            },
            tooltip: 'Ayuda',
          ),
        ],
      ),
      body: Stack(
        children: [
          // WebView
          WebViewWidget(controller: _controller),

          // Loading indicator
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      color: Color(0xFF25D366),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Cargando WhatsApp Web...',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Escanea el código QR con tu teléfono',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      // Floating help button for mobile
      floatingActionButton: Platform.isAndroid || Platform.isIOS
          ? FloatingActionButton.extended(
              onPressed: _showMobileInstructions,
              backgroundColor: const Color(0xFF25D366),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.help),
              label: const Text('¿Cómo usar?'),
            )
          : null,
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cómo usar WhatsApp Web'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pasos:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 12),
              Text('1. Abre WhatsApp en tu teléfono'),
              SizedBox(height: 8),
              Text('2. Toca Menú (⋮) o Configuración'),
              SizedBox(height: 8),
              Text('3. Selecciona "Dispositivos vinculados"'),
              SizedBox(height: 8),
              Text('4. Toca "Vincular dispositivo"'),
              SizedBox(height: 8),
              Text('5. Escanea el código QR en esta pantalla'),
              SizedBox(height: 12),
              Text(
                'El mensaje ya está pre-llenado. Solo debes enviarlo.',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _showMobileInstructions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                const Text(
                  '¿Cómo usar WhatsApp Web?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              '📱 Desde tu teléfono con WhatsApp:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            const Text('1. Abre WhatsApp'),
            const Text('2. Ve a Configuración → Dispositivos vinculados'),
            const Text('3. Toca "Vincular dispositivo"'),
            const Text('4. Escanea el código QR de esta pantalla'),
            const SizedBox(height: 20),
            const Text(
              '✨ El mensaje ya está listo para enviar',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                ),
                child: const Text('Entendido'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
