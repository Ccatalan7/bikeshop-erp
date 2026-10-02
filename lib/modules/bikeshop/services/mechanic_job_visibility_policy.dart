import 'package:flutter/foundation.dart' show kDebugMode;

import '../models/bikeshop_models.dart';
import '../../sales/models/sales_models.dart';
import 'mechanic_job_sale_ui_policy.dart';

bool isMechanicJobCurrentlyDelivered(MechanicJob job) {
  return job.status == JobStatus.entregado ||
      job.customStatus?.triggersDelivery == true ||
      job.customStatus?.code.trim().toLowerCase() == 'entregado';
}

/// Los trabajos de prueba se ofrecen como activos al elegir un trabajo sólo
/// en la app de depuración, para probar contra ellos sin tocar trabajos
/// reales; la app publicada nunca los ofrece (dueño, 2026-10-01).
const bool kWorkshopTestJobsSelectable = kDebugMode;

/// Canonical eligibility for every UI that promises "Trabajos activos".
///
/// This deliberately matches the default Activos scope of the Jobs table:
/// completed work remains operational until delivery, and a delivered job
/// remains active while its invoice is still unpaid. Historical, cancelled,
/// closed quotation, paid sale and completed warranty records do not qualify.
/// A test fixture never qualifies unless [includeTestFixtures]; then it is
/// judged by the same rules as real work.
bool isMechanicJobOperationallyActive(
  MechanicJob job, {
  Invoice? invoice,
  String? customerName,
  String? bikeName,
  String? bikeBrand,
  String? bikeModel,
  String? bikeSerialNumber,
  bool includeTestFixtures = false,
}) {
  if (job.deletedAt != null) return false;
  if (!includeTestFixtures &&
      mechanicJobMatchesTestFixture(
        job,
        customerName: customerName,
        bikeName: bikeName,
        bikeBrand: bikeBrand,
        bikeModel: bikeModel,
        bikeSerialNumber: bikeSerialNumber,
      )) {
    return false;
  }

  if (job.isSaleWorkflow) {
    return isMechanicJobSaleActive(job, invoice);
  }

  if (job.isStandaloneQuotation &&
      (job.effectiveQuotationStatus == QuotationStatus.rejected ||
          job.effectiveQuotationStatus == QuotationStatus.expired)) {
    return false;
  }

  if (job.status == JobStatus.cancelado) return false;

  final isDelivered = isMechanicJobCurrentlyDelivered(job);
  final isInvoiced = job.invoiceId != null || job.isInvoiced;
  final isPaid =
      invoice != null ? invoice.status == InvoiceStatus.paid : job.isPaid;
  if (isDelivered && isInvoiced && isPaid) return false;

  final isFinishedWarranty = job.isWarrantyJob &&
      isDelivered &&
      (job.totalCost <= 0 || (isInvoiced && isPaid));
  return !isFinishedWarranty;
}

bool mechanicJobMatchesTestFixture(
  MechanicJob job, {
  String? customerName,
  String? bikeName,
  String? bikeBrand,
  String? bikeModel,
  String? bikeSerialNumber,
}) {
  final normalizedCustomerName = customerName?.trim().toLowerCase() ?? '';
  if (_startsWithTest(normalizedCustomerName)) return true;

  final normalizedBikeName = bikeName?.trim().toLowerCase() ?? '';
  if (_startsWithTest(normalizedBikeName)) return true;

  final auditText = [
    job.jobNumber,
    job.clientRequest,
    job.diagnosis,
    job.workPerformed,
    job.notes,
    bikeBrand,
    bikeModel,
    bikeSerialNumber,
  ].whereType<String>().join(' ').toLowerCase();

  return auditText.contains('[test') ||
      auditText.contains('test perfil') ||
      auditText.contains('test data') ||
      auditText.contains('sandbox') ||
      auditText.contains('dummy');
}

bool isMechanicJobBikeInWorkshop(
  MechanicJob job, {
  String? customerName,
  String? bikeName,
  String? bikeBrand,
  String? bikeModel,
  String? bikeSerialNumber,
}) {
  final bikeId = job.bikeId?.trim();
  if (bikeId == null || bikeId.isEmpty) return false;
  return isMechanicJobIntakeInWorkshop(
    job,
    customerName: customerName,
    bikeName: bikeName,
    bikeBrand: bikeBrand,
    bikeModel: bikeModel,
    bikeSerialNumber: bikeSerialNumber,
  );
}

/// La misma regla que [isMechanicJobBikeInWorkshop] cuando la bici se sabe por
/// `mechanic_job_bikes` y no por `mechanic_jobs.bike_id`.
///
/// En producción (2026-10-02) 15 trabajos no tienen `bike_id` y 50 tienen uno
/// que no está entre sus bicis: los de varias bicis guardan una sola en la
/// cabecera, y otros (de diciembre de 2025 a mayo de 2026) no tienen filas por
/// bici. El directorio de bicicletas une las dos fuentes y juzga el trabajo
/// con esto.
bool isMechanicJobIntakeInWorkshop(
  MechanicJob job, {
  String? customerName,
  String? bikeName,
  String? bikeBrand,
  String? bikeModel,
  String? bikeSerialNumber,
}) {
  if (job.deletedAt != null || !job.isBikeIntake) return false;
  if (job.status == JobStatus.cancelado ||
      job.customStatus?.code.trim().toUpperCase() == 'CANCELADO' ||
      isMechanicJobCurrentlyDelivered(job)) {
    return false;
  }

  return !mechanicJobMatchesTestFixture(
    job,
    customerName: customerName,
    bikeName: bikeName,
    bikeBrand: bikeBrand,
    bikeModel: bikeModel,
    bikeSerialNumber: bikeSerialNumber,
  );
}

bool _startsWithTest(String value) =>
    value == 'test' || value.startsWith('test ');
