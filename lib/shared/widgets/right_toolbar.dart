import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../modules/hr/pages/kiosk_mode_page.dart';
import '../../modules/ai_assistant/services/ai_assistant_context_service.dart';
import '../../modules/ai_assistant/widgets/ai_chat_bubble.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/storage/widgets/app_files_panel.dart';
import '../../modules/settings/services/appearance_service.dart';
import '../services/notification_service.dart';
import '../services/query_performance_service.dart';
import '../services/desktop_update_service.dart';
import '../services/current_user_profile_service.dart';
import '../services/right_toolbar_service.dart';
import '../services/workspace_manager.dart';
import '../themes/vinabike_theme_roles.dart';
import 'calculator_panel.dart';
import 'notifications_panel.dart';
import 'query_performance_gauge.dart';
import 'quick_bike_finder_panel.dart';
import 'quick_access_expense_rail.dart';
import 'quick_messages_panel.dart';
import 'quick_purchase_panel.dart';
import 'quick_sale_panel.dart';
import 'quick_supplier_messages_panel.dart';
import 'quick_task_panel.dart';
import 'right_toolbar_glass_surface.dart';
import 'toolbar_tool_presentation.dart';

enum RightToolbarPresentation {
  desktopRail,
  compactWorkspace,
}

/// A Zoho Books-style right sidebar toolbar.
///
/// In its **collapsed** state it shows a narrow vertical icon bar (~48px).
/// Tapping an icon **expands** the toolbar to a resizable width, revealing the
/// selected tool's panel. A close button collapses it back.
class RightToolbar extends StatefulWidget {
  const RightToolbar({
    super.key,
    this.presentation = RightToolbarPresentation.desktopRail,
  });

  const RightToolbar.compactWorkspace({super.key})
      : presentation = RightToolbarPresentation.compactWorkspace;

  static const double collapsedWidth = 48.0;

  final RightToolbarPresentation presentation;

  @override
  State<RightToolbar> createState() => _RightToolbarState();
}

class _RightToolbarState extends State<RightToolbar> {
  double _expandedWidth = 380.0;
  bool _isResizing = false;
  late final Map<ToolbarTool, GlobalKey> _panelKeys = {
    for (final tool in ToolbarTool.values)
      tool: GlobalKey(debugLabel: 'right-toolbar-panel-${tool.name}'),
  };

  static const double _minWidth = 320.0;
  static const double _absoluteMaxWidth = 1600.0;
  static const double _maxWindowFraction = 0.82;
  static const double _fileRunnerPreferredWidth = 640.0;
  static const double _collapsedWidth = RightToolbar.collapsedWidth;
  static const String _prefKey = 'right_toolbar_width';

  @override
  void initState() {
    super.initState();
    _loadWidth();
    NotificationService()
        .unreadNotificationsCount
        .addListener(_onUnreadNotificationsChanged);
  }

  @override
  void dispose() {
    NotificationService()
        .unreadNotificationsCount
        .removeListener(_onUnreadNotificationsChanged);
    super.dispose();
  }

