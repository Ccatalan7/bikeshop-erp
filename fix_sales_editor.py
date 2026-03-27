import re
file_path = 'lib/modules/sales/widgets/sales_invoice_editor.dart'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

cleaner_code = """
  String _cleanPdfText(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(RegExp(r'[^\\x20-\\x7E\\xA0-\\xFF\\r\\n\\t]'), ' ');
  }

"""

# just insert it before _buildEditorPdfItemRows or _buildPdfTotalRow
content = re.sub(
    r'(List<pw\.Widget> _buildEditorPdfItemRows)',
    lambda m: cleaner_code + m.group(1),
    content,
    count=1
)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)
print('Done')