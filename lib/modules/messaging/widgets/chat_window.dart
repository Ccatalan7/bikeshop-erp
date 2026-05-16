import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../sales/services/sales_service.dart';
import '../../sales/models/sales_models.dart';
import '../../website/services/website_service.dart';
import '../models/conversation.dart';
import '../services/messaging_service.dart';
import '../models/message.dart';
import '../models/autocomplete_suggestion.dart';
import 'parsed_message_text.dart';
import '../providers/chat_provider.dart';
import '../utils/message_parser.dart';
import 'assign_context_dialog.dart';
import '../../../shared/services/whatsapp_service.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/route_share_service.dart';
import '../../../shared/services/workspace_manager.dart';
import '../../../shared/utils/invoice_pdf_generator.dart';
import '../../../shared/utils/file_download.dart';

class _EmojiGroup {
  final String label;
  final IconData icon;
  final List<String> keywords;
  final List<String> emojis;

  const _EmojiGroup({
    required this.label,
    required this.icon,
    required this.keywords,
    required this.emojis,
  });
}

class _EmojiSection {
  final String label;
  final List<String> emojis;

  const _EmojiSection(this.label, this.emojis);
}

class _UnreadMessagesMarker {
  final int count;

  const _UnreadMessagesMarker(this.count);
}

enum _ChatInfoSection { info, media, workflow, backup }

class _ChatAttachment {
  final Message message;
  final String url;
  final String name;
  final String extension;
  final bool isImage;

  const _ChatAttachment({
    required this.message,
    required this.url,
    required this.name,
    required this.extension,
    required this.isImage,
  });
}

class _RouteSharePreview {
  final AppRouteLinkSegment link;
  final String title;
  final String intro;
  final String trailingText;

  const _RouteSharePreview({
    required this.link,
    required this.title,
    required this.intro,
    required this.trailingText,
  });
}

class ChatWindow extends StatefulWidget {
  final Conversation conversation;
  final Function(ReferenceSegment)? onReferenceTap;
  final bool isContextPanelClosed;
  final VoidCallback? onShowContextPanel;
  final List<Widget> headerActions;
  final bool compact;

  const ChatWindow({
    super.key,
    required this.conversation,
    this.onReferenceTap,
    this.isContextPanelClosed = false,
    this.onShowContextPanel,
    this.headerActions = const [],
    this.compact = false,
  });

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  static const Color _accentBlue = Color(0xFF093357);
  static const Duration _whatsAppMinimumClockDwell =
      Duration(milliseconds: 240);
  static const Duration _whatsAppInferredReadWindow = Duration(hours: 24);
  static const String _googleMapsReviewUrl =
      'https://g.page/r/CYVszP1uXQfgEBM/review';
  static final List<_EmojiGroup> _emojiGroups = [
    _EmojiGroup(
      label: 'Smileys y personas',
      icon: Icons.emoji_emotions_outlined,
      keywords: const ['cara', 'risa', 'feliz', 'triste', 'smiley', 'face'],
      emojis:
          '😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 🫠 😉 😊 😇 🥰 😍 🤩 😘 😗 ☺️ 😚 😙 🥲 😋 😛 😜 🤪 😝 🤑 🤗 🤭 🫢 🫣 🤫 🤔 🫡 🤐 🤨 😐 😑 😶 🫥 😏 😒 🙄 😬 😮‍💨 🤥 😌 😔 😪 🤤 😴 😷 🤒 🤕 🤢 🤮 🤧 🥵 🥶 🥴 😵 😵‍💫 🤯 🤠 🥳 🥸 😎 🤓 🧐 😕 🫤 😟 🙁 ☹️ 😮 😯 😲 😳 🥺 🥹 😦 😧 😨 😰 😥 😢 😭 😱 😖 😣 😞 😓 😩 😫 🥱 😤 😡 😠 🤬 😈 👿 💀 ☠️ 💩 🤡 👹 👺 👻 👽 👾 🤖 😺 😸 😹 😻 😼 😽 🙀 😿 😾'
              .split(' '),
    ),
    _EmojiGroup(
      label: 'Gestos y cuerpo',
      icon: Icons.waving_hand_outlined,
      keywords: const ['mano', 'gesto', 'persona', 'people', 'hand'],
      emojis:
          '👋 🤚 🖐️ ✋ 🖖 🫱 🫲 🫳 🫴 👌 🤌 🤏 ✌️ 🤞 🫰 🤟 🤘 🤙 👈 👉 👆 🖕 👇 ☝️ 🫵 👍 👎 ✊ 👊 🤛 🤜 👏 🙌 🫶 👐 🤲 🤝 🙏 ✍️ 💅 🤳 💪 🦾 🦿 🦵 🦶 👂 🦻 👃 🧠 🫀 🫁 🦷 🦴 👀 👁️ 👅 👄 🫦 👶 🧒 👦 👧 🧑 👨 👩 🧓 👴 👵 🙍 🙎 🙅 🙆 💁 🙋 🧏 🙇 🤦 🤷 👮 🕵️ 💂 🥷 👷 🫅 🤴 👸 👳 👲 🧕 🤵 👰 🤰 🫃 🫄 👼 🎅 🤶 🧑‍🎄 🦸 🦹 🧙 🧚 🧛 🧜 🧝 🧞 🧟 🧌 💆 💇 🚶 🧍 🧎 🏃 💃 🕺 🕴️ 👯 🧖 🧗 🤺 🏇 ⛷️ 🏂 🏌️ 🏄 🚣 🏊 ⛹️ 🏋️ 🚴 🚵 🤸 🤼 🤽 🤾 🤹 🧘 🛀 🛌'
              .split(' '),
    ),
    _EmojiGroup(
      label: 'Animales y naturaleza',
      icon: Icons.pets_outlined,
      keywords: const ['animal', 'naturaleza', 'clima', 'nature', 'weather'],
      emojis:
          '🐶 🐱 🐭 🐹 🐰 🦊 🐻 🐼 🐨 🐯 🦁 🐮 🐷 🐽 🐸 🐵 🙈 🙉 🙊 🐒 🐔 🐧 🐦 🐤 🐣 🐥 🦆 🦅 🦉 🦇 🐺 🐗 🐴 🦄 🫎 🐝 🪱 🐛 🦋 🐌 🐞 🐜 🪰 🪲 🪳 🦟 🦗 🕷️ 🕸️ 🦂 🐢 🐍 🦎 🦖 🦕 🐙 🦑 🦐 🦞 🦀 🪼 🐡 🐠 🐟 🐬 🐳 🐋 🦈 🦭 🐊 🐅 🐆 🦓 🦍 🦧 🦣 🐘 🦛 🦏 🐪 🐫 🦒 🦘 🦬 🐃 🐂 🐄 🫏 🐎 🐖 🐏 🐑 🦙 🐐 🦌 🐕 🐩 🦮 🐕‍🦺 🐈 🐈‍⬛ 🪶 🐓 🦃 🦤 🦚 🦜 🪽 🐇 🦝 🦨 🦡 🦫 🦦 🦥 🐁 🐀 🐿️ 🦔 🌵 🎄 🌲 🌳 🌴 🪵 🌱 🌿 ☘️ 🍀 🎍 🪴 🎋 🍃 🍂 🍁 🍄 🪨 🪸 🪷 🌹 🥀 🌺 🌸 🪻 🌼 🌻 🌞 🌝 🌛 🌜 🌚 🌕 🌖 🌗 🌘 🌑 🌒 🌓 🌔 🌙 🌎 🌍 🌏 🪐 💫 ⭐ 🌟 ✨ ⚡ ☄️ 💥 🔥 🌪️ 🌈 ☀️ 🌤️ ⛅ 🌥️ ☁️ 🌦️ 🌧️ ⛈️ 🌩️ 🌨️ ❄️ ☃️ ⛄ 🌬️ 💨 💧 💦 ☔ ☂️ 🌊'
              .split(' '),
    ),
    _EmojiGroup(
      label: 'Comida y bebida',
      icon: Icons.restaurant_outlined,
      keywords: const ['comida', 'bebida', 'food', 'drink'],
      emojis:
          '🍏 🍎 🍐 🍊 🍋 🍌 🍉 🍇 🍓 🫐 🍈 🍒 🍑 🥭 🍍 🥥 🥝 🍅 🍆 🥑 🥦 🫛 🥬 🥒 🌶️ 🫑 🌽 🥕 🫒 🧄 🧅 🥔 🍠 🫚 🥐 🥯 🍞 🥖 🥨 🧀 🥚 🍳 🧈 🥞 🧇 🥓 🥩 🍗 🍖 🦴 🌭 🍔 🍟 🍕 🫓 🥪 🥙 🧆 🌮 🌯 🫔 🥗 🥘 🫕 🥫 🍝 🍜 🍲 🍛 🍣 🍱 🥟 🦪 🍤 🍙 🍚 🍘 🍥 🥠 🥮 🍢 🍡 🍧 🍨 🍦 🥧 🧁 🍰 🎂 🍮 🍭 🍬 🍫 🍿 🍩 🍪 🌰 🥜 🫘 🍯 🥛 🫗 🍼 🫖 ☕ 🍵 🧃 🥤 🧋 🍶 🍺 🍻 🥂 🍷 🥃 🍸 🍹 🧉 🍾 🧊 🥄 🍴 🍽️ 🥣 🥡 🥢 🧂'
              .split(' '),
    ),
    _EmojiGroup(
      label: 'Viajes y lugares',
      icon: Icons.directions_bike_outlined,
      keywords: const ['viaje', 'lugar', 'auto', 'bici', 'bike', 'travel'],
      emojis:
          '🚲 🚴 🚵 🛴 🛹 🛼 🚗 🚕 🚙 🚌 🚎 🏎️ 🚓 🚑 🚒 🚐 🛻 🚚 🚛 🚜 🦯 🦽 🦼 🛺 🚔 🚍 🚘 🚖 🚡 🚠 🚟 🚃 🚋 🚞 🚝 🚄 🚅 🚈 🚂 🚆 🚇 🚊 🚉 ✈️ 🛫 🛬 🛩️ 💺 🛰️ 🚀 🛸 🚁 🛶 ⛵ 🚤 🛥️ 🛳️ ⛴️ 🚢 ⚓ 🛟 🪝 ⛽ 🚧 🚦 🚥 🚏 🗺️ 🗿 🗽 🗼 🏰 🏯 🏟️ 🎡 🎢 🎠 ⛲ ⛱️ 🏖️ 🏝️ 🏜️ 🌋 ⛰️ 🏔️ 🗻 🏕️ ⛺ 🛖 🏠 🏡 🏘️ 🏚️ 🏗️ 🏭 🏢 🏬 🏣 🏤 🏥 🏦 🏨 🏪 🏫 🏩 💒 🏛️ ⛪ 🕌 🕍 🛕 🕋 ⛩️ 🛤️ 🛣️ 🗾 🎑 🏞️ 🌅 🌄 🌠 🎇 🎆 🌇 🌆 🏙️ 🌃 🌌 🌉 🌁'
              .split(' '),
    ),
    _EmojiGroup(
      label: 'Actividades',
      icon: Icons.sports_soccer_outlined,
      keywords: const ['actividad', 'deporte', 'juego', 'sport', 'game'],
      emojis:
          '⚽ 🏀 🏈 ⚾ 🥎 🎾 🏐 🏉 🥏 🎱 🪀 🏓 🏸 🏒 🏑 🥍 🏏 🪃 🥅 ⛳ 🪁 🏹 🎣 🤿 🥊 🥋 🎽 🛹 🛼 🛷 ⛸️ 🥌 🎿 ⛷️ 🏂 🪂 🏋️ 🤼 🤸 ⛹️ 🤺 🤾 🏌️ 🏇 🧘 🏄 🏊 🤽 🚣 🧗 🚵 🚴 🏆 🥇 🥈 🥉 🏅 🎖️ 🏵️ 🎗️ 🎫 🎟️ 🎪 🤹 🎭 🩰 🎨 🎬 🎤 🎧 🎼 🎹 🥁 🪘 🎷 🎺 🪗 🎸 🪕 🎻 🪈 🎲 ♟️ 🎯 🎳 🎮 🎰 🧩'
              .split(' '),
    ),
    _EmojiGroup(
      label: 'Objetos',
      icon: Icons.lightbulb_outline,
      keywords: const ['objeto', 'herramienta', 'tool', 'work', 'camera'],
      emojis:
          '⌚ 📱 📲 💻 ⌨️ 🖥️ 🖨️ 🖱️ 🖲️ 🕹️ 🗜️ 💽 💾 💿 📀 📼 📷 📸 📹 🎥 📽️ 🎞️ 📞 ☎️ 📟 📠 📺 📻 🎙️ 🎚️ 🎛️ 🧭 ⏱️ ⏲️ ⏰ 🕰️ ⌛ ⏳ 📡 🔋 🪫 🔌 💡 🔦 🕯️ 🪔 🧯 🛢️ 💸 💵 💴 💶 💷 🪙 💰 💳 🧾 💎 ⚖️ 🪜 🧰 🪛 🔧 🔨 ⚒️ 🛠️ ⛏️ 🪚 🔩 ⚙️ 🪤 🧱 ⛓️ 🧲 🔫 💣 🧨 🪓 🔪 🗡️ ⚔️ 🛡️ 🚬 ⚰️ 🪦 ⚱️ 🏺 🔮 📿 🧿 💈 ⚗️ 🔭 🔬 🕳️ 🩹 🩺 💊 💉 🩸 🧬 🦠 🧫 🧪 🌡️ 🧹 🪠 🧺 🧻 🚽 🚰 🚿 🛁 🛀 🧼 🪥 🪒 🧽 🪣 🧴 🛎️ 🔑 🗝️ 🚪 🪑 🛋️ 🛏️ 🛌 🧸 🪆 🖼️ 🪞 🪟 🛍️ 🛒 🎁 🎈 🎏 🎀 🪄 🪅 🎊 🎉 🪩 🎎 🏮 🎐 🧧 ✉️ 📩 📨 📧 💌 📥 📤 📦 🏷️ 🪧 📪 📫 📬 📭 📮 📯 📜 📃 📄 📑 📊 📈 📉 🗒️ 🗓️ 📆 📅 🗑️ 📇 🗃️ 🗳️ 🗄️ 📋 📁 📂 🗂️ 🗞️ 📰 📓 📔 📒 📕 📗 📘 📙 📚 📖 🔖 🧷 🔗 📎 🖇️ 📐 📏 🧮 📌 📍 ✂️ 🖊️ 🖋️ ✒️ 🖌️ 🖍️ 📝 ✏️ 🔍 🔎 🔏 🔐 🔒 🔓'
              .split(' '),
    ),
    _EmojiGroup(
      label: 'Símbolos',
      icon: Icons.tag_outlined,
      keywords: const ['simbolo', 'corazon', 'alerta', 'check', 'symbol'],
      emojis:
          '❤️ 🧡 💛 💚 💙 💜 🖤 🤍 🤎 ❤️‍🔥 ❤️‍🩹 💔 ❣️ 💕 💞 💓 💗 💖 💘 💝 💟 ☮️ ✝️ ☪️ 🕉️ ☸️ ✡️ 🔯 🕎 ☯️ ☦️ 🛐 ⛎ ♈ ♉ ♊ ♋ ♌ ♍ ♎ ♏ ♐ ♑ ♒ ♓ 🆔 ⚛️ 🉑 ☢️ ☣️ 📴 📳 🈶 🈚 🈸 🈺 🈷️ ✴️ 🆚 💮 🉐 ㊙️ ㊗️ 🈴 🈵 🈹 🈲 🅰️ 🅱️ 🆎 🆑 🅾️ 🆘 ❌ ⭕ 🛑 ⛔ 📛 🚫 💯 💢 ♨️ 🚷 🚯 🚳 🚱 🔞 📵 🚭 ❗ ❕ ❓ ❔ ‼️ ⁉️ 🔅 🔆 〽️ ⚠️ 🚸 🔱 ⚜️ 🔰 ♻️ ✅ 🈯 💹 ❇️ ✳️ ❎ 🌐 💠 Ⓜ️ 🌀 💤 🏧 🚾 ♿ 🅿️ 🛗 🈳 🈂️ 🛂 🛃 🛄 🛅 🚹 🚺 🚼 ⚧️ 🚻 🚮 🎦 📶 🈁 🔣 ℹ️ 🔤 🔡 🔠 🆖 🆗 🆙 🆒 🆕 🆓 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣ 5️⃣ 6️⃣ 7️⃣ 8️⃣ 9️⃣ 🔟 🔢 #️⃣ *️⃣ ▶️ ⏸️ ⏯️ ⏹️ ⏺️ ⏭️ ⏮️ ⏩ ⏪ 🔀 🔁 🔂 ◀️ 🔼 🔽 ⏫ ⏬ ➡️ ⬅️ ⬆️ ⬇️ ↗️ ↘️ ↙️ ↖️ ↕️ ↔️ ↪️ ↩️ ⤴️ ⤵️ 🔃 🔄 🔙 🔚 🔛 🔜 🔝'
              .split(' '),
    ),
    _EmojiGroup(
      label: 'Banderas',
      icon: Icons.flag_outlined,
      keywords: const ['bandera', 'pais', 'flag', 'country'],
      emojis:
          '🏁 🚩 🎌 🏴 🏳️ 🏳️‍🌈 🏳️‍⚧️ 🏴‍☠️ 🇨🇱 🇦🇷 🇧🇷 🇺🇾 🇵🇪 🇧🇴 🇨🇴 🇪🇨 🇻🇪 🇲🇽 🇺🇸 🇨🇦 🇪🇸 🇫🇷 🇩🇪 🇮🇹 🇬🇧 🇵🇹 🇳🇱 🇧🇪 🇨🇭 🇦🇹 🇸🇪 🇳🇴 🇩🇰 🇫🇮 🇮🇪 🇯🇵 🇨🇳 🇰🇷 🇮🇳 🇦🇺 🇳🇿 🇿🇦'
              .split(' '),
    ),
  ];

