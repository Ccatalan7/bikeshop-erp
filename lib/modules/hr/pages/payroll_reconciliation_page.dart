import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/current_user_profile_service.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/return_navigation.dart';
import '../models/payroll_statement_reconciliation.dart';
import '../models/payroll_voucher.dart';
import '../payroll/surfaces/payroll_accent_action.dart';
import '../payroll/surfaces/payroll_reconciliation_surface.dart';
import '../payroll/surfaces/payroll_transfer_review_surface.dart';
import '../payroll/theme/payroll_tokens.dart';
import '../services/payroll_reconciliation_service.dart';
import '../services/payroll_statement_capture_cleanup.dart';
import '../services/payroll_statement_extraction_service.dart';
import '../services/payroll_statement_local_image_ocr.dart';
import '../services/payroll_voucher_service.dart';
import '../widgets/payroll_format.dart';
import '../widgets/payroll_money_bar.dart';
import '../widgets/payroll_payment_sheet.dart'
    show ClpAmountInputFormatter, parsePayrollAmount;
import '../widgets/payroll_reconciliation_row.dart';

/// A statement chosen by the operator. Bytes stay in memory only.
@immutable
class PayrollPickedStatement {
  const PayrollPickedStatement({
    required this.bytes,
    required this.filename,
    this.sourcePath,
  });

  final Uint8List bytes;
  final String filename;
  final String? sourcePath;
}

typedef PayrollStatementPicker = Future<PayrollPickedStatement?> Function();

typedef PayrollStatementProgressPrepare = Future<PayrollStatementPreparedDraft>
    Function({
  required Uint8List bytes,
  required String filename,
  String? sourcePath,
  required PayrollStatementPreparationProgressCallback onProgress,
});

@immutable
class PayrollStatementCaptureCapabilities {
  const PayrollStatementCaptureCapabilities({
    required this.supportsImages,
    required this.supportsCamera,
  });

  final bool supportsImages;
  final bool supportsCamera;
  bool get supportsGallery => supportsImages;
}

/// Resolves picker capabilities independently from viewport composition.
///
/// Local image OCR is available on Android, iOS and macOS. Camera capture is
/// intentionally narrower: only Android and iOS. Web always remains
/// text-PDF-only even if a test adapter is accidentally supplied.
@visibleForTesting
PayrollStatementCaptureCapabilities payrollStatementCaptureCapabilities({
  required bool isWeb,
  required TargetPlatform platform,
  required bool localImageOcrSupported,
}) {
  final supportsImages = !isWeb && localImageOcrSupported;
  final supportsCamera = supportsImages &&
      (platform == TargetPlatform.android || platform == TargetPlatform.iOS);
  return PayrollStatementCaptureCapabilities(
    supportsImages: supportsImages,
    supportsCamera: supportsCamera,
  );
}

/// Converts the file-picker result without evaluating [PlatformFile.path] on
/// web, where that getter throws even though the requested bytes are present.
///
/// [isWeb] is exposed for the focused regression test; production callers use
/// the compile-time [kIsWeb] value.
@visibleForTesting
PayrollPickedStatement? payrollPickedStatementFromPlatformFile(
  PlatformFile? file, {
  bool isWeb = kIsWeb,
}) {
  final bytes = file?.bytes;
  if (file == null || bytes == null) return null;
  return PayrollPickedStatement(
    bytes: bytes,
    filename: file.name,
    sourcePath: isWeb ? null : file.path,
  );
}

/// The three service operations this page is allowed to issue.
@immutable
class PayrollReconciliationActions {
  const PayrollReconciliationActions({
    required this.prepare,
    required this.createImport,
    required this.apply,
    this.prepareWithProgress,
    this.learnBeneficiaryAlias,
    this.refresh,
    this.isImageOcrSupported = false,
    this.isCameraCaptureSupported = false,
    this.versionedCommandsProbe,
  });

  final Future<PayrollStatementPreparedDraft> Function({
    required Uint8List bytes,
    required String filename,
    String? sourcePath,
  }) prepare;
  final PayrollStatementProgressPrepare? prepareWithProgress;

  final Future<PayrollStatementImportReceipt> Function(
    PayrollStatementPreparedDraft draft, {
    required String erpAccountId,
  }) createImport;

  final Future<PayrollStatementApplyReceipt> Function({
    required PayrollStatementPreparedDraft draft,
    required PayrollStatementImportReceipt importReceipt,
    required List<PayrollStatementReviewDecision> decisions,
    required Set<String> authorizedDraftVoucherIds,
    String? operationKey,
  }) apply;

  final Future<PayrollBeneficiaryAliasLearnReceipt> Function({
    required String employeeId,
    required String alias,
  })? learnBeneficiaryAlias;

  /// Refreshes ERP-owned context while retaining the already extracted
  /// statement evidence and its stable operation key.
  final Future<PayrollStatementPreparedDraft> Function(
    PayrollStatementPreparedDraft draft,
  )? refresh;

  /// Whether an image can be read without leaving the device.
  final bool isImageOcrSupported;
  final bool isCameraCaptureSupported;

  /// Tri-state versioned-backend probe: `null` = unknown yet, `false` =
  /// confirmed absent (review stays available; import/apply are blocked with
  /// the reason visible), `true` = installed. Absent callback behaves as
  /// unknown so injected test actions keep the full flow.
  final bool? Function()? versionedCommandsProbe;
}

enum PayrollReconciliationStage { file, extract, review, apply }

extension _StageCopy on PayrollReconciliationStage {
  String get label => switch (this) {
        PayrollReconciliationStage.file => 'Subir cartola',
        PayrollReconciliationStage.extract => 'Extraer',
        PayrollReconciliationStage.review => 'Revisar',
        PayrollReconciliationStage.apply => 'Aplicar',
      };
}

enum _CashDisposition {
  pending,
  notPaid,
  cashPayment,
}

/// Cash is a stage of its own: it is never inferred from a bank movement.
///
/// A resolved obligation may combine any number of eligible advances with new
/// cash. The pieces remain separate decisions so their evidence is auditable.
class _CashAnswer {
  _CashAnswer({DateTime? date, this.amount}) : date = date ?? DateTime.now();

  _CashDisposition disposition = _CashDisposition.pending;
  DateTime date;

  /// New cash handed over for this obligation. Advance allocations are kept
  /// independently in [selectedAdvanceIds].
  double? amount;
  final Set<String> selectedAdvanceIds = <String>{};

  bool get isAnswered => switch (disposition) {
        _CashDisposition.pending => false,
        _CashDisposition.notPaid => true,
        _CashDisposition.cashPayment =>
          (amount ?? 0) > 0 || selectedAdvanceIds.isNotEmpty,
      };
}

@immutable
class _ErpBankAccountOption {
  const _ErpBankAccountOption({
    required this.accountId,
    required this.label,
  });

  final String accountId;
  final String label;
}

@immutable
class _ConfirmationItem {
  const _ConfirmationItem({
    required this.title,
    required this.subtitle,
    required this.action,
    required this.amountClp,
    required this.weekLabel,
    required this.isMoney,
    this.accountLabel,
  });

  final String title;
  final String subtitle;
  final String action;
  final int amountClp;

  /// Grouping key of the final summary; weeks first, then everything else.
  final String weekLabel;

  /// Whether [amountClp] represents money being recognized (vs. informative
  /// pending amounts on "not paid" rows).
  final bool isMoney;
  final String? accountLabel;
}

@immutable
class _AliasLearningIntent {
  const _AliasLearningIntent({
    required this.sourceRowId,
    required this.employeeId,
    required this.employeeName,
    required this.alias,
  });

  final String sourceRowId;
  final String employeeId;
  final String employeeName;
  final String alias;
}

/// Bank statement reconciliation, staged so nothing is applied by accident.
///
/// The page owns no matching logic: proposals, reasons, tolerance and variance
/// all come from `PayrollStatementMatcher` through the prepared draft. Every
/// outgoing movement needs an explicit human disposition, and the batch is
/// committed once through `createImport` followed by a single `apply`.
class PayrollReconciliationPage extends StatefulWidget {
  const PayrollReconciliationPage({
    super.key,
    this.actions,
    this.pickFile,
    this.pickCamera,
    this.pickGallery,
    this.onConfigureEmployeePaymentMethod,
    this.fallbackRoute = '/hr/payroll',
  });

  final PayrollReconciliationActions? actions;
  final PayrollStatementPicker? pickFile;
  final PayrollStatementPicker? pickCamera;
  final PayrollStatementPicker? pickGallery;
  final Future<void> Function(String employeeId)?
      onConfigureEmployeePaymentMethod;
  final String fallbackRoute;

  @override
  State<PayrollReconciliationPage> createState() =>
      _PayrollReconciliationPageState();
}

class _PayrollReconciliationPageState extends State<PayrollReconciliationPage> {
  PayrollReconciliationActions? _resolvedActions;

  PayrollReconciliationStage _stage = PayrollReconciliationStage.file;
  PayrollStatementPreparedDraft? _draft;
  PayrollStatementImportReceipt? _importReceipt;

  /// Kept across retries so a repeated apply is recognized as a replay instead
  /// of duplicating money.
  String? _applyOperationKey;

  final Map<String, PayrollRowDisposition> _dispositions = {};
  final Map<String, PayrollVarianceDisposition> _varianceDispositions = {};
  final Map<String, String> _reviewReasons = {};
  final Map<String, String> _manualLineBySourceRowId = {};
  final Set<String> _learnAliasSourceRowIds = <String>{};
  final Map<String, _CashAnswer> _cashAnswers = {};
  String? _selectedErpAccountId;

  /// Review groups open in stage 2. "Pendientes de decisión" starts open;
  /// batch suggestions and informational movements start collapsed.
  // Suggestions and real questions open by default: mandatory work is never
  // born hidden. Automatic classifications and informational movements stay
  // collapsed as auditable evidence.

  /// Secciones plegables de la etapa de revisión. Nacen CERRADAS: la carga
  /// humana la lidera la tarjeta de una pregunta a la vez, y todo lo demás es
  /// evidencia auditable que no debe competir por la atención.
  final Set<String> _openReviewGroups = <String>{};

  /// Pregunta mostrada en la tarjeta que encabeza la etapa. Avanza sólo por
  /// gesto explícito: responder no salta sola a la siguiente, porque el
  /// operador suele querer confirmar lo que acaba de decidir.
  int _pendingQuestionIndex = 0;

  /// Fila traída a la tarjeta desde un grupo plegado con «Ver». Manda sobre el
  /// índice: si el operador pidió mirar ese movimiento, ése es el que se
  /// muestra hasta que avance a mano.
  String? _stagedQuestionRowId;

  /// Filas que ya se contestaron pero SIGUEN mostrándose como pregunta. Una
  /// respuesta suele venir en dos tiempos —elegir, y después completar la
  /// diferencia, la razón de auditoría o el alias—, así que la fila no puede
  /// desaparecer al primer clic: se iría justo cuando falta la mitad del
  /// trabajo, y sin dejar verificar lo recién decidido.
  final Set<String> _answeredInPlaceRowIds = <String>{};

  /// The cash person currently being answered. Advancing to the next person
  /// is always an explicit tap, never automatic.
  String? _activeCashLineId;

  bool _isBusy = false;
  PayrollStatementPreparationProgress? _preparationProgress;
  String? _error;
  PayrollReconciliationRecoveryAction _errorRecoveryAction =
      PayrollReconciliationRecoveryAction.none;
  bool _canRetrySameOperation = false;
  String? _appliedMessage;
  int _appliedAmountClp = 0;
  PayrollStatementApplyReceipt? _appliedReceipt;
  List<PayrollStatementReviewDecision> _appliedDecisions = const [];
  List<_AliasLearningIntent> _pendingAliasIntents = const [];
  int _learnedAliasCount = 0;
  bool _isLearningAliases = false;
  String? _aliasLearningError;

  bool get _hasUnappliedDraft => _draft != null && _appliedMessage == null;

  /// Once the evidence import exists, the reviewed payload must stay byte-for-
  /// byte stable across a retry with the same idempotency key.
  bool get _isReviewLocked => _isBusy || _importReceipt != null;

  PayrollReconciliationActions _actions() {
    final injected = widget.actions;
    if (injected != null) return injected;
    return _resolvedActions ??= _providerActions();
  }

  PayrollReconciliationActions _providerActions() {
    final payrollService = context.read<PayrollVoucherService>();
    final service = PayrollReconciliationService(
      database: context.read<DatabaseService>(),
      payrollService: payrollService,
    );
    const ocr = PayrollStatementLocalImageOcr();
    final captureCapabilities = payrollStatementCaptureCapabilities(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
      localImageOcrSupported: ocr.isSupported,
    );
    return PayrollReconciliationActions(
      prepare: ({required bytes, required filename, sourcePath}) =>
          service.prepare(
        bytes: bytes,
        filename: filename,
        sourcePath: sourcePath,
      ),
      prepareWithProgress: ({
        required bytes,
        required filename,
        sourcePath,
        required onProgress,
      }) =>
          service.prepare(
        bytes: bytes,
        filename: filename,
        sourcePath: sourcePath,
        onProgress: onProgress,
      ),
      createImport: service.createImport,
      apply: service.apply,
      learnBeneficiaryAlias: service.learnBeneficiaryAlias,
      refresh: service.refreshPreparedDraft,
      isImageOcrSupported: captureCapabilities.supportsImages,
      isCameraCaptureSupported: captureCapabilities.supportsCamera,
      versionedCommandsProbe: () =>
          payrollService.versionedPayrollCommandsProbe,
    );
  }

  /// Confirmed-absent versioned backend. Unknown (`null`) keeps the full
  /// flow: the server commands still gate every write themselves.
  bool get _versionedBackendMissing =>
      _actions().versionedCommandsProbe?.call() == false;

  // ---------------------------------------------------------------------------
  // Stage 1 — file
  // ---------------------------------------------------------------------------

