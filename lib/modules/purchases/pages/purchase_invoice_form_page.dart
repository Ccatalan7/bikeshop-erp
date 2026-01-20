import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/supplier.dart' as shared_supplier;
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/number_generation_service.dart';
import '../../../shared/services/remote_scanner_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/services/invoice_parser_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/smart_product_field.dart';
import '../../../shared/widgets/search_bar_widget.dart';
import '../../../shared/widgets/line_row_wrapper.dart';
import '../../../shared/widgets/ocr_upload_widget.dart';
import '../../inventory/pages/product_form_page.dart';
import '../models/purchase_invoice.dart';
import '../services/purchase_service.dart';

class PurchaseInvoiceFormPage extends StatefulWidget {
  final String? invoiceId;
  final bool isPrepayment;
  final String? initialSupplierId;
  final List<Map<String, dynamic>>? initialLineItems;
  final bool readOnly; // View-only mode (no editing, no status changes)

  const PurchaseInvoiceFormPage({
    super.key,
    this.invoiceId,
    this.isPrepayment = false,
    this.initialSupplierId,
    this.initialLineItems,
    this.readOnly = false,
    this.referrer,
  });

  final String? referrer;

  @override
  State<PurchaseInvoiceFormPage> createState() =>
      _PurchaseInvoiceFormPageState();
}

class _PurchaseInvoiceFormPageState extends State<PurchaseInvoiceFormPage> {
  static const double _ivaRate = 0.19;

  // Table column widths (match sales invoice)
  static const double _colIndexWidth = 40.0;
  static const double _colQuantityWidth = 120.0;
  static const double _colPriceWidth = 130.0;
  static const double _colDiscountWidth = 130.0;
  static const double _colTotalWidth = 130.0;
  static const double _colActionsWidth = 48.0;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _invoiceNumberController =
      TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final List<_PurchaseLineEntry> _lineEntries = [];

  late PurchaseService _purchaseService;
  late InventoryService _inventoryService;

  shared_supplier.Supplier? _selectedSupplier;
  PurchaseInvoice? _loadedInvoice;
  DateTime _issueDate = DateTime.now();
  DateTime? _dueDate;
  PurchaseInvoiceStatus _status = PurchaseInvoiceStatus.draft;
  TaxTreatment _taxTreatment = TaxTreatment.noTax;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUpdatingStatus = false;
  bool _isEditing = false; // Edit mode toggle (like sales invoice)

  /// Payment model: true = Prepayment (pay before receive), false = Standard (receive before pay)
  /// Defaults to true (prepayment) for new invoices
  late bool _isPrepaymentModel;

  List<shared_supplier.Supplier> _supplierCache = const [];
  List<Product> _productCache = const [];

  StreamSubscription? _scanSubscription;
  RemoteScannerService? _remoteScannerService; // Lazy init to avoid blocking
  bool _scannerEnabled = false;

  @override
  void initState() {
    super.initState();
    _dueDate = _issueDate.add(const Duration(days: 30));

    // Initialize payment model:
    // - New invoice: default to prepayment (true) unless widget says otherwise
    // - Existing invoice: will be loaded from database in _initialize()
    _isPrepaymentModel = widget.isPrepayment ||
        widget.invoiceId == null; // Default to prepayment for new

    // Set initial editing state:
    // - New invoice (invoiceId == null) → editing mode
    // - Existing draft → view mode (user clicks "Editar" to edit)
    // - Other statuses → always view mode
    _isEditing = widget.invoiceId == null;

    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());

