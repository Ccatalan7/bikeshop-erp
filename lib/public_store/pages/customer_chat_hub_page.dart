import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../modules/messaging/services/messaging_service.dart';
import '../services/customer_account_service.dart';
import '../widgets/customer_portal_layout.dart';
import '../widgets/customer_chat_view.dart';
import '../widgets/deferred_customer_chat_context_panel.dart';
import '../widgets/deferred_quote_review_panel.dart';
import '../../shared/widgets/safe_layout_builder.dart';

/// Unified customer chat page handling both list and detail views
/// Uses standard CustomerPortalLayout but animates the right panel content
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
  Widget? _customRightPanel; // For transient panels like Quote Review

  @override
  void initState() {
    super.initState();
    _selectedConversationId = widget.initialConversationId;
    _loadConversations();
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

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);
    try {
      final conversations = await _messagingService.getCustomerConversations();
      if (mounted) {
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
      if (mounted) setState(() => _isLoading = false);
    }
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
        context.go('/tienda/cuenta/chats/$conversationId');
      } else {
        context.go('/tienda/cuenta/chats');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine the right sidebar content
    Widget? rightContent = _customRightPanel;

    if (rightContent == null && _selectedConversationId != null) {
      final contextType = _selectedConversation?['context_type'];
      final contextId = _selectedConversation?['context_id'];

      if (contextType != null && contextId != null) {
        // Show context panel (job/invoice details)
        rightContent = Container(
          key: ValueKey('context-$contextId'),
          padding: const EdgeInsets.only(top: 16),
          child: DeferredCustomerChatContextPanel(
            contextType: contextType,
            contextId: contextId,
          ),
        );
      } else {
        // Show a "chat info" placeholder when no context
        rightContent = Container(
          key: ValueKey('chat-info-$_selectedConversationId'),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: const Icon(Icons.support_agent, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Soporte Vinabike',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Conversación activa',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text('Información',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              _buildInfoRow(Icons.access_time, 'Estado', 'Activo'),
              _buildInfoRow(Icons.calendar_today, 'Iniciado', 'Hoy'),
            ],
          ),
        );
      }
    }

    return CustomerPortalLayout(
      title: 'Mis Conversaciones',
      // Pass custom sidebar content - animation handled by layout
      rightSidebarContent: rightContent,
      // Disable scroll wrapping so chat can manage its own height/scrolling
      enableContentScrolling: false,

      // Main Center Content
      child: MediaQueryLayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 900;

          if (isDesktop) {
            // Desktop: Show List on Left is managed by Portal Layout?
            // Wait, CustomerPortalLayout defines LEFT COLUMN structure for us.
            // The 'child' we pass goes into the "Main Content" area (Left Column Body).

            // So on Desktop:
            // The 'child' should be EITHER the "List" OR "Chat View" (if we want single pane).
            // OR checks how user wants it.
            // Previous 'CustomerChatListPage' showed LIST in center.
            // Previous 'CustomerChatDetailPage' showed CHAT in center.

            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: _selectedConversationId == null
                  ? _buildConversationList()
                  : _buildChatView(constraints),
            );
          } else {
            // Mobile: Full screen switch
            return _selectedConversationId == null
                ? _buildConversationList()
                : _buildChatViewMobile(constraints);
          }
        },
      ),
    );
  }

  Widget _buildConversationList() {
    return Container(
      key: const ValueKey('list-view'),
      constraints: const BoxConstraints(minHeight: 400),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: _conversations.map((conv) {
                    return _ConversationTile(
                      conversation: conv,
                      onTap: () => _selectConversation(conv['id']),
                    );
                  }).toList(),
                ),
    );
  }

  Widget _buildChatView(BoxConstraints constraints) {
    // Explicitly constrain the height to the available space using SizedBox.
    // This allows the Expanded widget inside to function correctly.
    // If constraints are unbounded (e.g., inside ScrollView or editor viewport),
    // fallback to a calculated height based on MediaQuery.
    final height = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : MediaQuery.of(context).size.height - 200; // Fallback for editor mode

    return SizedBox(
      height: height,
      child: Column(
        children: [
          // Desktop back button to list
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _selectConversation(null),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver a la lista'),
              ),
            ],
          ),
          Expanded(
            child: CustomerChatView(
              conversationId: _selectedConversationId!,
              onShowQuote: _handleShowQuoteReview,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatViewMobile(BoxConstraints constraints) {
    // Similarly for mobile, use the available constraints to ensure
    // the chat view fills the screen properly.
    final height = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : MediaQuery.of(context).size.height - 200;

    return SizedBox(
      height: height,
      child: CustomerChatView(
        conversationId: _selectedConversationId!,
        onShowQuote: _handleShowQuoteReview,
      ),
    );
  }

  void _handleShowQuoteReview(String invoiceId, String messageId) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    if (isDesktop) {
      setState(() {
        _customRightPanel = DeferredQuoteReviewPanel(
          key: ValueKey('quote-$invoiceId'),
          invoiceId: invoiceId,
          messageId: messageId,
          onClose: () => setState(() => _customRightPanel = null),
          onApprove: () => _handleApproveQuote(invoiceId, messageId),
          onRequestChanges: (feedback) =>
              _handleRequestChanges(invoiceId, messageId, feedback),
        );
      });
    } else {
      // Mobile: Show Full Screen Modal
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        builder: (context) => DeferredQuoteReviewPanel(
          invoiceId: invoiceId,
          messageId: messageId,
          onClose: () => Navigator.pop(context),
          onApprove: () {
            Navigator.pop(context); // Close modal first
            _handleApproveQuote(invoiceId, messageId);
          },
          onRequestChanges: (feedback) {
            Navigator.pop(context);
            _handleRequestChanges(invoiceId, messageId, feedback);
          },
        ),
      );
    }
  }

  Future<void> _handleApproveQuote(String invoiceId, String messageId) async {
    try {
      final supabase = Supabase.instance.client;

      // 1. Update Invoice Status via RPC (Secure)
      await supabase
          .rpc('confirm_invoice_approval', params: {'p_invoice_id': invoiceId});

      // Update local cache if needed (SalesService listeners should handle realtime, but force refresh is safer)
      // await salesService.loadInvoices(forceRefresh: true); -- listeners will handle it via Realtime

      // 2. Update Message Metadata via RPC (Secure)
      await supabase.rpc('respond_to_action_request', params: {
        'p_message_id': messageId,
        'p_action_type': 'approve_quote',
        'p_status': 'accepted',
        'p_metadata_updates': {'target_id': invoiceId}
      });

      // Force refresh of messages to update UI state immediately
      if (mounted) {
        // UI logic for immediate refresh is handled by stream listeners
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Presupuesto aprobado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _customRightPanel = null); // Close panel
        // Trigger a refresh of the chat view if possible, or reliance on realtime
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleRequestChanges(
      String invoiceId, String messageId, String feedback) async {
    try {
      final supabase = Supabase.instance.client;
      final userId = supabase.auth.currentUser?.id;

      // Send the feedback as a new text message
      await supabase.from('messages').insert({
        'conversation_id': _selectedConversationId,
        'sender_id': userId,
        'content': 'Solicito cambios en el presupuesto: $feedback',
        'type': 'text',
      });

      // Update the action request status to 'declined' (or keep pending? user said "leave notes")
      // If we decline, the button disappears. Maybe keep it pending but just send comments?
      // The user said "leave notes to request... some changes".
      // Usually that implies NOT approving yet.
      // So status 'declined' (Rechazado) seems appropriate for "Request Changes".

      await supabase.from('messages').update({
        'metadata': {
          'action_type': 'approve_quote',
          'target_id': invoiceId,
          'status':
              'declined', // "Changes Requested" logic maps to declined for now
          'responded_at': DateTime.now().toIso8601String(),
        },
      }).eq('id', messageId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Solicitud de cambios enviada'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _customRightPanel = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No tienes conversaciones iniciadas'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _showNewChatDialog,
              child: const Text('NUEVA CONSULTA'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.grey)),
          const Spacer(),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  void _showNewChatDialog() {
    final accountService = context.read<CustomerAccountService>();
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(modalContext).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Nueva Consulta',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '¿En qué podemos ayudarte?',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                final message = controller.text.trim();
                // Get tenantId before closing
                final tenantId = accountService.tenantId;
                if (tenantId == null) {
                  Navigator.pop(modalContext);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Error: Tienda no identificada')),
                    );
                  }
                  return;
                }

                if (message.isNotEmpty) {
                  Navigator.pop(modalContext);
                  try {
                    final id = await _messagingService.createChatRequest(
                      initialMessage: message,
                      tenantId: tenantId,
                    );
                    _loadConversations();
                    _selectConversation(id);
                  } catch (e) {
                    // Handle error
                  }
                }
              },
              child: const Text('ENVIAR'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final lastMessage = conversation['last_message'] as String? ?? '';
    final updatedAt = conversation['updated_at'] as String?;

    // Simple Tile
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          backgroundColor: Colors.blue.withOpacity(0.1),
          child: const Icon(Icons.chat_bubble, color: Colors.blue),
        ),
        title: const Text('Consulta',
            style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(lastMessage, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            if (updatedAt != null)
              Text('Actualizado recientemente',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
