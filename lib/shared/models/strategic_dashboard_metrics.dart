class StrategicDashboardMetrics {
  const StrategicDashboardMetrics({
    required this.period,
    required this.flow,
    required this.load,
    required this.value,
    required this.inventory,
    required this.weekly,
  });

  final StrategicMetricPeriod period;
  final WorkshopFlowMetrics flow;
  final WorkshopLoadMetrics load;
  final WorkshopValueMetrics value;
  final InventoryRotationMetrics inventory;
  final List<StrategicWeeklyPoint> weekly;

  factory StrategicDashboardMetrics.fromJson(Map<String, dynamic> json) {
    return StrategicDashboardMetrics(
      period: StrategicMetricPeriod.fromJson(_map(json['period'])),
      flow: WorkshopFlowMetrics.fromJson(_map(json['flow'])),
      load: WorkshopLoadMetrics.fromJson(_map(json['load'])),
      value: WorkshopValueMetrics.fromJson(_map(json['value'])),
      inventory: InventoryRotationMetrics.fromJson(_map(json['inventory'])),
      weekly: _list(json['weekly'])
          .map((row) => StrategicWeeklyPoint.fromJson(_map(row)))
          .toList(growable: false),
    );
  }
}

class StrategicMetricPeriod {
  const StrategicMetricPeriod({
    required this.start,
    required this.end,
    required this.days,
  });

  final DateTime? start;
  final DateTime? end;
  final int days;

  factory StrategicMetricPeriod.fromJson(Map<String, dynamic> json) {
    return StrategicMetricPeriod(
      start: DateTime.tryParse(json['start']?.toString() ?? ''),
      end: DateTime.tryParse(json['end']?.toString() ?? ''),
      days: _integer(json['days']),
    );
  }
}

class WorkshopFlowMetrics {
  const WorkshopFlowMetrics({
    required this.approvalMedianHours,
    required this.approvalSamples,
    required this.startMedianHours,
    required this.startSamples,
    required this.executionMedianHours,
    required this.executionSamples,
    required this.totalMedianHours,
    required this.totalSamples,
    required this.deliveredCount,
    required this.onTimeRate,
    required this.onTimeSamples,
    required this.approvalRate,
    required this.decisionSamples,
  });

  final double? approvalMedianHours;
  final int approvalSamples;
  final double? startMedianHours;
  final int startSamples;
  final double? executionMedianHours;
  final int executionSamples;
  final double? totalMedianHours;
  final int totalSamples;
  final int deliveredCount;
  final double? onTimeRate;
  final int onTimeSamples;
  final double? approvalRate;
  final int decisionSamples;

  factory WorkshopFlowMetrics.fromJson(Map<String, dynamic> json) {
    return WorkshopFlowMetrics(
      approvalMedianHours: _nullableNumber(json['approvalMedianHours']),
      approvalSamples: _integer(json['approvalSamples']),
      startMedianHours: _nullableNumber(json['startMedianHours']),
      startSamples: _integer(json['startSamples']),
      executionMedianHours: _nullableNumber(json['executionMedianHours']),
      executionSamples: _integer(json['executionSamples']),
      totalMedianHours: _nullableNumber(json['totalMedianHours']),
      totalSamples: _integer(json['totalSamples']),
      deliveredCount: _integer(json['deliveredCount']),
      onTimeRate: _nullableNumber(json['onTimeRate']),
      onTimeSamples: _integer(json['onTimeSamples']),
      approvalRate: _nullableNumber(json['approvalRate']),
      decisionSamples: _integer(json['decisionSamples']),
    );
  }
}

class WorkshopLoadMetrics {
  const WorkshopLoadMetrics({
    required this.activeCount,
    required this.overdueCount,
    required this.ageBuckets,
  });

  final int activeCount;
  final int overdueCount;
  final List<WorkshopAgeBucket> ageBuckets;

  factory WorkshopLoadMetrics.fromJson(Map<String, dynamic> json) {
    return WorkshopLoadMetrics(
      activeCount: _integer(json['activeCount']),
      overdueCount: _integer(json['overdueCount']),
      ageBuckets: _list(json['ageBuckets'])
          .map((row) => WorkshopAgeBucket.fromJson(_map(row)))
          .toList(growable: false),
    );
  }
}

