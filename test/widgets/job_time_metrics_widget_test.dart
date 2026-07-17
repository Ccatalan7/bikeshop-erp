import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/job_time_metrics_widget.dart';

void main() {
  final job = MechanicJob(
    id: 'job-1',
    tenantId: 'tenant-1',
    customerId: 'customer-1',
    arrivalDate: DateTime.parse('2026-07-01T13:00:00Z'),
    actualLaborHours: 3.5,
    timeMetrics: MechanicJobTimeMetrics(
      jobId: 'job-1',
      startedAt: DateTime.parse('2026-07-01T15:00:00Z'),
      startSource: 'legacy_timeline',
      completedAt: DateTime.parse('2026-07-01T18:30:00Z'),
      completionSource: 'recorded_timestamp',
      firstDeliveredAt: DateTime.parse('2026-07-02T17:00:00Z'),
      deliverySource: 'legacy_timeline',
      currentIsCompleted: true,
      currentIsDelivered: false,
      reopenedAfterDelivery: true,
      qualityFlags: const ['start_reconstructed_from_timeline'],
    ),
  );

  testWidgets('compact workshop flow fits the table column', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 132,
            child: CompactJobTimeMetrics(job: job),
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.byType(CompactJobTimeMetrics), findsOneWidget);
    expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
  });

  testWidgets('detail timeline remains readable on a narrow host',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 340,
            child: JobTimeMetricsPanel(job: job),
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
    expect(find.text('Espera a taller'), findsOneWidget);
    expect(find.text('Ejecución'), findsOneWidget);
    expect(find.text('Primera entrega'), findsOneWidget);
    expect(find.textContaining('3,5 h de trabajo mecánico'), findsOneWidget);
  });
}
