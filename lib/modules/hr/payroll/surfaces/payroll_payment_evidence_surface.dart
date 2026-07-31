import 'package:flutter/material.dart';

import '../theme/payroll_tokens.dart';

@immutable
class PayrollPaymentEvidenceVM {
  const PayrollPaymentEvidenceVM({
    required this.personName,
    required this.weekLabel,
    required this.total,
    required this.newMoneyPaid,
    required this.advancesApplied,
    required this.balance,
    required this.entries,
  });

  final String personName;
  final String weekLabel;
  final String total;
  final String newMoneyPaid;
  final String advancesApplied;
  final String balance;
  final List<PayrollPaymentEvidenceEntryVM> entries;
}

@immutable
class PayrollPaymentEvidenceEntryVM {
  const PayrollPaymentEvidenceEntryVM({
    required this.id,
    required this.kind,
    required this.amount,
    required this.date,
    required this.source,
    this.method,
    this.account,
    this.reference,
    this.actor,
    this.cashMovement,
    this.variance,
    this.observedTransactionDate,
    this.observedDescription,
    this.observedDocument,
    this.observedLocation,
    this.hasAccountingEntry = false,
    this.journalNumber,
    this.journalLines = const [],
  });

  final String id;
  final String kind;
  final String amount;
  final String date;
  final String source;
  final String? method;
  final String? account;
  final String? reference;
  final String? actor;
  final String? cashMovement;
  final String? variance;
  final String? observedTransactionDate;
  final String? observedDescription;
  final String? observedDocument;
  final String? observedLocation;

  /// Las dos cuentas del asiento que dejó este movimiento. `debitAccount` es
  /// el gasto que se reconoce (sueldos) y `creditAccount` de dónde salió la
  /// plata. Se muestran juntas y con el mismo monto porque un asiento que no
  /// cuadra no es un asiento.
  final bool hasAccountingEntry;

  /// Número del asiento ("AC-01910") para poder ir a buscarlo en Contabilidad.
  final String? journalNumber;

  /// Las líneas del asiento tal como quedaron registradas: etiqueta y monto.
  final List<(String, String)> journalLines;

  bool get hasObservedStatementMetadata =>
      observedTransactionDate?.trim().isNotEmpty == true ||
      observedDescription?.trim().isNotEmpty == true ||
      observedDocument?.trim().isNotEmpty == true ||
      observedLocation?.trim().isNotEmpty == true;
}

/// Read-only audit surface opened from the clickable `Pagado` decision.
///
/// It deliberately lists every movement instead of collapsing partial
/// payments and advance allocations into one number.
class PayrollPaymentEvidenceSurface extends StatelessWidget {
  const PayrollPaymentEvidenceSurface({
    super.key,
    required this.value,
    required this.onClose,
  });

