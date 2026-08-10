import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/payroll/payroll_draft_editor_adapter.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_generation_surface.dart';

void main() {
  group('payrollGenerationPreviewFromVoucher', () {
    test('preserves the weekly source, overtime and inclusion snapshot', () {
      final voucher = _voucher(
        totalHours: 11.5,
        totalAmount: 44500,
        employeeCount: 1,
        lines: <PayrollVoucherLine>[
          _line(
            employeeId: 'employee-lucas',
            employeeName: 'Lucas Pacheco',
            workedHours: 8,
            overtimeHours: 1.5,
            hourlyRate: 4000,
            overtimeRate: 6000,
            regularAmount: 32000,
            overtimeAmount: 9000,
            totalAmount: 41000,
          ),
          _line(
            employeeId: 'employee-rodrigo',
            employeeName: 'Rodrigo Guillermo Nieto',
            workedHours: 2,
            hourlyRate: 1750,
            regularAmount: 3500,
            totalAmount: 3500,
            isIncluded: false,
          ),
        ],
      );

      final preview = payrollGenerationPreviewFromVoucher(
        voucher: voucher,
        sourceSnapshotLabel: 'Borrador NOM-00042 · versión 7',
      );

      expect(
          preview.week, PayrollGenerationWeek.containing(voucher.periodStart));
      expect(preview.week.start, DateTime(2026, 7, 27));
      expect(preview.week.end, DateTime(2026, 8, 2));
      expect(preview.sourceSnapshotLabel, 'Borrador NOM-00042 · versión 7');
      expect(preview.totalAmount, 44500);
      expect(preview.workers, hasLength(2));

      final lucas = preview.workers.first;
      expect(lucas.workerId, 'employee-lucas');
      expect(lucas.name, 'Lucas Pacheco');
      expect(lucas.initials, 'LP');
      expect(lucas.hours, 8);
      expect(lucas.overtimeHours, 1.5);
      expect(lucas.rateAmount, 4000);
      expect(lucas.overtimeRateAmount, 6000);
      expect(lucas.totalAmount, 41000);
      expect(lucas.isIncluded, isTrue);

      final rodrigo = preview.workers.last;
      expect(rodrigo.initials, 'RG');
      expect(rodrigo.isIncluded, isFalse);
    });

    test('rejects a voucher whose period is not the exact civil week', () {
      final voucher = _voucher(periodEnd: DateTime(2026, 8, 1));

      expect(
        () => payrollGenerationPreviewFromVoucher(
          voucher: voucher,
          sourceSnapshotLabel: 'Borrador',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects duplicate voucher employee IDs', () {
      final voucher = _voucher(
        lines: <PayrollVoucherLine>[
          _line(employeeId: 'employee-lucas'),
          _line(employeeId: 'employee-lucas'),
        ],
      );

      expect(
        () => payrollGenerationPreviewFromVoucher(
          voucher: voucher,
          sourceSnapshotLabel: 'Borrador',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('duplicate employee ID'),
          ),
        ),
      );
    });
  });

  group('applyPayrollGenerationPreviewToVoucher', () {
    test(
      'recomputes edited amounts and totals while preserving persisted fields',
      () {
        const evidence = PayrollSettlementEvidence(
          id: 'evidence-1',
          voucherId: 'voucher-42',
          lineId: 'line-lucas',
          kind: PayrollSettlementEvidenceKind.payment,
          source: PayrollSettlementEvidenceSource.manual,
          amount: 200,
        );
        final evidenceList = <PayrollSettlementEvidence>[evidence];
        final originalLucas = _line(
          id: 'line-lucas',
          voucherId: 'voucher-42',
          employeeId: 'employee-lucas',
          employeeName: 'Lucas Pacheco',
          workedHours: 8,
          overtimeHours: 1,
          hourlyRate: 3500,
          overtimeRate: 5250,
          regularAmount: 28000,
          overtimeAmount: 5250,
          totalAmount: 33250,
          paymentMethod: 'transfer',
          expenseId: 'expense-lucas',
          salaryAccountId: 'salary-account-lucas',
          salaryAccountLabel: '6101-01 · Sueldos',
          paymentMethodId: 'method-transfer',
          paymentAccountId: 'account-bank',
          cashPaid: 150,
          advancesApplied: 50,
          settledAmount: 200,
          balance: 33050,
          settlementEvidence: evidenceList,
        );
        final originalRodrigo = _line(
          id: 'line-rodrigo',
          voucherId: 'voucher-42',
          employeeId: 'employee-rodrigo',
          employeeName: 'Rodrigo Nieto',
          workedHours: 5,
          hourlyRate: 4000,
          regularAmount: 20000,
          totalAmount: 20000,
          paymentMethod: 'cash',
          paymentMethodId: 'method-cash',
          paymentAccountId: 'account-cash',
          salaryAccountId: 'salary-account-rodrigo',
        );
        final voucher = _voucher(
          id: 'voucher-42',
          status: PayrollVoucherStatus.draft,
          reconciliationVersion: 7,
          totalHours: 14,
          totalAmount: 53250,
          employeeCount: 2,
          lines: <PayrollVoucherLine>[originalLucas, originalRodrigo],
        );
        final preview = PayrollGenerationPreview(
          week: PayrollGenerationWeek.containing(voucher.periodStart),
          sourceSnapshotLabel: 'Borrador NOM-00042 · versión 7',
          totalAmount: 38000,
          workers: const <PayrollGenerationWorkerLine>[
            // Deliberately reversed: identity, not row order, owns the edit.
            PayrollGenerationWorkerLine(
              workerId: 'employee-rodrigo',
              name: 'A name from UI must not overwrite persisted metadata',
              initials: 'RN',
              hours: 12,
              rateAmount: 5000,
              totalAmount: 60000,
              isIncluded: false,
            ),
            PayrollGenerationWorkerLine(
              workerId: 'employee-lucas',
              name: 'Lucas edited label',
              initials: 'LE',
              hours: 7.25,
              overtimeHours: 1.5,
              rateAmount: 4000,
              overtimeRateAmount: 6000,
              totalAmount: 38000,
            ),
          ],
        );

        final updated = applyPayrollGenerationPreviewToVoucher(
          voucher: voucher,
          preview: preview,
        );

        expect(updated.id, voucher.id);
        expect(updated.tenantId, voucher.tenantId);
        expect(updated.voucherNumber, voucher.voucherNumber);
        expect(updated.periodStart, voucher.periodStart);
        expect(updated.periodEnd, voucher.periodEnd);
        expect(updated.periodLabel, voucher.periodLabel);
        expect(updated.status, PayrollVoucherStatus.draft);
        expect(updated.paidAt, voucher.paidAt);
        expect(updated.paidBy, voucher.paidBy);
        expect(updated.notes, voucher.notes);
        expect(updated.createdBy, voucher.createdBy);
        expect(updated.createdAt, voucher.createdAt);
        expect(updated.updatedAt, voucher.updatedAt);
        expect(updated.reconciliationVersion, 7);
        expect(updated.totalHours, 8.75);
        expect(updated.totalAmount, 38000);
        expect(updated.employeeCount, 1);

        final lucas = updated.lines.first;
        expect(lucas.id, originalLucas.id);
        expect(lucas.voucherId, originalLucas.voucherId);
        expect(lucas.employeeId, originalLucas.employeeId);
        expect(lucas.employeeName, originalLucas.employeeName);
        expect(lucas.workedHours, 7.25);
        expect(lucas.overtimeHours, 1.5);
        expect(lucas.hourlyRate, 4000);
        expect(lucas.overtimeRate, 6000);
        expect(lucas.regularAmount, 29000);
        expect(lucas.overtimeAmount, 9000);
        expect(lucas.totalAmount, 38000);
        expect(lucas.balance, 37800);
        expect(lucas.paymentMethod, originalLucas.paymentMethod);
        expect(lucas.expenseId, originalLucas.expenseId);
        expect(lucas.salaryAccountId, originalLucas.salaryAccountId);
        expect(lucas.salaryAccountLabel, originalLucas.salaryAccountLabel);
        expect(lucas.paymentMethodId, originalLucas.paymentMethodId);
        expect(lucas.paymentAccountId, originalLucas.paymentAccountId);
        expect(lucas.cashPaid, originalLucas.cashPaid);
        expect(lucas.advancesApplied, originalLucas.advancesApplied);
        expect(lucas.settledAmount, originalLucas.settledAmount);
        expect(lucas.settlementEvidence, same(evidenceList));

        final rodrigo = updated.lines.last;
        expect(rodrigo.isIncluded, isFalse);
        expect(rodrigo.workedHours, 12);
        expect(rodrigo.hourlyRate, 5000);
        expect(rodrigo.regularAmount, 60000);
        expect(rodrigo.totalAmount, 60000);
        expect(rodrigo.paymentMethodId, originalRodrigo.paymentMethodId);
        expect(rodrigo.paymentAccountId, originalRodrigo.paymentAccountId);
        expect(rodrigo.salaryAccountId, originalRodrigo.salaryAccountId);
      },
    );

    test('rejects week and employee-set drift instead of saving another draft',
        () {
      final voucher = _voucher(
        lines: <PayrollVoucherLine>[
          _line(employeeId: 'employee-lucas'),
        ],
      );
      final wrongWeek = PayrollGenerationPreview(
        week: PayrollGenerationWeek.containing(DateTime(2026, 8, 3)),
        sourceSnapshotLabel: 'Otro borrador',
        totalAmount: 0,
        workers: const <PayrollGenerationWorkerLine>[
          PayrollGenerationWorkerLine(
            workerId: 'employee-lucas',
            name: 'Lucas Pacheco',
            initials: 'LP',
            hours: 0,
            rateAmount: 0,
            totalAmount: 0,
          ),
        ],
      );
      final wrongEmployees = PayrollGenerationPreview(
        week: PayrollGenerationWeek.containing(voucher.periodStart),
        sourceSnapshotLabel: 'Borrador',
        totalAmount: 0,
        workers: const <PayrollGenerationWorkerLine>[
          PayrollGenerationWorkerLine(
            workerId: 'employee-other',
            name: 'Otra Persona',
            initials: 'OP',
            hours: 0,
            rateAmount: 0,
            totalAmount: 0,
          ),
        ],
      );

      expect(
        () => applyPayrollGenerationPreviewToVoucher(
          voucher: voucher,
          preview: wrongWeek,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => applyPayrollGenerationPreviewToVoucher(
          voucher: voucher,
          preview: wrongEmployees,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('employees do not match'),
          ),
        ),
      );
    });

    test('rejects duplicate preview employee IDs and non-draft vouchers', () {
      final voucher = _voucher(
        lines: <PayrollVoucherLine>[
          _line(employeeId: 'employee-lucas'),
          _line(employeeId: 'employee-rodrigo'),
        ],
      );
      final duplicatePreview = PayrollGenerationPreview(
        week: PayrollGenerationWeek.containing(voucher.periodStart),
        sourceSnapshotLabel: 'Borrador',
        totalAmount: 0,
        workers: const <PayrollGenerationWorkerLine>[
          PayrollGenerationWorkerLine(
            workerId: 'employee-lucas',
            name: 'Lucas Pacheco',
            initials: 'LP',
            hours: 0,
            rateAmount: 0,
            totalAmount: 0,
          ),
          PayrollGenerationWorkerLine(
            workerId: 'employee-lucas',
            name: 'Lucas Duplicado',
            initials: 'LD',
            hours: 0,
            rateAmount: 0,
            totalAmount: 0,
          ),
        ],
      );

      expect(
        () => applyPayrollGenerationPreviewToVoucher(
          voucher: voucher,
          preview: duplicatePreview,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('duplicate employee ID'),
          ),
        ),
      );
      expect(
        () => applyPayrollGenerationPreviewToVoucher(
          voucher: _voucher(status: PayrollVoucherStatus.confirmed),
          preview: PayrollGenerationPreview(
            week: PayrollGenerationWeek.containing(voucher.periodStart),
            sourceSnapshotLabel: 'Confirmada',
            totalAmount: 0,
            workers: const <PayrollGenerationWorkerLine>[],
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}

PayrollVoucher _voucher({
  String? id = 'voucher-42',
  DateTime? periodStart,
  DateTime? periodEnd,
  PayrollVoucherStatus status = PayrollVoucherStatus.draft,
  int reconciliationVersion = 7,
  double totalHours = 0,
  double totalAmount = 0,
  int employeeCount = 0,
  List<PayrollVoucherLine> lines = const <PayrollVoucherLine>[],
}) {
  return PayrollVoucher(
    id: id,
    tenantId: 'tenant-1',
    voucherNumber: 'NOM-00042',
    periodStart: periodStart ?? DateTime(2026, 7, 27, 14),
    periodEnd: periodEnd ?? DateTime(2026, 8, 2, 23, 59),
    periodLabel: 'Semana 31',
    totalHours: totalHours,
    totalAmount: totalAmount,
    employeeCount: employeeCount,
    status: status,
    paidAt: DateTime(2026, 8, 3, 12),
    paidBy: 'actor-1',
    notes: 'Nota preservada',
    createdBy: 'creator-1',
    createdAt: DateTime(2026, 8, 2, 9),
    updatedAt: DateTime(2026, 8, 2, 10),
    reconciliationVersion: reconciliationVersion,
    lines: lines,
  );
}

PayrollVoucherLine _line({
  String? id = 'line-1',
  String voucherId = 'voucher-42',
  String employeeId = 'employee-1',
  String employeeName = 'Persona Uno',
  double workedHours = 0,
  double overtimeHours = 0,
  double hourlyRate = 0,
  double overtimeRate = 0,
  double regularAmount = 0,
  double overtimeAmount = 0,
  double totalAmount = 0,
  String paymentMethod = 'transfer',
  bool isIncluded = true,
  String? expenseId,
  String? salaryAccountId,
  String? salaryAccountLabel,
  String? paymentMethodId,
  String? paymentAccountId,
  double cashPaid = 0,
  double advancesApplied = 0,
  double settledAmount = 0,
  double? balance,
  List<PayrollSettlementEvidence> settlementEvidence =
      const <PayrollSettlementEvidence>[],
}) {
  return PayrollVoucherLine(
    id: id,
    voucherId: voucherId,
    employeeId: employeeId,
    employeeName: employeeName,
    workedHours: workedHours,
    overtimeHours: overtimeHours,
    hourlyRate: hourlyRate,
    overtimeRate: overtimeRate,
    regularAmount: regularAmount,
    overtimeAmount: overtimeAmount,
    totalAmount: totalAmount,
    paymentMethod: paymentMethod,
    isIncluded: isIncluded,
    expenseId: expenseId,
    salaryAccountId: salaryAccountId,
    salaryAccountLabel: salaryAccountLabel,
    paymentMethodId: paymentMethodId,
    paymentAccountId: paymentAccountId,
    cashPaid: cashPaid,
    advancesApplied: advancesApplied,
    settledAmount: settledAmount,
    balance: balance,
    settlementEvidence: settlementEvidence,
  );
}
