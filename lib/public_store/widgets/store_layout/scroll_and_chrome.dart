part of '../public_store_layout.dart';

/// Scroll container for the non-sticky layouts.
///
/// The sticky header scaffold already manages its own ScrollController.
/// For solid/transparent layouts, we still want:
/// - restore scroll position when navigating back
/// - force scroll-to-top when user clicks "Inicio" / home
class _PublicStoreScrollView extends StatefulWidget {
  const _PublicStoreScrollView({
    super.key,
    required this.child,
    this.physics,
    this.clipBehavior = Clip.hardEdge,
  });

  final Widget child;
  final ScrollPhysics? physics;
  final Clip clipBehavior;

  @override
  State<_PublicStoreScrollView> createState() => _PublicStoreScrollViewState();
}

class _PublicStoreScrollViewState extends State<_PublicStoreScrollView> {
  final ScrollController _scrollController = ScrollController();
  String? _routeKey;
  bool _restoredForRoute = false;
  bool _isRestoringRouteScroll = false;
  int _routeRestoreGeneration = 0;
  PublicStoreScrollState? _scrollState;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final nextScrollState = context.read<PublicStoreScrollState>();
    if (!identical(_scrollState, nextScrollState)) {
      _scrollState?.scrollToTopSignal.removeListener(_onScrollToTopSignal);
      _scrollState = nextScrollState;
      _scrollState?.scrollToTopSignal.addListener(_onScrollToTopSignal);
    }

    final uri = GoRouterState.of(context).uri;
    final nextKey = websiteEditorScrollRouteKey(uri);
    if (_routeKey != nextKey) {
      _routeKey = nextKey;
      _restoredForRoute = false;
      _routeRestoreGeneration++;
    }

    if (_restoredForRoute) return;
    _restoredForRoute = true;

    final key = _routeKey;
    final path = GoRouterState.of(context).uri.path;
    final scrollState = _scrollState ?? context.read<PublicStoreScrollState>();

    final shouldScrollToTop =
        (key != null && scrollState.consumeScrollToTopRequest(key)) ||
            scrollState.consumeScrollToTopRequestForPath(path);

    if (key != null && shouldScrollToTop) {
      scrollState.clear(key);
      _restoreScrollForRoute(targetOffset: 0);
    } else {
      _restoreScrollForRoute();
    }
  }

  void _onScrollToTopSignal() {
    if (!mounted) return;
    final key = _routeKey;
    if (key == null) return;

    final scrollState = _scrollState;
    if (scrollState == null) return;

    final path = GoRouterState.of(context).uri.path;
    final shouldScrollToTop = scrollState.consumeScrollToTopRequest(key) ||
        scrollState.consumeScrollToTopRequestForPath(path);
    if (!shouldScrollToTop) return;

    scrollState.clear(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      if (_scrollController.offset <= 0) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _restoreScrollForRoute({double? targetOffset}) {
    final key = _routeKey;
    if (key == null) return;

    final offset =
        targetOffset ?? context.read<PublicStoreScrollState>().getOffset(key);
    final restoreGeneration = _routeRestoreGeneration;
    _isRestoringRouteScroll = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (restoreGeneration != _routeRestoreGeneration) return;
      if (!_scrollController.hasClients) {
        _isRestoringRouteScroll = false;
        return;
      }
      final max = _scrollController.position.maxScrollExtent;
      final clamped = offset.clamp(0.0, max);
      if ((_scrollController.offset - clamped).abs() >= 1.0) {
        _scrollController.jumpTo(clamped);
      }
      _isRestoringRouteScroll = false;
    });
  }

  void _onScroll() {
    if (_isRestoringRouteScroll) return;
    final key = _routeKey;
    if (key == null) return;
    context
        .read<PublicStoreScrollState>()
        .setOffset(key, _scrollController.offset);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollState?.scrollToTopSignal.removeListener(_onScrollToTopSignal);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      // Flutter Web can occasionally fail to repaint after route changes when
      // a scroll viewport is clipped. Disabling clipping is a pragmatic fix
      // for the "blank until resize" symptom.
      clipBehavior: kIsWeb ? Clip.none : widget.clipBehavior,
      physics: widget.physics,
      child: widget.child,
    );
  }
}

