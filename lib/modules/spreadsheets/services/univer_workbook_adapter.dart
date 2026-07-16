import 'dart:convert';

import '../models/spreadsheet_model.dart';

/// Converts the retired sparse-cell model into Univer's versioned workbook
/// snapshot on first open. Once [SpreadsheetModel.workbookData] contains a
/// valid versioned workbook, Univer owns it and this adapter only normalizes
/// workbook identity/name.
class UniverWorkbookAdapter {
  const UniverWorkbookAdapter._();

  static const String engineVersion = '0.25.1';
  static const String _defaultSheetId = 'sheet-1';

  /// Whether [snapshot] has the minimum versioned workbook structure Univer
  /// needs to reopen it without inventing a replacement sheet.
  static bool isValidSnapshot(Map<String, dynamic>? snapshot) {
    if (snapshot == null || snapshot.isEmpty) return false;

    final appVersion = snapshot['appVersion'];
    final sheetOrder = snapshot['sheetOrder'];
    final sheets = snapshot['sheets'];
    if (appVersion is! String || appVersion.trim().isEmpty) return false;
    if (sheetOrder is! List || sheetOrder.isEmpty || sheets is! Map) {
      return false;
    }

    for (final sheetId in sheetOrder) {
      if (sheetId is! String || sheetId.isEmpty) return false;
      final sheet = sheets[sheetId];
      if (sheet is! Map || sheet['id'] != sheetId) return false;
    }
    return true;
  }

  static Map<String, dynamic> createSnapshot({
    required SpreadsheetModel spreadsheet,
    required List<CellModel> legacyCells,
  }) {
    final persisted = spreadsheet.workbookData;
    if (isValidSnapshot(persisted)) {
      final snapshot = _jsonCopy(persisted!);
      snapshot['id'] = spreadsheet.id;
      snapshot['name'] = spreadsheet.name;
      snapshot['locale'] = 'esES';
      return snapshot;
    }

    final cellData = <String, dynamic>{};
    for (final cell in legacyCells) {
      final rawValue = cell.rawValue ?? '';
      if (rawValue.isEmpty) continue;
      final row = cellData.putIfAbsent(
        '${cell.row}',
        () => <String, dynamic>{},
      ) as Map<String, dynamic>;
      row['${cell.col}'] = _legacyCellData(cell, rawValue);
    }

    return <String, dynamic>{
      'id': spreadsheet.id,
      'name': spreadsheet.name,
      'appVersion': engineVersion,
      'locale': 'esES',
      'styles': <String, dynamic>{},
      'sheetOrder': const <String>[_defaultSheetId],
      'sheets': <String, dynamic>{
        _defaultSheetId: <String, dynamic>{
          'id': _defaultSheetId,
          'name': 'Hoja 1',
          'rowCount': spreadsheet.rowCount < 100 ? 100 : spreadsheet.rowCount,
          'columnCount': spreadsheet.colCount < 26 ? 26 : spreadsheet.colCount,
          'defaultColumnWidth': 100,
          'defaultRowHeight': 24,
          'cellData': cellData,
        },
      },
    };
  }

  static Map<String, dynamic> _legacyCellData(
    CellModel cell,
    String rawValue,
  ) {
    final style = <String, dynamic>{
      if (cell.bold) 'bl': 1,
      if (cell.italic) 'it': 1,
      if (cell.textAlign != 'left')
        'ht': switch (cell.textAlign) {
          'center' => 2,
          'right' => 3,
          _ => 1,
        },
    };
    final data = <String, dynamic>{
      if (style.isNotEmpty) 's': style,
    };

    final trimmed = rawValue.trim();
    if (trimmed.startsWith('=')) {
      data['f'] = _translateLegacyFormula(trimmed);
      return data;
    }

    final numericValue = double.tryParse(trimmed.replaceAll(',', '.'));
    if (numericValue != null) {
      data['v'] = numericValue;
      data['t'] = 2;
    } else {
      data['v'] = rawValue;
      data['t'] = 1;
    }
    return data;
  }

  static String _translateLegacyFormula(String formula) {
    var result = formula;
    const aliases = <String, String>{
      'SUMA': 'SUM',
      'PROMEDIO': 'AVERAGE',
      'CONTAR': 'COUNT',
      'SI': 'IF',
    };
    for (final entry in aliases.entries) {
      result = result.replaceAllMapped(
        RegExp('\\b${entry.key}\\s*\\(', caseSensitive: false),
        (_) => '${entry.value}(',
      );
    }
    return result.replaceAll(';', ',');
  }

  static Map<String, dynamic> _jsonCopy(Map<String, dynamic> value) {
    return Map<String, dynamic>.from(
      jsonDecode(jsonEncode(value)) as Map,
    );
  }
}
