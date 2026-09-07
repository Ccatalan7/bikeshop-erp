import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/widgets/vb_button.dart';
import 'package:vinabike_erp/shared/widgets/vb_segmented.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {Size size = const Size(1440, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
          preset: AppearancePresets.vinabike, brightness: Brightness.light),
      home: Scaffold(body: Center(child: child))));
}

Material _material(WidgetTester tester, Key key) => tester.widget<Material>(find
    .descendant(of: find.byKey(key), matching: find.byType(Material))
    .first);

void main() {
  testWidgets('A-01: height follows density and the label never wraps',
      (tester) async {
    await _pump(
        tester,
        const Column(mainAxisSize: MainAxisSize.min, children: [
          VbButton(
              key: Key('c'),
              label: 'Seleccionar',
              density: VbDensity.compact,
              onPressed: _noop),
          VbButton(
              key: Key('m'),
              label: 'Seleccionar',
              density: VbDensity.comfortable,
              onPressed: _noop),
          VbButton(
              key: Key('t'),
              label: 'Seleccionar',
              density: VbDensity.touch,
              onPressed: _noop),
        ]));
    expect(tester.getSize(find.byKey(const Key('c'))).height, 32);
    expect(tester.getSize(find.byKey(const Key('m'))).height, 38);
    expect(tester.getSize(find.byKey(const Key('t'))).height, 48);
    final text = tester.widget<Text>(find.text('Seleccionar').first);
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);
    expect(text.style?.fontSize, VbButton.fontSize);
    expect(text.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('under 900 px the default density is touch', (tester) async {
    await _pump(
        tester, const VbButton(key: Key('b'), label: 'Pagar', onPressed: _noop),
        size: const Size(390, 844));
    expect(tester.getSize(find.byKey(const Key('b'))).height, 48);
  });

  testWidgets('variants bind to theme roles, never to literals',
      (tester) async {
    late BuildContext context;
    await _pump(tester, Builder(builder: (ctx) {
      context = ctx;
      return const Column(mainAxisSize: MainAxisSize.min, children: [
        VbButton(key: Key('p'), label: 'Pagar', onPressed: _noop),
        VbButton(
            key: Key('s'),
            label: 'Ver pago',
            variant: VbButtonVariant.secondary,
            onPressed: _noop),
        VbButton(
            key: Key('x'),
            label: 'Cambiar',
            variant: VbButtonVariant.text,
            onPressed: _noop),
        VbButton(
            key: Key('d'),
            label: 'Anular pago',
            variant: VbButtonVariant.destructive,
            onPressed: _noop),
        VbButton(key: Key('off'), label: 'Confirmar', onPressed: null),
      ]);
    }));
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    expect(_material(tester, const Key('p')).color, scheme.primary);
    expect(_material(tester, const Key('s')).color, scheme.primaryContainer);
    expect(
        (_material(tester, const Key('s')).shape as RoundedRectangleBorder)
            .side
            .color,
        roles.accentBorder);
    expect(_material(tester, const Key('x')).color, Colors.transparent);
    expect(_material(tester, const Key('d')).color, roles.danger.accent);
    expect(_material(tester, const Key('off')).color, scheme.surface);
    final radius =
        (_material(tester, const Key('p')).shape as RoundedRectangleBorder)
            .borderRadius as BorderRadius;
    expect(radius.topLeft.x, VbButton.radius);
  });

  testWidgets(
      'a disabled button explains itself and a busy one keeps its label',
      (tester) async {
    var taps = 0;
    await _pump(
        tester,
        Column(mainAxisSize: MainAxisSize.min, children: [
          const VbButton(
              key: Key('off'),
              label: 'Confirmar S28',
              onPressed: null,
              disabledReason:
                  'Se habilita cuando los 2 pagos pendientes estén registrados.'),
          VbButton(
              key: const Key('busy'),
              label: 'Registrando…',
              busy: true,
              onPressed: () => taps++),
        ]));
    expect(
        find.text(
            'Se habilita cuando los 2 pagos pendientes estén registrados.'),
        findsOneWidget);
    expect(find.text('Registrando…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byKey(const Key('busy')));
    expect(taps, 0);
    expect(find.bySemanticsLabel('Confirmar S28'), findsOneWidget);
  });
}

void _noop() {}
