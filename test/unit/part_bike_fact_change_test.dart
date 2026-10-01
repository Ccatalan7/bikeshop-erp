import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/config/brake_canonical_data.dart';
import 'package:vinabike_erp/modules/bikeshop/config/drivetrain_canonical_data.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/job_form_lines.dart';
import 'package:vinabike_erp/modules/bikeshop/services/part_bike_fact_change.dart';
import 'package:vinabike_erp/modules/bikeshop/services/wheel_service_facts.dart';

// Las filas de `bike_fact_spec_links` como las entrega PostgREST
// (20260928100000).
final _links = [
  for (final row in const [
    {
      'spec_key': 'rotor_diameter_mm_value',
      'position': 'front',
      'bike_fact_key': 'frontRotorSizeMm',
      'component_label': 'rotor delantero',
      'unit': 'mm',
      'requires_fact_key': 'brakeType',
      'requires_fact_values': ['mechanical_disc', 'hydraulic_disc'],
      'min_value': 100,
      'max_value': 260,
    },
    {
      'spec_key': 'rotor_diameter_mm_value',
      'position': 'rear',
      'bike_fact_key': 'rearRotorSizeMm',
      'component_label': 'rotor trasero',
      'unit': 'mm',
      'requires_fact_key': 'brakeType',
      'requires_fact_values': ['mechanical_disc', 'hydraulic_disc'],
      'min_value': 100,
      'max_value': 260,
    },
  ])
    BikeFactSpecLink.fromJson(row)!,
];

// La ficha técnica del «Disco freno Shimano Deore RT56 180MM» como la lee
// `get_product_spec_contexts_v1` en producción (2026-09-28).
const _rt56At180 = {
  'rotor_material': 'Acero Inoxidable',
  'rotor_diameter_mm_value': 180,
  'rotor_nominal_thickness_mm': 1.75,
};

// La Scott Scale 960 del taller: hidráulico, 203 adelante y 160 atrás,
// confirmados.
const _scottValues = {
  'brakeType': 'hydraulic_disc',
  'frontRotorSizeMm': 203,
  'rearRotorSizeMm': 160,
};
const _scottConfirmed = {
  'brakeType': true,
  'frontRotorSizeMm': true,
  'rearRotorSizeMm': true,
};

