import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:uuid/uuid.dart';

import '../../../../shared/utils/responsive_viewport.dart';
import '../../../../shared/widgets/vb_money_text.dart';
import '../../../../shared/widgets/vb_notice.dart';
import '../../../../shared/widgets/vb_searchable_select.dart';
import '../../../../shared/widgets/vb_short_select.dart';
import '../../../../shared/widgets/vb_status_badge.dart';
import '../../models/payroll_statement_reconciliation.dart';
import '../../widgets/payroll_format.dart';
import '../../widgets/payroll_payment_sheet.dart'
    show ClpAmountInputFormatter, parsePayrollAmount;
import '../surfaces/payroll_accent_action.dart';
import '../surfaces/payroll_person_avatar.dart';
import '../theme/payroll_tokens.dart';
import 'payroll_payment_workspace_controller.dart';
import 'payroll_payment_workspace_models.dart';

/// Canonical payment editor used by both the queue side sheet and OCR batch.
/// The host chooses the scope; everything below the target selector is the
/// exact same editor/controller and the exact same save command.
class PayrollPaymentWorkspace extends StatefulWidget {
  const PayrollPaymentWorkspace({
    super.key,
    required this.controller,
    required this.onClose,
    this.onBatchComplete,
    this.expenseAccounts = const <PayrollExpenseAccountOption>[],
  });

  final PayrollPaymentWorkspaceController controller;
  final VoidCallback onClose;
  final VoidCallback? onBatchComplete;
  final List<PayrollExpenseAccountOption> expenseAccounts;

  @override
  State<PayrollPaymentWorkspace> createState() =>
      _PayrollPaymentWorkspaceState();
}

class _PayrollPaymentWorkspaceState extends State<PayrollPaymentWorkspace> {
  String? _error;
  bool _committedUnverified = false;
  bool _hasInlineEditor = false;
  String? _expandedTargetId;

  PayrollPaymentWorkspaceController get _controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (_controller.request.mode == PayrollPaymentWorkspaceMode.batch) {
          return _buildBatch(context);
        }
        final target = _controller.selectedTarget;
        final draft = _controller.draftFor(target.targetId);
        final validation = _controller.validationFor(target.targetId);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WorkspaceHeader(
              request: _controller.request,
              onClose: _requestClose,
            ),
            Expanded(
              child: _TargetEditor(
                key: ValueKey<String>(
                  'payroll-payment-target-editor-${target.targetId}',
                ),
                controller: _controller,
                target: target,
                draft: draft,
                validation: validation,
                expenseAccounts: widget.expenseAccounts,
                editable: !draft.isSaved,
                onError: (message) => setState(() => _error = message),
                onInlineEditingChanged: _setInlineEditing,
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: VbNotice(
                  tone: _committedUnverified
                      ? VbNoticeTone.warning
                      : VbNoticeTone.danger,
                  title: _error!,
                ),
              ),
            _WorkspaceFooter(
              draft: draft,
              validation: validation,
              saving: _controller.isSaving(target.targetId),
              editorActive: _hasInlineEditor,
              onSave: () => _save(target.targetId),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBatch(BuildContext context) {
    final request = _controller.request;
    final invalidCount = request.targets
        .where(
          (target) => !_controller.validationFor(target.targetId).isValid,
        )
        .length;
    return Column(
      key: const ValueKey<String>('payroll-payment-batch-workspace'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.separated(
            key: const ValueKey<String>('payroll-payment-batch-list'),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            itemCount: request.groups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final group = request.groups[index];
              return _BatchWeekGroup(
                key: ValueKey<String>(
                  'payroll-payment-week-${group.voucherId}',
                ),
                controller: _controller,
                group: group,
                expenseAccounts: widget.expenseAccounts,
                expandedTargetId: _expandedTargetId,
                editorActive: _hasInlineEditor,
                onToggleDetails: (targetId) {
                  if (_hasInlineEditor) {
                    setState(() {
                      _error = 'Termina o cancela la edición abierta antes '
                          'de cerrar el detalle o cambiar de trabajador.';
                    });
                    return;
                  }
                  setState(() {
                    _error = null;
                    _expandedTargetId =
                        _expandedTargetId == targetId ? null : targetId;
                  });
                },
                onError: (message) => setState(() {
                  _committedUnverified = false;
                  _error = message;
                }),
                onInlineEditingChanged: _setInlineEditing,
              );
            },
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: VbNotice(
              tone: _committedUnverified
                  ? VbNoticeTone.warning
                  : VbNoticeTone.danger,
              title: _error!,
            ),
          ),
        _BatchWorkspaceFooter(
          controller: _controller,
          invalidCount: invalidCount,
          editorActive: _hasInlineEditor,
          onBack: _requestClose,
          onApproveWeeks: _approveWeeks,
          onSave: _saveBatch,
          onComplete: widget.onBatchComplete ?? widget.onClose,
        ),
      ],
    );
  }

  void _setInlineEditing(bool active) {
    if (!mounted || _hasInlineEditor == active) return;
    setState(() => _hasInlineEditor = active);
  }

  Future<void> _save(String targetId) async {
    setState(() {
      _error = null;
      _committedUnverified = false;
    });
    try {
      await _controller.saveTarget(targetId);
    } on PayrollPaymentWorkspaceValidationException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } on PayrollPaymentWorkspaceSaveException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on PayrollPaymentCommittedUnverifiedException {
      if (!mounted) return;
      setState(() {
        _committedUnverified = true;
        _error = 'El servidor registró este pago, pero la app no pudo '
            'verificar el comprobante final. No vuelvas a registrarlo; '
            'cierra este panel y revisa Nóminas.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos registrar este pago. Puedes reintentar sin '
            'duplicarlo.';
      });
    }
  }

  Future<void> _saveBatch() async {
    setState(() {
      _error = null;
      _committedUnverified = false;
    });
    try {
      await _controller.saveBatch();
    } on PayrollPaymentWorkspaceValidationException catch (error) {
      if (!mounted) return;
      setState(() {
        _expandedTargetId = error.validation.targetId;
        _error = error.toString();
      });
    } on PayrollPaymentWorkspaceSaveException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on PayrollPaymentCommittedUnverifiedException {
      if (!mounted) return;
      setState(() {
        _committedUnverified = true;
        _error = 'El servidor registró los pagos, pero la app no pudo '
            'verificar el comprobante final. No vuelvas a registrarlos; '
            'cierra este panel y revisa Nóminas.';
      });
    } catch (error, stackTrace) {
      debugPrint('Payroll batch save failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos registrar el lote. Puedes reintentar la misma '
            'operación sin duplicar pagos.';
      });
    }
  }

  Future<void> _approveWeeks() async {
    setState(() {
      _error = null;
      _committedUnverified = false;
    });
    try {
      await _controller.approveRemainingWeeks();
    } on PayrollPaymentWorkspaceSaveException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos aprobar las semanas. Ninguna quedó aprobada; '
            'puedes reintentar la misma operación.';
      });
    }
  }

  Future<void> _requestClose() async {
    final dirty = _hasInlineEditor ||
        _controller.request.targets.any(
          (target) => _controller.isDirty(target.targetId),
        );
    if (!dirty) {
      widget.onClose();
      return;
    }
    final discard = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('¿Cerrar el panel de pago?'),
            content: const Text(
              'Hay cambios de pago que todavía no se han registrado.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Seguir editando'),
              ),
              // accent-fill: dialog-action
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Descartar cambios'),
              ),
            ],
          ),
        ) ??
        false;
    if (discard && mounted) widget.onClose();
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.request, required this.onClose});

  final PayrollPaymentWorkspaceRequest request;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final batch = request.mode == PayrollPaymentWorkspaceMode.batch;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
      decoration: BoxDecoration(
        color: visual.shell,
        border: Border(bottom: BorderSide(color: visual.shellEdge)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  batch ? 'PREPARAR PAGOS DE NÓMINA' : 'PAGO DE NÓMINA',
                  style: visual.overline.copyWith(color: visual.onShellMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  batch
                      ? '${request.groups.length} semanas · '
                          '${request.targets.length} trabajadores'
                      : 'Una semana · un trabajador',
                  style: visual.moduleTitle,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onClose,
            icon: Icon(Icons.close_rounded, color: visual.onShell),
          ),
        ],
      ),
    );
  }
}

class _BatchWeekGroup extends StatelessWidget {
  const _BatchWeekGroup({
    super.key,
    required this.controller,
    required this.group,
    required this.expenseAccounts,
    required this.expandedTargetId,
    required this.editorActive,
    required this.onToggleDetails,
    required this.onError,
    required this.onInlineEditingChanged,
  });

