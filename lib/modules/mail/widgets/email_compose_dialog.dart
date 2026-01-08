import 'package:flutter/material.dart';
import '../models/zoho_email.dart';
import '../services/zoho_mail_service.dart';

/// Email compose dialog - for new emails and replies
class EmailComposeDialog extends StatefulWidget {
  final ZohoMailService mailService;
  final ZohoEmail? replyTo;
  final bool replyAll;
  final ZohoEmail? forward;
  final VoidCallback? onSent;

  const EmailComposeDialog({
    super.key,
    required this.mailService,
    this.replyTo,
    this.replyAll = false,
    this.forward,
    this.onSent,
  });

  @override
  State<EmailComposeDialog> createState() => _EmailComposeDialogState();
}

class _EmailComposeDialogState extends State<EmailComposeDialog> {
  final _toController = TextEditingController();
  final _ccController = TextEditingController();
  final _subjectController = TextEditingController();
  final _contentController = TextEditingController();

  bool _isSending = false;
  bool _showCc = false;

  @override
  void initState() {
    super.initState();
    _prepopulateFields();
  }

  void _prepopulateFields() {
    if (widget.replyTo != null) {
      // Reply mode
      _toController.text = widget.replyTo!.senderEmail;
      _subjectController.text = widget.replyTo!.subject.startsWith('Re:')
          ? widget.replyTo!.subject
          : 'Re: ${widget.replyTo!.subject}';

      if (widget.replyAll && widget.replyTo!.ccAddress != null) {
        _ccController.text = widget.replyTo!.ccAddress!;
        _showCc = true;
      }

      // Add quoted content
      _contentController.text =
          '\n\n---\nEl ${_formatDate(widget.replyTo!.receivedTime)}, ${widget.replyTo!.senderName} escribió:\n\n${widget.replyTo!.summary ?? ''}';
    } else if (widget.forward != null) {
      // Forward mode
      _subjectController.text = 'Fwd: ${widget.forward!.subject}';
      _contentController.text =
          '\n\n--- Mensaje reenviado ---\nDe: ${widget.forward!.fromAddress}\nFecha: ${_formatDate(widget.forward!.receivedTime)}\nAsunto: ${widget.forward!.subject}\n\n${widget.forward!.summary ?? ''}';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _subjectController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_toController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un destinatario')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      bool success;

      if (widget.replyTo != null) {
        // Send reply
        success = await widget.mailService.replyToEmail(
          messageId: widget.replyTo!.messageId,
          content: _contentController.text,
          replyAll: widget.replyAll,
        );
      } else {
        // Send new email
        success = await widget.mailService.sendEmail(
          to: _toController.text.trim(),
          subject: _subjectController.text.trim(),
          content: _contentController.text,
          cc: _ccController.text.trim().isNotEmpty
              ? _ccController.text.trim()
              : null,
        );
      }

      if (success && mounted) {
        Navigator.pop(context);
        widget.onSent?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Correo enviado'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.mailService.error ?? 'Error al enviar'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isReply = widget.replyTo != null;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 700,
          maxHeight: 700,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    isReply
                        ? (widget.replyAll ? 'Responder a todos' : 'Responder')
                        : widget.forward != null
                            ? 'Reenviar'
                            : 'Nuevo correo',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // To field
              TextField(
                controller: _toController,
                decoration: InputDecoration(
                  labelText: 'Para',
                  border: const OutlineInputBorder(),
                  suffixIcon: !_showCc
                      ? IconButton(
                          onPressed: () => setState(() => _showCc = true),
                          icon: const Icon(Icons.add),
                          tooltip: 'Agregar CC',
                        )
                      : null,
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              if (_showCc) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _ccController,
                  decoration: const InputDecoration(
                    labelText: 'CC',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
              const SizedBox(height: 12),
              // Subject
              TextField(
                controller: _subjectController,
                decoration: const InputDecoration(
                  labelText: 'Asunto',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // Content
              Expanded(
                child: TextField(
                  controller: _contentController,
                  decoration: const InputDecoration(
                    hintText: 'Escribe tu mensaje...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                ),
              ),
              const SizedBox(height: 16),
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSending ? null : () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isSending ? null : _send,
                    icon: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isSending ? 'Enviando...' : 'Enviar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
