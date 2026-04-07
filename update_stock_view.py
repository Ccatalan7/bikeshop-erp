import re

with open("lib/modules/inventory/pages/stock_movements_page.dart", "r", encoding="utf-8") as f:
    text = f.read()

# 1. find `  Widget _buildSalesInvoiceInlineView(Invoice invoice) {`
start_idx = text.find('  Widget _buildSalesInvoiceInlineView(Invoice invoice) {')
# 2. find `  Widget _buildInlinePurchaseHeader(PurchaseInvoice invoice) {`
end_idx = text.find('  Widget _buildInlinePurchaseHeader(PurchaseInvoice invoice) {')

replacement = """  Widget _buildSalesInvoiceInlineView(Invoice invoice) {
    final payments = context.read<SalesService>().getPaymentsForInvoice(invoice.id ?? '');
    final inventoryService = context.watch<InventoryService>();

    final statusColor = _salesStatusColor(invoice.status);
    final statusText = _salesStatusLabel(invoice.status);

    // Group Items by Bike
    final Map<String, List<InvoiceItem>> groupedItems = {};
    for (final item in invoice.items) {
      final key = item.bikeName?.isNotEmpty == true ? item.bikeName! : 'General';
      groupedItems.putIfAbsent(key, () => []).add(item);
    }
    final sortedKeys = groupedItems.keys.toList()
      ..sort((a, b) {
        if (a == 'General' && b != 'General') return -1;
        if (b == 'General' && a != 'General') return 1;
        return a.compareTo(b);
      });

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER ROW
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.invoiceNumber.isNotEmpty ? 'Factura ${invoice.invoiceNumber}' : 'Factura',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      invoice.customerName ?? 'Cliente Asociado',
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(invoice.status == InvoiceStatus.paid ? Icons.check_circle : Icons.info_outline, size: 16, color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      statusText.toUpperCase(),
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          
          // DATES AND SOURCE
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                _buildInfoColumn('Fecha de emisión', ChileanUtils.formatDate(invoice.date), Icons.calendar_today),
                const SizedBox(width: 32),
                if (invoice.dueDate != null) ...[
                  _buildInfoColumn('Vencimiento', ChileanUtils.formatDate(invoice.dueDate!), Icons.schedule),
                  const SizedBox(width: 32),
                ],
                _buildInfoColumn('Origen', invoice.source ?? 'sale', Icons.storefront),
                if (invoice.reference != null && invoice.reference!.isNotEmpty) ...[
                  const SizedBox(width: 32),
                  _buildInfoColumn('Referencia', invoice.reference!, Icons.link),
                ],
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          const Text('Bicicletas y Productos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          
          // ITEMS GROUPED BY BIKE
          if (invoice.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Esta factura no tiene ítems asociados.', style: TextStyle(fontStyle: FontStyle.italic))),
            )
          else
            ...sortedKeys.map((sectionKey) {
              final items = groupedItems[sectionKey]!;
              final subtotal = items.fold<double>(0, (sum, i) => sum + i.lineTotal);
              final isGeneral = sectionKey == 'General';

              return Container(
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Section Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
                      ),
                      child: Row(
                        children: [
                          Icon(isGeneral ? Icons.inventory_2_outlined : Icons.pedal_bike, size: 20, color: Colors.blue[700]),
                          const SizedBox(width: 12),
                          Text(
                            isGeneral ? 'Artículos Generales' : sectionKey,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey[800]),
                          ),
                          const Spacer(),
                          Text(
                            ChileanUtils.formatCurrency(subtotal),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey[800]),
                          ),
                        ],
                      ),
                    ),
                    // Items List
                    ...items.map((item) {
                      final product = item.productId != null ? inventoryService.getProductById(item.productId!) : null;
                      final imageUrl = product?.imageUrls.isNotEmpty == true ? product!.imageUrls.first : (product?.imageUrl);
                      final isLast = items.last == item;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        decoration: BoxDecoration(
                          border: isLast ? null : Border(bottom: BorderSide(color: Colors.grey[100]!)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Thumbnail
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey[200]!),
                                image: imageUrl != null && imageUrl.isNotEmpty
                                    ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                                    : null,
                              ),
                              child: imageUrl == null || imageUrl.isEmpty
                                  ? Icon(item.isService ? Icons.build_outlined : Icons.inventory_2_outlined, color: Colors.grey[400])
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            // Item info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName ?? item.productSku ?? 'Ítem sin nombre',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                  ),
                                  if (item.productSku != null && item.productSku!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text('SKU: ${item.productSku}', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                                  ],
                                  if (item.description != null && item.description!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(item.description!, style: TextStyle(color: Colors.grey[600], fontSize: 13, fontStyle: FontStyle.italic)),
                                  ],
                                ],
                              ),
                            ),
                            // Price
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  ChileanUtils.formatCurrency(item.lineTotal),
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_formatQuantity(item.quantity)} x ${ChileanUtils.formatCurrency(item.unitPrice)}',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                ),
                                if (item.discount > 0) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '-${ChileanUtils.formatCurrency(item.discount)}',
                                    style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              );
            }).toList(),
            
          // TOTALS
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Payments (Left side)
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Restumen de Pagos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 16),
                      if (payments.isEmpty)
                        Text('No se han registrado pagos.', style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic))
                      else
                        ...payments.map((p) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.payments_outlined, size: 16, color: Colors.green[600]),
                              const SizedBox(width: 8),
                              Expanded(child: Text(ChileanUtils.formatDate(p.date), style: TextStyle(color: Colors.grey[700]))),
                              Text(ChileanUtils.formatCurrency(p.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Summary Calculation (Right side)
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Subtotal', style: TextStyle(color: Colors.grey[600])),
                          Text(ChileanUtils.formatCurrency(invoice.subtotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('IVA (19%)', style: TextStyle(color: Colors.grey[600])),
                          Text(ChileanUtils.formatCurrency(invoice.ivaAmount), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                          Text(ChileanUtils.formatCurrency(invoice.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.blue)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Pagado', style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)),
                          Text(ChileanUtils.formatCurrency(invoice.paidAmount), style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Saldo Pendiente', style: TextStyle(color: invoice.balance > 0 ? Colors.orange[800] : Colors.grey[600], fontWeight: FontWeight.w600)),
                          Text(ChileanUtils.formatCurrency(invoice.balance), style: TextStyle(color: invoice.balance > 0 ? Colors.orange[800] : Colors.grey[600], fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.blue.withOpacity(0.05), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: Colors.blue[700]),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w600, letterSpacing: 0.2)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  Widget _buildPurchaseInvoiceInlineView(PurchaseInvoice invoice) {
"""

new_text = text[:start_idx] + replacement + text[end_idx + len("  Widget _buildInlinePurchaseHeader(PurchaseInvoice invoice) {"):]

with open("lib/modules/inventory/pages/stock_movements_page.dart", "w", encoding="utf-8") as f:
    f.write(new_text)

print("Updated perfectly")
