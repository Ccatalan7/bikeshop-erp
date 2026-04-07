import re

with open('lib/modules/inventory/pages/stock_movements_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

start_str = "Widget _buildPurchaseInvoiceInlineView(PurchaseInvoice invoice) {"
end_str = "Widget _buildInlinePurchaseSummary(PurchaseInvoice invoice) {"

if start_str in content and end_str in content:
    start_idx = content.find(start_str) - 2 # Include spacing
    end_idx = content.find(end_str) - 2
    
    new_purchase_view = """  Widget _buildPurchaseInvoiceInlineView(PurchaseInvoice invoice) {
    final inventoryService = context.watch<InventoryService>();

    final statusColor = _purchaseStatusColor(invoice.status);
    final statusText = invoice.status.displayName;

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
                      invoice.invoiceNumber?.isNotEmpty == true
                          ? 'Factura de Compra '
                          : 'Factura de Compra',
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      invoice.supplierName ?? 'Proveedor Asociado',
                      style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        invoice.status == PurchaseInvoiceStatus.paid
                            ? Icons.check_circle
                            : Icons.info_outline,
                        size: 16,
                        color: statusColor),
                    const SizedBox(width: 6),
                    Text(
                      statusText.toUpperCase(),
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // SUMMARY METRICS ROW
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildMetricCol(
                      'FECHA', DateFormat('dd/MM/yyyy').format(invoice.date)),
                ),
                Expanded(
                  child: _buildMetricCol(
                      'IMPUESTO',
                      invoice.taxTreatment == TaxTreatment.taxIncluded
                          ? 'IVA Incluido'
                          : 'Sin IVA'),
                ),
                Expanded(
                  child: _buildMetricCol(
                    'TOTAL',
                    formatCurrency(invoice.total),
                    Colors.black87,
                    20,
                    FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // ITEMS LIST
          Text(
            'Productos ingresados',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
                letterSpacing: -0.5),
          ),
          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              children: [
                // Table Header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(11)),
                    border: Border(
                        bottom: BorderSide(color: Colors.grey[300]!)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 48 + 16), // space for image
                      Expanded(
                        flex: 3,
                        child: Text('PRODUCTO',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                                letterSpacing: 0.5)),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text('CANT.',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                                letterSpacing: 0.5)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('COSTO U.',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                                letterSpacing: 0.5)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('TOTAL',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                                letterSpacing: 0.5)),
                      ),
                    ],
                  ),
                ),

                // Items List
                ...invoice.items.map((item) {
                  final productList = inventoryService.products.where((p) => p.id == item.productId).toList();
                  final product = productList.isNotEmpty ? productList.first : null;
                  
                  final imageUrl = product?.imageUrls?.isNotEmpty == true
                      ? product!.imageUrls!.first
                      : (product?.imageUrl);
                  final isLast = invoice.items.last == item;

                  final subtotal = item.quantity * item.unitCost;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      border: !isLast
                          ? Border(
                              bottom:
                                  BorderSide(color: Colors.grey[200]!))
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Image Thumbnail
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[200]!),
                            image: imageUrl != null && imageUrl.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(imageUrl),
                                    fit: BoxFit.cover)
                                : null,
                          ),
                          child: imageUrl == null || imageUrl.isEmpty
                              ? Icon(
                                  Icons.inventory_2_outlined,
                                  color: Colors.grey[400],
                                  size: 20,
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName ?? 'Producto sin nombre',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                              ),
                              if (item.productSku != null && item.productSku!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    item.productSku!,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                        fontFamily: 'monospace'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            item.quantity.toStringAsFixed(0),
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            formatCurrency(item.unitCost),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                color: Colors.grey[700], fontSize: 13),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            formatCurrency(subtotal),
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ), // Ensure child Column is closed here
    ); // Ensure SingleChildScrollView is closed here
  }
"""
    
    new_content = content[:start_idx] + new_purchase_view + content[end_idx:]
    with open('lib/modules/inventory/pages/stock_movements_page.dart', 'w', encoding='utf-8') as f:
        f.write(new_content)
    print("Replaced!")
else:
    print("Could not find blocks.")
