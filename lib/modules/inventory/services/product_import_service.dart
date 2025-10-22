import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

import '../../../shared/services/database_service.dart';

class ProductImportService {
  ProductImportService(this._db);

  final DatabaseService _db;

  static final List<ProductImportFieldDefinition> _fieldDefinitions = [
    const ProductImportFieldDefinition(
      key: 'sku',
      label: 'SKU',
      required: true,
      isRecommended: true,
      sampleValue: 'MTB-ALU-001',
      aliases: [
        'sku',
        'product sku',
        'codigo',
        'código',
        'item code',
        'part number',
      ],
    ),
    const ProductImportFieldDefinition(
      key: 'name',
      label: 'Nombre',
      required: true,
      isRecommended: true,
      sampleValue: 'Mountain Bike Aluminio 29"',
      aliases: [
        'name',
        'nombre',
        'product name',
        'item name',
      ],
    ),
    const ProductImportFieldDefinition(
      key: 'category_name',
      label: 'Categoría',
      isRecommended: true,
      sampleValue: 'Bicicletas',
      aliases: [
        'category',
        'categoria',
        'categoría',
        'product category',
        'family',
        'familia',
      ],
    ),
    const ProductImportFieldDefinition(
      key: 'supplier_name',
      label: 'Proveedor',
      isRecommended: true,
      sampleValue: 'Proveedor Principal',
      aliases: ['supplier', 'proveedor', 'vendor'],
    ),
    const ProductImportFieldDefinition(
      key: 'brand',
      label: 'Marca',
      isRecommended: true,
      sampleValue: 'VinaBike',
      aliases: ['brand', 'marca'],
    ),
    const ProductImportFieldDefinition(
      key: 'inventory_qty',
      label: 'Stock disponible',
      type: ProductImportFieldType.integer,
      isRecommended: true,
      sampleValue: '10',
      aliases: ['inventory', 'stock', 'cantidad', 'existencias'],
    ),
    const ProductImportFieldDefinition(
      key: 'price',
      label: 'Precio venta (CLP)',
      type: ProductImportFieldType.decimal,
      isRecommended: true,
      sampleValue: '899000',
      aliases: ['price', 'precio', 'sale price', 'precio venta'],
    ),
    const ProductImportFieldDefinition(
      key: 'cost',
      label: 'Costo (CLP)',
      type: ProductImportFieldType.decimal,
      isRecommended: true,
      sampleValue: '540000',
      aliases: ['cost', 'costo', 'purchase cost', 'precio costo'],
    ),
    const ProductImportFieldDefinition(
      key: 'tax_rate',
      label: 'IVA (%)',
      type: ProductImportFieldType.decimal,
      isRecommended: true,
      sampleValue: '19',
      aliases: ['iva', 'tax', 'tax rate', 'impuesto'],
    ),
  ];

