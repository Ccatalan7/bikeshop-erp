import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../models/message.dart';
import '../models/message_reply.dart';
import '../utils/share_destinations.dart';
import 'share_destination_sliver.dart';

/// «Reenviar» desde un chat: la misma lista de destinos que el menú Compartir
/// del teléfono —cualquier chat, cliente, proveedor, compañero o número—.
///
/// Elegir el destino deja los mensajes en el compositor de ese chat (los
/// archivos como adjuntos, el texto en la caja) y lo abre; se envían desde
/// ahí. Así un cliente que no escribió en 24 h recibe primero el saludo que
/// Meta exige, en vez de un «debe responder primero» sin salida.
Future<void> showChatForwardPage(
  BuildContext context, {
  required List<Message> messages,
  required String sourceConversationId,
  required Future<void> Function(ShareDestination destination) onChoose,
  ShareDirectoryLoader? directoryLoader,
}) {
  final size = MediaQuery.sizeOf(context);
  final page = ChatForwardPage(
    messages: messages,
    sourceConversationId: sourceConversationId,
    onChoose: onChoose,
    directoryLoader: directoryLoader,
  );
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (_) => size.width < 600
        ? Dialog.fullscreen(child: page)
        : Dialog(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 520,
              height: math.min(720, size.height * 0.85),
              child: page,
            ),
          ),
  );
}

class ChatForwardPage extends StatefulWidget {
  const ChatForwardPage({
    super.key,
    required this.messages,
    required this.sourceConversationId,
    required this.onChoose,
    this.directoryLoader,
  });

  final List<Message> messages;
  final String sourceConversationId;

  /// Lee los adjuntos y los deja en el destino. Un error vuelve como aviso y
  /// la pantalla sigue abierta para elegir otro.
  final Future<void> Function(ShareDestination destination) onChoose;
  final ShareDirectoryLoader? directoryLoader;

  @override
  State<ChatForwardPage> createState() => _ChatForwardPageState();
}

class _ChatForwardPageState extends State<ChatForwardPage> {
  bool _busy = false;
  String? _error;

  Future<void> _choose(ShareDestination destination) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onChoose(destination);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error is StateError
            ? error.message.toString()
            : 'No se pudo abrir el chat con '
                '${shareDestinationLabel(destination)}. Revisa la conexión '
                'e intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final count = widget.messages.length;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          iconTheme: IconThemeData(color: scheme.onSurface),
          systemOverlayStyle: vinabikeSystemOverlayStyleFor(scheme.surface),
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          leading: IconButton(
            key: const ValueKey('chat-forward-close'),
            tooltip: 'Cancelar',
            onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reenviar',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                count == 1 ? '1 mensaje' : '$count mensajes',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
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
            slivers: [
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  decoration: BoxDecoration(
                    color:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      for (final message in widget.messages.take(4))
                        ListTile(
                          dense: true,
                          leading: Icon(switch (message.type) {
                            'image' => Icons.image_outlined,
                            'audio' => Icons.mic_none,
                            'file' => Icons.insert_drive_file_outlined,
                            _ => Icons.chat_bubble_outline,
                          }),
                          title: Text(
                            MessageReply.fromMessage(message).preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (count > 4)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'y ${count - 4} más',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: VbNotice(
                      tone: VbNoticeTone.danger,
                      title: 'No se reenvió',
                      body: _error,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Text(
                    'Queda en el chat que elijas, listo para enviar.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
              ShareDestinationSliver(
                keyPrefix: 'chat-forward',
                enabled: !_busy,
                excludeConversationId: widget.sourceConversationId,
                directoryLoader: widget.directoryLoader,
                onChoose: _choose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