  Future<void> _choose(PayrollStatementPicker? picker) async {
    if (picker == null || _isBusy) return;
    if (_draft != null) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Reemplazar la cartola?'),
          content: const Text(
            'Se descartarán todas las decisiones de esta revisión. Una '
            'importación ya creada puede quedar como evidencia no aplicada.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Seguir revisando'),
            ),
            // accent-fill: dialog-action (resolver-owned M3 dialog grammar)
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Reemplazar'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    setState(() {
      _isBusy = true;
      _preparationProgress = const PayrollStatementPreparationProgress(
        phase: PayrollStatementPreparationPhase.validatingFile,
      );
      _error = null;
      _errorRecoveryAction = PayrollReconciliationRecoveryAction.none;
      _canRetrySameOperation = false;
    });
    try {
      final picked = await picker();
      if (picked == null) {
        if (mounted) {
          setState(() {
            _isBusy = false;
            _preparationProgress = null;
          });
        }
        return;
      }
      final actions = _actions();
      final prepareWithProgress = actions.prepareWithProgress;
      final draft = prepareWithProgress == null
          ? await actions.prepare(
              bytes: picked.bytes,
              filename: picked.filename,
              sourcePath: picked.sourcePath,
            )
          : await prepareWithProgress(
              bytes: picked.bytes,
              filename: picked.filename,
              sourcePath: picked.sourcePath,
              onProgress: _reportPreparationProgress,
            );
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _importReceipt = null;
        _applyOperationKey = null;
        _dispositions.clear();
        _varianceDispositions.clear();
        _reviewReasons.clear();
        _manualLineBySourceRowId.clear();
        _learnAliasSourceRowIds.clear();
        _cashAnswers.clear();
        _selectedErpAccountId = null;
        _appliedReceipt = null;
        _appliedDecisions = const [];
        _appliedMessage = null;
        _appliedAmountClp = 0;
        _pendingAliasIntents = const [];
        _learnedAliasCount = 0;
        _isLearningAliases = false;
        _aliasLearningError = null;
        _errorRecoveryAction = PayrollReconciliationRecoveryAction.none;
        _canRetrySameOperation = false;
        _stage = PayrollReconciliationStage.extract;
        _isBusy = false;
        _preparationProgress = null;
      });
    } catch (error) {
      if (!mounted) return;
      final typed =
          error is PayrollReconciliationServiceException ? error : null;
      setState(() {
        // Service exceptions carry operator-ready copy; anything else stays
        // in the app log instead of leaking a technical trace to the screen.
        _error = typed != null
            ? typed.message
            : 'No pudimos leer la cartola. El detalle técnico quedó en el '
                'registro de la aplicación.';
        _errorRecoveryAction =
            typed?.recoveryAction ?? PayrollReconciliationRecoveryAction.none;
        _canRetrySameOperation = typed?.canRetrySameOperation ?? false;
        _isBusy = false;
        _preparationProgress = null;
      });
      _logFailure('Falla al preparar cartola', error);
    }
  }

  void _reportPreparationProgress(
    PayrollStatementPreparationProgress progress,
  ) {
    if (!mounted) return;
    setState(() => _preparationProgress = progress);
  }

  void _logFailure(String operation, Object error) {
    // Never interpolate the exception itself: OCR adapters and filesystem
    // failures may embed statement text, account data or sensitive paths.
    debugPrint(
      '❌ [PayrollReconciliation] $operation (${error.runtimeType})',
    );
  }

  Future<PayrollPickedStatement?> _defaultFilePicker() async {
    final supportsImages = _actions().isImageOcrSupported;
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: supportsImages
          ? const ['pdf', 'jpg', 'jpeg', 'png', 'webp']
          : const ['pdf'],
    );
    final file = result?.files.singleOrNull;
    return payrollPickedStatementFromPlatformFile(file);
  }

  Future<PayrollPickedStatement?> _defaultImagePicker(
      ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return null;
    final sourcePath = kIsWeb ? null : picked.path;
    try {
      final bytes = await picked.readAsBytes();
      return PayrollPickedStatement(
        bytes: bytes,
        filename: picked.name,
        sourcePath: source == ImageSource.camera ? null : sourcePath,
      );
    } finally {
      if (source == ImageSource.camera) {
        // ImagePicker owns this camera artifact. OCR receives the in-memory
        // bytes and creates its own short-lived copy, so the sensitive
        // capture never outlives this scope in the picker cache — even when
        // readAsBytes throws.
        await cleanupPayrollStatementCameraCapture(sourcePath);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Derived review model
  // ---------------------------------------------------------------------------

  List<_ErpBankAccountOption> get _bankAccountOptions {
    final draft = _draft;
    if (draft == null) return const [];
    final byAccountId = <String, _ErpBankAccountOption>{};
    for (final method in draft.paymentMethods) {
      if (method['is_active'] == false) continue;
      if (!_isCanonicalTransferMethod(method)) continue;
      final accountId = method['account_id']?.toString().trim() ?? '';
      if (accountId.isEmpty) continue;
      final methodName = method['name']?.toString().trim();
      final accountLabel = method['account_name']?.toString().trim();
      final accountCode = method['account_code']?.toString().trim();
      final details = <String>[
        if (accountCode != null && accountCode.isNotEmpty) accountCode,
        if (accountLabel != null && accountLabel.isNotEmpty) accountLabel,
        if ((accountCode == null || accountCode.isEmpty) &&
            (accountLabel == null || accountLabel.isEmpty))
          'Cuenta ERP …${_maskedSuffix(accountId)}',
      ].join(' · ');
      byAccountId.putIfAbsent(
        accountId,
        () => _ErpBankAccountOption(
          accountId: accountId,
          label: [
            if (methodName != null && methodName.isNotEmpty)
              methodName
            else
              'Transferencia bancaria',
            if (details.isNotEmpty) details,
          ].join(' · '),
        ),
      );
    }
    return List<_ErpBankAccountOption>.unmodifiable(byAccountId.values);
  }

  Map<String, dynamic>? _methodForEmployee(String? employeeId) {
    final draft = _draft;
    if (draft == null || employeeId == null) return null;
    final methodId = draft.employeeRowsById[employeeId]
            ?['preferred_payment_method_id']
        ?.toString()
        .trim();
    if (methodId == null || methodId.isEmpty) return null;
    for (final method in draft.paymentMethods) {
      if (method['id']?.toString() == methodId) return method;
    }
    return null;
  }

  bool _isUsableCanonicalMethod(Map<String, dynamic>? method) {
    if (method == null || method['is_active'] == false) return false;
    final accountId = method['account_id']?.toString().trim() ?? '';
    return accountId.isNotEmpty &&
        (_isCanonicalTransferMethod(method) || _isCanonicalCashMethod(method));
  }

  PayrollReconciliationVoucherLine? _reconciliationLineFor(
    String? voucherLineId,
  ) {
    final draft = _draft;
    if (draft == null || voucherLineId == null) return null;
    for (final result in draft.reconciliation.lineResults) {
      if (result.voucherLine.lineId == voucherLineId) {
        return result.voucherLine;
      }
    }
    return null;
  }

  Map<String, dynamic>? _methodForLine(
    String? voucherLineId, {
    String? fallbackEmployeeId,
  }) {
    final draft = _draft;
    if (draft == null) return null;
    final line = _reconciliationLineFor(voucherLineId);
    final snapshotMethodId = line?.paymentMethodId?.trim();
    if (snapshotMethodId != null && snapshotMethodId.isNotEmpty) {
      for (final method in draft.paymentMethods) {
        if (method['id']?.toString() == snapshotMethodId &&
            _isUsableCanonicalMethod(method)) {
          return method;
        }
      }
    }
    final employeeMethod =
        _methodForEmployee(line?.employeeId ?? fallbackEmployeeId);
    return _isUsableCanonicalMethod(employeeMethod) ? employeeMethod : null;
  }

  String _methodCode(Map<String, dynamic>? method) =>
      method?['code']?.toString().trim().toLowerCase() ?? '';

  bool _isCanonicalTransferMethod(Map<String, dynamic>? method) =>
      _methodCode(method) == 'transfer';

  bool _isCanonicalCashMethod(Map<String, dynamic>? method) =>
      _methodCode(method) == 'cash';

  String _employeeNameFor(String employeeId) {
    final row = _draft?.employeeRowsById[employeeId];
    final profileName = [
      row?['first_name']?.toString().trim() ?? '',
      row?['last_name']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).join(' ');
    if (profileName.isNotEmpty) return profileName;
    for (final voucher in _draft?.vouchers ?? const <PayrollVoucher>[]) {
      for (final line in voucher.lines) {
        if (line.employeeId == employeeId &&
            line.employeeName.trim().isNotEmpty) {
          return line.employeeName.trim();
        }
      }
    }
    return 'Persona sin ficha';
  }

  String get _authenticatedActorLabel {
    final displayName = context
            .read<CurrentUserProfileService?>()
            ?.profile
            ?.displayName
            .trim() ??
        '';
    return displayName.isEmpty ? 'Usuario autenticado' : displayName;
  }

  Future<void> _configureEmployeePaymentMethod(String employeeId) async {
    if (_isReviewLocked) return;
    final injected = widget.onConfigureEmployeePaymentMethod;
    if (injected != null) {
      await injected(employeeId);
    } else {
      await context.push('/hr/employees/${Uri.encodeComponent(employeeId)}');
    }
    if (!mounted) return;
    await _refreshAfterPaymentMethodConfiguration(employeeId);
  }

  Future<void> _refreshAfterPaymentMethodConfiguration(
    String employeeId,
  ) async {
    final current = _draft;
    final refresh = _actions().refresh;
    if (current == null || refresh == null || _importReceipt != null) {
      if (mounted) {
        setState(() {
          _error =
              'No pudimos refrescar la configuración sin perder la revisión. '
              'Vuelve a Nóminas y carga nuevamente la cartola.';
        });
      }
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
      _errorRecoveryAction = PayrollReconciliationRecoveryAction.none;
      _canRetrySameOperation = false;
    });
    try {
      final refreshed = await refresh(current);
      if (!mounted) return;
      setState(() {
        _draft = refreshed;

        final validSourceRowIds =
            refreshed.parseResult.rows.map((row) => row.sourceRowId).toSet();
        final validLineIds = refreshed.reconciliation.lineResults
            .map((result) => result.voucherLine.lineId)
            .toSet();
        _manualLineBySourceRowId.removeWhere(
          (sourceRowId, lineId) =>
              !validSourceRowIds.contains(sourceRowId) ||
              !validLineIds.contains(lineId),
        );
        _learnAliasSourceRowIds.removeWhere(
            (sourceRowId) => !validSourceRowIds.contains(sourceRowId));

        final validReviewRowIds = _transferRows.map((row) => row.id).toSet();
        _dispositions
            .removeWhere((rowId, _) => !validReviewRowIds.contains(rowId));
        _varianceDispositions
            .removeWhere((rowId, _) => !validReviewRowIds.contains(rowId));
        _reviewReasons
            .removeWhere((rowId, _) => !validReviewRowIds.contains(rowId));

        final validCashLineIds =
            _cashLines.map((line) => line.voucherLine.lineId).toSet();
        _cashAnswers
            .removeWhere((lineId, _) => !validCashLineIds.contains(lineId));
        if (_activeCashLineId case final activeId?
            when !validCashLineIds.contains(activeId)) {
          _activeCashLineId = null;
        }

        if (!_bankAccountOptions
            .any((option) => option.accountId == _selectedErpAccountId)) {
          _selectedErpAccountId = null;
        }
        _isBusy = false;
      });

      final stillMissing = refreshed.missingCanonicalPaymentMethodEmployeeIds
          .contains(employeeId);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            stillMissing
                ? 'La ficha todavía no tiene un método Transferencia o '
                    'Efectivo activo con cuenta contable.'
                : 'Método actualizado. Conservamos las decisiones que siguen '
                    'siendo válidas.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _error = error is PayrollReconciliationServiceException
            ? error.message
            : 'No pudimos refrescar la configuración. La revisión sigue '
                'abierta sin aplicar cambios.';
      });
      _logFailure('Falla al refrescar método', error);
    }
  }

  String _maskedSuffix(String value) {
    final compact = value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    if (compact.length <= 6) return compact;
    return compact.substring(compact.length - 6);
  }

  bool _isAfterDocumentClose(PayrollCivilDate? date) {
    final documentDate = _draft?.documentDate;
    return date != null &&
        documentDate != null &&
        date.compareTo(documentDate) > 0;
  }

  List<String> _warningCodesFor(PayrollStatementRow row) {
    return <String>[
      ...row.parseWarningCodes,
      if (!row.hasCompleteStructuredEvidence) 'incomplete_evidence',
      if (_isAfterDocumentClose(row.bookingDate)) 'out_of_statement_range',
    ];
  }

  List<String> _warningLabelsFor(PayrollStatementRow row) {
    return _warningCodesFor(row)
        .map(
          (code) => switch (code) {
            'out_of_statement_range' =>
              'La fecha queda después del cierre declarado por la cartola',
            'incomplete_evidence' =>
              'El OCR no recuperó toda la fecha, dirección o monto',
            _ => 'La fila trae una advertencia de lectura: $code',
          },
        )
        .toList(growable: false);
  }

  List<PayrollManualMatchOption> _manualOptionsFor(
    PayrollStatementRow row,
  ) {
    final draft = _draft;
    final amount = row.outgoingAmountClp;
    final date = row.bookingDate;
    if (draft == null || amount == null || date == null) return const [];
    const config = PayrollReconciliationConfig();
    final options = <PayrollManualMatchOption>[];
    for (final result in draft.reconciliation.lineResults) {
      final employee = result.employee;
      final line = result.voucherLine;
      if (employee == null ||
          line.paymentMethod != PayrollReconciliationPaymentMethod.transfer ||
          !line.isPending ||
          line.pendingAmountClp <= 0) {
        continue;
      }
      final daysAfterStart = line.periodStart.daysUntil(date);
      final daysAfterClose = line.periodEnd.daysUntil(date);
      final overpayment = amount - line.pendingAmountClp;
      if (daysAfterStart < 0 ||
          daysAfterClose > config.paymentWindowDays ||
          (overpayment > 0 &&
              overpayment > config.toleranceFor(line.pendingAmountClp))) {
        continue;
      }
      final isPartial = amount < line.pendingAmountClp;
      options.add(
        PayrollManualMatchOption(
          lineId: line.lineId,
          voucherId: line.voucherId,
          employeeId: line.employeeId,
          employeeName: employee.displayName,
          label: '${employee.displayName} · '
              '${_periodLabelFor(line.voucherId)} · '
              '${isPartial ? '${formatPayrollClp(amount)} de ' : ''}'
              '${formatPayrollClp(line.pendingAmountClp)}'
              '${isPartial ? ' · pago parcial' : ''}',
          expectedAmountClp: line.pendingAmountClp,
        ),
      );
    }
    options.sort((left, right) => left.label.compareTo(right.label));
    return List<PayrollManualMatchOption>.unmodifiable(options);
  }

  PayrollManualMatchOption? _selectedManualOption(
    PayrollStatementRow row, {
    String? fallbackLineId,
  }) {
    final selectedLineId =
        _manualLineBySourceRowId[row.sourceRowId] ?? fallbackLineId;
    if (selectedLineId == null) return null;
    for (final option in _manualOptionsFor(row)) {
      if (option.lineId == selectedLineId) return option;
    }
    return null;
  }

  List<PayrollDecisionRowData> get _transferRows {
    final draft = _draft;
    if (draft == null) return const [];
    final rows = <PayrollDecisionRowData>[];
    final reconciliation = draft.reconciliation;
    final manuallyLinkedLineIds = _manualLineBySourceRowId.values.toSet();
    final evaluatedCandidatesBySourceRowId =
        <String, List<PayrollReconciliationCandidate>>{};
    for (final result in reconciliation.lineResults) {
      for (final candidate in result.evaluatedCandidates) {
        evaluatedCandidatesBySourceRowId
            .putIfAbsent(
              candidate.statementRow.sourceRowId,
              () => <PayrollReconciliationCandidate>[],
            )
            .add(candidate);
      }
    }

    for (final statementRow in draft.parseResult.rows) {
      final priorDecisionId =
          draft.priorDecisionIdsBySourceRowId[statementRow.sourceRowId];
      if (priorDecisionId == null) continue;
      rows.add(
        PayrollDecisionRowData(
          id: statementRow.sourceRowId,
          kind: PayrollDecisionRowKind.alreadyResolvedMovement,
          title: 'Movimiento ya conciliado',
          subtitle: 'Existe una resolución final en otra importación',
          bankDescription: statementRow.description,
          beneficiaryObserved: statementRow.beneficiaryObserved,
          date: statementRow.bookingDate,
          bankAmountClp:
              statementRow.outgoingAmountClp ?? statementRow.creditAmountClp,
          explanations: const [
            'No puede volver a pagar una obligación. Reconoce la decisión '
                'anterior para conservar esta cartola completa.',
          ],
          sourceRowId: statementRow.sourceRowId,
          priorDecisionId: priorDecisionId,
          canConfirm: false,
        ),
      );
    }

    for (final result in reconciliation.lineResults) {
      final proposal = result.proposedMatch;
      final employeeName = result.employee?.displayName ??
          draft.vouchersById[result.voucherLine.voucherId]?.lines
              .firstWhere(
                (line) => line.id == result.voucherLine.lineId,
                orElse: () => const PayrollVoucherLine(
                  voucherId: '',
                  employeeId: '',
                  employeeName: 'Persona sin ficha',
                ),
              )
              .employeeName ??
          'Persona sin ficha';

      if (proposal != null) {
        final statementRow = proposal.statementRow;
        final warningCodes = _warningCodesFor(statementRow);
        final options = _manualOptionsFor(statementRow);
        final selected = _selectedManualOption(
          statementRow,
          fallbackLineId: proposal.voucherLine.lineId,
        );
        final selectedIsProposal =
            selected?.lineId == proposal.voucherLine.lineId;
        final expectedAmount = selected?.expectedAmountClp ??
            proposal.voucherLine.pendingAmountClp;
        final bankAmount = statementRow.outgoingAmountClp;
        final selectedIsPartial = selected != null &&
            bankAmount != null &&
            bankAmount < expectedAmount;
        rows.add(
          PayrollDecisionRowData(
            id: statementRow.sourceRowId,
            kind: PayrollDecisionRowKind.suggested,
            title: selected?.employeeName ?? employeeName,
            subtitle:
                '${selected == null ? 'Sin vínculo' : _periodLabelFor(selected.voucherId)}'
                ' · ${selectedIsProposal ? 'sugerido' : selectedIsPartial ? 'pago parcial elegido' : 'elegido manualmente'}',
            bankDescription: statementRow.description,
            beneficiaryObserved: statementRow.beneficiaryObserved,
            date: statementRow.bookingDate,
            bankAmountClp: bankAmount,
            expectedAmountClp: expectedAmount,
            varianceClp:
                bankAmount == null ? null : bankAmount - expectedAmount,
            confidence: selectedIsProposal ? proposal.confidence : null,
            confidenceScore: selectedIsProposal ? proposal.score : null,
            manualCertainty: !selectedIsProposal,
            explanations: (selectedIsProposal
                    ? proposal.reasons.map(payrollCandidateReasonLabel)
                    : [
                        selectedIsPartial
                            ? 'Pago parcial vinculado manualmente dentro de la '
                                'ventana de fecha. El saldo restante seguirá '
                                'pendiente.'
                            : 'Vínculo elegido manualmente dentro de la ventana '
                                'de fecha y monto.',
                      ])
                .followedBy(_warningLabelsFor(statementRow))
                .toList(growable: false),
            sourceRowId: statementRow.sourceRowId,
            voucherLineId: selected?.lineId,
            voucherId: selected?.voucherId,
            employeeId: selected?.employeeId,
            warningCodes: warningCodes,
            canConfirm: selected != null,
            manualMatchOptions: options,
            selectedManualLineId: selected?.lineId,
            isManualMatch: !selectedIsProposal,
            originalProposedLineId: proposal.voucherLine.lineId,
            originalProposedVoucherId: proposal.voucherLine.voucherId,
            originalProposedEmployeeId: proposal.voucherLine.employeeId,
          ),
        );
        continue;
      }

      if (result.status == PayrollLineMatchStatus.ineligible &&
          result.reasons.contains(PayrollLineMatchReason.paymentMethodIsCash)) {
        // Cash belongs to its own stage, not to the transfer review.
        continue;
      }

      if (manuallyLinkedLineIds.contains(result.voucherLine.lineId)) {
        // The unmatched bank row becomes the one and only decision surface for
        // this obligation as soon as the operator links it manually.
        continue;
      }

      rows.add(
        PayrollDecisionRowData(
          id: 'line:${result.voucherLine.lineId}',
          kind: PayrollDecisionRowKind.ineligibleLine,
          title: employeeName,
          subtitle: '${_periodLabelFor(result.voucherLine.voucherId)} · '
              '${switch (result.status) {
            PayrollLineMatchStatus.needsReview => 'Ambiguo',
            PayrollLineMatchStatus.ineligible => 'No elegible',
            _ => 'Sin movimiento',
          }}',
          expectedAmountClp: result.voucherLine.pendingAmountClp,
          explanations: result.reasons
              .map(payrollLineReasonLabel)
              .toList(growable: false),
          voucherLineId: result.voucherLine.lineId,
          voucherId: result.voucherLine.voucherId,
          employeeId: result.voucherLine.employeeId,
        ),
      );
    }

    for (final row in reconciliation.unmatchedOutgoingRows) {
      if (!row.hasCompleteStructuredEvidence) continue;
      final warningCodes = _warningCodesFor(row);
      final options = _manualOptionsFor(row);
      final selected = _selectedManualOption(row);
      final bankAmount = row.outgoingAmountClp;
      final selectedIsPartial = selected != null &&
          bankAmount != null &&
          bankAmount < selected.expectedAmountClp;
      final evaluatedCandidates =
          evaluatedCandidatesBySourceRowId[row.sourceRowId] ??
              const <PayrollReconciliationCandidate>[];
      final hasObservedBeneficiary =
          row.beneficiaryObserved?.trim().isNotEmpty ?? false;
      final isOutsideEveryPayrollWindow = evaluatedCandidates.isNotEmpty &&
          evaluatedCandidates.every(
            (candidate) => candidate.reasons
                .contains(PayrollCandidateReason.dateOutsideWindow),
          );
      // Automatic classification consumes only the matcher's POSITIVE proof
      // that the movement names nobody in payroll. A worker-named row can
      // never be absorbed by amount mismatch alone: with its window still
      // plausible (or unprovable) it stays a manual question, exactly like
      // the Vicente CLP 22.000 case. Rows whose OCR read carries warnings are
      // excluded from the automatic path because their text is not a safe
      // basis for a name-absence proof.
      final isForeignToPayroll =
          reconciliation.foreignOutgoingSourceRowIds.contains(row.sourceRowId);
      final automaticDisposition = selected != null || warningCodes.isNotEmpty
          ? null
          : isForeignToPayroll
              ? PayrollRowDisposition.notPayroll
              : isOutsideEveryPayrollWindow
                  ? PayrollRowDisposition.ignore
                  : null;
      final automaticAuditReason = switch (automaticDisposition) {
        PayrollRowDisposition.notPayroll => hasObservedBeneficiary
            ? 'Clasificación automática: el beneficiario del cargo no '
                'coincide con ninguna persona ni alias de la nómina abierta.'
            : 'Clasificación automática: el cargo no nombra a una persona ni '
                'a un alias de la nómina abierta.',
        PayrollRowDisposition.ignore =>
          'Clasificación automática: el movimiento queda fuera de todas las '
              'ventanas de pago abiertas.',
        _ => null,
      };
      rows.add(
        PayrollDecisionRowData(
          id: row.sourceRowId,
          kind: PayrollDecisionRowKind.unmatchedMovement,
          title: selected?.employeeName ?? 'Movimiento sin persona asignada',
          subtitle: selected == null
              ? 'La cartola no lo vincula con nadie de la nómina'
              : '${_periodLabelFor(selected.voucherId)} · '
                  '${selectedIsPartial ? 'pago parcial elegido' : 'elegido manualmente'}',
          bankDescription: row.description,
          beneficiaryObserved: row.beneficiaryObserved,
          date: row.bookingDate,
          bankAmountClp: bankAmount,
          expectedAmountClp: selected?.expectedAmountClp,
          varianceClp: selected == null || bankAmount == null
              ? null
              : bankAmount - selected.expectedAmountClp,
          explanations: [
            if (selected == null)
              'No se vincula automáticamente. Decide si corresponde a nómina.'
            else if (selectedIsPartial)
              'Pago parcial vinculado manualmente dentro de la ventana de '
                  'fecha. El saldo restante seguirá pendiente.'
            else
              'Vínculo elegido manualmente dentro de la ventana de fecha y '
                  'monto.',
            ..._warningLabelsFor(row),
          ],
          sourceRowId: row.sourceRowId,
          voucherLineId: selected?.lineId,
          voucherId: selected?.voucherId,
          employeeId: selected?.employeeId,
          warningCodes: warningCodes,
          canConfirm: selected != null,
          manualMatchOptions: options,
          selectedManualLineId: selected?.lineId,
          isManualMatch: selected != null,
          manualCertainty: selected != null,
          automaticDisposition: automaticDisposition,
          automaticAuditReason: automaticAuditReason,
        ),
      );
    }

    for (final row in draft.parseResult.rows) {
      if (row.hasCompleteStructuredEvidence ||
          draft.priorDecisionIdsBySourceRowId.containsKey(row.sourceRowId)) {
        continue;
      }
      final warningCodes = _warningCodesFor(row);
      rows.add(
        PayrollDecisionRowData(
          id: row.sourceRowId,
          kind: PayrollDecisionRowKind.incompleteEvidence,
          title: 'Fila OCR incompleta',
          subtitle: 'Se conserva como evidencia; no puede crear un pago',
          bankDescription: row.description,
          beneficiaryObserved: row.beneficiaryObserved,
          date: row.bookingDate,
          bankAmountClp: row.debitAmountClp ?? row.creditAmountClp,
          explanations: _warningLabelsFor(row),
          sourceRowId: row.sourceRowId,
          warningCodes: warningCodes,
          canConfirm: false,
        ),
      );
    }

    return rows;
  }

  /// Voucher lines whose person is paid in cash.
  List<PayrollReconciliationLineResult> get _cashLines {
    final draft = _draft;
    if (draft == null) return const [];
    return draft.reconciliation.lineResults
        .where(
          (result) => result.reasons
              .contains(PayrollLineMatchReason.paymentMethodIsCash),
        )
        .toList(growable: false);
  }

  PayrollRowDisposition _dispositionFor(PayrollDecisionRowData row) =>
      _dispositions[row.id] ??
      row.automaticDisposition ??
      PayrollRowDisposition.pending;

  PayrollVarianceDisposition _varianceFor(PayrollDecisionRowData row) =>
      _varianceDispositions[row.id] ?? PayrollVarianceDisposition.none;

  String _reviewReasonFor(PayrollDecisionRowData row) =>
      _reviewReasons[row.id]?.trim() ?? '';

  void _setRowDisposition(
    PayrollDecisionRowData row,
    PayrollRowDisposition value,
  ) {
    // Se mide ANTES de escribir la disposición: `_suggestionIsBatchSafe` exige
    // que la fila siga pendiente, así que preguntarlo después siempre daba
    // `false` y un calce de un solo toque quedaba abierto como pregunta en vez
    // de pasar a «Ya respondidos».
    final wasBatchSafe = _suggestionIsBatchSafe(row);
    setState(() {
      _dispositions[row.id] = value;
      // Answering does not make the question vanish: the row stays in place so
      // the operator can finish the variance/reason/alias it may still need,
      // and can see what was just decided. It leaves only on "next question".
      if (row.requiresDisposition && !wasBatchSafe) {
        _answeredInPlaceRowIds.add(row.id);
      }
      if (value == PayrollRowDisposition.confirm && row.isPartialPayment) {
        // A debit below the obligation has only one truthful money outcome:
        // apply the observed debit and keep the remainder pending. The operator
        // still has to explain the manual link before the batch can advance.
        _varianceDispositions[row.id] = PayrollVarianceDisposition.partial;
      } else if (value != PayrollRowDisposition.confirm || !row.hasVariance) {
        _varianceDispositions.remove(row.id);
      }
    });
  }

  String? _methodIdForLine(
    String? voucherLineId, {
    String? fallbackEmployeeId,
  }) =>
      _methodForLine(
        voucherLineId,
        fallbackEmployeeId: fallbackEmployeeId,
      )?['id']
          ?.toString();

  String? _methodAccountIdForLine(
    String? voucherLineId, {
    String? fallbackEmployeeId,
  }) =>
      _methodForLine(
        voucherLineId,
        fallbackEmployeeId: fallbackEmployeeId,
      )?['account_id']
          ?.toString();

  /// `07 – 13 jul · a pagar $179.375`, la segunda línea de la persona en la
  /// tabla de coincidencias (5j paso 3).
  ///
  /// Nulo cuando la fila no apunta a ninguna semana: un cargo ajeno no tiene
  /// obligación contra la cual contrastar, y rellenarlo con un guion sólo
  /// agrega ruido a la fila que menos lo necesita.
  String? _rowPersonDetail(PayrollDecisionRowData row) {
    final voucherId = row.voucherId;
    if (voucherId == null || voucherId.isEmpty) return null;
    final period = _periodLabelFor(voucherId);
    final expected = row.expectedAmountClp;
    if (expected == null) return period;
    return '$period · a pagar ${formatPayrollClp(expected)}';
  }

  String _periodLabelFor(String voucherId) {
    final voucher = _draft?.vouchersById[voucherId];
    if (voucher == null) return 'Semana sin identificar';
    return voucher.periodLabel?.trim().isNotEmpty == true
        ? voucher.periodLabel!.trim()
        : formatPayrollWeekRange(voucher.periodStart, voucher.periodEnd);
  }

  List<EmployeeAdvance> _advancesFor(
    PayrollReconciliationVoucherLine line,
  ) {
    final draft = _draft;
    if (draft == null) return const [];
    final periodEnd = DateTime(
      line.periodEnd.year,
      line.periodEnd.month,
      line.periodEnd.day,
      23,
      59,
      59,
    );
    return draft.openAdvances
        .where((advance) =>
            advance.employeeId == line.employeeId &&
            advance.availableAmount > 0.01 &&
            !advance.paidCivilDate.isAfter(periodEnd))
        .toList(growable: false)
      ..sort((left, right) {
        final byDate = left.paidCivilDate.compareTo(right.paidCivilDate);
        return byDate != 0 ? byDate : left.id.compareTo(right.id);
      });
  }

  List<(EmployeeAdvance, double)> _cashAdvanceAllocations(
    PayrollReconciliationVoucherLine line,
    _CashAnswer answer,
  ) {
    final allocations = <(EmployeeAdvance, double)>[];
    var remaining = line.pendingAmountClp.toDouble();
    for (final advance in _advancesFor(line)) {
      if (!answer.selectedAdvanceIds.contains(advance.id)) continue;
      if (remaining <= 0.01) break;
      final amount = advance.availableAmount > remaining
          ? remaining
          : advance.availableAmount;
      allocations.add((advance, amount));
      remaining -= amount;
    }
    return allocations;
  }

  double _cashAdvanceAmount(
    PayrollReconciliationVoucherLine line,
    _CashAnswer answer,
  ) =>
      _cashAdvanceAllocations(line, answer).fold<double>(
        0,
        (sum, allocation) => sum + allocation.$2,
      );

  double _cashResolvedAmount(
    PayrollReconciliationVoucherLine line,
    _CashAnswer answer,
  ) =>
      _cashAdvanceAmount(line, answer) + (answer.amount ?? 0);

  /// Everything that must be answered before the batch may be applied.
  List<String> get _blockers {
    final draft = _draft;
    if (draft == null) return const ['Todavía no hay una cartola preparada.'];
    final blockers = <String>[];
    if (_versionedBackendMissing) {
      blockers.add(
        'El servidor aún no tiene la actualización de nóminas: esta revisión '
        'es de solo lectura y aplicar quedará disponible cuando se instale.',
      );
    }
    final selectedAccountId = _selectedErpAccountId;

    if (_bankAccountOptions.isEmpty) {
      blockers.add(
        'No hay un método de transferencia activo vinculado a una cuenta '
        'contable del ERP.',
      );
    } else if (selectedAccountId == null) {
      blockers.add('Falta elegir la cuenta ERP correspondiente a la cartola.');
    }

    final pendingRows = _transferRows
        .where((row) =>
            row.requiresDisposition &&
            _dispositionFor(row) == PayrollRowDisposition.pending)
        .length;
    if (pendingRows > 0) {
      blockers.add(
        '$pendingRows ${pendingRows == 1 ? 'movimiento u obligación sigue' : 'movimientos o sueldos siguen'} sin disposición.',
      );
    }

    final undisposedVariance = _transferRows
        .where((row) =>
            row.hasVariance &&
            _dispositionFor(row) == PayrollRowDisposition.confirm &&
            _varianceFor(row) == PayrollVarianceDisposition.none)
        .length;
    if (undisposedVariance > 0) {
      blockers.add(
        '$undisposedVariance ${undisposedVariance == 1 ? 'diferencia' : 'diferencias'} de monto sin decidir qué pasa con ella.',
      );
    }

    final missingReviewReason = _transferRows
        .where(
          (row) =>
              row.needsReviewReason &&
              _dispositionFor(row) == PayrollRowDisposition.confirm &&
              (!row.hasVariance ||
                  _varianceFor(row) != PayrollVarianceDisposition.none) &&
              _reviewReasonFor(row).isEmpty,
        )
        .length;
    if (missingReviewReason > 0) {
      blockers.add(
        '$missingReviewReason '
        '${missingReviewReason == 1 ? 'confirmación necesita' : 'confirmaciones necesitan'} '
        'una razón de auditoría.',
      );
    }

    final incompatibleTransferMethods = _transferRows.where((row) {
      if (_dispositionFor(row) != PayrollRowDisposition.confirm) return false;
      final method = _methodForLine(
        row.voucherLineId,
        fallbackEmployeeId: row.employeeId,
      );
      final methodAccountId = method?['account_id']?.toString();
      return method == null ||
          method['is_active'] == false ||
          !_isCanonicalTransferMethod(method) ||
          selectedAccountId == null ||
          methodAccountId != selectedAccountId;
    }).length;
    if (incompatibleTransferMethods > 0) {
      blockers.add(
        '$incompatibleTransferMethods '
        '${incompatibleTransferMethods == 1 ? 'pago no usa' : 'pagos no usan'} '
        'el método de transferencia y la cuenta elegida.',
      );
    }

    final confirmedLineIds = _transferRows
        .where(
          (row) => _dispositionFor(row) == PayrollRowDisposition.confirm,
        )
        .map((row) => row.voucherLineId)
        .whereType<String>()
        .toList(growable: false);
    if (confirmedLineIds.toSet().length != confirmedLineIds.length) {
      blockers.add(
        'Dos movimientos están vinculados a la misma obligación. Elige una '
        'sola transferencia para esa persona y semana.',
      );
    }

    final unansweredCash = _cashLines
        .where((line) =>
            !(_cashAnswers[line.voucherLine.lineId]?.isAnswered ?? false))
        .length;
    if (unansweredCash > 0) {
      blockers.add(
        '$unansweredCash ${unansweredCash == 1 ? 'persona en efectivo' : 'personas en efectivo'} sin elegir cómo se resolvió.',
      );
    }

    final invalidCashAmounts = _cashLines.where((line) {
      final answer = _cashAnswers[line.voucherLine.lineId];
      if (answer?.disposition != _CashDisposition.cashPayment) {
        return false;
      }
      final amount = _cashResolvedAmount(line.voucherLine, answer!);
      return amount <= 0 ||
          amount > line.voucherLine.pendingAmountClp.toDouble();
    }).length;
    if (invalidCashAmounts > 0) {
      blockers.add(
        '$invalidCashAmounts '
        '${invalidCashAmounts == 1 ? 'monto en efectivo es inválido' : 'montos en efectivo son inválidos'}.',
      );
    }

    final invalidCashMethods = _cashLines.where((line) {
      final answer = _cashAnswers[line.voucherLine.lineId];
      if (answer?.disposition != _CashDisposition.cashPayment ||
          (answer?.amount ?? 0) <= 0) {
        return false;
      }
      final method = _methodForLine(
        line.voucherLine.lineId,
        fallbackEmployeeId: line.voucherLine.employeeId,
      );
      final accountId = method?['account_id']?.toString().trim() ?? '';
      return method == null ||
          method['is_active'] == false ||
          !_isCanonicalCashMethod(method) ||
          accountId.isEmpty;
    }).length;
    if (invalidCashMethods > 0) {
      blockers.add(
        '$invalidCashMethods '
        '${invalidCashMethods == 1 ? 'pago en efectivo no tiene' : 'pagos en efectivo no tienen'} '
        'método y cuenta contable canónicos.',
      );
    }

    final invalidCashDates = _cashLines.where((line) {
      final answer = _cashAnswers[line.voucherLine.lineId];
      if (answer?.disposition != _CashDisposition.cashPayment ||
          (answer?.amount ?? 0) <= 0) {
        return false;
      }
      final paidAt = DateTime(
        answer!.date.year,
        answer.date.month,
        answer.date.day,
      );
      final periodStart = DateTime(
        line.voucherLine.periodStart.year,
        line.voucherLine.periodStart.month,
        line.voucherLine.periodStart.day,
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return paidAt.isBefore(periodStart) || paidAt.isAfter(today);
    }).length;
    if (invalidCashDates > 0) {
      blockers.add(
        '$invalidCashDates '
        '${invalidCashDates == 1 ? 'pago en efectivo tiene' : 'pagos en efectivo tienen'} '
        'una fecha anterior al inicio de la semana o posterior a hoy.',
      );
    }

    final invalidAdvanceSelections = _cashLines.where((line) {
      final answer = _cashAnswers[line.voucherLine.lineId];
      if (answer?.disposition != _CashDisposition.cashPayment) {
        return false;
      }
      final availableIds =
          _advancesFor(line.voucherLine).map((advance) => advance.id).toSet();
      return !availableIds.containsAll(answer!.selectedAdvanceIds);
    }).length;
    if (invalidAdvanceSelections > 0) {
      blockers.add(
        '$invalidAdvanceSelections '
        '${invalidAdvanceSelections == 1 ? 'selección de anticipos ya no está' : 'selecciones de anticipos ya no están'} '
        'disponible para esa semana.',
      );
    }

    if (draft.missingCanonicalPaymentMethodEmployeeIds.isNotEmpty) {
      final count = draft.missingCanonicalPaymentMethodEmployeeIds.length;
      blockers.add(
        '$count ${count == 1 ? 'persona no tiene' : 'personas no tienen'} método de pago canónico configurado.',
      );
    }

    return blockers;
  }

  List<PayrollStatementReviewDecision> _buildDecisions() {
    final decisions = <PayrollStatementReviewDecision>[];
    final decidedLineIds = <String>{};

    for (final row in _transferRows) {
      final disposition = _dispositionFor(row);
      final kind = disposition.decisionKind;
      if (kind == null) continue;
      final usesAutomaticDefault =
          row.isAutomaticallyClassified && !_dispositions.containsKey(row.id);
      if (disposition == PayrollRowDisposition.confirm) {
        decisions.add(
          PayrollStatementReviewDecision(
            kind: kind,
            sourceRowId: row.sourceRowId,
            voucherLineId: row.voucherLineId,
            voucherId: row.voucherId,
            employeeId: row.employeeId,
            amountClp: switch ((row.bankAmountClp, row.expectedAmountClp)) {
              (final bank?, final expected?) =>
                bank < expected ? bank : expected,
              _ => null,
            },
            paymentDate: row.date,
            paymentMethodId: _methodIdForLine(
              row.voucherLineId,
              fallbackEmployeeId: row.employeeId,
            ),
            paymentAccountId: _selectedErpAccountId,
            varianceDisposition: _varianceFor(row),
            manualConfirmation: true,
            note: _reviewReasonFor(row).isEmpty
                ? 'El operador confirmó la propuesta única por persona, '
                    'fecha y monto.'
                : _reviewReasonFor(row),
          ),
        );
        if (row.voucherLineId case final lineId?) decidedLineIds.add(lineId);
        final originalLineId = row.originalProposedLineId;
        if (originalLineId != null &&
            originalLineId != row.voucherLineId &&
            decidedLineIds.add(originalLineId)) {
          decisions.add(
            PayrollStatementReviewDecision(
              kind: PayrollReviewDecisionKind.notPaid,
              voucherLineId: originalLineId,
              voucherId: row.originalProposedVoucherId,
              employeeId: row.originalProposedEmployeeId,
              manualConfirmation: true,
              note: 'El operador reasignó el movimiento sugerido a otra '
                  'obligación; la sugerencia original permanece sin pagar.',
            ),
          );
        }
        continue;
      }

      if (disposition != PayrollRowDisposition.notPaid &&
          row.sourceRowId != null) {
        decisions.add(
          PayrollStatementReviewDecision(
            kind: kind,
            sourceRowId: row.sourceRowId,
            priorDecisionId:
                disposition == PayrollRowDisposition.alreadyResolved
                    ? row.priorDecisionId
                    : null,
            manualConfirmation:
                usesAutomaticDefault ? false : row.warningCodes.isNotEmpty,
            note: usesAutomaticDefault
                ? row.automaticAuditReason
                : disposition.auditReason,
          ),
        );
      }

      final lineId = row.originalProposedLineId ??
          (row.kind == PayrollDecisionRowKind.ineligibleLine
              ? row.voucherLineId
              : null);
      if (lineId != null && decidedLineIds.add(lineId)) {
        decisions.add(
          PayrollStatementReviewDecision(
            kind: PayrollReviewDecisionKind.notPaid,
            voucherLineId: lineId,
            voucherId: row.voucherId,
            employeeId: row.employeeId,
            manualConfirmation: true,
            note: disposition == PayrollRowDisposition.notPaid
                ? 'El operador confirmó que esta obligación todavía no fue '
                    'pagada.'
                : 'El movimiento propuesto fue descartado; la obligación '
                    'permanece sin pagar.',
          ),
        );
      }
    }

    final reviewedSourceRows = decisions
        .map((decision) => decision.sourceRowId)
        .whereType<String>()
        .toSet();
    for (final row
        in _draft?.parseResult.rows ?? const <PayrollStatementRow>[]) {
      if (reviewedSourceRows.contains(row.sourceRowId)) continue;
      decisions.add(
        PayrollStatementReviewDecision(
          kind: PayrollReviewDecisionKind.ignore,
          sourceRowId: row.sourceRowId,
          note: row.direction == PayrollStatementMovementDirection.incoming
              ? 'Movimiento entrante clasificado como informativo; no puede '
                  'ser un pago de nómina saliente.'
              : 'Fila sin salida bancaria utilizable, conservada como '
                  'evidencia fuera de nómina.',
        ),
      );
    }

    for (final line in _cashLines) {
      final answer = _cashAnswers[line.voucherLine.lineId];
      if (answer == null || !answer.isAnswered) continue;
      if (answer.disposition == _CashDisposition.notPaid) {
        decisions.add(
          PayrollStatementReviewDecision(
            kind: PayrollReviewDecisionKind.notPaid,
            voucherLineId: line.voucherLine.lineId,
            voucherId: line.voucherLine.voucherId,
            employeeId: line.voucherLine.employeeId,
            manualConfirmation: true,
            note: 'El operador confirmó que este pago en efectivo aún no se '
                'realizó.',
          ),
        );
        continue;
      }
      for (final allocation
          in _cashAdvanceAllocations(line.voucherLine, answer)) {
        decisions.add(
          PayrollStatementReviewDecision(
            kind: PayrollReviewDecisionKind.advanceAllocation,
            voucherLineId: line.voucherLine.lineId,
            voucherId: line.voucherLine.voucherId,
            employeeId: line.voucherLine.employeeId,
            amountClp: allocation.$2.round(),
            advanceId: allocation.$1.id,
          ),
        );
      }
      final cashAmount = answer.amount ?? 0;
      if (cashAmount > 0) {
        decisions.add(
          PayrollStatementReviewDecision(
            kind: PayrollReviewDecisionKind.cashPayment,
            voucherLineId: line.voucherLine.lineId,
            voucherId: line.voucherLine.voucherId,
            employeeId: line.voucherLine.employeeId,
            amountClp: cashAmount.round(),
            paymentMethodId: _methodIdForLine(
              line.voucherLine.lineId,
              fallbackEmployeeId: line.voucherLine.employeeId,
            ),
            paymentAccountId: _methodAccountIdForLine(
              line.voucherLine.lineId,
              fallbackEmployeeId: line.voucherLine.employeeId,
            ),
            paymentDate: PayrollCivilDate(
              answer.date.year,
              answer.date.month,
              answer.date.day,
            ),
            manualConfirmation: true,
            note: 'El operador confirmó manualmente la entrega en efectivo.',
          ),
        );
      }
    }

    return decisions;
  }

  // ---------------------------------------------------------------------------
  // Stage 4 — commit
  // ---------------------------------------------------------------------------

  List<_AliasLearningIntent> _selectedAliasIntents() {
    final draft = _draft;
    if (draft == null || _actions().learnBeneficiaryAlias == null) {
      return const [];
    }
    final intents = <_AliasLearningIntent>[];
    for (final row in draft.parseResult.rows) {
      if (!_learnAliasSourceRowIds.contains(row.sourceRowId)) continue;
      final alias = row.beneficiaryObserved?.trim();
      final selected = _selectedManualOption(row);
      if (alias == null ||
          alias.length < 2 ||
          selected == null ||
          _dispositions[row.sourceRowId] != PayrollRowDisposition.confirm) {
        continue;
      }
      intents.add(
        _AliasLearningIntent(
          sourceRowId: row.sourceRowId,
          employeeId: selected.employeeId,
          employeeName: selected.employeeName,
          alias: alias,
        ),
      );
    }
    return List<_AliasLearningIntent>.unmodifiable(intents);
  }

  Future<void> _persistPendingAliases() async {
    final writer = _actions().learnBeneficiaryAlias;
    final pending = _pendingAliasIntents;
    if (writer == null || pending.isEmpty || _isLearningAliases) return;
    setState(() {
      _isLearningAliases = true;
      _aliasLearningError = null;
    });

    final failed = <_AliasLearningIntent>[];
    var learned = 0;
    for (final intent in pending) {
      try {
        await writer(
          employeeId: intent.employeeId,
          alias: intent.alias,
        );
        learned += 1;
      } catch (error) {
        failed.add(intent);
        _logFailure('No se guardó alias de beneficiario', error);
      }
    }
    if (!mounted) return;
    setState(() {
      _isLearningAliases = false;
      _learnedAliasCount += learned;
      _pendingAliasIntents = List<_AliasLearningIntent>.unmodifiable(failed);
      _aliasLearningError = failed.isEmpty
          ? null
          : 'Los pagos sí quedaron registrados, pero '
              '${failed.length == 1 ? 'un nombre bancario no se guardó' : '${failed.length} nombres bancarios no se guardaron'}. '
              'Puedes reintentar sólo este aprendizaje.';
    });
  }

  Future<void> _apply() async {
    final draft = _draft;
    if (draft == null || _isBusy) return;
    if (!_canApply) return;
    final decisions = _buildDecisions();
    final draftVouchersToCommit = _draftVouchersToCommit(decisions);
    final recognizedAmount = decisions
        .where(
          (decision) =>
              decision.kind == PayrollReviewDecisionKind.bankPayment ||
              decision.kind == PayrollReviewDecisionKind.cashPayment ||
              decision.kind == PayrollReviewDecisionKind.advanceAllocation,
        )
        .fold<int>(0, (sum, decision) => sum + (decision.amountClp ?? 0));

    setState(() {
      _isBusy = true;
      _error = null;
    });

    try {
      final actions = _actions();
      final erpAccountId = _selectedErpAccountId;
      if (erpAccountId == null) {
        throw const PayrollReconciliationServiceException(
          'Selecciona la cuenta ERP correspondiente a la cartola.',
        );
      }
      // The import is created once and reused, so a retry after a failure does
      // not register the same statement twice.
      final receipt = _importReceipt ??
          await actions.createImport(
            draft,
            erpAccountId: erpAccountId,
          );
      _importReceipt = receipt;

      final operationKey =
          _applyOperationKey ??= '${receipt.operationKey}:apply';

      final applied = await actions.apply(
        draft: draft,
        importReceipt: receipt,
        decisions: decisions,
        authorizedDraftVoucherIds: draftVouchersToCommit
            .map((voucher) => voucher.id)
            .whereType<String>()
            .toSet(),
        operationKey: operationKey,
      );
      if (!mounted) return;
      final aliasIntents = _selectedAliasIntents();
      setState(() {
        _isBusy = false;
        _appliedAmountClp = recognizedAmount;
        _appliedReceipt = applied;
        _appliedDecisions =
            List<PayrollStatementReviewDecision>.unmodifiable(decisions);
        // A replay is the server confirming the same batch already landed. It
        // is a success, not a duplicate attempt.
        final committedCount = applied.committedVoucherIds.length;
        _appliedMessage = applied.wasReplay
            ? 'Esta conciliación ya estaba registrada. No se duplicó nada.'
            : committedCount == 0
                ? 'Conciliación registrada.'
                : '$committedCount '
                    '${committedCount == 1 ? 'semana confirmada' : 'semanas confirmadas'} '
                    'y conciliación registrada.';
        _pendingAliasIntents = aliasIntents;
        _aliasLearningError = null;
        _errorRecoveryAction = PayrollReconciliationRecoveryAction.none;
        _canRetrySameOperation = false;
      });
      await _persistPendingAliases();
    } catch (error) {
      if (!mounted) return;
      final typed =
          error is PayrollReconciliationServiceException ? error : null;
      // An ambiguous acknowledgement keeps the exact operation keys so the
      // server can return the idempotent receipt. Deterministic failures never
      // advertise that retry path: the operator must reload, repair
      // configuration or review permissions first.
      setState(() {
        _isBusy = false;
        _error = typed != null
            ? typed.message
            : 'No pudimos aplicar la conciliación. Reintenta: se reutilizará '
                'el mismo intento. El detalle técnico quedó en el registro '
                'de la aplicación.';
        _errorRecoveryAction =
            typed?.recoveryAction ?? PayrollReconciliationRecoveryAction.retry;
        _canRetrySameOperation = typed?.canRetrySameOperation ?? true;
      });
      _logFailure('Falla al aplicar', error);
    }
  }

  String? get _errorActionLabel => switch (_errorRecoveryAction) {
        PayrollReconciliationRecoveryAction.selectAnotherFile =>
          'Elegir otro archivo',
        PayrollReconciliationRecoveryAction.retry when _canRetrySameOperation =>
          'Reintentar',
        PayrollReconciliationRecoveryAction.reload => 'Salir y recargar',
        PayrollReconciliationRecoveryAction.fixPaymentConfiguration =>
          'Salir y corregir',
        PayrollReconciliationRecoveryAction.reviewPermissions =>
          'Volver a Nóminas',
        _ => null,
      };

  void _runErrorRecovery() {
    if (_isBusy) return;
    if (_errorRecoveryAction ==
        PayrollReconciliationRecoveryAction.selectAnotherFile) {
      _choose(widget.pickFile ?? _defaultFilePicker);
      return;
    }
    if (_errorRecoveryAction == PayrollReconciliationRecoveryAction.retry &&
        _canRetrySameOperation) {
      _apply();
      return;
    }
    _closeImmediately();
  }

  void _closeImmediately() {
    ReturnNavigation.close(context, fallbackRoute: widget.fallbackRoute);
  }

  Future<void> _requestClose() async {
    if (_isBusy) return;
    if (!_hasUnappliedDraft) {
      _closeImmediately();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Salir de la conciliación?'),
        content: Text(
          _importReceipt == null
              ? 'Se perderán las decisiones que aún no has aplicado.'
              : 'La evidencia ya fue importada, pero la conciliación no tiene '
                  'confirmación final. Si el último intento falló, recarga las '
                  'nóminas antes de volver a intentarlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Seguir revisando'),
          ),
          // accent-fill: dialog-action (resolver-owned M3 dialog grammar)
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Salir sin guardar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) _closeImmediately();
  }

  // ---------------------------------------------------------------------------
  // Composition
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnappliedDraft && !_isBusy,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) await _requestClose();
      },
      child: PayrollReconciliationSurface(
        title: _workflowTitle,
        metadata: _workflowMetadata,
        steps: _surfaceSteps,
        closeLabel: _draft == null || _appliedMessage != null
            ? 'Volver a nómina'
            : 'Salir sin guardar',
        // Once the batch applied, the only meaningful close returns to payroll.
        closeEnabled: !_isBusy,
        busy: _isBusy,
        onClose: _requestClose,
        body: _buildStage(),
        footer: _buildBar(),
      ),
    );
  }

  String get _workflowTitle {
    if (_appliedMessage != null) return 'Conciliación registrada';
    return switch (_stage) {
      PayrollReconciliationStage.file => 'Subir cartola',
      PayrollReconciliationStage.extract => 'Extraer movimientos',
      PayrollReconciliationStage.review => 'Revisar coincidencias',
      PayrollReconciliationStage.apply => 'Aplicar conciliación',
    };
  }

  String? get _workflowMetadata {
    final draft = _draft;
    if (draft == null) {
      return 'PDF, imagen o cámara · OCR local';
    }
    final movementCount = draft.parseResult.rows.length;
    final pageCount = draft.extraction.pages.length;
    return '${draft.filename} · '
        '$pageCount ${pageCount == 1 ? 'página' : 'páginas'} · '
        '$movementCount ${movementCount == 1 ? 'movimiento' : 'movimientos'}';
  }

  List<ReconStep> get _surfaceSteps {
    final currentIndex = PayrollReconciliationStage.values.indexOf(_stage);
    final hasDraft = _draft != null;
    final enabled = !_isBusy && _appliedMessage == null;
    final completed = <bool>[
      hasDraft,
      hasDraft,
      _transferStageIsComplete,
      _appliedMessage != null,
    ];
    const compactNames = <String>[
      'Subir',
      'Extraer',
      'Revisar',
      'Aplicar',
    ];
    // The transfer counter reports the human workload: suggestions and real
    // questions. Automatically classified and informational rows are
    // evidence, not pending work, and must not inflate the denominator.
    final humanReviewRows = _transferRows
        .where((row) => row.requiresDisposition)
        .toList(growable: false);
    final movementCount = _draft?.parseResult.rows.length ?? 0;
    final metadata = <String>[
      hasDraft ? 'lista' : '',
      hasDraft
          ? '$movementCount ${movementCount == 1 ? 'movimiento' : 'movimientos'}'
          : '',
      humanReviewRows.isEmpty
          ? ''
          : '${_answeredCount(humanReviewRows)}/${humanReviewRows.length}',
      _cashLines.isEmpty
          ? ''
          : '${_cashLines.where((line) => _cashAnswers[line.voucherLine.lineId]?.isAnswered ?? false).length}/${_cashLines.length} efectivo',
    ];

    return <ReconStep>[
      for (var index = 0;
          index < PayrollReconciliationStage.values.length;
          index++)
        ReconStep(
          name: PayrollReconciliationStage.values[index].label,
          compactName: compactNames[index],
          meta: metadata[index],
          state: index == currentIndex
              ? ReconStepState.current
              : completed[index]
                  ? ReconStepState.done
                  : ReconStepState.next,
          onTap: !enabled ||
                  !_canEnterStage(PayrollReconciliationStage.values[index])
              ? null
              : () => setState(
                    () => _stage = PayrollReconciliationStage.values[index],
                  ),
        ),
    ];
  }

  bool _canEnterStage(PayrollReconciliationStage target) {
    return switch (target) {
      PayrollReconciliationStage.file => true,
      PayrollReconciliationStage.extract => _draft != null,
      PayrollReconciliationStage.review => _draft != null,
      PayrollReconciliationStage.apply => _transferStageIsComplete,
    };
  }

  bool get _applyRequiresExternalRecovery =>
      _applyOperationKey != null && _error != null && !_canRetrySameOperation;

  bool get _canApply =>
      _transferStageIsComplete &&
      _cashStageIsComplete &&
      _blockers.isEmpty &&
      !_applyRequiresExternalRecovery;

  void _enterStage(PayrollReconciliationStage target) {
    if (_isBusy || _appliedMessage != null || !_canEnterStage(target)) return;
    setState(() => _stage = target);
  }

  String? _gateNoteFor(PayrollReconciliationStage target) {
    if (_canEnterStage(target)) return null;
    if (_draft == null) {
      return 'Carga y lee una cartola para comenzar la revisión.';
    }
    final blockers = _blockers;
    if (blockers.isEmpty) {
      return switch (target) {
        PayrollReconciliationStage.apply =>
          'Completa la revisión de coincidencias para aplicar.',
        _ => null,
      };
    }
    final remaining = blockers.length - 1;
    return remaining <= 0
        ? blockers.first
        : '${blockers.first} (+$remaining más)';
  }

  bool get _transferStageIsComplete {
    if (_draft == null ||
        _bankAccountOptions.isEmpty ||
        _selectedErpAccountId == null ||
        _draft!.missingCanonicalPaymentMethodEmployeeIds.isNotEmpty) {
      return false;
    }
    final confirmedLineIds = <String>[];
    for (final row in _transferRows) {
      final disposition = _dispositionFor(row);
      if (row.requiresDisposition &&
          disposition == PayrollRowDisposition.pending) {
        return false;
      }
      if (disposition != PayrollRowDisposition.confirm) continue;
      if (row.hasVariance &&
          _varianceFor(row) == PayrollVarianceDisposition.none) {
        return false;
      }
      if (row.needsReviewReason && _reviewReasonFor(row).isEmpty) {
        return false;
      }
      final method = _methodForLine(
        row.voucherLineId,
        fallbackEmployeeId: row.employeeId,
      );
      if (method == null ||
          method['is_active'] == false ||
          !_isCanonicalTransferMethod(method) ||
          method['account_id']?.toString() != _selectedErpAccountId) {
        return false;
      }
      if (row.voucherLineId case final lineId?) confirmedLineIds.add(lineId);
    }
    return confirmedLineIds.toSet().length == confirmedLineIds.length;
  }

  bool get _cashStageIsComplete {
    if (_draft == null) return false;
    for (final line in _cashLines) {
      final answer = _cashAnswers[line.voucherLine.lineId];
      if (answer == null || !answer.isAnswered) return false;
      if (answer.disposition == _CashDisposition.cashPayment) {
        final cashAmount = answer.amount ?? 0;
        final advanceIds =
            _advancesFor(line.voucherLine).map((advance) => advance.id).toSet();
        if (!advanceIds.containsAll(answer.selectedAdvanceIds)) return false;
        final amount = _cashResolvedAmount(line.voucherLine, answer);
        final method = _methodForLine(
          line.voucherLine.lineId,
          fallbackEmployeeId: line.voucherLine.employeeId,
        );
        if (amount <= 0 ||
            amount > line.voucherLine.pendingAmountClp ||
            cashAmount < 0 ||
            (cashAmount > 0 &&
                (method == null ||
                    method['is_active'] == false ||
                    !_isCanonicalCashMethod(method) ||
                    (method['account_id']?.toString().trim().isEmpty ??
                        true)))) {
          return false;
        }
        if (cashAmount > 0) {
          final paidAt = DateTime(
            answer.date.year,
            answer.date.month,
            answer.date.day,
          );
          final periodStart = DateTime(
            line.voucherLine.periodStart.year,
            line.voucherLine.periodStart.month,
            line.voucherLine.periodStart.day,
          );
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          if (paidAt.isBefore(periodStart) || paidAt.isAfter(today)) {
            return false;
          }
        }
      }
    }
    return true;
  }

  Widget _buildStage() {
    if (_appliedMessage != null) return _buildApplied();
    return switch (_stage) {
      PayrollReconciliationStage.file => _buildFileStage(),
      PayrollReconciliationStage.extract => _buildExtractStage(),
      PayrollReconciliationStage.review => _buildTransfersStage(),
      PayrollReconciliationStage.apply => _buildApplyStage(),
    };
  }

  Widget _buildApplied() {
    final visual = PayrollVisualTokens.of(context);
    final receipt = _appliedReceipt;
    final bankCount = _appliedDecisionCount(
      PayrollReviewDecisionKind.bankPayment,
    );
    final cashCount = _appliedDecisionCount(
      PayrollReviewDecisionKind.cashPayment,
    );
    final advanceCount = _appliedDecisionCount(
      PayrollReviewDecisionKind.advanceAllocation,
    );
    final heldCount = _appliedDecisionCount(PayrollReviewDecisionKind.hold);
    final outsidePayrollCount =
        _appliedDecisionCount(PayrollReviewDecisionKind.ignore);
    final unpaidCount =
        _appliedDecisionCount(PayrollReviewDecisionKind.notPaid);
    final affectedWeeks = receipt?.voucherVersions.length ??
        _appliedDecisions
            .map((decision) => decision.voucherId)
            .whereType<String>()
            .toSet()
            .length;
    final committedVoucherIds =
        receipt?.committedVoucherIds ?? const <String>[];
    final committedWeekLabels = <String>[
      for (final voucherId in committedVoucherIds)
        if (_draft?.vouchersById[voucherId] case final voucher?)
          (voucher.periodLabel?.trim().isEmpty ?? true)
              ? voucher.voucherNumber
              : voucher.periodLabel!.trim(),
    ];
    final operationKey = receipt?.operationKey.trim() ?? '';
    final importId = receipt?.importId.trim() ?? '';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
            decoration: BoxDecoration(
              color: visual.surface,
              borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
              border: Border.all(color: visual.successBorder),
              boxShadow: visual.raised,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: visual.successSoft,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.check_rounded,
                    size: 23,
                    color: visual.successFg,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _appliedMessage!,
                  textAlign: TextAlign.center,
                  style: visual.sectionTitle.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 6),
                Text(
                  receipt?.wasReplay == true
                      ? 'El servidor reconoció el mismo lote y devolvió su '
                          'resultado anterior; no duplicó compromisos ni pagos.'
                      : committedVoucherIds.isEmpty
                          ? 'Los saldos y la evidencia de las semanas afectadas '
                              'ya quedaron actualizados.'
                          : 'Las semanas indicadas quedaron confirmadas y '
                              'después se aplicaron los pagos revisados.',
                  textAlign: TextAlign.center,
                  style: visual.bodyS.copyWith(
                    color: visual.inkFaint,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (affectedWeeks > 0)
                      _SummaryChip(
                        label: '$affectedWeeks '
                            '${affectedWeeks == 1 ? 'semana' : 'semanas'}',
                      ),
                    if (committedVoucherIds.isNotEmpty)
                      _SummaryChip(
                        label: '${committedVoucherIds.length} '
                            '${committedVoucherIds.length == 1 ? 'semana confirmada' : 'semanas confirmadas'}',
                      ),
                    if (bankCount > 0)
                      _SummaryChip(
                        label: '$bankCount '
                            '${bankCount == 1 ? 'transferencia' : 'transferencias'}',
                      ),
                    if (cashCount > 0)
                      _SummaryChip(
                        label: '$cashCount '
                            '${cashCount == 1 ? 'efectivo' : 'efectivos'}',
                      ),
                    if (advanceCount > 0)
                      _SummaryChip(
                        label: '$advanceCount '
                            '${advanceCount == 1 ? 'anticipo' : 'anticipos'}',
                      ),
                    if (heldCount > 0)
                      _SummaryChip(label: '$heldCount en espera'),
                    if (outsidePayrollCount > 0)
                      _SummaryChip(
                        label: '$outsidePayrollCount fuera de nómina',
                      ),
                    if (unpaidCount > 0)
                      _SummaryChip(label: '$unpaidCount sin pagar'),
                  ],
                ),
                if (importId.isNotEmpty || operationKey.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: visual.surfaceSunken,
                      borderRadius: BorderRadius.circular(PayrollTokens.rField),
                      border: Border.all(color: visual.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'COMPROBANTE',
                          style: visual.monoS.copyWith(
                            color: visual.inkFaint,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (importId.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          _ReceiptIdentifier(
                            label: 'Importación',
                            value: importId,
                          ),
                        ],
                        if (operationKey.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _ReceiptIdentifier(
                            label: 'Operación',
                            value: operationKey,
                          ),
                        ],
                        if (committedWeekLabels.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _ReceiptIdentifier(
                            label: 'Compromiso',
                            value: committedWeekLabels.join(' · '),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  'En Nóminas, abre “Pagado” en cualquier persona para revisar '
                  'el movimiento y la evidencia bancaria asociada.',
                  textAlign: TextAlign.center,
                  style: visual.bodyS.copyWith(
                    color: visual.inkMuted,
                    height: 1.35,
                  ),
                ),
                if (_isLearningAliases ||
                    _learnedAliasCount > 0 ||
                    _pendingAliasIntents.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    key: const ValueKey('payroll-alias-learning-result'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: visual.surfaceSunken,
                      borderRadius: BorderRadius.circular(PayrollTokens.rField),
                      border: Border.all(
                        color: _aliasLearningError == null
                            ? visual.border
                            : visual.warningBorder,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isLearningAliases)
                          const Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text('Guardando nombres bancarios…'),
                              ),
                            ],
                          )
                        else if (_aliasLearningError != null) ...[
                          Text(
                            _aliasLearningError!,
                            style: visual.bodyS.copyWith(
                              color: visual.warningFg,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 9),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              FilledButton.tonalIcon(
                                key: const ValueKey(
                                  'payroll-retry-alias-learning',
                                ),
                                onPressed: _persistPendingAliases,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 18,
                                ),
                                label: const Text(
                                  'Reintentar sólo nombres',
                                ),
                              ),
                              TextButton(
                                onPressed: () => setState(() {
                                  _pendingAliasIntents = const [];
                                  _aliasLearningError = null;
                                }),
                                child: const Text('Omitir'),
                              ),
                            ],
                          ),
                        ] else
                          Text(
                            'Se ${_learnedAliasCount == 1 ? 'guardó 1 nombre bancario' : 'guardaron $_learnedAliasCount nombres bancarios'} para sugerencias futuras.',
                            style: visual.bodyS.copyWith(
                              color: visual.successFg,
                              height: 1.35,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _appliedDecisionCount(PayrollReviewDecisionKind kind) =>
      _appliedDecisions.where((decision) => decision.kind == kind).length;

  Widget _buildStatementSummary() {
    final visual = PayrollVisualTokens.of(context);
    final draft = _draft;
    if (draft == null) return const SizedBox.shrink();
    final datedRows = draft.parseResult.rows
        .map((row) => row.bookingDate)
        .whereType<PayrollCivilDate>()
        .toList(growable: false)
      ..sort();
    final firstDate = datedRows.isEmpty ? null : datedRows.first;
    final lastDate = datedRows.isEmpty ? null : datedRows.last;
    final warningMessages = <String>[
      ...draft.extraction.warnings,
      ...draft.parseResult.warnings.map((warning) => warning.message),
    ];
    final selectedAccount = _bankAccountOptions
        .where((option) => option.accountId == _selectedErpAccountId)
        .firstOrNull;
    final extractionLabel = switch (draft.extraction.method) {
      PayrollStatementExtractionMethod.embeddedPdfText => 'Texto del PDF',
      PayrollStatementExtractionMethod.onDeviceImageOcr => 'OCR local',
      PayrollStatementExtractionMethod.imageOcrRequired => 'OCR pendiente',
    };

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.description_outlined,
                size: 18,
                color: visual.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  draft.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: visual.cardTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            runSpacing: 7,
            children: [
              _SummaryChip(
                label:
                    '${draft.parseResult.rows.length} filas · ${draft.parseResult.outgoingCandidates.length} cargos',
              ),
              _SummaryChip(
                label:
                    '${draft.extraction.pages.length} ${draft.extraction.pages.length == 1 ? 'página' : 'páginas'} · $extractionLabel',
              ),
              if (firstDate != null && lastDate != null)
                _SummaryChip(
                  label: '${_civilDateLabel(firstDate)}–'
                      '${_civilDateLabel(lastDate)}',
                ),
              if (draft.documentDate != null)
                _SummaryChip(
                  label:
                      'Cierre declarado ${_civilDateLabel(draft.documentDate!)}',
                ),
              _SummaryChip(
                label:
                    'Cuenta de la cartola · termina en …${_maskedSuffix(draft.accountFingerprint)}',
              ),
              if (selectedAccount != null)
                _SummaryChip(label: selectedAccount.label),
            ],
          ),
          if (warningMessages.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              warningMessages.join(' · '),
              style: visual.bodyS.copyWith(
                color: visual.warningFg,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _civilDateLabel(PayrollCivilDate date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  List<PayrollVoucher> _draftVouchersToCommit(
    List<PayrollStatementReviewDecision> decisions,
  ) {
    final draft = _draft;
    if (draft == null) return const <PayrollVoucher>[];
    final voucherIdByLineId = <String, String>{
      for (final voucher in draft.vouchers)
        if (voucher.id case final voucherId?)
          for (final line in voucher.lines)
            if (line.id case final lineId?) lineId: voucherId,
    };
    final touchedVoucherIds = <String>{
      for (final decision in decisions)
        if ((decision.voucherId ??
                (decision.voucherLineId == null
                    ? null
                    : voucherIdByLineId[decision.voucherLineId]))
            case final voucherId?)
          voucherId,
    };
    final vouchers = <PayrollVoucher>[
      for (final voucherId in touchedVoucherIds)
        if (draft.vouchersById[voucherId] case final voucher?)
          if (voucher.status == PayrollVoucherStatus.draft) voucher,
    ]..sort((left, right) {
        final periodComparison = left.periodStart.compareTo(right.periodStart);
        if (periodComparison != 0) return periodComparison;
        return (left.id ?? '').compareTo(right.id ?? '');
      });
    return List<PayrollVoucher>.unmodifiable(vouchers);
  }

  List<_ConfirmationItem> _confirmationItems(
    List<PayrollStatementReviewDecision> decisions,
  ) {
    final draft = _draft;
    if (draft == null) return const [];
    final reviewRows = _transferRows;
    final items = <_ConfirmationItem>[];

    for (final decision in decisions) {
      PayrollDecisionRowData? reviewRow;
      for (final row in reviewRows) {
        if ((decision.sourceRowId != null &&
                row.sourceRowId == decision.sourceRowId) ||
            (decision.sourceRowId == null &&
                decision.voucherLineId != null &&
                row.voucherLineId == decision.voucherLineId)) {
          reviewRow = row;
          break;
        }
      }

      PayrollReconciliationLineResult? lineResult;
      if (decision.voucherLineId != null) {
        for (final result in draft.reconciliation.lineResults) {
          if (result.voucherLine.lineId == decision.voucherLineId) {
            lineResult = result;
            break;
          }
        }
      }

      PayrollStatementRow? statementRow;
      if (decision.sourceRowId != null) {
        for (final row in draft.parseResult.rows) {
          if (row.sourceRowId == decision.sourceRowId) {
            statementRow = row;
            break;
          }
        }
      }
      if (decision.kind == PayrollReviewDecisionKind.ignore &&
          statementRow?.isOutgoingCandidate != true &&
          reviewRow == null) {
        continue;
      }

      final employeeName = reviewRow?.title ??
          lineResult?.employee?.displayName ??
          'Movimiento de cartola';
      final voucherId = decision.voucherId ??
          reviewRow?.voucherId ??
          lineResult?.voucherLine.voucherId;
      final subtitle = voucherId == null
          ? (statementRow?.description ?? 'Sin semana asociada')
          : _periodLabelFor(voucherId);
      final amount = decision.amountClp ??
          reviewRow?.bankAmountClp ??
          lineResult?.voucherLine.pendingAmountClp ??
          0;
      final method = _methodForLine(
        decision.voucherLineId ??
            reviewRow?.voucherLineId ??
            lineResult?.voucherLine.lineId,
        fallbackEmployeeId: decision.employeeId ??
            reviewRow?.employeeId ??
            lineResult?.voucherLine.employeeId,
      );
      final accountLabel = switch (decision.kind) {
        PayrollReviewDecisionKind.bankPayment => _bankAccountOptions
            .where((option) => option.accountId == _selectedErpAccountId)
            .map((option) => option.label)
            .firstOrNull,
        PayrollReviewDecisionKind.cashPayment =>
          '${method?['name'] ?? 'Efectivo'} · '
              'cuenta …${_maskedSuffix(method?['account_id']?.toString() ?? '')}',
        PayrollReviewDecisionKind.advanceAllocation =>
          'Anticipo ${decision.advanceId == null ? '' : '…${_maskedSuffix(decision.advanceId!)}'}'
              .trim(),
        _ => null,
      };
      final action = switch (decision.kind) {
        PayrollReviewDecisionKind.bankPayment
            when decision.varianceDisposition ==
                PayrollVarianceDisposition.partial =>
          'Registrar pago parcial · quedan '
              '${formatPayrollClp(reviewRow?.remainingAmountClp ?? 0)} pendientes',
        PayrollReviewDecisionKind.bankPayment => 'Registrar transferencia',
        PayrollReviewDecisionKind.cashPayment => 'Registrar efectivo',
        PayrollReviewDecisionKind.advanceAllocation => 'Aplicar anticipo',
        PayrollReviewDecisionKind.notPaid => 'Mantener pendiente',
        PayrollReviewDecisionKind.hold => 'Retener como excepción',
        PayrollReviewDecisionKind.ignore =>
          reviewRow?.kind == PayrollDecisionRowKind.unmatchedMovement
              ? 'Fuera de nómina'
              : 'Ignorar evidencia',
        PayrollReviewDecisionKind.alreadyResolved => 'Ya conciliado antes',
      };
      final isMoney = decision.kind == PayrollReviewDecisionKind.bankPayment ||
          decision.kind == PayrollReviewDecisionKind.cashPayment ||
          decision.kind == PayrollReviewDecisionKind.advanceAllocation;
      items.add(
        _ConfirmationItem(
          title: employeeName,
          subtitle: subtitle,
          action: action,
          amountClp: amount,
          weekLabel: voucherId == null
              ? 'Fuera de nómina'
              : _periodLabelFor(voucherId),
          isMoney: isMoney,
          accountLabel: accountLabel,
        ),
      );
    }
    return List<_ConfirmationItem>.unmodifiable(items);
  }

  /// Compact per-week impact of the decisions taken so far. Shown in the
  /// persistent bar until the final summary takes over in stage 4.
  String? _weekImpactNote(List<PayrollStatementReviewDecision> decisions) {
    final draft = _draft;
    if (draft == null) return null;
    final totals = <String, int>{};
    for (final decision in decisions) {
      final isMoney = decision.kind == PayrollReviewDecisionKind.bankPayment ||
          decision.kind == PayrollReviewDecisionKind.cashPayment ||
          decision.kind == PayrollReviewDecisionKind.advanceAllocation;
      final voucherId = decision.voucherId;
      if (!isMoney || voucherId == null) continue;
      totals.update(
        _periodLabelFor(voucherId),
        (value) => value + (decision.amountClp ?? 0),
        ifAbsent: () => decision.amountClp ?? 0,
      );
    }
    if (totals.isEmpty) return null;
    final parts = totals.entries
        .map((entry) => '${entry.key} +${formatPayrollClp(entry.value)}')
        .join(' · ');
    return 'Impacto por semana: $parts';
  }

  Widget _buildFileStage() {
    final visual = PayrollVisualTokens.of(context);
    final actions = _actions();
    final supportsImages = actions.isImageOcrSupported;
    final supportsCapture = actions.isCameraCaptureSupported;

    return ListView(
      key: const PageStorageKey<String>('payroll-reconciliation-file'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Container(
              key: const ValueKey('payroll-reconciliation-file-card'),
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              decoration: BoxDecoration(
                color: visual.surface,
                borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
                border: Border.all(color: visual.borderStrong),
                boxShadow: visual.raised,
              ),
              child: Column(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: visual.accentSoft,
                      borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
                      border: Border.all(color: visual.accentBorder),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.document_scanner_outlined,
                      color: visual.accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 13),
                  Text(
                    'Sube la cartola',
                    style: visual.sectionTitle.copyWith(fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    supportsImages
                        ? 'Lee cartolas de Banco de Chile en PDF —también '
                            'escaneado—, JPG, PNG o WebP. La extracción y el '
                            'OCR ocurren en este dispositivo.'
                        : 'En este dispositivo lee cartolas de Banco de Chile '
                            'en PDF con texto seleccionable. El archivo nunca '
                            'se envía a un servicio de OCR externo.',
                    textAlign: TextAlign.center,
                    style: visual.bodyS.copyWith(
                      color: visual.inkFaint,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 13),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      const _CapabilityChip(
                        label: 'PDF con texto',
                        available: true,
                      ),
                      _CapabilityChip(
                        label: 'PDF escaneado e imágenes',
                        available: supportsImages,
                      ),
                      _CapabilityChip(
                        label: 'Cámara',
                        available: supportsCapture,
                        unavailableLabel: 'Sólo Android/iPhone',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Al aplicar se guarda evidencia estructurada; no se '
                    'conserva la imagen ni el texto OCR completo.',
                    textAlign: TextAlign.center,
                    style: visual.bodyS.copyWith(
                      color: visual.inkFaint,
                      height: 1.35,
                    ),
                  ),
                  if (_versionedBackendMissing) ...[
                    const SizedBox(height: 12),
                    Container(
                      key: const ValueKey(
                        'payroll-reconciliation-backend-missing',
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: visual.warningSoft,
                        borderRadius:
                            BorderRadius.circular(PayrollTokens.rField),
                        border: Border.all(color: visual.warningBorder),
                      ),
                      child: Text(
                        'Modo revisión: el servidor aún no tiene la '
                        'actualización de nóminas. Puedes cargar, leer y '
                        'revisar la cartola; importar y aplicar quedarán '
                        'disponibles cuando se instale.',
                        textAlign: TextAlign.center,
                        style: visual.bodyS.copyWith(
                          color: visual.warningFg,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      PayrollPrimaryAction(
                        label: 'Elegir archivo',
                        icon: Icons.folder_open_rounded,
                        busy: _isBusy,
                        onPressed: _isBusy
                            ? null
                            : () => _choose(
                                  widget.pickFile ?? _defaultFilePicker,
                                ),
                      ),
                      if (supportsCapture) ...[
                        PayrollSecondaryAction(
                          label: 'Cámara',
                          icon: Icons.photo_camera_outlined,
                          onPressed: _isBusy
                              ? null
                              : () => _choose(
                                    widget.pickCamera ??
                                        () => _defaultImagePicker(
                                              ImageSource.camera,
                                            ),
                                  ),
                        ),
                      ],
                      if (supportsImages) ...[
                        PayrollSecondaryAction(
                          label: 'Galería',
                          icon: Icons.photo_library_outlined,
                          onPressed: _isBusy
                              ? null
                              : () => _choose(
                                    widget.pickGallery ??
                                        () => _defaultImagePicker(
                                              ImageSource.gallery,
                                            ),
                                  ),
                        ),
                      ],
                    ],
                  ),
                  if (_isBusy && _preparationProgress != null) ...[
                    const SizedBox(height: 14),
                    _PreparationProgress(
                      progress: _preparationProgress!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!supportsImages) ...[
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: const _Notice(
                message: 'La lectura de imágenes necesita OCR en el propio '
                    'dispositivo y aquí no está disponible. Usa un PDF con '
                    'texto seleccionable, o abre esta tarea desde Mac, Android '
                    'o iPhone para un PDF escaneado, una foto o la cámara.',
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _Notice(
                message: _error!,
                isError: true,
                actionLabel: _errorActionLabel,
                onAction: _errorActionLabel == null ? null : _runErrorRecovery,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _reviewRow(PayrollDecisionRowData row, {required bool isFirst}) {
    return PayrollReconciliationRow(
      data: row,
      isFirst: isFirst,
      enabled: !_isReviewLocked,
      disposition: _dispositionFor(row),
      onDisposition: (value) {
        _setRowDisposition(row, value);
      },
      varianceDisposition: _varianceFor(row),
      onVarianceDisposition: (value) => setState(() {
        _varianceDispositions[row.id] = value;
      }),
      reviewReason: _reviewReasonFor(row),
      onReviewReasonChanged: (value) => setState(() {
        _reviewReasons[row.id] = value;
      }),
      learnBeneficiaryAlias: _learnAliasSourceRowIds.contains(row.sourceRowId),
      onLearnBeneficiaryAliasChanged:
          _actions().learnBeneficiaryAlias == null || row.sourceRowId == null
              ? null
              : (value) => setState(() {
                    if (value) {
                      _learnAliasSourceRowIds.add(row.sourceRowId!);
                    } else {
                      _learnAliasSourceRowIds.remove(row.sourceRowId);
                    }
                  }),
      onManualMatchChanged: (value) => setState(() {
        final sourceRowId = row.sourceRowId;
        if (sourceRowId == null) return;
        if (value == null) {
          _manualLineBySourceRowId.remove(sourceRowId);
          _dispositions.remove(row.id);
        } else {
          _manualLineBySourceRowId[sourceRowId] = value;
          _dispositions[row.id] = PayrollRowDisposition.pending;
        }
        _learnAliasSourceRowIds.remove(sourceRowId);
        _varianceDispositions.remove(row.id);
        _reviewReasons.remove(row.id);
      }),
    );
  }

  int _answeredCount(List<PayrollDecisionRowData> rows) => rows
      .where((row) =>
          !row.requiresDisposition ||
          _dispositionFor(row) != PayrollRowDisposition.pending)
      .length;

  // ── Paso 2 — revisión de transferencias (Design 2c) ──────────────────────

  static String _initialsOf(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '·';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  Color _reconAvatarFor(String seed, PayrollVisualTokens visual) {
    final palette = <Color>[
      visual.avatarSky,
      visual.avatarCyan,
      visual.avatarAmber,
    ];
    return palette[seed.hashCode.abs() % palette.length];
  }

  static String _ledgerDate(PayrollCivilDate? date) {
    if (date == null) return '—';
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}';
  }

  /// A suggestion is batch-approvable only when nothing about it demands
  /// individual judgement: the unique proposal is selected, amounts match
  /// exactly and the OCR read carries no warnings.
  bool _suggestionIsBatchSafe(PayrollDecisionRowData row) =>
      row.kind == PayrollDecisionRowKind.suggested &&
      _dispositionFor(row) == PayrollRowDisposition.pending &&
      row.canConfirm &&
      !row.hasVariance &&
      row.warningCodes.isEmpty &&
      !row.isManualMatch &&
      !row.needsReviewReason;

  String _statusLabelFor(PayrollRowDisposition disposition) =>
      disposition == PayrollRowDisposition.confirm
          ? 'CONFIRMADO'
          : disposition.label.toUpperCase();

  // ── Tabla de revisión (Design t5 · 5j paso 3) ────────────────────────────

  /// Nombra por qué la fila se ve como se ve. Es descripción, no juicio.
  (String, PayrollStateTone) _rowStateTag(PayrollDecisionRowData row) {
    final visual = PayrollVisualTokens.of(context);
    if (row.kind == PayrollDecisionRowKind.alreadyResolvedMovement) {
      return ('YA REGISTRADO', visual.neutral);
    }
    if (row.kind == PayrollDecisionRowKind.incompleteEvidence) {
      return ('LECTURA INCOMPLETA', visual.danger);
    }
    if (row.kind == PayrollDecisionRowKind.ineligibleLine) {
      return ('SIN MOVIMIENTO', visual.warning);
    }
    if (row.isPartialPayment) return ('PAGO PARCIAL', visual.warning);
    if (row.isAutomaticallyClassified) {
      return (
        _dispositionFor(row) == PayrollRowDisposition.notPayroll
            ? 'SIN PERSONA DE NÓMINA'
            : 'FUERA DE VENTANA',
        visual.neutral,
      );
    }
    if (row.kind == PayrollDecisionRowKind.suggested) {
      if (row.warningCodes.isNotEmpty) {
        return ('REVISAR LECTURA', visual.warning);
      }
      if (row.hasVariance) {
        return (
          'TOLERANCIA ${formatPayrollClpSigned(row.varianceClp!)}',
          visual.warning,
        );
      }
      return ('CALCE EXACTO', visual.success);
    }
    return ('DECIDE UNA PERSONA', visual.warning);
  }

  /// Una línea honesta de por qué calza (o no). Se lee antes de decidir.
  String _rowWhy(PayrollDecisionRowData row) {
    if (row.explanations.isNotEmpty) return row.explanations.first;
    return switch (row.kind) {
      PayrollDecisionRowKind.ineligibleLine =>
        'Ningún movimiento de la cartola nombra esta obligación.',
      PayrollDecisionRowKind.incompleteEvidence =>
        'La lectura de esta línea no es segura; no puede crear un pago.',
      _ => 'Sin coincidencia automática.',
    };
  }

  /// Acción principal de la fila, con la palabra exacta de su consecuencia.
  /// Which open question the leading card is currently showing, so the list
  /// below never renders it twice.
  bool _isLeadingQuestion(List<PayrollDecisionRowData> pending, int index) {
    if (pending.isEmpty) return false;
    final stagedIndex = _stagedQuestionRowId == null
        ? -1
        : pending.indexWhere((r) => r.id == _stagedQuestionRowId);
    final leading = stagedIndex >= 0
        ? stagedIndex
        : _pendingQuestionIndex.clamp(0, pending.length - 1);
    return index == leading;
  }

  void _toggleReviewGroup(String id) {
    setState(() {
      if (!_openReviewGroups.remove(id)) _openReviewGroups.add(id);
    });
  }

  /// The card that leads the step: one open question at a time, with its full
  /// evidence in place. When nothing is pending the card does not vanish — it
  /// says so, because an empty area reads as "the screen failed to load".
  Widget _buildPendingQuestion(List<PayrollDecisionRowData> pending) {
    // A row staged with "Ver" is shown even when it is not one of the open
    // questions — otherwise asking to look at a resolved movement would
    // silently do nothing.
    final staged = _stagedQuestionRowId == null
        ? null
        : _transferRows.where((r) => r.id == _stagedQuestionRowId).firstOrNull;
    if (staged != null && !pending.any((r) => r.id == staged.id)) {
      return PayrollPendingDecisionCard(
        key: const ValueKey('payroll-pending-decision-card'),
        counterLabel: 'REVISANDO',
        explainer: _rowWhy(staged),
        onNext: pending.isEmpty
            ? null
            : () => setState(() => _stagedQuestionRowId = null),
        child: _reviewRow(staged, isFirst: true),
      );
    }
    if (pending.isEmpty) {
      // Same slot, same key: the step always has a leading card. A slot that
      // disappears when the work is done reads as a screen that failed to
      // load, and it makes "where do I decide?" a different question on every
      // visit.
      return const PayrollNoPendingDecisionsCard(
        key: ValueKey('payroll-pending-decision-card'),
        message: 'No queda nada por decidir en esta cartola. Revisa los '
            'grupos de abajo si quieres cambiar algo antes de aplicar.',
      );
    }
    final stagedIndex =
        staged == null ? -1 : pending.indexWhere((r) => r.id == staged.id);
    final index = stagedIndex >= 0
        ? stagedIndex
        : _pendingQuestionIndex.clamp(0, pending.length - 1);
    final row = pending[index];
    return PayrollPendingDecisionCard(
      key: const ValueKey('payroll-pending-decision-card'),
      counterLabel: '${index + 1} DE ${pending.length}',
      explainer: _rowWhy(row),
      onPrevious:
          pending.length > 1 && index > 0 ? () => _moveQuestion(-1) : null,
      onNext: pending.length > 1 && index < pending.length - 1
          ? () => _moveQuestion(1)
          : null,
      child: _reviewRow(row, isFirst: true),
    );
  }

  void _moveQuestion(int delta) {
    setState(() => _pendingQuestionIndex += delta);
  }

  /// A dense, auditable line inside a collapsed group. It carries the row's own
  /// key so a test — and a human reading a bug report — can point at exactly
  /// one movement.
  Widget _ledgerRowFor(
    PayrollDecisionRowData row, {
    required bool isFirst,
    // The verb names what the tap DOES in this group, which is not the same
    // thing everywhere: a suggestion is inspected, an automatic verdict is
    // audited, an answered row is amended. One generic "Ver" would hide that.
    String reopenLabel = 'Ver',
  }) {
    final visual = PayrollVisualTokens.of(context);
    final disposition = _dispositionFor(row);
    final answered = disposition != PayrollRowDisposition.pending;
    // La tabla de coincidencias de 5j paso 3 es la composición de Design para
    // esta etapa: fecha · movimiento · monto · persona y semana · por qué
    // calza · confianza · decisión. Antes se montaba un ledger denso —una
    // composición que otro turno improvisó y que funcionaba— mientras
    // `PayrollReviewTableRow`, que es la de Design, quedaba escrita y sin
    // instanciar. La regla del dueño es explícita: manda el diseño de Design
    // aunque lo otro funcione bien.
    return PayrollReviewTableRow(
      key: ValueKey('payroll-ledger-${row.id}'),
      isFirst: isFirst,
      settled: answered,
      date: _ledgerDate(row.date),
      description: row.bankDescription.isEmpty
          ? 'Obligación sin movimiento en la cartola'
          : row.bankDescription,
      amount: switch (row.bankAmountClp ?? row.expectedAmountClp) {
        final amount? => formatPayrollClp(amount),
        null => '—',
      },
      person: row.title.isEmpty ? null : row.title,
      // 5j paso 3 pide «persona Y semana»: sin la semana y el monto que esa
      // semana espera, dos filas del mismo trabajador son indistinguibles y
      // no hay contra qué contrastar el monto de la cartola.
      personDetail: _rowPersonDetail(row),
      initials: _initialsOf(row.title),
      avatarColor: _reconAvatarFor(row.employeeId ?? row.title, visual),
      why: _rowWhy(row),
      // Answered rows say what was decided; open ones say what the matcher
      // found, in words. Both are the reason — never a bare score.
      stateTag: answered ? _statusLabelFor(disposition) : _rowStateTag(row).$1,
      stateTone: answered ? disposition.toneOf(visual) : _rowStateTag(row).$2,
      confidence: answered || _isReviewLocked
          ? const SizedBox.shrink()
          : PayrollConfidencePill(
              score: row.confidenceScore,
              manual: row.manualCertainty,
            ),
      decision: _isReviewLocked
          ? const SizedBox.shrink()
          : LayoutBuilder(
              builder: (context, constraints) {
                // 5j paso 3: la celda de decisión lleva UN verbo y un `⋯`,
                // no dos botones. La confianza ya vive en su propia columna,
                // y dos verbos lado a lado no caben en los 150 px que la
                // tabla le reserva —desbordaba 39 px—. El verbo es el que
                // mueve el trabajo; el `⋯` abre el camino largo.
                final batchSafe = !answered && _suggestionIsBatchSafe(row);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: PayrollSoftAction(
                        label: batchSafe ? 'Confirmar' : reopenLabel,
                        onTap: batchSafe
                            ? () => _setRowDisposition(
                                row, PayrollRowDisposition.confirm)
                            : () => _stageRowAsQuestion(row),
                        height: 28,
                      ),
                    ),
                    if (batchSafe) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: reopenLabel,
                        child: Semantics(
                          button: true,
                          label: '$reopenLabel esta coincidencia',
                          child: InkWell(
                            key: ValueKey('payroll-row-more-${row.id}'),
                            onTap: () => _stageRowAsQuestion(row),
                            borderRadius: BorderRadius.circular(
                              PayrollTokens.rField,
                            ),
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  PayrollTokens.rField,
                                ),
                                border: Border.all(color: visual.border),
                              ),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                size: 15,
                                color: visual.inkMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  /// Brings a row up into the leading card instead of expanding it in place:
  /// the card is the single surface where a decision is made, so evidence never
  /// appears in two shapes at once.
  void _stageRowAsQuestion(PayrollDecisionRowData row) {
    setState(() {
      _stagedQuestionRowId = row.id;
    });
  }

  Widget _buildTransfersStage() {
    final visual = PayrollVisualTokens.of(context);
    final rows = _transferRows;
    final missingMethods = [
      for (final employeeId
          in _draft?.missingCanonicalPaymentMethodEmployeeIds ??
              const <String>{})
        (id: employeeId, name: _employeeNameFor(employeeId)),
    ]..sort((left, right) => left.name.compareTo(right.name));
    // Static grouping by origin, so a row never jumps between groups while
    // the operator answers it. The pending-decision card leads the step;
    // suggestions are batchable evidence; clearly unrelated movements stay
    // collapsed, auditable and reversible.
    final automaticallyClassifiedRows = rows
        .where((row) => row.isAutomaticallyClassified)
        .toList(growable: false);
    final pendingCount = rows
        .where((row) =>
            row.requiresDisposition &&
            _dispositionFor(row) == PayrollRowDisposition.pending)
        .length;
    final readyCount = rows
        .where((row) =>
            row.requiresDisposition &&
            _dispositionFor(row) != PayrollRowDisposition.pending)
        .length;
    final automaticCount = automaticallyClassifiedRows.length;
    // Las tres pilas de la 2c. Una fila pertenece a exactamente una: la
    // pregunta abierta, el calce que se puede aprobar en lote, o la evidencia
    // ya resuelta/clasificada.
    final pendingRows = rows
        .where((row) =>
            !row.isAutomaticallyClassified &&
            row.requiresDisposition &&
            (_dispositionFor(row) == PayrollRowDisposition.pending ||
                _answeredInPlaceRowIds.contains(row.id)) &&
            !_suggestionIsBatchSafe(row))
        .toList(growable: false);
    final suggestedRows = rows
        .where((row) =>
            !row.isAutomaticallyClassified &&
            row.requiresDisposition &&
            _dispositionFor(row) == PayrollRowDisposition.pending &&
            _suggestionIsBatchSafe(row))
        .toList(growable: false);
    final resolvedRows = rows
        .where((row) =>
            !row.isAutomaticallyClassified &&
            !_answeredInPlaceRowIds.contains(row.id) &&
            (!row.requiresDisposition ||
                _dispositionFor(row) != PayrollRowDisposition.pending))
        .toList(growable: false);
    // Orden estable: primero lo que exige criterio, luego lo resuelto y al
    // final la evidencia clasificada. Una fila nunca salta de lugar por
    // responderla: se recalcula sólo al recomponer la etapa.
    return ListView(
      key: const PageStorageKey<String>('payroll-reconciliation-transfers'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        _buildStatementSummary(),
        const SizedBox(height: 12),
        if (missingMethods.isNotEmpty) ...[
          _MissingPaymentMethodsPanel(
            employees: missingMethods,
            enabled: !_isReviewLocked,
            onConfigure: _configureEmployeePaymentMethod,
          ),
          const SizedBox(height: 12),
        ],
        if (_bankAccountOptions.isEmpty)
          const _Notice(
            message: 'Configura un método Transferencia activo con su cuenta '
                'contable antes de importar esta cartola.',
            isError: true,
          )
        else
          DropdownButtonFormField<String>(
            key: const ValueKey('payroll-statement-erp-account'),
            initialValue: _selectedErpAccountId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Cuenta ERP de esta cartola',
              helperText:
                  'Se usará la misma cuenta para todos los pagos bancarios.',
            ),
            items: [
              for (final option in _bankAccountOptions)
                DropdownMenuItem<String>(
                  value: option.accountId,
                  child: Text(
                    option.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _isReviewLocked
                ? null
                : (value) => setState(() {
                      _selectedErpAccountId = value;
                      _error = null;
                    }),
          ),
        const SizedBox(height: 12),
        if (rows.isEmpty)
          const _Notice(message: 'La cartola no trae movimientos revisables.')
        else ...[
          // Composición 2c: UNA pregunta lidera la etapa. La tabla completa
          // ponía las 40 filas al mismo nivel, así que el operador tenía que
          // encontrar el trabajo real entre la evidencia. Acá la carga humana
          // va arriba, de a una, y lo demás nace plegado —visible y reabrible,
          // nunca oculto.
          // Three long bucket labels in one row need ~450 px; a phone gives
          // 354. Below that the strip is dropped rather than squeezed: each
          // section already carries its own count, so nothing is lost, and
          // 5l asks for one decision per screen instead of a summary band.
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 600) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PayrollReviewTableHeader(
                  buckets: [
                    ('necesitan tu decisión', pendingCount, visual.warning),
                    ('listos', readyCount, visual.success),
                    ('fuera de nómina', automaticCount, visual.neutral),
                  ],
                  rule: 'Cruce por persona + fecha dentro de la semana + '
                      'monto con tolerancia',
                ),
              );
            },
          ),
          _buildPendingQuestion(pendingRows),
          // The card leads with one question, but the remaining open ones are
          // NOT hidden behind it: mandatory work is never born collapsed, and
          // an operator scanning for "what is still stopping me" must see all
          // of it without clicking. Evidence and answered rows are what
          // collapse, further down.
          for (var i = 0; i < pendingRows.length; i++)
            if (!_isLeadingQuestion(pendingRows, i))
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _reviewRow(pendingRows[i], isFirst: true),
              ),
          const SizedBox(height: 12),
          if (suggestedRows.isNotEmpty) ...[
            PayrollReviewSection(
              key: const ValueKey('review-group-suggested'),
              dotColor: visual.success.fg,
              title: 'Calces sugeridos',
              subtitle: '${suggestedRows.length} sin diferencias',
              open: _openReviewGroups.contains('suggested'),
              onToggle: () => _toggleReviewGroup('suggested'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < suggestedRows.length; i++)
                    _ledgerRowFor(suggestedRows[i], isFirst: i == 0),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (automaticallyClassifiedRows.isNotEmpty) ...[
            PayrollReviewSection(
              key: const ValueKey('review-group-automatic'),
              dotColor: visual.neutral.fg,
              title: 'Fuera del lote de nómina',
              subtitle: '${automaticallyClassifiedRows.length} '
                  'clasificados solos',
              open: _openReviewGroups.contains('automatic'),
              onToggle: () => _toggleReviewGroup('automatic'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < automaticallyClassifiedRows.length; i++)
                    _ledgerRowFor(automaticallyClassifiedRows[i],
                        isFirst: i == 0, reopenLabel: 'Revisar'),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (resolvedRows.isNotEmpty) ...[
            PayrollReviewSection(
              key: const ValueKey('review-group-resolved'),
              dotColor: visual.success.fg,
              title: 'Ya respondidos',
              subtitle: '${resolvedRows.length} ya respondidos',
              open: _openReviewGroups.contains('resolved'),
              onToggle: () => _toggleReviewGroup('resolved'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < resolvedRows.length; i++)
                    _ledgerRowFor(resolvedRows[i],
                        isFirst: i == 0, reopenLabel: 'Cambiar'),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 2),
          // Las tres lecturas que el operador necesita para confiar en la
          // tabla: por qué Vicente sigue abierto, qué significa corregir a
          // mano y qué pasó con lo que no calza con nadie.
          LayoutBuilder(
            builder: (context, constraints) {
              final notes = <Widget>[
                _ReviewNote(
                  tone: visual.warning,
                  title: 'Un monto que no calza no se aplica solo',
                  body: 'Si el nombre coincide pero ningún saldo de esa '
                      'persona calza, la fila queda abierta. Decidir es tuyo: '
                      'puede ser otro gasto, un adelanto o un pago parcial.',
                ),
                _ReviewNote(
                  tone: visual.info,
                  title: 'Corregir a mano cambia quién responde',
                  body: 'Persona, semana y monto se editan en la misma fila. '
                      'Al corregir, la confianza pasa a MANUAL 100%: la '
                      'responsabilidad es de quien decidió, no del algoritmo.',
                ),
                _ReviewNote(
                  tone: visual.neutral,
                  title: 'Nada desaparece de la cartola',
                  body: 'Lo que no coincide con ninguna persona se clasifica '
                      'fuera de nómina y queda visible acá mismo. Puedes '
                      'reabrirlo cuando quieras; nada se borra.',
                ),
              ];
              if (constraints.maxWidth < 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < notes.length; index++) ...[
                      if (index != 0) const SizedBox(height: 8),
                      notes[index],
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < notes.length; index++) ...[
                    if (index != 0) const SizedBox(width: 10),
                    Expanded(child: notes[index]),
                  ],
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildCashSection() {
    final visual = PayrollVisualTokens.of(context);
    final lines = _cashLines;
    final unanswered = lines
        .where((line) =>
            !(_cashAnswers[line.voucherLine.lineId]?.isAnswered ?? false))
        .toList(growable: false);
    PayrollReconciliationLineResult? active;
    for (final line in lines) {
      if (line.voucherLine.lineId == _activeCashLineId) {
        active = line;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: visual.surface,
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            border: Border.all(color: visual.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: visual.warningFg,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'El efectivo no aparece en la cartola. Revisa una persona '
                  'a la vez y confirma qué pasó; nada avanza solo.',
                  style: visual.bodyS.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (lines.isEmpty)
          const _Notice(message: 'Nadie de esta nómina cobra en efectivo.')
        else ...[
          Container(
            decoration: BoxDecoration(
              color: visual.surface,
              borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
              border: Border.all(color: visual.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var index = 0; index < lines.length; index++)
                  _CashPersonTile(
                    line: lines[index],
                    answer: _cashAnswers[lines[index].voucherLine.lineId],
                    advanceAmount: switch (
                        _cashAnswers[lines[index].voucherLine.lineId]) {
                      final answer? =>
                        _cashAdvanceAmount(lines[index].voucherLine, answer),
                      null => 0,
                    },
                    periodLabel:
                        _periodLabelFor(lines[index].voucherLine.voucherId),
                    isFirst: index == 0,
                    isActive:
                        lines[index].voucherLine.lineId == _activeCashLineId,
                    enabled: !_isReviewLocked,
                    onTap: () => setState(
                      () => _activeCashLineId = lines[index].voucherLine.lineId,
                    ),
                  ),
              ],
            ),
          ),
          if (active != null) ...[
            const SizedBox(height: 14),
            _CashCard(
              key: ValueKey('cash-card-${active.voucherLine.lineId}'),
              line: active,
              answer: _cashAnswers.putIfAbsent(
                active.voucherLine.lineId,
                () => _CashAnswer(
                  amount: active!.voucherLine.pendingAmountClp.toDouble(),
                ),
              ),
              advances: _advancesFor(active.voucherLine),
              periodLabel: _periodLabelFor(active.voucherLine.voucherId),
              actorLabel: _authenticatedActorLabel,
              enabled: !_isReviewLocked,
              onChanged: () => setState(() {}),
              onConfirm: () => setState(() => _activeCashLineId = null),
            ),
          ] else if (unanswered.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Flexible(
                  child: FilledButton.tonalIcon(
                    onPressed: _isReviewLocked
                        ? null
                        : () => setState(
                              () => _activeCashLineId =
                                  unanswered.first.voucherLine.lineId,
                            ),
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: Text(
                      'Responder a ${unanswered.first.employee?.displayName ?? 'la siguiente persona'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize:
                          const Size(0, PayrollMoneyBar.minimumTouchTarget),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 14),
            const _Notice(
              message: 'Todas las personas en efectivo tienen respuesta. '
                  'Puedes tocar a cualquiera para cambiarla, o continuar al '
                  'resumen.',
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildConfirmSection() {
    final theme = Theme.of(context);
    final visual = PayrollVisualTokens.of(context);
    final blockers = _blockers;
    final decisions = _buildDecisions();
    final items = _confirmationItems(decisions);
    final draftVouchersToCommit = _draftVouchersToCommit(decisions);
    final informationalRows = decisions.where((decision) {
      if (decision.kind != PayrollReviewDecisionKind.ignore ||
          decision.sourceRowId == null) {
        return false;
      }
      return _draft?.parseResult.rows.any(
            (row) =>
                row.sourceRowId == decision.sourceRowId &&
                !row.isOutgoingCandidate,
          ) ??
          false;
    }).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
          decoration: BoxDecoration(
            color: visual.surface,
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            border: Border.all(color: visual.border),
          ),
          child: Row(
            children: [
              Icon(
                Icons.playlist_add_check_rounded,
                size: 18,
                color: visual.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Se registrará ${decisions.length} '
                  '${decisions.length == 1 ? 'decisión' : 'decisiones'} en '
                  'una sola operación, agrupadas por semana.',
                  style: visual.bodyS.copyWith(height: 1.4),
                ),
              ),
            ],
          ),
        ),
        if (draftVouchersToCommit.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DraftCommitmentPanel(vouchers: draftVouchersToCommit),
        ],
        const SizedBox(height: 12),
        if (items.isEmpty)
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(14),
            child: const Text('Todavía no hay decisiones listas para aplicar.'),
          )
        else
          ..._buildConfirmGroups(theme, items),
        if (informationalRows > 0) ...[
          const SizedBox(height: 10),
          Text(
            '$informationalRows '
            '${informationalRows == 1 ? 'fila informativa quedará' : 'filas informativas quedarán'} '
            'auditada fuera de nómina.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (blockers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Falta resolver antes de aplicar',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                for (final blocker in blockers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '· $blocker',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          _Notice(
            message: _error!,
            isError: true,
            actionLabel: _errorActionLabel,
            onAction: _errorActionLabel == null ? null : _runErrorRecovery,
          ),
        ],
      ],
    );
  }

  /// Final summary grouped by week: each group names the week, the money it
  /// recognizes, and every decision inside it.
  List<Widget> _buildConfirmGroups(
    ThemeData theme,
    List<_ConfirmationItem> items,
  ) {
    final visual = PayrollVisualTokens.of(context);
    final groups = <String, List<_ConfirmationItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.weekLabel, () => []).add(item);
    }
    final orderedKeys = [
      ...groups.keys.where((key) => key != 'Fuera de nómina'),
      if (groups.containsKey('Fuera de nómina')) 'Fuera de nómina',
    ];

    return [
      for (final key in orderedKeys) ...[
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: visual.surface,
            borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
            border: Border.all(color: visual.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                color: visual.surfaceSunken,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        key,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      'Se reconocen ${formatPayrollClp(groups[key]!.where((item) => item.isMoney).fold<int>(0, (sum, item) => sum + item.amountClp))}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              for (var index = 0; index < groups[key]!.length; index++)
                _ConfirmationRow(
                  item: groups[key]![index],
                  isFirst: index == 0,
                ),
            ],
          ),
        ),
      ],
    ];
  }

  Widget _buildExtractStage() {
    final visual = PayrollVisualTokens.of(context);
    final draft = _draft;
    if (draft == null) {
      return const _Notice(message: 'Carga una cartola primero.');
    }
    final rows = draft.parseResult.rows;
    final outgoing = rows.where((row) => row.isOutgoingCandidate).length;
    final incomplete =
        rows.where((row) => !row.hasCompleteStructuredEvidence).length;
    final dates = rows
        .map((row) => row.bookingDate)
        .whereType<PayrollCivilDate>()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    final weekLabels = {
      for (final voucher in draft.vouchersById.values)
        if (voucher.id case final id?) _periodLabelFor(id),
    }.toList();
    // Las líneas que exigen lectura humana van primero; el resto se resume.
    final ordered = [...rows]..sort((a, b) {
        int weight(PayrollStatementRow row) =>
            !row.hasCompleteStructuredEvidence
                ? 0
                : _warningCodesFor(row).isNotEmpty
                    ? 1
                    : 2;
        return weight(a).compareTo(weight(b));
      });
    const visibleCap = 9;
    final visible = ordered.take(visibleCap).toList(growable: false);
    final hidden = rows.length - visible.length;

    Widget readingTag(PayrollStatementRow row) {
      final PayrollStateTone tone;
      final String label;
      if (!row.hasCompleteStructuredEvidence) {
        tone = visual.danger;
        label = 'ILEGIBLE';
      } else if (_warningCodesFor(row).isNotEmpty) {
        tone = visual.warning;
        label = 'LECTURA DUDOSA';
      } else {
        tone = visual.success;
        label = 'NÍTIDA';
      }
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: tone.soft,
          borderRadius: BorderRadius.circular(PayrollTokens.rTag),
          border: Border.all(color: tone.border),
        ),
        child: Text(
          label,
          style: visual.monoS.copyWith(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: tone.fg,
          ),
        ),
      );
    }

    Widget factRow(String label, String value, {PayrollStateTone? tone}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: tone?.soft ?? visual.surface,
          borderRadius: BorderRadius.circular(PayrollTokens.rField),
          border: Border.all(color: tone?.border ?? visual.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: visual.bodyS.copyWith(
                  fontSize: 10.5,
                  color: tone?.fg ?? visual.inkMuted,
                ),
              ),
            ),
            Text(
              value,
              style: visual.monoM.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: tone?.fg ?? visual.ink,
              ),
            ),
          ],
        ),
      );
    }

    final table = Container(
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(17, 10, 17, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: visual.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${rows.length} de ${rows.length} líneas leídas',
                    style: visual.monoM.copyWith(fontSize: 11),
                  ),
                ),
                Text('LECTURA', style: visual.overline),
              ],
            ),
          ),
          for (var index = 0; index < visible.length; index++)
            PayrollStatementLedgerRow(
              isFirst: index == 0,
              date: _ledgerDate(visible[index].bookingDate),
              description: visible[index].description,
              amount: switch (visible[index].debitAmountClp ??
                  visible[index].creditAmountClp) {
                final amount? => formatPayrollClp(amount),
                null => '—',
              },
              trailing: readingTag(visible[index]),
            ),
          if (hidden > 0)
            Container(
              padding: const EdgeInsets.fromLTRB(17, 9, 17, 11),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: visual.border)),
              ),
              child: Text(
                '… $hidden ${hidden == 1 ? 'movimiento más' : 'movimientos más'} '
                'con lectura nítida. Todos quedan en la revisión.',
                style: visual.bodyS.copyWith(
                  fontSize: 10.5,
                  color: visual.inkFaint,
                ),
              ),
            ),
        ],
      ),
    );

    final facts = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('LO QUE LA EXTRACCIÓN AFIRMA', style: visual.overline),
        const SizedBox(height: 9),
        factRow(
          'Rango de fechas',
          dates.isEmpty
              ? '—'
              : '${_ledgerDate(dates.first)} – ${_ledgerDate(dates.last)}',
        ),
        const SizedBox(height: 7),
        factRow(
          'Semanas que cubre',
          weekLabels.isEmpty ? '—' : weekLabels.join(' · '),
        ),
        const SizedBox(height: 7),
        factRow('Egresos leídos', '$outgoing de ${rows.length}'),
        if (incomplete > 0) ...[
          const SizedBox(height: 7),
          factRow(
            'Requieren tu lectura',
            '$incomplete ${incomplete == 1 ? 'línea' : 'líneas'}',
            tone: visual.warning,
          ),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: visual.accentSoft,
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            border: Border.all(color: visual.accentBorder),
          ),
          child: Text(
            'Los abonos se descartan de entrada: un sueldo siempre es '
            'egreso. Aun así quedan visibles en «Otros movimientos» para '
            'que nadie sospeche que se perdió algo.',
            style: visual.bodyS.copyWith(
              fontSize: 10.5,
              height: 1.45,
              color: visual.accent,
            ),
          ),
        ),
      ],
    );

    return ListView(
      key: const PageStorageKey<String>('payroll-reconciliation-extract'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [table, const SizedBox(height: 14), facts],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: table),
                const SizedBox(width: 16),
                SizedBox(width: 320, child: facts),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildApplyStage() {
    final visual = PayrollVisualTokens.of(context);
    return ListView(
      key: const PageStorageKey<String>('payroll-reconciliation-apply'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        // t5-5j: el efectivo vive dentro de Aplicar. La cartola nunca prueba
        // una entrega en mano, así que se pregunta aquí, persona por persona,
        // junto al resumen y al único punto de escritura.
        if (_cashLines.isNotEmpty) ...[
          Text('EFECTIVO · SIEMPRE PREGUNTADO A MANO', style: visual.overline),
          const SizedBox(height: 9),
          _buildCashSection(),
          const SizedBox(height: 18),
        ],
        Row(
          children: [
            Text('RESUMEN ANTES DE ESCRIBIR', style: visual.overline),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nada se escribió todavía; este es el último punto de retorno.',
                style: visual.bodyS.copyWith(
                  fontSize: 10.5,
                  color: visual.inkFaint,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        _buildConfirmSection(),
      ],
    );
  }

  Widget _buildBar() {
    if (_appliedMessage != null) {
      return PayrollMoneyBar(
        figures: [
          PayrollMoneyFigure(
            label: 'Monto registrado',
            amount: _appliedAmountClp,
            isPrimary: true,
          ),
        ],
        primaryAction: PayrollPrimaryAction(
          label: 'Ver semanas y evidencia',
          icon: Icons.receipt_long_outlined,
          onPressed: _closeImmediately,
        ),
      );
    }

    final draft = _draft;
    final blockers = _blockers;
    final decisions = draft == null
        ? const <PayrollStatementReviewDecision>[]
        : _buildDecisions();
    final draftVouchersToCommit = _draftVouchersToCommit(decisions);
    final pendingTotal = _transferRows
        .where((row) =>
            row.requiresDisposition &&
            _dispositionFor(row) == PayrollRowDisposition.pending)
        .fold<int>(
          0,
          (sum, row) => sum + (row.bankAmountClp ?? row.expectedAmountClp ?? 0),
        );
    final readyTotal = decisions
        .where(
          (decision) =>
              decision.kind == PayrollReviewDecisionKind.bankPayment ||
              decision.kind == PayrollReviewDecisionKind.cashPayment ||
              decision.kind == PayrollReviewDecisionKind.advanceAllocation,
        )
        .fold<int>(
          0,
          (sum, decision) => sum + (decision.amountClp ?? 0),
        );

    return PayrollMoneyBar(
      figures: [
        PayrollMoneyFigure(
          label: 'Sin decidir',
          amount: pendingTotal,
          emphasis: true,
          isPrimary: true,
        ),
        PayrollMoneyFigure(
          label: 'Monto reconocido',
          amount: readyTotal,
        ),
      ],
      primaryAction: switch (_stage) {
        PayrollReconciliationStage.file => PayrollPrimaryAction(
            label: 'Continuar',
            onPressed:
                _isBusy || !_canEnterStage(PayrollReconciliationStage.extract)
                    ? null
                    : () => _enterStage(PayrollReconciliationStage.extract),
          ),
        PayrollReconciliationStage.extract => PayrollPrimaryAction(
            label: 'Revisar coincidencias',
            onPressed:
                _isBusy || !_canEnterStage(PayrollReconciliationStage.review)
                    ? null
                    : () => _enterStage(PayrollReconciliationStage.review),
          ),
        PayrollReconciliationStage.review => PayrollPrimaryAction(
            label: 'Ir a aplicar',
            onPressed:
                _isBusy || !_canEnterStage(PayrollReconciliationStage.apply)
                    ? null
                    : () => _enterStage(PayrollReconciliationStage.apply),
          ),
        PayrollReconciliationStage.apply => PayrollPrimaryAction(
            label: draftVouchersToCommit.isEmpty
                ? 'Aplicar conciliación'
                : 'Confirmar ${draftVouchersToCommit.length} '
                    '${draftVouchersToCommit.length == 1 ? 'semana' : 'semanas'} '
                    'y aplicar conciliación',
            icon: Icons.playlist_add_check_rounded,
            busy: _isBusy,
            onPressed: _canApply && !_isBusy ? _apply : null,
          ),
      },
      secondaryAction: PayrollSecondaryAction(
        label: 'Cancelar',
        icon: Icons.close_rounded,
        onPressed: _isBusy ? null : _requestClose,
      ),
      note: switch (_stage) {
        PayrollReconciliationStage.file =>
          _gateNoteFor(PayrollReconciliationStage.extract),
        PayrollReconciliationStage.extract =>
          _gateNoteFor(PayrollReconciliationStage.review),
        PayrollReconciliationStage.review =>
          _gateNoteFor(PayrollReconciliationStage.apply) ??
              _weekImpactNote(decisions),
        PayrollReconciliationStage.apply => !_canApply
            ? (_gateNoteFor(PayrollReconciliationStage.apply) ??
                (blockers.isEmpty
                    ? 'Completa la revisión antes de aplicar.'
                    : blockers.first))
            : null,
      },
    );
  }
}

class _CashCard extends StatelessWidget {
  const _CashCard({
    super.key,
    required this.line,
    required this.answer,
    required this.advances,
    required this.periodLabel,
    required this.actorLabel,
    required this.enabled,
    required this.onChanged,
    required this.onConfirm,
  });

  final PayrollReconciliationLineResult line;
  final _CashAnswer answer;
  final List<EmployeeAdvance> advances;
  final String periodLabel;
  final String actorLabel;
  final bool enabled;
  final VoidCallback onChanged;

  /// Explicit close of this person's answer. Never called automatically.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = PayrollVisualTokens.of(context);
    final name = line.employee?.displayName ?? 'Persona sin ficha';
    final pending = line.voucherLine.pendingAmountClp.toDouble();
    double selectedAdvanceAmount() {
      var remaining = pending;
      var total = 0.0;
      for (final advance in advances) {
        if (!answer.selectedAdvanceIds.contains(advance.id)) continue;
        if (remaining <= 0.01) break;
        final applied = advance.availableAmount > remaining
            ? remaining
            : advance.availableAmount;
        total += applied;
        remaining -= applied;
      }
      return total;
    }

    void fillCashRemainder() {
      answer.amount = (pending - selectedAdvanceAmount()).clamp(0.0, pending);
    }

    final advanceApplied = answer.disposition == _CashDisposition.cashPayment
        ? selectedAdvanceAmount()
        : 0.0;
    final cashGiven = answer.disposition == _CashDisposition.cashPayment
        ? (answer.amount ?? 0)
        : 0.0;
    final rest = (pending - advanceApplied - cashGiven).clamp(0.0, pending);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.accent, width: 1.5),
        boxShadow: visual.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            '$periodLabel · Monto esperado '
            '${formatPayrollClp(line.voucherLine.pendingAmountClp)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: visual.warningFg,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Efectivo manual · esta respuesta no proviene del OCR '
                  'de la cartola',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 15,
                color: visual.inkFaint,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Registrará: $actorLabel · identidad autenticada del servidor',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          // One equation per person: what was owed, what covers it, what
          // remains. It updates live with the chosen disposition.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              'Pendiente ${formatPayrollClp(pending)} − '
              'Anticipo ${formatPayrollClp(advanceApplied)} − '
              'Efectivo ${formatPayrollClp(cashGiven)} = '
              'Resto ${formatPayrollClp(rest)}',
              style: payrollMoneyTextStyle(context).copyWith(fontSize: 13.5),
            ),
          ),
          const SizedBox(height: 11),
          Text(
            '¿Cómo quedó esta obligación?',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final visual = PayrollVisualTokens.of(context);
              final cards = <Widget>[
                PayrollDecisionOptionCard(
                  title: 'Todavía no pagado',
                  description:
                      'La obligación queda pendiente; nada se registra.',
                  tag: 'sin pago',
                  tone: visual.warning,
                  selected: answer.disposition == _CashDisposition.notPaid,
                  onSelect: enabled
                      ? () {
                          answer.disposition = _CashDisposition.notPaid;
                          onChanged();
                        }
                      : null,
                ),
                PayrollDecisionOptionCard(
                  title: 'Entregué efectivo',
                  description: 'Registra la entrega manual de esta persona y '
                      'semana; nunca se infiere de la cartola.',
                  tag: 'crea pago',
                  tone: visual.success,
                  selected: answer.disposition == _CashDisposition.cashPayment,
                  onSelect: enabled
                      ? () {
                          answer.disposition = _CashDisposition.cashPayment;
                          fillCashRemainder();
                          onChanged();
                        }
                      : null,
                ),
              ];
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [cards[0], const SizedBox(height: 8), cards[1]],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[1]),
                ],
              );
            },
          ),
          if (answer.disposition == _CashDisposition.cashPayment &&
              advances.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Anticipos disponibles (opcional)',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'puedes aplicar varios. Se aplican por fecha y el efectivo se '
              'ajusta al saldo restante.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 5),
            for (final advance in advances)
              CheckboxListTile(
                key: ValueKey('cash-advance-${advance.id}'),
                value: answer.selectedAdvanceIds.contains(advance.id),
                onChanged: enabled
                    ? (selected) {
                        if (selected == true) {
                          answer.selectedAdvanceIds.add(advance.id);
                        } else {
                          answer.selectedAdvanceIds.remove(advance.id);
                        }
                        fillCashRemainder();
                        onChanged();
                      }
                    : null,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Anticipo del ${formatPayrollDate(advance.paidCivilDate)}',
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: Text(
                  'Disponible ${formatPayrollClp(advance.availableAmount)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
          if (answer.disposition == _CashDisposition.cashPayment) ...[
            const SizedBox(height: 12),
            if (advanceApplied >= pending - 0.01)
              const _Notice(
                message: 'Los anticipos seleccionados cubren todo el saldo. '
                    'No se registrará efectivo nuevo.',
              )
            else
              _CashPaymentFields(
                line: line,
                answer: answer,
                enabled: enabled,
                onChanged: onChanged,
              ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                child: PayrollAccentAction(
                  label: 'Confirmar respuesta',
                  icon: Icons.check_rounded,
                  onTap: onConfirm,
                  enabled: enabled && answer.isAnswered,
                  height: PayrollMoneyBar.minimumTouchTarget,
                  fontSize: 13,
                  horizontalPadding: 16,
                  disabledStyle: PayrollAccentDisabledStyle.neutral,
                ),
              ),
              if (!answer.isAnswered) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Elige una opción para poder confirmar.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CashPaymentFields extends StatelessWidget {
  const _CashPaymentFields({
    required this.line,
    required this.answer,
    required this.enabled,
    required this.onChanged,
  });

  final PayrollReconciliationLineResult line;
  final _CashAnswer answer;
  final bool enabled;
  final VoidCallback onChanged;

  Future<void> _pickDate(BuildContext context) async {
    // Cash may be confirmed from the start of the work week: a mid-week
    // handover is normal and must carry its true date.
    final periodStart = line.voucherLine.periodStart;
    final firstDate = DateTime(
      periodStart.year,
      periodStart.month,
      periodStart.day,
    );
    final now = DateTime.now();
    final lastDate = DateTime(now.year, now.month, now.day);
    final initialDate =
        answer.date.isBefore(firstDate) ? firstDate : answer.date;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(lastDate) ? lastDate : initialDate,
      firstDate: firstDate.isAfter(lastDate) ? lastDate : firstDate,
      lastDate: lastDate,
    );
    if (picked != null) {
      answer.date = picked;
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final amountField = TextFormField(
      key: const ValueKey('cash-manual-amount'),
      initialValue: (answer.amount ?? 0).round().toString(),
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      enabled: enabled,
      inputFormatters: const [ClpAmountInputFormatter()],
      decoration: const InputDecoration(
        labelText: 'Monto entregado',
        prefixText: '\$ ',
        isDense: true,
      ),
      onChanged: (value) {
        answer.amount = parsePayrollAmount(value);
        onChanged();
      },
    );
    final dateField = Semantics(
      button: true,
      enabled: enabled,
      label: 'Fecha de entrega de efectivo. ${formatPayrollDate(answer.date)}',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('cash-manual-date'),
        onTap: enabled ? () => _pickDate(context) : null,
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: PayrollMoneyBar.minimumTouchTarget,
          ),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Fecha de entrega',
              isDense: true,
            ),
            child: Text(formatPayrollDate(answer.date)),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            children: [
              amountField,
              const SizedBox(height: 10),
              dateField,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: amountField),
            const SizedBox(width: 10),
            Expanded(child: dateField),
          ],
        );
      },
    );
  }
}

/// One person of the cash progress list: state at a glance, tap to answer or
/// change. Switching people is always the operator's tap.
class _CashPersonTile extends StatelessWidget {
  const _CashPersonTile({
    required this.line,
    required this.answer,
    required this.advanceAmount,
    required this.periodLabel,
    required this.isFirst,
    required this.isActive,
    required this.enabled,
    required this.onTap,
  });

  final PayrollReconciliationLineResult line;
  final _CashAnswer? answer;
  final double advanceAmount;
  final String periodLabel;
  final bool isFirst;
  final bool isActive;
  final bool enabled;
  final VoidCallback onTap;

  String get _stateLabel {
    final current = answer;
    if (current == null || !current.isAnswered) return 'Sin responder';
    return switch (current.disposition) {
      _CashDisposition.notPaid => 'Todavía no pagado',
      _CashDisposition.cashPayment => switch ((
          advanceAmount > 0.01,
          (current.amount ?? 0) > 0.01
        )) {
          (true, true) => 'Anticipos ${formatPayrollClp(advanceAmount)} + '
              'efectivo ${formatPayrollClp(current.amount ?? 0)} · '
              '${formatPayrollDate(current.date)}',
          (true, false) =>
            'Anticipos aplicados ${formatPayrollClp(advanceAmount)}',
          (false, _) => 'Efectivo ${formatPayrollClp(current.amount ?? 0)} · '
              '${formatPayrollDate(current.date)}',
        },
      _CashDisposition.pending => 'Sin responder',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = PayrollVisualTokens.of(context);
    final name = line.employee?.displayName ?? 'Persona sin ficha';
    final isAnswered = answer?.isAnswered ?? false;
    final expected = formatPayrollClp(line.voucherLine.pendingAmountClp);
    final actionLabel = isAnswered ? 'Revisar' : 'Responder';

    return Semantics(
      button: true,
      selected: isActive,
      enabled: enabled,
      label: '$name. Pago en efectivo manual; no se obtiene de la cartola. '
          '$periodLabel. Monto esperado $expected. '
          'Estado: $_stateLabel. $actionLabel.',
      excludeSemantics: true,
      child: Material(
        color: isActive
            ? theme.colorScheme.surfaceContainerHighest
            : visual.surface.withValues(alpha: 0),
        child: InkWell(
          onTap: enabled ? onTap : null,
          mouseCursor:
              enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: PayrollMoneyBar.minimumTouchTarget,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: isFirst
                    ? BorderSide.none
                    : BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 600;
                final statusStyle = theme.textTheme.labelSmall?.copyWith(
                  color: isAnswered
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                );
                final methodAndWeek = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: visual.warningFg,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Efectivo manual · $periodLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                );

                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isAnswered
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: isAnswered
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'ESPERADO',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 9,
                                  letterSpacing: 0.7,
                                ),
                              ),
                              Text(
                                expected,
                                style: payrollMoneyTextStyle(context)
                                    .copyWith(fontSize: 13.5),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      methodAndWeek,
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _stateLabel,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: statusStyle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            actionLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    Icon(
                      isAnswered
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: isAnswered
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          methodAndWeek,
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Monto esperado',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            expected,
                            style: payrollMoneyTextStyle(context)
                                .copyWith(fontSize: 13.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 3,
                      child: Text(
                        _stateLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: statusStyle,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      actionLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Collapsible review group of stage 2 with an answered/total counter. The
/// grouping is presentation only: every row keeps its own individual
/// decision, and named obligations never receive a mass action.
/// Nota de lectura bajo la tabla de revisión (Design t5 · 5j paso 3): explica
/// el criterio, no repite la fila.
class _ReviewNote extends StatelessWidget {
  const _ReviewNote({
    required this.tone,
    required this.title,
    required this.body,
  });

  final PayrollStateTone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.soft,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: tone.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: visual.labelStrong.copyWith(fontSize: 11, color: tone.fg),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: visual.bodyS.copyWith(
              fontSize: 10.5,
              height: 1.45,
              color: tone.fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: visual.surfaceSunken,
        borderRadius: BorderRadius.circular(PayrollTokens.rPill),
        border: Border.all(color: visual.border),
      ),
      child: Text(
        label,
        style: visual.monoS.copyWith(color: visual.inkMuted),
      ),
    );
  }
}

class _PreparationProgress extends StatelessWidget {
  const _PreparationProgress({required this.progress});

  final PayrollStatementPreparationProgress progress;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final label = switch (progress.phase) {
      PayrollStatementPreparationPhase.validatingFile =>
        'Validando el archivo…',
      PayrollStatementPreparationPhase.readingPdfPage =>
        _pageLabel('Leyendo', progress),
      PayrollStatementPreparationPhase.preparingScannedPdf =>
        'Preparando las páginas del PDF escaneado…',
      PayrollStatementPreparationPhase.recognizingPdfPage =>
        _pageLabel('Reconociendo', progress),
      PayrollStatementPreparationPhase.recognizingImage =>
        'Reconociendo la imagen en este dispositivo…',
      PayrollStatementPreparationPhase.parsingMovements =>
        'Interpretando los movimientos…',
      PayrollStatementPreparationPhase.loadingPayrollContext =>
        'Cargando semanas y métodos de pago…',
    };

    return Semantics(
      key: const ValueKey('payroll-extraction-progress'),
      label: label,
      liveRegion: true,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          children: [
            Text(
              label,
              key: const ValueKey('payroll-extraction-progress-label'),
              textAlign: TextAlign.center,
              style: visual.bodyS.copyWith(
                color: visual.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(value: progress.fraction),
          ],
        ),
      ),
    );
  }

  static String _pageLabel(
    String verb,
    PayrollStatementPreparationProgress progress,
  ) {
    final page = progress.pageNumber;
    final total = progress.pageCount;
    if (page == null || total == null) return '$verb páginas…';
    return '$verb página $page de $total…';
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({
    required this.label,
    required this.available,
    this.unavailableLabel = 'No disponible aquí',
  });

  final String label;
  final bool available;
  final String unavailableLabel;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final foreground = available ? visual.successFg : visual.inkFaint;
    final background = available ? visual.successSoft : visual.surfaceSunken;
    final border = available ? visual.successBorder : visual.border;
    final stateLabel = available ? 'Disponible' : unavailableLabel;

    return Semantics(
      label: '$label. $stateLabel.',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PayrollTokens.rPill),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              available ? Icons.check_rounded : Icons.remove_rounded,
              size: 14,
              color: foreground,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '$label · $stateLabel',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: visual.bodyS.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptIdentifier extends StatelessWidget {
  const _ReceiptIdentifier({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: visual.bodyS.copyWith(
              color: visual.inkFaint,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            value,
            style: visual.monoS.copyWith(
              color: visual.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _DraftCommitmentPanel extends StatelessWidget {
  const _DraftCommitmentPanel({required this.vouchers});

  final List<PayrollVoucher> vouchers;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final count = vouchers.length;
    return Container(
      key: const ValueKey('payroll-draft-commitment-summary'),
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: visual.accentSoft,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.accentBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 18,
                color: visual.accent,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'También se ${count == 1 ? 'confirmará' : 'confirmarán'} '
                      '$count ${count == 1 ? 'semana borrador' : 'semanas borrador'}',
                      style: visual.cardTitle.copyWith(
                        color: visual.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Ese paso reconoce sus sueldos por pagar antes de '
                      'registrar los pagos de esta conciliación.',
                      style: visual.bodyS.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < vouchers.length; index++) ...[
            if (index > 0) Divider(height: 13, color: visual.accentBorder),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _labelFor(vouchers[index]),
                    style: visual.labelStrong,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatPayrollClp(_positiveObligationTotal(vouchers[index])),
                  style: visual.monoM.copyWith(
                    color: visual.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _labelFor(PayrollVoucher voucher) {
    final label = voucher.periodLabel?.trim() ?? '';
    if (label.isNotEmpty) return label;
    final start = voucher.periodStart;
    final end = voucher.periodEnd;
    String compact(DateTime value) {
      return '${value.day.toString().padLeft(2, '0')}/'
          '${value.month.toString().padLeft(2, '0')}';
    }

    return '${compact(start)}–${compact(end)}';
  }

  int _positiveObligationTotal(PayrollVoucher voucher) {
    return voucher.lines
        .where((line) => line.isIncluded && line.totalAmount > 0)
        .fold<double>(0, (sum, line) => sum + line.totalAmount)
        .round();
  }
}

class _ConfirmationRow extends StatelessWidget {
  const _ConfirmationRow({
    required this.item,
    required this.isFirst,
  });

  final _ConfirmationItem item;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          top: isFirst
              ? BorderSide.none
              : BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.subtitle} · ${item.action}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (item.accountLabel case final account?) ...[
                  const SizedBox(height: 3),
                  Text(
                    account,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            formatPayrollClp(item.amountClp),
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingPaymentMethodsPanel extends StatelessWidget {
  const _MissingPaymentMethodsPanel({
    required this.employees,
    required this.enabled,
    required this.onConfigure,
  });

  final List<({String id, String name})> employees;
  final bool enabled;
  final ValueChanged<String> onConfigure;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: visual.warningSoft,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.warningBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  size: 19,
                  color: visual.warningFg,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Falta definir cómo se paga',
                        style: visual.labelStrong.copyWith(
                          color: visual.warningFg,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Configura cada ficha y vuelve aquí. La cartola y las '
                        'decisiones válidas permanecerán abiertas.',
                        style: visual.bodyS.copyWith(
                          color: visual.warningFg,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < employees.length; index++)
            Container(
              constraints: const BoxConstraints(
                minHeight: PayrollMoneyBar.minimumTouchTarget,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: visual.surface,
                border: Border(
                  top: BorderSide(
                    color: index == 0 ? visual.warningBorder : visual.border,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employees[index].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: visual.bodyM.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Sin método activo con cuenta contable',
                          style: visual.bodyS.copyWith(
                            color: visual.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    key: ValueKey(
                      'payroll-reconciliation-configure-method-'
                      '${employees[index].id}',
                    ),
                    onPressed:
                        enabled ? () => onConfigure(employees[index].id) : null,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(
                        0,
                        PayrollMoneyBar.minimumTouchTarget,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Configurar'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.message,
    this.isError = false,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool isError;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: isError ? visual.dangerSoft : visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(
          color: isError ? visual.dangerBorder : visual.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 19,
            color: isError ? visual.dangerFg : visual.accent,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: visual.bodyS.copyWith(
                color: isError ? visual.dangerFg : visual.inkMuted,
                height: 1.35,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
