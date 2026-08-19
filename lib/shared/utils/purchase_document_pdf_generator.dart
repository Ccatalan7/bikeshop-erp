import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../modules/purchases/models/purchase_invoice.dart';
import '../../modules/settings/services/appearance_service.dart';
import '../models/tax_treatment.dart';
import '../services/inventory_service.dart';
import 'chilean_utils.dart';

/// Single owner of the purchase document PDF.
///
/// The same sheet the operator downloads from «Documentos de compra» is what
/// the supplier receives in the chat, so the layout lives here instead of
/// inside a page's state.
class PurchaseDocumentPdfGenerator {
  const PurchaseDocumentPdfGenerator._();

  static Uint8List? _cachedLogoBytes;
  static String? _cachedLogoUrl;

  static String fileNameFor(String invoiceNumber) =>
      'documento_compra_$invoiceNumber.pdf';

  static Future<Uint8List> generateBytes(
    PurchaseInvoice invoice, {
    required AppearanceService appearanceService,
    required InventoryService inventoryService,
  }) async {
    final document = await generate(
      invoice,
      appearanceService: appearanceService,
      inventoryService: inventoryService,
    );
    return document.save();
  }

  static Future<pw.Document> generate(
    PurchaseInvoice invoice, {
    required AppearanceService appearanceService,
    required InventoryService inventoryService,
  }) async {
    final pdf = pw.Document();

    // Try to load company logo (use cache if available)
    pw.ImageProvider? logoImage;
    try {
      final logoUrl = appearanceService.companyLogoUrl;
      if (logoUrl != null && logoUrl.isNotEmpty) {
        // Check if we already have cached bytes for this URL
        if (_cachedLogoBytes != null && _cachedLogoUrl == logoUrl) {
          logoImage = pw.MemoryImage(_cachedLogoBytes!);
        } else {
          // Fetch and cache
          final response = await http.get(Uri.parse(logoUrl));
          if (response.statusCode == 200) {
            _cachedLogoBytes = response.bodyBytes;
            _cachedLogoUrl = logoUrl;
            logoImage = pw.MemoryImage(_cachedLogoBytes!);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading logo for PDF: $e');
    }

    final products = await inventoryService.getProductsByIds(
      invoice.items.map((item) => item.productId),
    );
    final productsById = {
      for (final product in products) product.id: product,
    };

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header - much more compact
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Company logo or text fallback
                if (logoImage != null)
                  pw.Image(logoImage,
                      width: 120, height: 40, fit: pw.BoxFit.contain)
                else
                  pw.Text(
                    'VIÑABIKE',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      '# ${invoice.invoiceNumber}',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Saldo adeudado',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      ChileanUtils.formatCurrency(
                          invoice.total - invoice.paidAmount),
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 16),

            // Company info - smaller
            pw.Text('Viñabike',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.black)),
            pw.Text('Valparaíso',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.black)),
            pw.Text('Chile',
                style:
                    const pw.TextStyle(fontSize: 10, color: PdfColors.black)),

            pw.SizedBox(height: 16),

            // Supplier and date info - more compact
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Proveedor',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      invoice.supplierName ?? 'Sin registro',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue700,
                      ),
                    ),
                    if (invoice.supplierRut != null)
                      pw.Text(
                        invoice.supplierRut!,
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Fecha del documento:',
                      style: const pw.TextStyle(
                        fontSize: 9,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      ChileanUtils.formatDate(invoice.date),
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.black,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            pw.SizedBox(height: 16),

            // Items table - much tighter
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.grey300,
                width: 0.3, // Ultra thin borders
              ),
              columnWidths: {
                0: const pw.FixedColumnWidth(35),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FixedColumnWidth(60),
                3: const pw.FixedColumnWidth(70),
                4: const pw.FixedColumnWidth(70),
              },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey800),
                  children: [
                    _buildPdfTableCell('#', isHeader: true),
                    _buildPdfTableCell('Artículo & Descripción',
                        isHeader: true),
                    _buildPdfTableCell('Cant.', isHeader: true),
                    _buildPdfTableCell('Tarifa', isHeader: true),
                    _buildPdfTableCell('Importe', isHeader: true),
                  ],
                ),
                // Data rows
                ...invoice.items.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = entry.value;

                  // Lookup clean product name from cache if available (mirrors form view logic)
                  final product = productsById[item.productId];
                  final displayName = _cleanPdfText(
                      product?.name ?? item.productName ?? 'Sin nombre');
                  final displaySku =
                      _cleanPdfText(product?.sku ?? item.productSku ?? '');

                  final hasDescription =
                      item.description != null && item.description!.isNotEmpty;
                  final hasSku = displaySku.isNotEmpty;

                  return pw.TableRow(
                    children: [
                      _buildPdfTableCell('${index + 1}'),
                      // Product name + description (Zoho style)
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 5),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              displayName,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                            if (hasDescription) ...[
                              pw.SizedBox(height: 3),
                              pw.Text(
                                _cleanPdfText(item.description!),
                                style: const pw.TextStyle(
                                  fontSize: 9,
                                  color: PdfColors.grey700,
                                ),
                              ),
                            ] else if (hasSku) ...[
                              pw.SizedBox(height: 3),
                              pw.Text(
                                'SKU: $displaySku',
                                style: const pw.TextStyle(
                                  fontSize: 9,
                                  color: PdfColors.grey700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _buildPdfTableCell(item.quantity.toStringAsFixed(2)),
                      _buildPdfTableCell(
                          ChileanUtils.formatCurrency(item.unitCost)),
                      _buildPdfTableCell(
                          ChileanUtils.formatCurrency(item.netAmountClamped)),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 16),

            // Totals - tighter
            pw.Row(
              children: [
                pw.Spacer(),
                pw.SizedBox(
                  width: 250,
                  child: pw.Column(
                    children: [
                      // Subtotal (the actual stored subtotal is always the net amount for purchases)
                      _buildPdfTotalRow(
                          invoice.taxTreatment == TaxTreatment.taxIncluded
                              ? 'Subtotal (Neto)'
                              : 'Subtotal',
                          invoice.subtotal),
                      if (invoice.discountAmount > 0)
                        _buildPdfTotalRow('Descuento', -invoice.discountAmount),
                      if (invoice.ivaAmount > 0)
                        _buildPdfTotalRow('IVA (19%)', invoice.ivaAmount),
                      pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                      _buildPdfTotalRow('Total', invoice.total, isTotal: true),
                      if (invoice.paidAmount > 0) ...[
                        pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                        _buildPdfTotalRow(
                            'Pago realizado', -invoice.paidAmount),
                      ],
                      pw.Divider(thickness: 1, color: PdfColors.grey800),
                      _buildPdfTotalRow(
                          'Saldo adeudado', invoice.total - invoice.paidAmount,
                          isTotal: true),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return pdf;
  }

  static String _cleanPdfText(String text) {
    if (text.isEmpty) return text;
    return text.replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF\r\n\t]'), ' ');
  }

  static pw.Widget _buildPdfTableCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: isHeader ? PdfColors.white : PdfColors.black,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: isHeader ? 9 : 10,
        ),
      ),
    );
  }

  static pw.Widget _buildPdfTotalRow(String label, double amount,
      {bool isTotal = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: isTotal ? 12 : 11,
              color: PdfColors.black,
            ),
          ),
          pw.Text(
            ChileanUtils.formatCurrency(amount.abs()),
            style: pw.TextStyle(
              fontWeight: isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: isTotal ? 12 : 11,
              color: PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }
}
