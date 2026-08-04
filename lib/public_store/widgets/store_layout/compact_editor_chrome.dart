part of '../public_store_layout.dart';

/// Controls of the compact editor command bar.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames 10e/10f/10h and 11a
/// (`A-02 VbIconButton` at touch size on the shell, `O-05 VbBottomSheet` rows
/// of 48 with separators).

/// `A-02` on the shell, at touch size: 48 hit area, 16 glyph.
///
/// The glyph does not grow with the hit area — that is the published rule, and
/// it is why a compact bar can hold real targets without looking like a
/// toolbar of oversized icons.
class _CompactBarIconButton extends StatelessWidget {
  const _CompactBarIconButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.disabledReason,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  /// `A-01` · a disabled control always explains itself.
  final String? disabledReason;

  /// `F-06` · below 900 the density is touch.
  static const double target = 48;

  /// `A-02` · the glyph size, independent of the hit area.
  static const double glyph = 16;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: enabled ? label : (disabledReason ?? label),
      child: IconButton(
        key: buttonKey,
        onPressed: onPressed,
        icon: Icon(icon, size: glyph, semanticLabel: label),
        iconSize: glyph,
        color: color,
        disabledColor: color.withValues(alpha: 0.38),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: target,
          minHeight: target,
        ),
        style: IconButton.styleFrom(fixedSize: const Size.square(target)),
      ),
    );
  }
}

/// `O-05` · the sheet handle, 34×4.
class _CompactSheetHandle extends StatelessWidget {
  const _CompactSheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Center(
        child: Container(
          width: WebsiteBlockEditSheetGeometry.handleWidth,
          height: WebsiteBlockEditSheetGeometry.handleHeight,
          decoration: BoxDecoration(
            color: Theme.of(context).dividerColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

/// A labelled group inside the actions sheet.
///
/// Moving a wall of commands into a sheet is not simplification; grouping and
/// labelling them is what makes the drawer navigable.
class _CompactSheetGroup extends StatelessWidget {
  const _CompactSheetGroup({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Semantics(
        header: true,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}

/// `O-05` · a 48 row with a separator.
class _CompactSheetRow extends StatelessWidget {
  const _CompactSheetRow({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.disabledReason,
    this.destructive = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// `A-01` · when present the row is inert AND says why, in place. It is
  /// never hidden: a capability the operator cannot reach right now still has
  /// to be discoverable.
  final String? disabledReason;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final enabled = disabledReason == null;
    final Color foreground;
    if (!enabled) {
      foreground = roles?.disabledForeground ??
          theme.colorScheme.onSurface.withValues(alpha: 0.38);
    } else if (destructive) {
      foreground = roles?.danger.accent ?? theme.colorScheme.error;
    } else {
      foreground = theme.colorScheme.onSurface;
    }

    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (!enabled)
                      Text(
                        disabledReason!,
                        style: TextStyle(
                          color: roles?.disabledForeground ??
                              theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              if (selected)
                Icon(
                  Icons.check,
                  size: 18,
                  color: roles?.info.accent ?? theme.colorScheme.primary,
                  semanticLabel: 'Seleccionado',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The published/unpublished state, as a row that shows the current value.
///
/// A selector must expose its current value; hiding a business state behind an
/// ellipsis is not an acceptable compact design.
///
/// It receives state and a callback and knows nothing about persistence.
/// `_PublicStoreLayoutState._setSitePublished` is the single owner of that
/// write for both bars — publication is an outward-facing effect and must not
/// have a second writer deciding the stored value or the confirmation.
class _CompactSheetPublishRow extends StatelessWidget {
  const _CompactSheetPublishRow({
    required this.published,
    required this.onChanged,
  });

  final bool published;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      toggled: published,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Publicado',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    published
                        ? 'El sitio está visible para tus clientes.'
                        : 'El sitio no está visible para tus clientes.',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              key: const ValueKey('editor-compact-publish-switch'),
              value: published,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
