import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/database_service.dart';
import '../../../shared/utils/responsive_breakpoints.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/vb_money_text.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../../../shared/widgets/vb_short_select.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../bank_reconciliation/models/bank_reconciliation_models.dart';
import '../bank_reconciliation/services/bank_reconciliation_service.dart';

typedef BankStatementPrepareAction = Future<BankReconciliationPreparedDraft>
    Function({
  required List<BankStatementFileInput> files,
  required String erpAccountId,
});

/// Reads the movements nothing explains with the model (see
/// [BankReconciliationService.analyzeWithAi]).
typedef BankAiAnalyzeAction = Future<Map<String, BankAiAnalysis>> Function({
  required BankReconciliationPreparedDraft draft,
  required BankReconciliationWorkspaceOptions? options,
  Map<String, String> answers,
  Set<String>? rowIds,
  BankAiBatchCallback? onBatch,
});

class BankReconciliationActions {
  const BankReconciliationActions({
    required this.loadBankAccounts,
    required this.loadWorkspaceOptions,
    required this.prepare,
    required this.createImport,
    required this.apply,
    this.analyzeWithAi,
  });

  /// Absent where no model is available: the review works without it.
  final BankAiAnalyzeAction? analyzeWithAi;

  final Future<List<BankReconciliationAccountOption>> Function()
      loadBankAccounts;
  final Future<BankReconciliationWorkspaceOptions> Function({
    required String erpAccountId,
  }) loadWorkspaceOptions;
  final BankStatementPrepareAction prepare;
  final Future<BankStatementImportReceipt> Function({
    required BankReconciliationPreparedDraft draft,
    required String erpAccountId,
    String? operationKey,
  }) createImport;
  final Future<BankReconciliationApplyReceipt> Function({
    required BankReconciliationPreparedDraft draft,
    required BankStatementImportReceipt importReceipt,
    String? operationKey,
  }) apply;
}

enum _MovementFilter {
  all,
  open,
  ai,
  proposed,
  suggested,
  processor,
  unmatched
}

bool _isProcessorEstimate(BankReconciliationMatchKind kind) =>
    kind == BankReconciliationMatchKind.processorEstimate ||
    kind == BankReconciliationMatchKind.transbankEstimate;

class BankReconciliationPage extends StatefulWidget {
  const BankReconciliationPage({
    super.key,
    this.actions,
    this.initialDraft,
  });

  final BankReconciliationActions? actions;
  final BankReconciliationPreparedDraft? initialDraft;

  @override
  State<BankReconciliationPage> createState() => _BankReconciliationPageState();
}

class _BankReconciliationPageState extends State<BankReconciliationPage> {
  BankReconciliationActions? _resolvedActions;
  List<BankReconciliationAccountOption> _accounts = const [];
  String? _selectedAccountId;
  BankReconciliationPreparedDraft? _draft;
  BankReconciliationWorkspaceOptions? _workspaceOptions;
  String? _selectedSourceRowId;
  BankReconciliationApplyReceipt? _applyReceipt;
  _MovementFilter _filter = _MovementFilter.all;
  bool _loadingAccounts = true;
  bool _loadingWorkspaceOptions = false;
  bool _busy = false;
  String? _error;

  /// The AI analysis in flight: the whole review, or one answered movement.
  bool _analyzing = false;
  String? _analyzingRowId;
  int _aiAnalyzed = 0;
  int _aiRequested = 0;
  final Map<String, String> _aiAnswers = {};

  // One import per statement file, keyed by its sha: a retry after a partial
  // failure replays the same operations instead of duplicating them.
  final Map<String, BankStatementImportReceipt> _importReceipts = {};
  final Map<String, BankReconciliationApplyReceipt> _applyReceipts = {};
  final Map<String, String> _createOperationKeys = {};
  final Map<String, String> _applyOperationKeys = {};

  @override
  void reassemble() {
    super.reassemble();
    // Provider-backed action bundles can gain a new callback while this page
    // remains mounted during macOS debug iteration. Recreate the bundle after
    // hot reload so an old in-memory instance never exposes a newly added
    // callback as null. Injected test actions remain owned by the caller.
    if (widget.actions == null) _resolvedActions = null;
  }

  BankReconciliationActions get _actions {
    final injected = widget.actions;
    if (injected != null) return injected;
    return _resolvedActions ??= _providerActions();
  }

