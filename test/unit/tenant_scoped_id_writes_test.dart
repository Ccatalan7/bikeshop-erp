import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/hr/services/hr_service.dart';
import 'package:vinabike_erp/modules/messaging/services/messaging_service.dart';
import 'package:vinabike_erp/modules/tax_reports/services/f29_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

// A write by id carries the session tenant as a PostgREST filter, not only
// row-level security. These tests read the filter off the captured request.

const _tenantA = '73000000-0000-4000-8000-00000000000a';
const _userA = '73000000-0000-4000-8000-0000000000a1';

void main() {
  group('F29Service', () {
    test('updateStatus scopes the declaration update to the tenant', () async {
      final backend = _Backend();
      final service = F29Service(
        supabase: backend.client(),
        tenantService: _tenantService(_tenantA),
      );

      final updated = await service.updateStatus(
        'f29-1',
        'submitted',
        folioNumber: '12345',
      );

      expect(updated, isTrue);
      final write = backend.single('PATCH', 'f29_declarations');
      _expectScoped(write, id: 'f29-1');
      final body = jsonDecode(write.body) as Map<String, dynamic>;
      expect(body['status'], 'submitted');
      expect(body['folio_number'], '12345');
    });

    test('updateNotes scopes the declaration update to the tenant', () async {
      final backend = _Backend();
      final service = F29Service(
        supabase: backend.client(),
        tenantService: _tenantService(_tenantA),
      );

      expect(await service.updateNotes('f29-1', 'Revisar crédito'), isTrue);

      final write = backend.single('PATCH', 'f29_declarations');
      _expectScoped(write, id: 'f29-1');
      expect(jsonDecode(write.body)['notes'], 'Revisar crédito');
    });

    test('a session without tenant sends no update', () async {
      final backend = _Backend();
      final service = F29Service(
        supabase: backend.client(),
        tenantService: _tenantService(null),
      );

      expect(await service.updateStatus('f29-1', 'paid'), isFalse);
      expect(await service.updateNotes('f29-1', 'x'), isFalse);
      expect(backend.writes, isEmpty);
    });
  });

  group('HRService attendance approval', () {
    test('approveAttendance scopes the update to the tenant', () async {
      final backend = _Backend();
      final service = HRService(
        _tenantService(_tenantA),
        client: backend.client(),
      );

      await service.approveAttendance('attendance-1', 'manager-1');

      final write = backend.single('PATCH', 'attendances');
      _expectScoped(write, id: 'attendance-1');
      final body = jsonDecode(write.body) as Map<String, dynamic>;
      expect(body['status'], 'approved');
      expect(body['approved_by'], 'manager-1');
    });

    test('rejectAttendance scopes the update to the tenant', () async {
      final backend = _Backend();
      final service = HRService(
        _tenantService(_tenantA),
        client: backend.client(),
      );

      await service.rejectAttendance('attendance-1', 'manager-1');

      final write = backend.single('PATCH', 'attendances');
      _expectScoped(write, id: 'attendance-1');
      expect(jsonDecode(write.body)['status'], 'rejected');
    });

    test('a session without tenant fails before writing', () async {
      final backend = _Backend();
      final service = HRService(
        _tenantService(null),
        client: backend.client(),
      );

      await expectLater(
        service.approveAttendance('attendance-1', 'manager-1'),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        service.rejectAttendance('attendance-1', 'manager-1'),
        throwsA(isA<Exception>()),
      );
      expect(backend.writes, isEmpty);
    });
  });

  group('MessagingService chat requests', () {
    test('accept, reject and resolve scope the conversation to the tenant',
        () async {
      final backend = _Backend();
      final client = backend.client();
      await _signIn(client, userId: _userA);
      final service = MessagingService(
        client: client,
        tenantService: _tenantService(_tenantA),
      );

      await service.acceptChatRequest('conversation-1');
      await service.rejectChatRequest('conversation-2', 'Fuera de horario');
      await service.resolveChat('conversation-3');

      final updates = backend.all('PATCH', 'conversations');
      expect(updates, hasLength(3));
      _expectScoped(updates[0], id: 'conversation-1');
      _expectScoped(updates[1], id: 'conversation-2');
      _expectScoped(updates[2], id: 'conversation-3');
      expect(jsonDecode(updates[0].body)['status'], 'active');
      expect(jsonDecode(updates[0].body)['accepted_by'], _userA);
      expect(jsonDecode(updates[1].body)['status'], 'rejected');
      expect(jsonDecode(updates[2].body)['status'], 'resolved');
    });

    test('a session without tenant changes no conversation', () async {
      final backend = _Backend();
      final client = backend.client();
      await _signIn(client, userId: _userA);
      final service = MessagingService(
        client: client,
        tenantService: _tenantService(null),
      );

      await expectLater(
        service.acceptChatRequest('conversation-1'),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        service.rejectChatRequest('conversation-1', 'x'),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        service.resolveChat('conversation-1'),
        throwsA(isA<Exception>()),
      );
      expect(backend.writes, isEmpty);
    });
  });

  group('DatabaseService generic writes by id', () {
    test('update and delete carry the session tenant', () async {
      final backend = _Backend();
      final database = DatabaseService(
        client: backend.client(),
        tenantService: _tenantService(_tenantA),
      );
      addTearDown(database.dispose);

      await database.update('products', 'product-1', {'name': 'Cadena'});
      await database.delete('products', 'product-1');
      await database.deleteWhere('job_statuses', 'code', 'custom');

      _expectScoped(backend.single('PATCH', 'products'), id: 'product-1');
      _expectScoped(backend.single('DELETE', 'products'), id: 'product-1');
      final byColumn = backend.single('DELETE', 'job_statuses');
      expect(byColumn.url.queryParameters['code'], 'eq.custom');
      expect(byColumn.url.queryParameters['tenant_id'], 'eq.$_tenantA');
    });

    test('a system table has no tenant column to filter', () async {
      final backend = _Backend();
      final database = DatabaseService(
        client: backend.client(),
        tenantService: _tenantService(_tenantA),
      );
      addTearDown(database.dispose);

      await database.update('tenants', _tenantA, {'name': 'Taller'});

      final write = backend.single('PATCH', 'tenants');
      expect(write.url.queryParameters['id'], 'eq.$_tenantA');
      expect(write.url.queryParameters.containsKey('tenant_id'), isFalse);
    });

    test('a session without tenant fails before writing', () async {
      final backend = _Backend();
      final database = DatabaseService(
        client: backend.client(),
        tenantService: _tenantService(null),
      );
      addTearDown(database.dispose);

      await expectLater(
        database.update('products', 'product-1', {'name': 'Cadena'}),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        database.delete('products', 'product-1'),
        throwsA(isA<StateError>()),
      );
      expect(backend.writes, isEmpty);
    });
  });

  group('source contract', () {
    test('no update or delete in lib/ filters a tenant table by id alone', () {
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        offenders.addAll(_idOnlyWrites(entity.path, entity.readAsStringSync()));
      }

      expect(
        offenders,
        isEmpty,
        reason: 'Add .eq(\'tenant_id\', …) next to the id filter, or list the '
            'table in _tablesWithoutTenantColumn when it has no tenant_id.',
      );
    });

    test('the scanner sees an id-only write and its tenant-scoped fix', () {
      const unscoped = '''
await _client.from('f29_declarations').update({
  'status': 'paid', // "it's" in a comment must not open a string
  'notes': 'Folio \${row['folio']}',
}).eq('id', f29Id);
''';
      const scoped = '''
await _client
    .from('attendances')
    .delete()
    .eq('id', attendanceId)
    .eq('tenant_id', tenantId);
''';
      const insideComment = '''
/// await _client.from('attendances').delete().eq('id', id);
''';

      expect(_idOnlyWrites('a.dart', unscoped), ['a.dart:1 f29_declarations']);
      expect(_idOnlyWrites('a.dart', scoped), isEmpty);
      expect(_idOnlyWrites('a.dart', insideComment), isEmpty);
    });
  });
}

