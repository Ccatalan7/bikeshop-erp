import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Size;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// OCR Service using Google ML Kit Text Recognition
/// Extracts text from images (invoices, receipts, documents)
/// Works on Android, iOS, and Web (via Firebase ML)
class OCRService {
  static final OCRService _instance = OCRService._internal();
  factory OCRService() => _instance;
  OCRService._internal();

  late final TextRecognizer _textRecognizer;
  bool _isInitialized = false;

  /// Initialize the text recognizer
  /// Call this once at app startup or before first use
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Use Latin script (optimized for Spanish, English, French, etc.)
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      _isInitialized = true;
      print('✅ OCR Service initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize OCR Service: $e');
      rethrow;
    }
  }

  /// Process an image file and extract text
  /// Returns RecognizedText with blocks, lines, and elements
  ///
  /// Example usage:
  /// ```dart
  /// final result = await OCRService().processImage(File('invoice.jpg'));
  /// print('Extracted text: ${result.text}');
  /// for (var block in result.blocks) {
  ///   print('Block: ${block.text}');
  /// }
  /// ```
  Future<RecognizedText> processImage(String imagePath) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);

      print('📄 OCR extracted ${recognizedText.blocks.length} text blocks');
      return recognizedText;
    } catch (e) {
      print('❌ OCR processing failed: $e');
      rethrow;
    }
  }

  /// Process image from bytes (useful for web, network images)
  Future<RecognizedText> processImageBytes(
    List<int> bytes, {
    required int width,
    required int height,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final inputImage = InputImage.fromBytes(
        bytes: bytes as Uint8List,
        metadata: InputImageMetadata(
          size: Size(width.toDouble(), height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: width,
        ),
      );

      final recognizedText = await _textRecognizer.processImage(inputImage);
      print(
          '📄 OCR extracted ${recognizedText.blocks.length} text blocks from bytes');
      return recognizedText;
    } catch (e) {
      print('❌ OCR processing from bytes failed: $e');
      rethrow;
    }
  }

  /// Extract plain text as a single string
  /// Useful for simple text extraction without structure
  Future<String> extractText(String imagePath) async {
    final result = await processImage(imagePath);
    return result.text;
  }

  /// Extract text with line-by-line structure
  /// Returns list of lines (useful for receipts, invoices)
  Future<List<String>> extractLines(String imagePath) async {
    final result = await processImage(imagePath);
    final lines = <String>[];

    for (var block in result.blocks) {
      for (var line in block.lines) {
        if (line.text.trim().isNotEmpty) {
          lines.add(line.text.trim());
        }
      }
    }

    return lines;
  }

  /// Extract text blocks (useful for structured documents)
  /// Each block represents a paragraph or section
  Future<List<TextBlock>> extractBlocks(String imagePath) async {
    final result = await processImage(imagePath);
    return result.blocks;
  }

  /// Dispose resources when done
  /// Call this when app is closing or service is no longer needed
  Future<void> dispose() async {
    if (_isInitialized) {
      await _textRecognizer.close();
      _isInitialized = false;
      print('🔒 OCR Service disposed');
    }
  }

  /// Check if OCR is available on this platform
  static bool get isSupported {
    // ML Kit works on Android, iOS, and Web (via Firebase)
    // Desktop (Windows, macOS, Linux) not officially supported yet
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS;
  }
}
