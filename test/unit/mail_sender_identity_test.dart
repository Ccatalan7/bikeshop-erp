import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/mail/providers/email_provider.dart';
import 'package:vinabike_erp/modules/mail/providers/zoho_provider.dart';

void main() {
  group('Zoho sender identities', () {
    test('uses only sanitized server identities and keeps the primary first',
        () {
      final identities = parseZohoSenderIdentities(
        {
          'sender_identities': [
            {
              'address': 'ventas@vinabike.cl',
              'display_name': 'Ventas Viñabike',
            },
            {
              'address': 'CONTACTO@vinabike.cl',
              'display_name': 'Viñabike',
            },
            {
              'address': 'ventas@vinabike.cl',
              'display_name': 'Duplicado',
            },
            {'address': 'sin-formato'},
          ],
        },
        accountEmail: 'contacto@vinabike.cl',
      );

      expect(
        identities.map((identity) => identity.normalizedAddress),
        ['contacto@vinabike.cl', 'ventas@vinabike.cl'],
      );
      expect(identities.first.address, 'CONTACTO@vinabike.cl');
      expect(identities.last.displayName, 'Ventas Viñabike');
    });

    test('falls back to the authenticated mailbox when details are absent', () {
      final identities = parseZohoSenderIdentities(
        const {'sender_identities': <Object?>[]},
        accountEmail: 'contacto@vinabike.cl',
      );

      expect(identities, hasLength(1));
      expect(identities.single.address, 'contacto@vinabike.cl');
    });

    test('ignores malformed server entries instead of trusting their shape',
        () {
      final identities = parseZohoSenderIdentities(
        const {
          'sender_identities': [
            null,
            'ventas@vinabike.cl',
            {'address': 'sin-dominio@'},
            {'address': 'ventas@vinabike.cl', 'display_name': ''},
          ],
        },
        accountEmail: 'contacto@vinabike.cl',
      );

      expect(
        identities.map((identity) => identity.normalizedAddress),
        ['contacto@vinabike.cl', 'ventas@vinabike.cl'],
      );
    });
  });

  group('sender authorization', () {
    const identities = [
      EmailSenderIdentity(
        address: 'contacto@vinabike.cl',
        displayName: 'Viñabike',
      ),
      EmailSenderIdentity(
        address: 'ventas@vinabike.cl',
        displayName: 'Ventas Viñabike',
      ),
    ];

    test('returns the provider canonical address for a case-insensitive match',
        () {
      final resolved = resolveEmailSenderIdentity(
        identities,
        requestedAddress: ' VENTAS@VINABIKE.CL ',
      );

      expect(resolved?.address, 'ventas@vinabike.cl');
    });

    test('rejects an address not returned by the provider', () {
      final resolved = resolveEmailSenderIdentity(
        identities,
        requestedAddress: 'arbitrario@vinabike.cl',
      );

      expect(resolved, isNull);
    });

    test('uses the authenticated mailbox as the default identity', () {
      final resolved = resolveEmailSenderIdentity(
        identities,
        defaultAddress: 'contacto@vinabike.cl',
      );

      expect(resolved?.address, 'contacto@vinabike.cl');
    });
  });
}
