/// Las marcas como las lee Inventario › Marcas y la página de una marca
/// (`brand_directory_v1` y `brand_page_v1`, 20261115101500).
///
/// El dueño pidió (2026-11-14) rehacer la lista en lista y tarjetas, y que el
/// buscador lleve a la marca para «ver todo eso». Lo que una marca dice en el
/// taller no es su país ni su sitio —279 de 280 no los tienen—, sino cuántos
/// productos hay, cuánto se vende, quién la trae y dónde se usó.
library;

import '../../../shared/utils/bike_finder_search.dart';
import 'brand_models.dart';

/// Quién trae una marca, como lo nombra el directorio.
class BrandDirectorySupplier {
  const BrandDirectorySupplier({
    required this.id,
    required this.name,
    this.official = false,
    this.imageUrl,
  });

  factory BrandDirectorySupplier.fromJson(Map<String, dynamic> json) =>
      BrandDirectorySupplier(
        id: '${json['id']}',
        name: _text(json['name']) ?? 'Proveedor',
        official: json['official'] == true,
        imageUrl: _text(json['image_url']),
      );

  final String id;
  final String name;

  /// Representante oficial de la marca en Chile.
  final bool official;
  final String? imageUrl;
}

/// Una marca del directorio con sus cifras.
class BrandDirectoryEntry {
  const BrandDirectoryEntry({
    required this.id,
    required this.name,
    this.logoUrl,
    this.isActive = true,
    this.shared = false,
    this.products = 0,
    this.inStock = 0,
    this.units = 0,
    this.stockCost = 0,
    this.onWeb = 0,
    this.sold12m = 0,
    this.lastSale,
    this.images = const <String>[],
    this.supplier,
    this.supplierCount = 0,
  });

  factory BrandDirectoryEntry.fromJson(Map<String, dynamic> json) =>
      BrandDirectoryEntry(
        id: '${json['id']}',
        name: _text(json['name']) ?? 'Marca sin nombre',
        logoUrl: _text(json['logo_url']),
        isActive: json['is_active'] != false,
        shared: json['shared'] == true,
        products: _int(json['products']),
        inStock: _int(json['in_stock']),
        units: _num(json['units']),
        stockCost: _num(json['stock_cost']),
        onWeb: _int(json['on_web']),
        sold12m: _num(json['sold_12m']),
        lastSale: _date(json['last_sale']),
        images: [
          if (json['images'] is List)
            for (final image in json['images'] as List)
              if (_text(image) != null) _text(image)!,
        ],
        supplier: json['supplier'] is Map
            ? BrandDirectorySupplier.fromJson(
                Map<String, dynamic>.from(json['supplier'] as Map))
            : null,
        supplierCount: _int(json['supplier_count']),
      );

  final String id;
  final String name;
  final String? logoUrl;
  final bool isActive;

  /// Del catálogo compartido: sus datos los cuida Viñabike, no el taller.
  final bool shared;

  /// Productos activos de la marca.
  final int products;

  /// De esos, los que tienen stock.
  final int inStock;
  final num units;

  /// Lo que vale el stock a costo, en pesos.
  final num stockCost;
  final int onWeb;

  /// Unidades vendidas en los últimos 12 meses, menos las anuladas.
  final num sold12m;
  final DateTime? lastSale;

  /// Hasta tres fotos de sus productos más vendidos.
  final List<String> images;

  /// El oficial, o al que más se le compró.
  final BrandDirectorySupplier? supplier;

  /// Todos los que la traen o a los que se les compró.
  final int supplierCount;

  bool get hasLogo => (logoUrl ?? '').isNotEmpty;

  /// Los demás proveedores, sin contar el que se nombra.
  int get otherSuppliers => supplier == null ? 0 : supplierCount - 1;

  static List<BrandDirectoryEntry> listFromJson(Object? value) => [
        if (value is List)
          for (final row in value)
            if (row is Map)
              BrandDirectoryEntry.fromJson(Map<String, dynamic>.from(row)),
      ];
}

/// Las vistas de la lista, con su conteo junto a la pestaña.
enum BrandListView {
  /// Por defecto: 96 de las 280 marcas no tienen productos (2026-11-14).
  withProducts,
  inStock,

  /// Para completar logos: 141 marcas sin logo el 2026-11-14.
  noLogo,
  all;

  String get label => switch (this) {
        BrandListView.withProducts => 'Con productos',
        BrandListView.inStock => 'Con stock',
        BrandListView.noLogo => 'Sin logo',
        BrandListView.all => 'Todas',
      };

