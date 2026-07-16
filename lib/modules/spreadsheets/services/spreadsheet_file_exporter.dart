import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import 'univer_workbook_adapter.dart';

/// Encodes the canonical Univer workbook snapshot back into a stored file.
///
/// The runner uses this boundary instead of maintaining a second cell model.
/// XLSX round-trips common cell values, formulas, styles, merges, and sizing;
/// CSV writes the first worksheet as a normal delimited document.
class SpreadsheetFileExporter {
  const SpreadsheetFileExporter._();

  static Uint8List encode({
    required Map<String, dynamic> workbookData,
    required String fileName,
  }) {
    if (!UniverWorkbookAdapter.isValidSnapshot(workbookData)) {
      throw const FormatException('La planilla no tiene un formato válido.');
    }

    return switch (_extensionOf(fileName)) {
      'xlsx' => _encodeXlsx(workbookData),
      'csv' => _encodeCsv(workbookData),
      final extension => throw UnsupportedError(
          'No se puede guardar el formato .$extension desde Planillas.',
        ),
    };
  }

  static Uint8List _encodeXlsx(Map<String, dynamic> workbookData) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    final sheetOrder = List<dynamic>.from(
      workbookData['sheetOrder'] as List? ?? const <dynamic>[],
    );
    final sheets = Map<dynamic, dynamic>.from(
      workbookData['sheets'] as Map? ?? const <dynamic, dynamic>{},
    );
    final workbookStyles = Map<dynamic, dynamic>.from(
      workbookData['styles'] as Map? ?? const <dynamic, dynamic>{},
    );
    final usedNames = <String>{};

    for (var sheetIndex = 0; sheetIndex < sheetOrder.length; sheetIndex++) {
      final sheetId = sheetOrder[sheetIndex]?.toString() ?? '';
      final rawSheet = sheets[sheetId];
      if (rawSheet is! Map) continue;
      final sheetData = Map<dynamic, dynamic>.from(rawSheet);
      final sheetName = _safeSheetName(
        sheetData['name']?.toString(),
        sheetIndex,
        usedNames,
      );
      final sheet = excel[sheetName];

      final cellData = Map<dynamic, dynamic>.from(
        sheetData['cellData'] as Map? ?? const <dynamic, dynamic>{},
      );
      for (final rowEntry in cellData.entries) {
        final rowIndex = int.tryParse(rowEntry.key.toString());
        if (rowIndex == null || rowIndex < 0 || rowEntry.value is! Map) {
          continue;
        }
        final row = Map<dynamic, dynamic>.from(rowEntry.value as Map);
        for (final columnEntry in row.entries) {
          final columnIndex = int.tryParse(columnEntry.key.toString());
          if (columnIndex == null ||
              columnIndex < 0 ||
              columnEntry.value is! Map) {
            continue;
          }
          final cell = Map<dynamic, dynamic>.from(columnEntry.value as Map);
          final value = _cellValue(cell);
          final style = _cellStyle(cell['s'], workbookStyles);
          if (value == null && style == null) continue;
          final index = CellIndex.indexByColumnRow(
            columnIndex: columnIndex,
            rowIndex: rowIndex,
          );
          if (value != null) {
            sheet.updateCell(index, value, cellStyle: style);
          } else {
            sheet.cell(index).cellStyle = style;
          }
        }
      }

      final rowData = Map<dynamic, dynamic>.from(
        sheetData['rowData'] as Map? ?? const <dynamic, dynamic>{},
      );
      for (final entry in rowData.entries) {
        final rowIndex = int.tryParse(entry.key.toString());
        if (rowIndex == null || entry.value is! Map) continue;
        final height = (entry.value as Map)['h'];
        if (height is num && height > 0) {
          sheet.setRowHeight(rowIndex, height.toDouble() * 72 / 96);
        }
      }

      final columnData = Map<dynamic, dynamic>.from(
        sheetData['columnData'] as Map? ?? const <dynamic, dynamic>{},
      );
      for (final entry in columnData.entries) {
        final columnIndex = int.tryParse(entry.key.toString());
        if (columnIndex == null || entry.value is! Map) continue;
        final width = (entry.value as Map)['w'];
        if (width is num && width > 0) {
          sheet.setColumnWidth(
            columnIndex,
            math.max(1, (width.toDouble() - 5) / 7),
          );
        }
      }

      final merges = sheetData['mergeData'];
      if (merges is List) {
        for (final rawMerge in merges) {
          if (rawMerge is! Map) continue;
          final merge = Map<dynamic, dynamic>.from(rawMerge);
          final startRow = _intValue(merge['startRow']);
          final endRow = _intValue(merge['endRow']);
          final startColumn = _intValue(merge['startColumn']);
          final endColumn = _intValue(merge['endColumn']);
          if (startRow == null ||
              endRow == null ||
              startColumn == null ||
              endColumn == null) {
            continue;
          }
          sheet.merge(
            CellIndex.indexByColumnRow(
              columnIndex: startColumn,
              rowIndex: startRow,
            ),
            CellIndex.indexByColumnRow(
              columnIndex: endColumn,
              rowIndex: endRow,
            ),
          );
        }
      }
    }

