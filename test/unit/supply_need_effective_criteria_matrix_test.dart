import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_effective_criteria.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';

/// **¿Esto es general, o sólo sabe de cámaras?**
///
/// La ficha efectiva se validó primero sobre «Cámaras 700» y frases de la misma
/// familia, que no demuestra nada sobre otra categoría. Acá se cruza contra
/// **cuatro fichas reales de producción** —`tube`, `rim`, `rotor`, `chain`— con
/// sus `allowed_values` tal como están en la base, y contra **nombres reales del
/// catálogo de esta tienda**. Cada caso afirma dos cosas: qué criterios se
/// derivan y **qué candidatos sobreviven**. Un conteo no dice cuál sobrevivió.

SupplierNeedSearchField _f(
  String key,
  String label,
  String type, {
  List<Object> values = const <Object>[],
  String? unit,
  String? description,
}) =>
    SupplierNeedSearchField(
      key: key,
      label: label,
      dataType: type,
      unit: unit,
      allowedValues: values,
      description: description,
    );

/// Los valores tal como los tiene `spec_definitions` en producción.
const _wheel = <Object>[
  '12"',
  '16"',
  '20"',
  '24"',
  '26"',
  '27.5"',
  '29"',
  '700c',
  '650b',
  'Otra',
];
const _valve = <Object>[
  'Presta (francesa)',
  'Schrader (americana / auto)',
  'Dunlop (inglesa)',
  'Otra',
  'Desconocido',
];

final _tube = <SupplierNeedSearchField>[
  _f('wheel_size', 'Tamaño de rueda', 'single_select', values: _wheel),
  _f('tube_width_min_in', 'Ancho mínimo (pulgadas)', 'number', unit: 'in'),
  _f('tube_width_max_in', 'Ancho máximo (pulgadas)', 'number', unit: 'in'),
  _f('tube_has_sealant', 'Trae líquido sellante', 'boolean',
      description:
          'Autosellante o anti-pinchazo: viene con líquido adentro de fábrica.'),
  _f('tube_material', 'Material de la cámara', 'single_select',
      values: <Object>['Butilo', 'TPU', 'Látex', 'Otro']),
  _f('valve_type', 'Tipo de Válvula', 'single_select', values: _valve),
  _f('valve_length_mm', 'Largo de Válvula (mm)', 'single_select',
      unit: 'mm',
      values: <Object>['33', '35', '40', '44', '48', '52', '60', '80']),
];

final _rim = <SupplierNeedSearchField>[
  _f('wheel_size', 'Tamaño de rueda', 'single_select', values: _wheel),
  _f('spoke_holes', 'Perforaciones', 'single_select',
      values: <Object>['24', '28', '32', '36', '40']),
  _f('valve_type', 'Tipo de válvula', 'single_select', values: _valve),
  _f('rim_tubeless_ready', 'Tubeless Ready (TR)', 'boolean'),
  _f('rim_internal_width_mm', 'Ancho interno', 'number', unit: 'mm'),
  _f('rim_etrto', 'ETRTO', 'text'),
  _f('rim_material', 'Material', 'single_select',
      values: <Object>['Aluminio', 'Carbono', 'Acero', 'Otro']),
  _f('rim_wall_type', 'Pared', 'single_select',
      values: <Object>['Pared simple', 'Doble pared', 'Triple pared']),
];

final _rotor = <SupplierNeedSearchField>[
  _f('rotor_diameter_mm', 'Diámetro', 'single_select',
      values: <Object>['140', '160', '180', '203', '220']),
  _f('rotor_mount_type', 'Montaje', 'single_select',
      values: <Object>['6 pernos', 'Centerlock']),
  _f('rotor_material', 'Material', 'single_select', values: <Object>[
    'Acero Inoxidable',
    'Acero',
    'Aluminio (Pista Acerada)'
  ]),
  _f('rotor_floating', 'Rotor Flotante', 'boolean'),
  _f('brake_position', 'Posición', 'single_select',
      values: <Object>['Delantero', 'Trasero', 'Universal']),
  _f('tool_size_mm', 'Herramienta', 'text'),
];

/// Ficha real de neumáticos (`technical_family = tire`).
final _tire = <SupplierNeedSearchField>[
  _f('wheel_size', 'Tamaño de rueda', 'single_select', values: _wheel),
  _f('tire_width_in', 'Ancho', 'number', unit: 'in'),
  _f('tire_etrto', 'ETRTO', 'text'),
  _f('tire_bead_type', 'Talón', 'single_select', values: <Object>[
    'Talón de alambre',
    'Talón plegable',
    'Tubular',
    'Sólido',
  ]),
  _f('tire_tubeless_ready', 'Tubeless Ready (TR)', 'boolean'),
];

/// Ficha real del motor de centro. **Rompe los supuestos de rueda**: no tiene
/// `wheel_size`, sus números son anchos de caja y largos de eje, y sus valores
/// son frases compuestas.
final _bb = <SupplierNeedSearchField>[
  _f('bb_shell_standard', 'Caja del cuadro', 'single_select', values: <Object>[
    'BSA / Caja inglesa 34,8 mm (1.37") x 24',
    'Italiano 36 mm x 24',
    'BB30',
  ]),
  _f('bb_construction', 'Construcción', 'single_select', values: <Object>[
    'Rodamiento sellado',
    'Integrado',
    'Cubetas y canastillo',
  ]),
  _f('bb_shell_width_mm', 'Ancho de caja', 'number',
      unit: 'mm',
      values: <Object>[68, 70, 73, 83, 86.5, 89.5, 92, 100, 107, 121]),
  _f('spindle_interface', 'Interfaz del eje', 'single_select', values: <Object>[
    'Cuadrado JIS',
    'Cuadrado ISO',
    'Hollowtech / 24mm',
  ]),
  _f('spindle_length_mm', 'Largo del eje', 'number',
      unit: 'mm',
      values: <Object>[
        103,
        107,
        108,
        109,
        110,
        110.5,
        113,
        113.5,
        116,
        118,
        118.5,
        122.5,
        124.5,
        125.5,
        127.5,
      ]),
  _f('includes_spindle', 'Incluye eje', 'boolean'),
];

