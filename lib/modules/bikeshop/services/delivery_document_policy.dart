import '../../crm/models/crm_models.dart';
import '../models/bikeshop_models.dart';

/// Dónde se ofrece el comprobante de entrega y el QR de la cuenta: la misma
/// regla para la tabla de trabajos y la ficha del trabajo.
abstract final class DeliveryDocumentPolicy {
  /// El trabajo ya tuvo su primera entrega de taller: hay (o se puede armar)
  /// un comprobante. Sólo la venta no abre garantía, igual que en la base
  /// (`capture_mechanic_job_delivery_event`): un trabajo con «Presupuestar
  /// primero» es la bici de siempre todavía sin facturar, y la mayoría se
  /// entrega así. Un trabajo reabierto después de entregarse conserva el suyo.
  static bool offersDeliveryDocument(MechanicJob job) {
    if (job.id == null || job.deletedAt != null) return false;
    if (job.isSaleWorkflow) return false;
    return job.status == JobStatus.entregado ||
        job.customStatus?.triggersDelivery == true ||
        job.deliveredAt != null ||
        job.serviceWarranty?.firstDeliveredAt != null;
  }

  /// El cliente del trabajo todavía no tiene cuenta en el portal: se le
  /// puede mostrar el QR para crearla.
  static bool offersAccountQr(MechanicJob job, Customer? customer) {
    if (job.id == null || job.deletedAt != null) return false;
    if (job.status == JobStatus.cancelado) return false;
    if (customer == null || customer.id == null) return false;
    return (customer.authUserId ?? '').trim().isEmpty;
  }
}
