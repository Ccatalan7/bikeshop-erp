import 'package:flutter/material.dart';

import '../models/storefront_publication_status.dart';
import '../models/website_seo_center_models.dart';
import 'seo_google_operations_panel.dart' show formatSeoTimestamp;

/// The single presentational state of the Editor → build → deploy conduit.
///
/// One resolver owns the precedence so the band, the scope-rail attention dot
/// and the tests can never disagree about what the operator is being told.
enum StorefrontPublicationBandKind {
  loading,
  readFailed,
  unsupported,
  notConfigured,
  noEditorialRevision,
  working,
  failure,
  stale,
  publishedVerified,
  inconclusive,
  idle,
}

/// Presentation-only projection of [StorefrontPublicationStatus].
///
/// It adds no facts of its own: every headline is derived from ledger fields
/// plus, for the one verified state, the live release manifest. The band never
/// publishes, never edits metadata, and never promises crawling or indexing.
@immutable
class StorefrontPublicationPresentation {
  const StorefrontPublicationPresentation._({
    required this.kind,
    required this.headline,
    this.supporting = '',
    this.facts = const <String>[],
    required this.needsAttention,
    this.retryAllowed = false,
    this.retryBlockedReason,
    this.runUrl,
    this.showAutomationDisabledChip = false,
    this.refreshActionLabel,
  });

