enum NotificationDigestPeriod { today, sevenDays }

/// Aggregated operational activity for the notifications briefing.
///
/// The digest intentionally uses local calendar boundaries. "Hoy" therefore
/// means the current business day, rather than a moving 24-hour window that
/// changes while a manager is reading it.
class NotificationDigestSnapshot {
  const NotificationDigestSnapshot({
    required this.period,
    required this.startsAt,
    required this.endsAt,
    required this.jobCount,
    required this.paymentCount,
    required this.paymentTotal,
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
  }) {
    final localNow = (now ?? DateTime.now()).toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final startsAt = period == NotificationDigestPeriod.today
        ? today
        : today.subtract(const Duration(days: 6));
    final endsAt = today.add(const Duration(days: 1));

    var jobCount = 0;
    var paymentCount = 0;
    var paymentTotal = 0.0;
    var onlineOrderCount = 0;
    var catalogApprovalCount = 0;
    var unreadAlertCount = 0;

    for (final row in notifications) {
      final createdAt = DateTime.tryParse(
        row['created_at']?.toString() ?? '',
      )?.toLocal();
      if (createdAt == null ||
          createdAt.isBefore(startsAt) ||
          !createdAt.isBefore(endsAt)) {
        continue;
      }

      if (row['read_at'] == null) unreadAlertCount++;

      switch (row['type']?.toString()) {
        case 'mechanic_job_created':
          jobCount++;
          break;
        case 'sales_payment_received':
          paymentCount++;
          final data = row['data'];
          if (data is Map && data['amount'] is num) {
            paymentTotal += (data['amount'] as num).toDouble();
          }
          break;
        case 'online_order_created':
          onlineOrderCount++;
          break;
        case 'whatsapp_catalog_approved':
          catalogApprovalCount++;
          break;
      }
    }

    final fileCount = fileCreatedAt.where((createdAt) {
      final local = createdAt.toLocal();
      return !local.isBefore(startsAt) && local.isBefore(endsAt);
    }).length;

    return NotificationDigestSnapshot(
      period: period,
      startsAt: startsAt,
      endsAt: endsAt,
      jobCount: jobCount,
      paymentCount: paymentCount,
      paymentTotal: paymentTotal,
      onlineOrderCount: onlineOrderCount,
      catalogApprovalCount: catalogApprovalCount,
      fileCount: fileCount,
      unreadAlertCount: unreadAlertCount,
    );
  }

  final NotificationDigestPeriod period;
  final DateTime startsAt;
  final DateTime endsAt;
  final int jobCount;
  final int paymentCount;
  final double paymentTotal;
  final int onlineOrderCount;
  final int catalogApprovalCount;
  final int fileCount;
  final int unreadAlertCount;

  bool contains(DateTime dateTime) {
    final local = dateTime.toLocal();
    return !local.isBefore(startsAt) && local.isBefore(endsAt);
  }
}
