import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/catalog_name_reading.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_spec_extraction.dart';

const _compuesto = SupplierNeedSearchField(
  key: 'compound_type',
  label: 'Compuesto',
  dataType: 'single_select',
  allowedValues: <Object>['Metálico', 'Orgánico', 'Semi-Metálico'],
);
const _aletas = SupplierNeedSearchField(
  key: 'pad_finned',
  label: 'Con Aletas de Calor',
  dataType: 'boolean',
);

/// Un servidor de mentira que **acepta todo**. Sirve para probar que el filtro
/// del cliente ya mata lo que tiene que matar, sin apoyarse en el del servidor.
List<Map<String, Object?>> _guardados = <Map<String, Object?>>[];

Future<Map<String, Object?>> _servidorPermisivo({
  required String productId,
  required String fieldKey,
  required Object value,
  required String quote,
}) async {
  _guardados.add(<String, Object?>{
    'productId': productId,
    'field': fieldKey,
    'value': value,
    'quote': quote,
  });
  return <String, Object?>{'verdict': 'recorded'};
}

SupplierSpecExtractor _modeloQueResponde(Object? respuesta) =>
    (_) async => respuesta is String ? respuesta : jsonEncode(respuesta);

void main() {
  setUp(() {
    _guardados = <Map<String, Object?>>[];
    resetSupplierSpecReadingsCache();
  });

  test('una cita que dice lo contrario no se ofrece siquiera', () async {
    // Lo que el cliente SÍ puede desmentir por su cuenta, lo mata acá. El
    // lector del booleano vive en la capa baja y lo usan las dos orillas: una
    // fila que dice `SIN ALETAS DE CALOR` no sostiene `aletas = true`, y eso
    // no depende de ningún servidor.
    final resultado = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_aletas],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno Organica SIN ALETAS DE CALOR',
          missingFields: <String>{'pad_finned'},
        ),
      ],
      extractor: _modeloQueResponde(<String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'pad_finned',
                'value': true,
                'quote': 'SIN ALETAS DE CALOR',
              },
            ],
          },
        ],
      }),
      recorder: _servidorPermisivo,
    );
    expect(_guardados, isEmpty,
        reason: 'ni con un servidor que acepta todo: la cita se relee y dice '
            'lo contrario del valor');
    expect(resultado.recorded, 0);
  });

  test('la salida adversarial se ofrece tal cual y la juzga el servidor',
      () async {
    // `METALICA` está en el nombre y es una cita real; lo que el modelo hizo
    // mal fue normalizarla al valor opuesto. Ningún lector del cliente lee
    // `Orgánico` ni `Metálico` en esa palabra —el español flexiona el final—,
    // así que el cliente no puede desmentirla y **no le corresponde**: la
    // ofrece sin tocarla, con su cita, y el dueño de la frontera es el
    // servidor, que compara contra el vocabulario que declara la ficha.
    // Que ahí muere está probado en `spec_name_reading_evidence.sql`.
    var ofrecida = <String, Object?>{};
    final resultado = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno Shimano METALICA J04C Con Disipador',
          missingFields: <String>{'compound_type'},
        ),
      ],
      extractor: _modeloQueResponde(<String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'compound_type',
                'value': 'Orgánico',
                'quote': 'METALICA',
              },
            ],
          },
        ],
      }),
      recorder: ({
        required String productId,
        required String fieldKey,
        required Object value,
        required String quote,
      }) async {
        ofrecida = <String, Object?>{'value': value, 'quote': quote};
        return <String, Object?>{
          'verdict': 'rejected',
          'reason': 'la cita no dice ese valor',
        };
      },
    );
    expect(ofrecida['value'], 'Orgánico',
        reason: 'el cliente no maquilla la lectura antes de mandarla: el '
            'servidor tiene que ver exactamente lo que el modelo dijo');
    expect(ofrecida['quote'], 'METALICA');
    expect(resultado.recorded, 0);
    expect(resultado.changedSomething, isFalse);
    expect(resultado.rejectedByServer.single, contains('no dice ese valor'));
  });

  test('la misma cita sí sostiene su propio valor', () async {
    await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno Shimano METALICA J04C',
          missingFields: <String>{'compound_type'},
        ),
      ],
      extractor: _modeloQueResponde(<String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'compound_type',
                'value': 'Metálico',
                'quote': 'METALICA',
              },
            ],
          },
        ],
      }),
      recorder: _servidorPermisivo,
    );
    expect(_guardados, hasLength(1));
    expect(_guardados.single['value'], 'Metálico');
    expect(_guardados.single['quote'], 'METALICA');
  });

  test('una cita inventada no llega al servidor', () async {
    await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno Shimano J04C',
          missingFields: <String>{'compound_type'},
        ),
      ],
      extractor: _modeloQueResponde(<String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'compound_type',
                'value': 'Metálico',
                'quote': 'COMPUESTO METALICO',
              },
            ],
          },
        ],
      }),
      recorder: _servidorPermisivo,
    );
    expect(_guardados, isEmpty);
  });

  test('sólo se pregunta por los campos que a esa fila le faltan', () async {
    var promptRecibido = '';
    await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto, _aletas],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno METALICA',
          missingFields: <String>{'compound_type'},
        ),
      ],
      extractor: (prompt) async {
        promptRecibido = prompt;
        return jsonEncode(<String, Object?>{'rows': <Object?>[]});
      },
      recorder: _servidorPermisivo,
    );
    expect(promptRecibido, contains('compound_type'));
    expect(promptRecibido, isNot(contains('pad_finned')),
        reason: 'una ficha que ya existe manda sobre la lectura: preguntar por '
            'ella gasta la llamada en algo que el servidor va a descartar');
  });

  test('un rechazo del servidor se reporta y no cuenta como guardado',
      () async {
    final resultado = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno METALICA',
          missingFields: <String>{'compound_type'},
        ),
      ],
      extractor: _modeloQueResponde(<String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'compound_type',
                'value': 'Metálico',
                'quote': 'METALICA',
              },
            ],
          },
        ],
      }),
      recorder: ({
        required String productId,
        required String fieldKey,
        required Object value,
        required String quote,
      }) async =>
          <String, Object?>{
        'verdict': 'rejected',
        'reason': 'la cita describe mejor otro valor del campo',
      },
    );
    expect(resultado.recorded, 0);
    expect(resultado.changedSomething, isFalse,
        reason: 'sin nada guardado no hay por qué recargar la pantalla');
    expect(resultado.rejectedByServer.single,
        contains('la cita describe mejor otro valor'));
  });

  test('el modelo caído deja la fila sin verificar y lo dice', () async {
    final resultado = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno METALICA',
          missingFields: <String>{'compound_type'},
        ),
      ],
      extractor: (_) async => throw StateError('sin cuota'),
      recorder: _servidorPermisivo,
    );
    expect(_guardados, isEmpty);
    expect(resultado.modelUnavailable, isTrue);
    expect(resultado.changedSomething, isFalse);
  });

  test('un dueño cerrado no arranca la lectura', () async {
    final owner = SupplierModelReadOwner();
    cancelSupplierModelReadDeadlines(owner: owner);
    var llamadas = 0;
    final resultado = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno METALICA',
          missingFields: <String>{'compound_type'},
        ),
      ],
      extractor: (_) async {
        llamadas += 1;
        return '{}';
      },
      owner: owner,
      recorder: _servidorPermisivo,
    );
    expect(llamadas, 0);
    expect(resultado.modelUnavailable, isTrue);
  });

  test('el lote se acota: una necesidad grande no dispara un prompt enorme',
      () async {
    var filasEnElPrompt = 0;
    await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: <CatalogRowToRead>[
        for (var i = 0; i < 120; i += 1)
          CatalogRowToRead(
            productId: 'p$i',
            text: 'Pastilla Freno METALICA $i',
            missingFields: const <String>{'compound_type'},
          ),
      ],
      extractor: (prompt) async {
        filasEnElPrompt = RegExp('"id": "p[0-9]+"').allMatches(prompt).length;
        return jsonEncode(<String, Object?>{'rows': <Object?>[]});
      },
      recorder: _servidorPermisivo,
    );
    expect(filasEnElPrompt, kCatalogNameReadingRowCap);
  });

  test('cambiar de necesidad mientras el modelo responde no escribe nada',
      () async {
    // El dueño sólo se cierra en el `dispose`, así que no alcanza: la pantalla
    // sigue viva y la pregunta ya es otra. Se comprueba pegado a la escritura.
    var vigente = true;
    final resultado = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno METALICA',
          missingFields: <String>{'compound_type'},
        ),
      ],
      extractor: (_) async {
        // El operador cambió de necesidad mientras el modelo pensaba.
        vigente = false;
        return jsonEncode(<String, Object?>{
          'rows': <Object?>[
            <String, Object?>{
              'id': 'p1',
              'facts': <Object?>[
                <String, Object?>{
                  'field': 'compound_type',
                  'value': 'Metálico',
                  'quote': 'METALICA',
                },
              ],
            },
          ],
        });
      },
      stillCurrent: () => vigente,
      recorder: _servidorPermisivo,
    );
    expect(_guardados, isEmpty,
        reason: 'la lectura llegó tarde: escribirla tocaría productos que ya '
            'nadie está mirando, con los campos de otra pregunta');
    expect(resultado.recorded, 0);
  });

  test('la escritura tiene su propio tope, además del tope del prompt',
      () async {
    // Cuarenta filas por tres campos son ciento veinte viajes al servidor
    // detrás de una pantalla ya montada.
    final filas = <CatalogRowToRead>[
      for (var i = 0; i < 30; i += 1)
        CatalogRowToRead(
          productId: 'p$i',
          text: 'Pastilla Freno METALICA $i',
          missingFields: const <String>{'compound_type'},
        ),
    ];
    final resultado = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: filas,
      recordCap: 5,
      extractor: _modeloQueResponde(<String, Object?>{
        'rows': <Object?>[
          for (var i = 0; i < 30; i += 1)
            <String, Object?>{
              'id': 'p$i',
              'facts': <Object?>[
                <String, Object?>{
                  'field': 'compound_type',
                  'value': 'Metálico',
                  'quote': 'METALICA',
                },
              ],
            },
        ],
      }),
      recorder: _servidorPermisivo,
    );
    expect(_guardados, hasLength(5));
    expect(resultado.recorded, 5,
        reason: 'lo que no entró en esta pasada entra en la siguiente: la '
            'llave de la lectura la calculan los huecos que quedan');
  });

  test('una RPC colgada no se come el presupuesto entero', () async {
    // El presupuesto es del conjunto. Comprobarlo sólo antes del `await`
    // dejaba que una sola llamada sin respuesta lo consumiera completo y
    // siguiera corriendo detrás de una pantalla que el operador ya usa.
    final reloj = Stopwatch()..start();
    final resultado = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno METALICA',
          missingFields: <String>{'compound_type'},
        ),
      ],
      recordBudget: const Duration(milliseconds: 300),
      extractor: _modeloQueResponde(<String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'compound_type',
                'value': 'Metálico',
                'quote': 'METALICA',
              },
            ],
          },
        ],
      }),
      recorder: ({
        required String productId,
        required String fieldKey,
        required Object value,
        required String quote,
      }) =>
          Completer<Map<String, Object?>>().future,
      // Un servidor que nunca contesta.
    );
    reloj.stop();
    expect(reloj.elapsed, lessThan(const Duration(seconds: 3)),
        reason: 'la llamada se corta con lo que queda del presupuesto');
    expect(resultado.recorded, 0);
    expect(resultado.failures, hasLength(1),
        reason: 'no hubo veredicto: es un fallo, no un rechazo');
    expect(resultado.retryable, isTrue);
  });

  test('un fallo se puede reintentar; un rechazo no', () async {
    final ofrecidos = <String>{};
    Future<Map<String, Object?>> lector({
      required String productId,
      required String fieldKey,
      required Object value,
      required String quote,
    }) async =>
        <String, Object?>{
          'verdict': 'rejected',
          'reason': 'la cita no dice ese valor',
        };
    final rechazada = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno METALICA',
          missingFields: <String>{'compound_type'},
        ),
      ],
      alreadyOffered: ofrecidos,
      extractor: _modeloQueResponde(<String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'compound_type',
                'value': 'Metálico',
                'quote': 'METALICA',
              },
            ],
          },
        ],
      }),
      recorder: lector,
    );
    expect(rechazada.retryable, isFalse,
        reason: 'la misma cita y el mismo valor dan el mismo veredicto');
    expect(ofrecidos, contains('p1|compound_type'),
        reason: 'lo rechazado queda marcado y no se vuelve a ofrecer');
  });

  test('el corte continúa por donde quedó, sin repetir el primer bloque',
      () async {
    // Sesenta rechazos seguidos no guardan nada: sin continuidad, nadie
    // recarga y las lecturas válidas de más atrás no se alcanzan nunca.
    final ofrecidos = <String>{};
    final pedidos = <String>[];
    final filas = <CatalogRowToRead>[
      for (var i = 0; i < 6; i += 1)
        CatalogRowToRead(
          productId: 'p$i',
          text: 'Pastilla Freno METALICA $i',
          missingFields: const <String>{'compound_type'},
        ),
    ];
    final respuesta = <String, Object?>{
      'rows': <Object?>[
        for (var i = 0; i < 6; i += 1)
          <String, Object?>{
            'id': 'p$i',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'compound_type',
                'value': 'Metálico',
                'quote': 'METALICA',
              },
            ],
          },
      ],
    };
    Future<Map<String, Object?>> lector({
      required String productId,
      required String fieldKey,
      required Object value,
      required String quote,
    }) async {
      pedidos.add(productId);
      // Todos rechazados: nada que guardar, nada que recargar.
      return <String, Object?>{'verdict': 'rejected', 'reason': 'no'};
    }

    final primera = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: filas,
      recordCap: 2,
      alreadyOffered: ofrecidos,
      extractor: _modeloQueResponde(respuesta),
      recorder: lector,
    );
    expect(primera.recorded, 0);
    expect(primera.hasMoreToOffer, isTrue,
        reason: 'la pasada se cortó con lecturas todavía sin ofrecer');
    expect(pedidos, hasLength(2));

    resetSupplierSpecReadingsCache();
    final segunda = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: filas,
      recordCap: 2,
      alreadyOffered: ofrecidos,
      extractor: _modeloQueResponde(respuesta),
      recorder: lector,
    );
    expect(segunda.hasMoreToOffer, isTrue);
    expect(pedidos.toSet(), hasLength(4),
        reason: 'la segunda vuelta avanza en vez de repetir el primer bloque');
  });

  test('las filas más allá del tope del lote cuentan como trabajo pendiente',
      () async {
    // `take(rowCap)` las deja fuera del `result`, así que sin contarlas una
    // primera tanda de puros rechazos terminaba con `cutShort = false` y la
    // fila 41 no se miraba nunca — aunque fuera la única lectura válida.
    final ofrecidos = <String>{};
    final filas = <CatalogRowToRead>[
      for (var i = 0; i < 3; i += 1)
        CatalogRowToRead(
          productId: 'malo$i',
          text: 'Pastilla Freno METALICA $i',
          missingFields: const <String>{'compound_type'},
        ),
      const CatalogRowToRead(
        productId: 'bueno',
        text: 'Pastilla Freno METALICA buena',
        missingFields: <String>{'compound_type'},
      ),
    ];
    Map<String, Object?> respuestaPara(Iterable<String> ids) =>
        <String, Object?>{
          'rows': <Object?>[
            for (final id in ids)
              <String, Object?>{
                'id': id,
                'facts': <Object?>[
                  <String, Object?>{
                    'field': 'compound_type',
                    'value': 'Metálico',
                    'quote': 'METALICA',
                  },
                ],
              },
          ],
        };

    final primera = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: filas,
      rowCap: 3,
      alreadyOffered: ofrecidos,
      extractor: _modeloQueResponde(
          respuestaPara(<String>['malo0', 'malo1', 'malo2'])),
      recorder: ({
        required String productId,
        required String fieldKey,
        required Object value,
        required String quote,
      }) async =>
          <String, Object?>{'verdict': 'rejected', 'reason': 'no'},
    );
    expect(primera.recorded, 0);
    expect(primera.hasMoreToOffer, isTrue,
        reason: 'la fila que quedó fuera del lote es trabajo pendiente');

    resetSupplierSpecReadingsCache();
    final segunda = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: filas,
      rowCap: 3,
      alreadyOffered: ofrecidos,
      extractor: _modeloQueResponde(respuestaPara(<String>['bueno'])),
      recorder: _servidorPermisivo,
    );
    expect(segunda.recorded, 1,
        reason: 'la segunda vuelta sí llega a la fila que quedó fuera');
    expect(_guardados.single['productId'], 'bueno');
    expect(segunda.hasMoreToOffer, isFalse,
        reason: 'agotado el conjunto, la cadena se detiene sola');
  });

  test('el silencio del modelo también marca el lote, o la cadena no avanza',
      () async {
    // Un campo del que el modelo no dijo nada da la misma respuesta si se le
    // vuelve a preguntar con el mismo texto. Sin marcarlo, cada vuelta repetía
    // el mismo lote para siempre.
    final ofrecidos = <String>{};
    await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'mudo',
          text: 'Pastilla Freno sin nada que leer',
          missingFields: <String>{'compound_type'},
        ),
      ],
      alreadyOffered: ofrecidos,
      extractor: _modeloQueResponde(<String, Object?>{'rows': <Object?>[]}),
      recorder: _servidorPermisivo,
    );
    expect(ofrecidos, contains('mudo|compound_type'));
  });

  test('en ensayo se recorre todo el circuito y no se escribe nada', () async {
    // Verificar esta pantalla en la app real no puede dejar hechos de prueba
    // mezclados con los del taller.
    final resultado = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno METALICA',
          missingFields: <String>{'compound_type'},
        ),
      ],
      dryRun: true,
      extractor: _modeloQueResponde(<String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'compound_type',
                'value': 'Metálico',
                'quote': 'METALICA',
              },
            ],
          },
        ],
      }),
      recorder: _servidorPermisivo,
    );
    expect(_guardados, isEmpty, reason: 'la RPC no se llama en ensayo');
    expect(resultado.recorded, 0);
    expect(resultado.wouldOffer, 1,
        reason: 'se cuenta lo que se habría OFRECIDO, no lo que el servidor '
            'habría guardado: en ensayo nadie lo juzgó');
    expect(resultado.changedSomething, isFalse,
        reason: 'y por lo tanto no dispara ninguna recarga');
  });

  test('un fallo no gasta presupuesto; un veredicto sí', () async {
    // El presupuesto acota el trabajo útil: cuántos hechos alcanzan a
    // someterse al juicio del servidor. Una llamada que nunca obtuvo veredicto
    // no gastó nada de eso, y además detiene la cadena por sí sola.
    final conVeredicto = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno METALICA',
          missingFields: <String>{'compound_type'},
        ),
      ],
      extractor: _modeloQueResponde(<String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'compound_type',
                'value': 'Metálico',
                'quote': 'METALICA',
              },
            ],
          },
        ],
      }),
      recorder: ({
        required String productId,
        required String fieldKey,
        required Object value,
        required String quote,
      }) async =>
          <String, Object?>{'verdict': 'rejected', 'reason': 'no'},
    );
    expect(conVeredicto.attemptsSpent, 1);

    resetSupplierSpecReadingsCache();
    final conFallo = await readCatalogNamesIntoFicha(
      fields: const <SupplierNeedSearchField>[_compuesto],
      rows: const <CatalogRowToRead>[
        CatalogRowToRead(
          productId: 'p1',
          text: 'Pastilla Freno METALICA',
          missingFields: <String>{'compound_type'},
        ),
      ],
      extractor: _modeloQueResponde(<String, Object?>{
        'rows': <Object?>[
          <String, Object?>{
            'id': 'p1',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'compound_type',
                'value': 'Metálico',
                'quote': 'METALICA',
              },
            ],
          },
        ],
      }),
      recorder: ({
        required String productId,
        required String fieldKey,
        required Object value,
        required String quote,
      }) async =>
          throw StateError('la red se cayó'),
    );
    expect(conFallo.attemptsSpent, 0,
        reason: 'una caída transitoria no puede quemar capacidad útil');
    expect(conFallo.retryable, isTrue,
        reason: 'y detiene la cadena, así que tampoco da vueltas gratis');
  });

  test('el presupuesto es de la cadena entera, no de cada vuelta', () async {
    // Sesenta por pasada y cuatro pasadas son doscientas cuarenta llamadas
    // automáticas donde se prometieron sesenta. Se descuenta lo gastado.
    final ofrecidos = <String>{};
    var presupuesto = 4;
    var llamadas = 0;
    final filas = <CatalogRowToRead>[
      for (var i = 0; i < 10; i += 1)
        CatalogRowToRead(
          productId: 'p$i',
          text: 'Pastilla Freno METALICA $i',
          missingFields: const <String>{'compound_type'},
        ),
    ];
    final respuesta = <String, Object?>{
      'rows': <Object?>[
        for (var i = 0; i < 10; i += 1)
          <String, Object?>{
            'id': 'p$i',
            'facts': <Object?>[
              <String, Object?>{
                'field': 'compound_type',
                'value': 'Metálico',
                'quote': 'METALICA',
              },
            ],
          },
      ],
    };

    var vueltas = 0;
    while (presupuesto > 0 && vueltas < 10) {
      vueltas += 1;
      resetSupplierSpecReadingsCache();
      final pasada = await readCatalogNamesIntoFicha(
        fields: const <SupplierNeedSearchField>[_compuesto],
        rows: filas,
        recordCap: presupuesto,
        alreadyOffered: ofrecidos,
        extractor: _modeloQueResponde(respuesta),
        recorder: ({
          required String productId,
          required String fieldKey,
          required Object value,
          required String quote,
        }) async {
          llamadas += 1;
          return <String, Object?>{'verdict': 'rejected', 'reason': 'no'};
        },
      );
      presupuesto -= pasada.attemptsSpent;
      if (!pasada.hasMoreToOffer) break;
    }
    expect(llamadas, 4,
        reason: 'la cadena entera gasta el presupuesto una sola vez');
    expect(presupuesto, 0);
  });

  // ─────────────────────────────────────────────────────────────────────────
  // La regla del booleano vive en dos lenguajes y tiene que decir lo mismo.
  //
  // El servidor no puede delegar su compuerta en el cliente, así que la misma
  // regla existe en SQL —`spec_boolean_from_field_vocabulary_internal_v1`— y
  // acá. Esta tabla es el amarre: los mismos casos se afirman en
  // `supabase/tests/spec_name_reading_evidence.sql`. Si una implementación
  // cambia sin la otra, uno de los dos lados se cae.
  // ─────────────────────────────────────────────────────────────────────────
  group('el booleano se lee igual en las dos orillas', () {
    const casos = <String, bool?>{
      'CON ALETAS DE CALOR': true,
      'CON ALETAS': true,
      'SIN ALETAS DE CALOR': false,
      'SIN ALETAS': false,
      'CON DISIPADOR': null,
      'Pastilla Freno Organica': null,
    };
    casos.forEach((texto, esperado) {
      test('«$texto» → $esperado', () {
        expect(
          supplierBooleanFromFieldVocabulary(
            text: texto,
            label: 'Con Aletas de Calor',
          ),
          esperado,
        );
      });
    });
  });
}
