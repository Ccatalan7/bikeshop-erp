import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../providers/website_edit_mode_provider.dart';
import 'website_editor_host_theme.dart';

/// Something on the canvas that is not a page block but is selected and
/// edited like one: the header, the footer, and the sections a catalog page
/// draws from its presentation (its hero, plans, list and closing).
///
/// [selectionId] is the reserved value carried by `selectedBlockId`; the
/// inspector reads it to show this object's controls.
///
/// Two states, told apart by more than colour: unselected is a hairline plus an
/// outline chip, selected is the selection ring plus a filled chip. Both name
/// the object in words, so the state survives a monochrome screenshot and a
/// colour-blind operator.
class WebsiteEditorSelectableSurface extends StatelessWidget {
  const WebsiteEditorSelectableSurface({
    super.key,
    required this.selectionId,
    required this.label,
    required this.semanticsLabel,
    required this.child,
    this.badgeIcon = Icons.edit_outlined,
    this.childAdoptsHostTheme = false,
  });

  final String selectionId;

  /// What the chip calls it («Portada», «Encabezado»).
  final String label;

  /// What a screen reader announces («Portada de la página»).
  final String semanticsLabel;
  final IconData badgeIcon;
  final Widget child;

  /// The header and the footer have always been drawn under the ERP theme
  /// restored here; a catalog section keeps the site's theme, which its
  /// colours come from.
  final bool childAdoptsHostTheme;

  @visibleForTesting
  static Key badgeKeyFor(String selectionId) =>
      Key('website-editor-chrome-badge-$selectionId');

  @visibleForTesting
  static Key surfaceKeyFor(String selectionId) =>
      Key('website-editor-chrome-surface-$selectionId');

  @override
  Widget build(BuildContext context) {
    final selected = context.select<WebsiteEditModeProvider, bool>(
      (provider) => provider.selectedBlockId == selectionId,
    );
    void select() =>
        context.read<WebsiteEditModeProvider>().selectBlock(selectionId);

    // The operator's chrome wears the ERP, never the tenant's site.
    //
    // This widget is mounted INSIDE the storefront's `Theme(data: websiteTheme)`
    // and inside whatever `VinabikeThemeRoles` that theme carries, so reading
    // `Theme.of` here dressed the editor's own selection ring in the customer's
    // brand — and made it change when the tenant changed their palette. The ERP
    // host theme published above the storefront is restored for this subtree.
    final host = WebsiteEditorHostTheme.maybeOf(context);
    final theme = host?.theme ?? Theme.of(context);
    final roles = host?.roles ?? VinabikeThemeRoles.maybeOf(context);

    // Selection is a SELECTION role, not the informational accent: the ring
    // and the chip take the selection pair and the badge reads against it.
    final accent = roles?.focusRing ?? theme.colorScheme.primary;
    final selectionFill =
        roles?.selectionContainer ?? theme.colorScheme.primaryContainer;
    final onSelection =
        roles?.onSelectionContainer ?? theme.colorScheme.onPrimaryContainer;
    final hairline = roles?.neutral.border ?? theme.dividerColor;

    final chrome = Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected ? accent : hairline,
                  width: selected ? 3 : 1,
                ),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color:
                          selected ? selectionFill : theme.colorScheme.surface,
                      border: Border.all(color: accent),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        key: badgeKeyFor(selectionId),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            badgeIcon,
                            size: 12,
                            color: selected ? onSelection : accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            label,
                            style: TextStyle(
                              color: selected ? onSelection : accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel,
      child: Focus(
        // Reachable and operable without a pointer: `Enter` and `Space` are
        // the same operation as a tap. Only while the surface itself holds
        // the focus — a field inside it (a text being written on the page)
        // keeps every key, its spaces included.
        onKeyEvent: (node, event) {
          if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
            return KeyEventResult.ignored;
          }
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.numpadEnter ||
              key == LogicalKeyboardKey.space) {
            select();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          key: surfaceKeyFor(selectionId),
          // Translucent, not opaque: what is inside keeps receiving its taps.
          // Selecting the surface must not cost the operator the ability to
          // operate (or write in) what is inside it.
          behavior: HitTestBehavior.translucent,
          onTap: select,
          child:
              childAdoptsHostTheme ? Theme(data: theme, child: chrome) : chrome,
        ),
      ),
    );
  }
}
