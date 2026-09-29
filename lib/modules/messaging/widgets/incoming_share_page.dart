import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/services/incoming_share_service.dart';
import '../../../shared/services/media_compressor.dart';
import '../../../shared/services/ocr_file_handoff_service.dart';
import '../../../shared/services/right_toolbar_service.dart';
import '../../../shared/services/workspace_manager.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../storage/models/app_stored_file.dart';
import '../../storage/services/app_file_storage_service.dart';
import '../models/chat_attachment_draft.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../services/messaging_attachment_service.dart';
import '../utils/conversation_channel_presentation.dart';
import '../utils/incoming_share_intake.dart';
import 'counterparty_avatar_image.dart';

/// Lo que se abre al elegir «WhatsApp ERP» o «Viñabike ERP» en el menú
/// Compartir del teléfono.
///
/// «WhatsApp ERP» va directo a los chats, con «Guardar en Archivos» en el menú
/// ⋮. «Viñabike ERP» abre primero el menú de destinos: WhatsApp, Archivos, un
/// gasto o una factura de compra (los dos últimos por el mismo OCR que usa
/// Archivos, [OcrFileHandoffService]). **Elegir el chat no envía.** Los archivos quedan en
/// el compositor de ese chat, donde el operador los revisa, les escribe un
/// texto y aprieta enviar; es la misma regla del reenvío y de todo borrador
/// preparado fuera del chat.
///
/// Una foto o un video que pasa el tope de WhatsApp se comprime solo al abrir
/// la pantalla ([MediaCompressor]); Archivos guarda siempre el original.
class IncomingSharePage extends StatefulWidget {
  const IncomingSharePage({
    super.key,
    required this.batch,
    required this.service,
    this.compressor,
  });

  final IncomingShareBatch batch;
  final IncomingShareService service;
  final MediaCompressor? compressor;

  @override
  State<IncomingSharePage> createState() => _IncomingSharePageState();
}

class _IncomingSharePageState extends State<IncomingSharePage> {
  late final MediaCompressor _compressor =
      widget.compressor ?? MediaCompressor.instance;
  late final List<IncomingShareItem> _originals = IncomingShareIntake.classify(
    widget.batch.files,
    canCompressVideo: _compressor.canCompressVideo,
  );
  late final List<IncomingShareItem> _items = List.of(_originals);

  /// Fotos comprimidas en memoria (el original sigue en disco para Archivos).
  final Map<int, Uint8List> _compressedBytes = {};

  /// Índice → avance 0–100 mientras se comprime.
  final Map<int, int> _progress = {};
  final Set<int> _compressed = {};
  final TextEditingController _search = TextEditingController();
  final Set<int> _savedToFiles = {};
  String? _activeVideoId;
  late bool _choosingChat = widget.batch.target == IncomingShareTarget.whatsApp;
  bool _compressionStarted = false;
  Timer? _warmup;
  bool _warming = false;
  bool _busy = false;
  bool _handedOff = false;
  String? _error;

  List<int> get _sendableIndexes => [
        for (var index = 0; index < _items.length; index++)
          if (_items[index].canSendByWhatsApp) index,
      ];

