import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'invoice_parser_service.dart';
// API service disabled - uncomment to re-enable Python API integration
// import 'invoice_parser_api_service.dart';

/// Service for extracting text from PDF files
/// 
/// **Parsing Strategy:**
/// 1. Try Python API service first (most accurate, handles complex layouts)
/// 2. Fallback to Dart parser if API unavailable
/// 
/// For scanned PDFs, users should:
/// 1. Take photo of the PDF on screen, OR
/// 2. Convert PDF to image first, then use OCR camera/gallery feature
class PDFParserService {
  final InvoiceParserService _invoiceParser = InvoiceParserService();
  // API service disabled - uncomment to re-enable Python API integration
  // final InvoiceParserApiService _apiService = InvoiceParserApiService();

  /// Extract text from a PDF file (digital PDFs only)
  /// 
  /// Works for PDFs with selectable text. For scanned PDFs, use camera/gallery OCR instead.
  Future<PDFExtractionResult> extractTextFromPDF(String filePath) async {
    try {
      debugPrint('🔍 PDFParserService: Starting PDF text extraction from $filePath');

      // Try direct text extraction (digital PDFs)
      final directText = await _extractTextDirect(filePath);
      
      if (_isValidExtraction(directText)) {
        debugPrint('✅ PDFParserService: Direct text extraction successful (${directText.length} chars)');
        return PDFExtractionResult(
          text: directText,
          method: PDFExtractionMethod.direct,
          pageCount: await _getPageCount(filePath),
        );
      }

      debugPrint('⚠️ PDFParserService: PDF appears to be scanned (no selectable text)');
      debugPrint('💡 Please use camera/gallery feature to scan the document instead');
      
      return PDFExtractionResult(
        text: '',
        method: PDFExtractionMethod.scanned,
        pageCount: await _getPageCount(filePath),
      );
    } catch (e, stackTrace) {
      debugPrint('❌ PDFParserService: Error extracting text from PDF: $e');
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }

  /// Parse invoice data from PDF file path (native platforms)
  /// 
  /// Extracts text and parses invoice information (RUT, date, total, etc.)
  Future<ParsedInvoice?> parseInvoiceFromPDF(String filePath) async {
    try {
      final result = await extractTextFromPDF(filePath);
      
      if (result.text.isEmpty) {
        debugPrint('⚠️ No text extracted - likely a scanned PDF');
        return null;
      }
      
      debugPrint('📄 PDFParserService: Parsing invoice from extracted text (method: ${result.method.name})');
      
      // Parse the plain text
      return _invoiceParser.parseInvoiceFromText(result.text);
    } catch (e) {
      debugPrint('❌ PDFParserService: Error parsing invoice from PDF: $e');
      return null;
    }
  }

  /// Parse invoice data from PDF bytes (web platform)
  /// 
  /// Strategy: Using Dart parser only (API integration disabled)
  Future<ParsedInvoice?> parseInvoiceFromBytes(Uint8List bytes, {String filename = 'invoice.pdf'}) async {
    try {
      debugPrint('🔍 Using Dart parser for invoice extraction...');
      
      // API integration disabled - uncomment below to re-enable
      /*
      final isApiAvailable = await _apiService.isServiceAvailable();
      if (isApiAvailable) {
        debugPrint('✅ API service available, using API parser...');
        final apiResult = await _apiService.parseInvoiceFromBytes(bytes, filename);
        if (apiResult != null) {
          debugPrint('✅ API parsing successful');
          return apiResult;
        }
      }
      */
      
      // Dart parser (original implementation)
      final result = await _extractTextFromBytes(bytes);
      
      if (result.text.isEmpty) {
        debugPrint('⚠️ No text extracted - likely a scanned PDF');
        return null;
      }
      
      debugPrint('📄 PDFParserService: Parsing invoice from extracted text (method: ${result.method.name})');
      
      // Parse the plain text
      return _invoiceParser.parseInvoiceFromText(result.text);
    } catch (e) {
      debugPrint('❌ PDFParserService: Error parsing invoice from PDF bytes: $e');
      return null;
    }
  }

  /// Extract text from PDF bytes (for web)
  Future<PDFExtractionResult> _extractTextFromBytes(Uint8List bytes) async {
    try {
      debugPrint('🔍 PDFParserService: Extracting text from PDF bytes');

      final directText = await _extractTextDirectFromBytes(bytes);
      
      if (_isValidExtraction(directText)) {
        debugPrint('✅ PDFParserService: Direct text extraction successful (${directText.length} chars)');
        return PDFExtractionResult(
          text: directText,
          method: PDFExtractionMethod.direct,
          pageCount: await _getPageCountFromBytes(bytes),
        );
      }

      debugPrint('⚠️ PDFParserService: PDF appears to be scanned (no selectable text)');
      
      return PDFExtractionResult(
        text: '',
        method: PDFExtractionMethod.scanned,
        pageCount: await _getPageCountFromBytes(bytes),
      );
    } catch (e, stackTrace) {
      debugPrint('❌ PDFParserService: Error extracting text from PDF bytes: $e');
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }

  /// Extract text directly from PDF bytes
  Future<String> _extractTextDirectFromBytes(Uint8List bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final StringBuffer textBuffer = StringBuffer();

      debugPrint('📄 ========== PDF TEXT EXTRACTION ==========');
      for (int i = 0; i < document.pages.count; i++) {
        final String pageText = PdfTextExtractor(document).extractText(startPageIndex: i, endPageIndex: i);
        textBuffer.writeln(pageText);
        debugPrint('📄 Page ${i + 1} (${pageText.length} chars):');
        debugPrint(pageText);
        debugPrint('📄 ==========================================');
      }

      document.dispose();
      final result = textBuffer.toString();
      debugPrint('📄 TOTAL EXTRACTED: ${result.length} characters');
      return result;
    } catch (e) {
      debugPrint('⚠️ Direct text extraction from bytes failed: $e');
      return '';
    }
  }

  /// Get page count from PDF bytes
  Future<int> _getPageCountFromBytes(Uint8List bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final count = document.pages.count;
      document.dispose();
      return count;
    } catch (e) {
      debugPrint('⚠️ Error getting page count from bytes: $e');
      return 1;
    }
  }

