import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_catalog_canvas.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_host_theme.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/public_store/widgets/catalog_collection_presentation.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// «Frenos» as it is in production (2026-10-06): a published subcategory of
/// Componentes, with its presentation still at the defaults.
const _frenos = '9307b385-e9f7-46d2-8906-e5da8ab15ad6';

WebsiteCatalogPresentation _saved() => WebsiteCatalogPresentation.fallback(
      categoryId: _frenos,
      categoryName: 'Frenos',
    );

WebsiteCatalogCanvasContext _category() => WebsiteCatalogCanvasContext(
      saved: _saved(),
      rootLabel: 'Frenos',
      noun: 'productos',
      itemCount: 48,
      groupCount: 2,
      planCount: 0,
      categories: const [
        WebsiteCatalogCanvasCategory(
          id: 'discos',
          name: 'Discos',
          itemCount: 20,
        ),
        WebsiteCatalogCanvasCategory(
          id: 'pastillas',
          name: 'Pastillas',
          itemCount: 28,
        ),
      ],
      collection: true,
    );

final _publisher = Object();

String _id(WebsiteCatalogSection section) =>
    WebsiteCatalogSectionTarget(_frenos, section).selectionId;

WebsiteEditModeProvider _editor(WebsiteCatalogCanvasContext canvas) {
  final provider = WebsiteEditModeProvider()
    ..enterEditMode(
      const <Map<String, dynamic>>[],
      const <String, dynamic>{},
      pageSlug: 'productos',
    )
    ..publishCatalogCanvas(canvas, publisher: _publisher);
  addTearDown(provider.dispose);
  return provider;
}