  BankReconciliationActions _providerActions() {
    final service = BankReconciliationService(
      database: context.read<DatabaseService>(),
    );
    return BankReconciliationActions(
      loadBankAccounts: service.loadBankAccounts,
      loadWorkspaceOptions: service.loadWorkspaceOptions,
      prepare: ({
        required files,
        required erpAccountId,
      }) =>
          service.prepareMany(
        files: files,
        erpAccountId: erpAccountId,
      ),
      createImport: service.createImport,
      apply: service.apply,
      analyzeWithAi: service.analyzeWithAi,
    );
  }

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAccounts());
  }

  Future<void> _loadAccounts() async {
    try {
      final accounts = await _actions.loadBankAccounts();
      if (!mounted) return;
      setState(() {
        _accounts = accounts;
        _selectedAccountId =
            accounts.length == 1 ? accounts.single.accountId : null;
        _loadingAccounts = false;
      });
      if (_selectedAccountId != null && _draft != null) {
        await _loadWorkspaceOptions(_selectedAccountId!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingAccounts = false;
        _error = 'No pudimos cargar las cuentas bancarias de Contabilidad.';
      });
    }
  }

  Future<void> _loadWorkspaceOptions(String accountId) async {
    if (mounted) setState(() => _loadingWorkspaceOptions = true);
    try {
      final options = await _actions.loadWorkspaceOptions(
        erpAccountId: accountId,
      );
      if (!mounted) return;
      setState(() => _workspaceOptions = options);
    } catch (error, stackTrace) {
      debugPrint(
        '[BankReconciliation] workspace options failed: $error',
      );
      debugPrintStack(
        label: '[BankReconciliation] workspace options stack',
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar las cuentas y medios necesarios para '
            'resolver movimientos.';
      });
    } finally {
      if (mounted) setState(() => _loadingWorkspaceOptions = false);
    }
  }

  Future<void> _pickStatement() async {
    final accountId = _selectedAccountId;
    if (accountId == null || _busy) return;
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    final files = <BankStatementFileInput>[
      for (final file in result?.files ?? const <PlatformFile>[])
        if (file.bytes != null)
          BankStatementFileInput(
            bytes: file.bytes!,
            filename: file.name,
            sourcePath: file.path,
          ),
    ];
    if (files.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _applyReceipt = null;
    });
    try {
      final draft = await _actions.prepare(
        files: files,
        erpAccountId: accountId,
      );
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _clearPersistence();
      });
      await _loadWorkspaceOptions(accountId);
    } on BankReconciliationServiceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error, stackTrace) {
      debugPrint('[BankReconciliation] statement preparation failed: $error');
      debugPrintStack(
        label: '[BankReconciliation] preparation stack',
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() =>
          _error = 'No pudimos leer esta cartola. Prueba con otro archivo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clearPersistence() {
    _importReceipts.clear();
    _applyReceipts.clear();
    _createOperationKeys.clear();
    _applyOperationKeys.clear();
  }

  void _replaceRow(BankReconciliationRowDraft replacement) {
    _replaceRows(<BankReconciliationRowDraft>[replacement]);
  }

  void _replaceRows(List<BankReconciliationRowDraft> replacements) {
    final draft = _draft;
    if (draft == null || _busy || _applyReceipt != null) return;
    // A statement already applied (the other one failed) is final: an edit
    // there would never be saved.
    final editable = replacements
        .where((row) => !_applyReceipts.containsKey(
              row.sourceFileSha256 ?? draft.fileSha256,
            ))
        .toList(growable: false);
    if (editable.isEmpty) return;
    setState(() {
      _draft = draft.replaceRows(editable);
      _error = null;
      // A changed decision is a new apply payload for files not applied yet.
      _applyOperationKeys.removeWhere(
        (sha, _) => !_applyReceipts.containsKey(sha),
      );
    });
  }

  BankReconciliationRowDraft _withResolution(
    BankReconciliationRowDraft row,
    BankReconciliationResolutionDraft resolution,
  ) {
    return row.copyWith(
      clearSelection:
          resolution.action != BankReconciliationActionKind.associateExisting,
      resolution: resolution,
      disposition: switch (resolution.action) {
        BankReconciliationActionKind.dismiss =>
          BankReconciliationDisposition.ignored,
        BankReconciliationActionKind.pending =>
          BankReconciliationDisposition.pending,
        _ => BankReconciliationDisposition.reconciled,
      },
    );
  }

  void _applySuggestion(String sourceRowId) {
    final row = _draft?.rowsBySourceId[sourceRowId];
    final resolution = row?.suggestion?.resolution;
    if (row == null || resolution == null) return;
    _replaceRow(_withResolution(row, resolution));
  }

  void _applySafeSuggestions() {
    final draft = _draft;
    if (draft == null) return;
    _replaceRows(<BankReconciliationRowDraft>[
      for (final row in draft.acceptableSuggestionRows)
        _withResolution(row, row.suggestion!.resolution!),
    ]);
  }

  Future<void> _analyzeWithAi({String? sourceRowId, String? answer}) async {
    final draft = _draft;
    final analyze = _actions.analyzeWithAi;
    if (draft == null ||
        analyze == null ||
        _analyzing ||
        _busy ||
        _applyReceipt != null) {
      return;
    }
    if (sourceRowId != null && answer != null) {
      _aiAnswers[sourceRowId] = answer.trim();
    }
    final requested = sourceRowId == null
        ? <String>{
            for (final row in draft.rowsAwaitingAiAnalysis)
              row.movement.sourceRowId,
          }
        : <String>{sourceRowId};
    if (requested.isEmpty) return;
    setState(() {
      _analyzing = true;
      _analyzingRowId = sourceRowId;
      _aiAnalyzed = 0;
      _aiRequested = requested.length;
      _error = null;
    });
    // Each batch shows up as soon as it is judged; the operator keeps
    // working meanwhile.
    void show(Map<String, BankAiAnalysis> analyses) {
      if (!mounted) return;
      final current = _draft;
      if (current == null) return;
      _replaceRows(<BankReconciliationRowDraft>[
        for (final entry in analyses.entries)
          if (current.rowsBySourceId[entry.key] case final row?)
            row.copyWith(aiAnalysis: entry.value),
      ]);
      setState(() => _aiAnalyzed = requested
          .where((id) => _draft?.rowsBySourceId[id]?.aiAnalysis != null)
          .length);
    }

    try {
      final analyses = await analyze(
        draft: draft,
        options: _workspaceOptions,
        answers: Map.of(_aiAnswers),
        rowIds: sourceRowId == null ? null : <String>{sourceRowId},
        onBatch: show,
      );
      show(analyses);
      if (!mounted) return;
      if (sourceRowId == null) {
        final unread = _aiRequested - _aiAnalyzed;
        if (_aiAnalyzed == 0) {
          setState(() => _error = 'La IA no encontró nada que decir sobre '
              'los movimientos pendientes.');
        } else if (unread > 0) {
          setState(() => _error = unread == 1
              ? 'La IA no alcanzó a responder sobre 1 movimiento. Puedes '
                  'analizarlo de nuevo.'
              : 'La IA no alcanzó a responder sobre $unread movimientos. '
                  'Puedes analizarlos de nuevo.');
        }
      }
    } on BankReconciliationServiceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'El análisis con IA no respondió. No se '
          'cambió nada: puedes intentar de nuevo.');
    } finally {
      if (mounted) {
        setState(() {
          _analyzing = false;
          _analyzingRowId = null;
        });
      }
    }
  }

  /// Takes the AI's proposal as the operator's decision, still editable.
  void _useAiProposal(String sourceRowId) {
    final row = _draft?.rowsBySourceId[sourceRowId];
    final analysis = row?.aiAnalysis;
    if (row == null || analysis == null) return;
    final proposal = analysis.proposal;
    if (proposal != null) {
      _setManualChoice(row, <BankReconciliationCandidate>[
        for (final allocation in proposal.allocations) allocation.candidate,
      ]);
      return;
    }
    final resolution = analysis.resolution;
    if (resolution != null) _replaceRow(_withResolution(row, resolution));
  }

  void _setAction(
    String sourceRowId,
    BankReconciliationActionKind action,
  ) {
    final draft = _draft;
    if (draft == null || _busy || _applyReceipt != null) return;
    final row = draft.rowsBySourceId[sourceRowId];
    if (row == null) return;
    final current = row.effectiveResolution;
    final suggested = row.suggestion?.resolution;
    if (suggested != null &&
        suggested.action == action &&
        (current.action != action ||
            action == BankReconciliationActionKind.payPayroll)) {
      _replaceRow(_withResolution(row, suggested));
      return;
    }
    // A salary is paid only as Nómina's owed line was matched to the row.
    if (action == BankReconciliationActionKind.payPayroll) return;
    final defaults = switch (action) {
      BankReconciliationActionKind.createExpense =>
        BankReconciliationResolutionDraft(
          action: action,
          paymentMethodId: _workspaceOptions?.paymentMethods.length == 1
              ? _workspaceOptions!.paymentMethods.single.paymentMethodId
              : current.paymentMethodId,
          description: current.description ?? row.movement.description,
          counterparty:
              current.counterparty ?? row.movement.counterpartyObserved,
          reference: current.reference ?? row.movement.documentNumber,
        ),
      BankReconciliationActionKind.classifyAccount =>
        BankReconciliationResolutionDraft(
          action: action,
          description: current.description ?? row.movement.description,
          reference: current.reference ?? row.movement.documentNumber,
        ),
      BankReconciliationActionKind.split => BankReconciliationResolutionDraft(
          action: action,
          paymentMethodId: _defaultBankMethodId() ?? current.paymentMethodId,
          reference: current.reference ?? row.movement.documentNumber,
          splitParts: BankSplitPartDraft.withRemainder(
            const <BankSplitPartDraft>[
              BankSplitPartDraft(),
              BankSplitPartDraft(),
            ],
            row.movement.amountClp ?? 0,
          ),
        ),
      _ => BankReconciliationResolutionDraft(action: action),
    };
    _replaceRow(
      row.copyWith(
        clearSelection:
            action != BankReconciliationActionKind.associateExisting,
        resolution: defaults,
        disposition: switch (action) {
          BankReconciliationActionKind.dismiss =>
            BankReconciliationDisposition.ignored,
          BankReconciliationActionKind.pending =>
            BankReconciliationDisposition.pending,
          _ => BankReconciliationDisposition.reconciled,
        },
      ),
    );
  }

  /// The transfer method of the bank account, or its only method.
  String? _defaultBankMethodId() {
    final methods = _workspaceOptions?.paymentMethods ?? const [];
    return (methods.where((method) => method.code == 'transfer').firstOrNull ??
            (methods.length == 1 ? methods.single : null))
        ?.paymentMethodId;
  }

  void _updateResolution(
    String sourceRowId,
    BankReconciliationResolutionDraft resolution,
  ) {
    final row = _draft?.rowsBySourceId[sourceRowId];
    if (row == null) return;
    _replaceRow(row.copyWith(resolution: resolution));
  }

  void _selectProposal(String sourceRowId, String proposalId) {
    final draft = _draft;
    final row = draft?.rowsBySourceId[sourceRowId];
    if (draft == null || row == null) return;
    final proposal = row.proposals
        .where((item) =>
            BankReconciliationRowDraft.proposalIdentity(item) == proposalId)
        .firstOrNull;
    if (proposal == null) return;
    final occupiedTargets = <String>{
      for (final otherRow in draft.rows)
        if (otherRow.movement.sourceRowId != sourceRowId)
          for (final allocation in otherRow.selectedProposal?.allocations ??
              const <BankReconciliationAllocationDraft>[])
            allocation.candidate.identity,
    };
    if (proposal.allocations.any(
      (allocation) => occupiedTargets.contains(allocation.candidate.identity),
    )) {
      setState(() {
        _error = 'La misma operación ERP no puede asociarse a dos '
            'movimientos de la cartola.';
      });
      return;
    }
    _replaceRow(
      row.copyWith(
        selectedProposalId: proposalId,
        resolution: const BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.associateExisting,
        ),
        disposition: BankReconciliationDisposition.reconciled,
      ),
    );
  }

  /// Adds an operation to the movement's manual choice: one transfer can
  /// pay several operations, and they must add up to it.
  void _selectManualCandidate(
    String sourceRowId,
    BankReconciliationCandidate candidate,
  ) {
    final row = _draft?.rowsBySourceId[sourceRowId];
    if (row == null) return;
    final current = row.selectedProposal;
    final chosen = <BankReconciliationCandidate>[
      if (current?.matchKind == BankReconciliationMatchKind.manual)
        for (final allocation in current!.allocations) allocation.candidate,
    ];
    if (chosen.any((item) => item.identity == candidate.identity)) return;
    _setManualChoice(row, <BankReconciliationCandidate>[...chosen, candidate]);
  }

  void _removeManualCandidate(String sourceRowId, String identity) {
    final row = _draft?.rowsBySourceId[sourceRowId];
    final current = row?.selectedProposal;
    if (row == null ||
        current == null ||
        current.matchKind != BankReconciliationMatchKind.manual) {
      return;
    }
    _setManualChoice(row, <BankReconciliationCandidate>[
      for (final allocation in current.allocations)
        if (allocation.candidate.identity != identity) allocation.candidate,
    ]);
  }

  void _setManualChoice(
    BankReconciliationRowDraft row,
    List<BankReconciliationCandidate> chosen,
  ) {
    final bankAmount = row.movement.amountClp;
    if (bankAmount == null) return;
    final withoutManual = <BankReconciliationProposal>[
      ...row.proposals.where(
        (item) => item.matchKind != BankReconciliationMatchKind.manual,
      ),
    ];
    if (chosen.isEmpty) {
      _replaceRow(row.copyWith(
        proposals: withoutManual,
        clearSelection: true,
        resolution: const BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.associateExisting,
        ),
      ));
      return;
    }
    final proposal = BankReconciliationProposal.manual(
      sourceRowId: row.movement.sourceRowId,
      movementAmountClp: bankAmount,
      candidates: chosen,
    );
    if (proposal == null) {
      setState(() {
        _error = 'Esas operaciones suman más que el movimiento del banco. '
            'Quita alguna antes de agregar otra.';
      });
      return;
    }
    _replaceRow(row.copyWith(proposals: <BankReconciliationProposal>[
      ...withoutManual,
      proposal,
    ]));
    _selectProposal(
      row.movement.sourceRowId,
      BankReconciliationRowDraft.proposalIdentity(proposal),
    );
  }

  Future<void> _saveReview() async {
    final draft = _draft;
    final accountId = _selectedAccountId;
    if (draft == null || accountId == null || _busy || _applyReceipt != null) {
      return;
    }
    if (_hasRepeatedErpTargets(draft)) {
      setState(() {
        _error = 'La misma operación ERP no puede asociarse a dos '
            'movimientos de la cartola.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final source in draft.sources) {
        final sha = source.fileSha256;
        if (_applyReceipts.containsKey(sha)) continue;
        final part = draft.forSource(source);
        // A statement whose open rows all stay pending has nothing to save;
        // what an earlier sitting applied is already there.
        final changes = part.rows.any((row) =>
            row.isSettled ? !row.settled!.sameStatement : row.isResolved);
        if (!changes) continue;
        var importReceipt = _importReceipts[sha];
        if (importReceipt == null) {
          importReceipt = await _actions.createImport(
            draft: part,
            erpAccountId: accountId,
            operationKey: _createOperationKeys.putIfAbsent(
              sha,
              () => UniqueKey().toString(),
            ),
          );
          if (!mounted) return;
          _importReceipts[sha] = importReceipt;
        }
        final receipt = await _actions.apply(
          draft: part,
          importReceipt: importReceipt,
          operationKey: _applyOperationKeys.putIfAbsent(
            sha,
            () => UniqueKey().toString(),
          ),
        );
        if (!mounted) return;
        _applyReceipts[sha] = receipt;
      }
      if (_applyReceipts.isEmpty) {
        setState(() => _error = 'No hay decisiones nuevas que aplicar.');
        return;
      }
      setState(() => _applyReceipt = _combinedReceipt());
    } on BankReconciliationServiceException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'No pudimos guardar la revisión. Puedes reintentar sin duplicar asociaciones.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  BankReconciliationApplyReceipt _combinedReceipt() {
    final receipts = _applyReceipts.values.toList(growable: false);
    final first = receipts.first;
    return BankReconciliationApplyReceipt(
      importId: first.importId,
      revision: first.revision,
      status: first.status,
      allocationCount:
          receipts.fold<int>(0, (sum, item) => sum + item.allocationCount),
      replayed: receipts.every((item) => item.replayed),
      createdExpenseCount:
          receipts.fold<int>(0, (sum, item) => sum + item.createdExpenseCount),
      createdJournalCount:
          receipts.fold<int>(0, (sum, item) => sum + item.createdJournalCount),
      payrollPaymentCount:
          receipts.fold<int>(0, (sum, item) => sum + item.payrollPaymentCount),
    );
  }

  List<BankReconciliationRowDraft> get _visibleRows {
    final rows = _draft?.rows ?? const <BankReconciliationRowDraft>[];
    return rows.where((row) {
      if (_filter != _MovementFilter.all && row.isSettled) return false;
      return switch (_filter) {
        _MovementFilter.all => true,
        _MovementFilter.open => !row.isResolved,
        _MovementFilter.ai => row.aiAnalysis != null,
        _MovementFilter.proposed => row.proposals.isNotEmpty,
        _MovementFilter.suggested =>
          row.proposals.isEmpty && row.suggestion != null,
        _MovementFilter.processor => row.proposals
            .any((proposal) => _isProcessorEstimate(proposal.matchKind)),
        _MovementFilter.unmatched => row.proposals.isEmpty,
      };
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Conciliación bancaria',
      compactHeader: const MainLayoutCompactHeader(
        title: 'Conciliación bancaria',
        contextLine: 'Contabilidad',
      ),
      body: Scaffold(
        body: Column(
          children: [
            _Header(
              accounts: _accounts,
              selectedAccountId: _selectedAccountId,
              loadingAccounts: _loadingAccounts,
              busy: _busy,
              hasDraft: _draft != null,
              onAccountChanged: (value) {
                if (_draft != null || value == null) return;
                setState(() => _selectedAccountId = value);
              },
              onPick: _selectedAccountId == null ? null : _pickStatement,
            ),
            Expanded(child: _buildBody()),
            if (_draft != null)
              _Footer(
                draft: _draft!,
                busy: _busy,
                applied: _applyReceipt != null,
                onSave: _saveReview,
                onReplace: _busy ? null : _reset,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loadingAccounts) {
      return const Center(
        child: BrandedLoading(size: 72, message: 'Cargando cuentas…'),
      );
    }
    if (_accounts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: VbNotice(
          title: 'Falta una cuenta bancaria activa',
          body:
              'Crea o activa una cuenta de banco en el plan de cuentas antes de importar una cartola.',
          tone: VbNoticeTone.warning,
        ),
      );
    }
    final draft = _draft;
    if (draft == null) {
      return _EmptyImportState(
        accountSelected: _selectedAccountId != null,
        busy: _busy,
        error: _error,
        onPick: _selectedAccountId == null ? null : _pickStatement,
      );
    }
    return Column(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: VbNotice(
              title: 'Revisa la conciliación',
              body: _error,
              tone: VbNoticeTone.danger,
            ),
          ),
        if (_applyReceipt != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: VbNotice(
              title: 'Conciliación guardada',
              body: _successMessage(_applyReceipt!),
              tone: VbNoticeTone.success,
            ),
          ),
        _ReviewToolbar(
          draft: draft,
          filter: _filter,
          enabled: !_busy && _applyReceipt == null,
          onFilterChanged: (value) => setState(() => _filter = value),
          onApplySuggestions: _applySafeSuggestions,
          analyzing: _analyzing && _analyzingRowId == null,
          analyzed: _aiAnalyzed,
          requested: _aiRequested,
          onAnalyze:
              _actions.analyzeWithAi == null ? null : () => _analyzeWithAi(),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop =
                  constraints.maxWidth >= ResponsiveBreakpoints.desktopMin;
              final selected = _selectedSourceRowId == null
                  ? null
                  : draft.rowsBySourceId[_selectedSourceRowId];
              final list = _MovementList(
                // Findings scroll with the rows instead of taking the height
                // the operator needs to review movements.
                leading: <Widget>[
                  if (draft.extractionWarnings.isNotEmpty)
                    VbNotice(
                      title: 'La lectura tiene observaciones',
                      body: draft.extractionWarnings.join(' '),
                      tone: VbNoticeTone.warning,
                      bodyMaxLines: 3,
                    ),
                  if (_applyReceipt == null)
                    _UnexplainedErpNotice(
                      operations: draft.unexplainedErpOperations(),
                    ),
                  if (_applyReceipt == null)
                    for (final insight in draft.insights)
                      VbNotice(
                        title: insight.title,
                        body: insight.body,
                        tone: insight.tone == BankInsightTone.warning
                            ? VbNoticeTone.warning
                            : VbNoticeTone.info,
                        bodyMaxLines: 3,
                      ),
                ],
                rows: _visibleRows,
                desktop: desktop,
                enabled: !_busy && _applyReceipt == null,
                selectedSourceRowId: _selectedSourceRowId,
                onResolve: (sourceRowId) {
                  setState(() => _selectedSourceRowId = sourceRowId);
                },
              );
              if (!desktop) {
                if (selected == null) return list;
                return _ResolutionPanel(
                  key: ValueKey(
                    'bank-reconciliation-resolution-${selected.movement.sourceRowId}',
                  ),
                  row: selected,
                  draft: draft,
                  options: _workspaceOptions,
                  loadingOptions: _loadingWorkspaceOptions,
                  enabled: !_busy && _applyReceipt == null,
                  compact: true,
                  onBack: () => setState(() => _selectedSourceRowId = null),
                  onAction: (action) =>
                      _setAction(selected.movement.sourceRowId, action),
                  onResolutionChanged: (resolution) => _updateResolution(
                    selected.movement.sourceRowId,
                    resolution,
                  ),
                  onProposalSelected: (proposalId) => _selectProposal(
                    selected.movement.sourceRowId,
                    proposalId,
                  ),
                  onCandidateSelected: (candidate) => _selectManualCandidate(
                    selected.movement.sourceRowId,
                    candidate,
                  ),
                  onCandidateRemoved: (identity) => _removeManualCandidate(
                    selected.movement.sourceRowId,
                    identity,
                  ),
                  onApplySuggestion: () =>
                      _applySuggestion(selected.movement.sourceRowId),
                  aiBusy: _analyzing &&
                      _analyzingRowId == selected.movement.sourceRowId,
                  onUseAi: () => _useAiProposal(selected.movement.sourceRowId),
                  aiRunning: _analyzing,
                  onAnalyzeAi: _actions.analyzeWithAi == null
                      ? null
                      : () => _analyzeWithAi(
                            sourceRowId: selected.movement.sourceRowId,
                          ),
                  onAnswerAi: _actions.analyzeWithAi == null
                      ? null
                      : (answer) => _analyzeWithAi(
                            sourceRowId: selected.movement.sourceRowId,
                            answer: answer,
                          ),
                );
              }
              return Row(
                // The resolver starts at the top, level with the list.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: list),
                  const VerticalDivider(width: 1),
                  Expanded(
                    flex: 2,
                    child: selected == null
                        ? const _ResolutionEmptyState()
                        : _ResolutionPanel(
                            key: ValueKey(
                              'bank-reconciliation-resolution-${selected.movement.sourceRowId}',
                            ),
                            row: selected,
                            draft: draft,
                            options: _workspaceOptions,
                            loadingOptions: _loadingWorkspaceOptions,
                            enabled: !_busy && _applyReceipt == null,
                            compact: false,
                            onBack: null,
                            onAction: (action) => _setAction(
                              selected.movement.sourceRowId,
                              action,
                            ),
                            onResolutionChanged: (resolution) =>
                                _updateResolution(
                              selected.movement.sourceRowId,
                              resolution,
                            ),
                            onProposalSelected: (proposalId) => _selectProposal(
                              selected.movement.sourceRowId,
                              proposalId,
                            ),
                            onCandidateSelected: (candidate) =>
                                _selectManualCandidate(
                              selected.movement.sourceRowId,
                              candidate,
                            ),
                            onCandidateRemoved: (identity) =>
                                _removeManualCandidate(
                              selected.movement.sourceRowId,
                              identity,
                            ),
                            onApplySuggestion: () => _applySuggestion(
                              selected.movement.sourceRowId,
                            ),
                            aiBusy: _analyzing &&
                                _analyzingRowId ==
                                    selected.movement.sourceRowId,
                            onUseAi: () =>
                                _useAiProposal(selected.movement.sourceRowId),
                            aiRunning: _analyzing,
                            onAnalyzeAi: _actions.analyzeWithAi == null
                                ? null
                                : () => _analyzeWithAi(
                                      sourceRowId:
                                          selected.movement.sourceRowId,
                                    ),
                            onAnswerAi: _actions.analyzeWithAi == null
                                ? null
                                : (answer) => _analyzeWithAi(
                                      sourceRowId:
                                          selected.movement.sourceRowId,
                                      answer: answer,
                                    ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  void _reset() {
    setState(() {
      _draft = null;
      _clearPersistence();
      _applyReceipt = null;
      _error = null;
      _filter = _MovementFilter.all;
      _workspaceOptions = null;
      _selectedSourceRowId = null;
    });
  }

  String _successMessage(BankReconciliationApplyReceipt receipt) {
    final effects = <String>[
      if (receipt.allocationCount > 0)
        '${receipt.allocationCount} vínculo(s) con operaciones existentes',
      if (receipt.createdExpenseCount > 0)
        '${receipt.createdExpenseCount} gasto(s) contabilizado(s)',
      if (receipt.createdJournalCount > 0)
        '${receipt.createdJournalCount} asiento(s) de clasificación',
      if (receipt.payrollPaymentCount > 0)
        '${receipt.payrollPaymentCount} sueldo(s) pagado(s) en Nómina',
    ];
    if (effects.isEmpty) {
      return 'Las decisiones quedaron guardadas. Los movimientos pendientes '
          'siguen disponibles para otra revisión.';
    }
    return '${effects.join(' · ')}. Todo quedó aplicado en una sola operación.';
  }
}

/// What the AI read in one movement, what it proposes, and a place to
/// answer its question: the answer goes back to the model for this movement.
class _AiAnalysisPanel extends StatefulWidget {
  const _AiAnalysisPanel({
    super.key,
    required this.analysis,
    required this.movement,
    required this.options,
    required this.enabled,
    required this.busy,
    required this.onUse,
    required this.onAnswer,
  });

  final BankAiAnalysis analysis;
  final BankStatementMovement movement;
  final BankReconciliationWorkspaceOptions? options;
  final bool enabled;
  final bool busy;
  final VoidCallback? onUse;
  final ValueChanged<String>? onAnswer;

  @override
  State<_AiAnalysisPanel> createState() => _AiAnalysisPanelState();
}

class _AiAnalysisPanelState extends State<_AiAnalysisPanel> {
  final _answer = TextEditingController();

  @override
  void initState() {
    super.initState();
    _answer.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  String? _proposalText() {
    final analysis = widget.analysis;
    final proposal = analysis.proposal;
    if (proposal != null) {
      return 'Vincular con ${proposal.allocations.map((item) => '${item.candidate.label} (${_money(item.candidate.amountClp)})').join(' + ')}';
    }
    final resolution = analysis.resolution;
    if (resolution == null) return null;
    final account = widget.options?.account(resolution.accountId)?.label;
    return switch (resolution.action) {
      BankReconciliationActionKind.createExpense =>
        'Registrar un gasto en ${account ?? 'la cuenta propuesta'}: '
            '${resolution.description ?? ''}',
      BankReconciliationActionKind.classifyAccount =>
        'Clasificar en ${account ?? 'la cuenta propuesta'}: '
            '${resolution.description ?? ''}',
      BankReconciliationActionKind.split =>
        'Dividir: ${resolution.splitParts.map((part) => '${part.description} ${_money(part.amountClp)}').join(' + ')}',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = widget.analysis;
    final id = widget.movement.sourceRowId;
    final proposal = _proposalText();
    final canAnswer = widget.onAnswer != null;
    return Column(
      key: ValueKey('bank-reconciliation-ai-panel-$id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Análisis con IA', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        VbNotice(
          title: analysis.explanation,
          body: <String>[
            if (analysis.missing != null) 'Podría faltar: ${analysis.missing}',
            if (proposal != null) 'Propone: $proposal',
            if (analysis.answer != null) 'Tu respuesta: ${analysis.answer}',
          ].join('\n'),
          tone: VbNoticeTone.info,
          action: analysis.hasProposal && widget.onUse != null
              ? FilledButton.tonal(
                  key: ValueKey('bank-reconciliation-ai-use-$id'),
                  onPressed: widget.enabled ? widget.onUse : null,
                  child: const Text('Usar propuesta'),
                )
              : null,
        ),
        if (analysis.question != null) ...[
          const SizedBox(height: 12),
          Text(analysis.question!, style: theme.textTheme.bodyMedium),
        ],
        if (canAnswer) ...[
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('bank-reconciliation-ai-answer-$id'),
            controller: _answer,
            enabled: widget.enabled && !widget.busy,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Tu respuesta',
              hintText: 'Cuéntale qué pasó con este movimiento…',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              key: ValueKey('bank-reconciliation-ai-reply-$id'),
              onPressed: widget.enabled &&
                      !widget.busy &&
                      _answer.text.trim().isNotEmpty
                  ? () => widget.onAnswer!(_answer.text)
                  : null,
              icon: const Icon(Icons.send_outlined),
              label: Text(widget.busy ? 'Analizando…' : 'Responder'),
            ),
          ),
        ],
      ],
    );
  }
}

/// What the ERP says went through the bank and the statements do not show.
class _UnexplainedErpNotice extends StatelessWidget {
  const _UnexplainedErpNotice({required this.operations});

  static const _shown = 8;

  final List<BankReconciliationCandidate> operations;

  @override
  Widget build(BuildContext context) {
    if (operations.isEmpty) return const SizedBox.shrink();
    final lines = <String>[
      for (final operation in operations.take(_shown))
        '${_dayMonth(operation.occurredOn)} · ${operation.label} · '
            '${_money(operation.amountClp)}'
            '${_who(operation).isEmpty ? '' : ' · ${_who(operation)}'}',
      if (operations.length > _shown) 'y ${operations.length - _shown} más',
    ];
    return VbNotice(
      key: const ValueKey('bank-reconciliation-unexplained-erp'),
      title: operations.length == 1
          ? '1 operación del ERP no aparece en la cartola'
          : '${operations.length} operaciones del ERP no aparecen en la cartola',
      body: 'El ERP las registra como pagadas o cobradas por esta cuenta y '
          'ningún movimiento las explica. Puede ser un pago hecho por otra '
          'persona, un medio de pago mal elegido o algo que no ocurrió.\n'
          '${lines.join('\n')}',
      tone: VbNoticeTone.warning,
      bodyMaxLines: lines.length + 3,
    );
  }
}

/// The person an operation names: the registered name over a generic
/// «Proveedor».
String _who(BankReconciliationCandidate operation) =>
    operation.counterpartyNames.isNotEmpty
        ? operation.counterpartyNames.first
        : operation.counterparty ?? '';

String _dayMonth(BankCivilDate date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}';

bool _hasRepeatedErpTargets(BankReconciliationPreparedDraft draft) {
  final seen = <String>{};
  for (final row in draft.rows) {
    for (final allocation in row.selectedProposal?.allocations ??
        const <BankReconciliationAllocationDraft>[]) {
      if (!seen.add(allocation.candidate.identity)) return true;
    }
  }
  return false;
}

class _Header extends StatelessWidget {
  const _Header({
    required this.accounts,
    required this.selectedAccountId,
    required this.loadingAccounts,
    required this.busy,
    required this.hasDraft,
    required this.onAccountChanged,
    required this.onPick,
  });

  final List<BankReconciliationAccountOption> accounts;
  final String? selectedAccountId;
  final bool loadingAccounts;
  final bool busy;
  final bool hasDraft;
  final ValueChanged<String?> onAccountChanged;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxWidth < ResponsiveBreakpoints.desktopMin;
            final phone = constraints.maxWidth < 600;
            final title = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Conciliación bancaria inteligente',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'La cartola propone vínculos; tú decides qué evidencia conservar.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            );
            final accountSelect = SizedBox(
              width: phone ? double.infinity : (compact ? 220 : 300),
              child: VbSearchableSelect<String>(
                value: selectedAccountId,
                options: [
                  for (final account in accounts)
                    VbSearchableSelectOption<String>(
                      value: account.accountId,
                      label: account.label,
                    ),
                ],
                onChanged: loadingAccounts || busy || hasDraft
                    ? null
                    : onAccountChanged,
                sheetTitle: 'Elegir cuenta bancaria',
                placeholder: loadingAccounts ? 'Cargando…' : 'Elegir cuenta',
                showLabel: false,
              ),
            );
            final importButton = FilledButton.icon(
              onPressed: busy || hasDraft ? null : onPick,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(busy ? 'Leyendo…' : 'Importar cartolas'),
            );
            final controls = phone
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      accountSelect,
                      const SizedBox(height: 8),
                      importButton,
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      accountSelect,
                      const SizedBox(width: 8),
                      importButton,
                    ],
                  );
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [title, const SizedBox(height: 12), controls],
              );
            }
            return Row(
              children: [Expanded(child: title), controls],
            );
          },
        ),
      ),
    );
  }
}

