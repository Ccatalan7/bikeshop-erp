import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../modules/website/models/website_catalog_query.dart';
import '../../modules/website/models/website_page_models.dart';
import 'package:vinabike_public_core/modules/website/models/website_menu_icons.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/header_menu_help.dart';
import 'package:vinabike_public_core/public_store/theme/header_menu_palette.dart';
import 'website_menu_icon_view.dart';

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
/// receives only the media needed to render a branch, keyed by navigation ID:
/// since 2026-10-25 the panel draws the section's photo as it is, beside
/// its links, so the old card's darkening, width and text placement are no
/// longer read.
class MegaMenuBranchPresentation {
  const MegaMenuBranchPresentation({required this.imageUrl});

  final String imageUrl;
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

  /// Closes the open menu. With [menuId], only if that menu is the open one:
  /// moving from «Componentes» to «Accesorios», the second opens before the
  /// first finishes closing, and until 2026-10-25 that close turned the
  /// header back to clear under the open panel.
  void closeMenu([String? menuId]) {
    if (menuId != null && menuId != _activeMenuId) return;
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
  final bool uppercaseLabel;
  final Color textColor;

  /// The open panel's colors (`HeaderMenuPalette`, shared with the HTML
  /// store) and its help card.
  final HeaderMenuPalette palette;
  final HeaderMenuHelp help;
  final Map<String, MegaMenuBranchPresentation> branchPresentations;
  final bool Function(WebsiteNavigation navigation)? canNavigate;
  final Function(String href, bool openInNewTab) onNavigate;

  const MegaMenuButton({
    super.key,
    required this.parent,
    required this.children,
    required this.isEditMode,
    this.uppercaseLabel = false,
    required this.textColor,
    required this.palette,
    required this.help,
    this.branchPresentations = const <String, MegaMenuBranchPresentation>{},
    this.canNavigate,
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
  bool _overlayRebuildScheduled = false;
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
  void didUpdateWidget(covariant MegaMenuButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Overlay entries live outside this subtree. Rebuild the active panel when
    // a fresh category-publication projection removes or reclassifies rows.
    // didUpdateWidget itself runs inside the owner's build; marking the
    // OverlayEntry dirty synchronously from here causes Flutter's
    // "markNeedsBuild called during build" red screen. Coalesce changes and
    // invalidate the overlay only after the current frame has completed.
    if (_overlayEntry == null || _overlayRebuildScheduled) return;
    _overlayRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayRebuildScheduled = false;
      if (!mounted || !_isOpen) return;
      _overlayEntry?.markNeedsBuild();
    });
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
    final screenHeight = overlayRenderBox?.hasSize == true
        ? overlayRenderBox!.size.height
        : MediaQuery.sizeOf(context).height;

    // Get precise button position
    final RenderBox? renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // The Overlay's RenderBox is the ONE owner of coordinate conversion:
    // every global point maps into overlay space through globalToLocal, so
    // ancestor transforms (e.g. the ERP Preview 0.8 window zoom) are
    // inverted exactly once. Subtracting overlay/global origins by hand
    // reuses a transformed physical delta as an overlay-local logical
    // coordinate (double-scaling under zoom), and adding an untransformed
    // size.height to such a delta compounds the error.
    Offset toOverlay(Offset global) =>
        overlayRenderBox?.globalToLocal(global) ?? global;

    final buttonBottom = toOverlay(
      renderBox.localToGlobal(Offset(0, renderBox.size.height)),
    ).dy;

    // Panel placement: Prefer exact Header Bottom, fallback to Button Bottom
    double panelTop;
    double bridgeHeight = 0.0;

    final reportedHeaderBottom = MegaMenuController.instance.headerBottom;
    if (reportedHeaderBottom != null) {
      // Header geometry is reported globally, while Positioned uses the
      // nearest Overlay's coordinate space. Convert before placing the panel.
      final headerBottomInOverlay =
          toOverlay(Offset(0, reportedHeaderBottom)).dy;
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
          palette: widget.palette,
          help: widget.help,
          branchPresentations: widget.branchPresentations,
          canNavigate: widget.canNavigate,
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
      MegaMenuController.instance.closeMenu(_menuId);
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
      MegaMenuController.instance.closeMenu(_menuId);

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
    // Ensure closed state matches.
    MegaMenuController.instance.closeMenu(_menuId);
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

  /// The header's item: the same line as its links, underlined while open
  /// (`.mega-btn` of the HTML store).
  Widget _buildButtonContent() {
    final open = _isOpen || _isFocused;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: open ? widget.textColor : Colors.transparent,
            width: 2,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.uppercaseLabel
                ? widget.parent.label.toUpperCase()
                : widget.parent.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: widget.textColor,
                  letterSpacing: 0.84,
                ),
          ),
          const SizedBox(width: 2),
          AnimatedRotation(
            duration: const Duration(milliseconds: 200),
            turns: _isOpen ? -0.5 : 0,
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 16,
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
    this.uppercaseLabel = false,
    required this.textColor,
    required this.panelBackgroundColor,
    required this.panelForegroundColor,
    this.canNavigate,
    required this.onNavigate,
  });

  final WebsiteNavigation parent;
  final List<WebsiteNavigation> children;
  final bool isEditMode;
  final bool uppercaseLabel;
  final Color textColor;
  final Color panelBackgroundColor;
  final Color panelForegroundColor;
  final bool Function(WebsiteNavigation navigation)? canNavigate;
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
            style: ButtonStyle(
              foregroundColor: WidgetStatePropertyAll(textColor),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (controller.isOpen ||
                    states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)) {
                  return textColor.withValues(alpha: 0.08);
                }
                return Colors.transparent;
              }),
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 5),
              ),
              minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  uppercaseLabel ? parent.label.toUpperCase() : parent.label,
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

    if (_canNavigate(root) && root.href?.trim().isNotEmpty == true) {
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
    if (_canNavigate(root) &&
        root.href?.trim().isNotEmpty == true &&
        sorted.isNotEmpty) {
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
    final isDirectCategory =
        _canNavigate(node) && _isDirectCategoryDestination(node.href);
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
        onPressed: _canNavigate(node)
            ? () => onNavigate(
                  node.href ?? '/',
                  node.openInNewTab,
                )
            : null,
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

  bool _canNavigate(WebsiteNavigation navigation) =>
      canNavigate?.call(navigation) ?? true;

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
      // GUI_MOBILE_DESIGN_PRINCIPLES: 48px minimum in both dimensions. This
      // dropdown is the phone/tablet path through the whole category tree, so
      // a 40px row was the smallest target on the most-used navigation.
      minimumSize: const WidgetStatePropertyAll(Size(280, 48)),
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
  final HeaderMenuPalette palette;
  final HeaderMenuHelp help;
  final Map<String, MegaMenuBranchPresentation> branchPresentations;
  final bool Function(WebsiteNavigation navigation)? canNavigate;
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
    required this.palette,
    required this.help,
    required this.branchPresentations,
    this.canNavigate,
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

/// The wide panel, as `services/storefront_html/lib/src/mega_menu_view.dart`
/// draws it for the public store (2026-10-25): the first level as sections
/// in a column, each with its icon; the open section's name, «Ver todo …» and
/// its subcategories, each with its own under it; the section's photo over
/// the help card. Every section is laid out in the same place, so the panel
/// keeps the height of the tallest. A section opens when the pointer enters
/// its row, unless the pointer is heading into the open section's links.
class _MegaMenuOverlayState extends State<_MegaMenuOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  String? _activeId;
  final GlobalKey _railKey = GlobalKey();
  final List<Offset> _moves = [];
  Offset? _lastDelay;
  Timer? _aimTimer;

  bool isClosing = false;

  bool _canNavigate(WebsiteNavigation navigation) =>
      widget.canNavigate?.call(navigation) ?? true;

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

  void _select(WebsiteNavigation section) {
    _aimTimer?.cancel();
    if (_activeId == section.id) return;
    setState(() => _activeId = section.id);
  }

  /// The pointer is heading into the open section when, seen from the
  /// column's right corners, it moved closer to both since the last samples.
  bool _aiming() {
    final box = _railKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || _moves.length < 2) return false;
    final now = _moves.last;
    final before = _moves.first;
    if (_lastDelay == now) return false;
    final origin = box.localToGlobal(Offset.zero);
    final right = origin.dx + box.size.width;
    if (now.dx >= right) return false;
    final up = Offset(right, origin.dy - 40);
    final down = Offset(right, origin.dy + box.size.height + 40);
    double slope(Offset a, Offset b) => (b.dy - a.dy) / (b.dx - a.dx);
    if (slope(now, up) < slope(before, up) &&
        slope(now, down) > slope(before, down)) {
      _lastDelay = now;
      return true;
    }
    return false;
  }

  void _hover(WebsiteNavigation section) {
    _aimTimer?.cancel();
    if (_aiming()) {
      _aimTimer = Timer(const Duration(milliseconds: 160), () {
        if (mounted) _hover(section);
      });
      return;
    }
    _select(section);
  }

  void _go(WebsiteNavigation node) {
    final href = node.href?.trim();
    if (!_canNavigate(node) || href == null || href.isEmpty) return;
    widget.onNavigate(href, node.openInNewTab);
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
    _aimTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Color _c(WebsiteRgba color) => _flutterColor(color);

  @override
  Widget build(BuildContext context) {
    final availablePanelHeight = widget.screenHeight - widget.panelTop - 24;
    final panelMaxHeight = availablePanelHeight.clamp(240.0, 600.0).toDouble();
    final palette = widget.palette;

    return Stack(
      children: [
        // The page under the panel dims, and a click there closes it.
        Positioned(
          top: widget.panelTop,
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.translucent,
            child: FadeTransition(
              opacity: _opacity,
              child: const ColoredBox(color: Color(0x520B0E13)),
            ),
          ),
        ),
        Positioned(
          top: widget.panelTop - widget.bridgeHeight,
          left: 0,
          right: 0,
          child: MouseRegion(
            onEnter: (_) => widget.onEnter(),
            onExit: (_) => widget.onExit(),
            onHover: (event) {
              _moves.add(event.position);
              if (_moves.length > 3) _moves.removeAt(0);
            },
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
                        color: _c(palette.surface),
                        elevation: 8,
                        shadowColor: const Color(0x520F172A),
                        child: Container(
                          width: double.infinity,
                          constraints: BoxConstraints(
                            maxHeight: panelMaxHeight,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: _c(palette.divider)),
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
    final sections = _visibleDesktopNodes(widget.children);
    if (sections.isEmpty) return const SizedBox.shrink();
    final structured = sections.any(
      (section) => _visibleDesktopNodes(section.children).isNotEmpty,
    );
    final active = structured
        ? sections.firstWhere(
            (section) => section.id == _activeId,
            orElse: () => sections.first,
          )
        : null;
    final photos = <String, String>{
      if (structured)
        for (final section in sections)
          if (widget.branchPresentations[section.id]?.imageUrl.trim()
              case final url? when url.isNotEmpty)
            section.id: url,
    };
    final showAside = photos.isNotEmpty || widget.help.show;

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 1280;
        final railWidth = narrow ? 260.0 : 300.0;
        final asideWidth = narrow ? 240.0 : 280.0;
        final gutter = narrow ? 28.0 : 40.0;
        final mainWidth = constraints.maxWidth -
            (structured ? railWidth : 0) -
            (showAside ? asideWidth + gutter : 0) -
            gutter * 2;

        final main = structured
            ? Stack(
                children: [
                  for (final section in sections)
                    Visibility(
                      key: ValueKey<String>(
                        'mega-menu-branch-content-${section.id}',
                      ),
                      visible: section.id == active!.id,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: AnimatedOpacity(
                        opacity: section.id == active.id ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        curve: Curves.easeOut,
                        child: _buildSection(
                          context,
                          title: section.label,
                          page: section,
                          groups: _visibleDesktopNodes(section.children),
                          width: mainWidth,
                        ),
                      ),
                    ),
                ],
              )
            : _buildSection(
                context,
                title: widget.parent.label,
                page: widget.parent,
                groups: sections,
                width: mainWidth,
              );

        return SingleChildScrollView(
          child: Stack(
            children: [
              if (structured)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: railWidth,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _c(widget.palette.rail),
                      border: Border(
                        right: BorderSide(color: _c(widget.palette.divider)),
                      ),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (structured)
                    SizedBox(
                      width: railWidth,
                      child: _buildRail(context, sections, active!),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(gutter, 28, gutter, 32),
                      child: main,
                    ),
                  ),
                  if (showAside)
                    SizedBox(
                      width: asideWidth,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(0, 28, gutter, 32),
                        child: _buildAside(context, photos, active),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRail(
    BuildContext context,
    List<WebsiteNavigation> sections,
    WebsiteNavigation active,
  ) {
    final palette = widget.palette;
    final icons = sections.any(
      (section) => WebsiteMenuIcons.of(section.icon) != null,
    );
    return Padding(
      key: _railKey,
      padding: const EdgeInsets.fromLTRB(26, 20, 14, 24),
      child: Column(
        key: const ValueKey<String>('mega-menu-rail'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: _MegaMenuSectionRow(
                key: ValueKey<String>('mega-menu-section-${section.id}'),
                label: section.label,
                icon: icons ? section.icon : null,
                iconSlot: icons,
                active: section.id == active.id,
                palette: palette,
                onHover: () => _hover(section),
                onSelect: () => _select(section),
              ),
            ),
          if (_canNavigate(widget.parent) &&
              widget.parent.href?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: _c(palette.divider))),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _MegaMenuTextLink(
                  key: const ValueKey<String>('mega-menu-all'),
                  label: 'Ver todo ${widget.parent.label}',
                  color: _c(palette.ink),
                  hoverColor: _c(palette.ink),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  arrow: true,
                  minHeight: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onTap: () => _go(widget.parent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A section: its name and «Ver todo …», then its subcategories, each with
  /// its own under it, in as many columns of at least 190 px as fit.
  Widget _buildSection(
    BuildContext context, {
    required String title,
    required WebsiteNavigation page,
    required List<WebsiteNavigation> groups,
    required double width,
  }) {
    final theme = Theme.of(context);
    final palette = widget.palette;
    const columnGap = 32.0;
    final columns =
        math.max(1, ((width + columnGap) / (190 + columnGap)).floor());
    final itemWidth = math.max(
      0.0,
      (width - columnGap * (columns - 1)) / columns,
    );
    final ink = _c(palette.ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 24,
          runSpacing: 8,
          children: [
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontSize: 26,
                height: 1.15,
                fontWeight: FontWeight.w600,
                color: _c(palette.onSurface),
              ),
            ),
            if (_canNavigate(page) && page.href?.trim().isNotEmpty == true)
              _MegaMenuTextLink(
                label: 'Ver todo $title',
                color: ink,
                hoverColor: ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                arrow: true,
                onTap: () => _go(page),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: columnGap,
          runSpacing: 18,
          children: [
            for (final group in groups)
              SizedBox(
                width: itemWidth,
                child: _buildGroup(context, group),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGroup(BuildContext context, WebsiteNavigation group) {
    final palette = widget.palette;
    final ink = _c(palette.ink);
    final subs = [
      for (final sub in _visibleDesktopNodes(group.children))
        if (_canNavigate(sub) && sub.href?.trim().isNotEmpty == true) sub,
    ];
    const shownMax = 8;
    final shown = subs.take(shownMax).toList();
    final more = subs.length - shown.length;
    final groupLinks =
        _canNavigate(group) && group.href?.trim().isNotEmpty == true;
    return Column(
      key: ValueKey<String>('mega-menu-group-${group.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _MegaMenuTextLink(
          label: group.label,
          color: _c(palette.onSurface),
          hoverColor: ink,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          onTap: groupLinks ? () => _go(group) : null,
        ),
        if (shown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              spacing: 12,
              children: [
                for (final sub in shown)
                  _MegaMenuTextLink(
                    label: sub.label,
                    color: _c(palette.muted),
                    hoverColor: ink,
                    fontSize: 14,
                    onTap: () => _go(sub),
                  ),
                if (more > 0 && groupLinks)
                  _MegaMenuTextLink(
                    label: 'Ver $more más',
                    color: ink,
                    hoverColor: ink,
                    fontSize: 14,
                    onTap: () => _go(group),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAside(
    BuildContext context,
    Map<String, String> photos,
    WebsiteNavigation? active,
  ) {
    final theme = Theme.of(context);
    final palette = widget.palette;
    final help = widget.help;
    final photo = active == null ? null : photos[active.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (photo != null) ...[
          ClipRRect(
            key: ValueKey<String>('mega-menu-branch-image-${active!.id}'),
            borderRadius: BorderRadius.circular(6),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.network(
                photo,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    ColoredBox(color: _c(palette.helpFill)),
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        if (help.show)
          Container(
            key: const ValueKey<String>('mega-menu-help'),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _c(palette.helpFill),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 20,
                      color: _c(palette.ink),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        help.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: _c(palette.onSurface),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  help.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 14,
                    height: 1.5,
                    color: _c(palette.muted),
                  ),
                ),
                const SizedBox(height: 4),
                _MegaMenuTextLink(
                  label: help.action,
                  color: _c(palette.ink),
                  hoverColor: _c(palette.ink),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  arrow: true,
                  onTap: () => widget.onNavigate(help.href, help.external),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

Color _flutterColor(WebsiteRgba color) =>
    Color.from(alpha: color.a, red: color.r, green: color.g, blue: color.b);

/// A row of the column: hovering or focusing it opens its section, as does
/// a tap.
class _MegaMenuSectionRow extends StatefulWidget {
  const _MegaMenuSectionRow({
    super.key,
    required this.label,
    required this.icon,
    required this.iconSlot,
    required this.active,
    required this.palette,
    required this.onHover,
    required this.onSelect,
  });

  final String label;
  final String? icon;
  final bool iconSlot;
  final bool active;
  final HeaderMenuPalette palette;
  final VoidCallback onHover;
  final VoidCallback onSelect;

  @override
  State<_MegaMenuSectionRow> createState() => _MegaMenuSectionRowState();
}

class _MegaMenuSectionRowState extends State<_MegaMenuSectionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = widget.palette;
    final foreground = _flutterColor(
      widget.active ? palette.onRailActive : palette.onRail,
    );
    final background = widget.active
        ? _flutterColor(palette.railActive)
        : _hovered
            ? _flutterColor(palette.railHover)
            : Colors.transparent;
    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.label,
      excludeSemantics: true,
      // A MouseRegion, not the detector's hover highlight: that one waits for
      // the pointer's highlight mode, and a tap before leaves it in touch.
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onFocusChange: (focused) {
          if (focused) widget.onSelect();
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onSelect();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) {
            setState(() => _hovered = true);
            widget.onHover();
          },
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onSelect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  if (widget.iconSlot) ...[
                    WebsiteMenuIconView(
                      widget.icon,
                      size: 20,
                      color: widget.active
                          ? foreground
                          : _flutterColor(palette.ink),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      widget.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: widget.active
                        ? foreground
                        : _flutterColor(palette.onRail.withAlpha(0.42)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A text link of the panel: underlined in [hoverColor] while hovered or
/// focused; without [onTap] it is a plain label.
class _MegaMenuTextLink extends StatefulWidget {
  const _MegaMenuTextLink({
    super.key,
    required this.label,
    required this.color,
    required this.hoverColor,
    required this.fontSize,
    required this.onTap,
    this.fontWeight = FontWeight.w400,
    this.arrow = false,
    this.minHeight = 0,
    this.padding = EdgeInsets.zero,
  });

  final String label;
  final Color color;
  final Color hoverColor;
  final double fontSize;
  final FontWeight fontWeight;
  final bool arrow;
  final double minHeight;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  State<_MegaMenuTextLink> createState() => _MegaMenuTextLinkState();
}

class _MegaMenuTextLinkState extends State<_MegaMenuTextLink> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lit = widget.onTap != null && (_hovered || _focused);
    final color = lit ? widget.hoverColor : widget.color;
    final text = Text(
      widget.label,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize: widget.fontSize,
        height: widget.fontSize >= 15 ? 1.35 : 1.55,
        fontWeight: widget.fontWeight,
        color: color,
        decoration: lit ? TextDecoration.underline : TextDecoration.none,
        decorationColor: color,
      ),
    );
    final content = Container(
      constraints: BoxConstraints(minHeight: widget.minHeight),
      padding: widget.padding,
      alignment: widget.minHeight > 0 ? Alignment.centerLeft : null,
      child: widget.arrow
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: text),
                const SizedBox(width: 6),
                Icon(Icons.arrow_forward_rounded, size: 16, color: color),
              ],
            )
          : text,
    );
    if (widget.onTap == null) return content;
    return Semantics(
      link: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap!();
              return null;
            },
          ),
        },
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: content,
          ),
        ),
      ),
    );
  }
}
