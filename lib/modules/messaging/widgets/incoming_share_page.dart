import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/incoming_share_service.dart';
import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../storage/models/app_stored_file.dart';
import '../../storage/services/app_file_storage_service.dart';
import '../models/chat_attachment_draft.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../utils/conversation_channel_presentation.dart';
import '../utils/incoming_share_intake.dart';
import 'counterparty_avatar_image.dart';

/// Lo que se abre al elegir «vb-ERP» en el menú Compartir del teléfono.
///
/// Dos destinos: un chat de WhatsApp del ERP, o la biblioteca de Archivos.
/// **Elegir el chat no envía.** Los archivos quedan en el compositor de ese
/// chat, donde el operador los revisa, les escribe un texto y aprieta enviar;
/// es la misma regla del reenvío y de todo borrador preparado fuera del chat.
class IncomingSharePage extends StatefulWidget {
  const IncomingSharePage({
    super.key,
    required this.batch,
    required this.service,
  });

  final IncomingShareBatch batch;
  final IncomingShareService service;

  @override
  State<IncomingSharePage> createState() => _IncomingSharePageState();
}

class _IncomingSharePageState extends State<IncomingSharePage> {
  late final List<IncomingShareItem> _items =
      IncomingShareIntake.classify(widget.batch.files);
  final TextEditingController _search = TextEditingController();
  final Set<int> _savedToFiles = {};
  Timer? _warmup;
  bool _warming = false;
  bool _busy = false;
  bool _handedOff = false;
  String? _error;

