import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';

/// Camina la cascada completa del pedalier con el evaluador real.
///
/// El defecto que motivo esta prueba: `bb_construction` se ofrecia sin que la
/// caja del cuadro estuviera contestada, asi que una caja Pressfit podia
/// quedar marcada como «Rodamiento sellado», que no existe. El acotado de
/// opciones estaba implementado y el compuerteo casi no; la unica forma de que
/// eso no vuelva es recorrer las 15 cajas en vez de revisar campo por campo.
///
/// El grafo de aca es el mismo que despliega
/// `20260820270000_bottom_bracket_cascade_graph.sql`. Que la base tenga
/// exactamente estas reglas lo afirma
/// `verify_bottom_bracket_cascade_graph.sql`; lo que se prueba aca es la
/// semantica: que ninguna combinacion alcanzable quede sin salida y que ningun
/// campo termine ofreciendo su vocabulario entero.
const String _graphJson = r'''
{
  "bb_shell_standard": {
    "visibility_rules": [],
    "option_rules": []
  },
  "bb_construction": {
    "visibility_rules": [
      {
        "field": "bb_shell_standard",
        "operator": "is_set"
      }
    ],
    "option_rules": [
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BSA / Caja inglesa 34,8 mm (1.37\") x 24",
          "Italiano 36 mm x 24",
          "T47 47 mm",
          "Francés 35 mm x 1",
          "Suizo 35 mm x 1",
          "Euro BMX roscado 68 mm"
        ],
        "allow": [
          "Rodamiento sellado",
          "Integrado",
          "Cubetas y canastillo"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BB86 / BB92 41 mm",
          "PF30 46 mm",
          "BB30 42 mm",
          "BB386EVO 46 mm",
          "BB90 / BB95",
          "BBRight / OSBB"
        ],
        "allow": [
          "A presión",
          "Roscado entre sí"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "Mid BMX 41,2 mm",
          "Spanish BMX 37 mm"
        ],
        "allow": [
          "Rodamiento sellado",
          "A presión"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "Americano 51,5 mm"
        ],
        "allow": [
          "Cubetas y canastillo"
        ]
      }
    ]
  },
  "includes_spindle": {
    "visibility_rules": [
      {
        "field": "bb_construction",
        "operator": "is_set"
      }
    ],
    "option_rules": []
  },
  "spindle_interface": {
    "visibility_rules": [
      {
        "field": "includes_spindle",
        "operator": "eq",
        "value": true
      }
    ],
    "option_rules": [
      {
        "field": "bb_construction",
        "operator": "eq",
        "value": "Rodamiento sellado",
        "allow": [
          "Cuadrado JIS",
          "Cuadrado ISO",
          "ISIS",
          "Octalink",
          "Powerspline",
          "BMX 19mm",
          "BMX 22mm",
          "BMX 24mm"
        ]
      },
      {
        "field": "bb_construction",
        "operator": "eq",
        "value": "Integrado",
        "allow": [
          "Hollowtech / 24mm",
          "SRAM GXP 24/22",
          "SRAM DUB 28.99mm"
        ]
      },
      {
        "field": "bb_construction",
        "operator": "eq",
        "value": "Cubetas y canastillo",
        "allow": [
          "Cuadrado JIS",
          "Cuadrado ISO",
          "Con chaveta",
          "One-piece / americano"
        ]
      },
      {
        "field": "bb_construction",
        "operator": "in",
        "value": [
          "A presión",
          "Roscado entre sí"
        ],
        "allow": [
          "Hollowtech / 24mm",
          "SRAM DUB 28.99mm",
          "BB30 30mm",
          "SRAM GXP 24/22",
          "BMX 19mm",
          "BMX 22mm",
          "BMX 24mm"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BSA / Caja inglesa 34,8 mm (1.37\") x 24",
          "Italiano 36 mm x 24",
          "T47 47 mm",
          "Francés 35 mm x 1",
          "Suizo 35 mm x 1",
          "Euro BMX roscado 68 mm"
        ],
        "allow": [
          "Cuadrado JIS",
          "Cuadrado ISO",
          "ISIS",
          "Octalink",
          "Powerspline",
          "Con chaveta",
          "Hollowtech / 24mm",
          "SRAM GXP 24/22",
          "SRAM DUB 28.99mm"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BB86 / BB92 41 mm",
          "PF30 46 mm",
          "BB30 42 mm",
          "BB386EVO 46 mm",
          "BB90 / BB95",
          "BBRight / OSBB"
        ],
        "allow": [
          "Hollowtech / 24mm",
          "SRAM DUB 28.99mm",
          "BB30 30mm",
          "SRAM GXP 24/22"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "Mid BMX 41,2 mm",
          "Spanish BMX 37 mm"
        ],
        "allow": [
          "BMX 19mm",
          "BMX 22mm",
          "BMX 24mm"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "Americano 51,5 mm"
        ],
        "allow": [
          "One-piece / americano"
        ]
      }
    ]
  },
  "spindle_interface_accepted": {
    "visibility_rules": [
      {
        "field": "includes_spindle",
        "operator": "eq",
        "value": false
      }
    ],
    "option_rules": [
      {
        "field": "bb_construction",
        "operator": "eq",
        "value": "Integrado",
        "allow": [
          "Hollowtech / 24mm",
          "SRAM GXP 24/22",
          "SRAM DUB 28.99mm"
        ]
      },
      {
        "field": "bb_construction",
        "operator": "in",
        "value": [
          "A presión",
          "Roscado entre sí"
        ],
        "allow": [
          "Hollowtech / 24mm",
          "SRAM DUB 28.99mm",
          "BB30 30mm",
          "SRAM GXP 24/22",
          "BMX 19mm",
          "BMX 22mm",
          "BMX 24mm"
        ]
      },
      {
        "field": "bb_construction",
        "operator": "eq",
        "value": "Rodamiento sellado",
        "allow": [
          "Cuadrado JIS",
          "Cuadrado ISO",
          "ISIS",
          "Octalink",
          "Powerspline",
          "BMX 19mm",
          "BMX 22mm",
          "BMX 24mm"
        ]
      },
      {
        "field": "bb_construction",
        "operator": "eq",
        "value": "Cubetas y canastillo",
        "allow": [
          "Cuadrado JIS",
          "Cuadrado ISO",
          "Con chaveta",
          "One-piece / americano"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BSA / Caja inglesa 34,8 mm (1.37\") x 24",
          "Italiano 36 mm x 24",
          "T47 47 mm",
          "Francés 35 mm x 1",
          "Suizo 35 mm x 1",
          "Euro BMX roscado 68 mm"
        ],
        "allow": [
          "Cuadrado JIS",
          "Cuadrado ISO",
          "ISIS",
          "Octalink",
          "Powerspline",
          "Con chaveta",
          "Hollowtech / 24mm",
          "SRAM GXP 24/22",
          "SRAM DUB 28.99mm"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BB86 / BB92 41 mm",
          "PF30 46 mm",
          "BB30 42 mm",
          "BB386EVO 46 mm",
          "BB90 / BB95",
          "BBRight / OSBB"
        ],
        "allow": [
          "Hollowtech / 24mm",
          "SRAM DUB 28.99mm",
          "BB30 30mm",
          "SRAM GXP 24/22"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "Mid BMX 41,2 mm",
          "Spanish BMX 37 mm"
        ],
        "allow": [
          "BMX 19mm",
          "BMX 22mm",
          "BMX 24mm"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "Americano 51,5 mm"
        ],
        "allow": [
          "One-piece / americano"
        ]
      }
    ]
  },
  "bb_cup_thread_pair": {
    "visibility_rules": [
      {
        "field": "bb_construction",
        "operator": "in",
        "value": [
          "Cubetas y canastillo",
          "Integrado"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BSA / Caja inglesa 34,8 mm (1.37\") x 24",
          "Italiano 36 mm x 24",
          "T47 47 mm",
          "Francés 35 mm x 1",
          "Suizo 35 mm x 1",
          "Euro BMX roscado 68 mm"
        ]
      }
    ],
    "option_rules": [
      {
        "field": "bb_shell_standard",
        "operator": "eq",
        "value": "BSA / Caja inglesa 34,8 mm (1.37\") x 24",
        "allow": [
          "Derecha / Izquierda (BSA inglés)"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "Italiano 36 mm x 24",
          "T47 47 mm",
          "Francés 35 mm x 1",
          "Euro BMX roscado 68 mm"
        ],
        "allow": [
          "Derecha / Derecha (italiano o genérico)"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "eq",
        "value": "Suizo 35 mm x 1",
        "allow": [
          "Derecha / Izquierda (BSA inglés)"
        ]
      }
    ]
  },
  "bb_shell_width_mm": {
    "visibility_rules": [
      {
        "field": "bb_shell_standard",
        "operator": "is_set"
      }
    ],
    "option_rules": [
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BSA / Caja inglesa 34,8 mm (1.37\") x 24",
          "T47 47 mm",
          "Euro BMX roscado 68 mm",
          "Francés 35 mm x 1",
          "Suizo 35 mm x 1",
          "BB30 42 mm"
        ],
        "allow": [
          68,
          73,
          83,
          100
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "eq",
        "value": "Italiano 36 mm x 24",
        "allow": [
          70
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BB86 / BB92 41 mm",
          "PF30 46 mm",
          "BB386EVO 46 mm"
        ],
        "allow": [
          86.5,
          89.5,
          92,
          107,
          121
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BB90 / BB95",
          "BBRight / OSBB"
        ],
        "allow": [
          86.5,
          89.5,
          92
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "Mid BMX 41,2 mm",
          "Spanish BMX 37 mm",
          "Americano 51,5 mm"
        ],
        "allow": [
          68,
          73
        ]
      }
    ]
  },
  "bb_shell_diameter_mm": {
    "visibility_rules": [
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BB86 / BB92 41 mm",
          "PF30 46 mm",
          "BB30 42 mm",
          "BB386EVO 46 mm",
          "BB90 / BB95",
          "BBRight / OSBB",
          "Mid BMX 41,2 mm",
          "Spanish BMX 37 mm",
          "Americano 51,5 mm"
        ]
      }
    ],
    "option_rules": [
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BB86 / BB92 41 mm",
          "BB90 / BB95"
        ],
        "allow": [
          41
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "PF30 46 mm",
          "BB386EVO 46 mm",
          "BBRight / OSBB"
        ],
        "allow": [
          42,
          46
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "eq",
        "value": "BB30 42 mm",
        "allow": [
          42
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "eq",
        "value": "Mid BMX 41,2 mm",
        "allow": [
          41.2
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "eq",
        "value": "Spanish BMX 37 mm",
        "allow": [
          37
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "eq",
        "value": "Americano 51,5 mm",
        "allow": [
          51.5
        ]
      }
    ]
  },
  "bb_cup_outer_diameter_mm": {
    "visibility_rules": [
      {
        "field": "bb_construction",
        "operator": "eq",
        "value": "Cubetas y canastillo"
      }
    ],
    "option_rules": [
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BSA / Caja inglesa 34,8 mm (1.37\") x 24",
          "Italiano 36 mm x 24",
          "T47 47 mm",
          "Francés 35 mm x 1",
          "Suizo 35 mm x 1",
          "Euro BMX roscado 68 mm"
        ],
        "allow": [
          34.8,
          35,
          36,
          37
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "eq",
        "value": "Americano 51,5 mm",
        "allow": [
          51.5
        ]
      }
    ]
  },
  "spindle_length_mm": {
    "visibility_rules": [
      {
        "field": "includes_spindle",
        "operator": "eq",
        "value": true
      },
      {
        "field": "spindle_interface",
        "operator": "not_in",
        "value": [
          "Hollowtech / 24mm",
          "SRAM GXP 24/22",
          "SRAM DUB 28.99mm",
          "BB30 30mm",
          "One-piece / americano"
        ]
      }
    ],
    "option_rules": [
      {
        "field": "spindle_interface",
        "operator": "in",
        "value": [
          "Cuadrado JIS",
          "Cuadrado ISO"
        ],
        "allow": [
          103,
          107,
          110,
          110.5,
          113,
          113.5,
          116,
          118,
          118.5,
          119,
          121,
          122.5,
          124,
          124.5,
          125,
          125.5,
          126,
          127,
          127.5,
          128
        ]
      },
      {
        "field": "spindle_interface",
        "operator": "eq",
        "value": "ISIS",
        "allow": [
          108,
          113,
          118
        ]
      },
      {
        "field": "spindle_interface",
        "operator": "eq",
        "value": "Octalink",
        "allow": [
          109,
          113,
          118
        ]
      },
      {
        "field": "spindle_interface",
        "operator": "eq",
        "value": "Powerspline",
        "allow": [
          108,
          113,
          118
        ]
      },
      {
        "field": "spindle_interface",
        "operator": "in",
        "value": [
          "BMX 19mm",
          "BMX 22mm",
          "BMX 24mm"
        ],
        "allow": [
          128,
          131,
          135
        ]
      },
      {
        "field": "spindle_interface",
        "operator": "eq",
        "value": "Con chaveta",
        "allow": [
          127.5,
          131,
          135,
          140,
          145,
          147
        ]
      }
    ]
  },
  "spindle_diameter_mm": {
    "visibility_rules": [
      {
        "field": "includes_spindle",
        "operator": "eq",
        "value": true
      },
      {
        "field": "spindle_interface",
        "operator": "in",
        "value": [
          "BMX 19mm",
          "BMX 22mm",
          "BMX 24mm",
          "Hollowtech / 24mm",
          "SRAM DUB 28.99mm",
          "BB30 30mm",
          "SRAM GXP 24/22"
        ]
      }
    ],
    "option_rules": [
      {
        "field": "spindle_interface",
        "operator": "eq",
        "value": "BMX 19mm",
        "allow": [
          19
        ]
      },
      {
        "field": "spindle_interface",
        "operator": "eq",
        "value": "BMX 22mm",
        "allow": [
          22
        ]
      },
      {
        "field": "spindle_interface",
        "operator": "eq",
        "value": "BMX 24mm",
        "allow": [
          24
        ]
      },
      {
        "field": "spindle_interface",
        "operator": "eq",
        "value": "Hollowtech / 24mm",
        "allow": [
          24
        ]
      },
      {
        "field": "spindle_interface",
        "operator": "eq",
        "value": "SRAM DUB 28.99mm",
        "allow": [
          28.99
        ]
      },
      {
        "field": "spindle_interface",
        "operator": "eq",
        "value": "BB30 30mm",
        "allow": [
          30
        ]
      },
      {
        "field": "spindle_interface",
        "operator": "eq",
        "value": "SRAM GXP 24/22",
        "allow": [
          24
        ]
      }
    ]
  },
  "bb_spacer_stack_mm": {
    "visibility_rules": [
      {
        "field": "bb_construction",
        "operator": "eq",
        "value": "Integrado"
      }
    ],
    "option_rules": [
      {
        "field": "bb_shell_width_mm",
        "operator": "eq",
        "value": 68,
        "allow": [
          2.5,
          5
        ]
      },
      {
        "field": "bb_shell_width_mm",
        "operator": "eq",
        "value": 73,
        "allow": [
          0,
          2.5
        ]
      },
      {
        "field": "bb_shell_width_mm",
        "operator": "eq",
        "value": 83,
        "allow": [
          0
        ]
      }
    ]
  },
  "bb_ball_size_in": {
    "visibility_rules": [
      {
        "field": "bb_construction",
        "operator": "eq",
        "value": "Cubetas y canastillo"
      }
    ],
    "option_rules": [
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BSA / Caja inglesa 34,8 mm (1.37\") x 24",
          "Italiano 36 mm x 24",
          "T47 47 mm",
          "Francés 35 mm x 1",
          "Suizo 35 mm x 1",
          "Euro BMX roscado 68 mm"
        ],
        "allow": [
          "1/4"
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "eq",
        "value": "Americano 51,5 mm",
        "allow": [
          "1/4"
        ]
      }
    ]
  },
  "bb_ball_count_per_side": {
    "visibility_rules": [
      {
        "field": "bb_construction",
        "operator": "eq",
        "value": "Cubetas y canastillo"
      }
    ],
    "option_rules": [
      {
        "field": "bb_shell_standard",
        "operator": "in",
        "value": [
          "BSA / Caja inglesa 34,8 mm (1.37\") x 24",
          "Italiano 36 mm x 24",
          "T47 47 mm",
          "Francés 35 mm x 1",
          "Suizo 35 mm x 1",
          "Euro BMX roscado 68 mm"
        ],
        "allow": [
          9,
          11
        ]
      },
      {
        "field": "bb_shell_standard",
        "operator": "eq",
        "value": "Americano 51,5 mm",
        "allow": [
          9,
          11
        ]
      }
    ]
  },
  "bearing_size_code": {
    "visibility_rules": [
      {
        "field": "bb_construction",
        "operator": "in",
        "value": [
          "Integrado",
          "A presión",
          "Roscado entre sí",
          "Rodamiento sellado"
        ]
      }
    ],
    "option_rules": []
  }
}
''';