class _EmptyImportState extends StatelessWidget {
  const _EmptyImportState({
    required this.accountSelected,
    required this.busy,
    required this.error,
    required this.onPick,
  });

  final bool accountSelected;
  final bool busy;
  final String? error;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              if (error != null) ...[
                VbNotice(
                  title: 'No pudimos leer la cartola',
                  body: error,
                  tone: VbNoticeTone.danger,
                ),
                const SizedBox(height: 16),
              ],
              Icon(
                Icons.account_balance_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                accountSelected
                    ? 'Sube las cartolas de esta cuenta'
                    : 'Primero elige la cuenta bancaria',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Puedes elegir varios meses a la vez: se revisan juntos, así '
                'un pago que cruza de un mes al otro también calza. Guardamos '
                'los movimientos, nunca el archivo.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: busy ? null : onPick,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(busy ? 'Leyendo cartolas…' : 'Elegir archivos'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewToolbar extends StatelessWidget {
  const _ReviewToolbar({
    required this.draft,
    required this.filter,
    required this.enabled,
    required this.onFilterChanged,
    required this.onApplySuggestions,
    this.analyzing = false,
    this.analyzed = 0,
    this.requested = 0,
    this.onAnalyze,
  });

  final BankReconciliationPreparedDraft draft;
  final _MovementFilter filter;
  final bool enabled;
  final ValueChanged<_MovementFilter> onFilterChanged;
  final VoidCallback onApplySuggestions;
  final bool analyzing;

  /// Movements of the running analysis already answered, of [requested].
  final int analyzed;
  final int requested;
  final VoidCallback? onAnalyze;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final summary = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('${draft.movementCount} movimientos',
                style: Theme.of(context).textTheme.titleSmall),
            VbStatusBadge(
              label: '${draft.resolvedCount} decisiones listas',
              tone: VbStatusTone.success,
            ),
            VbStatusBadge(
              label: '${draft.pendingCount} pendientes',
              tone: VbStatusTone.info,
            ),
            if (draft.settledCount > 0)
              VbStatusBadge(
                label: '${draft.settledCount} ya conciliados',
                tone: VbStatusTone.neutral,
              ),
            if (draft.acceptableSuggestionRows.isNotEmpty)
              FilledButton.tonalIcon(
                key: const ValueKey('bank-reconciliation-accept-suggestions'),
                onPressed: enabled ? onApplySuggestions : null,
                icon: const Icon(Icons.done_all),
                label: Text(
                  draft.acceptableSuggestionRows.length == 1
                      ? 'Usar 1 sugerencia segura'
                      : 'Usar ${draft.acceptableSuggestionRows.length} '
                          'sugerencias seguras',
                ),
              ),
            if (onAnalyze != null &&
                (analyzing || draft.rowsAwaitingAiAnalysis.isNotEmpty))
              OutlinedButton.icon(
                key: const ValueKey('bank-reconciliation-analyze-ai'),
                onPressed: enabled && !analyzing ? onAnalyze : null,
                icon: const Icon(Icons.auto_awesome),
                label: Text(
                  analyzing
                      ? 'Analizando con IA… $analyzed de $requested'
                      : draft.rowsAwaitingAiAnalysis.length == 1
                          ? 'Analizar 1 pendiente con IA'
                          : 'Analizar ${draft.rowsAwaitingAiAnalysis.length} '
                              'pendientes con IA',
                ),
              ),
          ],
        );
        final filterSelect = SizedBox(
          width: 190,
          child: VbShortSelect<_MovementFilter>(
            value: filter,
            options: const [
              VbShortSelectOption(value: _MovementFilter.all, label: 'Todos'),
              VbShortSelectOption(
                  value: _MovementFilter.open, label: 'Por resolver'),
              VbShortSelectOption(
                  value: _MovementFilter.ai, label: 'Con análisis IA'),
              VbShortSelectOption(
                  value: _MovementFilter.proposed, label: 'Con propuesta'),
              VbShortSelectOption(
                  value: _MovementFilter.suggested, label: 'Con sugerencia'),
              VbShortSelectOption(
                  value: _MovementFilter.processor, label: 'Recaudadores'),
              VbShortSelectOption(
                  value: _MovementFilter.unmatched, label: 'Sin asociación'),
            ],
            onChanged: onFilterChanged,
            sheetTitle: 'Filtrar movimientos',
          ),
        );
        return Padding(
          padding: const EdgeInsets.all(16),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summary,
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: filterSelect,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: summary),
                    filterSelect,
                  ],
                ),
        );
      },
    );
  }
}

