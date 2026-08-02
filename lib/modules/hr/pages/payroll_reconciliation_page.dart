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
import '../../../shared/utils/responsive_breakpoints.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/vb_short_select.dart';
import '../services/payroll_statement_capture_cleanup.dart';
import '../services/payroll_statement_extraction_service.dart';
import '../services/payroll_statement_local_image_ocr.dart';
import '../services/payroll_voucher_service.dart';
import '../widgets/payroll_format.dart';
import '../widgets/payroll_money_bar.dart';
import '../widgets/payroll_payment_sheet.dart'
    show ClpAmountInputFormatter, parsePayrollAmount;
import '../widgets/payroll_reconciliation_row.dart';
import '../../../shared/widgets/vb_money_text.dart';
import '../../../shared/widgets/vb_notice.dart';

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

/// Los cuatro pasos, con las palabras de Design `7c`.
///
/// **Corrige el wording del 2026-07-30** (`Subir cartola · Extraer · Revisar`).
/// Adjudicado el 2026-08-01: **`Cargar`** y no «subir», porque el archivo se
/// procesa **en el equipo** y no viaja a ningún servidor —decir «subir» describe
/// algo que no pasa—; **`Lectura`** porque el paso 2 muestra lo que el OCR leyó,
/// no una acción del operador; y **`Propuestas`** porque el paso 3 contiene
/// propuestas de pago que se aceptan o se cambian, que es más preciso que el
/// «revisar» genérico que este ERP usa en otros seis módulos.
extension _StageCopy on PayrollReconciliationStage {
  String get label => switch (this) {
        PayrollReconciliationStage.file => 'Cargar cartola',
        PayrollReconciliationStage.extract => 'Lectura',
        PayrollReconciliationStage.review => 'Propuestas',
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

/// 5j paso 4 · una fila de «IMPACTO POR SEMANA».
///
/// El frame dibuja `antes → después` con el rótulo `falta pagar`. Las dos
/// cifras son **derivables** y por eso la columna existe: `antes` es la suma de
/// `pendingAmountClp` de las líneas de esa semana en la reconciliación
/// preparada, y `después` es esa suma menos lo que las decisiones de dinero de
/// esta cartola van a saldar. Nada de esto pregunta al servidor: el borrador ya
/// trae el saldo por línea.
@immutable
class _WeekImpact {
  const _WeekImpact({
    required this.voucherId,
    required this.weekLabel,
    required this.beforeClp,
    required this.appliedClp,
    required this.transferCount,
    required this.cashCount,
    required this.advanceCount,
    required this.partialCount,
  });

  final String voucherId;
  final String weekLabel;

  /// Lo que faltaba pagar en esa semana antes de aplicar esta cartola.
  final int beforeClp;

  /// Lo que esta cartola va a saldar en esa semana.
  final int appliedClp;

  final int transferCount;
  final int cashCount;
  final int advanceCount;
  final int partialCount;

  /// Nunca negativo: el cliente ya acota cada decisión al saldo de su línea
  /// (`min(banco, esperado)` en las transferencias, el saldo pendiente en el
  /// efectivo), así que un `después` bajo cero sería un defecto de cálculo, no
  /// un estado del negocio. Se acota igual para que la pantalla no pueda
  /// mostrar un número imposible.
  int get afterClp => beforeClp - appliedClp < 0 ? 0 : beforeClp - appliedClp;

  int get movementCount => transferCount + cashCount + advanceCount;
}

/// 5j paso 4 · el resumen que se muestra **antes** de escribir.
///
/// Cada campo tiene una fuente comprobable en `apply`. Lo que el frame dibuja y
/// esta clase **no** tiene es deliberado, no un olvido:
///
/// - **`Gasto a Contabilidad`** no existe. `payroll_statement_decisions` admite
///   siete acciones —`bank_payment`, `cash_payment`, `advance_allocation`,
///   `not_paid`, `ignore`, `hold`, `already_resolved`— y ninguna crea un gasto
///   en Contabilidad. Mostrar esa fila sería afirmar un asiento que nunca
///   ocurre.
/// - **`Omitidos por duplicado`** se convirtió en [alreadyResolvedCount], que
///   cuenta sólo `already_resolved`. `PayrollRowDisposition.ignore` se rotula
///   «Error o duplicado» y **mezcla las dos cosas**: contarlo como duplicado
///   diría que hubo una repetición donde pudo haber una lectura errónea.
@immutable
class _ApplySummary {
  const _ApplySummary({
    required this.paymentCount,
    required this.partialCount,
    required this.partialAmountClp,
    required this.advanceCount,
    required this.advanceAmountClp,
    required this.alreadyResolvedCount,
    required this.operatorExcludedCount,
    required this.totalClp,
  });

  /// Transferencias + efectivo. Un anticipo **no** es un pago que se crea:
  /// consume saldo que ya era del trabajador.
  final int paymentCount;

  /// Subconjunto de [paymentCount]: pagos con `variance_disposition = partial`.
  /// El RPC posta exactamente el monto del banco y deja el resto abierto.
  final int partialCount;
  final int partialAmountClp;

  final int advanceCount;
  final int advanceAmountClp;

  /// Filas que una importación anterior ya resolvió. Es la **única** señal de
  /// repetición que el modelo distingue.
  final int alreadyResolvedCount;

  /// Sólo lo que el operador excluyó **a mano**. Los descartes automáticos —un
  /// abono, una fila sin salida bancaria— no son decisiones suyas y contarlos
  /// acá le atribuiría un criterio que no aplicó.
  final int operatorExcludedCount;

  /// Todo lo que reduce lo que falta pagar: transferencias, efectivo y
  /// anticipos. Es el mismo conjunto que la barra de dinero llama «Monto
  /// reconocido», a propósito: dos cifras distintas para lo mismo es como se
  /// pierde la confianza en una pantalla de dinero.
  final int totalClp;
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
    // **El selector se espera FUERA del estado ocupado.** Antes la etapa
    // entraba en `Validando el archivo…` en el instante en que se abría el
    // panel del sistema, y eso era falso por partida doble: no se estaba
    // validando nada —el operador todavía estaba eligiendo— y, si el panel no
    // devolvía nunca, la etapa se quedaba ahí **para siempre** con `Cancelar`
    // deshabilitado por `_isBusy`. Visto en vivo el 2026-08-01: un panel que
    // el sistema dejó sin responder obligó a matar la sesión.
    //
    // El panel del sistema ya es modal a nivel de SO, así que no hace falta
    // bloquear la pantalla por debajo mientras está abierto.
    final PayrollPickedStatement? picked;
    try {
      picked = await picker();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos abrir el selector de archivos. Intenta de nuevo.';
        _errorRecoveryAction = PayrollReconciliationRecoveryAction.none;
        _canRetrySameOperation = true;
      });
      _logFailure('Falla al abrir el selector de cartola', error);
      return;
    }
    if (picked == null || !mounted) return;

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
      PayrollReconciliationStage.file => 'Cargar cartola',
      PayrollReconciliationStage.extract => 'Lectura de la cartola',
      PayrollReconciliationStage.review => 'Propuestas de pago',
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
      'Cargar',
      'Lectura',
      'Propuestas',
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

