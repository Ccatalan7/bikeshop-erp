import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_field_state.dart';
import 'package:vinabike_erp/modules/website/widgets/responsive_field_shell.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_segmented.dart';
import 'package:vinabike_erp/shared/widgets/vb_status_badge.dart';

/// `ResponsiveFieldShell` contract.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 (frames 10b, 10c, 10k) and t11.
/// The rule under test is that the shell is the visible authority per field:
/// the global selector only supplies a default and can never hide which scope
/// the next change writes.
void main() {
  const responsiveSchema = WebsiteBlockFieldSchema(
    key: 'blockHeight',
    label: 'Altura del bloque',
    type: WebsiteBlockFieldType.number,
    helpText: 'Alto visible de la sección.',
    responsivePolicy: WebsiteResponsivePropertyPolicy.perViewportGeometry,
  );

  const sharedSchema = WebsiteBlockFieldSchema(
    key: 'ctaHref',
    label: 'Destino del botón',
    type: WebsiteBlockFieldType.link,
    responsivePolicy: WebsiteResponsivePropertyPolicy.sharedOnly,
  );

  WebsiteAuthoringContext contextFor(
    WebsiteViewport viewport, {
    WebsiteAuthoringHostClass host = WebsiteAuthoringHostClass.desktop,
    WebsiteWriteScope scope = WebsiteWriteScope.viewport,
  }) {
    return WebsiteAuthoringContext(
      hostClass: host,
      previewViewport: viewport,
      writeScope: viewport == WebsiteViewport.desktop
          ? WebsiteWriteScope.shared
          : scope,
    );
  }

  WebsiteResolvedResponsiveValue<double> resolved({
    required WebsiteViewport viewport,
    bool isOverride = false,
    bool isLegacyOverride = false,
  }) {
    return WebsiteResolvedResponsiveValue<double>(
      shared: 420,
      value: isOverride ? 260 : 420,
      viewport: viewport,
      isOverride: isOverride,
      isLegacyOverride: isLegacyOverride,
    );
  }

  WebsiteResponsiveFieldState<double> stateFor({
    required WebsiteViewport viewport,
    WebsiteBlockFieldSchema schema = responsiveSchema,
    bool isOverride = false,
    bool isLegacyOverride = false,
    String? unavailableReason,
  }) {
    return WebsiteResponsiveFieldState<double>.resolve(
      schema: schema,
      context: contextFor(viewport),
      resolved: resolved(
        viewport: viewport,
        isOverride: isOverride,
        isLegacyOverride: isLegacyOverride,
      ),
      unavailableReason: unavailableReason,
    );
  }

  Widget host({
    required WebsiteResponsiveFieldState<double> state,
    VoidCallback? onCustomize,
    VoidCallback? onReset,
    Size size = const Size(1440, 900),
    bool disableAnimations = false,
    double? width,
  }) {
    return MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.pacific,
        brightness: Brightness.light,
      ),
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: disableAnimations),
        child: Scaffold(
          body: SizedBox(
            width: width ?? 420,
            child: ResponsiveFieldShell<double>(
              state: state,
              onCustomize: onCustomize,
              onReset: onReset,
              child: const SizedBox(height: 34, child: Text('control')),
            ),
          ),
        ),
      ),
    );
  }

  group('los seis estados', () {
    testWidgets('Común en escritorio: sin acciones, escribe el común',
        (tester) async {
      await tester.pumpWidget(
        host(
          state: stateFor(viewport: WebsiteViewport.desktop),
          onCustomize: () {},
          onReset: () {},
        ),
      );

      expect(find.text('Común'), findsOneWidget);
      expect(find.byKey(ResponsiveFieldShell.customizeActionKey), findsNothing);
      expect(find.byKey(ResponsiveFieldShell.resetActionKey), findsNothing);
      expect(
        find.text('Los cambios se guardan en el valor común.'),
        findsOneWidget,
      );
    });

    testWidgets('Heredado en móvil: ofrece personalizar y anuncia el scope',
        (tester) async {
      await tester.pumpWidget(
        host(
          state: stateFor(viewport: WebsiteViewport.mobile),
          onCustomize: () {},
          onReset: () {},
        ),
      );

      expect(find.text('Heredado'), findsOneWidget);
      expect(find.text('Personalizar para Móvil'), findsOneWidget);
      expect(find.byKey(ResponsiveFieldShell.resetActionKey), findsNothing);
      expect(
        find.text('Los cambios se guardan sólo para Móvil.'),
        findsOneWidget,
      );
    });

    testWidgets('Personalizado: ofrece restablecer', (tester) async {
      await tester.pumpWidget(
        host(
          state: stateFor(
            viewport: WebsiteViewport.mobile,
            isOverride: true,
          ),
          onCustomize: () {},
          onReset: () {},
        ),
      );

      expect(find.text('Personalizado para Móvil'), findsOneWidget);
      expect(find.text('Restablecer a Común'), findsOneWidget);
      expect(find.byKey(ResponsiveFieldShell.customizeActionKey), findsNothing);
    });

    testWidgets('Siempre común: nunca ofrece override y lo dice',
        (tester) async {
      await tester.pumpWidget(
        host(
          state: stateFor(
            viewport: WebsiteViewport.mobile,
            schema: sharedSchema,
          ),
          onCustomize: () {},
          onReset: () {},
        ),
      );

      expect(find.text('Siempre común'), findsOneWidget);
      expect(find.byKey(ResponsiveFieldShell.customizeActionKey), findsNothing);
      expect(find.byKey(ResponsiveFieldShell.resetActionKey), findsNothing);
      expect(find.text('Esta propiedad no varía por dispositivo.'),
          findsOneWidget);
      // Aunque el viewport sea móvil, el destino de escritura es el común.
      expect(
        find.text('Los cambios se guardan en el valor común.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'Configuración móvil anterior: explica y no escribe en silencio',
        (tester) async {
      await tester.pumpWidget(
        host(
          state: stateFor(
            viewport: WebsiteViewport.mobile,
            isOverride: true,
            isLegacyOverride: true,
          ),
          onCustomize: () {},
          onReset: () {},
        ),
      );

      expect(find.text('Configuración móvil anterior'), findsOneWidget);
      expect(
        find.textContaining('viene de una configuración móvil anterior'),
        findsOneWidget,
      );
      // La salida es explícita: restablecer, nunca una escritura implícita.
      expect(find.text('Restablecer a Común'), findsOneWidget);
      expect(find.byKey(ResponsiveFieldShell.customizeActionKey), findsNothing);
    });

    testWidgets('No disponible: da la razón y no ofrece escritura',
        (tester) async {
      await tester.pumpWidget(
        host(
          state: stateFor(
            viewport: WebsiteViewport.mobile,
            unavailableReason: 'Este bloque no tiene imagen todavía.',
          ),
          onCustomize: () {},
          onReset: () {},
        ),
      );

      expect(find.text('No disponible'), findsOneWidget);
      expect(find.text('Este bloque no tiene imagen todavía.'), findsOneWidget);
      expect(find.byKey(ResponsiveFieldShell.customizeActionKey), findsNothing);
      expect(find.byKey(ResponsiveFieldShell.resetActionKey), findsNothing);
      expect(find.text('Este campo no se puede editar aquí.'), findsOneWidget);
    });
  });

  group('callbacks exactos', () {
    testWidgets('personalizar llama sólo onCustomize', (tester) async {
      var customize = 0;
      var reset = 0;
      await tester.pumpWidget(
        host(
          state: stateFor(viewport: WebsiteViewport.mobile),
          onCustomize: () => customize++,
          onReset: () => reset++,
        ),
      );

      await tester.tap(find.byKey(ResponsiveFieldShell.customizeActionKey));
      await tester.pumpAndSettle();
      expect(customize, 1);
      expect(reset, 0);
    });

    testWidgets('restablecer llama sólo onReset', (tester) async {
      var customize = 0;
      var reset = 0;
      await tester.pumpWidget(
        host(
          state: stateFor(
            viewport: WebsiteViewport.mobile,
            isOverride: true,
          ),
          onCustomize: () => customize++,
          onReset: () => reset++,
        ),
      );

      await tester.tap(find.byKey(ResponsiveFieldShell.resetActionKey));
      await tester.pumpAndSettle();
      expect(reset, 1);
      expect(customize, 0);
    });

    testWidgets('sin callback no se pinta una acción muerta', (tester) async {
      await tester.pumpWidget(
        host(state: stateFor(viewport: WebsiteViewport.mobile)),
      );
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('escritorio, tablet y móvil', () {
    testWidgets('Común y Móvil nunca se ven ni se anuncian igual',
        (tester) async {
      await tester.pumpWidget(
        host(state: stateFor(viewport: WebsiteViewport.desktop)),
      );
      final desktopBadge = tester.widget<VbStatusBadge>(
        find.byType(VbStatusBadge),
      );
      final desktopScope = tester
          .widget<Text>(find.byKey(ResponsiveFieldShell.scopeNoticeKey))
          .data;

      await tester.pumpWidget(
        host(state: stateFor(viewport: WebsiteViewport.mobile)),
      );
      await tester.pumpAndSettle();
      final mobileBadge = tester.widget<VbStatusBadge>(
        find.byType(VbStatusBadge),
      );
      final mobileScope = tester
          .widget<Text>(find.byKey(ResponsiveFieldShell.scopeNoticeKey))
          .data;

      expect(desktopBadge.label, isNot(mobileBadge.label));
      expect(desktopScope, isNot(mobileScope));
    });

    testWidgets('tablet anuncia su propio scope y hereda del común',
        (tester) async {
      await tester.pumpWidget(
        host(
          state: stateFor(viewport: WebsiteViewport.tablet),
          onCustomize: () {},
        ),
      );
      expect(find.text('Heredado'), findsOneWidget);
      expect(find.text('Personalizar para Tablet'), findsOneWidget);
      expect(
        find.text('Los cambios se guardan sólo para Tablet.'),
        findsOneWidget,
      );
    });
  });

  group('composición compacta', () {
    testWidgets('no desborda a 320 px con el estado más largo', (tester) async {
      await tester.pumpWidget(
        host(
          state: stateFor(
            viewport: WebsiteViewport.mobile,
            isOverride: true,
            isLegacyOverride: true,
          ),
          onReset: () {},
          size: const Size(320, 720),
          width: 320,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Configuración móvil anterior'), findsOneWidget);
      expect(find.text('Restablecer a Común'), findsOneWidget);
    });

    testWidgets('bajo 900 la acción alcanza el target táctil de 48',
        (tester) async {
      await tester.pumpWidget(
        host(
          state: stateFor(viewport: WebsiteViewport.mobile),
          onCustomize: () {},
          size: const Size(390, 844),
          width: 390,
        ),
      );
      final size = tester.getSize(
        find.byKey(ResponsiveFieldShell.customizeActionKey),
      );
      expect(size.height, greaterThanOrEqualTo(48));
    });

    testWidgets('en escritorio conserva la densidad compacta de Design',
        (tester) async {
      await tester.pumpWidget(
        host(
          state: stateFor(viewport: WebsiteViewport.mobile),
          onCustomize: () {},
        ),
      );
      final size = tester.getSize(
        find.byKey(ResponsiveFieldShell.customizeActionKey),
      );
      expect(size.height, VbDensity.compact.controlHeight);
    });
  });

  group('estados que no permiten escritura silenciosa', () {
    /// A real interactive control, not a placeholder: the contract is about
    /// what the user can actually operate.
    Widget interactiveHost({
      required WebsiteResponsiveFieldState<double> state,
      required VoidCallback onChildPressed,
      required FocusNode childFocus,
      VoidCallback? onReset,
    }) {
      return MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: ResponsiveFieldShell<double>(
              state: state,
              onReset: onReset,
              child: ElevatedButton(
                focusNode: childFocus,
                onPressed: onChildPressed,
                child: const Text('editar valor'),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('No disponible: ni puntero ni teclado alcanzan el control',
        (tester) async {
      var childTaps = 0;
      final childFocus = FocusNode();
      addTearDown(childFocus.dispose);

      await tester.pumpWidget(
        interactiveHost(
          state: stateFor(
            viewport: WebsiteViewport.mobile,
            unavailableReason: 'Este bloque no tiene imagen todavía.',
          ),
          onChildPressed: () => childTaps++,
          childFocus: childFocus,
        ),
      );

      // El valor sigue visible: es la evidencia para decidir.
      expect(find.text('editar valor'), findsOneWidget);

      await tester.tap(find.text('editar valor'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(childTaps, 0);

      childFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(childFocus.hasFocus, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(childTaps, 0);

      // Y no ofrece ninguna acción propia.
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('Configuración móvil anterior: sólo Restablecer opera',
        (tester) async {
      var childTaps = 0;
      var resets = 0;
      final childFocus = FocusNode();
      addTearDown(childFocus.dispose);

      await tester.pumpWidget(
        interactiveHost(
          state: stateFor(
            viewport: WebsiteViewport.mobile,
            isOverride: true,
            isLegacyOverride: true,
          ),
          onChildPressed: () => childTaps++,
          childFocus: childFocus,
          onReset: () => resets++,
        ),
      );

      expect(find.text('editar valor'), findsOneWidget);

      await tester.tap(find.text('editar valor'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(childTaps, 0);

      childFocus.requestFocus();
      await tester.pumpAndSettle();
      expect(childFocus.hasFocus, isFalse);

      await tester.tap(find.byKey(ResponsiveFieldShell.resetActionKey));
      await tester.pumpAndSettle();
      expect(resets, 1);
      expect(childTaps, 0);
    });

    testWidgets('el control bloqueado no anuncia una acción que no hace nada',
        (tester) async {
      final handle = tester.ensureSemantics();
      final childFocus = FocusNode();
      addTearDown(childFocus.dispose);

      await tester.pumpWidget(
        interactiveHost(
          state: stateFor(
            viewport: WebsiteViewport.mobile,
            unavailableReason: 'Este bloque no tiene imagen todavía.',
          ),
          onChildPressed: () {},
          childFocus: childFocus,
        ),
      );

      final node = tester.getSemantics(
        find.byType(ResponsiveFieldShell<double>),
      );
      expect(node.label, contains('No disponible'));
      expect(node.label, isNot(contains('editar valor')));
      handle.dispose();
    });

    testWidgets('Común, Heredado y Personalizado dejan el control operable',
        (tester) async {
      for (final state in <WebsiteResponsiveFieldState<double>>[
        stateFor(viewport: WebsiteViewport.desktop),
        stateFor(viewport: WebsiteViewport.mobile),
        stateFor(viewport: WebsiteViewport.mobile, isOverride: true),
        stateFor(viewport: WebsiteViewport.mobile, schema: sharedSchema),
      ]) {
        var childTaps = 0;
        final childFocus = FocusNode();

        await tester.pumpWidget(
          interactiveHost(
            state: state,
            onChildPressed: () => childTaps++,
            childFocus: childFocus,
            onReset: () {},
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('editar valor'));
        await tester.pumpAndSettle();
        expect(childTaps, 1, reason: '${state.status.name} debe ser operable');

        childFocus.requestFocus();
        await tester.pumpAndSettle();
        expect(
          childFocus.hasFocus,
          isTrue,
          reason: '${state.status.name} debe aceptar foco',
        );
        childFocus.dispose();
      }
    });
  });

  group('semántica y motion', () {
    testWidgets('la semántica contiene label, estado y scope', (tester) async {
      final handle = tester.ensureSemantics();
      final state = stateFor(
        viewport: WebsiteViewport.mobile,
        isOverride: true,
      );
      await tester.pumpWidget(host(state: state, onReset: () {}));

      final node =
          tester.getSemantics(find.byType(ResponsiveFieldShell<double>));
      expect(node.label, contains('Altura del bloque'));
      expect(node.label, contains('Personalizado para Móvil'));
      expect(node.label, contains('la vista móvil'));
      // El resumen del shell encabeza el nodo; la semántica propia del control
      // hijo se suma después y debe seguir anunciándose.
      expect(node.label, startsWith(state.semanticSummary));
      expect(node.label, contains('control'));
      handle.dispose();
    });

    testWidgets('la semántica del estado no disponible lleva su razón',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          state: stateFor(
            viewport: WebsiteViewport.mobile,
            unavailableReason: 'Este bloque no tiene imagen todavía.',
          ),
        ),
      );
      final node =
          tester.getSemantics(find.byType(ResponsiveFieldShell<double>));
      expect(node.label, contains('No disponible'));
      expect(node.label, contains('Este bloque no tiene imagen todavía.'));
      handle.dispose();
    });

    testWidgets('el motion usa 120 ms y la curva publicada', (tester) async {
      await tester.pumpWidget(
        host(state: stateFor(viewport: WebsiteViewport.mobile)),
      );
      final switcher = tester.widget<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      );
      expect(switcher.duration, VbSegmentedMetrics.motionFast);
      expect(switcher.duration, const Duration(milliseconds: 120));
      expect(switcher.switchInCurve, VbSegmentedMetrics.motionCurve);
    });

    testWidgets('disableAnimations baja a la duración reducida',
        (tester) async {
      await tester.pumpWidget(
        host(
          state: stateFor(viewport: WebsiteViewport.mobile),
          disableAnimations: true,
        ),
      );
      final switcher = tester.widget<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      );
      expect(switcher.duration, VbSegmentedMetrics.motionReduced);
      expect(switcher.duration, const Duration(milliseconds: 80));
    });
  });
}
