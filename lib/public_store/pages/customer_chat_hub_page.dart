import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../modules/messaging/services/messaging_service.dart';
import '../models/customer_portal_presentation.dart';
import '../services/customer_account_service.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/customer_chat_view.dart';
import '../widgets/customer_chat_context_support.dart';
import '../widgets/deferred_customer_chat_context_panel.dart';
import '../widgets/customer_portal_style.dart';
import '../widgets/public_store_layout.dart';

/// «Soporte» (`/cuenta/chats`, `/cuenta/chats/:id`): la lista de
/// conversaciones con la tienda y, al abrir una, el chat en el mismo marco.
class CustomerChatHubPage extends StatefulWidget {
  final String? initialConversationId;

  const CustomerChatHubPage({
    super.key,
    this.initialConversationId,
  });

  @override
  State<CustomerChatHubPage> createState() => _CustomerChatHubPageState();
}

class _CustomerChatHubPageState extends State<CustomerChatHubPage> {
  final MessagingService _messagingService = MessagingService();
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;
  String? _selectedConversationId;
  Map<String, dynamic>? _selectedConversation;
  RealtimeChannel? _conversationLifecycleChannel;
  Timer? _conversationRefreshTimer;
  int _conversationLoadEpoch = 0;

  @override
  void initState() {
    super.initState();
    _selectedConversationId = widget.initialConversationId;
    _loadConversations();
    _subscribeToConversationLifecycle();
  }

