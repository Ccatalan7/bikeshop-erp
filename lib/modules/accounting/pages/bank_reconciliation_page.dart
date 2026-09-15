import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
  required Uint8List bytes,
  required String filename,
  required String erpAccountId,
  String? sourcePath,
});

class BankReconciliationActions {
  const BankReconciliationActions({
    required this.loadBankAccounts,
    required this.loadWorkspaceOptions,
    required this.prepare,
    required this.createImport,
    required this.apply,
  });

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

enum _MovementFilter { all, proposed, processor, unmatched }

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
  BankStatementImportReceipt? _importReceipt;
  BankReconciliationApplyReceipt? _applyReceipt;
  _MovementFilter _filter = _MovementFilter.all;
  bool _loadingAccounts = true;
  bool _loadingWorkspaceOptions = false;
  bool _busy = false;
  String? _error;
  String? _createOperationKey;
  String? _applyOperationKey;

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
        required bytes,
        required filename,
        required erpAccountId,
        sourcePath,
      }) =>
          service.prepare(
        bytes: bytes,
        filename: filename,
        erpAccountId: erpAccountId,
        sourcePath: sourcePath,
      ),
      createImport: service.createImport,
      apply: service.apply,
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
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _applyReceipt = null;
    });
    try {
      final draft = await _actions.prepare(
        bytes: bytes,
        filename: file.name,
        erpAccountId: accountId,
        sourcePath: file.path,
      );
      if (!mounted) return;
      setState(() {
        _draft = draft;
        _importReceipt = null;
        _createOperationKey = null;
        _applyOperationKey = null;
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

  void _replaceRow(BankReconciliationRowDraft replacement) {
    final draft = _draft;
    if (draft == null || _busy || _applyReceipt != null) return;
    setState(() {
      _draft = draft.replaceRow(replacement);
      _error = null;
      _applyOperationKey = null;
    });
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

  void _selectManualCandidate(
    String sourceRowId,
    BankReconciliationCandidate candidate,
  ) {
    final row = _draft?.rowsBySourceId[sourceRowId];
    final bankAmount = row?.movement.amountClp;
    if (row == null || bankAmount == null) return;
    final proposal = BankReconciliationProposal(
      sourceRowId: sourceRowId,
      matchKind: BankReconciliationMatchKind.manual,
      confidence: BankReconciliationConfidence.medium,
      allocations: <BankReconciliationAllocationDraft>[
        BankReconciliationAllocationDraft(
          candidate: candidate,
          bankAmountClp: bankAmount,
        ),
      ],
      reasons: const <String>['Operación elegida manualmente'],
    );
    final proposals = <BankReconciliationProposal>[
      ...row.proposals.where((item) =>
          BankReconciliationRowDraft.proposalIdentity(item) !=
          BankReconciliationRowDraft.proposalIdentity(proposal)),
      proposal,
    ];
    _replaceRow(row.copyWith(proposals: proposals));
    _selectProposal(
      sourceRowId,
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
      var importReceipt = _importReceipt;
      if (importReceipt == null) {
        _createOperationKey ??= UniqueKey().toString();
        importReceipt = await _actions.createImport(
          draft: draft,
          erpAccountId: accountId,
          operationKey: _createOperationKey,
        );
        if (!mounted) return;
        setState(() => _importReceipt = importReceipt);
      }
      _applyOperationKey ??= UniqueKey().toString();
      final receipt = await _actions.apply(
        draft: draft,
        importReceipt: importReceipt,
        operationKey: _applyOperationKey,
      );
      if (!mounted) return;
      setState(() => _applyReceipt = receipt);
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

  List<BankReconciliationRowDraft> get _visibleRows {
    final rows = _draft?.rows ?? const <BankReconciliationRowDraft>[];
    return rows.where((row) {
      return switch (_filter) {
        _MovementFilter.all => true,
        _MovementFilter.proposed => row.proposals.isNotEmpty,
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
        if (draft.extractionWarnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: VbNotice(
              title: 'La lectura tiene observaciones',
              body: draft.extractionWarnings.first,
              tone: VbNoticeTone.warning,
            ),
          ),
        _ReviewToolbar(
          draft: draft,
          filter: _filter,
          onFilterChanged: (value) => setState(() => _filter = value),
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
                );
              }
              return Row(
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
      _importReceipt = null;
      _applyReceipt = null;
      _createOperationKey = null;
      _applyOperationKey = null;
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
    ];
    if (effects.isEmpty) {
      return 'Las decisiones quedaron guardadas. Los movimientos pendientes '
          'siguen disponibles para otra revisión.';
    }
    return '${effects.join(' · ')}. Todo quedó aplicado en una sola operación.';
  }
}

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
              label: Text(busy ? 'Leyendo…' : 'Importar cartola'),
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
                    ? 'Sube la cartola de esta cuenta'
                    : 'Primero elige la cuenta bancaria',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Veryfi y el parser de Banco de Chile trabajan en memoria. Guardamos movimientos estructurados y huellas, nunca el archivo ni el texto OCR completo.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: busy ? null : onPick,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(busy ? 'Leyendo cartola…' : 'Elegir archivo'),
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
    required this.onFilterChanged,
  });

  final BankReconciliationPreparedDraft draft;
  final _MovementFilter filter;
  final ValueChanged<_MovementFilter> onFilterChanged;

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
          ],
        );
        final filterSelect = SizedBox(
          width: 190,
          child: VbShortSelect<_MovementFilter>(
            value: filter,
            options: const [
              VbShortSelectOption(value: _MovementFilter.all, label: 'Todos'),
              VbShortSelectOption(
                  value: _MovementFilter.proposed, label: 'Con propuesta'),
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
    required this.rows,
    required this.desktop,
    required this.enabled,
    required this.selectedSourceRowId,
    required this.onResolve,
  });

  final List<BankReconciliationRowDraft> rows;
  final bool desktop;
  final bool enabled;
  final String? selectedSourceRowId;
  final ValueChanged<String> onResolve;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const PageStorageKey('bank-reconciliation-rows'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: rows.length + (desktop ? 1 : 0),
      itemBuilder: (context, index) {
        if (desktop && index == 0) return const _ColumnHeader();
        final row = rows[index - (desktop ? 1 : 0)];
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
          const SizedBox(width: 142, child: Text('RESOLUCIÓN')),
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
      onPressed: enabled ? onResolve : null,
      icon: Icon(row.isResolved ? Icons.edit_outlined : Icons.tune),
      label: Text(row.isResolved ? 'Editar decisión' : 'Resolver'),
    );
    final status = _ResolutionStatus(row: row);
    final content = desktop
        ? Row(
            children: [
              SizedBox(width: 72, child: Text(_date(movement.bookingDate))),
              Expanded(flex: 4, child: _MovementIdentity(movement: movement)),
              SizedBox(width: 104, child: VbMoneyText(movement.amountClp)),
              const SizedBox(width: 16),
              Expanded(flex: 3, child: _ProposalSummary(proposal: proposal)),
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
              _ProposalSummary(proposal: proposal),
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
  const _ProposalSummary({required this.proposal});

  final BankReconciliationProposal? proposal;

  @override
  Widget build(BuildContext context) {
    final value = proposal;
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
                  : value.allocations.first.candidate.label,
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
  });

  final BankReconciliationRowDraft row;
  final BankReconciliationPreparedDraft draft;
  final BankReconciliationWorkspaceOptions? options;
  final bool loadingOptions;
  final bool enabled;
  final bool compact;
  final VoidCallback? onBack;
  final ValueChanged<BankReconciliationActionKind> onAction;
  final ValueChanged<BankReconciliationResolutionDraft> onResolutionChanged;
  final ValueChanged<String> onProposalSelected;
  final ValueChanged<BankReconciliationCandidate> onCandidateSelected;

  @override
  Widget build(BuildContext context) {
    final movement = row.movement;
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
            Text('¿Qué corresponde hacer?',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _ActionChooser(
              value: row.effectiveResolution.action,
              movement: movement,
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
                  ),
                BankReconciliationActionKind.createExpense => _ExpenseEditor(
                    row: row,
                    options: options,
                    enabled: enabled,
                    onChanged: onResolutionChanged,
                  ),
                BankReconciliationActionKind.classifyAccount => _JournalEditor(
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
                BankReconciliationActionKind.pending => const VbNotice(
                    title: 'Quedará pendiente',
                    body:
                        'No se crea ningún asiento ni se marca como conciliado. Puedes resolverlo en otra revisión.',
                    tone: VbNoticeTone.info,
                  ),
              },
          ],
        ),
      ),
    );
  }
}

class _ActionChooser extends StatelessWidget {
  const _ActionChooser({
    required this.value,
    required this.movement,
    required this.enabled,
    required this.onChanged,
  });

  final BankReconciliationActionKind value;
  final BankStatementMovement movement;
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
  });

  final BankReconciliationRowDraft row;
  final BankReconciliationPreparedDraft draft;
  final bool enabled;
  final ValueChanged<String> onProposalSelected;
  final ValueChanged<BankReconciliationCandidate> onCandidateSelected;

  @override
  Widget build(BuildContext context) {
    final used = <String>{
      for (final other in draft.rows)
        if (other.movement.sourceRowId != row.movement.sourceRowId)
          for (final allocation in other.selectedProposal?.allocations ??
              const <BankReconciliationAllocationDraft>[])
            allocation.candidate.identity,
    };
    final candidates = draft.candidateCatalog
        .where((candidate) =>
            candidate.direction == row.movement.direction &&
            !used.contains(candidate.identity))
        .toList(growable: false);
    final selected = row.selectedProposal;
    final selectedManual =
        selected?.matchKind == BankReconciliationMatchKind.manual
            ? selected!.allocations.single.candidate.identity
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Operaciones sugeridas',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (row.proposals.isEmpty)
          const VbNotice(
            title: 'No encontramos un calce directo',
            body:
                'Busca cualquier operación compatible del ERP o usa otra acción contable.',
            tone: VbNoticeTone.info,
          )
        else
          for (final proposal in row.proposals)
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
        VbSearchableSelect<String>(
          key: ValueKey(
            'bank-reconciliation-existing-search-${row.movement.sourceRowId}',
          ),
          value: selectedManual,
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
          label: 'Buscar otra operación del ERP',
          placeholder: 'Venta, compra, gasto, pago o asiento…',
          searchHint: 'Buscar por persona, documento o monto…',
        ),
        const SizedBox(height: 16),
        const VbNotice(
          title: 'Efecto contable',
          body:
              'Vincula evidencia bancaria a una operación que ya existe. No crea ni repite pagos ni asientos.',
          tone: VbNoticeTone.info,
        ),
      ],
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
              '${draft.resolvedCount} de ${draft.movementCount} movimientos resueltos · '
              '${draft.pendingCount} quedan pendientes',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            );
            final replaceButton = OutlinedButton(
              onPressed: onReplace,
              child: const Text('Cambiar cartola'),
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