  /// Mapa línea → semana del borrador. Varias decisiones (efectivo, anticipos,
  /// «no pagado») traen `voucherId`, pero una transferencia reasignada a mano
  /// puede traer sólo la línea: sin este mapa esa decisión se caería del
  /// impacto por semana y la columna mostraría menos de lo que se va a escribir.
  Map<String, String> _voucherIdByLineId() {
    final draft = _draft;
    if (draft == null) return const <String, String>{};
    return <String, String>{
      for (final voucher in draft.vouchers)
        if (voucher.id case final voucherId?)
          for (final line in voucher.lines)
            if (line.id case final lineId?) lineId: voucherId,
    };
  }

  bool _isMoneyDecision(PayrollStatementReviewDecision decision) =>
      decision.kind == PayrollReviewDecisionKind.bankPayment ||
      decision.kind == PayrollReviewDecisionKind.cashPayment ||
      decision.kind == PayrollReviewDecisionKind.advanceAllocation;

  /// 5j paso 4 · columna «IMPACTO POR SEMANA».
  ///
  /// Sólo aparecen las semanas que esta cartola **toca con dinero**: una semana
  /// cuya única decisión es «todavía no pagado» no cambia de saldo, y ponerla
  /// acá sugeriría un impacto que no existe.
  List<_WeekImpact> _weekImpacts(
    List<PayrollStatementReviewDecision> decisions,
  ) {
    final draft = _draft;
    if (draft == null) return const <_WeekImpact>[];
    final voucherIdByLineId = _voucherIdByLineId();

    final beforeByVoucher = <String, int>{};
    for (final result in draft.reconciliation.lineResults) {
      final line = result.voucherLine;
      beforeByVoucher.update(
        line.voucherId,
        (value) => value + line.pendingAmountClp,
        ifAbsent: () => line.pendingAmountClp,
      );
    }

    final applied = <String, int>{};
    final transfers = <String, int>{};
    final cash = <String, int>{};
    final advances = <String, int>{};
    final partials = <String, int>{};
    for (final decision in decisions) {
      if (!_isMoneyDecision(decision)) continue;
      final voucherId = decision.voucherId ??
          (decision.voucherLineId == null
              ? null
              : voucherIdByLineId[decision.voucherLineId]);
      if (voucherId == null) continue;
      applied.update(
        voucherId,
        (value) => value + (decision.amountClp ?? 0),
        ifAbsent: () => decision.amountClp ?? 0,
      );
      switch (decision.kind) {
        case PayrollReviewDecisionKind.bankPayment:
          transfers.update(voucherId, (v) => v + 1, ifAbsent: () => 1);
          if (decision.varianceDisposition ==
              PayrollVarianceDisposition.partial) {
            partials.update(voucherId, (v) => v + 1, ifAbsent: () => 1);
          }
        case PayrollReviewDecisionKind.cashPayment:
          cash.update(voucherId, (v) => v + 1, ifAbsent: () => 1);
        case PayrollReviewDecisionKind.advanceAllocation:
          advances.update(voucherId, (v) => v + 1, ifAbsent: () => 1);
        case _:
          break;
      }
    }

    final impacts = <_WeekImpact>[
      for (final entry in applied.entries)
        _WeekImpact(
          voucherId: entry.key,
          weekLabel: _periodLabelFor(entry.key),
          beforeClp: beforeByVoucher[entry.key] ?? 0,
          appliedClp: entry.value,
          transferCount: transfers[entry.key] ?? 0,
          cashCount: cash[entry.key] ?? 0,
          advanceCount: advances[entry.key] ?? 0,
          partialCount: partials[entry.key] ?? 0,
        ),
    ]..sort((left, right) => left.weekLabel.compareTo(right.weekLabel));
    return List<_WeekImpact>.unmodifiable(impacts);
  }

