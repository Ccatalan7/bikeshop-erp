import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../../modules/sales/models/sales_models.dart';
import '../../modules/settings/services/appearance_service.dart';
import '../../shared/services/database_service.dart';
import 'chilean_utils.dart';

enum InvoicePdfExportMode {
  invoiceOnly,
  invoiceWithDiagnosis,
}

/// The customer-facing commercial document rendered by the shared PDF layout.
///
/// Keep this separate from [InvoicePdfExportMode]: the latter controls whether
/// an invoice includes its diagnosis attachment, while this enum controls the
/// commercial meaning and wording of the document itself.
enum InvoicePdfDocumentKind {
  invoice,
  quotation,
  serviceBudget,
}

extension InvoicePdfDocumentKindX on InvoicePdfDocumentKind {
  bool get isProposal => this != InvoicePdfDocumentKind.invoice;

  String get label {
    switch (this) {
      case InvoicePdfDocumentKind.invoice:
        return 'Factura';
      case InvoicePdfDocumentKind.quotation:
        return 'Cotización';
      case InvoicePdfDocumentKind.serviceBudget:
        return 'Presupuesto';
    }
  }

  String get labelLower => label.toLowerCase();

  String fileNameFor(String documentNumber) {
    switch (this) {
      case InvoicePdfDocumentKind.invoice:
        return 'factura_$documentNumber.pdf';
      case InvoicePdfDocumentKind.quotation:
        return 'cotizacion_$documentNumber.pdf';
      case InvoicePdfDocumentKind.serviceBudget:
        return 'presupuesto_$documentNumber.pdf';
    }
  }

  String documentNameFor(String documentNumber) {
    switch (this) {
      case InvoicePdfDocumentKind.invoice:
        return 'factura_$documentNumber';
      case InvoicePdfDocumentKind.quotation:
        return 'cotizacion_$documentNumber';
      case InvoicePdfDocumentKind.serviceBudget:
        return 'presupuesto_$documentNumber';
    }
  }
}

extension InvoicePdfExportModeX on InvoicePdfExportMode {
  String get label {
    switch (this) {
      case InvoicePdfExportMode.invoiceOnly:
        return 'Factura';
      case InvoicePdfExportMode.invoiceWithDiagnosis:
        return 'Factura + Diagnóstico';
    }
  }

  String fileNameFor(String invoiceNumber) {
    switch (this) {
      case InvoicePdfExportMode.invoiceOnly:
        return 'factura_$invoiceNumber.pdf';
      case InvoicePdfExportMode.invoiceWithDiagnosis:
        return 'factura_${invoiceNumber}_con_diagnostico.pdf';
    }
  }

  String documentNameFor(String invoiceNumber) {
    switch (this) {
      case InvoicePdfExportMode.invoiceOnly:
        return 'factura_$invoiceNumber';
      case InvoicePdfExportMode.invoiceWithDiagnosis:
        return 'factura_${invoiceNumber}_con_diagnostico';
    }
  }
}