  bool includes(BrandDirectoryEntry entry) => switch (this) {
        BrandListView.withProducts => entry.products > 0,
        BrandListView.inStock => entry.inStock > 0,
        BrandListView.noLogo => !entry.hasLogo,
        BrandListView.all => true,
      };
}

/// Cómo se ordena la lista. Cada columna ordena por su cifra.
enum BrandSort {
  name,
  supplier,
  products,
  inStock,
  stockCost,
  sold,
  lastSale,
  onWeb;

  /// Una cifra se lee de más a menos; un nombre, de la A a la Z.
  bool get descendingFirst =>
      this != BrandSort.name && this != BrandSort.supplier;

  String get label => switch (this) {
        BrandSort.name => 'Marca',
        BrandSort.supplier => 'Proveedor',
        BrandSort.products => 'Productos',
        BrandSort.inStock => 'Con stock',
        BrandSort.stockCost => 'Stock a costo',
        BrandSort.sold => 'Vendidas 12 m',
        BrandSort.lastSale => 'Última venta',
        BrandSort.onWeb => 'En la web',
      };

  /// Cómo se dice el orden al pie de la lista.
  String phrase({required bool descending}) => switch (this) {
        BrandSort.name => descending ? 'de la Z a la A' : 'de la A a la Z',
        BrandSort.supplier =>
          descending ? 'por proveedor, de la Z a la A' : 'por proveedor',
        BrandSort.products => descending
            ? 'las de más productos primero'
            : 'las de menos productos primero',
        BrandSort.inStock => descending
            ? 'las de más productos con stock primero'
            : 'las de menos productos con stock primero',
        BrandSort.stockCost => descending
            ? 'el stock más caro primero'
            : 'el stock más barato primero',
        BrandSort.sold => descending
            ? 'de más a menos vendidas'
            : 'de menos a más vendidas',
        BrandSort.lastSale => descending
            ? 'la venta más reciente primero'
            : 'la venta más antigua primero',
        BrandSort.onWeb => descending
            ? 'las de más productos en la web primero'
            : 'las de menos productos en la web primero',
      };
}

/// Las marcas de una vista, ordenadas. Un empate se rompe por nombre, para
/// que la lista no se reordene sola entre dos lecturas.
List<BrandDirectoryEntry> brandDirectoryRows(
  List<BrandDirectoryEntry> entries, {
  required BrandListView view,
  required BrandSort sort,
  required bool descending,
}) {
  final rows = [
    for (final entry in entries)
      if (view.includes(entry)) entry,
  ];
  int byName(BrandDirectoryEntry a, BrandDirectoryEntry b) {
    final byLower = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byLower != 0 ? byLower : a.id.compareTo(b.id);
  }

  int compareNum(num a, num b) => descending ? b.compareTo(a) : a.compareTo(b);
  rows.sort((a, b) {
    final primary = switch (sort) {
      BrandSort.name => descending ? byName(b, a) : byName(a, b),
      BrandSort.supplier => _compareSupplier(a, b, descending: descending),
      BrandSort.products => compareNum(a.products, b.products),
      BrandSort.inStock => compareNum(a.inStock, b.inStock),
      BrandSort.stockCost => compareNum(a.stockCost, b.stockCost),
      BrandSort.sold => compareNum(a.sold12m, b.sold12m),
      BrandSort.lastSale => _compareDates(a.lastSale, b.lastSale,
          descending: descending),
      BrandSort.onWeb => compareNum(a.onWeb, b.onWeb),
    };
    return primary != 0 ? primary : byName(a, b);
  });
  return rows;
}

/// Sin proveedor va al final en los dos sentidos: no es la «A» de nadie.
int _compareSupplier(
  BrandDirectoryEntry a,
  BrandDirectoryEntry b, {
  required bool descending,
}) {
  final left = a.supplier?.name.toLowerCase();
  final right = b.supplier?.name.toLowerCase();
  if (left == null && right == null) return 0;
  if (left == null) return 1;
  if (right == null) return -1;
  return descending ? right.compareTo(left) : left.compareTo(right);
}

/// Sin venta va al final en los dos sentidos.
int _compareDates(DateTime? a, DateTime? b, {required bool descending}) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return descending ? b.compareTo(a) : a.compareTo(b);
}