    if (defaultSheet != null && !usedNames.contains(defaultSheet)) {
      excel.delete(defaultSheet);
    }
    final encoded = excel.encode();
    if (encoded == null) {
      throw const FormatException('No se pudo generar el archivo XLSX.');
    }
    return Uint8List.fromList(encoded);
  }

  static Uint8List _encodeCsv(Map<String, dynamic> workbookData) {
    final sheetOrder = workbookData['sheetOrder'];
    final sheets = workbookData['sheets'];
    if (sheetOrder is! List || sheetOrder.isEmpty || sheets is! Map) {
      throw const FormatException('La planilla no contiene hojas.');
    }
    final rawSheet = sheets[sheetOrder.first];
    if (rawSheet is! Map) {
      throw const FormatException('La primera hoja no es válida.');
    }
    final cellData = Map<dynamic, dynamic>.from(
      rawSheet['cellData'] as Map? ?? const <dynamic, dynamic>{},
    );
    var lastRow = -1;
    var lastColumn = -1;
    for (final rowEntry in cellData.entries) {
      final rowIndex = int.tryParse(rowEntry.key.toString());
      if (rowIndex == null || rowEntry.value is! Map) continue;
      lastRow = math.max(lastRow, rowIndex);
      for (final columnKey in (rowEntry.value as Map).keys) {
        final columnIndex = int.tryParse(columnKey.toString());
        if (columnIndex != null) lastColumn = math.max(lastColumn, columnIndex);
      }
    }

    final rows = <List<Object?>>[];
    for (var rowIndex = 0; rowIndex <= lastRow; rowIndex++) {
      final rawRow = cellData['$rowIndex'];
      final row = rawRow is Map ? rawRow : const <dynamic, dynamic>{};
      rows.add([
        for (var columnIndex = 0; columnIndex <= lastColumn; columnIndex++)
          _csvValue(row['$columnIndex']),
      ]);
    }
    return Uint8List.fromList(
      utf8.encode(const ListToCsvConverter().convert(rows)),
    );
  }

  static CellValue? _cellValue(Map<dynamic, dynamic> cell) {
    final formula = cell['f'];
    if (formula is String && formula.trim().isNotEmpty) {
      return FormulaCellValue(formula);
    }
    final value = cell['v'];
    return switch (value) {
      null => null,
      bool value => BoolCellValue(value),
      int value => IntCellValue(value),
      double value => DoubleCellValue(value),
      _ => TextCellValue(value.toString()),
    };
  }

  static Object? _csvValue(Object? rawCell) {
    if (rawCell is! Map) return '';
    final formula = rawCell['f'];
    if (formula is String && formula.isNotEmpty) return formula;
    return rawCell['v'] ?? '';
  }

  static CellStyle? _cellStyle(
    Object? rawStyle,
    Map<dynamic, dynamic> workbookStyles,
  ) {
    final resolved = rawStyle is Map
        ? rawStyle
        : workbookStyles[rawStyle] ?? workbookStyles[rawStyle?.toString()];
    if (resolved is! Map || resolved.isEmpty) return null;
    final style = Map<dynamic, dynamic>.from(resolved);
    final fontColor = _excelColor(style['cl']);
    final backgroundColor = _excelColor(style['bg']);
    final fontSize = _intValue(style['fs']);
    final rotationValue = style['tr'];
    final rotation = rotationValue is Map ? _intValue(rotationValue['a']) : 0;
    final numberFormatValue = style['n'];
    final numberPattern = numberFormatValue is Map
        ? numberFormatValue['pattern']?.toString()
        : null;

    return CellStyle(
      bold: _truthy(style['bl']),
      italic: _truthy(style['it']),
      underline: style['ul'] == null ? Underline.None : Underline.Single,
      fontFamily: style['ff']?.toString(),
      fontSize: fontSize,
      fontColorHex: fontColor ?? ExcelColor.black,
      backgroundColorHex: backgroundColor ?? ExcelColor.none,
      horizontalAlign: switch (_intValue(style['ht'])) {
        2 => HorizontalAlign.Center,
        3 => HorizontalAlign.Right,
        _ => HorizontalAlign.Left,
      },
      verticalAlign: switch (_intValue(style['vt'])) {
        1 => VerticalAlign.Top,
        2 => VerticalAlign.Center,
        _ => VerticalAlign.Bottom,
      },
      textWrapping: _intValue(style['tb']) == 3 ? TextWrapping.WrapText : null,
      rotation: (rotation ?? 0).clamp(-90, 90),
      numberFormat: numberPattern == null || numberPattern == 'General'
          ? NumFormat.standard_0
          : NumFormat.custom(formatCode: numberPattern),
      topBorder: _excelBorder(style['bd'], 't'),
      rightBorder: _excelBorder(style['bd'], 'r'),
      bottomBorder: _excelBorder(style['bd'], 'b'),
      leftBorder: _excelBorder(style['bd'], 'l'),
    );
  }

  static Border _excelBorder(Object? rawBorders, String side) {
    if (rawBorders is! Map || rawBorders[side] is! Map) return Border();
    final data = rawBorders[side] as Map;
    final style = switch (_intValue(data['s'])) {
      1 => BorderStyle.Thin,
      2 => BorderStyle.Hair,
      3 => BorderStyle.Dotted,
      4 => BorderStyle.Dashed,
      5 => BorderStyle.DashDot,
      6 => BorderStyle.DashDotDot,
      7 => BorderStyle.Double,
      8 => BorderStyle.Medium,
      9 => BorderStyle.MediumDashed,
      10 => BorderStyle.MediumDashDot,
      11 => BorderStyle.MediumDashDotDot,
      12 => BorderStyle.SlantDashDot,
      13 => BorderStyle.Thick,
      _ => BorderStyle.None,
    };
    return Border(
      borderStyle: style,
      borderColorHex: _excelColor(data['cl']) ?? ExcelColor.black,
    );
  }

  static ExcelColor? _excelColor(Object? rawColor) {
    final value = rawColor is Map ? rawColor['rgb'] : rawColor;
    if (value is! String || value.trim().isEmpty) return null;
    final rgb = value.replaceAll('#', '').trim();
    if (rgb.length != 6 && rgb.length != 8) return null;
    return ExcelColor.fromHexString(rgb.length == 6 ? 'FF$rgb' : rgb);
  }

  static bool _truthy(Object? value) =>
      value == true || value == 1 || value == '1';

  static int? _intValue(Object? value) => switch (value) {
        int value => value,
        num value => value.round(),
        _ => int.tryParse(value?.toString() ?? ''),
      };

  static String _safeSheetName(
    String? requested,
    int index,
    Set<String> usedNames,
  ) {
    var base = (requested?.trim().isNotEmpty == true
            ? requested!.trim()
            : 'Hoja ${index + 1}')
        .replaceAll(RegExp(r'''[\\/:?*\[\]]'''), '_');
    if (base.length > 31) base = base.substring(0, 31);
    if (base.isEmpty) base = 'Hoja ${index + 1}';
    var candidate = base;
    var suffix = 2;
    while (usedNames.contains(candidate)) {
      final suffixText = ' ($suffix)';
      final prefixLength = math.max(1, 31 - suffixText.length);
      candidate = '${base.substring(0, math.min(base.length, prefixLength))}'
          '$suffixText';
      suffix++;
    }
    usedNames.add(candidate);
    return candidate;
  }

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}
