import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../models/website_canvas_alignment.dart';
import '../models/website_canvas_layer_identity.dart';
import '../models/website_canvas_manipulation.dart';
import '../models/website_canvas_responsive_document.dart';
import '../models/website_responsive_authoring.dart';
import '../providers/website_edit_mode_provider.dart';
import 'website_editor_contextual_dock.dart';

/// Every Canvas layer operation, in the surface Design gives them.
///
/// **Why here and not in the dock.** `F-06` puts every touch target at 48 and
/// the dock is one row: four manipulation modes plus align, z-order, lock,
/// visibility, duplicate and delete cannot be a row at 390 without shrinking
/// something below its published size. t10 assigns groups to `O-05`, so the
/// dock keeps identity plus the entry and this is the group.
///
/// **Nothing here owns state.** Every control calls an existing provider or
/// binding command, so the phone and the pointer host produce the same
/// operation and the same single history step. A blocked mode stays visible,
/// goes inert and says why (`A-01`); a silent no-op on a locked layer is the
/// outcome this exists to prevent.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 frames **10d** (layer rows: 44,
/// 48 touch, state stated in words) and **10e**/`O-05`. **Not published:** any
/// paint for direct-manipulation handles, which is why the capability lives
/// here rather than in an invented handle.
class WebsiteCanvasLayerActions extends StatelessWidget {
  const WebsiteCanvasLayerActions({super.key, required this.provider});

  final WebsiteEditModeProvider provider;

  @visibleForTesting
  static const Key groupKey = Key('website-canvas-layer-actions');

  @visibleForTesting
  static Key modeKey(WebsiteCanvasManipulationMode mode) =>
      Key('website-canvas-layer-mode-${mode.name}');

  @visibleForTesting
  static const Key lockKey = Key('website-canvas-layer-lock');

  @visibleForTesting
  static const Key visibilityKey = Key('website-canvas-layer-visibility');

  @visibleForTesting
  static Key alignKey(WebsiteCanvasAlignment alignment) =>
      Key('website-canvas-layer-align-${alignment.name}');

  @visibleForTesting
  static Key zOrderKey(String action) => Key('website-canvas-layer-z-$action');

  @visibleForTesting
  static const Key duplicateKey = Key('website-canvas-layer-duplicate');

  @visibleForTesting
  static const Key deleteKey = Key('website-canvas-layer-delete');

  @visibleForTesting
  static Key geometryKey(String field) =>
      Key('website-canvas-layer-geometry-$field');

  /// `A-02` at touch size for the icon-only grids (align, z-order).
  static const double iconTarget = 48;

  /// The six alignments, in reading order.
  static const List<WebsiteCanvasAlignment> alignments =
      <WebsiteCanvasAlignment>[
    WebsiteCanvasAlignment.left,
    WebsiteCanvasAlignment.horizontalCenter,
    WebsiteCanvasAlignment.right,
    WebsiteCanvasAlignment.top,
    WebsiteCanvasAlignment.verticalCenter,
    WebsiteCanvasAlignment.bottom,
  ];

  static String labelForAlignment(WebsiteCanvasAlignment alignment) =>
      switch (alignment) {
        WebsiteCanvasAlignment.left => 'Alinear a la izquierda',
        WebsiteCanvasAlignment.horizontalCenter => 'Centrar horizontalmente',
        WebsiteCanvasAlignment.right => 'Alinear a la derecha',
        WebsiteCanvasAlignment.top => 'Alinear arriba',
        WebsiteCanvasAlignment.verticalCenter => 'Centrar verticalmente',
        WebsiteCanvasAlignment.bottom => 'Alinear abajo',
      };

  static IconData _iconForAlignment(WebsiteCanvasAlignment alignment) =>
      switch (alignment) {
        WebsiteCanvasAlignment.left => Icons.align_horizontal_left,
        WebsiteCanvasAlignment.horizontalCenter =>
          Icons.align_horizontal_center,
        WebsiteCanvasAlignment.right => Icons.align_horizontal_right,
        WebsiteCanvasAlignment.top => Icons.align_vertical_top,
        WebsiteCanvasAlignment.verticalCenter => Icons.align_vertical_center,
        WebsiteCanvasAlignment.bottom => Icons.align_vertical_bottom,
      };

