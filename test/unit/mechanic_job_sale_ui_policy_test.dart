import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/mechanic_job_sale_ui_policy.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';

void main() {
  final job = MechanicJob(
    id: 'job-1',
    tenantId: 'tenant-1',
    customerId: 'customer-1',
    jobType: JobType.sale,
    totalCost: 40000,
  );

  Invoice invoice(
      {double paid = 0, InvoiceStatus status = InvoiceStatus.sent}) {
    return Invoice(
      id: 'invoice-1',
      tenantId: 'tenant-1',
      customerId: 'customer-1',
      invoiceNumber: 'F-1',
      date: DateTime.utc(2026, 7, 16),
      dueDate: DateTime.utc(2026, 8, 16),
      total: 40000,
      paidAmount: paid,
      balance: 40000 - paid,
      status: status,
    );
  }

  test('sale remains active through partial payments', () {
    expect(isMechanicJobSaleActive(job, invoice()), isTrue);
    expect(isMechanicJobSaleActive(job, invoice(paid: 10000)), isTrue);
    expect(mechanicJobSalePaymentLabel(job, invoice(paid: 10000)),
        'Abono parcial');
  });

  test('sale exits active when invoice is fully paid', () {
    expect(isMechanicJobSaleFullyPaid(job, invoice(paid: 40000)), isTrue);
    expect(isMechanicJobSaleActive(job, invoice(paid: 40000)), isFalse);
  });
}
