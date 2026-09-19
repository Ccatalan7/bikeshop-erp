import '../models/bank_reconciliation_models.dart';

/// Reads `get_bank_reconciliation_candidates_v2` (and the v1 shape, which is
/// the same candidate list without identities or context).
class BankReconciliationCatalogCodec {
  const BankReconciliationCatalogCodec();

  BankReconciliationContext context(Object? raw) {
    final payload = raw is Map ? Map<String, dynamic>.from(raw) : null;
    if (payload == null) return BankReconciliationContext();
    return BankReconciliationContext(
      candidates: _list(payload['candidates'])
          .map(candidate)
          .whereType<BankReconciliationCandidate>()
          .toList(growable: false),
      payrollLines: _list(payload['payroll_lines'])
          .map(_payrollLine)
          .whereType<BankPayrollExpectation>()
          .toList(growable: false),
      openInvoices: <BankOpenInvoice>[
        ..._list(payload['open_sales'])
            .map((item) => _openInvoice(item, BankOpenInvoiceKind.sale))
            .whereType<BankOpenInvoice>(),
        ..._list(payload['open_purchases'])
            .map((item) => _openInvoice(item, BankOpenInvoiceKind.purchase))
            .whereType<BankOpenInvoice>(),
      ],
      parties: _list(payload['parties'])
          .map(_party)
          .whereType<BankCounterpartyProfile>()
          .toList(growable: false),
      decisions: _list(payload['decisions'])
          .map(_decision)
          .whereType<BankPriorDecision>()
          .toList(growable: false),
      openAdvances: _list(payload['open_advances'])
          .map(_advance)
          .whereType<BankOpenAdvance>()
          .toList(growable: false),
      reconciledRows: _list(payload['reconciled_rows'])
          .map(_reconciledRow)
          .whereType<BankReconciledRow>()
          .toList(growable: false),
    );
  }

  BankReconciledRow? _reconciledRow(Map<String, dynamic> json) {
    final importId = _text(json['import_id']);
    final sha = _text(json['file_sha256']);
    final sourceRowId = _text(json['source_row_id']);
    final disposition = switch (json['disposition']?.toString()) {
      'reconciled' => BankReconciliationDisposition.reconciled,
      'ignored' => BankReconciliationDisposition.ignored,
      'held' => BankReconciliationDisposition.held,
      _ => null,
    };
    if (importId == null ||
        sha == null ||
        sourceRowId == null ||
        disposition == null) {
      return null;
    }
    return BankReconciledRow(
      importId: importId,
      fileSha256: sha,
      sourceRowId: sourceRowId,
      bookingDate: _date(json['booking_date']),
      direction: switch (json['direction']?.toString()) {
        'debit' => BankMovementDirection.debit,
        'credit' => BankMovementDirection.credit,
        _ => BankMovementDirection.unknown,
      },
      amountClp: _int(json['amount']),
      balanceClp: _int(json['balance']),
      disposition: disposition,
      action: _text(json['action']) ?? '',
      settledElsewhere: json['settled_elsewhere'] == true,
      note: _text(json['note']),
      decidedOn: _localDay(json['decided_at']),
      labels: <String>[
        for (final label in json['labels'] is List
            ? json['labels'] as List
            : const <Object?>[])
          if (_text(label) != null) _text(label)!,
      ],
    );
  }

  BankOpenAdvance? _advance(Map<String, dynamic> json) {
    final id = _text(json['advance_id']);
    final employeeId = _text(json['employee_id']);
    final available = _int(json['available']);
    final paidOn = _date(json['paid_on']);
    if (id == null ||
        employeeId == null ||
        available == null ||
        available <= 0 ||
        paidOn == null) {
      return null;
    }
    return BankOpenAdvance(
      advanceId: id,
      employeeId: employeeId,
      availableClp: available,
      paidOn: paidOn,
      paymentMethodCode: _text(json['payment_method_code']),
    );
  }

