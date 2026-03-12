import 'package:flutter/material.dart';
import 'calculator_panel.dart';
import 'quick_sale_panel.dart';
import 'quick_task_panel.dart';

/// The tools available in the right toolbar.
/// Add new entries here to extend the toolbar with more tools.
enum ToolbarTool {
  quickSale,
  tasks,
  calculator,
}

/// A Zoho Books-style right sidebar toolbar.
///
/// In its **collapsed** state it shows a narrow vertical icon bar (~48px).
/// Tapping an icon **expands** the toolbar to a resizable width, revealing the
/// selected tool's panel. A close button collapses it back.
class RightToolbar extends StatefulWidget {
  const RightToolbar({super.key});

  @override
  State<RightToolbar> createState() => _RightToolbarState();
}

class _RightToolbarState extends State<RightToolbar> {
  ToolbarTool? _activeTool;
  double _expandedWidth = 380.0;
  bool _isResizing = false;

  static const double _minWidth = 320.0;
  static const double _maxWidth = 600.0;
  static const double _collapsedWidth = 48.0;

  bool get _isExpanded => _activeTool != null;

  void _selectTool(ToolbarTool tool) {
    setState(() {
      if (_activeTool == tool) {
        _activeTool = null; // toggle off
      } else {
        _activeTool = tool;
      }
    });
  }

  void _close() {
    setState(() {
      _activeTool = null;
    });
  }

  String _toolTitle(ToolbarTool tool) {
    switch (tool) {
      case ToolbarTool.quickSale:
        return 'Venta Rápida';
      case ToolbarTool.tasks:
        return 'Tareas';
      case ToolbarTool.calculator:
        return 'Calculadora';
    }
  }

  IconData _toolIcon(ToolbarTool tool) {
    switch (tool) {
      case ToolbarTool.quickSale:
        return Icons.flash_on;
      case ToolbarTool.tasks:
        return Icons.task_alt;
      case ToolbarTool.calculator:
        return Icons.calculate_outlined;
    }
  }

  Widget _toolPanel(ToolbarTool tool) {
    switch (tool) {
      case ToolbarTool.quickSale:
        return const QuickSalePanel();
      case ToolbarTool.tasks:
        return const QuickTaskPanel();
      case ToolbarTool.calculator:
        return const CalculatorPanel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final barBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F1F3);
    final barBorder = isDark ? const Color(0xFF2E2E2E) : const Color(0xFFDDE0E4);
    final activeBg = isDark
        ? theme.colorScheme.primary.withOpacity(0.2)
        : theme.colorScheme.primary.withOpacity(0.1);

    final double currentWidth = _isExpanded ? _expandedWidth : _collapsedWidth;

    return Stack(
      children: [
        AnimatedContainer(
          duration: _isResizing ? Duration.zero : const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          width: currentWidth,
          decoration: BoxDecoration(
            color: barBg,
            border: Border(
              left: BorderSide(color: barBorder, width: 1),
            ),
          ),
          child: _isExpanded
              ? _buildExpanded(theme, isDark)
              : _buildCollapsed(theme, isDark, activeBg),
        ),
        // Resize handle (left edge, only when expanded)
        if (_isExpanded)
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
                    _expandedWidth =
                        (_expandedWidth - details.delta.dx).clamp(_minWidth, _maxWidth);
                  });
                },
                onHorizontalDragEnd: (_) =>
                    setState(() => _isResizing = false),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
      ],
    );
  }

  /// Narrow icon column (collapsed state)
  Widget _buildCollapsed(ThemeData theme, bool isDark, Color activeBg) {
    return Column(
      children: [
        const SizedBox(height: 12),
        // Tool icons
        for (final tool in ToolbarTool.values)
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
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _toolIcon(tool),
                    size: 22,
                    color: theme.colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Expanded panel with header + tool content
  Widget _buildExpanded(ThemeData theme, bool isDark) {
    final tool = _activeTool!;

    return Column(
      children: [
        // Header bar
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF2E2E2E) : const Color(0xFFDDE0E4),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _toolIcon(tool),
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                _toolTitle(tool),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Close button
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
                      color: theme.colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Tool content
        Expanded(
          child: _toolPanel(tool),
        ),
      ],
    );
  }
}
