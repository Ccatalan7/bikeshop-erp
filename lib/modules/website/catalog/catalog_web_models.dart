import 'package:flutter/material.dart';

import '../../../shared/utils/chilean_utils.dart';

/// Where an item stands in the store, as `catalog_web_items_v1` decides it
/// with the same rule the store lists by (`catalog_product_web_block_v1`).
enum CatalogItemState {
  /// Listed, bought and sent to Google.
  selling,

  /// Out of stock: the page stays with «Agotado» and no cart.
  soldOut,

  /// Marked for the web but something blocks it (photo, price, name…).
  blocked,

  /// «Vender en la web» off, or the product is inactive.
  hidden,

  /// A workshop consumable: never sold online.
  workshop;

  static CatalogItemState fromCode(String? code) => switch (code) {
        'venta' => selling,
        'agotado' => soldOut,
        'falta' => blocked,
        'taller' => workshop,
        _ => hidden,
      };

  String get label => switch (this) {
        selling => 'En venta',
        soldOut => 'Agotado',
        blocked => 'Falta algo',
        hidden => 'Oculto',
        workshop => 'Taller',
      };

  String get pluralLabel => switch (this) {
        selling => 'En venta',
        soldOut => 'Agotados',
        blocked => 'Falta algo',
        hidden => 'Ocultos',
        workshop => 'Taller',
      };

  /// What the state means, as the tab says it.
  String get meaning => switch (this) {
        selling => 'Se ven en la tienda, en Google y se pueden comprar.',
        soldOut =>
          'Ficha visible con «Agotado» y sin carrito. Vuelven solos a venta cuando entra stock.',
        blocked =>
          'Marcados para vender, pero no salen. Arriba los que tienen stock: son ventas que se están perdiendo.',
        hidden =>
          '«Vender en la web» apagado o producto inactivo. No se ven en ningún lado.',
        workshop =>
          'Consumibles del taller: se gastan en los trabajos y nunca van a la tienda.',
      };
}

/// What kind of item it is, as the workshop thinks of it.
enum CatalogItemKind {
  product,
  kit,
  service,
  consumable;

  static CatalogItemKind fromCode(String? code) => switch (code) {
        'kit' => kit,
        'service' => service,
        'consumable' => consumable,
        _ => product,
      };

  String get label => switch (this) {
        product => 'Producto de venta',
        kit => 'Kit',
        service => 'Servicio',
        consumable => 'Consumible del taller',
      };

  bool get sellsGoods => this == product || this == kit;
}

/// How a price shows in the store (`products.website_price_mode`).
enum CatalogPriceMode {
  exact,
  from,
  quote;

  static CatalogPriceMode fromCode(String? code) => switch (code) {
        'from' => from,
        'quote' => quote,
        _ => exact,
      };

  String get code => name;

  String get label => switch (this) {
        exact => 'Precio exacto',
        from => 'Desde',
        quote => 'A cotizar',
      };
}

/// The rule's reason codes, in plain words.
abstract final class CatalogReasons {
  static String block(String? code, {num? minPrice}) => switch (code) {
        'workshop_consumable' => 'Consumible del taller: no se vende online',
        'inactive' => 'Producto inactivo',
        'web_off' => '«Vender en la web» apagado',
        'missing_tax' => 'Sin IVA clasificado',
        'missing_price' => 'Sin precio',
        'below_cost' => minPrice == null
            ? 'Bajo el costo con IVA'
            : 'Bajo el costo con IVA (mínimo ${ChileanUtils.formatCurrency(minPrice.toDouble())})',
        'missing_image' => 'Falta foto',
        'missing_web_name' => 'Falta nombre para la tienda',
        'missing_description' => 'Falta descripción',
        'missing_brand' => 'Falta marca',
        'category_hidden' => 'Su categoría no está en el menú',
        null => 'Todo en orden',
        // A step the app does not name yet still says it does not sell.
        _ => 'No sale a la venta',
      };

