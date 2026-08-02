import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/modules/hr/models/hr_models.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_method_sheet.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_employee_payment_method_command.dart';

/// **5g · comportamiento del comando y del dominio de tipo de cuenta.**
///
/// Esta ruta escribe el dato con el que después se giran sueldos, desde una
/// pantalla que **no** es la ficha del trabajador. Las pruebas de antes miraban
/// el **texto fuente** del comando; se reemplazaron por asertos de conducta,
/// porque un contrato que se verifica leyendo el código se rompe en cuanto
/// alguien reescribe la misma lógica de otra forma.
void main() {
  group('5g · dominio de tipo de cuenta', () {
    test('serializa EXACTAMENTE los tres valores del constraint vivo', () {
      // employees_bank_account_type_check
      //   CHECK (bank_account_type = ANY (ARRAY[
      //     'Cuenta Corriente','Cuenta Vista','Cuenta de Ahorro']))
      expect(
        BankAccountType.storageDomain,
        <String>['Cuenta Corriente', 'Cuenta Vista', 'Cuenta de Ahorro'],
      );
      expect(
        BankAccountType.values.map(BankAccountType.encode),
        <String>['Cuenta Corriente', 'Cuenta Vista', 'Cuenta de Ahorro'],
      );
    });

    test('«Cuenta RUT» no pertenece al dominio, aunque el frame la dibuje', () {
      expect(BankAccountType.storageDomain, isNot(contains('Cuenta RUT')));
      expect(BankAccountType.decode('Cuenta RUT'), isNull);
    });

    test('decodifica los códigos legacy en inglés sin perder lo guardado', () {
      // El enum serializaba 'checking'/'savings'/'vista' — valores que el CHECK
      // rechaza. Si alguno quedó escrito antes, se sigue entendiendo.
      expect(BankAccountType.decode('checking'), BankAccountType.checking);
      expect(BankAccountType.decode('savings'), BankAccountType.savings);
      expect(BankAccountType.decode('vista'), BankAccountType.vista);
    });

    test('decodifica los valores vivos y la variante «Cuenta Ahorro»', () {
      expect(
        BankAccountType.decode('Cuenta Corriente'),
        BankAccountType.checking,
      );
      expect(
        BankAccountType.decode('Cuenta de Ahorro'),
        BankAccountType.savings,
      );
      // El desplegable del editor rotulaba así, sin el «de».
      expect(BankAccountType.decode('Cuenta Ahorro'), BankAccountType.savings);
      expect(BankAccountType.decode(null), isNull);
      expect(BankAccountType.decode('   '), isNull);
    });

    test('lo que se decodifica se vuelve a escribir en el dominio vivo', () {
      for (final legacy in <String>['checking', 'savings', 'vista']) {
        expect(
          BankAccountType.storageDomain,
          contains(BankAccountType.encode(BankAccountType.decode(legacy))),
          reason: 'decodificar $legacy y volver a escribirlo tiene que caer '
              'dentro de lo que el CHECK admite',
        );
      }
    });
  });

  group('5g · parámetros del comando atómico', () {
    test('efectivo no envía autoridad legacy ni datos bancarios visibles',
        () async {
      final store = _FakeEmployeeStore(
        row: _row(
          bankName: 'BancoEstado',
          bankAccountType: 'Cuenta Vista',
          accountNumber: '123',
        ),
      );
      final command = PayrollEmployeePaymentMethodCommand.forTesting(store);
      final outcome = await command.apply(
        expected: _snapshot(
          bankName: 'BancoEstado',
          bankAccountType: 'Cuenta Vista',
          bankAccountNumber: '123',
        ),
        methodId: 'm-cash',
        methodCode: 'cash',
        touchesBankAccount: false,
      );

      expect(outcome.isApplied, isTrue);
      expect(outcome.snapshot?.preferredMethodLegacy, 'cash');
      expect(outcome.snapshot?.bankName, 'BancoEstado');
      expect(store.lastSetPaymentMethod, <String, dynamic>{
        'employeeId': 'e1',
        'expectedUpdatedAt': '2026-08-01T00:00:00.123456+00:00',
        'methodId': 'm-cash',
        'bankName': null,
        'bankAccountType': null,
        'bankAccountNumber': null,
      });
      expect(
        store.lastSetPaymentMethod,
        isNot(contains('methodCode')),
        reason: 'el servidor deriva el código desde el método bloqueado',
      );
    });

    test('con transferencia viajan los tres campos, y el tipo como valor vivo',
        () async {
      final store = _FakeEmployeeStore(row: _row());
      final command = PayrollEmployeePaymentMethodCommand.forTesting(store);
      await command.apply(
        expected: _snapshot(),
        methodId: 'm-transfer',
        methodCode: 'transfer',
        touchesBankAccount: true,
        bankName: '  BancoEstado  ',
        bankAccountType: BankAccountType.savings,
        bankAccountNumber: ' 18442107 ',
      );
      final params = store.lastSetPaymentMethod!;
      expect(params['bankName'], 'BancoEstado');
      expect(params['bankAccountNumber'], '18442107');
      expect(params['bankAccountType'], 'Cuenta de Ahorro');
      expect(
        BankAccountType.storageDomain,
        contains(params['bankAccountType']),
      );
    });

    test('envía identidad y versión exacta, pero no un tenant confiado',
        () async {
      final store = _FakeEmployeeStore(row: _row());
      final command = PayrollEmployeePaymentMethodCommand.forTesting(store);
      await command.apply(
        expected: _snapshot(),
        methodId: 'm-cash',
        methodCode: 'cash',
        touchesBankAccount: false,
      );
      expect(store.lastSetPaymentMethod!['employeeId'], 'e1');
      expect(
        store.lastSetPaymentMethod!['expectedUpdatedAt'],
        '2026-08-01T00:00:00.123456+00:00',
      );
      expect(store.lastSetPaymentMethod!['methodId'], 'm-cash');
      expect(store.lastSetPaymentMethod, isNot(contains('tenantId')));
    });
  });

  group('5g · ningún fallo se anuncia como guardado', () {
    test('un rechazo del servidor es «rejected», no «applied»', () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        writeError: _postgrest('23514', 'employees_bank_account_type_check'),
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store).apply(
        expected: _snapshot(),
        methodId: 'm-transfer',
        methodCode: 'transfer',
        touchesBankAccount: true,
        bankName: 'BancoEstado',
        bankAccountNumber: '1',
      );
      expect(outcome.status, PayrollEmployeePaymentWriteStatus.rejected);
      expect(outcome.isApplied, isFalse);
    });

    test('un 42501 se distingue como falta de autoridad', () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        writeError: _postgrest('42501', 'row-level security'),
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store).apply(
        expected: _snapshot(),
        methodId: 'm-cash',
        methodCode: 'cash',
        touchesBankAccount: false,
      );
      expect(outcome.status, PayrollEmployeePaymentWriteStatus.notAuthorized);
    });

    test('una falla de transporte no dice si escribió o no', () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        writeError: Exception('socket'),
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store).apply(
        expected: _snapshot(),
        methodId: 'm-cash',
        methodCode: 'cash',
        touchesBankAccount: false,
      );
      expect(outcome.status, PayrollEmployeePaymentWriteStatus.unreachable);
    });

    test('40001 es conflicto y relee la versión vigente', () async {
      final store = _FakeEmployeeStore(
        row: _row(updatedAt: '2026-08-01T09:00:00.000000+00:00'),
        writeError: _postgrest(
          '40001',
          'payroll_employee_payment_method_version_conflict',
        ),
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store).apply(
        expected: _snapshot(),
        methodId: 'm-cash',
        methodCode: 'cash',
        touchesBankAccount: false,
      );
      expect(outcome.status, PayrollEmployeePaymentWriteStatus.versionConflict);
      expect(
        outcome.snapshot?.updatedAtRaw,
        '2026-08-01T09:00:00.000000+00:00',
      );
    });

    test('P0002 es ficha ausente o fuera del tenant, no dato inválido',
        () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        writeError: _postgrest(
          'P0002',
          'payroll_employee_payment_method_employee_not_found',
        ),
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store).apply(
        expected: _snapshot(),
        methodId: 'm-cash',
        methodCode: 'cash',
        touchesBankAccount: false,
      );
      expect(outcome.status, PayrollEmployeePaymentWriteStatus.missing);
    });

    test('un recibo stale o de otro método jamás se anuncia como guardado',
        () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        writeRow: _row(
          // Mismo timestamp y método anterior: las dos señales son inválidas.
          updatedAt: '2026-08-01T00:00:00.123456+00:00',
          methodId: 'm-transfer',
          methodCode: 'transfer',
        ),
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store).apply(
        expected: _snapshot(),
        methodId: 'm-cash',
        methodCode: 'cash',
        touchesBankAccount: false,
      );
      expect(outcome.status, PayrollEmployeePaymentWriteStatus.unreachable);
      expect(outcome.isApplied, isFalse);
    });

    test('un recibo con id correcto pero código contrario no dice guardado',
        () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        writeRow: _row(
          updatedAt: '2026-08-01T00:00:01.654321+00:00',
          methodId: 'm-cash',
          methodCode: 'cash',
        ),
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store).apply(
        expected: _snapshot(),
        methodId: 'm-cash',
        methodCode: 'transfer',
        touchesBankAccount: true,
        bankName: 'BancoEstado',
        bankAccountType: BankAccountType.vista,
        bankAccountNumber: '123',
      );

      expect(outcome.status, PayrollEmployeePaymentWriteStatus.unreachable);
      expect(outcome.isApplied, isFalse);
    });

    test('un recibo que omite una clave nullable no dice guardado', () async {
      final receipt = _row(
        updatedAt: '2026-08-01T00:00:01.654321+00:00',
        methodId: 'm-cash',
        methodCode: 'cash',
      )..remove('bank_name');
      final store = _FakeEmployeeStore(row: _row(), writeRow: receipt);
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store).apply(
        expected: _snapshot(),
        methodId: 'm-cash',
        methodCode: 'cash',
        touchesBankAccount: false,
      );

      expect(outcome.status, PayrollEmployeePaymentWriteStatus.unreachable);
      expect(outcome.isApplied, isFalse);
    });

    test('identidad incompleta se rechaza antes de tocar el servidor',
        () async {
      final store = _FakeEmployeeStore(row: _row());
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store).apply(
        expected: const PayrollEmployeePaymentSnapshot(
          employeeId: '',
          tenantId: 't1',
          updatedAtRaw: '2026-08-01T00:00:00.123456+00:00',
          hasCompleteRow: true,
        ),
        methodId: 'm-cash',
        methodCode: 'cash',
        touchesBankAccount: false,
      );
      expect(outcome.status, PayrollEmployeePaymentWriteStatus.rejected);
      expect(store.writeCalls, 0);
    });

    test('la lectura inicial también tiene desenlace: no explota', () async {
      final store =
          _FakeEmployeeStore(row: _row(), selectError: Exception('x'));
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store)
              .read('e1');
      expect(outcome.status, PayrollEmployeePaymentReadStatus.unavailable);
      expect(outcome.snapshot, isNull);
    });

    test('una fila de lectura incompleta no se presenta como ficha cargada',
        () async {
      final store = _FakeEmployeeStore(
        row: <String, dynamic>{
          ..._row(),
          'updated_at': null,
        },
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store)
              .read('e1');
      expect(outcome.status, PayrollEmployeePaymentReadStatus.unavailable);
      expect(outcome.snapshot, isNull);
    });

    test('una clave nullable ausente tampoco se presenta como fila completa',
        () async {
      final incomplete = _row()..remove('bank_account_number');
      final store = _FakeEmployeeStore(row: incomplete);
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store)
              .read('e1');

      expect(outcome.status, PayrollEmployeePaymentReadStatus.unavailable);
      expect(outcome.snapshot, isNull);
    });
  });

  group('5g · el aviso de cambio seguro es alcanzable', () {
    test('cuenta los pagos reales de la persona, sin recorrer el historial',
        () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        lineExpenseIds: <String>['exp-1', 'exp-2', 'exp-1'],
        paymentsByExpense: <String, int>{'exp-1': 5, 'exp-2': 2},
      );
      final command = PayrollEmployeePaymentMethodCommand.forTesting(store);
      expect(
        await command.countRecordedPayments('e1'),
        const PayrollRecordedPaymentCount.known(7),
      );
      // **Una lectura y un conteo. Ni una por semana, ni una por página.**
      expect(store.readCalls, 2);
      expect(store.countCalls, 1);
    });

    test('sin líneas con gasto no consulta pagos y no inventa un número',
        () async {
      final store = _FakeEmployeeStore(row: _row());
      final command = PayrollEmployeePaymentMethodCommand.forTesting(store);
      expect(
        await command.countRecordedPayments('e1'),
        const PayrollRecordedPaymentCount.known(0),
      );
      expect(store.readCalls, 1);
    });

    testWidgets('la hoja MUESTRA el bloque con pagos y lo OMITE sin pagos',
        (tester) async {
      // La versión anterior de esta prueba sólo leía los parámetros del
      // constructor: no montaba nada, así que no probaba que el bloque se
      // dibujara. Un aviso que existe en el código y no aparece en pantalla es
      // exactamente el defecto que esta ronda vino a corregir.
      await tester.pumpWidget(
          _host(recordedPayments: const PayrollRecordedPaymentCount.known(7)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('payroll-method-safe-change')),
        findsOneWidget,
      );
      expect(find.textContaining('7 pagos'), findsOneWidget);

      await tester.pumpWidget(
          _host(recordedPayments: const PayrollRecordedPaymentCount.known(0)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('payroll-method-safe-change')),
        findsNothing,
        reason: 'sin pagos registrados el bloque no tiene nada que afirmar',
      );
    });

    testWidgets('el select ofrece exactamente el dominio del constraint',
        (tester) async {
      await tester.pumpWidget(
        _host(
          recordedPayments: const PayrollRecordedPaymentCount.known(0),
          selectTransfer: true,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sin especificar'));
      await tester.pumpAndSettle();
      for (final value in BankAccountType.storageDomain) {
        expect(find.text(value), findsWidgets, reason: 'falta $value');
      }
      expect(find.text('Cuenta RUT'), findsNothing);
    });
  });

  group('5g · el conteo distingue «cero» de «no pude contar»', () {
    test('una falla al contar NO se convierte en cero', () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        lineExpenseIds: <String>['exp-1'],
        countError: _postgrest('57014', 'canceling statement due to timeout'),
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store)
              .countRecordedPayments('e1');
      expect(outcome.isKnown, isFalse);
      expect(outcome.value, isNull);
      expect(
        outcome,
        isNot(const PayrollRecordedPaymentCount.known(0)),
        reason: '«0 pagos» afirma que nunca cobró; «no pude contar» no afirma '
            'nada, y sobre sueldos ya pagados no son lo mismo',
      );
    });

    test('una falla al LEER las líneas tampoco se convierte en cero', () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        lineExpenseIds: <String>['exp-1'],
        lineReadError: _postgrest('08006', 'connection failure'),
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store)
              .countRecordedPayments('e1');
      expect(outcome.isKnown, isFalse);
    });

    test('por encima del techo dice que NO SABE, no un total parcial',
        () async {
      // 151 gastos con un techo de 150: la lectura no alcanza a cubrirlos, así
      // que cualquier número que devolviera sería mentira. El defecto anterior
      // paginaba y **afirmaba exactitud entre páginas**, que ningún cliente
      // puede garantizar sin una consulta atómica del servidor.
      final store = _FakeEmployeeStore(
        row: _row(),
        lineExpenseIds: <String>[for (var i = 0; i < 151; i++) 'exp-$i'],
        paymentsByExpense: <String, int>{'exp-0': 5},
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store)
              .countRecordedPayments('e1');
      expect(outcome.isKnown, isFalse);
      expect(
        store.countCalls,
        0,
        reason: 'si no se puede afirmar el total, ni siquiera se pregunta',
      );
      expect(store.lastLimit, 150);
    });

    test('justo EN el techo sí cuenta, y con un solo conteo', () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        lineExpenseIds: <String>[for (var i = 0; i < 150; i++) 'exp-$i'],
        paymentsByExpense: <String, int>{'exp-0': 4, 'exp-149': 3},
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store)
              .countRecordedPayments('e1');
      expect(outcome, const PayrollRecordedPaymentCount.known(7));
      expect(store.countCalls, 1);
    });

    test(
        'si el servidor entrega MENOS filas que su propio conteo, tampoco '
        'afirma', () async {
      // El adversario exacto: PostgREST aplica su `max-rows` y recorta antes
      // del techo pedido. Medir el desborde por el largo de lo recibido se
      // engañaría solo — por eso manda el `count` de `Content-Range`.
      final store = _FakeEmployeeStore(
        row: _row(),
        lineExpenseIds: <String>['exp-1', 'exp-2'],
        reportedTotal: 40,
        paymentsByExpense: <String, int>{'exp-1': 9},
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store)
              .countRecordedPayments('e1');
      expect(
        outcome.isKnown,
        isFalse,
        reason: 'llegaron 2 filas de 40: contar sobre esas 2 daría un número '
            'que parece exacto y no lo es',
      );
      expect(store.countCalls, 0);
    });

    test('«conocido y cero» no afirma que haya pagos', () {
      expect(
        const PayrollRecordedPaymentCount.known(0).hasRecordedPayments,
        isFalse,
      );
      expect(
        const PayrollRecordedPaymentCount.unavailable().hasRecordedPayments,
        isFalse,
      );
      expect(
        const PayrollRecordedPaymentCount.known(1).hasRecordedPayments,
        isTrue,
      );
    });

    testWidgets('sin conteo la hoja NO escribe el aviso', (tester) async {
      await tester.pumpWidget(
        _host(
            recordedPayments: const PayrollRecordedPaymentCount.unavailable()),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('payroll-method-safe-change')),
        findsNothing,
        reason: 'no se pudo contar: la hoja calla, no dice «0 pagos»',
      );
      expect(find.textContaining('pagos registrados'), findsNothing);
    });
  });

  group('5g · qué significa cada falla del servidor', () {
    test('la clase 23 —constraint y FK— es rechazo del dato', () {
      for (final code in <String>[
        '23514', // check_violation: employees_bank_account_type_check
        '23503', // foreign_key_violation: el método ya no existe
        '23502', // not_null_violation
        '23505', // unique_violation
      ]) {
        expect(
          classifyStoreFailure(code),
          PayrollEmployeePaymentWriteStatus.rejected,
          reason: '$code sí habla del dato que escribió el operador',
        );
      }
    });

    test('42501 es permiso, no dato inválido', () {
      expect(
        classifyStoreFailure('42501'),
        PayrollEmployeePaymentWriteStatus.notAuthorized,
      );
    });

    test('clase 22 es argumento rechazado antes de escribir', () {
      for (final code in <String>[
        '22023', // invalid_parameter_value emitido por el RPC
        '22P02', // UUID inválido al resolver la firma
        '22007', // timestamp inválido
      ]) {
        expect(
          classifyStoreFailure(code),
          PayrollEmployeePaymentWriteStatus.rejected,
        );
      }
    });

    test('timeouts, cortes y errores del servidor NO acusan al dato', () {
      for (final code in <String?>[
        '57014', // query_canceled: timeout
        '53300', // too_many_connections
        '08006', // connection_failure
        'PGRST301', // JWT expirado
        '42P01', // undefined_table: un defecto nuestro, no del operador
        null,
        '',
      ]) {
        expect(
          classifyStoreFailure(code),
          PayrollEmployeePaymentWriteStatus.unreachable,
          reason: 'decirle «el tipo de cuenta no es válido» por $code lo manda '
              'a corregir algo que estaba bien',
        );
      }
    });

    test('un CHECK violado llega a la pantalla como rechazo, no como corte',
        () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        writeError: _postgrest(
          '23514',
          'new row violates check constraint '
              '"employees_bank_account_type_check"',
        ),
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store).apply(
        expected: _snapshot(),
        methodId: 'm-transfer',
        methodCode: 'transfer',
        touchesBankAccount: true,
        bankAccountType: BankAccountType.checking,
      );
      expect(outcome.status, PayrollEmployeePaymentWriteStatus.rejected);
    });

    test('un timeout del servidor ya NO se reporta como dato inválido',
        () async {
      final store = _FakeEmployeeStore(
        row: _row(),
        writeError: _postgrest('57014', 'canceling statement due to timeout'),
      );
      final outcome =
          await PayrollEmployeePaymentMethodCommand.forTesting(store).apply(
        expected: _snapshot(),
        methodId: 'm-cash',
        methodCode: 'cash',
        touchesBankAccount: false,
      );
      expect(outcome.status, PayrollEmployeePaymentWriteStatus.unreachable);
    });
  });

  group('5g · método actual que Nóminas no puede pagar', () {
    // **No es alcanzable en vivo sin escribir.** En producción el único
    // trabajador cuyo método apunta a `Cheque` es `Fernando Tapia`, y tiene
    // **0 líneas en 0 semanas** (medido el 2026-08-01): la hoja se abre desde
    // la fila de una persona en una semana, así que llegar a su estado exigiría
    // crearle una línea, que es una escritura de producción. Se cubre por
    // contrato, y el límite queda declarado en el handoff.
    testWidgets('no preselecciona en silencio, avisa y no deja guardar',
        (tester) async {
      await tester.pumpWidget(
        _host(
          recordedPayments: const PayrollRecordedPaymentCount.known(0),
          // El id del método guardado NO está entre las opciones de Nóminas:
          // es el `check` real de producción.
          selectedMethodId: 'm-check',
          currentMethodName: 'Cheque',
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('payroll-method-unsupported')),
        findsOneWidget,
      );
      expect(find.textContaining('Cheque'), findsOneWidget);

      // **Ninguna de las dos opciones queda marcada.** Preseleccionar una en
      // silencio le cambiaría el método a alguien sin decírselo a nadie.
      for (final name in const <String>['Transferencia', 'Efectivo']) {
        final option = tester.getSemantics(find.text(name).first);
        expect(
          option.flagsCollection.isSelected,
          isNot(ui.Tristate.isTrue),
          reason: '$name no puede aparecer elegida: el trabajador tiene otra '
              'cosa guardada',
        );
      }

      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('payroll-method-save')),
      );
      expect(
        save.onPressed,
        isNull,
        reason: 'sin método utilizable elegido no hay nada que guardar',
      );
    });

    testWidgets('al elegir uno válido el aviso se va y Guardar se habilita',
        (tester) async {
      await tester.pumpWidget(
        _host(
          recordedPayments: const PayrollRecordedPaymentCount.known(0),
          selectedMethodId: 'm-check',
          currentMethodName: 'Cheque',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Efectivo'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('payroll-method-unsupported')),
        findsNothing,
      );
      final save = tester.widget<FilledButton>(
        find.byKey(const ValueKey<String>('payroll-method-save')),
      );
      expect(save.onPressed, isNotNull);
    });
  });

  group('5g · el borrador de la hoja', () {
    test('efectivo declara que no toca la cuenta; transferencia sí', () {
      const cash = PayrollMethodDraft(methodId: 'a', methodCode: 'cash');
      const transfer =
          PayrollMethodDraft(methodId: 'b', methodCode: 'transfer');
      expect(cash.touchesBankAccount, isFalse);
      expect(transfer.touchesBankAccount, isTrue);
    });
  });
}