  List<IncomingShareItem> get _sendable =>
      _items.where((item) => item.canSendByWhatsApp).toList();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    final chat = context.read<ChatProvider>();
    // Si la app se abrió desde el menú Compartir, la bandeja puede no haber
    // cargado —ni tener la sesión lista— todavía. La lista aparece apenas
    // llega; mientras tanto se espera un rato antes de afirmar que no hay chats.
    if (chat.conversations.isEmpty) {
      _warming = true;
      _warmup = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _warming = false);
      });
      unawaited(chat.loadConversations());
    }
  }

  @override
  void dispose() {
    _warmup?.cancel();
    _search.dispose();
    // Cerrar sin elegir descarta la copia en caché; un envío o un guardado
    // ya leyeron los bytes que necesitaban.
    unawaited(widget.service.release(widget.batch));
    super.dispose();
  }

  Future<void> _sendTo(Conversation conversation) async {
    if (_busy || _handedOff) return;
    final sendable = _sendable;
    if (sendable.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final attachments = <PendingChatAttachment>[];
      for (var index = 0; index < sendable.length; index++) {
        final item = sendable[index];
        final bytes = await XFile(item.file.path).readAsBytes();
        attachments.add(
          PendingChatAttachment(
            id: 'shared-$stamp-$index',
            fileName: item.file.name,
            bytes: bytes,
            extension: item.validation!.extension,
            isImage: item.validation!.contentType.startsWith('image/'),
          ),
        );
      }
      if (!mounted) return;
      final chat = context.read<ChatProvider>();
      final toolbar = context.read<RightToolbarService>();
      chat.offerComposerAttachments(conversation.id, attachments);
      _handedOff = true;
      Navigator.of(context).pop();
      // La misma bandeja que abre una notificación del teléfono: el rail
      // derecho en escritorio, pantalla completa en compacto.
      toolbar.openConversation(
        tool: conversation.isSupplierConversation
            ? ToolbarTool.supplierMessages
            : ToolbarTool.messages,
        conversationId: conversation.id,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudieron leer los archivos. Vuelve a compartirlos.';
      });
    }
  }

  Future<void> _saveToFiles() async {
    if (_busy || _handedOff) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final toolbar = context.read<RightToolbarService>();
    String? failedName;
    for (var index = 0; index < _items.length; index++) {
      if (_savedToFiles.contains(index)) continue;
      final file = _items[index].file;
      try {
        final Uint8List bytes = await XFile(file.path).readAsBytes();
        await AppFileStorageService.instance.saveFile(
          bytes: bytes,
          fileName: file.name,
          mimeType: file.mimeType,
          context: const AppFileContext(
            sourceType: 'manual',
            sourceProvider: 'phone_share',
            sourceRoute: '/storage',
            contextType: 'manual',
            contextTitle: 'Compartido desde el teléfono',
          ),
        );
        // Un reintento no vuelve a subir lo que ya quedó guardado.
        _savedToFiles.add(index);
      } catch (_) {
        failedName = file.name;
        break;
      }
    }
    if (!mounted) return;
    if (failedName != null) {
      setState(() {
        _busy = false;
        _error = _savedToFiles.isEmpty
            ? 'No se pudo guardar $failedName. Revisa la conexión e intenta de nuevo.'
            : 'Se guardaron ${_savedToFiles.length} de ${_items.length}. '
                'No se pudo guardar $failedName; intenta de nuevo.';
      });
      return;
    }
    _handedOff = true;
    Navigator.of(context).pop();
    final count = _savedToFiles.length;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count == 1
              ? 'Guardado en Archivos.'
              : '$count archivos guardados en Archivos.',
        ),
        action: SnackBarAction(
          label: 'Ver',
          onPressed: () => toolbar.openTool(ToolbarTool.storage),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chat = context.watch<ChatProvider>();
    final destinations = IncomingShareIntake.destinations(
      chat.conversations,
      query: _search.text,
      titleFor: chat.getChatTitle,
    );
    final rejected = _items.where((item) => !item.canSendByWhatsApp).toList();
    final canSend = _sendable.isNotEmpty;
    final fileCount = widget.batch.files.length;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          // El AppBar del tema es navy con tinta blanca; esta pantalla es
          // clara. Sin esto, la X y los iconos del sistema quedaban blancos
          // sobre blanco (emulador Android, 2026-09-29).
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          iconTheme: IconThemeData(color: scheme.onSurface),
          actionsIconTheme: IconThemeData(color: scheme.onSurface),
          systemOverlayStyle: vinabikeSystemOverlayStyleFor(scheme.surface),
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            key: const ValueKey('incoming-share-close'),
            tooltip: 'Descartar',
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Compartir en el ERP',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                fileCount == 1 ? '1 archivo' : '$fileCount archivos',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          bottom: _busy
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: [
              if (_items.isNotEmpty)
                SliverToBoxAdapter(child: _SharedFilesStrip(items: _items)),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: VbNotice(
                      tone: VbNoticeTone.danger,
                      title: 'No se completó',
                      body: _error,
                    ),
                  ),
                ),
              if (rejected.isNotEmpty || widget.batch.skipped.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: VbNotice(
                      tone: VbNoticeTone.warning,
                      title: canSend
                          ? 'Algunos archivos no van por WhatsApp'
                          : 'Estos archivos no van por WhatsApp',
                      body: [
                        for (final item in rejected)
                          '${item.file.name}: ${item.whatsAppProblem}',
                        for (final skip in widget.batch.skipped)
                          '${skip.name}: ${skip.explanation}',
                      ].join('\n'),
                    ),
                  ),
                ),
              if (_items.isNotEmpty)
                SliverToBoxAdapter(
                  child: _DestinationTile(
                    key: const ValueKey('incoming-share-save-files'),
                    icon: Icons.folder_outlined,
                    title: 'Guardar en Archivos',
                    subtitle: 'La biblioteca de archivos del ERP',
                    enabled: !_busy,
                    onTap: _saveToFiles,
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Text(
                    'Enviar por WhatsApp',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
              if (canSend)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      key: const ValueKey('incoming-share-search'),
                      controller: _search,
                      enabled: !_busy,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Buscar cliente, proveedor o teléfono',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
              if (canSend)
                _conversationSliver(context, chat, destinations)
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Text(
                      'Guárdalos en Archivos, o conviértelos a un formato que '
                      'WhatsApp acepte y vuelve a compartirlos.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _conversationSliver(
    BuildContext context,
    ChatProvider chat,
    List<Conversation> destinations,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (destinations.isEmpty) {
      final loading = _warming && chat.conversations.isEmpty;
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Text(
                  _search.text.trim().isEmpty
                      ? 'No hay chats de WhatsApp abiertos.'
                      : 'Ningún chat coincide con «${_search.text.trim()}».',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
        ),
      );
    }
    return SliverList.builder(
      itemCount: destinations.length,
      itemBuilder: (context, index) {
        final conversation = destinations[index];
        return _ConversationDestinationTile(
          conversation: conversation,
          title: chat.getChatTitle(conversation),
          enabled: !_busy,
          onTap: () => _sendTo(conversation),
        );
      },
    );
  }
}

/// Miniaturas de lo compartido: la foto misma, o el tipo y el peso de un
/// documento. Lo que no va por WhatsApp se marca, sin esconderlo.
class _SharedFilesStrip extends StatelessWidget {
  const _SharedFilesStrip({required this.items});

  final List<IncomingShareItem> items;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _SharedFileCard(item: items[index]),
      ),
    );
  }
}

class _SharedFileCard extends StatelessWidget {
  const _SharedFileCard({required this.item});

  final IncomingShareItem item;

