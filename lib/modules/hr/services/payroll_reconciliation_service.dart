import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/database_service.dart';
import '../models/payroll_statement_reconciliation.dart';
import '../models/payroll_voucher.dart';
import 'payroll_bank_statement_parser.dart';
import 'payroll_statement_extraction_service.dart';
import 'payroll_statement_local_image_ocr.dart';
import 'payroll_statement_matcher.dart';
import 'payroll_voucher_service.dart';

typedef PayrollReconciliationRpc = Future<dynamic> Function(
  String functionName,
  Map<String, dynamic> params,
);

enum PayrollReviewDecisionKind {
  bankPayment,
  cashPayment,
  advanceAllocation,
  ignore,
  hold,
  notPaid,
  alreadyResolved,
}

enum PayrollVarianceDisposition {
  none,
  partial,
  unresolved,
  employeeAdvance,
}

enum PayrollReconciliationRecoveryAction {
  none,
  selectAnotherFile,
  retry,
  reload,
  fixPaymentConfiguration,
  reviewPermissions,
}

class PayrollStatementPreparedDraft {
  const PayrollStatementPreparedDraft({
    required this.operationKey,
    required this.filename,
    required this.extraction,
    required this.parseResult,
    required this.reconciliation,
    required this.vouchersById,
    required this.employeeRowsById,
    required this.paymentMethods,
    required this.openAdvances,
    required this.missingCanonicalPaymentMethodEmployeeIds,
    required this.rowFingerprintsBySourceRowId,
    required this.expectedVoucherVersionsById,
    required this.accountFingerprint,
    this.priorDecisionIdsBySourceRowId = const <String, String>{},
    required this.statementYear,
    this.documentDate,
  });

  final String operationKey;
  final String filename;
  final PayrollStatementExtractionResult extraction;
  final PayrollBankStatementParseResult parseResult;
  final PayrollStatementReconciliationResult reconciliation;
  final Map<String, PayrollVoucher> vouchersById;
  final Map<String, Map<String, dynamic>> employeeRowsById;
  final List<Map<String, dynamic>> paymentMethods;
  final List<EmployeeAdvance> openAdvances;
  final Set<String> missingCanonicalPaymentMethodEmployeeIds;
  final Map<String, String> rowFingerprintsBySourceRowId;
  final Map<String, int> expectedVoucherVersionsById;
  final String accountFingerprint;
  final Map<String, String> priorDecisionIdsBySourceRowId;
  final int statementYear;
  final PayrollCivilDate? documentDate;

  List<PayrollVoucher> get vouchers =>
      List<PayrollVoucher>.unmodifiable(vouchersById.values);
}

class PayrollStatementReviewDecision {
  const PayrollStatementReviewDecision({
    required this.kind,
    this.sourceRowId,
    this.voucherLineId,
    this.voucherId,
    this.employeeId,
    this.amountClp,
    this.paymentDate,
    this.paymentMethodId,
    this.paymentAccountId,
    this.advanceId,
    this.priorDecisionId,
    this.varianceDisposition = PayrollVarianceDisposition.none,
    this.manualConfirmation = false,
    this.note,
  });

  final PayrollReviewDecisionKind kind;
  final String? sourceRowId;
  final String? voucherLineId;
  final String? voucherId;
  final String? employeeId;
  final int? amountClp;
  final PayrollCivilDate? paymentDate;
  final String? paymentMethodId;
  final String? paymentAccountId;
  final String? advanceId;
  final String? priorDecisionId;
  final PayrollVarianceDisposition varianceDisposition;
  final bool manualConfirmation;
  final String? note;
}

class PayrollStatementImportReceipt {
  const PayrollStatementImportReceipt({
    required this.importId,
    required this.operationKey,
    required this.wasReplay,
    required this.erpAccountId,
    required this.rowIdsBySourceRowId,
    required this.rowFingerprintsBySourceRowId,
    this.priorDecisionIdsBySourceRowId = const <String, String>{},
    required this.raw,
  });

  final String importId;
  final String operationKey;
  final bool wasReplay;
  final String erpAccountId;
  final Map<String, String> rowIdsBySourceRowId;
  final Map<String, String> rowFingerprintsBySourceRowId;
  final Map<String, String> priorDecisionIdsBySourceRowId;
  final Map<String, dynamic> raw;
}

class PayrollStatementApplyReceipt {
  const PayrollStatementApplyReceipt({
    required this.importId,
    required this.operationKey,
    required this.wasReplay,
    required this.raw,
  });

  final String importId;
  final String operationKey;
  final bool wasReplay;
  final Map<String, dynamic> raw;

  String? get status {
    final value = raw['status']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  int get decisionCount => _receiptInt(raw['decision_count']);
  int get allocationCount => _receiptInt(raw['allocation_count']);
  int get alreadyResolvedCount => _receiptInt(raw['already_resolved_count']);
  int get unresolvedVarianceCount =>
      _receiptInt(raw['unresolved_variance_count']);
  int get unresolvedVarianceAmountClp =>
      _receiptInt(raw['unresolved_variance_total']);

  List<String> get committedVoucherIds {
    final value = raw['committed_voucher_ids'];
    if (value is! List) return const <String>[];
    final ids = value
        .map((entry) => entry?.toString().trim() ?? '')
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    return List<String>.unmodifiable(ids);
  }

  Map<String, int> get voucherVersions {
    final value = raw['voucher_versions'];
    if (value is! Map) return const <String, int>{};
    return Map<String, int>.unmodifiable({
      for (final entry in value.entries)
        if (entry.key.toString().trim().isNotEmpty)
          entry.key.toString(): _receiptInt(entry.value),
    });
  }

  static int _receiptInt(dynamic value) {
    if (value is num) return value.round();
    return num.tryParse(value?.toString() ?? '')?.round() ?? 0;
  }
}

class PayrollBeneficiaryAliasLearnReceipt {
  const PayrollBeneficiaryAliasLearnReceipt({
    required this.wasCreated,
    required this.employeeId,
    required this.alias,
    required this.normalizedAlias,
  });

  final bool wasCreated;
  final String employeeId;
  final String alias;
  final String normalizedAlias;
}

class PayrollReconciliationServiceException implements Exception {
  const PayrollReconciliationServiceException(
    this.message, {
    this.recoveryAction = PayrollReconciliationRecoveryAction.none,
    this.canRetrySameOperation = false,
  });

  final String message;
  final PayrollReconciliationRecoveryAction recoveryAction;
  final bool canRetrySameOperation;

