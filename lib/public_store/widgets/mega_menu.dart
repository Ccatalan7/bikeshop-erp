import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../modules/website/models/website_catalog_query.dart';
import '../../modules/website/models/website_page_models.dart';
import '../theme/public_store_theme.dart';

bool _isDirectCategoryDestination(String? href) {
  final uri = Uri.tryParse(href?.trim() ?? '');
  if (uri == null) return false;
  return WebsiteCatalogQuery.tryParse(uri)?.categoryScope ==
      WebsiteCatalogCategoryScope.direct;
}

// ============================================================================
// MEGA MENU STATE CONTROLLER
// Used to communicate mega menu open state to the header
// ============================================================================

/// Presentation-only projection supplied by the category presentation owner.
///
/// Navigation continues to own hierarchy and destinations. The mega menu
/// receives only the media needed to render a branch, keyed by navigation ID.
class MegaMenuBranchPresentation {
  const MegaMenuBranchPresentation({
    required this.imageUrl,
    required this.overlay,
  });

  final String imageUrl;
  final double overlay;
}

class MegaMenuController extends ChangeNotifier {
  static final MegaMenuController instance = MegaMenuController._();
  MegaMenuController._();

  bool _isAnyMenuOpen = false;
  bool get isAnyMenuOpen => _isAnyMenuOpen;

  String? _activeMenuId;
  String? get activeMenuId => _activeMenuId;

  double? _headerBottom;
  double? get headerBottom => _headerBottom;

  void reportHeaderBottom(double bottom) {
    if ((_headerBottom == null) || ((_headerBottom! - bottom).abs() > 0.5)) {
      _headerBottom = bottom;
    }
  }

  void openMenu(String menuId) {
    if (_activeMenuId != menuId || !_isAnyMenuOpen) {
      _activeMenuId = menuId;
      _isAnyMenuOpen = true;
      notifyListeners();
    }
  }

  void closeMenu() {
    if (_isAnyMenuOpen) {
      _activeMenuId = null;
      _isAnyMenuOpen = false;
      notifyListeners();
    }
  }
}

// ============================================================================
// MEGA MENU HEADER WRAPPER
// Wraps the header to provide:
// 1. The saved opaque navigation surface while the menu is open
// 2. High z-index so it sits on top of hero images
// 3. Logo color inversion when dark background is active
// ============================================================================

class MegaMenuHeaderWrapper extends StatefulWidget {
  final Widget child;
  final Color openBackgroundColor;

  const MegaMenuHeaderWrapper({
    super.key,
    required this.child,
    required this.openBackgroundColor,
  });

  @override
  State<MegaMenuHeaderWrapper> createState() => _MegaMenuHeaderWrapperState();
}

class _MegaMenuHeaderWrapperState extends State<MegaMenuHeaderWrapper> {
  @override
  void initState() {
    super.initState();
    MegaMenuController.instance.addListener(_onMenuStateChange);
    WidgetsBinding.instance.addPostFrameCallback(_reportGeometry);
  }

  @override
  void didUpdateWidget(MegaMenuHeaderWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback(_reportGeometry);
  }

  void _reportGeometry(_) {
    if (!mounted) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // Store the actual rendered bottom in global coordinates. Preview/Edit
    // can be mounted below more than one host toolbar, so a CMS-specific
    // offset cannot describe this geometry reliably.
    final bottom = renderBox.localToGlobal(Offset(0, renderBox.size.height)).dy;

    MegaMenuController.instance.reportHeaderBottom(bottom);
  }

  @override
  void dispose() {
    MegaMenuController.instance.removeListener(_onMenuStateChange);
    super.dispose();
  }

  void _onMenuStateChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = MegaMenuController.instance.isAnyMenuOpen;

    return Stack(
      children: [
        // Animated background - only this changes, NOT the child
        Positioned.fill(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            color: isOpen ? widget.openBackgroundColor : Colors.transparent,
          ),
        ),
        // Child content - always at full opacity
        widget.child,
      ],
    );
  }
}

// ============================================================================
// MEGA MENU BUTTON
//
// Refined interaction model:
// - Hover button -> Open Menu
// - Hover panel -> Keep Menu Open
// - Exit both -> Close after delay (debounce)
// - NO BLOCKING OVERLAYS over the header bar
// ============================================================================

class MegaMenuButton extends StatefulWidget {
  final WebsiteNavigation parent;
  final List<WebsiteNavigation> children;
  final bool isEditMode;
  final Color textColor;
  final Color panelBackgroundColor;
  final Color panelForegroundColor;
  final Color panelRailBackgroundColor;
  final Color panelRailForegroundColor;
  final Map<String, MegaMenuBranchPresentation> branchPresentations;
  final Function(String href, bool openInNewTab) onNavigate;

  const MegaMenuButton({
    super.key,
    required this.parent,
    required this.children,
    required this.isEditMode,
    required this.textColor,
    required this.panelBackgroundColor,
    required this.panelForegroundColor,
    required this.panelRailBackgroundColor,
    required this.panelRailForegroundColor,
    this.branchPresentations = const <String, MegaMenuBranchPresentation>{},
    required this.onNavigate,
  });

  @override
  State<MegaMenuButton> createState() => _MegaMenuButtonState();
}

class _MegaMenuButtonState extends State<MegaMenuButton> {
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  bool _isHoveringButton = false;
  bool _isHoveringPanel = false;
  bool _isFocusWithinPanel = false;
  bool _isFocused = false;
  bool _suppressFocusReopen = false;
  Timer? _openTimer;
  Timer? _closeTimer;
  final GlobalKey _buttonKey = GlobalKey();
  final GlobalKey<_MegaMenuOverlayState> _overlayKey = GlobalKey();

