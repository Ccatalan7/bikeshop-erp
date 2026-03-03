/// Represents a saved spreadsheet's metadata.

/// Represents a saved spreadsheet's metadata.
class SpreadsheetModel {
  final String? id;
  final String tenantId;
  final String name;
  final int rowCount;
  final int colCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SpreadsheetModel({
    this.id,
    required this.tenantId,
    this.name = 'Planilla sin título',
    this.rowCount = 100,
    this.colCount = 26,
    this.createdAt,
    this.updatedAt,
  });

  factory SpreadsheetModel.fromJson(Map<String, dynamic> json) {
    return SpreadsheetModel(
      id: json['id'] as String?,
      tenantId: json['tenant_id'] as String? ?? '',
      name: json['name'] as String? ?? 'Planilla sin título',
      rowCount: json['row_count'] as int? ?? 100,
      colCount: json['col_count'] as int? ?? 26,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'tenant_id': tenantId,
      'name': name,
      'row_count': rowCount,
      'col_count': colCount,
    };
  }

  SpreadsheetModel copyWith({
    String? id,
    String? tenantId,
    String? name,
    int? rowCount,
    int? colCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SpreadsheetModel(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      rowCount: rowCount ?? this.rowCount,
      colCount: colCount ?? this.colCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Represents a single cell in a spreadsheet.
class CellModel {
  final String? id;
  final String spreadsheetId;
  final int row;
  final int col;
  final String? rawValue;
  final String? displayValue;
  final String cellType; // text, number, formula
  final bool bold;
  final bool italic;
  final String textAlign; // left, center, right

  CellModel({
    this.id,
    required this.spreadsheetId,
    required this.row,
    required this.col,
    this.rawValue,
    this.displayValue,
    this.cellType = 'text',
    this.bold = false,
    this.italic = false,
    this.textAlign = 'left',
  });

  /// A1 notation for this cell (e.g., "A1", "B3", "AA10")
  String get cellRef => '${colToLetter(col)}${row + 1}';

  bool get isFormula => rawValue != null && rawValue!.startsWith('=');
  bool get isEmpty => rawValue == null || rawValue!.isEmpty;

  factory CellModel.fromJson(Map<String, dynamic> json) {
    return CellModel(
      id: json['id'] as String?,
      spreadsheetId: json['spreadsheet_id'] as String? ?? '',
      row: json['row_index'] as int? ?? 0,
      col: json['col_index'] as int? ?? 0,
      rawValue: json['raw_value'] as String?,
      displayValue: json['display_value'] as String?,
      cellType: json['cell_type'] as String? ?? 'text',
      bold: json['bold'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
      textAlign: json['text_align'] as String? ?? 'left',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'spreadsheet_id': spreadsheetId,
      'row_index': row,
      'col_index': col,
      'raw_value': rawValue,
      'display_value': displayValue,
      'cell_type': cellType,
      'bold': bold,
      'italic': italic,
      'text_align': textAlign,
    };
  }

  CellModel copyWith({
    String? id,
    String? spreadsheetId,
    int? row,
    int? col,
    String? rawValue,
    String? displayValue,
    String? cellType,
    bool? bold,
    bool? italic,
    String? textAlign,
  }) {
    return CellModel(
      id: id ?? this.id,
      spreadsheetId: spreadsheetId ?? this.spreadsheetId,
      row: row ?? this.row,
      col: col ?? this.col,
      rawValue: rawValue ?? this.rawValue,
      displayValue: displayValue ?? this.displayValue,
      cellType: cellType ?? this.cellType,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      textAlign: textAlign ?? this.textAlign,
    );
  }

  /// Convert 0-based column index to letter(s): 0→A, 1→B, ..., 25→Z, 26→AA
  static String colToLetter(int col) {
    String result = '';
    int c = col;
    while (c >= 0) {
      result = String.fromCharCode((c % 26) + 65) + result;
      c = (c ~/ 26) - 1;
    }
    return result;
  }

  /// Convert letter(s) to 0-based column index: A→0, B→1, Z→25, AA→26
  static int letterToCol(String letters) {
    int col = 0;
    for (int i = 0; i < letters.length; i++) {
      col = col * 26 + (letters.codeUnitAt(i) - 64);
    }
    return col - 1;
  }
}

/// In-memory cell data for the editor (avoids DB round-trips during editing).
class CellData {
  String rawValue;
  String displayValue;
  String cellType;
  bool bold;
  bool italic;
  String textAlign;
  bool dirty; // needs to be saved

  CellData({
    this.rawValue = '',
    this.displayValue = '',
    this.cellType = 'text',
    this.bold = false,
    this.italic = false,
    this.textAlign = 'left',
    this.dirty = false,
  });

  bool get isEmpty => rawValue.isEmpty;
  bool get isFormula => rawValue.startsWith('=');
}
