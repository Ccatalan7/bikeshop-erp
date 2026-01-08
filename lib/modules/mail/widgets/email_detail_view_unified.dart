import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:intl/intl.dart';
import '../providers/email_provider.dart';

/// Email detail view for unified inbox
class EmailDetailViewUnified extends StatelessWidget {
  final Email email;
  final EmailProvider? provider;
  final bool isLoading;
  final String? error;
  final VoidCallback? onClose;
  final VoidCallback onRetry;
  final VoidCallback? onReply;
  final VoidCallback? onReplyAll;
  final VoidCallback? onDelete;

  const EmailDetailViewUnified({
    super.key,
    required this.email,
    this.provider,
    required this.isLoading,
    this.error,
    this.onClose,
    required this.onRetry,
    this.onReply,
    this.onReplyAll,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show error state
    if (error != null && !isLoading) {
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
              error!.contains('404')
                  ? 'No se pudo encontrar el contenido del mensaje.'
                  : error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    // Loading content
    if (isLoading && email.content == null) {
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
              title: _ProviderBadge(providerId: email.providerId),
              actions: _buildActions(context),
            )
          : null,
      body: Column(
        children: [
          // Desktop toolbar
          if (onClose == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _ProviderBadge(providerId: email.providerId),
                  const Spacer(),
                  ..._buildActions(context),
                ],
              ),
            ),
          if (onClose == null) const Divider(height: 1),

          // Content
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: _getProviderColor(email.providerId),
                        child: Text(
                          email.senderName.isNotEmpty
                              ? email.senderName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              fontSize: 20, color: Colors.white),
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
                                    email.senderName,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '<${email.senderEmail}>',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'para ${email.toAddress}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        DateFormat('d MMM yyyy, HH:mm', 'es')
                            .format(email.receivedTime),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Email body
                  SelectableRegion(
                    focusNode: FocusNode(),
                    selectionControls: materialTextSelectionControls,
                    child: HtmlWidget(
                      email.content ?? email.summary ?? 'Sin contenido.',
                      textStyle: theme.textTheme.bodyLarge,
                      onTapUrl: (url) => true,
                    ),
                  ),

                  if (email.hasAttachment) ...[
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
                            'Adjuntos disponibles en la versión web.',
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

          // Reply actions bar at bottom
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border:
                  Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReply,
                    icon: const Icon(Icons.reply, size: 18),
                    label: const Text('Responder'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReplyAll,
                    icon: const Icon(Icons.reply_all, size: 18),
                    label: const Text('Responder a todos'),
                  ),
                ),
              ],
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
      const SizedBox(width: 4),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        tooltip: 'Más opciones',
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'reply_all',
            child: Row(
              children: [
                Icon(Icons.reply_all, size: 18),
                SizedBox(width: 8),
                Text('Responder a todos'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: Colors.red),
                SizedBox(width: 8),
                Text('Eliminar', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
        onSelected: (value) {
          if (value == 'reply_all') {
            onReplyAll?.call();
          } else if (value == 'delete') {
            _confirmDelete(context);
          }
        },
      ),
    ];
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar correo'),
        content:
            const Text('¿Estás seguro de que quieres eliminar este correo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDelete?.call();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Color _getProviderColor(String providerId) {
    switch (providerId) {
      case 'gmail':
        return Colors.red;
      case 'zoho':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }
}

class _ProviderBadge extends StatelessWidget {
  final String providerId;

  const _ProviderBadge({required this.providerId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _getIcon(),
          const SizedBox(width: 4),
          Text(
            _getLabel(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: _getColor(),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getColor() {
    switch (providerId) {
      case 'gmail':
        return Colors.red;
      case 'zoho':
        return const Color(0xFF2B579A); // Zoho blue
      default:
        return Colors.blue;
    }
  }

  Widget _getIcon() {
    switch (providerId) {
      case 'gmail':
        return Image.asset(
          'assets/icons/gmail_logo.webp',
          width: 16,
          height: 16,
        );
      case 'zoho':
        return Image.asset(
          'assets/icons/zoho_logo.png',
          width: 16,
          height: 16,
        );
      default:
        return const Icon(Icons.email_outlined, size: 14);
    }
  }

  String _getLabel() {
    switch (providerId) {
      case 'gmail':
        return 'Gmail';
      case 'zoho':
        return 'Zoho';
      default:
        return 'Email';
    }
  }
}