  static const double _size = 88;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final file = item.file;

    return Semantics(
      label: item.canSendByWhatsApp
          ? file.name
          : '${file.name}. No va por WhatsApp: ${item.whatsAppProblem}',
      child: ExcludeSemantics(
        child: SizedBox(
          width: _size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    width: _size,
                    height: _size,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: roles.hairline),
                    ),
                    child: file.isImage
                        ? _ImageThumbnail(path: file.path)
                        : _DocumentGlyph(file: file),
                  ),
                  if (!item.canSendByWhatsApp)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: roles.warning.container,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.priority_high_rounded,
                          size: 14,
                          color: roles.warning.onContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageThumbnail extends StatefulWidget {
  const _ImageThumbnail({required this.path});

  final String path;

  @override
  State<_ImageThumbnail> createState() => _ImageThumbnailState();
}

class _ImageThumbnailState extends State<_ImageThumbnail> {
  late final Future<Uint8List> _bytes = XFile(widget.path).readAsBytes();

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return Icon(
            Icons.image_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          // Una foto de 12 MP decodificada completa pesa ~48 MB en memoria.
          cacheWidth: (_SharedFileCard._size * dpr).round(),
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Icon(
            Icons.broken_image_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}

class _DocumentGlyph extends StatelessWidget {
  const _DocumentGlyph({required this.file});

  final IncomingSharedFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dot = file.name.lastIndexOf('.');
    final extension = dot < 0 ? '' : file.name.substring(dot + 1).toUpperCase();
    final icon = switch (file.mimeType) {
      final type when type.startsWith('video/') => Icons.movie_outlined,
      final type when type.startsWith('audio/') => Icons.graphic_eq,
      'application/pdf' => Icons.picture_as_pdf_outlined,
      _ => Icons.description_outlined,
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 28, color: scheme.primary),
        const SizedBox(height: 6),
        Text(
          [
            if (extension.isNotEmpty) extension,
            _formatSize(file.sizeBytes),
          ].join(' · '),
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: scheme.onPrimaryContainer),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _ConversationDestinationTile extends StatelessWidget {
  const _ConversationDestinationTile({
    required this.conversation,
    required this.title,
    required this.enabled,
    required this.onTap,
  });

  final Conversation conversation;
  final String title;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hint = conversation.contextHint;
    final phone = (conversation.isSupplierConversation
            ? hint?.supplierPhone ?? hint?.phone
            : hint?.phone)
        ?.trim();
    final counterparty =
        conversation.isSupplierConversation ? 'Proveedor' : 'Cliente';
    final subtitle = [
      counterparty,
      if (phone != null && phone.isNotEmpty && phone != title) phone,
    ].join(' · ');
    final when = _formatWhen(conversation.lastMessageAt);

    return ListTile(
      key: ValueKey('incoming-share-chat-${conversation.id}'),
      enabled: enabled,
      onTap: onTap,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _Avatar(conversation: conversation, title: title),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: when == null
          ? null
          : Text(
              when,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
    );
  }

  static String? _formatWhen(DateTime? value) {
    if (value == null) return null;
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final days = today.difference(day).inDays;
    if (days == 0) {
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
    }
    if (days == 1) return 'ayer';
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${local.day} ${months[local.month - 1]}';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.conversation, required this.title});

  final Conversation conversation;
  final String title;

  @override
  Widget build(BuildContext context) {
    final accent = ConversationChannelPresentation.accent(conversation);
    final initials = _initials(title.split(' · ').first);
    // El verde de WhatsApp es oscuro: sobre el fondo oscuro las iniciales no
    // se leían. En oscuro se aclara la tinta, no el color del canal.
    final ink = Theme.of(context).brightness == Brightness.dark
        ? HSLColor.fromColor(accent).withLightness(0.72).toColor()
        : accent;
    final fallback = CircleAvatar(
      radius: 22,
      backgroundColor: accent.withValues(alpha: 0.12),
      child: Text(
        initials,
        style: TextStyle(
          color: ink,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
    final url = conversation.contextHint?.counterpartyImageUrl;
    return SizedBox(
      width: 44,
      height: 44,
      child: url == null || url.isEmpty
          ? fallback
          : CounterpartyAvatarImage(
              url: url,
              size: 44,
              isMark: conversation.isSupplierConversation,
              backdrop: accent.withValues(alpha: 0.10),
              fallback: fallback,
            ),
    );
  }

  static String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    if (RegExp(r'^\+?[0-9 ]+$').hasMatch(trimmed)) return '#';
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length == 1) {
      return words.first.characters.take(2).toString().toUpperCase();
    }
    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
  }
}
