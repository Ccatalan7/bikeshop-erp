import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/mail/utils/email_link_transform.dart';
import 'package:vinabike_erp/modules/mail/widgets/compose_email_dialog.dart';

void main() {
  test('mail recipient validation accepts lists and rejects malformed input',
      () {
    expect(isValidMailRecipientList('cliente@example.com'), isTrue);
    expect(
      isValidMailRecipientList(
        'cliente@example.com; taller@example.cl, ventas@example.org',
      ),
      isTrue,
    );
    expect(isValidMailRecipientList('cliente@'), isFalse);
    expect(isValidMailRecipientList(''), isFalse);
    expect(isValidMailRecipientList('', allowEmpty: true), isTrue);
  });

  test('mail route and every responsive host use the canonical workspace', () {
    final router = File('lib/shared/routes/app_router.dart').readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(router, contains("path: '/mail'"));
    expect(router, contains('const mail.MailInboxPage()'));
    expect(registry, contains('## Email Workspace Surfaces'));
    expect(registry, contains('Unified inbox desktop'));
    expect(registry, contains('Unified inbox compact/mobile'));
    expect(registry, contains('Compose and reply'));
    expect(registry, contains('Message body and attachments'));
  });

  test('inbox preserves provider context and safe responsive actions', () {
    final page = File(
      'lib/modules/mail/pages/mail_inbox_page.dart',
    ).readAsStringSync();
    final manager = File(
      'lib/modules/mail/providers/mail_account_manager.dart',
    ).readAsStringSync();
    expect(page, contains('_desktopSplitMinWidth = 1120'));
    expect(page, contains('_inboxStatusRowHeight = 32'));
    expect(page, contains('height: _inboxStatusRowHeight'));
    expect(page, contains('MaterialTapTargetSize.shrinkWrap'));
    expect(page, contains('_buildAccountFilterControl()'));
    expect(page, contains('Ajustar ancho de la lista de correos'));
    expect(page, contains('_confirmDeleteSelectedEmail'));
    expect(page, contains('initialProviderId: email.providerId'));
    expect(page, contains("label: const Text('Redactar')"));
    expect(manager, contains('_selectedEmail?.providerId != providerId'));
    expect(manager, contains('_selectionRequestId++'));
    expect(manager, contains('final failedProviders = <EmailProvider>[]'));
    expect(manager, contains('final hadSenderIdentityFailure ='));
    expect(manager, contains('if (hadSenderIdentityFailure)'));
    expect(manager, contains('_error = null;'));
    expect(
        manager, contains('_providerFailureMessage(\n        failedProviders'));
    expect(
      manager,
      isNot(contains('await Future.wait(\n        providersToRefresh')),
    );
  });

  test('compose and message rendering retain the shared safety contract', () {
    final compose = File(
      'lib/modules/mail/widgets/compose_email_dialog.dart',
    ).readAsStringSync();
    final detail = File(
      'lib/modules/mail/widgets/email_detail_view_unified.dart',
    ).readAsStringSync();
    final zoho = File(
      'lib/modules/mail/providers/zoho_provider.dart',
    ).readAsStringSync();

    expect(compose, contains('widget.initialProviderId'));
    expect(compose, contains('sender.identity.address'));
    expect(compose, contains('refreshSenderIdentities()'));
    expect(compose, contains("'Desde:'"));
    expect(compose, contains("'CCO:'"));
    expect(compose, contains('bcc: _bccController.text.trim()'));
    expect(compose, contains('onPressed: _canSend ? _send : null'));
    expect(compose, contains('_requestClose'));
    expect(zoho, contains("body: {'action': 'sender_identities'}"));
    expect(zoho, isNot(contains("url: _accountUrl,\n        );")));
    expect(zoho, contains('resolveSenderIdentity(fromAddress)'));
    expect(zoho, contains("'fromAddress': sender.address"));
    expect(detail, contains('_emailBodyRendererVersion = 9'));
    expect(detail, contains('BoxConstraints(maxWidth: 960)'));
    expect(detail, contains("'overflow-wrap': 'break-word'"));
    expect(detail, contains('linkifyBareEmailUrls'));
    expect(detail, contains("path: '/tools/web'"));
    expect(detail, contains('openRouteInWorkspace(route)'));
    expect(detail, contains('Abrir en Planillas'));
    expect(detail, contains('SpreadsheetFileHandoffService.instance'));
    expect(detail, contains('.importBytes('));
    expect(detail, contains('Leyendo archivo...'));
    expect(detail, contains('Guardando planilla...'));
  });

  test('bare email URLs become visible links without nesting existing links',
      () {
    final linked = linkifyBareEmailUrls(
      'Para continuar: https://clientes.nic.cl/pago?id=8432751.',
    );
    expect(linked, contains('class="vinabike-auto-link"'));
    expect(
      linked,
      contains('href="https://clientes.nic.cl/pago?id=8432751"'),
    );
    expect(linked, endsWith('</a>.'));

    const existing = '<a href="https://clientes.nic.cl/pago">Pinche AQUÍ</a>';
    expect(linkifyBareEmailUrls(existing), existing);

    final gmailPlainText = linkifyBareEmailUrls(
      '<pre>https://clientes.nic.cl/restaurar?id=8432751</pre>',
    );
    expect(gmailPlainText, contains('class="vinabike-auto-link"'));
    expect(gmailPlainText, startsWith('<pre><a '));

    final encodedGmailPlainText = linkifyBareEmailUrls(
      '<pre>https:&#47;&#47;clientes.nic.cl/restaurar?id=8432751&amp;paso=1</pre>',
    );
    expect(encodedGmailPlainText, contains('class="vinabike-auto-link"'));
    expect(
      encodedGmailPlainText,
      contains(
        'href="https://clientes.nic.cl/restaurar?id=8432751&amp;paso=1"',
      ),
    );
  });

  test('email URL linkification does not alter attributes or script content',
      () {
    const content = '<div data-url="https://example.com/raw">Texto</div>'
        '<script>const url = "https://example.com/script";</script>';
    expect(linkifyBareEmailUrls(content), content);
  });
}
