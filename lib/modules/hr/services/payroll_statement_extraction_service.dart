import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

typedef PayrollStatementImageTextExtractor = Future<String> Function({
  required Uint8List bytes,
  required String filename,
  String? sourcePath,
});

typedef PayrollStatementPdfPageRasterizer = Stream<Uint8List> Function({
  required Uint8List bytes,
  required List<int> pages,
});

enum PayrollStatementInputKind {
  pdf,
  image,
}

enum PayrollStatementExtractionMethod {
  embeddedPdfText,
  onDeviceImageOcr,
  imageOcrRequired,
}

enum PayrollStatementPreparationPhase {
  validatingFile,
  readingPdfPage,
  preparingScannedPdf,
  recognizingPdfPage,
  recognizingImage,
  parsingMovements,
  loadingPayrollContext,
}

class PayrollStatementPreparationProgress {
  const PayrollStatementPreparationProgress({
    required this.phase,
    this.pageNumber,
    this.pageCount,
  });

  final PayrollStatementPreparationPhase phase;
  final int? pageNumber;
  final int? pageCount;

  double? get fraction {
    final current = pageNumber;
    final total = pageCount;
    if (current == null || total == null || total <= 0) return null;
    return (current / total).clamp(0, 1);
  }
}

typedef PayrollStatementPreparationProgressCallback = void Function(
  PayrollStatementPreparationProgress progress,
);

class PayrollStatementPageText {
  const PayrollStatementPageText({
    required this.pageNumber,
    required this.text,
  });

  final int pageNumber;
  final String text;
}

class PayrollStatementExtractionResult {
  const PayrollStatementExtractionResult({
    required this.fileSha256,
    required this.inputKind,
    required this.method,
    required this.pages,
    this.warnings = const <String>[],
  });

  final String fileSha256;
  final PayrollStatementInputKind inputKind;
  final PayrollStatementExtractionMethod method;
  final List<PayrollStatementPageText> pages;
  final List<String> warnings;

  bool get needsImageOcr =>
      method == PayrollStatementExtractionMethod.imageOcrRequired;

  bool get hasUsableText => pages.any((page) => page.text.trim().isNotEmpty);

  /// Keeps page boundaries explicit for parsers without logging or persisting
  /// the document's raw text.
  String get parserInput => pages
      .map(
        (page) => '[[PAYROLL_STATEMENT_PAGE:${page.pageNumber}]]\n${page.text}',
      )
      .join('\n');
}

class PayrollStatementExtractionException implements Exception {
  const PayrollStatementExtractionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Extracts bank-statement text in memory.
///
/// Raw statements are deliberately not uploaded, persisted, or printed here.
/// Digital PDFs are parsed locally first. Image OCR is injected so each
/// platform can use an on-device implementation without coupling this service
/// to an invoice OCR provider.
class PayrollStatementExtractionService {
  PayrollStatementExtractionService({
    PayrollStatementImageTextExtractor? imageTextExtractor,
    PayrollStatementPdfPageRasterizer? pdfPageRasterizer,
  })  : _imageTextExtractor = imageTextExtractor,
        _pdfPageRasterizer = pdfPageRasterizer ?? _rasterizePdfPagesOnDevice;

  static const int maxFileBytes = 12 * 1024 * 1024;
  static const int maxPdfPages = 40;
  static const int _minimumUsefulCharacters = 50;
  static const int _minimumUsefulCharactersPerPage = 20;

  final PayrollStatementImageTextExtractor? _imageTextExtractor;
  final PayrollStatementPdfPageRasterizer _pdfPageRasterizer;

  Future<PayrollStatementExtractionResult> extract({
    required Uint8List bytes,
    required String filename,
    String? sourcePath,
    bool forceImageOcrForPdf = false,
    PayrollStatementPreparationProgressCallback? onProgress,
  }) async {
    onProgress?.call(
      const PayrollStatementPreparationProgress(
        phase: PayrollStatementPreparationPhase.validatingFile,
      ),
    );
    _validateSize(bytes);

    if (_looksLikePdf(bytes)) {
      return _extractPdf(
        bytes,
        filename: filename,
        forceImageOcr: forceImageOcrForPdf,
        onProgress: onProgress,
      );
    }
    if (_looksLikeSupportedImage(bytes)) {
      return _extractImage(
        bytes: bytes,
        filename: filename,
        sourcePath: sourcePath,
        onProgress: onProgress,
      );
    }

    throw const PayrollStatementExtractionException(
      'El archivo no es un PDF, JPG, PNG o WebP válido.',
    );
  }

