import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  Finder visibilityToggle(String label) => find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label,
      );

  WebsiteEditModeProvider providerForLegacyVisibility() {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        const <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'hero-1',
            'block_type': 'hero',
            'block_data': <String, dynamic>{
              'title': 'Portada',
              'visibility': <String, dynamic>{
                'desktop': true,
                'tablet': false,
                'mobile': true,
              },
            },
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
        pageId: 'page-visibility-a',
        pageSlug: '/visibility-a',
      )
      ..selectBlock('hero-1');
    provider.reportRenderedBlockViewport(
      'hero-1',
      WebsiteViewport.mobile,
    );
    return provider;
  }

  Map<String, dynamic> visibilityOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(
        provider.getBlockData('hero-1')['visibility'] as Map,
      );

  Widget host(WebsiteEditModeProvider provider) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.light,
      ),
      home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: WebsiteEditorChromeScope(
          editorWidth: 390,
          canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(390),
          child: Consumer<WebsiteEditModeProvider>(
            builder: (context, live, _) => Scaffold(
              body: WebsiteBlockEditSurface(
                editProvider: live,
                section: WebsiteBlockEditSection.layout,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'un mapa legacy ambiguo sólo migra tras confirmación explícita',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = providerForLegacyVisibility();
      addTearDown(provider.dispose);
      final original = visibilityOf(provider);

      await tester.pumpWidget(host(provider));
      await tester.pumpAndSettle();

      final mobileToggle = visibilityToggle('Móvil: visible');
      expect(mobileToggle, findsOneWidget);
      await tester.ensureVisible(mobileToggle);
      await tester.tap(mobileToggle);
      await tester.pumpAndSettle();

      expect(find.text('Actualizar puntos de quiebre'), findsOneWidget);
      expect(visibilityOf(provider), original);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(visibilityOf(provider), original);
      expect(provider.canUndo, isFalse);

      await tester.tap(visibilityToggle('Móvil: visible'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actualizar y continuar'));
      await tester.pumpAndSettle();

      expect(
        visibilityOf(provider),
        <String, dynamic>{
          'version': 2,
          'desktop': true,
          'tablet': false,
          'mobile': false,
        },
      );
      expect(provider.hasUnsavedChanges, isTrue);
      expect(provider.canUndo, isTrue);

      provider.undo();
      await tester.pump();
      expect(visibilityOf(provider), original);
      expect(provider.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmación abierta no puede escribir otro documento con el mismo id',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final provider = providerForLegacyVisibility();
      addTearDown(provider.dispose);
      await tester.pumpWidget(host(provider));
      await tester.pumpAndSettle();

      final mobileToggle = visibilityToggle('Móvil: visible');
      await tester.ensureVisible(mobileToggle);
      await tester.tap(mobileToggle);
      await tester.pumpAndSettle();
      expect(find.text('Actualizar puntos de quiebre'), findsOneWidget);

      const nextDocument = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'hero-1',
          'block_type': 'hero',
          'block_data': <String, dynamic>{
            'title': 'Otra portada',
            'visibility': <String, dynamic>{
              'desktop': false,
              'tablet': true,
              'mobile': true,
            },
          },
          'is_visible': true,
          'sort_order': 0,
        },
      ];
      provider
        ..enterEditMode(
          nextDocument,
          const <String, dynamic>{},
          pageId: 'page-visibility-b',
          pageSlug: '/visibility-b',
        )
        ..selectBlock('hero-1');
      provider.reportRenderedBlockViewport(
        'hero-1',
        WebsiteViewport.mobile,
      );
      await tester.pump();

      await tester.tap(find.text('Actualizar y continuar'));
      await tester.pumpAndSettle();

      expect(
        visibilityOf(provider),
        <String, dynamic>{
          'desktop': false,
          'tablet': true,
          'mobile': true,
        },
      );
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'confirmación abierta no puede cruzar a otro provider idéntico',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final providerA = providerForLegacyVisibility();
      final providerB = providerForLegacyVisibility();
      addTearDown(providerA.dispose);
      addTearDown(providerB.dispose);
      final originalA = visibilityOf(providerA);
      final originalB = visibilityOf(providerB);

      await tester.pumpWidget(host(providerA));
      await tester.pumpAndSettle();
      final mobileToggle = visibilityToggle('Móvil: visible');
      await tester.ensureVisible(mobileToggle);
      await tester.tap(mobileToggle);
      await tester.pumpAndSettle();
      expect(find.text('Actualizar puntos de quiebre'), findsOneWidget);

      await tester.pumpWidget(host(providerB));
      await tester.pump();
      expect(find.text('Actualizar puntos de quiebre'), findsOneWidget);
      await tester.tap(find.text('Actualizar y continuar'));
      await tester.pumpAndSettle();

      expect(visibilityOf(providerA), originalA);
      expect(visibilityOf(providerB), originalB);
      expect(providerA.canUndo, isFalse);
      expect(providerB.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
