import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_segmented.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../models/website_responsive_authoring.dart';
import '../models/website_responsive_field_state.dart';

/// The visible authority of the responsive authoring model, per field.
///
/// The plan's rule is that the global viewport/scope control only supplies a
/// default: it may never hide which scope a given field writes. This shell is
/// therefore the one surface that always answers three questions at once —
/// *what is this value*, *where does it come from* and *where will my next
/// change land* — and it answers the third in words, not only in colour.
///
/// It is a pure presentation widget. It consumes an already-resolved
/// [WebsiteResponsiveFieldState] and never reinterprets persistence, never
/// reads a serialized key and never writes: the two callbacks are the only
/// outputs, and each state exposes at most one of them.
///
/// One owner serves every host. The desktop inspector and the phone
/// inline/sheet surfaces mount the same widget; only `F-06` density changes.
class ResponsiveFieldShell<T> extends StatelessWidget {
  const ResponsiveFieldShell({
    super.key,
    required this.state,
    required this.child,
    this.onCustomize,
    this.onReset,
    this.helpText,
    this.density,
  });

  /// Resolved inheritance for this field. Owned by the model layer.
  final WebsiteResponsiveFieldState<T> state;

  /// The real control — media row, colour field, slider, text input.
  final Widget child;

  /// Called only from the explicit "Personalizar para …" action.
  final VoidCallback? onCustomize;

  /// Called only from the explicit "Restablecer a Común" action.
  final VoidCallback? onReset;

  /// Overrides [WebsiteBlockFieldSchema.helpText].
  final String? helpText;

  /// Overrides the resolved `F-06` density. Product code lets it resolve.
  final VbDensity? density;

  /// `F-04` escala.
  static const double _gapSmall = 4;
  static const double _gapRow = 6;
  static const double _gapBlock = 8;

  /// `F-02` label · IBM Plex Sans 11 / 500.
  static const double _labelSize = 11;
  static const FontWeight _labelWeight = FontWeight.w500;

  /// `F-02` bodyM · 12.5 / 400 / 1.45 — used by help and explanation lines.
  static const double _bodySize = 12.5;
  static const double _bodyHeight = 1.45;

  @visibleForTesting
  static const Key customizeActionKey = Key('responsive-field-customize');

  @visibleForTesting
  static const Key resetActionKey = Key('responsive-field-reset');

  @visibleForTesting
  static const Key scopeNoticeKey = Key('responsive-field-scope');

  VbStatusTone get _tone => switch (state.status) {
        // `E-01`: neutral = "sin carga".
        WebsiteResponsiveFieldStatus.common => VbStatusTone.neutral,
        WebsiteResponsiveFieldStatus.inherited => VbStatusTone.neutral,
        WebsiteResponsiveFieldStatus.sharedOnly => VbStatusTone.neutral,
        WebsiteResponsiveFieldStatus.unavailable => VbStatusTone.neutral,
        // `E-01`: accent = "necesita criterio humano" -> the `info` role.
        WebsiteResponsiveFieldStatus.overridden => VbStatusTone.info,
        // `E-01`: warning = "te toca actuar".
        WebsiteResponsiveFieldStatus.legacyConflict => VbStatusTone.warning,
      };

  /// The sentence that makes "Común" and "Móvil" impossible to confuse.
  String get _scopeNotice {
    if (state.status == WebsiteResponsiveFieldStatus.unavailable) {
      return 'Este campo no se puede editar aquí.';
    }
    return switch (state.effectiveWriteScope) {
      WebsiteWriteScope.shared => 'Los cambios se guardan en el valor común.',
      WebsiteWriteScope.viewport =>
        'Los cambios se guardan sólo para ${state.context.previewViewport.label}.',
    };
  }

  /// The two states that promise no silent write, and therefore must not leave
  /// the control operable.
  ///
  /// `unavailable` has nothing to write to; `legacyConflict` renders a value
  /// that belongs to an older mobile setting, so editing it in place would
  /// silently promote legacy data into a canonical override. In both, the only
  /// legitimate output is the explicit "Restablecer a Común" action, which
  /// lives outside the blocked subtree.
  bool get _childIsInert =>
      state.status == WebsiteResponsiveFieldStatus.unavailable ||
      state.status == WebsiteResponsiveFieldStatus.legacyConflict;

