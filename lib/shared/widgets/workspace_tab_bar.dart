import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/workspace_manager.dart';

/// Tab bar UI for switching between workspaces
class WorkspaceTabBar extends StatelessWidget {
  const WorkspaceTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    final workspaceManager = context.watch<WorkspaceManager>();
    final theme = Theme.of(context);
    
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
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: workspaceManager.workspaces.length,
              itemBuilder: (context, index) {
                final workspace = workspaceManager.workspaces[index];
                final isActive = index == workspaceManager.activeIndex;
                
                return _WorkspaceTab(
                  workspace: workspace,
                  isActive: isActive,
                  onTap: () => workspaceManager.switchToWorkspace(index),
                  onClose: workspaceManager.workspaces.length > 1
                      ? () => workspaceManager.closeWorkspace(index)
                      : null,
                );
              },
            ),
          ),
          // New tab button with dropdown menu
          if (workspaceManager.workspaces.length < WorkspaceManager.maxWorkspaces)
            _NewTabDropdown(),
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
  final Workspace workspace;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _WorkspaceTab({
    required this.workspace,
    required this.isActive,
    required this.onTap,
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
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 120,
            maxWidth: 200,
          ),
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
              Expanded(
                child: Text(
                  widget.workspace.title,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor,
                    fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              if (widget.onClose != null && (_isHovered || widget.isActive))
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

class _NewTabDropdown extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return PopupMenuButton<Map<String, String>>(
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
        PopupMenuItem(
          value: {'title': 'Dashboard', 'route': '/dashboard'},
          child: const Row(
            children: [
              Icon(Icons.dashboard, size: 18),
              SizedBox(width: 12),
              Text('Dashboard'),
            ],
          ),
        ),
        PopupMenuItem(
          value: {'title': 'Productos', 'route': '/inventory/products'},
          child: const Row(
            children: [
              Icon(Icons.shopping_bag, size: 18),
              SizedBox(width: 12),
              Text('Productos'),
            ],
          ),
        ),
        PopupMenuItem(
          value: {'title': 'Ventas', 'route': '/sales/invoices'},
          child: const Row(
            children: [
              Icon(Icons.receipt, size: 18),
              SizedBox(width: 12),
              Text('Ventas'),
            ],
          ),
        ),
        PopupMenuItem(
          value: {'title': 'Clientes', 'route': '/clientes'},
          child: const Row(
            children: [
              Icon(Icons.people, size: 18),
              SizedBox(width: 12),
              Text('Clientes'),
            ],
          ),
        ),
        PopupMenuItem(
          value: {'title': 'Compras', 'route': '/purchases/suppliers'},
          child: const Row(
            children: [
              Icon(Icons.shopping_cart, size: 18),
              SizedBox(width: 12),
              Text('Compras'),
            ],
          ),
        ),
        PopupMenuItem(
          value: {'title': 'POS', 'route': '/pos'},
          child: const Row(
            children: [
              Icon(Icons.point_of_sale, size: 18),
              SizedBox(width: 12),
              Text('POS'),
            ],
          ),
        ),
        PopupMenuItem(
          value: {'title': 'Taller', 'route': '/taller/pegas'},
          child: const Row(
            children: [
              Icon(Icons.build, size: 18),
              SizedBox(width: 12),
              Text('Taller'),
            ],
          ),
        ),
        PopupMenuItem(
          value: {'title': 'Contabilidad', 'route': '/accounting/accounts'},
          child: const Row(
            children: [
              Icon(Icons.account_balance, size: 18),
              SizedBox(width: 12),
              Text('Contabilidad'),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        final workspaceManager = context.read<WorkspaceManager>();
        workspaceManager.addWorkspace(
          title: value['title']!,
          initialRoute: value['route']!,
        );
      },
    );
  }
}
