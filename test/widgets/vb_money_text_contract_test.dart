import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/widgets/vb_money_text.dart';

/// **F-03 · `VbMoneyText`** — contrato de cómo se escribe el dinero.
///
/// Cada regla existe porque romperla hace que una cifra diga algo distinto de
/// lo que vale: un cero en blanco no se lee «cero» sino «no sé», un `-40000` no
/// se lee como pérdida a la misma velocidad que `−$40.000`, y media cifra
/// truncada con `…` es peor que ninguna.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  AppearancePreset? preset,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      theme: AppTheme.resolve(
        preset: preset ?? AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pump();
}

void main() {
  test('CLP: sin decimales, punto de miles, símbolo pegado, menos matemático',
      () {
    expect(VbMoneyText.formatClp(1204900), r'$1.204.900');
    expect(VbMoneyText.formatClp(219375), r'$219.375');
    expect(VbMoneyText.formatClp(0), r'$0');
    expect(VbMoneyText.formatClp(250), r'$250');
    // El menos es el matemático `−` (U+2212), no el guion del teclado, y nunca
    // paréntesis contables.
    expect(VbMoneyText.formatClp(-40000), '−\$40.000');
    expect(VbMoneyText.formatClp(-40000).contains('('), isFalse);
    expect(VbMoneyText.formatClp(-40000).startsWith('-'), isFalse);
    // Sin decimales: se redondea, no se recorta a la vista.
    expect(VbMoneyText.formatClp(1204899.6), r'$1.204.900');
  });

  testWidgets(
      'cero y «no aplica» van en inkFaint —que es neutral.accent, NO onSurfaceVariant— en 6 presets × 2 brillos',
      (tester) async {
    for (final preset in AppearancePresets.all) {
      for (final brightness in Brightness.values) {
        final cell = '${preset.code}/${brightness.name}';

        await _pump(tester, const VbMoneyText(0),
            preset: preset, brightness: brightness);
        var roles =
            VinabikeThemeRoles.of(tester.element(find.byType(VbMoneyText)));
        expect(
          tester.widget<Text>(find.text(r'$0')).style?.color,
          roles.neutral.accent,
          reason: '$cell: un cero real va en inkFaint = neutral.accent',
        );

        await _pump(tester, const VbMoneyText(null),
            preset: preset, brightness: brightness);
        roles = VinabikeThemeRoles.of(tester.element(find.byType(VbMoneyText)));
        expect(find.text('—'), findsOneWidget,
            reason: '$cell: «no aplica» es una raya, jamás una celda vacía');
        expect(
          tester.widget<Text>(find.text('—')).style?.color,
          roles.neutral.accent,
          reason: '$cell: el «no aplica» también va apagado',
        );

        // Y una cifra con valor NO va apagada: si las dos usaran el mismo tono,
        // el contraste que separa «cero» de «plata» desaparecería.
        await _pump(tester, const VbMoneyText(551850),
            preset: preset, brightness: brightness);
        final element = tester.element(find.byType(VbMoneyText));
        final style = tester.widget<Text>(find.text(r'$551.850')).style;
        expect(style?.color, Theme.of(element).colorScheme.onSurface,
            reason: cell);
        expect(
          style?.color,
          isNot(VinabikeThemeRoles.of(element).neutral.accent),
          reason: '$cell: una cifra con valor no puede verse como un cero',
        );
      }
    }
  });

  testWidgets(
      'mono tabular, 700/14 y a la derecha: el único tamaño que la guía publica para dinero',
      (tester) async {
    await _pump(tester, const VbMoneyText(1204900));
    final text = tester.widget<Text>(find.text(r'$1.204.900'));

    expect(
      text.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
      reason: 'sin cifras tabulares los dígitos bailan entre filas',
    );
    expect(text.style?.fontFamily, contains('Mono'));
    expect(text.style?.fontSize, 14);
    expect(text.style?.fontWeight, FontWeight.w700);
    expect(text.textAlign, TextAlign.right);
  });

  testWidgets(
      '9 dígitos no se truncan: media cifra de dinero es peor que ninguna',
      (tester) async {
    await _pump(
      tester,
      const SizedBox(width: 40, child: VbMoneyText(123456789)),
    );
    final text = tester.widget<Text>(find.text(r'$123.456.789'));

    expect(text.overflow, TextOverflow.visible,
        reason: 'prohibido truncar dinero con «…»');
    expect(text.softWrap, isFalse);
    expect(text.maxLines, 1);
  });
}
