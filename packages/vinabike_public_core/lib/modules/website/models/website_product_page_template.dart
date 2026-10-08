import 'dart:convert';

/// The website setting holding the product page template.
const websiteProductPageTemplateSettingKey = 'product_page_template_v1';

/// Which side of the buy column the photos take on a wide screen.
enum WebsiteProductPhotoSide { left, right }

extension WebsiteProductPhotoSideX on WebsiteProductPhotoSide {
  String get storageValue => name;

  String get label => switch (this) {
    WebsiteProductPhotoSide.left => 'Izquierda',
    WebsiteProductPhotoSide.right => 'Derecha',
  };

  static WebsiteProductPhotoSide fromStorage(Object? raw) =>
      raw?.toString() == 'right'
      ? WebsiteProductPhotoSide.right
      : WebsiteProductPhotoSide.left;
}

/// The product page template (approved editor proposal, 2026-10-06: «Ficha
/// de producto · una plantilla»): what every product page shows around the
/// product's own data, and in what words. The product (name, price, photos,
/// stock, description, technical sheet, related items) is the catalog's and
/// is edited in Inventario; this is only the page.
///
/// A blank title falls back to the page's own words (the technical sheet is
/// «Ficha técnica» or «Detalles del producto» by what the product has); a
/// blank note is not shown; a blank button label is the default label,
/// since a button needs one.
class WebsiteProductPageTemplate {
  const WebsiteProductPageTemplate({
    this.photoSide = WebsiteProductPhotoSide.left,
    this.taxNote = defaultTaxNote,
    this.showHighlights = true,
    this.addToCartLabel = '',
    this.showBuyNow = true,
    this.buyNowLabel = '',
    this.showPromises = true,
    this.sheetTitle = '',
    this.showOriginNote = true,
    this.showHelp = true,
    this.helpTitle = '',
    this.helpText = '',
    this.showRelated = true,
    this.relatedTitle = '',
  });

  static const defaultTaxNote = 'Precio final con IVA incluido';
  static const defaultAddToCartLabel = 'Agregar al carrito';
  static const defaultBuyNowLabel = 'Comprar ahora';
  static const defaultRelatedTitle = 'Productos relacionados';
  static const originNote =
      'Ficha preparada por nuestro equipo con información del fabricante y '
      'del proveedor.';

  /// What a workshop service's page says where a product's speaks of stock,
  /// cart and shipping (2026-10-08). The template's own texts are about
  /// products, so a service page uses these.
  static const serviceBookLabel = 'Agendar por WhatsApp';
  static const serviceWhereTitle = 'Se hace en el taller';
  static const serviceSheetTitle = 'Detalles del servicio';
  static const serviceHelpTitle = '¿No sabes qué servicio necesita tu bici?';
  static const serviceHelpText =
      'Escríbenos qué le pasa o tráela al taller: la revisamos y te decimos '
      'qué hace falta antes de empezar.';
  static const serviceRelatedTitle = 'Otros servicios del taller';

  final WebsiteProductPhotoSide photoSide;

  /// Under the price; blank hides it.
  final String taxNote;

  /// The key data next to the price («Ver ficha técnica completa»).
  final bool showHighlights;
  final String addToCartLabel;
  final bool showBuyNow;
  final String buyNowLabel;

  /// Pickup and delivery under the buy column (their texts are the site's,
  /// in «Ajustes del sitio»).
  final bool showPromises;

  final String sheetTitle;
  final bool showOriginNote;

  /// The card beside the technical sheet that leads to WhatsApp.
  final bool showHelp;
  final String helpTitle;
  final String helpText;

  final bool showRelated;
  final String relatedTitle;

  String get resolvedAddToCartLabel => addToCartLabel.trim().isEmpty
      ? defaultAddToCartLabel
      : addToCartLabel.trim();

  String get resolvedBuyNowLabel =>
      buyNowLabel.trim().isEmpty ? defaultBuyNowLabel : buyNowLabel.trim();

  String get resolvedRelatedTitle =>
      relatedTitle.trim().isEmpty ? defaultRelatedTitle : relatedTitle.trim();

  /// «Ficha técnica», or «Detalles del producto» for a product with nothing
  /// technical to say (food, a souvenir), unless the template names it.
  String resolvedSheetTitle({required bool technical}) =>
      sheetTitle.trim().isNotEmpty
      ? sheetTitle.trim()
      : technical
      ? 'Ficha técnica'
      : 'Detalles del producto';