  static const Map<String, String> _emojiAliases = {
    '😀': 'feliz sonrisa happy smile',
    '😂': 'risa carcajada jajaja laugh joy',
    '🤣': 'risa carcajada rolling laugh',
    '😊': 'feliz amable smile blush',
    '😍': 'amor enamorado love heart eyes',
    '😘': 'beso kiss',
    '😎': 'cool lentes sunglasses',
    '😭': 'llanto llorar cry sob',
    '😡': 'enojo rabia angry',
    '👍': 'ok bien like pulgar',
    '👎': 'mal dislike',
    '🙏': 'gracias por favor pray thanks',
    '🙌': 'celebrar manos hooray',
    '👏': 'aplauso clap',
    '❤️': 'amor corazon heart love',
    '💔': 'corazon roto broken heart',
    '✅': 'check listo correcto ok',
    '❌': 'x error cancelar no',
    '⚠️': 'alerta advertencia warning',
    '📍': 'ubicacion direccion pin location',
    '📸': 'foto camara photo camera',
    '💬': 'mensaje chat comment',
    '🚲': 'bicicleta bici bike',
    '🔧': 'herramienta llave taller tool wrench',
    '🧰': 'herramientas taller toolbox',
    '💵': 'dinero plata money cash',
    '💳': 'tarjeta pago card payment',
    '🧾': 'boleta factura recibo invoice receipt',
    '📦': 'paquete entrega package box',
  };

  static const List<String> _defaultRecentEmojis = [
    '😀',
    '✌️',
    '😅',
    '😂',
    '🙏',
    '😰',
    '🥺',
    '🙌',
    '😢',
    '🤣',
    '❤️',
    '👍',
    '✅',
    '🚲',
    '🔧',
    '📍',
    '📸',
  ];

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _emojiScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _emojiSearchFocusNode = FocusNode();
  final TextEditingController _emojiSearchController = TextEditingController();
  final MessagingService _messagingService = MessagingService();
  bool _isSendingMessage = false;
  bool _isEmojiPickerOpen = false;
  OverlayEntry? _emojiOverlayEntry;
  int _selectedEmojiCategoryIndex = 0;
  int _openingUnreadCount = 0;
  String? _openingUnreadConversationId;
  TextSelection _lastComposerSelection = const TextSelection.collapsed(
    offset: 0,
  );
  final List<String> _recentEmojiChoices = [..._defaultRecentEmojis];

  // Autocomplete State
  List<AutocompleteSuggestion> _suggestions = [];
  Timer? _debounce;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _composerMenuOverlayEntry;
  String? _activeComposerMenuName;
  bool _showAutomaticMessagesPanel = false;
  bool _showChatInfoPanel = false;
  bool _isExportingChatArchive = false;
  _ChatInfoSection _selectedChatInfoSection = _ChatInfoSection.info;
  final GlobalKey _smartActionsButtonKey = GlobalKey();
  final GlobalKey _emojiButtonKey = GlobalKey();
  final GlobalKey _attachmentButtonKey = GlobalKey();
  final GlobalKey _templateButtonKey = GlobalKey();
  Timer? _serviceWindowTicker;
  Future<Map<String, dynamic>?>? _whatsAppContactFuture;
  String? _whatsAppContactFutureConversationId;
  Future<Map<String, dynamic>?>? _conversationContactFuture;
  String? _conversationContactFutureConversationId;

  // Cache futures so FutureBuilder doesn't re-fire on every rebuild.
  final Map<String, Future<Map<String, dynamic>?>> _senderInfoFutureCache = {};

  bool get _isWhatsAppConversation => widget.conversation.isWhatsApp;

  bool get _canUseSmartActions =>
      widget.conversation.isSupport && !widget.conversation.isInternal;

  bool get _canStartWhatsAppFromConversation =>
      widget.conversation.isSupport && widget.conversation.isWebsitePortal;

  void _clearWhatsAppContactCache() {
    _whatsAppContactFuture = null;
    _whatsAppContactFutureConversationId = null;
    _conversationContactFuture = null;
    _conversationContactFutureConversationId = null;
  }

  Future<Map<String, dynamic>?> _getWhatsAppContactFuture() {
    if (_whatsAppContactFutureConversationId != widget.conversation.id) {
      _whatsAppContactFutureConversationId = widget.conversation.id;
      _whatsAppContactFuture = _resolveConversationWhatsAppContact();
    }

    return _whatsAppContactFuture ??= _resolveConversationWhatsAppContact();
  }

  Future<Map<String, dynamic>?> _getConversationContactFuture() {
    if (_isWhatsAppConversation) {
      return _getWhatsAppContactFuture();
    }

    if (!widget.conversation.isSupport) {
      return Future.value(null);
    }

    if (_conversationContactFutureConversationId != widget.conversation.id) {
      _conversationContactFutureConversationId = widget.conversation.id;
      _conversationContactFuture = _resolvePotentialWhatsAppContact();
    }

    return _conversationContactFuture ??= _resolvePotentialWhatsAppContact();
  }

  void _debugLogWhatsAppSend(
    String clientMessageId,
    String phase,
    DateTime startedAt, [
    Map<String, Object?> details = const {},
  ]) {
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    final suffix = details.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    debugPrint(
      '⏱️ [WhatsAppSend] client=$clientMessageId phase=$phase elapsed=${elapsedMs}ms${suffix.isEmpty ? '' : ' $suffix'}',
    );
  }

  Future<void> _markWhatsAppOptimisticAcceptedAfterClock({
    required ChatProvider chatProvider,
    required String optimisticMessageId,
    required DateTime sendStartedAt,
    required String source,
    required bool Function() shouldMarkAccepted,
  }) async {
    final elapsed = DateTime.now().difference(sendStartedAt);
    final remaining = _whatsAppMinimumClockDwell - elapsed;
    if (remaining > Duration.zero) {
      await Future.delayed(remaining);
    }

    if (!shouldMarkAccepted()) {
      _debugLogWhatsAppSend(
        optimisticMessageId,
        'optimistic_status_accepted_skipped',
        sendStartedAt,
        {
          'source': source,
        },
      );
      return;
    }

    chatProvider.updateMessageMetadataById(
      optimisticMessageId,
      {
        'pending': false,
        'external_status': 'accepted',
        'server_ack_optimistic': true,
      },
    );
    _debugLogWhatsAppSend(
      optimisticMessageId,
      'optimistic_status_accepted',
      sendStartedAt,
      {
        'source': source,
      },
    );
  }

