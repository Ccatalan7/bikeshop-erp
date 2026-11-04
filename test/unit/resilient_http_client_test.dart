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
}