  final PayrollPaymentWorkspaceController controller;
  final PayrollPaymentWeekGroup group;
  final List<PayrollExpenseAccountOption> expenseAccounts;
  final String? expandedTargetId;
  final bool editorActive;
  final ValueChanged<String> onToggleDetails;
  final ValueChanged<String> onError;
  final ValueChanged<bool> onInlineEditingChanged;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final total = group.targets.fold<int>(
      0,
      (sum, target) =>
          sum + controller.validationFor(target.targetId).totalObligationClp,
    );
    final liveTargets = group.targets
        .map((target) => controller.targetById(target.targetId))
        .toList(growable: false);
    final approved = liveTargets.every(
      (target) => const <String>{'confirmed', 'partial'}
          .contains(target.voucherStatus.trim().toLowerCase()),
    );
    return Container(
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
            color: visual.surfaceSunken,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Semana ${_isoWeek(group.periodStart)} · '
                        '${_range(group.periodStart, group.periodEnd)}',
                        style: visual.sectionTitle,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${group.targets.length} trabajadores',
                        style: visual.bodyS.copyWith(color: visual.inkFaint),
                      ),
                    ],
                  ),
                ),
                if (!approved) ...[
                  const VbStatusBadge(
                    label: 'Sin aprobar',
                    tone: VbStatusTone.warning,
                    dense: true,
                  ),
                  const SizedBox(width: 10),
                ],
                VbMoneyText(total),
              ],
            ),
          ),
          for (var index = 0; index < group.targets.length; index++) ...[
            if (index > 0) Divider(height: 1, color: visual.border),
            _BatchTargetRow(
              controller: controller,
              target: group.targets[index],
              expenseAccounts: expenseAccounts,
              expanded: expandedTargetId == group.targets[index].targetId,
              detailsEnabled: !editorActive,
              onToggleDetails: () =>
                  onToggleDetails(group.targets[index].targetId),
              onError: onError,
              onInlineEditingChanged: onInlineEditingChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _BatchTargetRow extends StatelessWidget {
  const _BatchTargetRow({
    required this.controller,
    required this.target,
    required this.expenseAccounts,
    required this.expanded,
    required this.detailsEnabled,
    required this.onToggleDetails,
    required this.onError,
    required this.onInlineEditingChanged,
  });

  final PayrollPaymentWorkspaceController controller;
  final PayrollPaymentTarget target;
  final List<PayrollExpenseAccountOption> expenseAccounts;
  final bool expanded;
  final bool detailsEnabled;
  final VoidCallback onToggleDetails;
  final ValueChanged<String> onError;
  final ValueChanged<bool> onInlineEditingChanged;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final draft = controller.draftFor(target.targetId);
    final hasManualAdjustments =
        controller.hasManualAdjustments(target.targetId);
    final validation = controller.validationFor(target.targetId);
    final paymentLegs = draft.salaryLegs
        .where((leg) => leg.kind == PayrollPaymentLegKind.payment)
        .toList(growable: false);
    final simple = draft.salaryLegs.length == 1 && paymentLegs.length == 1;
    final currentMethod =
        simple ? paymentLegs.single.paymentMethodId?.trim() ?? '' : '';
    final methods = controller.request.paymentMethods
        .where((method) => method.isActive)
        .toList(growable: false);
    final evidence = paymentLegs
        .where((leg) => leg.ocrEvidence != null)
        .map((leg) => leg.ocrEvidence!)
        .firstOrNull;
    final wide =
        ResponsiveViewport.widthOf(context) >= ResponsiveViewport.desktopMin;

    final identity = Row(
      children: [
        PayrollPersonAvatar(
          personId: target.employeeId,
          initials: _initials(target.employeeName),
          size: 30,
          fontSize: 9.5,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(target.employeeName, style: visual.labelStrong),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (evidence != null) ...[
                    KeyedSubtree(
                      key: ValueKey<String>(
                        'payroll-payment-ocr-prefill-${target.targetId}',
                      ),
                      child: const VbStatusBadge(
                        label: 'Desde cartola',
                        tone: VbStatusTone.success,
                        dense: true,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      evidence == null
                          ? 'Sin movimiento de cartola preseleccionado'
                          : '${VbMoneyText.formatClp(evidence.amountClp)} · '
                              '${evidence.description}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: visual.bodyS.copyWith(color: visual.inkFaint),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final money = _BatchMoneySummary(
      pendingClp: validation.totalObligationClp,
      appliedClp: validation.appliedTotalClp,
      remainingClp: validation.remainingClp,
    );

    final method = methods.isEmpty
        ? Text('Sin métodos disponibles', style: visual.bodyS)
        : simple
            ? VbShortSelect<String>(
                key: ValueKey<String>(
                  'payroll-payment-method-${target.targetId}',
                ),
                value: currentMethod,
                options: [
                  for (final option in methods)
                    VbShortSelectOption<String>(
                      value: option.methodId,
                      label: option.label,
                    ),
                ],
                onChanged: draft.isSaved || controller.isSavingBatch
                    ? null
                    : (value) => controller.setSimplePaymentMethod(
                        target.targetId, value),
                sheetTitle: 'Método de ${target.employeeName}',
                semanticLabel: 'Método de pago de ${target.employeeName}',
              )
            : Text(
                '${draft.salaryLegs.length} formas de pago',
                key: ValueKey<String>(
                  'payroll-payment-method-${target.targetId}',
                ),
                style: visual.labelStrong,
              );

    final details = TextButton.icon(
      key: ValueKey<String>(
        'payroll-payment-details-${target.targetId}',
      ),
      onPressed: detailsEnabled ? onToggleDetails : null,
      icon: Icon(
        expanded ? Icons.expand_less_rounded : Icons.tune_rounded,
      ),
      label: Text(
        expanded
            ? 'Cerrar detalle'
            : hasManualAdjustments
                ? 'Editar ajuste'
                : 'Dividir o ajustar',
      ),
    );

    return Container(
      key: ValueKey<String>('payroll-payment-row-${target.targetId}'),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              children: [
                Expanded(flex: 5, child: identity),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: method),
                const SizedBox(width: 16),
                Expanded(flex: 5, child: money),
                const SizedBox(width: 8),
                details,
              ],
            )
          else ...[
            identity,
            const SizedBox(height: 9),
            money,
            const SizedBox(height: 8),
            if (ResponsiveViewport.widthOf(context) <
                ResponsiveViewport.phoneMaxExclusive) ...[
              method,
              Align(alignment: Alignment.centerRight, child: details),
            ] else
              Row(
                children: [
                  Expanded(child: method),
                  const SizedBox(width: 8),
                  details,
                ],
              ),
          ],
          if (!validation.isValid) ...[
            const SizedBox(height: 7),
            Text(
              validation.issues.first.message,
              style: visual.bodyS.copyWith(color: visual.warningFg),
            ),
          ],
          if (expanded) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: visual.border),
            _TargetEditor(
              key: ValueKey<String>(
                'payroll-payment-target-editor-${target.targetId}',
              ),
              controller: controller,
              target: target,
              draft: draft,
              validation: validation,
              expenseAccounts: expenseAccounts,
              editable: !draft.isSaved,
              embedded: true,
              showIdentityHeader: false,
              onError: onError,
              onInlineEditingChanged: onInlineEditingChanged,
            ),
          ],
        ],
      ),
    );
  }
}

class _BatchMoneySummary extends StatelessWidget {
  const _BatchMoneySummary({
    required this.pendingClp,
    required this.appliedClp,
    required this.remainingClp,
  });

  final int pendingClp;
  final int appliedClp;
  final int remainingClp;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: _BatchMoneyValue(
            label: 'A PAGAR',
            amountClp: pendingClp,
          ),
        ),
        Expanded(
          child: _BatchMoneyValue(
            label: 'APLICADO',
            amountClp: appliedClp,
          ),
        ),
        Expanded(
          child: _BatchMoneyValue(
            label: 'PENDIENTE',
            amountClp: remainingClp,
          ),
        ),
      ],
    );
  }
}

class _BatchMoneyValue extends StatelessWidget {
  const _BatchMoneyValue({
    required this.label,
    required this.amountClp,
  });

  final String label;
  final int amountClp;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: visual.overline),
        const SizedBox(height: 2),
        VbMoneyText(amountClp),
      ],
    );
  }
}

