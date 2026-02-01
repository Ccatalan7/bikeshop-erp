import 'dart:async';
import 'package:flutter/material.dart';
import '../../modules/website/models/website_page_models.dart';

// ============================================================================
// MEGA MENU CONSTANTS - Fox Racing Style
// ============================================================================

/// Rich Black - used for BOTH header background on hover AND mega menu panel
/// This creates a seamless unified look with no color seam between header and menu
const Color kMegaMenuPanelColor = Color(0xFF000000);

// ============================================================================
// MEGA MENU STATE CONTROLLER
// Used to communicate mega menu open state to the header
// ============================================================================

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
// 1. Solid background color (NOT opacity!) when menu is open - #111111
// 2. High z-index so it sits on top of hero images
// 3. Logo color inversion when dark background is active
// ============================================================================

class MegaMenuHeaderWrapper extends StatefulWidget {
  final Widget child;
  final double? fixedTop;

  const MegaMenuHeaderWrapper({
    super.key,
    required this.child,
    this.fixedTop,
  });

  @override
  State<MegaMenuHeaderWrapper> createState() => _MegaMenuHeaderWrapperState();
}

class _MegaMenuHeaderWrapperState extends State<MegaMenuHeaderWrapper> {
  @override
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

    // Get bottom coordinate in global space
    // If fixedTop is provided (e.g. for Sticky Header in Editor with known offset), use it.
    // Otherwise rely on localToGlobal (which can be flaky with some transforms/stacks).
    final position = renderBox.localToGlobal(Offset.zero);

    // We expect the header to be at 'fixedTop' (e.g. 48 or 0).
    // If localToGlobal reports something else (e.g. 70.4), we prefer the explicit fixedTop
    // to ensure the menu snaps TIGHTLY to the header.
    final effectiveTop = widget.fixedTop ?? position.dy;
    final bottom = effectiveTop + renderBox.size.height;

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
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            color: isOpen ? kMegaMenuPanelColor : Colors.transparent,
          ),
        ),
        // Child content - always at full opacity
        widget.child,
      ],
    );
  }
}

// ============================================================================
// MEGA MENU INVERTED LOGO
// Widget that inverts logo color when mega menu is open
// ============================================================================

class MegaMenuInvertedLogo extends StatefulWidget {
  final Widget child;

  const MegaMenuInvertedLogo({
    super.key,
    required this.child,
  });

  @override
  State<MegaMenuInvertedLogo> createState() => _MegaMenuInvertedLogoState();
}