class WorkshopAgeBucket {
  const WorkshopAgeBucket({required this.label, required this.count});

  final String label;
  final int count;

  factory WorkshopAgeBucket.fromJson(Map<String, dynamic> json) {
    return WorkshopAgeBucket(
      label: json['label']?.toString() ?? '',
      count: _integer(json['count']),
    );
  }
}

class WorkshopValueMetrics {
  const WorkshopValueMetrics({
    required this.netSales,
    required this.averageTicket,
    required this.invoiceCount,
    required this.serviceSales,
    required this.productSales,
    required this.unclassifiedSales,
    required this.serviceSalesShare,
    required this.productSalesShare,
    required this.unclassifiedSalesShare,
    required this.classificationCoverageRate,
    required this.workshopServiceSales,
    required this.workshopProductSales,
    required this.workshopUnclassifiedSales,
    required this.productCostCoverageRate,
    required this.productCogs,
    required this.productGrossContribution,
    required this.productGrossMarginRate,
    required this.actualHours,
    required this.actualHoursJobs,
    required this.laborHourCoverageRate,
    required this.netSalesPerLaborHour,
    required this.estimateAccuracyRate,
    required this.estimateSamples,
    required this.businessOpenHours,
    required this.mechanicAttendanceHours,
    required this.mechanicCount,
    required this.mechanicEquivalentCoverage,
    required this.productiveUtilizationRate,
    required this.netSalesPerAttendanceHour,
    required this.serviceSalesPerAttendanceHour,
    required this.paidMechanicCost,
    required this.pendingMechanicCost,
    required this.attendanceEstimatedMechanicCost,
    required this.mechanicCostSource,
    required this.mechanicCostUsed,
    required this.laborContribution,
    required this.laborContributionRate,
    required this.jobAssignmentCoverageRate,
  });

  final double netSales;
  final double averageTicket;
  final int invoiceCount;
  final double serviceSales;
  final double productSales;
  final double unclassifiedSales;
  final double? serviceSalesShare;
  final double? productSalesShare;
  final double? unclassifiedSalesShare;
  final double? classificationCoverageRate;
  final double workshopServiceSales;
  final double workshopProductSales;
  final double workshopUnclassifiedSales;
  final double? productCostCoverageRate;
  final double productCogs;
  final double productGrossContribution;
  final double? productGrossMarginRate;
  final double actualHours;
  final int actualHoursJobs;
  final double? laborHourCoverageRate;
  final double? netSalesPerLaborHour;
  final double? estimateAccuracyRate;
  final int estimateSamples;
  final double businessOpenHours;
  final double mechanicAttendanceHours;
  final int mechanicCount;
  final double? mechanicEquivalentCoverage;
  final double? productiveUtilizationRate;
  final double? netSalesPerAttendanceHour;
  final double? serviceSalesPerAttendanceHour;
  final double paidMechanicCost;
  final double pendingMechanicCost;
  final double attendanceEstimatedMechanicCost;
  final String mechanicCostSource;
  final double mechanicCostUsed;
  final double laborContribution;
  final double? laborContributionRate;
  final double? jobAssignmentCoverageRate;

