import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_statement_reconciliation.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_voucher.dart';
import 'package:vinabike_erp/modules/hr/pages/payroll_reconciliation_page.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_reconciliation_surface.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_transfer_review_surface.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_reconciliation_service.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_statement_extraction_service.dart';
import 'package:vinabike_erp/modules/hr/widgets/payroll_money_bar.dart';
import 'package:vinabike_erp/modules/hr/widgets/payroll_reconciliation_row.dart';

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
        localImageOcrSupported: true,
      ),
      'ios': payrollStatementCaptureCapabilities(
        isWeb: false,
        platform: TargetPlatform.iOS,
        localImageOcrSupported: true,
      ),
      'macos': payrollStatementCaptureCapabilities(
        isWeb: false,
        platform: TargetPlatform.macOS,
        localImageOcrSupported: true,
      ),
      'web': payrollStatementCaptureCapabilities(
        isWeb: true,
        platform: TargetPlatform.linux,
        localImageOcrSupported: false,
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
    expect(matrix['web']!.supportsImages, isFalse);
    expect(matrix['web']!.supportsGallery, isFalse);
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
  }) {
    return PayrollReconciliationVoucherLine(
      lineId: lineId,
      voucherId: 'voucher-1',
      employeeId: employeeId,
      periodStart: const PayrollCivilDate(2026, 7, 21),
      periodEnd: const PayrollCivilDate(2026, 7, 27),
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
    int? partialBankDebitClp,
    Set<String> missingCanonicalMethod = const {},
    List<EmployeeAdvance> openAdvances = const [],
    bool alreadyResolved = false,
    PayrollCivilDate? documentDate,
    PayrollVoucherStatus voucherStatus = PayrollVoucherStatus.draft,
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
      parseResult: PayrollBankStatementParseResult(rows: rows),
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
      expectedVoucherVersionsById: const {'voucher-1': 0},
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
    PayrollStatementPicker? pickFile,
    PayrollStatementPicker? pickCamera,
    PayrollStatementPicker? pickGallery,
    Future<void> Function(String employeeId)? onConfigureEmployeePaymentMethod,
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
            ),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(key: UniqueKey(), routerConfig: router),
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
        find.widgetWithText(PayrollPrimaryAction, 'Revisar coincidencias');
    if (toReview.evaluate().isNotEmpty &&
        tester.widget<PayrollPrimaryAction>(toReview.first).onPressed != null) {
      await tester.tap(toReview.first);
      await tester.pumpAndSettle();
    }
  }

  Future<void> goToStage(WidgetTester tester, String stage) async {
    const labels = <String>[
      'Subir cartola',
      'Extraer',
      'Revisar',
      'Aplicar',
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

  /// Design 2c: the suggestion section is born collapsed. Expand it via its
  /// disclosure zone (never the header center, which can hit the batch
  /// approval) only when it is actually closed.
  Future<void> openReviewGroup(WidgetTester tester, String id) async {
    final group = find.byKey(ValueKey('review-group-$id'));
    if (group.evaluate().isEmpty) {
      // The stage list virtualizes: bring the group into existence first.
      await tester.scrollUntilVisible(
        group,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
    }
    if (!tester.widget<PayrollReviewSection>(group).open) {
      await tester.ensureVisible(group);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(group) + const Offset(20, 22));
      await tester.pumpAndSettle();
    }
  }

  Future<void> openSuggestions(WidgetTester tester) =>
      openReviewGroup(tester, 'suggested');

  /// Un calce de un solo toque pasa a «Ya respondidos», que también nace
  /// plegado: leer su fila del ledger exige abrir ese grupo, no el de
  /// sugerencias.
  Future<void> openResolved(WidgetTester tester) =>
      openReviewGroup(tester, 'resolved');

  /// Taps a per-row action inside the suggestion section, scrolling the
  /// virtualized stage list until the action is built and visible.
  Future<void> tapSuggestionAction(WidgetTester tester, String label) async {
    await openSuggestions(tester);
    final action = find.descendant(
      of: find.byKey(const ValueKey('review-group-suggested')),
      matching: find.widgetWithText(PayrollSoftAction, label),
    );
    if (action.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        action,
        150,
        scrollable: find.byType(Scrollable).first,
      );
    } else {
      await tester.ensureVisible(action.first);
    }
    await tester.pumpAndSettle();
    await tester.tap(action.first);
    await tester.pumpAndSettle();
  }

  /// Approves the first batch-safe suggestion from its dense ledger row.
  Future<void> confirmSuggestion(WidgetTester tester) async {
    await tapSuggestionAction(tester, 'Confirmar');
  }

  /// Stages the first suggestion into the pending-decision card ("Ver"),
  /// where the full evidence, options, variance and reason controls live.
  Future<void> reviewSuggestion(WidgetTester tester) async {
    // 5j paso 3: la celda de decisión lleva UN verbo y un `⋯`. En una fila
    // batch-safe el verbo es «Confirmar» y el camino largo vive en el
    // overflow, así que «Ver» ya no existe como botón con texto.
    await openSuggestions(tester);
    final overflow = find.descendant(
      of: find.byKey(const ValueKey('review-group-suggested')),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>)
                .value
                .startsWith('payroll-row-more-'),
      ),
    );
    if (overflow.evaluate().isEmpty) {
      await tapSuggestionAction(tester, 'Ver');
      return;
    }
    await tester.ensureVisible(overflow.first);
    await tester.pumpAndSettle();
    await tester.tap(overflow.first);
    await tester.pumpAndSettle();
  }

  /// Opens the active cash card for one person in the cash stage.
  Future<void> openCashPerson(WidgetTester tester, String name) async {
    await tester.tap(find.text(name).first);
    await tester.pumpAndSettle();
  }

  Future<void> selectBankAccount(WidgetTester tester) async {
    final selector = find.byKey(
      const ValueKey('payroll-statement-erp-account'),
    );
    if (selector.evaluate().isEmpty) {
      // The stage list virtualizes; the selector lives at the top.
      await tester.dragUntilVisible(
        selector,
        find.byType(Scrollable).first,
        const Offset(0, 250),
      );
    } else {
      await tester.ensureVisible(selector);
    }
    await tester.pumpAndSettle();
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Banco principal').last);
    await tester.pumpAndSettle();
  }

  group('file stage', () {
    testWidgets('preparing a statement moves to the transfer review',
        (tester) async {
      final harness = recorder();
      await pump(tester, actions: harness.actions);

      expect(find.byType(PayrollReconciliationSurface), findsOneWidget);
      expect(find.text('Sube la cartola'), findsOneWidget);
      await loadStatement(tester);

      expect(harness.calls, ['prepare']);
      expect(find.textContaining('Revisar coincidencias'), findsWidgets);
      // The pending-decision card leads the review; the suggestion batch is
      // one deliberate expansion away with its dense ledger rows.
      expect(
        find.byKey(const ValueKey('payroll-pending-decision-card')),
        findsOneWidget,
      );
      expect(find.textContaining('Calces sugeridos'), findsOneWidget);
      await openSuggestions(tester);
      expect(find.byType(PayrollReviewTableRow), findsWidgets);
    });

    testWidgets('camera tap uses the injected picker and completes preparation',
        (tester) async {
      final harness = recorder(cameraCaptureSupported: true);
      var cameraCalls = 0;
      await pump(
        tester,
        actions: harness.actions,
        pickCamera: () async {
          cameraCalls += 1;
          return PayrollPickedStatement(
            bytes: Uint8List.fromList(const <int>[0xFF, 0xD8, 0xFF]),
            filename: 'captura-sintetica.jpg',
          );
        },
      );

      await tester.tap(find.text('Cámara'));
      await tester.pumpAndSettle();

      expect(cameraCalls, 1);
      expect(harness.calls, <String>['prepare']);
      expect(find.textContaining('Revisar coincidencias'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'gallery stays available on image-OCR hosts without camera support',
        (tester) async {
      final harness = recorder(cameraCaptureSupported: false);
      var galleryCalls = 0;
      await pump(
        tester,
        actions: harness.actions,
        pickGallery: () async {
          galleryCalls += 1;
          return PayrollPickedStatement(
            bytes: Uint8List.fromList(
              const <int>[0x89, 0x50, 0x4E, 0x47],
            ),
            filename: 'galeria-sintetica.png',
          );
        },
      );

      expect(find.text('Cámara'), findsNothing);
      expect(find.text('Galería'), findsOneWidget);
      await tester.tap(find.text('Galería'));
      await tester.pumpAndSettle();

      expect(galleryCalls, 1);
      expect(harness.calls, <String>['prepare']);
      expect(find.textContaining('Revisar coincidencias'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows the active extraction phase and page while preparing',
        (tester) async {
      final harness = recorder();
      final prepared = Completer<PayrollStatementPreparedDraft>();
      final actions = PayrollReconciliationActions(
        isImageOcrSupported: true,
        prepare: harness.actions.prepare,
        prepareWithProgress: ({
          required bytes,
          required filename,
          sourcePath,
          required onProgress,
        }) {
          onProgress(
            const PayrollStatementPreparationProgress(
              phase: PayrollStatementPreparationPhase.recognizingPdfPage,
              pageNumber: 2,
              pageCount: 3,
            ),
          );
          return prepared.future;
        },
        createImport: harness.actions.createImport,
        apply: harness.actions.apply,
      );
      await pump(tester, actions: actions);

      await tester.tap(find.text('Elegir archivo'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('payroll-extraction-progress')),
        findsOneWidget,
      );
      expect(find.text('Reconociendo página 2 de 3…'), findsOneWidget);
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, closeTo(2 / 3, 0.0001));

      prepared.complete(draft());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('payroll-extraction-progress')),
        findsNothing,
      );
      expect(find.textContaining('Revisar coincidencias'), findsWidgets);
    });

    testWidgets('technical failures never log OCR text or account data',
        (tester) async {
      final messages = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) messages.add(message);
      };
      try {
        final actions = PayrollReconciliationActions(
          isImageOcrSupported: true,
          prepare: ({required bytes, required filename, sourcePath}) async {
            throw const _SensitiveExtractionFailure();
          },
          createImport: (_, {required erpAccountId}) async =>
              throw UnimplementedError(),
          apply: ({
            required draft,
            required importReceipt,
            required decisions,
            required authorizedDraftVoucherIds,
            operationKey,
          }) async =>
              throw UnimplementedError(),
        );
        await pump(tester, actions: actions);
        await loadStatement(tester);

        final log = messages.join('\n');
        expect(log, contains('_SensitiveExtractionFailure'));
        expect(log, isNot(contains(_SensitiveExtractionFailure.ocrText)));
        expect(
          log,
          isNot(contains(_SensitiveExtractionFailure.accountNumber)),
        );
        expect(
          find.textContaining('No pudimos leer la cartola.'),
          findsOneWidget,
        );
      } finally {
        // Flutter verifies debug globals before test tearDown callbacks run.
        debugPrint = originalDebugPrint;
      }
    });

    testWidgets('a service failure is shown verbatim and keeps the stage',
        (tester) async {
      final actions = PayrollReconciliationActions(
        isImageOcrSupported: false,
        prepare: ({required bytes, required filename, sourcePath}) async {
          throw const PayrollReconciliationServiceException(
            'Este archivo necesita OCR de imagen.',
          );
        },
        createImport: (_, {required erpAccountId}) async =>
            throw UnimplementedError(),
        apply: ({
          required draft,
          required importReceipt,
          required decisions,
          required authorizedDraftVoucherIds,
          operationKey,
        }) async =>
            throw UnimplementedError(),
      );
      await pump(tester, actions: actions);
      await loadStatement(tester);

      expect(
        find.textContaining('Este archivo necesita OCR de imagen.'),
        findsOneWidget,
      );
      // On-device OCR is unavailable here, so the actionable state is shown
      // instead of a cloud fallback.
      expect(find.text('Cámara'), findsNothing);
      expect(
        find.textContaining('OCR en el propio dispositivo'),
        findsOneWidget,
      );
    });
  });

  group('stage gating', () {
    testWidgets(
        'before reading a file only the file stage is reachable and Continue explains the blocker',
        (tester) async {
      final harness = recorder();
      await pump(tester, actions: harness.actions);

      expect(stageIsEnabled(tester, 1), isTrue);
      expect(stageIsEnabled(tester, 2), isFalse);
      expect(stageIsEnabled(tester, 3), isFalse);
      expect(stageIsEnabled(tester, 4), isFalse);
      expect(primaryAction(tester, 'Continuar').onPressed, isNull);
      expect(
        find.text('Carga y lee una cartola para comenzar la revisión.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'a prepared draft unlocks transfers but not later stages until transfer review is complete',
        (tester) async {
      final harness = recorder();
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      expect(stageIsEnabled(tester, 1), isTrue);
      expect(stageIsEnabled(tester, 2), isTrue);
      // t5: la revisión abre con el borrador; sólo Aplicar espera a que la
      // revisión esté completa.
      expect(stageIsEnabled(tester, 3), isTrue);
      expect(stageIsEnabled(tester, 4), isFalse);
      expect(primaryAction(tester, 'Ir a aplicar').onPressed, isNull);
      expect(
        find.textContaining(
          'Falta elegir la cuenta ERP correspondiente a la cartola.',
        ),
        findsOneWidget,
      );

      // Gating never traps the operator: completed/earlier stages remain
      // reachable while later stages wait for their prerequisites.
      await goToStage(tester, 'Subir cartola');
      expect(find.text('Sube la cartola'), findsOneWidget);
      expect(stageIsEnabled(tester, 2), isTrue);
    });

    testWidgets(
        'cash unlocks after transfer review and confirm unlocks only after every cash answer',
        (tester) async {
      final harness = recorder(prepared: draft(withCashEmployee: true));
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);

      expect(stageIsEnabled(tester, 1), isTrue);
      expect(stageIsEnabled(tester, 2), isTrue);
      expect(stageIsEnabled(tester, 3), isTrue);
      expect(stageIsEnabled(tester, 4), isTrue);
      expect(primaryAction(tester, 'Ir a aplicar').onPressed, isNotNull);

      await goToStage(tester, 'Aplicar');
      // El efectivo sin responder bloquea la ESCRITURA, no la etapa.
      expect(primaryAction(tester, commitAndApplyLabel).onPressed, isNull);
      expect(
        find.text('1 persona en efectivo sin elegir cómo se resolvió.'),
        findsWidgets,
      );

      await openCashPerson(tester, 'Rosa Díaz');
      await tester.tap(
        find.widgetWithText(PayrollDecisionOptionCard, 'Todavía no pagado'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar respuesta'));
      await tester.pumpAndSettle();

      expect(stageIsEnabled(tester, 4), isTrue);
      expect(
        primaryAction(tester, commitAndApplyLabel).onPressed,
        isNotNull,
      );
    });
  });

  group('review blocks the batch until every question is answered', () {
    testWidgets(
        'a generic outgoing without beneficiary is informational, '
        'collapsed and nonblocking after the real match is confirmed',
        (tester) async {
      final harness = recorder(
        prepared: draft(withUnmatchedMovement: true),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await selectBankAccount(tester);

      final automaticGroup = find.byKey(
        const ValueKey('review-group-automatic'),
      );
      expect(automaticGroup, findsOneWidget);
      expect(find.text('Fuera del lote de nómina'), findsOneWidget);
      expect(
        find.text('Movimiento sin persona asignada'),
        findsNothing,
        reason: 'Informational movements stay collapsed by default.',
      );
      expect(
        find.text(
          '1 movimiento u obligación sigue sin disposición.',
        ),
        findsOneWidget,
      );
      expect(primaryAction(tester, 'Ir a aplicar').onPressed, isNull);

      await confirmSuggestion(tester);

      expect(stageIsEnabled(tester, 3), isTrue);
      expect(primaryAction(tester, 'Ir a aplicar').onPressed, isNotNull);

      await tester.scrollUntilVisible(
        automaticGroup,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(automaticGroup);
      await tester.pumpAndSettle();
      final informationalRow = find.byKey(
        const ValueKey('payroll-ledger-p1-l2-r2'),
      );
      await tester.ensureVisible(informationalRow);
      await tester.pumpAndSettle();
      final ledgerRow = tester.widget<PayrollReviewTableRow>(informationalRow);
      expect(ledgerRow.stateTag, 'NO ES NÓMINA');

      // Reversible: «Revisar» reabre la evidencia completa en la tarjeta de
      // decisión con el veredicto automático y su razón de auditoría.
      await tester.tap(
        find.descendant(
          of: informationalRow,
          matching: find.widgetWithText(PayrollSoftAction, 'Revisar'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('payroll-pending-decision-card')),
        find.byType(Scrollable).first,
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      final staged = find.byWidgetPredicate(
        (widget) =>
            widget is PayrollReconciliationRow &&
            widget.data.sourceRowId == 'p1-l2-r2',
      );
      expect(staged, findsOneWidget);
      final row = tester.widget<PayrollReconciliationRow>(staged);
      expect(row.data.isAutomaticallyClassified, isTrue);
      expect(row.data.requiresDisposition, isFalse);
      expect(row.disposition, PayrollRowDisposition.notPayroll);
      expect(
        row.data.automaticAuditReason,
        contains('Clasificación automática'),
      );
    });

    testWidgets(
        'a payroll-named within-window debit outside tolerance remains a '
        'manual blocker', (tester) async {
      final harness = recorder(
        prepared: draft(withPayrollNamedUnmatchedMovement: true),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);

      expect(stageIsEnabled(tester, 4), isFalse);
      expect(primaryAction(tester, 'Ir a aplicar').onPressed, isNull);
      expect(
        find.text('1 movimiento u obligación sigue sin disposición.'),
        findsOneWidget,
      );

      // The real ambiguity leads the step inside the pending-decision card;
      // nothing hides it behind an accordion.
      expect(
        find.byKey(const ValueKey('payroll-pending-decision-card')),
        findsOneWidget,
      );
      final suspiciousRow = find.byWidgetPredicate(
        (widget) =>
            widget is PayrollReconciliationRow &&
            widget.data.sourceRowId == 'p1-l2-r2',
      );
      expect(suspiciousRow, findsOneWidget);
      final row = tester.widget<PayrollReconciliationRow>(suspiciousRow);
      expect(row.data.bankDescription, 'TRANSFERENCIA A ANA RIVAS');
      expect(row.data.bankAmountClp, 22000);
      expect(row.data.isAutomaticallyClassified, isFalse);
      expect(row.data.requiresDisposition, isTrue);
      expect(row.disposition, PayrollRowDisposition.pending);
      expect(
        find.descendant(
          of: suspiciousRow,
          matching:
              find.widgetWithText(PayrollDecisionOptionCard, 'No es nómina'),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'a supplier debit whose observed beneficiary matches no worker is '
        'automatic, auditable and reopenable', (tester) async {
      final harness = recorder(
        prepared: draft(withForeignNamedMovement: true),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);

      // Naming a beneficiary is not enough to demand an answer: SODIMAC
      // matches nobody in payroll, so once the real suggestion is answered
      // nothing else blocks the batch.
      expect(
        find.textContaining('sigue sin disposición'),
        findsNothing,
      );
      expect(primaryAction(tester, 'Ir a aplicar').onPressed, isNotNull);
      final automaticGroup = find.byKey(
        const ValueKey('review-group-automatic'),
      );
      expect(automaticGroup, findsOneWidget);

      await tester.scrollUntilVisible(
        automaticGroup,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(automaticGroup);
      await tester.pumpAndSettle();
      final autoLedgerRow = find.byKey(
        const ValueKey('payroll-ledger-p1-l2-r2'),
      );
      await tester.ensureVisible(autoLedgerRow);
      await tester.pumpAndSettle();
      expect(
        tester.widget<PayrollReviewTableRow>(autoLedgerRow).stateTag,
        'NO ES NÓMINA',
      );

      // Reopenable: the automatic verdict is a default, not a lock. «Revisar»
      // stages the evidence into the card and the operator can override it
      // with any manual disposition.
      await tester.tap(
        find.descendant(
          of: autoLedgerRow,
          matching: find.widgetWithText(PayrollSoftAction, 'Revisar'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('payroll-pending-decision-card')),
        find.byType(Scrollable).first,
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      final autoRow = find.byWidgetPredicate(
        (widget) =>
            widget is PayrollReconciliationRow &&
            widget.data.sourceRowId == 'p1-l2-r2',
      );
      expect(autoRow, findsOneWidget);
      var row = tester.widget<PayrollReconciliationRow>(autoRow);
      expect(row.data.isAutomaticallyClassified, isTrue);
      expect(row.data.requiresDisposition, isFalse);
      expect(row.disposition, PayrollRowDisposition.notPayroll);
      expect(
        row.data.automaticAuditReason,
        contains('beneficiario del cargo no coincide'),
      );

      final holdChip = find.descendant(
        of: autoRow,
        matching: find.widgetWithText(
          PayrollDecisionOptionCard,
          'Retener como excepción',
        ),
      );
      expect(holdChip, findsOneWidget);
      await tester.ensureVisible(holdChip);
      await tester.pumpAndSettle();
      await tester.tap(holdChip);
      await tester.pumpAndSettle();
      row = tester.widget<PayrollReconciliationRow>(autoRow);
      expect(row.disposition, PayrollRowDisposition.hold);
    });

    testWidgets(
        'a foreign-named debit serializes one automatic ignore without '
        'manual confirmation', (tester) async {
      final harness = recorder(
        prepared: draft(withForeignNamedMovement: true),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);

      await goToStage(tester, 'Aplicar');
      await tester.tap(
        find.widgetWithText(PayrollPrimaryAction, commitAndApplyLabel),
      );
      await tester.pumpAndSettle();

      final sourceDecisions = harness.decisions.single
          .where((decision) => decision.sourceRowId == 'p1-l2-r2')
          .toList(growable: false);
      expect(sourceDecisions, hasLength(1));
      expect(sourceDecisions.single.kind, PayrollReviewDecisionKind.ignore);
      expect(sourceDecisions.single.manualConfirmation, isFalse);
      expect(
        sourceDecisions.single.note,
        contains('beneficiario del cargo no coincide'),
      );
    });

    testWidgets(
        'a worker-named debit with no candidate line never auto-classifies',
        (tester) async {
      // Bea Soto is a tenant worker without any pending obligation in this
      // batch (settled, cash or simply out of the loaded weeks). The matcher
      // produces no candidates for the row, but its name proof keeps it out
      // of the foreign set: absorbing it automatically would hide a possible
      // duplicate or extra payment to a real worker.
      final harness = recorder(
        prepared: draft(withSettledWorkerNamedMovement: true),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);

      expect(primaryAction(tester, 'Ir a aplicar').onPressed, isNull);
      expect(
        find.text('1 movimiento u obligación sigue sin disposición.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('review-group-automatic')),
        findsNothing,
      );

      // The real question leads the step inside the pending-decision card.
      expect(
        find.byKey(const ValueKey('payroll-pending-decision-card')),
        findsOneWidget,
      );
      final workerRow = find.byWidgetPredicate(
        (widget) =>
            widget is PayrollReconciliationRow &&
            widget.data.sourceRowId == 'p1-l2-r2',
      );
      expect(workerRow, findsOneWidget);
      final row = tester.widget<PayrollReconciliationRow>(workerRow);
      expect(row.data.bankDescription, 'TRANSFERENCIA A BEA SOTO');
      expect(row.data.isAutomaticallyClassified, isFalse);
      expect(row.data.requiresDisposition, isTrue);
      expect(row.disposition, PayrollRowDisposition.pending);
    });

    testWidgets('the transfer counter reports only the human workload',
        (tester) async {
      final harness = recorder(
        prepared: draft(withForeignNamedMovement: true),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await selectBankAccount(tester);

      // One suggestion is the whole human workload; the automatic supplier
      // row is evidence and must not inflate the denominator.
      expect(find.text('0/1'), findsWidgets);
      expect(find.text('0/2'), findsNothing);

      await confirmSuggestion(tester);
      expect(find.text('1/1'), findsWidgets);
      expect(find.text('1/2'), findsNothing);
    });

    testWidgets(
        'an automatically classified outgoing serializes one audited ignore '
        'without manual confirmation', (tester) async {
      final harness = recorder(
        prepared: draft(withUnmatchedMovement: true),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);

      await goToStage(tester, 'Aplicar');
      await tester.tap(
        find.widgetWithText(PayrollPrimaryAction, commitAndApplyLabel),
      );
      await tester.pumpAndSettle();

      final sourceDecisions = harness.decisions.single
          .where((decision) => decision.sourceRowId == 'p1-l2-r2')
          .toList(growable: false);
      expect(sourceDecisions, hasLength(1));
      expect(sourceDecisions.single.kind, PayrollReviewDecisionKind.ignore);
      expect(sourceDecisions.single.manualConfirmation, isFalse);
      expect(
        sourceDecisions.single.note,
        contains('Clasificación automática'),
      );
    });

    testWidgets(
        'an incomplete OCR row survives preparation and requires an explicit disposition',
        (tester) async {
      final harness = recorder(
        prepared: draft(withIncompleteEvidence: true),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      expect(harness.calls, ['prepare']);
      expect(find.textContaining('Revisar coincidencias'), findsWidgets);
      expect(find.text('Fila OCR incompleta'), findsOneWidget);
      expect(
        find.text('Se conserva como evidencia; no puede crear un pago'),
        findsOneWidget,
      );
      final incompleteFinder = find.byWidgetPredicate(
        (widget) =>
            widget is PayrollReconciliationRow &&
            widget.data.kind == PayrollDecisionRowKind.incompleteEvidence,
      );
      var incompleteWidget =
          tester.widget<PayrollReconciliationRow>(incompleteFinder);
      expect(incompleteWidget.data.canConfirm, isFalse);
      expect(incompleteWidget.data.requiresDisposition, isTrue);
      expect(incompleteWidget.disposition, PayrollRowDisposition.pending);

      final hold = find.descendant(
        of: incompleteFinder,
        matching: find.widgetWithText(
            PayrollDecisionOptionCard, 'Retener como excepción'),
      );
      expect(hold, findsOneWidget);
      await tester.ensureVisible(hold);
      await tester.pumpAndSettle();
      await tester.tap(hold);
      await tester.pumpAndSettle();

      incompleteWidget =
          tester.widget<PayrollReconciliationRow>(incompleteFinder);
      expect(incompleteWidget.disposition, PayrollRowDisposition.hold);
    });

    testWidgets('a positive difference demands an explicit disposition',
        (tester) async {
      final harness = recorder(prepared: draft(variance: 250));
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      // Una diferencia de monto no es un calce de un solo toque: la fila nace
      // como la pregunta que encabeza la etapa, con su evidencia abierta.
      await tester.tap(
        find.widgetWithText(PayrollDecisionOptionCard, 'Es este pago'),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('de más'), findsOneWidget);
      expect(find.textContaining('No se ajustan horas'), findsOneWidget);
      expect(
        find.widgetWithText(PayrollDecisionOptionCard, 'Dejar sin conciliar'),
        findsOneWidget,
      );

      await selectBankAccount(tester);
      expect(stageIsEnabled(tester, 4), isFalse);
      expect(primaryAction(tester, 'Ir a aplicar').onPressed, isNull);
      expect(
        find.text('1 diferencia de monto sin decidir qué pasa con ella.'),
        findsOneWidget,
      );
    });

    testWidgets('the systematic bank round-up resolves with one tap',
        (tester) async {
      final harness = recorder(prepared: draft(variance: 250));
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      // The account selector sits at the top of the stage; answer it before
      // working the leading question.
      await selectBankAccount(tester);
      await tester.tap(
        find.widgetWithText(PayrollDecisionOptionCard, 'Es este pago'),
      );
      await tester.pumpAndSettle();
      final quickAccept = find.widgetWithText(
        PayrollSoftAction,
        r'Aceptar como redondeo (+$250)',
      );
      await tester.ensureVisible(quickAccept);
      await tester.pumpAndSettle();
      await tester.tap(quickAccept);
      await tester.pumpAndSettle();

      // The residue stays unresolved (never an automatic advance) and the
      // audit reason arrives pre-filled but editable.
      expect(
        find.textContaining('Redondeo bancario'),
        findsOneWidget,
      );
      await goToStage(tester, 'Aplicar');
      expect(find.textContaining('sin decidir qué pasa'), findsNothing);
      expect(
        find.textContaining('necesita una razón de auditoría'),
        findsNothing,
      );
    });

    testWidgets(
        'backend legacy: el preview revisa la cartola pero aplicar queda '
        'bloqueado con la razón visible', (tester) async {
      final harness = recorder(
        prepared: draft(),
        versionedCommandsProbe: false,
      );
      await pump(tester, actions: harness.actions);

      // The file stage announces review-only mode before any work happens.
      expect(
        find.byKey(const ValueKey('payroll-reconciliation-backend-missing')),
        findsOneWidget,
      );

      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);

      await goToStage(tester, 'Aplicar');
      expect(primaryAction(tester, commitAndApplyLabel).onPressed, isNull);
      expect(
        find.textContaining('aún no tiene la actualización'),
        findsWidgets,
      );
      expect(harness.calls, isNot(contains('createImport')));
      expect(harness.calls, isNot(contains('apply')));
    });

    testWidgets(
        'an exact manual reassignment requires a reason and preserves both obligations',
        (tester) async {
      final harness = recorder(
        prepared: draft(withAlternateTransferLine: true),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await reviewSuggestion(tester);

      final manualSelector = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Vincular a persona y semana',
      );
      expect(manualSelector, findsOneWidget);
      await tester.ensureVisible(manualSelector);
      await tester.pumpAndSettle();
      await tester.tap(manualSelector);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Bea Soto ·').last);
      await tester.pumpAndSettle();

      expect(
        find.text('21 – 27 jul · elegido manualmente'),
        findsOneWidget,
      );
      final manuallyReassignedRow = find.byWidgetPredicate(
        (widget) =>
            widget is PayrollReconciliationRow &&
            widget.data.kind == PayrollDecisionRowKind.suggested &&
            widget.data.selectedManualLineId == 'line-bea',
      );
      final confirmReassignment = find.descendant(
        of: manuallyReassignedRow,
        matching:
            find.widgetWithText(PayrollDecisionOptionCard, 'Es este pago'),
      );
      await tester.ensureVisible(confirmReassignment);
      await tester.pumpAndSettle();
      await tester.tap(confirmReassignment);
      await tester.pumpAndSettle();
      expect(find.text('Razón de confirmación'), findsOneWidget);

      await selectBankAccount(tester);
      expect(
        find.text('1 confirmación necesita una razón de auditoría.'),
        findsOneWidget,
      );
      expect(stageIsEnabled(tester, 4), isFalse);
      expect(primaryAction(tester, 'Ir a aplicar').onPressed, isNull);

      await tester.enterText(
        find.widgetWithText(TextField, 'Razón de confirmación'),
        'Beneficiaria corregida contra el comprobante bancario.',
      );
      await tester.pumpAndSettle();
      expect(stageIsEnabled(tester, 4), isTrue);
      await goToStage(tester, 'Aplicar');
      expect(
        primaryAction(tester, commitAndApplyLabel).onPressed,
        isNotNull,
      );
      await tester.tap(
        find.widgetWithText(PayrollPrimaryAction, commitAndApplyLabel),
      );
      await tester.pumpAndSettle();

      final decisions = harness.decisions.single;
      final bankPayment = decisions.singleWhere(
        (decision) => decision.kind == PayrollReviewDecisionKind.bankPayment,
      );
      expect(bankPayment.voucherLineId, 'line-bea');
      expect(bankPayment.amountClp, 450000);
      expect(bankPayment.manualConfirmation, isTrue);
      expect(
        bankPayment.note,
        'Beneficiaria corregida contra el comprobante bancario.',
      );

      final originalNotPaid = decisions.singleWhere(
        (decision) =>
            decision.kind == PayrollReviewDecisionKind.notPaid &&
            decision.voucherLineId == 'line-ana',
      );
      expect(originalNotPaid.manualConfirmation, isTrue);
      expect(originalNotPaid.note, contains('reasignó'));
    });

    testWidgets(
        'an unmatched smaller debit can be manually linked as a partial payment',
        (tester) async {
      final harness = recorder(
        prepared: draft(partialBankDebitClp: 300000),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      final unmatchedBeforeLink = find.byWidgetPredicate(
        (widget) =>
            widget is PayrollReconciliationRow &&
            widget.data.kind == PayrollDecisionRowKind.unmatchedMovement,
      );
      expect(unmatchedBeforeLink, findsOneWidget);
      expect(
        tester
            .widget<PayrollReconciliationRow>(unmatchedBeforeLink)
            .data
            .canConfirm,
        isFalse,
        reason: 'A partial debit must not arrive as an automatic suggestion.',
      );
      final manualSelector = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Vincular a persona y semana',
      );
      expect(
        manualSelector,
        findsOneWidget,
        reason: 'The unmatched debit still needs an explicit manual-link path.',
      );
      await tester.ensureVisible(manualSelector);
      await tester.pumpAndSettle();
      await tester.tap(manualSelector);
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ana Rivas ·').last);
      await tester.pumpAndSettle();

      final partialRow = find.byWidgetPredicate(
        (widget) =>
            widget is PayrollReconciliationRow &&
            widget.data.kind == PayrollDecisionRowKind.unmatchedMovement &&
            widget.data.selectedManualLineId == 'line-ana',
      );
      expect(partialRow, findsOneWidget);
      final confirmPartial = find.descendant(
        of: partialRow,
        matching:
            find.widgetWithText(PayrollDecisionOptionCard, 'Es este pago'),
      );
      await tester.ensureVisible(confirmPartial);
      await tester.pumpAndSettle();
      await tester.tap(confirmPartial);
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: partialRow, matching: find.text('Pago parcial')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: partialRow,
          matching: find.text('Pago aplicado'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: partialRow,
          matching: find.text('Saldo después'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: partialRow,
          matching: find.text('Disposición: registrar pago parcial'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: partialRow,
          matching: find.widgetWithText(
              PayrollDecisionOptionCard, 'Dejar sin conciliar'),
        ),
        findsNothing,
        reason: 'An underpayment is a partial allocation, not an unresolved '
            'overpayment residue.',
      );
      await tester.enterText(
        find.descendant(
          of: partialRow,
          matching: find.widgetWithText(
            TextField,
            'Razón de confirmación',
          ),
        ),
        'Abono parcial validado contra la cartola.',
      );
      await tester.pumpAndSettle();

      await selectBankAccount(tester);
      await goToStage(tester, 'Aplicar');
      expect(find.textContaining('Registrar pago parcial'), findsOneWidget);
      expect(
          find.textContaining(r'quedan $150.000 pendientes'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(PayrollPrimaryAction, commitAndApplyLabel),
      );
      await tester.pumpAndSettle();

      final bankPayment = harness.decisions.single.singleWhere(
        (decision) => decision.kind == PayrollReviewDecisionKind.bankPayment,
      );
      expect(bankPayment.voucherLineId, 'line-ana');
      expect(
        bankPayment.amountClp,
        300000,
        reason: 'A manual partial allocation applies the bank debit, not the '
            'full obligation.',
      );
      expect(
        bankPayment.varianceDisposition,
        PayrollVarianceDisposition.partial,
      );
      expect(bankPayment.manualConfirmation, isTrue);
      expect(
        bankPayment.note,
        'Abono parcial validado contra la cartola.',
      );
    });

    testWidgets(
      'beneficiary learning is explicit and resets when the employee changes',
      (tester) async {
        final harness = recorder(
          prepared: draft(withAlternateTransferLine: true),
        );
        await pump(tester, actions: harness.actions);
        await loadStatement(tester);
        await reviewSuggestion(tester);

        const learningKey = ValueKey<String>(
          'payroll-alias-learning-p1-l1-r1',
        );
        expect(
          find.byKey(learningKey),
          findsNothing,
          reason: 'A matcher suggestion must never learn an alias implicitly.',
        );

        Future<void> selectManualEmployee(String employeeName) async {
          final selector = find.widgetWithText(
            DropdownButtonFormField<String>,
            'Vincular a persona y semana',
          );
          await tester.ensureVisible(selector);
          await tester.pumpAndSettle();
          await tester.tap(selector);
          await tester.pumpAndSettle();
          await tester.tap(find.textContaining('$employeeName ·').last);
          await tester.pumpAndSettle();
        }

        await selectManualEmployee('Bea Soto');

        Finder learningCheckbox() => find.descendant(
              of: find.byKey(learningKey),
              matching: find.byType(Checkbox),
            );

        expect(find.byKey(learningKey), findsOneWidget);
        expect(find.textContaining('Recordar'), findsOneWidget);
        expect(find.textContaining('Persona Depósito'), findsOneWidget);
        expect(tester.widget<Checkbox>(learningCheckbox()).value, isFalse);

        await tester.tap(learningCheckbox());
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(learningCheckbox()).value, isTrue);

        await selectManualEmployee('Ana Rivas');
        expect(
          find.byKey(learningKey),
          findsNothing,
          reason: 'Returning to the original suggestion is not a manual '
              'beneficiary correction.',
        );

        await selectManualEmployee('Bea Soto');
        expect(find.byKey(learningKey), findsOneWidget);
        expect(
          tester.widget<Checkbox>(learningCheckbox()).value,
          isFalse,
          reason: 'Changing the selected employee must clear prior consent.',
        );
      },
    );

    testWidgets('cash is answered person by person before applying',
        (tester) async {
      final harness = recorder(prepared: draft(withCashEmployee: true));
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      await confirmSuggestion(tester);
      await selectBankAccount(tester);
      expect(stageIsEnabled(tester, 4), isTrue);
      expect(primaryAction(tester, 'Ir a aplicar').onPressed, isNotNull);

      await goToStage(tester, 'Aplicar');
      expect(
        find.text('1 persona en efectivo sin elegir cómo se resolvió.'),
        findsWidgets,
      );
      // One person at a time: the equation card opens on demand.
      expect(find.text('¿Cómo quedó esta obligación?'), findsNothing);
      await openCashPerson(tester, 'Rosa Díaz');
      expect(find.text('¿Cómo quedó esta obligación?'), findsOneWidget);
      expect(find.textContaining('Pendiente'), findsWidgets);
      await tester.tap(
        find.widgetWithText(PayrollDecisionOptionCard, 'Todavía no pagado'),
      );
      await tester.pumpAndSettle();
      // Closing the person is explicit; nothing advances alone.
      await tester.tap(find.text('Confirmar respuesta'));
      await tester.pumpAndSettle();
      expect(find.text('¿Cómo quedó esta obligación?'), findsNothing);
      expect(find.textContaining('Todavía no pagado'), findsWidgets);

      await goToStage(tester, 'Aplicar');
      expect(find.textContaining('sin elegir cómo se resolvió'), findsNothing);
    });

    testWidgets(
        'one cash obligation can use two advances and pays only the remaining cash',
        (tester) async {
      final harness = recorder(
        prepared: draft(
          withCashEmployee: true,
          openAdvances: [
            cashAdvance(
              id: 'advance-oldest',
              amount: 30000,
              paidAt: DateTime(2026, 7, 10),
            ),
            cashAdvance(
              id: 'advance-newest',
              amount: 40000,
              paidAt: DateTime(2026, 7, 17),
            ),
          ],
        ),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);
      await goToStage(tester, 'Aplicar');
      await openCashPerson(tester, 'Rosa Díaz');

      await tester.tap(
          find.widgetWithText(PayrollDecisionOptionCard, 'Entregué efectivo'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cash-advance-advance-oldest')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cash-advance-advance-newest')),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining(r'Anticipo $70.000'),
        findsOneWidget,
      );
      expect(
        find.textContaining(r'Efectivo $50.000'),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirmar respuesta'));
      await tester.pumpAndSettle();
      await goToStage(tester, 'Aplicar');
      await tester.tap(find.text(commitAndApplyLabel));
      await tester.pumpAndSettle();

      final decisions = harness.decisions.single;
      final allocations = decisions
          .where(
            (decision) =>
                decision.kind == PayrollReviewDecisionKind.advanceAllocation,
          )
          .toList();
      expect(allocations, hasLength(2));
      expect(
        allocations.map((decision) => decision.advanceId),
        ['advance-oldest', 'advance-newest'],
      );
      expect(
        allocations.map((decision) => decision.amountClp),
        [30000, 40000],
      );

      final cash = decisions.singleWhere(
        (decision) => decision.kind == PayrollReviewDecisionKind.cashPayment,
      );
      expect(cash.voucherLineId, 'line-cash');
      expect(cash.amountClp, 50000);
    });

    testWidgets(
        'two advances that cover the obligation emit no zero-value cash payment',
        (tester) async {
      final harness = recorder(
        prepared: draft(
          withCashEmployee: true,
          openAdvances: [
            cashAdvance(
              id: 'advance-first-half',
              amount: 60000,
              paidAt: DateTime(2026, 7, 10),
            ),
            cashAdvance(
              id: 'advance-second-half',
              amount: 60000,
              paidAt: DateTime(2026, 7, 17),
            ),
          ],
        ),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);
      await goToStage(tester, 'Aplicar');
      await openCashPerson(tester, 'Rosa Díaz');

      await tester.tap(
          find.widgetWithText(PayrollDecisionOptionCard, 'Entregué efectivo'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cash-advance-advance-first-half')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cash-advance-advance-second-half')),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No se registrará efectivo nuevo'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cash-manual-amount')),
        findsNothing,
      );
      await tester.tap(find.text('Confirmar respuesta'));
      await tester.pumpAndSettle();
      await goToStage(tester, 'Aplicar');
      await tester.tap(find.text(commitAndApplyLabel));
      await tester.pumpAndSettle();

      final decisions = harness.decisions.single;
      expect(
        decisions
            .where(
              (decision) =>
                  decision.kind == PayrollReviewDecisionKind.advanceAllocation,
            )
            .map((decision) => decision.amountClp),
        [60000, 60000],
      );
      expect(
        decisions.where(
          (decision) => decision.kind == PayrollReviewDecisionKind.cashPayment,
        ),
        isEmpty,
      );
    });

    testWidgets(
        'cash rows identify the manual method, week, expected amount and action on phone',
        (tester) async {
      final harness = recorder(prepared: draft(withCashEmployee: true));
      await pump(
        tester,
        actions: harness.actions,
        size: const Size(390, 844),
      );
      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);
      await goToStage(tester, 'Aplicar');

      expect(find.text('Rosa Díaz'), findsWidgets);
      expect(find.textContaining('Efectivo manual'), findsWidgets);
      expect(find.textContaining('21 – 27 jul'), findsWidgets);
      expect(find.text('ESPERADO'), findsOneWidget);
      expect(find.text(r'$120.000'), findsWidgets);
      expect(find.text('Responder'), findsOneWidget);
      final cashRow = find.bySemanticsLabel(
        RegExp(
          r'Rosa Díaz.*efectivo manual.*21 – 27 jul.*'
          r'Monto esperado \$120\.000.*Sin responder.*Responder',
          caseSensitive: false,
        ),
      );
      expect(
        cashRow,
        findsOneWidget,
      );
      expect(
        tester.getSize(cashRow).height,
        greaterThanOrEqualTo(48),
      );

      await openCashPerson(tester, 'Rosa Díaz');
      expect(
        find.textContaining('esta respuesta no proviene del OCR'),
        findsOneWidget,
      );
      final cashPaymentChoice = find.widgetWithText(
        PayrollDecisionOptionCard,
        'Entregué efectivo',
      );
      await tester.ensureVisible(cashPaymentChoice);
      await tester.pumpAndSettle();
      await tester.tap(cashPaymentChoice);
      await tester.pumpAndSettle();

      final amount = find.byKey(const ValueKey('cash-manual-amount'));
      final date = find.byKey(const ValueKey('cash-manual-date'));
      expect(amount, findsOneWidget);
      expect(date, findsOneWidget);
      expect(tester.getSize(date).height, greaterThanOrEqualTo(48));
      expect(
        tester.getTopLeft(date).dy,
        greaterThan(tester.getBottomLeft(amount).dy),
        reason: 'Phone fields must stack instead of squeezing into one row.',
      );

      await tester.ensureVisible(amount);
      await tester.pumpAndSettle();
      await tester.tap(amount);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      await tester.ensureVisible(amount);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a missing canonical payment method blocks the batch',
        (tester) async {
      final harness = recorder(
        prepared: draft(missingCanonicalMethod: const {'employee-ana'}),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      expect(
        find.text('Falta definir cómo se paga'),
        findsOneWidget,
      );
      expect(find.text('Ana Rivas'), findsWidgets);
      expect(
        find.byKey(
          const ValueKey(
            'payroll-reconciliation-configure-method-employee-ana',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'configuring a missing method refreshes context and preserves decisions',
        (tester) async {
      final harness = recorder(
        prepared: draft(missingCanonicalMethod: const {'employee-ana'}),
        refreshed: draft(),
      );
      final configured = <String>[];
      await pump(
        tester,
        actions: harness.actions,
        onConfigureEmployeePaymentMethod: (employeeId) async {
          configured.add(employeeId);
        },
      );
      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);

      await tester.ensureVisible(
        find.byKey(
          const ValueKey(
            'payroll-reconciliation-configure-method-employee-ana',
          ),
        ),
      );
      await tester.tap(
        find.byKey(
          const ValueKey(
            'payroll-reconciliation-configure-method-employee-ana',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(configured, ['employee-ana']);
      expect(harness.calls, ['prepare', 'refresh']);
      expect(find.text('Falta definir cómo se paga'), findsNothing);
      await openResolved(tester);
      expect(
        tester
            .widget<PayrollReviewTableRow>(
              find.byKey(const ValueKey('payroll-ledger-p1-l1-r1')),
            )
            .stateTag,
        'CONFIRMADO',
      );
      expect(
        find.textContaining('Conservamos las decisiones'),
        findsOneWidget,
      );
    });

    testWidgets(
        'a movement after the declared close remains confirmable with explicit review',
        (tester) async {
      final harness = recorder(
        prepared: draft(
          documentDate: const PayrollCivilDate(2026, 7, 27),
        ),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      // Exige una razón escrita: no es batch-safe, así que encabeza la etapa
      // como pregunta en vez de vivir en «Calces sugeridos».
      expect(
        find.text('Fecha posterior al cierre declarado'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(PayrollDecisionOptionCard, 'Es este pago'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Razón de confirmación'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Razón de confirmación'),
        'El movimiento aparece íntegro en la cartola cargada.',
      );
      await selectBankAccount(tester);
      await goToStage(tester, 'Aplicar');

      final action = tester.widget<PayrollPrimaryAction>(
        find.widgetWithText(PayrollPrimaryAction, commitAndApplyLabel),
      );
      expect(action.onPressed, isNotNull);
    });

    testWidgets(
        'an already-resolved row names duplicate protection instead of a date error',
        (tester) async {
      final harness = recorder(prepared: draft(alreadyResolved: true));
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      expect(find.text('Movimiento ya conciliado'), findsOneWidget);
      expect(
        find.text('Protegido contra pago duplicado'),
        findsOneWidget,
      );
      expect(find.text('Fecha posterior al cierre declarado'), findsNothing);
      expect(find.widgetWithText(PayrollDecisionOptionCard, 'Ya conciliado'),
          findsOneWidget);
    });
  });

  group('commit', () {
    testWidgets('an already committed week keeps the simple apply action',
        (tester) async {
      final harness = recorder(
        prepared: draft(voucherStatus: PayrollVoucherStatus.confirmed),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await confirmSuggestion(tester);
      await selectBankAccount(tester);
      await goToStage(tester, 'Aplicar');

      expect(
        find.byKey(const ValueKey('payroll-draft-commitment-summary')),
        findsNothing,
      );
      expect(
        find.widgetWithText(PayrollPrimaryAction, 'Aplicar conciliación'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(PayrollPrimaryAction, 'Aplicar conciliación'),
      );
      await tester.pumpAndSettle();
      expect(harness.authorizedDraftVoucherIds, <Set<String>>[<String>{}]);
      expect(find.text('Conciliación registrada.'), findsOneWidget);
    });

    testWidgets('imports once, applies once, and reports the outcome',
        (tester) async {
      final harness = recorder();
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      await confirmSuggestion(tester);
      await selectBankAccount(tester);
      await goToStage(tester, 'Aplicar');
      expect(
        find.byKey(const ValueKey('payroll-draft-commitment-summary')),
        findsOneWidget,
      );
      expect(find.textContaining('1 semana borrador'), findsOneWidget);
      expect(
        find.textContaining('reconoce sus sueldos por pagar'),
        findsOneWidget,
      );
      await tester.tap(find.text(commitAndApplyLabel));
      await tester.pumpAndSettle();

      expect(harness.calls, ['prepare', 'createImport', 'apply']);
      expect(
        find.text(
          '1 semana confirmada y conciliación registrada.',
        ),
        findsOneWidget,
      );
      expect(find.text('1 semana confirmada'), findsOneWidget);
      expect(
        harness.authorizedDraftVoucherIds,
        <Set<String>>[
          <String>{'voucher-1'},
        ],
      );

      final decisions = harness.decisions.single;
      expect(decisions, hasLength(1));
      expect(decisions.single.kind, PayrollReviewDecisionKind.bankPayment);
      expect(decisions.single.voucherLineId, 'line-ana');
    });

    testWidgets('a retry reuses the import and the apply operation key',
        (tester) async {
      final harness = recorder(failFirstApply: true);
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      await confirmSuggestion(tester);
      await selectBankAccount(tester);
      await goToStage(tester, 'Aplicar');

      await tester.tap(find.text(commitAndApplyLabel));
      await tester.pumpAndSettle();
      expect(find.textContaining('red caída'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Reintentar'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Reintentar'));
      await tester.pumpAndSettle();

      // The import is created once; the apply key is stable across retries so
      // the server can recognize a replay instead of duplicating money.
      expect(
        harness.calls,
        ['prepare', 'createImport', 'apply', 'apply'],
      );
      expect(harness.applyKeys.first, harness.applyKeys.last);
      expect(harness.applyKeys.first, isNotEmpty);
    });

    testWidgets(
        'a deterministic conflict disables apply and offers reload instead of retry',
        (tester) async {
      var applyAttempts = 0;
      final base = recorder();
      final actions = PayrollReconciliationActions(
        isImageOcrSupported: base.actions.isImageOcrSupported,
        isCameraCaptureSupported: base.actions.isCameraCaptureSupported,
        prepare: base.actions.prepare,
        createImport: base.actions.createImport,
        apply: ({
          required draft,
          required importReceipt,
          required decisions,
          required authorizedDraftVoucherIds,
          operationKey,
        }) async {
          applyAttempts++;
          throw const PayrollReconciliationServiceException(
            'La conciliación cambió mientras la revisabas.',
            recoveryAction: PayrollReconciliationRecoveryAction.reload,
          );
        },
      );
      await pump(tester, actions: actions);
      await loadStatement(tester);

      await confirmSuggestion(tester);
      await selectBankAccount(tester);
      await goToStage(tester, 'Aplicar');
      await tester.tap(find.text(commitAndApplyLabel));
      await tester.pumpAndSettle();

      expect(applyAttempts, 1);
      expect(find.widgetWithText(TextButton, 'Reintentar'), findsNothing);
      expect(
        find.widgetWithText(TextButton, 'Salir y recargar'),
        findsOneWidget,
      );
      expect(
        primaryAction(tester, commitAndApplyLabel).onPressed,
        isNull,
      );
    });

    testWidgets('a replay acknowledgement is treated as success',
        (tester) async {
      final harness = recorder(replay: true);
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      await confirmSuggestion(tester);
      await selectBankAccount(tester);
      await goToStage(tester, 'Aplicar');
      await tester.tap(find.text(commitAndApplyLabel));
      await tester.pumpAndSettle();

      expect(find.textContaining('ya estaba registrada'), findsOneWidget);
      expect(find.textContaining('No se duplicó nada'), findsOneWidget);
    });

    testWidgets(
        'the final receipt exposes replay truth, week and action counts, identifiers and evidence navigation',
        (tester) async {
      final harness = recorder(
        replay: true,
        prepared: draft(
          withCashEmployee: true,
          openAdvances: [
            cashAdvance(
              id: 'advance-receipt-oldest',
              amount: 30000,
              paidAt: DateTime(2026, 7, 10),
            ),
            cashAdvance(
              id: 'advance-receipt-newest',
              amount: 40000,
              paidAt: DateTime(2026, 7, 17),
            ),
          ],
        ),
        applyRaw: const <String, dynamic>{
          'status': 'applied',
          'decision_count': 4,
          'allocation_count': 4,
          'voucher_versions': <String, dynamic>{'voucher-1': 1},
        },
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);
      await selectBankAccount(tester);
      await confirmSuggestion(tester);
      await goToStage(tester, 'Aplicar');
      await openCashPerson(tester, 'Rosa Díaz');
      await tester.tap(
          find.widgetWithText(PayrollDecisionOptionCard, 'Entregué efectivo'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cash-advance-advance-receipt-oldest')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('cash-advance-advance-receipt-newest')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar respuesta'));
      await tester.pumpAndSettle();
      await goToStage(tester, 'Aplicar');
      await tester.tap(find.text(commitAndApplyLabel));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Esta conciliación ya estaba registrada. No se duplicó nada.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('devolvió su resultado anterior'),
        findsOneWidget,
      );
      expect(find.text('1 semana'), findsOneWidget);
      expect(find.text('1 transferencia'), findsOneWidget);
      expect(find.text('1 efectivo'), findsOneWidget);
      expect(find.text('2 anticipos'), findsOneWidget);
      expect(find.text('Importación'), findsOneWidget);
      expect(find.text('import-1'), findsOneWidget);
      expect(find.text('Operación'), findsOneWidget);
      expect(find.text('operation-key-1:apply'), findsOneWidget);
      expect(find.text('Ver semanas y evidencia'), findsOneWidget);
    });
  });

  group('return contract and responsive composition', () {
    testWidgets('un borrador se cierra con copy honesto y confirmación',
        (tester) async {
      final harness = recorder();
      final router = await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      expect(find.text('Salir sin guardar'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('reconciliation-close')),
      );
      await tester.pumpAndSettle();

      expect(find.text('¿Salir de la conciliación?'), findsOneWidget);
      expect(
        find.textContaining('Se perderán las decisiones'),
        findsOneWidget,
      );
      await tester.tap(find.text('Seguir revisando'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/hr/payroll/reconcile',
      );

      await tester.tap(
        find.byKey(const ValueKey('reconciliation-close')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salir sin guardar').last);
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/hr/payroll',
      );
    });

    testWidgets('closing returns to the host instead of replacing it',
        (tester) async {
      final harness = recorder();
      final router = await pump(tester, actions: harness.actions);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      // Nothing to pop in this harness, so it lands on the declared fallback.
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/hr/payroll',
      );
    });

    testWidgets('renders one row per decision on phone without panning',
        (tester) async {
      final harness = recorder(
        prepared: draft(withUnmatchedMovement: true, variance: 250),
      );
      await pump(
        tester,
        actions: harness.actions,
        size: const Size(390, 844),
      );
      await loadStatement(tester);

      final automaticGroup = find.byKey(
        const ValueKey('review-group-automatic'),
      );
      await tester.scrollUntilVisible(
        automaticGroup,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(automaticGroup);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('PAGO PROVEEDOR GENERICO'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(PayrollReviewTableRow), findsWidgets);
      final horizontal = find
          .byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
          )
          .evaluate();
      expect(horizontal, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'the 2c shell exposes one header owner and full capture semantics across 899/900',
        (tester) async {
      for (final size in const <Size>[
        Size(390, 844),
        Size(899, 900),
        Size(900, 900),
        Size(1440, 900),
      ]) {
        final harness = recorder(cameraCaptureSupported: true);
        await pump(tester, actions: harness.actions, size: size);
        final semantics = tester.ensureSemantics();

        expect(find.byType(PayrollReconciliationSurface), findsOneWidget);
        expect(
          find.byKey(const ValueKey('reconciliation-workflow-header')),
          size.width < 900 ? findsNothing : findsOneWidget,
          reason: size.width < 900
              ? 'MainLayout already owns the compact route header.'
              : 'Desktop needs the reconciliation workflow header.',
        );
        expect(find.bySemanticsLabel('Subir cartola'), findsWidgets);
        expect(find.bySemanticsLabel(RegExp('^Extraer')), findsWidgets);
        expect(find.bySemanticsLabel(RegExp('^Revisar')), findsWidgets);
        expect(find.bySemanticsLabel(RegExp('^Aplicar')), findsWidgets);
        expect(find.text('Elegir archivo'), findsOneWidget);
        expect(find.text('Cámara'), findsOneWidget);
        expect(find.text('Galería'), findsOneWidget);

        for (final label in const <String>[
          'Elegir archivo',
          'Cámara',
          'Galería',
        ]) {
          final target = find.ancestor(
            of: find.text(label),
            matching: find.byWidgetPredicate(
              (widget) => widget is ButtonStyleButton,
            ),
          );
          expect(target, findsOneWidget);
          expect(
            tester.getSize(target).height,
            greaterThanOrEqualTo(48),
            reason: '$label touch target at ${size.width}px',
          );
        }

        expect(
          find.byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      }
    });

    testWidgets('review state survives a live desktop-phone-desktop resize',
        (tester) async {
      final harness = recorder();
      await pump(
        tester,
        actions: harness.actions,
        size: const Size(900, 900),
      );
      await loadStatement(tester);
      await confirmSuggestion(tester);

      Future<void> expectConfirmed() async {
        // El calce confirmado vive en «Ya respondidos», que nace plegado en
        // cada recomposición: hay que abrirlo antes de leer su fila.
        await openResolved(tester);
        final row = find.byKey(const ValueKey('payroll-ledger-p1-l1-r1'));
        if (row.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            row,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
        }
        expect(
          tester.widget<PayrollReviewTableRow>(row).stateTag,
          'CONFIRMADO',
        );
      }

      await expectConfirmed();

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(PayrollReconciliationSurface), findsOneWidget);
      await expectConfirmed();
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      expect(find.byType(PayrollReconciliationSurface), findsOneWidget);
      await expectConfirmed();
      expect(tester.takeException(), isNull);
    });

    testWidgets('crosses every declared boundary without overflowing',
        (tester) async {
      for (final size in const [
        Size(384, 824),
        Size(599, 900),
        Size(600, 900),
        Size(834, 1112),
        Size(899, 900),
        Size(900, 900),
        Size(1000, 900),
        Size(1440, 900),
      ]) {
        final harness = recorder(
          prepared: draft(withCashEmployee: true, withUnmatchedMovement: true),
        );
        // Colector propio: si algo desborda, el fallo nombra al widget.
        final collected = <FlutterErrorDetails>[];
        final prior = FlutterError.onError;
        FlutterError.onError = collected.add;
        try {
          await pump(tester, actions: harness.actions, size: size);
          await loadStatement(tester);
          await selectBankAccount(tester);
          await confirmSuggestion(tester);
          await goToStage(tester, 'Aplicar');
          await openCashPerson(tester, 'Rosa Díaz');
        } finally {
          FlutterError.onError = prior;
        }
        final creators = collected
            .map((d) =>
                d.informationCollector
                    ?.call()
                    .map((e) => e.toString())
                    .firstWhere((t) => t.contains('debugCreator'),
                        orElse: () => '') ??
                '')
            .where((t) => t.isNotEmpty)
            .join(' || ');
        tester.takeException();
        expect(
          collected,
          isEmpty,
          reason: 'overflow at ${size.width}x${size.height}: '
              '${collected.map((d) => d.exception).join('; ')} :: $creators',
        );
      }
    });
  });
}

class _SensitiveExtractionFailure implements Exception {
  const _SensitiveExtractionFailure();

  static const ocrText = 'TEXTO_OCR_SECRETO_NO_LOGGEAR';
  static const accountNumber = '0000111122223333';

  @override
  String toString() => '$ocrText cuenta $accountNumber';
}