  @override
  String toString() => message;
}

/// Coordinates local extraction and deterministic matching.
///
/// Preparing a draft performs no database writes. Import/apply methods are kept
/// behind idempotent server commands so the UI never posts one voucher at a
/// time or mutates payroll line amounts before the batch succeeds.
class PayrollReconciliationService {
  PayrollReconciliationService({
    required DatabaseService database,
    required PayrollVoucherService payrollService,
    PayrollBankStatementParser parser = const PayrollBankStatementParser(),
    PayrollStatementMatcher matcher = const PayrollStatementMatcher(),
    PayrollStatementLocalImageOcr localImageOcr =
        const PayrollStatementLocalImageOcr(),
    PayrollReconciliationRpc? sensitiveRpc,
  })  : _database = database,
        _payrollService = payrollService,
        _parser = parser,
        _matcher = matcher,
        _localImageOcr = localImageOcr,
        _sensitiveRpc = sensitiveRpc ??
            ((functionName, params) =>
                database.supabase.rpc(functionName, params: params));

  static const String parserName = 'banco_chile_statement';
  static const String parserVersion = 'banco_chile_v1';

  final DatabaseService _database;
  final PayrollVoucherService _payrollService;
  final PayrollBankStatementParser _parser;
  final PayrollStatementMatcher _matcher;
  final PayrollStatementLocalImageOcr _localImageOcr;
  final PayrollReconciliationRpc _sensitiveRpc;

  Future<PayrollStatementPreparedDraft> prepare({
    required Uint8List bytes,
    required String filename,
    String? sourcePath,
    int? statementYear,
    PayrollStatementPreparationProgressCallback? onProgress,
  }) async {
    final extractionService = PayrollStatementExtractionService(
      imageTextExtractor:
          _localImageOcr.isSupported ? _localImageOcr.extractText : null,
    );
    Future<PayrollStatementExtractionResult> extract({
      bool forceImageOcrForPdf = false,
    }) async {
      try {
        return await extractionService.extract(
          bytes: bytes,
          filename: filename,
          sourcePath: sourcePath,
          forceImageOcrForPdf: forceImageOcrForPdf,
          onProgress: onProgress,
        );
      } on PayrollStatementExtractionException catch (error) {
        throw PayrollReconciliationServiceException(
          error.message,
          recoveryAction: PayrollReconciliationRecoveryAction.selectAnotherFile,
        );
      }
    }

    var extraction = await extract();

    onProgress?.call(
      const PayrollStatementPreparationProgress(
        phase: PayrollStatementPreparationPhase.parsingMovements,
      ),
    );
    var resolvedYear =
        statementYear ?? _inferStatementYear(extraction) ?? DateTime.now().year;
    var parseResult = _parser.parsePages(
      extraction.pages.map((page) => page.text).toList(growable: false),
      statementYear: resolvedYear,
    );
    if (extraction.inputKind == PayrollStatementInputKind.pdf &&
        extraction.method == PayrollStatementExtractionMethod.embeddedPdfText &&
        _localImageOcr.isSupported &&
        _needsPdfOcrRetry(parseResult)) {
      extraction = await extract(forceImageOcrForPdf: true);
      onProgress?.call(
        const PayrollStatementPreparationProgress(
          phase: PayrollStatementPreparationPhase.parsingMovements,
        ),
      );
      resolvedYear = statementYear ??
          _inferStatementYear(extraction) ??
          DateTime.now().year;
      parseResult = _parser.parsePages(
        extraction.pages.map((page) => page.text).toList(growable: false),
        statementYear: resolvedYear,
      );
    }

    if (extraction.needsImageOcr) {
      throw const PayrollReconciliationServiceException(
        'Este archivo necesita OCR de imagen. Usa un dispositivo compatible '
        'con OCR local o sube una cartola PDF con texto seleccionable.',
        recoveryAction: PayrollReconciliationRecoveryAction.selectAnotherFile,
      );
    }
    final accountFingerprint = _extractAccountFingerprint(extraction);
    if (accountFingerprint == null) {
      throw const PayrollReconciliationServiceException(
        'No se pudo identificar la cuenta de la cartola sin guardar su '
        'número. Usa un archivo donde el encabezado sea legible.',
        recoveryAction: PayrollReconciliationRecoveryAction.selectAnotherFile,
      );
    }

    final documentDate = _extractDocumentDate(extraction);
    if (parseResult.rows.isEmpty) {
      throw const PayrollReconciliationServiceException(
        'No se reconocieron movimientos bancarios revisables.',
        recoveryAction: PayrollReconciliationRecoveryAction.selectAnotherFile,
      );
    }

    onProgress?.call(
      const PayrollStatementPreparationProgress(
        phase: PayrollStatementPreparationPhase.loadingPayrollContext,
      ),
    );
    return _prepareWithParsedEvidence(
      operationKey: const Uuid().v4(),
      filename: filename,
      extraction: extraction,
      parseResult: parseResult,
      statementYear: resolvedYear,
      accountFingerprint: accountFingerprint,
      documentDate: documentDate,
    );
  }

  /// Reloads the ERP-owned context without extracting or parsing the sensitive
  /// statement again.
  ///
  /// This is used after configuring a worker payment method from the review
  /// flow. The stable statement row IDs and operation key let the page retain
  /// still-valid human decisions while vouchers, methods, aliases, advances
  /// and reconciliation versions are refreshed from their canonical owners.
  Future<PayrollStatementPreparedDraft> refreshPreparedDraft(
    PayrollStatementPreparedDraft draft,
  ) {
    return _prepareWithParsedEvidence(
      operationKey: draft.operationKey,
      filename: draft.filename,
      extraction: draft.extraction,
      parseResult: draft.parseResult,
      statementYear: draft.statementYear,
      accountFingerprint: draft.accountFingerprint,
      documentDate: draft.documentDate,
    );
  }