Map<String, dynamic> _row({
  String updatedAt = '2026-08-01T00:00:00.123456+00:00',
  String? bankName,
  String? bankAccountType,
  String? accountNumber,
  String methodId = 'm-transfer',
  String methodCode = 'transfer',
}) {
  return <String, dynamic>{
    'id': 'e1',
    'tenant_id': 't1',
    'updated_at': updatedAt,
    'preferred_payment_method': methodCode,
    'preferred_payment_method_id': methodId,
    'bank_name': bankName,
    'bank_account_type': bankAccountType,
    'bank_account_number': accountNumber,
  };
}

PayrollEmployeePaymentSnapshot _snapshot({
  String? bankName,
  String? bankAccountType,
  String? bankAccountNumber,
}) =>
    PayrollEmployeePaymentSnapshot(
      employeeId: 'e1',
      tenantId: 't1',
      updatedAtRaw: '2026-08-01T00:00:00.123456+00:00',
      hasCompleteRow: true,
      bankName: bankName,
      bankAccountType: bankAccountType,
      bankAccountNumber: bankAccountNumber,
    );

Object _postgrest(String code, String message) =>
    PayrollEmployeePaymentStoreException(code: code, message: message);

/// Adaptador falso: guarda lo que el comando le pidió, para poder afirmar sobre
/// los **parámetros reales del RPC**, no sobre el texto del archivo.
class _FakeEmployeeStore implements PayrollEmployeePaymentStore {
  _FakeEmployeeStore({
    required this.row,
    this.writeError,
    this.writeRow,
    this.selectError,
    this.lineExpenseIds = const <String>[],
    this.paymentsByExpense = const <String, int>{},
    this.countError,
    this.lineReadError,
    this.reportedTotal,
  });