/// A stateful widget that manages the sticky header that stays fixed at top while scrolling
class _StickyHeaderScaffold extends StatefulWidget {
  final String storeName;
  final String storeDescription;
  final String logoUrl;
  final String topBannerText;
  final String contactPhone;
  final String contactEmail;
  final Color primaryColor;
  final Color accentColor;
  final String headerColorMode;
  final bool showTopBanner;
  final bool headerShadow;
  final Color headerBgColor;
  final Color headerMenuSurfaceColor;
  final Color headerMenuRailColor;
  final List<WebsiteNavigation> navItems;
  final PublicCategoryNavigationProjection categoryNavigationProjection;
  final bool isEditMode;
  final bool allowOverlayAtTop;
  final Widget Function({
    required BuildContext context,
    required String storeName,
    required String storeDescription,
    required String logoUrl,
    required String topBannerText,
    required String contactPhone,
    required String contactEmail,
    required Color primaryColor,
    required Color accentColor,
    bool isEditMode,
    String headerStyle,
    String headerColorMode,
    bool showTopBanner,
    bool headerShadow,
    Color headerBgColor,
    Color? menuSurfaceColor,
    Color? menuRailColor,
    required List<WebsiteNavigation> navItems,
    required PublicCategoryNavigationProjection categoryNavigationProjection,
    bool isOverlay,
  }) buildHeader;
  final Widget child;
  final Widget footer;

  const _StickyHeaderScaffold({
    super.key,
    required this.storeName,
    required this.storeDescription,
    required this.logoUrl,
    required this.topBannerText,
    required this.contactPhone,
    required this.contactEmail,
    required this.primaryColor,
    required this.accentColor,
    required this.headerColorMode,
    required this.showTopBanner,
    required this.headerShadow,
    required this.headerBgColor,
    required this.headerMenuSurfaceColor,
    required this.headerMenuRailColor,
    required this.navItems,
    required this.categoryNavigationProjection,
    required this.isEditMode,
    required this.allowOverlayAtTop,
    required this.buildHeader,
    required this.child,
    required this.footer,
  });

  @override
  State<_StickyHeaderScaffold> createState() => _StickyHeaderScaffoldState();
}

class _StickyHeaderScaffoldState extends State<_StickyHeaderScaffold> {
  static const double _fallbackReservedHeaderHeight = 66;

  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _headerScrollOffset = ValueNotifier<double>(0);
  final GlobalKey _headerKey = GlobalKey();
  double _reservedHeaderHeight = _fallbackReservedHeaderHeight;
  String? _routeKey;
  bool _restoredForRoute = false;
  bool _isRestoringRouteScroll = false;
  int _routeRestoreGeneration = 0;
  PublicStoreScrollState? _scrollState;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Attach once to the shared scroll state to support "scroll to top" even
    // when the route doesn't change (e.g., clicking the logo while already on
    // home).
    final nextScrollState = context.read<PublicStoreScrollState>();
    if (!identical(_scrollState, nextScrollState)) {
      _scrollState?.scrollToTopSignal.removeListener(_onScrollToTopSignal);
      _scrollState = nextScrollState;
      _scrollState?.scrollToTopSignal.addListener(_onScrollToTopSignal);
    }

    // Key scroll offset by current route location so going "back" restores where
    // the user was (most important for long lists like /productos).
    final uri = GoRouterState.of(context).uri;
    final nextKey = websiteEditorScrollRouteKey(uri);
    if (_routeKey != nextKey) {
      _routeKey = nextKey;
      _restoredForRoute = false;
      _routeRestoreGeneration++;
    }