  Future<PayrollStatementPreparedDraft> _prepareWithParsedEvidence({
    required String operationKey,
    required String filename,
    required PayrollStatementExtractionResult extraction,
    required PayrollBankStatementParseResult parseResult,
    required int statementYear,
    required String accountFingerprint,
    required PayrollCivilDate? documentDate,
  }) async {
    final vouchers = await _loadOpenVouchers();
    final employeeRows = await _loadEmployeeRows();
    final paymentMethods = await _payrollService.getPaymentMethods();
    final aliasesByEmployeeId = await _loadBeneficiaryAliases();
    final openAdvances = await _payrollService.getOpenEmployeeAdvances();

    final methodById = <String, Map<String, dynamic>>{
      for (final method in paymentMethods)
        if (method['id'] != null) method['id'].toString(): method,
    };
    final reconciliationEmployees = <PayrollReconciliationEmployee>[];

    for (final entry in employeeRows.entries) {
      final employeeId = entry.key;
      final row = entry.value;
      final canonicalMethodId = row['preferred_payment_method_id']?.toString();
      final employeeMethod =
          canonicalMethodId == null ? null : methodById[canonicalMethodId];
      reconciliationEmployees.add(
        PayrollReconciliationEmployee(
          employeeId: employeeId,
          displayName: [
            row['first_name']?.toString() ?? '',
            row['last_name']?.toString() ?? '',
          ].where((part) => part.trim().isNotEmpty).join(' '),
          paymentMethod: _paymentMethodFor(
            canonicalMethod: _isUsableCanonicalMethod(employeeMethod)
                ? employeeMethod
                : null,
            legacyValue: row['preferred_payment_method']?.toString(),
          ),
          bankBeneficiaryAliases:
              aliasesByEmployeeId[employeeId] ?? const <String>[],
        ),
      );
    }

    final voucherLines = <PayrollReconciliationVoucherLine>[];
    final effectiveCanonicalMethodIdByLineId = <String, String?>{};
    for (final voucher in vouchers) {
      if (voucher.id == null) continue;
      for (final line in voucher.lines) {
        if (!line.isIncluded || line.id == null || line.balance <= 0.01) {
          continue;
        }
        final employeeRow = employeeRows[line.employeeId];
        final employeeCanonicalMethodId =
            employeeRow?['preferred_payment_method_id']?.toString().trim();
        final snapshotMethodId = line.paymentMethodId?.trim();
        final snapshotMethod =
            snapshotMethodId == null ? null : methodById[snapshotMethodId];
        final employeeMethod = employeeCanonicalMethodId == null
            ? null
            : methodById[employeeCanonicalMethodId];
        final canonicalMethod = _isUsableCanonicalMethod(snapshotMethod)
            ? snapshotMethod
            : _isUsableCanonicalMethod(employeeMethod)
                ? employeeMethod
                : null;
        final effectiveMethodId = identical(canonicalMethod, snapshotMethod)
            ? snapshotMethodId
            : identical(canonicalMethod, employeeMethod)
                ? employeeCanonicalMethodId
                : null;
        final effectiveMethod = _paymentMethodFor(
          canonicalMethod: canonicalMethod,
          legacyValue: line.paymentMethod.trim().isNotEmpty
              ? line.paymentMethod
              : employeeRow?['preferred_payment_method']?.toString(),
        );
        effectiveCanonicalMethodIdByLineId[line.id!] =
            canonicalMethod == null ? null : effectiveMethodId;
        voucherLines.add(
          PayrollReconciliationVoucherLine(
            lineId: line.id!,
            voucherId: voucher.id!,
            employeeId: line.employeeId,
            periodStart: PayrollCivilDate(
              voucher.periodStart.year,
              voucher.periodStart.month,
              voucher.periodStart.day,
            ),
            periodEnd: PayrollCivilDate(
              voucher.periodEnd.year,
              voucher.periodEnd.month,
              voucher.periodEnd.day,
            ),
            pendingAmountClp: line.balance.round(),
            paymentMethod: effectiveMethod,
            paymentMethodId: canonicalMethod == null ? null : effectiveMethodId,
            paymentAccountId: line.paymentAccountId,
          ),
        );
      }
    }
    final missingCanonicalMethodEmployeeIds = <String>{
      for (final line in voucherLines)
        if (effectiveCanonicalMethodIdByLineId[line.lineId] == null)
          line.employeeId,
    };

    final fingerprints = _fingerprintsFor(
      parseResult.rows,
      accountFingerprint: accountFingerprint,
    );
    final priorDecisionIds = await _loadPriorDecisionIds(
      rowFingerprintsBySourceRowId: fingerprints,
    );
    final reconciliation = _matcher.match(
      statementRows: parseResult.rows
          .where(
            (row) => !priorDecisionIds.containsKey(row.sourceRowId),
          )
          .toList(growable: false),
      employees: reconciliationEmployees,
      voucherLines: voucherLines,
    );

    return PayrollStatementPreparedDraft(
      operationKey: operationKey,
      filename: filename,
      extraction: extraction,
      parseResult: parseResult,
      reconciliation: reconciliation,
      vouchersById: <String, PayrollVoucher>{
        for (final voucher in vouchers)
          if (voucher.id != null) voucher.id!: voucher,
      },
      employeeRowsById: employeeRows,
      paymentMethods: List<Map<String, dynamic>>.unmodifiable(paymentMethods),
      openAdvances: openAdvances,
      missingCanonicalPaymentMethodEmployeeIds:
          Set<String>.unmodifiable(missingCanonicalMethodEmployeeIds),
      rowFingerprintsBySourceRowId:
          Map<String, String>.unmodifiable(fingerprints),
      expectedVoucherVersionsById: Map<String, int>.unmodifiable(
        <String, int>{
          for (final voucher in vouchers)
            if (voucher.id != null) voucher.id!: voucher.reconciliationVersion,
        },
      ),
      accountFingerprint: accountFingerprint,
      priorDecisionIdsBySourceRowId:
          Map<String, String>.unmodifiable(priorDecisionIds),
      statementYear: statementYear,
      documentDate: documentDate,
    );
  }

  bool _needsPdfOcrRetry(PayrollBankStatementParseResult result) {
    if (result.rows.isEmpty) return true;
    final completeRows =
        result.rows.where((row) => row.hasCompleteStructuredEvidence).length;
    return completeRows == 0 || completeRows * 2 < result.rows.length;
  }

