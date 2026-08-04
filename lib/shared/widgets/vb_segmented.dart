import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../themes/vinabike_theme_roles.dart';
import '../utils/responsive_breakpoints.dart';

/// Density resolved from `F-06 VbDensity`.
///
/// The guide is explicit: *"Bajo 900 px de ancho lógico la densidad se fuerza a
/// touch: 48 px de target sin importar la preferencia"*. It is therefore
/// resolved from the **logical viewport width** (`MediaQuery`), never from the
/// local box constraints — a 420 px inspector pane on a 1440 px desktop is a
/// narrow box on a pointer host, not a touch host.
///
/// It lives beside [VbSegmented] because that is the first shared consumer; a
/// dedicated token file is out of the scope of this change.
enum VbDensity {
  compact,
  comfortable,
  touch;

  /// `F-06`: control/botón 32 · 38 · 48.
  double get controlHeight => switch (this) {
        VbDensity.compact => 32,
        VbDensity.comfortable => 38,
        VbDensity.touch => 48,
      };

  /// `S-04`: "compact 28 · touch 48 total, segmentos iguales".
  ///
  /// The segmented control declares its own compact height (28), lower than the
  /// generic control height, because the track wraps the segments.
  double get segmentedHeight => switch (this) {
        VbDensity.compact => 28,
        VbDensity.comfortable => 38,
        VbDensity.touch => 48,
      };

  bool get isTouch => this == VbDensity.touch;

  /// Resolves the density for the current host.
  ///
  /// [preferred] models the future `VbScale`/density preference; today it only
  /// distinguishes compact from comfortable, and the sub-900 rule overrides it.
  static VbDensity resolve(
    BuildContext context, {
    VbDensity preferred = VbDensity.compact,
  }) {
    final width = MediaQuery.maybeSizeOf(context)?.width;
    if (width != null && width < ResponsiveBreakpoints.desktopMin) {
      return VbDensity.touch;
    }
    return preferred == VbDensity.touch ? VbDensity.comfortable : preferred;
  }
}

/// Shared geometry read from `F-04 Espacio, radio y trazo` and `F-05`.
abstract final class VbSegmentedMetrics {
  /// `F-04` radio · ctrl 6.
  static const double trackRadius = 6;

  /// `F-04` radio · tag 4 — the inner segment sits inside the track.
  static const double segmentRadius = 4;

  /// `F-04` escala · 2.
  static const double trackInset = 2;

  /// `F-04` escala · 10.
  static const double segmentPadding = 10;

  /// `F-04` trazo · anillo de foco 3.
  static const double focusRingWidth = 3;

  /// `F-04` trazo · hairline 1.
  static const double hairline = 1;

  /// `F-05` motion · fast 120 (hover, check).
  static const Duration motionFast = Duration(milliseconds: 120);

  /// `F-05` motion · "con reduce-motion todo pasa a opacidad <= 80 ms".
  static const Duration motionReduced = Duration(milliseconds: 80);

  /// `F-05` curva · cubic-bezier(.22,1,.36,1).
  static const Curve motionCurve = Cubic(0.22, 1, 0.36, 1);

  /// `F-02` label · IBM Plex Sans 11 / 500. `F-06`: the type does not change
  /// with density, only heights, paddings and gaps do.
  static const double labelSize = 11;
  static const FontWeight labelWeight = FontWeight.w500;
}

/// One option of a [VbSegmented].
///
/// A disabled option keeps its [disabledReason] visible as text. `A-01` is
/// explicit that a disabled control always explains itself and that a tooltip
/// is never the only channel.
@immutable
class VbSegmentedOption<T> {
  const VbSegmentedOption({
    required this.value,
    required this.label,
    this.enabled = true,
    this.disabledReason,
  }) : assert(
          enabled || disabledReason != null,
          'A-01: un segmento deshabilitado debe explicar su razón.',
        );

  final T value;

  /// `S-04` limits labels to one or two words.
  final String label;
  final bool enabled;
  final String? disabledReason;
}