  bool get _compressing => _progress.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    final chat = context.read<ChatProvider>();
    // Si la app se abrió desde el menú Compartir, la bandeja puede no haber
    // cargado —ni tener la sesión lista— todavía. La lista aparece apenas
    // llega; mientras tanto se espera un rato antes de afirmar que no hay chats.
    if (chat.conversations.isEmpty) {
      _warming = true;
      _warmup = Timer(const Duration(seconds: 8), () {
        if (mounted) setState(() => _warming = false);
      });
      unawaited(chat.loadConversations());
    }
    if (_choosingChat) _startCompression();
  }

  /// Sólo cuando el destino es WhatsApp: Archivos y el OCR usan el original.
  void _startCompression() {
    if (_compressionStarted) return;
    _compressionStarted = true;
    for (var index = 0; index < _items.length; index++) {
      if (_items[index].needsCompression) _progress[index] = 0;
    }
    if (_progress.isNotEmpty) unawaited(_compressOversized());
  }

  void _chooseWhatsApp() {
    setState(() {
      _choosingChat = true;
      _error = null;
      _startCompression();
    });
  }

  /// El OCR lee una sola boleta o factura: foto o PDF.
  bool get _canReadWithOcr =>
      _originals.length == 1 &&
      (_originals.single.file.isImage ||
          _originals.single.file.mimeType == 'application/pdf');

  Future<void> _sendToOcr(OcrFileHandoffTarget target) async {
    if (_busy || _handedOff || !_canReadWithOcr) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final file = _originals.single.file;
    try {
      final bytes = await XFile(file.path).readAsBytes();
      if (!mounted) return;
      final dot = file.name.lastIndexOf('.');
      context.read<OcrFileHandoffService>().queue(
            target: target,
            fileName: file.name,
            mimeType: file.mimeType,
            bytes: bytes,
            extension:
                dot < 0 ? '' : file.name.substring(dot + 1).toLowerCase(),
            sourceLabel: 'Compartido desde el teléfono',
          );
      final messenger = ScaffoldMessenger.of(context);
      final toolbar = context.read<RightToolbarService>();
      final workspaces = context.read<WorkspaceManager>();
      _handedOff = true;
      Navigator.of(context).pop();
      // Los mismos destinos que «OCR como gasto» y «OCR factura compra» de
      // Archivos.
      if (target == OcrFileHandoffTarget.quickExpense) {
        toolbar.openTool(ToolbarTool.expenses);
        messenger.showSnackBar(
          const SnackBar(content: Text('Boleta enviada a Gastos rápidos.')),
        );
      } else {
        workspaces.navigateActiveWorkspace('/purchases/new');
        messenger.showSnackBar(
          const SnackBar(content: Text('Factura enviada a una compra nueva.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _handedOff = false;
        _error = 'No se pudo leer el archivo. Vuelve a compartirlo.';
      });
    }
  }

  @override
  void dispose() {
    _warmup?.cancel();
    final video = _activeVideoId;
    if (video != null) unawaited(_compressor.cancel(video));
    _search.dispose();
    // Cerrar sin elegir descarta la copia del teléfono; un envío o un guardado
    // ya leyeron los bytes que necesitaban.
    unawaited(widget.service.release(widget.batch));
    super.dispose();
  }

  /// De a uno: comprimir dos videos a la vez no termina antes y calienta el
  /// teléfono.
  Future<void> _compressOversized() async {
    for (final index in _progress.keys.toList()) {
      if (!mounted) return;
      final item = _items[index];
      IncomingShareItem next;
      try {
        if (item.compression == IncomingShareCompression.image) {
          final original = await XFile(item.file.path).readAsBytes();
          final bytes = await MediaCompressor.compressImage(
            original,
            maxBytes: MessagingAttachmentService.maxImageBytes,
          );
          if (bytes == null) {
            throw const MediaCompressionException(
              'unreadable',
              'No se pudo leer la foto para comprimirla.',
            );
          }
          _compressedBytes[index] = bytes;
          next = IncomingShareIntake.compressed(
            path: item.file.path,
            name: compressedFileName(item.file.name, 'jpg'),
            mimeType: 'image/jpeg',
            sizeBytes: bytes.length,
          );
        } else {
          final id = 'share-${widget.batch.id}-$index';
          _activeVideoId = id;
          final video = await _compressor.compressVideo(
            id: id,
            path: item.file.path,
            maxBytes: MessagingAttachmentService.maxAudioVideoBytes,
            onProgress: (percent) {
              if (mounted) setState(() => _progress[index] = percent);
            },
          );
          _activeVideoId = null;
          next = IncomingShareIntake.compressed(
            path: video.path,
            name: compressedFileName(item.file.name, 'mp4'),
            mimeType: 'video/mp4',
            sizeBytes: video.sizeBytes,
          );
        }
      } on MediaCompressionException catch (error) {
        _activeVideoId = null;
        next =
            IncomingShareItem(file: item.file, whatsAppProblem: error.message);
      } catch (_) {
        _activeVideoId = null;
        next = IncomingShareItem(
          file: item.file,
          whatsAppProblem: 'No se pudo comprimir.',
        );
      }
      if (!mounted) return;
      setState(() {
        _items[index] = next;
        _progress.remove(index);
        if (next.canSendByWhatsApp) _compressed.add(index);
      });
    }
  }

  Future<void> _sendTo(Conversation conversation) async {
    if (_busy || _handedOff || _compressing) return;
    final sendable = _sendableIndexes;
    if (sendable.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final attachments = <PendingChatAttachment>[];
      for (final index in sendable) {
        final item = _items[index];
        final bytes = _compressedBytes[index] ??
            await XFile(item.file.path).readAsBytes();
        attachments.add(
          PendingChatAttachment(
            id: 'shared-$stamp-$index',
            fileName: item.file.name,
            bytes: bytes,
            extension: item.validation!.extension,
            isImage: item.validation!.contentType.startsWith('image/'),
          ),
        );
      }
      if (!mounted) return;
      final chat = context.read<ChatProvider>();
      final toolbar = context.read<RightToolbarService>();
      chat.offerComposerAttachments(conversation.id, attachments);
      _handedOff = true;
      Navigator.of(context).pop();
      // La misma bandeja que abre una notificación del teléfono: el rail
      // derecho en escritorio, pantalla completa en compacto.
      toolbar.openConversation(
        tool: conversation.isSupplierConversation
            ? ToolbarTool.supplierMessages
            : ToolbarTool.messages,
        conversationId: conversation.id,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudieron leer los archivos. Vuelve a compartirlos.';
      });
    }
  }

  /// Guarda los originales, sin comprimir: la biblioteca no tiene el tope de
  /// WhatsApp.
  Future<void> _saveToFiles() async {
    if (_busy || _handedOff) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final toolbar = context.read<RightToolbarService>();
    String? failedName;
    for (var index = 0; index < _originals.length; index++) {
      if (_savedToFiles.contains(index)) continue;
      final file = _originals[index].file;
      try {
        final Uint8List bytes = await XFile(file.path).readAsBytes();
        await AppFileStorageService.instance.saveFile(
          bytes: bytes,
          fileName: file.name,
          mimeType: file.mimeType,
          context: const AppFileContext(
            sourceType: 'manual',
            sourceProvider: 'phone_share',
            sourceRoute: '/storage',
            contextType: 'manual',
            contextTitle: 'Compartido desde el teléfono',
          ),
        );
        // Un reintento no vuelve a subir lo que ya quedó guardado.
        _savedToFiles.add(index);
      } catch (_) {
        failedName = file.name;
        break;
      }
    }
    if (!mounted) return;
    if (failedName != null) {
      setState(() {
        _busy = false;
        _error = _savedToFiles.isEmpty
            ? 'No se pudo guardar $failedName. Revisa la conexión e intenta de nuevo.'
            : 'Se guardaron ${_savedToFiles.length} de ${_originals.length}. '
                'No se pudo guardar $failedName; intenta de nuevo.';
      });
      return;
    }
    _handedOff = true;
    Navigator.of(context).pop();
    final count = _savedToFiles.length;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          count == 1
              ? 'Guardado en Archivos.'
              : '$count archivos guardados en Archivos.',
        ),
        action: SnackBarAction(
          label: 'Ver',
          onPressed: () => toolbar.openTool(ToolbarTool.storage),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chat = context.watch<ChatProvider>();
    final destinations = IncomingShareIntake.destinations(
      chat.conversations,
      query: _search.text,
      titleFor: chat.getChatTitle,
    );
    final rejected = [
      for (var index = 0; index < _items.length; index++)
        if (!_items[index].canSendByWhatsApp && !_progress.containsKey(index))
          _items[index],
    ];
    final canSend = _sendableIndexes.isNotEmpty;
    final fileCount = widget.batch.files.length;
    final shrinking = [
      for (final index in {..._progress.keys, ..._compressed})
        _compressionLine(index),
    ];
    final fromHub = widget.batch.target == IncomingShareTarget.hub;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          // El AppBar del tema es navy con tinta blanca; esta pantalla es
          // clara. Sin esto, la X y los iconos del sistema quedaban blancos
          // sobre blanco (emulador Android, 2026-09-29).
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          iconTheme: IconThemeData(color: scheme.onSurface),
          actionsIconTheme: IconThemeData(color: scheme.onSurface),
          systemOverlayStyle: vinabikeSystemOverlayStyleFor(scheme.surface),
          surfaceTintColor: Colors.transparent,
          leading: fromHub && _choosingChat
              ? IconButton(
                  key: const ValueKey('incoming-share-back'),
                  tooltip: 'Volver a las opciones',
                  onPressed: _busy
                      ? null
                      : () => setState(() => _choosingChat = false),
                  icon: const BackButtonIcon(),
                )
              : IconButton(
                  key: const ValueKey('incoming-share-close'),
                  tooltip: 'Descartar',
                  onPressed:
                      _busy ? null : () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _choosingChat ? 'Enviar por WhatsApp' : 'Viñabike ERP',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                fileCount == 1 ? '1 archivo' : '$fileCount archivos',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            if (_choosingChat)
              PopupMenuButton<String>(
                key: const ValueKey('incoming-share-more'),
                tooltip: 'Más opciones',
                enabled: !_busy && _originals.isNotEmpty,
                onSelected: (value) {
                  if (value == 'files') _saveToFiles();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    key: ValueKey('incoming-share-save-files'),
                    value: 'files',
                    child: ListTile(
                      leading: Icon(Icons.folder_outlined),
                      title: Text('Guardar en Archivos'),
                      subtitle: Text('Los originales, sin enviar'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
          ],
          bottom: _busy
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: SafeArea(
          top: false,
          child: CustomScrollView(
            slivers: !_choosingChat
                ? _hubSlivers(context)
                : [
                    if (_items.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _SharedFilesStrip(
                          items: _items,
                          progress: _progress,
                          compressed: _compressed,
                        ),
                      ),
                    if (_error != null)
                      _noticeSliver(
                        VbNotice(
                          tone: VbNoticeTone.danger,
                          title: 'No se completó',
                          body: _error,
                        ),
                      ),
                    if (shrinking.isNotEmpty)
                      _noticeSliver(
                        VbNotice(
                          key: const ValueKey('incoming-share-compression'),
                          tone: VbNoticeTone.info,
                          title: _compressing
                              ? 'Comprimiendo para WhatsApp'
                              : 'Comprimidos para WhatsApp',
                          body: shrinking.join('\n'),
                        ),
                      ),
                    if (rejected.isNotEmpty || widget.batch.skipped.isNotEmpty)
                      _noticeSliver(
                        VbNotice(
                          tone: VbNoticeTone.warning,
                          title: canSend || _compressing
                              ? 'Algunos archivos no van por WhatsApp'
                              : 'Estos archivos no van por WhatsApp',
                          body: [
                            for (final item in rejected)
                              '${item.file.name}: ${item.whatsAppProblem}',
                            for (final skip in widget.batch.skipped)
                              '${skip.name}: ${skip.explanation}',
                          ].join('\n'),
                        ),
                      ),
                    if (canSend || _compressing) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                          child: TextField(
                            key: const ValueKey('incoming-share-search'),
                            controller: _search,
                            enabled: !_busy,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Buscar cliente, proveedor o teléfono',
                              prefixIcon: const Icon(Icons.search),
                              isDense: true,
                              filled: true,
                              fillColor: scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.6),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _conversationSliver(context, chat, destinations),
                    ] else
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Puedes guardarlos en Archivos del ERP.',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _busy ? null : _saveToFiles,
                                icon: const Icon(Icons.folder_outlined),
                                label: const Text('Guardar en Archivos'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
          ),
        ),
      ),
    );
  }

  /// «Viñabike ERP»: qué hacer con lo compartido.
  List<Widget> _hubSlivers(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ocrHint = _canReadWithOcr ? null : 'Comparte una sola foto o PDF';
    return [
      if (_items.isNotEmpty)
        SliverToBoxAdapter(
          child: _SharedFilesStrip(
            items: _originals,
            progress: const {},
            compressed: const {},
            // Acá todavía no hay destino: nada está «rechazado».
            neutral: true,
          ),
        ),
      if (_error != null)
        _noticeSliver(
          VbNotice(
            tone: VbNoticeTone.danger,
            title: 'No se completó',
            body: _error,
          ),
        ),
      if (widget.batch.skipped.isNotEmpty)
        _noticeSliver(
          VbNotice(
            tone: VbNoticeTone.warning,
            title: 'Algunos archivos no se pudieron traer',
            body: [
              for (final skip in widget.batch.skipped)
                '${skip.name}: ${skip.explanation}',
            ].join('\n'),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '¿Qué hacemos con esto?',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ),
      ),
      if (_originals.isNotEmpty)
        SliverList.list(
          children: [
            _HubActionTile(
              key: const ValueKey('incoming-share-hub-whatsapp'),
              icon: ConversationChannelPresentation.platformIconForChannel(
                'whatsapp',
              ),
              title: 'Enviar por WhatsApp',
              subtitle: 'A un chat de cliente o proveedor',
              enabled: !_busy,
              onTap: _chooseWhatsApp,
            ),
            _HubActionTile(
              key: const ValueKey('incoming-share-hub-files'),
              icon: Icons.folder_outlined,
              title: 'Guardar en Archivos',
              subtitle: 'La biblioteca de archivos del ERP',
              enabled: !_busy,
              onTap: _saveToFiles,
            ),
            _HubActionTile(
              key: const ValueKey('incoming-share-hub-expense'),
              icon: Icons.receipt_long_outlined,
              title: 'Registrar un gasto',
              subtitle: ocrHint ?? 'Lee la boleta y abre Gastos rápidos',
              enabled: !_busy && ocrHint == null,
              onTap: () => _sendToOcr(OcrFileHandoffTarget.quickExpense),
            ),
            _HubActionTile(
              key: const ValueKey('incoming-share-hub-purchase'),
              icon: Icons.document_scanner_outlined,
              title: 'Factura de compra',
              subtitle: ocrHint ?? 'Lee la factura y abre una compra nueva',
              enabled: !_busy && ocrHint == null,
              onTap: () => _sendToOcr(OcrFileHandoffTarget.purchaseInvoice),
            ),
          ],
        ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ];
  }

  Widget _noticeSliver(Widget notice) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: notice,
        ),
      );

  String _compressionLine(int index) {
    final name = _originals[index].file.name;
    final percent = _progress[index];
    if (percent != null) {
      return _items[index].compression == IncomingShareCompression.video
          ? '$name: comprimiendo… $percent %'
          : '$name: comprimiendo…';
    }
    return '$name: ${formatShareSize(_originals[index].file.sizeBytes)} → '
        '${formatShareSize(_items[index].file.sizeBytes)}';
  }

  Widget _conversationSliver(
    BuildContext context,
    ChatProvider chat,
    List<Conversation> destinations,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (destinations.isEmpty) {
      final loading = _warming && chat.conversations.isEmpty;
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Text(
                  _search.text.trim().isEmpty
                      ? 'No hay chats de WhatsApp abiertos.'
                      : 'Ningún chat coincide con «${_search.text.trim()}».',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
        ),
      );
    }
    // Mientras se comprime no se puede elegir: el chat recibiría el original
    // que WhatsApp rechaza.
    final enabled = !_busy && !_compressing;
    return SliverList.builder(
      itemCount: destinations.length,
      itemBuilder: (context, index) {
        final conversation = destinations[index];
        return _ConversationDestinationTile(
          conversation: conversation,
          title: chat.getChatTitle(conversation),
          enabled: enabled,
          onTap: () => _sendTo(conversation),
        );
      },
    );
  }
}

String formatShareSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.round()} KB';
  return '${(kb / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
}

