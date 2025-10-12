import 'package:flutter/material.dart';
import '../themes/app_theme.dart';

/// A responsive data display widget that shows data in a table on desktop
/// and as cards on mobile devices for better touch interaction
class ResponsiveDataView<T> extends StatelessWidget {
  final List<T> items;
  final List<DataColumn> columns;
  final List<DataCell> Function(T item) buildCells;
  final Widget Function(T item)? buildMobileCard;
  final VoidCallback? onRefresh;
  final bool isLoading;
  final String emptyMessage;
  
  const ResponsiveDataView({
    super.key,
    required this.items,
    required this.columns,
    required this.buildCells,
    this.buildMobileCard,
    this.onRefresh,
    this.isLoading = false,
    this.emptyMessage = 'No hay datos para mostrar',
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
              ),
              const SizedBox(height: 16),
              Text(
                emptyMessage,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isMobile = AppTheme.isMobile(context);
    
    if (isMobile && buildMobileCard != null) {
      return _buildMobileView(context);
    } else {
      return _buildTableView(context);
    }
  }

  Widget _buildMobileView(BuildContext context) {
    if (onRefresh != null) {
      return RefreshIndicator(
        onRefresh: () async {
          onRefresh?.call();
        },
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(
            vertical: AppTheme.mobilePaddingSmall,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            return buildMobileCard!(items[index]);
          },
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        vertical: AppTheme.mobilePaddingSmall,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return buildMobileCard!(items[index]);
      },
    );
  }

  Widget _buildTableView(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: columns,
          rows: items.map((item) {
            return DataRow(cells: buildCells(item));
          }).toList(),
        ),
      ),
    );
  }
}

/// A pre-styled card for mobile list views
class MobileDataCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> details;
  final List<Widget>? actions;
  final VoidCallback? onTap;
  final Color? statusColor;
  final String? statusText;
  
  const MobileDataCard({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.details,
    this.actions,
    this.onTap,
    this.statusColor,
    this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.mobilePaddingMedium,
        vertical: AppTheme.mobilePaddingSmall,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.mobilePaddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (statusText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (statusColor ?? theme.primaryColor).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusText!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor ?? theme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              
              // Details
              if (details.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...details,
              ],
              
              // Actions
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A detail row for mobile cards
class CardDetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  
  const CardDetailRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurface.withOpacity(0.5),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
