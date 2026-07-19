import 'dart:async';

import 'package:flutter/material.dart';
import '../providers/email_provider.dart';
import '../providers/mail_account_manager.dart';

bool isValidMailRecipientList(String value, {bool allowEmpty = false}) {
  final normalized = value.trim();
  if (normalized.isEmpty) return allowEmpty;

  final recipients = normalized
      .split(RegExp(r'[,;]'))
      .map((recipient) => recipient.trim())
      .where((recipient) => recipient.isNotEmpty)
      .toList(growable: false);
  if (recipients.isEmpty) return false;

  final emailPattern = RegExp(r'^[^\s@,;]+@[^\s@,;]+\.[^\s@,;]+$');
  return recipients.every(emailPattern.hasMatch);
}

/// Dialog for composing and sending emails
class ComposeEmailDialog extends StatefulWidget {
  final MailAccountManager manager;
  final String? initialProviderId;
  final String? replyTo;
  final String? replySubject;
  final String? quotedContent;
  final bool replyAll;

  const ComposeEmailDialog({
    super.key,
    required this.manager,
    this.initialProviderId,
    this.replyTo,
    this.replySubject,
    this.quotedContent,
    this.replyAll = false,
  });

  @override
  State<ComposeEmailDialog> createState() => _ComposeEmailDialogState();
}

class _ComposeSenderOption {
  final EmailProvider provider;
  final EmailSenderIdentity identity;

  const _ComposeSenderOption({
    required this.provider,
    required this.identity,
  });

  String get key => '${provider.providerId}:${identity.normalizedAddress}';
}

class _ComposeEmailDialogState extends State<ComposeEmailDialog> {
  final _formKey = GlobalKey<FormState>();
  final _toController = TextEditingController();
  final _ccController = TextEditingController();
  final _bccController = TextEditingController();
  final _subjectController = TextEditingController();
  final _bodyController = TextEditingController();

  String? _selectedSenderKey;
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

    _syncSelectedSender(preserveCurrent: false);
    unawaited(_refreshSenderOptions());

