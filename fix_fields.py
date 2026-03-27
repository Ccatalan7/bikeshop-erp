import re

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r') as f:
    content = f.read()

content = content.replace("inv.issueDate", "inv.date")
content = content.replace("inv.invoiceNumber ?? inv.folio ?? \"S/N\"", "inv.invoiceNumber ?? \"S/N\"")
content = content.replace("inv.status == 'paid'", "inv.status == PurchaseInvoiceStatus.paid")
content = content.replace("import '../../../shared/services/image_service.dart';", "")

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w') as f:
    f.write(content)
