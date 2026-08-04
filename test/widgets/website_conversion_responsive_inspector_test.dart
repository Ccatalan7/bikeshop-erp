import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_projection.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/inline_editable_text_v2.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_field_shell.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_edit_section.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_contact_block_content.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_chrome_geometry.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/modules/website/widgets/website_inline_action_editor.dart';
import 'package:vinabike_erp/modules/website/widgets/website_pricing_block_content.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// El lote de conversión por sus superficies reales.
///
/// Las tres familias cierran compartidas, así que lo que hay que demostrar es
/// lo contrario de un override: que el inspector no ofrece ninguno, que la
/// tienda compone por ancho y que el pie de página sigue teniendo un solo
/// dueño. Esta ronda no introduce ningún valor visual, así que no se consultó
/// DesignSync.
void main() {
  WebsiteEditModeProvider providerFor(
    String type,
    Map<String, dynamic> data, {
    DevicePreviewMode viewport = DevicePreviewMode.mobile,
  }) {
    return WebsiteEditModeProvider()
      ..enterEditMode(
        <Map<String, dynamic>>[
          {
            'id': 'block-1',
            'block_type': type,
            'block_data': data,
            'is_visible': true,
            'sort_order': 0,
          },
        ],
        const <String, dynamic>{},
      )
      ..selectBlock('block-1')
      ..setDevicePreviewMode(viewport);
  }

  Map<String, dynamic> dataOf(WebsiteEditModeProvider provider) =>
      Map<String, dynamic>.from(provider.blocks.single['block_data'] as Map);

  List<Map<String, dynamic>> plansOf(WebsiteEditModeProvider provider) =>
      (dataOf(provider)['plans'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);

  void useViewport(
    WidgetTester tester, {
    required double width,
    double height = 2400,
  }) {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Finder shellFinder() =>
      find.byWidgetPredicate((widget) => widget is ResponsiveFieldShell);

  Future<WebsiteEditModeProvider> pumpInspector(
    WidgetTester tester, {
    required String type,
    required Map<String, dynamic> data,
    required double width,
    required DevicePreviewMode viewport,
    Brightness brightness = Brightness.light,
  }) async {
    useViewport(tester, width: width);
    final provider = providerFor(type, data, viewport: viewport);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: brightness,
        ),
        home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: WebsiteEditorChromeScope(
            editorWidth: width,
            canvasWidth: WebsiteEditorChromeGeometry.canvasWidthFor(width),
            child: Consumer<WebsiteEditModeProvider>(
              builder: (context, watched, _) => Scaffold(
                body: WebsiteBlockEditSurface(
                  editProvider: watched,
                  section: WebsiteBlockEditSection.content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return provider;
  }

  Future<void> pumpEditableBlock(
    WidgetTester tester, {
    required WebsiteEditModeProvider provider,
    required String type,
    required double width,
  }) async {
    useViewport(tester, width: width);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: Brightness.light,
        ),
        home: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
          value: provider,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Consumer<WebsiteEditModeProvider>(
                builder: (context, watched, _) => EditableBlockRenderer.build(
                  context: context,
                  blockId: 'block-1',
                  blockType: type,
                  data: Map<String, dynamic>.from(
                    watched.blocks.single['block_data'] as Map,
                  ),
                  primaryColor: Colors.teal,
                  accentColor: Colors.tealAccent,
                  onNavigate: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  // ------------------------------------------------------------------ fixtures

  Map<String, dynamic> pricingData() => <String, dynamic>{
        'title': 'Planes de Servicio',
        'subtitle': 'Elige el plan que mejor se ajuste',
        'plans': <Map<String, dynamic>>[
          {
            'id': 'plan-a',
            'name': 'Full Service',
            'price': '59.990',
            'features': <String>['Ajuste integral'],
            'ctaText': 'Reservar',
            'ctaLink': '/contacto',
            'highlighted': true,
          },
          {
            'id': 'plan-b',
            'name': 'Mantención Básica',
            'price': '29.990',
            'features': <String>['Revisión de frenos'],
            'ctaText': 'Reservar',
            'ctaLink': '/productos',
          },
        ],
      };

  Map<String, dynamic> contactData() => <String, dynamic>{
        'title': 'Contáctanos',
        'subtitle': 'Resolvemos dudas en menos de 24h',
        'showForm': true,
        'showMap': false,
        'phone': '+56 9 1234 5678',
        'email': 'contacto@vinabike.cl',
        'address': 'Viña del Mar, Chile',
      };

  Map<String, dynamic> footerData() => <String, dynamic>{
        'companyName': 'Vinabike',
        'copyright': '© 2026 Vinabike',
        'columns': <Map<String, dynamic>>[
          {
            'title': 'Contacto',
            'items': <Map<String, dynamic>>[
              {'label': '+56 9 1234 5678', 'link': 'tel:+56912345678'},
            ],
          },
        ],
      };

  // ------------------------------------- 1 · el inspector no ofrece capacidad

  group('1 · el inspector no ofrece ninguna personalización', () {
    // Etiqueta visible de la sección abierta por defecto, y encabezado de la
    // sección plegada: juntas prueban que el editor de siempre sigue entero.
    for (final (type, data, visibleLabel, collapsedSection)
        in <(String, Map<String, dynamic>, String, String)>[
      ('pricing', pricingData(), 'Planes', 'Contenido'),
      ('contact', contactData(), 'Subtítulo', 'Opciones'),
      ('footer', footerData(), 'Nombre de la empresa', 'Columnas de enlaces'),
    ]) {
      for (final (width, viewport) in const <(double, DevicePreviewMode)>[
        (390, DevicePreviewMode.mobile),
        (834, DevicePreviewMode.tablet),
        (1440, DevicePreviewMode.desktop),
      ]) {
        testWidgets('$type a $width: sin personalizar, sin restablecer',
            (tester) async {
          final provider = await pumpInspector(
            tester,
            type: type,
            data: data,
            width: width,
            viewport: viewport,
          );
          final before = dataOf(provider);

          expect(
            find.byKey(ResponsiveFieldShell.customizeActionKey),
            findsNothing,
            reason: '$type @ $width',
          );
          expect(find.byKey(ResponsiveFieldShell.resetActionKey), findsNothing);
          for (final element in shellFinder().evaluate()) {
            final shell = element.widget as ResponsiveFieldShell;
            expect(
              shell.state.canCustomize || shell.state.canReset,
              isFalse,
              reason: '$type.${shell.state.schema.key} @ $width',
            );
          }
          // El editor de siempre sigue ahí y montarlo no escribe.
          expect(find.text(visibleLabel), findsWidgets, reason: type);
          expect(
            find.text(collapsedSection),
            findsWidgets,
            reason: '$type: el resto del inspector sigue alcanzable',
          );
          expect(dataOf(provider), before);
          expect(provider.hasUnsavedChanges, isFalse);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('Pricing en oscuro tampoco ofrece nada y no desborda',
        (tester) async {
      for (final width in const <double>[390, 834, 1440]) {
        await pumpInspector(
          tester,
          type: 'pricing',
          data: pricingData(),
          width: width,
          viewport: width < 600
              ? DevicePreviewMode.mobile
              : width < 900
                  ? DevicePreviewMode.tablet
                  : DevicePreviewMode.desktop,
          brightness: Brightness.dark,
        );
        expect(
          find.byKey(ResponsiveFieldShell.customizeActionKey),
          findsNothing,
          reason: '@ $width',
        );
        expect(tester.takeException(), isNull, reason: '@ $width');
      }
    });
  });

  // ------------------------------------------------ 2 · el consumidor real

  group('2 · la tienda compone por ancho, no por dato', () {
    Map<String, dynamic> projected(
      WebsiteBlockType type,
      Map<String, dynamic> document,
      WebsiteViewport viewport,
    ) =>
        WebsiteResponsiveBlockProjection.project(
          type: type,
          data: document,
          viewport: viewport,
        );

    Widget storefront(
      Widget child, {
      Brightness brightness = Brightness.light,
    }) =>
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.pacific,
            brightness: brightness,
          ),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        );

    testWidgets(
        'Pricing: la tarjeta se ensancha sola y el plan destacado es '
        'el mismo', (tester) async {
      final widths = <double, double>{};
      for (final (viewport, width) in const <(WebsiteViewport, double)>[
        (WebsiteViewport.desktop, 1440),
        (WebsiteViewport.tablet, 834),
        (WebsiteViewport.mobile, 390),
      ]) {
        for (final brightness in Brightness.values) {
          useViewport(tester, width: width);
          await tester.pumpWidget(
            storefront(
              WebsitePricingBlockContent(
                data: projected(
                  WebsiteBlockType.pricing,
                  pricingData(),
                  viewport,
                ),
                primaryColor: Colors.teal,
                accentColor: Colors.tealAccent,
              ),
              brightness: brightness,
            ),
          );
          await settle(tester);

          // El contenido de negocio es el mismo en los tres.
          expect(find.text('Full Service'), findsOneWidget);
          expect(find.textContaining('59.990'), findsWidgets);
          expect(find.text('Mantención Básica'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$viewport');

          if (brightness == Brightness.light) {
            widths[width] = tester
                .getSize(find.byKey(WebsitePricingBlockContent.planKey(0)))
                .width;
          }
        }
      }

      // Auto-layout demostrado: una columna ancha en el teléfono, tarjetas
      // acotadas en escritorio, sin ninguna propiedad guardada.
      expect(widths[390]!, greaterThan(widths[1440]!));
      expect(widths[1440], closeTo(320, 0.5));
    });

    testWidgets('Contact: tres composiciones por ancho con los mismos datos',
        (tester) async {
      for (final (viewport, width) in const <(WebsiteViewport, double)>[
        (WebsiteViewport.desktop, 1440),
        (WebsiteViewport.tablet, 834),
        (WebsiteViewport.mobile, 390),
      ]) {
        useViewport(tester, width: width);
        await tester.pumpWidget(
          storefront(
            WebsiteContactBlockContent(
              data: projected(
                WebsiteBlockType.contact,
                contactData(),
                viewport,
              ),
              primaryColor: Colors.teal,
              accentColor: Colors.tealAccent,
            ),
          ),
        );
        await settle(tester);

        expect(find.text('Contáctanos'), findsOneWidget, reason: '$viewport');
        expect(find.textContaining('+56 9 1234 5678'), findsWidgets);
        expect(tester.takeException(), isNull, reason: '$viewport');
      }
    });

    testWidgets(
        'Footer: el bloque de página sólo reserva alto en los tres '
        'modos', (tester) async {
      for (final previewMode in const <bool>[true, false]) {
        for (final (viewport, width) in const <(WebsiteViewport, double)>[
          (WebsiteViewport.desktop, 1440),
          (WebsiteViewport.mobile, 390),
        ]) {
          useViewport(tester, width: width);
          await tester.pumpWidget(
            storefront(
              Builder(
                builder: (context) => WebsiteBlockRenderer.build(
                  context: context,
                  blockType: 'footer',
                  data: projected(
                    WebsiteBlockType.footer,
                    footerData(),
                    viewport,
                  ),
                  primaryColor: Colors.teal,
                  accentColor: Colors.tealAccent,
                  previewMode: previewMode,
                ),
              ),
            ),
          );
          await settle(tester);

          // Ni marca, ni copyright, ni columnas: el pie real es del sitio.
          expect(find.text('Vinabike'), findsNothing, reason: '$viewport');
          expect(find.text('© 2026 Vinabike'), findsNothing);
          expect(find.text('Contacto'), findsNothing);
          expect(find.text('+56 9 1234 5678'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
    });

    testWidgets('Footer: Edit dibuja exactamente el mismo espaciador',
        (tester) async {
      final provider = providerFor('footer', footerData());
      await pumpEditableBlock(
        tester,
        provider: provider,
        type: 'footer',
        width: 390,
      );

      expect(find.text('Vinabike'), findsNothing);
      expect(find.text('+56 9 1234 5678'), findsNothing);
      // Y montar el bloque en Edit no crea dato ni ensucia el borrador.
      expect(provider.hasUnsavedChanges, isFalse);
      expect(dataOf(provider).containsKey('responsive'), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  // ---------------------------------------- 3 · el inline conserva su dueño

  group('3 · la edición inline escribe en su item, por el owner canónico', () {
    testWidgets('el nombre de un plan escribe en ese plan y no en la raíz',
        (tester) async {
      final provider = providerFor('pricing', pricingData());
      await pumpEditableBlock(
        tester,
        provider: provider,
        type: 'pricing',
        width: 390,
      );

      tester
          .widget<InlineEditableTextV2>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is InlineEditableTextV2 &&
                  widget.text == 'Full Service',
            ),
          )
          .onTextChanged!('Full Service Pro');
      await settle(tester);

      final plans = plansOf(provider);
      expect(plans[0]['name'], 'Full Service Pro');
      expect(plans[0]['id'], 'plan-a', reason: 'la identidad no se toca');
      expect(plans[1]['name'], 'Mantención Básica', reason: 'el hermano');
      expect(dataOf(provider)['title'], 'Planes de Servicio');
      expect(
        plans[0].containsKey('responsive'),
        isFalse,
        reason: 'sin personalizar, el copy es común',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('la acción de un plan conserva label, destino y alias',
        (tester) async {
      final provider = providerFor('pricing', pricingData());
      await pumpEditableBlock(
        tester,
        provider: provider,
        type: 'pricing',
        width: 1440,
      );

      final editors = tester.widgetList<WebsiteInlineActionEditor>(
        find.byType(WebsiteInlineActionEditor),
      );
      expect(editors, isNotEmpty);
      editors.first.onChanged(
        const WebsiteActionValue(
          label: 'Agendar',
          href: '/agenda',
          variant: WebsiteActionVariant.filled,
        ),
      );
      await settle(tester);

      final plans = plansOf(provider);
      expect(plans[0]['ctaText'], 'Agendar');
      expect(plans[0]['ctaLink'], '/agenda');
      // Los alias que el producto todavía lee viajan con el valor común.
      expect(plans[0]['buttonText'], 'Agendar');
      expect(plans[0]['buttonLink'], '/agenda');
      expect(plans[0]['actionVariant'], 'filled');
      expect(plans[0].containsKey('responsive'), isFalse);
      // El segundo plan no se movió.
      expect(plans[1]['ctaLink'], '/productos');
      expect(dataOf(provider).containsKey('ctaLink'), isFalse);
      expect(tester.takeException(), isNull);
    });
  });
}
