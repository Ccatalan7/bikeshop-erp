import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../shared/widgets/main_layout.dart';
import '../../services/sales_service.dart';
import '../../models/sales_models.dart';

class SalesByProductDetailPage extends StatelessWidget {
  final String productId;
  final String? productName;
  final DateTime? startDate;
  final DateTime? endDate;

  const SalesByProductDetailPage({
    super.key,
    required this.productId,
    this.productName,
    this.startDate,
    this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final salesService = context.watch<SalesService>();
    final currencyFormat = NumberFormat.currency(locale: 'es_CL', symbol: '\$');
    final dateFormat = DateFormat('dd/MM/yyyy');

    // Filter logic
    final transactions = <_TransactionItem>[];

    for (final invoice in salesService.invoices) {
      if (invoice.status == InvoiceStatus.cancelled ||
          invoice.status == InvoiceStatus.draft) {
        continue;
      }

      if (startDate != null && invoice.date.isBefore(startDate!)) continue;
      if (endDate != null &&
          invoice.date.isAfter(endDate!.add(const Duration(days: 1)))) continue;

      for (final item in invoice.items) {
        if (item.productId == productId) {
          transactions.add(_TransactionItem(
            invoiceId: invoice.id,
            invoiceNumber: invoice.invoiceNumber,
            date: invoice.date,
            customerName: invoice.customerName ?? 'Cliente Desconocido',
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            total: item.lineTotal,
          ));
        }
      }
    }

    // Sort by date desc
    transactions.sort((a, b) => b.date.compareTo(a.date));

    // Calculate totals
    final totalQty = transactions.fold(0.0, (sum, t) => sum + t.quantity);
    final totalAmount = transactions.fold(0.0, (sum, t) => sum + t.total);
    final avgPrice = totalQty > 0 ? totalAmount / totalQty : 0.0;

    return MainLayout(
      title: productName ?? 'Detalle de Producto',
      onBackPressed: () => context.pop(),
      child: LayoutBuilder(builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        return Column(
          children: [
            // Summary Card
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: isMobile
                      ? Column(
                          children: [
                            _SummaryStat(
                              label: 'Cantidad Total',
                              value: totalQty.toStringAsFixed(2),
                              theme: theme,
                            ),
                            const Divider(height: 24),
                            _SummaryStat(
                              label: 'Importe Total',
                              value: currencyFormat.format(totalAmount),
                              theme: theme,
                            ),
                            const Divider(height: 24),
                            _SummaryStat(
                              label: 'Precio Promedio',
                              value: currencyFormat.format(avgPrice),
                              theme: theme,
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _SummaryStat(
                              label: 'Cantidad Total',
                              value: totalQty.toStringAsFixed(2),
                              theme: theme,
                            ),
                            _SummaryStat(
                              label: 'Importe Total',
                              value: currencyFormat.format(totalAmount),
                              theme: theme,
                            ),
                            _SummaryStat(
                              label: 'Precio Promedio',
                              value: currencyFormat.format(avgPrice),
                              theme: theme,
                            ),
                          ],
                        ),
                ),
              ),
            ),

            // Transactions Table
            Expanded(
              child: transactions.isEmpty
                  ? const Center(
                      child: Text(
                          'No hay transacciones para el periodo seleccionado'))
                  : isMobile
                      ? ListView.builder(
                          itemCount: transactions.length,
                          padding: const EdgeInsets.all(16),
                          itemBuilder: (context, index) {
                            final t = transactions[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: InkWell(
                                onTap: t.invoiceId != null
                                    ? () => context
                                        .push('/sales/invoices/${t.invoiceId}')
                                    : null,
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            dateFormat.format(t.date),
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                          Text(
                                            t.invoiceNumber.isEmpty
                                                ? 'Borrador'
                                                : t.invoiceNumber,
                                            style: theme.textTheme.titleSmall
                                                ?.copyWith(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        t.customerName,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: FontWeight.w500,
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
                                              Text('Cant.',
                                                  style: theme
                                                      .textTheme.labelSmall),
                                              Text(t.quantity
                                                  .toStringAsFixed(0)),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text('Precio Unit.',
                                                  style: theme
                                                      .textTheme.labelSmall),
                                              Text(currencyFormat
                                                  .format(t.unitPrice)),
                                            ],
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text('Total',
                                                  style: theme
                                                      .textTheme.labelSmall),
                                              Text(
                                                currencyFormat.format(t.total),
                                                style: theme
                                                    .textTheme.titleSmall
                                                    ?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : SingleChildScrollView(
                          child: SizedBox(
                            width: double.infinity,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Fecha')),
                                DataColumn(label: Text('Nº Factura')),
                                DataColumn(label: Text('Cliente')),
                                DataColumn(
                                    label: Text('Cantidad'), numeric: true),
                                DataColumn(
                                    label: Text('Precio Unit.'), numeric: true),
                                DataColumn(label: Text('Total'), numeric: true),
                              ],
                              rows: transactions.map((t) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(dateFormat.format(t.date))),
                                    DataCell(
                                      Text(
                                        t.invoiceNumber.isEmpty
                                            ? 'Borrador'
                                            : t.invoiceNumber,
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                      onTap: t.invoiceId != null
                                          ? () => context.push(
                                              '/sales/invoices/${t.invoiceId}')
                                          : null,
                                    ),
                                    DataCell(Text(t.customerName)),
                                    DataCell(
                                        Text(t.quantity.toStringAsFixed(0))),
                                    DataCell(Text(
                                        currencyFormat.format(t.unitPrice))),
                                    DataCell(
                                        Text(currencyFormat.format(t.total))),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
            ),
          ],
        );
      }),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  const _SummaryStat({
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _TransactionItem {
  final String? invoiceId;
  final String invoiceNumber;
  final DateTime date;
  final String customerName;
  final double quantity;
  final double unitPrice;
  final double total;

  _TransactionItem({
    this.invoiceId,
    required this.invoiceNumber,
    required this.date,
    required this.customerName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });
}