  Future<PayrollStatementExtractionResult> _extractPdf(
    Uint8List bytes, {
    required String filename,
    required bool forceImageOcr,
    PayrollStatementPreparationProgressCallback? onProgress,
  }) async {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final pageCount = document.pages.count;
      if (pageCount < 1) {
        throw const PayrollStatementExtractionException(
          'El PDF no contiene páginas.',
        );
      }
      if (pageCount > maxPdfPages) {
        throw const PayrollStatementExtractionException(
          'La cartola supera el máximo de 40 páginas.',
        );
      }

      final extractor = PdfTextExtractor(document);
      final pages = <PayrollStatementPageText>[];
      final pageBands = <List<_PositionedTextBand>>[];
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        onProgress?.call(
          PayrollStatementPreparationProgress(
            phase: PayrollStatementPreparationPhase.readingPdfPage,
            pageNumber: pageIndex + 1,
            pageCount: pageCount,
          ),
        );
        // Give the mounted workflow a frame between pages without changing
        // extraction ownership or persisting any source content.
        await Future<void>.delayed(Duration.zero);
        pageBands.add(_extractPositionedPageBands(extractor, pageIndex));
      }
      final repairedPageBreakRows = _repairCrossPageRows(pageBands);
      var usefulCharacters = 0;
      final usefulCharactersByPage = <int>[];

      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        final text = pageBands[pageIndex]
            .map((band) => band.render())
            .where((line) => line.trim().isNotEmpty)
            .join('\n');
        final pageUsefulCharacters = text.replaceAll(RegExp(r'\s'), '').length;
        usefulCharacters += pageUsefulCharacters;
        usefulCharactersByPage.add(pageUsefulCharacters);
        pages.add(
          PayrollStatementPageText(
            pageNumber: pageIndex + 1,
            text: text,
          ),
        );
      }

      final hasUnreadableEmbeddedPage = pageCount > 1 &&
          usefulCharactersByPage.any(
            (count) => count < _minimumUsefulCharactersPerPage,
          );
      if (forceImageOcr ||
          usefulCharacters < _minimumUsefulCharacters ||
          hasUnreadableEmbeddedPage) {
        return _extractScannedPdf(
          bytes: bytes,
          filename: filename,
          pageCount: pageCount,
          embeddedPages: pages,
          onProgress: onProgress,
        );
      }