  Future<PayrollStatementImportReceipt> createImport(
    PayrollStatementPreparedDraft draft, {
    required String erpAccountId,
  }) async {
    if (!_looksLikeUuid(erpAccountId)) {
      throw const PayrollReconciliationServiceException(
        'Selecciona la cuenta bancaria del ERP antes de importar.',
      );
    }
    final serializedRows = _serializeStatementRows(draft);
    final sourceMetadata = _sourceMetadata(
      draft,
      erpAccountId: erpAccountId,
    );
    final response = _asJsonObject(
      await _callSensitiveRpc(
        'create_payroll_statement_import',
        <String, dynamic>{
          'p_operation_key': draft.operationKey,
          'p_file_sha256': draft.extraction.fileSha256,
          'p_source_metadata': sourceMetadata,
          'p_rows': serializedRows,
        },
      ),
    );
    final importId =
        response['import_id']?.toString() ?? response['id']?.toString();
    if (importId == null || importId.isEmpty) {
      throw const PayrollReconciliationServiceException(
        'El servidor no devolvió un identificador para la importación.',
      );
    }

    final persistedRows = await _database.select(
      'payroll_statement_rows',
      selectColumns: 'id,row_ordinal,fingerprint',
      where: 'import_id=$importId',
      orderBy: 'row_ordinal',
    );
    final persistedByOrdinal = <int, Map<String, dynamic>>{
      for (final row in persistedRows)
        if ((row['row_ordinal'] as num?)?.toInt() case final ordinal?)
          ordinal: row,
    };
    if (persistedByOrdinal.length != draft.parseResult.rows.length) {
      throw const PayrollReconciliationServiceException(
        'La importación guardada no coincide con las filas revisadas. '
        'Vuelve a cargar la cartola.',
      );
    }

    final rowIdsBySource = <String, String>{};
    final rowFingerprintsBySource = <String, String>{};
    for (final row in draft.parseResult.rows) {
      final persisted = persistedByOrdinal[row.evidence.sourceRowNumber];
      final rowId = persisted?['id']?.toString();
      final fingerprint = persisted?['fingerprint']?.toString();
      if (rowId == null ||
          rowId.isEmpty ||
          fingerprint == null ||
          fingerprint.isEmpty) {
        throw const PayrollReconciliationServiceException(
          'El servidor no devolvió toda la evidencia de la cartola.',
        );
      }
      rowIdsBySource[row.sourceRowId] = rowId;
      rowFingerprintsBySource[row.sourceRowId] = fingerprint;
      if (draft.rowFingerprintsBySourceRowId[row.sourceRowId] != fingerprint) {
        throw const PayrollReconciliationServiceException(
          'El servidor normalizó una fila de forma distinta. Vuelve a cargar '
          'la cartola antes de decidir.',
        );
      }
    }
    final priorDecisionIds = await _loadPriorDecisionIds(
      rowFingerprintsBySourceRowId: rowFingerprintsBySource,
      excludingImportId: importId,
    );
    if (!_sameStringMap(
      priorDecisionIds,
      draft.priorDecisionIdsBySourceRowId,
    )) {
      throw const PayrollReconciliationServiceException(
        'Otra conciliación resolvió movimientos de esta cartola mientras la '
        'revisabas. Vuelve a cargarla para evitar duplicar pagos.',
      );
    }

    return PayrollStatementImportReceipt(
      importId: importId,
      operationKey: draft.operationKey,
      wasReplay: response['replayed'] == true || response['was_replay'] == true,
      erpAccountId: erpAccountId,
      rowIdsBySourceRowId: Map<String, String>.unmodifiable(rowIdsBySource),
      rowFingerprintsBySourceRowId:
          Map<String, String>.unmodifiable(rowFingerprintsBySource),
      priorDecisionIdsBySourceRowId:
          Map<String, String>.unmodifiable(priorDecisionIds),
      raw: response,
    );
  }

  Future<PayrollStatementApplyReceipt> apply({
    required PayrollStatementPreparedDraft draft,
    required PayrollStatementImportReceipt importReceipt,
    required List<PayrollStatementReviewDecision> decisions,
    required Set<String> authorizedDraftVoucherIds,
    String? operationKey,
  }) async {
    final applyOperationKey = operationKey ?? const Uuid().v4();
    _validateDecisionCoverage(
      draft: draft,
      importReceipt: importReceipt,
      decisions: decisions,
    );
    for (final decision in decisions) {
      if (decision.kind == PayrollReviewDecisionKind.bankPayment &&
          decision.paymentAccountId != importReceipt.erpAccountId) {
        throw const PayrollReconciliationServiceException(
          'La cuenta del pago debe ser la misma cuenta ERP vinculada a la '
          'cartola.',
        );
      }
    }

    final voucherIdByLineId = <String, String>{
      for (final voucher in draft.vouchers)
        if (voucher.id != null)
          for (final line in voucher.lines)
            if (line.id != null) line.id!: voucher.id!,
    };
    final touchedVoucherIds = <String>{};
    for (final decision in decisions) {
      final lineId = decision.voucherLineId;
      if (lineId == null) continue;
      final voucherId = voucherIdByLineId[lineId];
      if (voucherId == null) {
        throw const PayrollReconciliationServiceException(
          'Una obligación cambió desde que se preparó la conciliación. '
          'Recarga las nóminas antes de aplicar.',
        );
      }
      touchedVoucherIds.add(voucherId);
    }
    final expectedVoucherVersions = <String, int>{};
    for (final voucherId in touchedVoucherIds) {
      final version = draft.expectedVoucherVersionsById[voucherId];
      if (version == null) {
        throw const PayrollReconciliationServiceException(
          'Cambió una nómina desde que se preparó la conciliación. Recarga '
          'los sueldos por pagar antes de aplicar.',
        );
      }
      expectedVoucherVersions[voucherId] = version;
    }
    final touchedDraftVoucherIds = <String>{
      for (final voucherId in touchedVoucherIds)
        if (draft.vouchersById[voucherId]?.status == PayrollVoucherStatus.draft)
          voucherId,
    };
    final normalizedAuthorizedDraftVoucherIds = authorizedDraftVoucherIds
        .map((voucherId) => voucherId.trim())
        .where((voucherId) => voucherId.isNotEmpty)
        .toSet();
    if (!_sameStringSet(
      touchedDraftVoucherIds,
      normalizedAuthorizedDraftVoucherIds,
    )) {
      throw const PayrollReconciliationServiceException(
        'Las semanas borrador que se confirmarán cambiaron. Vuelve a '
        'revisar el resumen antes de aplicar la conciliación.',
        recoveryAction: PayrollReconciliationRecoveryAction.reload,
      );
    }
    for (final voucherId in normalizedAuthorizedDraftVoucherIds) {
      final voucher = draft.vouchersById[voucherId];
      final hasPositiveObligation = voucher?.lines.any(
            (line) => line.isIncluded && line.totalAmount > 0,
          ) ??
          false;
      if (!hasPositiveObligation) {
        throw const PayrollReconciliationServiceException(
          'No se puede confirmar una semana sin sueldos que pagar.',
        );
      }
    }
    final serializedAuthorizedDraftVoucherIds =
        normalizedAuthorizedDraftVoucherIds.toList(growable: false)..sort();

    final response = _asJsonObject(
      await _callSensitiveRpc(
        'apply_payroll_statement_reconciliation',
        <String, dynamic>{
          'p_import_id': importReceipt.importId,
          'p_operation_key': applyOperationKey,
          'p_decisions': decisions.indexed
              .map(
                (entry) => _serializeDecision(
                  importReceipt,
                  entry.$2,
                  entry.$1 + 1,
                ),
              )
              .toList(growable: false),
          'p_expected_voucher_versions': expectedVoucherVersions,
          'p_authorized_draft_voucher_ids': serializedAuthorizedDraftVoucherIds,
        },
      ),
    );
    final appliedReceipt = PayrollStatementApplyReceipt(
      importId: importReceipt.importId,
      operationKey: applyOperationKey,
      wasReplay: response['replayed'] == true || response['was_replay'] == true,
      raw: response,
    );
    if (!_sameStringSet(
      normalizedAuthorizedDraftVoucherIds,
      appliedReceipt.committedVoucherIds.toSet(),
    )) {
      throw const PayrollReconciliationServiceException(
        'El comprobante del servidor no coincide con las semanas '
        'confirmadas. Recarga las nóminas antes de continuar.',
        recoveryAction: PayrollReconciliationRecoveryAction.reload,
      );
    }
    _payrollService.invalidateVouchersCache();
    return appliedReceipt;
  }