const _guardadaNeumatico = SupplyNeedCriteria(
  predicates: <SupplyNeedPredicate>[],
  categoryId: 'cat',
  categoryPath: 'Componentes / Ruedas / Neumáticos',
  revisionNo: 1,
  technicalFamily: 'tire',
);

const _guardadaMotor = SupplyNeedCriteria(
  predicates: <SupplyNeedPredicate>[],
  categoryId: 'cat',
  categoryPath: 'Transmisión / Motor',
  revisionNo: 1,
  technicalFamily: 'bottom_bracket',
);

final _chain = <SupplierNeedSearchField>[
  _f('chain_speeds', 'Velocidades', 'multi_select',
      values: <Object>['1', '5', '6', '7', '8', '9', '10', '11', '12', '13']),
  _f('chain_width_family', 'Ancho', 'single_select',
      values: <Object>['1/8', '3/32', '11/128', 'Otro']),
  _f('link_count', 'Eslabones', 'number', unit: 'eslabones'),
  // La ficha real dice «missing link», no «quick link».
  _f('quick_link_included', 'Incluye missing link', 'boolean',
      description: 'Indica si la cadena incluye conector rapido.'),
];

const _guardada = SupplyNeedCriteria(
  predicates: <SupplyNeedPredicate>[],
  categoryId: 'cat',
  revisionNo: 1,
  technicalFamily: 'tube',
);

const _guardadaLlanta = SupplyNeedCriteria(
  predicates: <SupplyNeedPredicate>[],
  categoryId: 'cat',
  revisionNo: 1,
  technicalFamily: 'rim',
);

const _guardadaRotor = SupplyNeedCriteria(
  predicates: <SupplyNeedPredicate>[],
  categoryId: 'cat',
  categoryPath: 'Componentes / Frenos / Discos',
  revisionNo: 1,
  technicalFamily: 'rotor',
);

const _guardadaCadena = SupplyNeedCriteria(
  predicates: <SupplyNeedPredicate>[],
  categoryId: 'cat',
  revisionNo: 1,
  technicalFamily: 'chain',
);

/// Los criterios derivados, como `campo=valor` ordenado, para poder afirmarlos
/// enteros y no de a uno.
Set<String> _derivados(
  String description,
  List<SupplierNeedSearchField> fields, {
  SupplyNeedCriteria stored = _guardada,
}) =>
    effectiveSupplyNeedCriteria(
      stored: stored,
      texts: <String>[description],
      fields: fields,
    )
        .predicates
        .map((predicate) => '${predicate.field}=${predicate.values.single}')
        .toSet();