class InvoiceDiagnosisNarrative {
  const InvoiceDiagnosisNarrative({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;
}

class InvoicePdfGenerator {
  static Uint8List? _cachedLogoBytes;
  static String? _cachedLogoUrl;

  static Future<String?> resolveDefaultSaveDirectory() async {
    final downloadsDirectory = await getDownloadsDirectory();
    return downloadsDirectory?.path;
  }

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

  static Future<List<InvoiceDiagnosisNarrative>> resolveDiagnosisNarratives(
    BuildContext context,
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) async {
    final narratives = <InvoiceDiagnosisNarrative>[];

    try {
      final db = context.read<DatabaseService>();
      final jobBikeIds = invoice.items
          .where((item) => item.jobBikeId != null && item.jobBikeId!.isNotEmpty)
          .map((item) => item.jobBikeId!)
          .toSet()
          .toList(growable: false);

      final linkedJobId = await _resolveLinkedJobId(db, invoice, jobBikeIds);

      if (jobBikeIds.isNotEmpty) {
        narratives.addAll(
          await _loadJobBikeNarratives(
            db,
            resolvedBikeNames,
            filterJobBikeIds: jobBikeIds,
          ),
        );
      } else if (linkedJobId != null) {
        narratives.addAll(
          await _loadJobBikeNarratives(
            db,
            resolvedBikeNames,
            linkedJobId: linkedJobId,
          ),
        );
      }

      if (narratives.isEmpty && linkedJobId != null) {
        final jobNarrative = await _loadJobLevelNarrative(db, linkedJobId);
        if (jobNarrative != null) {
          narratives.add(jobNarrative);
        }
      }
    } catch (e) {
      debugPrint('Could not resolve diagnosis narratives for PDF: $e');
    }

    return narratives;
  }

  static Future<pw.Document> generateInvoicePDF(
    BuildContext context,
    Invoice invoice,
    Map<String, String> resolvedBikeNames, {
    List<InvoiceDiagnosisNarrative> diagnosisNarratives =
        const <InvoiceDiagnosisNarrative>[],
    InvoicePdfDocumentKind documentKind = InvoicePdfDocumentKind.invoice,
    DateTime? validUntil,
    double discountAmount = 0,
  }) async {
    final logoImage = await _loadLogoImage(context);

    return buildDocumentPDF(
      invoice,
      resolvedBikeNames,
      logoImage: logoImage,
      diagnosisNarratives: diagnosisNarratives,
      documentKind: documentKind,
      validUntil: validUntil,
      discountAmount: discountAmount,
    );
  }

  /// Generates a customer-facing quotation without creating or implying an
  /// invoice, payment balance, or accounting document.
  static Future<pw.Document> generateQuotationPDF(
    BuildContext context,
    Invoice quotation,
    Map<String, String> resolvedBikeNames, {
    DateTime? validUntil,
    double discountAmount = 0,
  }) {
    return generateInvoicePDF(
      context,
      quotation,
      resolvedBikeNames,
      documentKind: InvoicePdfDocumentKind.quotation,
      validUntil: validUntil ?? quotation.dueDate,
      discountAmount: discountAmount,
    );
  }

  /// Generates a non-posting customer budget for a bicycle already received
  /// by the workshop. It is deliberately distinct from a standalone
  /// [generateQuotationPDF], whose commercial proposal has no received object.
  static Future<pw.Document> generateServiceBudgetPDF(
    BuildContext context,
    Invoice budget,
    Map<String, String> resolvedBikeNames, {
    DateTime? validUntil,
    double discountAmount = 0,
    List<InvoiceDiagnosisNarrative> diagnosisNarratives =
        const <InvoiceDiagnosisNarrative>[],
  }) {
    return generateInvoicePDF(
      context,
      budget,
      resolvedBikeNames,
      documentKind: InvoicePdfDocumentKind.serviceBudget,
      validUntil: validUntil ?? budget.dueDate,
      discountAmount: discountAmount,
      diagnosisNarratives: diagnosisNarratives,
    );
  }

  /// Public synchronous builder used by non-UI integrations and focused PDF
  /// contract tests. Existing UI callers should normally use
  /// [generateInvoicePDF], [generateQuotationPDF] or
  /// [generateServiceBudgetPDF] so the configured logo is resolved
  /// automatically.
  static pw.Document buildDocumentPDF(
    Invoice invoice,
    Map<String, String> resolvedBikeNames, {
    pw.ImageProvider? logoImage,
    List<InvoiceDiagnosisNarrative> diagnosisNarratives =
        const <InvoiceDiagnosisNarrative>[],
    InvoicePdfDocumentKind documentKind = InvoicePdfDocumentKind.invoice,
    DateTime? validUntil,
    double discountAmount = 0,
  }) {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.fromLTRB(34, 32, 34, 28),
        maxPages: 200,
        footer: (pageContext) => _buildFooter(pageContext, documentKind),
        build: (pageContext) => [
          _buildHeader(invoice, logoImage, documentKind),
          pw.SizedBox(height: 14),
          _buildPartyAndDateBlock(
            invoice,
            documentKind,
            validUntil: validUntil,
          ),
          ..._buildBikeBanner(invoice, resolvedBikeNames, documentKind),
          ..._buildProposalDescription(invoice, documentKind),
          _buildItemsTable(invoice, resolvedBikeNames, documentKind),
          pw.SizedBox(height: 18),
          _buildTotals(
            invoice,
            documentKind,
            discountAmount: discountAmount,
          ),
          if (diagnosisNarratives.isNotEmpty) ...[
            pw.NewPage(),
            ..._buildDiagnosisNarrativesSection(
              diagnosisNarratives,
              documentKind,
            ),
          ],
        ],
      ),
    );

    return pdf;
  }

  static String quotationFileNameFor(String quotationNumber) =>
      InvoicePdfDocumentKind.quotation.fileNameFor(quotationNumber);

  static String quotationDocumentNameFor(String quotationNumber) =>
      InvoicePdfDocumentKind.quotation.documentNameFor(quotationNumber);

