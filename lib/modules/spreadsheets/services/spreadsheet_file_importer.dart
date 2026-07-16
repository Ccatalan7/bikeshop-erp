import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import 'univer_workbook_adapter.dart';

/// A workbook snapshot decoded from a file before it is persisted.
class ImportedSpreadsheetWorkbook {
  const ImportedSpreadsheetWorkbook({
    required this.name,
    required this.workbookData,
    required this.rowCount,
    required this.colCount,
  });

  final String name;
  final Map<String, dynamic> workbookData;
  final int rowCount;
  final int colCount;
}

class UnsupportedSpreadsheetFileException implements Exception {
  const UnsupportedSpreadsheetFileException(this.extension);

  final String extension;

  @override
  String toString() => extension == 'xls'
      ? 'El formato .xls antiguo no es compatible. Convierte el archivo a .xlsx.'
      : 'El formato .$extension no se puede abrir en Planillas.';
}

/// Converts local XLSX and CSV files into the same versioned Univer snapshot
/// used by the native and web spreadsheet editors.
class SpreadsheetFileImporter {
  const SpreadsheetFileImporter._();

  static const supportedExtensions = <String>{'xlsx', 'csv'};

  static bool supportsExtension(String extension) =>
      supportedExtensions.contains(extension.trim().toLowerCase());

  static ImportedSpreadsheetWorkbook decode({
    required Uint8List bytes,
    required String fileName,
  }) {
    if (bytes.isEmpty) {
      throw const FormatException('El archivo está vacío.');
    }

    final extension = _extensionOf(fileName);
    if (!supportsExtension(extension)) {
      throw UnsupportedSpreadsheetFileException(extension);
    }

    return switch (extension) {
      'xlsx' => _decodeXlsx(bytes, fileName),
      'csv' => _decodeCsv(bytes, fileName),
      _ => throw UnsupportedSpreadsheetFileException(extension),
    };
  }