/// `S-04 VbSegmented` — selection, never navigation.
///
/// The guide draws the boundary itself: *"Es selección, no navegación: para eso
/// están los tabs (T-04)"*, and caps the control at *"2–4 opciones, etiquetas de
/// 1–2 palabras, conjunto estable. Sin ícono solo, sin badge de conteo, sin
/// scroll horizontal."*
///
/// Keyboard follows `S-04` verbatim: one Tab stop, arrows change the selection,
/// Home/End jump to the extremes. Enter/Space re-confirm the focused option.
/// Disabled options are skipped by the arrows and can never be selected.
///
/// Colour comes only from [VinabikeThemeRoles] and [ColorScheme]; the control
/// declares no literal hex and no local shadow — `F-05` is explicit that a
/// surface inside a surface earns `surfaceSunken` or a hairline, not a shadow.
class VbSegmented<T> extends StatefulWidget {
  const VbSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.groupDisabledReason,
    this.density,
    this.groupLabel,
    this.showDisabledReasons = true,
  })  : assert(
          options.length >= 2 && options.length <= 4,
          'S-04: 2–4 opciones. Con más, es un select (S-05/S-06).',
        ),
        assert(
          onChanged != null ||
              (groupDisabledReason != null && groupDisabledReason.length > 0),
          'A-01: un grupo deshabilitado debe explicar su razón. '
          'Pasa groupDisabledReason cuando onChanged es null.',
        );

  final List<VbSegmentedOption<T>> options;
  final T value;

  /// Null disables the whole group and requires [groupDisabledReason].
  final ValueChanged<T>? onChanged;

  /// Why the whole control is inert.
  ///
  /// `A-01` — *"El botón inerte queda visible con su razón al lado. Nunca un
  /// botón muerto sin explicación, nunca un tooltip como único canal."* When
  /// the owner disables the group, this is the single explanation: it is
  /// rendered once as text and announced by every option, so the reason is
  /// never duplicated and never missing.
  final String? groupDisabledReason;

  /// Overrides the resolved density. Tests and embedded hosts use it; product
  /// code should let [VbDensity.resolve] decide.
  final VbDensity? density;

  /// Accessible name of the radio group.
  final String? groupLabel;

  /// Renders the reason of every disabled option below the track.
  final bool showDisabledReasons;

  @override
  State<VbSegmented<T>> createState() => _VbSegmentedState<T>();
}

class _VbSegmentedState<T> extends State<VbSegmented<T>> {
  late final FocusNode _focusNode = FocusNode(debugLabel: 'VbSegmented');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// The owner turned the whole control off; the reason is group-wide.
  bool get _disabledByOwner => widget.onChanged == null;

  bool get _groupEnabled =>
      !_disabledByOwner && widget.options.any((option) => option.enabled);

  /// The single reason announced for [option] while it cannot be chosen.
  ///
  /// Returns null when the option is selectable, so the caller never builds a
  /// sentence around a missing reason.
  String? _reasonFor(VbSegmentedOption<T> option) {
    if (_disabledByOwner) return widget.groupDisabledReason;
    if (!option.enabled) return option.disabledReason;
    return null;
  }

  int get _selectedIndex {
    final index =
        widget.options.indexWhere((option) => option.value == widget.value);
    return index < 0 ? 0 : index;
  }

  void _select(int index) {
    final onChanged = widget.onChanged;
    if (onChanged == null) return;
    if (index < 0 || index >= widget.options.length) return;
    final option = widget.options[index];
    if (!option.enabled) return;
    if (option.value == widget.value) return;
    onChanged(option.value);
  }

  /// Moves to the next enabled option in [direction], without wrapping.
  void _move(int direction) {
    var index = _selectedIndex + direction;
    while (index >= 0 && index < widget.options.length) {
      if (widget.options[index].enabled) {
        _select(index);
        return;
      }
      index += direction;
    }
  }

