import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../modules/mail/providers/email_provider.dart';
import '../../modules/mail/providers/mail_account_manager.dart';
import '../../modules/messaging/models/conversation.dart';
import '../../modules/messaging/providers/chat_provider.dart';
import '../../modules/messaging/utils/conversation_channel_presentation.dart';
import '../../modules/storage/models/app_stored_file.dart';
import '../../modules/storage/services/app_file_storage_service.dart';
import '../models/notification_digest.dart';
import '../services/notification_service.dart';
import '../services/right_toolbar_service.dart';
import '../services/workspace_manager.dart';
import '../utils/chilean_utils.dart';
import '../utils/trusted_meta_notification_url.dart';

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
  _ActivityFilter _activityFilter = _ActivityFilter.all;
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
            final activity = _buildActivity(
              rows,
              _mail.emails,
              chat,
              periodFiles,
              digest,
            );
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
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0.035, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: RefreshIndicator(
                      key: ValueKey(_period),
                      onRefresh: () async {
                        await Future.wait([
                          _loadFiles(),
                          _mail.backgroundRefresh(),
                        ]);
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          _BriefingHero(
                            period: _period,
                            items: activity,
                          ),
                          _MetricsRibbon(
                            digest: digest,
                            onNavigate: widget.onNavigate,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                            child: _AttentionSection(
                              unreadEmails: unreadEmails,
                              unreadChats: unreadChats,
                              operationalAlerts: digest.unreadAlertCount,
                              onNavigate: widget.onNavigate,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                            child: _FilesSection(
                              period: _period,
                              files: periodFiles,
                              loading: _loadingFiles,
                              hasError: _filesError != null,
                              onRetry: _loadFiles,
                              onNavigate: widget.onNavigate,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                            child: _ActivitySection(
                              items: activity,
                              period: _period,
                              filter: _activityFilter,
                              onFilterChanged: (filter) {
                                setState(() => _activityFilter = filter);
                              },
                              onTap: (item) {
                                final notificationId = item.notificationId;
                                if (notificationId != null) {
                                  unawaited(
                                    _notifications.markNotificationRead(
                                      notificationId,
                                    ),
                                  );
                                }
                                widget.onNavigate(item.route);
                              },
                            ),
                          ),
                        ],
                      ),
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
    List<AppStoredFile> files,
    NotificationDigestSnapshot digest,
  ) {
    final items = <_BriefingActivityItem>[];

    for (final row in rows) {
      final createdAt = DateTime.tryParse(
        row['created_at']?.toString() ?? '',
      )?.toLocal();
      if (createdAt == null || !digest.contains(createdAt)) continue;
      final type = row['type']?.toString() ?? '';
      final platformKey = _platformKeyForNotificationType(type);
      final storedRoute = row['route']?.toString().trim();
      final entityId = row['entity_id']?.toString().trim();
      final route = storedRoute == '/sales/payments' &&
              entityId != null &&
              entityId.isNotEmpty
          ? '/sales/payments?paymentId=${Uri.encodeComponent(entityId)}'
          : storedRoute?.isNotEmpty == true
              ? storedRoute!
              : '/';
      items.add(
        _BriefingActivityItem(
          title: row['title']?.toString() ?? 'Actividad',
          subtitle: row['body']?.toString() ?? '',
          createdAt: createdAt,
          route: route,
          icon: _iconForNotificationType(type),
          accent: _accentForNotificationType(type),
          kind: _kindForNotificationType(type),
          unread: row['read_at'] == null,
          notificationId: row['id']?.toString(),
          platformKey: platformKey,
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
          accent: _mailAccent,
          kind: _BriefingActivityKind.email,
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
          route: Uri(
            path: '/chat',
            queryParameters: {'conversation': conversation.id},
          ).toString(),
          icon: ConversationChannelPresentation.icon(conversation),
          accent: ConversationChannelPresentation.accent(conversation),
          kind: _BriefingActivityKind.chat,
          unread: conversation.unreadCount > 0 ||
              (conversation.type == 'support' &&
                  conversation.status == 'pending'),
          platformKey: ConversationChannelPresentation.usesPlatformGlyph(
            conversation.channel,
          )
              ? conversation.channel
              : null,
        ),
      );
    }

    for (final file in files) {
      final contextLabel = file.contextTitle?.trim();
      items.add(
        _BriefingActivityItem(
          title: file.fileName,
          subtitle: contextLabel == null || contextLabel.isEmpty
              ? file.sourceType
              : contextLabel,
          createdAt: file.createdAt.toLocal(),
          route: '/storage',
          icon: _iconForFile(file),
          accent: _filesAccent,
          kind: _BriefingActivityKind.file,
          unread: false,
        ),
      );
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  String _conversationName(Conversation conversation) {
    final title = conversation.title?.trim();
    if (title != null && title.isNotEmpty) return title;
    final creator = conversation.creatorName?.trim();
    if (creator != null && creator.isNotEmpty) return creator;
    return conversation.channelLabel;
  }
}

const _jobsAccent = Color(0xFF2878B8);
const _paymentsAccent = Color(0xFF2C8A62);
const _ordersAccent = Color(0xFF7758A6);
const _filesAccent = Color(0xFFC4772D);
const _mailAccent = Color(0xFF3D6FA8);
const _chatAccent = Color(0xFF7559A5);
const _warningAccent = Color(0xFFC27A22);

enum _BriefingActivityKind { job, payment, order, email, chat, file, alert }

enum _ActivityFilter {
  all,
  jobs,
  payments,
  emails,
  chats,
  orders,
  files,
  alerts
}

extension _ActivityFilterPresentation on _ActivityFilter {
  String get label {
    switch (this) {
      case _ActivityFilter.all:
        return 'Todo';
      case _ActivityFilter.jobs:
        return 'Trabajos';
      case _ActivityFilter.payments:
        return 'Pagos';
      case _ActivityFilter.emails:
        return 'Correos';
      case _ActivityFilter.chats:
        return 'Chats';
      case _ActivityFilter.orders:
        return 'Pedidos';
      case _ActivityFilter.files:
        return 'Archivos';
      case _ActivityFilter.alerts:
        return 'Alertas';
    }
  }

  String get emptyLabel {
    switch (this) {
      case _ActivityFilter.all:
        return 'No hay actividad registrada en este período.';
      case _ActivityFilter.jobs:
        return 'No hay trabajos registrados en este período.';
      case _ActivityFilter.payments:
        return 'No hay pagos registrados en este período.';
      case _ActivityFilter.emails:
        return 'No hay correos registrados en este período.';
      case _ActivityFilter.chats:
        return 'No hay chats registrados en este período.';
      case _ActivityFilter.orders:
        return 'No hay pedidos registrados en este período.';
      case _ActivityFilter.files:
        return 'No hay archivos registrados en este período.';
      case _ActivityFilter.alerts:
        return 'No hay otras alertas en este período.';
    }
  }

  IconData get icon {
    switch (this) {
      case _ActivityFilter.all:
        return Icons.view_timeline_outlined;
      case _ActivityFilter.jobs:
        return Icons.build_outlined;
      case _ActivityFilter.payments:
        return Icons.payments_outlined;
      case _ActivityFilter.emails:
        return Icons.mail_outline;
      case _ActivityFilter.chats:
        return Icons.chat_bubble_outline;
      case _ActivityFilter.orders:
        return Icons.shopping_bag_outlined;
      case _ActivityFilter.files:
        return Icons.folder_open_outlined;
      case _ActivityFilter.alerts:
        return Icons.notifications_outlined;
    }
  }

  Color get accent {
    switch (this) {
      case _ActivityFilter.all:
      case _ActivityFilter.jobs:
        return _jobsAccent;
      case _ActivityFilter.payments:
        return _paymentsAccent;
      case _ActivityFilter.emails:
        return _mailAccent;
      case _ActivityFilter.chats:
        return _chatAccent;
      case _ActivityFilter.orders:
        return _ordersAccent;
      case _ActivityFilter.files:
        return _filesAccent;
      case _ActivityFilter.alerts:
        return _warningAccent;
    }
  }

  bool includes(_BriefingActivityKind kind) {
    switch (this) {
      case _ActivityFilter.all:
        return true;
      case _ActivityFilter.jobs:
        return kind == _BriefingActivityKind.job;
      case _ActivityFilter.payments:
        return kind == _BriefingActivityKind.payment;
      case _ActivityFilter.emails:
        return kind == _BriefingActivityKind.email;
      case _ActivityFilter.chats:
        return kind == _BriefingActivityKind.chat;
      case _ActivityFilter.orders:
        return kind == _BriefingActivityKind.order;
      case _ActivityFilter.files:
        return kind == _BriefingActivityKind.file;
      case _ActivityFilter.alerts:
        return kind == _BriefingActivityKind.alert;
    }
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
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(
        children: [
          _PeriodTab(
            label: 'Hoy',
            selected: period == NotificationDigestPeriod.today,
            onTap: () => onPeriodChanged(NotificationDigestPeriod.today),
          ),
          const SizedBox(width: 18),
          _PeriodTab(
            label: '7 días',
            selected: period == NotificationDigestPeriod.sevenDays,
            onTap: () => onPeriodChanged(NotificationDigestPeriod.sevenDays),
          ),
          const Spacer(),
          if (unreadAlerts > 0)
            Tooltip(
              message: 'Marcar alertas del ERP como leídas',
              child: TextButton.icon(
                onPressed: onMarkAlertsRead,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.primary,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.done_all, size: 17),
                label: Text('$unreadAlerts nuevas'),
              ),
            ),
        ],
      ),
    );
  }
}