  static ImportedSpreadsheetWorkbook _decodeXlsx(
    Uint8List bytes,
    String fileName,
  ) {
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes, skipEmptyStyledCells: true);
    } on UnsupportedError {
      rethrow;
    } catch (error) {
      throw FormatException('No se pudo leer el archivo XLSX: $error');
    }

    if (excel.sheets.isEmpty) {
      throw const FormatException('El archivo XLSX no contiene hojas.');
    }

    final sheets = <String, dynamic>{};
    final sheetOrder = <String>[];
    var workbookRows = 1;
    var workbookColumns = 1;
    var sheetNumber = 0;

    for (final entry in excel.sheets.entries) {
      sheetNumber++;
      final sheetId = 'sheet-$sheetNumber';
      final sheet = entry.value;
      final rowCount = math.max(100, sheet.maxRows);
      final columnCount = math.max(26, sheet.maxColumns);
      workbookRows = math.max(workbookRows, sheet.maxRows);
      workbookColumns = math.max(workbookColumns, sheet.maxColumns);

      final cellData = <String, dynamic>{};
      for (final row in sheet.rows) {
        for (final cell in row) {
          if (cell == null) continue;
          final converted = _xlsxCell(cell);
          if (converted == null) continue;
          final outputRow = cellData.putIfAbsent(
            '${cell.rowIndex}',
            () => <String, dynamic>{},
          ) as Map<String, dynamic>;
          outputRow['${cell.columnIndex}'] = converted;
        }
      }

      final mergeData = <Map<String, int>>[];
      for (final range in sheet.spannedItems) {
        final parts = range.split(':');
        if (parts.length != 2) continue;
        final start = CellIndex.indexByString(parts.first);
        final end = CellIndex.indexByString(parts.last);
        mergeData.add({
          'startRow': start.rowIndex,
          'endRow': end.rowIndex,
          'startColumn': start.columnIndex,
          'endColumn': end.columnIndex,
        });
      }

      final rowData = <String, dynamic>{
        for (final entry in sheet.getRowHeights.entries)
          '${entry.key}': <String, dynamic>{'h': _pointsToPixels(entry.value)},
      };
      final columnData = <String, dynamic>{
        for (final entry in sheet.getColumnWidths.entries)
          '${entry.key}': <String, dynamic>{
            'w': _excelColumnWidthToPixels(entry.value),
          },
      };

      sheetOrder.add(sheetId);
      sheets[sheetId] = <String, dynamic>{
        'id': sheetId,
        'name': entry.key,
        'rowCount': rowCount,
        'columnCount': columnCount,
        'defaultColumnWidth': sheet.defaultColumnWidth == null
            ? 100
            : _excelColumnWidthToPixels(sheet.defaultColumnWidth!),
        'defaultRowHeight': sheet.defaultRowHeight == null
            ? 24
            : _pointsToPixels(sheet.defaultRowHeight!),
        'mergeData': mergeData,
        'cellData': cellData,
        'rowData': rowData,
        'columnData': columnData,
      };
    }

    final name = _workbookName(fileName);
    return ImportedSpreadsheetWorkbook(
      name: name,
      rowCount: math.max(1, workbookRows),
      colCount: math.max(1, workbookColumns),
      workbookData: <String, dynamic>{
        'id': 'pending-import',
        'name': name,
        'appVersion': UniverWorkbookAdapter.engineVersion,
        'locale': 'esES',
        'styles': <String, dynamic>{},
        'sheetOrder': sheetOrder,
        'sheets': sheets,
      },
    );
  }

  static ImportedSpreadsheetWorkbook _decodeCsv(
    Uint8List bytes,
    String fileName,
  ) {
    final content = utf8
        .decode(bytes, allowMalformed: true)
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final delimiter = _detectDelimiter(content);
    final rows = CsvToListConverter(
      fieldDelimiter: delimiter,
      eol: '\n',
      shouldParseNumbers: true,
    ).convert(content);

    final cellData = <String, dynamic>{};
    var maxColumns = 0;
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final inputRow = rows[rowIndex];
      maxColumns = math.max(maxColumns, inputRow.length);
      for (var columnIndex = 0; columnIndex < inputRow.length; columnIndex++) {
        final value = inputRow[columnIndex];
        if (value == null || value == '') continue;
        final outputRow = cellData.putIfAbsent(
          '$rowIndex',
          () => <String, dynamic>{},
        ) as Map<String, dynamic>;
        outputRow['$columnIndex'] = _primitiveCell(value);
      }
    }

    final name = _workbookName(fileName);
    return ImportedSpreadsheetWorkbook(
      name: name,
      rowCount: math.max(1, rows.length),
      colCount: math.max(1, maxColumns),
      workbookData: <String, dynamic>{
        'id': 'pending-import',
        'name': name,
        'appVersion': UniverWorkbookAdapter.engineVersion,
        'locale': 'esES',
        'styles': <String, dynamic>{},
        'sheetOrder': const <String>['sheet-1'],
        'sheets': <String, dynamic>{
          'sheet-1': <String, dynamic>{
            'id': 'sheet-1',
            'name': 'Hoja 1',
            'rowCount': math.max(100, rows.length),
            'columnCount': math.max(26, maxColumns),
            'defaultColumnWidth': 100,
            'defaultRowHeight': 24,
            'mergeData': const <dynamic>[],
            'cellData': cellData,
            'rowData': const <String, dynamic>{},
            'columnData': const <String, dynamic>{},
          },
        },
      },
    );
  }

  static Map<String, dynamic>? _xlsxCell(Data cell) {
    final value = cell.value;
    // Supplier workbooks often pre-format tens of thousands of otherwise empty
    // cells. Materializing those style-only cells produces multi-megabyte
    // snapshots and can make a small XLSX appear to import forever. Preserve
    // styles on real values/formulas; sizing and merges remain sheet metadata.
    if (value == null) return null;

    final style = _xlsxStyle(cell.cellStyle);

    final output = <String, dynamic>{
      if (style.isNotEmpty) 's': style,
    };
    switch (value) {
      case FormulaCellValue(:final formula):
        output['f'] = formula.startsWith('=') ? formula : '=$formula';
      case IntCellValue(:final value):
        output
          ..['v'] = value
          ..['t'] = 2;
      case DoubleCellValue(:final value):
        output
          ..['v'] = value
          ..['t'] = 2;
      case BoolCellValue(:final value):
        output
          ..['v'] = value
          ..['t'] = 3;
      case TextCellValue(:final value):
        output
          ..['v'] = value.toString()
          ..['t'] = 1;
      case DateCellValue():
        output
          ..['v'] = _excelDateSerial(value.asDateTimeUtc())
          ..['t'] = 2;
      case DateTimeCellValue():
        output
          ..['v'] = _excelDateSerial(value.asDateTimeUtc())
          ..['t'] = 2;
      case TimeCellValue():
        output
          ..['v'] = value.asDuration().inMicroseconds /
              const Duration(days: 1).inMicroseconds
          ..['t'] = 2;
    }
    return output;
  }

  static Map<String, dynamic> _primitiveCell(Object value) {
    if (value is num) return <String, dynamic>{'v': value, 't': 2};
    if (value is bool) return <String, dynamic>{'v': value, 't': 3};
    return <String, dynamic>{'v': value.toString(), 't': 1};
  }

  static Map<String, dynamic> _xlsxStyle(CellStyle? style) {
    if (style == null) return const <String, dynamic>{};

    final fontColor = _univerColor(style.fontColor.colorHex);
    final backgroundColor = _univerColor(style.backgroundColor.colorHex);
    final numberFormat = style.numberFormat.formatCode;
    final borders = <String, dynamic>{
      if (_univerBorder(style.topBorder) case final value?) 't': value,
      if (_univerBorder(style.rightBorder) case final value?) 'r': value,
      if (_univerBorder(style.bottomBorder) case final value?) 'b': value,
      if (_univerBorder(style.leftBorder) case final value?) 'l': value,
    };

    return <String, dynamic>{
      if (style.isBold) 'bl': 1,
      if (style.isItalic) 'it': 1,
      if (style.underline != Underline.None) 'ul': <String, dynamic>{'s': 1},
      if (style.fontFamily?.trim().isNotEmpty == true) 'ff': style.fontFamily,
      if (style.fontSize != null && style.fontSize != 12) 'fs': style.fontSize,
      if (fontColor != null && fontColor != '#000000')
        'cl': <String, dynamic>{'rgb': fontColor},
      if (backgroundColor != null)
        'bg': <String, dynamic>{'rgb': backgroundColor},
      if (style.horizontalAlignment != HorizontalAlign.Left)
        'ht': switch (style.horizontalAlignment) {
          HorizontalAlign.Left => 1,
          HorizontalAlign.Center => 2,
          HorizontalAlign.Right => 3,
        },
      if (style.verticalAlignment != VerticalAlign.Bottom)
        'vt': switch (style.verticalAlignment) {
          VerticalAlign.Top => 1,
          VerticalAlign.Center => 2,
          VerticalAlign.Bottom => 3,
        },
      if (style.wrap != null) 'tb': style.wrap == TextWrapping.WrapText ? 3 : 2,
      if (style.rotation != 0) 'tr': <String, dynamic>{'a': style.rotation},
      if (numberFormat != 'General')
        'n': <String, dynamic>{'pattern': numberFormat},
      if (borders.isNotEmpty) 'bd': borders,
    };
  }

  static Map<String, dynamic>? _univerBorder(Border border) {
    final style = border.borderStyle;
    if (style == null || style == BorderStyle.None) return null;
    final color = _univerColor(border.borderColorHex ?? 'FF000000');
    return <String, dynamic>{
      's': switch (style) {
        BorderStyle.Thin => 1,
        BorderStyle.Hair => 2,
        BorderStyle.Dotted => 3,
        BorderStyle.Dashed => 4,
        BorderStyle.DashDot => 5,
        BorderStyle.DashDotDot => 6,
        BorderStyle.Double => 7,
        BorderStyle.Medium => 8,
        BorderStyle.MediumDashed => 9,
        BorderStyle.MediumDashDot => 10,
        BorderStyle.MediumDashDotDot => 11,
        BorderStyle.SlantDashDot => 12,
        BorderStyle.Thick => 13,
        BorderStyle.None => 0,
      },
      if (color != null) 'cl': <String, dynamic>{'rgb': color},
    };
  }

  static String? _univerColor(String value) {
    final normalized = value.replaceAll('#', '').trim().toUpperCase();
    if (normalized == 'NONE' || normalized.isEmpty) return null;
    final rgb = normalized.length == 8 ? normalized.substring(2) : normalized;
    if (rgb.length != 6) return null;
    return '#$rgb';
  }

  static double _excelDateSerial(DateTime value) {
    final utc = value.toUtc();
    final epoch = DateTime.utc(1899, 12, 30);
    return utc.difference(epoch).inMicroseconds /
        const Duration(days: 1).inMicroseconds;
  }

  static double _pointsToPixels(double points) => points * 96 / 72;

  static double _excelColumnWidthToPixels(double width) =>
      math.max(12, width * 7 + 5);

  static String _detectDelimiter(String content) {
    final firstLine = content.split(RegExp(r'\r?\n')).first;
    final counts = <String, int>{
      ',': _countOutsideQuotes(firstLine, ','),
      ';': _countOutsideQuotes(firstLine, ';'),
      '\t': _countOutsideQuotes(firstLine, '\t'),
    };
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  static int _countOutsideQuotes(String value, String character) {
    var insideQuotes = false;
    var count = 0;
    for (var index = 0; index < value.length; index++) {
      if (value[index] == '"') insideQuotes = !insideQuotes;
      if (!insideQuotes && value[index] == character) count++;
    }
    return count;
  }

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  static String _workbookName(String fileName) {
    final normalized = fileName.trim().split(RegExp(r'[\\/]')).last;
    final dot = normalized.lastIndexOf('.');
    final withoutExtension =
        dot <= 0 ? normalized : normalized.substring(0, dot);
    return withoutExtension.trim().isEmpty
        ? 'Planilla importada'
        : withoutExtension.trim();
  }
}
