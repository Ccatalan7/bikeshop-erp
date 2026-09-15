import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_effective_criteria.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';

/// **¿Aguanta otras necesidades, o quedó afinado para «Cámara 700»?**
///
/// Cada caso entra por donde entra la app: una `SupplyNeed` con su
/// `product_name` reconocido y su `original_description`, las dos fuentes
/// fusionadas por campo, la ficha real de esa categoría y **nombres reales del
/// catálogo de esta tienda**. Lo que se afirma son los productos que
/// sobreviven, por su nombre; un conteo no dice cuál sobrevivió.

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
];

final _tube = <SupplierNeedSearchField>[
  _f('wheel_size', 'Tamaño de rueda', 'single_select', values: _wheel),
  _f('valve_type', 'Tipo de Válvula', 'single_select', values: _valve),
  _f('tube_has_sealant', 'Trae líquido sellante', 'boolean',
      description: 'Autosellante o anti-pinchazo: viene con líquido adentro.'),
];

final _tire = <SupplierNeedSearchField>[
  _f('wheel_size', 'Tamaño de rueda', 'single_select', values: _wheel),
  _f('tire_width_in', 'Ancho', 'number', unit: 'in'),
  _f('tire_bead_type', 'Talón', 'single_select', values: <Object>[
    'Talón de alambre',
    'Talón plegable',
    'Tubular',
  ]),
  _f('tire_tubeless_ready', 'Tubeless Ready (TR)', 'boolean'),
];

final _rim = <SupplierNeedSearchField>[
  _f('wheel_size', 'Tamaño de rueda', 'single_select', values: _wheel),
  _f('spoke_holes', 'Perforaciones', 'single_select',
      values: <Object>['24', '28', '32', '36', '40']),
  _f('rim_material', 'Material', 'single_select',
      values: <Object>['Aluminio', 'Carbono', 'Acero', 'Otro']),
];

final _rotor = <SupplierNeedSearchField>[
  _f('rotor_diameter_mm', 'Diámetro', 'single_select',
      values: <Object>['140', '160', '180', '203', '220']),
  _f('rotor_mount_type', 'Montaje', 'single_select',
      values: <Object>['6 pernos', 'Centerlock']),
  _f('rotor_material', 'Material', 'single_select',
      values: <Object>['Acero Inoxidable', 'Acero']),
];

final _chain = <SupplierNeedSearchField>[
  _f('chain_speeds', 'Velocidades', 'multi_select',
      values: <Object>['6', '7', '8', '9', '10', '11', '12']),
  _f('chain_width_family', 'Ancho', 'single_select',
      values: <Object>['1/8', '3/32', '11/128', 'Otro']),
];

final _bb = <SupplierNeedSearchField>[
  _f('bb_construction', 'Construcción', 'single_select', values: <Object>[
    'Rodamiento sellado',
    'Integrado',
    'Cubetas y canastillo',
  ]),
  _f('bb_shell_width_mm', 'Ancho de caja', 'number',
      unit: 'mm', values: <Object>[68, 70, 73, 83, 92, 100]),
  _f('spindle_length_mm', 'Largo del eje', 'number',
      unit: 'mm',
      values: <Object>[103, 110.5, 113, 118, 122.5, 124.5, 125.5, 127.5]),
];

SupplyNeed _need(String originalDescription, {String? productName}) =>
    SupplyNeed.fromJson(<String, dynamic>{
      'id': 'need-x',
      'origin_kind': 'ad_hoc',
      'original_description': originalDescription,
      if (productName != null) 'product_name': productName,
      if (productName != null) 'product_id': 'product-x',
      'quantity': 1,
      'unit': 'unit',
      'identity_state': productName == null ? 'unresolved' : 'confirmed',
      'supply_state': 'open',
      'version': 1,
      'created_at': '2026-08-30T12:00:00Z',
    });

SupplierNeedPortalAdapter _adapter() =>
    SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
      'version': 1,
      'generic_family_search': true,
      'result_schema': <String, dynamic>{
        'columns': <String, dynamic>{
          'code': <String>['c'],
          'name': <String>['n'],
          'price': <String>['p'],
        },
      },
      'catalog_route': <String, dynamic>{
        'url_template': 'http://x/{node}{page}{page_size}',
        'page_size': 50,
      },
    });