void main() {
  group('la derivación cruza cuatro fichas reales, no una', () {
    test('cámaras (tube)', () {
      expect(_derivados('Cámaras 700', _tube), <String>{'wheel_size=700c'});
      expect(
        _derivados('Cámaras aro 700 para reposición del taller', _tube),
        <String>{'wheel_size=700c'},
      );
      expect(
        _derivados('cámara 27.5 butilo válvula francesa', _tube),
        <String>{
          'wheel_size=27.5"',
          'tube_material=Butilo',
          'valve_type=Presta (francesa)',
        },
      );
      // La necesidad real de esta tienda: el aro va pegado al sustantivo, así
      // que se declara, y la válvula sale de su marcador.
      expect(
        _derivados('Cámaras 29 con válvula Schrader', _tube),
        <String>{
          'wheel_size=29"',
          'valve_type=Schrader (americana / auto)',
        },
      );
    });

    test('llantas (rim): aro, radios, material y pared', () {
      expect(
        _derivados('Aro 29 de 32 hoyos aluminio doble pared', _rim,
            stored: _guardadaLlanta),
        <String>{
          'wheel_size=29"',
          'spoke_holes=32',
          'rim_material=Aluminio',
          'rim_wall_type=Doble pared',
        },
      );
      expect(
        _derivados('llanta 700c 28 hoyos', _rim, stored: _guardadaLlanta),
        <String>{'wheel_size=700c', 'spoke_holes=28'},
      );
    });

    test('rotores: montaje, posición y diámetro', () {
      expect(
        _derivados('disco 180 6 pernos delantero', _rotor,
            stored: _guardadaRotor),
        <String>{
          'rotor_diameter_mm=180',
          'rotor_mount_type=6 pernos',
          'brake_position=Delantero',
        },
      );
      expect(
        _derivados('rotor 203mm shimano trasero', _rotor,
            stored: _guardadaRotor),
        <String>{'rotor_diameter_mm=203', 'brake_position=Trasero'},
      );
      expect(
        _derivados('disco de freno 160 centerlock acero inoxidable', _rotor,
            stored: _guardadaRotor),
        <String>{
          'rotor_diameter_mm=160',
          'rotor_mount_type=Centerlock',
          'rotor_material=Acero Inoxidable',
        },
      );
    });

    test('cadenas: velocidades y ancho en fracción', () {
      expect(
          _derivados('cadena 11 velocidades', _chain, stored: _guardadaCadena),
          <String>{'chain_speeds=11'});
      expect(
        _derivados('cadena 3/32 de 116 eslabones 9v', _chain,
            stored: _guardadaCadena),
        <String>{'chain_speeds=9', 'chain_width_family=3/32'},
      );
      expect(_derivados('cadena para bmx 1/8', _chain, stored: _guardadaCadena),
          <String>{'chain_width_family=1/8'});
    });
  });

  group('dos familias que rompen los supuestos de la rueda', () {
    test('neumáticos: aro, talón y tubeless salen de su propia ficha', () {
      // La necesidad real que el dueño abrió en la app.
      expect(
        _derivados('2 neumáticos aro 29 para reposición', _tire,
            stored: _guardadaNeumatico),
        <String>{'wheel_size=29"'},
      );
      expect(
        _derivados('neumático 27.5 talón de alambre', _tire,
            stored: _guardadaNeumatico),
        <String>{'wheel_size=27.5"', 'tire_bead_type=Talón de alambre'},
      );
      expect(
        _derivados('neumático 700c tubeless', _tire,
            stored: _guardadaNeumatico),
        <String>{'wheel_size=700c', 'tire_tubeless_ready=true'},
      );
    });

    test('motor de centro: sin aro, con frases compuestas', () {
      // **La necesidad real que existe en producción.** «Sellado» nombra un
      // solo valor de `bb_construction`, así que lo dice; «eje cuadrado» nombra
      // DOS —`Cuadrado JIS` y `Cuadrado ISO`—, así que no elige, que es no
      // saber.
      expect(
        _derivados('Motor de centro sellado con eje cuadrado', _bb,
            stored: _guardadaMotor),
        <String>{'bb_construction=Rodamiento sellado'},
      );
      expect(
        _derivados('eje de motor sellado caja inglesa', _bb,
            stored: _guardadaMotor),
        <String>{
          'bb_shell_standard=BSA / Caja inglesa 34,8 mm (1.37") x 24',
          'bb_construction=Rodamiento sellado',
        },
      );
    });

    test('la pareja de un motor se reparte por los valores de la ficha', () {
      // **La necesidad real que existe en producción.** `73 x 118` es
      // inequívoco dentro de esta familia: 73 es un ancho de caja y no un largo
      // de eje; 118 es un largo de eje y no un ancho de caja. Lo decide la
      // ficha, no un orden fijo — por eso también funciona al revés.
      expect(
        _derivados('Motor de centro 73 x 118 mm', _bb, stored: _guardadaMotor),
        <String>{'bb_shell_width_mm=73', 'spindle_length_mm=118'},
      );
      expect(
        _derivados('eje de motor sellado 68 x 113', _bb,
            stored: _guardadaMotor),
        <String>{
          'bb_construction=Rodamiento sellado',
          'bb_shell_width_mm=68',
          'spindle_length_mm=113',
        },
      );
      expect(
        _derivados('motor de centro 118 x 73', _bb, stored: _guardadaMotor),
        <String>{'bb_shell_width_mm=73', 'spindle_length_mm=118'},
        reason: 'el reparto no depende del orden, sino de los valores',
      );
    });

    test('una pareja que la ficha no sabe repartir no se inventa', () {
      // Ninguno de los dos números pertenece a un campo de esta ficha.
      expect(
        _derivados('motor de centro 12 x 15', _bb, stored: _guardadaMotor),
        isEmpty,
      );
    });

    test('y «eje» no declara que el producto traiga el eje', () {
      // `Incluye eje` deja una sola palabra corta y genérica: con ella, «con
      // eje cuadrado» —que describe la interfaz— y hasta el nombre `Eje De
      // Motor Sellado` quedaban declarados como «trae el eje».
      for (final texto in const <String>[
        'Motor de centro sellado con eje cuadrado',
        'eje de motor sellado 68 x 113',
      ]) {
        expect(
          _derivados(texto, _bb, stored: _guardadaMotor),
          isNot(contains('includes_spindle=true')),
          reason: texto,
        );
      }
    });

    test('un número de motor no es un aro', () {
      // `68 X 113` tiene la forma exacta de una medida de rueda y aquí no lo
      // es: esta ficha no ofrece `wheel_size`, así que ese campo no existe. Lo
      // que sí existe se llena, no se descarta.
      final ficha = _derivados('eje de motor sellado 68 x 113', _bb,
          stored: _guardadaMotor);
      expect(ficha.where((p) => p.startsWith('wheel_size')), isEmpty);
      expect(ficha, contains('bb_shell_width_mm=68'));
    });
  });

  group('lo que NO debe inventar', () {
    test('una petición sin datos técnicos no rinde criterios', () {
      for (final texto in const <String>[
        'necesito camaras',
        'Motor de centro sellado con eje cuadrado',
        'repuestos varios para el taller',
      ]) {
        expect(_derivados(texto, _tube), isEmpty, reason: texto);
      }
    });

    test('un número que no es una medida no se lee', () {
      for (final texto in const <String>[
        'cámaras para el taller, presupuesto 700 pesos',
        'cámaras código 700 del proveedor',
        'llevar 32 cámaras al taller',
      ]) {
        expect(_derivados(texto, _tube), isEmpty, reason: texto);
      }
    });

    test('la válvula sigue exigiendo su marcador, aunque la palabra esté', () {
      // **El contrato de la válvula no se salta por la puerta de atrás.**
      // `Dunlop`, `americana` y `francesa` son palabras de los valores de
      // `valve_type`, así que una lectura por palabra única las declararía
      // aunque nadie escribiera `V/`, `VALVULA` ni `F/V`. Y `Dunlop` es una
      // MARCA: `CAMARA DUNLOP 700X25C` no dice nada de su válvula.
      for (final texto in const <String>[
        'CAMARA DUNLOP 700X25C',
        'cámara 700 marca americana',
        'cámara 700 hecha en francesa',
      ]) {
        expect(
          _derivados(texto, _tube).where((p) => p.startsWith('valve_type')),
          isEmpty,
          reason: texto,
        );
      }
      // Con marcador sí, que es el camino que siempre valió.
      expect(_derivados('CAMARA 700 V/DUNLOP', _tube),
          contains('valve_type=Dunlop (inglesa)'));
      expect(_derivados('cámara 700 válvula americana', _tube),
          contains('valve_type=Schrader (americana / auto)'));
    });

    test('los comodines de la ficha nunca son un criterio', () {
      // «Otra», «Otro» y «Desconocido» son la forma que tiene la ficha de decir
      // «no consta». Derivarlos convertiría la ignorancia en criterio, y además
      // cazarían cualquier «otro» de una frase corriente.
      for (final texto in const <String>[
        'cámaras y otro material para el taller',
        'cámaras de material desconocido',
        'llantas de otra medida',
      ]) {
        expect(_derivados(texto, _rim, stored: _guardadaLlanta), isEmpty,
            reason: texto);
        expect(_derivados(texto, _tube), isEmpty, reason: texto);
      }
    });

    test('dos valores del mismo campo se cancelan, no se elige uno', () {
      expect(
        _derivados('llanta aluminio o carbono, da lo mismo', _rim,
            stored: _guardadaLlanta),
        isEmpty,
      );
      expect(
        _derivados('disco centerlock o 6 pernos', _rotor,
            stored: _guardadaRotor),
        <String>{},
      );
    });

    test('un valor explícito guardado gana sobre el de la petición', () {
      const explicita = SupplyNeedCriteria(
        predicates: <SupplyNeedPredicate>[
          SupplyNeedPredicate(
            field: 'wheel_size',
            operator: 'eq',
            values: <Object>['650b'],
          ),
        ],
        categoryId: 'cat',
        revisionNo: 5,
      );
      expect(
        _derivados('Cámaras 700', _tube, stored: explicita),
        <String>{'wheel_size=650b'},
      );
      // Y no borra lo que la petición aporta en OTRO campo.
      expect(
        _derivados('Cámaras 700 válvula francesa', _tube, stored: explicita),
        <String>{'wheel_size=650b', 'valve_type=Presta (francesa)'},
      );
    });
  });

  /// **Dónde está el límite ahora.** Un número es una medida cuando va pegado
  /// al sustantivo que nombra el objeto y es uno de los tamaños que la ficha
  /// ofrece. Lo que queda fuera no es «un número con palabras al lado»: es un
  /// número que pertenece a otro tema —un presupuesto, un código, una
  /// cantidad— o que la ficha no reconoce como medida.
  group('el límite está en el contexto, no en la puntuación', () {
    test('el número pegado al objeto es su medida', () {
      expect(_derivados('Cámaras 29 con válvula Schrader', _tube),
          contains('wheel_size=29"'));
      expect(_derivados('Cámaras aro 29', _tube), contains('wheel_size=29"'));
      expect(_derivados('llanta 700c', _rim, stored: _guardadaLlanta),
          contains('wheel_size=700c'));
    });

    test('cantidad y dinero no son medidas', () {
      // El número está pegado al objeto igual que en «Cámaras 29», y no es una
      // medida: lo dice la palabra que viene DESPUÉS.
      expect(_derivados('Cámaras 29 unidades', _tube), isEmpty);
      expect(_derivados('Cámaras 700 pesos', _tube), isEmpty);
      expect(_derivados('Cámaras 29 und para el taller', _tube), isEmpty);
    });

    test('«Cámaras para aro 29» y «Cámaras 29 …» abren las dos con 29', () {
      expect(
          _derivados('Cámaras para aro 29', _tube), contains('wheel_size=29"'));
      expect(_derivados('Cámaras 29 con válvula Schrader', _tube),
          contains('wheel_size=29"'));
    });

    test('en discos el diámetro sale de la familia y la ficha, sin mm', () {
      expect(
        _derivados('disco 180', _rotor, stored: _guardadaRotor),
        contains('rotor_diameter_mm=180'),
      );
      expect(
        _derivados('disco de freno 160 centerlock', _rotor,
            stored: _guardadaRotor),
        contains('rotor_diameter_mm=160'),
      );
    });

    test('los booleanos claros de la ficha se declaran, y la negación también',
        () {
      // La palabra viene de la ETIQUETA del campo, que es vocabulario de la
      // ficha. `Trae líquido sellante` aporta `sellante`, y lo reconoce dentro
      // de `autosellante`.
      expect(_derivados('cámara 700 autosellante', _tube),
          contains('tube_has_sealant=true'));
      expect(_derivados('cámara 700 sin sellante', _tube),
          contains('tube_has_sealant=false'));
      expect(
        _derivados('aro 29 tubeless de 32 hoyos', _rim,
            stored: _guardadaLlanta),
        contains('rim_tubeless_ready=true'),
      );
      expect(
        _derivados('disco de freno 160 flotante', _rotor,
            stored: _guardadaRotor),
        contains('rotor_floating=true'),
      );
    });

    test('la negación se lee aunque no esté pegada a la palabra', () {
      // «no autosellante» y «sin líquido sellante»: en el primero la palabra
      // inmediata anterior es `auto` —parte de la misma palabra—, y en el
      // segundo es `líquido`. La negación está más atrás, y niega igual.
      for (final texto in const <String>[
        'cámara 700 no autosellante',
        'cámara 700 sin líquido sellante',
        'cámara 700 sin sellante',
        'cámara 700 sin autosellante',
      ]) {
        expect(_derivados(texto, _tube), contains('tube_has_sealant=false'),
            reason: texto);
      }
      for (final texto in const <String>[
        'cámara 700 autosellante',
        'cámara 700 con líquido sellante',
        'cámara 700 anti-pinchazo',
      ]) {
        expect(_derivados(texto, _tube), contains('tube_has_sealant=true'),
            reason: texto);
      }
    });

    test(
        'la frase completa de la etiqueta vale, aunque sus palabras sean '
        'cortas', () {
      // `Incluye missing link` no tiene ninguna palabra larga y distintiva,
      // pero la frase sí lo es. Cortar por número de letras dejaba mudo un
      // campo que la ficha nombra sin ambigüedad.
      expect(
        _derivados('cadena 11 velocidades con missing link', _chain,
            stored: _guardadaCadena),
        contains('quick_link_included=true'),
      );
      expect(
        _derivados('cadena 11 velocidades sin missing link', _chain,
            stored: _guardadaCadena),
        contains('quick_link_included=false'),
      );
    });

    test('una coma no salta el guard de cantidad', () {
      expect(_derivados('Cámaras 29, unidades', _tube),
          isNot(contains('wheel_size=29"')));
      // Y una coma que sólo separa cláusulas no borra la medida.
      expect(_derivados('Cámaras 29, con válvula Schrader', _tube),
          contains('wheel_size=29"'));
    });

    test('un booleano sin palabra propia se queda mudo, no se adivina', () {
      // **Un sinónimo que la ficha no tiene, no se inventa.** El operador dirá
      // «quick link», pero la ficha se llama «missing link»: la respuesta
      // correcta es agregar el sinónimo AL CAMPO, no cablearlo acá.
      expect(
        _derivados('cadena 11 velocidades con quick link', _chain,
            stored: _guardadaCadena),
        isNot(contains('quick_link_included=true')),
      );
    });

    test('el número de otro tema no lo es, aunque el objeto esté nombrado', () {
      // Entre el sustantivo y el número hay otro asunto, o el número va antes.
      for (final texto in const <String>[
        'cámaras código 700 del proveedor',
        'cámaras para el taller, presupuesto 700 pesos',
        'llevar 32 cámaras al taller',
      ]) {
        expect(_derivados(texto, _tube), isEmpty, reason: texto);
      }
    });

    test('un número que la ficha no reconoce como medida no se inventa', () {
      // No existe un aro 28 en la ficha, así que `LLANTA 28 VISION` no declara
      // medida por esta vía —y tampoco se le fuerza una parecida—.
      expect(_derivados('llanta 28 vision', _rim, stored: _guardadaLlanta),
          isEmpty);
    });
  });

  _pruebasDeSobrevivientes();
}