  void _onUnreadNotificationsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_prefKey);
    if (saved != null && mounted) {
      setState(
        () => _expandedWidth =
            saved.clamp(_minWidth, _absoluteMaxWidth).toDouble(),
      );
    }
  }

  double _effectiveMaxWidth(BuildContext context) {
    final windowLimit = MediaQuery.sizeOf(context).width * _maxWindowFraction;
    return windowLimit.clamp(_minWidth, _absoluteMaxWidth).toDouble();
  }

  Future<void> _saveWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey, _expandedWidth);
  }

  void _selectTool(ToolbarTool tool) {
    final presentation = tool.toolbarPresentation;
    final route = presentation.route;
    if (route != null) {
      context.read<WorkspaceManager>().navigateActiveWorkspace(route);
      return;
    }
    final toolbarService = context.read<RightToolbarService>();
    if (tool == ToolbarTool.fileRunner &&
        toolbarService.activeTool != tool &&
        _expandedWidth < _fileRunnerPreferredWidth) {
      setState(
        () => _expandedWidth = _fileRunnerPreferredWidth
            .clamp(_minWidth, _effectiveMaxWidth(context))
            .toDouble(),
      );
    }
    toolbarService.toggleTool(tool);
  }

  void _close() {
    context.read<RightToolbarService>().close();
  }

  Widget _toolPanel(ToolbarTool tool) {
    switch (tool) {
      case ToolbarTool.notifications:
        return const NotificationsToolbarPanel();
      case ToolbarTool.newJob:
        return const SizedBox.shrink();
      case ToolbarTool.bikeFinder:
        return const QuickBikeFinderPanel();
      case ToolbarTool.aiAssistant:
        final aiContext = context.watch<AIAssistantContextService>();
        final useJobsContext = aiContext.hasVisibleJobsContext;
        debugPrint(
          '[AI_CTX][RightToolbar.aiPanel] contextId=${identityHashCode(aiContext)} '
          'hasContext=${aiContext.hasVisibleJobsContext} '
          'useJobsContext=$useJobsContext count=${aiContext.visibleJobs.length} '
          'scope="${aiContext.visibleJobsScopeLabel}" '
          'jobs=[${aiContext.visibleJobs.take(12).map((job) => job.jobNumber ?? job.id ?? 'sin-numero').join(', ')}]',
        );
        return AIChatPanel(
          jobs: useJobsContext ? aiContext.visibleJobs : const [],
          embedded: true,
          jobsAreCurrentView: useJobsContext,
          jobsScopeLabel:
              useJobsContext ? aiContext.visibleJobsScopeLabel : null,
        );
      case ToolbarTool.messages:
        return const QuickMessagesPanel();
      case ToolbarTool.supplierMessages:
        return const QuickSupplierMessagesPanel();
      case ToolbarTool.storage:
        return const AppFilesPanel(compact: true, showHeader: false);
      case ToolbarTool.fileRunner:
        return const AppFilesPanel(
          compact: true,
          showHeader: false,
          runnerMode: true,
        );
      case ToolbarTool.kiosk:
        return const KioskModePage(
          embedded: true,
          compact: true,
        );
      case ToolbarTool.quickSale:
        return const QuickSalePanel();
      case ToolbarTool.expenses:
        return const QuickAccessExpenseRail(embedded: true);
      case ToolbarTool.purchases:
        return const QuickPurchasePanel();
      case ToolbarTool.tasks:
        return const QuickTaskPanel();
      case ToolbarTool.calculator:
        return const CalculatorPanel();
      case ToolbarTool.performance:
        return const QueryPerformanceToolbarPanel();
    }
  }

  Widget _stableToolPanel(ToolbarTool tool) {
    return KeyedSubtree(
      key: _panelKeys[tool],
      child: _toolPanel(tool),
    );
  }

  int _toolBadgeCount(ToolbarTool tool, ChatProvider chatProvider) {
    if (tool == ToolbarTool.notifications) {
      return NotificationService().unreadNotificationsCount.value;
    }
    if (tool == ToolbarTool.messages) {
      return chatProvider.conversations.fold(0, (sum, conversation) {
        if (conversation.isSupplierConversation) return sum;
        if (conversation.type == 'support' &&
            conversation.status == 'pending') {
          return sum +
              (conversation.unreadCount > 0 ? conversation.unreadCount : 1);
        }
        return sum + conversation.unreadCount;
      });
    }
    if (tool == ToolbarTool.supplierMessages) {
      return chatProvider.conversations.fold(0, (sum, conversation) {
        if (!conversation.isSupplierConversation) return sum;
        if (conversation.type == 'support' &&
            conversation.status == 'pending') {
          return sum +
              (conversation.unreadCount > 0 ? conversation.unreadCount : 1);
        }
        return sum + conversation.unreadCount;
      });
    }
    return 0;
  }

  Widget _buildToolIcon(
    ThemeData theme,
    ToolbarTool tool,
    ChatProvider chatProvider, {
    required double iconSize,
    required Color iconColor,
    required Color badgeBorderColor,
  }) {
    final badgeCount = _toolBadgeCount(tool, chatProvider);
    final badgeLabel = badgeCount > 99 ? '99+' : '$badgeCount';
    final roles = VinabikeThemeRoles.maybeOf(context);
    final badgeColor =
        tool == ToolbarTool.messages || tool == ToolbarTool.supplierMessages
            ? roles?.success.accent ?? theme.colorScheme.tertiary
            : theme.colorScheme.error;
    final badgeTextColor =
        tool == ToolbarTool.messages || tool == ToolbarTool.supplierMessages
            ? roles?.success.onAccent ?? theme.colorScheme.onTertiary
            : theme.colorScheme.onError;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(
          tool.toolbarPresentation.icon,
          size: iconSize,
          color: iconColor,
        ),
        if (badgeCount > 0)
          Positioned(
            right: -5,
            top: -5,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: badgeBorderColor,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: badgeColor.withValues(alpha: 0.24),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                badgeLabel,
                style: TextStyle(
                  color: badgeTextColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final toolbarService = context.watch<RightToolbarService>();
    final profileService = context.watch<CurrentUserProfileService?>();
    final canManageHr = profileService != null &&
        !profileService.isLoading &&
        profileService.loadIssue == null &&
        profileService.profile?.canManageUsers == true;
    final requestedTool = toolbarService.activeTool;
    final activeTool = requestedTool == ToolbarTool.kiosk && !canManageHr
        ? null
        : requestedTool;

    if (widget.presentation == RightToolbarPresentation.compactWorkspace) {
      if (activeTool == null || !activeTool.toolbarPresentation.opensPanel) {
        return const SizedBox.shrink();
      }
      return _buildCompactWorkspace(activeTool);
    }

    final theme = Theme.of(context);
    final desktopUpdateService = context.watch<DesktopUpdateService>();
    final chatProvider = context.watch<ChatProvider>();
    final appearanceService = context.watch<AppearanceService>();
    final visibleTools = resolveVisibleToolbarTools(
      canManageHr: canManageHr,
      performanceEnabled: QueryPerformanceService.isEnabled,
      performancePinned: toolbarService.isGaugePinned,
    );
    final blurEnabled = appearanceService.rightToolbarBlurEnabled;
    final isDark = theme.brightness == Brightness.dark;
    final railSurface = isDark
        ? theme.colorScheme.surfaceContainerLow
        : theme.colorScheme.surface;
    final railEdge = theme.colorScheme.outlineVariant;

    final bool isExpanded = activeTool != null;
    final effectiveMaxWidth = _effectiveMaxWidth(context);
    final double currentWidth = isExpanded
        ? _expandedWidth.clamp(_minWidth, effectiveMaxWidth).toDouble()
        : _collapsedWidth;

    return AnimatedContainer(
      duration: _isResizing ? Duration.zero : const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: currentWidth,
      child: Stack(
        fit: StackFit.expand,
        children: [
          isExpanded
              ? _buildExpanded(
                  theme,
                  activeTool,
                  visibleTools,
                  chatProvider,
                  desktopUpdateService,
                  appearanceService,
                  railSurface: railSurface,
                  railEdge: railEdge,
                )
              : RightToolbarGlassSurface(
                  key: const ValueKey('right-toolbar-collapsed-surface'),
                  tint: railSurface,
                  blurEnabled: blurEnabled,
                  border: Border(
                    left: BorderSide(
                      color: railEdge,
                      width: 1,
                    ),
                  ),
                  child: _buildCollapsed(
                    theme,
                    railSurface,
                    visibleTools,
                    chatProvider,
                    desktopUpdateService,
                  ),
                ),
          // Resize handle (left edge, only when expanded)
          if (isExpanded)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 8,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) =>
                      setState(() => _isResizing = true),
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _expandedWidth = (_expandedWidth - details.delta.dx)
                          .clamp(_minWidth, effectiveMaxWidth)
                          .toDouble();
                    });
                  },
                  onHorizontalDragEnd: (_) {
                    setState(() => _isResizing = false);
                    _saveWidth();
                  },
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactWorkspace(ToolbarTool tool) {
    final theme = Theme.of(context);
    final presentation = tool.toolbarPresentation;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Semantics(
        container: true,
        label: '${presentation.title}, herramienta',
        child: Material(
          color: theme.colorScheme.surface,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 56,
                  padding: const EdgeInsets.only(left: 4, right: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        key: const ValueKey('right-toolbar-compact-back'),
                        tooltip: 'Volver',
                        onPressed: _close,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            presentation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _stableToolPanel(tool)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Narrow icon column (collapsed state)
  Widget _buildCollapsed(
    ThemeData theme,
    Color railSurface,
    List<ToolbarTool> visibleTools,
    ChatProvider chatProvider,
    DesktopUpdateService desktopUpdateService,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (desktopUpdateService.hasDismissedReadyUpdate)
            _buildDismissedUpdateIcon(
              theme,
              desktopUpdateService,
            ),
          // Tool icons
          for (final tool in visibleTools)
            Tooltip(
              message: tool.toolbarPresentation.title,
              preferBelow: false,
              waitDuration: const Duration(milliseconds: 400),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _selectTool(tool),
                  borderRadius: BorderRadius.circular(8),
                  hoverColor:
                      theme.colorScheme.onSurface.withValues(alpha: 0.06),
                  focusColor: theme.colorScheme.primary.withValues(alpha: 0.12),
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _buildToolIcon(
                      theme,
                      tool,
                      chatProvider,
                      iconSize: 22,
                      iconColor: theme.colorScheme.onSurfaceVariant,
                      badgeBorderColor: railSurface,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Expanded panel with mini icon rail + header + tool content
  Widget _buildExpanded(
    ThemeData theme,
    ToolbarTool tool,
    List<ToolbarTool> visibleTools,
    ChatProvider chatProvider,
    DesktopUpdateService desktopUpdateService,
    AppearanceService appearanceService, {
    required Color railSurface,
    required Color railEdge,
  }) {
    final panelBorderColor = theme.colorScheme.outlineVariant;
    final panelSurface = theme.brightness == Brightness.dark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.surface;

    final panelContent = Column(
      children: [
        // Header bar
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: panelBorderColor),
            ),
          ),
          child: Row(
            children: [
              _buildToolIcon(
                theme,
                tool,
                chatProvider,
                iconSize: 18,
                iconColor: theme.colorScheme.primary,
                badgeBorderColor: panelSurface,
              ),
              const SizedBox(width: 8),
              Text(
                tool.toolbarPresentation.title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (tool == ToolbarTool.performance)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context
                        .read<RightToolbarService>()
                        .unpinGaugeFromToolbar(),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.push_pin_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _close,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Tool content
        Expanded(child: _stableToolPanel(tool)),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Panel area first (left), mini rail on right edge
        Expanded(
          child: RightToolbarGlassSurface(
            key: const ValueKey('right-toolbar-panel-surface'),
            tint: panelSurface,
            blurEnabled: appearanceService.rightToolbarBlurEnabled,
            border: Border(
              left: BorderSide(
                color: panelBorderColor,
                width: 1,
              ),
            ),
            child: panelContent,
          ),
        ),
        // Mini icon rail — right edge, always visible to switch tools
        RightToolbarGlassSurface(
          key: const ValueKey('right-toolbar-expanded-rail-surface'),
          tint: railSurface,
          blurEnabled: appearanceService.rightToolbarBlurEnabled,
          border: Border(
            left: BorderSide(
              color: railEdge,
              width: 1,
            ),
          ),
          child: SizedBox(
            width: _collapsedWidth,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (desktopUpdateService.hasDismissedReadyUpdate)
                    _buildDismissedUpdateIcon(
                      theme,
                      desktopUpdateService,
                    ),
                  for (final t in visibleTools)
                    Tooltip(
                      message: t.toolbarPresentation.title,
                      preferBelow: false,
                      waitDuration: const Duration(milliseconds: 300),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _selectTool(t),
                          borderRadius: BorderRadius.circular(8),
                          hoverColor: theme.colorScheme.onSurface
                              .withValues(alpha: 0.06),
                          focusColor:
                              theme.colorScheme.primary.withValues(alpha: 0.12),
                          child: Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 4,
                            ),
                            decoration: BoxDecoration(
                              color: t == tool
                                  ? theme.colorScheme.primaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              border: t == tool
                                  ? Border.all(
                                      color: theme.colorScheme.primary,
                                    )
                                  : null,
                            ),
                            child: _buildToolIcon(
                              theme,
                              t,
                              chatProvider,
                              iconSize: 20,
                              iconColor: t == tool
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                              badgeBorderColor: railSurface,
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
      ],
    );
  }

  Widget _buildDismissedUpdateIcon(
    ThemeData theme,
    DesktopUpdateService desktopUpdateService,
  ) {
    final accent = theme.colorScheme.primary;
    final boundary = theme.colorScheme.surfaceContainerLow;
    return Tooltip(
      message: 'Actualizacion lista',
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 300),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: desktopUpdateService.revealAvailableUpdate,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: accent.withValues(alpha: 0.32),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.system_update_alt_rounded,
                  size: 21,
                  color: accent,
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: boundary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