  static String serviceBudgetFileNameFor(String budgetNumber) =>
      InvoicePdfDocumentKind.serviceBudget.fileNameFor(budgetNumber);

  static String serviceBudgetDocumentNameFor(String budgetNumber) =>
      InvoicePdfDocumentKind.serviceBudget.documentNameFor(budgetNumber);

  static List<pw.Widget> _buildProposalDescription(
    Invoice invoice,
    InvoicePdfDocumentKind documentKind,
  ) {
    if (documentKind != InvoicePdfDocumentKind.quotation) {
      return const <pw.Widget>[];
    }

    final description = (invoice.workDescription?.trim().isNotEmpty ?? false)
        ? invoice.workDescription!.trim()
        : invoice.reference?.trim();
    if (description == null || description.isEmpty) {
      return const <pw.Widget>[];
    }

    return <pw.Widget>[
      pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.grey100,
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Descripción de la cotización',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey800,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              _cleanPdfText(description),
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    ];
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

  static Future<String?> _resolveLinkedJobId(
    DatabaseService db,
    Invoice invoice,
    List<String> jobBikeIds,
  ) async {
    if (invoice.id != null && invoice.id!.isNotEmpty) {
      final jobDataList = await db.supabase
          .from('mechanic_jobs')
          .select('id')
          .eq('invoice_id', invoice.id as Object)
          .limit(1);

      if (jobDataList.isNotEmpty) {
        return jobDataList.first['id']?.toString();
      }
    }

    if (jobBikeIds.isEmpty) {
      return null;
    }

    final bikeData = await db.supabase
        .from('mechanic_job_bikes')
        .select('job_id')
        .eq('id', jobBikeIds.first as Object)
        .maybeSingle();

    return bikeData?['job_id']?.toString();
  }

  static Future<List<InvoiceDiagnosisNarrative>> _loadJobBikeNarratives(
    DatabaseService db,
    Map<String, String> resolvedBikeNames, {
    List<String>? filterJobBikeIds,
    String? linkedJobId,
  }) async {
    dynamic query = db.supabase.from('mechanic_job_bikes').select('''
          id,
          job_id,
          diagnosis,
          bike:bikes(brand, model, year)
        ''');

    if (filterJobBikeIds != null && filterJobBikeIds.isNotEmpty) {
      query = query.inFilter('id', filterJobBikeIds);
    } else if (linkedJobId != null && linkedJobId.isNotEmpty) {
      query = query.eq('job_id', linkedJobId);
    } else {
      return const <InvoiceDiagnosisNarrative>[];
    }

    final data = await query;
    if (data is! List) {
      return const <InvoiceDiagnosisNarrative>[];
    }

    final narratives = <InvoiceDiagnosisNarrative>[];
    for (final row in data) {
      if (row is! Map) continue;
      final diagnosis = row['diagnosis']?.toString().trim();
      if (diagnosis == null || diagnosis.isEmpty) continue;

      final jobBikeId = row['id']?.toString();
      final title = _resolveDiagnosisTitle(
        row,
        resolvedBikeNames[jobBikeId]?.trim(),
      );

      narratives.add(
        InvoiceDiagnosisNarrative(
          title: title,
          content: diagnosis,
        ),
      );
    }

    return narratives;
  }

  static Future<InvoiceDiagnosisNarrative?> _loadJobLevelNarrative(
    DatabaseService db,
    String jobId,
  ) async {
    final jobData = await db.supabase
        .from('mechanic_jobs')
        .select('job_number, diagnosis')
        .eq('id', jobId as Object)
        .maybeSingle();

    final diagnosis = jobData?['diagnosis']?.toString().trim();
    if (diagnosis == null || diagnosis.isEmpty) {
      return null;
    }

    final jobNumber = jobData?['job_number']?.toString().trim();
    final title = (jobNumber != null && jobNumber.isNotEmpty)
        ? 'Diagnóstico general $jobNumber'
        : 'Diagnóstico general';

    return InvoiceDiagnosisNarrative(
      title: title,
      content: diagnosis,
    );
  }

  static String _resolveDiagnosisTitle(
    Map row,
    String? resolvedBikeName,
  ) {
    if (resolvedBikeName != null && resolvedBikeName.isNotEmpty) {
      return resolvedBikeName;
    }

    final bikeMap = row['bike'];
    if (bikeMap is Map) {
      final parts = <String>[
        if ((bikeMap['brand'] as String?)?.isNotEmpty == true)
          bikeMap['brand'] as String,
        if ((bikeMap['model'] as String?)?.isNotEmpty == true)
          bikeMap['model'] as String,
        if (bikeMap['year'] != null) bikeMap['year'].toString(),
      ];

      if (parts.isNotEmpty) {
        return parts.join(' ');
      }
    }

    return 'Bicicleta en servicio';
  }

  static pw.Widget _buildHeader(
    Invoice invoice,
    pw.ImageProvider? logoImage,
    InvoicePdfDocumentKind documentKind,
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
            if (documentKind.isProposal) ...[
              pw.Text(
                documentKind.label.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 17,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey900,
                  letterSpacing: 0.8,
                ),
              ),
              pw.SizedBox(height: 5),
            ],
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
              documentKind.isProposal
                  ? 'Total ${documentKind.labelLower}'
                  : 'Saldo adeudado',
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 1),
            pw.Text(
              ChileanUtils.formatCurrency(
                documentKind.isProposal ? invoice.total : invoice.balance,
              ),
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

  static pw.Widget _buildPartyAndDateBlock(
    Invoice invoice,
    InvoicePdfDocumentKind documentKind, {
    DateTime? validUntil,
  }) {
    final isProposal = documentKind.isProposal;
    final effectiveValidUntil = validUntil ?? invoice.dueDate;

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              isProposal ? '${documentKind.label} para' : 'Facturar a',
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
              isProposal
                  ? documentKind == InvoicePdfDocumentKind.serviceBudget
                      ? 'Fecha del presupuesto'
                      : 'Fecha de la cotización'
                  : 'Fecha de la factura',
              ChileanUtils.formatDate(invoice.date),
            ),
            if (isProposal)
              _buildMetaLine(
                'Válido hasta',
                effectiveValidUntil == null
                    ? 'No definido'
                    : ChileanUtils.formatDate(effectiveValidUntil),
              )
            else if (invoice.dueDate != null)
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
    InvoicePdfDocumentKind documentKind,
  ) {
    // A standalone quotation represents a commercial inquiry before the shop
    // receives an object. Even if a caller accidentally supplies a stale bike
    // map, the PDF must not claim custody of that bicycle.
    if (documentKind == InvoicePdfDocumentKind.quotation) {
      return const [];
    }
    final bikeNames = documentKind == InvoicePdfDocumentKind.serviceBudget
        ? _collectReceivedBikeNames(invoice, resolvedBikeNames)
        : _collectBikeNames(invoice, resolvedBikeNames);
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
            isMultiBike
                ? (documentKind == InvoicePdfDocumentKind.serviceBudget
                    ? 'Bicicletas recibidas'
                    : 'Bicicletas en servicio')
                : (documentKind == InvoicePdfDocumentKind.serviceBudget
                    ? 'Bicicleta recibida'
                    : 'Bicicleta en servicio'),
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
    InvoicePdfDocumentKind documentKind,
  ) {
    final groups = documentKind == InvoicePdfDocumentKind.quotation
        ? <_PdfInvoiceGroup>[
            _PdfInvoiceGroup(label: '')..items.addAll(invoice.items),
          ]
        : _groupItemsByBike(invoice, resolvedBikeNames);
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

  static pw.Widget _buildTotals(
    Invoice invoice,
    InvoicePdfDocumentKind documentKind, {
    double discountAmount = 0,
  }) {
    final isProposal = documentKind.isProposal;

    return pw.Row(
      children: [
        pw.Spacer(),
        pw.SizedBox(
          width: 250,
          child: pw.Column(
            children: [
              _buildPdfTotalRow('Subtotal', invoice.subtotal),
              if (isProposal && discountAmount > 0) ...[
                pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                _buildPdfTotalRow('Descuento', -discountAmount),
              ],
              if (invoice.ivaAmount > 0) ...[
                pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                _buildPdfTotalRow('IVA (19%)', invoice.ivaAmount),
              ],
              pw.Divider(thickness: 0.3, color: PdfColors.grey400),
              _buildPdfTotalRow('Total', invoice.total, isTotal: true),
              if (!isProposal && invoice.paidAmount > 0) ...[
                pw.Divider(thickness: 0.3, color: PdfColors.grey400),
                _buildPdfTotalRow('Pago realizado', -invoice.paidAmount),
              ],
              if (!isProposal) ...[
                pw.Divider(thickness: 1, color: PdfColors.grey800),
                _buildPdfTotalRow(
                  'Saldo adeudado',
                  invoice.balance,
                  isTotal: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static List<pw.Widget> _buildDiagnosisNarrativesSection(
    List<InvoiceDiagnosisNarrative> narratives,
    InvoicePdfDocumentKind documentKind,
  ) {
    return [
      pw.Text(
        'Ficha narrativa',
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        documentKind.isProposal
            ? documentKind == InvoicePdfDocumentKind.serviceBudget
                ? 'Se adjunta el diagnóstico narrativo asociado al presupuesto.'
                : 'Se adjunta el diagnóstico narrativo asociado a la cotización.'
            : 'Se adjunta el diagnóstico narrativo asociado al servicio facturado.',
        style: const pw.TextStyle(
          fontSize: 9,
          color: PdfColors.grey700,
        ),
      ),
      pw.SizedBox(height: 16),
      ...narratives.expand(
        (narrative) => [
          _buildDiagnosisNarrativeCard(narrative),
          pw.SizedBox(height: 14),
        ],
      ),
    ];
  }

  static pw.Widget _buildDiagnosisNarrativeCard(
    InvoiceDiagnosisNarrative narrative,
  ) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _cleanPdfText(narrative.title),
            style: pw.TextStyle(
              fontSize: 11.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blueGrey900,
            ),
          ),
          pw.SizedBox(height: 10),
          ..._buildNarrativeMarkdownBlocks(narrative.content),
        ],
      ),
    );
  }

  static List<pw.Widget> _buildNarrativeMarkdownBlocks(String rawContent) {
    final widgets = <pw.Widget>[];
    final paragraphBuffer = StringBuffer();

    void flushParagraph() {
      final text = paragraphBuffer.toString().trim();
      if (text.isEmpty) {
        paragraphBuffer.clear();
        return;
      }

      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            _cleanPdfText(text),
            style: const pw.TextStyle(
              fontSize: 9.4,
              color: PdfColors.black,
              lineSpacing: 2,
            ),
          ),
        ),
      );
      paragraphBuffer.clear();
    }

    final normalized = rawContent.replaceAll('\r\n', '\n');
    for (final rawLine in normalized.split('\n')) {
      final line = rawLine.trim();

      if (line.isEmpty) {
        flushParagraph();
        continue;
      }

      if (line.startsWith('### ') ||
          line.startsWith('## ') ||
          line.startsWith('# ')) {
        flushParagraph();
        final title = line.replaceFirst(RegExp(r'^#{1,3}\s+'), '').trim();
        if (title.isNotEmpty) {
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4, bottom: 6),
              child: pw.Text(
                _cleanPdfText(title),
                style: pw.TextStyle(
                  fontSize: 10.2,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
            ),
          );
        }
        continue;
      }

      if (line.startsWith('- ') || line.startsWith('• ')) {
        flushParagraph();
        final bulletText = line.substring(2).trim();
        if (bulletText.isNotEmpty) {
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6, left: 6),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '• ',
                    style: const pw.TextStyle(fontSize: 9.4),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      _cleanPdfText(bulletText),
                      style: const pw.TextStyle(
                        fontSize: 9.4,
                        color: PdfColors.black,
                        lineSpacing: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        continue;
      }

      if (paragraphBuffer.isNotEmpty) {
        paragraphBuffer.write(' ');
      }
      paragraphBuffer.write(line);
    }

    flushParagraph();

    if (widgets.isEmpty) {
      widgets.add(
        pw.Text(
          _cleanPdfText(rawContent.trim()),
          style: const pw.TextStyle(
            fontSize: 9.4,
            color: PdfColors.black,
            lineSpacing: 2,
          ),
        ),
      );
    }

    return widgets;
  }

  static pw.Widget _buildFooter(
    pw.Context context,
    InvoicePdfDocumentKind documentKind,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 10),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            documentKind.isProposal
                ? documentKind == InvoicePdfDocumentKind.serviceBudget
                    ? 'Este presupuesto no constituye una factura. Sujeto a aprobación y disponibilidad.'
                    : 'Esta cotización no constituye una factura ni acredita recepción de bicicleta o componente. Sujeta a aprobación y disponibilidad.'
                : 'Gracias por su preferencia',
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

  static List<String> _collectReceivedBikeNames(
    Invoice invoice,
    Map<String, String> resolvedBikeNames,
  ) {
    final names = <String>[];
    final seen = <String>{};

    for (final entry in resolvedBikeNames.entries) {
      if (entry.key == 'single') continue;
      final name = entry.value.trim();
      if (name.isNotEmpty && seen.add(name)) names.add(name);
    }

    for (final name in _collectBikeNames(invoice, resolvedBikeNames)) {
      if (seen.add(name)) names.add(name);
    }

    return names;
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
