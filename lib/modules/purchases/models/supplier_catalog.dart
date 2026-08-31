import 'dart:collection';

/// La ficha del proveedor: quién es, qué le compramos y qué más tiene.
///
/// Sale de `supplier_catalog_page_v1`, que **no** se cuelga de la necesidad
/// activa: el panel de evidencia contesta «por qué éste quedó acá para esta
/// línea» y esto contesta la pregunta siguiente —«abrí al proveedor, muéstrame
/// todo lo suyo»— para poder armarle un pedido sin salir del bloque.
class SupplierCatalogPage {
  SupplierCatalogPage({
    required this.supplier,
    required this.metrics,
    required List<SupplierCatalogItem> items,
    required this.total,
    required this.offset,
    this.matched = 0,
    this.needPhrase,
    this.droppedWords,
    this.droppedFilters,
  }) : items = UnmodifiableListView(items);

  final SupplierProfile supplier;
  final SupplierCatalogMetrics metrics;
  final UnmodifiableListView<SupplierCatalogItem> items;

  /// Cuántos hay en total, no cuántos vinieron. Publicar sólo lo devuelto hace
  /// que «40 productos» se lea como todo el catálogo cuando son 388.
  final int total;
  final int offset;

  /// Cuántos coinciden con lo que el operador venía buscando. Se entra a la
  /// ficha desde una necesidad concreta: ignorarla obligaba a volver a buscar a
  /// mano, en la misma pantalla a la que se llegó por eso.
  final int matched;

  /// La necesidad con la que se entró, para poder rotular el grupo con sus
  /// propias palabras y no con «coincidencias».
  final String? needPhrase;

  /// Qué tuvo que soltar la búsqueda para poder contestar. Sin publicarlo, el
  /// rótulo prometía una coincidencia exacta sobre un resultado ampliado: bajo
  /// «válvula Schrader» aparecía una cámara V/FRANCESA, que es justo la otra.
  final String? droppedWords;
  final String? droppedFilters;

  bool get matchWidened => droppedWords != null || droppedFilters != null;

  /// «se soltó la medida menos determinante». Una sola frase, la que
  /// corresponda.
  String? get widenedLabel => droppedFilters ?? droppedWords;

  bool get isEmpty => items.isEmpty;
  bool get hasMore => offset + items.length < total;