Future<void> _pumpInspector(
  WidgetTester tester,
  WebsiteEditModeProvider provider,
) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(420, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.dark,
      ),
      home: Builder(
        builder: (hostContext) => ChangeNotifierProvider.value(
          value: provider,
          child: WebsiteEditorChromeScope(
            editorWidth: 420,
            canvasWidth: 420,
            child: WebsiteEditorAuthoringViewportScope(
              requestedViewport: WebsiteViewport.desktop,
              effectiveViewport: WebsiteViewport.desktop,
              child: Theme(
                data: WebsiteEditorInspectorTheme.resolveFrom(hostContext),
                child: Consumer<WebsiteEditModeProvider>(
                  builder: (context, live, _) => Scaffold(
                    body: WebsiteBlockEditSurface(
                      editProvider: live,
                      section: WebsiteBlockEditSection.content,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('which sections a catalog page has is what it draws', () {
    test('a category: its portada and its products, never plans or closing',
        () {
      final provider = _editor(_category());
      bool available(WebsiteCatalogSection section) =>
          provider.isCatalogSectionAvailable(
            WebsiteCatalogSectionTarget(_frenos, section),
          );
      expect(available(WebsiteCatalogSection.page), isTrue);
      expect(available(WebsiteCatalogSection.hero), isTrue);
      expect(available(WebsiteCatalogSection.list), isTrue);
      expect(available(WebsiteCatalogSection.plans), isFalse);
      expect(available(WebsiteCatalogSection.closing), isFalse);
    });

    test('a category saved as a price list is still drawn as a grid', () {
      final provider = _editor(
        WebsiteCatalogCanvasContext(
          saved: _saved().copyWith(layout: WebsiteCatalogLayout.priceList),
          rootLabel: 'Frenos',
          noun: 'productos',
          itemCount: 48,
          groupCount: 0,
          planCount: 0,
          categories: const [],
          collection: true,
        ),
      );
      expect(
        provider.isCatalogSectionAvailable(
          WebsiteCatalogSectionTarget(_frenos, WebsiteCatalogSection.plans),
        ),
        isFalse,
      );
    });

    test('/productos: its products and its page, no portada', () {
      const owner = '@catalog/products';
      final provider = _editor(
        WebsiteCatalogCanvasContext(
          saved: WebsiteCatalogPresentation.catalogRoot(
            WebsiteCatalogRoot.products,
          ),
          rootLabel: 'Productos',
          noun: 'productos',
          itemCount: 812,
          groupCount: 0,
          planCount: 0,
          categories: const [],
        ),
      );
      bool available(WebsiteCatalogSection section) =>
          provider.isCatalogSectionAvailable(
            WebsiteCatalogSectionTarget(owner, section),
          );
      expect(available(WebsiteCatalogSection.list), isTrue);
      expect(available(WebsiteCatalogSection.page), isTrue);
      expect(available(WebsiteCatalogSection.hero), isFalse);
    });
  });

  group('a category page in the editor', () {
    testWidgets('lists its portada and its products, and where they change',
        (tester) async {
      final provider = _editor(_category());
      await _pumpInspector(tester, provider);

      expect(find.text('Frenos'), findsOneWidget);
      expect(find.text('Portada'), findsOneWidget);
      expect(find.text('Todos los productos'), findsOneWidget);
      expect(find.text('del catálogo · 48'), findsOneWidget);
      expect(find.text('En Google'), findsOneWidget);
      expect(find.text('Diseño y Google'), findsNothing);
      expect(find.text('Abrir categorías en Inventario'), findsOneWidget);

      await tester.tap(find.text('Portada'));
      await tester.pumpAndSettle();
      expect(provider.selectedBlockId, _id(WebsiteCatalogSection.hero));
    });

    testWidgets(
        'its portada edits its own texts and look, staged for «Guardar»',
        (tester) async {
      final provider = _editor(_category())
        ..selectBlock(_id(WebsiteCatalogSection.hero));
      await _pumpInspector(tester, provider);

      for (final group in [
        'Textos',
        'Foto y color',
        'Alto y alineación',
        'Subcategorías',
      ]) {
        expect(find.text(group), findsOneWidget, reason: group);
      }
      // A category's portada has no button and no Google rating.
      expect(find.text('Botón'), findsNothing);
      expect(find.text('Calificación de Google'), findsNothing);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('catalog-hero-title')),
          matching: find.byType(TextFormField),
        ),
        'Frenos de disco y v-brake',
      );
      await tester.pump();
      expect(provider.hasUnsavedChanges, isTrue);
      expect(
        provider.effectiveCatalogPresentation(_saved()).heroTitle,
        'Frenos de disco y v-brake',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('its products choose the cards, the filters and the trail',
        (tester) async {
      final provider = _editor(_category())
        ..selectBlock(_id(WebsiteCatalogSection.list));
      await _pumpInspector(tester, provider);

      expect(find.text('Tarjetas'), findsOneWidget);
      expect(find.text('Filtros'), findsOneWidget);
      expect(find.text('Ruta'), findsOneWidget);

      await tester.tap(find.text('Compacta'));
      await tester.pump();
      expect(
        provider.effectiveCatalogPresentation(_saved()).gridDensity,
        WebsiteCatalogGridDensity.compact,
      );

      final brandOn = _saved().facets.contains(WebsiteCatalogFacet.brand);
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('catalog-facet-brand')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      expect(
        provider
            .effectiveCatalogPresentation(_saved())
            .facets
            .contains(WebsiteCatalogFacet.brand),
        !brandOn,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('its filters go in the order the list shows', (tester) async {
      final provider = _editor(_category())
        ..selectBlock(_id(WebsiteCatalogSection.list));
      await _pumpInspector(tester, provider);
      expect(_saved().facets, [
        WebsiteCatalogFacet.categories,
        WebsiteCatalogFacet.availability,
      ]);

      await tester.tap(
        find.byKey(const ValueKey('catalog-facet-up-availability')),
      );
      await tester.pump();
      expect(provider.effectiveCatalogPresentation(_saved()).facets, [
        WebsiteCatalogFacet.availability,
        WebsiteCatalogFacet.categories,
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'its page moves its address and «Restablecer» keeps it, in the '
        'draft', (tester) async {
      final provider = _editor(_category())
        ..selectBlock(_id(WebsiteCatalogSection.page))
        ..stageCatalogPresentation(
          _saved().copyWith(heroTitle: 'Frenos de disco'),
          saved: _saved(),
        );
      await _pumpInspector(tester, provider);
      for (final group in ['Dirección', 'En el menú', 'Restablecer']) {
        expect(find.text(group), findsWidgets, reason: group);
      }

      await tester.tap(find.text('Dirección').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('catalog-slug')),
          matching: find.byType(TextFormField),
        ),
        'frenos-mtb',
      );
      await tester.pump();
      expect(
        provider.effectiveCatalogPresentation(_saved()).slug,
        'frenos-mtb',
      );
      expect(find.text('/productos/categoria/frenos-mtb'), findsOneWidget);

      await tester.tap(find.text('Restablecer'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('catalog-reset-presentation')),
      );
      await tester.pump();
      final reset = provider.effectiveCatalogPresentation(_saved());
      expect(reset.heroTitle, isEmpty);
      expect(reset.slug, 'frenos-mtb');
      expect(provider.hasUnsavedChanges, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('its page has Google, not a price-list choice', (tester) async {
      final provider = _editor(_category())
        ..selectBlock(_id(WebsiteCatalogSection.page));
      await _pumpInspector(tester, provider);
      expect(find.text('En Google'), findsWidgets);
      expect(find.text('Lista de precios'), findsNothing);
    });
  });

  group('the shared portada', () {
    Widget host(CatalogCollectionEditing? editing) => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CatalogCollectionPresentationHeader(
                presentation: _saved(),
                title: 'Frenos',
                description: 'Discos, pastillas y v-brake.',
                imageUrl: '',
                breadcrumbs: const [],
                subcategories: const [],
                compact: false,
                editing: editing,
              ),
            ),
          ),
        );

    testWidgets('is drawn as is on the site', (tester) async {
      await tester.pumpWidget(host(null));
      expect(find.text('FRENOS'), findsOneWidget);
      expect(find.text('Discos, pastillas y v-brake.'), findsOneWidget);
    });

    testWidgets(
        'in the editor draws what the customer sees, and offers an empty label '
        'only while chosen', (tester) async {
      final asked = <CatalogCollectionField, ({String text, String hint})>{};
      var chosen = false;
      int? descriptionLines;
      Widget build() => host(
            CatalogCollectionEditing(
              showsEmpty: (_) => chosen,
              fallbackTitle: 'Frenos',
              fallbackDescription: 'Discos, pastillas y v-brake.',
              text: (
                field, {
                required text,
                required style,
                required textAlign,
                required placeholder,
                required uppercase,
                maxLines,
              }) {
                asked[field] = (text: text, hint: placeholder);
                if (field == CatalogCollectionField.description) {
                  descriptionLines = maxLines;
                }
                return Text('[$field]');
              },
            ),
          );

      await tester.pumpWidget(build());
      // What the customer sees: the category's name, not a placeholder.
      expect(
        asked[CatalogCollectionField.title],
        (text: 'Frenos', hint: 'Frenos'),
      );
      expect(
        asked[CatalogCollectionField.description]?.hint,
        'Discos, pastillas y v-brake.',
      );
      expect(asked.containsKey(CatalogCollectionField.eyebrow), isFalse);
      // Within the site's own limit, so the portada keeps its height.
      expect(descriptionLines, 4);

      chosen = true;
      await tester.pumpWidget(build());
      expect(asked.containsKey(CatalogCollectionField.eyebrow), isTrue);
    });
  });
}
