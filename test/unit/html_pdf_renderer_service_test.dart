import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:vinabike_erp/shared/services/html_pdf_renderer_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test.html_pdf_renderer');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('macOS renderer forwards readiness contract and returns PDF bytes',
      () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      receivedCall = call;
      return Uint8List.fromList('%PDF-test'.codeUnits);
    });
    final renderer = HtmlPdfRendererService(
      channel: channel,
      useNativeMacOSOverride: true,
    );

    final bytes = await renderer.render(
      html: '<main id="invoiceRoot">Pedido</main>',
      format: PdfPageFormat.letter,
      readySelector: '#invoiceRoot',
      readyFlag: '__ALIEXPRESS_INVOICE_READY__',
    );

    expect(String.fromCharCodes(bytes), '%PDF-test');
    expect(receivedCall?.method, HtmlPdfRendererService.renderMethod);
    expect(receivedCall?.arguments, <String, Object?>{
      'html': '<main id="invoiceRoot">Pedido</main>',
      'viewportWidth': PdfPageFormat.letter.width,
      'viewportHeight': PdfPageFormat.letter.height,
      'readySelector': '#invoiceRoot',
      'readyFlag': '__ALIEXPRESS_INVOICE_READY__',
    });
  });

  test('macOS renderer rejects missing or malformed native output', () async {
    final renderer = HtmlPdfRendererService(
      channel: channel,
      useNativeMacOSOverride: true,
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    await expectLater(
      renderer.render(html: '<main>Pedido</main>'),
      throwsA(isA<StateError>()),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (_) async => Uint8List.fromList('not-a-pdf'.codeUnits),
    );
    await expectLater(
      renderer.render(html: '<main>Pedido</main>'),
      throwsA(isA<FormatException>()),
    );
  });

  test('other platforms keep the injected platform fallback', () async {
    var called = false;
    final renderer = HtmlPdfRendererService(
      useNativeMacOSOverride: false,
      printablePreparer: (html,
              {readySelector,
              readyFlag,
              timeout = const Duration(seconds: 30)}) async =>
          html,
      fallbackRenderer: (html, format) async {
        called = true;
        expect(html, '<main>Pedido</main>');
        expect(format, PdfPageFormat.a4);
        return Uint8List.fromList('%PDF-fallback'.codeUnits);
      },
    );

    final bytes = await renderer.render(
      html: '<main>Pedido</main>',
      format: PdfPageFormat.a4,
    );

    expect(called, isTrue);
    expect(String.fromCharCodes(bytes), '%PDF-fallback');
  });

  test(
      'the default fallback attempts the platform converter and reports '
      '"cannot" only when the implementation is missing', () async {
    // The Android plugin converts HTML but never reports canConvertHtml, so
    // gating on that flag rejected every phone (owner, 2026-09-03). Without a
    // platform (this test) the attempt itself surfaces the honest error.
    TestWidgetsFlutterBinding.ensureInitialized();
    final renderer = HtmlPdfRendererService(
      useNativeMacOSOverride: false,
      printablePreparer: (html,
              {readySelector,
              readyFlag,
              timeout = const Duration(seconds: 30)}) async =>
          html,
    );
    await expectLater(
      renderer.render(html: '<html><body>x</body></html>'),
      throwsA(isA<UnsupportedError>().having(
        (error) => error.message,
        'message',
        contains('no puede convertir la plantilla HTML'),
      )),
    );
    final source = File('lib/shared/services/html_pdf_renderer_service.dart')
        .readAsStringSync();
    expect(source, isNot(contains('if (!printingInfo.canConvertHtml)')),
        reason: 'the capability flag is not reported by Android');
    expect(source,
        contains('await Printing.convertHtml(html: html, format: edgeToEdge)'));
    expect(source, contains('marginLeft: 0,'),
        reason: 'the template owns its page padding, like the macOS host');
  });

  test('phones print the finished document, never the unrendered shell',
      () async {
    // Android's converter prints a WebView with JavaScript off, and this
    // template draws its body from JavaScript: the phone filed a blank page
    // (owner, 2026-09-03). The template is run first and the finished DOM is
    // what reaches the converter.
    String? preparedHtml;
    String? seenSelector;
    String? seenFlag;
    String? convertedHtml;
    final renderer = HtmlPdfRendererService(
      useNativeMacOSOverride: false,
      printablePreparer: (html,
          {readySelector,
          readyFlag,
          timeout = const Duration(seconds: 30)}) async {
        preparedHtml = html;
        seenSelector = readySelector;
        seenFlag = readyFlag;
        return '<!doctype html><html><body>rendered</body></html>';
      },
      fallbackRenderer: (html, format) async {
        convertedHtml = html;
        return Uint8List.fromList('%PDF-1.7 ok'.codeUnits);
      },
    );

    final bytes = await renderer.render(
      html: '<html><body><main id="invoiceRoot"></main></body></html>',
      readySelector: '#invoiceRoot',
      readyFlag: '__ALIEXPRESS_INVOICE_READY__',
    );

    expect(preparedHtml, contains('invoiceRoot'));
    expect(seenSelector, '#invoiceRoot');
    expect(seenFlag, '__ALIEXPRESS_INVOICE_READY__');
    expect(convertedHtml, '<!doctype html><html><body>rendered</body></html>',
        reason: 'the converter receives the finished document');
    expect(HtmlPdfRendererService.hasPdfHeader(bytes), isTrue);
  });

  test('a template that never finishes drawing fails instead of printing blank',
      () async {
    var converterCalls = 0;
    final renderer = HtmlPdfRendererService(
      useNativeMacOSOverride: false,
      printablePreparer: (html,
              {readySelector,
              readyFlag,
              timeout = const Duration(seconds: 30)}) async =>
          throw TimeoutException('no terminó', timeout),
      fallbackRenderer: (html, format) async {
        converterCalls++;
        return Uint8List.fromList('%PDF-1.7'.codeUnits);
      },
    );

    await expectLater(
      renderer.render(html: '<html></html>'),
      throwsA(isA<StateError>().having((error) => error.message, 'message',
          contains('No se pudo preparar la plantilla'))),
    );
    expect(converterCalls, 0, reason: 'a blank page is never filed');
  });

  test('readiness means the flag, a filled element, and finished images', () {
    final probe = HtmlPdfRendererService.readinessProbeSource(
      readySelector: '#invoiceRoot',
      readyFlag: '__ALIEXPRESS_INVOICE_READY__',
    );
    expect(probe, contains('globalThis["__ALIEXPRESS_INVOICE_READY__"]'));
    expect(probe, contains('document.querySelector("#invoiceRoot")'));
    expect(probe, contains('.childElementCount'),
        reason: 'an empty root is exactly the blank-page symptom');
    expect(probe, contains('image.complete'));
    expect(
      HtmlPdfRendererService.readinessProbeSource(),
      contains('true'),
      reason: 'without a contract the document only has to exist',
    );
    expect(HtmlPdfRendererService.serializeDocumentSource,
        contains("clone.querySelectorAll('script')"),
        reason: 'the printed copy runs nothing of its own');
  });
}
