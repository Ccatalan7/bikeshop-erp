import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../services/ocr_service.dart';
import '../services/invoice_parser_service.dart';
import '../services/pdf_parser_service.dart';

/// Callback when OCR completes successfully
typedef OnOCRComplete = void Function(ParsedInvoice parsedInvoice);

/// Callback when OCR fails
typedef OnOCRError = void Function(String error);

/// Reusable OCR Upload Widget
/// Allows user to:
/// 1. Take photo with camera
/// 2. Pick image from gallery
/// 3. Automatically extract text using OCR
/// 4. Parse invoice/receipt data
/// 5. Return parsed data to caller
class OCRUploadWidget extends StatefulWidget {
  /// Called when OCR successfully extracts invoice data
  final OnOCRComplete onComplete;

  /// Called when OCR fails
  final OnOCRError? onError;

  /// Type of document to scan
  final OCRDocumentType documentType;

  /// Show preview of extracted text before returning
  final bool showPreview;

  const OCRUploadWidget({
    super.key,
    required this.onComplete,
    this.onError,
    this.documentType = OCRDocumentType.invoice,
    this.showPreview = true,
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

  @override
  void initState() {
    super.initState();
    _ocrService.initialize();
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
              onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
            ),
            // Gallery button
            _buildActionButton(
              icon: Icons.photo_library,
              label: 'Galería',
              onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
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
          const Column(
            children: [
              SizedBox(height: 16),
              CircularProgressIndicator(),
              SizedBox(height: 8),
              Text('Procesando imagen...'),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 8),
            const Text(
              'Datos Extraídos',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Extracted fields
        if (data.supplierName != null) ...[
          _buildDataField('Proveedor', data.supplierName!),
          const SizedBox(height: 8),
        ],
        if (data.rut != null) ...[
          _buildDataField('RUT', data.rut!),
          const SizedBox(height: 8),
        ],
        if (data.invoiceNumber != null) ...[
          _buildDataField('N° Factura', data.invoiceNumber!),
          const SizedBox(height: 8),
        ],
        if (data.date != null) ...[
          _buildDataField('Fecha', '${data.date!.day}/${data.date!.month}/${data.date!.year}'),
          const SizedBox(height: 8),
        ],
        if (data.total != null) ...[
          _buildDataField('Total', '\$${data.total!.toStringAsFixed(0)}'),
          const SizedBox(height: 8),
        ],
        if (data.lineItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Productos: ${data.lineItems.length}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],

        const SizedBox(height: 24),

        // Action buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () {
                setState(() {
                  _parsedData = null;
                  _errorMessage = null;
                });
              },
              child: const Text('Reintentar'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                widget.onComplete(data);
              },
              child: const Text('Usar Datos'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDataField(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
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

      print('📷 Image picked: ${image.path}');

      // Process with OCR
      final recognizedText = await _ocrService.processImage(image.path);

      if (recognizedText.text.isEmpty) {
        throw Exception('No se pudo extraer texto de la imagen');
      }

      // Parse invoice data
      final parsedData = widget.documentType == OCRDocumentType.invoice
          ? _parserService.parseInvoice(recognizedText)
          : _parserService.parseReceipt(recognizedText);

      print('📋 Parsed data: $parsedData');

      setState(() {
        _parsedData = parsedData;
        _isProcessing = false;
      });

      // If preview disabled, return immediately
      if (!widget.showPreview) {
        widget.onComplete(parsedData);
      }
    } catch (e) {
      print('❌ OCR error: $e');
      final errorMsg = 'Error al procesar imagen: $e';
      
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
      
      // Web: use bytes, Native: use path
      ParsedInvoice? parsedData;
      
      if (file.bytes != null) {
        // Web platform - use bytes
        print('📄 PDF picked (web): ${file.name}');
        parsedData = await _pdfService.parseInvoiceFromBytes(file.bytes!, filename: file.name);
      } else if (file.path != null) {
        // Native platform - use path
        print('📄 PDF picked (native): ${file.path}');
        parsedData = await _pdfService.parseInvoiceFromPDF(file.path!);
      } else {
        throw Exception('No se pudo acceder al archivo PDF');
      }

      if (parsedData == null) {
        throw Exception(
          'Este PDF parece ser escaneado (sin texto seleccionable).\n\n'
          'Por favor, usa la opción de Cámara o Galería para escanear el documento.'
        );
      }

      print('📋 Parsed PDF data: $parsedData');

      setState(() {
        _parsedData = parsedData;
        _isProcessing = false;
      });

      // If preview disabled, return immediately
      if (!widget.showPreview) {
        widget.onComplete(parsedData);
      }
    } catch (e) {
      print('❌ PDF processing error: $e');
      final errorMsg = e.toString().contains('escaneado') 
          ? e.toString() 
          : 'Error al procesar PDF: $e';
      
      setState(() {
        _errorMessage = errorMsg;
        _isProcessing = false;
      });

      if (widget.onError != null) {
        widget.onError!(errorMsg);
      }
    }
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
