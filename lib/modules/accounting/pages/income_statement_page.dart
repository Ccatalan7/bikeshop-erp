import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../models/financial_report.dart';
import '../models/income_statement.dart';
import '../services/financial_reports_service.dart';
import '../widgets/report_line_widget.dart';

/// Income Statement Page (Estado de Resultados)
/// Displays company profitability over a period
/// Redesigned for compact, space-efficient layout
class IncomeStatementPage extends StatefulWidget {
  const IncomeStatementPage({super.key});

  @override
  State<IncomeStatementPage> createState() => _IncomeStatementPageState();
}

class _IncomeStatementPageState extends State<IncomeStatementPage> {
  IncomeStatement? _statement;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isCashFlow = true; // Default to Cash Flow (Efectivo)

  late DateRange _dateRange;
  late ReportPeriod _selectedPeriod;
  final NumberFormat _currencyFormat = NumberFormat.currency(
    symbol: '\$',
    decimalDigits: 0,
    locale: 'es_CL',
  );

  @override
  void initState() {
    super.initState();
    // Default to current month
    _selectedPeriod = ReportPeriod.currentMonth;
    _dateRange = _selectedPeriod.getDateRange();
    _loadStatement();
  }

  Future<void> _loadStatement() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = context.read<FinancialReportsService>();
      final statement = await service.generateIncomeStatement(
        startDate: _dateRange.start,
        endDate: _dateRange.end,
        isCashFlow: _isCashFlow,
      );

      setState(() {
        _statement = statement;
        _isLoading = false;
      });
    } catch (e) {
      String errorMsg = 'Error al generar el reporte: $e';

      // Check if it's a function not found error
      if (e.toString().contains('function') &&
          (e.toString().contains('does not exist') ||
              e.toString().contains('not found'))) {
        errorMsg = 'La función de base de datos no existe.\n\n'
            'Por favor, ejecuta el archivo:\n'
            'supabase/sql/core_schema.sql\n\n'
            'en tu base de datos Supabase para crear las funciones necesarias.';
      }

      setState(() {
        _errorMessage = errorMsg;
        _isLoading = false;
      });
    }
  }

  void _onDateRangeChanged(DateRange range, ReportPeriod period) {
    setState(() {
      _dateRange = range;
      _selectedPeriod = period;
    });
    _loadStatement();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          // Minimal header like Zoho - single compact row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                // Title
                Text(
                  'Estado de Resultados',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 24),
                // Period dropdown (compact, inline)
                SizedBox(
                  width: 160, // Reduced from 200
                  child: DropdownButtonFormField<ReportPeriod>(
                    initialValue: _selectedPeriod,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Período',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      prefixIcon: Icon(Icons.calendar_today, size: 18),
                    ),
                    items: ReportPeriod.values.map((period) {
                      return DropdownMenuItem(
                        value: period,
                        child: Text(
                          period.displayName,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (period) {
                      if (period != null && period != ReportPeriod.custom) {
                        final range = period.getDateRange();
                        _onDateRangeChanged(range, period);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Accounting Basis Toggle
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: true,
                      label: Text('Efectivo'),
                      icon: Icon(Icons.payments, size: 16),
                    ),
                    ButtonSegment<bool>(
                      value: false,
                      label: Text('Devengado'),
                      icon: Icon(Icons.receipt_long, size: 16),
                    ),
                  ],
                  selected: {_isCashFlow},
                  onSelectionChanged: (Set<bool> newSelection) {
                    setState(() {
                      _isCashFlow = newSelection.first;
                    });
                    _loadStatement();
                  },
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: WidgetStateProperty.all(
                      BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Date range display
                Flexible(
                  child: Text(
                    '${_formatDate(_dateRange.start)} - ${_formatDate(_dateRange.end)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Spacer(),
                // Refresh button
                IconButton(
                  onPressed: _isLoading ? null : _loadStatement,
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Actualizar',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                const SizedBox(width: 4),
                // Export button
                IconButton(
                  onPressed: _statement != null ? _showExportMenu : null,
                  icon: const Icon(Icons.download, size: 18),
                  tooltip: 'Exportar',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),

          // Report content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            BrandedLoading(),
            SizedBox(height: 12),
            Text('Generando reporte...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadStatement,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_statement == null) {
      return const Center(
        child: Text('No hay datos para mostrar'),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 12),

          // Key metrics cards (more compact)
          _buildMetricsCards(),

          const SizedBox(height: 12),

          // Report lines with horizontal scroll if needed
          LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth =
                  constraints.maxWidth > 1000 ? 1000.0 : constraints.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  width: contentWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Card(
                    elevation: 1,
                    margin: EdgeInsets.zero,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _statement!.allLines.map((line) {
                        return ReportLineWidget(
                          line: line,
                          currencyFormat: _currencyFormat,
                          showCode: true,
                        );
                      }).toList(),
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildMetricsCards() {
    if (_statement == null) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 1000),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _buildMetricCard(
              'Utilidad Bruta',
              _currencyFormat.format(_statement!.grossProfit),
              '${_statement!.grossMargin.toStringAsFixed(1)}%',
              Icons.trending_up,
              Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildMetricCard(
              'Utilidad Operacional',
              _currencyFormat.format(_statement!.operatingProfit),
              '${_statement!.operatingMargin.toStringAsFixed(1)}%',
              Icons.business,
              Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildMetricCard(
              'Utilidad Neta',
              _currencyFormat.format(_statement!.netIncome),
              '${_statement!.netMargin.toStringAsFixed(1)}%',
              Icons.account_balance_wallet,
              _statement!.isProfitable ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String amount,
    String percentage,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(10), // Reduced from 16
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                          fontSize: 11,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              amount,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              'Margen: $percentage',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _showExportMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Exportar a PDF'),
                subtitle: const Text('Formato profesional para imprimir'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement PDF export
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Exportación PDF disponible próximamente')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_chart),
                title: const Text('Exportar a Excel'),
                subtitle: const Text('Datos editables con fórmulas'),
                onTap: () {
                  Navigator.pop(context);
                  // TODO: Implement Excel export
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Exportación Excel disponible próximamente')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
