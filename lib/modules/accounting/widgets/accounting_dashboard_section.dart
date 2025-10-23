import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/dashboard_metrics.dart';
import '../services/accounting_service.dart';
import '../services/financial_reports_service.dart';

enum _ChartSeriesMode { monthly, cumulative }

class AccountingDashboardSection extends StatefulWidget {
  const AccountingDashboardSection({super.key});

  @override
  State<AccountingDashboardSection> createState() =>
      _AccountingDashboardSectionState();
}

class _AccountingDashboardSectionState
    extends State<AccountingDashboardSection> {
  static const List<int> _monthOptions = [6, 12, 18, 24];

  late Future<_DashboardPayload> _loadFuture;
  int _selectedMonths = 12;
  _ChartSeriesMode _seriesMode = _ChartSeriesMode.monthly;

  @override
  void initState() {
    super.initState();
    _loadFuture = _fetchData();
  }

  Future<_DashboardPayload> _fetchData({int? months}) async {
    final monthsToLoad = months ?? _selectedMonths;
    final accountingService = context.read<AccountingService>();
    final reportsService = context.read<FinancialReportsService>();

    await accountingService.initialize();

    final series =
        await reportsService.getIncomeExpenseTimeseries(months: monthsToLoad);

    final now = DateTime.now();
    final currentMonthStart = DateTime(now.year, now.month);
    final lastMonthEnd = currentMonthStart.subtract(const Duration(days: 1));
    final lastMonthStart = DateTime(lastMonthEnd.year, lastMonthEnd.month);

    final breakdown = await reportsService.getExpenseBreakdown(
      startDate: lastMonthStart,
      endDate: lastMonthEnd,
      limit: 6,
    );

    final totalIncome =
        series.fold<double>(0, (sum, point) => sum + point.income);
    final totalExpense =
        series.fold<double>(0, (sum, point) => sum + point.expense);

    final monthLabel = DateFormat('MMMM yyyy', 'es_CL').format(lastMonthStart);

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

  const _DashboardPayload({
    required this.series,
    required this.expenseBreakdown,
    required this.trailingLabel,
    required this.totalIncome,
    required this.totalExpense,
    required this.months,
    required this.rangeStart,
    required this.rangeEnd,
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

  const _DashboardContent({
    required this.data,
    required this.selectedMonths,
    required this.monthOptions,
    required this.onMonthsChanged,
    required this.seriesMode,
    required this.onSeriesModeChanged,
    required this.onRefresh,
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
                    child: SizedBox(
                      height: chartHeight,
                      child: _IncomeExpenseCard(
                        data: data.series,
                        height: chartHeight,
                        mode: seriesMode,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: chartHeight,
                      child: _ExpenseBreakdownCard(
                        items: data.expenseBreakdown,
                        monthLabel: data.trailingLabel,
                        height: chartHeight,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: _IncomeExpenseCard(
                      data: data.series,
                      height: chartHeight,
                      mode: seriesMode,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: _ExpenseBreakdownCard(
                      items: data.expenseBreakdown,
                      monthLabel: data.trailingLabel,
                      height: chartHeight,
                    ),
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
  final double height;
  final _ChartSeriesMode mode;

  const _IncomeExpenseCard({
    required this.data,
    required this.height,
    required this.mode,
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 12, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresos vs gastos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              mode == _ChartSeriesMode.monthly
                  ? 'Resultados mensuales'
                  : 'Acumulado del período',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: height,
              child: BarChart(
                BarChartData(
                  maxY: chartMax,
                  gridData: FlGridData(
                    show: true,
                    drawHorizontalLine: true,
                    horizontalInterval: chartMax / 5,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withOpacity(0.2),
                      strokeWidth: 1,
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
                        interval: chartMax / 4,
                        getTitlesWidget: (value, meta) {
                          final formatter = NumberFormat.compactCurrency(
                            locale: 'es_CL',
                            symbol: 'CLP',
                          );
                          return Text(
                            formatter.format(value),
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
                          final label =
                              displayData[index].monthLabel().toUpperCase();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              label,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          );
                        },
                        reservedSize: 48,
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
                            color: const Color(0xFF2E7D32),
                            width: 10,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(4),
                              topRight: Radius.circular(4),
                            ),
                          ),
                          BarChartRodData(
                            toY: displayData[i].expense,
                            color: const Color(0xFFC62828),
                            width: 10,
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
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: const [
                _LegendChip(label: 'Ingresos', color: Color(0xFF2E7D32)),
                _LegendChip(label: 'Gastos', color: Color(0xFFC62828)),
              ],
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
    return input
        .map(
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
        )
        .toList(growable: false);
  }
}

class _LegendChip extends StatelessWidget {
  final String label;
  final Color color;

  const _LegendChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: CircleAvatar(backgroundColor: color),
      label: Text(label),
      backgroundColor: color.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}

class _ExpenseBreakdownCard extends StatelessWidget {
  final List<ExpenseBreakdownItem> items;
  final String monthLabel;
  final double height;

  const _ExpenseBreakdownCard({
    required this.items,
    required this.monthLabel,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Card(
        child: SizedBox(
          height: height,
          child: Center(
            child: Text(
              'No hay gastos registrados en $monthLabel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }

    final total =
        items.fold<double>(0, (sum, item) => sum + item.displayAmount);
    final palette = _buildPalette(context, items.length);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Gastos principales ($monthLabel)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: height,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 60,
                        sections: [
                          for (var i = 0; i < items.length; i++)
                            PieChartSectionData(
                              value: items[i].displayAmount,
                              color: palette[i],
                              radius: height / 3,
                              title:
                                  '${((items[i].displayAmount / total) * 100).round()}%',
                              titleStyle: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < items.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    margin: const EdgeInsets.only(top: 6),
                                    decoration: BoxDecoration(
                                      color: palette[i],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${items[i].accountCode} · ${items[i].accountName}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                        Text(
                                          NumberFormat.currency(
                                            locale: 'es_CL',
                                            symbol: 'CLP',
                                          ).format(
                                              items[i].displayAmount.round()),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  color: Theme.of(context)
                                                      .hintColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
      ),
    );
  }

  List<Color> _buildPalette(BuildContext context, int count) {
    final baseColors = [
      const Color(0xFF1565C0),
      const Color(0xFF2E7D32),
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
