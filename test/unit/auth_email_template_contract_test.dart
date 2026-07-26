import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const actionableTemplates = <String>{
    'auth_confirmation.html',
    'auth_email_change.html',
    'auth_invite.html',
    'auth_magic_link.html',
    'auth_recovery.html',
  };
  const notificationTemplates = <String>{
    'auth_email_changed.html',
    'auth_identity_linked.html',
    'auth_identity_unlinked.html',
    'auth_password_changed.html',
    'auth_reauthentication.html',
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

    for (final template in actionableTemplates) {
      expect(
        config,
        contains('./supabase/templates/$template'),
        reason: '$template must be wired into the reproducible Auth config',
      );
    }
    expect(
      config,
      contains('./supabase/templates/auth_reauthentication.html'),
      reason:
          'auth_reauthentication.html must be wired as an Auth action template',
    );

    for (final template in notificationTemplates.where(
      (template) => template != 'auth_reauthentication.html',
    )) {
      expect(
        config,
        contains('./supabase/templates/$template'),
        reason: '$template must be wired into the reproducible Auth config',
      );
    }
  });

  test('Auth templates require a human click before consuming action URLs', () {
    for (final template in actionableTemplates) {
      final html = File('supabase/templates/$template').readAsStringSync();
      if (template == 'auth_invite.html') {
        expect(
          html,
          contains(
            '{{ .SiteURL }}/auth-action.html'
            '#token_hash={{ .TokenHash }}&amp;type=invite'
            '&amp;redirect_to={{ .RedirectTo }}',
          ),
        );
        expect('{{ .TokenHash }}'.allMatches(html), hasLength(1));
        expect('{{ .RedirectTo }}'.allMatches(html), hasLength(1));
        expect(html, isNot(contains('{{ .ConfirmationURL }}')));
      } else {
        expect(
          html,
          contains(
            '{{ .SiteURL }}/auth-action.html'
            '#confirmation_url={{ .ConfirmationURL }}',
          ),
        );
        expect(html, isNot(contains('href="{{ .ConfirmationURL }}"')));
        expect(
          '{{ .ConfirmationURL }}'.allMatches(html),
          hasLength(1),
          reason: '$template must have one unambiguous security action',
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
      contains("const inviteFragmentPrefix = '#token_hash='"),
    );
    expect(
      confirmationPage,
      contains("const inviteFragmentSeparator = '&type=invite&redirect_to='"),
    );
    expect(
      confirmationPage,
      contains("candidate.pathname === '/cuenta/login'"),
    );
    expect(
      confirmationPage,
      contains("candidate.searchParams.get('invited') === 'true'"),
    );
    expect(
      confirmationPage,
      contains("destination.hash = new URLSearchParams({"),
    );
    expect(confirmationPage, contains("token_hash: tokenHash"));
    expect(confirmationPage, contains("type: 'invite'"));
    expect(confirmationPage, contains('window.history.replaceState'));
    expect(confirmationPage, contains("button.addEventListener("));
    expect(confirmationPage, contains("{ once: true }"));
    expect(confirmationPage, isNot(contains('console.')));
    expect(confirmationPage, isNot(contains('localStorage')));
    expect(confirmationPage, isNot(contains('sessionStorage')));

    for (final template in notificationTemplates) {
      final html = File('supabase/templates/$template').readAsStringSync();
      if (template == 'auth_reauthentication.html') {
        expect(html, contains('{{ .Token }}'));
      } else {
        expect(html, isNot(contains('{{ .Token }}')));
      }
      expect(html, isNot(contains('{{ .ConfirmationURL }}')));
      _expectSafeTemplate(html, template);
    }
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
