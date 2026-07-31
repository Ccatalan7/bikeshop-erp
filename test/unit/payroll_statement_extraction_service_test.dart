import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:vinabike_erp/modules/hr/services/payroll_bank_statement_parser.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_statement_extraction_service.dart';

void main() {
  group('PayrollStatementExtractionService', () {
    test('extracts embedded PDF text without logging or cloud OCR', () async {
      var rasterWasCalled = false;
      final progress = <PayrollStatementPreparationProgress>[];
      final bytes = _syntheticPdfBytes(
        'Fecha Descripción Cargos Abonos Saldo\n'
        '27/07/2026 App-traspaso A: Persona Ejemplo 128.000 0 900.000',
      );

      final result = await PayrollStatementExtractionService(
        imageTextExtractor: ({
          required bytes,
          required filename,
          sourcePath,
        }) async =>
            throw StateError('No debe ejecutar OCR para un PDF digital.'),
        pdfPageRasterizer: ({
          required bytes,
          required pages,
        }) {
          rasterWasCalled = true;
          return const Stream<Uint8List>.empty();
        },
      ).extract(
        bytes: bytes,
        filename: 'cartola-redactada.pdf',
        onProgress: progress.add,
      );

      expect(
        result.method,
        PayrollStatementExtractionMethod.embeddedPdfText,
      );
      expect(result.pages, hasLength(1));
      expect(result.parserInput, matches(RegExp(r'Persona\s+Ejemplo')));
      expect(result.fileSha256, hasLength(64));
      expect(rasterWasCalled, isFalse);
      expect(
        progress.map((event) => event.phase),
        <PayrollStatementPreparationPhase>[
          PayrollStatementPreparationPhase.validatingFile,
          PayrollStatementPreparationPhase.readingPdfPage,
        ],
      );
      expect(progress.last.pageNumber, 1);
      expect(progress.last.pageCount, 1);
      expect(progress.last.fraction, 1);
    });

    test('preserves PDF columns and repairs a row split across pages',
        () async {
      final result = await PayrollStatementExtractionService().extract(
        bytes: _positionedStatementPdfBytes(),
        filename: 'cartola-tabular.pdf',
      );
      final parsed = const PayrollBankStatementParser().parsePages(
        result.pages.map((page) => page.text).toList(growable: false),
        statementYear: 2026,
      );

      expect(
        result.warnings,
        contains(contains('1 movimientos divididos')),
      );
      expect(parsed.rows, hasLength(3));
      expect(parsed.warnings, isEmpty);

      final splitRow = parsed.rows.firstWhere(
        (row) => row.description.contains('Persona Ejemplo'),
      );
      expect(splitRow.creditAmountClp, 6000);
      expect(splitRow.debitAmountClp, isNull);
      expect(splitRow.balanceAmountClp, 411372);

      final smallDebit = parsed.rows.firstWhere(
        (row) => row.description.contains('Cargo pequeño'),
      );
      expect(smallDebit.debitAmountClp, 86);
      expect(smallDebit.balanceAmountClp, 411286);
    });

    test('marks image input as requiring OCR when no local adapter exists',
        () async {
      final result = await PayrollStatementExtractionService().extract(
        bytes: Uint8List.fromList(<int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          ...List<int>.filled(80, 0),
        ]),
        filename: 'captura.png',
      );

      expect(result.inputKind, PayrollStatementInputKind.image);
      expect(result.needsImageOcr, isTrue);
      expect(result.hasUsableText, isFalse);
    });

    test('marks a scanned PDF as requiring local OCR without an adapter',
        () async {
      final result = await PayrollStatementExtractionService().extract(
        bytes: _blankPdfBytes(pageCount: 2),
        filename: 'cartola-escaneada.pdf',
      );

      expect(result.inputKind, PayrollStatementInputKind.pdf);
      expect(result.method, PayrollStatementExtractionMethod.imageOcrRequired);
      expect(result.pages.map((page) => page.pageNumber), <int>[1, 2]);
      expect(result.warnings.single, contains('Android o iPhone'));
    });

    test('rasterizes and OCRs every scanned PDF page locally in order',
        () async {
      final rasterRequests = <List<int>>[];
      final ocrFilenames = <String>[];
      final ocrSourcePaths = <String?>[];
      final progress = <PayrollStatementPreparationProgress>[];
      var page = 0;
      final service = PayrollStatementExtractionService(
        imageTextExtractor: ({
          required bytes,
          required filename,
          sourcePath,
        }) async {
          ocrFilenames.add(filename);
          ocrSourcePaths.add(sourcePath);
          page += 1;
          return 'Página $page Fecha Descripción Cargos Abonos Saldo\n'
              '27/07/2026 Transferencia a Persona $page 128.000 0 900.000';
        },
        pdfPageRasterizer: ({
          required bytes,
          required pages,
        }) {
          rasterRequests.add(List<int>.from(pages));
          return Stream<Uint8List>.fromIterable(
            pages.map(
              (index) => Uint8List.fromList(<int>[
                0x89,
                0x50,
                0x4E,
                0x47,
                index,
              ]),
            ),
          );
        },
      );

      final result = await service.extract(
        bytes: _blankPdfBytes(pageCount: 2),
        filename: 'cartola julio.pdf',
        onProgress: progress.add,
      );

      expect(
        result.method,
        PayrollStatementExtractionMethod.onDeviceImageOcr,
      );
      expect(result.inputKind, PayrollStatementInputKind.pdf);
      expect(result.pages.map((item) => item.pageNumber), <int>[1, 2]);
      expect(result.pages[0].text, contains('Persona 1'));
      expect(result.pages[1].text, contains('Persona 2'));
      expect(rasterRequests, <List<int>>[
        <int>[0, 1],
      ]);
      expect(
        ocrFilenames,
        <String>[
          'cartola_julio_pdf_pagina_1.png',
          'cartola_julio_pdf_pagina_2.png',
        ],
      );
      expect(ocrSourcePaths, <String?>[null, null]);
      expect(result.warnings.single, contains('no se enviaron'));
      expect(
        progress
            .where(
              (event) =>
                  event.phase ==
                  PayrollStatementPreparationPhase.recognizingPdfPage,
            )
            .map((event) => '${event.pageNumber}/${event.pageCount}'),
        <String>['1/2', '2/2'],
      );
      expect(
        progress.map((event) => event.phase),
        contains(PayrollStatementPreparationPhase.preparingScannedPdf),
      );
    });

    test('OCRs every page when a hybrid PDF has one unreadable page', () async {
      final rasterRequests = <List<int>>[];
      var recognizedPage = 0;
      final service = PayrollStatementExtractionService(
        imageTextExtractor: ({
          required bytes,
          required filename,
          sourcePath,
        }) async {
          recognizedPage += 1;
          return 'Página $recognizedPage Fecha Descripción Cargos Abonos Saldo\n'
              '27/07/2026 Transferencia Persona $recognizedPage 128.000 0 900.000';
        },
        pdfPageRasterizer: ({
          required bytes,
          required pages,
        }) {
          rasterRequests.add(List<int>.from(pages));
          return Stream<Uint8List>.fromIterable(
            pages.map((index) => Uint8List.fromList(<int>[0x89, index])),
          );
        },
      );

      final result = await service.extract(
        bytes: _hybridPdfBytes(),
        filename: 'cartola-hibrida.pdf',
      );

      expect(
        result.method,
        PayrollStatementExtractionMethod.onDeviceImageOcr,
      );
      expect(result.pages, hasLength(2));
      expect(rasterRequests, <List<int>>[
        <int>[0, 1],
      ]);
    });

    test('reports scanned PDF OCR as required when raster is unsupported',
        () async {
      final service = PayrollStatementExtractionService(
        imageTextExtractor: ({
          required bytes,
          required filename,
          sourcePath,
        }) async =>
            'unused',
        pdfPageRasterizer: ({
          required bytes,
          required pages,
        }) async* {
          throw UnsupportedError('not available');
        },
      );

      final result = await service.extract(
        bytes: _blankPdfBytes(pageCount: 1),
        filename: 'cartola-escaneada.pdf',
      );

      expect(result.method, PayrollStatementExtractionMethod.imageOcrRequired);
      expect(result.warnings.single, contains('no puede convertir'));
    });

    test('uses an injected on-device image extractor', () async {
      final service = PayrollStatementExtractionService(
        imageTextExtractor: ({
          required bytes,
          required filename,
          sourcePath,
        }) async =>
            'Fecha Descripción Cargos Abonos Saldo\n'
            '27/07/2026 App-traspaso A: Persona Ejemplo 128.000 0 900.000',
      );

      final result = await service.extract(
        bytes: Uint8List.fromList(<int>[
          0xFF,
          0xD8,
          0xFF,
          ...List<int>.filled(80, 0),
        ]),
        filename: 'foto.jpg',
        sourcePath: '/temporary/foto.jpg',
      );

      expect(
        result.method,
        PayrollStatementExtractionMethod.onDeviceImageOcr,
      );
      expect(result.parserInput, contains('Persona Ejemplo'));
    });

    test('rejects extension-only files with invalid magic bytes', () async {
      expect(
        () => PayrollStatementExtractionService().extract(
          bytes: Uint8List.fromList('not a pdf'.codeUnits),
          filename: 'cartola.pdf',
        ),
        throwsA(isA<PayrollStatementExtractionException>()),
      );
    });

    test('rejects oversized input before attempting extraction', () async {
      final bytes = Uint8List(
        PayrollStatementExtractionService.maxFileBytes + 1,
      );

      expect(
        () => PayrollStatementExtractionService().extract(
          bytes: bytes,
          filename: 'cartola.pdf',
        ),
        throwsA(
          isA<PayrollStatementExtractionException>().having(
            (error) => error.message,
            'message',
            contains('12 MB'),
          ),
        ),
      );
    });
  });
}

