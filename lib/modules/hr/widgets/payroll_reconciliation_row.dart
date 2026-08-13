import 'package:flutter/material.dart';

import '../models/payroll_statement_reconciliation.dart';
import '../payroll/surfaces/payroll_transfer_review_surface.dart';
import '../payroll/theme/payroll_tokens.dart';
import '../services/payroll_reconciliation_service.dart';
import 'payroll_money_bar.dart';

/// What the operator decided for one reviewable item.
///
/// [pending] is a real state: nothing is applied while an outgoing movement
/// still has no disposition, so a transfer can never disappear silently.
enum PayrollRowDisposition {
  pending,
  confirm,
  notPaid,
  alreadyResolved,
  ignore,
  hold,
  notPayroll,
}

extension PayrollRowDispositionCopy on PayrollRowDisposition {
  String get label => switch (this) {
        PayrollRowDisposition.pending => 'Sin decidir',
        PayrollRowDisposition.confirm => 'Es este pago',
        PayrollRowDisposition.notPaid => 'Todavía no pagado',
        PayrollRowDisposition.alreadyResolved => 'Ya conciliado',
        PayrollRowDisposition.ignore => 'Error o duplicado',
        PayrollRowDisposition.hold => 'Retener como excepción',
        PayrollRowDisposition.notPayroll => 'No es nómina',
      };

  PayrollReviewDecisionKind? get decisionKind => switch (this) {
        PayrollRowDisposition.pending => null,
        PayrollRowDisposition.confirm => PayrollReviewDecisionKind.bankPayment,
        PayrollRowDisposition.notPaid => PayrollReviewDecisionKind.notPaid,
        PayrollRowDisposition.alreadyResolved =>
          PayrollReviewDecisionKind.alreadyResolved,
        PayrollRowDisposition.ignore => PayrollReviewDecisionKind.ignore,
        PayrollRowDisposition.hold => PayrollReviewDecisionKind.hold,
        PayrollRowDisposition.notPayroll => PayrollReviewDecisionKind.ignore,
      };

  String? get auditReason => switch (this) {
        PayrollRowDisposition.pending ||
        PayrollRowDisposition.confirm ||
        PayrollRowDisposition.notPaid =>
          null,
        PayrollRowDisposition.alreadyResolved =>
          'El operador reconoció la resolución final de una importación '
              'anterior.',
        PayrollRowDisposition.ignore =>
          'El operador marcó la fila como lectura duplicada o errónea.',
        PayrollRowDisposition.hold =>
          'El operador retuvo la fila como excepción final de esta cartola.',
        PayrollRowDisposition.notPayroll =>
          'El operador confirmó que el movimiento no corresponde a nómina.',
      };
}

/// The shape of a reviewable item, independent of where it came from.
enum PayrollDecisionRowKind {
  /// The matcher proposes one voucher line for one bank movement.
  suggested,

  /// An outgoing movement with no proposal. It still needs a disposition.
  unmatchedMovement,

  /// A payroll obligation the matcher could not pair. It still needs an
  /// explicit "not paid" disposition before a draft week can be committed.
  ineligibleLine,

  /// A duplicate/overlapping statement row with a prior final decision.
  alreadyResolvedMovement,

  /// OCR detected a row but could not recover all structured fields. It stays
  /// visible and auditable without being eligible to create a payment.
  incompleteEvidence,
}

@immutable
class PayrollManualMatchOption {
  const PayrollManualMatchOption({
    required this.lineId,
    required this.voucherId,
    required this.employeeId,
    required this.employeeName,
    required this.label,
    required this.expectedAmountClp,
  });

  final String lineId;
  final String voucherId;
  final String employeeId;
  final String employeeName;
  final String label;
  final int expectedAmountClp;
}

