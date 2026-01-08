import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/zoho_email.dart';
import '../services/zoho_mail_service.dart';
import 'email_compose_dialog.dart';

/// Email detail panel - shows full email content
class EmailDetailPanel extends StatelessWidget {
  final ZohoEmail email;
  final ZohoMailService mailService;
  final VoidCallback onClose;
  final VoidCallback onReply;

  const EmailDetailPanel({
    super.key,
    required this.email,
    required this.mailService,
    required this.onClose,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with actions
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Volver',
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _reply(context),
                icon: const Icon(Icons.reply),
                tooltip: 'Responder',
              ),
              IconButton(
                onPressed: () => _replyAll(context),
                icon: const Icon(Icons.reply_all),
                tooltip: 'Responder a todos',
              ),
              IconButton(
                onPressed: () => _forward(context),
                icon: const Icon(Icons.forward),
                tooltip: 'Reenviar',
              ),
              IconButton(
                onPressed: () => _delete(context),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Eliminar',
              ),
            ],
          ),
        ),
        // Email content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Subject
                Text(
                  email.subject,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                // Sender info
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text(
                        email.senderName.isNotEmpty
                            ? email.senderName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            email.senderName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            email.senderEmail,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      DateFormat('d MMM yyyy, HH:mm')
                          .format(email.receivedTime),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // To
                Text(
                  'Para: ${email.toAddress}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (email.ccAddress != null && email.ccAddress!.isNotEmpty)
                  Text(
                    'CC: ${email.ccAddress}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const Divider(height: 32),
                // Body
                if (email.content != null)
                  SelectableText(
                    _stripHtml(email.content!),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                    ),
                  )
                else if (email.summary != null)
                  Text(
                    email.summary!,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.6,
                    ),
                  )
                else
                  Text(
                    'Cargando contenido...',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _reply(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => EmailComposeDialog(
        mailService: mailService,
        replyTo: email,
        onSent: onReply,
      ),
    );
  }

  void _replyAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => EmailComposeDialog(
        mailService: mailService,
        replyTo: email,
        replyAll: true,
        onSent: onReply,
      ),
    );
  }

  void _forward(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => EmailComposeDialog(
        mailService: mailService,
        forward: email,
        onSent: onReply,
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar correo'),
        content:
            const Text('¿Estás seguro de que quieres eliminar este correo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await mailService.moveToTrash(email.messageId);
      onClose();
    }
  }

  /// Simple HTML stripper (for display purposes)
  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<p[^>]*>'), '\n')
        .replaceAll(RegExp(r'</p>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'\n\s*\n'), '\n\n')
        .trim();
  }
}
