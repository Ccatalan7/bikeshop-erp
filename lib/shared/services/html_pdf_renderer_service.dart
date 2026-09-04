import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

typedef HtmlPdfFallbackRenderer = Future<Uint8List> Function(
  String html,
  PdfPageFormat format,
);

/// Converts the shared browser HTML document into PDF bytes.
///
/// macOS deliberately uses an app-owned native renderer. `printing`'s
/// deprecated HTML converter creates a detached, zero-sized WKWebView and
/// asks WebKit for a PDF after a fixed one-second delay. Whether that succeeds
/// varies by WebKit version and machine. The app-owned host instead attaches a
/// letter-sized WKWebView, waits for the document, fonts, images, and the
/// renderer's explicit ready flag, and only then captures the PDF.
class HtmlPdfRendererService {
  HtmlPdfRendererService({
    MethodChannel? channel,
    bool? useNativeMacOSOverride,
    HtmlPdfFallbackRenderer? fallbackRenderer,
    Duration nativeTimeout = const Duration(seconds: 30),
  })  : _channel = channel ?? const MethodChannel(channelName),
        _useNativeMacOSOverride = useNativeMacOSOverride,
        _fallbackRenderer = fallbackRenderer ?? _renderWithPrinting,
        _nativeTimeout = nativeTimeout;

  static const channelName = 'com.vinabike.erp/html_pdf_renderer';
  static const renderMethod = 'renderHtml';

  final MethodChannel _channel;
  final bool? _useNativeMacOSOverride;
  final HtmlPdfFallbackRenderer _fallbackRenderer;
  final Duration _nativeTimeout;

  bool get _useNativeMacOS =>
      _useNativeMacOSOverride ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS);

  Future<Uint8List> render({
    required String html,
    PdfPageFormat format = PdfPageFormat.standard,
    String? readySelector,
    String? readyFlag,
  }) async {
    if (html.trim().isEmpty) {
      throw ArgumentError.value(html, 'html', 'El documento está vacío.');
    }

    final Uint8List bytes;
    if (_useNativeMacOS) {
      try {
        final rendered = await _channel.invokeMethod<Uint8List>(
          renderMethod,
          <String, Object?>{
            'html': html,
            'viewportWidth': format.width,
            'viewportHeight': format.height,
            'readySelector': readySelector,
            'readyFlag': readyFlag,
          },
        ).timeout(_nativeTimeout);
        if (rendered == null) {
          throw StateError('El renderizador nativo no devolvió un PDF.');
        }
        bytes = rendered;
      } on MissingPluginException {
        throw StateError(
          'El renderizador PDF de macOS no está disponible en esta versión '
          'de la aplicación.',
        );
      } on TimeoutException {
        throw TimeoutException(
          'macOS tardó demasiado en preparar la plantilla para PDF.',
          _nativeTimeout,
        );
      }
    } else {
      bytes = await _fallbackRenderer(html, format);
    }

    if (!hasPdfHeader(bytes)) {
      throw const FormatException(
        'El renderizador devolvió un archivo que no es un PDF válido.',
      );
    }
    return bytes;
  }

  @visibleForTesting
  static bool hasPdfHeader(Uint8List bytes) =>
      bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2D;

  /// Android and iOS convert through the platform WebView print pipeline.
  ///
  /// `Printing.info().canConvertHtml` is not the gate: the Android plugin
  /// implements `convertHtml` but never reports that key, so the flag read as
  /// `false` on every phone and the owner saw «Este equipo no puede convertir
  /// la plantilla» on a device that could (2026-09-03). The attempt itself is
  /// the capability check; only a missing implementation is "cannot".
  static Future<Uint8List> _renderWithPrinting(
    String html,
    PdfPageFormat format,
  ) async {
    try {
      // Non-macOS targets keep their platform implementation. macOS never
      // reaches this deprecated API.
      // The template carries its own page padding and the macOS host prints
      // it edge to edge; printer margins on top would shrink the phone copy.
      final edgeToEdge = format.copyWith(
        marginLeft: 0,
        marginTop: 0,
        marginRight: 0,
        marginBottom: 0,
      );
      // ignore: deprecated_member_use
      return await Printing.convertHtml(html: html, format: edgeToEdge);
    } on MissingPluginException {
      throw UnsupportedError(
        'Este equipo no puede convertir la plantilla HTML de AliExpress.',
      );
    } on UnimplementedError {
      throw UnsupportedError(
        'Este equipo no puede convertir la plantilla HTML de AliExpress.',
      );
    } on PlatformException catch (error) {
      if (error.code.toLowerCase().contains('unimplemented') ||
          error.code.toLowerCase().contains('unsupported')) {
        throw UnsupportedError(
          'Este equipo no puede convertir la plantilla HTML de AliExpress.',
        );
      }
      rethrow;
    }
  }
}