  void _moveToEdge({required bool last}) {
    final indexes = List<int>.generate(widget.options.length, (i) => i);
    for (final index in last ? indexes.reversed : indexes) {
      if (widget.options[index].enabled) {
        _select(index);
        return;
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_groupEnabled) return KeyEventResult.ignored;

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.arrowDown:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _moveToEdge(last: false);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _moveToEdge(last: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
        // Re-confirms the focused option. Selection already follows the arrows,
        // so this is a no-op when nothing changed.
        _select(_selectedIndex);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    assert(
      widget.onChanged != null ||
          (widget.groupDisabledReason?.trim().isNotEmpty ?? false),
      'A-01: groupDisabledReason no puede ser sólo espacios.',
    );
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final density = widget.density ?? VbDensity.resolve(context);
    final height = density.segmentedHeight;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion
        ? VbSegmentedMetrics.motionReduced
        : VbSegmentedMetrics.motionFast;

    final baseLabelStyle =
        (theme.textTheme.labelMedium ?? const TextStyle()).copyWith(
      fontSize: VbSegmentedMetrics.labelSize,
      fontWeight: VbSegmentedMetrics.labelWeight,
    );

    // One explanation, never two. A group turned off by its owner shows the
    // group reason once; otherwise each disabled option shows its own.
    final reasons = <String>[
      if (widget.showDisabledReasons)
        if (_disabledByOwner)
          widget.groupDisabledReason!
        else
          for (final option in widget.options)
            if (!option.enabled && option.disabledReason != null)
              '${option.label}: ${option.disabledReason}',
    ];

    final track = Focus(
      focusNode: _focusNode,
      canRequestFocus: _groupEnabled,
      onKeyEvent: _onKey,
      child: AnimatedBuilder(
        animation: _focusNode,
        builder: (context, child) {
          final showFocusRing = _focusNode.hasFocus;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: roles.neutral.container,
              borderRadius:
                  BorderRadius.circular(VbSegmentedMetrics.trackRadius),
              border: Border.all(
                color: showFocusRing ? roles.focusRing : roles.neutral.border,
                width: showFocusRing
                    ? VbSegmentedMetrics.focusRingWidth
                    : VbSegmentedMetrics.hairline,
              ),
            ),
            child: child,
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(VbSegmentedMetrics.trackInset),
          child: SizedBox(
            height: height,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < widget.options.length; i++) ...[
                  if (i > 0)
                    const SizedBox(width: VbSegmentedMetrics.trackInset),
                  // `S-04`: "segmentos iguales".
                  Expanded(
                    child: _VbSegment(
                      option: widget.options[i],
                      selected: i == _selectedIndex,
                      groupEnabled: _groupEnabled,
                      unavailableReason: _reasonFor(widget.options[i]),
                      labelStyle: baseLabelStyle,
                      duration: duration,
                      roles: roles,
                      colorScheme: theme.colorScheme,
                      onTap: () {
                        _focusNode.requestFocus();
                        _select(i);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      label: widget.groupLabel,
      explicitChildNodes: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          track,
          for (final reason in reasons) ...[
            const SizedBox(height: VbSegmentedMetrics.trackInset * 2),
            // Announced by every segment already; here it is the visible
            // channel `A-01` demands, not a second announcement.
            ExcludeSemantics(
              child: Text(
                reason,
                style: baseLabelStyle.copyWith(
                  color: roles.disabledForeground,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VbSegment<T> extends StatelessWidget {
  const _VbSegment({
    required this.option,
    required this.selected,
    required this.groupEnabled,
    required this.unavailableReason,
    required this.labelStyle,
    required this.duration,
    required this.roles,
    required this.colorScheme,
    required this.onTap,
  });

  final VbSegmentedOption<T> option;
  final bool selected;
  final bool groupEnabled;

  /// Why this segment cannot be chosen, or null when it can.
  final String? unavailableReason;
  final TextStyle labelStyle;
  final Duration duration;
  final VinabikeThemeRoles roles;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = groupEnabled && option.enabled;
    final foreground = !enabled
        ? roles.disabledForeground
        : selected
            ? colorScheme.onSurface
            : roles.neutral.accent;

    // `S-04` tokens: neutral.soft · surface · border. No shadow — `F-05` is
    // explicit that a surface inside a surface does not earn one.
    final background = selected ? colorScheme.surface : Colors.transparent;

    // Built by precedence and never around a missing reason: interpolating a
    // null here is what made a disabled group announce the word "null".
    final reason = unavailableReason?.trim();
    final semanticLabel = enabled
        ? option.label
        : (reason == null || reason.isEmpty)
            ? '${option.label}. No disponible.'
            : '${option.label}. No disponible. $reason';

    return Semantics(
      inMutuallyExclusiveGroup: true,
      button: true,
      selected: selected,
      enabled: enabled,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: duration,
          curve: VbSegmentedMetrics.motionCurve,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: VbSegmentedMetrics.segmentPadding,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius:
                BorderRadius.circular(VbSegmentedMetrics.segmentRadius),
          ),
          // The parent Semantics already names this option; letting the Text
          // contribute its own node would announce the label twice.
          child: ExcludeSemantics(
            child: Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: labelStyle.copyWith(
                color: foreground,
                // The selected option is also readable without colour.
                fontWeight: selected ? FontWeight.w600 : labelStyle.fontWeight,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