  Map<String, dynamic> row;
  final Object? writeError;
  final Map<String, dynamic>? writeRow;
  final Object? selectError;
  final List<String> lineExpenseIds;
  final Map<String, int> paymentsByExpense;
  final Object? countError;
  final Object? lineReadError;

  /// Total que el servidor declara, cuando difiere de las filas entregadas.
  final int? reportedTotal;

  Map<String, dynamic>? lastSetPaymentMethod;
  int readCalls = 0;
  int writeCalls = 0;
  int countCalls = 0;
  int? lastLimit;

  @override
  Future<List<Map<String, dynamic>>> readEmployee(String employeeId) async {
    if (selectError != null) throw selectError!;
    return <Map<String, dynamic>>[row];
  }

  @override
  Future<Map<String, dynamic>> setPaymentMethod({
    required String employeeId,
    required String expectedUpdatedAt,
    required String methodId,
    String? bankName,
    String? bankAccountType,
    String? bankAccountNumber,
  }) async {
    writeCalls++;
    lastSetPaymentMethod = <String, dynamic>{
      'employeeId': employeeId,
      'expectedUpdatedAt': expectedUpdatedAt,
      'methodId': methodId,
      'bankName': bankName,
      'bankAccountType': bankAccountType,
      'bankAccountNumber': bankAccountNumber,
    };
    if (writeError != null) throw writeError!;
    if (writeRow != null) return writeRow!;
    final methodCode = methodId == 'm-cash' ? 'cash' : 'transfer';
    return <String, dynamic>{
      ...row,
      'updated_at': '2026-08-01T00:00:01.654321+00:00',
      'preferred_payment_method_id': methodId,
      'preferred_payment_method': methodCode,
      if (methodCode == 'transfer') ...<String, dynamic>{
        'bank_name': bankName,
        'bank_account_type': bankAccountType,
        'bank_account_number': bankAccountNumber,
      },
    };
  }