const List<String> _shells = <String>[
  'BSA / Caja inglesa 34,8 mm (1.37\") x 24',
  'Italiano 36 mm x 24',
  'T47 47 mm',
  'Francés 35 mm x 1',
  'Suizo 35 mm x 1',
  'Euro BMX roscado 68 mm',
  'BB86 / BB92 41 mm',
  'PF30 46 mm',
  'BB30 42 mm',
  'BB386EVO 46 mm',
  'BB90 / BB95',
  'BBRight / OSBB',
  'Mid BMX 41,2 mm',
  'Spanish BMX 37 mm',
  'Americano 51,5 mm',
];

const List<String> _threadedShells = <String>[
  'BSA / Caja inglesa 34,8 mm (1.37\") x 24',
  'Italiano 36 mm x 24',
  'T47 47 mm',
  'Francés 35 mm x 1',
  'Suizo 35 mm x 1',
  'Euro BMX roscado 68 mm',
];

const List<String> _pressFitShells = <String>[
  'BB86 / BB92 41 mm',
  'PF30 46 mm',
  'BB30 42 mm',
  'BB386EVO 46 mm',
  'BB90 / BB95',
  'BBRight / OSBB',
];

Map<String, SpecTemplateField> _fields() {
  final graph = jsonDecode(_graphJson) as Map<String, dynamic>;
  final result = <String, SpecTemplateField>{};
  var sort = 10;
  for (final entry in graph.entries) {
    result[entry.key] = SpecTemplateField.fromJson({
      'spec_definition_id': entry.key,
      'section_key': 'compatibility',
      'sort_order': sort,
      'is_required': false,
      'visibility_rules': (entry.value as Map)['visibility_rules'],
      'option_rules': (entry.value as Map)['option_rules'],
    });
    sort += 10;
  }
  return result;
}

