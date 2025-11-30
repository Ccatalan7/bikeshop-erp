import 'package:flutter/material.dart';

/// Universal line row wrapper for invoice/form line items.
/// 
/// This widget encapsulates:
/// - Hover state management (local, won't trigger parent rebuilds)
/// - Row styling with borders and hover highlight
/// - Index column with optional reorder arrows on hover
/// - Consistent column layout across all forms
/// 
/// Usage:
/// ```dart
/// LineRowWrapper(
///   index: 1,
///   canMoveUp: index > 1,
///   canMoveDown: index < totalLines,
///   onMoveUp: () => _moveLineUp(entry),
///   onMoveDown: () => _moveLineDown(entry),
///   onRemove: () => _removeLine(entry),
///   canEdit: _canEditFields,
///   columns: [
///     LineColumn(width: null, expanded: true, child: productField),
///     LineColumn(width: 120, child: quantityField),
///     LineColumn(width: 130, child: priceField),
///     LineColumn(width: 130, child: totalText),
///   ],
/// )
/// ```
class LineRowWrapper extends StatelessWidget {
  /// The 1-based index of this line
  final int index;
  
  /// Whether this line can be moved up
  final bool canMoveUp;
  
  /// Whether this line can be moved down
  final bool canMoveDown;
  
  /// Called when user clicks up arrow
  final VoidCallback? onMoveUp;
  
  /// Called when user clicks down arrow
  final VoidCallback? onMoveDown;
  
  /// Called when user clicks delete button
  final VoidCallback? onRemove;
  
  /// Whether the form is in edit mode
  final bool canEdit;
  
  /// Width of the index column (default 40)
  final double indexColumnWidth;
  
  /// Width of the actions column (default 48)
  final double actionsColumnWidth;
  
  /// Whether to show the delete button in actions column
  final bool showDeleteButton;
  
  /// The columns to display (excluding index and actions)
  final List<LineColumn> columns;
  
  /// Optional key for the container
  final Key? rowKey;

  const LineRowWrapper({
    super.key,
    required this.index,
    this.canMoveUp = false,
    this.canMoveDown = false,
    this.onMoveUp,
    this.onMoveDown,
    this.onRemove,
    this.canEdit = true,
    this.indexColumnWidth = 40.0,
    this.actionsColumnWidth = 48.0,
    this.showDeleteButton = true,
    required this.columns,
    this.rowKey,
  });

  @override
  Widget build(BuildContext context) {
    // Delegate to internal stateful widget for hover state management
    return _HoverableLineRow(
      index: index,
      canMoveUp: canMoveUp,
      canMoveDown: canMoveDown,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onRemove: onRemove,
      canEdit: canEdit,
      indexColumnWidth: indexColumnWidth,
      actionsColumnWidth: actionsColumnWidth,
      showDeleteButton: showDeleteButton,
      columns: columns,
      rowKey: rowKey,
    );
  }
}

/// Internal stateful widget to handle hover state locally
class _HoverableLineRow extends StatefulWidget {
  final int index;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onRemove;
  final bool canEdit;
  final double indexColumnWidth;
  final double actionsColumnWidth;
  final bool showDeleteButton;
  final List<LineColumn> columns;
  final Key? rowKey;

  const _HoverableLineRow({
    required this.index,
    required this.canMoveUp,
    required this.canMoveDown,
    this.onMoveUp,
    this.onMoveDown,
    this.onRemove,
    required this.canEdit,
    required this.indexColumnWidth,
    required this.actionsColumnWidth,
    required this.showDeleteButton,
    required this.columns,
    this.rowKey,
  });

  @override
  State<_HoverableLineRow> createState() => _HoverableLineRowState();
}

class _HoverableLineRowState extends State<_HoverableLineRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        key: widget.rowKey,
        decoration: BoxDecoration(
          color: _isHovered 
              ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.3) 
              : null,
          border: Border(
            bottom: BorderSide(
              color: theme.colorScheme.outline.withOpacity(0.2),
            ),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Index column with reorder arrows on hover
              _buildIndexColumn(theme),
              
              // Content columns
              ...widget.columns.map((col) => _buildColumn(theme, col)),
              
              // Actions column (always render for alignment)
              _buildActionsColumn(theme),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildIndexColumn(ThemeData theme) {
    return Container(
      width: widget.indexColumnWidth,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Up arrow (only when hovering and can move up)
          if (widget.canMoveUp && _isHovered && widget.canEdit)
            InkWell(
              onTap: widget.onMoveUp,
              child: Icon(
                Icons.keyboard_arrow_up,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            )
          else
            const SizedBox(height: 18),
          
          // Index number
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${widget.index}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          
          // Down arrow (only when hovering and can move down)
          if (widget.canMoveDown && _isHovered && widget.canEdit)
            InkWell(
              onTap: widget.onMoveDown,
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            )
          else
            const SizedBox(height: 18),
        ],
      ),
    );
  }
  
  Widget _buildColumn(ThemeData theme, LineColumn column) {
    final borderDecoration = column.showRightBorder
        ? BoxDecoration(
            border: Border(
              right: BorderSide(color: theme.colorScheme.outline.withOpacity(0.2)),
            ),
          )
        : null;
    
    if (column.expanded) {
      return Expanded(
        child: Container(
          constraints: BoxConstraints(minWidth: column.minWidth ?? 250),
          padding: column.padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: borderDecoration,
          child: column.child,
        ),
      );
    }
    
    return Container(
      width: column.width,
      padding: column.padding ?? const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: borderDecoration,
      child: column.child,
    );
  }
  
  Widget _buildActionsColumn(ThemeData theme) {
    return SizedBox(
      width: widget.actionsColumnWidth,
      child: widget.showDeleteButton && widget.canEdit && widget.onRemove != null
          ? IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: Colors.red,
              onPressed: widget.onRemove,
              tooltip: 'Eliminar línea',
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Defines a column in the line row.
class LineColumn {
  /// Fixed width (use null for expanded columns)
  final double? width;
  
  /// Whether this column should expand to fill available space
  final bool expanded;
  
  /// Minimum width for expanded columns
  final double? minWidth;
  
  /// Whether to show a right border
  final bool showRightBorder;
  
  /// Custom padding (default: horizontal 8, vertical 12)
  final EdgeInsets? padding;
  
  /// The widget to display in this column
  final Widget child;

  const LineColumn({
    this.width,
    this.expanded = false,
    this.minWidth,
    this.showRightBorder = true,
    this.padding,
    required this.child,
  }) : assert(expanded || width != null, 'Either width or expanded must be set');
}
