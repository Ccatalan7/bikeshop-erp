import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_sub_tabs.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../models/website_responsive_authoring.dart';
import '../providers/website_edit_mode_provider.dart';
import 'deferred_website_editor_panel.dart';
import 'website_block_edit_section.dart';
import 'website_canvas_layer_actions.dart';
import 'website_editor_chrome_geometry.dart';
import 'website_editor_contextual_dock.dart';
import 'website_editor_host_theme.dart';
import 'website_editor_contextual_operation_scope.dart';

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

/// The task a single O-05 route is presenting.
///
/// The route/chrome owner stays shared, while the body is intentionally one
/// task at a time. This prevents the Canvas actions scroll from wrapping the
/// desktop inspector's bounded Expanded and keeps the two dock controls
/// honest about what they open.
enum WebsiteBlockEditSheetTask {
  inspector,
  canvasLayerActions,
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
  WebsiteBlockEditSheetTask task = WebsiteBlockEditSheetTask.inspector,
  WebsiteViewport? effectiveViewport,
}) {
  // Resolve before opening the route: [context] still sits inside the editor
  // boundary and can recover the ERP preset even when the canvas below it is
  // wearing the tenant's authored theme. Brightness is intentionally fixed by
  // the inspector owner.
  final inspectorTheme = WebsiteEditorInspectorTheme.resolveFrom(context);
  final requestedViewport = provider.previewViewport;
  final selectedBlockId = provider.selectedBlockId;
  final selectedBlockViewport = selectedBlockId == null
      ? null
      : provider.renderedBlockViewportFor(selectedBlockId);
  final renderedViewport = effectiveViewport ??
      selectedBlockViewport ??
      WebsiteEditorChromeScope.maybeOf(context)?.canvasViewport ??
      requestedViewport;
  return showWebsiteContextualSheet<void>(
    context: context,
    builder: (sheetContext) {
      // `.value`: the sheet is a route outside the editor subtree, so it is
      // handed the SAME provider instance instead of creating a second one.
      return Theme(
        data: inspectorTheme,
        child: WebsiteEditorAuthoringViewportScope(
          requestedViewport: requestedViewport,
          effectiveViewport: renderedViewport,
          child: ChangeNotifierProvider<WebsiteEditModeProvider>.value(
            value: provider,
            child: WebsiteBlockEditSheet(task: task),
          ),
        ),
      );
    },
  );
}

/// The `O-05` route, owned once.
///
/// Every contextual sheet in the editor opens through here so the barrier, the
/// scroll-control flag and the SafeArea decision cannot drift between two
/// sheets that are supposed to be the same object to the operator.
///
/// [useRootNavigator] is the one thing a caller decides, because it depends on
/// where the caller sits relative to the contextual dock. The dock is a `Stack`
/// sibling of the canvas inside the editor shell, so it paints above every
/// route the canvas's own Navigator hosts:
///
/// * opened from the dock — the block sheet — the nearest Navigator is already
///   above the shell, and the default keeps that route inside the workspace
///   branch where it belongs;
/// * opened from inside the canvas — the inline CTA — it is not, and the sheet
///   would render *under* the dock. The canvas has no handle on the branch
///   Navigator, so that caller escapes to the root.
Future<T?> showWebsiteContextualSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useRootNavigator = false,
}) async {
  final lease = WebsiteEditorContextualOperationScope.maybeControllerOf(
    context,
  )?.acquire();
  try {
    return await showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      // The canvas must stay visible above the sheet: t10 10f edits the block
      // while its image is still on screen. A scrim would defeat that.
      barrierColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      elevation: 0,
      // The sheet owns its own height cap and its own SafeArea/viewInsets
      // handling; the route must not letterbox it first.
      isScrollControlled: true,
      useSafeArea: false,
      builder: builder,
    );
  } finally {
    lease?.release();
  }
}

/// The sheet body. Public so a widget test can mount it without a route.
class WebsiteBlockEditSheet extends StatefulWidget {
  const WebsiteBlockEditSheet({
    this.task = WebsiteBlockEditSheetTask.inspector,
    super.key,
  });

  final WebsiteBlockEditSheetTask task;

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
    final theme = Theme.of(context);

