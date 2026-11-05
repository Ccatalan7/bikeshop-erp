import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vinabike_erp/shared/services/network/network_resilience.dart';

/// Lo que el servidor de prueba hace con cada intento, en orden.
typedef _Step = FutureOr<http.StreamedResponse> Function(http.BaseRequest);

class _ScriptedSender implements StageAwareSender {
  _ScriptedSender(this.steps);

  final List<_Step> steps;
  final List<http.BaseRequest> sent = [];
  final List<bool> fresh = [];

  @override
  Future<http.StreamedResponse> send(
    http.BaseRequest request, {
    required Duration headerTimeout,
    required Duration idleTimeout,
    bool freshConnection = false,
  }) async {
    sent.add(request);
    fresh.add(freshConnection);
    final index = sent.length - 1;
    if (index >= steps.length) {
      throw StateError('Se intentó más veces de lo previsto ($index)');
    }
    return steps[index](request);
  }

  @override
  void close() {}
}

_Step _ok([int status = 200, String body = '{}']) =>
    (request) => http.StreamedResponse(Stream.value(utf8.encode(body)), status,
        request: request);

_Step _notSent() => (request) => throw TransportFailure(
      uri: request.url,
      cause: const _FakeSocketError('Failed host lookup'),
      notSent: true,
    );

_Step _cut() => (request) => throw TransportFailure(
      uri: request.url,
      cause: const _FakeSocketError('Connection reset by peer'),
      notSent: false,
    );

class _FakeSocketError {
  const _FakeSocketError(this.message);
  final String message;
  @override
  String toString() => 'SocketException: $message';
}

class _MemoryStore implements UnsavedChangesStore {
  final Map<String, String> values = {};
  @override
  Future<Map<String, String>> readAll() async => Map.of(values);
  @override
  Future<void> remove(String id) async => values.remove(id);
  @override
  Future<void> write(String id, String value) async => values[id] = value;
}

const _base = 'https://demo.supabase.co';

String _jwt(String sub) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({
        'sub': sub,
        'role': 'authenticated'
      })}.firma';
}

http.Request _post(String path, Object body, {Map<String, String>? headers}) =>
    http.Request('POST', Uri.parse('$_base$path'))
      ..headers['authorization'] = 'Bearer ${_jwt('usuario-1')}'
      ..headers['apikey'] = 'llave-publica'
      ..headers['content-type'] = 'application/json'
      ..headers.addAll(headers ?? const {})
      ..body = jsonEncode(body);

http.Request _request(String method, String path, [Object? body]) =>
    http.Request(method, Uri.parse('$_base$path'))
      ..headers['authorization'] = 'Bearer ${_jwt('usuario-1')}'
      ..headers['content-type'] = 'application/json'
      ..body = body == null ? '' : jsonEncode(body);