  /// 5j paso 4 · panel «RESUMEN ANTES DE ESCRIBIR».
  _ApplySummary _applySummary(
    List<PayrollStatementReviewDecision> decisions,
  ) {
    var paymentCount = 0;
    var partialCount = 0;
    var partialAmountClp = 0;
    var advanceCount = 0;
    var advanceAmountClp = 0;
    var alreadyResolvedCount = 0;
    var totalClp = 0;

    for (final decision in decisions) {
      final amount = decision.amountClp ?? 0;
      switch (decision.kind) {
        case PayrollReviewDecisionKind.bankPayment:
          paymentCount++;
          totalClp += amount;
          if (decision.varianceDisposition ==
              PayrollVarianceDisposition.partial) {
            partialCount++;
            partialAmountClp += amount;
          }
        case PayrollReviewDecisionKind.cashPayment:
          paymentCount++;
          totalClp += amount;
        case PayrollReviewDecisionKind.advanceAllocation:
          advanceCount++;
          advanceAmountClp += amount;
          totalClp += amount;
        case PayrollReviewDecisionKind.alreadyResolved:
          alreadyResolvedCount++;
        case _:
          break;
      }
    }

    // «Excluidos por ti» se cuenta sobre las filas, no sobre las decisiones, y
    // sólo cuando el operador tocó la fila: `_dispositions` guarda exactamente
    // sus elecciones explícitas. Un descarte automático —un abono, una fila sin
    // salida bancaria— produce la misma decisión `ignore` y no es suyo.
    var operatorExcludedCount = 0;
    for (final row in _transferRows) {
      if (!_dispositions.containsKey(row.id)) continue;
      switch (_dispositionFor(row)) {
        case PayrollRowDisposition.ignore:
        case PayrollRowDisposition.notPayroll:
        case PayrollRowDisposition.hold:
          operatorExcludedCount++;
        case _:
          break;
      }
    }

    return _ApplySummary(
      paymentCount: paymentCount,
      partialCount: partialCount,
      partialAmountClp: partialAmountClp,
      advanceCount: advanceCount,
      advanceAmountClp: advanceAmountClp,
      alreadyResolvedCount: alreadyResolvedCount,
      operatorExcludedCount: operatorExcludedCount,
      totalClp: totalClp,
    );
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
                        // Va ARRIBA, antes de la zona de carga: quien no va a
                        // poder aplicar tiene que saberlo **antes** de elegir un
                        // archivo, no después de bajar el scroll. Estaba al pie
                        // y mi propio cambio lo empujó fuera de la primera
                        // pantalla — el test lo destapó, pero el defecto era de
                        // orden, no de la prueba.
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
                  const SizedBox(height: 14),
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
                    'Carga la cartola',
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
                  Text(
                    // El límite lo publica el extractor, no el frame: `5j` dibuja
                    // «hasta 20 MB» y el código rechaza sobre **12**. Decirlo
                    // antes ahorra elegir un archivo que va a fallar.
                    'Hasta 12 MB. Al aplicar se guarda evidencia estructurada; '
                    'no se conserva la imagen ni el texto OCR completo.',
                    textAlign: TextAlign.center,
                    style: visual.bodyS.copyWith(
                      color: visual.inkFaint,
                      height: 1.35,
                    ),
                  ),
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
                  const SizedBox(height: PayrollTokens.gapBlocks),
                  // 5j paso 1: Design reemplaza los tres chips por tres
                  // tarjetas que dicen **qué esperar de cada fuente**, que es
                  // la decisión que el operador toma acá. Se copia esa
                  // composición —y su POSICIÓN: el frame las dibuja **debajo**
                  // de los botones, no encima. Ponerlas arriba empujaba
                  // `Elegir archivo` fuera de la primera pantalla en teléfono,
                  // que es donde más se usa la cámara. El texto se ancla a lo
                  // que el extractor hace de verdad — compuerta en el ledger.
                  _SourceExpectations(
                    supportsImages: supportsImages,
                    supportsCapture: supportsCapture,
                  ),
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
      onPrevious: index > 0 ? () => _moveQuestion(pending, index, -1) : null,
      // **`Siguiente` sigue activo en la última pregunta si ésta ya quedó
      // resuelta**, porque ahí lo que hace es soltarla. Con el guard anterior
      // (`index < pending.length - 1`) el operador quedaba clavado en la
      // última tarjeta respondida, sin forma de sacarla de la pila.
      onNext: index < pending.length - 1 || _releasesOnAdvance(row)
          ? () => _moveQuestion(pending, index, 1)
          : null,
      child: _reviewRow(row, isFirst: true),
    );
  }

  /// Una fila respondida «en el sitio» que ya no le debe nada a nadie: tiene
  /// disposición y, si trae diferencia o exige razón de auditoría, las dos
  /// están resueltas. Mientras le falte algo se queda en la pregunta abierta
  /// **a propósito**, que es lo que el comentario de `_setDisposition` promete.
  bool _releasesOnAdvance(PayrollDecisionRowData row) {
    if (!_answeredInPlaceRowIds.contains(row.id)) return false;
    final disposition = _dispositionFor(row);
    if (disposition == PayrollRowDisposition.pending) return false;
    if (disposition != PayrollRowDisposition.confirm) return true;
    if (row.hasVariance &&
        _varianceFor(row) == PayrollVarianceDisposition.none) {
      return false;
    }
    if (row.needsReviewReason && _reviewReasonFor(row).isEmpty) return false;
    return true;
  }

  /// Mueve la pregunta abierta **soltando la que se deja atrás**.
  ///
  /// El contrato lo escribió el propio código al responder: *«Answering does
  /// not make the question vanish… It leaves only on "next question".»* Pero
  /// esto sólo hacía `_pendingQuestionIndex += delta` y **nunca sacaba la fila
  /// de `_answeredInPlaceRowIds`**, así que la promesa no se cumplía: la
  /// tarjeta ya respondida seguía rotulada «Pendiente de decisión», el contador
  /// no bajaba nunca de `N DE 10`, y para llegar a una sin responder había que
  /// recorrer la lista entera — y al topar con la última, caminar hacia atrás.
  /// Medido recorriendo las 10 decisiones en la app viva el 2026-08-01.
  void _moveQuestion(
    List<PayrollDecisionRowData> pending,
    int index,
    int delta,
  ) {
    setState(() {
      final leaving =
          index >= 0 && index < pending.length ? pending[index] : null;
      // **El id «en revisión» se limpia en TODA navegación**, no sólo cuando
      // la fila se suelta. `_stagedQuestionRowId` manda sobre el índice al
      // elegir qué tarjeta encabeza la etapa, así que dejarlo puesto hacía que
      // la flecha moviera el índice y la pantalla siguiera mostrando la misma
      // tarjeta: para el operador, la flecha no hacía nada.
      if (leaving != null && _stagedQuestionRowId == leaving.id) {
        _stagedQuestionRowId = null;
      }
      // **Sólo `Siguiente` suelta la fila.** El contrato dice «It leaves only
      // on "next question"», y `Anterior` existe justamente para volver a
      // mirar lo que se acaba de decidir: si retroceder también la sacara de
      // la pila, volver sería imposible.
      final releases =
          delta > 0 && leaving != null && _releasesOnAdvance(leaving);
      if (releases) {
        _answeredInPlaceRowIds.remove(leaving.id);
        // La lista se acorta justo en esta posición y la siguiente ocupa el
        // hueco, así que el índice se queda donde está.
        _pendingQuestionIndex = index;
      } else {
        // **`index + delta`, no `+= delta`.** El índice que llega es el
        // EFECTIVO —el que la tarjeta está mostrando— y puede venir de
        // `stagedIndex`, que no tiene por qué coincidir con
        // `_pendingQuestionIndex`. Sumar sobre el guardado saltaba a una fila
        // distinta de la que el operador tenía delante.
        _pendingQuestionIndex = index + delta;
      }
      final remaining = releases ? pending.length - 1 : pending.length;
      _pendingQuestionIndex =
          remaining <= 0 ? 0 : _pendingQuestionIndex.clamp(0, remaining - 1);
    });
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
          // **`S-05` a través de [VbShortSelect]**, no un `DropdownButton` con
          // estilo propio. El techo de la guía se cumple con margen: medido en
          // producción el 2026-08-01, **ningún tenant tiene más de UNA** cuenta
          // ERP distinta con método de transferencia activo. Si algún día
          // pasara de siete, el `assert` del owner lo dice y el componente
          // correcto pasa a ser S-06 — no un S-05 más alto.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              VbShortSelect<String?>(
                key: const ValueKey('payroll-statement-erp-account'),
                value: _selectedErpAccountId,
                label: 'Cuenta ERP de esta cartola',
                sheetTitle: 'Cuenta ERP de esta cartola',
                semanticLabel: 'Cuenta ERP de esta cartola',
                placeholder: 'Elegir cuenta',
                options: [
                  for (final option in _bankAccountOptions)
                    VbShortSelectOption<String?>(
                      value: option.accountId,
                      label: option.label,
                    ),
                ],
                onChanged: _isReviewLocked
                    ? null
                    : (value) => setState(() {
                          _selectedErpAccountId = value;
                          _error = null;
                        }),
              ),
              const SizedBox(height: 5),
              // El texto de apoyo no es parte de S-05, así que lo pone el
              // llamador: dice algo real de esta pantalla, no del control.
              Text(
                'Se usará la misma cuenta para todos los pagos bancarios.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
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
                  // `7c` encabeza la tabla con sus rótulos de columna. Va sobre
                  // el grupo de calces, que es el que la tabla dibuja.
                  const PayrollReviewColumnHeader(),
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
              if (constraints.maxWidth < ResponsiveBreakpoints.desktopMin) {
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
        if (lines.isEmpty)
          const VbNotice(
            tone: VbNoticeTone.neutral,
            title: 'Nadie de esta nómina cobra en efectivo',
          )
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
            const VbNotice(
              tone: VbNoticeTone.success,
              title: 'Todas las personas en efectivo tienen respuesta',
              body: 'Puedes tocar a cualquiera para cambiarla, o seguir al '
                  'resumen.',
            ),
          ],
          const SizedBox(height: 14),
          // Copy del frame 5j paso 4, comprobada contra el código antes de
          // copiarla: `_canApply` exige `_cashStageIsComplete`, así que una
          // persona en efectivo sin responder bloquea de verdad la aplicación
          // entera —y con ella la confirmación de la semana—. La frase se puede
          // sostener porque el gate existe, no porque el frame la dibuje.
          VbNotice(
            key: const ValueKey<String>('payroll-reconciliation-cash-policy'),
            tone: unanswered.isEmpty
                ? VbNoticeTone.neutral
                : VbNoticeTone.warning,
            title: 'La cartola nunca prueba un pago en efectivo',
            body: 'Si queda sin responder, la semana no se puede confirmar, y '
                'eso es correcto: el módulo no inventa entregas.',
          ),
        ],
      ],
    );
  }

  /// 5j paso 4 · tercera columna: el resumen y lo que se compromete con él.
  ///
  /// **El detalle no vive acá.** El frame no dibuja la lista decisión por
  /// decisión en el paso 4 —ésa era la pantalla del paso 3—, y meterla en una
  /// columna del 40% la deja alta y angosta justo al lado de dos columnas
  /// cortas. Va debajo, a todo el ancho, en [_buildConfirmDetail].
  Widget _buildConfirmSection(_ApplySummary summary) {
    final decisions = _buildDecisions();
    final draftVouchersToCommit = _draftVouchersToCommit(decisions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ApplySummaryPanel(summary: summary),
        const SizedBox(height: 10),
        // El frame promete, palabra por palabra, que una segunda aplicación
        // hará que «el resumen diga "0 nuevos, 4 ya aplicados"». **El recibo no
        // trae ese desglose**: `apply_payroll_statement_reconciliation` devuelve
        // el recibo guardado tal cual en un reintento, con los mismos conteos.
        // Lo que sí es cierto —y es lo que dice acá— es que la segunda no crea
        // nada. Prometer el desglose sería inventar una pantalla que no existe.
        const VbNotice(
          key: ValueKey<String>('payroll-reconciliation-idempotence-notice'),
          tone: VbNoticeTone.success,
          title: 'Aplicar dos veces no duplica nada',
          body: 'Cada movimiento se escribe con su huella. Si esta misma '
              'conciliación se aplica de nuevo, la segunda vez no crea ningún '
              'pago.',
        ),
        if (draftVouchersToCommit.isNotEmpty) ...[
          const SizedBox(height: 12),
          _DraftCommitmentPanel(vouchers: draftVouchersToCommit),
        ],
      ],
    );
  }

  /// El detalle decisión por decisión, a todo el ancho y debajo de las tres
  /// columnas: agrupado por semana, más lo que falta resolver y el error.
  Widget _buildConfirmDetail() {
    final theme = Theme.of(context);
    final blockers = _blockers;
    final decisions = _buildDecisions();
    final items = _confirmationItems(decisions);
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
    // **UNA sola regla gobierna orden, etiqueta, resumen y conteo.** Antes eran
    // tres cálculos parecidos y ya divergían: «Requieren tu lectura» contaba
    // sólo las de campos incompletos y dejaba fuera las que la propia pantalla
    // ordenaba primero por traer un aviso.
    //   0 · le faltan campos    1 · completa pero con algún aviso    2 · limpia
    int rank(PayrollStatementRow row) => !row.hasCompleteStructuredEvidence
        ? 0
        : _warningCodesFor(row).isNotEmpty
            ? 1
            : 2;
    // `needsReview`, no `needsReading`: el conjunto incluye
    // `out_of_statement_range`, que pide **revisión** —la fecha cae tras el
    // cierre declarado— y no releer el OCR. El rótulo tiene que decir lo mismo.
    final needsReview = rows.where((row) => rank(row) < 2).length;
    final dates = rows
        .map((row) => row.bookingDate)
        .whereType<PayrollCivilDate>()
        .toList()
      ..sort((a, b) => a.compareTo(b));
    // **Esto NO son «las semanas que cubre la cartola».** `vouchersById` viene
    // de `_loadOpenVouchers`, que carga **todas** las nóminas abiertas del
    // tenant (`draft`/`confirmed`/`partial`), estén o no dentro del rango del
    // documento. Rotularlas como cobertura de la cartola era afirmar algo
    // falso: una nómina abierta de otro mes aparecía como «cubierta».
    // Orden **cronológico**, por el dato que manda: `periodStart`. Un `..sort()`
    // sobre la etiqueta ya formada daba orden **lexicográfico** —«Semana 10»
    // antes que «Semana 9»— y yo lo había declarado cronológico. Se ordena por
    // el dueño y recién después se forma el texto.
    final openPayrollVouchers = draft.vouchersById.values
        .where((voucher) => voucher.id != null)
        .toList()
      ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
    final openPayrollLabels = <String>[
      for (final voucher in openPayrollVouchers) _periodLabelFor(voucher.id!),
    ];
    final ordered = [...rows]..sort((a, b) => rank(a).compareTo(rank(b)));
    // **Qué se ve, y por qué.** La versión anterior mostraba «las que piden
    // atención, o todas si no hay ninguna», y eso **escondía todos los abonos
    // en cuanto aparecía una sola fila incompleta** — justo mientras la nota de
    // abajo prometía que los abonos quedan acá. Contradicción funcional.
    //
    // Obligatorias, siempre: (a) las que piden atención y (b) **todos los
    // abonos**, porque de ellos se afirma explícitamente que se muestran uno a
    // uno. Después se completa con egresos limpios, en orden, hasta las
    // **cuatro filas** que `frames[5j]` publica en su copy —el único número de
    // filas visibles con fuente en Design—. Si las obligatorias ya pasan de
    // cuatro, se muestran todas.
    const publishedPreviewRows = 4;
    final mandatory = ordered
        .where(
          (row) =>
              rank(row) < 2 ||
              row.direction == PayrollStatementMovementDirection.incoming,
        )
        .toList();
    final fillers = ordered.where((row) => !mandatory.contains(row));
    final visible = <PayrollStatementRow>[
      ...mandatory,
      ...fillers.take(
        (publishedPreviewRows - mandatory.length).clamp(0, rows.length),
      ),
    ];
    // Lo resumido sólo puede ser egreso limpio: es lo único de lo que el pie
    // puede afirmar algo sin mentir.
    final hidden = rows.length - visible.length;

    // El estado lo pinta `PayrollStatementLedgerRow` con su propio
    // `statusLabel`/`statusTone`: duplicarlo acá con un `Container` de
    // `padding 7/2` y `monoS` era inventar un segundo tag sin dueño.
    ({String label, PayrollStateTone tone}) readingStatus(
      PayrollStatementRow row,
    ) {
      final PayrollStateTone tone;
      final String label;
      if (rank(row) == 0) {
        tone = visual.danger;
        // **No dice `ILEGIBLE`.** `hasCompleteStructuredEvidence` sólo exige
        // fecha, dirección, monto positivo y descripción: su `false` prueba que
        // **faltan campos**, no que el OCR no pudiera leer.
        label = 'CAMPOS INCOMPLETOS';
      } else if (rank(row) == 1) {
        tone = visual.warning;
        // **No dice `LECTURA DUDOSA`.** Uno de los avisos posibles es
        // `out_of_statement_range` —la fecha cae después del cierre declarado—,
        // que no tiene nada que ver con la calidad de la lectura. Llamarlo
        // lectura dudosa era falso para esa fila.
        label = 'REVISAR';
      } else {
        tone = visual.success;
        // **No dice `NÍTIDA`, y la diferencia no es de estilo.** Lo que esta
        // rama sabe es que el parser reconoció **todos los campos** de la fila
        // (`hasCompleteStructuredEvidence`, sin avisos). No sabe si el OCR leyó
        // bien: un dígito mal leído produce una fila perfectamente estructurada
        // con el monto equivocado, y `NÍTIDA` en verde invitaba a confiar en
        // ella. En una pantalla que decide dinero eso es afirmar una precisión
        // que nadie midió — `GUI_DESIGN_PRINCIPLES.md`, «un estado se deriva
        // del PORQUÉ, no de un número».
        label = 'CAMPOS COMPLETOS';
      }
      return (label: label, tone: tone);
    }

    Widget factRow(String label, String value, {PayrollStateTone? tone}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: tone?.soft ?? visual.surface,
          borderRadius: BorderRadius.circular(PayrollTokens.rField),
          border: Border.all(color: tone?.border ?? visual.border),
        ),
        // El valor **envuelve**: con cinco nóminas abiertas —un taller con
        // semanas acumuladas, que es el caso normal— este `Row` desbordaba
        // **404 px** a la derecha. El `Text` del valor no tenía ni `Flexible`
        // ni `softWrap`, así que crecía sin límite dentro de un panel de 320.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(width: PayrollTokens.gapCards),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                softWrap: true,
                style: visual.monoM.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: tone?.fg ?? visual.ink,
                ),
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
                    // `parseResult` sólo conserva las filas que detectó: no
                    // existe un total de líneas del documento contra el cual
                    // comparar, así que «N de N» era tautológico.
                    '${rows.length} ${rows.length == 1 ? 'movimiento detectado' : 'movimientos detectados'}',
                    style: visual.monoM.copyWith(fontSize: 11),
                  ),
                ),
                // `ESTADO`, no `LECTURA`: la columna dice qué campos se
                // reconocieron, no cómo salió la lectura.
                Text('ESTADO', style: visual.overline),
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
              statusLabel: readingStatus(visible[index]).label,
              statusTone: readingStatus(visible[index]).tone,
            ),
          if (hidden > 0)
            Container(
              padding: const EdgeInsets.fromLTRB(17, 9, 17, 11),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: visual.border)),
              ),
              child: Text(
                // Sólo se resumen egresos limpios, y el pie no promete que
                // «todos quedan en la revisión»: no todos los movimientos
                // alimentan `_buildTransferRows`.
                '… $hidden ${hidden == 1 ? 'egreso más' : 'egresos más'} '
                'con todos sus campos reconocidos y sin avisos.',
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
          'Nóminas abiertas que se compararán',
          openPayrollLabels.isEmpty ? '—' : openPayrollLabels.join(' · '),
        ),
        const SizedBox(height: 7),
        // `detectados`, no `leídos`: es un conteo de filas clasificadas como
        // egreso, no una medida de cobertura de lectura.
        factRow('Egresos detectados', '$outgoing de ${rows.length}'),
        if (needsReview > 0) ...[
          const SizedBox(height: 7),
          factRow(
            'Requieren revisión',
            '$needsReview ${needsReview == 1 ? 'línea' : 'líneas'}',
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
            // **«Otros movimientos» no existe en este flujo.** `_buildTransferRows`
            // arma la revisión con los egresos sin calzar y las filas de campos
            // incompletos; un abono completo no entra ahí. Prometer una sección
            // que no se construye es inventar el consumidor.
            'Los abonos no pasan a las coincidencias: un sueldo siempre es '
            'egreso. Se muestran uno a uno en esta lectura para que nadie '
            'sospeche que se perdió algo.',
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
            if (constraints.maxWidth < ResponsiveBreakpoints.desktopMin) {
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

  /// Lo que el encabezado del paso 4 puede afirmar **hoy**, no lo que el frame
  /// dibuja siempre.
  ///
  /// El frame rotula «Nada se escribió todavía» de forma incondicional, y eso
  /// deja de ser cierto en cuanto un intento de aplicar falla: `_apply()` llama
  /// `createImport` **antes** que `apply`, y ese RPC inserta la importación y
  /// sus filas. Los pagos no se crearon —`apply` es una sola transacción— pero
  /// la cartola sí quedó registrada, y una pantalla de dinero que dice «nada»
  /// cuando ya hay algo es la misma clase de afirmación falsa que 5d corrigió.
  String get _applyWriteStateNote => _importReceipt == null
      ? 'Nada se escribió todavía. Este es el último punto de retorno.'
      : 'La cartola ya quedó registrada por el intento anterior. Ningún pago '
          'se ha creado todavía.';

  /// Ancho mínimo para la composición de tres columnas del frame.
  ///
  /// Sale del propio frame, medido sobre el PNG publicado (recorte sin
  /// reescalar, 1342×390): las columnas miden **430 · 430 · 400** con
  /// **20** de canaleta, y suman los 1340 de canvas que declara el `spec.json`.
  /// La más angosta que Design dibuja es 400, así que por debajo de
  /// `3×400 + 2×20` las tres ya no caben en su proporción y se apilan. No es un
  /// número elegido: es el propio frame diciendo cuánto necesita.
  static const double _applyThreeColumnMinWidth = 3 * 400 + 2 * _applyColumnGap;
  static const double _applyColumnGap = 20;

  Widget _buildApplyStage() {
    final visual = PayrollVisualTokens.of(context);
    final decisions = _buildDecisions();
    final impacts = _weekImpacts(decisions);
    final summary = _applySummary(decisions);

    // El orden es el del frame: impacto · efectivo · resumen. Apilado sigue
    // siendo el mismo orden, porque es el de la lectura: qué cambia, qué falta
    // preguntar, y recién entonces qué se va a escribir.
    final columns = <({int flex, String title, Widget child})>[
      if (impacts.isNotEmpty)
        (
          flex: 43,
          title: 'IMPACTO POR SEMANA',
          child: _buildWeekImpactSection(impacts),
        ),
      // t5-5j: el efectivo vive dentro de Aplicar. La cartola nunca prueba
      // una entrega en mano, así que se pregunta aquí, persona por persona,
      // junto al resumen y al único punto de escritura.
      if (_cashLines.isNotEmpty)
        (
          flex: 43,
          title: 'EFECTIVO · SIEMPRE PREGUNTADO A MANO',
          child: _buildCashSection(),
        ),
      (
        flex: 40,
        title: 'RESUMEN ANTES DE ESCRIBIR',
        child: _buildConfirmSection(summary),
      ),
    ];

    Widget titled(({int flex, String title, Widget child}) column) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(column.title, style: visual.overline),
          const SizedBox(height: 9),
          column.child,
        ],
      );
    }

    return ListView(
      key: const PageStorageKey<String>('payroll-reconciliation-apply'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      children: [
        Text(
          _applyWriteStateNote,
          key:
              const ValueKey<String>('payroll-reconciliation-apply-write-note'),
          style: visual.bodyS.copyWith(
            fontSize: 10.5,
            color: visual.inkFaint,
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            if (columns.length < 3 ||
                constraints.maxWidth < _applyThreeColumnMinWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < columns.length; index++) ...[
                    if (index > 0) const SizedBox(height: 18),
                    titled(columns[index]),
                  ],
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < columns.length; index++) ...[
                  if (index > 0) const SizedBox(width: _applyColumnGap),
                  Expanded(
                    flex: columns[index].flex,
                    child: titled(columns[index]),
                  ),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Text('DETALLE POR SEMANA', style: visual.overline),
        const SizedBox(height: 9),
        _buildConfirmDetail(),
      ],
    );
  }

  /// 5j paso 4 · «IMPACTO POR SEMANA»: antes tachado → después, con el rótulo
  /// `falta pagar` que el frame usa para decir qué significa la cifra grande.
  Widget _buildWeekImpactSection(List<_WeekImpact> impacts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < impacts.length; index++) ...[
          if (index > 0) const SizedBox(height: 9),
          _WeekImpactCard(impact: impacts[index]),
        ],
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
            label: 'Ver propuestas de pago',
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

/// **5j · paso 1** — qué esperar de cada fuente, antes de elegir.
///
/// Design dibuja tres tarjetas con una línea cada una. Se copia la composición
/// porque resuelve la decisión real del operador —«¿escaneo o saco una foto?»—
/// que los chips anteriores no resolvían: decían si la fuente estaba disponible,
/// no qué calidad de lectura iba a dar.
///
/// **El texto NO se copia entero**, y ésa es la parte que importa:
/// - *PDF del banco* — el frame promete que «la extracción es **exacta**». No
///   se copia: `embeddedPdfText` sólo nombra el método **inicial**, y
///   `_needsPdfOcrRetry` fuerza OCR de imagen cuando menos de la mitad de las
///   filas traen evidencia estructurada completa. Se promete lo que sí se
///   cumple: que lee el texto incorporado y no usa OCR cuando viene
///   estructurado.
/// - *Imagen o captura* — el frame promete «OCR **con confianza por línea**; las
///   dudosas se marcan». Esa confianza **no existe en la extracción**: la única
///   `PayrollMatchConfidence` del módulo es la del **match** del paso 3, otra
///   cosa. Y «lo que quede ilegible se marca» tampoco se puede prometer: el
///   parser señala **filas reconocidas con campos que no reconoció**
///   (`missing_date`, `invalid_date`, `ambiguous_direction`,
///   `missing_transaction_amount`, `unstructured_row`), que no es cobertura
///   total de lo ilegible. Se nombra exactamente eso.
/// - *Cámara* — el frame promete «guía de encuadre y recorte». **No existe**
///   ninguna, así que se descarta la promesa y se conserva la disponibilidad
///   real, que el frame no dibuja.
class _SourceExpectations extends StatelessWidget {
  const _SourceExpectations({
    required this.supportsImages,
    required this.supportsCapture,
  });

  final bool supportsImages;
  final bool supportsCapture;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);

    Widget card({
      required String title,
      required String body,
      required bool available,
      String? unavailable,
    }) {
      return Container(
        key: ValueKey<String>('payroll-source-expectation-$title'),
        // **Todo el espaciado sale de `PayrollTokens`**, que es el único dueño
        // de espaciado del módulo. Una versión anterior traía `12/10`, `4` y
        // `8` inventados acá, y encima el ledger afirmaba que venían de tokens.
        // El radio se toma de `rField` porque es radio; **no se usa un token de
        // radio como spacing**.
        padding: const EdgeInsets.all(PayrollTokens.gapBlocks),
        decoration: BoxDecoration(
          color: visual.surfaceSunken,
          borderRadius: BorderRadius.circular(PayrollTokens.rField),
          border: Border.all(color: visual.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              // `labelStrong` sin tocar tamaño ni alto: sólo el color, que es
              // un rol.
              style: visual.labelStrong.copyWith(
                color: available ? visual.ink : visual.inkFaint,
              ),
            ),
            const SizedBox(height: PayrollTokens.gapCards),
            Text(
              available ? body : (unavailable ?? body),
              // `bodyS` **entero**: es 11,5, no 11. Reducirlo acá era inventar
              // un tamaño de texto propio de esta pantalla.
              style: visual.bodyS.copyWith(
                color: available ? visual.inkMuted : visual.inkFaint,
              ),
            ),
          ],
        ),
      );
    }

    final cards = <Widget>[
      card(
        title: 'PDF del banco',
        body: 'Lee el texto incorporado al PDF; no usa OCR cuando viene '
            'estructurado.',
        available: true,
      ),
      card(
        title: 'Imagen o captura',
        body: 'Se lee con OCR en este dispositivo. Las filas con campos que no '
            'se reconocen quedan señaladas para que las revises en el paso 2.',
        available: supportsImages,
        unavailable: 'No disponible en este dispositivo: usa un PDF con texto.',
      ),
      card(
        // **No se copia el rótulo del frame.** `5j` titula esta tarjeta
        // «Cámara», que es **exactamente** el texto del control que dispara la
        // captura: dos cosas distintas con el mismo nombre en la misma
        // pantalla. Un lector de pantalla anuncia dos «Cámara» y el operador no
        // sabe cuál actúa. La tarjeta describe, el botón hace.
        title: 'Foto con la cámara',
        body: 'Una foto de la cartola en el mesón, con la misma lectura que '
            'una imagen.',
        available: supportsCapture,
        unavailable: 'Sólo en Android y iPhone.',
      ),
    ];

    // El corte lo decide el **owner responsivo canónico**, no un número de
    // esta pantalla: `ResponsiveBreakpoints.phoneMaxExclusive`. Una versión
    // anterior comparaba el ancho del contenido contra un `560` explicado sólo
    // por «se ve apretado» — un breakpoint feature-local sin dueño, que es lo
    // que `universal-ui-component-system.md` prohíbe.
    final stacked = ResponsiveViewport.widthOf(context) <
        ResponsiveBreakpoints.phoneMaxExclusive;
    return Builder(
      builder: (context) {
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < cards.length; i++) ...<Widget>[
                cards[i],
                if (i != cards.length - 1)
                  const SizedBox(height: PayrollTokens.gapCards),
              ],
            ],
          );
        }
        // `IntrinsicHeight` y no `stretch` a secas: dentro del `ListView` la
        // altura no está acotada, y un `Row` que estira pide infinito — el
        // árbol reventaba y la prueba lo veía como «el aviso no existe».
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < cards.length; i++) ...<Widget>[
                Expanded(child: cards[i]),
                if (i != cards.length - 1)
                  const SizedBox(width: PayrollTokens.gapCards),
              ],
            ],
          ),
        );
      },
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