  @override
  Future<PayrollLineExpenseIds> readLineExpenseIds(
    String employeeId, {
    required int limit,
  }) async {
    readCalls++;
    lastLimit = limit;
    if (lineReadError != null) throw lineReadError!;
    // El adaptador falso imita lo que hace el real: recorta al techo y dice si
    // el conjunto real lo superaba. `reportedTotal` permite simular además el
    // caso en que el servidor devuelve MENOS filas que su propio `count`.
    final total = reportedTotal ?? lineExpenseIds.length;
    final visible = lineExpenseIds.take(limit).toList(growable: false);
    return PayrollLineExpenseIds(
      ids: visible,
      exceededLimit: total > limit || visible.length < total,
    );
  }

  @override
  Future<int> countPaymentsForExpenses(List<String> expenseIds) async {
    readCalls++;
    countCalls++;
    if (countError != null) throw countError!;
    return expenseIds.fold<int>(
      0,
      (sum, id) => sum + (paymentsByExpense[id] ?? 0),
    );
  }
}

/// Monta la hoja con el tema del resolver: sin él no existe
/// `VinabikeThemeRoles` y los componentes compartidos se niegan a pintar.
Widget _host({
  required PayrollRecordedPaymentCount recordedPayments,
  bool selectTransfer = false,
  String? selectedMethodId,
  String? currentMethodName,
}) {
  const transfer = PayrollMethodOption(
      id: 'm-transfer', code: 'transfer', name: 'Transferencia');
  return MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.all.first,
      brightness: Brightness.light,
    ),
    home: Scaffold(
      body: Center(
        child: PayrollMethodSheet(
          employeeName: 'Vicente Díaz',
          options: const <PayrollMethodOption>[
            transfer,
            PayrollMethodOption(id: 'm-cash', code: 'cash', name: 'Efectivo'),
          ],
          authority: PayrollMethodAuthority.editable,
          returnLabel: 'Vuelves a la lista de la semana',
          confirmLabel: 'Guardar método',
          selectedMethodId:
              selectedMethodId ?? (selectTransfer ? transfer.id : null),
          currentMethodName: currentMethodName,
          recordedPayments: recordedPayments,
        ),
      ),
    ),
  );
}
