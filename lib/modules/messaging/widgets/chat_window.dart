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
  final FocusNode _focusNode = FocusNode();

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

  // ... (keeping _onTextChanged and others same)

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

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isNotEmpty) {
      context.read<ChatProvider>().sendMessage(text);
      _messageController.clear();
      // Keep focus on the text field after sending
      // On Web, post-frame callback isn't always enough due to engine/DOM sync.
      // A small delay ensures the focus request happens after the UI settles.
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) {
          FocusScope.of(context).requestFocus(_focusNode);
        }
      });
    }
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
      String? fileName;
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

      if (bytes == null || fileName == null || !mounted) return;

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
            // Render image or text based on message type
            if (msg.type == 'image')
              GestureDetector(
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
              )
            else if (msg.type == 'file')
              // File attachment (PDF, doc, etc.)
              GestureDetector(
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
                    color: isMe ? Colors.blue[700] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _getFileIcon(msg.metadata['extension'] ?? ''),
                        color: isMe ? Colors.white : Colors.blue[600],
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
                                color: isMe ? Colors.white : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              (msg.metadata['extension'] ?? '').toUpperCase(),
                              style: TextStyle(
                                color: isMe ? Colors.white70 : Colors.grey[600],
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.download,
                        color: isMe ? Colors.white70 : Colors.grey[500],
                        size: 20,
                      ),
                    ],
                  ),
                ),
              )
            else
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
}
