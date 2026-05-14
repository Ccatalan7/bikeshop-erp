import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/workspace_manager.dart';
import '../../modules/ai_assistant/widgets/global_ai_button.dart';

/// Tab bar UI for switching between workspaces
class WorkspaceTabBar extends StatelessWidget {
  const WorkspaceTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final workspaceManager = context.watch<WorkspaceManager>();
    final theme = Theme.of(context);

    // Debug: Log workspace state
    if (!workspaceManager.isInitialized) {
      debugPrint('⚠️ [WorkspaceTabBar] WorkspaceManager not yet initialized');
    } else {
      debugPrint(
          '✅ [WorkspaceTabBar] Rendering ${workspaceManager.workspaces.length} workspace(s)');
    }

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
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
              child: Row(
                children: [
                  for (var index = 0;
                      index < workspaceManager.workspaces.length;
                      index++)
                    _WorkspaceTabDropTarget(
                      key: ValueKey(
                          'workspace-tab-target-${workspaceManager.workspaces[index].id}'),
                      targetIndex: index,
                      child: _WorkspaceTab(
                        key: ValueKey(
                            'workspace-tab-${workspaceManager.workspaces[index].id}'),
                        index: index,
                        workspace: workspaceManager.workspaces[index],
                        isActive: index == workspaceManager.activeIndex,
                        onTap: () => workspaceManager.switchToWorkspace(index),
                        onTogglePin: () =>
                            workspaceManager.toggleWorkspacePinned(index),
                        onClose: workspaceManager.workspaces.length > 1
                            ? () => workspaceManager.closeWorkspace(index)
                            : null,
                      ),
                    ),
                  _WorkspaceDropSlot(
                    targetIndex: workspaceManager.workspaces.length,
                    trailing: true,
                  ),
                ],
              ),
            ),
          ),
          const _WorkspaceNavigationControls(),
          // New tab button with dropdown menu
          if (workspaceManager.workspaces.length <
              WorkspaceManager.maxWorkspaces)
            const _NewTabDropdown(),

          // Global AI Assistant
          const GlobalAIFloatingButton(),

          // Tab counter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '${workspaceManager.workspaces.length}/${WorkspaceManager.maxWorkspaces}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceTab extends StatefulWidget {
  final int index;
  final Workspace workspace;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback? onClose;

  const _WorkspaceTab({
    super.key,
    required this.index,
    required this.workspace,
    required this.isActive,
    required this.onTap,
    required this.onTogglePin,
    this.onClose,
  });

  @override
  State<_WorkspaceTab> createState() => _WorkspaceTabState();
}

class _WorkspaceTabState extends State<_WorkspaceTab> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = widget.isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
    final showTabTools = _isHovered || widget.isActive;
    final showPinControl = showTabTools || widget.workspace.isPinned;
    final pinColor = widget.workspace.isPinned
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: widget.workspace.isPinned ? 176 : 184,
          decoration: BoxDecoration(
            color: widget.isActive
                ? theme.colorScheme.surfaceContainerHighest
                : _isHovered
                    ? theme.colorScheme.surfaceContainerHigh
                    : Colors.transparent,
            border: Border(
              right: BorderSide(
                color: theme.dividerColor,
                width: 1,
              ),
              bottom: widget.isActive
                  ? BorderSide(
                      color: theme.colorScheme.primary,
                      width: 2,
                    )
                  : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (showTabTools)
                Draggable<String>(
                  data: widget.workspace.id,
                  feedback: _WorkspaceDragPreview(
                    title: widget.workspace.title,
                    isPinned: widget.workspace.isPinned,
                  ),
                  childWhenDragging: Opacity(
                    opacity: 0.35,
                    child: _WorkspaceDragHandle(color: pinColor),
                  ),
                  child: _WorkspaceDragHandle(
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.7),
                  ),
                ),
              if (showPinControl)
                InkWell(
                  onTap: widget.onTogglePin,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      widget.workspace.isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      size: 14,
                      color: pinColor,
                    ),
                  ),
                ),
              if (widget.workspace.isPinned && !showTabTools)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 1,
                    height: 16,
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                ),
              Expanded(
                child: Text(
                  widget.workspace.title,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor,
                    fontWeight:
                        widget.isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (widget.onClose != null && showTabTools)
                InkWell(
                  onTap: widget.onClose,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: textColor,
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

class _WorkspaceTabDropTarget extends StatelessWidget {
  final int targetIndex;
  final Widget child;

  const _WorkspaceTabDropTarget({
    super.key,
    required this.targetIndex,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        context
            .read<WorkspaceManager>()
            .moveWorkspaceToIndex(details.data, targetIndex);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isHovered
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: child,
        );
      },
    );
  }
}

class _WorkspaceDropSlot extends StatelessWidget {
  final int targetIndex;
  final bool trailing;

  const _WorkspaceDropSlot({
    required this.targetIndex,
    this.trailing = false,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => true,
      onAcceptWithDetails: (details) {
        context
            .read<WorkspaceManager>()
            .moveWorkspaceToIndex(details.data, targetIndex);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: trailing ? 18 : 8,
          height: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isHovered
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
        );
      },
    );
  }
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
    final theme = Theme.of(context);

    return Container(
      height: 28,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surface,
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
            color: theme.dividerColor,
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
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          width: 30,
          height: 26,
          child: Icon(
            icon,
            size: 15,
            color: enabled
                ? theme.colorScheme.onSurface
                : theme.disabledColor.withValues(alpha: 0.55),
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
    final theme = Theme.of(context);

    return PopupMenuButton<Map<String, String>>(
      key: _menuKey,
      icon: Icon(
        Icons.add,
        size: 18,
        color: theme.colorScheme.onSurface,
      ),
      tooltip: 'New tab',
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
