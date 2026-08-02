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
    Brightness brightness = Brightness.light,
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
        find.widgetWithText(PayrollPrimaryAction, 'Ver propuestas de pago');
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
      'Propuestas',
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

  /// Toca desplazando primero.
  ///
  /// Desde que el paso 4 adoptó la composición de tres columnas del frame 5j,
  /// la tarjeta de efectivo vive en una columna del ancho que Design le da a su
  /// propia hoja de efectivo (480), así que es **más alta que el viewport** y
  /// sus controles caen bajo el pliegue. Un `tap` sobre algo fuera de pantalla
  /// no falla: **avisa y no entrega el evento**, y la prueba sigue creyendo que
  /// tocó. Desplazar antes es conducir la pantalla, no relajar la aserción.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    await tester.tap(finder.first);
    await tester.pumpAndSettle();
  }

  /// Opens the active cash card for one person in the cash stage.
  Future<void> openCashPerson(WidgetTester tester, String name) async {
    await tapVisible(tester, find.text(name));
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

  group('5j · paso 3 · la pregunta respondida SE VA al avanzar', () {
    // El contrato lo escribió el propio código al responder: «Answering does
    // not make the question vanish… It leaves only on "next question".»
    // `_moveQuestion` sólo movía el índice y **nunca sacaba la fila de
    // `_answeredInPlaceRowIds`**, así que la promesa no se cumplía: la tarjeta
    // respondida seguía en la pila «Pendiente de decisión», el denominador del
    // contador no bajaba nunca, y para llegar a una sin responder había que
    // recorrer la lista entera y después caminar hacia atrás. Se vio
    // recorriendo las 10 decisiones en la app viva el 2026-08-01.
    int denominator(WidgetTester tester) {
      final label = tester
          .widgetList<Text>(find.textContaining(' DE '))
          .map((text) => text.data)
          .whereType<String>()
          .firstWhere((data) => RegExp(r'^\d+ DE \d+$').hasMatch(data));
      return int.parse(label.split(' DE ').last);
    }

    testWidgets('responder NO la hace desaparecer: se queda hasta avanzar',
        (tester) async {
      final harness = recorder(
        prepared: draft(
          withUnmatchedMovement: true,
          withIncompleteEvidence: true,
        ),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      final before = denominator(tester);
      await tester.tap(find.text('No es nómina').first);
      await tester.pumpAndSettle();

      // La mitad deliberada del contrato: la fila se queda para que el
      // operador vea lo que acaba de decidir y complete lo que le falte.
      expect(denominator(tester), before);
      expect(
        find.byType(PayrollNoPendingDecisionsCard),
        findsNothing,
        reason: 'responder no vacía la etapa por sí solo',
      );
    });

    /// Dos preguntas abiertas a la vez: sin eso `Anterior` viene deshabilitado
    /// por el guard `index > 0` y no hay nada que probar.
    PayrollStatementPreparedDraft twoOpenQuestions() => draft(
          withAlternateTransferLine: true,
          withPayrollNamedUnmatchedMovement: true,
        );

    testWidgets('«Anterior» NO la suelta: se vuelve para mirarla otra vez',
        (tester) async {
      // El contrato dice «It leaves only on "next question"». Si retroceder
      // también la sacara de la pila, volver a mirar lo recién decidido sería
      // imposible — y la flecha izquierda dejaría de tener sentido.
      final harness = recorder(prepared: twoOpenQuestions());
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      final before = denominator(tester);
      expect(before, greaterThan(1));

      // Voy a la segunda, la respondo, y vuelvo con «Anterior».
      await tester.tap(find.bySemanticsLabel('Siguiente pregunta').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('No es nómina').first);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Pregunta anterior').first);
      await tester.pumpAndSettle();

      expect(
        denominator(tester),
        before,
        reason: 'retroceder no suelta nada: la respondida sigue en la pila '
            'para poder volver a ella',
      );
    });

    // **La limpieza de `_stagedQuestionRowId` en `_moveQuestion` NO tiene
    // regresión, y se dice.** El arreglo está puesto —sin él, con una fila en
    // revisión la flecha mueve el índice y la tarjeta no cambia—, pero
    // provocar ese estado exige que una fila pendiente que no encabeza exponga
    // su acción de reapertura, y en los fixtures de este archivo esa acción no
    // se renderiza sin expandir grupos que el arnés no arma. Se intentó y no
    // muerde, así que **no se cuenta como cubierto**.

    testWidgets('en la ÚLTIMA pregunta, avanzar también la suelta',
        (tester) async {
      // El guard anterior apagaba «Siguiente» en el último índice, así que la
      // última tarjeta respondida quedaba clavada y sin forma de sacarla.
      final harness = recorder(
        prepared: draft(
          withUnmatchedMovement: true,
          withIncompleteEvidence: true,
        ),
      );
      await pump(tester, actions: harness.actions);
      await loadStatement(tester);

      var guard = 0;
      while (denominator(tester) > 1 && guard < 30) {
        guard += 1;
        await tester.tap(find.text('No es nómina').first);
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Siguiente pregunta').first);
        await tester.pumpAndSettle();
      }
      expect(denominator(tester), 1);

      await tester.tap(find.text('No es nómina').first);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Siguiente pregunta').first);
      await tester.pumpAndSettle();

      expect(
        find.byType(PayrollNoPendingDecisionsCard),
        findsOneWidget,
        reason: 'sin preguntas abiertas la etapa lo dice; no deja una tarjeta '
            'respondida haciéndose pasar por pendiente',
      );
    });
  });

  group('file stage', () {
    testWidgets('preparing a statement moves to the transfer review',
        (tester) async {
      final harness = recorder();
      await pump(tester, actions: harness.actions);

      expect(find.byType(PayrollReconciliationSurface), findsOneWidget);
      expect(find.text('Carga la cartola'), findsOneWidget);
      await loadStatement(tester);

      expect(harness.calls, ['prepare']);
      expect(
          find.textContaining(RegExp('[Pp]ropuestas de pago')), findsWidgets);
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
      expect(
          find.textContaining(RegExp('[Pp]ropuestas de pago')), findsWidgets);
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
      expect(
          find.textContaining(RegExp('[Pp]ropuestas de pago')), findsWidgets);
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
      expect(
          find.textContaining(RegExp('[Pp]ropuestas de pago')), findsWidgets);
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
      await goToStage(tester, 'Cargar cartola');
      expect(find.text('Carga la cartola'), findsOneWidget);
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
      expect(
          find.textContaining(RegExp('[Pp]ropuestas de pago')), findsWidgets);
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
      await tapVisible(
        tester,
        find.widgetWithText(PayrollDecisionOptionCard, 'Todavía no pagado'),
      );
      // Closing the person is explicit; nothing advances alone.
      await tapVisible(tester, find.text('Confirmar respuesta'));
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

      await tapVisible(tester,
          find.widgetWithText(PayrollDecisionOptionCard, 'Entregué efectivo'));
      await tapVisible(
        tester,
        find.byKey(const ValueKey('cash-advance-advance-oldest')),
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('cash-advance-advance-newest')),
      );

      expect(
        find.textContaining(r'Anticipo $70.000'),
        findsOneWidget,
      );
      expect(
        find.textContaining(r'Efectivo $50.000'),
        findsOneWidget,
      );
      await tapVisible(tester, find.text('Confirmar respuesta'));
      await goToStage(tester, 'Aplicar');
      await tapVisible(tester, find.text(commitAndApplyLabel));

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

      await tapVisible(tester,
          find.widgetWithText(PayrollDecisionOptionCard, 'Entregué efectivo'));
      await tapVisible(
        tester,
        find.byKey(const ValueKey('cash-advance-advance-first-half')),
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('cash-advance-advance-second-half')),
      );

      expect(
        find.textContaining('No se registrará efectivo nuevo'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cash-manual-amount')),
        findsNothing,
      );
      await tapVisible(tester, find.text('Confirmar respuesta'));
      await goToStage(tester, 'Aplicar');
      await tapVisible(tester, find.text(commitAndApplyLabel));

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
      await tapVisible(tester,
          find.widgetWithText(PayrollDecisionOptionCard, 'Entregué efectivo'));
      await tapVisible(
        tester,
        find.byKey(const ValueKey('cash-advance-advance-receipt-oldest')),
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('cash-advance-advance-receipt-newest')),
      );
      await tapVisible(tester, find.text('Confirmar respuesta'));
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
      // **Se asegura la visibilidad ANTES de tocar.** `scrollUntilVisible` deja
      // el objetivo dentro del árbol pero puede quedar bajo la barra de dinero,
      // y entonces `tap` avisa «finds no widget at the hit test location», el
      // evento no llega y el `scrollUntilVisible` siguiente revienta con «Bad
      // state: No element». Eso NO es un defecto del producto: es conducción
      // del arnés, y confundirlo cuesta una ronda entera.
      await tester.ensureVisible(automaticGroup);
      await tester.pumpAndSettle();
      await tester.tap(automaticGroup, warnIfMissed: false);
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
        expect(find.bySemanticsLabel('Cargar cartola'), findsWidgets);
        expect(find.bySemanticsLabel(RegExp('^Lectura')), findsWidgets);
        expect(find.bySemanticsLabel(RegExp('^Propuestas')), findsWidgets);
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

  testWidgets(
      '5j paso 2 · una nómina abierta FUERA del rango de la cartola no se anuncia como cubierta',
      (tester) async {
    // `vouchersById` trae todas las nóminas abiertas del tenant, no las que la
    // cartola cubre. El rótulo tiene que decir eso y no otra cosa.
    final harness = recorder(
      prepared: draft(documentDate: const PayrollCivilDate(2026, 7, 20)),
    );
    await pump(tester, actions: harness.actions);
    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();

    expect(find.text('Semanas que cubre'), findsNothing,
        reason: 'la cartola no determina esa lista; son nóminas abiertas');
    expect(find.text('Nóminas abiertas que se compararán'), findsOneWidget);
  });

  testWidgets(
      '5j paso 2 · un abono completo NO desaparece porque exista una fila incompleta',
      (tester) async {
    // El bug que el test anterior no veía: la política mostraba «las que piden
    // atención, o todas si no hay ninguna», así que **una sola fila incompleta
    // borraba todos los abonos** — mientras la nota prometía que se muestran
    // uno a uno.
    final incoming = PayrollStatementRow(
      bookingDate: const PayrollCivilDate(2026, 7, 15),
      description: 'ABONO VENTA WEBPAY',
      documentNumber: 'WP-1',
      debitAmountClp: null,
      creditAmountClp: 90000,
      balanceAmountClp: null,
      direction: PayrollStatementMovementDirection.incoming,
      evidence: const PayrollStatementRowEvidence(
        sourceRowNumber: 900,
        startPageNumber: 1,
        startLineNumber: 900,
        endPageNumber: 1,
        endLineNumber: 900,
      ),
    );
    // Conteo CONOCIDO y medido, no supuesto: el fixture rinde 9 filas —las del
    // draft base, una incompleta, un abono y seis egresos limpios—, de las que
    // 2 son obligatorias (incompleta y abono); se rellena hasta las 4
    // publicadas y quedan **5 ocultas**. Mi primera estimación decía 6: por eso
    // el número va exacto en el aserto y no dentro de un `if`.
    final harness = recorder(
      prepared: draft(
        withIncompleteEvidence: true,
        extraRows: <PayrollStatementRow>[
          incoming,
          for (var i = 1; i <= 6; i++)
            statementRow(
              rowNumber: 500 + i,
              description: 'PAGO PROVEEDOR LIMPIO $i',
              debit: 10000 * i,
            ),
        ],
      ),
    );
    await pump(tester, actions: harness.actions, size: const Size(1440, 2000));
    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();

    expect(find.text('ABONO VENTA WEBPAY'), findsOneWidget,
        reason: 'el abono se promete visible uno a uno');
    expect(find.text('CAMPOS INCOMPLETOS'), findsWidgets,
        reason: 'y la fila que pide atención sigue estando');
    // **Sin condicional**: el pie tiene que existir y decir el número exacto.
    // La versión anterior lo envolvía en un `if` y el fixture no producía pie,
    // así que el test pasaba sin comprobar nada.
    expect(
      find.text('… 5 egresos más con todos sus campos reconocidos y sin '
          'avisos.'),
      findsOneWidget,
    );
    expect(find.textContaining('Todos quedan en la revisión'), findsNothing,
        reason: 'no todos los movimientos alimentan la revisión');
    // Un egreso limpio concreto SÍ está oculto; los obligatorios no.
    expect(find.text('PAGO PROVEEDOR LIMPIO 6'), findsNothing);
  });

  testWidgets(
      '5j paso 2 · cinco nóminas abiertas se listan en orden CRONOLÓGICO y caben en el panel',
      (tester) async {
    // El test anterior decía «varias» y usaba un fixture con **una sola**: no
    // probaba ni el orden ni el ancho que yo había afirmado. Acá van cinco,
    // insertadas fuera de orden a propósito, y a 1360 —donde el panel derecho
    // mide 320 px, que es el caso estrecho real—.
    final harness = recorder(
      prepared: draft(
        extraOpenPayrollStarts: <DateTime>[
          DateTime(2026, 9, 7),
          DateTime(2026, 6, 1),
          DateTime(2026, 12, 21),
          DateTime(2026, 8, 3),
        ],
      ),
    );
    await pump(tester, actions: harness.actions, size: const Size(1360, 1200));
    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();

    expect(find.text('Nóminas abiertas que se compararán'), findsOneWidget);
    // El valor del `factRow` es el hermano del rótulo dentro de su fila.
    final value = tester
        .widgetList<Text>(
          find.descendant(
            of: find
                .ancestor(
                  of: find.text('Nóminas abiertas que se compararán'),
                  matching: find.byType(Row),
                )
                .first,
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data)
        .whereType<String>()
        .firstWhere((data) => data != 'Nóminas abiertas que se compararán');
    final weeks = value.split(' · ');
    expect(weeks.length, 5, reason: 'las cinco nóminas abiertas se listan');
    // Orden por `periodStart`: los cinco períodos se insertaron desordenados
    // (jul, sep, jun, dic, ago) y tienen que salir de junio a diciembre.
    final months = weeks
        .map((w) => const <String>[
              'ene',
              'feb',
              'mar',
              'abr',
              'may',
              'jun',
              'jul',
              'ago',
              'sep',
              'oct',
              'nov',
              'dic',
            ].indexWhere((m) => w.toLowerCase().contains(m)))
        .toList();
    expect(months.any((m) => m < 0), isFalse, reason: 'etiquetas: $weeks');
    expect(
      months,
      List<int>.from(months)..sort(),
      reason: 'orden lexicográfico sobre la etiqueta no es cronológico: $weeks',
    );
    expect(tester.takeException(), isNull,
        reason: 'el panel de 320 px no puede desbordar con cinco nóminas');
  });

  testWidgets(
      '5j paso 2 · una fila fuera del rango pide REVISIÓN, no releer el OCR',
      (tester) async {
    final harness = recorder(
      prepared: draft(documentDate: const PayrollCivilDate(2026, 7, 20)),
    );
    await pump(tester, actions: harness.actions);
    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();

    expect(find.text('Requieren revisión'), findsOneWidget);
    expect(find.textContaining('Requieren tu lectura'), findsNothing,
        reason: '`out_of_statement_range` no se arregla releyendo el OCR');
  });

  testWidgets(
      '5j paso 2 · un abono completo no promete una sección «Otros movimientos»',
      (tester) async {
    // `_buildTransferRows` arma la revisión con egresos sin calzar y filas de
    // campos incompletos: un abono COMPLETO no entra ahí. La nota no puede
    // mandar al operador a una sección que este flujo no construye.
    final incoming = PayrollStatementRow(
      bookingDate: const PayrollCivilDate(2026, 7, 15),
      description: 'ABONO VENTA WEBPAY',
      documentNumber: 'WP-1',
      debitAmountClp: null,
      creditAmountClp: 90000,
      balanceAmountClp: null,
      direction: PayrollStatementMovementDirection.incoming,
      evidence: const PayrollStatementRowEvidence(
        sourceRowNumber: 900,
        startPageNumber: 1,
        startLineNumber: 900,
        endPageNumber: 1,
        endLineNumber: 900,
      ),
    );
    final harness = recorder(
      prepared: draft(extraRows: <PayrollStatementRow>[incoming]),
    );
    await pump(tester, actions: harness.actions, size: const Size(1440, 2000));
    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Otros movimientos'), findsNothing,
        reason: 'esa sección no existe en este flujo');
    expect(
      find.textContaining('Se muestran uno a uno en esta lectura'),
      findsOneWidget,
    );
    // Y el abono sí se ve en la lectura del paso 2, que es lo que se promete.
    expect(find.text('ABONO VENTA WEBPAY'), findsOneWidget);
  });

  testWidgets(
      '5j paso 2 · genera las seis capturas de HARNESS (claro/oscuro × 1360/834/430)',
      (tester) async {
    // **Evidencia de HARNESS, no viva.** La etapa 2 sólo existe con una cartola
    // cargada, y cargar una es subir un archivo real a un flujo que corre
    // contra producción. Así que las seis celdas se generan acá, con el fixture
    // sintético, y se declaran como tales — no se maquilla la matriz.
    // **Opt-in.** Sin `PAYROLL_SHOT_DIR` la suite no escribe artefactos: una
    // batería de regresión no deja archivos por ahí como efecto colateral.
    final target = Platform.environment['PAYROLL_SHOT_DIR'];
    if (target == null || target.isEmpty) {
      markTestSkipped('define PAYROLL_SHOT_DIR para generar las capturas');
      return;
    }
    suspendGoogleFontsNetwork();
    final dir = Directory(target);
    for (final brightness in Brightness.values) {
      for (final width in const <double>[1360, 834, 430]) {
        // Fixture que **demuestra la política**: una incompleta, un abono
        // completo y egresos limpios de sobra, para que se vean cuatro filas y
        // quede resumen. Con el fixture anterior salían dos y ningún pie, así
        // que las capturas no probaban lo que el ledger afirmaba.
        final harness = recorder(
          prepared: draft(
            withIncompleteEvidence: true,
            extraRows: <PayrollStatementRow>[
              PayrollStatementRow(
                bookingDate: const PayrollCivilDate(2026, 7, 15),
                description: 'ABONO VENTA WEBPAY',
                documentNumber: 'WP-1',
                debitAmountClp: null,
                creditAmountClp: 90000,
                balanceAmountClp: null,
                direction: PayrollStatementMovementDirection.incoming,
                evidence: const PayrollStatementRowEvidence(
                  sourceRowNumber: 900,
                  startPageNumber: 1,
                  startLineNumber: 900,
                  endPageNumber: 1,
                  endLineNumber: 900,
                ),
              ),
              for (var i = 1; i <= 6; i++)
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
        await tester.tap(find.text('Elegir archivo'));
        await tester.pumpAndSettle();

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
            '${dir.path}/paso2-${brightness.name}-${width.toInt()}.png',
          ).writeAsBytesSync(data.buffer.asUint8List());
        });
      }
    }
    // Exactamente seis, y contando **sólo las de este generador**: un
    // `greaterThanOrEqualTo` sobre el directorio entero daba verde con un
    // destino contaminado —o con cinco propias y una ajena—, que es justo lo
    // que el contrato del comando promete que no puede pasar.
    expect(
      dir
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith('paso2-'))
          .length,
      6,
    );
  });

  // ── 5j · paso 2 · lo que la extracción PUEDE afirmar ──────────────────────
  // Fixture SINTÉTICO y determinista: ningún archivo real, ninguna importación
  // viva. Lo que se prueba es el lenguaje de la etapa, que es donde el módulo
  // se puede pasar de afirmación.
  testWidgets(
      '5j paso 2 · una fila sin avisos dice CAMPOS COMPLETOS, nunca NÍTIDA',
      (tester) async {
    final harness = recorder(prepared: draft());
    await pump(tester, actions: harness.actions);
    // Sólo hasta la etapa 2: `loadStatement` sigue de largo hacia la revisión.
    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();

    // Ningún vocabulario de confianza o calidad: el extractor no mide nada de
    // eso. Sólo hechos comprobables sobre los campos.
    for (final banned in const <String>[
      'NÍTIDA',
      'nítida',
      'ILEGIBLE',
      'LECTURA DUDOSA',
    ]) {
      expect(find.textContaining(banned), findsNothing, reason: banned);
    }
    expect(find.text('CAMPOS COMPLETOS'), findsWidgets);
    // «N de N líneas leídas» era tautológico: el parse sólo conserva lo que
    // detectó, no hay total del documento con el que comparar.
    expect(find.textContaining('líneas leídas'), findsNothing);
    // Singular o plural según el fixture: lo que importa es que ya no
    // compare contra un total que no existe.
    expect(find.textContaining('detectado'), findsWidgets);
    // Y el panel no puede llamar «semanas que cubre» a las nóminas abiertas.
    expect(find.text('Semanas que cubre'), findsNothing);
    expect(find.text('Nóminas abiertas que se compararán'), findsOneWidget);
  });

  testWidgets(
      '5j paso 2 · una fila sin evidencia estructurada dice CAMPOS INCOMPLETOS',
      (tester) async {
    final harness = recorder(prepared: draft(withIncompleteEvidence: true));
    await pump(tester, actions: harness.actions);
    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();

    // `hasCompleteStructuredEvidence` sólo exige fecha, dirección, monto
    // positivo y descripción: su `false` prueba que FALTAN CAMPOS, no que el
    // OCR fuera incapaz de leer.
    expect(find.text('CAMPOS INCOMPLETOS'), findsWidgets);
    expect(find.textContaining('ILEGIBLE'), findsNothing);
  });

  testWidgets(
      '5j paso 2 · un aviso que no es de lectura no se rotula como lectura dudosa',
      (tester) async {
    // `out_of_statement_range` marca una fila COMPLETA cuya fecha cae después
    // del cierre declarado. No dice nada de la calidad de lectura, así que
    // llamarla «LECTURA DUDOSA» era falso para esa fila.
    final harness = recorder(
      prepared: draft(documentDate: const PayrollCivilDate(2026, 7, 20)),
    );
    await pump(tester, actions: harness.actions);
    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();

    expect(find.text('REVISAR'), findsWidgets);
    expect(find.textContaining('LECTURA DUDOSA'), findsNothing);
  });

  testWidgets(
      '5j paso 2 · ninguna fila que pide atención se esconde, y el resumen sólo cuenta limpias',
      (tester) async {
    // Fixture adversarial: MÁS filas problemáticas que el antiguo tope de 9.
    // Con ese tope la décima quedaba oculta y el pie afirmaba que las ocultas
    // tenían todos sus campos — una mentira sobre movimientos de dinero.
    final noisy = <PayrollStatementRow>[
      for (var i = 1; i <= 12; i++)
        PayrollStatementRow(
          bookingDate: null,
          description: 'TRANSFERENCIA OCR CORTADA $i',
          documentNumber: 'OCR-$i',
          debitAmountClp: null,
          creditAmountClp: null,
          balanceAmountClp: null,
          direction: PayrollStatementMovementDirection.unknown,
          parseWarningCodes: const <String>['missing_transaction_amount'],
          evidence: PayrollStatementRowEvidence(
            sourceRowNumber: 100 + i,
            startPageNumber: 1,
            startLineNumber: 100 + i,
            endPageNumber: 1,
            endLineNumber: 100 + i,
          ),
        ),
    ];
    final harness = recorder(prepared: draft(extraRows: noisy));
    await pump(tester, actions: harness.actions, size: const Size(1440, 2400));
    await tester.tap(find.text('Elegir archivo'));
    await tester.pumpAndSettle();

    for (var i = 1; i <= 12; i++) {
      expect(
        find.text('TRANSFERENCIA OCR CORTADA $i'),
        findsOneWidget,
        reason: 'la fila $i pide atención y no puede esconderse tras un tope',
      );
    }
    // Las 12 problemáticas son obligatorias y se muestran todas; del fixture
    // base queda **una** limpia fuera, que es lo que el pie resume.
    // Singular exacto: queda **una** limpia oculta, así que el pie dice
    // «1 egreso más». El aserto anterior buscaba «movimientos más» —texto que
    // producción ya no emite— dentro de un `if`, así que nunca entraba.
    expect(
      find.text('… 1 egreso más con todos sus campos reconocidos y sin '
          'avisos.'),
      findsOneWidget,
    );
  });

  // ── 5j · paso 4 · el único punto de escritura ──────────────────────────────
  //
  // Fixture SINTÉTICO: ningún archivo real, ninguna importación viva. Lo que se
  // prueba es la aritmética del resumen y la composición del frame, que es
  // donde una pantalla de dinero se puede pasar de afirmación.

  /// Deja la app en el paso 4 con una semana tocada por una transferencia.
  Future<void> reachApplyStage(
    WidgetTester tester, {
    required PayrollReconciliationActions actions,
    Size size = const Size(1360, 1100),
  }) async {
    await pump(tester, actions: actions, size: size);
    await loadStatement(tester);
    await selectBankAccount(tester);
    await confirmSuggestion(tester);
    await goToStage(tester, 'Aplicar');
  }

  group('5j · el CTA largo del paso 4 no se recorta en compacto', () {
    // La prueba de elisión anterior sólo montaba **Revisar**, donde el
    // primario dice «Ir a aplicar» — corto. El rótulo que de verdad pierde
    // significado es el del paso 4: «Confirmar N semanas y aplicar
    // conciliación», que en la app viva a 430 salía «…y aplica…».
    for (final width in <double>[834, 430]) {
      testWidgets('a ${width.toInt()} el primario dice entero qué va a pasar',
          (tester) async {
        final harness = recorder(prepared: draft(withCashEmployee: true));
        await reachApplyStage(
          tester,
          actions: harness.actions,
          size: Size(width, 1100),
        );

        final cta = find.widgetWithText(
          PayrollPrimaryAction,
          commitAndApplyLabel,
        );
        expect(cta, findsOneWidget,
            reason: 'el paso 4 tiene que estar montado');

        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: cta,
            matching: find.text(commitAndApplyLabel),
          ),
        );
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: 'a ${width.toInt()} px el botón que aplica la conciliación '
              'dice «Confirmar N sema…»: eso no es una acción, es una '
              'adivinanza sobre dinero',
        );
      });
    }
  });

  group('5j · el stepper usa el breakpoint canónico, no 600', () {
    const compactNames = <String>[
      'Cargar',
      'Lectura',
      'Propuestas',
      'Aplicar',
    ];

    testWidgets('a 834 los cuatro pasos salen compactos y sin elidir',
        (tester) async {
      final harness = recorder();
      await pump(tester, actions: harness.actions, size: const Size(834, 1000));
      await loadStatement(tester);

      for (var i = 0; i < compactNames.length; i++) {
        final step =
            find.byKey(ValueKey<String>('reconciliation-step-${i + 1}'));
        expect(step, findsOneWidget);
        final label = find.descendant(
          of: step,
          matching: find.text(compactNames[i]),
        );
        expect(
          label,
          findsOneWidget,
          reason:
              'a 834 el paso ${i + 1} tiene que decir «${compactNames[i]}»; '
              'con el umbral en 600 tomaba la rama ancha y salía «Subir '
              'cart…», «14 movimie…», «0/4 efecti…»',
        );
        expect(
          tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
          isFalse,
        );
      }
    });

    testWidgets('a 900 vuelve la rama ancha, con el nombre largo',
        (tester) async {
      final harness = recorder();
      await pump(tester, actions: harness.actions, size: const Size(900, 1000));
      await loadStatement(tester);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('reconciliation-step-1')),
          matching: find.text('Cargar cartola'),
        ),
        findsOneWidget,
        reason: '900 ya es escritorio: ahí el nombre completo sí cabe',
      );
    });
  });

  testWidgets(
      '5j paso 4 · a 1360 las tres columnas arrancan en la misma fila, con la '
      'canaleta y la proporción del frame; a 834 y 430 se apilan',
      (tester) async {
    const titles = <String>[
      'IMPACTO POR SEMANA',
      'EFECTIVO · SIEMPRE PREGUNTADO A MANO',
      'RESUMEN ANTES DE ESCRIBIR',
    ];

    // 1360 · la composición del frame: tres columnas lado a lado, con su
    // proporción. Comparar sólo el borde superior no bastaba —tres columnas
    // apiladas de altura cero también lo cumplirían—, así que se miden los
    // rectángulos completos: misma línea, sin solaparse, en el orden del frame
    // y con los anchos que el frame publica.
    final wide = recorder(prepared: draft(withCashEmployee: true));
    await reachApplyStage(tester, actions: wide.actions);
    final rects = <Rect>[
      for (final title in titles)
        tester.getRect(
          find
              .ancestor(
                of: find.text(title),
                matching: find.byType(Column),
              )
              .first,
        ),
    ];
    expect(
      rects.map((rect) => rect.top).toSet().length,
      1,
      reason: 'las tres columnas arrancan en la misma línea: $rects',
    );
    for (var i = 1; i < rects.length; i++) {
      expect(
        rects[i].left,
        greaterThanOrEqualTo(rects[i - 1].right),
        reason: 'la columna $i se solapa con la anterior: $rects',
      );
      expect(
        rects[i].left - rects[i - 1].right,
        moreOrLessEquals(20, epsilon: 1),
        reason: 'la canaleta del frame es 20: $rects',
      );
    }
    // Proporción 43:43:40 del frame (medida sobre el PNG publicado en
    // 430/430/400). Se compara la razón, no el píxel: el canvas de la app no
    // es el del frame.
    expect(
      rects[0].width,
      moreOrLessEquals(rects[1].width, epsilon: 1),
      reason: 'las dos primeras columnas son iguales: $rects',
    );
    expect(
      rects[2].width / rects[0].width,
      moreOrLessEquals(40 / 43, epsilon: 0.02),
      reason: 'la tercera columna guarda la razón 40/43 del frame: $rects',
    );

    // 834 y 430 · Design no publicó una composición de paso 4 para tablet ni
    // para móvil, así que no se inventa una: se apila en el mismo orden de
    // lectura. Apilado significa **una debajo de otra**, no tres angostas.
    for (final width in const <double>[834, 430]) {
      final narrow = recorder(prepared: draft(withCashEmployee: true));
      await reachApplyStage(
        tester,
        actions: narrow.actions,
        size: Size(width, 1600),
      );
      final tops = <double>[
        for (final title in titles) tester.getTopLeft(find.text(title)).dy,
      ];
      expect(
        tops[0] < tops[1] && tops[1] < tops[2],
        isTrue,
        reason: 'a $width las columnas se apilan en orden: $tops',
      );
    }
  });

  testWidgets(
      '5j paso 4 · el total del resumen es exactamente lo que las semanas dejan '
      'de deber', (tester) async {
    // La cifra grande del resumen y las cifras de la columna izquierda salen
    // del mismo conjunto de decisiones a propósito: dos números distintos para
    // lo mismo, en una pantalla de dinero, es como se pierde la confianza. Si
    // alguien cambia una de las dos derivaciones, esta prueba se pone roja.
    //
    // El fixture tiene que mover las TRES clases de dinero —transferencia,
    // efectivo y anticipo—, porque el total las suma a las tres. Con sólo la
    // transferencia, sacar los anticipos de la suma dejaba la prueba en verde:
    // comprobado quitando esa línea del cálculo, y no se puso roja.
    final harness = recorder(
      prepared: draft(
        withCashEmployee: true,
        openAdvances: [
          cashAdvance(
            id: 'advance-total-check',
            amount: 30000,
            paidAt: DateTime(2026, 7, 10),
          ),
        ],
      ),
    );
    await reachApplyStage(tester, actions: harness.actions);

    // Se responde el efectivo con anticipo aplicado, para que el total tenga
    // las tres clases dentro.
    await openCashPerson(tester, 'Rosa Díaz');
    await tapVisible(tester,
        find.widgetWithText(PayrollDecisionOptionCard, 'Entregué efectivo'));
    await tapVisible(
      tester,
      find.byKey(const ValueKey('cash-advance-advance-total-check')),
    );
    await tapVisible(tester, find.text('Confirmar respuesta'));

    expect(
      find.text('Anticipos que se descontarán'),
      findsOneWidget,
      reason: 'el anticipo aplicado tiene que aparecer como su propia fila',
    );

    // La semana tocada aparece con su tarjeta de impacto.
    final impactCard = find.byKey(
      const ValueKey<String>('payroll-week-impact-voucher-1'),
    );
    expect(impactCard, findsOneWidget);

    /// `$1.234.567` → 1234567. Se lee de la pantalla a propósito: lo que hay
    /// que verificar es la cifra que el operador ve, no la variable interna.
    int parseClp(String text) =>
        int.parse(text.replaceAll(RegExp(r'[^0-9]'), ''));

    final cardMoney = tester
        .widgetList<Text>(
          find.descendant(of: impactCard, matching: find.byType(Text)),
        )
        .map((widget) => widget.data ?? '')
        .where((text) => text.startsWith(r'$'))
        .map(parseClp)
        .toList(growable: false);
    expect(
      cardMoney,
      hasLength(2),
      reason: 'la tarjeta muestra antes → después, dos cifras',
    );
    final before = cardMoney.first;
    final after = cardMoney.last;
    expect(
      after,
      lessThan(before),
      reason: 'la transferencia confirmada tiene que bajar lo que falta pagar',
    );
    expect(
      find.descendant(of: impactCard, matching: find.text('falta pagar')),
      findsOneWidget,
      reason: 'sin el rótulo, la cifra grande se lee como «lo que se paga»',
    );

    // La glosa nombra los movimientos que componen la baja. Si se cae uno, la
    // semana muestra una caída que su propia glosa no explica.
    expect(
      find.descendant(
        of: impactCard,
        matching: find.text('1 transferencia + 1 en efectivo + 1 anticipo'),
      ),
      findsOneWidget,
    );

    // El total del resumen y la baja de la semana son el MISMO conjunto de
    // decisiones. Si alguien cambia una de las dos derivaciones, esto se pone
    // rojo: dos cifras distintas para lo mismo, en una pantalla de dinero, es
    // como se pierde la confianza.
    final summary = find.byKey(
      const ValueKey<String>('payroll-reconciliation-apply-summary'),
    );
    expect(summary, findsOneWidget);
    final total = tester.widget<VbMoneyText>(
      find.descendant(of: summary, matching: find.byType(VbMoneyText)),
    );
    expect(
      total.amount,
      before - after,
      reason: 'el total a aplicar es exactamente lo que la semana deja de '
          'deber',
    );
    expect(find.text('Total a aplicar'), findsOneWidget);
    expect(find.text('Pagos que se crearán'), findsOneWidget);
  });

  testWidgets(
      '5j paso 4 · «Excluidos por ti» cuenta lo que excluyó el operador y NO lo '
      'que la app descartó sola', (tester) async {
    // Las dos mitades van en la misma prueba a propósito. La primera versión
    // sólo tenía la mitad negativa, con un fixture cuyo abono entrante ni
    // siquiera llega a `_transferRows`: quitarle el guard al contador **no la
    // ponía roja**. Verde sin probar nada es peor que ausente, así que acá el
    // fixture demuestra primero que construyó el caso, y la mitad positiva
    // obliga a que el contador sepa distinguir.

    // ── Descarte AUTOMÁTICO: el movimiento cae fuera de toda ventana de pago
    // y la app lo clasifica sola. Atribuírselo al operador sería ponerle un
    // criterio que no aplicó.
    final automatic = recorder(
      prepared: draft(withForeignNamedMovement: true),
    );
    await pump(tester,
        actions: automatic.actions, size: const Size(1360, 1100));
    await loadStatement(tester);
    await selectBankAccount(tester);
    await confirmSuggestion(tester);

    // Las filas auto-clasificadas nacen dentro de su grupo plegado: sin
    // abrirlo, `find` no las ve y una ausencia no probaría nada.
    final automaticGroup = find.byKey(
      const ValueKey('review-group-automatic'),
    );
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
      reason: 'sin la clasificación automática esta mitad no prueba nada',
    );

    await goToStage(tester, 'Aplicar');
    expect(
      find.text('Excluidos por ti'),
      findsNothing,
      reason: 'nadie excluyó nada a mano: la fila no debe existir',
    );

    // ── Exclusión EXPLÍCITA: el cargo nombra a alguien de la nómina, así que
    // exige respuesta, y el operador responde «No es nómina». Eso sí es suyo.
    final manual = recorder(
      prepared: draft(withPayrollNamedUnmatchedMovement: true),
    );
    await pump(tester, actions: manual.actions, size: const Size(1360, 1100));
    await loadStatement(tester);
    await selectBankAccount(tester);
    await confirmSuggestion(tester);

    final suspiciousRow = find.byWidgetPredicate(
      (widget) =>
          widget is PayrollReconciliationRow &&
          widget.data.sourceRowId == 'p1-l2-r2',
    );
    expect(suspiciousRow, findsOneWidget);
    expect(
      tester
          .widget<PayrollReconciliationRow>(suspiciousRow)
          .data
          .isAutomaticallyClassified,
      isFalse,
      reason: 'esta fila tiene que ser una pregunta, no un descarte solo',
    );
    await tapVisible(
      tester,
      find.descendant(
        of: suspiciousRow,
        matching:
            find.widgetWithText(PayrollDecisionOptionCard, 'No es nómina'),
      ),
    );

    await goToStage(tester, 'Aplicar');
    expect(
      find.text('Excluidos por ti'),
      findsOneWidget,
      reason: 'el operador excluyó una fila a mano y el resumen tiene que '
          'decirlo',
    );
  });

  testWidgets(
      '5j paso 4 · tras un intento fallido el encabezado deja de decir «nada se '
      'escribió»', (tester) async {
    // `createImport` corre ANTES que `apply` y escribe la importación con sus
    // filas. Si el apply falla, no hay pagos —es una sola transacción— pero la
    // cartola sí quedó registrada, y el encabezado del frame afirma lo
    // contrario de forma incondicional.
    final harness = recorder(
      failFirstApply: true,
      prepared: draft(),
    );
    await reachApplyStage(tester, actions: harness.actions);

    final note = find.byKey(
      const ValueKey<String>('payroll-reconciliation-apply-write-note'),
    );
    expect(
      tester.widget<Text>(note).data,
      'Nada se escribió todavía. Este es el último punto de retorno.',
    );

    await tapVisible(tester, find.text(commitAndApplyLabel));
    expect(harness.calls, contains('createImport'));

    expect(
      tester.widget<Text>(note).data,
      contains('La cartola ya quedó registrada por el intento anterior'),
      reason: 'la importación existe: el encabezado no puede decir «nada»',
    );
  });

  testWidgets(
      '5j paso 4 · genera las seis capturas de HARNESS (claro/oscuro × '
      '1360/834/430)', (tester) async {
    // **Evidencia de HARNESS, no viva.** El paso 4 sólo existe con una cartola
    // cargada, y cargar una es subir un archivo real a un flujo que corre
    // contra producción. Las seis celdas se generan acá, con fixture sintético,
    // y se declaran como tales. **Opt-in**: sin `PAYROLL_SHOT_DIR` no escribe
    // artefactos, porque una batería de regresión no deja archivos por ahí.
    //
    // **Límite visual declarado:** las fuentes reales no se cargan en
    // `flutter_test`, así que el texto sale como **bloques** —los glifos de la
    // tipografía de prueba del arnés— y en estas imágenes no se lee ni una
    // palabra. Demuestran **composición**; **no son evidencia de tipografía**.
    // El texto lo cubren las aserciones de copy, nunca la imagen.
    final target = Platform.environment['PAYROLL_SHOT_DIR'];
    if (target == null || target.isEmpty) {
      markTestSkipped('define PAYROLL_SHOT_DIR para generar las capturas');
      return;
    }
    suspendGoogleFontsNetwork();
    final dir = Directory(target);
    for (final brightness in Brightness.values) {
      for (final width in const <double>[1360, 834, 430]) {
        final harness = recorder(prepared: draft(withCashEmployee: true));
        // El brillo se fija al montar, así que cada celda monta exactamente una
        // vez.
        await pump(
          tester,
          actions: harness.actions,
          size: Size(width, width < 600 ? 1600 : 1100),
          brightness: brightness,
        );
        await loadStatement(tester);
        await selectBankAccount(tester);
        await confirmSuggestion(tester);
        await goToStage(tester, 'Aplicar');

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
            '${dir.path}/paso4-${brightness.name}-${width.toInt()}.png',
          ).writeAsBytesSync(data.buffer.asUint8List());
        });
      }
    }
    // Se filtra por el NOMBRE del archivo, no por la ruta: `path.contains`
    // también matchea el directorio, y los destinos de `mktemp -d` de esta
    // tarea se llaman `paso4-XXXXXX`, así que habría contado cualquier archivo
    // que cayera ahí dentro.
    expect(
      dir
          .listSync()
          .whereType<File>()
          .where((file) => file.uri.pathSegments.last.startsWith('paso4-'))
          .length,
      6,
    );
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
              confidence: const SizedBox(width: 60, height: 22),
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

      // La razón es la SEGUNDA línea de PERSONA Y RAZÓN, no una columna aparte.
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
      for (final label in const <String>[
        'FECHA',
        'DESCRIPCIÓN EN LA CARTOLA',
        'MONTO',
        'PERSONA Y RAZÓN',
        'CONFIANZA',
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