/// La ficha efectiva de esa necesidad, como `campo=valor`.
Set<String> derivados(
  SupplyNeed need, {
  required String family,
  required String path,
  required List<SupplierNeedSearchField> fields,
}) =>
    effectiveSupplyNeedCriteria(
      stored: SupplyNeedCriteria(
        predicates: const <SupplyNeedPredicate>[],
        categoryId: 'cat',
        categoryPath: path,
        revisionNo: 1,
        technicalFamily: family,
      ),
      texts: supplyNeedRequestTexts(need),
      fields: fields,
    ).predicates.map((p) => '${p.field}=${p.values.single}').toSet();

/// Los productos que sobreviven a esa ficha, por su nombre.
Set<String> sobreviven(
  SupplyNeed need, {
  required String family,
  required String path,
  required List<SupplierNeedSearchField> fields,
  required List<String> catalogo,
}) {
  final efectiva = effectiveSupplyNeedCriteria(
    stored: SupplyNeedCriteria(
      predicates: const <SupplyNeedPredicate>[],
      categoryId: 'cat',
      categoryPath: path,
      revisionNo: 1,
      technicalFamily: family,
    ),
    texts: supplyNeedRequestTexts(need),
    fields: fields,
  );
  final plan = buildSupplierNeedSearchPlan(
    request: SupplierNeedSearchRequest(
      needId: need.id,
      description: supplyNeedRequestText(need),
      categoryId: 'cat',
      categoryPath: path,
      technicalFamily: family,
      fields: fields,
      predicates: efectiva.predicates
          .map((p) => SupplierNeedSearchPredicate(
                field: p.field,
                operator: p.operator,
                values: p.values,
              ))
          .toList(growable: false),
    ),
    adapter: _adapter(),
    maxLength: 20,
  )!;
  return matchSupplierNeedCandidates(plan, <SupplierPortalCatalogCandidate>[
    for (var i = 0; i < catalogo.length; i += 1)
      SupplierPortalCatalogCandidate(
        code: '$i',
        name: catalogo[i],
        priceNet: 1000,
        rowText: catalogo[i],
      ),
  ])
      .where((m) => m.state != SupplierNeedMatchState.conflict)
      .map((m) => m.candidate.name)
      .toSet();
}

/// Catálogos reales de esta tienda.
const _catCamaras = <String>[
  'CAMARA 700 X 18/25C V/AUTO 60MM',
  'CAMARA 700 X 18/25C V/FRANCESA 48MM CAJA',
  'CAMARA 700 X 38/45C V/FRANCESA 60MM (28-5/8-1/4)',
  'CAMARA 26 X 1.3/8 V/AUTO 33MM',
  'CAMARA MAXXIS 29X1.75/2.40 A/V 48MM',
];
const _catNeumaticos = <String>[
  'MAXXIS ALAMBRE 26X2.20 IKON',
  'MAXXIS ALAMBRE 27.5X2.25 REKON RACE',
  'MAXXIS ALAMBRE 29X2.20 ARDENT RACE',
  'MAXXIS ALAMBRE 29X2.35 FOREKASTER',
  'MAXXIS ALAMBRE 700x25c DETONATOR',
];
const _catLlantas = <String>[
  'LLANTA 26 VISION ALUMINIO NEGRA  DOBLE PARED 32H',
  'LLANTA 26 X 1.75 MTB C.P. 36H. 7 X REFORZADA',
  'LLANTA 27,5 NEGRA ALUMINIO DOBLE PARED 32 Hoyos (economica)',
  'LLANTA 29 NEGRA DOBLE PARED ALUMINIO 36 H',
  'LLANTA 24 X 1.75 BUFFALO T/EXPLORER COLOR (36H)',
];
const _catDiscos = <String>[
  'Disco de Freno 160mm G3 TANKE',
  'Disco freno Shimano Deore RT56 160MM',
  'Disco de Freno Flotante 180mm Cyclami',
  'Disco freno Shimano Deore RT56 180MM',
  'Disco freno SRAM 160MM Acero Inoxidable',
];
const _catCadenas = <String>[
  'Cadena 1/2 X 1/8 Kmc Hv410 Gris/cafe Bolsa',
  'Cadena 1/2 X 1/8 Kmc K710 Negra/cromada',
  'CADENA 1/2 X 3/32 116 E 8 VEL. Z8.3 DISPLAY KMC',
  'Cadena 1/2 X 3/32 Kmc Hv408 Plata',
];
const _catMotores = <String>[
  'Eje De Motor Sellado 68 X 113mm Negro',
  'Eje De Motor Sellado 68 X 122.5mm ZTTO AE',
  'Eje De Motor Sellado 73 X 118mm AE',
  'Cubetas De Motor TSC Stacked MID 22mm Rojo',
];

