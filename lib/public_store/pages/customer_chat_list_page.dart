import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/models/conversation.dart';
import '../theme/public_store_theme.dart';

class CustomerChatListPage extends StatefulWidget {
  const CustomerChatListPage({super.key});

  @override
  State<CustomerChatListPage> createState() => _CustomerChatListPageState();
}

class _CustomerChatListPageState extends State<CustomerChatListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Load support conversations
      context.read<ChatProvider>().loadConversations(type: 'support');
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final conversations = chatProvider.conversations;

    return Column(
      children: [
        // Header
        Container(
          color: Theme.of(context).primaryColor,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top,
            left: 8,
            right: 8,
            bottom: 12,
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => context.go('/cuenta'),
              ),
              const Expanded(
                child: Text(
                  'Ayuda y Soporte',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                icon:
                    const Icon(Icons.add_comment_outlined, color: Colors.white),
                onPressed: () => _showCreateTicketDialog(context),
                tooltip: 'Nuevo ticket',
              ),
            ],
          ),
        ),

        // List
        Expanded(
          child: chatProvider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : conversations.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: conversations.length,
                      separatorBuilder: (c, i) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _buildConversationCard(
                            context, conversations[index]);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.support_agent, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '¿Necesitas ayuda?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Inicia una conversación con nuestro equipo.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => _showCreateTicketDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('NUEVO MENSAJE'),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationCard(
      BuildContext context, Conversation conversation) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: InkWell(
        onTap: () {
          context.go('/cuenta/mensajes/${conversation.id}');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: PublicStoreTheme.primaryBlue.withOpacity(0.1),
                child: Icon(Icons.chat_bubble_outline,
                    color: PublicStoreTheme.primaryBlue),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.title ?? 'Sin título',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Última actividad: ${_formatDate(conversation.updatedAt)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateTicketDialog(BuildContext context) async {
    final titleController = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo Mensaje'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(
            labelText: 'Asunto o Motivo',
            hintText: 'Ej: Consulta sobre mi pedido #123',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () async {
              if (titleController.text.trim().isNotEmpty) {
                Navigator.pop(context); // Close dialog
                final provider = context.read<ChatProvider>();
                await provider.createTicket(titleController.text.trim());
                if (context.mounted && provider.activeConversationId != null) {
                  context
                      .go('/cuenta/mensajes/${provider.activeConversationId}');
                }
              }
            },
            child: const Text('CREAR'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat('dd MMM HH:mm', 'es_CL').format(date);
  }
}