    // DON'T subscribe to barcode scanner here - causes freeze!
    // Will be set up after initialization completes
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    for (final entry in _lineEntries) {
      entry.dispose();
    }
    _scanSubscription?.cancel();
    super.dispose();
  }

  // Can edit fields only when status is draft AND in editing mode
  bool get _canEditFields =>
      _status == PurchaseInvoiceStatus.draft && _isEditing;

  Future<void> _toggleScanner() async {
    if (!_canEditFields) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No se puede escanear en facturas enviadas'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      // Lazy init scanner service
      _remoteScannerService ??= RemoteScannerService();

      if (_scannerEnabled) {
        await _remoteScannerService!.stopListening();
        setState(() => _scannerEnabled = false);
      } else {
        await _remoteScannerService!.startListening();
        setState(() => _scannerEnabled = true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📱 Escáner remoto activado'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error con escáner: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleBarcodeScan(String barcode) async {
    // Search for product by SKU
    final product = _productCache.cast<Product?>().firstWhere(
          (p) => p!.sku.toLowerCase() == barcode.toLowerCase(),
          orElse: () => null,
        );

    if (product != null) {
      // Check if product is already in the invoice
      final existingLineIndex = _lineEntries.indexWhere(
        (entry) => entry.line.productId == product.id,
      );

      if (existingLineIndex != -1) {
        // Increment quantity
        final entry = _lineEntries[existingLineIndex];
        final currentQty = int.tryParse(entry.quantityController.text) ?? 0;
        entry.quantityController.text = (currentQty + 1).toString();
        setState(() {}); // Trigger recalculation
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Cantidad aumentada: ${product.name}'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        // Add as new line
        setState(() {
          final newLine = PurchaseInvoiceItem(
            productId: product.id,
            productName: product.name,
            productSku: product.sku,
            quantity: 1,
            unitCost: product.cost,
            discount: 0,
          );
          final newEntry = _PurchaseLineEntry(line: newLine);
          newEntry.attachListeners(() {
            setState(() {});
          });
          _lineEntries.add(newEntry);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Producto agregado: ${product.name}'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Producto no encontrado: $barcode'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Open OCR scanner to extract invoice data from image
  Future<void> _openOCRScanner() async {
    if (!_canEditFields) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No se puede escanear en facturas enviadas'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show OCR upload widget in bottom sheet
    // Show OCR upload widget in centered dialog
    await showDialog(
      context: context,
      barrierDismissible: true, // Allow tapping outside to close
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1100,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Close button aligned to right
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Cerrar',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      foregroundColor: Colors.grey.shade700,
                    ),
                  ),
                ),
              ),
              // Content with padding
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: OCRUploadWidget(
                    documentType: OCRDocumentType.invoice,
                    showPreview: true,
                    supplierId: _selectedSupplier?.id,
                    supplierName: _selectedSupplier?.name,
                    onComplete: (parsedInvoice) {
                      // Close dialog
                      Navigator.of(context).pop();

                      // Apply extracted data to form
                      _applyOCRData(parsedInvoice);
                    },
                    onError: (error) {
                      // Error already shown in widget
                      debugPrint('OCR Error: $error');
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Apply OCR-extracted data to the form
  void _applyOCRData(ParsedInvoice parsedInvoice) {
    setState(() {
      // 1. Invoice number (if extracted)
      if (parsedInvoice.invoiceNumber != null &&
          parsedInvoice.invoiceNumber!.isNotEmpty) {
        _invoiceNumberController.text = parsedInvoice.invoiceNumber!;
      }

      // 2. Date (if extracted)
      if (parsedInvoice.date != null) {
        _issueDate = parsedInvoice.date!;
        _dueDate = _issueDate.add(const Duration(days: 30));
      }

      // 3. Supplier (match by RUT or name)
      if (parsedInvoice.rut != null || parsedInvoice.supplierName != null) {
        final rut = parsedInvoice.rut
            ?.replaceAll(RegExp(r'[.\-]'), ''); // Normalize RUT
        final name = parsedInvoice.supplierName?.toLowerCase();

        // Try to match existing supplier
        final matchedSupplier =
            _supplierCache.cast<shared_supplier.Supplier?>().firstWhere(
          (supplier) {
            if (supplier == null) return false;

            // Match by RUT (if available)
            if (rut != null && supplier.rut != null) {
              final supplierRut =
                  supplier.rut!.replaceAll(RegExp(r'[.\-]'), '');
              if (supplierRut == rut) return true;
            }

            // Match by name (fuzzy)
            if (name != null) {
              final supplierName = supplier.name.toLowerCase();
              return supplierName.contains(name) || name.contains(supplierName);
            }

            return false;
          },
          orElse: () => null,
        );

        if (matchedSupplier != null) {
          _selectedSupplier = matchedSupplier;
        }
      }

      // 4. Total amount (show as reference in notes if no line items)
      if (parsedInvoice.total != null && parsedInvoice.lineItems.isEmpty) {
        final totalStr = ChileanUtils.formatCurrency(parsedInvoice.total!);
        _notesController.text =
            'Total detectado: $totalStr\n${_notesController.text}';
      }
      // 5. Line items (if extracted)
      if (parsedInvoice.lineItems.isNotEmpty) {
        // Clear default empty line if it's the only one and has no product
        // Check if the list contains only one item and that item is "empty" (no product ID or name)
        if (_lineEntries.length == 1) {
          final firstLine = _lineEntries.first.line;
          if (firstLine.productId.isEmpty &&
              (firstLine.productName == null ||
                  firstLine.productName!.isEmpty)) {
            _lineEntries.clear();
          }
        }

        for (final item in parsedInvoice.lineItems) {
          // Try to match product by SKU first, then by name
          // Debug cache content
          debugPrint(
              '🔍 Matching item: ${item.description} (SKU: ${item.sku})');
          debugPrint('📦 Product Cache Size: ${_productCache.length}');

          // Check if SKU exists in cache manually for debugging
          if (item.sku != null) {
            final targetSku = item.sku!.trim().toUpperCase();

            // Check both SKU and supplier_code in cache
            final skuMatches = _productCache
                .where((p) => p.sku.trim().toUpperCase() == targetSku)
                .toList();
            final supplierCodeMatches = _productCache
                .where((p) =>
                    p.supplierCode != null &&
                    p.supplierCode!.trim().toUpperCase() == targetSku)
                .toList();

            debugPrint('🔎 Looking for: "$targetSku"');
            debugPrint('📊 SKU matches: ${skuMatches.length}');
            debugPrint(
                '📊 Supplier Code matches: ${supplierCodeMatches.length}');

            if (supplierCodeMatches.isNotEmpty) {
              debugPrint(
                  '✅ Found by SUPPLIER CODE: ${supplierCodeMatches.first.name}');
            }
            if (skuMatches.isNotEmpty) {
              debugPrint('✅ Found by SKU: ${skuMatches.first.name}');
            }

            if (skuMatches.isEmpty && supplierCodeMatches.isEmpty) {
              debugPrint('❌ Not found in either SKU or Supplier Code');
              // Print sample data for debugging
              debugPrint(
                  '📋 Sample products with supplier codes: ${_productCache.take(5).map((p) => '${p.sku} / ${p.supplierCode}').toList()}');
            }
          }

          final matchedProduct = _productCache.cast<Product?>().firstWhere(
            (product) {
              if (product == null) return false;

              // 1. Match by SKU or Supplier Code (Exact match)
              if (item.sku != null && item.sku!.isNotEmpty) {
                final productSku = product.sku.trim().toUpperCase();
                final itemSku = item.sku!.trim().toUpperCase();

                // Match by SKU
                if (productSku == itemSku) {
                  return true;
                }

                // Match by Supplier Code (Código Proveedor)
                if (product.supplierCode != null &&
                    product.supplierCode!.isNotEmpty) {
                  final productSupplierCode =
                      product.supplierCode!.trim().toUpperCase();
                  if (productSupplierCode == itemSku) {
                    return true;
                  }
                }
              }

              // 2. Match by Name (Fuzzy)
              final productName = product.name.toLowerCase();
              final itemDesc = item.description.toLowerCase();
              // Only match by name if SKU/Supplier Code check didn't pass
              return productName.contains(itemDesc) ||
                  itemDesc.contains(productName);
            },
            orElse: () => null,
          );

          if (matchedProduct != null) {
            debugPrint(
                '  ✨ Selected product: ${matchedProduct.name} (ID: ${matchedProduct.id})');

            // Add matched product - Mirroring manual selection logic
            final newLine = PurchaseInvoiceItem(
              productId: matchedProduct.id,
              productName: matchedProduct.name,
              productSku: matchedProduct.sku,
              quantity: item.quantity ?? 1,
              unitCost: item.unitPrice ??
                  matchedProduct
                      .cost, // Use OCR price if available, else product cost
              discount: 0,
            );

            final newEntry = _PurchaseLineEntry(line: newLine);

            // CRITICAL: Set all controllers and product object to match manual selection behavior
            newEntry.product = matchedProduct;
            newEntry.productNameController.text = matchedProduct.name;
            newEntry.productSkuController.text = matchedProduct.sku;
            newEntry.descriptionController.text =
                matchedProduct.description ?? '';

            // Set unit cost controller if we have a price
            if (newLine.unitCost > 0) {
              newEntry.unitCostController.text =
                  newLine.unitCost.toStringAsFixed(0);
            }

            // Apply discount from OCR if available
            if (item.discountRate != null && item.discountRate! > 0) {
              // Percentage discount detected
              newEntry.discountType = DiscountType.percentage;
              newEntry.discountController.text =
                  item.discountRate!.toStringAsFixed(0);
              // Force recalculation immediately
              newEntry.recalculateDiscount();
            } else if (item.discount != null && item.discount! > 0) {
              // Amount discount detected
              newEntry.discountType = DiscountType.amount;
              newEntry.discountController.text =
                  item.discount!.toStringAsFixed(0);
              // Force recalculation immediately
              newEntry.recalculateDiscount();
            }

            newEntry.attachListeners(_recalculateTotals);
            _lineEntries.add(newEntry);
          } else {
            debugPrint('  ❌ No match found for item');
          }
        }
      }

      // 6. Set tax treatment if total detected
      if (parsedInvoice.total != null && _taxTreatment == TaxTreatment.noTax) {
        // Assume tax included for Chilean invoices
        _taxTreatment = TaxTreatment.taxIncluded;
      }
    });

    // Show success message
    if (mounted) {
      final extractedFields = <String>[];
      if (parsedInvoice.invoiceNumber != null)
        extractedFields.add('N° Factura');
      if (parsedInvoice.supplierName != null) extractedFields.add('Proveedor');
      if (parsedInvoice.date != null) extractedFields.add('Fecha');
      if (parsedInvoice.total != null) extractedFields.add('Total');
      if (parsedInvoice.lineItems.isNotEmpty)
        extractedFields.add('${parsedInvoice.lineItems.length} productos');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Datos extraídos: ${extractedFields.join(', ')}',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _initialize() async {
    debugPrint('🔍 PurchaseForm._initialize() START');

    try {
      debugPrint('🔍 Getting PurchaseService from context...');
      _purchaseService = context.read<PurchaseService>();
      debugPrint('✅ Got PurchaseService');

      debugPrint('🔍 Getting InventoryService from context...');
      _inventoryService = context.read<InventoryService>();
      debugPrint('✅ Got InventoryService');
    } catch (e) {
      debugPrint('❌ Error getting services: $e');
      rethrow;
    }

    if (!mounted) {
      debugPrint('⚠️ Widget not mounted after getting services');
      return;
    }

    try {
      // Load suppliers and products in parallel
      debugPrint('🔍 Loading data in parallel (suppliers + products)...');

      final futures = <Future<dynamic>>[
        _purchaseService.getSuppliers(forceRefresh: false),
        _inventoryService.getProducts(forceRefresh: false),
      ];

      // Also fetch preview number in parallel if this is a new invoice
      if (widget.invoiceId == null) {
        futures.add(_previewPurchaseInvoiceNumber());
      }

      final results = await Future.wait(futures);

      _supplierCache = results[0] as List<shared_supplier.Supplier>;
      debugPrint('✅ Loaded ${_supplierCache.length} suppliers');

      final allProducts = results[1] as List<Product>;
      // Filter out child products (components) as they should not be purchased directly
      _productCache = allProducts.where((p) => p.parentSetId == null).toList();
      debugPrint(
          '✅ Loaded ${_productCache.length} products (filtered from ${allProducts.length})');

      if (!mounted) {
        debugPrint('⚠️ Widget not mounted after loading data');
        return;
      }

      // Handle preview number if loaded
      if (widget.invoiceId == null && results.length > 2) {
        _invoiceNumberController.text = results[2] as String;
      }

      if (widget.invoiceId != null) {
        final invoice =
            await _purchaseService.getPurchaseInvoice(widget.invoiceId!);
        if (invoice != null) {
          _loadedInvoice = invoice;
          _applyInvoice(invoice);
        }
      } else {
        // If preview number failed or wasn't loaded in parallel (shouldn't happen with above logic), fallback
        if (_invoiceNumberController.text.isEmpty) {
          _invoiceNumberController.text = await _previewPurchaseInvoiceNumber();
        }

        // Check for pending data from smart purchase list (via service)

        // Check for pending data from smart purchase list (via service)
        final pendingData = _purchaseService.consumePendingSmartPurchaseData();

        // Pre-fill from constructor params OR pending data from service
        final supplierId =
            widget.initialSupplierId ?? pendingData?['supplierId'] as String?;
        final lineItems = widget.initialLineItems ??
            pendingData?['lineItems'] as List<Map<String, dynamic>>?;

        if (supplierId != null && _supplierCache.isNotEmpty) {
          try {
            _selectedSupplier = _supplierCache.firstWhere(
              (s) => s.id == supplierId,
            );
          } catch (e) {
            // Supplier not found, leave null
          }
        }

        if (lineItems != null && lineItems.isNotEmpty) {
          for (final item in lineItems) {
            final productId = item['product_id'] as String?;
            final productName = item['product_name'] as String?;
            final productSku = item['product_sku'] as String?;
            final suggestedQty = (item['suggested_quantity'] as int?) ?? 1;

            if (productId != null &&
                productId.isNotEmpty &&
                _productCache.isNotEmpty) {
              try {
                final product = _productCache.firstWhere(
                  (p) => p.id == productId,
                );

                // Add line with suggested quantity from database product
                final entry = _PurchaseLineEntry(
                  line: PurchaseInvoiceItem(
                    productId: product.id,
                    productName: product.name,
                    productSku: product.sku,
                    quantity: suggestedQty.toDouble(),
                    unitCost: product.cost > 0 ? product.cost : product.price,
                    discount: 0,
                    ivaRate: _ivaRate,
                  ),
                );
                entry.attachListeners(_recalculateTotals);
                _lineEntries.add(entry);
              } catch (e) {
                debugPrint('⚠️ Product $productId not found: $e');
                // Product not found in cache, add as ad-hoc item
                if (productName != null && productName.isNotEmpty) {
                  final entry = _PurchaseLineEntry(
                    line: PurchaseInvoiceItem(
                      productId: '', // Ad-hoc item (empty string)
                      productName: productName,
                      productSku: productSku,
                      quantity: suggestedQty.toDouble(),
                      unitCost: 0, // User will fill this
                      discount: 0,
                      ivaRate: _ivaRate,
                    ),
                  );
                  entry.attachListeners(_recalculateTotals);
                  _lineEntries.add(entry);
                }
              }
            } else if (productName != null && productName.isNotEmpty) {
              // No productId or empty, add as ad-hoc item
              final entry = _PurchaseLineEntry(
                line: PurchaseInvoiceItem(
                  productId: '', // Ad-hoc item (empty string)
                  productName: productName,
                  productSku: productSku,
                  quantity: suggestedQty.toDouble(),
                  unitCost: 0, // User will fill this
                  discount: 0,
                  ivaRate: _ivaRate,
                ),
              );
              entry.attachListeners(_recalculateTotals);
              _lineEntries.add(entry);
            }
          }

          // Recalculate totals after adding all lines
          if (_lineEntries.isNotEmpty) {
            _recalculateTotals();
          } else {
            // If no lines, add one empty line to start
            _addEmptyLine();
          }
        } else {
          // New invoice - start with one empty line
          _addEmptyLine();
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error preparando el formulario: $e'),
          backgroundColor: Colors.red,
        ),
      );
      _invoiceNumberController.text = await _previewPurchaseInvoiceNumber();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);

        // Set up barcode scanner subscription AFTER initialization completes
        // Lazy init scanner service only when needed
        _remoteScannerService ??= RemoteScannerService();
        _scanSubscription = _remoteScannerService!.scanStream.listen((scan) {
          if (mounted && _canEditFields) {
            _handleBarcodeScan(scan.barcode);
          }
        });
        debugPrint('✅ Barcode scanner subscription set up');
      }
    }
  }

  void _applyInvoice(PurchaseInvoice invoice) {
    _invoiceNumberController.text = invoice.invoiceNumber.isNotEmpty
        ? invoice.invoiceNumber
        : _buildSuggestedNumber();
    _referenceController.text = invoice.reference ?? '';
    _notesController.text = invoice.notes ?? '';
    _issueDate = invoice.date;
    _dueDate = invoice.dueDate ?? invoice.date.add(const Duration(days: 30));
    _status = invoice.status;
    _taxTreatment = invoice.taxTreatment;
    _isPrepaymentModel =
        invoice.prepaymentModel; // Load payment model from invoice

    _selectedSupplier = _supplierCache.firstWhere(
      (supplier) => supplier.id == invoice.supplierId,
      orElse: () => shared_supplier.Supplier(
        id: invoice.supplierId ?? '',
        tenantId: invoice.tenantId, // Use invoice's tenant_id
        name: invoice.supplierName ?? 'Proveedor',
        createdAt: invoice.createdAt,
        updatedAt: invoice.updatedAt,
      ),
    );

    for (final item in invoice.items) {
      final product = _productCache.firstWhere(
        (candidate) => candidate.id == item.productId,
        orElse: () => Product(
          id: item.productId,
          name: item.productName ?? 'Producto',
          sku: item.productSku ?? '',
          price: item.unitCost,
          cost: item.unitCost,
          stockQuantity: 0,
          minStockLevel: 0,
          maxStockLevel: 0,
          description: null,
          imageUrl: null,
          imageUrls: const [],
          category: ProductCategory.other,
          specifications: const {},
          tags: const [],
          unit: ProductUnit.unit,
          weight: 0,
          trackStock: true,
          isActive: true,
          createdAt: item.createdAt,
          updatedAt: item.createdAt,
        ),
      );

      final entry = _PurchaseLineEntry(
        line: PurchaseInvoiceItem(
          productId: item.productId,
          productName: product.name,
          productSku: product.sku,
          quantity: item.quantity,
          unitCost: item.unitCost,
          discount: item.discount,
          ivaRate: item.ivaRate,
        ),
      );
      entry.attachListeners(_recalculateTotals);
      _lineEntries.add(entry);
    }
  }

  String _buildSuggestedNumber() {
    // Deprecated: Use NumberGenerationService instead
    // This fallback should rarely be used
    final now = DateTime.now();
    final datePortion =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timePortion = now.millisecondsSinceEpoch.toString().substring(7);
    return 'FC-$datePortion-$timePortion';
  }

  /// Preview what the next invoice number will be (doesn't increment counter)
  /// Used when entering form - actual number assigned only on save
  Future<String> _previewPurchaseInvoiceNumber() async {
    try {
      final numberService = NumberGenerationService();
      return await numberService.previewPurchaseInvoiceNumber();
    } catch (e) {
      debugPrint('Error previewing purchase invoice number: $e');
      return _buildSuggestedNumber(); // Fallback to old method
    }
  }

  /// Generate the actual invoice number (increments counter)
  /// Used only when actually SAVING a new invoice
  Future<String> _generatePurchaseInvoiceNumber() async {
    try {
      final numberService = NumberGenerationService();
      return await numberService.nextPurchaseInvoiceNumber();
    } catch (e) {
      debugPrint('Error generating purchase invoice number: $e');
      return _buildSuggestedNumber(); // Fallback to old method
    }
  }

  double get _subtotal => _lineEntries.fold<double>(
      0, (sum, entry) => sum + entry.line.netAmountClamped);

  // Tax calculations for PURCHASES (tax is ADDED, not included)
  // Opposite to sales where tax is included in price
  double get _netAmount {
    return _subtotal; // Net is always the subtotal for purchases
  }

  double get _iva {
    if (_taxTreatment == TaxTreatment.taxIncluded) {
      return _subtotal * 0.19; // Add 19% tax
    } else {
      return 0; // No tax
    }
  }

  double get _total {
    if (_taxTreatment == TaxTreatment.taxIncluded) {
      return _subtotal + _iva; // Subtotal + 19% tax
    } else {
      return _subtotal; // No tax added
    }
  }

  void _recalculateTotals() {
    if (mounted) setState(() {});
  }

  Future<void> _openSupplierSelector() async {
    if (_supplierCache.isEmpty) {
      try {
        _supplierCache =
            await _purchaseService.getSuppliers(forceRefresh: true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al cargar proveedores: $e'),
              backgroundColor: Colors.red),
        );
        return;
      }
    }

    if (!mounted) return;

    final selected = await showModalBottomSheet<shared_supplier.Supplier>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return _SupplierSelector(
          suppliers: _supplierCache,
          onCreateSupplier: _createQuickSupplier,
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedSupplier = selected;

        // 💡 Smart default: Auto-update tax treatment based on supplier
        // Only update if still in initial state (noTax), don't override user's manual selection
        if (_taxTreatment == TaxTreatment.noTax && _lineEntries.isEmpty) {
          _taxTreatment = selected.defaultTaxTreatment;

          // Show hint to user
          final taxLabel = _taxTreatment == TaxTreatment.taxIncluded
              ? 'IVA Incluido (19%)'
              : 'Sin IVA';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('💡 Tratamiento tributario sugerido: $taxLabel'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    }
  }

  Future<shared_supplier.Supplier?> _createQuickSupplier(String name) async {
    if (name.trim().isEmpty) return null;
    try {
      final supplier = await _purchaseService.createSupplier(name.trim());
      _supplierCache = [..._supplierCache, supplier];
      return supplier;
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error al crear proveedor: $e'),
            backgroundColor: Colors.red),
      );
      return null;
    }
  }

  Future<void> _pickDate({required bool isIssueDate}) async {
    final initial = isIssueDate
        ? _issueDate
        : (_dueDate ?? _issueDate.add(const Duration(days: 30)));

    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: isIssueDate ? 'Fecha de emisión' : 'Fecha de vencimiento',
    );
    if (selected == null) return;

    setState(() {
      if (isIssueDate) {
        _issueDate = selected;
        if (_dueDate != null && _dueDate!.isBefore(_issueDate)) {
          _dueDate = _issueDate.add(const Duration(days: 30));
        }
      } else {
        _dueDate = selected.isBefore(_issueDate)
            ? _issueDate.add(const Duration(days: 30))
            : selected;
      }
    });
  }

  Future<void> _saveInvoice() async {
    if (_selectedSupplier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona o crea un proveedor antes de guardar.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_lineEntries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega al menos un producto a la factura.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final items = _lineEntries
        .where((entry) => entry.line.quantity > 0)
        .map((entry) => entry.line)
        .toList();

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay líneas válidas para guardar.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final tenantService = context.read<TenantService>();
    final tenantId = await tenantService.getTenantId();

    if (tenantId == null) {
      throw Exception('No tenant found. Please log in again.');
    }

    // For NEW invoices (no ID yet), generate the ACTUAL number now
    // This is when the counter actually increments
    String invoiceNumber = _invoiceNumberController.text.trim();
    if (_loadedInvoice?.id == null && widget.invoiceId == null) {
      invoiceNumber = await _generatePurchaseInvoiceNumber();
      _invoiceNumberController.text = invoiceNumber;
    }

    final invoice = PurchaseInvoice(
      id: _loadedInvoice?.id,
      tenantId: tenantId,
      invoiceNumber: invoiceNumber,
      supplierId: _selectedSupplier!.id,
      supplierName: _selectedSupplier!.name,
      supplierRut: _selectedSupplier!.rut,
      date: _issueDate,
      dueDate: _dueDate,
      reference: _referenceController.text.trim().isEmpty
          ? null
          : _referenceController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      status: _status,
      subtotal: _subtotal,
      ivaAmount: _iva,
      total: _total,
      taxTreatment: _taxTreatment,
      netAmount: _netAmount,
      items: items,
      // Use the form's payment model state
      prepaymentModel: _isPrepaymentModel,
    );

    debugPrint('🔍 Save: prepaymentModel = ${invoice.prepaymentModel}');

    setState(() => _isSaving = true);

    try {
      await _purchaseService.savePurchaseInvoice(invoice);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factura de compra guardada correctamente'),
          backgroundColor: Colors.green,
        ),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la factura: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteInvoice() async {
    if (widget.invoiceId == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('Eliminar factura'),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar la factura '
          '${_invoiceNumberController.text}?\n\n'
          'Esta acción no se puede deshacer.\n\n'
          'Nota: Solo se pueden eliminar facturas en estado Borrador.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sí, eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isUpdatingStatus = true);

    try {
      await _purchaseService.deletePurchaseInvoice(widget.invoiceId!);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Factura eliminada correctamente'),
          backgroundColor: Colors.green,
        ),
      );

      // Return to list page
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  /// Generic status update method (similar to sales invoice)
  Future<void> _updateStatus(PurchaseInvoiceStatus newStatus) async {
    if (widget.invoiceId == null) return;

    setState(() => _isUpdatingStatus = true);

    try {
      // Update status via service
      final updated = await _purchaseService.updateInvoiceStatus(
        widget.invoiceId!,
        newStatus,
      );

      if (!mounted) return;

      if (updated != null) {
        setState(() {
          _status = updated.status;
          _loadedInvoice = updated;
        });
      }

      String message;
      switch (newStatus) {
        case PurchaseInvoiceStatus.sent:
          message = 'Factura enviada al proveedor';
          break;
        case PurchaseInvoiceStatus.confirmed:
          message = 'Factura confirmada';
          break;
        case PurchaseInvoiceStatus.received:
          message = 'Factura marcada como recibida. Inventario actualizado.';
          break;
        case PurchaseInvoiceStatus.draft:
          message = 'Factura revertida a borrador';
          break;
        default:
          message = 'Estado actualizado';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar estado: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingStatus = false);
      }
    }
  }

  /// Navigate to payment form (similar to sales invoice)
  Future<void> _openPaymentForm() async {
    final invoiceId = widget.invoiceId;
    if (invoiceId == null) {
      return;
    }

    final didRegisterPayment = await context.push<bool>(
          '/purchases/invoices/$invoiceId/payment',
        ) ??
        false;

    if (didRegisterPayment && mounted) {
      await _refreshInvoiceById(invoiceId);
    }
  }

  /// Undo last payment (similar to sales invoice)
  Future<void> _undoLastPayment() async {
    final invoiceId = widget.invoiceId;
    if (invoiceId == null) {
      return;
    }

    // Get all payments for this invoice
    final payments = await _purchaseService.getPaymentsForInvoice(invoiceId);
    if (payments.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay pagos para deshacer'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Get the last payment (most recent)
    payments.sort((a, b) => b.date.compareTo(a.date));
    final lastPayment = payments.first;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deshacer pago'),
        content: Text(
          'Se eliminará el pago de ${ChileanUtils.formatCurrency(lastPayment.amount)} '
          'y su asiento contable asociado.\n\n'
          'El estado de la factura se revertirá automáticamente. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Eliminar pago'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await _purchaseService.deletePayment(lastPayment.id!);
      if (mounted) {
        await _refreshInvoiceById(invoiceId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago eliminado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al eliminar el pago: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Refresh invoice after payment changes
  Future<void> _refreshInvoiceById(String invoiceId) async {
    try {
      final invoices =
          await _purchaseService.getPurchaseInvoices(forceRefresh: true);
      final updated = invoices.firstWhere((inv) => inv.id == invoiceId);

      if (mounted) {
        setState(() {
          _status = updated.status;
          _loadedInvoice = updated;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing invoice: $e');
    }
  }

  void _removeLine(_PurchaseLineEntry entry) {
    setState(() {
      _lineEntries.remove(entry);
      entry.dispose();

      // Prevent empty state: If list becomes empty, auto-add a new line
      if (_lineEntries.isEmpty) {
        _addEmptyLine(shouldAutoFocus: true);
      }
    });
    _recalculateTotals();
  }

  void _moveLineUp(_PurchaseLineEntry entry) {
    final index = _lineEntries.indexOf(entry);
    if (index <= 0) return;
    setState(() {
      _lineEntries.removeAt(index);
      _lineEntries.insert(index - 1, entry);
    });
  }

  void _moveLineDown(_PurchaseLineEntry entry) {
    final index = _lineEntries.indexOf(entry);
    if (index < 0 || index >= _lineEntries.length - 1) return;
    setState(() {
      _lineEntries.removeAt(index);
      _lineEntries.insert(index + 1, entry);
    });
  }

  void _addEmptyLine({bool shouldAutoFocus = false}) {
    if (!_canEditFields) return;

    final entry = _PurchaseLineEntry(
      line: PurchaseInvoiceItem(
        productId: '',
        productName: '',
        productSku: null,
        quantity: 1,
        unitCost: 0,
        discount: 0,
        ivaRate: _ivaRate,
      ),
      shouldAutoFocus: shouldAutoFocus,
    );
    entry.attachListeners(_recalculateTotals);

    setState(() {
      _lineEntries.add(entry);
    });
  }

  void _autoAddEmptyLineIfNeeded() {
    // Check if the last line has a product selected
    if (_lineEntries.isEmpty) return;

    final lastEntry = _lineEntries.last;
    if (lastEntry.line.productName?.isNotEmpty ?? false) {
      // Last line is filled, add a new empty line with auto-focus
      _addEmptyLine(shouldAutoFocus: true);
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    debugPrint(
        '🎨 PurchaseInvoiceFormPage.build() called, _isLoading = $_isLoading');
    return MainLayout(
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            _buildHeader(Theme.of(context)),
            Expanded(
              child: _isLoading
                  ? const Center(child: BrandedLoading())
                  : _buildForm(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final title = widget.invoiceId == null
        ? 'Nueva factura de compra'
        : 'Factura ${_invoiceNumberController.text}';

    // Helper to build the action buttons (Scanner, OCR, Save)
    List<Widget> buildEditActions() {
      if (widget.readOnly || !_canEditFields) return [];
      return [
        // OCR Scanner Button
        IconButton(
          onPressed: _openOCRScanner,
          icon: const Icon(Icons.document_scanner_outlined),
          tooltip: 'Escanear Factura (OCR)',
          style: IconButton.styleFrom(
            backgroundColor: Colors.blue.withOpacity(0.1),
          ),
        ),
        const SizedBox(width: 8),
        // Barcode Scanner Button
        IconButton(
          onPressed: _toggleScanner,
          icon: Icon(
            _scannerEnabled
                ? Icons.qr_code_scanner
                : Icons.qr_code_scanner_outlined,
            color: _scannerEnabled ? Colors.green : null,
          ),
          tooltip: _scannerEnabled ? 'Desactivar Escáner' : 'Activar Escáner',
          style: IconButton.styleFrom(
            backgroundColor:
                _scannerEnabled ? Colors.green.withOpacity(0.1) : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 0, // Don't force expand in Row, but allow in Column if needed
          child: AppButton(
            text: 'Guardar',
            icon: Icons.save,
            onPressed: _isSaving ? null : _saveInvoice,
            isLoading: _isSaving,
          ),
        ),
      ];
    }

    // Helper to build status/workflow actions
    List<Widget> buildWorkflowActions() {
      final actionButtons = <Widget>[];

      if (!widget.readOnly && widget.invoiceId != null) {
        // Use form's payment model state
        final isPrepayment = _isPrepaymentModel;

        if (_status == PurchaseInvoiceStatus.draft) {
          // Draft: Can edit (if not editing), send to supplier, or delete

          // Show "Editar" button when viewing draft (not editing)
          if (!_isEditing) {
            actionButtons.add(
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _isEditing = true;
                  });
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar'),
              ),
            );
            actionButtons.add(const SizedBox(width: 8));
          }

          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _deleteInvoice,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label:
                  const Text('Eliminar', style: TextStyle(color: Colors.red)),
            ),
          );
          actionButtons.add(const SizedBox(width: 8));
          actionButtons.add(
            FilledButton.icon(
              onPressed: _isUpdatingStatus
                  ? null
                  : () => _updateStatus(PurchaseInvoiceStatus.sent),
              icon: _isUpdatingStatus
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: const Text('Enviar'),
            ),
          );
        } else if (_status == PurchaseInvoiceStatus.sent) {
          // Sent: Can revert to draft or confirm
          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _isUpdatingStatus
                  ? null
                  : () => _updateStatus(PurchaseInvoiceStatus.draft),
              icon: const Icon(Icons.undo_outlined),
              label: const Text('Volver a borrador'),
            ),
          );
          actionButtons.add(const SizedBox(width: 8));
          actionButtons.add(
            FilledButton.icon(
              onPressed: _isUpdatingStatus
                  ? null
                  : () => _updateStatus(PurchaseInvoiceStatus.confirmed),
              icon: _isUpdatingStatus
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Confirmar'),
            ),
          );
        } else if (_status == PurchaseInvoiceStatus.confirmed) {
          // Confirmed: Next step depends on prepayment model
          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _isUpdatingStatus
                  ? null
                  : () => _updateStatus(PurchaseInvoiceStatus.sent),
              icon: const Icon(Icons.undo_outlined),
              label: const Text('Volver a enviado'),
            ),
          );
          actionButtons.add(const SizedBox(width: 8));

          if (isPrepayment) {
            // Prepayment: Pay first, then receive
            actionButtons.add(
              FilledButton.icon(
                onPressed: _openPaymentForm,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Registrar pago'),
              ),
            );
          } else {
            // Standard: Receive first, then pay
            actionButtons.add(
              FilledButton.icon(
                onPressed: _isUpdatingStatus
                    ? null
                    : () => _updateStatus(PurchaseInvoiceStatus.received),
                icon: _isUpdatingStatus
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.inventory_2_outlined),
                label: const Text('Marcar como recibida'),
              ),
            );
          }
        } else if (_status == PurchaseInvoiceStatus.received) {
          // Received (standard workflow): Can register payment
          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _isUpdatingStatus
                  ? null
                  : () => _updateStatus(PurchaseInvoiceStatus.confirmed),
              icon: const Icon(Icons.undo_outlined),
              label: const Text('Volver a confirmado'),
            ),
          );
          actionButtons.add(const SizedBox(width: 8));
          actionButtons.add(
            FilledButton.icon(
              onPressed: _openPaymentForm,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Registrar pago'),
            ),
          );
        } else if (_status == PurchaseInvoiceStatus.paid) {
          // Paid: Can undo payment or mark as received (prepayment only)
          final isPrepayment = _isPrepaymentModel;

          actionButtons.add(
            OutlinedButton.icon(
              onPressed: _undoLastPayment,
              icon: const Icon(Icons.undo_outlined, color: Colors.red),
              label: const Text('Deshacer pago',
                  style: TextStyle(color: Colors.red)),
            ),
          );

          if (isPrepayment) {
            // Prepayment workflow: After payment, can mark as received
            actionButtons.add(const SizedBox(width: 8));
            actionButtons.add(
              FilledButton.icon(
                onPressed: _isUpdatingStatus
                    ? null
                    : () => _updateStatus(PurchaseInvoiceStatus.received),
                icon: _isUpdatingStatus
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.inventory_2_outlined),
                label: const Text('Marcar como recibida'),
              ),
            );
          }
        }
      }

      // Add status chip and total badge if not new
      final widgets = <Widget>[];
      if (widget.invoiceId != null) {
        widgets.add(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.payments_outlined,
                    size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  ChileanUtils.formatCurrency(_total),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        );
        widgets.add(_buildStatusChip(theme));
      }
      widgets.addAll(actionButtons);
      return widgets;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        if (isMobile) {
          // Mobile Layout: Stacked
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        if (widget.referrer == 'movements') {
                          context.go('/inventory/movements');
                        } else {
                          context.pop();
                        }
                      },
                      icon: const Icon(Icons.arrow_back),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 20, // Slightly smaller on mobile
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 36), // Align with title
                  child: Text(
                    _isPrepaymentModel
                        ? 'Prepago: pagar antes de recibir'
                        : 'Estándar: recibir antes de pagar',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Actions in a horizontal scroll if needed, or wrapped
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...buildEditActions(),
                      if (buildEditActions().isNotEmpty &&
                          buildWorkflowActions().isNotEmpty)
                        const SizedBox(width: 12),
                      ...buildWorkflowActions().map((w) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: w,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          // Desktop/Tablet Layout: Row
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    if (widget.referrer == 'movements') {
                      context.go('/inventory/movements');
                    } else {
                      context.pop();
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Volver',
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isPrepaymentModel
                            ? 'Prepago: pagar antes de recibir mercancía'
                            : 'Flujo estándar: recibir y luego pagar',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ...buildEditActions(),
                const SizedBox(width: 16),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: buildWorkflowActions(),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    final color = _statusColor(theme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _status.displayName,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _statusColor(ThemeData theme) {
    switch (_status) {
      case PurchaseInvoiceStatus.draft:
        return Colors.grey;
      case PurchaseInvoiceStatus.sent:
        return Colors.orange;
      case PurchaseInvoiceStatus.confirmed:
        return Colors.purple;
      case PurchaseInvoiceStatus.received:
        return Colors.green;
      case PurchaseInvoiceStatus.paid:
        return Colors.blue;
      case PurchaseInvoiceStatus.cancelled:
        return Colors.red;
    }
  }

  /// Build payment model toggle (Prepayment vs Standard)
  Widget _buildPaymentModelToggle(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.swap_horiz,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Modelo de pago',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('Prepago'),
                icon: Icon(Icons.payment),
              ),
              ButtonSegment(
                value: false,
                label: Text('Estándar'),
                icon: Icon(Icons.local_shipping),
              ),
            ],
            selected: {_isPrepaymentModel},
            onSelectionChanged: (selection) {
              setState(() {
                _isPrepaymentModel = selection.first;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            _isPrepaymentModel
                ? 'Pagar primero, recibir después (importaciones, transferencias)'
                : 'Recibir primero, pagar después (proveedores locales)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1180;
        if (isWide) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Payment model toggle (only for new invoices or draft)
                        if (_canEditFields) _buildPaymentModelToggle(theme),
                        if (_canEditFields) const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.store_outlined,
                          title: 'Proveedor',
                          children: [_buildSupplierSection(theme)],
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.shopping_basket_outlined,
                          title: 'Productos y servicios',
                          children: [_buildLineItemsSection(theme)],
                        ),
                        const SizedBox(height: 16),
                        _buildSectionCard(
                          theme,
                          icon: Icons.notes_outlined,
                          title: 'Referencia',
                          children: [_buildReferenceSection(theme)],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildSectionCard(
                          theme,
                          icon: Icons.calendar_today_outlined,
                          title: 'Fechas y estado',
                          children: [_buildInvoiceMetaSection(theme)],
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryCard(theme),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          // Narrow layout: stack vertically
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Payment model toggle (only for new invoices or draft)
                if (_canEditFields) _buildPaymentModelToggle(theme),
                if (_canEditFields) const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.store_outlined,
                  title: 'Proveedor',
                  children: [_buildSupplierSection(theme)],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.calendar_today_outlined,
                  title: 'Fechas y estado',
                  children: [_buildInvoiceMetaSection(theme)],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.shopping_basket_outlined,
                  title: 'Productos y servicios',
                  children: [_buildLineItemsSection(theme)],
                ),
                const SizedBox(height: 16),
                _buildSectionCard(
                  theme,
                  icon: Icons.notes_outlined,
                  title: 'Referencia',
                  children: [_buildReferenceSection(theme)],
                ),
                const SizedBox(height: 16),
                _buildSummaryCard(theme),
                const SizedBox(height: 32),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildSectionCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
                  child: Icon(icon, color: theme.colorScheme.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _invoiceNumberController,
          enabled: _canEditFields,
          decoration: const InputDecoration(
            labelText: 'Número de factura',
            helperText: 'Puedes modificar el folio si tu numeración es manual',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Ingresa un número de factura';
            }
            return null;
          },
        ),
        const SizedBox(height: 20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: _selectedSupplier == null
                ? theme.colorScheme.surfaceVariant
                : theme.colorScheme.primary.withOpacity(0.12),
            child: Icon(
              Icons.store,
              color: _selectedSupplier == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
          ),
          title: Text(_selectedSupplier?.name ?? 'Selecciona un proveedor'),
          subtitle: _selectedSupplier != null && _selectedSupplier!.rut != null
              ? Text('RUT: ${ChileanUtils.formatRut(_selectedSupplier!.rut!)}')
              : const Text('Necesario para facturación y reportes'),
          trailing: FilledButton.tonalIcon(
            onPressed: _canEditFields ? _openSupplierSelector : null,
            icon: Icon(_selectedSupplier == null ? Icons.search : Icons.edit,
                size: 18),
            label: Text(
                _selectedSupplier == null ? 'Buscar proveedor' : 'Cambiar'),
          ),
        ),
      ],
    );
  }

  Widget _buildInvoiceMetaSection(ThemeData theme) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_note),
          title: const Text('Fecha de emisión'),
          subtitle: Text(ChileanUtils.formatDate(_issueDate)),
          trailing: TextButton(
            onPressed:
                _canEditFields ? () => _pickDate(isIssueDate: true) : null,
            child: const Text('Cambiar'),
          ),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Fecha de vencimiento'),
          subtitle: Text(ChileanUtils.formatDate(
              _dueDate ?? _issueDate.add(const Duration(days: 30)))),
          trailing: TextButton(
            onPressed:
                _canEditFields ? () => _pickDate(isIssueDate: false) : null,
            child: const Text('Cambiar'),
          ),
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Estado de la factura'),
          subtitle: Text(_statusDisplayName(_status)),
          trailing: _status == PurchaseInvoiceStatus.draft
              ? Text(
                  _canEditFields ? 'Editando' : 'Solo lectura',
                  style: theme.textTheme.labelMedium,
                )
              : null,
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.receipt_long_outlined,
            color: _taxTreatment == TaxTreatment.taxIncluded
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: const Text('Tratamiento de IVA'),
          subtitle: DropdownButtonFormField<TaxTreatment>(
            isExpanded: true,
            value: _taxTreatment,
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: _canEditFields
                  ? null
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            ),
            items: const [
              DropdownMenuItem(
                value: TaxTreatment.noTax,
                child: Text('Sin IVA (exento o no afecto)'),
              ),
              DropdownMenuItem(
                value: TaxTreatment.taxIncluded,
                child: Text('IVA Incluido en precio (19%)'),
              ),
            ],
            onChanged: _canEditFields
                ? (value) {
                    if (value != null) {
                      setState(() => _taxTreatment = value);
                    }
                  }
                : null,
          ),
        ),
      ],
    );
  }

  String _statusDisplayName(PurchaseInvoiceStatus status) {
    switch (status) {
      case PurchaseInvoiceStatus.draft:
        return 'Borrador';
      case PurchaseInvoiceStatus.sent:
        return 'Enviada';
      case PurchaseInvoiceStatus.confirmed:
        return 'Confirmada';
      case PurchaseInvoiceStatus.received:
        return 'Recibida';
      case PurchaseInvoiceStatus.paid:
        return 'Pagada';
      case PurchaseInvoiceStatus.cancelled:
        return 'Cancelada';
    }
  }

  Widget _buildLineItemsSection(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Mobile Breakpoint for Form Items
        if (constraints.maxWidth < 700) {
          return Column(
            children: [
              if (_lineEntries.isNotEmpty)
                ..._lineEntries.asMap().entries.map((entry) =>
                    _buildMobileItemCard(theme, entry.key + 1, entry.value)),
              if (_canEditFields) ...[
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => _addEmptyLine(shouldAutoFocus: true),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color:
                          theme.colorScheme.primaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline,
                            size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Agregar producto',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_lineEntries.isEmpty && !_canEditFields)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.remove_shopping_cart_outlined,
                            size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 16),
                        Text(
                          'No hay artículos',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        }

        // Desktop Table View (Existing Logic)
        const minTableWidth = 800.0;
        final tableWidth = constraints.maxWidth > minTableWidth
            ? constraints.maxWidth
            : minTableWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Table header
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(7),
                        topRight: Radius.circular(7),
                      ),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // # column
                          Container(
                            width: _colIndexWidth,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withOpacity(0.2)),
                              ),
                            ),
                            child: Center(
                              child: Text('#',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Product details column (expandable)
                          Expanded(
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 250),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                      color: theme.colorScheme.outline
                                          .withOpacity(0.2)),
                                ),
                              ),
                              child: Text('DETALLES DEL ARTÍCULO',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Cantidad column
                          Container(
                            width: _colQuantityWidth,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withOpacity(0.2)),
                              ),
                            ),
                            child: Center(
                              child: Text('CANTIDAD',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Tarifa column
                          Container(
                            width: _colPriceWidth,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withOpacity(0.2)),
                              ),
                            ),
                            child: Center(
                              child: Text('TARIFA',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Descuento column
                          Container(
                            width: _colDiscountWidth,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withOpacity(0.2)),
                              ),
                            ),
                            child: Center(
                              child: Text('DESCUENTO',
                                  style: theme.textTheme.labelSmall
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                            ),
                          ),

                          // Importe column
                          Container(
                            width: _colTotalWidth,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            child: Text('IMPORTE',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                textAlign: TextAlign.right),
                          ),

                          // Actions column
                          SizedBox(width: _colActionsWidth),
                        ],
                      ),
                    ),
                  ),

                  // Header/Content divider
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: theme.colorScheme.outline.withOpacity(0.2)),

                  // Line items
                  Column(
                    children: [
                      // Existing line items - using same pattern as sales invoice
                      if (_lineEntries.isNotEmpty)
                        ..._lineEntries.asMap().entries.map((entry) =>
                            _buildCompactLineRow(
                                theme, entry.key + 1, entry.value)),

                      // Manual Add Line Button
                      if (_canEditFields)
                        InkWell(
                          onTap: () => _addEmptyLine(shouldAutoFocus: true),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme
                                  .surface, // Background for contrast
                              border: Border(
                                top: BorderSide(
                                    color: theme.colorScheme.outline
                                        .withOpacity(0.2)),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_circle_outline,
                                    size: 18, color: theme.colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Agregar línea',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Empty state
                      if (_lineEntries.isEmpty && !_canEditFields)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            'No hay artículos en esta factura de compra',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileItemCard(
      ThemeData theme, int index, _PurchaseLineEntry entry) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Header with Product Name and Delete Action
          Container(
            padding: const EdgeInsets.all(12),
            color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: entry.buildSmartProductField(
                    context,
                    theme,
                    _canEditFields,
                    () {},
                    () => _autoAddEmptyLineIfNeeded(),
                  ),
                ),
                if (_canEditFields)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: theme.colorScheme.error,
                    onPressed: () => _removeLine(entry),
                  ),
              ],
            ),
          ),

          // Details Grid (Qty, Price, Discount, Total)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    // Quantity
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Cantidad', style: theme.textTheme.labelSmall),
                          const SizedBox(height: 4),
                          _canEditFields
                              ? SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: entry.quantityController,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      contentPadding:
                                          EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : Text(entry.quantityController.text,
                                  style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Price
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Costo Unit.',
                              style: theme.textTheme.labelSmall),
                          const SizedBox(height: 4),
                          _canEditFields
                              ? SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: entry.unitCostController,
                                    decoration: const InputDecoration(
                                      border: OutlineInputBorder(),
                                      prefixText: '\$',
                                      contentPadding:
                                          EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textAlign: TextAlign.right,
                                  ),
                                )
                              : Text(
                                  ChileanUtils.formatCurrency(
                                      entry.line.unitCost),
                                  style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Discount
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Descuento', style: theme.textTheme.labelSmall),
                          const SizedBox(height: 4),
                          _canEditFields
                              ? SizedBox(
                                  height: 40,
                                  child: TextField(
                                    controller: entry.discountController,
                                    decoration: InputDecoration(
                                      border: const OutlineInputBorder(),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8),
                                      suffixIcon: InkWell(
                                        onTap: () {
                                          setState(() {
                                            entry.toggleDiscountType();
                                            _recalculateTotals();
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Text(
                                            entry.discountType ==
                                                    DiscountType.amount
                                                ? '\$'
                                                : '%',
                                            style: TextStyle(
                                              color: theme.colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : Text(
                                  '${entry.discountController.text} ${entry.discountType == DiscountType.amount ? '\$' : '%'}',
                                  style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Total
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Total Línea',
                              style: theme.textTheme.labelSmall),
                          const SizedBox(height: 4),
                          Container(
                            alignment: Alignment.centerRight,
                            height: 40, // Height matching input fields
                            child: Text(
                              ChileanUtils.formatCurrency(
                                  entry.line.netAmountClamped),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a single line row using the universal LineRowWrapper.
  /// Hover state is managed locally inside the wrapper, preventing SmartProductField rebuilds.
  Widget _buildCompactLineRow(
      ThemeData theme, int index, _PurchaseLineEntry entry) {
    final line = entry.line;

    return LineRowWrapper(
      key: ValueKey('line_${entry.hashCode}_$index'),
      index: index,
      canMoveUp: index > 1 && _canEditFields,
      canMoveDown: index < _lineEntries.length && _canEditFields,
      onMoveUp: () => _moveLineUp(entry),
      onMoveDown: () => _moveLineDown(entry),
      onRemove: () => _removeLine(entry),
      canEdit: _canEditFields,
      indexColumnWidth: _colIndexWidth,
      actionsColumnWidth: _colActionsWidth,
      columns: [
        // Product details column - uses CACHED widget from entry
        LineColumn(
          expanded: true,
          minWidth: 250,
          padding: const EdgeInsets.all(12),
          child: entry.buildSmartProductField(
            context,
            theme,
            _canEditFields,
            () {}, // No setState needed - hover is local to wrapper
            () => _autoAddEmptyLineIfNeeded(),
          ),
        ),

        // Cantidad column
        LineColumn(
          width: _colQuantityWidth,
          child: _canEditFields
              ? TextField(
                  controller: entry.quantityController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                )
              : Center(
                  child: Text(
                    entry.quantityController.text,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
        ),

        // Precio column
        LineColumn(
          width: _colPriceWidth,
          child: _canEditFields
              ? TextField(
                  controller: entry.unitCostController,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                    prefixText: '\$',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium,
                )
              : Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    ChileanUtils.formatCurrency(line.unitCost),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
        ),

        // Descuento column
        LineColumn(
          width: _colDiscountWidth,
          child: _canEditFields
              ? TextField(
                  controller: entry.discountController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    isDense: true,
                    suffixIcon: InkWell(
                      onTap: () {
                        setState(() {
                          entry.toggleDiscountType();
                          // Trigger recalculation in UI
                          _recalculateTotals();
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Text(
                          entry.discountType == DiscountType.amount
                              ? '\$'
                              : '%',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                )
              : Center(
                  child: Text(
                    entry.discountController.text,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
        ),

        // Importe/Total column (no right border - last content column)
        LineColumn(
          width: _colTotalWidth,
          showRightBorder: false,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              ChileanUtils.formatCurrency(line.netAmountClamped),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReferenceSection(ThemeData theme) {
    return Column(
      children: [
        TextFormField(
          controller: _referenceController,
          enabled: _canEditFields,
          decoration: const InputDecoration(
            labelText: 'Referencia (opcional)',
            hintText: 'Ej: Orden de compra, guía de despacho...',
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notesController,
          enabled: _canEditFields,
          decoration: const InputDecoration(
            labelText: 'Notas internas (opcional)',
            hintText: 'Observaciones adicionales...',
            alignLabelWithHint: true,
          ),
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildSummaryCard(ThemeData theme) {
    return _buildSectionCard(
      theme,
      icon: Icons.calculate_outlined,
      title: 'Resumen',
      children: [_buildSummary(theme)],
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final textStyle =
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    return Column(
      children: [
        // For purchases: Always show subtotal (net amount)
        _buildSummaryRow('Subtotal (Neto)',
            ChileanUtils.formatCurrency(_subtotal), textStyle, theme),
        // Show IVA row when tax is included
        if (_taxTreatment == TaxTreatment.taxIncluded) ...[
          const SizedBox(height: 8),
          _buildSummaryRow(
              'IVA (19%)',
              ChileanUtils.formatCurrency(_iva),
              textStyle?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              theme),
        ],
        const Divider(height: 24),
        _buildSummaryRow(
          'Total',
          ChileanUtils.formatCurrency(_total),
          theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.primary,
          ),
          theme,
        ),
      ],
    );
  }

  Widget _buildSummaryRow(
      String label, String value, TextStyle? style, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Text(value, style: style),
      ],
    );
  }
}

enum DiscountType { amount, percentage }

class _PurchaseLineEntry {
  _PurchaseLineEntry(
      {required PurchaseInvoiceItem line, this.shouldAutoFocus = false})
      : line = line,
        quantityController =
            TextEditingController(text: line.quantity.toStringAsFixed(0)),
        unitCostController =
            TextEditingController(text: line.unitCost.toStringAsFixed(0)),
        discountController =
            TextEditingController(text: line.discount.toStringAsFixed(0)),
        productNameController =
            TextEditingController(text: line.productName ?? ''),
        productSkuController =
            TextEditingController(text: line.productSku ?? ''),
        descriptionController = TextEditingController(),
        productNameFocusNode = FocusNode();

  PurchaseInvoiceItem line;
  Product? product; // Store full product for image access
  /// Whether this line's product field should auto-focus (for newly added lines)
  bool shouldAutoFocus;
  DiscountType discountType = DiscountType.amount; // Default to amount

  final TextEditingController quantityController;
  final TextEditingController unitCostController;
  final TextEditingController discountController;
  final TextEditingController productNameController;
  final TextEditingController productSkuController;
  final TextEditingController descriptionController;
  final FocusNode productNameFocusNode;

  void toggleDiscountType() {
    discountType = discountType == DiscountType.amount
        ? DiscountType.percentage
        : DiscountType.amount;

    // Recalculate discount based on new type and current input
    recalculateDiscount();
  }

  void recalculateDiscount() {
    final inputValue =
        double.tryParse(discountController.text.replaceAll(',', '.')) ?? 0;

    if (inputValue < 0) return;

    double calculatedDiscount = 0;
    if (discountType == DiscountType.amount) {
      calculatedDiscount = inputValue;
    } else {
      // Percentage: (qty * unitCost) * (percentage / 100)
      final totalAmount = line.quantity * line.unitCost;
      calculatedDiscount = totalAmount * (inputValue / 100);
    }

    line = line.copyWith(discount: calculatedDiscount);
  }

  void attachListeners(VoidCallback onChanged) {
    quantityController.addListener(() {
      final value =
          double.tryParse(quantityController.text.replaceAll(',', '.'));
      if (value != null && value >= 0) {
        line = line.copyWith(quantity: value);
        // Recalculate discount if it's percentage based (depends on total)
        if (discountType == DiscountType.percentage) {
          recalculateDiscount();
        }
        onChanged();
      }
    });
    unitCostController.addListener(() {
      final value =
          double.tryParse(unitCostController.text.replaceAll(',', '.'));
      if (value != null && value >= 0) {
        line = line.copyWith(unitCost: value);
        // Recalculate discount if it's percentage based (depends on total)
        if (discountType == DiscountType.percentage) {
          recalculateDiscount();
        }
        onChanged();
      }
    });
    discountController.addListener(() {
      recalculateDiscount();
      onChanged();
    });
    // ❌ DON'T listen to productNameController - it causes auto-selection on every keystroke
    // Product name is updated ONLY when onProductSelected is called in ProductAutocompleteField
    productSkuController.addListener(() {
      line = line.copyWith(productSku: productSkuController.text);
      onChanged();
    });
  }

  void dispose() {
    quantityController.dispose();
    unitCostController.dispose();
    discountController.dispose();
    productNameController.dispose();
    productSkuController.dispose();
    descriptionController.dispose();
    productNameFocusNode.dispose();
  }

  // CRITICAL: Cache the SmartProductField widget to prevent rebuilds on parent hover state changes
  // This is the fix for flickering and disappearing dropdown when mouse moves
  Widget? _cachedSmartProductField;
  bool? _cachedCanEdit;

  /// Build the SmartProductField for this line entry
  /// This method lives on the entry (not the row widget state) to prevent
  /// row hover state changes from rebuilding the field
  Widget buildSmartProductField(
    BuildContext context,
    ThemeData theme,
    bool canEdit,
    VoidCallback onUpdate,
    VoidCallback onAutoAdd,
  ) {
    // Return cached widget if nothing meaningful changed
    // Only rebuild if canEdit changes (not on hover which doesn't change canEdit)
    if (_cachedSmartProductField != null && _cachedCanEdit == canEdit) {
      return _cachedSmartProductField!;
    }

    _cachedCanEdit = canEdit;
    _cachedSmartProductField = SmartProductField(
      key: ValueKey('product_${hashCode}'),
      initialData: ProductFieldData(
        product: product,
        productName:
            line.productName?.isEmpty ?? true ? null : line.productName,
        productSku: line.productSku?.isEmpty ?? true ? null : line.productSku,
        isCatalogProduct: line.productId.isNotEmpty,
        description: descriptionController.text,
      ),
      enabled: canEdit,
      showCost: true, // Purchases use cost, not price
      allowCustomItems: true,
      autoFocus: shouldAutoFocus,
      focusNode: productNameFocusNode,
      descriptionController: descriptionController,
      onAutoAddLine: onAutoAdd,
      onEditProduct: (p) => _showEditProductDialog(context, p),
      onShowProductDetails: (p) => _showProductDetailsPane(context, p, theme),
      onProductChanged: (selection) {
        if (selection == null) {
          // Product cleared
          product = null;
          productNameController.clear();
          productSkuController.clear();
          descriptionController.clear();
          line = line.copyWith(
            productId: '',
            productName: '',
            productSku: '',
          );
          onUpdate();
        } else {
          // Product selected or description changed
          product = selection.product;
          productNameController.text = selection.productName ?? '';
          productSkuController.text = selection.productSku ?? '';
          line = line.copyWith(
            productId: selection.product?.id ?? '',
            productName: selection.productName ?? '',
            productSku: selection.productSku,
            unitCost: selection.price > 0 ? selection.price : line.unitCost,
          );
          if (selection.price > 0) {
            unitCostController.text = selection.price.toStringAsFixed(0);
          }
          onUpdate();
        }
      },
    );

    return _cachedSmartProductField!;
  }

  void _showEditProductDialog(BuildContext context, Product product) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ProductFormPage(productId: product.id, showInDialog: true),
          ),
        ),
      ),
    );
  }

  void _showProductDetailsPane(
      BuildContext context, Product product, ThemeData theme) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Product Details',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            child: Container(
              width: 400,
              height: double.infinity,
              color: theme.scaffoldBackgroundColor,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Detalles del Producto',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.imageUrl != null)
                            Center(
                              child: Image.network(
                                product.imageUrl!,
                                height: 200,
                                fit: BoxFit.contain,
                              ),
                            ),
                          const SizedBox(height: 16),
                          Text(product.name, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 8),
                          Text('SKU: ${product.sku}'),
                          Text('Costo: \$${product.cost.toStringAsFixed(0)}'),
                          Text('Precio: \$${product.price.toStringAsFixed(0)}'),
                          Text('Stock: ${product.stockQuantity}'),
                          if (product.description != null) ...[
                            const SizedBox(height: 16),
                            Text('Descripción:',
                                style: theme.textTheme.titleSmall),
                            Text(product.description!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SupplierSelector extends StatefulWidget {
  final List<shared_supplier.Supplier> suppliers;
  final Future<shared_supplier.Supplier?> Function(String name)
      onCreateSupplier;

  const _SupplierSelector(
      {required this.suppliers, required this.onCreateSupplier});

  @override
  State<_SupplierSelector> createState() => _SupplierSelectorState();
}

class _SupplierSelectorState extends State<_SupplierSelector> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _newSupplierController = TextEditingController();

  late List<shared_supplier.Supplier> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.suppliers;
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _newSupplierController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.suppliers.where((supplier) {
        return supplier.name.toLowerCase().contains(query) ||
            (supplier.rut?.toLowerCase().contains(query) ?? false) ||
            (supplier.email?.toLowerCase().contains(query) ?? false);
      }).toList();
    });
  }

  Future<void> _handleCreateSupplier() async {
    final name = _newSupplierController.text.trim();
    if (name.isEmpty) return;
    final supplier = await widget.onCreateSupplier(name);
    if (supplier != null && mounted) {
      Navigator.of(context).pop(supplier);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.95,
          initialChildSize: 0.8,
          builder: (context, controller) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Seleccionar proveedor',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SearchBarWidget(
                    controller: _searchController,
                    hintText: 'Buscar por nombre, RUT o email...',
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newSupplierController,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Crear proveedor rápido',
                      hintText: 'Nombre del proveedor',
                      labelStyle: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[700],
                      ),
                      hintStyle: TextStyle(
                        color: isDark ? Colors.grey[500] : Colors.grey[500],
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          Icons.check,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        onPressed: _handleCreateSupplier,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: isDark ? Colors.grey[700]! : Colors.grey[400]!,
                        ),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _handleCreateSupplier(),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No se encontraron proveedores',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              final supplier = _filtered[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[200],
                                  child: Icon(
                                    Icons.store_outlined,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                title: Text(
                                  supplier.name,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (supplier.rut != null &&
                                        supplier.rut!.isNotEmpty)
                                      Text(
                                        'RUT: ${ChileanUtils.formatRut(supplier.rut!)}',
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                        ),
                                      ),
                                    if (supplier.email != null &&
                                        supplier.email!.isNotEmpty)
                                      Text(
                                        supplier.email!,
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.grey[400]
                                              : Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                                onTap: () =>
                                    Navigator.of(context).pop(supplier),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProductSelector extends StatefulWidget {
  final List<Product> products;

  const _ProductSelector({required this.products});

  @override
  State<_ProductSelector> createState() => _ProductSelectorState();
}

class _ProductSelectorState extends State<_ProductSelector> {
  final TextEditingController _searchController = TextEditingController();
  late List<Product> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.products;
    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filtered = widget.products.where((product) {
        final candidates = [
          product.name,
          product.sku,
          product.brand,
          product.model,
        ];
        return candidates.any(
            (value) => value != null && value.toLowerCase().contains(query));
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.95,
          initialChildSize: 0.85,
          builder: (context, controller) {
            final isDark = Theme.of(context).brightness == Brightness.dark;

            return Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Seleccionar producto',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  SearchBarWidget(
                    controller: _searchController,
                    hintText: 'Buscar por nombre, SKU, marca...',
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No se encontraron productos',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              final product = _filtered[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[200],
                                  child: Text(
                                    product.name.isNotEmpty
                                        ? product.name[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color:
                                          isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  product.name,
                                  style: TextStyle(
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SKU: ${product.sku}',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          'Costo: ${ChileanUtils.formatCurrency(product.cost)}',
                                          style: TextStyle(
                                            color: isDark
                                                ? Colors.grey[400]
                                                : Colors.grey[600],
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: product.stockQuantity > 0
                                                ? (isDark
                                                    ? Colors.green[900]
                                                    : Colors.green[100])
                                                : (isDark
                                                    ? Colors.red[900]
                                                    : Colors.red[100]),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            'Stock: ${product.stockQuantity}',
                                            style: TextStyle(
                                              color: product.stockQuantity > 0
                                                  ? (isDark
                                                      ? Colors.green[300]
                                                      : Colors.green[800])
                                                  : (isDark
                                                      ? Colors.red[300]
                                                      : Colors.red[800]),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: Icon(
                                  Icons.chevron_right,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                                onTap: () => Navigator.of(context).pop(product),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