@immutable
class PayrollDecisionRowData {
  const PayrollDecisionRowData({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.bankDescription = '',
    this.beneficiaryObserved,
    this.date,
    this.bankAmountClp,
    this.expectedAmountClp,
    this.varianceClp,
    this.confidence,
    this.confidenceScore,
    this.manualCertainty = false,
    this.explanations = const [],
    this.sourceRowId,
    this.voucherLineId,
    this.voucherId,
    this.employeeId,
    this.warningCodes = const [],
    this.canConfirm = true,
    this.manualMatchOptions = const [],
    this.selectedManualLineId,
    this.priorDecisionId,
    this.isManualMatch = false,
    this.originalProposedLineId,
    this.originalProposedVoucherId,
    this.originalProposedEmployeeId,
    this.automaticDisposition,
    this.automaticAuditReason,
  });

  final String id;
  final PayrollDecisionRowKind kind;
  final String title;
  final String subtitle;
  final String bankDescription;
  final String? beneficiaryObserved;
  final PayrollCivilDate? date;
  final int? bankAmountClp;
  final int? expectedAmountClp;
  final int? varianceClp;
  final PayrollMatchConfidence? confidence;

  /// Matcher score 0–100 for the proposal shown in this row. Absent when no
  /// proposal exists; irrelevant once the operator decides by hand.
  final int? confidenceScore;

  /// The operator resolved this row personally (manual link or explicit
  /// answer): certainty stops being an algorithm's estimate and becomes a
  /// human responsibility.
  final bool manualCertainty;
  final List<String> explanations;

  final String? sourceRowId;
  final String? voucherLineId;
  final String? voucherId;
  final String? employeeId;
  final List<String> warningCodes;
  final bool canConfirm;
  final List<PayrollManualMatchOption> manualMatchOptions;
  final String? selectedManualLineId;
  final String? priorDecisionId;
  final bool isManualMatch;
  final String? originalProposedLineId;
  final String? originalProposedVoucherId;
  final String? originalProposedEmployeeId;
  final PayrollRowDisposition? automaticDisposition;
  final String? automaticAuditReason;

  bool get isAutomaticallyClassified => automaticDisposition != null;

  /// A non-zero difference must be disposed of explicitly before applying.
  bool get hasVariance => (varianceClp ?? 0) != 0;

  bool get isPartialPayment {
    final bank = bankAmountClp;
    final expected = expectedAmountClp;
    return bank != null && expected != null && bank > 0 && bank < expected;
  }

  int? get appliedAmountClp =>
      isPartialPayment ? bankAmountClp : expectedAmountClp;

  int? get remainingAmountClp =>
      isPartialPayment ? expectedAmountClp! - bankAmountClp! : null;

  bool get needsReviewReason =>
      hasVariance || warningCodes.isNotEmpty || isManualMatch;

  /// Both outgoing bank money and an unmatched payroll obligation need an
  /// answer. This keeps a draft voucher complete when the server confirms it.
  bool get requiresDisposition =>
      !isAutomaticallyClassified &&
      (kind == PayrollDecisionRowKind.suggested ||
          kind == PayrollDecisionRowKind.unmatchedMovement ||
          kind == PayrollDecisionRowKind.ineligibleLine ||
          kind == PayrollDecisionRowKind.alreadyResolvedMovement ||
          kind == PayrollDecisionRowKind.incompleteEvidence);
}

/// Qué hacer con la fila, no cuán seguro está el sistema.
///
/// Decía «Confianza alta / media / baja», que es la misma precisión falsa que
/// el `61%` ya retirado, sólo que en palabras: describe una medida que nadie
/// tomó en vez de nombrar la acción. Y convivía en la MISMA pantalla con la
/// píldora `CALZA / REVISA / NO SÉ QUIÉN ES`, así que el operador leía dos
/// vocabularios para el mismo hecho. Ahora es uno solo.
String payrollConfidenceLabel(PayrollMatchConfidence confidence) {
  return switch (confidence) {
    PayrollMatchConfidence.none => 'NO SÉ QUIÉN ES',
    PayrollMatchConfidence.low || PayrollMatchConfidence.medium => 'REVISA',
    PayrollMatchConfidence.high => 'CALZA',
  };
}

