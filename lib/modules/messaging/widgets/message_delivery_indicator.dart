import 'package:flutter/material.dart';

import '../models/message_delivery_state.dart';

/// Shared WhatsApp-style receipt used by both the timeline and inbox preview.
class MessageDeliveryIndicator extends StatelessWidget {
  const MessageDeliveryIndicator({
    super.key,
    required this.state,
    this.size = 14,
  });

  final MessageDeliveryState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (icon, color, label) = switch (state.stage) {
      MessageDeliveryStage.pending => (
          Icons.access_time_rounded,
          colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          'Enviando',
        ),
      MessageDeliveryStage.outcomeUnknown => (
          Icons.help_outline_rounded,
          colorScheme.tertiary,
          state.failureMessage ??
              'Resultado incierto: verifica antes de reenviar',
        ),
      MessageDeliveryStage.accepted => (
          Icons.done_rounded,
          colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          'Aceptado por el canal de WhatsApp',
        ),
      MessageDeliveryStage.sent => (
          Icons.done_rounded,
          colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          'Enviado a WhatsApp',
        ),
      MessageDeliveryStage.delivered => (
          Icons.done_all_rounded,
          colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          'Entregado al teléfono',
        ),
      MessageDeliveryStage.read => (
          Icons.done_all_rounded,
          const Color(0xFF0B84D8),
          'Leído, confirmado por WhatsApp',
        ),
      MessageDeliveryStage.failed => (
          Icons.error_outline_rounded,
          colorScheme.error,
          state.failureMessage ?? 'No se pudo entregar',
        ),
      MessageDeliveryStage.none => (
          Icons.done_rounded,
          Colors.transparent,
          '',
        ),
    };

    if (!state.isVisible) return const SizedBox.shrink();

    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 450),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 170),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.86, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: Icon(
          icon,
          key: ValueKey(state.stage),
          size: size,
          color: color,
        ),
      ),
    );
  }
}