// ---------------------------------------------------------------------------
// La otra mitad: qué SOBREVIVE.
//
// Un criterio derivado que no cambia el listado no sirve de nada, y un conteo
// no dice cuál sobrevivió. Acá se juzgan filas con **nombres reales del catálogo
// de esta tienda** y se afirma el conjunto por su nombre.
// ---------------------------------------------------------------------------

SupplierNeedPortalAdapter _adapter() =>
    SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
      'version': 1,
      'generic_family_search': true,
      'result_schema': <String, dynamic>{
        'columns': <String, dynamic>{
          'code': <String>['Código'],
          'name': <String>['Descripción'],
          'price': <String>['Valor'],
        },
      },
      'catalog_route': <String, dynamic>{
        'url_template': 'http://x/?n={node}&p={page}&s={page_size}',
        'page_size': 50,
      },
    });

/// Llantas reales de la tienda.
const _llantas = <String>[
  'Alexrims Llanta MD30 SSE 27.5" 28h',
  'LLANTA 24 X 1.75 BUFFALO T/EXPLORER COLOR (36H)',
  'LLANTA 26 VISION ALUMINIO NEGRA  DOBLE PARED 32H',
  'LLANTA 26 X 1.75 MTB C.P. 36H. 7 X REFORZADA',
  'LLANTA 27,5 NEGRA ALUMINIO DOBLE PARED 32 Hoyos (economica)',
  'LLANTA 27.5 TLR 21 ( C/U ) BLACK JACK NEGRA 28H',
  'LLANTA 28 VISION ALUMINIO NEGRA  DOBLE PARED 32H (700)',
  'LLANTA 29 DP-30 NEGRA TR 622X30MM. 32H. A V.',
  'LLANTA 29 NEGRA DOBLE PARED ALUMINIO 36 H',
];

