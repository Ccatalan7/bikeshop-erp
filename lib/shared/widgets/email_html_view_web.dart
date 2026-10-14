import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// The browser's own rendering of the email, in a frame that runs no script
/// and opens every link in a new tab.
class EmailHtmlView extends StatelessWidget {
  const EmailHtmlView({super.key, required this.html});

  final String html;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: HtmlElementView.fromTagName(
        // A new document is a new frame: srcdoc is read when it is created.
        key: ValueKey<String>(html),
        tagName: 'iframe',
        onElementCreated: (element) {
          final frame = element as web.HTMLIFrameElement;
          frame
            ..setAttribute(
              'sandbox',
              'allow-popups allow-popups-to-escape-sandbox',
            )
            ..srcdoc = _withLinksOutside(html).toJS
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%'
            ..style.backgroundColor = 'white';
        },
      ),
    );
  }
}

String _withLinksOutside(String html) {
  const base = '<base target="_blank">';
  final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
  if (head == null) return '$base$html';
  return html.replaceRange(head.end, head.end, base);
}
