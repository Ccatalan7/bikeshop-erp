import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:math' as math;

import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../services/ocr_service.dart';
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
import '../../modules/inventory/services/brand_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../modules/inventory/models/brand_models.dart' show ProductBrand;
import '../models/supplier_ocr_template.dart';
import '../services/image_service.dart';
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

  const OCRUploadWidget({
    super.key,
    required this.onComplete,
    this.onError,
    this.documentType = OCRDocumentType.invoice,
    this.showPreview = true,
    this.provider = OCRProvider.auto,
    this.supplierId,
    this.supplierName,
  });

  @override
  State<OCRUploadWidget> createState() => _OCRUploadWidgetState();
}

class _OCRUploadWidgetState extends State<OCRUploadWidget> {
  final ImagePicker _picker = ImagePicker();
  final OCRService _ocrService = OCRService();
  final InvoiceParserService _parserService = InvoiceParserService();
  final PDFParserService _pdfService = PDFParserService();

  bool _isProcessing = false;
  String? _errorMessage;
  ParsedInvoice? _parsedData;
  ParsedInvoice? _baseParsedData;

  // Determined at runtime based on config
  bool _useVeryfi = false;
  bool _veryfiAvailable = false;
  bool _initialized = false;

  // Bulk product creation state
  bool _showBulkCreate = false;
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
      debugPrint(
          '🔍 OCR initialized: useVeryfi=$_useVeryfi, veryfiAvailable=$_veryfiAvailable');
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        Text(
          widget.documentType == OCRDocumentType.invoice
              ? 'Escanear Factura'
              : 'Escanear Boleta/Recibo',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),

