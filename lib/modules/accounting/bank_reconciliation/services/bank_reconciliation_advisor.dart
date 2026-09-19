import '../models/bank_reconciliation_models.dart';
import 'bank_counterparty_identity.dart';

/// Proposes what to do with a movement no existing ERP operation explains.
///
/// The order is from firmest to loosest evidence: a pair of movements that
/// cancel each other, what the operator decided for the same counterparty on
/// an earlier statement, a salary Nómina still owes, an open invoice, how the
/// counterparty was booked before, and finally what the merchant name on a
/// card charge says. A suggestion that this workspace can apply carries a
/// prefilled decision, a salary Nómina owes included: applying it pays the
/// salary through Nómina's own command. One that belongs to another module
/// (registering a purchase or a sale) only says where to do it.
class BankReconciliationAdvisor {
  const BankReconciliationAdvisor();

  Map<String, BankReconciliationSuggestion> suggest({
    required List<BankStatementMovement> movements,
    required Map<String, List<BankReconciliationProposal>> proposals,
    required BankReconciliationContext context,
    BankReconciliationWorkspaceOptions? options,
  }) {
    final open = movements.where((movement) {
      final rowProposals = proposals[movement.sourceRowId] ??
          const <BankReconciliationProposal>[];
      return movement.amountClp != null &&
          movement.bookingDate != null &&
          !rowProposals.any((proposal) => proposal.isSelectedByDefault);
    }).toList(growable: false);
    final result = <String, BankReconciliationSuggestion>{};
    result.addAll(_offsettingPairs(open));
    // One salary is paid by one transfer.
    final claimedPayrollLines = <String>{};
    final advancesByLine = _assignAdvances(context);
    for (final movement in open) {
      if (result.containsKey(movement.sourceRowId)) continue;
      final suggestion = _suggestOne(
        movement,
        hasProposal: (proposals[movement.sourceRowId] ?? const []).isNotEmpty,
        context: context,
        options: options,
        claimedPayrollLines: claimedPayrollLines,
        advancesByLine: advancesByLine,
      );
      if (suggestion != null) result[movement.sourceRowId] = suggestion;
    }
    return result;
  }

  /// Insights about the review as a whole, derived from the suggestions.
  List<BankReconciliationInsight> insights(
    Map<String, BankReconciliationSuggestion> suggestions,
  ) {
    final salaries = suggestions.values
        .where((item) =>
            item.kind == BankSuggestionKind.payroll &&
            item.confidence == BankReconciliationConfidence.high)
        .toList(growable: false);
    final payableHere =
        salaries.where((item) => item.resolution != null).length;
    final elsewhere = salaries.length - payableHere;
    return <BankReconciliationInsight>[
      if (payableHere > 0)
        BankReconciliationInsight(
          title: '$payableHere sueldo(s) que Nómina debe se pagan aquí',
          body: 'Al aplicar, cada sueldo queda pagado en Nómina con la fecha '
              'de la cartola y asociado a su transferencia; una semana en '
              'borrador se confirma. Si prefieres, págalos en Nómina y la '
              'próxima conciliación los asocia solos.',
        ),
      if (elsewhere > 0)
        BankReconciliationInsight(
          title: '$elsewhere transferencia(s) pagan sueldos que Nómina tiene '
              'pendientes',
          body: 'Nómina todavía no registra esos pagos. Págalos en Nómina '
              '(puedes usar esta misma cartola) y la próxima conciliación los '
              'asocia solos.',
        ),
    ];
  }