  Future<PayrollBeneficiaryAliasLearnReceipt> learnBeneficiaryAlias({
    required String employeeId,
    required String alias,
  }) async {
    final trimmedEmployeeId = employeeId.trim();
    final trimmedAlias = alias.trim();
    if (trimmedEmployeeId.isEmpty ||
        trimmedAlias.length < 2 ||
        trimmedAlias.length > 160) {
      throw const PayrollReconciliationServiceException(
        'El nombre bancario no es válido para guardarlo.',
      );
    }
    final response = _asJsonObject(
      await _callSensitiveRpc(
        'learn_payroll_beneficiary_alias',
        <String, dynamic>{
          'p_employee_id': trimmedEmployeeId,
          'p_alias': trimmedAlias,
        },
      ),
    );
    final status = response['status']?.toString().trim();
    if (status == 'conflict') {
      throw const PayrollReconciliationServiceException(
        'Ese nombre bancario ya pertenece a otra persona. No se modificó.',
      );
    }
    final resolvedEmployeeId = response['employee_id']?.toString().trim() ?? '';
    final savedAlias = response['alias']?.toString().trim() ?? '';
    final normalizedAlias =
        response['normalized_alias']?.toString().trim() ?? '';
    if (!const {'created', 'existing'}.contains(status) ||
        resolvedEmployeeId != trimmedEmployeeId ||
        savedAlias.isEmpty ||
        normalizedAlias.isEmpty) {
      throw const PayrollReconciliationServiceException(
        'El servidor no confirmó el nombre bancario guardado.',
      );
    }
    return PayrollBeneficiaryAliasLearnReceipt(
      wasCreated: status == 'created',
      employeeId: resolvedEmployeeId,
      alias: savedAlias,
      normalizedAlias: normalizedAlias,
    );
  }

  Future<dynamic> _callSensitiveRpc(
    String functionName,
    Map<String, dynamic> params,
  ) async {
    try {
      return await _sensitiveRpc(functionName, params);
    } on PostgrestException catch (error) {
      throw _typedPostgrestFailure(error);
    }
  }

  PayrollReconciliationServiceException _typedPostgrestFailure(
    PostgrestException error,
  ) {
    final code = error.code?.trim().toLowerCase() ?? '';
    final evidence = <Object?>[
      error.message,
      error.details,
      error.hint,
    ].whereType<Object>().map((value) => value.toString().toLowerCase()).join(
          ' ',
        );
    final hasExplicitPermissionEvidence = _containsAny(evidence, const <String>[
      'permission denied',
      'not authorized',
      'not authorised',
      'unauthorized',
      'unauthorised',
      'forbidden',
      'insufficient privilege',
      'insufficient_privilege',
      'permiso',
      'autorizacion',
      'autorización',
    ]);

    if (hasExplicitPermissionEvidence) {
      return const PayrollReconciliationServiceException(
        'No tienes permisos para aplicar esta conciliación. Revisa tus '
        'permisos antes de volver a intentarlo.',
        recoveryAction: PayrollReconciliationRecoveryAction.reviewPermissions,
      );
    }

    if (_containsAny(evidence, const <String>[
      'payment account',
      'payment_account',
      'payment method',
      'payment_method',
      'erp account',
      'erp_account',
      'cuenta de pago',
      'metodo de pago',
      'método de pago',
    ])) {
      return const PayrollReconciliationServiceException(
        'La cuenta o el método de pago de la nómina no está configurado '
        'correctamente. Corrige la configuración antes de continuar.',
        recoveryAction:
            PayrollReconciliationRecoveryAction.fixPaymentConfiguration,
      );
    }

    if (code == '42501') {
      return const PayrollReconciliationServiceException(
        'No tienes permisos para aplicar esta conciliación. Revisa tus '
        'permisos antes de volver a intentarlo.',
        recoveryAction: PayrollReconciliationRecoveryAction.reviewPermissions,
      );
    }

    if (code == '40001' ||
        code == '23505' ||
        _containsAny(evidence, const <String>[
          'version conflict',
          'version_conflict',
          'version mismatch',
          'version_mismatch',
          'already applied',
          'already_applied',
          'already reconciled',
          'already_reconciled',
          'already resolved',
          'already_resolved',
          'prior decision',
          'prior_decision',
          'duplicate',
          'duplicado',
          'stale',
          'conflict',
          'conflicto',
        ])) {
      return const PayrollReconciliationServiceException(
        'La conciliación cambió mientras la revisabas. Recarga las nóminas y '
        'vuelve a revisar los movimientos antes de aplicar.',
        recoveryAction: PayrollReconciliationRecoveryAction.reload,
      );
    }

    if (_isAmbiguousNetworkFailure(code, evidence)) {
      return const PayrollReconciliationServiceException(
        'No pudimos confirmar si la operación se completó por un problema de '
        'conexión. Reintenta la misma operación para recuperar su resultado.',
        recoveryAction: PayrollReconciliationRecoveryAction.retry,
        canRetrySameOperation: true,
      );
    }

    return const PayrollReconciliationServiceException(
      'El servidor rechazó la operación de conciliación. Revisa los datos '
      'antes de volver a intentarlo.',
    );
  }

  bool _isAmbiguousNetworkFailure(String code, String evidence) {
    return code.startsWith('08') ||
        const <String>{
          '57p01',
          '57p02',
          '57p03',
          '53300',
          '53400',
          'pgrst000',
          'pgrst001',
          'pgrst002',
        }.contains(code) ||
        _containsAny(evidence, const <String>[
          'connection',
          'network',
          'socket',
          'timeout',
          'timed out',
          'temporarily unavailable',
          'service unavailable',
          'gateway timeout',
          'failed to fetch',
        ]);
  }

  bool _containsAny(String value, Iterable<String> needles) {
    return needles.any(value.contains);
  }

  Future<List<PayrollVoucher>> _loadOpenVouchers() async {
    final headers = await _payrollService.fetchVouchers(forceRefresh: true);
    final open = headers
        .where(
          (voucher) =>
              voucher.status == PayrollVoucherStatus.draft ||
              voucher.status == PayrollVoucherStatus.confirmed ||
              voucher.status == PayrollVoucherStatus.partial,
        )
        .toList(growable: false);

    return Future.wait(
      open.map(_payrollService.hydrateVoucherSettlements),
    );
  }

  Future<Map<String, Map<String, dynamic>>> _loadEmployeeRows() async {
    final rows = await _database.select(
      'employees',
      selectColumns: 'id,first_name,last_name,status,preferred_payment_method,'
          'preferred_payment_method_id',
      orderBy: 'first_name',
    );
    return <String, Map<String, dynamic>>{
      for (final row in rows)
        if (row['id'] != null) row['id'].toString(): row,
    };
  }