void main() {
  final fields = _fields();

  Set<String>? optionsFor(String key, Map<String, dynamic> answers) =>
      fields[key]!.allowedOptionsFor(answers);
  bool visible(String key, Map<String, dynamic> answers) =>
      fields[key]!.isVisible(answers);

  group('nada se pregunta antes de lo que depende', () {
    test('sin caja del cuadro no se pregunta nada mas', () {
      for (final key in fields.keys) {
        if (key == 'bb_shell_standard') continue;
        expect(
          visible(key, const <String, dynamic>{}),
          isFalse,
          reason: '$key se ofrecia con la ficha en blanco',
        );
      }
    });

    test('la construccion aparece recien con la caja contestada', () {
      expect(visible('bb_construction', const {}), isFalse);
      expect(visible('bb_construction', {'bb_shell_standard': 'BSA / Caja inglesa 34,8 mm (1.37\") x 24'}),
          isTrue);
    });

    test('incluye-eje aparece recien con la construccion contestada', () {
      final conCaja = {'bb_shell_standard': 'BSA / Caja inglesa 34,8 mm (1.37\") x 24'};
      expect(visible('includes_spindle', conCaja), isFalse);
      expect(
        visible('includes_spindle',
            {...conCaja, 'bb_construction': 'Rodamiento sellado'}),
        isTrue,
      );
    });
  });

  group('la caja del cuadro manda sobre la construccion', () {
    test('una caja a presion no admite cartucho sellado', () {
      for (final shell in _pressFitShells) {
        final offered = optionsFor('bb_construction', {'bb_shell_standard': shell});
        expect(offered, isNotNull, reason: '$shell no acota la construccion');
        expect(
          offered,
          isNot(contains('Rodamiento sellado')),
          reason: '$shell ofrecia cartucho sellado, que no existe a presion',
        );
      }
    });

    test('una caja roscada no admite rodamientos prensados', () {
      for (final shell in _threadedShells) {
        final offered = optionsFor('bb_construction', {'bb_shell_standard': shell});
        expect(offered, isNotNull, reason: '$shell no acota la construccion');
        expect(offered, isNot(contains('A presión')),
            reason: '$shell ofrecia rodamientos prensados en una caja roscada');
        expect(offered, isNot(contains('Roscado entre sí')),
            reason: '$shell ofrecia thread-together en una caja roscada');
      }
    });

    test('el americano solo admite copa y cono', () {
      expect(optionsFor('bb_construction', {'bb_shell_standard': 'Americano 51,5 mm'}),
          {'Cubetas y canastillo'});
    });

    test('el italiano deja un solo ancho, asi que deja de preguntarse', () {
      expect(optionsFor('bb_shell_width_mm', {'bb_shell_standard': 'Italiano 36 mm x 24'}),
          {'70'});
    });
  });

  group('la respuesta trae su rama, no solo recorta', () {
    // Lo que faltaba: la cascada era sustractiva. Elegir «Cubetas y canastillo» no abria
    // ninguna pregunta, y las que esa rama necesita — la mano de la rosca, el
    // tamano de bolita, cuantas por lado — vivian en otra plantilla a la que un
    // producto de la categoria Motor no llega nunca.
    List<String> camposPara(Map<String, dynamic> respuestas) =>
        (fields.keys.where((k) => visible(k, respuestas)).toList()..sort());

    final soloCaja = <String, dynamic>{'bb_shell_standard': 'BSA / Caja inglesa 34,8 mm (1.37\") x 24'};

    test('sin construccion contestada la ficha es minima', () {
      expect(camposPara(soloCaja),
          ['bb_construction', 'bb_shell_standard', 'bb_shell_width_mm']);
    });

    test('copa y cono trae las cuatro preguntas que solo existen ahi', () {
      final antes = camposPara(soloCaja).toSet();
      final despues =
          camposPara({...soloCaja, 'bb_construction': 'Cubetas y canastillo'}).toSet();

      expect(
        despues.difference(antes),
        containsAll(<String>[
          'bb_cup_thread_pair',
          'bb_ball_size_in',
          'bb_ball_count_per_side',
          'bb_cup_outer_diameter_mm',
        ]),
        reason: 'la rama de bolas sueltas no aparecio',
      );
      expect(despues.length, greaterThan(antes.length),
          reason: 'la respuesta tiene que construir, no solo recortar');
    });

    test('copas externas trae otra rama distinta', () {
      final externas =
          camposPara({...soloCaja, 'bb_construction': 'Integrado'}).toSet();
      final bolas =
          camposPara({...soloCaja, 'bb_construction': 'Cubetas y canastillo'}).toSet();

      expect(externas, contains('bb_spacer_stack_mm'),
          reason: 'un juego de 68 necesita declarar sus espaciadores');
      expect(externas, isNot(contains('bb_ball_size_in')));
      expect(bolas, isNot(contains('bb_spacer_stack_mm')));
    });

    test('un cartucho sellado no arrastra ninguna de las dos', () {
      final cartucho =
          camposPara({...soloCaja, 'bb_construction': 'Rodamiento sellado'}).toSet();
      expect(cartucho, isNot(contains('bb_ball_size_in')));
      expect(cartucho, isNot(contains('bb_spacer_stack_mm')));
      expect(cartucho, isNot(contains('bb_cup_thread_pair')));
    });

    test('la mano de la rosca sale del estandar de la caja', () {
      expect(
        optionsFor('bb_cup_thread_pair',
            {'bb_shell_standard': 'BSA / Caja inglesa 34,8 mm (1.37\") x 24', 'bb_construction': 'Cubetas y canastillo'}),
        {'Derecha / Izquierda (BSA inglés)'},
        reason: 'el ingles lleva la copa fija a la izquierda, y es la unica opcion',
      );
      expect(
        optionsFor('bb_cup_thread_pair',
            {'bb_shell_standard': 'Italiano 36 mm x 24', 'bb_construction': 'Cubetas y canastillo'}),
        {'Derecha / Derecha (italiano o genérico)'},
      );
    });

    test('una caja a presion no tiene mano de rosca que declarar', () {
      expect(
        visible('bb_cup_thread_pair', {
          'bb_shell_standard': 'BB86 / BB92 41 mm',
          'bb_construction': 'A presión',
        }),
        isFalse,
      );
    });
  });

  test('las 15 cajas llegan al final sin quedarse sin opciones', () {
    final vacios = <String>[];
    final abiertos = <String>[];
    var alcanzables = 0;

    for (final shell in _shells) {
      final conCaja = <String, dynamic>{'bb_shell_standard': shell};

      for (final key in ['bb_construction', 'bb_shell_width_mm', 'bb_shell_diameter_mm']) {
        if (!visible(key, conCaja)) continue;
        final offered = optionsFor(key, conCaja);
        if (offered == null) {
          abiertos.add('$shell · $key ofrece todo su vocabulario');
        } else if (offered.isEmpty) {
          vacios.add('$shell · $key sin opciones');
        }
      }

      for (final construccion in optionsFor('bb_construction', conCaja) ?? <String>{}) {
        final conConstruccion = {...conCaja, 'bb_construction': construccion};

        for (final traeEje in [true, false]) {
          final conEje = {...conConstruccion, 'includes_spindle': traeEje};
          final key = traeEje ? 'spindle_interface' : 'spindle_interface_accepted';
          if (!visible(key, conEje)) continue;

          final interfaces = optionsFor(key, conEje);
          if (interfaces == null) {
            abiertos.add('$shell · $construccion · $key ofrece todo');
            continue;
          }
          if (interfaces.isEmpty) {
            vacios.add('$shell · $construccion · trae=$traeEje · $key sin opciones');
            continue;
          }
          alcanzables++;

          for (final interfaz in interfaces) {
            final completo = {...conEje, 'spindle_interface': interfaz};
            for (final medida in ['spindle_length_mm', 'spindle_diameter_mm']) {
              if (!visible(medida, completo)) continue;
              final offered = optionsFor(medida, completo);
              if (offered == null) {
                abiertos.add('$shell · $construccion · $interfaz · $medida ofrece todo');
              } else if (offered.isEmpty) {
                vacios.add('$shell · $construccion · $interfaz · $medida sin opciones');
              }
            }
          }
        }
      }
    }

    expect(vacios, isEmpty,
        reason: 'hay combinaciones sin salida:\n${vacios.join('\n')}');
    expect(abiertos, isEmpty,
        reason: 'hay campos sin acotar, que es como volvio el texto libre:'
            '\n${abiertos.join('\n')}');
    expect(alcanzables, 70,
        reason: 'cambio la cantidad de combinaciones alcanzables del pedalier');
  });

  test('el largo de eje no se pregunta en un eje pasante', () {
    final hollowtech = {
      'bb_shell_standard': 'BSA / Caja inglesa 34,8 mm (1.37\") x 24',
      'bb_construction': 'Integrado',
      'includes_spindle': true,
      'spindle_interface': 'Hollowtech / 24mm',
    };
    expect(visible('spindle_length_mm', hollowtech), isFalse,
        reason: 'un Hollowtech no tiene largo de eje propio que declarar');
    expect(visible('spindle_diameter_mm', hollowtech), isTrue);
    expect(optionsFor('spindle_diameter_mm', hollowtech), {'24'});
  });

  test('un largo ya guardado no se esconde por una interfaz sin contestar', () {
    // El guardado borra todo campo de la plantilla que no venga en el payload,
    // asi que un campo escondido con dato adentro esta a un guardado de
    // perderse. 29 pedaliers del catalogo tienen su largo de eje y ninguno
    // tiene la interfaz confirmada: el nombre dice `P/CUADRADA`, que no prueba
    // JIS ni ISO. Se esconde cuando se SABE que el eje es pasante, no mientras
    // no se sabe.
    final sinInterfaz = {
      'bb_shell_standard': 'BSA / Caja inglesa 34,8 mm (1.37\") x 24',
      'bb_construction': 'Rodamiento sellado',
      'includes_spindle': true,
    };
    expect(visible('spindle_length_mm', sinInterfaz), isTrue,
        reason: 'el largo de 29 productos desaparece y el guardado lo borra');

    expect(
      visible('spindle_length_mm', {...sinInterfaz, 'spindle_interface': 'Cuadrado JIS'}),
      isTrue,
    );
    expect(
      visible('spindle_length_mm', {
        ...sinInterfaz,
        'bb_construction': 'Integrado',
        'spindle_interface': 'SRAM DUB 28.99mm',
      }),
      isFalse,
      reason: 'un DUB pasante no tiene largo propio que declarar',
    );
  });

  test('el diametro de eje no se pregunta en un cono cuadrado', () {
    final cuadrado = {
      'bb_shell_standard': 'BSA / Caja inglesa 34,8 mm (1.37\") x 24',
      'bb_construction': 'Rodamiento sellado',
      'includes_spindle': true,
      'spindle_interface': 'Cuadrado JIS',
    };
    expect(visible('spindle_diameter_mm', cuadrado), isFalse,
        reason: 'en un cono cuadrado el diametro del eje no decide nada');
    expect(visible('spindle_length_mm', cuadrado), isTrue);
    expect(optionsFor('spindle_length_mm', cuadrado), contains('124.5'),
        reason: '124.5 mm es un largo real del catalogo');
  });
}
