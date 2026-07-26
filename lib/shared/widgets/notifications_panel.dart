import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../../modules/hr/models/hr_models.dart';
import '../../modules/hr/services/hr_service.dart';
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
import '../utils/notification_deep_link.dart';
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
  DateTimeRange? _customDateRange;
  _ActivityFilter _activityFilter = _ActivityFilter.all;
  List<Map<String, dynamic>> _periodNotifications = const [];
  List<AppStoredFile> _files = const [];
  List<CurrentAttendanceBriefingEntry> _currentAttendances = const [];
  StreamSubscription<AppStoredFile>? _savedFileSubscription;
  Timer? _briefingClock;
  final GlobalKey _activitySectionKey = GlobalKey();
  final GlobalKey _periodMenuAnchorKey = GlobalKey();
  int _periodLoadEpoch = 0;
  int _filesLoadEpoch = 0;
  int _attendanceLoadEpoch = 0;
  bool _loadingPeriodNotifications = true;
  bool _loadingFiles = true;
  bool _loadingAttendances = true;
  Object? _periodNotificationsError;
  Object? _filesError;
  Object? _attendancesError;
  DateTime _briefingNow = DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_loadPeriodNotifications());
    unawaited(_loadFiles());
    unawaited(_loadAttendances());
    _savedFileSubscription = _filesService.savedFiles.listen(_recordSavedFile);
    _scheduleBriefingTick();
  }

  @override
  void dispose() {
    _savedFileSubscription?.cancel();
    _briefingClock?.cancel();
    super.dispose();
  }

  void _scheduleBriefingTick() {
    final now = DateTime.now();
    final untilNextMinute = const Duration(minutes: 1) -
        Duration(seconds: now.second, milliseconds: now.millisecond);
    _briefingClock = Timer(untilNextMinute, () {
      if (!mounted) return;
      final previousDay = NotificationDigestWindow.businessToday(
        now: _briefingNow,
      );
      final nextNow = DateTime.now();
      final nextDay = NotificationDigestWindow.businessToday(now: nextNow);
      setState(() => _briefingNow = nextNow);
      if (!_loadingAttendances) {
        unawaited(_loadAttendances(silent: true));
      }
      if (previousDay != nextDay) {
        unawaited(_loadPeriodNotifications(silent: true));
        unawaited(_loadFiles(silent: true));
      }
      _scheduleBriefingTick();
    });
  }

  NotificationDigestWindow _currentWindow() {
    return NotificationDigestWindow.resolve(
      period: _period,
      now: _briefingNow,
      customStartDate: _customDateRange?.start,
      customEndDate: _customDateRange?.end,
    );
  }

  Future<void> _loadPeriodNotifications({bool silent = false}) async {
    final loadEpoch = ++_periodLoadEpoch;
    final window = _currentWindow();
    if (mounted && !silent) {
      setState(() {
        _loadingPeriodNotifications = true;
        _periodNotificationsError = null;
      });
    }
    try {
      final rows = await _notifications.loadNotificationsForRange(
        startsAt: window.startsAt,
        endsAt: window.endsAt,
      );
      if (!mounted || loadEpoch != _periodLoadEpoch) return;
      setState(() {
        _periodNotifications = rows;
        _loadingPeriodNotifications = false;
        _periodNotificationsError = null;
      });
    } catch (error) {
      if (!mounted || loadEpoch != _periodLoadEpoch || silent) return;
      setState(() {
        _loadingPeriodNotifications = false;
        _periodNotificationsError = error;
      });
    }
  }

  Future<void> _loadFiles({bool silent = false}) async {
    final loadEpoch = ++_filesLoadEpoch;
    final window = _currentWindow();
    if (mounted && !silent) {
      setState(() {
        _loadingFiles = true;
        _filesError = null;
      });
    }
    try {
      final files = await _filesService.listFilesForRange(
        startsAt: window.startsAt,
        endsAt: window.endsAt,
      );
      if (!mounted || loadEpoch != _filesLoadEpoch) return;
      setState(() {
        _files = files;
        _loadingFiles = false;
      });
    } catch (error) {
      if (!mounted || loadEpoch != _filesLoadEpoch || silent) return;
      setState(() {
        _loadingFiles = false;
        _filesError = error;
      });
    }
  }

  void _recordSavedFile(AppStoredFile file) {
    if (!mounted || !_currentWindow().contains(file.createdAt)) return;
    setState(() {
      _files = [
        file,
        ..._files.where((candidate) => candidate.id != file.id),
      ];
      _filesError = null;
    });
  }

  Future<void> _loadAttendances({bool silent = false}) async {
    final loadEpoch = ++_attendanceLoadEpoch;
    if (mounted && !silent) {
      setState(() {
        _loadingAttendances = true;
        _attendancesError = null;
      });
    }
    try {
      final entries =
          await context.read<HRService>().getCurrentAttendanceBriefing();
      if (!mounted || loadEpoch != _attendanceLoadEpoch) return;
      setState(() {
        _currentAttendances = entries;
        _briefingNow = DateTime.now();
        _loadingAttendances = false;
        _attendancesError = null;
      });
    } catch (error) {
      if (!mounted || loadEpoch != _attendanceLoadEpoch || silent) return;
      setState(() {
        _loadingAttendances = false;
        _attendancesError = error;
      });
    }
  }

  Future<void> _selectPeriod(NotificationDigestPeriod nextPeriod) async {
    DateTimeRange? nextCustomRange = _customDateRange;
    if (nextPeriod == NotificationDigestPeriod.custom) {
      final today = NotificationDigestWindow.businessToday();
      final currentWindow = _currentWindow();
      final firstDate = DateTime(today.year - 10);
      final initialStart = currentWindow.startDate.isBefore(firstDate)
          ? firstDate
          : currentWindow.startDate;
      final initialEnd =
          currentWindow.endDate.isAfter(today) ? today : currentWindow.endDate;
      final anchorBox =
          _periodMenuAnchorKey.currentContext?.findRenderObject() as RenderBox?;
      final overlayBox = Navigator.of(
        context,
        rootNavigator: true,
      ).overlay?.context.findRenderObject() as RenderBox?;
      if (anchorBox == null ||
          !anchorBox.attached ||
          overlayBox == null ||
          !overlayBox.attached) {
        return;
      }
      final anchorTopLeft = anchorBox.localToGlobal(
        Offset.zero,
        ancestor: overlayBox,
      );
      final anchorBottomRight = anchorBox.localToGlobal(
        anchorBox.size.bottomRight(Offset.zero),
        ancestor: overlayBox,
      );
      final anchorRect = Rect.fromPoints(anchorTopLeft, anchorBottomRight);
      final picked = await showGeneralDialog<DateTimeRange>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Cerrar rango personalizado',
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return _AnchoredDateRangePopover(
            anchorRect: anchorRect,
            overlaySize: overlayBox.size,
            firstDate: firstDate,
            lastDate: today,
            initialRange: DateTimeRange(
              start:
                  initialStart.isAfter(initialEnd) ? initialEnd : initialStart,
              end: initialEnd,
            ),
            onCancel: () => Navigator.of(dialogContext).pop(),
            onApply: (range) => Navigator.of(dialogContext).pop(range),
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.012),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
      if (picked == null || !mounted) return;
      nextCustomRange = picked;
    }

    if (!mounted) return;
    setState(() {
      _period = nextPeriod;
      _customDateRange = nextCustomRange;
    });
    await Future.wait([
      _loadPeriodNotifications(),
      _loadFiles(),
    ]);
  }

  Future<void> _markPeriodAlertsRead() async {
    final window = _currentWindow();
    final readAt = DateTime.now().toUtc().toIso8601String();
    if (mounted) {
      setState(() {
        _periodNotifications = _periodNotifications
            .map(
              (row) => row['read_at'] == null &&
                      _notificationDateIsInWindow(row, window)
                  ? {...row, 'read_at': readAt}
                  : row,
            )
            .toList(growable: false);
      });
    }
    await _notifications.markNotificationsReadForRange(
      startsAt: window.startsAt,
      endsAt: window.endsAt,
    );
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
            final rows = _mergeNotificationRows(
              _periodNotifications,
              _notifications.notificationsFeed.value,
            );
            final digest = NotificationDigestSnapshot.fromRows(
              period: _period,
              notifications: rows,
              fileCreatedAt: _files.map((file) => file.createdAt),
              customStartDate: _customDateRange?.start,
              customEndDate: _customDateRange?.end,
              now: _briefingNow,
            );
            final periodFiles = _files
                .where((file) => digest.contains(file.createdAt))
                .toList(growable: false);
            final activity = _buildActivity(
              rows,
              _mail.briefingEmails,
              chat,
              periodFiles,
              digest,
            );
            final unreadEmails = _mail.briefingEmails
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
                  customDateRange: _customDateRange,
                  periodMenuAnchorKey: _periodMenuAnchorKey,
                  unreadAlerts: digest.unreadAlertCount,
                  onPeriodChanged: _selectPeriod,
                  onMarkAlertsRead: _markPeriodAlertsRead,
                ),
                Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    const Divider(height: 1),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 160),
                      opacity: _loadingPeriodNotifications ? 1 : 0,
                      child: LinearProgressIndicator(
                        minHeight: 2,
                        color: Theme.of(context).colorScheme.primary,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                  ],
                ),
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
                      key: ValueKey(
                        '${_period.name}:'
                        '${_customDateRange?.start.toIso8601String() ?? ''}:'
                        '${_customDateRange?.end.toIso8601String() ?? ''}',
                      ),
                      onRefresh: () async {
                        await Future.wait([
                          _loadPeriodNotifications(),
                          _loadFiles(),
                          _loadAttendances(),
                          _mail.backgroundRefresh(),
                        ]);
                      },
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          _BriefingHero(
                            digest: digest,
                            items: activity,
                            now: _briefingNow,
                          ),
                          if (_periodNotificationsError != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                              child: _InlineError(
                                message:
                                    'No se pudo completar este período. Se muestran los datos recientes disponibles.',
                                onRetry: _loadPeriodNotifications,
                              ),
                            ),
                          _MetricsRibbon(
                            digest: digest,
                            onNavigate: widget.onNavigate,
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                            child: _AttendanceNowSection(
                              entries: _currentAttendances,
                              now: _briefingNow,
                              loading: _loadingAttendances,
                              hasError: _attendancesError != null,
                              onRetry: _loadAttendances,
                              onOpenAll: () => widget.onNavigate(
                                _attendanceDayRoute(_briefingNow),
                              ),
                              onOpenEntry: (entry) => widget.onNavigate(
                                _attendanceEntryRoute(entry),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                            child: _AttentionSection(
                              unreadEmails: unreadEmails,
                              unreadChats: unreadChats,
                              operationalAlerts: digest.unreadAlertCount,
                              onNavigate: widget.onNavigate,
                              onShowOperationalAlerts: _showOperationalAlerts,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                            child: _FilesSection(
                              digest: digest,
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
                              key: _activitySectionKey,
                              items: activity,
                              digest: digest,
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

  void _showOperationalAlerts() {
    setState(() => _activityFilter = _ActivityFilter.operational);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activityContext = _activitySectionKey.currentContext;
      if (!mounted || activityContext == null) return;
      Scrollable.ensureVisible(
        activityContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.06,
      );
    });
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
      final route = resolveErpNotificationRoute(row);
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
          route: buildMailMessageRoute(
            providerId: email.providerId,
            messageId: email.id,
          ),
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
          route: buildStoredFileRoute(file.id),
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
const _expensesAccent = Color(0xFF9A6332);
const _ordersAccent = Color(0xFF7758A6);
const _filesAccent = Color(0xFFC4772D);
const _mailAccent = Color(0xFF3D6FA8);
const _chatAccent = Color(0xFF7559A5);
const _attendanceAccent = Color(0xFF347E79);
const _warningAccent = Color(0xFFC27A22);

enum _BriefingActivityKind {
  job,
  payment,
  expense,
  order,
  email,
  chat,
  file,
  alert
}

enum _ActivityFilter {
  all,
  operational,
  jobs,
  payments,
  expenses,
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
      case _ActivityFilter.operational:
        return 'Operacionales';
      case _ActivityFilter.jobs:
        return 'Trabajos';
      case _ActivityFilter.payments:
        return 'Pagos';
      case _ActivityFilter.expenses:
        return 'Gastos';
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
      case _ActivityFilter.operational:
        return 'No hay alertas operativas en este período.';
      case _ActivityFilter.jobs:
        return 'No hay trabajos registrados en este período.';
      case _ActivityFilter.payments:
        return 'No hay pagos registrados en este período.';
      case _ActivityFilter.expenses:
        return 'No hay gastos registrados en este período.';
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
      case _ActivityFilter.operational:
        return Icons.notifications_active_outlined;
      case _ActivityFilter.jobs:
        return Icons.build_outlined;
      case _ActivityFilter.payments:
        return Icons.payments_outlined;
      case _ActivityFilter.expenses:
        return Icons.receipt_long_outlined;
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
      case _ActivityFilter.operational:
        return _warningAccent;
      case _ActivityFilter.payments:
        return _paymentsAccent;
      case _ActivityFilter.expenses:
        return _expensesAccent;
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
      case _ActivityFilter.operational:
        return kind == _BriefingActivityKind.job ||
            kind == _BriefingActivityKind.payment ||
            kind == _BriefingActivityKind.expense ||
            kind == _BriefingActivityKind.order ||
            kind == _BriefingActivityKind.alert;
      case _ActivityFilter.jobs:
        return kind == _BriefingActivityKind.job;
      case _ActivityFilter.payments:
        return kind == _BriefingActivityKind.payment;
      case _ActivityFilter.expenses:
        return kind == _BriefingActivityKind.expense;
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
    required this.customDateRange,
    required this.periodMenuAnchorKey,
    required this.unreadAlerts,
    required this.onPeriodChanged,
    required this.onMarkAlertsRead,
  });

  final NotificationDigestPeriod period;
  final DateTimeRange? customDateRange;
  final GlobalKey periodMenuAnchorKey;
  final int unreadAlerts;
  final Future<void> Function(NotificationDigestPeriod) onPeriodChanged;
  final Future<void> Function() onMarkAlertsRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 360;
          return Row(
            children: [
              _PeriodTab(
                label: 'Hoy',
                selected: period == NotificationDigestPeriod.today,
                onTap: () => onPeriodChanged(NotificationDigestPeriod.today),
              ),
              const SizedBox(width: 18),
              _DigestPeriodMenu(
                period: period,
                customDateRange: customDateRange,
                anchorKey: periodMenuAnchorKey,
                onSelected: onPeriodChanged,
              ),
              const Spacer(),
              if (unreadAlerts > 0)
                Tooltip(
                  message: 'Marcar alertas de este período como leídas',
                  child: TextButton.icon(
                    onPressed: onMarkAlertsRead,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(40, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                    ),
                    icon: const Icon(Icons.done_all, size: 17),
                    label: Text(
                      compact ? '$unreadAlerts' : '$unreadAlerts nuevas',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DigestPeriodMenu extends StatelessWidget {
  const _DigestPeriodMenu({
    required this.period,
    required this.customDateRange,
    required this.anchorKey,
    required this.onSelected,
  });

  final NotificationDigestPeriod period;
  final DateTimeRange? customDateRange;
  final GlobalKey anchorKey;
  final Future<void> Function(NotificationDigestPeriod) onSelected;

  static const _presets = <NotificationDigestPeriod>[
    NotificationDigestPeriod.thisWeek,
    NotificationDigestPeriod.previousWeek,
    NotificationDigestPeriod.thisMonth,
    NotificationDigestPeriod.previousMonth,
    NotificationDigestPeriod.thisYear,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = period != NotificationDigestPeriod.today;
    final label =
        selected ? _periodTriggerLabel(period, customDateRange) : 'Período';

    return SizedBox(
      key: anchorKey,
      child: PopupMenuButton<NotificationDigestPeriod>(
        key: const ValueKey<String>('notification-period-trigger'),
        tooltip: 'Cambiar período',
        initialValue: selected ? period : null,
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        elevation: 12,
        color: theme.colorScheme.surfaceContainerLowest,
        surfaceTintColor: theme.colorScheme.surfaceTint,
        constraints: const BoxConstraints(minWidth: 210, maxWidth: 238),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        onSelected: (value) => unawaited(onSelected(value)),
        itemBuilder: (context) => [
          for (final preset in _presets)
            _periodMenuItem(context, preset, period),
          const PopupMenuDivider(height: 9),
          _periodMenuItem(
            context,
            NotificationDigestPeriod.custom,
            period,
            leading: Icons.edit_calendar_outlined,
          ),
        ],
        child: Semantics(
          button: true,
          selected: selected,
          label: selected
              ? 'Período seleccionado: ${_periodAccessibleLabel(period, customDateRange)}'
              : 'Seleccionar otro período',
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 180),
                      style: (theme.textTheme.labelLarge ?? const TextStyle())
                          .copyWith(
                        color: selected
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 116),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 17,
                      color: selected
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
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
        ),
      ),
    );
  }

  PopupMenuItem<NotificationDigestPeriod> _periodMenuItem(
    BuildContext context,
    NotificationDigestPeriod value,
    NotificationDigestPeriod selected, {
    IconData? leading,
  }) {
    final theme = Theme.of(context);
    final isSelected = value == selected;
    return PopupMenuItem<NotificationDigestPeriod>(
      value: value,
      height: 44,
      child: Row(
        children: [
          if (leading != null) ...[
            Icon(
              leading,
              size: 17,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              _periodPresetLabel(value),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 140),
            opacity: isSelected ? 1 : 0,
            child: Icon(
              Icons.check_rounded,
              size: 17,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnchoredDateRangePopover extends StatelessWidget {
  const _AnchoredDateRangePopover({
    required this.anchorRect,
    required this.overlaySize,
    required this.firstDate,
    required this.lastDate,
    required this.initialRange,
    required this.onCancel,
    required this.onApply,
  });

  final Rect anchorRect;
  final Size overlaySize;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange initialRange;
  final VoidCallback onCancel;
  final ValueChanged<DateTimeRange> onApply;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    const edgeInset = 12.0;
    const preferredWidth = 360.0;
    const preferredHeight = 420.0;
    final availableWidth = overlaySize.width - (edgeInset * 2);
    final availableHeight =
        overlaySize.height - media.padding.vertical - (edgeInset * 2);
    final width =
        availableWidth < preferredWidth ? availableWidth : preferredWidth;
    final height =
        availableHeight < preferredHeight ? availableHeight : preferredHeight;
    const minLeft = edgeInset;
    final maxLeft = overlaySize.width - width - edgeInset;
    final minTop = media.padding.top + edgeInset;
    final maxTop =
        overlaySize.height - media.padding.bottom - height - edgeInset;

    var left = anchorRect.left;
    if (left + width > overlaySize.width - edgeInset) {
      left = anchorRect.right - width;
    }
    left = left.clamp(minLeft, maxLeft).toDouble();

    var top = anchorRect.bottom + 8;
    if (top > maxTop) top = anchorRect.top - height - 8;
    top = top.clamp(minTop, maxTop).toDouble();

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: width,
            height: height,
            child: SizedBox(
              key: const ValueKey<String>('notification-date-range-popover'),
              child: _DateRangePopover(
                firstDate: firstDate,
                lastDate: lastDate,
                initialRange: initialRange,
                onCancel: onCancel,
                onApply: onApply,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateRangePopover extends StatefulWidget {
  const _DateRangePopover({
    required this.firstDate,
    required this.lastDate,
    required this.initialRange,
    required this.onCancel,
    required this.onApply,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange initialRange;
  final VoidCallback onCancel;
  final ValueChanged<DateTimeRange> onApply;

  @override
  State<_DateRangePopover> createState() => _DateRangePopoverState();
}

class _DateRangePopoverState extends State<_DateRangePopover> {
  late DateTime _visibleMonth;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  @override
  void initState() {
    super.initState();
    _rangeStart = _dateOnly(widget.initialRange.start);
    _rangeEnd = _dateOnly(widget.initialRange.end);
    final focusedDate = _rangeEnd ?? _rangeStart ?? widget.lastDate;
    _visibleMonth = DateTime(focusedDate.year, focusedDate.month);
  }

  bool get _canApply => _rangeStart != null && _rangeEnd != null;

  void _selectDate(DateTime date) {
    if (date.isBefore(widget.firstDate) || date.isAfter(widget.lastDate)) {
      return;
    }
    setState(() {
      if (_rangeStart == null || _rangeEnd != null) {
        _rangeStart = date;
        _rangeEnd = null;
      } else if (date.isBefore(_rangeStart!)) {
        _rangeEnd = _rangeStart;
        _rangeStart = date;
      } else {
        _rangeEnd = date;
      }
    });
  }

  void _changeMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(
        _visibleMonth.year,
        _visibleMonth.month + delta,
      );
    });
  }

  bool _canChangeMonth(int delta) {
    final target = DateTime(
      _visibleMonth.year,
      _visibleMonth.month + delta,
    );
    if (delta < 0) {
      final targetEnd = DateTime(target.year, target.month + 1, 0);
      return !targetEnd.isBefore(widget.firstDate);
    }
    return !target.isAfter(widget.lastDate);
  }

  String _selectionLabel() {
    final start = _rangeStart;
    final end = _rangeEnd;
    if (start == null) return 'Selecciona la fecha inicial';
    if (end == null) {
      return '${_periodRangeLabel(start, start, includeYear: true)} · '
          'elige la fecha final';
    }
    return _periodRangeLabel(start, end, includeYear: true);
  }

  int? _selectedDayCount() {
    final start = _rangeStart;
    final end = _rangeEnd;
    if (start == null || end == null) return null;
    final civilStart = DateTime.utc(start.year, start.month, start.day);
    final civilEnd = DateTime.utc(end.year, end.month, end.day);
    return civilEnd.difference(civilStart).inDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final firstOfMonth = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    final leadingDays = firstOfMonth.weekday - DateTime.monday;
    final daysInMonth = DateUtils.getDaysInMonth(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    final selectedDays = _selectedDayCount();

    return Semantics(
      container: true,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Rango personalizado',
      child: Material(
        color: theme.colorScheme.surfaceContainerLowest,
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: 0.24),
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.58),
          ),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 58,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rango personalizado',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectionLabel(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: widget.onCancel,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ),
            Divider(
                height: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
            SizedBox(
              height: 42,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Mes anterior',
                    onPressed:
                        _canChangeMonth(-1) ? () => _changeMonth(-1) : null,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_left_rounded, size: 21),
                  ),
                  Expanded(
                    child: Text(
                      '${_briefingMonthLong[_visibleMonth.month - 1]} '
                      'de ${_visibleMonth.year}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Mes siguiente',
                    onPressed:
                        _canChangeMonth(1) ? () => _changeMonth(1) : null,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chevron_right_rounded, size: 21),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 24,
              child: Row(
                children: [
                  for (var weekday = 1; weekday <= 7; weekday++)
                    Expanded(
                      child: Center(
                        child: Text(
                          _weekdayLabel(weekday),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cellWidth = (constraints.maxWidth - 24) / 7;
                  final cellHeight = (constraints.maxHeight - 8) / 6;
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 42,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: cellWidth / cellHeight,
                    ),
                    itemBuilder: (context, index) {
                      final dayNumber = index - leadingDays + 1;
                      if (dayNumber < 1 || dayNumber > daysInMonth) {
                        return const SizedBox.shrink();
                      }
                      final day = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month,
                        dayNumber,
                      );
                      return _DateRangeDay(
                        date: day,
                        rangeStart: _rangeStart,
                        rangeEnd: _rangeEnd,
                        enabled: !day.isBefore(widget.firstDate) &&
                            !day.isAfter(widget.lastDate),
                        accent: accent,
                        onTap: () => _selectDate(day),
                      );
                    },
                  );
                },
              ),
            ),
            Divider(
                height: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedDays == null
                            ? 'Elige dos fechas'
                            : '$selectedDays '
                                '${selectedDays == 1 ? 'día' : 'días'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onCancel,
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: !_canApply
                          ? null
                          : () => widget.onApply(
                                DateTimeRange(
                                  start: _rangeStart!,
                                  end: _rangeEnd!,
                                ),
                              ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(76, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        visualDensity: VisualDensity.compact,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Aplicar'),
                    ),
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

class _DateRangeDay extends StatelessWidget {
  const _DateRangeDay({
    required this.date,
    required this.rangeStart,
    required this.rangeEnd,
    required this.enabled,
    required this.accent,
    required this.onTap,
  });

  final DateTime date;
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final bool enabled;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isStart = _sameCalendarDate(date, rangeStart);
    final isEnd = _sameCalendarDate(date, rangeEnd);
    final isEndpoint = isStart || isEnd;
    final inRange = rangeStart != null &&
        rangeEnd != null &&
        !date.isBefore(rangeStart!) &&
        !date.isAfter(rangeEnd!);
    final today = NotificationDigestWindow.businessToday();
    final isToday = _sameCalendarDate(date, today);
    final stateLabel = isStart && isEnd
        ? 'inicio y fin del rango'
        : isStart
            ? 'inicio del rango'
            : isEnd
                ? 'fin del rango'
                : inRange
                    ? 'dentro del rango'
                    : isToday
                        ? 'hoy'
                        : null;
    final accessibleDate = '${_briefingWeekdayLong[date.weekday - 1]}, '
        '${date.day} de ${_briefingMonthLong[date.month - 1]} de ${date.year}';

    return Semantics(
      button: true,
      enabled: enabled,
      selected: isEndpoint || inRange,
      label:
          stateLabel == null ? accessibleDate : '$accessibleDate, $stateLabel',
      child: Opacity(
        opacity: enabled ? 1 : 0.34,
        child: Material(
          color: inRange
              ? accent.withValues(alpha: isEndpoint ? 0.08 : 0.11)
              : Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isEndpoint ? accent : Colors.transparent,
                  shape: BoxShape.circle,
                  border: isToday && !isEndpoint
                      ? Border.all(color: accent.withValues(alpha: 0.72))
                      : null,
                ),
                child: Text(
                  '${date.day}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isEndpoint
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    fontWeight: isEndpoint || isToday
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
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
  const _BriefingHero({
    required this.digest,
    required this.items,
    required this.now,
  });

  final NotificationDigestSnapshot digest;
  final List<_BriefingActivityItem> items;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Container(
      color: accent.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.14 : 0.065,
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 340;
          final title = Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _periodHeroTitle(digest.period),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _periodRangeLabel(
                    digest.startDate,
                    digest.endDate,
                    includeYear: true,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
          final activityTotal = Column(
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
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  const SizedBox(width: 12),
                  if (isCompact)
                    activityTotal
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _ChileClock(now: now, accent: accent),
                        const SizedBox(width: 12),
                        activityTotal,
                      ],
                    ),
                ],
              ),
              if (isCompact) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: _ChileClock(now: now, accent: accent),
                ),
              ],
              const SizedBox(height: 12),
              _ActivityPulse(digest: digest, items: items, accent: accent),
            ],
          );
        },
      ),
    );
  }
}

class _ChileClock extends StatelessWidget {
  const _ChileClock({required this.now, required this.accent});

  final DateTime now;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = _chileClockTime(now);
    return Semantics(
      label: 'Hora de Chile, $time',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(
            alpha: theme.brightness == Brightness.dark ? 0.72 : 0.78,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_rounded, size: 14, color: accent),
            const SizedBox(width: 5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HORA CHILE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.55,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  time,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.25,
                    height: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityPulse extends StatelessWidget {
  const _ActivityPulse({
    required this.digest,
    required this.items,
    required this.accent,
  });

  final NotificationDigestSnapshot digest;
  final List<_BriefingActivityItem> items;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final buckets = _activityPulseBuckets(digest, items);
    final counts = buckets.map((bucket) => bucket.count).toList();

    var maxCount = 1;
    for (final count in counts) {
      if (count > maxCount) maxCount = count;
    }

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
                    buckets[index].label,
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
                label: 'Gastos',
                value: digest.expenseTotal > 0
                    ? ChileanUtils.formatCurrency(digest.expenseTotal)
                    : r'$0',
                hint: '${digest.expenseCount} mov.',
                icon: Icons.receipt_long_outlined,
                accent: _expensesAccent,
                onTap: () => onNavigate('/accounting/expenses'),
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

class _AttendanceNowSection extends StatelessWidget {
  const _AttendanceNowSection({
    required this.entries,
    required this.now,
    required this.loading,
    required this.hasError,
    required this.onRetry,
    required this.onOpenAll,
    required this.onOpenEntry,
  });

  final List<CurrentAttendanceBriefingEntry> entries;
  final DateTime now;
  final bool loading;
  final bool hasError;
  final Future<void> Function() onRetry;
  final VoidCallback onOpenAll;
  final ValueChanged<CurrentAttendanceBriefingEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final visibleEntries = entries.take(4).toList(growable: false);
    final peopleLabel =
        entries.length == 1 ? '1 persona' : '${entries.length} personas';

    return _OpenSection(
      title: 'Ahora en el local',
      trailing: peopleLabel,
      trailingWidget: _AttendanceSectionLink(
        label: loading ? 'Actualizando' : peopleLabel,
        onTap: onOpenAll,
      ),
      accent: _attendanceAccent,
      child: hasError
          ? _InlineError(
              message: 'No se pudo actualizar la asistencia.',
              onRetry: onRetry,
            )
          : loading && entries.isEmpty
              ? LinearProgressIndicator(
                  minHeight: 2,
                  color: _attendanceAccent,
                  backgroundColor: _attendanceAccent.withValues(alpha: 0.12),
                )
              : entries.isEmpty
                  ? const _QuietState(
                      icon: Icons.person_off_outlined,
                      text: 'Nadie ha marcado entrada.',
                      accent: _attendanceAccent,
                    )
                  : Column(
                      children: [
                        for (var index = 0;
                            index < visibleEntries.length;
                            index++) ...[
                          _AttendanceNowRow(
                            entry: visibleEntries[index],
                            now: now,
                            onTap: () => onOpenEntry(visibleEntries[index]),
                          ),
                          if (index < visibleEntries.length - 1)
                            Divider(
                              height: 1,
                              indent: 40,
                              color: Theme.of(context)
                                  .dividerColor
                                  .withValues(alpha: 0.45),
                            ),
                        ],
                        if (entries.length > visibleEntries.length)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: onOpenAll,
                              child: Text(
                                'Ver ${entries.length - visibleEntries.length} '
                                'más',
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}

class _AttendanceSectionLink extends StatelessWidget {
  const _AttendanceSectionLink({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Abrir control de asistencia',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 3, 0, 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
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

class _AttendanceNowRow extends StatelessWidget {
  const _AttendanceNowRow({
    required this.entry,
    required this.now,
    required this.onTap,
  });

  final CurrentAttendanceBriefingEntry entry;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final elapsed = _attendanceElapsed(entry.attendance.checkIn, now);
    final needsReview = elapsed >= const Duration(hours: 18);
    final accent = needsReview ? _warningAccent : _attendanceAccent;
    final title = entry.employee.fullName.trim();
    final jobTitle = entry.employee.jobTitle.trim();

    return Semantics(
      button: true,
      label: '${title.isEmpty ? 'Trabajador' : title}, entrada '
          '${_chileClockTime(entry.attendance.checkIn)}, '
          '${_attendanceDuration(elapsed)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _employeeInitials(entry.employee),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 1,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? 'Trabajador' : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      jobTitle.isEmpty ? 'Jornada en curso' : jobTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 154),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (needsReview) ...[
                          Icon(
                            Icons.error_outline_rounded,
                            size: 13,
                            color: accent,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Flexible(
                          child: Text(
                            needsReview
                                ? 'Revisar marcación'
                                : 'Jornada en curso',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Entrada ${_chileClockTime(entry.attendance.checkIn)}'
                      ' · ${_attendanceDuration(elapsed)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
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
    required this.onShowOperationalAlerts,
  });

  final int unreadEmails;
  final int unreadChats;
  final int operationalAlerts;
  final void Function(String route) onNavigate;
  final VoidCallback onShowOperationalAlerts;

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
                onTap: onShowOperationalAlerts,
              ),
          ],
        ],
      ),
    );
  }
}

class _FilesSection extends StatelessWidget {
  const _FilesSection({
    required this.digest,
    required this.files,
    required this.loading,
    required this.hasError,
    required this.onRetry,
    required this.onNavigate,
  });

  final NotificationDigestSnapshot digest;
  final List<AppStoredFile> files;
  final bool loading;
  final bool hasError;
  final Future<void> Function() onRetry;
  final void Function(String route) onNavigate;

  @override
  Widget build(BuildContext context) {
    final visibleFiles = files.take(4).toList(growable: false);
    return _OpenSection(
      title: _filesPeriodTitle(digest.period),
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
                            onTap: () =>
                                onNavigate(buildStoredFileRoute(file.id)),
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

class _ActivitySection extends StatefulWidget {
  const _ActivitySection({
    super.key,
    required this.items,
    required this.digest,
    required this.filter,
    required this.onFilterChanged,
    required this.onTap,
  });

  final List<_BriefingActivityItem> items;
  final NotificationDigestSnapshot digest;
  final _ActivityFilter filter;
  final ValueChanged<_ActivityFilter> onFilterChanged;
  final ValueChanged<_BriefingActivityItem> onTap;

  @override
  State<_ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends State<_ActivitySection> {
  static const int _activityBatchSize = 12;

  int _visibleLimit = _activityBatchSize;

  @override
  void didUpdateWidget(covariant _ActivitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final periodChanged = oldWidget.digest.period != widget.digest.period ||
        oldWidget.digest.startDate != widget.digest.startDate ||
        oldWidget.digest.endDate != widget.digest.endDate;
    if (oldWidget.filter != widget.filter || periodChanged) {
      _visibleLimit = _activityBatchSize;
    }
  }

  void _showMore() {
    setState(() => _visibleLimit += _activityBatchSize);
  }

  @override
  Widget build(BuildContext context) {
    final filteredItems = widget.items
        .where((item) => widget.filter.includes(item.kind))
        .toList(growable: false);
    final visibleItems =
        filteredItems.take(_visibleLimit).toList(growable: false);
    final remaining = filteredItems.length - visibleItems.length;
    final nextBatchCount =
        remaining < _activityBatchSize ? remaining : _activityBatchSize;

    return _OpenSection(
      title: 'Actividad reciente',
      trailing: _periodCompactLabel(widget.digest),
      trailingWidget: _ActivityFilterMenu(
        selected: widget.filter,
        items: widget.items,
        onSelected: widget.onFilterChanged,
      ),
      accent: widget.filter.accent,
      child: visibleItems.isEmpty
          ? _QuietState(
              icon: widget.filter.icon,
              text: widget.filter.emptyLabel,
              accent: widget.filter.accent,
            )
          : Column(
              children: [
                for (var index = 0; index < visibleItems.length; index++)
                  _ActivityRow(
                    item: visibleItems[index],
                    isLast: index == visibleItems.length - 1,
                    onTap: () => widget.onTap(visibleItems[index]),
                  ),
                if (remaining > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Semantics(
                      button: true,
                      label: 'Mostrar $nextBatchCount movimientos más. '
                          '${visibleItems.length} de ${filteredItems.length} visibles.',
                      child: TextButton(
                        onPressed: _showMore,
                        style: TextButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                          minimumSize: const Size(0, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Mostrar $nextBatchCount más',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.keyboard_arrow_down, size: 17),
                            const SizedBox(width: 8),
                            Text(
                              '${visibleItems.length} de '
                              '${filteredItems.length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant
                                        .withValues(alpha: 0.72),
                                  ),
                            ),
                          ],
                        ),
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
  });

  final IconData icon;
  final String label;
  final int count;
  final Color accent;
  final VoidCallback onTap;

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
            const SizedBox(width: 3),
            Icon(Icons.chevron_right, size: 18, color: accent),
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

const _briefingMonthShort = <String>[
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sept',
  'oct',
  'nov',
  'dic',
];

const _briefingMonthLong = <String>[
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

const _briefingWeekdayLong = <String>[
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

String _periodPresetLabel(NotificationDigestPeriod period) {
  switch (period) {
    case NotificationDigestPeriod.today:
      return 'Hoy';
    case NotificationDigestPeriod.thisWeek:
      return 'Esta semana';
    case NotificationDigestPeriod.previousWeek:
      return 'Semana anterior';
    case NotificationDigestPeriod.thisMonth:
      return 'Este mes';
    case NotificationDigestPeriod.previousMonth:
      return 'Mes anterior';
    case NotificationDigestPeriod.thisYear:
      return 'Este año';
    case NotificationDigestPeriod.custom:
      return 'Personalizado…';
  }
}

String _periodTriggerLabel(
  NotificationDigestPeriod period,
  DateTimeRange? customDateRange,
) {
  if (period != NotificationDigestPeriod.custom || customDateRange == null) {
    return _periodPresetLabel(period);
  }
  return _periodRangeLabel(
    _dateOnly(customDateRange.start),
    _dateOnly(customDateRange.end),
  );
}

String _periodAccessibleLabel(
  NotificationDigestPeriod period,
  DateTimeRange? customDateRange,
) {
  if (period != NotificationDigestPeriod.custom || customDateRange == null) {
    return _periodPresetLabel(period);
  }
  return _periodRangeLabel(
    _dateOnly(customDateRange.start),
    _dateOnly(customDateRange.end),
    includeYear: true,
  );
}

String _periodHeroTitle(NotificationDigestPeriod period) {
  switch (period) {
    case NotificationDigestPeriod.today:
      return 'Hoy en Viñabike';
    case NotificationDigestPeriod.thisWeek:
      return 'Esta semana en Viñabike';
    case NotificationDigestPeriod.previousWeek:
      return 'La semana anterior';
    case NotificationDigestPeriod.thisMonth:
      return 'Este mes en Viñabike';
    case NotificationDigestPeriod.previousMonth:
      return 'El mes anterior';
    case NotificationDigestPeriod.thisYear:
      return 'Este año en Viñabike';
    case NotificationDigestPeriod.custom:
      return 'Resumen del período';
  }
}

String _filesPeriodTitle(NotificationDigestPeriod period) {
  switch (period) {
    case NotificationDigestPeriod.today:
      return 'Archivos de hoy';
    case NotificationDigestPeriod.thisWeek:
      return 'Archivos de esta semana';
    case NotificationDigestPeriod.previousWeek:
      return 'Archivos de la semana anterior';
    case NotificationDigestPeriod.thisMonth:
      return 'Archivos de este mes';
    case NotificationDigestPeriod.previousMonth:
      return 'Archivos del mes anterior';
    case NotificationDigestPeriod.thisYear:
      return 'Archivos de este año';
    case NotificationDigestPeriod.custom:
      return 'Archivos del período';
  }
}

String _periodCompactLabel(NotificationDigestSnapshot digest) {
  if (digest.period == NotificationDigestPeriod.custom) {
    return _periodRangeLabel(digest.startDate, digest.endDate);
  }
  return _periodPresetLabel(digest.period);
}

String _periodRangeLabel(
  DateTime first,
  DateTime second, {
  bool includeYear = false,
}) {
  final start = _dateOnly(first);
  final end = _dateOnly(second);
  if (start == end) {
    if (!includeYear) {
      return '${start.day} ${_briefingMonthShort[start.month - 1]}';
    }
    return '${_briefingWeekdayLong[start.weekday - 1]}, ${start.day} de '
        '${_briefingMonthLong[start.month - 1]} de ${start.year}';
  }
  if (start.year == end.year && start.month == end.month) {
    return '${start.day}–${end.day} '
        '${_briefingMonthShort[start.month - 1]}'
        '${includeYear ? ' ${start.year}' : ''}';
  }
  if (start.year == end.year) {
    return '${start.day} ${_briefingMonthShort[start.month - 1]}–'
        '${end.day} ${_briefingMonthShort[end.month - 1]}'
        '${includeYear ? ' ${start.year}' : ''}';
  }
  return '${start.day} ${_briefingMonthShort[start.month - 1]} ${start.year}–'
      '${end.day} ${_briefingMonthShort[end.month - 1]} ${end.year}';
}

DateTime _dateOnly(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

bool _sameCalendarDate(DateTime? first, DateTime? second) {
  return first != null &&
      second != null &&
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

List<Map<String, dynamic>> _mergeNotificationRows(
  List<Map<String, dynamic>> historical,
  List<Map<String, dynamic>> live,
) {
  final byId = <String, Map<String, dynamic>>{};
  final anonymous = <Map<String, dynamic>>[];
  for (final row in [...historical, ...live]) {
    final id = row['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      anonymous.add(row);
    } else {
      byId[id] = row;
    }
  }
  final merged = [...byId.values, ...anonymous];
  merged.sort((a, b) {
    final aDate = DateTime.tryParse(a['created_at']?.toString() ?? '');
    final bDate = DateTime.tryParse(b['created_at']?.toString() ?? '');
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  });
  return merged;
}

bool _notificationDateIsInWindow(
  Map<String, dynamic> row,
  NotificationDigestWindow window,
) {
  final createdAt = DateTime.tryParse(row['created_at']?.toString() ?? '');
  return createdAt != null && window.contains(createdAt);
}

class _ActivityPulseBucket {
  const _ActivityPulseBucket(this.label, this.count);

  final String label;
  final int count;
}

List<_ActivityPulseBucket> _activityPulseBuckets(
  NotificationDigestSnapshot digest,
  List<_BriefingActivityItem> items,
) {
  if (digest.period == NotificationDigestPeriod.today) {
    final counts = List<int>.filled(6, 0);
    for (final item in items) {
      final chile = _chileBriefingTime(item.createdAt);
      counts[(chile.hour ~/ 4).clamp(0, 5)]++;
    }
    const labels = ['00', '04', '08', '12', '16', '20'];
    return List.generate(
      counts.length,
      (index) => _ActivityPulseBucket(labels[index], counts[index]),
    );
  }

  final start = digest.startDate;
  final end = digest.endDate;
  final totalDays = end.difference(start).inDays + 1;
  if (digest.period == NotificationDigestPeriod.thisYear || totalDays > 90) {
    final totalMonths =
        ((end.year - start.year) * 12) + end.month - start.month + 1;
    final bucketCount = totalMonths.clamp(1, 12);
    final counts = List<int>.filled(bucketCount, 0);
    for (final item in items) {
      final chile = _chileBriefingTime(item.createdAt);
      final monthOffset =
          ((chile.year - start.year) * 12) + chile.month - start.month;
      if (monthOffset < 0 || monthOffset >= totalMonths) continue;
      final index = (monthOffset * bucketCount ~/ totalMonths).clamp(
        0,
        bucketCount - 1,
      );
      counts[index]++;
    }
    return List.generate(bucketCount, (index) {
      final monthOffset = index * totalMonths ~/ bucketCount;
      final date = DateTime(start.year, start.month + monthOffset);
      return _ActivityPulseBucket(
        _briefingMonthShort[date.month - 1],
        counts[index],
      );
    });
  }

  final bucketCount = totalDays.clamp(1, 7);
  final counts = List<int>.filled(bucketCount, 0);
  for (final item in items) {
    final chile = _chileBriefingTime(item.createdAt);
    final day = DateTime(chile.year, chile.month, chile.day);
    final dayOffset = day.difference(start).inDays;
    if (dayOffset < 0 || dayOffset >= totalDays) continue;
    final index = (dayOffset * bucketCount ~/ totalDays).clamp(
      0,
      bucketCount - 1,
    );
    counts[index]++;
  }
  return List.generate(bucketCount, (index) {
    final dayOffset = index * totalDays ~/ bucketCount;
    final date = start.add(Duration(days: dayOffset));
    final label = totalDays <= 7
        ? _weekdayLabel(date.weekday)
        : '${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}';
    return _ActivityPulseBucket(label, counts[index]);
  });
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

  final requestedRoute = withNotificationOpenRequest(route);
  try {
    context.read<WorkspaceManager>().navigateActiveWorkspaceFromSharedLink(
          requestedRoute,
        );
  } catch (_) {
    context.go(requestedRoute);
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
    case 'expense_recorded':
      return Icons.receipt_long_outlined;
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
    case 'expense_recorded':
      return _BriefingActivityKind.expense;
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
    case 'expense_recorded':
      return _expensesAccent;
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
  final chile = _chileBriefingTime(dateTime);
  final now = tz.TZDateTime.now(_chileBriefingLocation());
  final sameDay = chile.year == now.year &&
      chile.month == now.month &&
      chile.day == now.day;
  if (sameDay) {
    final hour = chile.hour.toString().padLeft(2, '0');
    final minute = chile.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  final day = chile.day.toString().padLeft(2, '0');
  final month = chile.month.toString().padLeft(2, '0');
  return '$day/$month';
}

tz.Location? _briefingChileLocation;

tz.Location _chileBriefingLocation() {
  final existing = _briefingChileLocation;
  if (existing != null) return existing;
  tzdata.initializeTimeZones();
  return _briefingChileLocation = tz.getLocation('America/Santiago');
}

tz.TZDateTime _chileBriefingTime(DateTime value) {
  return tz.TZDateTime.from(value.toUtc(), _chileBriefingLocation());
}

String _chileClockTime(DateTime value) {
  final chile = _chileBriefingTime(value);
  final hour = chile.hour.toString().padLeft(2, '0');
  final minute = chile.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

Duration _attendanceElapsed(DateTime checkIn, DateTime now) {
  final elapsed = now.toUtc().difference(checkIn.toUtc());
  return elapsed.isNegative ? Duration.zero : elapsed;
}

String _attendanceDuration(Duration value) {
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60);
  if (hours == 0) return '$minutes min';
  if (minutes == 0) return '$hours h';
  return '$hours h $minutes min';
}

String _employeeInitials(Employee employee) {
  final parts = [
    employee.firstName.trim(),
    employee.lastName.trim(),
  ].where((part) => part.isNotEmpty).toList(growable: false);
  if (parts.isEmpty) return '—';
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}

String _attendanceDayRoute(DateTime value) {
  final chile = _chileBriefingTime(value);
  final date = '${chile.year.toString().padLeft(4, '0')}-'
      '${chile.month.toString().padLeft(2, '0')}-'
      '${chile.day.toString().padLeft(2, '0')}';
  return Uri(
    path: '/hr/attendances',
    queryParameters: {'view': 'day', 'date': date},
  ).toString();
}

String _attendanceEntryRoute(CurrentAttendanceBriefingEntry entry) {
  final attendance = entry.attendance;
  final base = Uri.parse(_attendanceDayRoute(attendance.checkIn));
  final query = <String, String>{
    ...base.queryParameters,
    'employeeId': attendance.employeeId,
  };
  final attendanceId = attendance.id?.trim();
  if (attendanceId != null && attendanceId.isNotEmpty) {
    query['attendanceId'] = attendanceId;
  }
  return base.replace(queryParameters: query).toString();
}
