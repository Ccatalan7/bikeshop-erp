import 'package:flutter/material.dart';

enum MailErrorKind {
  token,
  database,
  permissions,
  network,
  provider,
  unknown,
}

class MailErrorDiagnostic {
  final MailErrorKind kind;
  final String label;
  final String headline;
  final IconData icon;

  const MailErrorDiagnostic({
    required this.kind,
    required this.label,
    required this.headline,
    required this.icon,
  });

  factory MailErrorDiagnostic.fromMessage(String message) {
    final text = message.toLowerCase();

    if (_containsAny(text, const [
      'base de datos',
      'database',
      'sqlstate',
      'relation ',
      'schema cache',
      'postgrest',
      'email_accounts',
      'user_profiles',
      'tenant profile',
      'current user has no tenant profile',
      'duplicate key',
      'violates',
      'permission denied for table',
    ])) {
      return const MailErrorDiagnostic(
        kind: MailErrorKind.database,
        label: 'Base de datos',
        headline: 'Falló el registro/conexión guardada',
        icon: Icons.storage_outlined,
      );
    }

    if (_containsAny(text, const [
      'token',
      'oauth',
      'invalid_grant',
      'unauthorized',
      '401',
      'refresh token',
      'reconnect',
      'reconecta',
      'vuelve a conectar',
      'venció',
      'venció.',
      'revoked',
      'missing stored gmail refresh token',
    ])) {
      return const MailErrorDiagnostic(
        kind: MailErrorKind.token,
        label: 'Token/OAuth',
        headline: 'La conexión de la cuenta venció',
        icon: Icons.key_off_outlined,
      );
    }

    if (_containsAny(text, const [
      '403',
      'forbidden',
      'insufficient',
      'scope',
      'scopes',
      'permisos',
      'no autorizó',
      'not authorized',
      'access denied',
    ])) {
      return const MailErrorDiagnostic(
        kind: MailErrorKind.permissions,
        label: 'Permisos',
        headline: 'Faltan permisos para esta operación',
        icon: Icons.lock_outline,
      );
    }

    if (_containsAny(text, const [
      'timeout',
      'socket',
      'network',
      'failed host',
      'connection refused',
      'connection reset',
      'xmlhttprequest',
      'clientexception',
      '502',
      '503',
      '504',
    ])) {
      return const MailErrorDiagnostic(
        kind: MailErrorKind.network,
        label: 'Red/API',
        headline: 'La conexión falló temporalmente',
        icon: Icons.cloud_off_outlined,
      );
    }

    if (_containsAny(text, const [
      'gmail api',
      'gmail rechazó',
      'googleapis',
      'rate limit',
      'quota',
      '429',
      'bad request',
      'invalid_argument',
    ])) {
      return const MailErrorDiagnostic(
        kind: MailErrorKind.provider,
        label: 'Proveedor',
        headline: 'Gmail/Zoho rechazó la solicitud',
        icon: Icons.alternate_email_outlined,
      );
    }

    return const MailErrorDiagnostic(
      kind: MailErrorKind.unknown,
      label: 'Error',
      headline: 'No se pudo clasificar automáticamente',
      icon: Icons.bug_report_outlined,
    );
  }

  static bool _containsAny(String text, List<String> needles) {
    return needles.any(text.contains);
  }
}

class MailErrorDiagnosticBanner extends StatelessWidget {
  final String message;
  final bool compact;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const MailErrorDiagnosticBanner({
    super.key,
    required this.message,
    this.compact = true,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final diagnostic = MailErrorDiagnostic.fromMessage(message);
    final color = _colorFor(diagnostic.kind, colorScheme);
    final cleanMessage = _cleanMessage(message);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(diagnostic.icon, size: compact ? 16 : 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _IssuePill(label: diagnostic.label, color: color),
                    Text(
                      diagnostic.headline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  cleanMessage,
                  maxLines: compact ? 3 : 6,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon ?? Icons.refresh, size: 16),
                    label: Text(actionLabel!),
                    style: TextButton.styleFrom(
                      foregroundColor: color,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _colorFor(MailErrorKind kind, ColorScheme colorScheme) {
    return switch (kind) {
      MailErrorKind.token => Colors.deepOrange.shade700,
      MailErrorKind.database => Colors.purple.shade700,
      MailErrorKind.permissions => Colors.red.shade700,
      MailErrorKind.network => Colors.blueGrey.shade700,
      MailErrorKind.provider => Colors.amber.shade900,
      MailErrorKind.unknown => colorScheme.error,
    };
  }

  String _cleanMessage(String value) {
    return value
        .replaceFirst(RegExp(r'^Exception:\s*'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _IssuePill extends StatelessWidget {
  final String label;
  final Color color;

  const _IssuePill({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