class _PeriodTab extends StatelessWidget {
  const _PeriodTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(label),
            ),
            const SizedBox(height: 6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: selected ? 28 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BriefingHero extends StatelessWidget {
  const _BriefingHero({required this.period, required this.items});

  final NotificationDigestPeriod period;
  final List<_BriefingActivityItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todayLabel = MaterialLocalizations.of(context).formatFullDate(
      DateTime.now(),
    );
    final accent = theme.colorScheme.primary;
    return Container(
      color: accent.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.14 : 0.065,
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      period == NotificationDigestPeriod.today
                          ? 'Hoy en Viñabike'
                          : 'Pulso de la semana',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.25,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      period == NotificationDigestPeriod.today
                          ? todayLabel
                          : 'Los últimos siete días, en una mirada',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${items.length}',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'movimientos',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ActivityPulse(period: period, items: items, accent: accent),
        ],
      ),
    );
  }
}

class _ActivityPulse extends StatelessWidget {
  const _ActivityPulse({
    required this.period,
    required this.items,
    required this.accent,
  });

  final NotificationDigestPeriod period;
  final List<_BriefingActivityItem> items;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = period == NotificationDigestPeriod.today;
    final counts = List<int>.filled(isToday ? 6 : 7, 0);

    for (final item in items) {
      final local = item.createdAt.toLocal();
      if (isToday) {
        final index = (local.hour ~/ 4).clamp(0, 5);
        counts[index]++;
      } else {
        final start = today.subtract(const Duration(days: 6));
        final itemDay = DateTime(local.year, local.month, local.day);
        final index = itemDay.difference(start).inDays;
        if (index >= 0 && index < counts.length) counts[index]++;
      }
    }