class _BatchWorkspaceFooter extends StatelessWidget {
  const _BatchWorkspaceFooter({
    required this.controller,
    required this.invalidCount,
    required this.editorActive,
    required this.onBack,
    required this.onApproveWeeks,
    required this.onSave,
    required this.onComplete,
  });

  final PayrollPaymentWorkspaceController controller;
  final int invalidCount;
  final bool editorActive;
  final VoidCallback onBack;
  final VoidCallback onApproveWeeks;
  final VoidCallback onSave;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final compact = ResponsiveViewport.widthOf(context) <
        ResponsiveViewport.phoneMaxExclusive;
    final count = controller.request.targets.length;
    final total = controller.request.targets.fold<int>(
      0,
      (sum, target) =>
          sum + controller.validationFor(target.targetId).totalObligationClp,
    );
    final saved = controller.isBatchSaved;
    final unapprovedWeeks = controller.unapprovedWeekCount;
    final status = saved
        ? '$count pagos registrados'
        : unapprovedWeeks > 0
            ? '$unapprovedWeeks ${unapprovedWeeks == 1 ? 'semana sin aprobar' : 'semanas sin aprobar'}'
            : invalidCount == 0
                ? '$count pagos listos · ${VbMoneyText.formatClp(total)}'
                : '$invalidCount trabajadores necesitan revisión';
    final approveAction = unapprovedWeeks > 0
        ? PayrollAccentAction(
            actionKey: const ValueKey<String>('payroll-payment-approve-weeks'),
            label: 'Aprobar $unapprovedWeeks '
                '${unapprovedWeeks == 1 ? 'semana' : 'semanas'}',
            enabled: !controller.isApprovingWeeks &&
                !controller.isSavingBatch &&
                !editorActive,
            busy: controller.isApprovingWeeks,
            onTap: onApproveWeeks,
            minHeight: 38,
          )
        : null;
    final saveAction = PayrollAccentAction(
      actionKey: const ValueKey<String>('payroll-payment-save-batch'),
      label: saved ? 'Volver a Nóminas' : 'Registrar $count pagos',
      enabled: saved ||
          (controller.canSaveBatch &&
              !controller.isSavingBatch &&
              !controller.isApprovingWeeks &&
              !editorActive),
      busy: controller.isSavingBatch,
      onTap: saved ? onComplete : onSave,
      minHeight: 38,
    );
    final actions = <Widget>[
      OutlinedButton(
        onPressed: controller.isSavingBatch || controller.isApprovingWeeks
            ? null
            : onBack,
        child: Text(saved ? 'Cerrar' : 'Volver a propuestas'),
      ),
      const SizedBox(width: 8),
      if (approveAction != null) ...[
        approveAction,
        const SizedBox(width: 8),
      ],
      saveAction,
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: visual.surfaceOverlay,
        border: Border(top: BorderSide(color: visual.border)),
        boxShadow: visual.moneyBar,
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(status, style: visual.bodyS),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed:
                      controller.isSavingBatch || controller.isApprovingWeeks
                          ? null
                          : onBack,
                  child: Text(saved ? 'Cerrar' : 'Volver a propuestas'),
                ),
                const SizedBox(height: 8),
                if (approveAction != null) ...[
                  approveAction,
                  const SizedBox(height: 8),
                ],
                saveAction,
              ],
            )
          : Row(
              children: [
                Expanded(child: Text(status, style: visual.bodyS)),
                ...actions,
              ],
            ),
    );
  }
}

class _TargetEditor extends StatefulWidget {
  const _TargetEditor({
    super.key,
    required this.controller,
    required this.target,
    required this.draft,
    required this.validation,
    required this.expenseAccounts,
    required this.editable,
    required this.onError,
    required this.onInlineEditingChanged,
    this.embedded = false,
    this.showIdentityHeader = true,
  });

  final PayrollPaymentWorkspaceController controller;
  final PayrollPaymentTarget target;
  final PayrollPaymentTargetDraft draft;
  final PayrollPaymentTargetValidation validation;
  final List<PayrollExpenseAccountOption> expenseAccounts;
  final bool editable;
  final ValueChanged<String> onError;
  final ValueChanged<bool> onInlineEditingChanged;
  final bool embedded;
  final bool showIdentityHeader;

  @override
  State<_TargetEditor> createState() => _TargetEditorState();
}

class _TargetEditorState extends State<_TargetEditor> {
  _InlineEditorSession? _inlineEditor;
  final GlobalKey _inlineEditorViewportKey = GlobalKey();
  int _editorEpoch = 0;
  bool _inlineEditorTransitionPending = false;

  PayrollPaymentWorkspaceController get controller => widget.controller;
  PayrollPaymentTarget get target => widget.target;
  PayrollPaymentTargetDraft get draft => widget.draft;
  PayrollPaymentTargetValidation get validation => widget.validation;
  List<PayrollExpenseAccountOption> get expenseAccounts =>
      widget.expenseAccounts;
  bool get editable => widget.editable;
  ValueChanged<String> get onError => widget.onError;

