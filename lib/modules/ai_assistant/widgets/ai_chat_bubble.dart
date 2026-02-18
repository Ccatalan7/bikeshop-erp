import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'package:provider/provider.dart';
import '../../bikeshop/models/bikeshop_models.dart';
import '../../inventory/services/inventory_service.dart';
import '../services/ai_service.dart';

class AIAssistantButton extends StatelessWidget {
  final List<MechanicJob> jobs;

  const AIAssistantButton({super.key, required this.jobs});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => AIChatDialog(jobs: jobs),
        );
      },
      child: const Icon(Icons.smart_toy),
      tooltip: 'Assistant AI',
    );
  }
}

class AIChatDialog extends StatefulWidget {
  final List<MechanicJob> jobs;

  const AIChatDialog({super.key, required this.jobs});

  @override
  State<AIChatDialog> createState() => _AIChatDialogState();
}

class _AIChatDialogState extends State<AIChatDialog> {
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
          'Hola! Soy tu asistente de taller. Puedo ayudarte a analizar los trabajos actuales. ¿Qué necesitas saber?'
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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.smart_toy,
                        color: Theme.of(context).primaryColor),
                    const SizedBox(width: 8),
                    const Text('Asistente Taller',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
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
                      hintText: 'Pregunta sobre los trabajos...',
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
      ),
    );
  }
}
