import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/public_store/services/cart_lock.dart';
import 'package:vinabike_erp/modules/bikeshop/services/workshop_command_notices.dart';
import 'package:vinabike_erp/modules/bikeshop/services/workshop_command_outbox.dart';

/// El disco del equipo: sobrevive a que la app se cierre. Cada "reinicio" es
/// una bandeja nueva sobre el mismo disco.
/// JSON con las llaves ordenadas: la misma huella para el mismo contenido.
String _sortedJson(Object? value) {
  Object? sorted(Object? node) => switch (node) {
        final Map map => {
            for (final key in map.keys.map((key) => '$key').toList()..sort())
              key: sorted(map[key]),
          },
        final List list => [for (final item in list) sorted(item)],
        _ => node,
      };
  return jsonEncode(sorted(value));
}

class _Disk implements WorkshopOutboxStore {
  final Map<String, String> values = {};
  bool failWrites = false;
  bool failReads = false;

  /// Escrituras que salen bien antes de que el disco falle: un corte a mitad
  /// de respaldar varias llaves.
  int? failWriteAfter;

  /// Cede el turno en cada lectura y escritura, como un almacenamiento real:
  /// dos pestañas pueden leer las dos antes de que una escriba.
  bool yieldOnIo = false;

  /// Borrados que salen bien antes de que el disco falle: un corte a mitad
  /// de sacar varias llaves.
  int? failRemoveAfter;

  /// Lo que pasa justo después de escribir una llave (otra pestaña que actúa
  /// en ese instante). Se llama una vez y se olvida.
  Future<void> Function(String key)? afterWrite;

  @override
  Future<Map<String, String>> readAll(String prefix) async {
    if (yieldOnIo) await Future<void>.delayed(Duration.zero);
    if (failReads) {
      throw const WorkshopOutboxPersistenceException('no se pudo leer');
    }
    return {
      for (final entry in values.entries)
        if (entry.key.startsWith(prefix)) entry.key: entry.value,
    };
  }

  @override
  Future<void> write(String key, String value) async {
    if (yieldOnIo) await Future<void>.delayed(Duration.zero);
    final left = failWriteAfter;
    if (left != null) {
      if (left <= 0) {
        throw const WorkshopOutboxPersistenceException('corte a mitad');
      }
      failWriteAfter = left - 1;
    }
    if (failWrites) {
      throw const WorkshopOutboxPersistenceException('disco lleno');
    }
    values[key] = value;
    final hook = afterWrite;
    if (hook != null) await hook(key);
  }

  @override
  Future<void> remove(String key) async {
    final left = failRemoveAfter;
    if (left != null) {
      if (left <= 0) {
        throw const WorkshopOutboxPersistenceException('corte al sacar');
      }
      failRemoveAfter = left - 1;
    }
    values.remove(key);
  }
}

/// El servidor: un recibo por llave, como save_bike_aggregate y
/// patch_bike_technical_facts_v1.
class _Server implements WorkshopCommandTransport {
  final Map<String, Map<String, dynamic>> receipts = {};
  final List<Map<String, dynamic>> recordedAttempts = [];
  final Set<String> storedImages = {};
  final Set<String> referencedUrls = {};
  int applied = 0;
  bool networkUp = true;
  bool loseNextAck = false;
  bool probeUp = true;
  bool attemptsSinkUp = true;
  PostgrestException? rejectWith;

  /// Un rechazo sólo para un tipo de comando (la decisión, no las líneas).
  final Map<WorkshopCommandKind, PostgrestException> rejectKind = {};

  /// Lo que se aplicó, en orden: `tipo:llave`.
  final List<String> appliedLog = [];

  /// El contenido de cada alta escrita, como la huella del recibo.
  final Map<String, String> creationPayloads = {};

  /// Lo que los comandos escritos dejaron a la vista: adjuntos del trabajo y
  /// fotos de la bici.
  final Set<String> shownUrls = {};

  /// El borrado en Storage, controlado: avisa al empezar, espera la compuerta
  /// y puede fallar.
  Completer<void>? removeStarted;
  Completer<void>? removeGate;
  Object? removeFailure;
  String currentUser = 'mecanico';

  /// El taller activo de la sesión (la misma cuenta puede cambiar de taller).
  String currentTenant = 'taller';
  final List<String> sentKeys = [];

  /// Una respuesta sin recibo completo, en vez de escribir.
  Map<String, dynamic>? malformedAck;

  /// Lo que dice el recibo de la factura cuando el guardado la pidió; null
  /// hace de un servidor que no la trae.
  Map<String, dynamic>? invoiceResult;

  /// Lo que devuelve cada llamada a `continue_mechanic_job_invoice_v1`, en
  /// orden, mientras el recibo siga en `failed`.
  final List<Map<String, dynamic>> continuationResults = [];
  int continuations = 0;

  /// Lo que dice la transición de estado de la ficha al terminar.
  Map<String, dynamic>? statusInstalledFacts;

  /// Lo que pasa en el equipo mientras la llamada está en camino.
  void Function()? duringSend;
  Future<void> Function()? duringReferenceCheck;

  @override
  bool isCurrent(WorkshopCommandScope scope) =>
      scope.userId == currentUser && scope.tenantId == currentTenant;

  @override
  Future<Map<String, dynamic>> send(
    WorkshopCommandKind kind,
    Map<String, dynamic> params,
  ) async {
    final key = params['p_operation_key'] as String;
    if (kind == WorkshopCommandKind.jobInvoiceContinuation) {
      return _continueInvoice(key);
    }
    // Lo que la app intentó enviar, llegue o no.
    sentKeys.add(key);
    duringSend?.call();
    final malformed = malformedAck;
    if (malformed != null) return malformed;
    if (!networkUp) {
      throw const WorkshopCommandTransportException('SocketException: sin red');
    }
    final receipt = receipts[key];
    if (receipt != null &&
        kind == WorkshopCommandKind.jobCreate &&
        _sortedJson(params['p_job']) != creationPayloads[key]) {
      // Como create_mechanic_job_v1: la misma llave con otro contenido.
      throw const PostgrestException(
        message: 'La llave del alta ya respalda otro trabajo',
        code: '23505',
      );
    }
    if (receipt != null) {
      return switch (kind) {
        WorkshopCommandKind.jobStatusTransition => receipt,
        // Como decide_mechanic_job_warranty_claim: el evento y `replay`.
        WorkshopCommandKind.jobWarrantyDecision ||
        WorkshopCommandKind.jobWarrantyRegistration =>
          {...receipt, 'replay': true},
        _ => {...receipt, 'replayed': true},
      };
    }
    final rejection = rejectWith ?? rejectKind[kind];
    if (rejection != null) throw rejection;
    applied++;
    appliedLog.add('${kind.wireName}:$key');
    final shown = switch (kind) {
      WorkshopCommandKind.jobCreate => (params['p_job'] as Map)['image_urls'],
      WorkshopCommandKind.jobLineSave => switch (params['p_header']) {
          final Map header => switch (header['image_urls']) {
              final Map field => field['value'],
              _ => null,
            },
          _ => null,
        },
      WorkshopCommandKind.bikeAggregateSave => switch (
            params['p_bike_payload']) {
          final Map bike => bike['image_urls'],
          _ => null,
        },
      _ => null,
    };
    if (shown is List) shownUrls.addAll(shown.map((url) => '$url'));
    if (kind == WorkshopCommandKind.jobCreate) {
      // Como create_mechanic_job_v1: el trabajo con el id del formulario, en
      // el taller de la sesión, con el número que le da la base.
      final requested = Map<String, dynamic>.from(params['p_job'] as Map);
      creationPayloads[key] = _sortedJson(requested);
      final created = {
        'operation_id': 'op-$applied',
        'operation_key': key,
        'job': {
          ...requested,
          'tenant_id': currentTenant,
          'job_number': 'PG-00$applied',
        },
      };
      receipts[key] = created;
      if (loseNextAck) {
        loseNextAck = false;
        throw const WorkshopCommandTransportException('conexión cortada');
      }
      return {...created, 'replayed': false};
    }
    if (kind == WorkshopCommandKind.jobWarrantyRegistration) {
      // Como register_mechanic_job_warranty_claim: el evento y `replay`.
      final event = {
        'id': 'registro-$applied',
        'tenant_id': currentTenant,
        'warranty_job_id': params['p_warranty_job_id'],
        'source_job_id': params['p_source_job_id'],
        'operation_key': key,
        'event_type': 'registration',
      };
      receipts[key] = event;
      if (loseNextAck) {
        loseNextAck = false;
        throw const WorkshopCommandTransportException('conexión cortada');
      }
      return {...event, 'operation_id': 'op-$applied', 'replay': false};
    }
    if (kind == WorkshopCommandKind.jobWarrantyDecision) {
      // El evento inmutable de la decisión, como la tabla del servidor.
      final event = {
        'id': 'evento-garantia-$applied',
        'tenant_id': currentTenant,
        'warranty_job_id': params['p_warranty_job_id'],
        'operation_key': key,
        'event_type': 'decision',
        'outcome': params['p_outcome'],
        'reason': params['p_reason'],
      };
      receipts[key] = event;
      if (loseNextAck) {
        loseNextAck = false;
        throw const WorkshopCommandTransportException('conexión cortada');
      }
      return {
        ...event,
        'invoice_id': 'documento-$applied',
        'operation_id': 'op-$applied',
        'replay': false,
      };
    }
    if (kind == WorkshopCommandKind.jobStatusTransition) {
      // Como transition_mechanic_job_status: su comprobante dice el trabajo,
      // el estado y la llave.
      final jobId = params['p_job_id'];
      final statusId = params['p_status_id'];
      final statusReceipt = {
        'id': 'evento-$applied',
        'job_id': jobId,
        'to_status_id': statusId,
        'operation_key': key,
        'request_snapshot': {'job_id': jobId, 'status_id': statusId},
        'response_snapshot': {
          'job_id': jobId,
          'status_id': statusId,
          'status': 'finalizado',
          'changed': true,
          'job': {'id': jobId, 'status_id': statusId, 'status': 'finalizado'},
          'installed_bike_facts': statusInstalledFacts,
        },
      };
      receipts[key] = statusReceipt;
      if (loseNextAck) {
        loseNextAck = false;
        throw const WorkshopCommandTransportException('conexión cortada');
      }
      return statusReceipt;
    }
    final invoice = invoiceResult;
    final result = {
      'operation_id': 'op-$applied',
      'params': params,
      if (params['p_invoice'] == true && invoice != null) 'invoice': invoice,
    };
    receipts[key] = result;
    if (loseNextAck) {
      loseNextAck = false;
      throw const WorkshopCommandTransportException('conexión cortada');
    }
    return {...result, 'replayed': false};
  }

  /// Como `continue_mechanic_job_invoice_v1`: con el recibo en `failed`
  /// intenta otra vez y lo anota en el recibo; si no, devuelve lo que dice.
  Map<String, dynamic> _continueInvoice(String saveKey) {
    if (!networkUp) {
      throw const WorkshopCommandTransportException('SocketException: sin red');
    }
    final receipt = receipts[saveKey];
    if (receipt == null) {
      throw const PostgrestException(
        message: 'No hay un guardado del trabajo con esa llave en este taller.',
        code: 'P0002',
      );
    }
    final current = receipt['invoice'] as Map<String, dynamic>?;
    if (current?['action'] != 'failed') {
      return {
        'operation_id': receipt['operation_id'],
        'invoice': current,
        'replayed': true,
      };
    }
    continuations++;
    final next = continuationResults.isEmpty
        ? current!
        : continuationResults.removeAt(0);
    receipts[saveKey] = {...receipt, 'invoice': next};
    return {
      'operation_id': receipt['operation_id'],
      'invoice': next,
      'replayed': false,
    };
  }

  @override
  Future<Map<String, dynamic>?> probe(
    WorkshopCommandScope scope,
    PendingWorkshopCommand command,
  ) async {
    if (command.kind == WorkshopCommandKind.jobInvoiceContinuation) {
      return null;
    }
    if (!probeUp) {
      throw const WorkshopCommandTransportException('sin red para el recibo');
    }
    if (command.kind == WorkshopCommandKind.jobStatusTransition) {
      return receipts[command.operationKey];
    }
    if (command.kind == WorkshopCommandKind.jobWarrantyDecision ||
        command.kind == WorkshopCommandKind.jobWarrantyRegistration) {
      // Por taller, trabajo y llave, como la lectura de la bandeja.
      final event = receipts[command.operationKey];
      return event != null &&
              event['tenant_id'] == scope.tenantId &&
              event['warranty_job_id'] == command.params['p_warranty_job_id']
          ? event
          : null;
    }
    if (command.kind == WorkshopCommandKind.jobCreate) {
      // Como get_mechanic_job_creation_v1: por la llave, del taller de la
      // sesión, y si el contenido enviado es el que escribió.
      final receipt = receipts[command.operationKey];
      final job = receipt?['job'];
      final sent = command.params['p_job'];
      return job is Map && job['tenant_id'] == scope.tenantId
          ? {
              ...receipt!,
              'replayed': true,
              'payload_matches': sent == null
                  ? null
                  : _sortedJson(sent) == creationPayloads[command.operationKey],
            }
          : null;
    }
    if (!probeUp) {
      throw const WorkshopCommandTransportException('sin red para el recibo');
    }
    final receipt = receipts[command.operationKey];
    return receipt == null ? null : {...receipt, 'replayed': true};
  }

  @override
  Future<void> recordAttempts(List<Map<String, dynamic>> attempts) async {
    if (!attemptsSinkUp) {
      throw const PostgrestException(
        message: 'Could not find the function',
        code: 'PGRST202',
      );
    }
    // Como record_workshop_command_attempts_v1: un intento repetido no se
    // duplica (on conflict do nothing).
    final seen = recordedAttempts.map((a) => a['attempt_id']).toSet();
    recordedAttempts
        .addAll(attempts.where((a) => !seen.contains(a['attempt_id'])));
  }

  @override
  Future<Set<String>> referencedImageUrls(
    WorkshopCommandScope scope,
    List<String> urls,
  ) async {
    await duringReferenceCheck?.call();
    return urls.toSet().intersection(referencedUrls);
  }

  @override
  Future<void> removeImages(String bucket, List<String> objectPaths) async {
    removeStarted?.complete();
    removeStarted = null;
    final gate = removeGate;
    if (gate != null) await gate.future;
    final failure = removeFailure;
    if (failure != null) throw failure;
    storedImages.removeAll(objectPaths);
  }

  /// Las URL que algún trabajo o bici muestra y cuyo archivo ya no está.
  Set<String> get brokenLinks => {
        for (final url in shownUrls)
          if (!storedImages.contains(
              url.split('/public/').last.split('/').skip(1).join('/')))
            url,
      };
}

/// Un navegador sin Web Locks: la bandeja cae al candado de su pestaña.
class _NoWebLocks implements CartLockCoordinator {
  @override
  Future<void> synchronized(String name, Future<void> Function() action) =>
      throw UnsupportedError('sin Web Locks');
}

/// Un lock propio de cada instancia: lo que había antes de coordinar las
/// pestañas.
class _InstanceLock implements CartLockCoordinator {
  Future<void> _tail = Future<void>.value();

