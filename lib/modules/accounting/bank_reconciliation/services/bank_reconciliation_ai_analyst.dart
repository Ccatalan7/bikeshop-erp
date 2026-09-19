import 'dart:async';
import 'dart:convert';

import '../models/bank_reconciliation_models.dart';

/// Asks the model and returns its raw text: the system instruction carries
/// the rules, the prompt carries the movements and what the ERP knows.
typedef BankAiGenerate = Future<String> Function({
  required String system,
  required String prompt,
});

/// Reads the movements nothing explains the way the owner's accountant would:
/// what each one probably is, what may be missing in the ERP, and the one
/// question that would settle it.
///
/// **The model reads, the code judges.** Operations and accounts travel with
/// short ids (O1, A1…); a proposal survives only if every id exists, the
/// direction agrees and the amounts add up to the movement. Whatever fails
/// that is dropped and the explanation and question remain. Nothing is ever
/// applied: the operator uses a proposal or answers the question.
///
/// The model is asked in small batches, a few at a time: the Gemini proxy is
/// an edge function cut at 150 s, and 60 movements with 160 operations in
/// one question never came back (504 three times, 7½ minutes, 2026-09-19).
class BankReconciliationAiAnalyst {
  const BankReconciliationAiAnalyst({
    required this.generate,
    this.maxRows = 8,
    this.maxOperations = 100,
    this.concurrency = 3,
  });

  final BankAiGenerate generate;

  /// Movements per question to the model; more is split in several calls.
  final int maxRows;

  /// ERP operations offered as possible matches per question.
  final int maxOperations;

  /// Questions in flight at once.
  final int concurrency;

  static const _toleranceClp = BankReconciliationProposal.manualToleranceClp;

