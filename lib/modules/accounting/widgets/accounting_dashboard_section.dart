import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, Supabase;

import '../../../shared/models/product.dart' as shared_product;
import '../../../shared/models/current_user_profile.dart';
import '../../../shared/services/current_user_profile_service.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/services/inventory_service.dart' as shared_inventory;
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_date_range_picker.dart';
import '../../../shared/widgets/vb_money_text.dart';
import '../../sales/models/sales_models.dart';
import '../../sales/services/sales_service.dart';
import '../models/dashboard_metrics.dart';
import '../models/period_detail_breakdown.dart';
import '../services/financial_projection_refresh_coordinator.dart';
import '../services/financial_reports_service.dart';
import 'period_detail_view.dart';

enum _AccountingBasis { cash, accrual }

enum _ExpenseBreakdownRange {
  currentMonth,
  previousMonth,
  last3Months,
  last6Months,
  last12Months,
}

extension on _ExpenseBreakdownRange {
  String get label {
    switch (this) {
      case _ExpenseBreakdownRange.currentMonth:
        return 'Mes actual';
      case _ExpenseBreakdownRange.previousMonth:
        return 'Mes anterior';
      case _ExpenseBreakdownRange.last3Months:
        return 'Últimos 3 meses';
      case _ExpenseBreakdownRange.last6Months:
        return 'Últimos 6 meses';
      case _ExpenseBreakdownRange.last12Months:
        return 'Últimos 12 meses';
    }
  }
}

const String _periodLast7Days = 'Últimos 7 días';
const String _periodCurrentWeek = 'Esta semana';
const String _periodCurrentMonth = 'Mes actual';
const String _periodPreviousMonth = 'Mes anterior';
const String _periodCurrentYear = 'Año actual';

class _DashboardDateRange {
  final DateTime start;
  final DateTime end;
  final bool isDaily;
  final int months;

  const _DashboardDateRange({
    required this.start,
    required this.end,
    required this.isDaily,
    required this.months,
  });
}

class _DashboardQuery {
  const _DashboardQuery({
    required this.basis,
    required this.period,
    required this.breakdownRange,
    required this.projectionRevision,
    required this.coordinator,
    required this.tenantId,
    required this.actor,
  });

  final _AccountingBasis basis;
  final String period;
  final _ExpenseBreakdownRange breakdownRange;
  final int projectionRevision;
  final FinancialProjectionRefreshCoordinator coordinator;
  final String? tenantId;
  final String? actor;
}

const int _maxBreakdownSlices = 8;
const String _otherBreakdownKey = '__other__';

String _compactSpanishWeekdayDate(DateTime date) {
  final weekday = DateFormat('EEE', 'es_CL').format(date).replaceAll('.', '');
  final day = DateFormat('d', 'es_CL').format(date);
  final monthRaw = DateFormat('MMM', 'es_CL').format(date).replaceAll('.', '');
  final month = monthRaw.isEmpty
      ? monthRaw
      : '${monthRaw[0].toUpperCase()}${monthRaw.substring(1)}';

  return '$weekday $day $month';
}

String _expenseBreakdownKeyForDetail(PeriodDetailItem item) {
  if (item.sourceType == 'purchase_payment') {
    return 'purchase_payment';
  }
  if (item.accountId != null && item.accountId!.isNotEmpty) {
    return 'account:${item.accountId!}';
  }
  if (item.accountCode != null && item.accountCode!.isNotEmpty) {
    return 'code:${item.accountCode!}';
  }
  return '${item.sourceType}:${item.secondaryText.trim()}';
}

String _expenseBreakdownCodeForDetail(PeriodDetailItem item) {
  if (item.sourceType == 'purchase_payment') {
    return '5000';
  }
  return item.accountCode ?? '';
}

String _expenseBreakdownNameForDetail(PeriodDetailItem item) {
  if (item.sourceType == 'purchase_payment') {
    return 'Pagos a Proveedores';
  }

  final label = item.secondaryText.trim();
  if (label.isNotEmpty) {
    return label;
  }

  return 'Sin clasificar';
}

class _ExpenseBreakdownAggregate {
  final String key;
  final String code;
  final String name;
  double amount;

  _ExpenseBreakdownAggregate({
    required this.key,
    required this.code,
    required this.name,
    required this.amount,
  });
}

class AccountingDashboardSection extends StatefulWidget {
  const AccountingDashboardSection({
    super.key,
    this.refreshCoordinator,
  });

  final FinancialProjectionRefreshCoordinator? refreshCoordinator;

  /// Test/manual reset hook. Business writers publish through the financial
  /// projection coordinator instead of importing this widget.
  static void invalidateCache() {
    _AccountingDashboardSectionState._cachedData = null;
    _AccountingDashboardSectionState._cacheTimestamp = null;
    _AccountingDashboardSectionState._cachedProjectionRevision = null;
    _AccountingDashboardSectionState._cachedCoordinator = null;
    _AccountingDashboardSectionState._cachedTenantId = null;
    _AccountingDashboardSectionState._cachedActor = null;
  }

  @override
  State<AccountingDashboardSection> createState() =>
      _AccountingDashboardSectionState();
}

