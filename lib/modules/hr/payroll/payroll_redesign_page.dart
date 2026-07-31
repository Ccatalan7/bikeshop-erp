import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/current_user_profile_service.dart';
import '../../../shared/utils/responsive_viewport.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/workspace_shell_scope.dart';
import '../models/payroll_audit_read_models.dart';
import '../models/payroll_voucher.dart';
import '../services/payroll_voucher_service.dart';
import '../widgets/payroll_advance_entry.dart' show showPayrollAdvanceEntry;
import 'surfaces/payroll_accent_action.dart';
import 'surfaces/payroll_advances_and_cash_surfaces.dart';
import 'surfaces/payroll_history_surface.dart';
import 'surfaces/payroll_payment_composer.dart';
import 'surfaces/payroll_payment_evidence_surface.dart';
import 'surfaces/payroll_queue_surface.dart';
import 'theme/payroll_tokens.dart';

/// Host real del rediseño de Nóminas (handoff frames 2a–2e / 3a–3c).
///
/// Renderiza EXCLUSIVAMENTE las superficies nuevas del bundle; la capa visual
/// anterior (cola/tabla/sheet legacy) queda desconectada de esta ruta. Solo se
/// reutilizan modelos, servicios, autorización y callbacks lógicos.
class PayrollRedesignRoute extends StatefulWidget {
  const PayrollRedesignRoute({
    super.key,
    this.initialVoucherId,
  });

  final String? initialVoucherId;

  @override
  State<PayrollRedesignRoute> createState() => _PayrollRedesignRouteState();
}

class _PayrollRedesignRouteState extends State<PayrollRedesignRoute> {
  String? _compactContextLine;

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      title: 'Nóminas',
      compactHeader: MainLayoutCompactHeader(
        title: 'Nóminas',
        contextLine: _compactContextLine,
      ),
      child: PayrollRedesignPage(
        initialVoucherId: widget.initialVoucherId,
        onCompactContextChanged: (value) {
          if (!mounted || value == _compactContextLine) return;
          setState(() => _compactContextLine = value);
        },
      ),
    );
  }
}

class PayrollRedesignPage extends StatefulWidget {
  const PayrollRedesignPage({
    super.key,
    this.actions,
    this.initialVoucherId,
    this.onConfigureEmployeePaymentMethod,
    this.onCompactContextChanged,
  });

  /// Costura de inyección para tests.
  final PayrollRedesignActions? actions;

  /// Selección exacta entregada por el handoff desde Asistencias.
  final String? initialVoucherId;

  /// Test/integration seam for the canonical employee editor.
  ///
  /// Production pushes `/hr/employees/:id`, preserving Payroll underneath.
  final Future<void> Function(String employeeId)?
      onConfigureEmployeePaymentMethod;

  /// MainLayout owns the compact header; Payroll publishes only its live
  /// operational context (week, unresolved decisions and remaining balance).
  final ValueChanged<String?>? onCompactContextChanged;

  @override
  State<PayrollRedesignPage> createState() => _PayrollRedesignPageState();
}

/// Datos que la superficie necesita, cargados juntos.
@immutable
class PayrollRedesignData {
  const PayrollRedesignData({
    required this.vouchers,
    this.paymentMethods = const [],
    this.openAdvances = const [],
    this.employees = const [],
    this.versionedMutationsAvailable = true,
    this.historyNextCursor,
    this.historyHasMore = false,
  });

  final List<PayrollVoucher> vouchers;
  final List<Map<String, dynamic>> paymentMethods;
  final List<EmployeeAdvance> openAdvances;
  final List<Map<String, dynamic>> employees;
  final PayrollHistoryCursor? historyNextCursor;
  final bool historyHasMore;

  /// False when the server only exposes the legacy read contract.
  ///
  /// The page remains useful for review, but every command stays fail-closed
  /// until the atomic/versioned payroll migration is installed.
  final bool versionedMutationsAvailable;

  PayrollRedesignData copyWith({
    List<PayrollVoucher>? vouchers,
    List<Map<String, dynamic>>? paymentMethods,
    List<EmployeeAdvance>? openAdvances,
    List<Map<String, dynamic>>? employees,
    bool? versionedMutationsAvailable,
    PayrollHistoryCursor? historyNextCursor,
    bool clearHistoryNextCursor = false,
    bool? historyHasMore,
  }) {
    return PayrollRedesignData(
      vouchers: vouchers ?? this.vouchers,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      openAdvances: openAdvances ?? this.openAdvances,
      employees: employees ?? this.employees,
      versionedMutationsAvailable:
          versionedMutationsAvailable ?? this.versionedMutationsAvailable,
      historyNextCursor: clearHistoryNextCursor
          ? null
          : historyNextCursor ?? this.historyNextCursor,
      historyHasMore: historyHasMore ?? this.historyHasMore,
    );
  }
}

/// Comandos lógicos permitidos (idénticos a los del servicio existente).
@immutable
class PayrollRedesignActions {
  const PayrollRedesignActions({
    required this.load,
    required this.hydrateHistoryVoucher,
    required this.commitWeek,
    required this.payLine,
    required this.registerAdvance,
    this.excludeLine,
    this.journalEntriesForPayments,
    this.loadHistoryPage,
    this.loadHistoryVoucher,
    this.loadAdvanceLedgerPage,
    this.tenantCivilDateOf,
  });

  /// Saca una línea del borrador (`is_included = false`). No es una capacidad
  /// nueva: `updateLine` ya existe y ya rechaza semanas confirmadas. Lo que
  /// faltaba era ofrecerla donde el problema se ve.
  final Future<void> Function(String voucherId, String lineId)? excludeLine;

  /// Asientos contables por id de pago. Opcional: si falta, el respaldo
  /// simplemente no muestra el bloque en vez de inventarlo.
  final Future<Map<String, PayrollJournalEntry>> Function(List<String>)?
      journalEntriesForPayments;

  final Future<PayrollRedesignData> Function() load;
  final Future<PayrollVoucher> Function(PayrollVoucher voucher)
      hydrateHistoryVoucher;
  final Future<PayrollHistoryPage> Function({
    PayrollHistoryCursor? cursor,
  })? loadHistoryPage;
  final Future<PayrollVoucher?> Function(String voucherId)? loadHistoryVoucher;
  final Future<PayrollAdvanceLedgerPage?> Function({
    required String employeeId,
    PayrollAdvanceLedgerCursor? cursor,
  })? loadAdvanceLedgerPage;

  /// Resolves an instant to the tenant's civil date so the paginated ledger
  /// shows the same day as every other payroll reader regardless of the
  /// device timezone. Absent in injected test actions => device-local.
  final Future<DateTime> Function(DateTime instant)? tenantCivilDateOf;
  final Future<void> Function(String voucherId) commitWeek;
  final Future<void> Function({
    required String voucherId,
    required String lineId,
    required List<Map<String, dynamic>> splits,
    required String operationKey,
    required int expectedReconciliationVersion,
  }) payLine;
  final Future<void> Function({
    required String employeeId,
    required double amount,
    required String paymentMethodId,
    required String paymentAccountId,
    required DateTime paidAt,
    String? reference,
    String? notes,
    required String operationKey,
  }) registerAdvance;
}

@immutable
class _PayrollInitialHistoryLoad {
  const _PayrollInitialHistoryLoad({
    required this.vouchers,
    this.page,
  });

  final List<PayrollVoucher> vouchers;
  final PayrollHistoryPage? page;
}

enum _PayrollScope { weeks, history, advances }

enum _PayrollMobileUtility { reconcile, attendance }

class _PayrollRedesignPageState extends State<PayrollRedesignPage> {
  PayrollRedesignActions? _actions;
  PayrollRedesignData? _data;
  bool _isLoading = true;
  String? _error;
  bool _busy = false;
  bool _authoritativeReloadRequired = false;
  int _loadEpoch = 0;

  _PayrollScope _scope = _PayrollScope.weeks;
  String? _selectedVoucherId;
  String? _selectedHistoryVoucherId;
  String? _hydratingHistoryVoucherId;
  String? _historyHydrationError;
  final Set<String> _hydratedHistoryVoucherIds = <String>{};
  PayrollHistoryCursor? _historyNextCursor;
  bool _historyHasMore = false;
  bool _historyLoadingMore = false;
  String? _historyPaginationError;
  String? _expandedLineId;
  String? _selectedAdvanceEmployeeId;

  // Ledger paginado por persona (F4): el read model de auditoría es la
  // fuente cuando está instalado; el lector de saldos abiertos queda como
  // fallback honesto para un backend anterior a la paginación.
  String? _advanceLedgerEmployeeId;
  PayrollAdvanceLedgerTotals? _advanceLedgerTotals;
  final List<PayrollAdvanceLedgerEntry> _advanceLedgerEntries =
      <PayrollAdvanceLedgerEntry>[];
  PayrollAdvanceLedgerCursor? _advanceLedgerCursor;
  bool _advanceLedgerHasMore = false;
  bool _advanceLedgerLoading = false;
  bool _advanceLedgerLoadingMore = false;
  bool _advanceLedgerUnavailable = false;
  String? _advanceLedgerError;
  int _advanceLedgerEpoch = 0;
  // Ledger civil days keyed by entry id, resolved in the TENANT timezone so
  // the paginated reader shows the same day as every other payroll surface
  // (L-H3, Codex cross-review 2026-07-30). Absent key => device-local.
  final Map<String, DateTime> _advanceLedgerCivilDates = <String, DateTime>{};
  String? _lastCompactContextLine;

