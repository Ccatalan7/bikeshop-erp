import 'package:flutter/material.dart';

import '../services/website_seo_operations_service.dart';
import 'seo_readiness_badge.dart';

/// One Google operation offered by the SEO center.
enum SeoGoogleOperation { connect, submitSitemap, refreshMerchant }

/// The last locally observed outcome of one operation.
///
/// It is deliberately separate from the projection's Search Console evidence:
/// "yo lancé esta acción y Google respondió X" is not the same fact as "Google
/// informó que el sitemap fue descargado el día Y". Merging them is how a
/// submit turns into a fake "indexado".
@immutable
class SeoGoogleOperationOutcome {
  const SeoGoogleOperationOutcome({
    required this.succeeded,
    required this.observedAt,
    required this.message,
  });

  final bool succeeded;
  final DateTime observedAt;
  final String message;
}

/// Site-wide Google operations, rendered as operations and never as evidence.
///
/// Contract this widget exists to hold:
///
/// * an action the backend does not authorize is **disabled** and states its
///   reason; it is never offered and then silently failed;
/// * a completed action reports what Google accepted, with its own timestamp,
///   and never claims crawling or indexing; and
/// * no property id, account id, domain, feed URL or secret name appears here.
///   Every target is resolved server-side from the tenant's `store_url`.
class SeoGoogleOperationsPanel extends StatelessWidget {
  const SeoGoogleOperationsPanel({
    super.key,
    required this.status,
    required this.isBusy,
    required this.runningOperation,
    required this.outcomes,
    required this.onRun,
    this.merchantSupported = true,
  });

  /// `null` while the first connection read is still in flight.
  final WebsiteSeoConnectionStatus? status;

  final bool isBusy;
  final SeoGoogleOperation? runningOperation;
  final Map<SeoGoogleOperation, SeoGoogleOperationOutcome> outcomes;
  final void Function(SeoGoogleOperation operation) onRun;

  /// Merchant is an independent integration; the backend answers whether it is
  /// configured for this tenant. Hiding the action entirely would be worse
  /// than showing it unavailable with a reason.
  final bool merchantSupported;

  bool get _statusUnavailable => status != null && !status!.isAvailable;

