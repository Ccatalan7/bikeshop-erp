import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/notification_service.dart';
import '../services/right_toolbar_service.dart';
import '../services/workspace_manager.dart';
import '../utils/chilean_utils.dart';

/// Opens the right-side notifications center as a slide-in panel.
///
/// Uses [showGeneralDialog] so it works regardless of the surrounding
/// Scaffold structure (the desktop shell has no endDrawer).
Future<void> showNotificationsPanel(BuildContext context) {
  final rootContext = context;
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar notificaciones',
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return Align(
        alignment: Alignment.centerRight,
        child: _NotificationsPanel(rootContext: rootContext),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class _NotificationsPanel extends StatelessWidget {
  const _NotificationsPanel({required this.rootContext});

  /// The original (non-dialog) context used for navigation after closing.
  final BuildContext rootContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = NotificationService();
    final width = MediaQuery.of(context).size.width;
    final panelWidth = width < 480 ? width : 400.0;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 12,
      child: SafeArea(
        child: SizedBox(
          width: panelWidth,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context, theme, service),
              const Divider(height: 1),
              _DailySummary(
                onNavigate: (route) => _navigate(context, route),
              ),
              const Divider(height: 1),
              Expanded(
                child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: service.notificationsFeed,
                  builder: (context, items, _) {
                    if (items.isEmpty) {
                      return _buildEmptyState(theme);
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 60),
                      itemBuilder: (context, index) {
                        return _NotificationTile(
                          notification: items[index],
                          onTap: () => _handleTap(context, items[index]),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    NotificationService service,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Text(
            'Notificaciones',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          ValueListenableBuilder<int>(
            valueListenable: service.unreadNotificationsCount,
            builder: (context, unread, _) {
              if (unread == 0) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => service.markAllNotificationsRead(),
                child: const Text('Marcar todo leído'),
              );
            },
          ),
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'Sin notificaciones',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _handleTap(BuildContext context, Map<String, dynamic> notification) {
    final id = notification['id']?.toString();
    if (id != null && id.isNotEmpty) {
      NotificationService().markNotificationRead(id);
    }
    final route = notification['route']?.toString();
    if (route != null && route.isNotEmpty) {
      _navigate(context, route);
    }
  }

  void _navigate(BuildContext context, String route) {
    Navigator.of(context).maybePop();
    if (rootContext.mounted) {
      _navigateToRoute(rootContext, route);
    }
  }
}

/// Embedded notifications center rendered inside the [RightToolbar].
///
/// Unlike [showNotificationsPanel] (a slide-in dialog), this widget is meant to
/// fill the toolbar's tool panel area. The toolbar already provides the header
/// (title + close button), so this widget only renders the mark-all action,
/// the daily activity summary and the persistent notifications feed.
class NotificationsToolbarPanel extends StatelessWidget {
  const NotificationsToolbarPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = NotificationService();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<int>(
          valueListenable: service.unreadNotificationsCount,
          builder: (context, unread, _) {
            if (unread == 0) return const SizedBox.shrink();
            return Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                child: TextButton.icon(
                  onPressed: () => service.markAllNotificationsRead(),
                  icon: const Icon(Icons.done_all, size: 16),
                  label: const Text('Marcar todo leído'),
                ),
              ),
            );
          },
        ),
        _DailySummary(
          onNavigate: (route) => _navigate(context, route),
        ),
        const Divider(height: 1),
        Expanded(
          child: ValueListenableBuilder<List<Map<String, dynamic>>>(
            valueListenable: service.notificationsFeed,
            builder: (context, items, _) {
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 40,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Sin notificaciones',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, indent: 60),
                itemBuilder: (context, index) {
                  return _NotificationTile(
                    notification: items[index],
                    onTap: () => _handleTap(context, items[index]),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _handleTap(BuildContext context, Map<String, dynamic> notification) {
    final id = notification['id']?.toString();
    if (id != null && id.isNotEmpty) {
      NotificationService().markNotificationRead(id);
    }
    final route = notification['route']?.toString();
    if (route != null && route.isNotEmpty) {
      _navigate(context, route);
    }
  }

  void _navigate(BuildContext context, String route) {
    context.read<RightToolbarService>().close();
    _navigateToRoute(context, route);
  }
}

/// Navigates to [route] from a context that lives outside the per-workspace
/// GoRouter subtree (e.g. the right toolbar or the slide-in dialog).
///
/// The notifications center is mounted above the workspace routers, so
/// `context.go()` throws "No GoRouter found in context". Instead we route
/// through [WorkspaceManager], which owns each workspace's router and knows
/// how to open the destination in the active (or appropriate) workspace.
void _navigateToRoute(BuildContext context, String route) {
  try {
    context.read<WorkspaceManager>().navigateActiveWorkspaceFromSharedLink(
          route,
        );
  } catch (_) {
    // Fallback for contexts where the workspace system isn't available
    // (e.g. small-screen / non-workspace shells).
    context.go(route);
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final Map<String, dynamic> notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUnread = notification['read_at'] == null;
    final severity = notification['severity']?.toString() ?? 'info';
    final type = notification['type']?.toString() ?? '';
    final title = notification['title']?.toString() ?? 'Notificación';
    final body = notification['body']?.toString() ?? '';
    final createdAt = notification['created_at']?.toString();

    final accent = _severityColor(theme, severity);

    return InkWell(
      onTap: onTap,
      child: Container(
        color: isUnread
            ? theme.colorScheme.primary.withValues(alpha: 0.04)
            : null,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(_iconForType(type), size: 18, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                isUnread ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 6, top: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _relativeTime(createdAt),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _severityColor(ThemeData theme, String severity) {
    switch (severity) {
      case 'success':
        return const Color(0xFF2E7D32);
      case 'warning':
        return const Color(0xFFB26A00);
      case 'critical':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.primary;
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'mechanic_job_created':
        return Icons.build_outlined;
      case 'sales_payment_received':
        return Icons.payments_outlined;
      case 'online_order_created':
        return Icons.shopping_bag_outlined;
      case 'whatsapp_catalog_approved':
        return Icons.verified_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  String _relativeTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return '';
    final diff = DateTime.now().difference(parsed.toLocal());
    if (diff.inSeconds < 60) return 'Hace un momento';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
    if (diff.inDays < 7) return 'Hace ${diff.inDays} d';
    final d = parsed.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}

/// Daily activity digest shown at the top of the notifications center.
///
/// Summarizes the meaningful events from the last 24 hours (new workshop jobs,
/// payments received, online orders, WhatsApp catalog approvals) so the user
/// gets an at-a-glance recap when they arrive — instead of raw unread counters.
class _DailySummary extends StatelessWidget {
  const _DailySummary({required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = NotificationService();

    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: service.notificationsFeed,
      builder: (context, items, _) {
        final cutoff = DateTime.now().subtract(const Duration(hours: 24));
        int jobs = 0;
        int payments = 0;
        double paymentsTotal = 0;
        int orders = 0;
        int catalog = 0;

        for (final row in items) {
          final created =
              DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal();
          if (created == null || created.isBefore(cutoff)) continue;
          switch (row['type']?.toString()) {
            case 'mechanic_job_created':
              jobs++;
              break;
            case 'sales_payment_received':
              payments++;
              final data = row['data'];
              if (data is Map && data['amount'] is num) {
                paymentsTotal += (data['amount'] as num).toDouble();
              }
              break;
            case 'online_order_created':
              orders++;
              break;
            case 'whatsapp_catalog_approved':
              catalog++;
              break;
          }
        }

        final total = jobs + payments + orders + catalog;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.insights_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Resumen · últimas 24 h',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (total == 0)
                Text(
                  'Sin novedades en las últimas 24 horas',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Column(
                  children: [
                    if (jobs > 0)
                      _SummaryRow(
                        icon: Icons.build_outlined,
                        accent: theme.colorScheme.primary,
                        label: jobs == 1 ? 'Trabajo nuevo' : 'Trabajos nuevos',
                        trailing: '$jobs',
                        onTap: () => onNavigate('/taller/pegas'),
                      ),
                    if (payments > 0)
                      _SummaryRow(
                        icon: Icons.payments_outlined,
                        accent: const Color(0xFF2E7D32),
                        label: payments == 1
                            ? 'Pago recibido'
                            : 'Pagos recibidos',
                        sublabel: paymentsTotal > 0
                            ? ChileanUtils.formatCurrency(paymentsTotal)
                            : null,
                        trailing: '$payments',
                        onTap: () => onNavigate('/sales/payments'),
                      ),
                    if (orders > 0)
                      _SummaryRow(
                        icon: Icons.shopping_bag_outlined,
                        accent: theme.colorScheme.primary,
                        label:
                            orders == 1 ? 'Pedido online' : 'Pedidos online',
                        trailing: '$orders',
                        onTap: () => onNavigate('/website/orders'),
                      ),
                    if (catalog > 0)
                      _SummaryRow(
                        icon: Icons.verified_outlined,
                        accent: const Color(0xFF2E7D32),
                        label: catalog == 1
                            ? 'Producto aprobado en WhatsApp'
                            : 'Productos aprobados en WhatsApp',
                        trailing: '$catalog',
                        onTap: () => onNavigate('/inventory/products'),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.accent,
    required this.label,
    required this.trailing,
    required this.onTap,
    this.sublabel,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String? sublabel;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (sublabel != null)
                    Text(
                      sublabel!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              trailing,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