class _MegaMenuInvertedLogoState extends State<MegaMenuInvertedLogo> {
  @override
  void initState() {
    super.initState();
    MegaMenuController.instance.addListener(_onMenuStateChange);
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

    // Invert colors to white when menu is open
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: ColorFiltered(
        colorFilter: isOpen
            ? const ColorFilter.matrix(<double>[
                -1,
                0,
                0,
                0,
                255,
                0,
                -1,
                0,
                0,
                255,
                0,
                0,
                -1,
                0,
                255,
                0,
                0,
                0,
                1,
                0,
              ])
            : const ColorFilter.mode(
                Colors.transparent,
                BlendMode.dst,
              ),
        child: widget.child,
      ),
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
  final Function(String href, bool openInNewTab) onNavigate;

  const MegaMenuButton({
    super.key,
    required this.parent,
    required this.children,
    required this.isEditMode,
    required this.textColor,
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
  Timer? _closeTimer;
  final GlobalKey _buttonKey = GlobalKey();

  String get _menuId =>
      widget.parent.id.isNotEmpty ? widget.parent.id : widget.parent.label;

  @override
  void dispose() {
    _closeTimer?.cancel();
    _forceRemoveOverlay();
    super.dispose();
  }

  void _forceRemoveOverlay() {
    _overlayEntry?.remove();
    _overlayEntry?.dispose();
    _overlayEntry = null;
  }

  void _openMenu() {
    if (widget.isEditMode || _isOpen) return;
    _closeTimer?.cancel();

    final overlayState = Overlay.of(context);
    final screenSize = MediaQuery.of(context).size;

    // Get precise button position
    final RenderBox? renderBox =
        _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;

    final buttonBottom = buttonPosition.dy + buttonSize.height;

    // Panel placement: Prefer exact Header Bottom, fallback to Button Bottom
    double panelTop;
    double bridgeHeight = 0.0;

    if (MegaMenuController.instance.headerBottom != null) {
      // Exact match with header bottom
      panelTop = MegaMenuController.instance.headerBottom!;
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
          screenWidth: screenSize.width,
          screenHeight: screenSize.height,
          panelTop: panelTop,
          bridgeHeight: bridgeHeight,
          children: widget.children,
          onEnter: () {
            _isHoveringPanel = true;
            _closeTimer?.cancel();
          },
          onExit: () {
            _isHoveringPanel = false;
            _scheduleClose();
          },
          onClose: _closeMenu,
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

  void _closeMenu({bool force = false}) {
    // Only close if we are truly not hovering anything
    if (!force && (_isHoveringButton || _isHoveringPanel)) return;

    _closeTimer?.cancel();
    _forceRemoveOverlay();
    MegaMenuController.instance.closeMenu();
    if (mounted) {
      setState(() => _isOpen = false);
    }
  }

  void _scheduleClose() {
    _closeTimer?.cancel();
    // 150ms delay is enough to move mouse across small gaps without flickering,
    // but fast enough to feel responsive when actually leaving.
    _closeTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _closeMenu();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isEditMode) {
      return _buildButtonContent();
    }

    // CLICK-ONLY: No hover triggers, menu opens/closes on click
    return GestureDetector(
      key: _buttonKey,
      onTap: () {
        if (_isOpen) {
          // Force close
          _isHoveringButton = false;
          _isHoveringPanel = false;
          _closeMenu();
        } else {
          _openMenu();
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: _buildButtonContent(),
      ),
    );
  }

  Widget _buildButtonContent() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.parent.label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _isOpen ? Colors.white : widget.textColor,
                  letterSpacing: 0.3,
                ),
          ),
          const SizedBox(width: 4),
          AnimatedRotation(
            duration: const Duration(milliseconds: 250),
            turns: _isOpen ? -0.5 : 0,
            child: Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: _isOpen ? Colors.white : widget.textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _MegaMenuOverlay extends StatefulWidget {
  final double screenWidth;
  final double screenHeight;
  final double panelTop;
  final List<WebsiteNavigation> children;
  final VoidCallback onEnter;
  final VoidCallback onExit;
  final VoidCallback onClose;
  final Function(String href, bool openInNewTab) onNavigate;
  final double bridgeHeight;

  const _MegaMenuOverlay({
    required this.screenWidth,
    required this.screenHeight,
    required this.panelTop,
    required this.bridgeHeight,
    required this.children,
    required this.onEnter,
    required this.onExit,
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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _opacity = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // BACKDROP
        Positioned(
          top: widget.panelTop,
          left: 0,
          right: 0,
          bottom: 0,
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: FadeTransition(
              opacity: _opacity,
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),

        // PANEL POSITIONED
        // Positioned at [panelTop - bridgeHeight] so the mouse region starts
        // right at the button bottom, bridging the gap.
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
                // Invisible bridge to sustain hover state
                SizedBox(height: widget.bridgeHeight),
                // The Visual Panel
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return Transform.translate(
                      // Visual offset -2px (increased from -1) to FORCE overlap and kill gap
                      offset: const Offset(0, -2.0),
                      child: Opacity(
                        opacity: _opacity.value,
                        child: child,
                      ),
                    );
                  },
                  child: Material(
                    color: kMegaMenuPanelColor,
                    child: Container(
                      width: widget.screenWidth,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 40,
                      ),
                      child: _buildColumnsLayout(context),
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

  Widget _buildColumnsLayout(BuildContext context) {
    List<WebsiteNavigation> displayColumns = widget.children;

    if (displayColumns.length == 1 &&
        displayColumns.first.children.isNotEmpty) {
      displayColumns = displayColumns.first.children;
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Wrap(
          spacing: 48,
          runSpacing: 32,
          alignment: WrapAlignment.start,
          children: displayColumns.map((column) {
            return SizedBox(
              width: 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _MegaMenuColumnHeader(
                    label: column.label,
                    onTap: () => widget.onNavigate(
                        column.href ?? '/', column.openInNewTab),
                  ),
                  const SizedBox(height: 16),
                  if (column.children.isNotEmpty) ...[
                    ...column.children.map((child) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _MegaMenuLink(
                            label: child.label.toUpperCase(),
                            isAccent: true,
                            onTap: () => widget.onNavigate(
                                child.href ?? '/', child.openInNewTab),
                          ),
                        )),
                  ] else ...[
                    _MegaMenuLink(
                      label: 'VER ${column.label.toUpperCase()}',
                      isAccent: true,
                      onTap: () => widget.onNavigate(
                          column.href ?? '/', column.openInNewTab),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ============================================================================
// COLUMN HEADER & LINK (Helper Widgets)
// ============================================================================

class _MegaMenuColumnHeader extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _MegaMenuColumnHeader({
    required this.label,
    required this.onTap,
  });

  @override
  State<_MegaMenuColumnHeader> createState() => _MegaMenuColumnHeaderState();
}

class _MegaMenuColumnHeaderState extends State<_MegaMenuColumnHeader> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            color: _isHovered ? primaryColor : Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
          child: Text(widget.label.toUpperCase()),
        ),
      ),
    );
  }
}

class _MegaMenuLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool isAccent;

  const _MegaMenuLink({
    required this.label,
    required this.onTap,
    this.isAccent = false,
  });

  @override
  State<_MegaMenuLink> createState() => _MegaMenuLinkState();
}

class _MegaMenuLinkState extends State<_MegaMenuLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor =
        widget.isAccent ? theme.primaryColor : const Color(0xFF888888);
    final hoverColor =
        widget.isAccent ? theme.colorScheme.primaryContainer : Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            color: _isHovered ? hoverColor : accentColor,
            fontSize: 13,
            fontWeight: widget.isAccent ? FontWeight.w600 : FontWeight.normal,
            height: 1.4,
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}