  @override
  void didUpdateWidget(CustomerChatHubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialConversationId != widget.initialConversationId) {
      // If URL changed externally (back button), update state
      if (_selectedConversationId != widget.initialConversationId) {
        _selectConversation(widget.initialConversationId, updateUrl: false);
      }
    }
  }

  void _subscribeToConversationLifecycle() {
    final previous = _conversationLifecycleChannel;
    if (previous != null) unawaited(previous.unsubscribe());
    _conversationLifecycleChannel =
        _messagingService.subscribeToConversationLifecycleUpdates(() {
      _conversationRefreshTimer?.cancel();
      _conversationRefreshTimer = Timer(
        const Duration(milliseconds: 90),
        () => unawaited(_loadConversations(showLoading: false)),
      );
    });
  }

  Future<void> _loadConversations({bool showLoading = true}) async {
    if (!mounted) return;
    final loadEpoch = ++_conversationLoadEpoch;
    if (showLoading) setState(() => _isLoading = true);
    try {
      final conversations = await _messagingService.getCustomerConversations();
      if (mounted && loadEpoch == _conversationLoadEpoch) {
        setState(() {
          _conversations = conversations;
          _isLoading = false;
          // Refresh selection data if active
          if (_selectedConversationId != null) {
            _selectedConversation = _conversations.firstWhere(
              (c) => c['id'] == _selectedConversationId,
              orElse: () => <String, dynamic>{},
            );
          }
        });
      }
    } catch (e) {
      if (mounted && loadEpoch == _conversationLoadEpoch) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _conversationLoadEpoch += 1;
    _conversationRefreshTimer?.cancel();
    final channel = _conversationLifecycleChannel;
    if (channel != null) unawaited(channel.unsubscribe());
    super.dispose();
  }

  void _selectConversation(String? conversationId, {bool updateUrl = true}) {
    setState(() {
      _selectedConversationId = conversationId;
      if (conversationId != null) {
        _selectedConversation = _conversations.firstWhere(
          (c) => c['id'] == conversationId,
          orElse: () => <String, dynamic>{},
        );
      } else {
        _selectedConversation = null;
      }
    });

    if (updateUrl) {
      if (conversationId != null) {
        PublicStoreLayout.navigateToHref(
          context,
          '/cuenta/chats/$conversationId',
        );
      } else {
        PublicStoreLayout.navigateToHref(context, '/cuenta/chats');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = _selectedConversationId;
    final selected = selectedId == null
        ? null
        : CustomerConversationPresentation.of(
            _selectedConversation ?? const {},
            currentUserId: _messagingService.currentUserId,
          );

    // En ancho, un chat con contexto (un trabajo, una factura) lleva el
    // resumen a la derecha. Un chat sin contexto no lleva columna: antes
    // mostraba un «Iniciado: Hoy» fijo, que no era verdad.
    Widget? rightContent;
    final contextType =
        _selectedConversation?['context_type']?.toString().trim();
    final contextId = _selectedConversation?['context_id']?.toString().trim();
    final hasContext = selectedId != null &&
        CustomerChatContextSupport.supports(contextType) &&
        contextId != null &&
        contextId.isNotEmpty;
    if (hasContext) {
      rightContent = DeferredCustomerChatContextPanel(
        key: ValueKey('context-$contextId'),
        contextType: contextType!,
        contextId: contextId,
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= PortalStyle.wideBreakpoint;

    return CustomerPortalLayout(
      title: selected?.title ?? 'Soporte',
      subtitle: selected == null
          ? 'Escríbele a la tienda y al taller: pedidos, tu bici o lo que '
              'necesites.'
          : null,
      headerAction: selected == null && _conversations.isNotEmpty
          ? PortalButton(
              label: 'Nueva consulta',
              kind: PortalButtonKind.onPhoto,
              icon: Icons.add,
              onPressed: _showNewChatDialog,
            )
          : null,
      // En teléfono, el chat abierto usa todo el alto: sin título, con
      // «Volver» a la lista.
      showHeader: selected == null || wide,
      backPath: selectedId == null ? null : '/cuenta/chats',
      rightSidebarContent: rightContent,
      // El chat maneja su propio alto y su scroll.
      enableContentScrolling: false,
      child: selectedId == null
          ? _buildConversationList()
          : _ChatFrame(
              child: CustomerChatView(
                key: ValueKey('chat-$selectedId'),
                conversationId: selectedId,
                onInfoPressed: !wide && hasContext ? _showMobileContext : null,
              ),
            ),
    );
  }

  Widget _buildConversationList() {
    if (_isLoading) {
      return const Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 48),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_conversations.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 48),
        child: PortalEmptyState(
          title: 'No tienes conversaciones.',
          message: 'Pregúntanos por un pedido, un repuesto o tu bici en el '
              'taller. Te respondemos aquí mismo.',
          actions: [
            PortalButton(
              label: 'Nueva consulta',
              icon: Icons.add,
              onPressed: _showNewChatDialog,
            ),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < PortalStyle.compactBreakpoint;
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 48),
          child: PortalPanel(
            children: [
              for (final conversation in _conversations)
                _ConversationRow(
                  conversation: conversation,
                  currentUserId: _messagingService.currentUserId,
                  compact: compact,
                  onTap: () => _selectConversation(
                    conversation['id']?.toString(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showMobileContext() {
    final contextType = _selectedConversation?['context_type']?.toString();
    final contextId = _selectedConversation?['context_id']?.toString();
    if (!CustomerChatContextSupport.supports(contextType) ||
        contextId == null ||
        contextId.trim().isEmpty) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: PortalStyle.of(context).page,
      shape: PortalStyle.shape,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.88,
        child: DeferredCustomerChatContextPanel(
          contextType: contextType!,
          contextId: contextId,
        ),
      ),
    );
  }

  void _showNewChatDialog() {
    final accountService = context.read<CustomerAccountService>();
    final style = PortalStyle.of(context);
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: style.page,
      shape: PortalStyle.shape,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (modalContext) => Theme(
        data: style.formTheme(Theme.of(modalContext)),
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'NUEVA CONSULTA',
                  semanticsLabel: 'Nueva consulta',
                  style: style.heading(24),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Cuéntanos qué necesitas. Si es por un pedido o tu bici, '
                'indica cuál.',
                style: style.pageSubtitle,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                maxLines: 4,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: '¿En qué podemos ayudarte?',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              PortalButton(
                label: 'Enviar',
                arrow: true,
                expand: true,
                onPressed: () async {
                  final message = controller.text.trim();
                  if (message.isEmpty) return;
                  final tenantId = accountService.tenantId;
                  Navigator.pop(modalContext);
                  if (tenantId == null) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No pudimos enviar tu consulta. Recarga la página e '
                          'intenta de nuevo.',
                        ),
                      ),
                    );
                    return;
                  }
                  try {
                    final id = await _messagingService.createChatRequest(
                      initialMessage: message,
                      tenantId: tenantId,
                    );
                    await _loadConversations(showLoading: false);
                    if (mounted) _selectConversation(id);
                  } catch (_) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No pudimos enviar tu consulta. Intenta de nuevo.',
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El chat abierto, en un marco recto: la línea fuerte arriba como las
/// listas del portal y una fina alrededor.
class _ChatFrame extends StatelessWidget {
  const _ChatFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.page,
        border: Border(
          top: BorderSide(color: style.ink),
          left: BorderSide(color: style.line),
          right: BorderSide(color: style.line),
          bottom: BorderSide(color: style.line),
        ),
      ),
      child: ClipRect(child: child),
    );
  }
}

/// Una conversación en la lista: de qué se trata, el último mensaje y
/// cuándo. `conversations` no tiene `last_message`: el último mensaje sale
/// de los `messages` que trae la consulta.
class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.conversation,
    required this.currentUserId,
    required this.compact,
    required this.onTap,
  });

  final Map<String, dynamic> conversation;
  final String? currentUserId;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final p = CustomerConversationPresentation.of(
      conversation,
      currentUserId: currentUserId,
    );
    final when =
        p.lastActivity == null ? null : portalRelativeDay(p.lastActivity!);
    final icon = switch (conversation['context_type']?.toString()) {
      'invoice' => Icons.receipt_long_outlined,
      'job' => Icons.build_outlined,
      _ => Icons.chat_bubble_outline,
    };
    // Esperar al equipo es de la tienda (oscura); cerrada o archivada, apagada.
    final pill = p.statusLabel == null
        ? null
        : PortalTag(
            label: p.statusLabel!,
            kind: p.tone == PortalTone.neutral
                ? PortalTagKind.quiet
                : PortalTagKind.ink,
          );
    return PortalRow(
      leading: PortalThumb(fallbackIcon: icon),
      title: p.title,
      meta: [
        p.preview ?? 'Sin mensajes todavía',
        if (compact && when != null) when,
      ].join(' · '),
      footer: compact ? pill : null,
      semanticsLabel: [p.title, if (when != null) when].join(', '),
      trailing: compact
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (when != null) Text(when, style: style.rowMeta),
                if (pill != null) ...[const SizedBox(height: 8), pill],
              ],
            ),
      onTap: onTap,
    );
  }
}
