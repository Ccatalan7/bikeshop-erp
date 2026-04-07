import os

with open('lib/modules/inventory/pages/stock_movements_page.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("ChileanUtils.ChileanUtils.", "ChileanUtils.")

with open('lib/modules/inventory/pages/stock_movements_page.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("fixed duplicate")
