import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/payroll_money_bar.dart' show formatPayrollClp;
import '../theme/payroll_tokens.dart';
import 'payroll_accent_action.dart';

/// 2b — Composer de pago adaptable.
/// Etapa 1: anticipos elegibles. Al aplicar uno se revela la ecuación compacta.
/// Etapa 2: monto de la transferencia, con máximo y saldo residual explícitos.
/// Etapa 3: "Cómo se pagó" (método + fecha + referencia) en un solo bloque.
/// Una sola nota contextual, que cambia según lo aplicado. CTA persistente.
class PayrollAdvanceVM {
  const PayrollAdvanceVM({
    required this.reason,
    required this.meta,
    required this.amountLabel,
    required this.applied,
    required this.onToggle,
  });
  final String reason; // "Adelanto de quincena"
  final String meta; // "05/07 · efectivo"
  final String amountLabel; // "$15.000"
  final bool applied;
  final VoidCallback onToggle;
}

class PayrollPaymentComposer extends StatefulWidget {
  const PayrollPaymentComposer({
    super.key,
    required this.personName,
    required this.initials,
    required this.avatarColor,
    required this.weekLabel,
    required this.hoursAndEarned,
    required this.earnedLabel,
    required this.advances,
    required this.appliedLabel,
    required this.newMoneyLabel,
    required this.advancesBalanceLabel,
    required this.contextNote,
    required this.methods,
    required this.selectedMethod,
    required this.dateLabel,
    required this.referenceValue,
    required this.onClose,
    required this.onRegister,
    this.onSelectMethod,
    this.onPickDate,
    this.referenceController,
    this.lockSelectedMethod,
    this.amountController,
    this.onAmountChanged,
    this.maximumNewMoneyLabel,
    this.remainingAfterLabel,
    this.amountError,
    this.registerLabel,
    this.registerEnabled = true,
  });

  final String personName;
  final String initials;
  final Color avatarColor;
  final String weekLabel; // "PAGAR SEMANA 28 · 07 – 13 JUL"
  final String hoursAndEarned; // "38,5 h · total $172.875"
  final String earnedLabel; // "$172.875"
  final List<PayrollAdvanceVM> advances;
  final String appliedLabel; // "−$15.000" | "$0"
  final String newMoneyLabel; // "$157.875"
  final String advancesBalanceLabel; // "vigente $27.500"
  final String contextNote;

  /// Opciones de transferencia ya configuradas por el host. Cada etiqueta
  /// identifica una combinación método/cuenta concreta.
  ///
  /// Efectivo pertenece a su flujo de confirmación separado y, por defensa en
  /// profundidad, nunca es seleccionable aunque un caller antiguo lo incluya.
  final List<String> methods;
  final String selectedMethod;
  final String dateLabel; // "29/07/2026"
  final String referenceValue; // "TRF-88421"
  /// El host es dueño de la ruta y de cualquier confirmación de descarte.
  /// El compositor solo solicita cerrar o registrar y espera ese resultado.
  final FutureOr<void> Function() onClose;
  final FutureOr<void> Function() onRegister;

  /// Adaptadores funcionales: mismos visuales del handoff, entradas reales.
  final ValueChanged<String>? onSelectMethod;
  final VoidCallback? onPickDate;
  final TextEditingController? referenceController;
  final TextEditingController? amountController;
  final ValueChanged<String>? onAmountChanged;
  final String? maximumNewMoneyLabel;
  final String? remainingAfterLabel;
  final String? amountError;
  final String? registerLabel;
  final bool registerEnabled;

  /// `true` inmoviliza incluso la cuenta seleccionada. Por defecto el
  /// compositor permite cambiar entre las alternativas de transferencia que
  /// el host ya filtró, sin abrir el flujo separado de efectivo.
  final bool? lockSelectedMethod;

  @override
  State<PayrollPaymentComposer> createState() => _PayrollPaymentComposerState();
}

class _PayrollPaymentComposerState extends State<PayrollPaymentComposer> {
  bool _closing = false;
  bool _submitting = false;

  bool get _hasApplied =>
      widget.advances.any((PayrollAdvanceVM a) => a.applied);

