import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/dashboard_metrics.dart';
import '../services/accounting_service.dart';
import '../services/financial_reports_service.dart';

enum _ChartSeriesMode { monthly, cumulative }
enum _ExpenseBreakdownRange { previousMonth, last3Months, last6Months }

extension on _ExpenseBreakdownRange {
  String get label {
    switch (this) {
      case _ExpenseBreakdownRange.previousMonth:
        return 'Mes anterior';
      case _ExpenseBreakdownRange.last3Months:
        return 'Últimos 3 meses';
      case _ExpenseBreakdownRange.last6Months:
        return 'Últimos 6 meses';
    }
  }

}

class AccountingDashboardSection extends StatefulWidget {
  const AccountingDashboardSection({super.key});

  @override
  State<AccountingDashboardSection> createState() =>
      _AccountingDashboardSectionState();
}

class _AccountingDashboardSectionState
    extends State<AccountingDashboardSection> {
  static const List<int> _monthOptions = [6, 12, 18, 24];
  static const List<_ExpenseBreakdownRange> _breakdownOptions = [
    _ExpenseBreakdownRange.previousMonth,
    _ExpenseBreakdownRange.last3Months,
    _ExpenseBreakdownRange.last6Months,
  ];

  late Future<_DashboardPayload> _loadFuture;
  int _selectedMonths = 12;
  _ChartSeriesMode _seriesMode = _ChartSeriesMode.monthly;
  _ExpenseBreakdownRange _breakdownRange =
      _ExpenseBreakdownRange.previousMonth;

  @override
  void initState() {
    super.initState();
    _loadFuture = Future.value(_DashboardPayload(
      series: [],
      expenseBreakdown: [],
      trailingLabel: '',
      totalIncome: 0,
      totalExpense: 0,
      months: _selectedMonths,
      rangeStart: DateTime.now(),
      rangeEnd: DateTime.now(),
      breakdownRange: _ExpenseBreakdownRange.previousMonth,
      breakdownStart: DateTime.now(),
      breakdownEnd: DateTime.now(),
      breakdownTotal: 0,
    ));

    Future.microtask(() async {
      final accountingService = context.read<AccountingService>();
      await accountingService.initialize();
      if (mounted) {
        setState(() {
          _loadFuture = _fetchData();
        });
      }
    });
  }

  Future<_DashboardPayload> _fetchData({
    int? months,
    _ExpenseBreakdownRange? breakdownRange,
  }) async {
    final monthsToLoad = months ?? _selectedMonths;
    final selectedBreakdownRange = breakdownRange ?? _breakdownRange;
    final reportsService = context.read<FinancialReportsService>();

    final series =
        await reportsService.getIncomeExpenseTimeseries(months: monthsToLoad);

    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month);
    final previousMonthEnd = currentMonthStart.subtract(const Duration(days: 1));

    DateTime breakdownStart;
    DateTime breakdownEnd;
    switch (selectedBreakdownRange) {
      case _ExpenseBreakdownRange.previousMonth:
        breakdownStart = DateTime(previousMonthEnd.year, previousMonthEnd.month);
        breakdownEnd = DateTime(previousMonthEnd.year, previousMonthEnd.month,
            previousMonthEnd.day, 23, 59, 59);
        break;
      case _ExpenseBreakdownRange.last3Months:
        final startSeed = DateTime(previousMonthEnd.year,
            previousMonthEnd.month - 2, 1);
        breakdownStart = startSeed;
        breakdownEnd = DateTime(previousMonthEnd.year, previousMonthEnd.month,
            previousMonthEnd.day, 23, 59, 59);
        break;
      case _ExpenseBreakdownRange.last6Months:
        final startSeed = DateTime(previousMonthEnd.year,
            previousMonthEnd.month - 5, 1);
        breakdownStart = startSeed;
        breakdownEnd = DateTime(previousMonthEnd.year, previousMonthEnd.month,
            previousMonthEnd.day, 23, 59, 59);
        break;
    }

    final breakdown = await reportsService.getExpenseBreakdown(
      startDate: breakdownStart,
      endDate: breakdownEnd,
      limit: 8,
    );

    final totalIncome =
        series.fold<double>(0, (sum, point) => sum + point.income);
    final totalExpense =
        series.fold<double>(0, (sum, point) => sum + point.expense);

    final breakdownTotal =
        breakdown.fold<double>(0, (sum, item) => sum + item.displayAmount);

    final monthLabel = selectedBreakdownRange.label;

    final rangeStart = series.isNotEmpty ? series.first.periodStart : now;
    final rangeEnd = series.isNotEmpty ? series.last.periodEnd : now;

    return _DashboardPayload(
      series: series,
      expenseBreakdown: breakdown,
      trailingLabel: monthLabel,
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      months: monthsToLoad,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      breakdownRange: selectedBreakdownRange,
      breakdownStart: breakdownStart,
      breakdownEnd: breakdownEnd,
      breakdownTotal: breakdownTotal,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardPayload>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _DashboardSkeleton();
        }

        if (snapshot.hasError) {
          return _DashboardError(
            error: snapshot.error,
            onRetry: () => setState(() {
              _loadFuture = _fetchData();
            }),
          );
        }

        final data = snapshot.data;
        if (data == null || data.series.isEmpty) {
          return _DashboardEmpty(
              onRetry: () => setState(() {
                    _loadFuture = _fetchData();
                  }));
        }

        return _DashboardContent(
          data: data,
          selectedMonths: _selectedMonths,
          monthOptions: _monthOptions,
          onMonthsChanged: (value) {
            if (value == null || value == _selectedMonths) {
              return;
            }
            setState(() {
              _selectedMonths = value;
              _loadFuture = _fetchData();
            });
          },
          seriesMode: _seriesMode,
          onSeriesModeChanged: (mode) {
            if (mode == _seriesMode) return;
            setState(() {
              _seriesMode = mode;
            });
          },
          onRefresh: () => setState(() {
            _loadFuture = _fetchData();
          }),
          selectedBreakdownRange: _breakdownRange,
          breakdownOptions: _breakdownOptions,
          onBreakdownRangeChanged: (range) {
            if (range == _breakdownRange) return;
            setState(() {
              _breakdownRange = range;
              _loadFuture = _fetchData(breakdownRange: range);
            });
          },
        );
      },
    );
  }
}