  factory WorkshopValueMetrics.fromJson(Map<String, dynamic> json) {
    return WorkshopValueMetrics(
      netSales: _number(json['netSales']),
      averageTicket: _number(json['averageTicket']),
      invoiceCount: _integer(json['invoiceCount']),
      serviceSales: _number(json['serviceSales']),
      productSales: _number(json['productSales']),
      unclassifiedSales: _number(json['unclassifiedSales']),
      serviceSalesShare: _nullableNumber(json['serviceSalesShare']),
      productSalesShare: _nullableNumber(json['productSalesShare']),
      unclassifiedSalesShare: _nullableNumber(json['unclassifiedSalesShare']),
      classificationCoverageRate:
          _nullableNumber(json['classificationCoverageRate']),
      workshopServiceSales: _number(json['workshopServiceSales']),
      workshopProductSales: _number(json['workshopProductSales']),
      workshopUnclassifiedSales: _number(json['workshopUnclassifiedSales']),
      productCostCoverageRate: _nullableNumber(json['productCostCoverageRate']),
      productCogs: _number(json['productCogs']),
      productGrossContribution: _number(json['productGrossContribution']),
      productGrossMarginRate: _nullableNumber(json['productGrossMarginRate']),
      actualHours: _number(json['actualHours']),
      actualHoursJobs: _integer(json['actualHoursJobs']),
      laborHourCoverageRate: _nullableNumber(json['laborHourCoverageRate']),
      netSalesPerLaborHour: _nullableNumber(json['netSalesPerLaborHour']),
      estimateAccuracyRate: _nullableNumber(json['estimateAccuracyRate']),
      estimateSamples: _integer(json['estimateSamples']),
      businessOpenHours: _number(json['businessOpenHours']),
      mechanicAttendanceHours: _number(json['mechanicAttendanceHours']),
      mechanicCount: _integer(json['mechanicCount']),
      mechanicEquivalentCoverage:
          _nullableNumber(json['mechanicEquivalentCoverage']),
      productiveUtilizationRate:
          _nullableNumber(json['productiveUtilizationRate']),
      netSalesPerAttendanceHour:
          _nullableNumber(json['netSalesPerAttendanceHour']),
      serviceSalesPerAttendanceHour:
          _nullableNumber(json['serviceSalesPerAttendanceHour']),
      paidMechanicCost: _number(json['paidMechanicCost']),
      pendingMechanicCost: _number(json['pendingMechanicCost']),
      attendanceEstimatedMechanicCost:
          _number(json['attendanceEstimatedMechanicCost']),
      mechanicCostSource: json['mechanicCostSource']?.toString() ?? '',
      mechanicCostUsed: _number(json['mechanicCostUsed']),
      laborContribution: _number(json['laborContribution']),
      laborContributionRate: _nullableNumber(json['laborContributionRate']),
      jobAssignmentCoverageRate:
          _nullableNumber(json['jobAssignmentCoverageRate']),
    );
  }
}

class InventoryRotationMetrics {
  const InventoryRotationMetrics({
    required this.soldProducts,
    required this.unitsSold,
    required this.stockCoverDays,
    required this.stagnantProductCount,
    required this.stagnantStockValue,
    required this.topProducts,
  });

  final int soldProducts;
  final double unitsSold;
  final double? stockCoverDays;
  final int stagnantProductCount;
  final double stagnantStockValue;
  final List<TopProductMetric> topProducts;

  factory InventoryRotationMetrics.fromJson(Map<String, dynamic> json) {
    return InventoryRotationMetrics(
      soldProducts: _integer(json['soldProducts']),
      unitsSold: _number(json['unitsSold']),
      stockCoverDays: _nullableNumber(json['stockCoverDays']),
      stagnantProductCount: _integer(json['stagnantProductCount']),
      stagnantStockValue: _number(json['stagnantStockValue']),
      topProducts: _list(json['topProducts'])
          .map((row) => TopProductMetric.fromJson(_map(row)))
          .toList(growable: false),
    );
  }
}

class TopProductMetric {
  const TopProductMetric({
    required this.productId,
    required this.name,
    required this.units,
    required this.sales,
  });

  final String productId;
  final String name;
  final double units;
  final double sales;

  factory TopProductMetric.fromJson(Map<String, dynamic> json) {
    return TopProductMetric(
      productId: json['productId']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Producto',
      units: _number(json['units']),
      sales: _number(json['sales']),
    );
  }
}

class StrategicWeeklyPoint {
  const StrategicWeeklyPoint({
    required this.start,
    required this.deliveries,
    required this.netSales,
  });

  final DateTime? start;
  final int deliveries;
  final double netSales;

  factory StrategicWeeklyPoint.fromJson(Map<String, dynamic> json) {
    return StrategicWeeklyPoint(
      start: DateTime.tryParse(json['start']?.toString() ?? ''),
      deliveries: _integer(json['deliveries']),
      netSales: _number(json['netSales']),
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

List<dynamic> _list(Object? value) => value is List ? value : const [];

double _number(Object? value) => _nullableNumber(value) ?? 0;

double? _nullableNumber(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
