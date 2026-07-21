import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/mechanic_job_visibility_policy.dart';

void main() {
  MechanicJob bikeJob({
    JobStatus status = JobStatus.pendiente,
    JobStatusCustom? customStatus,
    String customerId = 'customer-1',
    String? bikeId = 'bike-1',
  }) {
    return MechanicJob(
      id: 'job-1',
      tenantId: 'tenant-1',
      customerId: customerId,
      bikeId: bikeId,
      status: status,
      customStatus: customStatus,
    );
  }

  test('completed bicycle remains in workshop until delivery', () {
    expect(
      isMechanicJobBikeInWorkshop(bikeJob(status: JobStatus.finalizado)),
      isTrue,
    );
    expect(
      isMechanicJobBikeInWorkshop(bikeJob(status: JobStatus.entregado)),
      isFalse,
    );
    expect(
      isMechanicJobBikeInWorkshop(bikeJob(status: JobStatus.cancelado)),
      isFalse,
    );
  });

  test('custom delivery status removes bicycle from workshop', () {
    final deliveredStatus = JobStatusCustom(
      tenantId: 'tenant-1',
      name: 'Retirada',
      code: 'retirada',
      triggersDelivery: true,
    );

    expect(
      isMechanicJobBikeInWorkshop(
        bikeJob(customStatus: deliveredStatus),
      ),
      isFalse,
    );
  });

  test('test fixtures never count as customer bicycles in workshop', () {
    final job = bikeJob();

    expect(
      isMechanicJobBikeInWorkshop(job, bikeName: 'Test 1'),
      isFalse,
    );
    expect(
      isMechanicJobBikeInWorkshop(job, customerName: 'Test Taller'),
      isFalse,
    );
    expect(
      isMechanicJobBikeInWorkshop(
        job.copyWith(notes: '[test fixture:drivetrain]'),
      ),
      isFalse,
    );
  });

  test('non-bike work never becomes a workshop bicycle', () {
    expect(
      isMechanicJobBikeInWorkshop(bikeJob(bikeId: null)),
      isFalse,
    );
  });
}