  /// The «Por resolver» groups, by what is at stake first.
  static const issueOrder = <String>[
    'missing_image',
    'below_cost',
    'missing_price',
    'missing_tax',
    'counter_consumable',
    'gtin_in_sku',
    'bulk_pack',
    'missing_web_name',
    'no_web_name',
    'no_brand',
    'missing_brand',
    'missing_description',
    'category_hidden',
    'empty_record',
  ];

  static String issueTitle(String code) => switch (code) {
        'missing_image' => 'Marcados para vender, pero sin foto',
        'below_cost' => 'Precio bajo el costo con IVA',
        'missing_price' => 'Sin precio',
        'missing_tax' => 'Sin clasificación de IVA',
        'counter_consumable' =>
          'Consumibles del taller que también se venden al mesón',
        'gtin_in_sku' => 'Códigos de barra reales guardados como SKU',
        'bulk_pack' => 'Paquetes del taller a la venta como un producto',
        'missing_web_name' => 'Sin nombre para la tienda: no salen',
        'no_web_name' => 'A la venta con el nombre del proveedor',
        'no_brand' => 'A la venta sin marca',
        'missing_brand' => 'Sin marca: no salen',
        'missing_description' => 'Sin descripción: no salen',
        'category_hidden' => 'En una categoría que no está en el menú',
        'empty_record' => 'Fichas que no son productos',
        _ => code,
      };

  static String issueShort(String code) => switch (code) {
        'missing_image' => 'Sin foto',
        'below_cost' => 'Bajo costo',
        'missing_price' => 'Sin precio',
        'missing_tax' => 'Sin IVA',
        'counter_consumable' => 'Consumibles al mesón',
        'gtin_in_sku' => 'GTIN en el SKU',
        'bulk_pack' => 'Paquetes a granel',
        'missing_web_name' => 'Sin nombre web',
        'no_web_name' => 'Nombre de proveedor',
        'no_brand' => 'Sin marca',
        'missing_brand' => 'Sin marca',
        'missing_description' => 'Sin descripción',
        'category_hidden' => 'Categoría oculta',
        'empty_record' => 'No son productos',
        _ => code,
      };

  static String issueExplanation(String code) => switch (code) {
        'missing_image' =>
          'No aparecen en la tienda. Arriba los que tienen stock: son ventas que se están perdiendo.',
        'below_cost' =>
          'No salen a la venta: cada venta perdería plata. Si es a propósito, márcalo como liquidación con fecha de término.',
        'missing_price' => 'Un ítem a \$0 no se publica.',
        'missing_tax' =>
          'Se ven en la tienda, pero el checkout los rechaza y Google Merchant no los recibe.',
        'counter_consumable' =>
          'Venderlos al mesón está bien y no cambia nada. Sólo si los quieres en la web hay que convertirlos en producto de venta.',
        'gtin_in_sku' =>
          'Tienen 12, 13 o 14 dígitos y el dígito verificador correcto. Google los usa para mostrar el producto junto a los demás vendedores. Copiarlos no cambia el SKU y se puede deshacer.',
        'bulk_pack' =>
          'Rollos, gruesas, cajas y packs. ¿Se venden así, o son insumo del taller?',
        'missing_web_name' =>
          'El ajuste de la tienda pide nombre para la tienda y estos no lo tienen.',
        'no_web_name' =>
          'El cliente y Google leen el nombre del proveedor, a veces en mayúsculas.',
        'no_brand' => 'Google y los filtros de la tienda usan la marca.',
        'missing_brand' => 'El ajuste de la tienda pide marca.',
        'missing_description' => 'El ajuste de la tienda pide descripción.',
        'category_hidden' =>
          'El ajuste de la tienda pide que la categoría esté en el menú.',
        'empty_record' =>
          'Activas, a \$0, sin costo, sin stock y nunca vendidas ni compradas: ensucian el catálogo y los buscadores del ERP.',
        _ => '',
      };
}

