import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/mechanic_job_sale_classification_coordinator.dart';

void main() {
  const operationKey = '11111111-1111-4111-8111-111111111111';

  MechanicJob saleJob() => MechanicJob(
        id: 'job-1',
        tenantId: 'tenant-1',
        customerId: 'customer-1',
        jobType: JobType.sale,
        workflowKind: JobWorkflowKind.sale,
        intakeKind: JobIntakeKind.none,
        modeNeedsReview: false,
      );

  test('lost acknowledgement reconciles the exact sale invariant', () async {
    final request = MechanicJobSaleClassificationRequest(
      jobId: 'job-1',
      operationKey: operationKey,
      reason: 'Venta confirmada',
    );
    final coordinator = MechanicJobSaleClassificationCoordinator(
      send: (_) async => throw const _NetworkError(),
      readback: (_) async => saleJob(),
      isOutcomeAmbiguous: (error) => error is _NetworkError,
    );

    final result = await coordinator.execute(request);
    expect(
      result.confirmation,
      MechanicJobSaleClassificationConfirmation.reconciledFromReadback,
    );
    expect(result.readbackConfirmed, isTrue);
    expect(request.toRpcParams()['p_operation_key'], operationKey);
  });
}

class _NetworkError implements Exception {
  const _NetworkError();
}
