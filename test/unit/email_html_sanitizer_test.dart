import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/mail/utils/email_html_sanitizer.dart';

void main() {
  test('removes sender code before the native JavaScript bridge is installed',
      () {
    final sanitized = sanitizeEmailHtml('''
      <!doctype html>
      <html>
        <head>
          <meta http-equiv="refresh" content="0;url=https://evil.example">
          <script>EmailLinkBridge.postMessage('https://evil.example')</script>
        </head>
        <body onload="EmailKeyboardBridge.postMessage('1')">
          <iframe src="https://evil.example"></iframe>
          <object data="https://evil.example/payload"></object>
          <form action="https://evil.example"><input name="secret"></form>
          <img src="https://images.example/logo.png" onerror="alert(1)">
          <a href="javascript:alert(1)" ping="https://evil.example">bad</a>
          <button data-url="java&#x0a;script:alert(1)">bad button</button>
        </body>
      </html>
    ''').toLowerCase();

    expect(sanitized, isNot(contains('<script')));
    expect(sanitized, isNot(contains('<iframe')));
    expect(sanitized, isNot(contains('<object')));
    expect(sanitized, isNot(contains('<form')));
    expect(sanitized, isNot(contains('http-equiv')));
    expect(sanitized, isNot(contains('onload')));
    expect(sanitized, isNot(contains('onerror')));
    expect(sanitized, isNot(contains('javascript:')));
    expect(sanitized, isNot(contains(' ping=')));
    expect(sanitized, contains('https://images.example/logo.png'));
  });

  test('preserves ordinary email layout, links, and safe inline images', () {
    final sanitized = sanitizeEmailHtml('''
      <table style="width: 100%"><tr><td>Pedido 42</td></tr></table>
      <a href="https://vinabike.cl/order/42" target="_blank">Abrir</a>
      <img src="cid:logo-1">
      <img src="data:image/png;base64,AAAA">
    ''');

    expect(sanitized, contains('<table style="width: 100%">'));
    expect(sanitized, contains('Pedido 42'));
    expect(sanitized, contains('https://vinabike.cl/order/42'));
    expect(sanitized, contains('rel="noopener noreferrer"'));
    expect(sanitized, contains('src="cid:logo-1"'));
    expect(sanitized, contains('src="data:image/png;base64,AAAA"'));
  });

  test('rejects active data documents and unsafe CSS', () {
    final sanitized = sanitizeEmailHtml('''
      <a href="data:text/html;base64,PHNjcmlwdD4=">document</a>
      <img src="data:image/svg+xml,<svg onload='alert(1)'>">
      <div style="background:url(javascript:alert(1))">content</div>
      <style>@import 'https://evil.example/tracker.css';</style>
    ''').toLowerCase();

    expect(sanitized, isNot(contains('data:text/html')));
    expect(sanitized, isNot(contains('data:image/svg')));
    expect(sanitized, isNot(contains('javascript:')));
    expect(sanitized, isNot(contains('@import')));
    expect(sanitized, contains('content'));
  });
}
