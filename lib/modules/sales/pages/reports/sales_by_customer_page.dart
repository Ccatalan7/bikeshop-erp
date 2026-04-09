import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/main_layout.dart';
import '../../services/sales_service.dart';
import '../../models/sales_models.dart';

class SalesByCustomerPage extends StatefulWidget {
  const SalesByCustomerPage({super.key});

  @override
  State<SalesByCustomerPage> createState() => _SalesByCustomerPageState();
}

class _SalesByCustomerPageState extends State<SalesByCustomerPage> {
  DateTimeRange? _dateRange;
  int _sortColumnIndex = 2; // Default Sort by Amount
  bool _sortAscending = false;

  @override
  void initState() {
    super.initState();
    // Default to current year
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, 1, 1),
      end: DateTime(now.year, 12, 31),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesService>().loadInvoices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final salesService = context.watch<SalesService>();
    final currencyFormat = NumberFormat.currency(locale: 'es_CL', symbol: '\$');

    // 1. Filter Invoices
    final filteredInvoices = salesService.invoices.where((invoice) {
      if (invoice.status == InvoiceStatus.cancelled ||
          invoice.status == InvoiceStatus.draft) {
        return false;
      }
      if (_dateRange != null) {
        if (invoice.date.isBefore(_dateRange!.start) ||
            invoice.date
                .isAfter(_dateRange!.end.add(const Duration(days: 1)))) {
          return false;
        }
      }
      return true;
    }).toList();

    // 2. Aggregate by Customer
    final Map<String, _CustomerSalesData> aggregation = {};

    for (final invoice in filteredInvoices) {
      final customerId = invoice.customerId ?? 'unknown';
      final customerName = invoice.customerName ?? 'Cliente Desconocido';

      if (!aggregation.containsKey(customerId)) {
        aggregation[customerId] = _CustomerSalesData(
          customerId: customerId,
          customerName: customerName,
        );
      }

      final data = aggregation[customerId]!;
      data.invoiceCount++;
      data.totalSales += invoice.total;
    }

    final sortedList = aggregation.values.toList();

    // 3. Sort
    sortedList.sort((a, b) {
      int compare = 0;
      switch (_sortColumnIndex) {
        case 0: // Name
          compare = a.customerName.compareTo(b.customerName);
          break;
        case 1: // Invoice Count
          compare = a.invoiceCount.compareTo(b.invoiceCount);
          break;
        case 2: // Total Sales
          compare = a.totalSales.compareTo(b.totalSales);
          break;
      }
      return _sortAscending ? compare : -compare;
    });

    return MainLayout(
      title: 'Ventas por cliente',
      onBackPressed: () => context.pop(),
      child: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.filter_list),
                          const SizedBox(width: 8),
                          Text('Filtros:', style: theme.textTheme.titleSmall),
                        ],
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(_dateRange == null
                            ? 'Todo el periodo'
                            : '${DateFormat('dd/MM/yyyy').format(_dateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_dateRange!.end)}'),
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                            initialDateRange: _dateRange,
                          );
                          if (picked != null) {
                            setState(() => _dateRange = picked);
                          }
                        },
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    const Icon(Icons.filter_list),
                    const SizedBox(width: 8),
                    Text('Filtros:', style: theme.textTheme.titleSmall),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(_dateRange == null
                          ? 'Todo el periodo'
                          : '${DateFormat('dd/MM/yyyy').format(_dateRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_dateRange!.end)}'),
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                          initialDateRange: _dateRange,
                        );
                        if (picked != null) {
                          setState(() => _dateRange = picked);
                        }
                      },
                    ),
                  ],
                );
              },
            ),
          ),

          // Data Table
          Expanded(
            child: salesService.isLoadingInvoices
                ? const Center(child: CircularProgressIndicator())
                : sortedList.isEmpty
                    ? const Center(
                        child:
                            Text('No hay datos para el periodo seleccionado'))
                    : LayoutBuilder(builder: (context, constraints) {
                        if (constraints.maxWidth < 600) {
                          return ListView.builder(
                            itemCount: sortedList.length,
                            padding: const EdgeInsets.all(16),
                            itemBuilder: (context, index) {
                              final data = sortedList[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: InkWell(
                                  // TODO: Add drill-down
                                  onTap: () {},
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data.customerName,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.primary,
                                          ),
                                        ),
                                        const Divider(),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Facturas',
                                                  style: theme
                                                      .textTheme.labelSmall,
                                                ),
                                                Text(
                                                  data.invoiceCount.toString(),
                                                  style:
                                                      theme.textTheme.bodyLarge,
                                                ),
                                              ],
                                            ),
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              children: [
                                                Text(
                                                  'Ventas Totales',
                                                  style: theme
                                                      .textTheme.labelSmall,
                                                ),
                                                Text(
                                                  currencyFormat
                                                      .format(data.totalSales),
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        }

                        return SingleChildScrollView(
                          child: SizedBox(
                            width: double.infinity,
                            child: DataTable(
                              sortColumnIndex: _sortColumnIndex,
                              sortAscending: _sortAscending,
                              columns: [
                                DataColumn(
                                  label: const Text('Nombre del cliente'),
                                  onSort: (idx, asc) => _updateSort(idx, asc),
                                ),
                                DataColumn(
                                  label: const Text('Recuento de facturas'),
                                  onSort: (idx, asc) => _updateSort(idx, asc),
                                  numeric: true,
                                ),
                                DataColumn(
                                  label: const Text('Ventas totales'),
                                  onSort: (idx, asc) => _updateSort(idx, asc),
                                  numeric: true,
                                ),
                              ],
                              rows: sortedList.map((data) {
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        data.customerName,
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      // TODO: Add drill-down to customer details/history if needed
                                      onTap: () {},
                                    ),
                                    DataCell(
                                        Text(data.invoiceCount.toString())),
                                    DataCell(Text(currencyFormat
                                        .format(data.totalSales))),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        );
                      }),
          ),
        ],
      ),
    );
  }

  void _updateSort(int index, bool ascending) {
    setState(() {
      _sortColumnIndex = index;
      _sortAscending = ascending;
    });
  }
}

class _CustomerSalesData {
  final String customerId;
  final String customerName;
  int invoiceCount;
  double totalSales;

  _CustomerSalesData({
    required this.customerId,
    required this.customerName,
    this.invoiceCount = 0,
    this.totalSales = 0.0,
  });
}
