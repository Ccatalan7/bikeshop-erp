import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../providers/website_edit_mode_provider.dart';
import 'deferred_website_editor_panel.dart';
import 'website_block_edit_section.dart';
import 'website_editor_contextual_dock.dart';

/// `O-05 VbBottomSheet` geometry, read from Design and not chosen here.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames **10f** and **10h**, plus
/// `handoff-t10/spec.json` `bottom_sheet_anatomy`:
/// "r14 arriba, handle 34×4, título 14 Poppins, filas de 48 con separador,
/// CTA de 50, máx. 60% de alto".
abstract final class WebsiteBlockEditSheetGeometry {
  /// `O-05` · top radius.
  static const double topRadius = 14;

  /// `O-05` · the grab handle.
  static const double handleWidth = 34;
  static const double handleHeight = 4;

  /// `O-05` · the title.
  static const double titleSize = 14;

  /// `O-05` · the closing CTA.
  static const double ctaHeight = 50;

  /// `O-05` · "Máx. 60% de alto; con más, es una página".
  ///
  /// This is the guarantee that the edited object stays visible. A group that
  /// does not fit is split into tasks; it never makes the sheet taller and it
  /// never becomes a route.
  static const double maxHeightFraction = 0.60;

  /// The height the sheet may occupy for a given available height.
  static double maxHeightFor(double availableHeight) =>
      availableHeight * maxHeightFraction;
}

/// Opens the selected block's controls as a contextual sheet.
///
/// Contract, from t10 §"Qué sobrevive" and the master plan §9.2 layer 3:
///
/// * the canvas stays mounted and visible — the barrier is transparent and the
///   sheet is capped at 60% of the available height;
/// * opening and closing performs **no** write, creates **no** history step and
///   changes neither the selection, the viewport nor the write scope;
/// * the sheet carries no `Guardar`. Save has exactly one owner
///   (`WebsiteEditorCommandScope`, surfaced by the compact top bar).
Future<void> showWebsiteBlockEditSheet({
  required BuildContext context,
  required WebsiteEditModeProvider provider,
}) {
  return showModalBottomSheet<void>(
    context: context,
    // The canvas must stay visible above the sheet: t10 10f edits the block
    // while its image is still on screen. A scrim would defeat that.
    barrierColor: Colors.transparent,
    backgroundColor: Colors.transparent,
    elevation: 0,
    // The sheet owns its own height cap and its own SafeArea/viewInsets
    // handling; the route must not letterbox it first.
    isScrollControlled: true,
    useSafeArea: false,
    builder: (sheetContext) {
      // `.value`: the sheet is a route outside the editor subtree, so it is
      // handed the SAME provider instance instead of creating a second one.
      return ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: const WebsiteBlockEditSheet(),
      );
    },
  );
}

/// The sheet body. Public so a widget test can mount it without a route.
class WebsiteBlockEditSheet extends StatefulWidget {
  const WebsiteBlockEditSheet({super.key});

  @visibleForTesting
  static const Key sheetKey = Key('website-editor-block-sheet');

  @visibleForTesting
  static const Key handleKey = Key('website-editor-block-sheet-handle');

  @visibleForTesting
  static const Key doneKey = Key('website-editor-block-sheet-done');

  @visibleForTesting
  static const Key sectionTabsKey = Key('website-editor-block-sheet-sections');

  @override
  State<WebsiteBlockEditSheet> createState() => _WebsiteBlockEditSheetState();
}

