import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/hr/services/hr_service.dart';
import 'package:vinabike_erp/modules/messaging/services/messaging_service.dart';
import 'package:vinabike_erp/modules/purchases/services/intelligent_purchasing_service.dart';
import 'package:vinabike_erp/modules/tax_reports/services/f29_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

// A read or write by id, and a write by any other key, carries the session
// tenant as a PostgREST filter, not only row-level security. These tests read
// the filter off the captured request.

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

  group('HRService reads by id', () {
    test('getEmployeeById scopes the read to the tenant', () async {
      final backend = _Backend();
      final service = HRService(
        _tenantService(_tenantA),
        client: backend.client(),
      );

      await service.getEmployeeById('employee-1');

      _expectScoped(backend.single('GET', 'employees'), id: 'employee-1');
    });

    test('a session without tenant reads no employee', () async {
      final backend = _Backend();
      final service = HRService(
        _tenantService(null),
        client: backend.client(),
      );

      expect(await service.getEmployeeById('employee-1'), isNull);
      expect(backend.requests, isEmpty);
    });
  });

  group('MessagingService conversation export', () {
    test('every read of the snapshot carries the tenant', () async {
      final backend = _Backend(
        rows: {
          'conversations': [
            {'id': 'conversation-1', 'tenant_id': _tenantA},
          ],
          'whatsapp_conversation_bindings': [
            {'conversation_id': 'conversation-1', 'channel_id': 'channel-1'},
          ],
        },
      );
      final client = backend.client();
      await _signIn(client, userId: _userA);
      final service = MessagingService(
        client: client,
        tenantService: _tenantService(_tenantA),
      );

      await service.getConversationArchiveSnapshot('conversation-1');

      _expectScoped(
        backend.single('GET', 'conversations'),
        id: 'conversation-1',
      );
      for (final table in const [
        'conversation_participants',
        'conversation_contexts',
        'messages',
        'whatsapp_conversation_bindings',
        'whatsapp_channels',
      ]) {
        expect(
          backend.single('GET', table).url.queryParameters['tenant_id'],
          'eq.$_tenantA',
          reason: table,
        );
      }
    });
  });

  group('IntelligentPurchasingService plan', () {
    test('fetchPlan reads the plan, its lines and products in the tenant',
        () async {
      final backend = _Backend(
        rows: {
          'purchase_plans': [
            {'id': 'plan-1', 'tenant_id': _tenantA},
          ],
          'purchase_plan_lines': [
            {'id': 'line-1', 'product_id': 'product-1'},
          ],
        },
      );
      final service = IntelligentPurchasingService(
        client: backend.client(),
        tenantService: _tenantService(_tenantA),
      );

      await service.fetchPlan('plan-1');

      _expectScoped(backend.single('GET', 'purchase_plans'), id: 'plan-1');
      expect(
        backend
            .single('GET', 'purchase_plan_lines')
            .url
            .queryParameters['tenant_id'],
        'eq.$_tenantA',
      );
      final products = backend.single('GET', 'products');
      expect(products.url.queryParameters['id'], 'in.("product-1")');
      expect(products.url.queryParameters['tenant_id'], 'eq.$_tenantA');
    });
  });

  group('DatabaseService generic reads by id', () {
    test('selectById and a select by id carry the session tenant', () async {
      final backend = _Backend();
      final database = DatabaseService(
        client: backend.client(),
        tenantService: _tenantService(_tenantA),
      );
      addTearDown(database.dispose);

      await database.selectById('products', 'product-1');
      await database.select('suppliers', where: 'id=supplier-1', limit: 1);
      await database.select(
        'payroll_vouchers',
        where: 'id',
        whereIn: ['voucher-1', 'voucher-2'],
      );
      await database.select('customers', where: 'rut=11111111-1');

      _expectScoped(backend.single('GET', 'products'), id: 'product-1');
      _expectScoped(backend.single('GET', 'suppliers'), id: 'supplier-1');
      final vouchers = backend.single('GET', 'payroll_vouchers');
      expect(
        vouchers.url.queryParameters['id'],
        'in.("voucher-1","voucher-2")',
      );
      expect(vouchers.url.queryParameters['tenant_id'], 'eq.$_tenantA');
      // A read by another column is unchanged: row-level security scopes it.
      final byRut = backend.single('GET', 'customers');
      expect(byRut.url.queryParameters['rut'], 'eq.11111111-1');
      expect(byRut.url.queryParameters.containsKey('tenant_id'), isFalse);
    });

    test('a table with shared rows keeps the rows without tenant', () async {
      final backend = _Backend();
      final database = DatabaseService(
        client: backend.client(),
        tenantService: _tenantService(_tenantA),
      );
      addTearDown(database.dispose);

      await database.selectById('expense_categories', 'category-1');

      final read = backend.single('GET', 'expense_categories');
      expect(read.url.queryParameters['id'], 'eq.category-1');
      expect(
        read.url.queryParameters['or'],
        '(tenant_id.eq.$_tenantA,tenant_id.is.null)',
      );
      expect(read.url.queryParameters.containsKey('tenant_id'), isFalse);
    });

    test('a session without a shop reads under row-level security', () async {
      final backend = _Backend();
      final database = DatabaseService(
        client: backend.client(),
        tenantService: _tenantService(null),
      );
      addTearDown(database.dispose);

      await database.selectById('bikes', 'bike-1');
      await database.selectById('tenants', _tenantA);

      final bike = backend.single('GET', 'bikes');
      expect(bike.url.queryParameters['id'], 'eq.bike-1');
      expect(bike.url.queryParameters.containsKey('tenant_id'), isFalse);
      final tenant = backend.single('GET', 'tenants');
      expect(tenant.url.queryParameters.containsKey('tenant_id'), isFalse);
    });
  });

  group('source contract', () {
    test(
        'no query in lib/ reaches a tenant table by id, or writes it by any '
        'key, without filtering tenant_id', () {
      final unexpected = <String>[];
      final rlsOnly = <String, int>{};
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final query
            in _unscopedQueries(entity.path, entity.readAsStringSync())) {
          final key = '${query.path} ${query.table}';
          if (query.kind == _readById && _rlsOnlyReads.containsKey(key)) {
            rlsOnly[key] = (rlsOnly[key] ?? 0) + 1;
          } else {
            unexpected.add(
              '${query.path}:${query.line} ${query.table} ${query.kind}',
            );
          }
        }
      }

      expect(
        unexpected,
        isEmpty,
        reason: 'Add .eq(\'tenant_id\', …) with the tenant the code already '
            'has, list the table in _tablesWithoutTenantColumn when it has no '
            'tenant_id, or list a read that serves sessions with no shop in '
            '_rlsOnlyReads with the reason.',
      );
      expect(
        rlsOnly,
        {for (final key in _rlsOnlyReads.keys) key: 1},
        reason: 'Each _rlsOnlyReads entry names exactly one read; update it '
            'when that read moves, gains its tenant or a second one appears.',
      );
    });

    test('the scanner sees unscoped queries and their tenant-scoped fixes', () {
      const writeById = '''
await _client.from('f29_declarations').update({
  'status': 'paid', // "it's" in a comment must not open a string
  'notes': 'Folio \${row['folio']}',
}).eq('id', f29Id);
''';
      const scopedWrite = '''
await _client
    .from('attendances')
    .delete()
    .eq('id', attendanceId)
    .eq('tenant_id', tenantId);
''';
      const insideComment = '''
/// await _client.from('attendances').delete().eq('id', id);
''';
      // Listing the column is not filtering by it.
      const readById = '''
final row = await _client
    .from('customers')
    .select('id, name, tenant_id')
    .eq('id', customerId)
    .maybeSingle();
''';
      const conditionallyScopedRead = '''
var query = _client.from('products').select().inFilter('id', ids);
if (tenantId != null) {
  query = query.eq('tenant_id', tenantId);
}
''';
      const writeByKey = '''
await _client
    .from('message_reactions')
    .delete()
    .eq('message_id', messageId)
    .eq('reactor_user_id', userId);
''';
      const readByKey = '''
await _client.from('messages').select().eq('conversation_id', id);
''';

      List<String> scan(String source) => [
            for (final query in _unscopedQueries('a.dart', source))
              '${query.path}:${query.line} ${query.table} ${query.kind}',
          ];

      expect(scan(writeById), ['a.dart:1 f29_declarations $_writeById']);
      expect(scan(scopedWrite), isEmpty);
      expect(scan(insideComment), isEmpty);
      expect(scan(readById), ['a.dart:2 customers $_readById']);
      expect(scan(conditionallyScopedRead), isEmpty);
      expect(scan(writeByKey), ['a.dart:2 message_reactions $_writeByKey']);
      expect(scan(readByKey), isEmpty);
    });
  });
}

