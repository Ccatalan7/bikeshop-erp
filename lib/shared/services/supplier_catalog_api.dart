import 'dart:convert';

import 'supplier_need_portal_search.dart';

/// Leer el catálogo de un proveedor por su **API**, no raspando su página.
///
/// **Por qué existe.** Medido el 2026-08-29: de 92 proveedores, 13 compran
/// repuestos, 10 tienen sitio y **uno solo** podía revisarse solo. El motor de
/// calce estaba completo; lo que faltaba era un adaptador escrito a mano por
/// tienda. Y el camino que teníamos —leer columnas de una `<table>`— no sirve
/// para WooCommerce ni PrestaShop, que dibujan una tarjeta por producto: dos
/// proveedores con catálogo público quedaban tan invisibles como uno sin sitio.
///
/// La salida obvia era configurar selectores CSS por tienda. **Es peor**: se
/// escriben a mano uno por uno, y se rompen cuando la tienda cambia de tema.
/// Las dos plataformas publican JSON, así que un lector por PLATAFORMA sirve
/// para cualquier tienda que corra sobre ella, sin configurar selectores:
///
/// - **WooCommerce** — `/wp-json/wc/store/v1/products?search=…`. Devuelve `sku`,
///   `prices.price`, `categories` y **`is_in_stock`**, y el total exacto en la
///   cabecera `X-WP-Total`. Verificado en `droppbike.cl`, donde además entrega
///   el precio que la página esconde tras «Regístrate para ver precio».
/// - **PrestaShop** — el mismo buscador con `&ajax=1`. Devuelve `reference`,
///   `price_amount` numérico y `pagination.total_items`. Verificado en
///   `derman.cl`.
///
/// Un total exacto no es un detalle: es lo que permite decir «revisé todo» sin
/// mentir. Sin él, la página 1 se lee igual que el catálogo completo.
enum SupplierCatalogApiKind {
  /// `/wp-json/wc/store/v1/products` — pública, sin credencial.
  wooCommerceStoreV1,

  /// El controlador de búsqueda de PrestaShop respondiendo JSON.
  prestashopSearchAjax,
}

SupplierCatalogApiKind? _kindFromWire(String? raw) => switch (raw?.trim()) {
      'woocommerce_store_v1' => SupplierCatalogApiKind.wooCommerceStoreV1,
      'prestashop_search_ajax' => SupplierCatalogApiKind.prestashopSearchAjax,
      _ => null,
    };

class SupplierCatalogApi {
  const SupplierCatalogApi({
    required this.kind,
    required this.baseUrl,
    this.pageSize = 50,
    this.maxPages = 6,
  });

  final SupplierCatalogApiKind kind;

  /// El origen de la tienda (`https://droppbike.cl`). Las rutas las pone el
  /// lector según la plataforma: una tienda no configura su propia API.
  final String baseUrl;
  final int pageSize;

  /// Tope de páginas por consulta. Recorrer un catálogo entero no es una
  /// respuesta: es un abuso del sitio de otro.
  final int maxPages;

  static SupplierCatalogApi? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    final kind = _kindFromWire(json['kind']?.toString());
    final base = json['base_url']?.toString().trim() ?? '';
    if (kind == null || base.isEmpty) return null;
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.isScheme('https')) return null;
    int bounded(String key, int fallback, int max) {
      final value = (json[key] as num?)?.round();
      if (value == null || value < 1 || value > max) return fallback;
      return value;
    }

    return SupplierCatalogApi(
      kind: kind,
      baseUrl: base.endsWith('/') ? base.substring(0, base.length - 1) : base,
      pageSize: bounded('page_size', 50, 100),
      maxPages: bounded('max_pages', 6, 40),
    );
  }

  Uri pageUri(String query, int page) => switch (kind) {
        SupplierCatalogApiKind.wooCommerceStoreV1 =>
          Uri.parse('$baseUrl/wp-json/wc/store/v1/products').replace(
            queryParameters: <String, String>{
              'search': query,
              'per_page': '$pageSize',
              'page': '$page',
            },
          ),
        SupplierCatalogApiKind.prestashopSearchAjax =>
          Uri.parse('$baseUrl/buscar').replace(
            queryParameters: <String, String>{
              'controller': 'search',
              's': query,
              'ajax': '1',
              'page': '$page',
            },
          ),
      };
}

/// Lo que una página de la API dijo: sus filas y **cuántas hay en total**.
class SupplierCatalogApiPage {
  const SupplierCatalogApiPage({
    required this.candidates,
    this.totalItems,
    this.totalPages,
  });

  final List<SupplierPortalCatalogCandidate> candidates;

  /// Cuántos productos declara el proveedor para esta consulta. `null` cuando
  /// no lo dice: entonces la cobertura no puede llamarse completa.
  final int? totalItems;
  final int? totalPages;
}

