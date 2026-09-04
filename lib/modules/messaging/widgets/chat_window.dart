import 'dart:async';
import 'dart:convert';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/whatsapp_outgoing_preview.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../purchases/models/purchase_invoice.dart';
import '../../purchases/services/purchase_service.dart';
import '../../sales/services/sales_service.dart';
import '../../settings/services/appearance_service.dart';
import '../../tasks/services/task_service.dart';
import '../../tasks/widgets/task_thread_root_card.dart';
import '../../website/services/website_service.dart';
import '../models/conversation.dart';
import '../models/conversation_smart_action_capabilities.dart';
import '../services/messaging_service.dart';
import '../services/messaging_attachment_service.dart';
import '../services/chat_media_cache.dart';
import 'chat_media_thumbnail.dart';
import 'chat_audio_message.dart';
import 'chat_voice_recorder.dart';
import '../services/meta_messaging_service.dart';
import '../models/message.dart';
import '../models/message_reply.dart';
import '../models/chat_attachment_draft.dart';
import '../models/message_delivery_state.dart';
import '../models/autocomplete_suggestion.dart';
import 'parsed_message_text.dart';
import 'purchase_document_preview_dialog.dart';
import '../providers/chat_provider.dart';
import '../utils/message_parser.dart';
import '../utils/conversation_channel_presentation.dart';
import 'assign_context_dialog.dart';
import 'chat_attachment_viewer.dart';
import 'message_delivery_indicator.dart';
import '../../storage/models/app_stored_file.dart';
import '../../../shared/services/whatsapp_service.dart';
import '../../../shared/services/route_share_service.dart';
import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/services/workspace_manager.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/file_download.dart';
import '../../../shared/utils/purchase_document_pdf_generator.dart';
import '../models/conversation_context_hint.dart';
import '../../../shared/utils/supplier_whatsapp_phone.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_surface_icon_button.dart';
import '../../../shared/services/supabase_functions_region.dart';

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

class _TimelineDaySeparator {
  final DateTime day;

  const _TimelineDaySeparator(this.day);
}

class _MessageGrouping {
  final bool withPrevious;
  final bool withNext;

  const _MessageGrouping({
    this.withPrevious = false,
    this.withNext = false,
  });
}

class _WhatsAppTemplatePreviewFailure implements Exception {
  const _WhatsAppTemplatePreviewFailure(this.message);

  final String message;
}

enum _ChatInfoSection { info, media, workflow, backup }

class _ChatAttachment {
  final Message message;
  final String? url;
  final String name;
  final String extension;
  final bool isImage;
  final bool isExternal;

  const _ChatAttachment({
    required this.message,
    this.url,
    required this.name,
    required this.extension,
    required this.isImage,
    this.isExternal = false,
  });
}

/// Un hilo de proveedor que corre por otro número que el registrado en su
/// ficha (el vendedor, o el Teléfono si no hay vendedor con número).
class _SupplierPhoneMismatch {
  const _SupplierPhoneMismatch({
    required this.threadPhone,
    required this.registeredPhone,
  });

  final String threadPhone;
  final String registeredPhone;
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
  @visibleForTesting
  final MessagingAttachmentService? attachmentService;
  final String? initialThreadRootMessageId;

  /// Test seam for the local preview read. Production always resolves the
  /// exact contact/business values through the canonical services below.
  @visibleForTesting
  final Future<String?> Function(WhatsAppTemplateOption option)?
      whatsAppTemplatePreviewLoader;

  const ChatWindow({
    super.key,
    required this.conversation,
    this.onReferenceTap,
    this.isContextPanelClosed = false,
    this.onShowContextPanel,
    this.headerActions = const [],
    this.compact = false,
    this.attachmentService,
    this.initialThreadRootMessageId,
    this.whatsAppTemplatePreviewLoader,
  });

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  static const Color _accentBlue = Color(0xFF093357);
  static const Duration _whatsAppTemplatePreviewTimeout = Duration(seconds: 8);

  /// Same sky the purchase list paints on «Enviada», so the composer entry
  /// reads as the step that produces that state.
  static const Color _purchaseDocumentAccent = Color(0xFF0EA5E9);
  static const String _pendingAttachmentMutationBlockedMessage =
      'WhatsApp aún no confirma este adjunto. Conservamos la misma reserva '
      'para evitar un envío duplicado; los controles se habilitarán cuando '
      'llegue la confirmación.';
  static final RegExp _durableMessageIdPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
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
  MessageReply? _replyToMessage;
  final ScrollController _scrollController = ScrollController();
  final ScrollController _threadScrollController = ScrollController();
  final ScrollController _emojiScrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _emojiSearchFocusNode = FocusNode();
  final TextEditingController _emojiSearchController = TextEditingController();
  final MessagingService _messagingService = MessagingService();
  final MetaMessagingService _metaMessagingService = MetaMessagingService();
  final Object _conversationViewOwner = Object();
  ChatProvider? _chatProvider;
  int? _composerSession;
  Timer? _composerFocusTimer;
  String? _reportedConversationId;
  String? _taskContextConversationIdLoaded;
  bool? _reportedConversationVisibility;
  bool _isSendingMessage = false;
  bool _isEmojiPickerOpen = false;
  OverlayEntry? _emojiOverlayEntry;

  /// Cuando el panel de emojis se abre desde el «+» de una reacción, este es el
  /// mensaje al que va dirigido. Nulo = el panel escribe en el compositor, que
  /// es su uso original.
  Message? _emojiPickerReactionTarget;
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

  /// Plantilla que el operador está revisando en el panel, con el texto exacto
  /// que recibirá el contacto. Tocar una plantilla ya no envía: abre esto.
  WhatsAppTemplateOption? _reviewingTemplate;
  String? _reviewingTemplateText;
  String? _reviewingTemplateError;
  bool _isReviewingTemplateLoading = false;
  bool _reviewingTemplateNeedsSupplierContact = false;
  int _reviewingTemplateGeneration = 0;
  String? _activeComposerMenuName;
  bool _showAutomaticMessagesPanel = false;
  bool _showChatInfoPanel = false;
  String? _activeThreadRootMessageId;
  bool _alsoSendThreadReplyToChannel = false;
  bool _isExportingChatArchive = false;
  bool _isDraggingAttachment = false;
  bool _isSendingPendingAttachments = false;
  bool _isPreparingPurchaseDocument = false;
  bool _pendingAttachmentReconciliationScheduled = false;
  bool _showJumpToLatest = false;
  bool _historyAutoLoadScheduled = false;
  final List<PendingChatAttachment> _pendingAttachments = [];
  int _pendingAttachmentSerial = 0;

  /// Voice notes. The bar replaces the text field while recording; the
  /// finished note goes through the same pipeline as any attachment.
  late final ChatVoiceRecorderController _voiceRecorder =
      ChatVoiceRecorderController()..addListener(_onVoiceRecorderChanged);

  void _onVoiceRecorderChanged() {
    if (mounted) setState(() {});
  }

  bool get _showsVoiceButton =>
      _supportsOutgoingAttachments &&
      !_voiceRecorder.isRecording &&
      _messageController.text.trim().isEmpty &&
      _pendingAttachments.isEmpty &&
      !_isSendingPendingAttachments;

  Future<void> _startVoiceNote() async {
    _removeComposerMenuOverlay(notify: false);
    final started = await _voiceRecorder.start();
    if (!started && mounted) {
      final reason = _voiceRecorder.error ?? 'No se pudo grabar.';
      _showErrorSnackBar(context, reason);
      await _voiceRecorder.cancel();
    }
  }

  Future<void> _cancelVoiceNote() => _voiceRecorder.cancel();

  Future<void> _finishVoiceNote() async {
    final note = await _voiceRecorder.stop();
    if (!mounted) return;
    if (note == null) {
      _showErrorSnackBar(context, 'La nota quedó demasiado corta.');
      return;
    }
    _pendingAttachmentSerial += 1;
    setState(() {
      _pendingAttachments.add(
        PendingChatAttachment(
          id: 'voice-${DateTime.now().microsecondsSinceEpoch}-$_pendingAttachmentSerial',
          fileName: note.fileName,
          bytes: note.bytes,
          extension: 'm4a',
          isImage: false,
          durationSeconds: note.duration.inSeconds,
        ),
      );
    });
    await _sendPendingAttachments();
  }

  _ChatInfoSection _selectedChatInfoSection = _ChatInfoSection.info;
  final GlobalKey _composerActionsButtonKey = GlobalKey();
  Timer? _serviceWindowTicker;
  Future<Map<String, dynamic>?>? _whatsAppContactFuture;
  String? _whatsAppContactFutureConversationId;
  Future<Map<String, dynamic>?>? _conversationContactFuture;
  String? _conversationContactFutureConversationId;
  Future<_SupplierPhoneMismatch?>? _supplierPhoneMismatchFuture;
  String? _supplierPhoneMismatchConversationId;

  // Cache futures so FutureBuilder doesn't re-fire on every rebuild.
  final Map<String, Future<Map<String, dynamic>?>> _senderInfoFutureCache = {};
  final Map<String, Future<String?>> _whatsAppMediaFutureCache = {};
  final MessagingAttachmentService _defaultAttachmentService =
      MessagingAttachmentService();
  MessagingAttachmentService get _messagingAttachmentService =>
      widget.attachmentService ?? _defaultAttachmentService;

  bool get _isWhatsAppConversation => widget.conversation.isWhatsApp;
  bool get _isMetaConversation => widget.conversation.isMetaMessaging;
  bool get _supportsOutgoingAttachments => !_isMetaConversation;

  bool get _hasBlockingOutcomeUnknownAttachment => _pendingAttachments.any(
        (attachment) => attachment.outcomeUnknown && !attachment.canRetrySafely,
      );

