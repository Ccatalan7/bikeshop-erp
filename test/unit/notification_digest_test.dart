import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/notification_digest.dart';

void main() {
  group('NotificationDigestWindow', () {
    test('businessToday follows Chile across the UTC date boundary', () {
      expect(
        NotificationDigestWindow.businessToday(
          now: DateTime.utc(2026, 7, 25, 3, 59),
        ),
        DateTime(2026, 7, 24),
      );
      expect(
        NotificationDigestWindow.businessToday(
          now: DateTime.utc(2026, 7, 25, 4),
        ),
        DateTime(2026, 7, 25),
      );
    });

    test('today resolves Chile start and ends at the current instant', () {
      final winter = NotificationDigestWindow.resolve(
        period: NotificationDigestPeriod.today,
        now: DateTime.utc(2026, 7, 25, 16),
      );
      final summer = NotificationDigestWindow.resolve(
        period: NotificationDigestPeriod.today,
        now: DateTime.utc(2026, 1, 15, 16),
      );

      expect(winter.startDate, DateTime(2026, 7, 25));
      expect(winter.endDate, DateTime(2026, 7, 25));
      expect(winter.startsAt, DateTime.utc(2026, 7, 25, 4));
      expect(winter.endsAt, DateTime.utc(2026, 7, 25, 16));
      expect(summer.startsAt, DateTime.utc(2026, 1, 15, 3));
      expect(summer.endsAt, DateTime.utc(2026, 1, 15, 16));
    });

    test('current presets begin at calendar boundaries and end today', () {
      final now = DateTime.utc(2026, 7, 25, 16);

      final windows = [
        NotificationDigestWindow.resolve(
          period: NotificationDigestPeriod.thisWeek,
          now: now,
        ),
        NotificationDigestWindow.resolve(
          period: NotificationDigestPeriod.thisMonth,
          now: now,
        ),
        NotificationDigestWindow.resolve(
          period: NotificationDigestPeriod.thisYear,
          now: now,
        ),
      ];

      _expectDates(
        windows[0],
        DateTime(2026, 7, 20),
        DateTime(2026, 7, 25),
      );
      _expectDates(
        windows[1],
        DateTime(2026, 7),
        DateTime(2026, 7, 25),
      );
      _expectDates(
        windows[2],
        DateTime(2026),
        DateTime(2026, 7, 25),
      );
      for (final window in windows) {
        expect(window.endsAt, now);
      }
    });

    test('yesterday is the complete prior business day in Chile', () {
      // 16:00 UTC on 25 July is 12:00 in Santiago; yesterday is the 24th,
      // from Chile midnight to Chile midnight (UTC-4 in July).
      final window = NotificationDigestWindow.resolve(
        period: NotificationDigestPeriod.yesterday,
        now: DateTime.utc(2026, 7, 25, 16),
      );

      _expectDates(window, DateTime(2026, 7, 24), DateTime(2026, 7, 24));
      expect(window.startsAt, DateTime.utc(2026, 7, 24, 4));
      expect(window.endsAt, DateTime.utc(2026, 7, 25, 4));
    });

    test('yesterday crosses the month boundary', () {
      final window = NotificationDigestWindow.resolve(
        period: NotificationDigestPeriod.yesterday,
        now: DateTime.utc(2026, 8, 1, 16),
      );
      _expectDates(window, DateTime(2026, 7, 31), DateTime(2026, 7, 31));
    });

    test('previous week is the complete prior Monday through Sunday', () {
      final window = NotificationDigestWindow.resolve(
        period: NotificationDigestPeriod.previousWeek,
        now: DateTime.utc(2026, 7, 25, 16),
      );

      _expectDates(
        window,
        DateTime(2026, 7, 13),
        DateTime(2026, 7, 19),
      );
      expect(window.startsAt, DateTime.utc(2026, 7, 13, 4));
      expect(window.endsAt, DateTime.utc(2026, 7, 20, 4));
    });

    test('previous month is the complete prior calendar month', () {
      final window = NotificationDigestWindow.resolve(
        period: NotificationDigestPeriod.previousMonth,
        now: DateTime.utc(2026, 1, 15, 16),
      );

      _expectDates(
        window,
        DateTime(2025, 12),
        DateTime(2025, 12, 31),
      );
    });

    test('custom dates are inclusive, date-only, and normalized', () {
      final window = NotificationDigestWindow.resolve(
        period: NotificationDigestPeriod.custom,
        now: DateTime.utc(2026, 7, 27, 16),
        customStartDate: DateTime(2026, 7, 25, 22, 45),
        customEndDate: DateTime(2026, 7, 20, 8, 15),
      );

      _expectDates(
        window,
        DateTime(2026, 7, 20),
        DateTime(2026, 7, 25),
      );
      expect(window.startsAt, DateTime.utc(2026, 7, 20, 4));
      expect(window.endsAt, DateTime.utc(2026, 7, 26, 4));
    });

    test('custom range ending today is clamped to the current instant', () {
      final window = NotificationDigestWindow.resolve(
        period: NotificationDigestPeriod.custom,
        now: DateTime.utc(2026, 7, 25, 16),
        customStartDate: DateTime(2026, 7, 20),
        customEndDate: DateTime(2026, 7, 25),
      );

      expect(window.startsAt, DateTime.utc(2026, 7, 20, 4));
      expect(window.endsAt, DateTime.utc(2026, 7, 25, 16));
    });

    test('calendar boundaries preserve Chile daylight-saving transitions', () {
      final window = NotificationDigestWindow.resolve(
        period: NotificationDigestPeriod.custom,
        now: DateTime.utc(2026, 4, 6, 16),
        customStartDate: DateTime(2026, 4, 4),
        customEndDate: DateTime(2026, 4, 4),
      );

      expect(window.startsAt, DateTime.utc(2026, 4, 4, 3));
      expect(window.endsAt, DateTime.utc(2026, 4, 5, 4));
      expect(
          window.endsAt.difference(window.startsAt), const Duration(hours: 25));
    });

    test('custom period requires both dates', () {
      expect(
        () => NotificationDigestWindow.resolve(
          period: NotificationDigestPeriod.custom,
          customStartDate: DateTime(2026, 7, 20),
        ),
        throwsArgumentError,
      );
      expect(
        () => NotificationDigestWindow.resolve(
          period: NotificationDigestPeriod.custom,
          customEndDate: DateTime(2026, 7, 25),
        ),
        throwsArgumentError,
      );
    });

    test('contains compares instants at inclusive and exclusive boundaries',
        () {
      final window = NotificationDigestWindow.resolve(
        period: NotificationDigestPeriod.today,
        now: DateTime.utc(2026, 7, 25, 16),
      );

      expect(window.contains(DateTime.utc(2026, 7, 25, 3, 59, 59)), isFalse);
      expect(window.contains(DateTime.utc(2026, 7, 25, 4)), isTrue);
      expect(window.contains(DateTime.utc(2026, 7, 25, 15, 59, 59)), isTrue);
      expect(window.contains(DateTime.utc(2026, 7, 25, 16)), isFalse);
    });
  });

  group('NotificationDigestSnapshot', () {
    test('today uses Chile boundaries and totals matching rows', () {
      final digest = NotificationDigestSnapshot.fromRows(
        period: NotificationDigestPeriod.today,
        now: DateTime.utc(2026, 7, 25, 16),
        notifications: [
          _row('mechanic_job_created', DateTime.utc(2026, 7, 25, 4)),
          _row(
            'sales_payment_received',
            DateTime.utc(2026, 7, 25, 13),
            amount: 24000,
          ),
          _row(
            'sales_payment_received',
            DateTime.utc(2026, 7, 25, 15, 59),
            amount: 6000,
            read: true,
          ),
          _row(
            'expense_recorded',
            DateTime.utc(2026, 7, 25, 15),
            totalAmount: 13580,
          ),
          _row(
            'online_order_created',
            DateTime.utc(2026, 7, 25, 3, 59, 59),
          ),
          _row(
            'whatsapp_catalog_approved',
            DateTime.utc(2026, 7, 25, 16),
          ),
        ],
        fileCreatedAt: [
          DateTime.utc(2026, 7, 25, 4),
          DateTime.utc(2026, 7, 25, 15, 59),
          DateTime.utc(2026, 7, 25, 16),
        ],
      );

      expect(digest.startDate, DateTime(2026, 7, 25));
      expect(digest.endDate, DateTime(2026, 7, 25));
      expect(digest.startsAt, DateTime.utc(2026, 7, 25, 4));
      expect(digest.endsAt, DateTime.utc(2026, 7, 25, 16));
      expect(digest.jobCount, 1);
      expect(digest.paymentCount, 2);
      expect(digest.paymentTotal, 30000);
      expect(digest.expenseCount, 1);
      expect(digest.expenseTotal, 13580);
      expect(digest.onlineOrderCount, 0);
      expect(digest.catalogApprovalCount, 0);
      expect(digest.fileCount, 2);
      expect(digest.unreadAlertCount, 3);
    });

    test('custom snapshot forwards and normalizes its selected dates', () {
      final digest = NotificationDigestSnapshot.fromRows(
        period: NotificationDigestPeriod.custom,
        now: DateTime.utc(2026, 7, 26, 16),
        customStartDate: DateTime(2026, 7, 25),
        customEndDate: DateTime(2026, 7, 20),
        notifications: [
          _row(
            'online_order_created',
            DateTime.utc(2026, 7, 20, 4),
          ),
          _row(
            'online_order_created',
            DateTime.utc(2026, 7, 26, 3, 59),
          ),
          _row(
            'online_order_created',
            DateTime.utc(2026, 7, 26, 4),
          ),
        ],
      );

      expect(digest.startDate, DateTime(2026, 7, 20));
      expect(digest.endDate, DateTime(2026, 7, 25));
      expect(digest.onlineOrderCount, 2);
      expect(digest.contains(DateTime.utc(2026, 7, 26, 3, 59)), isTrue);
      expect(digest.contains(DateTime.utc(2026, 7, 26, 4)), isFalse);
    });

    test('financial totals use occurred_at while unread uses created_at', () {
      final rows = [
        _row(
          'sales_payment_received',
          DateTime.utc(2026, 7, 25, 13),
          occurredAt: DateTime.utc(2026, 7, 24, 13),
          amount: 72000,
        ),
        _row(
          'expense_recorded',
          DateTime.utc(2026, 7, 25, 14),
          occurredAt: DateTime.utc(2026, 7, 24, 14),
          totalAmount: 52000,
        ),
      ];

      final today = NotificationDigestSnapshot.fromRows(
        period: NotificationDigestPeriod.today,
        now: DateTime.utc(2026, 7, 25, 16),
        notifications: rows,
      );
      final economicDay = NotificationDigestSnapshot.fromRows(
        period: NotificationDigestPeriod.custom,
        now: DateTime.utc(2026, 7, 25, 16),
        customStartDate: DateTime(2026, 7, 24),
        customEndDate: DateTime(2026, 7, 24),
        notifications: rows,
      );

      expect(today.paymentCount, 0);
      expect(today.paymentTotal, 0);
      expect(today.expenseCount, 0);
      expect(today.expenseTotal, 0);
      expect(today.unreadAlertCount, 2);
      expect(economicDay.paymentCount, 1);
      expect(economicDay.paymentTotal, 72000);
      expect(economicDay.expenseCount, 1);
      expect(economicDay.expenseTotal, 52000);
      expect(economicDay.unreadAlertCount, 0);
    });

    test('voided payments stay activity but never reach payment metrics', () {
      final digest = NotificationDigestSnapshot.fromRows(
        period: NotificationDigestPeriod.today,
        now: DateTime.utc(2026, 7, 25, 16),
        notifications: [
          _row(
            'sales_payment_received',
            DateTime.utc(2026, 7, 25, 13),
            amount: 10000,
          ),
          _row(
            'sales_payment_voided',
            DateTime.utc(2026, 7, 25, 14),
            amount: 82000,
            voided: true,
          ),
          // Defensive mixed-version shape: even before the server-side type
          // update is observed, the explicit state cannot inflate the metric.
          _row(
            'sales_payment_received',
            DateTime.utc(2026, 7, 25, 15),
            amount: 6000,
            voided: true,
          ),
        ],
      );

      expect(digest.paymentCount, 1);
      expect(digest.paymentTotal, 10000);
      expect(digest.unreadAlertCount, 3);
    });

    test('every ribbon metric counts one active source entity only', () {
      final now = DateTime.utc(2026, 7, 25, 16);
      final recordedAt = DateTime.utc(2026, 7, 25, 13);
      final notifications = <Map<String, dynamic>>[
        _row(
          'mechanic_job_created',
          recordedAt,
          id: 'job-live-notification',
          entityType: 'mechanic_job',
          entityId: 'job-live',
        ),
        _row(
          'mechanic_job_created',
          recordedAt,
          id: 'job-live-notification',
          entityType: 'mechanic_job',
          entityId: 'job-live',
        ),
        _row(
          'mechanic_job_created',
          recordedAt,
          id: 'job-stale-created',
          entityType: 'mechanic_job',
          entityId: 'job-archived',
        ),
        _row(
          'mechanic_job_archived',
          recordedAt,
          id: 'job-stale-archived',
          entityType: 'mechanic_job',
          entityId: 'job-archived',
          inactive: true,
        ),
        _row(
          'sales_payment_received',
          recordedAt,
          id: 'payment-live-notification',
          entityType: 'sales_payment',
          entityId: 'payment-live',
          amount: 12000,
        ),
        _row(
          'sales_payment_received',
          recordedAt,
          id: 'payment-live-notification',
          entityType: 'sales_payment',
          entityId: 'payment-live',
          amount: 12000,
        ),
        _row(
          'expense_recorded',
          recordedAt,
          id: 'expense-live-notification',
          entityType: 'expense',
          entityId: 'expense-live',
          totalAmount: 9000,
        ),
        _row(
          'expense_recorded',
          recordedAt,
          id: 'expense-live-notification',
          entityType: 'expense',
          entityId: 'expense-live',
          totalAmount: 9000,
        ),
        _row(
          'expense_recorded',
          recordedAt,
          id: 'expense-stale-recorded',
          entityType: 'expense',
          entityId: 'expense-deleted',
          totalAmount: 7000,
        ),
        _row(
          'expense_deleted',
          recordedAt,
          id: 'expense-stale-deleted',
          entityType: 'expense',
          entityId: 'expense-deleted',
          totalAmount: 7000,
          inactive: true,
        ),
        _row(
          'online_order_created',
          recordedAt,
          id: 'order-live-notification',
          entityType: 'online_order',
          entityId: 'order-live',
        ),
        _row(
          'online_order_created',
          recordedAt,
          id: 'order-live-notification',
          entityType: 'online_order',
          entityId: 'order-live',
        ),
        _row(
          'online_order_created',
          recordedAt,
          id: 'order-stale-created',
          entityType: 'online_order',
          entityId: 'order-cancelled',
        ),
        _row(
          'online_order_cancelled',
          recordedAt,
          id: 'order-stale-cancelled',
          entityType: 'online_order',
          entityId: 'order-cancelled',
          inactive: true,
        ),
      ];

      final digest = NotificationDigestSnapshot.fromRows(
        period: NotificationDigestPeriod.today,
        now: now,
        notifications: notifications,
      );

      expect(digest.jobCount, 1);
      expect(digest.paymentCount, 1);
      expect(digest.paymentTotal, 12000);
      expect(digest.expenseCount, 1);
      expect(digest.expenseTotal, 9000);
      expect(digest.onlineOrderCount, 1);
      expect(digest.unreadAlertCount, 10);
    });

    test('mixed-version inactive payloads suppress every active event type',
        () {
      final digest = NotificationDigestSnapshot.fromRows(
        period: NotificationDigestPeriod.today,
        now: DateTime.utc(2026, 7, 25, 16),
        notifications: [
          _row(
            'mechanic_job_created',
            DateTime.utc(2026, 7, 25, 12),
            entityType: 'mechanic_job',
            entityId: 'job-inactive',
            inactive: true,
          ),
          _row(
            'expense_recorded',
            DateTime.utc(2026, 7, 25, 12),
            entityType: 'expense',
            entityId: 'expense-inactive',
            totalAmount: 3500,
            inactive: true,
          ),
          _row(
            'online_order_created',
            DateTime.utc(2026, 7, 25, 12),
            entityType: 'online_order',
            entityId: 'order-inactive',
            inactive: true,
          ),
        ],
      );

      expect(digest.jobCount, 0);
      expect(digest.expenseCount, 0);
      expect(digest.expenseTotal, 0);
      expect(digest.onlineOrderCount, 0);
      expect(digest.unreadAlertCount, 3);
    });
  });
}

void _expectDates(
  NotificationDigestWindow window,
  DateTime startDate,
  DateTime endDate,
) {
  expect(window.startDate, startDate);
  expect(window.endDate, endDate);
}

Map<String, dynamic> _row(
  String type,
  DateTime createdAt, {
  DateTime? occurredAt,
  num? amount,
  num? totalAmount,
  bool read = false,
  bool voided = false,
  bool inactive = false,
  String? id,
  String? entityType,
  String? entityId,
}) {
  return {
    if (id != null) 'id': id,
    'type': type,
    if (entityType != null) 'entity_type': entityType,
    if (entityId != null) 'entity_id': entityId,
    'created_at': createdAt.toIso8601String(),
    'occurred_at': (occurredAt ?? createdAt).toIso8601String(),
    'read_at': read
        ? createdAt.add(const Duration(minutes: 1)).toIso8601String()
        : null,
    if (amount != null || totalAmount != null || voided || inactive)
      'data': {
        if (amount != null) 'amount': amount,
        if (totalAmount != null) 'total_amount': totalAmount,
        if (voided) 'is_voided': true,
        if (inactive) 'is_inactive': true,
      },
  };
}