class _AccountingDashboardSectionState
    extends State<AccountingDashboardSection> {
  // UI State
  _AccountingBasis _basis = _AccountingBasis.cash;
  String _selectedPeriod = 'Últimos 12 meses';
  _ExpenseBreakdownRange _breakdownRange = _ExpenseBreakdownRange.currentMonth;

  // Data State
  _DashboardPayload? _data;
  bool _isLoading = true;
  // Sin autoridad contable la base niega con 42501 (can_manage_tenant_accounting);
  // el panel no lo pide ni ofrece un «Reintentar» que nunca funcionará.
  bool _accessDenied = false;
  String? _error;
  FinancialProjectionRefreshCoordinator? _refreshCoordinator;
  StreamSubscription<FinancialProjectionRefreshSignal>? _refreshSubscription;
  Future<void>? _activeRefresh;
  bool _refreshPending = false;
  bool _surfaceActive = true;
  // Quién mira: si cambia (otra cuenta, otra autoridad) lo cargado se descarta.
  String? _boundActor;
  bool _actorBound = false;

  // Static cache - persists across widget rebuilds
  static _DashboardPayload? _cachedData;
  static DateTime? _cacheTimestamp;
  static String? _cachedPeriod;
  static _AccountingBasis? _cachedBasis;
  static _ExpenseBreakdownRange? _cachedBreakdownRange;
  static int? _cachedProjectionRevision;
  static FinancialProjectionRefreshCoordinator? _cachedCoordinator;
  static String? _cachedTenantId;
  // La caché es de un actor: lo que cargó un administrador no se le sirve a
  // un mecánico del mismo taller en el mismo equipo.
  static String? _cachedActor;
  static const Duration _cacheDuration = Duration(minutes: 5);

  static const Map<String, int> _periodToMonths = {
    'Últimos 6 meses': 6,
    'Últimos 12 meses': 12,
    'Últimos 18 meses': 18,
    'Últimos 24 meses': 24,
  };

  static const List<String> _periodOptions = [
    _periodLast7Days,
    _periodCurrentWeek,
    _periodCurrentMonth,
    _periodPreviousMonth,
    _periodCurrentYear,
    'Últimos 6 meses',
    'Últimos 12 meses',
    'Últimos 18 meses',
    'Últimos 24 meses',
  ];

  static const List<_ExpenseBreakdownRange> _breakdownOptions = [
    _ExpenseBreakdownRange.currentMonth,
    _ExpenseBreakdownRange.previousMonth,
    _ExpenseBreakdownRange.last3Months,
    _ExpenseBreakdownRange.last6Months,
    _ExpenseBreakdownRange.last12Months,
  ];

  @override
  void initState() {
    super.initState();
    // Keep the first frame lightweight, then start only the two read models
    // actually rendered by this dashboard surface.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final nextCoordinator = widget.refreshCoordinator ??
        FinancialProjectionRefreshCoordinator.fallback;
    _bindRefreshCoordinator(nextCoordinator);
    _bindActor(_actorKey(listen: true));

    final wasActive = _surfaceActive;
    _surfaceActive = TickerMode.of(context);
    if (!wasActive && _surfaceActive && _refreshPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestRefresh();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AccountingDashboardSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bindRefreshCoordinator(
      widget.refreshCoordinator ??
          FinancialProjectionRefreshCoordinator.fallback,
    );
  }

  @override
  void dispose() {
    unawaited(_refreshSubscription?.cancel());
    _refreshSubscription = null;
    super.dispose();
  }

  void _bindRefreshCoordinator(
    FinancialProjectionRefreshCoordinator coordinator,
  ) {
    if (identical(coordinator, _refreshCoordinator)) return;
    final hadCoordinator = _refreshCoordinator != null;
    unawaited(_refreshSubscription?.cancel());
    _refreshCoordinator = coordinator;
    _refreshSubscription = coordinator.signals.listen(
      _onProjectionChanged,
    );

    if (!hadCoordinator) return;
    AccountingDashboardSection.invalidateCache();
    _refreshPending = true;
    if (mounted) {
      setState(() {
        _data = null;
        _isLoading = true;
        _error = null;
        _accessDenied = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _requestRefresh();
      });
    }
  }

  void _onProjectionChanged(FinancialProjectionRefreshSignal signal) {
    if (signal.changes.contains(FinancialProjectionChangeKind.tenantScope)) {
      // A prior tenant's projection must never remain visible while the new
      // tenant is loading.
      AccountingDashboardSection.invalidateCache();
      if (mounted) {
        setState(() {
          _data = null;
          _isLoading = true;
          _error = null;
          _accessDenied = false;
        });
      }
    }
    _refreshPending = true;
    _requestRefresh();
  }

  /// Otra cuenta u otra autoridad en el mismo panel: nada de lo cargado ni de
  /// la negativa anterior sigue valiendo; se vuelve a decidir con el actor
  /// nuevo.
  void _bindActor(String? actor) {
    if (!_actorBound) {
      _actorBound = true;
      _boundActor = actor;
      return;
    }
    if (actor == _boundActor) return;
    _boundActor = actor;
    AccountingDashboardSection.invalidateCache();
    _data = null;
    _isLoading = true;
    _error = null;
    _accessDenied = false;
    _refreshPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestRefresh();
    });
  }

  void _loadInitialData() {
    if (!mounted) return;
    if (!_surfaceActive) {
      _refreshPending = true;
      return;
    }

    // La autoridad se valida antes de mirar la caché.
    if (_deniedByKnownProfile()) return;

    final coordinator =
        _refreshCoordinator ?? FinancialProjectionRefreshCoordinator.fallback;
    final projectionRevision = coordinator.revision;
    final actor = _actorKey();
    // Check if we have valid cached data
    final isCacheValid = actor != null &&
        _cachedActor == actor &&
        _cachedData != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < _cacheDuration &&
        _cachedPeriod == _selectedPeriod &&
        _cachedBasis == _basis &&
        _cachedBreakdownRange == _breakdownRange &&
        _cachedProjectionRevision == projectionRevision &&
        identical(_cachedCoordinator, coordinator) &&
        _cachedTenantId == coordinator.tenantId;

    if (isCacheValid) {
      // Use cached data immediately - no network request!
      setState(() {
        _data = _cachedData;
        _isLoading = false;
        _error = null;
        _accessDenied = false;
      });
    } else {
      // Need to fetch fresh data
      _requestRefresh();
    }
  }

  void _onBasisChanged(_AccountingBasis newValue) {
    if (_basis != newValue) {
      setState(() {
        _basis = newValue;
      });
      _refreshPending = true;
      _requestRefresh();
    }
  }

  void _onPeriodChanged(String? newValue) {
    if (newValue != null && _selectedPeriod != newValue) {
      setState(() {
        _selectedPeriod = newValue;
      });
      _refreshPending = true;
      _requestRefresh();
    }
  }

  void _onBreakdownRangeChanged(_ExpenseBreakdownRange newValue) {
    if (_breakdownRange != newValue) {
      setState(() {
        _breakdownRange = newValue;
      });
      _refreshPending = true;
      _requestRefresh();
    }
  }

  DateTime _exclusiveBreakdownEnd(DateTime inclusiveEnd) {
    return inclusiveEnd.add(const Duration(seconds: 1));
  }

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59);
  }

  DateTime _endOfMonth(int year, int month) {
    return DateTime(year, month + 1, 0, 23, 59, 59);
  }

  _DashboardDateRange _dateRangeForPeriod(String period, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);

    switch (period) {
      case _periodLast7Days:
        final start = today.subtract(const Duration(days: 6));
        return _DashboardDateRange(
          start: start,
          end: _endOfDay(today),
          isDaily: true,
          months: 1,
        );
      case _periodCurrentWeek:
        final start = today.subtract(Duration(days: now.weekday - 1));
        return _DashboardDateRange(
          start: start,
          end: _endOfDay(start.add(const Duration(days: 6))),
          isDaily: true,
          months: 1,
        );
      case _periodCurrentMonth:
        return _DashboardDateRange(
          start: DateTime(now.year, now.month, 1),
          end: _endOfMonth(now.year, now.month),
          isDaily: true,
          months: 1,
        );
      case _periodPreviousMonth:
        final previousMonthEnd = DateTime(now.year, now.month, 0);
        return _DashboardDateRange(
          start: DateTime(previousMonthEnd.year, previousMonthEnd.month, 1),
          end: _endOfDay(previousMonthEnd),
          isDaily: true,
          months: 1,
        );
      case _periodCurrentYear:
        return _DashboardDateRange(
          start: DateTime(now.year, 1, 1),
          end: _endOfMonth(now.year, now.month),
          isDaily: false,
          months: now.month,
        );
      default:
        final months = _periodToMonths[period] ?? 12;
        return _DashboardDateRange(
          start: DateTime(now.year, now.month - months + 1, 1),
          end: _endOfMonth(now.year, now.month),
          isDaily: false,
          months: months,
        );
    }
  }

  List<ExpenseBreakdownItem> _buildExpenseBreakdown(
    List<PeriodDetailItem> detailItems,
  ) {
    if (detailItems.isEmpty) {
      return const [];
    }

    final grouped = <String, _ExpenseBreakdownAggregate>{};

    for (final item in detailItems) {
      final key = _expenseBreakdownKeyForDetail(item);
      final aggregate = grouped.putIfAbsent(
        key,
        () => _ExpenseBreakdownAggregate(
          key: key,
          code: _expenseBreakdownCodeForDetail(item),
          name: _expenseBreakdownNameForDetail(item),
          amount: 0,
        ),
      );
      aggregate.amount += item.amount.abs();
    }

    final sorted = grouped.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    if (sorted.length <= _maxBreakdownSlices) {
      return sorted
          .map(
            (entry) => ExpenseBreakdownItem(
              accountId: entry.key,
              accountCode: entry.code,
              accountName: entry.name,
              amount: entry.amount,
              breakdownKey: entry.key,
            ),
          )
          .toList();
    }

    const topCount = _maxBreakdownSlices - 1;
    final topItems = sorted.take(topCount).toList();
    final otherAmount = sorted
        .skip(topCount)
        .fold<double>(0, (sum, entry) => sum + entry.amount);

    return [
      ...topItems.map(
        (entry) => ExpenseBreakdownItem(
          accountId: entry.key,
          accountCode: entry.code,
          accountName: entry.name,
          amount: entry.amount,
          breakdownKey: entry.key,
        ),
      ),
      ExpenseBreakdownItem(
        accountId: _otherBreakdownKey,
        accountCode: '',
        accountName: 'Otros',
        amount: otherAmount,
        breakdownKey: _otherBreakdownKey,
        isOther: true,
      ),
    ];
  }

  void _requestRefresh() {
    if (!mounted) return;
    if (!_surfaceActive) {
      _refreshPending = true;
      return;
    }
    if (_activeRefresh != null) {
      _refreshPending = true;
      return;
    }

    _refreshPending = false;
    final refresh = _runRefresh();
    _activeRefresh = refresh;
    unawaited(
      refresh.whenComplete(() {
        if (!mounted) return;
        _activeRefresh = null;
        if (_refreshPending) {
          _requestRefresh();
        }
      }),
    );
  }

  Future<void> _runRefresh() async {
    if (!mounted) return;
    final coordinator =
        _refreshCoordinator ?? FinancialProjectionRefreshCoordinator.fallback;
    final query = _DashboardQuery(
      basis: _basis,
      period: _selectedPeriod,
      breakdownRange: _breakdownRange,
      projectionRevision: coordinator.revision,
      coordinator: coordinator,
      tenantId: coordinator.tenantId,
      actor: _actorKey(),
    );

    if (_deniedByKnownProfile()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    Object? finalError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final newData = await _fetchData(query);
        if (!mounted) return;

        if (!_isCurrent(query) || !_surfaceActive) {
          _refreshPending = true;
          return;
        }

        _cachedData = newData;
        _cacheTimestamp = DateTime.now();
        _cachedPeriod = query.period;
        _cachedBasis = query.basis;
        _cachedBreakdownRange = query.breakdownRange;
        _cachedProjectionRevision = query.projectionRevision;
        _cachedCoordinator = query.coordinator;
        _cachedTenantId = query.tenantId;
        _cachedActor = query.actor;

        setState(() {
          _data = newData;
          _isLoading = false;
          _error = null;
          _accessDenied = false;
        });
        return;
      } catch (error) {
        if (error is PostgrestException && error.code == '42501') {
          if (!mounted) return;
          // La negativa es del actor que preguntó; si ya es otro, se vuelve
          // a preguntar por él.
          if (query.actor != _actorKey()) {
            _refreshPending = true;
            return;
          }
          _showAccessDenied();
          return;
        }
        finalError = error;
        final errorText = error.toString();
        final transient = errorText.contains('HandshakeException') ||
            errorText.contains('Connection terminated');
        if (!transient || attempt == 2) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
      }
    }

    if (!mounted) return;
    if (!_isCurrent(query) || !_surfaceActive) {
      _refreshPending = true;
      return;
    }
    // El detalle técnico va al registro; el operador lee qué hacer.
    debugPrint('Accounting dashboard load failed: $finalError');
    setState(() {
      _error = finalError?.toString() ?? 'Error desconocido';
      _isLoading = false;
    });
  }

  bool _isCurrent(_DashboardQuery query) =>
      query.basis == _basis &&
      query.period == _selectedPeriod &&
      query.breakdownRange == _breakdownRange &&
      identical(query.coordinator, _refreshCoordinator) &&
      query.tenantId == _refreshCoordinator?.tenantId &&
      query.projectionRevision == (_refreshCoordinator?.revision ?? 0) &&
      query.actor == _actorKey();

  /// El perfil conocido sin autoridad contable: no se pide nada ni se muestra
  /// lo que haya cargado otro.
  bool _deniedByKnownProfile() {
    final profile = _knownProfile();
    if (profile == null || profile.canAccessAccounting) return false;
    _showAccessDenied();
    return true;
  }

  void _showAccessDenied() {
    AccountingDashboardSection.invalidateCache();
    setState(() {
      _accessDenied = true;
      _data = null;
      _isLoading = false;
      _error = null;
    });
  }

  /// El perfil del operador, si el host lo monta. Sin él, la negación 42501
  /// de la base sigue llevando al mismo estado sin acceso.
  CurrentUserProfile? _knownProfile({bool listen = false}) {
    try {
      return Provider.of<CurrentUserProfileService>(context, listen: listen)
          .profile;
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Quién pide y con qué autoridad: la cuenta del perfil, o la de la sesión
  /// si el host no monta el perfil. Sin ninguna no hay llave y la caché no se
  /// reutiliza.
  String? _actorKey({bool listen = false}) {
    final profile = _knownProfile(listen: listen);
    if (profile != null) {
      return '${profile.userId}|${profile.canAccessAccounting}';
    }
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      return userId == null ? null : '$userId|?';
    } catch (_) {
      return null;
    }
  }

  Future<_DashboardPayload> _fetchData(_DashboardQuery query) async {
    final reportsService = context.read<FinancialReportsService>();
    final isCashFlow = query.basis == _AccountingBasis.cash;
    final now = DateTime.now();
    final selectedRange = _dateRangeForPeriod(query.period, now);

    // Breakdown Logic
    final currentMonthStart = DateTime(now.year, now.month);
    final previousMonthEnd =
        currentMonthStart.subtract(const Duration(days: 1));

    DateTime breakdownStart;
    DateTime breakdownEnd;
    switch (query.breakdownRange) {
      case _ExpenseBreakdownRange.currentMonth:
        breakdownStart = currentMonthStart;
        breakdownEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        break;
      case _ExpenseBreakdownRange.previousMonth:
        breakdownStart =
            DateTime(previousMonthEnd.year, previousMonthEnd.month);
        breakdownEnd = DateTime(previousMonthEnd.year, previousMonthEnd.month,
            previousMonthEnd.day, 23, 59, 59);
        break;
      case _ExpenseBreakdownRange.last3Months:
        breakdownStart = DateTime(now.year, now.month - 2, 1);
        breakdownEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case _ExpenseBreakdownRange.last6Months:
        breakdownStart = DateTime(now.year, now.month - 5, 1);
        breakdownEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case _ExpenseBreakdownRange.last12Months:
        breakdownStart = DateTime(now.year, now.month - 11, 1);
        breakdownEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
    }

    // These projections are independent. Start both before awaiting either so
    // first paint costs the slower query, rather than the sum of both.
    final Future<List<MonthlyIncomeExpensePoint>> seriesFuture =
        selectedRange.isDaily
            ? reportsService.getIncomeExpenseDailyTimeseries(
                startDate: selectedRange.start,
                endDate: selectedRange.end,
                isCashFlow: isCashFlow,
              )
            : reportsService.getIncomeExpenseTimeseries(
                months: selectedRange.months,
                isCashFlow: isCashFlow,
              );
    final breakdownDetailsFuture = reportsService.getExpensePeriodDetails(
      startDate: breakdownStart,
      endDate: _exclusiveBreakdownEnd(breakdownEnd),
      isCashFlow: isCashFlow,
    );
    final projections = await Future.wait<Object>([
      seriesFuture,
      breakdownDetailsFuture,
    ]);
    final series = projections[0] as List<MonthlyIncomeExpensePoint>;
    final breakdownDetails = projections[1] as List<PeriodDetailItem>;

    final breakdown = _buildExpenseBreakdown(breakdownDetails);

    final totalIncome =
        series.fold<double>(0, (sum, point) => sum + point.income);
    final totalExpense =
        series.fold<double>(0, (sum, point) => sum + point.expense);
    final breakdownTotal = breakdownDetails.fold<double>(
      0,
      (sum, item) => sum + item.amount.abs(),
    );

    final rangeStart =
        series.isNotEmpty ? series.first.periodStart : selectedRange.start;
    final rangeEnd =
        series.isNotEmpty ? series.last.periodEnd : selectedRange.end;

    return _DashboardPayload(
      series: series,
      expenseBreakdown: breakdown,
      trailingLabel: query.breakdownRange.label,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      months: selectedRange.months,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      breakdownRange: query.breakdownRange,
      breakdownStart: breakdownStart,
      breakdownEnd: breakdownEnd,
      breakdownTotal: breakdownTotal,
      breakdownDetails: breakdownDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_accessDenied) return const _DashboardNoAccess();

    // 1. Initial loading (no data yet)
    if (_data == null) {
      if (_isLoading) return const _DashboardSkeleton();
      if (_error != null) {
        return _DashboardError(
          error: _error,
          onRetry: _requestRefresh,
        );
      }
    }

    // 2. Data loaded but empty series (rare if data exists)
    final data = _data;
    if (data != null && data.series.isEmpty && !_isLoading) {
      return _DashboardEmpty(onRetry: _requestRefresh);
    }

    // 3. Show content (or loading overlay if refreshing)
    // Safe because if _data is null here, we would have returned above unless error logic failed
    if (data == null) return const SizedBox.shrink();

    final dashboard = Stack(
      children: [
        _DashboardContent(
          data: data,
          basis: _basis,
          onBasisChanged: _onBasisChanged,
          selectedPeriod: _selectedPeriod,
          periodOptions: _periodOptions,
          onPeriodChanged: _onPeriodChanged,
          onRefresh: _requestRefresh,
          selectedBreakdownRange: _breakdownRange,
          breakdownOptions: _breakdownOptions,
          onBreakdownRangeChanged: _onBreakdownRangeChanged,
        ),
        if (_isLoading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 4,
            child: LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              color:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
      ],
    );

    if (_error == null) return dashboard;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DashboardRefreshWarning(onRetry: _requestRefresh),
        const SizedBox(height: 8),
        dashboard,
      ],
    );
  }
}

