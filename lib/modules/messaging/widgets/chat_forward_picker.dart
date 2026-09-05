import 'package:flutter/material.dart';

import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/message_reply.dart';

/// Choosing a destination never sends. The final button submits the frozen
/// selection once; a lost acknowledgement must not offer an automatic replay.
class ChatForwardPicker extends StatefulWidget {
  const ChatForwardPicker({
    super.key,
    required this.messages,
    required this.destinations,
    required this.titleFor,
    required this.onSend,
  });

  final List<Message> messages;
  final List<Conversation> destinations;
  final String Function(Conversation) titleFor;
  final Future<void> Function(Conversation) onSend;

  @override
  State<ChatForwardPicker> createState() => _ChatForwardPickerState();
}

class _ChatForwardPickerState extends State<ChatForwardPicker> {
  Conversation? _destination;
  bool _attempted = false;
  bool _sending = false;
  String? _error;

  Future<void> _send() async {
    final destination = _destination;
    if (destination == null || _attempted) return;
    setState(() {
      _attempted = true;
      _sending = true;
    });
    try {
      await widget.onSend(destination);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is StateError
            ? error.message.toString()
            : 'No se pudo confirmar el reenvío. Revisa el chat destino antes de volver a enviar.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VbSearchableSelect<Conversation>(
            value: _destination,
            options: [
              for (final conversation in widget.destinations)
                VbSearchableSelectOption(
                  value: conversation,
                  label: widget.titleFor(conversation),
                  context: conversation.shortChannelLabel,
                ),
            ],
            onChanged: _attempted
                ? null
                : (value) => setState(() => _destination = value),
            sheetTitle: 'Reenviar a un chat',
            label: 'Destinatario',
            placeholder: 'Elegir chat',
            semanticLabel: 'Elegir destinatario del reenvío',
            emptyLabel: 'No hay chats disponibles',
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final message in widget.messages)
                    ListTile(
                      leading: Icon(switch (message.type) {
                        'image' => Icons.image_outlined,
                        'audio' => Icons.mic_none,
                        'file' => Icons.insert_drive_file_outlined,
                        _ => Icons.chat_bubble_outline,
                      }),
                      title: Text(MessageReply.fromMessage(message).preview),
                      subtitle: message.metadata['filename'] != null &&
                              message.metadata['filename'] != message.content
                          ? Text(message.metadata['filename'].toString())
                          : null,
                    ),
                ],
              ),
            ),
          ),
          if (_error != null)
            VbNotice(
              tone: VbNoticeTone.neutral,
              title: 'Reenvío detenido',
              body: _error!,
            ),
          if (_sending) const LinearProgressIndicator(),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _sending ? null : () => Navigator.of(context).pop(),
                child: Text(_attempted ? 'Cerrar' : 'Cancelar'),
              ),
              FilledButton(
                key: const ValueKey('chat-forward-confirm'),
                onPressed: _destination == null || _attempted ? null : _send,
                child: const Text('Reenviar'),
              ),
            ],
          ),
        ],
      );
}
