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

  const OCRUploadWidget({
    super.key,
    required this.onComplete,
    this.onError,
    this.documentType = OCRDocumentType.invoice,
    this.showPreview = true,
    this.provider = OCRProvider.auto,
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
      mainAxisSize: MainAxisSize.min,
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
              _buildDetailRow(
                Icons.store,
                'Proveedor',
                data.supplierName ?? 'No detectado',
                isBold: true,
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
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(theme
                        .colorScheme.surfaceContainerHighest
                        .withOpacity(0.5)),
                    columnSpacing: 20,
                    horizontalMargin: 12,
                    columns: const [
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('Descripción')),
                      DataColumn(label: Text('Cant.')),
                      DataColumn(label: Text('Precio')),
                      DataColumn(label: Text('Total')),
                    ],
                    rows: data.lineItems.map((item) {
                      return DataRow(cells: [
                        DataCell(
                          Text(
                            item.sku ?? '-',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 120,
                            child: Text(
                              item.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        DataCell(
                            Text(item.quantity?.toStringAsFixed(0) ?? '1')),
                        DataCell(Text(
                          item.unitPrice != null
                              ? '\$${item.unitPrice!.toStringAsFixed(0)}'
                              : '-',
                        )),
                        DataCell(Text(
                          item.total != null
                              ? '\$${item.total!.toStringAsFixed(0)}'
                              : '-',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),

        const SizedBox(height: 24),

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
      setState(() {
        _parsedData = parsedData;
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
      setState(() {
        _parsedData = parsedData;
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