void main() {
  group('el neumático calza con su rueda', () {
    // Las filas del neumático (20260928110000), con las del rotor.
    final links = [
      ..._links,
      for (final row in const [
        {
          'spec_key': 'bead_seat_diameter_mm',
          'position': 'front',
          'bike_fact_key': 'frontWheelBsdMm',
          'component_label': 'rueda delantera',
          'component_article': 'la',
          'unit': null,
          'requires_fact_key': null,
          'requires_fact_values': <String>[],
          'min_value': 150,
          'max_value': 700,
          'template_key': 'tire',
          'on_mismatch': 'conflict',
        },
        {
          'spec_key': 'bead_seat_diameter_mm',
          'position': 'rear',
          'bike_fact_key': 'rearWheelBsdMm',
          'component_label': 'rueda trasera',
          'component_article': 'la',
          'unit': null,
          'requires_fact_key': null,
          'requires_fact_values': <String>[],
          'min_value': 150,
          'max_value': 700,
          'template_key': 'tire',
          'on_mismatch': 'conflict',
        },
      ])
        BikeFactSpecLink.fromJson(row)!,
    ];
    // Como las entrega `get_product_spec_contexts_v1` en producción
    // (2026-09-28): «MAXXIS ALAMBRE 29X2.25 M315P ARDENT», «Neumatico
    // Bicicleta Aro 27.5 X 2.10 Voltage Best», «NEUMATICO ARISUN 26 X 2.10
    // MOUNT CAMERON» y «Llanta Weinmann U32 TL 29" Ojetillos 32H Presta
    // Negro».
    const ardent = {
      '__template_key': 'tire',
      'bead_seat_diameter_mm': 622,
      'tire_width_mm': 57.1,
    };
    const voltage = {'__template_key': 'tire', 'bead_seat_diameter_mm': 584};
    const cameron = {'__template_key': 'tire', 'bead_seat_diameter_mm': 559};
    const weinmannRim = {
      '__template_key': 'rim',
      'bead_seat_diameter_mm': 622,
    };
    const rearMarker = {'key': 'rearWheelBsdMm', 'value': 622};
    const frontMarker622 = {'key': 'frontWheelBsdMm', 'value': 622};

    test('en una 29" el Ardent se anota atrás, declarado', () {
      final change = partBikeFactChange(
        links: links,
        productSpecValues: ardent,
        location: BikeMemoryLocation.rear,
        confirmedMarker: rearMarker,
        bikeWheelSize: '29"',
      )!;
      expect(change.status, PartBikeFactChangeStatus.change);
      expect(change.marker, rearMarker);
      expect(change.label,
          'La ficha lo anota al terminar: rueda trasera 622 (29″/700c)');
      expect(change.tooltip, contains('sin confirmar'));
    });

    test('sin rueda, se nombra el neumático; el ancho no propone nada', () {
      final change = partBikeFactChange(
        links: links,
        productSpecValues: ardent,
        location: BikeMemoryLocation.none,
      )!;
      expect(change.status, PartBikeFactChangeStatus.chooseWheel);
      expect(change.label,
          'Neumático 622 (29″/700c): elige la rueda para anotarlo en la ficha');
      expect(change.marker, isNull);
    });

    test('un 584 no calza en una 29", con marca o sin ella', () {
      for (final marker in [
        null,
        const {'key': 'frontWheelBsdMm', 'value': 584},
      ]) {
        final change = partBikeFactChange(
          links: links,
          productSpecValues: voltage,
          location: BikeMemoryLocation.front,
          confirmedMarker: marker,
          bikeWheelSize: '29"',
        )!;
        expect(change.status, PartBikeFactChangeStatus.incompatible);
        expect(change.blockingKey, 'bikes.wheel_size');
        expect(change.label,
            'No calza con el aro 29" de la bici: la ficha no anotará la rueda delantera');
        // El aro escrito refuta un neumático y una llanta: el consejo es de
        // los dos (20260928140000).
        expect(change.tooltip, kWheelSizeAdvice);
      }
    });

    test('26 no refuta: son al menos seis diámetros', () {
      PartBikeFactChange at(Map<String, dynamic> specs, int value) =>
          partBikeFactChange(
            links: links,
            productSpecValues: specs,
            location: BikeMemoryLocation.front,
            confirmedMarker: {'key': 'frontWheelBsdMm', 'value': value},
            bikeWheelSize: "26''",
          )!;
      expect(at(cameron, 559).status, PartBikeFactChangeStatus.change);
      // 584 es un 26″ posible (650B, «26 × 1 1/2»), y la lista de 26″ no
      // se puede dar por completa: el rótulo no refuta ni un 622.
      expect(at(voltage, 584).status, PartBikeFactChangeStatus.change);
      expect(at(ardent, 622).status, PartBikeFactChangeStatus.change);
    });

    test('un rótulo que no se lee no refuta nada', () {
      for (final wheelSize in ['27.5" - 26"', '28', "14''", null]) {
        final change = partBikeFactChange(
          links: links,
          productSpecValues: voltage,
          location: BikeMemoryLocation.front,
          confirmedMarker: const {'key': 'frontWheelBsdMm', 'value': 584},
          bikeWheelSize: wheelSize,
        )!;
        expect(change.status, PartBikeFactChangeStatus.change,
            reason: '$wheelSize');
      }
    });

    test('lo que la ficha dice de la rueda manda sobre el rótulo', () {
      final change = partBikeFactChange(
        links: links,
        productSpecValues: ardent,
        location: BikeMemoryLocation.front,
        confirmedMarker: frontMarker622,
        bikeValues: const {'frontWheelBsdMm': 584},
        bikeConfirmed: const {'frontWheelBsdMm': true},
        bikeSources: const {'frontWheelBsdMm': 'mechanic'},
      )!;
      expect(change.status, PartBikeFactChangeStatus.incompatible);
      expect(change.blockingKey, 'frontWheelBsdMm');
      expect(change.label,
          'No calza: en la ficha la rueda delantera es 584 (27,5″/650b)');
    });

    test('sin confirmar también refuta: un BSD distinto es otra rueda', () {
      final change = partBikeFactChange(
        links: links,
        productSpecValues: ardent,
        location: BikeMemoryLocation.front,
        confirmedMarker: frontMarker622,
        bikeValues: const {'frontWheelBsdMm': 584},
        bikeSources: const {'frontWheelBsdMm': 'job_completion'},
        // Lo escribió otra línea: ésta no tenía marca guardada.
      )!;
      expect(change.status, PartBikeFactChangeStatus.incompatible);
    });

    test('la línea que lo escribió puede corregirse; ya medido, no', () {
      PartBikeFactChange corrected(
        String source, {
        Map<String, dynamic>? written = const {
          'key': 'frontWheelBsdMm',
          'value': 584,
        },
      }) =>
          partBikeFactChange(
            links: links,
            productSpecValues: ardent,
            location: BikeMemoryLocation.front,
            confirmedMarker: frontMarker622,
            writtenMarker: written,
            bikeValues: const {'frontWheelBsdMm': 584},
            bikeSources: {'frontWheelBsdMm': source},
            jobFinished: true,
          )!;
      // El servidor dice que el 584 lo escribió esta línea.
      final own = corrected('job_completion');
      expect(own.status, PartBikeFactChangeStatus.change);
      expect(own.label,
          'Corrige la ficha al guardar: rueda delantera 584 → 622 (29″/700c)');
      // El mecánico volvió a elegir 584 en la ficha: ya es su medida.
      expect(
          corrected('mechanic').status, PartBikeFactChangeStatus.incompatible);
      // Sin la lectura del servidor (o si otra línea lo escribió, como la
      // segunda de dos neumáticos de 584), no es suyo, aunque la marca
      // guardada de la línea diga 584.
      expect(corrected('job_completion', written: null).status,
          PartBikeFactChangeStatus.incompatible);
      expect(
        corrected('job_completion',
            written: const {'key': 'frontWheelBsdMm', 'value': 559}).status,
        PartBikeFactChangeStatus.incompatible,
      );
    });

    test('la misma medida no cambia nada ni se dice confirmada', () {
      final same = partBikeFactChange(
        links: links,
        productSpecValues: ardent,
        location: BikeMemoryLocation.rear,
        confirmedMarker: rearMarker,
        bikeValues: const {'rearWheelBsdMm': 622},
        bikeSources: const {'rearWheelBsdMm': 'job_completion'},
        bikeWheelSize: '29"',
      )!;
      expect(same.status, PartBikeFactChangeStatus.confirms);
      expect(same.label, 'La ficha ya dice rueda trasera 622 (29″/700c)');
      expect(same.tooltip,
          contains('Queda sin confirmar, salvo que la ficha técnica'));
    });

    test('una llanta no usa la fila del neumático', () {
      expect(
        partBikeFactChange(
          links: links,
          productSpecValues: weinmannRim,
          location: BikeMemoryLocation.rear,
          confirmedMarker: rearMarker,
          bikeWheelSize: '29"',
        ),
        isNull,
      );
    });

    test('una fila sin familia ni regla (sólo 20260928100000) es un cambio',
        () {
      final rotor = BikeFactSpecLink.fromJson(const {
        'spec_key': 'rotor_diameter_mm_value',
        'position': 'rear',
        'bike_fact_key': 'rearRotorSizeMm',
        'component_label': 'rotor trasero',
      })!;
      expect(rotor.templateKey, isNull);
      expect(rotor.mustFit, isFalse);
      expect(rotor.componentArticle, 'el');
      expect(rotor.appliesTo('rim'), isTrue);
      expect(links.last.appliesTo('TIRE'), isTrue);
      expect(links.last.appliesTo('rim'), isFalse);
      expect(links.last.appliesTo(null), isFalse);
    });

    test('lo que el servidor no escribió se dice con la medida de la rueda',
        () {
      final messages = installedBikeFactProblemMessages({
        'problems': [
          {
            'item_name': 'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best',
            'key': 'frontWheelBsdMm',
            'value': 584,
            'reason': 'incompatible',
            'requires_key': 'bikes.wheel_size',
            'requires_value': '29"',
          },
          {
            'item_name': 'Neumático FREEDOM Dual, 29x2.10',
            'key': 'frontWheelBsdMm',
            'value': 622,
            'reason': 'incompatible',
            'requires_key': 'frontWheelBsdMm',
            'requires_value': '584',
          },
        ],
      });
      expect(
          messages[0],
          startsWith(
              '«Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best» dice 584 (27,5″/650b) en la rueda delantera, pero la ficha de la bici dice aro 29": la ficha no cambió.'));
      expect(
          messages[1],
          contains(
              'dice 622 (29″/700c) en la rueda delantera, pero la ficha de la bici dice que la rueda delantera es 584 (27,5″/650b)'));
      expect(messages[1], contains('Revisa la medida del neumático'));
      expect(wheelInstalledFactLabel('rearWheelBsdMm', 622),
          '622 (29″/700c) en la rueda trasera');
    });

    test('la ficha de la bici muestra el diámetro de cada llanta', () {
      final bike =
          Bike(tenantId: 't', customerId: 'c', brand: 'Trek', model: '3900');
      expect(
        BikeProfileSummaryBuilder.buildTechnicalHighlights(
          bike: bike,
          technicalValues: const {
            'frontWheelBsdMm': 622,
            'rearWheelBsdMm': 622
          },
        ),
        contains('Llantas (BSD): 622 (29″/700c)'),
      );
      expect(
        BikeProfileSummaryBuilder.buildTechnicalHighlights(
          bike: bike,
          technicalValues: const {
            'frontWheelBsdMm': 584,
            'rearWheelBsdMm': 559
          },
        ),
        containsAll(<String>[
          'Llanta delantera (BSD): 584 (27,5″/650b)',
          'Llanta trasera (BSD): 559 (26″)',
        ]),
      );
    });
  });

  group('relación única', () {
    test('lee las filas del rotor y descarta una posición desconocida', () {
      expect(_links.map((link) => link.bikeFactKey),
          ['frontRotorSizeMm', 'rearRotorSizeMm']);
      expect(_links.last.position, BikeMemoryLocation.rear);
      expect(_links.last.requiresFactValues,
          {'mechanical_disc', 'hydraulic_disc'});
      expect(
        BikeFactSpecLink.fromJson(const {
          'spec_key': 'rotor_diameter_mm_value',
          'position': 'both',
          'bike_fact_key': 'x',
          'component_label': 'rotor',
        }),
        isNull,
      );
    });
  });

  group('el cambio que propone un rotor', () {
    test('reemplazo: 160 → 180 atrás, con su marca y la precaución', () {
      final change = partBikeFactChange(
        links: _links,
        productSpecValues: _rt56At180,
        location: BikeMemoryLocation.rear,
        confirmedMarker: const {'key': 'rearRotorSizeMm', 'value': 180},
        bikeValues: _scottValues,
        bikeConfirmed: _scottConfirmed,
      )!;

      expect(change.status, PartBikeFactChangeStatus.change);
      expect(change.label,
          'Cambia la ficha al terminar: rotor trasero 160 → 180 mm');
      expect(change.marker, {'key': 'rearRotorSizeMm', 'value': 180});
      expect(change.tooltip, contains('adaptador'));
    });

    test('sin rueda pide elegirla y no guarda marca', () {
      final change = partBikeFactChange(
        links: _links,
        productSpecValues: _rt56At180,
        location: BikeMemoryLocation.none,
        bikeValues: _scottValues,
        bikeConfirmed: _scottConfirmed,
      )!;

      expect(change.status, PartBikeFactChangeStatus.chooseWheel);
      expect(
          change.label, 'Rotor 180 mm: elige la rueda para cambiar la ficha');
      expect(change.marker, isNull);
    });

    test('en una bici con freno de llanta confirmado no calza', () {
      final change = partBikeFactChange(
        links: _links,
        productSpecValues: _rt56At180,
        location: BikeMemoryLocation.front,
        confirmedMarker: const {'key': 'frontRotorSizeMm', 'value': 180},
        bikeValues: const {'brakeType': 'rim', 'rimBrakeFamily': 'v_brake'},
        bikeConfirmed: const {'brakeType': true, 'rimBrakeFamily': true},
      )!;

      expect(change.status, PartBikeFactChangeStatus.incompatible);
      expect(change.label, contains('«Llanta (rim)»'));
      expect(change.label, contains('no cambiará el rotor delantero'));
      // La marca se guarda igual: al terminar lo decide el servidor con la
      // ficha de ese momento y deja el aviso en la historia de la bici.
      expect(change.marker, {'key': 'frontRotorSizeMm', 'value': 180});
    });

    test('sin marca, lo que no calza se dice antes que invitar a confirmar',
        () {
      final old = partBikeFactChange(
        links: _links,
        productSpecValues: _rt56At180,
        location: BikeMemoryLocation.front,
        bikeValues: const {'brakeType': 'rim'},
        bikeConfirmed: const {'brakeType': true},
      )!;
      expect(old.status, PartBikeFactChangeStatus.incompatible);
      expect(old.label, isNot(contains('toca')));
    });

    test('un freno de llanta sin confirmar no refuta el rotor', () {
      final change = partBikeFactChange(
        links: _links,
        productSpecValues: _rt56At180,
        location: BikeMemoryLocation.front,
        confirmedMarker: const {'key': 'frontRotorSizeMm', 'value': 180},
        bikeValues: const {'brakeType': 'rim'},
        bikeConfirmed: const {'brakeType': false},
      )!;

      expect(change.status, PartBikeFactChangeStatus.change);
      expect(
          change.label, 'Cambia la ficha al terminar: rotor delantero 180 mm');
    });

    test('la misma medida no cambia la ficha ni dice que la confirma', () {
      final same = partBikeFactChange(
        links: _links,
        productSpecValues: const {'rotor_diameter_mm_value': 160},
        location: BikeMemoryLocation.rear,
        confirmedMarker: const {'key': 'rearRotorSizeMm', 'value': 160},
        bikeValues: _scottValues,
        bikeConfirmed: _scottConfirmed,
      )!;
      expect(same.status, PartBikeFactChangeStatus.confirms);
      expect(same.label, 'La ficha ya dice rotor trasero 160 mm');

      final unconfirmed = partBikeFactChange(
        links: _links,
        productSpecValues: const {'rotor_diameter_mm_value': 160},
        location: BikeMemoryLocation.rear,
        confirmedMarker: const {'key': 'rearRotorSizeMm', 'value': 160},
        bikeValues: _scottValues,
        bikeConfirmed: const {'rearRotorSizeMm': false},
      )!;
      // Lo que no está verificado entra declarado: la misma medida no la
      // confirma (20260928110000).
      expect(unconfirmed.label, 'La ficha ya dice rotor trasero 160 mm');
      expect(unconfirmed.tooltip,
          contains('Queda sin confirmar, salvo que la ficha técnica'));
      expect(same.tooltip, isNull);
      expect(unconfirmed.marker, {'key': 'rearRotorSizeMm', 'value': 160});
    });

    test('una línea con rueda y sin marca no cambia nada hasta confirmarla',
        () {
      // Como las 4 líneas de rotor antiguas con rueda de producción: volver
      // a guardar su trabajo no reescribe la ficha.
      final old = partBikeFactChange(
        links: _links,
        productSpecValues: const {'rotor_diameter_mm_value': 160},
        location: BikeMemoryLocation.front,
        bikeValues: _scottValues,
        bikeConfirmed: _scottConfirmed,
      )!;
      expect(old.status, PartBikeFactChangeStatus.unconfirmed);
      expect(
          old.label, 'Rotor delantero 160 mm: toca para que cambie la ficha');
      // Lo que se guardaría al confirmar.
      expect(old.marker, {'key': 'frontRotorSizeMm', 'value': 160});

      // Una marca de otro repuesto u otra rueda tampoco vale.
      for (final stale in const [
        {'key': 'frontRotorSizeMm', 'value': 203},
        {'key': 'rearRotorSizeMm', 'value': 160},
      ]) {
        expect(
          partBikeFactChange(
            links: _links,
            productSpecValues: const {'rotor_diameter_mm_value': 160},
            location: BikeMemoryLocation.front,
            confirmedMarker: stale,
          )!
              .status,
          PartBikeFactChangeStatus.unconfirmed,
          reason: '$stale',
        );
      }
    });

    test('en un trabajo terminado el cambio es al guardar', () {
      final change = partBikeFactChange(
        links: _links,
        productSpecValues: _rt56At180,
        location: BikeMemoryLocation.rear,
        confirmedMarker: const {'key': 'rearRotorSizeMm', 'value': 180.0},
        bikeValues: _scottValues,
        bikeConfirmed: _scottConfirmed,
        jobFinished: true,
      )!;
      expect(change.label,
          'Cambia la ficha al guardar: rotor trasero 160 → 180 mm');
      expect(
        samePartChangeMarker(
          const {'key': 'rearRotorSizeMm', 'value': 180},
          const {'key': 'rearRotorSizeMm', 'value': '180'},
        ),
        isTrue,
      );
    });

    test('sin medida entera del concepto enlazado no propone nada', () {
      for (final specs in const [
        <String, dynamic>{},
        // Pastillas: nada de la relación.
        {'pad_compound': 'resina'},
        // El diámetro retirado guarda pares de montaje: no cuenta.
        {'rotor_diameter_mm': '180/160'},
        // Un decimal no se redondea a una medida de la ficha.
        {'rotor_diameter_mm_value': 180.5},
        // Fuera del rango de taller: un error de la ficha técnica, que el
        // servidor no aplicaría (revisión de Codex, 2026-09-28).
        {'rotor_diameter_mm_value': 99},
        {'rotor_diameter_mm_value': 261},
        {'rotor_diameter_mm_value': 1800},
      ]) {
        expect(
          partBikeFactChange(
            links: _links,
            productSpecValues: specs,
            location: BikeMemoryLocation.rear,
          ),
          isNull,
          reason: '$specs',
        );
      }
    });

    test('las medidas reales del inventario sí proponen', () {
      for (final size in const [160, 180, 203]) {
        expect(
          partBikeFactChange(
            links: _links,
            productSpecValues: {'rotor_diameter_mm_value': size},
            location: BikeMemoryLocation.rear,
          )?.marker,
          {'key': 'rearRotorSizeMm', 'value': size},
        );
      }
    });

    test('sin la relación (antes de desplegar) no propone nada', () {
      expect(
        partBikeFactChange(
          links: const [],
          productSpecValues: _rt56At180,
          location: BikeMemoryLocation.rear,
        ),
        isNull,
      );
    });
  });

  group('la marca en la línea', () {
    test('un repuesto guarda su marca aparte de «Configurar»', () {
      expect(
        jobLineConfiguration(
          answers: null,
          partChange: const {'key': 'rearRotorSizeMm', 'value': 180},
        ),
        {
          'part_change': {'key': 'rearRotorSizeMm', 'value': 180},
        },
      );
      // Sin marca nueva, la vieja no se arrastra en las respuestas.
      expect(
        jobLineConfiguration(
          answers: const {
            'part_change': {'key': 'rearRotorSizeMm', 'value': 180},
          },
          partChange: null,
        ),
        isNull,
      );
      expect(
        jobLineConfiguration(
          answers: const {'which_wheel': 'rear', 'hole_count': '28'},
          partChange: null,
        ),
        {'which_wheel': 'rear', 'hole_count': '28'},
      );
    });

    test('al cargar, la marca no convierte la línea en un servicio configurado',
        () {
      final line = JobPartItem.fromPersisted(MechanicJobItem(
        id: 'e2800000-0000-4000-8000-000000000061',
        jobId: 'e2800000-0000-4000-8000-000000000051',
        tenantId: 'e2800000-0000-4000-8000-000000000001',
        productId: 'e2800000-0000-4000-8000-000000000101',
        productName: 'Disco freno Shimano Deore RT56 180MM',
        productSku: '',
        quantity: 1,
        unitPrice: 25990,
        totalPrice: 25990,
        itemType: 'product',
        location: BikeMemoryLocation.rear,
        notes: 'Pedido por el cliente',
        serviceConfigurationData: const {
          'part_change': {'key': 'rearRotorSizeMm', 'value': 180},
        },
      ));

      expect(line.hasWizardAnswers, isFalse,
          reason: 'la descripción del repuesto sigue siendo editable');
      expect(line.partChange, {'key': 'rearRotorSizeMm', 'value': 180});
      expect(line.copyWith(quantity: 2).partChange, line.partChange);
      expect(line.withPersistedId('otro').partChange, line.partChange);
    });
  });

  group('lo que la ficha no tomó, dicho en el taller', () {
    test('rotor incompatible, marca vencida, fuera de rango y línea borrada',
        () {
      final messages = installedBikeFactProblemMessages({
        'applied': const [],
        'problems': const [
          {
            'item_name': 'Disco freno Shimano Deore RT56 180MM',
            'key': 'frontRotorSizeMm',
            'value': 180,
            'reason': 'incompatible',
            'requires_key': 'brakeType',
            'requires_value': 'rim',
          },
          {
            'item_name': 'Disco freno Shimano Deore RT56 180MM',
            'key': 'rearRotorSizeMm',
            'value': 160,
            'reason': 'stale_change',
          },
          {
            'item_name': 'Rotor mal cargado',
            'key': 'rearRotorSizeMm',
            'value': 1800,
            'reason': 'out_of_range',
          },
          {
            'item_name': 'Rotor ZTTO Acero Inoxidable 203x2.3mm',
            'reason': 'mixed_change',
          },
          {
            'bike_label': 'Scott Scale 960',
            'key': 'rearRotorSizeMm',
            'value': 180,
            'previous': 160,
            'reason': 'no_longer_installed',
          },
        ],
      });

      expect(
          messages[0],
          contains(
              'dice 180 mm en el rotor delantero, pero en la ficha el tipo de freno es «Llanta (rim)»'));
      expect(messages[1], contains('(160 mm en el rotor trasero) ya no calza'));
      expect(messages[2], contains('fuera de lo que acepta la ficha'));
      expect(messages[2], isNot(contains('perforaciones')));
      expect(
          messages[3], contains('dice perforaciones y un cambio de repuesto'));
      expect(
        messages[4],
        'La ficha de Scott Scale 960 sigue diciendo 180 mm en el rotor '
        'trasero por una línea que ya no está, que ya no dice haberlo '
        'instalado ahí (antes: 160 mm en el rotor trasero). Si esa pieza no '
        'se instaló, corrige su ficha; si sí, vuelve a elegir el dato en su '
        'campo de la ficha para confirmarlo.',
      );
    });
  });

  group('el cassette y el piñón de rosca calzan con el driver', () {
    // Las filas de 20260928120000, con las del rotor.
    final migration = File(
      'supabase/migrations/20260928120000_part_change_rear_cogs.sql',
    ).readAsStringSync();
    const splineMap = {
      'Shimano HG spline S (7v)': 'shimano_hg',
      'Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según '
          'filas C-731; LINKGLIDE según C-649)': 'shimano_hg',
      'Shimano HG spline L (ROAD 11/12v; otras coronas sólo según filas '
          'C-731)': 'shimano_hg_road_11',
      'Shimano MICRO SPLINE (MTB 12v)': 'microspline',
      'SRAM XD': 'sram_xd',
      'SRAM XDR': 'sram_xdr',
      'Campagnolo': 'campagnolo',
      'Campagnolo N3W': 'campagnolo_n3w',
    };
    final links = [
      ..._links,
      for (final row in const [
        {
          'spec_key': 'cassette_spline_standard',
          'position': 'rear',
          'bike_fact_key': 'freehubType',
          'component_label': 'driver trasero',
          'component_article': 'el',
          'min_value': 0,
          'max_value': 0,
          'template_key': 'cassette',
          'on_mismatch': 'conflict',
          'value_map': splineMap,
          'fits': {
            'shimano_hg': ['shimano_hg_road_11'],
            'sram_xd': ['sram_xdr'],
          },
        },
        {
          'spec_key': '_family',
          'position': 'rear',
          'bike_fact_key': 'freehubType',
          'component_label': 'driver trasero',
          'component_article': 'el',
          'min_value': 0,
          'max_value': 0,
          'template_key': 'freewheel',
          'on_mismatch': 'conflict',
          'constant_value': 'threaded_freewheel',
          'product_condition': {
            'spec_key': 'sprocket_count',
            'min': 2,
            'max': 14,
          },
        },
        {
          'spec_key': 'sprocket_count',
          'position': 'rear',
          'bike_fact_key': 'drivetrainConfig',
          'component_label': 'transmisión',
          'component_article': 'la',
          'min_value': 1,
          'max_value': 14,
          'template_key': 'cassette',
          'on_mismatch': 'check',
        },
        {
          'spec_key': 'sprocket_count',
          'position': 'rear',
          'bike_fact_key': 'drivetrainConfig',
          'component_label': 'transmisión',
          'component_article': 'la',
          'min_value': 1,
          'max_value': 14,
          'template_key': 'freewheel',
          'on_mismatch': 'check',
        },
      ])
        BikeFactSpecLink.fromJson(row)!,
    ];

    // Las fichas técnicas reales (producción, 2026-09-28).
    const hg200x7 = {
      '__template_key': 'cassette',
      'cassette_spline_standard': 'Shimano HG spline S (7v)',
      'sprocket_count': 7,
    };
    const hg200x9 = {
      '__template_key': 'cassette',
      'cassette_spline_standard':
          'Shimano HG spline M (8/9/10v y MTB 11v; ROAD 11v y 7v sólo según '
              'filas C-731; LINKGLIDE según C-649)',
      'sprocket_count': 9,
    };
    const slxMicrospline = {
      '__template_key': 'cassette',
      'cassette_spline_standard': 'Shimano MICRO SPLINE (MTB 12v)',
      'sprocket_count': 12,
    };
    const r7100L2 = {
      '__template_key': 'cassette',
      'cassette_spline_standard': 'Shimano HG spline L2 (ROAD 12v dedicado)',
      'sprocket_count': 12,
    };
    const sramNxWithoutSpline = {
      '__template_key': 'cassette',
      'sprocket_count': 12,
    };
    const fw71 = {'__template_key': 'freewheel', 'sprocket_count': 7};
    const fixedCog15 = {'__template_key': 'freewheel'};
    const rearHub = {
      '__template_key': 'hub',
      'hub_package_position': 'Trasera',
    };
    const hubSet = {
      '__template_key': 'hub',
      'hub_package_position': 'Juego (delantera y trasera)',
    };
    const rearShifter = {
      '__template_key': 'shifter',
      'shifter_position': 'Derecho (trasero)',
    };
    const frontShifter = {
      '__template_key': 'shifter',
      'shifter_position': 'Izquierdo (delantero)',
    };
    const hgMarker = {'key': 'freehubType', 'value': 'shimano_hg'};

    PartBikeFactChange? change(
      Map<String, dynamic> specs, {
      BikeMemoryLocation location = BikeMemoryLocation.rear,
      Map<String, dynamic>? marker = hgMarker,
      Map<String, dynamic>? written,
      Map<String, dynamic> values = const {},
      Map<String, dynamic> sources = const {},
      Set<String> families = const {},
    }) =>
        partBikeFactChange(
          links: links,
          productSpecValues: specs,
          location: location,
          confirmedMarker: marker,
          writtenMarker: written,
          bikeValues: values,
          bikeSources: sources,
          jobRearFamilies: families,
        );

    test('las filas de la prueba son las de la migración', () {
      final block = migration.substring(
        migration.indexOf("('cassette_spline_standard', 'rear'"),
        migration.indexOf("('_family', 'rear'"),
      );
      final map = block.substring(
        block.indexOf('jsonb_build_object('),
        block.indexOf("'Campagnolo N3W', 'campagnolo_n3w'),") + 36,
      );
      final pairs = {
        for (final match
            in RegExp(r"'([^']+)', '([a-z0-9_]+)'").allMatches(map))
          match.group(1)!: match.group(2)!,
      };
      expect(pairs, splineMap);
      expect(block, contains('"shimano_hg": ["shimano_hg_road_11"]'));
      expect(block, contains('"sram_xd": ["sram_xdr"]'));
      expect(
          migration,
          contains(
              '\'{"spec_key": "sprocket_count", "min": 2, "max": 14}\'::jsonb'));
    });

    test('los nombres del driver y la lectura de piñones son los del SQL', () {
      final label = migration.substring(
        migration.indexOf('function public.freehub_type_label'),
        migration.indexOf('function public.drivetrain_rear_cog_count'),
      );
      expect({
        for (final match
            in RegExp(r"when '([a-z0-9_]+)' then '([^']+)'").allMatches(label))
          match.group(1)!: match.group(2)!,
      }, kDrivetrainFreehubTypeOptions);
      expect(migration, contains(r"~ '^[1-3]\s*x\s*([1-9]|1[0-4])$'"));
      // Los mismos casos que `part_change_rear_cogs.sql`.
      expect(
        [
          '3x7',
          '1x12',
          'singlespeed',
          ' 3 x 8 ',
          '4x7',
          '2x15',
          'unknown',
          null,
        ].map(drivetrainRearCogCount).toList(),
        [7, 12, 1, 8, null, null, null, null],
      );
    });

    test('sin driver en la ficha, el cassette lo anota', () {
      final fill = change(hg200x7, values: const {'drivetrainConfig': '2x7'})!;
      expect(fill.status, PartBikeFactChangeStatus.change);
      expect(fill.label,
          'La ficha lo anota al terminar: driver trasero Shimano HG');
      expect(fill.marker, hgMarker);
      // «Desconocido» no refuta.
      expect(
        change(hg200x7, values: const {'freehubType': 'unknown'})!.status,
        PartBikeFactChangeStatus.change,
      );
      // Sin marca, se pide confirmar.
      expect(
        change(hg200x7, marker: null)!.label,
        'Driver trasero Shimano HG: toca para que la ficha lo anote',
      );
    });

    test('sin rueda, el cassette va atrás: tocar el chip la elige', () {
      final choose = change(
        hg200x7,
        location: BikeMemoryLocation.none,
        marker: null,
      )!;
      expect(choose.status, PartBikeFactChangeStatus.chooseWheel);
      expect(choose.onlyPosition, BikeMemoryLocation.rear);
      expect(
        choose.label,
        'Cassette (driver Shimano HG): toca para elegir la rueda trasera y '
        'anotarlo en la ficha',
      );
      // El rotor va en cualquiera: se elige en el menú.
      expect(
        partBikeFactChange(
          links: links,
          productSpecValues: _rt56At180,
          location: BikeMemoryLocation.none,
        )!
            .onlyPosition,
        isNull,
      );
    });

    // Dueño, 2026-10-01: «acaso existe un piñón delantero?». Sólo tiene
    // lado lo que de verdad puede ir en una u otra rueda.
    test(
        'el piñón va sólo atrás, el rotor en cualquiera y sin datos no hay lado',
        () {
      expect(partWheelPositions(links: links, productSpecValues: hg200x7),
          {BikeMemoryLocation.rear});
      expect(partWheelPositions(links: links, productSpecValues: fw71),
          {BikeMemoryLocation.rear});
      expect(partWheelPositions(links: links, productSpecValues: _rt56At180),
          {BikeMemoryLocation.front, BikeMemoryLocation.rear});
      expect(
          partWheelPositions(
            links: links,
            productSpecValues: const {'__template_key': 'chain'},
          ),
          isEmpty);
    });

    test('lo mismo confirma y lo que calza sin ser lo mismo no cambia', () {
      expect(
        change(hg200x7, values: const {'freehubType': 'shimano_hg'})!.label,
        'La ficha ya dice driver trasero Shimano HG',
      );
      final fits = change(
        hg200x9,
        values: const {
          'freehubType': 'shimano_hg_road_11',
          'drivetrainConfig': '2x9',
        },
      )!;
      expect(fits.status, PartBikeFactChangeStatus.fits);
      expect(
          fits.label, 'Calza con la ficha: driver trasero Shimano HG Road 11');
      expect(fits.tooltip, contains('separador (1,85 mm'));
      // El código es la familia del núcleo, no su largo: un cassette de 7
      // lleva además un separador.
      expect(
        change(hg200x7, values: const {'freehubType': 'shimano_hg'})!.tooltip,
        contains('separador de 4,5 mm'),
      );
      expect(
        change(hg200x9, values: const {'freehubType': 'shimano_hg'})!.tooltip,
        isNot(contains('4,5 mm')),
      );
      // Calzar con el núcleo no salva los piñones.
      final roubaix = change(
        hg200x9,
        values: const {
          'freehubType': 'shimano_hg_road_11',
          'drivetrainConfig': '2x8',
        },
      )!;
      expect(roubaix.status, PartBikeFactChangeStatus.incompatible);
      expect(roubaix.blockingKey, 'drivetrainConfig');
    });

    test('otro driver no calza; con una maza trasera nueva queda pendiente',
        () {
      final freewheel = change(
        fw71,
        marker: const {'key': 'freehubType', 'value': 'threaded_freewheel'},
        values: const {'freehubType': 'shimano_hg', 'drivetrainConfig': '3x7'},
      )!;
      expect(freewheel.status, PartBikeFactChangeStatus.incompatible);
      expect(freewheel.label,
          'No calza: en la ficha el driver trasero es «Shimano HG»');
      expect(
          freewheel.tooltip, contains('Revisa el núcleo de la maza trasera'));

      final withHub = change(
        hg200x7,
        values: const {
          'freehubType': 'threaded_freewheel',
          'drivetrainConfig': '2x7',
        },
        families: rearFamiliesInstalledByJob([
          (location: BikeMemoryLocation.rear, specs: rearHub),
        ]),
      )!;
      expect(withHub.status, PartBikeFactChangeStatus.pending);
      expect(withHub.pending, PartBikeFactPending.hubChange);
      expect(
          withHub.label,
          'Pendiente: el trabajo cambia la maza trasera; elige su driver en '
          'la ficha');
      // Una maza en juego montada adelante no decide el driver trasero.
      expect(
        change(
          hg200x7,
          values: const {'freehubType': 'threaded_freewheel'},
          families: rearFamiliesInstalledByJob([
            (location: BikeMemoryLocation.front, specs: hubSet),
          ]),
        )!
            .status,
        PartBikeFactChangeStatus.incompatible,
      );
      // Sin posición ni rueda no es la trasera; en la rueda trasera, sí.
      const necoHub = {'__template_key': 'hub'};
      expect(
        rearFamiliesInstalledByJob([
          (location: BikeMemoryLocation.none, specs: necoHub),
        ]),
        isEmpty,
      );
      expect(
        rearFamiliesInstalledByJob([
          (location: BikeMemoryLocation.rear, specs: necoHub),
        ]),
        {'hub'},
      );
      expect(
        change(slxMicrospline,
                marker: const {'key': 'freehubType', 'value': 'microspline'},
                values: const {'freehubType': 'shimano_hg'})!
            .blockingValue,
        'shimano_hg',
      );
    });

    test('otros piñones no calzan; con un mando trasero nuevo, pendiente', () {
      const outpost = {'freehubType': 'shimano_hg', 'drivetrainConfig': '3x8'};
      final nine = change(hg200x9, values: outpost)!;
      expect(nine.status, PartBikeFactChangeStatus.incompatible);
      expect(nine.label,
          'No calza: la transmisión de la ficha es 3x8 (8 piñones atrás)');
      expect(nine.tooltip, contains('necesita el mando de esa velocidad'));
      final withShifter = change(
        hg200x9,
        values: outpost,
        families: rearFamiliesInstalledByJob([
          (location: BikeMemoryLocation.none, specs: rearShifter),
        ]),
      )!;
      expect(withShifter.status, PartBikeFactChangeStatus.pending);
      expect(
          withShifter.label,
          'Pendiente: el trabajo cambia el mando trasero; revisa la '
          'transmisión 3x8 en la ficha');
      expect(
        change(
          hg200x9,
          values: outpost,
          families: rearFamiliesInstalledByJob([
            (location: BikeMemoryLocation.none, specs: frontShifter),
          ]),
        )!
            .status,
        PartBikeFactChangeStatus.incompatible,
      );
    });

    test('sólo corrige el driver que escribió esta misma línea', () {
      const microsplineByJob = {'freehubType': 'microspline'};
      const byJob = {'freehubType': 'job_completion'};
      final own = change(
        hg200x7,
        values: microsplineByJob,
        sources: byJob,
        written: const {'key': 'freehubType', 'value': 'microspline'},
      )!;
      expect(own.status, PartBikeFactChangeStatus.change);
      expect(
          own.label,
          'Corrige la ficha al terminar: driver trasero Micro Spline → '
          'Shimano HG');
      // Escrito por otra línea, o elegido otra vez por el mecánico: no.
      expect(
        change(hg200x7, values: microsplineByJob, sources: byJob)!.status,
        PartBikeFactChangeStatus.incompatible,
      );
      expect(
        change(
          hg200x7,
          values: microsplineByJob,
          sources: const {'freehubType': 'mechanic'},
          written: const {'key': 'freehubType', 'value': 'microspline'},
        )!
            .status,
        PartBikeFactChangeStatus.incompatible,
      );
    });

    test('no anota lo que no tiene código ni lo que la familia no asegura', () {
      for (final specs in [r7100L2, sramNxWithoutSpline, fixedCog15]) {
        expect(change(specs), isNull, reason: '$specs');
      }
      // 99 coronas es un error de la ficha técnica: ni marca ni refuta.
      expect(
          change(const {'__template_key': 'freewheel', 'sprocket_count': 99}),
          isNull);
      expect(
        change(
          const {
            '__template_key': 'cassette',
            'cassette_spline_standard': 'Shimano HG spline S (7v)',
            'sprocket_count': 99,
          },
          values: const {
            'freehubType': 'shimano_hg',
            'drivetrainConfig': '3x8'
          },
        )!
            .status,
        PartBikeFactChangeStatus.confirms,
      );
      // Un piñón de una corona puede ser fijo.
      expect(change(const {'__template_key': 'freewheel', 'sprocket_count': 1}),
          isNull);
      // La transmisión sólo se revisa: nunca se marca.
      expect(
        change(hg200x7, marker: const {'key': 'drivetrainConfig', 'value': 7})!
            .marker,
        hgMarker,
      );
    });

    test('las marcas de código se comparan por texto', () {
      expect(samePartChangeMarker(hgMarker, {...hgMarker}), isTrue);
      expect(
        samePartChangeMarker(
            hgMarker, const {'key': 'freehubType', 'value': 'microspline'}),
        isFalse,
      );
      expect(
        samePartChangeMarker(const {'key': 'rearRotorSizeMm', 'value': 180},
            const {'key': 'rearRotorSizeMm', 'value': '180'}),
        isTrue,
      );
      expect(
        samePartChangeMarker(
            hgMarker, const {'key': 'freehubType', 'value': 7}),
        isFalse,
      );
    });

    test('lo que el servidor informa, dicho en el taller', () {
      final messages = installedBikeFactProblemMessages({
        'applied': const [],
        'problems': const [
          {
            'item_name': 'PIÑON FW-61 FOR 6 SPEED 14-28T',
            'key': 'freehubType',
            'value': 'threaded_freewheel',
            'reason': 'incompatible',
            'requires_key': 'freehubType',
            'requires_value': 'shimano_hg',
          },
          {
            'item_name': 'CASSETTE SHIMANO 9V. (11-32) HG200 AE',
            'key': 'freehubType',
            'value': 'shimano_hg',
            'reason': 'incompatible',
            'requires_key': 'drivetrainConfig',
            'requires_value': '3x8',
          },
          {
            'item_name': 'Cassette Shimano 7V CS-HG200-7 12/32T',
            'key': 'freehubType',
            'value': 'shimano_hg',
            'reason': 'pending',
            'pending': 'hub_change',
            'requires_key': 'freehubType',
            'requires_value': 'threaded_freewheel',
          },
          {
            'item_name': 'CASSETTE SHIMANO 9V. (11-32) HG200 AE',
            'key': 'freehubType',
            'value': 'shimano_hg',
            'reason': 'pending',
            'pending': 'shifter_change',
            'requires_key': 'drivetrainConfig',
            'requires_value': '3x8',
          },
        ],
      });
      expect(
        messages[0],
        '«PIÑON FW-61 FOR 6 SPEED 14-28T» dice Rueda libre roscada en el '
        'driver trasero, pero la ficha de la bici dice que el driver trasero '
        'es «Shimano HG»: la ficha no cambió. Revisa el núcleo de la maza '
        'trasera: si es otro, corrige el driver en la ficha de la bici y '
        'guarda el trabajo; si no, cambia la línea.',
      );
      expect(
          messages[1],
          contains(
              'pero la transmisión de la ficha es 3x8: la ficha no cambió'));
      expect(
        messages[2],
        '«Cassette Shimano 7V CS-HG200-7 12/32T» dice Shimano HG en el '
        'driver trasero y la ficha de la bici dice que el driver trasero es '
        '«Rueda libre roscada», pero el trabajo también cambia la maza '
        'trasera: el driver lo dice la maza nueva. Elígelo en la ficha de la '
        'bici y guarda el trabajo. La ficha no cambió.',
      );
      expect(
          messages[3],
          contains(
              'que la transmisión es 3x8, pero el trabajo también cambia el mando trasero'));
    });
  });

  group('una línea de General es de una bici sólo si el trabajo tiene una', () {
    // Rotor, neumático y cassette, como los entrega PostgREST.
    final links = [
      ..._links,
      for (final row in const [
        {
          'spec_key': 'bead_seat_diameter_mm',
          'position': 'rear',
          'bike_fact_key': 'rearWheelBsdMm',
          'component_label': 'rueda trasera',
          'component_article': 'la',
          'min_value': 150,
          'max_value': 700,
          'template_key': 'tire',
          'on_mismatch': 'conflict',
        },
        {
          'spec_key': 'cassette_spline_standard',
          'position': 'rear',
          'bike_fact_key': 'freehubType',
          'component_label': 'driver trasero',
          'min_value': 0,
          'max_value': 0,
          'template_key': 'cassette',
          'on_mismatch': 'conflict',
          'value_map': {'Shimano HG spline S (7v)': 'shimano_hg'},
        },
      ])
        BikeFactSpecLink.fromJson(row)!,
    ];
    const hg200x7 = {
      '__template_key': 'cassette',
      'cassette_spline_standard': 'Shimano HG spline S (7v)',
      'sprocket_count': 7,
    };
    const ardent = {'__template_key': 'tire', 'bead_seat_diameter_mm': 622};

    PartBikeFactChange? inGeneral(
      Map<String, dynamic> specs,
      Map<String, dynamic> marker, {
      required int bikes,
    }) =>
        partBikeFactChange(
          links: links,
          productSpecValues: specs,
          location: BikeMemoryLocation.rear,
          confirmedMarker: marker,
          lineBike: partLineBike(inBikeTab: false, bikeCount: bikes),
        );

    test('la bici de la línea, como `job_line_bike_internal`', () {
      expect(
          partLineBike(inBikeTab: true, bikeCount: 2), PartLineBike.resolved);
      expect(
          partLineBike(inBikeTab: false, bikeCount: 1), PartLineBike.resolved);
      expect(
          partLineBike(inBikeTab: false, bikeCount: 2), PartLineBike.several);
      expect(partLineBike(inBikeTab: false, bikeCount: 0), PartLineBike.none);
    });

    test('con una bici promete y marca; con dos, no', () {
      const hgMarker = {'key': 'freehubType', 'value': 'shimano_hg'};
      final oneBike = inGeneral(hg200x7, hgMarker, bikes: 1)!;
      expect(oneBike.status, PartBikeFactChangeStatus.change);
      expect(oneBike.marker, hgMarker);
      expect(oneBike.label,
          'La ficha lo anota al terminar: driver trasero Shimano HG');

      final twoBikes = inGeneral(hg200x7, hgMarker, bikes: 2)!;
      expect(twoBikes.status, PartBikeFactChangeStatus.chooseBike);
      expect(twoBikes.marker, isNull);
      expect(
        twoBikes.label,
        'Cassette (driver Shimano HG): asígnalo a su bici para anotarlo en '
        'la ficha',
      );
      expect(twoBikes.tooltip, contains('varias bicis'));
      expect(twoBikes.tooltip, contains('«Asignar a…»'));

      // Lo mismo para el rotor y el neumático.
      final rotor = inGeneral(
        _rt56At180,
        const {'key': 'rearRotorSizeMm', 'value': 180},
        bikes: 2,
      )!;
      expect(rotor.marker, isNull);
      expect(rotor.label,
          'Rotor 180 mm: asígnalo a su bici para cambiar la ficha');
      final tire = inGeneral(
        ardent,
        const {'key': 'rearWheelBsdMm', 'value': 622},
        bikes: 2,
      )!;
      expect(tire.marker, isNull);
      expect(tire.label, startsWith('Neumático 622 (29″/700c): asígnalo'));

      // Sin bicis en el trabajo, la ficha no cambiará.
      expect(
        inGeneral(hg200x7, hgMarker, bikes: 0)!.label,
        'Cassette (driver Shimano HG): el trabajo no tiene bici; la ficha no '
        'cambiará',
      );
    });

    test('guardar conserva la marca que ya tenía (el servidor avisa)', () {
      // `_partChangeMarkerForSave` compara sin la bici: una marca vieja que
      // calza con el repuesto se guarda igual y el servidor responde
      // `line_without_bike` al terminar, en vez de callar.
      const marker = {'key': 'freehubType', 'value': 'shimano_hg'};
      expect(
        samePartChangeMarker(
          partBikeFactChange(
            links: links,
            productSpecValues: hg200x7,
            location: BikeMemoryLocation.rear,
          )?.marker,
          marker,
        ),
        isTrue,
      );
    });
  });

  group('«Asignar a…» pasa la misma línea de General a su bici', () {
    const hgMarker = {'key': 'freehubType', 'value': 'shimano_hg'};
    JobPartItem cassette() => JobPartItem(
          id: 'e2820000-0000-4000-8000-000000000200',
          name: 'Cassette Shimano 7V CS-HG200-7 12/32T',
          quantity: 1,
          unitPrice: 19990,
          location: BikeMemoryLocation.rear,
          notes: 'Cambio de cassette, cadena revisada',
          wizardAnswers: const {'cadena': 'revisada'},
          partChange: Map<String, dynamic>.from(hgMarker),
        );

    test('mismo id y datos, sin la marca, una sola vez', () {
      final chain =
          JobPartItem(name: 'Cadena KMC Z7', quantity: 1, unitPrice: 8990);
      final line = cassette();
      final general = [chain, line];
      final bianchi = <JobPartItem>[];

      final moved = assignJobLineToBike(
        general: general,
        bikeLines: bianchi,
        itemId: line.id,
      )!;

      expect(general, [chain]);
      expect(bianchi, hasLength(1));
      expect(bianchi.single, same(moved));
      expect(moved.id, line.id);
      expect(moved.name, line.name);
      expect(moved.quantity, 1);
      expect(moved.unitPrice, 19990);
      expect(moved.notes, 'Cambio de cassette, cadena revisada');
      expect(moved.location, BikeMemoryLocation.rear);
      expect(moved.wizardAnswers, const {'cadena': 'revisada'});
      // Lo confirmó sin bici: se vuelve a confirmar en la suya.
      expect(moved.partChange, isNull);

      // Otra vez (doble toque): ya no está en General y no se duplica.
      expect(
        assignJobLineToBike(
          general: general,
          bikeLines: bianchi,
          itemId: line.id,
        ),
        isNull,
      );
      expect(bianchi, hasLength(1));
    });

    test('al guardar es la misma fila, con su bici y sin marca', () {
      final bianchi = <JobPartItem>[];
      final moved = assignJobLineToBike(
        general: [cassette()],
        bikeLines: bianchi,
        itemId: 'e2820000-0000-4000-8000-000000000200',
      )!;
      final row = jobLineFromPart(
        moved,
        persisted: true,
        jobId: 'e2820000-0000-4000-8000-000000000070',
        jobBikeId: 'jb-bianchi',
        tenantId: 'e2820000-0000-4000-8000-000000000001',
        configuration: jobLineConfiguration(
          answers: moved.wizardAnswers,
          partChange: moved.partChange,
        ),
      );
      expect(row.id, 'e2820000-0000-4000-8000-000000000200');
      expect(row.jobBikeId, 'jb-bianchi');
      expect(row.productName, 'Cassette Shimano 7V CS-HG200-7 12/32T');
      expect(row.unitPrice, 19990);
      expect(row.notes, 'Cambio de cassette, cadena revisada');
      expect(row.serviceConfigurationData, const {'cadena': 'revisada'});
    });

    test('«Pasar a…» corrige la bici equivocada con la misma línea', () {
      final line = cassette();
      final trek = [line];
      final bianchi = <JobPartItem>[];

      final moved = assignJobLineToBike(
        general: trek,
        bikeLines: bianchi,
        itemId: line.id,
      )!;

      expect(trek, isEmpty);
      expect(bianchi.single, same(moved));
      expect(moved.id, line.id);
      // Lo confirmó contra la ficha de la otra bici.
      expect(moved.partChange, isNull);
    });

    test(
        '«Pasar a General» deja aparte lo que el cliente compró, '
        'aunque el trabajo tenga una sola bici (dueño, 2026-10-01)', () {
      final helmet = JobPartItem(
          id: 'e2820000-0000-4000-8000-000000000203',
          name: 'Casco urbano',
          quantity: 1,
          unitPrice: 29990);
      final trek = [helmet];
      final general = <JobPartItem>[];

      final moved = assignJobLineToBike(
        general: trek,
        bikeLines: general,
        itemId: helmet.id,
      )!;

      expect(trek, isEmpty);
      expect(general.single, same(moved));
      expect(moved.id, helmet.id);
      expect(moved.unitPrice, 29990);
    });

    test('el aviso del servidor dice cómo resolverlo', () {
      final messages = installedBikeFactProblemMessages(const {
        'problems': [
          {
            'item_name': 'Cassette Shimano 7V CS-HG200-7 12/32T',
            'key': 'freehubType',
            'value': 'shimano_hg',
            'reason': 'line_without_bike',
          },
        ],
      });
      expect(
          messages.single,
          startsWith(
              '«Cassette Shimano 7V CS-HG200-7 12/32T» no dice de qué bici'));
      expect(messages.single, contains('«Asignar a…» en el menú de la línea'));
    });

    test('el menú lo ofrece sólo donde es seguro (contrato)', () {
      final source = File(
        'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
      ).readAsStringSync();
      final targets = source.substring(
        source.indexOf('List<JobLineMoveTarget> _assignTargetsFor('),
        source.indexOf('void _assignLineToBike('),
      );
      // Con lo cobrado editable, a cualquier otra pestaña: desde General
      // «Asignar a <bici>», desde una bici «Pasar a <bici>» y «Pasar a
      // General» (2026-10-01; antes sólo desde General y con dos o más
      // bicis). Nunca a la misma pestaña.
      expect(targets, contains('_isCommercialSnapshotLocked'));
      expect(targets, contains('if (!identical(tab, currentTab))'));
      expect(targets, contains("? 'Pasar a General'"));
      expect(targets,
          contains("currentTab.isGeneralTab ? 'Asignar a' : 'Pasar a'"));
      // Mientras se configura o se guarda, espera: el comando ya lleva la
      // línea donde estaba.
      expect(
          targets,
          contains(
              'final waiting = _configuringItemId == item.id || _isSaving;'));
      expect(targets, contains('waiting ? null : () => _assignLineToBike('));

      final assign = source.substring(
        source.indexOf('void _assignLineToBike('),
        source.indexOf('void _choosePartWheel('),
      );
      expect(assign, contains('if (_isSaving ||'));
      expect(assign, contains('_isCommercialSnapshotLocked ||'));
      expect(assign, contains('assignJobLineToBike('));
      // General vacía se esconde: la vista pasa a la bici elegida.
      expect(assign, contains('if (sourceHidden) showTarget();'));
      expect(assign, contains('identical(_bikeTabs[tabIndex], source)'));
      // El aviso con «Ver <bici>» no queda fijo al salir del trabajo.
      expect(assign, contains('persist: false,'));

      // La fila lo recibe, y una fila protegida no tiene menú.
      expect(source, contains('assignTargets: _assignTargetsFor(item),'));
      final actions = source.substring(
        source.indexOf('List<JobLineAction> _lineActions('),
        source.indexOf("key: ValueKey('\${prefix}_move_up_\${item.id}'),"),
      );
      expect(actions, contains('if (widget.locked) return const [];'));
      expect(actions, contains('widget.assignTargets.indexed'));

      // Guardada, se envía por su id (actualiza, no inserta).
      final stage = source.substring(
        source.indexOf('void stagePartItem('),
        source.indexOf('// Save each bike tab'),
      );
      expect(
          stage,
          contains(
              'final persisted = _seenLineVersions.containsKey(item.id);'));
    });
  });

  group('la maza: su driver, su anclaje y la rueda que queda', () {
    // Las filas de 20260928130000 con las del rotor, como las entrega
    // PostgREST.
    final migration = File(
      'supabase/migrations/20260928130000_part_change_hub.sql',
    ).readAsStringSync();
    const receiverMap = {
      'Rosca para piñón (rueda libre)': 'threaded_freewheel',
      'Driver BMX': 'bmx_driver',
      'Rosca para piñón fijo': 'fixed_threaded',
    };
    const mountMap = {'6 pernos': 'six_bolt', 'Centerlock': 'centerlock'};
    Map<String, dynamic> hubCondition(String position) => {
          'spec_key': 'hub_package_position',
          'values': [position, 'Universal'],
          'missing_ok': true,
        };
    final links = [
      ..._links,
      for (final row in [
        {
          'spec_key': 'cassette_spline_standard',
          'position': 'rear',
          'bike_fact_key': 'freehubType',
          'component_label': 'driver trasero',
          'min_value': 0,
          'max_value': 0,
          'template_key': 'cassette',
          'on_mismatch': 'conflict',
          'value_map': const {'Shimano HG spline S (7v)': 'shimano_hg'},
          'fits': const {
            'shimano_hg': ['shimano_hg_road_11'],
          },
        },
        {
          'spec_key': '_family',
          'position': 'rear',
          'bike_fact_key': 'freehubType',
          'component_label': 'driver trasero',
          'min_value': 0,
          'max_value': 0,
          'template_key': 'freewheel',
          'on_mismatch': 'conflict',
          'constant_value': 'threaded_freewheel',
          'product_condition': const {
            'spec_key': 'sprocket_count',
            'min': 2,
            'max': 14,
          },
        },
        {
          'spec_key': 'hub_drive_receiver_kind',
          'position': 'rear',
          'bike_fact_key': 'freehubType',
          'component_label': 'driver trasero',
          'min_value': 0,
          'max_value': 0,
          'template_key': 'hub',
          'on_mismatch': 'change',
          'value_map': receiverMap,
          'product_condition': hubCondition('Trasera'),
        },
        for (final (position, key, label, condition) in [
          (
            'front',
            'frontRotorMount',
            'anclaje del rotor delantero',
            'Delantera'
          ),
          ('rear', 'rearRotorMount', 'anclaje del rotor trasero', 'Trasera'),
        ]) ...[
          {
            'spec_key': 'rotor_mount_type',
            'position': position,
            'bike_fact_key': key,
            'component_label': label,
            'min_value': 0,
            'max_value': 0,
            'template_key': 'hub',
            'on_mismatch': 'change',
            'value_map': mountMap,
            'product_condition': hubCondition(condition),
          },
          {
            'spec_key': 'rotor_mount_type',
            'position': position,
            'bike_fact_key': key,
            'component_label': label,
            'min_value': 0,
            'max_value': 0,
            'template_key': 'rotor',
            'on_mismatch': 'check',
            'value_map': mountMap,
            'fits': const {
              'six_bolt': ['centerlock'],
            },
          },
        ],
        for (final (position, key, label, condition) in [
          ('front', 'frontSpokeHoles', 'rueda delantera', 'Delantera'),
          ('rear', 'rearSpokeHoles', 'rueda trasera', 'Trasera'),
        ])
          {
            'spec_key': 'spoke_hole_count',
            'position': position,
            'bike_fact_key': key,
            'component_label': label,
            'component_article': 'la',
            'min_value': 12,
            'max_value': 48,
            'template_key': 'hub',
            'on_mismatch': 'check',
            'product_condition': hubCondition(condition),
          },
      ])
        BikeFactSpecLink.fromJson(row)!,
    ];

    // Las fichas técnicas reales (producción, 2026-09-28). Supuesto: la de
    // driver y anclaje a la vez (ninguna del inventario dice las dos) y el
    // anclaje del Cyclami flotante (no lo dice).
    const threaded36 = {
      '__template_key': 'hub',
      'hub_package_position': 'Trasera',
      'spoke_hole_count': 36,
      'hub_drive_receiver_kind': 'Rosca para piñón (rueda libre)',
      'hub_rotor_mount_present': true,
    };
    const betta32 = {
      '__template_key': 'hub',
      'hub_package_position': 'Trasera',
      'spoke_hole_count': 32,
      'hub_drive_receiver_kind': 'Rosca para piñón (rueda libre)',
    };
    const hbRm66 = {
      '__template_key': 'hub',
      'hub_package_position': 'Delantera',
      'spoke_hole_count': 36,
      'rotor_mount_type': 'Centerlock',
    };
    const novatec32Rear = {
      '__template_key': 'hub',
      'hub_package_position': 'Trasera',
      'spoke_hole_count': 32,
      'hub_old_mm': 135,
      'hub_axle_diameter_mm': 10,
    };
    const blookeCore = {
      '__template_key': 'hub',
      'hub_package_position': 'Trasera',
      'spoke_hole_count': 36,
      'hub_drive_receiver_kind': 'Núcleo de cassette',
    };
    const novatecSet = {
      '__template_key': 'hub',
      'hub_package_position': 'Juego (delantera y trasera)',
      'rotor_mount_type': 'Centerlock',
    };
    const freestyleBmx = {
      '__template_key': 'hub',
      'hub_package_position': 'Trasera',
      'spoke_hole_count': 36,
      'hub_drive_receiver_kind': 'Driver BMX',
    };
    const threadedCenterLock = {
      '__template_key': 'hub',
      'hub_package_position': 'Trasera',
      'spoke_hole_count': 36,
      'hub_drive_receiver_kind': 'Rosca para piñón (rueda libre)',
      'rotor_mount_type': 'Centerlock',
      'hub_old_mm': 135,
    };
    const unpositionedThreaded = {
      '__template_key': 'hub',
      'spoke_hole_count': 36,
      'hub_drive_receiver_kind': 'Rosca para piñón (rueda libre)',
    };
    const smRt10 = {
      '__template_key': 'rotor',
      'rotor_diameter_mm_value': 160,
      'rotor_mount_type': 'Centerlock',
    };
    const g3SixBolt = {
      '__template_key': 'rotor',
      'rotor_diameter_mm_value': 160,
      'rotor_mount_type': '6 pernos',
    };
    const cyclamiFloating = {
      '__template_key': 'rotor',
      'rotor_diameter_mm_value': 160,
      'rotor_floating': true,
      'rotor_mount_type': '6 pernos',
    };
    const hg200x7 = {
      '__template_key': 'cassette',
      'cassette_spline_standard': 'Shimano HG spline S (7v)',
      'sprocket_count': 7,
    };
    const fw71 = {'__template_key': 'freewheel', 'sprocket_count': 7};
    const fossRim36 = {'__template_key': 'rim', 'spoke_hole_count': 36};
    const threadedMark = {'key': 'freehubType', 'value': 'threaded_freewheel'};
    const rearCenterLockMark = {'key': 'rearRotorMount', 'value': 'centerlock'};
    // La Oxford Orion 4 del taller (PG-00459): 36 atrás, rueda libre.
    const orionValues = {
      'freehubType': 'threaded_freewheel',
      'frontSpokeHoles': 36,
      'rearSpokeHoles': 36,
      'brakeType': 'mechanical_disc',
    };

    List<PartBikeFactChange> changes(
      Map<String, dynamic> specs, {
      BikeMemoryLocation location = BikeMemoryLocation.rear,
      Object? marker,
      Map<String, dynamic> values = const {},
      Map<String, dynamic> confirmed = const {},
      JobWheelParts? job,
      Map<BikeMemoryLocation, double> spacing = const {},
    }) =>
        partBikeFactChanges(
          links: links,
          productSpecValues: specs,
          location: location,
          confirmedMarker: marker,
          bikeValues: values,
          bikeConfirmed: confirmed,
          job: job,
          bikeHubSpacingMm: spacing,
        );

    JobWheelParts jobWith(List<JobWheelLine> lines) =>
        jobWheelParts(lines, links);

    JobWheelLine part(
      Map<String, dynamic> specs, [
      BikeMemoryLocation location = BikeMemoryLocation.rear,
    ]) =>
        (location: location, specs: specs, holeCount: null, buildWheel: null);

    JobWheelLine build(int holes, BikeMemoryLocation wheel) => (
          location: BikeMemoryLocation.none,
          specs: null,
          holeCount: holes,
          buildWheel: wheel,
        );

    test('las filas y los nombres son los de la migración', () {
      final relation = migration.substring(
        migration.indexOf('insert into public.bike_fact_spec_links'),
        migration.indexOf('on conflict (spec_key, position'),
      );
      for (final entry in receiverMap.entries) {
        expect(relation, contains("'${entry.key}', '${entry.value}'"));
      }
      expect(relation, isNot(contains("'Núcleo de cassette'")));
      expect(
        "jsonb_build_object('6 pernos', 'six_bolt', 'Centerlock', 'centerlock')"
            .allMatches(relation)
            .length,
        4,
      );
      for (final position in ['Trasera', 'Delantera']) {
        expect(
          relation,
          contains('\'{"spec_key": "hub_package_position", "values": '
              '["$position", "Universal"], "missing_ok": true}\'::jsonb'),
        );
      }
      expect(relation, contains('\'{"six_bolt": ["centerlock"]}\'::jsonb'));
      expect(relation, contains("'hub', 'check', null, null, null,"));
      // Los nombres del anclaje son los de `rotor_mount_label`.
      final label = migration.substring(
        migration.indexOf('function public.rotor_mount_label'),
        migration.indexOf('function public.installed_bike_fact_label'),
      );
      expect({
        for (final match
            in RegExp(r"when '([a-z_]+)' then '([^']+)'").allMatches(label))
          match.group(1)!: match.group(2)!,
      }, kBikeRotorMountOptions);
      // Los patrones de Sheldon Brown, los mismos del SQL.
      final lacing = migration.substring(
        migration.indexOf('function public.hub_lacing_fits'),
        migration.indexOf('revoke all on function public.hub_lacing_fits'),
      );
      final pairs = {
        for (final match in RegExp(r'\((\d{2}), (\d{2})\)').allMatches(lacing))
          (int.parse(match.group(1)!), int.parse(match.group(2)!)),
      };
      expect(pairs, hasLength(12));
      for (var hub = 12; hub <= 48; hub++) {
        for (var rim = 12; rim <= 48; rim++) {
          expect(
              hubLacingFits(hub, rim), hub == rim || pairs.contains((hub, rim)),
              reason: '$hub en $rim');
        }
      }
    });

    test('una maza trasera de rueda libre pone su driver; sin rueda, la pide',
        () {
      final fill = changes(threaded36, marker: threadedMark).single;
      expect(fill.status, PartBikeFactChangeStatus.change);
      expect(fill.label,
          'Cambia la ficha al terminar: driver trasero Rueda libre roscada');
      expect(fill.marker, threadedMark);
      final choose =
          changes(threaded36, location: BikeMemoryLocation.none).single;
      expect(choose.status, PartBikeFactChangeStatus.chooseWheel);
      expect(choose.onlyPosition, BikeMemoryLocation.rear);
      expect(
        choose.label,
        'Maza (driver Rueda libre roscada): toca para elegir la rueda trasera '
        'y cambiar la ficha',
      );
      expect(choose.marker, isNull);
      // La BMX, su driver.
      expect(
        changes(freestyleBmx,
                marker: const {'key': 'freehubType', 'value': 'bmx_driver'})
            .single
            .label,
        'Cambia la ficha al terminar: driver trasero Driver BMX',
      );
    });

    test('la HB-RM66 pone Center Lock adelante; atrás pide la delantera', () {
      final front = changes(
        hbRm66,
        location: BikeMemoryLocation.front,
        marker: const {'key': 'frontRotorMount', 'value': 'centerlock'},
      ).single;
      expect(front.label,
          'Cambia la ficha al terminar: anclaje del rotor delantero Center Lock');
      final rear = changes(hbRm66).single;
      expect(rear.status, PartBikeFactChangeStatus.chooseWheel);
      expect(rear.onlyPosition, BikeMemoryLocation.front);
      expect(rear.label, contains('Maza (anclaje Center Lock)'));
    });

    test('driver y anclaje a la vez: un chip y una marca por dato', () {
      final both = changes(
        threadedCenterLock,
        marker: const [threadedMark, rearCenterLockMark],
      );
      expect([for (final change in both) change.link!.bikeFactKey],
          ['freehubType', 'rearRotorMount']);
      expect([for (final change in both) change.status],
          everyElement(PartBikeFactChangeStatus.change));
      expect(
        partChangeMarkerJson([for (final change in both) change.marker]),
        [threadedMark, rearCenterLockMark],
      );
      // Con sólo el driver confirmado, el anclaje espera su confirmación.
      final half = changes(threadedCenterLock, marker: threadedMark);
      expect([
        for (final change in half) change.status
      ], [
        PartBikeFactChangeStatus.change,
        PartBikeFactChangeStatus.unconfirmed,
      ]);
    });

    test('un juego no instala; sin posición dicha, la rueda elegida', () {
      expect(changes(novatecSet, location: BikeMemoryLocation.front), isEmpty);
      expect(changes(novatecSet), isEmpty);
      expect(
        changes(unpositionedThreaded, marker: threadedMark).single.status,
        PartBikeFactChangeStatus.change,
      );
      // Un núcleo de cassette no dice qué driver es.
      expect(changes(blookeCore), isEmpty);
    });

    test('las perforaciones: la rueda que queda decide, no la ficha vieja', () {
      // PG-00459: la Betta de 32 en la rueda de 36 de la Orion.
      final orion =
          changes(betta32, marker: threadedMark, values: orionValues).single;
      expect(orion.status, PartBikeFactChangeStatus.incompatible);
      expect(
          orion.label, 'No calza: en la ficha la rueda trasera lleva 36 rayos');
      expect(orion.tooltip, contains('Una maza con menos perforaciones'));
      // Si el Enrayado del trabajo la arma a 32, calza.
      expect(
        changes(
          betta32,
          marker: threadedMark,
          values: orionValues,
          job: jobWith([build(32, BikeMemoryLocation.rear)]),
        ).single.status,
        PartBikeFactChangeStatus.confirms,
      );
      // Una llanta nueva de 36 en esa rueda manda sobre una ficha de 32.
      final rim = changes(
        betta32,
        marker: threadedMark,
        values: const {'rearSpokeHoles': 32},
        job: jobWith([part(fossRim36)]),
      ).single;
      expect(rim.status, PartBikeFactChangeStatus.incompatible);
      expect(rim.blockingSource, 'job_rim');
      expect(rim.label,
          'No calza: la llanta nueva de la rueda trasera es de 36 perforaciones');
      // Una de 36 se raya en una rueda de 32 (Sheldon Brown).
      expect(
        changes(threaded36,
            marker: threadedMark,
            values: const {'rearSpokeHoles': 32}).single.status,
        PartBikeFactChangeStatus.change,
      );
      // Dos Enrayados de la misma rueda que no dicen lo mismo: la maza no se
      // da por buena (revisión de Codex, 2026-09-28).
      final twoBuilds = changes(
        betta32,
        marker: threadedMark,
        values: orionValues,
        job: jobWith([
          build(32, BikeMemoryLocation.rear),
          build(36, BikeMemoryLocation.rear),
        ]),
      ).single;
      expect(twoBuilds.status, PartBikeFactChangeStatus.incompatible);
      expect(twoBuilds.label,
          'No calza: el Enrayado arma la rueda trasera a 32 o 36 rayos');
    });

    test('un patrón de rayado especial se avisa, no se da por hecho', () {
      // Una maza de 36H con driver en una rueda de 32: calza, con la nota.
      final withFacts = changes(threaded36,
          marker: threadedMark, values: const {'rearSpokeHoles': 32}).single;
      expect(withFacts.status, PartBikeFactChangeStatus.change);
      expect(withFacts.tooltip, contains('patrón especial'));
      // Una de 36H sin datos que escribir: un aviso propio.
      const plain36 = {
        '__template_key': 'hub',
        'hub_package_position': 'Trasera',
        'spoke_hole_count': 36,
      };
      final special =
          changes(plain36, values: const {'rearSpokeHoles': 32}).single;
      expect(special.status, PartBikeFactChangeStatus.caution);
      expect(special.marker, isNull);
      expect(special.label, 'Revisa el rayado: maza 36H en una rueda de 32');
      expect(special.tooltip, contains('Sheldon Brown'));
      // La misma cantidad no dice nada.
      expect(changes(plain36, values: const {'rearSpokeHoles': 36}), isEmpty);
    });

    test('una maza sin datos que escribir también avisa: rayos y ancho', () {
      final holes = changes(novatec32Rear, values: orionValues).single;
      expect(holes.status, PartBikeFactChangeStatus.caution);
      expect(holes.marker, isNull);
      expect(
          holes.label, 'No calza: en la ficha la rueda trasera lleva 36 rayos');
      final spacing = changes(
        novatec32Rear,
        values: const {'rearSpokeHoles': 32},
        spacing: const {BikeMemoryLocation.rear: 142},
      ).single;
      expect(spacing.status, PartBikeFactChangeStatus.caution);
      expect(spacing.label,
          'Revisa el ancho: la maza mide 135 mm y la bici 142 mm entre punteras');
      expect(spacing.tooltip, contains('es del cuadro (u horquilla)'));
      // Con datos que escribir, el ancho va como condición en la ayuda.
      final withFacts = changes(
        threadedCenterLock,
        marker: const [threadedMark, rearCenterLockMark],
        spacing: const {BikeMemoryLocation.rear: 142},
      );
      expect(withFacts.first.status, PartBikeFactChangeStatus.change);
      expect(withFacts.first.tooltip,
          contains('La maza mide 135 mm entre tuercas y la bici 142 mm'));
      // El mismo ancho, o sin saberlo, no dice nada.
      expect(
        changes(novatec32Rear,
            values: const {'rearSpokeHoles': 32},
            spacing: const {BikeMemoryLocation.rear: 135}),
        isEmpty,
      );
    });

    test('el cassette se mide con la maza que instala el trabajo', () {
      final job = jobWith([part(threaded36)]);
      expect(job.hubs[BikeMemoryLocation.rear]?.driver, 'threaded_freewheel');
      final hg = changes(
        hg200x7,
        marker: const {'key': 'freehubType', 'value': 'shimano_hg'},
        values: const {'freehubType': 'shimano_hg'},
        job: job,
      ).single;
      expect(hg.status, PartBikeFactChangeStatus.incompatible);
      expect(hg.label,
          'No calza con la maza del trabajo: su driver es «Rueda libre roscada»');
      expect(hg.tooltip, contains('La maza trasera que instala este trabajo'));
      // El FW71 calza con ella aunque la ficha diga HG.
      final fw = changes(
        fw71,
        marker: threadedMark,
        values: const {'freehubType': 'shimano_hg'},
        job: job,
      ).single;
      expect(fw.status, PartBikeFactChangeStatus.change);
      // Una maza de núcleo sin código: queda pendiente, como antes.
      expect(
        changes(
          hg200x7,
          marker: const {'key': 'freehubType', 'value': 'shimano_hg'},
          values: const {'freehubType': 'threaded_freewheel'},
          job: jobWith([part(blookeCore)]),
        ).single.status,
        PartBikeFactChangeStatus.pending,
      );
      // Una maza sin rueda ni posición no decide: manda la ficha.
      expect(
        changes(
          hg200x7,
          marker: const {'key': 'freehubType', 'value': 'shimano_hg'},
          values: const {'freehubType': 'threaded_freewheel'},
          job: jobWith([part(unpositionedThreaded, BikeMemoryLocation.none)]),
        ).single.status,
        PartBikeFactChangeStatus.incompatible,
      );
    });

    test('el rotor se mide con el anclaje de su maza', () {
      const frontRotor = {'key': 'frontRotorSizeMm', 'value': 160};
      const disc = {'brakeType': 'hydraulic_disc'};
      // Un Center Lock no va en 6 pernos.
      final rt10 = changes(
        smRt10,
        location: BikeMemoryLocation.front,
        marker: frontRotor,
        values: const {...disc, 'frontRotorMount': 'six_bolt'},
      ).single;
      expect(rt10.status, PartBikeFactChangeStatus.incompatible);
      expect(rt10.label,
          'No calza: en la ficha el anclaje del rotor delantero es «6 pernos»');
      // Un 6 pernos entra en Center Lock con el SM-RTAD05.
      final g3 = changes(
        g3SixBolt,
        location: BikeMemoryLocation.front,
        marker: frontRotor,
        values: const {...disc, 'frontRotorMount': 'centerlock'},
      ).single;
      expect(g3.status, PartBikeFactChangeStatus.change);
      expect(g3.tooltip, contains('SM-RTAD05'));
      // El flotante no, y la maza del trabajo manda sobre la ficha.
      final cyclami = changes(
        cyclamiFloating,
        location: BikeMemoryLocation.front,
        marker: frontRotor,
        values: const {...disc, 'frontRotorMount': 'six_bolt'},
        job: jobWith([part(hbRm66, BikeMemoryLocation.front)]),
      ).single;
      expect(cyclami.status, PartBikeFactChangeStatus.incompatible);
      expect(cyclami.blockingSource, 'job_hub');
      expect(cyclami.label,
          'No calza con la maza del trabajo: su anclaje es «Center Lock»');
      expect(cyclami.tooltip, contains('araña de aluminio'));
      // Un anclaje desconocido no refuta.
      expect(
        changes(
          smRt10,
          location: BikeMemoryLocation.front,
          marker: frontRotor,
          values: const {...disc, 'frontRotorMount': 'unknown'},
        ).single.status,
        PartBikeFactChangeStatus.change,
      );
    });

    test('lo que el trabajo instala en cada rueda', () {
      final job = jobWith([
        part(novatecSet, BikeMemoryLocation.none),
        build(36, BikeMemoryLocation.rear),
        part(fossRim36, BikeMemoryLocation.front),
        (
          location: BikeMemoryLocation.rear,
          specs: null,
          holeCount: 32,
          buildWheel: null,
        ),
      ]);
      // Un juego cuenta en las dos ruedas.
      expect(
          job.hubs.keys, {BikeMemoryLocation.front, BikeMemoryLocation.rear});
      expect(job.hubs[BikeMemoryLocation.front]?.rotorMount, 'centerlock');
      // Dos Enrayados atrás (36 y 32): el trabajo decide, pero no se sabe.
      expect(job.spokes[BikeMemoryLocation.rear],
          (holes: null, either: '32 o 36', source: 'job_build'));
      expect(job.spokes[BikeMemoryLocation.front],
          (holes: 36, either: null, source: 'job_rim'));
      // Una llanta que no dice sus perforaciones no borra la que sí las dice,
      // como `job_wheel_spokes_internal`.
      expect(
        jobWith([
          part(fossRim36, BikeMemoryLocation.front),
          part(const {'__template_key': 'rim'}, BikeMemoryLocation.front),
        ]).spokes[BikeMemoryLocation.front],
        (holes: 36, either: null, source: 'job_rim'),
      );
      expect(job.rearFamilies, {'hub'});
      // Una maza que dice ser de la otra rueda no es evidencia de ésta, y un
      // Enrayado fuera de 12 a 48 es un error de tipeo.
      expect(jobWith([part(hbRm66)]).hubs, isEmpty);
      expect(jobWith([build(99, BikeMemoryLocation.front)]).spokes, isEmpty);
      // Un Enrayado con otro lado en la línea no dice rueda, aunque el
      // asistente diga una (`coalesce(nullif(location_key, 'none'), …)`).
      expect(
        jobWith([
          (
            location: BikeMemoryLocation.left,
            specs: null,
            holeCount: 36,
            buildWheel: BikeMemoryLocation.rear,
          ),
        ]).spokes,
        isEmpty,
      );
    });

    test('las marcas de varios datos se leen, se guardan y se cargan', () {
      expect(partChangeMarks(threadedMark), [threadedMark]);
      expect(
        partChangeMarks(const [
          rearCenterLockMark,
          threadedMark,
          'x',
          {'value': 1}
        ]),
        [threadedMark, rearCenterLockMark],
      );
      expect(partChangeMarkerJson(const []), isNull);
      expect(partChangeMarkerJson(const [threadedMark]), threadedMark);
      expect(
          partChangeMarkFor(
              const [threadedMark, rearCenterLockMark], 'rearRotorMount'),
          rearCenterLockMark);
      // Dos marcas de la misma clave no dicen cuál vale.
      expect(
        partChangeMarkFor(const [
          threadedMark,
          {'key': 'freehubType', 'value': 'bmx_driver'},
        ], 'freehubType'),
        isNull,
      );
      expect(
        jobLineConfiguration(
          answers: null,
          partChange: const [threadedMark, rearCenterLockMark],
        ),
        {
          'part_change': [threadedMark, rearCenterLockMark],
        },
      );
      final line = JobPartItem.fromPersisted(MechanicJobItem(
        id: 'e2830000-0000-4000-8000-000000000165',
        jobId: 'e2830000-0000-4000-8000-000000000060',
        tenantId: 'e2830000-0000-4000-8000-000000000001',
        productId: 'e2830000-0000-4000-8000-000000000110',
        productName: 'Maza trasera 36H rueda libre Center Lock',
        productSku: '',
        quantity: 1,
        unitPrice: 19990,
        totalPrice: 19990,
        itemType: 'product',
        location: BikeMemoryLocation.rear,
        serviceConfigurationData: const {
          'part_change': [threadedMark, rearCenterLockMark],
        },
      ));
      expect(line.hasWizardAnswers, isFalse);
      expect(line.partChange, [threadedMark, rearCenterLockMark]);
    });

    test('lo que el servidor informa de una maza, dicho en el taller', () {
      final messages = installedBikeFactProblemMessages({
        'problems': const [
          {
            'item_name': 'Maza Trasera Freewheel Disco 32h Betta',
            'key': 'freehubType',
            'value': 'threaded_freewheel',
            'reason': 'incompatible',
            'requires_key': 'rearSpokeHoles',
            'requires_value': '36',
            'requires_source': 'job_rim',
          },
          {
            'item_name': 'Disco de Freno Flotante 160mm Cyclami',
            'key': 'frontRotorSizeMm',
            'value': 160,
            'reason': 'incompatible',
            'requires_key': 'frontRotorMount',
            'requires_value': 'centerlock',
            'requires_source': 'job_hub',
          },
          {
            'item_name': 'Cassette Shimano 7V CS-HG200-7 12/32T',
            'key': 'freehubType',
            'value': 'shimano_hg',
            'reason': 'incompatible',
            'requires_key': 'freehubType',
            'requires_value': 'threaded_freewheel',
            'requires_source': 'job_hub',
          },
          {
            'item_name': 'maza shimano hb-rm66 36h (cl) delantero negro bolsa',
            'key': 'frontRotorMount',
            'value': 'centerlock',
            'reason': 'stale_change',
          },
          {
            'item_name': 'Enrayado + Centrado',
            'key': 'rearSpokeHoles',
            'value': 40,
            'reason': 'conflicting_build',
            'requires_value': '36',
          },
        ],
      });
      expect(
        messages[4],
        '«Enrayado + Centrado» dice 40H en la rueda trasera, pero otro '
        'Enrayado del mismo trabajo arma esa rueda a 36 rayos: la ficha no '
        'cambió. Una rueda se arma una vez: deja una sola línea con la '
        'cantidad real y guarda el trabajo.',
      );
      expect(
        messages[0],
        '«Maza Trasera Freewheel Disco 32h Betta» dice Rueda libre roscada en '
        'el driver trasero, pero la llanta que instala el trabajo dice que la '
        'rueda trasera lleva 36 rayos: la ficha no cambió. Una maza con menos '
        'perforaciones que la llanta no se puede rayar: si también cambiaste '
        'la llanta, agrega su línea en esa rueda; si la rueda lleva otra '
        'cantidad, corrige la ficha; si no, cambia la línea.',
      );
      expect(
        messages[1],
        contains('pero la maza que instala el trabajo dice que el anclaje del '
            'rotor delantero es «Center Lock»'),
      );
      expect(messages[2],
          contains('pero la maza que instala el trabajo dice que el driver'));
      expect(messages[3],
          contains('(Center Lock en el anclaje del rotor delantero)'));
    });
  });

  group('la llanta: el BSD y las perforaciones de su rueda', () {
    // Las filas de 20260928140000 con las del neumático y la maza, como las
    // entrega PostgREST.
    final migration = File(
      'supabase/migrations/20260928140000_part_change_rim.sql',
    ).readAsStringSync();
    Map<String, dynamic> row(
      String spec,
      String position,
      String key,
      String family,
      String rule,
      int min,
      int max,
    ) =>
        {
          'spec_key': spec,
          'position': position,
          'bike_fact_key': key,
          'component_label':
              position == 'front' ? 'rueda delantera' : 'rueda trasera',
          'component_article': 'la',
          'unit': null,
          'min_value': min,
          'max_value': max,
          'template_key': family,
          'on_mismatch': rule,
        };
    final links = [
      for (final position in const ['front', 'rear']) ...[
        BikeFactSpecLink.fromJson(row('bead_seat_diameter_mm', position,
            '${position}WheelBsdMm', 'rim', 'change', 150, 700))!,
        BikeFactSpecLink.fromJson(row('spoke_hole_count', position,
            '${position}SpokeHoles', 'rim', 'change', 12, 48))!,
        BikeFactSpecLink.fromJson(row('bead_seat_diameter_mm', position,
            '${position}WheelBsdMm', 'tire', 'conflict', 150, 700))!,
        BikeFactSpecLink.fromJson({
          ...row('spoke_hole_count', position, '${position}SpokeHoles', 'hub',
              'check', 12, 48),
          'product_condition': {
            'spec_key': 'hub_package_position',
            'values': [
              position == 'front' ? 'Delantera' : 'Trasera',
              'Universal'
            ],
            'missing_ok': true,
          },
        })!,
      ],
    ];

    // Llantas, mazas y neumáticos reales (producción, 2026-09-28).
    const u32Tl29 = {
      '__template_key': 'rim',
      'spoke_hole_count': 32,
      'bead_seat_diameter_mm': 622,
    };
    const fossF22 = {
      '__template_key': 'rim',
      'spoke_hole_count': 32,
      'rim_wall_type': 'Doble pared',
    };
    const u32Tl275 = {
      '__template_key': 'rim',
      'spoke_hole_count': 28,
      'bead_seat_diameter_mm': 584,
      'rim_etrto': '584x27.4',
    };
    const zac19x36 = {'__template_key': 'rim', 'spoke_hole_count': 36};
    const betta32 = {
      '__template_key': 'hub',
      'hub_package_position': 'Trasera',
      'spoke_hole_count': 32,
    };
    const hub36 = {
      '__template_key': 'hub',
      'hub_package_position': 'Trasera',
      'spoke_hole_count': 36,
    };
    const voltage584 = {
      '__template_key': 'tire',
      'bead_seat_diameter_mm': 584,
    };
    const ardent622 = {
      '__template_key': 'tire',
      'bead_seat_diameter_mm': 622,
    };
    const u32Marks = [
      {'key': 'rearSpokeHoles', 'value': 32},
      {'key': 'rearWheelBsdMm', 'value': 622},
    ];

    List<PartBikeFactChange> changes(
      Map<String, dynamic> specs, {
      BikeMemoryLocation location = BikeMemoryLocation.rear,
      Object? marker,
      Object? written,
      Map<String, dynamic> values = const {},
      Map<String, dynamic> sources = const {},
      String? wheelSize = '29"',
      List<JobWheelLine> job = const [],
    }) =>
        partBikeFactChanges(
          links: links,
          productSpecValues: specs,
          location: location,
          confirmedMarker: marker,
          writtenMarker: written,
          bikeValues: values,
          bikeSources: sources,
          bikeWheelSize: wheelSize,
          job: jobWheelParts(job, links),
        );

    JobWheelLine part(
      Map<String, dynamic> specs, [
      BikeMemoryLocation location = BikeMemoryLocation.rear,
    ]) =>
        (location: location, specs: specs, holeCount: null, buildWheel: null);

    JobWheelLine build(int holes) => (
          location: BikeMemoryLocation.none,
          specs: null,
          holeCount: holes,
          buildWheel: BikeMemoryLocation.rear,
        );

    test('las filas son las de la migración', () {
      final relation = migration.substring(
        migration.indexOf('insert into public.bike_fact_spec_links'),
        migration.indexOf('on conflict (spec_key, position'),
      );
      for (final position in const ['front', 'rear']) {
        final label = position == 'front' ? 'delantera' : 'trasera';
        expect(
            relation,
            contains("('bead_seat_diameter_mm', '$position', "
                "'${position}WheelBsdMm', 'rueda $label', 'la',\n"
                "   null, null, '{}', 150, 700, 'rim', 'change', null, null, "
                'null, null)'));
        expect(
            relation,
            contains("('spoke_hole_count', '$position', "
                "'${position}SpokeHoles', 'rueda $label', 'la',\n"
                "   null, null, '{}', 12, 48, 'rim', 'change', null, null, "
                'null, null)'));
      }
      final rim = links.where((link) => link.templateKey == 'rim').toList();
      expect(rim, hasLength(4));
      expect(rim.every((link) => !link.mustFit && !link.isCheck), isTrue);
      expect(rim.every((link) => link.productConditionKey == null), isTrue);
    });

    test(
        'la U32 TL 29" propone su BSD y sus perforaciones, un chip y una '
        'marca por dato', () {
      final chooseWheel = changes(u32Tl29, location: BikeMemoryLocation.none);
      expect(chooseWheel.single.status, PartBikeFactChangeStatus.chooseWheel);
      expect(chooseWheel.single.label,
          'Llanta 622 (29″/700c): elige la rueda para cambiar la ficha');

      final unconfirmed = changes(u32Tl29);
      expect(unconfirmed.map((change) => change.link!.bikeFactKey),
          ['rearSpokeHoles', 'rearWheelBsdMm']);
      expect(unconfirmed.map((change) => change.status),
          everyElement(PartBikeFactChangeStatus.unconfirmed));
      expect(partChangeMarkerJson(unconfirmed.map((change) => change.marker)),
          u32Marks);

      final marked = changes(u32Tl29, marker: u32Marks);
      expect(marked.map((change) => change.label), [
        'Cambia la ficha al terminar: rueda trasera 32H',
        'Cambia la ficha al terminar: rueda trasera 622 (29″/700c)',
      ]);

      // «Si cambio llanta y ahora usa 28h en vez de 32h» (el dueño): la maza
      // de 32 que queda se raya en 28, con un patrón que tiene que admitir.
      final to28 = changes(u32Tl275,
          marker: const [
            {'key': 'rearSpokeHoles', 'value': 28},
            {'key': 'rearWheelBsdMm', 'value': 584},
          ],
          values: const {'rearSpokeHoles': 32},
          wheelSize: '26"');
      expect(to28.map((change) => change.label), [
        'Cambia la ficha al terminar: rueda trasera 32H → 28H',
        'Cambia la ficha al terminar: rueda trasera 584 (27,5″/650b)',
      ]);
      expect(to28.first.tooltip, contains('Maza de 32H en una rueda de 28'));
    });

    test('el BSD no se lee del nombre: la FOSS F22 «29» propone sólo sus 32H',
        () {
      final foss = changes(fossF22,
          marker: const {'key': 'rearSpokeHoles', 'value': 32});
      expect(foss.single.link!.bikeFactKey, 'rearSpokeHoles');
      expect(
          foss.single.label, 'Cambia la ficha al terminar: rueda trasera 32H');
    });

    test('la maza que queda: menos perforaciones no; más, con patrón', () {
      final fewer = changes(fossF22, values: const {'rearSpokeHoles': 28});
      expect(fewer.single.status, PartBikeFactChangeStatus.incompatible);
      expect(
          fewer.single.label,
          'No calza con la maza que queda: en la ficha la rueda trasera '
          'lleva 28 rayos');
      expect(
          fewer.single.tooltip, startsWith('Una llanta se raya en una maza'));

      final more = changes(fossF22,
          marker: const {'key': 'rearSpokeHoles', 'value': 32},
          values: const {'rearSpokeHoles': 36});
      expect(more.single.status, PartBikeFactChangeStatus.change);
      expect(more.single.tooltip, contains('Maza de 36H en una rueda de 32'));

      // Lo que escribió esta misma línea no es la maza que queda.
      final own = changes(zac19x36,
          marker: const {'key': 'rearSpokeHoles', 'value': 36},
          values: const {'rearSpokeHoles': 28},
          sources: const {'rearSpokeHoles': 'job_completion'},
          written: const {'key': 'rearSpokeHoles', 'value': 28});
      expect(own.single.status, PartBikeFactChangeStatus.change);
      expect(own.single.label,
          'Cambia la ficha al terminar: rueda trasera 28H → 36H');
    });

    test('la maza del trabajo manda sobre la ficha', () {
      final betta = changes(zac19x36,
          values: const {'rearSpokeHoles': 36}, job: [part(betta32)]);
      expect(betta.single.status, PartBikeFactChangeStatus.incompatible);
      expect(betta.single.label,
          'No calza con la maza del trabajo: tiene 32 perforaciones');
      expect(betta.single.blockingSource, 'job_hub');

      final newHub = changes(fossF22,
          marker: const {'key': 'rearSpokeHoles', 'value': 32},
          values: const {'rearSpokeHoles': 28},
          job: [part(betta32)]);
      expect(newHub.single.status, PartBikeFactChangeStatus.change);

      final two = changes(fossF22, job: [part(betta32), part(hub36)]);
      expect(two.single.status, PartBikeFactChangeStatus.incompatible);
      expect(two.single.blockingValue, '32 o 36');
      // La maza de la otra rueda no cuenta.
      final otherWheel =
          changes(fossF22, job: [part(betta32, BikeMemoryLocation.front)]);
      expect(otherWheel.single.status, PartBikeFactChangeStatus.unconfirmed);
    });

    test('el Enrayado y otra llanta de esa rueda dicen la cuenta', () {
      final enrayado = changes(fossF22, job: [build(36)]);
      expect(enrayado.single.label,
          'No calza: el Enrayado arma la rueda trasera a 36 rayos');
      expect(enrayado.single.tooltip,
          startsWith('La rueda queda con las perforaciones de su llanta'));
      final otherRim = changes(fossF22, job: [part(zac19x36)]);
      expect(
          otherRim.single.label,
          'No calza: otra llanta del trabajo en la rueda trasera tiene 36 '
          'perforaciones');
      expect(changes(fossF22, job: [build(32)]).single.status,
          PartBikeFactChangeStatus.unconfirmed);
    });

    test('el neumático: el del trabajo, si no el que queda, si no el aro', () {
      // La ficha dice 584 atrás y el trabajo no pone neumático: la llanta,
      // como pieza, no cambia ninguno de sus datos.
      final remaining = changes(u32Tl29,
          marker: u32Marks, values: const {'rearWheelBsdMm': 584});
      expect(remaining.map((change) => change.status),
          everyElement(PartBikeFactChangeStatus.incompatible));
      expect(
          remaining.first.label,
          'No calza con el neumático que queda: en la ficha la rueda trasera '
          'es 584 (27,5″/650b)');
      expect(remaining.first.tooltip,
          startsWith('Una llanta y su neumático tienen el mismo BSD'));

      final jobTire = changes(u32Tl29,
          marker: u32Marks,
          values: const {'rearWheelBsdMm': 584},
          job: [part(ardent622)]);
      expect(jobTire.map((change) => change.status),
          everyElement(PartBikeFactChangeStatus.change));

      final wrongTire = changes(u32Tl29, job: [part(voltage584)]);
      expect(wrongTire.first.label,
          'No calza con el neumático del trabajo: es 584 (27,5″/650b)');

      final aro = changes(u32Tl275);
      expect(
          aro.first.label,
          'No calza con el aro 29" de la bici: la ficha no anotará la rueda '
          'trasera');
      expect(aro.first.tooltip, kWheelSizeAdvice);
      // 26″ no refuta un 584.
      expect(changes(u32Tl275, wheelSize: '26"').first.status,
          PartBikeFactChangeStatus.unconfirmed);

      final twoRims = changes(u32Tl29, job: [part(u32Tl275)]);
      expect(
          twoRims.first.label,
          'No calza: otra llanta del trabajo en esa rueda es 584 '
          '(27,5″/650b)');
    });

    test(
        'el neumático se mide con la llanta del trabajo antes que con la '
        'ficha', () {
      final voltage = changes(voltage584,
          marker: const {'key': 'rearWheelBsdMm', 'value': 584},
          job: [part(u32Tl29)]);
      expect(voltage.single.status, PartBikeFactChangeStatus.incompatible);
      expect(voltage.single.label,
          'No calza con la llanta del trabajo: es 622 (29″/700c)');
      expect(voltage.single.tooltip,
          startsWith('Un neumático calza sólo en una llanta de su mismo BSD'));

      // La ficha dice 584, pero la llanta nueva es 622: el Ardent entra.
      final ardent = changes(ardent622,
          marker: const {'key': 'rearWheelBsdMm', 'value': 622},
          values: const {'rearWheelBsdMm': 584},
          job: [part(u32Tl29)]);
      expect(ardent.single.status, PartBikeFactChangeStatus.change);
      // Una llanta sin BSD en el trabajo no refuta, y la ficha vieja ya no
      // es su rueda; el aro escrito sigue refutando.
      expect(
          changes(voltage584,
              marker: const {'key': 'rearWheelBsdMm', 'value': 584},
              values: const {'rearWheelBsdMm': 622},
              wheelSize: null,
              job: [part(fossF22)]).single.status,
          PartBikeFactChangeStatus.change);
      expect(changes(voltage584, job: [part(fossF22)]).single.blockingKey,
          'bikes.wheel_size');
    });

    test('lo que el trabajo instala en cada rueda: BSD y perforaciones', () {
      final job = jobWheelParts([
        part(u32Tl29),
        part(voltage584, BikeMemoryLocation.front),
        part(fossF22, BikeMemoryLocation.none),
        part(betta32),
        part(hub36),
      ], links);
      expect(job.rimBsd[BikeMemoryLocation.rear], (value: 622, either: null));
      expect(job.rimBsd[BikeMemoryLocation.front], isNull);
      // Sólo cuenta la rueda elegida en la línea (ni la llanta ni el
      // neumático dicen su posición).
      expect(job.rimBsd.keys, [BikeMemoryLocation.rear]);
      expect(job.tireBsd.keys, [BikeMemoryLocation.front]);
      expect(job.tireBsd[BikeMemoryLocation.front], (value: 584, either: null));
      expect(job.hubs[BikeMemoryLocation.rear]!.holes, isNull);
      expect(job.hubs[BikeMemoryLocation.rear]!.holesEither, '32 o 36');
      // Una llanta sin BSD en la rueda no esconde a la que lo dice
      // (revisión de Codex, 2026-09-29).
      expect(
          jobWheelParts([part(u32Tl29), part(fossF22)], links)
              .rimBsd[BikeMemoryLocation.rear],
          (value: 622, either: null));
      expect(
          jobWheelParts([part(fossF22)], links).rimBsd[BikeMemoryLocation.rear],
          (value: null, either: null));
    });

    test('una pieza sin medida no esconde a la que la dice', () {
      const tireWithoutBsd = {'__template_key': 'tire', 'tire_width_mm': 57.1};
      const hubWithoutHoles = {
        '__template_key': 'hub',
        'hub_package_position': 'Trasera',
      };
      const hub28 = {
        '__template_key': 'hub',
        'hub_package_position': 'Trasera',
        'spoke_hole_count': 28,
      };
      final tires = changes(u32Tl29,
          marker: u32Marks,
          wheelSize: null,
          job: [part(voltage584), part(tireWithoutBsd)]);
      expect(tires.map((change) => change.status),
          everyElement(PartBikeFactChangeStatus.incompatible));
      expect(tires.first.blockingKey, 'rearTireBsdMm');
      expect(tires.first.blockingValue, '584');
      expect(tires.first.blockingSource, 'job_tire');

      final hubs = changes(fossF22,
          marker: const {'key': 'rearSpokeHoles', 'value': 32},
          job: [part(hub28), part(hubWithoutHoles)]);
      expect(hubs.single.status, PartBikeFactChangeStatus.incompatible);
      expect(hubs.single.blockingKey, 'rearHubSpokeHoles');
      expect(hubs.single.blockingValue, '28');
    });

    test('el aro escrito que la ficha contradice no refuta', () {
      // El Gaspio 2: la ficha dice 584 y el aro escrito 29″; el trabajo pone
      // llanta y neumático de 584.
      const u28x32 = {
        '__template_key': 'rim',
        'spoke_hole_count': 32,
        'bead_seat_diameter_mm': 584,
      };
      const marks = [
        {'key': 'rearSpokeHoles', 'value': 32},
        {'key': 'rearWheelBsdMm', 'value': 584},
      ];
      final rim = changes(u28x32,
          marker: marks,
          values: const {'rearWheelBsdMm': 584},
          sources: const {'rearWheelBsdMm': 'mechanic'},
          job: [part(voltage584)]);
      // Las perforaciones cambian; el BSD ya es el de la ficha.
      expect(rim.map((change) => change.status), [
        PartBikeFactChangeStatus.change,
        PartBikeFactChangeStatus.confirms,
      ]);
      final tire = changes(voltage584,
          marker: const {'key': 'rearWheelBsdMm', 'value': 584},
          values: const {'rearWheelBsdMm': 584},
          sources: const {'rearWheelBsdMm': 'mechanic'},
          job: [part(u28x32)]);
      expect(tire.single.status, isNot(PartBikeFactChangeStatus.incompatible));

      // Con la ficha en 622, el aro 29″ sí es de fiar: 584 no entra.
      final stillRefutes = changes(u28x32,
          marker: marks,
          values: const {'rearWheelBsdMm': 622},
          job: [part(voltage584)]);
      expect(stillRefutes.first.blockingKey, 'bikes.wheel_size');
      final tireRefuted = changes(voltage584,
          marker: const {'key': 'rearWheelBsdMm', 'value': 584},
          values: const {'rearWheelBsdMm': 622},
          job: [part(u28x32)]);
      expect(tireRefuted.single.blockingKey, 'bikes.wheel_size');
    });

    test('lo que el servidor informa de una llanta, dicho en el taller', () {
      final messages = installedBikeFactProblemMessages({
        'problems': [
          {
            'item_name':
                'Llanta Weinmann ZAC19 26" Ojetillos 36H Schrader Negro',
            'key': 'rearSpokeHoles',
            'value': 36,
            'reason': 'incompatible',
            'requires_key': 'rearHubSpokeHoles',
            'requires_value': '32',
            'requires_source': 'job_hub',
          },
          {
            'item_name':
                'Llanta Weinmann U32 TL 29" Ojetillos 32H Presta Negro',
            'key': 'rearWheelBsdMm',
            'value': 622,
            'reason': 'incompatible',
            'requires_key': 'rearTireBsdMm',
            'requires_value': '584',
            'requires_source': 'job_tire',
          },
          {
            'item_name': 'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best',
            'key': 'rearWheelBsdMm',
            'value': 584,
            'reason': 'incompatible',
            'requires_key': 'rearRimBsdMm',
            'requires_value': '622',
            'requires_source': 'job_rim',
          },
          {
            'item_name':
                'Llanta FOSS F22 Aluminio Doble Pared con Ojetillos 29x32H',
            'key': 'rearSpokeHoles',
            'value': 32,
            'reason': 'incompatible',
            'requires_key': 'rearBuildSpokeHoles',
            'requires_value': '36',
            'requires_source': 'job_build',
          },
          {
            'item_name':
                'Llanta Weinmann U32 TL 27.5" Ojetillos 28H Presta Negro',
            'key': 'rearWheelBsdMm',
            'value': 584,
            'reason': 'incompatible',
            'requires_key': 'bikes.wheel_size',
            'requires_value': '29"',
          },
        ],
      });
      expect(
        messages[0],
        '«Llanta Weinmann ZAC19 26" Ojetillos 36H Schrader Negro» dice 36H en '
        'la rueda trasera, pero la maza que instala el trabajo dice que la '
        'maza trasera tiene 32 perforaciones: la ficha no cambió. Una llanta '
        'se raya en una maza con sus mismas perforaciones (o con más, en los '
        'patrones de Sheldon Brown), nunca con menos: si también cambiaste la '
        'maza, agrega su línea en esa rueda; si la maza tiene otra cantidad, '
        'corrige la ficha; si no, cambia la línea.',
      );
      expect(
          messages[1],
          contains('pero el neumático que instala el trabajo dice que el '
              'neumático trasero es 584 (27,5″/650b)'));
      expect(
          messages[2],
          contains('pero la llanta que instala el trabajo dice que la llanta '
              'trasera es 622 (29″/700c)'));
      expect(
          messages[3],
          contains('pero la rueda que arma el trabajo dice que la rueda '
              'trasera lleva 36 rayos'));
      expect(messages[4], endsWith(kWheelSizeAdvice));
    });
  });

  test('la línea de repuesto pide la rueda y dice el cambio (contrato)', () {
    final source = File(
      'lib/modules/bikeshop/pages/mechanic_job_form_page.dart',
    ).readAsStringSync();
    final start = source.indexOf('Widget _buildProductEditor(');
    final editor =
        source.substring(start, source.indexOf('return Column(', start));

    expect(
        editor,
        contains(
            'final choosesWheel = item.isServiceItem || partChanges.isNotEmpty;'));
    // Un chip por dato (una maza trasera: driver y anclaje); dos que no
    // calzan por lo mismo se dicen una vez.
    expect(
        editor,
        contains(
            'for (final (changeIndex, partChange) in partChanges.indexed)'));
    expect(editor, contains('shownLabels.add(partChange.label)'));
    expect(
        editor,
        contains(
            'if (choosesWheel && orderedLocations.length > 1 && !widget.locked)'));
    expect(
        editor,
        contains(
            "'\${mobileLayout ? 'mobile' : 'desktop'}_part_change_\${item.id}'"));
    expect(editor, contains('label: partChange.label'));

    // En General, la línea es de la única bici del trabajo, como en el
    // servidor.
    final changeFor = source.substring(
      source.indexOf('List<PartBikeFactChange> _partChangesFor('),
      source.indexOf('void _choosePartWheel('),
    );
    // Lo que el mismo trabajo instala en esa bici (sin la línea misma) se
    // cruza con la línea, como `job_hub_at_wheel_internal` y
    // `job_wheel_spokes_internal`.
    expect(changeFor, contains('.where((other) => other.id != item.id)'));
    expect(changeFor, contains('job: jobWheelParts(['));
    expect(changeFor, contains('holeCount: _enrayadoHoles(other),'));
    expect(changeFor, contains('bikeHubSpacingMm: {'));
    expect(changeFor, contains('physicalTabs.length == 1'));
    expect(changeFor, contains('_pendingBikeProfileForBike(tab.bike)'));
    // Con varias bicis (o ninguna), la línea de General no es de ninguna:
    // ni promete ni marca, y una línea protegida no muestra el aviso.
    expect(changeFor,
        contains('inBikeTab: currentTab != null && !currentTab.isGeneralTab,'));
    expect(changeFor, contains('bikeCount: physicalTabs.length,'));
    expect(
        editor,
        contains(
            'partChange.status == PartBikeFactChangeStatus.chooseBike ||'));

    // El asistente también repara un total que no es platos × piñones,
    // aunque la transmisión ya coincida (el parche no acepta dejarlos
    // incoherentes).
    final wizardConfig = source.substring(
      source.indexOf('String? _selectedDrivetrainConfigFromWizardAnswers('),
      source.indexOf('int? _selectedDrivetrainSpeedsFromWizardAnswers('),
    );
    expect(wizardConfig, contains('currentSpeeds == derivedSpeeds'));

    // Al guardar, la marca va en la configuración de la línea.
    expect(source, contains('partChange: _partChangeMarkerForSave(item)'));
    // La marca nace de elegir la rueda o tocar el chip, nunca de guardar.
    expect(editor, contains('choosePartWheel(location);'));
    expect(editor, contains('widget.onChoosePartWheel!(item.location)'));
    // Un cassette va sólo atrás: tocar el chip elige esa rueda.
    expect(editor,
        contains('widget.onChoosePartWheel!(partChange.onlyPosition!)'));
    final save = source.substring(
      source.indexOf('Object? _partChangeMarkerForSave('),
      source.indexOf('void _addCustomPart('),
    );
    expect(save, contains('final marker = item.partChange;'));
    expect(save, isNot(contains('lineBike')));
    // Cada marca por su clave: se conserva la que todavía calza.
    expect(save, contains('for (final mark in partChangeMarks(marker))'));
    expect(save,
        contains('current.any((valid) => samePartChangeMarker(valid, mark))'));
    // Elegir la rueda marca todos los datos de la pieza en esa rueda.
    final choose = source.substring(
      source.indexOf('void _choosePartWheel('),
      source.indexOf('Object? _partChangeMarkerForSave('),
    );
    expect(
        choose,
        contains(
            'for (final change in _partChangesFor(moved)) change.marker,'));
  });
}
