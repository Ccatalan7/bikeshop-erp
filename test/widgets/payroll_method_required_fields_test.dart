import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/models/hr_models.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_method_sheet.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **`5n` fila 14 · qué exige de verdad una transferencia.**
///
/// La fila de la matriz pide «banco/tipo/número/**RUT**» y da por hecho que los
/// cuatro son requeridos. **Contra esta app eso es falso, y por eso la fila se
/// re-adjudica en vez de probarse tal cual:**
///
/// * **Banco y número: requeridos.** Sin ellos no se puede transferir, y
///   `_canSave` lo exige.
/// * **Tipo: OPCIONAL.** `Sin especificar` es una opción legal del control, y
///   el `check` de la base (`employees_bank_account_type_check`) admite los
///   tres tipos pero no obliga a elegir uno.
/// * **RUT / titular: DESCARTADO con razón de ownership**, no pendiente.
///   `account_holder_name`/`account_holder_rut` existen sólo en
///   `company_bank_accounts` —las cuentas de la EMPRESA—, así que `employees`
///   no tiene dónde guardarlo; y el propósito que el frame le da («entender un
///   nombre distinto en la cartola») ya lo cumple el owner canónico
///   `payroll_beneficiary_aliases`. Pedirlo acá inventaría un campo y
///   duplicaría un mecanismo.
///
/// Que el RUT esté descartado **se afirma**, no se deja implícito: la prueba
/// exige que no exista, para que reaparecer sea una falla y no un descuido.
void main() {
  const transfer = PayrollMethodOption(
    id: 'm-transfer',
    code: 'transfer',
    name: 'Transferencia',
  );
  const cash = PayrollMethodOption(
    id: 'm-cash',
    code: 'cash',
    name: 'Efectivo',
  );

  final saveButton = find.byKey(const ValueKey<String>('payroll-method-save'));

  /// Monta la hoja en una ruta real para poder recoger el `PayrollMethodDraft`
  /// que devuelve al guardar: el draft ES el contrato de esta fila.
  Future<PayrollMethodDraft?> openSheet(
    WidgetTester tester, {
    required String selectedMethodId,
    String? bankName,
    BankAccountType? bankAccountType,
    String? bankAccountNumber,
    required Future<void> Function(WidgetTester tester) act,
  }) async {
    PayrollMethodDraft? result;
    late BuildContext hostContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: Builder(
          builder: (context) {
            hostContext = context;
            return const Scaffold(body: SizedBox.shrink());
          },
        ),
      ),
    );

    final pending = Navigator.of(hostContext).push<PayrollMethodDraft>(
      MaterialPageRoute<PayrollMethodDraft>(
        builder: (_) => Scaffold(
          body: PayrollMethodSheet(
            employeeName: 'Vicente Díaz',
            options: const <PayrollMethodOption>[transfer, cash],
            authority: PayrollMethodAuthority.editable,
            returnLabel: 'Vuelves a la lista de la semana',
            confirmLabel: 'Guardar método',
            selectedMethodId: selectedMethodId,
            bankName: bankName,
            bankAccountType: bankAccountType,
            bankAccountNumber: bankAccountNumber,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await act(tester);

    result = await pending;
    return result;
  }

  group('5n fila 14 · requeridos de la transferencia', () {
    testWidgets('sin banco ni número no se puede guardar', (tester) async {
      await openSheet(
        tester,
        selectedMethodId: transfer.id,
        act: (tester) async {
          expect(
            tester.widget<FilledButton>(saveButton).onPressed,
            isNull,
            reason: 'una transferencia sin cuenta no se puede guardar',
          );
          Navigator.of(tester.element(saveButton)).pop();
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('con banco pero sin número tampoco', (tester) async {
      await openSheet(
        tester,
        selectedMethodId: transfer.id,
        bankName: 'Banco de Chile',
        act: (tester) async {
          expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
          Navigator.of(tester.element(saveButton)).pop();
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets(
        'banco + número bastan: el TIPO es opcional y el draft los lleva',
        (tester) async {
      final draft = await openSheet(
        tester,
        selectedMethodId: transfer.id,
        bankName: 'Banco de Chile',
        bankAccountNumber: '00012345678',
        act: (tester) async {
          // El tipo quedó SIN elegir a propósito: si fuera requerido, esto
          // seguiría deshabilitado y la prueba caería acá.
          expect(
            tester.widget<FilledButton>(saveButton).onPressed,
            isNotNull,
            reason: 'el tipo de cuenta no es requerido',
          );
          await tester.tap(saveButton);
          await tester.pumpAndSettle();
        },
      );

      expect(draft, isNotNull);
      expect(draft!.methodCode, 'transfer');
      expect(draft.bankName, 'Banco de Chile');
      expect(draft.bankAccountNumber, '00012345678');
      expect(draft.bankAccountType, isNull, reason: 'nadie eligió un tipo');
      expect(draft.touchesBankAccount, isTrue);
    });

    testWidgets('efectivo guarda sin cuenta, y el draft NO toca lo bancario',
        (tester) async {
      final draft = await openSheet(
        tester,
        selectedMethodId: cash.id,
        // Aunque la ficha traiga datos bancarios de antes, elegir efectivo no
        // debe arrastrarlos al UPDATE: `touchesBankAccount` es lo que decide.
        bankName: 'Banco de Chile',
        bankAccountNumber: '00012345678',
        act: (tester) async {
          expect(find.byType(TextField), findsNothing);
          expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
          await tester.tap(saveButton);
          await tester.pumpAndSettle();
        },
      );

      expect(draft, isNotNull);
      expect(draft!.methodCode, 'cash');
      expect(draft.touchesBankAccount, isFalse);
      expect(draft.bankName, isNull);
      expect(draft.bankAccountNumber, isNull);
      expect(draft.bankAccountType, isNull);
    });

    testWidgets('el RUT/titular está DESCARTADO: no puede reaparecer',
        (tester) async {
      await openSheet(
        tester,
        selectedMethodId: transfer.id,
        bankName: 'Banco de Chile',
        bankAccountNumber: '00012345678',
        act: (tester) async {
          for (final forbidden in const <String>[
            'RUT',
            'Titular',
            'TITULAR',
            'Rut del titular',
          ]) {
            expect(
              find.textContaining(forbidden),
              findsNothing,
              reason: '«$forbidden» no tiene dónde guardarse en `employees`',
            );
          }
          // Los tres campos que SÍ existen siguen siendo dos de texto (banco y
          // número) más el select de tipo: si alguien agrega un cuarto, esto
          // cae y obliga a re-adjudicar la fila en vez de colarlo.
          expect(find.byType(TextField), findsNWidgets(2));
          Navigator.of(tester.element(saveButton)).pop();
          await tester.pumpAndSettle();
        },
      );
    });
  });
}