class _MovementList extends StatelessWidget {
  const _MovementList({
    this.leading = const <Widget>[],
    required this.rows,
    required this.desktop,
    required this.enabled,
    required this.selectedSourceRowId,
    required this.onResolve,
  });

  final List<Widget> leading;
  final List<BankReconciliationRowDraft> rows;
  final bool desktop;
  final bool enabled;
  final String? selectedSourceRowId;
  final ValueChanged<String> onResolve;

  @override
  Widget build(BuildContext context) {
    final header = desktop ? 1 : 0;
    return ListView.builder(
      key: const PageStorageKey('bank-reconciliation-rows'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: leading.length + header + rows.length,
      itemBuilder: (context, index) {
        if (index < leading.length) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: leading[index],
          );
        }
        final position = index - leading.length;
        if (desktop && position == 0) return const _ColumnHeader();
        final row = rows[position - header];
        return _MovementRow(
          key: ValueKey(
            'bank-reconciliation-row-${row.movement.sourceRowId}',
          ),
          row: row,
          desktop: desktop,
          selected: selectedSourceRowId == row.movement.sourceRowId,
          enabled: enabled,
          onResolve: () => onResolve(row.movement.sourceRowId),
        );
      },
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text('FECHA', style: style)),
          Expanded(flex: 4, child: Text('MOVIMIENTO EN CARTOLA', style: style)),
          SizedBox(
            width: 104,
            child: Text('MONTO', style: style, textAlign: TextAlign.right),
          ),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: Text('CALCE PROPUESTO', style: style)),
          SizedBox(width: 142, child: Text('RESOLUCIÓN', style: style)),
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({
    super.key,
    required this.row,
    required this.desktop,
    required this.selected,
    required this.enabled,
    required this.onResolve,
  });

  final BankReconciliationRowDraft row;
  final bool desktop;
  final bool selected;
  final bool enabled;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final movement = row.movement;
    final proposal = row.selectedProposal ?? row.proposals.firstOrNull;
    final action = TextButton.icon(
      key: ValueKey(
        'bank-reconciliation-resolve-${movement.sourceRowId}',
      ),
      onPressed: enabled || row.isSettled ? onResolve : null,
      icon: Icon(row.isSettled
          ? Icons.visibility_outlined
          : row.isResolved
              ? Icons.edit_outlined
              : Icons.tune),
      label: Text(row.isSettled
          ? 'Ver'
          : row.isResolved
              ? 'Editar decisión'
              : 'Resolver'),
    );
    final status = _ResolutionStatus(row: row);
    final content = desktop
        ? Row(
            children: [
              SizedBox(width: 72, child: Text(_date(movement.bookingDate))),
              Expanded(flex: 4, child: _MovementIdentity(movement: movement)),
              SizedBox(width: 104, child: VbMoneyText(movement.amountClp)),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: _ProposalSummary(proposal: proposal, row: row),
              ),
              SizedBox(
                width: 142,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [status, action],
                ),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(_date(movement.bookingDate),
                      style: theme.textTheme.labelSmall),
                  const Spacer(),
                  VbMoneyText(movement.amountClp),
                ],
              ),
              const SizedBox(height: 8),
              _MovementIdentity(movement: movement),
              const SizedBox(height: 12),
              _ProposalSummary(proposal: proposal, row: row),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [status, action],
              ),
            ],
          );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: selected ? theme.colorScheme.secondaryContainer : null,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: content,
      ),
    );
  }

  static String _date(BankCivilDate? date) {
    if (date == null) return 'Sin fecha';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}';
  }
}

