import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/mail/models/mail_folder.dart';
import 'package:vinabike_erp/modules/mail/providers/email_provider.dart';
import 'package:vinabike_erp/modules/mail/providers/gmail_provider.dart';
import 'package:vinabike_erp/modules/mail/providers/zoho_provider.dart';

void main() {
  Email gmailMail({required bool isRead}) {
    return Email(
      id: 'gmail-message-1',
      providerId: 'gmail',
      folderId: MailFolder.inbox.gmailLabelId,
      subject: 'Provider reconciliation',
      fromAddress: 'sender@example.com',
      toAddress: 'vinabike@example.com',
      receivedTime: DateTime(2026, 8, 13),
      isRead: isRead,
      hasAttachment: false,
    );
  }

  group('Gmail known-message metadata reconciliation', () {
    test('applies UNREAD added on another device', () {
      final reconciled = reconcileKnownGmailMetadata(
        gmailMail(isRead: true),
        const {
          'id': 'gmail-message-1',
          'known': true,
          'labelIds': ['INBOX', 'UNREAD'],
        },
        folder: MailFolder.inbox,
      );

      expect(reconciled.isRead, isFalse);
      expect(reconciled.folderId, MailFolder.inbox.gmailLabelId);
    });

    test('applies UNREAD removed on another device', () {
      final reconciled = reconcileKnownGmailMetadata(
        gmailMail(isRead: false),
        const {
          'id': 'gmail-message-1',
          'known': true,
          'labelIds': ['INBOX'],
        },
        folder: MailFolder.inbox,
      );

      expect(reconciled.isRead, isTrue);
    });

    test('preserves the cached state when labels are absent', () {
      final known = gmailMail(isRead: false);

      expect(
        reconcileKnownGmailMetadata(
          known,
          const {'id': 'gmail-message-1', 'known': true},
          folder: MailFolder.inbox,
        ),
        same(known),
      );
    });
  });

  group('Zoho read-state parsing', () {
    test('accepts every provider response shape used by the API', () {
      expect(parseZohoReadStatus(false), isFalse);
      expect(parseZohoReadStatus(0), isFalse);
      expect(parseZohoReadStatus('UNREAD'), isFalse);
      expect(parseZohoReadStatus('false'), isFalse);

      expect(parseZohoReadStatus(true), isTrue);
      expect(parseZohoReadStatus(1), isTrue);
      expect(parseZohoReadStatus('READ'), isTrue);
      expect(parseZohoReadStatus('true'), isTrue);
    });

    test('keeps the quiet legacy default for an omitted field', () {
      expect(parseZohoReadStatus(null), isTrue);
    });
  });
}