  @override
  Future<void> synchronized(String name, Future<void> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}

PendingWorkshopCommand _creation(String key, {String customer = 'cliente-1'}) =>
    PendingWorkshopCommand(
      operationKey: key,
      kind: WorkshopCommandKind.bikeAggregateSave,
      params: {
        'p_operation_key': key,
        'p_bike_id': 'bici-$key',
        'p_customer_id': customer,
        'p_expected_bike_updated_at': null,
        'p_bike_payload': const {'brand': 'Trek'},
      },
      createdAt: DateTime.utc(2026, 9, 28, 10),
      bikeId: 'bici-$key',
      label: 'Trek $key',
    );

const _scope = WorkshopCommandScope(tenantId: 'taller', userId: 'mecanico');
const _bikeId = 'bici-1';

int _ids = 0;

WorkshopCommandOutbox _outbox(
  WorkshopOutboxStore disk,
  _Server server, {
  bool concurrent = false,
  DateTime Function()? clock,
  CartLockCoordinator? lock,
}) =>
    WorkshopCommandOutbox(
      store: disk,
      transport: server,
      idFactory: () => 'intento-${_ids++}',
      clientPlatform: 'test',
      appVersion: 'test',
      concurrentSessions: concurrent,
      clock: clock,
      lock: lock,
    );

PendingWorkshopCommand _save(
  String key, {
  List<String> images = const [],
  DateTime? createdAt,
}) =>
    PendingWorkshopCommand(
      operationKey: key,
      kind: WorkshopCommandKind.bikeAggregateSave,
      params: {
        'p_operation_key': key,
        'p_bike_id': _bikeId,
        'p_bike_payload': {'brand': 'Trek', 'image_urls': images},
      },
      createdAt: createdAt ?? DateTime.utc(2026, 9, 27, 20),
      bikeId: _bikeId,
      label: 'Trek Marlin 5',
    );

/// El guardado de líneas y ficha de un trabajo (ítem 4), con lo que el
/// formulario manda: lo que vio, las líneas y lo de «Configurar» de una bici.
PendingWorkshopCommand _lines(
  String key, {
  String jobId = 'trabajo-1',
  String? factBike,
  DateTime? createdAt,
}) =>
    PendingWorkshopCommand(
      operationKey: key,
      kind: WorkshopCommandKind.jobLineSave,
      params: {
        'p_operation_key': key,
        'p_job_id': jobId,
        'p_seen_lines': const [
          {'id': 'linea-1', 'updated_at': '2026-09-27T10:00:00.123456+00:00'},
        ],
        'p_lines': const [
          {
            'client_key': 'linea-1',
            'id': 'linea-1',
            'product_name': 'Purga de frenos',
            'quantity': 1,
            'unit_price': 15000,
            'service_configuration_data': {'brake_type': 'hydraulic_disc'},
          },
          {
            'client_key': 'nueva-pastillas',
            'product_name': 'Pastillas',
            'quantity': 1,
            'unit_price': 9000,
          },
        ],
        'p_bike_facts': [
          if (factBike != null)
            {
              'bike_id': factBike,
              'facts': [
                {
                  'key': 'brakeType',
                  'op': 'set',
                  'value': 'hydraulic_disc',
                  'expected': 'rim',
                  'expected_confirmed': true,
                },
              ],
            },
        ],
      },
      createdAt: createdAt ?? DateTime.utc(2026, 9, 28, 10),
      jobId: jobId,
      label: 'Trabajo PG-00360',
    );

/// El guardado del trabajo que pide su factura (`p_invoice`), como lo manda
/// el formulario.
PendingWorkshopCommand _billedLines(
  String key, {
  String jobId = 'trabajo-1',
  DateTime? createdAt,
}) {
  final base = _lines(key, jobId: jobId, createdAt: createdAt);
  return PendingWorkshopCommand(
    operationKey: base.operationKey,
    kind: base.kind,
    params: {...base.params, 'p_invoice': true},
    createdAt: base.createdAt,
    jobId: base.jobId,
    label: base.label,
  );
}

/// La decisión de garantía como la respalda el servicio: los parámetros del
/// RPC y el trabajo.
PendingWorkshopCommand _decision(
  String key, {
  String outcome = 'covered',
  String? reason,
  String jobId = 'trabajo-1',
  DateTime? createdAt,
}) =>
    PendingWorkshopCommand(
      operationKey: key,
      kind: WorkshopCommandKind.jobWarrantyDecision,
      params: {
        'p_warranty_job_id': jobId,
        'p_outcome': outcome,
        'p_reason': reason,
        'p_operation_key': key,
      },
      createdAt: createdAt ?? DateTime.utc(2026, 9, 29, 10),
      jobId: jobId,
      label: 'Trabajo PG-00360',
    );

/// El alta de un trabajo nuevo, como la arma el servicio: la llave es el id.
PendingWorkshopCommand _jobCreation(
  String jobId, {
  List<String> images = const [],
  DateTime? createdAt,
}) =>
    PendingWorkshopCommand(
      operationKey: jobId,
      kind: WorkshopCommandKind.jobCreate,
      params: {
        'p_operation_key': jobId,
        'p_job': {
          'id': jobId,
          'tenant_id': 'taller',
          'customer_id': 'cliente-1',
          'job_type': 'service',
          'image_urls': images,
        },
      },
      createdAt: createdAt ?? DateTime.utc(2026, 9, 29, 9),
      jobId: jobId,
      label: 'Trabajo nuevo de Ana',
    );

/// El registro de la garantía de un trabajo nuevo, como lo arma el servicio.
PendingWorkshopCommand _registration(
  String key, {
  String jobId = 'trabajo-nuevo',
}) =>
    PendingWorkshopCommand(
      operationKey: key,
      kind: WorkshopCommandKind.jobWarrantyRegistration,
      params: {
        'p_warranty_job_id': jobId,
        'p_source_job_id': 'trabajo-origen',
        'p_operation_key': key,
      },
      createdAt: DateTime.utc(2026, 9, 29, 9),
      jobId: jobId,
      label: 'Trabajo nuevo de Ana',
    );

/// El cambio de estado de un trabajo, como lo arma el servicio.
PendingWorkshopCommand _statusChange(
  String key, {
  String jobId = 'trabajo-1',
  DateTime? createdAt,
}) =>
    PendingWorkshopCommand(
      operationKey: key,
      kind: WorkshopCommandKind.jobStatusTransition,
      params: {
        'p_job_id': jobId,
        'p_status_id': 'estado-terminado',
        'p_operation_key': key,
      },
      createdAt: createdAt ?? DateTime.utc(2026, 9, 29, 10, 1),
      jobId: jobId,
      label: 'Trabajo PG-00360',
    );

const _invoiceFailed = {
  'action': 'failed',
  'invoice_id': null,
  'error': {
    'code': '23514',
    'message': 'Confirma si se recibió una bicicleta o solo un componente '
        'antes de facturar.',
  },
};

List<String> _outcomes(_Server server) => [
      for (final attempt in server.recordedAttempts)
        '${attempt['trigger']}:${attempt['outcome']}',
    ];

void main() {
  test('escrito: sale de la bandeja y su intento llega a soporte', () async {
    final disk = _Disk();
    final server = _Server();
    final outbox = _outbox(disk, server);

    final run = await outbox.submit(_scope, _save('op-1'));
    await outbox.flushAttempts(_scope);

    expect(run.outcome, WorkshopCommandOutcome.committed);
    expect(await outbox.pending(_scope), isEmpty);
    expect(_outcomes(server), ['save:committed']);
    expect(server.recordedAttempts.single['attempt_number'], 1);
  });

  test('sin red, se cierra la app y al volver se escribe una sola vez',
      () async {
    final disk = _Disk();
    final server = _Server()..networkUp = false;

    final before = _outbox(disk, server);
    final run = await before.submit(_scope, _save('op-1'));
    expect(run.outcome, WorkshopCommandOutcome.offline);
    expect((await before.pending(_scope)).single.attempts, 1);
    await before.flushAttempts(_scope);

    // La app se cierra: la bandeja nueva sólo tiene el disco.
    server.networkUp = true;
    final after = _outbox(disk, server);
    final resumed = await after.resume(_scope);

    expect(resumed.single.outcome, WorkshopCommandOutcome.committed);
    expect(resumed.single.command.attempts, 2);
    expect(server.applied, 1);
    expect(await after.pending(_scope), isEmpty);
    expect(_outcomes(server), ['save:offline', 'resume:committed']);
  });

  test('escrito pero sin respuesta: al volver, el recibo lo reconcilia',
      () async {
    final disk = _Disk();
    final server = _Server()
      ..loseNextAck = true
      ..probeUp = false;

    final before = _outbox(disk, server);
    final run = await before.submit(_scope, _save('op-1'));
    // El servidor escribió, pero la app no lo sabe: sigue pendiente.
    expect(run.outcome, WorkshopCommandOutcome.offline);
    expect(server.applied, 1);
    await before.flushAttempts(_scope);

    server.probeUp = true;
    final after = _outbox(disk, server);
    final resumed = await after.resume(_scope);

    expect(resumed.single.outcome, WorkshopCommandOutcome.reconciled);
    expect(server.applied, 1, reason: 'el reenvío no escribe dos veces');
    expect(await after.pending(_scope), isEmpty);
    expect(_outcomes(server), ['save:offline', 'resume:reconciled']);
  });

  test('respuesta perdida con el recibo a la vista: se reconcilia al tiro',
      () async {
    final server = _Server()..loseNextAck = true;
    final outbox = _outbox(_Disk(), server);

    final run = await outbox.submit(_scope, _save('op-1'));

    expect(run.outcome, WorkshopCommandOutcome.reconciled);
    expect(run.response?['operation_id'], 'op-1');
    expect(await outbox.pending(_scope), isEmpty);
  });

  test('rechazado: no queda pendiente ni se reintenta al volver', () async {
    final disk = _Disk();
    final server = _Server()
      ..rejectWith = const PostgrestException(
        message: 'Bicycle payload contains unsupported or server-owned fields',
        code: '22023',
      );
    final outbox = _outbox(disk, server);

    final run = await outbox.submit(_scope, _save('op-1'));
    expect(run.outcome, WorkshopCommandOutcome.rejected);
    expect(run.error, isA<PostgrestException>());
    await outbox.flushAttempts(_scope);

    expect(await _outbox(disk, server).resume(_scope), isEmpty);
    expect(_outcomes(server), ['save:rejected']);
    expect(server.recordedAttempts.single['error_code'], '22023');
  });

  test('la bici cambió: stale, sin escribir, y no se reintenta', () async {
    final server = _Server()
      ..rejectWith = const PostgrestException(
        message: 'Bicycle profile changed since it was loaded',
        code: '40001',
      );
    final outbox = _outbox(_Disk(), server);

    final run = await outbox.submit(_scope, _save('op-1'));

    expect(run.outcome, WorkshopCommandOutcome.stale);
    expect(server.applied, 0);
    expect(await outbox.pending(_scope), isEmpty);
  });

  test('un 504 o una sesión vencida no son rechazos: siguen pendientes', () {
    for (final code in ['504', 'PGRST301', '57014', '08006', '40P01']) {
      expect(
        classifyWorkshopCommandError(
          PostgrestException(message: 'x', code: code),
        ),
        WorkshopCommandOutcome.offline,
        reason: code,
      );
    }
    expect(
      classifyWorkshopCommandError(
        const PostgrestException(message: 'x', code: '42501'),
      ),
      WorkshopCommandOutcome.rejected,
    );
    // El conflicto de la ficha llega como PT409 (HTTP 409): 40001 lo
    // reintenta PostgREST 14 sin fin y sólo se ve un 504.
    expect(
      classifyWorkshopCommandError(
        const PostgrestException(
          message: 'Bicycle no longer exists; reload before saving',
          code: 'PT409',
        ),
      ),
      WorkshopCommandOutcome.stale,
    );
  });

  test('la reanudación automática espera más después de cada intento',
      () async {
    var now = DateTime.utc(2026, 9, 28, 5);
    final disk = _Disk();
    final server = _Server()..networkUp = false;
    WorkshopCommandOutbox outbox() => WorkshopCommandOutbox(
          store: disk,
          transport: server,
          clock: () => now,
          clientPlatform: 'test',
        );
    await outbox().submit(_scope, _save('op-1'));
    await outbox().flushAttempts(_scope);

    // Recién intentado: la vuelta automática no lo toca; abrir la bici sí.
    expect(await outbox().resume(_scope, respectBackoff: true), isEmpty);
    now = now.add(const Duration(minutes: 1));
    expect(
      (await outbox().resume(_scope, respectBackoff: true)).single.outcome,
      WorkshopCommandOutcome.offline,
    );
    // Segundo intento: ahora espera dos minutos.
    now = now.add(const Duration(minutes: 1));
    expect(await outbox().resume(_scope, respectBackoff: true), isEmpty);
    expect((await outbox().resume(_scope)).single.command.attempts, 3);
    expect(WorkshopCommandOutbox.backoffAfter(40), const Duration(hours: 1));
  });

  test(
      'mientras vuela no se descarta; al terminar sin red se descarta y no '
      'revive', () async {
    final server = _Server()..networkUp = false;
    final outbox = _outbox(_Disk(), server);
    await outbox.enqueue(_scope, _save('op-1'));

    Future<Object?>? duringFlight;
    server.duringSend = () {
      server.duringSend = null;
      duringFlight = outbox
          .discard(_scope, 'op-1')
          .then<Object?>((run) => run, onError: (Object error) => error);
    };
    await outbox.run(
      _scope,
      'op-1',
      trigger: WorkshopCommandTrigger.save,
    );
    // El servidor puede estar escribiéndolo con sus fotos: soltarlas las
    // dejaría al barrido (revisión de Codex del barrido, 2026-09-29).
    expect(await duringFlight, isA<WorkshopCommandBusyException>());
    await outbox.discard(_scope, 'op-1');
    await outbox.resume(_scope);

    expect(await outbox.pending(_scope), isEmpty);
  });

  test('sin la función de intentos en el servidor, quedan en el equipo',
      () async {
    final disk = _Disk();
    final server = _Server()..attemptsSinkUp = false;
    final outbox = _outbox(disk, server);

    await outbox.submit(_scope, _save('op-1'));
    await outbox.flushAttempts(_scope);
    expect((await outbox.counts(_scope)).attempts, 1);

    server.attemptsSinkUp = true;
    await _outbox(disk, server).flushAttempts(_scope);
    expect(_outcomes(server), ['save:committed']);
    expect((await outbox.counts(_scope)).attempts, 0);
  });

  test('sin respaldo en el equipo no se envía', () async {
    final disk = _Disk()..failWrites = true;
    final server = _Server();
    final outbox = _outbox(disk, server);

    await expectLater(
      outbox.submit(_scope, _save('op-1')),
      throwsA(isA<WorkshopOutboxPersistenceException>()),
    );
    expect(server.applied, 0);
  });

  test('una llave nunca cambia de contenido', () async {
    final outbox = _outbox(_Disk(), _Server()..networkUp = false);
    await outbox.submit(_scope, _save('op-1'));

    await outbox.enqueue(_scope, _save('op-1'));
    await expectLater(
      outbox.enqueue(_scope, _save('op-1', images: ['otra-foto'])),
      throwsStateError,
    );
  });

  test('otra cuenta del mismo equipo no ve ni reenvía lo pendiente', () async {
    final disk = _Disk();
    final server = _Server()..networkUp = false;
    await _outbox(disk, server).submit(_scope, _save('op-1'));

    server.networkUp = true;
    const other = WorkshopCommandScope(tenantId: 'taller', userId: 'otra');
    expect(await _outbox(disk, server).resume(other), isEmpty);
    expect(server.applied, 0);
  });

  test('dos intentos a la vez con la misma llave envían una sola vez',
      () async {
    final server = _Server()..networkUp = false;
    final outbox = _outbox(_Disk(), server);
    await outbox.submit(_scope, _save('op-1'));
    server.networkUp = true;

    final runs = await Future.wait([
      outbox.run(_scope, 'op-1', trigger: WorkshopCommandTrigger.retry),
      outbox.run(_scope, 'op-1', trigger: WorkshopCommandTrigger.retry),
    ]);

    expect(identical(runs.first, runs.last), isTrue);
    expect(server.applied, 1);
  });

  group('fotos', () {
    PendingBikeImage image(String path, {String form = 'formulario-1'}) =>
        PendingBikeImage(
          bucket: 'bike-images',
          objectPath: path,
          publicUrl: 'https://x/storage/v1/object/public/bike-images/$path',
          bikeId: _bikeId,
          createdAt: DateTime.utc(2026, 9, 27, 20),
          ownerForm: form,
        );

    Future<PendingBikeImage> upload(
      WorkshopCommandOutbox outbox,
      _Server server,
      String path, {
      String form = 'formulario-1',
    }) async {
      final pending = image(path, form: form);
      await outbox.recordImageIntent(_scope, pending);
      server.storedImages.add(path);
      await outbox.markImageUploaded(_scope, path);
      return pending;
    }

    test('la foto de una bici guardada se queda', () async {
      final server = _Server();
      final outbox = _outbox(_Disk(), server);
      final foto = await upload(outbox, server, 'taller/bici-1/a.jpg');

      await outbox.submit(_scope, _save('op-1', images: [foto.publicUrl]));
      await outbox.sweepOrphanImages(_scope);

      expect(server.storedImages, {'taller/bici-1/a.jpg'});
      expect((await outbox.counts(_scope)).images, 0);
    });

    test('rechazada al volver, nadie la reclama: se borra', () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      final before = _outbox(disk, server);
      final foto = await upload(before, server, 'taller/bici-1/a.jpg');
      server.storedImages.add(foto.objectPath);
      await before.submit(_scope, _save('op-1', images: [foto.publicUrl]));
      await before.flushAttempts(_scope);

      server
        ..networkUp = true
        ..rejectWith = const PostgrestException(message: 'no', code: '22023');
      final runs = await _outbox(disk, server).resume(_scope);

      expect(runs.single.outcome, WorkshopCommandOutcome.rejected);
      expect(server.storedImages, isEmpty);
      expect((await before.counts(_scope)).images, 0);
    });

    test('rechazada con el formulario abierto: la conserva hasta cerrarlo',
        () async {
      final server = _Server()
        ..rejectWith = const PostgrestException(
          message: 'changed since it was loaded',
          code: '40001',
        );
      final outbox = _outbox(_Disk(), server);
      final foto = await upload(outbox, server, 'taller/bici-1/a.jpg');

      final run =
          await outbox.submit(_scope, _save('op-1', images: [foto.publicUrl]));
      expect(run.outcome, WorkshopCommandOutcome.stale);
      expect(server.storedImages, {'taller/bici-1/a.jpg'},
          reason: 'el formulario la vuelve a enviar tras recargar');

      await outbox.releaseImages(_scope, ownerForm: 'formulario-1');
      expect(server.storedImages, isEmpty);
    });

    test('cerrar un formulario no borra las fotos de otro abierto', () async {
      final server = _Server();
      final outbox = _outbox(_Disk(), server);
      await upload(outbox, server, 'taller/bici-1/a.jpg', form: 'uno');
      await upload(outbox, server, 'taller/bici-1/b.jpg', form: 'dos');

      await outbox.releaseImages(_scope, ownerForm: 'uno');
      // El barrido de esta misma sesión tampoco toca la del formulario vivo.
      await outbox.sweepOrphanImages(_scope);

      expect(server.storedImages, {'taller/bici-1/b.jpg'});
    });

    group('adjuntos del trabajo', () {
      PendingBikeImage attachment(String path,
              {String form = 'trabajo-form'}) =>
          PendingBikeImage(
            bucket: 'job-images',
            objectPath: path,
            publicUrl: 'https://x/storage/v1/object/public/job-images/$path',
            jobId: 'trabajo-1',
            createdAt: DateTime.utc(2026, 9, 28, 12),
            ownerForm: form,
          );

      Future<PendingBikeImage> uploadAttachment(
        WorkshopCommandOutbox outbox,
        _Server server,
        String path,
      ) async {
        final pending = attachment(path);
        await outbox.recordImageIntent(_scope, pending);
        server.storedImages.add(path);
        await outbox.markImageUploaded(_scope, path);
        return pending;
      }

      /// El guardado del trabajo con los adjuntos en su cabecera, como lo
      /// arma el formulario o la tabla.
      PendingWorkshopCommand withAttachments(String key, List<String> urls) {
        final base = _lines(key);
        return PendingWorkshopCommand(
          operationKey: key,
          kind: base.kind,
          params: {
            ...base.params,
            'p_header': {
              'image_urls': {'value': urls, 'expected': <String>[]},
            },
          },
          createdAt: base.createdAt,
          jobId: base.jobId,
          label: base.label,
        );
      }

      test('va con el guardado del trabajo y se queda al escribirse', () async {
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        final outbox = _outbox(disk, server);
        final pdf = await uploadAttachment(
            outbox, server, 'taller/trabajo-1/presupuesto.pdf');

        await outbox.submit(
            _scope, withAttachments('lineas-1', [pdf.publicUrl]));
        // El guardado sin respuesta lo lleva: ni el barrido de otra sesión
        // ni cerrar el formulario lo borran.
        await _outbox(disk, server).resume(_scope, sweepImages: true);
        await outbox.releaseImages(_scope, ownerForm: 'trabajo-form');
        expect(server.storedImages, {'taller/trabajo-1/presupuesto.pdf'});

        server.networkUp = true;
        await _outbox(disk, server).resume(_scope);
        expect(server.storedImages, {'taller/trabajo-1/presupuesto.pdf'});
        expect((await outbox.counts(_scope)).images, 0,
            reason: 'ya es un adjunto del trabajo guardado');
      });

      test(
          'si ningún guardado lo lleva, se borra; nunca uno que un trabajo '
          'muestra', () async {
        final disk = _Disk();
        final server = _Server();
        final outbox = _outbox(disk, server);
        await uploadAttachment(outbox, server, 'taller/trabajo-1/a.jpg');
        final shown =
            await uploadAttachment(outbox, server, 'taller/trabajo-1/b.jpg');
        // b ya quedó en el trabajo: otro guardado lo escribió.
        server.referencedUrls.add(shown.publicUrl);

        await outbox.releaseImages(_scope, ownerForm: 'trabajo-form');

        expect(server.storedImages, {'taller/trabajo-1/b.jpg'});
        expect((await outbox.counts(_scope)).images, 0);
      });

      test(
          'el alta de un trabajo nuevo lleva sus adjuntos: sin red, ni el '
          'barrido ni cerrar el formulario los borran', () async {
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        final outbox = _outbox(disk, server);
        final pdf = await uploadAttachment(
            outbox, server, 'taller/trabajo-1/presupuesto.pdf');

        await outbox.submit(
            _scope, _jobCreation('trabajo-1', images: [pdf.publicUrl]),
            followUps: [_lines('lineas-1')]);
        await _outbox(disk, server).resume(_scope, sweepImages: true);
        await outbox.releaseImages(_scope, ownerForm: 'trabajo-form');
        expect(server.storedImages, {'taller/trabajo-1/presupuesto.pdf'});

        server.networkUp = true;
        await _outbox(disk, server).resume(_scope);
        expect(server.appliedLog,
            ['job_create:trabajo-1', 'job_line_save:lineas-1']);
        expect(server.storedImages, {'taller/trabajo-1/presupuesto.pdf'});
        expect((await outbox.counts(_scope)).images, 0,
            reason: 'ya es un adjunto del trabajo creado');
      });

      test('se relee del equipo como adjunto del trabajo', () async {
        final disk = _Disk();
        final server = _Server();
        await uploadAttachment(
            _outbox(disk, server), server, 'taller/trabajo-1/a.jpg');
        final entry = disk.values.entries
            .firstWhere((entry) => entry.key.contains(':i:'))
            .value;
        final decoded = jsonDecode(entry) as Map<String, dynamic>;
        expect(decoded['job_id'], 'trabajo-1');
        expect(decoded['bike_id'], isNull);
        final again = PendingBikeImage.fromJson(decoded)!;
        expect(again.jobId, 'trabajo-1');
        expect(again.bucket, 'job-images');
      });
    });

    test('subida sin enviar y la app se cerró: el barrido la borra', () async {
      final disk = _Disk();
      final server = _Server();
      await upload(_outbox(disk, server), server, 'taller/bici-1/a.jpg');
      // Una a medio subir: la intención quedó, el archivo quizá no.
      await _outbox(disk, server)
          .recordImageIntent(_scope, image('taller/bici-1/b.jpg'));

      await _outbox(disk, server).resume(_scope, sweepImages: true);

      expect(server.storedImages, isEmpty);
      expect((await _outbox(disk, server).counts(_scope)).images, 0);
    });

    test('una foto que alguna bici ya muestra nunca se borra', () async {
      final disk = _Disk();
      final server = _Server();
      final foto =
          await upload(_outbox(disk, server), server, 'taller/bici-1/a.jpg');
      server.referencedUrls.add(foto.publicUrl);

      // La próxima sesión barre: la foto está en una bici, se queda.
      final outbox = _outbox(disk, server);
      await outbox.sweepOrphanImages(_scope);

      expect(server.storedImages, {'taller/bici-1/a.jpg'});
      expect((await outbox.counts(_scope)).images, 0);
    });

    test('descartar un pendiente de otra sesión borra sus fotos sin dueño',
        () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      final before = _outbox(disk, server);
      final foto = await upload(before, server, 'taller/bici-1/a.jpg');
      await before.submit(_scope, _save('op-1', images: [foto.publicUrl]));
      await before.flushAttempts(_scope);

      server.networkUp = true;
      final outbox = _outbox(disk, server);
      final run = await outbox.discard(_scope, 'op-1');
      await outbox.flushAttempts(_scope);

      expect(run?.outcome, WorkshopCommandOutcome.discarded);
      expect(server.storedImages, isEmpty);
      expect(_outcomes(server), ['save:offline', 'discard:discarded']);
    });
  });

  test('el aviso dice qué pasó con lo pendiente, sin repetir el sin red', () {
    WorkshopCommandRun run(WorkshopCommandOutcome outcome) =>
        WorkshopCommandRun(
          command: _save('op-1'),
          outcome: outcome,
          trigger: WorkshopCommandTrigger.resume,
        );

    expect(
      workshopCommandNotice(run(WorkshopCommandOutcome.committed)),
      'Trek Marlin 5: se guardó el cambio que había quedado pendiente.',
    );
    expect(
      workshopCommandNotice(run(WorkshopCommandOutcome.stale)),
      contains('la bici cambió mientras tanto'),
    );
    expect(workshopCommandNotice(run(WorkshopCommandOutcome.offline)), isNull);
    expect(
      workshopCommandNotice(
        run(WorkshopCommandOutcome.offline),
        includeOffline: true,
      ),
      contains('se reintenta solo'),
    );
  });

  test('dos pestañas que respaldan a la vez no se borran lo de la otra',
      () async {
    final disk = _Disk();
    final server = _Server()..networkUp = false;
    // Dos instancias sobre el mismo almacenamiento, como dos pestañas web.
    final tabA = _outbox(disk, server);
    final tabB = _outbox(disk, server);

    await Future.wait([
      tabA.submit(_scope, _save('op-a')),
      tabB.submit(_scope, _save('op-b')),
    ]);
    await Future.wait([tabA.flushAttempts(_scope), tabB.flushAttempts(_scope)]);

    expect(
      (await _outbox(disk, server).pending(_scope))
          .map((command) => command.operationKey)
          .toSet(),
      {'op-a', 'op-b'},
    );
  });

  test('con otra cuenta adentro no se envía ni se entrega nada', () async {
    final disk = _Disk();
    final server = _Server()..networkUp = false;
    final before = _outbox(disk, server);
    await before.submit(_scope, _save('op-1'));
    await before.flushAttempts(_scope);
    server
      ..networkUp = true
      ..currentUser = 'otra-persona'
      ..recordedAttempts.clear()
      ..sentKeys.clear();

    final outbox = _outbox(disk, server);
    expect(await outbox.resume(_scope), isEmpty);
    await outbox.flushAttempts(_scope);

    expect(server.sentKeys, isEmpty);
    expect(server.recordedAttempts, isEmpty);
    expect((await outbox.pending(_scope)).single.operationKey, 'op-1');
  });

  test(
      'la misma cuenta en otro taller: lo de éste ni se envía ni se descarta, '
      'y sigue al volver', () async {
    final disk = _Disk();
    final server = _Server()..networkUp = false;
    await _outbox(disk, server).submit(_scope, _lines('lineas-1'));

    // Con la sesión ya en otro taller, la reanudación no envía nada.
    server
      ..networkUp = true
      ..currentTenant = 'otro-taller'
      ..sentKeys.clear();
    expect(await _outbox(disk, server).resume(_scope), isEmpty);
    expect(server.sentKeys, isEmpty);

    // El taller cambia justo mientras vuela: el rechazo que llega (el
    // servidor lo busca en el otro taller) no retira el pendiente.
    server
      ..currentTenant = 'taller'
      ..rejectWith = const PostgrestException(
        message: 'Trabajo no encontrado o eliminado.',
        code: 'P0002',
      )
      ..duringSend = () => server.currentTenant = 'otro-taller';
    final raced = await _outbox(disk, server)
        .run(_scope, 'lineas-1', trigger: WorkshopCommandTrigger.retry);
    expect(raced.outcome, WorkshopCommandOutcome.offline);
    expect(raced.error, isA<WorkshopScopeChangedException>());
    expect((await _outbox(disk, server).pending(_scope)).single.operationKey,
        'lineas-1');

    // De vuelta en su taller, se escribe una vez.
    server
      ..currentTenant = 'taller'
      ..rejectWith = null
      ..duringSend = null;
    final resumed = await _outbox(disk, server).resume(_scope);
    expect(resumed.single.outcome, WorkshopCommandOutcome.committed);
    expect(server.applied, 1);
  });

  test('una bici es una cola: lo siguiente espera al comando sin respuesta',
      () async {
    final server = _Server()..networkUp = false;
    final outbox = _outbox(_Disk(), server);
    await outbox.submit(_scope, _save('op-1'));
    await outbox.enqueue(
      _scope,
      _save('op-2', createdAt: DateTime.utc(2026, 9, 27, 21)),
    );
    server.sentKeys.clear();

    final runs = await outbox.resume(_scope);

    expect(server.sentKeys, ['op-1']);
    expect(runs.single.outcome, WorkshopCommandOutcome.offline);
    expect((await outbox.pending(_scope)).length, 2);
  });

  test('un envío que murió a mitad queda anotado como interrumpido', () async {
    final disk = _Disk();
    final server = _Server();
    await _outbox(disk, server).enqueue(_scope, _save('op-1'));
    // La app contó el intento y murió antes de la respuesta: quedó en vuelo.
    final key = disk.values.keys.singleWhere((key) => key.contains(':c:'));
    final json = jsonDecode(disk.values[key]!) as Map<String, dynamic>;
    disk.values[key] = jsonEncode({
      ...json,
      'attempts': 1,
      'in_flight': true,
      'last_trigger': 'save',
      'last_attempt_at': '2026-09-28T05:00:00.000Z',
    });

    final restarted = _outbox(disk, server);
    final runs = await restarted.resume(_scope);
    await restarted.flushAttempts(_scope);

    expect(runs.single.outcome, WorkshopCommandOutcome.committed);
    expect(_outcomes(server), ['save:offline', 'resume:committed']);
    expect(server.recordedAttempts.first['error_code'], 'interrupted');
    expect(server.recordedAttempts.last['attempt_number'], 2);
  });

  test('el respaldo del equipo usa SharedPreferences y lo relee', () async {
    SharedPreferences.setMockInitialValues({});
    final server = _Server()..networkUp = false;
    final before = _outbox(SharedPreferencesWorkshopOutboxStore(), server);
    await before.submit(_scope, _save('op-1'));
    await before.flushAttempts(_scope);

    final restarted = _outbox(
        SharedPreferencesWorkshopOutboxStore(), server..networkUp = true);
    final runs = await restarted.resume(_scope);

    expect(runs.single.outcome, WorkshopCommandOutcome.committed);
    expect(await restarted.pending(_scope), isEmpty);
  });
  group('revisión del 2026-09-28', () {
    test('un pendiente ilegible se conserva y bloquea su bici', () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      final outbox = _outbox(disk, server);
      final unreadable = '${_scope.storageKey}:c:op-nuevo-formato';
      // Lo dejó otra versión de la app: se lee la bici, no el comando.
      disk.values[unreadable] = jsonEncode({'bike_id': _bikeId, 'formato': 99});

      await outbox.submit(_scope, _save('op-1'));
      await outbox.discard(_scope, 'op-1');

      expect(disk.values.containsKey(unreadable), isTrue);
      expect(await outbox.hasUnreadableFor(_scope, _bikeId), isTrue);
      expect(await outbox.hasUnreadableFor(_scope, 'otra-bici'), isFalse);
    });

    test(
        'un pendiente ilegible de un trabajo también lo detiene: el guardado '
        'nuevo espera en la bandeja', () async {
      final disk = _Disk();
      final server = _Server();
      final outbox = _outbox(disk, server);
      // Otra versión dejó un guardado de líneas de este trabajo; se lee el
      // trabajo, no el comando.
      disk.values['${_scope.storageKey}:c:op-lineas-futuras'] = jsonEncode({
        'kind': 'job_line_save_v2',
        'job_id': 'trabajo-1',
        'params': {'p_job_id': 'trabajo-1'},
      });

      final run = await outbox.submit(_scope, _lines('lineas-2'));
      expect(run.outcome, WorkshopCommandOutcome.offline);
      expect(run.error, isA<WorkshopCommandQueuedException>());
      expect(server.applied, 0);
      expect((await outbox.pending(_scope)).single.operationKey, 'lineas-2');

      expect(await outbox.resume(_scope, jobId: 'trabajo-1'), isEmpty,
          reason: 'la reanudación tampoco lo pasa por encima');
      final direct = await outbox.run(
        _scope,
        'lineas-2',
        trigger: WorkshopCommandTrigger.save,
      );
      expect(direct.error, isA<WorkshopCommandQueuedException>(),
          reason: 'ni resolverlo por su llave al guardar otra vez');
      expect(server.applied, 0);

      // Otro trabajo no espera.
      final other =
          await outbox.submit(_scope, _lines('lineas-3', jobId: 'trabajo-2'));
      expect(other.outcome, WorkshopCommandOutcome.committed);
    });

    test('una respuesta sin recibo completo no saca el comando', () async {
      final server = _Server()
        ..malformedAck = {'ok': true}
        ..probeUp = false;
      final outbox = _outbox(_Disk(), server);

      final run = await outbox.submit(_scope, _save('op-1'));

      expect(run.outcome, WorkshopCommandOutcome.offline);
      expect(run.error, isA<FormatException>());
      expect((await outbox.pending(_scope)).single.operationKey, 'op-1');

      // Con el recibo a la vista, el mismo comando se resuelve.
      server
        ..malformedAck = null
        ..probeUp = true;
      final resumed = await outbox.resume(_scope);
      expect(resumed.single.outcome, WorkshopCommandOutcome.committed);
      expect(await outbox.pending(_scope), isEmpty);
    });

    test(
        'un guardado que pidió su factura no sale de la bandeja sin saber qué '
        'pasó con ella', () async {
      final server = _Server()..probeUp = false;
      final outbox = _outbox(_Disk(), server);
      final base = _lines('lineas-factura');
      final command = PendingWorkshopCommand(
        operationKey: base.operationKey,
        kind: base.kind,
        params: {...base.params, 'p_invoice': true},
        createdAt: base.createdAt,
        jobId: base.jobId,
        label: base.label,
      );

      final run = await outbox.submit(_scope, command);
      expect(run.error, isA<FormatException>());
      expect(
          (await outbox.pending(_scope)).single.operationKey, 'lineas-factura');

      // Con el recibo completo, el mismo comando se resuelve.
      server
        ..invoiceResult = {'action': 'created', 'invoice_id': 'fv-1'}
        ..probeUp = true
        ..receipts['lineas-factura'] = {
          ...server.receipts['lineas-factura']!,
          'invoice': {'action': 'created', 'invoice_id': 'fv-1'},
        };
      final resumed = await outbox.resume(_scope, jobId: 'trabajo-1');
      expect(resumed.single.outcome, WorkshopCommandOutcome.reconciled);
      expect(await outbox.pending(_scope), isEmpty);
      expect(server.applied, 1, reason: 'sin escribir dos veces');
    });

    test('un rechazo con otra cuenta adentro no borra el pendiente', () async {
      final server = _Server()
        ..rejectWith = const PostgrestException(
          message: 'permission denied',
          code: '42501',
        );
      // La cuenta cambia mientras la llamada va en camino.
      server.duringSend = () => server.currentUser = 'otra-persona';
      final outbox = _outbox(_Disk(), server);

      final run = await outbox.submit(_scope, _save('op-1'));

      expect(run.outcome, WorkshopCommandOutcome.offline);
      expect(run.error, isA<WorkshopScopeChangedException>());
      expect((await outbox.pending(_scope)).single.operationKey, 'op-1');
    });

    test('un guardado nuevo espera a lo anterior de su bici', () async {
      final server = _Server()..networkUp = false;
      final outbox = _outbox(_Disk(), server);
      await outbox.submit(
          _scope, _save('op-1', createdAt: DateTime.utc(2026, 9, 28, 10)));
      server.sentKeys.clear();

      // Sigue sin red: op-2 queda en la bandeja sin enviarse.
      final queued = await outbox.submit(
          _scope, _save('op-2', createdAt: DateTime.utc(2026, 9, 28, 11)));
      expect(queued.outcome, WorkshopCommandOutcome.offline);
      expect(queued.error, isA<WorkshopCommandQueuedException>());
      expect(server.sentKeys, ['op-1']);

      // Con red, el siguiente guardado envía todo en el orden en que se hizo.
      server
        ..networkUp = true
        ..sentKeys.clear();
      final run = await outbox.submit(
          _scope, _save('op-3', createdAt: DateTime.utc(2026, 9, 28, 12)));
      expect(run.outcome, WorkshopCommandOutcome.committed);
      expect(server.sentKeys, ['op-1', 'op-2', 'op-3']);
      expect(await outbox.pending(_scope), isEmpty);
    });

    group('pestañas web', () {
      PendingBikeImage image(String path) => PendingBikeImage(
            bucket: 'bike-images',
            objectPath: path,
            publicUrl: 'https://x/storage/v1/object/public/bike-images/$path',
            bikeId: _bikeId,
            createdAt: DateTime.utc(2026, 9, 28, 10),
            ownerForm: 'formulario-1',
          );

      test('la foto de otra pestaña viva no se barre; la de una muerta sí',
          () async {
        var now = DateTime.utc(2026, 9, 28, 10);
        final disk = _Disk();
        final server = _Server();
        final tabA = _outbox(disk, server, concurrent: true, clock: () => now);
        final tabB = _outbox(disk, server, concurrent: true, clock: () => now);
        await tabA.recordImageIntent(_scope, image('taller/bici-1/a.jpg'));
        server.storedImages.add('taller/bici-1/a.jpg');
        await tabA.markImageUploaded(_scope, 'taller/bici-1/a.jpg');

        now = now.add(const Duration(minutes: 10));
        await tabB.sweepOrphanImages(_scope);
        expect(server.storedImages, {'taller/bici-1/a.jpg'});

        // La pestaña A se cerró: sin latido, su foto no la reclama nadie.
        now = now.add(WorkshopCommandOutbox.sessionTimeout);
        await tabB.sweepOrphanImages(_scope);
        expect(server.storedImages, isEmpty);
      });

      test('lo que envía otra pestaña viva no se reenvía ni es interrumpido',
          () async {
        var now = DateTime.utc(2026, 9, 28, 10);
        final disk = _Disk();
        final server = _Server();
        final tabA = _outbox(disk, server, concurrent: true, clock: () => now);
        final tabB = _outbox(disk, server, concurrent: true, clock: () => now);
        // A late (reanudar otra bici) y cuenta el intento; la llamada queda
        // en camino.
        await tabA.enqueue(_scope, _save('op-1'));
        await tabA.resume(_scope, bikeId: 'otra-bici');
        final key = disk.values.keys.singleWhere((k) => k.contains(':c:'));
        final json = jsonDecode(disk.values[key]!) as Map<String, dynamic>;
        disk.values[key] = jsonEncode({
          ...json,
          'attempts': 1,
          'in_flight': true,
          'in_flight_session': tabA.sessionId,
          'last_trigger': 'save',
          'last_attempt_at': now.toIso8601String(),
        });
        now = now.add(const Duration(seconds: 20));
        final runs = await tabB.resume(_scope);
        await tabB.flushAttempts(_scope);

        expect(runs.single.error, isA<WorkshopCommandBusyException>());
        expect(server.sentKeys, isEmpty);
        expect(server.recordedAttempts, isEmpty);

        // Pasado el plazo de un envío, sí era una llamada que murió.
        now = now.add(WorkshopCommandOutbox.sendTimeout);
        final later = await tabB.resume(_scope);
        await tabB.flushAttempts(_scope);
        expect(later.single.outcome, WorkshopCommandOutcome.committed);
        expect(server.recordedAttempts.first['error_code'], 'interrupted');
      });

      test('una foto reclamada mientras se consultaba no se borra', () async {
        var now = DateTime.utc(2026, 9, 28, 10);
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        final tabA = _outbox(disk, server, concurrent: true, clock: () => now);
        final tabB = _outbox(disk, server, concurrent: true, clock: () => now);
        final foto = image('taller/bici-1/a.jpg');
        await tabA.recordImageIntent(_scope, foto);
        server.storedImages.add(foto.objectPath);
        await tabA.markImageUploaded(_scope, foto.objectPath);

        // A durmió más que el plazo; B la da por huérfana, pero A despierta
        // y guarda la bici con esa foto mientras B consulta las bicis.
        now = now.add(WorkshopCommandOutbox.sessionTimeout * 2);
        server.duringReferenceCheck = () async {
          server.duringReferenceCheck = null;
          await tabA.submit(_scope, _save('op-1', images: [foto.publicUrl]));
        };
        await tabB.sweepOrphanImages(_scope);

        expect(server.storedImages, {foto.objectPath});
        final counts = await tabB.counts(_scope);
        expect(counts.images, 1);
        expect((await tabB.pending(_scope)).single.imageUrls, [foto.publicUrl]);
      });
    });

    test('el alta lee la bandeja al guardar, no lo que leyó al abrir',
        () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      final formTab = _outbox(disk, server, concurrent: true);
      final otherTab = _outbox(disk, server, concurrent: true);
      PendingWorkshopCommand creation(String key, String customer) =>
          PendingWorkshopCommand(
            operationKey: key,
            kind: WorkshopCommandKind.bikeAggregateSave,
            params: {
              'p_operation_key': key,
              'p_bike_id': 'bici-$key',
              'p_customer_id': customer,
              'p_expected_bike_updated_at': null,
              'p_bike_payload': const {'brand': 'Trek'},
            },
            createdAt: DateTime.utc(2026, 9, 28, 10),
            bikeId: 'bici-$key',
            label: 'Trek Marlin 5',
          );

      // Al abrir el formulario no había nada pendiente.
      expect((await formTab.pendingCreationsFor(_scope, 'cliente-1')).creations,
          isEmpty);
      // Otra pestaña deja un alta sin respuesta de ese cliente, y otra de
      // otro cliente.
      await otherTab.submit(_scope, creation('op-a', 'cliente-1'));
      await otherTab.submit(_scope, creation('op-b', 'cliente-2'));

      final atSave = await formTab.pendingCreationsFor(_scope, 'cliente-1');
      expect(atSave.creations.map((c) => c.operationKey), ['op-a']);
      expect(atSave.unreadable, isFalse);

      // Un alta que esta versión no sabe leer, de ese cliente, también frena.
      disk.values['${_scope.storageKey}:c:op-futura'] = jsonEncode({
        'formato': 99,
        'params': {'p_customer_id': 'cliente-3'},
      });
      expect(
          (await formTab.pendingCreationsFor(_scope, 'cliente-3')).unreadable,
          isTrue);
      expect(
          (await formTab.pendingCreationsFor(_scope, 'cliente-2')).unreadable,
          isFalse);

      // Sin poder leer la bandeja no hay respuesta que permita crear.
      disk.failReads = true;
      await expectLater(
        formTab.pendingCreationsFor(_scope, 'cliente-1'),
        throwsA(isA<WorkshopOutboxPersistenceException>()),
      );
    });

    test('el alta se vuelve a comprobar al respaldarla, no sólo al decidir',
        () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      final formTab = _outbox(disk, server, concurrent: true);
      final otherTab = _outbox(disk, server, concurrent: true);
      PendingWorkshopCommand creation(String key) => PendingWorkshopCommand(
            operationKey: key,
            kind: WorkshopCommandKind.bikeAggregateSave,
            params: {
              'p_operation_key': key,
              'p_bike_id': 'bici-$key',
              'p_customer_id': 'cliente-1',
              'p_expected_bike_updated_at': null,
              'p_bike_payload': const {'brand': 'Trek'},
            },
            createdAt: DateTime.utc(2026, 9, 28, 10),
            bikeId: 'bici-$key',
            label: 'Trek $key',
          );
      const nothingSeen = WorkshopCreationGuard(
        customerId: 'cliente-1',
        acknowledgedBikeIds: {},
      );

      // El formulario decidió con la bandeja vacía; mientras subían las
      // fotos, otra pestaña dejó un alta de ese cliente.
      await otherTab.submit(_scope, creation('op-a'));
      server.sentKeys.clear();
      await expectLater(
        formTab.submit(_scope, creation('op-b'), creationGuard: nothingSeen),
        throwsA(isA<WorkshopPendingCreationException>()),
      );
      expect(server.sentKeys, isEmpty, reason: 'no se envió nada');
      expect(
          (await formTab.pending(_scope)).map((c) => c.operationKey), ['op-a']);

      // Vista y decidida «es otra», se respalda y se envía.
      final run = await formTab.submit(
        _scope,
        creation('op-b'),
        creationGuard: const WorkshopCreationGuard(
          customerId: 'cliente-1',
          acknowledgedBikeIds: {'bici-op-a'},
        ),
      );
      expect(run.error, isNot(isA<WorkshopPendingCreationException>()));
      expect((await formTab.pending(_scope)).length, 2);

      // Reenviar su propia llave no vuelve a preguntar.
      await formTab.submit(_scope, creation('op-b'),
          creationGuard: nothingSeen);
    });

    group('dos pestañas que crean a la vez', () {
      const nothingSeen = WorkshopCreationGuard(
        customerId: 'cliente-1',
        acknowledgedBikeIds: {},
      );

      Future<List<Object>> createBoth(
        WorkshopCommandOutbox tabA,
        WorkshopCommandOutbox tabB,
      ) =>
          Future.wait([
            tabA
                .submit(_scope, _creation('op-a'), creationGuard: nothingSeen)
                .then<Object>((run) => run, onError: (Object error) => error),
            tabB
                .submit(_scope, _creation('op-b'), creationGuard: nothingSeen)
                .then<Object>((run) => run, onError: (Object error) => error),
          ]);

      test('con un lock por pestaña se respaldaban las dos (lo que había)',
          () async {
        final disk = _Disk()..yieldOnIo = true;
        final server = _Server()..networkUp = false;
        final results = await createBoth(
          _outbox(disk, server, concurrent: true, lock: _InstanceLock()),
          _outbox(disk, server, concurrent: true, lock: _InstanceLock()),
        );

        expect(results.whereType<WorkshopPendingCreationException>(), isEmpty);
        expect(
          (await _outbox(disk, server).pendingCreationsFor(_scope, 'cliente-1'))
              .creations,
          hasLength(2),
          reason: 'las dos leyeron la bandeja vacía: dos bicis con otro id',
        );
      });

      test('con el lock compartido, sólo una; la otra tiene que decidir',
          () async {
        final disk = _Disk()..yieldOnIo = true;
        final server = _Server()..networkUp = false;
        final results = await createBoth(
          _outbox(disk, server, concurrent: true),
          _outbox(disk, server, concurrent: true),
        );

        expect(
          results.whereType<WorkshopPendingCreationException>(),
          hasLength(1),
        );
        expect(
          (await _outbox(disk, server).pendingCreationsFor(_scope, 'cliente-1'))
              .creations,
          hasLength(1),
        );
      });
    });

    test('el aviso distingue la espera en cola y la otra pestaña', () {
      WorkshopCommandRun run(Object error) => WorkshopCommandRun(
            command: _save('op-1'),
            outcome: WorkshopCommandOutcome.offline,
            trigger: WorkshopCommandTrigger.save,
            error: error,
          );
      expect(
        workshopCommandNotice(run(const WorkshopCommandQueuedException()),
            includeOffline: true),
        contains('detrás de uno anterior'),
      );
      expect(
        workshopCommandNotice(run(const WorkshopCommandBusyException()),
            includeOffline: true),
        contains('otra pestaña'),
      );
    });
  });

  group('líneas del trabajo y ficha (ítem 4)', () {
    test('el comando completo y su llave están en el disco antes de salir',
        () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      final command = _lines('lineas-1', factBike: _bikeId);
      Map<String, dynamic>? onDiskWhileSending;
      server.duringSend = () {
        final entry = disk.values['${_scope.storageKey}:c:lineas-1'];
        onDiskWhileSending =
            entry == null ? null : jsonDecode(entry) as Map<String, dynamic>;
      };

      final run = await _outbox(disk, server).submit(_scope, command);

      expect(onDiskWhileSending?['kind'], 'job_line_save');
      expect(onDiskWhileSending?['job_id'], 'trabajo-1');
      expect(
        jsonEncode(onDiskWhileSending?['params']),
        jsonEncode(command.params),
        reason: 'lo que se reenvía es exactamente lo que se envió',
      );
      expect(run.outcome, WorkshopCommandOutcome.offline);
      expect(disk.values.keys, contains('${_scope.storageKey}:c:lineas-1'));
    });

    test('sin red y la app se cierra: al volver se guardan una sola vez',
        () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      await _outbox(disk, server).submit(_scope, _lines('lineas-1'));

      server.networkUp = true;
      final after = _outbox(disk, server);
      final resumed = await after.resume(_scope, jobId: 'trabajo-1');

      expect(resumed.single.outcome, WorkshopCommandOutcome.committed);
      // La sesión nueva envía el comando entero que se respaldó: lo que la
      // base hace al aplicarlo —las tareas de la línea nueva incluidas— no
      // depende del formulario que se cerró (antes las creaba él, después
      // de la respuesta).
      final resent = server.receipts['lineas-1']!['params'] as Map;
      expect(resent, _lines('lineas-1').params);
      expect(resumed.single.response?['operation_id'], 'op-1');
      expect(server.applied, 1);
      expect(await after.pending(_scope), isEmpty);
      await after.flushAttempts(_scope);
      expect(_outcomes(server), ['save:offline', 'resume:committed']);
      expect(
        server.recordedAttempts.map((a) => a['command_kind']).toSet(),
        {'job_line_save'},
      );
      expect(server.recordedAttempts.last['job_id'], 'trabajo-1');
    });

    test('escrito y la respuesta perdida: el recibo lo cierra sin reescribir',
        () async {
      final disk = _Disk();
      final server = _Server()
        ..loseNextAck = true
        ..probeUp = false;
      final first = await _outbox(disk, server)
          .submit(_scope, _lines('lineas-1', factBike: _bikeId));
      expect(first.outcome, WorkshopCommandOutcome.offline);
      expect(server.applied, 1, reason: 'el servidor alcanzó a escribir');

      // Otra sesión de la app, con red: pregunta por la llave y no reenvía.
      server
        ..probeUp = true
        ..sentKeys.clear();
      final after = _outbox(disk, server);
      final resumed = await after.resume(_scope);

      expect(resumed.single.outcome, WorkshopCommandOutcome.reconciled);
      expect(resumed.single.response?['operation_id'], 'op-1');
      expect(server.applied, 1, reason: 'líneas y ficha escritas una vez');
      expect(await after.pending(_scope), isEmpty);
    });

    test('otra cuenta u otro taller en el mismo equipo no lo ven ni envían',
        () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      await _outbox(disk, server).submit(_scope, _lines('lineas-1'));
      server
        ..networkUp = true
        ..sentKeys.clear();

      for (final other in const [
        WorkshopCommandScope(tenantId: 'taller', userId: 'otra'),
        WorkshopCommandScope(tenantId: 'otro-taller', userId: 'mecanico'),
      ]) {
        server.currentUser = other.userId;
        final outbox = _outbox(disk, server);
        expect(await outbox.pending(other), isEmpty);
        expect(await outbox.resume(other, jobId: 'trabajo-1'), isEmpty);
      }
      expect(server.sentKeys, isEmpty);

      server.currentUser = 'mecanico';
      expect(
        (await _outbox(disk, server).resume(_scope)).single.outcome,
        WorkshopCommandOutcome.committed,
        reason: 'su dueño sí lo envía al volver',
      );
    });

    test('un trabajo es una cola: el segundo guardado espera al primero',
        () async {
      final server = _Server()..networkUp = false;
      final outbox = _outbox(_Disk(), server);
      await outbox.submit(_scope, _lines('lineas-1'));
      server.sentKeys.clear();

      final queued = await outbox.submit(
        _scope,
        _lines('lineas-2', createdAt: DateTime.utc(2026, 9, 28, 11)),
      );
      expect(queued.outcome, WorkshopCommandOutcome.offline);
      expect(queued.error, isA<WorkshopCommandQueuedException>());
      expect(server.sentKeys, ['lineas-1']);

      // Resolver el segundo por su llave (lo que hace el formulario al
      // guardar otra vez) tampoco se salta al primero.
      server
        ..networkUp = true
        ..sentKeys.clear();
      final direct = await outbox.run(
        _scope,
        'lineas-2',
        trigger: WorkshopCommandTrigger.save,
      );
      expect(direct.error, isA<WorkshopCommandQueuedException>());
      expect(server.sentKeys, isEmpty);
      server.networkUp = false;

      // Otro trabajo no espera.
      server.sentKeys.clear();
      await outbox.submit(
        _scope,
        _lines('otro-1',
            jobId: 'trabajo-2', createdAt: DateTime.utc(2026, 9, 28, 12)),
      );
      expect(server.sentKeys, ['otro-1']);
    });

    test('dos guardados del mismo milisegundo también hacen cola', () async {
      final server = _Server()..networkUp = false;
      final outbox = _outbox(_Disk(), server);
      final at = DateTime.utc(2026, 9, 28, 11);
      await outbox.submit(_scope, _lines('lineas-b', createdAt: at));
      await outbox.submit(_scope, _lines('lineas-a', createdAt: at));

      server
        ..networkUp = true
        ..sentKeys.clear();
      // A igual hora va primero la llave menor, en todas las puertas.
      final direct = await outbox.run(
        _scope,
        'lineas-b',
        trigger: WorkshopCommandTrigger.save,
      );
      expect(direct.error, isA<WorkshopCommandQueuedException>());
      expect(server.sentKeys, isEmpty);
      await outbox.resume(_scope, jobId: 'trabajo-1');
      expect(server.sentKeys, ['lineas-a', 'lineas-b'],
          reason: 'la reanudación sigue el mismo orden y no se traba');
    });

    test('lo de «Configurar» espera al guardado sin respuesta de esa bici',
        () async {
      final server = _Server()..networkUp = false;
      final outbox = _outbox(_Disk(), server);
      await outbox.submit(
          _scope, _save('bici-1', createdAt: DateTime.utc(2026, 9, 28, 9)));

      server
        ..networkUp = true
        ..sentKeys.clear();
      // Al abrir el trabajo, lo anterior de la bici que toca va primero.
      await outbox.enqueue(_scope, _lines('lineas-1', factBike: _bikeId));
      final runs = await outbox.resume(_scope, jobId: 'trabajo-1');

      expect(server.sentKeys, ['bici-1', 'lineas-1']);
      expect(runs.map((run) => run.outcome), [
        WorkshopCommandOutcome.committed,
        WorkshopCommandOutcome.committed,
      ]);
    });

    test('un bloqueo que no se alcanzó a tomar no es un rechazo', () {
      expect(
        classifyWorkshopCommandError(
          const PostgrestException(message: 'lock', code: '55P03'),
        ),
        WorkshopCommandOutcome.offline,
      );
      expect(
        classifyWorkshopCommandError(const PostgrestException(
          message: 'Job lines changed since they were loaded',
          code: 'PT409',
          hint: 'job_lines_changed',
        )),
        WorkshopCommandOutcome.stale,
      );
    });

    test('el aviso nombra el trabajo y las líneas', () {
      WorkshopCommandRun run(WorkshopCommandOutcome outcome) =>
          WorkshopCommandRun(
            command: _lines('lineas-1'),
            outcome: outcome,
            trigger: WorkshopCommandTrigger.resume,
          );
      expect(
        workshopCommandNotice(run(WorkshopCommandOutcome.committed)),
        'Trabajo PG-00360: se guardaron las líneas que habían quedado '
        'pendientes.',
      );
      expect(
        workshopCommandNotice(run(WorkshopCommandOutcome.stale)),
        contains('el trabajo o la ficha de la bici cambió'),
      );
      expect(
        workshopCommandNotice(run(WorkshopCommandOutcome.offline),
            includeOffline: true),
        contains('Las líneas quedaron guardadas en este equipo'),
      );
    });

    test('tras un reinicio, el aviso dice si la factura no se pudo', () {
      final notice = workshopCommandNotice(WorkshopCommandRun(
        command: _lines('lineas-1'),
        outcome: WorkshopCommandOutcome.committed,
        trigger: WorkshopCommandTrigger.resume,
        response: const {
          'operation_id': 'op-1',
          'replayed': false,
          'invoice': {
            'action': 'failed',
            'invoice_id': null,
            'error': {
              'code': '23514',
              'message': 'Confirma si se recibió una bicicleta',
            },
          },
        },
      ));
      expect(notice, contains('se guardaron las líneas'));
      expect(notice, contains('Su factura no se pudo hacer'));
      expect(notice, contains('Confirma si se recibió una bicicleta'));
      expect(notice, contains('se vuelve a intentar sola'));

      // Confirmada: el comando ya rechazó lo que cambiaría lo que se cobra,
      // así que lo que llegó no la necesitaba y no hay nada que decir.
      final posted = workshopCommandNotice(WorkshopCommandRun(
        command: _lines('lineas-1'),
        outcome: WorkshopCommandOutcome.committed,
        trigger: WorkshopCommandTrigger.resume,
        response: const {
          'operation_id': 'op-2',
          'replayed': false,
          'invoice': {'action': 'posted', 'invoice_id': 'fv-9', 'error': null},
        },
      ));
      expect(posted, isNot(contains('factura')));
    });

    group('el cambio de estado (cierre)', () {
      PendingWorkshopCommand status(String key, {DateTime? createdAt}) =>
          PendingWorkshopCommand(
            operationKey: key,
            kind: WorkshopCommandKind.jobStatusTransition,
            params: {
              'p_job_id': 'trabajo-1',
              'p_status_id': 'estado-terminado',
              'p_operation_key': key,
            },
            createdAt: createdAt ?? DateTime.utc(2026, 9, 28, 10, 1),
            jobId: 'trabajo-1',
            label: 'Trabajo PG-00360',
          );

      test(
          'va en la cola del trabajo: espera al guardado sin respuesta y, tras '
          'un reinicio, se aplica después de él', () async {
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        final outbox = _outbox(disk, server);
        await outbox.submit(_scope, _lines('lineas-1'));
        server.sentKeys.clear();

        // El guardado del trabajo sigue sin respuesta: el estado no se
        // adelanta, queda detrás de él en la bandeja.
        final queued = await outbox.submit(_scope, status('estado-1'));
        expect(queued.outcome, WorkshopCommandOutcome.offline);
        expect(queued.error, isA<WorkshopCommandQueuedException>());
        expect(server.sentKeys, ['lineas-1'],
            reason: 'reintenta el guardado anterior y no envía el estado');
        expect(
          workshopCommandNotice(queued, includeOffline: true),
          contains('detrás de otro cambio del mismo trabajo que sigue sin '
              'respuesta'),
        );

        // Se cierra la app. Al volver, con red: primero el guardado, después
        // el estado, cada uno una vez.
        server
          ..networkUp = true
          ..sentKeys.clear();
        final resumed = await _outbox(disk, server).resume(_scope);
        expect(server.sentKeys, ['lineas-1', 'estado-1']);
        expect(resumed.map((run) => run.outcome), [
          WorkshopCommandOutcome.committed,
          WorkshopCommandOutcome.committed,
        ]);
        expect(server.applied, 2);
        expect(await _outbox(disk, server).pending(_scope), isEmpty);
        expect(
          workshopCommandNotice(resumed.last),
          'Trabajo PG-00360: se aplicó el cambio de estado que había quedado '
          'pendiente.',
        );
      });

      test(
          'respuesta perdida: el comprobante lo cierra sin aplicarlo dos veces',
          () async {
        final disk = _Disk();
        final server = _Server()..loseNextAck = true;
        final first = await _outbox(disk, server).submit(_scope, status('e-1'));
        expect(first.outcome, WorkshopCommandOutcome.reconciled);
        expect(server.applied, 1);
        expect(await _outbox(disk, server).pending(_scope), isEmpty);
      });

      test('un comprobante de otro cambio no lo retira', () async {
        final disk = _Disk();
        final server = _Server()..probeUp = false;
        server.receipts['e-1'] = {
          'id': 'evento-x',
          'job_id': 'trabajo-1',
          'to_status_id': 'otro-estado',
          'operation_key': 'e-1',
        };
        final run = await _outbox(disk, server).submit(_scope, status('e-1'));
        expect(run.outcome, WorkshopCommandOutcome.offline);
        expect(run.error, isA<FormatException>());
        expect((await _outbox(disk, server).pending(_scope)).single.kind,
            WorkshopCommandKind.jobStatusTransition);
      });

      test('al terminar dice lo que la ficha no tomó', () async {
        final server = _Server()
          ..statusInstalledFacts = {
            'applied': [],
            'problems': [
              {
                'item_name': 'Enrayado',
                'key': 'rearSpokeHoles',
                'value': 28,
                'reason': 'bike_locked',
              },
            ],
          };
        final disk = _Disk();
        await _outbox(disk, server).enqueue(_scope, status('e-1'));
        final resumed = await _outbox(disk, server).resume(_scope);
        final notice = workshopCommandNotice(resumed.single);
        expect(notice, startsWith('Trabajo PG-00360: se aplicó el cambio'));
        expect(notice, contains('«Enrayado»'),
            reason: 'lo que la ficha no tomó se dice como con la pantalla '
                'abierta');
      });
    });

    group('la factura que no se pudo (continuación)', () {
      test(
          'queda en el disco al retirar el guardado, y tras un reinicio se '
          'hace sin otro Guardar', () async {
        final disk = _Disk();
        final server = _Server()..invoiceResult = _invoiceFailed;
        final saved = await _outbox(disk, server)
            .submit(_scope, _billedLines('lineas-f'));

        expect(saved.outcome, WorkshopCommandOutcome.committed);
        final pending = await _outbox(disk, server).pending(_scope);
        expect(pending.single.kind, WorkshopCommandKind.jobInvoiceContinuation);
        expect(pending.single.operationKey, 'lineas-f:factura');
        expect(pending.single.params, {'p_operation_key': 'lineas-f'});
        expect(pending.single.jobId, 'trabajo-1');
        expect(disk.values.keys,
            contains('${_scope.storageKey}:c:lineas-f:factura'),
            reason: 'en la misma escritura que retira el guardado');

        // Se cierra la app. Al volver, la causa sigue: sigue pendiente, sin
        // reenviar las líneas, y sólo quien abre el trabajo lo ve.
        server.continuationResults.add(_invoiceFailed);
        final restarted = _outbox(disk, server);
        final stillFailing = await restarted.resume(_scope);
        expect(stillFailing.single.outcome, WorkshopCommandOutcome.offline);
        expect(
            stillFailing.single.error, isA<WorkshopInvoicePendingException>());
        expect(workshopCommandNotice(stillFailing.single), isNull);
        expect(
          workshopCommandNotice(stillFailing.single, includeOffline: true),
          allOf(contains('su factura sigue pendiente'),
              contains('Confirma si se recibió')),
        );
        expect((await restarted.pending(_scope)).single.operationKey,
            'lineas-f:factura');

        // Alguien resolvió la causa: el siguiente intento la hace.
        server.continuationResults
            .add({'action': 'created', 'invoice_id': 'fv-7', 'error': null});
        final done =
            await _outbox(disk, server).resume(_scope, jobId: 'trabajo-1');
        expect(done.single.outcome, WorkshopCommandOutcome.committed);
        expect(
            workshopCommandNotice(done.single),
            'Trabajo PG-00360: su factura, que había quedado pendiente, quedó '
            'al día.');
        expect(await _outbox(disk, server).pending(_scope), isEmpty);
        expect(server.applied, 1, reason: 'las líneas se escribieron una vez');
        expect(server.continuations, 2);
        expect(server.receipts['lineas-f']!['invoice']['action'], 'created');

        final outbox = _outbox(disk, server);
        await outbox.flushAttempts(_scope);
        expect(
          server.recordedAttempts
              .where((a) => a['command_kind'] == 'job_invoice_continuation')
              .map((a) => '${a['outcome']}:${a['error_code']}'),
          ['offline:invoice_failed:23514', 'committed:null'],
        );
      });

      test(
          'tras fallar tres veces por el dato deja de reintentarse cada hora, '
          'y abrir el trabajo la vuelve a intentar', () async {
        final disk = _Disk();
        final server = _Server()..invoiceResult = _invoiceFailed;
        var now = DateTime.utc(2026, 9, 28, 12);
        WorkshopCommandOutbox outbox() =>
            _outbox(disk, server, clock: () => now);
        await outbox().submit(_scope, _billedLines('lineas-f'));
        server.continuationResults
            .addAll([_invoiceFailed, _invoiceFailed, _invoiceFailed]);
        for (var i = 0; i < 3; i++) {
          await outbox().resume(_scope);
        }
        expect(server.continuations, 3);
        final paused = (await outbox().pending(_scope)).single;
        expect(paused.lastErrorCode, 'invoice_failed:23514');
        expect(paused.pausedForInvoiceData, isTrue);

        // Horas después, la reanudación periódica no la envía.
        now = now.add(const Duration(hours: 6));
        await outbox().resume(_scope, respectBackoff: true);
        expect(server.continuations, 3);

        // Alguien resolvió la causa y abre el trabajo: se intenta y se hace.
        server.continuationResults
            .add({'action': 'created', 'invoice_id': 'fv-9', 'error': null});
        final opened = await outbox().resume(_scope, jobId: 'trabajo-1');
        expect(opened.single.outcome, WorkshopCommandOutcome.committed);
        expect(await outbox().pending(_scope), isEmpty);
      });

      test('una falla de red no la pausa', () async {
        final server = _Server()..invoiceResult = _invoiceFailed;
        final disk = _Disk();
        await _outbox(disk, server).submit(_scope, _billedLines('lineas-f'));
        server.networkUp = false;
        for (var i = 0; i < 4; i++) {
          await _outbox(disk, server).resume(_scope);
        }
        expect(
            (await _outbox(disk, server).pending(_scope))
                .single
                .pausedForInvoiceData,
            isFalse);
      });

      test('la respuesta perdida del guardado también la deja pendiente',
          () async {
        final disk = _Disk();
        final server = _Server()
          ..invoiceResult = _invoiceFailed
          ..loseNextAck = true;
        final lost = await _outbox(disk, server)
            .submit(_scope, _billedLines('lineas-f'));
        expect(lost.outcome, WorkshopCommandOutcome.reconciled,
            reason: 'el recibo lo cerró');
        expect((await _outbox(disk, server).pending(_scope)).single.kind,
            WorkshopCommandKind.jobInvoiceContinuation);
      });

      test(
          'no traba la cola del trabajo, y un guardado con la factura al día '
          'la retira', () async {
        final server = _Server()..invoiceResult = _invoiceFailed;
        final outbox = _outbox(_Disk(), server);
        await outbox.submit(_scope, _billedLines('lineas-1'));
        server
          ..networkUp = false
          ..invoiceResult = {'action': 'synced', 'invoice_id': 'fv-7'};

        // Sin red, la continuación no se hace; el guardado siguiente del
        // mismo trabajo no la espera.
        await outbox.resume(_scope);
        server.networkUp = true;
        final next = await outbox.submit(
          _scope,
          _billedLines('lineas-2', createdAt: DateTime.utc(2026, 9, 28, 11)),
        );
        expect(next.outcome, WorkshopCommandOutcome.committed);
        expect(await outbox.pending(_scope), isEmpty,
            reason: 'su factura ya cubre lo que el trabajo tiene ahora');
      });

      test('un recibo de la continuación sin la factura no la retira',
          () async {
        final server = _Server()..invoiceResult = _invoiceFailed;
        final outbox = _outbox(_Disk(), server);
        await outbox.submit(_scope, _billedLines('lineas-1'));
        server.receipts['lineas-1'] = {
          ...server.receipts['lineas-1']!,
          'invoice': null,
        };
        final run = await outbox.resume(_scope);
        expect(run.single.error, isA<FormatException>());
        expect((await outbox.pending(_scope)).single.operationKey,
            'lineas-1:factura');
      });
    });
  });

  group('la decisión de garantía (punto 2 del cierre)', () {
    List<String> keys(List<PendingWorkshopCommand> commands) =>
        [for (final command in commands) command.operationKey];

    test(
        'se respalda con las líneas: si la app se cierra después de '
        'escribirlas, la decisión y el estado salen al volver, en orden y una '
        'vez', () async {
      final disk = _Disk();
      final server = _Server();
      final first = _outbox(disk, server);
      final lines = await first.submit(
        _scope,
        _lines('lineas-1'),
        followUps: [_decision('decision-1'), _statusChange('estado-1')],
      );
      expect(lines.outcome, WorkshopCommandOutcome.committed);
      // La app se cierra aquí, antes de enviar la decisión: queda en el
      // disco con su llave, detrás de las líneas, y el estado detrás de ella.
      expect(keys(await first.pending(_scope)), ['decision-1', 'estado-1']);
      expect(server.sentKeys, ['lineas-1']);

      final resumed = await _outbox(disk, server).resume(_scope);
      expect(
        [
          for (final run in resumed)
            '${run.command.kind.wireName}:${run.outcome.name}'
        ],
        ['job_warranty_decision:committed', 'job_status_transition:committed'],
      );
      expect(server.appliedLog, [
        'job_line_save:lineas-1',
        'job_warranty_decision:decision-1',
        'job_status_transition:estado-1',
      ]);
      expect(await _outbox(disk, server).pending(_scope), isEmpty);
      // Otra vuelta no aplica nada otra vez.
      await _outbox(disk, server).resume(_scope);
      expect(server.applied, 3);
    });

    test(
        'con las líneas sin respuesta, la decisión no se adelanta; tras '
        'reiniciar, sale después de ellas', () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      final outbox = _outbox(disk, server);
      final lines = await outbox.submit(
        _scope,
        _lines('lineas-1'),
        followUps: [_decision('decision-1'), _statusChange('estado-1')],
      );
      expect(lines.outcome, WorkshopCommandOutcome.offline);
      server.sentKeys.clear();

      // Enviar la decisión por su llave no la adelanta: espera a las líneas.
      server.networkUp = true;
      final early = await outbox.run(_scope, 'decision-1',
          trigger: WorkshopCommandTrigger.retry);
      expect(early.outcome, WorkshopCommandOutcome.offline);
      expect(early.error, isA<WorkshopCommandQueuedException>());
      expect(server.sentKeys, isEmpty);
      expect(
        workshopCommandNotice(early, includeOffline: true),
        contains('detrás de otro cambio del mismo trabajo que sigue sin '
            'respuesta'),
      );

      final resumed = await _outbox(disk, server).resume(_scope);
      expect(resumed.map((run) => run.outcome),
          everyElement(WorkshopCommandOutcome.committed));
      expect(server.appliedLog, [
        'job_line_save:lineas-1',
        'job_warranty_decision:decision-1',
        'job_status_transition:estado-1',
      ]);
    });

    test('si las líneas no se escriben, lo que las seguía sale sin enviarse',
        () async {
      final disk = _Disk();
      final server = _Server()
        ..rejectKind[WorkshopCommandKind.jobLineSave] =
            const PostgrestException(
          message: 'Las líneas del trabajo cambiaron mientras lo editabas',
          code: 'PT409',
        );
      final outbox = _outbox(disk, server);
      final lines = await outbox.submit(
        _scope,
        _lines('lineas-1'),
        followUps: [_decision('decision-1'), _statusChange('estado-1')],
      );
      expect(lines.outcome, WorkshopCommandOutcome.stale);
      expect(keys(lines.droppedFollowUps), ['decision-1', 'estado-1']);
      expect(await outbox.pending(_scope), isEmpty);
      expect(server.sentKeys, ['lineas-1']);
      expect(server.appliedLog, isEmpty);
      expect(
        workshopCommandNotice(lines),
        endsWith('La decisión de garantía y el cambio de estado que lo '
            'seguían no se enviaron: vuelve a pedirlo al guardar de nuevo.'),
      );
      await outbox.flushAttempts(_scope);
      expect(
        [
          for (final attempt in server.recordedAttempts)
            if (attempt['error_code'] == 'prerequisite_not_written')
              '${attempt['command_kind']}:${attempt['outcome']}',
        ],
        ['job_warranty_decision:discarded', 'job_status_transition:discarded'],
      );
    });

    test(
        'lo que sigue espera a su comando aunque vaya en otra cola, y deja de '
        'esperarlo cuando se escribe', () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      final outbox = _outbox(disk, server);
      // Una decisión de otro trabajo detrás de estas líneas: no comparten
      // cola, sólo la dependencia.
      await outbox.submit(_scope, _lines('lineas-1'),
          followUps: [_decision('d-otro', jobId: 'trabajo-2')]);
      server
        ..networkUp = true
        ..sentKeys.clear();
      final early = await outbox.run(_scope, 'd-otro',
          trigger: WorkshopCommandTrigger.retry);
      expect(early.error, isA<WorkshopCommandQueuedException>());
      expect(server.sentKeys, isEmpty);
      final stored = (await outbox.pending(_scope)).last;
      expect(stored.dependsOn, 'lineas-1');

      await outbox.run(_scope, 'lineas-1',
          trigger: WorkshopCommandTrigger.retry);
      expect((await outbox.pending(_scope)).single.dependsOn, isNull);
      final after = await outbox.run(_scope, 'd-otro',
          trigger: WorkshopCommandTrigger.retry);
      expect(after.outcome, WorkshopCommandOutcome.committed);
    });

    test('descartar las líneas descarta lo que las sigue', () async {
      final server = _Server()..networkUp = false;
      final outbox = _outbox(_Disk(), server);
      await outbox.submit(_scope, _lines('lineas-1'),
          followUps: [_decision('decision-1')]);
      final run = await outbox.discard(_scope, 'lineas-1');
      expect(keys(run!.droppedFollowUps), ['decision-1']);
      expect(await outbox.pending(_scope), isEmpty);
    });

    test('respuesta perdida: el evento la cierra sin aplicarla dos veces',
        () async {
      final disk = _Disk();
      final server = _Server()..loseNextAck = true;
      final run = await _outbox(disk, server).submit(_scope, _decision('d-1'));
      expect(run.outcome, WorkshopCommandOutcome.reconciled);
      expect(run.response?['id'], 'evento-garantia-1');
      expect(server.applied, 1);
      expect(await _outbox(disk, server).pending(_scope), isEmpty);
    });

    test(
        'sin respuesta ni lectura queda pendiente; el reenvío con la misma '
        'llave dice replay y se concilia sin otra decisión', () async {
      final disk = _Disk();
      final server = _Server()
        ..loseNextAck = true
        ..probeUp = false;
      final first =
          await _outbox(disk, server).submit(_scope, _decision('d-1'));
      expect(first.outcome, WorkshopCommandOutcome.offline);
      expect(server.applied, 1, reason: 'el servidor sí la escribió');
      expect(keys(await _outbox(disk, server).pending(_scope)), ['d-1']);
      expect(
        workshopCommandNotice(first, includeOffline: true),
        contains('sigue sin respuesta del servidor. Quedó en este equipo con '
            'su llave y se aplica sola'),
      );

      // Se cierra la app; al volver, el reenvío con la misma llave.
      server.probeUp = true;
      final resumed = await _outbox(disk, server).resume(_scope);
      expect(resumed.single.outcome, WorkshopCommandOutcome.reconciled);
      expect(resumed.single.response?['replay'], isTrue);
      expect(server.applied, 1);
      expect(await _outbox(disk, server).pending(_scope), isEmpty);
    });

    test('un comprobante de otra decisión no la retira', () async {
      final disk = _Disk();
      final server = _Server()
        ..malformedAck = {
          'id': 'evento-x',
          // El taller es el de la bandeja: lo que lo invalida es la decisión.
          'tenant_id': 'taller',
          'warranty_job_id': 'trabajo-1',
          'operation_key': 'd-1',
          'event_type': 'decision',
          'outcome': 'not_covered',
          'reason': 'otra',
          'replay': false,
        };
      final run = await _outbox(disk, server).submit(_scope, _decision('d-1'));
      expect(run.outcome, WorkshopCommandOutcome.offline);
      expect(run.error, isA<FormatException>());
      expect(keys(await _outbox(disk, server).pending(_scope)), ['d-1']);
    });

    test('rechazada: sale sin reintentarse, y el estado que la seguía también',
        () async {
      final disk = _Disk();
      final server = _Server()
        ..rejectKind[WorkshopCommandKind.jobWarrantyDecision] =
            const PostgrestException(
          message: 'Rechazar una garantía requiere una justificación',
          code: 'P0001',
        );
      final outbox = _outbox(disk, server);
      // Sin líneas que mandar: la decisión y el estado se respaldan juntos.
      await outbox.enqueue(_scope, _decision('d-1', outcome: 'not_covered'),
          followUps: [_statusChange('estado-1')]);
      final run =
          await outbox.run(_scope, 'd-1', trigger: WorkshopCommandTrigger.save);
      expect(run.outcome, WorkshopCommandOutcome.rejected);
      expect(keys(run.droppedFollowUps), ['estado-1']);
      expect(await outbox.pending(_scope), isEmpty);
      expect(server.sentKeys, ['d-1']);
      expect(
        workshopCommandNotice(run),
        'Trabajo PG-00360: la decisión de garantía «No cubierto» pendiente no '
        'se aplicó (Rechazar una garantía requiere una justificación). Ábrelo '
        'y decide de nuevo. El cambio de estado que lo seguía no se envió: '
        'vuelve a pedirlo al guardar de nuevo.',
      );
      // Al volver no se reintenta.
      await _outbox(disk, server).resume(_scope);
      expect(server.sentKeys, ['d-1']);
    });

    test('40001 en la decisión no es un rechazo: queda pendiente con su llave',
        () async {
      final disk = _Disk();
      final server = _Server()
        ..rejectKind[WorkshopCommandKind.jobWarrantyDecision] =
            const PostgrestException(
          message: 'El vínculo financiero del trabajo cambió durante la '
              'decisión; vuelve a intentarlo',
          code: '40001',
        );
      final run = await _outbox(disk, server).submit(_scope, _decision('d-1'));
      expect(run.outcome, WorkshopCommandOutcome.offline);
      expect(keys(await _outbox(disk, server).pending(_scope)), ['d-1']);
      server.rejectKind.clear();
      final resumed = await _outbox(disk, server).resume(_scope);
      expect(resumed.single.outcome, WorkshopCommandOutcome.committed);
      expect(server.applied, 1);
    });

    test(
        'desde la tabla: espera detrás de un guardado sin respuesta del mismo '
        'trabajo, y un estado pedido después espera detrás de ella', () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      final outbox = _outbox(disk, server);
      await outbox.submit(_scope, _lines('lineas-1'));
      final decision = await outbox.submit(_scope, _decision('d-1'));
      expect(decision.outcome, WorkshopCommandOutcome.offline);
      expect(decision.error, isA<WorkshopCommandQueuedException>());
      final status = await outbox.submit(_scope, _statusChange('estado-1'));
      expect(status.error, isA<WorkshopCommandQueuedException>());

      server.networkUp = true;
      await _outbox(disk, server).resume(_scope);
      expect(server.appliedLog, [
        'job_line_save:lineas-1',
        'job_warranty_decision:d-1',
        'job_status_transition:estado-1',
      ]);
    });

    test('otra cuenta u otro taller en el mismo equipo no la ven ni la envían',
        () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      await _outbox(disk, server).submit(_scope, _decision('d-1'));
      const otherTenant =
          WorkshopCommandScope(tenantId: 'otro-taller', userId: 'mecanico');
      const otherUser =
          WorkshopCommandScope(tenantId: 'taller', userId: 'otra');
      expect(await _outbox(disk, server).pending(otherTenant), isEmpty);
      expect(await _outbox(disk, server).pending(otherUser), isEmpty);

      // La misma cuenta, ahora en otro taller: no se envía con esa sesión.
      server
        ..networkUp = true
        ..currentTenant = 'otro-taller'
        ..sentKeys.clear();
      await expectLater(
        _outbox(disk, server)
            .run(_scope, 'd-1', trigger: WorkshopCommandTrigger.resume),
        throwsA(isA<WorkshopScopeChangedException>()),
      );
      expect(server.sentKeys, isEmpty);
      expect(keys(await _outbox(disk, server).pending(_scope)), ['d-1']);
    });

    test('volver a elegir la misma decisión reusa su llave; otra va detrás',
        () {
      final pending = [
        _decision('d-1', outcome: 'covered'),
        _lines('lineas-1'),
      ];
      expect(warrantyDecisionKeyFor(pending, _decision('nueva')), 'd-1');
      expect(
          warrantyDecisionKeyFor(
              pending, _decision('nueva', outcome: 'not_covered', reason: 'x')),
          'nueva');
      // Sólo la última cuenta: si después se pidió otra, volver a la primera
      // es una decisión nueva detrás de ésa.
      final both = [
        ...pending,
        _decision('d-2', outcome: 'not_covered', reason: 'sin factura'),
      ];
      expect(warrantyDecisionKeyFor(both, _decision('nueva')), 'nueva');
      expect(
          warrantyDecisionKeyFor(
              both,
              _decision('nueva',
                  outcome: 'not_covered', reason: ' sin factura ')),
          'd-2');
      // La de otro trabajo no se toca, ni tapa la de éste aunque vaya después.
      expect(warrantyDecisionKeyFor(pending, _decision('nueva', jobId: 'otro')),
          'nueva');
      final otherJobLast = [
        ...pending,
        _decision('d-otro', jobId: 'otro'),
      ];
      expect(warrantyDecisionKeyFor(otherJobLast, _decision('nueva')), 'd-1');
    });

    group('revisión de Codex (2026-09-29)', () {
      for (final written in [1, 2]) {
        test(
            'un corte tras $written de 3 escrituras nunca deja las líneas sin '
            'lo que las seguía', () async {
          final disk = _Disk()..failWriteAfter = written;
          final server = _Server()..networkUp = false;
          await expectLater(
            _outbox(disk, server).submit(_scope, _lines('lineas-1'),
                followUps: [_decision('d-1'), _statusChange('e-1')]),
            throwsA(isA<WorkshopOutboxPersistenceException>()),
          );
          // Lo escrito es lo que depende de otro; las líneas no.
          expect(
            disk.values.keys.where((key) => key.contains(':c:lineas-1')),
            isEmpty,
          );
          disk.failWriteAfter = null;
          server.networkUp = true;
          final outbox = _outbox(disk, server);
          expect(await outbox.pending(_scope), isEmpty);
          final runs = await outbox.resume(_scope);
          expect(server.sentKeys, isEmpty);
          expect(runs.single.outcome, WorkshopCommandOutcome.discarded);
          expect(runs.single.error,
              isA<WorkshopCommandPrerequisiteNotWrittenException>());
          expect(
            disk.values.keys.where((key) => key.contains(':c:')),
            isEmpty,
          );
        });
      }

      test(
          'lo que quedó sin su comando previo (un corte a mitad de sacarlo) '
          'sale sin enviarse y se dice', () async {
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        await _outbox(disk, server).submit(_scope, _lines('lineas-1'),
            followUps: [_decision('d-1'), _statusChange('e-1')]);
        // El corte: las líneas rechazadas alcanzaron a salir de la bandeja,
        // lo que las seguía no.
        disk.values.removeWhere((key, _) => key.endsWith(':c:lineas-1'));
        server
          ..networkUp = true
          ..sentKeys.clear();
        final outbox = _outbox(disk, server);
        expect(await outbox.pending(_scope), isEmpty);
        final run = await outbox.run(_scope, 'd-1',
            trigger: WorkshopCommandTrigger.retry);
        expect(server.sentKeys, isEmpty);
        expect(run.outcome, WorkshopCommandOutcome.discarded);
        expect(run.droppedFollowUps.single.operationKey, 'e-1');
        expect(
          workshopCommandNotice(run),
          'Trabajo PG-00360: la decisión de garantía «Cubierto» no se envió '
          'porque lo que iba antes no quedó guardado en este equipo; vuelve a '
          'pedirlo. El cambio de estado que lo seguía no se envió: vuelve a '
          'pedirlo al guardar de nuevo.',
        );
        expect(disk.values.keys.where((key) => key.contains(':c:')), isEmpty);
        // El envío de intentos que lanzó la corrida termina primero.
        await pumpEventQueue();
        await outbox.flushAttempts(_scope);
        expect(
          [
            for (final attempt in server.recordedAttempts)
              if (attempt['error_code'] == 'prerequisite_not_written')
                '${attempt['command_kind']}:${attempt['outcome']}',
          ],
          [
            'job_warranty_decision:discarded',
            'job_status_transition:discarded'
          ],
        );
      });

      test(
          'un estado pedido aparte con la decisión pendiente depende de ella: '
          'si se rechaza, el estado no se aplica', () async {
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        final outbox = _outbox(disk, server);
        await outbox.submit(_scope, _decision('d-1'));
        final status = await outbox.submit(
          _scope,
          _statusChange('e-1', createdAt: DateTime.utc(2026, 9, 29, 11)),
        );
        expect(status.error, isA<WorkshopCommandQueuedException>());
        expect((await outbox.pending(_scope)).last.dependsOn, 'd-1');
        server
          ..networkUp = true
          ..sentKeys.clear()
          ..rejectKind[WorkshopCommandKind.jobWarrantyDecision] =
              const PostgrestException(
            message: 'No se puede marcar como cubierta una garantía con pagos '
                'vigentes',
            code: 'P0001',
          );
        final runs = await outbox.resume(_scope);
        expect(server.sentKeys, ['d-1']);
        expect(runs.single.outcome, WorkshopCommandOutcome.rejected);
        expect(runs.single.droppedFollowUps.single.operationKey, 'e-1');
        expect(await outbox.pending(_scope), isEmpty);
      });

      test('un estado de otro trabajo no espera la decisión', () async {
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        final outbox = _outbox(disk, server);
        await outbox.submit(_scope, _decision('d-1'));
        await outbox.submit(_scope, _statusChange('e-2', jobId: 'trabajo-2'));
        expect((await outbox.pending(_scope)).last.dependsOn, isNull);
      });

      test(
          'reenviar la decisión ya respaldada, con otra hora, no la pone '
          'detrás del estado que la sigue', () async {
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        final outbox = _outbox(disk, server);
        await outbox.submit(_scope, _lines('lineas-1'),
            followUps: [_decision('d-1'), _statusChange('e-1')]);
        server
          ..networkUp = true
          ..sentKeys.clear();
        await outbox.run(_scope, 'lineas-1',
            trigger: WorkshopCommandTrigger.retry);
        // El formulario arma de nuevo la misma decisión, con la hora de ahora.
        final later = DateTime.utc(2026, 9, 30);
        final decision =
            await outbox.submit(_scope, _decision('d-1', createdAt: later));
        expect(decision.outcome, WorkshopCommandOutcome.committed);
        final status =
            await outbox.submit(_scope, _statusChange('e-1', createdAt: later));
        expect(status.outcome, WorkshopCommandOutcome.committed);
        expect(server.sentKeys, ['lineas-1', 'd-1', 'e-1']);
      });

      test('dos ventanas que eligen la misma decisión a la vez hacen una sola',
          () async {
        final disk = _Disk()..yieldOnIo = true;
        final server = _Server()..networkUp = false;
        final windowA = _outbox(disk, server);
        final windowB = _outbox(disk, server);
        final runs = await Future.wait([
          windowA.submit(_scope, _decision('d-a')),
          windowB.submit(_scope, _decision('d-b')),
        ]);
        final pending = await windowA.pending(_scope);
        expect(pending, hasLength(1));
        expect(
          runs.map((run) => run.command.operationKey).toSet(),
          {pending.single.operationKey},
        );
        server.networkUp = true;
        await windowA.resume(_scope);
        expect(server.appliedLog, hasLength(1));
      });

      for (final receipt in <String, Map<String, dynamic>>{
        'de otro taller': {'id': 'evento-x', 'tenant_id': 'otro-taller'},
        'sin id del evento': {'tenant_id': 'taller'},
        'con id en blanco': {'id': '   ', 'tenant_id': 'taller'},
      }.entries) {
        test('un comprobante ${receipt.key} no la retira', () async {
          final disk = _Disk();
          final server = _Server()
            ..probeUp = false
            ..malformedAck = {
              'warranty_job_id': 'trabajo-1',
              'operation_key': 'd-1',
              'event_type': 'decision',
              'outcome': 'covered',
              'reason': null,
              'replay': false,
              ...receipt.value,
            };
          final run =
              await _outbox(disk, server).submit(_scope, _decision('d-1'));
          expect(run.outcome, WorkshopCommandOutcome.offline);
          expect(run.error, isA<FormatException>());
          expect(
            (await _outbox(disk, server).pending(_scope)).single.operationKey,
            'd-1',
          );
        });
      }
    });

    group('segunda revisión de Codex (2026-09-29)', () {
      for (final statusAt in [
        DateTime.utc(2026, 9, 29, 10), // la misma hora que la decisión
        DateTime.utc(2026, 9, 29, 9), // antes que la decisión
      ]) {
        test(
            'el estado que depende de la decisión va después también en la '
            'cola (${statusAt.hour}:00)', () async {
          final disk = _Disk();
          final server = _Server()..networkUp = false;
          final outbox = _outbox(disk, server);
          await outbox.submit(_scope, _decision('z-decision'));
          await outbox.submit(
              _scope, _statusChange('a-status', createdAt: statusAt));
          final stored = (await outbox.pending(_scope))
              .firstWhere((command) => command.operationKey == 'a-status');
          expect(stored.dependsOn, 'z-decision');
          server
            ..networkUp = true
            ..sentKeys.clear();
          final runs = await outbox.resume(_scope);
          expect(server.sentKeys, ['z-decision', 'a-status']);
          expect(runs.map((run) => run.outcome),
              everyElement(WorkshopCommandOutcome.committed));
        });
      }

      test('lo que depende de un comando ilegible no es huérfano', () async {
        final disk = _Disk();
        final server = _Server();
        final prefix = '${_scope.storageKey}:c:';
        // Otra versión de la app guardó las líneas con un formato nuevo.
        disk.values['${prefix}lineas-x'] = jsonEncode({
          'operation_key': 'lineas-x',
          'kind': 'job_line_save_v9',
          'job_id': 'trabajo-1',
        });
        disk.values['${prefix}d-1'] = jsonEncode(
            _decision('d-1').copyWith(dependsOn: 'lineas-x').toJson());
        final outbox = _outbox(disk, server);
        expect((await outbox.pending(_scope)).single.operationKey, 'd-1');
        final runs = await outbox.resume(_scope);
        expect(runs, isEmpty);
        expect(server.sentKeys, isEmpty);
        expect(disk.values.containsKey('${prefix}d-1'), isTrue);
      });

      test(
          'una decisión igual a la pendiente, con un estado detrás, reusa la '
          'pendiente y le cuelga el estado', () async {
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        final outbox = _outbox(disk, server);
        await outbox.submit(_scope, _decision('d-a'));
        final key = await outbox.enqueue(_scope, _decision('d-b'),
            followUps: [_statusChange('e-1')]);
        expect(key, 'd-a');
        final pending = await outbox.pending(_scope);
        expect(pending.map((command) => command.operationKey), ['d-a', 'e-1']);
        expect(pending.last.dependsOn, 'd-a');
        server.networkUp = true;
        await outbox.resume(_scope);
        expect(server.appliedLog, [
          'job_warranty_decision:d-a',
          'job_status_transition:e-1',
        ]);
      });
    });

    test('el aviso dice la decisión que quedó aplicada', () async {
      final server = _Server();
      final run =
          await _outbox(_Disk(), server).submit(_scope, _decision('d-1'));
      expect(
        workshopCommandNotice(run),
        'Trabajo PG-00360: se aplicó la decisión de garantía «Cubierto» que '
        'había quedado pendiente. Su respaldo interno quedó al día.',
      );
    });
  });

  group('el alta del trabajo (cierre del 2026-09-29)', () {
    const job = 'trabajo-nuevo';

    for (final written in [0, 1, 2]) {
      test(
          'un corte tras $written de 3 escrituras nunca deja el alta sin sus '
          'líneas', () async {
        final disk = _Disk()..failWriteAfter = written;
        final server = _Server();
        await expectLater(
          _outbox(disk, server).submit(_scope, _jobCreation(job), followUps: [
            _lines('lineas-1', jobId: job),
            _registration('r-1')
          ]),
          throwsA(isA<WorkshopOutboxPersistenceException>()),
        );
        // Lo que quedó escrito depende de otro; el alta, que va primero,
        // se escribe última.
        expect(
            disk.values.keys.where((key) => key.endsWith(':c:$job')), isEmpty);
        expect(server.sentKeys, isEmpty,
            reason: 'nada salió antes de respaldar');
        disk.failWriteAfter = null;
        final outbox = _outbox(disk, server);
        expect(await outbox.pending(_scope), isEmpty);
        await outbox.resume(_scope);
        expect(server.sentKeys, isEmpty);
        expect(disk.values.keys.where((key) => key.contains(':c:')), isEmpty);
      });
    }

    test(
        'se cierra la app después del alta: al volver salen las líneas y el '
        'registro, una vez cada uno, en orden', () async {
      final disk = _Disk();
      final server = _Server();
      // `submit` envía sólo el alta; la app se cierra antes de las líneas.
      final created = await _outbox(disk, server).submit(
          _scope, _jobCreation(job),
          followUps: [_lines('lineas-1', jobId: job), _registration('r-1')]);
      expect(created.outcome, WorkshopCommandOutcome.committed);
      expect(server.appliedLog, ['job_create:$job']);
      final pending = await _outbox(disk, server).pending(_scope);
      expect(pending.map((command) => command.dependsOn), [null, 'lineas-1']);

      final runs = await _outbox(disk, server).resume(_scope);
      expect(runs.map((run) => run.outcome),
          everyElement(WorkshopCommandOutcome.committed));
      expect(server.appliedLog, [
        'job_create:$job',
        'job_line_save:lineas-1',
        'job_warranty_registration:r-1',
      ]);
      expect(await _outbox(disk, server).pending(_scope), isEmpty);
    });

    test(
        'sin red: no hay trabajo creado, nada sale, y al volver sale todo en '
        'orden', () async {
      final disk = _Disk();
      final server = _Server()..networkUp = false;
      final run = await _outbox(disk, server).submit(_scope, _jobCreation(job),
          followUps: [_lines('lineas-1', jobId: job)]);
      expect(run.outcome, WorkshopCommandOutcome.offline);
      expect(server.appliedLog, isEmpty);
      expect(
        workshopCommandNotice(run, includeOffline: true),
        'Trabajo nuevo de Ana: el trabajo nuevo sigue sin respuesta del '
        'servidor; todavía no está creado. Quedó en este equipo, con sus '
        'líneas, y se envía solo.',
      );
      // Las líneas esperan al alta aunque se pidan por su llave.
      final early = await _outbox(disk, server)
          .run(_scope, 'lineas-1', trigger: WorkshopCommandTrigger.retry);
      expect(early.error, isA<WorkshopCommandQueuedException>());
      expect(server.sentKeys, [job], reason: 'sólo se intentó el alta');

      server.networkUp = true;
      final runs = await _outbox(disk, server).resume(_scope);
      expect(server.appliedLog, ['job_create:$job', 'job_line_save:lineas-1']);
      expect(
        workshopCommandNotice(runs.first),
        'Trabajo nuevo de Ana: se creó el trabajo PG-001 que había quedado '
        'pendiente en este equipo; sus líneas van detrás.',
      );
    });

    test(
        'respuesta perdida del alta: el recibo la da por creada y no se crea '
        'otra', () async {
      final disk = _Disk();
      final server = _Server()..loseNextAck = true;
      final run = await _outbox(disk, server).submit(_scope, _jobCreation(job),
          followUps: [_lines('lineas-1', jobId: job)]);
      expect(run.outcome, WorkshopCommandOutcome.reconciled);
      expect(run.response?['job']?['id'], job);
      final lines = await _outbox(disk, server)
          .run(_scope, 'lineas-1', trigger: WorkshopCommandTrigger.save);
      expect(lines.outcome, WorkshopCommandOutcome.committed);
      expect(server.appliedLog, ['job_create:$job', 'job_line_save:lineas-1']);
    });

    test(
        'respuesta perdida sin recibo a la vista: sigue pendiente, y el '
        'reenvío con la misma llave repite el recibo', () async {
      final disk = _Disk();
      final server = _Server()
        ..loseNextAck = true
        ..probeUp = false;
      final run = await _outbox(disk, server).submit(_scope, _jobCreation(job),
          followUps: [_lines('lineas-1', jobId: job)]);
      expect(run.outcome, WorkshopCommandOutcome.offline);
      server.probeUp = true;
      final again = await _outbox(disk, server)
          .run(_scope, job, trigger: WorkshopCommandTrigger.retry);
      expect(again.outcome, WorkshopCommandOutcome.reconciled);
      expect(server.appliedLog, ['job_create:$job'],
          reason: 'el reenvío no creó otro trabajo');
    });

    test('el alta rechazada: no se envía nada de lo que la seguía, y se dice',
        () async {
      final disk = _Disk();
      final server = _Server()
        ..rejectKind[WorkshopCommandKind.jobCreate] = const PostgrestException(
          message: 'La llave del alta ya respalda otro trabajo',
          code: '23505',
        );
      final run = await _outbox(disk, server).submit(_scope, _jobCreation(job),
          followUps: [_lines('lineas-1', jobId: job), _registration('r-1')]);
      expect(run.outcome, WorkshopCommandOutcome.rejected);
      expect(server.sentKeys, [job]);
      expect(run.droppedFollowUps.map((command) => command.operationKey),
          ['lineas-1', 'r-1']);
      expect(
        workshopCommandNotice(run),
        'Trabajo nuevo de Ana: el trabajo nuevo no se creó (La llave del alta '
        'ya respalda otro trabajo). Las líneas y el registro de la garantía que '
        'lo seguían no se enviaron: vuelve a pedirlo al guardar de nuevo.',
      );
      expect(await _outbox(disk, server).pending(_scope), isEmpty);
    });

    for (final receipt in <String, Map<String, dynamic>>{
      'de otro trabajo': {'id': 'otro-trabajo', 'tenant_id': 'taller'},
      'de otro taller': {'id': job, 'tenant_id': 'otro-taller'},
      'sin trabajo': {},
    }.entries) {
      test('un recibo ${receipt.key} no da el alta por creada', () async {
        final disk = _Disk();
        final server = _Server()
          ..probeUp = false
          ..malformedAck = {
            'operation_id': 'op-x',
            'replayed': false,
            if (receipt.value.isNotEmpty) 'job': receipt.value,
          };
        final run = await _outbox(disk, server).submit(
            _scope, _jobCreation(job),
            followUps: [_lines('lineas-1', jobId: job)]);
        expect(run.outcome, WorkshopCommandOutcome.offline);
        expect(run.error, isA<FormatException>());
        expect((await _outbox(disk, server).pending(_scope)).first.operationKey,
            job);
      });
    }

    test(
        'el registro de otra garantía no retira el de éste; el registro que ya '
        'estaba sí', () async {
      final disk = _Disk();
      final server = _Server()
        ..probeUp = false
        ..malformedAck = {
          'id': 'registro-x',
          'tenant_id': 'taller',
          'warranty_job_id': job,
          'source_job_id': 'otro-origen',
          'operation_key': 'r-1',
          'event_type': 'registration',
          'replay': false,
        };
      await _outbox(disk, server).enqueue(_scope, _registration('r-1'));
      final wrong = await _outbox(disk, server)
          .run(_scope, 'r-1', trigger: WorkshopCommandTrigger.retry);
      expect(wrong.outcome, WorkshopCommandOutcome.offline);
      expect(wrong.error, isA<FormatException>());
      // El servidor devuelve el registro que ya estaba (otra llave) como
      // repetición: vale.
      server.malformedAck = {
        'id': 'registro-anterior',
        'tenant_id': 'taller',
        'warranty_job_id': job,
        'source_job_id': 'trabajo-origen',
        'operation_key': 'r-1',
        'canonical_operation_key': 'r-0',
        'event_type': 'registration',
        'replay': true,
      };
      final replay = await _outbox(disk, server)
          .run(_scope, 'r-1', trigger: WorkshopCommandTrigger.retry);
      expect(replay.outcome, WorkshopCommandOutcome.reconciled);
    });

    test('el alta y su registro van en la cola del trabajo', () {
      expect(_jobCreation(job).queueKeys, {'job:$job'});
      expect(_registration('r-1').queueKeys, {'job:$job'});
    });

    test(
        'otra ventana reanuda mientras ésta envía el alta: un trabajo, y las '
        'líneas nunca antes que él', () async {
      final disk = _Disk()..yieldOnIo = true;
      final server = _Server();
      final windowA = _outbox(disk, server);
      final windowB = _outbox(disk, server);
      final submitted = windowA.submit(_scope, _jobCreation(job),
          followUps: [_lines('lineas-a', jobId: job), _registration('r-1')]);
      final resumed = () async {
        for (var turn = 0; turn < 6; turn++) {
          await windowB.resume(_scope);
        }
      }();
      await Future.wait([submitted, resumed]);
      await windowA.resume(_scope);
      expect(server.appliedLog, [
        'job_create:$job',
        'job_line_save:lineas-a',
        'job_warranty_registration:r-1',
      ]);
      expect(await windowA.pending(_scope), isEmpty);
    });

    group('revisión de Codex del alta (2026-09-29)', () {
      for (final removed in [0, 1, 2]) {
        test(
            'un corte tras $removed borrados al sacar un alta rechazada nunca '
            'deja el alta sin sus líneas', () async {
          final disk = _Disk();
          final server = _Server()
            ..rejectKind[WorkshopCommandKind.jobCreate] =
                const PostgrestException(
                    message: 'cliente inválido', code: 'P0001');
          final outbox = _outbox(disk, server);
          await outbox.enqueue(_scope, _jobCreation(job), followUps: [
            _lines('lineas-1', jobId: job),
            _registration('r-1')
          ]);
          disk.failRemoveAfter = removed;
          await expectLater(
            outbox.run(_scope, job, trigger: WorkshopCommandTrigger.save),
            throwsA(isA<WorkshopOutboxPersistenceException>()),
          );
          // Se arregló lo que el servidor rechazaba y la app vuelve.
          disk.failRemoveAfter = null;
          server.rejectKind.clear();
          await _outbox(disk, server).resume(_scope);
          if (server.appliedLog.contains('job_create:$job')) {
            expect(server.appliedLog, contains('job_line_save:lineas-1'),
                reason: 'el alta nunca sale sin sus líneas');
          }
          expect(await _outbox(disk, server).pending(_scope), isEmpty);
        });
      }

      test(
          'un corte al respaldar y el mismo trabajo guardado otra vez: lo viejo '
          'sale sin enviarse y no traba la cola', () async {
        final disk = _Disk()..failWriteAfter = 2;
        final server = _Server();
        await expectLater(
          _outbox(disk, server).submit(_scope, _jobCreation(job), followUps: [
            _lines('lineas-1', jobId: job),
            _registration('r-1')
          ]),
          throwsA(isA<WorkshopOutboxPersistenceException>()),
        );
        disk.failWriteAfter = null;
        // El formulario vuelve a guardar el mismo trabajo nuevo (la misma
        // llave del alta) con sus líneas de ahora.
        final run = await _outbox(disk, server).submit(
          _scope,
          _jobCreation(job, createdAt: DateTime.utc(2026, 9, 29, 11)),
          followUps: [
            _lines('lineas-2',
                jobId: job, createdAt: DateTime.utc(2026, 9, 29, 11)),
            _registration('r-2'),
          ],
        );
        expect(run.outcome, WorkshopCommandOutcome.committed);
        await _outbox(disk, server).resume(_scope);
        expect(server.appliedLog, [
          'job_create:$job',
          'job_line_save:lineas-2',
          'job_warranty_registration:r-2',
        ]);
        expect(server.sentKeys, isNot(contains('lineas-1')));
        expect(await _outbox(disk, server).pending(_scope), isEmpty);
      });

      test(
          'otra pestaña envía el alta entre el respaldo y el envío de ésta: '
          'el recibo la da por creada, sin error', () async {
        final disk = _Disk();
        final server = _Server();
        // Sin Web Locks: cada pestaña con su candado.
        final windowA = _outbox(disk, server, lock: _InstanceLock());
        final windowB = _outbox(disk, server, lock: _InstanceLock());
        disk.afterWrite = (key) async {
          if (!key.endsWith(':c:$job')) return;
          disk.afterWrite = null;
          await windowB.run(_scope, job,
              trigger: WorkshopCommandTrigger.resume);
        };
        final run = await windowA.submit(_scope, _jobCreation(job),
            followUps: [_lines('lineas-1', jobId: job)]);
        expect(run.outcome, WorkshopCommandOutcome.reconciled);
        expect(run.response?['job']?['id'], job);
        final lines = await windowA.run(_scope, 'lineas-1',
            trigger: WorkshopCommandTrigger.save);
        expect(lines.outcome, WorkshopCommandOutcome.committed);
        expect(
            server.appliedLog, ['job_create:$job', 'job_line_save:lineas-1']);
      });

      test('el recibo de la misma llave con otro contenido no confirma el alta',
          () async {
        final disk = _Disk();
        final server = _Server();
        // Lo que esa llave escribió antes, con otra prioridad.
        await server.send(WorkshopCommandKind.jobCreate, {
          'p_operation_key': job,
          'p_job': {
            ..._jobCreation(job).params['p_job'] as Map,
            'priority': 'URGENTE',
          },
        });
        server.networkUp = false;
        final run = await _outbox(disk, server).submit(
            _scope, _jobCreation(job),
            followUps: [_lines('lineas-1', jobId: job)]);
        // Sin red y con un recibo de otro contenido: sigue pendiente.
        expect(run.outcome, WorkshopCommandOutcome.offline);
        expect((await _outbox(disk, server).pending(_scope)).first.operationKey,
            job);
        // Ya fuera de la bandeja, tampoco.
        // Fuera de la bandeja nadie lo reenviaría: es definitivo, y se dice
        // (segunda revisión de Codex).
        final gone = await _outbox(_Disk(), server).runOrReconcile(
            _scope, _jobCreation(job),
            trigger: WorkshopCommandTrigger.retry);
        expect(gone.outcome, WorkshopCommandOutcome.rejected);
        expect(gone.error, isA<WorkshopCommandContentConflictException>());
        expect(
          workshopCommandNotice(gone),
          'Trabajo nuevo de Ana: el trabajo nuevo no se creó (esa llave ya se '
          'usó con otro contenido; lo que se escribió con ella está en el '
          'servidor (búscalo en Trabajos)).',
        );
        // Y el suyo sí.
        final same = await _outbox(_Disk(), server).runOrReconcile(
            _scope,
            PendingWorkshopCommand(
              operationKey: job,
              kind: WorkshopCommandKind.jobCreate,
              params: {
                'p_operation_key': job,
                'p_job': {
                  ..._jobCreation(job).params['p_job'] as Map,
                  'priority': 'URGENTE',
                },
              },
              createdAt: DateTime.utc(2026, 9, 29, 9),
              jobId: job,
            ),
            trigger: WorkshopCommandTrigger.retry);
        expect(same.outcome, WorkshopCommandOutcome.reconciled);
        // Sin recibo y fuera de la bandeja: no se creó.
        final never = await _outbox(_Disk(), _Server()).runOrReconcile(
            _scope, _jobCreation(job),
            trigger: WorkshopCommandTrigger.retry);
        expect(never.outcome, WorkshopCommandOutcome.discarded);
        expect(never.error, isA<WorkshopCommandNotPendingError>());
      });

      test(
          'la misma decisión con un estado detrás, y otra pestaña la envía '
          'antes: se concilia por su recibo (segunda revisión)', () async {
        final disk = _Disk();
        final server = _Server();
        final windowA = _outbox(disk, server, lock: _InstanceLock());
        final windowB = _outbox(disk, server, lock: _InstanceLock());
        await windowA.enqueue(_scope, _decision('d-1'));
        disk.afterWrite = (key) async {
          if (!key.endsWith(':c:estado-1')) return;
          disk.afterWrite = null;
          await windowB.run(_scope, 'd-1',
              trigger: WorkshopCommandTrigger.resume);
        };
        // El formulario pide la misma decisión (reusa d-1) con un estado.
        final run = await windowA.submit(
          _scope,
          _decision('d-2', createdAt: DateTime.utc(2026, 9, 29, 11)),
          followUps: [_statusChange('estado-1')],
        );
        expect(run.command.operationKey, 'd-1');
        expect(run.outcome, WorkshopCommandOutcome.reconciled);
        // Cada uno una vez: la otra pestaña siguió con el estado.
        expect(server.appliedLog,
            ['job_warranty_decision:d-1', 'job_status_transition:estado-1']);
      });
    });
  });

  group('carrera del barrido de adjuntos (2026-09-29)', () {
    const job = 'trabajo-nuevo';

    PendingBikeImage attachment(String path, {String jobId = job}) =>
        PendingBikeImage(
          bucket: 'job-images',
          objectPath: path,
          publicUrl: 'https://x/storage/v1/object/public/job-images/$path',
          jobId: jobId,
          createdAt: DateTime.utc(2026, 9, 29, 12),
          ownerForm: 'trabajo-form',
        );

    Future<PendingBikeImage> uploadAttachment(
      WorkshopCommandOutbox outbox,
      _Server server,
      String path, {
      String jobId = job,
    }) async {
      final pending = attachment(path, jobId: jobId);
      await outbox.recordImageIntent(_scope, pending);
      server.storedImages.add(path);
      await outbox.markImageUploaded(_scope, path);
      return pending;
    }

    /// El guardado de líneas de un trabajo que ya existe, con [urls] como
    /// sus adjuntos y [seen] como lo que el formulario vio en el trabajo.
    PendingWorkshopCommand linesWithAttachments(
      String key,
      List<String> urls, {
      List<String> seen = const [],
      String jobId = 'trabajo-1',
    }) {
      final base = _lines(key, jobId: jobId);
      return PendingWorkshopCommand(
        operationKey: key,
        kind: base.kind,
        params: {
          ...base.params,
          'p_header': {
            'image_urls': {'value': urls, 'expected': seen},
          },
        },
        createdAt: base.createdAt,
        jobId: base.jobId,
        label: base.label,
      );
    }

    for (final path in ['alta', 'edición de líneas']) {
      test(
          'otra ventana pone el adjunto en un guardado ($path) mientras el '
          'barrido lo borra: ningún trabajo queda con un enlace roto',
          () async {
        final disk = _Disk();
        final server = _Server();
        // Dos ventanas con el mismo candado (el mismo proceso, o Web Locks).
        final lock = _InstanceLock();
        var now = DateTime.utc(2026, 9, 29, 12);
        final windowA = _outbox(disk, server,
            concurrent: true, clock: () => now, lock: lock);
        final windowB = _outbox(disk, server,
            concurrent: true, clock: () => now, lock: lock);
        final jobId = path == 'alta' ? job : 'trabajo-1';
        // A sube el adjunto y queda inactiva: su latido envejece más allá de
        // lo que B da por vivo.
        final pdf = await uploadAttachment(
            windowA, server, 'taller/$jobId/a.pdf',
            jobId: jobId);
        now = now.add(const Duration(minutes: 31));
        final gate = Completer<void>();
        final started = Completer<void>();
        server
          ..removeGate = gate
          ..removeStarted = started;
        // B barre: el borrado en Storage queda en camino, fuera del candado.
        final sweeping = windowB.sweepOrphanImages(_scope);
        await started.future;
        // A vuelve y guarda con ese adjunto.
        Object? refused;
        try {
          await windowA.submit(
            _scope,
            path == 'alta'
                ? _jobCreation(job, images: [pdf.publicUrl])
                : linesWithAttachments('lineas-1', [pdf.publicUrl]),
            followUps:
                path == 'alta' ? [_lines('lineas-1', jobId: job)] : const [],
          );
        } catch (error) {
          refused = error;
        }
        gate.complete();
        await sweeping;
        await windowA.resume(_scope);
        expect(server.storedImages, isNot(contains('taller/$jobId/a.pdf')));
        expect(server.brokenLinks, isEmpty,
            reason: 'ningún trabajo muestra un archivo borrado');
        expect(refused, isA<WorkshopImageUnavailableException>());
        expect(
          '$refused',
          'Un adjunto nuevo ya no está: se borró de este equipo porque la '
              'ventana estuvo inactiva mucho rato. No se guardó nada: vuelve a '
              'adjuntarlo y guarda.',
        );
        expect(server.appliedLog, isEmpty);
        expect(await windowA.pending(_scope), isEmpty,
            reason: 'el rechazo no respaldó nada');
      });
    }

    test(
        'un borrado que falla o que un cierre corta sigue marcado: nadie lo '
        'toma, y el próximo barrido lo termina, sea de quien sea', () async {
      final disk = _Disk();
      final server = _Server();
      var now = DateTime.utc(2026, 9, 29, 12);
      final windowA = _outbox(disk, server, concurrent: true, clock: () => now);
      final pdf = await uploadAttachment(windowA, server, 'taller/$job/a.pdf');
      now = now.add(const Duration(minutes: 31));
      server.removeFailure =
          const WorkshopCommandTransportException('sin red para Storage');
      await _outbox(disk, server, concurrent: true, clock: () => now)
          .sweepOrphanImages(_scope);
      expect(server.storedImages, contains('taller/$job/a.pdf'),
          reason: 'el borrado falló');
      // Reinicio: otra bandeja sobre el mismo disco. La ventana dueña vuelve
      // a latir, pero el archivo quizá ya no está: nadie lo toma.
      final restarted =
          _outbox(disk, server, concurrent: true, clock: () => now);
      await expectLater(
        restarted.submit(_scope, _jobCreation(job, images: [pdf.publicUrl])),
        throwsA(isA<WorkshopImageUnavailableException>()),
      );
      // La dueña vuelve a latir (anota otro adjunto).
      await windowA.recordImageIntent(
          _scope, attachment('taller/$job/otro.pdf'));
      server.removeFailure = null;
      await restarted.sweepOrphanImages(_scope);
      expect(server.storedImages, isNot(contains('taller/$job/a.pdf')),
          reason: 'el reintento lo borró aunque la dueña volvió');
      // Borrado: queda la lápida, que sigue rechazándolo y no cuenta.
      await expectLater(
        _outbox(disk, server, concurrent: true, clock: () => now)
            .submit(_scope, _jobCreation(job, images: [pdf.publicUrl])),
        throwsA(isA<WorkshopImageUnavailableException>()),
      );
      expect((await restarted.counts(_scope)).images, 1,
          reason: 'sólo el adjunto vivo de la dueña');
      expect(server.appliedLog, isEmpty);
    });

    test('la lápida dura removedImageMemory y después sale', () async {
      final disk = _Disk();
      final server = _Server();
      var now = DateTime.utc(2026, 9, 29, 12);
      final pdf = await uploadAttachment(
          _outbox(disk, server, concurrent: true, clock: () => now),
          server,
          'taller/$job/a.pdf');
      now = now.add(const Duration(minutes: 31));
      final outbox = _outbox(disk, server, concurrent: true, clock: () => now);
      await outbox.sweepOrphanImages(_scope);
      bool tombstone() => disk.values.entries.any((entry) =>
          entry.key.contains(':i:') && entry.value.contains('deleted_at'));
      expect(tombstone(), isTrue);
      now = now.add(
          WorkshopCommandOutbox.removedImageMemory - const Duration(hours: 1));
      await outbox.sweepOrphanImages(_scope);
      expect(tombstone(), isTrue, reason: 'dentro del plazo sigue');
      await expectLater(
        outbox.submit(_scope, _jobCreation(job, images: [pdf.publicUrl])),
        throwsA(isA<WorkshopImageUnavailableException>()),
      );
      now = now.add(const Duration(hours: 2));
      await outbox.sweepOrphanImages(_scope);
      expect(tombstone(), isFalse, reason: 'vencido, sale');
    });

    test(
        'lo que el trabajo ya muestra no se juzga; un adjunto de otro trabajo '
        'no entra', () async {
      final disk = _Disk();
      final server = _Server();
      final outbox = _outbox(disk, server);
      const shown = 'https://x/storage/v1/object/public/job-images/taller/'
          'trabajo-1/viejo.pdf';
      final nuevo = await uploadAttachment(
          outbox, server, 'taller/trabajo-1/nuevo.pdf',
          jobId: 'trabajo-1');
      final ajeno = await uploadAttachment(
          outbox, server, 'taller/trabajo-2/ajeno.pdf',
          jobId: 'trabajo-2');
      // Uno ajeno, de otro trabajo: no entra, y nada se respalda.
      await expectLater(
        outbox.submit(
            _scope,
            linesWithAttachments('lineas-ajeno', [shown, ajeno.publicUrl],
                seen: [shown])),
        throwsA(isA<WorkshopImageUnavailableException>()
            .having((error) => error.foreignUrls, 'ajenos', [ajeno.publicUrl])),
      );
      expect(await outbox.pending(_scope), isEmpty);
      // El que el trabajo ya muestra, con el nuevo suyo: entra y lo lleva.
      final run = await outbox.submit(
          _scope,
          linesWithAttachments('lineas-1', [shown, nuevo.publicUrl],
              seen: [shown]));
      expect(run.outcome, WorkshopCommandOutcome.committed);
      expect(server.shownUrls, containsAll([shown, nuevo.publicUrl]));
    });

    test(
        'el que el trabajo ya muestra no se rechaza aunque la bandeja lo '
        'recuerde borrado', () async {
      final disk = _Disk();
      final server = _Server();
      var now = DateTime.utc(2026, 9, 29, 12);
      final pdf = await uploadAttachment(
          _outbox(disk, server, concurrent: true, clock: () => now),
          server,
          'taller/trabajo-1/a.pdf',
          jobId: 'trabajo-1');
      now = now.add(const Duration(minutes: 31));
      final outbox = _outbox(disk, server, concurrent: true, clock: () => now);
      await outbox.sweepOrphanImages(_scope);
      // El formulario lo tiene como visto en el trabajo (otra vía lo dejó
      // ahí): no es nuevo y no se juzga; quitarlo tampoco se impide.
      final run = await outbox.submit(
          _scope,
          linesWithAttachments('lineas-1', [pdf.publicUrl],
              seen: [pdf.publicUrl]));
      expect(run.outcome, WorkshopCommandOutcome.committed);
      // Y la lápida no la toma ningún comando: sigue ahí.
      expect(
          disk.values.entries.where((entry) =>
              entry.key.contains(':i:') && entry.value.contains('deleted_at')),
          hasLength(1));
    });

    test('lo que va detrás también se juzga', () async {
      final disk = _Disk();
      final server = _Server();
      var now = DateTime.utc(2026, 9, 29, 12);
      final pdf = await uploadAttachment(
          _outbox(disk, server, concurrent: true, clock: () => now),
          server,
          'taller/$job/a.pdf');
      now = now.add(const Duration(minutes: 31));
      final outbox = _outbox(disk, server, concurrent: true, clock: () => now);
      await outbox.sweepOrphanImages(_scope);
      // El alta sin adjuntos y, detrás, un guardado que los agrega.
      await expectLater(
        outbox.submit(_scope, _jobCreation(job), followUps: [
          linesWithAttachments('lineas-1', [pdf.publicUrl], jobId: job),
        ]),
        throwsA(isA<WorkshopImageUnavailableException>()),
      );
      expect(await outbox.pending(_scope), isEmpty);
      expect(server.appliedLog, isEmpty);
    });

    group('revisión de Codex del barrido (2026-09-29)', () {
      test(
          'un corte entre el comando y su reclamo no deja el adjunto al '
          'barrido: lo protege el comando que lo lleva', () async {
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        var now = DateTime.utc(2026, 9, 29, 12);
        final windowA =
            _outbox(disk, server, concurrent: true, clock: () => now);
        final pdf =
            await uploadAttachment(windowA, server, 'taller/$job/a.pdf');
        // El comando alcanza a escribirse; el reclamo del adjunto, no.
        disk.failWriteAfter = 1;
        await expectLater(
          windowA.submit(_scope, _jobCreation(job, images: [pdf.publicUrl])),
          throwsA(isA<WorkshopOutboxPersistenceException>()),
        );
        disk.failWriteAfter = null;
        // Reinicio sin red, con la dueña ya sin latido: el barrido no lo
        // borra, y al volver la red el alta sale con su adjunto.
        now = now.add(const Duration(minutes: 31));
        final restarted =
            _outbox(disk, server, concurrent: true, clock: () => now);
        await restarted.sweepOrphanImages(_scope);
        expect(server.storedImages, contains('taller/$job/a.pdf'));
        server.networkUp = true;
        await restarted.resume(_scope);
        expect(server.appliedLog, ['job_create:$job']);
        expect(server.brokenLinks, isEmpty);
      });

      test(
          'dos pendientes con el mismo adjunto: sacar el que lo reclamó no lo '
          'deja sin dueño', () async {
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        var now = DateTime.utc(2026, 9, 29, 12);
        final outbox =
            _outbox(disk, server, concurrent: true, clock: () => now);
        final pdf = await uploadAttachment(
            outbox, server, 'taller/trabajo-1/a.pdf',
            jobId: 'trabajo-1');
        await outbox.enqueue(
            _scope, linesWithAttachments('lineas-1', [pdf.publicUrl]));
        // El segundo se lleva el reclamo, y se descarta.
        await outbox.enqueue(
            _scope,
            linesWithAttachments('lineas-2', [pdf.publicUrl],
                jobId: 'trabajo-1'));
        now = now.add(const Duration(minutes: 31));
        final other = _outbox(disk, server, concurrent: true, clock: () => now);
        await other.discard(_scope, 'lineas-2');
        await other.sweepOrphanImages(_scope);
        expect(server.storedImages, contains('taller/trabajo-1/a.pdf'),
            reason: 'lineas-1 sigue pendiente y lo lleva');
        server.networkUp = true;
        await other.resume(_scope);
        expect(server.appliedLog, ['job_line_save:lineas-1']);
        expect(server.brokenLinks, isEmpty);
      });

      test(
          'un comando que lleva un adjunto marcado sin candado compartido no '
          'se envía: sale rechazado con lo que lo seguía', () async {
        final disk = _Disk();
        final server = _Server()..networkUp = false;
        final outbox = _outbox(disk, server);
        final pdf = await uploadAttachment(outbox, server, 'taller/$job/a.pdf');
        await outbox.enqueue(_scope, _jobCreation(job, images: [pdf.publicUrl]),
            followUps: [_lines('lineas-1', jobId: job)]);
        // Otra pestaña sin Web Locks lo marcó encima del reclamo.
        final key = disk.values.keys.firstWhere((key) => key.contains(':i:'));
        disk.values[key] = jsonEncode({
          ...jsonDecode(disk.values[key]!) as Map<String, dynamic>,
          'operation_key': null,
          'deleting_at': '2026-09-29T12:31:00.000Z',
        });
        server.networkUp = true;
        final run = await _outbox(disk, server)
            .run(_scope, job, trigger: WorkshopCommandTrigger.retry);
        expect(run.outcome, WorkshopCommandOutcome.rejected);
        expect(run.error, isA<WorkshopImageUnavailableException>());
        expect(run.droppedFollowUps.map((command) => command.operationKey),
            ['lineas-1']);
        expect(server.sentKeys, isEmpty, reason: 'no salió nada');
        expect(await _outbox(disk, server).pending(_scope), isEmpty);
      });

      test(
          'sin Web Locks no se borra lo de otra sesión; lo de un formulario '
          'propio que se cerró, sí', () async {
        final disk = _Disk();
        final server = _Server();
        var now = DateTime.utc(2026, 9, 29, 12);
        await uploadAttachment(
            _outbox(disk, server, concurrent: true, clock: () => now),
            server,
            'taller/$job/de-otra.pdf');
        now = now.add(const Duration(minutes: 31));
        final tab = _outbox(disk, server,
            concurrent: true, clock: () => now, lock: _NoWebLocks());
        await uploadAttachment(tab, server, 'taller/$job/propio.pdf');
        await tab.sweepOrphanImages(_scope);
        expect(server.storedImages, contains('taller/$job/de-otra.pdf'),
            reason: 'sin candado compartido no se decide por otra pestaña');
        await tab.releaseImages(_scope, ownerForm: 'trabajo-form');
        expect(server.storedImages, isNot(contains('taller/$job/propio.pdf')));
      });

      test('no se descarta un comando que se está enviando', () async {
        final disk = _Disk();
        final server = _Server();
        final outbox = _outbox(disk, server);
        await outbox.enqueue(_scope, _lines('lineas-1'));
        Future<Object?>? discarding;
        server.duringSend = () {
          server.duringSend = null;
          // La misma bandeja de la app (`shared`), que es la que lo envía.
          discarding = outbox
              .discard(_scope, 'lineas-1')
              .then<Object?>((run) => run, onError: (Object error) => error);
        };
        final run = await outbox.run(_scope, 'lineas-1',
            trigger: WorkshopCommandTrigger.save);
        expect(await discarding, isA<WorkshopCommandBusyException>());
        expect(run.outcome, WorkshopCommandOutcome.committed);
      });

      test(
          'una subida que termina después de que el barrido la borró vuelve '
          'a borrarse, y nadie la toma', () async {
        final disk = _Disk();
        final server = _Server();
        var now = DateTime.utc(2026, 9, 29, 12);
        final windowA =
            _outbox(disk, server, concurrent: true, clock: () => now);
        // A anota el adjunto y la subida se demora: su latido envejece.
        final pdf = attachment('taller/$job/lento.pdf');
        await windowA.recordImageIntent(_scope, pdf);
        now = now.add(const Duration(minutes: 31));
        final windowB =
            _outbox(disk, server, concurrent: true, clock: () => now);
        await windowB.sweepOrphanImages(_scope);
        // La subida termina ahora: el archivo existe.
        server.storedImages.add('taller/$job/lento.pdf');
        await windowA.markImageUploaded(_scope, 'taller/$job/lento.pdf');
        await expectLater(
          windowA.submit(_scope, _jobCreation(job, images: [pdf.publicUrl])),
          throwsA(isA<WorkshopImageUnavailableException>()),
        );
        await windowB.resume(_scope);
        expect(server.storedImages, isNot(contains('taller/$job/lento.pdf')),
            reason: 'el archivo que llegó tarde no queda huérfano');
      });

      test(
          'un borrado que falló se reintenta en la reanudación, no sólo al '
          'abrir la sesión', () async {
        final disk = _Disk();
        final server = _Server();
        var now = DateTime.utc(2026, 9, 29, 12);
        await uploadAttachment(
            _outbox(disk, server, concurrent: true, clock: () => now),
            server,
            'taller/$job/a.pdf');
        now = now.add(const Duration(minutes: 31));
        final outbox =
            _outbox(disk, server, concurrent: true, clock: () => now);
        server.removeFailure =
            const WorkshopCommandTransportException('sin red para Storage');
        await outbox.sweepOrphanImages(_scope);
        expect(server.storedImages, contains('taller/$job/a.pdf'));
        server.removeFailure = null;
        await outbox.resume(_scope);
        expect(server.storedImages, isNot(contains('taller/$job/a.pdf')));
      });
    });
  });
}