class _ResolutionStatus extends StatelessWidget {
  const _ResolutionStatus({required this.row});

  final BankReconciliationRowDraft row;

  @override
  Widget build(BuildContext context) {
    final settled = row.settled;
    if (settled != null) {
      return VbStatusBadge(
        label: settled.excluded ? 'Ya excluido' : 'Ya conciliado',
        tone: VbStatusTone.neutral,
        dense: true,
      );
    }
    final (label, tone) = switch (row.effectiveResolution.action) {
      BankReconciliationActionKind.associateExisting when row.isResolved => (
          'Asociada',
          VbStatusTone.success
        ),
      BankReconciliationActionKind.createExpense when row.isResolved => (
          'Gasto listo',
          VbStatusTone.success
        ),
      BankReconciliationActionKind.classifyAccount when row.isResolved => (
          'Asiento listo',
          VbStatusTone.success
        ),
      BankReconciliationActionKind.dismiss when row.isResolved => (
          'Excluida',
          VbStatusTone.neutral
        ),
      BankReconciliationActionKind.payPayroll when row.isResolved => (
          'Sueldo listo',
          VbStatusTone.success
        ),
      BankReconciliationActionKind.split when row.isResolved => (
          'División lista',
          VbStatusTone.success
        ),
      _ => ('Pendiente', VbStatusTone.warning),
    };
    return VbStatusBadge(label: label, tone: tone, dense: true);
  }
}

class _MovementIdentity extends StatelessWidget {
  const _MovementIdentity({required this.movement});

  final BankStatementMovement movement;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(movement.description,
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            VbStatusBadge(
              label: movement.direction == BankMovementDirection.credit
                  ? 'Abono'
                  : movement.direction == BankMovementDirection.debit
                      ? 'Cargo'
                      : 'Dirección incierta',
              tone: movement.direction == BankMovementDirection.unknown
                  ? VbStatusTone.warning
                  : VbStatusTone.neutral,
              dense: true,
            ),
            if (!movement.isComplete)
              const VbStatusBadge(
                label: 'Lectura incompleta',
                tone: VbStatusTone.warning,
                dense: true,
              ),
          ],
        ),
      ],
    );
  }
}

class _ProposalSummary extends StatelessWidget {
  const _ProposalSummary({required this.proposal, required this.row});

  final BankReconciliationProposal? proposal;
  final BankReconciliationRowDraft row;

