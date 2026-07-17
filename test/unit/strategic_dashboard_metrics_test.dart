import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/strategic_dashboard_metrics.dart';
import 'package:vinabike_erp/shared/services/strategic_dashboard_service.dart';

void main() {
  test('builds exact calendar windows for strategic dashboard presets', () {
    final today = DateTime(2026, 7, 17);

    final thisMonth = StrategicDashboardDateWindow.forPreset(
      StrategicDashboardPeriodPreset.thisMonth,
      today: today,
    );
    final previousMonth = StrategicDashboardDateWindow.forPreset(
      StrategicDashboardPeriodPreset.previousMonth,
      today: today,
    );
    final last30Days = StrategicDashboardDateWindow.forPreset(
      StrategicDashboardPeriodPreset.last30Days,
      today: today,
    );

    expect(thisMonth.startDate, DateTime(2026, 7));
    expect(thisMonth.endDate, today);
    expect(previousMonth.startDate, DateTime(2026, 6));
    expect(previousMonth.endDate, DateTime(2026, 6, 30));
    expect(last30Days.startDate, DateTime(2026, 6, 18));
    expect(last30Days.endDate, today);
  });

  test('normalizes a reversed custom strategic dashboard range', () {
    final window = StrategicDashboardDateWindow.custom(
      DateTime(2026, 7, 17, 18),
      DateTime(2026, 7, 4, 9),
    );

    expect(window.startDate, DateTime(2026, 7, 4));
    expect(window.endDate, DateTime(2026, 7, 17));
  });

  test('anchors dashboard calendar presets to the Chile business date', () {
    expect(
      StrategicDashboardService.businessToday(
        nowUtc: DateTime.utc(2026, 7, 17, 2),
      ),
      DateTime(2026, 7, 16),
    );
    expect(
      StrategicDashboardService.businessToday(
        nowUtc: DateTime.utc(2026, 7, 17, 6),
      ),
      DateTime(2026, 7, 17),
    );
  });

  test('parses precise workshop, capacity, payroll and sales-mix metrics', () {
    final metrics = StrategicDashboardMetrics.fromJson({
      'period': {
        'start': '2026-07-01T00:00:00Z',
        'end': '2026-07-31T00:00:00Z',
        'days': 30,
      },
      'flow': {
        'approvalMedianHours': 12.5,
        'approvalSamples': 4,
        'startMedianHours': 8,
        'startSamples': 5,
        'executionMedianHours': 24,
        'executionSamples': 6,
        'totalMedianHours': 72,
        'totalSamples': 7,
        'deliveredCount': 7,
        'onTimeRate': 0.75,
        'onTimeSamples': 4,
        'approvalRate': 0.8,
        'decisionSamples': 5,
      },
      'load': {
        'activeCount': 8,
        'overdueCount': 2,
        'ageBuckets': [
          {'label': '0–2 días', 'count': 3},
        ],
      },
      'value': {
        'netSales': 320000,
        'averageTicket': 150000,
        'invoiceCount': 2,
        'serviceSales': 100000,
        'productSales': 200000,
        'unclassifiedSales': 20000,
        'serviceSalesShare': 100000 / 320000,
        'productSalesShare': 200000 / 320000,
        'unclassifiedSalesShare': 20000 / 320000,
        'classificationCoverageRate': 300000 / 320000,
        'workshopServiceSales': 100000,
        'workshopProductSales': 200000,
        'workshopUnclassifiedSales': 20000,
        'productCostCoverageRate': 1,
        'productCogs': 100000,
        'productGrossContribution': 100000,
        'productGrossMarginRate': 0.5,
        'actualHours': 5,
        'actualHoursJobs': 1,
        'laborHourCoverageRate': 0.5,
        'netSalesPerLaborHour': 60000,
        'estimateAccuracyRate': 1,
        'estimateSamples': 1,
        'businessOpenHours': 40,
        'mechanicAttendanceHours': 10,
        'mechanicCount': 1,
        'mechanicEquivalentCoverage': 0.25,
        'productiveUtilizationRate': 0.5,
        'netSalesPerAttendanceHour': 30000,
        'serviceSalesPerAttendanceHour': 10000,
        'paidMechanicCost': 40000,
        'pendingMechanicCost': 0,
        'attendanceEstimatedMechanicCost': 40000,
        'mechanicCostSource': 'paid_payroll',
        'mechanicCostUsed': 40000,
        'laborContribution': 60000,
        'laborContributionRate': 0.6,
        'jobAssignmentCoverageRate': 0,
      },
      'inventory': {
        'soldProducts': 1,
        'unitsSold': 2,
        'stockCoverDays': 35,
        'stagnantProductCount': 3,
        'stagnantStockValue': 90000,
        'topProducts': [
          {
            'productId': 'product-1',
            'name': 'Cadena',
            'units': 2,
            'sales': 200000,
          },
        ],
      },
      'weekly': [
        {
          'start': '2026-07-06T00:00:00Z',
          'deliveries': 4,
          'netSales': 300000,
        },
      ],
    });

    expect(metrics.flow.approvalMedianHours, 12.5);
    expect(metrics.load.ageBuckets.single.count, 3);
    expect(metrics.value.serviceSales, 100000);
    expect(metrics.value.productSales, 200000);
    expect(metrics.value.unclassifiedSales, 20000);
    expect(metrics.value.classificationCoverageRate, 0.9375);
    expect(metrics.value.productGrossMarginRate, 0.5);
    expect(metrics.value.mechanicAttendanceHours, 10);
    expect(metrics.value.mechanicCostSource, 'paid_payroll');
    expect(metrics.value.laborContribution, 60000);
    expect(metrics.inventory.topProducts.single.name, 'Cadena');
    expect(metrics.weekly.single.deliveries, 4);
  });

  test('keeps unavailable ratios nullable instead of turning them into zero',
      () {
    final metrics = StrategicDashboardMetrics.fromJson({
      'period': {},
      'flow': {},
      'load': {},
      'value': {},
      'inventory': {},
      'weekly': const [],
    });

    expect(metrics.flow.approvalMedianHours, isNull);
    expect(metrics.flow.onTimeRate, isNull);
    expect(metrics.value.productGrossMarginRate, isNull);
    expect(metrics.value.productiveUtilizationRate, isNull);
    expect(metrics.inventory.stockCoverDays, isNull);
  });
}
