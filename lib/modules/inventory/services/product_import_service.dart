import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/constants/storage_constants.dart';
import '../../../shared/models/product_tax_treatment.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';

typedef MissingProductSupplierCreator = Future<String> Function(String name);

class ProductImportService {
  ProductImportService(
    this._db, {
    required MissingProductSupplierCreator createMissingSupplier,
  }) : _createMissingSupplier = createMissingSupplier;

  final DatabaseService _db;
  final MissingProductSupplierCreator _createMissingSupplier;

  static final List<ProductImportFieldDefinition> _fieldDefinitions = [
    // 1. SKU (Referencia interna in Odoo)
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
        'referencia',
        'referencia interna',
      ],
    ),
    // 2. Nombre (Nombre in Odoo)
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
    // 3. Categoría (Categoría del producto in Odoo)
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
        'categoria del producto',
        'family',
        'familia',
      ],
    ),
    // 4. Proveedor (Proveedores in Odoo)
    const ProductImportFieldDefinition(
      key: 'supplier_name',
      label: 'Proveedor',
      isRecommended: true,
      sampleValue: 'Proveedor Principal',
      aliases: [
        'supplier',
        'proveedor',
        'proveedores',
        'vendor',
      ],
    ),
    // 4b. Código Proveedor (Supplier Code for this product)
    const ProductImportFieldDefinition(
      key: 'supplier_code',
      label: 'Código Proveedor',
      isRecommended: false,
      sampleValue: 'KMC-2025-001',
      aliases: [
        'supplier code',
        'supplier sku',
        'código proveedor',
        'codigo proveedor',
        'vendor code',
        'vendor sku',
        'supplier reference',
      ],
    ),
    // 5. Marca (Marca in Odoo)
    const ProductImportFieldDefinition(
      key: 'brand',
      label: 'Marca',
      isRecommended: true,
      sampleValue: 'VinaBike',
      aliases: ['brand', 'marca'],
    ),
    // 6. Imagen (Imagen in Odoo - exports as Base64)
    const ProductImportFieldDefinition(
      key: 'image_base64',
      label: 'Imagen',
      isRecommended: true,
      sampleValue: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA',
      aliases: [
        'image',
        'imagen',
        'image base64',
        'imagen base64',
        'imagen64',
        'imagen principal',
      ],
    ),
    // 7. Stock (Cantidad a la mano in Odoo)
    const ProductImportFieldDefinition(
      key: 'inventory_qty',
      label: 'Stock disponible',
      type: ProductImportFieldType.integer,
      isRecommended: true,
      sampleValue: '10',
      aliases: [
        'inventory',
        'stock',
        'cantidad',
        'cantidad a la mano',
        'existencias',
      ],
    ),
    // 8. Precio de venta (Precio de venta in Odoo)
    const ProductImportFieldDefinition(
      key: 'price',
      label: 'Precio venta (CLP)',
      type: ProductImportFieldType.decimal,
      isRecommended: true,
      sampleValue: '899000',
      aliases: [
        'price',
        'precio',
        'sale price',
        'precio venta',
        'precio de venta',
      ],
    ),
    // 9. Costo (Costo in Odoo)
    const ProductImportFieldDefinition(
      key: 'cost',
      label: 'Costo (CLP)',
      type: ProductImportFieldType.decimal,
      isRecommended: true,
      sampleValue: '540000',
      aliases: [
        'cost',
        'costo',
        'purchase cost',
        'precio costo',
      ],
    ),
    // 10. IVA (Impuesto de ventas in Odoo)
    const ProductImportFieldDefinition(
      key: 'tax_rate',
      label: 'IVA (%)',
      type: ProductImportFieldType.decimal,
      isRecommended: true,
      sampleValue: '19',
      aliases: [
        'iva',
        'tax',
        'tax rate',
        'impuesto',
        'impuesto de ventas',
      ],
    ),
    // Optional fields (not in Odoo export but useful for our system)
    const ProductImportFieldDefinition(
      key: 'image_url',
      label: 'Imagen URL',
      isRecommended: false,
      sampleValue: 'https://example.com/imagenes/mtb.jpg',
      aliases: [
        'image url',
        'imagen url',
      ],
    ),
    const ProductImportFieldDefinition(
      key: 'image_urls',
      label: 'Galería de imágenes (URLs separadas por coma)',
      isRecommended: false,
      sampleValue:
          'https://example.com/imagenes/mtb-1.jpg, https://example.com/imagenes/mtb-2.jpg',
      aliases: ['imagenes', 'images', 'gallery', 'image gallery'],
    ),
    const ProductImportFieldDefinition(
      key: 'image_gallery_base64',
      label: 'Galería de imágenes (Base64 separadas por coma)',
      isRecommended: false,
      sampleValue:
          'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ, data:image/png;base64,iVBORw0KGgoAAAANSUhEUg',
      aliases: [
        'imagenes base64',
        'images base64',
        'gallery base64',
        'imagen galeria base64',
      ],
    ),
    const ProductImportFieldDefinition(
      key: 'is_published',
      label: 'Publicado en tienda',
      type: ProductImportFieldType.boolean,
      isRecommended: false,
      sampleValue: 'TRUE',
      aliases: [
        'is_published',
        'published',
        'publicado',
        'publicado_en_tienda',
        'show_on_website',
        'mostrar_en_web',
      ],
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
    final structure = _buildTemplateStructure(includeOptional: includeOptional);
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
    final structure = _buildTemplateStructure(includeOptional: includeOptional);
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

  Future<Uint8List> exportProductsCsv({bool includeOptional = true}) async {
    final dataset = await _buildExportDataset(includeOptional: includeOptional);
    const converter = ListToCsvConverter();
    final rows = <List<String>>[
      dataset.headers,
      ...dataset.rows,
    ];
    final csv = converter.convert(rows);
    return Uint8List.fromList(utf8.encode(csv));
  }

  Future<Uint8List> exportProductsExcel({bool includeOptional = true}) async {
    final dataset = await _buildExportDataset(includeOptional: includeOptional);
    final excel = Excel.createExcel();
    const sheetName = 'Productos';
    final sheet = excel[sheetName];
    sheet.appendRow(_toTextRow(dataset.headers));
    for (final row in dataset.rows) {
      sheet.appendRow(_toTextRow(row));
    }
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      excel.delete(defaultSheet);
    }
    final encoded = excel.encode();
    if (encoded == null) {
      throw ProductImportException(
        'No se pudo generar el archivo Excel de exportación.',
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
    final importBatchId = const Uuid().v4();
    final importReference = 'product_import:$importBatchId';
    final errors = <ProductImportError>[];
    final supplierCache = <String, String>{};
    final supplierIdentityCache = <String, _ImportSupplierIdentity>{};

    for (var index = 0; index < rows.length; index++) {
      final rowNumber = index + 2;
      final row = rows[index];
      try {
        final stockHeader = fieldToHeader['inventory_qty'];
        final stockWasProvided = stockHeader != null &&
            (row[stockHeader]?.trim().isNotEmpty ?? false);

        // A set header has no independent stock ledger. Detect it before image
        // uploads, supplier creation, metadata updates, or stock RPCs so the
        // entire row fails without leaving partial side effects.
        if (stockWasProvided) {
          final skuHeader = fieldToHeader['sku'];
          final sku = skuHeader == null ? '' : (row[skuHeader] ?? '').trim();
          if (sku.isNotEmpty) {
            await _rejectStockImportForSetHeader(sku);
          }
        }

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
          stockWasProvided: stockWasProvided,
          importReference: importReference,
          idempotencyKey: '$importBatchId:$rowNumber',
          supplierIdentityCache: supplierIdentityCache,
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
    final taxRate = normalizeProductTaxRate(rawTaxRate);
    if (rawTaxRate != null && taxRate == null) {
      throw ProductImportRowException(
        'IVA debe ser 19, 0.19 o 0 (Exento).',
      );
    }
    final directImageUrl = valueFor('image_url');
    final directGalleryInputs = _parseList(valueFor('image_urls'));
    final primaryBase64 = valueFor('image_base64');
    final base64GalleryInputs = _parseList(valueFor('image_gallery_base64'));

    final combinedGalleryInputs = <String>[];
    if (directGalleryInputs != null) {
      combinedGalleryInputs.addAll(directGalleryInputs);
    }
    if (base64GalleryInputs != null) {
      combinedGalleryInputs.addAll(base64GalleryInputs);
    }

    final primaryCandidate = (primaryBase64 != null && primaryBase64.isNotEmpty)
        ? primaryBase64
        : directImageUrl;

    if (primaryBase64 != null &&
        primaryBase64.isNotEmpty &&
        directImageUrl != null &&
        directImageUrl.isNotEmpty) {
      combinedGalleryInputs.add(directImageUrl);
    }

    final rawProductType = (valueFor('product_type') ?? valueFor('type') ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final parsedProductType = (rawProductType == 'service' ||
            rawProductType == 'servicio' ||
            rawProductType == 'servicios')
        ? 'service'
        : 'product';

    final payload = <String, dynamic>{
      'sku': sku,
      'name': name,
      'category_name': valueFor('category_name'),
      'category': _guessCategory(valueFor('category_name')) ?? 'other',
      'brand': valueFor('brand'),
      'product_type': parsedProductType,
      // Services never track stock. Even if the import includes inventory_qty,
      // we store it as 0 to avoid confusing UI and stock adjustment triggers.
      'track_stock': parsedProductType != 'service',
      'inventory_qty': parsedProductType == 'service' ? 0 : inventoryQty,
      'stock_quantity': parsedProductType == 'service' ? 0 : inventoryQty,
      'price': price,
      'cost': cost,
      'price_currency': 'CLP',
      'cost_currency': 'CLP',
      'tax_rate': taxRate,
      'is_active': true,
      // Publication is opt-in and requires an explicit supported tax class.
      'is_published': false,
      'show_on_website': false,
    };

    final images = await _processImages(
      sku: sku,
      primaryInput: primaryCandidate,
      galleryInputs:
          combinedGalleryInputs.isEmpty ? null : combinedGalleryInputs,
    );

    if (images.primary != null) {
      payload['image_url'] = images.primary;
    }

    final hadGalleryInput = combinedGalleryInputs.isNotEmpty;
    if (images.gallery != null) {
      payload['image_urls'] = images.gallery;
    } else if (hadGalleryInput) {
      payload['image_urls'] = <String>[];
    }

    final supplierId = await _resolveSupplierId(
      explicitId: valueFor('supplier_id'),
      supplierName: valueFor('supplier_name'),
      cache: supplierCache,
      createIfMissing: createMissingSuppliers,
    );

    if (supplierId != null) {
      payload['supplier_id'] = supplierId;
      payload['supplier_name'] = valueFor('supplier_name');
    }

    // Add supplier code if provided
    final supplierCode = valueFor('supplier_code');
    if (supplierCode != null && supplierCode.toString().isNotEmpty) {
      payload['supplier_code'] = supplierCode;
    }

    final publishedRaw = valueFor('is_published') ?? valueFor('published');
    final parsedPublished = _parseBool(publishedRaw);
    if (parsedPublished != null) {
      if (parsedPublished && taxRate == null) {
        throw ProductImportRowException(
          'No se puede publicar sin clasificar IVA 19% o Exento.',
        );
      }
      payload['is_published'] = parsedPublished;
      payload['show_on_website'] = parsedPublished;
    }

    payload.removeWhere((_, value) => value == null);

    payload.putIfAbsent('unit', () => 'unit');
    // Services don't have stock levels.
    payload.putIfAbsent(
      'min_stock_level',
      () => (payload['product_type'] == 'service') ? 0 : 1,
    );

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
      selectColumns: 'id,name',
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

    final id = await _createMissingSupplier(supplierName.trim());
    if (id.trim().isEmpty) {
      throw StateError('Supplier command returned an empty durable id');
    }
    cache[normalized] = id;
    return id;
  }

  Future<bool> _upsertProduct({
    required Map<String, dynamic> payload,
    required bool allowUpdates,
    required bool stockWasProvided,
    required String importReference,
    required String idempotencyKey,
    required Map<String, _ImportSupplierIdentity> supplierIdentityCache,
  }) async {
    final sku = (payload['sku'] as String).trim();
    final existing = await _db.select('products', where: 'sku=$sku');
    final targetStock = (payload['inventory_qty'] as num?)?.round() ?? 0;
    if (existing.isEmpty) {
      final insertPayload = Map<String, dynamic>.from(payload)
        ..['inventory_qty'] = 0
        ..['stock_quantity'] = 0;

      final supplier = await _supplierIdentityForPayload(
        payload,
        cache: supplierIdentityCache,
      );
      if (supplier?.isAliExpress ?? false) {
        final reservedSku = await _reserveAliExpressSku(
          supplier: supplier!,
          operationKey: 'product-import:$idempotencyKey',
        );

        // The allocator serializes every migrated caller. This read catches a
        // legacy client that might still occupy the reservation before insert,
        // and fails closed rather than overwriting or updating that product.
        final occupied = await _db.select(
          'products',
          selectColumns: 'id',
          where: 'sku=$reservedSku',
          limit: 1,
        );
        if (occupied.isNotEmpty) {
          throw ProductImportRowException(
            'El SKU AliExpress reservado $reservedSku ya fue ocupado. '
            'Vuelve a intentar esta fila para obtener una reserva nueva.',
          );
        }
        insertPayload['sku'] = reservedSku;
      }

      final created = await _db.insert('products', insertPayload);
      if (targetStock > 0) {
        await _db.rpc('apply_product_import_stock', params: {
          'p_product_id': created['id'].toString(),
          'p_target_quantity': targetStock,
          'p_import_reference': importReference,
          'p_idempotency_key': idempotencyKey,
        });
      }
      return true;
    }

    if (!allowUpdates) {
      throw ProductImportRowException(
        'El SKU $sku ya existe y las actualizaciones están desactivadas.',
      );
    }

    if (stockWasProvided && existing.first['is_set'] == true) {
      throw ProductImportRowException(_setHeaderStockImportMessage(sku));
    }

    final productId = existing.first['id'].toString();
    final currentStock =
        (existing.first['inventory_qty'] as num?)?.round() ?? 0;
    final becomesNonStock = payload['product_type'] == 'service' ||
        payload['track_stock'] == false ||
        payload['purchase_treatment'] == 'workshop_consumable';
    if (currentStock > 0 && becomesNonStock) {
      throw ProductImportRowException(
        'El SKU $sku tiene stock. Conviértelo a servicio/consumible desde el flujo de conversión trazable antes de importarlo.',
      );
    }
    final updatePayload = Map<String, dynamic>.from(payload)
      ..remove('sku')
      ..remove('created_at')
      ..remove('inventory_qty')
      ..remove('stock_quantity');
    await _db.update('products', productId, updatePayload);
    if (stockWasProvided && !becomesNonStock) {
      await _db.rpc('apply_product_import_stock', params: {
        'p_product_id': productId,
        'p_target_quantity': targetStock,
        'p_import_reference': importReference,
        'p_idempotency_key': idempotencyKey,
      });
    }
    return false;
  }

  Future<void> _rejectStockImportForSetHeader(String sku) async {
    final existing = await _db.select(
      'products',
      selectColumns: 'id,sku,is_set',
      where: 'sku=$sku',
      limit: 1,
    );
    if (existing.isNotEmpty && existing.first['is_set'] == true) {
      throw ProductImportRowException(_setHeaderStockImportMessage(sku));
    }
  }

  String _setHeaderStockImportMessage(String sku) =>
      'El SKU $sku es un juego. Su stock se calcula desde sus componentes y '
      'no se puede importar en la cabecera; importa o ajusta las piezas del juego.';

  Future<_ImportSupplierIdentity?> _supplierIdentityForPayload(
    Map<String, dynamic> payload, {
    required Map<String, _ImportSupplierIdentity> cache,
  }) async {
    final supplierId = payload['supplier_id']?.toString().trim() ?? '';
    if (supplierId.isEmpty) return null;

    final cached = cache[supplierId];
    if (cached != null) return cached;

    final rows = await _db.select(
      'suppliers',
      selectColumns: 'id,name,aliases',
      where: 'id=$supplierId',
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ProductImportRowException(
        'El proveedor seleccionado ya no existe.',
      );
    }

    final row = rows.first;
    final name = row['name']?.toString().trim() ?? '';
    final aliases = row['aliases'] is Iterable
        ? (row['aliases'] as Iterable)
            .map((value) => value?.toString().trim() ?? '')
            .where((value) => value.isNotEmpty)
        : const Iterable<String>.empty();
    final identity = _ImportSupplierIdentity(
      id: supplierId,
      name: name,
      isAliExpress: <String>[name, ...aliases].any(_looksLikeAliExpress),
    );
    cache[supplierId] = identity;
    return identity;
  }

  Future<String> _reserveAliExpressSku({
    required _ImportSupplierIdentity supplier,
    required String operationKey,
  }) async {
    if (supplier.name.isEmpty) {
      throw ProductImportRowException(
        'El proveedor AliExpress no tiene un nombre válido.',
      );
    }
    final response = await _db.rpc(
      'reserve_aliexpress_skus',
      params: {
        'p_count': 1,
        'p_operation_key': operationKey,
        'p_supplier_id': supplier.id,
        'p_supplier_name': supplier.name,
      },
    );
    final rawSkus = response is Map ? response['skus'] : null;
    if (rawSkus is! List || rawSkus.length != 1) {
      throw ProductImportRowException(
        'La reserva de SKU AliExpress devolvió una respuesta inválida.',
      );
    }
    final reservedSku = rawSkus.single?.toString().trim() ?? '';
    if (!RegExp(r'^AE\d{4,}$').hasMatch(reservedSku)) {
      throw ProductImportRowException(
        'La reserva de SKU AliExpress devolvió un código inválido.',
      );
    }
    return reservedSku;
  }

  bool _looksLikeAliExpress(String value) {
    final normalized =
        value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return normalized.contains('aliexpress');
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

  bool? _parseBool(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final normalized = _normalize(trimmed);
    if (normalized.isEmpty) return null;

    const trueValues = {
      '1',
      'true',
      'si',
      'sí',
      'activo',
      'yes',
      'on',
    };

    const falseValues = {
      '0',
      'false',
      'no',
      'inactivo',
      'off',
    };

    if (trueValues.contains(normalized)) return true;
    if (falseValues.contains(normalized)) return false;
    return null;
  }

  List<String>? _parseList(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (trimmed.startsWith('data:')) {
      return [trimmed];
    }
    final separator = trimmed.contains(';') ? ';' : ',';
    final items = trimmed
        .split(separator)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return items.isEmpty ? null : items;
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

  Future<_ImageProcessingResult> _processImages({
    required String sku,
    String? primaryInput,
    List<String>? galleryInputs,
  }) async {
    String? primaryUrl;
    final galleryUrls = <String>[];
    final seenGallery = <String>{};

    Future<String?> resolve(String? raw, bool isPrimary, int index) async {
      if (raw == null) return null;
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;

      if (_looksLikeRemoteUrl(trimmed)) {
        return trimmed;
      }

      final decoded = _tryDecodeBase64(trimmed);
      if (decoded == null) {
        throw ProductImportRowException(
          'La imagen proporcionada para el SKU $sku no es una URL ni un valor base64 válido.',
        );
      }

      final folder = isPrimary
          ? StorageFolders.productMain
          : StorageFolders.productGallery;
      final sanitizedSku = _sanitizeForFileName(sku);
      final suffix = isPrimary ? 'main' : 'gallery_${index + 1}';
      final extension = decoded.extension;
      final fileName = '${sanitizedSku}_$suffix.$extension';

      try {
        final uploadedUrl = await ImageService.uploadBytes(
          bytes: decoded.bytes,
          fileName: fileName,
          bucket: StorageConfig.defaultBucket,
          folder: folder,
          contentType: decoded.mimeType,
        );

        if (uploadedUrl == null || uploadedUrl.isEmpty) {
          throw ProductImportRowException(
            'No se pudo obtener la URL pública para la imagen del SKU $sku.',
          );
        }

        return uploadedUrl;
      } catch (error) {
        throw ProductImportRowException(
          'Error al subir la imagen para el SKU $sku: $error',
        );
      }
    }

    primaryUrl = await resolve(primaryInput, true, 0);

    if (galleryInputs != null && galleryInputs.isNotEmpty) {
      for (var i = 0; i < galleryInputs.length; i++) {
        final resolved = await resolve(galleryInputs[i], false, i);
        if (resolved != null &&
            resolved.isNotEmpty &&
            seenGallery.add(resolved)) {
          galleryUrls.add(resolved);
        }
      }
    }

    if (primaryUrl == null && galleryUrls.isNotEmpty) {
      primaryUrl = galleryUrls.first;
    }

    final filteredGallery = galleryUrls
        .where((url) => primaryUrl == null || url != primaryUrl)
        .toList(growable: false);

    return _ImageProcessingResult(
      primary: primaryUrl,
      gallery: filteredGallery.isEmpty ? null : filteredGallery,
    );
  }

  _DecodedImage? _tryDecodeBase64(String input) {
    var data = input.trim();
    String? declaredMime;

    if (data.startsWith('data:')) {
      final commaIndex = data.indexOf(',');
      if (commaIndex == -1) {
        return null;
      }
      final header = data.substring(5, commaIndex); // remove 'data:'
      final headerParts = header.split(';');
      if (headerParts.isNotEmpty && headerParts.first.isNotEmpty) {
        declaredMime = headerParts.first;
      }
      data = data.substring(commaIndex + 1);
    }

    final normalized = data.replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) {
      return null;
    }

    try {
      final bytes = base64Decode(normalized);
      final mimeType = declaredMime ??
          lookupMimeType('', headerBytes: bytes) ??
          'image/jpeg';
      final extension = _extensionFromMime(mimeType);
      return _DecodedImage(
        bytes: bytes,
        extension: extension,
        mimeType: mimeType,
      );
    } on FormatException {
      return null;
    }
  }

  String _extensionFromMime(String? mimeType) {
    if (mimeType == null) {
      return 'jpg';
    }

    switch (mimeType.toLowerCase()) {
      case 'image/png':
        return 'png';
      case 'image/jpeg':
      case 'image/jpg':
        return 'jpg';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
    }

    if (mimeType.startsWith('image/')) {
      final parts = mimeType.split('/');
      if (parts.length == 2 && parts[1].isNotEmpty) {
        return parts[1];
      }
    }

    return 'jpg';
  }

  String _sanitizeForFileName(String input) {
    final sanitized = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return sanitized.isEmpty ? 'producto' : sanitized;
  }

  bool _looksLikeRemoteUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return false;
    }
    if (uri.hasScheme) {
      return uri.scheme == 'http' || uri.scheme == 'https';
    }
    return value.contains('/storage/v1/object/');
  }

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
    final sampleRow =
        fields.map((field) => field.sampleValue ?? '').toList(growable: false);

    return _TemplateStructure(headers: headers, sampleRow: sampleRow);
  }

  Future<_ExportDataset> _buildExportDataset({
    required bool includeOptional,
  }) async {
    final fields = includeOptional
        ? _fieldDefinitions
        : _fieldDefinitions
            .where((field) => field.required || field.isRecommended)
            .toList(growable: false);
    final headers = fields.map((field) => field.label).toList(growable: false);

    final products = await _db.select('products');
    if (products.isEmpty) {
      return _ExportDataset(headers: headers, rows: const []);
    }

    products.sort((a, b) {
      final nameA = (a['name']?.toString() ?? '').toLowerCase();
      final nameB = (b['name']?.toString() ?? '').toLowerCase();
      return nameA.compareTo(nameB);
    });

    final supplierNames = await _loadSupplierNames(products);
    final rows = <List<String>>[];

    for (final product in products) {
      final row = <String>[];
      for (final field in fields) {
        row.add(
          _valueForExport(
            field.key,
            product,
            supplierNames,
          ),
        );
      }
      rows.add(row);
    }

    return _ExportDataset(headers: headers, rows: rows);
  }

  Future<Map<String, String>> _loadSupplierNames(
    List<Map<String, dynamic>> products,
  ) async {
    final ids = products
        .map((product) => product['supplier_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) {
      return const {};
    }

    try {
      final rows = await _db.select(
        'suppliers',
        selectColumns: 'id,name',
        where: 'id',
        whereIn: ids.toList(),
      );
      final map = <String, String>{};
      for (final row in rows) {
        final id = row['id']?.toString();
        final name = row['name']?.toString();
        if (id != null && name != null) {
          map[id] = name;
        }
      }
      return map;
    } catch (_) {
      return const {};
    }
  }

  String _valueForExport(
    String key,
    Map<String, dynamic> product,
    Map<String, String> supplierNames,
  ) {
    switch (key) {
      case 'sku':
      case 'name':
      case 'brand':
        return product[key]?.toString() ?? '';
      case 'category_name':
        final categoryName = product['category_name'];
        if (categoryName != null && categoryName.toString().isNotEmpty) {
          return categoryName.toString();
        }
        final category = product['category'];
        return category?.toString() ?? '';
      case 'supplier_name':
        final supplierId = product['supplier_id']?.toString();
        if (supplierId != null && supplierId.isNotEmpty) {
          final lookup = supplierNames[supplierId];
          if (lookup != null && lookup.isNotEmpty) {
            return lookup;
          }
        }
        final fallback = product['supplier_name'] ??
            product['supplier'] ??
            product['supplier_display_name'];
        return fallback?.toString() ?? '';
      case 'supplier_code':
        return product['supplier_code']?.toString() ?? '';
      case 'image_url':
        return product['image_url']?.toString() ?? '';
      case 'image_urls':
        return _stringifyList(product['image_urls']);
      case 'image_base64':
      case 'image_gallery_base64':
        return '';
      case 'inventory_qty':
        final qty = product['inventory_qty'] ?? product['stock_quantity'];
        if (qty == null) return '';
        if (qty is num) {
          return qty.toInt().toString();
        }
        return qty.toString();
      case 'price':
      case 'cost':
        final value = product[key];
        if (value == null) return '';
        if (value is num) {
          return _trimZeros(value.toStringAsFixed(2));
        }
        return value.toString();
      case 'tax_rate':
        final value = product['tax_rate'];
        if (value == null) return '';
        if (value is num) {
          final percent = value > 1 ? value : value * 100;
          return _trimZeros(percent.toStringAsFixed(2));
        }
        return value.toString();
      case 'is_published':
        final published = product['is_published'] ?? product['published'];
        if (published is bool) {
          return published ? 'TRUE' : 'FALSE';
        }
        if (published == null) return '';
        return published.toString();
      default:
        final raw = product[key];
        if (raw == null) return '';
        if (raw is List) {
          return _stringifyList(raw);
        }
        return raw.toString();
    }
  }

  String _stringifyList(dynamic value) {
    if (value == null) return '';
    if (value is List) {
      return value
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .join(', ');
    }
    return value.toString();
  }

  String _trimZeros(String value) {
    if (!value.contains('.')) {
      return value;
    }
    var result = value;
    while (result.endsWith('0')) {
      result = result.substring(0, result.length - 1);
    }
    if (result.endsWith('.')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
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

class _ImportSupplierIdentity {
  const _ImportSupplierIdentity({
    required this.id,
    required this.name,
    required this.isAliExpress,
  });

  final String id;
  final String name;
  final bool isAliExpress;
}

class _TemplateStructure {
  _TemplateStructure({
    required this.headers,
    required this.sampleRow,
  });

  final List<String> headers;
  final List<String> sampleRow;
}

class _ExportDataset {
  const _ExportDataset({
    required this.headers,
    required this.rows,
  });

  final List<String> headers;
  final List<List<String>> rows;
}

class _ImageProcessingResult {
  const _ImageProcessingResult({
    this.primary,
    this.gallery,
  });

  final String? primary;
  final List<String>? gallery;
}

class _DecodedImage {
  const _DecodedImage({
    required this.bytes,
    required this.extension,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String extension;
  final String mimeType;
}