  static const List<String> _months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun', //
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  @override
  void initState() {
    super.initState();
    _selectedVoucherId = widget.initialVoucherId?.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(covariant PayrollRedesignPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextVoucherId = widget.initialVoucherId?.trim();
    if (nextVoucherId == null ||
        nextVoucherId.isEmpty ||
        nextVoucherId == oldWidget.initialVoucherId?.trim() ||
        nextVoucherId == _selectedVoucherId) {
      return;
    }
    _selectedVoucherId = nextVoucherId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  // ── Formatos (locales al host: sin dependencia visual legacy) ────────────

  static String _clp(num amount) {
    final rounded = amount.round();
    final negative = rounded < 0;
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return '${negative ? '−' : ''}\$$buffer';
  }

  static String _clpInput(num amount) =>
      _clp(amount).replaceFirst(RegExp(r'^[−-]?\$'), '');

  static double _parseClpInput(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(digits) ?? 0;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _range(DateTime start, DateTime end) {
    final endPart = '${_two(end.day)} ${_months[end.month - 1]}';
    if (start.month == end.month) return '${_two(start.day)} – $endPart';
    return '${_two(start.day)} ${_months[start.month - 1]} – $endPart';
  }

  static int _isoWeek(DateTime date) {
    // Aritmética en UTC: con fechas locales un cambio de hora dentro del año
    // acorta un día y corre TODA la numeración en −1 (visto en preview:
    // "Semana 26" para la semana real 27).
    final day = DateTime.utc(date.year, date.month, date.day);
    final thursday = day.add(Duration(days: 3 - ((day.weekday + 6) % 7)));
    final firstThursday = DateTime.utc(thursday.year, 1, 4);
    final firstWeekThursday = firstThursday
        .add(Duration(days: 3 - ((firstThursday.weekday + 6) % 7)));
    return 1 + thursday.difference(firstWeekThursday).inDays ~/ 7;
  }

  static String _initialsOf(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '·';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  /// Mounted visual vocabulary for every helper in this State. Local
  /// `final visual = …` declarations in inner builders shadow this getter
  /// harmlessly.
  PayrollVisualTokens get visual => PayrollVisualTokens.of(context);

  List<Color> get _avatarPalette => [
        visual.avatarSky,
        visual.avatarCyan,
        visual.avatarAmber,
      ];

  Color _avatarFor(String employeeId) =>
      _avatarPalette[employeeId.hashCode.abs() % _avatarPalette.length];

  // ── Datos ────────────────────────────────────────────────────────────────

  PayrollRedesignActions _resolveActions() {
    final injected = widget.actions;
    if (injected != null) return injected;
    return _actions ??= _providerActions(context.read<PayrollVoucherService>());
  }

  PayrollRedesignActions _providerActions(PayrollVoucherService service) {
    return PayrollRedesignActions(
      load: () async {
        final tenantId =
            context.read<CurrentUserProfileService>().profile?.tenantId.trim();
        if (tenantId == null || tenantId.isEmpty) {
          throw StateError(
            'Nóminas requiere un tenant autoritativo antes de cargar.',
          );
        }
        final openFuture = service.fetchOpenVouchers().then(
              service.hydrateOpenVoucherSettlements,
            );
        final historyFuture = () async {
          final page = await service.tryFetchPayrollHistoryPage();
          if (page == null) {
            return _PayrollInitialHistoryLoad(
              vouchers: await service.fetchLegacyHistoryVoucherHeaders(),
            );
          }
          return _PayrollInitialHistoryLoad(
            page: page,
            vouchers: page.items
                .map(
                  (header) => _voucherFromHistoryHeader(
                    header,
                    tenantId: tenantId,
                  ),
                )
                .toList(growable: false),
          );
        }();
        final methodsFuture = service.getPaymentMethods();
        final advancesFuture = service.getOpenEmployeeAdvances();
        final employeesFuture = service.getPayrollEmployees();
        final results = await Future.wait<Object?>(
          <Future<Object?>>[
            openFuture,
            historyFuture,
            methodsFuture,
            advancesFuture,
            employeesFuture,
          ],
          eagerError: true,
        );
        final open = results[0] as List<PayrollVoucher>;
        final history = results[1] as _PayrollInitialHistoryLoad;
        return PayrollRedesignData(
          vouchers: <PayrollVoucher>[...open, ...history.vouchers],
          paymentMethods: results[2] as List<Map<String, dynamic>>,
          openAdvances: results[3] as List<EmployeeAdvance>,
          employees: results[4] as List<Map<String, dynamic>>,
          versionedMutationsAvailable: service.supportsVersionedPayrollCommands,
          historyNextCursor: history.page?.nextCursor,
          historyHasMore: history.page?.hasMore ?? false,
        );
      },
      hydrateHistoryVoucher: service.hydrateVoucherSettlements,
      loadHistoryPage: ({cursor}) =>
          service.fetchPayrollHistoryPage(cursor: cursor),
      loadHistoryVoucher: service.fetchVoucherDetail,
      tenantCivilDateOf: service.tenantCivilDate,
      loadAdvanceLedgerPage: ({
        required employeeId,
        cursor,
      }) =>
          service.tryFetchEmployeeAdvanceLedgerPage(
        employeeId: employeeId,
        cursor: cursor,
      ),
      commitWeek: service.commitVoucher,
      payLine: ({
        required voucherId,
        required lineId,
        required splits,
        required operationKey,
        required expectedReconciliationVersion,
      }) =>
          service.payVoucher(
        voucherId,
        paymentSplits: <String, dynamic>{lineId: splits},
        operationKey: operationKey,
        expectedReconciliationVersion: expectedReconciliationVersion,
      ),
      journalEntriesForPayments: service.fetchJournalEntriesForPayments,
      excludeLine: (voucherId, lineId) async {
        final voucher = await service.getVoucher(voucherId);
        final line = voucher?.lines.firstWhere((l) => l.id == lineId);
        if (line == null) return;
        await service.updateLine(line.copyWith(isIncluded: false));
      },
      registerAdvance: ({
        required employeeId,
        required amount,
        required paymentMethodId,
        required paymentAccountId,
        required paidAt,
        reference,
        notes,
        required operationKey,
      }) =>
          service.registerEmployeeAdvance(
        employeeId: employeeId,
        amount: amount,
        paymentMethodId: paymentMethodId,
        paymentAccountId: paymentAccountId,
        paidAt: paidAt,
        reference: reference,
        notes: notes,
        operationKey: operationKey,
      ),
    );
  }

  static PayrollVoucher _voucherFromHistoryHeader(
    PayrollHistoryHeader header, {
    required String tenantId,
  }) {
    return PayrollVoucher(
      id: header.id,
      tenantId: tenantId,
      voucherNumber: header.voucherNumber,
      periodStart: header.periodStart,
      periodEnd: header.periodEnd,
      periodLabel: header.periodLabel,
      totalHours: header.totalHours,
      totalAmount: header.totalAmount,
      employeeCount: header.employeeCount,
      status: header.status == PayrollHistoryStatus.voided
          ? PayrollVoucherStatus.voided
          : PayrollVoucherStatus.paid,
      paidAt: header.paidAt,
      paidBy: header.paidBy.id,
      notes: header.notes,
      createdBy: header.createdBy.id,
      createdAt: header.createdAt,
      updatedAt: header.updatedAt,
      reconciliationVersion: header.reconciliationVersion,
    );
  }

  Future<bool> _load() async {
    if (!mounted) return false;
    final epoch = ++_loadEpoch;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await _resolveActions().load();
      if (!mounted || epoch != _loadEpoch) return false;
      final previouslySelectedId = _selectedVoucherId;
      final open = _openWeeks(data);
      final history = _historyWeeks(data);
      final selectedRemainsOpen = open.any(
        (voucher) => voucher.id != null && voucher.id == previouslySelectedId,
      );
      final selectedMovedToHistory = previouslySelectedId != null &&
          !selectedRemainsOpen &&
          history.any((voucher) => voucher.id == previouslySelectedId);
      setState(() {
        _data = data;
        _isLoading = false;
        _authoritativeReloadRequired = false;
        _hydratedHistoryVoucherIds.clear();
        _hydratingHistoryVoucherId = null;
        _historyHydrationError = null;
        _historyNextCursor = data.historyNextCursor;
        _historyHasMore = data.historyHasMore;
        _historyLoadingMore = false;
        _historyPaginationError = null;
        // An authoritative reload invalidates the per-person ledger cache and
        // re-probes availability on the next Anticipos build.
        _advanceLedgerEmployeeId = null;
        _advanceLedgerEntries.clear();
        _advanceLedgerTotals = null;
        _advanceLedgerCursor = null;
        _advanceLedgerHasMore = false;
        _advanceLedgerError = null;
        _advanceLedgerUnavailable = false;
        _advanceLedgerEpoch++;
        if (!selectedRemainsOpen) {
          _selectedVoucherId = open.isEmpty ? null : open.first.id;
        }
        final selectedHistoryStillExists = history.any(
          (voucher) =>
              voucher.id != null && voucher.id == _selectedHistoryVoucherId,
        );
        if (selectedMovedToHistory) {
          _scope = _PayrollScope.history;
          _selectedHistoryVoucherId = previouslySelectedId;
        } else if (!selectedHistoryStillExists) {
          _selectedHistoryVoucherId = history.isEmpty ? null : history.first.id;
        }
        if (_scope == _PayrollScope.weeks &&
            open.isEmpty &&
            history.isNotEmpty) {
          _scope = _PayrollScope.history;
        }
      });
      if (_scope == _PayrollScope.history) {
        await _hydrateSelectedHistory();
      }
      return true;
    } catch (error) {
      if (!mounted || epoch != _loadEpoch) return false;
      setState(() {
        _isLoading = false;
        _error = 'No pudimos cargar las semanas. Revisa la conexión y '
            'reintenta; el detalle técnico quedó en el registro.';
      });
      debugPrint('❌ [PayrollRedesign] load: $error');
      return false;
    }
  }

  bool _isOpen(PayrollVoucher v) =>
      v.status == PayrollVoucherStatus.draft ||
      v.status == PayrollVoucherStatus.confirmed ||
      v.status == PayrollVoucherStatus.partial;

  bool _isHistory(PayrollVoucher v) =>
      v.status == PayrollVoucherStatus.paid ||
      v.status == PayrollVoucherStatus.voided;

  List<PayrollVoucher> _openWeeks(PayrollRedesignData data) {
    final list = data.vouchers.where(_isOpen).toList(growable: false)
      ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
    return list;
  }

  List<PayrollVoucher> _historyWeeks(PayrollRedesignData data) {
    final list = data.vouchers.where(_isHistory).toList(growable: false)
      ..sort((a, b) {
        final byEnd = b.periodEnd.compareTo(a.periodEnd);
        if (byEnd != 0) return byEnd;
        return (b.id ?? '').compareTo(a.id ?? '');
      });
    return list;
  }

  PayrollVoucher? get _selected {
    final data = _data;
    if (data == null) return null;
    for (final v in data.vouchers) {
      if (v.id != null && v.id == _selectedVoucherId) return v;
    }
    final open = _openWeeks(data);
    return open.isEmpty ? null : open.first;
  }

  PayrollVoucher? get _selectedHistory {
    final data = _data;
    if (data == null) return null;
    final history = _historyWeeks(data);
    for (final voucher in history) {
      if (voucher.id != null && voucher.id == _selectedHistoryVoucherId) {
        return voucher;
      }
    }
    return history.isEmpty ? null : history.first;
  }

  Future<void> _selectHistoryVoucher(String? voucherId) async {
    if (voucherId == null) return;
    setState(() {
      _selectedHistoryVoucherId = voucherId;
      _historyHydrationError = null;
    });
    await _hydrateSelectedHistory();
  }

  Future<void> _showHistory() async {
    setState(() => _scope = _PayrollScope.history);
    await _hydrateSelectedHistory();
  }

  Future<void> _hydrateSelectedHistory() async {
    final voucher = _selectedHistory;
    final id = voucher?.id;
    if (voucher == null ||
        id == null ||
        _hydratedHistoryVoucherIds.contains(id) ||
        _hydratingHistoryVoucherId == id) {
      return;
    }
    final epoch = _loadEpoch;
    setState(() {
      _hydratingHistoryVoucherId = id;
      _historyHydrationError = null;
    });
    try {
      final actions = _resolveActions();
      final exactLoader = actions.loadHistoryVoucher;
      final hydrated = exactLoader == null
          ? await actions.hydrateHistoryVoucher(voucher)
          : await exactLoader(id);
      if (hydrated == null) {
        throw StateError('El comprobante histórico ya no está disponible.');
      }
      if (!mounted || epoch != _loadEpoch || _selectedHistoryVoucherId != id) {
        return;
      }
      final current = _data;
      if (current == null) return;
      final vouchers = <PayrollVoucher>[
        for (final candidate in current.vouchers)
          if (candidate.id == id) hydrated else candidate,
      ];
      setState(() {
        _data = current.copyWith(vouchers: vouchers);
        _hydratedHistoryVoucherIds.add(id);
        _hydratingHistoryVoucherId = null;
      });
    } catch (error) {
      if (!mounted || epoch != _loadEpoch || _selectedHistoryVoucherId != id) {
        return;
      }
      debugPrint('❌ [PayrollRedesign] historial $id: $error');
      setState(() {
        _hydratingHistoryVoucherId = null;
        _historyHydrationError =
            'No pudimos cargar los pagos registrados. Reintenta.';
      });
    }
  }

  Future<void> _loadMoreHistory() async {
    final action = _resolveActions().loadHistoryPage;
    final cursor = _historyNextCursor;
    if (action == null ||
        cursor == null ||
        !_historyHasMore ||
        _historyLoadingMore) {
      return;
    }
    final epoch = _loadEpoch;
    setState(() {
      _historyLoadingMore = true;
      _historyPaginationError = null;
    });
    try {
      final page = await action(cursor: cursor);
      if (!mounted || epoch != _loadEpoch) return;
      final current = _data;
      if (current == null) return;
      final tenantId =
          context.read<CurrentUserProfileService>().profile?.tenantId.trim();
      if (tenantId == null || tenantId.isEmpty) {
        throw StateError('No hay un tenant autoritativo para el historial.');
      }
      final knownIds = current.vouchers
          .map((voucher) => voucher.id)
          .whereType<String>()
          .toSet();
      final appended = <PayrollVoucher>[
        for (final header in page.items)
          if (knownIds.add(header.id))
            _voucherFromHistoryHeader(header, tenantId: tenantId),
      ];
      setState(() {
        _data = current.copyWith(
          vouchers: <PayrollVoucher>[...current.vouchers, ...appended],
          historyNextCursor: page.nextCursor,
          clearHistoryNextCursor: page.nextCursor == null,
          historyHasMore: page.hasMore,
        );
        _historyNextCursor = page.nextCursor;
        _historyHasMore = page.hasMore;
        _historyLoadingMore = false;
      });
    } catch (error) {
      if (!mounted || epoch != _loadEpoch) return;
      debugPrint('❌ [PayrollRedesign] más historial: $error');
      setState(() {
        _historyLoadingMore = false;
        _historyPaginationError = 'No pudimos cargar más semanas. Reintenta.';
      });
    }
  }

  double _pendingOf(PayrollVoucher v) => v.lines
      .where((l) => l.isIncluded)
      .fold<double>(0, (s, l) => s + l.balance);

  /// Cuánto de la semana ya está saldado, 0..1. Se mide contra el total de la
  /// semana, no contra las personas: dos sueldos chicos pagados no significan
  /// que la semana esté "casi lista".
  double? _settledFractionOf(PayrollVoucher v) {
    final total = v.lines
        .where((l) => l.isIncluded)
        .fold<double>(0, (s, l) => s + l.totalAmount);
    if (total <= 0.01) return null;
    return ((total - _pendingOf(v)) / total).clamp(0.0, 1.0);
  }

  /// La línea que dice qué falta. Es la diferencia entre una tira de montos y
  /// un panorama: sin esto hay que abrir cada semana para saber si hay trabajo.
  String? _weekFootnote(PayrollVoucher v, DateTime today) {
    final open = v.lines.where((l) => l.isIncluded && l.balance > 0.01).length;
    if (open > 0) {
      return open == 1 ? '1 persona por pagar' : '$open personas por pagar';
    }
    if (v.periodEnd.isAfter(today)) return 'la semana sigue corriendo';
    return 'todo pagado · falta confirmar';
  }

  List<EmployeeAdvance> _advancesFor(PayrollVoucher week, String employeeId) {
    final data = _data;
    if (data == null) return const [];
    final close = DateTime(
        week.periodEnd.year, week.periodEnd.month, week.periodEnd.day, 23, 59);
    final list = data.openAdvances
        .where((a) =>
            a.employeeId == employeeId &&
            a.availableAmount > 0.01 &&
            !a.paidCivilDate.isAfter(close))
        .toList(growable: false)
      ..sort((a, b) => a.paidCivilDate.compareTo(b.paidCivilDate));
    return list;
  }

  bool _isConfiguredPaymentMethod(Map<String, dynamic> method) {
    if (method['is_active'] == false) return false;
    final code = method['code']?.toString().trim().toLowerCase() ?? '';
    if (code != 'transfer' && code != 'cash') return false;
    return method['account_id']?.toString().trim().isNotEmpty == true;
  }

  Map<String, dynamic>? _configuredMethodById(String? id) {
    final normalized = id?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    for (final method
        in _data?.paymentMethods ?? const <Map<String, dynamic>>[]) {
      if (method['id']?.toString() == normalized &&
          _isConfiguredPaymentMethod(method)) {
        return method;
      }
    }
    return null;
  }

  String? _employeePreferredMethodId(String employeeId) {
    for (final employee in _data?.employees ?? const <Map<String, dynamic>>[]) {
      if (employee['id']?.toString() != employeeId) continue;
      final id = employee['preferred_payment_method_id']?.toString().trim();
      return id == null || id.isEmpty ? null : id;
    }
    return null;
  }

  /// Resolves only canonical, active and account-backed methods.
  ///
  /// A stale/missing line method may inherit the employee's persisted
  /// preference. The legacy free-text `paymentMethod` field is intentionally
  /// ignored: it must never turn an unknown method into Transferencia.
  Map<String, dynamic>? _resolvedMethodForLine(PayrollVoucherLine line) {
    return _configuredMethodById(line.paymentMethodId) ??
        _configuredMethodById(_employeePreferredMethodId(line.employeeId));
  }

  bool _requiresMethodConfiguration(PayrollVoucherLine line) =>
      line.balance > 0.01 && _resolvedMethodForLine(line) == null;

  /// Configura cómo se le paga a alguien y **vuelve a lo que se estaba
  /// haciendo**.
  ///
  /// 5g: «el retorno es el punto del flujo». Antes esto era un viaje de ida:
  /// se salía a la ficha del trabajador y se volvía a la tabla, con la fila
  /// perdida entre las demás y el pago sin empezar. Si se entró desde la
  /// intención de pagar, al volver se abre el composer de esa misma fila con
  /// el método ya resuelto.
  Future<void> _openEmployeePaymentMethod(
    PayrollVoucherLine line, {
    PayrollVoucher? resumePaymentFor,
  }) async {
    final employeeId = line.employeeId.trim();
    if (employeeId.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text('${line.employeeName} no tiene una ficha de trabajador '
            'válida para configurar su método de pago.'),
      ));
      return;
    }

    final injected = widget.onConfigureEmployeePaymentMethod;
    if (injected != null) {
      await injected(employeeId);
    } else {
      await context.push('/hr/employees/${Uri.encodeComponent(employeeId)}');
    }
    if (!mounted) return;
    await _load();
    if (!mounted || resumePaymentFor == null) return;

    // La semana y la línea se vuelven a buscar por id: `_load()` reemplazó
    // los objetos, y seguir con los viejos pagaría contra una versión que ya
    // no existe.
    final week = _voucherById(resumePaymentFor.id);
    final refreshed = week == null ? null : _lineById(week, line.id);
    if (week == null || refreshed == null) return;
    // Si el método sigue sin resolverse, no se abre nada: el composer sin
    // método vuelve a mandar acá y el operador queda en un círculo.
    if (_requiresMethodConfiguration(refreshed)) return;
    if (refreshed.balance <= 0.01) return;
    if (_statusOf(week, refreshed) == PayrollRowStatus.pendingCash) {
      await _openCash(week, refreshed);
    } else {
      await _openComposer(week, refreshed);
    }
  }

  PayrollVoucher? _voucherById(String? id) {
    if (id == null) return null;
    for (final voucher in _data?.vouchers ?? const <PayrollVoucher>[]) {
      if (voucher.id == id) return voucher;
    }
    return null;
  }

  PayrollVoucherLine? _lineById(PayrollVoucher week, String? lineId) {
    if (lineId == null) return null;
    for (final line in week.lines) {
      if (line.id == lineId) return line;
    }
    return null;
  }

  Map<String, dynamic>? _employeeRecord(String employeeId) {
    for (final e in _data?.employees ?? const <Map<String, dynamic>>[]) {
      if (e['id']?.toString() == employeeId) return e;
    }
    return null;
  }

  String _employeeName(String employeeId) {
    final employee = _employeeRecord(employeeId);
    if (employee == null) return 'Persona sin ficha';
    final displayName = employee['display_name']?.toString().trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    final name =
        '${employee['first_name'] ?? ''} ${employee['last_name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    return 'Persona sin ficha';
  }

  bool _employeeCanReceiveAdvance(String employeeId) {
    final employee = _employeeRecord(employeeId);
    if (employee == null || employee['is_active'] == false) return false;
    final status = employee['status']?.toString().trim().toLowerCase();
    return status == null || status.isEmpty || status == 'active';
  }

  // ── Comandos ─────────────────────────────────────────────────────────────

  bool get _versionedMutationsAvailable =>
      _data?.versionedMutationsAvailable == true;

  void _showVersionedUpdateRequired() {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      content: Text('Actualización de nóminas pendiente. Puedes revisar los '
          'saldos, pero confirmar, pagar, registrar anticipos o conciliar '
          'quedará disponible cuando se instale la actualización del servidor.'),
    ));
  }

  Future<bool> _run(Future<void> Function() command) async {
    if (_busy) return false;
    if (!_versionedMutationsAvailable) {
      _showVersionedUpdateRequired();
      return false;
    }
    if (_authoritativeReloadRequired) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('La vista necesita una recarga autoritativa antes de '
            'aceptar otro movimiento. Usa Reintentar y verifica el saldo.'),
      ));
      return false;
    }
    setState(() => _busy = true);
    try {
      await command();
      // A receipt confirms the command, but the old projection is not safe for
      // another mutation until a new authoritative read succeeds.
      _authoritativeReloadRequired = true;
      final refreshed = await _load();
      if (!refreshed && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('El servidor confirmó el movimiento, pero no pudimos '
              'actualizar la vista. No lo repitas hasta recargar y verificar '
              'el saldo.'),
        ));
      }
      return refreshed;
    } catch (error) {
      debugPrint('❌ [PayrollRedesign] comando: $error');
      // A transport failure may happen after the server committed. Fence every
      // repeat until an authoritative projection resolves that ambiguity.
      _authoritativeReloadRequired = true;
      if (mounted) {
        final refreshed = await _load();
        if (!mounted) return false;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('No pudimos verificar el movimiento. Revisa el saldo '
              'actualizado antes de decidir si corresponde repetirlo.'),
        ));
        if (!refreshed) {
          _authoritativeReloadRequired = true;
        }
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAttendances() async {
    await context.push('/hr/attendances');
    if (!mounted) return;
    await _load();
  }

  Future<void> _openReconciliation() async {
    // Navigation is never gated on the versioned backend: with the update
    // absent the reconciliation route opens as an honest read-only preview
    // (extract, match and review locally) and only import/apply stay
    // disabled there with the reason visible.
    await context.push('/hr/payroll/reconcile');
    if (!mounted) return;
    await _load();
  }

  Future<void> _newAdvance([String? initialEmployeeId]) async {
    final data = _data;
    if (data == null || _busy) return;
    if (!_versionedMutationsAvailable) {
      _showVersionedUpdateRequired();
      return;
    }
    // Inactive employees stay discoverable in the ledger by their true name,
    // but a NEW advance can only target someone who still works here.
    final selectableEmployees = data.employees.where((employee) {
      final id = employee['id']?.toString().trim() ?? '';
      return id.isNotEmpty && _employeeCanReceiveAdvance(id);
    }).toList(growable: false);
    final intent = await showPayrollAdvanceEntry(
      context: context,
      paymentMethods: data.paymentMethods,
      employees: selectableEmployees,
      initialEmployeeId: initialEmployeeId,
    );
    if (intent == null) return;
    final refreshed = await _run(() => _resolveActions().registerAdvance(
          employeeId: intent.employeeId,
          amount: intent.amount,
          paymentMethodId: intent.paymentMethodId,
          paymentAccountId: intent.paymentAccountId,
          paidAt: intent.paidAt,
          reference: intent.reference,
          notes: intent.notes,
          operationKey: intent.operationKey,
        ));
    if (!refreshed || !mounted) return;
    setState(() => _selectedAdvanceEmployeeId = intent.employeeId);
  }

  bool get _weekIsDraft => _selected?.status == PayrollVoucherStatus.draft;

  void _explainDraftGate() {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
      content: Text('Esta semana sigue en borrador: usa «Confirmar semana» '
          'para fijar las horas y habilitar los pagos.'),
    ));
  }

  Future<void> _commitWeek(PayrollVoucher week) async {
    final id = week.id;
    if (id == null || week.status != PayrollVoucherStatus.draft) return;

    // El alcance que se declara es el que se va a crear: una línea en $0 no
    // genera un sueldo por pagar, así que contarla inflaba la promesa.
    final included = week.lines
        .where((line) => line.isIncluded && line.totalAmount > 0.01)
        .toList();
    final total =
        included.fold<double>(0, (sum, line) => sum + line.totalAmount);
    final proceed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => Dialog(
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: visual.surface,
                  borderRadius: BorderRadius.circular(PayrollTokens.rSheet),
                  border: Border.all(color: visual.borderStrong),
                  boxShadow: visual.overlay,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '¿Confirmar esta semana?',
                        style: visual.sectionTitle,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Se crearán los sueldos por pagar de ${included.length} '
                        '${included.length == 1 ? 'persona' : 'personas'} por '
                        '${_clp(total)} y quedarán habilitados sus pagos.',
                        style: visual.bodyM,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: visual.surfaceSunken,
                          borderRadius:
                              BorderRadius.circular(PayrollTokens.rField),
                          border: Border.all(color: visual.border),
                        ),
                        child: Text(
                          'Las horas y tarifas vienen de Asistencias. Revisa '
                          'esos datos antes de continuar; una semana con pagos '
                          'registrados ya no puede volver a editarse.',
                          style: visual.bodyS,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Volver a revisar'),
                          ),
                          // accent-fill: dialog-action (resolver-owned M3 dialog grammar)
                          FilledButton(
                            key: const ValueKey(
                              'payroll-confirm-week-dialog-submit',
                            ),
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('Confirmar semana'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ) ??
        false;
    if (!proceed || !mounted) return;
    await _run(() => _resolveActions().commitWeek(id));
  }

  Future<void> _runNextWeekAction(PayrollVoucher week) async {
    if (week.status == PayrollVoucherStatus.draft) {
      await _commitWeek(week);
      return;
    }

    for (final line in week.lines.where((candidate) => candidate.isIncluded)) {
      if (line.balance <= 0.01) continue;
      if (_requiresMethodConfiguration(line)) {
        await _openEmployeePaymentMethod(line, resumePaymentFor: week);
        return;
      }
      if (!_versionedMutationsAvailable) {
        _showVersionedUpdateRequired();
        return;
      }
      if (_statusOf(week, line) == PayrollRowStatus.pendingCash) {
        await _openCash(week, line);
      } else {
        await _openComposer(week, line);
      }
      return;
    }
  }

  // ── VMs ──────────────────────────────────────────────────────────────────

  List<PayrollWeekCardVM> _weekCards(PayrollRedesignData data) {
    final open = _openWeeks(data);
    final today = DateTime.now();
    final selectedId = _selected?.id;
    String? oldestPendingId;
    for (final v in open) {
      if (_pendingOf(v) > 0.01 && v.periodEnd.isBefore(today)) {
        oldestPendingId = v.id;
        break;
      }
    }
    return [
      for (final v in open)
        PayrollWeekCardVM(
          name: 'Semana ${_isoWeek(v.periodStart)}',
          range: _range(v.periodStart, v.periodEnd),
          amountLabel: _clp(_pendingOf(v)),
          amountCaption: v.periodEnd.isAfter(today) ? 'acumulado' : 'por pagar',
          // "ABIERTA" y "EN COLA" eran el mismo hecho —no está pagada— con dos
          // nombres, y ninguno decía qué hacer: era el orden interno disfrazado
          // de estado. La etiqueta sólo aparece cuando dice algo que no se
          // puede deducir del monto ni del pie: si la semana todavía corre, o
          // si sigue en borrador (que es lo que realmente impide pagar).
          statusLabel: v.periodEnd.isAfter(today)
              ? 'EN CURSO'
              : v.status == PayrollVoucherStatus.draft
                  ? 'SIN CONFIRMAR'
                  : _pendingOf(v) <= 0.01
                      ? 'PAGADA'
                      : '',
          tone: v.id == oldestPendingId ? visual.warning : visual.neutral,
          selected: v.id == selectedId,
          settledFraction: _settledFractionOf(v),
          footnote: _weekFootnote(v, today),
          onTap: () => setState(() {
            _selectedVoucherId = v.id;
            _expandedLineId = null;
          }),
        ),
    ];
  }

  List<PayrollHistoryWeekVM> _historyCards(PayrollRedesignData data) {
    final selectedId = _selectedHistory?.id;
    return [
      for (final voucher in _historyWeeks(data))
        if (voucher.id != null)
          PayrollHistoryWeekVM(
            id: voucher.id!,
            title: 'Semana ${_isoWeek(voucher.periodStart)}',
            range: _range(voucher.periodStart, voucher.periodEnd),
            amount: _clp(voucher.totalAmount),
            status: voucher.status == PayrollVoucherStatus.voided
                ? 'ANULADA'
                : 'PAGADA',
            voided: voucher.status == PayrollVoucherStatus.voided,
            selected: voucher.id == selectedId,
            people: _historyPeopleLabel(voucher),
            // El historial hidrata sus líneas al abrirlas: hasta entonces el
            // saldo NO se conoce, y mostrar `$0` afirmaría que cerró bien una
            // semana que nadie ha mirado. Nulo es la respuesta honesta.
            balance:
                _historyIsHydrated(voucher) ? _clp(_pendingOf(voucher)) : null,
            settled: _pendingOf(voucher) <= 0.01,
          ),
    ];
  }

  bool _historyIsHydrated(PayrollVoucher voucher) => voucher.lines.isNotEmpty;

  String? _historyPeopleLabel(PayrollVoucher voucher) {
    final count = _historyIsHydrated(voucher)
        ? voucher.lines
            .where((l) => l.isIncluded && l.totalAmount > 0.01)
            .length
        : voucher.employeeCount;
    if (count <= 0) return null;
    return '$count ${count == 1 ? 'persona' : 'personas'}';
  }

  /// Cuántos pagos de la semana entraron a mano y cuántos por cartola.
  ///
  /// Los anticipos no cuentan: no son un pago de esta semana, son saldo
  /// consumido de otro momento.
  int _countPayments(
    List<PayrollVoucherLine> lines, {
    required bool fromStatement,
  }) {
    var count = 0;
    for (final line in lines) {
      for (final evidence in line.settlementEvidence) {
        if (evidence.isAdvance) continue;
        if (evidence.isFromStatement == fromStatement) count++;
      }
    }
    return count;
  }

  /// Nulo cuando no hay ningún pago: una nota de origen sin origen sobra.
  String? _paymentOriginNote(List<PayrollVoucherLine> lines) {
    final manual = _countPayments(lines, fromStatement: false);
    final statement = _countPayments(lines, fromStatement: true);
    if (manual + statement == 0) return null;
    return 'Origen de los pagos de esta semana';
  }

  PayrollHistoryDetailVM? _historyDetail(PayrollVoucher? voucher) {
    final id = voucher?.id;
    if (voucher == null || id == null) return null;
    final included = voucher.lines.where((line) => line.isIncluded).toList();
    final weekTotal =
        included.fold<double>(0, (sum, line) => sum + line.totalAmount);
    final paid = included.fold<double>(0, (sum, line) => sum + line.cashPaid);
    final advances =
        included.fold<double>(0, (sum, line) => sum + line.advancesApplied);
    final pending = included.fold<double>(0, (sum, line) => sum + line.balance);
    return PayrollHistoryDetailVM(
      id: id,
      title: 'Semana ${_isoWeek(voucher.periodStart)}',
      range: _range(voucher.periodStart, voucher.periodEnd),
      voucherNumber: voucher.voucherNumber,
      status:
          voucher.status == PayrollVoucherStatus.voided ? 'ANULADA' : 'PAGADA',
      voided: voucher.status == PayrollVoucherStatus.voided,
      weekTotal: _clp(weekTotal),
      // Los anticipos se leen como lo que son: plata que ya salió antes. El
      // signo evita tener que adivinar si suman o restan.
      advances: advances > 0.01 ? _clp(-advances) : '—',
      payable: _clp(weekTotal - advances),
      paid: paid > 0.01 ? _clp(paid) : '—',
      pending: _clp(pending),
      settled: pending <= 0.01,
      originNote: _paymentOriginNote(included),
      manualPayments: _countPayments(included, fromStatement: false),
      statementPayments: _countPayments(included, fromStatement: true),
      lines: [
        for (final line in included)
          PayrollHistoryLineVM(
            name: line.employeeName,
            weekTotal: _clp(line.totalAmount),
            // Un `$0` afirma un pago de cero; `—` dice que no hubo ninguno,
            // que es el hecho. Misma regla que la columna PAGADO de 5a.
            paid: line.cashPaid > 0.01 ? _clp(line.cashPaid) : '—',
            advances:
                line.advancesApplied > 0.01 ? _clp(-line.advancesApplied) : '—',
            pending: _clp(line.balance),
            initials: _initialsOf(line.employeeName),
            avatarColor: _avatarFor(line.employeeId),
            paymentCaption: _historyPaymentCaption(line),
            hasEvidence: line.settledAmount > 0.01,
            onOpenEvidence: line.settledAmount <= 0.01
                ? null
                : () => _openPaymentEvidence(voucher, line),
          ),
      ],
    );
  }

  Widget _buildHistory(PayrollRedesignData data, {required bool compact}) {
    final selected = _selectedHistory;
    final selectedId = selected?.id;
    return PayrollHistorySurface(
      weeks: _historyCards(data),
      detail: _historyDetail(selected),
      compact: compact,
      isHydrating:
          selectedId != null && _hydratingHistoryVoucherId == selectedId,
      authoritativeReady:
          selectedId != null && _hydratedHistoryVoucherIds.contains(selectedId),
      error: _historyHydrationError,
      onSelect: _selectHistoryVoucher,
      onRetry: _hydrateSelectedHistory,
      hasMore: _historyHasMore,
      isLoadingMore: _historyLoadingMore,
      paginationError: _historyPaginationError,
      onLoadMore: _loadMoreHistory,
    );
  }

  PayrollRowStatus _statusOf(PayrollVoucher week, PayrollVoucherLine line) {
    if (week.status == PayrollVoucherStatus.draft &&
        week.periodEnd.isAfter(DateTime.now())) {
      return PayrollRowStatus.openWeek;
    }
    // Deber $0 porque el total es $0 NO es haber pagado. Se veía "Pagado" en
    // verde sobre alguien que entró a la semana sin horas cerradas — la
    // pantalla afirmaba un pago que nunca ocurrió.
    if (line.totalAmount <= 0.01 && line.settledAmount <= 0.01) {
      return PayrollRowStatus.nothingToPay;
    }
    // Una semana en borrador no puede pagar a nadie: las horas todavía no
    // están fijas. Ofrecer "Pagar" aquí era mentir sobre lo que hace el botón,
    // porque en realidad abría el diálogo de confirmar la semana.
    if (week.status == PayrollVoucherStatus.draft && line.balance > 0.01) {
      return PayrollRowStatus.weekNotConfirmed;
    }
    if (line.balance <= 0.01) return PayrollRowStatus.paid;
    final method = _resolvedMethodForLine(line);
    final isCash =
        (method?['code']?.toString().trim().toLowerCase() ?? '') == 'cash';
    return isCash
        ? PayrollRowStatus.pendingCash
        : PayrollRowStatus.pendingTransfer;
  }

  /// How the money actually moved, in short bank language ("transferencia",
  /// "efectivo"). Historical rows show it under the dominant figure so the
  /// reader knows the channel without opening the evidence panel.
  String? _historyPaymentCaption(PayrollVoucherLine line) {
    if (line.settledAmount <= 0.01) return null;
    // Una semana puede quedar cubierta sin que se mueva dinero nuevo: si sólo
    // se imputó un anticipo, decirlo «efectivo» o «transferencia» sería
    // falso. La glosa nombra lo que realmente ocurrió.
    if (line.cashPaid <= 0.01 && line.advancesApplied > 0.01) {
      return 'cubierto con anticipo';
    }
    final method = _resolvedMethodForLine(line);
    final name = method?['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name.toLowerCase();
    final legacy = line.paymentMethod.trim();
    return legacy.isEmpty ? 'pago registrado' : legacy.toLowerCase();
  }

  String _methodLabel(PayrollVoucherLine line) {
    final method = _resolvedMethodForLine(line);
    return method?['name']?.toString() ??
        (line.balance > 0.01
            ? 'Configuración requerida'
            : 'Sin método registrado');
  }

  /// Cómo y cuándo se pagó, para la segunda línea del chip (`transf 14/07`).
  ///
  /// Dos filas «Pagado» son indistinguibles sin esto, y a 1116 el chip es el
  /// único lugar donde queda el dato: ahí la columna PAGADO se retira.
  String _decisionMetaFor(PayrollVoucherLine line, PayrollRowStatus status) {
    if (status != PayrollRowStatus.paid &&
        status != PayrollRowStatus.paidWithinTolerance) {
      return '';
    }
    final parts = <String>[];
    // Cubrir la semana con un anticipo no es transferir ni entregar efectivo:
    // decir «transf» ahí sería falso.
    if (line.cashPaid <= 0.01 && line.advancesApplied > 0.01) {
      parts.add('anticipo');
    } else {
      final code = _resolvedMethodForLine(line)?['code']
          ?.toString()
          .trim()
          .toLowerCase();
      parts.add(switch (code) {
        'cash' => 'efectivo',
        'transfer' => 'transf',
        _ => _methodLabel(line).toLowerCase(),
      });
    }
    final paidAt = _lastPaymentDate(line);
    if (paidAt != null) {
      parts.add('${_two(paidAt.day)}/${_two(paidAt.month)}');
    }
    return parts.join(' ');
  }

  DateTime? _lastPaymentDate(PayrollVoucherLine line) {
    DateTime? latest;
    for (final evidence in line.settlementEvidence) {
      if (evidence.isAdvance) continue;
      // La fecha del movimiento manda sobre la de registro: el chip cuenta
      // cuándo se pagó, no cuándo alguien lo tecleó.
      final at = evidence.cashMovementDate ??
          evidence.effectiveDate ??
          evidence.recordedAt;
      if (at == null) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    return latest;
  }

  /// La cuenta desde la que sale el dinero, tal como la nombra el banco.
  String? _bankAccountCaptionFor(PayrollVoucherLine line) {
    final method = _resolvedMethodForLine(line);
    if (method == null) return null;
    final name = method['account_name']?.toString().trim();
    if (name == null || name.isEmpty) return null;
    final code = method['account_code']?.toString().trim();
    return code == null || code.isEmpty ? name : '$name · $code';
  }

  /// Salidas de la fila abierta. Ninguna mueve dinero: son navegación, y por
  /// eso viven acá abajo y no compiten con la decisión de la fila.
  List<PayrollRowShortcutVM> _shortcutsFor(PayrollVoucherLine line) {
    return <PayrollRowShortcutVM>[
      // El anticipo nace con la persona ya elegida: se abre desde su fila.
      PayrollRowShortcutVM(
        label: 'Nuevo anticipo',
        onTap: () => _newAdvance(line.employeeId),
      ),
      PayrollRowShortcutVM(label: 'Ver historial', onTap: _showHistory),
      PayrollRowShortcutVM(
        label: 'Abrir en Asistencias',
        external: true,
        onTap: _openAttendances,
      ),
    ];
  }

  List<PayrollPersonRowVM> _personRows(PayrollVoucher week) {
    final rows = <PayrollPersonRowVM>[];
    for (final line in week.lines.where((l) => l.isIncluded)) {
      final status = _statusOf(week, line);
      final needsMethod = _requiresMethodConfiguration(line);
      // Only server-confirmed allocations are displayed as deducted. Open
      // advances remain available in the composer and start unselected.
      final appliedAdvance = line.advancesApplied;
      // `A PAGAR` es la obligación en dinero después de consumir anticipos,
      // NO el saldo pendiente. Con el saldo, una fila ya pagada mostraba `$0`
      // y la columna dejaba de sumar la aritmética del pie
      // (`total − anticipos − pagado`). Quien no tiene horas cerradas no
      // participa del cálculo, y su celda lo dice con un guion.
      final newMoney = status == PayrollRowStatus.nothingToPay
          ? '—'
          : _clp(line.totalAmount - appliedAdvance);
      final statusLabel = needsMethod
          ? 'Sin método'
          : !_versionedMutationsAvailable && line.balance > 0.01
              ? 'Actualización pendiente'
              : switch (status) {
                  PayrollRowStatus.paid => 'Pagado',
                  PayrollRowStatus.paidWithinTolerance => 'Pagado',
                  // Un solo estado para ambos métodos: desde el lado del
                  // dueño la intención es la misma, y separarlos obligaba a
                  // leer dos vocabularios en la misma columna.
                  PayrollRowStatus.pendingTransfer => 'Por pagar',
                  PayrollRowStatus.pendingCash => 'Por pagar',
                  PayrollRowStatus.openWeek => 'Semana en curso',
                  // No es «sin horas»: las horas existen, lo que falta es
                  // cerrarlas en Asistencias. Decir el hecho nombra la salida.
                  PayrollRowStatus.nothingToPay => 'Horas sin cerrar',
                  PayrollRowStatus.weekNotConfirmed => 'Falta confirmar',
                };
      final action = needsMethod
          ? 'Configurar método'
          : !_versionedMutationsAvailable && line.balance > 0.01
              ? ''
              : switch (status) {
                  PayrollRowStatus.paid ||
                  PayrollRowStatus.paidWithinTolerance =>
                    'Ver pago',
                  // Efectivo y transferencia comparten verbo: la intención del
                  // dueño es la misma. Lo que cambia es la evidencia —el banco
                  // no prueba un pago en efectivo— y eso se explica dentro del
                  // pago, no en el rótulo del botón.
                  PayrollRowStatus.pendingTransfer ||
                  PayrollRowStatus.pendingCash =>
                    'Pagar',
                  PayrollRowStatus.openWeek => '',
                  // Nóminas no cierra horas ni borra gente de la semana: la
                  // corrección vive en Asistencias, y la franja de arriba
                  // lleva ahí. Un botón acá sería una salida falsa —y una que
                  // escribe en producción por accidente.
                  PayrollRowStatus.nothingToPay => '',
                  // El único camino real es confirmar la semana, y ésa es la
                  // acción del pie. La fila no compite con ella.
                  PayrollRowStatus.weekNotConfirmed => '',
                };
      final actionMode = needsMethod
          ? PayrollRowActionMode.menu
          : !_versionedMutationsAvailable && line.balance > 0.01
              ? PayrollRowActionMode.none
              : switch (status) {
                  PayrollRowStatus.paid ||
                  PayrollRowStatus.paidWithinTolerance =>
                    PayrollRowActionMode.paidDetails,
                  PayrollRowStatus.pendingTransfer ||
                  PayrollRowStatus.pendingCash =>
                    PayrollRowActionMode.direct,
                  PayrollRowStatus.openWeek => PayrollRowActionMode.none,
                  PayrollRowStatus.nothingToPay => PayrollRowActionMode.none,
                  PayrollRowStatus.weekNotConfirmed =>
                    PayrollRowActionMode.none,
                };
      rows.add(PayrollPersonRowVM(
        name: line.employeeName,
        initials: _initialsOf(line.employeeName),
        avatarColor: _avatarFor(line.employeeId),
        method: _methodLabel(line),
        methodIsCash: status == PayrollRowStatus.pendingCash,
        earned: _clp(line.totalAmount),
        advances: appliedAdvance > 0.01 ? _clp(-appliedAdvance) : '—',
        newMoney: newMoney,
        paid: line.cashPaid > 0.01 ? _clp(line.cashPaid) : '—',
        status: status,
        statusLabel: statusLabel,
        statusMeta: _decisionMetaFor(line, status),
        actionLabel: action,
        actionMode: actionMode,
        hours: '${line.totalHours.toStringAsFixed(1).replaceAll('.', ',')} h',
        rate: '${_clp(line.hourlyRate)} / h',
        paymentsSummary: line.settledAmount > 0.01
            ? 'Pago registrado ${_clp(line.settledAmount)}'
            : 'Sin pagos registrados',
        bankAccountCaption: _bankAccountCaptionFor(line),
        shortcuts: _shortcutsFor(line),
        expanded: _expandedLineId == line.id,
        onToggle: () => setState(() {
          _expandedLineId = _expandedLineId == line.id ? null : line.id;
        }),
        onAction: () {
          if (needsMethod) {
            _openEmployeePaymentMethod(line, resumePaymentFor: week);
            return;
          }
          if (!_versionedMutationsAvailable && line.balance > 0.01) {
            _showVersionedUpdateRequired();
            return;
          }
          switch (status) {
            case PayrollRowStatus.paid:
            case PayrollRowStatus.paidWithinTolerance:
              _openPaymentEvidence(week, line);
            case PayrollRowStatus.pendingTransfer:
              if (_weekIsDraft) {
                _explainDraftGate();
              } else {
                _openComposer(week, line);
              }
            case PayrollRowStatus.pendingCash:
              if (_weekIsDraft) {
                _explainDraftGate();
              } else {
                _openCash(week, line);
              }
            case PayrollRowStatus.openWeek:
            case PayrollRowStatus.weekNotConfirmed:
            case PayrollRowStatus.nothingToPay:
              break;
          }
        },
      ));
    }
    return rows;
  }

  Future<void> _openPaymentEvidence(
    PayrollVoucher week,
    PayrollVoucherLine line,
  ) async {
    // El asiento REAL de cada pago, leído de journal_entries. Se pide acá y no
    // en la carga general porque sólo hace falta al abrir un respaldo.
    final journalByPayment =
        await _resolveActions().journalEntriesForPayments?.call(
                  line.settlementEvidence
                      .where((e) => !e.isAdvance)
                      .map((e) => e.id)
                      .toList(),
                ) ??
            const <String, PayrollJournalEntry>{};
    if (!mounted) return;

    String dateLabel(DateTime? value) {
      if (value == null) return 'Fecha no conservada';
      return '${_two(value.day)}/${_two(value.month)}/${value.year}';
    }

    String sourceLabel(PayrollSettlementEvidence evidence) =>
        switch (evidence.source) {
          PayrollSettlementEvidenceSource.manual =>
            'Registro manual de Nóminas',
          PayrollSettlementEvidenceSource.bankStatement =>
            'Cartola bancaria conciliada',
          PayrollSettlementEvidenceSource.cashReconciliation =>
            'Efectivo confirmado en conciliación',
          PayrollSettlementEvidenceSource.statementReconciliation =>
            'Conciliación de cartola',
          PayrollSettlementEvidenceSource.legacy => 'Historial anterior',
        };

    String? statementLocation(PayrollSettlementEvidence evidence) {
      if (!evidence.hasObservedStatementMetadata) return null;
      final parts = <String>[
        if (evidence.statementPageNumber != null)
          'Página ${evidence.statementPageNumber}',
        if (evidence.statementSourceLineStart != null &&
            evidence.statementSourceLineEnd != null)
          evidence.statementSourceLineStart == evidence.statementSourceLineEnd
              ? 'línea ${evidence.statementSourceLineStart}'
              : 'líneas ${evidence.statementSourceLineStart}'
                  '–${evidence.statementSourceLineEnd}'
        else if (evidence.statementSourceLineStart != null)
          'línea ${evidence.statementSourceLineStart}'
        else if (evidence.statementSourceLineEnd != null)
          'línea ${evidence.statementSourceLineEnd}',
        if (evidence.statementRowOrdinal != null)
          'fila OCR ${evidence.statementRowOrdinal}',
      ];
      return parts.isEmpty ? null : parts.join(' · ');
    }

    final entries = <PayrollPaymentEvidenceEntryVM>[
      for (final evidence in line.settlementEvidence)
        PayrollPaymentEvidenceEntryVM(
          id: evidence.id,
          kind: evidence.isAdvance ? 'Anticipo aplicado' : 'Pago registrado',
          amount: _clp(evidence.amount),
          date: dateLabel(evidence.effectiveDate ?? evidence.recordedAt),
          method: evidence.isAdvance
              ? 'Saldo de anticipo'
              : evidence.paymentMethodLabel ?? 'Método no conservado',
          account: evidence.paymentAccountLabel,
          // Un anticipo aplicado no mueve plata: sólo consume un saldo ya
          // entregado, así que no genera este asiento y decir que sí sería
          // falso. Sólo los pagos reales lo traen.
          // El asiento existe si hubo un pago real. Un anticipo aplicado NO
          // mueve plata —sólo consume un saldo ya entregado— así que pintarle
          // Debe/Haber afirmaría un movimiento que no ocurrió.
          hasAccountingEntry: !evidence.isAdvance,
          journalNumber: journalByPayment[evidence.id]?.entryNumber,
          journalLines: [
            for (final jl in journalByPayment[evidence.id]?.lines ??
                const <PayrollJournalLine>[])
              (
                '${jl.isDebit ? 'Debe' : 'Haber'} · ${jl.accountCode} ${jl.accountName}',
                _clp(jl.isDebit ? jl.debit : jl.credit),
              ),
          ],
          reference: evidence.reference?.trim().isNotEmpty == true
              ? evidence.reference!.trim()
              : evidence.isAdvance
                  ? 'Anticipo aplicado'
                  : 'Sin referencia',
          actor: evidence.actorName?.trim().isNotEmpty == true
              ? evidence.actorName!.trim()
              : 'Sin actor histórico',
          cashMovement: evidence.cashMovementDate == null
              ? null
              : '${dateLabel(evidence.cashMovementDate)}'
                  '${evidence.fundingActorName?.trim().isNotEmpty == true ? ' · ${evidence.fundingActorName!.trim()}' : ''}',
          source: sourceLabel(evidence),
          observedTransactionDate: !evidence.hasObservedStatementMetadata ||
                  evidence.statementTransactionDate == null
              ? null
              : dateLabel(evidence.statementTransactionDate),
          observedDescription: evidence.hasObservedStatementMetadata
              ? evidence.statementDescriptionObserved?.trim()
              : null,
          observedDocument: evidence.hasObservedStatementMetadata
              ? evidence.statementDocumentObserved?.trim()
              : null,
          observedLocation: statementLocation(evidence),
          variance: evidence.variance == null ||
                  evidence.variance!.abs() <= 0.01
              ? null
              : 'La cartola muestra ${_clp(evidence.bankAmount ?? 0)}; '
                  'se aplicaron ${_clp(evidence.amount)} '
                  '(${evidence.variance! > 0 ? '+' : ''}${_clp(evidence.variance!)} '
                  'de diferencia).',
        ),
    ];

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar respaldo de pago',
      barrierColor: visual.overlayVeil,
      transitionDuration: PayrollTokens.base,
      pageBuilder: (dialogContext, _, __) => Align(
        alignment: Alignment.centerRight,
        child: _adaptivePayrollPanel(
          dialogContext,
          desktopWidth: 520,
          background: visual.surfaceOverlay,
          child: PayrollPaymentEvidenceSurface(
            value: PayrollPaymentEvidenceVM(
              personName: line.employeeName,
              weekLabel: 'Semana ${_isoWeek(week.periodStart)} · '
                  '${_range(week.periodStart, week.periodEnd)}',
              total: _clp(line.totalAmount),
              newMoneyPaid: _clp(line.cashPaid),
              advancesApplied: _clp(line.advancesApplied),
              balance: _clp(line.balance),
              entries: entries,
            ),
            onClose: () => Navigator.of(dialogContext).pop(),
          ),
        ),
      ),
    );
  }

  /// Quienes entraron a la semana sin horas cerradas en Asistencias.
  ///
  /// No son deuda ni pago: son captura incompleta. Se nombran aparte para que
  /// nadie los busque en la aritmética, y la salida es cerrar sus horas, no
  /// borrarlos de la nómina.
  List<PayrollVoucherLine> _outsideCalculation(PayrollVoucher week) =>
      week.lines
          .where((l) => l.isIncluded && l.totalAmount <= 0.01)
          .toList(growable: false);

  /// `2 personas fuera del cálculo: Rocío y Ana · horas sin cerrar en
  /// Asistencias`. Nombra a quién, porque «alguien» no se puede arreglar.
  String? _excludedNote(PayrollVoucher week) {
    final excluded = _outsideCalculation(week);
    if (excluded.isEmpty) return null;
    final names = excluded
        .map((l) => l.employeeName.trim().split(RegExp(r'\s+')).first)
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    final who = switch (names.length) {
      0 => '',
      1 => ': ${names.first}',
      2 => ': ${names[0]} y ${names[1]}',
      // Más de dos nombres dejan de ser una lista y pasan a ser ruido: la
      // fila de cada uno los identifica.
      _ => '',
    };
    final count = excluded.length;
    return '$count ${count == 1 ? 'persona queda' : 'personas quedan'} fuera '
        'del cálculo$who · horas sin cerrar en Asistencias';
  }

  PayrollWeekTotalsVM _totals(PayrollVoucher week) {
    // Sumar filas de $0 no cambia el monto pero sí el conteo de personas, y
    // una semana decía «4 personas» cuando una de ellas no tenía nada que
    // cobrar. La aritmética del pie cuenta a quien participa de ella.
    final lines = week.lines.where((l) => l.isIncluded && l.totalAmount > 0.01);
    final earned = lines.fold<double>(0, (s, l) => s + l.totalAmount);
    final cashPaid = lines.fold<double>(0, (s, l) => s + l.cashPaid);
    final advancesApplied =
        lines.fold<double>(0, (s, l) => s + l.advancesApplied);
    final pending = lines.fold<double>(0, (s, l) => s + l.balance);
    final pendingCount = lines.where((l) => l.balance > 0.01).length;
    final isDraft = week.status == PayrollVoucherStatus.draft;
    final weekName = 'S${_isoWeek(week.periodStart)}';

    PayrollVoucherLine? firstPending;
    for (final l in lines) {
      if (l.balance > 0.01) {
        firstPending = l;
        break;
      }
    }
    final firstName = firstPending == null
        ? ''
        : firstPending.employeeName.trim().split(RegExp(r'\s+')).first;

    return PayrollWeekTotalsVM(
      title: 'Semana ${_isoWeek(week.periodStart)} · '
          '${_range(week.periodStart, week.periodEnd)}',
      equation: 'total ${_clp(earned)} − anticipos ${_clp(advancesApplied)} − '
          'pagado ${_clp(cashPaid)}',
      remaining: _clp(pending),
      showCommitAction: isDraft,
      canConfirm: isDraft && !_busy && _versionedMutationsAvailable,
      blockedReason: !_versionedMutationsAvailable
          ? 'Actualización de nóminas pendiente: esta vista queda en modo '
              'lectura hasta instalar los comandos versionados.'
          : isDraft
              ? 'Confirmar fija las horas, crea la deuda y habilita los pagos.'
              : pendingCount == 0
                  ? 'Todos los saldos están en \$0; la semana pasa a Pagada '
                      'automáticamente.'
                  : '$weekName pasa a Pagada automáticamente cuando '
                      '${pendingCount == 1 ? 'su saldo pendiente llegue' : 'sus $pendingCount saldos pendientes lleguen'} a \$0.',
      // Una sola acción primaria en la barra: en borrador el CTA es el propio
      // "Confirmar semana", por lo que la acción-siguiente queda vacía y la
      // superficie no la renderiza (nunca dos CTA idénticos).
      nextActionLabel: !_versionedMutationsAvailable || isDraft
          ? ''
          : firstPending == null
              ? ''
              : _requiresMethodConfiguration(firstPending)
                  ? 'Configurar método de $firstName'
                  : _statusOf(week, firstPending) ==
                          PayrollRowStatus.pendingCash
                      ? 'Confirmar efectivo'
                      : 'Pagar a $firstName',
    );
  }

  bool _sameCivilDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _adaptivePayrollPanel(
    BuildContext context, {
    required double desktopWidth,
    required Color background,
    required Widget child,
  }) {
    final media = MediaQuery.of(context);
    final compact = ResponsiveViewport.usesCompactShell(context);
    return SafeArea(
      child: AnimatedPadding(
        duration: PayrollTokens.fast,
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = compact || desktopWidth > constraints.maxWidth
                ? constraints.maxWidth
                : desktopWidth;
            // Un panel flotante necesita las cuatro cosas juntas: capa propia,
            // borde, sombra y el velo que va detrás. Antes era un `Material`
            // pelado pintado con `canvas` — que en oscuro ES el fondo de la
            // página, así que el panel no tenía límite alguno: flotaba sobre
            // un color idéntico al suyo. La sombra sola tampoco bastaba,
            // porque sin velo debajo no se ve.
            final radius = compact
                ? BorderRadius.zero
                : const BorderRadius.horizontal(left: Radius.circular(14));
            return Align(
              alignment:
                  compact ? Alignment.bottomCenter : Alignment.centerRight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  boxShadow: visual.overlay,
                ),
                child: Material(
                  color: background,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: radius,
                    side: BorderSide(color: visual.borderStrong),
                  ),
                  child: SizedBox(
                    width: width,
                    height: constraints.maxHeight,
                    child: child,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<bool> _confirmDiscardPaymentDraft(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => Dialog(
            backgroundColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: visual.surface,
                  borderRadius: BorderRadius.circular(PayrollTokens.rSheet),
                  border: Border.all(color: visual.borderStrong),
                  boxShadow: visual.overlay,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '¿Descartar los cambios?',
                        style: visual.sectionTitle,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'La fecha, referencia, monto o anticipos seleccionados '
                        'todavía no se han registrado.',
                        style: visual.bodyS,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Seguir editando'),
                          ),
                          const SizedBox(width: 8),
                          // accent-fill: dialog-action (resolver-owned M3 dialog grammar)
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('Descartar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  // ── Composer (2b) ────────────────────────────────────────────────────────

  Future<void> _openComposer(
      PayrollVoucher week, PayrollVoucherLine line) async {
    final data = _data;
    final lineId = line.id;
    final voucherId = week.id;
    if (data == null || lineId == null || voucherId == null) return;
    if (!_versionedMutationsAvailable) {
      _showVersionedUpdateRequired();
      return;
    }
    final resolvedMethod = _resolvedMethodForLine(line);
    if (resolvedMethod == null) {
      await _openEmployeePaymentMethod(line, resumePaymentFor: week);
      return;
    }
    final advances = _advancesFor(week, line.employeeId);
    // Availability is not application. Every composer starts with a deliberate
    // empty selection and only sends allocations the user checked now.
    final appliedIds = <String>{};
    var date = DateTime.now();
    final initialDate = date;
    var allowClose = false;
    final referenceController = TextEditingController();
    final amountController =
        TextEditingController(text: _clpInput(line.balance));
    var transferAmount = line.balance;
    final initialTransferAmount = transferAmount;
    final operationKey = const Uuid().v4();
    final vigente = advances.fold<double>(0, (s, a) => s + a.availableAmount);
    final resolvedCode =
        resolvedMethod['code']?.toString().trim().toLowerCase() ?? '';

    final familyCandidates = <Map<String, dynamic>>[];
    for (final candidate in data.paymentMethods) {
      if (!_isConfiguredPaymentMethod(candidate)) continue;
      final code = candidate['code']?.toString().trim().toLowerCase();
      // Cash confirmation is a separate, auditable workflow. A transfer
      // composer may choose another configured transfer account, but it must
      // never silently turn into a cash delivery.
      if (code != resolvedCode) continue;
      familyCandidates.add(candidate);
    }
    String baseLabelOf(Map<String, dynamic> candidate) {
      final name = candidate['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
      return resolvedCode == 'cash' ? 'Efectivo' : 'Transferencia';
    }

    final baseLabelCounts = <String, int>{};
    for (final candidate in familyCandidates) {
      final base = baseLabelOf(candidate);
      baseLabelCounts[base] = (baseLabelCounts[base] ?? 0) + 1;
    }
    final methodsByLabel = <String, Map<String, dynamic>>{};
    for (final candidate in familyCandidates) {
      final base = baseLabelOf(candidate);
      var label = base;
      if (baseLabelCounts[base]! > 1) {
        // Registered contract: duplicate method names identify their
        // accounting account; a positional or numeric suffix is not an
        // identity.
        final accountCode = candidate['account_code']?.toString().trim();
        final accountName = candidate['account_name']?.toString().trim();
        final identity = <String>[
          if (accountCode != null && accountCode.isNotEmpty) accountCode,
          if (accountName != null && accountName.isNotEmpty) accountName,
        ].join(' · ');
        if (identity.isNotEmpty) label = '$base · $identity';
      }
      var suffix = 2;
      while (methodsByLabel.containsKey(label)) {
        label = '$base ($suffix)';
        suffix += 1;
      }
      methodsByLabel[label] = candidate;
    }
    final resolvedId = resolvedMethod['id']?.toString();
    final initialMethod = methodsByLabel.entries
        .where((entry) => entry.value['id']?.toString() == resolvedId)
        .map((entry) => entry.key)
        .firstOrNull;
    if (initialMethod == null) {
      await _openEmployeePaymentMethod(line);
      return;
    }
    var method = initialMethod;
    final availableMethods = methodsByLabel.keys.toList(growable: false);

    double maximumAfterSelectedAdvances() {
      var remaining = line.balance;
      for (final advance in advances) {
        if (!appliedIds.contains(advance.id) || remaining <= 0.01) continue;
        final take = advance.availableAmount > remaining
            ? remaining
            : advance.availableAmount;
        remaining -= take;
      }
      return remaining < 0 ? 0 : remaining;
    }

    void writeTransferAmount(double amount) {
      transferAmount = amount;
      final text = _clpInput(amount);
      amountController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Cerrar',
      barrierColor: visual.overlayVeil,
      transitionDuration: PayrollTokens.base,
      pageBuilder: (dialogContext, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: StatefulBuilder(
            builder: (context, setSheet) {
              double applied = 0;
              var remaining = line.balance;
              final allocations = <(EmployeeAdvance, double)>[];
              for (final a in advances) {
                if (!appliedIds.contains(a.id) || remaining <= 0.01) continue;
                final take = a.availableAmount > remaining
                    ? remaining
                    : a.availableAmount;
                allocations.add((a, take));
                applied += take;
                remaining -= take;
              }
              final newMoney = line.balance - applied;
              final remainingAfterPayment =
                  newMoney - transferAmount > 0 ? newMoney - transferAmount : 0;
              String? amountError;
              if (newMoney > 0.01 && transferAmount <= 0.01) {
                amountError = 'Ingresa un monto mayor a \$0.';
              } else if (transferAmount > newMoney + 0.01) {
                amountError = 'El monto no puede superar ${_clp(newMoney)}.';
              }
              final canRegister = (newMoney <= 0.01 &&
                      allocations.isNotEmpty) ||
                  (transferAmount > 0.01 && transferAmount <= newMoney + 0.01);

              Future<void> register() async {
                if (!canRegister) return;
                final methodRow = methodsByLabel[method];
                final accountId =
                    methodRow?['account_id']?.toString().trim() ?? '';
                if (transferAmount > 0.01 &&
                    (methodRow == null || accountId.isEmpty)) {
                  ScaffoldMessenger.maybeOf(context)
                      ?.showSnackBar(const SnackBar(
                    content: Text('El método elegido no tiene una cuenta '
                        'contable activa.'),
                  ));
                  return;
                }
                if (transferAmount > 0.01 &&
                    methodRow?['requires_reference'] == true &&
                    referenceController.text.trim().isEmpty) {
                  ScaffoldMessenger.maybeOf(context)
                      ?.showSnackBar(const SnackBar(
                    content: Text('Este método exige una referencia antes de '
                        'registrar el pago.'),
                  ));
                  return;
                }
                final splits = <Map<String, dynamic>>[
                  for (final (a, take) in allocations)
                    {
                      'kind': 'advance',
                      'advance_id': a.id,
                      'amount': take,
                    },
                  if (transferAmount > 0.01)
                    {
                      'kind': 'payment',
                      'payment_method_id': methodRow?['id']?.toString(),
                      'payment_account_id': accountId,
                      'amount': transferAmount,
                      'payment_date':
                          DateTime.utc(date.year, date.month, date.day, 12)
                              .toIso8601String(),
                      'reference': referenceController.text.trim().isEmpty
                          ? null
                          : referenceController.text.trim(),
                    },
                ];
                final ok = await _run(() => _resolveActions().payLine(
                      voucherId: voucherId,
                      lineId: lineId,
                      splits: splits,
                      operationKey: operationKey,
                      expectedReconciliationVersion: week.reconciliationVersion,
                    ));
                if (ok && dialogContext.mounted) {
                  setSheet(() => allowClose = true);
                  await Future<void>.delayed(Duration.zero);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                }
                // Sin autoavance: la cola queda como estaba, misma semana.
              }

              return ValueListenableBuilder<TextEditingValue>(
                valueListenable: referenceController,
                builder: (context, referenceValue, _) {
                  final hasDraftChanges = appliedIds.isNotEmpty ||
                      method != initialMethod ||
                      !_sameCivilDate(date, initialDate) ||
                      (transferAmount - initialTransferAmount).abs() > 0.01 ||
                      referenceValue.text.trim().isNotEmpty;

                  Future<void> requestClose() async {
                    if (!hasDraftChanges) {
                      Navigator.of(dialogContext).pop();
                      return;
                    }
                    final discard =
                        await _confirmDiscardPaymentDraft(dialogContext);
                    if (!discard || !dialogContext.mounted) return;
                    setSheet(() => allowClose = true);
                    await Future<void>.delayed(Duration.zero);
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  }

                  return PopScope<void>(
                    canPop: allowClose || !hasDraftChanges,
                    onPopInvokedWithResult: (didPop, _) {
                      if (!didPop) requestClose();
                    },
                    child: _adaptivePayrollPanel(
                      dialogContext,
                      desktopWidth: 540,
                      background: visual.surfaceOverlay,
                      child: PayrollPaymentComposer(
                        personName: line.employeeName,
                        initials: _initialsOf(line.employeeName),
                        avatarColor: _avatarFor(line.employeeId),
                        weekLabel:
                            'PAGAR SEMANA ${_isoWeek(week.periodStart)} · '
                                    '${_range(week.periodStart, week.periodEnd)}'
                                .toUpperCase(),
                        hoursAndEarned:
                            '${line.totalHours.toStringAsFixed(1).replaceAll('.', ',')} h '
                            '· total ${_clp(line.totalAmount)}',
                        earnedLabel: _clp(line.balance),
                        advances: [
                          for (final a in advances)
                            PayrollAdvanceVM(
                              reason: a.notes?.trim().isNotEmpty == true
                                  ? a.notes!.trim()
                                  : 'Anticipo',
                              meta: '${_two(a.paidCivilDate.day)}/'
                                  '${_two(a.paidCivilDate.month)}'
                                  '${a.reference?.trim().isNotEmpty == true ? ' · ${a.reference!.trim()}' : ''}',
                              amountLabel: _clp(a.availableAmount),
                              applied: appliedIds.contains(a.id),
                              onToggle: () => setSheet(() {
                                final previousMaximum =
                                    maximumAfterSelectedAdvances();
                                final wasPayingMaximum =
                                    (transferAmount - previousMaximum).abs() <=
                                        0.01;
                                if (!appliedIds.remove(a.id)) {
                                  appliedIds.add(a.id);
                                }
                                final nextMaximum =
                                    maximumAfterSelectedAdvances();
                                if (wasPayingMaximum ||
                                    transferAmount > nextMaximum) {
                                  writeTransferAmount(nextMaximum);
                                }
                              }),
                            ),
                        ],
                        appliedLabel: applied > 0 ? _clp(-applied) : '\$0',
                        newMoneyLabel: _clp(newMoney),
                        amountController: amountController,
                        onAmountChanged: (value) => setSheet(
                          () => transferAmount = _parseClpInput(value),
                        ),
                        maximumNewMoneyLabel: _clp(newMoney),
                        remainingAfterLabel: _clp(remainingAfterPayment),
                        amountError: amountError,
                        registerLabel: transferAmount > 0.01
                            ? 'Registrar ${_clp(transferAmount)}'
                            : 'Aplicar anticipos',
                        registerEnabled: canRegister,
                        advancesBalanceLabel: 'vigente ${_clp(vigente)}',
                        contextNote: remainingAfterPayment > 0.01 &&
                                transferAmount > 0.01 &&
                                transferAmount <= newMoney + 0.01
                            ? 'Registrarás ${_clp(transferAmount)} ahora y '
                                'quedarán ${_clp(remainingAfterPayment)} '
                                'pendientes. La línea seguirá parcialmente '
                                'pagada; no requiere un segundo cierre manual.'
                            : applied > 0
                                ? 'Aplicar anticipos no cambia horas ni total calculado: '
                                    'baja el dinero nuevo y descuenta el saldo de '
                                    '${line.employeeName.trim().split(' ').first} a '
                                    '${_clp(vigente - applied)}.'
                                : advances.isEmpty
                                    ? 'Sin anticipos vigentes: el dinero nuevo es el '
                                        'saldo completo.'
                                    : '${line.employeeName.trim().split(' ').first} '
                                        'tiene ${_clp(vigente)} de anticipos vigentes. '
                                        'Si no aplicas ninguno, el saldo queda para '
                                        'semanas siguientes.',
                        methods: availableMethods,
                        selectedMethod: method,
                        dateLabel: '${_two(date.day)}/${_two(date.month)}/'
                            '${date.year}',
                        referenceValue: referenceController.text,
                        onSelectMethod: (value) =>
                            setSheet(() => method = value),
                        onPickDate: () async {
                          final first = DateTime(week.periodEnd.year,
                              week.periodEnd.month, week.periodEnd.day);
                          final last = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date.isBefore(first) ? first : date,
                            firstDate: first.isAfter(last) ? last : first,
                            lastDate: last,
                          );
                          if (picked != null) setSheet(() => date = picked);
                        },
                        referenceController: referenceController,
                        onClose: requestClose,
                        onRegister: register,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
    // showGeneralDialog completes when the pop starts, while the reverse
    // transition can still be listening to the field controller. Keep its
    // lifetime aligned with the route instead of disposing it mid-frame.
    await Future<void>.delayed(PayrollTokens.base);
    referenceController.dispose();
    amountController.dispose();
  }

  // ── Efectivo (2e) ────────────────────────────────────────────────────────

  Future<void> _openCash(PayrollVoucher week, PayrollVoucherLine line) async {
    final lineId = line.id;
    final voucherId = week.id;
    if (lineId == null || voucherId == null) return;
    if (!_versionedMutationsAvailable) {
      _showVersionedUpdateRequired();
      return;
    }
    final resolvedMethod = _resolvedMethodForLine(line);
    if ((resolvedMethod?['code']?.toString().trim().toLowerCase() ?? '') !=
        'cash') {
      await _openEmployeePaymentMethod(line);
      return;
    }
    final advances = _advancesFor(week, line.employeeId);
    final available = advances.fold<double>(0, (s, a) => s + a.availableAmount);
    var applyAdvance = false;
    var date = DateTime.now();
    final initialDate = date;
    var confirmed = false;
    var allowClose = false;
    final operationKey = const Uuid().v4();
    final weekPendingBefore = _pendingOf(week);
    final currentUserName = context
            .read<CurrentUserProfileService?>()
            ?.profile
            ?.displayName
            .trim() ??
        '';

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Cerrar',
      barrierColor: visual.overlayVeil,
      transitionDuration: PayrollTokens.base,
      pageBuilder: (dialogContext, _, __) {
        return Align(
          alignment: Alignment.centerRight,
          child: StatefulBuilder(
            builder: (context, setSheet) {
              final coverable = !applyAdvance
                  ? 0.0
                  : (available > line.balance ? line.balance : available);
              final deliver = line.balance - coverable;

              Future<void> confirm() async {
                final cashMethod = resolvedMethod;
                final accountId =
                    cashMethod?['account_id']?.toString().trim() ?? '';
                if (deliver > 0.01 &&
                    (cashMethod == null || accountId.isEmpty)) {
                  ScaffoldMessenger.maybeOf(context)
                      ?.showSnackBar(const SnackBar(
                    content: Text('No hay un método Efectivo activo con '
                        'cuenta contable.'),
                  ));
                  return;
                }
                var remainingAdvance = coverable;
                final advanceSplits = <Map<String, dynamic>>[];
                if (applyAdvance) {
                  for (final advance in advances) {
                    if (remainingAdvance <= 0.01) break;
                    final take = advance.availableAmount > remainingAdvance
                        ? remainingAdvance
                        : advance.availableAmount;
                    if (take <= 0.01) continue;
                    advanceSplits.add(<String, dynamic>{
                      'kind': 'advance',
                      'advance_id': advance.id,
                      'amount': take,
                    });
                    remainingAdvance -= take;
                  }
                }
                final splits = <Map<String, dynamic>>[
                  ...advanceSplits,
                  if (deliver > 0.01)
                    {
                      'kind': 'payment',
                      'payment_method_id': cashMethod?['id']?.toString(),
                      'payment_account_id': accountId,
                      'amount': deliver,
                      'payment_date':
                          DateTime.utc(date.year, date.month, date.day, 12)
                              .toIso8601String(),
                      'reference': null,
                    },
                ];
                final ok = await _run(() => _resolveActions().payLine(
                      voucherId: voucherId,
                      lineId: lineId,
                      splits: splits,
                      operationKey: operationKey,
                      expectedReconciliationVersion: week.reconciliationVersion,
                    ));
                if (ok && dialogContext.mounted) {
                  setSheet(() => confirmed = true);
                }
              }

              // Estado post-confirmación: qué pasó + elecciones explícitas.
              final refreshedWeek =
                  _data?.vouchers.where((v) => v.id == voucherId).firstOrNull;
              final weekRemaining = refreshedWeek == null
                  ? (weekPendingBefore - deliver - coverable)
                  : _pendingOf(refreshedWeek);
              PayrollVoucherLine? nextCash;
              if (refreshedWeek != null) {
                for (final l in refreshedWeek.lines.where((l) =>
                    l.isIncluded && l.balance > 0.01 && l.id != lineId)) {
                  if (_statusOf(refreshedWeek, l) ==
                      PayrollRowStatus.pendingCash) {
                    nextCash = l;
                    break;
                  }
                }
              }

              final hasDraftChanges = !confirmed &&
                  (applyAdvance || !_sameCivilDate(date, initialDate));

              Future<void> requestClose() async {
                if (!hasDraftChanges) {
                  Navigator.of(dialogContext).pop();
                  return;
                }
                final discard =
                    await _confirmDiscardPaymentDraft(dialogContext);
                if (!discard || !dialogContext.mounted) return;
                setSheet(() => allowClose = true);
                await Future<void>.delayed(Duration.zero);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              }

              return PopScope<void>(
                canPop: allowClose || !hasDraftChanges,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) requestClose();
                },
                child: _adaptivePayrollPanel(
                  dialogContext,
                  desktopWidth: 390,
                  background: visual.surfaceOverlay,
                  child: PayrollCashSurface(
                    weekLabel: 'Semana ${_isoWeek(week.periodStart)}',
                    personName: line.employeeName,
                    initials: _initialsOf(line.employeeName),
                    avatarColor: _avatarFor(line.employeeId),
                    hoursAndMethod:
                        '${line.totalHours.toStringAsFixed(1).replaceAll('.', ',')} h · efectivo',
                    earnedLabel: _clp(line.balance),
                    advancesLabel: _clp(coverable),
                    deliverLabel: _clp(deliver),
                    availableAdvanceLabel: _clp(available),
                    dateLabel:
                        '${_two(date.day)}/${_two(date.month)}/${date.year}',
                    deliveredBy: currentUserName.isEmpty
                        ? 'Usuario actual'
                        : currentUserName,
                    onClose: requestClose,
                    onApplyAdvance: available <= 0.01
                        ? null
                        : () => setSheet(() => applyAdvance = !applyAdvance),
                    onPickDate: () async {
                      final first = DateTime(week.periodStart.year,
                          week.periodStart.month, week.periodStart.day);
                      final last = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: first,
                        lastDate: last,
                      );
                      if (picked != null) setSheet(() => date = picked);
                    },
                    onConfirm: confirm,
                    confirmed: confirmed,
                    weekRemainingLabel: _clp(weekRemaining),
                    weekBlockedReason: weekRemaining <= 0.01
                        ? 'La semana quedó sin saldos pendientes.'
                        : 'No se puede cerrar la semana todavía: quedan '
                            '${_clp(weekRemaining)} por resolver.',
                    nextCashLabel: nextCash == null
                        ? 'No quedan efectivos pendientes esta semana'
                        : 'Confirmar efectivo de ${nextCash.employeeName} · '
                            'Semana ${_isoWeek(refreshedWeek!.periodStart)} · '
                            '${_clp(nextCash.balance)}',
                    onNextCash: nextCash == null
                        ? null
                        : () {
                            final target = nextCash!;
                            Navigator.of(dialogContext).pop();
                            final w = _data?.vouchers
                                .where((v) => v.id == voucherId)
                                .firstOrNull;
                            if (w != null) _openCash(w, target);
                          },
                    onBackToQueue: requestClose,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ── Anticipos (2d) ───────────────────────────────────────────────────────

  Future<void> _loadAdvanceLedger(String employeeId,
      {bool more = false}) async {
    final loader = _resolveActions().loadAdvanceLedgerPage;
    if (loader == null || _advanceLedgerUnavailable) return;
    if (more && (_advanceLedgerCursor == null || _advanceLedgerLoadingMore)) {
      return;
    }
    final epoch = ++_advanceLedgerEpoch;
    setState(() {
      if (more) {
        _advanceLedgerLoadingMore = true;
      } else {
        _advanceLedgerEmployeeId = employeeId;
        _advanceLedgerEntries.clear();
        _advanceLedgerCivilDates.clear();
        _advanceLedgerTotals = null;
        _advanceLedgerCursor = null;
        _advanceLedgerHasMore = false;
        _advanceLedgerLoading = true;
      }
      _advanceLedgerError = null;
    });
    try {
      final page = await loader(
        employeeId: employeeId,
        cursor: more ? _advanceLedgerCursor : null,
      );
      if (!mounted || epoch != _advanceLedgerEpoch) return;
      // Civil days resolve BEFORE the rows publish so a row never renders a
      // device-local day and then flips to the tenant day.
      final civilDates = page == null
          ? const <String, DateTime>{}
          : await _tenantCivilDatesFor(page.items);
      if (!mounted || epoch != _advanceLedgerEpoch) return;
      setState(() {
        _advanceLedgerLoading = false;
        _advanceLedgerLoadingMore = false;
        if (page == null) {
          // RPC absent: stay on the open-advance compatibility reader.
          _advanceLedgerUnavailable = true;
          return;
        }
        _advanceLedgerEntries.addAll(page.items);
        _advanceLedgerCivilDates.addAll(civilDates);
        _advanceLedgerTotals = page.totals;
        _advanceLedgerCursor = page.nextCursor;
        _advanceLedgerHasMore = page.hasMore;
      });
    } catch (error) {
      if (!mounted || epoch != _advanceLedgerEpoch) return;
      debugPrint('❌ [PayrollRedesign] ledger de anticipos: $error');
      setState(() {
        _advanceLedgerLoading = false;
        _advanceLedgerLoadingMore = false;
        _advanceLedgerError =
            'No pudimos cargar el libro de anticipos. Reintenta.';
      });
    }
  }

  /// Resolves each entry's paid instant to the tenant's civil day. A failed
  /// resolution falls back to the device-local day for that entry only; the
  /// ledger itself never blocks on timezone metadata.
  Future<Map<String, DateTime>> _tenantCivilDatesFor(
    List<PayrollAdvanceLedgerEntry> entries,
  ) async {
    final resolve = _resolveActions().tenantCivilDateOf;
    if (resolve == null) return const <String, DateTime>{};
    final dates = <String, DateTime>{};
    for (final entry in entries) {
      try {
        dates[entry.id] = await resolve(entry.paidAt);
      } catch (error) {
        debugPrint('⚠️ [PayrollRedesign] fecha civil del ledger: '
            '${error.runtimeType}');
      }
    }
    return dates;
  }

  AdvanceLedgerRowVM _advanceLedgerRowFromEntry(
    PayrollAdvanceLedgerEntry entry,
  ) {
    final reference = entry.reference?.trim();
    final notes = entry.notes?.trim();
    final hasReference = reference != null && reference.isNotEmpty;
    final hasNotes = notes != null && notes.isNotEmpty;
    final reason = hasReference
        ? reference
        : hasNotes
            ? notes
            : 'Anticipo';
    final detailParts = <String>[
      if (hasReference &&
          hasNotes &&
          notes.toLowerCase() != reference.toLowerCase())
        notes,
      if (entry.allocations.isNotEmpty)
        'Aplicado en ${entry.allocations.map((a) => a.voucherNumber).toSet().join(', ')}',
      if (entry.status == PayrollAdvanceLedgerStatus.voided) 'Anulado',
    ];
    final local = _advanceLedgerCivilDates[entry.id] ?? entry.paidAt.toLocal();
    final tone = switch (entry.status) {
      PayrollAdvanceLedgerStatus.applied => visual.success,
      PayrollAdvanceLedgerStatus.partiallyApplied => visual.warning,
      PayrollAdvanceLedgerStatus.open => visual.info,
      PayrollAdvanceLedgerStatus.voided => visual.neutral,
    };
    return AdvanceLedgerRowVM(
      date: '${_two(local.day)}/${_two(local.month)}',
      reason: reason,
      detail: detailParts.isEmpty ? null : detailParts.join(' · '),
      amount: _clp(entry.amount),
      applied: _clp(entry.appliedAmount),
      balance: _clp(entry.balanceAmount),
      statusLabel: switch (entry.status) {
        PayrollAdvanceLedgerStatus.applied => 'IMPUTADO',
        PayrollAdvanceLedgerStatus.partiallyApplied => 'PARCIAL',
        PayrollAdvanceLedgerStatus.open => 'VIGENTE',
        PayrollAdvanceLedgerStatus.voided => 'ANULADO',
      },
      tone: tone,
    );
  }

  AdvanceLedgerRowVM _advanceLedgerRow(EmployeeAdvance advance) {
    final reference = advance.reference?.trim();
    final notes = advance.notes?.trim();
    final hasReference = reference != null && reference.isNotEmpty;
    final hasNotes = notes != null && notes.isNotEmpty;
    final reason = hasReference
        ? reference
        : hasNotes
            ? notes
            : 'Anticipo';
    final detail = hasReference &&
            hasNotes &&
            notes.toLowerCase() != reference.toLowerCase()
        ? notes
        : null;

    return AdvanceLedgerRowVM(
      date:
          '${_two(advance.paidCivilDate.day)}/${_two(advance.paidCivilDate.month)}',
      reason: reason,
      detail: detail,
      amount: _clp(advance.amount),
      applied: _clp(advance.amountApplied),
      balance: _clp(advance.availableAmount),
      statusLabel: advance.availableAmount <= 0.01
          ? 'IMPUTADO'
          : advance.amountApplied > 0.01
              ? 'PARCIAL'
              : 'VIGENTE',
      tone: advance.availableAmount <= 0.01
          ? visual.success
          : advance.amountApplied > 0.01
              ? visual.warning
              : visual.info,
    );
  }

  Widget _buildAdvances(PayrollRedesignData data) {
    final byEmployee = <String, List<EmployeeAdvance>>{};
    for (final a in data.openAdvances) {
      byEmployee.putIfAbsent(a.employeeId, () => []).add(a);
    }
    // With the audit read model installed, every employee (including an
    // inactive one whose advances were all applied) stays discoverable; the
    // legacy fallback can only offer people with open balances.
    final ledgerAvailable = !_advanceLedgerUnavailable &&
        _resolveActions().loadAdvanceLedgerPage != null;
    final selectableIds = <String>{
      ...byEmployee.keys,
      if (ledgerAvailable)
        for (final row in data.employees)
          if (row['id'] != null) row['id'].toString(),
    };
    if (selectableIds.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
            decoration: BoxDecoration(
              color: visual.surface,
              borderRadius: BorderRadius.circular(PayrollTokens.rPanel),
              border: Border.all(color: visual.borderStrong),
              boxShadow: visual.raised,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: visual.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.payments_outlined,
                    size: 21,
                    color: visual.accent,
                  ),
                ),
                const SizedBox(height: 13),
                Text(
                  'No hay anticipos vigentes',
                  style: visual.sectionTitle.copyWith(fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Registra el primero cuando una persona reciba dinero antes '
                  'del pago semanal. Quedará disponible para aplicarlo en la '
                  'nómina correspondiente.',
                  style: visual.bodyS.copyWith(
                    color: visual.inkFaint,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (!_versionedMutationsAvailable) ...[
                  Text(
                    'Actualización del servidor pendiente: registrar '
                    'anticipos se habilita cuando se instale.',
                    key: const ValueKey<String>(
                      'payroll-empty-advance-blocked-reason',
                    ),
                    style: visual.bodyS.copyWith(
                      color: visual.warningFg,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ] else
                  SizedBox(
                    width: double.infinity,
                    height: PayrollTokens.touchMobile,
                    child: FilledButton.tonalIcon(
                      key: const ValueKey<String>(
                        'payroll-empty-advance-register',
                      ),
                      onPressed: _busy ? null : _newAdvance,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Registrar anticipo'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final employeeIds = selectableIds.toList()
      ..sort(
        (a, b) => _employeeName(a)
            .toLowerCase()
            .compareTo(_employeeName(b).toLowerCase()),
      );
    final selectedId = employeeIds.contains(_selectedAdvanceEmployeeId)
        ? _selectedAdvanceEmployeeId!
        : employeeIds.first;
    final selectedAdvances =
        (byEmployee[selectedId] ?? const <EmployeeAdvance>[]).toList()
          ..sort((a, b) => a.paidCivilDate.compareTo(b.paidCivilDate));
    final selectedName = _employeeName(selectedId);
    final canRegisterForSelected =
        _versionedMutationsAvailable && _employeeCanReceiveAdvance(selectedId);
    final unavailableReason = canRegisterForSelected
        ? null
        : !_versionedMutationsAvailable
            ? 'Actualización del servidor pendiente: el ledger queda '
                'disponible para revisión y registrar anticipos se habilita '
                'cuando se instale.'
            : 'Esta persona ya no está disponible como trabajador activo. '
                'Su ledger se conserva para revisión, pero no admite nuevos anticipos.';
    final openBalance =
        selectedAdvances.fold<double>(0, (s, a) => s + a.availableAmount);

    if (ledgerAvailable &&
        _advanceLedgerEmployeeId != selectedId &&
        !_advanceLedgerLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _scope != _PayrollScope.advances) return;
        if (_advanceLedgerEmployeeId == selectedId || _advanceLedgerLoading) {
          return;
        }
        _loadAdvanceLedger(selectedId);
      });
    }
    final usingLedger =
        ledgerAvailable && _advanceLedgerEmployeeId == selectedId;
    final showLedgerRows = usingLedger &&
        (_advanceLedgerEntries.isNotEmpty ||
            (!_advanceLedgerLoading && _advanceLedgerError == null));
    final totals = usingLedger ? _advanceLedgerTotals : null;

    return PayrollAdvancesSurface(
      people: [
        for (final id in employeeIds)
          AdvancePersonVM(
            id: id,
            name: _employeeName(id),
            initials: _initialsOf(_employeeName(id)),
            avatarColor: _avatarFor(id),
            balanceLabel: byEmployee.containsKey(id)
                ? _clp(byEmployee[id]!
                    .fold<double>(0, (s, a) => s + a.availableAmount))
                : '—',
            caption: !byEmployee.containsKey(id)
                ? 'historial'
                : byEmployee[id]!
                            .fold<double>(0, (s, a) => s + a.availableAmount) >
                        0.01
                    ? 'aplicable ahora'
                    : 'todo aplicado',
            selected: id == selectedId,
            onTap: () => setState(() => _selectedAdvanceEmployeeId = id),
          ),
      ],
      selectedName: selectedName,
      selectedInitials: _initialsOf(selectedName),
      selectedAvatar: _avatarFor(selectedId),
      selectedBalance:
          totals != null ? _clp(totals.balanceAmount) : _clp(openBalance),
      selectedCount: totals != null
          ? '${totals.recordCount} '
              '${totals.recordCount == 1 ? 'movimiento' : 'movimientos'}'
          : '${selectedAdvances.length} '
              '${selectedAdvances.length == 1 ? 'movimiento' : 'movimientos'}',
      ledger: showLedgerRows
          ? [
              for (final entry in _advanceLedgerEntries)
                _advanceLedgerRowFromEntry(entry),
            ]
          : [
              for (final a in selectedAdvances) _advanceLedgerRow(a),
            ],
      hasMore: usingLedger && _advanceLedgerHasMore,
      isLoadingMore: usingLedger &&
          (_advanceLedgerLoadingMore ||
              (_advanceLedgerLoading && _advanceLedgerEntries.isEmpty)),
      paginationError: usingLedger ? _advanceLedgerError : null,
      onLoadMore: !usingLedger
          ? null
          : () {
              if (_advanceLedgerError != null &&
                  _advanceLedgerEntries.isEmpty) {
                _loadAdvanceLedger(selectedId);
              } else {
                _loadAdvanceLedger(selectedId, more: true);
              }
            },
      onNewAdvanceForSelectedPerson:
          canRegisterForSelected ? () => _newAdvance(selectedId) : null,
      selectedPersonActionUnavailableReason: unavailableReason,
    );
  }

  /// `S28 · 3 por resolver · 4 personas · $329.475`.
  ///
  /// «Por resolver» cuenta filas que todavía piden una decisión de pago;
  /// «personas» cuenta a quienes entran en el cálculo de la semana, así que
  /// quien no tiene horas cerradas no infla ninguno de los dos números.
  String _selectedWeekSummary() {
    final week = _selected;
    if (week == null) return 'sin semanas abiertas';
    final counted = week.lines
        .where((l) => l.isIncluded && l.totalAmount > 0.01)
        .toList(growable: false);
    final unresolved = counted.where((l) => l.balance > 0.01).length;
    final pending = counted.fold<double>(0, (s, l) => s + l.balance);
    final parts = <String>[
      'S${_isoWeek(week.periodStart)}',
      if (unresolved > 0)
        '$unresolved por resolver'
      else
        'sin decisiones pendientes',
      '${counted.length} ${counted.length == 1 ? 'persona' : 'personas'}',
      if (pending > 0.01) _clp(pending),
    ];
    return parts.join(' · ');
  }

  // ── moduleCommand (fila 2 del bloque navy, opt-in de Nóminas) ────────────

  Widget _buildModuleCommand(PayrollRedesignData data,
      {required bool compact}) {
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;
    final open = _openWeeks(data);
    final historyCount = _historyWeeks(data).length;
    final advanceTotal = data.openAdvances.fold<double>(
      0,
      (sum, advance) => sum + advance.availableAmount,
    );
    final advancePeople = data.openAdvances
        .where((advance) => advance.availableAmount > 0.01)
        .map((advance) => advance.employeeId)
        .toSet()
        .length;
    final meta = switch (_scope) {
      // 5a resume la semana que se está mirando, no el rango de todas: el
      // rango contestaba «cuánto debo en total», que no es el trabajo de nadie.
      // Acá dice qué falta decidir, sobre cuánta gente y por cuánta plata.
      _PayrollScope.weeks =>
        open.isEmpty ? 'sin semanas abiertas' : _selectedWeekSummary(),
      _PayrollScope.history => historyCount == 0
          ? 'sin semanas cerradas'
          : '${_historyHasMore ? '$historyCount+' : '$historyCount'} '
              '${historyCount == 1 && !_historyHasMore ? 'semana cerrada' : 'semanas cerradas'} '
              '· solo lectura',
      _PayrollScope.advances => advancePeople == 0
          ? 'sin anticipos vigentes'
          : '$advancePeople ${advancePeople == 1 ? 'persona' : 'personas'} · ${_clp(advanceTotal)} disponible',
    };

    Widget scopePill(String label, _PayrollScope value) {
      final active = _scope == value;
      final borderRadius = BorderRadius.circular(PayrollTokens.rControl);
      return Semantics(
        button: true,
        selected: active,
        label: label,
        child: Material(
          color: active ? chrome.raised : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: BorderSide(
              color: active ? chrome.edge : Colors.transparent,
            ),
          ),
          child: InkWell(
            onTap: () {
              if (value == _PayrollScope.history) {
                _showHistory();
                return;
              }
              setState(() => _scope = value);
            },
            mouseCursor: SystemMouseCursors.click,
            borderRadius: borderRadius,
            hoverColor: chrome.foreground.withValues(alpha: 0.08),
            focusColor: chrome.accent.withValues(alpha: 0.14),
            highlightColor: chrome.foreground.withValues(alpha: 0.12),
            splashColor: chrome.accent.withValues(alpha: 0.12),
            child: SizedBox(
              height: 26,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: Text(
                    label,
                    style: visual.label.copyWith(
                      fontSize: 11,
                      color:
                          active ? chrome.foreground : chrome.mutedForeground,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: PayrollTokens.moduleCommandH,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
      decoration: BoxDecoration(
        color: chrome.canvas,
        border: Border(
          bottom: BorderSide(color: chrome.edge),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Nóminas',
            style: visual.moduleTitle.copyWith(
              color: chrome.foreground,
            ),
          ),
          const SizedBox(width: 12),
          scopePill('Semanas', _PayrollScope.weeks),
          const SizedBox(width: 4),
          scopePill('Historial', _PayrollScope.history),
          const SizedBox(width: 4),
          scopePill('Anticipos', _PayrollScope.advances),
          const SizedBox(width: 12),
          Expanded(
            child: Text(meta,
                key: const ValueKey('payroll-module-meta'),
                style: visual.monoS.copyWith(color: chrome.mutedForeground),
                overflow: TextOverflow.ellipsis),
          ),
          Semantics(
            button: true,
            label: 'Importar cartola con OCR',
            child: Tooltip(
              message: 'Importar PDF o imagen y conciliar pagos con OCR',
              child: SizedBox(
                height: 28,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _openReconciliation,
                  icon: const Icon(Icons.document_scanner_outlined, size: 14),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: chrome.foreground,
                    disabledForegroundColor:
                        chrome.mutedForeground.withValues(alpha: 0.72),
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(color: chrome.edge),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(PayrollTokens.rControl),
                    ),
                  ),
                  label: Text(
                    'Importar cartola',
                    style: visual.labelStrong.copyWith(
                      fontSize: 11.5,
                      color: chrome.foreground,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Móvil (<900): tarjeta por persona, CTA 50, targets 48 ────────────────

  String _compactHeaderContext(
    PayrollRedesignData data,
    PayrollVoucher? week,
  ) {
    switch (_scope) {
      case _PayrollScope.history:
        final count = _historyWeeks(data).length;
        return count == 0
            ? 'Sin semanas cerradas'
            : '${_historyHasMore ? '$count+' : '$count'} '
                '${count == 1 && !_historyHasMore ? 'semana cerrada' : 'semanas cerradas'} '
                '· solo lectura';
      case _PayrollScope.advances:
        final active = data.openAdvances
            .where((advance) => advance.availableAmount > 0.01)
            .toList(growable: false);
        final people =
            active.map((advance) => advance.employeeId).toSet().length;
        final amount = active.fold<double>(
            0, (sum, advance) => sum + advance.availableAmount);
        return people == 0
            ? 'Sin anticipos vigentes'
            : '$people ${people == 1 ? 'persona' : 'personas'} · ${_clp(amount)} disponible';
      case _PayrollScope.weeks:
        if (week == null) return 'Sin semanas abiertas';
        final unresolved = week.lines
            .where((line) => line.isIncluded && line.balance > 0.01)
            .length;
        final weekNumber = _isoWeek(week.periodStart);
        return 'S$weekNumber · $unresolved por resolver · ${_clp(_pendingOf(week))}';
    }
  }

  void _publishCompactHeaderContext(
    PayrollRedesignData data,
    PayrollVoucher? week,
  ) {
    final callback = widget.onCompactContextChanged;
    if (callback == null) return;
    final next = _compactHeaderContext(data, week);
    if (next == _lastCompactContextLine) return;
    _lastCompactContextLine = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(next);
    });
  }

  Future<void> _showMobilePayrollUtilities() async {
    final action = await showModalBottomSheet<_PayrollMobileUtility>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Text(
                'Utilidades de Nóminas',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              minTileHeight: PayrollTokens.touchMobile,
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Importar cartola'),
              subtitle: const Text('Ponerse al día conciliando pagos con OCR'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(
                sheetContext,
                _PayrollMobileUtility.reconcile,
              ),
            ),
            ListTile(
              minTileHeight: PayrollTokens.touchMobile,
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Abrir Asistencias'),
              subtitle: const Text('Revisar las horas que originan la semana'),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => Navigator.pop(
                sheetContext,
                _PayrollMobileUtility.attendance,
              ),
            ),
            const SizedBox(height: 12),
          ],
        );
      },
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _PayrollMobileUtility.reconcile:
        await _openReconciliation();
      case _PayrollMobileUtility.attendance:
        _openAttendances();
    }
  }

  Widget _buildMobile(PayrollRedesignData data, PayrollVoucher? week) {
    final visual = PayrollVisualTokens.of(context);
    final weeks = _weekCards(data);
    final historyCount = _historyWeeks(data).length;
    final advanceCount = data.openAdvances
        .where((advance) => advance.availableAmount > 0.01)
        .map((advance) => advance.employeeId)
        .toSet()
        .length;
    return Container(
      color: visual.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CompactPayrollScopeBar(
            scope: _scope,
            weekCount: weeks.length,
            historyCount: historyCount,
            advanceCount: advanceCount,
            onWeeks: () => setState(() => _scope = _PayrollScope.weeks),
            onHistory: _showHistory,
            onAdvances: () => setState(() => _scope = _PayrollScope.advances),
            onUtilities: _busy ? null : _showMobilePayrollUtilities,
          ),
          if (_staleProjectionBanner() case final banner?) banner,
          if (_scope == _PayrollScope.advances)
            Expanded(child: _buildAdvances(data))
          else if (_scope == _PayrollScope.history)
            Expanded(child: _buildHistory(data, compact: true))
          else ...[
            _MobileWeekStrip(weeks: weeks),
            ...[
              Expanded(
                child: week == null
                    ? _PayrollEmptyWeeks(onOpenAttendance: _openAttendances)
                    : ListView(
                        padding: const EdgeInsets.all(13),
                        children: [
                          for (final row in _personRows(week)) ...[
                            _MobilePersonCard(vm: row),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
              ),
              if (week != null)
                _MobileMoneyBar(
                  totals: _totals(week),
                  onConfirmWeek: () => _commitWeek(week),
                  onNextAction: () => _runNextWeekAction(week),
                ),
            ],
          ],
        ],
      ),
    );
  }

  /// L-H2 (Codex cross-review 2026-07-30): while stale data stays on screen
  /// after a failed authoritative reload, the operator gets a persistent
  /// warning with a REAL retry instead of a transient snackbar. The banner
  /// disappears only when `_load` succeeds and clears both fences.
  Widget? _staleProjectionBanner() {
    if (_error == null && !_authoritativeReloadRequired) return null;
    final visual = PayrollVisualTokens.of(context);
    final message = _authoritativeReloadRequired
        ? 'El servidor confirmó el último movimiento, pero la vista no pudo '
            'recargarse. Recarga y verifica el saldo antes de repetir nada.'
        : 'No pudimos actualizar los datos: estás viendo la última carga '
            'buena. Recarga antes de registrar movimientos.';
    return Container(
      key: const ValueKey<String>('payroll-stale-projection-banner'),
      margin: const EdgeInsets.fromLTRB(13, 10, 13, 0),
      padding: const EdgeInsets.fromLTRB(12, 9, 9, 9),
      decoration: BoxDecoration(
        color: visual.warningSoft,
        borderRadius: BorderRadius.circular(PayrollTokens.rField),
        border: Border.all(color: visual.warningBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.sync_problem_rounded, size: 18, color: visual.warningFg),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: visual.bodyS.copyWith(color: visual.warningFg),
            ),
          ),
          const SizedBox(width: 9),
          SizedBox(
            width: 108,
            child: PayrollAccentAction(
              label: 'Reintentar',
              onTap: _isLoading ? null : () => _load(),
              busy: _isLoading,
              height: 36,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    if (_isLoading && _data == null) {
      return ColoredBox(
        color: visual.canvas,
        child: Center(
          child: CircularProgressIndicator(color: visual.accent),
        ),
      );
    }
    final error = _error;
    final data = _data;
    if (data == null) {
      return ColoredBox(
        color: visual.canvas,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error ?? 'Sin datos.', style: visual.bodyM),
              const SizedBox(height: 12),
              SizedBox(
                width: 124,
                child: PayrollAccentAction(
                  label: 'Reintentar',
                  onTap: _load,
                  height: 48,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final compactShell = ResponsiveViewport.usesCompactShell(context);
    final week = _selected;
    _publishCompactHeaderContext(data, week);

    if (compactShell) {
      // 3c: sin rail ni tabs persistentes; el header único lo pone el shell
      // compacto canónico (AppBar + drawer de MainLayout).
      return _buildMobile(data, week);
    }

    return Container(
      color: visual.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildModuleCommand(data, compact: false),
          if (_staleProjectionBanner() case final banner?) banner,
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dense = constraints.maxWidth < 1240;
                if (_scope == _PayrollScope.advances) {
                  return _buildAdvances(data);
                }
                if (_scope == _PayrollScope.history) {
                  return _buildHistory(data, compact: false);
                }
                if (week == null) {
                  return _PayrollEmptyWeeks(
                    onOpenAttendance: _openAttendances,
                  );
                }
                return PayrollQueueSurface(
                  weeks: _weekCards(data),
                  rows: _personRows(week),
                  totals: _totals(week),
                  dense: dense,
                  excludedNote: _excludedNote(week),
                  onOpenAttendance: _openAttendances,
                  onConfirmWeek: () => _commitWeek(week),
                  onNextAction: () => _runNextWeekAction(week),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Piezas móviles (spec 390: tarjeta 12, CTA 50/11, targets 48) ────────────

class _PayrollEmptyWeeks extends StatelessWidget {
  const _PayrollEmptyWeeks({required this.onOpenAttendance});

  final VoidCallback onOpenAttendance;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: visual.accentSoft,
                  borderRadius: BorderRadius.circular(PayrollTokens.rField),
                  border: Border.all(color: visual.accentBorder),
                ),
                child: Icon(
                  Icons.calendar_month_outlined,
                  color: visual.accent,
                  size: 21,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No hay semanas por resolver',
                textAlign: TextAlign.center,
                style: visual.sectionTitle,
              ),
              const SizedBox(height: 6),
              Text(
                'Cuando cierres horas en Asistencias, la semana aparecerá aquí '
                'lista para confirmar y pagar.',
                textAlign: TextAlign.center,
                style: visual.bodyS,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('payroll-empty-weeks-open-attendance'),
                onPressed: onOpenAttendance,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Abrir Asistencias'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: visual.accent,
                  minimumSize: const Size(0, PayrollTokens.touchMobile),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  side: BorderSide(color: visual.accentBorder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PayrollTokens.rField),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactPayrollScopeBar extends StatelessWidget {
  const _CompactPayrollScopeBar({
    required this.scope,
    required this.weekCount,
    required this.historyCount,
    required this.advanceCount,
    required this.onWeeks,
    required this.onHistory,
    required this.onAdvances,
    required this.onUtilities,
  });

  final _PayrollScope scope;
  final int weekCount;
  final int historyCount;
  final int advanceCount;
  final VoidCallback onWeeks;
  final VoidCallback onHistory;
  final VoidCallback onAdvances;
  final VoidCallback? onUtilities;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Container(
      key: const ValueKey('payroll-mobile-scope-bar'),
      height: 48,
      padding: const EdgeInsets.only(left: 8),
      color: visual.surface,
      // Paint the divider over the surface so it does not steal one pixel
      // from the 48px interaction targets inside the scope bar.
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: visual.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CompactPayrollScopePill(
                    key: const ValueKey('payroll-mobile-weeks'),
                    label: 'Semanas',
                    count: weekCount,
                    selected: scope == _PayrollScope.weeks,
                    onTap: onWeeks,
                  ),
                  const SizedBox(width: 7),
                  _CompactPayrollScopePill(
                    key: const ValueKey('payroll-mobile-history'),
                    label: 'Historial',
                    count: historyCount,
                    selected: scope == _PayrollScope.history,
                    onTap: historyCount == 0 ? null : onHistory,
                  ),
                  const SizedBox(width: 7),
                  _CompactPayrollScopePill(
                    key: const ValueKey('payroll-mobile-advances'),
                    label: 'Anticipos',
                    count: advanceCount,
                    selected: scope == _PayrollScope.advances,
                    onTap: onAdvances,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              key: const ValueKey('payroll-mobile-utilities'),
              tooltip: 'Utilidades de Nóminas',
              onPressed: onUtilities,
              icon: const Icon(Icons.more_horiz_rounded),
              color: visual.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactPayrollScopePill extends StatelessWidget {
  const _CompactPayrollScopePill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: '$label${count > 0 ? ', $count' : ''}',
      child: SizedBox(
        height: 48,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(PayrollTokens.rPill),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(minWidth: 76, minHeight: 34),
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: selected ? visual.accentSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(PayrollTokens.rPill),
                  border: Border.all(
                    color: selected ? visual.accentBorder : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      style: visual.labelStrong.copyWith(
                        color: selected ? visual.accent : visual.inkMuted,
                      ),
                    ),
                    if (selected && count > 0) ...[
                      const SizedBox(width: 5),
                      Text(
                        '$count',
                        style: visual.monoS.copyWith(
                          color: visual.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ] else if (!selected && count > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: visual.warningFg,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileWeekStrip extends StatelessWidget {
  const _MobileWeekStrip({required this.weeks});

  final List<PayrollWeekCardVM> weeks;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    if (weeks.isEmpty) return const SizedBox.shrink();
    return Container(
      key: const ValueKey('payroll-mobile-open-week-selector'),
      height: 62,
      padding: const EdgeInsets.symmetric(vertical: 7),
      color: visual.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showAmount = constraints.maxWidth >= 420;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            itemCount: weeks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (context, index) {
              final week = weeks[index];
              final shortName = week.name.replaceFirst('Semana ', 'S');
              return Semantics(
                button: true,
                selected: week.selected,
                label: '${week.name}, ${week.amountLabel}, ${week.statusLabel}',
                child: Material(
                  color:
                      week.selected ? visual.accentSoft : visual.surfaceSunken,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(PayrollTokens.rField),
                    side: BorderSide(
                      color: week.selected ? visual.accent : visual.border,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('payroll-mobile-week-${week.name}'),
                    onTap: week.onTap,
                    child: SizedBox(
                      width: showAmount ? 124 : 48,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: showAmount ? 9 : 5,
                          vertical: 5,
                        ),
                        child: showAmount
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(shortName, style: visual.labelStrong),
                                  Text(
                                    week.amountLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: visual.monoS,
                                  ),
                                ],
                              )
                            : Center(
                                child: Text(
                                  shortName,
                                  style: visual.labelStrong.copyWith(
                                    color: week.selected
                                        ? visual.accent
                                        : visual.ink,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MobilePersonCard extends StatelessWidget {
  const _MobilePersonCard({required this.vm});
  final PayrollPersonRowVM vm;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final tone = vm.toneFor(visual);
    final pending = vm.isPending;
    final hasAction =
        vm.actionMode != PayrollRowActionMode.none && vm.actionLabel.isNotEmpty;
    final disclosureLabel = vm.expanded ? 'Ocultar detalle' : 'Ver detalle';

    Widget factRow({required String label, required String value}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 4,
              child: Text(label, style: visual.label),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: visual.monoM,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: visual.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: visual.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            key: ValueKey<String>(
              'payroll-mobile-person-disclosure-${vm.name}',
            ),
            button: true,
            expanded: vm.expanded,
            label: '$disclosureLabel de nómina de ${vm.name}',
            hint: 'Muestra horas, tarifa y pagos registrados',
            child: Material(
              color: visual.surface,
              borderRadius: BorderRadius.circular(PayrollTokens.rField),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: vm.onToggle,
                mouseCursor: SystemMouseCursors.click,
                hoverColor: visual.accentSoft,
                focusColor: visual.accentSoft,
                splashColor: visual.accentSoft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: PayrollTokens.touchMobile,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: vm.avatarColor,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          vm.initials,
                          style: visual.avatarInitials(12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vm.name,
                              style: visual.bodyM
                                  .copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // 5l pone horas y método juntos bajo el nombre:
                            // en el teléfono no hay columna MÉTODO donde
                            // buscarlos.
                            Text(
                              vm.hours.isEmpty
                                  ? vm.method
                                  : '${vm.hours} · ${vm.method}',
                              style: visual.monoS.copyWith(fontSize: 10),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // La cifra lidera la tarjeta, como en 5l: en una lista
                      // táctil es lo primero que se busca. La ecuación que la
                      // explica baja al detalle, donde no compite con la
                      // acción.
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            vm.newMoney,
                            maxLines: 1,
                            style: visual.numRow.copyWith(fontSize: 17),
                          ),
                          Text(
                            vm.paid == '—' ? 'a pagar' : 'pagado ${vm.paid}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: visual.monoS.copyWith(fontSize: 9.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              // El estado sólo se rotula cuando la acción no lo dice ya: con
              // «Pagar» debajo, un chip «Por pagar» es la misma frase dos
              // veces.
              if (!hasAction)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tone.soft,
                    borderRadius: BorderRadius.circular(PayrollTokens.rPill),
                    border: Border.all(color: tone.border),
                  ),
                  child: Text(
                    vm.statusMeta.isEmpty
                        ? vm.statusLabel
                        : '${vm.statusLabel} ${vm.statusMeta}',
                    style: visual.labelStrong.copyWith(
                      fontSize: 9.5,
                      color: tone.fg,
                    ),
                  ),
                ),
              const Spacer(),
              Semantics(
                key: ValueKey<String>(
                  'payroll-mobile-person-detail-toggle-${vm.name}',
                ),
                button: true,
                expanded: vm.expanded,
                label: '$disclosureLabel de nómina de ${vm.name}',
                hint: 'Muestra horas, tarifa y pagos registrados',
                excludeSemantics: true,
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(PayrollTokens.rField),
                  child: InkWell(
                    onTap: vm.onToggle,
                    mouseCursor: SystemMouseCursors.click,
                    borderRadius: BorderRadius.circular(PayrollTokens.rField),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            disclosureLabel,
                            style: visual.label.copyWith(color: visual.accent),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            vm.expanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: visual.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (vm.expanded) ...[
            const SizedBox(height: 8),
            Divider(height: 1, color: visual.border),
            Padding(
              key: ValueKey<String>(
                'payroll-mobile-person-detail-${vm.name}',
              ),
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                children: [
                  factRow(label: 'Total de la semana', value: vm.earned),
                  factRow(label: 'Anticipos aplicados', value: vm.advances),
                  factRow(label: 'A pagar', value: vm.newMoney),
                  factRow(
                    label: 'Horas y tarifa',
                    value: '${vm.hours} · ${vm.rate}',
                  ),
                  factRow(
                    label: 'Pagos registrados',
                    value: vm.paymentsSummary,
                  ),
                ],
              ),
            ),
          ],
          if (hasAction) ...[
            const SizedBox(height: 11),
            if (vm.status == PayrollRowStatus.pendingTransfer)
              PayrollAccentAction(
                actionKey: ValueKey<String>(
                  'payroll-mobile-person-action-${vm.name}',
                ),
                label: pending
                    ? '${vm.actionLabel} ${vm.newMoney}'
                    : 'Ver respaldo del pago',
                semanticLabel: '${vm.actionLabel} para ${vm.name}',
                onTap: vm.onAction,
                height: 50,
                fontSize: 13,
                borderRadius: 11,
              )
            else
              Semantics(
                button: true,
                label: vm.actionMode == PayrollRowActionMode.paidDetails
                    ? 'Ver respaldo de pago de ${vm.name}'
                    : '${vm.actionLabel} para ${vm.name}',
                child: Material(
                  color: vm.actionMode == PayrollRowActionMode.paidDetails
                      ? visual.successSoft
                      : visual.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                    side: BorderSide(
                      color: vm.actionMode == PayrollRowActionMode.paidDetails
                          ? visual.successBorder
                          : visual.borderStrong,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey<String>(
                      'payroll-mobile-person-action-${vm.name}',
                    ),
                    onTap: vm.onAction,
                    mouseCursor: SystemMouseCursors.click,
                    child: SizedBox(
                      height: 50,
                      child: Center(
                        child: Text(
                          pending
                              ? '${vm.actionLabel} ${vm.newMoney}'
                              : 'Ver respaldo del pago',
                          style: visual.labelStrong.copyWith(
                            fontSize: 13,
                            color: vm.actionMode ==
                                    PayrollRowActionMode.paidDetails
                                ? visual.successFg
                                : visual.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MobileMoneyBar extends StatelessWidget {
  const _MobileMoneyBar({
    required this.totals,
    required this.onConfirmWeek,
    required this.onNextAction,
  });

  final PayrollWeekTotalsVM totals;
  final VoidCallback onConfirmWeek;
  final VoidCallback onNextAction;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final hasNextAction = totals.nextActionLabel.isNotEmpty;
    final actionLabel =
        hasNextAction ? totals.nextActionLabel : 'Confirmar semana';
    final actionEnabled = hasNextAction || totals.canConfirm;
    final showAction = hasNextAction || totals.showCommitAction;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 10, 13, 12),
      decoration: BoxDecoration(
        color: visual.surface,
        border: Border(top: BorderSide(color: visual.borderStrong)),
        boxShadow: visual.moneyBar,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('FALTA', style: visual.overline),
                const SizedBox(width: 8),
                Text(totals.remaining,
                    style: visual.numBar.copyWith(fontSize: 19)),
                const Spacer(),
                // La razón del bloqueo baja bajo el CTA cuando hay CTA (5l):
                // ahí explica el botón que se está mirando. Sin CTA se queda
                // arriba, que es el único lugar donde cabe.
                if (!actionEnabled && !showAction)
                  Flexible(
                    child: Text(
                      totals.blockedReason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: visual.bodyS.copyWith(
                        fontSize: 10,
                        color: visual.warningFg,
                      ),
                    ),
                  ),
              ],
            ),
            if (showAction) ...[
              const SizedBox(height: 10),
              PayrollAccentAction(
                actionKey: const ValueKey('payroll-mobile-primary-action'),
                label: actionLabel,
                onTap: hasNextAction ? onNextAction : onConfirmWeek,
                enabled: actionEnabled,
                height: PayrollTokens.touchMobile,
                fontSize: 12.5,
                disabledStyle: PayrollAccentDisabledStyle.sunkenBordered,
              ),
              if (!actionEnabled && totals.blockedReason.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  totals.blockedReason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: visual.bodyS.copyWith(
                    fontSize: 10,
                    color: visual.warningFg,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