class _DashboardPayload {
  final List<MonthlyIncomeExpensePoint> series;
  final List<ExpenseBreakdownItem> expenseBreakdown;
  final List<PeriodDetailItem> breakdownDetails;
  final String trailingLabel;
  final double totalIncome;
  final double totalExpense;
  final int months;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final _ExpenseBreakdownRange breakdownRange;
  final DateTime breakdownStart;
  final DateTime breakdownEnd;
  final double breakdownTotal;

  const _DashboardPayload({
    required this.series,
    required this.expenseBreakdown,
    required this.breakdownDetails,
    required this.trailingLabel,
    required this.totalIncome,
    required this.totalExpense,
    required this.months,
    required this.rangeStart,
    required this.rangeEnd,
    required this.breakdownRange,
    required this.breakdownStart,
    required this.breakdownEnd,
    required this.breakdownTotal,
  });

  double get totalNet => totalIncome - totalExpense;
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1000;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: isWide ? 3 : 1,
              child: _SkeletonCard(color: color, height: 320),
            ),
            if (isWide) const SizedBox(width: 16) else const SizedBox(width: 0),
            Expanded(
              flex: isWide ? 2 : 1,
              child: Column(
                children: [
                  _SkeletonCard(color: color, height: 320),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  final Color color;
  final double height;

  const _SkeletonCard({required this.color, required this.height});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// El panorama financiero es de quien administra la contabilidad del taller.
/// Otro rol ve por qué no está, sin error ni reintento.
class _DashboardNoAccess extends StatelessWidget {
  const _DashboardNoAccess();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      key: const ValueKey('accounting-dashboard-no-access'),
      color: colors.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, color: colors.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Panorama financiero',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Lo ve quien administra la contabilidad del taller.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  final Object? error;
  final VoidCallback onRetry;

  const _DashboardError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No pudimos cargar los datos contables',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Revisa la conexión e inténtalo de nuevo.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardRefreshWarning extends StatelessWidget {
  const _DashboardRefreshWarning({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      label:
          'Los gráficos conservan los últimos datos válidos. No se pudo actualizar.',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.errorContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 14,
            end: 4,
            top: 4,
            bottom: 4,
          ),
          child: Row(
            children: [
              Icon(
                Icons.sync_problem_outlined,
                size: 18,
                color: colors.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Datos sin actualizar. Conservamos la última lectura válida.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onErrorContainer,
                      ),
                ),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardEmpty extends StatelessWidget {
  final VoidCallback onRetry;

  const _DashboardEmpty({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.bar_chart,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Aún no hay movimientos contables para graficar',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Actualizar',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Registra ventas, compras o asientos manuales para visualizar tendencias reales.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  final _DashboardPayload data;
  final String selectedPeriod;
  final List<String> periodOptions;
  final ValueChanged<String?> onPeriodChanged;
  final _AccountingBasis basis;
  final ValueChanged<_AccountingBasis> onBasisChanged;
  final VoidCallback onRefresh;
  final _ExpenseBreakdownRange selectedBreakdownRange;
  final List<_ExpenseBreakdownRange> breakdownOptions;
  final ValueChanged<_ExpenseBreakdownRange> onBreakdownRangeChanged;

  const _DashboardContent({
    required this.data,
    required this.selectedPeriod,
    required this.periodOptions,
    required this.onPeriodChanged,
    required this.basis,
    required this.onBasisChanged,
    required this.onRefresh,
    required this.selectedBreakdownRange,
    required this.breakdownOptions,
    required this.onBreakdownRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 1080;
        // The compact composition needs extra vertical room because its
        // controls and summaries wrap instead of competing for touch width.
        final chartHeight = constraints.maxWidth < 600 ? 520.0 : 400.0;

        final charts = isWide
            ? IntrinsicHeight(
                // This ensures both cards have the same height
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6, // Slightly more width for bar chart
                      child: _IncomeExpenseCard(
                        data: data.series,
                        chartHeight: chartHeight,
                        basis: basis,
                        onBasisChanged: onBasisChanged,
                        selectedPeriod: selectedPeriod,
                        periodOptions: periodOptions,
                        onPeriodChanged: onPeriodChanged,
                        totalIncome: data.totalIncome,
                        totalExpense: data.totalExpense,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5, // Good space for pie chart
                      child: _ExpenseBreakdownCard(
                        items: data.expenseBreakdown,
                        details: data.breakdownDetails,
                        chartHeight: chartHeight,
                        basis: basis,
                        breakdownRange: selectedBreakdownRange,
                        rangeLabel: data.trailingLabel,
                        breakdownOptions: breakdownOptions,
                        onRangeChanged: onBreakdownRangeChanged,
                        totalAmount: data.breakdownTotal,
                        rangeStart: data.breakdownStart,
                        rangeEnd: data.breakdownEnd,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IncomeExpenseCard(
                    data: data.series,
                    chartHeight: chartHeight,
                    basis: basis,
                    onBasisChanged: onBasisChanged,
                    selectedPeriod: selectedPeriod,
                    periodOptions: periodOptions,
                    onPeriodChanged: onPeriodChanged,
                    totalIncome: data.totalIncome,
                    totalExpense: data.totalExpense,
                  ),
                  const SizedBox(height: 16),
                  _ExpenseBreakdownCard(
                    items: data.expenseBreakdown,
                    details: data.breakdownDetails,
                    chartHeight: chartHeight,
                    basis: basis,
                    breakdownRange: selectedBreakdownRange,
                    rangeLabel: data.trailingLabel,
                    breakdownOptions: breakdownOptions,
                    onRangeChanged: onBreakdownRangeChanged,
                    totalAmount: data.breakdownTotal,
                    rangeStart: data.breakdownStart,
                    rangeEnd: data.breakdownEnd,
                  ),
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            charts,
            const SizedBox(height: 16),
            _DashboardHeader(
              totalIncome: data.totalIncome,
              totalExpense: data.totalExpense,
              totalNet: data.totalNet,
              onRefresh: onRefresh,
              selectedPeriod: selectedPeriod,
            ),
          ],
        );
      },
    );
  }
}

class _DashboardHeader extends StatefulWidget {
  final double totalIncome;
  final double totalExpense;
  final double totalNet;
  final VoidCallback onRefresh;
  final String selectedPeriod;

  const _DashboardHeader({
    required this.totalIncome,
    required this.totalExpense,
    required this.totalNet,
    required this.onRefresh,
    required this.selectedPeriod,
  });

  @override
  State<_DashboardHeader> createState() => _DashboardHeaderState();
}

class _DashboardHeaderState extends State<_DashboardHeader> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    String formatCLP(double value) {
      final formatter = NumberFormat.currency(locale: 'es_CL', symbol: 'CLP');
      return formatter.format(value.round());
    }

    final netColor = widget.totalNet >= 0
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Resumen contable (${widget.selectedPeriod})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: widget.onRefresh,
                    tooltip: 'Actualizar datos',
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _StatChip(
                    label: 'Total de ingresos',
                    value: formatCLP(widget.totalIncome),
                    color: const Color(0xFF1B5E20),
                    icon: Icons.trending_up,
                  ),
                  _StatChip(
                    label: 'Total de gastos',
                    value: formatCLP(widget.totalExpense),
                    color: const Color(0xFFB71C1C),
                    icon: Icons.trending_down,
                  ),
                  _StatChip(
                    label: 'Resultado neto',
                    value: formatCLP(widget.totalNet),
                    color: netColor,
                    icon: widget.totalNet >= 0
                        ? Icons.stacked_line_chart
                        : Icons.warning,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartPeriodSelector extends StatelessWidget {
  final String selectedPeriod;
  final List<String> options;
  final ValueChanged<String?>? onChanged;

  const _ChartPeriodSelector({
    required this.selectedPeriod,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return PopupMenuButton<String>(
      tooltip: 'Cambiar rango del gráfico',
      enabled: onChanged != null,
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          child: Text('Rango del gráfico'),
        ),
        const PopupMenuDivider(height: 8),
        for (final option in options)
          PopupMenuItem<String>(
            value: option,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: selectedPeriod == option
                      ? Icon(Icons.check_rounded, size: 17, color: color)
                      : const SizedBox.shrink(),
                ),
                Expanded(child: Text(option)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                Theme.of(context).colorScheme.outline.withValues(alpha: 0.22),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month_rounded, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              selectedPeriod,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 17,
              color: Theme.of(context).hintColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        color: color.withValues(alpha: 0.05),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncomeExpenseCard extends StatefulWidget {
  final List<MonthlyIncomeExpensePoint> data;
  final double chartHeight;
  final _AccountingBasis basis;
  final ValueChanged<_AccountingBasis>? onBasisChanged;
  final String selectedPeriod;
  final List<String> periodOptions;
  final ValueChanged<String?>? onPeriodChanged;
  final double totalIncome;
  final double totalExpense;

  const _IncomeExpenseCard({
    required this.data,
    required this.chartHeight,
    required this.basis,
    this.onBasisChanged,
    required this.selectedPeriod,
    required this.periodOptions,
    required this.onPeriodChanged,
    required this.totalIncome,
    required this.totalExpense,
  });

  @override
  State<_IncomeExpenseCard> createState() => _IncomeExpenseCardState();
}

class _IncomeExpenseCardState extends State<_IncomeExpenseCard> {
  // Detalle de una barra. Abierto mientras haya un período.
  DateTimeRange? _detailRange;
  bool _showingIncome = true; // true = income, false = expense
  List<PeriodDetailItem>? _detailItems;
  bool _isLoadingDetails = false;
  bool _detailFailed = false;
  // Cada carga lleva su número: una respuesta lenta de un período anterior no
  // pisa la del período que el operador está mirando.
  int _detailRequest = 0;
  PeriodDetailMode _detailViewMode = PeriodDetailMode.movements;
  String? _selectedBucketKey;
  Set<DateTime> _expandedDays = const {};
  String? _selectedDetailKey;
  Invoice? _selectedInvoice;
  bool _isLoadingInvoiceDetails = false;
  String? _invoiceDetailError;
  Map<String, String?> _invoiceProductImagesById = const {};
  Map<String, String?> _invoiceProductImagesBySku = const {};

  bool get _detailOpen => _detailRange != null;

  PeriodDetailKind get _detailKind {
    final cash = widget.basis == _AccountingBasis.cash;
    if (_showingIncome) {
      return cash
          ? PeriodDetailKind.incomeCash
          : PeriodDetailKind.incomeAccrual;
    }
    return cash
        ? PeriodDetailKind.expenseCash
        : PeriodDetailKind.expenseAccrual;
  }

  @override
  void didUpdateWidget(covariant _IncomeExpenseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cambiar de caja a devengado cambia qué es un movimiento: el detalle
    // abierto se vuelve a pedir con la base nueva.
    final range = _detailRange;
    if (range != null && oldWidget.basis != widget.basis) {
      _changeDetailRange(range);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 24),
        child: Stack(
          children: [
            // Chart View - Always present to dictate size
            Visibility(
              visible: !_detailOpen,
              maintainState: true,
              maintainSize: true,
              maintainAnimation: true,
              child: _buildChartContent(context),
            ),
            // Detail View - Overlays the chart when active
            if (_detailOpen)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).cardColor,
                  child: _buildDetailView(context),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartContent(BuildContext context) {
    final displayData = widget.data;

    final maxValue = displayData
        .map((point) => math.max(point.income.abs(), point.expense.abs()))
        .fold<double>(0, (previous, value) => math.max(previous, value));

    final chartMax = _calculateChartMax(maxValue);
    final axisInterval = _calculateAxisInterval(chartMax);

    final double rodWidth =
        displayData.length > 20 ? 6 : (displayData.length > 10 ? 10 : 16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Ingresos vs gastos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _ChartPeriodSelector(
              selectedPeriod: widget.selectedPeriod,
              options: widget.periodOptions,
              onChanged: widget.onPeriodChanged,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.onBasisChanged != null)
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_AccountingBasis>(
              segments: const [
                ButtonSegment<_AccountingBasis>(
                  value: _AccountingBasis.cash,
                  label: Text('Efectivo'),
                  icon: Icon(Icons.money),
                ),
                ButtonSegment<_AccountingBasis>(
                  value: _AccountingBasis.accrual,
                  label: Text('Devengado'),
                  icon: Icon(Icons.receipt_long),
                ),
              ],
              selected: {widget.basis},
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity(horizontal: -3, vertical: -3),
              ),
              onSelectionChanged: (selection) {
                if (selection.isEmpty) return;
                final next = selection.first;
                if (next != widget.basis) {
                  widget.onBasisChanged?.call(next);
                }
              },
            ),
          ),
        const SizedBox(height: 8),
        Text(
          widget.basis == _AccountingBasis.cash
              ? (widget.data.isNotEmpty &&
                      widget.data[0].periodStart.day ==
                          widget.data[0].periodEnd.day
                  ? 'Flujo de efectivo real por día'
                  : 'Flujo de efectivo real por mes')
              : 'Ingresos y gastos devengados (facturados)',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).hintColor),
        ),
        const SizedBox(height: 4),
        Text(
          'Toca una barra para ver detalles',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontStyle: FontStyle.italic,
              ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: math.max(widget.chartHeight * 0.6, 200.0),
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              minY: 0,
              maxY: chartMax,
              gridData: FlGridData(
                show: true,
                drawHorizontalLine: true,
                drawVerticalLine: true,
                horizontalInterval: axisInterval,
                verticalInterval: 1,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.2),
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (value) => FlLine(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.12),
                  strokeWidth: 1,
                  dashArray: const [4, 4],
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: axisInterval,
                    getTitlesWidget: (value, meta) {
                      if (value < 0) {
                        return const SizedBox.shrink();
                      }
                      final formatter = NumberFormat.compact(
                        locale: 'es_CL',
                      )
                        ..maximumFractionDigits = 1
                        ..minimumFractionDigits = 0;
                      final formatted =
                          value == 0 ? '0' : formatter.format(value);
                      return Text(
                        '$formatted CLP',
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                    },
                    reservedSize: 72,
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) =>
                        _buildBottomTitle(context, value, displayData),
                    reservedSize: 42,
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < displayData.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: displayData[i].income,
                        color: const Color(0xFF4CAF50),
                        width: rodWidth,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                      BarChartRodData(
                        toY: displayData[i].expense,
                        color: const Color(0xFFFF5252),
                        width: rodWidth,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                    ],
                  ),
              ],
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  tooltipRoundedRadius: 12,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final formatter = NumberFormat.currency(
                      locale: 'es_CL',
                      symbol: 'CLP',
                    );
                    final label = rodIndex == 0 ? 'Ingresos' : 'Gastos';
                    return BarTooltipItem(
                      '${displayData[group.x.toInt()].periodLabel()}\n$label: ${formatter.format(rod.toY)}\n(Toca para ver detalles)',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    );
                  },
                ),
                touchCallback: (FlTouchEvent event, barTouchResponse) {
                  if (event is FlTapUpEvent && barTouchResponse?.spot != null) {
                    final groupIndex =
                        barTouchResponse!.spot!.touchedBarGroupIndex;
                    final rodIndex = barTouchResponse.spot!.touchedRodDataIndex;
                    if (groupIndex >= 0 && groupIndex < displayData.length) {
                      _onBarTapped(
                        displayData[groupIndex],
                        rodIndex == 0, // 0 = income, 1 = expense
                      );
                    }
                  }
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            _LegendSummary(
              title: 'Ingresos',
              description: 'Total de ingresos',
              amount: widget.totalIncome,
              color: const Color(0xFF4CAF50),
            ),
            _LegendSummary(
              title: 'Gastos',
              description: 'Total de gastos',
              amount: widget.totalExpense,
              color: const Color(0xFFFF5252),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '* Los valores de ingresos y gastos que se muestran no incluyen impuestos.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).hintColor,
                fontStyle: FontStyle.italic,
              ),
        ),
      ],
    );
  }

  Widget _buildDetailView(BuildContext context) {
    final range = _detailRange;
    if (range == null) return const SizedBox.shrink();

    return PeriodDetailView(
      kind: _detailKind,
      range: range,
      today: DateTime.now(),
      items: _detailItems,
      isLoading: _isLoadingDetails,
      hasError: _detailFailed,
      mode: _detailViewMode,
      selectedBucketKey: _selectedBucketKey,
      expandedDays: _expandedDays,
      onBack: _closeDetailView,
      onPickRange: _openDetailPeriodPicker,
      onStepRange: _stepDetailRange,
      onModeChanged: _setDetailViewMode,
      onBucketSelected: _setBucketFilter,
      onToggleDay: _toggleDay,
      onRetry: () => _changeDetailRange(range),
      canOpenItem: (item) => _showingIncome && _isInvoiceBackedIncome(item),
      onOpenItem: _openInvoiceDetailInline,
      openItemKey: _selectedDetailKey,
      loadingItemKey: _isLoadingInvoiceDetails ? _selectedDetailKey : null,
      expandedItemBuilder: (item) => _buildInlineInvoiceDetail(context, item),
    );
  }

  Widget _buildInlineInvoiceDetail(
    BuildContext context,
    PeriodDetailItem item,
  ) {
    final isPayment = item.sourceType == 'sales_payment';
    if (_isLoadingInvoiceDetails) {
      return const SizedBox.shrink();
    }

    if (_invoiceDetailError != null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(54, 2, 8, 12),
        padding: const EdgeInsets.all(14),
        decoration: _inlineDetailDecoration(context),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _invoiceDetailError!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (isPayment)
              VbButton(
                label: 'Ver cobro',
                variant: VbButtonVariant.text,
                onPressed: () => _openReceivedPayment(item),
              ),
          ],
        ),
      );
    }

    final invoice = _selectedInvoice;
    if (invoice == null) return const SizedBox.shrink();

    return _InlineInvoiceDetailPanel(
      invoice: invoice,
      paymentAmount: isPayment ? item.amount : null,
      productImagesById: _invoiceProductImagesById,
      productImagesBySku: _invoiceProductImagesBySku,
      decoration: _inlineDetailDecoration(context),
      onClose: _clearInlineInvoiceDetail,
      onOpenPayment: isPayment ? () => _openReceivedPayment(item) : null,
      onOpenInvoice: () => context.push('/sales/invoices/${invoice.id}'),
    );
  }

  BoxDecoration _inlineDetailDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }

  Widget _buildBottomTitle(BuildContext context, double value,
      List<MonthlyIncomeExpensePoint> displayData) {
    final index = value.toInt();
    if (index < 0 || index >= displayData.length) {
      return const SizedBox.shrink();
    }

    final date = displayData[index].periodStart;
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    final isDailyView = displayData[index].periodStart.day ==
            displayData[index].periodEnd.day &&
        displayData[index].periodStart.month ==
            displayData[index].periodEnd.month;

    if (isDailyView) {
      int skipInterval = 1;
      if (displayData.length > 7) skipInterval = isSmallScreen ? 3 : 2;
      if (displayData.length > 14) skipInterval = 2;
      if (displayData.length > 21) skipInterval = 3;
      if (isSmallScreen && displayData.length > 10) skipInterval = 3;

      if (index % skipInterval != 0) return const SizedBox.shrink();

      final day = DateFormat('d', 'es_CL').format(date);
      final weekday = DateFormat('EEE', 'es_CL').format(date);
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '$weekday\n$day',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 10,
              ),
        ),
      );
    } else {
      int skipInterval = 1;
      if (isSmallScreen) {
        if (displayData.length >= 10) skipInterval = 2;
        if (displayData.length >= 20) skipInterval = 3;
      } else {
        if (displayData.length > 12) skipInterval = 2;
        if (displayData.length > 24) skipInterval = 3;
      }

      if (index % skipInterval != 0) return const SizedBox.shrink();

      final month = DateFormat('MMM', 'es_CL').format(date).toUpperCase();
      final year = DateFormat('yy').format(date);

      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          '$month\n$year',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 9,
              ),
        ),
      );
    }
  }

  void _onBarTapped(MonthlyIncomeExpensePoint period, bool isIncome) {
    _showingIncome = isIncome;
    _detailViewMode = PeriodDetailMode.movements;
    _changeDetailRange(_periodRangeForPeriod(period));
  }

  /// Abre o cambia el período del detalle y lo pide. El filtro por método se
  /// conserva si el período nuevo lo tiene; los días abiertos y la factura en
  /// línea no, porque eran de otro período.
  Future<void> _changeDetailRange(DateTimeRange range) async {
    final request = ++_detailRequest;
    setState(() {
      _detailRange = range;
      _isLoadingDetails = true;
      _detailFailed = false;
      _expandedDays = const {};
      _clearInlineInvoiceDetailState();
    });

    try {
      final reportsService = context.read<FinancialReportsService>();
      final isCashFlow = widget.basis == _AccountingBasis.cash;
      final endDate = DateTime(range.end.year, range.end.month, range.end.day)
          .add(const Duration(days: 1));

      final items = _showingIncome
          ? await reportsService.getIncomePeriodDetails(
              startDate: range.start,
              endDate: endDate,
              isCashFlow: isCashFlow,
            )
          : await reportsService.getExpensePeriodDetails(
              startDate: range.start,
              endDate: endDate,
              isCashFlow: isCashFlow,
            );

      if (!mounted || request != _detailRequest) return;
      setState(() {
        _detailItems = items;
        _isLoadingDetails = false;
        final breakdown = PeriodDetailBreakdown.of(items, _detailKind);
        if (breakdown.bucket(_selectedBucketKey) == null) {
          _selectedBucketKey = null;
        }
      });
    } catch (error) {
      if (!mounted || request != _detailRequest) return;
      // Antes un error se veía como «No hay transacciones»: un período vacío
      // y uno que no cargó no pueden verse igual.
      debugPrint('Accounting dashboard detail load failed: $error');
      setState(() {
        _detailItems = null;
        _isLoadingDetails = false;
        _detailFailed = true;
      });
    }
  }

  void _closeDetailView() {
    _detailRequest++;
    setState(() {
      _detailRange = null;
      _detailItems = null;
      _isLoadingDetails = false;
      _detailFailed = false;
      _detailViewMode = PeriodDetailMode.movements;
      _selectedBucketKey = null;
      _expandedDays = const {};
      _clearInlineInvoiceDetailState();
    });
  }

  Future<void> _openDetailPeriodPicker(BuildContext anchorContext) async {
    final currentRange = _detailRange;
    if (currentRange == null) return;

    final today = DateUtils.dateOnly(DateTime.now());
    // El detalle no depende del rango del gráfico: se puede mirar cualquier
    // día de los últimos tres años, nunca uno futuro.
    final firstDate = DateTime(today.year - 3, 1, 1);
    final pickedRange = await showVbDateRangePicker(
      anchorContext: anchorContext,
      initialRange: currentRange,
      firstDate: firstDate,
      lastDate: today,
      today: today,
      presets: vbReportDateRangePresets(today),
    );

    if (pickedRange == null || !mounted) return;
    await _changeDetailRange(pickedRange);
  }

  void _stepDetailRange(int direction) {
    final range = _detailRange;
    if (range == null) return;
    final next = periodDetailStep(range, direction, DateTime.now());
    if (next == null) return;
    _changeDetailRange(next);
  }

  DateTimeRange _periodRangeForPeriod(MonthlyIncomeExpensePoint period) {
    final today = DateUtils.dateOnly(DateTime.now());
    final start = DateUtils.dateOnly(period.periodStart);
    var end = DateUtils.dateOnly(period.periodEnd);
    // La barra del mes en curso termina hoy, no el 31.
    if (end.isAfter(today)) end = today;
    if (end.isBefore(start)) end = start;
    return DateTimeRange(start: start, end: end);
  }

  void _setDetailViewMode(PeriodDetailMode mode) {
    setState(() {
      _detailViewMode = mode;
      _expandedDays = const {};
      _clearInlineInvoiceDetailState();
    });
  }

  void _setBucketFilter(String? key) {
    setState(() {
      _selectedBucketKey = key;
      _clearInlineInvoiceDetailState();
    });
  }

  void _toggleDay(DateTime day) {
    setState(() {
      final next = {..._expandedDays};
      if (!next.remove(day)) next.add(day);
      _expandedDays = next;
      _clearInlineInvoiceDetailState();
    });
  }

  String _detailKeyFor(PeriodDetailItem item) {
    return PeriodDetailView.itemKey(item);
  }

  bool _isInvoiceBackedIncome(PeriodDetailItem item) {
    return item.sourceType == 'sales_invoice' ||
        item.sourceType == 'sales_payment';
  }

  /// «Ver cobro»: un cobro abre su propia ficha, nunca la factura.
  void _openReceivedPayment(PeriodDetailItem item) {
    if (item.sourceType == 'sales_payment') {
      context.push('/sales/payments/${item.id}');
      return;
    }
  }

  /// Tocar un movimiento despliega ahí mismo lo que se vendió: las líneas de
  /// la factura del cobro (o de la venta), con foto, cantidad y precio. Es lo
  /// que responde «¿qué me pagaron?»; la ficha del cobro y la factura quedan
  /// como acciones explícitas del panel.
  Future<void> _openInvoiceDetailInline(PeriodDetailItem item) async {
    final detailKey = _detailKeyFor(item);

    if (_selectedDetailKey == detailKey &&
        (_selectedInvoice != null || _invoiceDetailError != null)) {
      setState(_clearInlineInvoiceDetailState);
      return;
    }

    final databaseService = context.read<DatabaseService>();
    final salesService = context.read<SalesService>();
    final inventoryService = context.read<shared_inventory.InventoryService>();

    setState(() {
      _selectedDetailKey = detailKey;
      _selectedInvoice = null;
      _isLoadingInvoiceDetails = true;
      _invoiceDetailError = null;
      _invoiceProductImagesById = const {};
      _invoiceProductImagesBySku = const {};
    });

    try {
      final invoiceId = await _resolveSalesInvoiceId(item, databaseService);
      if (invoiceId == null || invoiceId.isEmpty) {
        if (!mounted || _selectedDetailKey != detailKey) return;
        setState(() {
          _isLoadingInvoiceDetails = false;
          _invoiceDetailError =
              'No se encontró una factura vinculada a esta transacción.';
        });
        return;
      }

      final invoice = await salesService.fetchInvoice(invoiceId);
      if (invoice == null) {
        if (!mounted || _selectedDetailKey != detailKey) return;
        setState(() {
          _isLoadingInvoiceDetails = false;
          _invoiceDetailError = 'No se pudo cargar la factura vinculada.';
        });
        return;
      }

      final imageMaps = await _loadInvoiceItemImages(
        invoice,
        inventoryService,
      );

      if (!mounted || _selectedDetailKey != detailKey) return;
      setState(() {
        _selectedInvoice = invoice;
        _isLoadingInvoiceDetails = false;
        _invoiceDetailError = null;
        _invoiceProductImagesById = imageMaps.byId;
        _invoiceProductImagesBySku = imageMaps.bySku;
      });
    } catch (_) {
      if (!mounted || _selectedDetailKey != detailKey) return;
      setState(() {
        _isLoadingInvoiceDetails = false;
        _invoiceDetailError = 'No se pudo abrir el detalle de la factura.';
      });
    }
  }

  Future<String?> _resolveSalesInvoiceId(
    PeriodDetailItem item,
    DatabaseService databaseService,
  ) async {
    if (item.sourceType == 'sales_invoice') {
      return item.id;
    }

    if (item.sourceType == 'sales_payment') {
      final payment = await databaseService.selectById(
        'sales_payments',
        item.id,
        selectColumns: 'invoice_id',
      );
      return payment?['invoice_id']?.toString();
    }

    return null;
  }

  Future<({Map<String, String?> byId, Map<String, String?> bySku})>
      _loadInvoiceItemImages(
    Invoice invoice,
    shared_inventory.InventoryService inventoryService,
  ) async {
    final productIds = invoice.items
        .map((item) => item.productId?.trim())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    final productSkus = invoice.items
        .map((item) => item.productSku?.trim())
        .whereType<String>()
        .where((sku) => sku.isNotEmpty)
        .toSet();

    final byId = <String, String?>{};
    final bySku = <String, String?>{};

    if (productIds.isNotEmpty) {
      final products = await inventoryService.getProductsByIds(productIds);
      for (final product in products) {
        byId[product.id] = _bestProductImageUrl(product);
        if (product.sku.trim().isNotEmpty) {
          bySku[product.sku.trim().toLowerCase()] = _bestProductImageUrl(
            product,
          );
        }
      }
    }

    final missingSkus = productSkus
        .where((sku) => !bySku.containsKey(sku.toLowerCase()))
        .toList(growable: false);
    for (final sku in missingSkus) {
      final product = await inventoryService.getProductBySku(sku);
      if (product != null) {
        bySku[sku.toLowerCase()] = _bestProductImageUrl(product);
      }
    }

    return (byId: byId, bySku: bySku);
  }

  String? _bestProductImageUrl(shared_product.Product product) {
    final optimized = product.imageUrlOptimized?.trim();
    if (optimized != null && optimized.isNotEmpty) return optimized;

    final primary = product.imageUrl?.trim();
    if (primary != null && primary.isNotEmpty) return primary;

    for (final imageUrl in product.imageUrls) {
      final trimmed = imageUrl.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }

    return null;
  }

  void _clearInlineInvoiceDetail() {
    setState(_clearInlineInvoiceDetailState);
  }

  void _clearInlineInvoiceDetailState() {
    _selectedDetailKey = null;
    _selectedInvoice = null;
    _isLoadingInvoiceDetails = false;
    _invoiceDetailError = null;
    _invoiceProductImagesById = const {};
    _invoiceProductImagesBySku = const {};
  }

  double _calculateChartMax(double maxValue) {
    if (maxValue == 0) return 100000.0;

    final paddedMax = maxValue * 1.15;
    final magnitude = math.pow(10, (math.log(paddedMax) / math.ln10).floor());
    final normalized = paddedMax / magnitude;

    double rounded;
    if (normalized <= 1) {
      rounded = 1;
    } else if (normalized <= 2) {
      rounded = 2;
    } else if (normalized <= 5) {
      rounded = 5;
    } else {
      rounded = 10;
    }

    return rounded * magnitude;
  }

  double _calculateAxisInterval(double chartMax) {
    if (chartMax <= 0) return 10000.0;

    final rawInterval = chartMax / 4;
    final magnitude = math.pow(10, (math.log(rawInterval) / math.ln10).floor());
    final normalized = rawInterval / magnitude;

    double rounded;
    if (normalized <= 1) {
      rounded = 1;
    } else if (normalized <= 2) {
      rounded = 2;
    } else if (normalized <= 5) {
      rounded = 5;
    } else {
      rounded = 10;
    }

    return rounded * magnitude;
  }
}