    if (!_restoredForRoute) {
      _restoredForRoute = true;
      final key = _routeKey;
      final path = GoRouterState.of(context).uri.path;
      final scrollState =
          _scrollState ?? context.read<PublicStoreScrollState>();
      final shouldScrollToTop =
          (key != null && scrollState.consumeScrollToTopRequest(key)) ||
              scrollState.consumeScrollToTopRequestForPath(path);

      if (key != null && shouldScrollToTop) {
        // Explicit home navigation: land at top, don't restore.
        scrollState.clear(key);
        _restoreScrollForRoute(targetOffset: 0);
      } else {
        _restoreScrollForRoute();
      }
    }
  }

  void _onScrollToTopSignal() {
    if (!mounted) return;
    final key = _routeKey;
    if (key == null) return;

    final scrollState = _scrollState;
    if (scrollState == null) return;

    final path = GoRouterState.of(context).uri.path;
    final shouldScrollToTop = scrollState.consumeScrollToTopRequest(key) ||
        scrollState.consumeScrollToTopRequestForPath(path);
    if (!shouldScrollToTop) return;

    scrollState.clear(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      if (_scrollController.offset <= 0) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _headerScrollOffset.dispose();
    _scrollState?.scrollToTopSignal.removeListener(_onScrollToTopSignal);
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    // Inner routes use an always-solid header, so they need no scroll-driven
    // rebuild at all. On the overlay homepage, notify only the header subtree.
    if (widget.allowOverlayAtTop) {
      _headerScrollOffset.value = offset;
    }

    if (!_isRestoringRouteScroll) {
      final key = _routeKey;
      if (key == null) return;
      context.read<PublicStoreScrollState>().setOffset(key, offset);
    }
  }

  void _restoreScrollForRoute({double? targetOffset}) {
    final key = _routeKey;
    if (key == null) return;

    final offset =
        targetOffset ?? context.read<PublicStoreScrollState>().getOffset(key);
    final restoreGeneration = _routeRestoreGeneration;
    _isRestoringRouteScroll = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (restoreGeneration != _routeRestoreGeneration) return;
      if (!_scrollController.hasClients) {
        _isRestoringRouteScroll = false;
        return;
      }

      final max = _scrollController.position.maxScrollExtent;
      final clamped = offset.clamp(0.0, max);
      if ((_scrollController.offset - clamped).abs() >= 1.0) {
        _scrollController.jumpTo(clamped);
      }
      _isRestoringRouteScroll = false;
    });
  }

  void _scheduleHeaderMeasurement() {
    if (widget.allowOverlayAtTop) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final headerContext = _headerKey.currentContext;
      if (headerContext == null) return;

      final renderBox = headerContext.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return;

      final measuredHeight = renderBox.size.height;
      if ((measuredHeight - _reservedHeaderHeight).abs() < 0.5) return;

      setState(() {
        _reservedHeaderHeight = measuredHeight;
      });
    });
  }

  @override
  void didUpdateWidget(covariant _StickyHeaderScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.allowOverlayAtTop != widget.allowOverlayAtTop ||
        oldWidget.showTopBanner != widget.showTopBanner) {
      _scheduleHeaderMeasurement();
    }
  }

  @override
  Widget build(BuildContext context) {
    _scheduleHeaderMeasurement();
    final allowOverlayAtTop = widget.allowOverlayAtTop;

    return Stack(
      // On Flutter Web (HTML renderer especially), clipping can create DOM
      // stacking contexts that end up painting *above* later Stack children.
      // We keep this Stack unclipped so the sticky header reliably stays on top.
      clipBehavior: Clip.none,
      children: [
        // Main scrollable content
        // Main scrollable content
        ScrollConfiguration(
          behavior: widget.isEditMode
              ? const _NoDragScrollBehavior()
              : const MaterialScrollBehavior(),
          child: SingleChildScrollView(
            controller: _scrollController,
            // Avoid clip-induced z-order issues on Web where the scroll viewport
            // can end up above the sticky header.
            clipBehavior: kIsWeb ? Clip.none : Clip.hardEdge,
            child: Column(
              children: [
                if (!allowOverlayAtTop) SizedBox(height: _reservedHeaderHeight),
                widget.child,
                widget.footer,
              ],
            ),
          ),
        ),
        // Floating header
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<double>(
            valueListenable: _headerScrollOffset,
            builder: (context, scrollOffset, _) {
              // Calculate header opacity based on scroll (0 = transparent,
              // 1 = solid). Only this header subtree rebuilds while scrolling.
              final headerOpacity = allowOverlayAtTop
                  ? (scrollOffset / 100).clamp(0.0, 1.0)
                  : 1.0;
              final isScrolled = allowOverlayAtTop && scrollOffset > 50;
              final effectiveColorMode = allowOverlayAtTop && isScrolled
                  ? 'light'
                  : widget.headerColorMode;
              final effectiveBgColor = allowOverlayAtTop
                  ? (isScrolled
                      ? widget.headerBgColor
                      : widget.headerBgColor.withValues(alpha: headerOpacity))
                  : widget.headerBgColor;

              return KeyedSubtree(
                key: _headerKey,
                child: widget.buildHeader(
                  context: context,
                  storeName: widget.storeName,
                  storeDescription: widget.storeDescription,
                  logoUrl: widget.logoUrl,
                  topBannerText: widget.topBannerText,
                  contactPhone: widget.contactPhone,
                  contactEmail: widget.contactEmail,
                  primaryColor: widget.primaryColor,
                  accentColor: widget.accentColor,
                  isEditMode: widget.isEditMode,
                  headerStyle: 'transparent',
                  headerColorMode: effectiveColorMode,
                  showTopBanner: allowOverlayAtTop
                      ? widget.showTopBanner && !isScrolled
                      : widget.showTopBanner,
                  headerShadow: allowOverlayAtTop
                      ? widget.headerShadow && isScrolled
                      : widget.headerShadow,
                  headerBgColor: effectiveBgColor,
                  menuSurfaceColor: widget.headerMenuSurfaceColor,
                  menuRailColor: widget.headerMenuRailColor,
                  navItems: widget.navItems,
                  categoryNavigationProjection:
                      widget.categoryNavigationProjection,
                  isOverlay: allowOverlayAtTop && !isScrolled,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// CMS mode action without a Material ink feature.
///
/// Edit/Preview replaces the editor viewport after activation. A regular
/// ElevatedButton leaves an ink decoration attached to the old Scaffold for a
/// few frames, which can try to paint against a detached RenderPadding on
/// Flutter desktop. This control keeps the same professional interaction and
/// keyboard semantics without retaining paint state outside its own subtree.
class _CmsModeButton extends StatefulWidget {
  const _CmsModeButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_CmsModeButton> createState() => _CmsModeButtonState();
}

class _CmsModeButtonState extends State<_CmsModeButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = !_enabled
        ? Colors.white.withValues(alpha: 0.16)
        : _pressed
            ? Colors.red.shade800
            : _hovered
                ? Colors.red.shade500
                : Colors.red.shade600;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: FocusableActionDetector(
        enabled: _enabled,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        onShowHoverHighlight: (value) {
          if (_hovered != value && mounted) {
            setState(() => _hovered = value);
          }
        },
        onShowFocusHighlight: (value) {
          if (_focused != value && mounted) {
            setState(() => _focused = value);
          }
        },
        child: MouseRegion(
          cursor:
              _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            onTapDown: _enabled ? (_) => _setPressed(true) : null,
            onTapUp: _enabled ? (_) => _setPressed(false) : null,
            onTapCancel: _enabled ? () => _setPressed(false) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(4),
                border: _focused
                    ? Border.all(color: Colors.white, width: 1.5)
                    : null,
              ),
              child: Text(
                widget.label,
                style: TextStyle(
                  color: _enabled ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoDragScrollBehavior extends MaterialScrollBehavior {
  const _NoDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.unknown,
      };
}

/// Payment badge widget for footer - displays payment method icons
/// The only payment claims this storefront can make.
///
/// Deliberately limited to what `PublicCheckoutCapabilities` can actually
/// confirm. Card networks are absent by design: the server contract exposes
/// `mercadopago` and `transfer` only, so a Visa/Mastercard/Redcompra badge
/// could never be backed by evidence — it would be inferred from the mere
/// presence of a card processor, which is exactly the invented claim this
/// surface exists to prevent.
const Map<PublicCheckoutPaymentCode, ({String label, String? imageUrl})>
    kPublicStorePaymentClaims = {
  PublicCheckoutPaymentCode.mercadopago: (
    label: 'MercadoPago',
    imageUrl:
        'https://xzdvtzdqjeyqxnkqprtf.supabase.co/storage/v1/object/public/vinabike-assets/payment-icons/mercadopago.svg',
  ),
  // Bank transfer has no third-party mark to display, so it is stated with
  // this application's own generic icon and wording.
  PublicCheckoutPaymentCode.transfer: (
    label: 'Transferencia bancaria',
    imageUrl: null,
  ),
};

/// Projects the server-confirmed methods into footer claims.
///
/// A `null` capability set means loading or failed — both are *unknown*, and
/// unknown must show nothing rather than a stale or optimistic list.
@visibleForTesting
List<PublicCheckoutPaymentCode> resolvePublicPaymentClaims(
  PublicCheckoutCapabilities? capabilities,
) {
  if (capabilities == null) return const <PublicCheckoutPaymentCode>[];
  return capabilities.availableMethods
      .where(kPublicStorePaymentClaims.containsKey)
      .toList(growable: false);
}

/// A confirmed method that has no third-party mark to display.
///
/// Bank transfer is stated with this application's own icon and wording so the
/// claim stays generic and owned, never borrowing a bank's identity.
class _GenericPaymentClaim extends StatelessWidget {
  const _GenericPaymentClaim({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_balance_outlined,
              size: 15,
              color: Colors.white70,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  final String name;
  final String imageUrl;
  final bool isSvg;

  const _PaymentBadge({
    required this.name,
    required this.imageUrl,
    this.isSvg = false,
  });

  @override
  Widget build(BuildContext context) {
    // MercadoPago and Redcompra logos render naturally smaller due to aspect ratio,
    // so we give them size boosts to visually match the other logos.
    double height = 40;
    double maxWidth = 100;

    if (name == 'MercadoPago') {
      height = 60;
      maxWidth = 150;
    } else if (name == 'Redcompra') {
      height = 48;
      maxWidth = 120;
    }

    return Tooltip(
      message: name,
      child: Container(
        height: height,
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: isSvg
            ? SvgPicture.network(
                imageUrl,
                fit: BoxFit.contain,
                placeholderBuilder: (_) => const SizedBox.shrink(),
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            : Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const SizedBox.shrink();
                },
              ),
      ),
    );
  }
}