/// The tenant row itself: filtering `tenants` by `id` already names the
/// tenant.
const _tablesWithoutTenantColumn = {'tenants'};

final _writeStart = RegExp(
  r'''^\.from\(\s*['"]([a-z0-9_]+)['"]\s*\)\s*\.(update|delete)\(''',
);
final _idFilter = RegExp(r'''\.(eq|inFilter)\(\s*['"]id['"]''');

/// `path:line table` for every `.from('<table>').update(…)` or `.delete()`
/// statement in [source] that filters `id` and never names `tenant_id`.
List<String> _idOnlyWrites(String path, String source) {
  final kinds = _lex(source);
  final text = String.fromCharCodes([
    for (var i = 0; i < source.length; i++)
      kinds[i] == _Kind.comment ? 0x20 : source.codeUnitAt(i),
  ]);
  final offenders = <String>[];
  for (final from in RegExp(r'\.from\(').allMatches(text)) {
    if (kinds[from.start] != _Kind.code) continue;
    var depth = 0;
    var end = from.start;
    for (; end < text.length; end++) {
      if (kinds[end] != _Kind.code) continue;
      final char = text[end];
      if ('([{'.contains(char)) depth++;
      if (')]}'.contains(char) && --depth < 0) break;
      if (char == ';' && depth == 0) break;
    }
    var statement = text.substring(from.start, end);
    final nested = RegExp(r'\.from\(').allMatches(statement).skip(1);
    if (nested.isNotEmpty) {
      statement = statement.substring(0, nested.first.start);
    }
    final write = _writeStart.firstMatch(statement);
    if (write == null || _tablesWithoutTenantColumn.contains(write[1])) {
      continue;
    }
    if (!_idFilter.hasMatch(statement) || statement.contains('tenant_id')) {
      continue;
    }
    final line = '\n'.allMatches(text.substring(0, from.start)).length + 1;
    offenders.add('$path:$line ${write[1]}');
  }
  return offenders;
}

