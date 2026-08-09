import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../models/website_block_registry.dart';
import '../models/website_block_type.dart';
import '../models/website_responsive_authoring.dart';
import '../providers/website_edit_mode_provider.dart';
import '../models/website_canvas_manipulation.dart';
import 'website_editor_block_sheet.dart';

/// The contextual dock — the compact host's answer to the desktop pane.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames **10e** (phone, light),
/// **10h** (phone, dark) and **10j** (tablet 834, same dock). Components:
/// `E-01 VbStatusBadge` for identity and scope, `A-02 VbIconButton` at the
/// touch size for the actions, `A-01 VbButton` primary for `Editar`,
/// `O-01 VbMenu` for the overflow and `O-03 VbConfirmDialog` for the delete.
///
/// Three properties make it a dock and not an app bar:
///
/// * it exists only while a block is selected — it accompanies the selection;
/// * it never covers the canvas permanently: it is the bottom band, the canvas
///   keeps the rest, and `Editar` opens a sheet capped at 60% (t10 `O-05`);
/// * it owns no state. Every action is an existing provider command, so the
///   phone and the desktop inspector produce the same operation and the same
///   single history step.
class WebsiteEditorContextualDock extends StatelessWidget {
  const WebsiteEditorContextualDock({super.key});

  /// The dock as a whole. Absent means no selection, not a hidden control.
  @visibleForTesting
  static const Key dockKey = Key('website-editor-contextual-dock');

  @visibleForTesting
  static const Key identityBadgeKey = Key('website-editor-dock-identity');

  @visibleForTesting
  static const Key scopeBadgeKey = Key('website-editor-dock-scope');

  @visibleForTesting
  static const Key moveUpKey = Key('website-editor-dock-move-up');

  @visibleForTesting
  static const Key moveDownKey = Key('website-editor-dock-move-down');

  @visibleForTesting
  static const Key visibilityKey = Key('website-editor-dock-visibility');

  @visibleForTesting
  static const Key duplicateKey = Key('website-editor-dock-duplicate');

  @visibleForTesting
  static const Key overflowKey = Key('website-editor-dock-more');

  @visibleForTesting
  static const Key editKey = Key('website-editor-dock-edit');

  /// Enters/leaves a direct-manipulation mode on the selected Canvas layer.
  @visibleForTesting
  static Key manipulationKey(WebsiteCanvasManipulationMode mode) =>
      Key('website-editor-dock-canvas-${mode.name}');

  /// Opens the `O-05` group that holds every layer operation.
  @visibleForTesting
  static const Key layerActionsKey = Key('website-editor-dock-layer-actions');

  /// Leaves whatever mode is active.
  @visibleForTesting
  static const Key exitManipulationKey = Key('website-editor-dock-canvas-exit');

  /// The operator-facing word for each mode.
  static String labelForMode(WebsiteCanvasManipulationMode mode) =>
      switch (mode) {
        WebsiteCanvasManipulationMode.move => 'Mover',
        WebsiteCanvasManipulationMode.resize => 'Redimensionar',
        WebsiteCanvasManipulationMode.rotate => 'Rotar',
        WebsiteCanvasManipulationMode.crop => 'Recortar',
      };

  static String viewportLabel(WebsiteViewport viewport) => switch (viewport) {
        WebsiteViewport.mobile => 'móvil',
        WebsiteViewport.tablet => 'tablet',
        WebsiteViewport.desktop => 'escritorio',
      };

  /// Why a mode cannot start, in the operator's words.
  ///
  /// `A-01` — a disabled control always explains itself. A silent no-op on a
  /// locked or hidden layer is the worst outcome: the operator taps, nothing
  /// happens, and nothing tells them the layer is locked.
  static String reasonFor(WebsiteCanvasManipulationBlockReason reason) =>
      switch (reason) {
        WebsiteCanvasManipulationBlockReason.editorInactive =>
          'Sólo se puede manipular en Edición.',
        WebsiteCanvasManipulationBlockReason.selectionMismatch =>
          'Selecciona la capa primero.',
        WebsiteCanvasManipulationBlockReason.canvasNotMeasured =>
          'Preparando el lienzo para esta ventana.',
        WebsiteCanvasManipulationBlockReason.viewportMismatch =>
          'La vista efectiva del lienzo cambió. Inténtalo de nuevo.',
        WebsiteCanvasManipulationBlockReason.documentMissing =>
          'Este bloque ya no tiene un lienzo.',
        WebsiteCanvasManipulationBlockReason.layerMissing =>
          'La capa ya no existe en este viewport.',
        WebsiteCanvasManipulationBlockReason.layerAmbiguous =>
          'Hay dos capas con la misma identidad. Revísalas antes de moverla.',
        WebsiteCanvasManipulationBlockReason.layerHidden =>
          'La capa está oculta en este viewport. Muéstrala para manipularla.',
        WebsiteCanvasManipulationBlockReason.layerLocked =>
          'La capa está bloqueada. Desbloquéala para manipularla.',
        WebsiteCanvasManipulationBlockReason.modeUnsupported =>
          'Esta capa no admite esta operación.',
      };

