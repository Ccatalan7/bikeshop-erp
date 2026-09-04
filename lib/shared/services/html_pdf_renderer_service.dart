import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

typedef HtmlPdfFallbackRenderer = Future<Uint8List> Function(
  String html,
  PdfPageFormat format,
);

/// Runs a JavaScript-rendered template and returns the finished document as
/// static HTML.
typedef HtmlPrintablePreparer = Future<String> Function(
  String html, {
  String? readySelector,
  String? readyFlag,
  Duration timeout,
});

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
    HtmlPrintablePreparer? printablePreparer,
    Duration nativeTimeout = const Duration(seconds: 30),
  })  : _channel = channel ?? const MethodChannel(channelName),
        _useNativeMacOSOverride = useNativeMacOSOverride,
        _fallbackRenderer = fallbackRenderer ?? _renderWithPrinting,
        _printablePreparer = printablePreparer ?? prepareWithHeadlessWebView,
        _nativeTimeout = nativeTimeout;

  static const channelName = 'com.vinabike.erp/html_pdf_renderer';
  static const renderMethod = 'renderHtml';

  final MethodChannel _channel;
  final bool? _useNativeMacOSOverride;
  final HtmlPdfFallbackRenderer _fallbackRenderer;
  final HtmlPrintablePreparer _printablePreparer;
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
      // The platform converter prints a plain WebView with JavaScript OFF on
      // Android, and this template draws its whole body from JavaScript, so
      // the phone filed an empty page as the invoice (owner, 2026-09-03; the
      // OCR review still looked right because the handoff also carries the
      // parsed data). Run the template first, print the finished document.
      final String printable;
      try {
        printable = await _printablePreparer(
          html,
          readySelector: readySelector,
          readyFlag: readyFlag,
          timeout: _nativeTimeout,
        );
      } catch (error) {
        throw StateError(
          'No se pudo preparar la plantilla antes de convertirla a PDF. '
          'Detalle: $error',
        );
      }
      bytes = await _fallbackRenderer(printable, format);
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

  /// Renders [html] in a headless web view with JavaScript enabled, waits for
  /// the same readiness contract the macOS host honours, and returns the
  /// finished DOM as static HTML with its scripts removed.
  ///
  /// Static output is what makes the result identical on every printer path:
  /// nothing is left to run, or to fail to run, inside the converter.
  @visibleForTesting
  static Future<String> prepareWithHeadlessWebView(
    String html, {
    String? readySelector,
    String? readyFlag,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final loaded = Completer<void>();
    HeadlessInAppWebView? webView;
    try {
      webView = HeadlessInAppWebView(
        initialSize: const Size(816, 1056), // Letter at 96 dpi.
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          javaScriptCanOpenWindowsAutomatically: false,
          supportMultipleWindows: false,
          incognito: true,
        ),
        initialData: InAppWebViewInitialData(
          data: html,
          mimeType: 'text/html',
          encoding: 'utf-8',
        ),
        onLoadStop: (_, __) {
          if (!loaded.isCompleted) loaded.complete();
        },
        onReceivedError: (_, __, ___) {
          if (!loaded.isCompleted) loaded.complete();
        },
        onReceivedHttpError: (_, __, ___) {
          if (!loaded.isCompleted) loaded.complete();
        },
      );
      await webView.run();
      await loaded.future.timeout(timeout);
      final controller = webView.webViewController;
      if (controller == null) {
        throw StateError('El renderizador oculto no expuso su controlador.');
      }

      final probe = readinessProbeSource(
        readySelector: readySelector,
        readyFlag: readyFlag,
      );
      final deadline = DateTime.now().add(timeout);
      while (true) {
        final ready = await controller.evaluateJavascript(source: probe);
        if (ready == true || ready == 1 || ready.toString() == 'true') break;
        if (!DateTime.now().isBefore(deadline)) {
          throw TimeoutException(
            'La plantilla no terminó de dibujarse antes de imprimirla.',
            timeout,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }

      final serialized = await controller.evaluateJavascript(
        source: serializeDocumentSource,
      );
      final printable = serialized?.toString().trim() ?? '';
      if (printable.isEmpty) {
        throw StateError('El renderizador oculto devolvió un documento vacío.');
      }
      return printable;
    } finally {
      await webView?.dispose();
    }
  }

  /// True once the template says it is done: its ready flag is set, the ready
  /// element exists **and holds content**, and every image has finished.
  @visibleForTesting
  static String readinessProbeSource({
    String? readySelector,
    String? readyFlag,
  }) {
    final flagCheck = readyFlag == null
        ? 'true'
        : 'Boolean(globalThis[${jsonEncode(readyFlag)}])';
    final selectorCheck = readySelector == null
        ? 'true'
        : 'Boolean((document.querySelector(${jsonEncode(readySelector)}) || {})'
            '.childElementCount)';
    return '''
(function () {
  try {
    var images = Array.prototype.slice.call(document.images || []);
    return Boolean(
      $flagCheck &&
      $selectorCheck &&
      images.every(function (image) { return image.complete; })
    );
  } catch (error) {
    return false;
  }
})()
''';
  }

  /// The finished DOM, without scripts: what the converter prints is exactly
  /// what the template already drew.
  @visibleForTesting
  static const String serializeDocumentSource = '''
(function () {
  var clone = document.documentElement.cloneNode(true);
  var scripts = clone.querySelectorAll('script');
  for (var index = 0; index < scripts.length; index++) {
    scripts[index].parentNode.removeChild(scripts[index]);
  }
  return '<!doctype html>\\n' + clone.outerHTML;
})()
''';

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
      // The template carries its own page padding and the macOS host prints
      // it edge to edge; printer margins on top would shrink the phone copy.
      final edgeToEdge = format.copyWith(
        marginLeft: 0,
        marginTop: 0,
        marginRight: 0,
        marginBottom: 0,
      );
      // Non-macOS targets keep their platform implementation. macOS never
      // reaches this deprecated API.
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
