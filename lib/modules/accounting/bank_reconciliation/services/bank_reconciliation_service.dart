import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../../shared/services/database_service.dart';
import '../../../../shared/services/gemini_proxy_service.dart';
import '../../models/account.dart';
import '../../utils/bank_ledger_account_policy.dart';
import '../../../hr/models/payroll_statement_reconciliation.dart';
import '../../../hr/services/payroll_bank_statement_parser.dart';
import '../../../hr/services/payroll_statement_extraction_service.dart';
import '../../../hr/services/payroll_statement_veryfi_ocr.dart';
import '../models/bank_reconciliation_models.dart';
import 'bank_reconciliation_advisor.dart';
import 'bank_reconciliation_ai_analyst.dart';
import 'bank_reconciliation_catalog_codec.dart';
import 'bank_reconciliation_matcher.dart';
import 'bank_reconciliation_third_party.dart';

typedef BankReconciliationRpc = Future<dynamic> Function(
  String functionName,
  Map<String, dynamic> params,
);

/// Another screen saved the conciliation after this one loaded it.
class BankReconciliationDraftConflict implements Exception {
  const BankReconciliationDraftConflict();
}

class BankReconciliationServiceException implements Exception {
  const BankReconciliationServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One statement file picked by the operator.
class BankStatementFileInput {
  const BankStatementFileInput({
    required this.bytes,
    required this.filename,
    this.sourcePath,
  });

  final Uint8List bytes;
  final String filename;
  final String? sourcePath;
}

class _ReadStatement {
  const _ReadStatement({
    required this.file,
    required this.extraction,
    required this.movements,
    required this.sourceType,
    required this.accountFingerprint,
    required this.firstDate,
    required this.lastDate,
    required this.warnings,
  });

  final BankStatementFileInput file;
  final PayrollStatementExtractionResult extraction;
  final List<BankStatementMovement> movements;
  final String sourceType;
  final String? accountFingerprint;
  final BankCivilDate? firstDate;
  final BankCivilDate? lastDate;
  final List<String> warnings;
}

/// What the review needs of one statement, read from its file or rebuilt
/// from the rows an earlier import saved.
class _StatementEvidence {
  const _StatementEvidence({
    required this.fileSha256,
    required this.filename,
    required this.sourceType,
    required this.accountFingerprint,
    required this.movements,
    required this.firstDate,
    required this.lastDate,
    this.warnings = const <String>[],
  });

  final String fileSha256;
  final String filename;
  final String sourceType;
  final String? accountFingerprint;
  final List<BankStatementMovement> movements;
  final BankCivilDate? firstDate;
  final BankCivilDate? lastDate;
  final List<String> warnings;
}

class BankReconciliationService {
  BankReconciliationService({
    required DatabaseService database,
    PayrollBankStatementParser parser = const PayrollBankStatementParser(),
    PayrollStatementVeryfiOcr veryfiOcr = const PayrollStatementVeryfiOcr(),
    BankReconciliationMatcher matcher = const BankReconciliationMatcher(),
    BankReconciliationAdvisor advisor = const BankReconciliationAdvisor(),
    BankReconciliationRpc? rpc,
    BankAiGenerate? aiGenerate,
  })  : _database = database,
        _aiGenerate = aiGenerate,
        _parser = parser,
        _veryfiOcr = veryfiOcr,
        _matcher = matcher,
        _advisor = advisor,
        _rpc = rpc ??
            ((functionName, params) =>
                database.supabase.rpc(functionName, params: params));

  static const parserName = 'banco_chile_statement';
  static const parserVersion = 'banco_chile_v2_accounting';

  final DatabaseService _database;
  final PayrollBankStatementParser _parser;
  final PayrollStatementVeryfiOcr _veryfiOcr;
  final BankReconciliationMatcher _matcher;
  final BankReconciliationAdvisor _advisor;
  final BankReconciliationRpc _rpc;
  final BankAiGenerate? _aiGenerate;

  /// The model the AI analysis asks: the same one the rest of the ERP uses
  /// for reading with judgement, through the tenant's Gemini proxy.
  static const aiModel = 'gemini-2.5-flash';

  /// Reads the movements nothing explains and proposes, per movement, what
  /// it probably is, what may be missing and the question that would settle
  /// it. Proposals are verified before they reach the review; nothing is
  /// applied. Batches arrive through [onBatch] as they are judged.
  Future<Map<String, BankAiAnalysis>> analyzeWithAi({
    required BankReconciliationPreparedDraft draft,
    required BankReconciliationWorkspaceOptions? options,
    Map<String, String> answers = const <String, String>{},
    Set<String>? rowIds,
    BankAiBatchCallback? onBatch,
  }) async {
    final analyst = BankReconciliationAiAnalyst(
      generate: _aiGenerate ?? _geminiGenerate,
    );
    try {
      return await analyst.analyze(
        draft: draft,
        options: options,
        answers: answers,
        rowIds: rowIds,
        onBatch: onBatch,
      );
    } catch (error) {
      debugPrint('BankReconciliationService AI analysis: $error');
      final text = error.toString();
      throw BankReconciliationServiceException(
        text.contains('429') || text.contains('RESOURCE_EXHAUSTED')
            ? 'La IA está al límite de consultas por minuto. No se cambió '
                'nada: intenta de nuevo en un minuto.'
            : 'El análisis con IA no respondió. No se cambió nada: puedes '
                'intentar de nuevo.',
      );
    }
  }

