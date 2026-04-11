import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
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

    // Mobile: Outlook-style architecture
    // 1. Native AppBar with subject
    // 2. Native sender header (Flutter widget)
    // 3. WebView for email body ONLY
    if (onClose != null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onClose,
          ),
          title: Text(
            email.subject,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          actions: _buildActions(context),
        ),
        body: Column(
          children: [
            // Native sender header - like Outlook
            _SenderHeader(email: email),
            // WebView with email body only
            Expanded(
              child: _EmailBodyWebView(email: email),
            ),
          ],
        ),
      );
    }

    // Desktop: Toolbar + Content
    return ColoredBox(
      color: colorScheme.surface,
      child: Column(
        children: [
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
          const Divider(height: 1),
          Expanded(
            child: Column(
              children: [
                _SenderHeader(email: email),
                Expanded(
                  child: _EmailBodyWebView(email: email),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
        color: _getColor().withValues(alpha: 0.1),
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
        return const Color(0xFF2B579A);
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
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.mail, size: 16, color: Colors.red),
        );
      case 'zoho':
        return Image.asset(
          'assets/icons/zoho_logo.png',
          width: 16,
          height: 16,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.business, size: 16, color: Color(0xFF2B579A)),
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

/// Native sender header widget - like Outlook/Gmail
class _SenderHeader extends StatelessWidget {
  final Email email;

  const _SenderHeader({required this.email});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final senderInitial =
        email.senderName.isNotEmpty ? email.senderName[0].toUpperCase() : '?';
    final avatarColor =
        email.providerId.contains('gmail') ? Colors.red : Colors.blue;

    final date = email.receivedTime;
    final dateStr =
        '${date.day} ${_monthName(date.month)}, ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: avatarColor,
            child: Text(
              senderInitial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Sender info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email.senderName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'para ${email.toAddress}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Date
          Text(
            dateStr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _monthName(int month) {
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic'
    ];
    return months[month - 1];
  }
}

/// WebView that renders ONLY the email body HTML (no sender info)
class _EmailBodyWebView extends StatefulWidget {
  final Email email;

  const _EmailBodyWebView({required this.email});

  @override
  State<_EmailBodyWebView> createState() => _EmailBodyWebViewState();
}

class _EmailBodyWebViewState extends State<_EmailBodyWebView> {
  late final WebViewController _controller;
  bool _isReady = false;
  String _lastLoadedContent = '';

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
              return NavigationDecision.prevent;
            },
          ),
        );
      _loadContent();
    }
  }

  @override
  void didUpdateWidget(covariant _EmailBodyWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newContent = widget.email.content ?? '';
    if (newContent != _lastLoadedContent && newContent.isNotEmpty) {
      _loadContent();
    }
  }

  void _loadContent() {
    _lastLoadedContent = widget.email.content ?? '';
    _controller.loadHtmlString(_buildBodyHtml());
  }

  String _buildBodyHtml() {
    final rawContent =
        widget.email.content ?? widget.email.summary ?? 'Sin contenido.';

    // Check if the email already has proper HTML structure
    final hasHtmlTag = rawContent.toLowerCase().contains('<html');
    final hasViewport = rawContent.toLowerCase().contains('viewport');

    if (hasHtmlTag && hasViewport) {
      // Email has its own HTML structure with viewport - use as-is
      // Inject CSS to fix common issues
      const injectedCss = '''<style>
html{margin:0!important;min-height:0!important;height:auto!important}
body{margin:0!important;padding:16px!important;min-height:0!important;height:auto!important}
img{max-width:100%!important;height:auto!important}
table[height="100%"],div[style*="height:100%"],td[height="100%"]{height:auto!important;min-height:0!important}
</style>''';

      return rawContent.replaceFirstMapped(
        RegExp(r'</head>', caseSensitive: false),
        (match) => '$injectedCss${match.group(0)}',
      );
    }

    // Email doesn't have proper structure - wrap minimally
    final content = _extractBodyInnerHtml(rawContent);
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body { margin: 0; padding: 8px; }
    img { max-width: 100% !important; height: auto !important; }
  </style>
</head>
<body>$content</body>
</html>
''';
  }

  String _extractBodyInnerHtml(String html) {
    final lower = html.toLowerCase();
    int start = lower.indexOf('<body');
    if (start != -1) {
      start = lower.indexOf('>', start) + 1;
      int end = lower.lastIndexOf('</body>');
      if (end != -1 && end > start) {
        return html.substring(start, end);
      }
    }
    return html
        .replaceAll(RegExp(r'<!doctype[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<html[^>]*>', caseSensitive: false), '')
        .replaceAll('</html>', '')
        .replaceAll(RegExp(r'<head>.*?</head>', dotAll: true), '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: HtmlWidget(widget.email.content ?? widget.email.summary ?? ''),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller),
        if (!_isReady)
          Container(
            color: colorScheme.surface,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}
