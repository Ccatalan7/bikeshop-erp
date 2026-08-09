import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'website_background_removal_processor.dart';
import 'website_media_service.dart';
import 'website_service.dart';

class WebsiteBackgroundRemovalSmartResult {
  final String imageUrl;
  final String sourceUrl;

  const WebsiteBackgroundRemovalSmartResult({
    required this.imageUrl,
    required this.sourceUrl,
  });
}

class WebsiteBackgroundRemovalService {
  final SupabaseClient _supabase;
  final http.Client _http;

  WebsiteBackgroundRemovalService({
    SupabaseClient? supabase,
    http.Client? httpClient,
  })  : _supabase = supabase ?? Supabase.instance.client,
        _http = httpClient ?? http.Client();

  Future<Uint8List> downloadImage(String imageUrl) async {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null || !uri.hasScheme) {
      throw const FormatException('La imagen no tiene una URL válida.');
    }
    final response = await _http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'No se pudo descargar la imagen (${response.statusCode}).',
      );
    }
    if (response.bodyBytes.length > 15 * 1024 * 1024) {
      throw const FormatException('La imagen supera el límite de 15 MB.');
    }
    return response.bodyBytes;
  }

  Future<WebsiteBackgroundRemovalResult> removeUniformBackground(
    Uint8List bytes, {
    int tolerance = 34,
  }) {
    return compute(
      _processUniformBackground,
      <String, Object>{
        'bytes': bytes,
        'tolerance': tolerance,
      },
    );
  }

  Future<String> uploadTransparentPng(
    Uint8List pngBytes, {
    String prefix = 'website-no-bg',
    String? originalUrl,
    String? tenantId,
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    final asset = await WebsiteMediaService(client: _supabase).uploadImage(
      bytes: pngBytes,
      fileName: '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png',
      operation: 'background-removal-local',
      originalUrl: originalUrl,
      tenantId: tenantId,
      writeGuard: writeGuard,
    );
    if (asset.publicUrl.isEmpty) {
      throw Exception('No se pudo guardar la imagen transparente.');
    }
    return asset.publicUrl;
  }

  Future<WebsiteBackgroundRemovalSmartResult> removeSmartBackground({
    required String imageUrl,
    String? tenantId,
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    writeGuard?.call();
    final response = await _supabase.functions.invoke(
      'website-remove-background',
      body: {
        'imageUrl': imageUrl,
        if (tenantId != null && tenantId.isNotEmpty) 'tenantId': tenantId,
      },
    );
    writeGuard?.call();
    final data = response.data;
    if (response.status < 200 || response.status >= 300 || data is! Map) {
      throw Exception(_smartErrorMessage(data, response.status));
    }
    final sourceUrl = data['imageUrl']?.toString().trim() ?? '';
    final sourcePath = data['sourcePath']?.toString().trim() ?? '';
    if (sourceUrl.isEmpty || sourcePath.isEmpty) {
      throw Exception('El servicio inteligente no devolvió una imagen.');
    }
    final optimized =
        await WebsiteMediaService(client: _supabase).optimizeStoredImage(
      sourcePath: sourcePath,
      sourceUrl: sourceUrl,
      fileName: 'smart-no-bg.png',
      operation: 'background-removal-smart',
      originalUrl: imageUrl,
      writeGuard: writeGuard,
    );
    writeGuard?.call();
    return WebsiteBackgroundRemovalSmartResult(
      imageUrl: optimized.publicUrl,
      sourceUrl: sourceUrl,
    );
  }

  String _smartErrorMessage(dynamic data, int status) {
    final code = data is Map ? data['code']?.toString() : null;
    if (code == 'provider_not_configured') {
      return 'La eliminación inteligente todavía no está configurada. '
          'El modo local gratuito sigue disponible.';
    }
    if (status == 402 || code == 'provider_credits_exhausted') {
      return 'No quedan créditos del servicio inteligente.';
    }
    if (status == 429) {
      return 'El servicio inteligente está ocupado. Inténtalo nuevamente.';
    }
    return data is Map && data['error'] != null
        ? data['error'].toString()
        : 'No se pudo quitar el fondo automáticamente.';
  }
}

FutureOr<WebsiteBackgroundRemovalResult> _processUniformBackground(
  Map<String, Object> request,
) {
  return WebsiteBackgroundRemovalProcessor.process(
    request['bytes']! as Uint8List,
    tolerance: request['tolerance']! as int,
  );
}