  /// `F-06` · below 900 the density is touch.
  static const double rowHeight = 48;

  static bool _isRenderedCommandCurrent(
    WebsiteEditModeProvider provider,
    WebsiteCanvasLayerTarget target,
    WebsiteViewport requestedViewport,
    WebsiteViewport effectiveViewport,
    int selectionVersion,
  ) =>
      provider.previewViewport == requestedViewport &&
      provider.renderedCanvasViewport(target.document) == effectiveViewport &&
      provider.selectedCanvasLayerTarget == target &&
      provider.selectionVersion == selectionVersion;

  static WebsiteWriteScope _visibleWriteScope(
    WebsiteEditModeProvider provider,
    WebsiteViewport viewport,
  ) =>
      viewport == WebsiteViewport.desktop
          ? WebsiteWriteScope.shared
          : provider.writeScope;

  static String _scopeName(
    WebsiteViewport viewport,
    WebsiteWriteScope scope,
  ) =>
      WebsiteEditorContextualDock.scopeLabelFor(
        viewport: viewport,
        scope: scope,
      ).replaceFirst('Escribe en: ', '');

  static bool _isRenderedFieldCommandCurrent(
    WebsiteEditModeProvider provider,
    WebsiteCanvasLayerTarget target,
    WebsiteViewport requestedViewport,
    WebsiteViewport effectiveViewport,
    int selectionVersion,
    WebsiteWriteScope writeScope,
  ) =>
      _isRenderedCommandCurrent(
        provider,
        target,
        requestedViewport,
        effectiveViewport,
        selectionVersion,
      ) &&
      _visibleWriteScope(provider, effectiveViewport) == writeScope;

  static String _viewportName(WebsiteViewport viewport) => switch (viewport) {
        WebsiteViewport.mobile => 'móvil',
        WebsiteViewport.tablet => 'tablet',
        WebsiteViewport.desktop => 'escritorio',
      };