class _WebsiteBlockEditSheetState extends State<WebsiteBlockEditSheet> {
  WebsiteBlockEditSection _section = WebsiteBlockEditSection.content;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WebsiteEditModeProvider>();
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);

    // The keyboard is part of the geometry, not an afterthought: the sheet is
    // measured against the height the keyboard actually leaves, and its own
    // bottom padding is pushed by `viewInsets` so the CTA never ends up behind
    // the keyboard.
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight = media.size.height - keyboardInset;
    final maxHeight = WebsiteBlockEditSheetGeometry.maxHeightFor(
      availableHeight <= 0 ? media.size.height : availableHeight,
    );

    final selectedId = provider.selectedBlockId;
    final block =
        selectedId == null ? null : provider.getBlock(selectedId);
    final title = block == null
        ? 'Bloque'
        : WebsiteEditorContextualDock.identityLabelFor(block);
    final scope = WebsiteEditorContextualDock.scopeLabelFor(
      viewport: provider.previewViewport,
      scope: provider.writeScope,
    );

    return Padding(
      // `viewInsets` pushes the whole sheet up with the keyboard.
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          key: WebsiteBlockEditSheet.sheetKey,
          color: theme.colorScheme.surface,
          shadowColor: roles?.shadow ?? theme.shadowColor,
          elevation: 12,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(WebsiteBlockEditSheetGeometry.topRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SheetHandle(),
                _SheetTitleRow(title: title, scope: scope),
                Divider(height: 1, color: theme.dividerColor),
                _SheetSectionTabs(
                  key: WebsiteBlockEditSheet.sectionTabsKey,
                  section: _section,
                  onChanged: (value) => setState(() => _section = value),
                ),
                Divider(height: 1, color: theme.dividerColor),
                Expanded(
                  child: selectedId == null
                      ? const _NoSelection()
                      : DeferredWebsiteBlockEditSurface(
                          editProvider: provider,
                          section: _section,
                        ),
                ),
                _SheetDoneCta(
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Center(
        child: Container(
          key: WebsiteBlockEditSheet.handleKey,
          width: WebsiteBlockEditSheetGeometry.handleWidth,
          height: WebsiteBlockEditSheetGeometry.handleHeight,
          decoration: BoxDecoration(
            color: theme.dividerColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _SheetTitleRow extends StatelessWidget {
  const _SheetTitleRow({required this.title, required this.scope});

  final String title;
  final String scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: WebsiteBlockEditSheetGeometry.titleSize,
                    fontWeight: FontWeight.w600,
                  ) ??
                  const TextStyle(
                    fontSize: WebsiteBlockEditSheetGeometry.titleSize,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          VbStatusBadge(label: scope, tone: VbStatusTone.neutral),
        ],
      ),
    );
  }
}

/// `T-04 VbSubTabs` · 32 tall, 2 px accent underline, 12/600, no capsule and
/// no icons. Below 900 the density is touch, so the hit area grows to 48 while
/// the underline keeps its published geometry.
class _SheetSectionTabs extends StatelessWidget {
  const _SheetSectionTabs({
    super.key,
    required this.section,
    required this.onChanged,
  });

  final WebsiteBlockEditSection section;
  final ValueChanged<WebsiteBlockEditSection> onChanged;

  /// `T-04` · the underline weight.
  static const double underline = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final accent = roles?.info.accent ?? theme.colorScheme.primary;

    return Row(
      children: [
        for (final value in WebsiteBlockEditSection.values)
          Expanded(
            child: Semantics(
              button: true,
              selected: value == section,
              label: 'Sección ${value.label}',
              child: InkWell(
                key: Key('website-editor-sheet-section-${value.name}'),
                onTap: () => onChanged(value),
                child: Container(
                  height: WebsiteEditorContextualDock.touchTarget,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: value == section ? accent : Colors.transparent,
                        width: underline,
                      ),
                    ),
                  ),
                  child: Text(
                    value.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: value == section
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SheetDoneCta extends StatelessWidget {
  const _SheetDoneCta({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: SizedBox(
        width: double.infinity,
        height: WebsiteBlockEditSheetGeometry.ctaHeight,
        child: FilledButton(
          key: WebsiteBlockEditSheet.doneKey,
          onPressed: onPressed,
          // "Listo" closes the sheet. It is not a save: the edits are already
          // in the draft, and saving belongs to the top bar's single owner.
          child: const Text('Listo'),
        ),
      ),
    );
  }
}

class _NoSelection extends StatelessWidget {
  const _NoSelection();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Toca un bloque de la página para editarlo.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