/// Cadenas reales de la tienda.
const _cadenas = <String>[
  'Cadena 1/2 X 1/8 Kmc Hv410 Gris/cafe Bolsa',
  'Cadena 1/2 X 1/8 Kmc K710 Negra/cromada',
  'CADENA 1/2 X 3/32 116 E 6VEL DARK SILVE KMC',
  'CADENA 1/2 X 3/32 116 E 8 VEL. Z8.3 DISPLAY KMC',
  'Cadena 1/2 X 3/32 Kmc Hv408 Plata',
  'Cadena 1/2" X 3/32" Kmc X8 Plata/Gris',
];

List<SupplierPortalCatalogCandidate> _filas(List<String> nombres) =>
    <SupplierPortalCatalogCandidate>[
      for (var index = 0; index < nombres.length; index += 1)
        SupplierPortalCatalogCandidate(
          code: '${index + 1}',
          name: nombres[index],
          priceNet: 1000 + index.toDouble(),
          rowText: nombres[index],
        ),
    ];

/// Los nombres que quedan vivos bajo la ficha efectiva de esa petición.
Set<String> _sobreviven({
  required String description,
  required String technicalFamily,
  required String categoryPath,
  required List<SupplierNeedSearchField> fields,
  required List<String> nombres,
}) {
  final efectiva = effectiveSupplyNeedCriteria(
    stored: SupplyNeedCriteria(
      predicates: const <SupplyNeedPredicate>[],
      categoryId: 'cat',
      revisionNo: 1,
      technicalFamily: technicalFamily,
    ),
    texts: <String>[description],
    fields: fields,
  );
  final plan = buildSupplierNeedSearchPlan(
    request: SupplierNeedSearchRequest(
      needId: 'need',
      description: description,
      categoryId: 'cat',
      categoryPath: categoryPath,
      technicalFamily: technicalFamily,
      fields: fields,
      predicates: efectiva.predicates
          .map((predicate) => SupplierNeedSearchPredicate(
                field: predicate.field,
                operator: predicate.operator,
                values: predicate.values,
              ))
          .toList(growable: false),
    ),
    adapter: _adapter(),
    maxLength: 20,
  )!;
  return matchSupplierNeedCandidates(plan, _filas(nombres))
      .where((match) => match.state != SupplierNeedMatchState.conflict)
      .map((match) => match.candidate.name)
      .toSet();
}