/// Lo que se vendió en un cobro o una venta, desplegado bajo su fila: las
/// líneas de la factura con foto, cantidad y precio, y los totales. En un cobro
/// dice además cuánto de la factura cubre ese cobro.
class _InlineInvoiceDetailPanel extends StatelessWidget {
  final Invoice invoice;
  final double? paymentAmount;
  final Map<String, String?> productImagesById;
  final Map<String, String?> productImagesBySku;
  final BoxDecoration decoration;
  final VoidCallback onClose;
  final VoidCallback? onOpenPayment;
  final VoidCallback onOpenInvoice;

  const _InlineInvoiceDetailPanel({
    required this.invoice,
    required this.paymentAmount,
    required this.productImagesById,
    required this.productImagesBySku,
    required this.decoration,
    required this.onClose,
    required this.onOpenPayment,
    required this.onOpenInvoice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final payment = paymentAmount;
    final coversAll = payment != null && (payment - invoice.total).abs() < 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(54, 2, 8, 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: decoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNumber.isEmpty
                          ? 'Factura'
                          : 'Factura ${invoice.invoiceNumber}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        if ((invoice.customerName ?? '').trim().isNotEmpty)
                          invoice.customerName!.trim(),
                        _compactSpanishWeekdayDate(invoice.date),
                        _invoiceStatusLabel(invoice.status),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: roles.neutral.accent,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Cerrar detalle',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (invoice.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Esta factura no tiene líneas registradas.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: roles.neutral.accent,
                ),
              ),
            )
          else
            for (var i = 0; i < invoice.items.length; i++) ...[
              if (i > 0) Divider(height: 10, color: roles.hairline),
              _InvoiceItemDetailRow(
                item: invoice.items[i],
                imageUrl: _imageUrlForItem(invoice.items[i]),
              ),
            ],
          const SizedBox(height: 10),
          Divider(height: 1, color: roles.hairline),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final totals = ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _InvoiceTotalLine(
                      label: 'Neto',
                      amount: invoice.subtotal,
                    ),
                    if (invoice.ivaAmount > 0)
                      _InvoiceTotalLine(
                        label: 'IVA',
                        amount: invoice.ivaAmount,
                      ),
                    _InvoiceTotalLine(
                      label: 'Total factura',
                      amount: invoice.total,
                      isStrong: true,
                    ),
                    if (payment != null && !coversAll)
                      _InvoiceTotalLine(
                        label: 'Este cobro',
                        amount: payment,
                        isStrong: true,
                      ),
                    if (invoice.balance > 0)
                      _InvoiceTotalLine(
                        label: 'Saldo por cobrar',
                        amount: invoice.balance,
                        color: roles.warning.accent,
                        isStrong: true,
                      ),
                  ],
                ),
              );
              final actions = Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (onOpenPayment != null)
                    VbButton(
                      label: 'Ver cobro',
                      icon: Icons.receipt_outlined,
                      variant: VbButtonVariant.secondary,
                      onPressed: onOpenPayment,
                    ),
                  VbButton(
                    label: 'Ver factura',
                    icon: Icons.open_in_new_rounded,
                    variant: VbButtonVariant.text,
                    onPressed: onOpenInvoice,
                  ),
                ],
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: Alignment.centerRight, child: totals),
                    const SizedBox(height: 10),
                    actions,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: actions),
                  const SizedBox(width: 16),
                  totals,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String? _imageUrlForItem(InvoiceItem item) {
    final productId = item.productId?.trim();
    if (productId != null && productId.isNotEmpty) {
      final imageUrl = productImagesById[productId]?.trim();
      if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;
    }

    final sku = item.productSku?.trim().toLowerCase();
    if (sku != null && sku.isNotEmpty) {
      final imageUrl = productImagesBySku[sku]?.trim();
      if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;
    }

    return null;
  }

  String _invoiceStatusLabel(InvoiceStatus status) {
    switch (status) {
      case InvoiceStatus.draft:
        return 'Borrador';
      case InvoiceStatus.sent:
        return 'Enviada';
      case InvoiceStatus.confirmed:
        return 'Confirmada';
      case InvoiceStatus.paid:
        return 'Pagada';
      case InvoiceStatus.overdue:
        return 'Vencida';
      case InvoiceStatus.cancelled:
        return 'Anulada';
    }
  }
}