        // Provider indicator
        if (_initialized)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _useVeryfi ? Colors.purple.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    _useVeryfi ? Colors.purple.shade200 : Colors.blue.shade200,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _useVeryfi ? Icons.cloud : Icons.phone_android,
                  size: 16,
                  color: _useVeryfi ? Colors.purple : Colors.blue,
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
          'Toma una foto o selecciona una imagen para extraer los datos automáticamente',
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
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
              onPressed:
                  _isProcessing ? null : () => _pickImage(ImageSource.camera),
            ),
            // Gallery button
            _buildActionButton(
              icon: Icons.photo_library,
              label: 'Galería',
              onPressed:
                  _isProcessing ? null : () => _pickImage(ImageSource.gallery),
            ),
            // PDF button
            _buildActionButton(
              icon: Icons.picture_as_pdf,
              label: 'PDF',
              onPressed: _isProcessing ? null : _pickPDFFile,
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
    final supplierTemplateActive = _ocrSupplier?.ocrTemplate.enabled ?? false;

    return Column(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with Status and Provider
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.green),
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
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            // Provider Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _useVeryfi ? Colors.purple.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
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
                    _useVeryfi ? Icons.auto_awesome : Icons.phone_android,
                    size: 14,
                    color: _useVeryfi ? Colors.purple : Colors.blue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _useVeryfi ? 'Veryfi AI' : 'Local OCR',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _useVeryfi ? Colors.purple : Colors.blue,
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
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
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
                    const Icon(Icons.edit, size: 16, color: Colors.grey),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                          supplierTemplateActive
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
                          const Icon(Icons.edit, size: 16, color: Colors.grey),
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
                          const Icon(Icons.edit, size: 16, color: Colors.grey),
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
                      child: _buildCompactDiagnosticsStatus(invoiceDiagnostics),
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
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange.shade700),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No se detectaron productos individuales. Se importará solo el total.',
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          )
        else
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
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
                            .withOpacity(0.5),
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
                                    color: Colors.grey.shade700,
                                    fontSize: 12)),
                          ),
                          Expanded(
                            flex: _showStock
                                ? 8
                                : 10, // Give description most space
                            child: Text('Descripción',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                    fontSize: 12)),
                          ),
                          if (_showStock)
                            Expanded(
                              flex: 2,
                              child: Text('Stock',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                      fontSize: 12)),
                            ),
                          Expanded(
                            flex: 2,
                            child: Text('Cant.',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                    fontSize: 12)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('Precio',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                    fontSize: 12)),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('Dscto',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                    fontSize: 12)),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text('Total',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                    fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    // Scrollable Data Rows
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: data.lineItems.map((item) {
                            final rowDiagnostics = _getRowDiagnostics(item);
                            // Determine verification status
                            Widget statusIcon;
                            String tooltip;

                            if (item.sku == null || item.sku!.isEmpty) {
                              statusIcon = const Icon(
                                  Icons.remove_circle_outline,
                                  size: 18,
                                  color: Colors.grey);
                              tooltip = 'Sin código SKU';
                            } else if (item.existsInDatabase == true) {
                              statusIcon = const Icon(Icons.check_circle,
                                  size: 18, color: Colors.green);
                              tooltip =
                                  'Producto encontrado: ${item.matchedProductName ?? item.sku}';
                            } else {
                              statusIcon = const Icon(Icons.warning_amber,
                                  size: 18, color: Colors.orange);
                              tooltip = 'Producto nuevo - debe crearse';
                            }

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                              decoration: BoxDecoration(
                                  border: Border(
                                      bottom: BorderSide(
                                          color: Colors.grey.shade200))),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 32,
                                    child: Tooltip(
                                        message: tooltip, child: statusIcon),
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
                                                    color:
                                                        Colors.orange.shade300,
                                                    width: 0.5),
                                              )
                                            : InputBorder.none,
                                        filled: (item.sku == null ||
                                            item.sku!.isEmpty),
                                        fillColor: Colors.orange.shade50,
                                        hintStyle: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.orange.shade300),
                                      ),
                                      controller: _skuControllers.putIfAbsent(
                                          _parsedData!.lineItems.indexOf(item),
                                          () => TextEditingController(
                                              text: item.sku)),
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: item.existsInDatabase == true
                                            ? Colors.green.shade700
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
                                          item.currentStock?.toString() ?? '-',
                                          style: const TextStyle(
                                              fontSize: 13,
                                              color: Colors.blueGrey)),
                                    ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                        item.quantity?.toStringAsFixed(0) ??
                                            '1',
                                        style: const TextStyle(fontSize: 13)),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                        item.unitPrice != null
                                            ? '\$${item.unitPrice!.toStringAsFixed(0)}'
                                            : '-',
                                        style: const TextStyle(fontSize: 13)),
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
                                            color: Colors.orange.shade800)),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (!rowDiagnostics.isComplete ||
                                            !rowDiagnostics.isConsistent ||
                                            rowDiagnostics.wasAutoAdjusted)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(right: 6),
                                            child: Tooltip(
                                              message:
                                                  _buildRowDiagnosticsTooltip(
                                                item,
                                                rowDiagnostics,
                                              ),
                                              child: Icon(
                                                !rowDiagnostics.isComplete ||
                                                        !rowDiagnostics
                                                            .isConsistent
                                                    ? Icons.error_outline
                                                    : Icons.auto_fix_high,
                                                size: 16,
                                                color: !rowDiagnostics
                                                            .isComplete ||
                                                        !rowDiagnostics
                                                            .isConsistent
                                                    ? Colors.orange.shade700
                                                    : Colors.blue.shade700,
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
                                            color: !rowDiagnostics.isComplete ||
                                                    !rowDiagnostics.isConsistent
                                                ? Colors.orange.shade800
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
              onPressed: _openBulkCreateScreen,
              icon: const Icon(Icons.add_circle_outline, color: Colors.orange),
              label: Text(
                'Crear ${data.lineItems.where((item) => item.existsInDatabase == false).length} Productos Nuevos',
                style: const TextStyle(color: Colors.orange),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.orange),
              ),
            ),
          ),

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
                onPressed: () => _handleUseParsedData(data),
                icon: const Icon(Icons.check),
                label: const Text('Usar Datos'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ],
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
      final verifiedItem =
          await _verifySingleProduct(item.copyWith(sku: newSku.trim()));

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
            child: const Text('Ingresar otro SKU',
                style: TextStyle(color: Colors.red)),
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
  Future<ParsedLineItem> _verifySingleProduct(ParsedLineItem item) async {
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
        matchedProduct =
            await inventoryService.getProductBySupplierCode(cleanSku);
      } catch (e) {
        debugPrint('   ❌ Error looking up Supplier Code $cleanSku: $e');
      }
    }

    // PRIORITY 3: Fall back to searching by name (EXACT MATCH ONLY)
    if (matchedProduct == null && item.description.isNotEmpty) {
      try {
        final normalizedDescription = item.description.trim().toLowerCase();
        final allProducts = await inventoryService.getProducts();

        for (final product in allProducts) {
          final normalizedProductName = product.name.trim().toLowerCase();
          if (normalizedProductName == normalizedDescription) {
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
      return item.copyWith(existsInDatabase: false);
    }
  }

  /// Open the bulk product creation screen
  Future<void> _uploadImage(
      _NewProductEntry entry, Uint8List bytes, String fileName) async {
    setState(() => entry.isUploadingImage = true);
    try {
      final result = await ImageService.uploadProductImageWithOptimization(
          bytes: bytes, fileName: fileName);
      setState(() {
        entry.imageUrl = result.optimizedUrl ?? result.originalUrl;
        entry.imageUrlOptimized = result.optimizedUrl;
      });
    } catch (e) {
      debugPrint('Error uploading image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al subir imagen: $e')),
      );
    } finally {
      setState(() => entry.isUploadingImage = false);
    }
  }

  Future<void> _openBulkCreateScreen() async {
    if (_parsedData == null) return;

    // Get new products (all unrecognized items)
    final newProducts = _parsedData!.lineItems
        .where((item) => item.existsInDatabase == false)
        .toList();

    if (newProducts.isEmpty) return;

    // Load categories and brands
    try {
      final dbService = DatabaseService();
      final tenantService = TenantService();
      final categoryService = CategoryService(dbService, tenantService);
      final brandService = BrandService(dbService);
      _categories = await categoryService.getCategories();
      _brands = await brandService.getBrands(activeOnly: true);
    } catch (e) {
      debugPrint('Failed to load categories/brands: $e');
    }

    // Create entries for each new product
    _newProductEntries = newProducts
        .map((item) => _NewProductEntry(
              originalItem: item,
              isSelected: true,
              selectedCategory: null, // No default - user must choose
            ))
        .toList();

    setState(() => _showBulkCreate = true);
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
                              searchQuery = value.toLowerCase();
                              filteredSuppliers = allSuppliers
                                  .where((s) =>
                                      s.name
                                          .toLowerCase()
                                          .contains(searchQuery) ||
                                      (s.rut != null &&
                                          s.rut!
                                              .toLowerCase()
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
                                      title: Text(supplier.name),
                                      subtitle: supplier.rut != null
                                          ? Text(supplier.rut!)
                                          : null,
                                      onTap: () {
                                        this.setState(() {
                                          _ocrSupplier = supplier;
                                          _ocrSupplierName = supplier.name;
                                          _supplierIdForNewProducts =
                                              supplier.id;

                                          // Update parsed data to reflect manually selected supplier
                                          if (_baseParsedData != null) {
                                            _parsedData =
                                                _applySupplierTemplate(
                                              _baseParsedData!,
                                              supplier,
                                            );
                                          }
                                        });
                                        Navigator.pop(context);
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

  /// Build the bulk product creation screen
  Widget _buildBulkCreateScreen() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double baseWChk = 40;
        const double baseWImg = 58;
        const double baseWSku = 130;
        const double baseWName = 260;
        const double baseWCost = 110;
        const double baseWPrice = 110;
        const double baseWCat = 170;
        const double baseWBrand = 160;
        const double baseWTaller = 72;
        const double gap = 8;
        const double hPad = 12;
        const double minTableInnerWidth = hPad * 2 +
            baseWChk +
            baseWImg +
            baseWSku +
            baseWName +
            baseWCost +
            baseWPrice +
            baseWCat +
            baseWBrand +
            baseWTaller +
            gap * 7;

        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : minTableInnerWidth;
        final tableInnerWidth = math.max(minTableInnerWidth, availableWidth);
        final extraWidth = tableInnerWidth - minTableInnerWidth;

        final wChk = baseWChk;
        final wImg = baseWImg;
        final wSku = baseWSku + (extraWidth * 0.14);
        final wName = baseWName + (extraWidth * 0.42);
        final wCost = baseWCost;
        final wPrice = baseWPrice;
        final wCat = baseWCat + (extraWidth * 0.22);
        final wBrand = baseWBrand + (extraWidth * 0.22);
        final wTaller = baseWTaller;

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

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.add_circle, color: Colors.orange, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Crear Productos Nuevos',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            Text(
                              '${_newProductEntries.where((e) => e.isSelected).length} de ${_newProductEntries.length} seleccionados',
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey.shade600),
                            ),
                            Text(' • ',
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey.shade400)),
                            Icon(
                              (_ocrSupplierName ?? widget.supplierName) != null
                                  ? Icons.local_shipping_outlined
                                  : Icons.warning_amber_rounded,
                              size: 14,
                              color:
                                  (_ocrSupplierName ?? widget.supplierName) !=
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
                                color:
                                    (_ocrSupplierName ?? widget.supplierName) !=
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
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Header ──────────────────────────────────────────────
                        Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: hPad),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(9)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(width: wChk), // checkbox placeholder
                              headerCell('Img', wImg),
                              const SizedBox(width: gap),
                              headerCell('SKU', wSku),
                              const SizedBox(width: gap),
                              headerCell('Nombre', wName),
                              const SizedBox(width: gap),
                              headerCell('Costo', wCost,
                                  align: TextAlign.center),
                              const SizedBox(width: gap),
                              headerCell('Precio', wPrice,
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
                        ...List.generate(_newProductEntries.length, (index) {
                          final entry = _newProductEntries[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: hPad, vertical: 6),
                            decoration: BoxDecoration(
                              color: entry.isSelected
                                  ? Colors.white
                                  : Colors.grey.shade50,
                              border: Border(
                                  top: BorderSide(color: Colors.grey.shade200)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Checkbox
                                SizedBox(
                                  width: wChk,
                                  child: Checkbox(
                                    value: entry.isSelected,
                                    onChanged: (v) => setState(
                                        () => entry.isSelected = v ?? false),
                                  ),
                                ),
                                // Image cell
                                SizedBox(
                                  width: wImg - gap,
                                  child: DropTarget(
                                    onDragDone: (d) async {
                                      if (d.files.isNotEmpty) {
                                        final f = d.files.first;
                                        _uploadImage(entry,
                                            await f.readAsBytes(), f.name);
                                      }
                                    },
                                    onDragEntered: (_) => setState(
                                        () => entry.isHoveringImage = true),
                                    onDragExited: (_) => setState(
                                        () => entry.isHoveringImage = false),
                                    child: MouseRegion(
                                      onEnter: (_) => setState(
                                          () => entry.isHoveringImage = true),
                                      onExit: (_) => setState(
                                          () => entry.isHoveringImage = false),
                                      child: Stack(children: [
                                        InkWell(
                                          onTap: () async {
                                            final r =
                                                await ImageService.pickImage();
                                            if (r != null)
                                              _uploadImage(
                                                  entry, r.bytes, r.name);
                                          },
                                          child: Container(
                                            width: 46,
                                            height: 46,
                                            decoration: BoxDecoration(
                                              color: entry.isHoveringImage
                                                  ? Colors.blue
                                                      .withOpacity(0.08)
                                                  : Colors.grey[100],
                                              border: Border.all(
                                                color: entry.isHoveringImage
                                                    ? Colors.blue
                                                    : Colors.grey[300]!,
                                                width: entry.isHoveringImage
                                                    ? 2
                                                    : 1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
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
                                                                .circular(4),
                                                        child: ImageService
                                                            .buildProductImage(
                                                          imageUrl:
                                                              entry.imageUrl,
                                                          size: 46,
                                                        ),
                                                      )
                                                    : const Icon(
                                                        Icons
                                                            .add_photo_alternate,
                                                        size: 18,
                                                        color: Colors.grey),
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
                                                entry.imageUrlOptimized = null;
                                              }),
                                              child: Container(
                                                width: 16,
                                                height: 16,
                                                decoration: const BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle),
                                                child: const Icon(Icons.close,
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
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      border: const OutlineInputBorder(),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                      errorText: entry.sku.isEmpty
                                          ? 'Requerido'
                                          : null,
                                      errorStyle: const TextStyle(fontSize: 10),
                                    ),
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: gap),
                                // Name
                                SizedBox(
                                  width: wName,
                                  child: TextField(
                                    controller: entry.nameController,
                                    enabled: entry.isSelected,
                                    onChanged: (_) => setState(() {}),
                                    minLines: 1,
                                    maxLines: 2,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                    ),
                                    style: const TextStyle(fontSize: 12),
                                  ),
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
                                          color: Colors.grey.shade400),
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
                                          color: Colors.grey.shade400),
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
                                    initialSelection: entry.selectedCategory,
                                    hintText: 'Categoría',
                                    textStyle: const TextStyle(fontSize: 12),
                                    inputDecorationTheme:
                                        const InputDecorationTheme(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                    ),
                                    enabled: entry.isSelected,
                                    enableFilter: true,
                                    requestFocusOnTap: true,
                                    dropdownMenuEntries: _categories
                                        .map((c) => DropdownMenuEntry<Category>(
                                            value: c, label: c.name))
                                        .toList(),
                                    onSelected: (v) {
                                      if (v != null)
                                        setState(
                                            () => entry.selectedCategory = v);
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
                                    textStyle: const TextStyle(fontSize: 12),
                                    inputDecorationTheme:
                                        const InputDecorationTheme(
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 8),
                                      border: OutlineInputBorder(),
                                    ),
                                    enabled: entry.isSelected,
                                    enableFilter: true,
                                    requestFocusOnTap: true,
                                    dropdownMenuEntries: _brands
                                        .map((b) =>
                                            DropdownMenuEntry<ProductBrand>(
                                                value: b, label: b.name))
                                        .toList(),
                                    onSelected: (v) {
                                      if (v != null)
                                        setState(() => entry.selectedBrand = v);
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
                                          value: entry.isWorkshopConsumable,
                                          onChanged: entry.isSelected
                                              ? (v) => setState(() => entry
                                                  .isWorkshopConsumable = v)
                                              : null,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
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

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
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
                      onPressed: _newProductEntries
                              .any((e) => e.isSelected && e.isValid)
                          ? _createBulkProducts
                          : null,
                      icon: _creatingProducts
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check),
                      label: Text(
                          _creatingProducts ? 'Creando...' : 'Crear Productos'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Create products from the bulk creation form
  Future<void> _createBulkProducts() async {
    final selectedEntries =
        _newProductEntries.where((e) => e.isSelected && e.isValid).toList();
    if (selectedEntries.isEmpty) return;

    setState(() => _creatingProducts = true);

    try {
      final dbService = DatabaseService();
      final tenantService = TenantService();
      final inventoryService =
          inv_service.InventoryService(dbService, tenantService);
      int created = 0;

      for (final entry in selectedEntries) {
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
          supplierCode: entry.sku, // Store OCR SKU as supplier code
          isActive: true,
          purchaseTreatment: entry.isWorkshopConsumable
              ? PurchaseTreatment.workshopConsumable
              : PurchaseTreatment.inventory,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          imageUrl: entry.imageUrl,
          imageUrlOptimized: entry.imageUrlOptimized,
        );

        try {
          await inventoryService.createProduct(product);
          created++;
          debugPrint('✅ Created product: ${product.name} (${product.sku})');
        } catch (e) {
          debugPrint('❌ Failed to create product ${product.sku}: $e');
        }
      }

      // Re-verify products after creation
      if (_parsedData != null && created > 0) {
        // Refresh shared inventory cache to ensure newly created products are found
        await Provider.of<InventoryService>(context, listen: false).refresh();

        final verifiedInvoice = await _verifyProductsInDatabase(_parsedData!);
        setState(() {
          _parsedData = verifiedInvoice;
          _showBulkCreate = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ $created producto(s) creado(s)'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }

      // Dispose controllers
      for (final entry in _newProductEntries) {
        entry.dispose();
      }
      _newProductEntries.clear();
    } catch (e) {
      debugPrint('Error creating products: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _creatingProducts = false);
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
                color: Colors.grey.shade600,
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

  /// Try to match OCR supplier string against database suppliers
  Future<shared_supplier.Supplier?> _matchSupplier(String rawName) async {
    try {
      final purchaseService = context.read<PurchaseService>();
      final suppliers = await purchaseService.getSuppliers();
      if (suppliers.isEmpty) return null;

      final normalizedRaw = rawName.toLowerCase().trim();

      // 1. Exact match
      try {
        return suppliers
            .firstWhere((s) => s.name.toLowerCase().trim() == normalizedRaw);
      } catch (_) {}

      // 2. Database name contains OCR name (e.g. DB: "Big Supplier Inc", OCR: "Supplier")
      try {
        return suppliers
            .firstWhere((s) => s.name.toLowerCase().contains(normalizedRaw));
      } catch (_) {}

      // 3. OCR name contains Database name (e.g. OCR: "Big Supplier Limitada", DB: "Big Supplier")
      // This solves the "DERMAN CICLISMO..." -> "Derman" case
      try {
        return suppliers.firstWhere(
            (s) => normalizedRaw.contains(s.name.toLowerCase().trim()));
      } catch (_) {}
    } catch (e) {
      debugPrint('Error matching supplier: $e');
    }
    return null;
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
                value: parser,
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
          backgroundColor: Colors.red,
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

      // Verify products against database
      parsedData = await _verifyProductsInDatabase(parsedData);
      ParsedInvoice baseParsedData = parsedData;

      String? matchedSupplierName = parsedData.supplierName;
      String? matchedSupplierId;
      shared_supplier.Supplier? matchedSupplier;

      if (parsedData.supplierName != null) {
        matchedSupplier = await _matchSupplier(parsedData.supplierName!);
        if (matchedSupplier != null) {
          matchedSupplierName = matchedSupplier.name;
          matchedSupplierId = matchedSupplier.id;
          parsedData = _applySupplierTemplate(parsedData, matchedSupplier);
          debugPrint('✅ OCR matched supplier: ${matchedSupplier.name}');
        } else {
          // If supplier not found in DB, clear it to avoid phantom suppliers
          // forcing user to select a valid one later
          matchedSupplierName = null;
          debugPrint('⚠️ Supplier not found in DB, clearing OCR result');
          baseParsedData = ParsedInvoice(
            rut: parsedData.rut,
            invoiceNumber: parsedData.invoiceNumber,
            date: parsedData.date,
            total: parsedData.total,
            supplierName: null, // Clear supplier name
            lineItems: parsedData.lineItems,
            rawText: parsedData.rawText,
          );
          parsedData = baseParsedData;
        }
      }

      setState(() {
        _baseParsedData = baseParsedData;
        _parsedData = parsedData;
        _ocrSupplier = matchedSupplier;
        _ocrSupplierName = matchedSupplierName;
        _supplierIdForNewProducts = matchedSupplierId;
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

  Future<void> _pickPDFFile() async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      // Pick PDF file (withData: true for web compatibility)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true, // Load bytes for web
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isProcessing = false);
        return;
      }

      final file = result.files.first;

      ParsedInvoice? parsedData;

      if (_useVeryfi) {
        // Use Veryfi for PDF
        Uint8List pdfBytes;
        if (file.bytes != null) {
          pdfBytes = file.bytes!;
        } else if (file.path != null && !kIsWeb) {
          pdfBytes = await File(file.path!).readAsBytes();
        } else {
          throw Exception('No se pudo acceder al archivo PDF');
        }

        parsedData = await _processWithVeryfi(pdfBytes, file.name);
      } else {
        // Local PDF processing
        if (file.bytes != null) {
          // Web platform - use bytes
          debugPrint('📄 PDF picked (web): ${file.name}');
          parsedData = await _pdfService.parseInvoiceFromBytes(file.bytes!,
              filename: file.name);
        } else if (file.path != null && !kIsWeb) {
          // Native platform - use path
          debugPrint('📄 PDF picked (native): ${file.path}');
          parsedData = await _pdfService.parseInvoiceFromPDF(file.path!);
        } else {
          throw Exception('No se pudo acceder al archivo PDF');
        }
      }

      if (parsedData == null) {
        throw Exception(
            'Este PDF parece ser escaneado (sin texto seleccionable).\n\n'
            'Por favor, usa la opción de Cámara o Galería para escanear el documento.');
      }

      debugPrint('📋 Parsed PDF data: $parsedData');

      // Verify products against database
      parsedData = await _verifyProductsInDatabase(parsedData);
      ParsedInvoice baseParsedData = parsedData;

      String? matchedSupplierName = parsedData.supplierName;
      String? matchedSupplierId;
      shared_supplier.Supplier? matchedSupplier;

      if (parsedData.supplierName != null) {
        matchedSupplier = await _matchSupplier(parsedData.supplierName!);
        if (matchedSupplier != null) {
          matchedSupplierName = matchedSupplier.name;
          matchedSupplierId = matchedSupplier.id;
          parsedData = _applySupplierTemplate(parsedData, matchedSupplier);
          debugPrint('✅ OCR matched supplier: ${matchedSupplier.name}');
        } else {
          // If supplier not found in DB, clear it to avoid phantom suppliers
          matchedSupplierName = null;
          debugPrint('⚠️ Supplier not found in DB, clearing OCR result');
          baseParsedData = ParsedInvoice(
            rut: parsedData.rut,
            invoiceNumber: parsedData.invoiceNumber,
            date: parsedData.date,
            total: parsedData.total,
            supplierName: null, // Clear supplier name
            lineItems: parsedData.lineItems,
            rawText: parsedData.rawText,
          );
          parsedData = baseParsedData;
        }
      }

      setState(() {
        _baseParsedData = baseParsedData;
        _parsedData = parsedData;
        _ocrSupplier = matchedSupplier;
        _ocrSupplierName = matchedSupplierName;
        _supplierIdForNewProducts = matchedSupplierId;
        _isProcessing = false;
      });
      if (!widget.showPreview) {
        await _handleUseParsedData(parsedData);
      }
    } catch (e) {
      debugPrint('❌ PDF processing error: $e');
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
  Future<ParsedInvoice> _verifyProductsInDatabase(ParsedInvoice invoice) async {
    debugPrint(
        '🔍 Verifying ${invoice.lineItems.length} products in database...');

    final verifiedItems = <ParsedLineItem>[];

    for (final item in invoice.lineItems) {
      final verifiedItem = await _verifySingleProduct(item);
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

/// Entry for a new product to be created from OCR
class _NewProductEntry {
  final ParsedLineItem originalItem;
  bool isSelected;
  final TextEditingController nameController;
  final TextEditingController skuController;
  final TextEditingController costController;
  final TextEditingController priceController;
  Category? selectedCategory;
  ProductBrand? selectedBrand;
  String? imageUrl;
  String? imageUrlOptimized;
  bool isUploadingImage = false;
  bool isHoveringImage = false;
  bool isWorkshopConsumable = false;

  _NewProductEntry({
    required this.originalItem,
    this.isSelected = true,
    String? initialName,
    this.selectedCategory,
  })  : nameController = TextEditingController(
            text: initialName ?? _cleanDescription(originalItem.description)),
        skuController = TextEditingController(text: originalItem.sku),
        costController =
            TextEditingController(text: _calculateDefaultCost(originalItem)),
        priceController =
            TextEditingController(text: _calculateDefaultPrice(originalItem));

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

  /// Calculate default sale price: 2x cost, rounded to nearest 100
  static String _calculateDefaultPrice(ParsedLineItem item) {
    final rawCost = _calculateDefaultCost(item);
    final cost = double.tryParse(rawCost.replaceAll(',', '.')) ?? 0;
    if (cost <= 0) return '';
    // Cost + IVA (19%) * 2, rounded to nearest 100
    // Formula: Cost * 1.19 * 2
    final price = (cost * 1.19 * 2 / 100).round() * 100;
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
      parsedCost != null &&
      parsedCost! >= 0 &&
      price != null &&
      price! > 0;
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