  BankReconciliationCandidate? candidate(Map<String, dynamic> json) {
    final id = _text(json['target_id']);
    final amount = _int(json['amount']);
    final date = _date(json['occurred_on']);
    if (id == null || amount == null || amount <= 0 || date == null) {
      return null;
    }
    final kind = switch (json['target_kind']?.toString()) {
      'sales_payment' => BankReconciliationTargetKind.salesPayment,
      'purchase_payment' => BankReconciliationTargetKind.purchasePayment,
      'expense_payment' => BankReconciliationTargetKind.expensePayment,
      'expense' => BankReconciliationTargetKind.expense,
      'journal_entry' => BankReconciliationTargetKind.journalEntry,
      _ => null,
    };
    if (kind == null) return null;
    return BankReconciliationCandidate(
      targetKind: kind,
      targetId: id,
      direction: json['direction']?.toString() == 'credit'
          ? BankMovementDirection.credit
          : BankMovementDirection.debit,
      amountClp: amount,
      occurredOn: date,
      label: _text(json['label']) ?? 'Operación ERP',
      counterparty: json['counterparty']?.toString(),
      reference: json['reference']?.toString(),
      paymentMethodCode: json['payment_method_code']?.toString().toLowerCase(),
      provider: switch (json['provider']?.toString().toLowerCase()) {
        'transbank' => BankSettlementProvider.transbank,
        'mercadopago' => BankSettlementProvider.mercadoPago,
        'other' => BankSettlementProvider.other,
        _ => BankSettlementProvider.none,
      },
      instrument: instrument(json['instrument']),
      occurredAt: DateTime.tryParse(json['occurred_at']?.toString() ?? ''),
      counterpartyKind: _counterpartyKind(json['counterparty_kind']),
      counterpartyId: _text(json['counterparty_id']),
      counterpartyNames: _strings(json['counterparty_names']),
      documentNumber: _text(json['document_number']),
      bankEvidence: <BankObservedRowEvidence>[
        for (final item in _list(json['bank_evidence']))
          if (_date(item['date']) != null && _int(item['amount']) != null)
            BankObservedRowEvidence(
              date: _date(item['date'])!,
              amountClp: _int(item['amount'])!,
              beneficiary: _text(item['beneficiary']),
            ),
      ],
    );
  }

  BankPaymentInstrument instrument(Object? value) =>
      switch (value?.toString()) {
        'debit' => BankPaymentInstrument.debit,
        'credit' => BankPaymentInstrument.credit,
        'prepaid' => BankPaymentInstrument.prepaid,
        _ => BankPaymentInstrument.unknown,
      };

  BankPayrollExpectation? _payrollLine(Map<String, dynamic> json) {
    final amount = _int(json['amount']);
    final periodEnd = _date(json['period_end']);
    final voucherId = _text(json['voucher_id']);
    final lineId = _text(json['line_id']);
    if (amount == null ||
        amount <= 0 ||
        periodEnd == null ||
        voucherId == null ||
        lineId == null) {
      return null;
    }
    final employeeName = _text(json['employee_name']) ?? 'Trabajador';
    return BankPayrollExpectation(
      voucherId: voucherId,
      voucherNumber: _text(json['voucher_number']) ?? 'Nómina',
      periodLabel: _text(json['period_label']) ?? '',
      periodEnd: periodEnd,
      lineId: lineId,
      employeeName: employeeName,
      names: <String>{employeeName, ..._strings(json['counterparty_names'])}
          .toList(growable: false),
      amountClp: amount,
      paymentMethod: _text(json['payment_method']),
      paymentMethodId: _text(json['payment_method_id']),
      status: _text(json['status']) ?? 'draft',
      reconciliationVersion: _int(json['reconciliation_version']),
      payableFrom: _date(json['payable_from']),
      employeeId: _text(json['employee_id']),
    );
  }

