/// Las marcas de un proveedor y los proveedores de una marca
/// (`supplier_brands`, 20261103090000). La marca es la del catálogo
/// (`product_brands`): la misma de los productos, la tienda y las
/// cotizaciones, así que Shimano es una sola aunque la traigan varios.
library;

/// De dónde salió que el proveedor trae la marca.
enum SupplierBrandSource {
  /// Su catálogo: su sitio o su lista de marcas.
  catalog,

  /// Nuestros registros: se le compró, o hay productos que lo tienen como
  /// proveedor. La asignación nocturna las agrega sola.
  records,

  /// Una persona la agregó.
  manual;

  static SupplierBrandSource parse(Object? value) => switch (value) {
        'catalog' => SupplierBrandSource.catalog,
        'records' => SupplierBrandSource.records,
        _ => SupplierBrandSource.manual,
      };
}

/// Una marca que trae un proveedor, con lo que dicen nuestros registros.
class SupplierBrand {
  const SupplierBrand({
    required this.brandId,
    required this.name,
    this.logoUrl,
    this.official = false,
    this.source = SupplierBrandSource.manual,
    this.catalogUrl,
    this.catalogCheckedOn,
    this.addedFromPurchases = false,
    this.addedAt,
    this.products = 0,
    this.purchases = 0,
    this.purchaseLines = 0,
    this.lastPurchase,
  });

  factory SupplierBrand.fromJson(Map<String, dynamic> json) {
    final evidence = json['evidence'] is Map
        ? Map<String, dynamic>.from(json['evidence'] as Map)
        : const <String, dynamic>{};
    final catalog = evidence['catalog'] is Map
        ? Map<String, dynamic>.from(evidence['catalog'] as Map)
        : const <String, dynamic>{};
    final records = evidence['records'] is Map
        ? Map<String, dynamic>.from(evidence['records'] as Map)
        : const <String, dynamic>{};
    final lines = _int(json['purchase_lines']);
    return SupplierBrand(
      brandId: json['brand_id'].toString(),
      name: (json['name'] ?? '').toString(),
      logoUrl: _text(json['logo_url']),
      official: json['official'] == true,
      source: SupplierBrandSource.parse(json['source']),
      catalogUrl: _text(catalog['url']),
      catalogCheckedOn: _date(catalog['checked_on']),
      addedFromPurchases: _int(records['purchase_lines']) > 0,
      addedAt: _date(json['added_at']),
      products: _int(json['products']),
      // 20261103110000 cuenta documentos; antes sólo había líneas.
      purchases:
          json.containsKey('purchases') ? _int(json['purchases']) : lines,
      purchaseLines: lines,
      lastPurchase: _date(json['last_purchase']),
    );
  }

  final String brandId;
  final String name;

  /// Su logo (20261103120000), o null: se muestran sus iniciales.
  final String? logoUrl;

  /// Representante oficial de la marca.
  final bool official;
  final SupplierBrandSource source;

  /// El catálogo donde se vio, si salió o se confirmó en uno.
  final String? catalogUrl;
  final DateTime? catalogCheckedOn;

  /// Con [SupplierBrandSource.records]: se agregó porque se le compró (si
  /// no, porque hay productos que lo tienen como proveedor).
  final bool addedFromPurchases;
  final DateTime? addedAt;

  /// Productos de la marca en nuestro catálogo (de cualquier proveedor).
  final int products;

  /// Documentos de compra a este proveedor con la marca (recibidos o
  /// pagados), y sus líneas.
  final int purchases;
  final int purchaseLines;
  final DateTime? lastPurchase;

  bool get boughtFromThem => purchases > 0;

  static List<SupplierBrand> listFromJson(Object? value) => [
        if (value is List)
          for (final row in value)
            if (row is Map)
              SupplierBrand.fromJson(Map<String, dynamic>.from(row)),
      ];
}

/// Un proveedor que trae una marca (la página de la marca).
class BrandSupplier {
  const BrandSupplier({
    required this.supplierId,
    required this.name,
    this.imageUrl,
    this.isActive = true,
    this.official = false,
    this.source = SupplierBrandSource.manual,
    this.purchases = 0,
    this.lastPurchase,
  });

  factory BrandSupplier.fromJson(Map<String, dynamic> json) => BrandSupplier(
        supplierId: json['supplier_id'].toString(),
        name: (json['name'] ?? '').toString(),
        imageUrl: _text(json['image_url']),
        isActive: json['is_active'] != false,
        official: json['official'] == true,
        source: SupplierBrandSource.parse(json['source']),
        purchases: json.containsKey('purchases')
            ? _int(json['purchases'])
            : _int(json['purchase_lines']),
        lastPurchase: _date(json['last_purchase']),
      );

  final String supplierId;
  final String name;
  final String? imageUrl;
  final bool isActive;
  final bool official;
  final SupplierBrandSource source;

  /// Documentos de compra de la marca a este proveedor.
  final int purchases;
  final DateTime? lastPurchase;

  static List<BrandSupplier> listFromJson(Object? value) => [
        if (value is List)
          for (final row in value)
            if (row is Map)
              BrandSupplier.fromJson(Map<String, dynamic>.from(row)),
      ];
}

/// Las marcas de todos los proveedores, para buscarlos por marca.
class SupplierBrandIndex {
  const SupplierBrandIndex(this._bySupplier);

  factory SupplierBrandIndex.fromJson(Object? value) {
    final map = <String, ({List<String> brands, Set<String> official})>{};
    if (value is Map) {
      value.forEach((key, entry) {
        if (entry is! Map) return;
        final brands = [
          for (final name in (entry['brands'] as List? ?? const []))
            name.toString(),
        ];
        final official = {
          for (final name in (entry['official'] as List? ?? const []))
            name.toString(),
        };
        map[key.toString()] = (brands: brands, official: official);
      });
    }
    return SupplierBrandIndex(map);
  }

  static const empty = SupplierBrandIndex({});

  final Map<String, ({List<String> brands, Set<String> official})> _bySupplier;

  List<String> brandsOf(String supplierId) =>
      _bySupplier[supplierId]?.brands ?? const [];

  bool isOfficial(String supplierId, String brand) =>
      _bySupplier[supplierId]?.official.contains(brand) ?? false;
}

/// Una marca del catálogo que se puede asignar.
class SupplierBrandOption {
  const SupplierBrandOption({required this.id, required this.name});

  final String id;
  final String name;
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _int(Object? value) => switch (value) {
      final int number => number,
      final num number => number.toInt(),
      final String text => int.tryParse(text) ?? 0,
      _ => 0,
    };

DateTime? _date(Object? value) {
  final text = _text(value);
  return text == null ? null : DateTime.tryParse(text);
}
