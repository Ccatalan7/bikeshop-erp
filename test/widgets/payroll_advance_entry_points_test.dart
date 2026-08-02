import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_queue_surface.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **`5n` fila 16 · un anticipo se crea desde la persona O desde la semana.**
///
/// La entrada **desde la persona** ya estaba cubierta por conducta
/// (`payroll_advances_ux_test.dart`, «a person-scoped entry starts with that
/// worker selected»: el formulario abre con ese trabajador preseleccionado y
/// **sin escribir nada**). Lo que no tenía prueba era la **otra** entrada: el
/// atajo `Nuevo anticipo` de la fila de la semana.
///
/// Acá se prueba esa pata, y se prueba lo que importa de ella: que el atajo
/// **existe dentro de la fila abierta** —no suelto en la pantalla— y que al
/// tocarlo dispara su acción **con la identidad de esa fila**. El escritor es
/// falso: esta prueba no toca base de datos ni registra ningún anticipo.
///
/// Lo que **no** se afirma acá, para no fingir alcance: que el diálogo que la
/// página abre después quede preseleccionado. Eso es lo que ya demuestra la
/// prueba de la entrada por persona, y duplicarlo con un arnés de página no
/// agregaría verdad.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  PayrollWeekCardVM week() => PayrollWeekCardVM(
        name: 'Semana 28',
        range: '07 – 13 jul',
        amountLabel: r'$267.875',
        amountCaption: 'por pagar',
        statusLabel: 'ABIERTA',
        tone: PayrollStateTone.warning,
        selected: true,
        onTap: () {},
      );

  const totals = PayrollWeekTotalsVM(
    title: 'Semana 28 · 07 – 13 jul',
    equation: r'total $172.875 − anticipos $0 − pagado $0',
    remaining: r'$172.875',
    showCommitAction: false,
    canConfirm: false,
    blockedReason: '',
    nextActionLabel: 'Pagar a Lucas',
  );

  testWidgets(
      '5n fila 16 · el atajo «Nuevo anticipo» vive en la fila y lleva su identidad',
      (tester) async {
    final opened = <String>[];

    PayrollPersonRowVM personRow({
      required String name,
      required bool expanded,
    }) =>
        PayrollPersonRowVM(
          name: name,
          initials: name.substring(0, 2).toUpperCase(),
          avatarColor: PayrollTokens.avatarSky,
          method: 'Transferencia bancaria',
          methodIsCash: false,
          earned: r'$172.875',
          advances: '—',
          newMoney: r'$172.875',
          paid: '—',
          status: PayrollRowStatus.pendingTransfer,
          statusLabel: 'Por pagar',
          statusMeta: '',
          actionLabel: 'Pagar',
          actionMode: PayrollRowActionMode.direct,
          blockedReason: '',
          hours: '38,5 h',
          rate: r'$4.490 / h',
          paymentsSummary: 'Sin pagos registrados',
          expanded: expanded,
          shortcuts: <PayrollRowShortcutVM>[
            // El escritor es este `add`: la prueba no registra nada.
            PayrollRowShortcutVM(
              label: 'Nuevo anticipo',
              onTap: () => opened.add(name),
            ),
          ],
          onToggle: () {},
          onAction: () {},
        );

    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pumpWith({required bool expanded}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike,
            brightness: Brightness.light,
          ),
          home: Scaffold(
            body: PayrollQueueSurface(
              weeks: <PayrollWeekCardVM>[week()],
              rows: <PayrollPersonRowVM>[
                personRow(name: 'Lucas Pacheco', expanded: expanded),
                personRow(name: 'Vicente Díaz', expanded: false),
              ],
              totals: totals,
              dense: false,
              onOpenAttendance: () {},
              onConfirmWeek: () {},
              onNextAction: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    // Con la fila CERRADA el atajo no está: es parte del disclosure, no una
    // acción suelta de la pantalla. Si esto deja de ser cierto, el atajo se
    // volvió alcanzable sin abrir a nadie.
    await pumpWith(expanded: false);
    expect(find.text('Nuevo anticipo'), findsNothing);

    // Abierta la fila de Lucas, el atajo aparece **una vez** —el de Vicente
    // sigue cerrado— y al tocarlo dispara con SU identidad.
    await pumpWith(expanded: true);
    final shortcut = find.text('Nuevo anticipo');
    expect(shortcut, findsOneWidget);

    await tester.tap(shortcut);
    await tester.pumpAndSettle();

    expect(opened, <String>['Lucas Pacheco']);
    expect(tester.takeException(), isNull);
  });
}
