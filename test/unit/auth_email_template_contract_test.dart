import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const clickableTemplates = <String>{
    'auth_confirmation.html',
    'auth_email_change.html',
    'auth_invite.html',
    'auth_magic_link.html',
    'auth_recovery.html',
  };
  const actionTemplates = <String>{
    ...clickableTemplates,
    'auth_reauthentication.html',
  };
  const notificationTemplates = <String>{
    'auth_email_changed.html',
    'auth_identity_linked.html',
    'auth_identity_unlinked.html',
    'auth_mfa_factor_enrolled.html',
    'auth_mfa_factor_unenrolled.html',
    'auth_password_changed.html',
    'auth_phone_changed.html',
  };
  const allTemplates = <String>{
    ...actionTemplates,
    ...notificationTemplates,
  };

  test('local Auth config mirrors the hardened email and password contract',
      () {
    final config = File('supabase/config.toml').readAsStringSync();

    expect(config, contains('site_url = "http://127.0.0.1:54330"'));
    expect(config, contains('minimum_password_length = 8'));
    expect(config, contains('password_requirements = "letters_digits"'));
    expect(config, contains('enable_confirmations = true'));
    expect(config, contains('secure_password_change = true'));
    expect(config, contains('max_frequency = "60s"'));

    for (final template in actionTemplates) {
      expect(
        config,
        contains('./supabase/templates/$template'),
        reason: '$template must be wired into the reproducible Auth config',
      );
    }
    for (final template in notificationTemplates) {
      expect(
        config,
        contains('./templates/$template'),
        reason:
            '$template must use the Supabase CLI notification path convention',
      );
    }
    expect(config, isNot(contains('subject = "{{ .Token }}')));
    expect(
      RegExp(r'\[auth\.email\.notification\.').allMatches(config),
      hasLength(7),
    );
    expect(
      RegExp(r'enabled = true')
          .allMatches(
            config.substring(config.indexOf('[auth.email.notification.')),
          )
          .length,
      greaterThanOrEqualTo(7),
    );
  });

  test('Auth templates require a human click before consuming action URLs', () {
    for (final template in clickableTemplates) {
      final html = File('supabase/templates/$template').readAsStringSync();
      if (template == 'auth_invite.html' || template == 'auth_recovery.html') {
        final type = template == 'auth_invite.html' ? 'invite' : 'recovery';
        final actionUrl = '{{ .SiteURL }}/auth-action.html'
            '#token_hash={{ .TokenHash }}&amp;type=$type'
            '&amp;redirect_to={{ .RedirectTo }}';
        expect(
          actionUrl.allMatches(html),
          hasLength(2),
          reason:
              '$template must expose one action through its CTA and fallback',
        );
        expect('{{ .TokenHash }}'.allMatches(html), hasLength(2));
        expect('{{ .RedirectTo }}'.allMatches(html), hasLength(2));
        expect(html, isNot(contains('{{ .ConfirmationURL }}')));
      } else {
        const actionUrl = '{{ .SiteURL }}/auth-action.html'
            '#confirmation_url={{ .ConfirmationURL }}';
        expect(
          actionUrl.allMatches(html),
          hasLength(2),
          reason:
              '$template must expose one action through its CTA and fallback',
        );
        expect(html, isNot(contains('href="{{ .ConfirmationURL }}"')));
        expect(
          '{{ .ConfirmationURL }}'.allMatches(html),
          hasLength(2),
          reason: '$template must repeat only the same protected action',
        );
      }
      _expectSafeTemplate(html, template);
    }

    final confirmationPage = File('web/auth-action.html').readAsStringSync();
    expect(
      confirmationPage,
      contains("const confirmationFragmentPrefix = '#confirmation_url='"),
    );
    expect(
        confirmationPage, contains("candidate.pathname === '/auth/v1/verify'"));
    expect(confirmationPage, contains("candidate.searchParams.has('token')"));
    expect(confirmationPage, contains("candidate.searchParams.has('type')"));
    expect(confirmationPage, contains('xzdvtzdqjeyqxnkqprtf.supabase.co'));
    expect(
      confirmationPage,
      contains("const tokenFragmentPrefix = '#token_hash='"),
    );
    expect(
      confirmationPage,
      contains("const inviteFragmentSeparator = '&type=invite&redirect_to='"),
    );
    expect(
      confirmationPage,
      contains(
        "const recoveryFragmentSeparator = '&type=recovery&redirect_to='",
      ),
    );
    expect(
      confirmationPage,
      contains("candidate.pathname === '/cuenta/login'"),
    );
    expect(
      confirmationPage,
      contains("candidate.searchParams.get(flow.queryKey) === 'true'"),
    );
    expect(
      confirmationPage,
      contains("destination.hash = new URLSearchParams({"),
    );
    expect(confirmationPage, contains("token_hash: tokenHash"));
    expect(confirmationPage, contains('type: flow.type'));
    expect(confirmationPage, contains('window.history.replaceState'));
    expect(confirmationPage, contains("button.addEventListener("));
    expect(confirmationPage, contains("{ once: true }"));
    expect(confirmationPage, isNot(contains('console.')));
    expect(confirmationPage, isNot(contains('localStorage')));
    expect(confirmationPage, isNot(contains('sessionStorage')));

    for (final template in notificationTemplates) {
      final html = File('supabase/templates/$template').readAsStringSync();
      expect(html, isNot(contains('{{ .Token }}')));
      expect(html, isNot(contains('{{ .ConfirmationURL }}')));
      _expectSafeTemplate(html, template);
    }

    final reauthentication =
        File('supabase/templates/auth_reauthentication.html')
            .readAsStringSync();
    expect('{{ .Token }}'.allMatches(reauthentication), hasLength(1));
    expect(reauthentication, isNot(contains('{{ .ConfirmationURL }}')));
    _expectSafeTemplate(reauthentication, 'auth_reauthentication.html');
  });

  test('all 13 Auth emails share the responsive accessible visual system', () {
    final generated = Directory('supabase/templates')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.startsWith('auth_') && name.endsWith('.html'))
        .toSet();
    expect(generated, allTemplates);

    for (final template in allTemplates) {
      final html = File('supabase/templates/$template').readAsStringSync();
      expect(html, contains('<html lang="es">'), reason: template);
      expect(html, contains('name="viewport"'), reason: template);
      expect(html, contains('name="format-detection"'), reason: template);
      expect(html, contains('display:none;max-height:0'), reason: template);
      expect(html, contains('@media only screen and (max-width: 600px)'),
          reason: template);
      expect(html, contains('table-layout:fixed'), reason: template);
      expect(html, contains('overflow-wrap:anywhere'), reason: template);
      expect(html, contains('word-break:break-word'), reason: template);
      expect(html, contains('Cuenta y seguridad'), reason: template);
      expect(html, contains('Mensaje seguro'), reason: template);
      expect(
        html,
        isNot(contains('contacta al administrador')),
        reason: '$template must work for both customer and staff accounts',
      );
    }

    for (final template in clickableTemplates) {
      final html = File('supabase/templates/$template').readAsStringSync();
      expect(html, contains('min-height:48px'), reason: template);
      expect(html, contains('class="button-link"'), reason: template);
      expect(html, contains('abre este enlace seguro'), reason: template);
    }

    final phone =
        File('supabase/templates/auth_phone_changed.html').readAsStringSync();
    expect(phone, contains('{{ .OldPhone }}'));
    expect(phone, contains('{{ .Phone }}'));

    for (final template in const {
      'auth_mfa_factor_enrolled.html',
      'auth_mfa_factor_unenrolled.html',
    }) {
      expect(
        File('supabase/templates/$template').readAsStringSync(),
        contains('{{ .FactorType }}'),
      );
    }
  });

  test('generated Auth emails cannot drift from their canonical renderer', () {
    final result = Process.runSync(
      'node',
      const ['scripts/auth/auth_email_templates.mjs', '--check'],
      workingDirectory: Directory.current.path,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('Auth action page is served with non-cacheable security headers', () {
    final firebaseConfig = jsonDecode(File('firebase.json').readAsStringSync())
        as Map<String, dynamic>;
    final hostingTargets = firebaseConfig['hosting'] as List<dynamic>;

    for (final rawTarget in hostingTargets) {
      final target = rawTarget as Map<String, dynamic>;
      final headers = target['headers'] as List<dynamic>;
      final authAction = headers
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['source'] == '/auth-action.html');
      final values = {
        for (final rawHeader in authAction['headers'] as List<dynamic>)
          (rawHeader as Map<String, dynamic>)['key']: rawHeader['value'],
      };

      expect(values['Cache-Control'], 'no-store, max-age=0');
      expect(values['Referrer-Policy'], 'no-referrer');
      expect(values['X-Frame-Options'], 'DENY');
      expect(values['X-Content-Type-Options'], 'nosniff');
      expect(
        values['Content-Security-Policy'],
        contains("frame-ancestors 'none'"),
      );
    }
  });
}

void _expectSafeTemplate(String html, String template) {
  expect(html, isNot(contains('<script')), reason: template);
  expect(
    RegExp(r'\bon[a-z]+\s*=', caseSensitive: false).hasMatch(html),
    isFalse,
    reason: template,
  );
  expect(html, isNot(contains('{{ .Data')), reason: template);
  expect(html, isNot(contains('access_token')), reason: template);
  expect(html, isNot(contains('refresh_token')), reason: template);
  expect(
    RegExp(r'''(?:src|href)\s*=\s*["']https?://''', caseSensitive: false)
        .hasMatch(html),
    isFalse,
    reason: '$template must not load or track remote content',
  );
}
