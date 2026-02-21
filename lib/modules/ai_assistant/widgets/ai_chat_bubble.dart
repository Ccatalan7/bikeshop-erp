import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../inventory/services/inventory_service.dart';
import '../../../shared/services/workspace_manager.dart';
import '../services/ai_service.dart';

class AIAssistantButton extends StatelessWidget {
  final List<MechanicJob> jobs;

  const AIAssistantButton({super.key, required this.jobs});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        context.read<WorkspaceManager>().toggleAIPanel();
      },
      child: const Icon(Icons.smart_toy),
      tooltip: 'Asistente IA',
    );
  }
}

class AIChatPanel extends StatefulWidget {
  final List<MechanicJob> jobs;

  const AIChatPanel({super.key, required this.jobs});

  @override
  State<AIChatPanel> createState() => _AIChatPanelState();
}

class _AIChatPanelState extends State<AIChatPanel> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = []; // 'role', 'text'
  late AIAssistantService _aiService;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _aiService = AIAssistantService();
    _aiService.initialize();

    // Add welcome message
    _messages.add({
      'role': 'assistant',
      'text':
          'Hola! Soy tu asistente de taller. Puedo ayudarte a analizar trabajos, buscar productos en el inventario, y más. ¿Qué necesitas?'
    });
  }

  /// Called by the AI when it wants to navigate somewhere inside the app.
  void _handleAINavigation(String route, {String? searchTerm}) {
    debugPrint(
        '🧭 [AIChatPanel] AI navigation requested: $route (search: $searchTerm)');

    // Use WorkspaceManager to navigate since we are now a global side panel
    final workspaceManager = context.read<WorkspaceManager>();

    // Defer the navigation slightly so the UI doesn't stutter while animating the chat response
    WidgetsBinding.instance.addPostFrameCallback((_) {
      workspaceManager.navigateActiveWorkspace(route);
    });
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _controller.clear();
    });

    _scrollToBottom();

    final inventoryService = context.read<InventoryService>();
    final response = await _aiService.sendMessage(
      text,
      jobs: widget.jobs,
      inventoryService: inventoryService,
      onNavigate: _handleAINavigation,
    );

    if (mounted) {
      setState(() {
        _messages.add({'role': 'assistant', 'text': response});
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400, // Fixed width for the side panel
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          left: BorderSide(color: Theme.of(context).dividerColor),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(-2, 0),
            blurRadius: 10,
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.smart_toy, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  const Text('Asistente Taller',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  context.read<WorkspaceManager>().toggleAIPanel();
                },
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: const BoxConstraints(maxWidth: 400),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Theme.of(context).primaryColor
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: isUser
                        ? Text(msg['text']!,
                            style: const TextStyle(color: Colors.white))
                        : MarkdownBody(data: msg['text']!),
                  ),
                );
              },
            ),
          ),
          if (_aiService.isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Pregunta o pide algo al asistente...',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendMessage,
                color: Theme.of(context).primaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