  @override
  void dispose() {
    final releaseParentLock =
        _inlineEditor != null || _inlineEditorTransitionPending;
    final onInlineEditingChanged = widget.onInlineEditingChanged;
    if (releaseParentLock) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onInlineEditingChanged(false);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final canStartEditor = editable && _inlineEditor == null;
    return ListView(
      key: ValueKey<String>('payroll-payment-editor-${target.targetId}'),
      shrinkWrap: widget.embedded,
      primary: !widget.embedded,
      physics: widget.embedded
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
      children: [
        if (widget.showIdentityHeader) ...[
          Row(
            children: [
              PayrollPersonAvatar(
                personId: target.employeeId,
                initials: _initials(target.employeeName),
                size: 34,
                fontSize: 10.5,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(target.employeeName, style: visual.sectionTitle),
                    const SizedBox(height: 2),
                    Text(
                      'Semana ${_isoWeek(target.periodStart)} · '
                      '${_range(target.periodStart, target.periodEnd)}',
                      style: visual.bodyS.copyWith(color: visual.inkFaint),
                    ),
                  ],
                ),
              ),
              if (draft.isSaved)
                Text('GUARDADO',
                    style: visual.overline.copyWith(
                      color: visual.successFg,
                    )),
            ],
          ),
          const SizedBox(height: 12),
        ],
        _MoneySummary(draft: draft, validation: validation),
        if (!editable) ...[
          const SizedBox(height: 12),
          const VbNotice(
            tone: VbNoticeTone.success,
            title: 'Pago guardado',
            body: 'Para registrar otro pago, cierra este panel y vuelve a '
                'abrirlo desde el saldo actualizado.',
          ),
        ],
        const SizedBox(height: 16),
        _SectionHeader(
          title: 'Cómo se paga el sueldo',
          actionLabel: 'Agregar parte',
          onAction: canStartEditor ? () => _addSalaryPayment(context) : null,
        ),
        if (_inlineEditor?.kind == _InlineEditorKind.salaryLeg) ...[
          const SizedBox(height: 7),
          _buildInlineEditor(context, _inlineEditor!),
        ],
        const SizedBox(height: 7),
        if (draft.salaryLegs.isEmpty)
          const VbNotice(
            tone: VbNoticeTone.neutral,
            title: 'Todavía no agregas ninguna parte del pago',
          )
        else
          for (final leg in draft.salaryLegs) ...[
            _PaymentLegTile(
              leg: leg,
              methods: controller.request.paymentMethods,
              onEdit:
                  canStartEditor && leg.kind == PayrollPaymentLegKind.payment
                      ? () => _editSalaryPayment(context, leg)
                      : null,
              onRemove: canStartEditor
                  ? () => controller.removeSalaryLeg(target.targetId, leg.legId)
                  : null,
            ),
            const SizedBox(height: 7),
          ],
        if (target.availableAdvances.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Anticipos disponibles', style: visual.cardTitle),
          const SizedBox(height: 6),
          if (_inlineEditor?.kind == _InlineEditorKind.advance) ...[
            _buildInlineEditor(context, _inlineEditor!),
            const SizedBox(height: 7),
          ],
          for (final advance in target.availableAdvances)
            _AdvanceTile(
              advance: advance,
              selectedLeg: draft.salaryLegs
                  .where((leg) =>
                      leg.kind == PayrollPaymentLegKind.advance &&
                      leg.advanceId == advance.advanceId)
                  .firstOrNull,
              onToggle: !canStartEditor
                  ? null
                  : (selectedLeg) {
                      if (selectedLeg != null) {
                        controller.toggleAdvance(
                          target.targetId,
                          advance.advanceId,
                        );
                        return;
                      }
                      final remaining = validation.payrollRemainingClp;
                      if (remaining <= 0) {
                        onError(
                            'El sueldo ya está cubierto. Quita o reduce otra '
                            'parte antes de aplicar este anticipo.');
                        return;
                      }
                      controller.toggleAdvance(
                        target.targetId,
                        advance.advanceId,
                        amountClp: advance.availableAmountClp < remaining
                            ? advance.availableAmountClp
                            : remaining,
                      );
                    },
              onEdit: canStartEditor
                  ? (selectedLeg) => _editAdvance(context, advance, selectedLeg)
                  : null,
            ),
        ],
        const SizedBox(height: 16),
        _SectionHeader(
          title: 'Conceptos del pago',
          actionLabel: 'Agregar concepto',
          onAction: !canStartEditor
              ? null
              : expenseAccounts.isEmpty
                  ? () => onError(
                        'No hay cuentas de gasto disponibles para agregar un '
                        'concepto separado del sueldo.',
                      )
                  : () => _addConcept(context),
        ),
        const SizedBox(height: 4),
        Text(
          'Separa reembolsos y otros gastos para contabilizarlos correctamente, '
          'ya estén incluidos en la nómina o se sumen al pago.',
          style: visual.bodyS.copyWith(color: visual.inkFaint),
        ),
        const SizedBox(height: 7),
        if (_inlineEditor?.kind == _InlineEditorKind.concept) ...[
          _buildInlineEditor(context, _inlineEditor!),
          const SizedBox(height: 7),
        ],
        for (final concept in draft.additionalConcepts) ...[
          _ConceptTile(
            concept: concept,
            methods: controller.request.paymentMethods,
            onEdit:
                canStartEditor ? () => _editConcept(context, concept) : null,
            onRemove: canStartEditor
                ? () => controller.removeConcept(
                      target.targetId,
                      concept.conceptId,
                    )
                : null,
            onAddFunding: canStartEditor
                ? () => _addConceptFunding(context, concept)
                : null,
            onEditFunding: canStartEditor
                ? (leg) => _editConceptFunding(context, concept, leg)
                : null,
            onRemoveFunding: canStartEditor
                ? (leg) => controller.removeConceptPaymentLeg(
                      target.targetId,
                      concept.conceptId,
                      leg.legId,
                    )
                : null,
          ),
          if (_inlineEditor?.kind == _InlineEditorKind.conceptFunding &&
              _inlineEditor?.concept?.conceptId == concept.conceptId) ...[
            const SizedBox(height: 7),
            _buildInlineEditor(context, _inlineEditor!),
          ],
          const SizedBox(height: 7),
        ],
        if (validation.issues.isNotEmpty) ...[
          const SizedBox(height: 8),
          VbNotice(
            tone: VbNoticeTone.warning,
            title: validation.issues.first.message,
          ),
        ],
      ],
    );
  }

  Future<void> _addSalaryPayment(BuildContext context) async {
    final remaining = validation.payrollRemainingClp;
    if (_usesInlineEditor(context)) {
      _openInlineEditor(
        _InlineEditorSession.salaryLeg(
          epoch: ++_editorEpoch,
          initialAmountClp: remaining,
        ),
      );
      return;
    }
    final leg = await showDialog<PayrollPaymentLeg>(
      context: context,
      builder: (_) => _PaymentLegDialog(
        methods: controller.request.paymentMethods,
        initialAmountClp: remaining,
        initialMethodId: target.preferredPaymentMethodId,
        evidenceChoices: _evidenceChoices(),
        allowPayrollReferenceFallback: true,
      ),
    );
    if (leg != null) controller.addPaymentLeg(target.targetId, leg);
  }

  Future<void> _editSalaryPayment(
    BuildContext context,
    PayrollPaymentLeg leg,
  ) async {
    if (_usesInlineEditor(context)) {
      _openInlineEditor(
        _InlineEditorSession.salaryLeg(
          epoch: ++_editorEpoch,
          initialLeg: leg,
        ),
      );
      return;
    }
    final edited = await showDialog<PayrollPaymentLeg>(
      context: context,
      builder: (_) => _PaymentLegDialog(
        methods: controller.request.paymentMethods,
        initial: leg,
        evidenceChoices: _evidenceChoices(editing: leg),
        allowPayrollReferenceFallback: true,
      ),
    );
    if (edited != null) controller.updatePaymentLeg(target.targetId, edited);
  }

  Future<void> _addConcept(BuildContext context) async {
    if (_usesInlineEditor(context)) {
      _openInlineEditor(
        _InlineEditorSession.concept(epoch: ++_editorEpoch),
      );
      return;
    }
    final concept = await showDialog<PayrollAdditionalConcept>(
      context: context,
      builder: (_) => _ConceptDialog(
        expenseAccounts: expenseAccounts,
      ),
    );
    if (concept == null) return;
    controller.addConcept(target.targetId, concept);
    if (!context.mounted) return;
    await _addConceptFunding(context, concept);
  }

  Future<void> _editConcept(
    BuildContext context,
    PayrollAdditionalConcept concept,
  ) async {
    if (_usesInlineEditor(context)) {
      _openInlineEditor(
        _InlineEditorSession.concept(
          epoch: ++_editorEpoch,
          initialConcept: concept,
        ),
      );
      return;
    }
    final edited = await showDialog<PayrollAdditionalConcept>(
      context: context,
      builder: (_) => _ConceptDialog(
        expenseAccounts: expenseAccounts,
        initial: concept,
      ),
    );
    if (edited != null) controller.updateConcept(target.targetId, edited);
  }

  Future<void> _addConceptFunding(
    BuildContext context,
    PayrollAdditionalConcept concept,
  ) async {
    final funded = concept.paymentLegs.fold<int>(
      0,
      (sum, leg) => sum + leg.amountClp,
    );
    final remaining = concept.amountClp - funded;
    if (_usesInlineEditor(context)) {
      _openInlineEditor(
        _InlineEditorSession.conceptFunding(
          epoch: ++_editorEpoch,
          concept: concept,
          initialAmountClp: remaining > 0 ? remaining : 0,
        ),
      );
      return;
    }
    final leg = await showDialog<PayrollPaymentLeg>(
      context: context,
      builder: (_) => _PaymentLegDialog(
        methods: controller.request.paymentMethods,
        initialAmountClp: remaining > 0 ? remaining : 0,
        initialMethodId: target.preferredPaymentMethodId,
        evidenceChoices: _evidenceChoices(),
      ),
    );
    if (leg != null) {
      controller.addConceptPaymentLeg(
        target.targetId,
        concept.conceptId,
        leg,
      );
    }
  }

  Future<void> _editConceptFunding(
    BuildContext context,
    PayrollAdditionalConcept concept,
    PayrollPaymentLeg leg,
  ) async {
    if (_usesInlineEditor(context)) {
      _openInlineEditor(
        _InlineEditorSession.conceptFunding(
          epoch: ++_editorEpoch,
          concept: concept,
          initialLeg: leg,
        ),
      );
      return;
    }
    final edited = await showDialog<PayrollPaymentLeg>(
      context: context,
      builder: (_) => _PaymentLegDialog(
        methods: controller.request.paymentMethods,
        initial: leg,
        evidenceChoices: _evidenceChoices(editing: leg),
      ),
    );
    if (edited != null) {
      controller.updateConceptPaymentLeg(
        target.targetId,
        concept.conceptId,
        edited,
      );
    }
  }

  Future<void> _editAdvance(
    BuildContext context,
    PayrollAdvanceOption advance,
    PayrollPaymentLeg leg,
  ) async {
    if (_usesInlineEditor(context)) {
      _openInlineEditor(
        _InlineEditorSession.advance(
          epoch: ++_editorEpoch,
          advance: advance,
          initialLeg: leg,
        ),
      );
      return;
    }
    final amount = await showDialog<int>(
      context: context,
      builder: (_) => _AdvanceAmountDialog(
        initialAmountClp: leg.amountClp,
        maximumAmountClp: advance.availableAmountClp,
      ),
    );
    if (amount == null) return;
    controller.updateSalaryLeg(
      target.targetId,
      PayrollPaymentLeg.advance(
        legId: leg.legId,
        advanceId: advance.advanceId,
        amountClp: amount,
      ),
    );
  }

  bool _usesInlineEditor(BuildContext context) =>
      ResponsiveViewport.widthOf(context) >=
      ResponsiveViewport.phoneMaxExclusive;

  void _openInlineEditor(_InlineEditorSession editor) {
    if (!mounted) return;
    setState(() => _inlineEditor = editor);
    widget.onInlineEditingChanged(true);
    _ensureInlineEditorVisible();
  }

  void _replaceInlineEditor(_InlineEditorSession editor) {
    _transitionInlineEditor(editor);
  }

  void _closeInlineEditor() {
    _transitionInlineEditor(null);
  }

  void _transitionInlineEditor(_InlineEditorSession? nextEditor) {
    if (!mounted || _inlineEditorTransitionPending) return;
    final wasEditing = _inlineEditor != null;
    if (!wasEditing && nextEditor == null) return;

    // On macOS the platform text-input connection can still own the focused
    // EditableText during the pointer callback. Keep the form mounted for the
    // rest of this frame so that connection detaches before its controllers
    // are disposed or the next inline form replaces it.
    _inlineEditorTransitionPending = true;
    FocusManager.instance.primaryFocus?.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _inlineEditor = nextEditor;
        _inlineEditorTransitionPending = false;
      });
      final isEditing = nextEditor != null;
      if (wasEditing != isEditing) {
        widget.onInlineEditingChanged(isEditing);
      }
      if (isEditing) _ensureInlineEditorVisible();
    });
  }

  void _ensureInlineEditorVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final editorContext = _inlineEditorViewportKey.currentContext;
      if (editorContext == null) return;
      Scrollable.ensureVisible(
        editorContext,
        alignment: 0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildInlineEditor(
    BuildContext context,
    _InlineEditorSession editor,
  ) {
    switch (editor.kind) {
      case _InlineEditorKind.salaryLeg:
        final initial = editor.initialLeg;
        return _InlineEditorFrame(
          key: _inlineEditorViewportKey,
          editorKey:
              const ValueKey<String>('payroll-payment-inline-leg-editor'),
          title: initial == null ? 'Agregar parte' : 'Editar parte',
          onCancel: _closeInlineEditor,
          child: _PaymentLegForm(
            key: ValueKey<int>(editor.epoch),
            methods: controller.request.paymentMethods,
            evidenceChoices: _evidenceChoices(editing: initial),
            allowPayrollReferenceFallback: true,
            initial: initial,
            initialAmountClp: editor.initialAmountClp,
            initialMethodId: target.preferredPaymentMethodId,
            onCancel: _closeInlineEditor,
            onSubmit: (leg) {
              if (initial == null) {
                controller.addPaymentLeg(target.targetId, leg);
              } else {
                controller.updatePaymentLeg(target.targetId, leg);
              }
              _closeInlineEditor();
            },
          ),
        );
      case _InlineEditorKind.concept:
        final initial = editor.initialConcept;
        return _InlineEditorFrame(
          key: _inlineEditorViewportKey,
          editorKey:
              const ValueKey<String>('payroll-payment-inline-concept-editor'),
          title: initial == null
              ? 'Agregar concepto separado'
              : 'Editar concepto separado',
          onCancel: _closeInlineEditor,
          child: _ConceptForm(
            key: ValueKey<int>(editor.epoch),
            expenseAccounts: expenseAccounts,
            initial: initial,
            onCancel: _closeInlineEditor,
            onSubmit: (concept) {
              if (initial != null) {
                controller.updateConcept(target.targetId, concept);
                _closeInlineEditor();
                return;
              }
              controller.addConcept(target.targetId, concept);
              _replaceInlineEditor(
                _InlineEditorSession.conceptFunding(
                  epoch: ++_editorEpoch,
                  concept: concept,
                  initialAmountClp: concept.amountClp,
                ),
              );
            },
          ),
        );
      case _InlineEditorKind.conceptFunding:
        final concept = editor.concept!;
        final initial = editor.initialLeg;
        return _InlineEditorFrame(
          key: _inlineEditorViewportKey,
          editorKey:
              const ValueKey<String>('payroll-payment-inline-leg-editor'),
          title: initial == null
              ? 'Cómo se pagó ${concept.description}'
              : 'Editar forma de pago',
          onCancel: _closeInlineEditor,
          child: _PaymentLegForm(
            key: ValueKey<int>(editor.epoch),
            methods: controller.request.paymentMethods,
            evidenceChoices: _evidenceChoices(editing: initial),
            initial: initial,
            initialAmountClp: editor.initialAmountClp,
            initialMethodId: target.preferredPaymentMethodId,
            onCancel: _closeInlineEditor,
            onSubmit: (leg) {
              if (initial == null) {
                controller.addConceptPaymentLeg(
                  target.targetId,
                  concept.conceptId,
                  leg,
                );
              } else {
                controller.updateConceptPaymentLeg(
                  target.targetId,
                  concept.conceptId,
                  leg,
                );
              }
              _closeInlineEditor();
            },
          ),
        );
      case _InlineEditorKind.advance:
        final advance = editor.advance!;
        final leg = editor.initialLeg!;
        return _InlineEditorFrame(
          key: _inlineEditorViewportKey,
          editorKey: const ValueKey<String>(
            'payroll-payment-inline-advance-editor',
          ),
          title: 'Monto del anticipo',
          onCancel: _closeInlineEditor,
          child: _AdvanceAmountForm(
            key: ValueKey<int>(editor.epoch),
            initialAmountClp: leg.amountClp,
            maximumAmountClp: advance.availableAmountClp,
            onCancel: _closeInlineEditor,
            onSubmit: (amount) {
              controller.updateSalaryLeg(
                target.targetId,
                PayrollPaymentLeg.advance(
                  legId: leg.legId,
                  advanceId: advance.advanceId,
                  amountClp: amount,
                ),
              );
              _closeInlineEditor();
            },
          ),
        );
    }
  }

  List<_PaymentEvidenceChoice> _evidenceChoices({
    PayrollPaymentLeg? editing,
  }) {
    final choices = <_PaymentEvidenceChoice>[];
    for (final candidate in target.ocrCandidates) {
      final available = controller.availableEvidenceAmount(
        target.targetId,
        candidate.evidence,
        excludingLegId: editing?.legId,
      );
      if (available <= 0) continue;
      choices.add(
        _PaymentEvidenceChoice(
          candidate: candidate,
          availableAmountClp: available,
        ),
      );
    }
    return choices;
  }
}

