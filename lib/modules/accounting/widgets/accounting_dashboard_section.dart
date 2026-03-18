import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/dashboard_metrics.dart';
import '../services/accounting_service.dart';
import '../services/financial_reports_service.dart';

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

const int _maxBreakdownSlices = 8;
const String _otherBreakdownKey = '__other__';

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
  const AccountingDashboardSection({super.key});

  /// Call this after making a sale/purchase to ensure dashboard shows fresh data
  static void invalidateCache() {
    _AccountingDashboardSectionState._cachedData = null;
    _AccountingDashboardSectionState._cacheTimestamp = null;
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
  String? _error;

  // Static cache - persists across widget rebuilds
  static _DashboardPayload? _cachedData;
  static DateTime? _cacheTimestamp;
  static String? _cachedPeriod;
  static _AccountingBasis? _cachedBasis;
  static _ExpenseBreakdownRange? _cachedBreakdownRange;
  static const Duration _cacheDuration = Duration(minutes: 5);

  static const Map<String, int> _periodToMonths = {
    'Esta semana': 1,
    'Mes actual': 1,
    'Mes anterior': 1,
    'Últimos 6 meses': 6,
    'Últimos 12 meses': 12,
    'Últimos 18 meses': 18,
    'Últimos 24 meses': 24,
  };

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
    // Schedule initialization to avoid "setState during build" if service notifies listeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    final accountingService = context.read<AccountingService>();
    await accountingService.initialize();

    if (!mounted) return;

    // Check if we have valid cached data
    final isCacheValid = _cachedData != null &&
        _cacheTimestamp != null &&
        DateTime.now().difference(_cacheTimestamp!) < _cacheDuration &&
        _cachedPeriod == _selectedPeriod &&
        _cachedBasis == _basis &&
        _cachedBreakdownRange == _breakdownRange;

    if (isCacheValid) {
      // Use cached data immediately - no network request!
      setState(() {
        _data = _cachedData;
        _isLoading = false;
        _error = null;
      });
    } else {
      // Need to fetch fresh data
      _refreshData();
    }
  }

  void _onBasisChanged(_AccountingBasis newValue) {
    if (_basis != newValue) {
      setState(() {
        _basis = newValue;
      });
      _refreshData();
    }
  }

  void _onPeriodChanged(String? newValue) {
    if (newValue != null && _selectedPeriod != newValue) {
      setState(() {
        _selectedPeriod = newValue;
      });
      _refreshData();
    }
  }

  void _onBreakdownRangeChanged(_ExpenseBreakdownRange newValue) {
    if (_breakdownRange != newValue) {
      setState(() {
        _breakdownRange = newValue;
      });
      _refreshData();
    }
  }

  DateTime _exclusiveBreakdownEnd(DateTime inclusiveEnd) {
    return inclusiveEnd.add(const Duration(seconds: 1));
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

    final topCount = _maxBreakdownSlices - 1;
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

  Future<void> _refreshData({int retryCount = 0}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final newData = await _fetchData();
      if (mounted) {
        // Update static cache
        _cachedData = newData;
        _cacheTimestamp = DateTime.now();
        _cachedPeriod = _selectedPeriod;
        _cachedBasis = _basis;
        _cachedBreakdownRange = _breakdownRange;

        setState(() {
          _data = newData;
          _isLoading = false;
        });
      }
    } catch (e) {
      // Auto-retry on HandshakeException (network not ready yet)
      final errorStr = e.toString();
      if (retryCount < 2 &&
          (errorStr.contains('HandshakeException') ||
              errorStr.contains('Connection terminated'))) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          _refreshData(retryCount: retryCount + 1);
        }
        return;
      }

      if (mounted) {
        setState(() {
          _error = errorStr;
          _isLoading = false;
        });
      }
    }
  }

  Future<_DashboardPayload> _fetchData() async {
    final reportsService = context.read<FinancialReportsService>();
    final isCashFlow = _basis == _AccountingBasis.cash;
    final now = DateTime.now();

    final isDailyView = _selectedPeriod == 'Esta semana' ||
        _selectedPeriod == 'Mes actual' ||
        _selectedPeriod == 'Mes anterior';

    List<MonthlyIncomeExpensePoint> series;

    if (isDailyView) {
      DateTime startDate;
      DateTime endDate;

      if (_selectedPeriod == 'Esta semana') {
        final weekday = now.weekday;
        startDate = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: weekday - 1));
        endDate =
            startDate.add(const Duration(days: 6, hours: 23, minutes: 59));
      } else if (_selectedPeriod == 'Mes actual') {
        startDate = DateTime(now.year, now.month, 1);
        final lastDay = DateTime(now.year, now.month + 1, 0);
        endDate =
            DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59);
      } else {
        // Mes anterior
        startDate = DateTime(now.year, now.month - 1, 1);
        final lastDay = DateTime(now.year, now.month, 0);
        endDate =
            DateTime(lastDay.year, lastDay.month, lastDay.day, 23, 59, 59);
      }

      series = await reportsService.getIncomeExpenseDailyTimeseries(
        startDate: startDate,
        endDate: endDate,
        isCashFlow: isCashFlow,
      );
    } else {
      final months = _periodToMonths[_selectedPeriod] ?? 12;
      series = await reportsService.getIncomeExpenseTimeseries(
        months: months,
        isCashFlow: isCashFlow,
      );
    }

    // Breakdown Logic
    final currentMonthStart = DateTime(now.year, now.month);
    final previousMonthEnd =
        currentMonthStart.subtract(const Duration(days: 1));

    DateTime breakdownStart;
    DateTime breakdownEnd;
    switch (_breakdownRange) {
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

    final breakdownDetails = await reportsService.getExpensePeriodDetails(
      startDate: breakdownStart,
      endDate: _exclusiveBreakdownEnd(breakdownEnd),
      isCashFlow: isCashFlow,
    );

    final breakdown = _buildExpenseBreakdown(breakdownDetails);

    final totalIncome =
        series.fold<double>(0, (sum, point) => sum + point.income);
    final totalExpense =
        series.fold<double>(0, (sum, point) => sum + point.expense);
    final breakdownTotal = breakdownDetails.fold<double>(
      0,
      (sum, item) => sum + item.amount.abs(),
    );

    final monthsCount = _periodToMonths[_selectedPeriod] ?? 12;
    final rangeStart = series.isNotEmpty ? series.first.periodStart : now;
    final rangeEnd = series.isNotEmpty ? series.last.periodEnd : now;

    return _DashboardPayload(
      series: series,
      expenseBreakdown: breakdown,
      trailingLabel: _breakdownRange.label,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      months: monthsCount,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      breakdownRange: _breakdownRange,
      breakdownStart: breakdownStart,
      breakdownEnd: breakdownEnd,
      breakdownTotal: breakdownTotal,
      breakdownDetails: breakdownDetails,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Initial loading (no data yet)
    if (_data == null) {
      if (_isLoading) return const _DashboardSkeleton();
      if (_error != null) {
        return _DashboardError(
          error: _error,
          onRetry: _refreshData,
        );
      }
    }

    // 2. Data loaded but empty series (rare if data exists)
    final data = _data;
    if (data != null && data.series.isEmpty && !_isLoading) {
      return _DashboardEmpty(onRetry: _refreshData);
    }

    // 3. Show content (or loading overlay if refreshing)
    // Safe because if _data is null here, we would have returned above unless error logic failed
    if (data == null) return const SizedBox.shrink();

    return Stack(
      children: [
        _DashboardContent(
          data: data,
          basis: _basis,
          onBasisChanged: _onBasisChanged,
          selectedPeriod: _selectedPeriod,
          periodOptions: _periodToMonths.keys.toList(),
          onPeriodChanged: _onPeriodChanged,
          onRefresh: _refreshData,
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
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
          ),
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
    final color = Theme.of(context).colorScheme.surfaceVariant;
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
            color: color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
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
              error?.toString() ?? 'Error desconocido',
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
        // Same fixed height for both cards to keep them aligned
        final chartHeight = 400.0;

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
        border: Border.all(color: color.withOpacity(0.2)),
        color: color.withOpacity(0.05),
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
  // State for detail view
  MonthlyIncomeExpensePoint? _selectedPeriod;
  bool _showingIncome = true; // true = income, false = expense
  List<PeriodDetailItem>? _detailItems;
  bool _isLoadingDetails = false;
  bool _showDayView = false; // false = list view, true = day grouped view

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 24),
        child: Stack(
          children: [
            // Chart View - Always present to dictate size
            Visibility(
              visible: _selectedPeriod == null,
              maintainState: true,
              maintainSize: true,
              maintainAnimation: true,
              child: _buildChartContent(context),
            ),
            // Detail View - Overlays the chart when active
            if (_selectedPeriod != null)
              Positioned.fill(
                child: Container(
                  color: Theme.of(context).cardColor,
                  child: _buildDetailView(context, _showingIncome),
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
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.selectedPeriod,
                borderRadius: BorderRadius.circular(12),
                onChanged: widget.onPeriodChanged,
                style: Theme.of(context).textTheme.bodyMedium,
                items: widget.periodOptions
                    .map(
                      (value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      ),
                    )
                    .toList(),
              ),
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
                      .withOpacity(0.2),
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (value) => FlLine(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withOpacity(0.12),
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

  Widget _buildDetailView(BuildContext context, bool isIncome) {
    if (_selectedPeriod == null) return const SizedBox.shrink();

    final period = _selectedPeriod!;
    final color = isIncome ? const Color(0xFF4CAF50) : const Color(0xFFFF5252);
    final totalAmount = isIncome ? period.income : period.expense;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with back button, title, toggle, and total
        Row(
          children: [
            IconButton(
              onPressed: _closeDetailView,
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Volver al gráfico',
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isIncome ? 'Ingresos' : 'Gastos',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Text(
                  period.periodLabel(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const Spacer(),
            // Compact toggle buttons
            if (_detailItems != null && _detailItems!.isNotEmpty) ...[
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        Theme.of(context).colorScheme.outline.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ToggleIconButton(
                      icon: Icons.list,
                      isSelected: !_showDayView,
                      onPressed: () => setState(() => _showDayView = false),
                      tooltip: 'Detalle',
                    ),
                    _ToggleIconButton(
                      icon: Icons.calendar_view_day,
                      isSelected: _showDayView,
                      onPressed: () => setState(() => _showDayView = true),
                      tooltip: 'Por día',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    NumberFormat.currency(locale: 'es_CL', symbol: 'CLP')
                        .format(totalAmount),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (_detailItems != null && _detailItems!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Builder(
                      builder: (context) {
                        double average = 0;
                        String label = '';

                        if (_showDayView) {
                          // Calculate daily average
                          final uniqueDays = _detailItems!
                              .map((i) => DateTime(
                                    i.transactionDate.year,
                                    i.transactionDate.month,
                                    i.transactionDate.day,
                                  ))
                              .toSet()
                              .length;
                          if (uniqueDays > 0) {
                            average = totalAmount / uniqueDays;
                            label = 'prom. diario';
                          }
                        } else {
                          // Calculate per-transaction average
                          average = totalAmount / _detailItems!.length;
                          label = 'prom. tx';
                        }

                        return Text(
                          '${NumberFormat.currency(locale: 'es_CL', symbol: '', decimalDigits: 0).format(average)} / $label',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: color.withOpacity(0.8),
                                    fontSize: 10,
                                  ),
                        );
                      },
                    ),
                  ],
                ],
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
                        'No hay transacciones para este período',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).hintColor,
                            ),
                      ),
                    )
                  : _showDayView
                      ? _buildDayGroupedView(context, isIncome)
                      : _buildDetailListView(context, isIncome),
        ),
      ],
    );
  }

  Widget _buildDetailListView(BuildContext context, bool isIncome) {
    return ListView.separated(
      itemCount: _detailItems!.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _detailItems![index];
        return _PeriodDetailTile(item: item, isIncome: isIncome);
      },
    );
  }

  Widget _buildDayGroupedView(BuildContext context, bool isIncome) {
    // Group items by day
    final groupedByDay = <DateTime, List<PeriodDetailItem>>{};
    for (final item in _detailItems!) {
      final day = DateTime(
        item.transactionDate.year,
        item.transactionDate.month,
        item.transactionDate.day,
      );
      groupedByDay.putIfAbsent(day, () => []).add(item);
    }

    // Sort by date descending
    final sortedDays = groupedByDay.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    final color = isIncome ? const Color(0xFF4CAF50) : const Color(0xFFFF5252);
    final formatter = NumberFormat.currency(locale: 'es_CL', symbol: 'CLP');

    return ListView.separated(
      itemCount: sortedDays.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final day = sortedDays[index];
        final items = groupedByDay[day]!;
        final dayTotal =
            items.fold<double>(0, (sum, item) => sum + item.amount);
        final itemCount = items.length;

        return ListTile(
          dense: true,
          leading: CircleAvatar(
            backgroundColor: color.withOpacity(0.1),
            radius: 18,
            child: Icon(Icons.calendar_today, color: color, size: 18),
          ),
          title: Text(
            DateFormat('EEEE d', 'es_CL').format(day),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          subtitle: Text(
            '$itemCount ${itemCount == 1 ? 'transacción' : 'transacciones'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          trailing: Text(
            formatter.format(dayTotal),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
          ),
        );
      },
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

  void _onBarTapped(MonthlyIncomeExpensePoint period, bool isIncome) async {
    setState(() {
      _selectedPeriod = period;
      _showingIncome = isIncome;
      _isLoadingDetails = true;
      _detailItems = null;
    });

    try {
      final reportsService = context.read<FinancialReportsService>();
      final isCashFlow = widget.basis == _AccountingBasis.cash;

      // Calculate end date (add 1 day for daily, 1 month for monthly)
      final isDailyView = period.periodStart.day == period.periodEnd.day &&
          period.periodStart.month == period.periodEnd.month;
      final endDate = isDailyView
          ? period.periodStart.add(const Duration(days: 1))
          : DateTime(period.periodStart.year, period.periodStart.month + 1, 1);

      final items = isIncome
          ? await reportsService.getIncomePeriodDetails(
              startDate: period.periodStart,
              endDate: endDate,
              isCashFlow: isCashFlow,
            )
          : await reportsService.getExpensePeriodDetails(
              startDate: period.periodStart,
              endDate: endDate,
              isCashFlow: isCashFlow,
            );

      if (mounted) {
        setState(() {
          _detailItems = items;
          _isLoadingDetails = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingDetails = false;
        });
      }
    }
  }

  void _closeDetailView() {
    setState(() {
      _selectedPeriod = null;
      _detailItems = null;
    });
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

/// Compact icon button for toggle in header
class _ToggleIconButton extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final VoidCallback onPressed;
  final String tooltip;

  const _ToggleIconButton({
    required this.icon,
    required this.isSelected,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
        ),
      ),
    );
  }
}

/// Tile for showing a single period detail item
class _PeriodDetailTile extends StatelessWidget {
  final PeriodDetailItem item;
  final bool isIncome;

  const _PeriodDetailTile({required this.item, required this.isIncome});

  @override
  Widget build(BuildContext context) {
    final color = isIncome ? const Color(0xFF4CAF50) : const Color(0xFFFF5252);
    final formatter = NumberFormat.currency(locale: 'es_CL', symbol: 'CLP');

    // Icon based on source type
    IconData icon;
    switch (item.sourceType) {
      case 'sales_payment':
        icon = Icons.payments;
        break;
      case 'sales_invoice':
        icon = Icons.description;
        break;
      case 'purchase_payment':
        icon = Icons.shopping_cart;
        break;
      case 'expense':
        icon = Icons.receipt;
        break;
      case 'journal_entry':
        icon = Icons.book;
        break;
      default:
        icon = Icons.attach_money;
    }

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.1),
        radius: 18,
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(
        item.description.isNotEmpty ? item.description : item.documentNumber,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
      ),
      subtitle: Text(
        [
          if (item.documentNumber.isNotEmpty && item.description.isNotEmpty)
            item.documentNumber,
          if (item.secondaryText.isNotEmpty) item.secondaryText,
          DateFormat('d MMM yyyy', 'es_CL').format(item.transactionDate),
        ].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: Text(
        formatter.format(item.amount),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
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
        border: Border.all(color: color.withOpacity(0.2)),
        color: color.withOpacity(0.06),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                widget.basis == _AccountingBasis.cash
                    ? 'Principales egresos de caja'
                    : 'Gastos principales',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            DropdownButtonHideUnderline(
              child: DropdownButton<_ExpenseBreakdownRange>(
                value: widget.breakdownRange,
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
                        child: Text(option.label),
                      ),
                    )
                    .toList(),
              ),
            ),
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
                                  for (var i = 0; i < widget.items.length; i++)
                                    PieChartSectionData(
                                      value: widget.items[i].displayAmount,
                                      color: palette[i],
                                      radius: i == _touchedIndex
                                          ? size * 0.26
                                          : size * 0.25,
                                      title: '',
                                      badgeWidget: i == _touchedIndex
                                          ? Container(
                                              constraints: const BoxConstraints(
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
                                                        .withOpacity(0.15),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    widget.items[i].accountName,
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.black87,
                                                    ),
                                                    textAlign: TextAlign.center,
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
                                      if (!event.isInterestedForInteractions ||
                                          pieTouchResponse == null ||
                                          pieTouchResponse.touchedSection ==
                                              null) {
                                        _touchedIndex = -1;
                                        return;
                                      }
                                      _touchedIndex = pieTouchResponse
                                          .touchedSection!.touchedSectionIndex;
                                    });

                                    if (event is FlTapUpEvent &&
                                        pieTouchResponse != null &&
                                        pieTouchResponse.touchedSection !=
                                            null) {
                                      final index = pieTouchResponse
                                          .touchedSection!.touchedSectionIndex;
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
    );
  }

  Widget _buildDetailView(BuildContext context) {
    final color = const Color(0xFFFF5252); // Expense color

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
                color: color.withOpacity(0.1),
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
                  : ListView.separated(
                      itemCount: _detailItems!.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _detailItems![index];
                        return _PeriodDetailTile(item: item, isIncome: false);
                      },
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