  /// The movements the analysis has not read yet
  /// ([BankReconciliationPreparedDraft.rowsAwaitingAiAnalysis]), or only
  /// [rowIds] when the operator asks about one. [answers] are the
  /// operator's replies to earlier questions, by movement. Each batch is
  /// handed to [onBatch] as soon as it is judged; a batch that fails leaves
  /// its movements unread and the rest stands. Only when every batch fails
  /// is the error thrown.
  Future<Map<String, BankAiAnalysis>> analyze({
    required BankReconciliationPreparedDraft draft,
    required BankReconciliationWorkspaceOptions? options,
    Map<String, String> answers = const <String, String>{},
    Set<String>? rowIds,
    BankAiBatchCallback? onBatch,
  }) async {
    final open = rowIds == null
        ? draft.rowsAwaitingAiAnalysis
        : draft.rows
            .where((row) =>
                !row.isSettled &&
                !row.isResolved &&
                row.movement.amountClp != null &&
                rowIds.contains(row.movement.sourceRowId))
            .toList(growable: false);
    final ordered = [...open]..sort((left, right) {
        final leftDate = left.movement.bookingDate;
        final rightDate = right.movement.bookingDate;
        if (leftDate == null || rightDate == null) return 0;
        return leftDate.compareTo(rightDate);
      });
    final result = <String, BankAiAnalysis>{};
    final claimed = <String>{
      for (final row in draft.rows)
        if (rowIds == null || !rowIds.contains(row.movement.sourceRowId))
          for (final allocation in row.selectedProposal?.allocations ??
              const <BankReconciliationAllocationDraft>[])
            allocation.candidate.identity,
    };
    final unexplained = {
      for (final candidate in draft.unexplainedErpOperations())
        candidate.identity,
    };
    final questions = <_Question>[
      for (var start = 0; start < ordered.length; start += maxRows)
        _Question.build(
          batch: ordered.sublist(
            start,
            start + maxRows > ordered.length ? ordered.length : start + maxRows,
          ),
          draft: draft,
          options: options,
          answers: answers,
          claimed: claimed,
          unexplained: unexplained,
          maxOperations: maxOperations,
        ),
    ];
    Object? firstError;
    StackTrace? firstStack;
    var answered = 0;
    var next = 0;
    Future<void> worker() async {
      while (next < questions.length) {
        final question = questions[next++];
        final String raw;
        try {
          raw = await generate(system: _system, prompt: question.prompt);
        } catch (error, stack) {
          firstError ??= error;
          firstStack ??= stack;
          continue;
        }
        answered++;
        // Judged one at a time as they arrive: an operation a batch linked
        // is taken for the batches judged after it.
        final judged = _judge(raw, question, options, claimed);
        for (final analysis in judged.values) {
          for (final allocation in analysis.proposal?.allocations ??
              const <BankReconciliationAllocationDraft>[]) {
            claimed.add(allocation.candidate.identity);
          }
        }
        result.addAll(judged);
        if (judged.isNotEmpty) onBatch?.call(judged);
      }
    }

    await Future.wait<void>([
      for (var index = 0;
          index < concurrency && index < questions.length;
          index++)
        worker(),
    ]);
    if (answered == 0 && firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack!);
    }
    return result;
  }

  /// The deterministic gate between the model's answer and the review.
  Map<String, BankAiAnalysis> _judge(
    String raw,
    _Question question,
    BankReconciliationWorkspaceOptions? options,
    Set<String> claimed,
  ) {
    final decoded = _decode(raw);
    final items = decoded is Map && decoded['rows'] is List
        ? decoded['rows'] as List
        : decoded is List
            ? decoded
            : const <Object?>[];
    final result = <String, BankAiAnalysis>{};
    final taken = <String>{};
    for (final item in items.whereType<Map>()) {
      final row = question.rows[item['row']?.toString()];
      if (row == null || result.containsKey(row.movement.sourceRowId)) {
        continue;
      }
      final explanation = question.humanize(_text(item['explanation'], 400));
      if (explanation == null) continue;
      final proposalJson = item['proposal'];
      BankReconciliationProposal? proposal;
      BankReconciliationResolutionDraft? resolution;
      if (proposalJson is Map) {
        switch (proposalJson['type']?.toString()) {
          case 'link':
            proposal = _link(row, proposalJson, question, {
              ...claimed,
              ...taken,
            });
          case 'expense':
            resolution = _expense(row, proposalJson, question, options);
          case 'journal':
            resolution = _journal(row, proposalJson, question);
          case 'split':
            resolution = _split(row, proposalJson, question, options);
        }
      }
      for (final allocation in proposal?.allocations ??
          const <BankReconciliationAllocationDraft>[]) {
        taken.add(allocation.candidate.identity);
      }
      result[row.movement.sourceRowId] = BankAiAnalysis(
        explanation: explanation,
        question: question.humanize(_text(item['question'], 300)),
        missing: question.humanize(_text(item['missing'], 300)),
        proposal: proposal,
        resolution: resolution,
        answer: question.answers[row.movement.sourceRowId],
      );
    }
    return result;
  }

  BankReconciliationProposal? _link(
    BankReconciliationRowDraft row,
    Map proposal,
    _Question question,
    Set<String> taken,
  ) {
    final ids = proposal['ops'];
    if (ids is! List || ids.isEmpty || ids.length > 10) return null;
    final chosen = <BankReconciliationCandidate>[];
    for (final id in ids) {
      final candidate = question.operations[id?.toString()];
      if (candidate == null ||
          candidate.direction != row.movement.direction ||
          taken.contains(candidate.identity) ||
          chosen.any((item) => item.identity == candidate.identity)) {
        return null;
      }
      chosen.add(candidate);
    }
    final total = chosen.fold<int>(0, (sum, item) => sum + item.amountClp);
    if ((total - row.movement.amountClp!).abs() > _toleranceClp) return null;
    final manual = BankReconciliationProposal.manual(
      sourceRowId: row.movement.sourceRowId,
      movementAmountClp: row.movement.amountClp!,
      candidates: chosen,
    );
    if (manual == null) return null;
    return BankReconciliationProposal(
      sourceRowId: manual.sourceRowId,
      matchKind: BankReconciliationMatchKind.manual,
      confidence: BankReconciliationConfidence.low,
      allocations: manual.allocations,
      reasons: const <String>['Propuesta del análisis con IA'],
    );
  }

  BankReconciliationResolutionDraft? _expense(
    BankReconciliationRowDraft row,
    Map proposal,
    _Question question,
    BankReconciliationWorkspaceOptions? options,
  ) {
    if (row.movement.direction != BankMovementDirection.debit) return null;
    final account = question.accounts[proposal['account']?.toString()];
    final description = _text(proposal['description'], 200);
    if (account == null || !account.canReceiveExpense || description == null) {
      return null;
    }
    final supplier = question.suppliers[proposal['supplier']?.toString()];
    return BankReconciliationResolutionDraft(
      action: BankReconciliationActionKind.createExpense,
      accountId: account.accountId,
      paymentMethodId: _bankMethod(options),
      description: description,
      counterparty: supplier?.name ?? row.movement.counterpartyObserved,
      reference: row.movement.documentNumber,
    );
  }

  BankReconciliationResolutionDraft? _journal(
    BankReconciliationRowDraft row,
    Map proposal,
    _Question question,
  ) {
    final account = question.accounts[proposal['account']?.toString()];
    final description = _text(proposal['description'], 200);
    if (account == null || description == null) return null;
    return BankReconciliationResolutionDraft(
      action: BankReconciliationActionKind.classifyAccount,
      accountId: account.accountId,
      description: description,
      reference: row.movement.documentNumber,
    );
  }

  BankReconciliationResolutionDraft? _split(
    BankReconciliationRowDraft row,
    Map proposal,
    _Question question,
    BankReconciliationWorkspaceOptions? options,
  ) {
    final parts = proposal['parts'];
    if (parts is! List || parts.length < 2 || parts.length > 10) return null;
    final debit = row.movement.direction == BankMovementDirection.debit;
    final drafts = <BankSplitPartDraft>[];
    for (final part in parts) {
      if (part is! Map) return null;
      final account = question.accounts[part['account']?.toString()];
      final amount = part['amount'] is num ? (part['amount'] as num) : null;
      final description = _text(part['description'], 200);
      if (account == null ||
          amount == null ||
          amount <= 0 ||
          amount != amount.roundToDouble() ||
          description == null) {
        return null;
      }
      final expense = debit && account.canReceiveExpense;
      final supplier = question.suppliers[part['supplier']?.toString()];
      drafts.add(BankSplitPartDraft(
        accountId: account.accountId,
        amountClp: amount.toInt(),
        description: description,
        supplierId: expense ? supplier?.supplierId : null,
        isExpense: expense,
      ));
    }
    final total = drafts.fold<int>(0, (sum, part) => sum + part.amountClp!);
    if (total != row.movement.amountClp) return null;
    return BankReconciliationResolutionDraft(
      action: BankReconciliationActionKind.split,
      paymentMethodId: _bankMethod(options),
      reference: row.movement.documentNumber,
      splitParts: drafts,
    );
  }

  static String? _bankMethod(BankReconciliationWorkspaceOptions? options) {
    final methods = options?.paymentMethods ??
        const <BankReconciliationPaymentMethodOption>[];
    return (methods.where((method) => method.code == 'transfer').firstOrNull ??
            (methods.length == 1 ? methods.single : null))
        ?.paymentMethodId;
  }

  static Object? _decode(String raw) {
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(raw);
    final text = (fence?.group(1) ?? raw).trim();
    try {
      return jsonDecode(text);
    } on FormatException {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      try {
        return jsonDecode(text.substring(start, end + 1));
      } on FormatException {
        return null;
      }
    }
  }

  static String? _text(Object? value, int max) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return null;
    return text.length > max ? '${text.substring(0, max - 1)}…' : text;
  }

  static const _system = r'''
Eres el contador de una tienda y taller de bicicletas en Viña del Mar, Chile.
Revisas los movimientos de la cartola del Banco de Chile que la conciliación
automática no pudo explicar, con lo que el ERP sabe de la tienda.

Para cada movimiento:
- "explanation": qué es probablemente, en una o dos frases, citando nombres,
  fechas y montos concretos. Si no hay base, dilo.
- "missing": qué parece faltar o estar mal registrado en el ERP (una venta sin
  registrar, un medio de pago equivocado, un pago hecho por otra persona), o
  null.
- "question": la única pregunta al dueño que lo resolvería, concreta y
  cerrada si es posible («¿Los $22.000 del 13-07 a Vicente fueron un anticipo,
  un reembolso o un pago extra?»), o null si la propuesta ya es clara.
- "proposal": una sola, o null si no hay base suficiente:
  {"type":"link","ops":["O4","O7"]} cuando operaciones del ERP de la lista
    explican el movimiento; sus montos deben sumar el movimiento (diferencia
    máxima $1.000) y deben ir en la misma dirección (cargo con pagos, abono
    con cobros).
  {"type":"expense","account":"A3","supplier":"S2"|null,"description":"..."}
    para un cargo que es un gasto sin registrar; sólo cuentas de tipo gasto.
  {"type":"journal","account":"A5","description":"..."} para clasificarlo a
    una cuenta (aporte de socio, préstamo, comisión bancaria, impuesto).
  {"type":"split","parts":[{"account":"A2","amount":50000,
    "description":"...","supplier":"S1"|null}, ...]} cuando un movimiento paga
    varias cosas; las partes suman exactamente el movimiento.

Reglas:
- Usa sólo ids que aparecen en las listas. Nunca inventes operaciones,
  cuentas, proveedores ni montos.
- Los ids (M1, O4, A3, S2) van sólo en "row", "ops", "account" y "supplier".
  El dueño no los ve: en los textos nombra la fecha, el monto y la persona
  («el abono de $28.000 del 05-06 de Vicente»).
- Un pago del ERP registrado a otra persona puede haberlo pagado un tercero
  (un familiar que paga y luego se le devuelve).
- Los abonos «Abonos Debito Y Credito» son depósitos de Transbank: agrupan
  ventas con tarjeta de días anteriores menos una comisión (débito 1,21% + IVA
  a 2 días hábiles; crédito ~1,60% + IVA a 3).
- Si el dueño ya respondió una pregunta sobre un movimiento, su respuesta es
  la verdad: úsala para proponer.
- Escribe en español de Chile, simple y directo.

Responde sólo JSON: {"rows":[{"row":"M1","explanation":"...","missing":null,
"question":null,"proposal":null}, ...]} con un elemento por movimiento.
''';
}

