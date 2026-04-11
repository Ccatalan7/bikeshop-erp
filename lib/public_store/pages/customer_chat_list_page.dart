import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../modules/messaging/services/messaging_service.dart';
import '../services/customer_account_service.dart';
import '../widgets/customer_portal_layout.dart';

/// Customer chat list page - shows all customer conversations
/// Uses the new design with frictionless chat request flow
class CustomerChatListPage extends StatefulWidget {
  const CustomerChatListPage({super.key});

  @override
  State<CustomerChatListPage> createState() => _CustomerChatListPageState();
}

class _CustomerChatListPageState extends State<CustomerChatListPage> {
  final MessagingService _messagingService = MessagingService();
  List<Map<String, dynamic>> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() => _isLoading = true);
    try {
      final conversations = await _messagingService.getCustomerConversations();
      if (mounted) {
        setState(() {
          _conversations = conversations;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading conversations: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountService = context.watch<CustomerAccountService>();

    if (!accountService.isAuthenticated) {
      return CustomerPortalLayout(
        title: 'Mis Conversaciones',
        child: _buildLoginPrompt(),
      );
    }

    return CustomerPortalLayout(
      title: 'Mis Conversaciones',
      child: RefreshIndicator(
        onRefresh: _loadConversations,
        child: _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(48),
                  child: CircularProgressIndicator(),
                ),
              )
            : _conversations.isEmpty
                ? _buildEmptyState(accountService)
                : _buildConversationsList(),
      ),
    );
  }

  Widget _buildLoginPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Inicia sesión',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Debes iniciar sesión para ver tus conversaciones.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.go('/login'),
              child: const Text('IR AL LOGIN'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(CustomerAccountService accountService) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 48,
                color: Colors.blue[700],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No tienes conversaciones',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '¿Tienes una consulta? Escríbenos y te responderemos lo antes posible.',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => _showNewChatDialog(context, accountService),
              icon: const Icon(Icons.chat),
              label: const Text('NUEVA CONSULTA'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationsList() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: _conversations.map((conv) {
          return _ConversationCard(
            conversation: conv,
            onTap: () => context.go('/tienda/cuenta/chats/${conv['id']}'),
          );
        }).toList(),
      ),
    );
  }

  void _showNewChatDialog(
      BuildContext parentContext, CustomerAccountService accountService) {
    final controller = TextEditingController();

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(modalContext).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.chat_bubble_outline, color: Colors.blue),
                  const SizedBox(width: 12),
                  Text(
                    'Nueva Consulta',
                    style:
                        Theme.of(modalContext).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(modalContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Escribe tu consulta y un mecánico te responderá pronto.',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                maxLines: 4,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Escribe tu consulta aquí...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final message = controller.text.trim();
                    if (message.isEmpty) return;

                    // Check tenantId BEFORE closing modal
                    final tenantId = accountService.tenantId;
                    if (tenantId == null) {
                      Navigator.pop(modalContext);
                      ScaffoldMessenger.of(parentContext).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Error: No se pudo determinar la tienda'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    Navigator.pop(modalContext);

                    try {
                      // Auto-attach active job if any
                      String? contextType;
                      String? contextId;
                      final activeServices = accountService.serviceHistory
                          .where((s) =>
                              !['ENTREGADO', 'CANCELADO'].contains(s['status']))
                          .toList();
                      if (activeServices.isNotEmpty) {
                        contextType = 'job';
                        contextId = activeServices.first['id'];
                      }

                      debugPrint(
                          '📤 Creating chat request with tenantId: $tenantId');
                      final conversationId =
                          await _messagingService.createChatRequest(
                        initialMessage: message,
                        contextType: contextType,
                        contextId: contextId,
                        tenantId: tenantId,
                      );

                      debugPrint('✅ Chat created: $conversationId');
                      if (mounted) {
                        _loadConversations();
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Consulta enviada. Te responderemos pronto.'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        // Navigate to the new chat using parent context
                        parentContext
                            .go('/tienda/cuenta/chats/$conversationId');
                      }
                    } catch (e, stack) {
                      debugPrint('❌ Error creating chat: $e');
                      debugPrint('$stack');
                      if (mounted) {
                        ScaffoldMessenger.of(parentContext).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.send),
                  label: const Text('ENVIAR'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback onTap;

  const _ConversationCard({
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final status = conversation['status'] ?? 'pending';
    final title = conversation['title'] ?? 'Consulta';
    final contextType = conversation['context_type'];
    final messages = conversation['messages'] as List? ?? [];
    final lastMessage = messages.isNotEmpty ? messages.last : null;
    final updatedAt = conversation['last_message_at'] != null
        ? DateTime.parse(conversation['last_message_at'])
        : DateTime.now();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Icon based on context
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getContextIcon(contextType),
                  color: _getStatusColor(status),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _getContextLabel(contextType) ?? title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildStatusBadge(status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (lastMessage != null)
                      Text(
                        lastMessage['content'] ?? '',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(updatedAt),
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getStatusLabel(status),
        style: TextStyle(
          color: _getStatusColor(status),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'active':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'PENDIENTE';
      case 'active':
        return 'ACTIVO';
      case 'resolved':
        return 'RESUELTO';
      case 'rejected':
        return 'RECHAZADO';
      default:
        return status.toUpperCase();
    }
  }

  IconData _getContextIcon(String? contextType) {
    switch (contextType) {
      case 'job':
        return Icons.build_circle_outlined;
      case 'order':
        return Icons.shopping_bag_outlined;
      case 'bike':
        return Icons.pedal_bike;
      case 'invoice':
        return Icons.receipt_long_outlined;
      default:
        return Icons.chat_bubble_outline;
    }
  }

  String? _getContextLabel(String? contextType) {
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
        return null;
    }
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} hrs';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
    return '${time.day}/${time.month}/${time.year}';
  }
}