  Future<Map<String, List<String>>> _loadBeneficiaryAliases() async {
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _database.select(
        'payroll_beneficiary_aliases',
        selectColumns: 'employee_id,alias',
        orderBy: 'alias',
      );
    } on PostgrestException catch (error) {
      // Only a backend that predates the alias migration degrades to "no
      // aliases yet". Authorization, connectivity and every other failure
      // stay visible instead of silently weakening the matcher.
      if (!_isMissingBeneficiaryAliasTable(error)) rethrow;
      debugPrint(
        '⚠️ [PayrollReconciliationService] Backend sin aliases de '
        'beneficiario: preparando sin nombres alternativos.',
      );
      return const <String, List<String>>{};
    }
    final aliases = <String, List<String>>{};
    for (final row in rows) {
      final employeeId = row['employee_id']?.toString();
      final alias = row['alias']?.toString().trim();
      if (employeeId == null || alias == null || alias.isEmpty) continue;
      aliases.putIfAbsent(employeeId, () => <String>[]).add(alias);
    }
    return aliases;
  }

  bool _isMissingBeneficiaryAliasTable(PostgrestException error) {
    final diagnostic = <Object?>[
      error.message,
      error.details,
      error.hint,
    ].whereType<Object>().join(' ').toLowerCase();
    final identifiesTable = diagnostic.contains('payroll_beneficiary_aliases');
    final tableIsUnavailable = error.code == 'PGRST205' ||
        error.code == '42P01' ||
        diagnostic.contains('schema cache') ||
        diagnostic.contains('does not exist') ||
        diagnostic.contains('could not find the table');
    // A missing COLUMN on an existing table (half-migrated backend) names
    // the table too but is contract drift: keep it loudly visible.
    final isColumnError =
        error.code == '42703' || diagnostic.contains('column');
    return identifiesTable && tableIsUnavailable && !isColumnError;
  }

  Future<Map<String, String>> _loadPriorDecisionIds({
    required Map<String, String> rowFingerprintsBySourceRowId,
    String? excludingImportId,
  }) async {
    final fingerprints =
        rowFingerprintsBySourceRowId.values.toSet().toList(growable: false);
    if (fingerprints.isEmpty) return const <String, String>{};
    final List<Map<String, dynamic>> rows;
    try {
      rows = await _database.select(
        'payroll_statement_decisions',
        selectColumns: 'id,row_fingerprint,import_id,action,outcome,decided_at',
        where: 'row_fingerprint',
        whereIn: fingerprints,
        orderBy: 'decided_at',
        descending: true,
      );
    } on PostgrestException catch (error) {
      // A backend without the reconciliation migration has no decisions
      // table; the read-only preview simply has no prior decisions. Every
      // other failure (authorization, connectivity) stays visible, and the
      // server commands still gate import/apply themselves.
      if (!_isMissingReconciliationDecisionsTable(error)) rethrow;
      debugPrint(
        '⚠️ [PayrollReconciliationService] Backend sin conciliación: '
        'preparando vista previa sin decisiones anteriores.',
      );
      return const <String, String>{};
    }
    final priorIdByFingerprint = <String, String>{};
    for (final row in rows) {
      final fingerprint = row['row_fingerprint']?.toString();
      final decisionId = row['id']?.toString();
      if (fingerprint == null ||
          decisionId == null ||
          row['import_id']?.toString() == excludingImportId ||
          row['action']?.toString() == 'already_resolved' ||
          !const {'applied', 'acknowledged', 'held'}
              .contains(row['outcome']?.toString())) {
        continue;
      }
      priorIdByFingerprint.putIfAbsent(fingerprint, () => decisionId);
    }
    return <String, String>{
      for (final entry in rowFingerprintsBySourceRowId.entries)
        if (priorIdByFingerprint[entry.value] case final priorId?)
          entry.key: priorId,
    };
  }

  bool _isMissingReconciliationDecisionsTable(PostgrestException error) {
    final diagnostic = <Object?>[
      error.message,
      error.details,
      error.hint,
    ].whereType<Object>().join(' ').toLowerCase();
    final identifiesTable = diagnostic.contains('payroll_statement_decisions');
    final tableIsUnavailable = error.code == 'PGRST205' ||
        error.code == '42P01' ||
        diagnostic.contains('schema cache') ||
        diagnostic.contains('does not exist') ||
        diagnostic.contains('could not find the table');
    // A missing COLUMN on an existing table (half-migrated backend) names
    // the table too but is contract drift: keep it loudly visible.
    final isColumnError =
        error.code == '42703' || diagnostic.contains('column');
    return identifiesTable && tableIsUnavailable && !isColumnError;
  }

  PayrollReconciliationPaymentMethod _paymentMethodFor({
    required Map<String, dynamic>? canonicalMethod,
    required String? legacyValue,
  }) {
    final normalizedCanonicalCode = normalizePayrollReconciliationText(
      canonicalMethod?['code']?.toString() ?? '',
    );
    final normalizedLegacy =
        normalizePayrollReconciliationText(legacyValue ?? '');

    if (normalizedCanonicalCode == 'cash') {
      return PayrollReconciliationPaymentMethod.cash;
    }
    if (normalizedCanonicalCode == 'transfer') {
      return PayrollReconciliationPaymentMethod.transfer;
    }
    if (canonicalMethod == null && normalizedLegacy.contains('transfer')) {
      return PayrollReconciliationPaymentMethod.transfer;
    }
    if (canonicalMethod == null &&
        (normalizedLegacy.contains('efectivo') ||
            normalizedLegacy.contains('cash'))) {
      return PayrollReconciliationPaymentMethod.cash;
    }
    return PayrollReconciliationPaymentMethod.other;
  }

  bool _isUsableCanonicalMethod(Map<String, dynamic>? method) {
    if (method == null || method['is_active'] == false) return false;
    final code =
        normalizePayrollReconciliationText(method['code']?.toString() ?? '');
    if (code != 'transfer' && code != 'cash') return false;
    return method['account_id']?.toString().trim().isNotEmpty == true;
  }

  int? _inferStatementYear(PayrollStatementExtractionResult extraction) {
    final counts = <int, int>{};
    final yearPattern = RegExp(r'\b(20\d{2})\b');
    for (final page in extraction.pages) {
      for (final match in yearPattern.allMatches(page.text)) {
        final year = int.tryParse(match.group(1)!);
        if (year != null) {
          counts.update(year, (count) => count + 1, ifAbsent: () => 1);
        }
      }
    }
    if (counts.isEmpty) return null;
    final ranked = counts.entries.toList()
      ..sort((left, right) {
        final countComparison = right.value.compareTo(left.value);
        return countComparison != 0
            ? countComparison
            : right.key.compareTo(left.key);
      });
    return ranked.first.key;
  }

