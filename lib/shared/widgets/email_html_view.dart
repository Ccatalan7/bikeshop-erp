import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// An email the ERP itself wrote (its HTML document), drawn the way a mail
/// app draws it: a real browser view where there is one (Android, iOS,
/// macOS) and the HTML widget elsewhere, like the Mail module's reader. For
/// a preview before sending (2026-10-13: the «va en camino» email). Links do
/// not navigate inside; they open outside, so the preview stays the preview.
class EmailHtmlView extends StatefulWidget {
  const EmailHtmlView({super.key, required this.html});

  final String html;

  @override
  State<EmailHtmlView> createState() => _EmailHtmlViewState();
}

class _EmailHtmlViewState extends State<EmailHtmlView> {
  WebViewController? _controller;
  bool _ready = false;

  // A test or a platform without a browser view draws the HTML widget.
  bool get _native =>
      !kIsWeb &&
      WebViewPlatform.instance != null &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  void initState() {
    super.initState();
    if (!_native) return;
    _controller = WebViewController()
      // No setBackgroundColor: macOS WKWebView throws «opaque is not
      // implemented» (2026-10-13); the white cover below hides the paint.
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _ready = true);
          },
          onNavigationRequest: (request) {
            if (request.url.startsWith('about:') ||
                request.url.startsWith('data:')) {
              return NavigationDecision.navigate;
            }
            unawaited(_openOutside(request.url));
            return NavigationDecision.prevent;
          },
        ),
      );
    _load();
  }

  @override
  void didUpdateWidget(covariant EmailHtmlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.html != widget.html && _controller != null) {
      setState(() => _ready = false);
      _load();
    }
  }

  void _load() {
    unawaited(_controller!.loadHtmlString(widget.html));
    // macOS WKWebView does not always report the end of a string load (the
    // Mail reader found it first): show the page shortly after anyway.
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      Future<void>.delayed(const Duration(milliseconds: 160), () {
        if (mounted && !_ready) setState(() => _ready = true);
      });
    }
  }

  Future<bool> _openOutside(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return ColoredBox(
        color: Colors.white,
        child: SingleChildScrollView(
          child: HtmlWidget(
            widget.html,
            onTapUrl: _openOutside,
            customStylesBuilder: (element) => switch (element.localName) {
              'table' => {'max-width': '100%'},
              'img' => {'max-width': '100%', 'height': 'auto'},
              _ => null,
            },
          ),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: controller),
        // White until the email paints, so the native view never flashes.
        if (!_ready) const ColoredBox(color: Colors.white),
      ],
    );
  }
}