/// Miniaturas de lo compartido: la foto misma, o el tipo y el peso de un
/// documento. Lo que no va por WhatsApp se marca, sin esconderlo.
class _SharedFilesStrip extends StatelessWidget {
  const _SharedFilesStrip({
    required this.items,
    required this.progress,
    required this.compressed,
    this.neutral = false,
  });

  final List<IncomingShareItem> items;
  final Map<int, int> progress;
  final Set<int> compressed;

  /// Sin destino elegido: no se marca lo que WhatsApp no acepta.
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _SharedFileCard(
          item: items[index],
          progress: progress[index],
          compressed: compressed.contains(index),
          neutral: neutral,
        ),
      ),
    );
  }
}

class _SharedFileCard extends StatelessWidget {
  const _SharedFileCard({
    required this.item,
    this.progress,
    this.compressed = false,
    this.neutral = false,
  });

  final bool neutral;

  final IncomingShareItem item;

  /// 0–100 mientras se comprime.
  final int? progress;
  final bool compressed;

  static const double _size = 88;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final file = item.file;

    final label = progress != null
        ? '${file.name}. Comprimiendo para WhatsApp'
        : neutral || item.canSendByWhatsApp
            ? compressed
                ? '${file.name}. Comprimido para WhatsApp'
                : file.name
            : '${file.name}. No va por WhatsApp: ${item.whatsAppProblem}';

    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: SizedBox(
          width: _size,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    width: _size,
                    height: _size,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: roles.hairline),
                    ),
                    child: file.isImage
                        ? _ImageThumbnail(path: file.path)
                        : _DocumentGlyph(file: file),
                  ),
                  if (progress != null)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: roles.scrim.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              // Una foto no informa avance: gira sin valor.
                              value: item.compression ==
                                          IncomingShareCompression.video &&
                                      progress! > 0
                                  ? progress! / 100
                                  : null,
                              color: Colors.white,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (!neutral && !item.canSendByWhatsApp)
                    _CardBadge(
                      icon: Icons.priority_high_rounded,
                      tone: roles.warning,
                    )
                  else if (compressed)
                    _CardBadge(icon: Icons.compress_rounded, tone: roles.info),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubActionTile extends StatelessWidget {
  const _HubActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: enabled
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          size: 22,
          color: enabled ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _CardBadge extends StatelessWidget {
  const _CardBadge({required this.icon, required this.tone});

  final IconData icon;
  final VinabikeSemanticTone tone;

  @override
  Widget build(BuildContext context) => Positioned(
        right: 4,
        top: 4,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration:
              BoxDecoration(color: tone.container, shape: BoxShape.circle),
          child: Icon(icon, size: 14, color: tone.onContainer),
        ),
      );
}