class _MoneySummary extends StatelessWidget {
  const _MoneySummary({required this.draft, required this.validation});

  final PayrollPaymentTargetDraft draft;
  final PayrollPaymentTargetValidation validation;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      decoration: BoxDecoration(
        color: visual.surfaceSunken,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 10,
        children: [
          _MoneyFact(
            label: 'Total a entregar',
            amount: validation.totalObligationClp,
          ),
          _MoneyFact(
            label: 'Cubierto ahora',
            amount: validation.appliedTotalClp,
          ),
          _MoneyFact(
            label: 'Quedará pendiente',
            amount: validation.remainingClp,
          ),
          if (validation.includedConceptsTotalClp > 0)
            _MoneyFact(
              label: 'Incluido como gasto',
              amount: validation.includedConceptsTotalClp,
            ),
          if (validation.additionalConceptsAdditiveTotalClp > 0)
            _MoneyFact(
              label: 'Gastos que se suman',
              amount: validation.additionalConceptsAdditiveTotalClp,
            ),
        ],
      ),
    );
  }
}

class _MoneyFact extends StatelessWidget {
  const _MoneyFact({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: visual.overline),
        const SizedBox(height: 3),
        VbMoneyText(amount),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: visual.sectionTitle)),
        if (onAction != null)
          TextButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded),
            label: Text(actionLabel),
          ),
      ],
    );
  }
}

class _PaymentLegTile extends StatelessWidget {
  const _PaymentLegTile({
    required this.leg,
    required this.methods,
    required this.onEdit,
    required this.onRemove,
  });

  final PayrollPaymentLeg leg;
  final List<PayrollPaymentMethodOption> methods;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final method = methods
        .where((option) => option.methodId == leg.paymentMethodId)
        .firstOrNull;
    final title = leg.kind == PayrollPaymentLegKind.advance
        ? 'Anticipo aplicado'
        : method?.label ?? 'Parte de pago incompleta';
    final evidence = leg.ocrEvidence;
    return Container(
      key: ValueKey<String>('payroll-payment-leg-${leg.legId}'),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.border),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      child: Row(
        children: [
          Icon(
            leg.kind == PayrollPaymentLegKind.advance
                ? Icons.savings_outlined
                : evidence == null
                    ? Icons.payments_outlined
                    : Icons.receipt_long_outlined,
            size: 18,
            color: visual.inkFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: visual.labelStrong),
                if (leg.reference?.trim().isNotEmpty == true ||
                    evidence != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    evidence?.description ?? leg.reference!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: visual.bodyS.copyWith(color: visual.inkFaint),
                  ),
                ],
              ],
            ),
          ),
          VbMoneyText(leg.amountClp),
          if (onEdit != null)
            IconButton(
              tooltip: 'Editar parte',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Quitar parte',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
    );
  }
}