  factory SupplierCatalogPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return SupplierCatalogPage(
      supplier: SupplierProfile.fromJson(
        (json['supplier'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      metrics: SupplierCatalogMetrics.fromJson(
        (json['metrics'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((item) =>
                  SupplierCatalogItem.fromJson(item.cast<String, dynamic>()))
              .toList(growable: false)
          : const <SupplierCatalogItem>[],
      total: _int(json['total']),
      offset: _int(json['offset']),
      matched: _int(json['matched']),
      needPhrase: _text(json['needPhrase']),
      droppedWords: _text(json['droppedWords']),
      droppedFilters: _text(json['droppedFilters']),
    );
  }

  SupplierCatalogPage merge(SupplierCatalogPage next) {
    return SupplierCatalogPage(
      supplier: next.supplier,
      metrics: next.metrics,
      items: [...items, ...next.items],
      total: next.total,
      offset: offset,
      matched: next.matched,
      needPhrase: next.needPhrase,
      droppedWords: next.droppedWords,
      droppedFilters: next.droppedFilters,
    );
  }
}

class SupplierProfile {
  const SupplierProfile({
    required this.id,
    required this.name,
    required this.legalName,
    required this.rut,
    required this.city,
    required this.website,
    required this.imageUrl,
    required this.paymentTerms,
    required this.purchaseInstructions,
    required this.salesRepName,
    required this.salesRepPhone,
    required this.salesRepEmail,
    required this.hasPortalAccount,
  });

  final String id;
  final String name;
  final String? legalName;
  final String? rut;
  final String? city;
  final String? website;

  /// Ninguno de los 91 proveedores del taller tiene una hoy. La ficha usa el
  /// monograma como estado normal —no como error— y ofrece agregarla ahí mismo.
  final String? imageUrl;

  final String? paymentTerms;
  final String? purchaseInstructions;
  final String? salesRepName;

  /// Por dónde se le manda el pedido. Sólo 25 de 91 tienen teléfono: la
  /// pantalla lo necesita **antes** del último paso para poder ofrecer
  /// agregarlo en vez de fallar al final.
  final String? salesRepPhone;
  final String? salesRepEmail;
  final bool hasPortalAccount;

  bool get canReceiveMessage => (salesRepPhone ?? '').trim().isNotEmpty;

  /// «TE» — las mismas dos letras de la tabla, para que la ficha se reconozca
  /// como la fila de la que salió.
  String get monogram {
    final limpio = name.trim();
    if (limpio.isEmpty) return '··';
    final palabras =
        limpio.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (palabras.length == 1) {
      return palabras.first
          .substring(0, palabras.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return '${palabras[0][0]}${palabras[1][0]}'.toUpperCase();
  }

  factory SupplierProfile.fromJson(Map<String, dynamic> json) {
    return SupplierProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Proveedor',
      legalName: _text(json['legalName']),
      rut: _text(json['rut']),
      city: _text(json['city']),
      website: _text(json['website']),
      imageUrl: _text(json['imageUrl']),
      paymentTerms: _text(json['paymentTerms']),
      purchaseInstructions: _text(json['purchaseInstructions']),
      salesRepName: _text(json['salesRepName']),
      salesRepPhone: _text(json['salesRepPhone']),
      salesRepEmail: _text(json['salesRepEmail']),
      hasPortalAccount: json['hasPortalAccount'] == true,
    );
  }
}

class SupplierCatalogMetrics {
  const SupplierCatalogMetrics({
    required this.purchaseLines,
    required this.purchaseInvoices,
    required this.distinctProducts,
    required this.landedSpendNet,
    required this.purchasedUnits,
    required this.firstPurchaseAt,
    required this.lastPurchaseAt,
  });

  final int purchaseLines;
  final int purchaseInvoices;
  final int distinctProducts;
  final double landedSpendNet;
  final double purchasedUnits;
  final DateTime? firstPurchaseAt;
  final DateTime? lastPurchaseAt;

  bool get hasHistory => purchaseLines > 0;

  factory SupplierCatalogMetrics.fromJson(Map<String, dynamic> json) {
    return SupplierCatalogMetrics(
      purchaseLines: _int(json['purchaseLines']),
      purchaseInvoices: _int(json['purchaseInvoices']),
      distinctProducts: _int(json['distinctProducts']),
      landedSpendNet: _double(json['landedSpendNet']) ?? 0,
      purchasedUnits: _double(json['purchasedUnits']) ?? 0,
      firstPurchaseAt: _date(json['firstPurchaseAt']),
      lastPurchaseAt: _date(json['lastPurchaseAt']),
    );
  }
}

/// De dónde viene la fila. **No significan lo mismo y no se mezclan sin
/// decirlo**: un costo de ficha que nadie verificó, presentado como «lo que
/// pagamos», haría que el operador pida a un precio inventado.
enum SupplierCatalogOrigin {
  /// Se le compró: el costo es el aterrizado de la última factura.
  purchased,

  /// Está en su ficha pero nunca se le compró: el costo es el de catálogo.
  catalogued,
}

class SupplierCatalogItem {
  const SupplierCatalogItem({
    required this.productId,
    required this.name,
    required this.sku,
    required this.brand,
    required this.categoryPath,
    required this.origin,
    required this.timesPurchased,
    required this.totalQuantity,
    required this.lastPurchaseAt,
    required this.lastInvoiceNumber,
    required this.lastLandedUnitCostNet,
    required this.lastBaseUnitCostNet,
    required this.catalogCostNet,
    required this.available,
    required this.imageUrl,
    required this.matchesNeed,
  });

  final String productId;
  final String name;
  final String? sku;
  final String? brand;
  final String? categoryPath;
  final SupplierCatalogOrigin origin;
  final int timesPurchased;
  final double? totalQuantity;
  final DateTime? lastPurchaseAt;
  final String? lastInvoiceNumber;
  final double? lastLandedUnitCostNet;

  /// Lo que el proveedor cobró, sin el flete que pagamos aparte.
  final double? lastBaseUnitCostNet;
  final double? catalogCostNet;
  final double? available;

  /// 1.365 de los 1.612 productos del taller tienen foto. Acá la imagen es el
  /// caso común y su ausencia la excepción — al revés que la foto del
  /// proveedor, donde no hay ninguna y el monograma es lo normal.
  final String? imageUrl;

  /// Calza con lo que el operador venía buscando. Lo resuelve la MISMA función
  /// que usan el ranking y la evidencia: con un criterio propio, la ficha
  /// destacaría productos distintos de los que el ranking dijo que calzaban.
  final bool matchesNeed;

  bool get wasPurchased => origin == SupplierCatalogOrigin.purchased;

  /// El costo pagado, según el eje elegido. Con flete es lo que salió puesto en
  /// bodega; sin flete es lo que el proveedor cobró.
  double? paidUnitCost({required bool withFreight}) =>
      withFreight ? lastLandedUnitCostNet : lastBaseUnitCostNet;

  /// Lo que se propone cobrar en el pedido. Lo pagado manda; el costo de ficha
  /// sólo aparece cuando no hay nada pagado, y la pantalla lo rotula distinto.
  ///
  /// **El pedido se arma sobre el eje elegido**: proponerle al proveedor un
  /// precio que incluye nuestro flete es pedirle que cobre por algo que él no
  /// despacha.
  double? suggestedUnitCostNet({bool withFreight = false}) =>
      paidUnitCost(withFreight: withFreight) ??
      lastLandedUnitCostNet ??
      catalogCostNet;

  bool suggestedCostIsCatalog({bool withFreight = false}) =>
      paidUnitCost(withFreight: withFreight) == null &&
      lastLandedUnitCostNet == null &&
      catalogCostNet != null;

  factory SupplierCatalogItem.fromJson(Map<String, dynamic> json) {
    return SupplierCatalogItem(
      productId: json['productId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Producto',
      sku: _text(json['sku']),
      brand: _text(json['brand']),
      categoryPath: _text(json['categoryPath']),
      origin: json['origin'] == 'comprado'
          ? SupplierCatalogOrigin.purchased
          : SupplierCatalogOrigin.catalogued,
      timesPurchased: _int(json['timesPurchased']),
      totalQuantity: _double(json['totalQuantity']),
      lastPurchaseAt: _date(json['lastPurchaseAt']),
      lastInvoiceNumber: _text(json['lastInvoiceNumber']),
      lastLandedUnitCostNet: _double(json['lastLandedUnitCostNet']),
      lastBaseUnitCostNet: _double(json['lastBaseUnitCostNet']),
      catalogCostNet: _double(json['catalogCostNet']),
      available: _double(json['available']),
      imageUrl: _text(json['imageUrl']),
      matchesNeed: json['matchesNeed'] == true,
    );
  }
}

String? _text(Object? value) {
  final texto = value?.toString().trim();
  return texto == null || texto.isEmpty ? null : texto;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

DateTime? _date(Object? value) {
  final texto = value?.toString();
  if (texto == null || texto.isEmpty) return null;
  return DateTime.tryParse(texto);
}