  /// The mandated presentational precedence:
  ///
  /// availability problems → no editorial revision → working (including an
  /// ambiguous dispatch, which outranks any older failure) → current failure →
  /// stale/pending changes → exact live-verified success → inconclusive.
  factory StorefrontPublicationPresentation.resolve({
    required StorefrontPublicationStatus? status,
    WebsiteSeoReleaseArtifactEvidence? release,
  }) {
    if (status == null) {
      return const StorefrontPublicationPresentation._(
        kind: StorefrontPublicationBandKind.loading,
        headline: 'Consultando la publicación de la tienda…',
        needsAttention: false,
      );
    }
    if (status.readFailed) {
      return const StorefrontPublicationPresentation._(
        kind: StorefrontPublicationBandKind.readFailed,
        headline: 'No se pudo consultar el estado de publicación.',
        supporting: 'El resto del centro SEO sigue disponible.',
        needsAttention: true,
        refreshActionLabel: 'Actualizar estado',
      );
    }
    if (!status.supported) {
      return const StorefrontPublicationPresentation._(
        kind: StorefrontPublicationBandKind.unsupported,
        headline: 'La publicación automática no está soportada.',
        needsAttention: false,
      );
    }
    if (!status.configured) {
      return const StorefrontPublicationPresentation._(
        kind: StorefrontPublicationBandKind.notConfigured,
        headline: 'Publicación automática no disponible en esta tienda.',
        needsAttention: false,
      );
    }

    final disabledChip = !status.dispatchEnabled;

    if (status.desiredRevision == 0) {
      return StorefrontPublicationPresentation._(
        kind: StorefrontPublicationBandKind.noEditorialRevision,
        headline: 'Sin revisión editorial que publicar.',
        supporting:
            'Los cambios del editor crean la primera revisión publicable.',
        needsAttention: false,
        showAutomationDisabledChip: disabledChip,
      );
    }

    if (status.isWorking) {
      final active = status.active;
      final workingState =
          active?.state ?? status.queue?.state ?? status.requestState;
      final revision = active?.requestedRevision ??
          status.queue?.requestedRevision ??
          status.desiredRevision;
      final (headline, supporting) = switch (workingState) {
        StorefrontPublicationRequestState.queued => (
            'Cambios en cola · rev. $revision',
            _queueSupporting(status.queue),
          ),
        StorefrontPublicationRequestState.dispatching => (
            'Despachando la publicación…',
            '',
          ),
        StorefrontPublicationRequestState.dispatched => (
            'Despacho confirmado · esperando la ejecución',
            '',
          ),
        StorefrontPublicationRequestState.dispatchUnknown => (
            'Despacho sin confirmación de GitHub',
            'La reconciliación automática resolverá este estado. No se '
                'reintenta a ciegas.',
          ),
        StorefrontPublicationRequestState.sealed => (
            'Build sellado · verificando los orígenes publicados',
            '',
          ),
        _ => (
            'Publicando · rev. $revision en ejecución',
            '',
          ),
      };
      return StorefrontPublicationPresentation._(
        kind: StorefrontPublicationBandKind.working,
        headline: headline,
        supporting: supporting,
        facts: [
          if (active != null && active.attemptNo > 0)
            'Intento ${active.attemptNo}',
          if (active?.startedAt != null)
            'Inició ${formatSeoTimestamp(active!.startedAt!)}',
          if (active?.sealedAt != null)
            'Sellado ${formatSeoTimestamp(active!.sealedAt!)}',
        ],
        needsAttention: false,
        runUrl: _safeGithubRunUrl(active?.githubRunUrl),
        showAutomationDisabledChip: disabledChip,
      );
    }

    if (status.hasFailed) {
      final failure = status.latestFailure;
      final isDead = (failure?.state ?? status.requestState) ==
          StorefrontPublicationRequestState.deadLetter;
      final retryAllowed = status.canRetry &&
          !status.isWorking &&
          status.requestState !=
              StorefrontPublicationRequestState.dispatchUnknown;
      return StorefrontPublicationPresentation._(
        kind: StorefrontPublicationBandKind.failure,
        headline: isDead
            ? 'Publicación detenida tras varios intentos'
            : 'La publicación falló',
        supporting: isDead
            ? 'El sistema dejó de reintentar; requiere una decisión.'
            : '',
        facts: [
          if (failure != null && failure.requestedRevision > 0)
            'Revisión ${failure.requestedRevision}',
          if (failure != null && failure.failureStage.isNotEmpty)
            'Etapa: ${failure.failureStage}',
          if (failure != null && failure.errorClass.isNotEmpty)
            'Clase: ${failure.errorClass}',
          if (failure?.finishedAt != null)
            'Terminó ${formatSeoTimestamp(failure!.finishedAt!)}',
        ],
        needsAttention: true,
        retryAllowed: retryAllowed,
        retryBlockedReason: retryAllowed
            ? null
            : 'El reintento no está disponible en este estado.',
        showAutomationDisabledChip: disabledChip,
      );
    }

    final liveVerified =
        release != null && status.provesCurrentLiveRelease(release);

    if (status.hasUnpublishedChanges) {
      final lastLiveStillVerified = release != null &&
          status.lastSuccess?.matchesLiveRelease(release) == true;
      return StorefrontPublicationPresentation._(
        kind: StorefrontPublicationBandKind.stale,
        headline:
            'Cambios sin publicar · rev. ${status.desiredRevision} pendiente',
        supporting: disabledChip
            ? 'La automatización está desactivada; los cambios esperan.'
            : '',
        facts: [
          if (status.lastOwnerChangeAt != null)
            'Último cambio ${formatSeoTimestamp(status.lastOwnerChangeAt!)}',
          if (lastLiveStillVerified)
            'El sitio muestra la rev. ${status.lastPublishedRevision} '
                'verificada'
          else if (status.hasTrackedPublication)
            'Última publicación registrada: rev. '
                '${status.lastPublishedRevision}',
        ],
        needsAttention: true,
        showAutomationDisabledChip: disabledChip,
      );
    }

    if (liveVerified) {
      final success = status.lastSuccess!;
      return StorefrontPublicationPresentation._(
        kind: StorefrontPublicationBandKind.publishedVerified,
        headline: 'Publicado y verificado · rev. ${success.publishedRevision}',
        supporting:
            'El manifiesto en vivo coincide exactamente con esta publicación. '
            'Google decide por su cuenta si rastrea o indexa.',
        facts: [
          if (success.completedAt != null)
            'Completado ${formatSeoTimestamp(success.completedAt!)}',
          if (success.primaryVerifiedAt != null &&
              success.customVerifiedAt != null)
            'Ambos orígenes verificados',
        ],
        needsAttention: false,
        runUrl: _safeGithubRunUrl(success.githubRunUrl),
        showAutomationDisabledChip: disabledChip,
      );
    }

    if (status.ledgerClaimsCurrentRevision) {
      // The ledger reports success but the live manifest is absent or does not
      // match. Necessary-but-not-sufficient: this is inconclusive evidence and
      // must never be presented as published.
      return StorefrontPublicationPresentation._(
        kind: StorefrontPublicationBandKind.inconclusive,
        headline: 'Éxito registrado · sin verificación en vivo',
        supporting:
            'El manifiesto publicado no coincide o no está disponible; la '
            'publicación no se afirma hasta verificarla.',
        facts: [
          'Rev. ${status.lastPublishedRevision} según el registro',
        ],
        needsAttention: true,
        showAutomationDisabledChip: disabledChip,
      );
    }

    return StorefrontPublicationPresentation._(
      kind: StorefrontPublicationBandKind.idle,
      headline: 'Sin publicaciones registradas.',
      needsAttention: false,
      showAutomationDisabledChip: disabledChip,
    );
  }

