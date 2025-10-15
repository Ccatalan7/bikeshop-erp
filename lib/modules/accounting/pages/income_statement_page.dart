import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/main_layout.dart';
import '../models/financial_report.dart';
import '../models/income_statement.dart';
import '../services/financial_reports_service.dart';
import '../widgets/report_header_widget.dart';
import '../widgets/report_line_widget.dart';
import '../widgets/date_range_selector_widget.dart';

/// Income Statement Page (Estado de Resultados)
/// Displays company profitability over a period
class IncomeStatementPage extends StatefulWidget {
  const IncomeStatementPage({super.key});

  @override
  State<IncomeStatementPage> createState() => _IncomeStatementPageState();
}

class _IncomeStatementPageState extends State<IncomeStatementPage> {
  IncomeStatement? _statement;
  bool _isLoading = false;
  String? _errorMessage;
  
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
      );

      setState(() {
        _statement = statement;
        _isLoading = false;
      });
    } catch (e) {
      String errorMsg = 'Error al generar el reporte: $e';
      
      // Check if it's a function not found error
      if (e.toString().contains('function') && 
          (e.toString().contains('does not exist') || e.toString().contains('not found'))) {
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
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estado de Resultados'),
          actions: [
            // Refresh button
            IconButton(
              onPressed: _isLoading ? null : _loadStatement,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
            ),
            
            // Export button (future feature)
            IconButton(
              onPressed: _statement != null ? _showExportMenu : null,
              icon: const Icon(Icons.download),
              tooltip: 'Exportar',
            ),
            
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            // Date range selector
            Padding(
              padding: const EdgeInsets.all(16),
              child: DateRangeSelectorWidget(
                initialRange: _dateRange,
                initialPeriod: _selectedPeriod,
                onRangeChanged: _onDateRangeChanged,
                showEndDate: true,
              ),
            ),
            
            // Report content
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
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
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
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
          // Report header
          ReportHeaderWidget(
            companyName: _statement!.companyName,
            reportTitle: _statement!.title,
            subtitle: _statement!.subtitle,
            generatedAt: _statement!.generatedAt,
          ),
          
          const SizedBox(height: 24),
          
          // Key metrics cards
          _buildMetricsCards(),
          
          const SizedBox(height: 24),
          
          // Report lines with horizontal scroll if needed
          LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = constraints.maxWidth > 1200 ? 1200.0 : constraints.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  width: contentWidth,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    elevation: 2,
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
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildMetricsCards() {
    if (_statement == null) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
          const SizedBox(width: 16),
          Expanded(
            child: _buildMetricCard(
              'Utilidad Operacional',
              _currencyFormat.format(_statement!.operatingProfit),
              '${_statement!.operatingMargin.toStringAsFixed(1)}%',
              Icons.business,
              Colors.orange,
            ),
          ),
          const SizedBox(width: 16),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              amount,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Margen: $percentage',
              style: Theme.of(context).textTheme.bodySmall,
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
                    const SnackBar(content: Text('Exportación PDF disponible próximamente')),
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
                    const SnackBar(content: Text('Exportación Excel disponible próximamente')),
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