enum _Kind { code, string, comment }

/// Classifies each character of Dart [source]: string literals (with their
/// `${…}` interpolations counted as code) and nested block comments are
/// recognised, so a bracket or a quote inside them never ends a statement.
List<_Kind> _lex(String source) {
  final kinds = List<_Kind>.filled(source.length, _Kind.code);

  bool isIdentifier(int i) =>
      i >= 0 && RegExp(r'[A-Za-z0-9_$]').hasMatch(source[i]);

  late int Function(int, {bool untilBrace}) lexCode;

  int lexString(int i) {
    final raw = i > 0 && source[i - 1] == 'r' && !isIdentifier(i - 2);
    final quote = source[i];
    final delimiter = source.startsWith(quote * 3, i) ? quote * 3 : quote;
    for (var k = 0; k < delimiter.length; k++) {
      kinds[i + k] = _Kind.string;
    }
    i += delimiter.length;
    while (i < source.length) {
      if (source.startsWith(delimiter, i)) {
        for (var k = 0; k < delimiter.length; k++) {
          kinds[i + k] = _Kind.string;
        }
        return i + delimiter.length;
      }
      if (!raw && source[i] == r'\') {
        kinds[i] = _Kind.string;
        if (i + 1 < source.length) kinds[i + 1] = _Kind.string;
        i += 2;
        continue;
      }
      if (!raw && source.startsWith(r'${', i)) {
        kinds[i] = _Kind.string;
        kinds[i + 1] = _Kind.string;
        i = lexCode(i + 2, untilBrace: true);
        continue;
      }
      if (delimiter.length == 1 && source[i] == '\n') return i;
      kinds[i] = _Kind.string;
      i++;
    }
    return i;
  }

  lexCode = (int i, {bool untilBrace = false}) {
    var braces = 0;
    while (i < source.length) {
      if (source.startsWith('//', i)) {
        while (i < source.length && source[i] != '\n') {
          kinds[i++] = _Kind.comment;
        }
        continue;
      }
      if (source.startsWith('/*', i)) {
        var nesting = 0;
        do {
          if (source.startsWith('/*', i)) {
            nesting++;
            kinds[i] = kinds[i + 1] = _Kind.comment;
            i += 2;
          } else if (source.startsWith('*/', i)) {
            nesting--;
            kinds[i] = kinds[i + 1] = _Kind.comment;
            i += 2;
          } else {
            kinds[i++] = _Kind.comment;
          }
        } while (nesting > 0 && i < source.length);
        continue;
      }
      final char = source[i];
      if (char == "'" || char == '"') {
        i = lexString(i);
        continue;
      }
      if (untilBrace) {
        if (char == '{') braces++;
        if (char == '}' && braces-- == 0) {
          kinds[i] = _Kind.string;
          return i + 1;
        }
      }
      i++;
    }
    return i;
  };

  lexCode(0);
  return kinds;
}