  Map<String, BankReconciliationSuggestion> _offsettingPairs(
    List<BankStatementMovement> movements,
  ) {
    final result = <String, BankReconciliationSuggestion>{};
    final debits = movements
        .where((movement) => movement.direction == BankMovementDirection.debit)
        .toList(growable: false);
    for (final credit in movements.where(
      (movement) => movement.direction == BankMovementDirection.credit,
    )) {
      BankStatementMovement? partner;
      var partnerDistance = 1 << 30;
      for (final debit in debits) {
        if (result.containsKey(debit.sourceRowId)) continue;
        if (debit.amountClp != credit.amountClp) continue;
        final distance =
            debit.bookingDate!.daysUntil(credit.bookingDate!).abs();
        if (distance > 3) continue;
        final identity = BankCounterpartyIdentity.compare(
          _party(credit),
          <String>[_party(debit)],
        );
        if (!identity.isStrong) continue;
        if (distance < partnerDistance) {
          partner = debit;
          partnerDistance = distance;
        }
      }
      if (partner == null) continue;
      String reason(BankStatementMovement other) =>
          'Transferencia devuelta: se compensa con el movimiento del '
          '${_day(other.bookingDate!)} por ${_money(other.amountClp!)}.';
      result[credit.sourceRowId] = BankReconciliationSuggestion(
        kind: BankSuggestionKind.dismiss,
        confidence: BankReconciliationConfidence.high,
        title: 'Devolución de ${_displayParty(partner)}',
        reasons: <String>[
          'Mismo monto y misma persona, en sentido contrario',
          'Juntos no mueven el saldo: no se contabilizan',
        ],
        resolution: BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.dismiss,
          reason: reason(partner),
        ),
        relatedSourceRowId: partner.sourceRowId,
      );
      result[partner.sourceRowId] = BankReconciliationSuggestion(
        kind: BankSuggestionKind.dismiss,
        confidence: BankReconciliationConfidence.high,
        title: 'Transferencia devuelta por ${_displayParty(credit)}',
        reasons: <String>[
          'Mismo monto y misma persona, en sentido contrario',
          'Juntos no mueven el saldo: no se contabilizan',
        ],
        resolution: BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.dismiss,
          reason: reason(credit),
        ),
        relatedSourceRowId: credit.sourceRowId,
      );
    }
    return result;
  }

  BankReconciliationSuggestion? _suggestOne(
    BankStatementMovement movement, {
    required bool hasProposal,
    required BankReconciliationContext context,
    required BankReconciliationWorkspaceOptions? options,
    required Set<String> claimedPayrollLines,
    required Map<String, List<BankPayrollAdvanceUse>> advancesByLine,
  }) {
    final party = _party(movement);
    final amount = movement.amountClp!;
    final date = movement.bookingDate!;
    final isCardCharge = _isCardCharge(movement);
    final isDebit = movement.direction == BankMovementDirection.debit;

    // 1. What the operator decided for this counterparty before.
    final prior = _priorDecision(movement, context.decisions);
    if (prior != null) {
      final resolution = _resolutionFromPrior(movement, prior, options);
      if (resolution != null) {
        return BankReconciliationSuggestion(
          kind: switch (prior.action) {
            BankReconciliationActionKind.createExpense =>
              BankSuggestionKind.createExpense,
            BankReconciliationActionKind.dismiss => BankSuggestionKind.dismiss,
            BankReconciliationActionKind.split => BankSuggestionKind.split,
            _ => BankSuggestionKind.postJournal,
          },
          // A split repeats its structure, not its amounts: what the
          // accountant, the F29 or the licence cost changes every month.
          confidence: prior.action == BankReconciliationActionKind.split
              ? BankReconciliationConfidence.medium
              : BankReconciliationConfidence.high,
          title: prior.action == BankReconciliationActionKind.split
              ? 'Dividir como la vez anterior'
              : prior.supplierName ?? prior.text ?? _displayParty(movement),
          reasons: <String>[
            'Así resolviste "${prior.counterparty ?? prior.description}" en '
                'una conciliación anterior',
            if (prior.action == BankReconciliationActionKind.split)
              resolution.splitParts.map((part) => part.description).join(' + '),
          ],
          followUp: prior.action == BankReconciliationActionKind.split
              ? 'Revisa los montos de cada parte: la última toma lo que queda.'
              : null,
          resolution: resolution,
        );
      }
    }

    // 2. A salary Nómina still owes, net of the advances it already paid.
    if (isDebit && !isCardCharge) {
      final match = _payrollMatch(
        party,
        amount,
        date,
        context.payrollLines
            .where((item) => !claimedPayrollLines.contains(item.lineId))
            .toList(growable: false),
        advancesByLine,
      );
      if (match != null) {
        final line = match.line;
        claimedPayrollLines.add(line.lineId);
        // Money before the week's close is an advance for Nómina, never
        // this week's salary: offering it here would fail the whole apply.
        final beforeClose = !line.acceptsSalaryOn(date);
        final payment = beforeClose
            ? null
            : _payrollPayment(line, amount, options, advances: match.advances);
        final missing =
            match.partial && payment != null ? payment.owedAfterClp : 0;
        return BankReconciliationSuggestion(
          kind: BankSuggestionKind.payroll,
          confidence: match.partial
              ? BankReconciliationConfidence.medium
              : BankReconciliationConfidence.high,
          title: match.partial
              ? 'Parte del sueldo de ${line.employeeName} · ${line.periodLabel}'
              : 'Sueldo de ${line.employeeName} · ${line.periodLabel}',
          reasons: <String>[
            'Nómina ${line.voucherNumber} le debe ${_money(line.amountClp)} '
                'y aún no registra el pago',
            for (final use in match.advances)
              'Descuenta el anticipo ${use.advance.isCash ? 'en efectivo ' : ''}'
                  'del ${_day(use.advance.paidOn)}: ${_money(use.amountClp)}',
            if (match.advances.isNotEmpty && !match.partial)
              'La transferencia paga el resto',
            if (!match.partial &&
                match.advances.isEmpty &&
                line.amountClp != amount)
              'La transferencia redondea ${_money((amount - line.amountClp).abs())}',
            if (missing > 0)
              'Esta transferencia cubre ${_money(amount)}: faltan '
                  '${_money(missing)}',
            if (beforeClose)
              'Se transfirió antes del cierre de la semana '
                  '(${_day(line.payableFrom ?? line.periodEnd)}): para Nómina '
                  'es un anticipo, no el sueldo',
            if (payment != null)
              line.isDraft
                  ? 'Al aplicar, la semana ${line.voucherNumber} (en borrador) '
                      'se confirma y el sueldo queda pagado el ${_day(date)}'
                  : 'Al aplicar, el sueldo queda pagado en Nómina el '
                      '${_day(date)}',
          ],
          resolution: payment == null
              ? null
              : BankReconciliationResolutionDraft(
                  action: BankReconciliationActionKind.payPayroll,
                  payroll: payment,
                ),
          followUp: beforeClose
              ? 'Regístralo como anticipo de ${line.employeeName} en Nómina; '
                  'al pagar la semana ${line.voucherNumber} se descuenta.'
              : missing > 0
                  ? '¿Esos ${_money(missing)} fueron un anticipo que no '
                      'registraste (en efectivo o por transferencia durante la '
                      'semana)? Regístralo en Nómina y se descuenta del sueldo. '
                      'Si todavía se le deben, quedan pendientes en Nómina.'
                  : payment == null
                      ? 'Págalo en Nómina (${line.voucherNumber}); la próxima '
                          'conciliación lo asocia sola.'
                      : null,
        );
      }
    }

    final profile = _profile(party, context.parties);

    // 3. People on the payroll who are not being paid a pending salary.
    if (profile?.kind == BankCounterpartyKind.employee && !isCardCharge) {
      if (isDebit) {
        return BankReconciliationSuggestion(
          kind: BankSuggestionKind.payroll,
          confidence: BankReconciliationConfidence.medium,
          title: 'Transferencia a ${profile!.displayName}',
          reasons: const <String>[
            'No hay sueldo pendiente en Nómina por este monto',
          ],
          followUp: 'Si es un anticipo o un sueldo atrasado, regístralo en '
              'Nómina para que el pago quede en su ficha.',
        );
      }
      if (!hasProposal) {
        final capital = _accountByKeywords(options, const <String>['capital']);
        return BankReconciliationSuggestion(
          kind: BankSuggestionKind.postJournal,
          confidence: BankReconciliationConfidence.low,
          title: 'Ingreso de ${profile!.displayName}',
          reasons: const <String>[
            'Viene de una persona de la planilla y no hay venta que calce',
            'Si es aporte del dueño va a capital; si es un préstamo, elige la '
                'cuenta del préstamo',
          ],
          resolution: BankReconciliationResolutionDraft(
            action: BankReconciliationActionKind.classifyAccount,
            accountId: capital?.accountId,
            description: 'Aporte de ${profile.displayName}',
            reference: movement.documentNumber,
          ),
        );
      }
    }

    // 4. An open invoice waiting for exactly this payment.
    final invoice = _openInvoice(movement, party, context.openInvoices);
    if (invoice != null) {
      final sale = invoice.kind == BankOpenInvoiceKind.sale;
      return BankReconciliationSuggestion(
        kind: sale ? BankSuggestionKind.sale : BankSuggestionKind.purchase,
        confidence: BankReconciliationConfidence.high,
        title: sale
            ? 'Pago de la venta ${invoice.number}'
            : 'Pago de la compra ${invoice.number}',
        reasons: <String>[
          '${invoice.names.isEmpty ? 'La factura' : invoice.names.first} '
              'tiene ${_money(invoice.balanceClp > 0 ? invoice.balanceClp : invoice.totalClp)} '
              'por ${sale ? 'cobrar' : 'pagar'}',
        ],
        followUp: sale
            ? 'Registra el pago en Ventas (${invoice.number}) con pago por '
                'transferencia; la próxima conciliación lo asocia solo.'
            : 'Registra el pago en Compras (${invoice.number}); la próxima '
                'conciliación lo asocia solo.',
      );
    }

    // 5. A known supplier or payee: book it the way it was booked before.
    if (isDebit && profile != null) {
      final usual = profile.usual
          .where((item) => _expenseAccount(options, item.accountId) != null)
          .toList(growable: false);
      if (usual.isNotEmpty) {
        final booking = usual.first;
        final method = _method(
          options,
          isCardCharge ? 'card' : 'transfer',
          fallback: booking.paymentMethodCode,
        );
        final account = _expenseAccount(options, booking.accountId)!;
        return BankReconciliationSuggestion(
          kind: BankSuggestionKind.createExpense,
          confidence: booking.uses >= 2
              ? BankReconciliationConfidence.high
              : BankReconciliationConfidence.medium,
          title: '${account.name} · ${profile.displayName}',
          reasons: <String>[
            booking.uses >= 2
                ? 'Lo registraste ${booking.uses} veces en ${account.label}'
                : 'La última vez lo registraste en ${account.label}',
          ],
          resolution: BankReconciliationResolutionDraft(
            action: BankReconciliationActionKind.createExpense,
            accountId: account.accountId,
            paymentMethodId: method?.paymentMethodId,
            description: booking.lastDescription ?? account.name,
            counterparty: profile.displayName,
            reference: movement.documentNumber,
          ),
        );
      }
      if (profile.kind == BankCounterpartyKind.supplier &&
          profile.purchaseCount > 0) {
        return BankReconciliationSuggestion(
          kind: BankSuggestionKind.purchase,
          confidence: BankReconciliationConfidence.medium,
          title: 'Compra a ${profile.displayName} sin registrar',
          reasons: <String>[
            '${profile.displayName} es proveedor de mercadería y no hay una '
                'compra por ${_money(amount)}',
          ],
          followUp: 'Registra la factura en Compras con este pago; la '
              'próxima conciliación lo asocia solo.',
        );
      }
    }

    // 6. What the merchant on a card charge or a bank fee says.
    if (isDebit) {
      final merchant = _merchant(movement);
      if (merchant != null) {
        return _merchantSuggestion(movement, merchant, context, options);
      }
    }

    // 7. A card deposit that no registered sale explains.
    if (!isDebit && !hasProposal && _isAcquirerDeposit(movement)) {
      return BankReconciliationSuggestion(
        kind: BankSuggestionKind.sale,
        confidence: BankReconciliationConfidence.low,
        title: 'Abono de tarjetas sin ventas que calcen',
        reasons: const <String>[
          'Ninguna combinación de ventas con tarjeta registradas suma este '
              'abono',
        ],
        followUp: 'Revisa si falta registrar ventas con tarjeta de los días '
            'anteriores o si alguna quedó con otro medio de pago.',
      );
    }

    // 8. Money from someone with no sale.
    if (!isDebit && !hasProposal) {
      return BankReconciliationSuggestion(
        kind: BankSuggestionKind.sale,
        confidence: BankReconciliationConfidence.low,
        title: 'Transferencia de ${_displayParty(movement)} sin venta',
        reasons: const <String>[
          'No hay venta ni factura abierta por este monto',
        ],
        followUp: 'Si fue una venta, regístrala en Ventas con pago por '
            'transferencia; si es un abono o una devolución, clasifícala aquí.',
      );
    }
    return null;
  }

  BankPriorDecision? _priorDecision(
    BankStatementMovement movement,
    List<BankPriorDecision> decisions,
  ) {
    final party = _party(movement);
    final merchant = _merchant(movement)?.key;
    for (final decision in decisions) {
      if (decision.direction != movement.direction) continue;
      if (merchant != null) {
        final decided = _merchantKey(decision.description);
        if (decided == merchant) return decision;
        continue;
      }
      final identity = BankCounterpartyIdentity.compare(
        party,
        <String>[
          if (decision.counterparty != null) decision.counterparty!,
          decision.description,
        ],
      );
      if (identity.isStrong) return decision;
    }
    return null;
  }

  BankReconciliationResolutionDraft? _resolutionFromPrior(
    BankStatementMovement movement,
    BankPriorDecision prior,
    BankReconciliationWorkspaceOptions? options,
  ) {
    switch (prior.action) {
      case BankReconciliationActionKind.createExpense:
        final account = _expenseAccount(options, prior.accountId);
        if (account == null) return null;
        final method = options?.paymentMethods
            .where((item) => item.paymentMethodId == prior.paymentMethodId)
            .firstOrNull;
        return BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.createExpense,
          accountId: account.accountId,
          paymentMethodId: method?.paymentMethodId,
          description: prior.text ?? movement.description,
          counterparty: prior.supplierName,
          reference: movement.documentNumber,
        );
      case BankReconciliationActionKind.classifyAccount:
        final account = options?.accounts
            .where((item) => item.accountId == prior.accountId)
            .firstOrNull;
        if (account == null) return null;
        return BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.classifyAccount,
          accountId: account.accountId,
          description: prior.text ?? movement.description,
          reference: movement.documentNumber,
        );
      case BankReconciliationActionKind.dismiss:
        return BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.dismiss,
          reason: prior.text ?? 'Igual que en la conciliación anterior',
        );
      case BankReconciliationActionKind.split:
        final amount = movement.amountClp;
        if (amount == null || prior.parts.length < 2) return null;
        final parts = <BankSplitPartDraft>[];
        for (final part in prior.parts) {
          final account = options?.account(part.accountId);
          if (account == null) return null;
          final expense = account.canReceiveExpense &&
              movement.direction == BankMovementDirection.debit;
          parts.add(BankSplitPartDraft(
            accountId: account.accountId,
            amountClp: part.amountClp,
            description: part.description,
            supplierId: expense ? part.supplierId : null,
            isExpense: expense,
          ));
        }
        final withRest = BankSplitPartDraft.withRemainder(parts, amount);
        if (withRest.last.amountClp == null) return null;
        final method = options?.paymentMethods
                .where((item) => item.paymentMethodId == prior.paymentMethodId)
                .firstOrNull ??
            options?.paymentMethods
                .where((item) => item.code == 'transfer')
                .firstOrNull;
        return BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.split,
          paymentMethodId: method?.paymentMethodId,
          reference: movement.documentNumber,
          splitParts: withRest,
        );
      case BankReconciliationActionKind.associateExisting:
      case BankReconciliationActionKind.payPayroll:
      case BankReconciliationActionKind.pending:
        return null;
    }
  }

  /// The salary this transfer pays, through the bank's own transfer method.
  /// A transfer a little short pays that much and Nómina keeps the rest
  /// owed; one a little over pays the salary and the rounding stays on the
  /// row, as any direct association tolerates.
  BankPayrollPaymentDraft? _payrollPayment(
    BankPayrollExpectation line,
    int amount,
    BankReconciliationWorkspaceOptions? options, {
    List<BankPayrollAdvanceUse> advances = const <BankPayrollAdvanceUse>[],
  }) {
    final transfers = options?.paymentMethods
            .where((method) => method.code.trim().toLowerCase() == 'transfer')
            .toList(growable: false) ??
        const <BankReconciliationPaymentMethodOption>[];
    final method = transfers
            .where((item) => item.paymentMethodId == line.paymentMethodId)
            .firstOrNull ??
        (transfers.length == 1 ? transfers.single : null);
    final owedByBank = line.amountClp -
        advances.fold<int>(0, (sum, item) => sum + item.amountClp);
    final paid = amount < owedByBank ? amount : owedByBank;
    if (method == null || paid <= 0 || amount - paid > 1000) return null;
    return BankPayrollPaymentDraft(
      voucherId: line.voucherId,
      voucherNumber: line.voucherNumber,
      periodLabel: line.periodLabel,
      lineId: line.lineId,
      employeeName: line.employeeName,
      expectedAmountClp: line.amountClp,
      amountClp: paid,
      paymentMethodId: method.paymentMethodId,
      confirmDraft: line.isDraft,
      advances: advances,
    );
  }

  /// Open advances onto the weeks Nómina will discount them from: each
  /// worker's oldest owed week whose end is on or after the advance, as
  /// pay_payroll_voucher_v2 only takes an advance paid by the week's end.
  Map<String, List<BankPayrollAdvanceUse>> _assignAdvances(
    BankReconciliationContext context,
  ) {
    final result = <String, List<BankPayrollAdvanceUse>>{};
    final room = <String, int>{
      for (final line in context.payrollLines) line.lineId: line.amountClp,
    };
    final advances = [...context.openAdvances]
      ..sort((left, right) => left.paidOn.compareTo(right.paidOn));
    for (final advance in advances) {
      final lines = context.payrollLines
          .where((line) =>
              line.employeeId == advance.employeeId &&
              line.periodEnd.compareTo(advance.paidOn) >= 0)
          .toList(growable: false)
        ..sort((left, right) => left.periodEnd.compareTo(right.periodEnd));
      var left = advance.availableClp;
      for (final line in lines) {
        if (left <= 0) break;
        final free = room[line.lineId] ?? 0;
        final take = left < free ? left : free;
        if (take <= 0) continue;
        result
            .putIfAbsent(line.lineId, () => <BankPayrollAdvanceUse>[])
            .add(BankPayrollAdvanceUse(advance: advance, amountClp: take));
        room[line.lineId] = free - take;
        left -= take;
      }
    }
    return result;
  }

  /// The owed salary this transfer pays: exactly (net of the advances Nómina
  /// will discount, or in full), or — oldest week first — only in part,
  /// which usually means an advance nobody registered.
  _SalaryMatch? _payrollMatch(
    String party,
    int amount,
    BankCivilDate date,
    List<BankPayrollExpectation> lines,
    Map<String, List<BankPayrollAdvanceUse>> advancesByLine,
  ) {
    _SalaryMatch? best;
    var bestScore = 1 << 30;
    final rounding = amount ~/ 100;
    for (final line in lines) {
      if (line.paymentMethod == 'cash') continue;
      // Salaries go out on the Monday or Tuesday after the week, sometimes
      // weeks later; a transfer a few days before its end is recognised too,
      // to say it is an advance.
      final distance = line.periodEnd.daysUntil(date);
      if (distance < -3 || distance > 35) continue;
      if (!BankCounterpartyIdentity.compare(party, line.names).isStrong) {
        continue;
      }
      final uses =
          advancesByLine[line.lineId] ?? const <BankPayrollAdvanceUse>[];
      final net = line.amountClp -
          uses.fold<int>(0, (sum, item) => sum + item.amountClp);
      _SalaryMatch? candidate;
      var score = 0;
      if (uses.isNotEmpty && (net - amount).abs() <= rounding) {
        candidate = _SalaryMatch(line, uses, partial: false);
        score = (net - amount).abs() * 10 + distance.abs();
      } else if ((line.amountClp - amount).abs() <= rounding) {
        candidate = _SalaryMatch(line, const [], partial: false);
        score = (line.amountClp - amount).abs() * 10 + distance.abs();
      } else if (amount < net - rounding && line.acceptsSalaryOn(date)) {
        candidate = _SalaryMatch(line, uses, partial: true);
        // Behind every exact match; among partials the oldest week first.
        score = 100000 - distance;
      }
      if (candidate != null && score < bestScore) {
        best = candidate;
        bestScore = score;
      }
    }
    return best;
  }

  BankCounterpartyProfile? _profile(
    String party,
    List<BankCounterpartyProfile> parties,
  ) {
    BankCounterpartyProfile? best;
    var bestRank = -1;
    for (final profile in parties) {
      final identity = BankCounterpartyIdentity.compare(party, profile.names);
      if (!identity.isStrong) continue;
      // Prefer the party with booking history, then a goods supplier, then
      // a supplier record over a free-text payee.
      final rank = (profile.usual.isNotEmpty ? 4 : 0) +
          (profile.purchaseCount > 0 ? 2 : 0) +
          (profile.kind == BankCounterpartyKind.payee ? 0 : 1);
      if (rank > bestRank) {
        best = profile;
        bestRank = rank;
      }
    }
    return best;
  }

  /// A supplier whose own name is the merchant's (not a similar one).
  BankCounterpartyProfile? _profileNamed(
    String name,
    List<BankCounterpartyProfile> parties,
  ) {
    final wanted = BankCounterpartyIdentity.normalize(name);
    for (final profile in parties) {
      if (profile.names.any(
        (item) => BankCounterpartyIdentity.normalize(item) == wanted,
      )) {
        return profile;
      }
    }
    return null;
  }

  BankOpenInvoice? _openInvoice(
    BankStatementMovement movement,
    String party,
    List<BankOpenInvoice> invoices,
  ) {
    final kind = movement.direction == BankMovementDirection.credit
        ? BankOpenInvoiceKind.sale
        : BankOpenInvoiceKind.purchase;
    final amount = movement.amountClp!;
    final date = movement.bookingDate!;
    BankOpenInvoice? best;
    for (final invoice in invoices) {
      if (invoice.kind != kind) continue;
      final due =
          invoice.balanceClp > 0 ? invoice.balanceClp : invoice.totalClp;
      if (due != amount) continue;
      final distance = invoice.date.daysUntil(date);
      if (distance < -5 || distance > 90) continue;
      final identity = BankCounterpartyIdentity.compare(party, invoice.names);
      if (identity.isConflict) continue;
      if (!identity.isStrong && distance.abs() > 10) continue;
      best ??= invoice;
    }
    return best;
  }

  BankReconciliationSuggestion _merchantSuggestion(
    BankStatementMovement movement,
    _Merchant merchant,
    BankReconciliationContext context,
    BankReconciliationWorkspaceOptions? options,
  ) {
    if (merchant.isPurchase) {
      return BankReconciliationSuggestion(
        kind: BankSuggestionKind.purchase,
        confidence: BankReconciliationConfidence.medium,
        title: 'Compra en ${merchant.name}',
        reasons: <String>[
          'Cargo con tarjeta en ${merchant.name}',
        ],
        followUp: 'Si es mercadería, regístrala en Compras con pago con '
            'tarjeta; si es un insumo, créala aquí como gasto.',
      );
    }
    final profile = merchant.isBankFee
        ? null
        : _profileNamed(merchant.name, context.parties);
    final usual = profile?.usual
            .where((item) => _expenseAccount(options, item.accountId) != null)
            .toList(growable: false) ??
        const <BankUsualBooking>[];
    final account = usual.isNotEmpty
        ? _expenseAccount(options, usual.first.accountId)
        : _accountByKeywords(options, merchant.accountKeywords, expense: true);
    if (merchant.isBankFee) {
      return BankReconciliationSuggestion(
        kind: BankSuggestionKind.postJournal,
        confidence: account == null
            ? BankReconciliationConfidence.medium
            : BankReconciliationConfidence.high,
        title: merchant.description,
        reasons: <String>[
          'Cargo del banco: no tiene documento de proveedor',
          if (account != null) 'Va a ${account.label}',
        ],
        resolution: BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.classifyAccount,
          accountId: account?.accountId,
          description: merchant.description,
          reference: movement.documentNumber,
        ),
      );
    }
    final method = _method(options, 'card');
    return BankReconciliationSuggestion(
      kind: BankSuggestionKind.createExpense,
      confidence: account != null && merchant.certain
          ? BankReconciliationConfidence.high
          : BankReconciliationConfidence.medium,
      title:
          '${merchant.description} · ${profile?.displayName ?? merchant.name}',
      reasons: <String>[
        'Cargo con tarjeta en ${merchant.name}',
        if (usual.isNotEmpty)
          'Lo registraste antes en ${account!.label}'
        else if (account != null)
          'Cuenta sugerida: ${account.label}',
        if (!merchant.certain)
          'Confirma que es un gasto del negocio y no personal',
      ],
      resolution: BankReconciliationResolutionDraft(
        action: BankReconciliationActionKind.createExpense,
        accountId: account?.accountId,
        paymentMethodId: method?.paymentMethodId,
        description: merchant.description,
        counterparty: profile?.displayName ?? merchant.name,
        reference: movement.documentNumber,
      ),
    );
  }

  static const List<_Merchant> _merchants = <_Merchant>[
    _Merchant(
      key: 'google-cloud',
      patterns: <String>['google cloud', 'google *cloud'],
      name: 'Google',
      description: 'Google Cloud',
      accountKeywords: <String>['servicios digitales', 'hosting'],
      certain: true,
    ),
    _Merchant(
      key: 'google-one',
      patterns: <String>['google *google on', 'google one'],
      name: 'Google',
      description: 'Google One (almacenamiento)',
      accountKeywords: <String>['servicios digitales'],
      certain: true,
    ),
    _Merchant(
      key: 'google-microsoft',
      patterns: <String>['google *microsoft', 'microsoft'],
      name: 'Microsoft',
      description: 'Suscripción Microsoft',
      accountKeywords: <String>['servicios digitales'],
      certain: true,
    ),
    _Merchant(
      key: 'google-play',
      patterns: <String>['google play', 'youtube', 'youtu', 'dl*google'],
      name: 'Google',
      description: 'Suscripción Google Play / YouTube',
      accountKeywords: <String>['servicios digitales'],
      certain: false,
    ),
    _Merchant(
      key: 'meta',
      patterns: <String>['facebk', 'facebook', 'instagram', 'meta platforms'],
      name: 'Meta',
      description: 'Publicidad en Facebook / Instagram',
      accountKeywords: <String>['publicidad', 'marketing'],
      certain: true,
    ),
    _Merchant(
      key: 'nic-chile',
      patterns: <String>['nic chile', 'univ de chile nic', 'univ.de chile nic'],
      name: 'NIC Chile',
      description: 'Dominio en NIC Chile',
      accountKeywords: <String>['dominios', 'servicios digitales'],
      certain: true,
    ),
    _Merchant(
      key: 'meli-plus',
      patterns: <String>['melimas', 'meli+'],
      name: 'Mercado Libre',
      description: 'Suscripción Meli+',
      accountKeywords: <String>['servicios digitales'],
      certain: false,
    ),
    _Merchant(
      key: 'aliexpress',
      patterns: <String>['alipay', 'aliexpress'],
      name: 'AliExpress',
      description: 'Compra en AliExpress',
      accountKeywords: <String>[],
      certain: false,
      isPurchase: true,
    ),
    _Merchant(
      key: 'mercadolibre',
      patterns: <String>['mercadoli', 'mercadolibre', 'mercado libre'],
      name: 'Mercado Libre',
      description: 'Compra en Mercado Libre',
      accountKeywords: <String>[],
      certain: false,
      isPurchase: true,
    ),
    _Merchant(
      key: 'bank-fee',
      patterns: <String>[
        'comision',
        'mantencion',
        'impuesto',
        'intereses',
        'cargo por',
      ],
      name: 'Banco',
      description: 'Comisión bancaria',
      accountKeywords: <String>['gastos financieros', 'financier'],
      certain: true,
      isBankFee: true,
    ),
  ];

  _Merchant? _merchant(BankStatementMovement movement) {
    final text = movement.description.toLowerCase();
    for (final merchant in _merchants) {
      if (merchant.patterns.any(text.contains)) return merchant;
    }
    return null;
  }

  String? _merchantKey(String description) {
    final text = description.toLowerCase();
    for (final merchant in _merchants) {
      if (merchant.patterns.any(text.contains)) return merchant.key;
    }
    return null;
  }

  bool _isAcquirerDeposit(BankStatementMovement movement) {
    final text = movement.normalizedDescription.toLowerCase();
    return text.contains('transbank') ||
        text.contains('abonos debito y credito') ||
        text.contains('abono debito credito');
  }

  bool _isCardCharge(BankStatementMovement movement) {
    final text = movement.description.trim().toLowerCase();
    return text.startsWith('pago:') || text.startsWith('compra');
  }

  BankReconciliationLedgerAccountOption? _expenseAccount(
    BankReconciliationWorkspaceOptions? options,
    String? accountId,
  ) {
    if (options == null || accountId == null) return null;
    return options.expenseAccounts
        .where((account) => account.accountId == accountId)
        .firstOrNull;
  }

  BankReconciliationLedgerAccountOption? _accountByKeywords(
    BankReconciliationWorkspaceOptions? options,
    List<String> keywords, {
    bool expense = false,
  }) {
    if (options == null) return null;
    final accounts = expense ? options.expenseAccounts : options.accounts;
    for (final keyword in keywords) {
      final wanted = BankCounterpartyIdentity.normalize(keyword);
      // Prefer the most general account (shortest code) that matches.
      final matches = accounts
          .where((account) =>
              BankCounterpartyIdentity.normalize(account.name).contains(wanted))
          .toList()
        ..sort((left, right) => left.code.length.compareTo(right.code.length));
      if (matches.isNotEmpty) return matches.first;
    }
    return null;
  }

  BankReconciliationPaymentMethodOption? _method(
    BankReconciliationWorkspaceOptions? options,
    String code, {
    String? fallback,
  }) {
    final methods = options?.paymentMethods ??
        const <BankReconciliationPaymentMethodOption>[];
    return methods.where((method) => method.code == code).firstOrNull ??
        methods.where((method) => method.code == fallback).firstOrNull ??
        (methods.length == 1 ? methods.single : null);
  }

  String _party(BankStatementMovement movement) {
    final observed = movement.counterpartyObserved?.trim() ?? '';
    return observed.isNotEmpty ? observed : movement.description;
  }

  String _displayParty(BankStatementMovement movement) {
    final words = BankCounterpartyIdentity.tokens(_party(movement))
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .toList(growable: false);
    return words.isEmpty ? 'la contraparte' : words.join(' ');
  }

  String _day(BankCivilDate date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';

  String _money(int value) {
    final digits = value.abs().toString().replaceAllMapped(
          RegExp(r'(?<=\d)(?=(\d{3})+$)'),
          (_) => '.',
        );
    return '\$$digits';
  }
}

class _Merchant {
  const _Merchant({
    required this.key,
    required this.patterns,
    required this.name,
    required this.description,
    required this.accountKeywords,
    required this.certain,
    this.isPurchase = false,
    this.isBankFee = false,
  });

  final String key;
  final List<String> patterns;
  final String name;
  final String description;
  final List<String> accountKeywords;

  /// A business expense beyond doubt; otherwise it may be personal.
  final bool certain;

  /// Goods that belong in Compras rather than in a loose expense.
  final bool isPurchase;
  final bool isBankFee;
}

class _SalaryMatch {
  const _SalaryMatch(this.line, this.advances, {required this.partial});

  final BankPayrollExpectation line;
  final List<BankPayrollAdvanceUse> advances;

  /// The transfer pays less than the week owes after its advances.
  final bool partial;
}
