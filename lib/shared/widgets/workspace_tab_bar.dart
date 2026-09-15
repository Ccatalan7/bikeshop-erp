import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'browser_workspace_favicon.dart';
import 'vb_anchored_popover.dart';
import 'vb_shell_icon_button.dart';

import '../services/workspace_launch_options.dart';
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

class _WorkspaceTabBarState extends State<WorkspaceTabBar>
    with WidgetsBindingObserver {
  String? _draggingWorkspaceId;
  int? _hoveringWorkspaceIndex;
  final GlobalKey _browserStackTrigger = GlobalKey();
  final GlobalKey _browserStackAnchor = GlobalKey();
  final GlobalKey _browserStackMenu = GlobalKey();
  bool _browserStackPopoverOpen = false;
  bool _browserStackPopoverLocked = false;
  Timer? _browserStackHoverOpenTimer;
  Timer? _browserStackHoverCloseTimer;

  static const double _regularTabWidth = 152;
  static const double _pinnedTabWidth = 144;
  static const double _trailingDropWidth = 24;

  NavigatorState? _browserStackNavigator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
  }

  @override
  void dispose() {
    _browserStackHoverOpenTimer?.cancel();
    _browserStackHoverCloseTimer?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _browserStackHoverOpenTimer?.cancel();
    if (!_browserStackPopoverOpen) return;
    final navigator = _browserStackNavigator;
    if (navigator != null && navigator.mounted) {
      navigator.maybePop();
    }
  }

  Rect? _globalRectFor(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (!_browserStackPopoverOpen ||
        _browserStackPopoverLocked ||
        event is! PointerHoverEvent && event is! PointerMoveEvent) {
      return;
    }

    final triggerRect = _globalRectFor(_browserStackTrigger);
    final menuRect = _globalRectFor(_browserStackMenu);
    if (triggerRect == null || menuRect == null) return;

    // The extension overlaps the shell hairline, so these two real painted
    // rectangles touch. No invisible hover corridor extends beside the menu.
    if (triggerRect.contains(event.position) ||
        menuRect.contains(event.position)) {
      _browserStackHoverCloseTimer?.cancel();
      _browserStackHoverCloseTimer = null;
      return;
    }
    _scheduleBrowserStackHoverClose();
  }

  void _handleBrowserStackHover(
    bool hovered,
    List<Workspace> workspaces,
    WorkspaceChromeStyleData chrome,
  ) {
    if (!hovered) {
      if (!_browserStackPopoverOpen) {
        _browserStackHoverOpenTimer?.cancel();
        _browserStackHoverOpenTimer = null;
      }
      return;
    }

    _browserStackHoverCloseTimer?.cancel();
    _browserStackHoverCloseTimer = null;
    if (_browserStackPopoverOpen || _browserStackHoverOpenTimer != null) {
      return;
    }
    // F-05 gives O-02 a 200 ms base motion budget. Reusing that same beat as
    // hover intent prevents accidental fly-outs while preserving immediacy.
    _browserStackHoverOpenTimer = Timer(
      const Duration(milliseconds: 200),
      () {
        _browserStackHoverOpenTimer = null;
        if (mounted) {
          _openBrowserStack(
            workspaces,
            locked: false,
            chrome: chrome,
          );
        }
      },
    );
  }

  void _scheduleBrowserStackHoverClose() {
    if (_browserStackHoverCloseTimer != null) return;
    _browserStackHoverCloseTimer = Timer(
      const Duration(milliseconds: 120),
      () {
        _browserStackHoverCloseTimer = null;
        if (_browserStackPopoverOpen && !_browserStackPopoverLocked) {
          final navigator = _browserStackNavigator;
          if (navigator != null && navigator.mounted) {
            navigator.maybePop();
          }
        }
      },
    );
  }

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

  double _tabWidthFor(_WorkspaceStripItem item) => item.isBrowserStack
      ? _regularTabWidth
      : item.workspace!.isPinned
          ? _pinnedTabWidth
          : _regularTabWidth;

  List<_WorkspaceStripItem> _stripItemsFor(List<Workspace> workspaces) {
    final browserStack = workspaces
        .where(
          (workspace) => workspace.isBrowserWorkspace && !workspace.isPinned,
        )
        .toList(growable: false);
    if (browserStack.length < 2) {
      return workspaces
          .map(_WorkspaceStripItem.workspace)
          .toList(growable: false);
    }

    final browserIds = browserStack.map((workspace) => workspace.id).toSet();
    var insertedStack = false;
    final items = <_WorkspaceStripItem>[];
    for (final workspace in workspaces) {
      if (!browserIds.contains(workspace.id)) {
        items.add(_WorkspaceStripItem.workspace(workspace));
        continue;
      }
      if (!insertedStack) {
        items.add(_WorkspaceStripItem.browserStack(browserStack));
        insertedStack = true;
      }
    }
    return items;
  }

  List<_WorkspaceTabPlacement> _placementsFor(
    List<_WorkspaceStripItem> items,
  ) {
    var left = 0.0;
    return items.map((item) {
      final width = _tabWidthFor(item);
      final placement = _WorkspaceTabPlacement(
        item: item,
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
    final items = _stripItemsFor(workspaces);
    return items.map((item) {
      final firstWorkspace = item.workspaces.first;
      final width = _tabWidthFor(item);
      final placement = _WorkspaceDropPlacement(
        itemId: item.id,
        targetIndex: workspaces.indexWhere(
          (workspace) => workspace.id == firstWorkspace.id,
        ),
        left: left,
        width: width,
      );
      left += width;
      return placement;
    }).toList();
  }

  Future<void> _openBrowserStack(
    List<Workspace> workspaces, {
    required bool locked,
    required WorkspaceChromeStyleData chrome,
  }) async {
    _browserStackHoverOpenTimer?.cancel();
    _browserStackHoverOpenTimer = null;
    if (_browserStackPopoverOpen) {
      _browserStackPopoverLocked = _browserStackPopoverLocked || locked;
      return;
    }
    if (workspaces.length < 2) return;

    _browserStackNavigator = Navigator.of(context, rootNavigator: true);
    _browserStackPopoverLocked = locked;
    setState(() => _browserStackPopoverOpen = true);
    final selectedWorkspaceId = await showVbAnchoredPopover<String>(
      anchorContext: _browserStackAnchor.currentContext ?? context,
      // The visible tab is two pixels narrower than its reorder slot. The
      // extension anchors to that painted surface and preserves its width.
      minWidth: _regularTabWidth - 2,
      // Overlap the strip's one-pixel bottom hairline so tab and extension
      // read as one continuous control rather than two adjacent surfaces.
      gap: -1,
      barrierLabel: 'Cerrar la lista de pestañas web',
      contentTransitionBuilder: _browserStackExtensionTransition,
      builder: (context) => _BrowserWorkspaceStackMenu(
        key: _browserStackMenu,
        workspaces: List<Workspace>.unmodifiable(workspaces),
        activeWorkspaceId: context.read<WorkspaceManager>().activeWorkspace?.id,
        chrome: chrome,
      ),
    );
    if (!mounted) return;
    _browserStackHoverCloseTimer?.cancel();
    _browserStackHoverCloseTimer = null;
    _browserStackNavigator = null;
    _browserStackPopoverLocked = false;
    setState(() => _browserStackPopoverOpen = false);
    if (selectedWorkspaceId != null) {
      context
          .read<WorkspaceManager>()
          .switchToWorkspaceById(selectedWorkspaceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workspaceManager = context.watch<WorkspaceManager>();
    final chrome = WorkspaceChromeStyle.maybeOf(context) ??
        WorkspaceChromeStyleData.vinabike;
    final displayedWorkspaces =
        _displayedWorkspaces(workspaceManager.workspaces);
    final placements = _placementsFor(_stripItemsFor(displayedWorkspaces));
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
                          'workspace-tab-position-${placements[index].item.id}',
                        ),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        left: placements[index].left,
                        top: 0,
                        width: placements[index].width,
                        height: 40,
                        child: placements[index].item.isBrowserStack
                            ? KeyedSubtree(
                                key: _browserStackTrigger,
                                child: _BrowserWorkspaceStackTab(
                                  anchorKey: _browserStackAnchor,
                                  workspaces: placements[index].item.workspaces,
                                  activeWorkspaceId:
                                      workspaceManager.activeWorkspace?.id,
                                  isOpen: _browserStackPopoverOpen,
                                  onOpen: () => _openBrowserStack(
                                    placements[index].item.workspaces,
                                    locked: true,
                                    chrome: chrome,
                                  ),
                                  onHoverChanged: (hovered) =>
                                      _handleBrowserStackHover(
                                    hovered,
                                    placements[index].item.workspaces,
                                    chrome,
                                  ),
                                ),
                              )
                            : _WorkspaceTab(
                                key: ValueKey(
                                  'workspace-tab-${placements[index].item.workspace!.id}',
                                ),
                                index: index,
                                workspace: placements[index].item.workspace!,
                                isActive:
                                    placements[index].item.workspace!.id ==
                                        workspaceManager.activeWorkspace?.id,
                                isDragging:
                                    placements[index].item.workspace!.id ==
                                        _draggingWorkspaceId,
                                onTap: () {
                                  workspaceManager.switchToWorkspaceById(
                                    placements[index].item.workspace!.id,
                                  );
                                },
                                onTogglePin: () =>
                                    workspaceManager.toggleWorkspacePinned(
                                  workspaceManager.workspaces.indexWhere(
                                    (workspace) =>
                                        workspace.id ==
                                        placements[index].item.workspace!.id,
                                  ),
                                ),
                                onDragStarted: () => _startDrag(
                                  placements[index].item.workspace!.id,
                                ),
                                onDragEnded: _finishDrag,
                                onClose: workspaceManager.workspaces.length > 1
                                    ? () async {
                                        await workspaceManager
                                            .requestCloseWorkspaceById(
                                          placements[index].item.workspace!.id,
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
                            workspaceId: placement.itemId,
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

class _BrowserWorkspaceStackTab extends StatefulWidget {
  const _BrowserWorkspaceStackTab({
    required this.anchorKey,
    required this.workspaces,
    required this.activeWorkspaceId,
    required this.isOpen,
    required this.onOpen,
    required this.onHoverChanged,
  });

  final GlobalKey anchorKey;
  final List<Workspace> workspaces;
  final String? activeWorkspaceId;
  final bool isOpen;
  final VoidCallback onOpen;
  final ValueChanged<bool> onHoverChanged;

  @override
  State<_BrowserWorkspaceStackTab> createState() =>
      _BrowserWorkspaceStackTabState();
}

class _BrowserWorkspaceStackTabState extends State<_BrowserWorkspaceStackTab> {
  bool _isHovered = false;
  bool _isFocused = false;
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'workspace-browser-stack-tab',
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
    final activeWorkspaceIndex = widget.workspaces.indexWhere(
      (workspace) => workspace.id == widget.activeWorkspaceId,
    );
    final activeWorkspace = activeWorkspaceIndex < 0
        ? null
        : widget.workspaces[activeWorkspaceIndex];
    final active = activeWorkspace != null;
    final extended = active || widget.isOpen;
    final title = activeWorkspace?.title ?? 'Pestañas web';
    const tabWidth = _WorkspaceTabBarState._regularTabWidth;

    return Semantics(
      button: true,
      selected: active,
      expanded: widget.isOpen,
      label: 'Pestañas web, ${widget.workspaces.length} abiertas',
      hint: 'Presiona Enter para elegir una pestaña web',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey<String>('workspace-browser-stack-tab'),
        focusNode: _focusNode,
        mouseCursor: SystemMouseCursors.click,
        onTap: widget.onOpen,
        onHover: (hovered) {
          setState(() => _isHovered = hovered);
          widget.onHoverChanged(hovered);
        },
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        child: SizedBox(
          width: tabWidth,
          height: WorkspaceShellScope.workspaceBarHeight,
          child: Align(
            alignment: Alignment.bottomLeft,
            // Anchor the route to the painted tab's outer rectangle, not to
            // AnimatedContainer's decorated child. A Border contributes its
            // own padding, which otherwise shifts the overlay one pixel and
            // makes the extension read as a detached menu.
            child: SizedBox(
              key: widget.anchorKey,
              width: tabWidth - 2,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                height: extended ? 32 : 30,
                width: tabWidth - 2,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: extended
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
                            : _isHovered || widget.isOpen
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
                    BrowserWorkspaceFavicon(
                      key: const ValueKey<String>(
                        'workspace-browser-stack-active-favicon',
                      ),
                      faviconUrl: activeWorkspace?.browserFaviconUrl,
                      size: 14,
                      fallbackColor:
                          extended ? chrome.foreground : chrome.mutedForeground,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$title · ${widget.workspaces.length}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 11.5,
                          height: 1.2,
                          color: extended
                              ? chrome.foreground
                              : chrome.mutedForeground,
                          fontWeight:
                              extended ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: widget.isOpen ? 0.5 : 0,
                      duration: const Duration(milliseconds: 120),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 16,
                        color: extended
                            ? chrome.foreground
                            : chrome.mutedForeground,
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

class _BrowserWorkspaceStackMenu extends StatefulWidget {
  const _BrowserWorkspaceStackMenu({
    super.key,
    required this.workspaces,
    required this.activeWorkspaceId,
    required this.chrome,
  });

  final List<Workspace> workspaces;
  final String? activeWorkspaceId;
  final WorkspaceChromeStyleData chrome;

  @override
  State<_BrowserWorkspaceStackMenu> createState() =>
      _BrowserWorkspaceStackMenuState();
}

class _BrowserWorkspaceStackMenuState
    extends State<_BrowserWorkspaceStackMenu> {
  late int _highlightedIndex = _initialHighlight();

  int _initialHighlight() {
    final activeIndex = widget.workspaces.indexWhere(
      (workspace) => workspace.id == widget.activeWorkspaceId,
    );
    return activeIndex < 0 ? 0 : activeIndex;
  }

  void _moveHighlight(int delta) {
    final nextIndex = (_highlightedIndex + delta)
        .clamp(0, widget.workspaces.length - 1)
        .toInt();
    if (nextIndex != _highlightedIndex) {
      setState(() => _highlightedIndex = nextIndex);
    }
  }

  void _select(Workspace workspace) {
    Navigator.of(context).pop(workspace.id);
  }

  void _togglePinned(Workspace workspace) {
    final manager = context.read<WorkspaceManager>();
    final index = manager.workspaces.indexWhere(
      (candidate) => candidate.id == workspace.id,
    );
    if (index < 0) return;
    manager.toggleWorkspacePinned(index);
    Navigator.of(context).pop();
  }

  Future<void> _close(Workspace workspace) async {
    final navigator = Navigator.of(context);
    final closed = await context
        .read<WorkspaceManager>()
        .requestCloseWorkspaceById(workspace.id);
    if (closed && navigator.mounted) {
      navigator.maybePop();
    }
  }

  String _hostFor(Workspace workspace) {
    final directUrl = workspace.browserUrl?.trim();
    final routeUrl =
        Uri.tryParse(workspace.currentRoute)?.queryParameters['url']?.trim();
    final uri = Uri.tryParse(
      directUrl?.isNotEmpty == true ? directUrl! : routeUrl ?? '',
    );
    final host = uri?.host ?? '';
    if (host.isEmpty) return 'Navegador web';
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _moveHighlight(1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          _moveHighlight(-1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          _select(widget.workspaces[_highlightedIndex]);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        key: const ValueKey<String>(
          'workspace-browser-stack-extension-surface',
        ),
        color: widget.chrome.raised,
        elevation: 0,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          key: const ValueKey<String>('workspace-browser-stack-popover'),
          width: _WorkspaceTabBarState._regularTabWidth - 2,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
            border: Border(
              left: BorderSide(color: widget.chrome.edge),
              right: BorderSide(color: widget.chrome.edge),
              bottom: BorderSide(color: widget.chrome.edge),
            ),
          ),
          child: SingleChildScrollView(
            primary: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < widget.workspaces.length; index++)
                  _BrowserWorkspaceExtensionRow(
                    key: ValueKey<String>(
                      'workspace-browser-stack-row-${widget.workspaces[index].id}',
                    ),
                    workspace: widget.workspaces[index],
                    host: _hostFor(widget.workspaces[index]),
                    chrome: widget.chrome,
                    isActive:
                        widget.workspaces[index].id == widget.activeWorkspaceId,
                    isHighlighted: index == _highlightedIndex,
                    showTopDivider: index > 0,
                    onHover: () => setState(() => _highlightedIndex = index),
                    onTap: () => _select(widget.workspaces[index]),
                    onPin: () => _togglePinned(widget.workspaces[index]),
                    onClose: () => _close(widget.workspaces[index]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BrowserWorkspaceExtensionRow extends StatefulWidget {
  const _BrowserWorkspaceExtensionRow({
    super.key,
    required this.workspace,
    required this.host,
    required this.chrome,
    required this.isActive,
    required this.isHighlighted,
    required this.showTopDivider,
    required this.onHover,
    required this.onTap,
    required this.onPin,
    required this.onClose,
  });

  final Workspace workspace;
  final String host;
  final WorkspaceChromeStyleData chrome;
  final bool isActive;
  final bool isHighlighted;
  final bool showTopDivider;
  final VoidCallback onHover;
  final VoidCallback onTap;
  final VoidCallback onPin;
  final VoidCallback onClose;

  @override
  State<_BrowserWorkspaceExtensionRow> createState() =>
      _BrowserWorkspaceExtensionRowState();
}

class _BrowserWorkspaceExtensionRowState
    extends State<_BrowserWorkspaceExtensionRow> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showActions = _isHovered || _isFocused || widget.isHighlighted;
    return Semantics(
      container: true,
      button: true,
      selected: widget.isActive,
      label:
          'Pestaña web ${widget.workspace.title}, ${widget.host}${widget.isActive ? ', activa' : ''}',
      child: InkWell(
        key: ValueKey<String>(
          'workspace-browser-stack-item-${widget.workspace.id}',
        ),
        onTap: widget.onTap,
        onHover: (hovered) {
          setState(() => _isHovered = hovered);
          if (hovered) widget.onHover();
        },
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: WorkspaceShellScope.workspaceBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.isHighlighted
                ? widget.chrome.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            border: widget.showTopDivider
                ? Border(top: BorderSide(color: widget.chrome.edge))
                : null,
          ),
          child: Row(
            children: [
              BrowserWorkspaceFavicon(
                key: ValueKey<String>(
                  'workspace-browser-stack-favicon-${widget.workspace.id}',
                ),
                faviconUrl: widget.workspace.browserFaviconUrl,
                size: 14,
                fallbackColor: widget.isActive
                    ? widget.chrome.accent
                    : widget.chrome.mutedForeground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Tooltip(
                  message: '${widget.workspace.title}\n${widget.host}',
                  child: Text(
                    widget.workspace.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontSize: 11.5,
                      height: 1.2,
                      color: widget.chrome.foreground,
                      fontWeight: widget.isHighlighted
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
              if (showActions) ...[
                _BrowserWorkspaceExtensionAction(
                  actionKey: ValueKey<String>(
                    'workspace-browser-stack-pin-${widget.workspace.id}',
                  ),
                  icon: Icons.push_pin_outlined,
                  label: 'Fijar ${widget.workspace.title}',
                  color: widget.chrome.mutedForeground,
                  onTap: widget.onPin,
                ),
                _BrowserWorkspaceExtensionAction(
                  actionKey: ValueKey<String>(
                    'workspace-browser-stack-close-${widget.workspace.id}',
                  ),
                  icon: Icons.close_rounded,
                  label: 'Cerrar ${widget.workspace.title}',
                  color: widget.chrome.mutedForeground,
                  onTap: widget.onClose,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowserWorkspaceExtensionAction extends StatelessWidget {
  const _BrowserWorkspaceExtensionAction({
    required this.actionKey,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final Key actionKey;
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Semantics(
        key: actionKey,
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(icon, size: 12, color: color),
          ),
        ),
      ),
    );
  }
}

Widget _browserStackExtensionTransition(
  BuildContext context,
  Animation<double> animation,
  Widget child,
) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: const Cubic(0.22, 1, 0.36, 1),
    reverseCurve: Curves.easeOutCubic,
  );
  if (MediaQuery.disableAnimationsOf(context)) {
    return FadeTransition(opacity: curved, child: child);
  }
  return AnimatedBuilder(
    animation: curved,
    child: child,
    builder: (context, child) => ClipRect(
      child: Align(
        alignment: Alignment.topCenter,
        widthFactor: 1,
        heightFactor: curved.value,
        child: child,
      ),
    ),
  );
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
                    if (widget.workspace.isBrowserWorkspace) ...[
                      BrowserWorkspaceFavicon(
                        key: ValueKey<String>(
                          'workspace-tab-favicon-${widget.workspace.id}',
                        ),
                        faviconUrl: widget.workspace.browserFaviconUrl,
                        size: 14,
                        fallbackColor:
                            active ? chrome.foreground : chrome.mutedForeground,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Tooltip(
                        message: widget.workspace.isBrowserWorkspace
                            ? '${widget.workspace.title}\n'
                                '${widget.workspace.browserUrl ?? ''}'
                            : widget.workspace.title,
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

class _WorkspaceStripItem {
  const _WorkspaceStripItem._({
    required this.workspace,
    required this.workspaces,
  });

  _WorkspaceStripItem.workspace(Workspace workspace)
      : this._(
          workspace: workspace,
          workspaces: List<Workspace>.unmodifiable([workspace]),
        );

  _WorkspaceStripItem.browserStack(List<Workspace> workspaces)
      : this._(
          workspace: null,
          workspaces: List<Workspace>.unmodifiable(workspaces),
        );

  final Workspace? workspace;
  final List<Workspace> workspaces;

  bool get isBrowserStack => workspace == null;
  String get id => isBrowserStack ? 'browser-workspace-stack' : workspace!.id;
}

class _WorkspaceTabPlacement {
  final _WorkspaceStripItem item;
  final double left;
  final double width;

  const _WorkspaceTabPlacement({
    required this.item,
    required this.left,
    required this.width,
  });
}

class _WorkspaceDropPlacement {
  final String itemId;
  final int targetIndex;
  final double left;
  final double width;

  const _WorkspaceDropPlacement({
    required this.itemId,
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

class _NewTabDropdownState extends State<_NewTabDropdown> {
  final GlobalKey _anchor = GlobalKey();

  // El catálogo es compartido: compacto ofrece los mismos destinos en una
  // hoja inferior. Ver `workspace_launch_options.dart`.
  static const List<WorkspaceLaunchOption> _options = workspaceLaunchOptions;

  Future<void> _open() async {
    final chosen = await showVbAnchoredPopover<WorkspaceLaunchOption>(
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

  final List<WorkspaceLaunchOption> options;

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