      return PayrollStatementExtractionResult(
        fileSha256: sha256.convert(bytes).toString(),
        inputKind: PayrollStatementInputKind.pdf,
        method: PayrollStatementExtractionMethod.embeddedPdfText,
        pages: pages,
        warnings: <String>[
          if (repairedPageBreakRows > 0)
            'Se recompusieron $repairedPageBreakRows movimientos divididos '
                'por un salto de página.',
        ],
      );
    } on PayrollStatementExtractionException {
      rethrow;
    } catch (_) {
      throw const PayrollStatementExtractionException(
        'No se pudo leer el PDF. Puede estar dañado o protegido.',
      );
    } finally {
      document?.dispose();
    }
  }

  Future<PayrollStatementExtractionResult> _extractScannedPdf({
    required Uint8List bytes,
    required String filename,
    required int pageCount,
    required List<PayrollStatementPageText> embeddedPages,
    PayrollStatementPreparationProgressCallback? onProgress,
  }) async {
    final imageExtractor = _imageTextExtractor;
    if (imageExtractor == null) {
      return _imageOcrRequiredPdfResult(
        bytes: bytes,
        pages: embeddedPages,
        warning:
            'El PDF parece escaneado y necesita reconocimiento local de imagen, '
            'disponible en Android o iPhone.',
      );
    }

    final pageIndexes = List<int>.generate(pageCount, (index) => index);
    final ocrPages = <PayrollStatementPageText>[];
    var usefulCharacters = 0;

    try {
      var pageIndex = 0;
      onProgress?.call(
        PayrollStatementPreparationProgress(
          phase: PayrollStatementPreparationPhase.preparingScannedPdf,
          pageCount: pageCount,
        ),
      );
      await for (final rasterBytes in _pdfPageRasterizer(
        bytes: bytes,
        pages: pageIndexes,
      )) {
        if (pageIndex >= pageCount) {
          throw const PayrollStatementExtractionException(
            'No se pudo convertir el PDF escaneado de forma segura.',
          );
        }
        onProgress?.call(
          PayrollStatementPreparationProgress(
            phase: PayrollStatementPreparationPhase.recognizingPdfPage,
            pageNumber: pageIndex + 1,
            pageCount: pageCount,
          ),
        );
        final text = await imageExtractor(
          bytes: rasterBytes,
          filename: _rasterPageFilename(filename, pageIndex + 1),
        );
        usefulCharacters += text.replaceAll(RegExp(r'\s'), '').length;
        ocrPages.add(
          PayrollStatementPageText(
            pageNumber: pageIndex + 1,
            text: text,
          ),
        );
        pageIndex += 1;
      }

      if (ocrPages.length != pageCount) {
        throw const PayrollStatementExtractionException(
          'No se pudieron convertir todas las páginas del PDF escaneado.',
        );
      }
    } on UnsupportedError {
      return _imageOcrRequiredPdfResult(
        bytes: bytes,
        pages: embeddedPages,
        warning:
            'Este dispositivo no puede convertir el PDF escaneado para OCR '
            'local. Usa Android o iPhone, o una cartola con texto seleccionable.',
      );
    } on PayrollStatementExtractionException {
      rethrow;
    } catch (_) {
      throw const PayrollStatementExtractionException(
        'No se pudo reconocer el PDF escaneado localmente.',
      );
    }

    if (usefulCharacters < _minimumUsefulCharacters) {
      throw const PayrollStatementExtractionException(
        'No se pudo reconocer suficiente texto en el PDF escaneado.',
      );
    }

    return PayrollStatementExtractionResult(
      fileSha256: sha256.convert(bytes).toString(),
      inputKind: PayrollStatementInputKind.pdf,
      method: PayrollStatementExtractionMethod.onDeviceImageOcr,
      pages: ocrPages,
      warnings: const <String>[
        'El PDF escaneado se reconoció localmente en el dispositivo. '
            'Sus imágenes temporales no se enviaron ni se conservaron.',
      ],
    );
  }

  PayrollStatementExtractionResult _imageOcrRequiredPdfResult({
    required Uint8List bytes,
    required List<PayrollStatementPageText> pages,
    required String warning,
  }) {
    return PayrollStatementExtractionResult(
      fileSha256: sha256.convert(bytes).toString(),
      inputKind: PayrollStatementInputKind.pdf,
      method: PayrollStatementExtractionMethod.imageOcrRequired,
      pages: pages,
      warnings: <String>[warning],
    );
  }

  static Stream<Uint8List> _rasterizePdfPagesOnDevice({
    required Uint8List bytes,
    required List<int> pages,
  }) async* {
    final printingInfo = await Printing.info();
    if (!printingInfo.canRaster) {
      throw UnsupportedError(
        'La conversión local de PDF a imagen no está disponible.',
      );
    }

    await for (final page in Printing.raster(
      bytes,
      pages: pages,
      dpi: 200,
    )) {
      yield await page.toPng();
    }
  }

  String _rasterPageFilename(String filename, int pageNumber) {
    final baseName = filename
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return '${baseName.isEmpty ? 'cartola' : baseName}'
        '_pagina_$pageNumber.png';
  }

  Future<PayrollStatementExtractionResult> _extractImage({
    required Uint8List bytes,
    required String filename,
    String? sourcePath,
    PayrollStatementPreparationProgressCallback? onProgress,
  }) async {
    final extractor = _imageTextExtractor;
    if (extractor == null) {
      return PayrollStatementExtractionResult(
        fileSha256: sha256.convert(bytes).toString(),
        inputKind: PayrollStatementInputKind.image,
        method: PayrollStatementExtractionMethod.imageOcrRequired,
        pages: const <PayrollStatementPageText>[],
        warnings: const <String>[
          'El reconocimiento local de imágenes no está disponible en este dispositivo.',
        ],
      );
    }

    onProgress?.call(
      const PayrollStatementPreparationProgress(
        phase: PayrollStatementPreparationPhase.recognizingImage,
        pageNumber: 1,
        pageCount: 1,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final text = await extractor(
      bytes: bytes,
      filename: filename,
      sourcePath: sourcePath,
    );
    if (text.replaceAll(RegExp(r'\s'), '').length < _minimumUsefulCharacters) {
      throw const PayrollStatementExtractionException(
        'No se pudo reconocer suficiente texto en la imagen.',
      );
    }

    return PayrollStatementExtractionResult(
      fileSha256: sha256.convert(bytes).toString(),
      inputKind: PayrollStatementInputKind.image,
      method: PayrollStatementExtractionMethod.onDeviceImageOcr,
      pages: <PayrollStatementPageText>[
        PayrollStatementPageText(pageNumber: 1, text: text),
      ],
    );
  }

  void _validateSize(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const PayrollStatementExtractionException(
        'El archivo está vacío.',
      );
    }
    if (bytes.length > maxFileBytes) {
      throw const PayrollStatementExtractionException(
        'El archivo supera el máximo de 12 MB.',
      );
    }
  }

  bool _looksLikePdf(Uint8List bytes) {
    return bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;
  }

  bool _looksLikeSupportedImage(Uint8List bytes) {
    final isJpeg = bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF;
    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A;
    final isWebp = bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50;
    return isJpeg || isPng || isWebp;
  }

  List<_PositionedTextBand> _extractPositionedPageBands(
    PdfTextExtractor extractor,
    int pageIndex,
  ) {
    final textLines = extractor
        .extractTextLines(
          startPageIndex: pageIndex,
          endPageIndex: pageIndex,
        )
        .toList()
      ..sort((left, right) {
        final topComparison = left.bounds.top.compareTo(right.bounds.top);
        return topComparison != 0
            ? topComparison
            : left.bounds.left.compareTo(right.bounds.left);
      });

    final bands = <_PositionedTextBand>[];
    for (final line in textLines) {
      if (line.text.trim().isEmpty) continue;
      final tokens = line.wordCollection
          .where((word) => word.text.trim().isNotEmpty)
          .map(
            (word) => _PositionedTextToken(
              text: word.text.trim(),
              left: word.bounds.left,
            ),
          )
          .toList(growable: false);
      if (tokens.isEmpty) continue;

      final canJoinLast = bands.isNotEmpty &&
          line.bounds.top < bands.last.bottom - 0.5 &&
          line.bounds.bottom > bands.last.top + 0.5;
      if (canJoinLast) {
        bands.last.add(
          top: line.bounds.top,
          bottom: line.bounds.bottom,
          tokens: tokens,
        );
      } else {
        bands.add(
          _PositionedTextBand(
            top: line.bounds.top,
            bottom: line.bounds.bottom,
            tokens: tokens,
          ),
        );
      }
    }

    return bands;
  }

  int _repairCrossPageRows(List<List<_PositionedTextBand>> pages) {
    var repaired = 0;
    for (var pageIndex = 0; pageIndex + 1 < pages.length; pageIndex++) {
      final current = pages[pageIndex];
      final next = pages[pageIndex + 1];
      final orphanIndex = current.lastIndexWhere(
        (band) => band.isNumericOnlyMovementTail,
      );
      final nextRowIndex = next.indexWhere((band) => band.hasLeadingDate);
      if (orphanIndex < 0 || nextRowIndex < 0) continue;

      final nextRow = next[nextRowIndex];
      if (nextRow.hasMovementAmount) continue;

      final orphan = current.removeAt(orphanIndex);
      nextRow.absorbTokens(orphan.tokens);
      repaired += 1;
    }
    return repaired;
  }
}

