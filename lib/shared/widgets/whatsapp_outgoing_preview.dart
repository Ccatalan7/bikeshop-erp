import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';

/// Cómo se verá el mensaje en el chat del cliente, dibujado con la misma
/// gramática que usa la ventana de conversación: burbuja propia sobre el rol
/// `selectionContainer`, cola abajo a la derecha y hora al pie. Verlo como un
/// texto plano en un diálogo del sistema no dejaba juzgar lo único que importa
/// acá, que es cómo le va a llegar.
class WhatsAppOutgoingPreview extends StatelessWidget {
  const WhatsAppOutgoingPreview({
    super.key,
    required this.text,
    required this.onCancel,
    required this.onSend,
    this.disabledReason,
  });

  final String text;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  /// Por qué no se puede enviar todavía. Revisar el texto siempre se puede:
  /// una plantilla en revisión igual hay que poder leerla.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = theme.extension<VinabikeThemeRoles>();
    final bubbleColor =
        roles?.selectionContainer ?? scheme.primaryContainer;
    final onBubble =
        roles?.onSelectionContainer ?? scheme.onPrimaryContainer;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Así le llegará',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: roles?.shadow ??
                        scheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: onBubble,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // La hora es la de envío: se muestra para que la burbuja
                    // se lea como un mensaje y no como una cita.
                    TimeOfDay.fromDateTime(DateTime.now()).format(context),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: onBubble.withValues(alpha: 0.6),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (disabledReason != null) ...[
            const SizedBox(height: 8),
            Text(
              disabledReason!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                key: const Key('ai-card-option-confirm'),
                onPressed: disabledReason == null ? onSend : null,
                icon: const Icon(Icons.send_rounded, size: 16),
                label: const Text('Enviar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