  @override
  Widget build(BuildContext context) {
    final value = proposal;
    final suggestion = row.suggestion;
    final settled = row.settled;
    if (settled != null) {
      return Text(
        settled.summary,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final ai = row.aiAnalysis;
    if (value == null && ai != null && !row.isResolved) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VbStatusBadge(
            label: ai.hasProposal ? 'IA propone' : 'IA pregunta',
            tone: VbStatusTone.info,
            dense: true,
          ),
          const SizedBox(height: 4),
          Text(
            ai.question ?? ai.explanation,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }
    if (value == null && suggestion != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              VbStatusBadge(
                label: suggestion.resolution == null
                    ? 'Por registrar'
                    : 'Sugerencia',
                tone: VbStatusTone.info,
                dense: true,
              ),
              Text(
                suggestion.title,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            <String>[
              ...suggestion.reasons,
              if (suggestion.followUp != null) suggestion.followUp!,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }
    if (value == null) {
      return Text('Sin operación existente candidata',
          style: Theme.of(context).textTheme.bodySmall);
    }
    final processor = _isProcessorEstimate(value.matchKind);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            VbStatusBadge(
              label: processor
                  ? 'Estimado · revisar'
                  : value.isSelectedByDefault
                      ? 'Directo incluido'
                      : 'Propuesta',
              tone: processor
                  ? VbStatusTone.info
                  : value.isSelectedByDefault
                      ? VbStatusTone.success
                      : VbStatusTone.warning,
              dense: true,
            ),
            Text(
              processor
                  ? '${value.allocations.length} ventas con tarjeta'
                  : value.allocations
                      .map((allocation) => allocation.candidate.label)
                      .join(' + '),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value.reasons.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ResolutionEmptyState extends StatelessWidget {
  const _ResolutionEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.rule_folder_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Elige un movimiento para resolverlo',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Podrás vincularlo, registrar el gasto, clasificarlo o excluirlo con una razón.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResolutionPanel extends StatelessWidget {
  const _ResolutionPanel({
    super.key,
    required this.row,
    required this.draft,
    required this.options,
    required this.loadingOptions,
    required this.enabled,
    required this.compact,
    required this.onBack,
    required this.onAction,
    required this.onResolutionChanged,
    required this.onProposalSelected,
    required this.onCandidateSelected,
    required this.onCandidateRemoved,
    required this.onApplySuggestion,
    this.aiBusy = false,
    this.aiRunning = false,
    this.onUseAi,
    this.onAnalyzeAi,
    this.onAnswerAi,
  });

  final BankReconciliationRowDraft row;
  final BankReconciliationPreparedDraft draft;
  final BankReconciliationWorkspaceOptions? options;

  /// The AI is reading this movement.
  final bool aiBusy;

  /// An analysis is running, of this movement or of the pending ones.
  final bool aiRunning;
  final VoidCallback? onUseAi;

  /// Asks the AI about this movement alone: one it has not read, such as a
  /// card deposit the bulk analysis leaves out.
  final VoidCallback? onAnalyzeAi;
  final ValueChanged<String>? onAnswerAi;
  final bool loadingOptions;
  final bool enabled;
  final bool compact;
  final VoidCallback? onBack;
  final ValueChanged<BankReconciliationActionKind> onAction;
  final ValueChanged<BankReconciliationResolutionDraft> onResolutionChanged;
  final ValueChanged<String> onProposalSelected;
  final ValueChanged<BankReconciliationCandidate> onCandidateSelected;
  final ValueChanged<String> onCandidateRemoved;
  final VoidCallback onApplySuggestion;

  @override
  Widget build(BuildContext context) {
    final movement = row.movement;
    final settled = row.settled;
    return Material(
      key: const ValueKey('bank-reconciliation-resolution-workspace'),
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        key: const PageStorageKey('bank-reconciliation-resolution-scroll'),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('bank-reconciliation-resolution-back'),
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Volver a movimientos'),
                ),
              ),
            Text(
              'Resolver movimiento',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              movement.description,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                VbStatusBadge(
                  label: movement.direction == BankMovementDirection.credit
                      ? 'Abono'
                      : 'Cargo',
                  tone: VbStatusTone.neutral,
                ),
                const Spacer(),
                VbMoneyText(movement.amountClp),
              ],
            ),
            const Divider(height: 32),
            if (settled != null)
              VbNotice(
                title: settled.sameStatement
                    ? 'Ya se aplicó en esta cartola'
                    : 'Ya está conciliado en otra cartola',
                body: '${settled.summary}.'
                    '${settled.decidedOn == null ? '' : ' Aplicado el ${_dayMonth(settled.decidedOn!)}.'}'
                    ' No se vuelve a tocar: '
                    '${settled.sameStatement ? 'lo que ya se aplicó queda firme.' : 'al aplicar ésta queda registrado como conciliado allá.'}',
                tone: VbNoticeTone.info,
              )
            else ...[
              if (row.aiAnalysis != null) ...[
                _AiAnalysisPanel(
                  key: ValueKey(
                    'bank-reconciliation-ai-${movement.sourceRowId}-'
                    '${row.aiAnalysis!.answer ?? ''}',
                  ),
                  analysis: row.aiAnalysis!,
                  movement: movement,
                  options: options,
                  enabled: enabled,
                  busy: aiBusy,
                  onUse: onUseAi,
                  onAnswer: onAnswerAi,
                ),
                const SizedBox(height: 20),
              ],
              if (row.suggestion != null && row.selectedProposal == null) ...[
                _SuggestionPanel(
                  suggestion: row.suggestion!,
                  applied: _suggestionApplied(row),
                  enabled: enabled,
                  onApply: onApplySuggestion,
                ),
                const SizedBox(height: 20),
              ],
              if (row.aiAnalysis == null &&
                  !row.isResolved &&
                  onAnalyzeAi != null) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: ValueKey(
                      'bank-reconciliation-ai-ask-${movement.sourceRowId}',
                    ),
                    onPressed: enabled && !aiRunning ? onAnalyzeAi : null,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      aiBusy ? 'Analizando con IA…' : 'Analizar con IA',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text('¿Qué corresponde hacer?',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _ActionChooser(
                value: row.effectiveResolution.action,
                movement: movement,
                payrollAvailable: row.suggestion?.resolution?.action ==
                    BankReconciliationActionKind.payPayroll,
                enabled: enabled,
                onChanged: onAction,
              ),
              const SizedBox(height: 20),
              if (loadingOptions)
                const BrandedLoading(
                  size: 48,
                  message: 'Cargando opciones contables…',
                )
              else
                switch (row.effectiveResolution.action) {
                  BankReconciliationActionKind.associateExisting =>
                    _ExistingOperationEditor(
                      row: row,
                      draft: draft,
                      enabled: enabled,
                      onProposalSelected: onProposalSelected,
                      onCandidateSelected: onCandidateSelected,
                      onCandidateRemoved: onCandidateRemoved,
                    ),
                  BankReconciliationActionKind.createExpense => _ExpenseEditor(
                      row: row,
                      options: options,
                      enabled: enabled,
                      onChanged: onResolutionChanged,
                    ),
                  BankReconciliationActionKind.classifyAccount =>
                    _JournalEditor(
                      row: row,
                      options: options,
                      enabled: enabled,
                      onChanged: onResolutionChanged,
                    ),
                  BankReconciliationActionKind.dismiss => _DismissEditor(
                      resolution: row.effectiveResolution,
                      enabled: enabled,
                      onChanged: onResolutionChanged,
                    ),
                  BankReconciliationActionKind.split => _SplitEditor(
                      row: row,
                      options: options,
                      enabled: enabled,
                      onChanged: onResolutionChanged,
                    ),
                  BankReconciliationActionKind.payPayroll =>
                    _PayrollPaymentSummary(
                      payroll: row.effectiveResolution.payroll,
                      movement: movement,
                    ),
                  BankReconciliationActionKind.pending => const VbNotice(
                      title: 'Quedará pendiente',
                      body:
                          'No se crea ningún asiento ni se marca como conciliado. Puedes resolverlo en otra revisión.',
                      tone: VbNoticeTone.info,
                    ),
                },
            ],
          ],
        ),
      ),
    );
  }
}

bool _suggestionApplied(BankReconciliationRowDraft row) {
  final suggested = row.suggestion?.resolution;
  final current = row.effectiveResolution;
  return suggested != null &&
      current.action == suggested.action &&
      current.accountId == suggested.accountId &&
      current.paymentMethodId == suggested.paymentMethodId &&
      current.reason == suggested.reason &&
      current.payroll?.lineId == suggested.payroll?.lineId;
}

/// What the ERP proposes for a movement no existing operation explains.
class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.suggestion,
    required this.applied,
    required this.enabled,
    required this.onApply,
  });

  final BankReconciliationSuggestion suggestion;
  final bool applied;
  final bool enabled;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final body = <String>[
      ...suggestion.reasons,
      if (suggestion.followUp != null) suggestion.followUp!,
    ].join('. ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VbNotice(
          title: suggestion.resolution == null
              ? 'Por registrar: ${suggestion.title}'
              : 'Sugerencia: ${suggestion.title}',
          body: body,
          tone: VbNoticeTone.info,
        ),
        if (suggestion.resolution != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const ValueKey('bank-reconciliation-use-suggestion'),
              onPressed: enabled && !applied ? onApply : null,
              icon: Icon(applied ? Icons.check : Icons.auto_fix_high_outlined),
              label: Text(applied ? 'Sugerencia aplicada' : 'Usar sugerencia'),
            ),
          ),
        ],
      ],
    );
  }
}

class _ActionChooser extends StatelessWidget {
  const _ActionChooser({
    required this.value,
    required this.movement,
    required this.payrollAvailable,
    required this.enabled,
    required this.onChanged,
  });

  final BankReconciliationActionKind value;
  final BankStatementMovement movement;

  /// Nómina owes a salary this transfer pays.
  final bool payrollAvailable;
  final bool enabled;
  final ValueChanged<BankReconciliationActionKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final choices = <(BankReconciliationActionKind, IconData, String)>[
      (
        BankReconciliationActionKind.associateExisting,
        Icons.link,
        'Vincular operación',
      ),
      if (payrollAvailable && movement.direction == BankMovementDirection.debit)
        (
          BankReconciliationActionKind.payPayroll,
          Icons.payments_outlined,
          'Pagar sueldo',
        ),
      if (movement.direction == BankMovementDirection.debit)
        (
          BankReconciliationActionKind.createExpense,
          Icons.receipt_long_outlined,
          'Crear gasto',
        ),
      (
        BankReconciliationActionKind.classifyAccount,
        Icons.account_tree_outlined,
        'Clasificar cuenta',
      ),
      (
        BankReconciliationActionKind.split,
        Icons.call_split,
        'Dividir',
      ),
      (
        BankReconciliationActionKind.dismiss,
        Icons.block_outlined,
        'Excluir',
      ),
      (
        BankReconciliationActionKind.pending,
        Icons.schedule_outlined,
        'Dejar pendiente',
      ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final choice in choices)
          if (value == choice.$1)
            FilledButton.tonalIcon(
              key: ValueKey('bank-reconciliation-action-${choice.$1.name}'),
              onPressed: enabled ? () => onChanged(choice.$1) : null,
              icon: Icon(choice.$2),
              label: Text(choice.$3),
            )
          else
            OutlinedButton.icon(
              key: ValueKey('bank-reconciliation-action-${choice.$1.name}'),
              onPressed: enabled ? () => onChanged(choice.$1) : null,
              icon: Icon(choice.$2),
              label: Text(choice.$3),
            ),
      ],
    );
  }
}

class _ExistingOperationEditor extends StatelessWidget {
  const _ExistingOperationEditor({
    required this.row,
    required this.draft,
    required this.enabled,
    required this.onProposalSelected,
    required this.onCandidateSelected,
    required this.onCandidateRemoved,
  });

  final BankReconciliationRowDraft row;
  final BankReconciliationPreparedDraft draft;
  final bool enabled;
  final ValueChanged<String> onProposalSelected;
  final ValueChanged<BankReconciliationCandidate> onCandidateSelected;
  final ValueChanged<String> onCandidateRemoved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final used = <String>{
      for (final other in draft.rows)
        if (other.movement.sourceRowId != row.movement.sourceRowId)
          for (final allocation in other.selectedProposal?.allocations ??
              const <BankReconciliationAllocationDraft>[])
            allocation.candidate.identity,
    };
    final selected = row.selectedProposal;
    final manual = selected?.matchKind == BankReconciliationMatchKind.manual
        ? selected
        : null;
    final chosen = <String>{
      for (final allocation
          in manual?.allocations ?? const <BankReconciliationAllocationDraft>[])
        allocation.candidate.identity,
    };
    final candidates = draft.candidateCatalog
        .where((candidate) =>
            candidate.direction == row.movement.direction &&
            !used.contains(candidate.identity) &&
            !chosen.contains(candidate.identity))
        .toList(growable: false);
    final suggested = row.proposals
        .where((proposal) =>
            proposal.matchKind != BankReconciliationMatchKind.manual)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Operaciones sugeridas', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (suggested.isEmpty)
          const VbNotice(
            title: 'No encontramos un calce directo',
            body:
                'Busca cualquier operación compatible del ERP o usa otra acción contable.',
            tone: VbNoticeTone.info,
          )
        else
          for (final proposal in suggested)
            _ProposalChoice(
              proposal: proposal,
              selected: BankReconciliationRowDraft.proposalIdentity(proposal) ==
                  row.selectedProposalId,
              enabled: enabled,
              onSelected: () => onProposalSelected(
                BankReconciliationRowDraft.proposalIdentity(proposal),
              ),
            ),
        const SizedBox(height: 16),
        if (manual != null) ...[
          Text('Elegidas por ti', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final allocation in manual.allocations)
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(allocation.candidate.label),
                      Text(
                        '${allocation.candidate.occurredOn} · '
                        '${_money(allocation.candidate.amountClp)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey(
                    'bank-reconciliation-manual-remove-'
                    '${allocation.candidate.identity}',
                  ),
                  tooltip: 'Quitar',
                  onPressed: enabled
                      ? () => onCandidateRemoved(allocation.candidate.identity)
                      : null,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          const SizedBox(height: 8),
          _ManualTotal(proposal: manual, movement: row.movement),
          const SizedBox(height: 16),
        ],
        VbSearchableSelect<String>(
          key: ValueKey(
            'bank-reconciliation-existing-search-${row.movement.sourceRowId}',
          ),
          value: null,
          options: [
            for (final candidate in candidates)
              VbSearchableSelectOption<String>(
                value: candidate.identity,
                label: candidate.label,
                context:
                    '${candidate.occurredOn} · ${_money(candidate.amountClp)}',
                searchText:
                    '${candidate.counterparty ?? ''} ${candidate.reference ?? ''}',
              ),
          ],
          onChanged: enabled
              ? (identity) {
                  if (identity == null) return;
                  final candidate = candidates
                      .where((item) => item.identity == identity)
                      .firstOrNull;
                  if (candidate != null) onCandidateSelected(candidate);
                }
              : null,
          sheetTitle: 'Buscar operación existente',
          label: manual == null
              ? 'Buscar otra operación del ERP'
              : 'Agregar otra operación',
          placeholder: 'Venta, compra, gasto, pago o asiento…',
          searchHint: 'Buscar por persona, documento o monto…',
        ),
        const SizedBox(height: 16),
        const VbNotice(
          title: 'Efecto contable',
          body:
              'Vincula evidencia bancaria a una o varias operaciones que ya existen. No crea ni repite pagos ni asientos.',
          tone: VbNoticeTone.info,
        ),
      ],
    );
  }
}