String payrollCandidateReasonLabel(PayrollCandidateReason reason) {
  return switch (reason) {
    PayrollCandidateReason.outgoingMovement => 'Es un cargo saliente',
    PayrollCandidateReason.primaryNameMatched => 'El nombre coincide',
    PayrollCandidateReason.configuredAliasMatched =>
      'Coincide con un alias configurado',
    // Se dice lo que de verdad pasó, no «el nombre coincide»: el banco imprimió
    // una parte del nombre registrado, y esa diferencia es justo lo que el
    // operador tiene que mirar antes de aceptar el pago.
    PayrollCandidateReason.shortNameMatched =>
      'El banco imprime una forma corta del nombre registrado',
    PayrollCandidateReason.paymentMethodIsTransfer =>
      'La persona cobra por transferencia',
    PayrollCandidateReason.paymentMethodDiffersFromPreference =>
      'El movimiento puede ser pago aunque difiera del método habitual',
    PayrollCandidateReason.dateWithinWindow =>
      'La fecha cae dentro de la ventana de pago',
    PayrollCandidateReason.dateMissing => 'El movimiento no trae fecha',
    PayrollCandidateReason.dateOutsideWindow =>
      'La fecha queda fuera de la ventana de pago',
    PayrollCandidateReason.amountExact => 'El monto es exacto',
    PayrollCandidateReason.amountWithinTolerance =>
      'El monto está dentro de la tolerancia',
    PayrollCandidateReason.amountBelowPendingBalance =>
      'El monto es menor al saldo y sólo puede vincularse como pago parcial',
    PayrollCandidateReason.amountOutsideTolerance =>
      'El monto queda fuera de la tolerancia',
    PayrollCandidateReason.nonZeroVariance => 'Hay diferencia de monto',
    PayrollCandidateReason.multipleTransactionsForLine =>
      'Varios movimientos podrían ser este pago',
    // **Decía «con más de una persona», y era falso.** Lo normal es que las
    // otras candidatas sean OTRAS SEMANAS DE LA MISMA PERSONA —sueldo semanal
    // plano, dos semanas cuya ventana se solapa—, y leer «más de una persona»
    // ahí no describe nada de lo que está pasando. Corregido el 2026-08-10
    // sobre la cartola real, donde las tres semanas de $35.000 de un mismo
    // trabajador se explicaban con esa frase.
    PayrollCandidateReason.transactionMatchesMultipleLines =>
      'Este movimiento podría pagar más de una semana',
    PayrollCandidateReason.transactionMatchesMultipleEmployees =>
      'Este movimiento calza con más de una persona',
    PayrollCandidateReason.assignedByWeekOrder =>
      'Hay pagos iguales: se asignó el más antiguo a la semana más antigua',
  };
}

String payrollLineReasonLabel(PayrollLineMatchReason reason) {
  return switch (reason) {
    PayrollLineMatchReason.uniqueCandidate => 'Hay un único candidato',
    PayrollLineMatchReason.missingEmployee =>
      'No se encontró la ficha de la persona',
    PayrollLineMatchReason.paymentMethodIsCash =>
      'La persona cobra en efectivo',
    PayrollLineMatchReason.paymentMethodIsNotTransfer =>
      'Su método de pago no es transferencia',
    PayrollLineMatchReason.lineIsNotPending => 'La línea ya no está pendiente',
    PayrollLineMatchReason.pendingAmountIsNotPositive =>
      'No queda saldo por pagar',
    PayrollLineMatchReason.noBeneficiaryMatch =>
      'Ningún movimiento nombra a esta persona',
    PayrollLineMatchReason.noEligibleTransaction =>
      'No hay movimiento elegible en la cartola',
    PayrollLineMatchReason.multipleTransactionsForLine =>
      'Varios movimientos podrían ser este pago',
    PayrollLineMatchReason.transactionMatchesMultipleLines =>
      'El movimiento podría pagar más de una semana',
    PayrollLineMatchReason.transactionMatchesMultipleEmployees =>
      'El movimiento calza con más de una persona',
    PayrollLineMatchReason.assignedByWeekOrder =>
      'Hay pagos iguales: se asignó el más antiguo a la semana más antigua',
    PayrollLineMatchReason.transactionsTakenByOlderWeeks =>
      'Los pagos que calzaban se asignaron a semanas anteriores',
  };
}

