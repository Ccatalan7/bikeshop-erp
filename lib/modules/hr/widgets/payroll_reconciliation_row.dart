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
    PayrollCandidateReason.paymentMethodIsTransfer =>
      'La persona cobra por transferencia',
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
    PayrollCandidateReason.transactionMatchesMultipleLines =>
      'Este movimiento calza con más de una persona',
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
      'El movimiento calza con más de una persona',
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

/// One reviewable item, rendered as a single decision.
///
/// The proposal, its reasons and the difference are shown; the row never
/// applies anything by itself and never offers to change hours or rate to make
/// a difference disappear.
class PayrollReconciliationRow extends StatefulWidget {
  const PayrollReconciliationRow({
    super.key,
    required this.data,
    required this.disposition,
    required this.onDisposition,
    required this.varianceDisposition,
    required this.onVarianceDisposition,
    this.reviewReason = '',
    this.onReviewReasonChanged,
    this.onManualMatchChanged,
    this.learnBeneficiaryAlias = false,
    this.onLearnBeneficiaryAliasChanged,
    this.isFirst = false,
    this.enabled = true,
  });

  static const double stackWidth = 600;

  final PayrollDecisionRowData data;
  final PayrollRowDisposition disposition;
  final ValueChanged<PayrollRowDisposition> onDisposition;
  final PayrollVarianceDisposition varianceDisposition;
  final ValueChanged<PayrollVarianceDisposition> onVarianceDisposition;
  final String reviewReason;
  final ValueChanged<String>? onReviewReasonChanged;
  final ValueChanged<String?>? onManualMatchChanged;
  final bool learnBeneficiaryAlias;
  final ValueChanged<bool>? onLearnBeneficiaryAliasChanged;

  final bool isFirst;
  final bool enabled;

  @override
  State<PayrollReconciliationRow> createState() =>
      _PayrollReconciliationRowState();
}

class _PayrollReconciliationRowState extends State<PayrollReconciliationRow> {
  late final TextEditingController _reasonController =
      TextEditingController(text: widget.reviewReason);

