import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../bikeshop/services/bikeshop_service.dart';
import '../../sales/services/sales_service.dart';
import '../../sales/models/sales_models.dart';
import '../models/conversation.dart';
import '../services/messaging_service.dart';
import '../models/message.dart';
import '../models/autocomplete_suggestion.dart';
import 'parsed_message_text.dart';
import '../providers/chat_provider.dart';
import '../utils/message_parser.dart';
import 'assign_context_dialog.dart';
import '../../../shared/services/whatsapp_service.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/utils/invoice_pdf_generator.dart';

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
  final FocusNode _focusNode = FocusNode();
  final MessagingService _messagingService = MessagingService();
  bool _isSendingMessage = false;

  // Autocomplete State
  List<AutocompleteSuggestion> _suggestions = [];
  Timer? _debounce;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  // Scroll State
  int _previousMessageCount = 0;

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
    _focusNode.dispose();
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
    // Reset count when loading new chat so it triggers scroll on build
    _previousMessageCount = 0;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<ChatProvider>()
          .setActiveConversation(widget.conversation.id);
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSendingMessage) {
      return;
    }

    final chatProvider = context.read<ChatProvider>();
    final pendingText = text;
    final optimisticMessageId =
        'temp-wa-${DateTime.now().millisecondsSinceEpoch}';

    _messageController.clear();
    _restoreComposerFocus();
    setState(() => _isSendingMessage = true);

    try {
      final contact = await _resolveConversationWhatsAppContact();
      final phone = contact?['phone']?.toString();

      if (phone != null && phone.isNotEmpty) {
        final whatsappService = WhatsAppService();
        chatProvider.addOptimisticMessage(
          Message(
            id: optimisticMessageId,
            conversationId: widget.conversation.id,
            senderId: _messagingService.currentUserId,
            content: pendingText,
            type: 'text',
            metadata: const {
              'channel': 'whatsapp',
              'provider': 'whatsapp',
              'pending': true,
            },
            createdAt: DateTime.now(),
            isMe: true,
          ),
        );

        final success = await whatsappService.sendMessage(
          context: context,
          customerPhone: phone,
          message: pendingText,
          contactName: contact?['name']?.toString(),
          conversationId: widget.conversation.id,
          contextType: widget.conversation.contextType,
          contextId: widget.conversation.contextId,
        );

        if (!mounted) {
          return;
        }

        if (!success) {
          chatProvider.removeMessageById(optimisticMessageId);
          throw Exception('No se pudo enviar el mensaje por WhatsApp');
        }

        if (whatsappService.lastDeliveryMethod ==
            WhatsAppDeliveryMethod.cloudApi) {
          chatProvider.updateMessageMetadataById(
            optimisticMessageId,
            {
              'pending': false,
              'external_status': 'accepted',
            },
          );
        }

        if (whatsappService.lastDeliveryMethod ==
            WhatsAppDeliveryMethod.manualFallback) {
          _showWhatsAppResultSnackbar(
            context: context,
            deliveryMethod: whatsappService.lastDeliveryMethod,
            successMessage: 'Mensaje enviado por WhatsApp Cloud API',
            fallbackMessage: 'WhatsApp abierto con el mensaje prellenado',
          );
        }
        return;
      }

      await chatProvider.sendMessage(pendingText);
      if (!mounted) {
        return;
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      if (_messageController.text.trim().isEmpty) {
        _messageController.text = pendingText;
        _messageController.selection = TextSelection.collapsed(
          offset: _messageController.text.length,
        );
      }
      _restoreComposerFocus();
      _showErrorSnackBar(context, 'No se pudo enviar el mensaje: $e');
    } finally {
      if (mounted) {
        setState(() => _isSendingMessage = false);
      }
    }
  }

  void _restoreComposerFocus() {
    // On Web, post-frame callback isn't always enough due to engine/DOM sync.
    // A small delay ensures the focus request happens after the UI settles.
    Future.delayed(const Duration(milliseconds: 50), () {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  /// Accept a pending chat request
  Future<void> _acceptChatRequest(BuildContext ctx) async {
    try {
      final provider = ctx.read<ChatProvider>();
      await provider.acceptChatRequest(widget.conversation.id);
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('Chat aceptado. Ahora puedes responder.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Show reject dialog with reason input
  void _showRejectDialog(BuildContext ctx) {
    final reasonController = TextEditingController();
    showDialog(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('¿Por qué rechazas esta solicitud? (opcional)'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Motivo del rechazo...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                final provider = ctx.read<ChatProvider>();
                await provider.rejectChatRequest(
                  widget.conversation.id,
                  reasonController.text.trim(),
                );
                if (mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Solicitud rechazada'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
  }

  /// Pick and send a file (image, PDF, document, etc.)
  Future<void> _pickAndSendFile() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (!kIsWeb)
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Cámara'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('Archivo (PDF, Doc, etc.)'),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    try {
      late String fileName;
      Uint8List? bytes;

      if (choice == 'camera') {
        // Use ImagePicker for camera
        final picker = ImagePicker();
        final XFile? pickedFile = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1200,
          imageQuality: 85,
        );
        if (pickedFile == null) return;
        fileName = pickedFile.name;
        bytes = await pickedFile.readAsBytes();
      } else if (choice == 'gallery') {
        // Use ImagePicker for gallery (better image handling)
        final picker = ImagePicker();
        final XFile? pickedFile = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1200,
          imageQuality: 85,
        );
        if (pickedFile == null) return;
        fileName = pickedFile.name;
        bytes = await pickedFile.readAsBytes();
      } else {
        // Use FilePicker for documents
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'txt',
            'png',
            'jpg',
            'jpeg',
            'gif'
          ],
          withData: true,
        );
        if (result == null || result.files.isEmpty) return;
        final file = result.files.first;
        fileName = file.name;
        bytes = file.bytes;
      }

      if (bytes == null || !mounted) return;

      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white)),
            SizedBox(width: 12),
            Text('Subiendo archivo...'),
          ]),
          duration: Duration(seconds: 60),
        ),
      );

      // Determine file type and MIME
      final ext = fileName.split('.').last.toLowerCase();
      final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
      final isPdf = ext == 'pdf';

      String contentType;
      if (isImage) {
        contentType = 'image/$ext';
      } else if (isPdf) {
        contentType = 'application/pdf';
      } else if (['doc', 'docx'].contains(ext)) {
        contentType = 'application/msword';
      } else if (['xls', 'xlsx'].contains(ext)) {
        contentType = 'application/vnd.ms-excel';
      } else {
        contentType = 'application/octet-stream';
      }

      final storagePath =
          'chat/${DateTime.now().millisecondsSinceEpoch}_$fileName';

      // Upload to Supabase Storage (vinabike-assets bucket)
      final supabase = Supabase.instance.client;
      await supabase.storage.from('vinabike-assets').uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );

      // Get public URL
      final publicUrl =
          supabase.storage.from('vinabike-assets').getPublicUrl(storagePath);

      if (!mounted) return;

      // Dismiss loading snackbar
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Determine message type
      final msgType = isImage ? 'image' : 'file';

      // Send as file message
      context.read<ChatProvider>().sendMessage(
        publicUrl,
        type: msgType,
        metadata: {
          'url': publicUrl,
          'filename': fileName,
          'extension': ext,
          'contentType': contentType,
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error al subir archivo: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final messages = chatProvider.activeMessages;
    final isLoading = chatProvider.isLoading;

    // Detect new messages
    if (messages.length > _previousMessageCount) {
      _previousMessageCount = messages.length;
    }

    // Handle case where messages might be cleared (e.g. switching chats)
    if (messages.length < _previousMessageCount) {
      _previousMessageCount = messages.length;
    }

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
              // Link to Job/Invoice button
              IconButton(
                icon: Icon(
                  widget.conversation.contextType != null
                      ? Icons.link
                      : Icons.link_off,
                  color: widget.conversation.contextType != null
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                tooltip: widget.conversation.contextType != null
                    ? 'Vinculado a ${widget.conversation.contextType}'
                    : 'Vincular chat...',
                onPressed: () => _showAssignContextDialog(context),
              ),
            ],
          ),
        ),

        // Pending Chat Request Banner (for employees reviewing customer requests)
        if (widget.conversation.type == 'support' &&
            widget.conversation.status == 'pending')
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              border: Border(
                bottom: BorderSide(color: Colors.orange[200]!),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.pending_actions, color: Colors.orange[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Solicitud de chat pendiente',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'El cliente espera respuesta. Acepta para comenzar a chatear.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => _showRejectDialog(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[700],
                  ),
                  child: const Text('Rechazar'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () => _acceptChatRequest(context),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Aceptar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green[600],
                  ),
                ),
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
                    reverse: true, // Start from bottom
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      // Reverse index to show newest at bottom
                      final msg = messages[messages.length - 1 - index];
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
                icon: const Icon(Icons.flash_on, color: Colors.amber),
                tooltip: 'Acciones Rápidas',
                onPressed: () => _showSmartActions(context),
              ),
              IconButton(
                icon: const Icon(Icons.attach_file),
                onPressed: _pickAndSendFile,
              ),
              Expanded(
                child: CompositedTransformTarget(
                  link: _layerLink,
                  child: TextField(
                    controller: _messageController,
                    focusNode: _focusNode,
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

  /// Show dialog to link this conversation to a Job or Invoice
  void _showAssignContextDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AssignContextDialog(
        conversationId: widget.conversation.id,
        currentContextType: widget.conversation.contextType,
        currentContextId: widget.conversation.contextId,
      ),
    );
  }

  void _showSmartActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Acciones Rápidas',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.orange,
                child: Icon(Icons.description, color: Colors.white, size: 20),
              ),
              title: const Text('Solicitar Aprobación de Presupuesto'),
              subtitle: const Text('El cliente puede aprobar o rechazar'),
              onTap: () {
                Navigator.pop(ctx);
                _sendActionRequest(context, 'approve_quote');
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.green,
                child: Icon(Icons.payment, color: Colors.white, size: 20),
              ),
              title: const Text('Solicitar Pago'),
              subtitle: const Text('Envía botón de pago al cliente'),
              onTap: () {
                Navigator.pop(ctx);
                _sendActionRequest(context, 'pay_now');
              },
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blue,
                child:
                    Icon(Icons.local_shipping, color: Colors.white, size: 20),
              ),
              title: const Text('Confirmar Entrega'),
              subtitle: const Text('Cliente confirma recepción del producto'),
              onTap: () {
                Navigator.pop(ctx);
                _sendActionRequest(context, 'confirm_delivery');
              },
            ),
            const Divider(),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.grey,
                child: Icon(Icons.receipt_long, color: Colors.white, size: 20),
              ),
              title: const Text('Enviar Presupuesto (Antiguo)'),
              subtitle: const Text('Actualiza estado y notifica'),
              onTap: () {
                Navigator.pop(ctx);
                _handleSendQuote(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Send an action request message to the customer
  Future<void> _sendActionRequest(
      BuildContext context, String actionType) async {
    final conversation = widget.conversation;
    final contextType = conversation.contextType;
    final contextId = conversation.contextId;

    // Validate context
    if (contextId == null) {
      _showErrorSnackBar(
          context, 'No hay contexto asociado a este chat (Job/Invoice).');
      return;
    }

    String? invoiceId;
    String? jobId;
    double? amount;
    String? actionTargetId;
    String? actionKind;

    if (contextType == 'job') {
      jobId = contextId;
      try {
        final bikeshopService = context.read<BikeshopService>();
        final job = await bikeshopService.getJobById(contextId);
        if (job?.invoiceId != null) {
          invoiceId = job!.invoiceId;
        }
      } catch (e) {
        _showErrorSnackBar(context, 'Error al obtener datos del trabajo.');
        return;
      }
    } else if (contextType == 'invoice') {
      invoiceId = contextId;
    }

    // Get invoice amount for payment requests
    if (invoiceId != null && actionType == 'pay_now') {
      try {
        final salesService = context.read<SalesService>();
        final invoice = await salesService.fetchInvoice(invoiceId);
        amount = invoice?.balance ?? invoice?.total ?? 0;
      } catch (e) {
        debugPrint('Error fetching invoice: $e');
      }
    }

    if (actionType == 'approve_quote' && jobId == null) {
      if (invoiceId == null) {
        _showErrorSnackBar(
          context,
          'No se encontró una factura asociada para solicitar la aprobación.',
        );
        return;
      }
    }

    if (actionType == 'confirm_delivery' && jobId == null) {
      _showErrorSnackBar(
        context,
        'La confirmación de entrega por WhatsApp requiere una pega asociada.',
      );
      return;
    }

    if (actionType == 'pay_now' && invoiceId == null) {
      _showErrorSnackBar(
        context,
        'No se encontró una factura asociada para solicitar el pago.',
      );
      return;
    }

    // Build message content
    String content;
    switch (actionType) {
      case 'approve_quote':
        content = 'Por favor revisa y aprueba el presupuesto adjunto.';
        actionTargetId = invoiceId;
        actionKind = 'invoice';
        break;
      case 'pay_now':
        content = amount != null
            ? 'Tienes un saldo pendiente de \$${amount.toStringAsFixed(0)}. Por favor procede con el pago.'
            : 'Por favor procede con el pago.';
        actionTargetId = invoiceId;
        actionKind = 'invoice';
        break;
      case 'confirm_delivery':
        content = 'Tu pedido ha sido enviado. Por favor confirma la recepción.';
        actionTargetId = jobId;
        actionKind = 'job';
        break;
      default:
        content = 'Acción requerida.';
    }

    if (actionTargetId == null || actionKind == null) {
      _showErrorSnackBar(
        context,
        'No se pudo determinar el destino de la acción de WhatsApp.',
      );
      return;
    }

    try {
      final whatsappService = WhatsAppService();

      // For approve_quote, update invoice status to 'sent' first
      if (actionType == 'approve_quote' && invoiceId != null) {
        try {
          final salesService = context.read<SalesService>();
          await salesService.updateInvoiceStatus(invoiceId, InvoiceStatus.sent);
        } catch (e) {
          debugPrint('Error updating invoice status: $e');
        }
      }

      final success = await _sendWhatsAppInteractiveRequest(
        context: context,
        actionType: actionType,
        actionKind: actionKind,
        actionTargetId: actionTargetId,
        message: content,
        contextType: contextType,
        contextId: contextId,
        jobId: jobId,
        amount: amount,
        metadata: {
          'action_type': actionType,
          'target_id': actionTargetId,
          'invoiceId': invoiceId,
          if (jobId != null) 'jobId': jobId,
        },
      );

      if (!success || !mounted) {
        return;
      }

      if (mounted) {
        _showWhatsAppResultSnackbar(
          context: context,
          deliveryMethod: whatsappService.lastDeliveryMethod,
          successMessage: actionType == 'approve_quote'
              ? 'Presupuesto enviado por WhatsApp Cloud API'
              : 'Solicitud enviada por WhatsApp Cloud API',
          fallbackMessage: actionType == 'approve_quote'
              ? 'WhatsApp abierto con el presupuesto prellenado'
              : 'WhatsApp abierto con la solicitud prellenada',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleSendQuote(BuildContext context) async {
    final conversation = widget.conversation;
    // Check context
    final contextType = conversation.contextType;
    final contextId = conversation.contextId;

    if (contextId == null) {
      _showErrorSnackBar(
          context, 'No hay contexto asociado a este chat (Job/Invoice).');
      return;
    }

    String? jobId;
    String? invoiceId;

    if (contextType == 'job') {
      jobId = contextId;
      try {
        final bikeshopService = context.read<BikeshopService>();
        final job = await bikeshopService.getJobById(jobId);
        invoiceId = job?.invoiceId;
      } catch (e) {
        _showErrorSnackBar(context, 'Error al obtener datos del trabajo.');
        return;
      }
    } else if (contextType == 'invoice') {
      invoiceId = contextId;
    } else {
      _showErrorSnackBar(
        context,
        'El envío de presupuesto por WhatsApp requiere una factura o pega asociada.',
      );
      return;
    }

    if (invoiceId == null) {
      _showErrorSnackBar(
        context,
        'No se encontró una factura asociada para enviar el presupuesto.',
      );
      return;
    }

    // Confirm Action
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Enviar Presupuesto?'),
        content: const Text(
            'Esto cambiará el estado de la factura a "Enviado" y enviará una tarjeta de confirmación al cliente.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // 1. Update Invoice Status
      await context
          .read<SalesService>()
          .updateInvoiceStatus(invoiceId, InvoiceStatus.sent);

      // 2. Generate and Upload PDF
      String? documentUrl;
      String? documentFilename;
      try {
        final salesService = context.read<SalesService>();
        final invoiceToPrint = await salesService.fetchInvoice(
          invoiceId,
          refresh: true,
        );
        if (invoiceToPrint != null) {
          final resolvedBikeNames = await InvoicePdfGenerator.resolveBikeNames(
              context, invoiceToPrint);
          final pdfDoc = await InvoicePdfGenerator.generateInvoicePDF(
              context, invoiceToPrint, resolvedBikeNames);
          final pdfBytes = await pdfDoc.save();

          final db = context.read<DatabaseService>();
          final filename =
              'presupuestos/presupuesto_${invoiceToPrint.invoiceNumber}_${DateTime.now().millisecondsSinceEpoch}.pdf';

          await db.supabase.storage.from('vinabike-assets').uploadBinary(
                filename,
                pdfBytes,
                fileOptions: const FileOptions(
                    contentType: 'application/pdf', upsert: true),
              );

          documentUrl = db.supabase.storage
              .from('vinabike-assets')
              .getPublicUrl(filename);
          documentFilename = 'Presupuesto_${invoiceToPrint.invoiceNumber}.pdf';
        }
      } catch (e) {
        debugPrint('Error generating/uploading PDF for quote: $e');
      }

      final whatsappService = WhatsAppService();
      final success = await _sendWhatsAppInteractiveRequest(
        context: context,
        actionType: 'approve_quote',
        actionKind: 'invoice',
        actionTargetId: invoiceId,
        message:
            '📋 Presupuesto enviado\nPor favor revisa y confirma los detalles para proceder.',
        contextType: contextType,
        contextId: contextId,
        jobId: jobId,
        markQuoteSent: true,
        documentUrl: documentUrl,
        documentFilename: documentFilename,
        metadata: {
          'action_type': 'approve_quote',
          'target_id': invoiceId,
          'invoiceId': invoiceId,
          if (jobId != null) 'jobId': jobId,
        },
      );

      if (!success || !mounted) {
        return;
      }

      if (mounted) {
        _showWhatsAppResultSnackbar(
          context: context,
          deliveryMethod: whatsappService.lastDeliveryMethod,
          successMessage: 'Presupuesto enviado por WhatsApp Cloud API',
          fallbackMessage: 'WhatsApp abierto con el presupuesto prellenado',
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(context, 'Error al enviar presupuesto: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> _getSenderInfo(String senderId) async {
    return _messagingService.getSenderInfo(senderId);
  }

  Future<Map<String, dynamic>?> _resolveConversationWhatsAppContact() {
    return _messagingService.getSupportConversationContact(
      widget.conversation.id,
    );
  }

  Future<bool> _sendWhatsAppInteractiveRequest({
    required BuildContext context,
    required String actionType,
    required String actionKind,
    required String actionTargetId,
    required String message,
    String? customerId,
    String? contextType,
    String? contextId,
    String? jobId,
    double? amount,
    bool markQuoteSent = false,
    Map<String, dynamic>? metadata,
    String? documentUrl,
    String? documentFilename,
  }) async {
    final contact = await _resolveConversationWhatsAppContact();
    final phone = contact?['phone']?.toString();

    if (phone == null || phone.isEmpty) {
      throw Exception(
        'La conversación no tiene un contacto con teléfono para WhatsApp',
      );
    }

    final customerName = contact?['name']?.toString();
    final whatsappService = WhatsAppService();

    return whatsappService.sendInteractiveAction(
      context: context,
      customerPhone: phone,
      customerName: customerName == null || customerName.isEmpty
          ? 'Cliente'
          : customerName,
      conversationId: widget.conversation.id,
      customerId: customerId ?? contact?['customer_id']?.toString(),
      contextType: contextType,
      contextId: contextId,
      jobId: jobId,
      actionType: actionType,
      actionKind: actionKind,
      actionTargetId: actionTargetId,
      message: message,
      amount: amount,
      markQuoteSent: markQuoteSent,
      metadata: metadata,
      documentUrl: documentUrl,
      documentFilename: documentFilename,
    );
  }

  void _showWhatsAppResultSnackbar({
    required BuildContext context,
    required WhatsAppDeliveryMethod deliveryMethod,
    required String successMessage,
    required String fallbackMessage,
  }) {
    final content = switch (deliveryMethod) {
      WhatsAppDeliveryMethod.cloudApi => successMessage,
      WhatsAppDeliveryMethod.manualFallback => fallbackMessage,
      WhatsAppDeliveryMethod.failed => successMessage,
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(content),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Color _getNameColor(String name) {
    if (name == 'Cliente') return Colors.blue[800]!;

    final colors = [
      Colors.orange[800]!,
      Colors.purple[700]!,
      Colors.pink[700]!,
      Colors.teal[700]!,
      Colors.brown[700]!,
      Colors.indigo[700]!,
    ];
    return colors[name.hashCode.abs() % colors.length];
  }

  Widget _buildMessageBubble(BuildContext context, Message msg) {
    final isMe = msg.isMe; // In ERP context, "Me" is the logged-in employee

    return FutureBuilder<Map<String, dynamic>?>(
      future: msg.senderId != null
          ? _getSenderInfo(msg.senderId!)
          : Future.value(null),
      builder: (context, snapshot) {
        final senderInfo = snapshot.data;
        final senderName = senderInfo?['name'] ?? (isMe ? 'Tú' : 'Cliente');
        final senderAvatar = senderInfo?['avatar_url'];

        // Message Content Widget
        Widget contentWidget;
        if (msg.type == 'image') {
          contentWidget = GestureDetector(
            onTap: () {
              // Show full-screen image preview
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  backgroundColor: Colors.transparent,
                  child: Stack(
                    children: [
                      InteractiveViewer(
                        child: Image.network(msg.content),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 32),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                msg.content,
                width: 200,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    width: 200,
                    height: 150,
                    color: Colors.grey[300],
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 200,
                  height: 150,
                  color: Colors.grey[300],
                  child: const Icon(Icons.broken_image, size: 48),
                ),
              ),
            ),
          );
        } else if (msg.metadata['type'] == 'quote_request') {
          contentWidget = _buildQuoteCard(context, msg, isMe);
        } else if (msg.type == 'file') {
          // File attachment (PDF, doc, etc.)
          contentWidget = GestureDetector(
            onTap: () async {
              // Open URL in browser
              final url = Uri.parse(msg.content);
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              } else {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'No se pudo abrir: ${msg.metadata['filename'] ?? 'archivo'}')),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? Colors.white.withOpacity(0.3) : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getFileIcon(msg.metadata['extension'] ?? ''),
                    color: isMe ? Colors.black87 : Colors.blue[600],
                    size: 32,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg.metadata['filename'] ?? 'Archivo',
                          style: TextStyle(
                            color: isMe ? Colors.black87 : Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          (msg.metadata['extension'] ?? '').toUpperCase(),
                          style: TextStyle(
                            color: isMe ? Colors.black54 : Colors.grey[600],
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.download,
                    color: isMe ? Colors.black54 : Colors.grey[500],
                    size: 20,
                  ),
                ],
              ),
            ),
          );
        } else if (msg.type == 'action_request') {
          // ACTION REQUEST - Interactive buttons for customers
          contentWidget = _buildActionRequestCard(context, msg, isMe);
        } else {
          // Text Message
          contentWidget = ParsedMessageText(
            text: msg.content,
            isMe: isMe,
            onReferenceTap: widget.onReferenceTap,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
            ),
          );
        }

        // Timestamp
        final timeStr = DateFormat('HH:mm').format(msg.createdAt);

        // Bubble Decoration
        final bubbleDecoration = BoxDecoration(
          color: isMe ? const Color(0xFFD9FDD3) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 1,
              offset: const Offset(0, 1),
            ),
          ],
        );

        if (!isMe) {
          // INCOMING MESSAGE
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.grey[200],
                  backgroundImage:
                      senderAvatar != null ? NetworkImage(senderAvatar) : null,
                  child: senderAvatar == null
                      ? Icon(Icons.person, size: 16, color: Colors.grey[500])
                      : null,
                ),
                const SizedBox(width: 8),

                // Bubble
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: bubbleDecoration,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sender Name (Colored)
                        Text(
                          senderName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _getNameColor(senderName),
                          ),
                        ),
                        const SizedBox(height: 2),

                        contentWidget,

                        // Timestamp
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, left: 8),
                            child: Text(
                              timeStr,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
          );
        }

        // OUTGOING MESSAGE
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 40),
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  decoration: bubbleDecoration,
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: contentWidget,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: _buildOutgoingMessageFooter(msg, timeStr),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Handle customer response to action request
  Future<void> _handleActionResponse(
    BuildContext context,
    String messageId,
    String actionType,
    String? targetId,
    String response,
  ) async {
    try {
      final supabase = Supabase.instance.client;

      // Update the message metadata with the response
      await supabase.from('messages').update({
        'metadata': {
          'status': response,
          'responded_at': DateTime.now().toIso8601String(),
        },
      }).eq('id', messageId);

      // If accepted, perform the action
      if (response == 'accepted' && targetId != null) {
        switch (actionType) {
          case 'approve_quote':
            // Update invoice status to confirmed
            final salesService =
                Provider.of<SalesService>(context, listen: false);
            await salesService.updateInvoiceStatus(
                targetId, InvoiceStatus.confirmed);
            break;
          case 'pay_now':
            // Navigate to payment page or show payment dialog
            // This would typically trigger a MercadoPago checkout
            debugPrint('💳 Payment requested for invoice: $targetId');
            break;
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                response == 'accepted' ? '✅ Acción completada' : 'Rechazado'),
            backgroundColor:
                response == 'accepted' ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Get appropriate icon for file extension
  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'txt':
        return Icons.text_snippet;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  Widget _buildOutgoingMessageFooter(Message msg, String timeStr) {
    final statusIcon = _buildWhatsAppStatusIcon(msg);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeStr,
          style: TextStyle(
            color: Colors.grey[500],
            fontSize: 10,
          ),
        ),
        if (statusIcon != null) ...[
          const SizedBox(width: 4),
          statusIcon,
        ],
      ],
    );
  }

  Widget? _buildWhatsAppStatusIcon(Message msg) {
    final metadata = msg.metadata;
    final isWhatsAppMessage =
        metadata['provider'] == 'whatsapp' || metadata['channel'] == 'whatsapp';

    if (!isWhatsAppMessage) {
      return null;
    }

    if (metadata['pending'] == true) {
      return Icon(
        Icons.access_time_rounded,
        size: 13,
        color: Colors.grey[500],
      );
    }

    final externalStatus =
        metadata['external_status']?.toString().toLowerCase();

    switch (externalStatus) {
      case 'accepted':
      case 'sent':
        return Icon(
          Icons.done_rounded,
          size: 14,
          color: Colors.grey[500],
        );
      case 'delivered':
        return Icon(
          Icons.done_all_rounded,
          size: 14,
          color: Colors.grey[500],
        );
      case 'read':
        return const Icon(
          Icons.done_all_rounded,
          size: 14,
          color: Colors.lightBlue,
        );
      case 'failed':
        return const Icon(
          Icons.error_outline_rounded,
          size: 13,
          color: Colors.red,
        );
      default:
        return null;
    }
  }

  Widget _buildQuoteCard(BuildContext context, Message msg, bool isMe) {
    final invoiceId = msg.metadata['invoiceId'];
    final isConfirmed = msg.metadata['status'] == 'confirmed';

    // High contrast colors for both sender (green bubble) and receiver (white bubble)
    // On green bubble (isMe), we use Dark Green/Black text.
    // On white bubble (!isMe), we use Green/Black text.
    final headerIconColor = isMe ? Colors.green[900] : Colors.green;
    final headerTextColor = isMe ? Colors.green[900] : Colors.green[800];
    final headerBgColor =
        isMe ? Colors.black.withOpacity(0.05) : Colors.green[50];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: headerBgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.receipt_long, color: headerIconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Presupuesto',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: headerTextColor,
                  ),
                ),
              ),
              if (isConfirmed)
                Icon(Icons.check_circle, color: headerIconColor, size: 16),
            ],
          ),
        ),

        // Body
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                msg.content.split('\n').first,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.black87, // Always dark for readability
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isMe
                    ? 'Esperando confirmación del cliente.'
                    : 'Por favor revisa y confirma para proceder.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black54, // Always dark grey
                ),
              ),
            ],
          ),
        ),

        // Actions
        if (!isMe && !isConfirmed)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _confirmQuote(context, invoiceId),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Confirmar Presupuesto'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),

        if (isConfirmed)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text('✅ Confirmado',
                  style: TextStyle(
                      color: Colors.green[800], // Always visible
                      fontWeight: FontWeight.bold)),
            ),
          ),
      ],
    );
  }

  Widget _buildActionRequestCard(BuildContext context, Message msg, bool isMe) {
    final actionType = msg.metadata['action_type'] as String? ?? 'unknown';
    final targetId = msg.metadata['target_id'] as String?;
    final status = msg.metadata['status'] as String? ?? 'pending';
    final amount = msg.metadata['amount'] as num?;

    // Determine card appearance based on action type
    IconData icon;
    String title;
    String buttonLabel;
    Color accentColor;

    // Contrast Logic:
    // Bubbles are Light Green (Me) or White (Other).
    // Text should ALWAYS be dark (Black/Dark Grey).
    // Feature colors (icons/titles) should be dark versions of their accent.

    Color iconColor;
    Color titleColor = Colors.black87;
    Color headerBgColor =
        isMe ? Colors.black.withOpacity(0.05) : Colors.grey[50]!;

    switch (actionType) {
      case 'approve_quote':
        icon = Icons.description;
        if (status == 'accepted') {
          title = 'Presupuesto Aprobado';
          accentColor = Colors.green;
        } else if (status == 'declined') {
          title = 'Presupuesto Rechazado';
          accentColor = Colors.red;
        } else {
          title = 'Presupuesto Enviado';
          accentColor = Colors.orange;
        }
        buttonLabel = 'Aprobar Presupuesto';
        // Use darker shade for icon to ensure visibility on light green
        iconColor = isMe ? Colors.black54 : accentColor;
        break;
      case 'pay_now':
        icon = Icons.payment;
        title = 'Solicitud de Pago';
        buttonLabel = amount != null
            ? 'Pagar \$${amount.toStringAsFixed(0)}'
            : 'Pagar Ahora';
        accentColor = Colors.green;
        iconColor =
            isMe ? Colors.green[900]! : accentColor; // Visible green on green
        break;
      case 'confirm_delivery':
        icon = Icons.local_shipping;
        title = 'Confirmar Entrega';
        buttonLabel = 'Confirmar Recepción';
        accentColor = Colors.blue;
        iconColor =
            isMe ? Colors.blue[900]! : accentColor; // Visible blue on green
        break;
      default:
        icon = Icons.help_outline;
        title = 'Acción Requerida';
        buttonLabel = 'Ver Detalles';
        accentColor = Colors.grey;
        iconColor = Colors.grey[700]!;
    }

    // Build status badge
    Widget statusBadge = const SizedBox.shrink();
    if (status == 'accepted') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (isMe ? Colors.black : Colors.green).withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 14, color: Colors.green[800]),
            const SizedBox(width: 4),
            Text('Aceptado',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[900],
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    } else if (status == 'declined') {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (isMe ? Colors.black : Colors.red).withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel, size: 14, color: Colors.red[800]),
            const SizedBox(width: 4),
            Text('Rechazado',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.red[900],
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: headerBgColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: titleColor,
                  ),
                ),
              ),
              statusBadge,
            ],
          ),
        ),
        // Message content
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            msg.content,
            style: const TextStyle(
                color: Colors.black87, fontSize: 13, height: 1.4),
          ),
        ),
        // Action button (only if pending and viewer is not sender)
        if (status == 'pending' && !isMe)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _handleActionResponse(
                        context, msg.id, actionType, targetId, 'declined'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey[700],
                    ),
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _handleActionResponse(
                        context, msg.id, actionType, targetId, 'accepted'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                    ),
                    child: Text(buttonLabel),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmQuote(BuildContext context, String? invoiceId) async {
    if (invoiceId == null) return;

    try {
      await context
          .read<SalesService>()
          .updateInvoiceStatus(invoiceId, InvoiceStatus.confirmed);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Presupuesto confirmado. ¡Gracias!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al confirmar: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }
}