class _DashboardPayload {
  final List<MonthlyIncomeExpensePoint> series;
  final List<ExpenseBreakdownItem> expenseBreakdown;
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
  final int selectedMonths;
  final List<int> monthOptions;
  final ValueChanged<int?> onMonthsChanged;
  final _ChartSeriesMode seriesMode;
  final ValueChanged<_ChartSeriesMode> onSeriesModeChanged;
  final VoidCallback onRefresh;
  final _ExpenseBreakdownRange selectedBreakdownRange;
  final List<_ExpenseBreakdownRange> breakdownOptions;
  final ValueChanged<_ExpenseBreakdownRange> onBreakdownRangeChanged;

  const _DashboardContent({
    required this.data,
    required this.selectedMonths,
    required this.monthOptions,
    required this.onMonthsChanged,
    required this.seriesMode,
    required this.onSeriesModeChanged,
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
        final chartHeight =
            math.min(360.0, constraints.maxWidth / (isWide ? 3 : 1.5));

        final charts = isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _IncomeExpenseCard(
                      data: data.series,
                      chartHeight: chartHeight,
                      mode: seriesMode,
                      onModeChanged: onSeriesModeChanged,
                      selectedMonths: selectedMonths,
                      monthOptions: monthOptions,
                      onMonthsChanged: onMonthsChanged,
                      totalIncome: data.totalIncome,
                      totalExpense: data.totalExpense,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _ExpenseBreakdownCard(
                      items: data.expenseBreakdown,
                      chartHeight: chartHeight,
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
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IncomeExpenseCard(
                    data: data.series,
                    chartHeight: chartHeight,
                    mode: seriesMode,
                    onModeChanged: onSeriesModeChanged,
                    selectedMonths: selectedMonths,
                    monthOptions: monthOptions,
                    onMonthsChanged: onMonthsChanged,
                    totalIncome: data.totalIncome,
                    totalExpense: data.totalExpense,
                  ),
                  const SizedBox(height: 16),
                  _ExpenseBreakdownCard(
                    items: data.expenseBreakdown,
                    chartHeight: chartHeight,
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
            _DashboardHeader(
              totalIncome: data.totalIncome,
              totalExpense: data.totalExpense,
              totalNet: data.totalNet,
              onRefresh: onRefresh,
            ),
            const SizedBox(height: 16),
            charts,
          ],
        );
      },
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  final double totalIncome;
  final double totalExpense;
  final double totalNet;
  final VoidCallback onRefresh;

  const _DashboardHeader({
    required this.totalIncome,
    required this.totalExpense,
    required this.totalNet,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    String formatCLP(double value) {
      final formatter = NumberFormat.currency(locale: 'es_CL', symbol: 'CLP');
      return formatter.format(value.round());
    }

    final netColor = totalNet >= 0
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.error;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Resumen contable (últimos 12 meses)',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: onRefresh,
                  tooltip: 'Actualizar datos',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _StatChip(
                  label: 'Total de ingresos',
                  value: formatCLP(totalIncome),
                  color: const Color(0xFF1B5E20),
                  icon: Icons.trending_up,
                ),
                _StatChip(
                  label: 'Total de gastos',
                  value: formatCLP(totalExpense),
                  color: const Color(0xFFB71C1C),
                  icon: Icons.trending_down,
                ),
                _StatChip(
                  label: 'Resultado neto',
                  value: formatCLP(totalNet),
                  color: netColor,
                  icon:
                      totalNet >= 0 ? Icons.stacked_line_chart : Icons.warning,
                ),
              ],
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

class _IncomeExpenseCard extends StatelessWidget {
  final List<MonthlyIncomeExpensePoint> data;
  final double chartHeight;
  final _ChartSeriesMode mode;
  final ValueChanged<_ChartSeriesMode>? onModeChanged;
  final int selectedMonths;
  final List<int> monthOptions;
  final ValueChanged<int?>? onMonthsChanged;
  final double totalIncome;
  final double totalExpense;

  const _IncomeExpenseCard({
    required this.data,
    required this.chartHeight,
    required this.mode,
    this.onModeChanged,
    required this.selectedMonths,
    required this.monthOptions,
    required this.onMonthsChanged,
    required this.totalIncome,
    required this.totalExpense,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }

    final displayData =
        mode == _ChartSeriesMode.monthly ? data : _buildCumulative(data);

    final maxValue = displayData
        .map((point) => math.max(point.income.abs(), point.expense.abs()))
        .fold<double>(0, (previous, value) => math.max(previous, value));
    final chartMax = maxValue == 0 ? 1000.0 : maxValue * 1.15;
    final axisInterval = chartMax <= 0 ? 1.0 : chartMax / 4;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 24),
        child: Column(
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
                  child: DropdownButton<int>(
                    value: selectedMonths,
                    borderRadius: BorderRadius.circular(12),
                    onChanged: onMonthsChanged,
                    style: Theme.of(context).textTheme.bodyMedium,
                    items: monthOptions
                        .map(
                          (value) => DropdownMenuItem<int>(
                            value: value,
                            child: Text('Últimos $value meses'),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (onModeChanged != null)
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<_ChartSeriesMode>(
                  segments: const [
                    ButtonSegment<_ChartSeriesMode>(
                      value: _ChartSeriesMode.monthly,
                      label: Text('Efectivo'),
                      icon: Icon(Icons.ssid_chart_outlined),
                    ),
                    ButtonSegment<_ChartSeriesMode>(
                      value: _ChartSeriesMode.cumulative,
                      label: Text('Acumulación'),
                      icon: Icon(Icons.timeline),
                    ),
                  ],
                  selected: {mode},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity:
                        VisualDensity(horizontal: -3, vertical: -3),
                  ),
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    final next = selection.first;
                    if (next != mode) {
                      onModeChanged?.call(next);
                    }
                  },
                ),
              ),
            const SizedBox(height: 8),
            Text(
              mode == _ChartSeriesMode.monthly
                  ? 'Resultados efectivos por mes'
                  : 'Comportamiento acumulado del período',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: math.max(chartHeight, 200.0),
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
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
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
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= displayData.length) {
                            return const SizedBox.shrink();
                          }
                          if (displayData.length > 10 && index % 2 == 1) {
                            return const SizedBox.shrink();
                          }
                          final date = displayData[index].periodStart;
                          final month = DateFormat('MMM', 'es_CL')
                              .format(date)
                              .toUpperCase();
                          final year = DateFormat('yyyy').format(date);
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '$month\n$year',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          );
                        },
                        reservedSize: 30,
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < displayData.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 8,
                        barRods: [
                          BarChartRodData(
                            toY: displayData[i].income,
                            color: const Color(0xFF4CAF50),
                            width: 12,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(4),
                            ),
                          ),
                          BarChartRodData(
                            toY: displayData[i].expense,
                            color: const Color(0xFFFF5252),
                            width: 12,
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
                          '${displayData[group.x.toInt()].monthLabel()}\n$label: ${formatter.format(rod.toY)}',
                          const TextStyle(color: Colors.white),
                        );
                      },
                    ),
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
                  amount: totalIncome,
                  color: const Color(0xFF4CAF50),
                ),
                _LegendSummary(
                  title: 'Gastos',
                  description: 'Total de gastos',
                  amount: totalExpense,
                  color: const Color(0xFFFF5252),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '* Los valores de ingresos y gastos que se muestran no incluyen impuestos.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(
                    color: Theme.of(context).hintColor,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  List<MonthlyIncomeExpensePoint> _buildCumulative(
    List<MonthlyIncomeExpensePoint> input,
  ) {
    var runningIncome = 0.0;
    var runningExpense = 0.0;
    return input.map(
      (point) {
        runningIncome += point.income;
        runningExpense += point.expense;
        return MonthlyIncomeExpensePoint(
          periodStart: point.periodStart,
          periodEnd: point.periodEnd,
          income: runningIncome,
          expense: runningExpense,
        );
      },
    ).toList(growable: false);
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

class _ExpenseBreakdownCard extends StatelessWidget {
  final List<ExpenseBreakdownItem> items;
  final double chartHeight;
  final _ExpenseBreakdownRange breakdownRange;
  final String rangeLabel;
  final List<_ExpenseBreakdownRange> breakdownOptions;
  final ValueChanged<_ExpenseBreakdownRange> onRangeChanged;
  final double totalAmount;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  const _ExpenseBreakdownCard({
    required this.items,
    required this.chartHeight,
    required this.breakdownRange,
    required this.rangeLabel,
    required this.breakdownOptions,
    required this.onRangeChanged,
    required this.totalAmount,
    required this.rangeStart,
    required this.rangeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveHeight = math.max(chartHeight, 220.0);
    final currency = NumberFormat.currency(
      locale: 'es_CL',
      symbol: 'CLP',
      decimalDigits: 0,
    );

    if (items.isEmpty) {
      return Card(
        child: SizedBox(
          height: effectiveHeight,
          child: Center(
            child: Text(
              'No hay gastos registrados en ${rangeLabel.toLowerCase()}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }

    final palette = _buildPalette(context, items.length);
    final total = totalAmount == 0
        ? items.fold<double>(0, (sum, item) => sum + item.displayAmount)
        : totalAmount;
    final startLabel = DateFormat('dd MMM', 'es_CL').format(rangeStart);
    final endLabel = DateFormat('dd MMM yyyy', 'es_CL').format(rangeEnd);
    final rangeDescription = '$rangeLabel · $startLabel – $endLabel';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Gastos principales',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<_ExpenseBreakdownRange>(
                    value: breakdownRange,
                    borderRadius: BorderRadius.circular(12),
                    onChanged: (value) {
                      if (value != null) {
                        onRangeChanged(value);
                      }
                    },
                    items: breakdownOptions
                        .map(
                          (option) => DropdownMenuItem<
                              _ExpenseBreakdownRange>(
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
            const SizedBox(height: 16),
            SizedBox(
              height: effectiveHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PieChart(
                          PieChartData(
                            sectionsSpace: 4,
                            centerSpaceRadius: 58,
                            sections: [
                              for (var i = 0; i < items.length; i++)
                                PieChartSectionData(
                                  value: items[i].displayAmount,
                                  color: palette[i],
                                  radius: effectiveHeight / 3.2,
                                  title: '',
                                ),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'GASTOS',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'PRINCIPALES',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).hintColor,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              currency.format(total.round()),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < items.length; i++)
                            _ExpenseLegendRow(
                              color: palette[i],
                              accountCode: items[i].accountCode,
                              accountName: items[i].accountName,
                              amount: items[i].displayAmount,
                              total: total,
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
      ),
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
