import '../../../shared/services/tenant_service.dart';
import '../models/sales_models.dart';

/// Client-side explanation of the server-owned payment correction policy.
/// This never replaces database authorization; it keeps the form honest before
/// the command performs its authoritative source, role and concurrency checks.
class SalesPaymentEditPolicy {
  const SalesPaymentEditPolicy._();

  static const Set<String> sourceManagedInvoiceSources = {
    'pos',
    'quick_sale',
    'ecommerce',
    'online_order',
    'online_orders',
    'mercado_pago',
    'webpay',
  };

  static bool isSourceManaged(Invoice invoice) {
    return sourceManagedInvoiceSources.contains(
      invoice.source?.trim().toLowerCase(),
    );
  }

  static bool canEditFinancialFields(
    Invoice invoice,
    TenantService tenantService,
  ) {
    if (isSourceManaged(invoice)) return false;
    return tenantService.hasAnyRole(
          const ['admin', 'manager', 'accountant'],
        ) ||
        tenantService.hasPermission('access_accounting');
  }

  static bool canEditReference(Invoice invoice) => !isSourceManaged(invoice);

  static String sourceLabel(Invoice invoice) {
    switch (invoice.source?.trim().toLowerCase()) {
      case 'pos':
        return 'Punto de venta';
      case 'quick_sale':
        return 'Venta rápida';
      case 'ecommerce':
      case 'online_order':
      case 'online_orders':
        return 'Tienda en línea';
      case 'mercado_pago':
        return 'Mercado Pago';
      case 'webpay':
        return 'Webpay';
      case 'mechanic_job':
        return 'Taller';
      case 'manual_sale':
        return 'Venta manual';
      default:
        return 'Registro histórico';
    }
  }

  static String lockedMessage(Invoice invoice) {
    if (isSourceManaged(invoice)) {
      return 'Los datos financieros pertenecen a ${sourceLabel(invoice)}. '
          'Corrige el cobro en su flujo de origen; aquí solo puedes agregar '
          'notas sin alterar la contabilidad.';
    }
    return 'Tu rol puede consultar este pago, pero no modificar importe, '
        'fecha ni método. Un responsable contable debe realizar la corrección.';
  }
}
