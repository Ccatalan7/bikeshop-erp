import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

enum NotificationDigestPeriod {
  today,
  thisWeek,
  previousWeek,
  thisMonth,
  previousMonth,
  thisYear,
  custom,
}

/// Inclusive business-calendar dates and their equivalent half-open UTC range.
///
/// Notification summaries belong to Viñabike's business calendar in
/// `America/Santiago`, regardless of the device's current timezone. The
/// date-only values are inclusive; [startsAt] and [endsAt] are UTC instants
/// suitable for filtering persisted timestamps.
class NotificationDigestWindow {
  const NotificationDigestWindow._({
    required this.startDate,
    required this.endDate,
    required this.startsAt,
    required this.endsAt,
  });

  factory NotificationDigestWindow.resolve({
    required NotificationDigestPeriod period,
    DateTime? now,
    DateTime? customStartDate,
    DateTime? customEndDate,
  }) {
    final referenceNow = (now ?? DateTime.now()).toUtc();
    final today = businessToday(now: referenceNow);
    late DateTime startDate;
    late DateTime endDate;

    switch (period) {
      case NotificationDigestPeriod.today:
        startDate = today;
        endDate = today;
      case NotificationDigestPeriod.thisWeek:
        startDate = _calendarDate(
          today.year,
          today.month,
          today.day - (today.weekday - 1),
        );
        endDate = today;
      case NotificationDigestPeriod.previousWeek:
        final thisWeekStart = _calendarDate(
          today.year,
          today.month,
          today.day - (today.weekday - 1),
        );
        endDate = _calendarDate(
          thisWeekStart.year,
          thisWeekStart.month,
          thisWeekStart.day - 1,
        );
        startDate = _calendarDate(
          endDate.year,
          endDate.month,
          endDate.day - 6,
        );
      case NotificationDigestPeriod.thisMonth:
        startDate = DateTime(today.year, today.month);
        endDate = today;
      case NotificationDigestPeriod.previousMonth:
        endDate = _calendarDate(today.year, today.month, 0);
        startDate = DateTime(endDate.year, endDate.month);
      case NotificationDigestPeriod.thisYear:
        startDate = DateTime(today.year);
        endDate = today;
      case NotificationDigestPeriod.custom:
        if (customStartDate == null || customEndDate == null) {
          throw ArgumentError(
            'customStartDate and customEndDate are required for a custom '
            'notification digest window.',
          );
        }
        final first = _dateOnly(customStartDate);
        final second = _dateOnly(customEndDate);
        if (first.isAfter(second)) {
          startDate = second;
          endDate = first;
        } else {
          startDate = first;
          endDate = second;
        }
    }

    startDate = _dateOnly(startDate);
    endDate = _dateOnly(endDate);
    final location = _santiago;
    final startsAt = tz.TZDateTime(
      location,
      startDate.year,
      startDate.month,
      startDate.day,
    ).toUtc();
    final selectedEndsAt = tz.TZDateTime(
      location,
      endDate.year,
      endDate.month,
      endDate.day + 1,
    ).toUtc();
    final endsAt = switch (period) {
      NotificationDigestPeriod.today ||
      NotificationDigestPeriod.thisWeek ||
      NotificationDigestPeriod.thisMonth ||
      NotificationDigestPeriod.thisYear =>
        referenceNow,
      NotificationDigestPeriod.custom
          when selectedEndsAt.isAfter(referenceNow) =>
        referenceNow,
      _ => selectedEndsAt,
    };

    return NotificationDigestWindow._(
      startDate: startDate,
      endDate: endDate,
      startsAt: startsAt,
      endsAt: endsAt,
    );
  }

  final DateTime startDate;
  final DateTime endDate;
  final DateTime startsAt;
  final DateTime endsAt;

  bool contains(DateTime dateTime) {
    final instant = dateTime.toUtc();
    return !instant.isBefore(startsAt) && instant.isBefore(endsAt);
  }