  static const Map<String, String> _accentMap = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };

  List<ProductImportFieldDefinition> get fieldDefinitions =>
      List.unmodifiable(_fieldDefinitions);

  List<ProductImportFieldDefinition> get requiredFields => List.unmodifiable(
        _fieldDefinitions.where((field) => field.required),
      );

  List<String> get recommendedColumnLabels => _fieldDefinitions
      .where((field) => field.isRecommended || field.required)
      .map((field) => field.label)
      .toList(growable: false);

  Future<Uint8List> buildTemplateBytes({bool includeOptional = false}) async {
    final structure =
        _buildTemplateStructure(includeOptional: includeOptional);
    const converter = ListToCsvConverter();
    final csv = converter.convert([
      structure.headers,
      structure.sampleRow,
    ]);
    return Uint8List.fromList(utf8.encode(csv));
  }

  Future<Uint8List> buildTemplateExcelBytes({
    bool includeOptional = false,
  }) async {
    final structure =
        _buildTemplateStructure(includeOptional: includeOptional);
    final excel = Excel.createExcel();
    const sheetName = 'Productos';
    final sheet = excel[sheetName];
    sheet.appendRow(_toTextRow(structure.headers));
    sheet.appendRow(_toTextRow(structure.sampleRow));
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      excel.delete(defaultSheet);
    }
    final encoded = excel.encode();
    if (encoded == null) {
      throw ProductImportException(
        'No se pudo generar la plantilla en formato Excel.',
      );
    }
    return Uint8List.fromList(encoded);
  }

  Future<ProductImportParseResult> parseBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final extension = _detectExtension(fileName);
    final records = extension == 'xlsx' || extension == 'xls'
        ? _parseExcel(bytes)
        : _parseDelimited(bytes, extension == 'tsv');

    if (records.isEmpty) {
      throw ProductImportException('El archivo no contiene datos.');
    }

    final rawHeaders = records.first
        .map((value) => value?.toString().trim() ?? '')
        .toList(growable: false);
    final headers = <String>[];
    final seen = <String>{};
    for (final header in rawHeaders) {
      var candidate = _normalizeHeader(header);
      var suffix = 1;
      while (candidate.isNotEmpty && !seen.add(candidate)) {
        suffix += 1;
        candidate = '${header}_$suffix';
      }
      headers.add(candidate);
    }

    final rows = <Map<String, String>>[];
    for (var i = 1; i < records.length; i++) {
      final record = records[i];
      final mapped = <String, String>{};
      var hasData = false;
      for (var col = 0; col < headers.length; col++) {
        final header = headers[col];
        if (header.isEmpty) continue;
        final value = col < record.length ? record[col] : null;
        final text = value == null ? '' : value.toString().trim();
        mapped[header] = text;
        if (text.isNotEmpty) {
          hasData = true;
        }
      }
      if (hasData) {
        rows.add(mapped);
      }
    }

    return ProductImportParseResult(
      headers: headers,
      rows: rows,
      sourceName: fileName,
    );
  }

  Map<String, String?> buildInitialMapping(List<String> headers) {
    final mapping = <String, String?>{};
    final assigned = <String>{};
    for (final header in headers) {
      final normalizedHeader = _normalize(header);
      ProductImportFieldDefinition? match;
      for (final field in _fieldDefinitions) {
        if (assigned.contains(field.key)) continue;
        final aliases = <String>{field.key, field.label, ...field.aliases};
        if (aliases.any((alias) => _normalize(alias) == normalizedHeader)) {
          match = field;
          break;
        }
      }
      if (match != null) {
        mapping[header] = match.key;
        assigned.add(match.key);
      } else {
        mapping[header] = null;
      }
    }
    return mapping;
  }

  Future<ProductImportSummary> importProducts({
    required List<Map<String, String>> rows,
    required Map<String, String?> mapping,
    bool allowUpdates = true,
    bool createMissingSuppliers = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    final fieldToHeader = <String, String>{};

    mapping.forEach((header, key) {
      if (key == null) return;
      fieldToHeader[key] = header;
    });

    var inserted = 0;
    var updated = 0;
    final errors = <ProductImportError>[];
    final supplierCache = <String, String>{};

    for (var index = 0; index < rows.length; index++) {
      final rowNumber = index + 2;
      final row = rows[index];
      try {
        final payload = await _buildPayload(
          row: row,
          fieldToHeader: fieldToHeader,
          createMissingSuppliers: createMissingSuppliers,
          supplierCache: supplierCache,
        );

        if (payload == null) {
          continue;
        }

        final isInsert = await _upsertProduct(
          payload: payload,
          allowUpdates: allowUpdates,
        );
        if (isInsert) {
          inserted += 1;
        } else {
          updated += 1;
        }
      } on ProductImportRowException catch (e) {
        errors.add(
          ProductImportError(
            rowNumber: rowNumber,
            message: e.message,
            rowSnapshot: row,
          ),
        );
      } catch (error, stackTrace) {
        debugPrint('Error inesperado al importar fila $rowNumber: $error');
        debugPrint(stackTrace.toString());
        errors.add(
          ProductImportError(
            rowNumber: rowNumber,
            message: 'Error inesperado: $error',
            rowSnapshot: row,
          ),
        );
      }
    }

    stopwatch.stop();

    return ProductImportSummary(
      processed: rows.length,
      inserted: inserted,
      updated: updated,
      errors: errors,
      elapsed: stopwatch.elapsed,
    );
  }

  Future<Map<String, dynamic>?> _buildPayload({
    required Map<String, String> row,
    required Map<String, String> fieldToHeader,
    required bool createMissingSuppliers,
    required Map<String, String> supplierCache,
  }) async {
    String? valueFor(String key) {
      final header = fieldToHeader[key];
      if (header == null) return null;
      final raw = row[header];
      if (raw == null || raw.trim().isEmpty) return null;
      return raw.trim();
    }

    final sku = valueFor('sku');
    final name = valueFor('name');

    if (sku == null || sku.isEmpty) {
      throw ProductImportRowException('La fila no incluye un SKU.');
    }
    if (name == null || name.isEmpty) {
      throw ProductImportRowException('La fila no incluye un nombre.');
    }

    final inventoryQty = _parseInt(valueFor('inventory_qty')) ?? 0;
    final price = _parseDecimal(valueFor('price')) ?? 0;
    final cost = _parseDecimal(valueFor('cost')) ?? 0;
    final rawTaxRate = _parseDecimal(valueFor('tax_rate'));
    final taxRate = _normalizeTaxRate(rawTaxRate);

    final payload = <String, dynamic>{
      'sku': sku,
      'name': name,
      'category_name': valueFor('category_name'),
      'category': _guessCategory(valueFor('category_name')) ?? 'other',
      'brand': valueFor('brand'),
      'inventory_qty': inventoryQty,
      'stock_quantity': inventoryQty,
      'price': price,
      'cost': cost,
      'price_currency': 'CLP',
      'cost_currency': 'CLP',
      'tax_rate': taxRate,
      'track_stock': true,
      'is_active': true,
    };

    final supplierId = await _resolveSupplierId(
      explicitId: valueFor('supplier_id'),
      supplierName: valueFor('supplier_name'),
      cache: supplierCache,
      createIfMissing: createMissingSuppliers,
    );

    if (supplierId != null) {
      payload['supplier_id'] = supplierId;
    }

    payload.removeWhere((_, value) => value == null);

    payload.putIfAbsent('unit', () => 'unit');
    payload.putIfAbsent('min_stock_level', () => 1);
    payload.putIfAbsent('product_type', () => 'product');

    return payload;
  }

  Future<String?> _resolveSupplierId({
    required String? explicitId,
    required String? supplierName,
    required Map<String, String> cache,
    required bool createIfMissing,
  }) async {
    if (explicitId != null && explicitId.trim().isNotEmpty) {
      return explicitId.trim();
    }
    if (supplierName == null || supplierName.trim().isEmpty) {
      return null;
    }

    final normalized = supplierName.trim().toLowerCase();
    if (cache.containsKey(normalized)) {
      return cache[normalized];
    }

    final existing = await _db.select(
      'suppliers',
      where: 'name=${supplierName.trim()}',
    );
    if (existing.isNotEmpty) {
      final id = existing.first['id'].toString();
      cache[normalized] = id;
      return id;
    }

    if (!createIfMissing) {
      return null;
    }

    final created = await _db.insert('suppliers', {
      'name': supplierName.trim(),
      'is_active': true,
    });
    final id = created['id'].toString();
    cache[normalized] = id;
    return id;
  }

  Future<bool> _upsertProduct({
    required Map<String, dynamic> payload,
    required bool allowUpdates,
  }) async {
    final sku = (payload['sku'] as String).trim();
    final existing = await _db.select('products', where: 'sku=$sku');
    if (existing.isEmpty) {
      await _db.insert('products', payload);
      return true;
    }

    if (!allowUpdates) {
      throw ProductImportRowException(
        'El SKU $sku ya existe y las actualizaciones están desactivadas.',
      );
    }

    final productId = existing.first['id'].toString();
    final updatePayload = Map<String, dynamic>.from(payload)
      ..remove('sku')
      ..remove('created_at');
    await _db.update('products', productId, updatePayload);
    return false;
  }

  List<List<dynamic>> _parseDelimited(Uint8List bytes, bool isTsv) {
    final content = utf8.decode(bytes, allowMalformed: true);
    final converter = CsvToListConverter(
      fieldDelimiter: isTsv ? '\t' : ',',
      shouldParseNumbers: false,
    );
    return converter.convert(content);
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    Sheet? sheet;
    for (final table in excel.tables.values) {
      if (table.maxRows > 0) {
        sheet = table;
        break;
      }
    }
    if (sheet == null) {
      return const [];
    }
    return sheet.rows
        .map((row) => row.map((cell) => cell?.value).toList())
        .toList();
  }

  String _detectExtension(String fileName) {
    final parts = fileName.split('.');
    if (parts.length < 2) return 'csv';
    final ext = parts.last.toLowerCase();
    switch (ext) {
      case 'xlsx':
      case 'xls':
      case 'tsv':
      case 'csv':
      case 'txt':
        return ext;
      default:
        return 'csv';
    }
  }

  double? _parseDecimal(String? value) {
    if (value == null) return null;
    final sanitized = value
        .replaceAll(RegExp(r'[^0-9,.-]'), '')
        .replaceAll('.', '')
        .replaceAll(',', '.');
    return double.tryParse(sanitized);
  }

  int? _parseInt(String? value) {
    final decimal = _parseDecimal(value);
    return decimal?.round();
  }

  double? _normalizeTaxRate(double? value) {
    if (value == null) return null;
    if (value > 1) {
      return value / 100;
    }
    return value;
  }

  String _normalize(String input) {
    final lower = input.toLowerCase().trim();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_accentMap[char] ?? char);
    }
    return buffer.toString().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _normalizeHeader(String header) => header.trim();

  String? _guessCategory(String? categoryName) {
    if (categoryName == null) return null;
    final normalized = categoryName.toLowerCase();
    for (final entry in _categoryHints.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  _TemplateStructure _buildTemplateStructure({
    required bool includeOptional,
  }) {
    final fields = includeOptional
        ? _fieldDefinitions
        : _fieldDefinitions
            .where((field) => field.required || field.isRecommended)
            .toList(growable: false);

    final headers = fields.map((field) => field.label).toList(growable: false);
    final sampleRow = fields
        .map((field) => field.sampleValue ?? '')
        .toList(growable: false);

    return _TemplateStructure(headers: headers, sampleRow: sampleRow);
  }

  static const Map<String, String> _categoryHints = {
    'bici': 'bicycles',
    'bike': 'bicycles',
    'frame': 'parts',
    'repuesto': 'parts',
    'part': 'parts',
    'herramienta': 'tools',
    'tool': 'tools',
    'accesorio': 'accessories',
    'accessor': 'accessories',
    'ropa': 'clothing',
    'wear': 'clothing',
    'mantencion': 'maintenance',
    'maintenance': 'maintenance',
    'servi': 'services',
  };

  static List<CellValue?> _toTextRow(List<String> values) {
    return values
        .map<CellValue?>((value) => TextCellValue(value))
        .toList(growable: false);
  }
}

class ProductImportParseResult {
  const ProductImportParseResult({
    required this.headers,
    required this.rows,
    required this.sourceName,
  });

  final List<String> headers;
  final List<Map<String, String>> rows;
  final String sourceName;
}

class ProductImportSummary {
  const ProductImportSummary({
    required this.processed,
    required this.inserted,
    required this.updated,
    required this.errors,
    required this.elapsed,
  });

  final int processed;
  final int inserted;
  final int updated;
  final List<ProductImportError> errors;
  final Duration elapsed;

  int get skipped => errors.length;
}

class ProductImportError {
  const ProductImportError({
    required this.rowNumber,
    required this.message,
    required this.rowSnapshot,
  });

  final int rowNumber;
  final String message;
  final Map<String, String> rowSnapshot;
}

class ProductImportException implements Exception {
  ProductImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProductImportRowException implements Exception {
  ProductImportRowException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProductImportFieldDefinition {
  const ProductImportFieldDefinition({
    required this.key,
    required this.label,
    this.required = false,
    this.aliases = const [],
    this.type = ProductImportFieldType.text,
    this.description,
    this.isRecommended = false,
    this.sampleValue,
  });

  final String key;
  final String label;
  final bool required;
  final List<String> aliases;
  final ProductImportFieldType type;
  final String? description;
  final bool isRecommended;
  final String? sampleValue;
}

enum ProductImportFieldType { text, longText, integer, decimal, boolean }

class _TemplateStructure {
  _TemplateStructure({
    required this.headers,
    required this.sampleRow,
  });

  final List<String> headers;
  final List<String> sampleRow;
}