/// Tables without a `tenant_id` column, and why a filter by it would fail.
/// Every other table is tenant-scoped.
const _tablesWithoutTenantColumn = {
  'tenants': 'the tenant row itself: its id already names the tenant',
  'spreadsheet_cells': 'cells hang from their spreadsheet, which has the '
      'tenant',
  'bike_catalog': 'the bike catalog every shop shares',
};

/// Reads by id that also serve sessions with no shop of their own, where
/// row-level security alone scopes the row. Each entry is one statement.
const _rlsOnlyReads = {
  'lib/modules/bikeshop/services/bikeshop_service.dart mechanic_jobs':
      'getJobById also feeds the store customer chat panel '
          '(customer_chat_context_panel.dart), whose session has no ERP '
          'tenant',
  'lib/modules/messaging/services/messaging_service.dart messages':
      'getMessagesByIds serves ChatProvider in the store customer chat too',
  'lib/public_store/services/public_inventory_service.dart product_brands':
      'global brands have no tenant; canonicalPublicProductBrandNames keeps '
          'this shop and the global rows and drops any other shop',
};

const _readById = 'read by id';
const _writeById = 'write by id';
const _writeByKey = 'write by key';

final _queryStart = RegExp(
  r'''^\.from\(\s*['"]([a-z0-9_]+)['"]\s*\)\s*\.(select|update|delete)\(''',
);
final _idFilter = RegExp(r'''\.(eq|inFilter)\(\s*['"]id['"]''');
final _tenantFilter = RegExp(
  r'''\.(eq|inFilter|match|filter)\(\s*\{?\s*['"]tenant_id['"]|\.or\(\s*['"]tenant_id\.''',
);

