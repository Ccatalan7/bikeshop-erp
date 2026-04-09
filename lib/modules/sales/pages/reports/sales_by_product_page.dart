import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/main_layout.dart';
import '../../services/sales_service.dart';
import '../../models/sales_models.dart';

class SalesByProductPage extends StatefulWidget {
  const SalesByProductPage({super.key});

  @override
  State<SalesByProductPage> createState() => _SalesByProductPageState();
}

class _SalesByProductPageState extends State<SalesByProductPage> {
  DateTimeRange? _dateRange;

  // Sorting
  int _sortColumnIndex = 2; // Default validation by Quantity
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

    // Ensure data is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SalesService>().loadInvoices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final salesService = context.watch<SalesService>();
    final currencyFormat = NumberFormat.currency(locale: 'es_CL', symbol: '\$');

    // 1. Filter Invoices by Date and Status
    final filteredInvoices = salesService.invoices.where((invoice) {
      if (invoice.status == InvoiceStatus.cancelled ||
          invoice.status == InvoiceStatus.draft) {
        return false;
      }
      if (_dateRange != null) {
        if (invoice.date.isBefore(_dateRange!.start) ||
            invoice.date
                .isAfter(_dateRange!.end.add(const Duration(days: 1)))) {
          // Add 1 day to end to make it inclusive
          return false;
        }
      }
      return true;
    }).toList();

    // 2. Aggregate by Product
    final Map<String, _ProductSalesData> aggregation = {};

    for (final invoice in filteredInvoices) {
      for (final item in invoice.items) {
        // Use product ID as key, fallback to SKU or Name for ad-hoc items
        final key =
            item.productId ?? item.productSku ?? item.productName ?? 'Unknown';

        if (!aggregation.containsKey(key)) {
          aggregation[key] = _ProductSalesData(
            id: item.productId,
            sku: item.productSku ?? '',
            name: item.productName ?? 'Item desconocido',
            isService: item.isService,
          );
        }

        final data = aggregation[key]!;
        data.quantity += item.quantity;
        data.totalAmount += item.lineTotal;
      }
    }

    final sortedList = aggregation.values.toList();

    // 3. Sort
    sortedList.sort((a, b) {
      int compare = 0;
      switch (_sortColumnIndex) {
        case 0: // Name
          compare = a.name.compareTo(b.name);
          break;
        case 1: // SKU
          compare = a.sku.compareTo(b.sku);
          break;
        case 2: // Quantity
          compare = a.quantity.compareTo(b.quantity);
          break;
        case 3: // Amount
          compare = a.totalAmount.compareTo(b.totalAmount);
          break;
        case 4: // Average Price
          compare = a.averagePrice.compareTo(b.averagePrice);
          break;
      }
      return _sortAscending ? compare : -compare;
    });

    return MainLayout(
      title: 'Ventas por artículo',
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
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          // TODO: Implement CSV Export
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Exportar'),
                      ),
                    ],
                  );
                }

                // Desktop / Wide
                return Row(
                  children: [
                    const Icon(Icons.filter_list),
                    const SizedBox(width: 8),
                    Text('Filtros:', style: theme.textTheme.titleSmall),
                    const SizedBox(width: 16),

                    // Date Range Picker
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

                    const Spacer(),

                    // Export Button (Placeholder)
                    OutlinedButton.icon(
                      onPressed: () {
                        // TODO: Implement CSV Export
                      },
                      icon: const Icon(Icons.download),
                      label: const Text('Exportar'),
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
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 800) {
                            return ListView.builder(
                              itemCount: sortedList.length,
                              padding: const EdgeInsets.all(16),
                              itemBuilder: (context, index) {
                                final data = sortedList[index];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: InkWell(
                                    onTap: data.id != null
                                        ? () => _navigateToDetail(context, data)
                                        : null,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  data.name,
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: theme
                                                        .colorScheme.primary,
                                                  ),
                                                ),
                                              ),
                                              if (data.sku.isNotEmpty)
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: theme.colorScheme
                                                        .surfaceContainerHighest,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                    data.sku,
                                                    style: theme
                                                        .textTheme.labelSmall,
                                                  ),
                                                ),
                                            ],
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
                                                    'Cantidad',
                                                    style: theme
                                                        .textTheme.labelSmall,
                                                  ),
                                                  Text(
                                                    data.quantity
                                                        .toStringAsFixed(2),
                                                    style: theme
                                                        .textTheme.bodyLarge,
                                                  ),
                                                ],
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    'Importe',
                                                    style: theme
                                                        .textTheme.labelSmall,
                                                  ),
                                                  Text(
                                                    currencyFormat.format(
                                                        data.totalAmount),
                                                    style: theme
                                                        .textTheme.titleMedium
                                                        ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                'Precio promedio:',
                                                style:
                                                    theme.textTheme.labelSmall,
                                              ),
                                              Text(
                                                currencyFormat
                                                    .format(data.averagePrice),
                                                style:
                                                    theme.textTheme.bodyMedium,
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
                            scrollDirection: Axis.vertical,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                sortColumnIndex: _sortColumnIndex,
                                sortAscending: _sortAscending,
                                columns: [
                                  DataColumn(
                                    label: const Text('Nombre del artículo'),
                                    onSort: (idx, asc) => _updateSort(idx, asc),
                                  ),
                                  DataColumn(
                                    label: const Text('SKU'),
                                    onSort: (idx, asc) => _updateSort(idx, asc),
                                  ),
                                  DataColumn(
                                    label: const Text('Cantidad vendida'),
                                    onSort: (idx, asc) => _updateSort(idx, asc),
                                    numeric: true,
                                  ),
                                  DataColumn(
                                    label: const Text('Importe'),
                                    onSort: (idx, asc) => _updateSort(idx, asc),
                                    numeric: true,
                                  ),
                                  DataColumn(
                                    label: const Text('Precio promedio'),
                                    onSort: (idx, asc) => _updateSort(idx, asc),
                                    numeric: true,
                                  ),
                                ],
                                rows: sortedList.map((data) {
                                  return DataRow(
                                    cells: [
                                      DataCell(
                                        Text(data.name,
                                            style: TextStyle(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.w500,
                                            )),
                                        onTap: data.id != null
                                            ? () =>
                                                _navigateToDetail(context, data)
                                            : null,
                                      ),
                                      DataCell(Text(data.sku)),
                                      DataCell(Text(
                                          data.quantity.toStringAsFixed(2))),
                                      DataCell(Text(currencyFormat
                                          .format(data.totalAmount))),
                                      DataCell(Text(currencyFormat
                                          .format(data.averagePrice))),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          );
                        },
                      ),
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

  void _navigateToDetail(BuildContext context, _ProductSalesData data) {
    if (data.id == null) return;

    // Pass date range via query params or extra
    final startStr = _dateRange?.start.toIso8601String() ?? '';
    final endStr = _dateRange?.end.toIso8601String() ?? '';

    context.push(
        '/sales/reports/by-product/${data.id}?start=$startStr&end=$endStr&name=${Uri.encodeComponent(data.name)}');
  }
}

class _ProductSalesData {
  final String? id;
  final String sku;
  final String name;
  final bool isService;
  double quantity;
  double totalAmount;

  _ProductSalesData({
    this.id,
    required this.sku,
    required this.name,
    required this.isService,
    this.quantity = 0.0,
    this.totalAmount = 0.0,
  });

  double get averagePrice => quantity == 0 ? 0 : totalAmount / quantity;
}
