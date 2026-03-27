import re

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r') as f:
    content = f.read()

content = content.replace("inv.invoiceNumber ?? \"S/N\"", "inv.invoiceNumber.isNotEmpty ? inv.invoiceNumber : \"S/N\"")

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w') as f:
    f.write(content)