class _PositionedTextToken {
  const _PositionedTextToken({
    required this.text,
    required this.left,
  });

  final String text;
  final double left;
}

class _PositionedTextBand {
  _PositionedTextBand({
    required this.top,
    required this.bottom,
    required List<_PositionedTextToken> tokens,
  }) : tokens = List<_PositionedTextToken>.from(tokens);

  double top;
  double bottom;
  final List<_PositionedTextToken> tokens;

  bool get hasLeadingDate {
    return RegExp(r'^\s*\d{1,2}\s*[/.-]\s*\d{1,2}\s*[/.-]\s*\d{2,4}')
        .hasMatch(render());
  }

  bool get hasMovementAmount {
    return tokens.any(
      (token) => token.left >= 350 && _looksLikePositionedAmount(token.text),
    );
  }

  bool get isNumericOnlyMovementTail {
    final visible = tokens.where((token) => token.text.trim().isNotEmpty);
    return visible.length >= 2 &&
        visible.every(
          (token) =>
              token.left >= 350 && _looksLikePositionedAmount(token.text),
        );
  }

  void add({
    required double top,
    required double bottom,
    required List<_PositionedTextToken> tokens,
  }) {
    if (top < this.top) this.top = top;
    if (bottom > this.bottom) this.bottom = bottom;
    this.tokens.addAll(tokens);
  }

  void absorbTokens(Iterable<_PositionedTextToken> other) {
    tokens.addAll(other);
  }

  String render() {
    tokens.sort((left, right) => left.left.compareTo(right.left));
    const pointsPerColumn = 2.0;
    final characters = <String>[];
    var occupiedThrough = -1;

    for (final token in tokens) {
      var start = (token.left / pointsPerColumn).round();
      if (start <= occupiedThrough) start = occupiedThrough + 1;
      while (characters.length < start) {
        characters.add(' ');
      }
      for (final character in token.text.runes) {
        characters.add(String.fromCharCode(character));
      }
      occupiedThrough = characters.length - 1;
    }
    return characters.join().trimRight();
  }
}

bool _looksLikePositionedAmount(String value) {
  return RegExp(r'^(?:-|\d{1,3}(?:\.\d{3})*|\d+)$').hasMatch(value.trim());
}