  Future<void> _close() async {
    if (_submitting || _closing) return;
    setState(() => _closing = true);
    try {
      await Future<void>.sync(widget.onClose);
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _register() async {
    if (_submitting || _closing) return;
    setState(() => _submitting = true);
    try {
      await Future<void>.sync(widget.onRegister);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final visual = PayrollVisualTokens.of(context);
    final weekLabel = widget.weekLabel;
    final avatarColor = widget.avatarColor;
    final initials = widget.initials;
    final personName = widget.personName;
    final hoursAndEarned = widget.hoursAndEarned;
    final advancesBalanceLabel = widget.advancesBalanceLabel;
    final advances = widget.advances;
    final earnedLabel = widget.earnedLabel;
    final appliedLabel = widget.appliedLabel;
    final newMoneyLabel = widget.newMoneyLabel;
    final methods = widget.methods;
    final selectedMethod = widget.selectedMethod;
    final dateLabel = widget.dateLabel;
    final referenceValue = widget.referenceValue;
    final onSelectMethod = widget.onSelectMethod;
    final onPickDate = widget.onPickDate;
    final referenceController = widget.referenceController;
    final contextNote = widget.contextNote;
    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = media.size.width < 600 || constraints.maxWidth < 420;
        final touchOptimized = media.size.width < 900;
        // El route host aplica SafeArea y viewInsets una sola vez. Duplicarlos
        // aquí desplazaría el panel dos veces cuando se abre el teclado.
        return Container(
          key: const ValueKey<String>('payroll-payment-composer'),
          decoration: BoxDecoration(color: visual.surface),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Header navy del composer (no es chrome global: es la ficha del pago).
              Container(
                color: visual.shell,
                padding: EdgeInsets.fromLTRB(
                  phone ? 16 : 18,
                  phone ? 10 : 15,
                  phone ? 8 : 12,
                  phone ? 12 : 15,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            weekLabel,
                            style: visual.overline.copyWith(
                              color: visual.onShellMuted,
                            ),
                          ),
                        ),
                        Semantics(
                          button: true,
                          label: 'Cerrar compositor de pago',
                          child: IconButton(
                            key: const ValueKey<String>(
                                'payroll-composer-close'),
                            onPressed: _submitting || _closing ? null : _close,
                            tooltip: 'Cerrar',
                            constraints: BoxConstraints.tightFor(
                              width: touchOptimized
                                  ? PayrollTokens.touchMobile
                                  : 36,
                              height: touchOptimized
                                  ? PayrollTokens.touchMobile
                                  : 36,
                            ),
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.close,
                              size: 18,
                              color: visual.onShellMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: phone ? 6 : 8),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                              color: avatarColor, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Text(
                            initials,
                            style: visual.avatarInitials(12.5),
                          ),
                        ),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(personName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: visual.recordTitle
                                      .copyWith(fontSize: 17)),
                              const SizedBox(height: 2),
                              Text(hoursAndEarned,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: visual.monoS.copyWith(
                                      fontSize: 11,
                                      color: visual.onShellMuted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Cuerpo
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey<String>('payroll-composer-scroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    phone ? 16 : 18,
                    phone ? 14 : 17,
                    phone ? 16 : 18,
                    phone ? 20 : 17,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _StepTitle(
                          index: '1',
                          title: '¿Se aplica algún anticipo?',
                          trailing: advancesBalanceLabel),
                      const SizedBox(height: 9),
                      for (final PayrollAdvanceVM a in advances) ...<Widget>[
                        _AdvanceRow(
                          vm: a,
                          touchOptimized: touchOptimized,
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 2),
                      if (_hasApplied)
                        _EquationStrip(
                          earned: earnedLabel,
                          applied: appliedLabel,
                          result: newMoneyLabel,
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 11),
                          decoration: BoxDecoration(
                            color: visual.surfaceSunken,
                            borderRadius:
                                BorderRadius.circular(PayrollTokens.rField),
                            border: Border.all(color: visual.border),
                          ),
                          child: Text.rich(
                            TextSpan(
                              style: visual.bodyS.copyWith(fontSize: 11),
                              children: <InlineSpan>[
                                const TextSpan(
                                  text:
                                      'Sin anticipos aplicados el dinero nuevo es el total calculado: ',
                                ),
                                TextSpan(
                                    text: earnedLabel,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const TextSpan(text: '.'),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (widget.amountController != null) ...<Widget>[
                        const _StepTitle(
                          index: '2',
                          title: 'Cuánto se transfirió',
                        ),
                        const SizedBox(height: 9),
                        _PaymentAmountBlock(
                          controller: widget.amountController!,
                          onChanged: widget.onAmountChanged,
                          maximumLabel:
                              widget.maximumNewMoneyLabel ?? newMoneyLabel,
                          remainingLabel: widget.remainingAfterLabel ?? '\$0',
                          errorText: widget.amountError,
                          suggestedLabel:
                              widget.maximumNewMoneyLabel ?? newMoneyLabel,
                        ),
                        const SizedBox(height: 16),
                      ],
                      _StepTitle(
                        index: widget.amountController == null ? '2' : '3',
                        title: 'Cómo se pagó',
                      ),
                      const SizedBox(height: 9),
                      _HowPaidBlock(
                        methods: methods,
                        selected: selectedMethod,
                        dateLabel: dateLabel,
                        reference: referenceValue,
                        onSelectMethod: onSelectMethod,
                        onPickDate: onPickDate,
                        referenceController: referenceController,
                        touchOptimized: touchOptimized,
                        stackFields: phone,
                        methodLocked: widget.lockSelectedMethod ?? false,
                      ),
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 12),
                        decoration: BoxDecoration(
                          color: visual.accentSoft,
                          borderRadius:
                              BorderRadius.circular(PayrollTokens.rField),
                          border: Border.all(color: visual.accentBorder),
                        ),
                        child: Text(contextNote,
                            style: visual.bodyS.copyWith(
                                fontSize: 11.5,
                                height: 1.55,
                                color: visual.accent)),
                      ),
                    ],
                  ),
                ),
              ),
              // Footer con CTA persistente y monto en la etiqueta.
              Container(
                key: const ValueKey<String>('payroll-composer-footer'),
                padding: EdgeInsets.fromLTRB(
                  phone ? 16 : 18,
                  phone ? 12 : 13,
                  phone ? 16 : 18,
                  phone ? 12 : 13,
                ),
                decoration: BoxDecoration(
                  color: visual.surfaceSunken,
                  border: Border(
                    top: BorderSide(color: visual.borderStrong),
                  ),
                ),
                child: phone
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'Se guarda como pago de '
                            '${weekLabel.replaceFirst(RegExp(r'^PAGAR\s+', caseSensitive: false), '')}',
                            style: visual.bodyS.copyWith(
                              fontSize: 11,
                              color: visual.inkFaint,
                            ),
                          ),
                          const SizedBox(height: 9),
                          _RegisterButton(
                            key: const ValueKey<String>(
                              'payroll-composer-register',
                            ),
                            label: widget.registerLabel ??
                                'Registrar ${widget.newMoneyLabel}',
                            compact: true,
                            submitting: _submitting || _closing,
                            enabled: widget.registerEnabled,
                            onTap: _register,
                          ),
                        ],
                      )
                    : Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              'Se guarda como pago de '
                              '${widget.weekLabel.replaceFirst(RegExp(r'^PAGAR\s+', caseSensitive: false), '')}',
                              style: visual.bodyS.copyWith(
                                fontSize: 11,
                                color: visual.inkFaint,
                              ),
                            ),
                          ),
                          _RegisterButton(
                            key: const ValueKey<String>(
                              'payroll-composer-register',
                            ),
                            label: widget.registerLabel ??
                                'Registrar ${widget.newMoneyLabel}',
                            compact: false,
                            submitting: _submitting || _closing,
                            enabled: widget.registerEnabled,
                            onTap: _register,
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RegisterButton extends StatelessWidget {
  const _RegisterButton({
    super.key,
    required this.label,
    required this.compact,
    required this.submitting,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool compact;
  final bool submitting;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PayrollAccentAction(
      label: label,
      onTap: onTap,
      enabled: enabled,
      busy: submitting,
      height: compact ? 50 : 38,
      fontSize: compact ? 13 : 12.5,
      horizontalPadding: 16,
      disabledStyle: PayrollAccentDisabledStyle.neutral,
      animate: true,
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.index, required this.title, this.trailing});
  final String index;
  final String title;
  final String? trailing;
  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        Expanded(
          child: Text(
            '$index · $title',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: visual.sectionTitle.copyWith(fontSize: 13),
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: 8),
          Text(trailing!, style: visual.monoS.copyWith(fontSize: 10.5)),
        ],
      ],
    );
  }
}

/// Qué caso de pago está registrando el operador, medido contra lo que la
/// semana espera. No es una regla nueva: es el nombre del caso que ya existe.
enum _AmountCase { exact, over, partial, empty }

int _clpDigits(String value) =>
    int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

_AmountCase _amountCaseOf(String typed, String suggested) {
  final typedValue = _clpDigits(typed);
  final suggestedValue = _clpDigits(suggested);
  if (typedValue == 0) return _AmountCase.empty;
  if (suggestedValue == 0 || typedValue == suggestedValue) {
    return _AmountCase.exact;
  }
  return typedValue > suggestedValue ? _AmountCase.over : _AmountCase.partial;
}

/// Los tres casos de 5e, lado a lado. Marca cuál está ocurriendo; no cambia
/// el monto ni la validación.
class _AmountCaseStrip extends StatelessWidget {
  const _AmountCaseStrip({
    required this.suggestedLabel,
    required this.typedLabel,
  });

  final String suggestedLabel;
  final String typedLabel;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final active = _amountCaseOf(typedLabel, suggestedLabel);
    final difference = _clpDigits(typedLabel) - _clpDigits(suggestedLabel);

    Widget chip(_AmountCase value, String label, String detail) {
      final selected = active == value;
      return Container(
        key: ValueKey<String>('payroll-composer-case-${value.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? visual.accentSoft : visual.surface,
          borderRadius: BorderRadius.circular(PayrollTokens.rField),
          border: Border.all(
            color: selected ? visual.accent : visual.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: visual.labelStrong.copyWith(
                fontSize: 11,
                color: selected ? visual.accent : visual.inkMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              detail,
              style: visual.monoS.copyWith(fontSize: 9.5),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: <Widget>[
        chip(_AmountCase.exact, 'Completo', suggestedLabel),
        chip(
          _AmountCase.over,
          'Con diferencia',
          difference > 0 ? '+${formatPayrollClp(difference)}' : 'de más',
        ),
        chip(
          _AmountCase.partial,
          'Parcial',
          difference < 0
              ? formatPayrollClp(_clpDigits(typedLabel))
              : 'de menos',
        ),
      ],
    );
  }
}

/// Qué va a pasar exactamente al guardar. 5e la pone antes del botón porque
/// una diferencia o un parcial cambian el estado de la semana, no sólo el de
/// la fila.
class _AmountConsequenceNote extends StatelessWidget {
  const _AmountConsequenceNote({
    required this.suggestedLabel,
    required this.typedLabel,
    required this.remainingLabel,
  });

  final String suggestedLabel;
  final String typedLabel;
  final String remainingLabel;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final active = _amountCaseOf(typedLabel, suggestedLabel);
    if (active == _AmountCase.empty) return const SizedBox.shrink();
    final (tone, message) = switch (active) {
      _AmountCase.exact => (
          visual.success,
          'Calza exacto con lo calculado. Al guardar, la fila queda Pagada y '
              'la semana recalcula su saldo.',
        ),
      _AmountCase.over => (
          visual.warning,
          'Se transfirió más de lo calculado. Al guardar queda registrada la '
              'diferencia; las horas no se tocan.',
        ),
      _AmountCase.partial => (
          visual.warning,
          'Es un pago parcial. La fila vuelve con «Registrar resto» y la '
              'semana baja sólo lo transferido: quedan $remainingLabel.',
        ),
      _AmountCase.empty => (visual.neutral, ''),
    };
    return Container(
      key: const ValueKey<String>('payroll-composer-consequence'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: tone.soft,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: tone.border),
      ),
      child: Text(
        message,
        style: visual.bodyS.copyWith(fontSize: 11, color: tone.fg),
      ),
    );
  }
}

class _PaymentAmountBlock extends StatelessWidget {
  const _PaymentAmountBlock({
    required this.controller,
    required this.maximumLabel,
    required this.remainingLabel,
    required this.suggestedLabel,
    this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String maximumLabel;
  final String remainingLabel;

  /// Lo que la semana espera de esta transferencia. Es contra esto que se
  /// declara si el pago fue completo, con diferencia o parcial.
  final String suggestedLabel;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final hasError = errorText?.isNotEmpty == true;
    return Container(
      key: const ValueKey<String>('payroll-composer-amount-block'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(
          color: hasError ? visual.warningFg : visual.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('TRANSFERENCIA', style: visual.overline),
          const SizedBox(height: 6),
          // 5e: el caso se DECLARA, no se infiere del monto. Antes, teclear
          // menos de lo esperado se interpretaba solo como «pago parcial»: un
          // dedazo se convertía en una decisión de negocio sin que nadie la
          // tomara. El segmentado no cambia ninguna regla —la validación
          // sigue siendo la misma— pero obliga a nombrar el caso, y la nota de
          // abajo dice la consecuencia exacta antes de guardar.
          _AmountCaseStrip(
            suggestedLabel: suggestedLabel,
            typedLabel: controller.text,
          ),
          const SizedBox(height: 8),
          Semantics(
            textField: true,
            label: 'Monto de esta transferencia',
            child: TextField(
              key: const ValueKey<String>('payroll-composer-amount-field'),
              controller: controller,
              onChanged: onChanged,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: const <TextInputFormatter>[
                _ClpThousandsFormatter(),
              ],
              style: visual.numCard.copyWith(
                fontSize: 20,
                color: visual.ink,
              ),
              decoration: InputDecoration(
                prefixText: '\$ ',
                prefixStyle: visual.numCard.copyWith(
                  fontSize: 20,
                  color: visual.inkMuted,
                ),
                isDense: true,
                filled: true,
                fillColor: visual.surfaceSunken,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PayrollTokens.rField),
                  borderSide: BorderSide(
                    color: hasError ? visual.warningFg : visual.borderStrong,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(PayrollTokens.rField),
                  borderSide: BorderSide(
                    color: visual.accent,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 4,
            spacing: 12,
            children: <Widget>[
              Text(
                'Máximo disponible $maximumLabel',
                style: visual.bodyS.copyWith(
                  fontSize: 10.5,
                  color: visual.inkFaint,
                ),
              ),
              Text(
                remainingLabel == '\$0'
                    ? 'El saldo queda cubierto'
                    : 'Quedará pendiente $remainingLabel',
                style: visual.bodyS.copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: remainingLabel == '\$0'
                      ? visual.successFg
                      : visual.warningFg,
                ),
              ),
            ],
          ),
          if (!hasError) ...<Widget>[
            const SizedBox(height: 8),
            _AmountConsequenceNote(
              suggestedLabel: suggestedLabel,
              typedLabel: controller.text,
              remainingLabel: remainingLabel,
            ),
          ],
          if (hasError) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              errorText!,
              key: const ValueKey<String>('payroll-composer-amount-error'),
              style: visual.bodyS.copyWith(
                fontSize: 10.5,
                color: visual.warningFg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClpThousandsFormatter extends TextInputFormatter {
  const _ClpThousandsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final normalized = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final reversed = normalized.split('').reversed.toList(growable: false);
    final grouped = <String>[];
    for (var index = 0; index < reversed.length; index++) {
      if (index > 0 && index % 3 == 0) grouped.add('.');
      grouped.add(reversed[index]);
    }
    final formatted = grouped.reversed.join();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _AdvanceRow extends StatelessWidget {
  const _AdvanceRow({
    required this.vm,
    required this.touchOptimized,
  });

  final PayrollAdvanceVM vm;
  final bool touchOptimized;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Semantics(
      button: true,
      checked: vm.applied,
      label: '${vm.reason}, ${vm.amountLabel}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: vm.onToggle,
          mouseCursor: SystemMouseCursors.click,
          hoverColor: visual.accentSoft.withValues(alpha: 0.55),
          focusColor: visual.accentSoft,
          child: Container(
            constraints: BoxConstraints(
              minHeight: touchOptimized ? PayrollTokens.touchMobile : 0,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              // An advance chosen for this payment is a committed control
              // state: the filled checkbox plus the accent border carry it.
              // The selection-container fill stays reserved for the
              // selected week/History meaning.
              color: visual.surface,
              borderRadius: BorderRadius.circular(PayrollTokens.rField),
              border: Border.all(
                  color: vm.applied ? visual.accentBorder : visual.border),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 17,
                  height: 17,
                  decoration: BoxDecoration(
                    // accent-fill: selection — checked indicator of the
                    // advance chosen for this payment; the row is the control.
                    color: vm.applied ? visual.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: vm.applied ? visual.accent : visual.borderStrong,
                        width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: vm.applied
                      ? Icon(
                          Icons.check,
                          size: 11,
                          color: visual.onAccent,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(vm.reason,
                          style: visual.bodyM
                              .copyWith(fontWeight: FontWeight.w500)),
                      Text(vm.meta,
                          style: visual.monoS.copyWith(fontSize: 10.5)),
                    ],
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(vm.amountLabel,
                      style: visual.monoM.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: vm.applied ? visual.accent : visual.inkMuted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EquationStrip extends StatelessWidget {
  const _EquationStrip({
    required this.earned,
    required this.applied,
    required this.result,
  });
  final String earned;
  final String applied;
  final String result;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: visual.surfaceSunken,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                children: <Widget>[
                  Text(earned, style: visual.monoM.copyWith(fontSize: 11.5)),
                  const SizedBox(width: 10),
                  Text(applied,
                      style: visual.monoM.copyWith(
                        fontSize: 11.5,
                        color: visual.inkFaint,
                      )),
                  const SizedBox(width: 10),
                  Text('=',
                      style: visual.monoM.copyWith(
                        fontSize: 11.5,
                        color: visual.inkFaint,
                      )),
                  const SizedBox(width: 10),
                  Text(result,
                      style: visual.numCard.copyWith(
                        fontSize: 17,
                        color: visual.accent,
                      )),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            'dinero nuevo',
            style: visual.bodyS.copyWith(
              fontSize: 10,
              color: visual.inkFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _HowPaidBlock extends StatelessWidget {
  const _HowPaidBlock({
    required this.methods,
    required this.selected,
    required this.dateLabel,
    required this.reference,
    required this.touchOptimized,
    required this.stackFields,
    required this.methodLocked,
    this.onSelectMethod,
    this.onPickDate,
    this.referenceController,
  });
  final List<String> methods;
  final String selected;
  final String dateLabel;
  final String reference;
  final bool touchOptimized;
  final bool stackFields;
  final bool methodLocked;
  final ValueChanged<String>? onSelectMethod;
  final VoidCallback? onPickDate;
  final TextEditingController? referenceController;

  bool _isCashMethod(String method) {
    final normalized = method.trim().toLowerCase();
    return normalized == 'efectivo' ||
        normalized == 'cash' ||
        normalized.startsWith('efectivo ·') ||
        normalized.startsWith('cash ·');
  }

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    Widget methodOption(String method) {
      final isSelected = method == selected;
      final selectable =
          onSelectMethod != null && !methodLocked && !_isCashMethod(method);

      return Semantics(
        button: true,
        selected: isSelected,
        enabled: selectable,
        label: method,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(PayrollTokens.rField),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: selectable ? () => onSelectMethod!(method) : null,
            mouseCursor: selectable
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            hoverColor: visual.accentSoft.withValues(alpha: 0.55),
            focusColor: visual.accentSoft,
            child: Container(
              key: ValueKey<String>('payroll-payment-method-$method'),
              height: touchOptimized ? PayrollTokens.touchMobile : 34,
              decoration: BoxDecoration(
                // accent-fill: selection — the selected method chip is a
                // selection state inside the segmented selector, not a CTA.
                color: isSelected
                    ? visual.accent
                    : selectable
                        ? visual.surface
                        : visual.surfaceSunken,
                borderRadius: BorderRadius.circular(PayrollTokens.rField),
                border: Border.all(
                  color: isSelected ? visual.accent : visual.borderStrong,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                method,
                style: visual.labelStrong.copyWith(
                  fontSize: 11.5,
                  color: isSelected
                      ? visual.onAccent
                      : selectable
                          ? visual.inkMuted
                          : visual.inkDisabled,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text('MÉTODO', style: visual.overline),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    for (int i = 0; i < methods.length; i++) ...<Widget>[
                      Expanded(child: methodOption(methods[i])),
                      if (i != methods.length - 1) const SizedBox(width: 6),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: visual.border),
          if (stackFields) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              child: Semantics(
                button: true,
                enabled: onPickDate != null,
                label: 'Elegir fecha de pago, $dateLabel',
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(PayrollTokens.rField),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onPickDate,
                    mouseCursor: onPickDate == null
                        ? SystemMouseCursors.basic
                        : SystemMouseCursors.click,
                    hoverColor: visual.accentSoft.withValues(alpha: 0.55),
                    focusColor: visual.accentSoft,
                    child: _Field(
                      key: const ValueKey<String>(
                        'payroll-composer-date-field',
                      ),
                      label: 'FECHA',
                      value: dateLabel,
                      mono: true,
                      touchOptimized: touchOptimized,
                    ),
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: visual.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              child: _Field(
                key: const ValueKey<String>(
                  'payroll-composer-reference-field',
                ),
                label: 'REFERENCIA',
                value: reference,
                mono: true,
                focused: true,
                controller: referenceController,
                touchOptimized: touchOptimized,
              ),
            ),
          ] else
            // IntrinsicHeight: el Row estirado vive dentro de un scroll sin
            // altura acotada; sin esto el stretch no puede resolverse.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: visual.border),
                        ),
                      ),
                      child: Semantics(
                        button: true,
                        enabled: onPickDate != null,
                        label: 'Elegir fecha de pago, $dateLabel',
                        child: Material(
                          color: Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(PayrollTokens.rField),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: onPickDate,
                            mouseCursor: onPickDate == null
                                ? SystemMouseCursors.basic
                                : SystemMouseCursors.click,
                            hoverColor:
                                visual.accentSoft.withValues(alpha: 0.55),
                            focusColor: visual.accentSoft,
                            child: _Field(
                              key: const ValueKey<String>(
                                'payroll-composer-date-field',
                              ),
                              label: 'FECHA',
                              value: dateLabel,
                              mono: true,
                              touchOptimized: touchOptimized,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 12,
                      ),
                      child: _Field(
                        key: const ValueKey<String>(
                          'payroll-composer-reference-field',
                        ),
                        label: 'REFERENCIA',
                        value: reference,
                        mono: true,
                        focused: true,
                        controller: referenceController,
                        touchOptimized: touchOptimized,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: visual.surfaceSunken,
              border: Border(top: BorderSide(color: visual.border)),
            ),
            child: Text(
                'La referencia queda como respaldo del pago. La conciliación '
                'compara persona, fecha y monto; si la evidencia no basta, '
                'el movimiento queda como caso a revisar.',
                style: visual.bodyS.copyWith(
                  fontSize: 10.5,
                  color: visual.inkFaint,
                )),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.label,
    required this.value,
    this.mono = false,
    this.focused = false,
    this.controller,
    this.touchOptimized = false,
  });
  final String label;
  final String value;
  final bool mono;
  final bool focused;
  final TextEditingController? controller;
  final bool touchOptimized;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(label, style: visual.overline),
        const SizedBox(height: 6),
        Container(
          height:
              touchOptimized ? PayrollTokens.touchMobile : PayrollTokens.fieldH,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: visual.surface,
            borderRadius: BorderRadius.circular(PayrollTokens.rField),
            border: Border.all(
              color: focused ? visual.accent : visual.border,
            ),
            boxShadow: focused
                ? <BoxShadow>[
                    BoxShadow(
                      color: visual.accent.withValues(alpha: 0.12),
                      spreadRadius: 3,
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: controller != null
              ? TextField(
                  controller: controller,
                  style: visual.monoM.copyWith(
                    fontSize: 12,
                    color: visual.ink,
                  ),
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                  ),
                )
              : Text(value,
                  style: mono
                      ? visual.monoM.copyWith(
                          fontSize: 12,
                          color: visual.ink,
                        )
                      : visual.bodyM),
        ),
      ],
    );
  }
}
