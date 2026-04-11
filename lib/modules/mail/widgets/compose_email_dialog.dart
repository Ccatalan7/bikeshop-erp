import 'package:flutter/material.dart';
import '../providers/mail_account_manager.dart';

/// Dialog for composing and sending emails
class ComposeEmailDialog extends StatefulWidget {
  final MailAccountManager manager;
  final String? replyTo;
  final String? replySubject;
  final String? quotedContent;
  final bool replyAll;

  const ComposeEmailDialog({
    super.key,
    required this.manager,
    this.replyTo,
    this.replySubject,
    this.quotedContent,
    this.replyAll = false,
  });

  @override
  State<ComposeEmailDialog> createState() => _ComposeEmailDialogState();
}

class _ComposeEmailDialogState extends State<ComposeEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  final _toController = TextEditingController();
  final _ccController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  String? _selectedProviderId;
  bool _isSending = false;
  bool _showCc = false;

  @override
  void initState() {
    super.initState();

    // Pre-fill for reply
    if (widget.replyTo != null) {
      _toController.text = widget.replyTo!;
    }
    if (widget.replySubject != null) {
      _subjectController.text = widget.replySubject!;
    }

    // Default to first connected provider
    final connected = widget.manager.connectedProviders;
    if (connected.isNotEmpty) {
      _selectedProviderId = connected.first.providerId;
    }
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProviderId == null) return;

    setState(() => _isSending = true);

    try {
      // Build content with quoted text if replying
      String content = _bodyController.text;
      if (widget.quotedContent != null) {
        content = '$content${widget.quotedContent}';
      }

      final success = await widget.manager.sendEmail(
        _selectedProviderId!,
        to: _toController.text.trim(),
        subject: _subjectController.text.trim(),
        content: content,
        cc: _ccController.text.trim().isNotEmpty
            ? _ccController.text.trim()
            : null,
      );

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Correo enviado'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al enviar correo'),
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
    final connected = widget.manager.connectedProviders;

    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.replyTo != null ? Icons.reply : Icons.edit,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.replyTo != null
                        ? (widget.replyAll ? 'Responder a todos' : 'Responder')
                        : 'Nuevo correo',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // From (provider selector)
                      Row(
                        children: [
                          SizedBox(
                            width: 60,
                            child: Text(
                              'Desde:',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedProviderId,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              items: connected
                                  .map((p) => DropdownMenuItem(
                                        value: p.providerId,
                                        child: Row(
                                          children: [
                                            _providerIcon(p.providerId),
                                            const SizedBox(width: 8),
                                            Text(p.accountEmail ??
                                                p.displayName),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (value) =>
                                  setState(() => _selectedProviderId = value),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // To
                      Row(
                        children: [
                          SizedBox(
                            width: 60,
                            child: Text(
                              'Para:',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _toController,
                              decoration: InputDecoration(
                                isDense: true,
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                suffixIcon: !_showCc
                                    ? TextButton(
                                        onPressed: () =>
                                            setState(() => _showCc = true),
                                        child: const Text('CC'),
                                      )
                                    : null,
                              ),
                              validator: (v) =>
                                  v?.isEmpty ?? true ? 'Requerido' : null,
                            ),
                          ),
                        ],
                      ),

                      // CC (optional)
                      if (_showCc) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            SizedBox(
                              width: 60,
                              child: Text(
                                'CC:',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: _ccController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Subject
                      Row(
                        children: [
                          SizedBox(
                            width: 60,
                            child: Text(
                              'Asunto:',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextFormField(
                              controller: _subjectController,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                              ),
                              validator: (v) =>
                                  v?.isEmpty ?? true ? 'Requerido' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Body
                      TextFormField(
                        controller: _bodyController,
                        decoration: const InputDecoration(
                          hintText: 'Escribe tu mensaje...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.all(16),
                        ),
                        maxLines: 10,
                        minLines: 5,
                      ),

                      // Show quoted content preview if replying
                      if (widget.quotedContent != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(
                                color: theme.colorScheme.outline,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Text(
                            'Mensaje original incluido en la respuesta',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _isSending ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isSending ? null : _send,
                    icon: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send, size: 18),
                    label: Text(_isSending ? 'Enviando...' : 'Enviar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerIcon(String providerId) {
    switch (providerId) {
      case 'gmail':
        return Image.asset('assets/icons/gmail_logo.webp',
            width: 18, height: 18);
      case 'zoho':
        return Image.asset('assets/icons/zoho_logo.png', width: 18, height: 18);
      default:
        return const Icon(Icons.email_outlined, size: 18);
    }
  }
}