  /// Extra explanation for the states that must never write silently.
  String? get _stateExplanation => switch (state.status) {
        WebsiteResponsiveFieldStatus.sharedOnly =>
          'Esta propiedad no varía por dispositivo.',
        WebsiteResponsiveFieldStatus.legacyConflict =>
          'El valor viene de una configuración móvil anterior. '
              'Restablécelo para volver al valor común.',
        WebsiteResponsiveFieldStatus.unavailable => state.unavailableReason,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final resolvedDensity = density ?? VbDensity.resolve(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion
        ? VbSegmentedMetrics.motionReduced
        : VbSegmentedMetrics.motionFast;

    final labelStyle =
        (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
      fontSize: _labelSize,
      fontWeight: _labelWeight,
      color: theme.colorScheme.onSurface,
    );
    final bodyStyle = (theme.textTheme.bodySmall ?? const TextStyle()).copyWith(
      fontSize: _bodySize,
      height: _bodyHeight,
      color: roles.neutral.accent,
    );

    final help = helpText ?? state.schema.helpText;
    final explanation = _stateExplanation;
    final action = _buildAction(
      context,
      density: resolvedDensity,
      labelStyle: labelStyle,
    );

    return Semantics(
      container: true,
      // Contains label, status and scope in one sentence.
      label: state.semanticSummary,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Text(state.schema.label, style: labelStyle),
                ),
              ),
              const SizedBox(width: _gapRow),
              // Fade only: `F-05` forbids displacement under reduce-motion, and
              // a status change must never move the field it describes.
              AnimatedSwitcher(
                duration: duration,
                switchInCurve: VbSegmentedMetrics.motionCurve,
                switchOutCurve: VbSegmentedMetrics.motionCurve,
                child: ExcludeSemantics(
                  key: ValueKey<WebsiteResponsiveFieldStatus>(state.status),
                  child: VbStatusBadge(
                    label: state.statusLabel,
                    tone: _tone,
                  ),
                ),
              ),
            ],
          ),
          if (help != null && help.trim().isNotEmpty) ...[
            const SizedBox(height: _gapSmall),
            ExcludeSemantics(child: Text(help, style: bodyStyle)),
          ],
          const SizedBox(height: _gapBlock),
          // The value stays visible — it is the evidence the user needs to
          // decide — but pointer, focus and the semantics actions that come
          // with them are gone. `ExcludeFocus` removes keyboard traversal and
          // `IgnorePointer` removes hit testing; with `ignoringSemantics` left
          // at its default the semantics follow `ignoring`, so no action is
          // advertised that would do nothing when invoked.
          if (_childIsInert)
            ExcludeFocus(child: IgnorePointer(child: child))
          else
            child,
          const SizedBox(height: _gapRow),
          ExcludeSemantics(
            child: Text(
              key: scopeNoticeKey,
              _scopeNotice,
              style: bodyStyle,
            ),
          ),
          if (explanation != null && explanation.trim().isNotEmpty) ...[
            const SizedBox(height: _gapSmall),
            ExcludeSemantics(
              child: Text(
                explanation,
                style: bodyStyle.copyWith(
                  color: state.status ==
                          WebsiteResponsiveFieldStatus.legacyConflict
                      ? roles.warning.accent
                      : bodyStyle.color,
                ),
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: _gapSmall),
            Align(alignment: Alignment.centerLeft, child: action),
          ],
        ],
      ),
    );
  }

  /// At most one action per state, and each state owns exactly one callback.
  ///
  /// `sharedOnly` and `unavailable` offer none by construction: the model
  /// already reports `canCustomize == false` and `canReset == false` for them,
  /// so no surface can produce an override they do not allow.
  Widget? _buildAction(
    BuildContext context, {
    required VbDensity density,
    required TextStyle labelStyle,
  }) {
    final String label;
    final Key key;
    final VoidCallback? callback;

    if (state.canReset) {
      label = 'Restablecer a Común';
      key = resetActionKey;
      callback = onReset;
    } else if (state.canCustomize) {
      label = 'Personalizar para ${state.context.previewViewport.label}';
      key = customizeActionKey;
      callback = onCustomize;
    } else {
      return null;
    }
    if (callback == null) return null;

    // `F-06`: bajo 900 px el target es 48 sin importar la preferencia.
    final minHeight = density.controlHeight;
    return TextButton(
      key: key,
      onPressed: callback,
      style: TextButton.styleFrom(
        minimumSize: Size(0, minHeight),
        padding: const EdgeInsets.symmetric(horizontal: _gapBlock),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: labelStyle,
      ),
      child: Text(label),
    );
  }
}
