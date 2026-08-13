import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';
import 'package:go_router/go_router.dart';
// ignore: implementation_imports
import 'package:google_fonts/src/google_fonts_base.dart' as gf_base;
import 'package:http/http.dart' as http;
import 'package:vinabike_erp/modules/hr/models/payroll_statement_reconciliation.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/pages/payroll_reconciliation_page.dart';
import 'package:vinabike_erp/modules/hr/payroll/payment_workspace/payroll_payment_workspace_controller.dart';
import 'package:vinabike_erp/modules/hr/payroll/payment_workspace/payroll_payment_workspace_models.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_reconciliation_surface.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_transfer_review_surface.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_reconciliation_service.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_statement_extraction_service.dart';
import 'package:vinabike_erp/modules/hr/widgets/payroll_money_bar.dart';
import 'package:vinabike_erp/modules/hr/widgets/payroll_reconciliation_row.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_money_text.dart';

/// Behaviour tests for the staged bank-statement reconciliation.
///
/// Fixtures are entirely synthetic: invented beneficiaries, invented ids and
/// round amounts. No real statement text, account number or person appears
/// here, and no file is ever read from disk.
void main() {
  const commitAndApplyLabel = 'Confirmar 1 semana y aplicar conciliación';

  test('web consumes PlatformFile bytes without requiring an unavailable path',
      () {
    final bytes = Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]);
    final file = PlatformFile(
      name: 'cartola.pdf',
      bytes: bytes,
      size: bytes.length,
    );

    final picked = payrollPickedStatementFromPlatformFile(file, isWeb: true);

    expect(picked, isNotNull);
    expect(picked!.filename, 'cartola.pdf');
    expect(picked.bytes, same(bytes));
    expect(picked.sourcePath, isNull);
  });

  test('native file conversion preserves the picker path', () {
    final bytes = Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]);
    final file = PlatformFile(
      name: 'cartola.pdf',
      path: '/tmp/cartola.pdf',
      bytes: bytes,
      size: bytes.length,
    );

    final picked = payrollPickedStatementFromPlatformFile(file, isWeb: false);

    expect(picked, isNotNull);
    expect(picked!.sourcePath, '/tmp/cartola.pdf');
  });

  test('capture capability matrix is explicit per supported platform', () {
    final matrix = <String, PayrollStatementCaptureCapabilities>{
      'android': payrollStatementCaptureCapabilities(
        isWeb: false,
        platform: TargetPlatform.android,
        cloudImageOcrSupported: true,
      ),
      'ios': payrollStatementCaptureCapabilities(
        isWeb: false,
        platform: TargetPlatform.iOS,
        cloudImageOcrSupported: true,
      ),
      'macos': payrollStatementCaptureCapabilities(
        isWeb: false,
        platform: TargetPlatform.macOS,
        cloudImageOcrSupported: true,
      ),
      'web': payrollStatementCaptureCapabilities(
        isWeb: true,
        platform: TargetPlatform.linux,
        cloudImageOcrSupported: true,
      ),
    };

    for (final platform in const <String>['android', 'ios']) {
      expect(matrix[platform]!.supportsImages, isTrue, reason: platform);
      expect(matrix[platform]!.supportsGallery, isTrue, reason: platform);
      expect(matrix[platform]!.supportsCamera, isTrue, reason: platform);
    }
    expect(matrix['macos']!.supportsImages, isTrue);
    expect(matrix['macos']!.supportsGallery, isTrue);
    expect(matrix['macos']!.supportsCamera, isFalse);
    expect(matrix['web']!.supportsImages, isTrue);
    expect(matrix['web']!.supportsGallery, isTrue);
    expect(matrix['web']!.supportsCamera, isFalse);
  });

  PayrollStatementRow statementRow({
    required int rowNumber,
    required String description,
    required int debit,
    PayrollCivilDate? date,
    String? beneficiaryObserved,
  }) {
    return PayrollStatementRow(
      bookingDate: date ?? const PayrollCivilDate(2026, 7, 28),
      description: description,
      beneficiaryObserved: beneficiaryObserved,
      documentNumber: null,
      debitAmountClp: debit,
      creditAmountClp: null,
      balanceAmountClp: null,
      direction: PayrollStatementMovementDirection.outgoing,
      evidence: PayrollStatementRowEvidence(
        sourceRowNumber: rowNumber,
        startPageNumber: 1,
        startLineNumber: rowNumber,
        endPageNumber: 1,
        endLineNumber: rowNumber,
      ),
    );
  }

  PayrollReconciliationVoucherLine voucherLine({
    required String lineId,
    required String employeeId,
    required int pending,
    PayrollReconciliationPaymentMethod method =
        PayrollReconciliationPaymentMethod.transfer,
    String? methodId = 'method-transfer',
    String voucherId = 'voucher-1',
    PayrollCivilDate periodStart = const PayrollCivilDate(2026, 7, 21),
    PayrollCivilDate periodEnd = const PayrollCivilDate(2026, 7, 27),
  }) {
    return PayrollReconciliationVoucherLine(
      lineId: lineId,
      voucherId: voucherId,
      employeeId: employeeId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      pendingAmountClp: pending,
      paymentMethod: method,
      paymentMethodId: methodId,
    );
  }

  PayrollReconciliationEmployee employee({
    required String id,
    required String name,
    PayrollReconciliationPaymentMethod method =
        PayrollReconciliationPaymentMethod.transfer,
  }) {
    return PayrollReconciliationEmployee(
      employeeId: id,
      displayName: name,
      paymentMethod: method,
    );
  }

  EmployeeAdvance cashAdvance({
    required String id,
    required double amount,
    required DateTime paidAt,
  }) {
    return EmployeeAdvance(
      id: id,
      employeeId: 'employee-cash',
      amount: amount,
      amountApplied: 0,
      paidAt: paidAt,
      status: 'open',
      paymentMethodId: 'method-cash',
      paymentAccountId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      reference: 'ANTICIPO-$id',
    );
  }

  PayrollReconciliationCandidate candidate({
    required PayrollStatementRow row,
    required PayrollReconciliationVoucherLine line,
    required int variance,
    bool isEligible = true,
  }) {
    return PayrollReconciliationCandidate(
      statementRow: row,
      voucherLine: line,
      beneficiaryMatchKind: PayrollBeneficiaryMatchKind.primaryName,
      normalizedMatchedBeneficiary: 'ana rivas',
      isEligible: isEligible,
      amountVarianceClp: variance,
      allowedToleranceClp: 500,
      daysAfterPeriodEnd: 1,
      score: 80,
      confidence: PayrollMatchConfidence.high,
      reasons: const [
        PayrollCandidateReason.outgoingMovement,
        PayrollCandidateReason.primaryNameMatched,
        PayrollCandidateReason.dateWithinWindow,
      ],
    );
  }

  PayrollStatementPreparedDraft draft({
    int variance = 0,
    bool withCashEmployee = false,
    bool withUnmatchedMovement = false,
    bool withPayrollNamedUnmatchedMovement = false,
    bool withForeignNamedMovement = false,
    bool withSettledWorkerNamedMovement = false,
    bool withIncompleteEvidence = false,
    bool withAlternateTransferLine = false,
    // Una obligación real de OTRA semana, sin ningún movimiento en la cartola.
    bool withUntouchedWeek = false,
    // La misma fila bancaria fue evaluada contra dos semanas de la misma
    // persona, pero el matcher se la asignó sólo a la más antigua. Es el caso
    // real que permite comprobar que la UI no pinte el mismo dinero dos veces.
    bool withCrossWeekEvaluatedCandidate = false,
    int? partialBankDebitClp,
    Set<String> missingCanonicalMethod = const {},
    List<EmployeeAdvance> openAdvances = const [],
    bool alreadyResolved = false,
    PayrollCivilDate? documentDate,
    PayrollVoucherStatus voucherStatus = PayrollVoucherStatus.draft,
    // Filas extra para fixtures adversariales, p. ej. más filas problemáticas
    // que el antiguo tope de visibles.
    List<PayrollStatementRow> extraRows = const <PayrollStatementRow>[],
    // Períodos extra de nóminas abiertas, para probar orden y ancho del panel.
    // Se insertan en el orden que se pase: el fixture NO los ordena.
    List<DateTime> extraOpenPayrollStarts = const <DateTime>[],
  }) {
    final matchedRow = statementRow(
      rowNumber: 1,
      description: 'TRANSFERENCIA A ANA RIVAS',
      beneficiaryObserved: 'Persona Depósito',
      debit: partialBankDebitClp ?? 450000 + variance,
    );
    final strayRow = statementRow(
      rowNumber: 2,
      description: withPayrollNamedUnmatchedMovement
          ? 'TRANSFERENCIA A ANA RIVAS'
          : withForeignNamedMovement
              ? 'PAGO PROVEEDOR SODIMAC'
              : withSettledWorkerNamedMovement
                  ? 'TRANSFERENCIA A BEA SOTO'
                  : 'PAGO PROVEEDOR GENERICO',
      beneficiaryObserved: withPayrollNamedUnmatchedMovement
          ? 'Ana Rivas'
          : withForeignNamedMovement
              ? 'Sodimac SA'
              : withSettledWorkerNamedMovement
                  ? 'Bea Soto'
                  : null,
      debit: 22000,
    );
    final incompleteRow = PayrollStatementRow(
      bookingDate: null,
      description: 'TRANSFERENCIA OCR CORTADA',
      documentNumber: 'OCR-003',
      debitAmountClp: 22000,
      creditAmountClp: null,
      balanceAmountClp: null,
      direction: PayrollStatementMovementDirection.outgoing,
      evidence: const PayrollStatementRowEvidence(
        sourceRowNumber: 3,
        startPageNumber: 1,
        startLineNumber: 3,
        endPageNumber: 1,
        endLineNumber: 3,
      ),
      parseWarningCodes: const ['ocr_missing_date'],
    );
    final untouchedWeekLine = voucherLine(
      lineId: 'line-ana-semana-previa',
      employeeId: 'employee-ana',
      pending: 120000,
      voucherId: 'voucher-previo',
      periodStart: const PayrollCivilDate(2026, 7, 14),
      periodEnd: const PayrollCivilDate(2026, 7, 20),
    );
    final crossWeekLine = voucherLine(
      lineId: 'line-ana-semana-siguiente',
      employeeId: 'employee-ana',
      pending: 450000,
      voucherId: 'voucher-siguiente',
      periodStart: const PayrollCivilDate(2026, 7, 28),
      periodEnd: const PayrollCivilDate(2026, 8, 3),
    );
    final anaLine = voucherLine(
      lineId: 'line-ana',
      employeeId: 'employee-ana',
      pending: 450000,
    );
    final alternateLine = voucherLine(
      lineId: 'line-bea',
      employeeId: 'employee-bea',
      pending: 450000,
    );
    final cashLine = voucherLine(
      lineId: 'line-cash',
      employeeId: 'employee-cash',
      pending: 120000,
      method: PayrollReconciliationPaymentMethod.cash,
      methodId: 'method-cash',
    );

    final includeStrayRow = withUnmatchedMovement ||
        withPayrollNamedUnmatchedMovement ||
        withForeignNamedMovement ||
        withSettledWorkerNamedMovement;
    final rows = <PayrollStatementRow>[
      matchedRow,
      if (includeStrayRow) strayRow,
      if (withIncompleteEvidence) incompleteRow,
    ];

    final lineResults = <PayrollReconciliationLineResult>[
      PayrollReconciliationLineResult(
        voucherLine: anaLine,
        employee: employee(id: 'employee-ana', name: 'Ana Rivas'),
        status: alreadyResolved || partialBankDebitClp != null
            ? PayrollLineMatchStatus.unmatched
            : PayrollLineMatchStatus.suggested,
        evaluatedCandidates: alreadyResolved
            ? const []
            : [
                candidate(
                  row: matchedRow,
                  line: anaLine,
                  variance: (partialBankDebitClp ?? 450000 + variance) - 450000,
                  isEligible: partialBankDebitClp == null,
                ),
                if (withPayrollNamedUnmatchedMovement)
                  candidate(
                    row: strayRow,
                    line: anaLine,
                    variance: 22000 - 450000,
                    isEligible: false,
                  ),
              ],
        proposedMatch: alreadyResolved || partialBankDebitClp != null
            ? null
            : candidate(row: matchedRow, line: anaLine, variance: variance),
        reasons: alreadyResolved || partialBankDebitClp != null
            ? const [PayrollLineMatchReason.noEligibleTransaction]
            : const [PayrollLineMatchReason.uniqueCandidate],
      ),
      if (withUntouchedWeek)
        PayrollReconciliationLineResult(
          voucherLine: untouchedWeekLine,
          employee: employee(id: 'employee-ana', name: 'Ana Rivas'),
          status: PayrollLineMatchStatus.unmatched,
          evaluatedCandidates: const [],
          proposedMatch: null,
          reasons: const [PayrollLineMatchReason.noEligibleTransaction],
        ),
      if (withCrossWeekEvaluatedCandidate)
        PayrollReconciliationLineResult(
          voucherLine: crossWeekLine,
          employee: employee(id: 'employee-ana', name: 'Ana Rivas'),
          status: PayrollLineMatchStatus.unmatched,
          evaluatedCandidates: [
            candidate(
              row: matchedRow,
              line: crossWeekLine,
              variance: variance,
            ),
          ],
          proposedMatch: null,
          reasons: const [
            PayrollLineMatchReason.transactionsTakenByOlderWeeks,
          ],
        ),
      if (withAlternateTransferLine)
        PayrollReconciliationLineResult(
          voucherLine: alternateLine,
          employee: employee(id: 'employee-bea', name: 'Bea Soto'),
          status: PayrollLineMatchStatus.unmatched,
          evaluatedCandidates: const [],
          proposedMatch: null,
          reasons: const [PayrollLineMatchReason.noBeneficiaryMatch],
        ),
      if (withCashEmployee)
        PayrollReconciliationLineResult(
          voucherLine: cashLine,
          employee: employee(
            id: 'employee-cash',
            name: 'Rosa Díaz',
            method: PayrollReconciliationPaymentMethod.cash,
          ),
          status: PayrollLineMatchStatus.ineligible,
          evaluatedCandidates: const [],
          proposedMatch: null,
          reasons: const [PayrollLineMatchReason.paymentMethodIsCash],
        ),
    ];

    return PayrollStatementPreparedDraft(
      operationKey: 'operation-key-1',
      filename: 'cartola-sintetica.pdf',
      extraction: const PayrollStatementExtractionResult(
        fileSha256: 'sha-sintetico',
        inputKind: PayrollStatementInputKind.pdf,
        method: PayrollStatementExtractionMethod.embeddedPdfText,
        pages: [PayrollStatementPageText(pageNumber: 1, text: 'texto')],
      ),
      parseResult: PayrollBankStatementParseResult(
        rows: <PayrollStatementRow>[...rows, ...extraRows],
      ),
      reconciliation: PayrollStatementReconciliationResult(
        statementRows: alreadyResolved
            ? rows.where((row) => row != matchedRow).toList()
            : rows,
        lineResults: lineResults,
        foreignOutgoingSourceRowIds: {
          if (withUnmatchedMovement || withForeignNamedMovement)
            strayRow.sourceRowId,
        },
      ),
      vouchersById: {
        // Insertadas ANTES de la principal y deliberadamente desordenadas: si
        // la pantalla recorriera el `Map` tal cual, saldrían así.
        for (final start in extraOpenPayrollStarts)
          'voucher-${start.month}-${start.day}': PayrollVoucher(
            id: 'voucher-${start.month}-${start.day}',
            tenantId: 'tenant-1',
            voucherNumber: 'NOM-${start.month}${start.day}',
            periodStart: start,
            periodEnd: start.add(const Duration(days: 6)),
            totalAmount: 100000,
            status: PayrollVoucherStatus.confirmed,
            createdAt: start,
            updatedAt: start,
            lines: const <PayrollVoucherLine>[],
          ),
        if (withUntouchedWeek)
          'voucher-previo': PayrollVoucher(
            id: 'voucher-previo',
            tenantId: 'tenant-1',
            voucherNumber: 'NOM-00000',
            periodStart: DateTime(2026, 7, 14),
            periodEnd: DateTime(2026, 7, 20),
            totalAmount: 120000,
            status: PayrollVoucherStatus.draft,
            createdAt: DateTime(2026, 7, 20),
            updatedAt: DateTime(2026, 7, 20),
            lines: const <PayrollVoucherLine>[
              PayrollVoucherLine(
                id: 'line-ana-semana-previa',
                voucherId: 'voucher-previo',
                employeeId: 'employee-ana',
                employeeName: 'Ana Rivas',
                totalAmount: 120000,
              ),
            ],
          ),
        if (withCrossWeekEvaluatedCandidate)
          'voucher-siguiente': PayrollVoucher(
            id: 'voucher-siguiente',
            tenantId: 'tenant-1',
            voucherNumber: 'NOM-00002',
            periodStart: DateTime(2026, 7, 28),
            periodEnd: DateTime(2026, 8, 3),
            totalAmount: 450000,
            status: PayrollVoucherStatus.draft,
            createdAt: DateTime(2026, 8, 3),
            updatedAt: DateTime(2026, 8, 3),
            lines: const <PayrollVoucherLine>[
              PayrollVoucherLine(
                id: 'line-ana-semana-siguiente',
                voucherId: 'voucher-siguiente',
                employeeId: 'employee-ana',
                employeeName: 'Ana Rivas',
                totalAmount: 450000,
              ),
            ],
          ),
        'voucher-1': PayrollVoucher(
          id: 'voucher-1',
          tenantId: 'tenant-1',
          voucherNumber: 'NOM-00001',
          periodStart: DateTime(2026, 7, 21),
          periodEnd: DateTime(2026, 7, 27),
          totalAmount: 570000,
          status: voucherStatus,
          createdAt: DateTime(2026, 7, 27),
          updatedAt: DateTime(2026, 7, 27),
          lines: [
            const PayrollVoucherLine(
              id: 'line-ana',
              voucherId: 'voucher-1',
              employeeId: 'employee-ana',
              employeeName: 'Ana Rivas',
              totalAmount: 450000,
            ),
            if (withCashEmployee)
              const PayrollVoucherLine(
                id: 'line-cash',
                voucherId: 'voucher-1',
                employeeId: 'employee-cash',
                employeeName: 'Rosa Díaz',
                totalAmount: 120000,
              ),
            if (withAlternateTransferLine)
              const PayrollVoucherLine(
                id: 'line-bea',
                voucherId: 'voucher-1',
                employeeId: 'employee-bea',
                employeeName: 'Bea Soto',
                totalAmount: 450000,
              ),
          ],
        ),
      },
      employeeRowsById: const {
        'employee-ana': {
          'preferred_payment_method_id': 'method-transfer',
          'first_name': 'Ana',
          'last_name': 'Rivas',
        },
        'employee-cash': {
          'preferred_payment_method_id': 'method-cash',
          'first_name': 'Rosa',
          'last_name': 'Díaz',
        },
        'employee-bea': {
          'preferred_payment_method_id': 'method-transfer',
          'first_name': 'Bea',
          'last_name': 'Soto',
        },
      },
      paymentMethods: const [
        {
          'id': 'method-transfer',
          'code': 'transfer',
          'name': 'Transferencia',
          'account_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'account_code': '110101',
          'account_name': 'Banco principal',
          'is_active': true,
        },
        {
          'id': 'method-cash',
          'code': 'cash',
          'name': 'Efectivo',
          'account_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
          'is_active': true,
        },
      ],
      openAdvances: openAdvances,
      missingCanonicalPaymentMethodEmployeeIds: missingCanonicalMethod,
      rowFingerprintsBySourceRowId: const {},
      expectedVoucherVersionsById: {
        'voucher-1': 0,
        if (withCrossWeekEvaluatedCandidate) 'voucher-siguiente': 0,
      },
      accountFingerprint:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      priorDecisionIdsBySourceRowId:
          alreadyResolved ? const {'p1-l1-r1': 'prior-decision-1'} : const {},
      statementYear: 2026,
      documentDate: documentDate,
    );
  }

  ({
    PayrollReconciliationActions actions,
    List<String> calls,
    List<String> applyKeys,
    List<List<PayrollStatementReviewDecision>> decisions,
    List<Set<String>> authorizedDraftVoucherIds,
  }) recorder({
    bool failFirstApply = false,
    bool replay = false,
    bool cameraCaptureSupported = false,
    PayrollStatementPreparedDraft? prepared,
    PayrollStatementPreparedDraft? refreshed,
    Map<String, dynamic> applyRaw = const <String, dynamic>{},
    bool? versionedCommandsProbe,
  }) {
    final calls = <String>[];
    final applyKeys = <String>[];
    final capturedDecisions = <List<PayrollStatementReviewDecision>>[];
    final capturedAuthorizations = <Set<String>>[];
    var applyAttempts = 0;

    final actions = PayrollReconciliationActions(
      isImageOcrSupported: true,
      isCameraCaptureSupported: cameraCaptureSupported,
      versionedCommandsProbe:
          versionedCommandsProbe == null ? null : () => versionedCommandsProbe,
      prepare: ({required bytes, required filename, sourcePath}) async {
        calls.add('prepare');
        return prepared ?? draft();
      },
      refresh: refreshed == null
          ? null
          : (current) async {
              calls.add('refresh');
              return refreshed;
            },
      createImport: (draftValue, {required erpAccountId}) async {
        calls.add('createImport');
        return PayrollStatementImportReceipt(
          importId: 'import-1',
          operationKey: draftValue.operationKey,
          wasReplay: false,
          erpAccountId: erpAccountId,
          rowIdsBySourceRowId: const {},
          rowFingerprintsBySourceRowId: const {},
          raw: const {},
        );
      },
      learnBeneficiaryAlias: ({
        required employeeId,
        required alias,
      }) async {
        calls.add('learnBeneficiaryAlias:$employeeId:$alias');
        return PayrollBeneficiaryAliasLearnReceipt(
          wasCreated: true,
          employeeId: employeeId,
          alias: alias,
          normalizedAlias: normalizePayrollReconciliationText(alias),
        );
      },
      apply: ({
        required draft,
        required importReceipt,
        required decisions,
        required authorizedDraftVoucherIds,
        operationKey,
      }) async {
        calls.add('apply');
        applyKeys.add(operationKey ?? '');
        capturedDecisions.add(decisions);
        capturedAuthorizations.add(
          Set<String>.unmodifiable(authorizedDraftVoucherIds),
        );
        applyAttempts++;
        if (failFirstApply && applyAttempts == 1) {
          throw const PayrollReconciliationServiceException(
            'red caída',
            recoveryAction: PayrollReconciliationRecoveryAction.retry,
            canRetrySameOperation: true,
          );
        }
        return PayrollStatementApplyReceipt(
          importId: importReceipt.importId,
          operationKey: operationKey ?? '',
          wasReplay: replay,
          raw: <String, dynamic>{
            ...applyRaw,
            'committed_voucher_ids':
                authorizedDraftVoucherIds.toList(growable: false)..sort(),
          },
        );
      },
    );

    return (
      actions: actions,
      calls: calls,
      applyKeys: applyKeys,
      decisions: capturedDecisions,
      authorizedDraftVoucherIds: capturedAuthorizations,
    );
  }

  PayrollStatementPicker picker() {
    return () async => PayrollPickedStatement(
          bytes: Uint8List.fromList(const [1, 2, 3]),
          filename: 'cartola-sintetica.pdf',
        );
  }

  Future<GoRouter> pump(
    WidgetTester tester, {
    required PayrollReconciliationActions actions,
    Size size = const Size(1440, 900),
    Brightness brightness = Brightness.light,
    PayrollStatementPicker? pickFile,
    PayrollStatementPicker? pickCamera,
    PayrollStatementPicker? pickGallery,
    Future<void> Function(String employeeId)? onConfigureEmployeePaymentMethod,
    Future<void> Function(PayrollPaymentWorkspaceRequest request)?
        onPaymentHandoff,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.view.viewInsets = FakeViewPadding.zero);

    final router = GoRouter(
      initialLocation: '/hr/payroll/reconcile',
      routes: [
        GoRoute(
          path: '/hr/payroll',
          builder: (context, state) =>
              const Scaffold(body: Text('lista de nómina')),
        ),
        GoRoute(
          path: '/hr/payroll/reconcile',
          builder: (context, state) => Scaffold(
            body: PayrollReconciliationPage(
              actions: actions,
              pickFile: pickFile ?? picker(),
              pickCamera: pickCamera,
              pickGallery: pickGallery,
              onConfigureEmployeePaymentMethod:
                  onConfigureEmployeePaymentMethod,
              onPaymentHandoff: onPaymentHandoff,
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        key: UniqueKey(),
        // Sin el tema del resolver no existe `VinabikeThemeRoles` y el arnés no
        // representa a la app — el mismo hueco que ya se cerró en otros tres
        // arneses el 2026-08-01. Además, sin tema las capturas de evidencia no
        // mostrarían el aspecto real.
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: brightness,
        ),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> loadStatement(WidgetTester tester) async {
    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();
    // t5: tras preparar, la app aterriza en la evidencia de extracción; la
    // mayoría de los flujos siguen hacia la revisión.
    final toReview =
        find.widgetWithText(PayrollPrimaryAction, 'Ver pagos encontrados');
    if (toReview.evaluate().isNotEmpty &&
        tester.widget<PayrollPrimaryAction>(toReview.first).onPressed != null) {
      await tester.tap(toReview.first);
      await tester.pumpAndSettle();
    }
  }

  Future<void> goToStage(WidgetTester tester, String stage) async {
    const labels = <String>[
      'Cargar cartola',
      'Lectura',
      'Preparar pagos',
    ];
    final index = labels.indexOf(stage);
    expect(
      index,
      greaterThanOrEqualTo(0),
      reason: 'Unknown reconciliation stage: $stage',
    );
    await tester.tap(
      find.byKey(ValueKey<String>('reconciliation-step-${index + 1}')),
    );
    await tester.pumpAndSettle();
  }

  bool stageIsEnabled(WidgetTester tester, int stageNumber) {
    return tester
            .widget<InkWell>(
              find.byKey(
                ValueKey<String>('reconciliation-step-$stageNumber'),
              ),
            )
            .onTap !=
        null;
  }

  PayrollPrimaryAction primaryAction(
    WidgetTester tester,
    String label,
  ) {
    return tester.widget<PayrollPrimaryAction>(
      find.widgetWithText(PayrollPrimaryAction, label),
    );
  }

  /// Trae un widget a la vista aunque la lista de la etapa lo virtualice.
  ///
  /// **`ensureVisible` no basta.** La etapa tiene una barra de dinero fija al
  /// pie: un objetivo «visible» puede quedar justo debajo de ella, y entonces
  /// el `tap` avisa que no encontró nada en el punto y **no entrega el evento**
  /// —la prueba sigue creyendo que tocó—. Se desplaza lo justo para sacarlo de
  /// debajo de la barra. Costó una ronda el 2026-08-10.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();

    const footerSafeArea = 150.0;
    final viewportHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final overlap =
        tester.getCenter(finder.first).dy - (viewportHeight - footerSafeArea);
    if (overlap > 0) {
      final list = find.byType(ListView).first;
      await tester.dragFrom(
        tester.getTopLeft(list) + const Offset(12, 40),
        Offset(0, -overlap - 20),
      );
      await tester.pumpAndSettle();
    }
  }

  /// Suspende la red de `google_fonts` **sólo dentro del generador opt-in**.
  ///
  /// **El problema, con su mecánica exacta.** `GoogleFonts.textStyle` lanza la
  /// carga de la fuente como un future *fire-and-forget* y le hace `.then(...)`
  /// sin `onError`, así que si ese future **rechaza**, el error llega a la zona
  /// como asíncrono no capturado y el binding lo convierte en fallo de la
  /// prueba. En `flutter_test` toda petición HTTP vuelve 400, de modo que
  /// rechaza siempre. Y **no basta con que falle una vez**: el `catch` de
  /// `loadFontIfNecessary` hace `_loadedFonts.remove(...)` antes de `rethrow`
  /// (google_fonts 6.3.2, `google_fonts_base.dart`), o sea **borra la marca de
  /// carga y vuelve a intentarlo en la siguiente resolución de estilo**. Por eso
  /// no existe drenaje ni precalentamiento que lo silencie.
  ///
  /// **Por qué sólo estalla al capturar.** El rechazo se materializa cuando el
  /// future completa, y eso exige el event loop real: fuera de `runAsync` la
  /// zona falsa de `flutter_test` nunca lo deja completar. La captura es el
  /// único punto que necesita `runAsync` —el encoder de `toImage`/`toByteData`
  /// corre ahí—, así que es justo ahí donde aterrizaban los rechazos.
  ///
  /// **La sustitución.** Se cambia el cliente HTTP del paquete por uno cuyo
  /// `send` devuelve un `Completer` que nunca se completa: las cargas quedan
  /// **pendientes**, no rechazadas, así que no hay error que contaminar. Un
  /// `Completer` pelado no tiene timer ni I/O, de modo que no mantiene vivo el
  /// isolate ni deja temporizadores al cerrar.
  ///
  /// Es una **sustitución de red de prueba**, no un comportamiento de
  /// producción: se restaura el cliente original y se limpia la caché al salir.
  ///
  /// **No cambia lo que se ve.** Las fuentes ya no se cargaban antes —fallaban
  /// en vez de quedar pendientes—, y está comprobado: las seis capturas del
  /// paso 4 salen **byte a byte idénticas** a las de antes de esta sustitución.
  /// El texto sale como **bloques**, los glifos de la tipografía de prueba del
  /// arnés: estas capturas prueban **composición** y **no son evidencia de
  /// tipografía**. Cuál familia se dibuja no se midió y no se afirma.
  void suspendGoogleFontsNetwork() {
    final original = gf_base.httpClient;
    gf_base.clearCache();
    gf_base.httpClient = _NeverCompletingClient();
    addTearDown(() {
      gf_base.httpClient = original;
      gf_base.clearCache();
    });
  }

  testWidgets(
      'OCR prepara pagos por semana y entrega evidencia sin aplicar dinero',
      (tester) async {
    final harness = recorder();
    PayrollPaymentWorkspaceRequest? handoff;
    await pump(
      tester,
      actions: harness.actions,
      onPaymentHandoff: (request) async => handoff = request,
    );

    await loadStatement(tester);

    expect(find.text('Nóminas abiertas'), findsOneWidget);
    expect(find.textContaining('Semana 30'), findsOneWidget);
    expect(find.text('Ana Rivas'), findsOneWidget);
    expect(find.text('Otros egresos de la cartola'), findsOneWidget);
    expect(find.text('Cuenta ERP de esta cartola'), findsNothing);
    expect(find.text('Aplicar conciliación'), findsNothing);

    final barriersBefore = find.byType(ModalBarrier).evaluate().length;
    final continueAction = primaryAction(tester, 'Continuar con 1 pago');
    expect(continueAction.onPressed, isNotNull);
    continueAction.onPressed!.call();
    await tester.pumpAndSettle();

    expect(handoff, isNotNull);
    expect(handoff!.mode, PayrollPaymentWorkspaceMode.batch);
    expect(handoff!.targets, hasLength(1));
    expect(handoff!.targets.single.employeeName, 'Ana Rivas');
    expect(
      handoff!.targets.single.ocrCandidates.single.selectedForPrefill,
      isTrue,
    );
    expect(
      find.byKey(
        const ValueKey<String>('payroll-payment-batch-workspace'),
      ),
      findsOneWidget,
      reason: 'El paso final vive dentro de Importar cartola.',
    );
    expect(find.text('Completar pagos'), findsWidgets);
    expect(
      find.byType(ModalBarrier).evaluate().length,
      barriersBefore,
      reason: 'OCR no abre el panel lateral de pago individual.',
    );
    expect(harness.calls, isNot(contains('createImport')));
    expect(harness.calls, isNot(contains('apply')));
  });

  testWidgets(
      'paso final incluye todas las obligaciones abiertas y sólo precarga calces directos',
      (tester) async {
    final harness = recorder(
      prepared: draft(
        withUntouchedWeek: true,
        withAlternateTransferLine: true,
        withCashEmployee: true,
      ),
    );
    PayrollPaymentWorkspaceRequest? handoff;
    await pump(
      tester,
      actions: harness.actions,
      size: const Size(1440, 1000),
      onPaymentHandoff: (request) async => handoff = request,
    );

    await loadStatement(tester);

    final continueAction = primaryAction(tester, 'Continuar con 4 pagos');
    expect(continueAction.onPressed, isNotNull);
    continueAction.onPressed!.call();
    await tester.pumpAndSettle();

    final request = handoff;
    expect(request, isNotNull);
    expect(
      request!.targets.map((target) => target.targetId).toSet(),
      <String>{
        'line-ana',
        'line-bea',
        'line-cash',
        'line-ana-semana-previa',
      },
      reason: 'El OCR sólo decide qué evidencia precargar; no puede eliminar '
          'sueldos positivos sin match ni semanas que la cartola no tocó.',
    );
    expect(
      request.groups.map((group) => group.voucherId),
      <String>['voucher-1', 'voucher-previo'],
      reason: 'Las obligaciones permanecen separadas por nómina y en orden '
          'descendente de fecha.',
    );

    final selectedEvidenceByTarget = <String, List<String>>{
      for (final target in request.targets)
        target.targetId: target.ocrCandidates
            .where((candidate) => candidate.selectedForPrefill)
            .map((candidate) => candidate.candidateId)
            .toList(growable: false),
    };
    expect(
      selectedEvidenceByTarget,
      <String, List<String>>{
        'line-ana': <String>['p1-l1-r1'],
        'line-bea': const <String>[],
        'line-cash': const <String>[],
        'line-ana-semana-previa': const <String>[],
      },
      reason: 'Sólo el calce bancario directo seleccionado puede llegar '
          'precargado; las demás obligaciones llegan completas pero sin '
          'inventar evidencia.',
    );

    final matchedRow = find.byKey(
      const ValueKey<String>('payroll-payment-row-line-ana'),
    );
    expect(matchedRow, findsOneWidget);
    expect(
      find.descendant(
        of: matchedRow,
        matching: find.textContaining('\$450.000'),
      ),
      findsWidgets,
    );

    for (final targetId in <String>[
      'line-bea',
      'line-cash',
      'line-ana-semana-previa',
    ]) {
      final row = find.byKey(
        ValueKey<String>('payroll-payment-row-$targetId'),
      );
      if (row.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          row,
          180,
          scrollable: find.byKey(
            const ValueKey<String>('payroll-payment-batch-list'),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.text('Sin movimiento de cartola preseleccionado'),
        ),
        findsOneWidget,
        reason: '$targetId debe estar en el lote sin apropiarse de una fila '
            'bancaria ajena.',
      );
    }
    expect(harness.calls, isNot(contains('createImport')));
    expect(harness.calls, isNot(contains('apply')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('paso 3 · muestra CARTOLA contra NÓMINA por fila sin disclosure',
      (tester) async {
    final harness = recorder(prepared: draft(variance: 250));
    await pump(
      tester,
      actions: harness.actions,
      size: const Size(1360, 1000),
    );
    await loadStatement(tester);

    final comparison = find.byKey(
      const ValueKey<String>(
        'payroll-assist-candidate-line-ana-p1-l1-r1',
      ),
    );
    expect(comparison, findsOneWidget);
    expect(find.text('CARTOLA'), findsOneWidget);
    expect(find.text('NÓMINA'), findsOneWidget);
    expect(
      find.descendant(of: comparison, matching: find.text(r'$450.250')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: comparison, matching: find.text(r'$450.000')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: comparison, matching: find.text(r'+$250')),
      findsOneWidget,
    );
    expect(find.text('Ver movimientos encontrados'), findsNothing);
    expect(find.text('Ocultar movimientos encontrados'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'paso 3 · cada fila bancaria aparece una vez bajo su proposedMatch',
      (tester) async {
    final harness = recorder(
      prepared: draft(
        withCrossWeekEvaluatedCandidate: true,
        withPayrollNamedUnmatchedMovement: true,
      ),
    );
    await pump(
      tester,
      actions: harness.actions,
      size: const Size(1360, 1000),
    );
    await loadStatement(tester);

    final proposed = find.byKey(
      const ValueKey<String>(
        'payroll-assist-candidate-line-ana-p1-l1-r1',
      ),
    );
    final repeatedUnderOtherWeek = find.byKey(
      const ValueKey<String>(
        'payroll-assist-candidate-line-ana-semana-siguiente-p1-l1-r1',
      ),
    );
    final largeDifference = find.byKey(
      const ValueKey<String>(
        'payroll-assist-candidate-line-ana-p1-l2-r2',
      ),
    );

    expect(proposed, findsOneWidget);
    expect(repeatedUnderOtherWeek, findsNothing);
    expect(largeDifference, findsNothing);
    expect(
      find.descendant(of: proposed, matching: find.text(r'$450.000')),
      findsNWidgets(2),
    );

    // La segunda semana sí evaluó p1-l1-r1, pero el matcher no se la propuso:
    // la fila bancaria pertenece únicamente al proposedMatch de `line-ana`.
    final bankRows = tester
        .widgetList<PayrollReviewTableRow>(
          find.byType(PayrollReviewTableRow),
        )
        .map((row) => (row.key! as ValueKey<String>).value)
        .where((key) => key.endsWith('p1-l1-r1'));
    expect(bankRows, hasLength(1));

    // El movimiento de $22.000 nombra a Ana, pero la diferencia lo dejó
    // ineligible. No se ofrece como candidato de pago: queda auditable en la
    // sección de otros egresos, sin desaparecer ni duplicarse.
    final otherMovements = find.byKey(
      const ValueKey<String>('payroll-assist-other-movements'),
    );
    await scrollTo(tester, otherMovements);
    await tester.tap(
      find.descendant(
        of: otherMovements,
        matching: find.byType(ExpansionTile),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: otherMovements, matching: find.text(r'$22.000')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'paso 3 · otros egresos no confunde el offset de scroll con estado expandido',
      (tester) async {
    final harness = recorder(
      prepared: draft(
        withUntouchedWeek: true,
        withAlternateTransferLine: true,
        withCashEmployee: true,
        withUnmatchedMovement: true,
      ),
    );
    await pump(
      tester,
      actions: harness.actions,
      size: const Size(1360, 520),
    );
    await loadStatement(tester);

    final stage = find.byKey(
      const PageStorageKey<String>('payroll-payment-assist'),
    );
    expect(stage, findsOneWidget);
    await tester.drag(stage, const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>('payroll-assist-other-movements'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const PageStorageKey<String>(
          'payroll-assist-other-movements-tile',
        ),
      ),
      findsOneWidget,
    );
  });

  group('5j · ningún texto se recorta en tablet ni en teléfono', () {
    // **Se MIDE, no se supone.** `RenderParagraph.didExceedMaxLines` es `true`
    // exactamente cuando Flutter tuvo que cortar el texto con puntos
    // suspensivos, así que este aserto ve lo mismo que el operador.
    //
    // Nace de la app viva el 2026-08-01: a 834 los pasos decían «Subir cart…»,
    // «14 movimie…» y «0/4 efecti…», y la barra de dinero «Monto reco…» con el
    // primario en «Confirmar 4 sema…». Un botón que no dice qué hace no es una
    // acción: es una adivinanza sobre dinero.
    List<String> elided(WidgetTester tester) {
      final cut = <String>[];
      for (final element in find.byType(Text).evaluate()) {
        final render = element.renderObject;
        if (render is RenderParagraph && render.didExceedMaxLines) {
          cut.add((element.widget as Text).data ?? '<rich>');
        }
      }
      return cut;
    }

    for (final width in <double>[834, 430]) {
      testWidgets(
          'a ${width.toInt()} no queda texto elidido en la etapa de revisión',
          (tester) async {
        final harness = recorder();
        // `pump` es quien fija el tamaño de la vista: ponerlo por fuera lo
        // sobrescribe y las dos anchuras miden lo mismo.
        await pump(
          tester,
          actions: harness.actions,
          size: Size(width, 1000),
        );
        await loadStatement(tester);

        // **Se acota a los rótulos ACCIONABLES**, que son los que al
        // recortarse dejan de decir qué va a pasar: el primario y el
        // secundario de la barra de dinero. Los textos explicativos largos
        // también se eliden hoy y **eso queda declarado abajo**, medido y sin
        // arreglar en esta ronda.
        final acciones = <String>{
          for (final w in tester.widgetList<PayrollPrimaryAction>(
            find.byType(PayrollPrimaryAction),
          ))
            w.label,
          for (final w in tester.widgetList<PayrollSecondaryAction>(
            find.byType(PayrollSecondaryAction),
          ))
            w.label,
        };
        expect(
          elided(tester).where(acciones.contains),
          isEmpty,
          reason: 'a ${width.toInt()} px un botón que mueve dinero no puede '
              'decir «Confirmar 4 sema…»: eso no es una acción, es una '
              'adivinanza',
        );
      });
    }
  });

  testWidgets(
      '5j p3 · la fila de propuestas usa las siete pistas de 7c y marca con '
      'selectionRow', (tester) async {
    // Fuente: proyecto `ERP Bikeshop UI Mockups`, página `Nóminas - Rediseño`,
    // turno 7, frames `7c-ocr-{pacific,aubergine}`. Las pistas se leyeron
    // literales del archivo con DesignSync:
    // `26px 76px minmax(190px,1fr) 118px minmax(200px,1.1fr) 148px 84px`.
    tester.view.physicalSize = const Size(1360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final expanded in <bool>[false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike,
            brightness: Brightness.dark,
          ),
          home: Scaffold(
            body: PayrollReviewTableRow(
              date: '11 jul',
              description: 'TRANSF A L FUENTES',
              amount: r'$172.875',
              stateTag: 'CALZA',
              stateTone: PayrollStateTone.success,
              why: 'monto y cuenta coinciden',
              person: 'Lucas Fuentes',
              personDetail: 'Semana 28',
              expectedAmount: r'$172.875',
              decision: const SizedBox(height: 28),
              expanded: expanded,
              isFirst: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(PayrollReviewTableRow));
      final visual = PayrollVisualTokens.of(context);
      final box = tester
          .widget<Container>(
            find
                .descendant(
                  of: find.byType(PayrollReviewTableRow),
                  matching: find.byType(Container),
                )
                .first,
          )
          .decoration! as BoxDecoration;
      // 7c: la fila marcada va en `selectionRow`, NUNCA en el hundido, que es
      // profundidad de disclosure y tiene otro dueño.
      expect(
        box.color,
        expanded ? visual.surfaceSelected : null,
        reason: 'expanded=$expanded',
      );
      expect(box.color, isNot(visual.surfaceSunken),
          reason: 'expanded=$expanded');

      // La razón es la SEGUNDA línea de la celda de persona, no una columna.
      expect(find.text('monto y cuenta coinciden'), findsOneWidget);
      expect(find.text('Lucas Fuentes'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('5j p3 · los rótulos de columna son los de 7c, y sólo desde 900',
      (tester) async {
    for (final width in const <double>[1360, 834]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike,
            brightness: Brightness.dark,
          ),
          home: const Scaffold(body: PayrollReviewColumnHeader()),
        ),
      );
      await tester.pumpAndSettle();

      final visible = width >= 900;
      expect(
        find.byKey(const ValueKey<String>('payroll-review-column-header')),
        visible ? findsOneWidget : findsNothing,
        reason: 'a $width',
      );
      // La sexta pista dejó de ser CONFIANZA el 2026-08-10: la ocupa el monto
      // que la nómina espera, porque el contraste cartola↔nómina es lo que la
      // etapa existe para resolver y no tenía columna.
      for (final label in const <String>[
        'FECHA',
        'DESCRIPCIÓN EN LA CARTOLA',
        'CARTOLA',
        'PERSONA Y SEMANA',
        'NÓMINA',
        'QUÉ HACER',
      ]) {
        expect(
          find.text(label),
          visible ? findsOneWidget : findsNothing,
          reason: '$label a $width',
        );
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5j p1 · un selector que no responde NO deja la etapa en «Validando el '
      'archivo…» ni esconde Cancelar', (tester) async {
    // Visto en la app viva el 2026-08-01: el panel del sistema quedó sin
    // responder y la etapa 1 se quedó en `Validando el archivo…` **para
    // siempre**, con `Cancelar` deshabilitado por `_isBusy`. La única salida
    // fue matar la sesión.
    //
    // La causa era que el estado ocupado se levantaba ANTES de esperar al
    // selector, así que la pantalla afirmaba estar validando mientras el
    // operador todavía estaba eligiendo el archivo.
    final never = Completer<PayrollPickedStatement?>();
    addTearDown(() {
      if (!never.isCompleted) never.complete(null);
    });
    final harness = recorder();
    await pump(
      tester,
      actions: harness.actions,
      pickFile: () => never.future,
    );

    await tester.tap(find.text('Elegir archivo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // La etapa NO miente: nadie está validando nada todavía.
    expect(
      find.text('Validando el archivo…'),
      findsNothing,
      reason: 'el selector abierto no es una validación en curso',
    );
    expect(
      find.byKey(const ValueKey('payroll-extraction-progress')),
      findsNothing,
    );
    // Y la salida sigue existiendo.
    final cancel = find.text('Cancelar');
    expect(cancel, findsWidgets, reason: 'Cancelar nunca desaparece');
    expect(tester.takeException(), isNull);
  });

  testWidgets('5j p1 · cancelar el selector deja la etapa utilizable',
      (tester) async {
    final harness = recorder();
    await pump(
      tester,
      actions: harness.actions,
      pickFile: () async => null,
    );

    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();

    expect(find.text('Validando el archivo…'), findsNothing);
    expect(find.text('Elegir archivo'), findsOneWidget);
    expect(harness.calls, isEmpty, reason: 'cancelar no prepara nada');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5j p1 · si el selector falla, la etapa lo dice y se puede '
      'reintentar', (tester) async {
    final harness = recorder();
    await pump(
      tester,
      actions: harness.actions,
      pickFile: () async => throw StateError('panel del sistema caído'),
    );

    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();

    expect(find.text('Validando el archivo…'), findsNothing);
    expect(
      find.textContaining('No pudimos abrir el selector'),
      findsOneWidget,
      reason: 'una falla del selector se nombra, no se traga',
    );
    expect(find.text('Elegir archivo'), findsOneWidget);
    expect(harness.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      '5j p3 · las dos columnas de dinero comparten borde derecho y ningún '
      'rótulo se recorta', (tester) async {
    // **Se mide, no se supone.** El contraste cartola↔nómina sólo se lee si los
    // dos números caen en la misma rejilla que sus rótulos: un encabezado
    // corrido, o recortado con puntos suspensivos, deja al operador sin saber
    // cuál columna está mirando — que es exactamente el defecto que este
    // rediseño vino a corregir.
    final harness = recorder(prepared: draft(variance: 250));
    await pump(tester, actions: harness.actions, size: const Size(1360, 1000));
    await loadStatement(tester);

    double rightOf(Finder finder) => tester.getRect(finder.first).right;
    final comparison = find.byKey(
      const ValueKey<String>(
        'payroll-assist-candidate-line-ana-p1-l1-r1',
      ),
    );
    Finder comparisonText(String value) =>
        find.descendant(of: comparison, matching: find.text(value));

    expect(
      rightOf(find.text('CARTOLA')),
      moreOrLessEquals(rightOf(comparisonText(r'$450.250')), epsilon: 0.5),
    );
    expect(
      rightOf(find.text('NÓMINA')),
      moreOrLessEquals(rightOf(comparisonText(r'$450.000')), epsilon: 0.5),
    );
    // La diferencia va bajo el monto que la nómina espera, con signo.
    expect(
      rightOf(comparisonText(r'+$250')),
      moreOrLessEquals(rightOf(find.text('NÓMINA')), epsilon: 0.5),
    );

    final elided = <String>[
      for (final element in find.byType(Text).evaluate())
        if (element.renderObject case final RenderParagraph render
            when render.didExceedMaxLines)
          (element.widget as Text).data ?? '<rich>',
    ];
    for (final label in const <String>[
      'FECHA',
      'DESCRIPCIÓN EN LA CARTOLA',
      'CARTOLA',
      'PERSONA Y SEMANA',
      'NÓMINA',
      'QUÉ HACER',
    ]) {
      expect(elided, isNot(contains(label)));
    }
  });

  testWidgets(
      '5j paso 3 · genera las seis capturas de HARNESS (claro/oscuro × '
      '1360/834/430)', (tester) async {
    // Mismo contrato que las de los pasos 2 y 4: **evidencia de HARNESS**, con
    // fixture sintético, opt-in por `PAYROLL_SHOT_DIR`, y con su límite
    // declarado —las fuentes reales no cargan en `flutter_test`, así que el
    // texto sale en bloques: prueban **composición**, no tipografía.
    final target = Platform.environment['PAYROLL_SHOT_DIR'];
    if (target == null || target.isEmpty) {
      markTestSkipped('define PAYROLL_SHOT_DIR para generar las capturas');
      return;
    }
    suspendGoogleFontsNetwork();
    final dir = Directory(target);
    for (final brightness in Brightness.values) {
      for (final width in const <double>[1360, 834, 430]) {
        final harness = recorder(
          prepared: draft(
            variance: 250,
            withPayrollNamedUnmatchedMovement: true,
            withIncompleteEvidence: true,
            extraRows: <PayrollStatementRow>[
              for (var i = 1; i <= 4; i++)
                statementRow(
                  rowNumber: 500 + i,
                  description: 'PAGO PROVEEDOR LIMPIO $i',
                  debit: 10000 * i,
                ),
            ],
          ),
        );
        await pump(
          tester,
          actions: harness.actions,
          size: Size(width, width < 600 ? 1400 : 1100),
          brightness: brightness,
        );
        await loadStatement(tester);

        final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ImageByteFormat.png);
          image.dispose();
          if (data == null) return;
          if (!dir.existsSync()) dir.createSync(recursive: true);
          File(
            '${dir.path}/paso3-${brightness.name}-${width.toInt()}.png',
          ).writeAsBytesSync(data.buffer.asUint8List());
        });
      }
    }
    expect(
      dir
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith('paso3-'))
          .length,
      6,
    );
  });
}

/// Cliente HTTP que nunca responde, para `suspendGoogleFontsNetwork`.
///
/// No falla ni acierta: deja la petición colgada. Es exactamente lo que se
/// necesita para que una carga de fuente accesoria no rechace y contamine el
/// `runAsync` de la captura.
class _NeverCompletingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Completer<http.StreamedResponse>().future;
  }
}

class _SensitiveExtractionFailure implements Exception {
  const _SensitiveExtractionFailure();

  static const ocrText = 'TEXTO_OCR_SECRETO_NO_LOGGEAR';
  static const accountNumber = '0000111122223333';

  @override
  String toString() => '$ocrText cuenta $accountNumber';
}
