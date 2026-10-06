import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_price_list.dart';

import 'package:vinabike_erp/modules/website/models/website_catalog_canvas.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_host_theme.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/public_store/widgets/catalog_price_list_view.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

const _owner = websiteServicesCatalogPresentationId;

WebsiteCatalogPresentation _saved() =>
    WebsiteCatalogPresentation.catalogRoot(WebsiteCatalogRoot.services)
        .copyWith(
      layout: WebsiteCatalogLayout.priceList,
      heroTitle: 'Servicios del taller',
      heroDescription: 'Con su precio, IVA incluido.',
      plansCategoryId: 'mantenciones',
      closingTitle: '¿No ves lo que necesitas?',
    );

WebsiteCatalogCanvasContext _canvas() => WebsiteCatalogCanvasContext(
      saved: _saved(),
      rootLabel: 'Servicios',
      noun: 'servicios',
      itemCount: 62,
      groupCount: 9,
      planCount: 3,
      categories: const [
        WebsiteCatalogCanvasCategory(
          id: 'mantenciones',
          name: 'Mantenciones',
          itemCount: 3,
        ),
        WebsiteCatalogCanvasCategory(
            id: 'frenos', name: 'Frenos', itemCount: 8),
      ],
      ratingSummary: '4,4 de 5 · 36 reseñas',
    );

final _publisher = Object();

String _id(WebsiteCatalogSection section) =>
    WebsiteCatalogSectionTarget(_owner, section).selectionId;

