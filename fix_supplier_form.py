import re

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r') as f:
    content = f.read()

content = content.replace(
    "import '../../../shared/models/purchase_invoice.dart';",
    "import '../models/purchase_invoice.dart';"
)

content = content.replace("withOpacity", "withValues(alpha: ")
content = content.replace(".withValues(alpha: (0.1)", ".withValues(alpha: 0.1)")

# For the 'total' and 'InvoiceStatus' errors:
# Let's check how 'total' property is accessed in purchase_invoice:
content = content.replace("inv.calculatedStatus == InvoiceStatus.paid", "inv.status == 'paid'")

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w') as f:
    f.write(content)
