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
    this.showStickyBuyBar = true,
    this.showPromises = true,
    this.sheetTitle = '',
    this.showOriginNote = true,
    this.showHelp = true,
    this.helpTitle = '',
    this.helpText = '',
    this.showRelated = true,
    this.relatedTitle = '',
    this.showFits = true,
    this.fitsTitle = '',
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

  /// On a phone, the price and «Agregar al carrito» fixed at the bottom
  /// once the page's own button scrolls out of sight (2026-10-24), as the
  /// big stores do: the button stays in reach while the visitor reads the
  /// sheet. Never for a product that cannot be bought now.
  final bool showStickyBuyBar;

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

  /// What goes with the product, by its technical sheet (2026-10-23): the
  /// tubes that fit a tyre, the tyres a tube fits. A blank title is the
  /// page's own words for what it offers.
  final bool showFits;
  final String fitsTitle;

  String get resolvedAddToCartLabel => addToCartLabel.trim().isEmpty
      ? defaultAddToCartLabel
      : addToCartLabel.trim();

  String get resolvedBuyNowLabel =>
      buyNowLabel.trim().isEmpty ? defaultBuyNowLabel : buyNowLabel.trim();

  String get resolvedRelatedTitle =>
      relatedTitle.trim().isEmpty ? defaultRelatedTitle : relatedTitle.trim();

  /// The section's title for what it offers: `tubes` (a tyre's page) or
  /// `tyres` (a tube's page).
  String resolvedFitsTitle(String kind) => fitsTitle.trim().isNotEmpty
      ? fitsTitle.trim()
      : kind == 'tyres'
      ? 'Neumáticos para esta cámara'
      : 'Cámaras que calzan';

  /// The line over the title.
  static String fitsEyebrow(String kind) => kind == 'tyres'
      ? 'Lo que va con esta cámara'
      : 'Lo que va con este neumático';

  /// Why they fit, in the shop's words, and what the buyer still decides.
  static String fitsNote(String kind) => kind == 'tyres'
      ? 'Mismo aro, y su ancho cabe en el rango de esta cámara.'
      : 'Mismo aro, y su rango de ancho incluye el de este neumático. La '
            'válvula va con el agujero de tu llanta: americana (auto) o '
            'francesa (Presta).';

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
      showStickyBuyBar: flag('show_sticky_buy_bar'),
      showPromises: flag('show_promises'),
      sheetTitle: text('sheet_title'),
      showOriginNote: flag('show_origin_note'),
      showHelp: flag('show_help'),
      helpTitle: text('help_title'),
      helpText: text('help_text'),
      showRelated: flag('show_related'),
      relatedTitle: text('related_title'),
      showFits: flag('show_fits'),
      fitsTitle: text('fits_title'),
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
    'show_sticky_buy_bar': showStickyBuyBar,
    'show_promises': showPromises,
    'sheet_title': sheetTitle.trim(),
    'show_origin_note': showOriginNote,
    'show_help': showHelp,
    'help_title': helpTitle.trim(),
    'help_text': helpText.trim(),
    'show_related': showRelated,
    'related_title': relatedTitle.trim(),
    'show_fits': showFits,
    'fits_title': fitsTitle.trim(),
  };

  String encode() => jsonEncode(toJson());

  WebsiteProductPageTemplate copyWith({
    WebsiteProductPhotoSide? photoSide,
    String? taxNote,
    bool? showHighlights,
    String? addToCartLabel,
    bool? showBuyNow,
    String? buyNowLabel,
    bool? showStickyBuyBar,
    bool? showPromises,
    String? sheetTitle,
    bool? showOriginNote,
    bool? showHelp,
    String? helpTitle,
    String? helpText,
    bool? showRelated,
    String? relatedTitle,
    bool? showFits,
    String? fitsTitle,
  }) => WebsiteProductPageTemplate(
    photoSide: photoSide ?? this.photoSide,
    taxNote: taxNote ?? this.taxNote,
    showHighlights: showHighlights ?? this.showHighlights,
    addToCartLabel: addToCartLabel ?? this.addToCartLabel,
    showBuyNow: showBuyNow ?? this.showBuyNow,
    buyNowLabel: buyNowLabel ?? this.buyNowLabel,
    showStickyBuyBar: showStickyBuyBar ?? this.showStickyBuyBar,
    showPromises: showPromises ?? this.showPromises,
    sheetTitle: sheetTitle ?? this.sheetTitle,
    showOriginNote: showOriginNote ?? this.showOriginNote,
    showHelp: showHelp ?? this.showHelp,
    helpTitle: helpTitle ?? this.helpTitle,
    helpText: helpText ?? this.helpText,
    showRelated: showRelated ?? this.showRelated,
    relatedTitle: relatedTitle ?? this.relatedTitle,
    showFits: showFits ?? this.showFits,
    fitsTitle: fitsTitle ?? this.fitsTitle,
  );

  @override
  bool operator ==(Object other) =>
      other is WebsiteProductPageTemplate && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