    _toController.addListener(_onDraftChanged);
    _ccController.addListener(_onDraftChanged);
    _bccController.addListener(_onDraftChanged);
    _subjectController.addListener(_onDraftChanged);
    _bodyController.addListener(_onDraftChanged);
  }

  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  List<_ComposeSenderOption> get _senderOptions {
    final options = <_ComposeSenderOption>[];
    final seen = <String>{};
    for (final provider in widget.manager.connectedProviders) {
      for (final identity in provider.senderIdentities) {
        final option = _ComposeSenderOption(
          provider: provider,
          identity: identity,
        );
        if (seen.add(option.key)) options.add(option);
      }
    }
    return options;
  }

  _ComposeSenderOption? get _selectedSender {
    final selectedKey = _selectedSenderKey;
    if (selectedKey == null) return null;
    for (final option in _senderOptions) {
      if (option.key == selectedKey) return option;
    }
    return null;
  }

  void _syncSelectedSender({bool preserveCurrent = true}) {
    final options = _senderOptions;
    if (preserveCurrent &&
        options.any((option) => option.key == _selectedSenderKey)) {
      return;
    }

    final requestedProviderId = widget.initialProviderId;
    if (requestedProviderId != null) {
      final requestedProvider = widget.manager.getProvider(requestedProviderId);
      final preferredAddress =
          requestedProvider?.defaultSenderIdentity?.normalizedAddress;
      for (final option in options) {
        if (option.provider.providerId == requestedProviderId &&
            (preferredAddress == null ||
                option.identity.normalizedAddress == preferredAddress)) {
          _selectedSenderKey = option.key;
          return;
        }
      }
      for (final option in options) {
        if (option.provider.providerId == requestedProviderId) {
          _selectedSenderKey = option.key;
          return;
        }
      }
    }

    _selectedSenderKey = options.isEmpty ? null : options.first.key;
  }

  Future<void> _refreshSenderOptions() async {
    try {
      await widget.manager.refreshSenderIdentities();
    } catch (_) {
      // The provider keeps the authenticated mailbox as its fail-closed
      // fallback, so composing remains available without exposing stale aliases.
    } finally {
      if (mounted) {
        setState(() => _syncSelectedSender());
      }
    }
  }

  @override
  void dispose() {
    _toController.dispose();
    _ccController.dispose();
    _bccController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    final sender = _selectedSender;
    if (sender == null) return;

    setState(() => _isSending = true);

    try {
      // Build content with quoted text if replying
      String content = _bodyController.text;
      if (widget.quotedContent != null) {
        content = '$content${widget.quotedContent}';
      }

      final success = await widget.manager.sendEmail(
        sender.provider.providerId,
        to: _toController.text.trim(),
        subject: _subjectController.text.trim(),
        content: content,
        fromAddress: sender.identity.address,
        cc: _ccController.text.trim().isNotEmpty
            ? _ccController.text.trim()
            : null,
        bcc: _bccController.text.trim().isNotEmpty
            ? _bccController.text.trim()
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

  bool get _canSend =>
      !_isSending &&
      _selectedSender != null &&
      isValidMailRecipientList(_toController.text) &&
      isValidMailRecipientList(_ccController.text, allowEmpty: true) &&
      isValidMailRecipientList(_bccController.text, allowEmpty: true) &&
      _subjectController.text.trim().isNotEmpty &&
      _bodyController.text.trim().isNotEmpty;

  bool get _hasDraftContent =>
      _toController.text.trim().isNotEmpty ||
      _ccController.text.trim().isNotEmpty ||
      _bccController.text.trim().isNotEmpty ||
      _subjectController.text.trim().isNotEmpty ||
      _bodyController.text.trim().isNotEmpty;

  String? _validateRecipients(String? value, {bool optional = false}) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return optional ? null : 'Requerido';
    if (!isValidMailRecipientList(normalized)) {
      return 'Revisa las direcciones de correo';
    }
    return null;
  }

  Future<void> _requestClose() async {
    if (_isSending) return;
    if (!_hasDraftContent) {
      Navigator.of(context).pop();
      return;
    }

    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descartar borrador'),
        content: const Text(
          'El contenido de este correo no se guardará.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Seguir editando'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final senderOptions = _senderOptions;
    final selectedSenderKey = senderOptions.any(
      (option) => option.key == _selectedSenderKey,
    )
        ? _selectedSenderKey
        : null;

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
                color:
                    theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
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
                    onPressed: _requestClose,
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Cerrar',
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
                              key: ValueKey(
                                'mail-from-$selectedSenderKey-${senderOptions.length}',
                              ),
                              initialValue: selectedSenderKey,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              hint: const Text('Sin remitentes autorizados'),
                              items: senderOptions
                                  .map((option) => DropdownMenuItem(
                                        value: option.key,
                                        child: Row(
                                          children: [
                                            _providerIcon(
                                              option.provider.providerId,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                option.identity.menuLabel,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                              onChanged: senderOptions.isEmpty
                                  ? null
                                  : (value) => setState(
                                        () => _selectedSenderKey = value,
                                      ),
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
                                        child: const Text('CC/CCO'),
                                      )
                                    : null,
                              ),
                              keyboardType: TextInputType.emailAddress,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              validator: _validateRecipients,
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
                                keyboardType: TextInputType.emailAddress,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                validator: (value) =>
                                    _validateRecipients(value, optional: true),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            SizedBox(
                              width: 60,
                              child: Text(
                                'CCO:',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            Expanded(
                              child: TextFormField(
                                controller: _bccController,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                ),
                                keyboardType: TextInputType.emailAddress,
                                autovalidateMode:
                                    AutovalidateMode.onUserInteraction,
                                validator: (value) =>
                                    _validateRecipients(value, optional: true),
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
                              validator: (v) => v?.trim().isEmpty ?? true
                                  ? 'Requerido'
                                  : null,
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
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
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (value) => value?.trim().isEmpty ?? true
                            ? 'Escribe un mensaje'
                            : null,
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
                    onPressed: _isSending ? null : _requestClose,
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _canSend ? _send : null,
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