    var maxCount = 1;
    for (final count in counts) {
      if (count > maxCount) maxCount = count;
    }
    final labels = isToday
        ? const ['00', '04', '08', '12', '16', '20']
        : List<String>.generate(7, (index) {
            final start = today.subtract(const Duration(days: 6));
            return _weekdayLabel(start.add(Duration(days: index)).weekday);
          });

    return SizedBox(
      height: 54,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < counts.length; index++) ...[
            if (index > 0) const SizedBox(width: 7),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(
                          begin: 0,
                          end: counts[index] / maxCount,
                        ),
                        duration: Duration(milliseconds: 360 + (index * 35)),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, _) {
                          return FractionallySizedBox(
                            widthFactor: 1,
                            heightFactor: 0.12 + (value * 0.88),
                            alignment: Alignment.bottomCenter,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: accent.withValues(
                                  alpha: counts[index] == 0 ? 0.12 : 0.72,
                                ),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[index],
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 9,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricsRibbon extends StatelessWidget {
  const _MetricsRibbon({required this.digest, required this.onNavigate});

  final NotificationDigestSnapshot digest;
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.65),
          ),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _MetricRibbonItem(
                label: 'Trabajos',
                value: '${digest.jobCount}',
                hint: 'nuevos',
                icon: Icons.build_outlined,
                accent: _jobsAccent,
                onTap: () => onNavigate('/taller/pegas'),
              ),
            ),
            const _MetricDivider(),
            Expanded(
              child: _MetricRibbonItem(
                label: 'Pagos',
                value: digest.paymentTotal > 0
                    ? ChileanUtils.formatCurrency(digest.paymentTotal)
                    : r'$0',
                hint: '${digest.paymentCount} mov.',
                icon: Icons.payments_outlined,
                accent: _paymentsAccent,
                onTap: () => onNavigate('/sales/payments'),
              ),
            ),
            const _MetricDivider(),
            Expanded(
              child: _MetricRibbonItem(
                label: 'Pedidos',
                value: '${digest.onlineOrderCount}',
                hint: 'online',
                icon: Icons.shopping_bag_outlined,
                accent: _ordersAccent,
                onTap: () => onNavigate('/website/orders'),
              ),
            ),
            const _MetricDivider(),
            Expanded(
              child: _MetricRibbonItem(
                label: 'Archivos',
                value: '${digest.fileCount}',
                hint: 'guardados',
                icon: Icons.folder_open_outlined,
                accent: _filesAccent,
                onTap: () => onNavigate('/storage'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRibbonItem extends StatelessWidget {
  const _MetricRibbonItem({
    required this.label,
    required this.value,
    required this.hint,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final String value;
  final String hint;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 15, color: accent),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 20,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                hint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return VerticalDivider(
      width: 1,
      thickness: 1,
      indent: 8,
      endIndent: 8,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.55),
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
    final theme = Theme.of(context);
    final total = unreadEmails + unreadChats + operationalAlerts;
    final isClear = total == 0;
    final accent = isClear ? _paymentsAccent : _warningAccent;

    return Container(
      padding: const EdgeInsets.fromLTRB(13, 12, 10, 8),
      decoration: BoxDecoration(
        color: accent.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.14 : 0.075,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isClear ? Icons.check_circle_outline : Icons.bolt_outlined,
                size: 19,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isClear ? 'Todo al día' : 'Requiere atención',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                isClear ? 'Sin pendientes' : '$total pendientes',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (isClear)
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Correo, chats y alertas están revisados.'),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            if (unreadEmails > 0)
              _ActionRow(
                icon: Icons.mark_email_unread_outlined,
                label: 'Correos sin leer',
                count: unreadEmails,
                accent: _mailAccent,
                onTap: () => onNavigate('/mail'),
              ),
            if (unreadChats > 0)
              _ActionRow(
                icon: Icons.mark_chat_unread_outlined,
                label: 'Mensajes pendientes',
                count: unreadChats,
                accent: _chatAccent,
                onTap: () => onNavigate('/chat'),
              ),
            if (operationalAlerts > 0)
              _ActionRow(
                icon: Icons.notifications_active_outlined,
                label: 'Alertas operativas nuevas',
                count: operationalAlerts,
                accent: _warningAccent,
                onTap: () {},
                showChevron: false,
              ),
          ],
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
    return _OpenSection(
      title: period == NotificationDigestPeriod.today
          ? 'Archivos de hoy'
          : 'Archivos de los últimos 7 días',
      trailing: loading ? 'Actualizando' : '${files.length}',
      accent: _filesAccent,
      child: hasError
          ? _InlineError(
              message: 'No se pudo cargar el resumen de archivos.',
              onRetry: onRetry,
            )
          : loading && files.isEmpty
              ? LinearProgressIndicator(
                  minHeight: 2,
                  color: _filesAccent,
                  backgroundColor: _filesAccent.withValues(alpha: 0.12),
                )
              : files.isEmpty
                  ? const _QuietState(
                      icon: Icons.folder_open_outlined,
                      text: 'No se guardaron archivos en este período.',
                      accent: _filesAccent,
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
                              child: Text('Ver los ${files.length} archivos'),
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
    required this.filter,
    required this.onFilterChanged,
    required this.onTap,
  });

  final List<_BriefingActivityItem> items;
  final NotificationDigestPeriod period;
  final _ActivityFilter filter;
  final ValueChanged<_ActivityFilter> onFilterChanged;
  final ValueChanged<_BriefingActivityItem> onTap;

  @override
  Widget build(BuildContext context) {
    final filteredItems = items
        .where((item) => filter.includes(item.kind))
        .toList(growable: false);
    final visibleItems = filteredItems.take(12).toList(growable: false);
    return _OpenSection(
      title: 'Actividad reciente',
      trailing: period == NotificationDigestPeriod.today ? 'Hoy' : '7 días',
      trailingWidget: _ActivityFilterMenu(
        selected: filter,
        items: items,
        onSelected: onFilterChanged,
      ),
      accent: filter.accent,
      child: visibleItems.isEmpty
          ? _QuietState(
              icon: filter.icon,
              text: filter.emptyLabel,
              accent: filter.accent,
            )
          : Column(
              children: [
                for (var index = 0; index < visibleItems.length; index++)
                  _ActivityRow(
                    item: visibleItems[index],
                    isLast: index == visibleItems.length - 1,
                    onTap: () => onTap(visibleItems[index]),
                  ),
                if (filteredItems.length > visibleItems.length)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Se muestran los 12 movimientos más recientes.',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ActivityFilterMenu extends StatelessWidget {
  const _ActivityFilterMenu({
    required this.selected,
    required this.items,
    required this.onSelected,
  });

  final _ActivityFilter selected;
  final List<_BriefingActivityItem> items;
  final ValueChanged<_ActivityFilter> onSelected;

  int _countFor(_ActivityFilter filter) {
    return items.where((item) => filter.includes(item.kind)).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFiltered = selected != _ActivityFilter.all;

    return PopupMenuButton<_ActivityFilter>(
      tooltip: 'Filtrar actividad',
      initialValue: selected,
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      elevation: 8,
      color: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.65),
        ),
      ),
      constraints: const BoxConstraints(minWidth: 205, maxWidth: 220),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final filter in _ActivityFilter.values)
          PopupMenuItem<_ActivityFilter>(
            value: filter,
            height: 42,
            child: Row(
              children: [
                Icon(
                  filter.icon,
                  size: 17,
                  color: filter == selected
                      ? filter.accent
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    filter.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: filter == selected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${_countFor(filter)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 16,
                  child: filter == selected
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: filter.accent,
                        )
                      : null,
                ),
              ],
            ),
          ),
      ],
      child: Semantics(
        button: true,
        label: 'Filtrar actividad: ${selected.label}',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFiltered ? selected.icon : Icons.filter_list_rounded,
                size: 16,
                color: isFiltered
                    ? selected.accent
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                selected.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isFiltered
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isFiltered ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 1),
              Icon(
                Icons.expand_more_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenSection extends StatelessWidget {
  const _OpenSection({
    required this.title,
    required this.trailing,
    required this.accent,
    required this.child,
    this.trailingWidget,
  });

  final String title;
  final String trailing;
  final Color accent;
  final Widget child;
  final Widget? trailingWidget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 18,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            trailingWidget ??
                Text(
                  trailing,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
          ],
        ),
        const SizedBox(height: 9),
        child,
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.count,
    required this.accent,
    required this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final int count;
  final Color accent;
  final VoidCallback onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 27,
              height: 27,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 15, color: accent),
            ),
            const SizedBox(width: 9),
            Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
            Text(
              '$count',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (showChevron) ...[
              const SizedBox(width: 3),
              Icon(Icons.chevron_right, size: 18, color: accent),
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
      borderRadius: BorderRadius.circular(7),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _filesAccent.withValues(alpha: 0.11),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                _iconForFile(file),
                size: 16,
                color: _filesAccent,
              ),
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
  const _ActivityRow({
    required this.item,
    required this.isLast,
    required this.onTap,
  });

  final _BriefingActivityItem item;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowHeight = item.subtitle.trim().isEmpty ? 46.0 : 72.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(
        height: rowHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 32,
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  if (!isLast)
                    Positioned(
                      top: 28,
                      bottom: 0,
                      child: Container(
                        width: 1,
                        color: item.accent.withValues(alpha: 0.25),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: item.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: item.accent.withValues(alpha: 0.28),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: item.platformKey == null
                          ? Icon(item.icon, size: 14, color: item.accent)
                          : FaIcon(
                              ConversationChannelPresentation
                                  .platformIconForChannel(
                                item.platformKey,
                              ),
                              size: 14,
                              color: item.accent,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 7, bottom: 12),
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
                              fontWeight: item.unread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (item.unread) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: item.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          _compactTime(item.createdAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
            ),
          ],
        ),
      ),
    );
  }
}

class _QuietState extends StatelessWidget {
  const _QuietState({
    required this.icon,
    required this.text,
    this.accent,
  });

  final IconData icon;
  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedAccent = accent ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: resolvedAccent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 15, color: resolvedAccent),
          ),
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

String _weekdayLabel(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return 'L';
    case DateTime.tuesday:
      return 'M';
    case DateTime.wednesday:
      return 'X';
    case DateTime.thursday:
      return 'J';
    case DateTime.friday:
      return 'V';
    case DateTime.saturday:
      return 'S';
    default:
      return 'D';
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
    required this.kind,
    required this.unread,
    this.notificationId,
    this.platformKey,
  });

  final String title;
  final String subtitle;
  final DateTime createdAt;
  final String route;
  final IconData icon;
  final Color accent;
  final _BriefingActivityKind kind;
  final bool unread;
  final String? notificationId;
  final String? platformKey;
}

void _navigateToRoute(BuildContext context, String route) {
  final trustedExternalUri = trustedMetaNotificationUrl(route);
  if (trustedExternalUri != null) {
    unawaited(
      launchUrl(
        trustedExternalUri,
        mode: LaunchMode.externalApplication,
      ).then<void>(
        (opened) {
          if (!opened && context.mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text('No se pudo abrir la interacción de Meta.'),
              ),
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('No se pudo abrir la interacción de Meta: $error');
        },
      ),
    );
    return;
  }

  try {
    context.read<WorkspaceManager>().navigateActiveWorkspaceFromSharedLink(
          route,
        );
  } catch (_) {
    context.go(route);
  }
}

IconData _iconForNotificationType(String type) {
  if (type.startsWith('meta_instagram_')) {
    return ConversationChannelPresentation.iconForChannel('instagram');
  }
  if (type.startsWith('meta_facebook_')) {
    return ConversationChannelPresentation.iconForChannel(
      'facebook_messenger',
    );
  }
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

String? _platformKeyForNotificationType(String type) {
  if (type.startsWith('meta_instagram_')) return 'instagram';
  if (type.startsWith('meta_facebook_')) return 'facebook';
  return null;
}

_BriefingActivityKind _kindForNotificationType(String type) {
  switch (type) {
    case 'mechanic_job_created':
      return _BriefingActivityKind.job;
    case 'sales_payment_received':
      return _BriefingActivityKind.payment;
    case 'online_order_created':
      return _BriefingActivityKind.order;
    default:
      return _BriefingActivityKind.alert;
  }
}

Color _accentForNotificationType(String type) {
  if (type.startsWith('meta_instagram_')) {
    return ConversationChannelPresentation.instagramAccent;
  }
  if (type.startsWith('meta_facebook_')) {
    return ConversationChannelPresentation.facebookMessengerAccent;
  }
  switch (type) {
    case 'mechanic_job_created':
      return _jobsAccent;
    case 'sales_payment_received':
      return _paymentsAccent;
    case 'online_order_created':
      return _ordersAccent;
    case 'whatsapp_catalog_approved':
      return _paymentsAccent;
    default:
      return _warningAccent;
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