void _expectScoped(http.Request write, {required String id}) {
  expect(write.url.queryParameters['id'], 'eq.$id');
  expect(write.url.queryParameters['tenant_id'], 'eq.$_tenantA');
}

/// [tenantId] null models a session whose profile does not resolve to exactly
/// one tenant: [TenantService] then fails closed.
TenantService _tenantService(String? tenantId) {
  return TenantService.testing(
    currentUserId: () => _userA,
    profileLookup: (_) async => tenantId == null
        ? const <Map<String, dynamic>>[]
        : [
            {
              'tenant_id': tenantId,
              'role': 'admin',
              'permissions': <String, dynamic>{},
            },
          ],
  );
}

/// Records every request and answers like PostgREST would for a write that
/// matched one row; reads come back empty.
class _Backend {
  final List<http.Request> requests = [];

  List<http.Request> get writes =>
      requests.where((request) => request.method != 'GET').toList();

  SupabaseClient client() {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(_handle),
    );
    addTearDown(client.dispose);
    return client;
  }

  List<http.Request> all(String method, String table) => requests
      .where(
        (request) =>
            request.method == method &&
            request.url.path.endsWith('/rest/v1/$table'),
      )
      .toList();

  http.Request single(String method, String table) {
    final matches = all(method, table);
    expect(matches, hasLength(1), reason: '$method $table');
    return matches.single;
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (request.method == 'GET') return _json(request, const <dynamic>[]);
    final returnsRow =
        request.headers['Prefer']?.contains('return=representation') ?? false;
    if (!returnsRow) return http.Response('', 204, request: request);
    final row = <String, dynamic>{
      'id': request.url.queryParameters['id']?.replaceFirst('eq.', ''),
      if (request.body.isNotEmpty)
        ...jsonDecode(request.body) as Map<String, dynamic>,
    };
    final wantsObject = request.headers['Accept']?.contains(
          'application/vnd.pgrst.object+json',
        ) ??
        false;
    return _json(request, wantsObject ? row : [row]);
  }
}

http.Response _json(http.BaseRequest request, Object body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const {'content-type': 'application/json'},
    request: request,
  );
}

Future<void> _signIn(SupabaseClient client, {required String userId}) async {
  String segment(Map<String, Object> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  final token = '${segment({'alg': 'none', 'typ': 'JWT'})}.'
      '${segment({
        'exp': 4102444800,
        'sub': userId,
        'role': 'authenticated',
      })}.signature';
  await client.auth.recoverSession(
    jsonEncode({
      'access_token': token,
      'expires_in': 3600,
      'refresh_token': 'test-refresh-token',
      'token_type': 'bearer',
      'user': {
        'id': userId,
        'app_metadata': const <String, dynamic>{},
        'user_metadata': const <String, dynamic>{},
        'aud': 'authenticated',
        'created_at': '2026-10-29T00:00:00.000Z',
      },
    }),
  );
}