/// 5j paso 4 · una semana de la columna «IMPACTO POR SEMANA».
///
/// Geometría del frame publicado (`handoff-t5/frames/5j-paso4.png`, 1342×390,
/// recorte sin reescalar): tarjeta de **69** de alto y **9** de separación,
/// borde `border` y radio `rPanel`. Los colores no se miden: salen de
/// [PayrollVisualTokens], que es quien los ata al preset y al brillo.
class _WeekImpactCard extends StatelessWidget {
  const _WeekImpactCard({required this.impact});

  final _WeekImpact impact;

  /// La glosa de la derecha, en el idioma del módulo. El frame escribe
  /// «1 transferencia + 1 efectivo» y «1 pago parcial de $100.000»: cuenta
  /// movimientos, no decisiones.
  String get _movementsLabel {
    final parts = <String>[
      if (impact.transferCount > 0)
        '${impact.transferCount} '
            '${impact.transferCount == 1 ? 'transferencia' : 'transferencias'}',
      if (impact.cashCount > 0) '${impact.cashCount} en efectivo',
      if (impact.advanceCount > 0)
        '${impact.advanceCount} '
            '${impact.advanceCount == 1 ? 'anticipo' : 'anticipos'}',
    ];
    final base = parts.join(' + ');
    if (impact.partialCount == 0) return base;
    return '$base · ${impact.partialCount} '
        '${impact.partialCount == 1 ? 'parcial' : 'parciales'}';
  }

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: ValueKey<String>('payroll-week-impact-${impact.voucherId}'),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  impact.weekLabel,
                  style: visual.cardTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _movementsLabel,
                  style: visual.bodyS.copyWith(color: visual.inkFaint),
                  textAlign: TextAlign.right,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          // `antes → después`. El «antes» va tachado porque deja de ser cierto
          // en cuanto se aplica; el «después» es la cifra que manda y por eso
          // lleva el rótulo que dice qué es. Sin ese rótulo, una cifra sola en
          // una pantalla de nómina se lee como «lo que se va a pagar», que es
          // justo lo contrario.
          //
          // **Excepción declarada a F-03, y por qué NO se ensancha su API.**
          // Estas dos cifras usan `VbMoneyText.formatClp` dentro de un `Text`
          // en vez del widget `VbMoneyText`, porque necesitan dos cosas que el
          // componente canónico no ofrece **a propósito**: tachado para el
          // «antes» y el tamaño mayor de `numCard` para el «después».
          // `universal-ui-component-system.md` prohíbe que un componente
          // canónico acepte overrides visuales arbitrarios, y `VbMoneyText`
          // documenta que una versión suya con `size`/`weight`/`color` fue
          // retirada justo por eso. Agregarle parámetros para este caso sería
          // reabrir esa puerta para una sola pantalla.
          // Lo que sí es innegociable es el **formato**, y por eso se usa
          // `formatClp`, que el propio F-03 publica como `static` precisamente
          // para que un `Text`, una etiqueta de semántica y una prueba escriban
          // el peso de la misma manera. La cifra del total del resumen, que no
          // necesita ninguna de las dos excepciones, sí usa `VbMoneyText`.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                VbMoneyText.formatClp(impact.beforeClp),
                style: visual.monoM.copyWith(
                  color: visual.inkFaint,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: visual.inkFaint,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded,
                  size: 13, color: visual.inkFaint),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  VbMoneyText.formatClp(impact.afterClp),
                  style: visual.numCard,
                  maxLines: 1,
                  softWrap: false,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                'falta pagar',
                style: visual.bodyS.copyWith(color: visual.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 5j paso 4 · panel «RESUMEN ANTES DE ESCRIBIR».
///
/// Cada fila corresponde a algo que `apply` hace de verdad. Las dos filas del
/// frame que no sobrevivieron la auditoría están documentadas en [_ApplySummary]
/// con su razón; no se descartaron por gusto.
class _ApplySummaryPanel extends StatelessWidget {
  const _ApplySummaryPanel({required this.summary});

  final _ApplySummary summary;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final rows = <({String label, String value, bool emphasis})>[
      (
        label: 'Pagos que se crearán',
        value: '${summary.paymentCount}',
        emphasis: false,
      ),
      if (summary.partialCount > 0)
        (
          label: 'De ellos, pagos parciales',
          value: '${summary.partialCount} · '
              '${VbMoneyText.formatClp(summary.partialAmountClp)}',
          emphasis: true,
        ),
      if (summary.advanceCount > 0)
        (
          label: 'Anticipos que se descontarán',
          value: '${summary.advanceCount} · '
              '${VbMoneyText.formatClp(summary.advanceAmountClp)}',
          emphasis: false,
        ),
      if (summary.alreadyResolvedCount > 0)
        (
          label: 'Ya conciliados en otra cartola',
          value: '${summary.alreadyResolvedCount}',
          emphasis: false,
        ),
      if (summary.operatorExcludedCount > 0)
        (
          label: 'Excluidos por ti',
          value: '${summary.operatorExcludedCount}',
          emphasis: false,
        ),
    ];

    return Container(
      key: const ValueKey<String>('payroll-reconciliation-apply-summary'),
      padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
      decoration: BoxDecoration(
        color: visual.surfaceSelected,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.accentBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0) const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Text(
                    rows[index].label,
                    style: visual.bodyS.copyWith(color: visual.ink),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  rows[index].value,
                  style: visual.monoM.copyWith(
                    fontWeight: FontWeight.w700,
                    color: rows[index].emphasis ? visual.warningFg : visual.ink,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Divider(height: 1, color: visual.accentBorder),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  // «Imputar» quedó derogado por el propio Design en el turno 7
                  // («Decisiones de producto respetadas: "Imputar" →
                  // "Aplicar"»), y el contrato de sincronía lo nombra como el
                  // ejemplo de copy que este módulo no usa. El frame del turno 5
                  // conserva la palabra vieja; gana la decisión posterior.
                  'Total a aplicar',
                  style: visual.labelStrong,
                ),
              ),
              const SizedBox(width: 12),
              VbMoneyText(summary.totalClp),
            ],
          ),
        ],
      ),
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