/// One question to the model: short ids for what it may cite, and the text.
class _Question {
  _Question({
    required this.rows,
    required this.operations,
    required this.accounts,
    required this.suppliers,
    required this.answers,
    required this.prompt,
  });

  final Map<String, BankReconciliationRowDraft> rows;
  final Map<String, BankReconciliationCandidate> operations;
  final Map<String, BankReconciliationLedgerAccountOption> accounts;
  final Map<String, BankReconciliationSupplierOption> suppliers;
  final Map<String, String> answers;
  final String prompt;

  static final _idPattern = RegExp(r'\b([MOAS])(\d+)\b');

  /// The model is told the ids are not for the owner; any that slips into a
  /// text is replaced by what it names.
  String? humanize(String? text) {
    if (text == null) return null;
    return text.replaceAllMapped(_idPattern, (match) {
      final id = match.group(0)!;
      switch (match.group(1)) {
        case 'M':
          final movement = rows[id]?.movement;
          if (movement == null) return id;
          final kind = movement.direction == BankMovementDirection.credit
              ? 'abono'
              : 'cargo';
          final date = movement.bookingDate;
          return 'el $kind de ${_money(movement.amountClp ?? 0)}'
              '${date == null ? '' : ' del ${_day(date)}'}';
        case 'O':
          final operation = operations[id];
          if (operation == null) return id;
          return '${operation.label} (${_money(operation.amountClp)})';
        case 'A':
          return accounts[id]?.label ?? id;
        case 'S':
          return suppliers[id]?.name ?? id;
      }
      return id;
    });
  }

