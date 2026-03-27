import re

with open('lib/modules/purchases/services/purchase_service.dart', 'r') as f:
    content = f.read()

method = """  Future<List<PurchaseInvoice>> getInvoicesBySupplier(String supplierId) async {
    try {
      final List<dynamic> data = await _db.client
          .from('purchase_invoices')
          .select()
          .eq('tenant_id', _db.tenantId)
          .eq('supplier_id', supplierId)
          .order('issue_date', ascending: false);
      return data.map((row) => PurchaseInvoice.fromJson(row)).toList();
    } catch (e) {
      debugPrint('Error getting invoices for supplier: $e');
      return [];
    }
  }

"""

if 'getInvoicesBySupplier' not in content:
    content = re.sub(r'(  Future<PurchaseInvoice\?> getPurchaseInvoice\(String id\) async \{)', f'{method}\\1', content)

with open('lib/modules/purchases/services/purchase_service.dart', 'w') as f:
    f.write(content)