  /// Extract text directly from PDF using Syncfusion PDF library
  /// 
  /// Works for digital PDFs with selectable text. Fast and accurate.
  Future<String> _extractTextDirect(String filePath) async {
    try {
      // Load PDF document
      final File file = File(filePath);
      final Uint8List bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);

      final StringBuffer textBuffer = StringBuffer();

      // Extract text from each page
      for (int i = 0; i < document.pages.count; i++) {
        final String pageText = PdfTextExtractor(document).extractText(startPageIndex: i, endPageIndex: i);
        textBuffer.writeln(pageText);
        debugPrint('📄 Page ${i + 1}: Extracted ${pageText.length} characters');
      }

      document.dispose();

      return textBuffer.toString();
    } catch (e) {
      debugPrint('⚠️ Direct text extraction failed: $e');
      return '';
    }
  }

  /// Check if extracted text is valid (sufficient content)
  bool _isValidExtraction(String text) {
    // Require at least 50 characters for a valid extraction
    // This helps detect scanned PDFs that yield empty/minimal text
    return text.trim().length >= 50;
  }

  /// Get page count from PDF
  Future<int> _getPageCount(String filePath) async {
    try {
      final File file = File(filePath);
      final Uint8List bytes = await file.readAsBytes();
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final count = document.pages.count;
      document.dispose();
      return count;
    } catch (e) {
      debugPrint('⚠️ Error getting page count: $e');
      return 1;
    }
  }
}

/// Result of PDF text extraction
class PDFExtractionResult {
  final String text;
  final PDFExtractionMethod method;
  final int pageCount;

  PDFExtractionResult({
    required this.text,
    required this.method,
    required this.pageCount,
  });

  bool get isScanned => method == PDFExtractionMethod.scanned;
  bool get isDirect => method == PDFExtractionMethod.direct;
}

/// Method used to extract text from PDF
enum PDFExtractionMethod {
  /// Direct text extraction (digital PDF)
  direct,
  
  /// Scanned PDF detected (no text extraction possible, use camera OCR instead)
  scanned,
}