/// Convierte la respuesta de una plataforma en candidatos del dominio.
///
/// **Es una función pura sobre el cuerpo ya leído**: el transporte queda
/// afuera para poder probar esto contra respuestas reales grabadas, sin red.
SupplierCatalogApiPage parseSupplierCatalogApiPage({
  required SupplierCatalogApiKind kind,
  required String body,
  String? totalItemsHeader,
  String? totalPagesHeader,
}) {
  final decoded = jsonDecode(body);
  return switch (kind) {
    SupplierCatalogApiKind.wooCommerceStoreV1 => _parseWooCommerce(
        decoded,
        totalItemsHeader,
        totalPagesHeader,
      ),
    SupplierCatalogApiKind.prestashopSearchAjax => _parsePrestashop(decoded),
  };
}

int? _asInt(Object? raw) {
  if (raw is num) return raw.round();
  final text = raw?.toString().trim();
  if (text == null || text.isEmpty) return null;
  return int.tryParse(text);
}

double? _asMoney(Object? raw) {
  if (raw is num) return raw.toDouble();
  final text = raw?.toString().trim();
  if (text == null || text.isEmpty) return null;
  // `$7.900` en Chile es siete mil novecientos: el punto agrupa miles y el
  // separador decimal es la coma. Tomar el punto por decimal convertía un
  // precio en 7,9 y lo dejaba encabezando el ranking por barato.
  final digits = text.replaceAll(RegExp(r'[^0-9,]'), '').split(',').first;
  return digits.isEmpty ? null : double.tryParse(digits);
}

String _text(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  // Una tienda puede devolver el nombre con entidades HTML dentro del JSON.
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&nbsp;', ' ');
}

SupplierCatalogApiPage _parseWooCommerce(
  Object? decoded,
  String? totalItemsHeader,
  String? totalPagesHeader,
) {
  if (decoded is! List) {
    return const SupplierCatalogApiPage(
      candidates: <SupplierPortalCatalogCandidate>[],
    );
  }
  final candidates = <SupplierPortalCatalogCandidate>[];
  for (final entry in decoded) {
    if (entry is! Map) continue;
    final row = Map<String, Object?>.from(entry);
    final name = _text(row['name']);
    if (name.isEmpty) continue;
    final sku = _text(row['sku']);
    final prices = row['prices'];
    final price = prices is Map ? _asMoney(prices['price']) : null;
    final categories = <String>[
      for (final category in (row['categories'] as List? ?? const <Object?>[]))
        if (category is Map) _text(category['name']),
    ].where((value) => value.isNotEmpty).toList(growable: false);
    final inStock = row['is_in_stock'];
    final availability = row['stock_availability'];
    candidates.add(SupplierPortalCatalogCandidate(
      // Sin SKU el `id` de la tienda es la única identidad estable que hay.
      code: sku.isNotEmpty ? sku : _text(row['id']),
      name: name,
      priceNet: price,
      // La categoría que la tienda le puso entra al texto que se lee para
      // reconocer el objeto. No es una spec: es vocabulario del proveedor.
      rowText: <String>[
        name,
        ...categories,
        if (availability is Map) _text(availability['text']),
      ].join(' · '),
      technicalFacts: <String, Object?>{
        if (categories.isNotEmpty) 'supplier_categories': categories,
        if (inStock is bool) 'in_stock': inStock,
      },
    ));
  }
  return SupplierCatalogApiPage(
    candidates: candidates,
    totalItems: _asInt(totalItemsHeader),
    totalPages: _asInt(totalPagesHeader),
  );
}

SupplierCatalogApiPage _parsePrestashop(Object? decoded) {
  if (decoded is! Map) {
    return const SupplierCatalogApiPage(
      candidates: <SupplierPortalCatalogCandidate>[],
    );
  }
  final json = Map<String, Object?>.from(decoded);
  final products = json['products'];
  final candidates = <SupplierPortalCatalogCandidate>[];
  for (final entry in (products as List? ?? const <Object?>[])) {
    if (entry is! Map) continue;
    final row = Map<String, Object?>.from(entry);
    final name = _text(row['name']);
    if (name.isEmpty) continue;
    final reference = _text(row['reference']);
    final category = _text(row['category_name']);
    candidates.add(SupplierPortalCatalogCandidate(
      code: reference.isNotEmpty ? reference : _text(row['id_product']),
      name: name,
      priceNet: _asMoney(row['price_amount']) ?? _asMoney(row['price']),
      rowText: <String>[
        name,
        if (category.isNotEmpty) category,
      ].join(' · '),
      technicalFacts: <String, Object?>{
        if (category.isNotEmpty) 'supplier_categories': <String>[category],
      },
    ));
  }
  final pagination = json['pagination'];
  return SupplierCatalogApiPage(
    candidates: candidates,
    totalItems: pagination is Map ? _asInt(pagination['total_items']) : null,
    totalPages: pagination is Map ? _asInt(pagination['pages_count']) : null,
  );
}
