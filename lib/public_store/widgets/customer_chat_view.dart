import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/models/message_delivery_state.dart';
import '../../modules/messaging/models/message.dart';
import '../../modules/messaging/services/messaging_attachment_service.dart';
import '../../modules/messaging/services/messaging_service.dart';
import '../../modules/messaging/widgets/message_delivery_indicator.dart';
import 'customer_chat_visibility.dart';

class _AttachmentUrlCacheEntry {
  const _AttachmentUrlCacheEntry({
    required this.future,
    required this.refreshAt,
  });

  final Future<String?> future;
  final DateTime refreshAt;

  bool get shouldRefresh => !DateTime.now().isBefore(refreshAt);
}

class CustomerChatView extends StatefulWidget {
  final String conversationId;
  final VoidCallback? onInfoPressed; // For Mobile Context View trigger

  const CustomerChatView({
    super.key,
    required this.conversationId,
    this.onInfoPressed,
  });

  @override
  State<CustomerChatView> createState() => _CustomerChatViewState();
}

class _CustomerChatViewState extends State<CustomerChatView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final MessagingService _messagingService = MessagingService();
  final MessagingAttachmentService _attachmentService =
      MessagingAttachmentService();
  final Object _conversationViewOwner = Object();
  final Set<String> _pendingActionResponses = <String>{};
  final Map<String, _AttachmentUrlCacheEntry> _attachmentUrlCache = {};
  ChatProvider? _chatProvider;
  RealtimeChannel? _conversationLifecycleChannel;
  Timer? _conversationRefreshTimer;
  Timer? _attachmentUrlRefreshTimer;
  int _conversationLoadEpoch = 0;
  int _visibilityEpoch = 0;
  bool? _scheduledVisibility;
  bool? _reportedVisibility;
  String? _reportedConversationId;
  bool _historyAutoLoadScheduled = false;

  Map<String, dynamic>? _conversation;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleTimelineScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scheduleVisibilitySync();
      _subscribeToConversationLifecycle();
      _loadConversationDetails();
    });
  }

  @override
  void didUpdateWidget(CustomerChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _attachmentUrlCache.clear();
      _attachmentUrlRefreshTimer?.cancel();
      _conversation = null;
      _historyAutoLoadScheduled = false;
      _scheduleVisibilitySync();
      _subscribeToConversationLifecycle();
      _loadConversationDetails();
      // Reset scroll to bottom (0.0 because of reverse: true)
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider ??= context.read<ChatProvider>();
    _scheduleVisibilitySync();
  }

  void _scheduleVisibilitySync() {
    if (!mounted) return;
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    final visible = isCustomerChatHostVisible(
      tickerEnabled: TickerMode.of(context),
      routeIsCurrent: routeIsCurrent,
    );
    final conversationId = widget.conversationId;

    if (_scheduledVisibility == visible &&
        _reportedConversationId == conversationId) {
      return;
    }
    _scheduledVisibility = visible;
    final epoch = ++_visibilityEpoch;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != _visibilityEpoch) return;
      if (_reportedVisibility == visible &&
          _reportedConversationId == conversationId) {
        return;
      }
      _chatProvider?.updateConversationView(
        owner: _conversationViewOwner,
        conversationId: conversationId,
        visible: visible,
      );
      _reportedVisibility = visible;
      _reportedConversationId = conversationId;
    });
  }

  void _subscribeToConversationLifecycle() {
    final previous = _conversationLifecycleChannel;
    if (previous != null) unawaited(previous.unsubscribe());
    _conversationLifecycleChannel =
        _messagingService.subscribeToConversationLifecycleUpdates(
      () {
        _conversationRefreshTimer?.cancel();
        _conversationRefreshTimer = Timer(
          const Duration(milliseconds: 70),
          () => unawaited(_loadConversationDetails()),
        );
      },
      conversationId: widget.conversationId,
    );
  }

  Future<void> _loadConversationDetails() async {
    final conversationId = widget.conversationId;
    final loadEpoch = ++_conversationLoadEpoch;
    try {
      final conversations = await _messagingService.getCustomerConversations();
      final conv = conversations.firstWhere(
        (c) => c['id'] == conversationId,
        orElse: () => <String, dynamic>{},
      );
      if (mounted &&
          loadEpoch == _conversationLoadEpoch &&
          conversationId == widget.conversationId) {
        setState(() {
          _conversation = conv.isNotEmpty
              ? conv
              : <String, dynamic>{
                  'id': conversationId,
                  'status': 'unavailable',
                };
        });
      }
    } catch (_) {
      if (mounted &&
          loadEpoch == _conversationLoadEpoch &&
          conversationId == widget.conversationId &&
          _conversation == null) {
        setState(() {
          _conversation = <String, dynamic>{
            'id': conversationId,
            'status': 'unavailable',
          };
        });
      }
    }
  }

  @override
  void dispose() {
    _conversationLoadEpoch += 1;
    _visibilityEpoch += 1;
    _conversationRefreshTimer?.cancel();
    _attachmentUrlRefreshTimer?.cancel();
    final channel = _conversationLifecycleChannel;
    if (channel != null) unawaited(channel.unsubscribe());
    _chatProvider?.detachConversationView(_conversationViewOwner);
    _messageController.dispose();
    _scrollController.removeListener(_handleTimelineScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    try {
      await context.read<ChatProvider>().sendMessage(
            text,
            conversationId: widget.conversationId,
          );
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0, // Scroll to bottom (start of list in reverse mode)
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (error) {
      if (!mounted) return;
      if (_messageController.text.trim().isEmpty) {
        _messageController.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se envió el mensaje. El texto quedó listo para reintentar.',
          ),
        ),
      );
    }
  }

  void _handleTimelineScroll() {
    _requestOlderMessagesIfAtStart();
  }

  void _requestOlderMessagesIfAtStart() {
    if (!_scrollController.hasClients) return;
    final provider = _chatProvider;
    if (provider == null) return;
    final conversationId = widget.conversationId;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels > 180 ||
        !provider.hasMoreMessages(conversationId) ||
        provider.isLoadingOlderMessages(conversationId) ||
        provider.olderMessagesErrorForConversation(conversationId) != null) {
      return;
    }
    unawaited(provider.loadOlderMessages(conversationId));
  }

  void _scheduleOlderMessagesIfAtStart(ChatProvider provider) {
    final conversationId = widget.conversationId;
    if (_historyAutoLoadScheduled ||
        !provider.hasMoreMessages(conversationId) ||
        provider.isLoadingOlderMessages(conversationId) ||
        provider.olderMessagesErrorForConversation(conversationId) != null) {
      return;
    }
    _historyAutoLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyAutoLoadScheduled = false;
      if (!mounted || widget.conversationId != conversationId) return;
      _requestOlderMessagesIfAtStart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final messages =
        chatProvider.messagesForConversation(widget.conversationId);
    final timelineItems = _buildTimelineItems(messages);
    final isLoading = chatProvider.isConversationLoading(widget.conversationId);
    final streamError = chatProvider.messageStreamErrorForConversation(
      widget.conversationId,
    );
    final showHistoryBoundary = messages.isNotEmpty ||
        chatProvider.isLoadingOlderMessages(widget.conversationId) ||
        chatProvider.olderMessagesErrorForConversation(
              widget.conversationId,
            ) !=
            null;
    if (messages.isNotEmpty) {
      _scheduleOlderMessagesIfAtStart(chatProvider);
    }

    final status = _conversation?['status']?.toString() ?? 'loading';
    final isPending = status == 'pending';
    final isRejected = status == 'rejected';
    final isClosed = isRejected ||
        status == 'resolved' ||
        status == 'closed' ||
        status == 'archived' ||
        status == 'cancelled' ||
        status == 'unavailable' ||
        status == 'loading';

    return Column(
      children: [
        // Optional Info Button Header (Only visible if handler provided, effectively Mobile)
        if (widget.onInfoPressed != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onInfoPressed,
              icon: const Icon(Icons.info_outline, size: 16),
              label: const Text('Ver Detalles'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey[700],
              ),
            ),
          ),

        // Status banner
        if (isPending)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              border: Border(
                  bottom:
                      BorderSide(color: Colors.orange.withValues(alpha: 0.3))),
            ),
            child: Row(
              children: [
                Icon(Icons.schedule, color: Colors.orange[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Esperando respuesta del equipo...',
                    style: TextStyle(color: Colors.orange[700], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        if (isRejected)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              border: Border(
                  bottom: BorderSide(color: Colors.red.withValues(alpha: 0.3))),
            ),
            child: Row(
              children: [
                Icon(Icons.cancel_outlined, color: Colors.red[700], size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _conversation?['reject_reason'] ??
                        'Esta consulta fue cerrada.',
                    style: TextStyle(color: Colors.red[700], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        if (!isRejected && isClosed)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.72),
            child: Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 18,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Esta conversación está archivada y se conserva como respaldo.',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

        if (streamError != null)
          _buildMessageStreamErrorBanner(
            context,
            chatProvider,
            streamError,
          ),

        // Messages Area
        Expanded(
          child: Container(
            color: Colors.grey[50],
            child: isLoading && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                // Use NotificationListener to suppress OverscrollIndicatorNotification
                // This prevents the scroll event from bubbling up to the parent ScrollView
                // when the list reaches its bounds.
                : NotificationListener<OverscrollIndicatorNotification>(
                    onNotification: (notification) {
                      notification.disallowIndicator();
                      return true; // Stop propagation
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      reverse: true, // Anchor to bottom, scroll up for older
                      padding: const EdgeInsets.all(16),
                      itemCount:
                          timelineItems.length + (showHistoryBoundary ? 1 : 0),
                      // Allow physics again, but keep primary false
                      primary: false,
                      itemBuilder: (context, index) {
                        if (showHistoryBoundary &&
                            index == timelineItems.length) {
                          return _buildHistoryBoundary(
                            context,
                            chatProvider,
                            hasMessages: messages.isNotEmpty,
                          );
                        }
                        // Reverse index since list is reversed
                        final item =
                            timelineItems[timelineItems.length - 1 - index];
                        if (item.day != null) {
                          return _buildDaySeparator(context, item.day!);
                        }
                        return _buildMessageBubble(context, item.message!);
                      },
                    ),
                  ),
          ),
        ),

        // Input Area
        if (!isClosed)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: isPending
                            ? 'Agregar más información...'
                            : 'Escribe un mensaje...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _sendMessage,
                      icon:
                          const Icon(Icons.send, color: Colors.white, size: 20),
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryBoundary(
    BuildContext context,
    ChatProvider provider, {
    required bool hasMessages,
  }) {
    final conversationId = widget.conversationId;
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
        'Inicio de la conversación',
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
            onPressed: () =>
                provider.retryConversationMessages(widget.conversationId),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(BuildContext context, Message msg) {
    final isMe = msg.isMe;

    // Handle action request cards specially
    if (msg.type == 'action_request') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            child: _buildActionRequestCard(context, msg),
          ),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final privateAttachment =
        MessagingAttachmentService.hasPrivateReference(msg);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (privateAttachment)
              _buildPrivateAttachment(context, msg)
            else
              SelectableText(
                msg.content,
                style: TextStyle(
                  color: isMe
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurface,
                  fontSize: 15,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat('HH:mm').format(msg.createdAt),
                  style: TextStyle(
                    color: isMe
                        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.7)
                        : colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  MessageDeliveryIndicator(
                    state: MessageDeliveryState.fromMessage(msg),
                    size: 14,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<_CustomerTimelineItem> _buildTimelineItems(List<Message> messages) {
    final items = <_CustomerTimelineItem>[];
    DateTime? previousDay;
    for (final message in messages) {
      final day = DateTime(
        message.createdAt.year,
        message.createdAt.month,
        message.createdAt.day,
      );
      if (previousDay == null || day != previousDay) {
        items.add(_CustomerTimelineItem.day(day));
        previousDay = day;
      }
      items.add(_CustomerTimelineItem.message(message));
    }
    return items;
  }

  Widget _buildDaySeparator(BuildContext context, DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final label = day == today
        ? 'Hoy'
        : day == today.subtract(const Duration(days: 1))
            ? 'Ayer'
            : DateFormat('dd/MM/yyyy').format(day);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: colorScheme.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

  Widget _buildPrivateAttachment(BuildContext context, Message message) {
    final future = _attachmentUrlFuture(message);
    final isImage = message.type == 'image' ||
        (message.metadata['content_type']?.toString().startsWith('image/') ??
            false);
    final filename = message.metadata['filename']?.toString().trim();
    final label = filename == null || filename.isEmpty
        ? (isImage ? 'Imagen' : 'Documento')
        : filename;

    return FutureBuilder<String?>(
      future: future,
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            width: 180,
            height: 72,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (url == null) {
          return InkWell(
            onTap: () => _retryAttachmentPreview(message.id),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.refresh_rounded, size: 18),
                const SizedBox(width: 8),
                Flexible(child: Text('$label no disponible · Reintentar')),
              ],
            ),
          );
        }
        if (isImage) {
          return InkWell(
            onTap: () => _openPrivateAttachment(message),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                url,
                width: 260,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => InkWell(
                  onTap: () => _retryAttachmentPreview(message.id),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No se pudo cargar la imagen · Reintentar'),
                  ),
                ),
              ),
            ),
          );
        }
        return InkWell(
          onTap: () => _openPrivateAttachment(message),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description_outlined, size: 22),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.open_in_new, size: 16),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _attachmentUrlFuture(Message message) {
    final cached = _attachmentUrlCache[message.id];
    if (cached != null && !cached.shouldRefresh) return cached.future;

    final refreshAt = DateTime.now().add(
      const Duration(
        seconds: MessagingAttachmentService.signedUrlLifetimeSeconds - 30,
      ),
    );
    final entry = _AttachmentUrlCacheEntry(
      future: _attachmentService.createRuntimeSignedUrl(message),
      refreshAt: refreshAt,
    );
    _attachmentUrlCache[message.id] = entry;
    _scheduleAttachmentPreviewRefresh();
    return entry.future;
  }

  void _retryAttachmentPreview(String messageId) {
    if (!mounted) return;
    setState(() => _attachmentUrlCache.remove(messageId));
    _scheduleAttachmentPreviewRefresh();
  }

  void _scheduleAttachmentPreviewRefresh() {
    _attachmentUrlRefreshTimer?.cancel();
    if (_attachmentUrlCache.isEmpty) return;
    final nextRefresh = _attachmentUrlCache.values
        .map((entry) => entry.refreshAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final delay = nextRefresh.difference(DateTime.now());
    _attachmentUrlRefreshTimer = Timer(
      delay.isNegative ? Duration.zero : delay,
      () {
        if (!mounted) return;
        setState(() {
          _attachmentUrlCache.removeWhere((_, entry) => entry.shouldRefresh);
        });
        _scheduleAttachmentPreviewRefresh();
      },
    );
  }

  Future<void> _openPrivateAttachment(Message message) async {
    final freshUrl = await _attachmentService.createRuntimeSignedUrl(message);
    if (!mounted) return;
    if (freshUrl == null || freshUrl.isEmpty) {
      _retryAttachmentPreview(message.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo renovar el acceso al adjunto.'),
        ),
      );
      return;
    }
    final refreshAt = DateTime.now().add(
      const Duration(
        seconds: MessagingAttachmentService.signedUrlLifetimeSeconds - 30,
      ),
    );
    setState(() {
      _attachmentUrlCache[message.id] = _AttachmentUrlCacheEntry(
        future: Future<String?>.value(freshUrl),
        refreshAt: refreshAt,
      );
    });
    _scheduleAttachmentPreviewRefresh();
    await launchUrl(Uri.parse(freshUrl));
  }

  /// Build action request card for customer with interactive buttons
  Widget _buildActionRequestCard(BuildContext context, Message msg) {
    final actionType = msg.metadata['action_type'] as String? ?? 'unknown';
    final status = msg.metadata['status'] as String? ?? 'pending';
    final amount = msg.metadata['amount'] as num?;
    final responseNote = msg.metadata['response_note']?.toString().trim();
    final isResponding = _pendingActionResponses.contains(msg.id);
    final isDecisionAction =
        actionType == 'approve_quote' || actionType == 'confirm_delivery';

    // Determine card appearance based on action type
    IconData icon;
    String title;
    String buttonLabel;
    Color accentColor;

    switch (actionType) {
      case 'approve_quote':
        icon = Icons.description_outlined;
        if (status == 'accepted') {
          title = 'Presupuesto Aprobado';
          accentColor = Colors.green;
        } else if (status == 'declined') {
          title = 'Presupuesto Rechazado';
          accentColor = Colors.red;
        } else {
          title = 'Presupuesto Pendiente';
          accentColor = Colors.orange;
        }
        buttonLabel = 'Aprobar presupuesto';
        break;
      case 'pay_now':
        icon = Icons.payment;
        title = 'Pago solicitado';
        buttonLabel = amount != null
            ? 'Monto: \$${amount.toStringAsFixed(0)}'
            : 'Revisa tu pedido';
        accentColor = Colors.teal;
        break;
      case 'confirm_delivery':
        icon = Icons.local_shipping;
        title = 'Confirmar Entrega';
        buttonLabel = 'Confirmar Recibido';
        accentColor = Colors.blue;
        break;
      default:
        icon = Icons.info_outline;
        title = 'Acción Requerida';
        buttonLabel = 'Ver Detalles';
        accentColor = Colors.grey;
    }

    // Status badge
    Widget statusBadge = const SizedBox.shrink();
    if (status == 'accepted') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green),
            SizedBox(width: 6),
            Text('Aprobado',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.green,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    } else if (status == 'declined') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel, size: 16, color: Colors.red),
            SizedBox(width: 6),
            Text('Rechazado',
                style: TextStyle(
                    fontSize: 13,
                    color: Colors.red,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: const BoxConstraints(
          maxWidth: 400, // Fixed reasonable width, not percentage based
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
              ),
              child: Row(
                children: [
                  Icon(icon, color: accentColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  statusBadge,
                ],
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                msg.content,
                style: const TextStyle(
                    color: Colors.black87, fontSize: 13, height: 1.4),
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
                        style: const TextStyle(fontSize: 12, height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
            if (status == 'pending' && actionType == 'pay_now')
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: Colors.teal.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$buttonLabel. El chat no abre cobros sin una sesión de pago autorizada; revisa el pedido o solicita un enlace vigente al equipo.',
                        style: TextStyle(
                          color: Colors.teal.shade900,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Workshop decisions are persisted by the canonical audited
            // server command. Unknown and payment actions remain read-only.
            if (status == 'pending' && isDecisionAction)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(
                  children: [
                    if (actionType == 'approve_quote') ...[
                      Expanded(
                        child: TextButton(
                          onPressed: isResponding
                              ? null
                              : () => _requestQuotationChanges(msg),
                          child: const Text('Solicitar cambios'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: isResponding
                            ? null
                            : () => _handlePrimaryAction(msg),
                        icon: isResponding
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                actionType == 'pay_now'
                                    ? Icons.payment_outlined
                                    : Icons.check_rounded,
                                size: 18,
                              ),
                        label: Text(buttonLabel),
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            // Timestamp
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                DateFormat('HH:mm').format(msg.createdAt),
                style: TextStyle(color: Colors.grey[400], fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePrimaryAction(
    Message message,
  ) async {
    final actionType = message.metadata['action_type']?.toString();
    final targetId = message.metadata['target_id']?.toString();
    if (targetId == null || targetId.trim().isEmpty) return;
    if (actionType != 'approve_quote' && actionType != 'confirm_delivery') {
      return;
    }
    await _handleActionResponse(message, 'accepted');
  }

  Future<void> _requestQuotationChanges(Message message) async {
    final controller = TextEditingController();
    final feedback = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Solicitar cambios'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Indica qué necesitas ajustar',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (feedback == null || !mounted) return;

    await _handleActionResponse(
      message,
      'declined',
      responseNote: feedback,
    );
  }

  /// The server validates participant, conversation/job/customer binding and
  /// performs the workshop quotation transition plus message response as one
  /// idempotent operation keyed by the message UUID.
  Future<void> _handleActionResponse(
    Message message,
    String response, {
    String? responseNote,
  }) async {
    if (!_pendingActionResponses.add(message.id)) return;
    if (mounted) setState(() {});
    final messenger = ScaffoldMessenger.of(context);

    try {
      final actionType =
          message.metadata['action_type']?.toString() ?? 'unknown';
      await Supabase.instance.client.rpc(
        'respond_to_action_request',
        params: {
          'p_message_id': message.id,
          'p_action_type': actionType,
          'p_status': response,
          'p_metadata_updates': {
            if (responseNote?.trim().isNotEmpty == true)
              'response_note': responseNote!.trim(),
          },
        },
      );

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                response == 'accepted' ? '✅ Acción completada' : 'Rechazado'),
            backgroundColor:
                response == 'accepted' ? Colors.green : Colors.orange,
          ),
        );
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo registrar la respuesta: ${error.message}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (error) {
      debugPrint('Customer action outcome unknown for ${message.id}: $error');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'No pudimos confirmar la respuesta. Puede haberse guardado; vuelve a pulsar la misma opción para verificarla sin duplicar.',
            ),
            backgroundColor: Colors.orange.shade900,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    } finally {
      _pendingActionResponses.remove(message.id);
      if (mounted) setState(() {});
    }
  }
}

class _CustomerTimelineItem {
  final Message? message;
  final DateTime? day;

  const _CustomerTimelineItem._({this.message, this.day});

  factory _CustomerTimelineItem.message(Message message) =>
      _CustomerTimelineItem._(message: message);

  factory _CustomerTimelineItem.day(DateTime day) =>
      _CustomerTimelineItem._(day: day);
}