  bool get _connected => status?.connected == true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = status;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Operaciones con Google',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (current != null)
                SeoReadinessBadge(
                  state: _connectionBadge(current),
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Acciones sobre el sitio completo. Se ejecutan en el servidor con '
            'los datos de esta tienda; enviar no equivale a rastrear ni a '
            'indexar.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (current == null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'Leyendo el estado de conexión…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ] else ...[
            if (current.accountEmail.isNotEmpty ||
                current.siteUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ConnectionFacts(status: current),
            ],
            if (_statusUnavailable) ...[
              const SizedBox(height: 10),
              _ReasonNotice(
                icon: Icons.info_outline_rounded,
                message: current.unavailableReason.isEmpty
                    ? 'El estado de conexión no está disponible.'
                    : current.unavailableReason,
              ),
            ],
            const SizedBox(height: 14),
            _Actions(
              operations: _operations(current),
              isBusy: isBusy,
              runningOperation: runningOperation,
              onRun: onRun,
            ),
            for (final entry in _orderedOutcomes) ...[
              const SizedBox(height: 10),
              _OutcomeLine(
                label: _operationLabel(entry.key),
                outcome: entry.value,
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<MapEntry<SeoGoogleOperation, SeoGoogleOperationOutcome>>
      get _orderedOutcomes => [
            for (final operation in SeoGoogleOperation.values)
              if (outcomes[operation] != null)
                MapEntry(operation, outcomes[operation]!),
          ];

  /// Availability is decided only by what the backend reported. The client
  /// never guesses that an action would probably work.
  List<_OperationSpec> _operations(WebsiteSeoConnectionStatus current) {
    final statusReason = current.unavailableReason;
    final connectBlocked = _statusUnavailable &&
        current.blocker == WebsiteSeoOperationBlocker.notAuthorized;

    return [
      _OperationSpec(
        operation: SeoGoogleOperation.connect,
        label: _connected
            ? 'Reconectar Search Console'
            : 'Conectar Search Console',
        icon: _connected ? Icons.link_rounded : Icons.link_off_rounded,
        emphasised: !_connected,
        unavailableReason: connectBlocked ? statusReason : null,
      ),
      _OperationSpec(
        operation: SeoGoogleOperation.submitSitemap,
        label: 'Enviar sitemap',
        icon: Icons.upload_file_outlined,
        // Only a *known* disconnection blocks the submit. When the status
        // itself could not be read we do not know, and inventing "no estás
        // conectado" would be the same class of lie as inventing a success:
        // let the operation run and report the server's own reason.
        unavailableReason: connectBlocked
            ? statusReason
            : (current.isAvailable && !current.connected)
                ? WebsiteSeoOperationBlocker.notConnected.explanation
                : null,
      ),
      if (merchantSupported)
        _OperationSpec(
          operation: SeoGoogleOperation.refreshMerchant,
          label: 'Actualizar Merchant',
          icon: Icons.sync_outlined,
          // Merchant uses its own server-side integration, so a missing
          // Search Console grant does not block it. The backend answers.
          unavailableReason: connectBlocked ? statusReason : null,
        ),
    ];
  }

  SeoBadgeState _connectionBadge(WebsiteSeoConnectionStatus current) {
    if (!current.isAvailable) {
      return const SeoBadgeState(
        label: 'Sin consultar',
        tone: SeoBadgeTone.unknown,
      );
    }
    return current.connected
        ? const SeoBadgeState(label: 'Conectado', tone: SeoBadgeTone.confirmed)
        : const SeoBadgeState(
            label: 'No conectado', tone: SeoBadgeTone.neutral);
  }

  static String _operationLabel(SeoGoogleOperation operation) =>
      switch (operation) {
        SeoGoogleOperation.connect => 'Conexión',
        SeoGoogleOperation.submitSitemap => 'Envío de sitemap',
        SeoGoogleOperation.refreshMerchant => 'Actualización Merchant',
      };
}

@immutable
class _OperationSpec {
  const _OperationSpec({
    required this.operation,
    required this.label,
    required this.icon,
    this.emphasised = false,
    this.unavailableReason,
  });

  final SeoGoogleOperation operation;
  final String label;
  final IconData icon;
  final bool emphasised;

  /// Non-null disables the action and is shown verbatim beside it.
  final String? unavailableReason;
}

/// Wraps at any width, so a phone never gets a horizontally scrolling row.
class _Actions extends StatelessWidget {
  const _Actions({
    required this.operations,
    required this.isBusy,
    required this.runningOperation,
    required this.onRun,
  });

  final List<_OperationSpec> operations;
  final bool isBusy;
  final SeoGoogleOperation? runningOperation;
  final void Function(SeoGoogleOperation operation) onRun;

  @override
  Widget build(BuildContext context) {
    final unavailable = [
      for (final spec in operations)
        if (spec.unavailableReason != null) spec,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final spec in operations)
              _OperationButton(
                spec: spec,
                isRunning: runningOperation == spec.operation,
                onPressed: spec.unavailableReason != null || isBusy
                    ? null
                    : () => onRun(spec.operation),
              ),
          ],
        ),
        for (final spec in unavailable) ...[
          const SizedBox(height: 8),
          _ReasonNotice(
            icon: Icons.block_outlined,
            message: '${spec.label}: no disponible. '
                '${spec.unavailableReason}',
          ),
        ],
      ],
    );
  }
}

class _OperationButton extends StatelessWidget {
  const _OperationButton({
    required this.spec,
    required this.isRunning,
    required this.onPressed,
  });

  final _OperationSpec spec;
  final bool isRunning;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = isRunning
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(spec.icon, size: 18);
    final label = Text(spec.label);

    // Semantics carry the reason so the disabled state is not mouse-only
    // knowledge; the visible notice below repeats it for everyone.
    return Semantics(
      enabled: onPressed != null,
      hint: spec.unavailableReason,
      child: spec.emphasised
          ? FilledButton.icon(onPressed: onPressed, icon: icon, label: label)
          : OutlinedButton.icon(onPressed: onPressed, icon: icon, label: label),
    );
  }
}

class _ConnectionFacts extends StatelessWidget {
  const _ConnectionFacts({required this.status});

  final WebsiteSeoConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = <(String, String)>[
      if (status.siteUrl.isNotEmpty) ('Propiedad', status.siteUrl),
      if (status.accountEmail.isNotEmpty) ('Cuenta', status.accountEmail),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final fact in facts)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${fact.$1}: ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  TextSpan(
                    text: fact.$2,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ReasonNotice extends StatelessWidget {
  const _ReasonNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

class _OutcomeLine extends StatelessWidget {
  const _OutcomeLine({required this.label, required this.outcome});

  final String label;
  final SeoGoogleOperationOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        outcome.succeeded ? theme.colorScheme.primary : theme.colorScheme.error;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          outcome.succeeded
              ? Icons.check_circle_outline_rounded
              : Icons.error_outline_rounded,
          size: 15,
          color: accent,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label · ${formatSeoTimestamp(outcome.observedAt)}\n',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextSpan(
                  text: outcome.message,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared date wording so an operation timestamp reads exactly like the
/// evidence timestamps beside it.
String formatSeoTimestamp(DateTime value) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day ${months[local.month - 1]} ${local.year} · $hour:$minute';
}
