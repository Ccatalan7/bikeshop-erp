import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../modules/messaging/models/conversation.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../services/customer_account_service.dart';
import 'customer_chat_view.dart';
import 'public_store_layout.dart';

/// Compact host for the customer account and storefront launcher.
///
/// It deliberately owns no message stream, composer, receipt state or unread
/// counter. Those all come from [ChatProvider] and [CustomerChatView], exactly
/// like the routed customer inbox.
class CustomerChatSurface extends StatefulWidget {
  const CustomerChatSurface({
    super.key,
    this.activeContext,
    this.onClose,
  });

  final Map<String, dynamic>? activeContext;
  final VoidCallback? onClose;

  @override
  State<CustomerChatSurface> createState() => _CustomerChatSurfaceState();
}

class _CustomerChatSurfaceState extends State<CustomerChatSurface> {
  bool _loadScheduled = false;
  bool _isLoading = true;
  bool _loadFailed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loadScheduled) return;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadConversations());
    });
  }

  Future<void> _loadConversations() async {
    final provider = context.read<ChatProvider>();
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }

    try {
      await provider.synchronizeSessionScope();
      await provider.loadConversations(type: 'support');
    } catch (_) {
      if (mounted) _loadFailed = true;
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Conversation? _resolveConversation(List<Conversation> conversations) {
    final customerConversations = conversations
        .where(
          (conversation) =>
              conversation.isSupport &&
              conversation.isWebsitePortal &&
              !conversation.isSupplierConversation,
        )
        .toList(growable: false);
    if (customerConversations.isEmpty) return null;

    final contextType = widget.activeContext?['type']?.toString();
    final contextId = widget.activeContext?['id']?.toString();
    if (contextType != null && contextId != null) {
      for (final conversation in customerConversations) {
        if (conversation.contextType == contextType &&
            conversation.contextId == contextId) {
          return conversation;
        }
      }
    }

    for (final conversation in customerConversations) {
      if (conversation.status == 'active' || conversation.status == 'pending') {
        return conversation;
      }
    }
    return customerConversations.first;
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<CustomerAccountService>();
    final provider = context.watch<ChatProvider>();
    final conversation = _resolveConversation(provider.conversations);

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          _buildHeader(context, conversation),
          const Divider(height: 1),
          Expanded(
            child: !account.isAuthenticated
                ? _buildSignedOutState(context)
                : _isLoading && conversation == null
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : conversation == null
                        ? _buildEmptyState(context)
                        : CustomerChatView(
                            key: ValueKey(conversation.id),
                            conversationId: conversation.id,
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    Conversation? conversation,
  ) {
    final theme = Theme.of(context);
    final status = switch (conversation?.status) {
      'pending' => 'Esperando al equipo',
      'active' => 'Conversación activa',
      'resolved' || 'closed' || 'archived' => 'Historial',
      _ => 'Ayuda y seguimiento',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Icon(
            Icons.support_agent_rounded,
            size: 21,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Soporte Viñabike',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  status,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Abrir bandeja',
            onPressed: () =>
                PublicStoreLayout.navigateToHref(context, '/cuenta/chats'),
            icon: const Icon(Icons.open_in_full_rounded, size: 19),
          ),
          if (widget.onClose != null)
            IconButton(
              tooltip: 'Cerrar',
              onPressed: widget.onClose,
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildSignedOutState(BuildContext context) {
    return _CenteredState(
      icon: Icons.lock_outline_rounded,
      title: 'Inicia sesión para conversar',
      body: 'Tus consultas y su historial quedan vinculados a tu cuenta.',
      actionLabel: 'Iniciar sesión',
      onPressed: () =>
          PublicStoreLayout.navigateToHref(context, '/cuenta/login'),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return _CenteredState(
      icon: _loadFailed
          ? Icons.sync_problem_rounded
          : Icons.chat_bubble_outline_rounded,
      title: _loadFailed
          ? 'No pudimos cargar tus conversaciones'
          : 'Aún no tienes conversaciones',
      body: _loadFailed
          ? 'Reintenta sin salir de esta pantalla.'
          : 'Abre la bandeja para iniciar una consulta con el equipo.',
      actionLabel: _loadFailed ? 'Reintentar' : 'Abrir bandeja',
      onPressed: _loadFailed
          ? _loadConversations
          : () => PublicStoreLayout.navigateToHref(context, '/cuenta/chats'),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: onPressed,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