  final PayrollPaymentEvidenceVM value;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final phone = media.size.width < 600;
    final visual = PayrollVisualTokens.of(context);
    return ColoredBox(
      key: const ValueKey<String>('payroll-payment-evidence-surface'),
      color: visual.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EvidenceHeader(
            value: value,
            phone: phone,
            onClose: onClose,
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                phone ? 14 : 18,
                16,
                phone ? 14 : 18,
                media.padding.bottom + 20,
              ),
              children: [
                _SettlementEquation(value: value, phone: phone),
                const SizedBox(height: 18),
                Text('MOVIMIENTOS REGISTRADOS', style: visual.overline),
                const SizedBox(height: 8),
                if (value.entries.isEmpty)
                  const _LegacyEvidenceNotice()
                else
                  for (var index = 0;
                      index < value.entries.length;
                      index++) ...[
                    _EvidenceEntry(
                      entry: value.entries[index],
                      index: index,
                    ),
                    if (index != value.entries.length - 1)
                      const SizedBox(height: 8),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceHeader extends StatelessWidget {
  const _EvidenceHeader({
    required this.value,
    required this.phone,
    required this.onClose,
  });

  final PayrollPaymentEvidenceVM value;
  final bool phone;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return ColoredBox(
      color: visual.shell,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(phone ? 14 : 18, 12, 8, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value.weekLabel.toUpperCase(),
                      style: visual.overline.copyWith(
                        color: visual.onShellMuted,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      value.personName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: visual.recordTitle.copyWith(fontSize: 17),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Respaldo de pago · solo lectura',
                      style: visual.bodyS.copyWith(
                        color: visual.onShellMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: const ValueKey<String>('payroll-payment-evidence-close'),
                onPressed: onClose,
                tooltip: 'Volver a Nóminas',
                mouseCursor: SystemMouseCursors.click,
                constraints: BoxConstraints.tightFor(
                  width: phone ? PayrollTokens.touchMobile : 38,
                  height: phone ? PayrollTokens.touchMobile : 38,
                ),
                icon: Icon(
                  Icons.close,
                  size: 19,
                  color: visual.onShell,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettlementEquation extends StatelessWidget {
  const _SettlementEquation({required this.value, required this.phone});

  final PayrollPaymentEvidenceVM value;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final figures = [
      ('TOTAL SEMANA', value.total),
      ('DINERO PAGADO', value.newMoneyPaid),
      ('ANTICIPOS APLICADOS', value.advancesApplied),
      ('SALDO', value.balance),
    ];
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
        border: Border.all(color: visual.borderStrong),
      ),
      child: phone
          ? Wrap(
              spacing: 18,
              runSpacing: 14,
              children: [
                for (final figure in figures)
                  SizedBox(
                    width: 132,
                    child: _EvidenceFigure(
                      label: figure.$1,
                      value: figure.$2,
                    ),
                  ),
              ],
            )
          : Row(
              children: [
                for (var index = 0; index < figures.length; index++) ...[
                  Expanded(
                    child: _EvidenceFigure(
                      label: figures[index].$1,
                      value: figures[index].$2,
                    ),
                  ),
                  if (index != figures.length - 1) const SizedBox(width: 12),
                ],
              ],
            ),
    );
  }
}

class _EvidenceFigure extends StatelessWidget {
  const _EvidenceFigure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: visual.overline),
        const SizedBox(height: 4),
        Text(value, style: visual.numRow),
      ],
    );
  }
}

class _EvidenceEntry extends StatelessWidget {
  const _EvidenceEntry({required this.entry, required this.index});

  final PayrollPaymentEvidenceEntryVM entry;
  final int index;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final rows = <(String, String)>[
      if (entry.method?.trim().isNotEmpty == true)
        ('Método', entry.method!.trim()),
      if (entry.account?.trim().isNotEmpty == true)
        ('Cuenta', entry.account!.trim()),
      if (entry.reference?.trim().isNotEmpty == true)
        ('Referencia', entry.reference!.trim()),
      if (entry.actor?.trim().isNotEmpty == true)
        ('Registrado por', entry.actor!.trim()),
      if (entry.cashMovement?.trim().isNotEmpty == true)
        ('Anticipo entregado', entry.cashMovement!.trim()),
      ('Origen', entry.source),
    ];
    // El asiento va en su propio bloque y no mezclado con los atributos del
    // pago: Debe y Haber son UN hecho de dos lados que tienen que cuadrar, y
    // como dos filas sueltas más se leerían como dos datos independientes.
    final hasEntry = entry.hasAccountingEntry && entry.journalLines.isNotEmpty;
    return Container(
      key: ValueKey<String>('payroll-payment-evidence-${entry.id}'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: entry.kind == 'Anticipo aplicado'
                      ? visual.warningSoft
                      : visual.successSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  entry.kind == 'Anticipo aplicado'
                      ? Icons.account_balance_wallet_outlined
                      : Icons.check,
                  size: 15,
                  color: entry.kind == 'Anticipo aplicado'
                      ? visual.warningFg
                      : visual.successFg,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.kind, style: visual.cardTitle),
                    const SizedBox(height: 2),
                    Text(entry.date, style: visual.monoS),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(entry.amount, style: visual.numRow),
            ],
          ),
          const SizedBox(height: 12),
          for (final row in rows) ...[
            _EvidenceFact(label: row.$1, value: row.$2),
            if (row != rows.last) const SizedBox(height: 7),
          ],
          if (hasEntry) ...[
            const SizedBox(height: 11),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              decoration: BoxDecoration(
                color: visual.surfaceSunken,
                borderRadius: BorderRadius.circular(PayrollTokens.rField),
                border: Border.all(color: visual.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('ASIENTO CONTABLE', style: visual.overline),
                      ),
                      if (entry.journalNumber?.trim().isNotEmpty == true)
                        Text(
                          entry.journalNumber!.trim(),
                          style: visual.monoS.copyWith(
                            fontSize: 10,
                            color: visual.accent,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Las líneas TAL COMO quedaron en el libro. No se derivan ni
                  // se completan: si el asiento tiene tres líneas, se ven tres.
                  for (var i = 0; i < entry.journalLines.length; i++) ...[
                    if (i != 0) const SizedBox(height: 7),
                    _EvidenceFact(
                      label: entry.journalLines[i].$1,
                      value: entry.journalLines[i].$2,
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (entry.hasObservedStatementMetadata) ...[
            const SizedBox(height: 12),
            _StatementObservation(entry: entry),
          ],
          if (entry.variance?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: visual.warningSoft,
                borderRadius: BorderRadius.circular(PayrollTokens.rField),
                border: Border.all(color: visual.warningBorder),
              ),
              child: Text(
                entry.variance!,
                style: visual.bodyS.copyWith(
                  color: visual.warningFg,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatementObservation extends StatelessWidget {
  const _StatementObservation({required this.entry});

  final PayrollPaymentEvidenceEntryVM entry;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final facts = <(String, String)>[
      if (entry.observedTransactionDate?.trim().isNotEmpty == true)
        ('Fecha bancaria', entry.observedTransactionDate!.trim()),
      if (entry.observedDocument?.trim().isNotEmpty == true)
        ('Documento', entry.observedDocument!.trim()),
      if (entry.observedLocation?.trim().isNotEmpty == true)
        ('Ubicación', entry.observedLocation!.trim()),
    ];
    final description = entry.observedDescription?.trim();

    return Semantics(
      label: 'Movimiento observado en cartola',
      readOnly: true,
      child: Container(
        key: ValueKey<String>(
          'payroll-payment-statement-observation-${entry.id}',
        ),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: visual.surfaceSunken,
          borderRadius: BorderRadius.circular(PayrollTokens.rField),
          border: Border.all(color: visual.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'MOVIMIENTO OBSERVADO EN CARTOLA',
              style: visual.overline.copyWith(
                color: visual.accent,
              ),
            ),
            if (description?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              SelectableText(
                description!,
                style: visual.bodyS.copyWith(
                  color: visual.ink,
                ),
              ),
            ],
            if (facts.isNotEmpty) ...[
              const SizedBox(height: 9),
              for (var index = 0; index < facts.length; index++) ...[
                _EvidenceFact(
                  label: facts[index].$1,
                  value: facts[index].$2,
                ),
                if (index != facts.length - 1) const SizedBox(height: 7),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _EvidenceFact extends StatelessWidget {
  const _EvidenceFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 104, child: Text(label, style: visual.label)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: visual.bodyS.copyWith(color: visual.ink),
          ),
        ),
      ],
    );
  }
}

class _LegacyEvidenceNotice extends StatelessWidget {
  const _LegacyEvidenceNotice();

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: visual.warningSoft,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: visual.warningFg,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Este pago pertenece al historial anterior al registro '
              'versionado. El monto está conciliado, pero el servidor antiguo '
              'no conservó fecha, referencia y actor por movimiento.',
              style: visual.bodyS.copyWith(
                color: visual.warningFg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
