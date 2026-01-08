import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import '../models/zoho_email.dart';
import '../services/zoho_mail_service.dart';

class EmailDetailView extends StatelessWidget {
  final ZohoEmail? email;
  final ZohoMailService mailService;
  final VoidCallback? onClose; // For mobile
  final VoidCallback onReply;

  const EmailDetailView({
    super.key,
    required this.email,
    required this.mailService,
    this.onClose,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (email == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mail_outline,
                size: 64, color: colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'Selecciona un correo para leerlo',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Check for error during content fetch
    if (mailService.error != null && !mailService.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('Error al cargar el contenido',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              mailService.error!.contains('404')
                  ? 'No se pudo encontrar el contenido del mensaje.\nTal vez fue eliminado o movido.'
                  : mailService.error.toString(),
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => mailService.getEmailContent(email!),
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (mailService.isLoading && email!.content == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: onClose != null
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: onClose,
              ),
              actions: _buildActions(context),
            )
          : null,
      body: Column(
        children: [
          // Desktop Toolbar (if not mobile)
          if (onClose == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: _buildActions(context),
              ),
            ),
          if (onClose == null) const Divider(height: 1),

          // Content Scroll
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Subject
                  Text(
                    email!.subject,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Sender info row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: colorScheme.primaryContainer,
                        child: Text(
                          email!.senderName.isNotEmpty
                              ? email!.senderName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                              fontSize: 20,
                              color: colorScheme.onPrimaryContainer),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    email!.senderName,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '<${email!.senderEmail}>',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'para ${email!.toAddress}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        DateFormat('d MMM yyyy, HH:mm')
                            .format(email!.receivedTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Email Body
                  SelectableRegion(
                    focusNode: FocusNode(),
                    selectionControls: materialTextSelectionControls,
                    child: HtmlWidget(
                      email!.content ?? email!.summary ?? 'Sin contenido.',
                      textStyle: theme.textTheme.bodyLarge,
                      onTapUrl: (url) {
                        // Open links?
                        return true;
                      },
                    ),
                  ),

                  if (email!.hasAttachment) ...[
                    const SizedBox(height: 32),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        children: [
                          Icon(Icons.attach_file,
                              color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(
                            'Adjuntos disponibles en la versión web de Zoho.',
                            style:
                                TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.reply),
        tooltip: 'Responder',
        onPressed: onReply,
      ),
      const SizedBox(width: 8),
      IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Eliminar',
        onPressed: () {}, // TODO: Implement delete
      ),
      const SizedBox(width: 8),
      IconButton(
        icon: const Icon(Icons.mark_email_unread_outlined),
        tooltip: 'Marcar como no leído',
        onPressed: () {}, // TODO: Implement unread
      ),
    ];
  }
}
