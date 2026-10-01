import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/bikeshop/services/workshop_asset_service.dart';

const _actor = 'e3c30000-0000-4000-8000-000000000091';
const _otherActor = 'e3c30000-0000-4000-8000-000000000092';
const _privatePath = 'e3c30000-0000-4000-8000-000000000001/'
    'e3c30000-0000-4000-8000-000000000021/'
    'e3c30000-0000-4000-8000-000000000041/e2e.jpg';
const _signPath =
    '/storage/v1/object/sign/workshop-legacy-private/$_privatePath';
const _source = 'https://example.supabase.co/storage/v1/object/public/'
    'vinabike-assets/mechanic_jobs/'
    'e3c30000-0000-4000-8000-000000000011/e2e.jpg';

String _session(String actor) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final header = encode({'alg': 'none', 'typ': 'JWT'});
  final payload =
      encode({'exp': 4102444800, 'sub': actor, 'role': 'authenticated'});
  final accessToken = '$header.$payload.test';
  return jsonEncode({
    'access_token': accessToken,
    'refresh_token': 'test-refresh',
    'expires_in': 3600,
    'token_type': 'bearer',
    'user': {
      'id': actor,
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': '2026-09-30T00:00:00Z',
    },
  });
}

Future<SupabaseClient> _client(
    Future<http.Response> Function(http.Request) handle) async {
  final client = SupabaseClient(
    'https://example.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient(handle),
  );
  await client.auth.recoverSession(_session(_actor));
  return client;
}

http.Response _json(Object body,
        {required http.Request request, int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

void main() {
  test(
      'a live job resolves to a five-minute private URL without changing its reference',
      () async {
    var resolutions = 0;
    var signs = 0;
    final observedPaths = <String>[];
    Object? gatewayError;
    final client = await _client((request) async {
      observedPaths.add(request.url.path);
      if (request.url.path == '/rest/v1/rpc/workshop_legacy_asset_read_v1') {
        resolutions++;
        try {
          expect(jsonDecode(request.body), {'p_reference': _source});
        } catch (error) {
          gatewayError = error;
          rethrow;
        }
        return _json({
          'mode': 'private',
          'bucket': WorkshopAssetService.privateBucket,
          'path': _privatePath,
        }, request: request);
      }
      if (request.url.path == _signPath) {
        signs++;
        expect(jsonDecode(request.body)['expiresIn'], 300);
        return _json({
          'signedURL':
              '/object/sign/workshop-legacy-private/$_privatePath?token=test',
        }, request: request);
      }
      throw StateError('Unexpected request');
    });
    addTearDown(client.dispose);
    String url;
    try {
      url = await WorkshopAssetService(client).resolve(_source);
    } catch (_) {
      fail(
          'Private resolution failed after requests: $observedPaths; $gatewayError');
    }
    expect(url, contains('/object/sign/workshop-legacy-private/'));
    expect(url, isNot(contains('/object/public/')));
    expect(resolutions, 1);
    expect(signs, 1);
  });

  test('a missing private copy fails without reopening the public source',
      () async {
    var requests = 0;
    final client = await _client((request) async {
      requests++;
      expect(request.url.path, '/rest/v1/rpc/workshop_legacy_asset_read_v1');
      return _json({
        'code': '55000',
        'message': 'private object missing',
        'details': _privatePath,
      }, request: request, status: 400);
    });
    addTearDown(client.dispose);
    await expectLater(
      WorkshopAssetService(client).resolve(_source),
      throwsA(isA<WorkshopAssetUnavailable>()),
    );
    expect(requests, 1, reason: 'no signing or public fallback after a denial');
    expect(const WorkshopAssetUnavailable().toString(),
        isNot(contains(_privatePath)));
  });

  test('a response from the prior identity cannot be signed or shown',
      () async {
    late SupabaseClient client;
    var signs = 0;
    client = await _client((request) async {
      if (request.url.path == '/rest/v1/rpc/workshop_legacy_asset_read_v1') {
        await client.auth.recoverSession(_session(_otherActor));
        return _json({
          'mode': 'private',
          'bucket': WorkshopAssetService.privateBucket,
          'path': _privatePath,
        }, request: request);
      }
      signs++;
      throw StateError('The previous identity must not reach Storage');
    });
    addTearDown(client.dispose);
    await expectLater(
      WorkshopAssetService(client).resolve(_source),
      throwsA(isA<WorkshopAssetUnavailable>()),
    );
    expect(signs, 0);
  });
}
