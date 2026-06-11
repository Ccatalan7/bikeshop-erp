import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../modules/hr/pages/kiosk_mode_page.dart';
import '../../modules/ai_assistant/widgets/ai_chat_bubble.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/storage/widgets/app_files_panel.dart';
import '../../modules/settings/services/appearance_service.dart';
import '../services/query_performance_service.dart';
import '../services/right_toolbar_service.dart';
import '../services/workspace_manager.dart';
import 'calculator_panel.dart';
import 'query_performance_gauge.dart';
import 'quick_bike_finder_panel.dart';
import 'quick_access_expense_rail.dart';
import 'quick_messages_panel.dart';
import 'quick_purchase_panel.dart';
import 'quick_sale_panel.dart';
import 'quick_supplier_messages_panel.dart';
import 'quick_task_panel.dart';
import 'right_toolbar_glass_surface.dart';

/// A Zoho Books-style right sidebar toolbar.
///
/// In its **collapsed** state it shows a narrow vertical icon bar (~48px).
/// Tapping an icon **expands** the toolbar to a resizable width, revealing the
/// selected tool's panel. A close button collapses it back.
class RightToolbar extends StatefulWidget {
  const RightToolbar({super.key});

  static const double collapsedWidth = 48.0;

  @override
  State<RightToolbar> createState() => _RightToolbarState();
}

class _RightToolbarState extends State<RightToolbar> {
  double _expandedWidth = 380.0;
  bool _isResizing = false;

  static const double _minWidth = 320.0;
  static const double _maxWidth = 600.0;
  static const double _collapsedWidth = RightToolbar.collapsedWidth;
  static const String _prefKey = 'right_toolbar_width';

  @override
  void initState() {
    super.initState();
    _loadWidth();
  }

