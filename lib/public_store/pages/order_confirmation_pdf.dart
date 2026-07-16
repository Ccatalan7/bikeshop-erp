import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';

import '../../modules/website/models/website_models.dart';
import '../../shared/utils/chilean_utils.dart';

Future<void> downloadOrderPdf(OnlineOrder order) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'VIÑABIKE',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Comprobante de Pedido',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      order.orderNumber,
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.blue700,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 20),

            // Customer Info
            pw.Text(
              'Datos del Cliente',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Nombre: ${order.customerName}'),
            pw.Text('Email: ${order.customerEmail}'),
            if (order.customerPhone != null)
              pw.Text('Teléfono: ${order.customerPhone}'),
            if (order.customerAddress != null)
              pw.Text('Dirección: ${order.customerAddress}'),
            pw.SizedBox(height: 20),

            // Products
            pw.Text(
              'Productos',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Producto',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Cant.',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Precio',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(
                        'Subtotal',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                // Product rows
                ...order.items.map(
                  (item) => pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(item.productName),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text('${item.quantity}'),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          ChileanUtils.formatCurrency(item.unitPrice),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(
                          ChileanUtils.formatCurrency(item.subtotal),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Totals
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.SizedBox(width: 100, child: pw.Text('Subtotal:')),
                      pw.SizedBox(
                        width: 100,
                        child: pw.Text(
                          ChileanUtils.formatCurrency(order.subtotal),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                  if (order.taxAmount > 0)
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.SizedBox(width: 100, child: pw.Text('IVA (19%):')),
                        pw.SizedBox(
                          width: 100,
                          child: pw.Text(
                            ChileanUtils.formatCurrency(order.taxAmount),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  if (order.shippingCost > 0)
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.SizedBox(width: 100, child: pw.Text('Envío:')),
                        pw.SizedBox(
                          width: 100,
                          child: pw.Text(
                            ChileanUtils.formatCurrency(order.shippingCost),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  pw.Divider(),
                  pw.Row(
                    mainAxisSize: pw.MainAxisSize.min,
                    children: [
                      pw.SizedBox(
                        width: 100,
                        child: pw.Text(
                          'TOTAL:',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ),
                      pw.SizedBox(
                        width: 100,
                        child: pw.Text(
                          ChileanUtils.formatCurrency(order.total),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 30),

            // Footer
            pw.Center(
              child: pw.Text(
                'Gracias por tu compra en Viñabike',
                style:
                    const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
              ),
            ),
            pw.Center(
              child: pw.Text(
                'vinabike.cl | +56 9 9835 7797',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.grey500),
              ),
            ),
          ],
        );
      },
    ),
  );

  final bytes = await pdf.save();
  final fileName = 'pedido_${order.orderNumber}.pdf';

  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar Pedido PDF',
      fileName: fileName,
      allowedExtensions: ['pdf'],
      type: FileType.custom,
    );

    if (outputFile != null) {
      final file = File(outputFile);
      await file.writeAsBytes(bytes);
    }
  } else {
    await Printing.sharePdf(
      bytes: bytes,
      filename: fileName,
    );
  }
}