    final selectedId = provider.selectedBlockId;
    final block = selectedId == null ? null : provider.getBlock(selectedId);
    final chrome = provider.selectedChromeTarget;
    // Chrome names itself. The sheet BODY already knew how to render the
    // header — `_EditBlockTab` branches on the reserved id before it looks the
    // selection up — so the only thing wrong here was the title falling
    // through to the generic word for a surface that has a real name.
    final title = chrome != null || block != null
        ? WebsiteEditorContextualDock.identityLabelForSelection(
            chrome: chrome,
            block: block ?? const <String, dynamic>{},
          )
        : 'Bloque';
    final isCanvasLayerTask =
        widget.task == WebsiteBlockEditSheetTask.canvasLayerActions;
    // A block inspector is mixed too: titles/actions can be common-only while
    // height, spacing, media framing and presentation fields may target this
    // viewport. One sheet-level sentence would lie for at least one control.
    // Chrome is the exception because header/footer settings are site-wide by
    // contract and therefore always common.
    final scope = chrome == null ? null : 'Escribe en: común';
    final hasCanvasLayerTarget = provider.selectedCanvasLayerTarget != null;

    return WebsiteContextualSheetScaffold(
      surfaceKey: WebsiteBlockEditSheet.sheetKey,
      title: title,
      scope: scope,
      // `T-04` navigates between sets. Chrome has no sets: `_EditBlockTab`
      // returns the header and footer controls *before* it consults the
      // section, so mounting three tabs there would offer navigation that
      // changes nothing — a control that lies about being a control. A
      // surface with one group shows no tabs.
      headerExtras: chrome != null || isCanvasLayerTask
          ? [Divider(height: 1, color: theme.dividerColor)]
          : [
              Divider(height: 1, color: theme.dividerColor),
              VbSubTabs<WebsiteBlockEditSection>(
                key: WebsiteBlockEditSheet.sectionTabsKey,
                tabs: [
                  for (final value in WebsiteBlockEditSection.values)
                    VbSubTab<WebsiteBlockEditSection>(
                      value: value,
                      label: value.label,
                    ),
                ],
                value: _section,
                onChanged: (value) => setState(() => _section = value),
                // `F-06` · below 900 the density is touch, and `T-04`
                // publishes 40 as its comfortable height.
                density: VbSubTabsDensity.comfortable,
                overflowTooltip: 'Más secciones del bloque',
              ),
              Divider(height: 1, color: theme.dividerColor),
            ],
      footer: _SheetDoneCta(
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      child: isCanvasLayerTask
          ? hasCanvasLayerTarget
              ? SingleChildScrollView(
                  // Canvas layer actions are a complete, typed O-05 intent.
                  // Nesting the desktop inspector here duplicated operations
                  // and put its Expanded under an unbounded scroll owner.
                  // The block inspector remains the sibling intent reached by
                  // selecting the owning block instead of its nested layer.
                  child: WebsiteCanvasLayerActions(provider: provider),
                )
              : const _NoSelection(
                  message:
                      'Selecciona una capa del lienzo para ver sus acciones.',
                )
          : selectedId == null
              ? const _NoSelection()
              : DeferredWebsiteBlockEditSurface(
                  editProvider: provider,
                  section: _section,
                ),
    );
  }
}

/// The `O-05` chrome itself: cap, radius, handle, title, keyboard and SafeArea.
///
/// Extracted from the block sheet so a second contextual sheet reuses the
/// published geometry instead of restating it. Everything measured here comes
/// from [WebsiteBlockEditSheetGeometry], which reads `handoff-t10/spec.json`;
/// this widget adds no value of its own.
class WebsiteContextualSheetScaffold extends StatelessWidget {
  const WebsiteContextualSheetScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.footer,
    this.scope,
    this.surfaceKey,
    this.headerExtras = const <Widget>[],
  });

  final String title;

  /// The `Escribe en: …` sentence, when the surface can state it truthfully.
  /// Null renders no badge — a sheet that does not know its attribution says
  /// nothing rather than guessing one.
  final String? scope;

  final Widget child;
  final Widget footer;
  final Key? surfaceKey;

  /// Rows between the title and the body — the block sheet's `T-04` tabs and
  /// their separators. Empty for a sheet that edits a single object.
  final List<Widget> headerExtras;

  @override
  Widget build(BuildContext context) {
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

    return Padding(
      // `viewInsets` pushes the whole sheet up with the keyboard.
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Material(
          key: surfaceKey,
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
                ...headerExtras,
                Expanded(child: child),
                footer,
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
  final String? scope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scopeLabel = scope;
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
          if (scopeLabel != null) ...[
            const SizedBox(width: 8),
            VbStatusBadge(label: scopeLabel, tone: VbStatusTone.neutral),
          ],
        ],
      ),
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
  const _NoSelection({
    this.message = 'Toca un bloque de la página para editarlo.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
