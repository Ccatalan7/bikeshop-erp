import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../modules/messaging/services/messaging_service.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/customer_inbox_list.dart';
import '../widgets/customer_chat_view.dart';
import '../widgets/deferred_customer_chat_context_panel.dart';

class CustomerChatDetailPage extends StatefulWidget {
  final String conversationId;

  const CustomerChatDetailPage({
    super.key,
    required this.conversationId,
  });

  @override
  State<CustomerChatDetailPage> createState() => _CustomerChatDetailPageState();
}

class _CustomerChatDetailPageState extends State<CustomerChatDetailPage> {
  final MessagingService _messagingService = MessagingService();
  Map<String, dynamic>? _conversation;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversationDetails();
  }

  @override
  void didUpdateWidget(CustomerChatDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _loadConversationDetails();
    }
  }

  Future<void> _loadConversationDetails() async {
    setState(() => _isLoading = true);
    try {
      final conversations = await _messagingService.getCustomerConversations();
      final conv = conversations.firstWhere(
        (c) => c['id'] == widget.conversationId,
        orElse: () => <String, dynamic>{},
      );
      if (mounted) {
        setState(() {
          _conversation = conv.isNotEmpty ? conv : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine context for side panel
    final contextType = _conversation?['context_type'];
    final contextId = _conversation?['context_id'];
    final hasContext = contextType != null && contextId != null;

    final title = _getTitle(contextType);

    return CustomerPortalLayout(
      title: title,
      showBackButton: true,
      overrideLayout: true,
      backPath: '/tienda/cuenta/chats',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 900;

          if (isDesktop) {
            return _buildDesktopLayout(hasContext, contextType, contextId);
          } else {
            return _buildMobileLayout(
                context, hasContext, contextType, contextId);
          }
        },
      ),
    );
  }

  Widget _buildDesktopLayout(
      bool hasContext, String? contextType, String? contextId) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Inbox Pane (Left)
        Container(
          width: 300,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: Colors.grey.shade200)),
            color: Colors.white,
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: const Text('Conversaciones',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const Divider(height: 1),
              Expanded(
                child: CustomerInboxList(
                  activeConversationId: widget.conversationId,
                  onConversationSelected: (id) =>
                      context.go('/tienda/cuenta/chats/$id'),
                ),
              ),
            ],
          ),
        ),

        // Chat Pane (Center)
        Expanded(
          flex: 2,
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : CustomerChatView(conversationId: widget.conversationId),
        ),

        // Context Pane (Right)
        if (hasContext)
          SizedBox(
            width: 350,
            child: DeferredCustomerChatContextPanel(
              contextType: contextType!,
              contextId: contextId!,
            ),
          ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context, bool hasContext,
      String? contextType, String? contextId) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : CustomerChatView(
            conversationId: widget.conversationId,
            onInfoPressed: hasContext
                ? () =>
                    _showContextBottomSheet(context, contextType!, contextId!)
                : null,
          );
  }

  void _showContextBottomSheet(
      BuildContext context, String contextType, String contextId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: DeferredCustomerChatContextPanel(
                  contextType: contextType,
                  contextId: contextId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getTitle(String? contextType) {
    switch (contextType) {
      case 'job':
        return 'Servicio Técnico';
      case 'order':
        return 'Pedido';
      case 'bike':
        return 'Mi Bicicleta';
      case 'invoice':
        return 'Factura';
      default:
        return 'Chat de Soporte';
    }
  }
}
