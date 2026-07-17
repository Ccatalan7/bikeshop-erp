import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../modules/mail/providers/email_provider.dart';
import '../../modules/mail/providers/mail_account_manager.dart';
import '../../modules/messaging/models/conversation.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/storage/models/app_stored_file.dart';
import '../../modules/storage/services/app_file_storage_service.dart';
import '../models/notification_digest.dart';
import '../services/notification_service.dart';
import '../services/right_toolbar_service.dart';
import '../services/workspace_manager.dart';
import '../utils/chilean_utils.dart';

/// Opens the operational briefing as a slide-in panel.
Future<void> showNotificationsPanel(BuildContext context) {
  final rootContext = context;
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar resumen diario',
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

  final BuildContext rootContext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = width < 480 ? width : 420.0;

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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Text(
                      'Resumen diario',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Cerrar',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _NotificationBriefing(
                  onNavigate: (route) {
                    Navigator.of(context).maybePop();
                    if (rootContext.mounted) {
                      _navigateToRoute(rootContext, route);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Embedded operational briefing rendered inside the right toolbar.
class NotificationsToolbarPanel extends StatelessWidget {
  const NotificationsToolbarPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return _NotificationBriefing(
      onNavigate: (route) {
        context.read<RightToolbarService>().close();
        _navigateToRoute(context, route);
      },
    );
  }
}

class _NotificationBriefing extends StatefulWidget {
  const _NotificationBriefing({required this.onNavigate});

  final void Function(String route) onNavigate;

  @override
  State<_NotificationBriefing> createState() => _NotificationBriefingState();
}

class _NotificationBriefingState extends State<_NotificationBriefing> {
  final NotificationService _notifications = NotificationService();
  final MailAccountManager _mail = MailAccountManager.instance;
  final AppFileStorageService _filesService = AppFileStorageService.instance;

  NotificationDigestPeriod _period = NotificationDigestPeriod.today;
  List<AppStoredFile> _files = const [];
  StreamSubscription<AppStoredFile>? _savedFileSubscription;
  bool _loadingFiles = true;
  Object? _filesError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFiles());
    _savedFileSubscription = _filesService.savedFiles.listen(_recordSavedFile);
  }

  @override
  void dispose() {
    _savedFileSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    if (mounted) {
      setState(() {
        _loadingFiles = true;
        _filesError = null;
      });
    }
    try {
      final files = await _filesService.listFiles(limit: 120);
      if (!mounted) return;
      setState(() {
        _files = files;
        _loadingFiles = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingFiles = false;
        _filesError = error;
      });
    }
  }

  void _recordSavedFile(AppStoredFile file) {
    if (!mounted) return;
    setState(() {
      _files = [
        file,
        ..._files.where((candidate) => candidate.id != file.id),
      ];
      _filesError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _notifications.notificationsFeed,
        _mail,
      ]),
      builder: (context, _) {
        return Consumer<ChatProvider>(
          builder: (context, chat, _) {
            final rows = _notifications.notificationsFeed.value;
            final digest = NotificationDigestSnapshot.fromRows(
              period: _period,
              notifications: rows,
              fileCreatedAt: _files.map((file) => file.createdAt),
            );
            final periodFiles = _files
                .where((file) => digest.contains(file.createdAt))
                .toList(growable: false);
            final activity = _buildActivity(rows, _mail.emails, chat, digest);
            final unreadEmails = _mail.emails
                .where(
                  (email) =>
                      !email.isRead && digest.contains(email.receivedTime),
                )
                .length;
            final unreadChats = chat.conversations.fold<int>(0, (
              total,
              conversation,
            ) {
              final lastMessageAt = conversation.lastMessageAt;
              if (lastMessageAt == null || !digest.contains(lastMessageAt)) {
                return total;
              }
              if (conversation.type == 'support' &&
                  conversation.status == 'pending') {
                return total +
                    (conversation.unreadCount > 0
                        ? conversation.unreadCount
                        : 1);
              }
              return total + conversation.unreadCount;
            });

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BriefingToolbar(
                  period: _period,
                  unreadAlerts: digest.unreadAlertCount,
                  onPeriodChanged: (period) {
                    setState(() => _period = period);
                  },
                  onMarkAlertsRead: _notifications.markAllNotificationsRead,
                ),
                const Divider(height: 1),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      await Future.wait([
                        _loadFiles(),
                        _mail.backgroundRefresh(),
                      ]);
                    },
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      children: [
                        _BriefingHeading(period: _period),
                        const SizedBox(height: 12),
                        _MetricsGrid(
                          digest: digest,
                          onNavigate: widget.onNavigate,
                        ),
                        const SizedBox(height: 16),
                        _AttentionSection(
                          unreadEmails: unreadEmails,
                          unreadChats: unreadChats,
                          operationalAlerts: digest.unreadAlertCount,
                          onNavigate: widget.onNavigate,
                        ),
                        const SizedBox(height: 16),
                        _FilesSection(
                          period: _period,
                          files: periodFiles,
                          loading: _loadingFiles,
                          hasError: _filesError != null,
                          onRetry: _loadFiles,
                          onNavigate: widget.onNavigate,
                        ),
                        const SizedBox(height: 16),
                        _ActivitySection(
                          items: activity,
                          period: _period,
                          onTap: (item) {
                            final notificationId = item.notificationId;
                            if (notificationId != null) {
                              unawaited(
                                _notifications
                                    .markNotificationRead(notificationId),
                              );
                            }
                            widget.onNavigate(item.route);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<_BriefingActivityItem> _buildActivity(
    List<Map<String, dynamic>> rows,
    List<Email> emails,
    ChatProvider chat,
    NotificationDigestSnapshot digest,
  ) {
    final items = <_BriefingActivityItem>[];

    for (final row in rows) {
      final createdAt = DateTime.tryParse(
        row['created_at']?.toString() ?? '',
      )?.toLocal();
      if (createdAt == null || !digest.contains(createdAt)) continue;
      final type = row['type']?.toString() ?? '';
      items.add(
        _BriefingActivityItem(
          title: row['title']?.toString() ?? 'Actividad',
          subtitle: row['body']?.toString() ?? '',
          createdAt: createdAt,
          route: row['route']?.toString().trim().isNotEmpty == true
              ? row['route'].toString()
              : '/',
          icon: _iconForNotificationType(type),
          accent: _accentForNotificationType(type),
          unread: row['read_at'] == null,
          notificationId: row['id']?.toString(),
        ),
      );
    }

    for (final email in emails) {
      if (!digest.contains(email.receivedTime)) continue;
      final sender = email.senderName.trim().isEmpty
          ? email.senderEmail
          : email.senderName;
      final subject =
          email.subject.trim().isEmpty ? '(sin asunto)' : email.subject.trim();
      items.add(
        _BriefingActivityItem(
          title: sender.trim().isEmpty ? 'Correo recibido' : sender,
          subtitle: subject,
          createdAt: email.receivedTime.toLocal(),
          route: '/mail',
          icon: Icons.mail_outline,
          accent: const Color(0xFF4B5563),
          unread: !email.isRead,
        ),
      );
    }

    for (final conversation in chat.conversations) {
      final lastMessageAt = conversation.lastMessageAt?.toLocal();
      if (lastMessageAt == null || !digest.contains(lastMessageAt)) continue;
      final name = _conversationName(conversation);
      final message = conversation.lastMessageContent?.trim();
      items.add(
        _BriefingActivityItem(
          title: name,
          subtitle: message == null || message.isEmpty
              ? conversation.channelLabel
              : message,
          createdAt: lastMessageAt,
          route: '/chat',
          icon: Icons.chat_bubble_outline,
          accent: const Color(0xFF4B5563),
          unread: conversation.unreadCount > 0 ||
              (conversation.type == 'support' &&
                  conversation.status == 'pending'),
        ),
      );
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items.take(12).toList(growable: false);
  }

  String _conversationName(Conversation conversation) {
    final title = conversation.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final creator = conversation.creatorName?.trim();
    if (creator != null && creator.isNotEmpty) return creator;
    return conversation.channelLabel;
  }
}

class _BriefingToolbar extends StatelessWidget {
  const _BriefingToolbar({
    required this.period,
    required this.unreadAlerts,
    required this.onPeriodChanged,
    required this.onMarkAlertsRead,
  });

  final NotificationDigestPeriod period;
  final int unreadAlerts;
  final ValueChanged<NotificationDigestPeriod> onPeriodChanged;
  final Future<void> Function() onMarkAlertsRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          SegmentedButton<NotificationDigestPeriod>(
            segments: const [
              ButtonSegment(
                value: NotificationDigestPeriod.today,
                label: Text('Hoy'),
              ),
              ButtonSegment(
                value: NotificationDigestPeriod.sevenDays,
                label: Text('7 días'),
              ),
            ],
            selected: {period},
            showSelectedIcon: false,
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            onSelectionChanged: (selection) {
              onPeriodChanged(selection.first);
            },
          ),
          const Spacer(),
          if (unreadAlerts > 0)
            Tooltip(
              message: 'Marcar alertas del ERP como leídas',
              child: TextButton.icon(
                onPressed: onMarkAlertsRead,
                icon: const Icon(Icons.done_all, size: 16),
                label: Text('$unreadAlerts'),
              ),
            ),
        ],
      ),
    );
  }
}

class _BriefingHeading extends StatelessWidget {
  const _BriefingHeading({required this.period});

  final NotificationDigestPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todayLabel = MaterialLocalizations.of(context).formatFullDate(
      DateTime.now(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          period == NotificationDigestPeriod.today
              ? 'Briefing de hoy'
              : 'Resumen de los últimos 7 días',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          period == NotificationDigestPeriod.today
              ? todayLabel
              : 'Actividad operativa consolidada',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.digest,
    required this.onNavigate,
  });

  final NotificationDigestSnapshot digest;
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetricCard(
              width: itemWidth,
              label: 'Trabajos nuevos',
              value: '${digest.jobCount}',
              detail: 'Taller',
              icon: Icons.build_outlined,
              onTap: () => onNavigate('/taller/pegas'),
            ),
            _MetricCard(
              width: itemWidth,
              label: 'Pagos recibidos',
              value: digest.paymentTotal > 0
                  ? ChileanUtils.formatCurrency(digest.paymentTotal)
                  : r'$0',
              detail: '${digest.paymentCount} movimientos',
              icon: Icons.payments_outlined,
              onTap: () => onNavigate('/sales/payments'),
            ),
            _MetricCard(
              width: itemWidth,
              label: 'Pedidos online',
              value: '${digest.onlineOrderCount}',
              detail: 'Tienda web',
              icon: Icons.shopping_bag_outlined,
              onTap: () => onNavigate('/website/orders'),
            ),
            _MetricCard(
              width: itemWidth,
              label: 'Archivos',
              value: '${digest.fileCount}',
              detail: 'Recibidos y guardados',
              icon: Icons.folder_open_outlined,
              onTap: () => onNavigate('/storage'),
            ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.onTap,
  });

  final double width;
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Material(
        color: theme.colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.8)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      icon,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _AttentionSection extends StatelessWidget {
  const _AttentionSection({
    required this.unreadEmails,
    required this.unreadChats,
    required this.operationalAlerts,
    required this.onNavigate,
  });

  final int unreadEmails;
  final int unreadChats;
  final int operationalAlerts;
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    final total = unreadEmails + unreadChats + operationalAlerts;
    return _SectionSurface(
      title: 'Requiere atención',
      trailing: total > 0 ? '$total pendientes' : 'Todo al día',
      child: total == 0
          ? const _QuietState(
              icon: Icons.check_circle_outline,
              text: 'No hay pendientes en correo, chats ni alertas.',
            )
          : Column(
              children: [
                if (unreadEmails > 0)
                  _ActionRow(
                    icon: Icons.mark_email_unread_outlined,
                    label: 'Correos sin leer',
                    count: unreadEmails,
                    onTap: () => onNavigate('/mail'),
                  ),
                if (unreadChats > 0)
                  _ActionRow(
                    icon: Icons.mark_chat_unread_outlined,
                    label: 'Mensajes pendientes',
                    count: unreadChats,
                    onTap: () => onNavigate('/chat'),
                  ),
                if (operationalAlerts > 0)
                  _ActionRow(
                    icon: Icons.notifications_active_outlined,
                    label: 'Alertas operativas nuevas',
                    count: operationalAlerts,
                    onTap: () {},
                    showChevron: false,
                  ),
              ],
            ),
    );
  }
}

class _FilesSection extends StatelessWidget {
  const _FilesSection({
    required this.period,
    required this.files,
    required this.loading,
    required this.hasError,
    required this.onRetry,
    required this.onNavigate,
  });

  final NotificationDigestPeriod period;
  final List<AppStoredFile> files;
  final bool loading;
  final bool hasError;
  final Future<void> Function() onRetry;
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    final visibleFiles = files.take(4).toList(growable: false);
    return _SectionSurface(
      title: period == NotificationDigestPeriod.today
          ? 'Archivos de hoy'
          : 'Archivos de los últimos 7 días',
      trailing: loading ? 'Actualizando' : '${files.length}',
      child: hasError
          ? _InlineError(
              message: 'No se pudo cargar el resumen de archivos.',
              onRetry: onRetry,
            )
          : loading && files.isEmpty
              ? const LinearProgressIndicator(minHeight: 2)
              : files.isEmpty
                  ? const _QuietState(
                      icon: Icons.folder_open_outlined,
                      text: 'No se guardaron archivos en este período.',
                    )
                  : Column(
                      children: [
                        for (final file in visibleFiles)
                          _FileRow(
                            file: file,
                            onTap: () => onNavigate('/storage'),
                          ),
                        if (files.length > visibleFiles.length)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => onNavigate('/storage'),
                              child: Text(
                                'Ver los ${files.length} archivos',
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({
    required this.items,
    required this.period,
    required this.onTap,
  });

  final List<_BriefingActivityItem> items;
  final NotificationDigestPeriod period;
  final ValueChanged<_BriefingActivityItem> onTap;

  @override
  Widget build(BuildContext context) {
    return _SectionSurface(
      title: 'Actividad reciente',
      trailing: period == NotificationDigestPeriod.today ? 'Hoy' : '7 días',
      child: items.isEmpty
          ? const _QuietState(
              icon: Icons.inbox_outlined,
              text: 'No hay actividad registrada en este período.',
            )
          : Column(
              children: [
                for (final item in items)
                  _ActivityRow(item: item, onTap: () => onTap(item)),
                if (items.length == 12)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Se muestran las 12 novedades más recientes.',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _SectionSurface extends StatelessWidget {
  const _SectionSurface({
    required this.title,
    required this.trailing,
    required this.child,
  });

  final String title;
  final String trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.8)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  trailing,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.7)),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: theme.textTheme.bodySmall),
            ),
            Text(
              '$count',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onTap});

  final AppStoredFile file;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contextLabel = file.contextTitle?.trim();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
        child: Row(
          children: [
            Icon(
              _iconForFile(file),
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    contextLabel == null || contextLabel.isEmpty
                        ? file.sourceType
                        : contextLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _compactTime(file.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item, required this.onTap});

  final _BriefingActivityItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: item.accent.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon, size: 16, color: item.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight:
                                item.unread ? FontWeight.w700 : FontWeight.w600,
                          ),
                        ),
                      ),
                      if (item.unread)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if (item.subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _compactTime(item.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietState extends StatelessWidget {
  const _QuietState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    );
  }
}

class _BriefingActivityItem {
  const _BriefingActivityItem({
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.route,
    required this.icon,
    required this.accent,
    required this.unread,
    this.notificationId,
  });

  final String title;
  final String subtitle;
  final DateTime createdAt;
  final String route;
  final IconData icon;
  final Color accent;
  final bool unread;
  final String? notificationId;
}

void _navigateToRoute(BuildContext context, String route) {
  try {
    context.read<WorkspaceManager>().navigateActiveWorkspaceFromSharedLink(
          route,
        );
  } catch (_) {
    context.go(route);
  }
}

IconData _iconForNotificationType(String type) {
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

Color _accentForNotificationType(String type) {
  switch (type) {
    case 'sales_payment_received':
    case 'whatsapp_catalog_approved':
      return const Color(0xFF2E7D32);
    default:
      return const Color(0xFF4B5563);
  }
}

IconData _iconForFile(AppStoredFile file) {
  if (file.isPdf) return Icons.picture_as_pdf_outlined;
  if (file.isImage) return Icons.image_outlined;
  if (file.isTextLike) return Icons.description_outlined;
  return Icons.insert_drive_file_outlined;
}

String _compactTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) {
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month';
}
