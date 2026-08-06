import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:convert';

import 'dart:async';
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import '../services/ocr_service.dart';
import '../services/ocr_file_handoff_service.dart';
import '../services/ocr_product_resolution_policy.dart';
import '../services/invoice_parser_service.dart';
import '../services/pdf_parser_service.dart';
import '../services/veryfi_proxy_service.dart';
import '../services/veryfi_adapter.dart';
import '../services/inventory_service.dart';
import '../models/product.dart' show Product, PurchaseTreatment;
import '../services/database_service.dart';
import '../services/tenant_service.dart';
import '../../modules/inventory/services/category_service.dart';
import '../../modules/inventory/models/category_models.dart' show Category;
import '../../modules/inventory/services/inventory_service.dart' as inv_service;
import '../../modules/inventory/models/inventory_models.dart' as inv_models;
import '../../modules/inventory/models/product_duplicate_candidate.dart';
import '../../modules/inventory/services/brand_service.dart';
import '../../modules/inventory/services/product_duplicate_matcher_service.dart';
import '../../modules/inventory/services/product_image_fingerprint_service.dart';
import '../../modules/inventory/widgets/product_duplicate_review_dialog.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../modules/inventory/models/brand_models.dart' show ProductBrand;
import '../../modules/ai_assistant/services/ai_service.dart';
import '../models/supplier_ocr_template.dart';
import '../services/image_service.dart';
import '../themes/vinabike_theme_roles.dart';
import '../utils/chilean_utils.dart';
import '../../modules/purchases/services/purchase_service.dart';
import '../../shared/models/supplier.dart' as shared_supplier;
import 'package:provider/provider.dart';

/// Callback when OCR completes successfully
typedef OnOCRComplete = void Function(ParsedInvoice parsedInvoice);

/// Callback when OCR fails
typedef OnOCRError = void Function(String error);

/// OCR Provider selection
enum OCRProvider {
  /// Local ML Kit OCR (on-device, free, works offline)
  local,

  /// Veryfi Cloud OCR (better accuracy, requires API key)
  veryfi,

  /// Auto-detect: Use Veryfi if configured, otherwise local
  auto,
}

/// Reusable OCR Upload Widget
/// Allows user to:
/// 1. Take photo with camera
/// 2. Pick image from gallery
/// 3. Pick PDF file
/// 4. Automatically extract text using OCR (local or Veryfi cloud)
/// 5. Parse invoice/receipt data
/// 6. Return parsed data to caller
class OCRUploadWidget extends StatefulWidget {
  /// Called when OCR successfully extracts invoice data
  final OnOCRComplete onComplete;

  /// Called when OCR fails
  final OnOCRError? onError;

  /// Type of document to scan
  final OCRDocumentType documentType;

  /// Show preview of extracted text before returning
  final bool showPreview;

  /// OCR provider to use
  /// - `OCRProvider.auto` (default): Use Veryfi if configured, otherwise local
  /// - `OCRProvider.veryfi`: Force Veryfi (will error if not configured)
  /// - `OCRProvider.local`: Force local ML Kit OCR
  final OCRProvider provider;

  /// Supplier ID to assign to newly created products
  final String? supplierId;

  /// Supplier name for display and assignment to products
  final String? supplierName;

  /// Show product/stock review. Expense capture uses the same OCR pipeline but
  /// only needs document header totals, supplier, date, and folio.
  final bool showLineItemReview;

  /// Optional title override for non-purchase invoice workflows.
  final String? title;

  /// Optional stored file to process immediately when the OCR widget opens.
  final OcrFileHandoffPayload? initialFile;

  const OCRUploadWidget({
    super.key,
    required this.onComplete,
    this.onError,
    this.documentType = OCRDocumentType.invoice,
    this.showPreview = true,
    this.provider = OCRProvider.auto,
    this.supplierId,
    this.supplierName,
    this.showLineItemReview = true,
    this.title,
    this.initialFile,
  });

  @override
  State<OCRUploadWidget> createState() => _OCRUploadWidgetState();
}

class _OCRUploadWidgetState extends State<OCRUploadWidget> {
  static const List<String> _invoiceFilePickerExtensions = [
    'pdf',
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
    'tif',
    'tiff',
    'heic',
    'heif',
    'json',
    'html',
    'htm',
  ];

