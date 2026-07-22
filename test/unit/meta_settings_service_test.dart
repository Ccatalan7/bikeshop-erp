import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/settings/services/meta_settings_service.dart';

void main() {
  group('Meta settings service contract', () {
    test('accepts the exact versioned Meta OAuth contract', () {
      final valid = parseMetaAuthorizationUrl(_oauthPayload());

      expect(valid?.host, 'www.facebook.com');
      expect(valid?.path, '/v24.0/dialog/oauth');
      expect(valid?.queryParameters['client_id'], _clientId);
    });

    test('rejects non-HTTPS, foreign hosts, and custom ports', () {
      expect(
        parseMetaAuthorizationUrl(
          _oauthPayload(
            authorizationUrl: _authorizationUrl.replaceFirst(
              'https://',
              'http://',
            ),
          ),
        ),
        isNull,
      );
      expect(
        parseMetaAuthorizationUrl(
          _oauthPayload(
            authorizationUrl: _authorizationUrl.replaceFirst(
              'www.facebook.com',
              'evilfacebook.com',
            ),
          ),
        ),
        isNull,
      );
      expect(
        parseMetaAuthorizationUrl(
          _oauthPayload(
            authorizationUrl: _authorizationUrl.replaceFirst(
              'www.facebook.com',
              'login.facebook.com',
            ),
          ),
        ),
        isNull,
      );
      expect(
        parseMetaAuthorizationUrl(
          _oauthPayload(
            authorizationUrl: _authorizationUrl.replaceFirst(
              'www.facebook.com',
              'www.facebook.com.evil.example',
            ),
          ),
        ),
        isNull,
      );
      expect(
        parseMetaAuthorizationUrl(
          _oauthPayload(
            authorizationUrl: _authorizationUrl.replaceFirst(
              'www.facebook.com',
              'www.facebook.com:444',
            ),
          ),
        ),
        isNull,
      );
    });

    test('rejects logout and malformed or custom OAuth paths', () {
      for (final path in <String>[
        '/logout.php',
        '/dialog/oauth',
        '/v24/dialog/oauth',
        '/v24.0/dialog/oauth/',
        '/v24.0/dialog/custom',
      ]) {
        expect(
          parseMetaAuthorizationUrl(
            _oauthPayload(
              authorizationUrl: _authorizationUrl.replaceFirst(
                '/v24.0/dialog/oauth',
                path,
              ),
            ),
          ),
          isNull,
          reason: 'must reject $path',
        );
      }
    });

    test('rejects incomplete or mismatched OAuth parameters', () {
      expect(parseMetaAuthorizationUrl({'ok': true}), isNull);
      expect(
        parseMetaAuthorizationUrl(_oauthPayload(clientId: '9999')),
        isNull,
      );
      expect(
        parseMetaAuthorizationUrl(
          _oauthPayload(
            authorizationUrl: '$_authorizationUrl&client_id=$_clientId',
          ),
        ),
        isNull,
      );
      for (final queryParameter in <String>[
        'redirect_uri',
        'state',
        'response_type',
      ]) {
        final uri = Uri.parse(_authorizationUrl);
        final query = Map<String, String>.from(uri.queryParameters)
          ..remove(queryParameter);
        expect(
          parseMetaAuthorizationUrl(
            _oauthPayload(
              authorizationUrl: uri.replace(queryParameters: query).toString(),
            ),
          ),
          isNull,
          reason: 'must require $queryParameter',
        );
      }
      expect(
        parseMetaAuthorizationUrl(
          _oauthPayload(
            authorizationUrl: _authorizationUrl.replaceFirst(
              'response_type=code',
              'response_type=token',
            ),
          ),
        ),
        isNull,
      );
      expect(
        parseMetaAuthorizationUrl(
          _oauthPayload(
            authorizationUrl: _authorizationUrl.replaceFirst(
              Uri.encodeQueryComponent(_redirectUri),
              Uri.encodeQueryComponent('http://example.test/callback'),
            ),
          ),
        ),
        isNull,
      );
    });

    test('parses public channel status without credential material', () {
      final channels = parseMetaChannelRows([
        {
          'id': 'instagram-channel',
          'provider': 'instagram',
          'external_account_id': '17840000000000000',
          'display_name': 'Viñabike',
          'username': 'vina.bike',
          'granted_scopes': [
            'instagram_basic',
            'instagram_manage_messages',
          ],
          'token_expires_at': '2026-09-01T12:00:00Z',
          'subscribed_at': '2026-07-21T12:00:00Z',
          'updated_at': '2026-07-21T12:10:00Z',
          'is_active': true,
          'access_token': 'must-not-be-modeled',
        },
        {
          'id': 'unsupported',
          'provider': 'unknown_provider',
          'external_account_id': 'ignored',
          'is_active': true,
        },
      ]);

      expect(channels, hasLength(1));
      expect(channels.single.provider, MetaChannelProvider.instagram);
      expect(channels.single.accountLabel, 'Viñabike');
      expect(
        channels.single.grantedPermissions,
        ['instagram_basic', 'instagram_manage_messages'],
      );
      expect(
        channels.single.missingRequiredPermissions,
        containsAll(<String>[
          'pages_show_list',
          'pages_messaging',
          'pages_manage_metadata',
          'pages_read_engagement',
          'instagram_manage_comments',
        ]),
      );
      expect(channels.single.isActive, isTrue);
      expect(
        channels.single.authorizationExpiredAt(
          DateTime.parse('2026-09-02T00:00:00Z'),
        ),
        isTrue,
      );
    });

    test('authorization is restricted to the two backend roles', () {
      MetaSettingsSnapshot snapshotFor(
        String role, {
        bool isProfileActive = true,
      }) =>
          MetaSettingsSnapshot(
            tenantId: 'tenant',
            role: role,
            isProfileActive: isProfileActive,
            channels: const [],
          );

      expect(snapshotFor('admin').canManageAuthorization, isTrue);
      expect(snapshotFor('manager').canManageAuthorization, isTrue);
      expect(snapshotFor('owner').canManageAuthorization, isFalse);
      expect(snapshotFor('employee').canManageAuthorization, isFalse);
      expect(
        snapshotFor('admin', isProfileActive: false).canManageAuthorization,
        isFalse,
      );
    });

    test('connected status requires subscription and every provider grant', () {
      MetaChannelStatus instagramChannel({
        required List<String> grantedPermissions,
        DateTime? subscribedAt,
      }) {
        return MetaChannelStatus(
          id: 'instagram-channel',
          provider: MetaChannelProvider.instagram,
          externalAccountId: '17840000000000000',
          displayName: 'Viñabike',
          username: 'vina.bike',
          grantedPermissions: grantedPermissions,
          authorizationExpiresAt: DateTime.utc(2030),
          subscribedAt: subscribedAt,
          updatedAt: DateTime.utc(2026, 7, 21),
          isActive: true,
        );
      }

      final allRequired = <String>[
        'pages_show_list',
        'pages_messaging',
        'pages_manage_metadata',
        'pages_read_engagement',
        'instagram_basic',
        'instagram_manage_messages',
        'instagram_manage_comments',
      ];
      final now = DateTime.utc(2026, 7, 21);

      expect(
        instagramChannel(
          grantedPermissions: allRequired,
          subscribedAt: now,
        ).isOperationalAt(now),
        isTrue,
      );
      expect(
        instagramChannel(
          grantedPermissions: allRequired,
        ).isOperationalAt(now),
        isFalse,
      );
      expect(
        instagramChannel(
          grantedPermissions: allRequired.sublist(0, allRequired.length - 1),
          subscribedAt: now,
        ).isOperationalAt(now),
        isFalse,
      );
    });

    test('route and settings entry point to the canonical page', () {
      final settings = File(
        'lib/modules/settings/pages/settings_page.dart',
      ).readAsStringSync();
      final router = File(
        'lib/shared/routes/app_router.dart',
      ).readAsStringSync();
      final barrel = File(
        'lib/shared/routes/erp_routes_barrel.dart',
      ).readAsStringSync();
      final service = File(
        'lib/modules/settings/services/meta_settings_service.dart',
      ).readAsStringSync();

      expect(settings, contains("route: '/settings/meta'"));
      expect(router, contains("path: '/settings/meta'"));
      expect(router, contains('child: erp.MetaSettingsPage()'));
      expect(barrel, contains("pages/meta_settings_page.dart"));
      expect(service, contains("'meta-oauth'"));
      expect(service, contains("'action': 'start'"));
      expect(service, contains("'tenantId': normalizedTenantId"));
      expect(service, contains(".eq('tenant_id', tenantId)"));
      expect(service, contains('tenantService.currentTenantId'));
      expect(service, contains('LaunchMode.externalApplication'));
      expect(
        service,
        contains(
          "'granted_scopes, token_expires_at, subscribed_at, is_active, '",
        ),
      );
    });
  });
}

const _clientId = '26325303243793949';
const _redirectUri =
    'https://xzdvgtjnegorztcaimog.supabase.co/functions/v1/meta-oauth/callback';
final _authorizationUrl = Uri.https(
  'www.facebook.com',
  '/v24.0/dialog/oauth',
  <String, String>{
    'client_id': _clientId,
    'redirect_uri': _redirectUri,
    'state': 'opaque-state',
    'response_type': 'code',
  },
).toString();

Map<String, Object> _oauthPayload({
  String clientId = _clientId,
  String? authorizationUrl,
}) {
  return <String, Object>{
    'ok': true,
    'client_id': clientId,
    'authorization_url': authorizationUrl ?? _authorizationUrl,
  };
}