Uint8List _syntheticPdfBytes(String text) {
  final document = PdfDocument();
  final page = document.pages.add();
  page.graphics.drawString(
    text,
    PdfStandardFont(PdfFontFamily.helvetica, 11),
    bounds: const Rect.fromLTWH(20, 20, 500, 700),
  );
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

Uint8List _blankPdfBytes({required int pageCount}) {
  final document = PdfDocument();
  for (var index = 0; index < pageCount; index++) {
    document.pages.add();
  }
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

Uint8List _hybridPdfBytes() {
  final document = PdfDocument();
  final firstPage = document.pages.add();
  firstPage.graphics.drawString(
    'Cartola bancaria con encabezado digital y bastante texto seleccionable '
    'que no debe ocultar una segunda página escaneada.',
    PdfStandardFont(PdfFontFamily.helvetica, 11),
    bounds: const Rect.fromLTWH(20, 20, 500, 700),
  );
  document.pages.add();
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

Uint8List _positionedStatementPdfBytes() {
  final document = PdfDocument();
  final font = PdfStandardFont(PdfFontFamily.helvetica, 9);

  void drawCell(PdfPage page, String text, double x, double y) {
    page.graphics.drawString(
      text,
      font,
      bounds: Rect.fromLTWH(x, y, 160, 16),
    );
  }

  final firstPage = document.pages.add();
  drawCell(firstPage, 'Fecha', 20, 20);
  drawCell(firstPage, 'Descripción', 80, 20);
  drawCell(firstPage, 'Nro. Docto.', 300, 20);
  drawCell(firstPage, 'Cargos', 355, 20);
  drawCell(firstPage, 'Abonos', 425, 20);
  drawCell(firstPage, 'Saldo', 500, 20);

  drawCell(firstPage, '26/06/2026', 20, 60);
  drawCell(firstPage, 'Pago: Abonos Transbank', 80, 60);
  drawCell(firstPage, '13.754', 425, 60);
  drawCell(firstPage, '425.126', 500, 60);

  // The bank renderer placed these cells at the end of page one even though
  // their date and description begin page two.
  drawCell(firstPage, '6.000', 425, 760);
  drawCell(firstPage, '411.372', 500, 760);

  final secondPage = document.pages.add();
  drawCell(secondPage, '25/06/2026', 20, 20);
  drawCell(secondPage, 'Traspaso De: Persona Ejemplo', 80, 20);

  drawCell(secondPage, '25/06/2026', 20, 60);
  drawCell(secondPage, 'Cargo pequeño', 80, 60);
  drawCell(secondPage, '86', 355, 60);
  drawCell(secondPage, '411.286', 500, 60);

  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}