/// Every statement in [source] that starts at `.from('<table>')` on a tenant
/// table and reads it by id, or updates or deletes it by any key, without a
/// `tenant_id` filter. A filter added later to the same query variable
/// (`query = query.eq('tenant_id', …)`) in the enclosing block counts.
List<({String path, int line, String table, String kind})> _unscopedQueries(
  String path,
  String source,
) {
  final kinds = _lex(source);
  final text = String.fromCharCodes([
    for (var i = 0; i < source.length; i++)
      kinds[i] == _Kind.comment ? 0x20 : source.codeUnitAt(i),
  ]);

  // Index just past the statement or block that starts at [start]: its `;` at
  // depth 0, or the bracket that closes the enclosing one.
  int endOf(int start, {bool block = false}) {
    var depth = 0;
    var end = start;
    for (; end < text.length; end++) {
      if (kinds[end] != _Kind.code) continue;
      final char = text[end];
      if ('([{'.contains(char)) depth++;
      if (')]}'.contains(char) && --depth < 0) break;
      if (!block && char == ';' && depth == 0) break;
    }
    return end;
  }

  final offenders = <({String path, int line, String table, String kind})>[];
  for (final from in RegExp(r'\.from\(').allMatches(text)) {
    if (kinds[from.start] != _Kind.code) continue;
    final end = endOf(from.start);
    var statement = text.substring(from.start, end);
    final nested = RegExp(r'\.from\(').allMatches(statement).skip(1);
    if (nested.isNotEmpty) {
      statement = statement.substring(0, nested.first.start);
    }
    final query = _queryStart.firstMatch(statement);
    if (query == null ||
        _tablesWithoutTenantColumn.containsKey(query[1]) ||
        _tenantFilter.hasMatch(statement)) {
      continue;
    }
    final byId = _idFilter.hasMatch(statement);
    final String kind;
    if (query[2] != 'select') {
      kind = byId ? _writeById : _writeByKey;
    } else if (byId) {
      kind = _readById;
    } else {
      continue;
    }
    final before =
        text.substring(from.start < 200 ? 0 : from.start - 200, from.start);
    final variable =
        RegExp(r'(\w+)\s*=\s*[\w.]+\s*$').firstMatch(before)?.group(1);
    if (variable != null &&
        RegExp(
          '\\b$variable\\s*=\\s*$variable\\s*\\.\\s*(eq|inFilter)'
          r'''\(\s*['"]tenant_id['"]''',
        ).hasMatch(text.substring(end, endOf(end, block: true)))) {
      continue;
    }
    offenders.add((
      path: path,
      line: '\n'.allMatches(text.substring(0, from.start)).length + 1,
      table: query[1]!,
      kind: kind,
    ));
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
/// matched one row; a read returns the [rows] of its table.
class _Backend {
  _Backend({this.rows = const {}});

  final Map<String, List<Map<String, dynamic>>> rows;
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
    final wantsObject = request.headers['Accept']?.contains(
          'application/vnd.pgrst.object+json',
        ) ??
        false;
    if (request.method == 'GET') {
      final found = rows[request.url.pathSegments.last] ?? const [];
      if (!wantsObject) return _json(request, found);
      if (found.isNotEmpty) return _json(request, found.first);
      return http.Response(
        jsonEncode({
          'code': 'PGRST116',
          'details': 'The result contains 0 rows',
          'hint': null,
          'message': 'JSON object requested, multiple (or no) rows returned',
        }),
        406,
        headers: const {'content-type': 'application/json'},
        request: request,
      );
    }
    final returnsRow =
        request.headers['Prefer']?.contains('return=representation') ?? false;
    if (!returnsRow) return http.Response('', 204, request: request);
    final row = <String, dynamic>{
      'id': request.url.queryParameters['id']?.replaceFirst('eq.', ''),
      if (request.body.isNotEmpty)
        ...jsonDecode(request.body) as Map<String, dynamic>,
    };
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
