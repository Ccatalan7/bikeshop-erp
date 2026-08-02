import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'vb_anchored_popover.dart';
import 'vb_shell_icon_button.dart';

import '../services/workspace_manager.dart';
import 'quick_ui_settings_button.dart';
import 'share_workspace_link_button.dart';
import 'smart_screenshot_button.dart';
import 'workspace_shell_scope.dart';

/// Global navy workspace strip (40px).
///
/// The strip paints on `colorScheme.primary` and styles its own tabs with
/// explicit on-navy colors — deliberately NOT with an inherited [Theme]
/// override, because popup menus, dialogs and tooltips capture the inherited
/// themes of their trigger context and would drag the navy palette into every
/// overlay. The chrome tool buttons keep the base theme on a light pill.
///
/// A module may extend the block downward by rendering [ModuleCommandBar] at
/// the very top of its body; the strip's 1px bottom border then reads as the
/// block's internal hairline. That extension is opt-in per module.
class WorkspaceTabBar extends StatefulWidget {
  const WorkspaceTabBar({super.key});

  @override
  State<WorkspaceTabBar> createState() => _WorkspaceTabBarState();
}

class _WorkspaceTabBarState extends State<WorkspaceTabBar> {
  String? _draggingWorkspaceId;
  int? _hoveringWorkspaceIndex;

  static const double _regularTabWidth = 152;
  static const double _pinnedTabWidth = 144;
  static const double _trailingDropWidth = 24;

  void _startDrag(String workspaceId) {
    setState(() {
      _draggingWorkspaceId = workspaceId;
      _hoveringWorkspaceIndex = null;
    });
  }

  void _hoverIndex(int targetIndex) {
    if (_draggingWorkspaceId == null) {
      return;
    }

    final normalizedTargetIndex = _normalizedVisualTargetIndex(targetIndex);
    if (normalizedTargetIndex == null ||
        _hoveringWorkspaceIndex == normalizedTargetIndex) {
      return;
    }

    setState(() {
      _hoveringWorkspaceIndex = normalizedTargetIndex;
    });
  }

  void _finishDrag() {
    if (_draggingWorkspaceId == null && _hoveringWorkspaceIndex == null) {
      return;
    }

    setState(() {
      _draggingWorkspaceId = null;
      _hoveringWorkspaceIndex = null;
    });
  }

  List<Workspace> _displayedWorkspaces(List<Workspace> source) {
    final workspaces = List<Workspace>.from(source);
    if (_draggingWorkspaceId == null || _hoveringWorkspaceIndex == null) {
      return workspaces;
    }

    final draggedIndex =
        workspaces.indexWhere((w) => w.id == _draggingWorkspaceId);
    if (draggedIndex == -1) return workspaces;

    final draggedWorkspace = workspaces.removeAt(draggedIndex);
    final insertIndex =
        _normalizeVisualInsertIndex(workspaces, draggedWorkspace);
    workspaces.insert(insertIndex, draggedWorkspace);
    return workspaces;
  }

  int? _normalizedVisualTargetIndex(int targetIndex) {
    final workspaceManager = context.read<WorkspaceManager>();
    final workspaces = List<Workspace>.from(workspaceManager.workspaces);
    final draggedIndex =
        workspaces.indexWhere((w) => w.id == _draggingWorkspaceId);
    if (draggedIndex == -1) return null;

    final draggedWorkspace = workspaces.removeAt(draggedIndex);
    return _normalizeVisualInsertIndex(
      workspaces,
      draggedWorkspace,
      targetIndex: targetIndex,
    );
  }

  int _normalizeVisualInsertIndex(
    List<Workspace> workspaces,
    Workspace draggedWorkspace, {
    int? targetIndex,
  }) {
    final pinnedCount = workspaces.where((w) => w.isPinned).length;
    final minIndex = draggedWorkspace.isPinned ? 0 : pinnedCount;
    final maxIndex =
        draggedWorkspace.isPinned ? pinnedCount : workspaces.length;
    return (targetIndex ?? _hoveringWorkspaceIndex ?? workspaces.length)
        .clamp(minIndex, maxIndex)
        .toInt();
  }

  double _tabWidthFor(Workspace workspace) =>
      workspace.isPinned ? _pinnedTabWidth : _regularTabWidth;

