import 'dart:io' show File;
import 'dart:typed_data';
import 'dart:math' as math;
import 'dart:convert';

import 'dart:async';
import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        defaultTargetPlatform,
        kDebugMode,
        kIsWeb,
        listEquals,
        visibleForTesting;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import 'package:uuid/uuid.dart';

import '../services/ocr_service.dart';
import '../services/ocr_file_handoff_service.dart';
import '../services/ocr_product_resolution_policy.dart';
import '../services/invoice_parser_service.dart';
import '../services/pdf_parser_service.dart';
import '../services/veryfi_proxy_service.dart';
import '../services/veryfi_adapter.dart';
import '../services/inventory_service.dart';
import '../services/image_service.dart';
import '../models/product.dart' show Product, PurchaseTreatment;
import '../models/supplier_variant_resolution.dart';
import '../services/supplier_variant_resolution_service.dart';
import '../services/database_service.dart';
import '../services/tenant_service.dart';
import '../../modules/inventory/services/category_service.dart';
import '../../modules/inventory/models/category_models.dart' show Category;
import '../../modules/inventory/services/inventory_service.dart' as inv_service;
import '../../modules/inventory/models/inventory_models.dart' as inv_models;
import '../../modules/inventory/models/product_duplicate_candidate.dart';
import '../../modules/inventory/services/aliexpress_sku_reservation.dart';
import '../../modules/inventory/services/brand_service.dart';
import '../../modules/inventory/services/product_catalog_semantic_resolver.dart';
import '../../modules/inventory/services/product_duplicate_listing_group_resolver.dart';
import '../../modules/inventory/services/product_duplicate_matcher_service.dart';
import '../../modules/inventory/services/product_identity_review_coordinator.dart';
import '../../modules/inventory/services/product_identity/product_catalog_identity_index.dart';
import '../../modules/inventory/services/product_identity/product_category_resolver.dart';
import '../../modules/inventory/services/product_identity/product_identity_extractor.dart';
import '../../modules/inventory/services/product_identity/product_visual_reading.dart';
import '../../modules/inventory/services/product_identity/supplier_resolution_proposal.dart';
import '../../modules/inventory/services/product_image_fingerprint_service.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../modules/inventory/models/brand_models.dart' show ProductBrand;
import '../../modules/ai_assistant/services/ai_service.dart';
import '../../modules/ai_assistant/services/product_identity_trace.dart';
import '../models/supplier_ocr_template.dart';
import '../themes/vinabike_theme_roles.dart';
import '../utils/chilean_utils.dart';
import 'ocr_candidate_picker.dart';
import 'ocr_product_review_workspace.dart';
import 'vb_notice.dart';
import 'vb_status_badge.dart';
import '../../modules/purchases/services/purchase_service.dart';
import '../../shared/models/supplier.dart' as shared_supplier;
import 'package:provider/provider.dart';

/// Callback when OCR completes successfully
typedef OnOCRComplete = FutureOr<void> Function(ParsedInvoice parsedInvoice);

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

enum _OcrReadSource { veryfi, local, structured }

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
  State<OCRUploadWidget> createState() => OCRUploadWidgetState();
}

class OCRUploadWidgetState extends State<OCRUploadWidget> {
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
  _OcrReadSource _lastReadSource = _OcrReadSource.local;

  // Bulk product creation state
  bool _showBulkCreate = false;
  // A partial AliExpress discovery may exercise the read-only matcher in a
  // debug build, but it must never reserve a SKU, learn an alias, create a
  // product or apply a purchase draft.
  bool _isReadOnlyEvaluation = false;

  /// Whether the current OCR review must actually block business mutations.
  ///
  /// Older debug handoffs marked every daily invoice as evaluation-only even
  /// after the exact-date collector had certified the full source day. During
  /// hot reload that flag remains in the in-memory document. A certified
  /// internal handoff can therefore be promoted safely without rerunning its
  /// image/AI work; a canary or partial discovery remains locked.
  bool get _readOnlyEvaluationBlocksMutations {
    if (!_isReadOnlyEvaluation) return false;
    if (!kDebugMode) return true;
    final rawText = _parsedData?.rawText.trim();
    if (rawText == null || rawText.isEmpty) return true;
    try {
      final decoded = jsonDecode(rawText);
      if (decoded is! Map) return true;
      final invoice = Map<String, dynamic>.from(decoded);
      final rawCoverage = invoice['coverage'];
      if (rawCoverage is! Map) return true;
      final coverage = Map<String, dynamic>.from(rawCoverage);
      return !(coverage['certified'] == true &&
          coverage['targetDateComplete'] == true);
    } catch (_) {
      return true;
    }
  }

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
  String? _supplierIdForNewProducts; // For potential future use
  String? _ocrSupplierName; // Supplier detected by OCR
  shared_supplier.Supplier? _ocrSupplier;
  bool _isSavingSupplierTemplate = false;
  bool _isOpeningBulkCreate = false;
  bool _isApplyingResult = false;
  int _bulkReviewGeneration = 0;
  int _parsedInvoiceEpoch = 0;
  int? _productReviewDraftEpoch;

  /// Owns every `AE0xxx` this review session hands out.
  ///
  /// Reservation authority belongs to one object, not to a map of keys spread
  /// across the widget: the RPC is idempotent *by key*, so any key that is not
  /// row-exact replays one row's answer onto another. The authority binds each
  /// key to the exact row — document, row index, listing, variant — serialises
  /// requests against the shared AE sequence, and refuses a number it has
  /// already issued.
  AliExpressSkuReservationAuthority? _skuReservationAuthority;
  String? _processedInitialFileId;
  final AIAssistantService _aiAssistantService = AIAssistantService();
  final Map<String, Uint8List> _ocrProductImageBytesCache = {};
  final Map<String, Future<Uint8List?>> _ocrProductImageLoads = {};
  final Map<String, Timer> _identityRecomputeTimers = <String, Timer>{};
  List<inv_models.Product>? _productReviewCatalogSnapshot;
  ProductDuplicateMatcherService? _productReviewDuplicateMatcher;
  int? _productReviewCatalogGeneration;
  final Map<String, Future<inv_models.ProductSetCompositionSnapshot?>>
      _productSetCompositionLoads =
      <String, Future<inv_models.ProductSetCompositionSnapshot?>>{};

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

