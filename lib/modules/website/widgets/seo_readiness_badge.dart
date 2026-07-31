import 'package:flutter/material.dart';

/// Visual vocabulary for the three independent SEO planes.
///
/// The Website Builder must never merge these into a single score or a
/// "listo/indexado" promise. Each plane has a different owner and a different
/// epistemic status:
///
/// * [SeoPlane.appEligibility] is decided by this application from current
///   publication and content. It is knowable right now.
/// * [SeoPlane.buildInclusion] is decided by the last deployed build. A value
///   saved today only appears here after the storefront is published again.
/// * [SeoPlane.googleIndex] is decided by Google. The product may only repeat
///   dated evidence; it may never predict or promise indexing.
enum SeoPlane { appEligibility, buildInclusion, googleIndex }

extension SeoPlaneCopy on SeoPlane {
  /// Short caption used above a badge in the detail body.
  String get caption => switch (this) {
        SeoPlane.appEligibility => 'Elegibilidad · nuestra app',
        SeoPlane.buildInclusion => 'Publicación · último build',
        SeoPlane.googleIndex => 'Google · evidencia',
      };

  /// One sentence explaining who decides this plane.
  String get explanation => switch (this) {
        SeoPlane.appEligibility =>
          'Lo decide esta aplicación con la publicación y el contenido actuales.',
        SeoPlane.buildInclusion =>
          'Evidencia del último build desplegado. Un cambio guardado hoy '
              'aparece aquí solo después de publicar la tienda.',
        SeoPlane.googleIndex =>
          'Evidencia fechada de Search Console. Google decide si indexa; esta '
              'aplicación no puede garantizarlo.',
      };
}

/// How a state should read, independent of the exact wording.
///
/// [neutral] is deliberately not a failure. An owner decision such as keeping
/// 128 of 133 collections out of the public site is a normal configuration,
/// not a defect, and must never be rendered as an error or as missing work.
///
/// [attention] is reserved for a state that contradicts the owner's apparent
/// intent (for example a published collection with no eligible products, which
/// the generator silently drops from the sitemap).
///
/// [unknown] means there is no evidence. It is never inferred from anything
/// else.
enum SeoBadgeTone { confirmed, neutral, attention, unknown }

/// One plane's readable state plus its provenance.
@immutable
class SeoBadgeState {
  const SeoBadgeState({
    required this.label,
    required this.tone,
    this.detail,
  });

  /// Human wording shown inside the badge, e.g. `Incluido`.
  final String label;

  final SeoBadgeTone tone;

  /// Reason, date or origin. For [SeoPlane.googleIndex] this should carry the
  /// consultation date and source whenever evidence exists.
  final String? detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SeoBadgeState &&
          other.label == label &&
          other.tone == tone &&
          other.detail == detail;

  @override
  int get hashCode => Object.hash(label, tone, detail);
}

/// Resolved colors and glyph for a tone.
///
/// Every value comes from a declared scheme role. The tones are additionally
/// separated by glyph so the state survives color-blindness, grayscale print
/// and low-contrast displays.
@immutable
class _SeoToneStyle {
  const _SeoToneStyle({
    required this.background,
    required this.border,
    required this.foreground,
    required this.glyph,
  });

  final Color background;
  final Color border;
  final Color foreground;
  final IconData glyph;
}

_SeoToneStyle _toneStyle(ThemeData theme, SeoBadgeTone tone) {
  final scheme = theme.colorScheme;
  return switch (tone) {
    SeoBadgeTone.confirmed => _SeoToneStyle(
        background: scheme.primaryContainer,
        border: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
        glyph: Icons.check_rounded,
      ),
    SeoBadgeTone.attention => _SeoToneStyle(
        background: scheme.tertiaryContainer,
        border: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
        glyph: Icons.warning_amber_rounded,
      ),
    SeoBadgeTone.neutral => _SeoToneStyle(
        background: scheme.surfaceContainerHighest,
        border: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
        glyph: Icons.remove_rounded,
      ),
    SeoBadgeTone.unknown => _SeoToneStyle(
        background: scheme.surface,
        border: scheme.outlineVariant,
        foreground: scheme.onSurfaceVariant,
        glyph: Icons.help_outline_rounded,
      ),
  };
}

/// A single plane rendered as a compact chip.
///
/// This is intentionally not [OperationalStatusBadge]: that badge encodes a
/// workflow status at a fixed 132 px with uppercase text and has no way to
/// express "no evidence" as distinct from a negative state. Geometry,
/// typography weight and radius are kept aligned with it so both read as one
/// system, but the label stays sentence case because phrases such as
/// "Sin evidencia de publicación" are unreadable in caps.
class SeoReadinessBadge extends StatelessWidget {
  const SeoReadinessBadge({
    super.key,
    required this.state,
    this.compact = false,
  });

  final SeoBadgeState state;

  /// Drops the provenance line. Used in dense list rows where the detail is
  /// available one tap away.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _toneStyle(theme, state.tone);
    final detail = state.detail?.trim();
    final showDetail = !compact && detail != null && detail.isNotEmpty;

    return Semantics(
      label: detail == null || detail.isEmpty
          ? state.label
          : '${state.label}. $detail',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: showDetail ? 6 : 5,
        ),
        decoration: BoxDecoration(
          color: style.background,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: style.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(style.glyph,
                    size: compact ? 13 : 14, color: style.foreground),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    state.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 11 : 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: style.foreground,
                    ),
                  ),
                ),
              ],
            ),
            if (showDetail) ...[
              const SizedBox(height: 3),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                  color: style.foreground,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The three planes side by side, never combined.
///
/// [showPlaneCaptions] adds the plane caption and the sentence explaining who
/// decides it. List rows keep captions off because the labels are already
/// self-describing; the detail body turns them on.
class SeoReadinessBadgeGroup extends StatelessWidget {
  const SeoReadinessBadgeGroup({
    super.key,
    required this.appEligibility,
    required this.buildInclusion,
    required this.googleIndex,
    this.showPlaneCaptions = false,
    this.compact = false,
  });

  final SeoBadgeState appEligibility;
  final SeoBadgeState buildInclusion;
  final SeoBadgeState googleIndex;
  final bool showPlaneCaptions;
  final bool compact;

  Map<SeoPlane, SeoBadgeState> get _states => {
        SeoPlane.appEligibility: appEligibility,
        SeoPlane.buildInclusion: buildInclusion,
        SeoPlane.googleIndex: googleIndex,
      };

  @override
  Widget build(BuildContext context) {
    if (!showPlaneCaptions) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final entry in _states.entries)
            SeoReadinessBadge(state: entry.value, compact: compact),
        ],
      );
    }

    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in _states.entries) ...[
          Text(
            entry.key.caption,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: SeoReadinessBadge(state: entry.value),
          ),
          const SizedBox(height: 5),
          Text(
            entry.key.explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          if (entry.key != SeoPlane.googleIndex) const SizedBox(height: 16),
        ],
      ],
    );
  }
}