void main() {
  group('catalog section selection ids', () {
    test('round-trip the owner and the section', () {
      for (final section in WebsiteCatalogSection.values) {
        final target = WebsiteCatalogSectionTarget(_owner, section);
        expect(WebsiteCatalogSectionTarget.parse(target.selectionId), target);
      }
      expect(
        WebsiteCatalogSectionTarget.parse(
          'catalog:6f1c2a3e-1111-4111-8111-111111111111:closing',
        )?.ownerId,
        '6f1c2a3e-1111-4111-8111-111111111111',
      );
      for (final notOne in [
        null,
        'header',
        'hero-1',
        'catalog:',
        'catalog:x'
      ]) {
        expect(WebsiteCatalogSectionTarget.parse(notOne), isNull);
      }
    });
  });

  group('the catalog page inspector', () {
    WebsiteEditModeProvider editor() {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const <Map<String, dynamic>>[],
          const <String, dynamic>{},
          pageSlug: 'servicios',
        )
        ..publishCatalogCanvas(_canvas(), publisher: _publisher);
      addTearDown(provider.dispose);
      return provider;
    }

    Future<void> pump(
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

    testWidgets(
        'with nothing selected lists the sections, says what comes from the '
        'catalog, and selects one', (tester) async {
      final provider = editor();
      await pump(tester, provider);

      for (final label in [
        'Secciones',
        'Servicios',
        'Encabezado',
        'Portada',
        'Planes',
        'Todos los servicios',
        'Cierre',
        'Pie de página',
        'Diseño y Google',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('del catálogo · 3'), findsOneWidget);
      expect(find.text('del catálogo · 59'), findsOneWidget);
      expect(find.text('Lo que viene del catálogo'), findsOneWidget);
      expect(find.text('Abrir servicios en Inventario'), findsOneWidget);

      await tester.tap(find.text('Portada'));
      await tester.pumpAndSettle();
      expect(provider.selectedBlockId, _id(WebsiteCatalogSection.hero));
    });

    testWidgets(
        'a section shows only its own controls and stages what is written '
        'into the draft «Guardar» saves', (tester) async {
      final provider = editor()..selectBlock(_id(WebsiteCatalogSection.hero));
      await pump(tester, provider);

      expect(find.text('Textos'), findsOneWidget);
      expect(find.text('Botón'), findsOneWidget);
      expect(find.text('Calificación de Google'), findsOneWidget);
      // Not this section's: the plans' source and the page's layout.
      expect(find.text('De dónde salen'), findsNothing);
      expect(find.text('Diseño'), findsNothing);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('catalog-hero-title')),
          matching: find.byType(TextFormField),
        ),
        'Taller y precios',
      );
      await tester.pump();
      expect(provider.hasCatalogPresentationChanges, isTrue);
      expect(provider.hasUnsavedChanges, isTrue);
      expect(
        provider.effectiveCatalogPresentation(_saved()).heroTitle,
        'Taller y precios',
      );

      // Written back to the saved value: nothing left to save.
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('catalog-hero-title')),
          matching: find.byType(TextFormField),
        ),
        'Servicios del taller',
      );
      await tester.pump();
      expect(provider.hasUnsavedChanges, isFalse);
    });

    testWidgets(
        'the page section warns before a grid drops the price list sections',
        (tester) async {
      final provider = editor()..selectBlock(_id(WebsiteCatalogSection.page));
      await pump(tester, provider);

      expect(find.textContaining('se borran al guardar'), findsNothing);
      await tester.tap(find.text('Cuadrícula'));
      await tester.pumpAndSettle();
      expect(
        provider.effectiveCatalogPresentation(_saved()).layout,
        WebsiteCatalogLayout.grid,
      );
      expect(find.textContaining('se borran al guardar'), findsOneWidget);
    });

    testWidgets('the plans come from a category named with its count',
        (tester) async {
      final provider = editor()..selectBlock(_id(WebsiteCatalogSection.plans));
      await pump(tester, provider);

      expect(find.text('Mantenciones · 3 servicios'), findsOneWidget);
      expect(find.textContaining('3 planes.'), findsOneWidget);
    });

    testWidgets(
        'a section gone with its layout or its page is no longer selected',
        (tester) async {
      final provider = editor()..selectBlock(_id(WebsiteCatalogSection.hero));
      expect(
        provider.isCatalogSectionAvailable(
          const WebsiteCatalogSectionTarget(_owner, WebsiteCatalogSection.hero),
        ),
        isTrue,
      );

      // As a grid there is no portada: its page stays selected.
      provider.stageCatalogPresentation(
        _saved().copyWith(layout: WebsiteCatalogLayout.grid),
        saved: _saved(),
      );
      expect(provider.selectedBlockId, _id(WebsiteCatalogSection.page));

      // Another instance of the page cannot take back this one's canvas.
      provider.releaseCatalogCanvas(Object());
      expect(provider.catalogCanvas, isNotNull);

      provider.releaseCatalogCanvas(_publisher);
      await tester.pump();
      expect(provider.catalogCanvas, isNull);
      expect(provider.selectedBlockId, isNull);
    });

    testWidgets('leaving the editor drops the catalog draft', (tester) async {
      final provider = editor()..selectBlock(_id(WebsiteCatalogSection.hero));
      provider.stageCatalogPresentation(
        _saved().copyWith(heroEyebrow: 'Viña del Mar'),
        saved: _saved(),
      );
      expect(provider.hasUnsavedChanges, isTrue);
      provider.closeEditor();
      await tester.pump();
      expect(provider.hasCatalogPresentationChanges, isFalse);
    });
  });

  group('the price list on the canvas', () {
    CatalogPriceList list() => CatalogPriceList.build(
          items: const [
            CatalogPriceItem(
              id: 'p1',
              name: 'Mantención Básica',
              price: 24990,
              categoryId: 'mantenciones',
              description: 'Regulación de frenos y cambios',
            ),
            CatalogPriceItem(
              id: 's1',
              name: 'Purgado de frenos',
              price: 15000,
              categoryId: 'frenos',
              description: '',
            ),
          ],
          compareCategories: (a, b) => a.compareTo(b),
          categoryLabel: (id) => id == 'frenos' ? 'Frenos' : 'Mantenciones',
          plansCategoryId: 'mantenciones',
        );

    Future<void> pump(
      WidgetTester tester, {
      CatalogPriceListEditing? editing,
      WebsiteCatalogPresentation? presentation,
    }) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1280, 3200);
      addTearDown(tester.view.reset);
      final shown = presentation ?? _saved();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CatalogPriceListView(
                presentation: shown,
                list: list(),
                title: shown.heroTitle.isEmpty ? 'Servicios' : shown.heroTitle,
                intro: shown.heroDescription,
                heroImageUrl: '',
                rootLabel: 'Servicios',
                plansTitle: 'Mantenciones',
                plansIntro: '',
                editing: editing,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets(
        'wraps each section for the editor and hands it the presentation '
        'texts; an empty one only while offered', (tester) async {
      final sections = <CatalogPriceListSection>[];
      final written = <CatalogPriceListField, String>{};
      var offerEmpty = false;
      CatalogPriceListEditing editing() => CatalogPriceListEditing(
            section: (section, child) {
              sections.add(section);
              return KeyedSubtree(
                key: ValueKey('section-${section.name}'),
                child: child,
              );
            },
            showsEmpty: (_) => offerEmpty,
            text: (
              field, {
              required text,
              required style,
              required textAlign,
              required placeholder,
              required uppercase,
            }) {
              written[field] = text;
              return Text(text.isEmpty ? placeholder : text, style: style);
            },
          );

      await pump(tester, editing: editing());
      expect(sections, [
        CatalogPriceListSection.hero,
        CatalogPriceListSection.plans,
        CatalogPriceListSection.list,
        CatalogPriceListSection.closing,
      ]);
      // The canvas writes the saved title, not its uppercase rendering.
      expect(written[CatalogPriceListField.title], 'Servicios del taller');
      expect(
          written[CatalogPriceListField.intro], 'Con su precio, IVA incluido.');
      expect(
        written[CatalogPriceListField.closingTitle],
        '¿No ves lo que necesitas?',
      );
      expect(written.containsKey(CatalogPriceListField.eyebrow), isFalse);

      offerEmpty = true;
      sections.clear();
      written.clear();
      await pump(tester, editing: editing());
      expect(written[CatalogPriceListField.eyebrow], '');
      expect(find.text('Etiqueta sobre el título'), findsOneWidget);
    });

    testWidgets('the store draws the same texts with no editor',
        (tester) async {
      await pump(tester);
      expect(find.text('SERVICIOS DEL TALLER'), findsOneWidget);
      expect(find.text('Con su precio, IVA incluido.'), findsOneWidget);
      expect(find.text('¿NO VES LO QUE NECESITAS?'), findsOneWidget);
      expect(find.text('Etiqueta sobre el título'), findsNothing);
    });
  });
}
