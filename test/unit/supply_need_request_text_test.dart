import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/services/supply_need_effective_criteria.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';

/// **El nombre reconocido no reemplaza a la petición.**
///
/// La página derivaba la ficha y armaba la búsqueda desde
/// `need.productName ?? need.description`. En cuanto la interpretación
/// reconocía un producto, todo lo que el operador había escrito y no cabía en
/// ese nombre dejaba de existir: el fake realista del propio módulo tiene
/// `product_name: 'Neumático 27,5'` y
/// `original_description: 'neumático económico 27,5 ancho mayor a 2,0'`.
///
/// Se mide sobre `SupplyNeed` real —con sus dos campos y su mapeo— y no
/// llamando al lector con un string armado a mano, que es justo lo que ocultaba
/// el hueco.

const _tube = <SupplierNeedSearchField>[
  SupplierNeedSearchField(
    key: 'wheel_size',
    label: 'Tamaño de rueda',
    dataType: 'single_select',
    allowedValues: <Object>['26"', '27.5"', '29"', '700c', 'Otra'],
  ),
  SupplierNeedSearchField(
    key: 'valve_type',
    label: 'Tipo de Válvula',
    dataType: 'single_select',
    allowedValues: <Object>[
      'Presta (francesa)',
      'Schrader (americana / auto)',
      'Dunlop (inglesa)',
      'Otra',
    ],
  ),
  SupplierNeedSearchField(
    key: 'tube_has_sealant',
    label: 'Trae líquido sellante',
    dataType: 'boolean',
    description: 'Autosellante o anti-pinchazo: viene con líquido adentro.',
  ),
];

SupplyNeed _need({
  required String originalDescription,
  String? productName,
}) =>
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

Set<String> _derivados(SupplyNeed need) => effectiveSupplyNeedCriteria(
      stored: const SupplyNeedCriteria(
        predicates: <SupplyNeedPredicate>[],
        categoryId: 'cat',
        categoryPath: 'Componentes / Ruedas / Cámaras',
        revisionNo: 1,
        technicalFamily: 'tube',
      ),
      texts: supplyNeedRequestTexts(need),
      fields: _tube,
    ).predicates.map((p) => '${p.field}=${p.values.single}').toSet();

/// Cámaras reales de RBX.
const _camaras = <String>[
  'CAMARA 700 X 18/25C V/AUTO 60MM',
  'CAMARA 700 X 18/25C V/FRANCESA 48MM CAJA',
  'CAMARA 700 X 28/38C V/AUTO 48MM (28-5/8-1/4)',
  'CAMARA 700 X 38/45C V/FRANCESA 60MM (28-5/8-1/4)',
  'CAMARA 26 X 1.3/8 V/AUTO 33MM',
];

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

/// Los productos que sobreviven a la ficha efectiva de esa necesidad.
Set<String> _sobreviven(SupplyNeed need) {
  final texto = supplyNeedRequestText(need);
  final efectiva = effectiveSupplyNeedCriteria(
    stored: const SupplyNeedCriteria(
      predicates: <SupplyNeedPredicate>[],
      categoryId: 'cat',
      categoryPath: 'Componentes / Ruedas / Cámaras',
      revisionNo: 1,
      technicalFamily: 'tube',
    ),
    texts: <String>[texto],
    fields: _tube,
  );
  final plan = buildSupplierNeedSearchPlan(
    request: SupplierNeedSearchRequest(
      needId: need.id,
      description: texto,
      categoryId: 'cat',
      categoryPath: 'Componentes / Ruedas / Cámaras',
      technicalFamily: 'tube',
      fields: _tube,
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
    for (var i = 0; i < _camaras.length; i += 1)
      SupplierPortalCatalogCandidate(
        code: '$i',
        name: _camaras[i],
        priceNet: 1000,
        rowText: _camaras[i],
      ),
  ])
      .where((m) => m.state != SupplierNeedMatchState.conflict)
      .map((m) => m.candidate.name)
      .toSet();
}