void main() {
  late ConnectionStatus status;
  late _MemoryStore store;
  late UnsavedChangesJournal journal;

  setUp(() {
    StableOperationKeys.resetForTest();
    RecordIdentities.resetForTest();
    RecordIdentities.persist = false;
    status = ConnectionStatus();
    store = _MemoryStore();
    journal = UnsavedChangesJournal(
      store: store,
      currentUserId: () => 'usuario-1',
      currentAccessToken: () => 'token-fresco',
      apiKey: 'llave-publica',
    );
  });

  tearDown(() {
    journal.dispose();
    status.dispose();
  });

  ResilientHttpClient client(_ScriptedSender sender) => ResilientHttpClient(
        sender: sender,
        status: status,
        journal: journal,
        delay: (_) async {},
      );

  group('qué se puede volver a mandar', () {
    test('una lectura se reintenta aunque se haya cortado', () {
      final safety = classifyRequest(
        'POST',
        Uri.parse('$_base/rest/v1/rpc/get_checked_in_employees'),
        body: utf8.encode('{}'),
      );
      expect(safety.effect, RequestEffect.read);
      expect(safety.replayIsHarmless, isTrue);
    });

    test('un comando con llave de operación es repetible', () {
      final safety = classifyRequest(
        'POST',
        Uri.parse('$_base/rest/v1/rpc/register_sales_payment_with_invoice_tax'),
        body: utf8.encode(
            jsonEncode({'p_idempotency_key': 'pago-1', 'p_amount': 12000})),
      );
      expect(safety.effect, RequestEffect.keyedCommand);
      expect(safety.idempotencyKey, 'pago-1');
      expect(safety.label, 'Pago de venta');
      expect(safety.detail, '\$ 12.000');
    });

    test('p_key es el nombre de un ajuste, no una llave de operación', () {
      final safety = classifyRequest(
        'POST',
        Uri.parse('$_base/rest/v1/rpc/upsert_company_setting'),
        body: utf8.encode(jsonEncode({'p_key': 'iva', 'p_value': '19'})),
      );
      expect(safety.effect, RequestEffect.insert);
    });

    test('una función con nombre de lectura que consume un folio no es lectura',
        () {
      final safety = classifyRequest(
        'POST',
        Uri.parse('$_base/rest/v1/rpc/get_next_document_number'),
        body: utf8.encode('{}'),
      );
      expect(safety.effect, RequestEffect.insert);
      expect(safety.replayIsHarmless, isFalse);
      // Pero no es un cambio de la persona: si no llega, la venta pide su
      // folio otra vez; reenviarlo desde «Sin guardar» sólo gastaba uno.
      expect(safety.belongsInJournal, isFalse);
    });

    test('un comando de verdad sí queda en «Sin guardar» si no llega', () {
      final safety = classifyRequest(
        'POST',
        Uri.parse('$_base/rest/v1/rpc/upsert_company_setting'),
        body: utf8.encode(jsonEncode({'p_key': 'iva', 'p_value': '19'})),
      );
      expect(safety.belongsInJournal, isTrue);
    });

    test('un PATCH es repetible y un alta no', () {
      expect(
        classifyRequest(
                'PATCH', Uri.parse('$_base/rest/v1/attendances?id=eq.7'))
            .effect,
        RequestEffect.repeatableWrite,
      );
      final insert = classifyRequest(
        'POST',
        Uri.parse('$_base/rest/v1/customers'),
        body: utf8.encode(jsonEncode({'name': 'Juan Pérez'})),
      );
      expect(insert.effect, RequestEffect.insert);
      expect(insert.label, 'Cliente');
      expect(insert.detail, 'Juan Pérez');
    });

    test('un alta con merge-duplicates es repetible', () {
      expect(
        classifyRequest('POST', Uri.parse('$_base/rest/v1/bike_system_states'),
            headers: {
              'Prefer': 'resolution=merge-duplicates,return=representation'
            }).effect,
        RequestEffect.repeatableWrite,
      );
    });

    test('la bandeja del taller y WhatsApp cuidan lo suyo', () {
      final safety = classifyRequest(
        'POST',
        Uri.parse('$_base/rest/v1/rpc/save_mechanic_job_lines_v1'),
        body: utf8.encode(jsonEncode({'p_operation_key': 'k'})),
      );
      expect(safety.durableElsewhere, isTrue);
    });
  });

  group('el transporte', () {
    test('una lectura cortada se reintenta y la conexión vuelve', () async {
      final sender = _ScriptedSender([_cut(), _ok(200, '[1]')]);
      final response = await client(sender)
          .send(_post('/rest/v1/rpc/get_checked_in_employees', {}));
      expect(await response.stream.bytesToString(), '[1]');
      expect(sender.sent, hasLength(2));
      expect(status.isOffline, isFalse);
      expect(journal.pendingCount, 0);
    });

    test('un alta que no salió se reintenta, y una que se cortó no', () async {
      final again = _ScriptedSender([_notSent(), _ok(201)]);
      final created = await client(again)
          .send(_post('/rest/v1/customers', {'name': 'Ana'}));
      expect(created.statusCode, 201);
      expect(again.sent, hasLength(2));
      expect(again.fresh, everyElement(isTrue),
          reason: 'un alta sale por una conexión nueva');

      final once = _ScriptedSender([_cut()]);
      await expectLater(
        client(once).send(_post('/rest/v1/customers', {'name': 'Ana'})),
        throwsA(isA<http.ClientException>()),
      );
      expect(once.sent, hasLength(1),
          reason: 'pudo haber llegado: no se repite');
      await Future<void>.delayed(Duration.zero);
      final pending = journal.pending.single;
      expect(pending.label, 'Cliente');
      expect(pending.detail, 'Ana');
      expect(pending.notSent, isFalse);
      expect(pending.headers.containsKey('authorization'), isFalse,
          reason: 'la sesión no se guarda en el equipo');
      expect(pending.userId, 'usuario-1');
    });

    test('un comando con llave cortado se reintenta con la misma llave',
        () async {
      final sender = _ScriptedSender([_cut(), _cut(), _ok()]);
      final response = await client(sender).send(_post(
        '/rest/v1/rpc/create_atomic_sales_checkout',
        {'p_checkout_key': 'venta-9', 'p_items': []},
      ));
      expect(response.statusCode, 200);
      expect(sender.sent, hasLength(3));
      for (final request in sender.sent.cast<http.Request>()) {
        expect(jsonDecode(request.body)['p_checkout_key'], 'venta-9');
      }
    });

    test('el refresco de la sesión sólo se reintenta si no salió', () async {
      final sender = _ScriptedSender([_cut()]);
      await expectLater(
        client(sender).send(_post(
            '/auth/v1/token?grant_type=refresh_token', {'refresh_token': 'r'})),
        throwsA(isA<http.ClientException>()),
      );
      expect(sender.sent, hasLength(1));
      expect(journal.pendingCount, 0,
          reason: 'la sesión no va a «Sin guardar»');
    });

    test('503 se reintenta siempre; 504 sólo si es repetible', () async {
      final busy = _ScriptedSender([_ok(503), _ok(201)]);
      expect(
        (await client(busy).send(_post('/rest/v1/customers', {'name': 'B'})))
            .statusCode,
        201,
      );
      final gateway = _ScriptedSender([_ok(504)]);
      expect(
        (await client(gateway).send(_post('/rest/v1/customers', {'name': 'C'})))
            .statusCode,
        504,
      );
      expect(gateway.sent, hasLength(1));
    });

    test(
        'sin red todo el plazo: queda en «Sin guardar» y quien llamó se entera',
        () async {
      final sender = _ScriptedSender(List.generate(6, (_) => _notSent()));
      await expectLater(
        client(sender).send(_request('PATCH', '/rest/v1/attendances?id=eq.7',
            {'check_out': '2026-11-04T18:00:00Z'})),
        throwsA(isA<http.ClientException>()),
      );
      expect(sender.sent, hasLength(6));
      expect(status.isOffline, isTrue);
      await Future<void>.delayed(Duration.zero);
      final pending = journal.pending.single;
      expect(pending.label, 'Asistencia');
      expect(pending.notSent, isTrue);
      expect(pending.effect, RequestEffect.repeatableWrite);
    });
  });

  group('la bandeja de lo que no llegó', () {
    Future<UnsavedChange> failed(
      _ScriptedSender sender,
      http.BaseRequest request,
    ) async {
      try {
        await client(sender).send(request);
      } catch (_) {}
      await Future<void>.delayed(Duration.zero);
      return journal.pending.first;
    }

    test('un guardado igual que sí llega resuelve el pendiente', () async {
      await failed(_ScriptedSender([_cut()]),
          _post('/rest/v1/customers', {'name': 'Dora'}));
      expect(journal.pendingCount, 1);
      await client(_ScriptedSender([_ok(201)]))
          .send(_post('/rest/v1/customers', {'name': 'Dora'}));
      expect(journal.pendingCount, 0);
    });

    test('volver a guardar lo mismo un minuto después lo resuelve igual',
        () async {
      await failed(
          _ScriptedSender([_cut()]),
          _post('/rest/v1/customers', {
            'name': 'Dora',
            'created_at': '2026-11-04T12:00:00Z',
            'updated_at': '2026-11-04T12:00:00Z',
          }));
      await client(_ScriptedSender([_ok(201)]))
          .send(_post('/rest/v1/customers', {
        'updated_at': '2026-11-04T12:01:00Z',
        'name': 'Dora',
        'created_at': '2026-11-04T12:01:00Z',
      }));
      expect(journal.pendingCount, 0);
    });

    test('un cambio más nuevo al mismo registro manda sobre el viejo',
        () async {
      await failed(_ScriptedSender(List.generate(6, (_) => _notSent())),
          _request('PATCH', '/rest/v1/customers?id=eq.3', {'phone': '1'}));
      await client(_ScriptedSender([_ok(204)])).send(
          _request('PATCH', '/rest/v1/customers?id=eq.3', {'phone': '2'}));
      expect(journal.pendingCount, 0);
    });

    test('al volver la conexión reenvía lo seguro y deja lo dudoso', () async {
      await failed(_ScriptedSender(List.generate(6, (_) => _notSent())),
          _request('PATCH', '/rest/v1/attendances?id=eq.7', {'x': 1}));
      await failed(_ScriptedSender([_cut()]),
          _post('/rest/v1/customers', {'name': 'Eva'}));
      expect(journal.pendingCount, 2);

      final replays = _ScriptedSender([_ok(204)]);
      final transport = client(replays);
      journal.attach(
        send: transport.send,
        currentUserId: () => 'usuario-1',
        currentAccessToken: () => 'token-fresco',
        apiKey: 'llave-publica',
        status: status,
      );
      final saved = await journal.resendSafe();
      expect(saved, 1);
      expect(replays.sent.single.method, 'PATCH');
      expect(
          replays.sent.single.headers['authorization'], 'Bearer token-fresco');
      expect(
          replays.sent.single.headers
              .containsKey(UnsavedChangesJournal.replayHeader),
          isFalse);
      expect(journal.pending.single.label, 'Cliente',
          reason: 'el alta que pudo llegar espera a la persona');
    });

    test('un reenvío que vuelve a fallar no crea otra entrada', () async {
      final change = await failed(_ScriptedSender([_cut()]),
          _post('/rest/v1/customers', {'name': 'Fito'}));
      final transport = client(_ScriptedSender([_cut()]));
      journal.attach(
        send: transport.send,
        currentUserId: () => 'usuario-1',
        currentAccessToken: () => 'token-fresco',
        apiKey: 'llave-publica',
        status: status,
      );
      expect(await journal.resend(change.id), UnsavedChangeResend.stillOffline);
      expect(journal.pendingCount, 1);
      expect(journal.pending.single.attempts, 2);
    });

    test('lo que el servidor rechaza queda con su motivo', () async {
      final change = await failed(_ScriptedSender([_cut()]),
          _post('/rest/v1/customers', {'name': 'Gabo'}));
      final transport = client(_ScriptedSender([
        _ok(409, jsonEncode({'message': 'duplicate key value'})),
      ]));
      journal.attach(
        send: transport.send,
        currentUserId: () => 'usuario-1',
        currentAccessToken: () => 'token-fresco',
        apiKey: 'llave-publica',
        status: status,
      );
      expect(await journal.resend(change.id), UnsavedChangeResend.rejected);
      expect(journal.pending.single.lastError, contains('duplicate key value'));
    });

    void attachTo(ResilientHttpClient transport) => journal.attach(
          send: transport.send,
          currentUserId: () => 'usuario-1',
          currentAccessToken: () => 'token-fresco',
          apiKey: 'llave-publica',
          status: status,
        );

    test('una edición que llega pero no calza con nada no se da por guardada',
        () async {
      await failed(
          _ScriptedSender(List.generate(6, (_) => _notSent())),
          _request('PATCH', '/rest/v1/customers?id=eq.3&updated_at=eq.x',
              {'phone': '9'}));
      final replays = _ScriptedSender([_ok(200, '[]')]);
      attachTo(client(replays));

      expect(await journal.resendSafe(), 0);
      final change = journal.pending.single;
      expect(change.serverRejected, isTrue);
      expect(change.lastError, contains('No se aplicó'));

      await journal.resendSafe();
      expect(replays.sent, hasLength(1),
          reason: 'reenviarlo solo daría lo mismo: espera a la persona');
    });

    test('lo que el servidor rechazó no se vuelve a mandar solo', () async {
      StableOperationKeys.hold('venta-1');
      await failed(
        _ScriptedSender(List.generate(6, (_) => _cut())),
        _post('/rest/v1/rpc/create_atomic_sales_checkout',
            {'p_checkout_key': 'venta-1'}),
      );
      final replays = _ScriptedSender([
        _ok(400, jsonEncode({'message': 'La caja está cerrada'})),
      ]);
      attachTo(client(replays));

      expect(await journal.resendSafe(), 0);
      expect(
          journal.pending.single.lastError, contains('La caja está cerrada'));
      await journal.resendSafe();
      expect(replays.sent, hasLength(1));
    });

    test('un 500 al reenviar no corta el resto ni lo da por rechazado',
        () async {
      StableOperationKeys.hold('venta-1');
      StableOperationKeys.hold('venta-2');
      await failed(
        _ScriptedSender(List.generate(6, (_) => _cut())),
        _post('/rest/v1/rpc/create_atomic_sales_checkout',
            {'p_checkout_key': 'venta-1'}),
      );
      await failed(
        _ScriptedSender(List.generate(6, (_) => _cut())),
        _post('/rest/v1/rpc/create_atomic_sales_checkout',
            {'p_checkout_key': 'venta-2'}),
      );
      final replays = _ScriptedSender([_ok(500), _ok(200)]);
      attachTo(client(replays));

      // La respuesta del 500 ya cuenta como «volvió la conexión» y dispara su
      // propio reenvío: lo que importa es que cada venta salga una sola vez.
      await journal.resendSafe();
      await pumpEventQueue();
      final keys = [
        for (final request in replays.sent)
          jsonDecode((request as http.Request).body)['p_checkout_key'],
      ];
      expect(keys, ['venta-1', 'venta-2']);
      final left = journal.pending.single;
      expect(left.idempotencyKey, 'venta-1');
      expect(left.serverRejected, isFalse);
      expect(left.attempts, 2);
    });

    test('queda guardada en el equipo y vuelve al abrir la app', () async {
      await failed(_ScriptedSender([_cut()]),
          _post('/rest/v1/customers', {'name': 'Hugo'}));
      final reopened = UnsavedChangesJournal(
        store: store,
        currentUserId: () => 'usuario-1',
      );
      await reopened.load();
      expect(reopened.pending.single.detail, 'Hugo');
      reopened.dispose();
    });

    test('lo de otra cuenta no se le muestra a quien está conectado', () async {
      await failed(_ScriptedSender([_cut()]),
          _post('/rest/v1/customers', {'name': 'Ivi'}));
      final other = UnsavedChangesJournal(
        store: store,
        currentUserId: () => 'usuario-2',
      );
      await other.load();
      expect(other.pending, isEmpty);
      other.dispose();
    });
  });

  group('llaves sostenidas, altas con identidad y la nota previa', () {
    const id = '0b5f8f1e-6a3c-4c39-9d2a-2f4f6f8a9b10';

    void attachTo(ResilientHttpClient transport) => journal.attach(
          send: transport.send,
          currentUserId: () => 'usuario-1',
          currentAccessToken: () => 'token-fresco',
          apiKey: 'llave-publica',
          status: status,
        );

    Future<Object?> failing(
        _ScriptedSender sender, http.BaseRequest request) async {
      Object? error;
      try {
        await client(sender).send(request);
      } catch (caught) {
        error = caught;
      }
      await pumpEventQueue();
      return error;
    }

    test('un alta que trae su id se reconoce por él', () {
      final one = classifyRequest(
        'POST',
        Uri.parse('$_base/rest/v1/customers?select=*'),
        body: utf8.encode(jsonEncode({'id': id, 'name': 'Dora'})),
      );
      expect(one.effect, RequestEffect.identifiedInsert);
      expect(one.idempotencyKey, id);
      expect(one.replayIsHarmless, isTrue);

      final keyed = classifyRequest(
        'POST',
        Uri.parse('$_base/rest/v1/sales_payments'),
        body: utf8.encode(
            jsonEncode({'id': id, 'idempotency_key': 'pago-7', 'amount': 5})),
      );
      expect(keyed.idempotencyKey, 'pago-7',
          reason: 'la llave del dueño manda sobre el id de la llamada');

      final batch = classifyRequest(
        'POST',
        Uri.parse('$_base/rest/v1/expense_lines'),
        body: utf8.encode(jsonEncode([
          {'id': id, 'amount': 1},
          {'amount': 2},
        ])),
      );
      expect(batch.effect, RequestEffect.insert,
          reason: 'un lote con una fila sin id puede quedar dos veces');

      final notUuid = classifyRequest(
        'POST',
        Uri.parse('$_base/rest/v1/website_content'),
        body: utf8.encode(jsonEncode({'id': 'hero', 'body': 'x'})),
      );
      expect(notUuid.effect, RequestEffect.insert);
    });

    test('un alta con identidad cortada después de salir se reintenta',
        () async {
      final sender = _ScriptedSender([_cut(), _ok(201, '[]')]);
      final response = await client(sender)
          .send(_post('/rest/v1/customers', {'id': id, 'name': 'Dora'}));
      expect(response.statusCode, 201);
      expect(sender.sent, hasLength(2));
      expect(journal.pendingCount, 0);
    });

    test('un comando con llave por intento no se reenvía solo', () async {
      // Una pantalla que saca una llave nueva en cada intento: si la persona
      // lo repite, el reenvío y su repetición quedarían dos veces.
      final error = await failing(
        _ScriptedSender(List.generate(6, (_) => _notSent())),
        _post('/rest/v1/rpc/add_purchase_list_item_v1',
            {'p_operation_key': 'una-vez', 'p_product_id': 'p1'}),
      );
      expect((error! as ErpConnectionException).willResend, isFalse);
      final replays = _ScriptedSender([_ok(200)]);
      attachTo(client(replays));
      expect(await journal.resendSafe(), 0);
      expect(replays.sent, isEmpty);
      expect(journal.resendsByItself(journal.pending.single), isFalse);
    });

    test('una llave sostenida por su dueño se reenvía sola', () async {
      StableOperationKeys.hold('carro-1');
      final error = await failing(
        _ScriptedSender(List.generate(6, (_) => _notSent())),
        _post('/rest/v1/rpc/create_atomic_sales_checkout',
            {'p_checkout_key': 'carro-1'}),
      );
      final exception = error! as ErpConnectionException;
      expect(exception.willResend, isTrue);
      expect(exception.message, contains('se envía solo'));

      final replays = _ScriptedSender([_ok(200)]);
      attachTo(client(replays));
      expect(await journal.resendSafe(), 1);
      expect(journal.pendingCount, 0);
    });

    test('cuando el dueño la suelta, espera a la persona', () async {
      StableOperationKeys.hold('carro-2');
      await failing(
        _ScriptedSender(List.generate(6, (_) => _notSent())),
        _post('/rest/v1/rpc/create_atomic_sales_checkout',
            {'p_checkout_key': 'carro-2'}),
      );
      StableOperationKeys.release('carro-2');
      final replays = _ScriptedSender([_ok(200)]);
      attachTo(client(replays));
      expect(await journal.resendSafe(), 0);
      expect(journal.pendingCount, 1);
    });

    test('repetir con la misma llave reemplaza al pendiente', () async {
      StableOperationKeys.hold('carro-3');
      for (var i = 0; i < 2; i++) {
        await failing(
          _ScriptedSender(List.generate(6, (_) => _notSent())),
          _post('/rest/v1/rpc/create_atomic_sales_checkout',
              {'p_checkout_key': 'carro-3', 'p_total': 1000 + i}),
        );
      }
      expect(journal.pendingCount, 1);
      final body =
          utf8.decode(base64Decode(journal.pending.single.bodyBase64!));
      expect(jsonDecode(body)['p_total'], 1001,
          reason: 'queda lo último que la persona dejó');
    });

    // Como responde producción (medido el 2026-11-04): con RLS, Postgres no
    // pone los valores de la llave en el detalle del choque.
    final pkeyConflict = jsonEncode({
      'code': '23505',
      'details': null,
      'hint': null,
      'message':
          'duplicate key value violates unique constraint "customers_pkey"',
    });

    test('un alta con identidad que choca con su propia fila ya estaba',
        () async {
      final error = await failing(
        _ScriptedSender(List.generate(6, (_) => _cut())),
        _post('/rest/v1/customers?select=*', {'id': id, 'name': 'Dora'}),
      );
      expect((error! as ErpConnectionException).kept, isTrue);
      final change = journal.pending.single;
      expect(change.effect, RequestEffect.identifiedInsert);
      expect(change.resendIsHarmless, isTrue);

      final replays = _ScriptedSender([
        _ok(409, pkeyConflict),
        _ok(
            200,
            jsonEncode([
              {'id': id}
            ])),
      ]);
      attachTo(client(replays));
      expect(await journal.resend(change.id), UnsavedChangeResend.saved);
      expect(journal.pendingCount, 0);
      final lookup = replays.sent.last;
      expect(lookup.method, 'GET');
      expect(lookup.url.path, '/rest/v1/customers');
      expect(lookup.url.queryParameters['id'], 'eq.$id');
      expect(lookup.headers['authorization'], 'Bearer token-fresco');
    });

    test('un choque con otra llave única no se da por guardado', () async {
      await failing(
        _ScriptedSender(List.generate(6, (_) => _cut())),
        _post('/rest/v1/customers', {'id': id, 'rut': '11.111.111-1'}),
      );
      final change = journal.pending.single;
      attachTo(client(_ScriptedSender([
        _ok(
            409,
            jsonEncode({
              'code': '23505',
              'details': null,
              'message':
                  'duplicate key value violates unique constraint "customers_rut_key"',
            })),
        _ok(200, '[]'),
      ])));
      expect(await journal.resend(change.id), UnsavedChangeResend.rejected);
      expect(journal.pending.single.serverRejected, isTrue);
    });

    test('otro cliente igual guardado con otra identidad lo resuelve',
        () async {
      await failing(
        _ScriptedSender(List.generate(6, (_) => _cut())),
        _post('/rest/v1/customers', {'id': id, 'name': 'Eva'}),
      );
      expect(journal.pendingCount, 1);
      await client(_ScriptedSender([_ok(201)])).send(_post('/rest/v1/customers',
          {'id': '9c2d7a4e-1b3f-4e5a-8c6d-0f1e2d3c4b5a', 'name': 'Eva'}));
      expect(journal.pendingCount, 0);
    });

    test('un cambio más nuevo deja esperando sólo lo que no tocó', () async {
      await failing(
        _ScriptedSender(List.generate(6, (_) => _notSent())),
        _request('PATCH', '/rest/v1/customers?id=eq.3',
            {'phone': '1', 'updated_at': '2026-11-04T12:00:00Z'}),
      );
      await client(_ScriptedSender([_ok(204)])).send(_request(
          'PATCH',
          '/rest/v1/customers?id=eq.3',
          {'email': 'a@b.cl', 'updated_at': 'x'}));
      final left = journal.pending.single;
      final body = jsonDecode(utf8.decode(base64Decode(left.bodyBase64!)));
      expect(body['phone'], '1');
      expect(body.containsKey('email'), isFalse);

      await client(_ScriptedSender([_ok(204)])).send(_request(
          'PATCH', '/rest/v1/customers?id=eq.3', {'phone': '2', 'email': 'c'}));
      expect(journal.pendingCount, 0);
    });

    test('mientras espera su respuesta, la nota no se ve', () async {
      final gate = Completer<http.StreamedResponse>();
      final sender = _ScriptedSender([(request) => gate.future]);
      final sending = client(sender)
          .send(_post('/rest/v1/customers', {'id': id, 'name': 'Fito'}));
      await pumpEventQueue();
      expect(store.values, hasLength(1),
          reason: 'quedó anotada en el equipo antes de salir');
      expect(journal.pendingCount, 0);

      gate.complete(await _ok(201)(sender.sent.single));
      await sending;
      await pumpEventQueue();
      expect(store.values, isEmpty);
    });

    test('si la app se cerró esperando, al abrirla aparece', () async {
      final gate = Completer<http.StreamedResponse>();
      unawaited(client(_ScriptedSender([(request) => gate.future]))
          .send(_post('/rest/v1/customers', {'name': 'Gabo'})));
      await pumpEventQueue();

      final reopened = UnsavedChangesJournal(
        store: store,
        currentUserId: () => 'usuario-1',
      );
      await reopened.load();
      final change = reopened.pending.single;
      expect(change.detail, 'Gabo');
      expect(change.notSent, isFalse,
          reason: 'pudo haber llegado antes de que se cerrara');
      expect(change.lastError, contains('La app se cerró'));
      reopened.dispose();
    });

    test('la identidad de un registro nuevo dura hasta soltarla', () async {
      final first = await RecordIdentities.of('cliente:nuevo');
      expect(await RecordIdentities.of('cliente:nuevo'), first);
      expect(StableOperationKeys.holds(first), isTrue);
      await RecordIdentities.release('cliente:nuevo');
      expect(StableOperationKeys.holds(first), isFalse);
      expect(await RecordIdentities.of('cliente:nuevo'), isNot(first));
    });

    test('la identidad de un formulario sin borrador vive con él', () {
      final identity = HeldRecordIdentity();
      final first = identity.take();
      expect(identity.take(), first);
      expect(StableOperationKeys.holds(first), isTrue);
      identity.renew();
      expect(StableOperationKeys.holds(first), isFalse);
      expect(identity.take(), isNot(first));
    });
  });

  group('un comando que dice qué versión espera', () {
    void attachTo(ResilientHttpClient transport) => journal.attach(
          send: transport.send,
          currentUserId: () => 'usuario-1',
          currentAccessToken: () => 'token-fresco',
          apiKey: 'llave-publica',
          status: status,
        );

    test('se reconoce sólo si la versión trae valor', () {
      RequestSafety classify(Map<String, Object?> body) => classifyRequest(
            'POST',
            Uri.parse('$_base/rest/v1/rpc/set_supply_need_quantity_v1'),
            body: utf8.encode(jsonEncode(body)),
          );
      expect(
          classify({'p_operation_key': 'k1', 'p_expected_version': 3})
              .versionGuarded,
          isTrue);
      expect(
          classify({'p_operation_key': 'k2', 'p_expected_version': null})
              .versionGuarded,
          isFalse);
      expect(
          classify({
            'p_operation_key': 'k3',
            'p_expected_updated_at': '2026-11-04T12:00:00Z',
          }).versionGuarded,
          isTrue);
    });

    test('se reenvía solo aunque su llave sea de una sola llamada', () async {
      // Si ya se aplicó, la versión cambió y el servidor rechaza el segundo:
      // no puede quedar dos veces aunque la persona lo haya repetido.
      try {
        await client(_ScriptedSender(List.generate(6, (_) => _notSent())))
            .send(_post('/rest/v1/rpc/set_supply_need_quantity_v1', {
          'p_operation_key': 'una-vez',
          'p_need_id': 'n1',
          'p_expected_version': 3,
          'p_quantity': 2,
        }));
      } catch (error) {
        expect((error as ErpConnectionException).willResend, isTrue);
      }
      await pumpEventQueue();
      final entry = journal.pending.single;
      expect(entry.versionGuarded, isTrue);
      expect(journal.resendsByItself(entry), isTrue);

      attachTo(client(_ScriptedSender([_ok(200)])));
      expect(await journal.resendSafe(), 1);
      expect(journal.pendingCount, 0);
    });
  });
}