  String get _menuId =>
      widget.parent.id.isNotEmpty ? widget.parent.id : widget.parent.label;

  @override
  void initState() {
    super.initState();
    MegaMenuController.instance.addListener(_onControllerChange);
  }

  @override
  void dispose() {
    MegaMenuController.instance.removeListener(_onControllerChange);
    _openTimer?.cancel();
    _closeTimer?.cancel();
    _forceRemoveOverlay();
    super.dispose();
  }

  void _onControllerChange() {
    if (!mounted) return;
    final activeId = MegaMenuController.instance.activeMenuId;
    // If we are open, but the active menu is someone else -> Close immediately
    // ensuring we don't interfere with the global controller state (which is owned by the new menu)
    if (_isOpen && activeId != _menuId && activeId != null) {
      _closeTimer?.cancel();
      _forceRemoveOverlay();
      setState(() => _isOpen = false);
    }
  }

  void _forceRemoveOverlay() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  void _openMenu() {
    if (widget.isEditMode || _isOpen) return;
    _openTimer?.cancel();
    _closeTimer?.cancel();

    final overlayState = Overlay.of(context);
    final overlayRenderBox =
        overlayState.context.findRenderObject() as RenderBox?;
    final overlayGlobalOrigin =
        overlayRenderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final screenHeight = overlayRenderBox?.hasSize == true
        ? overlayRenderBox!.size.height
        : MediaQuery.sizeOf(context).height;

    // Get precise button position
    final RenderBox? renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final buttonPosition =
        renderBox.localToGlobal(Offset.zero) - overlayGlobalOrigin;
    final buttonSize = renderBox.size;

    final buttonBottom = buttonPosition.dy + buttonSize.height;

    // Panel placement: Prefer exact Header Bottom, fallback to Button Bottom
    double panelTop;
    double bridgeHeight = 0.0;

    final reportedHeaderBottom = MegaMenuController.instance.headerBottom;
    if (reportedHeaderBottom != null) {
      // Header geometry is reported globally, while Positioned uses the
      // nearest Overlay's coordinate space. Convert before placing the panel.
      final headerBottomInOverlay =
          reportedHeaderBottom - overlayGlobalOrigin.dy;
      // A stale measurement must never place the panel over its own trigger.
      panelTop = headerBottomInOverlay > buttonBottom
          ? headerBottomInOverlay
          : buttonBottom;
      // Calculate bridge height (gap between button and header bottom)
      if (panelTop > buttonBottom) {
        bridgeHeight = panelTop - buttonBottom;
      }
    } else {
      // Fallback
      panelTop = buttonBottom;
    }

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return _MegaMenuOverlay(
          key: _overlayKey,
          screenHeight: screenHeight,
          panelTop: panelTop,
          bridgeHeight: bridgeHeight,
          parent: widget.parent,
          children: widget.children,
          panelBackgroundColor: widget.panelBackgroundColor,
          panelForegroundColor: widget.panelForegroundColor,
          panelRailBackgroundColor: widget.panelRailBackgroundColor,
          panelRailForegroundColor: widget.panelRailForegroundColor,
          branchPresentations: widget.branchPresentations,
          onEnter: () {
            _isHoveringPanel = true;
            _closeTimer?.cancel();
            // If we re-entered during a close animation, try to restore
            if (_overlayKey.currentState?.isClosing ?? false) {
              _overlayKey.currentState?.animateOpen();
              MegaMenuController.instance.openMenu(_menuId);
            }
          },
          onExit: () {
            _isHoveringPanel = false;
            _scheduleClose();
          },
          onFocusEnter: () {
            _isFocusWithinPanel = true;
            _closeTimer?.cancel();
          },
          onFocusExit: () {
            _isFocusWithinPanel = false;
            _scheduleClose();
          },
          onClose: () {
            _isHoveringButton = false;
            _isHoveringPanel = false;
            _isFocusWithinPanel = false;
            _closeMenu(force: true);
          },
          onNavigate: (href, openNew) {
            _closeMenu(force: true);
            widget.onNavigate(href, openNew);
          },
        );
      },
    );

    overlayState.insert(_overlayEntry!);
    setState(() => _isOpen = true);
    MegaMenuController.instance.openMenu(_menuId);
  }

  void _scheduleOpen() {
    if (widget.isEditMode || _isOpen) return;
    _closeTimer?.cancel();
    _openTimer?.cancel();
    _openTimer = Timer(const Duration(milliseconds: 110), () {
      if (mounted && (_isHoveringButton || _isFocused)) {
        _openMenu();
      }
    });
  }

  void _toggleMenu() {
    if (_isOpen) {
      _isHoveringButton = false;
      _isHoveringPanel = false;
      _isFocusWithinPanel = false;
      _closeMenu(force: true);
      return;
    }
    _openMenu();
  }

  Future<void> _closeMenu({bool force = false}) async {
    if (force) {
      _suppressFocusReopen = true;
      _closeTimer?.cancel();
      _closeTimer = null;
      _forceRemoveOverlay();
      MegaMenuController.instance.closeMenu();
      if (mounted) setState(() => _isOpen = false);
      return;
    }

    // PRE-CHECK: only close if we are truly not hovering anything
    if (_isHoveringButton || _isHoveringPanel || _isFocusWithinPanel) {
      return;
    }

    _closeTimer?.cancel();
    _closeTimer = null;

    final state = _overlayKey.currentState;

    // If overlay exists, animate out first
    if (state != null) {
      // 1. Notify header to fade out (matches panel fade out)
      MegaMenuController.instance.closeMenu();

      // 2. Animate panel opacity out
      await state.animateClose();

      // 3. POST-CHECK: Did user hover back in during animation?
      if (_isHoveringButton || _isHoveringPanel || _isFocusWithinPanel) {
        // Abort close!
        MegaMenuController.instance.openMenu(_menuId);
        state.animateOpen();
        return;
      }
    }

    // 4. Actually remove overlay
    _forceRemoveOverlay();
    MegaMenuController.instance.closeMenu(); // Ensure closed state matches
    if (mounted) {
      setState(() => _isOpen = false);
    }
  }

  void _scheduleClose() {
    _openTimer?.cancel();
    _closeTimer?.cancel();
    // The short intent window lets customers cross the header/panel gap
    // without flicker while still dismissing accidental passes quickly.
    _closeTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) _closeMenu();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEditMode) {
      return _buildButtonContent();
    }

    return Semantics(
      button: true,
      label: widget.parent.label,
      hint: _isOpen ? 'Cerrar menú' : 'Abrir menú',
      child: FocusableActionDetector(
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.arrowDown): _OpenMegaMenuIntent(),
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggleMenu();
              return null;
            },
          ),
          _OpenMegaMenuIntent: CallbackAction<_OpenMegaMenuIntent>(
            onInvoke: (_) {
              _openMenu();
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _isHoveringButton = false;
              _isHoveringPanel = false;
              _isFocusWithinPanel = false;
              _closeMenu(force: true);
              return null;
            },
          ),
        },
        onShowFocusHighlight: (value) {
          if (_isFocused != value && mounted) {
            setState(() => _isFocused = value);
          }
          if (value) {
            if (!_suppressFocusReopen) _scheduleOpen();
          } else if (!_isHoveringButton) {
            _suppressFocusReopen = false;
            _scheduleClose();
          }
        },
        child: GestureDetector(
          key: _buttonKey,
          behavior: HitTestBehavior.opaque,
          onTap: _toggleMenu,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) {
              _isHoveringButton = true;
              _scheduleOpen();
            },
            onExit: (_) {
              _isHoveringButton = false;
              _scheduleClose();
            },
            child: _buildButtonContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildButtonContent() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        color: (_isOpen || _isFocused)
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.parent.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.textColor,
                  letterSpacing: 0.1,
                ),
          ),
          const SizedBox(width: 4),
          AnimatedRotation(
            duration: const Duration(milliseconds: 250),
            turns: _isOpen ? -0.5 : 0,
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: widget.textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _OpenMegaMenuIntent extends Intent {
  const _OpenMegaMenuIntent();
}

/// Compact dropdown for navigation branches that are not configured as a
/// full-width mega menu. The `Panel ancho` switch in Structure > Navigation
/// remains meaningful: both renderers consume the same saved hierarchy and
/// typed destinations.
class NavigationDropdownButton extends StatelessWidget {
  const NavigationDropdownButton({
    super.key,
    required this.parent,
    required this.children,
    required this.isEditMode,
    required this.textColor,
    required this.panelBackgroundColor,
    required this.panelForegroundColor,
    required this.onNavigate,
  });

  final WebsiteNavigation parent;
  final List<WebsiteNavigation> children;
  final bool isEditMode;
  final Color textColor;
  final Color panelBackgroundColor;
  final Color panelForegroundColor;
  final void Function(String href, bool openInNewTab) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = panelForegroundColor.withValues(alpha: 0.16);

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(panelBackgroundColor),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(4),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: 0.22),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(2),
            side: BorderSide(color: borderColor),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 8),
        ),
        maximumSize: const WidgetStatePropertyAll(Size(390, 560)),
      ),
      menuChildren: _buildMenuChildren(context, parent, children),
      builder: (context, controller, child) {
        return Semantics(
          button: true,
          label: parent.label,
          hint: controller.isOpen ? 'Cerrar menú' : 'Abrir menú',
          child: TextButton(
            onPressed: isEditMode
                ? null
                : () {
                    if (controller.isOpen) {
                      controller.close();
                    } else {
                      controller.open();
                    }
                  },
            style: TextButton.styleFrom(
              foregroundColor: textColor,
              padding: const EdgeInsets.symmetric(vertical: 5),
              minimumSize: const Size(0, 34),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  parent.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 160),
                  turns: controller.isOpen ? -0.5 : 0,
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildMenuChildren(
    BuildContext context,
    WebsiteNavigation root,
    List<WebsiteNavigation> nodes,
  ) {
    final theme = Theme.of(context);
    final sorted = nodes
        .where((node) => node.isVisible && node.showOnDesktop)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final items = <Widget>[];

    if (root.href?.trim().isNotEmpty == true) {
      items.add(
        MenuItemButton(
          trailingIcon: Icon(
            Icons.arrow_outward_rounded,
            size: 16,
            color: panelForegroundColor.withValues(alpha: 0.7),
          ),
          onPressed: () => onNavigate(
            root.href!,
            root.openInNewTab,
          ),
          style: _compactItemStyle(context, emphasized: true),
          child: Text(
            'VER TODO ${root.label.toUpperCase()}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: panelForegroundColor,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      );
    }
    if (root.href?.trim().isNotEmpty == true && sorted.isNotEmpty) {
      items.add(
        Divider(
          height: 17,
          color: panelForegroundColor.withValues(alpha: 0.14),
        ),
      );
    }
    for (final node in sorted) {
      items.addAll(_buildMenuNode(context, node));
    }
    return items;
  }

  List<Widget> _buildMenuNode(
    BuildContext context,
    WebsiteNavigation node, {
    int depth = 0,
  }) {
    final theme = Theme.of(context);
    final isDirectCategory = _isDirectCategoryDestination(node.href);
    final children = node.children
        .where((child) => child.isVisible && child.showOnDesktop)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final items = <Widget>[
      MenuItemButton(
        trailingIcon: children.isEmpty
            ? null
            : Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 17,
                color: panelForegroundColor.withValues(alpha: 0.55),
              ),
        onPressed: () => onNavigate(
          node.href ?? '/',
          node.openInNewTab,
        ),
        style: _compactItemStyle(
          context,
          depth: depth,
          emphasized: children.isNotEmpty,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              node.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: panelForegroundColor.withValues(
                  alpha: depth == 0 ? 0.96 : 0.74,
                ),
                fontWeight: children.isNotEmpty || depth == 0
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
            if (isDirectCategory)
              Text(
                'Solo esta categoría',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: panelForegroundColor.withValues(alpha: 0.52),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    ];

    for (final child in children) {
      items.addAll(
        _buildMenuNode(
          context,
          child,
          depth: depth + 1,
        ),
      );
    }
    if (depth == 0 && children.isNotEmpty) {
      items.add(
        Divider(
          height: 13,
          color: panelForegroundColor.withValues(alpha: 0.1),
        ),
      );
    }
    return items;
  }

  ButtonStyle _compactItemStyle(
    BuildContext context, {
    int depth = 0,
    bool emphasized = false,
  }) {
    return ButtonStyle(
      foregroundColor: WidgetStatePropertyAll(panelForegroundColor),
      overlayColor: WidgetStatePropertyAll(
        panelForegroundColor.withValues(alpha: 0.08),
      ),
      padding: WidgetStatePropertyAll(
        EdgeInsets.fromLTRB(16 + depth * 18, 10, 14, 10),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(280, 40)),
      textStyle: WidgetStatePropertyAll(
        Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
            ),
      ),
    );
  }
}

class _MegaMenuOverlay extends StatefulWidget {
  final double screenHeight;
  final double panelTop;
  final List<WebsiteNavigation> children;
  final WebsiteNavigation parent;
  final Color panelBackgroundColor;
  final Color panelForegroundColor;
  final Color panelRailBackgroundColor;
  final Color panelRailForegroundColor;
  final Map<String, MegaMenuBranchPresentation> branchPresentations;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onFocusEnter;
  final VoidCallback onFocusExit;
  final VoidCallback onClose;
  final Function(String href, bool openInNewTab) onNavigate;
  final double bridgeHeight;

  const _MegaMenuOverlay({
    super.key,
    required this.screenHeight,
    required this.panelTop,
    required this.bridgeHeight,
    required this.parent,
    required this.children,
    required this.panelBackgroundColor,
    required this.panelForegroundColor,
    required this.panelRailBackgroundColor,
    required this.panelRailForegroundColor,
    required this.branchPresentations,
    required this.onEnter,
    required this.onExit,
    required this.onFocusEnter,
    required this.onFocusExit,
    required this.onClose,
    required this.onNavigate,
  });

  @override
  State<_MegaMenuOverlay> createState() => _MegaMenuOverlayState();
}

class _MegaMenuOverlayState extends State<_MegaMenuOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  WebsiteNavigation? _currentHoveredCategory;
  final List<WebsiteNavigation> _drilldownPath = [];
  bool _isPointerInsideRail = false;
  String? _hoveredSectionId;
  Timer? _railBlankCollapseTimer;

  bool isClosing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _controller.forward();
  }

  List<WebsiteNavigation> _visibleDesktopNodes(
    Iterable<WebsiteNavigation> nodes,
  ) {
    final visible = nodes
        .where((node) => node.isVisible && node.showOnDesktop)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return visible;
  }

  void _selectBranch(WebsiteNavigation branch) {
    if (_currentHoveredCategory?.id == branch.id && _drilldownPath.isEmpty) {
      return;
    }
    setState(() {
      _currentHoveredCategory = branch;
      _drilldownPath.clear();
    });
  }

  void _handleRailHover(bool isInside) {
    _isPointerInsideRail = isInside;
    if (isInside) {
      _collapseBranchIfRailIsBlank();
    } else {
      _railBlankCollapseTimer?.cancel();
    }
  }

  void _handleSectionHover(WebsiteNavigation branch, bool isHovered) {
    if (isHovered) {
      _railBlankCollapseTimer?.cancel();
      _hoveredSectionId = branch.id;
      _selectBranch(branch);
      return;
    }

    if (_hoveredSectionId == branch.id) _hoveredSectionId = null;
    _collapseBranchIfRailIsBlank();
  }

  void _collapseBranchIfRailIsBlank() {
    _railBlankCollapseTimer?.cancel();
    _railBlankCollapseTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted ||
          !_isPointerInsideRail ||
          _hoveredSectionId != null ||
          _currentHoveredCategory == null) {
        return;
      }
      setState(() {
        _currentHoveredCategory = null;
        _drilldownPath.clear();
      });
    });
  }

  void _openVisualCategory(WebsiteNavigation node) {
    final children = _visibleDesktopNodes(node.children);
    if (children.isNotEmpty) {
      setState(() => _drilldownPath.add(node));
      return;
    }

    final href = node.href?.trim();
    if (href != null && href.isNotEmpty) {
      widget.onNavigate(href, node.openInNewTab);
    }
  }

  void _closeVisualCategory() {
    if (_drilldownPath.isEmpty) return;
    setState(() => _drilldownPath.removeLast());
  }

  /// Animate close (fade out)
  Future<void> animateClose() async {
    if (!mounted) return;
    isClosing = true;
    await _controller.reverse();
    isClosing = false;
  }

  /// Animate open (fade in) - used to recover from partial close
  Future<void> animateOpen() async {
    if (!mounted) return;
    isClosing = false;
    await _controller.forward();
  }

  @override
  void dispose() {
    _railBlankCollapseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final availablePanelHeight = widget.screenHeight - widget.panelTop - 12;
    final panelMaxHeight = availablePanelHeight.clamp(180.0, 520.0).toDouble();
    final borderColor = widget.panelForegroundColor.withValues(alpha: 0.14);

    return Stack(
      children: [
        Positioned(
          top: widget.panelTop,
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.translucent,
            child: const ColoredBox(color: Colors.transparent),
          ),
        ),
        Positioned(
          top: widget.panelTop - widget.bridgeHeight,
          left: 0,
          right: 0,
          child: MouseRegion(
            onEnter: (_) => widget.onEnter(),
            onExit: (_) => widget.onExit(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: widget.bridgeHeight),
                CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.escape):
                        widget.onClose,
                  },
                  child: FocusScope(
                    onFocusChange: (focused) {
                      if (focused) {
                        widget.onFocusEnter();
                      } else {
                        widget.onFocusExit();
                      }
                    },
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return Transform.translate(
                          offset: Offset(0, -8 * (1 - _opacity.value)),
                          child: Opacity(
                            opacity: _opacity.value,
                            child: child,
                          ),
                        );
                      },
                      child: Material(
                        key: const ValueKey<String>('mega-menu-panel'),
                        color: widget.panelBackgroundColor,
                        elevation: 4,
                        shadowColor: Colors.black.withValues(alpha: 0.24),
                        child: Container(
                          width: double.infinity,
                          constraints: BoxConstraints(
                            maxHeight: panelMaxHeight,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: borderColor),
                              bottom: BorderSide(color: borderColor),
                            ),
                          ),
                          child: _buildPanelContent(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPanelContent(BuildContext context) {
    final roots = _visibleDesktopNodes(widget.children);
    if (roots.isEmpty) return const SizedBox.shrink();

    final hasStructuredBranches = roots.any(
      (root) => _visibleDesktopNodes(root.children).isNotEmpty,
    );
    final active = roots.contains(_currentHoveredCategory)
        ? _currentHoveredCategory
        : null;
    final drilldownKey = _drilldownPath.map((node) => node.id).join('/');

    final body = hasStructuredBranches
        ? active == null
            ? null
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey('${active.id}|$drilldownKey'),
                  child: _buildBranchDetail(context, active),
                ),
              )
        : _buildFlatRootGrid(context, roots);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildNavigationRail(
          context,
          roots: roots,
          showSections: hasStructuredBranches,
        ),
        if (body != null)
          Flexible(
            child: SingleChildScrollView(child: body),
          ),
      ],
    );
  }

  Widget _buildNavigationRail(
    BuildContext context, {
    required List<WebsiteNavigation> roots,
    required bool showSections,
  }) {
    final theme = Theme.of(context);
    final foreground = widget.panelRailForegroundColor;

    return MouseRegion(
      onEnter: (_) => _handleRailHover(true),
      onExit: (_) => _handleRailHover(false),
      child: ColoredBox(
        key: const ValueKey<String>('mega-menu-rail'),
        color: widget.panelRailBackgroundColor,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: showSections
                    ? Wrap(
                        spacing: 30,
                        runSpacing: 2,
                        children: roots
                            .map(
                              (root) => _MegaMenuSectionTab(
                                label: root.label,
                                isActive:
                                    _currentHoveredCategory?.id == root.id,
                                foregroundColor: foreground,
                                onHoverChanged: (isHovered) =>
                                    _handleSectionHover(root, isHovered),
                                onSelect: () => _selectBranch(root),
                                onNavigate: () {
                                  final href = root.href?.trim();
                                  if (href == null || href.isEmpty) {
                                    _selectBranch(root);
                                    return;
                                  }
                                  widget.onNavigate(
                                    href,
                                    root.openInNewTab,
                                  );
                                },
                              ),
                            )
                            .toList(),
                      )
                    : Text(
                        'Seleccioná una opción para continuar',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: foreground.withValues(alpha: 0.62),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
              if (widget.parent.href?.trim().isNotEmpty == true) ...[
                const SizedBox(width: 28),
                SizedBox(
                  height: 62,
                  child: _MegaMenuLink(
                    label: 'VER TODO',
                    color: foreground,
                    hoverColor: foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    showArrow: true,
                    onTap: () => widget.onNavigate(
                      widget.parent.href!,
                      widget.parent.openInNewTab,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBranchDetail(
    BuildContext context,
    WebsiteNavigation branch,
  ) {
    final children = _visibleDesktopNodes(branch.children);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final overview = _buildBranchOverviewCard(
          context,
          branch,
          compact: compact,
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              overview,
              if (children.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  child: _buildVisualCategoryBrowser(
                    context,
                    branch,
                    compact: true,
                  ),
                ),
            ],
          );
        }

        return SizedBox(
          height: 440,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 440, child: overview),
              if (children.isNotEmpty)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(30, 20, 28, 22),
                    child: _buildVisualCategoryBrowser(
                      context,
                      branch,
                      compact: false,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBranchOverviewCard(
    BuildContext context,
    WebsiteNavigation branch, {
    required bool compact,
  }) {
    final theme = Theme.of(context);
    final presentation = widget.branchPresentations[branch.id];
    final imageUrl = presentation?.imageUrl.trim() ?? '';
    final hasImage = imageUrl.isNotEmpty;
    final overlay = (presentation?.overlay ?? 0.58).clamp(0.0, 0.85);
    final centerOverlay = math.max(0.08, overlay * 0.34);
    final foreground = hasImage ? Colors.white : widget.panelForegroundColor;

    final card = ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: widget.panelBackgroundColor),
          if (hasImage)
            Semantics(
              image: true,
              label: 'Imagen de ${branch.label}',
              child: Image.network(
                imageUrl,
                key: ValueKey<String>('mega-menu-branch-image-${branch.id}'),
                fit: BoxFit.cover,
                alignment: Alignment.center,
                filterQuality: FilterQuality.high,
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: widget.panelBackgroundColor,
                ),
              ),
            ),
          if (hasImage)
            DecoratedBox(
              key: ValueKey<String>(
                'mega-menu-branch-gradient-${branch.id}',
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: overlay),
                    Colors.black.withValues(alpha: centerOverlay),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.48, 0.86],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SECCIÓN',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: foreground.withValues(alpha: 0.68),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.25,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  branch.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.55,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 36,
                  height: 2,
                  color: foreground.withValues(alpha: 0.84),
                ),
                if (branch.href?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  _MegaMenuLink(
                    label: 'Explorar ${branch.label}',
                    color: foreground.withValues(alpha: 0.82),
                    hoverColor: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    showArrow: true,
                    onTap: () => widget.onNavigate(
                      branch.href!,
                      branch.openInNewTab,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return KeyedSubtree(
      key: ValueKey<String>('mega-menu-branch-overview-${branch.id}'),
      child: compact
          ? SizedBox(height: 220, child: card)
          : ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 440),
              child: card,
            ),
    );
  }

  Widget _buildVisualCategoryBrowser(
    BuildContext context,
    WebsiteNavigation branch, {
    required bool compact,
  }) {
    final levelOwner = _drilldownPath.isEmpty ? branch : _drilldownPath.last;
    final nodes = _visibleDesktopNodes(levelOwner.children);
    if (nodes.isEmpty) return const SizedBox.shrink();

    final previousOwner = _drilldownPath.length < 2
        ? branch
        : _drilldownPath[_drilldownPath.length - 2];
    final showHeader = _drilldownPath.isNotEmpty;

    final grid = _buildVisualCardGrid(
      context,
      nodes,
      compact: compact,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          Row(
            children: [
              TextButton.icon(
                key: const ValueKey<String>('mega-menu-drill-back'),
                onPressed: _closeVisualCategory,
                icon: const Icon(Icons.arrow_back_rounded, size: 17),
                label: Text('Volver a ${previousOwner.label}'),
                style: TextButton.styleFrom(
                  foregroundColor: widget.panelForegroundColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const StadiumBorder(),
                  side: BorderSide(
                    color: widget.panelForegroundColor.withValues(alpha: 0.22),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              const Spacer(),
              if (levelOwner.href?.trim().isNotEmpty == true)
                _MegaMenuLink(
                  label: 'VER TODO EN ${levelOwner.label.toUpperCase()}',
                  color: widget.panelForegroundColor.withValues(alpha: 0.66),
                  hoverColor: widget.panelForegroundColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.65,
                  showArrow: true,
                  onTap: () => widget.onNavigate(
                    levelOwner.href!,
                    levelOwner.openInNewTab,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (compact) grid else Expanded(child: grid),
      ],
    );
  }

  Widget _buildVisualCardGrid(
    BuildContext context,
    List<WebsiteNavigation> nodes, {
    required bool compact,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final delegate = compact
            ? const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 18,
                mainAxisSpacing: 16,
                mainAxisExtent: 164,
              )
            : const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 286,
                crossAxisSpacing: 18,
                mainAxisSpacing: 16,
                mainAxisExtent: 184,
              );

        return GridView.builder(
          key: const ValueKey<String>('mega-menu-card-grid'),
          padding: EdgeInsets.zero,
          primary: false,
          shrinkWrap: compact,
          physics: compact
              ? const NeverScrollableScrollPhysics()
              : const ClampingScrollPhysics(),
          gridDelegate: delegate,
          itemCount: nodes.length,
          itemBuilder: (context, index) {
            final node = nodes[index];
            final children = _visibleDesktopNodes(node.children);
            return _MegaMenuMediaCard(
              key: ValueKey<String>('mega-menu-card-${node.id}'),
              navigationId: node.id,
              label: node.label,
              imageUrl:
                  widget.branchPresentations[node.id]?.imageUrl.trim() ?? '',
              childLabels:
                  children.map((child) => child.label).toList(growable: false),
              directCategory: _isDirectCategoryDestination(node.href),
              foregroundColor: widget.panelForegroundColor,
              panelColor: widget.panelBackgroundColor,
              onExplore: () => _openVisualCategory(node),
              onNavigate: node.href?.trim().isNotEmpty == true
                  ? () => widget.onNavigate(
                        node.href!,
                        node.openInNewTab,
                      )
                  : null,
            );
          },
        );
      },
    );
  }

  Widget _buildFlatRootGrid(
    BuildContext context,
    List<WebsiteNavigation> roots,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
      child: _buildCategoryGrid(
        context,
        roots,
        onSelect: (_) {},
      ),
    );
  }

  Widget _buildCategoryGrid(
    BuildContext context,
    List<WebsiteNavigation> nodes, {
    String? activeId,
    required ValueChanged<WebsiteNavigation> onSelect,
  }) {
    const gap = 18.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 480
                ? 3
                : 2;
        final itemWidth =
            (constraints.maxWidth - gap * (columnCount - 1)) / columnCount;

        return Wrap(
          spacing: gap,
          runSpacing: 10,
          children: nodes
              .map(
                (node) => SizedBox(
                  width: itemWidth,
                  child: _MegaMenuCategoryLink(
                    label: node.label,
                    childCount: _visibleDesktopNodes(node.children).length,
                    isActive: activeId == node.id,
                    foregroundColor: widget.panelForegroundColor,
                    onSelect: () => onSelect(node),
                    onNavigate: () {
                      final href = node.href?.trim();
                      if (href == null || href.isEmpty) {
                        onSelect(node);
                        return;
                      }
                      widget.onNavigate(href, node.openInNewTab);
                    },
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

// ============================================================================
// COLUMN HEADER & LINK (Helper Widgets)
// ============================================================================

class _MegaMenuMediaCard extends StatefulWidget {
  const _MegaMenuMediaCard({
    super.key,
    required this.navigationId,
    required this.label,
    required this.imageUrl,
    required this.childLabels,
    required this.directCategory,
    required this.foregroundColor,
    required this.panelColor,
    required this.onExplore,
    required this.onNavigate,
  });

  final String navigationId;
  final String label;
  final String imageUrl;
  final List<String> childLabels;
  final bool directCategory;
  final Color foregroundColor;
  final Color panelColor;
  final VoidCallback onExplore;
  final VoidCallback? onNavigate;

  @override
  State<_MegaMenuMediaCard> createState() => _MegaMenuMediaCardState();
}

class _MegaMenuMediaCardState extends State<_MegaMenuMediaCard> {
  bool _isHovered = false;
  bool _isFocused = false;
  bool _isNavigateHovered = false;
  bool _isNavigateFocused = false;

  bool get _isActive => _isHovered || _isFocused;
  bool get _isNavigateActive => _isNavigateHovered || _isNavigateFocused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewLabels = widget.childLabels.take(5).toList(growable: false);
    final remaining = widget.childLabels.length - previewLabels.length;
    final hasChildren = widget.childLabels.isNotEmpty;
    final imageUrl = widget.imageUrl.trim();
    final actionLabel =
        widget.directCategory ? 'SOLO ESTA CATEGORÍA' : 'VER CATEGORÍA';
    final semanticLabel = widget.directCategory
        ? 'Ver solo productos de ${widget.label}'
        : 'Ver categoría ${widget.label}';

    Widget buildImage() => ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: Color.alphaBlend(
                  widget.foregroundColor.withValues(alpha: 0.08),
                  widget.panelColor,
                ),
              ),
              if (imageUrl.isNotEmpty)
                AnimatedScale(
                  duration: const Duration(milliseconds: 190),
                  curve: Curves.easeOutCubic,
                  scale: _isActive ? 1.025 : 1,
                  child: Image.network(
                    imageUrl,
                    key: ValueKey<String>(
                      'mega-menu-card-image-${widget.navigationId}',
                    ),
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, __, ___) => ColoredBox(
                      color: Color.alphaBlend(
                        widget.foregroundColor.withValues(alpha: 0.08),
                        widget.panelColor,
                      ),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: widget.foregroundColor.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                )
              else
                Icon(
                  Icons.image_outlined,
                  size: 30,
                  color: widget.foregroundColor.withValues(alpha: 0.38),
                ),
              IgnorePointer(
                child: AnimatedOpacity(
                  key: ValueKey<String>(
                    'mega-menu-card-hover-${widget.navigationId}',
                  ),
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  opacity: _isActive ? 1 : 0,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.74),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: hasChildren
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final label in previewLabels)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 1.5,
                                      ),
                                      child: Text(
                                        label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: theme.textTheme.labelMedium
                                            ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  if (remaining > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text(
                                        '+$remaining más',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: Colors.white
                                              .withValues(alpha: 0.68),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    actionLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.75,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );

    Widget buildLabel({required bool exposeParentAction}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: widget.foregroundColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.1,
                      ),
                    ),
                    if (widget.directCategory)
                      Text(
                        'SOLO ESTA CATEGORÍA',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: widget.foregroundColor.withValues(alpha: 0.55),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.45,
                        ),
                      ),
                  ],
                ),
              ),
              if (exposeParentAction) ...[
                const SizedBox(width: 8),
                Text(
                  actionLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _isNavigateActive
                        ? PublicStoreTheme.info
                        : widget.foregroundColor.withValues(alpha: 0.68),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.45,
                  ),
                ),
              ],
              const SizedBox(width: 5),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: exposeParentAction && _isNavigateActive
                    ? PublicStoreTheme.info
                    : widget.foregroundColor.withValues(alpha: 0.58),
              ),
            ],
          ),
        );

    void updateFocus(bool value) {
      if (_isFocused != value) setState(() => _isFocused = value);
    }

    if (!hasChildren) {
      return Semantics(
        button: true,
        label: semanticLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey<String>(
              'mega-menu-card-navigate-${widget.navigationId}',
            ),
            onTap: widget.onNavigate ?? widget.onExplore,
            onHover: (value) {
              if (_isHovered != value) setState(() => _isHovered = value);
            },
            onFocusChange: updateFocus,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: widget.foregroundColor.withValues(alpha: 0.08),
            highlightColor: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: buildImage()),
                const SizedBox(height: 7),
                buildLabel(exposeParentAction: false),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: MouseRegion(
        onEnter: (_) {
          if (!_isHovered) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (_isHovered) setState(() => _isHovered = false);
        },
        child: Material(
          color: Colors.transparent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Explorar subcategorías de ${widget.label}',
                  child: InkWell(
                    key: ValueKey<String>(
                      'mega-menu-card-explore-${widget.navigationId}',
                    ),
                    onTap: widget.onExplore,
                    onFocusChange: updateFocus,
                    overlayColor:
                        const WidgetStatePropertyAll(Colors.transparent),
                    focusColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    splashColor: widget.foregroundColor.withValues(alpha: 0.08),
                    highlightColor: Colors.transparent,
                    child: buildImage(),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Semantics(
                button: true,
                label: widget.onNavigate == null
                    ? 'Explorar subcategorías de ${widget.label}'
                    : semanticLabel,
                child: InkWell(
                  key: ValueKey<String>(
                    'mega-menu-card-navigate-${widget.navigationId}',
                  ),
                  onTap: widget.onNavigate ?? widget.onExplore,
                  onHover: (value) {
                    if (_isNavigateHovered != value) {
                      setState(() => _isNavigateHovered = value);
                    }
                  },
                  onFocusChange: (value) {
                    updateFocus(value);
                    if (_isNavigateFocused != value) {
                      setState(() => _isNavigateFocused = value);
                    }
                  },
                  borderRadius: BorderRadius.circular(3),
                  child: buildLabel(
                    exposeParentAction: widget.onNavigate != null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MegaMenuSectionTab extends StatelessWidget {
  final String label;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onSelect;
  final VoidCallback onNavigate;
  final bool isActive;
  final Color foregroundColor;

  const _MegaMenuSectionTab({
    required this.label,
    required this.onHoverChanged,
    required this.onSelect,
    required this.onNavigate,
    required this.isActive,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextButton(
      onPressed: onNavigate,
      onHover: onHoverChanged,
      onFocusChange: (focused) {
        if (focused) onSelect();
      },
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 12),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 62)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        overlayColor: WidgetStatePropertyAll(
          foregroundColor.withValues(alpha: 0.06),
        ),
        foregroundColor: WidgetStatePropertyAll(foregroundColor),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelMedium?.copyWith(
              color: foregroundColor.withValues(
                alpha: isActive ? 1 : 0.67,
              ),
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 130),
            curve: Curves.easeOut,
            width: isActive ? 30 : 0,
            height: 2,
            color: foregroundColor,
          ),
        ],
      ),
    );
  }
}

class _MegaMenuCategoryLink extends StatelessWidget {
  const _MegaMenuCategoryLink({
    required this.label,
    required this.childCount,
    required this.isActive,
    required this.foregroundColor,
    required this.onSelect,
    required this.onNavigate,
  });

  final String label;
  final int childCount;
  final bool isActive;
  final Color foregroundColor;
  final VoidCallback onSelect;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeTint = foregroundColor.withValues(alpha: 0.065);

    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onSelect(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: foregroundColor.withValues(
                  alpha: isActive ? 0.5 : 0.14,
                ),
                width: isActive ? 2 : 1,
              ),
            ),
          ),
          child: TextButton(
            onPressed: onNavigate,
            onFocusChange: (focused) {
              if (focused) onSelect();
            },
            style: ButtonStyle(
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              ),
              minimumSize: const WidgetStatePropertyAll(Size(0, 54)),
              alignment: Alignment.centerLeft,
              shape: const WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (isActive ||
                    states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return activeTint;
                }
                return Colors.transparent;
              }),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: foregroundColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.05,
                        ),
                      ),
                      if (childCount > 0) ...[
                        const SizedBox(height: 2),
                        Text(
                          '$childCount ${childCount == 1 ? 'opción' : 'opciones'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: foregroundColor.withValues(alpha: 0.56),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  childCount > 0
                      ? Icons.chevron_right_rounded
                      : Icons.arrow_outward_rounded,
                  size: 17,
                  color: foregroundColor.withValues(alpha: 0.58),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MegaMenuLink extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final double? fontSize;
  final Color? color;
  final Color? hoverColor;
  final FontWeight? fontWeight;
  final double? letterSpacing;
  final bool showArrow;

  const _MegaMenuLink({
    required this.label,
    required this.onTap,
    this.fontSize,
    this.color,
    this.hoverColor,
    this.fontWeight,
    this.letterSpacing,
    this.showArrow = false,
  });

  @override
  State<_MegaMenuLink> createState() => _MegaMenuLinkState();
}

class _MegaMenuLinkState extends State<_MegaMenuLink> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final restingColor = widget.color ?? colors.onSurface;
    final interactiveColor = widget.hoverColor ?? colors.primary;

    return TextButton(
      onPressed: widget.onTap,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        alignment: Alignment.centerLeft,
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return interactiveColor;
          }
          return restingColor;
        }),
        overlayColor: WidgetStatePropertyAll(
          interactiveColor.withValues(alpha: 0.06),
        ),
        textStyle: WidgetStatePropertyAll(
          theme.textTheme.bodyMedium?.copyWith(
            fontSize: widget.fontSize ?? 13,
            fontWeight: widget.fontWeight ?? FontWeight.normal,
            letterSpacing: widget.letterSpacing,
            height: 1.35,
          ),
        ),
      ),
      child: widget.showArrow
          ? Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(widget.label),
                const Icon(Icons.arrow_forward_rounded, size: 14),
              ],
            )
          : Text(widget.label),
    );
  }
}
