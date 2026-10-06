import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/widgets/catalog_price_list_view.dart';
import 'package:vinabike_public_core/modules/website/models/website_action.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_price_list.dart';

void main() {
  const plans = 'plans';
  const order = {plans: 1, 'frenos': 2, 'ruedas': 3};
  const names = {plans: 'Mantenciones', 'frenos': 'Frenos', 'ruedas': 'Ruedas'};

  final presentation = WebsiteCatalogPresentation.catalogRoot(
    WebsiteCatalogRoot.services,
  ).copyWith(
    layout: WebsiteCatalogLayout.priceList,
    heroTitle: 'Servicios del taller',
    heroAction: const WebsiteActionValue(
      label: 'Agendar por WhatsApp',
      href: 'https://wa.me/56998357797',
    ),
    heroShowRating: true,
    plansCategoryId: plans,
    closingTitle: '¿No ves lo que necesitas?',
  );

  CatalogPriceList list() => CatalogPriceList.build(
        items: const [
          CatalogPriceItem(
            id: 'basica',
            name: 'Mantención Básica',
            price: 24990,
            categoryId: plans,
            description: '1) Cambio de piolas\n2) Ajuste de cambios',
          ),
          CatalogPriceItem(
            id: 'full',
            name: 'Mantención Full',
            price: 70000,
            categoryId: plans,
            description: '1) Desarme\n2) Transmisión\n- Cadena\n3) Centrado',
          ),
          CatalogPriceItem(
            id: 'purgado',
            name: 'Purgado de frenos',
            price: 18000,
            categoryId: 'frenos',
          ),
          CatalogPriceItem(
            id: 'regulacion',
            name: 'Regulación de frenos',
            price: 4000,
            categoryId: 'frenos',
          ),
          CatalogPriceItem(
            id: 'centrado',
            name: 'Centrado de rueda',
            price: 10000,
            categoryId: 'ruedas',
          ),
        ],
        compareCategories: (a, b) => order[a]!.compareTo(order[b]!),
        categoryLabel: (id) => names[id] ?? '',
        plansCategoryId: plans,
      );

  Widget view({
    String initialQuery = '',
    bool Function(String href)? isActionShown,
    List<String>? opened,
  }) =>
      CatalogPriceListView(
        presentation: presentation,
        list: list(),
        title: presentation.heroTitle,
        intro: 'Con su precio, IVA incluido.',
        heroImageUrl: '',
        rootLabel: 'Servicios',
        plansTitle: 'Mantenciones',
        plansIntro: 'Para dejar la bici al día de una vez.',
        rating: const CatalogPriceListRating(4.4, 36),
        initialQuery: initialQuery,
        isActionShown: isActionShown,
        onOpenItem: opened?.add,
        onAction: opened == null ? null : (action) => opened.add(action.href),
      );

  Future<List<String>> pump(
    WidgetTester tester, {
    required Size size,
  }) async {
    final opened = <String>[];
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: view(opened: opened)),
        ),
      ),
    );
    return opened;
  }

  testWidgets(
    'draws the hero, the plans with the fullest marked, every group and '
    'the closing band',
    (tester) async {
      final opened = await pump(tester, size: const Size(1280, 3200));
      expect(find.text('SERVICIOS DEL TALLER'), findsOneWidget);
      expect(find.text('4,4'), findsOneWidget);
      expect(find.text('36 reseñas en Google'), findsOneWidget);
      expect(find.text('MANTENCIONES'), findsOneWidget);
      expect(
          find.text('Para dejar la bici al día de una vez.'), findsOneWidget);
      // Only the plan that includes the most is marked.
      expect(find.text('LA MÁS COMPLETA'), findsOneWidget);
      expect(find.text('\$ 24.990'), findsOneWidget);
      expect(find.text('Cadena'), findsOneWidget);
      expect(find.text('TODOS LOS SERVICIOS'), findsOneWidget);
      expect(find.text('FRENOS'), findsOneWidget);
      expect(find.text('2 servicios'), findsOneWidget);
      expect(find.text('1 servicio'), findsOneWidget);
      // Cheapest first inside a group, in reading order (two columns).
      final cheaper = tester.getTopLeft(find.text('Regulación de frenos'));
      final dearer = tester.getTopLeft(find.text('Purgado de frenos'));
      expect(
        cheaper.dy < dearer.dy ||
            (cheaper.dy == dearer.dy && cheaper.dx < dearer.dx),
        isTrue,
      );
      expect(find.text('¿NO VES LO QUE NECESITAS?'), findsOneWidget);

      await tester.tap(find.text('Purgado de frenos'));
      await tester.tap(find.text('AGENDAR POR WHATSAPP').first);
      expect(opened, ['purgado', 'https://wa.me/56998357797']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the search keeps the groups that match, accents aside', (
    tester,
  ) async {
    await pump(tester, size: const Size(1280, 3200));
    await tester.enterText(find.byType(TextField), 'regulacion');
    await tester.pump();
    expect(find.text('Regulación de frenos'), findsOneWidget);
    expect(find.text('Purgado de frenos'), findsNothing);
    expect(find.text('RUEDAS'), findsNothing);

    await tester.enterText(find.byType(TextField), 'cadena');
    await tester.pump();
    expect(find.text('No hay servicios con ese nombre.'), findsOneWidget);
  });

  testWidgets('on a phone every group but the first folds until opened', (
    tester,
  ) async {
    await pump(tester, size: const Size(390, 4200));
    expect(find.text('Regulación de frenos'), findsOneWidget);
    expect(find.text('Centrado de rueda'), findsNothing);
    await tester.tap(find.text('RUEDAS'));
    await tester.pump();
    expect(find.text('Centrado de rueda'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an action a visitor may not follow is not drawn', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1280, 3200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: view(isActionShown: (href) => !href.contains('wa.me')),
          ),
        ),
      ),
    );
    expect(find.text('AGENDAR POR WHATSAPP'), findsNothing);
    expect(find.text('MANTENCIONES'), findsOneWidget);
  });

  testWidgets('a new ?q= replaces the search', (tester) async {
    tester.view
      ..physicalSize = const Size(1280, 3200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Widget app(String query) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: view(initialQuery: query)),
          ),
        );
    await tester.pumpWidget(app('purgado'));
    expect(find.text('Purgado de frenos'), findsOneWidget);
    expect(find.text('Centrado de rueda'), findsNothing);
    await tester.pumpWidget(app('centrado'));
    await tester.pump();
    expect(find.text('Centrado de rueda'), findsOneWidget);
    expect(find.text('Purgado de frenos'), findsNothing);
  });
}
