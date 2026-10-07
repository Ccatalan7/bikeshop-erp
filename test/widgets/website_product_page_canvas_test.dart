import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_product_canvas.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_host_theme.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_public_core/modules/website/models/website_product_page_template.dart';

/// A real product of the store (2026-10-06): a fork with a technical sheet.
const _fork = WebsiteProductCanvasContext(
  productName: 'Horquilla Suntour 29 Auron 35',
  technical: true,
  highlightCount: 4,
  relatedCount: 4,
  hasPromises: true,
  service: false,
);

final _publisher = Object();

String _id(WebsiteProductPageSection section) =>
    WebsiteProductSectionTarget(section).selectionId;

WebsiteEditModeProvider _editor({Map<String, dynamic> settings = const {}}) {
  final provider = WebsiteEditModeProvider()
    ..enterEditMode(
      const <Map<String, dynamic>>[],
      settings,
      pageSlug: 'productos',
    )
    ..publishProductCanvas(_fork, publisher: _publisher);
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
  group('the product page is one template on the canvas', () {
    test('its sections exist while a product page is drawn', () {
      final provider = _editor()
        ..selectBlock(_id(WebsiteProductPageSection.sheet));
      expect(provider.selectedBlockId, _id(WebsiteProductPageSection.sheet));
      expect(
        WebsiteProductSectionTarget.parse(provider.selectedBlockId)?.section,
        WebsiteProductPageSection.sheet,
      );

      provider.releaseProductCanvas(_publisher);
      expect(provider.productCanvas, isNull);
      expect(provider.selectedBlockId, isNull);
    });

    test('a value equal to the saved template is no change', () {
      final saved = const WebsiteProductPageTemplate(
        relatedTitle: 'Te puede servir',
      ).encode();
      final provider = _editor(
        settings: {websiteProductPageTemplateSettingKey: saved},
      );
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.effectiveProductPageTemplate.relatedTitle,
          'Te puede servir');

      provider.stageProductPageTemplate(
        provider.effectiveProductPageTemplate.copyWith(showBuyNow: false),
      );
      expect(provider.hasUnsavedChanges, isTrue);
      expect(
        provider.pendingSiteSettings.keys,
        [websiteProductPageTemplateSettingKey],
      );

      provider.stageProductPageTemplate(
        provider.effectiveProductPageTemplate.copyWith(showBuyNow: true),
      );
      expect(provider.pendingSiteSettings, isEmpty);
      expect(provider.hasUnsavedChanges, isFalse);
    });

    testWidgets(
        'its buy column says it is the template and stages what it shows',
        (tester) async {
      final provider = _editor()
        ..selectBlock(_id(WebsiteProductPageSection.buy));
      await _pumpInspector(tester, provider);

      expect(find.text('Plantilla · cambia todas las fichas'), findsOneWidget);
      for (final group in ['Fotos', 'Precio', 'Botones']) {
        expect(find.text(group), findsOneWidget, reason: group);
      }
      expect(find.textContaining('4 en Horquilla Suntour'), findsOneWidget);

      await tester.tap(find.text('Derecha'));
      await tester.pump();
      expect(
        provider.effectiveProductPageTemplate.photoSide,
        WebsiteProductPhotoSide.right,
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('product-show-buy-now')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      expect(provider.effectiveProductPageTemplate.showBuyNow, isFalse);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('product-add-label')),
          matching: find.byType(TextFormField),
        ),
        'Lo quiero',
      );
      await tester.pump();
      expect(
        provider.effectiveProductPageTemplate.resolvedAddToCartLabel,
        'Lo quiero',
      );
      expect(provider.hasUnsavedChanges, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'its delivery and pickup texts are the site\'s, now in the editor',
        (tester) async {
      final provider = _editor()
        ..selectBlock(_id(WebsiteProductPageSection.buy));
      await _pumpInspector(tester, provider);

      await tester.tap(find.text('Despacho y retiro'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('product-pickup-detail')),
          matching: find.byType(TextFormField),
        ),
        'Álvarez 32, local 17, de lunes a sábado',
      );
      await tester.pump();
      expect(
        provider.pendingSiteSettings['pickup_promise_detail'],
        'Álvarez 32, local 17, de lunes a sábado',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('its sheet and related sections stage their words',
        (tester) async {
      final provider = _editor()
        ..selectBlock(_id(WebsiteProductPageSection.sheet));
      await _pumpInspector(tester, provider);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('product-sheet-title')),
          matching: find.byType(TextFormField),
        ),
        'Especificaciones',
      );
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('product-show-help')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      final staged = provider.effectiveProductPageTemplate;
      expect(staged.resolvedSheetTitle(technical: true), 'Especificaciones');
      expect(staged.showHelp, isFalse);

      provider.selectBlock(_id(WebsiteProductPageSection.related));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('product-show-related')),
          matching: find.byType(Switch),
        ),
      );
      await tester.pump();
      expect(provider.effectiveProductPageTemplate.showRelated, isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
