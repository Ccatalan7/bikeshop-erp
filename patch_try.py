import re

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'r', encoding='utf-8') as f:
    text = f.read()

# Replace inner try
to_replace = """    try {
        await _purchaseService.saveSupplier(supplier);"""
        
replacement = """      await _purchaseService.saveSupplier(supplier);"""

text = text.replace(to_replace, replacement)

with open('lib/modules/purchases/pages/supplier_form_page.dart', 'w', encoding='utf-8') as f:
    f.write(text)
