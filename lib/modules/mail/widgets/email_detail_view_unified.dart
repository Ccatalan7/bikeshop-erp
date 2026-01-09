import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/email_provider.dart';

/// Email detail view for unified inbox
class EmailDetailViewUnified extends StatelessWidget {
  final Email email;
  final EmailProvider? provider;
  final bool isLoading;
  final String? error;
  final VoidCallback? onClose;
  final VoidCallback onRetry;
  final VoidCallback? onReply;
  final VoidCallback? onReplyAll;
  final VoidCallback? onDelete;

  const EmailDetailViewUnified({
    super.key,
    required this.email,
    this.provider,
    required this.isLoading,
    this.error,
    this.onClose,
    required this.onRetry,
    this.onReply,
    this.onReplyAll,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show error state
    if (error != null && !isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('Error al cargar el contenido',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              error!.contains('404')
                  ? 'No se pudo encontrar el contenido del mensaje.'
                  : error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    // Loading content
    if (isLoading && email.content == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: onClose != null
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onClose,
              ),
              title: _ProviderBadge(providerId: email.providerId),
              actions: _buildActions(context),
            )
          : null,
      body: Column(
        children: [
          // Desktop toolbar
          if (onClose == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _ProviderBadge(providerId: email.providerId),
                  const Spacer(),
                  ..._buildActions(context),
                ],
              ),
            ),
          if (onClose == null) const Divider(height: 1),

          // Metadata Header (Fixed)
          Container(
            padding: const EdgeInsets.all(16),
            color: colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject
                Text(
                  email.subject,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                // Sender info
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _getProviderColor(email.providerId),
                      child: Text(
                        email.senderName.isNotEmpty
                            ? email.senderName[0].toUpperCase()
                            : '?',
                        style:
                            const TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  email.senderName,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  '<${email.senderEmail}>',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'para ${email.toAddress}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      DateFormat('d MMM, HH:mm', 'es')
                          .format(email.receivedTime),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Email Content (WebView takes remaining space)
          Expanded(
            child: _EmailContentRenderer(
              html: email.content ?? email.summary ?? 'Sin contenido.',
            ),
          ),
        ],
      ),
    );
  }

  Color _getProviderColor(String providerId) {
    if (providerId.contains('gmail')) return Colors.red;
    if (providerId.contains('zoho')) return Colors.blue;
    return Colors.grey;
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      if (onReply != null)
        IconButton(
          icon: const Icon(Icons.reply),
          onPressed: onReply,
          tooltip: 'Responder',
        ),
      if (onReplyAll != null)
        IconButton(
          icon: const Icon(Icons.reply_all),
          onPressed: onReplyAll,
          tooltip: 'Responder a todos',
        ),
      if (onDelete != null)
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: onDelete,
          tooltip: 'Eliminar',
        ),
    ];
  }
}

class _ProviderBadge extends StatelessWidget {
  final String providerId;

  const _ProviderBadge({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _getIcon(),
          const SizedBox(width: 4),
          Text(
            _getLabel(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _getColor(),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor() {
    switch (providerId) {
      case 'gmail':
        return Colors.red;
      case 'zoho':
        return const Color(0xFF2B579A); // Zoho blue
      default:
        return Colors.blue;
    }
  }

  Widget _getIcon() {
    switch (providerId) {
      case 'gmail':
        return Image.asset(
          'assets/icons/gmail_logo.webp',
          width: 16,
          height: 16,
        );
      case 'zoho':
        return Image.asset(
          'assets/icons/zoho_logo.png',
          width: 16,
          height: 16,
        );
      default:
        return const Icon(Icons.email_outlined, size: 14);
    }
  }

  String _getLabel() {
    switch (providerId) {
      case 'gmail':
        return 'Gmail';
      case 'zoho':
        return 'Zoho';
      default:
        return 'Email';
    }
  }
}

/// Email content renderer using WebView for Gmail/Outlook quality HTML rendering
class _EmailContentRenderer extends StatefulWidget {
  final String html;

  const _EmailContentRenderer({required this.html});

  @override
  State<_EmailContentRenderer> createState() => _EmailContentRendererState();
}

class _EmailContentRendererState extends State<_EmailContentRenderer> {
  late final WebViewController _controller;
  bool _isReady = false;
  String _lastLoadedHtml = '';

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _isReady = true);
            },
            onNavigationRequest: (request) {
              // Block external navigation, open in browser instead
              return NavigationDecision.prevent;
            },
          ),
        );
      _loadContent();
    }
  }

  @override
  void didUpdateWidget(covariant _EmailContentRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload WebView if content changes (async content loading)
    if (widget.html != oldWidget.html && widget.html != _lastLoadedHtml) {
      _loadContent();
    }
  }

  void _loadContent() {
    _lastLoadedHtml = widget.html;
    _isReady = false;
    _controller.loadHtmlString(_buildFullHtml(widget.html));
  }

  String _buildFullHtml(String emailContent) {
    // Minimal CSS - preserve email's original styling (like Gmail/Outlook do)
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0">
  <style>
    /* Minimal resets only - don't override email styles */
    html { height: 100%; }
    body { 
      margin: 0; 
      padding: 0;
      min-height: 100%;
      background: #fff;
    }
    /* Only fix responsive images, don't touch anything else */
    img { max-width: 100% !important; height: auto !important; }
  </style>
</head>
<body>
$emailContent
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    // Fallback for web platform
    if (kIsWeb) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: HtmlWidget(widget.html),
      );
    }

    // WebView fills the Expanded container and handles its own scrolling
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (!_isReady)
          Container(
            color: Colors.white,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