  List<_WorkspaceTabPlacement> _placementsFor(List<Workspace> workspaces) {
    var left = 0.0;
    return workspaces.map((workspace) {
      final width = _tabWidthFor(workspace);
      final placement = _WorkspaceTabPlacement(
        workspace: workspace,
        left: left,
        width: width,
      );
      left += width;
      return placement;
    }).toList();
  }

  List<_WorkspaceDropPlacement> _dropPlacementsFor(
    List<Workspace> workspaces,
  ) {
    var left = 0.0;
    return workspaces.asMap().entries.map((entry) {
      final workspace = entry.value;
      final width = _tabWidthFor(workspace);
      final placement = _WorkspaceDropPlacement(
        workspace: workspace,
        targetIndex: entry.key,
        left: left,
        width: width,
      );
      left += width;
      return placement;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final workspaceManager = context.watch<WorkspaceManager>();
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;
    final displayedWorkspaces =
        _displayedWorkspaces(workspaceManager.workspaces);
    final placements = _placementsFor(displayedWorkspaces);
    final dropPlacements = _dropPlacementsFor(workspaceManager.workspaces);
    final stripWidth = placements.fold<double>(
          0,
          (width, placement) => width + placement.width,
        ) +
        _trailingDropWidth;

    // Debug: Log workspace state
    if (!workspaceManager.isInitialized) {
      debugPrint('⚠️ [WorkspaceTabBar] WorkspaceManager not yet initialized');
    } else {
      debugPrint(
          '✅ [WorkspaceTabBar] Rendering ${workspaceManager.workspaces.length} workspace(s)');
    }

    return Container(
      key: const ValueKey('workspace-tab-bar-surface'),
      height: WorkspaceShellScope.workspaceBarHeight,
      decoration: BoxDecoration(
        color: chrome.canvas,
        border: Border(
          bottom: BorderSide(
            color: chrome.edge,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              child: SizedBox(
                width: stripWidth,
                height: 40,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var index = 0; index < placements.length; index++)
                      AnimatedPositioned(
                        key: ValueKey(
                            'workspace-tab-position-${placements[index].workspace.id}'),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        left: placements[index].left,
                        top: 0,
                        width: placements[index].width,
                        height: 40,
                        child: _WorkspaceTab(
                          key: ValueKey(
                              'workspace-tab-${placements[index].workspace.id}'),
                          index: index,
                          workspace: placements[index].workspace,
                          isActive: placements[index].workspace.id ==
                              workspaceManager.activeWorkspace?.id,
                          isDragging: placements[index].workspace.id ==
                              _draggingWorkspaceId,
                          onTap: () {
                            workspaceManager.switchToWorkspaceById(
                              placements[index].workspace.id,
                            );
                          },
                          onTogglePin: () =>
                              workspaceManager.toggleWorkspacePinned(
                            workspaceManager.workspaces.indexWhere(
                              (w) => w.id == placements[index].workspace.id,
                            ),
                          ),
                          onDragStarted: () =>
                              _startDrag(placements[index].workspace.id),
                          onDragEnded: _finishDrag,
                          onClose: workspaceManager.workspaces.length > 1
                              ? () async {
                                  await workspaceManager
                                      .requestCloseWorkspaceById(
                                    placements[index].workspace.id,
                                  );
                                }
                              : null,
                        ),
                      ),
                    if (_draggingWorkspaceId != null) ...[
                      for (final placement in dropPlacements)
                        Positioned(
                          left: placement.left,
                          top: 0,
                          width: placement.width,
                          height: 40,
                          child: _WorkspaceTabDropTarget(
                            workspaceId: placement.workspace.id,
                            targetIndex: placement.targetIndex,
                            draggingWorkspaceId: _draggingWorkspaceId,
                            onHoverIndex: _hoverIndex,
                            onAccept: (workspaceId, targetIndex) {
                              workspaceManager.moveWorkspaceToIndex(
                                workspaceId,
                                targetIndex,
                              );
                              _finishDrag();
                            },
                            child: const SizedBox.expand(),
                          ),
                        ),
                      Positioned(
                        left: stripWidth - _trailingDropWidth,
                        top: 0,
                        width: _trailingDropWidth,
                        height: 40,
                        child: _WorkspaceTabDropTarget(
                          targetIndex: workspaceManager.workspaces.length,
                          draggingWorkspaceId: _draggingWorkspaceId,
                          onHoverIndex: _hoverIndex,
                          onAccept: (workspaceId, targetIndex) {
                            workspaceManager.moveWorkspaceToIndex(
                              workspaceId,
                              targetIndex,
                            );
                            _finishDrag();
                          },
                          child: _WorkspaceDropSlot(
                            isActive: _draggingWorkspaceId != null &&
                                _hoveringWorkspaceIndex ==
                                    workspaceManager.workspaces.length,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // `A-02` sobre shell: los iconos son la unidad, no una píldora que
          // los encierra. La píldora exterior con borde + la píldora interior
          // de navegación daban dos marcos anidados y tres alturas distintas
          // (32 / 28 / 26) en 20 px de ancho: eso es lo que se veía comprimido
          // y superpuesto. Ahora es UNA fila de controles de 32 con un solo
          // separador donde cambia el significado.
          Container(
            key: const ValueKey('workspace-chrome-actions'),
            height: _chromeGroupHeight,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              // UN marco, no dos. Lo que se veía comprimido eran dos píldoras
              // anidadas —ésta y la de navegación— con tres alturas distintas
              // (32 / 28 / 26) en unos pocos píxeles. El grupo conserva su
              // marco, que es lo que lo separa de las pestañas; lo que se
              // retiró es el marco interior.
              color: chrome.raised.withValues(alpha: 0.48),
              border: Border.all(color: chrome.edge),
              borderRadius: BorderRadius.circular(8),
            ),
            // El margen vertical se calcula, no se elige: la barra mide
            // `workspaceBarHeight` menos 1 px de hairline inferior, y la caja
            // `A-02` de 32 tiene que caber ENTERA. Con `4` fijo quedaban 31 y
            // el control se recortaba un píxel — que es parte de por qué el
            // grupo se veía comprimido.
            margin: const EdgeInsets.fromLTRB(
                6, _chromeGroupInset, 8, _chromeGroupInset),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _WorkspaceNavigationControls(),
                _ChromeSeparator(color: chrome.edge),
                const ShareWorkspaceLinkButton(),
                const SmartScreenshotButton(),
                if (workspaceManager.workspaces.length <
                    WorkspaceManager.maxWorkspaces)
                  const _NewTabDropdown(),
                const QuickUiSettingsButton(),
                Padding(
                  padding: const EdgeInsets.only(left: 3, right: 7),
                  child: Text(
                    '${workspaceManager.workspaces.length}/${WorkspaceManager.maxWorkspaces}',
                    style: TextStyle(
                      fontSize: 10,
                      height: 1,
                      color: chrome.mutedForeground,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opt-in 44px module command surface.
///
/// A module that wants the navy block to extend below the global tab strip
/// renders this at the very top of its body: same navy, and the strip's 1px
/// bottom border becomes the block's internal hairline. Modules that keep
/// their own headers simply don't render it — it is never universal chrome,
/// and a module using it must not paint a second navy header below.
class ModuleCommandBar extends StatelessWidget {
  const ModuleCommandBar({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  /// Height of the command surface.
  static const double height = 44;

  final String title;
  final String? subtitle;

  /// Optional module-owned command cluster, rendered on the right.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;

    return Semantics(
      container: true,
      header: true,
      label: 'Módulo $title',
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: chrome.canvas,
          border: Border(
            bottom: BorderSide(color: chrome.edge, width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: chrome.foreground,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (subtitle?.trim().isNotEmpty == true) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        subtitle!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: chrome.mutedForeground,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTab extends StatefulWidget {
  final int index;
  final Workspace workspace;
  final bool isActive;
  final bool isDragging;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final VoidCallback? onClose;

  const _WorkspaceTab({
    super.key,
    required this.index,
    required this.workspace,
    required this.isActive,
    required this.isDragging,
    required this.onTap,
    required this.onTogglePin,
    required this.onDragStarted,
    required this.onDragEnded,
    this.onClose,
  });

  @override
  State<_WorkspaceTab> createState() => _WorkspaceTabState();
}

class _WorkspaceTabState extends State<_WorkspaceTab> {
  bool _isHovered = false;
  bool _isFocused = false;
  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'workspace-tab-${widget.workspace.id}',
  );

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;
    final theme = Theme.of(context);
    final active = widget.isActive;
    final showTabTools = _isHovered || _isFocused || active;
    final showPinControl = showTabTools || widget.workspace.isPinned;
    final pinColor =
        widget.workspace.isPinned ? chrome.accent : chrome.mutedForeground;
    final tabWidth = widget.workspace.isPinned
        ? _WorkspaceTabBarState._pinnedTabWidth
        : _WorkspaceTabBarState._regularTabWidth;

    return Semantics(
      button: true,
      selected: active,
      label: 'Espacio de trabajo ${widget.workspace.title}',
      hint: 'Presiona Enter para abrir',
      child: InkWell(
        key: ValueKey<String>(
          'workspace-tab-control-${widget.workspace.id}',
        ),
        focusNode: _focusNode,
        canRequestFocus: !widget.isDragging,
        mouseCursor: SystemMouseCursors.click,
        onTap: widget.onTap,
        onHover: (hovered) => setState(() => _isHovered = hovered),
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: widget.isDragging ? 0.58 : 1,
          child: SizedBox(
            width: tabWidth,
            height: WorkspaceShellScope.workspaceBarHeight,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: active ? 32 : 30,
                width: tabWidth - 2,
                margin: const EdgeInsets.only(right: 2),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: active
                    ? BoxDecoration(
                        color: chrome.raised,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: _isFocused ? chrome.accent : chrome.edge,
                          ),
                          left: BorderSide(
                            color: _isFocused ? chrome.accent : chrome.edge,
                          ),
                          right: BorderSide(
                            color: _isFocused ? chrome.accent : chrome.edge,
                          ),
                        ),
                      )
                    : BoxDecoration(
                        color: _isFocused
                            ? chrome.accent.withValues(alpha: 0.12)
                            : _isHovered
                                ? chrome.raised.withValues(alpha: 0.58)
                                : Colors.transparent,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                        border: _isFocused
                            ? Border.all(color: chrome.accent)
                            : null,
                      ),
                child: Row(
                  children: [
                    if (active) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: chrome.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (showTabTools)
                      Draggable<String>(
                        data: widget.workspace.id,
                        onDragStarted: widget.onDragStarted,
                        onDragEnd: (_) => widget.onDragEnded(),
                        feedback: _WorkspaceDragPreview(
                          title: widget.workspace.title,
                          isPinned: widget.workspace.isPinned,
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.35,
                          child: _WorkspaceDragHandle(color: pinColor),
                        ),
                        child: Tooltip(
                          message: 'Arrastrar ${widget.workspace.title}',
                          child: _WorkspaceDragHandle(
                            color: chrome.mutedForeground,
                          ),
                        ),
                      ),
                    if (showPinControl)
                      Tooltip(
                        message: widget.workspace.isPinned
                            ? 'Desfijar ${widget.workspace.title}'
                            : 'Fijar ${widget.workspace.title}',
                        child: Semantics(
                          key: ValueKey<String>(
                            'workspace-tab-pin-${widget.workspace.id}',
                          ),
                          button: true,
                          label: widget.workspace.isPinned
                              ? 'Desfijar ${widget.workspace.title}'
                              : 'Fijar ${widget.workspace.title}',
                          child: InkWell(
                            onTap: widget.onTogglePin,
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: Icon(
                                widget.workspace.isPinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 11,
                                color: pinColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        widget.workspace.title,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 11.5,
                          height: 1.2,
                          color: active
                              ? chrome.foreground
                              : chrome.mutedForeground,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (widget.onClose != null && showTabTools)
                      Tooltip(
                        message: 'Cerrar ${widget.workspace.title}',
                        child: Semantics(
                          key: ValueKey<String>(
                            'workspace-tab-close-${widget.workspace.id}',
                          ),
                          button: true,
                          label: 'Cerrar ${widget.workspace.title}',
                          child: InkWell(
                            onTap: widget.onClose,
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: chrome.mutedForeground,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceTabDropTarget extends StatefulWidget {
  final String? workspaceId;
  final int targetIndex;
  final String? draggingWorkspaceId;
  final ValueChanged<int> onHoverIndex;
  final void Function(String workspaceId, int targetIndex) onAccept;
  final Widget child;

  const _WorkspaceTabDropTarget({
    this.workspaceId,
    required this.targetIndex,
    required this.draggingWorkspaceId,
    required this.onHoverIndex,
    required this.onAccept,
    required this.child,
  });

  @override
  State<_WorkspaceTabDropTarget> createState() =>
      _WorkspaceTabDropTargetState();
}

class _WorkspaceTabDropTargetState extends State<_WorkspaceTabDropTarget> {
  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => widget.draggingWorkspaceId != null,
      onMove: (details) {
        final zone = _hoverZone(context, details);
        final targetIndex = _targetIndexFor(details.data, zone);
        if (targetIndex != null) {
          widget.onHoverIndex(targetIndex);
        }
      },
      onAcceptWithDetails: (details) {
        final zone = _hoverZone(context, details);
        widget.onAccept(
          details.data,
          _targetIndexFor(details.data, zone) ?? widget.targetIndex,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final chrome = WorkspaceChromeStyle.maybeOf(context) ??
            WorkspaceChromeStyleData.vinabike;
        final isHovered = candidateData.any((id) => id != widget.workspaceId);
        return Stack(
          children: [
            widget.child,
            Positioned(
              left: 0,
              top: 8,
              bottom: 8,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: isHovered ? 2 : 0,
                decoration: BoxDecoration(
                  color: chrome.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _hoverZone(
    BuildContext context,
    DragTargetDetails<String> details,
  ) {
    if (widget.workspaceId == null) return 'trailing';

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return 'unknown';

    final localPosition = renderObject.globalToLocal(details.offset);
    final width = renderObject.size.width;
    if (width <= 0) return 'unknown';

    final hoverRatio = localPosition.dx / width;
    if (details.data == widget.workspaceId) {
      return hoverRatio < 0.5 ? 'self-left' : 'self-right';
    }

    const edgeDeadZone = 0.22;
    if (hoverRatio < edgeDeadZone) return 'left-edge';
    if (hoverRatio > 1 - edgeDeadZone) return 'right-edge';
    return 'middle';
  }

  int? _targetIndexFor(String draggedWorkspaceId, String zone) {
    if (zone == 'unknown') return null;
    if (widget.workspaceId == null) return widget.targetIndex;
    if (draggedWorkspaceId != widget.workspaceId) return widget.targetIndex;

    if (zone == 'self-left') {
      return widget.targetIndex;
    }
    if (zone == 'self-right') {
      return widget.targetIndex + 1;
    }
    return null;
  }
}

class _WorkspaceDropSlot extends StatelessWidget {
  final bool isActive;

  const _WorkspaceDropSlot({
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;
    return SizedBox(
      width: 24,
      height: 40,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: isActive ? 2 : 0,
          height: 24,
          decoration: BoxDecoration(
            color: chrome.accent,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceTabPlacement {
  final Workspace workspace;
  final double left;
  final double width;

  const _WorkspaceTabPlacement({
    required this.workspace,
    required this.left,
    required this.width,
  });
}

class _WorkspaceDropPlacement {
  final Workspace workspace;
  final int targetIndex;
  final double left;
  final double width;

  const _WorkspaceDropPlacement({
    required this.workspace,
    required this.targetIndex,
    required this.left,
    required this.width,
  });
}

class _WorkspaceDragHandle extends StatelessWidget {
  final Color color;

  const _WorkspaceDragHandle({
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Icon(
        Icons.drag_indicator,
        size: 14,
        color: color,
      ),
    );
  }
}

class _WorkspaceDragPreview extends StatelessWidget {
  final String title;
  final bool isPinned;

  const _WorkspaceDragPreview({
    required this.title,
    required this.isPinned,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 170,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.primary),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isPinned ? Icons.push_pin : Icons.tab_outlined,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceNavigationControls extends StatelessWidget {
  const _WorkspaceNavigationControls();

  @override
  Widget build(BuildContext context) {
    final workspaceManager = context.watch<WorkspaceManager>();
    final workspace = workspaceManager.activeWorkspace;
    // Atrás y adelante son la MISMA clase de control que el resto del grupo:
    // `A-02` sobre shell. Encerrarlos en su propia píldora los hacía parecer
    // otra cosa y obligaba a encogerlos para que cupieran.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VbShellIconButton(
          buttonKey: const ValueKey<String>('workspace-nav-back'),
          icon: Icons.arrow_back,
          tooltip: 'Atrás',
          onPressed: (workspace?.canGoBack ?? false)
              ? workspaceManager.navigateActiveWorkspaceBack
              : null,
        ),
        VbShellIconButton(
          buttonKey: const ValueKey<String>('workspace-nav-forward'),
          icon: Icons.arrow_forward,
          tooltip: 'Adelante',
          onPressed: (workspace?.canGoForward ?? false)
              ? workspaceManager.navigateActiveWorkspaceForward
              : null,
        ),
      ],
    );
  }
}

/// Aire vertical del grupo, **derivado y no elegido**.
///
/// La barra útil mide `workspaceBarHeight` menos 1 px de hairline inferior; el
/// grupo suma 1 px de marco arriba y otro abajo; y la caja `A-02` de 32 tiene
/// que caber ENTERA. Con el `4` fijo anterior quedaban 30 px para una caja de
/// 32: el control se recortaba dos píxeles, y eso es parte de lo que se veía
/// comprimido.
const double _chromeGroupHeight = VbShellIconButton.box + 2;
const double _chromeGroupInset =
    ((WorkspaceShellScope.workspaceBarHeight - 1) - _chromeGroupHeight) / 2;

class _NewTabDropdown extends StatefulWidget {
  const _NewTabDropdown();

  @override
  State<_NewTabDropdown> createState() => _NewTabDropdownState();
}

@immutable
class _NewWorkspaceOption {
  const _NewWorkspaceOption(this.icon, this.title, this.route);
  final IconData icon;
  final String title;
  final String route;
}

class _NewTabDropdownState extends State<_NewTabDropdown> {
  final GlobalKey _anchor = GlobalKey();

  static const List<_NewWorkspaceOption> _options = <_NewWorkspaceOption>[
    _NewWorkspaceOption(Icons.dashboard, 'Dashboard', '/dashboard'),
    _NewWorkspaceOption(
      Icons.language,
      'Navegador web',
      '/tools/web?url=https%3A%2F%2Fwww.google.com&name=Navegador%20web',
    ),
    _NewWorkspaceOption(Icons.shopping_bag, 'Productos', '/inventory/products'),
    _NewWorkspaceOption(Icons.receipt, 'Ventas', '/sales/invoices'),
    _NewWorkspaceOption(Icons.people, 'Clientes', '/clientes'),
    _NewWorkspaceOption(
      Icons.shopping_cart,
      'Compras',
      '/purchases/suppliers',
    ),
    _NewWorkspaceOption(Icons.point_of_sale, 'POS', '/pos'),
    _NewWorkspaceOption(Icons.build, 'Taller', '/taller/pegas'),
    _NewWorkspaceOption(
      Icons.account_balance,
      'Contabilidad',
      '/accounting/accounts',
    ),
  ];

  Future<void> _open() async {
    final chosen = await showVbAnchoredPopover<_NewWorkspaceOption>(
      anchorContext: _anchor.currentContext ?? context,
      minWidth: 208,
      barrierLabel: 'Cerrar el menú de espacios de trabajo',
      builder: (context) => const _NewWorkspaceMenu(options: _options),
    );
    if (chosen == null || !mounted) return;
    context.read<WorkspaceManager>().addWorkspace(
          title: chosen.title,
          initialRoute: chosen.route,
        );
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _anchor,
      child: VbShellIconButton(
        buttonKey: const ValueKey<String>('workspace-new-tab'),
        icon: Icons.add,
        tooltip: 'Nuevo espacio de trabajo',
        onPressed: _open,
      ),
    );
  }
}

class _NewWorkspaceMenu extends StatelessWidget {
  const _NewWorkspaceMenu({required this.options});

  final List<_NewWorkspaceOption> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // This is a nine-command menu, NOT the seven-option `S-05` short select.
    // Position and surface both come from the exclusive `O-02` owner; this
    // widget supplies only bounded, scroll-safe command content.
    return VbPopoverSurface(
      width: 248,
      child: SingleChildScrollView(
        primary: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final option in options)
              Semantics(
                button: true,
                label: 'Abrir ${option.title} en un espacio nuevo',
                excludeSemantics: true,
                child: InkWell(
                  key: ValueKey<String>('workspace-new-${option.route}'),
                  onTap: () => Navigator.of(context).pop(option),
                  child: SizedBox(
                    height: 30,
                    child: Row(
                      children: <Widget>[
                        const SizedBox(width: 11),
                        Icon(option.icon, size: 16),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            option.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 11),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Separador de 1 px entre dos significados distintos del grupo. `F-04` lo
/// resuelve con el rol `border` del shell; no lleva color propio.
class _ChromeSeparator extends StatelessWidget {
  const _ChromeSeparator({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 16,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: color,
      );
}
