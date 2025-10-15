import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/main_layout.dart';
import '../models/financial_report.dart';
import '../models/balance_sheet.dart';
import '../services/financial_reports_service.dart';
import '../widgets/report_header_widget.dart';
import '../widgets/report_line_widget.dart';
import '../widgets/date_range_selector_widget.dart';

/// Balance Sheet Page (Balance General)
/// Displays company financial position at a point in time
class BalanceSheetPage extends StatefulWidget {
  const BalanceSheetPage({super.key});

  @override
  State<BalanceSheetPage> createState() => _BalanceSheetPageState();
}

class _BalanceSheetPageState extends State<BalanceSheetPage> {
  BalanceSheet? _balanceSheet;
  bool _isLoading = false;
  String? _errorMessage;
  
  late DateTime _asOfDate;
  late ReportPeriod _selectedPeriod;
  final NumberFormat _currencyFormat = NumberFormat.currency(
    symbol: '\$',
    decimalDigits: 0,
    locale: 'es_CL',
  );

  @override
  void initState() {
    super.initState();
    // Default to end of current month
    _selectedPeriod = ReportPeriod.currentMonth;
    final range = _selectedPeriod.getDateRange();
    _asOfDate = range.end;
    _loadBalanceSheet();
  }

  Future<void> _loadBalanceSheet() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = context.read<FinancialReportsService>();
      
      // Calculate period start for ROE/ROA (beginning of year)
      final periodStart = DateTime(_asOfDate.year, 1, 1);
      
      final balanceSheet = await service.generateBalanceSheet(
        asOfDate: _asOfDate,
        periodStartDate: periodStart,
      );

      setState(() {
        _balanceSheet = balanceSheet;
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
      _asOfDate = range.end; // Balance sheet is as of end date
      _selectedPeriod = period;
    });
    _loadBalanceSheet();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Balance General'),
          actions: [
            // Refresh button
            IconButton(
              onPressed: _isLoading ? null : _loadBalanceSheet,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar',
            ),
            
            // Export button
            IconButton(
              onPressed: _balanceSheet != null ? _showExportMenu : null,
              icon: const Icon(Icons.download),
              tooltip: 'Exportar',
            ),
            
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            // Date selector
            Padding(
              padding: const EdgeInsets.all(16),
              child: DateRangeSelectorWidget(
                initialRange: DateRange(_asOfDate, _asOfDate),
                initialPeriod: _selectedPeriod,
                onRangeChanged: _onDateRangeChanged,
                showEndDate: false, // Only show single date for balance sheet
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
              onPressed: _loadBalanceSheet,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_balanceSheet == null) {
      return const Center(
        child: Text('No hay datos para mostrar'),
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // Report header
          ReportHeaderWidget(
            companyName: _balanceSheet!.companyName,
            reportTitle: _balanceSheet!.title,
            subtitle: _balanceSheet!.subtitle,
            generatedAt: _balanceSheet!.generatedAt,
          ),
          
          const SizedBox(height: 24),
          
          // Accounting equation validation
          _buildAccountingEquationCard(),
          
          const SizedBox(height: 24),
          
          // Financial ratios
          _buildFinancialRatiosCards(),
          
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
                      children: _balanceSheet!.allLines.map((line) {
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

  Widget _buildAccountingEquationCard() {
    if (_balanceSheet == null) return const SizedBox.shrink();

    final isBalanced = _balanceSheet!.isBalanced;
    final difference = _balanceSheet!.accountingEquationDifference;

    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: isBalanced
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                isBalanced ? Icons.check_circle : Icons.error,
                color: isBalanced ? Colors.green : Colors.red,
                size: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBalanced
                          ? 'Ecuación Contable Balanceada'
                          : 'Advertencia: Ecuación Contable Desbalanceada',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isBalanced ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Activos = Pasivos + Patrimonio',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (!isBalanced) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Diferencia: ${_currencyFormat.format(difference)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinancialRatiosCards() {
    if (_balanceSheet == null) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxWidth: 1200),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Indicadores Financieros',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Liquidity ratios
          Row(
            children: [
              Expanded(
                child: _buildRatioCard(
                  'Razón Corriente',
                  _balanceSheet!.currentRatio.toStringAsFixed(2),
                  'Liquidez',
                  Icons.water_drop,
                  Colors.blue,
                  'Activos Circulantes / Pasivos Circulantes',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildRatioCard(
                  'Capital de Trabajo',
                  _currencyFormat.format(_balanceSheet!.workingCapital),
                  'Liquidez',
                  Icons.account_balance,
                  Colors.cyan,
                  'Activos Circulantes - Pasivos Circulantes',
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Leverage ratios
          Row(
            children: [
              Expanded(
                child: _buildRatioCard(
                  'Endeudamiento',
                  '${(_balanceSheet!.debtRatio * 100).toStringAsFixed(1)}%',
                  'Apalancamiento',
                  Icons.trending_down,
                  Colors.orange,
                  'Pasivos / Activos',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildRatioCard(
                  'Deuda/Patrimonio',
                  _balanceSheet!.debtToEquityRatio.toStringAsFixed(2),
                  'Apalancamiento',
                  Icons.balance,
                  Colors.deepOrange,
                  'Pasivos / Patrimonio',
                ),
              ),
            ],
          ),
          
          if (_balanceSheet!.periodNetIncome != 0) ...[
            const SizedBox(height: 16),
            
            // Profitability ratios
            Row(
              children: [
                Expanded(
                  child: _buildRatioCard(
                    'ROE',
                    '${_balanceSheet!.returnOnEquity.toStringAsFixed(1)}%',
                    'Rentabilidad',
                    Icons.show_chart,
                    Colors.green,
                    'Utilidad Neta / Patrimonio',
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildRatioCard(
                    'ROA',
                    '${_balanceSheet!.returnOnAssets.toStringAsFixed(1)}%',
                    'Rentabilidad',
                    Icons.analytics,
                    Colors.teal,
                    'Utilidad Neta / Activos',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRatioCard(
    String title,
    String value,
    String category,
    IconData icon,
    Color color,
    String formula,
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
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formula,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 10,
                fontStyle: FontStyle.italic,
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