  static const Set<String> _invoiceImageFileExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'bmp',
    'tif',
    'tiff',
    'heic',
    'heif',
  };

  static const Set<String> _supportedInvoiceFileExtensions = {
    'pdf',
    ..._invoiceImageFileExtensions,
    'json',
    'html',
    'htm',
  };

  final ImagePicker _picker = ImagePicker();
  final OCRService _ocrService = OCRService();
  final InvoiceParserService _parserService = InvoiceParserService();
  final PDFParserService _pdfService = PDFParserService();

  bool _isProcessing = false;
  bool _isDraggingInvoiceFile = false;
  String? _errorMessage;
  ParsedInvoice? _parsedData;
  ParsedInvoice? _baseParsedData;

  // Determined at runtime based on config
  bool _useVeryfi = false;
  bool _veryfiAvailable = false;
  bool _initialized = false;

  // Bulk product creation state
  bool _showBulkCreate = false;
  // True when the costs coming from OCR/JSON already include IVA (19%).
  // Auto-detected from the parsed invoice (e.g. AliExpress allocates IVA into
  // each unit price). Used to compute the suggested selling price correctly
  // and to avoid double-charging IVA when the user reviews the bulk dialog.
  bool _costsIncludeIva = false;
  List<_NewProductEntry> _newProductEntries = [];
  List<Category> _categories = [];
  List<ProductBrand> _brands = [];
  bool _creatingProducts = false;
  final Map<int, TextEditingController> _skuControllers = {};
  final ScrollController _bulkCreateHorizontalScrollController =
      ScrollController();
  Timer? _debounceTimer;
  bool _isDialogShowing = false;
  String? _supplierIdForNewProducts; // For potential future use
  String? _ocrSupplierName; // Supplier detected by OCR
  shared_supplier.Supplier? _ocrSupplier;
  bool _showStock = false; // Toggle to show/hide stock column
  bool _isSavingSupplierTemplate = false;
  bool _isCheckingSimilarProducts = false;
  bool _isOpeningBulkCreate = false;
  String? _similarProductMessage;
  String? _aliExpressSkuReservationOperationKey;
  int _aliExpressSkuReservationGeneration = 0;
  String? _processedInitialFileId;
  final AIAssistantService _aiAssistantService = AIAssistantService();

  @override
  void initState() {
    super.initState();
    _initializeOCR();
  }

  /// Whether the current platform supports local ML Kit OCR.
  /// ML Kit only works on iOS and Android, not on macOS/Windows/Linux/Web.
  bool get _isLocalOCRSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<void> _initializeOCR() async {
    try {
      // Initialize local OCR only on supported platforms (iOS/Android)
      if (_isLocalOCRSupported) {
        try {
          await _ocrService.initialize();
        } catch (e) {
          debugPrint('⚠️ Local OCR init failed: $e');
        }
      } else {
        debugPrint('ℹ️ Local ML Kit OCR not supported on this platform');
      }

      // Check Veryfi availability
      _veryfiAvailable = true;
      debugPrint('🔧 Veryfi proxy available through Supabase Edge Function');

      // Determine which provider to use
      switch (widget.provider) {
        case OCRProvider.auto:
          // Prefer local OCR on supported mobile platforms.
          // Use cloud OCR on desktop/web where ML Kit is unavailable.
          _useVeryfi = !_isLocalOCRSupported;
          break;
        case OCRProvider.veryfi:
          _useVeryfi = true;
          break;
        case OCRProvider.local:
          // If someone forces local on desktop, override to Veryfi
          if (!_isLocalOCRSupported) {
            _useVeryfi = true;
            debugPrint(
                '⚠️ Local OCR forced but not supported on this platform, switching to Veryfi');
          } else {
            _useVeryfi = false;
          }
          break;
      }
    } catch (e) {
      debugPrint('❌ OCR initialization error: $e');
    } finally {
      // Always mark as initialized so badge shows
      if (mounted) {
        setState(() => _initialized = true);
      }
      unawaited(_processInitialFileIfNeeded());
      debugPrint(
          '🔍 OCR initialized: useVeryfi=$_useVeryfi, veryfiAvailable=$_veryfiAvailable');
    }
  }

  Future<void> _processInitialFileIfNeeded() async {
    final file = widget.initialFile;
    if (file == null ||
        _processedInitialFileId == file.id ||
        _isProcessing ||
        !mounted) {
      return;
    }

    _processedInitialFileId = file.id;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _isDraggingInvoiceFile = false;
    });

    try {
      await _processInvoiceBytes(
        fileName: file.fileName,
        fileBytes: file.bytes,
        extension: file.extension,
        sourceSupplierId: file.sourceSupplierId,
        sourceSupplierName: file.sourceSupplierName,
        sourceSupplierWebsite: file.sourceSupplierWebsite,
        structuredInvoiceData: file.structuredInvoiceData,
      );
    } catch (error) {
      _handleInvoiceFileProcessingError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    // If showing bulk creation screen
    if (_showBulkCreate) {
      return _buildBulkCreateScreen();
    }

    // If preview enabled and we have data, show preview screen
    if (widget.showPreview && _parsedData != null) {
      return _buildPreviewScreen();
    }

    // Otherwise show upload options
    return _buildUploadScreen();
  }

  Widget _buildUploadScreen() {
    final accentColor = _isDraggingInvoiceFile
        ? Theme.of(context).colorScheme.primary
        : Colors.transparent;

    return DropTarget(
      enable: !_isProcessing,
      onDragEntered: (_) => setState(() => _isDraggingInvoiceFile = true),
      onDragExited: (_) => setState(() => _isDraggingInvoiceFile = false),
      onDragDone: (details) => _handleDroppedInvoiceFiles(details.files),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _isDraggingInvoiceFile
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.04)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Text(
              widget.title ??
                  (widget.documentType == OCRDocumentType.invoice
                      ? 'Escanear Factura'
                      : 'Escanear Boleta/Recibo'),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Provider indicator
            if (_initialized)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color:
                      _useVeryfi ? Colors.purple.shade50 : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _useVeryfi
                        ? Colors.purple.shade200
                        : Colors.blue.shade200,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _useVeryfi ? Icons.cloud : Icons.phone_android,
                      size: 16,
                      color: VinabikeThemeRoles.of(context).info.accent,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _useVeryfi ? 'Veryfi Cloud OCR' : 'OCR Local (ML Kit)',
                        style: TextStyle(
                          fontSize: 12,
                          color: _useVeryfi
                              ? Colors.purple.shade700
                              : Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),
            Text(
              _isDraggingInvoiceFile
                  ? 'Suelta la factura aquí'
                  : 'Toma una foto, selecciona una imagen o arrastra una imagen/PDF aquí',
              style: TextStyle(
                fontSize: 14,
                color: _isDraggingInvoiceFile
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[600],
                fontWeight: _isDraggingInvoiceFile
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Upload buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Camera button
                _buildActionButton(
                  icon: Icons.camera_alt,
                  label: 'Cámara',
                  onPressed: _isProcessing
                      ? null
                      : () => _pickImage(ImageSource.camera),
                ),
                // Gallery button
                _buildActionButton(
                  icon: Icons.photo_library,
                  label: 'Galería',
                  onPressed: _isProcessing
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                ),
                // PDF button
                _buildActionButton(
                  icon: Icons.upload_file,
                  label: 'Archivo',
                  onPressed: _isProcessing ? null : _pickInvoiceFile,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Processing indicator
            if (_isProcessing)
              Column(
                children: [
                  const SizedBox(height: 16),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_useVeryfi
                      ? 'Procesando con Veryfi...'
                      : 'Procesando imagen...'),
                ],
              ),

            // Error message
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red[700]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Cloud OCR warning (shown only if proxy availability is explicitly false)
            if (widget.provider == OCRProvider.veryfi &&
                !_veryfiAvailable &&
                _initialized)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[300]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'El OCR en la nube no está configurado en el servidor. Configura los secrets de Veryfi en Supabase Edge Functions.',
                          style: TextStyle(color: Colors.orange[700]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: onPressed != null ? Colors.blue[50] : Colors.grey[200],
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, size: 32),
            color: onPressed != null ? Colors.blue : Colors.grey,
            onPressed: onPressed,
            iconSize: 32,
            padding: const EdgeInsets.all(20),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: onPressed != null ? Colors.black87 : Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewScreen() {
    final data = _parsedData!;
    final theme = Theme.of(context);
    final invoiceDiagnostics = _getInvoiceDiagnostics(data);
    final aliExpressTemplateActive = _looksLikeAliExpressInvoice(data);
    final supplierTemplateActive =
        (_ocrSupplier?.ocrTemplate.enabled ?? false) ||
            aliExpressTemplateActive;
    final unresolvedProductCount = widget.showLineItemReview
        ? data.lineItems
            .where((item) =>
                item.matchedProductId == null ||
                item.matchedProductId!.trim().isEmpty)
            .length
        : 0;
    final hasResolvedSupplier = _ocrSupplier != null;
    final canUseParsedData = !widget.showLineItemReview ||
        (hasResolvedSupplier &&
            data.lineItems.isNotEmpty &&
            unresolvedProductCount == 0);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Status and Provider
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: VinabikeThemeRoles.of(context).success.container,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check,
                    color: VinabikeThemeRoles.of(context).success.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Factura Procesada',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _useVeryfi
                          ? 'Procesado con Inteligencia Artificial (Veryfi)'
                          : 'Procesado localmente',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              // Provider Badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: VinabikeThemeRoles.of(context).info.container,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _useVeryfi
                        ? VinabikeThemeRoles.of(context).info.border
                        : VinabikeThemeRoles.of(context).info.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _useVeryfi ? Icons.auto_awesome : Icons.phone_android,
                      size: 14,
                      color: VinabikeThemeRoles.of(context).info.accent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _useVeryfi ? 'Veryfi AI' : 'Local OCR',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: VinabikeThemeRoles.of(context).info.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Invoice Details Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context)
                      .colorScheme
                      .shadow
                      .withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                InkWell(
                  onTap: _showSupplierSelectionDialog,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildDetailRow(
                          Icons.store,
                          'Proveedor',
                          _ocrSupplierName ??
                              data.supplierName ??
                              'No detectado (Toca para seleccionar)',
                          isBold: true,
                          valueColor:
                              (_ocrSupplierName ?? data.supplierName) == null
                                  ? Colors.orange
                                  : null,
                        ),
                      ),
                      Icon(Icons.edit,
                          size: 16,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: supplierTemplateActive
                            ? Colors.blue.shade50
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: supplierTemplateActive
                              ? Colors.blue.shade200
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            supplierTemplateActive
                                ? Icons.auto_fix_high
                                : Icons.rule,
                            size: 14,
                            color: supplierTemplateActive
                                ? Colors.blue.shade700
                                : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            aliExpressTemplateActive
                                ? 'Plantilla AliExpress activa'
                                : supplierTemplateActive
                                    ? 'Plantilla OCR activa'
                                    : 'Sin plantilla OCR',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: supplierTemplateActive
                                  ? Colors.blue.shade700
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _isSavingSupplierTemplate
                          ? null
                          : _showSaveSupplierTemplateDialog,
                      icon: _isSavingSupplierTemplate
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_as, size: 16),
                      label: const Text('Guardar plantilla OCR'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () =>
                            _showEditInvoiceNumberDialog(data.invoiceNumber),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildDetailRow(
                                Icons.receipt,
                                'N° Factura',
                                data.invoiceNumber ?? '---',
                              ),
                            ),
                            Icon(Icons.edit,
                                size: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => _showEditDateDialog(data.date),
                        borderRadius: BorderRadius.circular(8),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildDetailRow(
                                Icons.calendar_today,
                                'Fecha',
                                data.date != null
                                    ? '${data.date!.day}/${data.date!.month}/${data.date!.year}'
                                    : '---',
                              ),
                            ),
                            Icon(Icons.edit,
                                size: 16,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildDetailRow(
                  Icons.attach_money,
                  'Total',
                  _formatAmount(data.total),
                  isBold: true,
                  valueColor: theme.colorScheme.primary,
                  valueSize: 18,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (widget.showLineItemReview) ...[
            // Products Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Productos Detectados (${data.lineItems.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (data.lineItems.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: _buildCompactDiagnosticsStatus(
                              invoiceDiagnostics),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () => setState(() => _showStock = !_showStock),
                  icon: Icon(
                    _showStock ? Icons.visibility_off : Icons.visibility,
                    size: 16,
                  ),
                  label: Text(_showStock ? 'Ocultar Stock' : 'Ver Stock'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (data.lineItems.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: VinabikeThemeRoles.of(context).warning.container,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: VinabikeThemeRoles.of(context).warning.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber,
                        color: VinabikeThemeRoles.of(context).warning.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No se detectaron productos individuales. Se importará solo el total.',
                        style: TextStyle(
                            color: VinabikeThemeRoles.of(context)
                                .warning
                                .onContainer),
                      ),
                    ),
                  ],
                ),
              )
            else
              // Altura acotada, no `Expanded`: esta sección vive dentro de un
              // scroll vertical, donde «ocupa el resto» no tiene resto que
              // ocupar. Con flex aquí el layout aborta y la revisión OCR se
              // mostraba como un cuadro en blanco (2026-08-06).
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      children: [
                        // Header Row
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(8)),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 32), // Status icon width
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 3,
                                child: Text('SKU',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 12)),
                              ),
                              Expanded(
                                flex: _showStock
                                    ? 8
                                    : 10, // Give description most space
                                child: Text('Descripción',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 12)),
                              ),
                              if (_showStock)
                                Expanded(
                                  flex: 2,
                                  child: Text('Stock',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                          fontSize: 12)),
                                ),
                              Expanded(
                                flex: 2,
                                child: Text('Cant.',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 12)),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text('Precio',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 12)),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text('Dscto',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 12)),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text('Total',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                        // Scrollable Data Rows
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 320),
                          child: SingleChildScrollView(
                            child: Column(
                              children: data.lineItems.map((item) {
                                final rowDiagnostics = _getRowDiagnostics(item);
                                // Determine verification status
                                Widget statusIcon;
                                String tooltip;

                                if (item.sku == null || item.sku!.isEmpty) {
                                  statusIcon = Icon(Icons.remove_circle_outline,
                                      size: 18,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant);
                                  tooltip = 'Sin código SKU';
                                } else if (item.existsInDatabase == true) {
                                  statusIcon = Icon(Icons.check_circle,
                                      size: 18,
                                      color: VinabikeThemeRoles.of(context)
                                          .success
                                          .accent);
                                  tooltip =
                                      'Producto encontrado: ${item.matchedProductName ?? item.sku}';
                                } else {
                                  statusIcon = Icon(Icons.warning_amber,
                                      size: 18,
                                      color: VinabikeThemeRoles.of(context)
                                          .warning
                                          .accent);
                                  tooltip = 'Producto nuevo - debe crearse';
                                }

                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                      border: Border(
                                          bottom: BorderSide(
                                              color: Theme.of(context)
                                                  .dividerColor))),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 32,
                                        child: Tooltip(
                                            message: tooltip,
                                            child: statusIcon),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 3,
                                        child: TextField(
                                          decoration: InputDecoration(
                                            hintText: 'ASIGNAR SKU',
                                            isDense: true,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 4, vertical: 4),
                                            border: (item.sku == null ||
                                                    item.sku!.isEmpty)
                                                ? OutlineInputBorder(
                                                    borderSide: BorderSide(
                                                        color: Colors
                                                            .orange.shade300,
                                                        width: 0.5),
                                                  )
                                                : InputBorder.none,
                                            filled: (item.sku == null ||
                                                item.sku!.isEmpty),
                                            fillColor:
                                                VinabikeThemeRoles.of(context)
                                                    .warning
                                                    .container,
                                            hintStyle: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: VinabikeThemeRoles.of(
                                                        context)
                                                    .warning
                                                    .border),
                                          ),
                                          controller:
                                              _skuControllers.putIfAbsent(
                                                  _parsedData!.lineItems
                                                      .indexOf(item),
                                                  () => TextEditingController(
                                                      text: item.sku)),
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: item.existsInDatabase == true
                                                ? VinabikeThemeRoles.of(context)
                                                    .success
                                                    .accent
                                                : null,
                                          ),
                                          onChanged: (newSku) =>
                                              _updateItemSku(item, newSku),
                                        ),
                                      ),
                                      Expanded(
                                        flex: _showStock ? 8 : 10,
                                        child: Text(
                                          item.description,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                      if (_showStock)
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                              item.currentStock?.toString() ??
                                                  '-',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant)),
                                        ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                            item.quantity?.toStringAsFixed(0) ??
                                                '1',
                                            style:
                                                const TextStyle(fontSize: 13)),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                            item.unitPrice != null
                                                ? '\$${item.unitPrice!.toStringAsFixed(0)}'
                                                : '-',
                                            style:
                                                const TextStyle(fontSize: 13)),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                            (item.discount != null &&
                                                    item.discount! > 0)
                                                ? '\$${item.discount!.toStringAsFixed(0)}'
                                                : (item.discountRate != null &&
                                                        item.discountRate! > 0)
                                                    ? '${item.discountRate!.toStringAsFixed(0)}%'
                                                    : '-',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: VinabikeThemeRoles.of(
                                                        context)
                                                    .warning
                                                    .onContainer)),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            if (!rowDiagnostics.isComplete ||
                                                !rowDiagnostics.isConsistent ||
                                                rowDiagnostics.wasAutoAdjusted)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    right: 6),
                                                child: Tooltip(
                                                  message:
                                                      _buildRowDiagnosticsTooltip(
                                                    item,
                                                    rowDiagnostics,
                                                  ),
                                                  child: Icon(
                                                    !rowDiagnostics
                                                                .isComplete ||
                                                            !rowDiagnostics
                                                                .isConsistent
                                                        ? Icons.error_outline
                                                        : Icons.auto_fix_high,
                                                    size: 16,
                                                    color: !rowDiagnostics
                                                                .isComplete ||
                                                            !rowDiagnostics
                                                                .isConsistent
                                                        ? VinabikeThemeRoles.of(
                                                                context)
                                                            .warning
                                                            .accent
                                                        : VinabikeThemeRoles.of(
                                                                context)
                                                            .info
                                                            .accent,
                                                  ),
                                                ),
                                              ),
                                            Text(
                                              item.total != null
                                                  ? '\$${item.total!.toStringAsFixed(0)}'
                                                  : '-',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: !rowDiagnostics
                                                            .isComplete ||
                                                        !rowDiagnostics
                                                            .isConsistent
                                                    ? VinabikeThemeRoles.of(
                                                            context)
                                                        .warning
                                                        .onContainer
                                                    : null,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 24),

            // Create New Products Button (if any unrecognized products)
            if (data.lineItems.any((item) => item.existsInDatabase == false))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: OutlinedButton.icon(
                  onPressed:
                      _isOpeningBulkCreate ? null : _openBulkCreateScreen,
                  icon: _isOpeningBulkCreate
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.add_circle_outline,
                          color: VinabikeThemeRoles.of(context).warning.accent),
                  label: Text(
                    'Crear ${data.lineItems.where((item) => item.existsInDatabase == false).length} Productos Nuevos',
                    style: TextStyle(
                      color: VinabikeThemeRoles.of(context).warning.accent,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: VinabikeThemeRoles.of(context).warning.border,
                    ),
                  ),
                ),
              ),
          ],

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _parsedData = null;
                      _baseParsedData = null;
                      _errorMessage = null;
                      _ocrSupplier = null;
                      _ocrSupplierName = null;
                      _supplierIdForNewProducts = null;
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: canUseParsedData
                      ? () => _handleUseParsedData(data)
                      : null,
                  icon: const Icon(Icons.check),
                  label: Text(canUseParsedData
                      ? 'Usar Datos'
                      : !hasResolvedSupplier
                          ? 'Seleccionar proveedor'
                          : data.lineItems.isEmpty
                              ? 'Sin productos detectados'
                              : unresolvedProductCount == 1
                                  ? 'Resolver 1 producto'
                                  : 'Resolver $unresolvedProductCount productos'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDiagnosticsStatus(_OCRInvoiceDiagnostics diagnostics) {
    final hasWarning = diagnostics.hasTotalMismatch ||
        diagnostics.inconsistentRowCount > 0 ||
        diagnostics.incompleteRowCount > 0;
    final hasAdjustments = diagnostics.adjustedRowCount > 0;

    if (!hasWarning && !hasAdjustments) {
      return const SizedBox.shrink();
    }

    final color =
        hasWarning ? Colors.orange.shade700 : Colors.blueGrey.shade700;
    final icon = hasWarning ? Icons.warning_amber_rounded : Icons.info_outline;

    final parts = <String>[];
    if (diagnostics.incompleteRowCount > 0) {
      parts.add('${diagnostics.incompleteRowCount} incompletas');
    }
    if (diagnostics.inconsistentRowCount > 0) {
      parts.add('${diagnostics.inconsistentRowCount} con desfase');
    }
    if (diagnostics.hasTotalMismatch) {
      parts.add('dif. ${_formatAmount(diagnostics.delta.abs())}');
    } else if (diagnostics.adjustedRowCount > 0) {
      parts.add('${diagnostics.adjustedRowCount} con plantilla');
    }

    final summary =
        hasWarning ? 'Revisar antes de importar' : 'OCR con plantilla aplicada';

    final tooltipLines = <String>[
      summary,
      'Total OCR: ${_formatAmount(diagnostics.headerTotal)}',
      'Suma líneas: ${_formatAmount(diagnostics.rowTotal)}',
      'Diferencia: ${_formatAmount(diagnostics.delta.abs())}',
    ];

    return Tooltip(
      message: tooltipLines.join('\n'),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$summary${parts.isNotEmpty ? ' · ${parts.join(' · ')}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: hasWarning ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildRowDiagnosticsTooltip(
    ParsedLineItem item,
    _OCRRowDiagnostics diagnostics,
  ) {
    final lines = <String>[];

    if (diagnostics.adjustmentSummary != null &&
        diagnostics.adjustmentSummary!.isNotEmpty) {
      lines.add('Nota OCR: ${diagnostics.adjustmentSummary}');
    }

    if (diagnostics.grossAmount != null) {
      lines.add('Bruto esperado: ${_formatAmount(diagnostics.grossAmount)}');
    }

    if (diagnostics.discountAmount > 0) {
      lines.add(
        'Descuento aplicado: ${_formatAmount(diagnostics.discountAmount)}',
      );
    }

    if (diagnostics.displayedTotal != null) {
      lines.add('Total OCR: ${_formatAmount(diagnostics.displayedTotal)}');
    }

    if (diagnostics.computedTotal != null) {
      lines.add(
        'Total calculado: ${_formatAmount(diagnostics.computedTotal)}',
      );
    }

    if (diagnostics.delta != null && diagnostics.delta!.abs() > 0) {
      lines.add('Diferencia: ${_formatAmount(diagnostics.delta!.abs())}');
    }

    if (!diagnostics.isComplete) {
      lines.add('Fila incompleta: falta cantidad, precio o total.');
    } else if (!diagnostics.isConsistent) {
      lines.add('La fila no cuadra con los valores actuales.');
    } else if (item.wasAutoAdjusted || item.discountInferred) {
      lines.add('La fila fue completada por una regla OCR del proveedor.');
    }

    return lines.join('\n');
  }

  /// Update SKU for a line item and re-verify against database
  void _updateItemSku(ParsedLineItem item, String newSku) {
    if (_parsedData == null) return;

    // Use debounce for real-time matching to avoid overlapping lookups and dialogs
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      final verifiedItem = await _verifySingleProduct(
        item.copyWith(sku: newSku.trim()),
        supplierId: _supplierIdForNewProducts ?? widget.supplierId,
      );

      // If we found a match, validate if names match
      if (verifiedItem.existsInDatabase == true &&
          verifiedItem.matchedProductId != null) {
        await _validateSkuMatch(item, verifiedItem);
      } else {
        // No match or mismatch cleared, just update the item
        _applyItemUpdate(item, verifiedItem);
      }
    });
  }

  void _applyItemUpdate(ParsedLineItem oldItem, ParsedLineItem newItem) {
    if (_parsedData == null) return;
    final updatedItems = _parsedData!.lineItems.map((i) {
      if (i == oldItem) {
        return newItem;
      }
      return i;
    }).toList();

    setState(() {
      _parsedData = _parsedData!.copyWith(lineItems: updatedItems);
    });
  }

  /// Validates if the matched product name corresponds to the invoice description.
  /// If not, asks the user for confirmation.
  Future<void> _validateSkuMatch(
      ParsedLineItem originalItem, ParsedLineItem verifiedItem) async {
    if (_isDialogShowing) return;

    final invoiceName = originalItem.description.trim().toLowerCase();
    final inventoryName = verifiedItem.matchedProductName!.trim().toLowerCase();

    // SIMPLE SIMILARITY CHECK:
    // If one contains the other or they are "similar enough" (basic check for now)
    bool isMatch = inventoryName.contains(invoiceName) ||
        invoiceName.contains(inventoryName) ||
        inventoryName == invoiceName;

    // Case-insensitive exact match or inclusion is considered "ok"
    if (isMatch) {
      _applyItemUpdate(originalItem, verifiedItem);
      return;
    }

    // DISCREPANCY DETECTED: Show confirmation dialog
    _isDialogShowing = true;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Discrepancia de Nombre'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'El SKU ingresado corresponde a un producto diferente en el inventario:'),
            const SizedBox(height: 16),
            _buildDiffRow('En Factura:', originalItem.description),
            _buildDiffRow('En Inventario:', verifiedItem.matchedProductName!),
            const SizedBox(height: 16),
            const Text('¿Cómo deseas proceder?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'REJECT'),
            child: Text('Ingresar otro SKU',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'SYNC'),
            child: const Text('Usar nombre de inventario'),
          ),
        ],
      ),
    );
    _isDialogShowing = false;

    if (result == 'SYNC') {
      // Update the item but ALSO overwrite description with the one from DB
      _applyItemUpdate(
          originalItem,
          verifiedItem.copyWith(
            description: verifiedItem.matchedProductName!,
          ));
    } else {
      // Reject match: clear SKU in the controller and revert item status
      final index = _parsedData!.lineItems.indexOf(originalItem);
      if (index != -1 && _skuControllers.containsKey(index)) {
        _skuControllers[index]!.clear();
      }
      _applyItemUpdate(originalItem, originalItem.copyWith(sku: ''));
    }
  }

  Widget _buildDiffRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          Text(value,
              style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ],
      ),
    );
  }

  /// Verify a single product against the database
  Future<ParsedLineItem> _verifySingleProduct(
    ParsedLineItem item, {
    String? supplierId,
  }) async {
    final inventoryService =
        Provider.of<InventoryService>(context, listen: false);

    Product? matchedProduct;

    // PRIORITY 1: Try to find by SKU (if available)
    if (item.sku != null && item.sku!.trim().isNotEmpty) {
      try {
        matchedProduct =
            await inventoryService.getProductBySku(item.sku!.trim());
      } catch (e) {
        debugPrint('   ❌ Error looking up SKU ${item.sku}: $e');
      }
    }

    // PRIORITY 2: Try to find by Supplier Code
    if (matchedProduct == null &&
        item.sku != null &&
        item.sku!.trim().isNotEmpty) {
      final cleanSku = item.sku!.trim();
      try {
        final scopedSupplierId = supplierId?.trim();
        if (scopedSupplierId != null && scopedSupplierId.isNotEmpty) {
          matchedProduct =
              await inventoryService.getProductBySupplierCodeForSupplier(
            supplierId: scopedSupplierId,
            supplierCode: cleanSku,
          );
        }
      } catch (e) {
        debugPrint('   ❌ Error looking up Supplier Code $cleanSku: $e');
      }
    }

    // PRIORITY 3: Fall back to searching by name (EXACT MATCH ONLY)
    final scopedSupplierId = supplierId?.trim();
    if (matchedProduct == null &&
        scopedSupplierId != null &&
        scopedSupplierId.isNotEmpty &&
        item.description.isNotEmpty) {
      try {
        final normalizedDescription = item.description.trim().toLowerCase();
        final candidateProducts =
            await inventoryService.searchProducts(item.description, limit: 25);

        for (final product in candidateProducts) {
          final normalizedProductName = product.name.trim().toLowerCase();
          if (product.supplierId == scopedSupplierId &&
              normalizedProductName == normalizedDescription) {
            matchedProduct = product;
            break;
          }
        }
      } catch (e) {
        debugPrint('   ❌ Error searching by name: $e');
      }
    }

    // Set verification result
    if (matchedProduct != null) {
      return item.copyWith(
        existsInDatabase: true,
        matchedProductId: matchedProduct.id,
        matchedProductName: matchedProduct.name,
        currentStock: matchedProduct.stockQuantity,
        sku: item.sku, // Keep whatever the user typed or OCR found
      );
    } else {
      return _clearProductResolution(item);
    }
  }

  ParsedLineItem _clearProductResolution(ParsedLineItem item) {
    return ParsedLineItem(
      description: item.description,
      sku: item.sku,
      rawRowText: item.rawRowText,
      imageUrl: item.imageUrl,
      productUrl: item.productUrl,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      total: item.total,
      discount: item.discount,
      discountRate: item.discountRate,
      discountInferred: item.discountInferred,
      wasAutoAdjusted: item.wasAutoAdjusted,
      adjustmentSummary: item.adjustmentSummary,
      existsInDatabase: false,
    );
  }

  /// Open the bulk product creation screen
  Future<void> _uploadImage(
      _NewProductEntry entry, Uint8List bytes, String fileName) async {
    if (!mounted || !_newProductEntries.contains(entry)) return;
    setState(() => entry.isUploadingImage = true);
    try {
      final result = await ImageService.uploadProductImageWithOptimization(
          bytes: bytes, fileName: fileName);
      if (!mounted || !_newProductEntries.contains(entry)) return;
      setState(() {
        entry.imageUrl = result.optimizedUrl ?? result.originalUrl;
        entry.imageUrlOptimized = result.optimizedUrl;
        entry.imageBytes = bytes;
        entry.imageFileName = fileName;
        entry.invalidateDuplicateResolution();
      });
    } catch (e) {
      debugPrint('Error uploading image: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al subir imagen: $e')),
      );
    } finally {
      if (mounted && _newProductEntries.contains(entry)) {
        setState(() => entry.isUploadingImage = false);
      }
    }
  }

  Future<void> _openBulkCreateScreen() async {
    if (kDebugMode) {
      debugPrint(
        '🧪 [BulkCreate] pressed · parsed=${_parsedData != null} '
        'opening=$_isOpeningBulkCreate',
      );
    }
    if (_parsedData == null || _isOpeningBulkCreate) return;
    final sourceData = _parsedData!;
    setState(() => _isOpeningBulkCreate = true);

    try {
      // Get new products (all unrecognized items)
      final newProducts = sourceData.lineItems
          .where((item) => item.existsInDatabase == false)
          .toList();

      if (newProducts.isEmpty) return;

      // Category is mandatory for every created catalog product. Do not open a
      // form that can never be completed if its reference data did not load.
      try {
        final dbService = DatabaseService();
        final tenantService = TenantService();
        final categoryService = CategoryService(dbService, tenantService);
        final brandService = BrandService(dbService);
        // Con tope: sin él, una de las dos consultas colgada dejaba la
        // apertura del panel esperando para siempre, sin error ni panel, y el
        // botón parecía muerto (2026-08-06). Si vence, se avisa y se puede
        // reintentar en vez de quedar en un limbo silencioso.
        final results = await Future.wait<dynamic>([
          categoryService.getCategories(),
          brandService.getBrands(activeOnly: true),
        ]).timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'Las categorías y marcas no respondieron a tiempo.',
          ),
        );
        if (kDebugMode) {
          debugPrint('🧪 [BulkCreate] referencias cargadas');
        }
        if (!mounted || !identical(_parsedData, sourceData)) return;
        _categories = results[0] as List<Category>;
        _brands = results[1] as List<ProductBrand>;
        if (_categories.isEmpty) {
          throw StateError(
              'No hay categorías disponibles para crear productos.');
        }
      } catch (e) {
        debugPrint('Failed to load categories/brands: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No se pudo abrir la creación de productos: $e Reintenta.',
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
        return;
      }

      if (!mounted || !identical(_parsedData, sourceData)) return;

      // Auto-detect tax-inclusive cost source. AliExpress invoices allocate
      // IVA into each item's unitPrice, so the unit cost already contains IVA.
      final isAliExpressInvoice = _looksLikeAliExpressInvoice(sourceData);
      _costsIncludeIva = isAliExpressInvoice;

      final nextEntries = newProducts
          .map((item) => _NewProductEntry(
                originalItem: item,
                isSelected: true,
                initialSku: isAliExpressInvoice ? '' : null,
                selectedCategory: null,
                costIncludesIva: _costsIncludeIva,
                requiresDuplicateReview: isAliExpressInvoice,
              ))
          .toList();
      for (final oldEntry in _newProductEntries) {
        oldEntry.dispose();
      }
      _newProductEntries = nextEntries;

      // Assigned from the exact pending line identities on first reservation,
      // so retries replay while a reopened/partially completed invoice gets a
      // different request fingerprint.
      _aliExpressSkuReservationOperationKey = null;
      _aliExpressSkuReservationGeneration = 0;

      if (isAliExpressInvoice) {
        try {
          // Con tope: es una sugerencia de numeración, no un requisito para
          // abrir la revisión. Sin él, una consulta lenta dejaba el panel sin
          // abrir y el botón parecía no responder (2026-08-06); los SKU
          // definitivos se reservan igual al crear los productos.
          await _assignNextAliExpressSkus(_newProductEntries)
              .timeout(const Duration(seconds: 12));
        } catch (error) {
          debugPrint(
              '⚠️ [OCR] No se pudo preparar la secuencia SKU AE: $error');
        }
      }

      if (!mounted || !identical(_parsedData, sourceData)) return;
      if (kDebugMode) {
        debugPrint('🧪 [BulkCreate] abriendo panel de revisión');
      }
      setState(() {
        _showBulkCreate = true;
        _similarProductMessage = null;
      });

      if (isAliExpressInvoice) {
        // Matching must consume the final cleaned title/category/brand/model.
        await _aiCleanProductNamesForEntries();
        await _checkSimilarProductsForNewEntries(autoTriggered: true);
      }
    } finally {
      if (mounted) setState(() => _isOpeningBulkCreate = false);
    }
  }

  Future<void> _assignNextAliExpressSkus(
    List<_NewProductEntry> entries,
  ) async {
    if (entries.isEmpty) return;
    final inventoryService = inv_service.InventoryService(
      DatabaseService(),
      TenantService(),
    );
    final firstSku = await inventoryService.getNextAliExpressSku(
      supplierId: _supplierIdForNewProducts ?? widget.supplierId,
      supplierName:
          _ocrSupplierName ?? widget.supplierName ?? 'AliExpress Marketplace',
    );
    final firstSequence = int.tryParse(
          RegExp(r'^AE(\d{4,})$', caseSensitive: false)
                  .firstMatch(firstSku)
                  ?.group(1) ??
              '',
        ) ??
        1;
    for (var index = 0; index < entries.length; index++) {
      entries[index].skuController.text =
          'AE${(firstSequence + index).toString().padLeft(4, '0')}';
    }
  }

  Future<void> _reserveAliExpressSkusForEntries(
    List<_NewProductEntry> entries,
  ) async {
    final pending = entries
        .where((entry) => !entry.hasReservedAliExpressSku)
        .toList(growable: false);
    if (pending.isEmpty) return;

    final supplierId = (_supplierIdForNewProducts ?? widget.supplierId)?.trim();
    final supplierName = (_ocrSupplierName ?? widget.supplierName)?.trim();
    if (supplierId == null || supplierId.isEmpty) {
      throw StateError('Falta resolver el proveedor AliExpress.');
    }
    if (supplierName == null || supplierName.isEmpty) {
      throw StateError('Falta el nombre del proveedor AliExpress.');
    }
    final inventoryService = context.read<InventoryService>();
    for (var attempt = 0; attempt < 5; attempt++) {
      var operationKey = _aliExpressSkuReservationOperationKey?.trim();
      if (operationKey == null || operationKey.isEmpty) {
        operationKey = _buildAliExpressSkuReservationOperationKey(pending);
        _aliExpressSkuReservationOperationKey = operationKey;
      }

      final reservation = await inventoryService.reserveAliExpressSkus(
        count: pending.length,
        operationKey: operationKey,
        supplierId: supplierId,
        supplierName: supplierName,
      );
      if (reservation.skus.length != pending.length) {
        throw StateError('La reserva SKU devolvió una cantidad inesperada.');
      }

      var hasForeignCollision = false;
      for (final sku in reservation.skus) {
        if (await inventoryService.getProductBySku(sku) != null) {
          hasForeignCollision = true;
          break;
        }
      }
      if (hasForeignCollision) {
        _aliExpressSkuReservationGeneration++;
        _aliExpressSkuReservationOperationKey = null;
        continue;
      }

      for (var index = 0; index < pending.length; index++) {
        pending[index].skuController.text = reservation.skus[index];
        pending[index].hasReservedAliExpressSku = true;
      }
      return;
    }
    throw StateError(
      'No se pudo obtener un rango SKU AE libre después de 5 intentos.',
    );
  }

  String _buildAliExpressSkuReservationOperationKey(
    List<_NewProductEntry> entries,
  ) {
    final invoice = _parsedData;
    final identity = <String>[
      'v1',
      'generation=$_aliExpressSkuReservationGeneration',
      invoice?.invoiceNumber?.trim() ?? 'sin-folio',
      invoice?.date?.toIso8601String() ?? 'sin-fecha',
      (_supplierIdForNewProducts ?? widget.supplierId ?? '').trim(),
      for (final entry in entries) ...[
        _aliExpressItemIdForLine(entry.originalItem) ?? '',
        entry.originalItem.productUrl?.trim() ?? '',
        entry.originalItem.sku?.trim() ?? '',
        entry.originalItem.description.trim(),
        '${entry.originalItem.quantity ?? ''}',
        '${entry.originalItem.total ?? ''}',
      ],
    ].join('\u001f');
    final digest = ProductImageFingerprintService.contentDigest(
      Uint8List.fromList(utf8.encode(identity)),
    );
    return 'aliexpress-ocr-v1-${digest.substring(0, 32)}';
  }

  Future<void> _showSupplierSelectionDialog() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final dbService = DatabaseService();
      final suppliers = await dbService.select('suppliers');
      final allSuppliers = suppliers
          .map((s) => shared_supplier.Supplier.fromJson(s))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (mounted) {
        Navigator.pop(context); // Close loading start

        await showDialog(
          context: context,
          builder: (context) {
            String searchQuery = '';
            List<shared_supplier.Supplier> filteredSuppliers = allSuppliers;

            return StatefulBuilder(
              builder: (context, setState) {
                return AlertDialog(
                  title: const Text('Seleccionar Proveedor'),
                  content: SizedBox(
                    width: double.maxFinite,
                    height: 500, // Increased height for search bar
                    child: Column(
                      children: [
                        // Search Bar
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Buscar proveedor',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          onChanged: (value) {
                            setState(() {
                              searchQuery = _normalizeSimilarityText(value);
                              filteredSuppliers = allSuppliers
                                  .where((s) =>
                                      _supplierSearchText(s)
                                          .contains(searchQuery) ||
                                      (s.rut != null &&
                                          _normalizeSimilarityText(s.rut!)
                                              .contains(searchQuery)))
                                  .toList();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        // Supplier List
                        Expanded(
                          child: filteredSuppliers.isEmpty
                              ? const Center(
                                  child: Text('No se encontraron proveedores'),
                                )
                              : ListView.builder(
                                  itemCount: filteredSuppliers.length,
                                  itemBuilder: (context, index) {
                                    final supplier = filteredSuppliers[index];
                                    return ListTile(
                                      title: Text(supplier.displayName),
                                      subtitle: Text(
                                        _supplierSubtitle(supplier),
                                      ),
                                      onTap: () async {
                                        Navigator.pop(context);
                                        final source = _baseParsedData;
                                        if (!mounted || source == null) return;
                                        this.setState(
                                            () => _isProcessing = true);
                                        try {
                                          final supplierBase =
                                              await _verifyProductsInDatabase(
                                            source.copyWith(
                                              supplierName: supplier.name,
                                            ),
                                            supplierId: supplier.id,
                                          );
                                          if (!mounted) return;
                                          this.setState(() {
                                            _ocrSupplier = supplier;
                                            _ocrSupplierName = supplier.name;
                                            _supplierIdForNewProducts =
                                                supplier.id;
                                            _baseParsedData = supplierBase;
                                            _parsedData =
                                                _applySupplierTemplate(
                                              supplierBase,
                                              supplier,
                                            );
                                            _isProcessing = false;
                                          });
                                        } catch (error) {
                                          if (!mounted) return;
                                          this.setState(
                                              () => _isProcessing = false);
                                          ScaffoldMessenger.of(this.context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'No se pudo verificar el catálogo de ${supplier.name}: $error',
                                              ),
                                              backgroundColor:
                                                  Theme.of(this.context)
                                                      .colorScheme
                                                      .error,
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                  ],
                );
              },
            );
          },
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context); // Close loading on error if still open
      }
      debugPrint('Error loading suppliers: $e');
    }
  }

  /// Recompute the suggested selling price for every entry whose user has not
  /// manually overridden it. Called when the "costs already include IVA"
  /// toggle flips so the math stays consistent across all rows.
  void _recomputeSuggestedPricesFromCost() {
    for (final entry in _newProductEntries) {
      entry.costIncludesIva = _costsIncludeIva;
      final cost =
          double.tryParse(entry.costController.text.replaceAll(',', '.')) ?? 0;
      entry.priceController.text = _NewProductEntry._suggestedPriceFromCost(
        cost,
        costIncludesIva: _costsIncludeIva,
      );
    }
  }

  /// Compact info strip explaining how the suggested price is calculated and
  /// letting the user toggle whether the OCR/JSON cost already contains IVA.
  Widget _buildPricingRuleStrip() {
    final formula = _costsIncludeIva
        ? 'Precio sugerido = Costo × 2  (el costo ya incluye IVA, no se vuelve a sumar)'
        : 'Precio sugerido = Costo × 1,19 × 2  (Neto + IVA, luego margen 2x)';
    final hint = _costsIncludeIva
        ? 'Detectado: el proveedor distribuye IVA, envío y descuentos en el costo unitario (ej. AliExpress).'
        : 'Modo estándar: el costo es Neto y se le suma 19% de IVA antes del margen.';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color:
            _costsIncludeIva ? Colors.amber.shade50 : Colors.blueGrey.shade50,
        border: Border.all(
          color: _costsIncludeIva
              ? Colors.amber.shade200
              : Colors.blueGrey.shade200,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.calculate_outlined,
            size: 18,
            color: _costsIncludeIva
                ? Colors.amber.shade800
                : Colors.blueGrey.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formula,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Tooltip(
            message:
                'Activa si el costo ya trae IVA incluido (no se vuelve a sumar 19%).',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Costo con IVA',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                Switch(
                  value: _costsIncludeIva,
                  onChanged: (v) {
                    setState(() {
                      _costsIncludeIva = v;
                      _recomputeSuggestedPricesFromCost();
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the bulk product creation screen
  Widget _buildBulkCreateScreen() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double baseWChk = 40;
        const double baseWImg = 58;
        const double baseWSku = 130;
        const double baseWName = 260;
        const double baseWSimilar = 210;
        const double baseWCost = 110;
        const double baseWPrice = 110;
        const double baseWCat = 170;
        const double baseWBrand = 160;
        const double baseWTaller = 72;
        const double gap = 8;
        const double hPad = 12;
        const double borderAllowance = 2;
        const double minTableInnerWidth = hPad * 2 +
            borderAllowance +
            baseWChk +
            baseWImg +
            baseWSku +
            baseWName +
            baseWSimilar +
            baseWCost +
            baseWPrice +
            baseWCat +
            baseWBrand +
            baseWTaller +
            gap * 8;

        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minTableInnerWidth;
        final tableInnerWidth = math.max(minTableInnerWidth, availableWidth);
        final extraWidth = tableInnerWidth - minTableInnerWidth;

        const wChk = baseWChk;
        const wImg = baseWImg;
        final wSku = baseWSku + (extraWidth * 0.14);
        final wName = baseWName + (extraWidth * 0.30);
        final wSimilar = baseWSimilar + (extraWidth * 0.12);
        const wCost = baseWCost;
        const wPrice = baseWPrice;
        final wCat = baseWCat + (extraWidth * 0.22);
        final wBrand = baseWBrand + (extraWidth * 0.22);
        const wTaller = baseWTaller;

        Widget headerCell(String label, double width,
                {TextAlign align = TextAlign.left}) =>
            SizedBox(
              width: width,
              child: Text(label,
                  textAlign: align,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Color(0xFF616161))),
            );

        // O-04 de la guía de componentes: cuerpo con scroll propio y pie fijo
        // con un primario. La altura la acota el diálogo que la contiene.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header
                    Row(
                      children: [
                        const Icon(Icons.add_circle,
                            color: Colors.orange, size: 28),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Revisar productos de la factura',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                              Row(
                                children: [
                                  Text(
                                    '${_newProductEntries.where((e) => e.isSelected).length} de ${_newProductEntries.length} seleccionados',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant),
                                  ),
                                  Text(' • ',
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline)),
                                  Icon(
                                    (_ocrSupplierName ?? widget.supplierName) !=
                                            null
                                        ? Icons.local_shipping_outlined
                                        : Icons.warning_amber_rounded,
                                    size: 14,
                                    color: (_ocrSupplierName ??
                                                widget.supplierName) !=
                                            null
                                        ? Colors.orange.shade700
                                        : Colors.red.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _ocrSupplierName ??
                                        widget.supplierName ??
                                        'Sin proveedor',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: (_ocrSupplierName ??
                                                  widget.supplierName) !=
                                              null
                                          ? Colors.orange.shade700
                                          : Colors.red.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.manage_search,
                            size: 18,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _similarProductMessage ??
                                  (_looksLikeAliExpressInvoice(_parsedData!)
                                      ? 'Plantilla AliExpress: revisa parecidos antes de crear productos nuevos.'
                                      : 'Busca parecidos para reutilizar productos existentes antes de crear nuevos.'),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _bulkCreateBusy()
                                ? null
                                : () => _checkSimilarProductsForNewEntries(),
                            icon: _isCheckingSimilarProducts
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.search, size: 16),
                            label: Text(_isCheckingSimilarProducts
                                ? 'Buscando...'
                                : 'Buscar parecidos'),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Pricing rule strip ─ explains the suggested-price formula and
                    // lets the user toggle whether the OCR/JSON cost already
                    // includes IVA (e.g. AliExpress allocates tax into each unit).
                    _buildPricingRuleStrip(),

                    const SizedBox(height: 12),

                    // Table — always tableInnerWidth wide, scrolls horizontally if needed
                    Scrollbar(
                      controller: _bulkCreateHorizontalScrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      notificationPredicate: (notification) =>
                          notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _bulkCreateHorizontalScrollController,
                        scrollDirection: Axis.horizontal,
                        child: Container(
                          width: tableInnerWidth,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ── Header ──────────────────────────────────────────────
                              Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: hPad),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(9)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                        width: wChk), // checkbox placeholder
                                    headerCell('Img', wImg),
                                    const SizedBox(width: gap),
                                    headerCell('SKU', wSku),
                                    const SizedBox(width: gap),
                                    headerCell('Nombre', wName),
                                    const SizedBox(width: gap),
                                    headerCell('Parecidos', wSimilar),
                                    const SizedBox(width: gap),
                                    headerCell(
                                        _costsIncludeIva
                                            ? 'Costo (c/IVA)'
                                            : 'Costo (Neto)',
                                        wCost,
                                        align: TextAlign.center),
                                    const SizedBox(width: gap),
                                    headerCell(
                                        _costsIncludeIva
                                            ? 'Precio (×2)'
                                            : 'Precio (×1,19×2)',
                                        wPrice,
                                        align: TextAlign.center),
                                    const SizedBox(width: gap),
                                    headerCell('Categoría', wCat),
                                    const SizedBox(width: gap),
                                    headerCell('Marca', wBrand),
                                    const SizedBox(width: gap),
                                    headerCell('Taller', wTaller,
                                        align: TextAlign.center),
                                  ],
                                ),
                              ),
                              // ── Rows ─────────────────────────────────────────────────
                              ...List.generate(_newProductEntries.length,
                                  (index) {
                                final entry = _newProductEntries[index];
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: hPad, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: entry.isSelected
                                        ? Colors.white
                                        : Colors.grey.shade50,
                                    border: Border(
                                        top: BorderSide(
                                            color: Colors.grey.shade200)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // Checkbox
                                      SizedBox(
                                        width: wChk,
                                        child: Checkbox(
                                          value: entry.isSelected,
                                          onChanged:
                                              entry.requiresDuplicateReview
                                                  ? null
                                                  : (v) => setState(() => entry
                                                      .isSelected = v ?? false),
                                        ),
                                      ),
                                      // Image cell
                                      SizedBox(
                                        width: wImg - gap,
                                        child: DropTarget(
                                          onDragDone: (d) async {
                                            if (d.files.isNotEmpty) {
                                              final f = d.files.first;
                                              _uploadImage(
                                                  entry,
                                                  await f.readAsBytes(),
                                                  f.name);
                                            }
                                          },
                                          onDragEntered: (_) => setState(() =>
                                              entry.isHoveringImage = true),
                                          onDragExited: (_) => setState(() =>
                                              entry.isHoveringImage = false),
                                          child: MouseRegion(
                                            onEnter: (_) => setState(() =>
                                                entry.isHoveringImage = true),
                                            onExit: (_) => setState(() =>
                                                entry.isHoveringImage = false),
                                            child: Stack(children: [
                                              InkWell(
                                                onTap: () async {
                                                  final r = await ImageService
                                                      .pickImage();
                                                  if (r != null) {
                                                    _uploadImage(
                                                        entry, r.bytes, r.name);
                                                  }
                                                },
                                                child: Container(
                                                  width: 46,
                                                  height: 46,
                                                  decoration: BoxDecoration(
                                                    color: entry.isHoveringImage
                                                        ? Colors.blue
                                                            .withValues(
                                                                alpha: 0.08)
                                                        : Colors.grey[100],
                                                    border: Border.all(
                                                      color: entry
                                                              .isHoveringImage
                                                          ? Colors.blue
                                                          : Colors.grey[300]!,
                                                      width:
                                                          entry.isHoveringImage
                                                              ? 2
                                                              : 1,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: entry.isUploadingImage
                                                      ? const Center(
                                                          child: SizedBox(
                                                              width: 18,
                                                              height: 18,
                                                              child:
                                                                  CircularProgressIndicator(
                                                                      strokeWidth:
                                                                          2)))
                                                      : entry.imageUrl != null
                                                          ? ClipRRect(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          4),
                                                              child: ImageService
                                                                  .buildProductImage(
                                                                imageUrl: entry
                                                                    .imageUrl,
                                                                size: 46,
                                                              ),
                                                            )
                                                          : const Icon(
                                                              Icons
                                                                  .add_photo_alternate,
                                                              size: 18,
                                                              color:
                                                                  Colors.grey),
                                                ),
                                              ),
                                              if (entry.imageUrl != null &&
                                                  entry.isHoveringImage)
                                                Positioned(
                                                  right: 0,
                                                  top: 0,
                                                  child: GestureDetector(
                                                    onTap: () => setState(() {
                                                      entry.imageUrl = null;
                                                      entry.imageUrlOptimized =
                                                          null;
                                                      entry.imageBytes = null;
                                                      entry.imageFileName =
                                                          null;
                                                      entry
                                                          .invalidateDuplicateResolution();
                                                    }),
                                                    child: Container(
                                                      width: 16,
                                                      height: 16,
                                                      decoration:
                                                          const BoxDecoration(
                                                              color: Colors.red,
                                                              shape: BoxShape
                                                                  .circle),
                                                      child: const Icon(
                                                          Icons.close,
                                                          size: 11,
                                                          color: Colors.white),
                                                    ),
                                                  ),
                                                ),
                                            ]),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: gap),
                                      // SKU
                                      SizedBox(
                                        width: wSku,
                                        child: TextField(
                                          controller: entry.skuController,
                                          enabled: entry.isSelected,
                                          onChanged: (_) => setState(() {
                                            entry
                                                .invalidateDuplicateResolution();
                                          }),
                                          decoration: InputDecoration(
                                            isDense: true,
                                            border: const OutlineInputBorder(),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 8),
                                            errorText: entry.sku.isEmpty
                                                ? 'Requerido'
                                                : null,
                                            errorStyle:
                                                const TextStyle(fontSize: 10),
                                          ),
                                          style: const TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: gap),
                                      // Name
                                      SizedBox(
                                        width: wName,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            TextField(
                                              controller: entry.nameController,
                                              enabled: entry.isSelected,
                                              onChanged: (_) => setState(() {}),
                                              minLines: 1,
                                              maxLines: 2,
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 8),
                                              ),
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                            if (entry.isAICleaningName ||
                                                entry.nameWasAICleaned)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 3),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (entry.isAICleaningName)
                                                      const SizedBox(
                                                        width: 10,
                                                        height: 10,
                                                        child:
                                                            CircularProgressIndicator(
                                                                strokeWidth:
                                                                    1.5),
                                                      )
                                                    else
                                                      const Text('✨',
                                                          style: TextStyle(
                                                              fontSize: 11)),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      entry.isAICleaningName
                                                          ? 'IA limpiando título…'
                                                          : 'Limpiado por IA',
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: entry
                                                                .isAICleaningName
                                                            ? Colors
                                                                .grey.shade600
                                                            : Colors.deepPurple
                                                                .shade400,
                                                      ),
                                                    ),
                                                    if (entry
                                                            .nameWasAICleaned &&
                                                        entry.originalNoisyTitle !=
                                                            null) ...[
                                                      const SizedBox(width: 6),
                                                      Tooltip(
                                                        message:
                                                            'Título original:\n${entry.originalNoisyTitle}',
                                                        child: Icon(
                                                          Icons.info_outline,
                                                          size: 12,
                                                          color: Theme.of(
                                                                  context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: gap),
                                      SizedBox(
                                        width: wSimilar,
                                        child: _buildSimilarProductCell(entry),
                                      ),
                                      const SizedBox(width: gap),
                                      // Cost
                                      SizedBox(
                                        width: wCost,
                                        child: TextField(
                                          controller: entry.costController,
                                          enabled: entry.isSelected,
                                          onChanged: (_) => setState(() {}),
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            border: const OutlineInputBorder(),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 8),
                                            prefixText: '\$ ',
                                            hintText: '0',
                                            hintStyle: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline),
                                          ),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: gap),
                                      // Price
                                      SizedBox(
                                        width: wPrice,
                                        child: TextField(
                                          controller: entry.priceController,
                                          enabled: entry.isSelected,
                                          onChanged: (_) => setState(() {}),
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            isDense: true,
                                            border: const OutlineInputBorder(),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 8),
                                            prefixText: '\$ ',
                                            hintText: '0',
                                            hintStyle: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .outline),
                                          ),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(width: gap),
                                      // Category
                                      SizedBox(
                                        width: wCat,
                                        child: DropdownMenu<Category>(
                                          width: wCat,
                                          menuHeight: 280,
                                          initialSelection:
                                              entry.selectedCategory,
                                          hintText: 'Categoría',
                                          textStyle:
                                              const TextStyle(fontSize: 12),
                                          inputDecorationTheme:
                                              const InputDecorationTheme(
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 8),
                                            border: OutlineInputBorder(),
                                          ),
                                          enabled: entry.isSelected,
                                          enableFilter: true,
                                          requestFocusOnTap: true,
                                          dropdownMenuEntries: _categories
                                              .map((c) =>
                                                  DropdownMenuEntry<Category>(
                                                      value: c, label: c.name))
                                              .toList(),
                                          onSelected: (v) {
                                            if (v != null) {
                                              setState(() {
                                                entry.selectedCategory = v;
                                                entry
                                                    .invalidateDuplicateResolution();
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: gap),
                                      // Brand
                                      SizedBox(
                                        width: wBrand,
                                        child: DropdownMenu<ProductBrand>(
                                          width: wBrand,
                                          menuHeight: 280,
                                          initialSelection: entry.selectedBrand,
                                          hintText: 'Marca',
                                          textStyle:
                                              const TextStyle(fontSize: 12),
                                          inputDecorationTheme:
                                              const InputDecorationTheme(
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 8),
                                            border: OutlineInputBorder(),
                                          ),
                                          enabled: entry.isSelected,
                                          enableFilter: true,
                                          requestFocusOnTap: true,
                                          dropdownMenuEntries: _brands
                                              .map((b) => DropdownMenuEntry<
                                                      ProductBrand>(
                                                  value: b, label: b.name))
                                              .toList(),
                                          onSelected: (v) {
                                            if (v != null) {
                                              setState(() {
                                                entry.selectedBrand = v;
                                                entry
                                                    .invalidateDuplicateResolution();
                                              });
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: gap),
                                      // Workshop toggle
                                      SizedBox(
                                        width: wTaller,
                                        child: Tooltip(
                                          message: 'Consumible de taller',
                                          child: Center(
                                            child: Transform.scale(
                                              scale: 0.82,
                                              child: Switch.adaptive(
                                                value:
                                                    entry.isWorkshopConsumable,
                                                onChanged: entry.isSelected
                                                    ? (v) => setState(() => entry
                                                        .isWorkshopConsumable = v)
                                                    : null,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            _buildBulkCreateFooter(),
          ],
        );
      },
    );
  }

  /// Pie fijo de la revisión de productos (O-04 de la guía de componentes).
  ///
  /// Vive fuera del área con scroll a propósito: con las acciones al final del
  /// contenido, el botón para crear los productos quedaba bajo el pliegue y
  /// había que descubrirlo scrolleando —con ocho filas ya no se veía— y el
  /// motivo por el que estaba deshabilitado quedaba aún más lejos
  /// (2026-08-06). El aviso acompaña al primario porque explica justamente por
  /// qué no se puede continuar.
  Widget _buildBulkCreateFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_bulkCreateBlockingMessage() case final message?) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: VinabikeThemeRoles.of(context).warning.container,
              border: Border.all(
                  color: VinabikeThemeRoles.of(context).warning.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 17,
                    color: VinabikeThemeRoles.of(context).warning.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(
                      fontSize: 12,
                      color: VinabikeThemeRoles.of(context).warning.onContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _bulkCreateBusy()
                    ? null
                    : () {
                        for (final e in _newProductEntries) {
                          e.dispose();
                        }
                        _newProductEntries.clear();
                        setState(() => _showBulkCreate = false);
                      },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver'),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed:
                    _canCreateBulkProducts() ? _createBulkProducts : null,
                icon: _creatingProducts
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check),
                label: Text(
                  _creatingProducts
                      ? 'Creando...'
                      : 'Crear ${_newProductEntries.where((entry) => entry.isSelected).length} producto${_newProductEntries.where((entry) => entry.isSelected).length == 1 ? '' : 's'}',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor:
                      VinabikeThemeRoles.of(context).warning.accent,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _canCreateBulkProducts() => OcrProductResolutionPolicy.canCreate(
        globalBusy: _isOpeningBulkCreate ||
            _creatingProducts ||
            _isCheckingSimilarProducts,
        lines: _newProductEntries.map(
          (entry) => OcrProductResolutionSnapshot(
            selected: entry.isSelected,
            valid: entry.isValid,
            requiresDuplicateReview: entry.requiresDuplicateReview,
            state: entry.resolutionState,
            aiCleaning: entry.isAICleaningName,
            matchChecking: entry.isCheckingSimilar ||
                entry.isLinkingExisting ||
                entry.isUploadingImage,
          ),
        ),
      );

  bool _bulkCreateBusy() =>
      _isOpeningBulkCreate ||
      _creatingProducts ||
      _isCheckingSimilarProducts ||
      _newProductEntries.any((entry) =>
          entry.isAICleaningName ||
          entry.isCheckingSimilar ||
          entry.isLinkingExisting ||
          entry.isUploadingImage);

  String? _bulkCreateBlockingMessage() {
    final selected =
        _newProductEntries.where((entry) => entry.isSelected).toList();
    if (_creatingProducts) return null;
    if (selected.any((entry) =>
        entry.isAICleaningName ||
        entry.isCheckingSimilar ||
        entry.isLinkingExisting ||
        entry.isUploadingImage)) {
      return 'Espera a que termine el análisis o la carga de imágenes.';
    }
    final unresolved = selected
        .where(
            (entry) => entry.requiresDuplicateReview && !entry.isReadyToCreate)
        .length;
    if (unresolved > 0) {
      return 'Revisa $unresolved fila${unresolved == 1 ? '' : 's'}: vincula un producto existente o confirma que es nuevo.';
    }
    final incomplete = selected.where((entry) => !entry.isValid).length;
    if (incomplete > 0) {
      return 'Completa SKU, nombre, categoría, costo y precio en $incomplete fila${incomplete == 1 ? '' : 's'}.';
    }
    return null;
  }

  Widget _buildSimilarProductCell(_NewProductEntry entry) {
    if (entry.isLinkingExisting) {
      return const Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Guardando vínculo...', style: TextStyle(fontSize: 11)),
        ],
      );
    }

    if (entry.creationError != null) {
      return Tooltip(
        message: entry.creationError!,
        child: Row(
          children: [
            Icon(Icons.error_outline,
                size: 15, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Error al crear · reintentar',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      );
    }

    if (entry.isCheckingSimilar ||
        entry.resolutionState == OcrProductResolutionState.searching) {
      return Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Buscando...',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      );
    }

    if (entry.resolutionState == OcrProductResolutionState.newProduct) {
      return Tooltip(
        message: 'Revisión completa. Pulsa para buscar nuevamente.',
        child: InkWell(
          onTap: entry.isSelected && !_bulkCreateBusy()
              ? () => _checkSimilarProductsForNewEntries(entry: entry)
              : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              color: VinabikeThemeRoles.of(context).success.container,
              border: Border.all(color: Colors.green.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.add_box_outlined,
                    size: 15,
                    color: VinabikeThemeRoles.of(context).success.onContainer),
                const SizedBox(width: 6),
                Text(
                  'Nuevo',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade900,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (entry.resolutionState == OcrProductResolutionState.noCandidates) {
      return FilledButton.tonalIcon(
        onPressed: entry.isSelected && !_bulkCreateBusy()
            ? () => setState(() {
                  entry.markNewProduct();
                  _similarProductMessage =
                      'Producto nuevo confirmado manualmente.';
                })
            : null,
        icon: const Icon(Icons.add_box_outlined, size: 14),
        label: const Text('Confirmar nuevo'),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          textStyle: const TextStyle(fontSize: 12),
        ),
      );
    }

    if (entry.resolutionState == OcrProductResolutionState.failed) {
      return OutlinedButton.icon(
        onPressed: entry.isSelected && !_bulkCreateBusy()
            ? () => _checkSimilarProductsForNewEntries(entry: entry)
            : null,
        icon: const Icon(Icons.refresh, size: 14),
        label: const Text('Reintentar'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red.shade700,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          textStyle: const TextStyle(fontSize: 12),
        ),
      );
    }

    return ProductDuplicateSummaryButton(
      candidates: entry.similarCandidates,
      isEnabled: entry.isSelected && !_bulkCreateBusy(),
      onPressed: () => entry.similarCandidates.isEmpty
          ? _checkSimilarProductsForNewEntries(entry: entry)
          : _showSimilarProductsDialog(entry),
    );
  }

  /// Run the AI cleaner over noisy supplier titles (e.g. AliExpress) and
  /// rewrite each row's name field with a short, shop-friendly title plus
  /// suggested category/brand. Skips rows the user has already edited.
  /// Concurrency is capped to avoid hammering the Gemini proxy.
  Future<void> _aiCleanProductNamesForEntries({
    int concurrency = 3,
  }) async {
    if (_newProductEntries.isEmpty) return;

    // Lightweight normalizer: lowercase, strip accents, drop non-alphanumeric.
    String norm(String value) {
      final lower = value.toLowerCase();
      final unaccented = lower
          .replaceAll(RegExp(r'[áàäâã]'), 'a')
          .replaceAll(RegExp(r'[éèëê]'), 'e')
          .replaceAll(RegExp(r'[íìïî]'), 'i')
          .replaceAll(RegExp(r'[óòöôõ]'), 'o')
          .replaceAll(RegExp(r'[úùüû]'), 'u')
          .replaceAll('ñ', 'n');
      return unaccented.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    }

    // Chilean bike-shop synonym map. Both directions (suggested -> canonical
    // and canonical -> suggested) are checked. Singular/plural variants are
    // already handled by norm + substring, so list distinct concepts only.
    const categorySynonyms = <String, List<String>>{
      'asiento': ['sillin', 'sillines', 'asientos', 'sillon'],
      'asientos': ['sillin', 'sillines', 'asiento', 'sillon'],
      'porta caramagiola': [
        'portacaramagiola',
        'portacaramagiolas',
        'portabotella',
        'portabotellas',
        'porta botella',
        'porta botellas',
        'portabidon',
        'portabidones',
      ],
      'valvula tubeless': [
        'valvulas tubeless',
        'valvula',
        'valvulas',
        'valves tubeless',
      ],
      'cassette': ['cassettes', 'piñon', 'pinones', 'cassete'],
      'rotores': ['rotor', 'discos freno', 'disco freno'],
      'camaras': ['camara', 'tubos', 'tubo'],
      'puños': ['punos', 'puno', 'grips', 'grip'],
      'pastillas': ['pastilla', 'pastillas freno', 'pads freno'],
      'cadenas': ['cadena'],
      'missinglink': [
        'missing link',
        'missinglinks',
        'missing links',
        'eslabon rapido',
        'eslabones rapidos',
        'eslabon',
        'eslabones',
        'quick link',
        'quick links',
        'quicklink',
        'quicklinks',
        'cadena rapida',
        'cierre cadena',
        'cierres cadena',
      ],
      'postiza': ['postizas', 'postiza casette', 'postiza pinon'],
      'pedales': ['pedal'],
      'rayos': ['rayo', 'spokes'],
      'manillas': ['manilla', 'palanca freno', 'palancas freno'],
      'rodamientos': ['rodamiento', 'balines', 'balin', 'bearings'],
    };

    bool synonymMatch(String target, String candidateNorm) {
      // Direct synonym lookup: candidate canonical -> includes target?
      final candidateSynonyms = categorySynonyms[candidateNorm];
      if (candidateSynonyms != null) {
        for (final syn in candidateSynonyms) {
          final synN = norm(syn);
          if (synN == target ||
              synN.contains(target) ||
              target.contains(synN)) {
            return true;
          }
        }
      }
      // Reverse: target maps to a list that includes the candidate
      final targetSynonyms = categorySynonyms[target];
      if (targetSynonyms != null) {
        for (final syn in targetSynonyms) {
          if (norm(syn) == candidateNorm) return true;
        }
      }
      // Walk the map: any key whose synonym list contains target AND that
      // key EXACTLY equals candidate (no substring). This is the critical
      // anti-hijack rule: without exact equality, "sillin" (synonym of
      // "asiento") would also match local "Cubre Asientos" because that
      // string contains "asientos". We never want that.
      for (final entry in categorySynonyms.entries) {
        final keyN = norm(entry.key);
        if (keyN != candidateNorm) continue;
        final listHasTarget = entry.value.any((s) {
          final sN = norm(s);
          return sN == target || sN.contains(target) || target.contains(sN);
        });
        if (listHasTarget) return true;
      }
      return false;
    }

    // Fuzzy resolver: exact normalized match first (preferring the longest /
    // most specific local name), then synonyms, then bidirectional contains,
    // then significant word overlap, then compound-word matching. Returns
    // null when nothing is confidently close.
    Category? resolveCategory(String? suggested) {
      if (suggested == null) return null;
      final target = norm(suggested);
      if (target.isEmpty) return null;
      // 1. Exact normalized match — pick the most specific (longest name)
      // when several locals normalize the same. So "Válvula Tubeless" wins
      // over "Tubeless" when AI sends "valvula tubeless".
      Category? exactBest;
      for (final c in _categories) {
        if (norm(c.name) == target) {
          if (exactBest == null || c.name.length > exactBest.name.length) {
            exactBest = c;
          }
        }
      }
      if (exactBest != null) return exactBest;
      // 2. Synonym map (chilean shop vocabulary).
      Category? synonymBest;
      for (final c in _categories) {
        final cn = norm(c.name);
        if (cn.isEmpty) continue;
        if (synonymMatch(target, cn)) {
          if (synonymBest == null || c.name.length > synonymBest.name.length) {
            synonymBest = c;
          }
        }
      }
      if (synonymBest != null) return synonymBest;
      // 3. Substring either way; prefer longer (more specific) local name.
      Category? substringBest;
      for (final c in _categories) {
        final cn = norm(c.name);
        if (cn.isEmpty) continue;
        if (cn.contains(target) || target.contains(cn)) {
          if (substringBest == null ||
              c.name.length > substringBest.name.length) {
            substringBest = c;
          }
        }
      }
      if (substringBest != null) return substringBest;
      // 4. Word overlap (>=1 meaningful word, ignoring tiny stop tokens).
      final stop = {'de', 'del', 'la', 'el', 'los', 'las', 'para', 'y'};
      final targetTokens = target
          .split(' ')
          .where((t) => t.length >= 4 && !stop.contains(t))
          .toSet();
      for (final c in _categories) {
        final cTokens = norm(c.name)
            .split(' ')
            .where((t) => t.length >= 4 && !stop.contains(t))
            .toSet();
        if (cTokens.intersection(targetTokens).isNotEmpty) return c;
      }
      // 5. Compound-word matching: handles "Portacaramagiola" vs
      // "Porta Caramagiola". Strip spaces from both sides; if either is a
      // substring of the other AND the shorter one is >=6 chars, accept.
      final targetCompact = target.replaceAll(' ', '');
      if (targetCompact.length >= 6) {
        for (final c in _categories) {
          final cnCompact = norm(c.name).replaceAll(' ', '');
          if (cnCompact.length < 6) continue;
          if (cnCompact == targetCompact ||
              cnCompact.contains(targetCompact) ||
              targetCompact.contains(cnCompact)) {
            return c;
          }
        }
      }
      return null;
    }

    ProductBrand? resolveBrand(String? suggested) {
      if (suggested == null) return null;
      final target = norm(suggested);
      if (target.isEmpty) return null;
      for (final b in _brands) {
        if (norm(b.name) == target) return b;
      }
      for (final b in _brands) {
        final bn = norm(b.name);
        if (bn.isEmpty) continue;
        if (bn.contains(target) || target.contains(bn)) return b;
      }
      return null;
    }

    // Last-resort fallback: scan the product NAME (cleaned name first, then
    // original noisy title) for any local brand whose normalized form
    // appears as a whole token. So "Pedal ENLEE CR-2 aluminio" will pick up
    // local brand "ENLEE" even when the AI didn't fill the brand field.
    ProductBrand? scanBrandInName(String? name) {
      if (name == null) return null;
      final hay = ' ${norm(name)} ';
      if (hay.trim().isEmpty) return null;
      ProductBrand? best;
      for (final b in _brands) {
        final bn = norm(b.name);
        if (bn.length < 2) continue;
        if (hay.contains(' $bn ')) {
          if (best == null || bn.length > norm(best.name).length) best = b;
        }
      }
      return best;
    }

    // Same idea for category: keyword map from product-name token -> local
    // category name. Used only when the AI's suggested category didn't
    // resolve to any local row. Conservative on purpose.
    const nameToCategoryKeywords = <String, String>{
      'cincel': 'Herramientas',
      'martillo': 'Herramientas',
      'destornillador': 'Herramientas',
      'alicate': 'Herramientas',
      'llave': 'Herramientas',
      'sillin': 'Asientos',
      'sillon': 'Asientos',
      'asiento': 'Asientos',
      'pedal': 'Pedales',
      'pedales': 'Pedales',
      'puno': 'Puños',
      'punos': 'Puños',
      'grip': 'Puños',
      'cadena': 'Cadenas',
      'rotor': 'Rotores',
      'cassette': 'Cassette',
      'cassete': 'Cassette',
      'pinon': 'Cassette',
      'eslabon': 'Missinglink',
      'missinglink': 'Missinglink',
      'pastilla': 'Pastillas',
      'pastillas': 'Pastillas',
      'rodamiento': 'Rodamientos',
      'manilla': 'Manillas',
      'manubrio': 'Manubrios',
      'horquilla': 'Horquillas',
      'maza': 'Mazas',
      'rayo': 'Rayos',
      'llanta': 'Llantas',
      'camara': 'Cámaras',
      'tubeless': 'Tubeless',
      'valvula': 'Válvula Tubeless',
      'portacaramagiola': 'Porta Caramagiola',
      'portabotella': 'Porta Caramagiola',
      'portabidon': 'Porta Caramagiola',
      'tija': 'Tija',
      'shifter': 'Shifters',
      'casco': 'Cascos',
      'guante': 'Guantes',
      'luz': 'Luces',
      'parche': 'Parches',
      'lubricante': 'Lubricantes',
      'grasa': 'Grasa',
    };

    Category? scanCategoryInName(String? name) {
      if (name == null) return null;
      final hay = ' ${norm(name)} ';
      if (hay.trim().isEmpty) return null;
      for (final entry in nameToCategoryKeywords.entries) {
        if (hay.contains(' ${entry.key} ')) {
          final hit = resolveCategory(entry.value);
          if (hit != null) return hit;
        }
      }
      return null;
    }

    // Short-circuit: rows that already came in with addon AI cleanup.
    // The Chrome addon (>=0.4.0) stamps `aiCleaned/originalDescription/
    // aiCategory/aiBrand` per item; the JSON parser stuffs those into
    // rawRowText. We honor that here so we don't pay Gemini twice.
    String? extractMarker(String? raw, String key) {
      if (raw == null) return null;
      final regex = RegExp('$key:\\s*([^\\n]+)', caseSensitive: false);
      final match = regex.firstMatch(raw);
      final value = match?.group(1)?.trim();
      return (value == null || value.isEmpty) ? null : value;
    }

    for (final entry in _newProductEntries) {
      if (entry.nameUserEdited) continue;
      final raw = entry.originalItem.rawRowText;
      final isAddonCleaned = raw != null &&
          RegExp(r'AI_CLEANED:\s*true', caseSensitive: false).hasMatch(raw);
      if (!isAddonCleaned) continue;
      final originalTitle = extractMarker(raw, 'ORIGINAL_TITLE');
      final addonCategory = extractMarker(raw, 'AI_CATEGORY');
      final addonBrand = extractMarker(raw, 'AI_BRAND');
      final addonModel = extractMarker(raw, 'AI_MODEL');
      if (originalTitle != null) entry.originalNoisyTitle = originalTitle;
      if (addonCategory != null) entry.aiSuggestedCategoryName = addonCategory;
      if (addonBrand != null) entry.aiSuggestedBrandName = addonBrand;
      if (addonModel != null) entry.aiSuggestedModel = addonModel;
      entry.nameWasAICleaned = true;
      if (entry.selectedBrand == null && addonBrand != null) {
        final match = resolveBrand(addonBrand);
        if (match != null) entry.selectedBrand = match;
      }
      if (entry.selectedCategory == null && addonCategory != null) {
        final match = resolveCategory(addonCategory);
        if (match != null) entry.selectedCategory = match;
      }
      // Name-scan fallbacks: if the AI didn't fill or we couldn't resolve,
      // try to extract brand and category directly from the cleaned name.
      if (entry.selectedBrand == null) {
        final viaName = scanBrandInName(entry.nameController.text) ??
            scanBrandInName(entry.originalNoisyTitle);
        if (viaName != null) entry.selectedBrand = viaName;
      }
      if (entry.selectedCategory == null) {
        final viaName = scanCategoryInName(entry.nameController.text) ??
            scanCategoryInName(entry.originalNoisyTitle);
        if (viaName != null) entry.selectedCategory = viaName;
      }
    }

    for (final entry in _newProductEntries) {
      if (entry.nameUserEdited) continue;
      if (entry.nameWasAICleaned) continue; // addon already cleaned this row
      entry.isAICleaningName = true;
    }
    if (mounted) setState(() {});

    final pending = _newProductEntries
        .where((e) => !e.nameUserEdited && !e.nameWasAICleaned)
        .toList();
    if (pending.isEmpty) {
      // Nothing left for Gemini to do; just refresh the UI.
      if (mounted) setState(() {});
      return;
    }
    final supplierName = _ocrSupplierName ?? widget.supplierName;

    Future<void> processOne(_NewProductEntry entry) async {
      try {
        final raw =
            (entry.originalNoisyTitle ?? entry.nameController.text).trim();
        if (raw.isEmpty) {
          entry.isAICleaningName = false;
          return;
        }
        final result = await _aiAssistantService.cleanProductTitleFromImage(
          rawTitle: raw,
          imageBytes: entry.imageBytes,
          imageUrl: entry.imageUrl,
          supplierName: supplierName,
        );
        if (!mounted) return;
        if (result != null) {
          entry.aiSuggestedCategoryName = result.categoryName;
          entry.aiSuggestedBrandName = result.brand;
          entry.aiSuggestedModel = result.model;
          entry.applyAICleanedName(result.cleanedName);
          if (entry.selectedBrand == null && result.brand != null) {
            final match = resolveBrand(result.brand);
            if (match != null) entry.selectedBrand = match;
          }
          if (entry.selectedCategory == null && result.categoryName != null) {
            final match = resolveCategory(result.categoryName);
            if (match != null) entry.selectedCategory = match;
          }
          if (entry.selectedBrand == null) {
            final viaName = scanBrandInName(entry.nameController.text) ??
                scanBrandInName(entry.originalNoisyTitle);
            if (viaName != null) entry.selectedBrand = viaName;
          }
          if (entry.selectedCategory == null) {
            final viaName = scanCategoryInName(entry.nameController.text) ??
                scanCategoryInName(entry.originalNoisyTitle);
            if (viaName != null) entry.selectedCategory = viaName;
          }
        }
      } catch (e) {
        debugPrint('⚠️ [OCR] AI clean name failed for row: $e');
      } finally {
        entry.isAICleaningName = false;
        if (mounted) setState(() {});
      }
    }

    final iterator = pending.iterator;
    final workers = List.generate(concurrency, (_) async {
      while (iterator.moveNext()) {
        await processOne(iterator.current);
      }
    });
    await Future.wait(workers);
  }

  Future<void> _checkSimilarProductsForNewEntries({
    _NewProductEntry? entry,
    bool autoTriggered = false,
  }) async {
    if (!autoTriggered && _bulkCreateBusy()) return;
    final entries = entry == null
        ? _newProductEntries.where((e) => e.isSelected).toList()
        : [entry];
    if (entries.isEmpty) return;

    setState(() {
      _isCheckingSimilarProducts = entry == null;
      _similarProductMessage = autoTriggered
          ? 'Plantilla AliExpress: buscando parecidos antes de crear productos.'
          : 'Buscando productos parecidos...';
      for (final current in entries) {
        current.markSearching();
      }
    });

    try {
      final inventoryService = context.read<inv_service.InventoryService>();
      final allProducts = await inventoryService.getProducts();
      final duplicateMatcher = ProductDuplicateMatcherService(
        inventoryService: inventoryService,
        aiAssistantService: _aiAssistantService,
      );

      var flagged = 0;
      var unresolved = 0;
      var autoLinked = 0;
      for (final current in entries) {
        final revision = current.resolutionRevision;
        try {
          await _ensureEntryImageBytes(current);
          inv_models.Product? remembered;
          try {
            remembered = await _resolveRememberedProductAlias(
              current,
              inventoryService: inventoryService,
              products: allProducts,
            );
          } catch (aliasError) {
            // Learning is an optimization. A missing/transient alias service
            // must never prevent the current invoice from being reviewed.
            debugPrint(
                'Could not resolve remembered supplier alias: $aliasError');
          }
          if (remembered != null) {
            final linked =
                await _useExistingProductForEntry(current, remembered);
            if (linked) {
              autoLinked++;
              continue;
            }
          }
          final candidates = await duplicateMatcher.findCandidates(
            probe: ProductDuplicateProbe(
              name: current.nameController.text,
              description: current.originalItem.description,
              sku: _costsIncludeIva && current.supplierCode.isNotEmpty
                  ? current.supplierCode
                  : current.skuController.text.trim().isNotEmpty
                      ? current.skuController.text.trim()
                      : current.originalItem.sku,
              model: current.aiSuggestedModel,
              rawText: current.originalItem.rawRowText,
              categoryName: current.selectedCategory?.name ??
                  current.aiSuggestedCategoryName,
              brandName:
                  current.selectedBrand?.name ?? current.aiSuggestedBrandName,
              supplierId: _supplierIdForNewProducts ?? widget.supplierId,
              supplierName: _ocrSupplierName ?? widget.supplierName,
              imageUrl: current.imageUrl,
              imageBytes: current.imageBytes,
              imageFileName: current.imageFileName,
              price: current.price,
              cost: current.cost,
            ),
            products: allProducts,
          );
          // Ignore a stale response if the worker edited identity fields while
          // the matcher was running. The row returns to "Buscar" instead.
          if (current.resolutionRevision != revision) continue;
          if (candidates.isEmpty) {
            current.markNoCandidates();
          } else {
            current.markNeedsReview(candidates);
            flagged++;
          }
        } catch (error) {
          if (current.resolutionRevision == revision) {
            current.markResolutionFailed(error);
            unresolved++;
          }
          debugPrint('Error checking OCR row for duplicates: $error');
        }
        if (mounted) setState(() {});
      }

      if (!mounted) return;
      setState(() {
        _similarProductMessage = unresolved > 0
            ? 'No se pudieron revisar $unresolved fila${unresolved == 1 ? '' : 's'}. Reintenta antes de crear.'
            : flagged == 0
                ? autoLinked == 0
                    ? 'Revisión completa: confirma las filas sin coincidencias antes de crear productos nuevos.'
                    : '$autoLinked producto${autoLinked == 1 ? '' : 's'} vinculado${autoLinked == 1 ? '' : 's'} por una publicación ya confirmada; confirma las filas restantes.'
                : 'Hay $flagged fila${flagged == 1 ? '' : 's'} por confirmar. Vincula el existente o confirma producto nuevo.';
      });

      if (entry != null && entry.similarCandidates.isNotEmpty) {
        await _showSimilarProductsDialog(entry);
      }
    } catch (e) {
      debugPrint('Error checking OCR similar products: $e');
      if (!mounted) return;
      setState(() {
        _similarProductMessage =
            'No se pudo completar la búsqueda de parecidos.';
        for (final current in entries) {
          current.markResolutionFailed(e);
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isCheckingSimilarProducts = false);
      }
    }
  }

  String _normalizeSimilarityText(String value) {
    final lower = value.toLowerCase();
    final withoutAccents = lower
        .replaceAll(RegExp(r'[áàäâã]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöôõ]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll('ñ', 'n');
    return withoutAccents
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<inv_models.Product?> _resolveRememberedProductAlias(
    _NewProductEntry entry, {
    required inv_service.InventoryService inventoryService,
    required List<inv_models.Product> products,
  }) async {
    if (!entry.requiresDuplicateReview) return null;
    final supplierId = (_supplierIdForNewProducts ?? widget.supplierId)?.trim();
    final productUrl = entry.originalItem.productUrl?.trim();
    final itemId = _aliExpressItemIdForLine(entry.originalItem);
    final variantKey = _aliExpressVariantKeyForLine(entry.originalItem);
    if (supplierId == null ||
        supplierId.isEmpty ||
        itemId == null ||
        itemId.isEmpty ||
        variantKey == null ||
        variantKey.isEmpty) {
      return null;
    }

    final remembered =
        await context.read<InventoryService>().resolveSupplierProductAlias(
              supplierId: supplierId,
              productUrl: productUrl,
              itemId: itemId,
              variantKey: variantKey,
            );
    if (remembered == null) return null;

    for (final product in products) {
      if (product.id == remembered.id) return product;
    }
    return inventoryService.getProductById(remembered.id);
  }

  Future<void> _showSimilarProductsDialog(_NewProductEntry entry) async {
    var confirmedNewProduct = false;
    final selected = await showDialog<inv_models.Product>(
      context: context,
      builder: (context) => ProductDuplicateReviewDialog(
        rows: [
          ProductDuplicateReviewRow(
            title: entry.nameController.text,
            subtitle: entry.originalItem.description,
            imageUrl: entry.imageUrl,
            badges: [
              if (entry.sku.isNotEmpty) entry.sku,
              if ((entry.selectedCategory?.name ?? '').isNotEmpty)
                entry.selectedCategory!.name,
              if ((entry.selectedBrand?.name ?? '').isNotEmpty)
                entry.selectedBrand!.name,
              if ((entry.aiSuggestedModel ?? '').isNotEmpty)
                entry.aiSuggestedModel!,
            ],
            candidates: entry.similarCandidates,
            onCandidateSelected: (product) =>
                Navigator.of(context).pop(product),
          ),
        ],
        title: 'Productos parecidos',
        subtitle: entry.nameController.text,
        emptyActionLabel: 'Crear como producto nuevo',
        onEmptyAction: () {
          confirmedNewProduct = true;
          Navigator.of(context).pop();
        },
      ),
    );

    if (selected != null) {
      await _useExistingProductForEntry(entry, selected);
    } else if (confirmedNewProduct && mounted) {
      setState(() {
        entry.markNewProduct();
        _similarProductMessage =
            'Producto nuevo confirmado. Completa sus datos para crearlo.';
      });
    }
  }

  Future<bool> _useExistingProductForEntry(
    _NewProductEntry entry,
    inv_models.Product product,
  ) async {
    final productId = product.id;
    if (productId == null || _parsedData == null) return false;

    // 2026-08-05: aprender SIEMPRE, no sólo tras una revisión de duplicados.
    // Con la condición anterior, la primera creación/vínculo de cada producto
    // jamás guardaba su listing y la tabla de aliases llevaba 0 filas tras
    // ~10 facturas: cada re-importación volvía a adivinar desde cero. El
    // helper ya se autoprotege: sin itemId y variante reales no persiste.
    {
      if (mounted) setState(() => entry.isLinkingExisting = true);
      try {
        await _rememberAliExpressAlias(entry, productId: productId);
      } catch (error) {
        debugPrint('Error remembering AliExpress product alias: $error');
        if (mounted) {
          setState(() => entry.isLinkingExisting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Producto vinculado para esta factura, pero no se pudo guardar la publicación para el próximo ingreso. ($error)'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
      if (mounted) setState(() => entry.isLinkingExisting = false);
    }

    final oldItem = entry.originalItem;
    final existingSku = product.sku.trim();
    final updatedItem = oldItem.copyWith(
      description: product.name,
      existsInDatabase: true,
      matchedProductId: productId,
      matchedProductName: product.name,
      currentStock: product.inventoryQty,
      sku: existingSku.isNotEmpty ? existingSku : oldItem.sku,
    );

    final rowIndex = _parsedData!.lineItems.indexOf(oldItem);
    final updatedItems = _parsedData!.lineItems.map((item) {
      return identical(item, oldItem) || item == oldItem ? updatedItem : item;
    }).toList();

    if (rowIndex >= 0) {
      _skuControllers[rowIndex]?.text = updatedItem.sku ?? '';
    }

    setState(() {
      _parsedData = _parsedData!.copyWith(lineItems: updatedItems);
      if (_baseParsedData != null &&
          rowIndex >= 0 &&
          rowIndex < _baseParsedData!.lineItems.length) {
        final baseItems = List<ParsedLineItem>.from(_baseParsedData!.lineItems);
        baseItems[rowIndex] = updatedItem;
        _baseParsedData = _baseParsedData!.copyWith(lineItems: baseItems);
      }
      _newProductEntries.remove(entry);
      entry.dispose();
      _similarProductMessage =
          'Producto existente seleccionado: ${product.name}. Esa fila salió de la lista de creación.';
      if (_newProductEntries.isEmpty) {
        _showBulkCreate = false;
      }
    });
    return true;
  }

  String? _aliExpressItemIdForLine(ParsedLineItem item) {
    final ids = _extractAliExpressItemIds(
      '${item.productUrl ?? ''}\n${item.rawRowText ?? ''}',
    );
    return ids.isEmpty ? null : ids.first;
  }

  String? _aliExpressVariantKeyForLine(ParsedLineItem item) {
    final raw = item.rawRowText ?? '';
    for (final marker in ['VARIANT_KEY', 'VARIANT']) {
      final value = RegExp(
        '^$marker:\\s*(.+)\$',
        caseSensitive: false,
        multiLine: true,
      ).firstMatch(raw)?.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        return _normalizeSimilarityText(value).replaceAll(' ', '-');
      }
    }
    return null;
  }

  Future<bool> _rememberAliExpressAlias(
    _NewProductEntry entry, {
    required String productId,
  }) async {
    final supplierId = (_supplierIdForNewProducts ?? widget.supplierId)?.trim();
    if (supplierId == null || supplierId.isEmpty) {
      throw StateError('Falta resolver el proveedor AliExpress.');
    }

    final itemId = _aliExpressItemIdForLine(entry.originalItem);
    final variantKey = _aliExpressVariantKeyForLine(entry.originalItem);
    final productUrl = entry.originalItem.productUrl?.trim();
    // Order-message URLs are not product identities. Persist only when a real
    // AliExpress item ID was extracted from the item URL/markers; otherwise
    // the current manual link still applies without pretending it was learned.
    if (itemId == null ||
        itemId.isEmpty ||
        variantKey == null ||
        variantKey.isEmpty) {
      return false;
    }

    await _ensureEntryImageBytes(entry);
    if (!mounted) return false;
    final imageHash = entry.imageBytes == null
        ? null
        : ProductImageFingerprintService.contentDigest(entry.imageBytes!);
    await context.read<InventoryService>().rememberSupplierProductAlias(
          supplierId: supplierId,
          productId: productId,
          productUrl: productUrl,
          itemId: itemId,
          variantKey: variantKey,
          originalTitle:
              entry.originalNoisyTitle ?? entry.originalItem.description,
          model: entry.aiSuggestedModel,
          imageUrl: imageHash == null ? entry.imageUrl : null,
          imageContentHash: imageHash,
        );
    return true;
  }

  /// Create products from the bulk creation form
  Future<void> _createBulkProducts() async {
    final selectedEntries =
        _newProductEntries.where((entry) => entry.isSelected).toList();
    if (!_canCreateBulkProducts() || selectedEntries.isEmpty) return;

    setState(() => _creatingProducts = true);

    try {
      final dbService = DatabaseService();
      final tenantService = TenantService();
      final inventoryService =
          inv_service.InventoryService(dbService, tenantService);
      final sharedInventoryService = context.read<InventoryService>();
      final createdProducts = <_NewProductEntry, inv_models.Product>{};
      var failed = 0;
      var aliasWarnings = 0;

      if (_looksLikeAliExpressInvoice(_parsedData!)) {
        // The database serializes the shared AE namespace and replays this
        // exact reservation when a response is lost and the worker retries.
        await _reserveAliExpressSkusForEntries(selectedEntries);
      }

      for (final entry in selectedEntries) {
        entry.creationError = null;
        await _ensureEntryImageBytes(entry);
        final product = inv_models.Product(
          tenantId: tenantService.currentTenantId ?? '',
          name: entry.nameController.text.trim(),
          sku: entry.sku,
          price: entry.price!,
          cost: entry.cost,
          inventoryQty:
              0, // Always 0 for new products (stock added via invoice)
          minStockLevel: 5,
          maxStockLevel: 100,
          categoryId: entry.selectedCategory?.id,
          categoryName: entry.selectedCategory?.name,
          brandId: entry.selectedBrand?.id,
          brand: entry.selectedBrand?.name,
          supplierId: _supplierIdForNewProducts ?? widget.supplierId,
          supplierName: _ocrSupplierName ?? widget.supplierName,
          supplierCode:
              entry.supplierCode.isEmpty ? entry.sku : entry.supplierCode,
          isActive: true,
          purchaseTreatment: entry.isWorkshopConsumable
              ? PurchaseTreatment.workshopConsumable
              : PurchaseTreatment.inventory,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          imageUrl: entry.imageUrl,
          imageUrlOptimized: entry.imageUrlOptimized,
          imageFingerprint: entry.imageBytes == null
              ? null
              : ProductImageFingerprintService.computeStorageJson(
                  entry.imageBytes!,
                ),
        );

        try {
          var savedProduct = await inventoryService.createProduct(product);
          if (savedProduct.id != null) {
            try {
              await _rememberAliExpressAlias(
                entry,
                productId: savedProduct.id!,
              );
            } catch (error) {
              aliasWarnings++;
              debugPrint(
                  'Product was created but its supplier alias was not stored: $error');
            }
          }
          createdProducts[entry] = savedProduct;
          debugPrint('✅ Created product: ${product.name} (${product.sku})');
        } catch (e) {
          // A lost HTTP acknowledgement can happen after the insert commits.
          // Read back the reserved SKU before reporting a failure or allowing
          // a retry that would otherwise look like a duplicate.
          inv_models.Product? committedProduct;
          try {
            committedProduct = await inventoryService.getProductBySku(
              entry.sku,
            );
          } catch (readbackError) {
            debugPrint('Product read-back also failed: $readbackError');
          }
          if (committedProduct != null &&
              _matchesAttemptedProduct(product, committedProduct)) {
            createdProducts[entry] = committedProduct;
            debugPrint(
                '✅ Product commit confirmed by SKU read-back: ${entry.sku}');
          } else {
            failed++;
            if (committedProduct != null && entry.requiresDuplicateReview) {
              // Another legacy creator claimed a reserved-but-not-yet-used SKU.
              // Never interpret that row as this operation's commit. The next
              // retry receives a fresh audited range for the affected rows.
              entry.hasReservedAliExpressSku = false;
              _aliExpressSkuReservationGeneration++;
              _aliExpressSkuReservationOperationKey = null;
              entry.creationError =
                  'El SKU ${entry.sku} fue ocupado por otro producto. Reintenta para reservar uno nuevo.';
            } else {
              entry.creationError = e.toString();
            }
            debugPrint('❌ Failed to create product ${product.sku}: $e');
          }
        }
      }

      if (_parsedData != null && createdProducts.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          final parsedItems = List<ParsedLineItem>.from(_parsedData!.lineItems);
          final baseItems = _baseParsedData == null
              ? null
              : List<ParsedLineItem>.from(_baseParsedData!.lineItems);
          for (final created in createdProducts.entries) {
            final createdEntry = created.key;
            final savedProduct = created.value;
            final rowIndex = parsedItems.indexOf(createdEntry.originalItem);
            if (rowIndex >= 0) {
              final resolvedItem = createdEntry.originalItem.copyWith(
                description: savedProduct.name,
                sku: savedProduct.sku,
                existsInDatabase: true,
                matchedProductId: savedProduct.id,
                matchedProductName: savedProduct.name,
                currentStock: savedProduct.inventoryQty,
              );
              parsedItems[rowIndex] = resolvedItem;
              if (baseItems != null && rowIndex < baseItems.length) {
                baseItems[rowIndex] = resolvedItem;
              }
              _skuControllers[rowIndex]?.text = savedProduct.sku;
            }
            _newProductEntries.remove(createdEntry);
            createdEntry.dispose();
          }
          _parsedData = _parsedData!.copyWith(lineItems: parsedItems);
          if (_baseParsedData != null && baseItems != null) {
            _baseParsedData = _baseParsedData!.copyWith(lineItems: baseItems);
          }
          _showBulkCreate = _newProductEntries.isNotEmpty;
          _similarProductMessage = failed == 0
              ? null
              : '$failed producto${failed == 1 ? '' : 's'} no se pudieron crear. Corrige el error y reintenta; los creados no se repetirán.';
        });

        try {
          await sharedInventoryService.refresh();
        } catch (error) {
          debugPrint(
              'Products were committed but inventory cache refresh failed: $error');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(failed == 0
                  ? '✅ ${createdProducts.length} producto${createdProducts.length == 1 ? '' : 's'} creado${createdProducts.length == 1 ? '' : 's'}${aliasWarnings == 0 ? '' : '; $aliasWarnings vínculo${aliasWarnings == 1 ? '' : 's'} pendiente${aliasWarnings == 1 ? '' : 's'}'}'
                  : '${createdProducts.length} creados; $failed pendientes de reintento.'),
              backgroundColor: failed == 0 && aliasWarnings == 0
                  ? Colors.green
                  : Colors.orange,
            ),
          );
        }
      } else if (failed > 0 && mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'No se creó ningún producto. Las $failed filas siguen disponibles para reintentar.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error creating products: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creatingProducts = false);
    }
  }

  bool _matchesAttemptedProduct(
    inv_models.Product attempted,
    inv_models.Product readBack,
  ) {
    String normalized(String? value) =>
        _normalizeSimilarityText(value?.trim() ?? '');
    bool sameMoney(double left, double right) => (left - right).abs() <= 0.01;

    if (normalized(attempted.sku) != normalized(readBack.sku) ||
        normalized(attempted.name) != normalized(readBack.name) ||
        !sameMoney(attempted.cost, readBack.cost) ||
        !sameMoney(attempted.price, readBack.price)) {
      return false;
    }
    final expectedSupplierId = attempted.supplierId?.trim() ?? '';
    if (expectedSupplierId.isNotEmpty &&
        readBack.supplierId?.trim() != expectedSupplierId) {
      return false;
    }
    final expectedSupplierCode = normalized(attempted.supplierCode);
    if (expectedSupplierCode.isNotEmpty &&
        normalized(readBack.supplierCode) != expectedSupplierCode) {
      return false;
    }
    return true;
  }

  Future<void> _ensureEntryImageBytes(_NewProductEntry entry) async {
    if (entry.imageBytes != null) return;
    final imageUrl = entry.imageUrl?.trim();
    if (imageUrl == null || imageUrl.isEmpty) return;

    try {
      final uri = Uri.tryParse(imageUrl);
      if (uri == null || !uri.hasScheme) return;
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.isNotEmpty && !contentType.startsWith('image/')) return;
      if (response.bodyBytes.isEmpty ||
          response.bodyBytes.length > 8 * 1024 * 1024) {
        return;
      }
      entry.imageBytes = response.bodyBytes;
      entry.imageFileName ??= _NewProductEntry._imageFileNameFromUrl(imageUrl);
    } catch (e) {
      debugPrint('Could not download OCR row image for fingerprint: $e');
    }
  }

  Future<void> _showEditInvoiceNumberDialog(String? currentNumber) async {
    final controller = TextEditingController(text: currentNumber);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar N° Factura'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Número de Factura',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (result != null && _parsedData != null) {
      setState(() {
        _parsedData = _parsedData!.copyWith(invoiceNumber: result);
      });
    }
    controller.dispose();
  }

  Future<void> _showEditDateDialog(DateTime? currentDate) async {
    final now = DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: currentDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365)),
    );

    if (result != null && _parsedData != null) {
      setState(() {
        _parsedData = _parsedData!.copyWith(date: result);
      });
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value,
      {bool isBold = false, Color? valueColor, double? valueSize}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: Colors.grey.shade700),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: valueSize ?? 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: valueColor ?? Colors.black87,
              ),
            ),
          ],
        ),
      ],
    );
  }

  bool _isAliExpressSupplierName(String? value) {
    final normalized = _normalizeSimilarityText(value ?? '');
    return normalized.contains('aliexpress') ||
        normalized.contains('ali express') ||
        normalized.contains('ali express marketplace');
  }

  bool _looksLikeAliExpressInvoice(ParsedInvoice invoice, {String? fileName}) {
    return _isAliExpressSupplierName(invoice.supplierName) ||
        _isAliExpressSupplierName(widget.supplierName) ||
        _isAliExpressSupplierName(fileName) ||
        _isAliExpressSupplierName(invoice.rawText);
  }

  ParsedInvoice _applyAliExpressInvoiceNumber(
    ParsedInvoice invoice, {
    String? fileName,
  }) {
    if (!_looksLikeAliExpressInvoice(invoice, fileName: fileName)) {
      return invoice;
    }

    final invoiceDate = invoice.date ?? _extractAliExpressDate(invoice.rawText);
    if (invoiceDate == null) return invoice;

    final invoiceNumber = _formatAliExpressInvoiceNumber(invoiceDate);
    return invoice.copyWith(
      invoiceNumber: invoiceNumber,
      date: invoice.date ?? invoiceDate,
    );
  }

  String _formatAliExpressInvoiceNumber(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = (date.year % 100).toString().padLeft(2, '0');
    return 'AE$day$month$year';
  }

  DateTime? _extractAliExpressDate(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return null;

    final isoMatch =
        RegExp(r'\b(20\d{2})-(\d{1,2})-(\d{1,2})\b').firstMatch(text);
    if (isoMatch != null) {
      return _buildDate(
        year: int.tryParse(isoMatch.group(1) ?? ''),
        month: int.tryParse(isoMatch.group(2) ?? ''),
        day: int.tryParse(isoMatch.group(3) ?? ''),
      );
    }

    final dateMatches = RegExp(
      r'\b(\d{1,2})[/-](\d{1,2})[/-](20\d{2}|\d{2})\b',
    ).allMatches(text);
    for (final match in dateMatches) {
      final first = int.tryParse(match.group(1) ?? '');
      final second = int.tryParse(match.group(2) ?? '');
      var year = int.tryParse(match.group(3) ?? '');
      if (year != null && year < 100) year += 2000;
      if (first == null || second == null || year == null) continue;

      final firstLooksLikeMonth = first <= 12 && second > 12;
      final day = firstLooksLikeMonth ? second : first;
      final month = firstLooksLikeMonth ? first : second;
      final parsed = _buildDate(year: year, month: month, day: day);
      if (parsed != null) return parsed;
    }

    return null;
  }

  DateTime? _buildDate({int? year, int? month, int? day}) {
    if (year == null || month == null || day == null) return null;
    if (year < 2000 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  Future<shared_supplier.Supplier?> _matchSupplierForInvoice(
    ParsedInvoice invoice, {
    String? fileName,
    String? sourceSupplierId,
    String? sourceSupplierName,
    String? sourceSupplierWebsite,
  }) async {
    final supplierProbe = invoice.supplierName?.trim();
    final widgetSupplierId = widget.supplierId?.trim();
    final sourceSupplierIdProbe = sourceSupplierId?.trim();
    final sourceSupplierNameProbe = sourceSupplierName?.trim();
    final sourceSupplierWebsiteProbe = sourceSupplierWebsite?.trim();

    try {
      final purchaseService = context.read<PurchaseService>();
      final suppliers = await purchaseService.getSuppliers();
      if (suppliers.isEmpty) return null;

      final isAliExpressInvoice =
          _looksLikeAliExpressInvoice(invoice, fileName: fileName);

      if (isAliExpressInvoice) {
        try {
          return suppliers.firstWhere((s) => _isAliExpressSupplierName(s.name));
        } catch (_) {}
      }

      if (widgetSupplierId != null && widgetSupplierId.isNotEmpty) {
        try {
          return suppliers.firstWhere((s) => s.id == widgetSupplierId);
        } catch (_) {}
      }

      if (sourceSupplierIdProbe != null && sourceSupplierIdProbe.isNotEmpty) {
        try {
          return suppliers.firstWhere((s) => s.id == sourceSupplierIdProbe);
        } catch (_) {}
      }

      if (sourceSupplierWebsiteProbe != null &&
          sourceSupplierWebsiteProbe.isNotEmpty) {
        final websiteMatch =
            _matchSupplierByWebsite(sourceSupplierWebsiteProbe, suppliers);
        if (websiteMatch != null) return websiteMatch;
      }

      if (sourceSupplierNameProbe != null &&
          sourceSupplierNameProbe.isNotEmpty) {
        final sourceMatch =
            _matchSupplierFromList(sourceSupplierNameProbe, suppliers);
        if (sourceMatch != null) return sourceMatch;
      }

      if (supplierProbe == null || supplierProbe.isEmpty) return null;
      return _matchSupplierFromList(supplierProbe, suppliers);
    } catch (e) {
      debugPrint('Error matching supplier: $e');
    }
    return null;
  }

  Future<_PreparedOcrInvoice> _prepareInvoiceForReview(
    ParsedInvoice invoice, {
    String? fileName,
    String? sourceSupplierId,
    String? sourceSupplierName,
    String? sourceSupplierWebsite,
  }) async {
    final supplier = await _matchSupplierForInvoice(
      invoice,
      fileName: fileName,
      sourceSupplierId: sourceSupplierId,
      sourceSupplierName: sourceSupplierName,
      sourceSupplierWebsite: sourceSupplierWebsite,
    );

    final canonicalSupplierInvoice = ParsedInvoice(
      rut: invoice.rut,
      invoiceNumber: invoice.invoiceNumber,
      date: invoice.date,
      total: invoice.total,
      supplierName: supplier?.name,
      lineItems: invoice.lineItems,
      rawText: invoice.rawText,
    );
    final base = await _verifyProductsInDatabase(
      canonicalSupplierInvoice,
      supplierId: supplier?.id,
    );
    final display = supplier == null
        ? base
        : _applySupplierTemplate(base, supplier).copyWith(
            supplierName: supplier.name,
          );

    if (supplier != null) {
      debugPrint('✅ OCR matched supplier: ${supplier.name}');
    } else if (invoice.supplierName?.trim().isNotEmpty == true) {
      debugPrint('⚠️ Supplier not found in DB, clearing OCR result');
    }
    return _PreparedOcrInvoice(
      base: base,
      display: display,
      supplier: supplier,
    );
  }

  shared_supplier.Supplier? _matchSupplierByWebsite(
    String rawWebsite,
    List<shared_supplier.Supplier> suppliers,
  ) {
    final sourceUri = _normalizeSupplierWebsiteUri(rawWebsite);
    if (sourceUri == null) return null;
    final sourceHost = _normalizeSupplierWebsiteHost(sourceUri.host);
    if (sourceHost.isEmpty) return null;

    for (final supplier in suppliers) {
      final website = supplier.website?.trim();
      if (website == null || website.isEmpty) continue;
      final supplierUri = _normalizeSupplierWebsiteUri(website);
      if (supplierUri == null) continue;
      final supplierHost = _normalizeSupplierWebsiteHost(supplierUri.host);
      if (supplierHost.isEmpty) continue;
      if (sourceHost == supplierHost ||
          sourceHost.endsWith('.$supplierHost') ||
          supplierHost.endsWith('.$sourceHost')) {
        return supplier;
      }
    }

    return null;
  }

  Uri? _normalizeSupplierWebsiteUri(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final hasScheme = RegExp(r'^[a-z][a-z0-9+\-.]*://', caseSensitive: false)
        .hasMatch(trimmed);
    return Uri.tryParse(hasScheme ? trimmed : 'https://$trimmed');
  }

  String _normalizeSupplierWebsiteHost(String host) {
    final lower = host.toLowerCase().trim();
    if (lower.startsWith('www.')) return lower.substring(4);
    return lower;
  }

  shared_supplier.Supplier? _matchSupplierFromList(
    String rawName,
    List<shared_supplier.Supplier> suppliers,
  ) {
    if (suppliers.isEmpty) return null;

    final normalizedRaw = _normalizeSimilarityText(rawName);
    if (normalizedRaw.isEmpty) return null;

    if (_isAliExpressSupplierName(normalizedRaw)) {
      try {
        return suppliers.firstWhere((s) => _isAliExpressSupplierName(s.name));
      } catch (_) {}
    }

    if (normalizedRaw.contains('kaudat')) {
      try {
        return suppliers.firstWhere((s) {
          final supplierText = _supplierSearchText(s);
          return supplierText.contains('starken') ||
              supplierText.contains('kaudat');
        });
      } catch (_) {}
    }

    // 1. Exact match
    try {
      return suppliers
          .firstWhere((s) => _supplierIdentityTerms(s).contains(normalizedRaw));
    } catch (_) {}

    // 2. Database name contains OCR name (e.g. DB: "Big Supplier Inc", OCR: "Supplier")
    try {
      return suppliers.firstWhere((s) => _supplierIdentityTerms(s).any(
            (term) => term.contains(normalizedRaw),
          ));
    } catch (_) {}

    // 3. OCR name contains Database name (e.g. OCR: "DERMAN CICLISMO...", DB: "Derman")
    try {
      return suppliers.firstWhere(
        (s) => _supplierIdentityTerms(s).any(normalizedRaw.contains),
      );
    } catch (_) {}

    return null;
  }

  List<String> _supplierIdentityTerms(shared_supplier.Supplier supplier) {
    return supplier.identityNames
        .map(_normalizeSimilarityText)
        .where((term) => term.length >= 3)
        .toList(growable: false);
  }

  String _supplierSearchText(shared_supplier.Supplier supplier) {
    return _normalizeSimilarityText([
      ...supplier.identityNames,
      supplier.rut ?? '',
      supplier.phone ?? '',
    ].join(' '));
  }

  String _supplierSubtitle(shared_supplier.Supplier supplier) {
    final parts = <String>[
      if ((supplier.legalName ?? '').trim().isNotEmpty)
        supplier.legalName!.trim(),
      if ((supplier.rut ?? '').trim().isNotEmpty) supplier.rut!.trim(),
      if (supplier.aliases.isNotEmpty) supplier.aliases.take(3).join(', '),
    ];
    return parts.isEmpty ? 'Sin RUT' : parts.join(' · ');
  }

  ParsedInvoice _applySupplierTemplate(
    ParsedInvoice invoice,
    shared_supplier.Supplier? supplier,
  ) {
    return VeryfiAdapter.applySupplierOcrTemplate(
      invoice,
      supplier?.ocrTemplate,
      supplierName: supplier?.name ?? invoice.supplierName,
    );
  }

  Future<void> _showSaveSupplierTemplateDialog() async {
    if (_ocrSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Selecciona un proveedor antes de guardar una plantilla OCR.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    var enabled = _ocrSupplier!.ocrTemplate.enabled;
    var parser = _ocrSupplier!.ocrTemplate.discountParser;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Guardar plantilla OCR del proveedor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Proveedor: ${_ocrSupplier!.name}'),
              const SizedBox(height: 12),
              const Text(
                'Esta plantilla no inventa montos. Solo permite extraer el descuento desde el texto OCR de la fila cuando el proveedor usa columnas finales del tipo cantidad | precio | descuento | total.',
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Activar plantilla OCR'),
                subtitle:
                    const Text('Aplicar fallback determinístico por fila'),
                value: enabled,
                onChanged: (value) => setState(() => enabled = value),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<SupplierOcrDiscountParser>(
                initialValue: parser,
                decoration: const InputDecoration(
                  labelText: 'Regla de descuento',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: SupplierOcrDiscountParser.none,
                    child: Text('Sin regla adicional'),
                  ),
                  DropdownMenuItem(
                    value: SupplierOcrDiscountParser.anchoredTrailingNumeric,
                    child: Text(
                        'Texto OCR por fila: descuento entre precio y total'),
                  ),
                ],
                onChanged: enabled
                    ? (value) {
                        if (value != null) {
                          setState(() => parser = value);
                        }
                      }
                    : null,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (shouldSave != true || _ocrSupplier == null) {
      return;
    }

    if (!mounted) return;

    final template = SupplierOcrTemplate(
      enabled: enabled,
      discountParser: enabled ? parser : SupplierOcrDiscountParser.none,
    );

    setState(() => _isSavingSupplierTemplate = true);
    try {
      final purchaseService = context.read<PurchaseService>();
      final updatedSupplier = await purchaseService.saveSupplier(
        _ocrSupplier!.copyWith(ocrTemplate: template),
      );

      if (!mounted) return;

      setState(() {
        _ocrSupplier = updatedSupplier;
        _ocrSupplierName = updatedSupplier.name;
        _supplierIdForNewProducts = updatedSupplier.id;
        if (_baseParsedData != null) {
          _parsedData =
              _applySupplierTemplate(_baseParsedData!, updatedSupplier);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Plantilla OCR guardada para ${updatedSupplier.name}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la plantilla OCR: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingSupplierTemplate = false);
      }
    }
  }

  double _resolveParsedLineDiscountAmount(ParsedLineItem item) {
    if (item.discount != null && item.discount! > 0) {
      return item.discount!;
    }

    final qty = item.quantity;
    final unitPrice = item.unitPrice;
    final discountRate = item.discountRate;

    if (qty != null &&
        qty > 0 &&
        unitPrice != null &&
        unitPrice > 0 &&
        discountRate != null &&
        discountRate > 0) {
      return qty * unitPrice * (discountRate / 100);
    }

    return 0.0;
  }

  _OCRRowDiagnostics _getRowDiagnostics(ParsedLineItem item) {
    final qty = item.quantity;
    final unitPrice = item.unitPrice;
    final hasBaseValues =
        qty != null && qty > 0 && unitPrice != null && unitPrice > 0;

    final grossAmount = hasBaseValues ? qty * unitPrice : null;
    final discountAmount = _resolveParsedLineDiscountAmount(item);
    final computedTotal = grossAmount != null
        ? math.max(0.0, grossAmount - discountAmount).toDouble()
        : null;
    final displayedTotal = item.total ?? computedTotal;

    double? delta;
    bool isConsistent = true;
    final isComplete = hasBaseValues && displayedTotal != null;

    if (computedTotal != null && displayedTotal != null) {
      delta = displayedTotal - computedTotal;
      final tolerance = math
          .max(
            1.0,
            math.max(displayedTotal.abs(), computedTotal.abs()) * 0.001,
          )
          .toDouble();
      isConsistent = delta.abs() <= tolerance;
    } else if (hasBaseValues || item.total != null) {
      isConsistent = false;
    }

    return _OCRRowDiagnostics(
      isComplete: isComplete,
      isConsistent: isConsistent,
      wasAutoAdjusted: item.wasAutoAdjusted || item.discountInferred,
      grossAmount: grossAmount,
      discountAmount: discountAmount,
      displayedTotal: displayedTotal,
      computedTotal: computedTotal,
      delta: delta,
      adjustmentSummary: item.adjustmentSummary,
    );
  }

  _OCRInvoiceDiagnostics _getInvoiceDiagnostics(ParsedInvoice invoice) {
    final rowDiagnostics =
        invoice.lineItems.map(_getRowDiagnostics).toList(growable: false);
    final rowTotal = rowDiagnostics.fold<double>(
      0.0,
      (sum, row) => sum + (row.displayedTotal ?? 0.0),
    );
    final headerTotal = invoice.total;
    final delta = headerTotal != null ? headerTotal - rowTotal : 0.0;
    final tolerance = math
        .max(
          10.0,
          math.max(headerTotal?.abs() ?? 0.0, rowTotal.abs()) * 0.002,
        )
        .toDouble();

    return _OCRInvoiceDiagnostics(
      lineCount: invoice.lineItems.length,
      rowTotal: rowTotal,
      headerTotal: headerTotal,
      delta: delta,
      hasTotalMismatch: headerTotal != null && delta.abs() > tolerance,
      adjustedRowCount:
          rowDiagnostics.where((row) => row.wasAutoAdjusted).length,
      inconsistentRowCount:
          rowDiagnostics.where((row) => !row.isConsistent).length,
      incompleteRowCount: rowDiagnostics.where((row) => !row.isComplete).length,
    );
  }

  String _formatAmount(double? value) {
    if (value == null) return '---';
    return ChileanUtils.formatCurrency(value);
  }

  Future<void> _handleUseParsedData(ParsedInvoice data) async {
    if (widget.showLineItemReview) {
      if (_ocrSupplier == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Selecciona un proveedor antes de aplicar la factura.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      final unresolved = data.lineItems
          .where((item) =>
              item.matchedProductId == null ||
              item.matchedProductId!.trim().isEmpty)
          .length;
      if (data.lineItems.isEmpty || unresolved > 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data.lineItems.isEmpty
                  ? 'La factura no tiene productos detectados para aplicar.'
                  : 'Resuelve los $unresolved producto${unresolved == 1 ? '' : 's'} antes de usar la factura.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
    }
    final diagnostics = _getInvoiceDiagnostics(data);
    if (!diagnostics.shouldWarnBeforeApply) {
      widget.onComplete(data);
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Revisar Totales OCR'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'La factura OCR todavía tiene diferencias que pueden afectar los montos importados.',
            ),
            const SizedBox(height: 12),
            if (diagnostics.headerTotal != null)
              Text(
                'Total OCR: ${_formatAmount(diagnostics.headerTotal)} | Líneas: ${_formatAmount(diagnostics.rowTotal)} | Dif.: ${_formatAmount(diagnostics.delta.abs())}',
              ),
            if (diagnostics.inconsistentRowCount > 0)
              Text(
                  'Filas con desfase matemático: ${diagnostics.inconsistentRowCount}'),
            if (diagnostics.incompleteRowCount > 0)
              Text('Filas incompletas: ${diagnostics.incompleteRowCount}'),
            if (diagnostics.adjustedRowCount > 0)
              Text('Filas con plantilla OCR: ${diagnostics.adjustedRowCount}'),
            const SizedBox(height: 12),
            const Text('Puedes continuar igual o volver a revisar el preview.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Revisar primero'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continuar igual'),
          ),
        ],
      ),
    );

    if (proceed == true) {
      widget.onComplete(data);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Pick image
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image == null) {
        setState(() => _isProcessing = false);
        return;
      }

      debugPrint('📷 Image picked: ${image.path}');

      ParsedInvoice parsedData;

      if (_useVeryfi) {
        // Use Veryfi cloud OCR
        parsedData = await _processWithVeryfi(
          await image.readAsBytes(),
          image.name,
        );
      } else {
        // Process with local OCR
        final recognizedText = await _ocrService.processImage(image.path);
        if (recognizedText.text.isEmpty) {
          throw Exception('No se pudo extraer texto de la imagen');
        }
        parsedData = widget.documentType == OCRDocumentType.invoice
            ? _parserService.parseInvoice(recognizedText)
            : _parserService.parseReceipt(recognizedText);
      }

      debugPrint('📋 Parsed data: $parsedData');

      parsedData = _applyAliExpressInvoiceNumber(
        parsedData,
        fileName: image.name,
      );

      final prepared = await _prepareInvoiceForReview(
        parsedData,
        fileName: image.name,
      );
      parsedData = prepared.display;

      if (!mounted) return;
      setState(() {
        _baseParsedData = prepared.base;
        _parsedData = parsedData;
        _ocrSupplier = prepared.supplier;
        _ocrSupplierName = prepared.supplier?.name;
        _supplierIdForNewProducts = prepared.supplier?.id;
        _isProcessing = false;
      });
      if (!widget.showPreview) {
        await _handleUseParsedData(parsedData);
      }
    } catch (e) {
      debugPrint('❌ OCR error: $e');
      final errorMsg = _formatError(e);

      setState(() {
        _errorMessage = errorMsg;
        _isProcessing = false;
      });

      if (widget.onError != null) {
        widget.onError!(errorMsg);
      }
    }
  }

  Future<void> _pickInvoiceFile() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _isDraggingInvoiceFile = false;
    });

    try {
      // Pick invoice file (withData: true for web compatibility)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: _invoiceFilePickerExtensions,
        withData: true, // Load bytes for web
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isProcessing = false);
        return;
      }

      await _processInvoicePlatformFile(result.files.first);
    } catch (e) {
      _handleInvoiceFileProcessingError(e);
    }
  }

  Future<void> _handleDroppedInvoiceFiles(List<DropItem> files) async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _isDraggingInvoiceFile = false;
      _errorMessage = null;
    });

    try {
      DropItem? invoiceFile;
      for (final file in files) {
        final name = _dropFileName(file);
        final extension = _fileExtension(name);
        if (_isSupportedInvoiceFileExtension(extension)) {
          invoiceFile = file;
          break;
        }
      }

      if (invoiceFile == null) {
        throw Exception('Arrastra una imagen, PDF, HTML o JSON de factura.');
      }

      final fileName = _dropFileName(invoiceFile);
      final bytes = await invoiceFile.readAsBytes();
      await _processInvoiceBytes(
        fileName: fileName,
        fileBytes: bytes,
        extension: _fileExtension(fileName),
        filePath: invoiceFile.path,
      );
    } catch (e) {
      _handleInvoiceFileProcessingError(e);
    }
  }

  Future<void> _processInvoicePlatformFile(PlatformFile file) async {
    await _processInvoiceBytes(
      fileName: file.name,
      fileBytes: await _readPickedFileBytes(file),
      extension: _fileExtension(file.name, fallback: file.extension),
      filePath: file.path,
    );
  }

  Future<void> _processInvoiceBytes({
    required String fileName,
    required Uint8List fileBytes,
    required String extension,
    String? filePath,
    String? sourceSupplierId,
    String? sourceSupplierName,
    String? sourceSupplierWebsite,
    Map<String, dynamic>? structuredInvoiceData,
  }) async {
    ParsedInvoice? parsedData;
    ParsedInvoice? directPdfParsedData;
    final normalizedExtension = extension.isNotEmpty
        ? extension
        : _inferInvoiceFileExtension(fileBytes);
    final isPdf = normalizedExtension == 'pdf';
    final isImage = _isSupportedInvoiceImageExtension(normalizedExtension);

    if (structuredInvoiceData != null) {
      parsedData = _parseAliExpressInvoiceMap(structuredInvoiceData);
    } else if (isPdf) {
      directPdfParsedData = await _pdfService.parseInvoiceFromBytes(
        fileBytes,
        filename: fileName,
      );
    }

    if (parsedData != null) {
      // A trusted internal extractor already supplied the lossless invoice
      // structure alongside the human-readable PDF. Continue through the
      // same supplier matching, product verification and review below.
    } else if (isImage) {
      if (_useVeryfi) {
        parsedData = await _processWithVeryfi(
          fileBytes,
          _fileNameWithExtension(fileName, normalizedExtension),
        );
      } else if (filePath != null && filePath.trim().isNotEmpty && !kIsWeb) {
        final recognizedText = await _ocrService.processImage(filePath);
        if (recognizedText.text.isEmpty) {
          throw Exception('No se pudo extraer texto de la imagen');
        }
        parsedData = widget.documentType == OCRDocumentType.invoice
            ? _parserService.parseInvoice(recognizedText)
            : _parserService.parseReceipt(recognizedText);
      } else {
        throw Exception('No se pudo procesar esta imagen desde Archivo.\n\n'
            'Usa Galería o procesa con OCR en la nube.');
      }
    } else if (normalizedExtension == 'json') {
      parsedData = _parseAliExpressJsonFile(fileBytes);
    } else if (normalizedExtension == 'html' || normalizedExtension == 'htm') {
      parsedData = _parseAliExpressHtmlFile(fileBytes);
    } else if (directPdfParsedData != null &&
        directPdfParsedData.lineItems.isNotEmpty &&
        _looksLikeAliExpressInvoice(directPdfParsedData, fileName: fileName)) {
      parsedData = directPdfParsedData;
    } else if (_useVeryfi) {
      // Use Veryfi for PDFs and other supported document files.
      parsedData = await _processWithVeryfi(fileBytes, fileName);
      parsedData = _mergeLineItemMedia(parsedData, directPdfParsedData);
    } else {
      if (directPdfParsedData != null &&
          directPdfParsedData.lineItems.isNotEmpty) {
        parsedData = directPdfParsedData;
      } else {
        debugPrint('📄 Invoice file picked: $fileName');
        parsedData = await _pdfService.parseInvoiceFromBytes(fileBytes,
            filename: fileName);
      }
    }

    if (parsedData == null) {
      throw Exception(
          'Este PDF parece ser escaneado (sin texto seleccionable).\n\n'
          'Por favor, usa la opción de Cámara o Galería para escanear el documento.');
    }

    debugPrint('📋 Parsed invoice file data: $parsedData');

    parsedData = _applyAliExpressInvoiceNumber(
      parsedData,
      fileName: fileName,
    );

    final prepared = await _prepareInvoiceForReview(
      parsedData,
      fileName: fileName,
      sourceSupplierId: sourceSupplierId,
      sourceSupplierName: sourceSupplierName,
      sourceSupplierWebsite: sourceSupplierWebsite,
    );
    parsedData = prepared.display;

    if (!mounted) return;
    setState(() {
      _baseParsedData = prepared.base;
      _parsedData = parsedData;
      _ocrSupplier = prepared.supplier;
      _ocrSupplierName = prepared.supplier?.name;
      _supplierIdForNewProducts = prepared.supplier?.id;
      _isProcessing = false;
    });
    if (!widget.showPreview) {
      await _handleUseParsedData(parsedData);
    }
  }

  void _handleInvoiceFileProcessingError(Object error) {
    debugPrint('❌ Invoice file processing error: $error');
    final errorMsg = _formatError(error);

    setState(() {
      _errorMessage = errorMsg;
      _isProcessing = false;
      _isDraggingInvoiceFile = false;
    });

    if (widget.onError != null) {
      widget.onError!(errorMsg);
    }
  }

  String _dropFileName(DropItem file) {
    final name = file.name.trim();
    if (name.isNotEmpty) return name;
    return file.path.split(RegExp(r'[/\\]')).last;
  }

  String _fileExtension(String fileName, {String? fallback}) {
    final fallbackText = fallback?.trim().toLowerCase();
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex >= 0 && dotIndex < fileName.length - 1) {
      return fileName.substring(dotIndex + 1).toLowerCase();
    }
    return fallbackText ?? '';
  }

  bool _isSupportedInvoiceFileExtension(String extension) {
    return _supportedInvoiceFileExtensions.contains(extension);
  }

  bool _isSupportedInvoiceImageExtension(String extension) {
    return _invoiceImageFileExtensions.contains(extension);
  }

  String _fileNameWithExtension(String fileName, String extension) {
    if (extension.isEmpty || _fileExtension(fileName).isNotEmpty) {
      return fileName;
    }
    return '$fileName.$extension';
  }

  String _inferInvoiceFileExtension(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'pdf';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return 'bmp';
    }
    if (bytes.length >= 4 &&
        ((bytes[0] == 0x49 &&
                bytes[1] == 0x49 &&
                bytes[2] == 0x2A &&
                bytes[3] == 0x00) ||
            (bytes[0] == 0x4D &&
                bytes[1] == 0x4D &&
                bytes[2] == 0x00 &&
                bytes[3] == 0x2A))) {
      return 'tiff';
    }
    return '';
  }

  Future<Uint8List> _readPickedFileBytes(PlatformFile file) async {
    if (file.bytes != null) return file.bytes!;
    if (file.path != null && !kIsWeb) {
      return File(file.path!).readAsBytes();
    }
    throw Exception('No se pudo acceder al archivo seleccionado');
  }

  ParsedInvoice _parseAliExpressJsonFile(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw Exception('El JSON de AliExpress no tiene formato de factura');
    }
    return _parseAliExpressInvoiceMap(Map<String, dynamic>.from(decoded));
  }

  ParsedInvoice _parseAliExpressHtmlFile(Uint8List bytes) {
    final html = utf8.decode(bytes, allowMalformed: true);
    final jsonScript = RegExp(
      '<script[^>]+type=["\\\']application/json["\\\'][^>]+id=["\\\']aliexpress-invoice-data["\\\'][^>]*>(.*?)</script>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html);
    if (jsonScript != null) {
      final decoded =
          jsonDecode(_decodeHtmlEntities(jsonScript.group(1) ?? ''));
      if (decoded is Map) {
        return _parseAliExpressInvoiceMap(Map<String, dynamic>.from(decoded));
      }
    }

    return _parseAliExpressInvoiceHtml(html);
  }

  ParsedInvoice _parseAliExpressInvoiceMap(Map<String, dynamic> invoice) {
    DateTime? parseDate(dynamic value) {
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    double? parseNumber(dynamic value) {
      if (value is num) return value.toDouble();
      final text = value?.toString().trim();
      if (text == null || text.isEmpty) return null;
      return double.tryParse(text.replaceAll('.', '').replaceAll(',', '.')) ??
          double.tryParse(text);
    }

    final rawItems =
        (invoice['items'] as List? ?? const []).whereType<Map>().toList();
    var items = rawItems.map((raw) {
      final item = Map<String, dynamic>.from(raw);
      final description = item['description']?.toString().trim();
      return ParsedLineItem(
        description: description == null || description.isEmpty
            ? 'AliExpress item'
            : description,
        sku: item['sku']?.toString().trim(),
        rawRowText: [
          item['description'],
          item['originalDescription'] == null
              ? null
              : 'ORIGINAL_TITLE: ${item['originalDescription']}',
          (item['variant']?.toString().trim().isNotEmpty ?? false)
              ? 'VARIANT: ${item['variant'].toString().trim()}'
              : null,
          (item['variantKey']?.toString().trim().isNotEmpty ?? false)
              ? 'VARIANT_KEY: ${item['variantKey'].toString().trim()}'
              : null,
          item['aiCleaned'] == true ? 'AI_CLEANED: true' : null,
          (item['aiCategory'] is String &&
                  (item['aiCategory'] as String).trim().isNotEmpty)
              ? 'AI_CATEGORY: ${(item['aiCategory'] as String).trim()}'
              : null,
          (item['aiBrand'] is String &&
                  (item['aiBrand'] as String).trim().isNotEmpty)
              ? 'AI_BRAND: ${(item['aiBrand'] as String).trim()}'
              : null,
          (item['aiModel'] is String &&
                  (item['aiModel'] as String).trim().isNotEmpty)
              ? 'AI_MODEL: ${(item['aiModel'] as String).trim()}'
              : null,
          (item['itemId']?.toString().trim().isNotEmpty ?? false)
              ? 'ITEM_ID: ${item['itemId'].toString().trim()}'
              : null,
          item['productUrl'],
          item['imageUrl'] == null ? null : 'IMAGE_URL: ${item['imageUrl']}',
        ].whereType<Object>().join('\n'),
        imageUrl: item['imageUrl']?.toString().trim(),
        productUrl: item['productUrl']?.toString().trim(),
        quantity: parseNumber(item['quantity']),
        unitPrice: parseNumber(item['unitPrice']),
        total: parseNumber(item['total']),
      );
    }).toList(growable: false);

    items = _repairSingleMissingAliExpressLineCost(
      items,
      subtotal: parseNumber(invoice['subtotal']),
      total: parseNumber(invoice['total']),
    );

    final supplierName = invoice['supplierName']?.toString().trim();
    return ParsedInvoice(
      invoiceNumber: invoice['orderNumber']?.toString().trim(),
      date: parseDate(invoice['orderDate']),
      total: parseNumber(invoice['total']),
      supplierName: supplierName == null || supplierName.isEmpty
          ? 'AliExpress Marketplace'
          : supplierName,
      lineItems: items,
      rawText: jsonEncode(invoice),
    );
  }

  List<ParsedLineItem> _repairSingleMissingAliExpressLineCost(
    List<ParsedLineItem> items, {
    double? subtotal,
    double? total,
  }) {
    final missingIndexes = <int>[];
    var knownTotal = 0.0;

    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final lineTotal = item.total;
      final unitPrice = item.unitPrice;
      final quantity = item.quantity ?? 1;

      if (lineTotal != null && lineTotal > 0) {
        knownTotal += lineTotal;
      } else if (unitPrice != null && unitPrice > 0 && quantity > 0) {
        knownTotal += unitPrice * quantity;
      } else {
        missingIndexes.add(index);
      }
    }

    if (missingIndexes.length != 1) return items;

    final invoiceLineBasis = (subtotal != null && subtotal > knownTotal)
        ? subtotal
        : (total != null && total > knownTotal ? total : null);
    if (invoiceLineBasis == null) return items;

    final missingTotal = invoiceLineBasis - knownTotal;
    if (missingTotal <= 0) return items;

    final missingIndex = missingIndexes.single;
    final item = items[missingIndex];
    final quantity = (item.quantity ?? 1) > 0 ? item.quantity ?? 1 : 1.0;
    final repaired = item.copyWith(
      unitPrice: missingTotal / quantity,
      total: missingTotal,
      rawRowText: _mergeRawRowText(
        item.rawRowText,
        'REPAIRED_COST_FROM_INVOICE_RESIDUAL: ${missingTotal.toStringAsFixed(0)}',
      ),
    );

    final updated = List<ParsedLineItem>.from(items);
    updated[missingIndex] = repaired;
    return updated;
  }

  ParsedInvoice _parseAliExpressInvoiceHtml(String html) {
    String? firstText(RegExp pattern) {
      final value =
          _decodeHtmlEntities(pattern.firstMatch(html)?.group(1) ?? '').trim();
      return value.isEmpty ? null : value;
    }

    double? parseMoney(String? value) {
      if (value == null || value.trim().isEmpty) return null;
      final numeric = value.replaceAll(RegExp(r'[^0-9,\.]'), '').trim();
      if (numeric.isEmpty) return null;
      return double.tryParse(
              numeric.replaceAll('.', '').replaceAll(',', '.')) ??
          double.tryParse(numeric);
    }

    final itemRows = RegExp(
      r'<tr>\s*<td class="index-cell">.*?</tr>',
      caseSensitive: false,
      dotAll: true,
    )
        .allMatches(html)
        .map((match) => match.group(0) ?? '')
        .where((row) => row.contains('article-cell'));

    final items = <ParsedLineItem>[];
    for (final row in itemRows) {
      final imageUrl = RegExp(
        r'<img[^>]+class="item-image"[^>]+src="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(row)?.group(1);
      final description = _firstTextIn(
        row,
        RegExp(r'<strong>(.*?)</strong>', caseSensitive: false, dotAll: true),
      );
      final sku = _firstTextIn(
        row,
        RegExp(r'SKU:\s*([^<\n]+)', caseSensitive: false),
      );
      final originalDescription = _firstTextIn(
        row,
        RegExp(r'ORIGINAL_TITLE:\s*([^<]+)', caseSensitive: false),
      );
      final productUrl =
          RegExp(r'PRODUCT_URL:\s*(https?://[^<\s]+)', caseSensitive: false)
              .firstMatch(row)
              ?.group(1);
      final cells = RegExp(
        r'<td[^>]*class="numeric"[^>]*>(.*?)</td>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(row).map((cell) => _stripHtml(cell.group(1) ?? '')).toList();

      if ((description ?? '').isEmpty) continue;
      items.add(ParsedLineItem(
        description: description!,
        sku: sku,
        rawRowText: [
          description,
          originalDescription == null
              ? null
              : 'ORIGINAL_TITLE: $originalDescription',
          productUrl,
          imageUrl == null ? null : 'IMAGE_URL: $imageUrl',
        ].whereType<Object>().join('\n'),
        imageUrl: imageUrl == null ? null : _decodeHtmlEntities(imageUrl),
        productUrl: productUrl == null ? null : _decodeHtmlEntities(productUrl),
        quantity: cells.isNotEmpty ? parseMoney(cells[0]) : null,
        unitPrice: cells.length > 1 ? parseMoney(cells[1]) : null,
        total: cells.length > 2 ? parseMoney(cells[2]) : null,
      ));
    }

    return ParsedInvoice(
      invoiceNumber: firstText(RegExp(
        r'<strong>#\s*([^<]+)</strong>',
        caseSensitive: false,
        dotAll: true,
      )),
      supplierName: 'AliExpress Marketplace',
      lineItems: items,
      rawText: _stripHtml(html),
    );
  }

  ParsedInvoice _mergeLineItemMedia(
    ParsedInvoice primary,
    ParsedInvoice? mediaSource,
  ) {
    if (mediaSource == null || mediaSource.lineItems.isEmpty) return primary;

    final updatedItems = <ParsedLineItem>[];
    var changed = false;

    for (var index = 0; index < primary.lineItems.length; index++) {
      final item = primary.lineItems[index];
      final source = index < mediaSource.lineItems.length
          ? mediaSource.lineItems[index]
          : _matchMediaLineItem(item, mediaSource.lineItems);
      if (source == null) {
        updatedItems.add(item);
        continue;
      }

      final imageUrl = _firstNonEmpty(item.imageUrl, source.imageUrl);
      final productUrl = _firstNonEmpty(item.productUrl, source.productUrl);
      final rawRowText = _mergeRawRowText(item.rawRowText, source.rawRowText);
      final itemChanged = imageUrl != item.imageUrl ||
          productUrl != item.productUrl ||
          rawRowText != item.rawRowText;

      updatedItems.add(itemChanged
          ? item.copyWith(
              imageUrl: imageUrl,
              productUrl: productUrl,
              rawRowText: rawRowText,
            )
          : item);
      changed = changed || itemChanged;
    }

    if (!changed) return primary;
    return primary.copyWith(
      lineItems: updatedItems,
      rawText: _mergeRawRowText(primary.rawText, mediaSource.rawText),
    );
  }

  ParsedLineItem? _matchMediaLineItem(
    ParsedLineItem item,
    List<ParsedLineItem> sources,
  ) {
    final sku = item.sku?.trim().toLowerCase();
    final itemIds = _extractAliExpressItemIds(
      '${item.description}\n${item.rawRowText ?? ''}\n${item.productUrl ?? ''}',
    );
    for (final source in sources) {
      final sourceSku = source.sku?.trim().toLowerCase();
      if (sku != null && sku.isNotEmpty && sourceSku == sku) return source;
      final sourceIds = _extractAliExpressItemIds(
        '${source.description}\n${source.rawRowText ?? ''}\n${source.productUrl ?? ''}',
      );
      if (itemIds.intersection(sourceIds).isNotEmpty) return source;
    }
    return null;
  }

  Set<String> _extractAliExpressItemIds(String value) {
    final ids = <String>{};
    final patterns = [
      RegExp(r'item\s*id\s*:?\s*(\d{8,})', caseSensitive: false),
      RegExp(r'itemId=(\d{8,})', caseSensitive: false),
      RegExp(r'/item/(\d{8,})', caseSensitive: false),
      RegExp(r'productId=(\d{8,})', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(value)) {
        final id = match.group(1);
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  String? _firstNonEmpty(String? preferred, String? fallback) {
    final preferredText = preferred?.trim();
    if (preferredText != null && preferredText.isNotEmpty) return preferredText;
    final fallbackText = fallback?.trim();
    if (fallbackText != null && fallbackText.isNotEmpty) return fallbackText;
    return null;
  }

  String? _mergeRawRowText(String? first, String? second) {
    final firstText = first?.trim();
    final secondText = second?.trim();
    if (firstText == null || firstText.isEmpty) {
      return secondText == null || secondText.isEmpty ? null : secondText;
    }
    if (secondText == null || secondText.isEmpty) return firstText;
    if (firstText.contains(secondText)) return firstText;
    if (secondText.contains(firstText)) return secondText;
    return '$firstText\n$secondText';
  }

  String? _firstTextIn(String html, RegExp pattern) {
    final value = pattern.firstMatch(html)?.group(1);
    if (value == null) return null;
    final decoded = _decodeHtmlEntities(_stripHtml(value)).trim();
    return decoded.isEmpty ? null : decoded;
  }

  String _stripHtml(String value) {
    return _decodeHtmlEntities(value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim());
  }

  String _decodeHtmlEntities(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  /// Process document bytes with Veryfi cloud OCR
  Future<ParsedInvoice> _processWithVeryfi(
      Uint8List bytes, String filename) async {
    debugPrint('☁️ Processing with Veryfi: $filename');

    final veryfi = VeryfiProxyService();
    final response = await veryfi.parseInvoiceFromBytes(bytes, filename);
    final parsedData = VeryfiAdapter.toParsedInvoice(response);
    return parsedData;
  }

  /// Verify parsed line items against the product database.
  /// Returns a new ParsedInvoice with verification status on each line item.
  ///
  /// Search priority:
  /// 1. By SKU (exact match)
  /// 2. By product name (fuzzy search fallback)
  Future<ParsedInvoice> _verifyProductsInDatabase(
    ParsedInvoice invoice, {
    String? supplierId,
  }) async {
    debugPrint(
        '🔍 Verifying ${invoice.lineItems.length} products in database...');

    final verifiedItems = <ParsedLineItem>[];

    for (final item in invoice.lineItems) {
      final verifiedItem = await _verifySingleProduct(
        item,
        supplierId: supplierId,
      );
      verifiedItems.add(verifiedItem);
    }

    debugPrint(
        '🔍 Verification complete: ${verifiedItems.where((i) => i.existsInDatabase == true).length}/${verifiedItems.length} found');

    return ParsedInvoice(
      rut: invoice.rut,
      invoiceNumber: invoice.invoiceNumber,
      date: invoice.date,
      total: invoice.total,
      supplierName: invoice.supplierName,
      lineItems: verifiedItems,
      rawText: invoice.rawText,
    );
  }

  /// Format error message for display
  String _formatError(dynamic e) {
    final errorStr = e.toString();

    if (errorStr.contains('escaneado')) {
      return errorStr;
    }
    if (errorStr.contains('Veryfi proxy error: OCR server not configured')) {
      return 'El OCR en la nube no está configurado en el servidor.\n\n'
          'Configura los secrets de Veryfi en Supabase Edge Functions.';
    }
    if (errorStr.contains('Veryfi proxy error: Missing authentication')) {
      return 'Tu sesión no es válida para usar OCR en la nube.\n\n'
          'Inicia sesión nuevamente e inténtalo otra vez.';
    }
    if (errorStr.contains('Veryfi proxy error: Veryfi API error: 401')) {
      return 'Error de autenticación del servidor OCR con Veryfi.\n\n'
          'Revisa los secrets configurados en Supabase.';
    }
    if (errorStr.contains('Veryfi proxy error: Veryfi API error: 403')) {
      return 'Veryfi rechazó la solicitud desde el servidor OCR.\n\n'
          'Tu cuenta puede haber excedido el límite de documentos.';
    }
    if (errorStr.contains('Veryfi proxy error')) {
      return 'Error del OCR en la nube: $errorStr';
    }
    if (errorStr.contains('Failed to parse invoice JSON') ||
        errorStr.contains('Invalid response from OCR server')) {
      return 'El servidor OCR devolvió una respuesta inválida.';
    }
    if (errorStr.contains('SocketException') ||
        errorStr.contains('ClientException')) {
      return 'Error de conexión.\n\n'
          'Verifica tu conexión a internet e intenta nuevamente.';
    }

    return 'Error al procesar: $e';
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _bulkCreateHorizontalScrollController.dispose();
    for (final entry in _newProductEntries) {
      entry.dispose();
    }
    _newProductEntries.clear();
    for (var controller in _skuControllers.values) {
      controller.dispose();
    }
    _skuControllers.clear();
    // Note: Don't dispose OCRService here (it's a singleton)
    super.dispose();
  }
}

/// Type of document to scan
enum OCRDocumentType {
  invoice, // Factura (extracts full invoice data)
  receipt, // Boleta/Recibo (simpler format)
}

class _PreparedOcrInvoice {
  const _PreparedOcrInvoice({
    required this.base,
    required this.display,
    required this.supplier,
  });

  final ParsedInvoice base;
  final ParsedInvoice display;
  final shared_supplier.Supplier? supplier;
}

/// Entry for a new product to be created from OCR
class _NewProductEntry {
  final ParsedLineItem originalItem;
  final String supplierCode;
  final bool requiresDuplicateReview;
  bool isSelected;
  final TextEditingController nameController;
  final TextEditingController skuController;
  final TextEditingController costController;
  final TextEditingController priceController;
  Category? selectedCategory;
  ProductBrand? selectedBrand;
  String? imageUrl;
  String? imageUrlOptimized;
  Uint8List? imageBytes;
  String? imageFileName;
  bool isUploadingImage = false;
  bool isHoveringImage = false;
  bool isWorkshopConsumable = false;
  bool isCheckingSimilar = false;
  bool isLinkingExisting = false;
  bool hasReservedAliExpressSku = false;
  List<ProductDuplicateCandidate> similarCandidates = [];
  OcrProductResolutionState resolutionState;
  String? resolutionError;
  String? creationError;
  int resolutionRevision = 0;

  /// AI-cleanup state for AliExpress (and other noisy supplier) titles.
  /// When true, the row name field is being rewritten by the AI cleaner.
  bool isAICleaningName = false;

  /// Set to `true` after the AI cleaner successfully replaced the name.
  /// Drives the small "✨ Limpio por IA" badge in the row UI.
  bool nameWasAICleaned = false;

  /// Set to `true` once the user has manually edited the name field. After
  /// this, the AI cleaner must NOT overwrite the user's edit.
  bool nameUserEdited = false;

  /// AI-suggested category name (e.g. "Postizas"). Used to seed the
  /// duplicate-matcher probe so the family detector classifies the row
  /// correctly even before the user picks a category from the dropdown.
  String? aiSuggestedCategoryName;

  /// AI-detected brand visible in the photo (e.g. "ZTTO", "Shimano"). Used
  /// to seed the duplicate-matcher probe.
  String? aiSuggestedBrandName;

  /// Model/part number returned by the AI cleaner (for example RT56). Model
  /// identifiers are normalized by the duplicate matcher before comparison.
  String? aiSuggestedModel;

  /// Original noisy supplier title preserved as the description fallback so
  /// the long AliExpress text doesn't get lost when the name is cleaned.
  String? originalNoisyTitle;

  /// True when the cost in [costController] already includes 19% IVA (e.g.
  /// AliExpress unit prices, where shipping/tax/discount have been allocated
  /// into each unit). Drives the suggested-price formula:
  ///   - tax-included cost: price = cost * 2 (IVA already inside the cost)
  ///   - tax-excluded cost: price = cost * 1.19 * 2 (Net + IVA, then x2)
  bool costIncludesIva;

  _NewProductEntry({
    required this.originalItem,
    this.isSelected = true,
    String? initialName,
    String? initialSku,
    this.selectedCategory,
    this.costIncludesIva = false,
    this.requiresDuplicateReview = false,
  })  : supplierCode = _supplierCodeForItem(originalItem),
        resolutionState = requiresDuplicateReview
            ? OcrProductResolutionState.unsearched
            : OcrProductResolutionState.newProduct,
        nameController = TextEditingController(
            text: initialName ?? _cleanDescription(originalItem.description)),
        skuController =
            TextEditingController(text: initialSku ?? originalItem.sku),
        costController =
            TextEditingController(text: _calculateDefaultCost(originalItem)),
        priceController = TextEditingController(
            text: _calculateDefaultPrice(originalItem,
                costIncludesIva: costIncludesIva)) {
    final sourceImageUrl = originalItem.imageUrl?.trim();
    if (sourceImageUrl != null && sourceImageUrl.isNotEmpty) {
      imageUrl = sourceImageUrl;
      imageUrlOptimized = sourceImageUrl;
      imageFileName = _imageFileNameFromUrl(sourceImageUrl);
    }
    originalNoisyTitle = nameController.text;
    // Track manual edits so the AI cleaner never overwrites the user.
    nameController.addListener(() {
      if (_suppressNameEditTracking) return;
      nameUserEdited = true;
      invalidateDuplicateResolution();
    });
  }

  void invalidateDuplicateResolution() {
    if (!requiresDuplicateReview) return;
    resolutionRevision++;
    isCheckingSimilar = false;
    similarCandidates = [];
    resolutionError = null;
    resolutionState = OcrProductResolutionState.unsearched;
  }

  void markSearching() {
    resolutionRevision++;
    isCheckingSimilar = true;
    resolutionError = null;
    resolutionState = OcrProductResolutionState.searching;
  }

  void markNeedsReview(List<ProductDuplicateCandidate> candidates) {
    isCheckingSimilar = false;
    similarCandidates = candidates;
    resolutionError = null;
    resolutionState = OcrProductResolutionState.reviewRequired;
  }

  void markNoCandidates() {
    isCheckingSimilar = false;
    similarCandidates = [];
    resolutionError = null;
    resolutionState = OcrProductResolutionState.noCandidates;
  }

  void markNewProduct() {
    isCheckingSimilar = false;
    similarCandidates = [];
    resolutionError = null;
    resolutionState = OcrProductResolutionState.newProduct;
  }

  void markResolutionFailed(Object error) {
    isCheckingSimilar = false;
    resolutionError = error.toString();
    resolutionState = OcrProductResolutionState.failed;
  }

  /// Set by the AI cleaner around `nameController.text = ...` so the
  /// controller listener does NOT mark the value as a user edit.
  bool _suppressNameEditTracking = false;

  /// Replace the row name with an AI-cleaned title without tripping the
  /// "user edited" guard. Returns false if the user has already edited the
  /// name, in which case the AI suggestion is dropped silently.
  bool applyAICleanedName(String cleanedName) {
    if (nameUserEdited) return false;
    _suppressNameEditTracking = true;
    nameController.text = cleanedName;
    _suppressNameEditTracking = false;
    nameWasAICleaned = true;
    return true;
  }

  static String? _imageFileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final segment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : 'aliexpress-product-image.jpg';
    final clean = segment.split('?').first.trim();
    if (clean.isEmpty) return 'aliexpress-product-image.jpg';
    return clean.contains('.') ? clean : '$clean.jpg';
  }

  static String _supplierCodeForItem(ParsedLineItem item) {
    final identityText = [
      item.productUrl,
      item.rawRowText,
    ].whereType<String>().join('\n');
    for (final pattern in [
      RegExp(r'ITEM_ID:\s*(\d{8,})', caseSensitive: false),
      RegExp(r'/item/(\d{8,})', caseSensitive: false),
      RegExp(r'(?:itemId|productId)=(\d{8,})', caseSensitive: false),
    ]) {
      final match = pattern.firstMatch(identityText)?.group(1)?.trim();
      if (match != null && match.isNotEmpty) return match;
    }
    return item.sku?.trim() ?? '';
  }

  static String _calculateDefaultCost(ParsedLineItem item) {
    final qty = item.quantity ?? 1;
    if (item.total != null && item.total! > 0 && qty > 0) {
      final effectiveCost = item.total! / qty;
      final unitPrice = item.unitPrice;

      if (unitPrice == null || unitPrice <= 0) {
        return effectiveCost.toStringAsFixed(0);
      }

      final grossAmount = qty * unitPrice;
      if ((grossAmount - item.total!).abs() > 1) {
        return effectiveCost.toStringAsFixed(0);
      }
    }

    if (item.unitPrice != null && item.unitPrice! > 0) {
      return item.unitPrice!.toStringAsFixed(0);
    }
    if (item.total != null && item.total! > 0) {
      final calculatedCost = item.total! / (qty > 0 ? qty : 1);
      return calculatedCost.toStringAsFixed(0);
    }
    return '';
  }

  /// Calculate default sale price (rounded to nearest 100).
  ///
  /// When [costIncludesIva] is true, the cost already contains IVA (e.g.
  /// AliExpress allocates tax into each unit), so the suggested price is
  /// `cost * 2` (a clean 100% margin over the all-in landed cost).
  ///
  /// When [costIncludesIva] is false, the cost is a Net (pre-tax) value, so
  /// IVA must be added before the markup: `cost * 1.19 * 2`.
  static String _calculateDefaultPrice(
    ParsedLineItem item, {
    bool costIncludesIva = false,
  }) {
    final rawCost = _calculateDefaultCost(item);
    final cost = double.tryParse(rawCost.replaceAll(',', '.')) ?? 0;
    return _suggestedPriceFromCost(cost, costIncludesIva: costIncludesIva);
  }

  /// Shared formula used both for first render and live recompute when the
  /// user toggles the "costs already include IVA" switch in the dialog.
  static String _suggestedPriceFromCost(
    double cost, {
    bool costIncludesIva = false,
  }) {
    if (cost <= 0) return '';
    final base = costIncludesIva ? cost * 2 : cost * 1.19 * 2;
    final price = (base / 100).round() * 100;
    return price.toString();
  }

  /// Remove "SKU: xxx" suffix from description to avoid duplication
  static String _cleanDescription(String description) {
    // Remove "SKU: xxx" pattern from end of description (case insensitive)
    // Also handles newlines before SKU
    return description
        .replaceAll(RegExp(r'[\n\r]+SKU:\s*\S+', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*SKU:\s*\S+$', caseSensitive: false), '')
        .trim();
  }

  void dispose() {
    nameController.dispose();
    skuController.dispose();
    costController.dispose();
    priceController.dispose();
  }

  /// Get SKU from controller
  String get sku => skuController.text.trim();

  /// Get cost from controller (editable by the user)
  double get cost {
    return double.tryParse(costController.text.replaceAll(',', '.')) ?? 0;
  }

  /// Get entered price
  double? get price =>
      double.tryParse(priceController.text.replaceAll(',', '.'));

  double? get parsedCost =>
      double.tryParse(costController.text.replaceAll(',', '.'));

  /// Validate entry is complete
  bool get isValid =>
      sku.isNotEmpty &&
      nameController.text.isNotEmpty &&
      selectedCategory != null &&
      parsedCost != null &&
      parsedCost! >= 0 &&
      price != null &&
      price! > 0;

  bool get isReadyToCreate =>
      !requiresDuplicateReview ||
      resolutionState == OcrProductResolutionState.newProduct;
}

class _OCRRowDiagnostics {
  final bool isComplete;
  final bool isConsistent;
  final bool wasAutoAdjusted;
  final double? grossAmount;
  final double discountAmount;
  final double? displayedTotal;
  final double? computedTotal;
  final double? delta;
  final String? adjustmentSummary;

  const _OCRRowDiagnostics({
    required this.isComplete,
    required this.isConsistent,
    required this.wasAutoAdjusted,
    required this.grossAmount,
    required this.discountAmount,
    required this.displayedTotal,
    required this.computedTotal,
    required this.delta,
    required this.adjustmentSummary,
  });
}

class _OCRInvoiceDiagnostics {
  final int lineCount;
  final double rowTotal;
  final double? headerTotal;
  final double delta;
  final bool hasTotalMismatch;
  final int adjustedRowCount;
  final int inconsistentRowCount;
  final int incompleteRowCount;

  const _OCRInvoiceDiagnostics({
    required this.lineCount,
    required this.rowTotal,
    required this.headerTotal,
    required this.delta,
    required this.hasTotalMismatch,
    required this.adjustedRowCount,
    required this.inconsistentRowCount,
    required this.incompleteRowCount,
  });

  bool get shouldWarnBeforeApply =>
      hasTotalMismatch || inconsistentRowCount > 0 || incompleteRowCount > 0;
}
