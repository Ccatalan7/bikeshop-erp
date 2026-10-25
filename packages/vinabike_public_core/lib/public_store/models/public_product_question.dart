// «Pregunta por este producto» (2026-10-24): a product page asks the store
// about that product, by WhatsApp or by the portal's chat, with the product
// already in the message. Until then the page's only way was the help card
// under the technical sheet, and customers who wrote by WhatsApp had to
// describe the product themselves. The HTML store and Flutter's product page
// use these, so a word or the message changes in one place.

/// What the product page's question box and its sheet say, and the message
/// both channels send.
abstract final class PublicProductQuestion {
  /// The box's title when the product page template leaves it blank: an
  /// out-of-stock product invites the question it raises.
  static String defaultTitle({required bool inStock}) =>
      inStock ? '¿Tienes dudas con este producto?' : '¿Lo necesitas?';

  static String lead({required bool inStock}) => inStock
      ? 'Pregúntanos por WhatsApp o por el chat: el producto va en tu mensaje.'
      : 'Pregúntanos por él o por algo parecido: el producto va en tu mensaje.';

  static const sheetTitle = 'Pregunta por este producto';
  static const questionLabel = '¿Qué quieres saber?';
  static const questionHint =
      'Escribe tu pregunta. Si es por compatibilidad, cuéntanos qué bicicleta '
      'tienes.';
  static const sendWhatsApp = 'Enviar por WhatsApp';
  static const sendChat = 'Enviar por el chat';
  static const chatSignInNote =
      'El chat queda en tu cuenta de la tienda: si no has entrado, te pedimos '
      'entrar y tu pregunta se envía sola al volver.';
  static const chatSignIn =
      'Para enviarla por el chat, entra a tu cuenta de la tienda.';
  static const chatSending = 'Enviando tu pregunta…';
  static const chatFailed =
      'No pudimos enviar tu pregunta por el chat. Intenta de nuevo o '
      'escríbenos por WhatsApp.';
  static const whatsAppLabel = 'WhatsApp';
  static const chatLabel = 'Chat';

  /// The longest question the sheet takes; the message adds the product.
  static const questionMaxLength = 1000;

  /// The questions a visitor taps, in the shop's words, by what the
  /// product is: one in stock asks for it today, one out of stock when it
  /// comes back or for something like it; a part with a technical sheet,
  /// whether it fits and whether the workshop puts it on.
  static List<String> suggestions({
    required bool inStock,
    required bool technical,
  }) => [
    if (inStock) '¿Lo tienen para retiro hoy?' else '¿Cuándo les llega?',
    if (technical) '¿Le sirve a mi bicicleta?',
    if (!inStock) '¿Tienen algo parecido?',
    if (technical && inStock) '¿Me lo instalan en el taller?',
  ];

  /// A search that found nothing, asked by WhatsApp as the visitor wrote it
  /// (the catalog's empty search and the header's search, 2026-10-24).
  static String notFoundMessage(String term) =>
      'Hola, busqué «${term.trim()}» en la tienda y no lo encontré. '
      '¿Lo tienen?';

  static const notFoundLead =
      'Revisa cómo se escribe o prueba con otra palabra. Si no lo ves, '
      'pregúntanos: te ayudamos a encontrarlo.';

  /// The message either channel sends: the product first, as the shop
  /// finds it (name, SKU, price and its page), then the question.
  static String message({
    required String title,
    required String sku,
    required String price,
    required String url,
    String question = '',
  }) {
    final facts = [
      if (sku.trim().isNotEmpty) 'SKU ${sku.trim()}',
      if (price.trim().isNotEmpty) price.trim(),
    ];
    final asked = question.trim();
    return [
      'Hola, les escribo por este producto:',
      '${title.trim()}${facts.isEmpty ? '' : ' (${facts.join(', ')})'}',
      if (url.trim().isNotEmpty) url.trim(),
      if (asked.isNotEmpty) '\n$asked',
    ].join('\n');
  }
}
