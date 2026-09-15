import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/mechanic_job_visibility_policy.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';

void main() {
  MechanicJob bikeJob({
    JobStatus status = JobStatus.pendiente,
    JobStatusCustom? customStatus,
    String customerId = 'customer-1',
    String? bikeId = 'bike-1',
    JobType jobType = JobType.service,
    JobWorkflowKind? workflowKind,
    QuotationStatus? quotationStatus,
    DateTime? quotationValidUntil,
    String? invoiceId,
    bool isInvoiced = false,
    bool isPaid = false,
    bool isWarrantyJob = false,
    double totalCost = 0,
    DateTime? deletedAt,
    String? clientRequest,
  }) {
    return MechanicJob(
      id: 'job-1',
      tenantId: 'tenant-1',
      customerId: customerId,
      bikeId: bikeId,
      jobType: jobType,
      workflowKind: workflowKind,
      status: status,
      customStatus: customStatus,
      quotationStatus: quotationStatus,
      quotationValidUntil: quotationValidUntil,
      invoiceId: invoiceId,
      isInvoiced: isInvoiced,
      isPaid: isPaid,
      isWarrantyJob: isWarrantyJob,
      totalCost: totalCost,
      deletedAt: deletedAt,
      clientRequest: clientRequest,
    );
  }

  Invoice invoice({
    InvoiceStatus status = InvoiceStatus.confirmed,
    double total = 10000,
    double paidAmount = 0,
  }) {
    return Invoice(
      id: 'invoice-1',
      tenantId: 'tenant-1',
      invoiceNumber: 'FV-1',
      date: DateTime.utc(2026, 8, 27),
      status: status,
      total: total,
      paidAmount: paidAmount,
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

  test('selector activo conserva trabajos en curso y finalizados sin entregar',
      () {
    expect(isMechanicJobOperationallyActive(bikeJob()), isTrue);
    expect(
      isMechanicJobOperationallyActive(
        bikeJob(status: JobStatus.finalizado, isPaid: true),
      ),
      isTrue,
    );
  });

  test('selector activo excluye cancelados, archivados y fixtures de prueba',
      () {
    expect(
      isMechanicJobOperationallyActive(
        bikeJob(status: JobStatus.cancelado),
      ),
      isFalse,
    );
    expect(
      isMechanicJobOperationallyActive(
        bikeJob(deletedAt: DateTime.utc(2026, 8, 27)),
      ),
      isFalse,
    );
    expect(
      isMechanicJobOperationallyActive(
        bikeJob(clientRequest: '[test fixture:tasks]'),
      ),
      isFalse,
    );
  });

  test('selector activo excluye entregados pagados pero conserva impagos', () {
    final delivered = bikeJob(
      status: JobStatus.entregado,
      invoiceId: 'invoice-1',
      isInvoiced: true,
      totalCost: 10000,
    );
    expect(
      isMechanicJobOperationallyActive(delivered, invoice: invoice()),
      isTrue,
    );
    expect(
      isMechanicJobOperationallyActive(
        delivered.copyWith(isPaid: true),
        invoice: invoice(),
      ),
      isTrue,
      reason: 'la factura vinculada es la autoridad cuando existe',
    );
    expect(
      isMechanicJobOperationallyActive(
        delivered,
        invoice: invoice(status: InvoiceStatus.paid, paidAmount: 10000),
      ),
      isFalse,
    );
  });

  test('selector activo excluye cotizaciones cerradas y ventas pagadas', () {
    expect(
      isMechanicJobOperationallyActive(
        bikeJob(
          jobType: JobType.quotation,
          workflowKind: JobWorkflowKind.quotation,
          bikeId: null,
          quotationStatus: QuotationStatus.rejected,
        ),
      ),
      isFalse,
    );
    expect(
      isMechanicJobOperationallyActive(
        bikeJob(
          jobType: JobType.sale,
          workflowKind: JobWorkflowKind.sale,
          invoiceId: 'invoice-1',
          totalCost: 10000,
        ),
        invoice: invoice(paidAmount: 10000),
      ),
      isFalse,
    );
  });
}