  BankOpenInvoice? _openInvoice(
    Map<String, dynamic> json,
    BankOpenInvoiceKind kind,
  ) {
    final id = _text(json['invoice_id']);
    final date = _date(json['date']);
    final total = _int(json['total']);
    if (id == null || date == null || total == null) return null;
    return BankOpenInvoice(
      kind: kind,
      invoiceId: id,
      number: _text(json['supplier_invoice_number']) ??
          _text(json['invoice_number']) ??
          '',
      date: date,
      totalClp: total,
      balanceClp: _int(json['balance']) ?? 0,
      status: _text(json['status']) ?? '',
      counterpartyId: _text(json['counterparty_id']),
      names: _strings(json['counterparty_names']),
    );
  }

  BankCounterpartyProfile? _party(Map<String, dynamic> json) {
    final displayName = _text(json['display_name']);
    if (displayName == null) return null;
    return BankCounterpartyProfile(
      kind: _counterpartyKind(json['kind']),
      id: _text(json['id']),
      displayName: displayName,
      names: <String>{displayName, ..._strings(json['counterparty_names'])}
          .toList(growable: false),
      purchaseCount: _int(json['purchase_count']) ?? 0,
      usual: <BankUsualBooking>[
        for (final item in _list(json['usual']))
          if (_text(item['account_id']) != null)
            BankUsualBooking(
              accountId: _text(item['account_id'])!,
              paymentMethodCode: _text(item['payment_method_code']),
              uses: _int(item['uses']) ?? 0,
              lastDescription: _text(item['last_description']),
            ),
      ],
    );
  }

  BankPriorDecision? _decision(Map<String, dynamic> json) {
    final action = switch (json['action']?.toString()) {
      'create_expense' => BankReconciliationActionKind.createExpense,
      'post_journal' => BankReconciliationActionKind.classifyAccount,
      'dismiss' => BankReconciliationActionKind.dismiss,
      'split' => BankReconciliationActionKind.split,
      _ => null,
    };
    final description = _text(json['description']);
    if (action == null || description == null) return null;
    final parts = <BankPriorSplitPart>[
      for (final raw in _list(json['parts']))
        if (_text(raw['account_id']) != null &&
            (_int(raw['amount']) ?? 0) > 0 &&
            _text(raw['description']) != null)
          BankPriorSplitPart(
            accountId: _text(raw['account_id'])!,
            amountClp: _int(raw['amount'])!,
            description: _text(raw['description'])!,
            supplierId: _text(raw['supplier_id']),
            isExpense: raw['kind']?.toString() == 'expense',
          ),
    ];
    if (action == BankReconciliationActionKind.split && parts.length < 2) {
      return null;
    }
    return BankPriorDecision(
      action: action,
      direction: json['direction']?.toString() == 'credit'
          ? BankMovementDirection.credit
          : BankMovementDirection.debit,
      description: description,
      counterparty: _text(json['counterparty']),
      amountClp: _int(json['amount']),
      accountId: _text(json['account_id']),
      paymentMethodId: _text(json['payment_method_id']),
      supplierName: _text(json['supplier_name']),
      text: _text(json['text']),
      parts: parts,
    );
  }

  BankCounterpartyKind _counterpartyKind(Object? value) =>
      switch (value?.toString()) {
        'customer' => BankCounterpartyKind.customer,
        'supplier' => BankCounterpartyKind.supplier,
        'employee' => BankCounterpartyKind.employee,
        'payee' => BankCounterpartyKind.payee,
        _ => BankCounterpartyKind.unknown,
      };

  List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false)
      : const <Map<String, dynamic>>[];

  List<String> _strings(Object? value) => value is List
      ? value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
      : const <String>[];

  String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  int? _int(Object? value) {
    if (value is num) return value.round();
    final parsed = num.tryParse(value?.toString() ?? '');
    return parsed?.round();
  }

  BankCivilDate? _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? null : BankCivilDate.fromDateTime(parsed);
  }

  /// The operator's day of a timestamp (a decision taken on a Chilean
  /// evening is already the next day in UTC).
  BankCivilDate? _localDay(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? null : BankCivilDate.fromDateTime(parsed.toLocal());
  }
}
