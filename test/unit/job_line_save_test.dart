import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bike_technical_fact_patch.dart';
import 'package:vinabike_erp/modules/bikeshop/services/job_line_save.dart';

MechanicJobItem _line({String? id, double unitPrice = 15000}) =>
    MechanicJobItem(
      id: id,
      tenantId: 'taller',
      jobId: 'trabajo-1',
      jobBikeId: 'bici-del-trabajo',
      productName: 'Revisión de frenos',
      quantity: 1,
      unitPrice: unitPrice,
      totalPrice: unitPrice,
      itemType: 'service',
      serviceConfigurationData: const {'brake_type': 'hydraulic_disc'},
    );

const _brakeFact = BikeTechnicalFact.set(
  key: 'brakeType',
  value: 'hydraulic_disc',
  expected: 'rim',
  expectedConfirmed: true,
);

Map<String, dynamic> _params({
  List<JobLineVersion>? seen,
  List<JobLineToSave>? lines,
  Map<String, List<BikeTechnicalFact>> facts = const {},
}) =>
    jobLineSaveParams(
      jobId: 'trabajo-1',
      seenLines: seen ?? const [],
      lines: lines ?? const [],
      bikeFacts: facts,
    );

void main() {
  group('el pedido', () {
    test('una línea guardada viaja con su id; una nueva, sólo con su llave',
        () {
      final params = _params(lines: [
        JobLineToSave(
          clientKey: 'linea-1',
          item: _line(id: 'linea-1'),
          persisted: true,
        ),
        JobLineToSave(
          clientKey: '1727530000000',
          item: _line(),
          persisted: false,
        ),
      ]);
      final lines = (params['p_lines'] as List).cast<Map<String, dynamic>>();
      expect(lines.first['id'], 'linea-1');
      expect(lines.last.containsKey('id'), isFalse);
      expect(lines.last['client_key'], '1727530000000');
      // El total, el taller, el trabajo y las fechas los pone la base.
      for (final key in [
        'total_price',
        'tenant_id',
        'job_id',
        'created_at',
        'updated_at',
      ]) {
        expect(lines.first.containsKey(key), isFalse, reason: key);
      }
      expect(lines.first['location_key'], 'none');
    });

    test('una línea nueva no manda tareas: su descripción es instrucción', () {
      final params = _params(lines: [
        JobLineToSave(clientKey: 'nueva', item: _line(), persisted: false),
      ]);
      final line = (params['p_lines'] as List).single as Map<String, dynamic>;
      // Ni la app ni la base crean tareas desde la descripción del catálogo
      // (20260929040000): antes lo hacían las dos y se repetían.
      expect(line.containsKey('auto_task_description'), isFalse);
    });

    test(
        'sin líneas no manda lo que vio: el trabajo con pago sólo va a la '
        'ficha', () {
      final params = jobLineSaveParams(
        jobId: 'trabajo-1',
        seenLines: null,
        lines: null,
        bikeFacts: const {
          'bici-1': [_brakeFact]
        },
      );
      expect(params['p_lines'], isNull);
      expect(params['p_seen_lines'], isNull);
      expect(
        () => jobLineSaveParams(
          jobId: 'trabajo-1',
          seenLines: const [],
          lines: null,
          bikeFacts: const {},
        ),
        throwsArgumentError,
      );
    });

    test('lo de la ficha va por bici y una bici sin datos no viaja', () {
      final params = _params(facts: const {
        'bici-b': [_brakeFact],
        'bici-a': [_brakeFact],
        'bici-sin-cambios': [],
      });
      final bikes = (params['p_bike_facts'] as List).cast<Map>();
      expect(bikes.map((bike) => bike['bike_id']), ['bici-a', 'bici-b']);
      expect(
        (bikes.first['facts'] as List).single,
        _brakeFact.toJson(),
      );
    });
  });

  test('lo que vio va ordenado y con la versión exacta del servidor', () {
    final params = _params(seen: [
      const JobLineVersion(
          id: 'b', version: '2026-09-28T10:00:00.123456+00:00'),
      const JobLineVersion(
          id: 'a', version: '2026-09-28T11:00:00.654321+00:00'),
    ]);
    // La versión viaja tal como la mandó el servidor, con sus microsegundos.
    expect(
      params['p_seen_lines'],
      [
        {'id': 'a', 'updated_at': '2026-09-28T11:00:00.654321+00:00'},
        {'id': 'b', 'updated_at': '2026-09-28T10:00:00.123456+00:00'},
      ],
    );
  });

  test('el recibo dice el id de cada línea nueva y la versión de todas', () {
    final result = JobLineSaveResult.fromJson({
      'operation_id': 'op-1',
      'replayed': true,
      'lines': [
        {
          'id': 'linea-nueva',
          'client_key': '1727530000000',
          'updated_at': '2026-09-28T13:52:59.311719+00:00',
        },
        {
          'id': 'linea-igual',
          'client_key': null,
          'updated_at': '2026-09-27T13:52:59.311719+00:00',
        },
      ],
      'bike_facts': const [],
      'tasks_created': 2,
    });
    expect(result.replayed, isTrue);
    expect(result.tasksCreated, 2);
    expect(result.lines!.first.clientKey, '1727530000000');
    expect(result.lines!.first.id, 'linea-nueva');
    expect(
      result.lines!.first.version,
      '2026-09-28T13:52:59.311719+00:00',
      reason: 'la versión vuelve exacta, al microsegundo, también en web',
    );
    expect(result.lines!.last.clientKey, isNull);
    expect(
      () => JobLineSaveResult.fromJson(const {'lines': []}),
      throwsFormatException,
      reason: 'sin recibo no se da por guardado',
    );
  });

  group('la factura en el mismo comando', () {
    test('se pide sólo cuando el guardado la deja al día', () {
      expect(_params().containsKey('p_invoice'), isFalse);
      expect(
        jobLineSaveParams(
          jobId: 'trabajo-1',
          seenLines: const [],
          lines: const [],
          bikeFacts: const {},
          invoice: true,
        )['p_invoice'],
        isTrue,
      );
    });

    test('el recibo dice qué hizo con la factura', () {
      final created = JobLineSaveResult.fromJson(const {
        'operation_id': 'op-1',
        'replayed': true,
        'bike_facts': [],
        'invoice': {'action': 'created', 'invoice_id': 'fv-1', 'error': null},
      });
      expect(created.invoice!.action, 'created');
      expect(created.invoice!.invoiceId, 'fv-1');
      expect(created.invoice!.failed, isFalse);

      final failed = JobLineSaveResult.fromJson(const {
        'operation_id': 'op-2',
        'replayed': false,
        'bike_facts': [],
        'invoice': {
          'action': 'failed',
          'invoice_id': null,
          'error': {'code': '23514', 'message': 'Falta la bicicleta'},
        },
      });
      expect(failed.invoice!.failed, isTrue);
      expect(failed.invoice!.errorMessage, 'Falta la bicicleta');
    });
  });

  group('las bicis del trabajo', () {
    MechanicJobBike jobBike({String? id, String? diagnosis}) => MechanicJobBike(
          id: id,
          tenantId: 'taller',
          jobId: 'trabajo-1',
          bikeId: 'bici-7',
          orderIndex: 1,
          statusId: 'estado-de-otro-dueño',
          diagnosis: diagnosis,
          requiresApproval: true,
          approvedAt: DateTime.utc(2026, 9, 1),
          imageUrls: const ['https://x/a.jpg'],
        );

    // Como la manda PostgREST al cargar.
    const seen = <String, dynamic>{
      'bike_id': 'bici-7',
      'order_index': 1,
      'diagnosis': 'Llega sin luz',
      'work_requested': null,
      'work_performed': null,
      'technician_notes': null,
      'diagnosis_sheet_key': null,
      'diagnosis_sheet_data': <String, dynamic>{},
      'diagnosis_sheet_updated_at': null,
      'is_warranty_work': false,
      'requires_approval': true,
      'approved_by_customer': false,
    };

    test('una nueva viaja con lo suyo y sus líneas la nombran por su llave',
        () {
      final params = jobLineSaveParams(
        jobId: 'trabajo-1',
        seenLines: const [],
        lines: [
          JobLineToSave(
            clientKey: 'luz',
            item: _line(),
            persisted: false,
            jobBikeKey: 'bici-7',
          ),
        ],
        bikeFacts: const {},
        jobBikes: [
          JobBikeToSave.added(
            clientKey: 'bici-7',
            jobBike: jobBike(diagnosis: 'Llega sin luz'),
          ),
        ],
      );
      final bike = (params['p_job_bikes'] as List).single as Map;
      expect(bike.containsKey('id'), isFalse,
          reason: 'la nueva toma su id en el comando');
      expect(
        mechanicJobBikeFormColumns
            .containsAll(bike.keys.where((key) => key != 'client_key')),
        isTrue,
        reason: 'el estado, las fotos, la fecha de aprobación, el taller y '
            'el trabajo no los escribe el formulario',
      );
      expect(bike['diagnosis'], 'Llega sin luz');
      final line = (params['p_lines'] as List).single as Map;
      expect(line['job_bike_key'], 'bici-7');
      expect(line.containsKey('job_bike_id'), isFalse);
    });

    test('de una que estaba, sólo lo que cambió y con lo que se vio', () {
      expect(
        JobBikeToSave.changed(
          clientKey: 'bici-7',
          jobBike: jobBike(id: 'jb-7', diagnosis: 'Llega sin luz'),
          seen: seen,
        ),
        isNull,
        reason: 'sin cambios no viaja; la hoja vacía {} es la misma',
      );
      final changed = JobBikeToSave.changed(
        clientKey: 'bici-7',
        jobBike: jobBike(id: 'jb-7', diagnosis: 'Cable cortado'),
        seen: seen,
      )!
          .toJson();
      expect(changed, {
        'client_key': 'bici-7',
        'id': 'jb-7',
        'bike_id': 'bici-7',
        'diagnosis': 'Cable cortado',
        'expected': {'diagnosis': 'Llega sin luz'},
      });
    });

    test('la que el formulario quitó sale con lo que se vio de ella', () {
      final removed = JobBikeToSave.removed(
        clientKey: 'sale-jb-8',
        jobBikeId: 'jb-8',
        bikeId: 'bici-8',
        seen: seen,
      ).toJson();
      expect(removed['remove'], isTrue);
      expect(removed['id'], 'jb-8');
      expect(removed['expected'], {...seen}..remove('bike_id'),
          reason: 'si otro la cambió desde que se cargó, no se borra');
    });

    test('el recibo dice qué id tomó cada bici y lo que quedó', () {
      final result = JobLineSaveResult.fromJson({
        'operation_id': 'op-1',
        'replayed': false,
        'lines': const [],
        'bike_facts': const [],
        'job_bikes': [
          {
            'id': 'jb-nueva',
            'client_key': 'bici-7',
            'bike_id': 'bici-7',
            'row': {'diagnosis': 'Llega sin luz'},
          },
        ],
      });
      expect(result.jobBikes!.single.id, 'jb-nueva');
      expect(result.jobBikes!.single.bikeId, 'bici-7');
      expect(result.jobBikes!.single.row['diagnosis'], 'Llega sin luz');
      expect(
        JobLineSaveResult.fromJson(const {
          'operation_id': 'op-2',
          'replayed': false,
          'bike_facts': [],
        }).jobBikes,
        isNull,
        reason: 'un guardado sin bicis no las toca',
      );
    });

    test('otra persona agregó, quitó o cambió una bici: nada se guardó', () {
      final error = classifyJobLineSaveError(const PostgrestException(
        message: 'Otra persona cambió una bici',
        code: 'PT409',
        details: '[{"job_bike_id": "jb-8", "field": "diagnosis"}]',
        hint: 'job_bikes_changed',
      ));
      expect(error, isA<JobBikesChangedException>());
      expect(error.toString(), contains('no se guardó nada'));
    });
  });

  group('la cabecera', () {
    // Como la manda PostgREST: fecha con microsegundos, números de numeric.
    const seen = {
      'diagnosis': 'Frenos sin fuerza',
      'priority': 'NORMAL',
      'arrival_date': '2026-09-27T10:00:00.123456+00:00',
      'deadline': null,
      'estimated_duration_hours': 1.5,
      'discount_amount': 0,
      'image_urls': ['https://x/a.jpg'],
    };

    test('lo que sólo cambia de forma no viaja', () {
      final patch = jobHeaderPatch(seen: seen, edited: {
        'diagnosis': 'Frenos sin fuerza',
        'priority': 'NORMAL',
        // En web, un DateTime pierde los microsegundos.
        'arrival_date': '2026-09-27T10:00:00.123Z',
        'deadline': null,
        'estimated_duration_hours': 1.50,
        'discount_amount': 0.0,
        'image_urls': ['https://x/a.jpg'],
        // Lo que el formulario no edita no se manda aunque venga distinto.
        'invoice_id': 'otra',
        'final_cost': 0,
      });
      expect(patch, isEmpty);
    });

    test('lo que cambió viaja con el valor que mandó el servidor', () {
      final patch = jobHeaderPatch(seen: seen, edited: {
        ...seen,
        'diagnosis': 'Pastillas cristalizadas',
        'discount_amount': 1000.0,
      });
      expect(patch, {
        'diagnosis': {
          'value': 'Pastillas cristalizadas',
          'expected': 'Frenos sin fuerza',
        },
        'discount_amount': {'value': 1000.0, 'expected': 0},
      });
      expect(
        jobLineSaveParams(
          jobId: 'trabajo-1',
          seenLines: null,
          lines: null,
          bikeFacts: const {},
          header: patch,
        )['p_header'],
        patch,
      );
    });

    test(
        'con bicis, lo editado se mide contra lo que mostró el formulario, '
        'no contra la cabecera', () {
      // La cabecera dice una cosa y la primera bici, que es lo que se ve,
      // otra (o nada: 20 trabajos así en producción al 2026-09-28).
      const shown = {'diagnosis': null, 'client_request': 'Frena mal'};
      const header = {
        'diagnosis': 'Escrito desde la tabla',
        'client_request': 'Revisar frenos',
      };
      expect(
        jobHeaderPatch(
          seen: header,
          shown: shown,
          edited: const {'diagnosis': null, 'client_request': 'Frena mal'},
        ),
        isEmpty,
        reason: 'sin tocarlos, no borra el diagnóstico ni choca con quien '
            'lo escribió',
      );
      expect(
        jobHeaderPatch(
          seen: header,
          shown: shown,
          edited: const {
            'diagnosis': 'Pastillas gastadas',
            'client_request': 'Frena mal',
          },
        ),
        {
          'diagnosis': {
            'value': 'Pastillas gastadas',
            'expected': 'Escrito desde la tabla',
          },
        },
        reason: 'editado, compara con lo que mandó el servidor',
      );
    });

    test('un campo que el servidor no mandó no se toca', () {
      expect(
        jobHeaderPatch(seen: const {}, edited: const {'diagnosis': 'x'}),
        isEmpty,
      );
    });

    test('sin cambios la cabecera no viaja', () {
      expect(_params()['p_header'], isNull);
    });

    test('otra persona cambió un campo: dice cuál, en palabras del taller', () {
      final error = classifyJobLineSaveError(const PostgrestException(
        message: 'Otra persona cambió la cabecera',
        code: 'PT409',
        hint: 'job_header_changed',
        details: '["diagnosis", "priority"]',
      ));
      expect(error, isA<JobHeaderChangedException>());
      expect((error as JobHeaderChangedException).fields,
          ['diagnosis', 'priority']);
      expect(error.toString(), contains('el diagnóstico, la prioridad'));
    });

    test('el recibo trae la cabecera que quedó', () {
      final result = JobLineSaveResult.fromJson(const {
        'operation_id': 'op-1',
        'replayed': false,
        'header': {'diagnosis': 'Pastillas cristalizadas'},
        'bike_facts': [],
      });
      expect(result.header, {'diagnosis': 'Pastillas cristalizadas'});
    });
  });

  group('los errores', () {
    test('otro cambió las líneas: nada se guardó y se dice cuántas', () {
      final error = classifyJobLineSaveError(const PostgrestException(
        message: 'Las líneas del trabajo cambiaron mientras lo editabas',
        code: 'PT409',
        hint: 'job_lines_changed',
        details:
            '[{"line_id": "a", "reason": "changed"}, {"line_id": "b", "reason": "added"}]',
      ));
      expect(error, isA<JobLinesChangedException>());
      final changed = error as JobLinesChangedException;
      expect(changed.lines.map((line) => line.reason), ['changed', 'added']);
      expect(changed.toString(), contains('2 líneas'));
    });

    test('la ficha de una bici cambió: dice cuál y qué claves', () {
      final error = classifyJobLineSaveError(const PostgrestException(
        message: 'Bicycle facts changed since they were loaded',
        code: 'PT409',
        hint: 'bike_facts:bici-1',
        details: '[{"key": "brakeType", "expected": "rim", "current": "x"}]',
      ));
      expect(error, isA<JobLineSaveBikeFactException>());
      final bikeFact = error as JobLineSaveBikeFactException;
      expect(bikeFact.bikeId, 'bici-1');
      expect(bikeFact.cause, isA<BikeTechnicalFactConflict>());
      expect((bikeFact.cause as BikeTechnicalFactConflict).keys, ['brakeType']);
    });

    test('la ficha rechaza el dato: es un rechazo, no un conflicto', () {
      final error = classifyJobLineSaveError(const PostgrestException(
        message: 'Bicycle fact brakeType has an unknown value',
        code: 'P0001',
        hint: 'bike_facts:bici-1',
      ));
      expect(
        (error as JobLineSaveBikeFactException).cause,
        isA<BikeTechnicalFactRejected>(),
      );
    });

    test('un error pasajero no descarta lo de Configurar', () {
      // El servidor ya no le pone la pista; si llegara con ella, igual no es
      // un rechazo de la ficha.
      const deadlock = PostgrestException(
        message: 'deadlock detected',
        code: '40P01',
        hint: 'bike_facts:bici-1',
      );
      expect(classifyJobLineSaveError(deadlock), same(deadlock));
    });

    test('lo demás sigue siendo el error del servidor', () {
      const other = PostgrestException(
        message: 'La línea «X» no se guardó: no dice qué rueda armó.',
        code: '23514',
      );
      expect(classifyJobLineSaveError(other), same(other));
    });
  });
}