void _pruebasDeSobrevivientes() {
  group('la ficha derivada cambia de verdad el conjunto', () {
    Set<String> llantas(String description) => _sobreviven(
          description: description,
          technicalFamily: 'rim',
          categoryPath: 'Componentes / Ruedas / Llantas',
          fields: _rim,
          nombres: _llantas,
        );

    test('«llantas» sin medida deja pasar todas, que es el defecto de origen',
        () {
      expect(llantas('llantas para el taller').length, _llantas.length);
    });

    test('«Aro 29» elimina las que declaran otra medida, y sólo ésas', () {
      // **Ninguna 26 ni 27.5 sobrevive.** Las tres que quedan son las dos 29 y
      // la única que no declara medida: `LLANTA 28 VISION … (700)` — no existe
      // un aro 28 en la ficha, así que el número no es una medida que ella
      // reconozca, y una ausencia no elimina.
      expect(llantas('Aro 29 para reposición'), <String>{
        'LLANTA 29 DP-30 NEGRA TR 622X30MM. 32H. A V.',
        'LLANTA 29 NEGRA DOBLE PARED ALUMINIO 36 H',
        'LLANTA 28 VISION ALUMINIO NEGRA  DOBLE PARED 32H (700)',
      });
      for (final fuera in const <String>[
        'LLANTA 26 VISION ALUMINIO NEGRA  DOBLE PARED 32H',
        'LLANTA 26 X 1.75 MTB C.P. 36H. 7 X REFORZADA',
        'LLANTA 27,5 NEGRA ALUMINIO DOBLE PARED 32 Hoyos (economica)',
        'LLANTA 27.5 TLR 21 ( C/U ) BLACK JACK NEGRA 28H',
        'Alexrims Llanta MD30 SSE 27.5" 28h',
        'LLANTA 24 X 1.75 BUFFALO T/EXPLORER COLOR (36H)',
      ]) {
        expect(llantas('Aro 29 para reposición'), isNot(contains(fuera)),
            reason: fuera);
      }
    });

    test('la 29 con su medida en ETRTO no se elimina por error', () {
      // `622X30MM` es el MISMO aro escrito en milímetros. Leerlo como una
      // medida francesa de tres dígitos hacía que `622` contradijera `29"` y
      // sacaba del listado una llanta correcta: una exclusión falsa, peor que
      // no saber.
      expect(
        llantas('Aro 29 para reposición'),
        contains('LLANTA 29 DP-30 NEGRA TR 622X30MM. 32H. A V.'),
      );
    });

    test('«aro 26 de 32 hoyos» cruza dos criterios derivados', () {
      // Cada criterio elimina por su lado: las de 36H y 28H se van por radios,
      // las 24, 27.5 y 29 por medida. Queda la 26 que dice 32H, y la única que
      // no declara medida y sí dice 32H.
      expect(llantas('aro 26 de 32 hoyos'), <String>{
        'LLANTA 26 VISION ALUMINIO NEGRA  DOBLE PARED 32H',
        'LLANTA 28 VISION ALUMINIO NEGRA  DOBLE PARED 32H (700)',
      });
    });

    test('precisar el aro cambia el conjunto, no sólo el número', () {
      final veinticuatro = llantas('aro 24');
      final veintiseis = llantas('aro 26');
      expect(veinticuatro, isNot(equals(veintiseis)));
      // La 24 real sobrevive a «aro 24» y muere con «aro 26»; la 26 al revés.
      const laVeinticuatro = 'LLANTA 24 X 1.75 BUFFALO T/EXPLORER COLOR (36H)';
      const laVeintiseis = 'LLANTA 26 X 1.75 MTB C.P. 36H. 7 X REFORZADA';
      expect(veinticuatro, contains(laVeinticuatro));
      expect(veinticuatro, isNot(contains(laVeintiseis)));
      expect(veintiseis, contains(laVeintiseis));
      expect(veintiseis, isNot(contains(laVeinticuatro)));
    });

    /// Cámaras reales de RBX, de la corrida del 2026-08-30.
    const camaras = <String>[
      'CAMARA 26 X 1.3/8 V/AUTO 33MM',
      'CAMARA 27.5 X 1.25/1.50 AV48 EN CAJA',
      'CAMARA 700 X 18/25C V/AUTO 60MM',
      'CAMARA 700 X 18/25C V/FRANCESA 48MM CAJA',
      'CAMARA 700 X 28/38C V/AUTO 48MM (28-5/8-1/4)',
      'CAMARA 700 X 38/45C V/AMERICANA 48MM (28-5/8-1/4)',
      'CAMARA CARRETILLA 350 X 8 A/V TR87',
      'CAMARA SCOOTER 10 X 2.125 VALVULA SCHRADER CURVA 9',
      // Una 29 real de esta tienda, con válvula Auto: el conjunto vacío sólo
      // prueba exclusión, no que el candidato correcto sobreviva.
      'CAMARA MAXXIS 29X1.75/2.40 A/V 48MM',
    ];

    Set<String> tubos(String description) => _sobreviven(
          description: description,
          technicalFamily: 'tube',
          categoryPath: 'Componentes / Ruedas / Cámaras',
          fields: _tube,
          nombres: camaras,
        );

    test('«Cámaras 700» deja las 700 y bota scooter, carretilla y otras', () {
      expect(tubos('Cámaras 700'), <String>{
        'CAMARA 700 X 18/25C V/AUTO 60MM',
        'CAMARA 700 X 18/25C V/FRANCESA 48MM CAJA',
        'CAMARA 700 X 28/38C V/AUTO 48MM (28-5/8-1/4)',
        'CAMARA 700 X 38/45C V/AMERICANA 48MM (28-5/8-1/4)',
      });
    });

    test('el conjunto no se degrada al mover orden, sinónimo ni relleno', () {
      // **La misma pregunta escrita como la diría cualquiera.** Si el conjunto
      // cambiara con el orden de las palabras, la regla sería un truco.
      final base = tubos('Cámaras 700');
      for (final variante in const <String>[
        'Cámaras aro 700',
        'Cámaras para aro 700',
        'cámara 700 para reposición del taller',
        'necesito cámaras 700, urgente, las de siempre',
        'CAMARAS 700',
      ]) {
        expect(tubos(variante), base, reason: variante);
      }
    });

    test('«Cámaras 29 con válvula Schrader» deja exactamente la 29 A/V', () {
      expect(tubos('Cámaras 29 con válvula Schrader'), <String>{
        'CAMARA MAXXIS 29X1.75/2.40 A/V 48MM',
      });
    });

    test('y con válvula francesa esa misma fila se cae', () {
      // Cambiar sólo la válvula cambia el conjunto: la 29 que queda es Auto.
      expect(tubos('Cámaras 29 con válvula francesa'), isEmpty);
    });

    test('y «Cámaras 29 unidades» no es una medida: no acota nada', () {
      expect(tubos('Cámaras 29 unidades').length, camaras.length);
    });

    /// Rotores reales de la tienda.
    const discos = <String>[
      'Disco de Freno 160mm G3 TANKE',
      'Disco de Freno Flotante 180mm Cyclami',
      'Disco freno Shimano Deore RT56 160MM',
      'Disco freno Shimano Deore RT56 180MM',
      'Disco freno SRAM 160MM Acero Inoxidable',
      'ROTOR FRENO DISCO SHIMANO SM-RT10 160MM (BOLSA)',
    ];

    Set<String> rotores(String description) => _sobreviven(
          description: description,
          technicalFamily: 'rotor',
          categoryPath: 'Componentes / Frenos / Discos',
          fields: _rotor,
          nombres: discos,
        );

    test('«disco de freno 160» deja los 160 y bota los 180', () {
      expect(rotores('disco de freno 160'), <String>{
        'Disco de Freno 160mm G3 TANKE',
        'Disco freno Shimano Deore RT56 160MM',
        'Disco freno SRAM 160MM Acero Inoxidable',
        'ROTOR FRENO DISCO SHIMANO SM-RT10 160MM (BOLSA)',
      });
    });

    test('«disco de freno 180» deja exactamente los otros dos', () {
      final ciensesenta = rotores('disco de freno 160');
      final cienochenta = rotores('disco de freno 180');
      expect(cienochenta, <String>{
        'Disco de Freno Flotante 180mm Cyclami',
        'Disco freno Shimano Deore RT56 180MM',
      });
      expect(ciensesenta.intersection(cienochenta), isEmpty);
      expect(ciensesenta.union(cienochenta).length, discos.length);
    });

    /// Neumáticos reales de la tienda.
    const neumaticos = <String>[
      'MAXXIS ALAMBRE 26X2.20 IKON',
      'MAXXIS ALAMBRE 27.5X2.25 REKON RACE',
      'MAXXIS ALAMBRE 29X2.20 ARDENT RACE',
      'MAXXIS ALAMBRE 29X2.25 W FOREKASTER',
      'MAXXIS ALAMBRE 29X2.35 FOREKASTER',
      'MAXXIS ALAMBRE 700x25c DETONATOR',
    ];

    Set<String> gomas(String description) => _sobreviven(
          description: description,
          technicalFamily: 'tire',
          categoryPath: 'Componentes / Ruedas / Neumáticos',
          fields: _tire,
          nombres: neumaticos,
        );

    test('«neumáticos aro 29» deja los tres 29 y ningún otro', () {
      expect(gomas('2 neumáticos aro 29 para reposición'), <String>{
        'MAXXIS ALAMBRE 29X2.20 ARDENT RACE',
        'MAXXIS ALAMBRE 29X2.25 W FOREKASTER',
        'MAXXIS ALAMBRE 29X2.35 FOREKASTER',
      });
    });

    test('y aro 26, 27.5 y 700 parten el resto sin solaparse', () {
      final veintiseis = gomas('neumático aro 26');
      final veintisiete = gomas('neumático aro 27.5');
      final setecientos = gomas('neumático 700c');
      expect(veintiseis, <String>{'MAXXIS ALAMBRE 26X2.20 IKON'});
      expect(veintisiete, <String>{'MAXXIS ALAMBRE 27.5X2.25 REKON RACE'});
      expect(setecientos, <String>{'MAXXIS ALAMBRE 700x25c DETONATOR'});
      expect(
        veintiseis.union(veintisiete).union(setecientos).union(
              gomas('2 neumáticos aro 29 para reposición'),
            ),
        neumaticos.toSet(),
        reason: 'las cuatro medidas cubren el catálogo entero',
      );
    });

    /// Motores de centro reales de la tienda.
    const motores = <String>[
      'CUBETA DE MOTOR SHIMANO BB-UN300, SPINDLE:SQUARE TYPE, SHELL:BSA 68MM',
      'Cubetas De Motor TSC Stacked MID 22mm Rojo',
      'Eje De Motor Sellado 68 X 113mm Negro',
      'Eje De Motor Sellado 68 X 122.5mm ZTTO AE',
      'Eje de Motor Sellado Ozono 125.5mm - 73mm',
    ];

    Set<String> motorDeCentro(String description) => _sobreviven(
          description: description,
          technicalFamily: 'bottom_bracket',
          categoryPath: 'Transmisión / Motor',
          fields: _bb,
          nombres: motores,
        );

    test('la pareja también juzga el catálogo, fila por fila', () {
      // El nombre real trae la pareja igual que la petición, así que el
      // criterio elimina de verdad: 122.5 no es 113.
      final vivos = motorDeCentro('Motor de centro sellado 68 x 113');
      expect(vivos, contains('Eje De Motor Sellado 68 X 113mm Negro'));
      expect(
          vivos, isNot(contains('Eje De Motor Sellado 68 X 122.5mm ZTTO AE')));
      // La Ozono escribe `125.5mm - 73mm`, sin `x`: no forma pareja, no declara
      // y por lo tanto no se elimina. Una ausencia sigue sin eliminar.
      expect(vivos, contains('Eje de Motor Sellado Ozono 125.5mm - 73mm'));
    });

    test('«motor de centro sellado» elimina la cubeta que se declara cubeta',
        () {
      // El criterio derivado es `bb_construction = Rodamiento sellado`. La
      // `Cubetas De Motor TSC` se elimina porque su propio nombre dice
      // `Cubetas`, que en esta ficha nombra un solo valor —`Cubetas y
      // canastillo`— y contradice.
      //
      // La `CUBETA DE MOTOR SHIMANO` **sobrevive**, y está bien: dice `CUBETA`
      // en singular, que no es la palabra de la ficha, así que no declara
      // construcción. Una ausencia no elimina — es la regla del módulo, y acá
      // se ve en una familia que no tiene nada que ver con ruedas.
      final vivos = motorDeCentro('Motor de centro sellado con eje cuadrado');
      expect(vivos, <String>{
        'Eje De Motor Sellado 68 X 113mm Negro',
        'Eje De Motor Sellado 68 X 122.5mm ZTTO AE',
        'Eje de Motor Sellado Ozono 125.5mm - 73mm',
        'CUBETA DE MOTOR SHIMANO BB-UN300, SPINDLE:SQUARE TYPE, SHELL:BSA 68MM',
      });
      expect(
          vivos, isNot(contains('Cubetas De Motor TSC Stacked MID 22mm Rojo')));
    });

    Set<String> cadenas(String description) => _sobreviven(
          description: description,
          technicalFamily: 'chain',
          categoryPath: 'Transmisión / Cadenas',
          fields: _chain,
          nombres: _cadenas,
        );

    test('«cadena 1/8» deja las de 1/8 y descarta las 3/32', () {
      expect(cadenas('cadena para bmx 1/8'), <String>{
        'Cadena 1/2 X 1/8 Kmc Hv410 Gris/cafe Bolsa',
        'Cadena 1/2 X 1/8 Kmc K710 Negra/cromada',
      });
    });

    test('y «cadena 3/32» deja exactamente las otras', () {
      final unOctavo = cadenas('cadena para bmx 1/8');
      final tresTreintaidos = cadenas('cadena 3/32');
      expect(unOctavo.intersection(tresTreintaidos), isEmpty);
      expect(
        unOctavo.union(tresTreintaidos).length,
        _cadenas.length,
        reason: 'entre las dos cubren el catálogo, sin solaparse',
      );
    });
  });
}
