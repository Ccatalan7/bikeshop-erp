import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../../modules/sales/models/sales_models.dart';
import '../../modules/settings/services/appearance_service.dart';
import '../../shared/services/database_service.dart';
import 'chilean_utils.dart';

class InvoicePdfGenerator {
  static Uint8List? _cachedLogoBytes;
  static String? _cachedLogoUrl;

  static Future<Map<String, String>> resolveBikeNames(
    BuildContext context,
    Invoice invoice,
  ) async {
    final Map<String, String> resolvedBikeNames = {};
    try {
      final db = context.read<DatabaseService>();

      // 1. Single-bike invoice: fetch via invoice.bikeId
      final bikeId = invoice.bikeId;
      if (bikeId != null && bikeId.isNotEmpty) {
        final bikeData = await db.supabase
            .from('bikes')
            .select('brand, model, year')
            .eq('id', bikeId as Object)
            .maybeSingle();
        if (bikeData != null) {
          final parts = <String>[
            if ((bikeData['brand'] as String?)?.isNotEmpty == true)
              bikeData['brand'] as String,
            if ((bikeData['model'] as String?)?.isNotEmpty == true)
              bikeData['model'] as String,
            if (bikeData['year'] != null) bikeData['year'].toString(),
          ];
          if (parts.isNotEmpty) resolvedBikeNames['single'] = parts.join(' ');
        }
      }

      // 2. Multi-bike items via jobBikeId
      final jobBikeIds = invoice.items
          .where((i) => i.jobBikeId != null && i.jobBikeId!.isNotEmpty)
          .map((i) => i.jobBikeId!)
          .toSet();

      for (final jobBikeId in jobBikeIds) {
        final existingName =
            invoice.items.firstWhere((i) => i.jobBikeId == jobBikeId).bikeName;
        if (existingName != null && existingName.isNotEmpty) {
          resolvedBikeNames[jobBikeId] = existingName;
          continue;
        }
        final jobBikeData = await db.supabase
            .from('mechanic_job_bikes')
            .select('bikes(brand, model, year)')
            .eq('id', jobBikeId as Object)
            .maybeSingle();
        if (jobBikeData != null) {
          final bikeMap = jobBikeData['bikes'] as Map<String, dynamic>?;
          if (bikeMap != null) {
            final parts = <String>[
              if ((bikeMap['brand'] as String?)?.isNotEmpty == true)
                bikeMap['brand'] as String,
              if ((bikeMap['model'] as String?)?.isNotEmpty == true)
                bikeMap['model'] as String,
              if (bikeMap['year'] != null) bikeMap['year'].toString(),
            ];
            if (parts.isNotEmpty) {
              resolvedBikeNames[jobBikeId] = parts.join(' ');
            }
          }
        }
      }
    } catch (e) {
      debugPrint(
          'Could not resolve bike names for PDF: $e'); // ignore: avoid_print
    }
    return resolvedBikeNames;
  }

  static Future<pw.Document> generateInvoicePDF(
    BuildContext context,
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) async {
    final pdf = pw.Document();

    // Try to load company logo (use cache if available)
    pw.ImageProvider? logoImage;
    try {
      final appearanceService = context.read<AppearanceService>();
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
                      color: PdfColors.grey800,
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
                      ChileanUtils.formatCurrency(invoice.balance),
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

            // Customer and date info - more compact
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Facturar a',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      invoice.customerName ?? 'Sin registro',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue700,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'Fecha de la factura :',
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

            // ── Bicycle info banner ──────────────────────────────────
            ..._buildFormPdfBikeBanner(invoice, resolvedBikeNames),

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
                    _buildPdfTableCell('Cantidad', isHeader: true),
                  ],
                ),
                // Data rows grouped by bike
                ..._buildFormPdfItemRows(invoice, resolvedBikeNames),
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
                      _buildPdfTotalRow('Subtotal', invoice.subtotal),
                      pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                      _buildPdfTotalRow('Total', invoice.total, isTotal: true),
                      if (invoice.paidAmount > 0) ...[
                        pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                        _buildPdfTotalRow(
                            'Pago realizado', -invoice.paidAmount),
                      ],
                      pw.Divider(thickness: 1, color: PdfColors.grey800),
                      _buildPdfTotalRow('Saldo adeudado', invoice.balance,
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

  static List<pw.Widget> _buildFormPdfBikeBanner(
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) {
    final multiBikeNames = <String>[];
    for (final item in invoice.items) {
      final jbId = item.jobBikeId;
      if (jbId != null && jbId.isNotEmpty) {
        final name = resolvedBikeNames[jbId] ?? item.bikeName ?? '';
        if (name.isNotEmpty && !multiBikeNames.contains(name)) {
          multiBikeNames.add(name);
        }
      }
    }

    final singleBikeName = resolvedBikeNames['single'];
    final List<String> bikeNames;
    if (multiBikeNames.isNotEmpty) {
      bikeNames = multiBikeNames;
    } else if (singleBikeName != null && singleBikeName.isNotEmpty) {
      bikeNames = [singleBikeName];
    } else {
      return [];
    }

    final isMultiBike = bikeNames.length > 1;
    return [
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
                  child: pw.Row(
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
                  ),
                ),
              ),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
    ];
  }

  static List<pw.TableRow> _buildFormPdfItemRows(
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) {
    final rows = <pw.TableRow>[];
    String? lastBikeName;
    int itemIndex = 0;

    final bikeNamesForItems = <String>{};
    for (final item in invoice.items) {
      final jbId = item.jobBikeId;
      if (jbId != null && jbId.isNotEmpty) {
        final name = resolvedBikeNames[jbId] ?? item.bikeName ?? '';
        if (name.isNotEmpty) {
          bikeNamesForItems.add(name);
        }
      }
    }

    final hasMultiBike = bikeNamesForItems.length > 1;

    for (final item in invoice.items) {
      if (hasMultiBike) {
        final jbId = item.jobBikeId ?? '';
        final bikeName = jbId.isNotEmpty
            ? (resolvedBikeNames[jbId] ?? item.bikeName ?? '')
            : (item.bikeName ?? '');
        if (bikeName.isNotEmpty && bikeName != lastBikeName) {
          lastBikeName = bikeName;
          rows.add(
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: pw.SizedBox(),
                ),
                pw.Padding(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: pw.Text(
                    bikeName,
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800,
                    ),
                  ),
                ),
                pw.SizedBox(),
                pw.SizedBox(),
                pw.SizedBox(),
              ],
            ),
          );
        }
      }

      itemIndex++;
      final hasDescription =
          item.description != null && item.description!.isNotEmpty;
      rows.add(
        pw.TableRow(
          children: [
            _buildPdfTableCell('$itemIndex'),
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _cleanPdfText(item.productName ?? 'Sin nombre'),
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
                  ],
                ],
              ),
            ),
            _buildPdfTableCell(item.quantity.toStringAsFixed(2)),
            _buildPdfTableCell(ChileanUtils.formatCurrency(item.unitPrice)),
            _buildPdfTableCell(ChileanUtils.formatCurrency(item.lineTotal)),
          ],
        ),
      );
    }

    return rows;
  }

  static String _cleanPdfText(String text) {
    if (text.isEmpty) {
      return text;
    }
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
