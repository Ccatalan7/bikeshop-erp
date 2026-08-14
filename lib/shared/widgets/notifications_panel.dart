import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../modules/website/models/website_models.dart';
import '../models/notification_digest.dart';
import '../services/notification_service.dart';
import '../services/right_toolbar_service.dart';
import '../services/workspace_manager.dart';
import '../utils/chilean_utils.dart';
import '../utils/notification_deep_link.dart';
import '../utils/responsive_viewport.dart';
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
  List<DailyAttendanceBriefingEntry> _dailyAttendances = const [];
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
        unawaited(
          _loadAttendances(silent: previousDay == nextDay),
        );
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
      final referenceNow = DateTime.now();
      final todayWindow = NotificationDigestWindow.resolve(
        period: NotificationDigestPeriod.today,
        now: referenceNow,
      );
      final entries =
          await context.read<HRService>().getDailyAttendanceBriefing(
                startsAt: todayWindow.startsAt,
                endsAt: todayWindow.endsAt,
              );
      if (!mounted || loadEpoch != _attendanceLoadEpoch) return;
      setState(() {
        _dailyAttendances = entries;
        _briefingNow = referenceNow;
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
                              entries: _dailyAttendances,
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
                                _markActivityRead(item);
                                widget.onNavigate(item.route);
                              },
                              onExpand: _markActivityRead,
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

  /// Opening the record and opening its disclosure are both acts of reading, so
  /// they settle unread state through the same idempotent writer.
  ///
  /// The historical projection is reconciled first. `NotificationService` only
  /// owns the latest realtime feed, and `_mergeNotificationRows` lets that feed
  /// win per id — so a row that exists only in the selected period would keep
  /// its unread dot and stay inside `n nuevas` until the next reload.
  void _markActivityRead(_BriefingActivityItem item) {
    final notificationId = item.notificationId;
    if (notificationId == null || !item.unread) return;
    _reconcilePeriodRowRead(notificationId);
    unawaited(_notifications.markNotificationRead(notificationId));
  }

  /// Idempotent: a row that is already read produces no new list and no
  /// rebuild, so reopening a disclosure cannot rewrite its `read_at`.
  void _reconcilePeriodRowRead(String notificationId) {
    final readAt = DateTime.now().toUtc().toIso8601String();
    var changed = false;
    final reconciled = _periodNotifications.map((row) {
      if (row['id']?.toString() != notificationId || row['read_at'] != null) {
        return row;
      }
      changed = true;
      return {...row, 'read_at': readAt};
    }).toList(growable: false);
    if (!changed || !mounted) return;
    setState(() => _periodNotifications = reconciled);
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
      final occurredAt = DateTime.tryParse(
        row['occurred_at']?.toString() ?? '',
      )?.toLocal();
      if (createdAt == null ||
          (!digest.contains(createdAt) &&
              (occurredAt == null || !digest.contains(occurredAt)))) {
        continue;
      }
      final type = row['type']?.toString() ?? '';
      final platformKey = _platformKeyForNotificationType(type);
      final route = resolveErpNotificationRoute(row);
      final body = row['body']?.toString() ?? '';
      // The payload already travelled with the row (`data` is part of both the
      // period read and the realtime projection), so enrichment costs no query.
      final data = _notificationPayload(row);
      final economicDateContext = _economicDateContext(
        createdAt: createdAt,
        occurredAt: occurredAt,
        type: type,
      );
      items.add(
        _BriefingActivityItem(
          title: row['title']?.toString() ?? 'Actividad',
          subtitle: _erpActivitySubtitle(type, body, data),
          createdAt: createdAt,
          occurredAt: occurredAt,
          economicDateContext: economicDateContext,
          route: route,
          icon: _iconForNotificationType(type),
          accent: _accentForNotificationType(type),
          kind: _kindForNotificationType(type),
          unread: row['read_at'] == null,
          notificationId: row['id']?.toString(),
          platformKey: platformKey,
          detail: _erpActivityDetail(type, data, createdAt),
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
      items.add(
        _BriefingActivityItem(
          title: name,
          subtitle: _conversationSubtitle(conversation),
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

/// Reads the durable JSON payload the notification row already carries.
///
/// `data` is selected by both `loadNotifications` and
/// `loadNotificationsForRange`, and realtime inserts publish the whole row, so
/// no consumer of this helper performs an additional read.
Map<String, dynamic> _notificationPayload(Map<String, dynamic> row) {
  final data = row['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  return const <String, dynamic>{};
}

String _payloadText(Map<String, dynamic> data, String key) =>
    data[key]?.toString().trim() ?? '';

/// Joins the segments that actually resolved, so a missing payload field
/// disappears instead of leaving a dangling separator or a false placeholder.
String _joinActivitySegments(Iterable<String> segments) => segments
    .map((segment) => segment.trim())
    .where((segment) => segment.isNotEmpty)
    .join(' · ');

/// Second line of a collapsed ERP activity row.
///
/// The server-composed `body` already carries the identity and the money for
/// every type it applies to, so enrichment appends the operational fact the
/// owner decides with (`método`, `bicicleta`, `entrega`) instead of
/// re-formatting an amount in the widget layer.
String _erpActivitySubtitle(
  String type,
  String body,
  Map<String, dynamic> data,
) {
  switch (type) {
    case 'mechanic_job_created':
      return _joinActivitySegments([body, _payloadText(data, 'bike_label')]);
    case 'sales_payment_received':
    case 'expense_recorded':
      return _joinActivitySegments(
        [body, _payloadText(data, 'payment_method')],
      );
    case 'online_order_created':
      final deliveryType = _payloadText(data, 'delivery_type');
      return _joinActivitySegments([
        body,
        deliveryType.isEmpty
            ? ''
            : onlineOrderDeliveryDisplayName(deliveryType),
      ]);
    case 'whatsapp_catalog_approved':
      final product = _payloadText(data, 'product_name');
      if (product.isEmpty) return body;
      final sku = _payloadText(data, 'sku');
      return _joinActivitySegments([product, sku.isEmpty ? '' : 'SKU $sku']);
    default:
      return body;
  }
}

String _economicDateContext({
  required DateTime createdAt,
  required String type,
  DateTime? occurredAt,
}) {
  if (occurredAt == null) return '';
  final recorded = _chileBriefingTime(createdAt);
  final occurred = _chileBriefingTime(occurredAt);
  if (recorded.year == occurred.year &&
      recorded.month == occurred.month &&
      recorded.day == occurred.day) {
    return '';
  }
  final today = tz.TZDateTime.now(_chileBriefingLocation());
  final recordedLabel = recorded.year == today.year &&
          recorded.month == today.month &&
          recorded.day == today.day
      ? 'Registrado hoy'
      : 'Registrado el ${recorded.day} '
          '${_briefingMonthShort[recorded.month - 1]}';
  final economicNoun = switch (type) {
    'sales_payment_received' => 'pago',
    'expense_recorded' => 'gasto',
    _ => 'corresponde',
  };
  final occurrenceLabel =
      economicNoun == 'corresponde' ? 'corresponde al' : '$economicNoun del';
  final includeYear = recorded.year != occurred.year;
  return '$recordedLabel · $occurrenceLabel ${occurred.day} '
      '${_briefingMonthShort[occurred.month - 1]}'
      '${includeYear ? ' ${occurred.year}' : ''}';
}

/// Second line of a conversation row.
///
/// The channel used to live only in the row glyph and its accent colour, which
/// made it a colour-only signal. It is named in words here, and the preview
/// never claims an unread incoming message when the shop itself sent last.
String _conversationSubtitle(Conversation conversation) {
  final message = conversation.lastMessageContent?.trim() ?? '';
  final isOutgoing = conversation.lastMessageIsMine ||
      conversation.lastMessageDirection?.trim().toLowerCase() == 'outbound';
  final unread = conversation.unreadCount;
  return _joinActivitySegments([
    conversation.shortChannelLabel,
    if (!isOutgoing && unread > 1) '$unread nuevos',
    if (message.isNotEmpty) isOutgoing ? 'Tú: $message' : message,
  ]);
}

/// Builds the in-place disclosure for the ERP types that have something real to
/// read. Returns `null` when the payload resolves nothing, which is what keeps
/// the affordance itself meaningful: no chevron means no hidden content.
_ActivityDetail? _erpActivityDetail(
  String type,
  Map<String, dynamic> data,
  DateTime createdAt,
) {
  switch (type) {
    case 'mechanic_job_created':
      final fields = <_ActivityDetailField>[
        ..._optionalField(
          'SOLICITUD DEL CLIENTE',
          _payloadText(data, 'client_request'),
          maxLines: 4,
        ),
        ..._optionalField(
          'REGISTRÓ',
          _payloadText(data, 'recorded_by_name'),
        ),
      ];
      if (fields.isEmpty) return null;
      return _ActivityDetail(
        noun: 'el detalle del trabajo',
        actionLabel: 'Abrir trabajo',
        fields: fields,
      );
    case 'sales_payment_received':
      final fields = <_ActivityDetailField>[
        ..._optionalField('CLIENTE', _payloadText(data, 'customer_name')),
        ..._optionalField('REGISTRÓ', _payloadText(data, 'recorded_by_name')),
        ..._optionalField(
          'REFERENCIA',
          _payloadText(data, 'reference'),
        ),
        ..._divergentDateField(
          'FECHA DEL PAGO',
          _payloadText(data, 'payment_date'),
          createdAt,
        ),
      ];
      if (fields.isEmpty) return null;
      return _ActivityDetail(
        noun: 'el detalle del pago',
        actionLabel: 'Abrir pago',
        fields: fields,
      );
    case 'expense_recorded':
      final fields = <_ActivityDetailField>[
        ..._optionalField('CATEGORÍA', _payloadText(data, 'category_name')),
        // `document_type` is deliberately absent: its operator-facing label is
        // owned three times over inside `lib/modules/accounting/pages/`, all
        // private, and this surface must not become a fourth copy.
        ..._optionalField(
          'N° DE DOCUMENTO',
          _payloadText(data, 'document_number'),
        ),
        ..._optionalField('REGISTRÓ', _payloadText(data, 'recorded_by_name')),
        ..._divergentDateField(
          'FECHA DEL DOCUMENTO',
          _payloadText(data, 'issue_date'),
          createdAt,
        ),
      ];
      if (fields.isEmpty) return null;
      return _ActivityDetail(
        noun: 'el detalle del gasto',
        actionLabel: 'Abrir gasto',
        fields: fields,
      );
    default:
      return null;
  }
}

List<_ActivityDetailField> _optionalField(
  String label,
  String value, {
  int maxLines = 2,
}) {
  if (value.isEmpty) return const [];
  return [
    _ActivityDetailField(
      label: label,
      value: value,
      maxLines: maxLines,
    ),
  ];
}

/// A payload date earns a line only when it disagrees with the day the row was
/// registered. When both fall on the same Chilean civil day the row timestamp
/// already says it, and repeating it would be noise.
///
/// `payment_date` and `issue_date` are calendar dates, not instants: the
/// pipeline serialises them as `YYYY-MM-DD` or as midnight UTC. Reading the
/// leading date parts textually keeps `2026-07-31T00:00:00+00:00` on the 31st
/// instead of letting a timezone conversion move it to the 30th.
List<_ActivityDetailField> _divergentDateField(
  String label,
  String rawDate,
  DateTime createdAt,
) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(rawDate);
  if (match == null) return const [];
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final reference = _chileBriefingTime(createdAt);
  if (year == reference.year &&
      month == reference.month &&
      day == reference.day) {
    return const [];
  }
  return [
    _ActivityDetailField(
      label: label,
      value: '${match.group(3)}/${match.group(2)}/$year',
    ),
  ];
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
          // The threshold decides whether the long `n nuevas` label fits, so it
          // has to move with the text, not stay a fixed pixel count. At a 384
          // panel this row lands on exactly 360.0: at scale 1.0 the long label
          // fits (unchanged behaviour), at 1.3 it overflowed the flex by 33 px.
          final labelFontSize = theme.textTheme.labelLarge?.fontSize ?? 14;
          final scaledLabelFontSize =
              MediaQuery.textScalerOf(context).scale(labelFontSize);
          final labelScale = scaledLabelFontSize / labelFontSize;
          final compact = constraints.maxWidth < 360 * labelScale;
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
                '${items.where((item) => digest.contains(item.metricAt)).length}',
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

  final List<DailyAttendanceBriefingEntry> entries;
  final DateTime now;
  final bool loading;
  final bool hasError;
  final Future<void> Function() onRetry;
  final VoidCallback onOpenAll;
  final ValueChanged<DailyAttendanceBriefingEntry> onOpenEntry;

  @override
  Widget build(BuildContext context) {
    final currentEntries = entries
        .where((entry) => entry.attendance.isOngoing)
        .toList(growable: false)
      ..sort(
        (first, second) {
          final byCheckIn =
              first.attendance.checkIn.compareTo(second.attendance.checkIn);
          if (byCheckIn != 0) return byCheckIn;
          return (first.attendance.id ?? '')
              .compareTo(second.attendance.id ?? '');
        },
      );
    final completedEntries = entries.where((entry) {
      final attendance = entry.attendance;
      return attendance.checkOut != null &&
          (attendance.status == AttendanceStatus.completed ||
              attendance.status == AttendanceStatus.approved);
    }).toList(growable: false)
      ..sort((first, second) {
        final byCheckOut =
            second.attendance.checkOut!.compareTo(first.attendance.checkOut!);
        if (byCheckOut != 0) return byCheckOut;
        final byCheckIn =
            first.attendance.checkIn.compareTo(second.attendance.checkIn);
        if (byCheckIn != 0) return byCheckIn;
        return (first.attendance.id ?? '')
            .compareTo(second.attendance.id ?? '');
      });
    final visibleCurrentEntries =
        currentEntries.take(4).toList(growable: false);
    final visibleCompletedEntries =
        completedEntries.take(4).toList(growable: false);
    final hiddenCount = currentEntries.length +
        completedEntries.length -
        visibleCurrentEntries.length -
        visibleCompletedEntries.length;
    final peopleLabel = currentEntries.length == 1
        ? '1 persona'
        : '${currentEntries.length} personas';

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
              : Column(
                  children: [
                    if (visibleCurrentEntries.isEmpty)
                      _QuietState(
                        icon: Icons.person_off_outlined,
                        text: completedEntries.isEmpty
                            ? 'Nadie ha marcado entrada hoy.'
                            : 'Nadie está en el local ahora.',
                        accent: _attendanceAccent,
                      )
                    else
                      for (var index = 0;
                          index < visibleCurrentEntries.length;
                          index++) ...[
                        _AttendanceNowRow(
                          entry: visibleCurrentEntries[index],
                          now: now,
                          onTap: () =>
                              onOpenEntry(visibleCurrentEntries[index]),
                        ),
                        if (index < visibleCurrentEntries.length - 1)
                          Divider(
                            height: 1,
                            indent: 40,
                            color: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.45),
                          ),
                      ],
                    if (visibleCompletedEntries.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Divider(
                        height: 1,
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.45),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 9, bottom: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Turnos finalizados hoy',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            Text(
                              '${completedEntries.length}',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      for (var index = 0;
                          index < visibleCompletedEntries.length;
                          index++) ...[
                        _AttendanceNowRow(
                          entry: visibleCompletedEntries[index],
                          now: now,
                          onTap: () =>
                              onOpenEntry(visibleCompletedEntries[index]),
                        ),
                        if (index < visibleCompletedEntries.length - 1)
                          Divider(
                            height: 1,
                            indent: 40,
                            color: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.45),
                          ),
                      ],
                    ],
                    if (hiddenCount > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: onOpenAll,
                          child: Text('Ver $hiddenCount más en Asistencias'),
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

  final DailyAttendanceBriefingEntry entry;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final attendance = entry.attendance;
    final checkOut = attendance.checkOut;
    final isCurrent = attendance.isOngoing;
    final elapsed = _attendanceElapsed(attendance.checkIn, checkOut ?? now);
    final needsReview = isCurrent && elapsed >= const Duration(hours: 18);
    final accent = needsReview ? _warningAccent : _attendanceAccent;
    final title = entry.employee.fullName.trim();
    final jobTitle = entry.employee.jobTitle.trim();
    final statusLabel = isCurrent
        ? (needsReview ? 'Revisar marcación' : 'Jornada en curso')
        : 'Turno finalizado';
    final timeLabel = isCurrent
        ? 'Entrada ${_chileClockTime(attendance.checkIn)}'
            ' · ${_attendanceDuration(elapsed)}'
        : '${_chileClockTime(attendance.checkIn)}–'
            '${_chileClockTime(checkOut!)} · ${_attendanceDuration(elapsed)}';
    final semanticsTiming = isCurrent
        ? 'entrada ${_chileClockTime(attendance.checkIn)}'
        : 'entrada ${_chileClockTime(attendance.checkIn)}, salida '
            '${_chileClockTime(checkOut!)}';

    return Semantics(
      button: true,
      label: '${title.isEmpty ? 'Trabajador' : title}, $semanticsTiming, '
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
                          color: isCurrent
                              ? accent
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (isCurrent)
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
                      jobTitle.isEmpty
                          ? (isCurrent
                              ? 'Jornada en curso'
                              : 'Asistencia del día')
                          : jobTitle,
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
                            statusLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isCurrent
                                  ? accent
                                  : theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      timeLabel,
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
    required this.onExpand,
  });

  final List<_BriefingActivityItem> items;
  final NotificationDigestSnapshot digest;
  final _ActivityFilter filter;
  final ValueChanged<_ActivityFilter> onFilterChanged;

  /// Opens the record. Rows without a disclosure invoke it directly; rows with
  /// one invoke it from the explicit action inside the open disclosure.
  final ValueChanged<_BriefingActivityItem> onTap;

  /// Reading a disclosure is reading the notification, so opening one settles
  /// the same unread state a click used to. Collapsing writes nothing.
  final ValueChanged<_BriefingActivityItem> onExpand;

  @override
  State<_ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends State<_ActivitySection> {
  static const int _activityBatchSize = 12;

  int _visibleLimit = _activityBatchSize;

  /// Exactly one open row, owned by the list rather than by the row, per
  /// Design `T-03 VbRowDisclosure`: "Una fila abierta a la vez; abrir otra
  /// cierra la anterior."
  String? _expandedNotificationId;

  @override
  void didUpdateWidget(covariant _ActivitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final periodChanged = oldWidget.digest.period != widget.digest.period ||
        oldWidget.digest.startDate != widget.digest.startDate ||
        oldWidget.digest.endDate != widget.digest.endDate;
    if (oldWidget.filter != widget.filter || periodChanged) {
      _visibleLimit = _activityBatchSize;
      _expandedNotificationId = null;
    }
  }

  void _showMore() {
    setState(() => _visibleLimit += _activityBatchSize);
  }

  void _toggleDetail(_BriefingActivityItem item) {
    final notificationId = item.notificationId;
    if (notificationId == null) return;
    final opening = _expandedNotificationId != notificationId;
    setState(() => _expandedNotificationId = opening ? notificationId : null);
    if (opening) widget.onExpand(item);
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
                    expanded: visibleItems[index].isExpandable &&
                        visibleItems[index].notificationId ==
                            _expandedNotificationId,
                    onOpen: () => widget.onTap(visibleItems[index]),
                    onToggle: () => _toggleDetail(visibleItems[index]),
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
    required this.expanded,
    required this.onOpen,
    required this.onToggle,
  });

  /// `F-06 VbDensity` publishes 48 for a comfortable table row, and the same
  /// 48 is the forced touch target below 900 logical px. The row is the single
  /// target either way, so one minimum serves both.
  static const double minRowHeight = 48;

  final _BriefingActivityItem item;
  final bool isLast;
  final bool expanded;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = item.detail;
    final expandable = item.isExpandable;
    final isOpen = expandable && expanded;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // A row with hidden content toggles it; a row without one keeps navigating
    // exactly as it did before. The visible control is what tells them apart.
    final primaryAction = expandable ? onToggle : onOpen;

    final header = Semantics(
      button: true,
      expanded: expandable ? isOpen : null,
      child: InkWell(
        onTap: primaryAction,
        borderRadius: BorderRadius.circular(7),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minRowHeight),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
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
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 7, bottom: 10),
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
                      if (item.subtitle.trim().isNotEmpty ||
                          detail != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: item.subtitle.trim().isEmpty
                                  ? const SizedBox.shrink()
                                  : Text(
                                      item.subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                            ),
                            if (detail != null) ...[
                              const SizedBox(width: 8),
                              _ActivityDisclosureIndicator(
                                detail: detail,
                                expanded: isOpen,
                                reduceMotion: reduceMotion,
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (item.economicDateContext.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.economicDateContext,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: item.accent,
                            fontWeight: FontWeight.w600,
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
      ),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (detail != null)
          AnimatedSize(
            duration: reduceMotion
                ? Duration.zero
                // `T-03` publishes no duration of its own; `F-05` publishes
                // exactly three (fast 120 / base 200 / pane 380) and `base` is
                // the in-place one. Replace this if Design publishes a row
                // disclosure duration.
                : const Duration(milliseconds: 200),
            curve: _briefingDisclosureCurve,
            alignment: Alignment.topCenter,
            child: isOpen
                ? _ActivityDetailBody(detail: detail, onOpen: onOpen)
                : const SizedBox(width: double.infinity),
          ),
      ],
    );

    // The timeline connector spans the whole row, so an open disclosure does
    // not break the chain the collapsed list draws.
    final body = isLast
        ? content
        : Stack(
            children: [
              Positioned(
                top: 28,
                bottom: 0,
                left: 0,
                width: 32,
                child: Center(
                  child: Container(
                    width: 1,
                    color: item.accent.withValues(alpha: 0.25),
                  ),
                ),
              ),
              content,
            ],
          );

    if (!expandable) return body;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          if (!isOpen) onToggle();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (isOpen) onToggle();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: body,
    );
  }
}

/// Design `F-05`: `cubic-bezier(.22,1,.36,1)`, the single ERP motion curve.
const Curve _briefingDisclosureCurve = Cubic(0.22, 1, 0.36, 1);

/// The visible, labelled disclosure affordance.
///
/// It is deliberately not a second tap target: the whole row owns the gesture.
/// `GUI_MOBILE_DESIGN_PRINCIPLES.md` requires that the label describe what
/// opens, because "an unlabelled chevron is not enough".
///
/// No `Tooltip` here, and that is a measured exception rather than an
/// oversight: `Tooltip` mounts an `OverlayPortal`, this file already composes
/// inside `LayoutBuilder`, and a visible tooltip during a width change mutates
/// one `_RenderLayoutBuilder` from inside another's `performLayout`. The word
/// is rendered instead, so nothing is left to a hover-only channel.
class _ActivityDisclosureIndicator extends StatelessWidget {
  const _ActivityDisclosureIndicator({
    required this.detail,
    required this.expanded,
    required this.reduceMotion,
  });

  /// `A-02 VbIconButton`: "el glifo no crece; crece el hit target".
  static const double glyphSize = 16;

  final _ActivityDetail detail;
  final bool expanded;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = expanded ? 'Ocultar' : 'Detalles';
    return Semantics(
      label: expanded ? 'Ocultar ${detail.noun}' : 'Ver ${detail.noun}',
      child: ExcludeSemantics(
        child: SizedBox(
          // `A-02` control box on surface; the row supplies the touch target.
          height: 28,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 2),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                curve: _briefingDisclosureCurve,
                child: Icon(
                  Icons.expand_more,
                  size: glyphSize,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// In-place disclosure body.
///
/// Design `T-03 VbRowDisclosure`: opens in place, indented to the content,
/// no shadow. It carries the sunken surface layer rather than the guide's
/// `surfaceSelected`, because `appearance-palette-contract.md` keeps selected,
/// expanded and applied as separate meanings and this list has no selection —
/// which is also why there is no selected-row bar.
class _ActivityDetailBody extends StatelessWidget {
  const _ActivityDetailBody({required this.detail, required this.onOpen});

  final _ActivityDetail detail;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Aligned after the existing 32 px gutter and its 10 px gap.
      padding: const EdgeInsets.only(left: 42, bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          // `F-04`: radius ctrl 6.
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final field in detail.fields) ...[
              Text(
                field.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  // `F-02` overline: +0.8 tracking.
                  letterSpacing: 0.8,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                field.value,
                maxLines: field.maxLines,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  // This is an independent target, not part of the row, so it
                  // carries its own height. `F-06`: compact 32, and the forced
                  // 48 touch minimum below 900 logical px — measured on the
                  // unzoomed viewport owner, never on a local breakpoint.
                  minimumSize: Size(
                    0,
                    ResponsiveViewport.usesCompactShell(context)
                        ? _ActivityRow.minRowHeight
                        : 32,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(detail.actionLabel),
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
      if (!digest.contains(item.metricAt)) continue;
      final chile = _chileBriefingTime(item.metricAt);
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
      if (!digest.contains(item.metricAt)) continue;
      final chile = _chileBriefingTime(item.metricAt);
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
    if (!digest.contains(item.metricAt)) continue;
    final chile = _chileBriefingTime(item.metricAt);
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
    this.occurredAt,
    this.economicDateContext = '',
    this.platformKey,
    this.detail,
  });

  final String title;
  final String subtitle;
  final DateTime createdAt;
  final DateTime? occurredAt;
  final String economicDateContext;
  final String route;
  final IconData icon;
  final Color accent;
  final _BriefingActivityKind kind;
  final bool unread;
  final String? notificationId;
  final String? platformKey;

  /// In-place disclosure content, or `null` when the payload resolved nothing
  /// worth hiding. Only rows carrying a notification id can expand, because the
  /// list owner tracks the open row by that id.
  final _ActivityDetail? detail;

  DateTime get metricAt => switch (kind) {
        _BriefingActivityKind.payment ||
        _BriefingActivityKind.expense =>
          occurredAt ?? createdAt,
        _ => createdAt,
      };

  bool get isExpandable => detail != null && notificationId != null;
}

/// One labelled fact inside an activity disclosure.
class _ActivityDetailField {
  const _ActivityDetailField({
    required this.label,
    required this.value,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final int maxLines;
}

/// Contents of an activity row disclosure: context plus one explicit action.
///
/// Design `GUÍA GENERAL Viñabike - Componentes` · `T-03 VbRowDisclosure`:
/// "Contiene contexto y enlaces, no un formulario". Anything that needs fields
/// belongs in a side sheet, not here.
class _ActivityDetail {
  const _ActivityDetail({
    required this.noun,
    required this.actionLabel,
    required this.fields,
  });

  /// Names what opens, for the accessible label of the disclosure control.
  final String noun;

  /// Verb + object, per `A-01 VbButton` (`text` variant) content rule.
  final String actionLabel;

  final List<_ActivityDetailField> fields;
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

String _attendanceEntryRoute(DailyAttendanceBriefingEntry entry) {
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
