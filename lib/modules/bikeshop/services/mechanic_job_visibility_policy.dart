import '../models/bikeshop_models.dart';
import '../../sales/models/sales_models.dart';
import 'mechanic_job_sale_ui_policy.dart';

bool isMechanicJobCurrentlyDelivered(MechanicJob job) {
  return job.status == JobStatus.entregado ||
      job.customStatus?.triggersDelivery == true ||
      job.customStatus?.code.trim().toLowerCase() == 'entregado';
}

/// Canonical eligibility for every UI that promises "Trabajos activos".
///
/// This deliberately matches the default Activos scope of the Jobs table:
/// completed work remains operational until delivery, and a delivered job
/// remains active while its invoice is still unpaid. Historical, cancelled,
/// closed quotation, paid sale and completed warranty records do not qualify.
bool isMechanicJobOperationallyActive(
  MechanicJob job, {
  Invoice? invoice,
  String? customerName,
  String? bikeName,
  String? bikeBrand,
  String? bikeModel,
  String? bikeSerialNumber,
}) {
  if (job.deletedAt != null) return false;
  if (mechanicJobMatchesTestFixture(
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
  if (bikeId == null || bikeId.isEmpty || !job.isBikeIntake) return false;
  if (job.status == JobStatus.cancelado ||
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