  static Future<String> _geminiGenerate({
    required String system,
    required String prompt,
  }) async {
    final result = await GeminiProxyService().generateContent(
      model: aiModel,
      systemInstruction: <String, dynamic>{
        'parts': <Map<String, dynamic>>[
          <String, dynamic>{'text': system},
        ],
      },
      contents: <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'user',
          'parts': <Map<String, dynamic>>[
            <String, dynamic>{'text': prompt},
          ],
        },
      ],
      // A bounded thought keeps one batch far below the proxy's 150 s.
      generationConfig: const <String, dynamic>{
        'responseMimeType': 'application/json',
        'temperature': 0.2,
        'thinkingConfig': <String, dynamic>{'thinkingBudget': 2048},
      },
    );
    if (result.text.trim().isEmpty) throw StateError('Empty AI response');
    return result.text;
  }

  /// Every direct table read is scoped to the operator's tenant explicitly,
  /// not only by row-level security.
  Future<String> _requireTenantId() async {
    final tenantId = await _database.getTenantId();
    if (tenantId == null || tenantId.trim().isEmpty) {
      throw const BankReconciliationServiceException(
        'No pudimos identificar la empresa de tu sesión.',
      );
    }
    return tenantId;
  }

  Future<List<BankReconciliationAccountOption>> loadBankAccounts() async {
    final tenantId = await _requireTenantId();
    final rows = await _database.supabase
        .from('accounts')
        .select(
          'id, tenant_id, code, name, type, category, parent_id, is_active',
        )
        .eq('tenant_id', tenantId)
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
    final tenantId = await _requireTenantId();
    final accountRows = await _database.supabase
        .from('accounts')
        .select('id, code, name, type, category, is_active')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('code');
    final methodRows = await _database.supabase
        .from('payment_methods')
        .select('id, code, name, account_id, is_active, usage_scope')
        .eq('tenant_id', tenantId)
        .eq('account_id', erpAccountId)
        .eq('is_active', true)
        .inFilter('usage_scope', const ['outbound', 'both']).order('name');
    final supplierRows = await _database.supabase
        .from('suppliers')
        .select('id, name')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('name');

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
      suppliers: <BankReconciliationSupplierOption>[
        for (final raw in supplierRows)
          if ((raw['id']?.toString().trim() ?? '').isNotEmpty &&
              (raw['name']?.toString().trim() ?? '').isNotEmpty)
            BankReconciliationSupplierOption(
              supplierId: raw['id'].toString().trim(),
              name: raw['name'].toString().trim(),
            ),
      ],
    );
  }

  Future<BankReconciliationPreparedDraft> prepare({
    required Uint8List bytes,
    required String filename,
    required String erpAccountId,
    String? sourcePath,
    int? statementYear,
    PayrollStatementPreparationProgressCallback? onProgress,
  }) {
    return prepareMany(
      files: <BankStatementFileInput>[
        BankStatementFileInput(
          bytes: bytes,
          filename: filename,
          sourcePath: sourcePath,
        ),
      ],
      erpAccountId: erpAccountId,
      statementYear: statementYear,
      onProgress: onProgress,
    );
  }

  /// Reads one or several statements of the same account and reviews them
  /// together: a card sale of 30 June settled on 2 July is explained across
  /// the two files, and one assignment covers every movement.
  Future<BankReconciliationPreparedDraft> prepareMany({
    required List<BankStatementFileInput> files,
    required String erpAccountId,
    int? statementYear,
    PayrollStatementPreparationProgressCallback? onProgress,
  }) async {
    if (files.isEmpty) {
      throw const BankReconciliationServiceException(
        'Elige al menos una cartola.',
      );
    }
    final extractionService = PayrollStatementExtractionService(
      cloudDocumentTextExtractor: _veryfiOcr.extractText,
    );
    final statements = <_ReadStatement>[];
    final seenFiles = <String>{};
    for (final file in files) {
      final statement = await _readStatement(
        extractionService,
        file,
        statementYear: statementYear,
        onProgress: onProgress,
      );
      if (seenFiles.add(statement.extraction.fileSha256)) {
        statements.add(statement);
      }
    }
    return _review(
      statements: <_StatementEvidence>[
        for (final statement in statements)
          _StatementEvidence(
            fileSha256: statement.extraction.fileSha256,
            filename: statement.file.filename,
            sourceType: statement.sourceType,
            accountFingerprint: statement.accountFingerprint,
            movements: statement.movements,
            firstDate: statement.firstDate,
            lastDate: statement.lastDate,
            warnings: statement.warnings,
          ),
      ],
      erpAccountId: erpAccountId,
    );
  }

  /// Reviews statements already read, from their files or from what an
  /// earlier import saved: one assignment covers every movement.
  Future<BankReconciliationPreparedDraft> _review({
    required List<_StatementEvidence> statements,
    required String erpAccountId,
  }) async {
    final fingerprints = statements
        .map((statement) => statement.accountFingerprint)
        .whereType<String>()
        .toSet();
    if (fingerprints.length > 1) {
      throw const BankReconciliationServiceException(
        'Las cartolas son de cuentas bancarias distintas. Concilia cada '
        'cuenta por separado.',
      );
    }

    // Unique ids across files; a movement repeated by two overlapping
    // statements (same date, amount, balance and text) is reviewed once.
    final multiple = statements.length > 1;
    final entries = <(BankStatementMovement, String, int)>[];
    final seenInEarlierFiles = <String>{};
    var repeated = 0;
    for (var index = 0; index < statements.length; index++) {
      final statement = statements[index];
      final keys = <String>{};
      for (final movement in statement.movements) {
        final key = movement.balanceClp == null
            ? null
            : <Object?>[
                movement.bookingDate,
                movement.direction.name,
                movement.amountClp,
                movement.balanceClp,
                movement.normalizedDescription,
              ].join('|');
        if (multiple && key != null && seenInEarlierFiles.contains(key)) {
          repeated++;
          continue;
        }
        if (key != null) keys.add(key);
        entries.add((
          multiple
              ? movement.withSourceRowId(
                  '${statement.fileSha256.substring(0, 12)}:'
                  '${movement.sourceRowId}',
                )
              : movement,
          statement.fileSha256,
          index,
        ));
      }
      seenInEarlierFiles.addAll(keys);
    }
    entries.sort((left, right) {
      final leftDate = left.$1.bookingDate;
      final rightDate = right.$1.bookingDate;
      if (leftDate != null && rightDate != null) {
        final byDate = leftDate.compareTo(rightDate);
        if (byDate != 0) return byDate;
      }
      final byFile = left.$3.compareTo(right.$3);
      return byFile != 0 ? byFile : left.$1.ordinal.compareTo(right.$1.ordinal);
    });
    final movements = [for (final entry in entries) entry.$1];
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

    // Salaries are registered up to weeks after the transfer, so the
    // catalog reaches further back than the statement.
    final context = await loadContext(
      erpAccountId: erpAccountId,
      from: dated.first.addDays(-45),
      to: dated.last.addDays(10),
    );
    final terminalPolicies = await loadTerminalMatchPolicies(
      from: dated.first.addDays(-30),
      to: dated.last,
    );
    BankReconciliationWorkspaceOptions? options;
    try {
      options = await loadWorkspaceOptions(erpAccountId: erpAccountId);
    } catch (error) {
      // Suggestions degrade to prefilled text; matching still works.
      debugPrint('BankReconciliationService workspace options: $error');
    }
    // What an earlier review settled is shown as done and never decided
    // again: rows of this statement applied in an earlier sitting, and
    // movements an overlapping statement of the account already settled.
    final settled = settledMovements(entries, context.reconciledRows);
    final open = <BankStatementMovement>[
      for (final movement in movements)
        if (!settled.containsKey(movement.sourceRowId)) movement,
    ];
    final match = _matcher.analyze(
      movements: open,
      candidates: context.candidates,
      terminalPolicies: terminalPolicies,
    );
    final suggestions = _advisor.suggest(
      movements: open,
      proposals: match.proposals,
      context: context,
      options: options,
    );
    // Several operations one transfer to somebody else settled; not where a
    // salary or a known booking already explains the movement.
    final thirdParty = const BankThirdPartyFinder().find(
      movements: open,
      proposals: match.proposals,
      candidates: context.candidates,
      skipSourceRowIds: <String>{
        for (final entry in suggestions.entries)
          if (entry.value.confidence == BankReconciliationConfidence.high)
            entry.key,
      },
    );
    // A transfer somebody else paid, beyond doubt, is accepted with the safe
    // suggestions: it selects the association.
    final allSuggestions = <String, BankReconciliationSuggestion>{
      ...suggestions,
    };
    for (final entry in thirdParty.entries) {
      final proposal = entry.value;
      if (proposal.confidence != BankReconciliationConfidence.high ||
          proposal.allocations.length != 1 ||
          allSuggestions.containsKey(entry.key)) {
        continue;
      }
      final candidate = proposal.allocations.single.candidate;
      final incoming = candidate.direction == BankMovementDirection.credit;
      allSuggestions[entry.key] = BankReconciliationSuggestion(
        kind: BankSuggestionKind.otherPayer,
        confidence: BankReconciliationConfidence.high,
        title: '${candidate.label} · '
            '${incoming ? 'la pagó otra persona' : 'la recibió otra persona'}',
        reasons: proposal.reasons,
        resolution: const BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.associateExisting,
        ),
        proposalId: BankReconciliationRowDraft.proposalIdentity(proposal),
      );
    }
    final first = statements.first;
    return BankReconciliationPreparedDraft(
      fileSha256: first.fileSha256,
      filename: multiple ? '${statements.length} cartolas' : first.filename,
      sourceType: first.sourceType,
      accountFingerprint: first.accountFingerprint,
      parserName: parserName,
      parserVersion: parserVersion,
      rows: <BankReconciliationRowDraft>[
        for (final entry in entries)
          BankReconciliationRowDraft(
            movement: entry.$1,
            proposals: <BankReconciliationProposal>[
              // The same operation found as paid by somebody else replaces
              // the doubtful alternative the name made of it.
              for (final proposal in match.proposals[entry.$1.sourceRowId] ??
                  const <BankReconciliationProposal>[])
                if (!_sameOperations(
                    proposal, thirdParty[entry.$1.sourceRowId]))
                  proposal,
              if (thirdParty[entry.$1.sourceRowId] != null)
                thirdParty[entry.$1.sourceRowId]!,
            ],
            suggestion: allSuggestions[entry.$1.sourceRowId],
            sourceFileSha256: multiple ? entry.$2 : null,
            settled: settled[entry.$1.sourceRowId],
          ),
      ],
      candidateCatalog: context.candidates,
      extractionWarnings: <String>[
        for (final statement in statements) ...statement.warnings,
        if (repeated > 0)
          '$repeated movimiento(s) aparecen en dos cartolas que se traslapan; '
              'se revisan una sola vez.',
      ],
      sources: <BankStatementSource>[
        for (final statement in statements)
          BankStatementSource(
            fileSha256: statement.fileSha256,
            filename: statement.filename,
            sourceType: statement.sourceType,
            accountFingerprint: statement.accountFingerprint,
            firstDate: statement.firstDate,
            lastDate: statement.lastDate,
            movementCount: entries
                .where((entry) => entry.$2 == statement.fileSha256)
                .length,
          ),
      ],
      context: context,
      insights: <BankReconciliationInsight>[
        ..._settledInsights(settled.values),
        ...match.insights,
        ..._advisor.insights(allSuggestions),
      ],
    );
  }

  static bool _sameOperations(
    BankReconciliationProposal proposal,
    BankReconciliationProposal? other,
  ) {
    if (other == null || proposal.isSelectedByDefault) return false;
    final mine = proposal.allocations.map((item) => item.candidate.identity);
    final theirs = other.allocations.map((item) => item.candidate.identity);
    return mine.toSet().containsAll(theirs) && theirs.toSet().containsAll(mine);
  }

  /// Which movements an earlier review settled, by statement row or, across
  /// overlapping statements, by date, direction, amount and balance.
  @visibleForTesting
  static Map<String, BankSettledMovement> settledMovements(
    List<(BankStatementMovement, String, int)> entries,
    List<BankReconciledRow> reconciled,
  ) {
    final byStatementRow = <String, BankReconciledRow>{
      for (final row in reconciled) '${row.fileSha256}|${row.sourceRowId}': row,
    };
    final byKey = <String, BankReconciledRow>{};
    for (final row in reconciled) {
      final key = row.key;
      if (key == null) continue;
      final current = byKey[key];
      // The statement that settled it, not a later one that recorded it.
      if (current == null ||
          (current.settledElsewhere && !row.settledElsewhere)) {
        byKey[key] = row;
      }
    }
    final settled = <String, BankSettledMovement>{};
    for (final (movement, sha, _) in entries) {
      final own = byStatementRow['$sha|${movement.persistedRowId}'];
      if (own != null) {
        settled[movement.sourceRowId] = _settledFrom(own, sameStatement: true);
        continue;
      }
      final key = BankReconciledRow.keyOf(
        bookingDate: movement.bookingDate,
        direction: movement.direction,
        amountClp: movement.amountClp,
        balanceClp: movement.balanceClp,
      );
      final other = key == null ? null : byKey[key];
      if (other != null && other.fileSha256 != sha) {
        settled[movement.sourceRowId] =
            _settledFrom(other, sameStatement: false);
      }
    }
    return settled;
  }

  static BankSettledMovement _settledFrom(
    BankReconciledRow row, {
    required bool sameStatement,
  }) {
    final note = row.note?.trim();
    final summary = row.labels.isNotEmpty
        ? row.labels.join(' + ')
        : row.settledElsewhere
            ? 'Conciliado en otra cartola'
            : row.disposition == BankReconciliationDisposition.ignored
                ? (note == null || note.isEmpty
                    ? 'Excluido'
                    : 'Excluido: $note')
                : 'Conciliado';
    return BankSettledMovement(
      sameStatement: sameStatement,
      summary: summary,
      disposition: row.disposition,
      excluded: row.disposition == BankReconciliationDisposition.ignored &&
          !row.settledElsewhere,
      decidedOn: row.decidedOn,
    );
  }

  static List<BankReconciliationInsight> _settledInsights(
    Iterable<BankSettledMovement> settled,
  ) {
    final same = settled.where((item) => item.sameStatement).length;
    final other = settled.length - same;
    return <BankReconciliationInsight>[
      if (same > 0)
        BankReconciliationInsight(
          title: same == 1
              ? '1 movimiento ya se aplicó'
              : '$same movimientos ya se aplicaron',
          body: 'Se aplicaron en una revisión anterior de esta cartola. Se '
              'muestran como conciliados y no se vuelven a tocar; lo que '
              'quedó pendiente se resuelve ahora.',
        ),
      if (other > 0)
        BankReconciliationInsight(
          title: other == 1
              ? '1 movimiento ya estaba conciliado en otra cartola'
              : '$other movimientos ya estaban conciliados en otra cartola',
          body: 'Aparecen también en una cartola que ya aplicaste. Al aplicar '
              'ésta quedan registrados como conciliados allá, sin crear ni '
              'asociar nada dos veces.',
        ),
    ];
  }

  Future<_ReadStatement> _readStatement(
    PayrollStatementExtractionService extractionService,
    BankStatementFileInput file, {
    required int? statementYear,
    required PayrollStatementPreparationProgressCallback? onProgress,
  }) async {
    PayrollStatementExtractionResult extraction;
    try {
      extraction = await extractionService.extract(
        bytes: file.bytes,
        filename: file.filename,
        sourcePath: file.sourcePath,
        onProgress: onProgress,
      );
    } on PayrollStatementExtractionException catch (error) {
      throw BankReconciliationServiceException(
        '${file.filename}: ${error.message}',
      );
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
        bytes: file.bytes,
        filename: file.filename,
        sourcePath: file.sourcePath,
        forceImageOcrForPdf: true,
        onProgress: onProgress,
      );
      parsed = _parser.parsePages(
        extraction.pages.map((page) => page.text).toList(growable: false),
        statementYear: year,
      );
    }
    if (extraction.needsImageOcr || parsed.rows.isEmpty) {
      throw BankReconciliationServiceException(
        '${file.filename}: no se reconocieron movimientos bancarios '
        'revisables.',
      );
    }
    final movements = _mapMovements(parsed.rows);
    final dated = movements
        .map((movement) => movement.bookingDate)
        .whereType<BankCivilDate>()
        .toList(growable: false)
      ..sort();
    return _ReadStatement(
      file: file,
      extraction: extraction,
      movements: movements,
      sourceType: _sourceType(extraction),
      accountFingerprint: _extractAccountFingerprint(extraction),
      firstDate: dated.isEmpty ? null : dated.first,
      lastDate: dated.isEmpty ? null : dated.last,
      warnings: <String>[
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
      final tenantId = await _requireTenantId();
      final profileRows = await _database.supabase
          .from('payment_terminal_profiles')
          .select(
            'id,provider_code,provider_name,terminal_name,descriptor_patterns',
          )
          .eq('tenant_id', tenantId)
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
          .eq('tenant_id', tenantId)
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
    final context = await loadContext(
      erpAccountId: erpAccountId,
      from: from,
      to: to,
    );
    return context.candidates;
  }

  /// Candidates plus what explains an unregistered movement: unpaid payroll,
  /// open invoices, counterparties and earlier decisions.
  Future<BankReconciliationContext> loadContext({
    required String erpAccountId,
    required BankCivilDate from,
    required BankCivilDate to,
  }) async {
    final raw = await _rpc(
      'get_bank_reconciliation_candidates_v2',
      <String, dynamic>{
        'p_erp_account_id': erpAccountId,
        'p_from_date': from.toString(),
        'p_to_date': to.toString(),
      },
    );
    final context = const BankReconciliationCatalogCodec().context(raw);
    return context.withRules(await loadRules());
  }

  /// The company's rules for statement lines by their words. Without them
  /// the review still works on the shared merchant table.
  Future<List<BankReconciliationRule>> loadRules() async {
    try {
      final tenantId = await _requireTenantId();
      final rows = await _database.supabase
          .from('bank_reconciliation_rules')
          .select('id,pattern,direction,action,account_id,description')
          .eq('tenant_id', tenantId);
      return <BankReconciliationRule>[
        for (final row in rows) ruleFromRow(Map<String, dynamic>.from(row)),
      ];
    } catch (error) {
      debugPrint('BankReconciliationService rules: $error');
      return const <BankReconciliationRule>[];
    }
  }

  static BankReconciliationRule ruleFromRow(Map<String, dynamic> row) =>
      BankReconciliationRule(
        ruleId: (row['id'] ?? row['rule_id']).toString(),
        pattern: row['pattern'].toString(),
        direction: row['direction'] == 'credit'
            ? BankMovementDirection.credit
            : BankMovementDirection.debit,
        action: row['action'] == 'create_expense'
            ? BankReconciliationActionKind.createExpense
            : BankReconciliationActionKind.classifyAccount,
        accountId: row['account_id'].toString(),
        description: row['description'].toString(),
      );

  /// Teaches the company rule for lines with [pattern]; the same text again
  /// replaces it.
  Future<BankReconciliationRule> saveRule({
    required String pattern,
    required BankMovementDirection direction,
    required BankReconciliationActionKind action,
    required String accountId,
    required String description,
  }) async {
    final raw = await _rpc(
      'save_bank_reconciliation_rule_v1',
      <String, dynamic>{
        'p_pattern': pattern,
        'p_direction':
            direction == BankMovementDirection.credit ? 'credit' : 'debit',
        'p_action': action == BankReconciliationActionKind.createExpense
            ? 'create_expense'
            : 'post_journal',
        'p_account_id': accountId,
        'p_description': description,
      },
    );
    return ruleFromRow(_receiptMap(raw));
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
    // The server keys rows by the file's own row id; the review keys them by
    // the id made unique across statements.
    final draftIdByPersisted = <String, String>{
      for (final row in draft.rows)
        row.movement.persistedRowId: row.movement.sourceRowId,
    };
    final rowMap = <String, String>{};
    final rows = receipt['rows'];
    if (rows is List) {
      for (final item in rows.whereType<Map>()) {
        final source = item['source_row_id']?.toString() ?? '';
        final id = item['row_id']?.toString() ?? '';
        final draftId = draftIdByPersisted[source];
        if (draftId != null && id.isNotEmpty) rowMap[draftId] = id;
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

  /// Registers the conciliation these imports belong to, or opens the one
  /// they already joined, with its saved draft.
  Future<BankReconciliationSession> openSession({
    required String erpAccountId,
    required List<String> importIds,
  }) async {
    final raw = await _rpc(
      'open_bank_reconciliation_session_v1',
      <String, dynamic>{
        'p_erp_account_id': erpAccountId,
        'p_import_ids': importIds,
      },
    );
    final receipt = _receiptMap(raw);
    final draft = receipt['draft'];
    return BankReconciliationSession(
      sessionId: _requiredText(receipt, 'session_id'),
      revision: _requiredInt(receipt, 'revision'),
      draft: draft is Map ? Map<String, dynamic>.from(draft) : const {},
      created: receipt['created'] == true,
    );
  }

  /// Saves the draft over [revision]; another screen's newer save is never
  /// overwritten ([BankReconciliationDraftConflict]).
  Future<int> saveSessionDraft({
    required String sessionId,
    required int revision,
    required Map<String, dynamic> draft,
  }) async {
    final dynamic raw;
    try {
      raw = await _rpc(
        'save_bank_reconciliation_session_draft_v1',
        <String, dynamic>{
          'p_session_id': sessionId,
          'p_expected_revision': revision,
          'p_draft': draft,
        },
      );
    } catch (error) {
      if (error.toString().contains('bank_reconciliation_draft_conflict')) {
        throw const BankReconciliationDraftConflict();
      }
      rethrow;
    }
    return _requiredInt(_receiptMap(raw), 'revision');
  }

  /// The account's saved conciliations, newest first.
  Future<List<BankReconciliationSessionSummary>> listSessions({
    required String erpAccountId,
  }) async {
    final raw = await _rpc(
      'list_bank_reconciliation_sessions_v1',
      <String, dynamic>{'p_erp_account_id': erpAccountId},
    );
    final items = raw is List ? raw : const <Object?>[];
    return <BankReconciliationSessionSummary>[
      for (final item in items.whereType<Map>())
        BankReconciliationSessionSummary(
          sessionId: item['session_id'].toString(),
          statementCount: _intOf(item['statement_count']) ?? 0,
          movementCount: _intOf(item['movement_count']) ?? 0,
          decidedCount: _intOf(item['decided_count']) ?? 0,
          draftRows: _intOf(item['draft_rows']) ?? 0,
          draftDecisions: _intOf(item['draft_decisions']) ?? 0,
          draftAnalyses: _intOf(item['draft_analyses']) ?? 0,
          updatedAt: DateTime.tryParse(item['updated_at']?.toString() ?? '')
                  ?.toLocal() ??
              DateTime.now(),
          firstDate: _civilDate(item['first_date']),
          lastDate: _civilDate(item['last_date']),
          lastAppliedAt:
              DateTime.tryParse(item['last_applied_at']?.toString() ?? '')
                  ?.toLocal(),
        ),
    ];
  }

  /// Rebuilds a saved conciliation from the rows its imports kept — the
  /// files are never stored — and reviews it against today's ERP: what was
  /// applied shows as settled, the rest is decided again from the draft.
  Future<BankReconciliationResumedSession> resumeSession({
    required String sessionId,
    required String erpAccountId,
  }) async {
    final tenantId = await _requireTenantId();
    final imports = await _database.supabase
        .from('bank_statement_imports')
        .select('id,file_sha256,account_fingerprint,source_metadata,revision')
        .eq('tenant_id', tenantId)
        .eq('erp_account_id', erpAccountId)
        .eq('session_id', sessionId)
        .order('created_at');
    if (imports.isEmpty) {
      throw const BankReconciliationServiceException(
        'Esta conciliación no tiene cartolas guardadas.',
      );
    }
    final importIds = <String>[
      for (final item in imports) item['id'].toString(),
    ];
    final rows = <Map<String, dynamic>>[];
    const page = 1000;
    for (var from = 0;; from += page) {
      final batch = await _database.supabase
          .from('bank_statement_rows')
          .select(
            'id,import_id,source_row_id,ordinal,booking_date,operation_date,'
            'direction,amount,description,normalized_description,'
            'counterparty_observed,document_number,balance,warning_codes,'
            'source_page,source_page_end,source_line_start,source_line_end',
          )
          .eq('tenant_id', tenantId)
          .inFilter('import_id', importIds)
          .order('id')
          .range(from, from + page - 1);
      rows.addAll(batch.map(Map<String, dynamic>.from));
      if (batch.length < page) break;
    }
    final multiple = imports.length > 1;
    final evidence = <_StatementEvidence>[];
    final receipts = <String, BankStatementImportReceipt>{};
    for (final item in imports) {
      final importId = item['id'].toString();
      final sha = item['file_sha256'].toString();
      final metadata = item['source_metadata'];
      final own = rows.where((row) => row['import_id'].toString() == importId);
      final movements = <BankStatementMovement>[
        for (final row in own) _movementFromRow(row),
      ];
      final dated = movements
          .map((movement) => movement.bookingDate)
          .whereType<BankCivilDate>()
          .toList(growable: false)
        ..sort();
      evidence.add(_StatementEvidence(
        fileSha256: sha,
        filename: dated.isEmpty
            ? 'Cartola guardada'
            : 'Cartola ${_dayMonthYear(dated.first)} – '
                '${_dayMonthYear(dated.last)}',
        sourceType: metadata is Map
            ? metadata['source_type']?.toString() ?? 'pdf_text'
            : 'pdf_text',
        accountFingerprint: item['account_fingerprint']?.toString(),
        movements: movements,
        firstDate: dated.isEmpty ? null : dated.first,
        lastDate: dated.isEmpty ? null : dated.last,
      ));
      receipts[sha] = BankStatementImportReceipt(
        importId: importId,
        revision: _intOf(item['revision']) ?? 1,
        rowIdsBySourceRowId: <String, String>{
          for (final row in own)
            multiple
                ? '${sha.substring(0, 12)}:${row['source_row_id']}'
                : row['source_row_id'].toString(): row['id'].toString(),
        },
        replayed: true,
      );
    }
    final draft = await _review(
      statements: evidence,
      erpAccountId: erpAccountId,
    );
    final session = await openSession(
      erpAccountId: erpAccountId,
      importIds: importIds,
    );
    return BankReconciliationResumedSession(
      draft: draft,
      session: session,
      importReceipts: receipts,
    );
  }

  BankStatementMovement _movementFromRow(Map<String, dynamic> row) {
    int? money(Object? value) =>
        value is num ? value.round() : num.tryParse('$value')?.round();
    return BankStatementMovement(
      sourceRowId: row['source_row_id'].toString(),
      ordinal: _intOf(row['ordinal']) ?? 1,
      bookingDate: _civilDate(row['booking_date']),
      operationDate: _civilDate(row['operation_date']),
      description: row['description'].toString(),
      normalizedDescription: row['normalized_description'].toString(),
      counterpartyObserved: row['counterparty_observed']?.toString(),
      documentNumber: row['document_number']?.toString(),
      direction: switch (row['direction']) {
        'debit' => BankMovementDirection.debit,
        'credit' => BankMovementDirection.credit,
        _ => BankMovementDirection.unknown,
      },
      amountClp: row['amount'] == null ? null : money(row['amount']),
      balanceClp: row['balance'] == null ? null : money(row['balance']),
      warningCodes: <String>[
        for (final code in row['warning_codes'] as List? ?? const [])
          code.toString(),
      ],
      sourcePage: _intOf(row['source_page']) ?? 1,
      sourceLineStart: _intOf(row['source_line_start']) ?? 1,
      sourceLineEnd: _intOf(row['source_line_end']) ?? 1,
      sourcePageEnd: _intOf(row['source_page_end']),
    );
  }

  static String _dayMonthYear(BankCivilDate date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<BankReconciliationApplyReceipt> apply({
    required BankReconciliationPreparedDraft draft,
    required BankStatementImportReceipt importReceipt,
    String? operationKey,
  }) async {
    final actions = <Map<String, dynamic>>[];
    for (final row in draft.rows) {
      final settled = row.settled;
      // Decided in an earlier sitting of this statement: final on the server.
      if (settled != null && settled.sameStatement) continue;
      final rowId = importReceipt.rowIdsBySourceRowId[row.movement.sourceRowId];
      if (rowId == null) {
        throw const BankReconciliationServiceException(
          'La evidencia guardada no coincide con la revisión.',
        );
      }
      if (settled != null) {
        // Settled by an overlapping statement: recorded as such, which the
        // server proves against that statement.
        final reason = 'Conciliado en otra cartola: ${settled.summary}';
        actions.add(<String, dynamic>{
          'row_id': rowId,
          'action': 'dismiss',
          'reason': reason.length > 500 ? reason.substring(0, 500) : reason,
          'settled_elsewhere': true,
        });
        continue;
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
          BankReconciliationActionKind.payPayroll => 'pay_payroll',
          BankReconciliationActionKind.split => 'split',
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
        case BankReconciliationActionKind.split:
          if (!row.isResolved) {
            throw const BankReconciliationServiceException(
              'Completa cada parte con cuenta, monto y descripción: juntas '
              'deben sumar el movimiento.',
            );
          }
          final parts = resolution.splitParts;
          action['split'] = <String, dynamic>{
            if (parts.any((part) => part.isExpense))
              'payment_method_id': resolution.paymentMethodId,
            'reference': resolution.reference?.trim(),
            'parts': <Map<String, dynamic>>[
              for (final part in parts)
                <String, dynamic>{
                  'account_id': part.accountId,
                  'amount': part.amountClp,
                  'description': part.description.trim(),
                  if (part.isExpense && part.supplierId != null)
                    'supplier_id': part.supplierId,
                },
            ],
          };
          break;
        case BankReconciliationActionKind.payPayroll:
          final payroll = resolution.payroll;
          if (row.movement.direction != BankMovementDirection.debit ||
              payroll == null) {
            throw const BankReconciliationServiceException(
              'Elige el sueldo de Nómina que paga esta transferencia.',
            );
          }
          action['payroll'] = <String, dynamic>{
            'voucher_id': payroll.voucherId,
            'voucher_line_id': payroll.lineId,
            'expected_amount': payroll.expectedAmountClp,
            'amount': payroll.amountClp,
            'payment_method_id': payroll.paymentMethodId,
            'confirm_draft': payroll.confirmDraft,
            if (payroll.advances.isNotEmpty)
              'advances': <Map<String, dynamic>>[
                for (final use in payroll.advances)
                  <String, dynamic>{
                    'advance_id': use.advance.advanceId,
                    'amount': use.amountClp,
                  },
              ],
          };
          break;
      }
      actions.add(action);
    }
    final paidLines = <String>{};
    for (final row in draft.rows) {
      final payroll = row.effectiveResolution.action ==
              BankReconciliationActionKind.payPayroll
          ? row.effectiveResolution.payroll
          : null;
      if (payroll != null && !paidLines.add(payroll.lineId)) {
        throw BankReconciliationServiceException(
          'El sueldo de ${payroll.employeeName} (${payroll.voucherNumber}) '
          'está elegido en dos transferencias.',
        );
      }
    }
    // v3 is v2 plus paying Nómina salaries in the same transaction.
    final dynamic raw;
    try {
      raw = await _rpc(
        'apply_bank_reconciliation_actions_v3',
        <String, dynamic>{
          'p_import_id': importReceipt.importId,
          'p_expected_revision': importReceipt.revision,
          'p_operation_key': operationKey ?? const Uuid().v4(),
          'p_actions': actions,
        },
      );
    } catch (error) {
      final message = _payrollFailureMessage(error.toString());
      if (message == null) rethrow;
      throw BankReconciliationServiceException(message);
    }
    final receipt = _receiptMap(raw);
    return BankReconciliationApplyReceipt(
      importId: _requiredText(receipt, 'import_id'),
      revision: _requiredInt(receipt, 'revision'),
      status: _requiredText(receipt, 'status'),
      allocationCount: _requiredInt(receipt, 'allocation_count'),
      replayed: receipt['replayed'] == true,
      createdExpenseCount: _intOf(receipt['created_expense_count']) ?? 0,
      createdJournalCount: _intOf(receipt['created_journal_count']) ?? 0,
      payrollPaymentCount: _intOf(receipt['payroll_payment_count']) ?? 0,
    );
  }

  /// What the operator can do when Nómina refused to pay a salary. Nothing
  /// was saved: the apply is one transaction.
  static String? _payrollFailureMessage(String error) {
    if (error.contains('bank_reconciliation_payroll_line_changed') ||
        error.contains('payroll_payment_version_conflict') ||
        error.contains('payroll_voucher_lifecycle_version_conflict') ||
        error.contains('payroll_voucher_is_not_a_draft') ||
        error.contains('payroll_expense_payment_exceeds_line_balance') ||
        error.contains('Los movimientos exceden el saldo')) {
      return 'Un sueldo cambió en Nómina después de preparar la revisión '
          '(se pagó, se editó o se confirmó la semana). No se guardó nada: '
          'vuelve a subir las cartolas para ver lo que Nómina debe hoy.';
    }
    if (error.contains('bank_reconciliation_payroll_access_required') ||
        error.contains('Payroll access denied')) {
      return 'Tu usuario no puede pagar sueldos. No se guardó nada: pide '
          'acceso a Nómina o deja esas transferencias pendientes.';
    }
    if (error.contains('bank_reconciliation_payroll_advance_invalid')) {
      return 'Un anticipo de esta revisión ya se aplicó o cambió en Nómina. '
          'No se guardó nada: vuelve a subir las cartolas.';
    }
    if (error.contains('bank_reconciliation_payroll_method_invalid')) {
      return 'La cuenta no tiene un medio de pago «Transferencia» activo. '
          'No se guardó nada: créalo en Métodos de pago y vuelve a intentar.';
    }
    if (error.contains('debe registrarse como anticipo')) {
      return 'Nómina no acepta un sueldo pagado antes de cerrar su semana: '
          'regístralo como anticipo en Nómina. No se guardó nada.';
    }
    if (error.contains('bank_reconciliation_payroll')) {
      return 'Nómina no pudo registrar un sueldo de esta revisión. No se '
          'guardó nada; revisa esos movimientos o págalos en Nómina.';
    }
    if (error.contains('bank_reconciliation_split_total_mismatch')) {
      return 'Las partes de un movimiento dividido no suman lo mismo que el '
          'movimiento. No se guardó nada: corrige los montos.';
    }
    if (error.contains('bank_reconciliation_split_supplier_invalid')) {
      return 'Un proveedor elegido en un movimiento dividido ya no existe. '
          'No se guardó nada: elige otro o déjalo en blanco.';
    }
    if (error.contains('bank_reconciliation_split_expense_needs_debit')) {
      return 'Un abono no se registra como gasto. No se guardó nada: usa una '
          'cuenta que no sea de gasto para esa parte.';
    }
    if (error.contains('bank_reconciliation_row_already_decided') ||
        error.contains('bank_reconciliation_revision_conflict')) {
      return 'Esta cartola se aplicó en otra revisión mientras tenías ésta '
          'abierta. No se guardó nada: vuelve a subirla para ver lo que '
          'queda pendiente.';
    }
    if (error.contains('bank_reconciliation_row_settled_elsewhere') ||
        error.contains('bank_reconciliation_settled_elsewhere_unproven') ||
        error.contains('bank_reconciliation_target_already_linked')) {
      return 'Un movimiento u operación de esta revisión ya quedó conciliado '
          'en otra cartola. No se guardó nada: vuelve a subir las cartolas '
          'y aparecerá como ya conciliado.';
    }
    return null;
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
          sourcePageEnd:
              row.evidence.endPageNumber != row.evidence.startPageNumber
                  ? row.evidence.endPageNumber
                  : null,
        ),
    ];
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
      'source_row_id': movement.persistedRowId,
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
      if (movement.sourcePageEnd != null)
        'source_page_end': movement.sourcePageEnd,
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
        BankReconciliationMatchKind.thirdParty => 'manual',
      };

  String _providerCode(BankSettlementProvider provider) => switch (provider) {
        BankSettlementProvider.none => 'none',
        BankSettlementProvider.transbank => 'transbank',
        BankSettlementProvider.mercadoPago => 'mercadopago',
        BankSettlementProvider.other => 'other',
      };

  String _normalize(String value) => normalizePayrollReconciliationText(value);
}