class _AdvanceTile extends StatelessWidget {
  const _AdvanceTile({
    required this.advance,
    required this.selectedLeg,
    required this.onToggle,
    required this.onEdit,
  });

  final PayrollAdvanceOption advance;
  final PayrollPaymentLeg? selectedLeg;
  final ValueChanged<PayrollPaymentLeg?>? onToggle;
  final ValueChanged<PayrollPaymentLeg>? onEdit;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final selected = selectedLeg != null;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: visual.border)),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: onToggle == null ? null : (_) => onToggle!(selectedLeg),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(advance.label, style: visual.labelStrong),
                if (advance.reference?.trim().isNotEmpty == true)
                  Text(advance.reference!, style: visual.bodyS),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              VbMoneyText(selectedLeg?.amountClp ?? advance.availableAmountClp),
              if (selected)
                Text('de ${VbMoneyText.formatClp(advance.availableAmountClp)}',
                    style: visual.bodyS.copyWith(color: visual.inkFaint)),
            ],
          ),
          if (selected && onEdit != null)
            IconButton(
              tooltip: 'Editar monto del anticipo',
              onPressed: () => onEdit!(selectedLeg!),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
    );
  }
}

class _ConceptTile extends StatelessWidget {
  const _ConceptTile({
    required this.concept,
    required this.methods,
    required this.onEdit,
    required this.onRemove,
    required this.onAddFunding,
    required this.onEditFunding,
    required this.onRemoveFunding,
  });

  final PayrollAdditionalConcept concept;
  final List<PayrollPaymentMethodOption> methods;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final VoidCallback? onAddFunding;
  final ValueChanged<PayrollPaymentLeg>? onEditFunding;
  final ValueChanged<PayrollPaymentLeg>? onRemoveFunding;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final funded = concept.paymentLegs.fold<int>(
      0,
      (sum, leg) => sum + leg.amountClp,
    );
    return Container(
      key: ValueKey<String>('payroll-additional-concept-${concept.conceptId}'),
      decoration: BoxDecoration(
        color: visual.info.soft,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.info.border),
      ),
      padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(concept.description, style: visual.labelStrong),
                    const SizedBox(height: 2),
                    Text(
                      '${concept.disposition == PayrollAdditionalConceptDisposition.includedInPayrollTotal ? 'Incluido en el total de la nómina' : 'Se suma al pago'} · Financiado '
                      '${VbMoneyText.formatClp(funded)} de '
                      '${VbMoneyText.formatClp(concept.amountClp)}',
                      style: visual.bodyS.copyWith(color: visual.inkFaint),
                    ),
                  ],
                ),
              ),
              VbMoneyText(concept.amountClp),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Editar concepto',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Quitar concepto',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          if (concept.paymentLegs.isEmpty)
            Text(
              'Falta indicar cómo se pagó este concepto.',
              style: visual.bodyS.copyWith(color: visual.inkFaint),
            )
          else
            for (final leg in concept.paymentLegs) ...[
              const SizedBox(height: 7),
              _PaymentLegTile(
                leg: leg,
                methods: methods,
                onEdit:
                    onEditFunding == null ? null : () => onEditFunding!(leg),
                onRemove: onRemoveFunding == null
                    ? null
                    : () => onRemoveFunding!(leg),
              ),
            ],
          if (onAddFunding != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAddFunding,
                icon: const Icon(Icons.add_card_rounded),
                label: const Text('Agregar otra forma de pago'),
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkspaceFooter extends StatelessWidget {
  const _WorkspaceFooter({
    required this.draft,
    required this.validation,
    required this.saving,
    required this.editorActive,
    required this.onSave,
  });

  final PayrollPaymentTargetDraft draft;
  final PayrollPaymentTargetValidation validation;
  final bool saving;
  final bool editorActive;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: visual.surfaceOverlay,
        border: Border(top: BorderSide(color: visual.border)),
        boxShadow: visual.moneyBar,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              validation.remainingClp == 0
                  ? 'El pago queda cubierto'
                  : 'Quedarán ${VbMoneyText.formatClp(validation.remainingClp)} pendientes del pago',
              style: visual.bodyS.copyWith(color: visual.inkFaint),
            ),
          ),
          const SizedBox(width: 10),
          PayrollAccentAction(
            actionKey: const ValueKey<String>('payroll-payment-save-target'),
            label: draft.isSaved ? 'Guardado' : 'Registrar pago',
            enabled: validation.isValid &&
                !saving &&
                !draft.isSaved &&
                !editorActive,
            busy: saving,
            onTap: onSave,
            minHeight: 38,
          ),
        ],
      ),
    );
  }
}

class _PaymentEvidenceChoice {
  const _PaymentEvidenceChoice({
    required this.candidate,
    required this.availableAmountClp,
  });

  final PayrollOcrPaymentCandidate candidate;
  final int availableAmountClp;
}

enum _InlineEditorKind { salaryLeg, concept, conceptFunding, advance }

class _InlineEditorSession {
  const _InlineEditorSession._({
    required this.kind,
    required this.epoch,
    this.initialLeg,
    this.initialConcept,
    this.concept,
    this.advance,
    this.initialAmountClp,
  });

  factory _InlineEditorSession.salaryLeg({
    required int epoch,
    PayrollPaymentLeg? initialLeg,
    int? initialAmountClp,
  }) =>
      _InlineEditorSession._(
        kind: _InlineEditorKind.salaryLeg,
        epoch: epoch,
        initialLeg: initialLeg,
        initialAmountClp: initialAmountClp,
      );

  factory _InlineEditorSession.concept({
    required int epoch,
    PayrollAdditionalConcept? initialConcept,
  }) =>
      _InlineEditorSession._(
        kind: _InlineEditorKind.concept,
        epoch: epoch,
        initialConcept: initialConcept,
      );

  factory _InlineEditorSession.conceptFunding({
    required int epoch,
    required PayrollAdditionalConcept concept,
    PayrollPaymentLeg? initialLeg,
    int? initialAmountClp,
  }) =>
      _InlineEditorSession._(
        kind: _InlineEditorKind.conceptFunding,
        epoch: epoch,
        concept: concept,
        initialLeg: initialLeg,
        initialAmountClp: initialAmountClp,
      );

  factory _InlineEditorSession.advance({
    required int epoch,
    required PayrollAdvanceOption advance,
    required PayrollPaymentLeg initialLeg,
  }) =>
      _InlineEditorSession._(
        kind: _InlineEditorKind.advance,
        epoch: epoch,
        advance: advance,
        initialLeg: initialLeg,
      );

  final _InlineEditorKind kind;
  final int epoch;
  final PayrollPaymentLeg? initialLeg;
  final PayrollAdditionalConcept? initialConcept;
  final PayrollAdditionalConcept? concept;
  final PayrollAdvanceOption? advance;
  final int? initialAmountClp;
}

class _InlineEditorFrame extends StatelessWidget {
  const _InlineEditorFrame({
    super.key,
    required this.editorKey,
    required this.title,
    required this.onCancel,
    required this.child,
  });

  final Key editorKey;
  final String title;
  final VoidCallback onCancel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): onCancel,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          key: editorKey,
          decoration: BoxDecoration(
            color: visual.surfaceSunken,
            borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
            border: Border.all(color: visual.borderStrong),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: visual.sectionTitle),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentLegDialog extends StatelessWidget {
  const _PaymentLegDialog({
    required this.methods,
    required this.evidenceChoices,
    this.allowPayrollReferenceFallback = false,
    this.initial,
    this.initialAmountClp,
    this.initialMethodId,
  });

  final List<PayrollPaymentMethodOption> methods;
  final List<_PaymentEvidenceChoice> evidenceChoices;
  final bool allowPayrollReferenceFallback;
  final PayrollPaymentLeg? initial;
  final int? initialAmountClp;
  final String? initialMethodId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(initial == null ? 'Agregar parte' : 'Editar parte'),
      content: SingleChildScrollView(
        child: _PaymentLegForm(
          methods: methods,
          evidenceChoices: evidenceChoices,
          allowPayrollReferenceFallback: allowPayrollReferenceFallback,
          initial: initial,
          initialAmountClp: initialAmountClp,
          initialMethodId: initialMethodId,
          onCancel: () => Navigator.pop(context),
          onSubmit: (leg) => Navigator.pop(context, leg),
        ),
      ),
    );
  }
}

