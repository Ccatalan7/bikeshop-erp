import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_price_list.dart';

void main() {
  group('catalogPlanIncludes', () {
    test('folds the lines under each numbered heading into its detail', () {
      final includes = catalogPlanIncludes(
        '1) Mantención de transmisión\n'
        'Limpieza profunda de:\n'
        '- Cadena\n'
        '- Ambos desviadores (cambios)\n'
        '- Piñón\n'
        '- Incluye lubricación\n'
        '2) Cables y piolas nuevas\n'
        '3) Revisión de los 4 ejes (apertura y re-engrasado):\n'
        '- Maza trasera\n'
        '- Motor (pedalier)\n'
        '4) Limpieza general: marco y ruedas. Se aplica renovador',
      );
      expect(includes.map((include) => include.title), [
        'Mantención de transmisión',
        'Cables y piolas nuevas',
        'Revisión de los 4 ejes (apertura y re-engrasado)',
        'Limpieza general: marco y ruedas. Se aplica renovador',
      ]);
      expect(
        includes[0].detail,
        'Limpieza profunda de: cadena, ambos desviadores (cambios), piñón, '
        'incluye lubricación',
      );
      expect(includes[1].detail, isEmpty);
      expect(includes[2].detail, 'maza trasera, motor (pedalier)');
    });

    test('without numbers each line is one include and acronyms keep case', () {
      expect(
        catalogPlanIncludes('- Ajuste de frenos\n\nRevisión SRAM\n')
            .map((include) => include.title),
        ['Ajuste de frenos', 'Revisión SRAM'],
      );
      expect(catalogPlanIncludes('  \n'), isEmpty);
    });
  });

  group('CatalogPriceList.build', () {
    const order = {'frenos': 2, 'mantenciones': 1, 'ruedas': 5};
    const names = {
      'frenos': 'Frenos',
      'mantenciones': 'Mantenciones',
      'ruedas': 'Ruedas',
    };

    CatalogPriceItem item(String id, num? price, String category) =>
        CatalogPriceItem(
          id: id,
          name: id,
          price: price,
          categoryId: category,
          description: category == 'mantenciones' ? '1) Algo' : '',
        );

    test('groups by category order, cheapest first, plans apart', () {
      final list = CatalogPriceList.build(
        items: [
          item('Centrado', 10000, 'ruedas'),
          item('Inflado', 0, 'ruedas'),
          item('Cámara', 1990, 'ruedas'),
          item('Purgado', 18000, 'frenos'),
          item('Full', 70000, 'mantenciones'),
          item('Básica', 24990, 'mantenciones'),
          item('Suelto', 5000, ''),
        ],
        compareCategories: (a, b) => order[a]!.compareTo(order[b]!),
        categoryLabel: (id) => names[id] ?? '',
        plansCategoryId: 'mantenciones',
      );
      expect(list.plans.map((plan) => plan.item.id), ['Básica', 'Full']);
      expect(list.plans.first.includes.single.title, 'Algo');
      expect(list.groups.map((group) => group.label), [
        'Frenos',
        'Ruedas',
        'Otros',
      ]);
      expect(list.groups[1].items.map((entry) => entry.id), [
        'Cámara',
        'Centrado',
        'Inflado',
      ]);
      expect(list.groups[1].items.last.priceLabel, 'Consultar');
      expect(list.listedCount, 5);
      expect(list.totalCount, 7);
    });
  });

  group('WebsiteCatalogPresentation price list', () {
    test('a price-list root keeps its hero, plans and closing band', () {
      final root = WebsiteCatalogPresentation.catalogRoot(
        WebsiteCatalogRoot.services,
      ).copyWith(
        layout: WebsiteCatalogLayout.priceList,
        heroTitle: 'Servicios del taller',
        heroDescription: 'Con su precio.',
        heroAction: const WebsiteActionValue(
          label: 'Agendar por WhatsApp',
          href: 'https://wa.me/56998357797',
        ),
        heroShowRating: true,
        plansCategoryId: 'plans-1',
        closingTitle: '¿No ves lo que necesitas?',
        closingAction: const WebsiteActionValue(
          label: 'Escribir',
          href: 'https://wa.me/56998357797',
          variant: WebsiteActionVariant.outline,
        ),
      );
      final restored = WebsiteCatalogPresentation.fromJson(root.toJson());
      expect(restored.layout, WebsiteCatalogLayout.priceList);
      expect(restored.heroTitle, 'Servicios del taller');
      expect(restored.heroAction?.label, 'Agendar por WhatsApp');
      expect(restored.heroShowRating, isTrue);
      expect(restored.plansCategoryId, 'plans-1');
      expect(restored.closingTitle, '¿No ves lo que necesitas?');
      expect(restored.closingAction?.variant, WebsiteActionVariant.outline);
      expect(restored.hasSamePersistedValue(root), isTrue);
    });

    test('a grid root keeps none of the price-list values', () {
      final grid = WebsiteCatalogPresentation.fromJson(const {
        'category_id': websiteServicesCatalogPresentationId,
        'layout': 'grid',
        'hero_title': 'Escondido',
        'hero_action': {'label': 'Ir', 'to': '/contacto'},
        'plans_category_id': 'plans-1',
        'closing_title': 'Escondido',
      });
      expect(grid.layout, WebsiteCatalogLayout.grid);
      expect(grid.heroTitle, isEmpty);
      expect(grid.heroAction, isNull);
      expect(grid.plansCategoryId, isEmpty);
      expect(grid.closingTitle, isEmpty);
    });

    test('only the services are a price list', () {
      final products = WebsiteCatalogPresentation.catalogRoot(
        WebsiteCatalogRoot.products,
      )
          .copyWith(
            layout: WebsiteCatalogLayout.priceList,
            heroTitle: 'Escondido',
            closingTitle: 'Escondido',
          )
          .normalizedForOwner();
      expect(products.layout, WebsiteCatalogLayout.grid);
      expect(products.heroTitle, isEmpty);
      expect(products.closingTitle, isEmpty);
    });

    test('a button half written is not saved', () {
      final services = WebsiteCatalogPresentation.catalogRoot(
        WebsiteCatalogRoot.services,
      )
          .copyWith(
            layout: WebsiteCatalogLayout.priceList,
            heroAction: const WebsiteActionValue(label: 'Agendar', href: ''),
            closingAction: const WebsiteActionValue(
              label: ' Escribir ',
              href: ' https://wa.me/56998357797 ',
            ),
          )
          .normalizedForOwner();
      expect(services.heroAction, isNull);
      expect(services.closingAction?.label, 'Escribir');
      expect(services.closingAction?.href, 'https://wa.me/56998357797');
    });

    test('the search folds accents, composed or decomposed, like NFD', () {
      const composed = CatalogPriceItem(
        id: 'a',
        name: 'Regulación de frenos',
        price: 4000,
        categoryId: 'frenos',
      );
      const decomposed = CatalogPriceItem(
        id: 'b',
        name: 'Regulacio\u0301n de frenos',
        price: 4000,
        categoryId: 'frenos',
      );
      for (final item in [composed, decomposed]) {
        expect(item.matches('regulacion'), isTrue, reason: item.id);
        expect(item.matches('REGULACIÓN'), isTrue, reason: item.id);
        expect(item.matches('purgado'), isFalse, reason: item.id);
        expect(item.matches('  '), isTrue, reason: item.id);
      }
    });

    test('the fullest plan is marked, the dearest of a tie, none alone', () {
      CatalogPriceList plans(List<(String, num, String)> rows) =>
          CatalogPriceList.build(
            items: [
              for (final (id, price, description) in rows)
                CatalogPriceItem(
                  id: id,
                  name: id,
                  price: price,
                  categoryId: 'p',
                  description: description,
                ),
            ],
            compareCategories: (a, b) => a.compareTo(b),
            categoryLabel: (_) => '',
            plansCategoryId: 'p',
          );
      expect(
        plans([('a', 1, '1) x\n2) y'), ('b', 2, '1) x')]).fullestPlan?.item.id,
        'a',
      );
      expect(
        plans([('a', 1, '1) x'), ('b', 2, '1) y')]).fullestPlan?.item.id,
        'b',
      );
      expect(plans([('a', 1, '1) x')]).fullestPlan, isNull);
    });

    test('the rating reads the synced setting, nothing without one', () {
      final settings = {
        'google_reviews_rating': '4.4',
        'google_reviews_total': '36',
      };
      final rating = CatalogPriceListRating.read((key) => settings[key] ?? '');
      expect(rating?.label, '4,4');
      expect(rating?.totalLabel, '36 reseñas en Google');
      expect(CatalogPriceListRating.read((_) => ''), isNull);
      expect(
        CatalogPriceListRating.read(
          (key) => key == 'google_reviews_rating' ? '5' : '1',
        )?.totalLabel,
        '1 reseña en Google',
      );
    });

    test('an action without label or destination is no action', () {
      final presentation = WebsiteCatalogPresentation.fromJson(const {
        'category_id': websiteServicesCatalogPresentationId,
        'layout': 'price_list',
        'hero_action': {'label': '', 'to': '/contacto'},
        'closing_action': {'label': 'Ir', 'to': ' '},
      });
      expect(presentation.heroAction, isNull);
      expect(presentation.closingAction, isNull);
    });
  });
}
