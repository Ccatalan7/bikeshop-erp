import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/trusted_meta_notification_url.dart';

void main() {
  group('trustedMetaNotificationUrl', () {
    test('accepts exact HTTPS Instagram and Facebook permalink hosts', () {
      expect(
        trustedMetaNotificationUrl(
          'https://www.instagram.com/p/example/?comment_id=123',
        ),
        isNotNull,
      );
      expect(
        trustedMetaNotificationUrl(
          'https://m.facebook.com/story.php?story_fbid=123',
        ),
        isNotNull,
      );
      expect(
        trustedMetaNotificationUrl('https://facebook.com/example'),
        isNotNull,
      );
    });

    test('rejects deceptive hosts, credentials, plaintext, and custom ports',
        () {
      expect(
        trustedMetaNotificationUrl('https://evilfacebook.com/example'),
        isNull,
      );
      expect(
        trustedMetaNotificationUrl('https://facebook.com.evil.test/example'),
        isNull,
      );
      expect(
        trustedMetaNotificationUrl('https://user@instagram.com/example'),
        isNull,
      );
      expect(
        trustedMetaNotificationUrl('http://www.instagram.com/example'),
        isNull,
      );
      expect(
        trustedMetaNotificationUrl('https://www.facebook.com:8443/example'),
        isNull,
      );
    });

    test('keeps internal ERP routes out of the external URL path', () {
      expect(trustedMetaNotificationUrl('/chat'), isNull);
      expect(
        trustedMetaNotificationUrl('/chat?conversation=conversation-id'),
        isNull,
      );
    });
  });
}