void main() {
  group('cámaras', () {
    Set<String> vivos(SupplyNeed need) => sobreviven(need,
        family: 'tube',
        path: 'Componentes / Ruedas / Cámaras',
        fields: _tube,
        catalogo: _catCamaras);

    test('la válvula que sólo trae la petición acota el listado', () {
      expect(vivos(_need('cámara 700', productName: 'Cámara 700')), <String>{
        'CAMARA 700 X 18/25C V/AUTO 60MM',
        'CAMARA 700 X 18/25C V/FRANCESA 48MM CAJA',
        'CAMARA 700 X 38/45C V/FRANCESA 60MM (28-5/8-1/4)',
      });
      expect(
        vivos(_need('cámara 700 válvula francesa', productName: 'Cámara 700')),
        <String>{
          'CAMARA 700 X 18/25C V/FRANCESA 48MM CAJA',
          'CAMARA 700 X 38/45C V/FRANCESA 60MM (28-5/8-1/4)',
        },
      );
    });

    test('cambiar el aro cambia el producto, no el número', () {
      expect(vivos(_need('cámaras 29 válvula americana')), <String>{
        'CAMARA MAXXIS 29X1.75/2.40 A/V 48MM',
      });
    });
  });

  group('neumáticos', () {
    Set<String> vivos(SupplyNeed need) => sobreviven(need,
        family: 'tire',
        path: 'Componentes / Ruedas / Neumáticos',
        fields: _tire,
        catalogo: _catNeumaticos);

    test('el caso realista del módulo: nombre 27,5 y petición con el ancho',
        () {
      // `product_name: 'Neumático 27,5'` con
      // `original_description: 'neumático económico 27,5 ancho mayor a 2,0'`.
      final need = _need('neumático económico 27,5 ancho mayor a 2,0',
          productName: 'Neumático 27,5');
      expect(
        derivados(need,
            family: 'tire',
            path: 'Componentes / Ruedas / Neumáticos',
            fields: _tire),
        <String>{'wheel_size=27.5"'},
        reason: '«ancho mayor a 2,0» es un rango: este lector no lo expresa y '
            'no lo inventa',
      );
      expect(vivos(need), <String>{'MAXXIS ALAMBRE 27.5X2.25 REKON RACE'});
    });

    test('aro 29 deja los dos 29 y ninguno más', () {
      expect(vivos(_need('2 neumáticos aro 29 para reposición')), <String>{
        'MAXXIS ALAMBRE 29X2.20 ARDENT RACE',
        'MAXXIS ALAMBRE 29X2.35 FOREKASTER',
      });
    });
  });

  group('llantas', () {
    Set<String> vivos(SupplyNeed need) => sobreviven(need,
        family: 'rim',
        path: 'Componentes / Ruedas / Llantas',
        fields: _rim,
        catalogo: _catLlantas);

    test('aro 26 con 36 hoyos cruza los dos criterios', () {
      expect(vivos(_need('Aro 26 36 hoyos')), <String>{
        'LLANTA 26 X 1.75 MTB C.P. 36H. 7 X REFORZADA',
      });
    });

    test('y con 32 hoyos cambia el producto', () {
      expect(vivos(_need('Aro 26 32 hoyos')), <String>{
        'LLANTA 26 VISION ALUMINIO NEGRA  DOBLE PARED 32H',
      });
    });
  });

  group('discos', () {
    Set<String> vivos(SupplyNeed need) => sobreviven(need,
        family: 'rotor',
        path: 'Componentes / Frenos / Discos',
        fields: _rotor,
        catalogo: _catDiscos);

    test('160 y 180 parten el catálogo sin solaparse', () {
      final ciento60 = vivos(_need('disco de freno 160'));
      final ciento80 = vivos(_need('disco de freno 180'));
      expect(ciento60, <String>{
        'Disco de Freno 160mm G3 TANKE',
        'Disco freno Shimano Deore RT56 160MM',
        'Disco freno SRAM 160MM Acero Inoxidable',
      });
      expect(ciento80, <String>{
        'Disco de Freno Flotante 180mm Cyclami',
        'Disco freno Shimano Deore RT56 180MM',
      });
      expect(ciento60.intersection(ciento80), isEmpty);
    });

    test('el material acota, y lo que no lo declara sigue por revisar', () {
      // Sólo uno dice su material; los otros dos 160 no lo declaran, y una
      // ausencia no elimina. El que declara OTRO material sí se iría.
      expect(vivos(_need('disco de freno 160 acero inoxidable')), <String>{
        'Disco freno SRAM 160MM Acero Inoxidable',
        'Disco de Freno 160mm G3 TANKE',
        'Disco freno Shimano Deore RT56 160MM',
      });
    });
  });

  group('cadenas', () {
    Set<String> vivos(SupplyNeed need) => sobreviven(need,
        family: 'chain',
        path: 'Transmisión / Cadenas',
        fields: _chain,
        catalogo: _catCadenas);

    test('11 velocidades ya elimina la que declara 8', () {
      // `CADENA 1/2 X 3/32 116 E 8 VEL.` dice su velocidad y contradice; las
      // demás no la declaran y quedan por revisar.
      expect(
        vivos(_need('Cadena de 11 velocidades', productName: 'Cadena 11v')),
        <String>{
          'Cadena 1/2 X 1/8 Kmc Hv410 Gris/cafe Bolsa',
          'Cadena 1/2 X 1/8 Kmc K710 Negra/cromada',
          'Cadena 1/2 X 3/32 Kmc Hv408 Plata',
        },
      );
    });

    test('pero cambiar el ancho a 3/32 sí parte el catálogo', () {
      expect(
        vivos(_need('cadena 11 velocidades ancho 3/32',
            productName: 'Cadena 11v')),
        <String>{'Cadena 1/2 X 3/32 Kmc Hv408 Plata'},
        reason: 'la otra 3/32 declara 8 velocidades y ya estaba fuera',
      );
      expect(
        vivos(_need('cadena 11 velocidades ancho 1/8',
            productName: 'Cadena 11v')),
        <String>{
          'Cadena 1/2 X 1/8 Kmc Hv410 Gris/cafe Bolsa',
          'Cadena 1/2 X 1/8 Kmc K710 Negra/cromada',
        },
      );
    });
  });

  group('motor de centro', () {
    Set<String> vivos(SupplyNeed need) => sobreviven(need,
        family: 'bottom_bracket',
        path: 'Transmisión / Motor',
        fields: _bb,
        catalogo: _catMotores);

    test('68 x 113 deja ese eje y no los otros largos', () {
      // «Sellado» elimina la cubeta que se declara cubeta; la pareja elimina
      // los ejes de otro largo.
      expect(vivos(_need('Motor de centro sellado 68 x 113')), <String>{
        'Eje De Motor Sellado 68 X 113mm Negro',
      });
    });

    test('73 x 118 deja el otro, y no se confunden entre sí', () {
      final ciento13 = vivos(_need('Motor de centro sellado 68 x 113'));
      final ciento18 = vivos(_need('Motor de centro 73 x 118 mm'));
      // La cubeta no declara ni caja ni eje —no trae la pareja—, así que no
      // contradice y queda por revisar. Los ejes con OTRA pareja sí se van.
      expect(ciento18, <String>{
        'Eje De Motor Sellado 73 X 118mm AE',
        'Cubetas De Motor TSC Stacked MID 22mm Rojo',
      });
      expect(
          ciento18, isNot(contains('Eje De Motor Sellado 68 X 113mm Negro')));
      expect(ciento13, isNot(contains('Eje De Motor Sellado 73 X 118mm AE')));
    });
  });

  group('cantidades, códigos y precios no son specs, en ninguna familia', () {
    test('no derivan criterios', () {
      final casos = <String, Set<String>>{};
      casos['cámaras 700, 29 unidades'] = derivados(
          _need('cámaras 700, 29 unidades'),
          family: 'tube',
          path: 'Componentes / Ruedas / Cámaras',
          fields: _tube);
      casos['llantas aro 26, código 32 del proveedor'] = derivados(
          _need('llantas aro 26, código 32 del proveedor'),
          family: 'rim',
          path: 'Componentes / Ruedas / Llantas',
          fields: _rim);
      casos['discos, presupuesto 180 pesos'] = derivados(
          _need('discos, presupuesto 180 pesos'),
          family: 'rotor',
          path: 'Componentes / Frenos / Discos',
          fields: _rotor);

      expect(casos['cámaras 700, 29 unidades'], <String>{'wheel_size=700c'},
          reason: 'la cantidad no borra ni agrega medida');
      expect(casos['llantas aro 26, código 32 del proveedor'],
          <String>{'wheel_size=26"'},
          reason: 'un código no es una perforación');
      expect(casos['discos, presupuesto 180 pesos'], isEmpty,
          reason: 'un precio no es un diámetro');
    });
  });
}
