import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/mail/providers/gmail_provider.dart';
import 'package:vinabike_erp/modules/mail/widgets/compose_email_dialog.dart';

void main() {
  test('authored text is escaped and quoted provider HTML is sanitized', () {
    final body = buildSafeOutboundMailBody(
      'Hola <script>alert(1)</script>\nPedido 42',
      quotedHtml: '''
        <div>Mensaje original</div>
        <script>EmailLinkBridge.postMessage('https://evil.example')</script>
        <img src="https://images.example/item.png" onerror="alert(1)">
      ''',
    );

    expect(
      body,
      contains('Hola &lt;script&gt;alert(1)&lt;&#47;script&gt;<br>'),
    );
    expect(body, contains('Pedido 42'));
    expect(body, contains('Mensaje original'));
    expect(body, isNot(contains('<script')));
    expect(body, isNot(contains('onerror')));
    expect(body, contains('https://images.example/item.png'));
  });

  test('Gmail MIME builder rejects header injection', () {
    expect(
      () => buildGmailRawMessage(
        to: 'receiver@example.com',
        from: 'sender@example.com',
        subject: 'Factura\r\nBcc: attacker@example.com',
        content: '<p>Body</p>',
      ),
      throwsFormatException,
    );
    expect(
      () => buildGmailRawMessage(
        to: 'receiver@example.com\nCc: attacker@example.com',
        from: 'sender@example.com',
        subject: 'Factura',
        content: '<p>Body</p>',
      ),
      throwsFormatException,
    );
  });

  test('Gmail MIME builder encodes non-ASCII subjects and declares MIME', () {
    final message = buildGmailRawMessage(
      to: 'receiver@example.com',
      from: 'sender@example.com',
      subject: 'Cotización bicicleta',
      content: '<p>Lista</p>',
    );
    final encodedSubject = base64.encode(utf8.encode('Cotización bicicleta'));

    expect(message, contains('Subject: =?UTF-8?B?$encodedSubject?='));
    expect(message, contains('MIME-Version: 1.0'));
    expect(message, contains('Content-Transfer-Encoding: 8bit'));
    expect(message, endsWith('<p>Lista</p>'));
  });

  test('Gmail replies carry RFC thread headers', () {
    final message = buildGmailRawMessage(
      to: 'receiver@example.com',
      from: 'sender@example.com',
      subject: 'Re: Pedido 42',
      content: '<p>Respuesta</p>',
      inReplyTo: '<message-42@example.com>',
      references: '<parent@example.com> <message-42@example.com>',
    );

    expect(message, contains('In-Reply-To: <message-42@example.com>'));
    expect(
      message,
      contains(
        'References: <parent@example.com> <message-42@example.com>',
      ),
    );
  });
}
