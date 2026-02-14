import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../services/ocr_service.dart';
import '../services/invoice_parser_service.dart';
import '../services/pdf_parser_service.dart';
import '../services/veryfi_service.dart';
import '../services/veryfi_config_loader.dart';
import '../services/veryfi_adapter.dart';
import '../services/inventory_service.dart';
import '../models/product.dart' show Product;
import '../services/database_service.dart';
import '../services/tenant_service.dart';
import '../../modules/inventory/services/category_service.dart';
import '../../modules/inventory/models/category_models.dart' show Category;
import '../../modules/inventory/services/inventory_service.dart' as inv_service;
import '../../modules/inventory/models/inventory_models.dart' as inv_models;
import '../../modules/inventory/services/brand_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../modules/inventory/models/brand_models.dart' show ProductBrand;
import '../services/image_service.dart';
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

  // Determined at runtime based on config
  bool _useVeryfi = false;
  bool _veryfiAvailable = false;
  bool _initialized = false;

  // Bulk product creation state
  bool _showBulkCreate = false;
  List<_NewProductEntry> _newProductEntries = [];
  List<Category> _categories = [];
  List<ProductBrand> _brands = [];
  bool _loadingCategories = false;
  bool _creatingProducts = false;
  String? _supplierIdForNewProducts; // For potential future use
  String? _ocrSupplierName; // Supplier detected by OCR

  @override
  void initState() {
    super.initState();
    _initializeOCR();
  }

  Future<void> _initializeOCR() async {
    try {
      // Initialize local OCR (may fail on macOS/desktop)
      try {
        await _ocrService.initialize();
      } catch (e) {
        debugPrint('⚠️ Local OCR init failed (OK on desktop): $e');
      }

      // Check Veryfi availability
      try {
        await VeryfiConfigLoader.loadEnv();
        _veryfiAvailable = VeryfiConfigLoader.isConfigured;
        debugPrint('🔧 Veryfi configured: $_veryfiAvailable');
      } catch (e) {
        debugPrint('⚠️ Veryfi config load failed: $e');
        _veryfiAvailable = false;
      }

      // Determine which provider to use
      switch (widget.provider) {
        case OCRProvider.auto:
          _useVeryfi = _veryfiAvailable;
          break;
        case OCRProvider.veryfi:
          _useVeryfi = true;
          break;
        case OCRProvider.local:
          _useVeryfi = false;
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

        // Veryfi not configured warning (only when forcing Veryfi)
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
                      'Veryfi no está configurado. Agrega VERYFI_CLIENT_ID y VERYFI_API_KEY en el archivo .env',
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
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _buildDetailRow(
                      Icons.receipt,
                      'N° Factura',
                      data.invoiceNumber ?? '---',
                    ),
                  ),
                  Expanded(
                    child: _buildDetailRow(
                      Icons.calendar_today,
                      'Fecha',
                      data.date != null
                          ? '${data.date!.day}/${data.date!.month}/${data.date!.year}'
                          : '---',
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              _buildDetailRow(
                Icons.attach_money,
                'Total',
                data.total != null
                    ? '\$${data.total!.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}'
                    : '---',
                isBold: true,
                valueColor: theme.colorScheme.primary,
                valueSize: 18,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Products Section
        Text(
          'Productos Detectados (${data.lineItems.length})',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
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
                            flex: 2,
                            child: Text('SKU',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                    fontSize: 12)),
                          ),
                          Expanded(
                            flex: 6, // Give description most space
                            child: Text('Descripción',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                    fontSize: 12)),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text('Cant.',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                    fontSize: 12)),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text('Precio',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade700,
                                    fontSize: 12)),
                          ),
                          Expanded(
                            flex: 2,
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
                                    flex: 2,
                                    child: Text(
                                      item.sku ?? '-',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: item.existsInDatabase == true
                                            ? Colors.green.shade700
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 6,
                                    child: Text(
                                      item.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                        item.quantity?.toStringAsFixed(0) ??
                                            '1',
                                        style: const TextStyle(fontSize: 13)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                        item.unitPrice != null
                                            ? '\$${item.unitPrice!.toStringAsFixed(0)}'
                                            : '-',
                                        style: const TextStyle(fontSize: 13)),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                        item.total != null
                                            ? '\$${item.total!.toStringAsFixed(0)}'
                                            : '-',
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold)),
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

        // Create New Products Button (if any new products detected)
        if (data.lineItems.any((item) =>
            item.existsInDatabase == false && (item.sku?.isNotEmpty ?? false)))
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: OutlinedButton.icon(
              onPressed: _openBulkCreateScreen,
              icon: const Icon(Icons.add_circle_outline, color: Colors.orange),
              label: Text(
                'Crear ${data.lineItems.where((item) => item.existsInDatabase == false && (item.sku?.isNotEmpty ?? false)).length} Productos Nuevos',
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
                    _errorMessage = null;
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
                onPressed: () {
                  widget.onComplete(data);
                },
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

    // Get new products (those with SKU but not in database)
    final newProducts = _parsedData!.lineItems
        .where((item) =>
            item.existsInDatabase == false && (item.sku?.isNotEmpty ?? false))
        .toList();

    if (newProducts.isEmpty) return;

    // Load categories and brands
    setState(() => _loadingCategories = true);
    try {
      final dbService = DatabaseService();
      final tenantService = TenantService();
      final categoryService = CategoryService(dbService, tenantService);
      final brandService = BrandService(dbService);
      _categories = await categoryService.getCategories();
      _brands = await brandService.getBrands(activeOnly: true);
    } catch (e) {
      debugPrint('Failed to load categories/brands: $e');
    } finally {
      setState(() => _loadingCategories = false);
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
      final supplierList = suppliers
          .map((s) => shared_supplier.Supplier.fromJson(s))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      if (mounted) {
        Navigator.pop(context); // Close loading start

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Seleccionar Proveedor'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                itemCount: supplierList.length,
                itemBuilder: (context, index) {
                  final supplier = supplierList[index];
                  return ListTile(
                    title: Text(supplier.name),
                    subtitle: supplier.rut != null ? Text(supplier.rut!) : null,
                    onTap: () {
                      setState(() {
                        _ocrSupplierName = supplier.name;
                        _supplierIdForNewProducts = supplier.id;

                        // Update parsed data to reflect manually selected supplier
                        if (_parsedData != null) {
                          _parsedData = _parsedData!.copyWith(
                            supplierName: supplier.name,
                          );
                        }
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading on error
      debugPrint('Error loading suppliers: $e');
    }
  }

  /// Build the bulk product creation screen
  Widget _buildBulkCreateScreen() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.add_circle, color: Colors.orange, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Crear Productos Nuevos',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        Text(
                          '${_newProductEntries.where((e) => e.isSelected).length} de ${_newProductEntries.length} seleccionados',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade600),
                        ),
                        Text(
                          ' • ',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade400),
                        ),
                        Icon(
                          (_ocrSupplierName ?? widget.supplierName) != null
                              ? Icons.local_shipping_outlined
                              : Icons.warning_amber_rounded,
                          size: 14,
                          color:
                              (_ocrSupplierName ?? widget.supplierName) != null
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
                            color: (_ocrSupplierName ?? widget.supplierName) !=
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
          const SizedBox(height: 24),

          // Product entries table
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Table header
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(11)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 32), // Status icon width
                      const SizedBox(width: 40), // Checkbox width
                      const SizedBox(
                          width: 50, child: Text('Img')), // Image col
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Text('SKU',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700,
                                fontSize: 12)),
                      ),
                      Expanded(
                          flex: 14, // Name 7 * 2
                          child: Text('Nombre',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey.shade700))),
                      Expanded(
                          flex: 3, // Cost 1.5 * 2
                          child: Text('Costo',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey.shade700))),
                      Expanded(
                          flex: 4, // Price 2 * 2
                          child: Text('Precio',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey.shade700))),
                      Expanded(
                          flex: 5, // Cat 2.5 * 2
                          child: Text('Categoría',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey.shade700))),
                      Expanded(
                          flex: 5, // Brand 2.5 * 2
                          child: Text('Marca',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Colors.grey.shade700))),
                    ],
                  ),
                ),
                // Table rows
                ...List.generate(_newProductEntries.length, (index) {
                  final entry = _newProductEntries[index];
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          entry.isSelected ? Colors.white : Colors.grey.shade50,
                      border:
                          Border(top: BorderSide(color: Colors.grey.shade200)),
                    ),
                    child: Row(
                      children: [
                        // Checkbox
                        SizedBox(
                          width: 40,
                          child: Checkbox(
                            value: entry.isSelected,
                            onChanged: (val) =>
                                setState(() => entry.isSelected = val ?? false),
                          ),
                        ),
                        // Image Drag & Drop Cell
                        DropTarget(
                          onDragDone: (details) async {
                            if (details.files.isNotEmpty) {
                              final file = details.files.first;
                              final bytes = await file.readAsBytes();
                              _uploadImage(entry, bytes, file.name);
                            }
                          },
                          onDragEntered: (details) =>
                              setState(() => entry.isHoveringImage = true),
                          onDragExited: (details) =>
                              setState(() => entry.isHoveringImage = false),
                          child: MouseRegion(
                            onEnter: (_) =>
                                setState(() => entry.isHoveringImage = true),
                            onExit: (_) =>
                                setState(() => entry.isHoveringImage = false),
                            child: Stack(
                              children: [
                                InkWell(
                                  onTap: () async {
                                    final result =
                                        await ImageService.pickImage();
                                    if (result != null) {
                                      _uploadImage(
                                          entry, result.bytes, result.name);
                                    }
                                  },
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: entry.isHoveringImage
                                          ? Colors.blue.withOpacity(0.1)
                                          : Colors.grey[100],
                                      border: Border.all(
                                        color: entry.isHoveringImage
                                            ? Colors.blue
                                            : Colors.grey[300]!,
                                        width: entry.isHoveringImage ? 2 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: entry.isUploadingImage
                                        ? const Center(
                                            child: SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2)))
                                        : entry.imageUrl != null
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                child: ImageService
                                                    .buildProductImage(
                                                  imageUrl: entry.imageUrl,
                                                  size: 50,
                                                ),
                                              )
                                            : const Icon(
                                                Icons.add_photo_alternate,
                                                size: 20,
                                                color: Colors.grey),
                                  ),
                                ),
                                // Remove button overlay (only when image exists and hovering)
                                if (entry.imageUrl != null &&
                                    entry.isHoveringImage)
                                  Positioned(
                                    right: 8, // Adjust for margin
                                    top: 0,
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          entry.imageUrl = null;
                                          entry.imageUrlOptimized = null;
                                        });
                                      },
                                      child: Container(
                                        width: 18,
                                        height: 18,
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 12,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // SKU (readonly)
                        Expanded(
                          flex: 3,
                          child: Text(
                            entry.sku,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              color: entry.isSelected
                                  ? Colors.black87
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        // Name (editable)
                        Expanded(
                          flex: 14,
                          child: TextField(
                            controller: entry.nameController,
                            enabled: entry.isSelected,
                            minLines: 1,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Cost (readonly)
                        Expanded(
                          flex: 3,
                          child: Text(
                            '\$${entry.cost.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: entry.isSelected
                                  ? Colors.black87
                                  : Colors.grey,
                            ),
                          ),
                        ),
                        // Price (editable)
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: entry.priceController,
                            enabled: entry.isSelected,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              isDense: true,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              prefixText: '\$ ',
                              hintText: 'Precio',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Category dropdown
                        Expanded(
                          flex: 5,
                          child: LayoutBuilder(builder: (context, constraints) {
                            return DropdownMenu<Category>(
                              width: constraints.maxWidth,
                              menuHeight: 250,
                              initialSelection: entry.selectedCategory,
                              hintText: 'Categoría',
                              textStyle: const TextStyle(fontSize: 12),
                              inputDecorationTheme: const InputDecorationTheme(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              enabled: entry.isSelected,
                              enableFilter: true,
                              requestFocusOnTap: true,
                              dropdownMenuEntries: _categories
                                  .map((cat) => DropdownMenuEntry<Category>(
                                        value: cat,
                                        label: cat.name,
                                      ))
                                  .toList(),
                              onSelected: (val) {
                                if (val != null) {
                                  setState(() => entry.selectedCategory = val);
                                }
                              },
                            );
                          }),
                        ),
                        const SizedBox(width: 8),
                        // Brand dropdown
                        Expanded(
                          flex: 5,
                          child: LayoutBuilder(builder: (context, constraints) {
                            return DropdownMenu<ProductBrand>(
                              width: constraints.maxWidth,
                              menuHeight: 250,
                              initialSelection: entry.selectedBrand,
                              hintText: 'Marca',
                              textStyle: const TextStyle(fontSize: 12),
                              inputDecorationTheme: const InputDecorationTheme(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              enabled: entry.isSelected,
                              enableFilter: true,
                              requestFocusOnTap: true,
                              dropdownMenuEntries: _brands
                                  .map((brand) =>
                                      DropdownMenuEntry<ProductBrand>(
                                        value: brand,
                                        label: brand.name,
                                      ))
                                  .toList(),
                              onSelected: (val) {
                                if (val != null) {
                                  setState(() => entry.selectedBrand = val);
                                }
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Dispose controllers
                    for (final entry in _newProductEntries) {
                      entry.dispose();
                    }
                    _newProductEntries.clear();
                    setState(() => _showBulkCreate = false);
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Volver'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _newProductEntries.any((e) => e.isSelected && e.isValid)
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
          inventoryQty: (entry.originalItem.quantity ?? 0).toInt(),
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

      String? matchedSupplierName = parsedData?.supplierName;
      String? matchedSupplierId;

      if (parsedData?.supplierName != null) {
        final supplier = await _matchSupplier(parsedData!.supplierName!);
        if (supplier != null) {
          matchedSupplierName = supplier.name;
          matchedSupplierId = supplier.id;
          debugPrint('✅ OCR matched supplier: ${supplier.name}');
        } else {
          // If supplier not found in DB, clear it to avoid phantom suppliers
          // forcing user to select a valid one later
          matchedSupplierName = null;
          debugPrint('⚠️ Supplier not found in DB, clearing OCR result');
          parsedData = ParsedInvoice(
            rut: parsedData!.rut,
            invoiceNumber: parsedData!.invoiceNumber,
            date: parsedData!.date,
            total: parsedData!.total,
            supplierName: null, // Clear supplier name
            lineItems: parsedData!.lineItems,
            rawText: parsedData!.rawText,
          );
        }
      }

      setState(() {
        _parsedData = parsedData;
        _ocrSupplierName = matchedSupplierName;
        _supplierIdForNewProducts = matchedSupplierId;
        _isProcessing = false;
      });
      if (!widget.showPreview) {
        widget.onComplete(parsedData);
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

      String? matchedSupplierName = parsedData?.supplierName;
      String? matchedSupplierId;

      if (parsedData?.supplierName != null) {
        final supplier = await _matchSupplier(parsedData!.supplierName!);
        if (supplier != null) {
          matchedSupplierName = supplier.name;
          matchedSupplierId = supplier.id;
          debugPrint('✅ OCR matched supplier: ${supplier.name}');
        } else {
          // If supplier not found in DB, clear it to avoid phantom suppliers
          matchedSupplierName = null;
          debugPrint('⚠️ Supplier not found in DB, clearing OCR result');
          parsedData = ParsedInvoice(
            rut: parsedData!.rut,
            invoiceNumber: parsedData!.invoiceNumber,
            date: parsedData!.date,
            total: parsedData!.total,
            supplierName: null, // Clear supplier name
            lineItems: parsedData!.lineItems,
            rawText: parsedData!.rawText,
          );
        }
      }

      setState(() {
        _parsedData = parsedData;
        _ocrSupplierName = matchedSupplierName;
        _supplierIdForNewProducts = matchedSupplierId;
        _isProcessing = false;
      });
      if (!widget.showPreview) {
        widget.onComplete(parsedData);
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

    if (!_veryfiAvailable) {
      throw Exception('Veryfi no está configurado.\n\n'
          'Agrega VERYFI_CLIENT_ID y VERYFI_API_KEY en el archivo .env');
    }

    final config = VeryfiConfigLoader.fromEnv();

    if (!VeryfiConfigLoader.validateConfig(config)) {
      throw Exception('Configuración de Veryfi incompleta.\n\n'
          'Verifica que VERYFI_CLIENT_ID y VERYFI_API_KEY están correctos en .env');
    }

    final veryfi = VeryfiService(config);

    try {
      final response = await veryfi.parseInvoiceFromBytes(bytes, filename);
      final parsedData = VeryfiAdapter.toParsedInvoice(response);
      return parsedData;
    } finally {
      veryfi.dispose();
    }
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

    // Use the existing InventoryService from the provider to ensure we access the cached products
    final inventoryService =
        Provider.of<InventoryService>(context, listen: false);
    final verifiedItems = <ParsedLineItem>[];

    for (final item in invoice.lineItems) {
      Product? matchedProduct;

      // PRIORITY 1: Try to find by SKU (if available)
      if (item.sku != null && item.sku!.isNotEmpty) {
        try {
          matchedProduct = await inventoryService.getProductBySku(item.sku!);
          if (matchedProduct != null) {
            debugPrint(
                '   ✓ Found by SKU: ${matchedProduct.name} (${item.sku})');
          }
        } catch (e) {
          debugPrint('   ❌ Error looking up SKU ${item.sku}: $e');
        }
      }

      // PRIORITY 2: Try to find by Supplier Code (match invoice SKU to product supplier_code)
      if (matchedProduct == null && item.sku != null && item.sku!.isNotEmpty) {
        final cleanSku = item.sku!.trim();
        try {
          debugPrint('   🔍 Searching by Supplier Code: "$cleanSku"');
          matchedProduct =
              await inventoryService.getProductBySupplierCode(cleanSku);
          if (matchedProduct != null) {
            debugPrint(
                '   ✓ Found by Supplier Code: ${matchedProduct.name} ($cleanSku)');
          } else {
            debugPrint('   ⚠️ No product found with supplier_code="$cleanSku"');
          }
        } catch (e) {
          debugPrint('   ❌ Error looking up Supplier Code $cleanSku: $e');
        }
      }

      // PRIORITY 3: Fall back to searching by name (EXACT MATCH ONLY)
      // Only matches if product name exactly equals OCR description (case-insensitive)
      if (matchedProduct == null && item.description.isNotEmpty) {
        try {
          final normalizedDescription = item.description.trim().toLowerCase();
          final allProducts = await inventoryService.getProducts();

          // Find product with exact name match (case-insensitive)
          for (final product in allProducts) {
            final normalizedProductName = product.name.trim().toLowerCase();
            if (normalizedProductName == normalizedDescription) {
              matchedProduct = product;
              debugPrint(
                  '   ✓ Found by EXACT name match: ${matchedProduct.name}');
              break;
            }
          }

          if (matchedProduct == null) {
            debugPrint('   ⚠ No exact name match for: "${item.description}"');
          }
        } catch (e) {
          debugPrint('   ❌ Error searching by name: $e');
        }
      }

      // Set verification result
      if (matchedProduct != null) {
        verifiedItems.add(item.copyWith(
          existsInDatabase: true,
          matchedProductId: matchedProduct.id,
          matchedProductName: matchedProduct.name,
        ));
      } else {
        debugPrint('   ⚠ No match for: ${item.sku ?? item.description}');
        verifiedItems.add(item.copyWith(existsInDatabase: false));
      }
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
    if (errorStr.contains('Veryfi API error: 401')) {
      return 'Error de autenticación con Veryfi.\n\n'
          'Verifica que las credenciales en .env son correctas.';
    }
    if (errorStr.contains('Veryfi API error: 403')) {
      return 'Acceso denegado por Veryfi.\n\n'
          'Tu cuenta puede haber excedido el límite de documentos.';
    }
    if (errorStr.contains('Veryfi API error')) {
      return 'Error del servidor Veryfi: $errorStr';
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
  final TextEditingController priceController;
  Category? selectedCategory;
  ProductBrand? selectedBrand;
  String? imageUrl;
  String? imageUrlOptimized;
  bool isUploadingImage = false;
  bool isHoveringImage = false;

  _NewProductEntry({
    required this.originalItem,
    this.isSelected = true,
    String? initialName,
    this.selectedCategory,
    this.selectedBrand,
  })  : nameController = TextEditingController(
            text: initialName ?? _cleanDescription(originalItem.description)),
        priceController =
            TextEditingController(text: _calculateDefaultPrice(originalItem));

  /// Calculate default sale price: 2x cost, rounded to nearest 100
  static String _calculateDefaultPrice(ParsedLineItem item) {
    double cost = 0;
    if (item.unitPrice != null && item.unitPrice! > 0) {
      cost = item.unitPrice!;
    } else if (item.total != null && item.total! > 0) {
      final qty = item.quantity ?? 1;
      cost = item.total! / (qty > 0 ? qty : 1);
    }
    if (cost <= 0) return '';
    // 2x cost, rounded to nearest 100
    final price = (cost * 2 / 100).round() * 100;
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
    priceController.dispose();
  }

  /// Get SKU from original item
  String get sku => originalItem.sku ?? '';

  /// Get cost from original item (unitPrice, or calculated from total/quantity)
  double get cost {
    if (originalItem.unitPrice != null && originalItem.unitPrice! > 0) {
      return originalItem.unitPrice!;
    }
    // Fallback: calculate from line total divided by quantity
    if (originalItem.total != null && originalItem.total! > 0) {
      final qty = originalItem.quantity ?? 1;
      return originalItem.total! / (qty > 0 ? qty : 1);
    }
    return 0;
  }

  /// Get entered price
  double? get price =>
      double.tryParse(priceController.text.replaceAll(',', '.'));

  /// Validate entry is complete
  bool get isValid =>
      sku.isNotEmpty &&
      nameController.text.isNotEmpty &&
      price != null &&
      price! > 0;
}