  final StorefrontPublicationBandKind kind;
  final String headline;
  final String supporting;
  final List<String> facts;

  /// Drives the Sitio scope-rail attention dot. Same resolver, no second
  /// precedence anywhere.
  final bool needsAttention;

  final bool retryAllowed;
  final String? retryBlockedReason;
  final Uri? runUrl;
  final bool showAutomationDisabledChip;

  /// Non-null only when the state itself is a failed read, whose remedy is a
  /// fresh status read rather than a publication retry.
  final String? refreshActionLabel;

  static String _queueSupporting(StorefrontPublicationQueueInfo? queue) {
    if (queue == null) return '';
    final parts = <String>[
      if (queue.coalescedCount > 1) '${queue.coalescedCount} cambios agrupados',
      if (queue.availableAt != null)
        'Despacho desde ${formatSeoTimestamp(queue.availableAt!)}',
    ];
    return parts.join(' · ');
  }

  /// Accepts only the exact public GitHub Actions run shape. A missing,
  /// malformed or merely GitHub-hosted URL renders no link at all — the band
  /// never fabricates a run destination from partial evidence.
  static Uri? _safeGithubRunUrl(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.isScheme('https')) return null;
    final host = uri.host.toLowerCase();
    if (host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final segments = uri.pathSegments;
    if (segments.length != 5 ||
        segments[0].isEmpty ||
        segments[1].isEmpty ||
        segments[2] != 'actions' ||
        segments[3] != 'runs' ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(segments[4])) {
      return null;
    }
    return uri;
  }
}

/// Editor → build → deploy stage band for the SEO center's `Sitio` scope.
///
/// Operational state only: it is deliberately not a fourth evidence plane, it
/// exposes no route-level publish action, and it edits nothing. It renders
/// once, before the Google operations panel, as its sibling.
class StorefrontPublicationBand extends StatefulWidget {
  const StorefrontPublicationBand({
    super.key,
    required this.status,
    required this.release,
    required this.isBusy,
    required this.onRetry,
    required this.onRefreshStatus,
    this.notice,
    this.onOpenRun,
  });

  final StorefrontPublicationStatus? status;
  final WebsiteSeoReleaseArtifactEvidence? release;

  /// Disables actions while a retry or refresh round is in flight.
  final bool isBusy;

  final VoidCallback onRetry;
  final VoidCallback onRefreshStatus;

  /// Transient outcome of the last operator action (e.g. a refused retry),
  /// already humanized by the service. Never a raw server error.
  final String? notice;

  /// Injection seam for opening the run URL; production launches externally.
  final Future<void> Function(Uri url)? onOpenRun;

  @override
  State<StorefrontPublicationBand> createState() =>
      _StorefrontPublicationBandState();
}

