import os

with open('lib/modules/inventory/pages/stock_movements_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

metric_col_str = '''  Widget _buildMetricCol(String label, String value,
      [Color? valueColor, double fontSize = 16, FontWeight fontWeight = FontWeight.bold]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey[500],
              letterSpacing: 1),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: valueColor ?? Colors.black87),
        ),
      ],
    );
  }
'''

if "Widget _buildPurchaseInvoiceInlineView" in content and "Widget _buildMetricCol" not in content:
    content = content.replace("Widget _buildPurchaseInvoiceInlineView(PurchaseInvoice invoice) {", metric_col_str + "\n  Widget _buildPurchaseInvoiceInlineView(PurchaseInvoice invoice) {")

content = content.replace("formatCurrency(", "ChileanUtils.formatCurrency(")

with open('lib/modules/inventory/pages/stock_movements_page.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("done")