/// One row of `catalog_web_items_v1`.
@immutable
class CatalogWebItem {
  const CatalogWebItem({
    required this.id,
    required this.name,
    required this.sku,
    required this.kind,
    required this.state,
    required this.price,
    required this.webPrice,
    required this.webOn,
    required this.isActive,
    required this.hasDescription,
    required this.priceMode,
    required this.stock,
    required this.issues,
    this.websiteName,
    this.gtin,
    this.categoryId,
    this.categoryName,
    this.brandId,
    this.brand,
    this.cost,
    this.taxRate,
    this.minWebPrice,
    this.imageUrl,
    this.clearanceUntil,
    this.available,
    this.block,
    this.soldCounter12m = 0,
    this.usedJobs12m = 0,
    this.soldTotal12m = 0,
  });

  factory CatalogWebItem.fromRow(Map<String, dynamic> row) {
    double? number(Object? value) =>
        value == null ? null : double.tryParse(value.toString());
    int? integer(Object? value) =>
        value == null ? null : int.tryParse(value.toString().split('.').first);
    String? text(Object? value) {
      final s = value?.toString().trim();
      return s == null || s.isEmpty ? null : s;
    }

    return CatalogWebItem(
      id: row['id'].toString(),
      name: (row['name'] ?? '').toString(),
      websiteName: text(row['website_name']),
      sku: (row['sku'] ?? '').toString(),
      gtin: text(row['gtin']),
      kind: CatalogItemKind.fromCode(row['kind']?.toString()),
      categoryId: text(row['category_id']),
      categoryName: text(row['category_name']),
      brandId: text(row['brand_id']),
      brand: text(row['brand']),
      price: number(row['price']) ?? 0,
      webPrice: number(row['web_price']) ?? 0,
      cost: number(row['cost']),
      taxRate: number(row['tax_rate']),
      minWebPrice: number(row['min_web_price']),
      imageUrl: text(row['image_url']),
      hasDescription: row['has_description'] == true,
      webOn: row['web_on'] == true,
      isActive: row['is_active'] == true,
      clearanceUntil:
          DateTime.tryParse(row['clearance_until']?.toString() ?? ''),
      priceMode: CatalogPriceMode.fromCode(row['price_mode']?.toString()),
      stock: integer(row['stock']) ?? 0,
      available: integer(row['available']),
      block: text(row['block']),
      state: CatalogItemState.fromCode(row['state']?.toString()),
      soldCounter12m: integer(row['sold_counter_12m']) ?? 0,
      usedJobs12m: integer(row['used_jobs_12m']) ?? 0,
      soldTotal12m: integer(row['sold_total_12m']) ?? 0,
      issues: [
        for (final issue in (row['issues'] as List?) ?? const [])
          issue.toString(),
      ],
    );
  }

  final String id;
  final String name;
  final String? websiteName;
  final String sku;
  final String? gtin;
  final CatalogItemKind kind;
  final String? categoryId;
  final String? categoryName;
  final String? brandId;
  final String? brand;

  /// The ERP price and the store price (the web override, or the ERP one).
  final double price;
  final double webPrice;
  final double? cost;
  final double? taxRate;

  /// Cost with VAT, rounded up: the lowest price that loses nothing.
  final double? minWebPrice;
  final String? imageUrl;
  final bool hasDescription;
  final bool webOn;
  final bool isActive;
  final DateTime? clearanceUntil;
  final CatalogPriceMode priceMode;

  /// Stock on the shelf, and what the store can sell after web reservations
  /// (a kit by its scarcest part); null when it does not count stock.
  final int stock;
  final int? available;

  /// The first reason the rule gives, or null when it sells.
  final String? block;
  final CatalogItemState state;
  final int soldCounter12m;
  final int usedJobs12m;
  final int soldTotal12m;
  final List<String> issues;

  /// The name the customer reads.
  String get displayName =>
      (websiteName?.trim().isNotEmpty ?? false) ? websiteName!.trim() : name;

  bool get hasWebName => websiteName?.trim().isNotEmpty ?? false;
  bool get hasPhoto => imageUrl != null;
  bool get onClearance =>
      clearanceUntil != null &&
      !clearanceUntil!.isBefore(DateUtils.dateOnly(DateTime.now()));

