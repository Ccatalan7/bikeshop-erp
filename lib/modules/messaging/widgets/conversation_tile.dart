import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../../../shared/services/route_share_service.dart';
import '../../../shared/services/image_service.dart';

class ConversationTile extends StatefulWidget {
  final Conversation conversation;
  final bool isActive;
  final bool isMobile;
  final bool isPinned;
  final String subtitle;
  final VoidCallback onTap;
  final Future<void> Function()? onTogglePinned;
  final Future<bool> Function() onDelete;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.isActive,
    required this.isMobile,
    this.isPinned = false,
    required this.subtitle,
    required this.onTap,
    this.onTogglePinned,
    required this.onDelete,
  });

  @override
  State<ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<ConversationTile> {
  bool _isHovering = false;

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final local = dt.toLocal();
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final localDate = DateTime(local.year, local.month, local.day);

    if (now.year == local.year &&
        now.month == local.month &&
        now.day == local.day) {
      return DateFormat.Hm().format(local);
    }

    if (localDate == yesterday) {
      return 'Ayer';
    }

    final diff = now.difference(local);
    if (diff.inDays < 7) {
      const weekdays = ['lun', 'mar', 'mie', 'jue', 'vie', 'sab', 'dom'];
      return weekdays[local.weekday - 1];
    }

    return DateFormat('dd/MM/yy').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final conv = widget.conversation;
    final title = provider.getChatTitle(conv);
    final hasUnread = conv.unreadCount > 0;
    final isPending = conv.status == 'pending';
    final accentColor = _channelColor(conv, isPending);
    const unreadColor = Color(0xFF16A34A);
    final timeColor = hasUnread
        ? unreadColor
        : colorScheme.onSurfaceVariant.withValues(alpha: 0.68);
    final backgroundColor = widget.isActive
        ? colorScheme.primary.withValues(alpha: 0.09)
        : hasUnread
            ? unreadColor.withValues(alpha: 0.075)
            : _isHovering
                ? colorScheme.onSurface.withValues(alpha: 0.035)
                : Colors.transparent;
    final leftEdgeColor = widget.isActive
        ? colorScheme.primary
        : hasUnread
            ? unreadColor
            : Colors.transparent;

    Widget content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border(
              left: BorderSide(
                color: leftEdgeColor,
                width: 3,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildAvatar(title, conv, accentColor, hasUnread),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                              fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w700,
                              color: colorScheme.onSurface,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatTime(conv.lastMessageAt ?? conv.updatedAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: timeColor,
                            fontWeight:
                                hasUnread ? FontWeight.w800 : FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (conv.lastMessageIsMine) ...[
                          _buildDeliveryIcon(conv),
                          const SizedBox(width: 4),
                        ],
                        if (_previewIcon(conv) != null) ...[
                          Icon(
                            _previewIcon(conv),
                            size: 14,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.72),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            _previewText(conv),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isPending
                                  ? const Color(0xFFB45309)
                                  : hasUnread
                                      ? colorScheme.onSurface
                                      : colorScheme.onSurfaceVariant,
                              fontWeight:
                                  hasUnread ? FontWeight.w700 : FontWeight.w500,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: _buildContextPills(
                            conv,
                            prominent: hasUnread,
                          ),
                        ),
                        if (widget.isPinned) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.push_pin,
                            size: 12,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildTrailing(conv, hasUnread, theme, unreadColor),
            ],
          ),
        ),
      ),
    );

    if (widget.isMobile) {
      return Dismissible(
        key: Key(conv.id),
        direction: DismissDirection.endToStart,
        background: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Icon(Icons.delete_outline, color: Colors.white),
        ),
        confirmDismiss: (_) => widget.onDelete(),
        child: content,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: content,
    );
  }

  Widget _buildAvatar(
    String title,
    Conversation conv,
    Color accentColor,
    bool hasUnread,
  ) {
    final initials = _initialsFor(title);
    final avatarUrl = conv.contextHint?.customerImageUrl?.trim();
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
    final fallbackAvatar = _buildInitialsAvatar(
      initials,
      accentColor,
      hasUnread,
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: hasAvatar
              ? ImageService.buildCachedImage(
                  imageUrl: avatarUrl,
                  width: 44,
                  height: 44,
                  isCircular: true,
                  placeholder: fallbackAvatar,
                  errorWidget: fallbackAvatar,
                )
              : fallbackAvatar,
        ),
        Positioned(
          right: -2,
          bottom: -1,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
            child: Icon(
              _channelIcon(conv),
              size: 12,
              color: accentColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInitialsAvatar(
    String initials,
    Color accentColor,
    bool hasUnread,
  ) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: accentColor.withValues(alpha: hasUnread ? 0.16 : 0.1),
      child: Text(
        initials,
        style: TextStyle(
          color: accentColor,
          fontWeight: FontWeight.w800,
          fontSize: initials.length > 1 ? 12 : 15,
          letterSpacing: 0,
        ),
      ),
    );
  }

  Widget _buildContextPills(
    Conversation conv, {
    bool prominent = false,
  }) {
    final hint = conv.contextHint;
    final items = <Widget>[];

    if (hint?.hasJob == true) {
      items.add(
        _buildMiniContextPill(
          label: [
            hint!.jobNumber?.trim().isNotEmpty == true
                ? hint.jobNumber!.trim()
                : 'Trabajo',
            if (hint.jobStatus?.trim().isNotEmpty == true)
              hint.jobStatus!.trim(),
          ].join(' · '),
          color: _colorFromHex(hint.jobStatusColor, const Color(0xFF2563EB)),
          prominent: true,
        ),
      );
    }

    if (hint?.bikeName?.trim().isNotEmpty == true) {
      items.add(
        _buildMiniContextPill(
          label: hint!.bikeName!.trim(),
          color: const Color(0xFF475569),
          prominent: prominent,
        ),
      );
    }

    if (items.isNotEmpty) {
      return Wrap(
        spacing: 5,
        runSpacing: 4,
        children: items,
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildMiniContextPill({
    required String label,
    required Color color,
    bool prominent = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 178),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: prominent ? 0.13 : 0.07),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
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

  Widget _buildTrailing(
    Conversation conv,
    bool hasUnread,
    ThemeData theme,
    Color unreadColor,
  ) {
    final menuVisible = _isHovering || widget.isActive;
    return SizedBox(
      width: 34,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (hasUnread)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              constraints: const BoxConstraints(minWidth: 22),
              decoration: BoxDecoration(
                color: unreadColor,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: unreadColor.withValues(alpha: 0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            )
          else
            const SizedBox(height: 18),
          const SizedBox(height: 4),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: menuVisible ? 1 : 0,
            child: SizedBox(
              width: 28,
              height: 28,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                tooltip: 'Opciones del chat',
                icon: Icon(
                  Icons.more_horiz,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                splashRadius: 16,
                onSelected: (value) {
                  if (value == 'pin') {
                    widget.onTogglePinned?.call();
                  } else if (value == 'delete') {
                    Future.delayed(
                      const Duration(milliseconds: 80),
                      widget.onDelete,
                    );
                  }
                },
                itemBuilder: (context) => [
                  if (widget.onTogglePinned != null)
                    PopupMenuItem<String>(
                      value: 'pin',
                      child: Row(
                        children: [
                          Icon(
                            widget.isPinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Text(
                              widget.isPinned ? 'Desfijar chat' : 'Fijar chat'),
                        ],
                      ),
                    ),
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.red, size: 18),
                        SizedBox(width: 10),
                        Text(
                          'Eliminar chat',
                          style: TextStyle(color: Colors.red),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryIcon(Conversation conv) {
    final status = conv.lastMessageExternalStatus?.toLowerCase();
    final isRead = status == 'read';
    final isDelivered = status == 'delivered' || status == 'sent' || isRead;
    return Icon(
      isDelivered ? Icons.done_all : Icons.done,
      size: 14,
      color: isRead
          ? const Color(0xFF0EA5E9)
          : Theme.of(context)
              .colorScheme
              .onSurfaceVariant
              .withValues(alpha: 0.7),
    );
  }

  IconData? _previewIcon(Conversation conv) {
    final metadata = conv.lastMessageMetadata;
    if (metadata['share_kind'] == 'route' || metadata['route'] != null) {
      return Icons.link;
    }

    return switch (conv.lastMessageType) {
      'image' => Icons.image_outlined,
      'file' => Icons.attach_file,
      'action_request' => Icons.bolt,
      'system' => Icons.info_outline,
      _ => null,
    };
  }

  String _previewText(Conversation conv) {
    final metadata = conv.lastMessageMetadata;
    final title = metadata['title']?.toString().trim();
    String preview;

    if (metadata['share_kind'] == 'route' || metadata['route'] != null) {
      preview = title == null || title.isEmpty
          ? 'Página compartida del ERP'
          : 'Página compartida: $title';
    } else {
      preview = switch (conv.lastMessageType) {
        'image' => 'Foto',
        'file' => metadata['filename']?.toString().trim().isNotEmpty == true
            ? 'Archivo: ${metadata['filename']}'
            : 'Archivo adjunto',
        'action_request' =>
          title == null || title.isEmpty ? 'Solicitud interactiva' : title,
        'system' => conv.lastMessageContent?.trim() ?? 'Actualización del chat',
        _ => conv.lastMessageContent?.trim() ?? '',
      };
    }

    preview = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (preview.isEmpty) preview = widget.subtitle;
    if (preview.contains('vinabike://app/open') ||
        preview.contains('${RouteShareService.publicHost}'
            '${RouteShareService.publicOpenPath}') ||
        RouteShareService.isShareLink(preview)) {
      preview = 'Página compartida del ERP';
    }
    if (conv.lastMessageIsMine && preview.isNotEmpty) {
      return 'Tú: $preview';
    }
    return preview;
  }

  IconData _channelIcon(Conversation conv) {
    if (conv.isWhatsApp) return Icons.phone_in_talk_outlined;
    if (conv.isWebsitePortal) return Icons.language_outlined;
    return Icons.people_outline;
  }

  Color _channelColor(Conversation conv, bool isPending) {
    if (isPending) return const Color(0xFFD97706);
    if (conv.isWhatsApp) return const Color(0xFF047857);
    if (conv.isWebsitePortal) return const Color(0xFF0F4C81);
    return const Color(0xFF475569);
  }

  String _initialsFor(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '?';
    if (RegExp(r'^\+?[0-9 ]+$').hasMatch(trimmed)) return '#';

    final words = trimmed
        .split(RegExp(r'\s+'))
        .where((word) => word.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      return words.first.characters.take(2).toString().toUpperCase();
    }
    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
  }
}
