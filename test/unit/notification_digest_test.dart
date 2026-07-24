import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/notification_digest.dart';

void main() {
  group('NotificationDigestSnapshot', () {
    test('today uses local calendar boundaries and totals payments', () {
      final now = DateTime(2026, 7, 16, 22, 30);
      final digest = NotificationDigestSnapshot.fromRows(
        period: NotificationDigestPeriod.today,
        now: now,
        notifications: [
          _row('mechanic_job_created', DateTime(2026, 7, 16, 0, 1)),
          _row(
            'sales_payment_received',
            DateTime(2026, 7, 16, 9),
            amount: 24000,
          ),
          _row(
            'sales_payment_received',
            DateTime(2026, 7, 16, 18),
            amount: 6000,
            read: true,
          ),
          _row(
            'expense_recorded',
            DateTime(2026, 7, 16, 19),
            totalAmount: 13580,
          ),
          _row('online_order_created', DateTime(2026, 7, 15, 23, 59)),
        ],
        fileCreatedAt: [
          DateTime(2026, 7, 16, 12),
          DateTime(2026, 7, 15, 23, 59),
        ],
      );

      expect(digest.jobCount, 1);
      expect(digest.paymentCount, 2);
      expect(digest.paymentTotal, 30000);
      expect(digest.expenseCount, 1);
      expect(digest.expenseTotal, 13580);
      expect(digest.onlineOrderCount, 0);
      expect(digest.fileCount, 1);
      expect(digest.unreadAlertCount, 3);
    });

    test('seven day period includes today and the six prior calendar days', () {
      final now = DateTime(2026, 7, 16, 10);
      final digest = NotificationDigestSnapshot.fromRows(
        period: NotificationDigestPeriod.sevenDays,
        now: now,
        notifications: [
          _row('mechanic_job_created', DateTime(2026, 7, 10)),
          _row('online_order_created', DateTime(2026, 7, 16, 23, 59)),
          _row('whatsapp_catalog_approved', DateTime(2026, 7, 9, 23, 59)),
        ],
      );

      expect(digest.startsAt, DateTime(2026, 7, 10));
      expect(digest.endsAt, DateTime(2026, 7, 17));
      expect(digest.jobCount, 1);
      expect(digest.onlineOrderCount, 1);
      expect(digest.catalogApprovalCount, 0);
    });
  });
}

Map<String, dynamic> _row(
  String type,
  DateTime createdAt, {
  num? amount,
  num? totalAmount,
  bool read = false,
}) {
  return {
    'type': type,
    'created_at': createdAt.toIso8601String(),
    'read_at': read
        ? createdAt.add(const Duration(minutes: 1)).toIso8601String()
        : null,
    if (amount != null || totalAmount != null)
      'data': {
        if (amount != null) 'amount': amount,
        if (totalAmount != null) 'total_amount': totalAmount,
      },
  };
}