/// Claude Design 2c copy for one disposition option card: honest description
/// and a semantic consequence tag. Colors resolve from the mounted tokens at
/// build time, never here.
extension PayrollRowDispositionPresentation on PayrollRowDisposition {
  String describe(PayrollDecisionRowKind kind) => switch (this) {
        PayrollRowDisposition.pending => '',
        PayrollRowDisposition.confirm =>
          kind == PayrollDecisionRowKind.suggested
              ? 'Registra el pago con este movimiento bancario.'
              : 'Registra el pago con el vínculo elegido.',
        PayrollRowDisposition.notPaid =>
          'La obligación sigue pendiente para otra cartola.',
        PayrollRowDisposition.alreadyResolved =>
          'Reconoce la resolución final de una importación anterior.',
        PayrollRowDisposition.ignore =>
          'Lectura duplicada o errónea de la cartola. No crea pago.',
        PayrollRowDisposition.hold =>
          'Queda retenido como excepción auditada de esta cartola.',
        PayrollRowDisposition.notPayroll =>
          'Gasto ajeno a la nómina. Se conserva como evidencia.',
      };

  String get consequenceTag => switch (this) {
        PayrollRowDisposition.pending => '',
        PayrollRowDisposition.confirm => 'crea pago',
        PayrollRowDisposition.notPaid => 'sin pago',
        PayrollRowDisposition.alreadyResolved => 'protegido',
        PayrollRowDisposition.ignore => 'sin pago',
        PayrollRowDisposition.hold => 'excepción',
        PayrollRowDisposition.notPayroll => 'sin pago',
      };

  PayrollStateTone toneOf(PayrollVisualTokens visual) => switch (this) {
        PayrollRowDisposition.confirm => visual.success,
        PayrollRowDisposition.notPaid => visual.warning,
        PayrollRowDisposition.alreadyResolved => visual.info,
        PayrollRowDisposition.hold => visual.warning,
        PayrollRowDisposition.pending ||
        PayrollRowDisposition.ignore ||
        PayrollRowDisposition.notPayroll =>
          visual.neutral,
      };
}

/// Las respuestas posibles para una fila, en el orden en que se ofrecen.
///
/// Vive fuera del widget porque la tabla de la etapa 3 monta la misma lista en
/// un `S-05`: una sola fuente para «qué se puede contestar acá», de modo que el
/// selector de la tabla y el detalle de la fila nunca ofrezcan cosas distintas.
List<PayrollRowDisposition> payrollDispositionOptionsFor(
  PayrollDecisionRowData data,
) {
  if (data.canConfirm) {
    return const [
      PayrollRowDisposition.confirm,
      PayrollRowDisposition.hold,
      PayrollRowDisposition.notPayroll,
      PayrollRowDisposition.ignore,
    ];
  }
  return switch (data.kind) {
    PayrollDecisionRowKind.suggested => const [
        PayrollRowDisposition.hold,
        PayrollRowDisposition.notPayroll,
        PayrollRowDisposition.ignore,
      ],
    PayrollDecisionRowKind.unmatchedMovement => const [
        PayrollRowDisposition.notPayroll,
        PayrollRowDisposition.hold,
        PayrollRowDisposition.ignore,
      ],
    PayrollDecisionRowKind.ineligibleLine => const [
        PayrollRowDisposition.notPaid,
      ],
    PayrollDecisionRowKind.alreadyResolvedMovement => const [
        PayrollRowDisposition.alreadyResolved,
      ],
    PayrollDecisionRowKind.incompleteEvidence => const [
        PayrollRowDisposition.hold,
        PayrollRowDisposition.notPayroll,
        PayrollRowDisposition.ignore,
      ],
  };
}

