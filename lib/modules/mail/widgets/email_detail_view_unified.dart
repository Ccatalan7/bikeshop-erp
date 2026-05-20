import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../providers/email_provider.dart';
import 'mail_error_diagnostic_banner.dart';

/// Email detail view for unified inbox
class EmailDetailViewUnified extends StatelessWidget {
  final Email email;
  final EmailProvider? provider;
  final bool isLoading;
  final String? error;
  final VoidCallback? onClose;
  final VoidCallback onRetry;
  final VoidCallback? onToggleRead;
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
    this.onToggleRead,
    this.onReply,
    this.onReplyAll,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
            _SubjectHeader(email: email),
            // Native sender header - like Outlook
            _SenderHeader(email: email),
            // WebView with email body only
            Expanded(
              child: _EmailBodyPane(
                email: email,
                isLoading: isLoading,
                error: error,
                onRetry: onRetry,
              ),
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
                _SubjectHeader(email: email),
                _SenderHeader(email: email),
                Expanded(
                  child: _EmailBodyPane(
                    email: email,
                    isLoading: isLoading,
                    error: error,
                    onRetry: onRetry,
                  ),
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
      if (onToggleRead != null)
        IconButton(
          icon: Icon(
            email.isRead
                ? Icons.mark_email_unread_outlined
                : Icons.mark_email_read_outlined,
          ),
          onPressed: onToggleRead,
          tooltip: email.isRead ? 'Marcar como no leído' : 'Marcar como leído',
        ),
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

class _SubjectHeader extends StatelessWidget {
  final Email email;

  const _SubjectHeader({required this.email});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      color: theme.colorScheme.surface,
      child: Text(
        email.subject.isEmpty ? '(sin asunto)' : email.subject,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
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
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 19,
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        email.senderName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        email.senderEmail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Para: ${email.toAddress}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
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

class _EmailBodyPane extends StatelessWidget {
  final Email email;
  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;

  const _EmailBodyPane({
    required this.email,
    required this.isLoading,
    required this.error,
    required this.onRetry,
  });

  bool get _hasContent => email.content?.trim().isNotEmpty ?? false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (error != null && !_hasContent) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: colorScheme.error),
              const SizedBox(height: 14),
              Text(
                'No se pudo cargar el mensaje',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              MailErrorDiagnosticBanner(
                message: error!.contains('404')
                    ? 'No se pudo encontrar el contenido del mensaje.'
                    : error!,
                compact: false,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (isLoading && !_hasContent) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(
              'Cargando mensaje...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (!_hasContent) {
      return Center(
        child: Text(
          'Este mensaje no tiene contenido.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Stack(
      children: [
        _EmailBodyWebView(email: email),
        if (isLoading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
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
  WebViewController? _controller;
  bool _isReady = false;
  String _lastLoadedContent = '';
  int _loadGeneration = 0;

  bool get _useNativeWebView =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    if (_useNativeWebView) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (mounted) setState(() => _isReady = true);
            },
            onNavigationRequest: (request) {
              // Allow initial about:blank / data loads; block external link navigation
              if (request.url.startsWith('about:') ||
                  request.url.startsWith('data:')) {
                return NavigationDecision.navigate;
              }
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
    final generation = ++_loadGeneration;
    _lastLoadedContent = widget.email.content ?? '';
    if (_isReady) setState(() => _isReady = false);
    _controller?.loadHtmlString(_buildBodyHtml());

    // macOS WKWebView doesn't reliably fire onPageFinished for loadHtmlString.
    // Keep a white surface briefly so the native view doesn't flash dark before
    // the email document paints, then reveal the already-loaded content.
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      Future<void>.delayed(const Duration(milliseconds: 140), () {
        if (mounted && generation == _loadGeneration) {
          setState(() => _isReady = true);
        }
      });
    }
  }

  String _buildBodyHtml() {
    final rawContent = widget.email.content ?? 'Sin contenido.';

    // Check if the email already has proper HTML structure
    final hasHtmlTag = rawContent.toLowerCase().contains('<html');
    final hasViewport = rawContent.toLowerCase().contains('viewport');

    if (hasHtmlTag && hasViewport) {
      // Email has its own HTML structure with viewport - use as-is
      // Inject CSS to fix common issues
      const injectedCss = '''<style>
    html{background:#ffffff!important;-webkit-text-size-adjust:100%}
    body{background:#ffffff!important;-webkit-text-size-adjust:100%}
    img{max-width:100%!important;height:auto!important}
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
    html, body {
      margin: 0;
      padding: 0;
      background: #ffffff;
      color: #242424;
      -webkit-text-size-adjust: 100%;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      font-size: 14px;
      line-height: 1.45;
    }
    #mail-reader {
      box-sizing: border-box;
      width: 100%;
      min-height: 100vh;
      padding: 24px 32px;
      background: #ffffff;
    }
    #mail-content {
      width: 100%;
      max-width: 760px;
      margin: 0 auto;
    }
    img { max-width: 100% !important; height: auto !important; }
    table { max-width: 100%; }
    pre { white-space: pre-wrap; word-wrap: break-word; }
  </style>
</head>
<body><div id="mail-reader"><div id="mail-content">$content</div></div></body>
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
    if (!_useNativeWebView) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: HtmlWidget(widget.email.content ?? ''),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: _controller!),
        if (!_isReady) const ColoredBox(color: Colors.white),
      ],
    );
  }
}
