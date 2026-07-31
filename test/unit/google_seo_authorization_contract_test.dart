import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Google OAuth storage is tenant scoped and state is one-time', () {
    final migration = File(
      'supabase/migrations/'
      '20260728200000_tenant_scope_google_integrations.sql',
    ).readAsStringSync();
    final coreSchema = File('supabase/sql/core_schema.sql').readAsStringSync();

    expect(
      migration,
      contains('Additive Google integration cutover'),
    );
    expect(
      migration,
      contains(
        'create table if not exists '
        'public.google_oauth_tenant_connections',
      ),
    );
    expect(
      migration,
      contains('google_oauth_tenant_connections_owner_key'),
    );
    expect(
      migration,
      contains(
        'create table if not exists public.google_oauth_generation_heads',
      ),
    );
    expect(
      migration,
      isNot(contains('drop constraint if exists '
          'google_oauth_connections_pkey')),
    );
    expect(
      migration,
      isNot(contains('rename column state to state_hash')),
    );
    expect(
      migration,
      contains(
        'create table if not exists public.google_oauth_tenant_states',
      ),
    );
    expect(
      migration,
      contains('create or replace function public.create_google_oauth_state'),
    );
    expect(
      migration,
      contains('create or replace function public.consume_google_oauth_state'),
    );
    expect(
      migration,
      contains(
        'create or replace function public.commit_google_oauth_connection',
      ),
    );
    expect(
      migration,
      contains(
        'create or replace function '
        'public.refresh_google_oauth_access_token',
      ),
    );
    expect(
      migration,
      contains(
        'create or replace function '
        'public.acquire_google_merchant_refresh_lease',
      ),
    );
    expect(
      migration,
      contains(
        'create or replace function '
        'public.renew_google_merchant_refresh_lease',
      ),
    );
    expect(
      migration,
      contains('public.google_oauth_site_matches_tenant'),
    );
    expect(
      migration,
      contains('profile.permissions @> \'{"edit_settings": true}\'::jsonb'),
    );
    expect(migration, contains('lease_fence'));
    expect(migration, contains('pg_advisory_xact_lock'));
    expect(migration, contains('for update'));
    expect(migration, contains("'reason', 'superseded'"));
    expect(migration, contains('credential_version'));
    expect(
      migration,
      contains('The final cleanup is deliberately not included'),
    );
    expect(
      migration,
      contains(
        'Google OAuth requires exactly one active authorized tenant profile',
      ),
    );
    expect(
      migration,
      contains(
        'grant execute on function public.consume_google_oauth_state(text)',
      ),
    );
    for (final functionName in [
      'google_oauth_tenant_store_host',
      'google_oauth_site_matches_tenant',
      'prepare_google_oauth_state_transition',
      'mirror_google_oauth_connection_transition',
      'create_google_oauth_state',
      'consume_google_oauth_state',
      'commit_google_oauth_connection',
      'refresh_google_oauth_access_token',
      'acquire_google_merchant_refresh_lease',
      'renew_google_merchant_refresh_lease',
      'release_google_merchant_refresh_lease',
    ]) {
      expect(
        _normalizedSqlFunction(coreSchema, functionName),
        _normalizedSqlFunction(migration, functionName),
        reason: '$functionName must match the bootstrap schema',
      );
    }
  });

  test('Google Edge functions consume the tenant scoped contract', () {
    final diagnostics = File(
      'supabase/functions/google-product-diagnostics/index.ts',
    ).readAsStringSync();
    final oauth = File(
      'supabase/functions/google-oauth-callback/index.ts',
    ).readAsStringSync();

    expect(
      diagnostics,
      contains('.from("google_oauth_tenant_connections")'),
    );
    expect(diagnostics, contains('.eq("site_url", siteUrl)'));
    expect(
      diagnostics,
      contains('merchantIntegrationForTenant(auth.tenantId)'),
    );
    expect(
      diagnostics,
      contains('"acquire_google_merchant_refresh_lease"'),
    );
    expect(
      diagnostics,
      contains('"renew_google_merchant_refresh_lease"'),
    );
    expect(
      diagnostics,
      contains('"refresh_google_oauth_access_token"'),
    );
    expect(
      diagnostics,
      contains('reuse that committed token'),
    );
    expect(
      diagnostics,
      contains('exact tenant/site OAuth connection is the primary credential'),
    );
    expect(
      diagnostics,
      contains('ipv4Range(value, "240.0.0.0", 4)'),
    );
    expect(diagnostics, isNot(contains('"Access-Control-Allow-Origin": "*"')));

    final consume = oauth.indexOf('"consume_google_oauth_state"');
    final authority = oauth.indexOf(
      'await requireWebsiteSeoActor(actorId, tenantId)',
    );
    final tokenExchange =
        oauth.indexOf('const tokens = await exchangeCode(code)');
    final commit = oauth.indexOf(
      '"commit_google_oauth_connection"',
      tokenExchange,
    );
    expect(consume, greaterThan(0));
    expect(authority, greaterThan(consume));
    expect(tokenExchange, greaterThan(authority));
    expect(commit, greaterThan(tokenExchange));
    expect(oauth, isNot(contains('.upsert(')));
    expect(oauth, contains('selectGoogleRefreshToken'));
    expect(oauth, contains('GOOGLE_SEARCH_CONSOLE_SITE_TENANT_ID'));
    expect(oauth, isNot(contains('"Access-Control-Allow-Origin": "*"')));
  });

  test('gateway verifies diagnostics JWT and leaves only OAuth callback public',
      () {
    final config = File('supabase/config.toml').readAsLinesSync();

    expect(
      _tomlBoolean(
        config,
        section: 'functions.google-product-diagnostics',
        key: 'verify_jwt',
      ),
      isTrue,
    );
    expect(
      _tomlBoolean(
        config,
        section: 'functions.google-oauth-callback',
        key: 'verify_jwt',
      ),
      isFalse,
    );
  });
}

String _normalizedSqlFunction(String source, String functionName) {
  final start =
      source.indexOf('create or replace function public.$functionName');
  if (start < 0) return '';
  final end = source.indexOf('\n\$\$;', start);
  if (end < 0) return '';
  return source
      .substring(start, end + 4)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool? _tomlBoolean(
  List<String> lines, {
  required String section,
  required String key,
}) {
  var inSection = false;
  for (final rawLine in lines) {
    final line = rawLine.split('#').first.trim();
    if (line.isEmpty) continue;
    final sectionMatch = RegExp(r'^\[([^\]]+)\]$').firstMatch(line);
    if (sectionMatch != null) {
      inSection = sectionMatch.group(1) == section;
      continue;
    }
    if (!inSection) continue;
    final keyMatch = RegExp(
      '^${RegExp.escape(key)}\\s*=\\s*(true|false)\$',
    ).firstMatch(line);
    if (keyMatch != null) return keyMatch.group(1) == 'true';
  }
  return null;
}
