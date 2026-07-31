import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
          Container(
            key: const ValueKey('workspace-chrome-actions'),
            height: 32,
            margin: const EdgeInsets.fromLTRB(6, 4, 8, 4),
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: chrome.raised.withValues(alpha: 0.48),
              border: Border.all(color: chrome.edge),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _WorkspaceNavigationControls(),
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
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;

    return Container(
      height: 28,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        border: Border.all(color: chrome.edge),
        borderRadius: BorderRadius.circular(7),
        color: chrome.canvas.withValues(alpha: 0.28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WorkspaceNavButton(
            icon: Icons.arrow_back,
            tooltip: 'Atrás',
            enabled: workspace?.canGoBack ?? false,
            onPressed: workspaceManager.navigateActiveWorkspaceBack,
          ),
          Container(
            width: 1,
            height: 16,
            color: chrome.edge,
          ),
          _WorkspaceNavButton(
            icon: Icons.arrow_forward,
            tooltip: 'Adelante',
            enabled: workspace?.canGoForward ?? false,
            onPressed: workspaceManager.navigateActiveWorkspaceForward,
          ),
        ],
      ),
    );
  }
}

class _WorkspaceNavButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  const _WorkspaceNavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        mouseCursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: 30,
          height: 26,
          child: Icon(
            icon,
            size: 15,
            color: enabled
                ? chrome.foreground
                : chrome.mutedForeground.withValues(alpha: 0.42),
          ),
        ),
      ),
    );
  }
}

class _NewTabDropdown extends StatefulWidget {
  const _NewTabDropdown();

  @override
  State<_NewTabDropdown> createState() => _NewTabDropdownState();
}

class _NewTabDropdownState extends State<_NewTabDropdown> {
  // Use GlobalKey to keep the popup menu button stable across rebuilds
  final GlobalKey _menuKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;

    return PopupMenuButton<Map<String, String>>(
      key: _menuKey,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      icon: Icon(
        Icons.add,
        size: 18,
        color: chrome.foreground,
      ),
      tooltip: 'Nuevo espacio de trabajo',
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: {'title': 'Dashboard', 'route': '/dashboard'},
          child: Row(
            children: [
              Icon(Icons.dashboard, size: 18),
              SizedBox(width: 12),
              Text('Dashboard'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: {
            'title': 'Navegador web',
            'route':
                '/tools/web?url=https%3A%2F%2Fwww.google.com&name=Navegador%20web',
          },
          child: Row(
            children: [
              Icon(Icons.language, size: 18),
              SizedBox(width: 12),
              Text('Navegador web'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: {'title': 'Productos', 'route': '/inventory/products'},
          child: Row(
            children: [
              Icon(Icons.shopping_bag, size: 18),
              SizedBox(width: 12),
              Text('Productos'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: {'title': 'Ventas', 'route': '/sales/invoices'},
          child: Row(
            children: [
              Icon(Icons.receipt, size: 18),
              SizedBox(width: 12),
              Text('Ventas'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: {'title': 'Clientes', 'route': '/clientes'},
          child: Row(
            children: [
              Icon(Icons.people, size: 18),
              SizedBox(width: 12),
              Text('Clientes'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: {'title': 'Compras', 'route': '/purchases/suppliers'},
          child: Row(
            children: [
              Icon(Icons.shopping_cart, size: 18),
              SizedBox(width: 12),
              Text('Compras'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: {'title': 'POS', 'route': '/pos'},
          child: Row(
            children: [
              Icon(Icons.point_of_sale, size: 18),
              SizedBox(width: 12),
              Text('POS'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: {'title': 'Taller', 'route': '/taller/pegas'},
          child: Row(
            children: [
              Icon(Icons.build, size: 18),
              SizedBox(width: 12),
              Text('Taller'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: {'title': 'Contabilidad', 'route': '/accounting/accounts'},
          child: Row(
            children: [
              Icon(Icons.account_balance, size: 18),
              SizedBox(width: 12),
              Text('Contabilidad'),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        // Use read() instead of requiring a watch dependency
        final workspaceManager = context.read<WorkspaceManager>();
        workspaceManager.addWorkspace(
          title: value['title']!,
          initialRoute: value['route']!,
        );
      },
    );
  }
}
