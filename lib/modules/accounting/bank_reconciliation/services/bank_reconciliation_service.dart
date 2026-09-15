import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/services/database_service.dart';
import '../../models/account.dart';
import '../../utils/bank_ledger_account_policy.dart';
import '../../../hr/models/payroll_statement_reconciliation.dart';
import '../../../hr/services/payroll_bank_statement_parser.dart';
import '../../../hr/services/payroll_statement_extraction_service.dart';
import '../../../hr/services/payroll_statement_veryfi_ocr.dart';
import '../models/bank_reconciliation_models.dart';
import 'bank_reconciliation_matcher.dart';

typedef BankReconciliationRpc = Future<dynamic> Function(
  String functionName,
  Map<String, dynamic> params,
);

class BankReconciliationServiceException implements Exception {
  const BankReconciliationServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BankReconciliationService {
  BankReconciliationService({
    required DatabaseService database,
    PayrollBankStatementParser parser = const PayrollBankStatementParser(),
    PayrollStatementVeryfiOcr veryfiOcr = const PayrollStatementVeryfiOcr(),
    BankReconciliationMatcher matcher = const BankReconciliationMatcher(),
    BankReconciliationRpc? rpc,
  })  : _database = database,
        _parser = parser,
        _veryfiOcr = veryfiOcr,
        _matcher = matcher,
        _rpc = rpc ??
            ((functionName, params) =>
                database.supabase.rpc(functionName, params: params));

  static const parserName = 'banco_chile_statement';
  static const parserVersion = 'banco_chile_v2_accounting';

  final DatabaseService _database;
  final PayrollBankStatementParser _parser;
  final PayrollStatementVeryfiOcr _veryfiOcr;
  final BankReconciliationMatcher _matcher;
  final BankReconciliationRpc _rpc;

  Future<List<BankReconciliationAccountOption>> loadBankAccounts() async {
    final rows = await _database.supabase
        .from('accounts')
        .select(
          'id, tenant_id, code, name, type, category, parent_id, is_active',
        )
        .eq('type', 'asset')
        .eq('is_active', true)
        .order('code');
    final accounts = rows
        .map((raw) => Account.fromJson(Map<String, dynamic>.from(raw)))
        .toList(growable: false);
    final result = <BankReconciliationAccountOption>[];
    for (final account
        in BankLedgerAccountPolicy.activeBankAccounts(accounts)) {
      final id = account.id?.trim() ?? '';
      final code = account.code.trim();
      final name = account.name.trim();
      if (id.isEmpty || code.isEmpty || name.isEmpty) continue;
      result.add(
        BankReconciliationAccountOption(
          accountId: id,
          code: code,
          name: name,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  Future<BankReconciliationWorkspaceOptions> loadWorkspaceOptions({
    required String erpAccountId,
  }) async {
    final accountRows = await _database.supabase
        .from('accounts')
        .select('id, code, name, type, category, is_active')
        .eq('is_active', true)
        .order('code');
    final methodRows = await _database.supabase
        .from('payment_methods')
        .select('id, code, name, account_id, is_active, usage_scope')
        .eq('account_id', erpAccountId)
        .eq('is_active', true)
        .inFilter('usage_scope', const ['outbound', 'both']).order('name');

    final accounts = <BankReconciliationLedgerAccountOption>[];
    for (final raw in accountRows) {
      final row = Map<String, dynamic>.from(raw);
      final id = row['id']?.toString().trim() ?? '';
      final code = row['code']?.toString().trim() ?? '';
      final name = row['name']?.toString().trim() ?? '';
      final type = row['type']?.toString().trim() ?? '';
      if (id.isEmpty || id == erpAccountId || code.isEmpty || name.isEmpty) {
        continue;
      }
      accounts.add(
        BankReconciliationLedgerAccountOption(
          accountId: id,
          code: code,
          name: name,
          type: type,
          category: row['category']?.toString(),
        ),
      );
    }

    final methods = <BankReconciliationPaymentMethodOption>[];
    for (final raw in methodRows) {
      final row = Map<String, dynamic>.from(raw);
      final id = row['id']?.toString().trim() ?? '';
      final code = row['code']?.toString().trim() ?? '';
      final name = row['name']?.toString().trim() ?? '';
      final accountId = row['account_id']?.toString().trim() ?? '';
      if (id.isEmpty || code.isEmpty || name.isEmpty || accountId.isEmpty) {
        continue;
      }
      methods.add(
        BankReconciliationPaymentMethodOption(
          paymentMethodId: id,
          code: code,
          name: name,
          accountId: accountId,
        ),
      );
    }
    return BankReconciliationWorkspaceOptions(
      accounts: accounts,
      paymentMethods: methods,
    );
  }

  Future<BankReconciliationPreparedDraft> prepare({
    required Uint8List bytes,
    required String filename,
    required String erpAccountId,
    String? sourcePath,
    int? statementYear,
    PayrollStatementPreparationProgressCallback? onProgress,
  }) async {
    final extractionService = PayrollStatementExtractionService(
      cloudDocumentTextExtractor: _veryfiOcr.extractText,
    );
    PayrollStatementExtractionResult extraction;
    try {
      extraction = await extractionService.extract(
        bytes: bytes,
        filename: filename,
        sourcePath: sourcePath,
        onProgress: onProgress,
      );
    } on PayrollStatementExtractionException catch (error) {
      throw BankReconciliationServiceException(error.message);
    }

    var year = statementYear ?? _inferStatementYear(extraction);
    year ??= DateTime.now().year;
    var parsed = _parser.parsePages(
      extraction.pages.map((page) => page.text).toList(growable: false),
      statementYear: year,
    );
    if (extraction.inputKind == PayrollStatementInputKind.pdf &&
        extraction.method == PayrollStatementExtractionMethod.embeddedPdfText &&
        parsed.rows.isEmpty) {
      extraction = await extractionService.extract(
        bytes: bytes,
        filename: filename,
        sourcePath: sourcePath,
        forceImageOcrForPdf: true,
        onProgress: onProgress,
      );
      parsed = _parser.parsePages(
        extraction.pages.map((page) => page.text).toList(growable: false),
        statementYear: year,
      );
    }
    if (extraction.needsImageOcr || parsed.rows.isEmpty) {
      throw const BankReconciliationServiceException(
        'No se reconocieron movimientos bancarios revisables.',
      );
    }

    final movements = _mapMovements(parsed.rows);
    final dated = movements
        .map((movement) => movement.bookingDate)
        .whereType<BankCivilDate>()
        .toList(growable: false)
      ..sort();
    if (dated.isEmpty) {
      throw const BankReconciliationServiceException(
        'La cartola no contiene fechas contables legibles.',
      );
    }
    final candidates = await loadCandidates(
      erpAccountId: erpAccountId,
      from: dated.first.addDays(-14),
      to: dated.last.addDays(7),
    );
    final terminalPolicies = await loadTerminalMatchPolicies(
      from: dated.first.addDays(-30),
      to: dated.last,
    );
    final proposals = _matcher.match(
      movements: movements,
      candidates: candidates,
      terminalPolicies: terminalPolicies,
    );

    return BankReconciliationPreparedDraft(
      fileSha256: extraction.fileSha256,
      filename: filename,
      sourceType: _sourceType(extraction),
      accountFingerprint: _extractAccountFingerprint(extraction),
      parserName: parserName,
      parserVersion: parserVersion,
      rows: <BankReconciliationRowDraft>[
        for (final movement in movements)
          BankReconciliationRowDraft(
            movement: movement,
            proposals: proposals[movement.sourceRowId] ?? const [],
          ),
      ],
      candidateCatalog: candidates,
      extractionWarnings: <String>[
        ...extraction.warnings,
        ...parsed.warnings.map((warning) => warning.message),
      ],
    );
  }

  Future<List<BankTerminalMatchPolicy>> loadTerminalMatchPolicies({
    required BankCivilDate from,
    required BankCivilDate to,
  }) async {
    try {
      final profileRows = await _database.supabase
          .from('payment_terminal_profiles')
          .select(
            'id,provider_code,provider_name,terminal_name,descriptor_patterns',
          )
          .eq('is_active', true);
      final termRows = await _database.supabase
          .from('payment_terminal_terms')
          .select(
            'terminal_profile_id,instrument,commission_rate_bps,'
            'commission_vat_bps,settlement_business_days,'
            'booking_grace_business_days,amount_tolerance_clp,'
            'effective_from,effective_to,'
            'payment_methods!payment_terminal_terms_method_fk(code,is_active)',
          )
          .lte('effective_from', to.toString())
          .or('effective_to.is.null,effective_to.gte.${from.toString()}');
      final profileById = <String, Map<String, dynamic>>{
        for (final raw in profileRows)
          raw['id'].toString(): Map<String, dynamic>.from(raw),
      };
      final policies = <BankTerminalMatchPolicy>[];
      for (final raw in termRows) {
        final term = Map<String, dynamic>.from(raw);
        final profile = profileById[term['terminal_profile_id']?.toString()];
        final method = term['payment_methods'];
        if (profile == null || method is! Map || method['is_active'] == false) {
          continue;
        }
        final code = method['code']?.toString().trim() ?? '';
        final effectiveFrom = _civilDate(term['effective_from']);
        if (code.isEmpty || effectiveFrom == null) continue;
        policies.add(
          BankTerminalMatchPolicy(
            profileId: profile['id'].toString(),
            providerCode: profile['provider_code']?.toString() ?? 'other',
            providerName: profile['provider_name']?.toString() ?? 'Proveedor',
            terminalName: profile['terminal_name']?.toString() ?? 'Terminal',
            descriptorPatterns:
                (profile['descriptor_patterns'] as List? ?? const [])
                    .map((item) => item.toString())
                    .toList(growable: false),
            paymentMethodCode: code,
            instrument: _instrument(term['instrument']),
            commissionRateBps:
                (term['commission_rate_bps'] as num?)?.toInt() ?? 0,
            commissionVatBps:
                (term['commission_vat_bps'] as num?)?.toInt() ?? 0,
            settlementBusinessDays:
                (term['settlement_business_days'] as num?)?.toInt() ?? 0,
            bookingGraceBusinessDays:
                (term['booking_grace_business_days'] as num?)?.toInt() ?? 0,
            amountToleranceClp:
                (term['amount_tolerance_clp'] as num?)?.toInt() ?? 0,
            effectiveFrom: effectiveFrom,
            effectiveTo: _civilDate(term['effective_to']),
          ),
        );
      }
      return List.unmodifiable(policies);
    } catch (error) {
      // A legacy tenant can still use the conservative combined-card matcher
      // while this independently deployable settings schema is unavailable.
      debugPrint('BankReconciliationService terminal policies: $error');
      return const [];
    }
  }

  Future<List<BankReconciliationCandidate>> loadCandidates({
    required String erpAccountId,
    required BankCivilDate from,
    required BankCivilDate to,
  }) async {
    final raw = await _rpc(
      'get_bank_reconciliation_candidates_v1',
      <String, dynamic>{
        'p_erp_account_id': erpAccountId,
        'p_from_date': from.toString(),
        'p_to_date': to.toString(),
      },
    );
    final payload = raw is Map ? Map<String, dynamic>.from(raw) : null;
    final items = payload?['candidates'];
    if (items is! List) return const [];
    final result = <BankReconciliationCandidate>[];
    for (final item in items.whereType<Map>()) {
      final candidate = _candidateFromJson(Map<String, dynamic>.from(item));
      if (candidate != null) result.add(candidate);
    }
    return List.unmodifiable(result);
  }

  Future<BankStatementImportReceipt> createImport({
    required BankReconciliationPreparedDraft draft,
    required String erpAccountId,
    String? operationKey,
  }) async {
    final key = operationKey ?? const Uuid().v4();
    final raw = await _rpc(
      'save_bank_statement_import_v1',
      <String, dynamic>{
        'p_operation_key': key,
        'p_file_sha256': draft.fileSha256,
        'p_account_fingerprint': draft.accountFingerprint,
        'p_erp_account_id': erpAccountId,
        'p_source_metadata': <String, dynamic>{
          'source_type': draft.sourceType,
          'parser_name': draft.parserName,
          'parser_version': draft.parserVersion,
          'filename_extension': _safeExtension(draft.filename),
        },
        'p_rows': <Map<String, dynamic>>[
          for (final row in draft.rows) _rowPayload(row.movement),
        ],
      },
    );
    final receipt = _receiptMap(raw);
    final rowMap = <String, String>{};
    final rows = receipt['rows'];
    if (rows is List) {
      for (final item in rows.whereType<Map>()) {
        final source = item['source_row_id']?.toString() ?? '';
        final id = item['row_id']?.toString() ?? '';
        if (source.isNotEmpty && id.isNotEmpty) rowMap[source] = id;
      }
    }
    if (rowMap.length != draft.rows.length) {
      throw const BankReconciliationServiceException(
        'El servidor no confirmó todas las filas importadas.',
      );
    }
    return BankStatementImportReceipt(
      importId: _requiredText(receipt, 'import_id'),
      revision: _requiredInt(receipt, 'revision'),
      rowIdsBySourceRowId: rowMap,
      replayed: receipt['replayed'] == true,
    );
  }

  Future<BankReconciliationApplyReceipt> apply({
    required BankReconciliationPreparedDraft draft,
    required BankStatementImportReceipt importReceipt,
    String? operationKey,
  }) async {
    final actions = <Map<String, dynamic>>[];
    for (final row in draft.rows) {
      final rowId = importReceipt.rowIdsBySourceRowId[row.movement.sourceRowId];
      if (rowId == null) {
        throw const BankReconciliationServiceException(
          'La evidencia guardada no coincide con la revisión.',
        );
      }
      final resolution = row.effectiveResolution;
      final proposal = row.selectedProposal;
      final action = <String, dynamic>{
        'row_id': rowId,
        'action': switch (resolution.action) {
          BankReconciliationActionKind.pending => 'pending',
          BankReconciliationActionKind.associateExisting =>
            'associate_existing',
          BankReconciliationActionKind.createExpense => 'create_expense',
          BankReconciliationActionKind.classifyAccount => 'post_journal',
          BankReconciliationActionKind.dismiss => 'dismiss',
        },
      };
      switch (resolution.action) {
        case BankReconciliationActionKind.pending:
          break;
        case BankReconciliationActionKind.associateExisting:
          if (proposal == null) {
            throw const BankReconciliationServiceException(
              'Elige la operación ERP que corresponde antes de guardar.',
            );
          }
          action['allocations'] = <Map<String, dynamic>>[
            for (final allocation in proposal.allocations)
              <String, dynamic>{
                'row_id': rowId,
                'target_kind': _targetKindCode(allocation.candidate.targetKind),
                'target_id': allocation.candidate.targetId,
                'bank_amount': allocation.bankAmountClp,
                'target_amount': allocation.candidate.amountClp,
                'match_kind': _matchKindCode(proposal.matchKind),
                'confidence': proposal.confidence.name,
                'provider': _providerCode(allocation.candidate.provider),
                'instrument': allocation.candidate.instrument.name,
                'rationale': <String, dynamic>{
                  'reasons': proposal.reasons,
                  'estimated_gross': proposal.estimatedGrossClp,
                  'estimated_difference': proposal.estimatedDifferenceClp,
                },
              },
          ];
          break;
        case BankReconciliationActionKind.createExpense:
          if (row.movement.direction != BankMovementDirection.debit ||
              (resolution.accountId?.trim().isEmpty ?? true) ||
              (resolution.paymentMethodId?.trim().isEmpty ?? true) ||
              (resolution.description?.trim().isEmpty ?? true)) {
            throw const BankReconciliationServiceException(
              'Completa la cuenta, el medio de pago y la descripción del gasto.',
            );
          }
          action['expense'] = <String, dynamic>{
            'account_id': resolution.accountId,
            'payment_method_id': resolution.paymentMethodId,
            'description': resolution.description!.trim(),
            'supplier_name': resolution.counterparty?.trim(),
            'reference': resolution.reference?.trim(),
          };
          break;
        case BankReconciliationActionKind.classifyAccount:
          if ((resolution.accountId?.trim().isEmpty ?? true) ||
              (resolution.description?.trim().isEmpty ?? true)) {
            throw const BankReconciliationServiceException(
              'Completa la cuenta de contrapartida y la descripción contable.',
            );
          }
          action['journal'] = <String, dynamic>{
            'counterpart_account_id': resolution.accountId,
            'description': resolution.description!.trim(),
            'reference': resolution.reference?.trim(),
          };
          break;
        case BankReconciliationActionKind.dismiss:
          if (resolution.reason?.trim().isEmpty ?? true) {
            throw const BankReconciliationServiceException(
              'Explica por qué este movimiento se excluye de la conciliación.',
            );
          }
          action['reason'] = resolution.reason!.trim();
          break;
      }
      actions.add(action);
    }
    final raw = await _rpc(
      'apply_bank_reconciliation_actions_v2',
      <String, dynamic>{
        'p_import_id': importReceipt.importId,
        'p_expected_revision': importReceipt.revision,
        'p_operation_key': operationKey ?? const Uuid().v4(),
        'p_actions': actions,
      },
    );
    final receipt = _receiptMap(raw);
    return BankReconciliationApplyReceipt(
      importId: _requiredText(receipt, 'import_id'),
      revision: _requiredInt(receipt, 'revision'),
      status: _requiredText(receipt, 'status'),
      allocationCount: _requiredInt(receipt, 'allocation_count'),
      replayed: receipt['replayed'] == true,
      createdExpenseCount: _intOf(receipt['created_expense_count']) ?? 0,
      createdJournalCount: _intOf(receipt['created_journal_count']) ?? 0,
    );
  }

  List<BankStatementMovement> _mapMovements(
    List<PayrollStatementRow> rows,
  ) {
    return <BankStatementMovement>[
      for (final row in rows)
        BankStatementMovement(
          sourceRowId: row.sourceRowId,
          ordinal: row.evidence.sourceRowNumber,
          bookingDate: row.bookingDate == null
              ? null
              : BankCivilDate(
                  row.bookingDate!.year,
                  row.bookingDate!.month,
                  row.bookingDate!.day,
                ),
          description: row.description,
          normalizedDescription: row.normalizedDescription,
          counterpartyObserved: row.beneficiaryObserved,
          documentNumber: row.documentNumber,
          direction: switch (row.direction) {
            PayrollStatementMovementDirection.outgoing =>
              BankMovementDirection.debit,
            PayrollStatementMovementDirection.incoming =>
              BankMovementDirection.credit,
            PayrollStatementMovementDirection.unknown =>
              BankMovementDirection.unknown,
          },
          amountClp: switch (row.direction) {
            PayrollStatementMovementDirection.outgoing => row.debitAmountClp,
            PayrollStatementMovementDirection.incoming => row.creditAmountClp,
            PayrollStatementMovementDirection.unknown => null,
          },
          balanceClp: row.balanceAmountClp,
          warningCodes: row.parseWarningCodes,
          sourcePage: row.evidence.startPageNumber,
          sourceLineStart: row.evidence.startLineNumber,
          sourceLineEnd: row.evidence.endLineNumber,
        ),
    ];
  }

  BankReconciliationCandidate? _candidateFromJson(Map<String, dynamic> json) {
    final id = json['target_id']?.toString().trim() ?? '';
    final amount = _intOf(json['amount']);
    final date = DateTime.tryParse(json['occurred_on']?.toString() ?? '');
    if (id.isEmpty || amount == null || amount <= 0 || date == null) {
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
    final direction = json['direction']?.toString() == 'credit'
        ? BankMovementDirection.credit
        : BankMovementDirection.debit;
    final methodCode = json['payment_method_code']?.toString().toLowerCase();
    final providerCode = json['provider']?.toString().toLowerCase();
    final provider = switch (providerCode) {
      'transbank' => BankSettlementProvider.transbank,
      'mercadopago' => BankSettlementProvider.mercadoPago,
      'other' => BankSettlementProvider.other,
      _ => BankSettlementProvider.none,
    };
    final instrument = switch (json['instrument']?.toString()) {
      'debit' => BankPaymentInstrument.debit,
      'credit' => BankPaymentInstrument.credit,
      'prepaid' => BankPaymentInstrument.prepaid,
      _ => BankPaymentInstrument.unknown,
    };
    return BankReconciliationCandidate(
      targetKind: kind,
      targetId: id,
      direction: direction,
      amountClp: amount,
      occurredOn: BankCivilDate.fromDateTime(date),
      label: json['label']?.toString().trim().isNotEmpty == true
          ? json['label'].toString().trim()
          : 'Operación ERP',
      counterparty: json['counterparty']?.toString(),
      reference: json['reference']?.toString(),
      paymentMethodCode: methodCode,
      provider: provider,
      instrument: instrument,
    );
  }

  BankPaymentInstrument _instrument(Object? value) =>
      switch (value?.toString()) {
        'debit' => BankPaymentInstrument.debit,
        'credit' => BankPaymentInstrument.credit,
        'prepaid' => BankPaymentInstrument.prepaid,
        _ => BankPaymentInstrument.unknown,
      };

  BankCivilDate? _civilDate(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? null : BankCivilDate.fromDateTime(parsed);
  }

  Map<String, dynamic> _rowPayload(BankStatementMovement movement) {
    final base = <String>[
      movement.bookingDate?.toString() ?? '',
      movement.direction.name,
      movement.amountClp?.toString() ?? '',
      movement.normalizedDescription,
      _normalize(movement.counterpartyObserved ?? ''),
      _normalize(movement.documentNumber ?? ''),
      movement.ordinal.toString(),
    ].join('|');
    return <String, dynamic>{
      'source_row_id': movement.sourceRowId,
      'ordinal': movement.ordinal,
      'booking_date': movement.bookingDate?.toString(),
      'operation_date': movement.operationDate?.toString(),
      'direction': movement.direction.name,
      'amount': movement.amountClp,
      'description': movement.description,
      'normalized_description': movement.normalizedDescription,
      'counterparty_observed': movement.counterpartyObserved,
      'document_number': movement.documentNumber,
      'balance': movement.balanceClp,
      'warning_codes': movement.warningCodes,
      'source_page': movement.sourcePage,
      'source_line_start': movement.sourceLineStart,
      'source_line_end': movement.sourceLineEnd,
      'fingerprint': sha256.convert(utf8.encode(base)).toString(),
    };
  }

  int? _inferStatementYear(PayrollStatementExtractionResult extraction) {
    final counts = <int, int>{};
    final pattern = RegExp(r'\b(20\d{2})\b');
    for (final page in extraction.pages) {
      for (final match in pattern.allMatches(page.text)) {
        final year = int.tryParse(match.group(1)!);
        if (year != null) {
          counts.update(year, (count) => count + 1, ifAbsent: () => 1);
        }
      }
    }
    if (counts.isEmpty) return null;
    final ranked = counts.entries.toList()
      ..sort((left, right) => right.value.compareTo(left.value));
    return ranked.first.key;
  }

  String? _extractAccountFingerprint(
    PayrollStatementExtractionResult extraction,
  ) {
    final header = extraction.pages.take(2).map((page) => page.text).join('\n');
    final patterns = <RegExp>[
      RegExp(
        r'cuenta\s*(?:corriente\s*)?(?:n(?:ro\.?|[°ºo])\s*)?:?\s*'
        r'([0-9][0-9.\-\s]{5,30})',
        caseSensitive: false,
      ),
      RegExp(
        r'n[uú]mero\s+de\s+cuenta\s*:?\s*([0-9][0-9.\-\s]{5,30})',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final observed = pattern.firstMatch(header)?.group(1);
      final canonical = observed?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
      if (canonical.length >= 6 && canonical.length <= 24) {
        return sha256.convert(utf8.encode('banco_chile|$canonical')).toString();
      }
    }
    return null;
  }

  String _sourceType(PayrollStatementExtractionResult extraction) {
    if (extraction.inputKind == PayrollStatementInputKind.image) {
      return 'image_ocr';
    }
    return extraction.method == PayrollStatementExtractionMethod.embeddedPdfText
        ? 'pdf_text'
        : 'pdf_ocr';
  }

  String _safeExtension(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot < 0 || dot == filename.length - 1) return '';
    return filename.substring(dot + 1).toLowerCase();
  }

  Map<String, dynamic> _receiptMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw const BankReconciliationServiceException(
      'El servidor respondió sin un comprobante válido.',
    );
  }

  String _requiredText(Map<String, dynamic> value, String key) {
    final text = value[key]?.toString().trim() ?? '';
    if (text.isEmpty) {
      throw const BankReconciliationServiceException(
        'El comprobante del servidor está incompleto.',
      );
    }
    return text;
  }

  int _requiredInt(Map<String, dynamic> value, String key) {
    final result = _intOf(value[key]);
    if (result == null) {
      throw const BankReconciliationServiceException(
        'El comprobante del servidor está incompleto.',
      );
    }
    return result;
  }

  int? _intOf(dynamic value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }

  String _targetKindCode(BankReconciliationTargetKind kind) => switch (kind) {
        BankReconciliationTargetKind.salesPayment => 'sales_payment',
        BankReconciliationTargetKind.purchasePayment => 'purchase_payment',
        BankReconciliationTargetKind.expensePayment => 'expense_payment',
        BankReconciliationTargetKind.expense => 'expense',
        BankReconciliationTargetKind.journalEntry => 'journal_entry',
      };

  String _matchKindCode(BankReconciliationMatchKind kind) => switch (kind) {
        BankReconciliationMatchKind.direct => 'direct',
        BankReconciliationMatchKind.processorEstimate => 'processor_estimate',
        BankReconciliationMatchKind.transbankEstimate => 'transbank_estimate',
        BankReconciliationMatchKind.manual => 'manual',
      };

  String _providerCode(BankSettlementProvider provider) => switch (provider) {
        BankSettlementProvider.none => 'none',
        BankSettlementProvider.transbank => 'transbank',
        BankSettlementProvider.mercadoPago => 'mercadopago',
        BankSettlementProvider.other => 'other',
      };

  String _normalize(String value) => normalizePayrollReconciliationText(value);
}
