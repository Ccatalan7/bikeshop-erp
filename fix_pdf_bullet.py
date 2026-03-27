import os
import re

files_to_fix = [
    'lib/modules/sales/widgets/sales_invoice_editor.dart',
    'lib/modules/sales/pages/invoice_list_page.dart',
    'lib/modules/sales/pages/invoice_form_page.dart',
    'lib/modules/sales/pages/invoice_detail_page.dart',
]

for file_path in files_to_fix:
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Replace the text bullet with a drawn circle
    old_bullet = """pw.Text(
                    '• ${name}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.black,
                    ),
                  )"""
                  
    new_bullet = """pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: 3,
                        height: 3,
                        margin: const pw.EdgeInsets.only(right: 6),
                        decoration: const pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          color: PdfColors.black,
                        ),
                      ),
                      pw.Text(
                        name,
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.black,
                        ),
                      ),
                    ],
                  )"""
    
    content = content.replace(old_bullet, new_bullet)

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

print('Done')