  /// `F-06` · below 900 the density is touch, so every target is 48.
  static const double touchTarget = 48;

  /// `A-02` · the glyph does not grow with the hit area.
  static const double glyphSize = 16;

  /// t10 10e · the primary action inside the dock row.
  static const double primaryActionHeight = 44;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WebsiteEditModeProvider>();
    // Edit chrome exists in Edit only. The shell already gates the mount, and
    // this second reading is deliberate: a dock that could survive a mode
    // change would put block commands on top of a visitor's Preview.
    if (!provider.isEditMode || !provider.isPageEditorWorkspace) {
      return const SizedBox.shrink();
    }
    final selectedId = provider.selectedBlockId;
    if (selectedId == null) return const SizedBox.shrink();

    // What KIND of thing is selected is asked before the document is searched.
    // Going straight to `indexWhere` is why the published header — selectable
    // on every host, and edited through the same sheet body as any block —
    // had no dock, and therefore no `Editar`, on the contextual host: its id
    // is reserved chrome, so the lookup was always -1 and the dock vanished.
    final chrome = provider.selectedChromeTarget;
    final blocks = provider.blocks;
    final index = blocks.indexWhere((block) => block['id'] == selectedId);
    if (chrome == null && index == -1) return const SizedBox.shrink();

    final block = index == -1 ? const <String, dynamic>{} : blocks[index];
    final isVisible = block['is_visible'] != false;
    final roles = VinabikeThemeRoles.maybeOf(context);
    final theme = Theme.of(context);
    // t10 10e/10h · the dock sits on `surface` with a hairline above it. Both
    // resolve from the active palette, so the same composition is correct in
    // light and dark without this widget knowing either value.
    final surface = theme.colorScheme.surface;
    final divider = theme.dividerColor;

