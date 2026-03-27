import os
import re

files_to_fix = [
    r'lib\modules\purchases\pages\purchase_invoice_list_page.dart',
    r'lib\modules\sales\pages\invoice_detail_page.dart',
    r'lib\modules\sales\pages\invoice_form_page.dart',
    r'lib\modules\sales\pages\invoice_list_page.dart',
    r'lib\modules\bikeshop\widgets\smart_job_details_editor.dart',
    r'lib\modules\sales\widgets\sales_invoice_editor.dart'
]

cleaner_code = """
  String _cleanPdfText(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(RegExp(r'[^\\x20-\\x7E\\xA0-\\xFF\\r\\n\\t]'), ' ');
  }

"""

for file_path in files_to_fix:
    if not os.path.exists(file_path):
        print(f"Not found: {file_path}")
        continue
        
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Add the cleaner function if not present
    if '_cleanPdfText' not in content:
        # insert it before the first widget build method or _buildPdfTableCell
        content_new = re.sub(
            r'(pw\.Widget _buildPdfTableCell)',
            lambda m: cleaner_code + m.group(1),
            content,
            count=1
        )
        if content == content_new:
            # try _buildTableCell
            content_new = re.sub(
                r'(pw\.Widget _buildTableCell)',
                lambda m: cleaner_code + m.group(1),
                content,
                count=1
            )
        if content == content_new:
             # try _buildNotesSection or just before _buildFormPdfItemRows
             content_new = re.sub(
                r'(pw\.Widget _buildNotesSection)',
                lambda m: cleaner_code + m.group(1),
                content,
                count=1
            )
             
        content = content_new

    # Safely replace name/desc calls:

    # 1. Purchases specific
    content = re.sub(
        r"final displayName =\s*product\?\.name \?\? item\.productName \?\? 'Sin nombre';",
        "final displayName = _cleanPdfText(product?.name ?? item.productName ?? 'Sin nombre');",
        content
    )

    content = re.sub(
        r"final displaySku = product\?\.sku \?\? item\.productSku;",
        "final displaySku = _cleanPdfText(product?.sku ?? item.productSku ?? '');",
        content
    )

    # 2. Description in items mapping
    content = re.sub(
        r"pw\.Text\(\s*item\.description!,\s*style",
        "pw.Text(_cleanPdfText(item.description!), style",
        content
    )
    
    # 3. item.productName in sales
    content = re.sub(
        r"pw\.Text\(item\.productName \?\? 'Sin nombre',\s*style",
        "pw.Text(_cleanPdfText(item.productName ?? 'Sin nombre'), style",
        content
    )

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

print('Done')