  Future<void> _loadWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_prefKey);
    if (saved != null && mounted) {
      setState(() => _expandedWidth = saved.clamp(_minWidth, _maxWidth));
    }
  }

  Future<void> _saveWidth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefKey, _expandedWidth);
  }

  void _selectTool(ToolbarTool tool) {
    if (tool == ToolbarTool.newJob) {
      context
          .read<WorkspaceManager>()
          .navigateActiveWorkspace('/taller/pegas/nueva');
      return;
    }
    context.read<RightToolbarService>().toggleTool(tool);
  }

  void _close() {
    context.read<RightToolbarService>().close();
  }

  String _toolTitle(ToolbarTool tool) {
    switch (tool) {
      case ToolbarTool.newJob:
        return 'Nuevo Trabajo';
      case ToolbarTool.bikeFinder:
        return 'Buscador de Bicicletas';
      case ToolbarTool.aiAssistant:
        return 'Asistente IA';
      case ToolbarTool.messages:
        return 'Mensajería';
      case ToolbarTool.supplierMessages:
        return 'Proveedores';
      case ToolbarTool.storage:
        return 'Archivos';
      case ToolbarTool.kiosk:
        return 'Kiosko RRHH';
      case ToolbarTool.quickSale:
        return 'Venta Rápida';
      case ToolbarTool.expenses:
        return 'Gastos Rápidos';
      case ToolbarTool.purchases:
        return 'Compras';
      case ToolbarTool.tasks:
        return 'Tareas';
      case ToolbarTool.calculator:
        return 'Calculadora';
      case ToolbarTool.performance:
        return 'DB Gauge';
    }
  }

  IconData _toolIcon(ToolbarTool tool) {
    switch (tool) {
      case ToolbarTool.newJob:
        return Icons.build_circle_outlined;
      case ToolbarTool.bikeFinder:
        return Icons.pedal_bike_outlined;
      case ToolbarTool.aiAssistant:
        return Icons.auto_awesome;
      case ToolbarTool.messages:
        return Icons.chat_bubble_outline;
      case ToolbarTool.supplierMessages:
        return Icons.storefront_outlined;
      case ToolbarTool.storage:
        return Icons.folder_open_outlined;
      case ToolbarTool.kiosk:
        return Icons.badge_outlined;
      case ToolbarTool.quickSale:
        return Icons.flash_on;
      case ToolbarTool.expenses:
        return Icons.receipt_long_outlined;
      case ToolbarTool.purchases:
        return Icons.shopping_cart_outlined;
      case ToolbarTool.tasks:
        return Icons.task_alt;
      case ToolbarTool.calculator:
        return Icons.calculate_outlined;
      case ToolbarTool.performance:
        return Icons.speed_outlined;
    }
  }

  Widget _toolPanel(ToolbarTool tool) {
    switch (tool) {
      case ToolbarTool.newJob:
        return const SizedBox.shrink();
      case ToolbarTool.bikeFinder:
        return const QuickBikeFinderPanel();
      case ToolbarTool.aiAssistant:
        return const AIChatPanel(jobs: [], embedded: true);
      case ToolbarTool.messages:
        return const QuickMessagesPanel();
      case ToolbarTool.supplierMessages:
        return const QuickSupplierMessagesPanel();
      case ToolbarTool.storage:
        return const AppFilesPanel(compact: true, showHeader: false);
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

  int _toolBadgeCount(ToolbarTool tool, ChatProvider chatProvider) {
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
  }) {
    final badgeCount = _toolBadgeCount(tool, chatProvider);
    final badgeLabel = badgeCount > 99 ? '99+' : '$badgeCount';
    final badgeColor =
        tool == ToolbarTool.messages || tool == ToolbarTool.supplierMessages
            ? const Color(0xFF16A34A)
            : theme.colorScheme.error;
    final badgeTextColor =
        tool == ToolbarTool.messages || tool == ToolbarTool.supplierMessages
            ? Colors.white
            : theme.colorScheme.onError;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Icon(
          _toolIcon(tool),
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
                  color: theme.colorScheme.surface,
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

  List<ToolbarTool> _visibleTools(RightToolbarService toolbarService) {
    return ToolbarTool.values.where((tool) {
      if (tool == ToolbarTool.performance) {
        return QueryPerformanceService.isEnabled &&
            toolbarService.isGaugePinned;
      }
      return true;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final toolbarService = context.watch<RightToolbarService>();
    final chatProvider = context.watch<ChatProvider>();
    final appearanceService = context.watch<AppearanceService>();
    final activeTool = toolbarService.activeTool;
    final visibleTools = _visibleTools(toolbarService);
    final useToolbarPalette = appearanceService.messagingUsesSidebarPalette;
    final blurEnabled = appearanceService.rightToolbarBlurEnabled;
    final sidebarPalette = appearanceService.sidebarPalette;
    final stripTheme = useToolbarPalette
        ? buildSidebarPaletteTheme(theme, sidebarPalette)
        : theme;

    final barBorder =
        isDark ? const Color(0xFF2E2E2E) : const Color(0xFFDDE0E4);
    final activeBg = useToolbarPalette
        ? sidebarPalette.accent.withValues(alpha: 0.16)
        : isDark
            ? theme.colorScheme.primary.withValues(alpha: 0.2)
            : theme.colorScheme.primary.withValues(alpha: 0.1);

    final bool isExpanded = activeTool != null;
    final double currentWidth = isExpanded ? _expandedWidth : _collapsedWidth;

    return Stack(
      children: [
        AnimatedContainer(
          duration:
              _isResizing ? Duration.zero : const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: currentWidth,
          child: isExpanded
              ? _buildExpanded(
                  theme,
                  isDark,
                  activeTool,
                  visibleTools,
                  chatProvider,
                  appearanceService,
                )
              : RightToolbarGlassSurface(
                  tint: useToolbarPalette ? sidebarPalette.background : null,
                  blurEnabled: blurEnabled,
                  border: Border(
                    left: BorderSide(
                      color: (useToolbarPalette
                              ? sidebarPalette.border
                              : barBorder)
                          .withValues(alpha: 0.72),
                      width: 1,
                    ),
                  ),
                  child: _buildCollapsed(
                    stripTheme,
                    activeBg,
                    visibleTools,
                    chatProvider,
                  ),
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
                        .clamp(_minWidth, _maxWidth);
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
    );
  }

  /// Narrow icon column (collapsed state)
  Widget _buildCollapsed(
    ThemeData theme,
    Color activeBg,
    List<ToolbarTool> visibleTools,
    ChatProvider chatProvider,
  ) {
    return Column(
      children: [
        const SizedBox(height: 12),
        // Tool icons
        for (final tool in visibleTools)
          Tooltip(
            message: _toolTitle(tool),
            preferBelow: false,
            waitDuration: const Duration(milliseconds: 400),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _selectTool(tool),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: 40,
                  height: 40,
                  margin:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _buildToolIcon(
                    theme,
                    tool,
                    chatProvider,
                    iconSize: 22,
                    iconColor:
                        theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Expanded panel with mini icon rail + header + tool content
  Widget _buildExpanded(
    ThemeData theme,
    bool isDark,
    ToolbarTool tool,
    List<ToolbarTool> visibleTools,
    ChatProvider chatProvider,
    AppearanceService appearanceService,
  ) {
    final useToolbarPalette = appearanceService.messagingUsesSidebarPalette;
    final palette = appearanceService.sidebarPalette;
    final railTheme =
        useToolbarPalette ? buildSidebarPaletteTheme(theme, palette) : theme;
    final railBorder = useToolbarPalette
        ? palette.border
        : isDark
            ? const Color(0xFF2E2E2E)
            : const Color(0xFFDDE0E4);
    final useSidebarPalette = tool == ToolbarTool.messages &&
        appearanceService.messagingUsesSidebarPalette;
    final panelTheme =
        useSidebarPalette ? buildSidebarPaletteTheme(theme, palette) : theme;
    final panelBorderColor = useSidebarPalette
        ? palette.border
        : isDark
            ? const Color(0xFF2E2E2E)
            : const Color(0xFFDDE0E4);

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
                panelTheme,
                tool,
                chatProvider,
                iconSize: 18,
                iconColor: panelTheme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                _toolTitle(tool),
                style: panelTheme.textTheme.titleSmall?.copyWith(
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
                        color: panelTheme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
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
                      color: panelTheme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Tool content
        Expanded(child: _toolPanel(tool)),
      ],
    );

    return Row(
      children: [
        // Panel area first (left), mini rail on right edge
        Expanded(
          child: Theme(
            data: panelTheme,
            child: RightToolbarGlassSurface(
              tint: useSidebarPalette ? palette.background : null,
              blurEnabled: appearanceService.rightToolbarBlurEnabled,
              border: Border(
                left: BorderSide(
                  color: panelBorderColor.withValues(alpha: 0.72),
                  width: 1,
                ),
              ),
              child: panelContent,
            ),
          ),
        ),
        // Mini icon rail — right edge, always visible to switch tools
        Theme(
          data: railTheme,
          child: RightToolbarGlassSurface(
            tint: useToolbarPalette ? palette.background : null,
            blurEnabled: appearanceService.rightToolbarBlurEnabled,
            border: Border(
              left: BorderSide(
                color: railBorder.withValues(alpha: 0.72),
                width: 1,
              ),
            ),
            child: SizedBox(
              width: _collapsedWidth,
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  for (final t in visibleTools)
                    Tooltip(
                      message: _toolTitle(t),
                      preferBelow: false,
                      waitDuration: const Duration(milliseconds: 300),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _selectTool(t),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 4),
                            decoration: BoxDecoration(
                              color: t == tool
                                  ? railTheme.colorScheme.primary.withValues(
                                      alpha: useToolbarPalette
                                          ? 0.16
                                          : isDark
                                              ? 0.25
                                              : 0.12,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: _buildToolIcon(
                              railTheme,
                              t,
                              chatProvider,
                              iconSize: 20,
                              iconColor: t == tool
                                  ? railTheme.colorScheme.primary
                                  : railTheme.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
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
}
