import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/supplier_catalog_api.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/services/supplier_portal_reading.dart';

/// Leer el catálogo de un proveedor por su API, con respuestas reales.
///
/// Las dos fixtures son la respuesta literal de cada tienda el 2026-08-29 —
/// `droppbike.cl` (WooCommerce) y `derman.cl` (PrestaShop)—, recortada a las
/// claves que se usan. Una fixture redactada por nosotros habría estado verde
/// mientras la lectura real fallaba: ya pasó con el validador del portal.

String _fixture(String name) =>
    File('test/fixtures/supplier_portal/$name').readAsStringSync();

void main() {
  group('WooCommerce publica lo que su propia página esconde', () {
    late SupplierCatalogApiPage page;

    setUp(() {
      page = parseSupplierCatalogApiPage(
        kind: SupplierCatalogApiKind.wooCommerceStoreV1,
        body: _fixture('droppbike_woocommerce_camara.json'),
        totalItemsHeader: '33',
        totalPagesHeader: '11',
      );
    });

    test('el precio llega aunque la tienda lo tape tras registro', () {
      // En droppbike.cl la ficha dice «🔐 Regístrate para ver precio». La API
      // devuelve 1310. Sin esto el proveedor no se puede comparar por precio.
      final first = page.candidates.first;
      expect(first.name, 'CAMARA 12X2.125 VALVULA CAUCHO NATURA 34MM RITECH');
      expect(first.code, 'IM04760');
      expect(first.priceNet, 1310);
    });

    test('el total exacto viene en la cabecera, no se estima', () {
      // «Revisé todo» sólo se puede decir con este número. La página trae 5.
      expect(page.candidates, hasLength(5));
      expect(page.totalItems, 33);
      expect(page.totalPages, 11);
    });

    test('el stock del proveedor es un hecho observado', () {
      // Hasta ahora el módulo sólo probaba catálogo y precio. La tienda dice
      // si tiene unidades, y eso es justo lo que se pregunta al comprar.
      expect(page.candidates.first.technicalFacts['in_stock'], isTrue);
    });

    test('la categoría del proveedor entra al texto, no a los hechos', () {
      final first = page.candidates.first;
      expect(first.rowText, contains('Camaras'));
      expect(first.technicalFacts['supplier_categories'], contains('Camaras'));
      // Una categoría no es una medida: nunca puede probar una spec.
      expect(first.technicalFacts.containsKey('wheel_size'), isFalse);
    });
  });

  group('PrestaShop responde JSON al mismo buscador', () {
    late SupplierCatalogApiPage page;

    setUp(() {
      page = parseSupplierCatalogApiPage(
        kind: SupplierCatalogApiKind.prestashopSearchAjax,
        body: _fixture('derman_prestashop_camara700.json'),
      );
    });

    test('nombre, referencia y precio numérico', () {
      final first = page.candidates.first;
      expect(first.name, 'CAMARA ARO 700X25/35C F/V 60MM PANARACER');
      expect(first.code, 'PANARACER-70025/35');
      expect(first.priceNet, 7900);
    });

    test('`\$7.900` son siete mil novecientos, no siete coma nueve', () {
      // El punto agrupa miles en Chile. Leerlo como decimal dejaba el precio
      // en 7,9 y esa fila encabezaba el ranking por ser «la más barata».
      final page = parseSupplierCatalogApiPage(
        kind: SupplierCatalogApiKind.prestashopSearchAjax,
        body: '{"products":[{"name":"CAMARA X","reference":"R1",'
            '"price":"\$7.900"}]}',
      );
      expect(page.candidates.single.priceNet, 7900);
    });

    test('el total lo declara la paginación', () {
      expect(page.candidates, hasLength(5));
      expect(page.totalItems, 30);
      expect(page.totalPages, 2);
    });
  });

  group('una tienda con API entra al barrido automático', () {
    SupplierPortalProbe probe({required bool withApi}) => SupplierPortalProbe(
          searchUrlTemplate: 'https://tienda.cl/?s={code}',
          // Sin plantilla de buscador por navegador: es justo el caso que
          // dejaba fuera a una tienda que sí publica su catálogo.
          needSearchAdapter:
              SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
            'version': 1,
            'generic_family_search': true,
            'result_schema': <String, dynamic>{
              'columns': <String, dynamic>{
                'code': <String>['Referencia'],
                'name': <String>['Nombre'],
              },
            },
            if (withApi)
              'catalog_api': <String, dynamic>{
                'kind': 'woocommerce_store_v1',
                'base_url': 'https://tienda.cl',
              },
          }),
        );

    const request = SupplierNeedSearchRequest(
      needId: 'n1',
      description: 'Cámaras aro 700 para reposición del taller',
      categoryId: 'category-tubes',
      technicalFamily: 'tube',
      fields: <SupplierNeedSearchField>[],
      predicates: <SupplierNeedSearchPredicate>[],
    );

    test('sin URL de buscador pero con API, puede contestar', () {
      expect(probe(withApi: true).canSearchNeed(request), isTrue);
    });

    test('sin ninguna de las dos, no puede', () {
      expect(probe(withApi: false).canSearchNeed(request), isFalse);
    });

    test('la API se rehúsa a hablar en claro', () {
      // Un `base_url` sin https mandaría la consulta del taller por la red
      // abierta. No se corrige: se descarta.
      expect(
        SupplierCatalogApi.fromJson(<String, dynamic>{
          'kind': 'woocommerce_store_v1',
          'base_url': 'http://tienda.cl',
        }),
        isNull,
      );
      expect(
        SupplierCatalogApi.fromJson(<String, dynamic>{
          'kind': 'plataforma_inventada',
          'base_url': 'https://tienda.cl',
        }),
        isNull,
      );
    });

    test('la ruta la pone la plataforma, no la tienda', () {
      final api = SupplierCatalogApi.fromJson(<String, dynamic>{
        'kind': 'woocommerce_store_v1',
        'base_url': 'https://droppbike.cl/',
        'page_size': 50,
      })!;
      final uri = api.pageUri('camara', 2);
      expect(uri.path, '/wp-json/wc/store/v1/products');
      expect(uri.queryParameters['search'], 'camara');
      expect(uri.queryParameters['page'], '2');
      expect(uri.queryParameters['per_page'], '50');
    });
  });

  group('lo que la API entrega, el calce lo juzga igual', () {
    test('de Derman quedan las cámaras, no el cubre llanta', () {
      // La misma fixture real, pasada por el matcher determinista: la API sólo
      // cambia de dónde salen las filas, nunca quién decide si cumplen.
      final page = parseSupplierCatalogApiPage(
        kind: SupplierCatalogApiKind.prestashopSearchAjax,
        body: _fixture('derman_prestashop_camara700.json'),
      );
      final plan = buildSupplierNeedSearchPlan(
        request: const SupplierNeedSearchRequest(
          needId: 'need-tubes',
          description: 'Cámaras aro 700 para reposición del taller',
          categoryId: 'category-tubes',
          technicalFamily: 'tube',
          fields: <SupplierNeedSearchField>[
            SupplierNeedSearchField(
              key: 'valve_type',
              label: 'Tipo de válvula',
              dataType: 'single_select',
              allowedValues: <Object>['presta', 'schrader'],
            ),
          ],
          predicates: <SupplierNeedSearchPredicate>[
            SupplierNeedSearchPredicate(
              field: 'valve_type',
              operator: 'eq',
              values: <Object>['presta'],
            ),
          ],
        ),
        adapter: SupplierNeedPortalAdapter.fromJson(<String, dynamic>{
          'version': 1,
          'generic_family_search': true,
          'result_schema': <String, dynamic>{
            'columns': <String, dynamic>{
              'code': <String>['Referencia'],
              'name': <String>['Nombre'],
            },
          },
        }),
        maxLength: 15,
      )!;

      final matches = matchSupplierNeedCandidates(plan, page.candidates);
      final quedan = <String>{
        for (final match in matches)
          if (match.state != SupplierNeedMatchState.conflict)
            match.candidate.code,
      };

      // Tres cámaras F/V; la A/V se contradice y el cubre llanta no es cámara.
      expect(quedan, <String>{'PANARACER-70025/35', 'CM-0001864', '257225'});
      expect(quedan, isNot(contains('JN-700C')), reason: 'es un cubre llanta');
      expect(quedan, isNot(contains('CM-000251')), reason: 'es A/V');

      final tally = tallySupplierNeedMatchesUnder(
        matches: matches,
        predicates: const <SupplierNeedSearchPredicate>[
          SupplierNeedSearchPredicate(
            field: 'valve_type',
            operator: 'eq',
            values: <Object>['presta'],
          ),
        ],
      );
      expect(tally.confirmed, 3);
      expect(tally.unverified, 0);
    });
  });
}