  double get taxFactor {
    final rate = taxRate;
    if (rate == null) return 1.19;
    return 1 + (rate > 1 ? rate / 100 : rate);
  }

  bool get hasTaxClassification =>
      taxRate != null && (taxRate == 0 || taxRate == 0.19 || taxRate == 19);

  /// Margin on the net price, or null without a cost.
  double? get marginPct {
    final c = cost;
    if (c == null || c <= 0 || webPrice <= 0) return null;
    final net = webPrice / taxFactor;
    return (net - c) / net * 100;
  }

  /// Stock the store can sell, for sorting and display.
  int get sellable => available ?? stock;

  /// Value of the sellable stock at the store price.
  double get stockValue => sellable > 0 ? sellable * webPrice : 0;

  String get reason {
    if (state == CatalogItemState.soldOut) {
      return 'Sin stock: ficha visible, sin carrito';
    }
    if (state == CatalogItemState.selling) {
      if (kind == CatalogItemKind.service) return 'Publicado en /servicios';
      if (onClearance) return 'En liquidación';
      return 'Todo en orden';
    }
    return CatalogReasons.block(block, minPrice: minWebPrice);
  }

  String get priceLabel {
    if (priceMode == CatalogPriceMode.quote) return 'A cotizar';
    final amount = ChileanUtils.formatCurrency(webPrice);
    return priceMode == CatalogPriceMode.from ? 'Desde $amount' : amount;
  }

  /// Text the list search matches: names, SKU, GTIN, brand and category.
  String get searchText => [
        name,
        websiteName ?? '',
        sku,
        gtin ?? '',
        brand ?? '',
        categoryName ?? '',
      ].join(' ').toLowerCase();
}

/// One row of `catalog_category_counts_v1`.
@immutable
class CatalogCategoryCount {
  const CatalogCategoryCount({
    required this.id,
    required this.name,
    required this.visible,
    required this.subcategories,
    required this.selling,
    required this.soldOut,
    required this.needsAttention,
    required this.sellingDirect,
    this.parentId,
    this.fullPath,
    this.level = 0,
    this.sortOrder = 0,
  });

  factory CatalogCategoryCount.fromRow(Map<String, dynamic> row) {
    int integer(Object? value) =>
        int.tryParse(value?.toString().split('.').first ?? '') ?? 0;
    return CatalogCategoryCount(
      id: row['category_id'].toString(),
      name: (row['name'] ?? '').toString(),
      parentId: row['parent_id']?.toString(),
      fullPath: row['full_path']?.toString(),
      level: integer(row['level']),
      sortOrder: integer(row['sort_order']),
      visible: row['show_on_website'] == true,
      subcategories: integer(row['subcategories']),
      selling: integer(row['selling']),
      soldOut: integer(row['out_of_stock']),
      needsAttention: integer(row['needs_attention']),
      sellingDirect: integer(row['selling_direct']),
    );
  }

  final String id;
  final String name;
  final String? parentId;
  final String? fullPath;
  final int level;
  final int sortOrder;
  final bool visible;
  final int subcategories;
  final int selling;
  final int soldOut;
  final int needsAttention;
  final int sellingDirect;

  CatalogCategoryCount copyWith({bool? visible}) => CatalogCategoryCount(
        id: id,
        name: name,
        parentId: parentId,
        fullPath: fullPath,
        level: level,
        sortOrder: sortOrder,
        visible: visible ?? this.visible,
        subcategories: subcategories,
        selling: selling,
        soldOut: soldOut,
        needsAttention: needsAttention,
        sellingDirect: sellingDirect,
      );
}

/// One row of `catalog_featured_suggestions_v1`.
@immutable
class CatalogFeaturedSuggestion {
  const CatalogFeaturedSuggestion({
    required this.productId,
    required this.name,
    required this.webPrice,
    required this.available,
    required this.soldTotal12m,
    this.marginPct,
    this.imageUrl,
  });

