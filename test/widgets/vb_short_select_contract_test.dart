import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/models/hr_models.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/utils/responsive_breakpoints.dart';
import 'package:vinabike_erp/shared/widgets/vb_anchored_popover.dart';
import 'package:vinabike_erp/shared/widgets/vb_short_select.dart';

/// **S-05 · `VbShortSelect`** — contrato del select corto compartido.
///
/// Cada aserto está atado a una frase del archivo de Design leído con
/// `DesignSync`, no a un parecido. Los tres que más importan son los que la
/// guía escribe con esas palabras: *«Jamás un modal centrado para elegir de una
/// lista»*, *«Escape cierra sin cambiar»* y *«en touch la lista es un bottom
/// sheet, no un popover de 200 px»*.
const List<VbShortSelectOption<String?>> _tres = <VbShortSelectOption<String?>>[
  VbShortSelectOption<String?>(value: null, label: 'Sin especificar'),
  VbShortSelectOption<String?>(value: 'a', label: 'Abierta'),
  VbShortSelectOption<String?>(value: 'b', label: 'En cola'),
  VbShortSelectOption<String?>(value: 'c', label: 'Anulada', enabled: false),
];

Future<List<String?>> _pump(
  WidgetTester tester, {
  String? value = 'a',
  Size size = const Size(1360, 800),
  bool enabled = true,
  String? label,
  String? placeholder,
  List<VbShortSelectOption<String?>> options = _tres,
  Brightness brightness = Brightness.light,
}) async {
  final picked = <String?>[];
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 236,
            child: VbShortSelect<String?>(
              value: value,
              options: options,
              label: label,
              placeholder: placeholder,
              sheetTitle: 'Estado de la semana',
              semanticLabel: 'Estado de la semana',
              onChanged: enabled ? picked.add : null,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return picked;
}

/// La caja **visual** de 34, que no siempre es el primer `Container`: bajo 900
/// px el objetivo táctil de 48 la envuelve, y ése no lleva decoración.
BoxDecoration _fieldDecoration(WidgetTester tester) {
  final containers = tester.widgetList<Container>(
    find.descendant(
      of: find.byType(VbShortSelect<String?>),
      matching: find.byType(Container),
    ),
  );
  return containers
      .firstWhere((container) => container.decoration is BoxDecoration)
      .decoration! as BoxDecoration;
}

VinabikeThemeRoles _roles(WidgetTester tester) => VinabikeThemeRoles.of(
      tester.element(find.byType(VbShortSelect<String?>)),
    );

ColorScheme _scheme(WidgetTester tester) => Theme.of(
      tester.element(find.byType(VbShortSelect<String?>)),
    ).colorScheme;

/// Alto real de la caja que envuelve un texto — la opción o la fila del sheet.
double _boxHeightAround(WidgetTester tester, String text) {
  return tester
      .getSize(
        find
            .ancestor(of: find.text(text), matching: find.byType(Container))
            .first,
      )
      .height;
}

void main() {
  group('S-05 · el campo cerrado', () {
    testWidgets('mide 34 de alto con radio 8, el valor del archivo',
        (tester) async {
      await _pump(tester);
      expect(tester.getSize(find.byType(VbShortSelect<String?>)).height, 34);
      final decoration = _fieldDecoration(tester);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(8),
        reason: '`radius.field` del kit: 8, no el 4 de Material ni el 12 de '
            'nadie',
      );
    });

    testWidgets('el borde es `borderStrong`, no la divisoria', (tester) async {
      await _pump(tester);
      final border = _fieldDecoration(tester).border! as Border;
      expect(border.top.color, _scheme(tester).outline);
      expect(
        border.top.color,
        isNot(_scheme(tester).outlineVariant),
        reason: '#CDD5DE y #E2E7ED son dos roles distintos: usar la divisoria '
            'deja el campo sin contorno legible',
      );
    });

    testWidgets('sin sombra cerrado; el anillo de foco aparece SÓLO al abrir',
        (tester) async {
      await _pump(tester);
      expect(_fieldDecoration(tester).boxShadow, isNull);

      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();

      final shadow = _fieldDecoration(tester).boxShadow!.single;
      // «0 0 0 3px rgba(22,104,189,.12)»: sin blur, sin desplazamiento.
      expect(shadow.spreadRadius, 3);
      expect(shadow.blurRadius, 0);
      expect(shadow.offset, Offset.zero);
      expect(shadow.color.a, closeTo(0.12, 0.001));
      expect(_fieldDecoration(tester).border, isNotNull);
    });

    testWidgets('un valor fuera de la lista muestra el placeholder atenuado',
        (tester) async {
      await _pump(tester, value: 'zzz', placeholder: 'Elegir estado');
      expect(find.text('Elegir estado'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Elegir estado'));
      expect(text.style!.color, _scheme(tester).onSurfaceVariant);
    });

    testWidgets('deshabilitado se hunde y no abre nada', (tester) async {
      await _pump(tester, enabled: false);
      expect(
          _fieldDecoration(tester).color, _scheme(tester).surfaceContainerLow);

      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();
      expect(find.byType(VbPopoverSurface), findsNothing);
      expect(find.text('En cola'), findsNothing);
    });

    testWidgets('el rótulo sale a 500/11 con 5 px de aire', (tester) async {
      await _pump(tester, label: 'Estado de la semana');
      final text = tester.widget<Text>(find.text('Estado de la semana'));
      expect(text.style!.fontSize, 11);
      expect(text.style!.fontWeight, FontWeight.w500);
      expect(text.style!.color, _scheme(tester).onSurfaceVariant);
      final gap = tester.getTopLeft(find.byType(InkWell)).dy -
          tester.getBottomLeft(find.text('Estado de la semana')).dy;
      expect(gap, 5);
    });
  });

  group('S-05 · escritorio: popover anclado, jamás un modal centrado', () {
    testWidgets('abre pegado al campo y sin oscurecer la app', (tester) async {
      await _pump(tester);
      final anchor = tester.getRect(find.byType(InkWell).first);
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();

      expect(find.byType(VbPopoverSurface), findsOneWidget);
      final popover = tester.getRect(find.byType(VbPopoverSurface));
      expect(
        popover.top - anchor.bottom,
        4,
        reason: '«4 px de gap» está escrito con esas palabras en el archivo',
      );
      // «mismo ancho o más» — y ese «más» es el de la opción más larga, **no
      // el de la pantalla**. La app viva lo dibujó a 1.672 px colgando de un
      // campo de 206 mientras este aserto decía sólo `>= ancho del campo`, que
      // un menú del ancho del viewport cumple de sobra.
      expect(
        popover.width,
        anchor.width,
        reason: 'con etiquetas más cortas que el campo, «mismo ancho o más» es '
            'exactamente el ancho del campo. La app viva lo dibujó a 1.672 px '
            'colgando de uno de 206 mientras el aserto sólo decía `>=`, que un '
            'menú del ancho del viewport cumple de sobra',
      );

      final barriers = tester.widgetList<ModalBarrier>(
        find.byType(ModalBarrier),
      );
      expect(
        barriers.every((barrier) => barrier.color == null),
        isTrue,
        reason: 'oscurecer la app es la firma del modal centrado, y la guía lo '
            'elimina',
      );
    });

    testWidgets('cada opción mide 30 y la elegida lleva su check',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();

      expect(_boxHeightAround(tester, 'En cola'), 30);
      expect(find.text('✓'), findsOneWidget);
      final check = tester.getCenter(find.text('✓'));
      final chosen = tester.getRect(find.text('Abierta').last);
      expect(check.dy, closeTo(chosen.center.dy, 1));
    });

    testWidgets('la opción elegida se tiñe con el contenedor de selección',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();

      final container = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Abierta').last,
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, _roles(tester).selectionContainer);
      expect(decoration.borderRadius, BorderRadius.circular(6));
    });

    testWidgets('elegir devuelve el valor, incluso cuando el valor es null',
        (tester) async {
      final picked = await _pump(tester);
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sin especificar'));
      await tester.pumpAndSettle();

      expect(picked, <String?>[null]);
      expect(
        find.byType(VbPopoverSurface),
        findsNothing,
        reason: 'elegir cierra el popover',
      );
    });

    testWidgets('Escape cierra SIN cambiar el valor', (tester) async {
      final picked = await _pump(tester);
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();
      expect(find.byType(VbPopoverSurface), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(VbPopoverSurface), findsNothing);
      expect(
        picked,
        isEmpty,
        reason: '«Escape cierra sin cambiar» — si notificara, deshacer sería '
            'imposible con el teclado',
      );
    });

    testWidgets('↓ recorre y Enter elige, sin tocar el mouse', (tester) async {
      final picked = await _pump(tester);
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();

      // Parte en `Abierta`; una flecha abajo cae en `En cola`.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(picked, <String?>['b']);
    });

    testWidgets('↓ salta la opción deshabilitada en vez de elegirla',
        (tester) async {
      final picked = await _pump(tester, value: 'b');
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();

      // Desde `En cola`, la siguiente dibujada es `Anulada`, deshabilitada:
      // el recorrido tiene que pasarla de largo y volver al principio.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(picked, <String?>[null]);
    });

    testWidgets('una opción deshabilitada tampoco se puede pulsar',
        (tester) async {
      final picked = await _pump(tester);
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anulada'));
      await tester.pumpAndSettle();

      expect(picked, isEmpty);
      expect(find.byType(VbPopoverSurface), findsOneWidget);
    });
  });

  group('O-05 · la anatomía del bottom sheet táctil', () {
    testWidgets('a 430 no aparece el popover: aparece la hoja', (tester) async {
      await _pump(tester, size: const Size(430, 900));
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();

      expect(
        find.byType(VbPopoverSurface),
        findsNothing,
        reason: '«Nunca aparece en desktop pointer: ahí es popover o side '
            'sheet» — y al revés, en táctil no es un popover de 200 px',
      );
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Estado de la semana'), findsOneWidget);
    });

    testWidgets('filas de 48 y radio 14 arriba, la anatomía de O-05',
        (tester) async {
      await _pump(tester, size: const Size(430, 900));
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();

      expect(_boxHeightAround(tester, 'En cola'), 48);

      // El `Material` de la hoja es el que envuelve su título: el que crea
      // `showModalBottomSheet` va por fuera y queda transparente a propósito,
      // para que el radio y la sombra de O-05 los pinte este archivo.
      final material = tester.widget<Material>(
        find
            .ancestor(
              of: find.text('Estado de la semana'),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(
        material.borderRadius,
        const BorderRadius.vertical(top: Radius.circular(14)),
      );
    });

    testWidgets('el título es 14 Poppins y encabeza para el lector',
        (tester) async {
      await _pump(tester, size: const Size(430, 900));
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();

      final title = tester.widget<Text>(find.text('Estado de la semana'));
      expect(title.style!.fontSize, 14);
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(
        tester.getSemantics(find.text('Estado de la semana')).hasFlag(
              SemanticsFlag.isHeader,
            ),
        isTrue,
      );
    });

    testWidgets('la hoja no pasa del 60% del alto', (tester) async {
      await _pump(tester, size: const Size(430, 900));
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(BottomSheet)).height,
        lessThanOrEqualTo(900 * 0.6),
      );
    });

    testWidgets('tocar una fila devuelve el valor y cierra', (tester) async {
      final picked = await _pump(tester, size: const Size(430, 900));
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('En cola'));
      await tester.pumpAndSettle();

      expect(picked, <String?>['b']);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('F-06 · dónde empieza «táctil»: 900, no 600', () {
    // «Bajo 900 px de ancho lógico la densidad se fuerza a touch: 48 px de
    // target sin importar la preferencia.» Los tres anchos que rodean el
    // umbral, uno por uno: 899 todavía es táctil, 900 ya no.
    for (final width in <double>[430, 834, 899]) {
      testWidgets('a $width la lista es un bottom sheet', (tester) async {
        await _pump(tester, size: Size(width, 1000));
        await tester.tap(find.byType(VbShortSelect<String?>));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.byType(VbPopoverSurface),
          findsNothing,
          reason: 'la tablet de 834 es un host TÁCTIL, no un escritorio '
              'angosto: usar 600 como umbral es lo que puso un popover ahí',
        );
      });
    }

    testWidgets('a 900 ya es escritorio: popover', (tester) async {
      await _pump(tester, size: const Size(900, 1000));
      await tester.tap(find.byType(VbShortSelect<String?>));
      await tester.pumpAndSettle();
      expect(find.byType(VbPopoverSurface), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    });

    test('el umbral del widget es el del repositorio, no uno propio', () {
      expect(VbShortSelect.touchTargetHeight, 48);
      expect(ResponsiveBreakpoints.desktopMin, 900);
      expect(VbShortSelect.fieldHeight, 34);
    });
  });

  group('F-06 · el objetivo táctil crece; la caja NO', () {
    for (final width in <double>[430, 834, 899]) {
      testWidgets('a $width el objetivo mide 48 y la caja sigue en 34',
          (tester) async {
        await _pump(tester, size: Size(width, 1000));
        expect(
          tester.getSize(find.byType(InkWell)).height,
          48,
          reason: 'GUI_MOBILE_DESIGN_PRINCIPLES exige 48 px de objetivo '
              'táctil, y F-06 lo repite para todo lo que esté bajo 900',
        );
        // La guía dibuja este patrón como «TOUCH — 48 con área invisible»: lo
        // que crece es el área, no el control.
        final visual = tester.getSize(
          find
              .descendant(
                of: find.byType(InkWell),
                matching: find.byType(Container),
              )
              .last,
        );
        expect(visual.height, 34);
        // Y el nodo semántico es el objetivo, no la caja: un lector de
        // pantalla y el sistema de accesibilidad ven los 48.
        expect(
          tester.getSize(find.byType(VbShortSelect<String?>)).height,
          48,
        );
      });
    }

    testWidgets('en escritorio el objetivo ES la caja: 34', (tester) async {
      await _pump(tester, size: const Size(1360, 800));
      expect(tester.getSize(find.byType(InkWell)).height, 34);
      expect(tester.getSize(find.byType(VbShortSelect<String?>)).height, 34);
    });
  });

  group('S-05 · el techo de la guía', () {
    test('los consumidores migrados caben bajo el techo de 7', () {
      // «Hasta ~7 opciones… El menú no es scrollable: si necesita scroll, era
      // el otro componente.» El tipo de cuenta son los tres del CHECK más
      // «Sin especificar».
      expect(
        BankAccountType.values.length + 1,
        lessThanOrEqualTo(VbShortSelect.maxOptions),
        reason: 'si el CHECK crece más allá del techo, el tipo de cuenta pasa '
            'a ser S-06 y no un S-05 más alto',
      );
      expect(VbShortSelect.maxOptions, 7);
    });
  });

  group('S-05 · oscuro no es claro con otro fondo', () {
    testWidgets('el campo toma la superficie y el contorno del tema oscuro',
        (tester) async {
      await _pump(tester, brightness: Brightness.dark);
      final decoration = _fieldDecoration(tester);
      final scheme = _scheme(tester);
      expect(decoration.color, scheme.surface);
      expect((decoration.border! as Border).top.color, scheme.outline);
      expect(scheme.brightness, Brightness.dark);
    });
  });
}
