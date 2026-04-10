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

          if (parts.isNotEmpty) {
            resolvedBikeNames['single'] = parts.join(' ');
          }
        }
      }

      final jobBikeIds = invoice.items
          .where((item) => item.jobBikeId != null && item.jobBikeId!.isNotEmpty)
          .map((item) => item.jobBikeId!)
          .toSet();

      for (final jobBikeId in jobBikeIds) {
        final existingName = invoice.items
            .firstWhere((item) => item.jobBikeId == jobBikeId)
            .bikeName;
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
      debugPrint('Could not resolve bike names for PDF: $e');
    }

    return resolvedBikeNames;
  }

  static Future<pw.Document> generateInvoicePDF(
    BuildContext context,
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) async {
    final pdf = pw.Document();
    final logoImage = await _loadLogoImage(context);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(34, 32, 34, 28),
        maxPages: 200,
        footer: (pageContext) => _buildFooter(pageContext),
        build: (pageContext) => [
          _buildHeader(invoice, logoImage),
          pw.SizedBox(height: 14),
          _buildPartyAndDateBlock(invoice),
          ..._buildBikeBanner(invoice, resolvedBikeNames),
          _buildItemsTable(invoice, resolvedBikeNames),
          pw.SizedBox(height: 18),
          _buildTotals(invoice),
        ],
      ),
    );

    return pdf;
  }

  static Future<pw.ImageProvider?> _loadLogoImage(BuildContext context) async {
    try {
      final appearanceService = context.read<AppearanceService>();
      final logoUrl = appearanceService.companyLogoUrl;
      if (logoUrl == null || logoUrl.isEmpty) {
        return null;
      }

      if (_cachedLogoBytes != null && _cachedLogoUrl == logoUrl) {
        return pw.MemoryImage(_cachedLogoBytes!);
      }

      final response = await http.get(Uri.parse(logoUrl));
      if (response.statusCode != 200) {
        return null;
      }

      _cachedLogoBytes = response.bodyBytes;
      _cachedLogoUrl = logoUrl;
      return pw.MemoryImage(_cachedLogoBytes!);
    } catch (e) {
      debugPrint('Error loading logo for PDF: $e');
      return null;
    }
  }

  static pw.Widget _buildHeader(
    Invoice invoice,
    pw.ImageProvider? logoImage,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logoImage != null)
              pw.Image(
                logoImage,
                width: 128,
                height: 42,
                fit: pw.BoxFit.contain,
              )
            else
              pw.Text(
                'VINABIKE',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
            pw.SizedBox(height: 12),
            pw.Text(
              'Viñabike',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.black),
            ),
            pw.Text(
              'Valparaíso',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.black),
            ),
            pw.Text(
              'Chile',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.black),
            ),
          ],
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
    );
  }

  static pw.Widget _buildPartyAndDateBlock(Invoice invoice) {
    return pw.Row(
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
            pw.SizedBox(height: 4),
            pw.Text(
              invoice.customerName ?? 'Sin registro',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue700,
              ),
            ),
            if (invoice.customerRut != null && invoice.customerRut!.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  invoice.customerRut!,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            _buildMetaLine(
              'Fecha de la factura',
              ChileanUtils.formatDate(invoice.date),
            ),
            if (invoice.dueDate != null)
              _buildMetaLine(
                'Vencimiento',
                ChileanUtils.formatDate(invoice.dueDate!),
              ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildMetaLine(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.Text(
            '$label: ',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _buildBikeBanner(
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) {
    final bikeNames = _collectBikeNames(invoice, resolvedBikeNames);
    if (bikeNames.isEmpty) {
      return const [];
    }

    final isMultiBike = bikeNames.length > 1;
    return [
      pw.SizedBox(height: 14),
      pw.Column(
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
    ];
  }

  static pw.Widget _buildItemsTable(
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) {
    final groups = _groupItemsByBike(invoice, resolvedBikeNames);
    final showBikeHeaders = groups.length > 1;
    var itemIndex = 0;

    final rows = <pw.TableRow>[
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: PdfColors.grey800),
        children: [
          _buildPdfTableCell(
            '#',
            isHeader: true,
            alignment: pw.TextAlign.center,
          ),
          _buildPdfTableCell('Artículo & Descripción', isHeader: true),
          _buildPdfTableCell(
            'Cant.',
            isHeader: true,
            alignment: pw.TextAlign.center,
          ),
          _buildPdfTableCell(
            'Tarifa',
            isHeader: true,
            alignment: pw.TextAlign.right,
          ),
          _buildPdfTableCell(
            'Total',
            isHeader: true,
            alignment: pw.TextAlign.right,
          ),
        ],
      ),
    ];

    for (final group in groups) {
      if (showBikeHeaders) {
        rows.add(
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
            children: [
              _buildEmptyCell(),
              _buildPdfTableCell(
                group.label,
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
              _buildEmptyCell(),
              _buildEmptyCell(),
              _buildEmptyCell(),
            ],
          ),
        );
      }

      for (final item in group.items) {
        itemIndex += 1;
        rows.add(
          pw.TableRow(
            verticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              _buildPdfTableCell(
                '$itemIndex',
                alignment: pw.TextAlign.center,
              ),
              _buildDescriptionCell(item),
              _buildPdfTableCell(
                _formatQuantity(item.quantity),
                alignment: pw.TextAlign.center,
              ),
              _buildPdfTableCell(
                ChileanUtils.formatCurrency(item.unitPrice),
                alignment: pw.TextAlign.right,
              ),
              _buildPdfTableCell(
                ChileanUtils.formatCurrency(item.lineTotal),
                alignment: pw.TextAlign.right,
              ),
            ],
          ),
        );
      }
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14),
      child: pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.35),
        columnWidths: {
          0: const pw.FixedColumnWidth(24),
          1: const pw.FlexColumnWidth(4.8),
          2: const pw.FixedColumnWidth(48),
          3: const pw.FixedColumnWidth(76),
          4: const pw.FixedColumnWidth(76),
        },
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
        children: rows,
      ),
    );
  }

  static pw.Widget _buildDescriptionCell(InvoiceItem item) {
    final hasDescription =
        item.description != null && item.description!.trim().isNotEmpty;

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _cleanPdfText(item.productName ?? item.productSku ?? 'Producto'),
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.black,
            ),
          ),
          if (hasDescription)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                _cleanPdfText(item.description!.trim()),
                style: const pw.TextStyle(
                  fontSize: 8.2,
                  color: PdfColors.grey700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildTotals(Invoice invoice) {
    return pw.Row(
      children: [
        pw.Spacer(),
        pw.SizedBox(
          width: 250,
          child: pw.Column(
            children: [
              _buildPdfTotalRow('Subtotal', invoice.subtotal),
              if (invoice.ivaAmount > 0) ...[
                pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                _buildPdfTotalRow('IVA (19%)', invoice.ivaAmount),
              ],
              pw.Divider(thickness: 0.3, color: PdfColors.grey400),
              _buildPdfTotalRow('Total', invoice.total, isTotal: true),
              if (invoice.paidAmount > 0) ...[
                pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                _buildPdfTotalRow('Pago realizado', -invoice.paidAmount),
              ],
              pw.Divider(thickness: 1, color: PdfColors.grey800),
              _buildPdfTotalRow(
                'Saldo adeudado',
                invoice.balance,
                isTotal: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFooter(pw.Context context) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Gracias por su preferencia',
            style: pw.TextStyle(
              fontSize: 8,
              fontStyle: pw.FontStyle.italic,
              color: PdfColors.grey700,
            ),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  static List<String> _collectBikeNames(
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) {
    final bikeNames = <String>[];
    final seen = <String>{};

    for (final item in invoice.items) {
      final bikeName = _resolveBikeName(invoice, item, resolvedBikeNames);
      if (bikeName == null || bikeName.isEmpty || seen.contains(bikeName)) {
        continue;
      }

      seen.add(bikeName);
      bikeNames.add(bikeName);
    }

    final singleBikeName = resolvedBikeNames['single'];
    if (bikeNames.isEmpty &&
        singleBikeName != null &&
        singleBikeName.trim().isNotEmpty) {
      bikeNames.add(singleBikeName.trim());
    }

    return bikeNames;
  }

  static List<_PdfInvoiceGroup> _groupItemsByBike(
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) {
    final groups = <_PdfInvoiceGroup>[];
    final byKey = <String, _PdfInvoiceGroup>{};

    for (final item in invoice.items) {
      final bikeName = _resolveBikeName(invoice, item, resolvedBikeNames);
      final normalizedName = bikeName?.trim();
      final label = normalizedName == null || normalizedName.isEmpty
          ? 'Sin bicicleta asociada'
          : normalizedName;
      final key = normalizedName == null || normalizedName.isEmpty
          ? '__unassigned__'
          : normalizedName;

      final group = byKey.putIfAbsent(key, () {
        final createdGroup = _PdfInvoiceGroup(label: label);
        groups.add(createdGroup);
        return createdGroup;
      });

      group.items.add(item);
    }

    return groups;
  }

  static String? _resolveBikeName(
    Invoice invoice,
    InvoiceItem item,
    Map<String, String> resolvedBikeNames,
  ) {
    final jobBikeId = item.jobBikeId;
    if (jobBikeId != null && jobBikeId.isNotEmpty) {
      final resolved = resolvedBikeNames[jobBikeId]?.trim();
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }

    final itemBikeName = item.bikeName?.trim();
    if (itemBikeName != null && itemBikeName.isNotEmpty) {
      return itemBikeName;
    }

    if (invoice.bikeId != null && invoice.bikeId!.isNotEmpty) {
      final singleBikeName = resolvedBikeNames['single']?.trim();
      if (singleBikeName != null && singleBikeName.isNotEmpty) {
        return singleBikeName;
      }
    }

    return null;
  }

  static String _cleanPdfText(String text) {
    if (text.isEmpty) {
      return text;
    }

    return text.replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF\r\n\t]'), ' ');
  }

  static String _formatQuantity(double quantity) {
    if (quantity.truncateToDouble() == quantity) {
      return quantity.toStringAsFixed(0);
    }

    return quantity.toStringAsFixed(2);
  }

  static pw.Widget _buildPdfTableCell(
    String text, {
    bool isHeader = false,
    pw.TextAlign alignment = pw.TextAlign.left,
    double? fontSize,
    pw.FontWeight? fontWeight,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: alignment,
        style: pw.TextStyle(
          color: isHeader ? PdfColors.white : PdfColors.black,
          fontWeight: fontWeight ??
              (isHeader ? pw.FontWeight.bold : pw.FontWeight.normal),
          fontSize: fontSize ?? (isHeader ? 9 : 9.2),
        ),
      ),
    );
  }

  static pw.Widget _buildEmptyCell() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.SizedBox(),
    );
  }

  static pw.Widget _buildPdfTotalRow(
    String label,
    double amount, {
    bool isTotal = false,
  }) {
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

class _PdfInvoiceGroup {
  _PdfInvoiceGroup({required this.label});

  final String label;
  final List<InvoiceItem> items = <InvoiceItem>[];
}
