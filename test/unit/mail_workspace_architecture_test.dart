import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
  });

  test('compose and message rendering retain the shared safety contract', () {
    final compose = File(
      'lib/modules/mail/widgets/compose_email_dialog.dart',
    ).readAsStringSync();
    final detail = File(
      'lib/modules/mail/widgets/email_detail_view_unified.dart',
    ).readAsStringSync();

    expect(compose, contains('widget.initialProviderId'));
    expect(compose, contains("'CCO:'"));
    expect(compose, contains('bcc: _bccController.text.trim()'));
    expect(compose, contains('onPressed: _canSend ? _send : null'));
    expect(compose, contains('_requestClose'));
    expect(detail, contains('_emailBodyRendererVersion = 8'));
    expect(detail, contains('BoxConstraints(maxWidth: 960)'));
    expect(detail, contains("'overflow-wrap': 'break-word'"));
    expect(detail, contains('Abrir en Planillas'));
    expect(detail, contains('SpreadsheetFileHandoffService.instance'));
    expect(detail, contains('.importBytes('));
    expect(detail, contains('Leyendo archivo...'));
    expect(detail, contains('Guardando planilla...'));
  });
}
