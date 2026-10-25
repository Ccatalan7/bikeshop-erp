/// The help card of the wide menu, under its section's photo: for the one who
/// does not know which part fits, a line to the shop. «Menú desplegado» in the
/// editor shows it, hides it and writes its words; blank words are these
/// defaults. It answers by WhatsApp when the store has a number, else by the
/// customer chat.
final class HeaderMenuHelp {
  const HeaderMenuHelp({
    required this.show,
    required this.title,
    required this.text,
    required this.action,
    required this.href,
    required this.external,
  });

  static const showKey = 'header_menu_help_show';
  static const titleKey = 'header_menu_help_title';
  static const textKey = 'header_menu_help_text';
  static const actionKey = 'header_menu_help_action';

  static const defaultTitle = '¿No sabes cuál calza?';
  static const defaultText =
      'Mándanos una foto de tu pieza y te decimos cuál le sirve a tu bici.';
  static const defaultWhatsAppAction = 'Escribir por WhatsApp';
  static const defaultChatAction = 'Escribir por el chat';

  /// The customer chat, when the store has no WhatsApp.
  static const chatHref = '/cuenta/chats';

  static String whatsAppMessage(String storeName) =>
      'Hola${storeName.isEmpty ? '' : ' $storeName'}, quiero saber qué pieza '
      'le sirve a mi bici';

  /// [read] returns the setting as saved, or '' when there is none;
  /// [whatsappDigits] is the store's number for `wa.me`, or ''.
  factory HeaderMenuHelp.resolve(
    String Function(String key) read, {
    required String whatsappDigits,
    required String storeName,
  }) {
    String text(String key, String fallback) {
      final value = read(key).trim();
      return value.isEmpty ? fallback : value;
    }

    final whatsapp = whatsappDigits.isNotEmpty;
    return HeaderMenuHelp(
      show: read(showKey).trim() != 'false',
      title: text(titleKey, defaultTitle),
      text: text(textKey, defaultText),
      action: text(
        actionKey,
        whatsapp ? defaultWhatsAppAction : defaultChatAction,
      ),
      href: whatsapp
          ? 'https://wa.me/$whatsappDigits?text='
                '${Uri.encodeComponent(whatsAppMessage(storeName))}'
          : chatHref,
      external: whatsapp,
    );
  }

  final bool show;
  final String title;
  final String text;
  final String action;
  final String href;

  /// WhatsApp opens outside the store.
  final bool external;
}