/// Lo que coincide con la búsqueda: por el nombre de la marca o por el del
/// proveedor que la trae («teknobike» trae sus marcas). Es la búsqueda que
/// reemplazó al filtro por proveedor.
List<BrandDirectoryEntry> searchBrandDirectory(
  List<BrandDirectoryEntry> rows,
  String query,
) {
  final normalized = normalizeBikeFinderSearch(query).trim();
  if (normalized.isEmpty) return rows;
  final scored = <(BrandDirectoryEntry, int, int)>[];
  for (var index = 0; index < rows.length; index++) {
    final entry = rows[index];
    final score = bikeFinderRelationalSearchScore(
      query: normalized,
      fields: [
        BikeFinderSearchField(entry.name, weight: 135),
        BikeFinderSearchField(entry.supplier?.name, weight: 90),
      ],
    );
    if (score > 0) scored.add((entry, score, index));
  }
  // El mejor calce primero; entre iguales, el orden de la vista.
  scored.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    return byScore != 0 ? byScore : a.$3.compareTo(b.$3);
  });
  return [for (final hit in scored) hit.$1];
}

/// Un producto activo de la marca, en su página.
class BrandPageProduct {
  const BrandPageProduct({
    required this.id,
    required this.name,
    this.sku,
    this.price,
    this.stock,
    this.image,
    this.sold12m = 0,
    this.lastSale,
    this.onWeb = false,
  });

  factory BrandPageProduct.fromJson(Map<String, dynamic> json) =>
      BrandPageProduct(
        id: '${json['id']}',
        name: _text(json['name']) ?? 'Producto sin nombre',
        sku: _text(json['sku']),
        price: json['price'] is num ? json['price'] as num : null,
        stock: json['stock_quantity'] is num
            ? json['stock_quantity'] as num
            : null,
        image: _text(json['image']),
        sold12m: _num(json['sold_12m']),
        lastSale: _date(json['last_sale']),
        onWeb: json['on_web'] == true,
      );

  final String id;
  final String name;
  final String? sku;
  final num? price;
  final num? stock;
  final String? image;
  final num sold12m;
  final DateTime? lastSale;
  final bool onWeb;

  bool get hasStock => (stock ?? 0) > 0;
}

/// Un proveedor de la marca en su página: los que la traen y a los que se
/// les compró.
class BrandPageSupplier {
  const BrandPageSupplier({
    required this.supplierId,
    required this.name,
    this.imageUrl,
    this.isActive = true,
    this.official = false,
    this.carries = false,
    this.purchases = 0,
    this.units = 0,
    this.lastPurchase,
  });

  factory BrandPageSupplier.fromJson(Map<String, dynamic> json) =>
      BrandPageSupplier(
        supplierId: '${json['supplier_id']}',
        name: _text(json['name']) ?? 'Proveedor',
        imageUrl: _text(json['image_url']),
        isActive: json['is_active'] != false,
        official: json['official'] == true,
        carries: json['carries'] == true,
        purchases: _int(json['purchases']),
        units: _num(json['units']),
        lastPurchase: _date(json['last_purchase']),
      );

  final String supplierId;
  final String name;
  final String? imageUrl;
  final bool isActive;
  final bool official;

  /// Está entre los que traen la marca (`supplier_brands`).
  final bool carries;

  /// Documentos de compra recibidos o pagados de la marca a este proveedor.
  final int purchases;
  final num units;
  final DateTime? lastPurchase;
}

/// Un trabajo que usó productos de la marca.
class BrandPageJob {
  const BrandPageJob({
    required this.id,
    required this.number,
    this.status,
    this.arrivalDate,
    this.deliveredAt,
    this.customerName,
    this.bike,
    this.lines = 0,
    this.firstItem,
  });

  factory BrandPageJob.fromJson(Map<String, dynamic> json) => BrandPageJob(
        id: '${json['id']}',
        number: _text(json['job_number']) ?? 'Trabajo',
        status: _text(json['status']),
        arrivalDate: _date(json['arrival_date']),
        deliveredAt: _date(json['delivered_at']),
        customerName: _text(json['customer_name']),
        bike: _text(json['bike']),
        lines: _int(json['lines']),
        firstItem: _text(json['first_item']),
      );

  final String id;
  final String number;

  /// Como lo guarda el trabajo: `ENTREGADO`, `EN_PROCESO`…
  final String? status;
  final DateTime? arrivalDate;
  final DateTime? deliveredAt;
  final String? customerName;
  final String? bike;

  /// Líneas del trabajo con productos de la marca.
  final int lines;
  final String? firstItem;

  /// «Entregado», «En proceso»: el estado como frase, sin reinterpretarlo.
  String? get statusLabel {
    final raw = status?.trim();
    if (raw == null || raw.isEmpty) return null;
    final words = raw.toLowerCase().replaceAll('_', ' ');
    return words[0].toUpperCase() + words.substring(1);
  }
}

