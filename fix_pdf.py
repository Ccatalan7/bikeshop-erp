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

    def box_replacer(match):
        return """    return [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.only(top: 8, bottom: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              isMultiBike ? 'Bicicletas en servicio' : 'Bicicleta en servicio',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
            pw.SizedBox(height: 4),
            if (!isMultiBike)
              pw.Text(
                bikeNames.first,
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.black,
                ),
              )
            else
              ...bikeNames.map(
                (name) => pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 2, left: 4),
                  child: pw.Text(
                    '• ${name}',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.black,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
    ];"""

    content = re.sub(
        r'return \[\s*pw\.Container\([\s\S]*?pw\.SizedBox\(height: 12\),\s*\];',
        box_replacer,
        content
    )

    content = content.replace('PdfColors.blue50', 'PdfColors.grey100')
    content = content.replace('PdfColors.blue800', 'PdfColors.grey800')
    content = content.replace("'🚲  $bikeName'", "bikeName")

    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

print('Done')