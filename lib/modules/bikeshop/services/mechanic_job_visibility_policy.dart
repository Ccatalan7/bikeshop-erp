import '../models/bikeshop_models.dart';

bool isMechanicJobCurrentlyDelivered(MechanicJob job) {
  return job.status == JobStatus.entregado ||
      job.customStatus?.triggersDelivery == true ||
      job.customStatus?.code.trim().toLowerCase() == 'entregado';
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