  PayrollCivilDate? _extractDocumentDate(
    PayrollStatementExtractionResult extraction,
  ) {
    final headerText =
        extraction.pages.take(2).map((page) => page.text).join('\n');
    final patterns = <RegExp>[
      RegExp(
        r'\b(?:movimientos|cartola)[^\n]{0,80}?\bal\s+'
        r'(\d{1,2})/(\d{1,2})/(\d{4})\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:fecha\s+(?:de\s+)?(?:cartola|emisi[oó]n|cierre))'
        r'\s*:?\s*(\d{1,2})/(\d{1,2})/(\d{4})\b',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(headerText);
      if (match == null) continue;
      final day = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);
      final year = int.tryParse(match.group(3)!);
      if (day == null ||
          month == null ||
          year == null ||
          !PayrollCivilDate.isValid(year, month, day)) {
        continue;
      }
      return PayrollCivilDate(year, month, day);
    }
    return null;
  }

  Map<String, String> _fingerprintsFor(
    List<PayrollStatementRow> rows, {
    required String accountFingerprint,
  }) {
    final result = <String, String>{};
    final occurrencesByEvidence = <String, int>{};
    for (final row in rows) {
      final direction = switch (row.direction) {
        PayrollStatementMovementDirection.outgoing => 'debit',
        PayrollStatementMovementDirection.incoming => 'credit',
        PayrollStatementMovementDirection.unknown => '',
      };
      final amount = switch (row.direction) {
        PayrollStatementMovementDirection.outgoing => row.debitAmountClp,
        PayrollStatementMovementDirection.incoming => row.creditAmountClp,
        PayrollStatementMovementDirection.unknown => null,
      };
      final document =
          normalizePayrollReconciliationText(row.documentNumber ?? '');
      final beneficiary =
          normalizePayrollReconciliationText(row.beneficiaryObserved ?? '');
      final occurrenceBase = [
        row.bookingDate?.toString() ?? '',
        direction,
        amount == null ? '' : '$amount.00',
        row.normalizedDescription,
        beneficiary,
        document,
      ].join('|');
      final occurrence = occurrencesByEvidence.update(
        occurrenceBase,
        (current) => current + 1,
        ifAbsent: () => 1,
      );
      final base = [
        accountFingerprint,
        row.bookingDate?.toString() ?? '',
        direction,
        amount == null ? '' : '$amount.00',
        row.normalizedDescription,
        beneficiary,
        document,
        occurrence,
      ].join('|');
      result[row.sourceRowId] = sha256.convert(utf8.encode(base)).toString();
    }
    return result;
  }

  List<Map<String, dynamic>> _serializeStatementRows(
    PayrollStatementPreparedDraft draft,
  ) {
    final occurrencesByBase = <String, int>{};
    final serialized = <Map<String, dynamic>>[];

    for (final row in draft.parseResult.rows) {
      final date = row.bookingDate;
      final direction = switch (row.direction) {
        PayrollStatementMovementDirection.outgoing => 'debit',
        PayrollStatementMovementDirection.incoming => 'credit',
        PayrollStatementMovementDirection.unknown => null,
      };
      final amount = switch (row.direction) {
        PayrollStatementMovementDirection.outgoing => row.debitAmountClp,
        PayrollStatementMovementDirection.incoming => row.creditAmountClp,
        PayrollStatementMovementDirection.unknown => null,
      };
      final occurrenceBase = [
        date?.toString() ?? '',
        direction ?? '',
        amount?.toString() ?? '',
        row.normalizedDescription,
        normalizePayrollReconciliationText(row.beneficiaryObserved ?? ''),
        normalizePayrollReconciliationText(row.documentNumber ?? ''),
      ].join('|');
      final occurrence = occurrencesByBase.update(
        occurrenceBase,
        (current) => current + 1,
        ifAbsent: () => 1,
      );
      serialized.add(<String, dynamic>{
        'ordinal': row.evidence.sourceRowNumber,
        'page': row.evidence.startPageNumber,
        'source_line_start': row.evidence.startLineNumber,
        'source_line_end': row.evidence.endLineNumber,
        'source_occurrence': occurrence,
        'transaction_date': date?.toString(),
        'direction': direction,
        'amount': amount,
        'description_observed':
            row.description.trim().isEmpty ? null : row.description,
        'beneficiary_observed': row.beneficiaryObserved,
        'document_observed': row.documentNumber,
        'fingerprint': draft.rowFingerprintsBySourceRowId[row.sourceRowId],
        'warnings': <String>[
          ...row.parseWarningCodes,
          if (!row.hasCompleteStructuredEvidence) 'incomplete_evidence',
          if (row.bookingDate != null &&
              draft.documentDate != null &&
              row.bookingDate!.compareTo(draft.documentDate!) > 0)
            'out_of_statement_range',
        ],
      });
    }
    return serialized;
  }

  Map<String, dynamic> _sourceMetadata(
    PayrollStatementPreparedDraft draft, {
    required String erpAccountId,
  }) {
    final dates = draft.parseResult.rows
        .map((row) => row.bookingDate)
        .whereType<PayrollCivilDate>()
        .toList()
      ..sort();
    return <String, dynamic>{
      'parser_name': parserName,
      'parser_version': parserVersion,
      'source_type': _sourceType(draft.extraction),
      'page_count': draft.extraction.pages.length,
      'extraction_kind': draft.extraction.method.name,
      'account_fingerprint': draft.accountFingerprint,
      'erp_account_id': erpAccountId,
      'locale': 'es-CL',
      if (dates.isNotEmpty) 'statement_start': dates.first.toString(),
      if (dates.isNotEmpty)
        'statement_end': (draft.documentDate ?? dates.last).toString(),
      if (draft.documentDate != null)
        'document_date': draft.documentDate.toString(),
      'bank_name': 'Banco de Chile',
    };
  }

  String _sourceType(PayrollStatementExtractionResult extraction) {
    if (extraction.inputKind == PayrollStatementInputKind.pdf) {
      return extraction.method ==
              PayrollStatementExtractionMethod.embeddedPdfText
          ? 'pdf_text'
          : 'pdf_ocr';
    }
    return 'image_ocr';
  }