/// El detalle de una fila revisable: por qué calza, a quién vincularla, qué
/// pasa con la diferencia y la razón de auditoría.
///
/// Se abre desde la fila de la tabla de propuestas, que ya muestra identidad,
/// los dos montos y la disposición. **Este widget dejó de dibujar todo eso el
/// 2026-08-10**: repetirlo era exactamente el bloque que el dueño rechazó al
/// usar la etapa («infinite huge fucking blocks everywhere») — la misma
/// información dos veces, con dos gramáticas, multiplicada por cada fila.
///
/// Nunca aplica nada por sí mismo y nunca ofrece cambiar horas o tarifa para
/// hacer desaparecer una diferencia.
class PayrollReconciliationRowDetail extends StatefulWidget {
  const PayrollReconciliationRowDetail({
    super.key,
    required this.data,
    required this.disposition,
    required this.varianceDisposition,
    required this.onVarianceDisposition,
    this.reviewReason = '',
    this.onReviewReasonChanged,
    this.onManualMatchChanged,
    this.learnBeneficiaryAlias = false,
    this.onLearnBeneficiaryAliasChanged,
    this.enabled = true,
  });

  final PayrollDecisionRowData data;
  final PayrollRowDisposition disposition;
  final PayrollVarianceDisposition varianceDisposition;
  final ValueChanged<PayrollVarianceDisposition> onVarianceDisposition;
  final String reviewReason;
  final ValueChanged<String>? onReviewReasonChanged;
  final ValueChanged<String?>? onManualMatchChanged;
  final bool learnBeneficiaryAlias;
  final ValueChanged<bool>? onLearnBeneficiaryAliasChanged;

  final bool enabled;

  @override
  State<PayrollReconciliationRowDetail> createState() =>
      _PayrollReconciliationRowDetailState();
}

