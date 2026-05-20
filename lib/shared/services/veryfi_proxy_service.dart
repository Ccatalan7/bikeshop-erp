import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VeryfiProxyService {
  final SupabaseClient _client;

  VeryfiProxyService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<Map<String, dynamic>> parseInvoiceFromBytes(
    Uint8List bytes,
    String filename,
  ) async {
    final response = await _client.functions.invoke(
      'veryfi-ocr',
      body: {
        'filename': filename,
        'contentBase64': base64Encode(bytes),
        'contentType': _contentTypeForFilename(filename),
      },
    );

    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final error = data is Map<String, dynamic>
          ? (data['error']?.toString() ?? 'Unknown OCR proxy error')
          : data?.toString() ?? 'Unknown OCR proxy error';
      throw Exception('Veryfi proxy error: $error');
    }

    final data = response.data;
    if (data is Map<String, dynamic>) {
      return data;
    }

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    debugPrint('Unexpected OCR proxy response type: ${data.runtimeType}');
    throw Exception('Veryfi proxy error: Invalid response from OCR server');
  }

  String _contentTypeForFilename(String filename) {
    final extension = filename.split('.').last.trim().toLowerCase();
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'tif':
      case 'tiff':
        return 'image/tiff';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'application/octet-stream';
    }
  }
}
