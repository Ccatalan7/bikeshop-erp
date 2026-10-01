import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_spec_field_row.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

Widget _host(Widget child, {double width = 900}) => MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: Center(child: SizedBox(width: width, child: child)),
      ),
    );

void main() {
  testWidgets('the name of the datum sits beside the control when it fits',
      (tester) async {
    await tester.pumpWidget(_host(const ProductSpecFieldRow(
      label: 'Paso',
      info: 'Distancia entre pasadores.',
      child: TextField(key: ValueKey('control')),
    )));
    final label = tester.getTopLeft(find.text('Paso'));
    final control = tester.getTopLeft(find.byKey(const ValueKey('control')));
    expect(control.dx, greaterThan(label.dx + 150));
    // The explanation is behind the icon, not printed under the control.
    expect(find.text('Distancia entre pasadores.'), findsNothing);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    // A short value keeps a short box.
    expect(tester.getSize(find.byKey(const ValueKey('control'))).width,
        lessThanOrEqualTo(ProductSpecFieldRow.compactControlMaxWidth));
  });

  testWidgets('on a phone the name goes above the control', (tester) async {
    await tester.pumpWidget(_host(
        const ProductSpecFieldRow(
          label: 'Paso',
          child: TextField(key: ValueKey('control')),
        ),
        width: 380));
    final label = tester.getBottomLeft(find.text('Paso'));
    final control = tester.getTopLeft(find.byKey(const ValueKey('control')));
    expect(control.dy, greaterThanOrEqualTo(label.dy));
  });

  testWidgets('only a pending or blocking note is written under the control',
      (tester) async {
    await tester.pumpWidget(_host(const ProductSpecFieldRow(
      label: 'Longitud',
      note: 'Se habilita cuando completes «Referencia de medida».',
      noteTone: ProductSpecFieldNoteTone.pending,
      dependent: true,
      child: TextField(),
    )));
    expect(find.text('Se habilita cuando completes «Referencia de medida».'),
        findsOneWidget);
  });
}