/// Todo lo que muestra la página de una marca, de una sola lectura.
class BrandPageData {
  const BrandPageData({
    required this.brand,
    required this.totals,
    this.products = const <BrandPageProduct>[],
    this.suppliers = const <BrandPageSupplier>[],
    this.jobsTotal = 0,
    this.recentJobs = const <BrandPageJob>[],
    this.filesTotal = 0,
    this.recentFiles = const <Map<String, dynamic>>[],
  });

  factory BrandPageData.fromJson(Map<String, dynamic> json) {
    final brandJson = Map<String, dynamic>.from(json['brand'] as Map);
    final jobs = json['jobs'] is Map
        ? Map<String, dynamic>.from(json['jobs'] as Map)
        : const <String, dynamic>{};
    final files = json['files'] is Map
        ? Map<String, dynamic>.from(json['files'] as Map)
        : const <String, dynamic>{};
    final totals = json['totals'] is Map
        ? Map<String, dynamic>.from(json['totals'] as Map)
        : const <String, dynamic>{};
    final brand = ProductBrand.fromJson(brandJson);
    return BrandPageData(
      brand: brand,
      totals: BrandDirectoryEntry(
        id: brand.id ?? '',
        name: brand.name,
        logoUrl: brand.logoUrl,
        isActive: brand.isActive,
        shared: brandJson['shared'] == true,
        products: _int(totals['products']),
        inStock: _int(totals['in_stock']),
        units: _num(totals['units']),
        stockCost: _num(totals['stock_cost']),
        onWeb: _int(totals['on_web']),
        sold12m: _num(totals['sold_12m']),
        lastSale: _date(totals['last_sale']),
      ),
      products: [
        if (json['products'] is List)
          for (final row in json['products'] as List)
            if (row is Map)
              BrandPageProduct.fromJson(Map<String, dynamic>.from(row)),
      ],
      suppliers: [
        if (json['suppliers'] is List)
          for (final row in json['suppliers'] as List)
            if (row is Map)
              BrandPageSupplier.fromJson(Map<String, dynamic>.from(row)),
      ],
      jobsTotal: _int(jobs['total']),
      recentJobs: [
        if (jobs['recent'] is List)
          for (final row in jobs['recent'] as List)
            if (row is Map)
              BrandPageJob.fromJson(Map<String, dynamic>.from(row)),
      ],
      filesTotal: _int(files['total']),
      recentFiles: [
        if (files['recent'] is List)
          for (final row in files['recent'] as List)
            if (row is Map) Map<String, dynamic>.from(row),
      ],
    );
  }

  final ProductBrand brand;

  /// Las cifras de la marca, las mismas que muestra el directorio.
  final BrandDirectoryEntry totals;
  final List<BrandPageProduct> products;
  final List<BrandPageSupplier> suppliers;
  final int jobsTotal;
  final List<BrandPageJob> recentJobs;
  final int filesTotal;

  /// Filas de `messaging_attachments` con la misma forma que lee el buscador,
  /// para nombrar y abrir cada archivo con las mismas palabras.
  final List<Map<String, dynamic>> recentFiles;

  bool get shared => totals.shared;
}

/// «hoy», «ayer», «10 nov», o «16 sep 2025» si no es de este año.
String brandDayLabel(DateTime date, {DateTime? today}) {
  final now = today ?? DateTime.now();
  final local = date.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final base = DateTime(now.year, now.month, now.day);
  final days = base.difference(day).inDays;
  if (days == 0) return 'hoy';
  if (days == 1) return 'ayer';
  final month = _months[local.month - 1];
  return local.year == now.year
      ? '${local.day} $month'
      : '${local.day} $month ${local.year}';
}

/// Un entero con puntos de miles: 1.001.085.
String brandCount(num value) {
  final rounded = value.round();
  final negative = rounded < 0;
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
    buffer.write(digits[index]);
  }
  return '${negative ? '-' : ''}$buffer';
}

/// Pesos chilenos: $1.001.085.
String brandMoney(num value) => '\$${brandCount(value)}';

/// «1 producto», «30 productos».
String brandPlural(num count, String singular, [String? plural]) =>
    count == 1
        ? '1 $singular'
        : '${brandCount(count)} ${plural ?? '${singular}s'}';

const List<String> _months = <String>[
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String? _text(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

int _int(Object? value) => switch (value) {
      int value => value,
      num value => value.round(),
      String value => int.tryParse(value) ?? num.tryParse(value)?.round() ?? 0,
      _ => 0,
    };

num _num(Object? value) => switch (value) {
      num value => value,
      String value => num.tryParse(value) ?? 0,
      _ => 0,
    };

DateTime? _date(Object? value) {
  final text = _text(value);
  return text == null ? null : DateTime.tryParse(text);
}