  @override
  Widget build(BuildContext context) {
    final target = provider.selectedCanvasLayerTarget;
    if (target == null) return const SizedBox.shrink();
    final requestedViewport = provider.previewViewport;
    final viewport = provider.renderedCanvasViewport(target.document);
    if (viewport == null) {
      return Column(
        key: groupKey,
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _GroupHeader(
            label: provider.selectedCanvasLayerLabel ?? 'Capa del lienzo',
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              WebsiteEditorContextualDock.reasonFor(
                WebsiteCanvasManipulationBlockReason.canvasNotMeasured,
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      );
    }
    final selectionVersion = provider.selectionVersion;
    final defaultWriteScope = provider.writeScope;
    final visibleWriteScope = _visibleWriteScope(provider, viewport);
    final visibleScopeName = _scopeName(viewport, visibleWriteScope);
    final visibilityScopeName = _scopeName(
      viewport,
      WebsiteWriteScope.viewport,
    );

    final document = provider.canvasDocument(
      target.document.blockId,
      slideIndex: target.document.slideIndex,
    );
    if (document == null) return const SizedBox.shrink();

    final layers = WebsiteCanvasResponsiveDocument.projectLayers(
      data: document,
      viewport: viewport,
    );
    final projectedDocument = WebsiteCanvasResponsiveDocument.project(
      data: document,
      viewport: viewport,
    );
    WebsiteCanvasLayerProjection? layer;
    for (final candidate in layers) {
      if (candidate.id == target.layerId) layer = candidate;
    }
    if (layer == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final activeSession = provider.canvasManipulationSession;
    final activeMode =
        activeSession?.target == target && activeSession?.viewport == viewport
            ? activeSession?.mode
            : null;
    final locked = layer.data['locked'] == true;
    // `A-01` · a boundary is stated. A locked layer keeps every control in
    // place and inert, so the operator learns WHY nothing happened.
    final lockedReason =
        locked ? 'La capa está bloqueada. Desbloquéala para moverla.' : null;

    return Column(
      key: groupKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _GroupHeader(
          label: '${WebsiteCanvasLayerIdentity.describe(layer)} · '
              '$visibleScopeName'
              '${requestedViewport == viewport ? '' : ' · Vista ${_viewportName(viewport)} (solicitada: ${_viewportName(requestedViewport)})'}',
        ),
        // The four modes. Each states its own availability.
        for (final mode in WebsiteCanvasManipulationMode.values)
          _ModeRow(
            mode: mode,
            isActive: activeMode == mode,
            availability: provider.canvasManipulationAvailability(
              mode,
              target: target,
              viewport: viewport,
            ),
            // The target is part of this rendered command. If selection moves
            // before an old callback fires, availability rejects A rather than
            // silently arming the newly selected B.
            onEnter: () {
              if (!_isRenderedCommandCurrent(
                    provider,
                    target,
                    requestedViewport,
                    viewport,
                    selectionVersion,
                  ) ||
                  provider.writeScope != defaultWriteScope) {
                return;
              }
              final started = provider.startCanvasManipulation(
                mode,
                target: target,
                viewport: viewport,
              );
              if (started && context.mounted) {
                // O-05 owns a modal route, so a successful mode choice hands
                // control straight back to the Canvas. `maybePop` addresses
                // the Navigator that owns this rendered sheet; an isolated
                // test/body mounted as the first route remains in place.
                Navigator.maybeOf(context)?.maybePop();
              }
            },
            // Likewise an exit born under S1 may stop only S1. It cannot tear
            // down S2 after a stop/re-arm race.
            onExit: () {
              final expected = activeSession;
              if (expected != null &&
                  expected.target == target &&
                  expected.mode == mode &&
                  expected.viewport == viewport) {
                provider.stopCanvasManipulation(expectedSession: expected);
              }
            },
          ),
        Divider(height: 1, color: theme.dividerColor),
        // Alignment — the six directions, through the ONE pure operation.
        _IconGrid(
          label: 'Alinear · $visibleScopeName',
          children: [
            for (final alignment in WebsiteCanvasLayerActions.alignments)
              _IconAction(
                actionKey: WebsiteCanvasLayerActions.alignKey(alignment),
                icon: WebsiteCanvasLayerActions._iconForAlignment(alignment),
                label: WebsiteCanvasLayerActions.labelForAlignment(alignment),
                onPressed: locked
                    ? null
                    : () => _align(
                          provider,
                          target,
                          layer!,
                          projectedDocument,
                          alignment,
                          requestedViewport,
                          viewport,
                          selectionVersion,
                          visibleWriteScope,
                        ),
                disabledReason: lockedReason,
              ),
          ],
        ),
        // Z-order — the four moves the document supports.
        _IconGrid(
          label: 'Orden · $visibleScopeName',
          children: [
            _IconAction(
              actionKey: WebsiteCanvasLayerActions.zOrderKey('back'),
              icon: Icons.vertical_align_bottom,
              label: 'Enviar al fondo',
              onPressed: locked
                  ? null
                  : () => _reorder(
                        provider,
                        target,
                        0,
                        requestedViewport,
                        viewport,
                        selectionVersion,
                        visibleWriteScope,
                      ),
              disabledReason: lockedReason,
            ),
            _IconAction(
              actionKey: WebsiteCanvasLayerActions.zOrderKey('backward'),
              icon: Icons.arrow_downward,
              label: 'Una atrás',
              onPressed: locked
                  ? null
                  : () => _reorder(
                        provider,
                        target,
                        layer!.order - 1,
                        requestedViewport,
                        viewport,
                        selectionVersion,
                        visibleWriteScope,
                      ),
              disabledReason: lockedReason,
            ),
            _IconAction(
              actionKey: WebsiteCanvasLayerActions.zOrderKey('forward'),
              icon: Icons.arrow_upward,
              label: 'Una adelante',
              onPressed: locked
                  ? null
                  : () => _reorder(
                        provider,
                        target,
                        layer!.order + 1,
                        requestedViewport,
                        viewport,
                        selectionVersion,
                        visibleWriteScope,
                      ),
              disabledReason: lockedReason,
            ),
            _IconAction(
              actionKey: WebsiteCanvasLayerActions.zOrderKey('front'),
              icon: Icons.vertical_align_top,
              label: 'Traer al frente',
              onPressed: locked
                  ? null
                  : () => _reorder(
                        provider,
                        target,
                        layers.length - 1,
                        requestedViewport,
                        viewport,
                        selectionVersion,
                        visibleWriteScope,
                      ),
              disabledReason: lockedReason,
            ),
          ],
        ),
        Divider(height: 1, color: theme.dividerColor),
        // Numeric precision, so no operation depends on a steady finger.
        _GroupHeader(label: 'Geometría · $visibleScopeName'),
        _GeometryFields(
          provider: provider,
          target: target,
          layer: layer,
          requestedViewport: requestedViewport,
          viewport: viewport,
          selectionVersion: selectionVersion,
        ),
        Divider(height: 1, color: theme.dividerColor),
        // State the operator can change without entering a mode at all.
        _ToggleRow(
          rowKey: lockKey,
          label: layer.data['locked'] == true
              ? 'Desbloquear capa'
              : 'Bloquear capa',
          description: layer.data['locked'] == true
              ? 'Bloqueada: no se puede mover ni redimensionar. Alcance: común.'
              : 'Bloquear impide moverla por accidente. Alcance: común.',
          value: layer.data['locked'] == true,
          // `locked` is declared `sharedOnly` by the Canvas policy registry: a
          // lock protects the layer, it is not a per-device presentation. The
          // scope stated here is the one the write will honour.
          onChanged: (next) {
            if (!_isRenderedCommandCurrent(
              provider,
              target,
              requestedViewport,
              viewport,
              selectionVersion,
            )) {
              return;
            }
            provider.setCanvasLayerProperties(
              target.document.blockId,
              target.layerId,
              <String, dynamic>{'locked': next},
              slideIndex: target.document.slideIndex,
              scope: WebsiteWriteScope.shared,
              viewport: viewport,
            );
          },
        ),
        _ToggleRow(
          rowKey: visibilityKey,
          label: viewport == WebsiteViewport.desktop
              ? (layer.visible ? 'Ocultar capa' : 'Mostrar capa')
              : (layer.visible ? 'Ocultar en este viewport' : 'Mostrar aquí'),
          // t10 10d: visibility is independent per viewport, and a layer
          // hidden here stays selectable and repairable in Edit.
          description: viewport == WebsiteViewport.desktop
              ? layer.visible
                  ? 'Cambia la visibilidad base de la capa. Alcance: común.'
                  : 'Oculta en la base y en viewports que la heredan. '
                      'Alcance: común.'
              : layer.visible
                  ? 'La visibilidad es independiente por dispositivo. '
                      'Alcance: $visibilityScopeName.'
                  : 'Oculta aquí; sigue existiendo en los demás viewports. '
                      'Alcance: $visibilityScopeName.',
          value: !layer.visible,
          // t10 `visibility.layer` is `responsiveVisibility`: independent per
          // viewport by contract, so this writes THIS viewport and leaves the
          // others exactly as they were.
          onChanged: (hidden) {
            if (!_isRenderedCommandCurrent(
              provider,
              target,
              requestedViewport,
              viewport,
              selectionVersion,
            )) {
              return;
            }
            provider.setCanvasLayerProperties(
              target.document.blockId,
              target.layerId,
              <String, dynamic>{'visible': !hidden},
              slideIndex: target.document.slideIndex,
              scope: WebsiteWriteScope.viewport,
              viewport: viewport,
            );
          },
        ),
        Divider(height: 1, color: theme.dividerColor),
        _TextAction(
          actionKey: WebsiteCanvasLayerActions.duplicateKey,
          label: 'Duplicar capa · común',
          // The new identity is minted by the caller, as the command
          // requires. It is derived from the source plus the draft revision so
          // two duplicates in one session cannot collide.
          onPressed: () {
            if (!_isRenderedCommandCurrent(
              provider,
              target,
              requestedViewport,
              viewport,
              selectionVersion,
            )) {
              return;
            }
            provider.duplicateCanvasLayer(
              target.document.blockId,
              target.layerId,
              '${target.layerId}-copia-'
              '${provider.document.sessionRevision}-'
              '${DateTime.now().microsecondsSinceEpoch}',
              slideIndex: target.document.slideIndex,
            );
          },
        ),
        // `O-03 VbConfirmDialog` · the safe exit holds the initial focus and
        // the buttons name the act. Never Sí/No.
        _TextAction(
          actionKey: WebsiteCanvasLayerActions.deleteKey,
          label: 'Eliminar capa · común',
          destructive: true,
          onPressed: () => _confirmDelete(
            context,
            provider,
            target,
            requestedViewport,
            viewport,
            selectionVersion,
          ),
        ),
      ],
    );
  }

  /// Alignment through the ONE pure operation, written as one geometry command.
  void _align(
    WebsiteEditModeProvider provider,
    WebsiteCanvasLayerTarget target,
    WebsiteCanvasLayerProjection layer,
    Map<String, dynamic> projectedDocument,
    WebsiteCanvasAlignment alignment,
    WebsiteViewport requestedViewport,
    WebsiteViewport viewport,
    int selectionVersion,
    WebsiteWriteScope writeScope,
  ) {
    if (!_isRenderedFieldCommandCurrent(
      provider,
      target,
      requestedViewport,
      viewport,
      selectionVersion,
      writeScope,
    )) {
      return;
    }
    final origin = WebsiteCanvasAlignmentMath.align(
      alignment: alignment,
      x: (layer.data['x'] as num?)?.toDouble() ?? 0,
      y: (layer.data['y'] as num?)?.toDouble() ?? 0,
      width: (layer.data['w'] as num?)?.toDouble() ?? 0,
      height: (layer.data['h'] as num?)?.toDouble() ?? 0,
      // The inspector is authoritative about the document's declared surface.
      designWidth: (projectedDocument['designWidth'] as num?)?.toDouble() ?? 0,
      designHeight: ((projectedDocument['designHeight'] ??
                  projectedDocument['blockHeight']) as num?)
              ?.toDouble() ??
          0,
    );
    // ONE write, so one history step: both axes travel together even though
    // an alignment only ever moves one of them.
    provider.setCanvasLayerProperties(
      target.document.blockId,
      target.layerId,
      <String, Object?>{'x': origin.x, 'y': origin.y},
      slideIndex: target.document.slideIndex,
      // Alignment follows the same X-field attribution the full inspector
      // publishes. The visible global/field scope, not this compact surface,
      // decides whether the operation is common or a viewport override.
      scope: writeScope,
      viewport: viewport,
    );
  }

  void _reorder(
    WebsiteEditModeProvider provider,
    WebsiteCanvasLayerTarget target,
    int targetIndex,
    WebsiteViewport requestedViewport,
    WebsiteViewport viewport,
    int selectionVersion,
    WebsiteWriteScope writeScope,
  ) {
    if (!_isRenderedFieldCommandCurrent(
      provider,
      target,
      requestedViewport,
      viewport,
      selectionVersion,
      writeScope,
    )) {
      return;
    }
    provider.reorderCanvasLayer(
      target.document.blockId,
      target.layerId,
      targetIndex,
      slideIndex: target.document.slideIndex,
      scope: writeScope,
      viewport: viewport,
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WebsiteEditModeProvider provider,
    WebsiteCanvasLayerTarget target,
    WebsiteViewport requestedViewport,
    WebsiteViewport viewport,
    int selectionVersion,
  ) async {
    final intent = provider.captureAsyncIntent(
      blockId: target.document.blockId,
    );
    if (intent == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('¿Eliminar esta capa?'),
        content: const Text(
          'Se quita del lienzo. Puedes deshacerlo mientras no guardes.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Conservar capa'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar capa'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final live = context.read<WebsiteEditModeProvider>();
    live.commitAsyncIntent(intent, () {
      if (!_isRenderedCommandCurrent(
        live,
        target,
        requestedViewport,
        viewport,
        selectionVersion,
      )) {
        return WebsiteInlineMutationResult.rejected;
      }
      final changed = live.removeCanvasLayer(
        target.document.blockId,
        target.layerId,
        slideIndex: target.document.slideIndex,
      );
      return changed
          ? WebsiteInlineMutationResult.committed
          : WebsiteInlineMutationResult.unchanged;
    });
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

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

/// One manipulation mode, with its availability stated in place.
class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.mode,
    required this.isActive,
    required this.availability,
    required this.onEnter,
    required this.onExit,
  });

  final WebsiteCanvasManipulationMode mode;
  final bool isActive;
  final WebsiteCanvasManipulationAvailability availability;
  final VoidCallback onEnter;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final enabled = availability.isAvailable || isActive;
    final reason = availability.reason;
    final label = WebsiteEditorContextualDock.labelForMode(mode);

    return Semantics(
      button: true,
      enabled: enabled,
      selected: isActive,
      child: InkWell(
        key: WebsiteCanvasLayerActions.modeKey(mode),
        onTap: enabled ? (isActive ? onExit : onEnter) : null,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: WebsiteCanvasLayerActions.rowHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isActive
                ? (roles?.info.container ?? theme.colorScheme.primaryContainer)
                : null,
            border: Border(
              bottom: BorderSide(color: theme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isActive ? '$label · activo' : label,
                      style: TextStyle(
                        color: enabled
                            ? theme.colorScheme.onSurface
                            : (roles?.disabledForeground ??
                                theme.colorScheme.onSurface
                                    .withValues(alpha: 0.38)),
                        fontSize: 13.5,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    // `A-01`: the boundary is stated, never a silent no-op.
                    if (!enabled && reason != null)
                      Text(
                        WebsiteEditorContextualDock.reasonFor(reason),
                        style: theme.textTheme.bodySmall,
                      ),
                    if (isActive)
                      Text(
                        switch (mode) {
                          WebsiteCanvasManipulationMode.move =>
                            'Arrastra la capa en el lienzo. Toca para salir.',
                          WebsiteCanvasManipulationMode.resize =>
                            'Arrastra un tirador del marco. Toca para salir.',
                          WebsiteCanvasManipulationMode.rotate =>
                            'Arrastra el control circular. Toca para salir.',
                          WebsiteCanvasManipulationMode.crop =>
                            'Arrastra la imagen dentro del marco. Toca para salir.',
                        },
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (isActive)
                Icon(
                  Icons.check,
                  size: 18,
                  color: roles?.info.accent ?? theme.colorScheme.primary,
                  semanticLabel: 'Modo activo',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A layer state the operator flips without entering a mode.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.rowKey,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final Key rowKey;
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      toggled: value,
      child: Container(
        key: rowKey,
        constraints: const BoxConstraints(
          minHeight: WebsiteCanvasLayerActions.rowHeight,
        ),
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
                    label,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(description, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// A labelled row of icon-only actions, each at the touch target.
class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Semantics(
              header: true,
              child: Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
          // Wraps instead of overflowing: six 48 targets do not fit one row at
          // 390, and `F-06` does not allow making them smaller.
          Wrap(children: children),
        ],
      ),
    );
  }
}

/// `A-02` at touch size. The glyph does not grow with the hit area.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.disabledReason,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: enabled ? label : (disabledReason ?? label),
      child: IconButton(
        key: actionKey,
        onPressed: onPressed,
        icon: Icon(icon, size: 18, semanticLabel: label),
        iconSize: 18,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: WebsiteCanvasLayerActions.iconTarget,
          minHeight: WebsiteCanvasLayerActions.iconTarget,
        ),
        style: IconButton.styleFrom(
          fixedSize: const Size.square(WebsiteCanvasLayerActions.iconTarget),
        ),
      ),
    );
  }
}

/// A full-width row action, at the touch row height.
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.actionKey,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final Key actionKey;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    return Semantics(
      button: true,
      child: InkWell(
        key: actionKey,
        onTap: onPressed,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: WebsiteCanvasLayerActions.rowHeight,
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: destructive
                  ? (roles?.danger.accent ?? theme.colorScheme.error)
                  : theme.colorScheme.onSurface,
              fontSize: 13.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Numeric precision for the layer's geometry.
///
/// Every field is `perViewportGeometry`, but this compact surface publishes one
/// visible default-scope badge rather than five independent field shells. Its
/// writes therefore follow that exact visible default: common or this viewport.
class _GeometryFields extends StatelessWidget {
  const _GeometryFields({
    required this.provider,
    required this.target,
    required this.layer,
    required this.requestedViewport,
    required this.viewport,
    required this.selectionVersion,
  });

  final WebsiteEditModeProvider provider;
  final WebsiteCanvasLayerTarget target;
  final WebsiteCanvasLayerProjection layer;
  final WebsiteViewport requestedViewport;
  final WebsiteViewport viewport;
  final int selectionVersion;

  static const List<({String key, String label})> _fields =
      <({String key, String label})>[
    (key: 'x', label: 'X'),
    (key: 'y', label: 'Y'),
    (key: 'w', label: 'Ancho'),
    (key: 'h', label: 'Alto'),
    (key: 'rotation', label: 'Rotación'),
  ];

  @override
  Widget build(BuildContext context) {
    final locked = layer.data['locked'] == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final field in _fields)
            Builder(
              builder: (context) {
                final writeScope = WebsiteCanvasLayerActions._visibleWriteScope(
                  provider,
                  viewport,
                );
                return SizedBox(
                  width: 104,
                  child: _GeometryField(
                    key: ValueKey(
                      '${target.document.blockId}|'
                      '${target.document.slideIndex}|'
                      '${target.layerId}|${requestedViewport.name}|'
                      '${viewport.name}|${field.key}',
                    ),
                    fieldKey: WebsiteCanvasLayerActions.geometryKey(field.key),
                    label: field.label,
                    value: (layer.data[field.key] as num?)?.toDouble(),
                    viewport: viewport,
                    enabled: !locked,
                    onSubmitted: (next) {
                      if (!WebsiteCanvasLayerActions
                          ._isRenderedFieldCommandCurrent(
                        provider,
                        target,
                        requestedViewport,
                        viewport,
                        selectionVersion,
                        writeScope,
                      )) {
                        return false;
                      }
                      return provider.setCanvasLayerProperties(
                        target.document.blockId,
                        target.layerId,
                        <String, Object?>{field.key: next},
                        slideIndex: target.document.slideIndex,
                        scope: writeScope,
                        viewport: viewport,
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _GeometryField extends StatefulWidget {
  const _GeometryField({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.viewport,
    required this.enabled,
    required this.onSubmitted,
  });

  final Key fieldKey;
  final String label;
  final double? value;
  final WebsiteViewport viewport;
  final bool enabled;
  final bool Function(double) onSubmitted;

  @override
  State<_GeometryField> createState() => _GeometryFieldState();
}

class _GeometryFieldState extends State<_GeometryField> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));

  static String _format(double? value) {
    if (value == null) return '';
    return value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);
  }

  @override
  void didUpdateWidget(covariant _GeometryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only adopt an external change: retyping the field's own value under the
    // operator's cursor is how a numeric control starts fighting the keyboard.
    if ((widget.value != oldWidget.value ||
            widget.viewport != oldWidget.viewport) &&
        _format(widget.value) != _controller.text) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = double.tryParse(_controller.text.replaceAll(',', '.'));
    // A value that does not parse is not a write: the field returns to the
    // document's truth rather than inventing one.
    if (parsed == null) {
      _controller.text = _GeometryFieldState._format(widget.value);
      return;
    }
    if (parsed == widget.value) return;
    if (!widget.onSubmitted(parsed)) {
      _controller.text = _GeometryFieldState._format(widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: widget.fieldKey,
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _commit(),
      onTapOutside: (_) => _commit(),
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