class _ImageThumbnail extends StatefulWidget {
  const _ImageThumbnail({required this.path});

  final String path;

  @override
  State<_ImageThumbnail> createState() => _ImageThumbnailState();
}

class _ImageThumbnailState extends State<_ImageThumbnail> {
  late final Future<Uint8List> _bytes = XFile(widget.path).readAsBytes();

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return Icon(
            Icons.image_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
        }
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          // Una foto de 12 MP decodificada completa pesa ~48 MB en memoria.
          cacheWidth: (_SharedFileCard._size * dpr).round(),
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Icon(
            Icons.broken_image_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}

class _DocumentGlyph extends StatelessWidget {
  const _DocumentGlyph({required this.file});

  final IncomingSharedFile file;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dot = file.name.lastIndexOf('.');
    final extension = dot < 0 ? '' : file.name.substring(dot + 1).toUpperCase();
    final icon = switch (file.mimeType) {
      final type when type.startsWith('video/') => Icons.movie_outlined,
      final type when type.startsWith('audio/') => Icons.graphic_eq,
      'application/pdf' => Icons.picture_as_pdf_outlined,
      _ => Icons.description_outlined,
    };
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 28, color: scheme.primary),
        const SizedBox(height: 6),
        Text(
          [
            if (extension.isNotEmpty) extension,
            formatShareSize(file.sizeBytes),
          ].join(' · '),
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ConversationDestinationTile extends StatelessWidget {
  const _ConversationDestinationTile({
    required this.conversation,
    required this.title,
    required this.enabled,
    required this.onTap,
  });

  final Conversation conversation;
  final String title;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hint = conversation.contextHint;
    final phone = (conversation.isSupplierConversation
            ? hint?.supplierPhone ?? hint?.phone
            : hint?.phone)
        ?.trim();
    final counterparty =
        conversation.isSupplierConversation ? 'Proveedor' : 'Cliente';
    final subtitle = [
      counterparty,
      if (phone != null && phone.isNotEmpty && phone != title) phone,
    ].join(' · ');
    final when = _formatWhen(conversation.lastMessageAt);

    return ListTile(
      key: ValueKey('incoming-share-chat-${conversation.id}'),
      enabled: enabled,
      onTap: onTap,
      minTileHeight: 64,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: _Avatar(conversation: conversation, title: title),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: when == null
          ? null
          : Text(
              when,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
    );
  }

  static String? _formatWhen(DateTime? value) {
    if (value == null) return null;
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final days = today.difference(day).inDays;
    if (days == 0) {
      return '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';
    }
    if (days == 1) return 'ayer';
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${local.day} ${months[local.month - 1]}';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.conversation, required this.title});

  final Conversation conversation;
  final String title;

  @override
  Widget build(BuildContext context) {
    final accent = ConversationChannelPresentation.accent(conversation);
    final initials = _initials(title.split(' · ').first);
    // El verde de WhatsApp es oscuro: sobre el fondo oscuro las iniciales no
    // se leían. En oscuro se aclara la tinta, no el color del canal.
    final ink = Theme.of(context).brightness == Brightness.dark
        ? HSLColor.fromColor(accent).withLightness(0.72).toColor()
        : accent;
    final fallback = CircleAvatar(
      radius: 22,
      backgroundColor: accent.withValues(alpha: 0.12),
      child: Text(
        initials,
        style: TextStyle(
          color: ink,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      ),
    );
    final url = conversation.contextHint?.counterpartyImageUrl;
    return SizedBox(
      width: 44,
      height: 44,
      child: url == null || url.isEmpty
          ? fallback
          : CounterpartyAvatarImage(
              url: url,
              size: 44,
              isMark: conversation.isSupplierConversation,
              backdrop: accent.withValues(alpha: 0.10),
              fallback: fallback,
            ),
    );
  }

  static String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    if (RegExp(r'^\+?[0-9 ]+$').hasMatch(trimmed)) return '#';
    final words = trimmed.split(RegExp(r'\s+'));
    if (words.length == 1) {
      return words.first.characters.take(2).toString().toUpperCase();
    }
    return '${words.first.characters.first}${words.last.characters.first}'
        .toUpperCase();
  }
}