  void _syncServiceWindowTicker() {
    _serviceWindowTicker?.cancel();
    _serviceWindowTicker = null;

    if (!_isWhatsAppConversation) return;

    unawaited(_getWhatsAppContactFuture());

    _serviceWindowTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ChatWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.id != widget.conversation.id) {
      _senderInfoFutureCache.clear();
      _clearWhatsAppContactCache();
      _removeEmojiOverlay();
      _removeComposerMenuOverlay(notify: false);
      _showAutomaticMessagesPanel = false;
      _showChatInfoPanel = false;
      _selectedChatInfoSection = _ChatInfoSection.info;
      _syncServiceWindowTicker();
      _captureOpeningUnreadCount();
      _loadMessages();
      _applyPendingDraft();
    }
  }

  @override
  void initState() {
    super.initState();
    _captureOpeningUnreadCount();
    _loadMessages();
    _applyPendingDraft();
    _syncServiceWindowTicker();
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _removeEmojiOverlay();
    _removeComposerMenuOverlay(notify: false);
    _removeOverlay();
    _serviceWindowTicker?.cancel();
    _debounce?.cancel();
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _emojiScrollController.dispose();
    _focusNode.dispose();
    _emojiSearchFocusNode.dispose();
    _emojiSearchController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _debounce?.cancel();

    final text = _messageController.text;
    final selection = _messageController.selection;

    if (_focusNode.hasFocus && selection.isValid) {
      _lastComposerSelection = selection;
    }

    if (selection.baseOffset < 0) return;

    final textBeforeCursor = text.substring(0, selection.baseOffset);
    final hashIndex = textBeforeCursor.lastIndexOf('#');

    if (hashIndex != -1) {
      final query = textBeforeCursor.substring(hashIndex + 1);
      if (!query.contains(' ')) {
        _debounce = Timer(const Duration(milliseconds: 300), () {
          _search(query);
        });
        return;
      }
    }

    _removeOverlay();
  }

  Future<void> _search(String query) async {
    final suggestions = <AutocompleteSuggestion>[];

    try {
      if (query.isEmpty || query.toUpperCase().startsWith('J')) {
        final term =
            query.toUpperCase().replaceAll('JOB-', '').replaceAll('JOB', '');
        final jobs =
            await context.read<BikeshopService>().getJobs(searchTerm: term);
        suggestions.addAll(jobs.take(3).map((job) => AutocompleteSuggestion(
              id: 'JOB-${job.jobNumber}',
              title: 'Job #${job.jobNumber ?? "N/A"}',
              subtitle:
                  '${job.assignedTechnicianName ?? "Sin mecánico"} - ${job.status.name}',
              type: SuggestionType.job,
            )));
      }

      if (query.isEmpty || query.toUpperCase().startsWith('I')) {
        final term =
            query.toUpperCase().replaceAll('INV-', '').replaceAll('INV', '');
        final invoices = context.read<SalesService>().searchInvoices(term);
        suggestions
            .addAll(invoices.take(3).map((invoice) => AutocompleteSuggestion(
                  id: 'INV-${invoice.invoiceNumber}',
                  title: 'Invoice #${invoice.invoiceNumber}',
                  subtitle:
                      '${invoice.customerName} - \$${invoice.total.toStringAsFixed(0)}',
                  type: SuggestionType.invoice,
                )));
      }
    } catch (e) {
      debugPrint('Autocomplete Error: $e');
    }

    if (mounted) {
      setState(() => _suggestions = suggestions);
      if (suggestions.isNotEmpty) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 300,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, -200),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: Colors.grey[200]!)),
                      color: Colors.grey[50],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.flash_on, size: 16, color: Colors.amber),
                        SizedBox(width: 4),
                        Text(
                          'Quick Insert',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final item = _suggestions[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            item.type == SuggestionType.job
                                ? Icons.build
                                : Icons.receipt,
                            size: 16,
                            color: Colors.blue,
                          ),
                          title: Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            item.subtitle ?? '',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => _applySuggestion(item),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final currentOverlay = _overlayEntry;
    if (currentOverlay != null) {
      Overlay.of(context).insert(currentOverlay);
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _toggleEmojiPicker() {
    if (_emojiOverlayEntry != null) {
      _hideEmojiPicker(restoreComposerFocus: true);
      return;
    }

    _removeOverlay();
    _removeComposerMenuOverlay(notify: false);
    _rememberComposerSelection();
    _isEmojiPickerOpen = true;
    _emojiOverlayEntry = OverlayEntry(
      builder: (context) => _buildEmojiOverlay(context),
    );
    Overlay.of(context).insert(_emojiOverlayEntry!);
    setState(() {});
  }

  void _hideEmojiPicker({bool restoreComposerFocus = false}) {
    _removeEmojiOverlay();
    if (mounted) setState(() {});
    if (restoreComposerFocus) _restoreComposerFocus();
  }

  void _removeEmojiOverlay() {
    _emojiOverlayEntry?.remove();
    _emojiOverlayEntry = null;
    _isEmojiPickerOpen = false;
    _emojiSearchController.clear();
  }

  void _refreshEmojiPicker() {
    if (mounted) setState(() {});
    _emojiOverlayEntry?.markNeedsBuild();
  }

  void _toggleComposerMenu({
    required String name,
    required GlobalKey anchorKey,
    required double width,
    required double estimatedHeight,
    required Widget Function(BuildContext overlayContext) panelBuilder,
  }) {
    if (_activeComposerMenuName == name && _composerMenuOverlayEntry != null) {
      _removeComposerMenuOverlay(restoreComposerFocus: true);
      return;
    }

    _removeEmojiOverlay();
    _removeOverlay();
    _removeComposerMenuOverlay(notify: false);
    _rememberComposerSelection();

    _activeComposerMenuName = name;
    _composerMenuOverlayEntry = OverlayEntry(
      builder: (overlayContext) => _buildAnchoredComposerOverlay(
        overlayContext: overlayContext,
        anchorKey: anchorKey,
        width: width,
        estimatedHeight: estimatedHeight,
        onDismiss: () => _removeComposerMenuOverlay(
          restoreComposerFocus: true,
        ),
        child: panelBuilder(overlayContext),
      ),
    );
    Overlay.of(context).insert(_composerMenuOverlayEntry!);
    if (mounted) setState(() {});
  }

  void _removeComposerMenuOverlay({
    bool restoreComposerFocus = false,
    bool notify = true,
  }) {
    _composerMenuOverlayEntry?.remove();
    _composerMenuOverlayEntry = null;
    _activeComposerMenuName = null;
    _showAutomaticMessagesPanel = false;
    if (notify && mounted) setState(() {});
    if (restoreComposerFocus) _restoreComposerFocus();
  }

  Widget _buildAnchoredComposerOverlay({
    required BuildContext overlayContext,
    required GlobalKey anchorKey,
    required double width,
    required double estimatedHeight,
    required Widget child,
    required VoidCallback onDismiss,
  }) {
    final overlayBox = Overlay.of(
      overlayContext,
    ).context.findRenderObject() as RenderBox?;
    final anchorBox =
        anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final screenSize = MediaQuery.sizeOf(overlayContext);
    final overlaySize = overlayBox?.size ?? screenSize;
    final effectiveWidth = width
        .clamp(260.0, (overlaySize.width - 24).clamp(260.0, width))
        .toDouble();
    final anchorOffset = overlayBox != null && anchorBox != null
        ? overlayBox.globalToLocal(anchorBox.localToGlobal(Offset.zero))
        : Offset(12, overlaySize.height - estimatedHeight - 72);
    final anchorSize = anchorBox?.size ?? const Size(40, 40);
    final anchorRect = anchorOffset & anchorSize;
    final horizontalLimit =
        (overlaySize.width - effectiveWidth - 12).clamp(12.0, double.infinity);
    final left = (anchorRect.center.dx - effectiveWidth / 2)
        .clamp(12.0, horizontalLimit)
        .toDouble();
    final preferredTop = anchorRect.top - estimatedHeight - 8;
    final fallbackTop = anchorRect.bottom + 8;
    final verticalLimit = (overlaySize.height - estimatedHeight - 12)
        .clamp(12.0, double.infinity);
    final top = (preferredTop >= 12 ? preferredTop : fallbackTop)
        .clamp(12.0, verticalLimit)
        .toDouble();
    final maxPanelHeight = (overlaySize.height - top - 12)
        .clamp(120.0, overlaySize.height - 24)
        .toDouble();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: effectiveWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxPanelHeight),
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComposerPopoverPanel({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor.withValues(alpha: 0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: iconColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _removeComposerMenuOverlay(
                      restoreComposerFocus: true,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: theme.dividerColor),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerPopoverAction({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _captureOpeningUnreadCount() {
    final provider = context.read<ChatProvider>();
    final count = provider.takeOpeningUnreadCount(
      widget.conversation.id,
      fallback: widget.conversation.unreadCount,
    );
    _openingUnreadConversationId = widget.conversation.id;
    _openingUnreadCount = count > 0 ? count : 0;
  }

  TextSelection _safeComposerSelection(
      TextSelection selection, int textLength) {
    if (!selection.isValid) {
      final offset = _lastComposerSelection.baseOffset.clamp(0, textLength);
      return TextSelection.collapsed(offset: offset);
    }

    final start = selection.start.clamp(0, textLength);
    final end = selection.end.clamp(0, textLength);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  void _rememberComposerSelection() {
    final textLength = _messageController.text.length;
    _lastComposerSelection = _safeComposerSelection(
      _messageController.selection,
      textLength,
    );
  }

  void _applySuggestion(AutocompleteSuggestion item) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final textBeforeCursor = text.substring(0, selection.baseOffset);
    final hashIndex = textBeforeCursor.lastIndexOf('#');

    if (hashIndex != -1) {
      final newText =
          text.replaceRange(hashIndex, selection.baseOffset, '#${item.id} ');
      _messageController.value = TextEditingValue(
        text: newText,
        selection:
            TextSelection.collapsed(offset: hashIndex + item.id.length + 2),
      );
    }
    _removeOverlay();
  }

  void _insertEmoji(String emoji) {
    final value = _messageController.value;
    final text = value.text;
    final selection = _focusNode.hasFocus
        ? _safeComposerSelection(value.selection, text.length)
        : _safeComposerSelection(_lastComposerSelection, text.length);
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    final safeStart = start.clamp(0, text.length);
    final safeEnd = end.clamp(0, text.length);
    final newText = text.replaceRange(safeStart, safeEnd, emoji);
    final nextSelection = TextSelection.collapsed(
      offset: safeStart + emoji.length,
    );

    _messageController.value = TextEditingValue(
      text: newText,
      selection: nextSelection,
    );
    _lastComposerSelection = nextSelection;
    setState(() {
      _recentEmojiChoices.remove(emoji);
      _recentEmojiChoices.insert(0, emoji);
      if (_recentEmojiChoices.length > 32) {
        _recentEmojiChoices.removeRange(32, _recentEmojiChoices.length);
      }
    });
    _emojiOverlayEntry?.markNeedsBuild();
    _restoreComposerFocus(selection: nextSelection);
  }

  void _loadMessages() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ChatProvider>();
      provider.setActiveConversation(widget.conversation.id);
      if (_openingUnreadCount == 0) {
        final count = provider.takeOpeningUnreadCount(widget.conversation.id);
        if (count > 0 && mounted) {
          setState(() {
            _openingUnreadConversationId = widget.conversation.id;
            _openingUnreadCount = count;
          });
        }
      }
    });
  }

  List<Object> _buildTimelineItems(List<Message> messages) {
    final markerMessageId = _unreadMarkerBeforeMessageId(messages);
    final items = <Object>[];

    for (final message in messages) {
      if (message.id == markerMessageId) {
        items.add(_UnreadMessagesMarker(_openingUnreadCount));
      }
      items.add(message);
    }

    return items;
  }

  String? _unreadMarkerBeforeMessageId(List<Message> messages) {
    if (_openingUnreadConversationId != widget.conversation.id ||
        _openingUnreadCount <= 0 ||
        messages.isEmpty) {
      return null;
    }

    var remainingUnreadInbound = _openingUnreadCount;
    String? oldestAvailableUnreadId;

    for (var index = messages.length - 1; index >= 0; index--) {
      final message = messages[index];
      if (!_isUnreadInboundCandidate(message)) continue;

      oldestAvailableUnreadId = message.id;
      remainingUnreadInbound--;
      if (remainingUnreadInbound <= 0) return message.id;
    }

    return oldestAvailableUnreadId;
  }

  bool _isUnreadInboundCandidate(Message message) {
    return !message.isMe && message.type != 'system';
  }

  void _applyPendingDraft() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _messageController.text.trim().isNotEmpty) return;

      final draft = context
          .read<ChatProvider>()
          .getConversationDraft(widget.conversation.id)
          ?.body;
      if (draft == null || draft.trim().isEmpty) return;

      _messageController.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
      _restoreComposerFocus();
    });
  }

  Future<void> _sendMessage({Map<String, dynamic>? metadata}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSendingMessage) {
      return;
    }
    final chatProvider = context.read<ChatProvider>();
    final pendingText = text;
    final messageMetadata = <String, dynamic>{...?metadata};

    if (_isWhatsAppConversation) {
      // Snappy precheck: derive the 24h window state from messages we already
      // have in memory instead of awaiting the contact DB query. The contact
      // lookup is still kicked off in the background (and surfaced via the
      // gauge / dispatch); if the cached window check is wrong we'll get the
      // re-engagement code from Graph and fall back to a template anyway.
      final lastInboundAt = _resolveLastInboundAt(
        null,
        chatProvider.activeMessages,
      );
      if (!_isWhatsAppServiceWindowOpen(lastInboundAt)) {
        _showWhatsAppTemplatePicker(pendingText: pendingText);
        return;
      }
      // Warm the contact future so _dispatchWhatsAppSend below doesn't pay
      // the lookup cost serially.
      unawaited(_getWhatsAppContactFuture());
    }

    _messageController.clear();
    _restoreComposerFocus();
    setState(() {
      _isSendingMessage = true;
      _isEmojiPickerOpen = false;
    });

    try {
      if (!_isWhatsAppConversation) {
        await chatProvider.sendMessage(
          pendingText,
          metadata: messageMetadata.isEmpty ? null : messageMetadata,
        );
        if (!mounted) {
          return;
        }
        return;
      }

      final sendStartedAt = DateTime.now();
      final optimisticMessageId =
          'temp-wa-${sendStartedAt.millisecondsSinceEpoch}';
      chatProvider.addOptimisticMessage(
        Message(
          id: optimisticMessageId,
          conversationId: widget.conversation.id,
          senderId: _messagingService.currentUserId,
          content: pendingText,
          type: 'text',
          metadata: {
            ...messageMetadata,
            'channel': 'whatsapp',
            'provider': 'whatsapp',
            'pending': true,
            'client_message_id': optimisticMessageId,
          },
          createdAt: DateTime.now(),
          isMe: true,
        ),
      );
      _debugLogWhatsAppSend(
        optimisticMessageId,
        'optimistic_clock_rendered',
        sendStartedAt,
        {
          'conversation': widget.conversation.id,
        },
      );

      // Bubble is in. Release the composer immediately so the user can keep
      // typing/sending while the contact lookup + Cloud API round trip
      // happens in the background, like a real chat app.
      if (mounted) {
        setState(() => _isSendingMessage = false);
      }
      unawaited(_dispatchWhatsAppSend(
        chatProvider: chatProvider,
        optimisticMessageId: optimisticMessageId,
        pendingText: pendingText,
        sendStartedAt: sendStartedAt,
      ));
      return;
    } catch (e) {
      if (!mounted) {
        return;
      }
      if (_messageController.text.trim().isEmpty) {
        _messageController.text = pendingText;
        _messageController.selection = TextSelection.collapsed(
          offset: _messageController.text.length,
        );
      }
      _restoreComposerFocus();
      _showErrorSnackBar(context, 'No se pudo enviar el mensaje: $e');
    } finally {
      if (mounted && _isSendingMessage) {
        setState(() => _isSendingMessage = false);
      }
    }
  }

  Future<void> _dispatchWhatsAppSend({
    required ChatProvider chatProvider,
    required String optimisticMessageId,
    required String pendingText,
    required DateTime sendStartedAt,
  }) async {
    final whatsappService = WhatsAppService();
    try {
      final contactWaitStartedAt = DateTime.now();
      final contact = await _getWhatsAppContactFuture();
      _debugLogWhatsAppSend(
        optimisticMessageId,
        'contact_ready',
        sendStartedAt,
        {
          'waitMs':
              DateTime.now().difference(contactWaitStartedAt).inMilliseconds,
          'hasPhone': contact?['phone'] != null,
        },
      );
      final phone = contact?['phone']?.toString();
      final lastInboundAt = _resolveLastInboundAt(
        contact,
        chatProvider.activeMessages,
      );

      if (phone == null || phone.isEmpty) {
        _debugLogWhatsAppSend(
          optimisticMessageId,
          'failed_no_phone',
          sendStartedAt,
        );
        chatProvider.removeMessageById(optimisticMessageId);
        if (mounted) {
          _showErrorSnackBar(
            context,
            'La conversación de WhatsApp no tiene un teléfono asociado.',
          );
        }
        return;
      }

      _debugLogWhatsAppSend(
        optimisticMessageId,
        'cloud_request_start',
        sendStartedAt,
        {
          'windowOpen': _isWhatsAppServiceWindowOpen(lastInboundAt),
        },
      );

      var sendCompleted = false;
      bool? sendResult;
      final sendFuture = whatsappService
          .sendMessage(
        context: context,
        customerPhone: phone,
        message: pendingText,
        contactName: contact?['name']?.toString(),
        conversationId: widget.conversation.id,
        contextType: widget.conversation.contextType,
        contextId: widget.conversation.contextId,
        lastInboundAt: lastInboundAt,
        clientMessageId: optimisticMessageId,
      )
          .then(
        (value) {
          sendCompleted = true;
          sendResult = value;
          return value;
        },
        onError: (Object error, StackTrace stackTrace) {
          sendCompleted = true;
          Error.throwWithStackTrace(error, stackTrace);
        },
      );

      await _markWhatsAppOptimisticAcceptedAfterClock(
        chatProvider: chatProvider,
        optimisticMessageId: optimisticMessageId,
        sendStartedAt: sendStartedAt,
        source: 'cloud_request_started_after_clock',
        shouldMarkAccepted: () => !sendCompleted || sendResult == true,
      );

      final success =
          sendCompleted && sendResult != null ? sendResult! : await sendFuture;
      _debugLogWhatsAppSend(
        optimisticMessageId,
        'cloud_request_done',
        sendStartedAt,
        {
          'success': success,
          'delivery': whatsappService.lastDeliveryMethod.name,
          'external': whatsappService.lastExternalMessageId,
          'error': whatsappService.lastErrorCode,
        },
      );

      if (!success) {
        _debugLogWhatsAppSend(
          optimisticMessageId,
          'failed_cloud_or_fallback',
          sendStartedAt,
          {
            'delivery': whatsappService.lastDeliveryMethod.name,
            'error': whatsappService.lastErrorCode,
          },
        );
        chatProvider.updateMessageMetadataById(
          optimisticMessageId,
          {
            'pending': false,
            'external_status': 'failed',
            'server_ack_optimistic': false,
            'whatsapp_status_payload': {
              'errors': [
                {
                  'message': whatsappService.lastErrorRequiresServerFix
                      ? 'Meta rechazó el envío porque el token de WhatsApp Cloud API expiró. Hay que actualizar WHATSAPP_ACCESS_TOKEN en Supabase.'
                      : 'No se pudo enviar el mensaje por WhatsApp',
                },
              ],
            },
          },
        );
        if (mounted) {
          if (_messageController.text.trim().isEmpty) {
            _messageController.text = pendingText;
            _messageController.selection = TextSelection.collapsed(
              offset: _messageController.text.length,
            );
          }
          final errorMessage = whatsappService.lastErrorRequiresServerFix
              ? 'Meta rechazó el envío porque el token de WhatsApp Cloud API expiró. Hay que actualizar WHATSAPP_ACCESS_TOKEN en Supabase.'
              : 'No se pudo enviar el mensaje por WhatsApp';
          _showErrorSnackBar(context, errorMessage);
        }
        return;
      }

      if (whatsappService.lastDeliveryMethod ==
          WhatsAppDeliveryMethod.cloudApi) {
        if (whatsappService.lastUsedFirstContactTemplate) {
          chatProvider.setConversationDraft(
            widget.conversation.id,
            pendingText,
            title: 'Mensaje pendiente de ventana WhatsApp',
            subtitle:
                'Se envió la plantilla aprobada. Cuando el cliente responda, puedes enviar este texto.',
          );
        } else {
          chatProvider.clearConversationDraft(widget.conversation.id);
        }
        chatProvider.updateMessageById(
          optimisticMessageId,
          content: whatsappService.lastResolvedMessageText ?? pendingText,
          metadataUpdates: {
            'pending': false,
            'external_status': 'accepted',
            'server_ack_optimistic': false,
            if (whatsappService.lastExternalMessageId != null)
              'external_message_id': whatsappService.lastExternalMessageId,
            if (whatsappService.lastUsedFirstContactTemplate)
              'template_used': true,
          },
        );
        _debugLogWhatsAppSend(
          optimisticMessageId,
          'cloud_ack_confirmed',
          sendStartedAt,
          {
            'external': whatsappService.lastExternalMessageId,
            'template': whatsappService.lastUsedFirstContactTemplate,
          },
        );

        if (whatsappService.lastUsedFirstContactTemplate && mounted) {
          _showWhatsAppResultSnackbar(
            context: context,
            deliveryMethod: whatsappService.lastDeliveryMethod,
            successMessage:
                'Meta pidió plantilla para abrir o reabrir la ventana de WhatsApp. Se envió la plantilla aprobada.',
            fallbackMessage: 'WhatsApp abierto con el mensaje prellenado',
          );
        }
      } else if (whatsappService.lastDeliveryMethod ==
          WhatsAppDeliveryMethod.manualFallback) {
        chatProvider.removeMessageById(optimisticMessageId);
        if (mounted) {
          if (_messageController.text.isEmpty) {
            _messageController.text = pendingText;
          }
          _showWhatsAppResultSnackbar(
            context: context,
            deliveryMethod: whatsappService.lastDeliveryMethod,
            successMessage: 'Mensaje enviado por WhatsApp Cloud API',
            fallbackMessage: 'WhatsApp abierto con el mensaje prellenado',
          );
        }
      }
    } catch (e) {
      chatProvider.removeMessageById(optimisticMessageId);
      if (mounted) {
        if (_messageController.text.trim().isEmpty) {
          _messageController.text = pendingText;
          _messageController.selection = TextSelection.collapsed(
            offset: _messageController.text.length,
          );
        }
        _showErrorSnackBar(context, 'No se pudo enviar el mensaje: $e');
      }
    }
  }

  void _restoreComposerFocus({TextSelection? selection}) {
    // On Web, post-frame callback isn't always enough due to engine/DOM sync.
    // A small delay ensures the focus request happens after the UI settles.
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
        if (selection != null) {
          final textLength = _messageController.text.length;
          final offset = selection.baseOffset.clamp(0, textLength);
          final safeSelection = TextSelection.collapsed(offset: offset);
          _messageController.selection = safeSelection;
          _lastComposerSelection = safeSelection;
        }
      }
    });
  }

  /// Accept a pending chat request
  Future<void> _acceptChatRequest(BuildContext ctx) async {
    try {
      final provider = ctx.read<ChatProvider>();
      await provider.acceptChatRequest(widget.conversation.id);
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('Chat aceptado. Ahora puedes responder.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Show reject dialog with reason input
  void _showRejectDialog(BuildContext ctx) {
    final reasonController = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('¿Por qué rechazas esta solicitud? (opcional)'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Motivo del rechazo...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                final provider = ctx.read<ChatProvider>();
                await provider.rejectChatRequest(
                  widget.conversation.id,
                  reasonController.text.trim(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Solicitud rechazada'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
  }

  void _showAttachmentOptions() {
    _toggleComposerMenu(
      name: 'attachments',
      anchorKey: _attachmentButtonKey,
      width: 330,
      estimatedHeight: kIsWeb ? 210 : 260,
      panelBuilder: (overlayContext) => _buildComposerPopoverPanel(
        context: overlayContext,
        icon: Icons.attach_file,
        iconColor: _accentBlue,
        title: 'Adjuntar',
        children: [
          _buildComposerPopoverAction(
            icon: Icons.photo_library_outlined,
            color: const Color(0xFF2563EB),
            title: 'Galería',
            subtitle: 'Enviar una imagen desde el equipo',
            onTap: () {
              _removeComposerMenuOverlay(notify: true);
              _pickAndSendFile('gallery');
            },
          ),
          if (!kIsWeb)
            _buildComposerPopoverAction(
              icon: Icons.camera_alt_outlined,
              color: const Color(0xFF059669),
              title: 'Cámara',
              subtitle: 'Tomar una foto y enviarla',
              onTap: () {
                _removeComposerMenuOverlay(notify: true);
                _pickAndSendFile('camera');
              },
            ),
          _buildComposerPopoverAction(
            icon: Icons.insert_drive_file_outlined,
            color: const Color(0xFF7C3AED),
            title: 'Archivo',
            subtitle: 'PDF, documento, planilla o imagen',
            onTap: () {
              _removeComposerMenuOverlay(notify: true);
              _pickAndSendFile('file');
            },
          ),
        ],
      ),
    );
  }

  /// Pick and send a file (image, PDF, document, etc.)
  Future<void> _pickAndSendFile(String choice) async {
    if (!mounted) return;

    try {
      late String fileName;
      Uint8List? bytes;

      if (choice == 'camera') {
        // Use ImagePicker for camera
        final picker = ImagePicker();
        final XFile? pickedFile = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1200,
          imageQuality: 85,
        );
        if (pickedFile == null) return;
        fileName = pickedFile.name;
        bytes = await pickedFile.readAsBytes();
      } else if (choice == 'gallery') {
        // Use ImagePicker for gallery (better image handling)
        final picker = ImagePicker();
        final XFile? pickedFile = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1200,
          imageQuality: 85,
        );
        if (pickedFile == null) return;
        fileName = pickedFile.name;
        bytes = await pickedFile.readAsBytes();
      } else {
        // Use FilePicker for documents
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'txt',
            'png',
            'jpg',
            'jpeg',
            'gif'
          ],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.first;
        fileName = file.name;
        bytes = file.bytes;
      }

      if (bytes == null || !mounted) return;

      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Subiendo archivo...'),
          ]),
          duration: Duration(seconds: 60),
        ),
      );

      // Determine file type and MIME
      final ext = _resolveFileExtension(fileName);
      final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
      final contentType = _contentTypeForExtension(ext);
      final safeFileName = _safeStorageFileName(
        fileName,
        fallbackExtension: ext,
      );

      final storagePath =
          'chat/${widget.conversation.id}/${DateTime.now().millisecondsSinceEpoch}_$safeFileName';

      // Upload to Supabase Storage (vinabike-assets bucket)
      final supabase = Supabase.instance.client;
      await supabase.storage.from('vinabike-assets').uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );

      // Get public URL
      final publicUrl =
          supabase.storage.from('vinabike-assets').getPublicUrl(storagePath);

      if (!mounted) return;

      // Dismiss loading snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Determine message type
      final msgType = isImage ? 'image' : 'file';
      final metadata = {
        'url': publicUrl,
        'filename': fileName,
        'originalFilename': fileName,
        'storageFilename': safeFileName,
        'extension': ext,
        'contentType': contentType,
        'content_type': contentType,
        'sizeBytes': bytes.length,
        'storageBucket': 'vinabike-assets',
        'storagePath': storagePath,
      };

      if (_isWhatsAppConversation) {
        _sendWhatsAppAttachment(
          chatProvider: context.read<ChatProvider>(),
          publicUrl: publicUrl,
          fileName: fileName,
          messageType: msgType,
          metadata: metadata,
        );
        return;
      }

      // Send as file message
      await context.read<ChatProvider>().sendMessage(
            publicUrl,
            type: msgType,
            metadata: metadata,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error al subir archivo: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  String _resolveFileExtension(String fileName) {
    final normalizedName = fileName.trim().split(RegExp(r'[\\/]')).last;
    final dotIndex = normalizedName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == normalizedName.length - 1) {
      return '';
    }
    return normalizedName.substring(dotIndex + 1).toLowerCase();
  }

  String _safeStorageFileName(
    String fileName, {
    String fallbackExtension = '',
  }) {
    final originalName = fileName.trim().split(RegExp(r'[\\/]')).last;
    final candidate = originalName.isEmpty ? 'archivo' : originalName;
    var cleaned = candidate
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^[._-]+'), '')
        .replaceAll(RegExp(r'[._-]+$'), '');

    if (cleaned.isEmpty) {
      cleaned = 'archivo';
    }

    final cleanedExtension = _resolveFileExtension(cleaned);
    if (cleanedExtension.isEmpty && fallbackExtension.isNotEmpty) {
      cleaned = '$cleaned.$fallbackExtension';
    }

    if (cleaned.length <= 96) {
      return cleaned;
    }

    final extension = _resolveFileExtension(cleaned);
    if (extension.isEmpty) {
      return cleaned.substring(0, 96);
    }

    final suffix = '.$extension';
    final baseLength = 96 - suffix.length;
    final safeBaseLength = baseLength.clamp(1, cleaned.length).toInt();
    return '${cleaned.substring(0, safeBaseLength)}$suffix';
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  void _sendWhatsAppAttachment({
    required ChatProvider chatProvider,
    required String publicUrl,
    required String fileName,
    required String messageType,
    required Map<String, dynamic> metadata,
  }) {
    final optimisticMessageId =
        'temp-wa-file-${DateTime.now().millisecondsSinceEpoch}';
    final sendMetadata = {
      ...metadata,
      'channel': 'whatsapp',
      'provider': 'whatsapp',
      'client_message_id': optimisticMessageId,
    };
    final optimisticMetadata = {
      ...sendMetadata,
      'pending': true,
    };

    chatProvider.addOptimisticMessage(
      Message(
        id: optimisticMessageId,
        conversationId: widget.conversation.id,
        senderId: _messagingService.currentUserId,
        content: publicUrl,
        type: messageType,
        metadata: optimisticMetadata,
        createdAt: DateTime.now(),
        isMe: true,
      ),
    );

    unawaited(_dispatchWhatsAppAttachment(
      chatProvider: chatProvider,
      optimisticMessageId: optimisticMessageId,
      publicUrl: publicUrl,
      fileName: fileName,
      messageType: messageType,
      metadata: sendMetadata,
    ));
  }

  Future<void> _dispatchWhatsAppAttachment({
    required ChatProvider chatProvider,
    required String optimisticMessageId,
    required String publicUrl,
    required String fileName,
    required String messageType,
    required Map<String, dynamic> metadata,
  }) async {
    final whatsappService = WhatsAppService();
    try {
      final contact = await _getWhatsAppContactFuture();
      final phone = contact?['phone']?.toString();

      if (phone == null || phone.isEmpty) {
        chatProvider.removeMessageById(optimisticMessageId);
        if (mounted) {
          _showErrorSnackBar(
            context,
            'La conversación de WhatsApp no tiene un teléfono asociado.',
          );
        }
        return;
      }

      if (!mounted) {
        chatProvider.removeMessageById(optimisticMessageId);
        return;
      }

      final success = await whatsappService.sendAttachment(
        context: context,
        customerPhone: phone,
        mediaUrl: publicUrl,
        filename: fileName,
        messageType: messageType,
        contactName: contact?['name']?.toString(),
        conversationId: widget.conversation.id,
        customerId: contact?['customer_id']?.toString(),
        contextType: widget.conversation.contextType,
        contextId: widget.conversation.contextId,
        clientMessageId: optimisticMessageId,
        metadata: metadata,
      );

      if (!success) {
        chatProvider.removeMessageById(optimisticMessageId);
        if (mounted) {
          final errorMessage = whatsappService.lastErrorRequiresServerFix
              ? 'Meta rechazó el envío porque el token de WhatsApp Cloud API expiró. Hay que actualizar WHATSAPP_ACCESS_TOKEN en Supabase.'
              : whatsappService.lastErrorRequiresCustomerReply
                  ? 'Meta no permite enviar archivos fuera de la ventana de 24 horas. Envía una plantilla y espera respuesta del cliente antes de compartir la imagen.'
                  : 'No se pudo enviar el archivo por WhatsApp';
          _showErrorSnackBar(context, errorMessage);
        }
        return;
      }

      if (whatsappService.lastDeliveryMethod ==
          WhatsAppDeliveryMethod.cloudApi) {
        chatProvider.updateMessageById(
          optimisticMessageId,
          metadataUpdates: {
            'pending': false,
            'external_status': 'accepted',
            if (whatsappService.lastExternalMessageId != null)
              'external_message_id': whatsappService.lastExternalMessageId,
          },
        );
      } else if (whatsappService.lastDeliveryMethod ==
          WhatsAppDeliveryMethod.manualFallback) {
        chatProvider.removeMessageById(optimisticMessageId);
        if (mounted) {
          _showWhatsAppResultSnackbar(
            context: context,
            deliveryMethod: whatsappService.lastDeliveryMethod,
            successMessage: 'Archivo enviado por WhatsApp Cloud API',
            fallbackMessage: 'WhatsApp abierto con el archivo como enlace',
          );
        }
      }
    } catch (e) {
      chatProvider.removeMessageById(optimisticMessageId);
      if (mounted) {
        _showErrorSnackBar(context, 'No se pudo enviar el archivo: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final messages = chatProvider.activeMessages;
    final timelineItems = _buildTimelineItems(messages);
    final isLoading = chatProvider.isLoading;
    final pendingDraft =
        chatProvider.getConversationDraft(widget.conversation.id);

    return Column(
      children: [
        _buildHeader(context, chatProvider),

        if (pendingDraft != null) _buildPreparedHandoffBanner(pendingDraft),

        // Pending Chat Request Banner (for employees reviewing customer requests)
        if (widget.conversation.type == 'support' &&
            widget.conversation.status == 'pending')
          _buildPendingRequestBanner(context),

        if (_showChatInfoPanel)
          Expanded(
            child: _buildChatInfoPanel(context, chatProvider, messages),
          )
        else ...[
          // Messages
          Expanded(
            child: Container(
              color: Colors.grey[50], // Light background for chat area
              child: isLoading && messages.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true, // Start from bottom
                      padding: const EdgeInsets.all(16),
                      itemCount: timelineItems.length,
                      itemBuilder: (context, index) {
                        // Reverse index to show newest at bottom
                        final item =
                            timelineItems[timelineItems.length - 1 - index];
                        if (item is _UnreadMessagesMarker) {
                          return _buildUnreadMessagesMarker(item.count);
                        }

                        final msg = item as Message;
                        // Check continuity for bubble grouping (optional enhancement space)
                        return _buildMessageBubble(context, msg, messages);
                      },
                    ),
            ),
          ),

          // Input
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
            ),
            child: _buildComposer(context),
          ),
        ],
      ],
    );
  }

  Widget _buildPendingRequestBanner(BuildContext context) {
    final textBlock = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Solicitud de chat pendiente',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.orange[900],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'El cliente espera respuesta. Acepta para comenzar a chatear.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.orange[800],
            ),
          ),
        ],
      ),
    );

    final actions = [
      OutlinedButton(
        onPressed: () => _showRejectDialog(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red[700],
        ),
        child: const Text('Rechazar'),
      ),
      FilledButton.icon(
        onPressed: () => _acceptChatRequest(context),
        icon: const Icon(Icons.check, size: 18),
        label: const Text('Aceptar'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.green[600],
        ),
      ),
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 12 : 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        border: Border(
          bottom: BorderSide(color: Colors.orange[200]!),
        ),
      ),
      child: widget.compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.pending_actions, color: Colors.orange[700]),
                    const SizedBox(width: 10),
                    textBlock,
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ],
            )
          : Row(
              children: [
                Icon(Icons.pending_actions, color: Colors.orange[700]),
                const SizedBox(width: 12),
                textBlock,
                const SizedBox(width: 12),
                actions[0],
                const SizedBox(width: 8),
                actions[1],
              ],
            ),
    );
  }

  Widget _buildHeader(BuildContext context, ChatProvider chatProvider) {
    final conversation = widget.conversation;
    final hasContext = conversation.hasLinkedContext;
    final hasSupportedContextPanel = conversation.hasSupportedContextPanel;
    final title = chatProvider.getChatTitle(conversation);
    final subtitle = _buildConversationSubtitle(conversation);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 10 : 16,
        vertical: widget.compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _toggleChatInfoPanel,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: widget.compact ? 17 : 20,
                        backgroundColor: conversation.type == 'support'
                            ? _accentBlue.withValues(alpha: 0.08)
                            : Colors.grey[200],
                        child: Icon(
                          conversation.isWhatsApp
                              ? Icons.phone_in_talk_outlined
                              : conversation.isWebsitePortal
                                  ? Icons.language_outlined
                                  : Icons.groups_outlined,
                          color: conversation.type == 'support'
                              ? _accentBlue
                              : Colors.grey[700],
                          size: 20,
                        ),
                      ),
                      SizedBox(width: widget.compact ? 9 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: widget.compact ? 4 : 8),
                      Icon(
                        _showChatInfoPanel
                            ? Icons.keyboard_arrow_up
                            : Icons.info_outline,
                        size: 18,
                        color: _showChatInfoPanel ? _accentBlue : Colors.grey,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (_canStartWhatsAppFromConversation)
            IconButton(
              icon: const Icon(Icons.phone_in_talk_outlined),
              color: _accentBlue,
              tooltip: 'Contactar por WhatsApp',
              onPressed: _isSendingMessage
                  ? null
                  : () => _openWhatsAppConversationForCurrentContext(context),
            ),
          if (hasSupportedContextPanel &&
              widget.isContextPanelClosed &&
              widget.onShowContextPanel != null)
            IconButton(
              icon: Icon(
                _contextIcon(conversation.contextType),
                color: _accentBlue,
              ),
              tooltip: 'Mostrar detalles',
              onPressed: widget.onShowContextPanel,
            ),
          IconButton(
            icon: Icon(
              hasContext ? Icons.link : Icons.link_off,
              color: hasContext ? _accentBlue : Colors.grey,
            ),
            tooltip: hasContext
                ? 'Contexto vinculado: ${_contextLabel(conversation.contextType)}'
                : 'Vincular contexto del chat',
            onPressed: () => _showAssignContextDialog(context),
          ),
          ...widget.headerActions,
        ],
      ),
    );
  }

  void _toggleChatInfoPanel() {
    _removeOverlay();
    _removeEmojiOverlay();
    _removeComposerMenuOverlay(notify: false);
    setState(() {
      _showChatInfoPanel = !_showChatInfoPanel;
      if (!_showChatInfoPanel) {
        _selectedChatInfoSection = _ChatInfoSection.info;
      }
    });
  }

  Widget _buildChatInfoPanel(
    BuildContext context,
    ChatProvider chatProvider,
    List<Message> messages,
  ) {
    final theme = Theme.of(context);
    final title = chatProvider.getChatTitle(widget.conversation);
    final subtitle = _buildConversationSubtitle(widget.conversation);
    final attachments = _collectChatAttachments(messages);
    final mediaCount =
        attachments.where((attachment) => attachment.isImage).length;
    final fileCount = attachments.length - mediaCount;

    Widget contentForSection() {
      return switch (_selectedChatInfoSection) {
        _ChatInfoSection.info => _buildChatInfoOverview(
            theme: theme,
            title: title,
            subtitle: subtitle,
            messages: messages,
            attachments: attachments,
          ),
        _ChatInfoSection.media => _buildChatMediaSection(
            theme: theme,
            attachments: attachments,
          ),
        _ChatInfoSection.workflow => _buildChatWorkflowSection(theme),
        _ChatInfoSection.backup => _buildChatBackupSection(
            theme: theme,
            messages: messages,
            attachments: attachments,
          ),
      };
    }

    return Container(
      color: const Color(0xFFF8FAFC),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          if (compact) {
            return Column(
              children: [
                _buildChatInfoSectionBar(
                  theme,
                  mediaCount: mediaCount,
                  fileCount: fileCount,
                ),
                Expanded(child: contentForSection()),
              ],
            );
          }

          return Row(
            children: [
              SizedBox(
                width: 238,
                child: _buildChatInfoRail(
                  theme,
                  title: title,
                  subtitle: subtitle,
                  messageCount: messages.length,
                  mediaCount: mediaCount,
                  fileCount: fileCount,
                ),
              ),
              VerticalDivider(width: 1, color: Colors.grey[200]),
              Expanded(child: contentForSection()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChatInfoRail(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required int messageCount,
    required int mediaCount,
    required int fileCount,
  }) {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 14, 18),
            child: Column(
              children: [
                _buildChatInfoAvatar(size: 58),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                _buildChatInfoNavItem(
                  section: _ChatInfoSection.info,
                  icon: Icons.info_outline,
                  label: 'Info',
                  badge: '$messageCount',
                ),
                _buildChatInfoNavItem(
                  section: _ChatInfoSection.media,
                  icon: Icons.perm_media_outlined,
                  label: 'Multimedia y docs',
                  badge: '${mediaCount + fileCount}',
                ),
                _buildChatInfoNavItem(
                  section: _ChatInfoSection.workflow,
                  icon: Icons.tune_outlined,
                  label: 'Gestión',
                ),
                _buildChatInfoNavItem(
                  section: _ChatInfoSection.backup,
                  icon: Icons.verified_user_outlined,
                  label: 'Respaldo',
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: _toggleChatInfoPanel,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Volver al chat'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInfoSectionBar(
    ThemeData theme, {
    required int mediaCount,
    required int fileCount,
  }) {
    final items = [
      (_ChatInfoSection.info, Icons.info_outline, 'Info', null),
      (
        _ChatInfoSection.media,
        Icons.perm_media_outlined,
        'Archivos',
        '${mediaCount + fileCount}'
      ),
      (_ChatInfoSection.workflow, Icons.tune_outlined, 'Gestión', null),
      (_ChatInfoSection.backup, Icons.verified_user_outlined, 'Respaldo', null),
    ];

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: Colors.white,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = _selectedChatInfoSection == item.$1;
          return ChoiceChip(
            selected: selected,
            avatar: Icon(
              item.$2,
              size: 16,
              color: selected ? _accentBlue : const Color(0xFF64748B),
            ),
            label: Text(
              item.$4 == null ? item.$3 : '${item.$3} ${item.$4}',
            ),
            onSelected: (_) {
              setState(() => _selectedChatInfoSection = item.$1);
            },
          );
        },
      ),
    );
  }

  Widget _buildChatInfoNavItem({
    required _ChatInfoSection section,
    required IconData icon,
    required String label,
    String? badge,
  }) {
    final selected = _selectedChatInfoSection == section;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? _accentBlue.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _selectedChatInfoSection = section),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected ? _accentBlue : const Color(0xFF64748B),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected ? _accentBlue : const Color(0xFF334155),
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: selected
                          ? _accentBlue.withValues(alpha: 0.12)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: selected ? _accentBlue : const Color(0xFF64748B),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatInfoAvatar({required double size}) {
    final conversation = widget.conversation;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: conversation.type == 'support'
            ? _accentBlue.withValues(alpha: 0.09)
            : const Color(0xFFF1F5F9),
        border: Border.all(
          color: conversation.isWhatsApp
              ? const Color(0xFF14B8A6).withValues(alpha: 0.42)
              : Colors.white,
          width: 1.5,
        ),
      ),
      child: Icon(
        conversation.isWhatsApp
            ? Icons.phone_in_talk_outlined
            : conversation.isWebsitePortal
                ? Icons.language_outlined
                : Icons.groups_outlined,
        color: conversation.type == 'support'
            ? _accentBlue
            : const Color(0xFF64748B),
        size: size * 0.42,
      ),
    );
  }

  Widget _buildChatInfoOverview({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required List<Message> messages,
    required List<_ChatAttachment> attachments,
  }) {
    final inboundCount = messages.where((message) => !message.isMe).length;
    final outboundCount = messages.where((message) => message.isMe).length;
    final lastMessageAt = messages.isEmpty ? null : messages.last.createdAt;

    return _buildChatInfoContentShell(
      theme: theme,
      title: 'Info',
      subtitle: title,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildChatMetric(
              theme,
              icon: Icons.forum_outlined,
              label: 'Mensajes',
              value: '${messages.length}',
            ),
            _buildChatMetric(
              theme,
              icon: Icons.call_received_outlined,
              label: 'Entrantes',
              value: '$inboundCount',
            ),
            _buildChatMetric(
              theme,
              icon: Icons.call_made_outlined,
              label: 'Salientes',
              value: '$outboundCount',
            ),
            _buildChatMetric(
              theme,
              icon: Icons.attach_file,
              label: 'Archivos',
              value: '${attachments.length}',
            ),
          ],
        ),
        const SizedBox(height: 18),
        _buildPanelBlock(
          theme: theme,
          children: [
            _buildInfoRowTile(
              icon: Icons.badge_outlined,
              title: 'Nombre',
              value: title,
            ),
            if (widget.conversation.isSupport) _buildContactPhoneInfoRow(),
            _buildInfoRowTile(
              icon: Icons.route_outlined,
              title: 'Canal',
              value: widget.conversation.channelLabel,
            ),
            _buildInfoRowTile(
              icon: Icons.flag_outlined,
              title: 'Estado',
              value: _statusLabel(widget.conversation.status),
            ),
            _buildInfoRowTile(
              icon: _contextIcon(widget.conversation.contextType),
              title: 'Contexto',
              value: _contextLabel(widget.conversation.contextType) ??
                  'Sin contexto',
            ),
            _buildInfoRowTile(
              icon: Icons.schedule_outlined,
              title: 'Último mensaje',
              value: lastMessageAt == null
                  ? 'Sin mensajes'
                  : _formatPanelDate(lastMessageAt),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _buildInfoActionButton(
              icon: Icons.attach_file,
              label: 'Adjuntar',
              onPressed: () => _pickAndSendFile('file'),
            ),
            _buildInfoActionButton(
              icon: Icons.link,
              label: 'Vincular',
              onPressed: () => _showAssignContextDialog(context),
            ),
            if (_canStartWhatsAppFromConversation)
              _buildInfoActionButton(
                icon: Icons.phone_in_talk_outlined,
                label: 'WhatsApp',
                onPressed: () => _openWhatsAppConversationForCurrentContext(
                  context,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }

  Widget _buildChatMediaSection({
    required ThemeData theme,
    required List<_ChatAttachment> attachments,
  }) {
    final media = attachments.where((item) => item.isImage).toList();
    final files = attachments.where((item) => !item.isImage).toList();

    return _buildChatInfoContentShell(
      theme: theme,
      title: 'Multimedia y documentos',
      subtitle: '${attachments.length} elementos guardados en el chat',
      trailing: FilledButton.icon(
        onPressed: () => _pickAndSendFile('file'),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Agregar'),
      ),
      children: [
        if (attachments.isEmpty)
          _buildPanelEmptyState(
            theme,
            icon: Icons.perm_media_outlined,
            title: 'Sin archivos todavía',
            message: 'Las imágenes y documentos enviados aparecerán aquí.',
          )
        else ...[
          if (media.isNotEmpty) ...[
            _buildPanelSectionTitle(theme, 'Multimedia'),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: media.length,
              itemBuilder: (context, index) => _buildMediaTile(media[index]),
            ),
            const SizedBox(height: 20),
          ],
          if (files.isNotEmpty) ...[
            _buildPanelSectionTitle(theme, 'Documentos'),
            const SizedBox(height: 10),
            _buildPanelBlock(
              theme: theme,
              children: [
                for (final file in files) _buildFileTile(theme, file),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildChatWorkflowSection(ThemeData theme) {
    final hasSupportedContextPanel =
        widget.conversation.hasSupportedContextPanel;
    final canResolve = widget.conversation.type == 'support' &&
        widget.conversation.status == 'active';

    return _buildChatInfoContentShell(
      theme: theme,
      title: 'Gestión',
      subtitle: 'Estado, vínculo ERP y acciones operativas',
      children: [
        _buildPanelBlock(
          theme: theme,
          children: [
            _buildManagementActionTile(
              icon: Icons.link,
              color: _accentBlue,
              title: widget.conversation.hasLinkedContext
                  ? 'Cambiar contexto'
                  : 'Vincular contexto',
              subtitle: _contextLabel(widget.conversation.contextType) ??
                  'Conecta este chat con cliente, trabajo, factura o pedido',
              onTap: () => _showAssignContextDialog(context),
            ),
            if (hasSupportedContextPanel && widget.onShowContextPanel != null)
              _buildManagementActionTile(
                icon: _contextIcon(widget.conversation.contextType),
                color: const Color(0xFF2563EB),
                title: 'Abrir detalles vinculados',
                subtitle: 'Revisa el panel operativo del contexto actual',
                onTap: widget.onShowContextPanel!,
              ),
            if (_canUseSmartActions)
              _buildManagementActionTile(
                icon: Icons.flash_on,
                color: const Color(0xFFD97706),
                title: 'Acciones rápidas',
                subtitle: widget.conversation.isWhatsApp
                    ? 'Aprobaciones, pagos, entregas y mensajes automáticos'
                    : 'Mensajes automáticos y preparación de atención',
                onTap: () => _showSmartActions(context),
              ),
            if (_canStartWhatsAppFromConversation)
              _buildManagementActionTile(
                icon: Icons.phone_in_talk_outlined,
                color: const Color(0xFF059669),
                title: 'Abrir WhatsApp',
                subtitle: 'Crea o recupera el hilo WhatsApp de este cliente',
                onTap: () => _openWhatsAppConversationForCurrentContext(
                  context,
                ),
              ),
            if (canResolve)
              _buildManagementActionTile(
                icon: Icons.check_circle_outline,
                color: const Color(0xFF0F766E),
                title: 'Marcar como resuelto',
                subtitle: 'Cierra la conversación en la bandeja de clientes',
                onTap: _resolveCurrentConversation,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildChatBackupSection({
    required ThemeData theme,
    required List<Message> messages,
    required List<_ChatAttachment> attachments,
  }) {
    return _buildChatInfoContentShell(
      theme: theme,
      title: 'Respaldo',
      subtitle: 'Exportación auditada de esta conversación',
      children: [
        _buildPanelBlock(
          theme: theme,
          children: [
            _buildInfoRowTile(
              icon: Icons.forum_outlined,
              title: 'Mensajes en este chat',
              value: '${messages.length}',
            ),
            _buildInfoRowTile(
              icon: Icons.attach_file,
              title: 'Archivos referenciados',
              value: '${attachments.length}',
            ),
            _buildInfoRowTile(
              icon: Icons.cloud_done_outlined,
              title: 'Respaldo general',
              value: 'Incluye chats y WhatsApp',
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed:
              _isExportingChatArchive ? null : _downloadCurrentChatArchive,
          icon: _isExportingChatArchive
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined),
          label: Text(
            _isExportingChatArchive
                ? 'Preparando respaldo'
                : 'Descargar respaldo del chat',
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'El archivo JSON conserva conversación, participantes, vínculos ERP, mensajes, metadatos externos, estados WhatsApp y referencias a archivos.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF64748B),
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildChatInfoContentShell({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required List<Widget> children,
    Widget? trailing,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing,
                ],
              ],
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildPanelBlock({
    required ThemeData theme,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const Divider(height: 1, color: Color(0xFFE2E8F0)),
            children[index],
          ],
        ],
      ),
    );
  }

  Widget _buildChatMetric(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _accentBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _accentBlue, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactPhoneInfoRow() {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getConversationContactFuture(),
      builder: (context, snapshot) {
        final rawPhone = snapshot.data?['phone']?.toString().trim();
        final hasPhone = rawPhone != null && rawPhone.isNotEmpty;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return _buildInfoRowTile(
          icon: Icons.phone_iphone_outlined,
          title: 'Teléfono',
          value: hasPhone
              ? _formatContactPhone(rawPhone)
              : isLoading
                  ? 'Buscando...'
                  : 'Sin teléfono registrado',
        );
      },
    );
  }

  Widget _buildInfoRowTile({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF64748B)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _buildManagementActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelSectionTitle(ThemeData theme, String title) {
    return Text(
      title.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: const Color(0xFF64748B),
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _buildPanelEmptyState(
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 42),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaTile(_ChatAttachment attachment) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showImagePreview(attachment.url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              attachment.url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFFE2E8F0),
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(7),
                color: Colors.black.withValues(alpha: 0.48),
                child: Text(
                  _formatPanelDate(attachment.message.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileTile(ThemeData theme, _ChatAttachment attachment) {
    return InkWell(
      onTap: () => _openAttachmentUrl(attachment.url, attachment.name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _accentBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getFileIcon(attachment.extension),
                color: _accentBlue,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${attachment.extension.toUpperCase()} · ${_formatPanelDate(attachment.message.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.open_in_new, size: 18, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  List<_ChatAttachment> _collectChatAttachments(List<Message> messages) {
    final attachments = <_ChatAttachment>[];
    for (final message in messages) {
      final attachment = _attachmentFromMessage(message);
      if (attachment != null) attachments.add(attachment);
    }
    return attachments;
  }

  _ChatAttachment? _attachmentFromMessage(Message message) {
    final url = _messageAttachmentUrl(message);
    if (url == null) return null;

    final metadata = message.metadata;
    final contentType = metadata['contentType']?.toString() ??
        metadata['content_type']?.toString() ??
        '';
    final extension = _messageAttachmentExtension(message, url, contentType);
    final isImage = message.type == 'image' ||
        contentType.toLowerCase().startsWith('image/') ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);
    final hasAttachmentMetadata = [
      'url',
      'media_url',
      'documentUrl',
      'document_url',
    ].any((key) => metadata.containsKey(key));

    if (message.type != 'image' &&
        message.type != 'file' &&
        !hasAttachmentMetadata) {
      return null;
    }

    return _ChatAttachment(
      message: message,
      url: url,
      name: _messageAttachmentName(message, extension),
      extension: extension,
      isImage: isImage,
    );
  }

  String? _messageAttachmentUrl(Message message) {
    for (final key in ['url', 'media_url', 'documentUrl', 'document_url']) {
      final value = message.metadata[key]?.toString().trim();
      if (value != null && value.startsWith('http')) return value;
    }

    final content = message.content.trim();
    if (content.startsWith('http')) return content;
    return null;
  }

  String _messageAttachmentName(Message message, String extension) {
    final metadata = message.metadata;
    for (final key in ['filename', 'documentFilename', 'document_filename']) {
      final value = metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }

    final label = message.type == 'image' ? 'Imagen' : 'Archivo';
    final date = DateFormat('yyyyMMdd_HHmm').format(message.createdAt);
    final suffix = extension.isEmpty ? '' : '.$extension';
    return '${label}_$date$suffix';
  }

  String _messageAttachmentExtension(
    Message message,
    String url,
    String contentType,
  ) {
    final metadata = message.metadata;
    final explicit = metadata['extension']?.toString().trim().toLowerCase();
    if (explicit != null && explicit.isNotEmpty) return explicit;

    if (contentType.contains('/')) {
      final fromType = contentType.split('/').last.split(';').first;
      if (fromType.isNotEmpty) return fromType.toLowerCase();
    }

    final path = Uri.tryParse(url)?.path ?? url;
    final fileName = path.split('/').last;
    if (fileName.contains('.')) {
      return fileName.split('.').last.toLowerCase();
    }

    return message.type == 'image' ? 'jpg' : 'file';
  }

  String _formatPanelDate(DateTime value) {
    return DateFormat('dd/MM/yyyy HH:mm').format(value);
  }

  String _formatContactPhone(String rawPhone) {
    final trimmed = rawPhone.trim();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.startsWith('56') && digits.length == 11) {
      final national = digits.substring(2);
      return '+56 ${national[0]} ${national.substring(1, 5)} ${national.substring(5)}';
    }

    if (digits.length == 9 && digits.startsWith('9')) {
      return '+56 ${digits[0]} ${digits.substring(1, 5)} ${digits.substring(5)}';
    }

    if (trimmed.startsWith('+')) return trimmed;
    if (digits.isNotEmpty) return '+$digits';
    return trimmed;
  }

  String _safeArchiveFilePart(String value) {
    final cleaned = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (cleaned.isEmpty) return 'chat';
    return cleaned.length > 48 ? cleaned.substring(0, 48) : cleaned;
  }

  void _showImagePreview(String url) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(
          children: [
            InteractiveViewer(child: Image.network(url)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () {
                  Navigator.of(dialogContext).maybePop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachmentUrl(String urlValue, String name) async {
    final url = Uri.tryParse(urlValue);
    if (url == null || !await canLaunchUrl(url)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir: $name')),
      );
      return;
    }

    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _downloadCurrentChatArchive() async {
    if (_isExportingChatArchive) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final chatTitle =
        context.read<ChatProvider>().getChatTitle(widget.conversation);

    setState(() => _isExportingChatArchive = true);
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Preparando respaldo del chat...')),
    );

    try {
      final snapshot = await _messagingService.getConversationArchiveSnapshot(
        widget.conversation.id,
      );
      final jsonString = const JsonEncoder.withIndent('  ').convert(snapshot);
      final fileName =
          'chat_${_safeArchiveFilePart(chatTitle)}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';

      await downloadFile(
        bytes: utf8.encode(jsonString),
        fileName: fileName,
        mimeType: 'application/json',
      );

      if (!mounted) return;
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Respaldo descargado: $fileName'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo descargar el respaldo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isExportingChatArchive = false);
    }
  }

  Future<void> _resolveCurrentConversation() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await _messagingService.resolveChat(widget.conversation.id);
      if (!mounted) return;
      await context.read<ChatProvider>().loadConversations();
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Conversación marcada como resuelta'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar la conversación: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildUnreadMessagesMarker(int count) {
    final label =
        count == 1 ? '1 mensaje sin leer' : '$count mensajes sin leer';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: Colors.grey.shade300,
              thickness: 1,
              endIndent: 10,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.58),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: Colors.grey.shade300,
              thickness: 1,
              indent: 10,
            ),
          ),
        ],
      ),
    );
  }

  String _buildConversationSubtitle(Conversation conversation) {
    final parts = <String>[conversation.channelLabel];

    final contextLabel = _contextLabel(conversation.contextType);
    if (contextLabel != null) parts.add(contextLabel);
    parts.add(_statusLabel(conversation.status));

    return parts.join(' · ');
  }

  String? _contextLabel(String? contextType) {
    return switch (contextType) {
      'order' => 'Pedido web',
      'job' => 'Servicio técnico',
      'invoice' => 'Factura',
      'bike' => 'Bicicleta',
      'product' => 'Producto',
      'customer' => 'Cliente',
      _ => null,
    };
  }

  IconData _contextIcon(String? contextType) {
    return switch (contextType) {
      'order' => Icons.shopping_cart_outlined,
      'job' => Icons.build_outlined,
      'invoice' => Icons.receipt_long_outlined,
      _ => Icons.article_outlined,
    };
  }

  String _statusLabel(String status) {
    return switch (status) {
      'pending' => 'Pendiente',
      'active' => 'Activa',
      'resolved' => 'Resuelta',
      'rejected' => 'Rechazada',
      _ => status,
    };
  }

  Widget _buildPreparedHandoffBanner(ConversationDraft draft) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border(
          bottom: BorderSide(color: Colors.blueGrey[100]!),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.assignment_outlined, color: Color(0xFF093357)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  draft.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF093357),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  draft.subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey[700]),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey[100]!),
                  ),
                  child: Text(
                    draft.body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () {
              if (_messageController.text.trim().isEmpty) {
                _messageController.value = TextEditingValue(
                  text: draft.body,
                  selection: TextSelection.collapsed(offset: draft.body.length),
                );
              }
              _restoreComposerFocus();
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Editar'),
          ),
          IconButton(
            tooltip: 'Descartar borrador',
            onPressed: () {
              context
                  .read<ChatProvider>()
                  .clearConversationDraft(widget.conversation.id);
            },
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }

  /// Show dialog to link this conversation to a Job or Invoice
  void _showAssignContextDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AssignContextDialog(
        conversationId: widget.conversation.id,
        currentContextType: widget.conversation.contextType,
        currentContextId: widget.conversation.contextId,
      ),
    );
  }

  Future<void> _openWhatsAppConversationForCurrentContext(
    BuildContext context,
  ) async {
    if (!_canStartWhatsAppFromConversation || _isSendingMessage) return;

    final provider = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSendingMessage = true);

    try {
      final contact = await _resolvePotentialWhatsAppContact();
      final phone = contact?['phone']?.toString();

      if (phone == null || phone.isEmpty) {
        throw Exception(
          'Este chat web no tiene un teléfono asociado para WhatsApp.',
        );
      }

      final conversationId =
          await _messagingService.openWhatsAppSupportConversation(
        phoneNumber: phone,
        contactName: contact?['name']?.toString() ??
            widget.conversation.creatorName ??
            widget.conversation.title ??
            'Cliente',
        customerId: contact?['customer_id']?.toString(),
        contextType: widget.conversation.contextType,
        contextId: widget.conversation.contextId,
      );

      if (!mounted) return;

      await provider.loadConversations();
      provider.setActiveConversation(conversationId);

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Conversación de WhatsApp abierta aparte.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir WhatsApp: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingMessage = false);
    }
  }

  void _showSmartActions(BuildContext context) {
    if (!_canUseSmartActions) {
      _showErrorSnackBar(
        context,
        'Las acciones rápidas solo están disponibles en conversaciones de clientes.',
      );
      return;
    }

    _toggleComposerMenu(
      name: 'smart_actions',
      anchorKey: _smartActionsButtonKey,
      width: 460,
      estimatedHeight: _isWhatsAppConversation ? 560 : 400,
      panelBuilder: (overlayContext) => _buildSmartActionsPanel(
        overlayContext,
        parentContext: context,
      ),
    );
  }

  Widget _buildSmartActionsPanel(
    BuildContext overlayContext, {
    required BuildContext parentContext,
  }) {
    final theme = Theme.of(overlayContext);
    final showingAutomaticMessages = _showAutomaticMessagesPanel;
    final panelHeight = _isWhatsAppConversation ? 560.0 : 400.0;
    final headerColor =
        showingAutomaticMessages ? const Color(0xFF2DD4BF) : Colors.amber;
    final headerIcon =
        showingAutomaticMessages ? Icons.quickreply_outlined : Icons.flash_on;
    final headerTitle = showingAutomaticMessages
        ? 'Mensajes automáticos'
        : 'Centro de acciones';
    final headerSubtitle = showingAutomaticMessages
        ? 'Textos listos usando datos del ERP'
        : _isWhatsAppConversation
            ? 'Solicitudes interactivas y mensajes preparados'
            : 'Mensajes preparados para este chat de cliente';

    return Material(
      color: Colors.transparent,
      child: Container(
        height: panelHeight,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: const BoxDecoration(
                color: Color(0xFF0F172A),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: headerColor.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: headerColor.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Icon(
                      headerIcon,
                      color: headerColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          headerSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.68),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showingAutomaticMessages)
                    IconButton(
                      tooltip: 'Volver',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.arrow_back,
                        size: 18,
                        color: Colors.white,
                      ),
                      onPressed: () {
                        setState(() => _showAutomaticMessagesPanel = false);
                        _composerMenuOverlayEntry?.markNeedsBuild();
                      },
                    ),
                  IconButton(
                    tooltip: 'Cerrar',
                    visualDensity: VisualDensity.compact,
                    icon:
                        const Icon(Icons.close, size: 18, color: Colors.white),
                    onPressed: () => _removeComposerMenuOverlay(
                      restoreComposerFocus: true,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showingAutomaticMessages)
                        _buildAutomaticMessagesPanelBody(theme)
                      else ...[
                        _buildPopoverSectionHeader(
                          'Colaboración',
                          'Enlaces rápidos para trabajar con el equipo',
                        ),
                        const SizedBox(height: 8),
                        _buildCommandActionTile(
                          icon: Icons.ios_share_outlined,
                          color: const Color(0xFF2563EB),
                          title: 'Enviar página actual',
                          subtitle: 'Comparte este módulo en la conversación',
                          badge: 'ERP',
                          onTap: () {
                            _removeComposerMenuOverlay(notify: true);
                            unawaited(_shareCurrentPageInChat());
                          },
                        ),
                        const SizedBox(height: 12),
                        if (_isWhatsAppConversation) ...[
                          _buildPopoverSectionHeader(
                            'Solicitudes al cliente',
                            'Acciones con respuesta o pago desde WhatsApp',
                          ),
                          const SizedBox(height: 8),
                          _buildCommandActionTile(
                            icon: Icons.assignment_turned_in_outlined,
                            color: const Color(0xFFD97706),
                            title: 'Aprobación de presupuesto',
                            subtitle:
                                'Solicita aprobar o rechazar el presupuesto activo',
                            badge: 'INTERACTIVO',
                            onTap: () {
                              _removeComposerMenuOverlay(notify: true);
                              _sendActionRequest(
                                  parentContext, 'approve_quote');
                            },
                          ),
                          _buildCommandActionTile(
                            icon: Icons.payments_outlined,
                            color: const Color(0xFF059669),
                            title: 'Solicitud de pago',
                            subtitle:
                                'Envía el botón de pago para la factura asociada',
                            badge: 'COBRO',
                            onTap: () {
                              _removeComposerMenuOverlay(notify: true);
                              _sendActionRequest(parentContext, 'pay_now');
                            },
                          ),
                          _buildCommandActionTile(
                            icon: Icons.inventory_2_outlined,
                            color: const Color(0xFF2563EB),
                            title: 'Confirmación de entrega',
                            subtitle:
                                'El cliente confirma recepción del producto o servicio',
                            badge: 'ENTREGA',
                            onTap: () {
                              _removeComposerMenuOverlay(notify: true);
                              _sendActionRequest(
                                parentContext,
                                'confirm_delivery',
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                        ] else ...[
                          _buildWhatsAppOnlyActionsNotice(theme),
                          const SizedBox(height: 12),
                        ],
                        _buildAutomaticMessagesSection(theme),
                        if (_isWhatsAppConversation) ...[
                          const SizedBox(height: 10),
                          _buildCommandActionTile(
                            icon: Icons.history_toggle_off_outlined,
                            color: const Color(0xFF64748B),
                            title: 'Enviar presupuesto antiguo',
                            subtitle:
                                'Compatibilidad: actualiza estado y notifica',
                            badge: 'LEGACY',
                            compact: true,
                            onTap: () {
                              _removeComposerMenuOverlay(notify: true);
                              _handleSendQuote(parentContext);
                            },
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhatsAppOnlyActionsNotice(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF64748B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.lock_outline,
              color: Color(0xFF64748B),
              size: 18,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Solicitudes interactivas solo por WhatsApp',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF111827),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Este chat es ${widget.conversation.channelLabel.toLowerCase()}. Los mensajes automáticos sí pueden enviarse desde aquí.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopoverSectionHeader(String title, String subtitle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommandActionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? badge,
    bool compact = false,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 0 : 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: compact ? 9 : 10,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                Container(
                  width: compact ? 32 : 36,
                  height: compact ? 32 : 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withValues(alpha: 0.18)),
                  ),
                  child: Icon(icon, color: color, size: compact ? 18 : 20),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF111827),
                              ),
                            ),
                          ),
                          if (badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badge,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAutomaticMessagesSection(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() => _showAutomaticMessagesPanel = true);
          _composerMenuOverlayEntry?.markNeedsBuild();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFF0F766E).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.quickreply_outlined,
                  color: Color(0xFF0F766E),
                  size: 19,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mensajes automáticos',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Textos listos usando datos del ERP',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAutomaticMessagesPanelBody(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAutomaticMessageTile(
            icon: Icons.account_balance_outlined,
            title: 'Datos de transferencia',
            subtitle: 'Envía banco, cuenta, titular, RUT e instrucciones',
            onTap: _sendTransferDataMessage,
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          _buildAutomaticMessageTile(
            icon: Icons.rate_review_outlined,
            title: 'Pedir reseña en Google',
            subtitle: 'Solicita una reseña con enlace a Google Maps',
            onTap: _sendGoogleMapsReviewRequestMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildAutomaticMessageTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF093357).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: const Color(0xFF093357), size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.send_outlined, size: 17, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  Future<void> _sendTransferDataMessage() async {
    _removeComposerMenuOverlay(notify: true);

    try {
      final message = await _buildTransferDataMessage();
      if (message == null || message.trim().isEmpty) {
        if (mounted) {
          _showErrorSnackBar(
            context,
            'No hay datos de transferencia configurados en Sitio Web.',
          );
        }
        return;
      }

      await _sendPreparedMessage(message);
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(
        context,
        'No se pudieron preparar los datos de transferencia: $e',
      );
    }
  }

  Future<String?> _buildTransferDataMessage() async {
    final websiteService = context.read<WebsiteService>();
    await websiteService.loadSettings();

    final bankName =
        websiteService.getSetting('payment_transfer_bank_name', '').trim();
    final accountType =
        websiteService.getSetting('payment_transfer_account_type', '').trim();
    final accountNumber =
        websiteService.getSetting('payment_transfer_account_number', '').trim();
    final accountHolder =
        websiteService.getSetting('payment_transfer_account_holder', '').trim();
    final rut = websiteService.getSetting('payment_transfer_rut', '').trim();
    final contactEmail = websiteService
        .getSetting(
          'payment_transfer_contact_email',
          websiteService.getSetting('contact_email', ''),
        )
        .trim();
    final instructions =
        websiteService.getSetting('payment_transfer_instructions', '').trim();

    final hasTransferDestination = [
      bankName,
      accountNumber,
      accountHolder,
      rut,
    ].any((value) => value.isNotEmpty);

    if (!hasTransferDestination &&
        contactEmail.isEmpty &&
        instructions.isEmpty) {
      return null;
    }

    final lines = <String>[
      'Hola, te compartimos los datos para transferencia bancaria:',
      '',
      if (bankName.isNotEmpty) 'Banco: $bankName',
      if (accountType.isNotEmpty) 'Tipo de cuenta: $accountType',
      if (accountNumber.isNotEmpty) 'N° de cuenta: $accountNumber',
      if (accountHolder.isNotEmpty) 'Titular: $accountHolder',
      if (rut.isNotEmpty) 'RUT: $rut',
      if (contactEmail.isNotEmpty) 'Comprobante: $contactEmail',
    ];

    final proofInstructions = instructions.isNotEmpty
        ? instructions
        : contactEmail.isNotEmpty
            ? 'Una vez realizada la transferencia, envíanos el comprobante a $contactEmail.'
            : '';

    if (proofInstructions.isNotEmpty) {
      lines.addAll(['', proofInstructions]);
    }

    return lines.join('\n');
  }

  Future<void> _sendGoogleMapsReviewRequestMessage() async {
    _removeComposerMenuOverlay(notify: true);

    try {
      final message = await _buildGoogleMapsReviewRequestMessage();
      await _sendPreparedMessage(message);
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(
        context,
        'No se pudo preparar la solicitud de reseña: $e',
      );
    }
  }

  Future<String> _buildGoogleMapsReviewRequestMessage() async {
    final websiteService = context.read<WebsiteService>();
    await websiteService.loadSettings();

    final businessName = websiteService
        .getSetting(
          'store_name',
          websiteService.getSetting(
            'business_name',
            websiteService.getSetting('company_name', 'Viñabike'),
          ),
        )
        .trim();
    final displayName = businessName.isEmpty ? 'Viñabike' : businessName;

    return [
      'Hola, gracias por confiar en $displayName.',
      '',
      'Si quedaste conforme con la atención, nos ayudaría muchísimo que nos dejes una reseña en Google Maps:',
      '',
      _googleMapsReviewUrl,
      '',
      'Tu opinión ayuda a que más ciclistas nos encuentren y también nos ayuda a seguir mejorando. ¡Gracias!',
      '',
      'Si hubo algo pendiente, escríbenos por aquí y lo revisamos contigo.',
    ].join('\n');
  }

  Future<void> _sendPreparedMessage(
    String message, {
    Map<String, dynamic>? metadata,
  }) async {
    if (_isSendingMessage) {
      _showErrorSnackBar(
        context,
        'Espera a que termine el envío anterior antes de mandar otro mensaje.',
      );
      return;
    }

    final previousValue = _messageController.value;
    _messageController.value = TextEditingValue(
      text: message,
      selection: TextSelection.collapsed(offset: message.length),
    );

    await _sendMessage(metadata: metadata);

    if (!mounted) return;
    if (previousValue.text.trim().isNotEmpty &&
        _messageController.text.trim().isEmpty) {
      _messageController.value = previousValue;
      if (previousValue.selection.isValid) {
        _lastComposerSelection = previousValue.selection;
      }
    }
  }

  Future<void> _shareCurrentPageInChat() async {
    _removeOverlay();
    _removeEmojiOverlay();
    _removeComposerMenuOverlay(notify: false);

    final link = _buildCurrentWorkspaceLink();
    if (link == null) {
      _showErrorSnackBar(
        context,
        'Esta página todavía no se puede compartir.',
      );
      return;
    }

    await _sendPreparedMessage(
      link.shareText,
      metadata: _routeShareMetadata(link),
    );
  }

  SharedRouteLink? _buildCurrentWorkspaceLink() {
    final workspace = context.read<WorkspaceManager>().activeWorkspace;
    if (workspace == null) return null;

    return RouteShareService.buildForRoute(
      route: workspace.currentRoute,
      title: workspace.title,
    );
  }

  Map<String, dynamic> _routeShareMetadata(SharedRouteLink link) {
    return {
      'share_kind': 'route',
      'route': link.route,
      'title': link.title,
      'deep_link': link.uri.toString(),
      if (link.webUri != null) 'web_link': link.webUri.toString(),
    };
  }

  /// Send an action request message to the customer
  Future<void> _sendActionRequest(
      BuildContext context, String actionType) async {
    if (!_isWhatsAppConversation) {
      _showErrorSnackBar(
        context,
        'Esta acción requiere una conversación de WhatsApp.',
      );
      return;
    }

    final conversation = widget.conversation;
    final contextType = conversation.contextType;
    final contextId = conversation.contextId;

    // Validate context
    if (contextId == null) {
      _showErrorSnackBar(
          context, 'No hay contexto asociado a este chat (Job/Invoice).');
      return;
    }

    String? invoiceId;
    String? jobId;
    double? amount;
    String? actionTargetId;
    String? actionKind;

    if (contextType == 'job') {
      jobId = contextId;
      try {
        final bikeshopService = context.read<BikeshopService>();
        final job = await bikeshopService.getJobById(contextId);
        if (job?.invoiceId != null) {
          invoiceId = job?.invoiceId;
        }
      } catch (e) {
        _showErrorSnackBar(context, 'Error al obtener datos del trabajo.');
        return;
      }
    } else if (contextType == 'invoice') {
      invoiceId = contextId;
    }

    // Get invoice amount for payment requests
    if (invoiceId != null && actionType == 'pay_now') {
      try {
        final salesService = context.read<SalesService>();
        final invoice = await salesService.fetchInvoice(invoiceId);
        amount = invoice?.balance ?? invoice?.total ?? 0;
      } catch (e) {
        debugPrint('Error fetching invoice: $e');
      }
    }

    if (actionType == 'approve_quote' && jobId == null) {
      if (invoiceId == null) {
        _showErrorSnackBar(
          context,
          'No se encontró una factura asociada para solicitar la aprobación.',
        );
        return;
      }
    }

    if (actionType == 'confirm_delivery' && jobId == null) {
      _showErrorSnackBar(
        context,
        'La confirmación de entrega por WhatsApp requiere un trabajo asociado.',
      );
      return;
    }

    if (actionType == 'pay_now' && invoiceId == null) {
      _showErrorSnackBar(
        context,
        'No se encontró una factura asociada para solicitar el pago.',
      );
      return;
    }

    // Build message content
    String content;
    switch (actionType) {
      case 'approve_quote':
        content = 'Por favor revisa y aprueba el presupuesto adjunto.';
        actionTargetId = invoiceId;
        actionKind = 'invoice';
        break;
      case 'pay_now':
        content = amount != null
            ? 'Tienes un saldo pendiente de \$${amount.toStringAsFixed(0)}. Por favor procede con el pago.'
            : 'Por favor procede con el pago.';
        actionTargetId = invoiceId;
        actionKind = 'invoice';
        break;
      case 'confirm_delivery':
        content = 'Tu pedido ha sido enviado. Por favor confirma la recepción.';
        actionTargetId = jobId;
        actionKind = 'job';
        break;
      default:
        content = 'Acción requerida.';
    }

    if (actionTargetId == null || actionKind == null) {
      _showErrorSnackBar(
        context,
        'No se pudo determinar el destino de la acción de WhatsApp.',
      );
      return;
    }

    try {
      final whatsappService = WhatsAppService();

      // For approve_quote, update invoice status to 'sent' first
      if (actionType == 'approve_quote' && invoiceId != null) {
        try {
          final salesService = context.read<SalesService>();
          await salesService.updateInvoiceStatus(invoiceId, InvoiceStatus.sent);
        } catch (e) {
          debugPrint('Error updating invoice status: $e');
        }
      }

      final success = await _sendWhatsAppInteractiveRequest(
        context: context,
        actionType: actionType,
        actionKind: actionKind,
        actionTargetId: actionTargetId,
        message: content,
        contextType: contextType,
        contextId: contextId,
        jobId: jobId,
        amount: amount,
        metadata: {
          'action_type': actionType,
          'target_id': actionTargetId,
          'invoiceId': invoiceId,
          if (jobId != null) 'jobId': jobId,
        },
      );

      if (!success || !mounted) {
        return;
      }

      if (mounted) {
        _showWhatsAppResultSnackbar(
          context: context,
          deliveryMethod: whatsappService.lastDeliveryMethod,
          successMessage: actionType == 'approve_quote'
              ? 'Presupuesto enviado por WhatsApp Cloud API'
              : 'Solicitud enviada por WhatsApp Cloud API',
          fallbackMessage: actionType == 'approve_quote'
              ? 'WhatsApp abierto con el presupuesto prellenado'
              : 'WhatsApp abierto con la solicitud prellenada',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleSendQuote(BuildContext context) async {
    if (!_isWhatsAppConversation) {
      _showErrorSnackBar(
        context,
        'El envío de presupuesto por WhatsApp requiere una conversación de WhatsApp.',
      );
      return;
    }

    final conversation = widget.conversation;
    // Check context
    final contextType = conversation.contextType;
    final contextId = conversation.contextId;

    if (contextId == null) {
      _showErrorSnackBar(
          context, 'No hay contexto asociado a este chat (Job/Invoice).');
      return;
    }

    String? jobId;
    String? invoiceId;

    if (contextType == 'job') {
      jobId = contextId;
      try {
        final bikeshopService = context.read<BikeshopService>();
        final job = await bikeshopService.getJobById(jobId);
        invoiceId = job?.invoiceId;
      } catch (e) {
        _showErrorSnackBar(context, 'Error al obtener datos del trabajo.');
        return;
      }
    } else if (contextType == 'invoice') {
      invoiceId = contextId;
    } else {
      _showErrorSnackBar(
        context,
        'El envío de presupuesto por WhatsApp requiere una factura o trabajo asociado.',
      );
      return;
    }

    if (invoiceId == null) {
      _showErrorSnackBar(
        context,
        'No se encontró una factura asociada para enviar el presupuesto.',
      );
      return;
    }

    // Confirm Action
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Enviar Presupuesto?'),
        content: const Text(
            'Esto cambiará el estado de la factura a "Enviado" y enviará una tarjeta de confirmación al cliente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // 1. Update Invoice Status
      await context
          .read<SalesService>()
          .updateInvoiceStatus(invoiceId, InvoiceStatus.sent);

      // 2. Generate and Upload PDF
      String? documentUrl;
      String? documentFilename;
      try {
        final salesService = context.read<SalesService>();
        final invoiceToPrint = await salesService.fetchInvoice(
          invoiceId,
          refresh: true,
        );
        if (invoiceToPrint != null) {
          final resolvedBikeNames = await InvoicePdfGenerator.resolveBikeNames(
              context, invoiceToPrint);
          final pdfDoc = await InvoicePdfGenerator.generateInvoicePDF(
              context, invoiceToPrint, resolvedBikeNames);
          final pdfBytes = await pdfDoc.save();

          final db = context.read<DatabaseService>();
          final filename =
              'presupuestos/presupuesto_${invoiceToPrint.invoiceNumber}_${DateTime.now().millisecondsSinceEpoch}.pdf';

          await db.supabase.storage.from('vinabike-assets').uploadBinary(
                filename,
                pdfBytes,
                fileOptions: const FileOptions(
                    contentType: 'application/pdf', upsert: true),
              );

          documentUrl = db.supabase.storage
              .from('vinabike-assets')
              .getPublicUrl(filename);
          documentFilename = 'Presupuesto_${invoiceToPrint.invoiceNumber}.pdf';
        }
      } catch (e) {
        debugPrint('Error generating/uploading PDF for quote: $e');
      }

      final whatsappService = WhatsAppService();
      final success = await _sendWhatsAppInteractiveRequest(
        context: context,
        actionType: 'approve_quote',
        actionKind: 'invoice',
        actionTargetId: invoiceId,
        message:
            '📋 Presupuesto enviado\nPor favor revisa y confirma los detalles para proceder.',
        contextType: contextType,
        contextId: contextId,
        jobId: jobId,
        markQuoteSent: true,
        documentUrl: documentUrl,
        documentFilename: documentFilename,
        metadata: {
          'action_type': 'approve_quote',
          'target_id': invoiceId,
          'invoiceId': invoiceId,
          if (jobId != null) 'jobId': jobId,
        },
      );

      if (!success || !mounted) {
        return;
      }

      if (mounted) {
        _showWhatsAppResultSnackbar(
          context: context,
          deliveryMethod: whatsappService.lastDeliveryMethod,
          successMessage: 'Presupuesto enviado por WhatsApp Cloud API',
          fallbackMessage: 'WhatsApp abierto con el presupuesto prellenado',
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(context, 'Error al enviar presupuesto: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> _getSenderInfo(String senderId) {
    return _senderInfoFutureCache.putIfAbsent(
      senderId,
      () => _messagingService.getSenderInfo(senderId),
    );
  }

  Future<Map<String, dynamic>?> _resolveConversationWhatsAppContact() {
    if (!_isWhatsAppConversation) {
      return Future.value(null);
    }

    return _messagingService.getSupportConversationContact(
      widget.conversation.id,
    );
  }

  Future<Map<String, dynamic>?> _resolvePotentialWhatsAppContact() {
    return _messagingService.getSupportConversationContact(
      widget.conversation.id,
    );
  }

  String _resolveIncomingSenderName(
    Message msg,
    Map<String, dynamic>? senderInfo,
  ) {
    final senderName = senderInfo?['name']?.toString().trim();
    if (senderName != null && senderName.isNotEmpty) {
      return senderName;
    }

    final metadataName = msg.metadata['contact_name']?.toString().trim();
    if (metadataName != null && metadataName.isNotEmpty) {
      return metadataName;
    }

    final creatorName = widget.conversation.creatorName?.trim();
    if (creatorName != null && creatorName.isNotEmpty) {
      return creatorName;
    }

    return 'Cliente';
  }

  DateTime? _parseLastInboundAt(Map<String, dynamic>? contact) {
    final rawValue = contact?['last_inbound_at'];
    if (rawValue is DateTime) {
      return rawValue;
    }

    return DateTime.tryParse(rawValue?.toString() ?? '');
  }

  DateTime? _resolveLastInboundAt(
    Map<String, dynamic>? contact,
    List<Message> messages,
  ) {
    final bindingInboundAt = _parseLastInboundAt(contact);
    DateTime? latestCustomerMessageAt;

    for (final message in messages) {
      final direction = message.metadata['message_direction']?.toString();
      final provider = message.metadata['external_provider']?.toString();
      final isInbound = direction == 'inbound' ||
          (provider == 'whatsapp' &&
              direction != 'outbound' &&
              !message.isMe) ||
          (message.senderId == null &&
              message.type != 'system' &&
              message.content.trim().isNotEmpty);
      if (!isInbound) continue;

      if (latestCustomerMessageAt == null ||
          message.createdAt.toUtc().isAfter(latestCustomerMessageAt.toUtc())) {
        latestCustomerMessageAt = message.createdAt;
      }
    }

    if (bindingInboundAt == null) return latestCustomerMessageAt;
    if (latestCustomerMessageAt == null) return bindingInboundAt;

    return latestCustomerMessageAt.toUtc().isAfter(bindingInboundAt.toUtc())
        ? latestCustomerMessageAt
        : bindingInboundAt;
  }

  Future<bool> _sendWhatsAppInteractiveRequest({
    required BuildContext context,
    required String actionType,
    required String actionKind,
    required String actionTargetId,
    required String message,
    String? customerId,
    String? contextType,
    String? contextId,
    String? jobId,
    double? amount,
    bool markQuoteSent = false,
    Map<String, dynamic>? metadata,
    String? documentUrl,
    String? documentFilename,
  }) async {
    if (!_isWhatsAppConversation) {
      throw Exception(
        'Esta conversación no está vinculada a WhatsApp.',
      );
    }

    final contact = await _resolveConversationWhatsAppContact();
    final phone = contact?['phone']?.toString();

    if (phone == null || phone.isEmpty) {
      throw Exception(
        'La conversación no tiene un contacto con teléfono para WhatsApp',
      );
    }

    final customerName = contact?['name']?.toString();
    final whatsappService = WhatsAppService();

    return whatsappService.sendInteractiveAction(
      context: context,
      customerPhone: phone,
      customerName: customerName == null || customerName.isEmpty
          ? 'Cliente'
          : customerName,
      conversationId: widget.conversation.id,
      customerId: customerId ?? contact?['customer_id']?.toString(),
      contextType: contextType,
      contextId: contextId,
      jobId: jobId,
      actionType: actionType,
      actionKind: actionKind,
      actionTargetId: actionTargetId,
      message: message,
      amount: amount,
      markQuoteSent: markQuoteSent,
      metadata: metadata,
      documentUrl: documentUrl,
      documentFilename: documentFilename,
    );
  }

  bool _isWhatsAppServiceWindowOpen(DateTime? lastInboundAt) {
    if (lastInboundAt == null) return false;
    return DateTime.now().toUtc().difference(lastInboundAt.toUtc()) <
        const Duration(hours: 24);
  }

  Duration _whatsAppWindowRemaining(DateTime? lastInboundAt) {
    if (lastInboundAt == null) return Duration.zero;
    final elapsed = DateTime.now().toUtc().difference(lastInboundAt.toUtc());
    final remaining = const Duration(hours: 24) - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Widget _buildWhatsAppServiceWindowGauge(BuildContext context) {
    final messages = context.watch<ChatProvider>().activeMessages;

    return FutureBuilder<Map<String, dynamic>?>(
      future: _getWhatsAppContactFuture(),
      builder: (context, snapshot) {
        final contact = snapshot.data;
        final lastInboundAt = _resolveLastInboundAt(contact, messages);
        final remaining = _whatsAppWindowRemaining(lastInboundAt);
        final isOpen = remaining > Duration.zero;
        final progress =
            (remaining.inSeconds / const Duration(hours: 24).inSeconds)
                .clamp(0.0, 1.0)
                .toDouble();
        final label = lastInboundAt == null
            ? 'WhatsApp: ventana cerrada'
            : isOpen
                ? 'WhatsApp: ${_formatWindowDuration(remaining)} disponibles'
                : 'WhatsApp: requiere plantilla';
        final color = isOpen ? const Color(0xFF16A34A) : Colors.amber[800]!;

        return Tooltip(
          message: lastInboundAt == null
              ? 'El cliente no ha respondido en esta conversación. Para escribir por Cloud API necesitas una plantilla aprobada.'
              : isOpen
                  ? 'La ventana de 24 horas empezó con la última respuesta del cliente.'
                  : 'La ventana de 24 horas expiró. El próximo envío debe ser una plantilla aprobada.',
          child: Row(
            children: [
              Icon(
                isOpen ? Icons.schedule_outlined : Icons.lock_clock_outlined,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: isOpen ? progress : 1,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatWindowDuration(Duration duration) {
    if (duration.inHours >= 1) {
      final minutes = duration.inMinutes.remainder(60);
      return minutes == 0
          ? '${duration.inHours}h'
          : '${duration.inHours}h ${minutes}m';
    }
    return '${duration.inMinutes.clamp(0, 59)}m';
  }

  void _showWhatsAppTemplatePicker({String? pendingText}) {
    _toggleComposerMenu(
      name: 'whatsapp_templates',
      anchorKey: _templateButtonKey,
      width: 420,
      estimatedHeight: 390,
      panelBuilder: (overlayContext) => _buildWhatsAppTemplatePanel(
        overlayContext,
        pendingText: pendingText?.trim(),
      ),
    );
  }

  Widget _buildWhatsAppTemplatePanel(
    BuildContext overlayContext, {
    String? pendingText,
  }) {
    final theme = Theme.of(overlayContext);
    const options = WhatsAppService.templateOptions;
    final hasPendingText = pendingText != null && pendingText.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
              child: Row(
                children: [
                  const Icon(Icons.dynamic_form_outlined, color: _accentBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Plantillas WhatsApp',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          hasPendingText
                              ? 'El texto escrito queda como borrador hasta que el cliente responda.'
                              : 'Elige la plantilla aprobada para esta ocasión.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => _removeComposerMenuOverlay(
                      restoreComposerFocus: true,
                    ),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ...options.map(
              (option) => InkWell(
                onTap: () => _sendSelectedWhatsAppTemplate(
                  option,
                  pendingText: pendingText,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _accentBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(option.icon, color: _accentBlue, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              option.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendSelectedWhatsAppTemplate(
    WhatsAppTemplateOption option, {
    String? pendingText,
  }) async {
    if (_isSendingMessage) return;

    _removeComposerMenuOverlay(notify: true);
    final chatProvider = context.read<ChatProvider>();
    final whatsappService = WhatsAppService();
    setState(() => _isSendingMessage = true);

    try {
      final contact = await _getWhatsAppContactFuture();
      final phone = contact?['phone']?.toString();
      final customerName = contact?['name']?.toString().trim();

      if (phone == null || phone.isEmpty) {
        throw Exception('La conversación no tiene teléfono asociado.');
      }

      final success = await whatsappService.sendTemplateMessage(
        option: option,
        customerPhone: phone,
        customerName: customerName == null || customerName.isEmpty
            ? 'cliente'
            : customerName,
        conversationId: widget.conversation.id,
        contextType: widget.conversation.contextType,
        contextId: widget.conversation.contextId,
      );

      if (!success) {
        throw Exception('Meta rechazó la plantilla seleccionada.');
      }

      final pending = pendingText?.trim();
      if (pending != null && pending.isNotEmpty) {
        chatProvider.setConversationDraft(
          widget.conversation.id,
          pending,
          title: 'Mensaje pendiente de ventana WhatsApp',
          subtitle:
              'Se envió "${option.label}". Cuando el cliente responda, puedes enviar este texto.',
        );
      }

      if (_messageController.text.trim() == pending) {
        _messageController.clear();
      }

      if (!mounted) return;
      _showWhatsAppResultSnackbar(
        context: context,
        deliveryMethod: whatsappService.lastDeliveryMethod,
        successMessage: 'Plantilla enviada: ${option.label}',
        fallbackMessage: 'WhatsApp abierto con la plantilla prellenada',
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(context, 'No se pudo enviar la plantilla: $e');
    } finally {
      if (mounted) setState(() => _isSendingMessage = false);
    }
  }

  Widget _buildComposer(BuildContext context) {
    return _buildTextComposer(
      context,
      showSmartActions: _canUseSmartActions,
    );
  }

  Widget _buildTextComposer(
    BuildContext context, {
    required bool showSmartActions,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isWhatsAppConversation) ...[
          _buildWhatsAppServiceWindowGauge(context),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            if (showSmartActions)
              KeyedSubtree(
                key: _smartActionsButtonKey,
                child: IconButton(
                  icon: const Icon(Icons.flash_on, color: Colors.amber),
                  tooltip: 'Acciones Rápidas',
                  onPressed: () => _showSmartActions(context),
                ),
              ),
            KeyedSubtree(
              key: _emojiButtonKey,
              child: IconButton(
                icon: Icon(
                  _isEmojiPickerOpen
                      ? Icons.keyboard_alt_outlined
                      : Icons.emoji_emotions_outlined,
                ),
                tooltip: _isEmojiPickerOpen ? 'Cerrar emojis' : 'Emojis',
                onPressed: _toggleEmojiPicker,
              ),
            ),
            KeyedSubtree(
              key: _attachmentButtonKey,
              child: IconButton(
                icon: const Icon(Icons.attach_file),
                tooltip: 'Adjuntar',
                onPressed: _showAttachmentOptions,
              ),
            ),
            if (_isWhatsAppConversation)
              KeyedSubtree(
                key: _templateButtonKey,
                child: IconButton(
                  icon: const Icon(Icons.dynamic_form_outlined),
                  tooltip: 'Plantillas WhatsApp',
                  onPressed: () => _showWhatsAppTemplatePicker(
                    pendingText: _messageController.text.trim(),
                  ),
                ),
              ),
            Expanded(
              child: CompositedTransformTarget(
                link: _layerLink,
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  decoration: const InputDecoration(
                    hintText: 'Escribe un mensaje... (# para ref)',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.blue),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEmojiOverlay(BuildContext overlayContext) {
    final overlayBox = Overlay.of(
      overlayContext,
    ).context.findRenderObject() as RenderBox?;
    final buttonBox =
        _emojiButtonKey.currentContext?.findRenderObject() as RenderBox?;

    final screenSize = MediaQuery.sizeOf(overlayContext);
    final panelWidth = screenSize.width < 430 ? screenSize.width - 24 : 390.0;
    final panelHeight = screenSize.height < 720 ? 350.0 : 430.0;
    final width = panelWidth.clamp(280.0, 390.0).toDouble();
    final height = panelHeight;

    final overlaySize = overlayBox?.size ?? screenSize;
    final buttonOffset = overlayBox != null && buttonBox != null
        ? overlayBox.globalToLocal(buttonBox.localToGlobal(Offset.zero))
        : Offset(12, overlaySize.height - height - 72);
    final buttonSize = buttonBox?.size ?? const Size(40, 40);
    final buttonRect = buttonOffset & buttonSize;
    final horizontalLimit =
        (overlaySize.width - width - 12).clamp(12.0, double.infinity);
    final left = buttonRect.left.clamp(12.0, horizontalLimit).toDouble();
    final preferredTop = buttonRect.top - height - 8;
    final fallbackTop = buttonRect.bottom + 8;
    final verticalLimit =
        (overlaySize.height - height - 12).clamp(12.0, double.infinity);
    final top = (preferredTop >= 12 ? preferredTop : fallbackTop)
        .clamp(12.0, verticalLimit)
        .toDouble();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => _hideEmojiPicker(restoreComposerFocus: true),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: _buildEmojiPickerPanel(
              overlayContext,
              width: width,
              height: height,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmojiPickerPanel(
    BuildContext panelContext, {
    required double width,
    required double height,
  }) {
    final theme = Theme.of(panelContext);
    final query = _emojiSearchController.text.trim();
    final sections = _emojiSectionsForPicker(query);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: TextField(
                controller: _emojiSearchController,
                focusNode: _emojiSearchFocusNode,
                onChanged: (_) => _refreshEmojiPicker(),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Buscar con texto o emoji',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Limpiar',
                          onPressed: () {
                            _emojiSearchController.clear();
                            _refreshEmojiPicker();
                          },
                        ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _buildEmojiModeTabs(theme),
            ),
            Expanded(
              child: sections.isEmpty
                  ? _buildEmojiEmptyState(theme)
                  : ListView.builder(
                      controller: _emojiScrollController,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                      itemCount: sections.length,
                      itemBuilder: (context, index) {
                        final section = sections[index];
                        return _buildEmojiSection(section, theme);
                      },
                    ),
            ),
            _buildEmojiCategoryBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiModeTabs(ThemeData theme) {
    Widget tab(String label, {required bool selected}) {
      return Expanded(
        child: Container(
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.grey.shade200 : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.black87 : Colors.grey.shade500,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          tab('Emojis', selected: true),
          tab('GIFs', selected: false),
          tab('Stickers', selected: false),
        ],
      ),
    );
  }

  Widget _buildEmojiSection(_EmojiSection section, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              section.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Wrap(
            spacing: 2,
            runSpacing: 2,
            children: section.emojis.map(_buildEmojiButton).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiButton(String emoji) {
    return SizedBox(
      width: 34,
      height: 34,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _insertEmoji(emoji),
          child: Center(
            child: Text(
              emoji,
              style: const TextStyle(fontSize: 22, height: 1),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiCategoryBar(ThemeData theme) {
    final items = <({IconData icon, String label})>[
      (icon: Icons.access_time, label: 'Recientes'),
      ..._emojiGroups.map((group) => (icon: group.icon, label: group.label)),
    ];

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: List.generate(items.length, (index) {
            final item = items[index];
            final selected = index == _selectedEmojiCategoryIndex &&
                _emojiSearchController.text.trim().isEmpty;
            return Tooltip(
              message: item.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  _emojiSearchController.clear();
                  _selectedEmojiCategoryIndex = index;
                  if (_emojiScrollController.hasClients) {
                    _emojiScrollController.jumpTo(0);
                  }
                  _refreshEmojiPicker();
                },
                child: Container(
                  width: 36,
                  height: 34,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: selected ? Colors.grey.shade200 : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item.icon,
                    size: 19,
                    color: selected ? _accentBlue : Colors.grey.shade600,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildEmojiEmptyState(ThemeData theme) {
    return Center(
      child: Text(
        'Sin resultados',
        style: TextStyle(
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  List<_EmojiSection> _emojiSectionsForPicker(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      return _emojiGroups
          .map((group) {
            final emojis = group.emojis
                .where((emoji) => _emojiMatchesQuery(emoji, group, query))
                .toList();
            return _EmojiSection(group.label, emojis);
          })
          .where((section) => section.emojis.isNotEmpty)
          .toList();
    }

    if (_selectedEmojiCategoryIndex == 0) {
      return [
        _EmojiSection('Recientes', _recentEmojiChoices),
        _EmojiSection('Smileys y personas', _emojiGroups.first.emojis),
      ];
    }

    final groupIndex = (_selectedEmojiCategoryIndex - 1)
        .clamp(0, _emojiGroups.length - 1)
        .toInt();
    final group = _emojiGroups[groupIndex];
    return [_EmojiSection(group.label, group.emojis)];
  }

  bool _emojiMatchesQuery(String emoji, _EmojiGroup group, String query) {
    if (emoji.contains(query)) return true;
    if (group.label.toLowerCase().contains(query)) return true;
    if (group.keywords.any((keyword) => keyword.contains(query))) return true;
    final alias = _emojiAliases[emoji]?.toLowerCase();
    return alias?.contains(query) ?? false;
  }

  void _showWhatsAppResultSnackbar({
    required BuildContext context,
    required WhatsAppDeliveryMethod deliveryMethod,
    required String successMessage,
    required String fallbackMessage,
  }) {
    final content = switch (deliveryMethod) {
      WhatsAppDeliveryMethod.cloudApi => successMessage,
      WhatsAppDeliveryMethod.manualFallback => fallbackMessage,
      WhatsAppDeliveryMethod.failed => successMessage,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(content),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Color _getNameColor(String name) {
    if (name == 'Cliente') return Colors.blue[800]!;

    final colors = [
      Colors.orange[800]!,
      Colors.purple[700]!,
      Colors.pink[700]!,
      Colors.teal[700]!,
      Colors.brown[700]!,
      Colors.indigo[700]!,
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  _RouteSharePreview? _routeSharePreviewFor(Message message) {
    AppRouteLinkSegment? link;
    for (final segment in MessageParser.parse(message.content)) {
      if (segment is AppRouteLinkSegment) {
        link = segment;
        break;
      }
    }
    if (link == null) return null;

    final linkStart = message.content.indexOf(link.text);
    final beforeLink =
        linkStart <= 0 ? '' : message.content.substring(0, linkStart).trim();
    final afterLink = linkStart < 0
        ? ''
        : message.content.substring(linkStart + link.text.length).trim();
    final beforeLines = beforeLink
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final metadataTitle = message.metadata['title']?.toString().trim();
    final inferredTitle = metadataTitle != null && metadataTitle.isNotEmpty
        ? metadataTitle
        : beforeLines.isNotEmpty
            ? beforeLines.last
            : getRouteTitle(link.route);

    if (beforeLines.isNotEmpty && beforeLines.last == inferredTitle) {
      beforeLines.removeLast();
    }

    return _RouteSharePreview(
      link: link,
      title: inferredTitle,
      intro: beforeLines.join('\n'),
      trailingText: afterLink,
    );
  }

  Widget _buildRouteShareMessage(
    BuildContext context,
    Message message,
    bool isMe,
  ) {
    final preview = _routeSharePreviewFor(message);
    if (preview == null) {
      return ParsedMessageText(
        text: message.content,
        isMe: isMe,
        onReferenceTap: widget.onReferenceTap,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 14,
        ),
      );
    }

    const textStyle = TextStyle(color: Colors.black87, fontSize: 14);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (preview.intro.isNotEmpty) ...[
          ParsedMessageText(
            text: preview.intro,
            isMe: isMe,
            onReferenceTap: widget.onReferenceTap,
            style: textStyle,
          ),
          const SizedBox(height: 8),
        ],
        _buildRouteShareCard(context, preview),
        if (preview.trailingText.isNotEmpty) ...[
          const SizedBox(height: 8),
          ParsedMessageText(
            text: preview.trailingText,
            isMe: isMe,
            onReferenceTap: widget.onReferenceTap,
            style: textStyle,
          ),
        ],
      ],
    );
  }

  Widget _buildRouteShareCard(
    BuildContext context,
    _RouteSharePreview preview,
  ) {
    final theme = Theme.of(context);
    final routeLabel = _routePreviewSectionLabel(preview.link.route);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openRouteShareLink(context, preview.link),
        child: Container(
          constraints: const BoxConstraints(minWidth: 250),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBFDBFE)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.travel_explore_outlined,
                  color: Color(0xFF2563EB),
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vinabike ERP',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: const Color(0xFF2563EB),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      preview.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF0F172A),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Abrir en $routeLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Color(0xFF2563EB),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _routePreviewSectionLabel(String route) {
    final path = Uri.tryParse(route)?.path ?? route;
    if (path.startsWith('/pos')) return 'Punto de venta';
    if (path.startsWith('/taller')) return 'Taller';
    if (path.startsWith('/sales')) return 'Ventas';
    if (path.startsWith('/purchases')) return 'Compras';
    if (path.startsWith('/inventory')) return 'Inventario';
    if (path.startsWith('/clientes')) return 'Clientes';
    if (path.startsWith('/chat')) return 'Mensajería';
    if (path.startsWith('/accounting')) return 'Contabilidad';
    if (path.startsWith('/hr')) return 'RR.HH.';
    if (path.startsWith('/website') || path.startsWith('/tienda')) {
      return 'Sitio web';
    }
    return 'Workspace';
  }

  Future<void> _openRouteShareLink(
    BuildContext context,
    AppRouteLinkSegment link,
  ) async {
    try {
      context
          .read<WorkspaceManager>()
          .navigateActiveWorkspaceFromSharedLink(link.route);
      return;
    } catch (_) {
      if (await canLaunchUrl(link.uri)) {
        await launchUrl(link.uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el enlace compartido.')),
    );
  }

  Widget _buildMessageBubble(
    BuildContext context,
    Message msg,
    List<Message> messages,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMe = msg.isMe;
        final senderId = msg.senderId;
        final bubbleMaxWidth =
            constraints.maxWidth > 0 ? constraints.maxWidth * 0.72 : 280.0;

        return FutureBuilder<Map<String, dynamic>?>(
          future:
              senderId != null ? _getSenderInfo(senderId) : Future.value(null),
          builder: (context, snapshot) {
            final senderInfo = snapshot.data;
            final senderName =
                isMe ? 'Tú' : _resolveIncomingSenderName(msg, senderInfo);
            final senderAvatar = senderInfo?['avatar_url'];
            // Message Content Widget
            Widget contentWidget;
            if (msg.type == 'image') {
              contentWidget = GestureDetector(
                onTap: () {
                  _showImagePreview(msg.content);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    msg.content,
                    width: 200,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: 200,
                        height: 150,
                        color: Colors.grey[300],
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 200,
                      height: 150,
                      color: Colors.grey[300],
                      child: const Icon(Icons.broken_image, size: 48),
                    ),
                  ),
                ),
              );
            } else if (msg.metadata['type'] == 'quote_request') {
              contentWidget = _buildQuoteCard(context, msg, isMe);
            } else if (msg.type == 'file') {
              // File attachment (PDF, doc, etc.)
              contentWidget = GestureDetector(
                onTap: () async {
                  // Open URL in browser
                  final url = Uri.parse(msg.content);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'No se pudo abrir: ${msg.metadata['filename'] ?? 'archivo'}')),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getFileIcon(msg.metadata['extension'] ?? ''),
                        color: isMe ? Colors.black87 : Colors.blue[600],
                        size: 32,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg.metadata['filename'] ?? 'Archivo',
                              style: TextStyle(
                                color: isMe ? Colors.black87 : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              (msg.metadata['extension'] ?? '').toUpperCase(),
                              style: TextStyle(
                                color: isMe ? Colors.black54 : Colors.grey[600],
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.download,
                        color: isMe ? Colors.black54 : Colors.grey[500],
                        size: 20,
                      ),
                    ],
                  ),
                ),
              );
            } else if (msg.type == 'action_request') {
              // ACTION REQUEST - Interactive buttons for customers
              contentWidget = _buildActionRequestCard(context, msg, isMe);
            } else {
              // Text Message
              contentWidget = _buildRouteShareMessage(context, msg, isMe);
            }

            // Timestamp
            final timeStr = DateFormat('HH:mm').format(msg.createdAt);

            // Bubble Decoration
            final bubbleDecoration = BoxDecoration(
              color: isMe ? const Color(0xFFD9FDD3) : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(isMe ? 12 : 0),
                bottomRight: Radius.circular(isMe ? 0 : 12),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            );

            if (!isMe) {
              // INCOMING MESSAGE
              return SelectionContainer.disabled(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.grey[200],
                        backgroundImage: senderAvatar != null
                            ? NetworkImage(senderAvatar)
                            : null,
                        child: senderAvatar == null
                            ? Icon(Icons.person,
                                size: 16, color: Colors.grey[500])
                            : null,
                      ),
                      const SizedBox(width: 8),

                      // Bubble
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          constraints: BoxConstraints(
                            maxWidth: bubbleMaxWidth,
                          ),
                          decoration: bubbleDecoration,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Sender Name (Colored)
                              Text(
                                senderName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _getNameColor(senderName),
                                ),
                              ),
                              const SizedBox(height: 2),

                              contentWidget,

                              // Timestamp
                              Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(top: 4, left: 8),
                                  child: Text(
                                    timeStr,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
              );
            }

            // OUTGOING MESSAGE
            return SelectionContainer.disabled(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 40),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        constraints: BoxConstraints(
                          maxWidth: bubbleMaxWidth,
                        ),
                        decoration: bubbleDecoration,
                        child: Stack(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: contentWidget,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: _buildOutgoingMessageFooter(
                                msg,
                                timeStr,
                                messages,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Handle customer response to action request
  Future<void> _handleActionResponse(
    BuildContext context,
    String messageId,
    String actionType,
    String? targetId,
    String response,
  ) async {
    try {
      final supabase = Supabase.instance.client;

      // Update the message metadata with the response
      await supabase.from('messages').update({
        'metadata': {
          'status': response,
          'responded_at': DateTime.now().toIso8601String(),
        },
      }).eq('id', messageId);

      // If accepted, perform the action
      if (response == 'accepted' && targetId != null) {
        switch (actionType) {
          case 'approve_quote':
            // Update invoice status to confirmed
            final salesService =
                Provider.of<SalesService>(context, listen: false);
            await salesService.updateInvoiceStatus(
                targetId, InvoiceStatus.confirmed);
            break;
          case 'pay_now':
            // Navigate to payment page or show payment dialog
            // This would typically trigger a MercadoPago checkout
            debugPrint('💳 Payment requested for invoice: $targetId');
            break;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                response == 'accepted' ? '✅ Acción completada' : 'Rechazado'),
            backgroundColor:
                response == 'accepted' ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Get appropriate icon for file extension
  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'txt':
        return Icons.text_snippet;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Widget _buildOutgoingMessageFooter(
    Message msg,
    String timeStr,
    List<Message> messages,
  ) {
    final statusIcon = _buildWhatsAppStatusIcon(msg, messages);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 10,
          ),
        ),
        if (statusIcon != null) ...[
          const SizedBox(width: 4),
          statusIcon,
        ],
      ],
    );
  }

  int _whatsAppStatusRank(String? status) {
    switch (status?.toLowerCase()) {
      case 'failed':
        return 50;
      case 'read':
        return 40;
      case 'delivered':
        return 30;
      case 'sent':
        return 20;
      case 'accepted':
        return 10;
      default:
        return 0;
    }
  }

  String? _strongestWhatsAppStatus(Map<String, dynamic> metadata) {
    final statuses = [
      metadata['external_status']?.toString().toLowerCase(),
      metadata['whatsapp_status']?.toString().toLowerCase(),
    ].whereType<String>().where((status) => status.isNotEmpty);

    String? strongest;
    for (final status in statuses) {
      if (_whatsAppStatusRank(status) > _whatsAppStatusRank(strongest)) {
        strongest = status;
      }
    }
    return strongest;
  }

  bool _isWhatsAppMessage(Message msg) {
    final metadata = msg.metadata;
    return metadata['provider'] == 'whatsapp' ||
        metadata['channel'] == 'whatsapp' ||
        metadata['external_provider'] == 'whatsapp' ||
        metadata['external_message_id']?.toString().startsWith('wamid.') ==
            true;
  }

  bool _isInboundWhatsAppMessage(Message msg) {
    if (!_isWhatsAppMessage(msg)) {
      return false;
    }

    final direction =
        msg.metadata['message_direction']?.toString().toLowerCase();
    if (direction == 'inbound') {
      return true;
    }
    if (direction == 'outbound') {
      return false;
    }

    return !msg.isMe;
  }

  bool _isOutboundWhatsAppMessage(Message msg) {
    if (!_isWhatsAppMessage(msg)) {
      return false;
    }

    final direction =
        msg.metadata['message_direction']?.toString().toLowerCase();
    if (direction == 'outbound') {
      return true;
    }
    if (direction == 'inbound') {
      return false;
    }

    return msg.isMe;
  }

  bool _hasLaterInboundWhatsAppReplyInTurn(
    Message msg,
    List<Message> messages,
  ) {
    if (!_isOutboundWhatsAppMessage(msg)) {
      return false;
    }

    final laterInboundMessages = messages
        .where((candidate) =>
            candidate.conversationId == msg.conversationId &&
            _isInboundWhatsAppMessage(candidate) &&
            candidate.createdAt.isAfter(msg.createdAt) &&
            candidate.createdAt.difference(msg.createdAt) <=
                _whatsAppInferredReadWindow)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return laterInboundMessages.isNotEmpty;
  }

  String? _effectiveWhatsAppStatus(Message msg, List<Message> messages) {
    final externalStatus = _strongestWhatsAppStatus(msg.metadata);
    if (externalStatus == 'failed' || externalStatus == 'read') {
      return externalStatus;
    }

    if (_whatsAppStatusRank(externalStatus) >=
            _whatsAppStatusRank('accepted') &&
        _hasLaterInboundWhatsAppReplyInTurn(msg, messages)) {
      return 'read';
    }

    return externalStatus;
  }

  Widget? _buildWhatsAppStatusIcon(Message msg, List<Message> messages) {
    final metadata = msg.metadata;
    final isWhatsAppMessage = _isWhatsAppMessage(msg);

    if (!isWhatsAppMessage) {
      return null;
    }

    if (metadata['pending'] == true) {
      return Icon(
        Icons.access_time_rounded,
        size: 13,
        color: Colors.grey[500],
      );
    }

    final externalStatus = _effectiveWhatsAppStatus(msg, messages);

    switch (externalStatus) {
      case 'accepted':
      case 'sent':
        return Icon(
          Icons.done_rounded,
          size: 14,
          color: Colors.grey[500],
        );
      case 'delivered':
        return Icon(
          Icons.done_all_rounded,
          size: 14,
          color: Colors.grey[500],
        );
      case 'read':
        return const Icon(
          Icons.done_all_rounded,
          size: 14,
          color: Colors.lightBlue,
        );
      case 'failed':
        return Tooltip(
          message: _whatsAppFailureMessage(metadata),
          child: const Icon(
            Icons.error_outline_rounded,
            size: 13,
            color: Colors.red,
          ),
        );
      default:
        return null;
    }
  }

  String _whatsAppFailureMessage(Map<String, dynamic> metadata) {
    final statusPayload = metadata['whatsapp_status_payload'];
    if (statusPayload is Map) {
      final errors = statusPayload['errors'];
      if (errors is List && errors.isNotEmpty) {
        final firstError = errors.first;
        if (firstError is Map) {
          final errorData = firstError['error_data'];
          if (errorData is Map) {
            final details = errorData['details']?.toString();
            if (details != null && details.trim().isNotEmpty) {
              return details;
            }
          }

          final message = firstError['message']?.toString();
          if (message != null && message.trim().isNotEmpty) {
            return message;
          }

          final title = firstError['title']?.toString();
          if (title != null && title.trim().isNotEmpty) {
            return title;
          }
        }
      }
    }

    return 'WhatsApp marcó este mensaje como fallido.';
  }

  Widget _buildQuoteCard(BuildContext context, Message msg, bool isMe) {
    final invoiceId = msg.metadata['invoiceId'];
    final isConfirmed = msg.metadata['status'] == 'confirmed';

    // High contrast colors for both sender (green bubble) and receiver (white bubble)
    // On green bubble (isMe), we use Dark Green/Black text.
    // On white bubble (!isMe), we use Green/Black text.
    final headerIconColor = isMe ? Colors.green[900] : Colors.green;
    final headerTextColor = isMe ? Colors.green[900] : Colors.green[800];
    final headerBgColor =
        isMe ? Colors.black.withValues(alpha: 0.05) : Colors.green[50];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: headerBgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.receipt_long, color: headerIconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Presupuesto',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: headerTextColor,
                  ),
                ),
              ),
              if (isConfirmed)
                Icon(Icons.check_circle, color: headerIconColor, size: 16),
            ],
          ),
        ),

        // Body
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                msg.content.split('\n').first,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87, // Always dark for readability
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isMe
                    ? 'Esperando confirmación del cliente.'
                    : 'Por favor revisa y confirma para proceder.',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54, // Always dark grey
                ),
              ),
            ],
          ),
        ),

        // Actions
        if (!isMe && !isConfirmed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _confirmQuote(context, invoiceId),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Confirmar Presupuesto'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),

        if (isConfirmed)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text('✅ Confirmado',
                  style: TextStyle(
                      color: Colors.green[800], // Always visible
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }

  Widget _buildActionRequestCard(BuildContext context, Message msg, bool isMe) {
    final actionType = msg.metadata['action_type'] as String? ?? 'unknown';
    final targetId = msg.metadata['target_id'] as String?;
    final status = msg.metadata['status'] as String? ?? 'pending';
    final amount = msg.metadata['amount'] as num?;

    // Determine card appearance based on action type
    IconData icon;
    String title;
    String buttonLabel;
    Color accentColor;

    // Contrast Logic:
    // Bubbles are Light Green (Me) or White (Other).
    // Text should ALWAYS be dark (Black/Dark Grey).
    // Feature colors (icons/titles) should be dark versions of their accent.

    Color iconColor;
    Color titleColor = Colors.black87;
    Color headerBgColor =
        isMe ? Colors.black.withValues(alpha: 0.05) : Colors.grey[50]!;

    switch (actionType) {
      case 'approve_quote':
        icon = Icons.description;
        if (status == 'accepted') {
          title = 'Presupuesto Aprobado';
          accentColor = Colors.green;
        } else if (status == 'declined') {
          title = 'Presupuesto Rechazado';
          accentColor = Colors.red;
        } else {
          title = 'Presupuesto Enviado';
          accentColor = Colors.orange;
        }
        buttonLabel = 'Aprobar Presupuesto';
        // Use darker shade for icon to ensure visibility on light green
        iconColor = isMe ? Colors.black54 : accentColor;
        break;
      case 'pay_now':
        icon = Icons.payment;
        title = 'Solicitud de Pago';
        buttonLabel = amount != null
            ? 'Pagar \$${amount.toStringAsFixed(0)}'
            : 'Pagar Ahora';
        accentColor = Colors.green;
        iconColor =
            isMe ? Colors.green[900]! : accentColor; // Visible green on green
        break;
      case 'confirm_delivery':
        icon = Icons.local_shipping;
        title = 'Confirmar Entrega';
        buttonLabel = 'Confirmar Recepción';
        accentColor = Colors.blue;
        iconColor =
            isMe ? Colors.blue[900]! : accentColor; // Visible blue on green
        break;
      default:
        icon = Icons.help_outline;
        title = 'Acción Requerida';
        buttonLabel = 'Ver Detalles';
        accentColor = Colors.grey;
        iconColor = Colors.grey[700]!;
    }

    // Build status badge
    Widget statusBadge = const SizedBox.shrink();
    if (status == 'accepted') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (isMe ? Colors.black : Colors.green).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 14, color: Colors.green[800]),
            const SizedBox(width: 4),
            Text('Aceptado',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[900],
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else if (status == 'declined') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (isMe ? Colors.black : Colors.red).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel, size: 14, color: Colors.red[800]),
            const SizedBox(width: 4),
            Text('Rechazado',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[900],
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: headerBgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: titleColor,
                  ),
                ),
              ),
              statusBadge,
            ],
          ),
        ),
        // Message content
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            msg.content,
            style: const TextStyle(
                color: Colors.black87, fontSize: 13, height: 1.4),
          ),
        ),
        // Action button (only if pending and viewer is not sender)
        if (status == 'pending' && !isMe)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleActionResponse(
                        context, msg.id, actionType, targetId, 'declined'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                    ),
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _handleActionResponse(
                        context, msg.id, actionType, targetId, 'accepted'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                    ),
                    child: Text(buttonLabel),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmQuote(BuildContext context, String? invoiceId) async {
    if (invoiceId == null) return;

    try {
      await context
          .read<SalesService>()
          .updateInvoiceStatus(invoiceId, InvoiceStatus.confirmed);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Presupuesto confirmado. ¡Gracias!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al confirmar: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }
}