/// Whether the operations chosen by hand add up to the movement.
class _ManualTotal extends StatelessWidget {
  const _ManualTotal({required this.proposal, required this.movement});

  final BankReconciliationProposal proposal;
  final BankStatementMovement movement;

  @override
  Widget build(BuildContext context) {
    final amount = movement.amountClp ?? 0;
    final total = proposal.targetTotalClp;
    final difference = amount - total;
    final balanced =
        difference.abs() <= BankReconciliationProposal.manualToleranceClp;
    return VbNotice(
      key: const ValueKey('bank-reconciliation-manual-total'),
      title: difference == 0
          ? 'Suman lo mismo que el movimiento'
          : balanced
              ? 'Suman el movimiento con ${_money(difference.abs())} de diferencia'
              : difference > 0
                  ? 'Faltan ${_money(difference)}'
                  : 'Sobran ${_money(-difference)}',
      body: 'Operaciones: ${_money(total)} · Movimiento: ${_money(amount)}.'
          '${balanced ? '' : ' Una transferencia puede pagar varias operaciones: agrega las que faltan o quita las que sobran.'}',
      tone: balanced ? VbNoticeTone.success : VbNoticeTone.warning,
    );
  }
}

class _ProposalChoice extends StatelessWidget {
  const _ProposalChoice({
    required this.proposal,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final BankReconciliationProposal proposal;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final processor = _isProcessorEstimate(proposal.matchKind);
    final theme = Theme.of(context);
    return Card(
      key: ValueKey(
        'bank-reconciliation-proposal-${BankReconciliationRowDraft.proposalIdentity(proposal)}',
      ),
      elevation: 0,
      color: selected ? theme.colorScheme.secondaryContainer : null,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: enabled ? onSelected : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      processor
                          ? '${proposal.allocations.length} ventas del recaudador estimadas'
                          : proposal.allocations.first.candidate.label,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    if (processor) ...[
                      Text(
                        'Bruto ${_money(proposal.estimatedGrossClp)} − depósito '
                        '${_money(proposal.allocatedBankAmountClp)} = '
                        '${_money(proposal.estimatedDifferenceClp)} en comisiones y ajustes',
                      ),
                      const SizedBox(height: 4),
                      for (final allocation in proposal.allocations)
                        Text(
                          '${allocation.candidate.occurredOn} · '
                          '${allocation.candidate.label} · '
                          '${_money(allocation.candidate.amountClp)}',
                          style: theme.textTheme.bodySmall,
                        ),
                    ] else
                      Text(
                        '${proposal.allocations.first.candidate.occurredOn} · '
                        '${_money(proposal.allocations.first.candidate.amountClp)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      proposal.reasons.join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpenseEditor extends StatelessWidget {
  const _ExpenseEditor({
    required this.row,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final BankReconciliationRowDraft row;
  final BankReconciliationWorkspaceOptions? options;
  final bool enabled;
  final ValueChanged<BankReconciliationResolutionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final resolution = row.effectiveResolution;
    final expenseAccounts = options?.expenseAccounts ?? const [];
    final methods = options?.paymentMethods ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Registrar un gasto pagado',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey(
              'bank-reconciliation-expense-description-${row.movement.sourceRowId}'),
          initialValue: resolution.description,
          enabled: enabled,
          decoration: const InputDecoration(labelText: 'Descripción'),
          onChanged: (value) =>
              onChanged(resolution.copyWith(description: value)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: resolution.counterparty,
          enabled: enabled,
          decoration:
              const InputDecoration(labelText: 'Proveedor o contraparte'),
          onChanged: (value) =>
              onChanged(resolution.copyWith(counterparty: value)),
        ),
        const SizedBox(height: 12),
        VbSearchableSelect<String>(
          key: ValueKey(
              'bank-reconciliation-expense-account-${row.movement.sourceRowId}'),
          value: resolution.accountId,
          options: [
            for (final account in expenseAccounts)
              VbSearchableSelectOption<String>(
                value: account.accountId,
                label: account.label,
                context: 'Cuenta de gasto',
              ),
          ],
          onChanged: enabled
              ? (value) => onChanged(
                    resolution.copyWith(
                      accountId: value,
                      clearAccount: value == null,
                    ),
                  )
              : null,
          sheetTitle: 'Elegir cuenta de gasto',
          label: 'Cuenta de gasto o costo',
          placeholder: 'Elegir cuenta…',
        ),
        const SizedBox(height: 12),
        VbSearchableSelect<String>(
          key: ValueKey(
              'bank-reconciliation-expense-method-${row.movement.sourceRowId}'),
          value: resolution.paymentMethodId,
          options: [
            for (final method in methods)
              VbSearchableSelectOption<String>(
                value: method.paymentMethodId,
                label: method.name,
                context: 'Sale de la cuenta bancaria seleccionada',
                searchText: method.code,
              ),
          ],
          onChanged: enabled
              ? (value) => onChanged(
                    resolution.copyWith(
                      paymentMethodId: value,
                      clearPaymentMethod: value == null,
                    ),
                  )
              : null,
          sheetTitle: 'Elegir medio de pago',
          label: 'Medio de pago bancario',
          placeholder: 'Elegir medio…',
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: resolution.reference,
          enabled: enabled,
          decoration: const InputDecoration(labelText: 'Referencia opcional'),
          onChanged: (value) =>
              onChanged(resolution.copyWith(reference: value)),
        ),
        const SizedBox(height: 16),
        const VbNotice(
          title: 'Efecto contable',
          body:
              'Crea un gasto pagado y contabilizado en la fecha de la cartola: Debe gasto o costo / Haber banco. El movimiento queda vinculado al gasto nuevo.',
          tone: VbNoticeTone.info,
        ),
      ],
    );
  }
}

class _JournalEditor extends StatelessWidget {
  const _JournalEditor({
    required this.row,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final BankReconciliationRowDraft row;
  final BankReconciliationWorkspaceOptions? options;
  final bool enabled;
  final ValueChanged<BankReconciliationResolutionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final resolution = row.effectiveResolution;
    final accounts = options?.accounts ?? const [];
    final selectedAccount = accounts
        .where((account) => account.accountId == resolution.accountId)
        .firstOrNull;
    final isCredit = row.movement.direction == BankMovementDirection.credit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Clasificar en el libro contable',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        VbSearchableSelect<String>(
          key: ValueKey(
              'bank-reconciliation-journal-account-${row.movement.sourceRowId}'),
          value: resolution.accountId,
          options: [
            for (final account in accounts)
              VbSearchableSelectOption<String>(
                value: account.accountId,
                label: account.label,
                context: account.type,
                searchText: account.category,
              ),
          ],
          onChanged: enabled
              ? (value) => onChanged(
                    resolution.copyWith(
                      accountId: value,
                      clearAccount: value == null,
                    ),
                  )
              : null,
          sheetTitle: 'Elegir contrapartida',
          label: 'Cuenta de contrapartida',
          placeholder: 'Gasto, costo, ingreso, préstamo…',
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey(
              'bank-reconciliation-journal-description-${row.movement.sourceRowId}'),
          initialValue: resolution.description,
          enabled: enabled,
          decoration: const InputDecoration(labelText: 'Glosa contable'),
          onChanged: (value) =>
              onChanged(resolution.copyWith(description: value)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: resolution.reference,
          enabled: enabled,
          decoration: const InputDecoration(labelText: 'Referencia opcional'),
          onChanged: (value) =>
              onChanged(resolution.copyWith(reference: value)),
        ),
        const SizedBox(height: 16),
        VbNotice(
          title: 'Efecto contable',
          body: isCredit
              ? 'Genera un asiento contabilizado: Debe banco / Haber ${selectedAccount?.label ?? 'cuenta elegida'}. Úsalo para ingresos, aportes, devoluciones o préstamos.'
              : 'Genera un asiento contabilizado: Debe ${selectedAccount?.label ?? 'cuenta elegida'} / Haber banco. Úsalo cuando no corresponde crear un documento de gasto.',
          tone: VbNoticeTone.info,
        ),
      ],
    );
  }
}

/// One movement booked across several accounts: the parts the operator
/// knows (the accountant's fee, the licence) and a last one that takes what
/// is left (the F29).
class _SplitEditor extends StatelessWidget {
  const _SplitEditor({
    required this.row,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  static const _maxParts = 10;

  final BankReconciliationRowDraft row;
  final BankReconciliationWorkspaceOptions? options;
  final bool enabled;
  final ValueChanged<BankReconciliationResolutionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolution = row.effectiveResolution;
    final parts = resolution.splitParts;
    final amount = row.movement.amountClp ?? 0;
    final debit = row.movement.direction == BankMovementDirection.debit;
    final accounts = options?.accounts ?? const [];
    final suppliers = options?.suppliers ?? const [];
    final methods = options?.paymentMethods ?? const [];
    final id = row.movement.sourceRowId;

    void update(List<BankSplitPartDraft> next) => onChanged(
          resolution.copyWith(
            splitParts: BankSplitPartDraft.withRemainder(next, amount),
          ),
        );
    void replace(int index, BankSplitPartDraft part) => update(
          <BankSplitPartDraft>[
            for (var i = 0; i < parts.length; i++) i == index ? part : parts[i],
          ],
        );

    final expenseParts = parts.where((part) => part.isExpense).length;
    final journalParts = parts.length - expenseParts;
    final effects = <String>[
      if (expenseParts > 0)
        '$expenseParts gasto(s) pagado(s) con su proveedor y cuenta, en la '
            'fecha de la cartola',
      if (journalParts > 0)
        'un asiento contra el banco para '
            '${journalParts == 1 ? 'la otra parte' : 'las otras $journalParts partes'}',
    ].join(' y ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Dividir en varias cuentas', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Escribe el monto de cada parte que conoces; la última toma lo '
          'que queda del movimiento.',
          style: theme.textTheme.bodySmall,
        ),
        for (var index = 0; index < parts.length; index++) ...[
          const Divider(height: 24),
          Row(
            children: [
              Text('Parte ${index + 1}', style: theme.textTheme.labelLarge),
              const Spacer(),
              if (parts.length > 2)
                IconButton(
                  key: ValueKey('bank-reconciliation-split-remove-$id-$index'),
                  tooltip: 'Quitar parte',
                  onPressed: enabled
                      ? () => update(<BankSplitPartDraft>[
                            for (var i = 0; i < parts.length; i++)
                              if (i != index) parts[i],
                          ])
                      : null,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 8),
          VbSearchableSelect<String>(
            key: ValueKey('bank-reconciliation-split-account-$id-$index'),
            value: parts[index].accountId,
            options: [
              for (final account in accounts)
                VbSearchableSelectOption<String>(
                  value: account.accountId,
                  label: account.label,
                  context: account.canReceiveExpense && debit
                      ? 'Se registra como gasto pagado'
                      : 'Línea de asiento',
                  searchText: account.category,
                ),
            ],
            onChanged: enabled
                ? (value) {
                    final expense = debit &&
                        (options?.account(value)?.canReceiveExpense ?? false);
                    replace(
                      index,
                      parts[index].copyWith(
                        accountId: value,
                        isExpense: expense,
                        clearSupplier: !expense,
                      ),
                    );
                  }
                : null,
            sheetTitle: 'Elegir cuenta de esta parte',
            label: 'Cuenta',
            placeholder: 'Honorarios, patente, IVA…',
          ),
          if (parts[index].isExpense) ...[
            const SizedBox(height: 12),
            VbSearchableSelect<String>(
              key: ValueKey('bank-reconciliation-split-supplier-$id-$index'),
              value: parts[index].supplierId,
              options: [
                for (final supplier in suppliers)
                  VbSearchableSelectOption<String>(
                    value: supplier.supplierId,
                    label: supplier.name,
                  ),
              ],
              onChanged: enabled
                  ? (value) => replace(
                        index,
                        parts[index].copyWith(
                          supplierId: value,
                          clearSupplier: value == null,
                        ),
                      )
                  : null,
              sheetTitle: 'Elegir proveedor',
              label: 'Proveedor (opcional)',
              placeholder: 'A quién se le pagó…',
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            key: ValueKey(
              'bank-reconciliation-split-description-$id-$index-${parts.length}',
            ),
            initialValue: parts[index].description,
            enabled: enabled,
            decoration: const InputDecoration(labelText: 'Qué fue'),
            onChanged: (value) =>
                replace(index, parts[index].copyWith(description: value)),
          ),
          const SizedBox(height: 12),
          if (index < parts.length - 1)
            TextFormField(
              key: ValueKey(
                'bank-reconciliation-split-amount-$id-$index-${parts.length}',
              ),
              initialValue: parts[index].amountClp?.toString() ?? '',
              enabled: enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: '\$ ',
              ),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                replace(
                  index,
                  parts[index].copyWith(
                    amountClp: parsed,
                    clearAmount: parsed == null,
                  ),
                );
              },
            )
          else
            Text(
              parts[index].amountClp == null
                  ? 'Las otras partes ya suman el movimiento o más: no queda '
                      'nada para ésta.'
                  : 'Lo que queda: ${_money(parts[index].amountClp)}',
              key: ValueKey('bank-reconciliation-split-rest-$id'),
              style: theme.textTheme.bodyMedium,
            ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: ValueKey('bank-reconciliation-split-add-$id'),
            onPressed: enabled && parts.length < _maxParts
                ? () => update(<BankSplitPartDraft>[
                      ...parts.take(parts.length - 1),
                      const BankSplitPartDraft(),
                      parts.last,
                    ])
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Agregar parte'),
          ),
        ),
        if (expenseParts > 0) ...[
          const SizedBox(height: 12),
          VbSearchableSelect<String>(
            key: ValueKey('bank-reconciliation-split-method-$id'),
            value: resolution.paymentMethodId,
            options: [
              for (final method in methods)
                VbSearchableSelectOption<String>(
                  value: method.paymentMethodId,
                  label: method.name,
                  context: 'Sale de la cuenta bancaria seleccionada',
                  searchText: method.code,
                ),
            ],
            onChanged: enabled
                ? (value) => onChanged(
                      resolution.copyWith(
                        paymentMethodId: value,
                        clearPaymentMethod: value == null,
                      ),
                    )
                : null,
            sheetTitle: 'Elegir medio de pago',
            label: 'Medio de pago bancario de los gastos',
            placeholder: 'Elegir medio…',
          ),
        ],
        const SizedBox(height: 16),
        VbNotice(
          title: 'Efecto contable',
          body: 'Crea ${effects.isEmpty ? 'un asiento' : effects}. El '
              'movimiento queda explicado por todas las partes.',
          tone: VbNoticeTone.info,
        ),
      ],
    );
  }
}

/// What applying a [BankReconciliationActionKind.payPayroll] row does.
class _PayrollPaymentSummary extends StatelessWidget {
  const _PayrollPaymentSummary({
    required this.payroll,
    required this.movement,
  });

