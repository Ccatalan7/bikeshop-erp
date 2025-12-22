import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../sales/services/sales_service.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/autocomplete_suggestion.dart';
import 'parsed_message_text.dart';
import '../providers/chat_provider.dart';
import '../utils/message_parser.dart';

class ChatWindow extends StatefulWidget {
  final Conversation conversation;
  final Function(ReferenceSegment)? onReferenceTap;

  const ChatWindow({
    super.key,
    required this.conversation,
    this.onReferenceTap,
  });

  @override
  State<ChatWindow> createState() => _ChatWindowState();
}

class _ChatWindowState extends State<ChatWindow> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Autocomplete State
  List<AutocompleteSuggestion> _suggestions = [];
  Timer? _debounce;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void didUpdateWidget(covariant ChatWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation.id != widget.conversation.id) {
      _loadMessages();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    _removeOverlay();
    super.dispose();
  }

  void _onTextChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    final text = _messageController.text;
    final selection = _messageController.selection;

    if (selection.baseOffset < 0) return;

    // Check if we are typing a reference (starts with #)
    // We look backwards from cursor to find the last #
    final textBeforeCursor = text.substring(0, selection.baseOffset);
    final hashIndex = textBeforeCursor.lastIndexOf('#');

    if (hashIndex != -1) {
      // confirm no whitespace after the hash (except waiting for first char)
      final query = textBeforeCursor.substring(hashIndex + 1);
      if (!query.contains(' ')) {
        _debounce = Timer(const Duration(milliseconds: 300), () {
          _search(query);
        });
        return;
      }
    }

    _removeOverlay();
  }

  Future<void> _search(String query) async {
    // setState(() => _isLoadingSuggestions = true); // Unused for now

    final suggestions = <AutocompleteSuggestion>[];

    try {
      // 1. Jobs (Search if query is empty or matches JOB pattern)
      if (query.isEmpty || query.toUpperCase().startsWith('J')) {
        // If query implies specific number e.g. "JOB-123", extract "123"
        // For simplicity, we just pass the raw query or parts of it
        final term =
            query.toUpperCase().replaceAll('JOB-', '').replaceAll('JOB', '');
        final jobs =
            await context.read<BikeshopService>().getJobs(searchTerm: term);
        suggestions.addAll(jobs.take(3).map((j) => AutocompleteSuggestion(
              id: 'JOB-${j.jobNumber}',
              title: 'Job #${j.jobNumber ?? "N/A"}',
              subtitle:
                  '${j.assignedTechnicianName ?? "Sin mecánico"} - ${j.status.name}',
              type: SuggestionType.job,
            )));
      }

      // 2. Invoices (Search if query is empty or matches INV pattern)
      if (query.isEmpty || query.toUpperCase().startsWith('I')) {
        final term =
            query.toUpperCase().replaceAll('INV-', '').replaceAll('INV', '');
        final invoices = context.read<SalesService>().searchInvoices(term);
        suggestions.addAll(invoices.take(3).map((i) => AutocompleteSuggestion(
              id: 'INV-${i.invoiceNumber}',
              title: 'Invoice #${i.invoiceNumber}',
              subtitle: '${i.customerName} - \$${i.total.toStringAsFixed(0)}',
              type: SuggestionType.invoice,
            )));
      }
    } catch (e) {
      debugPrint('Autocomplete Error: $e');
    }

    if (mounted) {
      setState(() {
        _suggestions = suggestions;
        // _isLoadingSuggestions = false;
      });
      if (suggestions.isNotEmpty) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    }
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: 300, // Fixed width or dynamic
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, -200), // Show above
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: Colors.grey[200]!)),
                      color: Colors.grey[50],
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.flash_on, size: 16, color: Colors.amber),
                        SizedBox(width: 4),
                        Text('Quick Insert',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _suggestions.length,
                      itemBuilder: (context, index) {
                        final item = _suggestions[index];
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            item.type == SuggestionType.job
                                ? Icons.build
                                : Icons.receipt,
                            size: 16,
                            color: Colors.blue,
                          ),
                          title: Text(item.title,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          subtitle: Text(item.subtitle ?? '',
                              style: const TextStyle(fontSize: 11)),
                          onTap: () => _applySuggestion(item),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _applySuggestion(AutocompleteSuggestion item) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final textBeforeCursor = text.substring(0, selection.baseOffset);
    final hashIndex = textBeforeCursor.lastIndexOf('#');

    if (hashIndex != -1) {
      final newText =
          text.replaceRange(hashIndex, selection.baseOffset, '#${item.id} ');
      _messageController.value = TextEditingValue(
        text: newText,
        selection:
            TextSelection.collapsed(offset: hashIndex + item.id.length + 2),
      );
    }
    _removeOverlay();
  }

  void _loadMessages() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<ChatProvider>()
          .setActiveConversation(widget.conversation.id);
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      context.read<ChatProvider>().sendMessage(text);
      _messageController.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
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
    final chatProvider = context.watch<ChatProvider>();
    final messages = chatProvider.activeMessages;
    final isLoading = chatProvider.isLoading;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
            color: Colors.white,
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.grey[200],
                child: const Icon(Icons.person, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chatProvider.getChatTitle(widget.conversation),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    widget.conversation.type.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Actions (optional: resolve ticket, etc)
              IconButton(
                  icon: const Icon(Icons.info_outline), onPressed: () {}),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: Container(
            color: Colors.grey[50], // Light background for chat area
            child: isLoading && messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      // Check continuity for bubble grouping (optional enhancement space)
                      return _buildMessageBubble(context, msg);
                    },
                  ),
          ),
        ),

        // Input
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey[200]!)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: () {
                  // TODO: File upload
                },
              ),
              Expanded(
                child: CompositedTransformTarget(
                  link: _layerLink,
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje... (# para ref)',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.blue),
                onPressed: _sendMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(BuildContext context, Message msg) {
    final isMe = msg.isMe; // In ERP context, "Me" is the logged-in employee

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.6,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue[600] : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 12),
          ),
          boxShadow: [
            if (!isMe)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            ParsedMessageText(
              text: msg.content,
              isMe: isMe,
              onReferenceTap: widget.onReferenceTap,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black87,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(msg.createdAt),
              style: TextStyle(
                color: isMe ? Colors.white70 : Colors.grey[500],
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