  String? _extractAccountFingerprint(
    PayrollStatementExtractionResult extraction,
  ) {
    final headerText =
        extraction.pages.take(2).map((page) => page.text).join('\n');
    final patterns = <RegExp>[
      RegExp(
        r'cuenta\s*(?:corriente\s*)?'
        r'(?:n(?:ro\.?|[°ºo])\s*)?:?\s*'
        r'([0-9][0-9.\-\s]{5,30})',
        caseSensitive: false,
      ),
      RegExp(
        r'n[uú]mero\s+de\s+cuenta\s*:?\s*'
        r'([0-9][0-9.\-\s]{5,30})',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final observed = pattern.firstMatch(headerText)?.group(1);
      final canonical = observed?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
      if (canonical.length >= 6 && canonical.length <= 24) {
        return sha256.convert(utf8.encode('banco_chile|$canonical')).toString();
      }
    }
    return null;
  }

  void _validateDecisionCoverage({
    required PayrollStatementPreparedDraft draft,
    required PayrollStatementImportReceipt importReceipt,
    required List<PayrollStatementReviewDecision> decisions,
  }) {
    if (importReceipt.importId.isEmpty ||
        importReceipt.rowIdsBySourceRowId.length !=
            draft.parseResult.rows.length) {
      throw const PayrollReconciliationServiceException(
        'La evidencia importada está incompleta. Vuelve a cargar la cartola.',
      );
    }

    final reviewedSourceRows = <String>{};
    for (final decision in decisions) {
      final requiresBankRow =
          decision.kind == PayrollReviewDecisionKind.bankPayment ||
              decision.kind == PayrollReviewDecisionKind.ignore ||
              decision.kind == PayrollReviewDecisionKind.hold ||
              decision.kind == PayrollReviewDecisionKind.alreadyResolved;
      if (requiresBankRow) {
        final sourceRowId = decision.sourceRowId;
        if (sourceRowId == null ||
            !importReceipt.rowIdsBySourceRowId.containsKey(sourceRowId)) {
          throw const PayrollReconciliationServiceException(
            'Cada movimiento bancario debe conservar su fila de evidencia.',
          );
        }
        if (!reviewedSourceRows.add(sourceRowId)) {
          throw const PayrollReconciliationServiceException(
            'Un movimiento bancario tiene más de una decisión.',
          );
        }
      } else if (decision.sourceRowId != null) {
        throw const PayrollReconciliationServiceException(
          'El efectivo, los anticipos y los no pagados no pueden inventar una '
          'fila bancaria.',
        );
      }

      if (decision.kind == PayrollReviewDecisionKind.alreadyResolved) {
        final sourceRowId = decision.sourceRowId!;
        final expectedPrior =
            importReceipt.priorDecisionIdsBySourceRowId[sourceRowId];
        if (expectedPrior == null ||
            decision.priorDecisionId != expectedPrior ||
            decision.voucherLineId != null ||
            decision.amountClp != null ||
            decision.paymentMethodId != null ||
            decision.paymentAccountId != null) {
          throw const PayrollReconciliationServiceException(
            'La referencia a una conciliación anterior cambió. Recarga la '
            'cartola antes de aplicar.',
          );
        }
      } else if (decision.priorDecisionId != null) {
        throw const PayrollReconciliationServiceException(
          'Solo una fila ya resuelta puede citar una decisión anterior.',
        );
      }

      if (decision.varianceDisposition ==
          PayrollVarianceDisposition.employeeAdvance) {
        throw const PayrollReconciliationServiceException(
          'El residuo bancario debe quedar no resuelto; no se convierte en '
          'anticipo automáticamente.',
        );
      }
      if (decision.kind == PayrollReviewDecisionKind.bankPayment &&
          const <PayrollVarianceDisposition>{
            PayrollVarianceDisposition.partial,
            PayrollVarianceDisposition.unresolved,
          }.contains(decision.varianceDisposition) &&
          (!decision.manualConfirmation ||
              (decision.note?.trim().isEmpty ?? true))) {
        throw const PayrollReconciliationServiceException(
          'Confirma y explica cualquier diferencia entre la transferencia y '
          'la obligación.',
        );
      }
      if ((decision.kind == PayrollReviewDecisionKind.cashPayment ||
              decision.kind == PayrollReviewDecisionKind.notPaid) &&
          !decision.manualConfirmation) {
        throw const PayrollReconciliationServiceException(
          'Los pagos en efectivo y los no pagados requieren confirmación '
          'manual explícita.',
        );
      }
      if ((decision.kind == PayrollReviewDecisionKind.ignore ||
              decision.kind == PayrollReviewDecisionKind.hold ||
              decision.kind == PayrollReviewDecisionKind.notPaid ||
              decision.kind == PayrollReviewDecisionKind.alreadyResolved) &&
          (decision.note?.trim().isEmpty ?? true)) {
        throw const PayrollReconciliationServiceException(
          'La decisión requiere una razón para conservar la auditoría.',
        );
      }
    }

    if (reviewedSourceRows.length != importReceipt.rowIdsBySourceRowId.length) {
      throw const PayrollReconciliationServiceException(
        'Debes decidir explícitamente qué hacer con cada fila de la cartola.',
      );
    }
  }

  Map<String, dynamic> _serializeDecision(
    PayrollStatementImportReceipt importReceipt,
    PayrollStatementReviewDecision decision,
    int ordinal,
  ) {
    final rowId = decision.sourceRowId == null
        ? null
        : importReceipt.rowIdsBySourceRowId[decision.sourceRowId];
    final isBankPayment =
        decision.kind == PayrollReviewDecisionKind.bankPayment;
    return <String, dynamic>{
      'ordinal': ordinal,
      'action': switch (decision.kind) {
        PayrollReviewDecisionKind.bankPayment => 'bank_payment',
        PayrollReviewDecisionKind.cashPayment => 'cash_payment',
        PayrollReviewDecisionKind.advanceAllocation => 'advance_allocation',
        PayrollReviewDecisionKind.ignore => 'ignore',
        PayrollReviewDecisionKind.hold => 'hold',
        PayrollReviewDecisionKind.notPaid => 'not_paid',
        PayrollReviewDecisionKind.alreadyResolved => 'already_resolved',
      },
      'row_id': rowId,
      if (decision.kind == PayrollReviewDecisionKind.alreadyResolved)
        'row_fingerprint': decision.sourceRowId == null
            ? null
            : importReceipt.rowFingerprintsBySourceRowId[decision.sourceRowId],
      'prior_decision_id': decision.priorDecisionId,
      'voucher_line_id': decision.voucherLineId,
      'applied_amount': decision.amountClp,
      'payment_date': decision.paymentDate?.toString(),
      'payment_method_id': decision.paymentMethodId,
      'payment_account_id': decision.paymentAccountId,
      'advance_id': decision.advanceId,
      'variance_disposition': isBankPayment
          ? switch (decision.varianceDisposition) {
              PayrollVarianceDisposition.none => 'exact',
              PayrollVarianceDisposition.partial => 'partial',
              PayrollVarianceDisposition.unresolved => 'unresolved',
              PayrollVarianceDisposition.employeeAdvance => 'unresolved',
            }
          : null,
      'manual_confirmation': decision.manualConfirmation,
      'reason': decision.note,
    };
  }

  Map<String, dynamic> _asJsonObject(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const PayrollReconciliationServiceException(
      'El servidor devolvió una respuesta de conciliación inválida.',
    );
  }

  bool _sameStringMap(Map<String, String> left, Map<String, String> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  bool _sameStringSet(Set<String> left, Set<String> right) {
    return left.length == right.length && left.containsAll(right);
  }

  bool _looksLikeUuid(String value) {
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
      r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(value);
  }
}