    return Semantics(
      container: true,
      label: 'Acciones del bloque seleccionado',
      child: Material(
        key: dockKey,
        color: surface,
        // `F-05` popover depth: the dock floats over the canvas, it is not a
        // second canvas layer.
        elevation: 6,
        shadowColor: roles?.shadow ?? theme.shadowColor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: divider)),
          ),
          // One inset owner: the dock is the bottom-most editor chrome, so it
          // consumes the bottom system inset once and nothing below it adds a
          // second SafeArea.
          child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _IdentityRow(
                  provider: provider,
                  blockId: selectedId,
                  block: block,
                  chrome: chrome,
                ),
                _ActionRow(
                  provider: provider,
                  blockId: selectedId,
                  isFirst: index == 0,
                  isLast: index == blocks.length - 1,
                  isVisible: isVisible,
                  chrome: chrome,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// t10 10e/10h/10j copy: `Escribe en: móvil` / `tablet` / `común`.
  ///
  /// Desktop is the base and has no override slot, so the scope reads `común`
  /// there however the selector is set — the dock states the truth the write
  /// will follow, never the control's raw value.
  ///
  /// Public because the contextual sheet header must say the same sentence;
  /// two copies of this rule is how a header and a dock start disagreeing.
  /// The scope sentence for whatever is selected.
  ///
  /// Editor chrome is **always** common: the header and the footer are
  /// site-wide settings written through `updateHeaderSettings` /
  /// `updateFooterSettings`, which have no per-viewport slot at all. Passing
  /// them through [scopeLabelFor] would have printed `Escribe en: móvil`
  /// whenever the viewport selector said mobile — a sentence the write cannot
  /// honour. The dock states what the write will do, never what the selector
  /// happens to be set to.
  static String scopeLabelForSelection({
    required WebsiteEditorChromeTarget? chrome,
    required WebsiteViewport viewport,
    required WebsiteWriteScope scope,
  }) {
    if (chrome != null) return 'Escribe en: común';
    return scopeLabelFor(viewport: viewport, scope: scope);
  }

  static String scopeLabelFor({
    required WebsiteViewport viewport,
    required WebsiteWriteScope scope,
  }) {
    if (viewport == WebsiteViewport.desktop ||
        scope == WebsiteWriteScope.shared) {
      return 'Escribe en: común';
    }
    return switch (viewport) {
      WebsiteViewport.mobile => 'Escribe en: móvil',
      WebsiteViewport.tablet => 'Escribe en: tablet',
      WebsiteViewport.desktop => 'Escribe en: común',
    };
  }

  /// What the dock and the sheet call the current selection.
  ///
  /// Chrome names itself; a block asks the registry. One function so the dock
  /// and the sheet header can never disagree about what is being edited.
  static String identityLabelForSelection({
    required WebsiteEditorChromeTarget? chrome,
    required Map<String, dynamic> block,
  }) =>
      chrome?.label ?? identityLabelFor(block);

  /// The block's own name, from the registry — never the serialized key.
  ///
  /// Shared with the contextual sheet for the same reason as [scopeLabelFor].
  static String identityLabelFor(Map<String, dynamic> block) {
    final raw = (block['block_type'] ?? block['type'] ?? '').toString().trim();
    if (raw.isEmpty) return 'Bloque';
    for (final type in WebsiteBlockType.values) {
      if (type.name.toLowerCase() == raw.toLowerCase()) {
        return WebsiteBlockRegistry.definitionFor(type).title;
      }
    }
    return raw;
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.provider,
    required this.blockId,
    required this.block,
    required this.chrome,
  });

  final WebsiteEditModeProvider provider;
  final String blockId;
  final Map<String, dynamic> block;
  final WebsiteEditorChromeTarget? chrome;

  @override
  Widget build(BuildContext context) {
    var identity = WebsiteEditorContextualDock.identityLabelForSelection(
      chrome: chrome,
      block: block,
    );
    // The identity of the SELECTED LAYER reaches the dock, not just the block.
    // `Bloque · capa` named nothing: a canvas holds a headline, a button and
    // three shapes, and they are not interchangeable. t10 frame 10d shows what
    // a layer row says — kind plus its own useful words — and that naming has
    // one owner so the dock and the sheet cannot describe it differently.
    final layerTarget = provider.selectedCanvasLayerTarget;
    final effectiveCanvasViewport = layerTarget == null
        ? null
        : provider.renderedCanvasViewport(layerTarget.document);
    if (layerTarget != null && effectiveCanvasViewport == null) {
      // The selector is only a request. Until the renderer reports the real
      // Canvas width, neither layer projection nor write scope may borrow it
      // and present that guess as the effective viewport.
      identity = '$identity · vista efectiva sin medir';
    } else {
      final layerLabel = provider.selectedCanvasLayerLabel;
      if (layerLabel != null) identity = '$identity · $layerLabel';
      if (effectiveCanvasViewport != null &&
          effectiveCanvasViewport != provider.previewViewport) {
        identity = '$identity · vista '
            '${WebsiteEditorContextualDock.viewportLabel(effectiveCanvasViewport)}';
      }
    }
    final scope = layerTarget != null && effectiveCanvasViewport == null
        ? 'Preparando el lienzo'
        : WebsiteEditorContextualDock.scopeLabelForSelection(
            chrome: chrome,
            viewport: effectiveCanvasViewport ?? provider.previewViewport,
            scope: provider.writeScope,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Row(
        children: [
          Flexible(
            child: VbStatusBadge(
              key: WebsiteEditorContextualDock.identityBadgeKey,
              label: identity,
              tone: VbStatusTone.info,
            ),
          ),
          const SizedBox(width: 8),
          const Spacer(),
          Flexible(
            child: VbStatusBadge(
              key: WebsiteEditorContextualDock.scopeBadgeKey,
              label: scope,
              tone: VbStatusTone.neutral,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.provider,
    required this.blockId,
    required this.isFirst,
    required this.isLast,
    required this.isVisible,
    required this.chrome,
  });

  final WebsiteEditModeProvider provider;
  final String blockId;
  final bool isFirst;
  final bool isLast;
  final bool isVisible;
  final WebsiteEditorChromeTarget? chrome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // The header and the footer are site-wide chrome: they have no position in
    // the page, no duplicate and no delete. `A-01` says a boundary is stated,
    // not hidden — so the controls keep their place and their 48, go inert and
    // say why. Removing them would make the dock reflow under the finger and
    // would teach the operator that the phone editor has fewer capabilities
    // than it does.
    final chromeReason = chrome == null
        ? null
        : '${chrome!.label} es del sitio, no de esta página.';
    final isChrome = chrome != null;
    // A Canvas layer is selected when the block owns one and the operator
    // picked it. The dock states that identity and offers its operations, so
    // the capability does not depend on hitting a small handle.
    // The exact layer this dock operates on, from the session contract — not
    // an ambient guess. Null means there is no layer to manipulate.
    final layerTarget = isChrome ? null : provider.selectedCanvasLayerTarget;
    final effectiveCanvasViewport = layerTarget == null
        ? null
        : provider.renderedCanvasViewport(layerTarget.document);
    final activeSession = provider.canvasManipulationSession;
    final activeMode = activeSession?.target == layerTarget &&
            effectiveCanvasViewport != null &&
            activeSession?.viewport == effectiveCanvasViewport
        ? activeSession?.mode
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 8, 4),
      child: Row(
        children: [
          _DockIconButton(
            buttonKey: WebsiteEditorContextualDock.moveUpKey,
            icon: Icons.arrow_upward,
            label: 'Mover arriba',
            // A boundary is stated, not hidden: the control stays in place and
            // goes inert so the row never reflows under the finger.
            onPressed: isChrome || isFirst
                ? null
                : () => provider.moveBlockUp(blockId),
            disabledReason:
                chromeReason ?? 'Ya es el primer bloque de la página.',
          ),
          _DockIconButton(
            buttonKey: WebsiteEditorContextualDock.moveDownKey,
            icon: Icons.arrow_downward,
            label: 'Mover abajo',
            onPressed: isChrome || isLast
                ? null
                : () => provider.moveBlockDown(blockId),
            disabledReason:
                chromeReason ?? 'Ya es el último bloque de la página.',
          ),
          _DockIconButton(
            buttonKey: WebsiteEditorContextualDock.visibilityKey,
            icon: isVisible ? Icons.visibility : Icons.visibility_off,
            label: isVisible ? 'Ocultar bloque' : 'Mostrar bloque',
            onPressed:
                isChrome ? null : () => provider.toggleBlockVisibility(blockId),
            disabledReason: chromeReason,
          ),
          _DockIconButton(
            buttonKey: WebsiteEditorContextualDock.duplicateKey,
            icon: Icons.content_copy,
            label: 'Duplicar bloque',
            onPressed: isChrome ? null : () => provider.duplicateBlock(blockId),
            disabledReason: chromeReason,
          ),
          // ONE canvas control in the dock, and the modes in the sheet.
          //
          // Four 48 buttons for move/resize/rotate/crop plus the five block
          // actions overflowed the row at 390 — the same mistake as five tabs
          // in a `Row` of `Expanded`s, in a different place. `F-06` says every
          // target is 48, so the answer is not smaller buttons: it is that the
          // dock carries identity and frequent actions while `O-05` carries
          // groups. The dock keeps the entry and the way out; the modes and
          // every layer operation live in the sheet's `Capa` group.
          if (layerTarget != null)
            _DockIconButton(
              buttonKey: WebsiteEditorContextualDock.layerActionsKey,
              icon: Icons.layers_outlined,
              label: activeMode == null
                  ? 'Acciones de la capa'
                  : '${WebsiteEditorContextualDock.labelForMode(activeMode)} activo',
              isActive: activeMode != null,
              onPressed: () => showWebsiteBlockEditSheet(
                context: context,
                provider: provider,
                task: WebsiteBlockEditSheetTask.canvasLayerActions,
                effectiveViewport: effectiveCanvasViewport,
              ),
            ),
          if (activeMode != null)
            _DockIconButton(
              buttonKey: WebsiteEditorContextualDock.exitManipulationKey,
              icon: Icons.close_fullscreen,
              label: 'Salir de '
                  '${WebsiteEditorContextualDock.labelForMode(activeMode).toLowerCase()}',
              onPressed: () => provider.stopCanvasManipulation(
                expectedSession: activeSession!,
              ),
            ),
          _DockOverflowMenu(
            provider: provider,
            blockId: blockId,
            chromeReason: chromeReason,
          ),
          const Spacer(),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: WebsiteEditorContextualDock.primaryActionHeight,
              ),
              child: FilledButton(
                key: WebsiteEditorContextualDock.editKey,
                onPressed: () => showWebsiteBlockEditSheet(
                  context: context,
                  provider: provider,
                  task: WebsiteBlockEditSheetTask.inspector,
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(
                    0,
                    WebsiteEditorContextualDock.primaryActionHeight,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: theme.textTheme.labelLarge,
                ),
                child: const Text(
                  'Editar',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `A-02` at the touch size: 48 hit area, 16 glyph, always a semantic label.
class _DockIconButton extends StatelessWidget {
  const _DockIconButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.disabledReason,
    this.isActive = false,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// `A-01` · a disabled control always explains itself.
  final String? disabledReason;

  /// Whether this control's mode is the one currently running.
  ///
  /// Announced through `Semantics.selected` as well as painted, so "which mode
  /// am I in" never depends on telling two tints apart.
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final message = enabled ? label : (disabledReason ?? label);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final theme = Theme.of(context);
    return Tooltip(
      message: message,
      child: Semantics(
        selected: isActive,
        child: IconButton(
          key: buttonKey,
          onPressed: onPressed,
          icon: Icon(icon, size: WebsiteEditorContextualDock.glyphSize),
          iconSize: WebsiteEditorContextualDock.glyphSize,
          tooltip: null,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: WebsiteEditorContextualDock.touchTarget,
            minHeight: WebsiteEditorContextualDock.touchTarget,
          ),
          isSelected: isActive,
          style: IconButton.styleFrom(
            fixedSize: const Size.square(
              WebsiteEditorContextualDock.touchTarget,
            ),
            backgroundColor: isActive
                ? (roles?.info.container ?? theme.colorScheme.primaryContainer)
                : null,
          ),
        ),
      ),
    );
  }
}

/// `O-01 VbMenu` · the drawer for the actions the row cannot afford.
///
/// Delete lives here on purpose: `GUI_DESIGN_PRINCIPLES` §5 keeps destructive
/// commands in a discoverable secondary location, and it still confirms.
class _DockOverflowMenu extends StatelessWidget {
  const _DockOverflowMenu({
    required this.provider,
    required this.blockId,
    this.chromeReason,
  });

  final WebsiteEditModeProvider provider;
  final String blockId;

  /// Non-null when the selection is site chrome, which cannot be deleted.
  final String? chromeReason;

  @override
  Widget build(BuildContext context) {
    final canUndo = provider.canUndo;
    final canRedo = provider.canRedo;
    return Tooltip(
      message: 'Más acciones del bloque',
      child: PopupMenuButton<String>(
        key: WebsiteEditorContextualDock.overflowKey,
        tooltip: '',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 220),
        onSelected: (action) async {
          switch (action) {
            case 'undo':
              provider.undo();
            case 'redo':
              provider.redo();
            case 'delete':
              await _confirmDelete(context);
          }
        },
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'undo',
            enabled: canUndo,
            child: _MenuRow(
              icon: Icons.undo,
              label: 'Deshacer',
              // A disabled item explains itself in one line instead of
              // disappearing (`O-01`).
              reason: canUndo ? null : 'No hay cambios que deshacer.',
            ),
          ),
          PopupMenuItem<String>(
            value: 'redo',
            enabled: canRedo,
            child: _MenuRow(
              icon: Icons.redo,
              label: 'Rehacer',
              reason: canRedo ? null : 'No hay nada que rehacer.',
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem<String>(
            value: 'delete',
            enabled: chromeReason == null,
            child: _MenuRow(
              icon: Icons.delete_outline,
              label: 'Eliminar bloque',
              reason: chromeReason,
              destructive: chromeReason == null,
            ),
          ),
        ],
        child: const SizedBox(
          width: WebsiteEditorContextualDock.touchTarget,
          height: WebsiteEditorContextualDock.touchTarget,
          child: Icon(
            Icons.more_horiz,
            size: WebsiteEditorContextualDock.glyphSize,
            semanticLabel: 'Más acciones del bloque',
          ),
        ),
      ),
    );
  }

  /// `O-03 VbConfirmDialog` · the safe exit holds the initial focus and the
  /// buttons name the act. Never Sí/No.
  Future<void> _confirmDelete(BuildContext context) async {
    final intent = provider.captureAsyncIntent(blockId: blockId);
    if (intent == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar este bloque?'),
        content: const Text(
          'Se quita de la página. Puedes deshacerlo mientras no guardes.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Conservar bloque'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar bloque'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final live = context.read<WebsiteEditModeProvider>();
    live.commitAsyncIntent(intent, () {
      final before = live.blocks.length;
      live.deleteBlock(blockId);
      return live.blocks.length < before
          ? WebsiteInlineMutationResult.committed
          : WebsiteInlineMutationResult.unchanged;
    });
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.reason,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final String? reason;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final color =
        destructive ? (roles?.danger.accent ?? theme.colorScheme.error) : null;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(color: color)),
              if (reason != null)
                Text(
                  reason!,
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