  void _showPendingAttachmentMutationBlocked() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(_pendingAttachmentMutationBlockedMessage),
        ),
      );
  }

  bool _guardPendingAttachmentMutation() {
    if (!_hasBlockingOutcomeUnknownAttachment) return false;
    _showPendingAttachmentMutationBlocked();
    return true;
  }

  bool _isDurableAttachmentMessage(
    Message message,
    String attachmentId,
  ) {
    if (message.conversationId != widget.conversation.id ||
        !_durableMessageIdPattern.hasMatch(message.id)) {
      return false;
    }
    return MessagingAttachmentService.attachmentId(message) == attachmentId;
  }

  void _schedulePendingAttachmentReconciliation(List<Message> messages) {
    if (_pendingAttachmentReconciliationScheduled ||
        !_hasBlockingOutcomeUnknownAttachment) {
      return;
    }
    final resolvedReservationIds = _pendingAttachments
        .where(
          (attachment) =>
              attachment.outcomeUnknown &&
              !attachment.canRetrySafely &&
              attachment.reservation != null &&
              messages.any(
                (message) => _isDurableAttachmentMessage(
                  message,
                  attachment.reservation!.id,
                ),
              ),
        )
        .map((attachment) => attachment.reservation!.id)
        .toSet();
    if (resolvedReservationIds.isEmpty) return;

    _pendingAttachmentReconciliationScheduled = true;
    final conversationId = widget.conversation.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingAttachmentReconciliationScheduled = false;
      if (!mounted || widget.conversation.id != conversationId) return;
      final before = _pendingAttachments.length;
      setState(() {
        _pendingAttachments.removeWhere(
          (attachment) =>
              attachment.reservation != null &&
              resolvedReservationIds.contains(attachment.reservation!.id),
        );
      });
      if (before != _pendingAttachments.length) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Adjunto confirmado por WhatsApp. La reserva quedó reconciliada.',
              ),
            ),
          );
      }
    });
  }

  String? get _effectiveContextType => widget.conversation.effectiveContextType;

  String? get _effectiveContextId => widget.conversation.effectiveContextId;

  ConversationSmartActionCapabilities get _smartActionCapabilities =>
      ConversationSmartActionCapabilities.fromConversation(
        widget.conversation,
      );

  bool get _canUseSmartActions =>
      _smartActionCapabilities.isEligibleCustomerConversation;

  String? get _canonicalContextRoute {
    final contextId = _effectiveContextId;
    if (contextId == null || contextId.isEmpty) return null;
    return switch (_effectiveContextType) {
      'job' => '/taller/pegas/$contextId',
      'invoice' => '/sales/invoices/$contextId',
      'order' || 'online_order' => '/website/orders',
      'purchase_invoice' => '/purchases/$contextId',
      'supplier' => '/purchases/suppliers/$contextId',
      _ => null,
    };
  }

  bool get _canOpenCurrentContext =>
      widget.conversation.hasSupportedContextPanel &&
      (widget.onShowContextPanel != null || _canonicalContextRoute != null);

  void _openCurrentContext() {
    final showPanel = widget.onShowContextPanel;
    if (showPanel != null) {
      showPanel();
      return;
    }
    final route = _canonicalContextRoute;
    if (route != null) {
      context.read<WorkspaceManager>().openRouteInWorkspace(route);
    }
  }

  void _openTaskFromThread(String taskId) {
    if (taskId.trim().isEmpty) return;
    context.read<RightToolbarService>().openConversation(
          tool: ToolbarTool.tasks,
          conversationId: taskId,
        );
  }

  void _openTaskThreadRoute(String route) {
    unawaited(context.read<WorkspaceManager>().pushActiveWorkspace(route));
  }

  String? _taskIdForRoot(Message root) {
    final stored = widget.conversation.taskIdForRoot(root.id);
    if (stored != null && stored.isNotEmpty) return stored;
    if (root.metadata['task_thread_root'] != true) return null;
    final metadataTaskId = root.metadata['task_id']?.toString().trim();
    return metadataTaskId == null || metadataTaskId.isEmpty
        ? null
        : metadataTaskId;
  }

  void _openThreadReplies(String rootMessageId) {
    _removeOverlay();
    _removeEmojiOverlay();
    _removeComposerMenuOverlay(notify: false);
    setState(() {
      _activeThreadRootMessageId = rootMessageId;
      _alsoSendThreadReplyToChannel = false;
      _showChatInfoPanel = false;
    });
    _jumpToLatest();
  }

  void _returnToTaskConversation() {
    _removeOverlay();
    _removeEmojiOverlay();
    _removeComposerMenuOverlay(notify: false);
    setState(() {
      _activeThreadRootMessageId = null;
      _alsoSendThreadReplyToChannel = false;
      _showChatInfoPanel = false;
    });
  }

  Widget _buildTaskThreadNavigation(BuildContext context, int replyCount) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      key: const ValueKey<String>('task-thread-replies-header'),
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey<String>('task-thread-close-replies'),
            tooltip: 'Volver al canal',
            onPressed: _returnToTaskConversation,
            icon: const Icon(Icons.arrow_back, size: 18),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              replyCount == 1
                  ? 'Hilo · 1 respuesta'
                  : 'Hilo · $replyCount respuestas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskThreadRoot(
    BuildContext context,
    String taskId,
    int replyCount, {
    String? fallbackTitle,
    VoidCallback? onOpenReplies,
  }) {
    final taskService = context.watch<TaskService>();
    final matchingTasks = taskService.tasks.where((task) => task.id == taskId);
    if (matchingTasks.isEmpty) {
      return TaskThreadRootLoadingCard(
        title: fallbackTitle ?? 'Tarea vinculada',
        replyCount: replyCount,
        onOpenTask: () => _openTaskFromThread(taskId),
        onOpenReplies: onOpenReplies,
      );
    }

    final task = matchingTasks.first;
    final links = taskService.jobItemsOf(taskId);
    final jobHeader = taskService.jobHeaderOf(task);
    final linkedJobId =
        task.linkedJobId ?? (links.isNotEmpty ? links.first.jobId : null);
    final jobNumber = task.linkedJobNumber ??
        (links.isNotEmpty ? links.first.jobNumber : null) ??
        jobHeader?.jobNumber;
    final jobSummary = [
      jobHeader?.customerName,
      jobHeader?.clientRequest,
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TaskThreadRootCard(
        task: task,
        links: links,
        replyCount: replyCount,
        onOpenReplies: onOpenReplies,
        jobNumber: jobNumber,
        jobSummary: jobSummary,
        onOpenTask: () => _openTaskFromThread(taskId),
        onOpenJob: linkedJobId == null
            ? null
            : () => _openTaskThreadRoute('/taller/pegas/$linkedJobId'),
        onOpenLinkedContext: task.linkedContextTarget == null
            ? null
            : () => _openTaskThreadRoute(task.linkedContextTarget!.route),
      ),
    );
  }

  bool get _canStartWhatsAppFromConversation =>
      widget.conversation.isSupport && widget.conversation.isWebsitePortal;

  void _clearWhatsAppContactCache() {
    _whatsAppContactFuture = null;
    _whatsAppContactFutureConversationId = null;
    _conversationContactFuture = null;
    _conversationContactFutureConversationId = null;
    _supplierPhoneMismatchFuture = null;
    _supplierPhoneMismatchConversationId = null;
  }

  Future<_SupplierPhoneMismatch?> _getSupplierPhoneMismatchFuture() {
    if (_supplierPhoneMismatchConversationId != widget.conversation.id) {
      _supplierPhoneMismatchConversationId = widget.conversation.id;
      _supplierPhoneMismatchFuture = _resolveSupplierPhoneMismatch();
    }
    return _supplierPhoneMismatchFuture ??= _resolveSupplierPhoneMismatch();
  }

  /// El número registrado viene en el hint (vendedor, o el Teléfono de la
  /// ficha); el del hilo lo dice el vínculo WhatsApp. Cuando el vendedor
  /// cambia, el hilo viejo sigue abierto con sus mensajes y el ERP le escribe
  /// al nuevo: el panel lo declara en vez de mostrar dos números sin explicar.
  Future<_SupplierPhoneMismatch?> _resolveSupplierPhoneMismatch() async {
    if (!widget.conversation.isSupplierConversation ||
        !_isWhatsAppConversation) {
      return null;
    }
    final registered = widget.conversation.contextHint?.supplierPhone?.trim();
    if (!supplierPhoneIsUsable(registered)) return null;
    Map<String, dynamic>? contact;
    try {
      contact = await _getConversationContactFuture();
    } catch (_) {
      return null;
    }
    final threadPhone = contact?['phone']?.toString().trim();
    if (!supplierThreadPhoneDiffers(
      threadPhone: threadPhone,
      registeredPhone: registered,
    )) {
      return null;
    }
    return _SupplierPhoneMismatch(
      threadPhone: threadPhone!,
      registeredPhone: registered!,
    );
  }

  /// Abre —o crea— el hilo con el número registrado del proveedor y lo deja
  /// activo en la bandeja de proveedores. El hilo viejo no se toca: queda en
  /// el historial con sus mensajes.
  Future<void> _openRegisteredSupplierChat(
    _SupplierPhoneMismatch mismatch,
  ) async {
    if (_isSendingMessage) return;
    final provider = context.read<ChatProvider>();
    final toolbar = context.read<RightToolbarService>();
    final messenger = ScaffoldMessenger.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final hint = widget.conversation.contextHint;
    final supplierId = hint?.supplierId ??
        (_effectiveContextType == 'supplier' ? _effectiveContextId : null);
    final supplierName = hint?.supplierName?.trim();
    setState(() => _isSendingMessage = true);
    try {
      await provider.openWhatsAppCustomerChat(
        phoneNumber: mismatch.registeredPhone,
        contactName: supplierName != null && supplierName.isNotEmpty
            ? supplierName
            : widget.conversation.title ?? 'Proveedor',
        contextType: supplierId == null ? null : 'supplier',
        contextId: supplierId,
      );
      if (!mounted) return;
      final conversationId = provider.activeConversationId;
      if (conversationId != null && conversationId != widget.conversation.id) {
        toolbar.openConversation(
          tool: ToolbarTool.supplierMessages,
          conversationId: conversationId,
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Chat abierto con ${_formatContactPhone(mismatch.registeredPhone)}.',
          ),
          backgroundColor: roles.success.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir el chat: $e'),
          backgroundColor: roles.danger.accent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingMessage = false);
    }
  }

  Future<void> _copyPanelValue(String value, {required String label}) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado')),
    );
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

  void _syncServiceWindowTicker() {
    _serviceWindowTicker?.cancel();
    _serviceWindowTicker = null;

    if (!_isWhatsAppConversation && !_isMetaConversation) return;

    if (_isWhatsAppConversation) {
      unawaited(_getWhatsAppContactFuture());
    }

    _serviceWindowTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider = context.read<ChatProvider>();
    final session = _chatProvider!.composerSession;
    if (_composerSession != null && _composerSession != session) {
      _replyToMessage = null;
      _messageController.removeListener(_onTextChanged);
      _messageController.clear();
      _messageController.addListener(_onTextChanged);
      _pendingAttachments.clear();
    }
    if (_composerSession == null) {
      _pendingAttachments.addAll(
          _chatProvider!.getComposerAttachments(widget.conversation.id));
    }
    _composerSession = session;
    _loadTaskChannelContext();
  }

  void _loadTaskChannelContext() {
    if (!widget.conversation.isTaskChannel ||
        _taskContextConversationIdLoaded == widget.conversation.id) {
      return;
    }
    _taskContextConversationIdLoaded = widget.conversation.id;
    unawaited(context.read<TaskService>().fetchTasks());
  }

  @override
  void didUpdateWidget(covariant ChatWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.id != widget.conversation.id) {
      _composerFocusTimer?.cancel();
      _saveComposerDraft(oldWidget.conversation.id);
      _messageController.removeListener(_onTextChanged);
      final draft = _chatProvider?.getComposerDraft(widget.conversation.id);
      _replyToMessage = draft?.reply;
      _messageController.text = draft?.text ?? '';
      _messageController.addListener(_onTextChanged);
      _isSendingMessage = false;
      _saveAttachmentDraft(oldWidget.conversation.id);
      final nextAttachmentDraft =
          _chatProvider?.getComposerAttachments(widget.conversation.id);
      _pendingAttachments
        ..clear()
        ..addAll(nextAttachmentDraft ?? const <PendingChatAttachment>[]);
      _isSendingPendingAttachments = false;
      _senderInfoFutureCache.clear();
      _whatsAppMediaFutureCache.clear();
      _clearWhatsAppContactCache();
      _removeEmojiOverlay();
      _removeComposerMenuOverlay(notify: false);
      _showAutomaticMessagesPanel = false;
      _showChatInfoPanel = false;
      _activeThreadRootMessageId =
          widget.initialThreadRootMessageId?.trim().isNotEmpty == true
              ? widget.initialThreadRootMessageId!.trim()
              : null;
      _alsoSendThreadReplyToChannel = false;
      _historyAutoLoadScheduled = false;
      _selectedChatInfoSection = _ChatInfoSection.info;
      _loadTaskChannelContext();
      _syncServiceWindowTicker();
      _captureOpeningUnreadCount();
      _loadMessages();
      _applyPendingDraft();
    } else if (oldWidget.initialThreadRootMessageId !=
        widget.initialThreadRootMessageId) {
      _activeThreadRootMessageId =
          widget.initialThreadRootMessageId?.trim().isNotEmpty == true
              ? widget.initialThreadRootMessageId!.trim()
              : null;
      _alsoSendThreadReplyToChannel = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _activeThreadRootMessageId =
        widget.initialThreadRootMessageId?.trim().isNotEmpty == true
            ? widget.initialThreadRootMessageId!.trim()
            : null;
    _scrollController.addListener(_handleTimelineScroll);
    _captureOpeningUnreadCount();
    _loadMessages();
    _applyPendingDraft();
    _syncServiceWindowTicker();
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _composerFocusTimer?.cancel();
    _saveComposerDraft(widget.conversation.id);
    _saveAttachmentDraft(widget.conversation.id);
    _chatProvider?.detachConversationView(_conversationViewOwner);
    _removeEmojiOverlay();
    _removeComposerMenuOverlay(notify: false);
    _removeOverlay();
    _serviceWindowTicker?.cancel();
    _debounce?.cancel();
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _voiceRecorder
      ..removeListener(_onVoiceRecorderChanged)
      ..dispose();
    _historyRequestDebounce?.cancel();
    _scrollController.removeListener(_handleTimelineScroll);
    _scrollController.dispose();
    _threadScrollController.dispose();
    _emojiScrollController.dispose();
    _focusNode.dispose();
    _emojiSearchFocusNode.dispose();
    _emojiSearchController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _saveComposerDraft(widget.conversation.id);
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
    final bikeshopService = context.read<BikeshopService>();
    final salesService = context.read<SalesService>();

    try {
      if (query.isEmpty || query.toUpperCase().startsWith('J')) {
        final term =
            query.toUpperCase().replaceAll('JOB-', '').replaceAll('JOB', '');
        final jobs = await bikeshopService.getJobs(searchTerm: term);
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
        final invoices = salesService.searchInvoices(term);
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
                      border: Border(
                          bottom: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant)),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
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

  /// Abre el panel de emojis del chat apuntando a un mensaje, para el «+» de
  /// la barra de reacciones. Se ancla y se dibuja igual que el del compositor:
  /// dentro del chat, no como un diálogo flotante al medio de la pantalla.
  void _openEmojiPickerForReaction(Message msg) {
    _removeEmojiOverlay();
    _removeOverlay();
    _removeComposerMenuOverlay(notify: false);
    _emojiPickerReactionTarget = msg;
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
    _emojiPickerReactionTarget = null;
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
    _resetWhatsAppTemplatePreview();
    if (notify && mounted) setState(() {});
    if (restoreComposerFocus) _restoreComposerFocus();
  }

  void _resetWhatsAppTemplatePreview() {
    _reviewingTemplateGeneration += 1;
    _reviewingTemplate = null;
    _reviewingTemplateText = null;
    _reviewingTemplateError = null;
    _isReviewingTemplateLoading = false;
    _reviewingTemplateNeedsSupplierContact = false;
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
    // Hug the button's own edge instead of centring on it: the panel is wider
    // than the button, so centring pushes it past the pane and the clamp then
    // parks it against the window border, far from what was pressed.
    final left = anchorRect.left > horizontalLimit
        ? (anchorRect.right - effectiveWidth)
            .clamp(12.0, horizontalLimit)
            .toDouble()
        : anchorRect.left.clamp(12.0, horizontalLimit).toDouble();

    // `estimatedHeight` only chooses the side. The panel is then pinned by the
    // edge that touches the button, so a panel shorter than the estimate stays
    // glued to it instead of floating that difference away.
    final spaceAbove = anchorRect.top - 20;
    final spaceBelow = overlaySize.height - anchorRect.bottom - 20;
    final opensUpward = spaceAbove >= 140 &&
        (spaceAbove >= estimatedHeight || spaceAbove >= spaceBelow);
    final maxPanelHeight = (opensUpward ? spaceAbove : spaceBelow)
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
          top: opensUpward ? null : anchorRect.bottom + 8,
          bottom: opensUpward ? overlaySize.height - anchorRect.top + 8 : null,
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
    // Mismo panel, distinto destino. Un segundo selector para reaccionar se
    // desincronizaría del del compositor y, peor, WhatsApp no lo tiene: es el
    // mismo teclado de emojis abierto desde otro lado.
    final reactionTarget = _emojiPickerReactionTarget;
    if (reactionTarget != null) {
      _hideEmojiPicker();
      unawaited(_toggleReaction(reactionTarget, emoji));
      return;
    }
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
      if (!mounted) return;

      final provider = context.read<ChatProvider>();
      final visible = _isConversationHostVisible(context, listen: false);
      provider.updateConversationView(
        owner: _conversationViewOwner,
        conversationId: widget.conversation.id,
        visible: visible,
      );
      _reportedConversationId = widget.conversation.id;
      _reportedConversationVisibility = visible;
      final count =
          visible ? provider.takeOpeningUnreadCount(widget.conversation.id) : 0;
      if (_openingUnreadCount == 0 && count > 0 && mounted) {
        setState(() {
          _openingUnreadConversationId = widget.conversation.id;
          _openingUnreadCount = count;
        });
      }
    });
  }

  bool _isConversationHostVisible(
    BuildContext context, {
    bool listen = true,
  }) {
    try {
      final workspace = Provider.of<Workspace>(context, listen: false);
      final manager = Provider.of<WorkspaceManager>(context, listen: listen);
      return manager.activeWorkspace?.id == workspace.id;
    } catch (_) {
      // Public/customer portal hosts do not live inside a desktop workspace.
      return true;
    }
  }

  void _reportConversationHostVisibility(
    ChatProvider provider,
    bool visible,
  ) {
    if (_reportedConversationId == widget.conversation.id &&
        _reportedConversationVisibility == visible) {
      return;
    }
    _reportedConversationId = widget.conversation.id;
    _reportedConversationVisibility = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      provider.updateConversationView(
        owner: _conversationViewOwner,
        conversationId: widget.conversation.id,
        visible: visible,
      );
      if (visible) {
        final count = provider.takeOpeningUnreadCount(widget.conversation.id);
        if (_openingUnreadCount == 0 && count > 0 && mounted) {
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
    DateTime? previousDay;

    for (final message in messages) {
      final day = DateTime(
        message.createdAt.year,
        message.createdAt.month,
        message.createdAt.day,
      );
      if (previousDay == null || day != previousDay) {
        items.add(_TimelineDaySeparator(day));
        previousDay = day;
      }
      if (message.id == markerMessageId) {
        items.add(_UnreadMessagesMarker(_openingUnreadCount));
      }
      items.add(message);
    }

    return items;
  }

  /// Espera a que el scroll SE DETENGA antes de pedir historial.
  ///
  /// Antes se pedía en cada evento de scroll. Cargar mensajes viejos mientras
  /// el dedo está en movimiento inserta contenido en una lista invertida, la
  /// extensión cambia y el viewport corrige la posición en medio del gesto: eso
  /// es el «se queda pegado y vibra» al volver hacia abajo tras haber subido.
  /// El indicador de «ir al último» sí sigue al dedo, porque no toca la
  /// geometría.
  Timer? _historyRequestDebounce;

  void _handleTimelineScroll() {
    if (!_scrollController.hasClients) return;

    _historyRequestDebounce?.cancel();
    _historyRequestDebounce = Timer(const Duration(milliseconds: 160), () {
      if (!mounted || !_scrollController.hasClients) return;
      // Una inercia larga sigue viva cuando expira el temporizador; pedir ahí
      // reintroduce exactamente el defecto.
      if (_scrollController.position.isScrollingNotifier.value) return;
      _requestOlderMessagesIfAtStart();
    });

    final shouldShow = _scrollController.offset > 180;
    if (shouldShow == _showJumpToLatest || !mounted) return;
    setState(() => _showJumpToLatest = shouldShow);
  }

  void _requestOlderMessagesIfAtStart() {
    if (!_scrollController.hasClients) return;
    final provider = _chatProvider;
    if (provider == null) return;
    final conversationId = widget.conversation.id;
    final position = _scrollController.position;
    final distanceToOldest = position.maxScrollExtent - position.pixels;
    if (distanceToOldest > 180 ||
        !provider.hasMoreMessages(conversationId) ||
        provider.isLoadingOlderMessages(conversationId) ||
        provider.olderMessagesErrorForConversation(conversationId) != null) {
      return;
    }
    unawaited(provider.loadOlderMessages(conversationId));
  }

  void _scheduleOlderMessagesIfAtStart(ChatProvider provider) {
    final conversationId = widget.conversation.id;
    if (_historyAutoLoadScheduled ||
        !provider.hasMoreMessages(conversationId) ||
        provider.isLoadingOlderMessages(conversationId) ||
        provider.olderMessagesErrorForConversation(conversationId) != null) {
      return;
    }
    _historyAutoLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyAutoLoadScheduled = false;
      if (!mounted || widget.conversation.id != conversationId) return;
      _requestOlderMessagesIfAtStart();
    });
  }

  Future<void> _jumpToLatest() async {
    final controller =
        _activeThreadRootMessageId != null && _threadScrollController.hasClients
            ? _threadScrollController
            : _scrollController;
    if (!controller.hasClients) return;
    await controller.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
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

  bool _isCurrentComposer(String conversationId, int? session) =>
      mounted &&
      widget.conversation.id == conversationId &&
      _chatProvider?.composerSession == session;

  void _saveAttachmentDraft(String conversationId) {
    if (_composerSession == null) return;
    _chatProvider?.saveComposerAttachments(conversationId, _pendingAttachments,
        session: _composerSession!);
  }

  void _saveComposerDraft(String conversationId) {
    if (_composerSession == null) return;
    _chatProvider?.saveComposerDraft(
        conversationId,
        ChatComposerDraft(
            text: _messageController.text, reply: _replyToMessage),
        session: _composerSession!);
  }

  void _restoreFailedDraft(ChatProvider provider, String conversationId,
      String text, MessageReply? reply, int session) {
    if (provider.composerSession != session) return;
    final existing = provider.getComposerDraft(conversationId);
    if (existing?.text.isNotEmpty == true || existing?.reply != null) return;
    provider.saveComposerDraft(
        conversationId, ChatComposerDraft(text: text, reply: reply),
        session: session);
    if (!mounted || widget.conversation.id != conversationId) return;
    setState(() => _replyToMessage = reply);
    _messageController.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  bool _canQuoteMessage(Message message) =>
      message.conversationId == widget.conversation.id &&
      message.type != 'system' &&
      !message.id.startsWith('temp-') &&
      message.metadata['pending'] != true &&
      (widget.conversation.isInternal ||
          (_isWhatsAppConversation &&
              message.metadata['external_message_id']?.toString().isNotEmpty ==
                  true));

  void _selectReply(Message message) {
    if (!_canQuoteMessage(message)) return;
    setState(() => _replyToMessage = MessageReply.fromMessage(message));
    _saveComposerDraft(widget.conversation.id);
    _restoreComposerFocus();
  }

  Widget _buildMessageQuote(MessageReply reply, {bool composing = false}) {
    final author = reply.senderId != null &&
            reply.senderId == _messagingService.currentUserId
        ? 'Tú'
        : reply.senderName?.trim().isNotEmpty == true
            ? reply.senderName!
            : reply.direction == 'inbound'
                ? widget.conversation.title ?? 'Contacto'
                : 'Mensaje';
    return VbNotice(
      key: composing ? const ValueKey('chat-reply-preview') : null,
      tone: VbNoticeTone.neutral,
      glyph: '↩',
      title: composing ? 'Responder a $author' : author,
      body: reply.preview,
      bodyMaxLines: 2,
      action: composing
          ? IconButton(
              tooltip: 'Cancelar respuesta',
              onPressed: () {
                setState(() => _replyToMessage = null);
                _saveComposerDraft(widget.conversation.id);
              },
              icon: const Icon(Icons.close),
            )
          : null,
    );
  }

  void _applyPendingDraft() {
    final conversationId = widget.conversation.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.conversation.id != conversationId ||
          _messageController.text.isNotEmpty) return;

      final provider = context.read<ChatProvider>();
      final composer = provider.getComposerDraft(conversationId);
      final draft =
          composer?.text ?? provider.getConversationDraft(conversationId)?.body;
      if (composer?.reply != null)
        setState(() => _replyToMessage = composer!.reply);
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
    final composerSession = chatProvider.composerSession;
    final conversationId = widget.conversation.id;
    final reply = _replyToMessage;
    final pendingText = text;
    final threadRootMessageId = _activeThreadRootMessageId;
    final messageMetadata = <String, dynamic>{
      ...?metadata,
      if (reply != null) 'reply_to': reply.toJson(),
      if (threadRootMessageId != null)
        'thread_root_message_id': threadRootMessageId,
      if (threadRootMessageId != null && _alsoSendThreadReplyToChannel)
        'also_send_to_channel': true,
    };

    if (_isWhatsAppConversation) {
      // Snappy precheck: derive the 24h window state from messages we already
      // have in memory instead of awaiting the contact DB query. The contact
      // lookup is still kicked off in the background (and surfaced via the
      // gauge / dispatch); if the cached window check is wrong we'll get the
      // re-engagement code from Graph and fall back to a template anyway.
      final lastInboundAt = _resolveLastInboundAt(
        null,
        chatProvider.messagesForConversation(widget.conversation.id),
      );
      if (!_isWhatsAppServiceWindowOpen(lastInboundAt)) {
        _showWhatsAppTemplatePicker(pendingText: pendingText);
        return;
      }
      // Warm the contact future so _dispatchWhatsAppSend below doesn't pay
      // the lookup cost serially.
      unawaited(_getWhatsAppContactFuture());
    }

    if (_isMetaConversation) {
      if (!chatProvider.hasCompleteMetaConversationStateSnapshot(
        widget.conversation.id,
      )) {
        unawaited(
          chatProvider.refreshMetaConversationState(widget.conversation.id),
        );
        _showErrorSnackBar(
          context,
          chatProvider.metaConversationStateError(widget.conversation.id) ??
              'Espera mientras verificamos el estado autorizado por Meta.',
        );
        return;
      }
      if (!chatProvider.canReplyToMetaConversation(widget.conversation.id)) {
        _showMetaReplyWindowClosed();
        return;
      }
    }

    _replyToMessage = null;
    _messageController.clear();
    _restoreComposerFocus();
    setState(() {
      _isSendingMessage = true;
      _isEmojiPickerOpen = false;
    });

    try {
      if (!_isWhatsAppConversation && !_isMetaConversation) {
        await chatProvider.sendMessage(
          pendingText,
          conversationId: conversationId,
          metadata: messageMetadata.isEmpty ? null : messageMetadata,
          threadRootMessageId: threadRootMessageId,
        );
        if (!mounted || widget.conversation.id != conversationId) {
          return;
        }
        if (threadRootMessageId != null && _alsoSendThreadReplyToChannel) {
          setState(() => _alsoSendThreadReplyToChannel = false);
        }
        return;
      }

      if (_isMetaConversation) {
        final sendStartedAt = DateTime.now();
        final optimisticMessageId =
            'temp-meta-${sendStartedAt.microsecondsSinceEpoch}';
        chatProvider.addOptimisticMessage(
          Message(
            id: optimisticMessageId,
            conversationId: widget.conversation.id,
            senderId: _messagingService.currentUserId,
            content: pendingText,
            type: 'text',
            metadata: {
              ...messageMetadata,
              'channel': widget.conversation.channel,
              'provider': widget.conversation.channel,
              'external_provider': widget.conversation.channel,
              'pending': true,
              'client_message_id': optimisticMessageId,
            },
            createdAt: sendStartedAt,
            isMe: true,
          ),
        );

        if (mounted) setState(() => _isSendingMessage = false);
        unawaited(
          _dispatchMetaSend(
            chatProvider: chatProvider,
            composerSession: composerSession,
            optimisticMessageId: optimisticMessageId,
            pendingText: pendingText,
            messageMetadata: messageMetadata,
            conversationId: widget.conversation.id,
          ),
        );
        return;
      }

      final sendStartedAt = DateTime.now();
      final optimisticMessageId =
          'temp-wa-${sendStartedAt.microsecondsSinceEpoch}';
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
      final dispatchContext = context;
      final dispatchConversationId = widget.conversation.id;
      final dispatchContextType = _effectiveContextType;
      final dispatchContextId = _effectiveContextId;
      final contactFuture = _getWhatsAppContactFuture();
      final messageSnapshot = chatProvider.messagesForConversation(
        dispatchConversationId,
      );
      unawaited(_dispatchWhatsAppSend(
        chatProvider: chatProvider,
        composerSession: composerSession,
        optimisticMessageId: optimisticMessageId,
        pendingText: pendingText,
        messageMetadata: messageMetadata,
        reply: reply,
        sendStartedAt: sendStartedAt,
        fallbackContext: dispatchContext,
        conversationId: dispatchConversationId,
        isSupplierConversation: widget.conversation.isSupplierConversation,
        contextType: dispatchContextType,
        contextId: dispatchContextId,
        contactFuture: contactFuture,
        messageSnapshot: messageSnapshot,
      ));
      return;
    } catch (e) {
      _restoreFailedDraft(
          chatProvider, conversationId, pendingText, reply, composerSession);
      if (!mounted || widget.conversation.id != conversationId) return;
      _restoreComposerFocus();
      _showErrorSnackBar(context, 'No se pudo enviar el mensaje: $e');
    } finally {
      if (mounted &&
          widget.conversation.id == conversationId &&
          _isSendingMessage) {
        setState(() => _isSendingMessage = false);
      }
    }
  }

  void _showMetaReplyWindowClosed() {
    if (!mounted) return;
    _showErrorSnackBar(
      context,
      'La ventana de respuesta de 24 horas está cerrada. Podrás responder cuando el cliente vuelva a escribir por ${widget.conversation.shortChannelLabel}.',
    );
  }

  Future<void> _dispatchMetaSend({
    required ChatProvider chatProvider,
    required int composerSession,
    required String optimisticMessageId,
    required String pendingText,
    required Map<String, dynamic> messageMetadata,
    required String conversationId,
  }) async {
    final receipt = await _metaMessagingService.sendText(
      conversationId: conversationId,
      message: pendingText,
      clientMessageId: optimisticMessageId,
      metadata: messageMetadata,
    );

    switch (receipt.outcome) {
      case MetaSendOutcome.accepted:
        chatProvider.updateMessageById(
          optimisticMessageId,
          metadataUpdates: {
            'pending': false,
            'server_ack_durable': true,
            'server_message_id': receipt.messageId,
            'external_status': receipt.externalStatus ?? 'accepted',
            'external_message_id': receipt.externalMessageId,
            if (receipt.attemptId != null)
              'provider_attempt_id': receipt.attemptId,
          },
        );
        break;
      case MetaSendOutcome.outcomeUnknown:
        chatProvider.updateMessageMetadataById(
          optimisticMessageId,
          {
            'pending': false,
            'external_status': 'outcome_unknown',
            'meta_status': 'outcome_unknown',
            'outcome_unknown': true,
            'retry_disabled': true,
            'server_ack_optimistic': false,
            if (receipt.attemptId != null)
              'provider_attempt_id': receipt.attemptId,
            if (receipt.messageId != null)
              'server_message_id': receipt.messageId,
            if (receipt.externalMessageId != null)
              'external_message_id': receipt.externalMessageId,
          },
        );
        if (mounted && widget.conversation.id == conversationId) {
          _showErrorSnackBar(
            context,
            'Resultado incierto: verifica la conversación antes de reenviar.',
          );
        }
        break;
      case MetaSendOutcome.rejected:
        final errorMessage = receipt.replyWindowClosed
            ? 'La ventana de respuesta de 24 horas se cerró antes del envío.'
            : receipt.errorMessage?.trim().isNotEmpty == true
                ? receipt.errorMessage!.trim()
                : 'El canal Meta rechazó el mensaje.';
        chatProvider.updateMessageMetadataById(
          optimisticMessageId,
          {
            'pending': false,
            'external_status': 'failed',
            'server_ack_optimistic': false,
            if (receipt.attemptId != null)
              'provider_attempt_id': receipt.attemptId,
            if (receipt.errorCode != null)
              'external_error_code': receipt.errorCode,
            'external_error_message': errorMessage,
          },
        );
        _restoreFailedDraft(
            chatProvider, conversationId, pendingText, null, composerSession);
        if (mounted && widget.conversation.id == conversationId) {
          _restoreComposerFocus();
          _showErrorSnackBar(context, errorMessage);
        }
        break;
    }
  }

  Future<void> _dispatchWhatsAppSend({
    required ChatProvider chatProvider,
    required int composerSession,
    required String optimisticMessageId,
    required String pendingText,
    required Map<String, dynamic> messageMetadata,
    required MessageReply? reply,
    required DateTime sendStartedAt,
    required BuildContext fallbackContext,
    required String conversationId,
    required bool isSupplierConversation,
    required String? contextType,
    required String? contextId,
    required Future<Map<String, dynamic>?> contactFuture,
    required List<Message> messageSnapshot,
  }) async {
    final whatsappService = WhatsAppService();
    try {
      final contactWaitStartedAt = DateTime.now();
      final contact = await contactFuture;
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
        messageSnapshot,
      );

      if (phone == null || phone.isEmpty) {
        _debugLogWhatsAppSend(
          optimisticMessageId,
          'failed_no_phone',
          sendStartedAt,
        );
        chatProvider.removeMessageById(optimisticMessageId);
        _restoreFailedDraft(
            chatProvider, conversationId, pendingText, reply, composerSession);
        if (mounted && widget.conversation.id == conversationId) {
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

      final receipt = await whatsappService.sendMessage(
        context: fallbackContext.mounted ? fallbackContext : null,
        customerPhone: phone,
        message: pendingText,
        contactName: contact?['name']?.toString(),
        templateContactName: contact?['template_contact_name']?.toString(),
        isSupplierConversation: isSupplierConversation,
        conversationId: conversationId,
        contextType: contextType,
        contextId: contextId,
        lastInboundAt: lastInboundAt,
        clientMessageId: optimisticMessageId,
        metadata: messageMetadata,
        replyToMessageId: reply?.externalMessageId,
      );
      _debugLogWhatsAppSend(
        optimisticMessageId,
        'cloud_request_done',
        sendStartedAt,
        {
          'success': receipt.isSuccess,
          'delivery': receipt.deliveryMethod.name,
          'external': receipt.externalMessageId,
          'error': receipt.errorCode,
        },
      );

      if (!receipt.isSuccess) {
        if (receipt.unsafeToFallback) {
          chatProvider.updateMessageMetadataById(
            optimisticMessageId,
            {
              'pending': false,
              'external_status': 'outcome_unknown',
              'whatsapp_status': 'outcome_unknown',
              'outcome_unknown': true,
              'retry_disabled': true,
              'server_ack_optimistic': false,
              if (receipt.messageId != null)
                'server_message_id': receipt.messageId,
              if (receipt.externalMessageId != null)
                'external_message_id': receipt.externalMessageId,
            },
          );
          // Keep the optimistic row: the active realtime subscription can
          // still reconcile a late durable/provider receipt.
          if (mounted && widget.conversation.id == conversationId) {
            _showErrorSnackBar(
              context,
              'Resultado incierto: verifica la conversación antes de reenviar.',
            );
          }
          return;
        }
        _debugLogWhatsAppSend(
          optimisticMessageId,
          'failed_cloud_or_fallback',
          sendStartedAt,
          {
            'delivery': receipt.deliveryMethod.name,
            'error': receipt.errorCode,
          },
        );
        chatProvider.updateMessageMetadataById(
          optimisticMessageId,
          {
            'pending': false,
            'external_status': 'failed',
            'server_ack_optimistic': false,
            if (receipt.messageId != null)
              'server_message_id': receipt.messageId,
            if (receipt.externalMessageId != null)
              'external_message_id': receipt.externalMessageId,
            'whatsapp_status_payload': {
              'errors': [
                {
                  'message': receipt.errorRequiresServerFix
                      ? 'Meta rechazó el envío porque el token de WhatsApp Cloud API expiró. Hay que actualizar WHATSAPP_ACCESS_TOKEN en Supabase.'
                      : 'No se pudo enviar el mensaje por WhatsApp',
                },
              ],
            },
          },
        );
        _restoreFailedDraft(
            chatProvider, conversationId, pendingText, reply, composerSession);
        if (mounted && widget.conversation.id == conversationId) {
          final errorMessage = receipt.errorRequiresServerFix
              ? 'Meta rechazó el envío porque el token de WhatsApp Cloud API expiró. Hay que actualizar WHATSAPP_ACCESS_TOKEN en Supabase.'
              : 'No se pudo enviar el mensaje por WhatsApp';
          _showErrorSnackBar(context, errorMessage);
        }
        return;
      }

      if (receipt.deliveryMethod == WhatsAppDeliveryMethod.cloudApi) {
        if (receipt.usedFirstContactTemplate) {
          _restoreFailedDraft(chatProvider, conversationId, pendingText, reply,
              composerSession);
          chatProvider.setConversationDraft(
            conversationId,
            pendingText,
            title: 'Mensaje pendiente de ventana WhatsApp',
            subtitle:
                'El mensaje autorizado quedó registrado. Cuando el ${isSupplierConversation ? 'proveedor' : 'cliente'} responda, puedes enviar este texto libre.',
          );
        } else {
          chatProvider.clearConversationDraft(conversationId);
        }
        chatProvider.updateMessageById(
          optimisticMessageId,
          content: receipt.resolvedMessageText ?? pendingText,
          metadataUpdates: {
            // Database acceptance and provider acceptance are distinct receipts.
            'pending': false,
            'server_ack_durable': true,
            'server_message_id': receipt.messageId,
            'external_status': receipt.externalStatus,
            'external_message_id': receipt.externalMessageId,
            if (receipt.deliveryStrategy != null)
              'delivery_strategy': receipt.deliveryStrategy,
            if (receipt.usedFirstContactTemplate) 'template_used': true,
          },
        );
        _debugLogWhatsAppSend(
          optimisticMessageId,
          'cloud_ack_confirmed',
          sendStartedAt,
          {
            'external': receipt.externalMessageId,
            'template': receipt.usedFirstContactTemplate,
          },
        );

        if (receipt.usedFirstContactTemplate &&
            mounted &&
            widget.conversation.id == conversationId) {
          _showWhatsAppResultSnackbar(
            context: context,
            deliveryMethod: receipt.deliveryMethod,
            successMessage:
                'Mensaje autorizado registrado para abrir o reabrir WhatsApp.',
            fallbackMessage: 'WhatsApp abierto con el mensaje prellenado',
          );
        }
      } else if (receipt.deliveryMethod ==
          WhatsAppDeliveryMethod.manualFallback) {
        chatProvider.removeMessageById(optimisticMessageId);
        _restoreFailedDraft(
            chatProvider, conversationId, pendingText, reply, composerSession);
        if (mounted && widget.conversation.id == conversationId) {
          _showWhatsAppResultSnackbar(
            context: context,
            deliveryMethod: receipt.deliveryMethod,
            successMessage: 'Mensaje enviado por WhatsApp Cloud API',
            fallbackMessage: 'WhatsApp abierto con el mensaje prellenado',
          );
        }
      }
    } catch (e) {
      chatProvider.removeMessageById(optimisticMessageId);
      _restoreFailedDraft(
          chatProvider, conversationId, pendingText, reply, composerSession);
      if (mounted && widget.conversation.id == conversationId) {
        _showErrorSnackBar(context, 'No se pudo enviar el mensaje: $e');
      }
    }
  }

  void _restoreComposerFocus({TextSelection? selection}) {
    // On Web, post-frame callback isn't always enough due to engine/DOM sync.
    // A small delay ensures the focus request happens after the UI settles.
    final conversationId = widget.conversation.id;
    _composerFocusTimer?.cancel();
    _composerFocusTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted && widget.conversation.id == conversationId) {
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
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Chat aceptado. Ahora puedes responder.'),
            backgroundColor: VinabikeThemeRoles.of(context).success.accent,
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: VinabikeThemeRoles.of(context).danger.accent),
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
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Solicitud rechazada'),
                      backgroundColor:
                          VinabikeThemeRoles.of(context).warning.accent,
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor:
                            VinabikeThemeRoles.of(context).danger.accent),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
                backgroundColor: VinabikeThemeRoles.of(context).danger.accent),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
  }

  void _showAttachmentOptions({GlobalKey? anchorKey}) {
    _toggleComposerMenu(
      name: 'attachments',
      anchorKey: anchorKey ?? _composerActionsButtonKey,
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

  /// Pick files into the composer preview before sending.
  Future<void> _pickAndSendFile(String choice) async {
    if (!mounted) return;
    if (_guardPendingAttachmentMutation()) return;
    final conversationId = widget.conversation.id;
    final session = _composerSession;

    try {
      if (choice == 'camera') {
        final picker = ImagePicker();
        final XFile? pickedFile = await picker.pickImage(
          source: ImageSource.camera,
        );
        if (pickedFile == null ||
            !_isCurrentComposer(conversationId, session)) {
          return;
        }
        await _queueXFiles([pickedFile]);
      } else if (choice == 'gallery') {
        final picker = ImagePicker();
        final pickedFiles = await picker.pickMultiImage();
        if (pickedFiles.isEmpty ||
            !_isCurrentComposer(conversationId, session)) {
          return;
        }
        await _queueXFiles(pickedFiles);
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowMultiple: true,
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
            'gif',
            'webp',
            'mp4',
            '3gp',
            'mp3',
            'ogg',
            'm4a',
            'aac',
          ],
          withData: true,
        );
        if (result == null ||
            result.files.isEmpty ||
            !_isCurrentComposer(conversationId, session)) return;
        final attachments = <PendingChatAttachment>[];
        for (final file in result.files.take(
          MessagingAttachmentService.maxAttachmentsPerBatch,
        )) {
          MessagingAttachmentService.validateBeforeRead(
            fileName: file.name,
            sizeBytes: file.size,
          );
          final pickedBytes = file.bytes;
          if (pickedBytes == null || pickedBytes.isEmpty) continue;
          attachments.add(
            _buildPendingAttachment(
              fileName: file.name,
              bytes: pickedBytes,
            ),
          );
        }
        _addPendingAttachments(attachments);
      }
    } catch (e) {
      if (!_isCurrentComposer(conversationId, session)) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error al preparar archivo: $e'),
            backgroundColor: VinabikeThemeRoles.of(context).danger.accent),
      );
    }
  }

  Future<void> _queueDroppedFiles(List<XFile> files) async {
    if (files.isEmpty) return;

    setState(() {
      _isDraggingAttachment = false;
    });
    if (_guardPendingAttachmentMutation()) return;

    await _queueXFiles(files);
  }

  Future<void> _queueXFiles(List<XFile> files) async {
    if (_guardPendingAttachmentMutation()) return;
    final conversationId = widget.conversation.id;
    final session = _composerSession;
    final attachments = <PendingChatAttachment>[];
    for (final file in files.take(
      MessagingAttachmentService.maxAttachmentsPerBatch,
    )) {
      try {
        final fileName = _droppedFileName(file);
        final sizeBytes = await file.length();
        MessagingAttachmentService.validateBeforeRead(
          fileName: fileName,
          sizeBytes: sizeBytes,
        );
        final bytes = await file.readAsBytes();
        if (!_isCurrentComposer(conversationId, session)) return;
        if (bytes.isEmpty) continue;
        attachments.add(
          _buildPendingAttachment(
            fileName: fileName,
            bytes: bytes,
          ),
        );
      } catch (e) {
        if (!_isCurrentComposer(conversationId, session)) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo preparar ${_droppedFileName(file)}: $e'),
            backgroundColor: VinabikeThemeRoles.of(context).danger.accent,
          ),
        );
      }
    }

    _addPendingAttachments(attachments);
  }

  void _addPendingAttachments(List<PendingChatAttachment> attachments) {
    if (attachments.isEmpty || !mounted) return;
    if (_guardPendingAttachmentMutation()) return;
    final available = MessagingAttachmentService.maxAttachmentsPerBatch -
        _pendingAttachments.length;
    if (available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Puedes enviar hasta 8 adjuntos por vez.')),
      );
      return;
    }
    setState(() {
      _pendingAttachments.addAll(attachments.take(available));
      _isEmojiPickerOpen = false;
    });
    _restoreComposerFocus();
  }

  PendingChatAttachment _buildPendingAttachment({
    required String fileName,
    required Uint8List bytes,
    String? purchaseInvoiceId,
    String? purchaseInvoiceNumber,
  }) {
    final validation = MessagingAttachmentService.validateBeforeRead(
      fileName: fileName,
      sizeBytes: bytes.length,
    );
    final ext = validation.extension;
    final isImage = validation.contentType.startsWith('image/');
    _pendingAttachmentSerial += 1;
    return PendingChatAttachment(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}-$_pendingAttachmentSerial',
      fileName: fileName.trim().isEmpty ? 'archivo' : fileName.trim(),
      bytes: bytes,
      extension: ext,
      isImage: isImage,
      purchaseInvoiceId: purchaseInvoiceId,
      purchaseInvoiceNumber: purchaseInvoiceNumber,
    );
  }

  void _removePendingAttachment(String id) {
    final attachment =
        _pendingAttachments.cast<PendingChatAttachment?>().firstWhere(
              (item) => item?.id == id,
              orElse: () => null,
            );
    if (attachment?.outcomeUnknown == true &&
        attachment?.canRetrySafely == false) {
      _showPendingAttachmentMutationBlocked();
      return;
    }
    setState(() {
      _pendingAttachments.removeWhere((attachment) => attachment.id == id);
    });
    _restoreComposerFocus();
  }

  void _clearPendingAttachments() {
    if (_guardPendingAttachmentMutation()) return;
    setState(() => _pendingAttachments.clear());
    _restoreComposerFocus();
  }

  Future<void> _sendComposer() async {
    if (_hasBlockingOutcomeUnknownAttachment) {
      _showPendingAttachmentMutationBlocked();
      return;
    }
    if (_pendingAttachments.isNotEmpty) {
      await _sendPendingAttachments();
      return;
    }
    await _sendMessage();
  }

  Future<void> _sendPendingAttachments() async {
    if (_pendingAttachments.isEmpty || _isSendingPendingAttachments) return;
    if (!_supportsOutgoingAttachments) {
      _showErrorSnackBar(
        context,
        'Los adjuntos aún no están habilitados para ${widget.conversation.shortChannelLabel}.',
      );
      return;
    }
    if (_guardPendingAttachmentMutation()) return;

    final caption = _messageController.text.trim();
    final conversationId = widget.conversation.id;
    final reply = _replyToMessage;
    final attachments = List<PendingChatAttachment>.from(_pendingAttachments);
    if (reply != null && !attachments.first.outcomeUnknown) {
      attachments[0] = attachments.first.withReply(reply);
    }
    final chatProvider = context.read<ChatProvider>();
    final composerSession = chatProvider.composerSession;
    final purchaseService = attachments.any((a) => a.purchaseInvoiceId != null)
        ? context.read<PurchaseService>()
        : null;

    // Like WhatsApp: the composer is free the moment «enviar» is pressed and
    // every file is already a bubble, drawn from the bytes on this device.
    // The upload and the provider's answer update that bubble; a rejection
    // brings the file back into the composer with its reason.
    setState(() {
      _isSendingPendingAttachments = true;
      _pendingAttachments.clear();
      _replyToMessage = null;
      _messageController.clear();
    });
    _restoreComposerFocus();

    _saveAttachmentDraft(conversationId);
    final optimisticIds = <String, String>{};
    for (var i = 0; i < attachments.length; i += 1) {
      final attachment = attachments[i];
      final optimisticId = _seedOptimisticAttachment(
        chatProvider,
        attachment,
        caption: attachment.outcomeUnknown
            ? attachment.replayCaption
            : i == 0 && caption.isNotEmpty
                ? caption
                : null,
      );
      if (optimisticId != null) optimisticIds[attachment.id] = optimisticId;
    }

    final unresolved = <PendingChatAttachment>[];
    final confirmedPurchaseDocuments = <PendingChatAttachment>[];
    var rejectedCount = 0;
    var unknownCount = 0;
    var confirmedCount = 0;
    for (var i = 0; i < attachments.length; i += 1) {
      final attachment = attachments[i];
      final optimisticId = optimisticIds[attachment.id];
      // Navigation never retargets the rest of a batch to the new recipient.
      if (!mounted ||
          widget.conversation.id != conversationId ||
          chatProvider.composerSession != composerSession) {
        for (final skipped in attachments.skip(i)) {
          final skippedId = optimisticIds[skipped.id];
          if (skippedId != null) chatProvider.removeMessageById(skippedId);
          unresolved.add(skipped);
        }
        break;
      }
      final result = await _sendAttachmentBytes(
        fileName: attachment.fileName,
        bytes: attachment.bytes,
        showUploadingSnackBar: false,
        caption: attachment.outcomeUnknown
            ? attachment.replayCaption
            : i == 0 && caption.isNotEmpty
                ? caption
                : null,
        existingReservation: attachment.reservation,
        retryUpload: attachment.retryUpload,
        optimisticMessageId: optimisticId,
        localMediaKey: attachment.id,
        durationSeconds: attachment.durationSeconds,
        reply: attachment.reply,
      );
      switch (result.outcome) {
        case AttachmentDispatchOutcome.confirmed:
          confirmedCount += 1;
          if (attachment.purchaseInvoiceId != null) {
            confirmedPurchaseDocuments.add(attachment);
          }
          break;
        case AttachmentDispatchOutcome.rejected:
          // A confirmed rejection can start over with a fresh reservation on
          // the next explicit user attempt. Never reuse the failed row.
          if (optimisticId != null)
            chatProvider.removeMessageById(optimisticId);
          unresolved.add(attachment.resetForNewAttempt());
          rejectedCount += 1;
          break;
        case AttachmentDispatchOutcome.outcomeUnknown:
          if (optimisticId != null) {
            chatProvider.updateMessageMetadataById(optimisticId, {
              'pending': false,
              'outcome_unknown': true,
            });
          }
          unresolved.add(attachment.markOutcomeUnknown(result));
          // Stop the batch after an ambiguous provider result. The remaining
          // files were never attempted and stay in the composer. A native
          // attachment keeps its exact reservation for an idempotent replay;
          // provider sends remain blocked from blind retries.
          for (final skipped in attachments.skip(i + 1)) {
            final skippedId = optimisticIds[skipped.id];
            if (skippedId != null) chatProvider.removeMessageById(skippedId);
            unresolved.add(skipped);
          }
          unknownCount += 1;
          break;
      }
      if (result.outcome == AttachmentDispatchOutcome.outcomeUnknown) break;
    }

    if (purchaseService != null) {
      await _markPurchaseDocumentsAsSent(confirmedPurchaseDocuments,
          purchaseService: purchaseService, conversationId: conversationId);
    }
    if (chatProvider.composerSession != composerSession) return;
    if (!mounted || widget.conversation.id != conversationId) {
      if (unresolved.isNotEmpty) {
        chatProvider.saveComposerAttachments(
            conversationId,
            [
              ...chatProvider.getComposerAttachments(conversationId),
              ...unresolved
            ],
            session: composerSession);
        if (confirmedCount == 0)
          _restoreFailedDraft(
              chatProvider, conversationId, caption, reply, composerSession);
      }
      return;
    }
    setState(() {
      _isSendingPendingAttachments = false;
      _pendingAttachments.addAll(unresolved);
      if (unresolved.isNotEmpty &&
          confirmedCount == 0 &&
          _replyToMessage == null) {
        _replyToMessage = reply;
      }
      if (unresolved.isNotEmpty &&
          confirmedCount == 0 &&
          caption.isNotEmpty &&
          _messageController.text.trim().isEmpty) {
        _messageController.text = caption;
      }
    });

    if (unresolved.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(unknownCount > 0
              ? unresolved.any(
                  (attachment) =>
                      attachment.outcomeUnknown && attachment.canRetrySafely,
                )
                  ? 'No llegó la confirmación. El adjunto conserva su reserva y puede reintentarse sin duplicarlo.'
                  : 'Hay $unknownCount adjunto(s) con resultado incierto. Verifica antes de quitarlos o reenviar.'
              : rejectedCount == 1
                  ? 'No se pudo enviar 1 adjunto.'
                  : 'No se pudieron enviar $rejectedCount adjuntos.'),
          backgroundColor: unknownCount > 0
              ? null
              : VinabikeThemeRoles.of(context).danger.accent,
        ),
      );
    }
  }

  /// The bubble a file gets before anything has been uploaded. Its bytes go
  /// into the device cache under the composer's key, so the thumbnail is
  /// full on the first frame and the same bytes serve the server row later.
  /// Returns `null` when the file cannot be sent at all (the send path then
  /// reports the reason).
  String? _seedOptimisticAttachment(
    ChatProvider chatProvider,
    PendingChatAttachment attachment, {
    String? caption,
  }) {
    if (attachment.outcomeUnknown) return null;
    final MessagingAttachmentValidation validation;
    try {
      validation = MessagingAttachmentService.validateBeforeRead(
        fileName: attachment.fileName,
        sizeBytes: attachment.bytes.length,
      );
    } catch (_) {
      return null;
    }
    _pendingAttachmentSerial += 1;
    final optimisticId =
        'temp-file-${DateTime.now().microsecondsSinceEpoch}-$_pendingAttachmentSerial';
    final isImage = validation.contentType.startsWith('image/');
    final isAudio = validation.contentType.startsWith('audio/');
    final cleanCaption = caption?.trim();
    unawaited(
      ChatMediaCache.instance.put(
        'local:${attachment.id}',
        attachment.bytes,
        fileExtension: attachment.extension,
      ),
    );
    chatProvider.addOptimisticMessage(
      Message(
        id: optimisticId,
        conversationId: widget.conversation.id,
        senderId: _messagingService.currentUserId,
        content: cleanCaption?.isNotEmpty == true
            ? cleanCaption!
            : attachment.fileName,
        type: isAudio
            ? 'audio'
            : isImage
                ? 'image'
                : 'file',
        metadata: {
          'pending': true,
          if (attachment.reply != null) 'reply_to': attachment.reply!.toJson(),
          'client_message_id': optimisticId,
          'local_media_key': attachment.id,
          'filename': attachment.fileName,
          'extension': attachment.extension,
          'content_type': validation.contentType,
          if (attachment.durationSeconds != null)
            'duration_seconds': attachment.durationSeconds,
          if (cleanCaption != null && cleanCaption.isNotEmpty)
            'caption': cleanCaption,
          if (_isWhatsAppConversation) ...{
            'channel': 'whatsapp',
            'provider': 'whatsapp',
          },
          if (_activeThreadRootMessageId != null)
            'thread_root_message_id': _activeThreadRootMessageId,
        },
        createdAt: DateTime.now(),
        isMe: true,
      ),
    );
    return optimisticId;
  }

  String _droppedFileName(XFile file) {
    final rawName = file.name.trim();
    if (rawName.isNotEmpty) return rawName;
    final pathName = file.path.trim().split(RegExp(r'[\\/]')).last;
    if (pathName.isNotEmpty) return pathName;
    return 'archivo';
  }

  Future<AttachmentDispatchResult> _sendAttachmentBytes({
    required String fileName,
    required Uint8List bytes,
    bool showUploadingSnackBar = true,
    String? caption,
    ReservedMessagingAttachment? existingReservation,
    bool retryUpload = false,
    String? optimisticMessageId,
    String? localMediaKey,
    int? durationSeconds,
    MessageReply? reply,
  }) async {
    if (!mounted || bytes.isEmpty) {
      return const AttachmentDispatchResult.rejected();
    }
    if (!_supportsOutgoingAttachments) {
      _showErrorSnackBar(
        context,
        'Los adjuntos aún no están habilitados para ${widget.conversation.shortChannelLabel}.',
      );
      return const AttachmentDispatchResult.rejected();
    }

    final fallbackContext = context;
    final conversationId = widget.conversation.id;
    final threadRootMessageId = _activeThreadRootMessageId;
    final isWhatsAppConversation = _isWhatsAppConversation;
    final chatProvider = context.read<ChatProvider>();
    final contextType = _effectiveContextType;
    final contextId = _effectiveContextId;
    final contactFuture =
        isWhatsAppConversation ? _getWhatsAppContactFuture() : null;
    final cleanCaption = caption?.trim();
    final MessagingAttachmentValidation validation;
    try {
      validation = MessagingAttachmentService.validateBeforeRead(
        fileName: fileName,
        sizeBytes: bytes.length,
      );
    } catch (error) {
      _showErrorSnackBar(context, 'No se puede adjuntar el archivo: $error');
      return const AttachmentDispatchResult.rejected();
    }

    if (showUploadingSnackBar) {
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
    }

    ReservedMessagingAttachment reservation;
    if (existingReservation != null) {
      final reservationMatches =
          existingReservation.conversationId == conversationId &&
              existingReservation.sizeBytes == bytes.length &&
              existingReservation.contentType == validation.contentType;
      if (!reservationMatches) {
        if (showUploadingSnackBar && fallbackContext.mounted) {
          ScaffoldMessenger.of(fallbackContext).hideCurrentSnackBar();
        }
        _showErrorSnackBar(
          context,
          'La reserva del adjunto ya no coincide con esta conversación.',
        );
        return const AttachmentDispatchResult.rejected();
      }
      reservation = existingReservation;
    } else {
      try {
        reservation = await _messagingAttachmentService.reserve(
          conversationId: conversationId,
          fileName: fileName,
          sizeBytes: bytes.length,
        );
      } catch (error) {
        if (showUploadingSnackBar && fallbackContext.mounted) {
          ScaffoldMessenger.of(fallbackContext).hideCurrentSnackBar();
        }
        if (mounted && widget.conversation.id == conversationId) {
          _showErrorSnackBar(
            context,
            'No se pudo reservar el adjunto: $error',
          );
        }
        return const AttachmentDispatchResult.rejected();
      }
    }

    // The bytes this device is about to upload are the bytes it will be
    // asked to show under the server's path: keep them, never re-download.
    unawaited(
      ChatMediaCache.instance.put(
        'path:${reservation.path}',
        bytes,
        fileExtension: reservation.extension,
      ),
    );
    if (optimisticMessageId != null) {
      chatProvider.updateMessageMetadataById(
        optimisticMessageId,
        {
          ...reservation.messageMetadata,
          if (localMediaKey != null) 'local_media_key': localMediaKey,
        },
      );
    }

    if (existingReservation == null || retryUpload) {
      try {
        await _messagingAttachmentService.upload(
          reservation,
          bytes,
          acceptExistingObject: existingReservation != null,
        );
      } catch (error) {
        if (showUploadingSnackBar && fallbackContext.mounted) {
          ScaffoldMessenger.of(fallbackContext).hideCurrentSnackBar();
        }
        if (MessagingAttachmentService.isUploadOutcomeAmbiguous(error)) {
          if (mounted && widget.conversation.id == conversationId) {
            _showErrorSnackBar(
              context,
              'No llegó la confirmación de carga. Se conserva la misma reserva para un reintento seguro.',
            );
          }
          return AttachmentDispatchResult.outcomeUnknown(
            reservation: reservation,
            retryUpload: true,
            canRetrySafely: !isWhatsAppConversation,
            replayCaption: cleanCaption,
          );
        }
        await _messagingAttachmentService.fail(
          reservation,
          code: 'flutter_upload_rejected',
        );
        if (mounted && widget.conversation.id == conversationId) {
          _showErrorSnackBar(context, 'La carga del adjunto fue rechazada.');
        }
        return const AttachmentDispatchResult.rejected();
      }
    }

    if (showUploadingSnackBar && fallbackContext.mounted) {
      ScaffoldMessenger.of(fallbackContext).hideCurrentSnackBar();
    }

    final msgType = validation.contentType.startsWith('image/')
        ? 'image'
        : validation.contentType.startsWith('audio/')
            ? 'audio'
            : 'file';
    final metadata = {
      ...reservation.messageMetadata,
      if (reply != null) 'reply_to': reply.toJson(),
      if (cleanCaption != null && cleanCaption.isNotEmpty)
        'caption': cleanCaption,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
    };

    if (isWhatsAppConversation) {
      final outcome = await _sendWhatsAppAttachment(
        chatProvider: chatProvider,
        reservation: reservation,
        fileName: fileName,
        messageType: msgType,
        metadata: metadata,
        caption: cleanCaption,
        existingOptimisticMessageId: optimisticMessageId,
        fallbackContext: fallbackContext.mounted ? fallbackContext : null,
        conversationId: conversationId,
        contextType: contextType,
        contextId: contextId,
        contactFuture: contactFuture!,
      );
      switch (outcome) {
        case AttachmentDispatchOutcome.confirmed:
          return const AttachmentDispatchResult.confirmed();
        case AttachmentDispatchOutcome.rejected:
          return const AttachmentDispatchResult.rejected();
        case AttachmentDispatchOutcome.outcomeUnknown:
          return AttachmentDispatchResult.outcomeUnknown(
            reservation: reservation,
            retryUpload: false,
            canRetrySafely: false,
            replayCaption: cleanCaption,
          );
      }
    }

    try {
      await _messagingAttachmentService.publish(
        reservation: reservation,
        caption: cleanCaption,
        threadRootMessageId: threadRootMessageId,
        replyToMessageId: reply?.messageId,
      );
      if (optimisticMessageId != null) {
        // The database wrote the row; realtime prunes the bubble by
        // attachment id when it arrives.
        chatProvider.updateMessageMetadataById(optimisticMessageId, {
          'pending': false,
          'server_ack_durable': true,
        });
      }
      return const AttachmentDispatchResult.confirmed();
    } on MessagingAttachmentPublishOutcomeUnknown {
      if (mounted && widget.conversation.id == conversationId) {
        _showErrorSnackBar(
          context,
          'No llegó la confirmación de envío. El adjunto conserva su reserva y puede reintentarse sin duplicarlo.',
        );
      }
      return AttachmentDispatchResult.outcomeUnknown(
        reservation: reservation,
        retryUpload: false,
        canRetrySafely: true,
        replayCaption: cleanCaption,
      );
    } on MessagingAttachmentPublishRejected catch (error) {
      await _messagingAttachmentService.fail(
        reservation,
        code: error.failureCode,
      );
      if (mounted && widget.conversation.id == conversationId) {
        _showErrorSnackBar(context, 'El envío del adjunto fue rechazado.');
      }
      return const AttachmentDispatchResult.rejected();
    } catch (_) {
      // A non-contract exception after publish started is never evidence that
      // the transaction rolled back. Preserve the reservation for read-back
      // or exact replay instead of failing/deleting it.
      return AttachmentDispatchResult.outcomeUnknown(
        reservation: reservation,
        retryUpload: false,
        canRetrySafely: true,
        replayCaption: cleanCaption,
      );
    }
  }

  Future<AttachmentDispatchOutcome> _sendWhatsAppAttachment({
    required ChatProvider chatProvider,
    required ReservedMessagingAttachment reservation,
    required String fileName,
    required String messageType,
    required Map<String, dynamic> metadata,
    String? caption,
    required BuildContext? fallbackContext,
    required String conversationId,
    required String? contextType,
    required String? contextId,
    required Future<Map<String, dynamic>?> contactFuture,
    String? existingOptimisticMessageId,
  }) {
    final optimisticMessageId = existingOptimisticMessageId ??
        'temp-wa-file-${DateTime.now().microsecondsSinceEpoch}';
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
    if (existingOptimisticMessageId != null) {
      chatProvider.updateMessageMetadataById(
        optimisticMessageId,
        optimisticMetadata,
      );
    } else {
      chatProvider.addOptimisticMessage(
        Message(
          id: optimisticMessageId,
          conversationId: conversationId,
          senderId: _messagingService.currentUserId,
          content:
              caption?.trim().isNotEmpty == true ? caption!.trim() : fileName,
          type: messageType,
          metadata: optimisticMetadata,
          createdAt: DateTime.now(),
          isMe: true,
        ),
      );
    }
    return _dispatchWhatsAppAttachment(
      chatProvider: chatProvider,
      optimisticMessageId: optimisticMessageId,
      reservation: reservation,
      fileName: fileName,
      messageType: messageType,
      metadata: sendMetadata,
      caption: caption,
      fallbackContext: fallbackContext,
      conversationId: conversationId,
      contextType: contextType,
      contextId: contextId,
      contactFuture: contactFuture,
    );
  }

  Future<AttachmentDispatchOutcome> _dispatchWhatsAppAttachment({
    required ChatProvider chatProvider,
    required String optimisticMessageId,
    required ReservedMessagingAttachment reservation,
    required String fileName,
    required String messageType,
    required Map<String, dynamic> metadata,
    String? caption,
    required BuildContext? fallbackContext,
    required String conversationId,
    required String? contextType,
    required String? contextId,
    required Future<Map<String, dynamic>?> contactFuture,
  }) async {
    final whatsappService = WhatsAppService();
    try {
      final contact = await contactFuture;
      final phone = contact?['phone']?.toString();

      if (phone == null || phone.isEmpty) {
        await _messagingAttachmentService.fail(
          reservation,
          code: 'whatsapp_conversation_phone_missing',
        );
        chatProvider.removeMessageById(optimisticMessageId);
        if (mounted) {
          _showErrorSnackBar(
            context,
            'La conversación de WhatsApp no tiene un teléfono asociado.',
          );
        }
        return AttachmentDispatchOutcome.rejected;
      }

      final receipt = await whatsappService.sendAttachment(
        context: fallbackContext?.mounted == true ? fallbackContext : null,
        customerPhone: phone,
        attachmentId: reservation.id,
        filename: fileName,
        messageType: messageType,
        caption: caption,
        contactName: contact?['name']?.toString(),
        conversationId: conversationId,
        customerId: contact?['customer_id']?.toString(),
        contextType: contextType,
        contextId: contextId,
        clientMessageId: optimisticMessageId,
        metadata: metadata,
      );

      if (!receipt.isSuccess) {
        if (receipt.unsafeToFallback) {
          chatProvider.updateMessageMetadataById(
            optimisticMessageId,
            {
              'pending': false,
              'external_status': 'outcome_unknown',
              'whatsapp_status': 'outcome_unknown',
              'outcome_unknown': true,
              'retry_disabled': true,
              if (receipt.messageId != null)
                'server_message_id': receipt.messageId,
              if (receipt.externalMessageId != null)
                'external_message_id': receipt.externalMessageId,
            },
          );
          // Keep the optimistic row for realtime reconciliation.
          if (mounted) {
            _showErrorSnackBar(
              context,
              'Resultado incierto: verifica la conversación antes de reenviar el archivo.',
            );
          }
          return AttachmentDispatchOutcome.outcomeUnknown;
        }
        await _messagingAttachmentService.fail(
          reservation,
          code: 'whatsapp_send_rejected',
        );
        chatProvider.removeMessageById(optimisticMessageId);
        if (mounted) {
          final errorMessage = receipt.errorRequiresServerFix
              ? 'Meta rechazó el envío porque el token de WhatsApp Cloud API expiró. Hay que actualizar WHATSAPP_ACCESS_TOKEN en Supabase.'
              : receipt.errorRequiresCustomerReply
                  ? 'Meta no permite enviar archivos fuera de la ventana de 24 horas. Envía primero un mensaje autorizado y espera la respuesta antes de compartir la imagen.'
                  : 'No se pudo enviar el archivo por WhatsApp';
          _showErrorSnackBar(context, errorMessage);
        }
        return AttachmentDispatchOutcome.rejected;
      }

      if (receipt.deliveryMethod == WhatsAppDeliveryMethod.cloudApi) {
        chatProvider.updateMessageById(
          optimisticMessageId,
          metadataUpdates: {
            // The durable queue can acknowledge before Meta receives the file.
            'pending': false,
            'server_ack_durable': true,
            'server_message_id': receipt.messageId,
            'external_status': receipt.externalStatus,
            'external_message_id': receipt.externalMessageId,
          },
        );
      } else if (receipt.deliveryMethod ==
          WhatsAppDeliveryMethod.manualFallback) {
        chatProvider.removeMessageById(optimisticMessageId);
        if (mounted) {
          _showWhatsAppResultSnackbar(
            context: context,
            deliveryMethod: receipt.deliveryMethod,
            successMessage: 'Archivo enviado por WhatsApp Cloud API',
            fallbackMessage: 'WhatsApp abierto con el archivo como enlace',
          );
        }
      }
      return AttachmentDispatchOutcome.confirmed;
    } catch (e) {
      await _messagingAttachmentService.fail(
        reservation,
        code: 'whatsapp_send_exception',
      );
      chatProvider.removeMessageById(optimisticMessageId);
      if (mounted) {
        _showErrorSnackBar(context, 'No se pudo enviar el archivo: $e');
      }
      return AttachmentDispatchOutcome.rejected;
    }
  }

  int _replyCountForRoot(List<Message> messages, String rootMessageId) {
    return messages
        .where(
          (message) =>
              message.threadRootMessageId == rootMessageId &&
              message.type != 'system',
        )
        .length;
  }

  List<Message> _channelTimelineMessages(List<Message> messages) {
    return messages
        .where(
          (message) =>
              message.isTopLevelMessage ||
              message.metadata['also_send_to_channel'] == true,
        )
        .toList(growable: false);
  }

  Widget _buildChannelTimelineEntry(
    BuildContext context,
    Message message,
    List<Message> allMessages,
    List<Message> channelMessages,
  ) {
    final taskId = message.isTopLevelMessage ? _taskIdForRoot(message) : null;
    final rootMessageId = message.threadRootMessageId ?? message.id;
    final replyCount = _replyCountForRoot(allMessages, rootMessageId);

    if (taskId != null) {
      return _buildTaskThreadRoot(
        context,
        taskId,
        replyCount,
        fallbackTitle: message.content,
        onOpenReplies: () => _openThreadReplies(message.id),
      );
    }

    final canOpenThread = widget.conversation.isInternal &&
        message.type != 'system' &&
        message.type != 'action_request';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildMessageBubble(context, message, channelMessages),
        if (canOpenThread || replyCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 38, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey<String>('open-thread-$rootMessageId'),
                onPressed: () => _openThreadReplies(rootMessageId),
                icon: const Icon(Icons.forum_outlined, size: 14),
                label: Text(
                  message.isThreadReply
                      ? 'Respuesta en hilo · Ver conversación'
                      : replyCount == 0
                          ? 'Responder en hilo'
                          : replyCount == 1
                              ? '1 respuesta'
                              : '$replyCount respuestas',
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildThreadRootEntry(
    BuildContext context,
    Message root,
    List<Message> allMessages,
  ) {
    final taskId = _taskIdForRoot(root);
    final replyCount = _replyCountForRoot(allMessages, root.id);
    if (taskId != null) {
      return _buildTaskThreadRoot(
        context,
        taskId,
        replyCount,
        fallbackTitle: root.content,
      );
    }
    return _buildMessageBubble(context, root, <Message>[root]);
  }

  Widget _buildThreadPane(
    BuildContext context,
    ChatProvider chatProvider,
    List<Message> allMessages, {
    required bool canWriteConversation,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final rootMessageId = _activeThreadRootMessageId;
    if (rootMessageId == null) return const SizedBox.shrink();

    final matchingRoots =
        allMessages.where((message) => message.id == rootMessageId);
    final root = matchingRoots.isEmpty ? null : matchingRoots.first;
    final replies = allMessages
        .where((message) => message.threadRootMessageId == rootMessageId)
        .toList(growable: false);
    final timelineItems = _buildTimelineItems(replies);

    return ColoredBox(
      key: const ValueKey<String>('message-thread-pane'),
      color: colorScheme.surface,
      child: Column(
        children: [
          _buildTaskThreadNavigation(context, replies.length),
          Expanded(
            child: ColoredBox(
              color: _chatTimelineBackground(theme),
              child: root == null
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _threadScrollController,
                      reverse: true,
                      cacheExtent: 1600,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
                      itemCount: timelineItems.length + 1,
                      itemBuilder: (context, index) {
                        if (index < timelineItems.length) {
                          final item =
                              timelineItems[timelineItems.length - 1 - index];
                          if (item is _UnreadMessagesMarker) {
                            return const SizedBox.shrink();
                          }
                          if (item is _TimelineDaySeparator) {
                            return _buildTimelineDaySeparator(
                              context,
                              item.day,
                            );
                          }
                          return _buildMessageBubble(
                            context,
                            item as Message,
                            replies,
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildThreadRootEntry(
                              context,
                              root,
                              allMessages,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: colorScheme.outlineVariant,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      replies.length == 1
                                          ? '1 respuesta'
                                          : '${replies.length} respuestas',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: colorScheme.outlineVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
          if (canWriteConversation)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  top: BorderSide(color: colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _alsoSendThreadReplyToChannel,
                        onChanged: (value) => setState(
                          () => _alsoSendThreadReplyToChannel = value ?? false,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'También mostrar esta respuesta en el canal',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _buildComposer(context),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChannelBody(
    BuildContext context,
    ChatProvider chatProvider,
    List<Message> allMessages, {
    required bool isLoading,
    required bool canWriteConversation,
    required bool threadOpenBesideChannel,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final channelMessages = _channelTimelineMessages(allMessages);
    final timelineItems = _buildTimelineItems(channelMessages);
    final showHistoryBoundary = channelMessages.isNotEmpty ||
        chatProvider.isLoadingOlderMessages(widget.conversation.id) ||
        chatProvider.olderMessagesErrorForConversation(
              widget.conversation.id,
            ) !=
            null;

    return Column(
      children: [
        Expanded(
          child: Container(
            color: _chatTimelineBackground(theme),
            child: isLoading && allMessages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        cacheExtent: 2400,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
                        itemCount: timelineItems.length +
                            (showHistoryBoundary ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index < timelineItems.length) {
                            final item =
                                timelineItems[timelineItems.length - 1 - index];
                            if (item is _UnreadMessagesMarker) {
                              return _buildUnreadMessagesMarker(item.count);
                            }
                            if (item is _TimelineDaySeparator) {
                              return _buildTimelineDaySeparator(
                                context,
                                item.day,
                              );
                            }
                            return _buildChannelTimelineEntry(
                              context,
                              item as Message,
                              allMessages,
                              channelMessages,
                            );
                          }

                          return _buildHistoryBoundary(
                            context,
                            chatProvider,
                            hasMessages: allMessages.isNotEmpty,
                            boundaryLabel: 'Inicio del canal',
                          );
                        },
                      ),
                      Positioned(
                        right: 14,
                        bottom: 10,
                        child: IgnorePointer(
                          ignoring: !_showJumpToLatest,
                          child: AnimatedScale(
                            scale: _showJumpToLatest ? 1 : 0.82,
                            duration: const Duration(milliseconds: 150),
                            child: AnimatedOpacity(
                              opacity: _showJumpToLatest ? 1 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: Material(
                                color: colorScheme.surface,
                                elevation: 3,
                                shape: const CircleBorder(),
                                child: IconButton(
                                  tooltip: 'Ir al mensaje más reciente',
                                  onPressed: _jumpToLatest,
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (canWriteConversation && !threadOpenBesideChannel)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: _buildComposer(context),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final chatProvider = context.watch<ChatProvider>();
    final hostVisible = _isConversationHostVisible(context);
    _reportConversationHostVisibility(chatProvider, hostVisible);
    final messages =
        chatProvider.messagesForConversation(widget.conversation.id);
    _schedulePendingAttachmentReconciliation(messages);
    final isLoading =
        chatProvider.isConversationLoading(widget.conversation.id);
    final streamError = chatProvider.messageStreamErrorForConversation(
      widget.conversation.id,
    );
    // Sólo para el primer llenado: si el timeline aún no alcanza a llenar el
    // viewport no hay scroll que dispare la carga. Con contenido desplazable el
    // dueño de la paginación es el scroll ya detenido, no cada build — dos
    // disparadores compitiendo era la otra mitad del salto.
    if (!_showChatInfoPanel &&
        messages.isNotEmpty &&
        (!_scrollController.hasClients ||
            _scrollController.position.maxScrollExtent <= 0)) {
      _scheduleOlderMessagesIfAtStart(chatProvider);
    }
    final pendingDraft =
        chatProvider.getConversationDraft(widget.conversation.id);
    final canWriteConversation = widget.conversation.status == 'active' ||
        widget.conversation.status == 'pending';

    final chatContent = Column(
      children: [
        _buildHeader(context, chatProvider),
        if (pendingDraft != null) _buildPreparedHandoffBanner(pendingDraft),

        // Pending Chat Request Banner (for employees reviewing customer requests)
        if (widget.conversation.type == 'support' &&
            widget.conversation.status == 'pending')
          _buildPendingRequestBanner(context),

        if (streamError != null)
          _buildMessageStreamErrorBanner(
            context,
            chatProvider,
            streamError,
          ),

        if (_showChatInfoPanel)
          Expanded(
            child: _buildChatInfoPanel(context, chatProvider, messages),
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final hasOpenThread = _activeThreadRootMessageId != null;
                // Reuse the same width contract as the canonical messaging
                // context inspector. Compact/right-rail hosts get a focused
                // thread screen; the full desktop inbox keeps channel + pane.
                final showThreadBesideChannel = hasOpenThread &&
                    !widget.compact &&
                    constraints.maxWidth >= 760;

                if (hasOpenThread && !showThreadBesideChannel) {
                  return _buildThreadPane(
                    context,
                    chatProvider,
                    messages,
                    canWriteConversation: canWriteConversation,
                  );
                }

                final channel = _buildChannelBody(
                  context,
                  chatProvider,
                  messages,
                  isLoading: isLoading,
                  canWriteConversation: canWriteConversation,
                  threadOpenBesideChannel: showThreadBesideChannel,
                );
                if (!showThreadBesideChannel) return channel;

                final threadPaneWidth =
                    (constraints.maxWidth * 0.38).clamp(380.0, 440.0);
                return Row(
                  children: [
                    Expanded(child: channel),
                    VerticalDivider(
                      width: 1,
                      color: colorScheme.outlineVariant,
                    ),
                    SizedBox(
                      width: threadPaneWidth,
                      child: _buildThreadPane(
                        context,
                        chatProvider,
                        messages,
                        canWriteConversation: canWriteConversation,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        if (!_showChatInfoPanel && !canWriteConversation)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Conversación archivada. El historial se conserva como respaldo y ya no admite nuevos mensajes.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (!_supportsOutgoingAttachments) return chatContent;

    return DropTarget(
      onDragEntered: (_) {
        if (!_hasBlockingOutcomeUnknownAttachment &&
            !_showChatInfoPanel &&
            !_isDraggingAttachment) {
          setState(() => _isDraggingAttachment = true);
        }
      },
      onDragExited: (_) {
        if (_isDraggingAttachment) {
          setState(() => _isDraggingAttachment = false);
        }
      },
      onDragDone: (details) {
        if (_guardPendingAttachmentMutation()) return;
        unawaited(_queueDroppedFiles(details.files));
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          chatContent,
          if (_isDraggingAttachment && !_showChatInfoPanel)
            Positioned.fill(
              child: IgnorePointer(
                child: _buildAttachmentDropOverlay(theme),
              ),
            ),
        ],
      ),
    );
  }

  Color _chatTimelineBackground(ThemeData theme) {
    final surface = theme.colorScheme.surface;
    if (surface.computeLuminance() < 0.35) {
      return Color.alphaBlend(
        Colors.white.withValues(alpha: 0.04),
        surface,
      );
    }
    return const Color(0xFFF8FAFC);
  }

  Widget _buildAttachmentDropOverlay(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.07),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.45),
          width: 2,
        ),
      ),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.upload_file_outlined,
                color: colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suelta para adjuntar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Imágenes, PDF y documentos',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
              color: VinabikeThemeRoles.of(context).warning.onContainer,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'El cliente espera respuesta. Acepta para comenzar a chatear.',
            style: TextStyle(
              fontSize: 12,
              color: VinabikeThemeRoles.of(context).warning.onContainer,
            ),
          ),
        ],
      ),
    );

    final actions = [
      OutlinedButton(
        onPressed: () => _showRejectDialog(context),
        style: OutlinedButton.styleFrom(
          foregroundColor: VinabikeThemeRoles.of(context).danger.accent,
        ),
        child: const Text('Rechazar'),
      ),
      FilledButton.icon(
        onPressed: () => _acceptChatRequest(context),
        icon: const Icon(Icons.check, size: 18),
        label: const Text('Aceptar'),
        style: FilledButton.styleFrom(
          backgroundColor: VinabikeThemeRoles.of(context).success.accent,
        ),
      ),
    ];

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 12 : 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: VinabikeThemeRoles.of(context).warning.container,
        border: Border(
          bottom:
              BorderSide(color: VinabikeThemeRoles.of(context).warning.border),
        ),
      ),
      child: widget.compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.pending_actions,
                        color: VinabikeThemeRoles.of(context).warning.accent),
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
                Icon(Icons.pending_actions,
                    color: VinabikeThemeRoles.of(context).warning.accent),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final conversation = widget.conversation;
    final hasContext = conversation.hasAnyContext;
    final hasSupportedContextPanel = conversation.hasSupportedContextPanel;
    final contextType = conversation.effectiveContextType;
    final title = chatProvider.getChatTitle(conversation);
    final subtitle = _buildConversationSubtitle(conversation);
    final jobContextColor = _headerJobContextColor(conversation);
    final hasJobContext = conversation.effectiveContextType == 'job' &&
        conversation.effectiveContextId != null;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 10 : 16,
        vertical: widget.compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
        color: colorScheme.surface,
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
                        backgroundColor:
                            ConversationChannelPresentation.accent(conversation)
                                .withValues(alpha: 0.1),
                        child: Icon(
                          ConversationChannelPresentation.icon(conversation),
                          color: ConversationChannelPresentation.accent(
                            conversation,
                          ),
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
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            _buildHeaderContextSummary(
                              conversation,
                              fallback: subtitle,
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
                        color: _showChatInfoPanel
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
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
              color: colorScheme.primary,
              tooltip: 'Contactar por WhatsApp',
              onPressed: _isSendingMessage
                  ? null
                  : () => _openWhatsAppConversationForCurrentContext(context),
            ),
          if (hasSupportedContextPanel &&
              widget.isContextPanelClosed &&
              _canOpenCurrentContext)
            IconButton(
              icon: Icon(
                _contextIcon(contextType),
                color: colorScheme.primary,
              ),
              tooltip: 'Mostrar detalles',
              onPressed: _openCurrentContext,
            ),
          if (!conversation.isSupplierConversation)
            if (!conversation.isTaskThread)
              IconButton(
                icon: Icon(
                  hasContext ? Icons.link : Icons.link_off,
                  color: hasJobContext
                      ? jobContextColor
                      : hasContext
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                ),
                tooltip: hasContext
                    ? '${conversation.hasLinkedContext ? 'Contexto vinculado' : 'Contexto detectado'}: ${_contextLabel(contextType)}'
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

  Color _headerJobContextColor(Conversation conversation) {
    return _colorFromHex(
      conversation.contextHint?.jobStatusColor,
      const Color(0xFF16A34A),
    );
  }

  Widget _buildHeaderContextSummary(
    Conversation conversation, {
    required String fallback,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hint = conversation.contextHint;
    final hasJob =
        hint?.hasJob == true || conversation.effectiveContextType == 'job';
    final bikeName = hint?.bikeName?.trim();
    final hasBike = bikeName != null && bikeName.isNotEmpty;
    final invoiceLabel = _headerInvoiceLabel(hint);
    final purchaseInvoiceLabel = _headerPurchaseInvoiceLabel(hint);

    if (!hasJob &&
        !hasBike &&
        invoiceLabel == null &&
        purchaseInvoiceLabel == null) {
      return Text(
        fallback,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    final jobColor = _headerJobContextColor(conversation);
    final jobLabel = [
      if (hint?.jobNumber?.trim().isNotEmpty == true)
        hint!.jobNumber!.trim()
      else if (hasJob)
        'Trabajo',
      if (hint?.jobStatus?.trim().isNotEmpty == true) hint!.jobStatus!.trim(),
    ].join(' · ');

    return SizedBox(
      height: 22,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (jobLabel.isNotEmpty)
            _buildHeaderContextChip(
              label: jobLabel,
              color: jobColor,
              prominent: true,
            ),
          if (jobLabel.isNotEmpty &&
              (hasBike || invoiceLabel != null || purchaseInvoiceLabel != null))
            const SizedBox(width: 6),
          if (hasBike)
            _buildHeaderContextChip(
              label: bikeName,
              color: colorScheme.onSurfaceVariant,
            ),
          if (hasBike && (invoiceLabel != null || purchaseInvoiceLabel != null))
            const SizedBox(width: 6),
          if (invoiceLabel != null)
            _buildHeaderContextChip(
              label: invoiceLabel,
              color: _invoiceStatusColor(hint?.invoiceStatus),
              prominent: true,
            ),
          if (invoiceLabel != null && purchaseInvoiceLabel != null)
            const SizedBox(width: 6),
          if (purchaseInvoiceLabel != null)
            _buildHeaderContextChip(
              label: purchaseInvoiceLabel,
              color: _purchaseInvoiceStatusColor(hint?.purchaseInvoiceStatus),
              prominent: true,
            ),
        ],
      ),
    );
  }

  String? _headerInvoiceLabel(ConversationContextHint? hint) {
    if (hint?.hasInvoice != true) return null;
    final amountLabel = _headerCurrencyValue(
      balance: hint!.invoiceBalance,
      total: hint.invoiceTotal,
    );
    final parts = <String>[
      hint.invoiceNumber?.trim().isNotEmpty == true
          ? hint.invoiceNumber!.trim()
          : 'Factura',
      if (hint.invoiceStatus?.trim().isNotEmpty == true)
        hint.invoiceStatus!.trim(),
      if (amountLabel != null) amountLabel,
    ];
    return parts.join(' · ');
  }

  String? _headerPurchaseInvoiceLabel(ConversationContextHint? hint) {
    if (hint?.hasPurchaseInvoice != true) return null;
    final amountLabel = _headerCurrencyValue(
      balance: hint!.purchaseInvoiceBalance,
      total: hint.purchaseInvoiceTotal,
    );
    final parts = <String>[
      hint.purchaseInvoiceNumber?.trim().isNotEmpty == true
          ? hint.purchaseInvoiceNumber!.trim()
          : 'Compra',
      if (hint.purchaseInvoiceStatus?.trim().isNotEmpty == true)
        hint.purchaseInvoiceStatus!.trim(),
      if (amountLabel != null) amountLabel,
    ];
    return parts.join(' · ');
  }

  String? _headerCurrencyValue({
    required double? balance,
    required double? total,
  }) {
    final amount = balance != null && balance > 0 ? balance : total;
    if (amount == null || amount <= 0) return null;
    return _formatPanelCurrency(amount);
  }

  Color _invoiceStatusColor(String? status) {
    final normalized = status?.trim().toLowerCase();
    return switch (normalized) {
      'pagada' || 'paid' => const Color(0xFF16A34A),
      'vencida' || 'overdue' => const Color(0xFFDC2626),
      'confirmada' || 'confirmed' => const Color(0xFF7C3AED),
      'enviada' || 'sent' => const Color(0xFF0EA5E9),
      'entregada' || 'delivered' => const Color(0xFF16A34A),
      'anulada' || 'cancelled' || 'canceled' => const Color(0xFFDC2626),
      _ => const Color(0xFF64748B),
    };
  }

  Color _purchaseInvoiceStatusColor(String? status) {
    final normalized = status?.trim().toLowerCase();
    return switch (normalized) {
      'pagada' || 'paid' => const Color(0xFF2563EB),
      'recibida' || 'received' => const Color(0xFF16A34A),
      'confirmada' || 'confirmed' => const Color(0xFF7C3AED),
      'enviada' || 'sent' => const Color(0xFF0EA5E9),
      'anulada' || 'cancelled' || 'canceled' => const Color(0xFFDC2626),
      _ => const Color(0xFF64748B),
    };
  }

  Widget _buildHeaderContextChip({
    required String label,
    required Color color,
    bool prominent = false,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: prominent ? 0.13 : 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
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

    final colorScheme = theme.colorScheme;
    return Container(
      color: colorScheme.surfaceContainerLowest,
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
              VerticalDivider(width: 1, color: colorScheme.outlineVariant),
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
    final colorScheme = theme.colorScheme;
    return Container(
      color: colorScheme.surface,
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
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
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
                  label: 'Archivos',
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
    final colorScheme = theme.colorScheme;
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
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: colorScheme.surface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 2),
        itemBuilder: (context, index) {
          final item = items[index];
          final selected = _selectedChatInfoSection == item.$1;
          return InkWell(
            onTap: () => setState(() => _selectedChatInfoSection = item.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.$2,
                    size: 16,
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.$3,
                    style: TextStyle(
                      color: selected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  if (item.$4 != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      item.$4!,
                      style: TextStyle(
                        color: selected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _selectedChatInfoSection == section;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.62)
            : colorScheme.surface,
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
                  color: selected
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      color: selected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: selected
                          ? colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.1)
                          : colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSurfaceVariant,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ConversationChannelPresentation.accent(conversation)
            .withValues(alpha: 0.1),
        border: Border.all(
          color: conversation.usesExternalMessagingTransport
              ? ConversationChannelPresentation.accent(conversation)
                  .withValues(alpha: 0.42)
              : colorScheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: Icon(
        ConversationChannelPresentation.icon(conversation),
        color: ConversationChannelPresentation.accent(conversation),
        size: size * 0.42,
      ),
    );
  }

  /// Info responde «¿con quién hablo y sobre qué?». Los contadores de
  /// mensajes cargados eran diagnóstico, no información; el nombre ya está en
  /// la cabecera; y las acciones viven en Gestión.
  Widget _buildChatInfoOverview({
    required ThemeData theme,
    required String title,
    required String subtitle,
    required List<Message> messages,
    required List<_ChatAttachment> attachments,
  }) {
    final conversation = widget.conversation;
    final contactHint = conversation.contextHint;
    final contactPerson = contactHint?.contactPersonName?.trim();
    final contactPersonLine = contactPerson == null || contactPerson.isEmpty
        ? null
        : [
            contactPerson,
            if (contactHint?.contactPersonRole?.trim().isNotEmpty == true)
              contactHint!.contactPersonRole!.trim(),
            if (contactHint?.contactPersonIsActive == false)
              'contacto anterior',
          ].join(' · ');
    final lastMessageAt = messages.isEmpty ? null : messages.last.createdAt;
    final hasContext = conversation.hasLinkedContext ||
        conversation.contextHint?.hasOperationalContext == true;
    final canLinkContext = conversation.isSupport &&
        !conversation.isSupplierConversation &&
        !conversation.isTaskThread;

    return _buildChatInfoContentShell(
      theme: theme,
      title: 'Info',
      subtitle: title,
      children: [
        _buildPanelSectionTitle(theme, 'Conversación'),
        const SizedBox(height: 10),
        _buildPanelBlock(
          theme: theme,
          children: [
            if (conversation.isSupport)
              _buildContactPhoneInfoRow(
                title: _isWhatsAppConversation ? 'Número' : 'Teléfono',
              ),
            if (contactPersonLine != null)
              _buildInfoRowTile(
                icon: Icons.person_outline,
                title: 'Contacto',
                value: contactPersonLine,
              ),
            _buildInfoRowTile(
              icon: Icons.route_outlined,
              title: 'Canal',
              value: conversation.channelLabel,
            ),
            _buildInfoRowTile(
              icon: Icons.flag_outlined,
              title: 'Estado',
              trailing: VbStatusBadge(
                label: _statusLabel(conversation.status),
                tone: _statusTone(conversation.status),
              ),
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
        if (hasContext) ...[
          const SizedBox(height: 18),
          _buildPanelSectionTitle(
            theme,
            conversation.hasLinkedContext
                ? 'Vinculado a'
                : 'Contexto detectado',
          ),
          const SizedBox(height: 10),
          _buildOperationalContextCard(theme),
        ] else if (canLinkContext) ...[
          const SizedBox(height: 18),
          _buildPanelSectionTitle(theme, 'Vinculado a'),
          const SizedBox(height: 10),
          _buildPanelBlock(
            theme: theme,
            children: [
              _buildManagementActionTile(
                icon: Icons.link,
                color: theme.colorScheme.primary,
                title: 'Vincular contexto',
                subtitle:
                    'Este chat no está unido a un cliente, trabajo, venta o pedido',
                onTap: () => _showAssignContextDialog(context),
              ),
            ],
          ),
        ],
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
      title: 'Archivos',
      subtitle: attachments.length == 1
          ? '1 archivo en esta conversación'
          : '${attachments.length} archivos en esta conversación',
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
            _buildPanelSectionTitle(theme, 'Fotos'),
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
    final smartActions = _smartActionCapabilities;
    final contextType = _effectiveContextType;
    final hint = widget.conversation.contextHint;
    final contextActionTitle = switch (contextType) {
      'job' => hint?.jobNumber?.trim().isNotEmpty == true
          ? 'Revisar trabajo ${hint!.jobNumber!.trim()}'
          : 'Revisar trabajo vinculado',
      'bike' => hint?.bikeName?.trim().isNotEmpty == true
          ? 'Revisar bicicleta ${hint!.bikeName!.trim()}'
          : 'Revisar bicicleta vinculada',
      'invoice' => hint?.invoiceNumber?.trim().isNotEmpty == true
          ? 'Revisar venta ${hint!.invoiceNumber!.trim()}'
          : 'Revisar venta vinculada',
      'purchase_invoice' =>
        hint?.purchaseInvoiceNumber?.trim().isNotEmpty == true
            ? 'Revisar compra ${hint!.purchaseInvoiceNumber!.trim()}'
            : 'Revisar compra vinculada',
      'supplier' => hint?.supplierLabel?.trim().isNotEmpty == true
          ? 'Revisar proveedor ${hint!.supplierLabel!.trim()}'
          : 'Revisar proveedor vinculado',
      'order' || 'online_order' => 'Revisar pedido online',
      'task' => 'Abrir la tarea raíz',
      _ => 'Revisar contexto operativo',
    };
    final contextActionSubtitle = switch (contextType) {
      'job' => [
          if (hint?.jobStatus?.trim().isNotEmpty == true)
            hint!.jobStatus!.trim(),
          if (hint?.bikeName?.trim().isNotEmpty == true) hint!.bikeName!.trim(),
        ].join(' · '),
      'invoice' => [
          if (hint?.invoiceStatus?.trim().isNotEmpty == true)
            hint!.invoiceStatus!.trim(),
          if (hint?.invoiceBalance != null)
            'Saldo ${_formatPanelCurrency(hint!.invoiceBalance)}',
        ].join(' · '),
      'purchase_invoice' => [
          if (hint?.purchaseInvoiceStatus?.trim().isNotEmpty == true)
            hint!.purchaseInvoiceStatus!.trim(),
          if (hint?.purchaseInvoiceBalance != null)
            'Saldo ${_formatPanelCurrency(hint!.purchaseInvoiceBalance)}',
        ].join(' · '),
      'supplier' => 'Ficha, compras y portal del proveedor',
      'task' => 'Ver asignación, trabajo, servicios y ciclo de la tarea',
      _ => 'Abrir sus datos sin abandonar la conversación',
    };
    final canResolve = widget.conversation.type == 'support' &&
        widget.conversation.status == 'active';
    final canSendOperationalActions =
        smartActions.isEligibleCustomerConversation &&
            (widget.conversation.status == 'active' ||
                widget.conversation.status == 'pending');

    return _buildChatInfoContentShell(
      theme: theme,
      title: 'Gestión',
      subtitle: 'Acciones sobre esta conversación',
      children: [
        FutureBuilder<_SupplierPhoneMismatch?>(
          future: _getSupplierPhoneMismatchFuture(),
          builder: (context, snapshot) {
            final mismatch = snapshot.data;
            return _buildPanelBlock(
              theme: theme,
              children: [
                if (mismatch != null)
                  _buildManagementActionTile(
                    icon: Icons.swap_horiz,
                    color: theme.colorScheme.primary,
                    title: _writeToPrimaryContactLabel,
                    subtitle:
                        '${_formatContactPhone(mismatch.registeredPhone)} · este hilo es con ${widget.conversation.contextHint?.contactPersonName ?? _formatContactPhone(mismatch.threadPhone)}',
                    onTap: () => _openRegisteredSupplierChat(mismatch),
                  ),
                if (!widget.conversation.isSupplierConversation &&
                    !widget.conversation.isTaskThread)
                  _buildManagementActionTile(
                    icon: Icons.link,
                    color: theme.colorScheme.primary,
                    title: widget.conversation.hasLinkedContext
                        ? 'Cambiar contexto'
                        : widget.conversation.hasDetectedContext
                            ? 'Confirmar contexto detectado'
                            : 'Vincular contexto',
                    subtitle: _contextLabel(contextType) ??
                        'Conecta este chat con cliente, trabajo, factura o pedido',
                    onTap: () => _showAssignContextDialog(context),
                  ),
                if (hasSupportedContextPanel && _canOpenCurrentContext)
                  _buildManagementActionTile(
                    icon: _contextIcon(contextType),
                    color: theme.colorScheme.primary,
                    title: contextActionTitle,
                    subtitle: contextActionSubtitle.isEmpty
                        ? 'Abrir sus datos sin abandonar la conversación'
                        : contextActionSubtitle,
                    onTap: _openCurrentContext,
                  ),
                if (canSendOperationalActions)
                  _buildManagementActionTile(
                    icon: Icons.flash_on,
                    color: theme.colorScheme.tertiary,
                    title: smartActions.hasInteractiveActions
                        ? 'Preparar solicitud al cliente'
                        : 'Mensajes para el cliente',
                    subtitle: smartActions.hasInteractiveActions
                        ? 'Solo muestra acciones válidas para el contexto actual'
                        : smartActions.explanation ??
                            'Mensajes preparados con contexto del ERP',
                    onTap: () => _showSmartActions(context),
                  ),
                if (_canStartWhatsAppFromConversation)
                  _buildManagementActionTile(
                    icon: Icons.phone_in_talk_outlined,
                    color: const Color(0xFF059669),
                    title: 'Abrir WhatsApp',
                    subtitle:
                        'Crea o recupera el hilo WhatsApp de este cliente',
                    onTap: () => _openWhatsAppConversationForCurrentContext(
                      context,
                    ),
                  ),
                if (canResolve)
                  _buildManagementActionTile(
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF0F766E),
                    title: 'Marcar como resuelto',
                    subtitle: widget.conversation.isSupplierConversation
                        ? 'Cierra la conversación en la bandeja de proveedores'
                        : 'Cierra la conversación en la bandeja de clientes',
                    onTap: _resolveCurrentConversation,
                  ),
              ],
            );
          },
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
      subtitle: 'Descarga esta conversación como archivo',
      children: [
        _buildPanelBlock(
          theme: theme,
          children: [
            _buildInfoRowTile(
              icon: Icons.description_outlined,
              title: 'Formato',
              value: 'JSON',
            ),
            _buildInfoRowTile(
              icon: Icons.forum_outlined,
              title: 'Contenido',
              value: 'Mensajes, vínculos ERP y archivos',
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
          'El archivo se genera desde el servidor con todos los mensajes, no sólo los cargados en pantalla: participantes, vínculos con el ERP, estados de entrega de WhatsApp y referencias a los archivos.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
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
                          color: theme.colorScheme.onSurfaceVariant,
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
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0)
              Divider(height: 1, color: colorScheme.outlineVariant),
            children[index],
          ],
        ],
      ),
    );
  }

  Color _colorFromHex(String? value, Color fallback) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return fallback;
    final normalized = raw.replaceFirst('#', '');
    final parsed = int.tryParse('ff$normalized', radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  String _formatPanelCurrency(double? amount) {
    if (amount == null) return '-';
    return ChileanUtils.formatCurrency(amount);
  }

  /// Lo que el chat tiene detrás: proveedor o cliente, trabajo, venta o
  /// compra, y el botón que abre cada cosa por su nombre. En un chat de
  /// proveedor el «cliente» es la ficha técnica que WhatsApp crea por número:
  /// no es información, no se muestra.
  Widget _buildOperationalContextCard(ThemeData theme) {
    final conversation = widget.conversation;
    final hint = conversation.contextHint;
    final hasHint = hint != null && hint.hasOperationalContext;
    if (!hasHint && !conversation.hasLinkedContext) {
      return const SizedBox.shrink();
    }

    final colorScheme = theme.colorScheme;
    final isSupplierChat = conversation.isSupplierConversation;

    return FutureBuilder<_SupplierPhoneMismatch?>(
      future: _getSupplierPhoneMismatchFuture(),
      builder: (context, snapshot) {
        final mismatch = snapshot.data;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hint != null && hasHint)
                ..._buildOperationalContextRows(theme, hint)
              else
                _buildOperationalContextRow(
                  icon: _contextIcon(_effectiveContextType),
                  title: _contextLabel(_effectiveContextType) ??
                      'Registro vinculado',
                  value: '',
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Este hilo no es con el contacto principal: la salida es
                  // una sola, escribirle a quien corresponde hoy.
                  if (mismatch != null)
                    FilledButton.icon(
                      onPressed: _isSendingMessage
                          ? null
                          : () => _openRegisteredSupplierChat(mismatch),
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: Text(_writeToPrimaryContactLabel),
                    ),
                  if (_canOpenCurrentContext)
                    if (mismatch != null)
                      OutlinedButton.icon(
                        onPressed: _openCurrentContext,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(_openContextActionLabel),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _openCurrentContext,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(_openContextActionLabel),
                      ),
                  if (hint != null &&
                      hint.hasPurchaseInvoice &&
                      _effectiveContextType != 'purchase_invoice')
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.read<WorkspaceManager>().openRouteInWorkspace(
                                '/purchases/${hint.purchaseInvoiceId!}',
                              ),
                      icon: const Icon(Icons.inventory_2_outlined, size: 16),
                      label: const Text('Abrir compra'),
                    ),
                  if (hint != null &&
                      hint.hasSupplier &&
                      _effectiveContextType != 'supplier')
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.read<WorkspaceManager>().openRouteInWorkspace(
                                '/purchases/suppliers/${hint.supplierId!}',
                              ),
                      icon: const Icon(Icons.storefront_outlined, size: 16),
                      label: const Text('Abrir proveedor'),
                    ),
                  if (!isSupplierChat && !conversation.hasLinkedContext)
                    OutlinedButton.icon(
                      onPressed: () => _showAssignContextDialog(context),
                      icon: const Icon(Icons.link, size: 16),
                      label: const Text('Vincular contexto'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildOperationalContextRows(
    ThemeData theme,
    ConversationContextHint hint,
  ) {
    final colorScheme = theme.colorScheme;
    final statusColor = _colorFromHex(hint.jobStatusColor, colorScheme.primary);
    final isSupplierChat = widget.conversation.isSupplierConversation;
    final invoiceSummary = [
      if (hint.invoiceStatus != null) hint.invoiceStatus!,
      if (hint.invoiceBalance != null)
        'Saldo ${_formatPanelCurrency(hint.invoiceBalance)}',
    ].join(' · ');
    final purchaseInvoiceSummary = [
      if (hint.purchaseInvoiceStatus != null) hint.purchaseInvoiceStatus!,
      if (hint.purchaseInvoiceBalance != null)
        'Saldo ${_formatPanelCurrency(hint.purchaseInvoiceBalance)}',
    ].join(' · ');

    return [
      if (!isSupplierChat && hint.customerLabel != null)
        _buildOperationalContextRow(
          icon: Icons.person_outline,
          title: 'Cliente',
          value: hint.customerLabel!,
        ),
      if (hint.hasSupplier)
        _buildOperationalContextRow(
          icon: Icons.storefront_outlined,
          title: 'Proveedor',
          value: hint.supplierLabel ?? '',
        ),
      if (hint.hasJob)
        _buildOperationalContextRow(
          icon: Icons.build_outlined,
          title: hint.jobLabel ?? 'Trabajo activo',
          value: [
            if (hint.jobStatus != null) hint.jobStatus!,
            if (hint.bikeName != null) hint.bikeName!,
          ].join(' · '),
          color: statusColor,
        ),
      if (hint.hasInvoice)
        _buildOperationalContextRow(
          icon: Icons.receipt_long_outlined,
          title: hint.invoiceLabel ?? 'Factura vinculada',
          value: invoiceSummary.isEmpty
              ? _formatPanelCurrency(hint.invoiceTotal)
              : invoiceSummary,
        ),
      if (hint.hasPurchaseInvoice)
        _buildOperationalContextRow(
          icon: Icons.inventory_2_outlined,
          title: hint.purchaseInvoiceLabel ?? 'Compra vinculada',
          value: purchaseInvoiceSummary.isEmpty
              ? _formatPanelCurrency(hint.purchaseInvoiceTotal)
              : purchaseInvoiceSummary,
          color: _purchaseInvoiceStatusColor(hint.purchaseInvoiceStatus),
        ),
    ];
  }

  /// «Escribir al contacto actual: Víctor», o sólo «Escribir al contacto
  /// actual» cuando la ficha no tiene nombre para el principal.
  String get _writeToPrimaryContactLabel {
    final primary =
        widget.conversation.contextHint?.supplierPrimaryContactName?.trim();
    return primary == null || primary.isEmpty
        ? 'Escribir al contacto actual'
        : 'Escribir al contacto actual: $primary';
  }

  /// El botón dice qué abre; «Abrir panel» y «Abrir registro» no decían nada.
  String get _openContextActionLabel => switch (_effectiveContextType) {
        'supplier' => 'Abrir ficha del proveedor',
        'customer' => 'Abrir ficha del cliente',
        'job' => 'Abrir trabajo',
        'bike' => 'Abrir bicicleta',
        'invoice' => 'Abrir venta',
        'purchase_invoice' => 'Abrir compra',
        'order' || 'online_order' => 'Abrir pedido',
        'task' => 'Abrir tarea',
        'product' => 'Abrir producto',
        _ => 'Abrir registro',
      };

  VbStatusTone _statusTone(String status) => switch (status) {
        'active' => VbStatusTone.success,
        'pending' => VbStatusTone.warning,
        'rejected' => VbStatusTone.danger,
        _ => VbStatusTone.neutral,
      };

  Widget _buildOperationalContextRow({
    required IconData icon,
    required String title,
    required String value,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveColor = color ?? colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: effectiveColor),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (value.trim().isNotEmpty)
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactPhoneInfoRow({required String title}) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _getConversationContactFuture(),
      builder: (context, snapshot) {
        final rawPhone = snapshot.data?['phone']?.toString().trim();
        final hasPhone = rawPhone != null && rawPhone.isNotEmpty;
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return _buildInfoRowTile(
          icon: Icons.phone_iphone_outlined,
          title: title,
          value: hasPhone
              ? _formatContactPhone(rawPhone)
              : isLoading
                  ? 'Buscando...'
                  : 'Sin teléfono registrado',
          onCopy: hasPhone
              ? () => _copyPanelValue(rawPhone, label: 'Número')
              : null,
        );
      },
    );
  }

  Widget _buildInfoRowTile({
    required IconData icon,
    required String title,
    String? value,
    Widget? trailing,
    VoidCallback? onCopy,
  }) {
    assert(value != null || trailing != null);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (trailing != null)
            Flexible(child: trailing)
          else
            Flexible(
              child: Text(
                value!,
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (onCopy != null) ...[
            const SizedBox(width: 6),
            VbSurfaceIconButton(
              icon: Icons.copy_outlined,
              tooltip: 'Copiar',
              onPressed: onCopy,
            ),
          ],
        ],
      ),
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
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelSectionTitle(ThemeData theme, String title) {
    return Text(
      title.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
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
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: theme.colorScheme.onSurfaceVariant),
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
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaTile(_ChatAttachment attachment) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget placeholder(IconData icon) => Container(
          color: colorScheme.surfaceContainerHighest,
          child: Icon(icon, color: colorScheme.onSurfaceVariant),
        );

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openAttachmentViewer(attachment),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (attachment.isExternal)
              placeholder(Icons.link_outlined)
            else if (ChatMediaCache.keyFor(attachment.message) == null &&
                (attachment.url == null || attachment.url!.isEmpty))
              placeholder(Icons.image_not_supported_outlined)
            else
              LayoutBuilder(
                builder: (context, constraints) => ChatMediaThumbnail(
                  message: attachment.message,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  borderRadius: 0,
                  resolveUrl: () => _resolveAttachmentUrl(attachment),
                  unavailable: (_) => placeholder(Icons.broken_image_outlined),
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
      onTap: () => _openAttachmentViewer(attachment),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getFileIcon(attachment.extension),
                color: theme.colorScheme.onPrimaryContainer,
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
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.open_in_new,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
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
    final hasPrivateReference =
        MessagingAttachmentService.hasPrivateReference(message);
    final hasRemoteMedia = _messageHasRemoteWhatsAppMedia(message);
    final externalUrl =
        _messagingAttachmentService.externalUrlCandidate(message);

    final metadata = message.metadata;
    final contentType = metadata['contentType']?.toString() ??
        metadata['content_type']?.toString() ??
        '';
    final extension =
        _messageAttachmentExtension(message, url ?? '', contentType);
    final isImage = message.type == 'image' ||
        contentType.toLowerCase().startsWith('image/') ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);
    final hasAttachmentMetadata = [
      'url',
      'media_url',
      'image_url',
      'file_url',
      'documentUrl',
      'document_url',
      'storage_url',
      'public_url',
      'attachment_id',
    ].any((key) => metadata.containsKey(key));

    if (message.type != 'image' &&
        message.type != 'file' &&
        !hasAttachmentMetadata &&
        !hasPrivateReference &&
        !hasRemoteMedia) {
      return null;
    }

    return _ChatAttachment(
      message: message,
      url: url,
      name: _messageAttachmentName(message, extension),
      extension: extension,
      isImage: isImage,
      isExternal: url == null &&
          !hasPrivateReference &&
          !hasRemoteMedia &&
          externalUrl != null,
    );
  }

  String? _messageAttachmentUrl(Message message) {
    return _messagingAttachmentService.trustedLegacyPublicUrl(message);
  }

  bool _messageHasRemoteWhatsAppMedia(Message message) {
    final provider = message.metadata['provider']?.toString() ??
        message.metadata['external_provider']?.toString();
    return provider == 'whatsapp' &&
        (message.type == 'image' || message.type == 'file') &&
        _messageRemoteMediaId(message) != null;
  }

  String? _messageRemoteMediaId(Message message) {
    for (final key in ['whatsapp_media_id', 'media_id']) {
      final value = message.metadata[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }

    final rawPayload = message.metadata['raw_payload'];
    if (rawPayload is Map) {
      final rawMedia = rawPayload['media'];
      if (rawMedia is Map) {
        for (final key in ['whatsapp_media_id', 'media_id', 'id']) {
          final value = rawMedia[key]?.toString().trim();
          if (value != null && value.isNotEmpty) return value;
        }
      }

      final rawMessage = rawPayload['message'];
      if (rawMessage is Map) {
        final messageType =
            rawMessage['type']?.toString() ?? message.metadata['message_type'];
        final candidates = [
          if (messageType != null) rawMessage[messageType.toString()],
          rawMessage['image'],
          rawMessage['document'],
          rawMessage['video'],
          rawMessage['audio'],
          rawMessage['sticker'],
        ];
        for (final candidate in candidates) {
          if (candidate is! Map) continue;
          final value = candidate['id']?.toString().trim();
          if (value != null && value.isNotEmpty) return value;
        }
      }
    }

    return null;
  }

  String? _messageImageCaption(Message message) {
    final metadataCaption = message.metadata['caption']?.toString().trim();
    if (metadataCaption != null && metadataCaption.isNotEmpty) {
      return metadataCaption;
    }

    final content = message.content.trim();
    if (content.isNotEmpty &&
        !content.startsWith('http') &&
        content.toLowerCase() != 'imagen recibida') {
      return content;
    }

    final rawPayload = message.metadata['raw_payload'];
    if (rawPayload is Map) {
      final rawMessage = rawPayload['message'];
      if (rawMessage is Map) {
        final image = rawMessage['image'];
        if (image is Map) {
          final caption = image['caption']?.toString().trim();
          if (caption != null && caption.isNotEmpty) return caption;
        }
      }
    }

    return null;
  }

  String? _messageFileCaption(Message message) {
    final explicit = message.metadata['caption']?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final raw = message.metadata['raw_payload'];
    final inbound = raw is Map ? raw['message'] : null;
    final document = inbound is Map ? inbound['document'] : null;
    final original =
        document is Map ? document['caption']?.toString().trim() : null;
    if (original != null && original.isNotEmpty) return original;
    final content = message.content.trim();
    final fileName = _messageAttachmentName(message, '').trim();
    if (content.isEmpty ||
        content == fileName ||
        content == 'Archivo: $fileName' ||
        content == 'Documento recibido' ||
        content == 'Archivo recibido' ||
        content == _messageAttachmentUrl(message)) return null;
    return content;
  }

  Future<String?> _resolveWhatsAppMediaUrl(
    Message message, {
    bool playback = false,
  }) async {
    try {
      if (MessagingAttachmentService.hasPrivateReference(message)) {
        final playbackPath = playback
            ? MessagingAttachmentService.playbackStoragePath(message)
            : null;
        if (playbackPath != null) {
          return _messagingAttachmentService.createSignedUrlForPath(
            playbackPath,
          );
        }
        return _messagingAttachmentService.createCachedPreviewSignedUrl(
          message,
        );
      }

      final response = await Supabase.instance.client.functions.invoke(
        'whatsapp-media',
        headers: kSupabaseFunctionsRegionHeaders,
        body: {
          'messageId': message.id,
          if (playback) 'variant': 'playback',
        },
      );

      if (response.status < 200 || response.status >= 300) {
        debugPrint(
          '❌ [WhatsAppMedia] hydrate_failed status=${response.status} data=${response.data}',
        );
        return null;
      }

      final data = response.data;
      if (data is! Map) return null;

      final metadataUpdates = Map<String, dynamic>.from(
        (data['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
      final resolvedUrl = data['url']?.toString().trim();

      if (resolvedUrl == null || resolvedUrl.isEmpty) return null;

      if (mounted && metadataUpdates.isNotEmpty) {
        context
            .read<ChatProvider>()
            .updateMessageMetadataById(message.id, metadataUpdates);
      }

      return resolvedUrl;
    } catch (error) {
      debugPrint(
          '❌ [WhatsAppMedia] hydrate_error message=${message.id}: $error');
      return null;
    }
  }

  Widget _buildImageMessage(
    BuildContext context,
    Message message, {
    String? url,
  }) {
    final caption = _messageImageCaption(message);

    return GestureDetector(
      onTap: () {
        _openMessageAttachmentViewer(message, url ?? '');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Alto FIJO, no libre: una miniatura de tamaño conocido no hace
          // oscilar la estimación de largo del ListView. Los bytes vienen de
          // este equipo (memoria, disco o la copia del compositor de un
          // archivo recién enviado); la red se toca una vez por adjunto por
          // equipo, nunca en cada reapertura.
          ChatMediaThumbnail(
            message: message,
            resolveUrl: () => _resolveWhatsAppMediaUrl(message),
            placeholderColor: Theme.of(context).colorScheme.outlineVariant,
            unavailable: (retry) => _buildImageUnavailableMessage(
              title: 'No se pudo cargar la imagen',
              subtitle: 'Toca para intentar de nuevo.',
              onTap: retry,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 6),
            Text(
              caption,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeferredWhatsAppImageMessage(
    BuildContext context,
    Message message,
  ) {
    // The thumbnail resolves the WhatsApp media only when this device has
    // never stored it; a URL is minted on tap, for the viewer.
    return _buildImageMessage(context, message);
  }

  Widget _buildImageLoadingMessage() {
    return Container(
      width: 220,
      height: 160,
      decoration: BoxDecoration(
        color: const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  Widget _buildImageUnavailableMessage({
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 220,
        height: 150,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image_not_supported_outlined,
                size: 32, color: Color(0xFF475569)),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExternalAttachmentMessage(Message message) {
    return InkWell(
      onTap: () => _openExternalAttachmentLink(message),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_outlined, color: Color(0xFF475569)),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Enlace externo no previsualizado · Toca para abrir',
                style: TextStyle(
                  color: Color(0xFF334155),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternalAttachmentLink(Message message) async {
    final candidate = _messagingAttachmentService.externalUrlCandidate(message);
    final uri = Uri.tryParse(candidate ?? '');
    if (uri == null || !['https', 'http'].contains(uri.scheme)) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      _showErrorSnackBar(context, 'No se pudo abrir el enlace externo.');
    }
  }

  Widget _buildFileMessage(
    BuildContext context,
    Message message,
    String? fileUrl,
    bool isMe, {
    bool isLoading = false,
    bool failed = false,
  }) {
    final metadata = message.metadata;
    final contentType = metadata['contentType']?.toString() ??
        metadata['content_type']?.toString() ??
        '';
    final extension =
        _messageAttachmentExtension(message, fileUrl ?? '', contentType);
    final fileName = _messageAttachmentName(message, extension);
    final subtitle = isLoading
        ? 'Descargando desde WhatsApp...'
        : failed
            ? 'No se pudo descargar. Toca para reintentar.'
            : extension.toUpperCase();

    return GestureDetector(
      onTap: () async {
        if (fileUrl != null) {
          _openMessageAttachmentViewer(message, fileUrl);
          return;
        }
        if (failed) {
          setState(() {
            _whatsAppMediaFutureCache.remove(message.id);
          });
          return;
        }
        if (ChatMediaCache.keyFor(message) != null) {
          _openMessageAttachmentViewer(message, '');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.3)
              : Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getFileIcon(extension),
              color: isMe
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.blue[600],
              size: 32,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: failed
                          ? VinabikeThemeRoles.of(context).danger.accent
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                failed ? Icons.refresh : Icons.download,
                color: failed
                    ? VinabikeThemeRoles.of(context).danger.accent
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeferredWhatsAppFileMessage(
    BuildContext context,
    Message message,
    bool isMe,
  ) {
    // A document tile needs its name and kind, both in the row already. The
    // bytes are fetched — or served from this device — when it is opened.
    return _buildFileMessage(context, message, null, isMe);
  }

  String _messageAttachmentName(Message message, String extension) {
    final metadata = message.metadata;
    for (final key in [
      'filename',
      'documentFilename',
      'document_filename',
      'originalFilename',
      'original_filename',
    ]) {
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
      final mapped = _extensionForContentType(contentType);
      if (mapped != null) return mapped;

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

  String? _extensionForContentType(String contentType) {
    switch (contentType.toLowerCase().split(';').first.trim()) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'video/mp4':
        return 'mp4';
      case 'audio/mpeg':
        return 'mp3';
      case 'audio/ogg':
        return 'ogg';
      case 'application/pdf':
        return 'pdf';
      case 'application/msword':
        return 'doc';
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return 'docx';
      case 'application/vnd.ms-excel':
        return 'xls';
      case 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet':
        return 'xlsx';
      default:
        return null;
    }
  }

  String _formatPanelDate(DateTime value) {
    return DateFormat('dd/MM/yyyy HH:mm').format(value);
  }

  String _messageAttachmentContentType(Message message) {
    final metadata = message.metadata;
    return metadata['contentType']?.toString() ??
        metadata['content_type']?.toString() ??
        '';
  }

  Future<void> _openAttachmentViewer(_ChatAttachment attachment) async {
    if (!mounted) return;
    if (attachment.isExternal) {
      await _openExternalAttachmentLink(attachment.message);
      return;
    }
    await _openViewerForMessage(
      attachment.message,
      knownUrl: attachment.url,
      fileName: attachment.name,
      extension: attachment.extension,
      isImage: attachment.isImage,
    );
  }

  /// One URL for an attachment the panel lists: its legacy public URL when
  /// it has one, otherwise a fresh authorisation.
  Future<String?> _resolveAttachmentUrl(_ChatAttachment attachment) {
    final url = attachment.url;
    if (url != null && url.isNotEmpty) return Future.value(url);
    return _resolveWhatsAppMediaUrl(attachment.message);
  }

  /// Opens the viewer on the bytes this device already holds. Signed URLs
  /// last minutes, so one is never reused — but one is also never requested
  /// for a file that is already here.
  Future<void> _openViewerForMessage(
    Message message, {
    required String? knownUrl,
    required String fileName,
    required String extension,
    required bool isImage,
  }) async {
    final cache = ChatMediaCache.instance;
    final key = ChatMediaCache.keyFor(message);
    final cachedBytes = key == null ? null : await cache.read(key);
    if (!mounted) return;

    String? url;
    if (cachedBytes == null) {
      url = MessagingAttachmentService.hasPrivateReference(message)
          ? await _resolveWhatsAppMediaUrl(message)
          : (knownUrl != null && knownUrl.isNotEmpty)
              ? knownUrl
              : await _whatsAppMediaFutureCache.putIfAbsent(
                  message.id,
                  () => _resolveWhatsAppMediaUrl(message),
                );
      if (!mounted) return;
      if (url == null || url.isEmpty) {
        _whatsAppMediaFutureCache.remove(message.id);
        _showErrorSnackBar(context, 'No se pudo autorizar este adjunto.');
        return;
      }
    } else {
      url = (knownUrl != null && knownUrl.isNotEmpty)
          ? knownUrl
          : 'cache://${Uri.encodeComponent(key!)}';
    }
    final contentType = _messageAttachmentContentType(message);
    final resolvedUrl = url;
    ChatAttachmentViewer.show(
      context,
      url: resolvedUrl,
      fileName: fileName,
      extension: extension,
      contentType: contentType,
      isImage: isImage,
      loadBytes: () async {
        if (cachedBytes != null) return cachedBytes;
        if (key == null) return null;
        return cache.fetch(
          key,
          resolveUrl: () async => resolvedUrl,
          fileExtension: extension,
        );
      },
      fileContext: _attachmentFileContext(
        message,
        url: resolvedUrl,
        fileName: fileName,
        extension: extension,
        contentType: contentType,
        isImage: isImage,
      ),
    );
  }

  Future<void> _openMessageAttachmentViewer(
    Message message,
    String url,
  ) async {
    if (!mounted) return;
    final contentType = _messageAttachmentContentType(message);
    final extension = _messageAttachmentExtension(message, url, contentType);
    final isImage = message.type == 'image' ||
        contentType.toLowerCase().startsWith('image/') ||
        ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(extension);
    await _openViewerForMessage(
      message,
      knownUrl:
          MessagingAttachmentService.hasPrivateReference(message) ? null : url,
      fileName: _messageAttachmentName(message, extension),
      extension: extension,
      isImage: isImage,
    );
  }

  AppFileContext _attachmentFileContext(
    Message message, {
    required String url,
    required String fileName,
    required String extension,
    required String contentType,
    required bool isImage,
  }) {
    final metadata = message.metadata;
    final provider = metadata['provider']?.toString().trim().isNotEmpty == true
        ? metadata['provider'].toString().trim()
        : metadata['external_provider']?.toString().trim();
    final isWhatsApp = widget.conversation.isWhatsApp ||
        provider == 'whatsapp' ||
        metadata['channel'] == 'whatsapp';
    final contactName = message.isMe
        ? 'Tú'
        : (metadata['contact_name']?.toString().trim().isNotEmpty == true
            ? metadata['contact_name'].toString().trim()
            : widget.conversation.creatorName?.trim());
    final conversationTitle = widget.conversation.title?.trim();
    final contextTitle = contactName?.isNotEmpty == true
        ? contactName!
        : conversationTitle?.isNotEmpty == true
            ? conversationTitle!
            : widget.conversation.channelLabel;
    final effectiveContextType = _effectiveContextType;
    final effectiveContextId = _effectiveContextId;
    final hasLinkedContext = effectiveContextType != null &&
        effectiveContextId != null &&
        effectiveContextId.isNotEmpty;
    final contextType =
        hasLinkedContext ? effectiveContextType : 'conversation';
    final contextId =
        hasLinkedContext ? effectiveContextId : widget.conversation.id;
    final safeContentType =
        contentType.trim().isNotEmpty ? contentType.trim() : null;
    final safeExtension = extension.trim().isNotEmpty ? extension.trim() : null;
    final sourceStorageBucket =
        metadata['storageBucket'] ?? metadata['storage_bucket'];
    final sourceStoragePath =
        metadata['storagePath'] ?? metadata['storage_path'];
    final hasPrivateReference =
        MessagingAttachmentService.hasPrivateReference(message);

    return AppFileContext(
      sourceType: isWhatsApp ? 'chat_whatsapp' : 'chat',
      sourceId: message.id,
      sourceProvider:
          isWhatsApp ? 'WhatsApp' : widget.conversation.channelLabel,
      sourceRoute: '/messaging/conversations/${widget.conversation.id}',
      contextType: contextType,
      contextId: contextId,
      contextTitle: contextTitle,
      contextSubtitle:
          '${widget.conversation.channelLabel} · ${DateFormat('dd/MM/yyyy HH:mm').format(message.createdAt)}',
      tags: [
        'chat',
        'mensaje',
        if (isWhatsApp) 'whatsapp',
        if (isImage) 'imagen' else 'archivo',
      ],
      metadata: {
        'message_id': message.id,
        'conversation_id': widget.conversation.id,
        'message_type': message.type,
        'message_created_at': message.createdAt.toIso8601String(),
        if (!hasPrivateReference) 'url': url,
        if (hasPrivateReference && metadata['attachment_id'] != null)
          'source_attachment_id': metadata['attachment_id'],
        'filename': fileName,
        if (safeExtension != null) 'extension': safeExtension,
        if (safeContentType != null) 'content_type': safeContentType,
        if (safeContentType != null) 'contentType': safeContentType,
        if (metadata['external_message_id'] != null)
          'external_message_id': metadata['external_message_id'],
        if (metadata['whatsapp_media_id'] != null)
          'whatsapp_media_id': metadata['whatsapp_media_id'],
        if (metadata['media_id'] != null) 'media_id': metadata['media_id'],
        if (sourceStorageBucket != null)
          'source_storage_bucket': sourceStorageBucket,
        if (sourceStoragePath != null) 'source_storage_path': sourceStoragePath,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
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
          backgroundColor: VinabikeThemeRoles.of(context).success.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo descargar el respaldo: $e'),
          backgroundColor: VinabikeThemeRoles.of(context).danger.accent,
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
        SnackBar(
          content: Text('Conversación marcada como resuelta'),
          backgroundColor: VinabikeThemeRoles.of(context).success.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo actualizar la conversación: $e'),
          backgroundColor: VinabikeThemeRoles.of(context).danger.accent,
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
              color: Theme.of(context).colorScheme.outlineVariant,
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
              color: Theme.of(context).colorScheme.outlineVariant,
              thickness: 1,
              indent: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineDaySeparator(BuildContext context, DateTime day) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final label = day == today
        ? 'Hoy'
        : day == today.subtract(const Duration(days: 1))
            ? 'Ayer'
            : DateFormat('dd/MM/yyyy').format(day);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: colorScheme.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: Divider(color: colorScheme.outlineVariant)),
        ],
      ),
    );
  }

  Widget _buildHistoryBoundary(
    BuildContext context,
    ChatProvider provider, {
    required bool hasMessages,
    String boundaryLabel = 'Inicio de la conversación',
  }) {
    final conversationId = widget.conversation.id;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final error = provider.olderMessagesErrorForConversation(conversationId);

    if (provider.isLoadingOlderMessages(conversationId)) {
      return const SizedBox(
        height: 44,
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.error,
                ),
              ),
            ),
            const SizedBox(width: 6),
            TextButton(
              onPressed: () => provider.retryOlderMessages(conversationId),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (provider.hasMoreMessages(conversationId)) {
      return Center(
        child: TextButton.icon(
          onPressed: () => provider.loadOlderMessages(conversationId),
          icon: const Icon(Icons.history_rounded, size: 17),
          label: const Text('Cargar mensajes anteriores'),
        ),
      );
    }

    if (!hasMessages) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        boundaryLabel,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildMessageStreamErrorBanner(
    BuildContext context,
    ChatProvider provider,
    String message,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
      color: colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 17,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onErrorContainer,
                  ),
            ),
          ),
          TextButton(
            onPressed: () => provider.retryConversationMessages(
              widget.conversation.id,
            ),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  String _buildConversationSubtitle(Conversation conversation) {
    if (conversation.isTaskThread) {
      final count = conversation.taskThreadContexts.length;
      return count == 1
          ? 'Canal de tareas · 1 tarea'
          : 'Canal de tareas · $count tareas';
    }
    final parts = <String>[conversation.channelLabel];

    final contextLabel = _contextLabel(conversation.effectiveContextType);
    if (contextLabel != null) parts.add(contextLabel);
    parts.add(_statusLabel(conversation.status));

    return parts.join(' · ');
  }

  String? _contextLabel(String? contextType) {
    return switch (contextType) {
      'order' => 'Pedido web',
      'job' => 'Servicio técnico',
      'invoice' => 'Factura',
      'purchase_invoice' => 'Compra',
      'supplier' => 'Proveedor',
      'bike' => 'Bicicleta',
      'product' => 'Producto',
      'customer' => 'Cliente',
      'task' => 'Tarea',
      _ => null,
    };
  }

  IconData _contextIcon(String? contextType) {
    return switch (contextType) {
      'order' => Icons.shopping_cart_outlined,
      'job' => Icons.build_outlined,
      'invoice' => Icons.receipt_long_outlined,
      'purchase_invoice' => Icons.inventory_2_outlined,
      'supplier' => Icons.storefront_outlined,
      'task' => Icons.task_alt_outlined,
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
          bottom:
              BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
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
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant),
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
    if (widget.conversation.isSupplierConversation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El contexto de proveedor se administra desde su ficha o documento de compra.',
          ),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AssignContextDialog(
        conversationId: widget.conversation.id,
        currentContextType: _effectiveContextType,
        currentContextId: _effectiveContextId,
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
        contextType: _effectiveContextType,
        contextId: _effectiveContextId,
      );

      if (!mounted) return;

      await provider.loadConversations();
      provider.setActiveConversation(conversationId);

      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Conversación de WhatsApp abierta aparte.'),
          backgroundColor: VinabikeThemeRoles.of(context).success.accent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir WhatsApp: $e'),
          backgroundColor: VinabikeThemeRoles.of(context).danger.accent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingMessage = false);
    }
  }

  void _showSmartActions(BuildContext context, {GlobalKey? anchorKey}) {
    if (!_canUseSmartActions) {
      _showErrorSnackBar(
        context,
        'Las acciones rápidas solo están disponibles en conversaciones de clientes.',
      );
      return;
    }

    _toggleComposerMenu(
      name: 'smart_actions',
      anchorKey: anchorKey ?? _composerActionsButtonKey,
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
    final smartActions = _smartActionCapabilities;
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
          border: Border.all(color: theme.colorScheme.outlineVariant),
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
                            color: theme.colorScheme.onSurface,
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
                      icon: Icon(
                        Icons.arrow_back,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurface,
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
                        if (_isWhatsAppConversation &&
                            smartActions.hasInteractiveActions) ...[
                          _buildPopoverSectionHeader(
                            'Solicitudes al cliente',
                            'Disponibles según el contexto ERP vinculado',
                          ),
                          const SizedBox(height: 8),
                          if (smartActions.canRequestQuoteApproval)
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
                                  parentContext,
                                  'approve_quote',
                                );
                              },
                            ),
                          if (smartActions.canRequestPayment)
                            _buildCommandActionTile(
                              icon: Icons.payments_outlined,
                              color: const Color(0xFF059669),
                              title: 'Solicitud de pago',
                              subtitle:
                                  'Envía el botón de pago para la venta asociada',
                              badge: 'COBRO',
                              onTap: () {
                                _removeComposerMenuOverlay(notify: true);
                                _sendActionRequest(parentContext, 'pay_now');
                              },
                            ),
                          if (smartActions.canRequestDeliveryConfirmation)
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
                          if (smartActions.explanation != null) ...[
                            const SizedBox(height: 6),
                            _buildSmartActionContextNotice(
                              theme,
                              smartActions.explanation!,
                            ),
                          ],
                          const SizedBox(height: 12),
                        ] else if (_isWhatsAppConversation) ...[
                          _buildSmartActionContextNotice(
                            theme,
                            smartActions.explanation ??
                                'Vincula un trabajo o una venta para habilitar solicitudes al cliente.',
                          ),
                          const SizedBox(height: 12),
                        ] else ...[
                          _buildWhatsAppOnlyActionsNotice(theme),
                          const SizedBox(height: 12),
                        ],
                        _buildAutomaticMessagesSection(theme),
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

  Widget _buildSmartActionContextNotice(ThemeData theme, String message) {
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
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
    };
  }

  /// Send an action request message to the customer
  Future<void> _sendActionRequest(
      BuildContext context, String actionType) async {
    final smartActions = _smartActionCapabilities;
    if (!smartActions.isEligibleCustomerConversation) {
      _showErrorSnackBar(
        context,
        'Las solicitudes operativas solo se envían a conversaciones de clientes.',
      );
      return;
    }

    if (!_isWhatsAppConversation) {
      _showErrorSnackBar(
        context,
        'Esta acción requiere una conversación de WhatsApp.',
      );
      return;
    }

    if (!smartActions.allows(actionType)) {
      _showErrorSnackBar(
        context,
        smartActions.explanation ??
            'La conversación no tiene el contexto necesario para esta solicitud.',
      );
      return;
    }

    final bikeshopService = context.read<BikeshopService>();
    final salesService = context.read<SalesService>();
    final contextType = _effectiveContextType;
    final contextId = _effectiveContextId;

    // Validate context
    if (contextId == null) {
      _showErrorSnackBar(
          context, 'No hay contexto asociado a este chat (Job/Invoice).');
      return;
    }

    String? invoiceId;
    String? jobId;
    MechanicJob? job;
    double? amount;
    String? actionTargetId;
    String? actionKind;

    if (contextType == 'job') {
      jobId = contextId;
      try {
        job = await bikeshopService.getJobById(contextId);
        if (job?.invoiceId != null) {
          invoiceId = job?.invoiceId;
        }
      } catch (e) {
        if (context.mounted) {
          _showErrorSnackBar(context, 'Error al obtener datos del trabajo.');
        }
        return;
      }
    } else if (contextType == 'invoice') {
      invoiceId = contextId;
    }

    // Get invoice amount for payment requests
    if (invoiceId != null && actionType == 'pay_now') {
      try {
        final invoice = await salesService.fetchInvoice(invoiceId);
        amount = invoice?.balance ?? invoice?.total ?? 0;
      } catch (e) {
        debugPrint('Error fetching invoice: $e');
      }
    }

    if (!context.mounted) return;

    if (actionType == 'approve_quote' && jobId == null) {
      _showErrorSnackBar(
        context,
        'La aprobación requiere un presupuesto de taller asociado, no una factura.',
      );
      return;
    }

    if (actionType == 'approve_quote' &&
        (job == null || !job.isQuotationWorkflow)) {
      _showErrorSnackBar(
        context,
        'El trabajo asociado no tiene un presupuesto pendiente de decisión.',
      );
      return;
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
        content =
            'Por favor revisa y responde el ${job!.proposalDocumentLabelLower} de ${job.jobNumber}.';
        actionTargetId = jobId;
        actionKind = 'job';
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
      final receipt = await _sendWhatsAppInteractiveRequest(
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
          if (invoiceId != null) 'invoiceId': invoiceId,
          if (jobId != null) 'jobId': jobId,
        },
      );

      if (!receipt.isSuccess || !context.mounted) {
        return;
      }

      _showWhatsAppResultSnackbar(
        context: context,
        deliveryMethod: receipt.deliveryMethod,
        successMessage: actionType == 'approve_quote'
            ? 'Presupuesto enviado por WhatsApp Cloud API'
            : 'Solicitud enviada por WhatsApp Cloud API',
        fallbackMessage: actionType == 'approve_quote'
            ? 'WhatsApp abierto con el presupuesto prellenado'
            : 'WhatsApp abierto con la solicitud prellenada',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: VinabikeThemeRoles.of(context).danger.accent),
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _getSenderInfo(String senderId) {
    return _senderInfoFutureCache.putIfAbsent(
      senderId,
      () => _messagingService.getSenderInfo(senderId),
    );
  }

  Future<Map<String, dynamic>?> _resolveConversationWhatsAppContact({
    bool rethrowOnError = false,
  }) async {
    final conversation = widget.conversation;
    if (!conversation.isWhatsApp) {
      return null;
    }

    final contact = await _messagingService.getSupportConversationContact(
      conversation.id,
      rethrowOnError: rethrowOnError,
    );
    if (!conversation.isSupplierConversation) return contact;

    final supplierId = conversation.contextHint?.supplierId ??
        (conversation.effectiveContextType == 'supplier'
            ? conversation.effectiveContextId
            : null);
    final templateContactName =
        await _messagingService.getSupplierTemplateContactName(
      conversationId: conversation.id,
      supplierId: supplierId,
      rethrowOnError: rethrowOnError,
    );
    return <String, dynamic>{
      ...?contact,
      'template_contact_name': templateContactName,
    };
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
      final isExternalProvider = provider == 'whatsapp' ||
          provider == 'instagram' ||
          provider == 'facebook_messenger';
      final isInbound = direction == 'inbound' ||
          (isExternalProvider && direction != 'outbound' && !message.isMe) ||
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

  Future<WhatsAppSendReceipt> _sendWhatsAppInteractiveRequest({
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

    final conversationId = widget.conversation.id;
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
      context: context.mounted ? context : null,
      customerPhone: phone,
      customerName: customerName == null || customerName.isEmpty
          ? 'Cliente'
          : customerName,
      conversationId: conversationId,
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
    final messages = context
        .watch<ChatProvider>()
        .messagesForConversation(widget.conversation.id);

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
                : 'WhatsApp: sólo mensajes autorizados';
        final color = isOpen ? const Color(0xFF16A34A) : Colors.amber[800]!;

        return Tooltip(
          message: lastInboundAt == null
              ? 'El contacto no ha respondido. Puedes iniciar con un mensaje utilitario de Direct Send; marketing aún requiere plantilla.'
              : isOpen
                  ? 'La ventana de 24 horas empezó con la última respuesta del cliente.'
                  : 'La ventana expiró. El próximo envío debe ser utilitario o una plantilla de marketing aprobada.',
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
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetaReplyWindowNotice({
    required DateTime? replyWindowExpiresAt,
    required bool isChecking,
    required bool isRefreshing,
    required bool isOpen,
    required String? stateError,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final rawRemaining = replyWindowExpiresAt == null
        ? Duration.zero
        : replyWindowExpiresAt.toUtc().difference(DateTime.now().toUtc());
    final remaining = rawRemaining.isNegative ? Duration.zero : rawRemaining;
    final hasError = stateError != null;
    final color = hasError
        ? colorScheme.error
        : isOpen
            ? colorScheme.primary
            : colorScheme.tertiary;
    final label = hasError
        ? isRefreshing
            ? 'Reintentando verificación de Meta'
            : 'No se pudo verificar el estado de Meta'
        : isChecking
            ? 'Verificando estado de Meta'
            : isOpen
                ? '${widget.conversation.shortChannelLabel}: ${_formatWindowDuration(remaining)} disponibles'
                : '${widget.conversation.shortChannelLabel}: ventana cerrada';

    return Tooltip(
      message: hasError
          ? '$stateError Los envíos permanecerán bloqueados hasta completar la verificación.'
          : isChecking
              ? 'Esperando los receipts pendientes y la ventana autoritativa de Meta.'
              : isOpen
                  ? 'Ventana confirmada por el binding de Meta para esta conversación.'
                  : 'Meta requiere que el cliente vuelva a escribir antes de enviar otra respuesta.',
      child: Row(
        children: [
          Icon(
            hasError && !isRefreshing
                ? Icons.cloud_off_outlined
                : isChecking
                    ? Icons.sync_outlined
                    : isOpen
                        ? Icons.schedule_outlined
                        : Icons.lock_clock_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          if (isChecking)
            IconButton(
              tooltip: 'Volver a consultar Meta',
              visualDensity: VisualDensity.compact,
              onPressed: isRefreshing
                  ? null
                  : () => unawaited(
                        context
                            .read<ChatProvider>()
                            .refreshMetaConversationState(
                              widget.conversation.id,
                            ),
                      ),
              icon: isRefreshing
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 17),
            ),
        ],
      ),
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

  void _showWhatsAppTemplatePicker({
    String? pendingText,
    GlobalKey? anchorKey,
  }) {
    // El estado de revisión se pide también para las conversaciones de
    // cliente: una plantilla recién corregida queda PENDING en Meta y el envío
    // falla con 132001 hasta que la aprueban. Verlo aquí evita que el taller
    // interprete un rechazo temporal como una falla del sistema.
    final supplierStatusFuture =
        WhatsAppService().getSupplierTemplateReviewStatuses();
    _toggleComposerMenu(
      name: 'whatsapp_templates',
      anchorKey: anchorKey ?? _composerActionsButtonKey,
      width: 420,
      estimatedHeight: 390,
      panelBuilder: (overlayContext) => _buildWhatsAppTemplatePanel(
        overlayContext,
        pendingText: pendingText?.trim(),
        supplierStatusFuture: supplierStatusFuture,
      ),
    );
  }

  /// Manda a Meta el texto que el ERP considera correcto para las plantillas
  /// cuyo cuerpo aprobado difiere. Editar las devuelve a revisión: mientras
  /// estén pendientes, un envío con ese nombre puede fallar, y por eso se
  /// avisa con el detalle de cuáles se tocaron.
  Future<void> _syncWhatsAppTemplateBodies() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Corrigiendo textos en Meta…')),
    );
    try {
      final resultado = await WhatsAppService().syncApprovedTemplateBodies();
      // El aviso en pantalla es efímero y esta operación toca la cuenta de
      // Meta: queda también en el log, que es donde se puede auditar después.
      debugPrint(
        '[WhatsAppTemplates] editadas=${resultado.editadas} '
        'sinCambios=${resultado.sinCambios} faltan=${resultado.faltan}',
      );
      if (!mounted) return;
      final editadas = resultado.editadas;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            editadas.isEmpty
                ? 'Los textos aprobados ya estaban correctos.'
                : 'Enviadas a revisión de Meta: ${editadas.join(', ')}. '
                    'Mientras revisan, esos envíos pueden fallar.',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } catch (error) {
      debugPrint('[WhatsAppTemplates] falló la corrección: $error');
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo corregir en Meta: $error')),
      );
    }
  }

  /// Abre —o cierra— la revisión de una plantilla dentro del panel. Enviar sin
  /// ver el texto era lo que permitía que un mensaje saliera diciendo algo
  /// distinto de lo que el operador creía.
  Future<void> _reviewWhatsAppTemplate(WhatsAppTemplateOption option) async {
    final yaAbierta = _reviewingTemplate?.key == option.key;
    if (yaAbierta) {
      setState(_resetWhatsAppTemplatePreview);
      _composerMenuOverlayEntry?.markNeedsBuild();
      return;
    }
    await _loadWhatsAppTemplatePreview(option);
  }

  Future<void> _loadWhatsAppTemplatePreview(
    WhatsAppTemplateOption option, {
    bool refreshContact = false,
  }) async {
    if (refreshContact && widget.whatsAppTemplatePreviewLoader == null) {
      _clearWhatsAppContactCache();
    }

    final generation = ++_reviewingTemplateGeneration;
    setState(() {
      _reviewingTemplate = option;
      _reviewingTemplateText = null;
      _reviewingTemplateError = null;
      _isReviewingTemplateLoading = true;
      _reviewingTemplateNeedsSupplierContact = false;
    });
    _composerMenuOverlayEntry?.markNeedsBuild();

    try {
      final loader = widget.whatsAppTemplatePreviewLoader;
      final text = await (loader == null
              ? _resolveWhatsAppTemplatePreview(option)
              : loader(option))
          .timeout(_whatsAppTemplatePreviewTimeout);
      if (!_ownsWhatsAppTemplatePreview(option, generation)) return;

      final normalized = text?.trim();
      if (normalized == null || normalized.isEmpty) {
        setState(() {
          _reviewingTemplateError = widget.conversation.isSupplierConversation
              ? 'Falta el nombre del contacto o vendedor en el perfil del proveedor.'
              : 'La conversación no tiene un nombre de contacto asociado.';
          _reviewingTemplateNeedsSupplierContact =
              widget.conversation.isSupplierConversation;
          _isReviewingTemplateLoading = false;
        });
      } else {
        setState(() {
          _reviewingTemplateText = normalized;
          _isReviewingTemplateLoading = false;
        });
      }
    } on _WhatsAppTemplatePreviewFailure catch (error) {
      if (!_ownsWhatsAppTemplatePreview(option, generation)) return;
      setState(() {
        _reviewingTemplateError = error.message;
        _isReviewingTemplateLoading = false;
      });
    } on TimeoutException {
      if (!_ownsWhatsAppTemplatePreview(option, generation)) return;
      setState(() {
        _reviewingTemplateError =
            'La vista previa tardó demasiado en cargar. Vuelve a intentarlo.';
        _isReviewingTemplateLoading = false;
      });
    } catch (error) {
      debugPrint('⚠️ No se pudo previsualizar la plantilla: $error');
      if (!_ownsWhatsAppTemplatePreview(option, generation)) return;
      setState(() {
        _reviewingTemplateError =
            'No se pudo cargar la vista previa. Vuelve a intentarlo.';
        _isReviewingTemplateLoading = false;
      });
    }
    _composerMenuOverlayEntry?.markNeedsBuild();
  }

  bool _ownsWhatsAppTemplatePreview(
    WhatsAppTemplateOption option,
    int generation,
  ) =>
      mounted &&
      _reviewingTemplate?.key == option.key &&
      _reviewingTemplateGeneration == generation;

  String? get _supplierProfileRouteForTemplatePreview {
    final supplierId = widget.conversation.contextHint?.supplierId?.trim() ??
        (_effectiveContextType == 'supplier'
            ? _effectiveContextId?.trim()
            : null);
    return supplierId == null || supplierId.isEmpty
        ? null
        : '/purchases/suppliers/$supplierId';
  }

  void _openSupplierProfileFromTemplatePreview() {
    final route = _supplierProfileRouteForTemplatePreview;
    if (route == null) return;
    _removeComposerMenuOverlay(notify: true);
    context.read<WorkspaceManager>().openRouteInWorkspace(route);
  }

  /// El texto exacto que recibirá el contacto con esta plantilla, resuelto con
  /// los mismos valores que usará el envío. Un dato faltante se conserva como
  /// ausencia para que el owner visible lo convierta en una corrección precisa,
  /// nunca en un estado de carga perpetuo.
  Future<String?> _resolveWhatsAppTemplatePreview(
    WhatsAppTemplateOption option,
  ) async {
    final conversationId = widget.conversation.id;
    final contact = await _resolveConversationWhatsAppContact(
      rethrowOnError: true,
    );
    // The exact successful preview read is also the contact snapshot the
    // subsequent send should reuse. A late result from another chat cannot
    // enter this cache.
    if (widget.conversation.id == conversationId) {
      _whatsAppContactFutureConversationId = conversationId;
      _whatsAppContactFuture = Future.value(contact);
    }
    // La clave se elige antes de indexar: `cond ? mapa?[a] : mapa?[b]`
    // confunde al parser de Dart, que lee el `?[` como otro condicional.
    final contactKey = widget.conversation.isSupplierConversation
        ? 'template_contact_name'
        : 'name';
    final recipientName = contact?[contactKey]?.toString().trim();
    if (recipientName == null || recipientName.isEmpty) return null;
    String? agentName;
    if (option.parameterLayout ==
        WhatsAppTemplateParameterLayout.contactAndAgent) {
      final currentUserId = _messagingService.currentUserId;
      final senderInfo =
          currentUserId == null ? null : await _getSenderInfo(currentUserId);
      agentName = senderInfo?['name']?.toString().trim();
      if (option.requiresAgentName &&
          (agentName == null || agentName.isEmpty)) {
        throw const _WhatsAppTemplatePreviewFailure(
          'No pudimos resolver el nombre del usuario que inició sesión.',
        );
      }
    }
    return WhatsAppService().buildTemplatePreviewText(
      option: option,
      customerName: recipientName,
      businessName: await WhatsAppService().resolveBusinessNameForPreview(),
      agentName: agentName,
    );
  }

  Widget _buildWhatsAppTemplatePanel(
    BuildContext overlayContext, {
    String? pendingText,
    Future<Map<String, WhatsAppTemplateReviewStatus>>? supplierStatusFuture,
  }) {
    final theme = Theme.of(overlayContext);
    final options = WhatsAppService.templateOptionsForConversation(
      isSupplier: widget.conversation.isSupplierConversation,
    );
    final hasPendingText = pendingText != null && pendingText.isNotEmpty;
    final counterparty =
        widget.conversation.isSupplierConversation ? 'proveedor' : 'cliente';

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
                          'Mensajes WhatsApp',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          hasPendingText
                              ? 'El texto libre queda como borrador. Elige un mensaje autorizado para contactar al $counterparty.'
                              : 'Elige el motivo correcto. Los utilitarios usan Direct Send; marketing usa plantilla.',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Corregir el texto de una plantilla aprobada no tenía
                  // camino: `deploy_defaults` sólo crea lo que falta, así que
                  // un cuerpo mal escrito se quedaba para siempre. Vive acá
                  // porque es el lugar donde ya se ven las plantillas y su
                  // estado de revisión.
                  IconButton(
                    key: const Key('whatsapp-template-sync'),
                    tooltip: 'Corregir textos en Meta',
                    onPressed: _syncWhatsAppTemplateBodies,
                    icon: const Icon(Icons.cloud_sync_outlined, size: 18),
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
            if (supplierStatusFuture == null)
              ...options.map(
                (option) => _buildWhatsAppTemplateOption(
                  overlayContext,
                  option,
                  pendingText: pendingText,
                ),
              )
            else
              FutureBuilder<Map<String, WhatsAppTemplateReviewStatus>>(
                future: supplierStatusFuture,
                builder: (context, snapshot) {
                  final isLoading =
                      snapshot.connectionState == ConnectionState.waiting;
                  final statuses = snapshot.data ??
                      const <String, WhatsAppTemplateReviewStatus>{};
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoading)
                        const LinearProgressIndicator(minHeight: 2),
                      ...options.map(
                        (option) => _buildWhatsAppTemplateOption(
                          context,
                          option,
                          pendingText: pendingText,
                          reviewStatus: statuses[option.defaultTemplateName],
                          isCheckingReview: isLoading,
                          reviewCheckFailed: snapshot.hasError,
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWhatsAppTemplateOption(
    BuildContext context,
    WhatsAppTemplateOption option, {
    String? pendingText,
    WhatsAppTemplateReviewStatus? reviewStatus,
    bool isCheckingReview = false,
    bool reviewCheckFailed = false,
  }) {
    // Direct Send no necesita una plantilla aprobada. Marketing sí: intentar
    // quitarle esa puerta sería clasificar publicidad como utilidad y arriesga
    // que Meta bloquee Direct Send para toda la cuenta.
    final requiresLiveApproval =
        option.category != WhatsAppMessageCategory.utility;
    final isEnabled = !requiresLiveApproval || reviewStatus?.isApproved == true;
    final availabilityLabel = !requiresLiveApproval
        ? null
        : isCheckingReview
            ? 'Revisando…'
            : reviewCheckFailed
                ? 'Sin confirmar'
                : reviewStatus == null
                    ? 'No disponible'
                    : switch (reviewStatus.status) {
                        'PENDING' => 'En revisión',
                        'REJECTED' => 'Rechazada',
                        'PAUSED' => 'Pausada',
                        'DISABLED' => 'Deshabilitada',
                        'APPROVED' => null,
                        _ => 'No disponible',
                      };

    return Opacity(
      opacity: isEnabled ? 1 : 0.62,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            // Revisar el texto se puede siempre. Marketing requiere APPROVED;
            // utilidad sale por Direct Send y conserva la plantilla como respaldo.
            onTap: () => _reviewWhatsAppTemplate(option),
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
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          option.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (availabilityLabel == null)
                    const Icon(Icons.chevron_right, size: 18)
                  else
                    Text(
                      availabilityLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                ],
              ),
            ),
          ),
          if (_reviewingTemplate?.key == option.key)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildWhatsAppTemplatePreviewState(
                context,
                option,
                isEnabled: isEnabled,
                availabilityLabel: availabilityLabel,
                pendingText: pendingText,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWhatsAppTemplatePreviewState(
    BuildContext context,
    WhatsAppTemplateOption option, {
    required bool isEnabled,
    required String? availabilityLabel,
    required String? pendingText,
  }) {
    if (_isReviewingTemplateLoading) {
      return Semantics(
        label: 'Cargando vista previa del mensaje',
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              key: Key('whatsapp-template-preview-loading'),
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    final error = _reviewingTemplateError;
    if (error != null) {
      final colorScheme = Theme.of(context).colorScheme;
      final profileRoute = _supplierProfileRouteForTemplatePreview;
      return Semantics(
        liveRegion: true,
        child: Container(
          key: const Key('whatsapp-template-preview-error'),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onErrorContainer,
                            height: 1.35,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                runSpacing: 4,
                children: [
                  if (_reviewingTemplateNeedsSupplierContact &&
                      profileRoute != null)
                    TextButton.icon(
                      key: const Key('whatsapp-template-open-supplier'),
                      onPressed: _openSupplierProfileFromTemplatePreview,
                      icon: const Icon(Icons.storefront_outlined, size: 17),
                      label: const Text('Abrir ficha'),
                    ),
                  TextButton.icon(
                    key: const Key('whatsapp-template-preview-retry'),
                    onPressed: () => unawaited(
                      _loadWhatsAppTemplatePreview(
                        option,
                        refreshContact: true,
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Reintentar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final reviewedText = _reviewingTemplateText;
    if (reviewedText == null) return const SizedBox.shrink();
    return WhatsAppOutgoingPreview(
      key: const Key('whatsapp-template-preview'),
      text: reviewedText,
      disabledReason: isEnabled
          ? null
          : 'No se puede enviar: ${availabilityLabel ?? 'sin aprobación de Meta'}.',
      onCancel: () {
        setState(_resetWhatsAppTemplatePreview);
        _composerMenuOverlayEntry?.markNeedsBuild();
      },
      onSend: () {
        final textToSend = _reviewingTemplateText;
        setState(_resetWhatsAppTemplatePreview);
        _sendSelectedWhatsAppTemplate(
          option,
          pendingText: pendingText,
          previewText: textToSend,
        );
      },
    );
  }

  Future<void> _sendSelectedWhatsAppTemplate(
    WhatsAppTemplateOption option, {
    String? pendingText,
    String? previewText,
  }) async {
    if (_isSendingMessage) return;

    _removeComposerMenuOverlay(notify: true);
    final chatProvider = context.read<ChatProvider>();
    final whatsappService = WhatsAppService();
    final conversationId = widget.conversation.id;
    final contextType = _effectiveContextType;
    final contextId = _effectiveContextId;
    final contactFuture = _getWhatsAppContactFuture();
    final currentUserId = _messagingService.currentUserId;
    final needsAgent = option.parameterLayout ==
        WhatsAppTemplateParameterLayout.contactAndAgent;
    // Everything the send needs is asked for at once, not one after the
    // other: the contact, the agent's name and (inside the service) the
    // template settings and the business name.
    final senderInfoFuture = needsAgent && currentUserId != null
        ? _getSenderInfo(currentUserId)
        : Future<Map<String, dynamic>?>.value(null);

    // The bubble goes up now, with the text the operator just reviewed; the
    // provider's answer updates it. This is what a text message already did.
    final sendStartedAt = DateTime.now();
    final optimisticMessageId =
        'temp-wa-template-${sendStartedAt.microsecondsSinceEpoch}';
    final bubbleText = (previewText?.trim().isNotEmpty ?? false)
        ? previewText!.trim()
        : option.label;
    chatProvider.addOptimisticMessage(
      Message(
        id: optimisticMessageId,
        conversationId: conversationId,
        senderId: currentUserId,
        content: bubbleText,
        type: 'text',
        metadata: {
          'channel': 'whatsapp',
          'provider': 'whatsapp',
          'external_provider': 'whatsapp',
          'pending': true,
          'client_message_id': optimisticMessageId,
          'template_purpose': option.key,
          'template_name': option.defaultTemplateName,
          'message_category': option.category.name,
        },
        createdAt: sendStartedAt,
        isMe: true,
      ),
    );

    final pending = pendingText?.trim();
    if (mounted && _messageController.text.trim() == pending) {
      _messageController.clear();
    }
    // The composer is free from here; the dispatch continues behind it.
    unawaited(
      _dispatchWhatsAppTemplate(
        chatProvider: chatProvider,
        whatsappService: whatsappService,
        option: option,
        optimisticMessageId: optimisticMessageId,
        contactFuture: contactFuture,
        senderInfoFuture: senderInfoFuture,
        conversationId: conversationId,
        contextType: contextType,
        contextId: contextId,
        pendingText: pending,
      ),
    );
  }

  Future<void> _dispatchWhatsAppTemplate({
    required ChatProvider chatProvider,
    required WhatsAppService whatsappService,
    required WhatsAppTemplateOption option,
    required String optimisticMessageId,
    required Future<Map<String, dynamic>?> contactFuture,
    required Future<Map<String, dynamic>?> senderInfoFuture,
    required String conversationId,
    required String? contextType,
    required String? contextId,
    required String? pendingText,
  }) async {
    try {
      final reviewFuture = option.isSupplier &&
              option.category != WhatsAppMessageCategory.utility
          ? whatsappService.getSupplierTemplateReviewStatuses()
          : Future<Map<String, WhatsAppTemplateReviewStatus>>.value(const {});
      final results = await Future.wait<Object?>([
        contactFuture,
        senderInfoFuture,
        reviewFuture,
      ]);
      final contact = results[0] as Map<String, dynamic>?;
      final senderInfo = results[1] as Map<String, dynamic>?;
      final statuses = results[2] as Map<String, WhatsAppTemplateReviewStatus>;

      if (option.isSupplier &&
          option.category != WhatsAppMessageCategory.utility) {
        final review = statuses[option.defaultTemplateName];
        if (review?.isApproved != true) {
          throw Exception(
            review?.status == 'PENDING'
                ? 'Meta todavía está revisando esta plantilla.'
                : 'Meta no tiene este mensaje de marketing aprobado para enviar.',
          );
        }
      }

      final phone = contact?['phone']?.toString();
      final bindingContactName = contact?['name']?.toString().trim();
      final supplierTemplateContactName =
          contact?['template_contact_name']?.toString().trim();
      final recipientName = widget.conversation.isSupplierConversation
          ? supplierTemplateContactName
          : bindingContactName;

      if (phone == null || phone.isEmpty) {
        throw Exception('La conversación no tiene teléfono asociado.');
      }
      if (recipientName == null || recipientName.isEmpty) {
        throw Exception(
          widget.conversation.isSupplierConversation
              ? 'Falta el nombre del contacto o vendedor en el perfil del proveedor.'
              : 'La conversación no tiene un nombre de contacto asociado.',
        );
      }
      String? agentName;
      if (option.parameterLayout ==
          WhatsAppTemplateParameterLayout.contactAndAgent) {
        agentName = senderInfo?['name']?.toString().trim();
        if (option.requiresAgentName &&
            (agentName == null || agentName.isEmpty)) {
          throw Exception(
            'No pudimos resolver el nombre del usuario que inició sesión.',
          );
        }
      }

      final receipt = await whatsappService.sendTemplateMessage(
        option: option,
        customerPhone: phone,
        customerName: recipientName,
        agentName: agentName,
        bindingContactName: bindingContactName,
        conversationId: conversationId,
        contextType: contextType,
        contextId: contextId,
        clientMessageId: optimisticMessageId,
      );

      if (!receipt.isSuccess) {
        if (receipt.unsafeToFallback) {
          chatProvider.updateMessageMetadataById(optimisticMessageId, {
            'pending': false,
            'external_status': 'outcome_unknown',
            'outcome_unknown': true,
            'retry_disabled': true,
            if (receipt.messageId != null)
              'server_message_id': receipt.messageId,
            if (receipt.externalMessageId != null)
              'external_message_id': receipt.externalMessageId,
          });
          if (mounted) {
            _showErrorSnackBar(
              context,
              'Resultado incierto: verifica la conversación antes de reenviar.',
            );
          }
          return;
        }
        throw Exception('Meta rechazó el mensaje seleccionado.');
      }

      if (receipt.deliveryMethod == WhatsAppDeliveryMethod.cloudApi) {
        chatProvider.updateMessageById(
          optimisticMessageId,
          content: receipt.resolvedMessageText?.trim().isNotEmpty == true
              ? receipt.resolvedMessageText!.trim()
              : null,
          metadataUpdates: {
            'pending': false,
            'server_ack_durable': true,
            'server_message_id': receipt.messageId,
            'external_status': receipt.externalStatus,
            'external_message_id': receipt.externalMessageId,
          },
        );
      } else {
        // The manual fallback opened WhatsApp outside the ERP; nothing was
        // recorded here, so nothing stays in the timeline.
        chatProvider.removeMessageById(optimisticMessageId);
      }

      if (pendingText != null && pendingText.isNotEmpty) {
        chatProvider.setConversationDraft(
          conversationId,
          pendingText,
          title: 'Mensaje pendiente de ventana WhatsApp',
          subtitle:
              'Se envió "${option.label}". Cuando el ${widget.conversation.isSupplierConversation ? 'proveedor' : 'cliente'} responda, puedes enviar este texto libre.',
        );
      }

      if (!mounted) return;
      _showWhatsAppResultSnackbar(
        context: context,
        deliveryMethod: receipt.deliveryMethod,
        successMessage: 'Mensaje enviado: ${option.label}',
        fallbackMessage: 'WhatsApp abierto con el mensaje prellenado',
      );
    } catch (e) {
      chatProvider.removeMessageById(optimisticMessageId);
      if (!mounted) return;
      if (pendingText != null &&
          pendingText.isNotEmpty &&
          _messageController.text.trim().isEmpty) {
        _messageController.text = pendingText;
      }
      _showErrorSnackBar(context, 'No se pudo enviar el mensaje: $e');
    }
  }

  Widget _buildComposer(BuildContext context) {
    final chatProvider = context.read<ChatProvider>();
    final hasMetaStateSnapshot = !_isMetaConversation ||
        chatProvider.hasCompleteMetaConversationStateSnapshot(
          widget.conversation.id,
        );
    final replyWindowExpiresAt = _isMetaConversation
        ? chatProvider.metaReplyWindowExpiresAt(widget.conversation.id)
        : null;
    final metaStateError = _isMetaConversation
        ? chatProvider.metaConversationStateError(widget.conversation.id)
        : null;
    final isCheckingMetaWindow = _isMetaConversation && !hasMetaStateSnapshot;
    final isMetaWindowOpen = !_isMetaConversation ||
        chatProvider.canReplyToMetaConversation(widget.conversation.id);
    return _buildTextComposer(
      context,
      showSmartActions: _canUseSmartActions,
      composerEnabled: !isCheckingMetaWindow && isMetaWindowOpen,
      metaReplyWindowExpiresAt: replyWindowExpiresAt,
      isCheckingMetaWindow: isCheckingMetaWindow,
      isRefreshingMetaState: _isMetaConversation &&
          chatProvider.isMetaConversationStateLoading(widget.conversation.id),
      isMetaWindowOpen: isMetaWindowOpen,
      metaStateError: metaStateError,
    );
  }

  Widget _buildTextComposer(
    BuildContext context, {
    required bool showSmartActions,
    required bool composerEnabled,
    required DateTime? metaReplyWindowExpiresAt,
    required bool isCheckingMetaWindow,
    required bool isRefreshingMetaState,
    required bool isMetaWindowOpen,
    required String? metaStateError,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasBlockingOutcomeUnknownAttachment =
        _hasBlockingOutcomeUnknownAttachment;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyToMessage != null)
          _buildMessageQuote(_replyToMessage!, composing: true),
        if (_isWhatsAppConversation) ...[
          _buildWhatsAppServiceWindowGauge(context),
          const SizedBox(height: 8),
        ] else if (_isMetaConversation) ...[
          _buildMetaReplyWindowNotice(
            replyWindowExpiresAt: metaReplyWindowExpiresAt,
            isChecking: isCheckingMetaWindow,
            isRefreshing: isRefreshingMetaState,
            isOpen: isMetaWindowOpen,
            stateError: metaStateError,
          ),
          const SizedBox(height: 8),
        ],
        if (_pendingAttachments.isNotEmpty) ...[
          _buildPendingAttachmentTray(context),
          const SizedBox(height: 8),
        ],
        if (_voiceRecorder.isRecording)
          ChatVoiceRecordingBar(
            controller: _voiceRecorder,
            onCancel: _cancelVoiceNote,
            onSend: _finishVoiceNote,
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              KeyedSubtree(
                key: _composerActionsButtonKey,
                child: IconButton(
                  tooltip: hasBlockingOutcomeUnknownAttachment
                      ? 'Esperando confirmación del adjunto'
                      : !composerEnabled
                          ? 'Ventana de respuesta no disponible'
                          : 'Agregar al mensaje',
                  onPressed:
                      hasBlockingOutcomeUnknownAttachment || !composerEnabled
                          ? null
                          : () => _showComposerActionsMenu(
                                context,
                                showSmartActions: showSmartActions,
                              ),
                  style: IconButton.styleFrom(
                    foregroundColor: colorScheme.onSurfaceVariant,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    // 44 = alto natural del campo con una línea, para que la
                    // fila quede a ras.
                    minimumSize: const Size.square(44),
                  ),
                  icon: AnimatedRotation(
                    turns: _activeComposerMenuName == 'composer_actions' ||
                            _isEmojiPickerOpen
                        ? 0.125
                        : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.add_rounded),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CompositedTransformTarget(
                  link: _layerLink,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): () =>
                          unawaited(_sendComposer()),
                      const SingleActivator(LogicalKeyboardKey.numpadEnter):
                          () => unawaited(_sendComposer()),
                    },
                    child: TextField(
                      key: const ValueKey<String>('chat-message-composer'),
                      controller: _messageController,
                      focusNode: _focusNode,
                      enabled: composerEnabled,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: _activeThreadRootMessageId != null
                            ? 'Agregar una respuesta…'
                            : _isMetaConversation && !composerEnabled
                                ? metaStateError != null
                                    ? 'Verificación de Meta pendiente'
                                    : isCheckingMetaWindow
                                        ? 'Verificando ventana de respuesta...'
                                        : 'Espera un nuevo mensaje del cliente'
                                : 'Escribe un mensaje... (# para ref)',
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLowest,
                        // El texto de ayuda NO envuelve. En un teléfono angosto
                        // «Escribe un mensaje... (# para ref)» se partía en dos
                        // líneas y el campo vacío medía 66 px contra 44 de los
                        // botones: por eso se veía descuadrado. El campo sigue
                        // creciendo con texto real, hasta cinco líneas.
                        hintMaxLines: 1,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide:
                              BorderSide(color: colorScheme.outlineVariant),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide:
                              BorderSide(color: colorScheme.outlineVariant),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                          borderSide: BorderSide(
                            color: colorScheme.primary,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // The field's own listenable decides between microphone and
              // send, so typing never rebuilds the whole window.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _messageController,
                builder: (context, _, __) {
                  if (_showsVoiceButton) {
                    return FilledButton(
                      key: const ValueKey<String>('chat-voice-record'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.square(44),
                        maximumSize: const Size.square(44),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      onPressed: hasBlockingOutcomeUnknownAttachment ||
                              !composerEnabled
                          ? null
                          : _startVoiceNote,
                      child: const Icon(Icons.mic_rounded, size: 20),
                    );
                  }
                  return FilledButton(
                    key: const ValueKey<String>('chat-message-send'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.square(44),
                      maximumSize: const Size.square(44),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                      ),
                    ),
                    onPressed: _isSendingPendingAttachments ||
                            hasBlockingOutcomeUnknownAttachment ||
                            !composerEnabled
                        ? null
                        : () => _sendComposer(),
                    child: _isSendingPendingAttachments
                        ? const SizedBox.square(
                            dimension: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 19),
                  );
                },
              ),
            ],
          ),
      ],
    );
  }

  void _showComposerActionsMenu(
    BuildContext parentContext, {
    required bool showSmartActions,
  }) {
    final smartActions = _smartActionCapabilities;
    final purchaseSupplierId =
        _supportsOutgoingAttachments ? _supplierContextId : null;
    _toggleComposerMenu(
      name: 'composer_actions',
      anchorKey: _composerActionsButtonKey,
      width: 330,
      estimatedHeight: (_isWhatsAppConversation ? 330 : 275) +
          (purchaseSupplierId == null ? 0 : 56),
      panelBuilder: (overlayContext) => _buildComposerPopoverPanel(
        context: overlayContext,
        icon: Icons.add_circle_outline_rounded,
        iconColor: _accentBlue,
        title: 'Agregar al mensaje',
        children: [
          if (_supportsOutgoingAttachments)
            _buildComposerPopoverAction(
              icon: Icons.attach_file_rounded,
              color: const Color(0xFF2563EB),
              title: 'Foto o archivo',
              subtitle: 'Previsualiza antes de enviar',
              onTap: () => _showAttachmentOptions(
                anchorKey: _composerActionsButtonKey,
              ),
            ),
          if (purchaseSupplierId != null)
            _buildComposerPopoverAction(
              icon: Icons.receipt_long_outlined,
              color: _purchaseDocumentAccent,
              title: 'Documento de compra',
              subtitle: 'Envía un borrador o reenvía uno enviado',
              onTap: () => _showPurchaseDocumentPicker(
                supplierId: purchaseSupplierId,
                anchorKey: _composerActionsButtonKey,
              ),
            ),
          _buildComposerPopoverAction(
            icon: Icons.emoji_emotions_outlined,
            color: const Color(0xFFD97706),
            title: 'Emoji',
            subtitle: 'Insertar en el punto del cursor',
            onTap: _toggleEmojiPicker,
          ),
          if (showSmartActions)
            _buildComposerPopoverAction(
              icon: Icons.bolt_outlined,
              color: const Color(0xFF7C3AED),
              title: smartActions.hasInteractiveActions
                  ? 'Solicitud al cliente'
                  : 'Mensajes para el cliente',
              subtitle: smartActions.hasInteractiveActions
                  ? 'Acciones válidas para el contexto actual'
                  : smartActions.explanation ??
                      'Textos preparados usando datos del ERP',
              onTap: () => _showSmartActions(
                parentContext,
                anchorKey: _composerActionsButtonKey,
              ),
            ),
          if (_isWhatsAppConversation)
            _buildComposerPopoverAction(
              icon: Icons.dynamic_form_outlined,
              color: const Color(0xFF0F766E),
              title: 'Mensaje WhatsApp',
              subtitle: 'Utilidad por Direct Send o marketing aprobado',
              onTap: () => _showWhatsAppTemplatePicker(
                pendingText: _messageController.text.trim(),
                anchorKey: _composerActionsButtonKey,
              ),
            ),
        ],
      ),
    );
  }

  /// Supplier behind this thread, when there is one.
  ///
  /// The inbox binds a supplier by phone even when nothing was linked by hand,
  /// so the hint is the reliable source and the explicit context is the
  /// fallback.
  String? get _supplierContextId {
    if (!widget.conversation.isSupplierConversation) return null;
    final hinted = widget.conversation.contextHint?.supplierId?.trim();
    if (hinted != null && hinted.isNotEmpty) return hinted;
    if (_effectiveContextType == 'supplier') {
      final contextId = _effectiveContextId?.trim();
      if (contextId != null && contextId.isNotEmpty) return contextId;
    }
    return null;
  }

  void _showPurchaseDocumentPicker({
    required String supplierId,
    GlobalKey? anchorKey,
  }) {
    final documentsFuture = _loadSupplierSendableDocuments(supplierId);
    _toggleComposerMenu(
      name: 'purchase_documents',
      anchorKey: anchorKey ?? _composerActionsButtonKey,
      width: 400,
      estimatedHeight: 330,
      panelBuilder: (overlayContext) => _buildPurchaseDocumentPanel(
        overlayContext,
        documentsFuture: documentsFuture,
      ),
    );
  }

  Future<List<PurchaseInvoice>> _loadSupplierSendableDocuments(
    String supplierId,
  ) async {
    final purchaseService = context.read<PurchaseService>();
    final invoices = await purchaseService.getInvoicesBySupplier(supplierId);
    return invoices
        .where(
          (invoice) =>
              invoice.id != null &&
              (invoice.status == PurchaseInvoiceStatus.draft ||
                  invoice.status == PurchaseInvoiceStatus.sent),
        )
        .toList();
  }

  Widget _buildPurchaseDocumentPanel(
    BuildContext overlayContext, {
    required Future<List<PurchaseInvoice>> documentsFuture,
  }) {
    return _buildComposerPopoverPanel(
      context: overlayContext,
      icon: Icons.receipt_long_outlined,
      iconColor: _purchaseDocumentAccent,
      title: 'Borradores y enviados',
      children: [
        FutureBuilder<List<PurchaseInvoice>>(
          future: documentsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 18),
                child: LinearProgressIndicator(minHeight: 2),
              );
            }
            if (snapshot.hasError) {
              return _buildPurchaseDocumentNotice(
                context,
                'No se pudieron cargar los documentos de este proveedor.',
              );
            }
            final documents = snapshot.data ?? const <PurchaseInvoice>[];
            if (documents.isEmpty) {
              return _buildPurchaseDocumentNotice(
                context,
                'Este proveedor no tiene documentos de compra en borrador ni enviados.',
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 244),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: documents.length,
                itemBuilder: (context, index) => _buildPurchaseDocumentOption(
                  context,
                  documents[index],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildPurchaseDocumentNotice(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildPurchaseDocumentOption(
    BuildContext context,
    PurchaseInvoice invoice,
  ) {
    final theme = Theme.of(context);
    final lineCount = invoice.items.length;
    return InkWell(
      onTap: () => _queuePurchaseDocumentAttachment(invoice),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _purchaseDocumentAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.description_outlined,
                color: _purchaseDocumentAccent,
                size: 19,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'N° ${invoice.invoiceNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${invoice.status.displayName} · '
                    '${ChileanUtils.formatDate(invoice.date)} · '
                    '$lineCount ${lineCount == 1 ? 'línea' : 'líneas'} · '
                    '${ChileanUtils.formatCurrency(invoice.total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  /// Build the document the supplier receives and leave it in the composer.
  ///
  /// The draft only becomes «Enviada» once the transport confirms the send, so
  /// nothing is written to the document here.
  Future<void> _queuePurchaseDocumentAttachment(PurchaseInvoice invoice) async {
    final invoiceId = invoice.id;
    if (invoiceId == null || _isPreparingPurchaseDocument) return;
    _removeComposerMenuOverlay(notify: true);
    if (_guardPendingAttachmentMutation()) return;
    final conversationId = widget.conversation.id;
    final session = _composerSession;

    final appearanceService = context.read<AppearanceService>();
    final inventoryService = context.read<InventoryService>();
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isPreparingPurchaseDocument = true);
    try {
      final bytes = await PurchaseDocumentPdfGenerator.generateBytes(
        invoice,
        appearanceService: appearanceService,
        inventoryService: inventoryService,
      );
      if (!_isCurrentComposer(conversationId, session)) return;
      _addPendingAttachments([
        _buildPendingAttachment(
          fileName: PurchaseDocumentPdfGenerator.fileNameFor(
            invoice.invoiceNumber,
          ),
          bytes: bytes,
          purchaseInvoiceId: invoiceId,
          purchaseInvoiceNumber: invoice.invoiceNumber,
        ),
      ]);
      if (_messageController.text.trim().isEmpty) {
        _messageController.text =
            'Te enviamos el documento de compra N° ${invoice.invoiceNumber}.';
      }
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Documento N° ${invoice.invoiceNumber} listo para enviar.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('No se pudo preparar el documento: $error'),
            backgroundColor: VinabikeThemeRoles.of(context).danger.accent,
          ),
        );
    } finally {
      if (mounted) setState(() => _isPreparingPurchaseDocument = false);
    }
  }

  /// Open the queued purchase document, and take back whatever the operator
  /// saved while it was open.
  ///
  /// Editing happens in the canonical document form, so the file that leaves
  /// the chat is rebuilt from the stored document rather than from the copy
  /// generated when it was queued.
  Future<void> _openPurchaseDocumentPreview(
    PendingChatAttachment attachment,
  ) async {
    final invoiceId = attachment.purchaseInvoiceId;
    if (invoiceId == null) return;

    final isReserved = attachment.reservation != null;
    final revision = await showPurchaseDocumentPreviewDialog(
      context,
      invoiceId: invoiceId,
      invoiceNumber: attachment.purchaseInvoiceNumber ?? '',
      bytes: attachment.bytes,
      canEdit: !isReserved && !_isSendingPendingAttachments,
      lockedReason: isReserved
          ? 'Este adjunto ya está reservado para envío; no admite cambios.'
          : null,
    );
    if (revision == null || !mounted) return;

    final index = _pendingAttachments.indexWhere(
      (item) => item.id == attachment.id,
    );
    if (index == -1) return;
    setState(() {
      _pendingAttachments[index] = _pendingAttachments[index].withRevision(
        bytes: revision.bytes,
        fileName: revision.fileName,
        invoiceNumber: revision.invoiceNumber,
      );
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Se enviará la versión guardada del documento '
            'N° ${revision.invoiceNumber}.',
          ),
        ),
      );
  }

  /// Move each confirmed draft from «Borrador» to «Enviada».
  ///
  /// A document already sent or advanced is left alone: the chat send is not
  /// allowed to walk the purchase workflow backwards.
  Future<void> _markPurchaseDocumentsAsSent(
    List<PendingChatAttachment> attachments, {
    required PurchaseService purchaseService,
    required String conversationId,
  }) async {
    if (attachments.isEmpty) return;

    final messenger = mounted ? ScaffoldMessenger.maybeOf(context) : null;
    final marked = <String>[];
    final failed = <String>[];

    for (final attachment in attachments) {
      final invoiceId = attachment.purchaseInvoiceId;
      if (invoiceId == null) continue;
      final label = attachment.purchaseInvoiceNumber ?? invoiceId;
      try {
        final outcome = await purchaseService.markDocumentSentAfterDispatch(
          invoiceId,
        );
        switch (outcome) {
          case PurchaseDocumentSendOutcome.marked:
            marked.add(label);
          case PurchaseDocumentSendOutcome.alreadyAdvanced:
            break;
          case PurchaseDocumentSendOutcome.missing:
            failed.add(label);
        }
      } catch (error) {
        debugPrint(
            'No se pudo marcar el documento $label como enviada: $error');
        failed.add(label);
      }
    }

    if (!mounted ||
        widget.conversation.id != conversationId ||
        messenger == null) return;
    if (failed.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            failed.length == 1
                ? 'El documento N° ${failed.first} se envió, pero sigue en '
                    'borrador. Cámbialo en Documentos de compra.'
                : '${failed.length} documentos se enviaron, pero siguen en '
                    'borrador. Cámbialos en Documentos de compra.',
          ),
          backgroundColor: VinabikeThemeRoles.of(context).danger.accent,
        ),
      );
      return;
    }
    if (marked.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            marked.length == 1
                ? 'Documento N° ${marked.first} quedó como enviada.'
                : '${marked.length} documentos quedaron como enviada.',
          ),
        ),
      );
    }
  }

  Widget _buildPendingAttachmentTray(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final count = _pendingAttachments.length;
    final hasOutcomeUnknown =
        _pendingAttachments.any((attachment) => attachment.outcomeUnknown);
    final hasBlockingOutcome = _hasBlockingOutcomeUnknownAttachment;
    final hasReplaySafeOutcome = _pendingAttachments.any(
      (attachment) => attachment.outcomeUnknown && attachment.canRetrySafely,
    );
    final blockedReservation = _pendingAttachments
        .where(
          (attachment) =>
              attachment.outcomeUnknown && !attachment.canRetrySafely,
        )
        .firstOrNull
        ?.reservation;
    final blockedReservationId = blockedReservation?.id;
    final reservationLabel = blockedReservationId?.substring(
      blockedReservationId.length > 8 ? blockedReservationId.length - 8 : 0,
    );

    return Container(
      // No height cap: the tray's content is already bounded (header + one
      // 82 px row), and a hardcoded ceiling only clips — or overflows — when
      // the text renders taller than the number someone measured once.
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.attach_file,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasBlockingOutcome
                          ? 'Esperando confirmación de WhatsApp'
                          : hasOutcomeUnknown
                              ? hasReplaySafeOutcome
                                  ? 'Sin confirmación · reintento seguro disponible'
                                  : 'Resultado incierto'
                              : count == 1
                                  ? 'Adjunto listo'
                                  : '$count adjuntos listos',
                      key: ValueKey(hasOutcomeUnknown),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    if (hasBlockingOutcome) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Reserva${reservationLabel == null ? '' : ' · $reservationLabel'} conservada para evitar duplicados.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasOutcomeUnknown)
                Tooltip(
                  message: hasBlockingOutcome
                      ? _pendingAttachmentMutationBlockedMessage
                      : hasReplaySafeOutcome
                          ? 'Reutiliza la misma reserva sin crear otro mensaje'
                          : 'Verifica el chat antes de reenviar',
                  child: Icon(
                    hasBlockingOutcome
                        ? Icons.lock_clock_outlined
                        : Icons.help_outline_rounded,
                    size: 17,
                    color: colorScheme.tertiary,
                  ),
                ),
              TextButton(
                onPressed: _isSendingPendingAttachments || hasBlockingOutcome
                    ? null
                    : _clearPendingAttachments,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                ),
                child: const Text('Limpiar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _pendingAttachments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                return _buildPendingAttachmentTile(
                  context,
                  _pendingAttachments[index],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingAttachmentTile(
    BuildContext context,
    PendingChatAttachment attachment,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final extensionLabel = attachment.extension.isEmpty
        ? 'ARCHIVO'
        : attachment.extension.toUpperCase();
    final removalBlocked =
        attachment.outcomeUnknown && !attachment.canRetrySafely;
    final isPurchaseDocument = attachment.purchaseInvoiceId != null;

    return SizedBox(
      width: 112,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Tooltip(
            message: isPurchaseDocument ? 'Ver o editar el documento' : '',
            child: InkWell(
              onTap: isPurchaseDocument
                  ? () => _openPurchaseDocumentPreview(attachment)
                  : null,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 112,
                height: 82,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: attachment.isImage
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            attachment.bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(7, 12, 7, 5),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withValues(alpha: 0.62),
                                  ],
                                ),
                              ),
                              child: Text(
                                attachment.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _getFileIcon(attachment.extension),
                              size: 24,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              attachment.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$extensionLabel · ${_formatAttachmentSize(attachment.bytes.length)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 9.5,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            top: -7,
            right: -7,
            child: Tooltip(
              message: removalBlocked
                  ? _pendingAttachmentMutationBlockedMessage
                  : 'Quitar adjunto',
              child: IgnorePointer(
                ignoring: _isSendingPendingAttachments || removalBlocked,
                child: AnimatedOpacity(
                  opacity:
                      _isSendingPendingAttachments || removalBlocked ? 0.45 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: Material(
                    color: colorScheme.surface,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _removePendingAttachment(attachment.id),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: Icon(
                          removalBlocked ? Icons.lock_outline : Icons.close,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isSendingPendingAttachments)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.58),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          if (attachment.outcomeUnknown && !_isSendingPendingAttachments)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        colorScheme.tertiaryContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.help_outline_rounded,
                    color: colorScheme.onTertiaryContainer,
                    size: 24,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatAttachmentSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  Widget _buildEmojiOverlay(BuildContext overlayContext) {
    final overlayBox = Overlay.of(
      overlayContext,
    ).context.findRenderObject() as RenderBox?;
    final buttonBox = _composerActionsButtonKey.currentContext
        ?.findRenderObject() as RenderBox?;

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
          border: Border.all(color: theme.colorScheme.outlineVariant),
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
            color: selected
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color:
                  selected ? theme.colorScheme.onSurface : Colors.grey.shade500,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: theme.colorScheme.outlineVariant),
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
                color: theme.colorScheme.onSurfaceVariant,
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
        border:
            Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
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
                    color: selected
                        ? theme.colorScheme.surfaceContainerHighest
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    item.icon,
                    size: 19,
                    color: selected
                        ? _accentBlue
                        : theme.colorScheme.onSurfaceVariant,
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
        backgroundColor: VinabikeThemeRoles.of(context).success.accent,
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: VinabikeThemeRoles.of(context).danger.accent),
    );
  }

  Color _getNameColor(String name) {
    if (name == 'Cliente') return Colors.blue[800]!;

    final colors = [
      VinabikeThemeRoles.of(context).warning.onContainer!,
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
    // La tinta va SOBRE la burbuja, y la burbuja sale de la paleta. Con
    // `theme.colorScheme.onSurface` fijo el texto quedaba negro sobre una burbuja oscura.
    final theme = Theme.of(context);
    final roles = theme.extension<VinabikeThemeRoles>();
    final onBubble = isMe
        ? roles?.onSelectionContainer ?? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
    if (preview == null) {
      return ParsedMessageText(
        text: message.content,
        isMe: isMe,
        onReferenceTap: widget.onReferenceTap,
        style: TextStyle(
          color: onBubble,
          fontSize: 14,
        ),
      );
    }

    final textStyle = TextStyle(color: onBubble, fontSize: 14);
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

  _MessageGrouping _messageGroupingFor(
    Message message,
    List<Message> messages,
  ) {
    final index =
        messages.indexWhere((candidate) => candidate.id == message.id);
    if (index < 0) return const _MessageGrouping();
    final previous = index > 0 ? messages[index - 1] : null;
    final next = index + 1 < messages.length ? messages[index + 1] : null;
    return _MessageGrouping(
      withPrevious:
          previous != null && _messagesBelongToSameGroup(previous, message),
      withNext: next != null && _messagesBelongToSameGroup(message, next),
    );
  }

  bool _messagesBelongToSameGroup(Message older, Message newer) {
    if (older.type == 'system' ||
        newer.type == 'system' ||
        older.type == 'action_request' ||
        newer.type == 'action_request') {
      return false;
    }
    if (older.isMe != newer.isMe || older.senderId != newer.senderId) {
      return false;
    }
    if (older.createdAt.year != newer.createdAt.year ||
        older.createdAt.month != newer.createdAt.month ||
        older.createdAt.day != newer.createdAt.day) {
      return false;
    }
    final gap = newer.createdAt.difference(older.createdAt);
    return !gap.isNegative && gap <= const Duration(minutes: 4);
  }

  Widget _buildMessageBubble(
    BuildContext context,
    Message msg,
    List<Message> messages,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMe = msg.isMe;
        final isThreadReply =
            widget.conversation.isInternal && msg.isThreadReply;
        final contentIsMe = isThreadReply ? false : isMe;
        final senderId = msg.senderId;
        final grouping = _messageGroupingFor(msg, messages);
        final bubbleMaxWidth =
            constraints.maxWidth > 0 ? constraints.maxWidth * 0.72 : 280.0;

        return FutureBuilder<Map<String, dynamic>?>(
          future:
              senderId != null ? _getSenderInfo(senderId) : Future.value(null),
          builder: (context, snapshot) {
            final senderInfo = snapshot.data;
            final senderName =
                isMe ? 'Tú' : _resolveIncomingSenderName(msg, senderInfo);
            final senderAvatar = senderInfo?['avatar_url']?.toString();
            // Message Content Widget
            Widget contentWidget;
            if (msg.type == 'image') {
              final mediaUrl = _messageAttachmentUrl(msg);
              if (mediaUrl != null) {
                contentWidget = _buildImageMessage(context, msg, url: mediaUrl);
              } else if (MessagingAttachmentService.hasPrivateReference(msg) ||
                  _messageHasRemoteWhatsAppMedia(msg)) {
                contentWidget = _buildDeferredWhatsAppImageMessage(
                  context,
                  msg,
                );
              } else if (_messagingAttachmentService
                      .externalUrlCandidate(msg) !=
                  null) {
                contentWidget = _buildExternalAttachmentMessage(msg);
              } else if (ChatMediaCache.keyFor(msg) != null) {
                // A file this device holds — the composer's own copy of a
                // photo just sent — before the server has named it.
                contentWidget = _buildImageMessage(context, msg);
              } else {
                contentWidget = _buildImageUnavailableMessage(
                  title: 'Imagen sin archivo',
                  subtitle: 'El mensaje no trae una URL válida.',
                );
              }
            } else if (msg.metadata['type'] == 'quote_request') {
              contentWidget = _buildQuoteCard(context, msg, contentIsMe);
            } else if (msg.type == 'audio' ||
                _messageAttachmentContentType(msg)
                    .toLowerCase()
                    .startsWith('audio/')) {
              contentWidget = ChatAudioMessage(
                key: ValueKey('audio-${msg.id}'),
                message: msg,
                isMe: contentIsMe,
                resolveUrl: () => _resolveWhatsAppMediaUrl(msg, playback: true),
              );
            } else if (msg.type == 'file') {
              final fileUrl = _messageAttachmentUrl(msg);
              if (fileUrl != null) {
                contentWidget =
                    _buildFileMessage(context, msg, fileUrl, contentIsMe);
              } else if (MessagingAttachmentService.hasPrivateReference(msg) ||
                  _messageHasRemoteWhatsAppMedia(msg) ||
                  ChatMediaCache.keyFor(msg) != null) {
                contentWidget = _buildDeferredWhatsAppFileMessage(
                  context,
                  msg,
                  contentIsMe,
                );
              } else if (_messagingAttachmentService
                      .externalUrlCandidate(msg) !=
                  null) {
                contentWidget = _buildExternalAttachmentMessage(msg);
              } else {
                contentWidget = _buildFileMessage(
                  context,
                  msg,
                  null,
                  contentIsMe,
                  failed: true,
                );
              }
            } else if (msg.type == 'action_request') {
              // Staff see the request and its customer response, but never
              // answer an action card on the customer's behalf.
              contentWidget =
                  _buildActionRequestCard(context, msg, contentIsMe);
            } else {
              // Text Message
              contentWidget =
                  _buildRouteShareMessage(context, msg, contentIsMe);
            }

            final fileCaption =
                msg.type == 'file' ? _messageFileCaption(msg) : null;
            if (fileCaption != null) {
              contentWidget = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  contentWidget,
                  const SizedBox(height: 6),
                  Text(fileCaption,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 13,
                          height: 1.25)),
                ],
              );
            }

            final quote = MessageReply.fromMetadata(msg, messages);
            if (quote != null) {
              contentWidget = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [_buildMessageQuote(quote), contentWidget],
              );
            }

            // Timestamp
            final timeStr = DateFormat('HH:mm').format(msg.createdAt);

            if (isThreadReply) {
              return _buildTaskThreadReply(
                context,
                message: msg,
                isMe: isMe,
                senderName: senderName,
                senderAvatar: senderAvatar,
                timeLabel: timeStr,
                content: contentWidget,
              );
            }

            // Bubble Decoration
            // Las burbujas salen de la PALETA elegida en Apariencia, no de un
            // hex. Antes eran `0xFFD9FDD3` y blanco fijos, así que en modo
            // oscuro se veían idénticas al claro —dos manchas claras sobre un
            // fondo oscuro— y no seguían la paleta.
            //
            // `selectionContainer` es el rol correcto para la propia: su
            // contrato dice que es para un bloque que se lee «como elegido o
            // como propio del operador». La ajena usa una superficie neutra
            // elevada, que es lo que es.
            final theme = Theme.of(context);
            final roles = theme.extension<VinabikeThemeRoles>();
            final bubbleColor = isMe
                ? roles?.selectionContainer ??
                    theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHigh;
            final onBubbleColor = isMe
                ? roles?.onSelectionContainer ??
                    theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurface;
            final bubbleDecoration = BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(grouping.withPrevious ? 5 : 12),
                topRight: Radius.circular(grouping.withPrevious ? 5 : 12),
                bottomLeft: Radius.circular(
                  grouping.withNext
                      ? 5
                      : isMe
                          ? 12
                          : 2,
                ),
                bottomRight: Radius.circular(
                  grouping.withNext
                      ? 5
                      : isMe
                          ? 2
                          : 12,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  // La sombra sale del rol, no de negro fijo: sobre un lienzo
                  // oscuro un negro al 8% no separa nada.
                  color: roles?.shadow ??
                      theme.colorScheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ],
            );

            if (!isMe) {
              // INCOMING MESSAGE
              return SelectionArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: grouping.withNext ? 3 : 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar
                      if (grouping.withPrevious)
                        const SizedBox(width: 28)
                      else
                        CircleAvatar(
                          radius: 14,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          backgroundImage: senderAvatar != null
                              ? NetworkImage(senderAvatar)
                              : null,
                          child: senderAvatar == null
                              ? Icon(
                                  Icons.person,
                                  size: 16,
                                  color: theme.colorScheme.onSurfaceVariant,
                                )
                              : null,
                        ),
                      const SizedBox(width: 8),

                      // Bubble
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Builder(
                              builder: (bubbleContext) => GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onLongPress: () => _showMessageActions(
                                  bubbleContext,
                                  msg,
                                  isMe: false,
                                ),
                                onSecondaryTap: () => _showMessageActions(
                                  bubbleContext,
                                  msg,
                                  isMe: false,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  constraints: BoxConstraints(
                                    maxWidth: bubbleMaxWidth,
                                  ),
                                  decoration: bubbleDecoration,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Sender Name (Colored)
                                      if (!grouping.withPrevious) ...[
                                        Text(
                                          senderName,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: _getNameColor(senderName),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                      ],

                                      contentWidget,

                                      // Timestamp
                                      Align(
                                        alignment: Alignment.bottomRight,
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                              top: 4, left: 8),
                                          child: Text(
                                            timeStr,
                                            style: TextStyle(
                                              color: onBubbleColor.withValues(
                                                  alpha: 0.65),
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            _buildReactionStrip(context, msg, isMe: false),
                          ],
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
              );
            }

            // OUTGOING MESSAGE
            return SelectionArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: grouping.withNext ? 3 : 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 40),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Builder(
                            builder: (bubbleContext) => GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onLongPress: () => _showMessageActions(
                                bubbleContext,
                                msg,
                                isMe: true,
                              ),
                              onSecondaryTap: () => _showMessageActions(
                                bubbleContext,
                                msg,
                                isMe: true,
                              ),
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
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (msg.metadata[
                                                  'recovered_outbound_attempt'] ==
                                              true) ...[
                                            _buildRecoveredMetaAttemptNotice(
                                                msg),
                                            const SizedBox(height: 5),
                                          ],
                                          contentWidget,
                                        ],
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: _buildOutgoingMessageFooter(
                                        msg,
                                        timeStr,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          _buildReactionStrip(context, msg, isMe: true),
                        ],
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

  /// Presentación de una respuesta dentro del hilo canónico de una tarea.
  ///
  /// A diferencia de un chat de ida y vuelta, todas las respuestas cuelgan de
  /// la misma raíz y por eso comparten una sola columna. El autor y la hora se
  /// mantienen visibles sin convertir cada respuesta en una burbuja aislada.
  Widget _buildTaskThreadReply(
    BuildContext context, {
    required Message message,
    required bool isMe,
    required String senderName,
    required String? senderAvatar,
    required String timeLabel,
    required Widget content,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final avatarUrl = senderAvatar?.trim();

    return Semantics(
      container: true,
      label: 'Respuesta de $senderName en el hilo',
      child: SelectionArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 9, 2, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: colorScheme.surfaceContainerHighest,
                backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null || avatarUrl.isEmpty
                    ? Icon(
                        Icons.person_outline,
                        size: 16,
                        color: colorScheme.onSurfaceVariant,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Builder(
                  builder: (replyContext) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onLongPress: () => _showMessageActions(
                      replyContext,
                      message,
                      isMe: false,
                    ),
                    onSecondaryTap: () => _showMessageActions(
                      replyContext,
                      message,
                      isMe: false,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                senderName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: isMe
                                      ? colorScheme.primary
                                      : colorScheme.onSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (isMe)
                              _buildOutgoingMessageFooter(message, timeLabel)
                            else
                              Text(
                                timeLabel,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        if (message.metadata['recovered_outbound_attempt'] ==
                            true) ...[
                          _buildRecoveredMetaAttemptNotice(message),
                          const SizedBox(height: 5),
                        ],
                        content,
                        _buildReactionStrip(
                          context,
                          message,
                          isMe: false,
                        ),
                        Divider(
                          height: 18,
                          color: colorScheme.outlineVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  /// Los chips de reacción, colgando del borde inferior de la burbuja como en
  /// WhatsApp. El margen negativo es lo que produce el solape característico;
  /// sin él quedan flotando y se leen como otro mensaje.
  ///
  /// Un chip propio se marca y volver a tocarlo la retira, que es la regla de
  /// WhatsApp: una reacción por persona, no un contador acumulable.
  Widget _buildReactionStrip(
    BuildContext context,
    Message msg, {
    required bool isMe,
  }) {
    final provider = context.watch<ChatProvider>();
    final groups = provider.reactionGroupsFor(msg.id);
    if (groups.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    // El solape va por traslación y no por padding negativo: `RenderPadding`
    // exige valores no negativos y un `top: -6` revienta apenas se pinta.
    return Transform.translate(
      offset: const Offset(0, -6),
      child: Padding(
        padding: EdgeInsets.only(
          left: isMe ? 0 : 8,
          right: isMe ? 8 : 0,
          bottom: 2,
        ),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          alignment: isMe ? WrapAlignment.end : WrapAlignment.start,
          children: [
            for (final group in groups)
              Tooltip(
                message: group.tooltip,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _toggleReaction(msg, group.emoji),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    // Los dos chips se ven igual, entrante o saliente. La única
                    // diferencia es un tinte suave cuando la reacción es tuya:
                    // el anillo de color fuerte los hacía parecer controles
                    // distintos según de qué lado colgaran.
                    decoration: BoxDecoration(
                      color: group.includesCurrentUser
                          ? theme.colorScheme.primaryContainer
                              .withValues(alpha: 0.55)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 1,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(group.emoji, style: const TextStyle(fontSize: 13)),
                        if (group.count > 1) ...[
                          const SizedBox(width: 3),
                          Text(
                            '${group.count}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
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

  /// Los seis de WhatsApp, en su orden. No es un selector de emoji completo a
  /// propósito: la reacción rápida vive de ser un gesto, no de un buscador.
  /// Valor que devuelve el «+». No es un emoji, así que no puede chocar con
  /// uno elegido de verdad.
  static const String _moreReactionsSentinel = '__mas_emojis__';

  static const List<String> _quickReactionEmojis = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
  ];

  /// Abre la barra rápida COLGADA DE LA BURBUJA, como en WhatsApp: justo
  /// encima del mensaje y alineada a su lado, no donde cayó el dedo.
  ///
  /// [context] tiene que ser el de la burbuja —por eso cada una va envuelta en
  /// un `Builder`—: anclarla al contexto del constructor la pegaba al borde de
  /// la fila completa, que es ancho, y la barra quedaba flotando lejos del
  /// mensaje al que pertenece.
  ///
  /// Se usa `useRootNavigator` porque el menú, en el navegador anidado, se
  /// acomoda dentro del overlay del área de contenido —que no incluye el rail
  /// derecho— y terminaba dibujado sobre el dashboard.
  Future<void> _showMessageActions(
    BuildContext context,
    Message msg, {
    required bool isMe,
  }) async {
    final overlay = Overlay.of(context, rootOverlay: true)
        .context
        .findRenderObject() as RenderBox?;
    final bubble = context.findRenderObject() as RenderBox?;
    if (overlay == null || bubble == null || !bubble.hasSize) return;

    const emojiSlot = 30.0;
    const barHeight = 40.0;
    const gap = 6.0;
    // +1 por el botón «+», que abre el catálogo completo igual que WhatsApp:
    // los seis rápidos son un atajo, no el límite de lo que se puede poner.
    final barWidth = (_quickReactionEmojis.length + 1) * emojiSlot + 10.0;

    final origin = bubble.localToGlobal(Offset.zero, ancestor: overlay);
    final bubbleRect = origin & bubble.size;

    // Alineada al lado del que sale la burbuja, igual que WhatsApp.
    var left = isMe ? bubbleRect.right - barWidth : bubbleRect.left;
    // Encima del mensaje; si no cabe arriba, se pasa abajo en vez de salirse.
    var top = bubbleRect.top - barHeight - gap;
    if (top < 0) top = bubbleRect.bottom + gap;

    left = left.clamp(
      0.0,
      (overlay.size.width - barWidth).clamp(0.0, double.infinity),
    );
    top = top.clamp(
      0.0,
      (overlay.size.height - barHeight).clamp(0.0, double.infinity),
    );

    final mine = context.read<ChatProvider>().myReactionFor(msg.id);
    final theme = Theme.of(context);

    final selected = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromLTRB(
        left,
        top,
        overlay.size.width - left - barWidth,
        overlay.size.height - top,
      ),
      constraints: BoxConstraints(minWidth: barWidth, maxWidth: barWidth),
      items: [
        if (_canQuoteMessage(msg))
          const PopupMenuItem<String>(value: 'reply', child: Text('Responder')),
        if (msg.content.isNotEmpty)
          const PopupMenuItem<String>(
              value: 'copy', child: Text('Copiar mensaje')),
        _MessageReactionsMenuEntry(
          height: barHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final emoji in _quickReactionEmojis)
                Semantics(
                    container: true,
                    button: true,
                    label: 'Reaccionar con $emoji',
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).pop(emoji),
                    child: ExcludeSemantics(
                        child: InkWell(
                      borderRadius: BorderRadius.circular(15),
                      onTap: () =>
                          Navigator.of(context, rootNavigator: true).pop(emoji),
                      child: Container(
                        width: emojiSlot,
                        height: emojiSlot,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          // El que ya pusiste se ve elegido; tocarlo lo retira.
                          color: emoji == mine
                              ? theme.colorScheme.primaryContainer
                              : Colors.transparent,
                        ),
                        child:
                            Text(emoji, style: const TextStyle(fontSize: 17)),
                      ),
                    ))),
              InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: () => Navigator.of(context, rootNavigator: true)
                    .pop(_moreReactionsSentinel),
                child: Container(
                  width: emojiSlot,
                  height: emojiSlot,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (selected == null ||
        !mounted ||
        msg.conversationId != widget.conversation.id) return;
    if (selected == 'reply') {
      _selectReply(msg);
      return;
    }
    if (selected == 'copy') {
      await Clipboard.setData(ClipboardData(text: msg.content));
      return;
    }
    if (selected == _moreReactionsSentinel) {
      if (!mounted) return;
      _openEmojiPickerForReaction(msg);
      return;
    }
    await _toggleReaction(msg, selected);
  }

  Future<void> _toggleReaction(Message msg, String emoji) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await context.read<ChatProvider>().toggleMyReaction(
            message: msg,
            emoji: emoji,
          );
    } catch (error) {
      debugPrint('No se pudo cambiar la reacción: $error');
      messenger?.showSnackBar(
        const SnackBar(content: Text('No se pudo cambiar la reacción')),
      );
    }
  }

  Widget _buildOutgoingMessageFooter(
    Message msg,
    String timeStr,
  ) {
    final deliveryState = MessageDeliveryState.fromMessage(msg);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
        if (deliveryState.isVisible) ...[
          const SizedBox(width: 4),
          MessageDeliveryIndicator(state: deliveryState, size: 14),
        ],
      ],
    );
  }

  Widget _buildRecoveredMetaAttemptNotice(Message message) {
    final state = message.metadata['meta_attempt_state']?.toString();
    final (label, icon, color) = switch (state) {
      'prepared' => (
          'Preparado, resultado incierto · no reenviar',
          Icons.help_outline_rounded,
          const Color(0xFF9A6700),
        ),
      'provider_accepted'
          when message.metadata['external_message_id'] != null =>
        (
          'Aceptado por Meta · pendiente de registro',
          Icons.cloud_done_outlined,
          const Color(0xFF1D4ED8),
        ),
      'provider_rejected' => (
          'Rechazado por Meta',
          Icons.error_outline_rounded,
          const Color(0xFFB42318),
        ),
      'preflight_failed' => (
          'El envío no se inició · corrige y reintenta',
          Icons.report_gmailerrorred_outlined,
          const Color(0xFFB42318),
        ),
      _ => (
          'Resultado incierto · no reenviar',
          Icons.help_outline_rounded,
          const Color(0xFF9A6700),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteCard(BuildContext context, Message msg, bool isMe) {
    final isConfirmed = msg.metadata['status'] == 'confirmed';

    // High contrast colors for both sender (green bubble) and receiver (white bubble)
    // On green bubble (isMe), we use Dark Green/Black text.
    // On white bubble (!isMe), we use Green/Black text.
    final headerIconColor = isMe
        ? VinabikeThemeRoles.of(context).success.onContainer
        : VinabikeThemeRoles.of(context).success.accent;
    final headerTextColor = isMe
        ? VinabikeThemeRoles.of(context).success.onContainer
        : VinabikeThemeRoles.of(context).success.onContainer;
    final headerBgColor = isMe
        ? Colors.black.withValues(alpha: 0.05)
        : VinabikeThemeRoles.of(context).success.container;

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
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface, // Always dark for readability
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

        // Legacy quote messages are intentionally read-only. A workshop
        // decision must be sent as an action_request linked to a mechanic job
        // so the audited quotation command owns the transition.
        if (!isMe && !isConfirmed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Icon(Icons.history,
                    size: 15,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Mensaje histórico. La aprobación actual se registra desde la solicitud vinculada al trabajo.',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),

        if (isConfirmed)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text('✅ Confirmado',
                  style: TextStyle(
                      color: VinabikeThemeRoles.of(context)
                          .success
                          .onContainer, // Always visible
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }

  Widget _buildActionRequestCard(BuildContext context, Message msg, bool isMe) {
    final actionType = msg.metadata['action_type'] as String? ?? 'unknown';
    final status = msg.metadata['status'] as String? ?? 'pending';
    final responseNote = msg.metadata['response_note']?.toString().trim();

    // Determine card appearance based on action type
    IconData icon;
    String title;
    Color accentColor;

    // Contrast Logic:
    // Bubbles are Light Green (Me) or White (Other).
    // Text should ALWAYS be dark (Black/Dark Grey).
    // Feature colors (icons/titles) should be dark versions of their accent.

    Color iconColor;
    Color titleColor = Theme.of(context).colorScheme.onSurface;
    Color headerBgColor = isMe
        ? Colors.black.withValues(alpha: 0.05)
        : Theme.of(context).colorScheme.surfaceContainerLow!;

    switch (actionType) {
      case 'approve_quote':
        icon = Icons.description;
        if (status == 'accepted') {
          title = 'Presupuesto Aprobado';
          accentColor = VinabikeThemeRoles.of(context).success.accent;
        } else if (status == 'declined') {
          title = 'Presupuesto Rechazado';
          accentColor = VinabikeThemeRoles.of(context).danger.accent;
        } else {
          title = 'Presupuesto Enviado';
          accentColor = VinabikeThemeRoles.of(context).warning.accent;
        }
        // Use darker shade for icon to ensure visibility on light green
        iconColor = isMe ? Colors.black54 : accentColor;
        break;
      case 'pay_now':
        icon = Icons.payment;
        title = 'Solicitud de Pago';
        accentColor = VinabikeThemeRoles.of(context).success.accent;
        iconColor = isMe
            ? VinabikeThemeRoles.of(context).success.onContainer!
            : accentColor; // Visible green on green
        break;
      case 'confirm_delivery':
        icon = Icons.local_shipping;
        title = 'Confirmar Entrega';
        accentColor = Colors.blue;
        iconColor =
            isMe ? Colors.blue[900]! : accentColor; // Visible blue on green
        break;
      default:
        icon = Icons.help_outline;
        title = 'Acción Requerida';
        accentColor = Colors.grey;
        iconColor = Theme.of(context).colorScheme.onSurfaceVariant!;
    }

    // Build status badge
    Widget statusBadge = const SizedBox.shrink();
    if (status == 'accepted') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (isMe
                  ? Colors.black
                  : VinabikeThemeRoles.of(context).success.accent)
              .withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: VinabikeThemeRoles.of(context)
                  .success
                  .accent
                  .withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                size: 14,
                color: VinabikeThemeRoles.of(context).success.onContainer),
            const SizedBox(width: 4),
            Text('Aceptado',
                style: TextStyle(
                    fontSize: 12,
                    color: VinabikeThemeRoles.of(context).success.onContainer,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else if (status == 'declined') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (isMe
                  ? Colors.black
                  : VinabikeThemeRoles.of(context).danger.accent)
              .withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: VinabikeThemeRoles.of(context)
                  .danger
                  .accent
                  .withValues(alpha: 0.5)),
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
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 13,
                height: 1.4),
          ),
        ),
        if (responseNote != null && responseNote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notes_outlined, size: 16),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    responseNote,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (status == 'pending')
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Icon(Icons.schedule_outlined, size: 16, color: accentColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isMe
                        ? 'Esperando respuesta del cliente.'
                        : 'Solicitud recibida. El equipo no puede responder en nombre del cliente.',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A row of independent actions must not inherit PopupMenuItem's
/// MergeSemantics, which turns every emoji into one inaccessible action.
class _MessageReactionsMenuEntry extends PopupMenuEntry<String> {
  const _MessageReactionsMenuEntry({required this.height, required this.child});

  @override
  final double height;
  final Widget child;

  @override
  bool represents(String? value) => false;

  @override
  State<_MessageReactionsMenuEntry> createState() =>
      _MessageReactionsMenuEntryState();
}

class _MessageReactionsMenuEntryState
    extends State<_MessageReactionsMenuEntry> {
  @override
  Widget build(BuildContext context) =>
      SizedBox(height: widget.height, child: widget.child);
}