  /// Consumes the next Back level owned by the OCR workflow.
  ///
  /// Product review returns to the parsed-invoice preview. The host owns the
  /// final transition from the OCR root back to the purchase draft.
  bool handleBack() {
    if (blocksOwnerExit) {
      // Consume Back while a guarded operation is in flight. Closing during
      // create/read-back could leave committed products detached from the
      // invoice draft; closing during a reservation strands an `AE0xxx` that
      // the database has already advanced past.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            _anyRowReservingSku && !_creatingProducts && !_isApplyingResult
                ? 'Espera a que termine de reservarse el SKU.'
                : 'Espera a que termine la creación y se vinculen los productos a la factura.',
          ),
        ),
      );
      return true;
    }
    if (_showBulkCreate) {
      _closeBulkReview();
      return true;
    }
    return false;
  }

  /// Whether the host must reject route, workspace and chrome exits.
  ///
  /// Product creation can commit remotely before this widget reconciles the
  /// new products into the invoice draft. Disposing the owner in that window
  /// would leave valid products detached from the operation that created them.
  bool get blocksOwnerExit =>
      _creatingProducts || _isApplyingResult || _anyRowReservingSku;

  void _discardProductReviewDraft({bool advanceDocumentEpoch = false}) {
    _bulkReviewGeneration++;
    for (final timer in _identityRecomputeTimers.values) {
      timer.cancel();
    }
    _identityRecomputeTimers.clear();
    for (final entry in _newProductEntries) {
      entry.dispose();
    }
    _newProductEntries.clear();
    _ocrProductImageBytesCache.clear();
    _ocrProductImageLoads.clear();
    _productReviewCatalogSnapshot = null;
    _productReviewDuplicateMatcher = null;
    _productReviewCatalogGeneration = null;
    _productSetCompositionLoads.clear();
    _productReviewDraftEpoch = null;
    _skuReservationAuthority = null;
    _showBulkCreate = false;
    _isOpeningBulkCreate = false;
    if (advanceDocumentEpoch) _parsedInvoiceEpoch++;
  }

  void _adoptParsedInvoiceDocument({
    required ParsedInvoice base,
    required ParsedInvoice display,
    required shared_supplier.Supplier? supplier,
  }) {
    _discardProductReviewDraft(advanceDocumentEpoch: true);
    _baseParsedData = base;
    _parsedData = display;
    _ocrSupplier = supplier;
    _ocrSupplierName = supplier?.name;
    _supplierIdForNewProducts = supplier?.id;
  }

  Widget _buildUploadScreen() {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final horizontalPadding = compact ? 16.0 : 24.0;
        final secondaryActions = <Widget>[
          OutlinedButton.icon(
            onPressed:
                _isProcessing ? null : () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Tomar foto'),
          ),
          OutlinedButton.icon(
            onPressed:
                _isProcessing ? null : () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Elegir de galería'),
          ),
        ];

        return DropTarget(
          enable: !_isProcessing,
          onDragEntered: (_) => setState(() => _isDraggingInvoiceFile = true),
          onDragExited: (_) => setState(() => _isDraggingInvoiceFile = false),
          onDragDone: (details) => _handleDroppedInvoiceFiles(details.files),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              compact ? 20 : 32,
              horizontalPadding,
              32,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.title ??
                          (widget.documentType == OCRDocumentType.invoice
                              ? 'Carga la factura'
                              : 'Carga el comprobante'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Primero leeremos el documento. Después podrás corregir sus datos y decidir qué hacer con cada producto.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedContainer(
                      key: const Key('ocr-upload-drop-zone'),
                      duration: const Duration(milliseconds: 140),
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 20 : 40,
                        vertical: compact ? 28 : 40,
                      ),
                      decoration: BoxDecoration(
                        color: _isDraggingInvoiceFile
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isDraggingInvoiceFile
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: _isDraggingInvoiceFile ? 2 : 1,
                        ),
                      ),
                      child: _isProcessing
                          ? Column(
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text(
                                  _useVeryfi
                                      ? 'Leyendo la factura…'
                                      : 'Leyendo la imagen…',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Al terminar verás el documento antes de aplicar cualquier cambio.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                Icon(
                                  _isDraggingInvoiceFile
                                      ? Icons.file_download_done_outlined
                                      : Icons.upload_file_outlined,
                                  size: 40,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  _isDraggingInvoiceFile
                                      ? 'Suelta la factura para leerla'
                                      : 'Arrastra una factura aquí',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'PDF, imagen, HTML o JSON de AliExpress',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  key: const Key('ocr-upload-select-file'),
                                  onPressed: _pickInvoiceFile,
                                  icon: const Icon(Icons.folder_open_outlined),
                                  label: const Text('Seleccionar factura'),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 16),
                    if (compact)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var index = 0;
                              index < secondaryActions.length;
                              index++) ...[
                            secondaryActions[index],
                            if (index != secondaryActions.length - 1)
                              const SizedBox(height: 8),
                          ],
                        ],
                      )
                    else
                      Row(
                        children: [
                          for (var index = 0;
                              index < secondaryActions.length;
                              index++) ...[
                            Expanded(child: secondaryActions[index]),
                            if (index != secondaryActions.length - 1)
                              const SizedBox(width: 12),
                          ],
                        ],
                      ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Nada se guarda ni cambia el stock hasta tu confirmación.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 18),
                      VbNotice(
                        title: 'No se pudo leer la factura',
                        body: _errorMessage,
                        tone: VbNoticeTone.danger,
                      ),
                    ],
                    if (widget.provider == OCRProvider.veryfi &&
                        !_veryfiAvailable &&
                        _initialized)
                      const Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: VbNotice(
                          title: 'OCR en la nube no disponible',
                          body:
                              'Veryfi no está configurado en el servidor. Usa el OCR local o configura sus credenciales en Supabase.',
                          tone: VbNoticeTone.warning,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPreviewScreen() {
    return LayoutBuilder(
      builder: (context, constraints) => _buildPreviewContent(
        constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width,
      ),
    );
  }

  Widget _buildPreviewContent(double width) {
    final data = _parsedData!;
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final diagnostics = _getInvoiceDiagnostics(data);
    final aliExpressTemplateActive = _looksLikeAliExpressInvoice(data);
    final supplierTemplateActive =
        (_ocrSupplier?.ocrTemplate.enabled ?? false) ||
            aliExpressTemplateActive;
    final hasResolvedSupplier = _ocrSupplier != null;
    final unresolved = widget.showLineItemReview
        ? data.lineItems
            .where(
              (item) => !_isParsedLineResolved(item),
            )
            .length
        : 0;
    final compact = width < 700;
    final tableLayout = width >= 900;
    final horizontalPadding = compact ? 16.0 : 24.0;
    final sourceLabel = switch (_lastReadSource) {
      _OcrReadSource.veryfi => 'Veryfi AI',
      _OcrReadSource.local => 'OCR local',
      _OcrReadSource.structured => 'Archivo estructurado',
    };
    final sourceDescription = switch (_lastReadSource) {
      _OcrReadSource.veryfi =>
        'Revisa los datos interpretados por Veryfi antes de usarlos.',
      _OcrReadSource.local =>
        'Revisa los datos leídos del documento antes de usarlos.',
      _OcrReadSource.structured =>
        'Revisa los datos importados del archivo antes de usarlos.',
    };

    Map<String, inv_models.Product> previewProductsById() {
      final products = <String, inv_models.Product>{};
      for (final product in _productReviewCatalogSnapshot ?? const []) {
        final id = product.id;
        if (id != null) products[id] = product;
      }
      for (final entry in _newProductEntries) {
        for (final product in entry.supplierResolutionProducts) {
          final id = product.id;
          if (id != null) products[id] = product;
        }
      }
      return products;
    }

    List<OcrPreviewResolutionComponent> previewComponents(
      ParsedLineItem item,
    ) =>
        buildOcrPreviewResolutionComponents(
          item: item,
          productsById: previewProductsById(),
        );

    String resolutionStatus(ParsedLineItem item) {
      final resolution = item.supplierResolution;
      if (resolution?.isResolved != true) {
        return _isParsedLineResolved(item) ? 'Vinculado' : 'Por revisar';
      }
      return switch (resolution!.kind) {
        SupplierVariantResolutionKind.composite => 'Descompuesto',
        SupplierVariantResolutionKind.homogeneous => 'Pack resuelto',
        SupplierVariantResolutionKind.single =>
          resolution.edges.single.componentRole == 'catalog_set'
              ? 'Set vinculado'
              : 'Vinculado',
        null => 'Vinculado',
      };
    }

    Widget resolvedOutput(
      ParsedLineItem item, {
      required bool desktop,
    }) {
      final components = previewComponents(item);
      if (components.isEmpty) {
        return Text(
          _isParsedLineResolved(item) &&
                  item.matchedProductName?.trim().isNotEmpty == true
              ? item.matchedProductName!.trim()
              : 'Sin vínculo',
          maxLines: desktop ? 2 : null,
          overflow: desktop ? TextOverflow.ellipsis : null,
          style: theme.textTheme.bodySmall?.copyWith(
            color: _isParsedLineResolved(item)
                ? roles.success.accent
                : theme.colorScheme.onSurfaceVariant,
            fontWeight:
                _isParsedLineResolved(item) ? FontWeight.w600 : FontWeight.w400,
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final component in components)
            Padding(
              padding: EdgeInsets.only(
                bottom: component == components.last ? 0 : 4,
              ),
              child: Text(
                component.displayLabel,
                maxLines: desktop ? 2 : null,
                overflow: desktop ? TextOverflow.ellipsis : null,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: roles.success.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      );
    }

    Widget invoiceDatum({
      required IconData icon,
      required String label,
      required String value,
      VoidCallback? onTap,
      bool emphasized = false,
    }) {
      final content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: (emphasized
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(
              Icons.edit_outlined,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
        ],
      );
      if (onTap == null) return content;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
        ),
      );
    }

    Widget productRow(ParsedLineItem item, int index) {
      final resolved = _isParsedLineResolved(item);
      final status = resolutionStatus(item);
      final code = item.sku?.trim();
      final imageUrl = item.imageUrl?.trim();
      final rowDiagnostics = _getRowDiagnostics(item);
      return Semantics(
        container: true,
        label:
            'Línea ${index + 1}, ${item.description}, ${status.toLowerCase()}',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 12 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: compact ? 48 : 56,
                    height: compact ? 48 : 56,
                    child: imageUrl == null || imageUrl.isEmpty
                        ? ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.inventory_2_outlined,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        : Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.inventory_2_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.description,
                        maxLines: compact ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (code != null && code.isNotEmpty)
                            Text(
                              'Código proveedor  $code',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          Text(
                            'Cant.  ${item.quantity ?? 1}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (item.unitPrice != null)
                            Text(
                              'Costo unit.  ${_formatAmount(item.unitPrice)}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          if (rowDiagnostics.displayedTotal != null)
                            Text(
                              'Total línea  ${_formatAmount(rowDiagnostics.displayedTotal)}',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                        ],
                      ),
                      if (resolved) ...[
                        const SizedBox(height: 5),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Entrará a inventario  ',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            Expanded(
                              child: resolvedOutput(item, desktop: false),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                VbStatusBadge(
                  label: status,
                  tone: resolved ? VbStatusTone.success : VbStatusTone.warning,
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget desktopProductTable(List<DataRow> rows) {
      return Semantics(
        container: true,
        label: 'Tabla de productos leídos de la factura',
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fluid, not a fixed canvas. A hard `minWidth: 1280` made the
                // invoice scroll sideways on every host narrower than that,
                // which the owner rejected: the totals column — the whole point
                // of reading the invoice — was permanently off screen. The
                // table now fills whatever width it is given and only scrolls
                // below the width where the columns stop being readable.
                LayoutBuilder(
                  builder: (context, tableConstraints) {
                    final available = tableConstraints.maxWidth.isFinite
                        ? tableConstraints.maxWidth
                        : _previewTableFloor;
                    final tableWidth = available >= _previewTableFloor
                        ? available
                        : _previewTableFloor;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: available >= _previewTableFloor
                          ? const NeverScrollableScrollPhysics()
                          : null,
                      child: SizedBox(
                        width: tableWidth,
                        child: DataTable(
                          key: const Key('ocr-preview-products-table'),
                          showCheckboxColumn: false,
                          headingRowHeight: 42,
                          dataRowMinHeight: 64,
                          dataRowMaxHeight: double.infinity,
                          horizontalMargin: 12,
                          columnSpacing: 16,
                          dividerThickness: 1,
                          headingRowColor: WidgetStatePropertyAll(
                            theme.colorScheme.surfaceContainerLow,
                          ),
                          headingTextStyle:
                              theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                          columns: const [
                            DataColumn(
                              label: Text(
                                '#',
                                key: Key('ocr-preview-table-header'),
                              ),
                            ),
                            DataColumn(label: Text('Producto leído')),
                            DataColumn(label: Text('Código proveedor')),
                            DataColumn(label: Text('Cant.'), numeric: true),
                            DataColumn(
                              label: Text('Costo unit. factura'),
                              numeric: true,
                            ),
                            DataColumn(label: Text('Dscto.'), numeric: true),
                            DataColumn(
                                label: Text('Total línea'), numeric: true),
                            DataColumn(label: Text('Producto ERP')),
                            DataColumn(label: Text('Estado')),
                          ],
                          rows: rows,
                        ),
                      ),
                    );
                  },
                ),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 24,
                    runSpacing: 6,
                    children: [
                      Text(
                        'Suma líneas  ${_formatAmount(diagnostics.rowTotal)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        'Total factura  ${_formatAmount(diagnostics.headerTotal)}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        'Diferencia  ${_formatAmount(diagnostics.delta.abs())}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: diagnostics.hasTotalMismatch
                              ? roles.warning.accent
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: diagnostics.hasTotalMismatch
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    DataRow previewDataRow(ParsedLineItem item, int index) {
      final resolved = _isParsedLineResolved(item);
      final status = resolutionStatus(item);
      final code = item.sku?.trim();
      final imageUrl = item.imageUrl?.trim();
      final unitPrice = item.unitPrice;
      final rowDiagnostics = _getRowDiagnostics(item);
      final discount = rowDiagnostics.discountAmount;
      final total = rowDiagnostics.displayedTotal;
      return DataRow(
        key: ValueKey<String>('ocr-preview-row-$index'),
        cells: [
          DataCell(
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          DataCell(
            SizedBox(
              key: Key('ocr-preview-cell-product-$index'),
              width: 390,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: imageUrl == null || imageUrl.isEmpty
                          ? ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.inventory_2_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.inventory_2_outlined,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          DataCell(
            SizedBox(
              key: Key('ocr-preview-cell-code-$index'),
              width: 142,
              child: Text(
                code?.isNotEmpty == true ? code! : '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          DataCell(
            SizedBox(
              key: Key('ocr-preview-cell-quantity-$index'),
              width: 54,
              child: Text(
                '${item.quantity ?? 1}',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          DataCell(
            SizedBox(
              key: Key('ocr-preview-cell-unit-price-$index'),
              width: 92,
              child: Text(
                _formatAmount(unitPrice),
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          DataCell(
            SizedBox(
              key: Key('ocr-preview-cell-discount-$index'),
              width: 76,
              child: Text(
                discount > 0 ? _formatAmount(discount) : '—',
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          DataCell(
            SizedBox(
              key: Key('ocr-preview-cell-total-$index'),
              width: 92,
              child: Text(
                _formatAmount(total),
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          DataCell(
            SizedBox(
              key: Key('ocr-preview-cell-erp-product-$index'),
              width: 156,
              child: resolvedOutput(item, desktop: true),
            ),
          ),
          DataCell(
            SizedBox(
              key: Key('ocr-preview-cell-status-$index'),
              width: 104,
              child: VbStatusBadge(
                label: status,
                tone: resolved ? VbStatusTone.success : VbStatusTone.warning,
                dense: true,
              ),
            ),
          ),
        ],
      );
    }

    final primaryLabel = _readOnlyEvaluationBlocksMutations
        ? widget.showLineItemReview && unresolved > 0
            ? 'Revisar $unresolved producto${unresolved == 1 ? '' : 's'} · solo lectura'
            : 'Evaluación completada'
        : _isApplyingResult
            ? 'Aplicando factura…'
            : !hasResolvedSupplier
                ? 'Seleccionar proveedor'
                : widget.showLineItemReview && unresolved > 0
                    ? 'Revisar $unresolved producto${unresolved == 1 ? '' : 's'}'
                    : 'Usar esta factura';
    final primaryAction = _readOnlyEvaluationBlocksMutations
        ? widget.showLineItemReview && unresolved > 0
            ? _isOpeningBulkCreate
                ? null
                : _openBulkCreateScreen
            : null
        : _isApplyingResult
            ? null
            : !hasResolvedSupplier
                ? _showSupplierSelectionDialog
                : widget.showLineItemReview && unresolved > 0
                    ? _isOpeningBulkCreate
                        ? null
                        : _openBulkCreateScreen
                    : () => _handleUseParsedData(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              20,
              horizontalPadding,
              28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Factura leída',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            sourceDescription,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    VbStatusBadge(
                      label: sourceLabel,
                      tone: VbStatusTone.info,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final supplier = invoiceDatum(
                              icon: Icons.store_outlined,
                              label: 'Proveedor',
                              value: _ocrSupplierName ??
                                  data.supplierName ??
                                  'Seleccionar proveedor',
                              onTap: _showSupplierSelectionDialog,
                            );
                            final invoiceNumber = invoiceDatum(
                              icon: Icons.tag,
                              label: 'N° de factura',
                              value: data.invoiceNumber ?? 'Sin número',
                              onTap: () => _showEditInvoiceNumberDialog(
                                data.invoiceNumber,
                              ),
                            );
                            final date = invoiceDatum(
                              icon: Icons.calendar_today_outlined,
                              label: 'Fecha',
                              value: data.date == null
                                  ? 'Sin fecha'
                                  : '${data.date!.day}/${data.date!.month}/${data.date!.year}',
                              onTap: () => _showEditDateDialog(data.date),
                            );
                            final total = invoiceDatum(
                              icon: Icons.payments_outlined,
                              label: 'Total leído',
                              value: _formatAmount(data.total),
                              emphasized: true,
                            );
                            if (constraints.maxWidth < 760) {
                              return Column(
                                children: [
                                  supplier,
                                  const SizedBox(height: 16),
                                  invoiceNumber,
                                  const SizedBox(height: 16),
                                  date,
                                  const SizedBox(height: 16),
                                  total,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: supplier),
                                const SizedBox(width: 20),
                                Expanded(flex: 2, child: invoiceNumber),
                                const SizedBox(width: 20),
                                Expanded(flex: 2, child: date),
                                const SizedBox(width: 20),
                                Expanded(flex: 2, child: total),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            VbStatusBadge(
                              label: aliExpressTemplateActive
                                  ? 'Plantilla AliExpress'
                                  : supplierTemplateActive
                                      ? 'Plantilla OCR'
                                      : 'Sin plantilla',
                              tone: supplierTemplateActive
                                  ? VbStatusTone.info
                                  : VbStatusTone.neutral,
                            ),
                            const Spacer(),
                            TextButton.icon(
                              onPressed: _isSavingSupplierTemplate
                                  ? null
                                  : _showSaveSupplierTemplateDialog,
                              icon: _isSavingSupplierTemplate
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: const Text('Guardar plantilla'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.showLineItemReview) ...[
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Productos de la factura',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              unresolved == 0
                                  ? 'Todos los productos están vinculados.'
                                  : '$unresolved de ${data.lineItems.length} necesitan una decisión.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (data.lineItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildCompactDiagnosticsStatus(diagnostics),
                  ],
                  const SizedBox(height: 12),
                  if (data.lineItems.isEmpty)
                    const VbNotice(
                      title: 'No encontré productos en el documento',
                      body:
                          'Puedes volver a cargarlo o completar la factura manualmente.',
                      tone: VbNoticeTone.warning,
                    )
                  else if (tableLayout)
                    desktopProductTable([
                      for (var index = 0;
                          index < data.lineItems.length;
                          index++)
                        previewDataRow(data.lineItems[index], index),
                    ])
                  else
                    for (var index = 0;
                        index < data.lineItems.length;
                        index++) ...[
                      productRow(data.lineItems[index], index),
                      if (index != data.lineItems.length - 1)
                        const SizedBox(height: 10),
                    ],
                ],
              ],
            ),
          ),
        ),
        Material(
          color: theme.colorScheme.surface,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final retry = OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _discardProductReviewDraft(
                        advanceDocumentEpoch: true,
                      );
                      _parsedData = null;
                      _baseParsedData = null;
                      _errorMessage = null;
                      _ocrSupplier = null;
                      _ocrSupplierName = null;
                      _supplierIdForNewProducts = null;
                    });
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Volver a cargar'),
                );
                final primary = FilledButton.icon(
                  key: const Key('ocr-preview-review-products'),
                  onPressed: primaryAction,
                  icon: _isOpeningBulkCreate
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: Text(primaryLabel),
                );
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      primary,
                      const SizedBox(height: 8),
                      retry,
                    ],
                  );
                }
                return Row(
                  children: [
                    retry,
                    const Spacer(),
                    primary,
                  ],
                );
              },
            ),
          ),
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

    final roles = VinabikeThemeRoles.of(context);
    final color = hasWarning ? roles.warning.accent : roles.info.accent;
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

  /// Verify a single product against the database
  Future<ParsedLineItem> _verifySingleProduct(
    ParsedLineItem item, {
    String? supplierId,
    bool allowNameFallback = true,
    bool allowCatalogCodeLookup = true,
  }) async {
    final inventoryService =
        Provider.of<InventoryService>(context, listen: false);

    Product? matchedProduct;

    // PRIORITY 1: Try to find by SKU (if available)
    if (allowCatalogCodeLookup &&
        item.sku != null &&
        item.sku!.trim().isNotEmpty) {
      try {
        matchedProduct =
            await inventoryService.getProductBySku(item.sku!.trim());
      } catch (e) {
        debugPrint('   ❌ Error looking up SKU ${item.sku}: $e');
      }
    }

    // PRIORITY 2: Try to find by Supplier Code
    if (allowCatalogCodeLookup &&
        matchedProduct == null &&
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
    if (allowNameFallback &&
        matchedProduct == null &&
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
      lineTitle: item.lineTitle,
      variantLabel: item.variantLabel,
      variantKey: item.variantKey,
      sku: item.sku,
      rawRowText: item.rawRowText,
      imageUrl: item.imageUrl,
      productUrl: item.productUrl,
      sourcePurchaseQuantity: item.sourcePurchaseQuantity,
      sourcePurchaseUnitPrice: item.sourcePurchaseUnitPrice,
      rawPackCount: item.rawPackCount,
      rawUnitToken: item.rawUnitToken,
      rawPackEvidenceConflict: item.rawPackEvidenceConflict,
      sourceOrderNumbers: item.sourceOrderNumbers,
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

  /// Open the bulk product creation screen.
  Future<void> _openBulkCreateScreen() async {
    if (kDebugMode) {
      debugPrint(
        '🧪 [BulkCreate] pressed · parsed=${_parsedData != null} '
        'opening=$_isOpeningBulkCreate',
      );
    }
    if (_parsedData == null || _isOpeningBulkCreate) return;
    final sourceData = _parsedData!;
    final reviewGeneration = ++_bulkReviewGeneration;
    setState(() => _isOpeningBulkCreate = true);

    try {
      final canResumeDraft = _productReviewDraftEpoch == _parsedInvoiceEpoch &&
          _newProductEntries.isNotEmpty;
      if (canResumeDraft) {
        final isAliExpressInvoice = _looksLikeAliExpressInvoice(sourceData);
        setState(() {
          _showBulkCreate = true;
          _isOpeningBulkCreate = false;
        });
        if (isAliExpressInvoice &&
            _newProductEntries.any(_needsSimilaritySearch)) {
          await _runAliExpressProductAnalysis(reviewGeneration);
        }
        return;
      }

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
        if (!_ownsOpeningBulkReview(reviewGeneration, sourceData)) return;
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

      if (!_ownsOpeningBulkReview(reviewGeneration, sourceData)) return;

      // Auto-detect tax-inclusive cost source. AliExpress invoices allocate
      // IVA into each item's unitPrice, so the unit cost already contains IVA.
      final isAliExpressInvoice = _looksLikeAliExpressInvoice(sourceData);
      _costsIncludeIva = isAliExpressInvoice;

      final nextEntries = newProducts
          .map((item) => _NewProductEntry(
                originalItem: item,
                sourceRowIndex: sourceData.lineItems.indexOf(item),
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
      _ocrProductImageBytesCache.clear();
      _ocrProductImageLoads.clear();
      _productReviewCatalogSnapshot = null;
      _productReviewDuplicateMatcher = null;
      _productReviewCatalogGeneration = null;
      _newProductEntries = nextEntries;
      _productReviewDraftEpoch = _parsedInvoiceEpoch;

      // A reopened review is a new authority: its rows re-derive their keys
      // from the document they belong to, and nothing survives from the batch
      // that was abandoned.
      _skuReservationAuthority = null;

      if (!_ownsOpeningBulkReview(reviewGeneration, sourceData)) return;
      if (kDebugMode) {
        debugPrint('🧪 [BulkCreate] abriendo panel de revisión');
      }
      setState(() {
        _showBulkCreate = true;
        // Reference data is ready and the workspace is interactive. AI and
        // duplicate analysis continue per row without globally disabling it.
        _isOpeningBulkCreate = false;
      });

      if (isAliExpressInvoice) {
        await _runAliExpressProductAnalysis(reviewGeneration);
      }
    } finally {
      if (mounted && _bulkReviewGeneration == reviewGeneration) {
        setState(() => _isOpeningBulkCreate = false);
      }
    }
  }

  bool _ownsOpeningBulkReview(
    int reviewGeneration,
    ParsedInvoice sourceData,
  ) =>
      mounted &&
      _bulkReviewGeneration == reviewGeneration &&
      identical(_parsedData, sourceData);

  bool _ownsBulkReview(int reviewGeneration) =>
      mounted && _showBulkCreate && _bulkReviewGeneration == reviewGeneration;

  bool _needsSimilaritySearch(_NewProductEntry entry) {
    if (!entry.isSelected ||
        !entry.requiresDuplicateReview ||
        entry.linkedProduct != null ||
        entry.hasSupplierResolution ||
        entry.isAICleaningName ||
        entry.isCheckingSimilar ||
        entry.isLinkingExisting ||
        entry.isUploadingImage) {
      return false;
    }
    return entry.resolutionState == OcrProductResolutionState.unsearched ||
        entry.resolutionState == OcrProductResolutionState.failed;
  }

  List<_NewProductEntry> _pendingSimilaritySearchEntries() =>
      _newProductEntries.where(_needsSimilaritySearch).toList(growable: false);

  void _scheduleAIIdentityRecompute(_NewProductEntry entry) {
    _identityRecomputeTimers.remove(entry.reviewId)?.cancel();
    _identityRecomputeTimers[entry.reviewId] = Timer(
      const Duration(milliseconds: 450),
      () {
        _identityRecomputeTimers.remove(entry.reviewId);
        if (!mounted ||
            !_newProductEntries.contains(entry) ||
            !_ownsBulkReview(_bulkReviewGeneration) ||
            !_needsSimilaritySearch(entry)) {
          return;
        }
        unawaited(_checkSimilarProductsForNewEntries(
          entry: entry,
          reviewGeneration: _bulkReviewGeneration,
        ));
      },
    );
  }

  /// Runs independent listing groups through authority → primary multimodal
  /// investigation → full-catalog matching. A slow product no longer delays
  /// useful results for unrelated rows, while variants from the same listing
  /// still share one semantic decision boundary.
  Future<void> _runAliExpressProductAnalysis(int reviewGeneration) async {
    if (!_ownsBulkReview(reviewGeneration)) return;
    final inventoryService = context.read<inv_service.InventoryService>();
    final productsFuture = inventoryService.getProducts().timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException(
            'El catálogo no respondió a tiempo.',
          ),
        );
    final matcher = _buildDuplicateMatcher(inventoryService);
    final grouped = <String, List<_NewProductEntry>>{};
    for (final entry in _pendingSimilaritySearchEntries()) {
      final listingId = _aliExpressItemIdForLine(entry.originalItem);
      final key = listingId?.trim().isNotEmpty == true
          ? 'listing:$listingId'
          : 'row:${entry.reviewId}';
      grouped.putIfAbsent(key, () => <_NewProductEntry>[]).add(entry);
    }
    final groups = grouped.values.toList(growable: false);
    if (groups.isEmpty) return;

    final iterator = groups.iterator;
    final workerCount = math.min(3, groups.length);
    await Future.wait(List.generate(workerCount, (_) async {
      while (iterator.moveNext()) {
        if (!_ownsBulkReview(reviewGeneration)) return;
        final group = iterator.current;
        try {
          final products = await productsFuture;
          if (_ownsBulkReview(reviewGeneration)) {
            _productReviewCatalogSnapshot = products;
            _productReviewDuplicateMatcher = matcher;
            _productReviewCatalogGeneration = reviewGeneration;
          }
          await _checkSimilarProductsForNewEntries(
            targetEntries:
                group.where(_needsSimilaritySearch).toList(growable: false),
            autoTriggered: true,
            reviewGeneration: reviewGeneration,
            preparedInventoryService: inventoryService,
            preparedProducts: products,
            preparedMatcher: matcher,
          );
        } catch (error) {
          for (final entry in group) {
            if (_newProductEntries.contains(entry) &&
                _needsSimilaritySearch(entry)) {
              entry.markResolutionFailed(error);
            }
          }
          if (_ownsBulkReview(reviewGeneration)) setState(() {});
        }
      }
    }));
  }

  /// The one authority for this review's SKUs, built lazily from live state.
  AliExpressSkuReservationAuthority _skuReservationAuthorityOrCreate() {
    final existing = _skuReservationAuthority;
    if (existing != null) return existing;
    final created = AliExpressSkuReservationAuthority(
      reserve: ({required count, required operationKey}) async {
        final supplierId =
            (_supplierIdForNewProducts ?? widget.supplierId)?.trim();
        final supplierName = (_ocrSupplierName ?? widget.supplierName)?.trim();
        if (supplierId == null || supplierId.isEmpty) {
          throw StateError('Falta resolver el proveedor AliExpress.');
        }
        if (supplierName == null || supplierName.isEmpty) {
          throw StateError('Falta el nombre del proveedor AliExpress.');
        }
        final reservation =
            await context.read<InventoryService>().reserveAliExpressSkus(
                  count: count,
                  operationKey: operationKey,
                  supplierId: supplierId,
                  supplierName: supplierName,
                );
        return reservation.skus;
      },
      isSkuTaken: (sku) async =>
          await context.read<InventoryService>().getProductBySku(sku) != null,
    );
    _skuReservationAuthority = created;
    return created;
  }

  /// Which document these rows belong to, in fields that survive a restart.
  String _reservationDocumentFingerprint() {
    final invoice = _parsedData;
    return <String>[
      'v2',
      invoice?.invoiceNumber?.trim() ?? 'sin-folio',
      invoice?.date?.toIso8601String() ?? 'sin-fecha',
      (_supplierIdForNewProducts ?? widget.supplierId ?? '').trim(),
      'lines=${invoice?.lineItems.length ?? 0}',
    ].join('\u001f');
  }

  /// Exact row identity.
  ///
  /// `sourceRowIndex` is the only field that keeps two byte-identical lines of
  /// the same order apart; listing and variant are what let the same order,
  /// re-imported tomorrow, replay its reservation instead of burning the
  /// sequence.
  AliExpressSkuRowIdentity _reservationIdentityFor(_NewProductEntry entry) =>
      AliExpressSkuRowIdentity(
        documentFingerprint: _reservationDocumentFingerprint(),
        sourceRowIndex: entry.sourceRowIndex,
        listingId: _aliExpressItemIdForLine(entry.originalItem) ?? '',
        variantKey: _aliExpressVariantKeyForLine(entry.originalItem) ?? '',
        generation: entry.skuReservationGeneration,
      );

  Future<void> _showSupplierSelectionDialog() async {
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final dbService = DatabaseService();
      final suppliers = await dbService.select(
        'suppliers',
        selectColumns: shared_supplier.Supplier.secretFreeSelect,
        orderBy: 'id',
        fetchAll: true,
      );
      final allSuppliers =
          suppliers.map((s) => shared_supplier.Supplier.fromJson(s)).toList()
            ..sort((a, b) {
              final byName = a.name.compareTo(b.name);
              return byName != 0 ? byName : a.id.compareTo(b.id);
            });

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
                                            _discardProductReviewDraft(
                                              advanceDocumentEpoch: true,
                                            );
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
      if (entry.priceUserEdited) continue;
      final cost =
          double.tryParse(entry.costController.text.replaceAll(',', '.')) ?? 0;
      entry.priceController.text = _NewProductEntry._suggestedPriceFromCost(
        cost,
        costIncludesIva: _costsIncludeIva,
      );
    }
  }

  /// Selects a replacement image locally. Upload is intentionally deferred to
  /// the already guarded product-creation operation so cancelling this review
  /// cannot leave an invisible remote side effect.
  Future<void> _pickReviewProductImage(
    _NewProductEntry entry, {
    required int reviewGeneration,
  }) async {
    final revision = entry.resolutionRevision;
    final picked = await ImageService.pickImage();
    if (picked == null ||
        !_ownsNewProductResolution(
          entry,
          revision,
          reviewGeneration: reviewGeneration,
        )) {
      return;
    }
    setState(() {
      entry.imageUrl = null;
      entry.imageUrlOptimized = null;
      entry.imageBytes = picked.bytes;
      entry.imageFileName = picked.name;
      entry.invalidateDuplicateResolution();
    });
    _scheduleAIIdentityRecompute(entry);
  }

  /// Build the bulk product creation screen
  Widget _buildBulkCreateScreen() {
    // Only rows the worker actually decided are «nuevo». Counting every
    // undecided row promised «Crear 7 productos» before a single one of those
    // seven decisions existed, which is the button lying about what it will do.
    final confirmedNewCount = _newProductEntries
        .where((entry) =>
            entry.isSelected &&
            entry.linkedProduct == null &&
            !entry.hasSupplierResolution &&
            entry.resolutionState == OcrProductResolutionState.newProduct)
        .length;
    final undecidedCount = _newProductEntries
        .where((entry) =>
            entry.isSelected &&
            entry.linkedProduct == null &&
            !entry.hasSupplierResolution &&
            entry.requiresDuplicateReview &&
            entry.resolutionState != OcrProductResolutionState.newProduct)
        .length;
    final incompleteCount = _bulkIncompleteRowCount();
    final pendingSimilaritySearch = _pendingSimilaritySearchEntries();
    return OcrProductReviewWorkspace(
      lines: _newProductEntries
          .map(_buildProductReviewLine)
          .toList(growable: false),
      callbacks: OcrProductReviewCallbacks(
        onSelectionChanged: (lineId, selected) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _creatingProducts) return;
          setState(() => entry.isSelected = selected);
        },
        onLinkCandidate: (lineId, product) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _bulkRowBusy(entry)) return;
          unawaited(_useExistingProductForEntry(
            entry,
            product,
            expectedRevision: entry.resolutionRevision,
            reviewGeneration: _bulkReviewGeneration,
          ));
        },
        onConfirmNewProduct: (lineId) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _bulkRowBusy(entry)) return;
          unawaited(_confirmNewProductForEntry(entry));
        },
        onConfirmCompositeProposal: (lineId) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _bulkRowBusy(entry)) return;
          unawaited(_confirmSupplierResolutionProposal(entry));
        },
        onRetrySkuReservation: (lineId) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _creatingProducts) return;
          entry.skuReservationError = null;
          unawaited(_ensureReservedSkuForEntry(entry));
        },
        onRetryLine: (lineId) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _bulkRowBusy(entry)) return;
          entry.retryDuplicateResolution();
          unawaited(_checkSimilarProductsForNewEntries(
            entry: entry,
            reviewGeneration: _bulkReviewGeneration,
          ));
        },
        onSearchPending: pendingSimilaritySearch.isEmpty
            ? null
            : () {
                if (_creatingProducts || _isOpeningBulkCreate) return;
                final pending = _pendingSimilaritySearchEntries();
                if (pending.isEmpty) return;
                unawaited(_checkSimilarProductsForNewEntries(
                  targetEntries: pending,
                  reviewGeneration: _bulkReviewGeneration,
                ));
              },
        onOpenCandidates: (lineId) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _bulkRowBusy(entry)) return;
          unawaited(_openCandidatePicker(entry));
        },
        onSkuChanged: (lineId, _) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _creatingProducts) return;
          setState(entry.invalidateDuplicateResolution);
          _scheduleAIIdentityRecompute(entry);
        },
        onNameChanged: (lineId, _) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry != null && mounted) {
            setState(() {});
            _scheduleAIIdentityRecompute(entry);
          }
        },
        onCategoryChanged: (lineId, category) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _creatingProducts) return;
          setState(() {
            entry.selectedCategory = category;
            entry.categoryUserEdited = true;
            entry.aiSuggestedCategoryName = category?.fullPath;
            entry.invalidateDuplicateResolution();
          });
          _scheduleAIIdentityRecompute(entry);
        },
        onBrandChanged: (lineId, brand) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _creatingProducts) return;
          setState(() {
            entry.selectedBrand = brand;
            entry.brandUserEdited = true;
            entry.aiSuggestedBrandName = brand?.name;
            entry.invalidateDuplicateResolution();
          });
          _scheduleAIIdentityRecompute(entry);
        },
        onCostChanged: (lineId, _) {
          if (_newProductEntryForReviewId(lineId) != null && mounted) {
            setState(() {});
          }
        },
        onPriceChanged: (lineId, _) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || !mounted) return;
          entry.priceUserEdited = true;
          setState(() {});
        },
        onSoldChanged: (lineId, isSold) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _creatingProducts) return;
          setState(() => entry.isWorkshopConsumable = !isSold);
        },
        onCopySibling: (lineId, siblingLineId) {
          final entry = _newProductEntryForReviewId(lineId);
          final sibling = _newProductEntryForReviewId(siblingLineId);
          if (entry == null || sibling == null || _creatingProducts) return;
          setState(() {
            entry.selectedCategory = sibling.selectedCategory;
            entry.selectedBrand = sibling.selectedBrand;
            entry.categoryUserEdited = true;
            entry.brandUserEdited = true;
            entry.invalidateDuplicateResolution();
          });
          _scheduleAIIdentityRecompute(entry);
        },
        onReplaceImage: (lineId) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _bulkRowBusy(entry)) return;
          unawaited(_pickReviewProductImage(
            entry,
            reviewGeneration: _bulkReviewGeneration,
          ));
        },
        onRemoveImage: (lineId) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _bulkRowBusy(entry)) return;
          setState(() {
            entry.imageUrl = null;
            entry.imageUrlOptimized = null;
            entry.imageBytes = null;
            entry.imageFileName = null;
            entry.invalidateDuplicateResolution();
          });
          _scheduleAIIdentityRecompute(entry);
        },
        onChangeDecision: (lineId) {
          final entry = _newProductEntryForReviewId(lineId);
          if (entry == null || _bulkRowBusy(entry)) return;
          _changeProductDecision(entry);
        },
        onCostIncludesVatChanged: (value) {
          setState(() {
            _costsIncludeIva = value;
            _recomputeSuggestedPricesFromCost();
          });
        },
        onBack: _closeBulkReview,
        onPrimary: _canCreateBulkProducts()
            ? confirmedNewCount == 0
                ? _finishBulkReview
                : () => unawaited(_createBulkProducts())
            : null,
      ),
      primaryLabel: _bulkPrimaryLabel(
        confirmedNewCount: confirmedNewCount,
        undecidedCount: undecidedCount,
        incompleteCount: incompleteCount,
      ),
      pricingPolicyLabel: _costsIncludeIva
          ? 'Precio sugerido = costo × 2 · costo con IVA'
          : 'Precio sugerido = costo × 1,19 × 2 · costo neto',
      primaryEnabled: _canCreateBulkProducts(),
      primaryBlockingReason: _bulkCreateBlockingMessage(),
      costIncludesVat: _costsIncludeIva,
      readOnly: _creatingProducts || _readOnlyEvaluationBlocksMutations,
      readOnlyReason: _creatingProducts
          ? 'Creando productos. Espera a que termine antes de volver.'
          : _readOnlyEvaluationBlocksMutations
              ? 'Evaluación de solo lectura: no se vinculará, creará ni guardará ningún producto.'
              : null,
    );
  }

  /// What the primary button honestly does next.
  ///
  /// While decisions are missing it says so and stays disabled; it never
  /// advertises a creation count that no decision has produced yet. A row that
  /// is decided but still missing a required field gets its own truthful
  /// wording, because «completar» and «decidir» are different jobs.
  String _bulkPrimaryLabel({
    required int confirmedNewCount,
    required int undecidedCount,
    required int incompleteCount,
  }) {
    if (_creatingProducts) return 'Creando productos…';
    if (_anyRowReservingSku) return 'Reservando SKU…';
    if (undecidedCount > 0) {
      return 'Faltan $undecidedCount '
          '${undecidedCount == 1 ? 'decisión' : 'decisiones'}';
    }
    if (incompleteCount > 0) {
      return 'Completa $incompleteCount '
          '${incompleteCount == 1 ? 'fila' : 'filas'}';
    }
    if (confirmedNewCount == 0) return 'Continuar';
    return 'Crear $confirmedNewCount '
        'producto${confirmedNewCount == 1 ? '' : 's'}';
  }

  /// Selected rows that are decided but still missing a required field.
  int _bulkIncompleteRowCount() {
    final isAliExpress =
        _parsedData != null && _looksLikeAliExpressInvoice(_parsedData!);
    return _newProductEntries
        .where((entry) =>
            entry.isSelected &&
            entry.linkedProduct == null &&
            !entry.hasSupplierResolution &&
            !(isAliExpress ? entry.isValidWithoutSku : entry.isValid))
        .length;
  }

  /// Confirms one row as a new product and gives it its real SKU now.
  ///
  /// The legacy flow reserved the whole batch at the final create click, so an
  /// operator deciding «Nuevo» watched the SKU column stay empty through the
  /// entire review and had nothing to write on the box. The reservation is
  /// database-owned and idempotent per row, so asking for it at the moment of
  /// the decision costs one call and makes the row immediately true.
  Future<void> _confirmNewProductForEntry(_NewProductEntry entry) async {
    if (_readOnlyEvaluationBlocksMutations || !mounted || _bulkRowBusy(entry)) {
      return;
    }
    setState(entry.markNewProduct);
    _reconcileListingGroupResults();
    await _ensureReservedSkuForEntry(entry);
  }

  /// Gives one row its database-owned SKU, or replays the one it already has.
  ///
  /// Ownership is checked twice: once before asking, and again before painting
  /// the answer. Between those two moments the operator may have linked the row
  /// to an existing product, closed the review or reopened the invoice, and a
  /// reservation that arrives into a row that no longer wants it must be
  /// dropped rather than displayed — while the spinner still clears, because a
  /// stuck spinner blocks Create and Back forever.
  Future<void> _ensureReservedSkuForEntry(_NewProductEntry entry) async {
    if (_readOnlyEvaluationBlocksMutations || !mounted) return;
    if (!entry.requiresDuplicateReview) return;
    if (!_newProductEntries.contains(entry)) return;
    if (entry.isReservingSku) return;
    if (entry.hasReservedAliExpressSku) {
      setState(entry.syncSkuField);
      return;
    }

    final reviewGeneration = _bulkReviewGeneration;
    final ticket = ++entry.skuReservationTicket;
    final identity = _reservationIdentityFor(entry);
    setState(() {
      entry.isReservingSku = true;
      entry.skuReservationError = null;
    });
    try {
      final reservation =
          await _skuReservationAuthorityOrCreate().reserveFor(identity);
      if (!mounted) return;
      if (!_ownsSkuReservation(entry, ticket, reviewGeneration)) {
        if (_newProductEntries.contains(entry) && entry.isReservingSku) {
          setState(() => entry.isReservingSku = false);
        }
        return;
      }
      setState(() {
        entry.isReservingSku = false;
        entry.reservedSku = reservation.sku;
        entry.skuOperationKey = reservation.operationKey;
        entry.skuReservationGeneration = reservation.generation;
        entry.syncSkuField();
      });
    } catch (error) {
      debugPrint('AliExpress SKU reservation failed for one row: $error');
      if (!mounted || !_newProductEntries.contains(entry)) return;
      setState(() {
        entry.isReservingSku = false;
        if (_ownsSkuReservation(entry, ticket, reviewGeneration)) {
          entry.skuReservationError = error;
        }
      });
    }
  }

  bool _ownsSkuReservation(
    _NewProductEntry entry,
    int ticket,
    int reviewGeneration,
  ) =>
      _ownsBulkReview(reviewGeneration) &&
      _newProductEntries.contains(entry) &&
      entry.skuReservationTicket == ticket;

  bool get _anyRowReservingSku =>
      _newProductEntries.any((entry) => entry.isReservingSku);

  /// Opens the centred picker for one line and applies whatever the operator
  /// decided there.
  ///
  /// The picker is the only place alternatives are shown. Expanding them inside
  /// the reconciliation row made rows different heights and hid the rest of the
  /// invoice, which is the composition the owner rejected on 2026-08-09.
  Future<void> _openCandidatePicker(_NewProductEntry entry) async {
    final reviewGeneration = _bulkReviewGeneration;
    final inventoryService = context.read<inv_service.InventoryService>();
    final cachedResult = entry.duplicateResult;
    final cachedOperatorChoices = applyAIManualReviewOrder(
      decision: cachedResult?.adjudication,
      candidates: cachedResult?.operatorChoices ?? entry.similarCandidates,
    );
    final cachedCategoryConflicts = applyAIManualReviewOrder(
      decision: cachedResult?.adjudication,
      candidates: cachedResult?.categoryConflicts ??
          const <ProductDuplicateCandidate>[],
    );
    final traceId = _productIdentityTraceId(entry, entry.resolutionRevision);
    ProductIdentityTrace.emit(
      traceId: traceId,
      event: 'picker.open_cached',
      data: <String, Object?>{
        'recommendation_count':
            entry.duplicateResult?.recommendations.length ?? 0,
        'operator_choice_count':
            entry.duplicateResult?.operatorChoices.length ??
                entry.similarCandidates.length,
        'category_conflict_count':
            entry.duplicateResult?.categoryConflicts.length ?? 0,
        'adjudication_state': entry.duplicateResult?.adjudicationState.name,
        'has_composite_proposal':
            entry.duplicateResult?.aiCompositeProposal != null,
        'new_model_calls': 0,
      },
    );
    final decision = await OcrCandidatePicker.show(
      context,
      line: OcrCandidateLineContext(
        title: entry.nameController.text.trim().isEmpty
            ? entry.originalItem.description
            : entry.nameController.text.trim(),
        originalTitle: entry.supplierIdentityTitle,
        supplierCode: entry.supplierCode.isEmpty
            ? entry.originalItem.sku
            : entry.supplierCode,
        imageUrl: entry.imageUrlOptimized ?? entry.imageUrl,
        quantity: entry.originalItem.quantity,
        unitCost: entry.cost,
        categoryLabel: entry.selectedCategory?.name,
        brandLabel: entry.selectedBrand?.name,
      ),
      candidates: cachedOperatorChoices,
      categoryConflicts: cachedCategoryConflicts,
      aiCompositeProposal: entry.supplierResolutionProposal?.displaySummary ??
          entry.duplicateResult?.aiCompositeProposal,
      canConfirmCompositeProposal: entry.supplierResolutionProposal != null &&
          !_readOnlyEvaluationBlocksMutations,
      allowCreateNew: entry.duplicateResult?.adjudicationState !=
          ProductDuplicateAdjudicationState.failed,
      inspectionOnly: _readOnlyEvaluationBlocksMutations,
      isLoading: entry.isCheckingSimilar,
      onSearch: (query) => inventoryService.searchProductPreviews(
        query,
        limit: 25,
      ),
    );
    if (!mounted || !_ownsBulkReview(reviewGeneration)) return;
    ProductIdentityTrace.emit(
      traceId: traceId,
      event: 'picker.decision',
      data: <String, Object?>{
        'decision': switch (decision) {
          OcrCandidateLink() => 'link',
          OcrCandidateCreateNew() => 'create_new',
          OcrCandidateConfirmComposition() => 'confirm_composition',
          null => 'dismissed',
        },
        if (decision
            case OcrCandidateLink(product: final product)) ...<String, Object?>{
          'product_id': product.id,
          'sku': product.sku,
        },
      },
    );
    switch (decision) {
      case OcrCandidateLink(product: final product):
        await _useExistingProductForEntry(
          entry,
          product,
          expectedRevision: entry.resolutionRevision,
          reviewGeneration: reviewGeneration,
        );
      case OcrCandidateCreateNew():
        await _confirmNewProductForEntry(entry);
      case OcrCandidateConfirmComposition():
        await _confirmSupplierResolutionProposal(entry);
      case null:
        break;
    }
  }

  /// One invoice row, phrased as the question the matcher answers.
  ///
  /// Both entry points build it here: the row's automatic search and the
  /// picker's wider one. Two copies of this construction is how the overlay
  /// once asked a subtly different question than the row it belongs to.
  ProductDuplicateProbe _duplicateProbeFor(_NewProductEntry entry) {
    final optionEvidence = _supplierOptionEvidenceForLine(entry.originalItem);
    return ProductDuplicateProbe(
      name: entry.nameController.text,
      description: _aiLineContextWithoutVariant(entry),
      // The immutable supplier wording, before the AI/editor rewrites the
      // display name. Every identity consumer must answer the same question.
      sourceTitle: entry.supplierIdentityTitle,
      sku: _costsIncludeIva && entry.supplierCode.isNotEmpty
          ? entry.supplierCode
          : entry.skuController.text.trim().isNotEmpty
              ? entry.skuController.text.trim()
              : entry.originalItem.sku,
      model: entry.aiSuggestedModel,
      rawText: entry.originalItem.rawRowText,
      categoryName: _duplicateMatcherCategoryName(entry),
      categoryId: entry.selectedCategory?.id,
      brandName: _duplicateMatcherBrandName(entry),
      supplierId: _supplierIdForNewProducts ?? widget.supplierId,
      supplierName: _ocrSupplierName ?? widget.supplierName,
      supplierListingId: _aliExpressItemIdForLine(entry.originalItem),
      selectedVariant: _aliExpressVariantLabelForLine(entry.originalItem),
      immutableVariantKey:
          _aliExpressImmutableVariantKeyForLine(entry.originalItem),
      investigation: entry.aiInvestigation,
      traceId: _productIdentityTraceId(entry, entry.resolutionRevision),
      imageUrl: entry.imageUrl,
      imageBytes: entry.imageBytes,
      imageFileName: entry.imageFileName,
      price: entry.price,
      cost: entry.cost,
      sourcePurchaseUnitCost: entry.originalItem.sourcePurchaseUnitPrice,
      sourcePurchaseQuantity: entry.originalItem.sourcePurchaseQuantity ??
          entry.originalItem.quantity,
      supplierPackCount: optionEvidence?.packCount,
      supplierUnitClass: optionEvidence?.unitClass,
      supplierPackEvidenceConflict:
          optionEvidence?.packEvidenceConflict ?? false,
      requiresExplicitComposition:
          optionEvidence?.requiresExplicitComposition ?? false,
    );
  }

  String _productIdentityTraceId(_NewProductEntry entry, int revision) =>
      ProductIdentityTrace.idFor(
        scope: 'ocr-product-review',
        rowKey: entry.reviewId,
        revision: '$revision',
      );

  OcrProductReviewLine _buildProductReviewLine(_NewProductEntry entry) {
    final sibling = _semanticSiblingFor(entry);
    final cachedChoices = applyAIManualReviewOrder(
      decision: entry.duplicateResult?.adjudication,
      candidates:
          entry.duplicateResult?.operatorChoices ?? entry.similarCandidates,
    );
    // This is the same ordered list the picker renders. A rejected normal
    // candidate may still be the operator's best manual lead, but a catalog
    // category conflict never jumps ahead of it or becomes a quick-link.
    final rowCandidates = orderOcrCandidateChoices(cachedChoices);
    final sku = entry.displaySku.isNotEmpty
        ? entry.displaySku
        : entry.requiresDuplicateReview
            ? 'Se asignará al confirmar «Nuevo»'
            : 'Falta SKU';
    final rejectedBrand = entry.semanticEvidence.any(
      (evidence) =>
          evidence.kind ==
              ProductCatalogSemanticEvidenceKind.rejectedBrandHint ||
          evidence.kind == ProductCatalogSemanticEvidenceKind.unresolvedBrand,
    );
    final currentSemanticSummary = _currentSemanticReviewSummary(entry);
    return OcrProductReviewLine(
      id: entry.reviewId,
      sku: sku,
      supplierCode: entry.supplierCode.isEmpty ? null : entry.supplierCode,
      originalTitle: entry.supplierIdentityTitle,
      sourceQuantity: entry.originalItem.quantity,
      sourceLineTotal: _getRowDiagnostics(entry.originalItem).displayedTotal,
      imageUrl: entry.imageUrlOptimized ?? entry.imageUrl,
      imageBytes: entry.imageUrl == null ? entry.imageBytes : null,
      controllers: OcrProductDraftControllers(
        sku: entry.skuController,
        name: entry.nameController,
        cost: entry.costController,
        price: entry.priceController,
      ),
      status: _productReviewStatus(entry),
      isUploadingImage: entry.isUploadingImage,
      isReservingSku: entry.isReservingSku,
      // A code the database owns is not an editable field. Showing it as one
      // invites a worker to "fix" it and send a number nothing reserved.
      skuIsReadOnly: entry.requiresDuplicateReview,
      skuErrorMessage: entry.skuReservationError == null
          ? null
          : 'No se pudo reservar el SKU. Reintenta.',
      candidates: rowCandidates,
      viableCandidateCount: cachedChoices
          .where((candidate) =>
              !candidate.isRuledOut && !candidate.isReviewOnlyFamilyScope)
          .length,
      discardedCandidateCount:
          cachedChoices.where((candidate) => candidate.isRuledOut).length,
      categoryConflictCount:
          entry.duplicateResult?.categoryConflicts.length ?? 0,
      categories: _categories,
      brands: _brands,
      category: entry.selectedCategory,
      brand: entry.selectedBrand,
      nameOrigin: entry.nameUserEdited
          ? OcrProductFieldOrigin.user
          : entry.nameWasAICleaned
              ? OcrProductFieldOrigin.aiCleaned
              : OcrProductFieldOrigin.invoice,
      categoryOrigin: entry.categoryUserEdited
          ? OcrProductFieldOrigin.user
          : OcrProductFieldOrigin.aiSuggested,
      brandOrigin: entry.brandUserEdited
          ? OcrProductFieldOrigin.user
          : OcrProductFieldOrigin.aiSuggested,
      isSold: !entry.isWorkshopConsumable,
      evidenceDegraded:
          entry.imageBytes == null && (entry.imageUrl?.isEmpty ?? true),
      errorMessage: entry.creationError ??
          entry.resolutionError ??
          entry.aiInvestigationError,
      searchSummary: currentSemanticSummary,
      aiCompositeProposal: entry.supplierResolutionProposal?.displaySummary ??
          entry.duplicateResult?.aiCompositeProposal,
      canConfirmCompositeProposal: entry.supplierResolutionProposal != null,
      categoryValidationMessage: entry.selectedCategory == null
          ? entry.categoryReviewReason ??
              'Falta elegir la familia correcta para este producto.'
          : null,
      brandWarning: rejectedBrand && entry.selectedBrand == null
          ? 'La marca sugerida no tiene evidencia de fabricante.'
          : null,
      siblingSuggestion: sibling == null
          ? null
          : 'La línea “${sibling.nameController.text}” comparte esta publicación. Puedes reutilizar familia y marca sin fusionar la variante.',
      siblingLineId: sibling?.reviewId,
      resolvedProductName: entry.linkedProduct?.name ??
          (entry.supplierResolutionProducts.isEmpty
              ? null
              : entry.supplierResolutionProducts
                  .map((product) => product.name)
                  .join(' + ')),
      resolvedProductSku: entry.linkedProduct?.sku ??
          (entry.supplierResolutionProducts.isEmpty
              ? null
              : entry.supplierResolutionProducts
                  .map((product) => product.sku)
                  .join(' + ')),
      resolvedOutcomeSummary: _rememberedSupplierResolutionSummary(entry),
      resolvedMode: _resolvedModeFor(entry),
      // A remembered supplier graph is durable authority, not a transient
      // row choice. The old "Cambiar" callback deliberately refused it, so
      // rendering that button was a lie. A future correction surface must
      // create a new revision with an explicit reason instead of silently
      // replacing the remembered graph.
      canChangeResolvedDecision: !entry.hasSupplierResolution,
      isSelected: entry.isSelected,
      inspectionOnly: _readOnlyEvaluationBlocksMutations,
    );
  }

  OcrProductResolvedMode _resolvedModeFor(_NewProductEntry entry) {
    final resolution = entry.supplierResolution;
    if (resolution?.isResolved != true) {
      return OcrProductResolvedMode.catalogLink;
    }
    return switch (resolution!.kind) {
      SupplierVariantResolutionKind.composite =>
        OcrProductResolvedMode.rememberedComposite,
      SupplierVariantResolutionKind.homogeneous =>
        OcrProductResolvedMode.rememberedPack,
      SupplierVariantResolutionKind.single => resolution.edges.length == 1 &&
              resolution.edges.single.componentRole == 'catalog_set'
          ? OcrProductResolvedMode.rememberedSet
          : OcrProductResolvedMode.rememberedLink,
      null => OcrProductResolvedMode.rememberedLink,
    };
  }

  String? _rememberedSupplierResolutionSummary(_NewProductEntry entry) {
    final resolution = entry.supplierResolution;
    final products = entry.supplierResolutionProducts;
    if (resolution?.isResolved != true ||
        resolution!.edges.isEmpty ||
        resolution.edges.length != products.length) {
      return null;
    }
    final sourceQuantity = entry.originalItem.sourcePurchaseQuantity ??
        entry.originalItem.quantity;
    if (sourceQuantity == null ||
        !sourceQuantity.isFinite ||
        sourceQuantity <= 0) {
      return null;
    }
    return <String>[
      for (var index = 0; index < resolution.edges.length; index++)
        _rememberedSupplierResolutionComponent(
          product: products[index],
          quantity:
              sourceQuantity * resolution.edges[index].catalogUnitsPerPurchase,
          role: resolution.edges[index].componentRole,
        ),
    ].join(' + ');
  }

  String _rememberedSupplierResolutionComponent({
    required inv_models.Product product,
    required double quantity,
    required String role,
  }) {
    final roleLabel = _ocrPreviewComponentRoleLabel(role);
    return '${_ocrPreviewQuantityLabel(quantity)} × ${product.sku}'
        '${roleLabel == null ? '' : ' · $roleLabel'}';
  }

  String? _currentSemanticReviewSummary(_NewProductEntry entry) {
    var summary = <String>{
      if (entry.duplicateResult?.reason?.trim().isNotEmpty == true)
        entry.duplicateResult!.reason!.trim(),
      if (entry.semanticReviewReason?.trim().isNotEmpty == true)
        entry.semanticReviewReason!.trim(),
    }.join(' · ');
    if (summary.isEmpty) return null;
    if (entry.duplicateResult?.probeIdentity.hasResolvedFamily == true) {
      // The legacy semantic helper recognizes only a handful of families.
      // Once the canonical identity matcher has resolved the object, its old
      // generic failure is stale. Remove only that clause so unresolved brand,
      // mixed-listing and category-conflict evidence remains visible.
      summary = summary
          .replaceFirst('No se pudo determinar la familia del producto.', '')
          .trim();
    }
    return summary.isEmpty ? null : summary;
  }

  OcrProductReviewStatus _productReviewStatus(_NewProductEntry entry) {
    if (entry.linkedProduct != null || entry.hasSupplierResolution) {
      return OcrProductReviewStatus.linked;
    }
    if (entry.isAICleaningName ||
        entry.isCheckingSimilar ||
        entry.isLinkingExisting ||
        entry.resolutionState == OcrProductResolutionState.searching) {
      return OcrProductReviewStatus.searching;
    }
    if (entry.creationError != null ||
        (entry.aiInvestigation == null &&
            entry.aiInvestigationError?.trim().isNotEmpty == true) ||
        entry.duplicateResult?.adjudicationState ==
            ProductDuplicateAdjudicationState.failed ||
        entry.resolutionState == OcrProductResolutionState.failed) {
      return OcrProductReviewStatus.failed;
    }
    return switch (entry.resolutionState) {
      OcrProductResolutionState.reviewRequired => OcrProductReviewStatus.ready,
      OcrProductResolutionState.abstained => OcrProductReviewStatus.abstained,
      OcrProductResolutionState.noCandidates =>
        OcrProductReviewStatus.noCandidates,
      OcrProductResolutionState.newProduct =>
        OcrProductReviewStatus.newProductReady,
      OcrProductResolutionState.unsearched =>
        OcrProductReviewStatus.needsSearch,
      OcrProductResolutionState.searching => OcrProductReviewStatus.searching,
      OcrProductResolutionState.failed => OcrProductReviewStatus.failed,
    };
  }

  _NewProductEntry? _newProductEntryForReviewId(String reviewId) {
    for (final entry in _newProductEntries) {
      if (entry.reviewId == reviewId) return entry;
    }
    return null;
  }

  _NewProductEntry? _semanticSiblingFor(_NewProductEntry entry) {
    final itemId = _aliExpressItemIdForLine(entry.originalItem);
    if (itemId == null || itemId.isEmpty) return null;
    for (final candidate in _newProductEntries) {
      if (identical(candidate, entry)) continue;
      if (_aliExpressItemIdForLine(candidate.originalItem) == itemId) {
        return candidate;
      }
    }
    return null;
  }

  bool _canCreateBulkProducts() {
    if (_readOnlyEvaluationBlocksMutations) return false;
    final isAliExpress =
        _parsedData != null && _looksLikeAliExpressInvoice(_parsedData!);
    final selected =
        _newProductEntries.where((entry) => entry.isSelected).toList();
    if (selected.isEmpty) return false;
    final pendingCreation = selected
        .where((entry) =>
            entry.linkedProduct == null && !entry.hasSupplierResolution)
        .toList();
    if (pendingCreation.isEmpty) {
      return !_isOpeningBulkCreate &&
          !_creatingProducts &&
          !_anyRowReservingSku;
    }
    if (pendingCreation
        .any((entry) => SupplierOptionEvidence.requiresExplicitCompositionFor(
              packCount: entry.originalItem.rawPackCount,
              rawUnitToken: entry.originalItem.rawUnitToken,
              packEvidenceConflict: entry.originalItem.rawPackEvidenceConflict,
            ))) {
      return false;
    }
    // A confirmed «Nuevo» row without its reserved code is not creatable: the
    // code is the database's to give, and creating without it is how a product
    // ends up with an invented SKU.
    if (pendingCreation.any((entry) =>
        entry.requiresDuplicateReview &&
        entry.resolutionState == OcrProductResolutionState.newProduct &&
        !entry.hasReservedAliExpressSku)) {
      return false;
    }
    return OcrProductResolutionPolicy.canCreate(
      globalBusy:
          _isOpeningBulkCreate || _creatingProducts || _anyRowReservingSku,
      lines: pendingCreation.map(
        (entry) => OcrProductResolutionSnapshot(
          selected: entry.isSelected,
          valid: isAliExpress ? entry.isValidWithoutSku : entry.isValid,
          requiresDuplicateReview: entry.requiresDuplicateReview,
          state: entry.resolutionState,
          aiCleaning: entry.isAICleaningName,
          matchChecking: entry.isCheckingSimilar ||
              entry.isLinkingExisting ||
              entry.isUploadingImage,
        ),
      ),
    );
  }

  bool _bulkRowBusy(_NewProductEntry entry) =>
      _creatingProducts ||
      entry.isAICleaningName ||
      entry.isCheckingSimilar ||
      entry.isLinkingExisting ||
      entry.isUploadingImage ||
      // A row whose SKU is being reserved has an operation running against the
      // shared AE sequence. Changing its decision mid-flight would either strand
      // the number or paint it onto a row that no longer wants it.
      entry.isReservingSku;

  void _closeBulkReview() {
    if (!mounted || _creatingProducts) return;
    if (_anyRowReservingSku) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Espera a que termine de reservarse el SKU.'),
        ),
      );
      return;
    }
    _bulkReviewGeneration++;
    for (final timer in _identityRecomputeTimers.values) {
      timer.cancel();
    }
    _identityRecomputeTimers.clear();
    setState(() {
      _showBulkCreate = false;
      _isOpeningBulkCreate = false;
      for (final entry in _newProductEntries) {
        entry.cancelTransientReviewWork();
      }
    });
  }

  void _finishBulkReview() {
    if (!mounted) return;
    _bulkReviewGeneration++;
    setState(() {
      _removeOmittedLinesFromInvoice();
      _showBulkCreate = false;
      _isOpeningBulkCreate = false;
    });
  }

  /// Omission is a review decision about the invoice line itself, not merely
  /// about product creation. Commit it only when the operator finishes the
  /// review so Back can still restore/reinclude the untouched batch.
  void _removeOmittedLinesFromInvoice() {
    final parsed = _parsedData;
    if (parsed == null) return;
    final omitted = _newProductEntries
        .where((entry) => !entry.isSelected)
        .toList(growable: false);
    if (omitted.isEmpty) return;

    final parsedItems = List<ParsedLineItem>.from(parsed.lineItems);
    final baseItems = _baseParsedData == null
        ? null
        : List<ParsedLineItem>.from(_baseParsedData!.lineItems);
    final indices = omitted
        .map((entry) {
          final current = parsedItems.indexOf(entry.originalItem);
          return current >= 0 ? current : entry.sourceRowIndex;
        })
        .where((index) => index >= 0 && index < parsedItems.length)
        .toSet()
        .toList()
      ..sort((left, right) => right.compareTo(left));

    for (final index in indices) {
      parsedItems.removeAt(index);
      if (baseItems != null && index < baseItems.length) {
        baseItems.removeAt(index);
      }
      _skuControllers.remove(index)?.dispose();
    }
    for (final entry in omitted) {
      _newProductEntries.remove(entry);
      entry.dispose();
    }
    _parsedData = parsed.copyWith(lineItems: parsedItems);
    if (_baseParsedData != null && baseItems != null) {
      _baseParsedData = _baseParsedData!.copyWith(lineItems: baseItems);
    }
  }

  String? _bulkCreateBlockingMessage() {
    final selected = _newProductEntries
        .where((entry) =>
            entry.isSelected &&
            entry.linkedProduct == null &&
            !entry.hasSupplierResolution)
        .toList();
    if (_creatingProducts) return null;
    if (selected.any((entry) => entry.isReservingSku)) {
      return 'Reservando el SKU de una fila. Espera a que termine.';
    }
    if (selected.any((entry) =>
        entry.isAICleaningName ||
        entry.isCheckingSimilar ||
        entry.isLinkingExisting ||
        entry.isUploadingImage)) {
      return 'Espera a que termine el análisis o la carga de imágenes.';
    }
    final withoutReservedSku = selected
        .where((entry) =>
            entry.requiresDuplicateReview &&
            entry.resolutionState == OcrProductResolutionState.newProduct &&
            !entry.hasReservedAliExpressSku)
        .length;
    if (withoutReservedSku > 0) {
      return 'Falta el SKU reservado en $withoutReservedSku '
          'fila${withoutReservedSku == 1 ? '' : 's'}. Reintenta la reserva.';
    }
    final unresolvedPacks = selected
        .where((entry) => SupplierOptionEvidence.requiresExplicitCompositionFor(
              packCount: entry.originalItem.rawPackCount,
              rawUnitToken: entry.originalItem.rawUnitToken,
              packEvidenceConflict: entry.originalItem.rawPackEvidenceConflict,
            ))
        .length;
    if (unresolvedPacks > 0) {
      return 'Falta confirmar la unidad o composición de $unresolvedPacks '
          'pack${unresolvedPacks == 1 ? '' : 's'} antes de crear productos.';
    }
    final unresolved = selected
        .where(
            (entry) => entry.requiresDuplicateReview && !entry.isReadyToCreate)
        .length;
    if (unresolved > 0) {
      return 'Revisa $unresolved fila${unresolved == 1 ? '' : 's'}: vincula un producto existente o confirma que es nuevo.';
    }
    final isAliExpress =
        _parsedData != null && _looksLikeAliExpressInvoice(_parsedData!);
    final incomplete = selected
        .where((entry) =>
            !(isAliExpress ? entry.isValidWithoutSku : entry.isValid))
        .length;
    if (incomplete > 0) {
      final fields = isAliExpress
          ? 'nombre, categoría, costo y precio'
          : 'SKU, nombre, categoría, costo y precio';
      return 'Completa $fields en $incomplete fila${incomplete == 1 ? '' : 's'}.';
    }
    return null;
  }

  List<AIProductCategoryLeaf> _activeAIProductLeaves() {
    final parentIds = <String>{
      for (final category in _categories)
        if (category.parentId?.trim().isNotEmpty == true)
          category.parentId!.trim(),
    };
    final leaves = <AIProductCategoryLeaf>[
      for (final category in _categories)
        if (category.isActive &&
            category.id?.trim().isNotEmpty == true &&
            category.fullPath.trim().isNotEmpty &&
            !parentIds.contains(category.id!.trim()))
          AIProductCategoryLeaf(
            id: category.id!.trim(),
            path: category.fullPath.trim(),
          ),
    ]..sort((left, right) {
        final byPath = left.path.compareTo(right.path);
        return byPath != 0 ? byPath : left.id.compareTo(right.id);
      });
    return List<AIProductCategoryLeaf>.unmodifiable(leaves);
  }

  String _aiCategoryTreeVersion(List<AIProductCategoryLeaf> leaves) =>
      crypto.sha256
          .convert(utf8.encode(jsonEncode(<Object?>[
            for (final leaf in leaves) <String>[leaf.id, leaf.path],
          ])))
          .toString();

  String _aiCatalogVersion(List<inv_models.Product> products) {
    final eligible = products
        .where((product) => product.isActive && !product.isService)
        .map((product) => <String?>[
              product.id,
              product.sku,
              product.name,
              product.categoryId,
              product.brand,
              product.model,
              product.imageUrlOptimized ?? product.imageUrl,
            ])
        .toList()
      ..sort((left, right) => (left.first ?? '').compareTo(right.first ?? ''));
    return crypto.sha256.convert(utf8.encode(jsonEncode(eligible))).toString();
  }

  String? _aiLineContextWithoutVariant(_NewProductEntry entry) {
    final selectedVariant =
        _aliExpressVariantLabelForLine(entry.originalItem)?.trim() ?? '';
    final kept = <String>[];
    for (final rawLine
        in (entry.originalItem.rawRowText ?? '').split(RegExp(r'[\r\n]+'))) {
      var line = rawLine.trim();
      if (line.isEmpty ||
          RegExp(
            r'^(?:AI_[A-Z_]+|ORIGINAL_TITLE|LINE_TITLE|VARIANT(?:_KEY)?|ITEM_ID|PRODUCT_URL|IMAGE_URL|SOURCE_[A-Z_]+|RAW_[A-Z_]+|UNITS_PER_PURCHASE|INVENTORY_UNIT|SOURCE_ORDERS|SKU):',
            caseSensitive: false,
          ).hasMatch(line) ||
          RegExp(r'^https?://', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      if (selectedVariant.isNotEmpty &&
          _normalizeSimilarityText(line) ==
              _normalizeSimilarityText(selectedVariant)) {
        continue;
      }
      if (line == entry.supplierIdentityTitle || kept.contains(line)) continue;
      kept.add(line);
    }
    // Explicit operator edits are new row evidence and therefore belong to a
    // new receipt revision. They remain delimited as untrusted source data in
    // the prompt and never replace the immutable supplier title or variant.
    if (entry.nameUserEdited && entry.nameController.text.trim().isNotEmpty) {
      kept.add('OPERATOR_NAME_HINT: ${entry.nameController.text.trim()}');
    }
    final selectedCategory = entry.selectedCategory;
    if (entry.categoryUserEdited && selectedCategory?.id != null) {
      kept.add(
        'OPERATOR_CATEGORY_HINT: ${selectedCategory!.id!.trim()} | '
        '${selectedCategory.fullPath.trim()}',
      );
    }
    if (entry.brandUserEdited &&
        entry.selectedBrand?.name.trim().isNotEmpty == true) {
      kept.add('OPERATOR_BRAND_HINT: ${entry.selectedBrand!.name.trim()}');
    }
    return kept.isEmpty ? null : kept.join('\n');
  }

  /// Canonical first pass: one multimodal identity receipt for one row
  /// revision. It never writes catalog state and never falls back to the
  /// legacy synonym cleaner when the model fails.
  Future<void> _investigateProductEntriesAIPrimary({
    required int reviewGeneration,
    required int concurrency,
    required List<_NewProductEntry> targetEntries,
    required List<inv_models.Product> catalogProducts,
  }) async {
    if (!_ownsBulkReview(reviewGeneration)) return;
    final leaves = _activeAIProductLeaves();
    final treeVersion = _aiCategoryTreeVersion(leaves);
    final catalogVersion = _aiCatalogVersion(catalogProducts);
    final supplierName = _ocrSupplierName ?? widget.supplierName;
    final pending = targetEntries
        .where(_newProductEntries.contains)
        .where((entry) =>
            !entry.ownsInvestigationForRevision(entry.resolutionRevision))
        .toList(growable: false);
    for (final entry in pending) {
      entry.isAICleaningName = true;
    }
    if (pending.isNotEmpty && _ownsBulkReview(reviewGeneration)) {
      setState(() {});
    }

    Future<void> investigate(_NewProductEntry entry) async {
      final revision = entry.resolutionRevision;
      final sourceImageUrl = entry.imageUrl;
      AICleanedProductName? result;
      AIProductIdentityFailure? identityFailure;
      Object? failure;
      try {
        await _ensureEntryImageBytes(entry);
        if (!_ownsNewProductResolution(
              entry,
              revision,
              reviewGeneration: reviewGeneration,
            ) ||
            entry.imageUrl != sourceImageUrl) {
          return;
        }
        result = await _aiAssistantService.cleanProductTitleFromImage(
          rawTitle: entry.supplierIdentityTitle,
          imageBytes: entry.imageBytes,
          imageUrl: entry.imageUrl,
          supplierName: supplierName,
          selectedVariant: _aliExpressVariantLabelForLine(entry.originalItem),
          immutableVariantKey:
              _aliExpressImmutableVariantKeyForLine(entry.originalItem),
          supplierListingId: _aliExpressItemIdForLine(entry.originalItem),
          supplierCode: entry.supplierCode.isEmpty
              ? entry.originalItem.sku
              : entry.supplierCode,
          quantity: entry.originalItem.quantity,
          lineContext: _aiLineContextWithoutVariant(entry),
          cacheContext: entry.reviewId,
          cacheRevision: '$revision',
          rowRevision: '$revision',
          traceId: _productIdentityTraceId(entry, revision),
          categoryTreeKey: treeVersion,
          catalogKey: catalogVersion,
          activeLeafCategories: leaves,
          requireLeafAuthority: true,
          onFailure: (reported) => identityFailure = reported,
        );
        if (result == null) {
          failure = StateError(
            identityFailure?.operatorMessage ??
                'Falló la investigación IA antes de producir un recibo válido. '
                    'La fila se mantuvo sin recomendación y se puede reintentar.',
          );
        }
      } on Object catch (error) {
        failure = error;
      }
      if (!_ownsNewProductResolution(
            entry,
            revision,
            reviewGeneration: reviewGeneration,
          ) ||
          entry.imageUrl != sourceImageUrl) {
        return;
      }

      entry.aiInvestigationRevision = revision;
      entry.aiInvestigation = result?.identityInvestigation;
      entry.aiInvestigationError =
          identityFailure?.operatorMessage ?? failure?.toString();
      if (result != null) {
        entry.aiVisualAnalysis = result.visualAnalysis;
        entry.aiSuggestedComponentType = result.componentType;
        entry.aiSuggestedCategoryName = result.categoryName;
        entry.aiSuggestedBrandName = result.brand;
        entry.aiSuggestedModel = result.model;
        entry.aiSuggestionConfidence = result.confidence;
        if (!entry.nameUserEdited) {
          entry.applyAICleanedName(result.cleanedName);
        }
        final proposals = result.identityInvestigation?.leafProposals ??
            const <AIProductLeafProposal>[];
        if (!entry.categoryUserEdited && proposals.isNotEmpty) {
          final leafId = proposals.first.categoryId;
          for (final category in _categories) {
            if (category.id?.trim() == leafId) {
              entry.selectedCategory = category;
              entry.categoryReviewReason = null;
              entry.categoryEvidence = <String>[
                'Hoja activa propuesta por la investigación multimodal',
              ];
              break;
            }
          }
        }
        if (!entry.brandUserEdited) {
          final manufacturer = result.identityInvestigation?.manufacturer;
          final manufacturerName = manufacturer?.value?.trim();
          ProductBrand? resolvedBrand;
          if (manufacturer?.asserted == true &&
              manufacturerName?.isNotEmpty == true) {
            final wanted = _normalizeSimilarityText(manufacturerName!);
            for (final brand in _brands) {
              if (_normalizeSimilarityText(brand.name) == wanted) {
                resolvedBrand = brand;
                break;
              }
            }
          }
          entry.selectedBrand = resolvedBrand;
          ProductIdentityTrace.emit(
            traceId: _productIdentityTraceId(entry, revision),
            event: 'investigation.catalog_brand_resolution',
            data: <String, Object?>{
              'asserted_manufacturer': manufacturerName,
              'asserted': manufacturer?.asserted,
              'matched_brand_id': resolvedBrand?.id,
              'matched_brand_name': resolvedBrand?.name,
            },
          );
        }
      }
      entry.isAICleaningName = false;
      if (failure != null) {
        debugPrint('⚠️ [OCR] AI-first investigation failed: $failure');
      }
      if (_ownsBulkReview(reviewGeneration)) setState(() {});
    }

    final iterator = pending.iterator;
    await Future.wait(
        List.generate(math.min(concurrency, pending.length), (_) async {
      while (iterator.moveNext()) {
        if (!_ownsBulkReview(reviewGeneration)) return;
        await investigate(iterator.current);
      }
    }));
  }

  /// Run the AI cleaner over noisy supplier titles (e.g. AliExpress) and
  /// rewrite each row's name field with a short, shop-friendly title plus
  /// suggested category/brand. Skips rows the user has already edited.
  /// Concurrency is capped to avoid hammering the Gemini proxy.
  // Legacy deterministic cleaner retained only for regression diagnostics.
  // ignore: unused_element
  Future<void> _aiCleanProductNamesForEntries({
    required int reviewGeneration,
    int concurrency = 3,
    List<_NewProductEntry>? targetEntries,
  }) async {
    final entries = targetEntries ?? _newProductEntries;
    if (entries.isEmpty || !_ownsBulkReview(reviewGeneration)) {
      return;
    }

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
        'valves tubeless',
      ],
      'tee': ['potencia', 'potencias', 'stem', 'stems'],
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
      'portacaramagiola': 'Porta Caramagiola',
      'portabotella': 'Porta Caramagiola',
      'portabidon': 'Porta Caramagiola',
      'tija': 'Tija',
      'tee': 'Tee',
      'potencia': 'Tee',
      'stem': 'Tee',
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

    for (final entry in entries) {
      if (!_ownsBulkReview(reviewGeneration)) return;
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
      if (!entry.categoryUserEdited &&
          entry.selectedCategory == null &&
          addonCategory != null) {
        final match = resolveCategory(addonCategory);
        if (match != null) entry.selectedCategory = match;
      }
      // Category may use the legacy name fallback. Brand cannot: the add-on
      // value and the cleaned title are evidence inputs only, reconciled once
      // by the canonical identity semantics below.
      if (!entry.categoryUserEdited && entry.selectedCategory == null) {
        final viaName = scanCategoryInName(entry.nameController.text) ??
            scanCategoryInName(entry.originalNoisyTitle);
        if (viaName != null) entry.selectedCategory = viaName;
      }
    }

    for (final entry in entries) {
      if (!_ownsBulkReview(reviewGeneration)) return;
      if (entry.nameUserEdited) continue;
      if (entry.nameWasAICleaned) continue; // addon already cleaned this row
      entry.isAICleaningName = true;
    }
    if (_ownsBulkReview(reviewGeneration)) setState(() {});

    final pending =
        entries.where((e) => !e.nameUserEdited && !e.nameWasAICleaned).toList();
    if (pending.isEmpty) {
      // The add-on may already have cleaned every title, but its free-form
      // category/brand suggestions still need the same deterministic catalog
      // owner used by native OCR rows.
      if (!_ownsBulkReview(reviewGeneration)) return;
      _applyCanonicalProductSemantics(targetEntries: entries);
      if (_ownsBulkReview(reviewGeneration)) setState(() {});
      return;
    }
    final supplierName = _ocrSupplierName ?? widget.supplierName;

    Future<void> processOne(_NewProductEntry entry) async {
      final revision = entry.resolutionRevision;
      final sourceImageUrl = entry.imageUrl;
      try {
        final raw =
            (entry.originalNoisyTitle ?? entry.nameController.text).trim();
        if (raw.isEmpty) {
          entry.isAICleaningName = false;
          return;
        }
        await _ensureEntryImageBytes(entry);
        if (!_ownsBulkReview(reviewGeneration) ||
            !_ownsNewProductResolution(entry, revision) ||
            entry.imageUrl != sourceImageUrl) {
          return;
        }
        final result = await _aiAssistantService
            .cleanProductTitleFromImage(
              rawTitle: raw,
              imageBytes: entry.imageBytes,
              imageUrl: entry.imageUrl,
              supplierName: supplierName,
            )
            .timeout(
              const Duration(seconds: 20),
              onTimeout: () => throw TimeoutException(
                'La identificación por IA no respondió a tiempo.',
              ),
            );
        if (!_ownsBulkReview(reviewGeneration) ||
            !_ownsNewProductResolution(entry, revision) ||
            entry.imageUrl != sourceImageUrl) {
          return;
        }
        if (result != null) {
          entry.aiVisualAnalysis =
              result.visualAnalysis ?? entry.aiVisualAnalysis;
          entry.aiSuggestedComponentType = result.componentType;
          entry.aiSuggestedCategoryName = result.categoryName;
          entry.aiSuggestedBrandName = result.brand;
          entry.aiSuggestedModel = result.model;
          entry.aiSuggestionConfidence = result.confidence;
          entry.applyAICleanedName(result.cleanedName);
          if (!entry.categoryUserEdited &&
              entry.selectedCategory == null &&
              result.categoryName != null) {
            final match = resolveCategory(result.categoryName);
            if (match != null) entry.selectedCategory = match;
          }
          if (!entry.categoryUserEdited && entry.selectedCategory == null) {
            final viaName = scanCategoryInName(entry.nameController.text) ??
                scanCategoryInName(entry.originalNoisyTitle);
            if (viaName != null) entry.selectedCategory = viaName;
          }
        }
      } catch (e) {
        debugPrint('⚠️ [OCR] AI clean name failed for row: $e');
      } finally {
        if (_newProductEntries.contains(entry)) {
          entry.isAICleaningName = false;
        }
        if (_ownsBulkReview(reviewGeneration)) setState(() {});
      }
    }

    final iterator = pending.iterator;
    final workers = List.generate(concurrency, (_) async {
      while (iterator.moveNext()) {
        if (!_ownsBulkReview(reviewGeneration)) return;
        await processOne(iterator.current);
      }
    });
    await Future.wait(workers);
    if (!_ownsBulkReview(reviewGeneration)) return;
    _applyCanonicalProductSemantics(targetEntries: entries);
    if (_ownsBulkReview(reviewGeneration)) setState(() {});
  }

  void _applyCanonicalProductSemantics({
    List<_NewProductEntry>? targetEntries,
  }) {
    final entries = targetEntries ?? _newProductEntries;
    if (entries.isEmpty || _categories.isEmpty) return;

    final resolver = ProductCatalogSemanticResolver(
      categories: _categories,
      brands: _brands,
    );
    final entriesByRowId = <String, _NewProductEntry>{};
    final inputs = <ProductCatalogSemanticInput>[];
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      final rowId = 'ocr-row-$index';
      final semanticTitles = <String>{
        entry.originalItem.description.trim(),
        if (entry.originalNoisyTitle?.trim().isNotEmpty == true)
          entry.originalNoisyTitle!.trim(),
      }..removeWhere((title) => title.isEmpty);
      entriesByRowId[rowId] = entry;
      inputs.add(ProductCatalogSemanticInput(
        rowId: rowId,
        rawTitle: semanticTitles.join(' | '),
        supplierId: _supplierIdForNewProducts ?? widget.supplierId,
        listingId: _aliExpressItemIdForLine(entry.originalItem),
        variantKey: _aliExpressVariantKeyForLine(entry.originalItem),
        variantLabel: _aliExpressVariantLabelForLine(entry.originalItem),
        componentTypeHint: entry.aiSuggestedComponentType,
        categoryHint: entry.aiSuggestedCategoryName,
        brandHint: entry.aiSuggestedBrandName,
        hintConfidence: entry.aiSuggestionConfidence,
      ));
    }

    final objectResolver = ProductCategoryResolver(categories: _categories);

    for (final resolution in resolver.resolveAll(inputs)) {
      final entry = entriesByRowId[resolution.rowId];
      if (entry == null) continue;
      entry.semanticFamily = resolution.family;
      entry.semanticConfidence = resolution.confidence;
      entry.semanticReviewReason = resolution.reviewReason;
      entry.semanticEvidence = resolution.evidence;

      final hasDeterministicFamily =
          resolution.family != ProductCatalogSemanticResolver.unknownFamily;
      final rejectedCategoryHint = resolution.evidence.any(
        (item) =>
            item.kind ==
                ProductCatalogSemanticEvidenceKind.rejectedCategoryHint ||
            item.kind == ProductCatalogSemanticEvidenceKind.unresolvedCategory,
      );
      // What the thing IS decides where it goes, before any hint does.
      //
      // The old order let a hint derived from the words win, and the words of a
      // bracket name the system it serves. Object-first resolution answers from
      // the photo and the head noun, refuses a parent node, and refuses
      // outright when the two disagree — which is why a `Herradura` can no
      // longer be filed under `Frenos`. It only steps aside where it has
      // nothing to say, and there the catalog resolver still answers.
      final objectCategory = _resolveObjectFirstCategory(entry, objectResolver);
      var categoryOutcomeHandled = false;
      if (!entry.categoryUserEdited && objectCategory != null) {
        entry.categoryReviewReason = objectCategory.reviewReason;
        if (objectCategory.isResolved) {
          entry.selectedCategory = objectCategory.category;
          entry.aiSuggestedCategoryName = objectCategory.category?.fullPath;
          entry.categoryEvidence =
              List<String>.unmodifiable(objectCategory.evidence);
          categoryOutcomeHandled = true;
        }
        if (objectCategory.refusal ==
            ProductCategoryRefusal.conflictingEvidence) {
          // Fail closed. A plausible leaf chosen while the photo and the title
          // name different objects is the exact wrong answer this refuses.
          entry.selectedCategory = null;
          entry.aiSuggestedCategoryName = null;
          entry.categoryEvidence =
              List<String>.unmodifiable(objectCategory.evidence);
          categoryOutcomeHandled = true;
        }
      }
      if (!categoryOutcomeHandled &&
          !entry.categoryUserEdited &&
          (resolution.category != null ||
              hasDeterministicFamily ||
              rejectedCategoryHint)) {
        entry.selectedCategory = resolution.category;
        // The free-form AI hint is no longer authoritative once the catalog
        // resolver has accepted or rejected it.
        entry.aiSuggestedCategoryName = resolution.category?.fullPath;
      }
      if (!entry.brandUserEdited) {
        // This is the sole non-user write to selectedBrand. A missing or
        // rejected canonical assertion explicitly clears stale add-on/AI
        // guesses, so matcher display and creation payload cannot diverge.
        entry.selectedBrand = resolution.brand;
      }

      if (!entry.nameUserEdited &&
          resolution.family == ProductCatalogSemanticResolver.stemFamily) {
        final canonicalName =
            ProductCatalogSemanticResolver.canonicalizeDisplayName(
          name: entry.nameController.text,
          family: resolution.family,
        );
        entry.applyAICleanedName(canonicalName);
      }
    }
  }

  /// Reads one row as an object, then places it.
  ///
  /// The photo evidence is the reading the title cleaner already paid for; no
  /// extra model call is made here. When the row has no usable photo the
  /// resolver still runs on the words alone — it simply has one fewer witness.
  ProductCategoryResolution? _resolveObjectFirstCategory(
    _NewProductEntry entry,
    ProductCategoryResolver objectResolver,
  ) {
    if (_categories.isEmpty) return null;
    final title = entry.nameController.text.trim();
    final sourceTitle = entry.supplierIdentityTitle;
    final noisyTitle = sourceTitle;
    final name = title.isNotEmpty ? title : sourceTitle;
    if (name.isEmpty) return null;

    var profile = ProductIdentityExtractor.extract(
      ProductIdentityInput(
        name: name,
        description: noisyTitle == name ? sourceTitle : noisyTitle,
        // Same rule as the matcher: the supplier's own words decide the
        // object, so a mislabelled AI name cannot file the row under the
        // wrong shelf either.
        sourceTitle: sourceTitle,
        knownBrands: _brands.map((brand) => brand.name),
      ),
    );
    final analysis = entry.aiVisualAnalysis;
    if (analysis != null) {
      final reading = ProductVisualReadingService.fromAnalysis(analysis);
      if (reading.isUseful) {
        profile = profile.withVisualReading(
          visualFamilyId: reading.familyId,
          visualTerms: reading.terms,
          visualConfidence: reading.confidence,
        );
      }
    }
    return objectResolver.resolve(profile);
  }

  String? _duplicateMatcherCategoryName(_NewProductEntry entry) {
    final selected = entry.selectedCategory;
    if (selected != null) return selected.fullPath;
    if (entry.categoryUserEdited) return null;
    final hintWasRejected = entry.semanticEvidence.any(
      (evidence) =>
          evidence.kind ==
              ProductCatalogSemanticEvidenceKind.rejectedCategoryHint ||
          evidence.kind ==
              ProductCatalogSemanticEvidenceKind.unresolvedCategory,
    );
    return hintWasRejected ? null : entry.aiSuggestedCategoryName;
  }

  String? _duplicateMatcherBrandName(_NewProductEntry entry) {
    // Only the operator or the supplier's own title may assert a maker. The
    // multimodal cleaner's brand is a hint for semantic reconciliation;
    // asserting it made a hallucinated `Alligator` eliminate the existing T6
    // light and poisoned the grounded AI tie-break prompt.
    if (entry.brandUserEdited) return entry.selectedBrand?.name;

    // Explicit source evidence (for example IXF printed in the title) may be
    // useful to the matcher even when that brand has not yet been added to the
    // tenant catalog. It must outrank a rejected AI compatibility guess.
    for (final evidence in entry.semanticEvidence) {
      if (evidence.kind == ProductCatalogSemanticEvidenceKind.explicitBrand) {
        final explicit = evidence.detail.trim();
        if (explicit.isNotEmpty) return explicit;
      }
    }
    return null;
  }

  /// One matcher per review session, holding the catalog identity index.
  ///
  /// The index is what makes the second and later lines of an invoice cheap:
  /// the catalog is analysed once, not once per line. Building a matcher per
  /// line would throw that away, so both entry points come through here.
  ///
  /// The tenant's real brands and category tree are handed over because the
  /// matcher cannot invent them: `IXF` is printed on the invoice but has no
  /// `product_brands` row, and only the tree knows that `Corta Cadena` is a
  /// child of `Herramientas`.
  ProductDuplicateMatcherService _buildDuplicateMatcher(
    inv_service.InventoryService inventoryService,
  ) {
    return ProductDuplicateMatcherService(
      inventoryService: inventoryService,
      aiAssistantService: _aiAssistantService,
      knownBrands: _brands.map((brand) => brand.name),
      categories: _categories,
      categoryAncestry:
          ProductCatalogIdentityIndex.buildCategoryAncestry(_categories),
      // Product review is a read path. Missing catalog fingerprints can be
      // backfilled by their maintenance owner; an operator waiting on one
      // invoice must not pay for hidden product writes.
      persistComputedImageFingerprints: false,
      requireAIPrimaryInvestigation: true,
    );
  }

  Future<void> _checkSimilarProductsForNewEntries({
    _NewProductEntry? entry,
    List<_NewProductEntry>? targetEntries,
    bool autoTriggered = false,
    required int reviewGeneration,
    inv_service.InventoryService? preparedInventoryService,
    List<inv_models.Product>? preparedProducts,
    ProductDuplicateMatcherService? preparedMatcher,
  }) async {
    if (!_ownsBulkReview(reviewGeneration)) return;
    if (_creatingProducts || _isOpeningBulkCreate) {
      return;
    }
    final requestedEntries =
        targetEntries ?? (entry == null ? _newProductEntries : [entry]);
    final entries = requestedEntries
        .where(_newProductEntries.contains)
        .where(_needsSimilaritySearch)
        .toList(growable: false);
    if (entries.isEmpty) return;
    setState(() {
      for (final current in entries) {
        current.markSearching();
      }
    });

    try {
      final inventoryService = preparedInventoryService ??
          context.read<inv_service.InventoryService>();
      final hasCurrentCatalogSnapshot =
          _productReviewCatalogGeneration == reviewGeneration &&
              _productReviewCatalogSnapshot != null;
      // A review must compare every retry against one stable catalog version.
      // InventoryService intentionally expires its normal five-minute cache,
      // but the already hydrated rows remain the exact snapshot this open
      // review used. Reuse them instead of making an operator retry depend on
      // another 1,600-row database query that can time out midway.
      final inheritedInventorySnapshot = !hasCurrentCatalogSnapshot &&
              inventoryService.hasProductsCache &&
              inventoryService.cachedProducts.isNotEmpty
          ? inventoryService.cachedProducts
          : null;
      final allProducts = preparedProducts ??
          (hasCurrentCatalogSnapshot
              ? _productReviewCatalogSnapshot!
              : inheritedInventorySnapshot ??
                  await inventoryService.getProducts());
      if (!_ownsBulkReview(reviewGeneration)) return;
      final duplicateMatcher = preparedMatcher ??
          (hasCurrentCatalogSnapshot && _productReviewDuplicateMatcher != null
              ? _productReviewDuplicateMatcher!
              : _buildDuplicateMatcher(inventoryService));
      _productReviewCatalogSnapshot = allProducts;
      _productReviewDuplicateMatcher = duplicateMatcher;
      _productReviewCatalogGeneration = reviewGeneration;
      ProductIdentityTrace.emit(
        traceId: _productIdentityTraceId(
          entries.first,
          entries.first.resolutionRevision,
        ),
        event: 'catalog_snapshot.resolved',
        data: <String, Object?>{
          'product_count': allProducts.length,
          'source': preparedProducts != null
              ? 'prepared_initial_load'
              : hasCurrentCatalogSnapshot
                  ? 'review_memory_cache'
                  : inheritedInventorySnapshot != null
                      ? 'inventory_hydrated_snapshot'
                      : 'database_retry_load',
          'matcher_reused': preparedMatcher != null ||
              (hasCurrentCatalogSnapshot &&
                  _productReviewDuplicateMatcher != null),
          'review_generation': reviewGeneration,
        },
      );

      // The primary investigation already sent this photo to the model and
      // recorded what object it shows. Handing that same reading to the
      // validator prevents a second vision request for the row.
      for (final current in entries) {
        final analysis = current.aiVisualAnalysis;
        if (analysis == null) continue;
        duplicateMatcher.primeVisualReading(
          imageUrl: current.imageUrl,
          imageBytes: current.imageBytes,
          analysis: analysis,
        );
      }

      Future<void> processOne(_NewProductEntry current) async {
        final revision = current.resolutionRevision;
        try {
          final coordination = await const ProductIdentityReviewCoordinator<
                  SupplierVariantResolution, ProductDuplicateSearchResult>()
              .resolve(
            lookupAuthority: () async {
              final traceId = _productIdentityTraceId(current, revision);
              ProductIdentityTrace.emit(
                traceId: traceId,
                event: 'authority.lookup_start',
                data: <String, Object?>{
                  'listing_present':
                      _aliExpressItemIdForLine(current.originalItem) != null,
                  'immutable_variant_present':
                      _aliExpressImmutableVariantKeyForLine(
                            current.originalItem,
                          ) !=
                          null,
                },
              );
              try {
                final authority =
                    await _resolveSupplierVariantResolution(current);
                ProductIdentityTrace.emit(
                  traceId: traceId,
                  event: 'authority.lookup_complete',
                  data: <String, Object?>{
                    'found': authority != null,
                    'authoritative': authority?.isResolved,
                    'revision_id': authority?.revisionId,
                    'resolution_kind': authority?.kind?.name,
                    'edge_count': authority?.edges.length ?? 0,
                  },
                );
                return authority;
              } on Object catch (error) {
                ProductIdentityTrace.emit(
                  traceId: traceId,
                  event: 'authority.lookup_failed',
                  data: <String, Object?>{
                    'error_type': error.runtimeType.toString(),
                  },
                );
                rethrow;
              }
            },
            investigate: () async {
              if (!current.ownsInvestigationForRevision(revision)) {
                await _investigateProductEntriesAIPrimary(
                  reviewGeneration: reviewGeneration,
                  concurrency: 1,
                  targetEntries: <_NewProductEntry>[current],
                  catalogProducts: allProducts,
                );
              }
              return current.aiInvestigation;
            },
            match: (_) => duplicateMatcher.resolveCandidates(
              probe: _duplicateProbeFor(current),
              products: allProducts,
            ),
          );
          if (!_ownsNewProductResolution(
            current,
            revision,
            reviewGeneration: reviewGeneration,
          )) {
            return;
          }
          if (coordination is ProductIdentityAuthorityCoordination<
              SupplierVariantResolution, ProductDuplicateSearchResult>) {
            final applied = await _useSupplierVariantResolutionForEntry(
              current,
              coordination.authority,
              inventoryService: inventoryService,
              products: allProducts,
              expectedRevision: revision,
              reviewGeneration: reviewGeneration,
            );
            if (!applied) {
              throw StateError(
                'La autoridad inmutable no pudo materializarse en la fila.',
              );
            }
            return;
          }
          if (coordination is ProductIdentityFailedCoordination<
              SupplierVariantResolution, ProductDuplicateSearchResult>) {
            throw coordination.failure;
          }
          final result = (coordination as ProductIdentityMatchedCoordination<
                  SupplierVariantResolution, ProductDuplicateSearchResult>)
              .result;
          // Ignore a stale response if the worker edited identity fields while
          // the matcher was running. The row returns to "Buscar" instead.
          if (!_ownsNewProductResolution(
            current,
            revision,
            reviewGeneration: reviewGeneration,
          )) {
            return;
          }
          final resolutionProposal = await _buildSupplierResolutionProposal(
            current,
            result,
            inventoryService: inventoryService,
            products: allProducts,
          );
          if (!_ownsNewProductResolution(
            current,
            revision,
            reviewGeneration: reviewGeneration,
          )) {
            return;
          }
          current.markSearchResult(
            result,
            supplierResolutionProposal: resolutionProposal,
          );
          ProductIdentityTrace.emit(
            traceId: _productIdentityTraceId(current, revision),
            event: 'row.final_decision',
            data: <String, Object?>{
              'kind': result.kind.name,
              'adjudication_state': result.adjudicationState.name,
              'recommendation_ids': result.recommendations
                  .map((candidate) => candidate.product.id)
                  .toList(growable: false),
              'operator_choice_count': result.operatorChoices.length,
              'category_conflict_count': result.categoryConflicts.length,
              'reason': result.reason,
              'resolution_proposal_kind': resolutionProposal?.kind.name,
              'resolution_proposal_edges': resolutionProposal?.edges.length,
              'resolution_proposal_uses_catalog_set':
                  resolutionProposal?.usesCanonicalSet,
            },
          );
        } catch (error) {
          if (_ownsNewProductResolution(
            current,
            revision,
            reviewGeneration: reviewGeneration,
          )) {
            current.markResolutionFailed(error);
          }
          ProductIdentityTrace.emit(
            traceId: _productIdentityTraceId(current, revision),
            event: 'row.failed',
            data: <String, Object?>{
              'error_type': error.runtimeType.toString(),
              'error': error.toString(),
            },
          );
          debugPrint('Error checking OCR row for duplicates: $error');
        }
        if (_ownsBulkReview(reviewGeneration)) setState(() {});
      }

      // A whole invoice used to await every row serially. Three workers keep
      // network/AI pressure bounded while allowing independent rows to
      // publish results as soon as they finish.
      final iterator = entries.iterator;
      final workerCount = math.min(3, entries.length);
      await Future.wait(List.generate(workerCount, (_) async {
        while (iterator.moveNext()) {
          if (!_ownsBulkReview(reviewGeneration)) return;
          await processOne(iterator.current);
        }
      }));
      if (!_ownsBulkReview(reviewGeneration)) return;
      _reconcileListingGroupResults();
      _traceDuplicateSearchResults(entries);
    } catch (e) {
      debugPrint('Error checking OCR similar products: $e');
      if (!_ownsBulkReview(reviewGeneration)) return;
      setState(() {
        for (final current in entries) {
          if (_newProductEntries.contains(current) &&
              current.isCheckingSimilar &&
              current.resolutionState == OcrProductResolutionState.searching) {
            current.markResolutionFailed(e);
          }
        }
      });
    }
  }

  /// Applies the document-level constraint only after every row in this
  /// listing group has independently passed the normal hard gates.
  ///
  /// The resolver can only downgrade a dissenting row to abstention and put a
  /// common viable option first for manual review. It never revives a
  /// discarded product, creates a recommendation, or assumes one listing is
  /// one product; front/rear and measured variants therefore remain separate.
  void _reconcileListingGroupResults() {
    final supplierId = (_supplierIdForNewProducts ?? widget.supplierId)?.trim();
    final rows = <ProductDuplicateListingGroupRow>[
      for (final entry in _newProductEntries)
        if (entry.independentDuplicateResult != null)
          if (entry.linkedProduct == null &&
              !entry.hasSupplierResolution &&
              entry.resolutionState != OcrProductResolutionState.newProduct)
            ProductDuplicateListingGroupRow(
              rowId: entry.reviewId,
              supplierId: supplierId,
              supplierListingId: _aliExpressItemIdForLine(entry.originalItem),
              immutableVariantKey:
                  _aliExpressImmutableVariantKeyForLine(entry.originalItem),
              deterministicTopCandidate:
                  entry.independentDuplicateResult!.deterministicTopCandidate,
              result: entry.independentDuplicateResult!,
            ),
    ];
    final reconciled = const ProductDuplicateListingGroupResolver().resolve(
      rows,
    );
    if (!mounted) return;
    setState(() {
      for (final entry in _newProductEntries) {
        final independent = entry.independentDuplicateResult;
        if (independent == null) continue;
        final groupResult = reconciled[entry.reviewId];
        final finalResult = groupResult ?? independent;
        if (kDebugMode) {
          debugPrint('[OCR_AI_TRACE] ${jsonEncode(<String, Object?>{
                'event': 'listing_group.decision',
                'reviewId': entry.reviewId,
                'listingId': _aliExpressItemIdForLine(entry.originalItem),
                'variantKey': _aliExpressImmutableVariantKeyForLine(
                  entry.originalItem,
                ),
                'deterministicTopSku':
                    independent.deterministicTopCandidate?.product.sku,
                'independentKind': independent.kind.name,
                'independentTopSku': independent.recommendations.isEmpty
                    ? null
                    : independent.recommendations.first.product.sku,
                'adjudicationState': independent.adjudicationState.name,
                'aiDecision': independent.adjudication?.decision.name,
                'groupOverride': groupResult != null,
                'finalKind': finalResult.kind.name,
                'finalTopSku': finalResult.recommendations.isEmpty
                    ? null
                    : finalResult.recommendations.first.product.sku,
                'finalReason': finalResult.reason,
              })}');
        }
        entry.applyReconciledSearchResult(finalResult);
      }
    });
  }

  /// Durable, structured evidence for real-invoice audits. The compact UI and
  /// picker intentionally hide numeric ranking values; the debug trace keeps
  /// the exact candidate/gate/adjudication decision inspectable without
  /// recomputing the matcher or mutating the invoice.
  void _traceDuplicateSearchResults(List<_NewProductEntry> entries) {
    if (!kDebugMode) return;
    for (final entry in entries) {
      final result = entry.duplicateResult;
      if (result == null) continue;
      debugPrint('[OCR-MATCH] ${jsonEncode(<String, Object?>{
            'reviewId': entry.reviewId,
            'sourceRowIndex': entry.sourceRowIndex,
            'listingId': _aliExpressItemIdForLine(entry.originalItem),
            'variantKey':
                _aliExpressImmutableVariantKeyForLine(entry.originalItem),
            'selectedVariant':
                _aliExpressVariantLabelForLine(entry.originalItem),
            'family': result.probeIdentity.resolvedFamilyId,
            'category': result.probeIdentity.category?.label,
            'kind': result.kind.name,
            'adjudication': result.adjudicationState.name,
            'aiDecision': result.adjudication?.decision.name,
            'aiLeafIds': result.investigation?.leafProposals
                .map((proposal) => proposal.categoryId)
                .toList(growable: false),
            'aiComposition': result.investigation?.composition.kind.name,
            'reason': result.reason,
            'recommendations': [
              for (final candidate in result.recommendations)
                _duplicateTraceCandidate(candidate),
            ],
            'normalCandidates': [
              for (final candidate in result.normalCandidates)
                _duplicateTraceCandidate(candidate),
            ],
            'operatorChoices': [
              for (final candidate in result.operatorChoices)
                _duplicateTraceCandidate(candidate),
            ],
            'categoryConflicts': [
              for (final candidate in result.categoryConflicts)
                _duplicateTraceCandidate(candidate),
            ],
          })}');
    }
  }

  Map<String, Object?> _duplicateTraceCandidate(
    ProductDuplicateCandidate candidate,
  ) =>
      <String, Object?>{
        'id': candidate.product.id,
        'sku': candidate.product.sku,
        'tier': candidate.matchTier.name,
        'score': candidate.confidence,
        'lineScore': candidate.lineConfidence,
        'variantAgreement': candidate.variantAgreement,
        'ruledOut': candidate.isRuledOut,
        'reviewOnlyFamilyScope': candidate.isReviewOnlyFamilyScope,
        'reasons': candidate.reasons,
        'objections': candidate.objections,
        'failedGates': [
          for (final gate in candidate.gates)
            if (gate.failed)
              <String, Object?>{
                'id': gate.id,
                'detail': gate.detail,
              },
        ],
      };

  bool _ownsNewProductResolution(
    _NewProductEntry entry,
    int revision, {
    int? reviewGeneration,
  }) {
    return mounted &&
        _newProductEntries.contains(entry) &&
        entry.resolutionRevision == revision &&
        (reviewGeneration == null || _ownsBulkReview(reviewGeneration));
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

  Future<bool> _useExistingProductForEntry(
    _NewProductEntry entry,
    inv_models.Product product, {
    int? expectedRevision,
    int? reviewGeneration,
  }) async {
    if (_readOnlyEvaluationBlocksMutations) return false;
    final revision = expectedRevision ?? entry.resolutionRevision;
    final productId = product.id;
    if (productId == null ||
        _parsedData == null ||
        !_ownsNewProductResolution(
          entry,
          revision,
          reviewGeneration: reviewGeneration,
        )) {
      return false;
    }

    if (SupplierOptionEvidence.requiresExplicitCompositionFor(
      packCount: entry.originalItem.rawPackCount,
      rawUnitToken: entry.originalItem.rawUnitToken,
      packEvidenceConflict: entry.originalItem.rawPackEvidenceConflict,
    )) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Esta variante declara un pack o conjunto. Confirma primero '
            'cuántas unidades de catálogo contiene; no se vinculó como un '
            'producto simple.',
          ),
          backgroundColor: VinabikeThemeRoles.of(context).warning.accent,
        ),
      );
      return false;
    }

    // A picker decision applies only to this invoice draft. Persisting it here
    // made a later correction diverge from durable supplier authority. New
    // product creation and the dedicated graph flow remain the only writers.

    final oldItem = entry.originalItem;
    final existingSku = product.sku.trim();
    final updatedItem = oldItem.copyWith(
      description: product.name,
      existsInDatabase: true,
      matchedProductId: productId,
      matchedProductName: product.name,
      currentStock: product.inventoryQty,
      sku: existingSku.isNotEmpty ? existingSku : oldItem.sku,
      supplierResolution: null,
      clearSupplierResolution: true,
    );

    if (!_ownsNewProductResolution(
          entry,
          revision,
          reviewGeneration: reviewGeneration,
        ) ||
        _parsedData == null) {
      return false;
    }
    final parsedData = _parsedData!;
    final rowIndex = parsedData.lineItems.indexOf(oldItem);
    final updatedItems = parsedData.lineItems.map((item) {
      return identical(item, oldItem) || item == oldItem ? updatedItem : item;
    }).toList();

    if (rowIndex >= 0) {
      _skuControllers[rowIndex]?.text = updatedItem.sku ?? '';
    }

    if (!_ownsNewProductResolution(
      entry,
      revision,
      reviewGeneration: reviewGeneration,
    )) {
      return false;
    }
    setState(() {
      _parsedData = parsedData.copyWith(lineItems: updatedItems);
      if (_baseParsedData != null &&
          rowIndex >= 0 &&
          rowIndex < _baseParsedData!.lineItems.length) {
        final baseItems = List<ParsedLineItem>.from(_baseParsedData!.lineItems);
        baseItems[rowIndex] = updatedItem;
        _baseParsedData = _baseParsedData!.copyWith(lineItems: baseItems);
      }
      entry.markLinkedProduct(product);
      // The row now shows the code of the product it points at. Its own
      // reservation is kept, not released: going back to «Nuevo» must restore
      // the same number without spending another one.
      entry.syncSkuField();
    });
    _reconcileListingGroupResults();
    return true;
  }

  void _changeProductDecision(_NewProductEntry entry) {
    if (!mounted || _parsedData == null) return;
    if (entry.isReservingSku) return;
    if (entry.hasSupplierResolution) return;
    if (entry.linkedProduct == null) {
      if (entry.resolutionState != OcrProductResolutionState.newProduct) return;
      setState(() {
        entry.resolutionState = entry.similarCandidates.isEmpty
            ? entry.duplicateResult?.kind ==
                    ProductDuplicateDecisionKind.abstained
                ? OcrProductResolutionState.abstained
                : OcrProductResolutionState.noCandidates
            : OcrProductResolutionState.reviewRequired;
      });
      return;
    }
    final rowIndex = entry.sourceRowIndex;
    if (rowIndex < 0 || rowIndex >= _parsedData!.lineItems.length) return;

    final parsedItems = List<ParsedLineItem>.from(_parsedData!.lineItems);
    parsedItems[rowIndex] = entry.originalItem;
    List<ParsedLineItem>? baseItems;
    if (_baseParsedData != null &&
        rowIndex < _baseParsedData!.lineItems.length) {
      baseItems = List<ParsedLineItem>.from(_baseParsedData!.lineItems);
      baseItems[rowIndex] = entry.originalItem;
    }

    setState(() {
      _parsedData = _parsedData!.copyWith(lineItems: parsedItems);
      if (_baseParsedData != null && baseItems != null) {
        _baseParsedData = _baseParsedData!.copyWith(lineItems: baseItems);
      }
      _skuControllers[rowIndex]?.text = entry.originalItem.sku ?? '';
      entry.clearLinkedProduct();
      // Back to undecided: the row shows its own reservation again if it ever
      // got one, and no RPC is spent to recover it.
      entry.syncSkuField();
    });
    _reconcileListingGroupResults();
  }

  String? _aliExpressItemIdForLine(ParsedLineItem item) {
    final ids = _extractAliExpressItemIds(
      '${item.productUrl ?? ''}\n${item.rawRowText ?? ''}',
    );
    return ids.isEmpty ? null : ids.first;
  }

  String? _aliExpressVariantKeyForLine(ParsedLineItem item) {
    final structured = item.variantKey?.trim();
    if (structured != null && structured.isNotEmpty) {
      return _normalizeSimilarityText(structured).replaceAll(' ', '-');
    }
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
    final legacyLabel = RegExp(r'\(([^()]{1,120})\)\s*$')
        .firstMatch(item.description)
        ?.group(1)
        ?.trim();
    if (legacyLabel != null && legacyLabel.isNotEmpty) {
      return _normalizeSimilarityText(legacyLabel).replaceAll(' ', '-');
    }
    final imageUri = Uri.tryParse(item.imageUrl?.trim() ?? '');
    final imageSegment = imageUri?.pathSegments.isNotEmpty == true
        ? imageUri!.pathSegments.last.trim()
        : '';
    if (imageSegment.isNotEmpty) {
      return 'image-${_normalizeSimilarityText(imageSegment).replaceAll(' ', '-')}';
    }
    // A listing with no variant still has a stable supplier identity. Keeping
    // it as `default` lets the second import use the learned alias instead of
    // paying for the full matcher forever.
    return 'default';
  }

  /// Exact alias authority is intentionally narrower than display/grouping
  /// identity. A translated label, image filename or `default` can help keep
  /// invoice rows together, but cannot prove which sold listing variant maps
  /// to a catalog product.
  String? _aliExpressImmutableVariantKeyForLine(ParsedLineItem item) {
    final raw = item.rawRowText ?? '';
    final value = (item.variantKey?.trim().isNotEmpty == true
            ? item.variantKey!.trim()
            : RegExp(
                r'^VARIANT_KEY:\s*(.+)$',
                caseSensitive: false,
                multiLine: true,
              ).firstMatch(raw)?.group(1)?.trim())
        ?.toLowerCase();
    if (value == null || value.isEmpty) return null;
    if (!value.startsWith('sku:') && !value.startsWith('props:')) return null;
    return value;
  }

  String? _aliExpressVariantLabelForLine(ParsedLineItem item) {
    final structured = item.variantLabel?.trim();
    if (structured != null && structured.isNotEmpty) return structured;
    final raw = item.rawRowText ?? '';
    final value = RegExp(
      r'^VARIANT:\s*(.+)$',
      caseSensitive: false,
      multiLine: true,
    ).firstMatch(raw)?.group(1)?.trim();
    if (value != null && value.isNotEmpty) return value;
    final legacyLabel = RegExp(r'\(([^()]{1,120})\)\s*$')
        .firstMatch(item.description)
        ?.group(1)
        ?.trim();
    return legacyLabel == null || legacyLabel.isEmpty ? null : legacyLabel;
  }

  SupplierOptionEvidence? _supplierOptionEvidenceForLine(
    ParsedLineItem item,
  ) {
    final variantKey = _aliExpressImmutableVariantKeyForLine(item);
    if (variantKey == null) return null;
    try {
      return SupplierOptionEvidence(
        variantKey: variantKey,
        packCount: item.rawPackCount,
        rawUnitToken: item.rawPackCount == null ? null : item.rawUnitToken,
        packEvidenceConflict: item.rawPackEvidenceConflict,
      );
    } on ArgumentError catch (error) {
      debugPrint('Supplier option evidence is contradictory: $error');
      return null;
    } on FormatException catch (error) {
      debugPrint('Supplier option evidence is not immutable: $error');
      return null;
    }
  }

  Future<SupplierVariantResolution?> _resolveSupplierVariantResolution(
    _NewProductEntry entry,
  ) async {
    if (!entry.requiresDuplicateReview) return null;
    final supplierId = (_supplierIdForNewProducts ?? widget.supplierId)?.trim();
    final itemId = _aliExpressItemIdForLine(entry.originalItem);
    final rawRowText = entry.originalItem.rawRowText ?? '';
    final declaredVariantKey =
        (entry.originalItem.variantKey?.trim().isNotEmpty == true
                ? entry.originalItem.variantKey!.trim()
                : RegExp(
                    r'^VARIANT_KEY:\s*(.+)$',
                    caseSensitive: false,
                    multiLine: true,
                  ).firstMatch(rawRowText)?.group(1)?.trim()) ??
            '';
    final immutableVariantKey =
        _aliExpressImmutableVariantKeyForLine(entry.originalItem);
    if (supplierId == null || supplierId.isEmpty) {
      throw StateError(
        'No se pudo comprobar la autoridad del proveedor: falta supplierId.',
      );
    }
    if (itemId == null || itemId.isEmpty) {
      throw StateError(
        'No se pudo comprobar la autoridad del proveedor: falta listingId.',
      );
    }
    // A listing with no immutable option key has no exact graph address and
    // may continue to investigation. A key that exists but cannot be parsed
    // is malformed authority input and must fail closed before any AI call.
    if (immutableVariantKey == null) {
      if (declaredVariantKey.isNotEmpty) {
        throw StateError(
          'La clave de variante declarada no es inmutable; no se consultó IA.',
        );
      }
      return null;
    }
    final evidence = _supplierOptionEvidenceForLine(entry.originalItem);
    if (evidence == null) {
      throw StateError(
        'La evidencia de variante inmutable es inválida; no se consultó IA.',
      );
    }
    final result = await SupplierVariantResolutionService(
      database: context.read<DatabaseService>(),
    ).resolve(
      supplierId: supplierId,
      itemId: itemId,
      productUrl: entry.originalItem.productUrl?.trim() ?? '',
      optionEvidence: evidence,
    );
    if (result.isResolved) return result;
    if (result.status == SupplierVariantResolutionStatus.notFound) return null;
    throw StateError(
      result.failureReason?.trim().isNotEmpty == true
          ? result.failureReason!.trim()
          : 'La resolución inmutable del proveedor no pudo comprobarse '
              '(${result.status.databaseValue}).',
    );
  }

  Future<bool> _useSupplierVariantResolutionForEntry(
    _NewProductEntry entry,
    SupplierVariantResolution resolution, {
    required inv_service.InventoryService inventoryService,
    required List<inv_models.Product> products,
    required int expectedRevision,
    required int reviewGeneration,
  }) async {
    if (!resolution.isResolved || resolution.edges.isEmpty) return false;
    final byId = <String, inv_models.Product>{
      for (final product in products)
        if (product.id != null) product.id!: product,
    };
    for (final edge in resolution.edges) {
      if (byId.containsKey(edge.productId)) continue;
      final product = await inventoryService.getProductById(edge.productId);
      if (product != null) byId[edge.productId] = product;
    }
    if (!_ownsNewProductResolution(
      entry,
      expectedRevision,
      reviewGeneration: reviewGeneration,
    )) {
      return false;
    }
    final resolvedProducts = <inv_models.Product>[];
    for (final edge in resolution.edges) {
      final product = byId[edge.productId];
      if (product == null || !product.isActive || product.isService) {
        throw StateError(
          'La resolución del proveedor apunta a un producto no utilizable.',
        );
      }
      resolvedProducts.add(product);
    }

    final parsed = _parsedData;
    if (parsed == null) return false;
    final oldItem = entry.originalItem;
    final rowIndex = parsed.lineItems.indexOf(oldItem);
    if (rowIndex < 0) return false;
    final singleProduct =
        resolvedProducts.length == 1 ? resolvedProducts.single : null;
    final resolvedName = resolvedProducts.map((product) => product.name).join(
          ' + ',
        );
    final resolvedSku = resolvedProducts.map((product) => product.sku).join(
          ' + ',
        );
    final updatedItem = oldItem.copyWith(
      supplierResolution: resolution,
      existsInDatabase: true,
      matchedProductId: singleProduct?.id,
      matchedProductName: resolvedName,
      currentStock: singleProduct?.inventoryQty,
      sku: singleProduct == null ? oldItem.sku : resolvedSku,
    );
    final updatedItems = List<ParsedLineItem>.from(parsed.lineItems)
      ..[rowIndex] = updatedItem;
    List<ParsedLineItem>? baseItems;
    if (_baseParsedData != null &&
        rowIndex < _baseParsedData!.lineItems.length) {
      baseItems = List<ParsedLineItem>.from(_baseParsedData!.lineItems)
        ..[rowIndex] = updatedItem;
    }
    if (!_ownsNewProductResolution(
      entry,
      expectedRevision,
      reviewGeneration: reviewGeneration,
    )) {
      return false;
    }
    setState(() {
      _parsedData = parsed.copyWith(lineItems: updatedItems);
      if (_baseParsedData != null && baseItems != null) {
        _baseParsedData = _baseParsedData!.copyWith(lineItems: baseItems);
      }
      entry.markSupplierResolution(resolution, resolvedProducts);
    });
    if (kDebugMode) {
      debugPrint('[OCR-SUPPLIER-RESOLUTION] ${jsonEncode(<String, Object?>{
            'reviewId': entry.reviewId,
            'sourceRowIndex': entry.sourceRowIndex,
            'listingId': resolution.listingId,
            'variantKey': resolution.variantKey?.value,
            'revisionId': resolution.revisionId,
            'kind': resolution.kind?.name,
            'products': [
              for (var index = 0; index < resolution.edges.length; index++)
                <String, Object?>{
                  'sku': resolvedProducts[index].sku,
                  'productId': resolution.edges[index].productId,
                  'units': resolution.edges[index].catalogUnitsPerPurchase,
                  'role': resolution.edges[index].componentRole,
                },
            ],
          })}');
    }
    return true;
  }

  Future<SupplierResolutionProposal?> _buildSupplierResolutionProposal(
    _NewProductEntry entry,
    ProductDuplicateSearchResult result, {
    required inv_service.InventoryService inventoryService,
    required List<inv_models.Product> products,
  }) async {
    final decision = result.adjudication;
    final optionEvidence = _supplierOptionEvidenceForLine(entry.originalItem);
    final sourceQuantity = entry.originalItem.sourcePurchaseQuantity ??
        entry.originalItem.quantity;
    if (decision == null ||
        optionEvidence == null ||
        sourceQuantity == null ||
        sourceQuantity <= 0) {
      return null;
    }
    final proposal = await SupplierResolutionProposalBuilder.build(
      decision: decision,
      investigation: entry.aiInvestigation,
      optionEvidence: optionEvidence,
      sourcePurchaseQuantity: sourceQuantity,
      catalog: products,
      lookupSetComposition: (setProduct) {
        final productId = setProduct.id;
        if (productId == null) return Future.value(null);
        return _productSetCompositionLoads.putIfAbsent(productId, () async {
          try {
            return await inventoryService.getProductSetComposition(productId);
          } on Object catch (error) {
            if (kDebugMode) {
              debugPrint(
                '[OCR-SET-COMPOSITION] No se pudo leer $productId: $error',
              );
            }
            return null;
          }
        });
      },
    );
    if (kDebugMode) {
      final trace = <String, Object?>{
        'reviewId': entry.reviewId,
        'accepted': proposal != null,
        'decision': decision.decision.name,
        'decisionConfidence': decision.confidence,
        'decisionComponents': [
          for (final component in decision.components)
            <String, Object?>{
              'productId': component.productId,
              'quantity': component.quantity,
              'role': component.role.name,
            },
        ],
        'sourcePurchaseQuantity': sourceQuantity,
        'optionPackCount': optionEvidence.packCount,
        'optionUnitClass': optionEvidence.unitClass,
        'investigationPackageKind': entry.aiInvestigation?.packageKind.name,
        'investigationComponents': [
          for (final component
              in entry.aiInvestigation?.composition.components ??
                  const <AIProductCompositionComponent>[])
            <String, Object?>{
              'label': component.label,
              'quantity': component.quantity,
              'role': component.role.name,
            },
        ],
        'kind': proposal?.kind.name,
        'usesCanonicalSet': proposal?.usesCanonicalSet,
        'canonicalSetSku': proposal?.canonicalSetProduct?.sku,
        'items': [
          for (final item
              in proposal?.items ?? const <SupplierResolutionProposalItem>[])
            <String, Object?>{
              'sku': item.product.sku,
              'productId': item.product.id,
              'unitsPerPurchase': item.catalogUnitsPerPurchase,
              'role': item.role.wireValue,
            },
        ],
        'edges': proposal?.edges
                .map((edge) => edge.toRpcJson())
                .toList(growable: false) ??
            const <Object?>[],
      };
      debugPrint(
        proposal == null
            ? '[OCR-RESOLUTION-PROPOSAL-REJECTED] ${jsonEncode(trace)}'
            : '[OCR-RESOLUTION-PROPOSAL] ${jsonEncode(trace)}',
      );
    }
    return proposal;
  }

  Future<void> _confirmSupplierResolutionProposal(
    _NewProductEntry entry,
  ) async {
    final proposal = entry.supplierResolutionProposal;
    if (_readOnlyEvaluationBlocksMutations ||
        proposal == null ||
        _bulkRowBusy(entry)) {
      return;
    }
    final inventoryService = context.read<inv_service.InventoryService>();
    final revision = entry.resolutionRevision;
    final reviewGeneration = _bulkReviewGeneration;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar ingreso al inventario'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(proposal.displaySummary),
            const SizedBox(height: 12),
            Text(
              proposal.usesCanonicalSet
                  ? 'Se usará el producto-set existente. Sus componentes '
                      'recibirán stock con la composición ya definida en inventario.'
                  : 'Cada componente recibirá su cantidad. El total de la línea '
                      'se repartirá entre ellos sin duplicar el costo.',
            ),
            const SizedBox(height: 8),
            const Text(
              'Esta regla quedará aprendida sólo para esta variante inmutable '
              'del proveedor.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('ocr-confirm-supplier-composition'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirmar descomposición'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !_ownsNewProductResolution(
          entry,
          revision,
          reviewGeneration: reviewGeneration,
        )) {
      return;
    }

    setState(() {
      entry.isLinkingExisting = true;
      entry.resolutionError = null;
    });
    try {
      final resolution = await _rememberSupplierResolutionProposal(
        entry,
        proposal,
      );
      if (!_ownsNewProductResolution(
        entry,
        revision,
        reviewGeneration: reviewGeneration,
      )) {
        return;
      }
      final products =
          _productReviewCatalogSnapshot ?? await inventoryService.getProducts();
      final applied = await _useSupplierVariantResolutionForEntry(
        entry,
        resolution,
        inventoryService: inventoryService,
        products: products,
        expectedRevision: revision,
        reviewGeneration: reviewGeneration,
      );
      if (!applied) {
        throw StateError(
          'La descomposición se confirmó, pero la fila cambió antes de aplicarla.',
        );
      }
    } on Object catch (error) {
      if (_ownsNewProductResolution(
        entry,
        revision,
        reviewGeneration: reviewGeneration,
      )) {
        setState(() {
          entry.isLinkingExisting = false;
          entry.resolutionError = error.toString();
          entry.resolutionState = OcrProductResolutionState.abstained;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo guardar la descomposición: $error'),
          ),
        );
      }
    }
  }

  Future<SupplierVariantResolution> _rememberSupplierResolutionProposal(
    _NewProductEntry entry,
    SupplierResolutionProposal proposal,
  ) async {
    final supplierId = (_supplierIdForNewProducts ?? widget.supplierId)?.trim();
    final itemId = _aliExpressItemIdForLine(entry.originalItem);
    final evidence = _supplierOptionEvidenceForLine(entry.originalItem);
    final invoice = _parsedData;
    final sourceDate = invoice?.date;
    final currencyCode = invoice?.currencyCode?.trim().toUpperCase();
    final sourceQuantity = entry.originalItem.sourcePurchaseQuantity ??
        entry.originalItem.quantity;
    final sourceTotal = entry.originalItem.total ??
        ((entry.originalItem.unitPrice ?? 0) * (sourceQuantity ?? 0));
    if (supplierId == null ||
        supplierId.isEmpty ||
        itemId == null ||
        itemId.isEmpty ||
        evidence == null ||
        sourceDate == null ||
        currencyCode != 'CLP' ||
        sourceQuantity == null ||
        sourceQuantity <= 0 ||
        sourceTotal < 0 ||
        entry.originalItem.sourceOrderNumbers.isEmpty) {
      throw StateError(
        'La línea no conserva toda la evidencia necesaria para aprender la descomposición.',
      );
    }
    final sourceLineKey = SupplierVariantResolutionService.buildSourceLineKey(
      supplierId: supplierId,
      sourceDate: sourceDate,
      sourceOrderNumbers: entry.originalItem.sourceOrderNumbers,
      listingId: itemId,
      variantKey: evidence.variantKey,
      commercialSplitKey: entry.originalItem.sourcePurchaseUnitPrice == null
          ? null
          : 'source-price:${entry.originalItem.sourcePurchaseUnitPrice}',
    );
    final decision = entry.duplicateResult?.adjudication;
    final operationId =
        entry.supplierResolutionOperationId ??= const Uuid().v4();
    final resolution = await SupplierVariantResolutionService(
      database: context.read<DatabaseService>(),
    ).remember(
      operationId: operationId,
      supplierId: supplierId,
      itemId: itemId,
      productUrl: entry.originalItem.productUrl?.trim() ?? '',
      optionEvidence: evidence,
      action: SupplierVariantResolutionAction.activate,
      kind: proposal.kind,
      edges: proposal.edges,
      decisionSource: SupplierVariantResolutionDecisionSource.operatorConfirmed,
      decisionEvidence: <String, dynamic>{
        'source_line_key': sourceLineKey,
        'source_document_date': sourceDate.toIso8601String().substring(0, 10),
        'supplier_order_numbers': entry.originalItem.sourceOrderNumbers,
        'source_purchase_quantity': sourceQuantity,
        'persisted_quantity': proposal.persistedQuantity,
        'source_total_minor': sourceTotal.round(),
        'persisted_total_minor': sourceTotal.round(),
        'currency_code': currencyCode,
        'confirmation_surface': 'purchase_invoice_ocr_composition_review',
        'resolution_kind': proposal.kind.name,
        'listing_id': itemId,
        'variant_key': evidence.variantKey.value,
        'source_title': entry.supplierIdentityTitle,
        'model_version': decision?.modelId ?? 'operator-confirmed',
        'match_prompt_version': decision?.promptVersion,
        'match_confidence': decision?.confidence,
        'uses_catalog_set': proposal.usesCanonicalSet,
        if (proposal.canonicalSetProduct?.id != null)
          'canonical_set_product_id': proposal.canonicalSetProduct!.id,
        'components': <Map<String, Object?>>[
          for (final item in proposal.items)
            <String, Object?>{
              'product_id': item.product.id,
              'sku': item.product.sku,
              'units_per_purchase': item.catalogUnitsPerPurchase,
              'role': item.role.wireValue,
            },
        ],
        if (_aliExpressVariantLabelForLine(entry.originalItem) != null)
          'selected_option': _aliExpressVariantLabelForLine(entry.originalItem),
      },
    );
    if (kDebugMode) {
      debugPrint(
        '[OCR-RESOLUTION-CONFIRMED] ${jsonEncode(<String, Object?>{
              'reviewId': entry.reviewId,
              'operationId': operationId,
              'revisionId': resolution.revisionId,
              'kind': resolution.kind?.name,
              'edgeCount': resolution.edges.length,
              'sourceQuantity': sourceQuantity,
              'persistedQuantity': proposal.persistedQuantity,
              'sourceTotalMinor': sourceTotal.round(),
            })}',
      );
    }
    return resolution;
  }

  Future<SupplierVariantResolution?> _rememberAliExpressResolution(
    _NewProductEntry entry, {
    required String productId,
  }) async {
    if (_readOnlyEvaluationBlocksMutations) return null;
    final supplierId = (_supplierIdForNewProducts ?? widget.supplierId)?.trim();
    if (supplierId == null || supplierId.isEmpty) {
      throw StateError('Falta resolver el proveedor AliExpress.');
    }

    final itemId = _aliExpressItemIdForLine(entry.originalItem);
    final evidence = _supplierOptionEvidenceForLine(entry.originalItem);
    final productUrl = entry.originalItem.productUrl?.trim();
    // Order-message URLs are not product identities. Persist only when a real
    // AliExpress item ID was extracted from the item URL/markers; otherwise
    // the current manual link still applies without pretending it was learned.
    if (itemId == null || itemId.isEmpty || evidence == null) {
      return null;
    }

    // A product click proves which catalog row the source means. It does not
    // prove whether `2PCS` means two inventory units or one catalog pack. Pack
    // and composite authority therefore needs the dedicated resolution UI or
    // a previously confirmed graph; never collapse it into a single alias.
    if (evidence.requiresExplicitComposition) {
      return null;
    }
    final invoice = _parsedData;
    final sourceDate = invoice?.date;
    final currencyCode = invoice?.currencyCode?.trim().toUpperCase();
    final sourceQuantity = entry.originalItem.sourcePurchaseQuantity ??
        entry.originalItem.quantity;
    final sourceTotal = entry.originalItem.total ??
        ((entry.originalItem.unitPrice ?? 0) * (sourceQuantity ?? 0));
    if (sourceDate == null ||
        currencyCode == null ||
        currencyCode != 'CLP' ||
        sourceQuantity == null ||
        sourceQuantity <= 0 ||
        sourceTotal < 0 ||
        entry.originalItem.sourceOrderNumbers.isEmpty) {
      return null;
    }
    final sourceLineKey = SupplierVariantResolutionService.buildSourceLineKey(
      supplierId: supplierId,
      sourceDate: sourceDate,
      sourceOrderNumbers: entry.originalItem.sourceOrderNumbers,
      listingId: itemId,
      variantKey: evidence.variantKey,
      commercialSplitKey: entry.originalItem.sourcePurchaseUnitPrice == null
          ? null
          : 'source-price:${entry.originalItem.sourcePurchaseUnitPrice}',
    );
    final operationId =
        entry.supplierResolutionOperationId ??= const Uuid().v4();
    return SupplierVariantResolutionService(
      database: context.read<DatabaseService>(),
    ).remember(
      operationId: operationId,
      supplierId: supplierId,
      itemId: itemId,
      productUrl: productUrl ?? '',
      optionEvidence: evidence,
      action: SupplierVariantResolutionAction.activate,
      kind: SupplierVariantResolutionKind.single,
      edges: <SupplierVariantResolutionEdge>[
        SupplierVariantResolutionEdge(
          position: 1,
          productId: productId,
          catalogUnitsPerPurchase: 1,
          allocationRatio: 1,
          componentRole: 'catalog_product',
        ),
      ],
      decisionSource: SupplierVariantResolutionDecisionSource.operatorConfirmed,
      decisionEvidence: <String, dynamic>{
        'source_line_key': sourceLineKey,
        'source_document_date': sourceDate.toIso8601String().substring(0, 10),
        'supplier_order_numbers': entry.originalItem.sourceOrderNumbers,
        'source_purchase_quantity': sourceQuantity,
        'persisted_quantity': sourceQuantity,
        'source_total_minor': sourceTotal.round(),
        'persisted_total_minor': sourceTotal.round(),
        'currency_code': currencyCode,
        'confirmation_surface': 'purchase_invoice_ocr_product_review',
        'product_id': productId,
        'listing_id': itemId,
        'variant_key': evidence.variantKey.value,
        'source_title': entry.supplierIdentityTitle,
        if (_aliExpressVariantLabelForLine(entry.originalItem) != null)
          'selected_option': _aliExpressVariantLabelForLine(entry.originalItem),
      },
    );
  }

  Future<void> _uploadSelectedEntryImageForCreation(
    _NewProductEntry entry,
  ) async {
    final bytes = entry.imageBytes;
    if (entry.imageUrl?.trim().isNotEmpty == true || bytes == null) return;
    final fileName = entry.imageFileName?.trim().isNotEmpty == true
        ? entry.imageFileName!.trim()
        : 'ocr-product.jpg';
    entry.isUploadingImage = true;
    if (mounted) setState(() {});
    try {
      final uploaded = await ImageService.uploadProductImageWithOptimization(
        bytes: bytes,
        fileName: fileName,
      );
      entry.imageUrl = uploaded.originalUrl;
      entry.imageUrlOptimized = uploaded.optimizedUrl;
    } finally {
      entry.isUploadingImage = false;
      if (mounted) setState(() {});
    }
  }

  /// Create products from the bulk creation form
  Future<void> _createBulkProducts() async {
    if (_readOnlyEvaluationBlocksMutations) return;
    final selectedEntries = _newProductEntries
        .where((entry) =>
            entry.isSelected &&
            entry.linkedProduct == null &&
            !entry.hasSupplierResolution)
        .toList();
    if (!_canCreateBulkProducts() || selectedEntries.isEmpty) return;

    setState(() => _creatingProducts = true);

    try {
      final dbService = DatabaseService();
      final tenantService = TenantService();
      final inventoryService =
          inv_service.InventoryService(dbService, tenantService);
      final sharedInventoryService = context.read<InventoryService>();
      final createdProducts = <_NewProductEntry, inv_models.Product>{};
      final learnedResolutions =
          <_NewProductEntry, SupplierVariantResolution>{};
      var failed = 0;
      var aliasWarnings = 0;

      if (_looksLikeAliExpressInvoice(_parsedData!)) {
        // Every row already owns its reserved code from the moment its «Nuevo»
        // decision was taken. Anything still missing one is a row whose
        // reservation failed; asking again here is the retry, not a new batch.
        for (final entry in selectedEntries) {
          if (!entry.hasReservedAliExpressSku) {
            await _ensureReservedSkuForEntry(entry);
          }
        }
      }
      if (selectedEntries.any((entry) => !entry.isValid)) {
        throw StateError(
          'La reserva de SKU no dejó todas las fichas listas para crear.',
        );
      }

      for (final entry in selectedEntries) {
        entry.creationError = null;
        await _ensureEntryImageBytes(entry);
        try {
          await _uploadSelectedEntryImageForCreation(entry);
        } catch (error) {
          failed++;
          entry.creationError = 'No se pudo guardar la imagen: $error';
          continue;
        }
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
          createdProducts[entry] =
              await inventoryService.createProduct(product);
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
            // A commit recovered from a lost acknowledgement is a commit. It
            // joins the same map every ordinary create joins, so it goes
            // through the same alias persistence and the same line
            // reconciliation instead of a shortcut that skipped both.
            createdProducts[entry] = committedProduct;
            debugPrint(
                '✅ Product commit confirmed by SKU read-back: ${entry.sku}');
          } else {
            failed++;
            if (committedProduct != null && entry.requiresDuplicateReview) {
              // Another creator claimed a reserved-but-not-yet-used SKU. Never
              // interpret that row as this operation's commit: drop this row's
              // grant so its retry asks for a genuinely new number.
              final next = _skuReservationAuthorityOrCreate()
                  .invalidate(_reservationIdentityFor(entry));
              entry.reservedSku = null;
              entry.skuOperationKey = null;
              entry.skuReservationGeneration = next.generation;
              entry.syncSkuField();
              entry.creationError = 'El SKU ${product.sku} fue ocupado por '
                  'otro producto. Reintenta para reservar uno nuevo.';
            } else {
              entry.creationError = e.toString();
            }
            debugPrint('❌ Failed to create product ${product.sku}: $e');
          }
        }
      }

      // One funnel for everything that committed, however it committed.
      //
      // The alias is what makes the *next* invoice cheap: without it every
      // re-import pays the full matcher again. A row is therefore not removed
      // from the review until both halves of its aftermath succeed — the alias
      // is stored (or there is genuinely nothing to store) and its invoice line
      // is reconciled. A row that committed but could not finish stays visible,
      // marked as linked to the product it created, so a second Create can
      // never duplicate it.
      final unreconciled = <_NewProductEntry>{};
      for (final created in createdProducts.entries) {
        final entry = created.key;
        final savedProduct = created.value;
        final productId = savedProduct.id;
        if (productId == null) {
          unreconciled.add(entry);
          entry.creationError =
              'El producto se creó pero la base no devolvió su identificador.';
          continue;
        }
        try {
          final learned = await _rememberAliExpressResolution(
            entry,
            productId: productId,
          );
          if (learned != null) learnedResolutions[entry] = learned;
        } catch (error) {
          aliasWarnings++;
          unreconciled.add(entry);
          entry.creationError =
              'Producto creado. Falta guardar la publicación del proveedor '
              'para el próximo ingreso. ($error)';
          debugPrint(
              'Product was created but its supplier alias was not stored: $error');
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
                supplierResolution: learnedResolutions[createdEntry],
              );
              parsedItems[rowIndex] = resolvedItem;
              if (baseItems != null && rowIndex < baseItems.length) {
                baseItems[rowIndex] = resolvedItem;
              }
              _skuControllers[rowIndex]?.text = savedProduct.sku;
            } else {
              // The line this product belongs to is no longer in the invoice.
              // Removing the row here would hide a committed product that
              // nothing points at.
              unreconciled.add(createdEntry);
            }
            if (unreconciled.contains(createdEntry)) {
              createdEntry.markLinkedProduct(savedProduct);
              createdEntry.syncSkuField();
              continue;
            }
            _newProductEntries.remove(createdEntry);
            createdEntry.dispose();
          }
          _parsedData = _parsedData!.copyWith(lineItems: parsedItems);
          if (_baseParsedData != null && baseItems != null) {
            _baseParsedData = _baseParsedData!.copyWith(lineItems: baseItems);
          }
          _showBulkCreate = _newProductEntries.any(
            (entry) =>
                entry.isSelected &&
                entry.linkedProduct == null &&
                !entry.hasSupplierResolution,
          );
          if (!_showBulkCreate) {
            _removeOmittedLinesFromInvoice();
          }
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
                  ? VinabikeThemeRoles.of(context).success.accent
                  : VinabikeThemeRoles.of(context).warning.accent,
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

    final cached = _ocrProductImageBytesCache[imageUrl];
    if (cached != null) {
      entry.imageBytes = cached;
      entry.imageFileName ??= _NewProductEntry._imageFileNameFromUrl(imageUrl);
      return;
    }

    final load = _ocrProductImageLoads.putIfAbsent(
      imageUrl,
      () async {
        final uri = Uri.tryParse(imageUrl);
        if (uri == null || !uri.hasScheme) return null;
        final response =
            await http.get(uri).timeout(const Duration(seconds: 8));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          return null;
        }
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.isNotEmpty && !contentType.startsWith('image/')) {
          return null;
        }
        if (response.bodyBytes.isEmpty ||
            response.bodyBytes.length > 8 * 1024 * 1024) {
          return null;
        }
        return response.bodyBytes;
      },
    );
    try {
      final bytes = await load;
      if (bytes == null) return;
      if (_ocrProductImageBytesCache.length >= 32) {
        _ocrProductImageBytesCache.remove(
          _ocrProductImageBytesCache.keys.first,
        );
      }
      _ocrProductImageBytesCache[imageUrl] = bytes;
      if (entry.imageUrl?.trim() != imageUrl || entry.imageBytes != null) {
        return;
      }
      entry.imageBytes = bytes;
      entry.imageFileName ??= _NewProductEntry._imageFileNameFromUrl(imageUrl);
    } catch (e) {
      debugPrint('Could not download OCR row image for fingerprint: $e');
    } finally {
      if (identical(_ocrProductImageLoads[imageUrl], load)) {
        _ocrProductImageLoads.remove(imageUrl);
      }
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
      netAmount: invoice.netAmount,
      taxAmount: invoice.taxAmount,
      currencyCode: invoice.currencyCode,
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
      final updatedSupplier = await purchaseService.updateSupplierOcrTemplate(
        supplier: _ocrSupplier!,
        template: template,
      );

      if (!mounted) return;

      setState(() {
        _discardProductReviewDraft(advanceDocumentEpoch: true);
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
          backgroundColor: VinabikeThemeRoles.of(context).success.accent,
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

  bool _isParsedLineResolved(ParsedLineItem item) =>
      item.matchedProductId?.trim().isNotEmpty == true ||
      item.hasAuthoritativeCatalogResolution;

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
    if (_readOnlyEvaluationBlocksMutations) return;
    if (widget.showLineItemReview) {
      if (_ocrSupplier == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Selecciona un proveedor antes de aplicar la factura.'),
            ),
          );
        }
        return;
      }
      final unresolved =
          data.lineItems.where((item) => !_isParsedLineResolved(item)).length;
      if (data.lineItems.isEmpty || unresolved > 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data.lineItems.isEmpty
                  ? 'La factura no tiene productos detectados para aplicar.'
                  : 'Resuelve los $unresolved producto${unresolved == 1 ? '' : 's'} antes de usar la factura.'),
              backgroundColor: VinabikeThemeRoles.of(context).warning.accent,
            ),
          );
        }
        return;
      }
    }
    final diagnostics = _getInvoiceDiagnostics(data);
    if (!diagnostics.shouldWarnBeforeApply) {
      await _completeParsedData(data);
      return;
    }

    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: VinabikeThemeRoles.of(context).warning.accent,
            ),
            const SizedBox(width: 8),
            const Text('Revisar Totales OCR'),
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
      await _completeParsedData(data);
    }
  }

  Future<void> _completeParsedData(ParsedInvoice data) async {
    if (_isApplyingResult) return;
    if (mounted) setState(() => _isApplyingResult = true);
    try {
      await widget.onComplete(data);
    } catch (error) {
      final message = 'No se pudo aplicar la factura: $error';
      widget.onError?.call(message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _isApplyingResult = false);
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
        _adoptParsedInvoiceDocument(
          base: prepared.base,
          display: parsedData,
          supplier: prepared.supplier,
        );
        _lastReadSource =
            _useVeryfi ? _OcrReadSource.veryfi : _OcrReadSource.local;
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
    _isReadOnlyEvaluation = structuredInvoiceData?['evaluationOnly'] == true;
    ParsedInvoice? parsedData;
    ParsedInvoice? directPdfParsedData;
    var readSource = structuredInvoiceData == null
        ? _OcrReadSource.local
        : _OcrReadSource.structured;
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
        readSource = _OcrReadSource.veryfi;
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
      readSource = _OcrReadSource.structured;
      parsedData = _parseAliExpressJsonFile(fileBytes);
    } else if (normalizedExtension == 'html' || normalizedExtension == 'htm') {
      readSource = _OcrReadSource.structured;
      parsedData = _parseAliExpressHtmlFile(fileBytes);
    } else if (directPdfParsedData != null &&
        directPdfParsedData.lineItems.isNotEmpty &&
        _looksLikeAliExpressInvoice(directPdfParsedData, fileName: fileName)) {
      parsedData = directPdfParsedData;
    } else if (_useVeryfi) {
      // Use Veryfi for PDFs and other supported document files.
      readSource = _OcrReadSource.veryfi;
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
    final displayData = prepared.display;

    if (!mounted) return;
    setState(() {
      _adoptParsedInvoiceDocument(
        base: prepared.base,
        display: displayData,
        supplier: prepared.supplier,
      );
      _lastReadSource = readSource;
      _isProcessing = false;
    });
    if (!widget.showPreview) {
      await _handleUseParsedData(displayData);
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
      final variantLabel = item['variant']?.toString().trim();
      final variantKey = item['variantKey']?.toString().trim();
      final sourcePurchaseQuantity = parseNumber(
        item['sourcePurchaseQuantity'] ?? item['quantity'],
      );
      final sourcePurchaseUnitPrice = parseNumber(
        item['sourcePurchaseUnitPrice'],
      );
      final rawPackCountValue = parseNumber(item['rawPackCount']);
      final rawPackCount = rawPackCountValue != null &&
              rawPackCountValue > 0 &&
              rawPackCountValue == rawPackCountValue.roundToDouble()
          ? rawPackCountValue.toInt()
          : null;
      final rawUnitToken = item['rawUnitToken']?.toString().trim();
      final rawPackEvidenceConflict = item['rawPackEvidenceConflict'] == true;
      final sourceOrderNumbers = (item['sourceOrderNumbers'] is Iterable
              ? item['sourceOrderNumbers'] as Iterable
              : const <dynamic>[])
          .map((value) => value?.toString().trim() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      final explicitLineTitle = _firstNonEmpty(
        item['lineTitle']?.toString(),
        item['originalDescription']?.toString(),
      );
      final lineTitle = explicitLineTitle ??
          _withoutAliExpressSelectedVariant(description, variantLabel);
      return ParsedLineItem(
        description: description == null || description.isEmpty
            ? 'AliExpress item'
            : description,
        lineTitle: lineTitle,
        variantLabel:
            variantLabel == null || variantLabel.isEmpty ? null : variantLabel,
        variantKey:
            variantKey == null || variantKey.isEmpty ? null : variantKey,
        sku: item['sku']?.toString().trim(),
        rawRowText: [
          item['description'],
          lineTitle == null ? null : 'ORIGINAL_TITLE: $lineTitle',
          (variantLabel?.isNotEmpty ?? false) ? 'VARIANT: $variantLabel' : null,
          (variantKey?.isNotEmpty ?? false) ? 'VARIANT_KEY: $variantKey' : null,
          sourcePurchaseQuantity == null
              ? null
              : 'SOURCE_PURCHASE_QUANTITY: $sourcePurchaseQuantity',
          sourcePurchaseUnitPrice == null
              ? null
              : 'SOURCE_PURCHASE_UNIT_PRICE: $sourcePurchaseUnitPrice',
          rawPackCount == null ? null : 'RAW_PACK_COUNT: $rawPackCount',
          (rawUnitToken?.isNotEmpty ?? false)
              ? 'RAW_UNIT_TOKEN: $rawUnitToken'
              : null,
          rawPackEvidenceConflict ? 'RAW_PACK_EVIDENCE_CONFLICT: true' : null,
          sourceOrderNumbers.isEmpty
              ? null
              : 'SOURCE_ORDERS: ${sourceOrderNumbers.join(',')}',
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
        sourcePurchaseQuantity: sourcePurchaseQuantity,
        sourcePurchaseUnitPrice: sourcePurchaseUnitPrice,
        rawPackCount: rawPackCount,
        rawUnitToken:
            rawUnitToken == null || rawUnitToken.isEmpty ? null : rawUnitToken,
        rawPackEvidenceConflict: rawPackEvidenceConflict,
        sourceOrderNumbers: sourceOrderNumbers,
        quantity: sourcePurchaseQuantity ?? parseNumber(item['quantity']),
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
    final currencyCode = invoice['currency']?.toString().trim().toUpperCase();
    return ParsedInvoice(
      invoiceNumber: invoice['orderNumber']?.toString().trim(),
      date: parseDate(invoice['orderDate']),
      total: parseNumber(invoice['total']),
      currencyCode:
          currencyCode == null || currencyCode.isEmpty ? null : currencyCode,
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
        RegExp(r'ORIGINAL_TITLE:\s*([^\n<]+)', caseSensitive: false),
      );
      final lineTitle = _firstTextIn(
            row,
            RegExp(r'LINE_TITLE:\s*([^\n<]+)', caseSensitive: false),
          ) ??
          originalDescription;
      final variantLabel = _firstTextIn(
        row,
        RegExp(r'VARIANT:\s*([^\n<]+)', caseSensitive: false),
      );
      final variantKey = _firstTextIn(
        row,
        RegExp(r'VARIANT_KEY:\s*([^\n<]+)', caseSensitive: false),
      );
      final sourcePurchaseQuantity = parseMoney(
        _firstTextIn(
          row,
          RegExp(
            r'SOURCE_PURCHASE_QUANTITY:\s*([^\n<]+)',
            caseSensitive: false,
          ),
        ),
      );
      final sourcePurchaseUnitPrice = parseMoney(
        _firstTextIn(
          row,
          RegExp(
            r'SOURCE_PURCHASE_UNIT_PRICE:\s*([^\n<]+)',
            caseSensitive: false,
          ),
        ),
      );
      final rawPackCountValue = parseMoney(
        _firstTextIn(
          row,
          RegExp(r'RAW_PACK_COUNT:\s*([^\n<]+)', caseSensitive: false),
        ),
      );
      final rawPackCount = rawPackCountValue != null &&
              rawPackCountValue > 0 &&
              rawPackCountValue == rawPackCountValue.roundToDouble()
          ? rawPackCountValue.toInt()
          : null;
      final rawUnitToken = _firstTextIn(
        row,
        RegExp(r'RAW_UNIT_TOKEN:\s*([^\n<]+)', caseSensitive: false),
      );
      final rawPackEvidenceConflict = RegExp(
        r'RAW_PACK_EVIDENCE_CONFLICT:\s*true',
        caseSensitive: false,
      ).hasMatch(row);
      final sourceOrderNumbers = (_firstTextIn(
                row,
                RegExp(r'SOURCE_ORDERS:\s*([^\n<]+)', caseSensitive: false),
              ) ??
              '')
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
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
        lineTitle: lineTitle ??
            _withoutAliExpressSelectedVariant(description, variantLabel),
        variantLabel: variantLabel,
        variantKey: variantKey,
        sku: sku,
        rawRowText: [
          description,
          lineTitle == null ? null : 'ORIGINAL_TITLE: $lineTitle',
          variantLabel == null ? null : 'VARIANT: $variantLabel',
          variantKey == null ? null : 'VARIANT_KEY: $variantKey',
          sourcePurchaseQuantity == null
              ? null
              : 'SOURCE_PURCHASE_QUANTITY: $sourcePurchaseQuantity',
          sourcePurchaseUnitPrice == null
              ? null
              : 'SOURCE_PURCHASE_UNIT_PRICE: $sourcePurchaseUnitPrice',
          rawPackCount == null ? null : 'RAW_PACK_COUNT: $rawPackCount',
          rawUnitToken == null ? null : 'RAW_UNIT_TOKEN: $rawUnitToken',
          rawPackEvidenceConflict ? 'RAW_PACK_EVIDENCE_CONFLICT: true' : null,
          sourceOrderNumbers.isEmpty
              ? null
              : 'SOURCE_ORDERS: ${sourceOrderNumbers.join(',')}',
          productUrl,
          imageUrl == null ? null : 'IMAGE_URL: $imageUrl',
        ].whereType<Object>().join('\n'),
        imageUrl: imageUrl == null ? null : _decodeHtmlEntities(imageUrl),
        productUrl: productUrl == null ? null : _decodeHtmlEntities(productUrl),
        sourcePurchaseQuantity: sourcePurchaseQuantity,
        sourcePurchaseUnitPrice: sourcePurchaseUnitPrice,
        rawPackCount: rawPackCount,
        rawUnitToken: rawUnitToken,
        rawPackEvidenceConflict: rawPackEvidenceConflict,
        sourceOrderNumbers: sourceOrderNumbers,
        quantity: sourcePurchaseQuantity ??
            (cells.isNotEmpty ? parseMoney(cells[0]) : null),
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
      currencyCode: 'CLP',
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
      final lineTitle = _firstNonEmpty(item.lineTitle, source.lineTitle);
      final variantLabel =
          _firstNonEmpty(item.variantLabel, source.variantLabel);
      final variantKey = _firstNonEmpty(item.variantKey, source.variantKey);
      final sourcePurchaseQuantity =
          item.sourcePurchaseQuantity ?? source.sourcePurchaseQuantity;
      final sourcePurchaseUnitPrice =
          item.sourcePurchaseUnitPrice ?? source.sourcePurchaseUnitPrice;
      final rawPackCount = item.rawPackCount ?? source.rawPackCount;
      final rawUnitToken = _firstNonEmpty(
        item.rawUnitToken,
        source.rawUnitToken,
      );
      final rawPackEvidenceConflict = item.rawPackEvidenceConflict ||
          source.rawPackEvidenceConflict ||
          (item.rawPackCount != null &&
              source.rawPackCount != null &&
              item.rawPackCount != source.rawPackCount) ||
          (item.rawUnitToken?.trim().isNotEmpty == true &&
              source.rawUnitToken?.trim().isNotEmpty == true &&
              item.rawUnitToken!.trim().toLowerCase() !=
                  source.rawUnitToken!.trim().toLowerCase());
      final sourceOrderNumbers = <String>{
        ...item.sourceOrderNumbers,
        ...source.sourceOrderNumbers,
      }.toList()
        ..sort();
      final rawRowText = _mergeRawRowText(item.rawRowText, source.rawRowText);
      final itemChanged = imageUrl != item.imageUrl ||
          productUrl != item.productUrl ||
          lineTitle != item.lineTitle ||
          variantLabel != item.variantLabel ||
          variantKey != item.variantKey ||
          sourcePurchaseQuantity != item.sourcePurchaseQuantity ||
          sourcePurchaseUnitPrice != item.sourcePurchaseUnitPrice ||
          rawPackCount != item.rawPackCount ||
          rawUnitToken != item.rawUnitToken ||
          rawPackEvidenceConflict != item.rawPackEvidenceConflict ||
          !listEquals(sourceOrderNumbers, item.sourceOrderNumbers) ||
          rawRowText != item.rawRowText;

      updatedItems.add(itemChanged
          ? item.copyWith(
              imageUrl: imageUrl,
              productUrl: productUrl,
              lineTitle: lineTitle,
              variantLabel: variantLabel,
              variantKey: variantKey,
              sourcePurchaseQuantity: sourcePurchaseQuantity,
              sourcePurchaseUnitPrice: sourcePurchaseUnitPrice,
              rawPackCount: rawPackCount,
              rawUnitToken: rawUnitToken,
              rawPackEvidenceConflict: rawPackEvidenceConflict,
              sourceOrderNumbers: sourceOrderNumbers,
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

  String? _withoutAliExpressSelectedVariant(
    String? description,
    String? variantLabel,
  ) {
    final value = description?.trim();
    final variant = variantLabel?.trim();
    if (value == null || value.isEmpty || variant == null || variant.isEmpty) {
      return null;
    }
    final suffix = RegExp(
      '\\s*\\(${RegExp.escape(variant)}\\)\\s*\$',
      caseSensitive: false,
    );
    final withoutVariant = value.replaceFirst(suffix, '').trim();
    return withoutVariant.isEmpty ? null : withoutVariant;
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
    final response =
        await veryfi.parseInvoiceFromBytes(bytes, filename).timeout(
              const Duration(seconds: 60),
              onTimeout: () => throw TimeoutException(
                'El lector de facturas no respondió en 60 segundos. Intenta nuevamente.',
              ),
            );
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

    final sourceItems = invoice.lineItems;
    final isAliExpress = _looksLikeAliExpressInvoice(invoice);
    final allowNameFallback = !isAliExpress;
    final verifiedItems = List<ParsedLineItem?>.filled(
      sourceItems.length,
      null,
    );
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= sourceItems.length) return;
        final item = sourceItems[index];
        try {
          verifiedItems[index] = await _verifySingleProduct(
            item,
            supplierId: supplierId,
            allowNameFallback: allowNameFallback,
            // AliExpress `sku` is a supplier option code, never an internal
            // catalog SKU. Its immutable graph must be checked in review first.
            allowCatalogCodeLookup: !isAliExpress,
          ).timeout(
            const Duration(seconds: 12),
            onTimeout: () {
              debugPrint(
                'Catalog verification timed out for OCR row ${index + 1}; leaving it for product review.',
              );
              return _clearProductResolution(item);
            },
          );
        } catch (error) {
          debugPrint(
            'Catalog verification failed for OCR row ${index + 1}: $error',
          );
          verifiedItems[index] = _clearProductResolution(item);
        }
      }
    }

    final workerCount = math.min(4, sourceItems.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));
    final completedItems = verifiedItems.cast<ParsedLineItem>();

    debugPrint(
        '🔍 Verification complete: ${completedItems.where((i) => i.existsInDatabase == true).length}/${completedItems.length} found');

    return ParsedInvoice(
      rut: invoice.rut,
      invoiceNumber: invoice.invoiceNumber,
      date: invoice.date,
      total: invoice.total,
      netAmount: invoice.netAmount,
      taxAmount: invoice.taxAmount,
      currencyCode: invoice.currencyCode,
      supplierName: invoice.supplierName,
      lineItems: completedItems,
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
    for (final timer in _identityRecomputeTimers.values) {
      timer.cancel();
    }
    _identityRecomputeTimers.clear();
    for (final entry in _newProductEntries) {
      entry.dispose();
    }
    _newProductEntries.clear();
    _ocrProductImageBytesCache.clear();
    _ocrProductImageLoads.clear();
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

/// One catalog line that a resolved supplier row will contribute to the
/// purchase draft.
///
/// The supplier row remains singular so its quantity and landed total are
/// audited once. This projection explains the inventory result that the
/// purchase form will materialize after the operator applies the invoice.
@visibleForTesting
final class OcrPreviewResolutionComponent {
  const OcrPreviewResolutionComponent({
    required this.product,
    required this.quantity,
    required this.roleLabel,
  });

  final inv_models.Product product;
  final double quantity;
  final String? roleLabel;

  String get displayLabel {
    final role = roleLabel == null ? '' : ' · $roleLabel';
    return '${_ocrPreviewQuantityLabel(quantity)} × ${product.sku}$role · '
        '${product.name}';
  }
}

/// Projects an authoritative supplier graph into what will enter inventory.
///
/// It returns no partial answer: if an edge lacks a catalog row, the preview
/// falls back to the unresolved display just as the apply path fails closed.
@visibleForTesting
List<OcrPreviewResolutionComponent> buildOcrPreviewResolutionComponents({
  required ParsedLineItem item,
  required Map<String, inv_models.Product> productsById,
}) {
  final resolution = item.supplierResolution;
  if (resolution?.isResolved != true || resolution!.edges.isEmpty) {
    return const [];
  }
  final sourceQuantity = item.sourcePurchaseQuantity ?? item.quantity;
  if (sourceQuantity == null ||
      !sourceQuantity.isFinite ||
      sourceQuantity <= 0) {
    return const [];
  }

  final components = <OcrPreviewResolutionComponent>[];
  for (final edge in resolution.edges) {
    final product = productsById[edge.productId];
    if (product == null) return const [];
    components.add(OcrPreviewResolutionComponent(
      product: product,
      quantity: sourceQuantity * edge.catalogUnitsPerPurchase,
      roleLabel: _ocrPreviewComponentRoleLabel(edge.componentRole),
    ));
  }
  return List<OcrPreviewResolutionComponent>.unmodifiable(components);
}

String? _ocrPreviewComponentRoleLabel(String rawRole) =>
    switch (rawRole.trim().toLowerCase()) {
      'front' => 'delantero',
      'rear' => 'trasero',
      'left' => 'izquierdo',
      'right' => 'derecho',
      'homogeneous' => 'unidades iguales',
      'catalog_set' => 'set canónico',
      _ => null,
    };

String _ocrPreviewQuantityLabel(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toString();

/// Entry for a new product to be created from OCR
/// Narrowest width at which the nine invoice columns actually fit.
///
/// It is arithmetic, not taste: the cells this table lays out are
/// `#` 28 + producto 320 + código 120 + cantidad 64 + costo 120 + descuento 96
/// + total 120 + producto ERP 200 + estado 66 = 1134, plus eight 16 px column
/// gaps and two 12 px horizontal margins = 1286. A previous floor of 1060 let
/// the table claim it fitted at 1108–1333 and then quietly cut `Total línea`
/// and `Estado` off the right edge with scrolling already disabled — the two
/// columns the operator opens this screen to read.
const double _previewTableFloor = 1286;

class _NewProductEntry {
  static int _nextReviewSequence = 0;

  late final String reviewId = 'ocr-product-${++_nextReviewSequence}';
  final ParsedLineItem originalItem;
  final int sourceRowIndex;
  final String supplierCode;
  final bool requiresDuplicateReview;
  bool isSelected;
  final TextEditingController nameController;
  final TextEditingController skuController;
  final TextEditingController costController;
  final TextEditingController priceController;
  Category? selectedCategory;
  ProductBrand? selectedBrand;
  bool categoryUserEdited = false;
  bool brandUserEdited = false;
  String? imageUrl;
  String? imageUrlOptimized;
  Uint8List? imageBytes;
  String? imageFileName;
  bool isUploadingImage = false;
  bool isHoveringImage = false;
  bool isWorkshopConsumable = false;
  bool priceUserEdited = false;
  bool isCheckingSimilar = false;
  bool isLinkingExisting = false;
  inv_models.Product? linkedProduct;

  /// This row's own database-owned `AE0xxx`, once granted.
  ///
  /// The reservation belongs to the row, not to a batch: it is what the worker
  /// writes on the box the moment they decide «Nuevo», it survives a detour
  /// through «Vinculado», and it is the only value creation is allowed to
  /// send. Free text in the SKU field can never become a product code.
  String? reservedSku;

  /// The idempotency key that produced [reservedSku]. Retrying the same row
  /// replays it; it is never reused by another row.
  String? skuOperationKey;

  /// Bumped only when a granted SKU turned out to be taken by someone else, so
  /// the next request is a new reservation rather than a replay of a lost one.
  int skuReservationGeneration = 0;

  /// Guards a late reservation answer. A row whose decision changed while the
  /// RPC was in flight must not be painted with the answer it no longer owns.
  int skuReservationTicket = 0;

  /// This row is asking the database for its next canonical `AE0xxx`.
  bool isReservingSku = false;

  /// Why the last reservation attempt for this row failed, if it did.
  Object? skuReservationError;

  bool get hasReservedAliExpressSku => (reservedSku ?? '').isNotEmpty;
  List<ProductDuplicateCandidate> similarCandidates = [];
  ProductDuplicateSearchResult? independentDuplicateResult;
  ProductDuplicateSearchResult? duplicateResult;
  SupplierResolutionProposal? supplierResolutionProposal;
  SupplierVariantResolution? supplierResolution;
  List<inv_models.Product> supplierResolutionProducts = const [];
  String? supplierResolutionOperationId;
  OcrProductResolutionState resolutionState;
  String? resolutionError;
  String? creationError;
  int resolutionRevision = 0;

  /// The primary identity receipt and its exact row revision. A failed
  /// attempt is cached too, so opening the picker or rebuilding the row cannot
  /// spend another model call for unchanged evidence.
  AIProductIdentityInvestigation? aiInvestigation;
  int? aiInvestigationRevision;
  String? aiInvestigationError;

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

  /// Raw component-family hint returned by AI. The canonical semantic
  /// resolver revalidates it against source evidence and catalog paths.
  String? aiSuggestedComponentType;

  /// What the cleaner's one call saw in the photo, independent of the title.
  ///
  /// It is kept on the row because three consumers need the same reading: the
  /// matcher's identity gate, the category resolver, and the review's
  /// «revisar» state. Re-asking the model for each of them is what made every
  /// row cost two vision calls.
  AIProductImageAnalysis? aiVisualAnalysis;

  /// AI-detected brand visible in the photo (e.g. "ZTTO", "Shimano"). Used
  /// to seed the duplicate-matcher probe.
  String? aiSuggestedBrandName;

  double? aiSuggestionConfidence;

  String? semanticFamily;
  double? semanticConfidence;
  String? semanticReviewReason;

  /// Why the object-first pipeline refused to place this row, when it did.
  String? categoryReviewReason;

  /// What justified the category it did choose, in the shop's own words.
  List<String> categoryEvidence = const <String>[];
  List<ProductCatalogSemanticEvidence> semanticEvidence = const [];

  /// Model/part number returned by the AI cleaner (for example RT56). Model
  /// identifiers are normalized by the duplicate matcher before comparison.
  String? aiSuggestedModel;

  /// Original noisy supplier title preserved as the description fallback so
  /// the long AliExpress text doesn't get lost when the name is cleaned.
  String? originalNoisyTitle;

  /// Supplier-authored title used as immutable identity evidence. The clean
  /// name is presentation; it must never rewrite what the invoice asserted.
  String get supplierIdentityTitle {
    final structured = originalItem.lineTitle?.trim();
    if (structured != null && structured.isNotEmpty) return structured;
    final preserved = originalNoisyTitle?.trim();
    if (preserved != null && preserved.isNotEmpty) return preserved;
    final parsed = originalItem.description.trim();
    if (parsed.isNotEmpty) return parsed;
    return nameController.text.trim();
  }

  /// True when the cost in [costController] already includes 19% IVA (e.g.
  /// AliExpress unit prices, where shipping/tax/discount have been allocated
  /// into each unit). Drives the suggested-price formula:
  ///   - tax-included cost: price = cost * 2 (IVA already inside the cost)
  ///   - tax-excluded cost: price = cost * 1.19 * 2 (Net + IVA, then x2)
  bool costIncludesIva;

  _NewProductEntry({
    required this.originalItem,
    required this.sourceRowIndex,
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
    originalNoisyTitle = originalItem.lineTitle?.trim().isNotEmpty == true
        ? originalItem.lineTitle!.trim()
        : originalItem.description.trim();
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
    aiInvestigation = null;
    aiInvestigationRevision = null;
    aiInvestigationError = null;
    aiVisualAnalysis = null;
    isAICleaningName = false;
    isCheckingSimilar = false;
    isLinkingExisting = false;
    similarCandidates = [];
    independentDuplicateResult = null;
    duplicateResult = null;
    supplierResolutionProposal = null;
    resolutionError = null;
    resolutionState = OcrProductResolutionState.unsearched;
  }

  /// Retries the model/matcher without pretending the operator edited the
  /// source identity. A valid primary receipt is reused; a failed/null primary
  /// receipt or one produced by an older contract is cleared so the first pass
  /// runs again. This keeps a transient adjudication formatting failure from
  /// paying for the source image twice without ever reusing stale semantics
  /// after a prompt/schema upgrade.
  void retryDuplicateResolution() {
    if (!requiresDuplicateReview) return;
    final investigation = aiInvestigation;
    final primaryReceiptIsCurrent = investigation != null &&
        investigation.schemaVersion ==
            AIAssistantService.productIdentitySchemaVersion &&
        investigation.promptVersion ==
            AIAssistantService.productIdentityPromptKey &&
        investigation.receipt.promptVersion ==
            AIAssistantService.productIdentityPromptKey;
    if (!primaryReceiptIsCurrent) {
      aiInvestigation = null;
      aiInvestigationRevision = null;
      aiInvestigationError = null;
      aiVisualAnalysis = null;
    }
    isAICleaningName = false;
    isCheckingSimilar = false;
    isLinkingExisting = false;
    similarCandidates = [];
    independentDuplicateResult = null;
    duplicateResult = null;
    supplierResolutionProposal = null;
    resolutionError = null;
    resolutionState = OcrProductResolutionState.unsearched;
  }

  void markSearching() {
    isCheckingSimilar = true;
    independentDuplicateResult = null;
    duplicateResult = null;
    supplierResolutionProposal = null;
    resolutionError = null;
    resolutionState = OcrProductResolutionState.searching;
  }

  bool ownsInvestigationForRevision(int revision) =>
      aiInvestigationRevision == revision;

  void markNeedsReview(List<ProductDuplicateCandidate> candidates) {
    isCheckingSimilar = false;
    independentDuplicateResult = null;
    duplicateResult = null;
    supplierResolutionProposal = null;
    similarCandidates = candidates;
    resolutionError = null;
    resolutionState = OcrProductResolutionState.reviewRequired;
  }

  void markSearchResult(
    ProductDuplicateSearchResult result, {
    SupplierResolutionProposal? supplierResolutionProposal,
  }) {
    independentDuplicateResult = result;
    this.supplierResolutionProposal = supplierResolutionProposal;
    applyReconciledSearchResult(result);
  }

  void applyReconciledSearchResult(ProductDuplicateSearchResult result) {
    isCheckingSimilar = false;
    if (!identical(result, independentDuplicateResult)) {
      supplierResolutionProposal = null;
    }
    duplicateResult = result;
    similarCandidates = result.recommendations;
    resolutionError = null;
    resolutionState = result.recommendations.isEmpty
        ? result.kind == ProductDuplicateDecisionKind.abstained
            ? OcrProductResolutionState.abstained
            : OcrProductResolutionState.noCandidates
        : OcrProductResolutionState.reviewRequired;
  }

  void markNoCandidates() {
    isCheckingSimilar = false;
    similarCandidates = [];
    independentDuplicateResult = null;
    duplicateResult = null;
    supplierResolutionProposal = null;
    resolutionError = null;
    resolutionState = OcrProductResolutionState.noCandidates;
  }

  void markNewProduct() {
    isCheckingSimilar = false;
    supplierResolutionProposal = null;
    resolutionError = null;
    resolutionState = OcrProductResolutionState.newProduct;
  }

  void markSupplierResolution(
    SupplierVariantResolution resolution,
    List<inv_models.Product> products,
  ) {
    isCheckingSimilar = false;
    isLinkingExisting = false;
    resolutionError = null;
    supplierResolution = resolution;
    supplierResolutionProposal = null;
    supplierResolutionProducts = List<inv_models.Product>.unmodifiable(
      products,
    );
    independentDuplicateResult = null;
    duplicateResult = null;
    similarCandidates = const [];
  }

  bool get hasSupplierResolution => supplierResolution?.isResolved == true;

  void markLinkedProduct(inv_models.Product product) {
    isCheckingSimilar = false;
    isLinkingExisting = false;
    resolutionError = null;
    linkedProduct = product;
  }

  void clearLinkedProduct() {
    linkedProduct = null;
    resolutionState = similarCandidates.isEmpty
        ? duplicateResult?.kind == ProductDuplicateDecisionKind.abstained
            ? OcrProductResolutionState.abstained
            : OcrProductResolutionState.unsearched
        : OcrProductResolutionState.reviewRequired;
  }

  void markResolutionFailed(Object error) {
    isCheckingSimilar = false;
    resolutionError = error.toString();
    resolutionState = OcrProductResolutionState.failed;
  }

  void cancelTransientReviewWork() {
    final wasTransient = isAICleaningName ||
        isCheckingSimilar ||
        isLinkingExisting ||
        isUploadingImage ||
        resolutionState == OcrProductResolutionState.searching;
    if (!wasTransient) return;
    resolutionRevision++;
    isAICleaningName = false;
    isCheckingSimilar = false;
    isLinkingExisting = false;
    isUploadingImage = false;
    if (resolutionState == OcrProductResolutionState.searching) {
      resolutionState = OcrProductResolutionState.unsearched;
      resolutionError = null;
    }
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

  /// The code this row will actually be created with.
  ///
  /// For an AliExpress row that is the reserved, database-owned number and
  /// nothing else. The text field is a display of it; typing over it must not
  /// be able to send a different code to `createProduct`.
  String get sku =>
      requiresDuplicateReview ? (reservedSku ?? '') : skuController.text.trim();

  /// What the SKU column shows: the linked product's code while the row is
  /// linked, this row's reservation once it has one.
  String get displaySku {
    final linked = linkedProduct?.sku.trim() ?? '';
    if (linked.isNotEmpty) return linked;
    return requiresDuplicateReview
        ? (reservedSku ?? '')
        : skuController.text.trim();
  }

  /// Puts the SKU field back in agreement with the row's current decision,
  /// without spending another reservation.
  void syncSkuField() {
    final expected = displaySku;
    if (skuController.text != expected) skuController.text = expected;
  }

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
  bool get isValid => sku.isNotEmpty && isValidWithoutSku;

  bool get isValidWithoutSku =>
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
