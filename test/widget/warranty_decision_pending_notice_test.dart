import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/warranty_decision_pending_notice.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';

Future<void> _pump(
  WidgetTester tester, {
  required WarrantyOutcome outcome,
  required Brightness brightness,
  double width = 320,
}) async {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.vinabike,
      brightness: brightness,
    ),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: WarrantyDecisionPendingNotice(outcome: outcome),
      ),
    ),
  ));
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'la decisión pendiente se lee entera y cabe en un teléfono '
        '(${brightness.name})', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        outcome: WarrantyOutcome.covered,
        brightness: brightness,
      );
      expect(tester.takeException(), isNull);
      final notice = find.byKey(const ValueKey('warranty-decision-pending'));
      expect(notice, findsOneWidget);
      // Un solo nodo con el qué y el por qué; nunca «aplicada».
      expect(
        find.bySemanticsLabel(
          'La decisión «Cubierto» todavía no se aplica. Quedó en este equipo '
          'y se envía sola, antes de cualquier cambio de estado del trabajo. '
          'Mientras tanto, la cobertura y el documento siguen como están.',
        ),
        findsOneWidget,
      );
      // El color sale de los roles del tema, así que el oscuro no hereda el
      // fondo claro.
      final context = tester.element(notice);
      final roles = VinabikeThemeRoles.of(context);
      final box = tester.widget<Container>(
          find.descendant(of: notice, matching: find.byType(Container)).first);
      expect((box.decoration! as BoxDecoration).color, roles.info.container);
      semantics.dispose();
    });
  }

  test('volver a evaluación no dice «Decisión «Pendiente» pendiente»', () {
    expect(
      WarrantyDecisionPendingNotice.titleFor(WarrantyOutcome.pending),
      'Devolver la garantía a evaluación todavía no se aplica',
    );
    expect(
      WarrantyDecisionPendingNotice.titleFor(WarrantyOutcome.notCovered),
      'La decisión «No cubierto» todavía no se aplica',
    );
  });
}