class _PaymentLegForm extends StatefulWidget {
  const _PaymentLegForm({
    super.key,
    required this.methods,
    required this.evidenceChoices,
    required this.onCancel,
    required this.onSubmit,
    this.allowPayrollReferenceFallback = false,
    this.initial,
    this.initialAmountClp,
    this.initialMethodId,
  });

  final List<PayrollPaymentMethodOption> methods;
  final List<_PaymentEvidenceChoice> evidenceChoices;
  final bool allowPayrollReferenceFallback;
  final PayrollPaymentLeg? initial;
  final int? initialAmountClp;
  final String? initialMethodId;
  final VoidCallback onCancel;
  final ValueChanged<PayrollPaymentLeg> onSubmit;

  @override
  State<_PaymentLegForm> createState() => _PaymentLegFormState();
}

class _PaymentLegFormState extends State<_PaymentLegForm> {
  late final TextEditingController _amount;
  late final TextEditingController _reference;
  late final TextEditingController _notes;
  String? _methodId;
  String? _evidenceCandidateId;
  late PayrollCivilDate _date;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final amount = initial?.amountClp ?? widget.initialAmountClp ?? 0;
    _amount = TextEditingController(text: _clpInput(amount));
    _reference = TextEditingController(text: initial?.reference ?? '');
    _notes = TextEditingController(text: initial?.notes ?? '');
    final preferred = widget.initialMethodId?.trim() ?? '';
    _methodId = initial?.paymentMethodId ??
        widget.methods
            .where((method) => method.isActive && method.methodId == preferred)
            .firstOrNull
            ?.methodId ??
        widget.methods.where((method) => method.isActive).firstOrNull?.methodId;
    final initialEvidenceKey = initial?.ocrEvidence?.allocationKey;
    _evidenceCandidateId = initialEvidenceKey == null
        ? null
        : widget.evidenceChoices
            .where((choice) =>
                choice.candidate.evidence.allocationKey == initialEvidenceKey)
            .firstOrNull
            ?.candidate
            .candidateId;
    final now = DateTime.now();
    _date =
        initial?.paymentDate ?? PayrollCivilDate(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedMethod = widget.methods
        .where((method) => method.methodId == _methodId)
        .firstOrNull;
    final referenceRequired = !widget.allowPayrollReferenceFallback &&
        (selectedMethod?.requiresReference ?? false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VbShortSelect<String?>(
          value: _methodId,
          label: 'Método',
          sheetTitle: 'Método de pago',
          placeholder: 'Elegir método',
          options: [
            for (final option in widget.methods)
              VbShortSelectOption<String?>(
                value: option.methodId,
                label: option.accountLabel == null
                    ? option.label
                    : '${option.label} · ${option.accountLabel}',
              ),
          ],
          onChanged: (value) => setState(() => _methodId = value),
        ),
        if (widget.evidenceChoices.isNotEmpty) ...[
          const SizedBox(height: 10),
          VbSearchableSelect<String>(
            key: const ValueKey<String>(
              'payroll-payment-evidence-select',
            ),
            value: _evidenceCandidateId,
            label: 'Movimiento de cartola (opcional)',
            sheetTitle: 'Usar movimiento de cartola',
            placeholder: 'Sin respaldo de cartola',
            searchHint: 'Buscar fecha, monto o descripción…',
            allowClear: true,
            options: [
              for (final choice in widget.evidenceChoices)
                VbSearchableSelectOption<String>(
                  value: choice.candidate.candidateId,
                  label: '${VbMoneyText.formatClp(
                    choice.availableAmountClp,
                  )} disponibles',
                  context: <String>[
                    if (choice.candidate.evidence.bookingDate case final date?)
                      _dateLabel(date),
                    choice.candidate.evidence.description,
                  ].join(' · '),
                  searchText: choice.candidate.evidence.documentReference,
                ),
            ],
            onChanged: _selectEvidence,
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey<String>('payroll-payment-leg-amount-input'),
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: const [ClpAmountInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Monto',
            prefixText: r'$ ',
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickDate,
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text('Fecha ${_dateLabel(_date)}'),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey<String>('payroll-payment-leg-reference-input'),
          controller: _reference,
          decoration: InputDecoration(
            labelText: widget.allowPayrollReferenceFallback
                ? 'Referencia bancaria (opcional)'
                : referenceRequired
                    ? 'Referencia obligatoria'
                    : 'Referencia',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey<String>('payroll-payment-leg-notes-input'),
          controller: _notes,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Nota'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('Cancelar'),
            ),
            // accent-fill: dialog-action
            FilledButton(
              onPressed: _submit,
              child: const Text('Guardar parte'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final initial = DateTime(_date.year, _date.month, _date.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() =>
          _date = PayrollCivilDate(picked.year, picked.month, picked.day));
    }
  }

  void _selectEvidence(String? candidateId) {
    final choice = _evidenceChoice(candidateId);
    setState(() {
      _evidenceCandidateId = candidateId;
      if (choice == null) return;
      _methodId = _compatibleTransferMethod(choice)?.methodId;
      final evidence = choice.candidate.evidence;
      if (evidence.bookingDate case final date?) _date = date;
      if (_reference.text.trim().isEmpty &&
          evidence.documentReference?.trim().isNotEmpty == true) {
        _reference.text = evidence.documentReference!.trim();
      }
      if (_notes.text.trim().isEmpty) _notes.text = evidence.description.trim();
      final currentAmount = parsePayrollAmount(_amount.text).round();
      if (currentAmount <= 0 || currentAmount > choice.availableAmountClp) {
        _amount.text = _clpInput(choice.availableAmountClp);
      }
    });
  }

  _PaymentEvidenceChoice? _evidenceChoice(String? candidateId) {
    if (candidateId == null) return null;
    return widget.evidenceChoices
        .where((choice) => choice.candidate.candidateId == candidateId)
        .firstOrNull;
  }

  PayrollPaymentMethodOption? _compatibleTransferMethod(
    _PaymentEvidenceChoice choice,
  ) {
    final accountId =
        choice.candidate.suggestedPaymentAccountId?.trim().isNotEmpty == true
            ? choice.candidate.suggestedPaymentAccountId!.trim()
            : choice.candidate.evidence.suggestedErpAccountId?.trim() ?? '';
    bool compatible(PayrollPaymentMethodOption method) =>
        method.isActive &&
        method.code.trim().toLowerCase() == 'transfer' &&
        (accountId.isEmpty || method.accountId == accountId);

    final suggestedMethodId = choice.candidate.suggestedPaymentMethodId?.trim();
    for (final method in widget.methods) {
      if (method.methodId == suggestedMethodId && compatible(method)) {
        return method;
      }
    }
    for (final method in widget.methods) {
      if (method.methodId == _methodId && compatible(method)) return method;
    }
    final compatibleMethods = widget.methods.where(compatible).toList();
    return compatibleMethods.length == 1 ? compatibleMethods.single : null;
  }

  void _submit() {
    final amount = parsePayrollAmount(_amount.text).round();
    final method = widget.methods
        .where((option) => option.methodId == _methodId)
        .firstOrNull;
    if (amount <= 0 || method == null || !method.isActive) {
      setState(
        () => _error = 'Completa un método activo y un monto mayor a \$0.',
      );
      return;
    }
    if (!widget.allowPayrollReferenceFallback &&
        method.requiresReference &&
        _reference.text.trim().isEmpty) {
      setState(() => _error = 'Este método exige una referencia.');
      return;
    }
    final evidenceChoice = _evidenceChoice(_evidenceCandidateId);
    if (evidenceChoice != null) {
      final expectedAccountId = evidenceChoice
                  .candidate.suggestedPaymentAccountId
                  ?.trim()
                  .isNotEmpty ==
              true
          ? evidenceChoice.candidate.suggestedPaymentAccountId!.trim()
          : evidenceChoice.candidate.evidence.suggestedErpAccountId?.trim() ??
              '';
      if (method.code.trim().toLowerCase() != 'transfer' ||
          (expectedAccountId.isNotEmpty &&
              method.accountId != expectedAccountId)) {
        setState(() {
          _error = 'El movimiento de cartola necesita una transferencia de la '
              'cuenta bancaria correspondiente.';
        });
        return;
      }
      if (amount > evidenceChoice.availableAmountClp) {
        setState(() {
          _error = 'Este movimiento sólo tiene '
              '${VbMoneyText.formatClp(evidenceChoice.availableAmountClp)} '
              'disponibles.';
        });
        return;
      }
    }
    widget.onSubmit(
      PayrollPaymentLeg.payment(
        legId: widget.initial?.legId ?? const Uuid().v4(),
        amountClp: amount,
        paymentMethodId: method.methodId,
        paymentAccountId: method.accountId,
        paymentDate: _date,
        reference:
            _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        ocrEvidence: evidenceChoice?.candidate.evidence,
      ),
    );
  }
}

class _AdvanceAmountDialog extends StatelessWidget {
  const _AdvanceAmountDialog({
    required this.initialAmountClp,
    required this.maximumAmountClp,
  });

  final int initialAmountClp;
  final int maximumAmountClp;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Monto del anticipo'),
      content: _AdvanceAmountForm(
        initialAmountClp: initialAmountClp,
        maximumAmountClp: maximumAmountClp,
        onCancel: () => Navigator.pop(context),
        onSubmit: (amount) => Navigator.pop(context, amount),
      ),
    );
  }
}

class _AdvanceAmountForm extends StatefulWidget {
  const _AdvanceAmountForm({
    super.key,
    required this.initialAmountClp,
    required this.maximumAmountClp,
    required this.onCancel,
    required this.onSubmit,
  });