class _InvoiceItemDetailRow extends StatelessWidget {
  final InvoiceItem item;
  final String? imageUrl;

  const _InvoiceItemDetailRow({
    required this.item,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final title = (item.productName ?? '').trim().isNotEmpty
        ? item.productName!.trim()
        : ((item.description ?? '').trim().isNotEmpty
            ? item.description!.trim()
            : 'Línea sin nombre');
    final subtitleParts = <String>[
      '${_formatQuantity(item.quantity)} × '
          '${VbMoneyText.formatClp(item.unitPrice)}',
      item.isService ? 'Servicio' : 'Producto',
      if ((item.productSku ?? '').trim().isNotEmpty) item.productSku!.trim(),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 40,
              height: 40,
              color: theme.colorScheme.surfaceContainerHigh,
              child: imageUrl == null || imageUrl!.isEmpty
                  ? Icon(
                      item.isService
                          ? Icons.handyman_outlined
                          : Icons.inventory_2_outlined,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  : ImageService.buildProductImage(
                      imageUrl: imageUrl,
                      size: 40,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: roles.neutral.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          VbMoneyText(item.lineTotal),
        ],
      ),
    );
  }

  String _formatQuantity(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }
}

class _InvoiceTotalLine extends StatelessWidget {
  final String label;
  final double amount;
  final bool isStrong;
  final Color? color;