class _PayrollReconciliationRowDetailState
    extends State<PayrollReconciliationRowDetail> {
  late final TextEditingController _reasonController =
      TextEditingController(text: widget.reviewReason);

  PayrollDecisionRowData get data => widget.data;
  PayrollRowDisposition get disposition => widget.disposition;
  bool get enabled => widget.enabled;
  PayrollVarianceDisposition get varianceDisposition =>
      widget.varianceDisposition;
  ValueChanged<PayrollVarianceDisposition> get onVarianceDisposition =>
      widget.onVarianceDisposition;
  String get reviewReason => widget.reviewReason;
  ValueChanged<String>? get onReviewReasonChanged =>
      widget.onReviewReasonChanged;
  ValueChanged<String?>? get onManualMatchChanged =>
      widget.onManualMatchChanged;
  bool get learnBeneficiaryAlias => widget.learnBeneficiaryAlias;
  ValueChanged<bool>? get onLearnBeneficiaryAliasChanged =>
      widget.onLearnBeneficiaryAliasChanged;

  PayrollManualMatchOption? get _selectedManualOption {
    final selectedLineId = data.selectedManualLineId;
    if (selectedLineId == null) return null;
    for (final option in data.manualMatchOptions) {
      if (option.lineId == selectedLineId) return option;
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant PayrollReconciliationRowDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The audit reason can be set from outside (quick rounding accept). Keep
    // the controller authoritative while typing: only push a text that is
    // genuinely different.
    if (widget.reviewReason != _reasonController.text) {
      _reasonController.text = widget.reviewReason;
      _reasonController.selection = TextSelection.collapsed(
        offset: _reasonController.text.length,
      );
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final needsAnswer = data.requiresDisposition &&
        disposition == PayrollRowDisposition.pending;

    // Las señales que la fila de la tabla NO puede decir con un solo tag de
    // estado. Fecha, confianza y montos ya viven en sus columnas, así que no se
    // repiten acá: sólo lo que cambia la lectura de la evidencia.
    final flags = <Widget>[
      if (data.isPartialPayment)
        const _MetaChip(label: 'Pago parcial', emphasis: true),
      if (data.isAutomaticallyClassified)
        const _MetaChip(label: 'Clasificado automáticamente'),
      if (needsAnswer)
        const _MetaChip(label: 'Necesita respuesta', emphasis: true),
      if (!data.canConfirm &&
          data.kind == PayrollDecisionRowKind.alreadyResolvedMovement)
        const _MetaChip(
          label: 'Protegido contra pago duplicado',
          emphasis: true,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 9, bottom: 13),
      child: Builder(
        builder: (context) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (flags.isNotEmpty) ...[
                Wrap(spacing: 6, runSpacing: 6, children: flags),
                const SizedBox(height: 9),
              ],
              if (data.explanations.isNotEmpty)
                _Explanations(explanations: data.explanations),
              if (data.manualMatchOptions.isNotEmpty) ...[
                const SizedBox(height: 11),
                DropdownButtonFormField<String>(
                  initialValue: data.selectedManualLineId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Vincular a persona y semana',
                    helperText:
                        'Puedes corregir una sugerencia o vincular un abono parcial.',
                  ),
                  items: [
                    for (final option in data.manualMatchOptions)
                      DropdownMenuItem<String>(
                        value: option.lineId,
                        child: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: enabled ? onManualMatchChanged : null,
                ),
              ],
              if (data.isManualMatch &&
                  data.beneficiaryObserved != null &&
                  _selectedManualOption != null &&
                  onLearnBeneficiaryAliasChanged != null) ...[
                const SizedBox(height: 8),
                CheckboxListTile(
                  key: ValueKey(
                    'payroll-alias-learning-${data.sourceRowId}',
                  ),
                  value: learnBeneficiaryAlias,
                  onChanged: enabled
                      ? (value) =>
                          onLearnBeneficiaryAliasChanged!(value == true)
                      : null,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Recordar “${data.beneficiaryObserved}” como nombre '
                    'bancario de ${_selectedManualOption!.employeeName}',
                    style: visual.bodyM.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Es opcional. La próxima cartola podrá sugerir esta '
                    'persona, pero nunca se pagará sin revisión.',
                  ),
                ),
              ],
              if (data.hasVariance &&
                  disposition == PayrollRowDisposition.confirm) ...[
                const SizedBox(height: 12),
                _VarianceDisposition(
                  movementId: data.id,
                  varianceClp: data.varianceClp!,
                  appliedAmountClp: data.appliedAmountClp,
                  value: varianceDisposition,
                  enabled: enabled,
                  onChanged: onVarianceDisposition,
                  // One tap for the systematic bank round-up: same contract
                  // (the residue stays unresolved), pre-filled editable
                  // reason instead of typing it every week.
                  onAcceptRounding:
                      data.varianceClp! > 0 && onReviewReasonChanged != null
                          ? () {
                              onVarianceDisposition(
                                PayrollVarianceDisposition.unresolved,
                              );
                              onReviewReasonChanged!(
                                'Redondeo bancario: la transferencia superó la '
                                'obligación en '
                                '${formatPayrollClp(data.varianceClp!)}.',
                              );
                            }
                          : null,
                ),
              ],
              if (data.needsReviewReason &&
                  disposition == PayrollRowDisposition.confirm) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _reasonController,
                  minLines: 2,
                  maxLines: 3,
                  enabled: enabled,
                  onChanged: enabled ? onReviewReasonChanged : null,
                  decoration: InputDecoration(
                    labelText: 'Razón de confirmación',
                    hintText: data.isPartialPayment
                        ? 'Explica cómo verificaste este abono parcial'
                        : 'Explica por qué aceptas la diferencia o advertencia',
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _VarianceDisposition extends StatelessWidget {
  const _VarianceDisposition({
    required this.movementId,
    required this.varianceClp,
    required this.appliedAmountClp,
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.onAcceptRounding,
  });

  /// Identidad del movimiento al que pertenece esta diferencia.
  ///
  /// Varias filas pueden tener su detalle abierto a la vez, y entonces hay
  /// varios «Dejar sin conciliar» idénticos en pantalla: sin id, quien resuelve
  /// por identidad —VoiceOver, una prueba— sólo alcanza el primero.
  final String movementId;
  final int varianceClp;
  final int? appliedAmountClp;
  final PayrollVarianceDisposition value;
  final ValueChanged<PayrollVarianceDisposition> onChanged;
  final bool enabled;

  /// One-tap accept for a positive bank round-up: selects "unresolved" and
  /// pre-fills the audit reason. The contract does not change — a residue is
  /// never converted into an advance automatically.
  final VoidCallback? onAcceptRounding;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final isOverpayment = varianceClp > 0;
    final isPartial = varianceClp < 0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: visual.warningSoft,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.warningBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isOverpayment
                ? 'Se transfirió ${formatPayrollClp(varianceClp.abs())} de más'
                : 'Pago parcial · quedan ${formatPayrollClp(varianceClp.abs())} pendientes',
            style: visual.bodyS.copyWith(
              fontSize: 11,
              color: visual.warningFg,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isPartial
                ? 'Se aplicarán ${formatPayrollClp(appliedAmountClp ?? 0)} a esta '
                    'obligación. El saldo restante seguirá pendiente y no se '
                    'marcará como pago completo.'
                : 'Elige qué pasa con la diferencia. No se ajustan horas ni '
                    'tarifas para hacerla desaparecer.',
            style: visual.bodyS.copyWith(
              fontSize: 10.5,
              color: visual.warningFg,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          if (isPartial)
            Row(
              children: [
                Icon(
                  value == PayrollVarianceDisposition.partial
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  size: 18,
                  color: visual.warningFg,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value == PayrollVarianceDisposition.partial
                        ? 'Disposición: registrar pago parcial'
                        : 'Falta reconocer este movimiento como pago parcial',
                    style: visual.bodyS.copyWith(
                      fontSize: 11,
                      color: visual.warningFg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PayrollDecisionOptionCard(
                  movementId: movementId,
                  optionName: 'varianceUnresolved',
                  title: 'Dejar sin conciliar',
                  description: 'La diferencia queda registrada y visible; '
                      'nadie la absorbe en silencio.',
                  tag: 'diferencia abierta',
                  tone: visual.warning,
                  selected: value == PayrollVarianceDisposition.unresolved,
                  onSelect: enabled
                      ? () => onChanged(PayrollVarianceDisposition.unresolved)
                      : null,
                ),
                if (onAcceptRounding != null)
                  PayrollSoftAction(
                    label: 'Aceptar como redondeo '
                        '(+${formatPayrollClp(varianceClp.abs())})',
                    onTap: enabled ? onAcceptRounding : null,
                    height: 34,
                  ),
              ],
            ),
          const SizedBox(height: 7),
          Text(
            isPartial
                ? 'Este abono no cambia las horas ni el total de la semana. '
                    'Sólo reduce el saldo por pagar.'
                : 'Una diferencia bancaria no crea un anticipo. Si hubo dinero '
                    'adelantado, regístralo desde la fila de la persona.',
            style: visual.bodyS.copyWith(
              fontSize: 10,
              color: visual.warningFg,
            ),
          ),
        ],
      ),
    );
  }
}

class _Explanations extends StatelessWidget {
  const _Explanations({required this.explanations});

  final List<String> explanations;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final explanation in explanations)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5, right: 7),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: visual.inkFaint,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    explanation,
                    style: visual.bodyS.copyWith(
                      fontSize: 10.5,
                      color: visual.inkMuted,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, this.emphasis = false});

  final String label;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = emphasis ? visual.warning : visual.neutral;
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
}