  static DateTime businessToday({DateTime? now}) {
    final chileNow = tz.TZDateTime.from(
      (now ?? DateTime.now()).toUtc(),
      _santiago,
    );
    return DateTime(chileNow.year, chileNow.month, chileNow.day);
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static DateTime _calendarDate(int year, int month, int day) {
    final normalized = DateTime.utc(year, month, day);
    return DateTime(normalized.year, normalized.month, normalized.day);
  }

  static bool _timeZonesInitialized = false;
  static tz.Location? _businessLocation;

  static tz.Location get _santiago {
    if (!_timeZonesInitialized) {
      tzdata.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    return _businessLocation ??= tz.getLocation('America/Santiago');
  }
}

/// Aggregated operational activity for the notifications briefing.
///
/// The digest uses [NotificationDigestWindow], so every preset follows Chilean
/// business-calendar boundaries instead of the device timezone or rolling
/// durations.
class NotificationDigestSnapshot {
  const NotificationDigestSnapshot({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.startsAt,
    required this.endsAt,
    required this.jobCount,
    required this.paymentCount,
    required this.paymentTotal,
    required this.expenseCount,
    required this.expenseTotal,
    required this.onlineOrderCount,
    required this.catalogApprovalCount,
    required this.fileCount,
    required this.unreadAlertCount,
  });

  factory NotificationDigestSnapshot.fromRows({
    required NotificationDigestPeriod period,
    required List<Map<String, dynamic>> notifications,
    Iterable<DateTime> fileCreatedAt = const <DateTime>[],
    DateTime? now,
    DateTime? customStartDate,
    DateTime? customEndDate,
  }) {
    final window = NotificationDigestWindow.resolve(
      period: period,
      now: now,
      customStartDate: customStartDate,
      customEndDate: customEndDate,
    );

    var jobCount = 0;
    var paymentCount = 0;
    var paymentTotal = 0.0;
    var expenseCount = 0;
    var expenseTotal = 0.0;
    var onlineOrderCount = 0;
    var catalogApprovalCount = 0;
    var unreadAlertCount = 0;

    // Every ribbon metric is a projection of unique, currently active source
    // entities. Lifecycle rows remain in the activity timeline, but an
    // archived/voided/deleted/cancelled identity must suppress any stale
    // active-shaped row observed during a mixed-version realtime refresh.
    final inactiveEntityKeys = <String>{};
    for (final row in notifications) {
      final type = row['type']?.toString() ?? '';
      final data = _notificationPayload(row);
      if (!_isInactiveNotification(type, data)) continue;
      final key = _notificationEntityKey(row, type, data);
      if (key != null) inactiveEntityKeys.add(key);
    }

    final seenJobKeys = <String>{};
    final seenPaymentKeys = <String>{};
    final seenExpenseKeys = <String>{};
    final seenOrderKeys = <String>{};
    final seenCatalogKeys = <String>{};
    final seenUnreadIds = <String>{};

    for (final row in notifications) {
      final type = row['type']?.toString() ?? '';
      final data = _notificationPayload(row);
      final entityKey = _notificationEntityKey(row, type, data);
      final isInactive = _isInactiveNotification(type, data) ||
          (entityKey != null && inactiveEntityKeys.contains(entityKey));
      final createdAt = DateTime.tryParse(
        row['created_at']?.toString() ?? '',
      );
      final occurredAt = DateTime.tryParse(
            row['occurred_at']?.toString() ?? '',
          ) ??
          createdAt;
      final wasRecordedInWindow =
          createdAt != null && window.contains(createdAt);
      final occurredInWindow =
          occurredAt != null && window.contains(occurredAt);

      // Attention belongs to when the durable alert reached the operator.
      // Financial metrics belong to the date of the underlying transaction.
      if (wasRecordedInWindow && row['read_at'] == null) {
        final notificationId = row['id']?.toString().trim() ?? '';
        if (notificationId.isEmpty || seenUnreadIds.add(notificationId)) {
          unreadAlertCount++;
        }
      }

      switch (type) {
        case 'mechanic_job_created':
          if (!isInactive &&
              wasRecordedInWindow &&
              _acceptMetricEntity(seenJobKeys, entityKey)) {
            jobCount++;
          }
          break;
        case 'sales_payment_received':
          if (isInactive ||
              !occurredInWindow ||
              !_acceptMetricEntity(seenPaymentKeys, entityKey)) {
            break;
          }
          paymentCount++;
          if (data['amount'] is num) {
            paymentTotal += (data['amount'] as num).toDouble();
          }
          break;
        case 'expense_recorded':
          if (isInactive ||
              !occurredInWindow ||
              !_acceptMetricEntity(seenExpenseKeys, entityKey)) {
            break;
          }
          expenseCount++;
          if (data['total_amount'] is num) {
            expenseTotal += (data['total_amount'] as num).toDouble();
          }
          break;
        case 'online_order_created':
          if (!isInactive &&
              wasRecordedInWindow &&
              _acceptMetricEntity(seenOrderKeys, entityKey)) {
            onlineOrderCount++;
          }
          break;
        case 'whatsapp_catalog_approved':
          if (!isInactive &&
              wasRecordedInWindow &&
              _acceptMetricEntity(seenCatalogKeys, entityKey)) {
            catalogApprovalCount++;
          }
          break;
      }
    }

    final fileCount = fileCreatedAt.where(window.contains).length;

    return NotificationDigestSnapshot(
      period: period,
      startDate: window.startDate,
      endDate: window.endDate,
      startsAt: window.startsAt,
      endsAt: window.endsAt,
      jobCount: jobCount,
      paymentCount: paymentCount,
      paymentTotal: paymentTotal,
      expenseCount: expenseCount,
      expenseTotal: expenseTotal,
      onlineOrderCount: onlineOrderCount,
      catalogApprovalCount: catalogApprovalCount,
      fileCount: fileCount,
      unreadAlertCount: unreadAlertCount,
    );
  }

  final NotificationDigestPeriod period;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime startsAt;
  final DateTime endsAt;
  final int jobCount;
  final int paymentCount;
  final double paymentTotal;
  final int expenseCount;
  final double expenseTotal;
  final int onlineOrderCount;
  final int catalogApprovalCount;
  final int fileCount;
  final int unreadAlertCount;

  bool contains(DateTime dateTime) {
    final instant = dateTime.toUtc();
    return !instant.isBefore(startsAt) && instant.isBefore(endsAt);
  }
}

Map<String, dynamic> _notificationPayload(Map<String, dynamic> row) {
  final data = row['data'];
  return data is Map
      ? Map<String, dynamic>.from(data)
      : const <String, dynamic>{};
}

bool _isInactiveNotification(
  String type,
  Map<String, dynamic> data,
) {
  const inactiveTypes = <String>{
    'mechanic_job_archived',
    'sales_payment_voided',
    'expense_voided',
    'expense_deleted',
    'online_order_cancelled',
  };
  return inactiveTypes.contains(type) ||
      _payloadBool(data['is_inactive']) ||
      _payloadBool(data['is_voided']);
}

bool _payloadBool(dynamic value) =>
    value == true || value?.toString().trim().toLowerCase() == 'true';

String? _notificationEntityKey(
  Map<String, dynamic> row,
  String type,
  Map<String, dynamic> data,
) {
  final entityType = row['entity_type']?.toString().trim() ?? '';
  final rowEntityId = row['entity_id']?.toString().trim() ?? '';
  if (entityType.isNotEmpty && rowEntityId.isNotEmpty) {
    return '$entityType:$rowEntityId';
  }

  final fallback = switch (type) {
    'mechanic_job_created' || 'mechanic_job_archived' => data['job_id'],
    'sales_payment_received' || 'sales_payment_voided' => data['payment_id'],
    'expense_recorded' ||
    'expense_voided' ||
    'expense_deleted' =>
      data['expense_id'],
    'online_order_created' || 'online_order_cancelled' => data['order_id'],
    'whatsapp_catalog_approved' => data['product_id'],
    _ => null,
  };
  final fallbackId = fallback?.toString().trim() ?? '';
  if (fallbackId.isEmpty) return null;

  final fallbackType = switch (type) {
    'mechanic_job_created' || 'mechanic_job_archived' => 'mechanic_job',
    'sales_payment_received' || 'sales_payment_voided' => 'sales_payment',
    'expense_recorded' || 'expense_voided' || 'expense_deleted' => 'expense',
    'online_order_created' || 'online_order_cancelled' => 'online_order',
    'whatsapp_catalog_approved' => 'product',
    _ => type,
  };
  return '$fallbackType:$fallbackId';
}

bool _acceptMetricEntity(Set<String> seen, String? entityKey) =>
    entityKey == null || seen.add(entityKey);
