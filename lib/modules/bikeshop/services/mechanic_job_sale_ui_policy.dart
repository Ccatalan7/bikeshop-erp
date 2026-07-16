import '../../sales/models/sales_models.dart';
import '../models/bikeshop_models.dart';

bool isMechanicJobSaleFullyPaid(MechanicJob job, Invoice? invoice) {
  if (!job.isSaleWorkflow) return false;
  if (invoice == null) return job.isPaid;
  if (invoice.status == InvoiceStatus.paid) return true;
  if (invoice.status == InvoiceStatus.cancelled) return false;
  final effectiveTotal = invoice.total > 0 ? invoice.total : job.totalCost;
  return effectiveTotal > 0.01 && invoice.paidAmount >= effectiveTotal - 0.01;
}

bool isMechanicJobSaleActive(MechanicJob job, Invoice? invoice) {
  return job.isSaleWorkflow &&
      job.status != JobStatus.cancelado &&
      !isMechanicJobSaleFullyPaid(job, invoice);
}

String mechanicJobSalePaymentLabel(MechanicJob job, Invoice? invoice) {
  if (isMechanicJobSaleFullyPaid(job, invoice)) return 'Pagado';
  if ((invoice?.paidAmount ?? 0) > 0.01) return 'Abono parcial';
  return 'Cobro pendiente';
}