  String resolvedHelpTitle({required bool technical}) =>
      helpTitle.trim().isNotEmpty
      ? helpTitle.trim()
      : technical
      ? '¿Le sirve a tu bicicleta?'
      : '¿Tienes una duda?';

  String resolvedHelpText({required bool technical}) =>
      helpText.trim().isNotEmpty
      ? helpText.trim()
      : technical
      ? 'Cuéntanos qué bicicleta tienes y te ayudamos a elegir la medida '
            'correcta antes de comprar.'
      : 'Escríbenos y te ayudamos con lo que necesites saber de este '
            'producto antes de comprar.';

  factory WebsiteProductPageTemplate.fromJson(Map<String, dynamic> json) {
    String text(String key, [String fallback = '']) =>
        json.containsKey(key) ? json[key]?.toString().trim() ?? '' : fallback;
    bool flag(String key) => json[key] != false;
    return WebsiteProductPageTemplate(
      photoSide: WebsiteProductPhotoSideX.fromStorage(json['photo_side']),
      // Missing is the default note; an explicit empty one hides it.
      taxNote: text('tax_note', defaultTaxNote),
      showHighlights: flag('show_highlights'),
      addToCartLabel: text('add_to_cart_label'),
      showBuyNow: flag('show_buy_now'),
      buyNowLabel: text('buy_now_label'),
      showPromises: flag('show_promises'),
      sheetTitle: text('sheet_title'),
      showOriginNote: flag('show_origin_note'),
      showHelp: flag('show_help'),
      helpTitle: text('help_title'),
      helpText: text('help_text'),
      showRelated: flag('show_related'),
      relatedTitle: text('related_title'),
    );
  }

  /// The template a site saved, or the default page when it has none (or
  /// what it has cannot be read).
  factory WebsiteProductPageTemplate.decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const WebsiteProductPageTemplate();
    }
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? WebsiteProductPageTemplate.fromJson(decoded)
          : const WebsiteProductPageTemplate();
    } catch (_) {
      return const WebsiteProductPageTemplate();
    }
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'photo_side': photoSide.storageValue,
    'tax_note': taxNote.trim(),
    'show_highlights': showHighlights,
    'add_to_cart_label': addToCartLabel.trim(),
    'show_buy_now': showBuyNow,
    'buy_now_label': buyNowLabel.trim(),
    'show_promises': showPromises,
    'sheet_title': sheetTitle.trim(),
    'show_origin_note': showOriginNote,
    'show_help': showHelp,
    'help_title': helpTitle.trim(),
    'help_text': helpText.trim(),
    'show_related': showRelated,
    'related_title': relatedTitle.trim(),
  };

  String encode() => jsonEncode(toJson());

  WebsiteProductPageTemplate copyWith({
    WebsiteProductPhotoSide? photoSide,
    String? taxNote,
    bool? showHighlights,
    String? addToCartLabel,
    bool? showBuyNow,
    String? buyNowLabel,
    bool? showPromises,
    String? sheetTitle,
    bool? showOriginNote,
    bool? showHelp,
    String? helpTitle,
    String? helpText,
    bool? showRelated,
    String? relatedTitle,
  }) => WebsiteProductPageTemplate(
    photoSide: photoSide ?? this.photoSide,
    taxNote: taxNote ?? this.taxNote,
    showHighlights: showHighlights ?? this.showHighlights,
    addToCartLabel: addToCartLabel ?? this.addToCartLabel,
    showBuyNow: showBuyNow ?? this.showBuyNow,
    buyNowLabel: buyNowLabel ?? this.buyNowLabel,
    showPromises: showPromises ?? this.showPromises,
    sheetTitle: sheetTitle ?? this.sheetTitle,
    showOriginNote: showOriginNote ?? this.showOriginNote,
    showHelp: showHelp ?? this.showHelp,
    helpTitle: helpTitle ?? this.helpTitle,
    helpText: helpText ?? this.helpText,
    showRelated: showRelated ?? this.showRelated,
    relatedTitle: relatedTitle ?? this.relatedTitle,
  );

  @override
  bool operator ==(Object other) =>
      other is WebsiteProductPageTemplate && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