class _StorefrontPublicationBandState extends State<StorefrontPublicationBand> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final presentation = StorefrontPublicationPresentation.resolve(
      status: widget.status,
      release: widget.release,
    );
    final style = _bandStyle(theme, presentation.kind);
    final hasDetails = presentation.facts.isNotEmpty;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.publish_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Publicación de la tienda',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (presentation.showAutomationDisabledChip)
                _StateChip(
                  label: 'Automatización desactivada',
                  glyph: Icons.pause_circle_outline_rounded,
                  background: theme.colorScheme.surfaceContainerHighest,
                  foreground: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 10),
          // The live region announces state changes for screen readers, per
          // the compact-surface accessibility rules.
          Semantics(
            container: true,
            liveRegion: true,
            label: 'Estado de publicación: ${presentation.headline}',
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stacked = constraints.maxWidth < 600;
                final chip = _StateChip(
                  label: presentation.headline,
                  glyph: style.glyph,
                  background: style.background,
                  foreground: style.foreground,
                );
                final actions = _buildActions(theme, presentation);

                if (stacked) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      chip,
                      if (presentation.supporting.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _supportingText(theme, presentation.supporting),
                      ],
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(spacing: 8, runSpacing: 8, children: actions),
                      ],
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: chip),
                        if (actions.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Wrap(spacing: 8, runSpacing: 8, children: actions),
                        ],
                      ],
                    ),
                    if (presentation.supporting.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _supportingText(theme, presentation.supporting),
                    ],
                  ],
                );
              },
            ),
          ),
          if (hasDetails) ...[
            const SizedBox(height: 6),
            _DisclosureRow(
              expanded: _expanded,
              onToggle: () => setState(() => _expanded = !_expanded),
            ),
            if (_expanded) ...[
              const SizedBox(height: 4),
              for (final fact in presentation.facts)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    fact,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
          ],
          if (widget.notice?.trim().isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                widget.notice!.trim(),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildActions(
    ThemeData theme,
    StorefrontPublicationPresentation presentation,
  ) {
    // 48 px targets, deliberately above the admin-shell 40 px default.
    final actionStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
    );
    return [
      if (presentation.refreshActionLabel != null)
        OutlinedButton.icon(
          style: actionStyle,
          onPressed: widget.isBusy ? null : widget.onRefreshStatus,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text(presentation.refreshActionLabel!),
        ),
      if (presentation.retryAllowed)
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: widget.isBusy ? null : widget.onRetry,
          icon: const Icon(Icons.replay_rounded, size: 18),
          label: const Text('Reintentar publicación'),
        ),
      if (presentation.runUrl != null && widget.onOpenRun != null)
        OutlinedButton.icon(
          style: actionStyle,
          onPressed: widget.isBusy
              ? null
              : () => widget.onOpenRun!(presentation.runUrl!),
          icon: const Icon(Icons.open_in_new_rounded, size: 18),
          label: const Text('Ver run'),
        ),
    ];
  }

  Widget _supportingText(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.35,
      ),
    );
  }
}

@immutable
class _BandStyle {
  const _BandStyle({
    required this.background,
    required this.foreground,
    required this.glyph,
  });

  final Color background;
  final Color foreground;
  final IconData glyph;
}

_BandStyle _bandStyle(ThemeData theme, StorefrontPublicationBandKind kind) {
  final scheme = theme.colorScheme;
  return switch (kind) {
    StorefrontPublicationBandKind.publishedVerified => _BandStyle(
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
        glyph: Icons.verified_outlined,
      ),
    StorefrontPublicationBandKind.working ||
    StorefrontPublicationBandKind.loading =>
      _BandStyle(
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
        glyph: Icons.autorenew_rounded,
      ),
    StorefrontPublicationBandKind.failure => _BandStyle(
        background: scheme.errorContainer,
        foreground: scheme.onErrorContainer,
        glyph: Icons.error_outline_rounded,
      ),
    StorefrontPublicationBandKind.stale ||
    StorefrontPublicationBandKind.inconclusive ||
    StorefrontPublicationBandKind.readFailed =>
      _BandStyle(
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        glyph: Icons.warning_amber_rounded,
      ),
    _ => _BandStyle(
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
        glyph: Icons.remove_rounded,
      ),
  };
}

/// State chip: text plus glyph, never color alone.
class _StateChip extends StatelessWidget {
  const _StateChip({
    required this.label,
    required this.glyph,
    required this.background,
    required this.foreground,
  });

  final String label;
  final IconData glyph;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(glyph, size: 15, color: foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.2,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Accessible disclosure: real button semantics, expanded state, 48 px target.
class _DisclosureRow extends StatelessWidget {
  const _DisclosureRow({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      expanded: expanded,
      // Material is provided locally: the embedded SEO center renders without
      // a Scaffold, and an InkWell must never depend on the host for ink.
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  expanded ? 'Ocultar detalle' : 'Ver detalle',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