  final BankPayrollPaymentDraft? payroll;
  final BankStatementMovement movement;

  @override
  Widget build(BuildContext context) {
    final payroll = this.payroll;
    if (payroll == null) {
      return const VbNotice(
        title: 'Ningún sueldo de Nómina calza con esta transferencia',
        body: 'Elige otra acción o registra el pago en Nómina.',
        tone: VbNoticeTone.warning,
      );
    }
    final date = movement.bookingDate;
    final day = date == null
        ? ''
        : ' el ${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}';
    final owedAfter = payroll.owedAfterClp;
    return VbNotice(
      key: const ValueKey('bank-reconciliation-payroll-summary'),
      title: 'Se paga en Nómina al aplicar',
      body: <String>[
        '${payroll.employeeName} · ${payroll.voucherNumber} '
            '${payroll.periodLabel}: ${_money(payroll.amountClp)} desde esta '
            'cuenta$day.',
        for (final use in payroll.advances)
          'Descuenta el anticipo del '
              '${use.advance.paidOn.day.toString().padLeft(2, '0')}/'
              '${use.advance.paidOn.month.toString().padLeft(2, '0')}: '
              '${_money(use.amountClp)}.',
        if (payroll.confirmDraft)
          'La semana está en borrador: se confirma antes de pagar.',
        if (owedAfter > 0) 'Nómina le seguirá debiendo ${_money(owedAfter)}.',
        'La transferencia queda asociada a ese pago.',
      ].join(' '),
      tone: VbNoticeTone.info,
    );
  }
}

class _DismissEditor extends StatelessWidget {
  const _DismissEditor({
    required this.resolution,
    required this.enabled,
    required this.onChanged,
  });

  final BankReconciliationResolutionDraft resolution;
  final bool enabled;
  final ValueChanged<BankReconciliationResolutionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('bank-reconciliation-dismiss-reason'),
          initialValue: resolution.reason,
          enabled: enabled,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Motivo obligatorio',
            helperText: 'Ej.: movimiento duplicado en la cartola.',
          ),
          onChanged: (value) => onChanged(resolution.copyWith(reason: value)),
        ),
        const SizedBox(height: 16),
        const VbNotice(
          title: 'No se contabiliza ni se concilia',
          body:
              'El movimiento queda excluido con esta justificación. No se crea gasto, pago ni asiento.',
          tone: VbNoticeTone.warning,
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.draft,
    required this.busy,
    required this.applied,
    required this.onSave,
    required this.onReplace,
  });

  final BankReconciliationPreparedDraft draft;
  final bool busy;
  final bool applied;
  final VoidCallback onSave;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 600;
            final summary = Text(
              '${draft.resolvedCount} de ${draft.openCount} movimientos resueltos · '
              '${draft.pendingCount} quedan pendientes'
              '${draft.settledCount > 0 ? ' · ${draft.settledCount} ya conciliados' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            );
            final replaceButton = OutlinedButton(
              onPressed: onReplace,
              child: Text(
                draft.sources.length > 1
                    ? 'Cambiar cartolas'
                    : 'Cambiar cartola',
              ),
            );
            final saveButton = FilledButton.icon(
              key: const ValueKey('bank-reconciliation-save'),
              onPressed:
                  busy || applied || draft.resolvedCount == 0 ? null : onSave,
              icon: Icon(applied ? Icons.check : Icons.account_balance),
              label: Text(applied
                  ? 'Decisiones aplicadas'
                  : busy
                      ? 'Aplicando…'
                      : 'Aplicar ${draft.resolvedCount} decisiones'),
            );
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        summary,
                        const SizedBox(height: 8),
                        saveButton,
                        const SizedBox(height: 8),
                        replaceButton,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: summary),
                        const SizedBox(width: 8),
                        replaceButton,
                        const SizedBox(width: 8),
                        saveButton,
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

String _money(int? value) {
  if (value == null) return '—';
  final digits = value.abs().toString().replaceAllMapped(
        RegExp(r'(?<=\d)(?=(\d{3})+$)'),
        (_) => '.',
      );
  return '${value < 0 ? '-' : ''}\$$digits';
}