void main() {
  test('lo que sólo está en la petición original no se pierde', () {
    final need = _need(
      originalDescription: 'cámara 700 válvula francesa autosellante',
      productName: 'Cámara 700',
    );
    expect(_derivados(need), <String>{
      'wheel_size=700c',
      'valve_type=Presta (francesa)',
      'tube_has_sealant=true',
    });
  });

  test('y el nombre reconocido tampoco se pierde', () {
    // El caso inverso: la identidad trae la medida y la petición no.
    final need = _need(
      originalDescription: 'necesito cámaras para el taller',
      productName: 'Cámara 700',
    );
    expect(_derivados(need), contains('wheel_size=700c'));
  });

  test('sin producto reconocido sigue mandando la petición', () {
    final need = _need(originalDescription: 'cámara 700 válvula francesa');
    expect(_derivados(need), contains('valve_type=Presta (francesa)'));
  });

  test('una cantidad en la petición no borra la medida del nombre', () {
    // **El borde del guard.** `29 unidades` y `código 26` no son medidas; si el
    // guard los cuenta como una segunda medida, marca ambigüedad y pierde el
    // 700 que el nombre sí dice.
    for (final peticion in const <String>[
      '29 unidades para el taller',
      'código 26 del proveedor',
      'presupuesto 29 pesos',
    ]) {
      expect(
        _derivados(_need(
          originalDescription: peticion,
          productName: 'Cámara 700',
        )),
        contains('wheel_size=700c'),
        reason: peticion,
      );
    }
  });

  test('dentro de UNA sola petición, un código o un precio tampoco borran', () {
    // Sin nombre reconocido: todo en el mismo `original_description`. El guard
    // no puede contar como segunda medida un número que el contexto declara
    // como código o como precio.
    for (final peticion in const <String>[
      'Cámara 700, código 26 del proveedor',
      'Cámara 700, presupuesto 29 pesos',
      'Cámara 700 para el pedido 26 del taller',
    ]) {
      expect(
        _derivados(_need(originalDescription: peticion)),
        contains('wheel_size=700c'),
        reason: peticion,
      );
    }
  });

  test('pero un surtido que nombra dos medidas sigue sin afirmar', () {
    expect(
      _derivados(_need(originalDescription: 'CAMARA 700X28C Y 26X1.75 SURTIDO'))
          .where((p) => p.startsWith('wheel_size')),
      isEmpty,
    );
  });

  test('las dos mitades no se pegan entre sí', () {
    // El nombre termina en el sustantivo y la petición empieza con un número
    // que es una cantidad: unir los textos no puede fabricar una medida que
    // ninguno de los dos dice.
    final need = _need(
      originalDescription: '29 unidades para el taller',
      productName: 'Cámara',
    );
    expect(
      _derivados(need).where((p) => p.startsWith('wheel_size')),
      isEmpty,
    );
  });

  test('si se contradicen, no se elige una', () {
    final need = _need(
      originalDescription: 'cámara aro 26 para la bici del taller',
      productName: 'Cámara 700',
    );
    expect(
      _derivados(need).where((p) => p.startsWith('wheel_size')),
      isEmpty,
      reason: 'dos medidas distintas no se resuelven por prioridad',
    );
  });

  test('un booleano que se contradice no elige el primero', () {
    // El nombre dice tubeless y la petición dice que no. Ni una ni otra.
    final need = _need(
      originalDescription: 'cámara 700 sin sellante',
      productName: 'Cámara 700 autosellante',
    );
    expect(
      _derivados(need).where((p) => p.startsWith('tube_has_sealant')),
      isEmpty,
    );
  });

  test('y dentro de un mismo texto tampoco', () {
    final need = _need(
      originalDescription: 'cámara 700 autosellante, la quiero sin sellante',
    );
    expect(
      _derivados(need).where((p) => p.startsWith('tube_has_sealant')),
      isEmpty,
    );
  });

  test('un nombre repetido en la petición no se duplica', () {
    final need = _need(
      originalDescription: 'Cámara 700',
      productName: 'Cámara 700',
    );
    expect(_derivados(need), <String>{'wheel_size=700c'});
  });
  group('el contexto extra cambia el conjunto, no sólo la ficha', () {
    test('la válvula que sólo estaba en la petición acota el listado', () {
      final soloNombre = _need(
        originalDescription: 'cámara 700',
        productName: 'Cámara 700',
      );
      final conPeticion = _need(
        originalDescription: 'cámara 700 válvula francesa',
        productName: 'Cámara 700',
      );
      // Con el nombre solo sobreviven las cuatro 700; la 26 se cae por medida.
      expect(_sobreviven(soloNombre), <String>{
        'CAMARA 700 X 18/25C V/AUTO 60MM',
        'CAMARA 700 X 18/25C V/FRANCESA 48MM CAJA',
        'CAMARA 700 X 28/38C V/AUTO 48MM (28-5/8-1/4)',
        'CAMARA 700 X 38/45C V/FRANCESA 60MM (28-5/8-1/4)',
      });
      // Con la petición completa quedan sólo las francesas. Esto es lo que se
      // perdía: el nombre reconocido tapaba el criterio.
      expect(_sobreviven(conPeticion), <String>{
        'CAMARA 700 X 18/25C V/FRANCESA 48MM CAJA',
        'CAMARA 700 X 38/45C V/FRANCESA 60MM (28-5/8-1/4)',
      });
    });

    test('y con válvula auto quedan exactamente las otras dos', () {
      final auto = _need(
        originalDescription: 'cámara 700 válvula americana',
        productName: 'Cámara 700',
      );
      expect(_sobreviven(auto), <String>{
        'CAMARA 700 X 18/25C V/AUTO 60MM',
        'CAMARA 700 X 28/38C V/AUTO 48MM (28-5/8-1/4)',
      });
    });
  });
}