  final int initialAmountClp;
  final int maximumAmountClp;
  final VoidCallback onCancel;
  final ValueChanged<int> onSubmit;

  @override
  State<_AdvanceAmountForm> createState() => _AdvanceAmountFormState();
}

class _AdvanceAmountFormState extends State<_AdvanceAmountForm> {
  late final TextEditingController _amount;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(text: _clpInput(widget.initialAmountClp));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: const [ClpAmountInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Monto a aplicar',
            prefixText: r'$ ',
          ),
        ),
        const SizedBox(height: 6),
        Text('Disponible ${VbMoneyText.formatClp(widget.maximumAmountClp)}'),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('Cancelar'),
            ),
            // accent-fill: dialog-action
            FilledButton(
              onPressed: _submit,
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ],
    );
  }

  void _submit() {
    final amount = parsePayrollAmount(_amount.text).round();
    if (amount <= 0 || amount > widget.maximumAmountClp) {
      setState(() {
        _error = 'Usa un monto entre \$1 y '
            '${VbMoneyText.formatClp(widget.maximumAmountClp)}.';
      });
      return;
    }
    widget.onSubmit(amount);
  }
}

class _ConceptDialog extends StatelessWidget {
  const _ConceptDialog({
    required this.expenseAccounts,
    this.initial,
  });

  final List<PayrollExpenseAccountOption> expenseAccounts;
  final PayrollAdditionalConcept? initial;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(initial == null
          ? 'Agregar concepto separado'
          : 'Editar concepto separado'),
      content: SingleChildScrollView(
        child: _ConceptForm(
          expenseAccounts: expenseAccounts,
          initial: initial,
          onCancel: () => Navigator.pop(context),
          onSubmit: (concept) => Navigator.pop(context, concept),
        ),
      ),
    );
  }
}

class _ConceptForm extends StatefulWidget {
  const _ConceptForm({
    super.key,
    required this.expenseAccounts,
    required this.onCancel,
    required this.onSubmit,
    this.initial,
  });

  final List<PayrollExpenseAccountOption> expenseAccounts;
  final PayrollAdditionalConcept? initial;
  final VoidCallback onCancel;
  final ValueChanged<PayrollAdditionalConcept> onSubmit;

  @override
  State<_ConceptForm> createState() => _ConceptFormState();
}

class _ConceptFormState extends State<_ConceptForm> {
  late final TextEditingController _description;
  late final TextEditingController _amount;
  PayrollAdditionalConceptType _type =
      PayrollAdditionalConceptType.expenseReimbursement;
  PayrollAdditionalConceptDisposition _disposition =
      PayrollAdditionalConceptDisposition.includedInPayrollTotal;
  String? _accountId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _description = TextEditingController(text: initial?.description ?? '');
    _amount = TextEditingController(
      text: initial == null ? '' : _clpInput(initial.amountClp),
    );
    _type = initial?.type ?? PayrollAdditionalConceptType.expenseReimbursement;
    _disposition = initial?.disposition ??
        PayrollAdditionalConceptDisposition.includedInPayrollTotal;
    _accountId = initial?.expenseAccountId ??
        widget.expenseAccounts.firstOrNull?.accountId;
  }

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey<String>('payroll-concept-description-input'),
          controller: _description,
          decoration: const InputDecoration(
            labelText: 'Descripción',
            hintText: 'Qué se está reembolsando o compensando',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey<String>('payroll-concept-amount-input'),
          controller: _amount,
          keyboardType: TextInputType.number,
          inputFormatters: const [ClpAmountInputFormatter()],
          decoration: const InputDecoration(
            labelText: 'Monto',
            prefixText: r'$ ',
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '¿Este monto ya está dentro del total de la nómina?',
          style: PayrollVisualTokens.of(context).labelStrong,
        ),
        const SizedBox(height: 7),
        SegmentedButton<PayrollAdditionalConceptDisposition>(
          segments: const <ButtonSegment<PayrollAdditionalConceptDisposition>>[
            ButtonSegment<PayrollAdditionalConceptDisposition>(
              value: PayrollAdditionalConceptDisposition.includedInPayrollTotal,
              label: Text('Sí, ya está incluido'),
            ),
            ButtonSegment<PayrollAdditionalConceptDisposition>(
              value: PayrollAdditionalConceptDisposition.additional,
              label: Text('No, se suma aparte'),
            ),
          ],
          selected: <PayrollAdditionalConceptDisposition>{_disposition},
          onSelectionChanged: (selection) {
            setState(() => _disposition = selection.single);
          },
        ),
        const SizedBox(height: 5),
        Text(
          _disposition ==
                  PayrollAdditionalConceptDisposition.includedInPayrollTotal
              ? 'Se separa contablemente, pero no aumenta el total a entregar.'
              : 'Este monto aumenta el total que se entrega al trabajador.',
          style: PayrollVisualTokens.of(context)
              .bodyS
              .copyWith(color: PayrollVisualTokens.of(context).inkFaint),
        ),
        const SizedBox(height: 10),
        VbSearchableSelect<String>(
          key: const ValueKey<String>(
            'payroll-concept-expense-account',
          ),
          value: _accountId,
          label: 'Cuenta contable',
          sheetTitle: 'Cuenta del gasto',
          placeholder: 'Elegir cuenta',
          searchHint: 'Buscar por código o nombre…',
          options: [
            for (final account in widget.expenseAccounts)
              VbSearchableSelectOption<String>(
                value: account.accountId,
                label: account.label,
                searchText: account.label,
              ),
          ],
          onChanged: (value) => setState(() => _accountId = value),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('Cancelar'),
            ),
            // accent-fill: dialog-action
            FilledButton(
              onPressed: _submit,
              child: Text(widget.initial == null ? 'Agregar' : 'Guardar'),
            ),
          ],
        ),
      ],
    );
  }

  void _submit() {
    final description = _description.text.trim();
    final amount = parsePayrollAmount(_amount.text).round();
    final accountId = _accountId?.trim() ?? '';
    if (description.isEmpty || amount <= 0 || accountId.isEmpty) {
      setState(() {
        _error = 'Completa descripción, monto y cuenta contable.';
      });
      return;
    }
    widget.onSubmit(
      PayrollAdditionalConcept(
        conceptId: widget.initial?.conceptId ?? const Uuid().v4(),
        type: _type,
        description: description,
        amountClp: amount,
        expenseAccountId: accountId,
        disposition: _disposition,
        evidenceReference: widget.initial?.evidenceReference,
        paymentLegs: widget.initial?.paymentLegs ?? const [],
      ),
    );
  }
}

String _initials(String name) {
  final parts =
      name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}

int _isoWeek(PayrollCivilDate date) => payrollIsoWeekNumber(
      DateTime(date.year, date.month, date.day),
    );

String _range(PayrollCivilDate start, PayrollCivilDate end) =>
    formatPayrollWeekRange(
      DateTime(start.year, start.month, start.day),
      DateTime(end.year, end.month, end.day),
    );

String _dateLabel(PayrollCivilDate date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/${date.year}';

String _clpInput(int amount) {
  final digits = amount.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
    buffer.write(digits[index]);
  }
  return buffer.toString();
}