  const _InvoiceTotalLine({
    required this.label,
    required this.amount,
    this.isStrong = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      fontWeight: isStrong ? FontWeight.w700 : FontWeight.w500,
      color: color ??
          (isStrong ? theme.colorScheme.onSurface : roles.neutral.accent),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          if (color == null)
            VbMoneyText(amount)
          else
            Text(
              VbMoneyText.formatClp(amount),
              style: labelStyle?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

class _LegendSummary extends StatelessWidget {
  final String title;
  final String description;
  final double amount;
  final Color color;

  const _LegendSummary({
    required this.title,
    required this.description,
    required this.amount,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = NumberFormat.currency(
      locale: 'es_CL',
      symbol: 'CLP',
      decimalDigits: 0,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        color: color.withValues(alpha: 0.06),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                formatter.format(amount.round()),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExpenseLegendRow extends StatelessWidget {
  final Color color;
  final String accountCode;
  final String accountName;
  final double amount;
  final double total;

  const _ExpenseLegendRow({
    required this.color,
    required this.accountCode,
    required this.accountName,
    required this.amount,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final percent = total <= 0 ? 0 : (amount / total) * 100;
    final formatter = NumberFormat.currency(
      locale: 'es_CL',
      symbol: 'CLP',
      decimalDigits: 0,
    );

    final codePrefix = accountCode.isEmpty ? '' : '$accountCode · ';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  accountName,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  '$codePrefix${formatter.format(amount.round())} • ${percent.toStringAsFixed(1)}%',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseBreakdownCard extends StatefulWidget {
  final List<ExpenseBreakdownItem> items;
  final List<PeriodDetailItem> details;
  final double chartHeight;
  final _AccountingBasis basis;
  final _ExpenseBreakdownRange breakdownRange;
  final String rangeLabel;
  final List<_ExpenseBreakdownRange> breakdownOptions;
  final ValueChanged<_ExpenseBreakdownRange> onRangeChanged;
  final double totalAmount;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  const _ExpenseBreakdownCard({
    required this.items,
    required this.details,
    required this.chartHeight,
    required this.basis,
    required this.breakdownRange,
    required this.rangeLabel,
    required this.breakdownOptions,
    required this.onRangeChanged,
    required this.totalAmount,
    required this.rangeStart,
    required this.rangeEnd,
  });

  @override
  State<_ExpenseBreakdownCard> createState() => _ExpenseBreakdownCardState();
}

class _ExpenseBreakdownCardState extends State<_ExpenseBreakdownCard> {
  // State for detail view
  ExpenseBreakdownItem? _selectedItem;
  List<PeriodDetailItem>? _detailItems;
  bool _isLoadingDetails = false;
  int _touchedIndex = -1;

  void _onSliceTapped(ExpenseBreakdownItem item) {
    setState(() {
      _selectedItem = item;
      _isLoadingDetails = true;
      _detailItems = null;
    });

    try {
      final visibleKeys = widget.items
          .where((entry) => !entry.isOther)
          .map((entry) => entry.breakdownKey)
          .toSet();

      final filteredItems = widget.details.where((detail) {
        final detailKey = _expenseBreakdownKeyForDetail(detail);

        if (item.isOther) {
          return !visibleKeys.contains(detailKey);
        }

        return detailKey == item.breakdownKey;
      }).toList()
        ..sort((a, b) => b.amount.abs().compareTo(a.amount.abs()));

      if (mounted) {
        setState(() {
          _detailItems = filteredItems;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching pie detail: $e');
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
        });
      }
    }
  }

  void _closeDetailView() {
    setState(() {
      _selectedItem = null;
      _detailItems = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Effective height calculation preserved from original
    // final effectiveHeight = widget.chartHeight * 0.7;

    if (widget.items.isEmpty) {
      return Card(
        child: SizedBox(
          height: widget.chartHeight * 0.7,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.pie_chart_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.basis == _AccountingBasis.cash
                        ? 'No hay egresos de caja registrados en ${widget.rangeLabel.toLowerCase()}'
                        : 'No hay gastos registrados en ${widget.rangeLabel.toLowerCase()}',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      child: SizedBox(
        height: widget.chartHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Stack(
            children: [
              // 1. Chart Content (Always rendered to maintain size)
              Visibility(
                visible: _selectedItem == null,
                maintainState: true,
                maintainSize: true,
                maintainAnimation: true,
                child: _buildChartContent(context),
              ),

              // 2. Detail View Overlay
              if (_selectedItem != null)
                Positioned.fill(
                  child: Container(
                    color: Theme.of(context).cardColor,
                    child: _buildDetailView(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartContent(BuildContext context) {
    final currency = NumberFormat.currency(
      locale: 'es_CL',
      symbol: 'CLP',
      decimalDigits: 0,
    );

    final palette = _buildPalette(context, widget.items.length);
    final total = widget.totalAmount == 0
        ? widget.items.fold<double>(0, (sum, item) => sum + item.displayAmount)
        : widget.totalAmount;
    final startLabel = DateFormat('dd MMM', 'es_CL').format(widget.rangeStart);
    final endLabel = DateFormat('dd MMM yyyy', 'es_CL').format(widget.rangeEnd);
    final rangeDescription = '${widget.rangeLabel} · $startLabel – $endLabel';
    final title = Text(
      widget.basis == _AccountingBasis.cash
          ? 'Principales egresos de caja'
          : 'Gastos principales',
      style: Theme.of(context).textTheme.titleMedium,
    );
    final rangeSelector = SizedBox(
      width: 180,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_ExpenseBreakdownRange>(
          value: widget.breakdownRange,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          onChanged: (value) {
            if (value != null) {
              widget.onRangeChanged(value);
            }
          },
          items: widget.breakdownOptions
              .map(
                (option) => DropdownMenuItem<_ExpenseBreakdownRange>(
                  value: option,
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (constraints.maxWidth < 480) ...[
            title,
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: rangeSelector,
            ),
          ] else
            Row(
              children: [
                Expanded(child: title),
                rangeSelector,
              ],
            ),
          const SizedBox(height: 4),
          Text(
            rangeDescription,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Pie chart section - LEFT SIDE
                Expanded(
                  flex: 3,
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final size = math.min(
                                constraints.maxWidth, constraints.maxHeight) *
                            0.85;
                        return SizedBox(
                          width: size,
                          height: size,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              PieChart(
                                PieChartData(
                                  sectionsSpace: 3,
                                  centerSpaceRadius: size * 0.35,
                                  sections: [
                                    for (var i = 0;
                                        i < widget.items.length;
                                        i++)
                                      PieChartSectionData(
                                        value: widget.items[i].displayAmount,
                                        color: palette[i],
                                        radius: i == _touchedIndex
                                            ? size * 0.26
                                            : size * 0.25,
                                        title: '',
                                        badgeWidget: i == _touchedIndex
                                            ? Container(
                                                constraints:
                                                    const BoxConstraints(
                                                        maxWidth: 100),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                              alpha: 0.15),
                                                      blurRadius: 6,
                                                      offset:
                                                          const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      widget
                                                          .items[i].accountName,
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.black87,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    Text(
                                                      '${(widget.items[i].displayAmount / total * 100).toStringAsFixed(1)}%',
                                                      style: const TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.black54,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : null,
                                        badgePositionPercentageOffset: 0.75,
                                      ),
                                  ],
                                  pieTouchData: PieTouchData(
                                    touchCallback:
                                        (FlTouchEvent event, pieTouchResponse) {
                                      setState(() {
                                        if (!event
                                                .isInterestedForInteractions ||
                                            pieTouchResponse == null ||
                                            pieTouchResponse.touchedSection ==
                                                null) {
                                          _touchedIndex = -1;
                                          return;
                                        }
                                        _touchedIndex = pieTouchResponse
                                            .touchedSection!
                                            .touchedSectionIndex;
                                      });

                                      if (event is FlTapUpEvent &&
                                          pieTouchResponse != null &&
                                          pieTouchResponse.touchedSection !=
                                              null) {
                                        final index = pieTouchResponse
                                            .touchedSection!
                                            .touchedSectionIndex;
                                        if (index >= 0 &&
                                            index < widget.items.length) {
                                          _onSliceTapped(widget.items[index]);
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.basis == _AccountingBasis.cash
                                        ? 'EGRESOS'
                                        : 'GASTOS',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                  ),
                                  Text(
                                    widget.basis == _AccountingBasis.cash
                                        ? 'DE CAJA'
                                        : 'PRINCIPALES',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context).hintColor,
                                          fontSize: 10,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    currency.format(total.round()),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Legend section - RIGHT SIDE
                Expanded(
                  flex: 2,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _ExpenseLegendRow(
                              color: palette[i],
                              accountCode: widget.items[i].accountCode,
                              accountName: widget.items[i].accountName,
                              amount: widget.items[i].displayAmount,
                              total: total,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailView(BuildContext context) {
    const color = Color(0xFFFF5252); // Expense color

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            IconButton(
              onPressed: _closeDetailView,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Volver al gráfico',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedItem?.accountName ?? 'Detalle',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _selectedItem?.accountCode ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                NumberFormat.currency(locale: 'es_CL', symbol: 'CLP')
                    .format(_selectedItem?.amount ?? 0),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(),
        // Detail list
        Expanded(
          child: _isLoadingDetails
              ? const Center(child: CircularProgressIndicator())
              : _detailItems == null || _detailItems!.isEmpty
                  ? Center(
                      child: Text(
                        'No hay transacciones disponibles',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).hintColor,
                            ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _detailItems!.length,
                      itemBuilder: (context, index) => PeriodDetailItemRow(
                        kind: widget.basis == _AccountingBasis.cash
                            ? PeriodDetailKind.expenseCash
                            : PeriodDetailKind.expenseAccrual,
                        item: _detailItems![index],
                      ),
                    ),
        ),
      ],
    );
  }

  List<Color> _buildPalette(BuildContext context, int count) {
    final baseColors = [
      const Color(0xFF1565C0),
      const Color(0xFF4CAF50),
      const Color(0xFFEF6C00),
      const Color(0xFF6A1B9A),
      const Color(0xFF00838F),
      const Color(0xFFAD1457),
      const Color(0xFF7B1FA2),
      const Color(0xFF00897B),
    ];

    return List<Color>.generate(count, (index) {
      return baseColors[index % baseColors.length];
    });
  }
}