  static String _money(int amount) {
    final digits = amount.abs().toString();
    final grouped = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) grouped.write('.');
      grouped.write(digits[index]);
    }
    return '${amount < 0 ? '-' : ''}\$$grouped';
  }

  static String _day(BankCivilDate date) =>
      '${date.day.toString().padLeft(2, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';

  static _Question build({
    required List<BankReconciliationRowDraft> batch,
    required BankReconciliationPreparedDraft draft,
    required BankReconciliationWorkspaceOptions? options,
    required Map<String, String> answers,
    required Set<String> claimed,
    required Set<String> unexplained,
    required int maxOperations,
  }) {
    final rows = <String, BankReconciliationRowDraft>{
      for (var index = 0; index < batch.length; index++)
        'M${index + 1}': batch[index],
    };
    final dates = batch
        .map((row) => row.movement.bookingDate)
        .whereType<BankCivilDate>()
        .toList()
      ..sort();
    final from = dates.isEmpty ? null : dates.first.addDays(-45);
    final until = dates.isEmpty ? null : dates.last.addDays(10);
    // An operation larger than every movement of its direction can be no
    // part of what explains them.
    final largest = <BankMovementDirection, int>{};
    for (final row in batch) {
      final amount = row.movement.amountClp!;
      final direction = row.movement.direction;
      if (amount > (largest[direction] ?? 0)) largest[direction] = amount;
    }
    final middle = dates.isEmpty ? null : dates[dates.length ~/ 2];
    final nearby = draft.candidateCatalog
        .where((candidate) =>
            !claimed.contains(candidate.identity) &&
            largest[candidate.direction] != null &&
            candidate.amountClp <=
                largest[candidate.direction]! +
                    BankReconciliationAiAnalyst._toleranceClp &&
            (from == null || candidate.occurredOn.compareTo(from) >= 0) &&
            (until == null || candidate.occurredOn.compareTo(until) <= 0))
        .toList()
      ..sort((left, right) {
        // What the ERP says went through the bank and did not come first,
        // then what is nearest in date.
        final byUnexplained = (unexplained.contains(right.identity) ? 1 : 0)
            .compareTo(unexplained.contains(left.identity) ? 1 : 0);
        if (byUnexplained != 0) return byUnexplained;
        if (middle == null) return 0;
        return left.occurredOn
            .daysUntil(middle)
            .abs()
            .compareTo(right.occurredOn.daysUntil(middle).abs());
      });
    final operations = <String, BankReconciliationCandidate>{
      for (var index = 0;
          index < nearby.length && index < maxOperations;
          index++)
        'O${index + 1}': nearby[index],
    };
    final accountList =
        options?.accounts ?? const <BankReconciliationLedgerAccountOption>[];
    final accounts = <String, BankReconciliationLedgerAccountOption>{
      for (var index = 0; index < accountList.length; index++)
        'A${index + 1}': accountList[index],
    };
    final supplierList =
        options?.suppliers ?? const <BankReconciliationSupplierOption>[];
    final suppliers = <String, BankReconciliationSupplierOption>{
      for (var index = 0; index < supplierList.length; index++)
        'S${index + 1}': supplierList[index],
    };
    final context = draft.context;
    final buffer = StringBuffer()
      ..writeln('MOVIMIENTOS SIN EXPLICAR (cartola):');
    for (final entry in rows.entries) {
      final movement = entry.value.movement;
      final suggestion = entry.value.suggestion;
      buffer.writeln(
        '${entry.key} | ${movement.bookingDate} | '
        '${movement.direction == BankMovementDirection.credit ? 'abono' : 'cargo'}'
        ' | \$${movement.amountClp} | ${movement.description}'
        '${suggestion == null ? '' : ' | la conciliación dijo: ${suggestion.title}'}',
      );
      final answer = answers[movement.sourceRowId];
      if (answer != null && answer.trim().isNotEmpty) {
        buffer.writeln('   RESPUESTA DEL DUEÑO: ${answer.trim()}');
      }
    }
    buffer
      ..writeln()
      ..writeln('OPERACIONES DEL ERP que pasan por esta cuenta y ningún '
          'movimiento explica todavía (las marcadas * no aparecen en la '
          'cartola):');
    for (final entry in operations.entries) {
      final candidate = entry.value;
      final who = candidate.counterpartyNames.isNotEmpty
          ? candidate.counterpartyNames.first
          : candidate.counterparty ?? '';
      buffer.writeln(
        '${entry.key}${unexplained.contains(candidate.identity) ? '*' : ''} | '
        '${candidate.occurredOn} | '
        '${candidate.direction == BankMovementDirection.credit ? 'cobro' : 'pago'}'
        ' | \$${candidate.amountClp} | ${candidate.label} | $who'
        '${candidate.paymentMethodCode == null ? '' : ' | ${candidate.paymentMethodCode}'}',
      );
    }
    if (context != null && context.payrollLines.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('SUELDOS QUE NÓMINA AÚN DEBE:');
      for (final line in context.payrollLines) {
        buffer.writeln(
          '${line.voucherNumber} | ${line.periodLabel} | ${line.employeeName}'
          ' | \$${line.amountClp}',
        );
      }
    }
    if (context != null && context.openInvoices.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('FACTURAS CON SALDO (se registran en Ventas o Compras):');
      for (final invoice in context.openInvoices.take(40)) {
        buffer.writeln(
          '${invoice.kind == BankOpenInvoiceKind.sale ? 'venta' : 'compra'} '
          '${invoice.number} | ${invoice.date} | ${invoice.names.join(' / ')}'
          ' | saldo \$${invoice.balanceClp}',
        );
      }
    }
    if (context != null && context.decisions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('CÓMO SE RESOLVIERON ANTES MOVIMIENTOS PARECIDOS:');
      for (final decision in context.decisions.take(30)) {
        final account = options?.account(decision.accountId);
        buffer.writeln(
          '${decision.description} | ${decision.action.name}'
          '${account == null ? '' : ' | ${account.label}'}'
          '${decision.text == null ? '' : ' | ${decision.text}'}',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('CUENTAS CONTABLES:');
    for (final entry in accounts.entries) {
      buffer
          .writeln('${entry.key} | ${entry.value.label} | ${entry.value.type}');
    }
    if (suppliers.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('PROVEEDORES:');
      for (final entry in suppliers.entries) {
        buffer.writeln('${entry.key} | ${entry.value.name}');
      }
    }
    return _Question(
      rows: rows,
      operations: operations,
      accounts: accounts,
      suppliers: suppliers,
      answers: {
        for (final row in batch)
          if (answers[row.movement.sourceRowId] != null)
            row.movement.sourceRowId: answers[row.movement.sourceRowId]!,
      },
      prompt: buffer.toString(),
    );
  }
}