  factory CatalogFeaturedSuggestion.fromRow(Map<String, dynamic> row) =>
      CatalogFeaturedSuggestion(
        productId: row['product_id'].toString(),
        name: (row['name'] ?? '').toString(),
        webPrice: double.tryParse(row['web_price']?.toString() ?? '') ?? 0,
        available:
            int.tryParse(row['available']?.toString().split('.').first ?? '') ??
                0,
        soldTotal12m: int.tryParse(
                row['sold_total_12m']?.toString().split('.').first ?? '') ??
            0,
        marginPct: double.tryParse(row['margin_pct']?.toString() ?? ''),
        imageUrl: row['image_url']?.toString(),
      );

  final String productId;
  final String name;
  final double webPrice;
  final int available;
  final int soldTotal12m;
  final double? marginPct;
  final String? imageUrl;
}

/// The store's rules as the settings keep them (`website_settings`).
@immutable
class CatalogRules {
  const CatalogRules({
    this.stockPolicy = 'available_only',
    this.requireImage = false,
    this.requireWebName = false,
    this.requireDescription = false,
    this.requireBrand = false,
    this.requireVisibleCategory = false,
    this.includeUncategorized = true,
  });

  static const stockPolicyKey = 'product_visibility_stock_policy';
  static const requireImageKey = 'product_visibility_require_image';
  static const requireWebNameKey = 'product_visibility_require_web_name';
  static const requireDescriptionKey = 'product_visibility_require_description';
  static const requireBrandKey = 'product_visibility_require_brand';
  static const requireVisibleCategoryKey =
      'product_visibility_require_visible_category';
  static const includeUncategorizedKey =
      'product_visibility_include_uncategorized';

  static const keys = <String>[
    stockPolicyKey,
    requireImageKey,
    requireWebNameKey,
    requireDescriptionKey,
    requireBrandKey,
    requireVisibleCategoryKey,
    includeUncategorizedKey,
  ];

  factory CatalogRules.fromSettings(Map<String, String> settings) {
    bool flag(String key, bool fallback) {
      final raw = settings[key]?.trim().toLowerCase();
      if (raw == null || raw.isEmpty) return fallback;
      return const {'true', '1', 'yes', 'si', 'sí'}.contains(raw);
    }

    final stock = (settings[stockPolicyKey] ?? '').trim().toLowerCase();
    return CatalogRules(
      stockPolicy: switch (stock) {
        'all' || 'both' => 'all',
        'out_of_stock_only' ||
        'out_of_stock' ||
        'sin_stock' =>
          'out_of_stock_only',
        _ => 'available_only',
      },
      requireImage: flag(requireImageKey, false),
      requireWebName: flag(requireWebNameKey, false),
      requireDescription: flag(requireDescriptionKey, false),
      requireBrand: flag(requireBrandKey, false),
      requireVisibleCategory: flag(requireVisibleCategoryKey, false),
      includeUncategorized: flag(includeUncategorizedKey, true),
    );
  }

  final String stockPolicy;
  final bool requireImage;
  final bool requireWebName;
  final bool requireDescription;
  final bool requireBrand;
  final bool requireVisibleCategory;
  final bool includeUncategorized;

  Map<String, String> toSettings() => {
        stockPolicyKey: stockPolicy,
        requireImageKey: '$requireImage',
        requireWebNameKey: '$requireWebName',
        requireDescriptionKey: '$requireDescription',
        requireBrandKey: '$requireBrand',
        requireVisibleCategoryKey: '$requireVisibleCategory',
        includeUncategorizedKey: '$includeUncategorized',
      };

  CatalogRules copyWith({
    String? stockPolicy,
    bool? requireImage,
    bool? requireWebName,
    bool? requireDescription,
    bool? requireBrand,
    bool? requireVisibleCategory,
  }) =>
      CatalogRules(
        stockPolicy: stockPolicy ?? this.stockPolicy,
        requireImage: requireImage ?? this.requireImage,
        requireWebName: requireWebName ?? this.requireWebName,
        requireDescription: requireDescription ?? this.requireDescription,
        requireBrand: requireBrand ?? this.requireBrand,
        requireVisibleCategory:
            requireVisibleCategory ?? this.requireVisibleCategory,
        includeUncategorized: includeUncategorized,
      );
}