  PayrollDecisionRowData get data => widget.data;
  PayrollRowDisposition get disposition => widget.disposition;
  bool get enabled => widget.enabled;
  bool get isFirst => widget.isFirst;
  ValueChanged<PayrollRowDisposition> get onDisposition => widget.onDisposition;
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
  void didUpdateWidget(covariant PayrollReconciliationRow oldWidget) {
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

  List<PayrollRowDisposition> get _options {
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

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final needsAnswer = data.requiresDisposition &&
        disposition == PayrollRowDisposition.pending;
    final options = data.canConfirm
        ? const [
            PayrollRowDisposition.confirm,
            PayrollRowDisposition.hold,
            PayrollRowDisposition.notPayroll,
            PayrollRowDisposition.ignore,
          ]
        : _options;

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          data.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: visual.cardTitle.copyWith(fontSize: 13),
        ),
        if (data.subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            data.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: visual.bodyS.copyWith(
              fontSize: 11,
              color: visual.inkMuted,
            ),
          ),
        ],
        if (data.bankDescription.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            data.bankDescription,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: visual.monoM.copyWith(
              fontSize: 11.5,
              color: visual.inkMuted,
              height: 1.35,
            ),
          ),
        ],
        const SizedBox(height: 7),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (data.date != null) _MetaChip(label: _formatDate(data.date!)),
            if (data.confidence != null)
              _MetaChip(label: payrollConfidenceLabel(data.confidence!)),
            if (data.isPartialPayment)
              const _MetaChip(
                label: 'Pago parcial',
                emphasis: true,
              ),
            if (data.isAutomaticallyClassified)
              const _MetaChip(label: 'Clasificado automáticamente'),
            if (needsAnswer)
              const _MetaChip(
                label: 'Necesita respuesta',
                emphasis: true,
              ),
            if (data.warningCodes.contains('out_of_statement_range'))
              const _MetaChip(
                label: 'Fecha posterior al cierre declarado',
                emphasis: true,
              ),
            if (!data.canConfirm &&
                data.kind == PayrollDecisionRowKind.alreadyResolvedMovement)
              const _MetaChip(
                label: 'Protegido contra pago duplicado',
                emphasis: true,
              ),
          ],
        ),
      ],
    );

    final amounts = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: data.isPartialPayment
          ? [
              _AmountLine(
                label: 'Saldo antes',
                value: formatPayrollClp(data.expectedAmountClp!),
              ),
              _AmountLine(
                label: 'Pago aplicado',
                value: formatPayrollClp(data.appliedAmountClp!),
                emphasis: true,
              ),
              _AmountLine(
                label: 'Saldo después',
                value: formatPayrollClp(data.remainingAmountClp!),
                attention: true,
              ),
            ]
          : [
              if (data.bankAmountClp != null)
                _AmountLine(
                  label: 'Banco',
                  value: formatPayrollClp(data.bankAmountClp!),
                  emphasis: true,
                ),
              if (data.expectedAmountClp != null)
                _AmountLine(
                  label: 'Esperado',
                  value: formatPayrollClp(data.expectedAmountClp!),
                ),
              if (data.hasVariance)
                _AmountLine(
                  label: 'Diferencia',
                  value: formatPayrollClpSigned(data.varianceClp!),
                  attention: true,
                ),
            ],
    );

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: isFirst ? BorderSide.none : BorderSide(color: visual.border),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < PayrollReconciliationRow.stackWidth;
          final head = stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    identity,
                    const SizedBox(height: 9),
                    Align(alignment: Alignment.centerLeft, child: amounts),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: identity),
                    const SizedBox(width: 14),
                    Expanded(flex: 3, child: amounts),
                  ],
                );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              head,
              if (data.explanations.isNotEmpty) ...[
                const SizedBox(height: 9),
                _Explanations(explanations: data.explanations),
              ],
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
              if (options.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('QUÉ ES ESTE MOVIMIENTO', style: visual.overline),
                const SizedBox(height: 8),
                _DecisionOptionGrid(
                  movementId: data.id,
                  options: options,
                  kind: data.kind,
                  disposition: disposition,
                  enabled: enabled,
                  onDisposition: onDisposition,
                ),
              ],
              if (data.hasVariance &&
                  disposition == PayrollRowDisposition.confirm) ...[
                const SizedBox(height: 12),
                _VarianceDisposition(
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

  static String _formatDate(PayrollCivilDate date) {
    const months = [
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
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

/// Equal-width 2c option cards on wide layouts; a stacked full-width list on
/// compact ones. Geometry adapts, the graphic language does not.
class _DecisionOptionGrid extends StatelessWidget {
  const _DecisionOptionGrid({
    required this.movementId,
    required this.options,
    required this.kind,
    required this.disposition,
    required this.enabled,
    required this.onDisposition,
  });

  final String movementId;
  final List<PayrollRowDisposition> options;
  final PayrollDecisionRowKind kind;
  final PayrollRowDisposition disposition;
  final bool enabled;
  final ValueChanged<PayrollRowDisposition> onDisposition;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640 && options.length > 1;
        final cards = <Widget>[
          for (final option in options)
            PayrollDecisionOptionCard(
              movementId: movementId,
              optionName: option.name,
              title: option.label,
              description: option.describe(kind),
              tag: option.consequenceTag,
              tone: option.toneOf(visual),
              selected: disposition == option,
              onSelect: enabled ? () => onDisposition(option) : null,
            ),
        ];
        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var index = 0; index < cards.length; index++) ...<Widget>[
                if (index != 0) const SizedBox(height: 8),
                cards[index],
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (var index = 0; index < cards.length; index++) ...<Widget>[
              if (index != 0) const SizedBox(width: 10),
              Expanded(child: cards[index]),
            ],
          ],
        );
      },
    );
  }
}

class _VarianceDisposition extends StatelessWidget {
  const _VarianceDisposition({
    required this.varianceClp,
    required this.appliedAmountClp,
    required this.value,
    required this.onChanged,
    required this.enabled,
    this.onAcceptRounding,
  });

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

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.attention = false,
  });

  final String label;
  final String value;
  final bool emphasis;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: visual.bodyS.copyWith(
              fontSize: 10,
              color: visual.inkFaint,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            value,
            style: payrollMoneyTextStyle(context, emphasis: emphasis).copyWith(
              fontSize: emphasis ? 15 : 13.5,
              // The warning foreground is the attention role of the mounted
              // palette; it stays legible over the plain row surface.
              color: attention ? visual.warningFg : visual.ink,
            ),
          ),
        ],
      ),
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
