import '../../modules/website/models/website_models.dart';
import 'order_confirmation_policy.dart';

/// Tono de un estado en el portal de clientes. El color lo pone el estilo del
/// portal; aquí sólo se decide qué significa.
enum PortalTone { neutral, info, success, warning, danger }

/// En qué pestaña de «Pedidos» cae un pedido.
enum CustomerOrderGroup { inProgress, delivered, cancelled }

/// Cómo ve el cliente un pedido: una sola etiqueta, derivada de lo que pasó
/// con él, no del campo de pago solo.
///
/// La precedencia de pago es la de [OrderConfirmationPolicy] (la misma que
/// muestra `/pedido/:id`): una cancelación manda sobre un pago «pendiente»
/// que quedó viejo. Encima de eso, los estados de entrega (listo para
/// retirar, enviado, entregado) dicen dónde está el pedido una vez pagado.
class CustomerOrderPresentation {
  const CustomerOrderPresentation._({
    required this.label,
    required this.tone,
    required this.group,
    required this.needsCustomer,
    this.nextStep,
  });

  factory CustomerOrderPresentation.of(OnlineOrder order) {
    final state = OrderConfirmationPolicy.resolve(order);
    final status = order.status.trim().toLowerCase();

    if (state == OrderConfirmationState.cancelled) {
      return const CustomerOrderPresentation._(
        label: 'Cancelado',
        tone: PortalTone.neutral,
        group: CustomerOrderGroup.cancelled,
        needsCustomer: false,
      );
    }
    if (status == 'delivered') {
      return const CustomerOrderPresentation._(
        label: 'Entregado',
        tone: PortalTone.success,
        group: CustomerOrderGroup.delivered,
        needsCustomer: false,
      );
    }
    if (status == 'ready_for_pickup') {
      return const CustomerOrderPresentation._(
        label: 'Listo para retirar',
        tone: PortalTone.success,
        group: CustomerOrderGroup.inProgress,
        needsCustomer: true,
        nextStep: 'Pasa a buscarlo a la tienda',
      );
    }
    if (status == 'shipped') {
      return const CustomerOrderPresentation._(
        label: 'En camino',
        tone: PortalTone.info,
        group: CustomerOrderGroup.inProgress,
        needsCustomer: false,
      );
    }
    return switch (state) {
      OrderConfirmationState.failed => const CustomerOrderPresentation._(
          label: 'Pago rechazado',
          tone: PortalTone.danger,
          group: CustomerOrderGroup.inProgress,
          needsCustomer: true,
          nextStep: 'Puedes intentar pagar de nuevo',
        ),
      OrderConfirmationState.transferPending =>
        const CustomerOrderPresentation._(
          label: 'Esperando transferencia',
          tone: PortalTone.warning,
          group: CustomerOrderGroup.inProgress,
          needsCustomer: true,
          nextStep: 'Transfiere para que preparemos tu pedido',
        ),
      OrderConfirmationState.pending => const CustomerOrderPresentation._(
          label: 'Pago en proceso',
          tone: PortalTone.warning,
          group: CustomerOrderGroup.inProgress,
          needsCustomer: false,
        ),
      OrderConfirmationState.paid => const CustomerOrderPresentation._(
          label: 'En preparación',
          tone: PortalTone.info,
          group: CustomerOrderGroup.inProgress,
          needsCustomer: false,
        ),
      _ => const CustomerOrderPresentation._(
          label: 'Recibido',
          tone: PortalTone.info,
          group: CustomerOrderGroup.inProgress,
          needsCustomer: false,
        ),
    };
  }

  final String label;
  final PortalTone tone;
  final CustomerOrderGroup group;

  /// El cliente tiene algo que hacer: pagar, reintentar o ir a retirar.
  final bool needsCustomer;

  /// Qué hacer, en una frase, cuando [needsCustomer].
  final String? nextStep;

  /// «Aceite mineral Shimano» o «Aceite mineral Shimano y 2 más».
  static String itemsSummary(OnlineOrder order) {
    final names = order.items
        .map((item) => item.productName.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) return 'Sin detalle de productos';
    if (names.length == 1) return names.first;
    return '${names.first} y ${names.length - 1} más';
  }
}

/// Cómo ve el cliente un trabajo de taller.
///
/// Los nombres de `job_statuses` son del taller («REPUESTOS», «COMENZAR»,
/// «Desglosar»), no del cliente, y el cliente no puede leer esa tabla. Cada
/// código conocido tiene aquí su frase; un código nuevo que agregue el taller
/// se muestra como «En el taller», activo, hasta que se le dé una.
class CustomerWorkshopPresentation {
  const CustomerWorkshopPresentation._({
    required this.label,
    required this.tone,
    required this.isActive,
    required this.needsCustomer,
    this.nextStep,
  });

  factory CustomerWorkshopPresentation.of(Map<String, dynamic> job) {
    final code = (job['status'] ?? '').toString().trim().toUpperCase();
    switch (code) {
      case 'ENTREGADO':
        return const CustomerWorkshopPresentation._(
          label: 'Entregada',
          tone: PortalTone.success,
          isActive: false,
          needsCustomer: false,
        );
      case 'RETIRO_SIN_SERVICIO':
        return const CustomerWorkshopPresentation._(
          label: 'Retirada sin servicio',
          tone: PortalTone.neutral,
          isActive: false,
          needsCustomer: false,
        );
      case 'CANCELADO':
        return const CustomerWorkshopPresentation._(
          label: 'Cancelado',
          tone: PortalTone.neutral,
          isActive: false,
          needsCustomer: false,
        );
      case 'FINALIZADO':
      case 'PROBADO':
        return const CustomerWorkshopPresentation._(
          label: 'Lista para retirar',
          tone: PortalTone.success,
          isActive: true,
          needsCustomer: true,
          nextStep: 'Pasa a buscarla al taller',
        );
      case 'ESPERANDO_APROBACION':
        final approved = job['approved_by_customer'] == true;
        return CustomerWorkshopPresentation._(
          label: approved ? 'Presupuesto aprobado' : 'Espera tu aprobación',
          tone: approved ? PortalTone.info : PortalTone.warning,
          isActive: true,
          needsCustomer: !approved,
          nextStep: approved ? null : 'Revisa el presupuesto y apruébalo',
        );
      case 'PRESUPUESTO':
        return const CustomerWorkshopPresentation._(
          label: 'Preparando presupuesto',
          tone: PortalTone.info,
          isActive: true,
          needsCustomer: false,
        );
      case 'PENDIENTE':
        return const CustomerWorkshopPresentation._(
          label: 'Recibida en el taller',
          tone: PortalTone.info,
          isActive: true,
          needsCustomer: false,
        );
      case 'CONTACTAR':
        return const CustomerWorkshopPresentation._(
          label: 'Te vamos a contactar',
          tone: PortalTone.info,
          isActive: true,
          needsCustomer: false,
        );
      case 'DIAGNOSTICO':
        return const CustomerWorkshopPresentation._(
          label: 'En diagnóstico',
          tone: PortalTone.info,
          isActive: true,
          needsCustomer: false,
        );
      case 'ESPERANDO_REPUESTOS':
        return const CustomerWorkshopPresentation._(
          label: 'Esperando repuestos',
          tone: PortalTone.warning,
          isActive: true,
          needsCustomer: false,
        );
      case 'EN_PAUSA':
        return const CustomerWorkshopPresentation._(
          label: 'En pausa',
          tone: PortalTone.warning,
          isActive: true,
          needsCustomer: false,
        );
      case 'GARANTA':
      case 'GARANTIA':
        return const CustomerWorkshopPresentation._(
          label: 'En garantía',
          tone: PortalTone.info,
          isActive: true,
          needsCustomer: false,
        );
      case 'COMENZAR':
      case 'EN_CURSO':
      case 'DESGLOSAR':
        return const CustomerWorkshopPresentation._(
          label: 'En reparación',
          tone: PortalTone.info,
          isActive: true,
          needsCustomer: false,
        );
      default:
        return const CustomerWorkshopPresentation._(
          label: 'En el taller',
          tone: PortalTone.info,
          isActive: true,
          needsCustomer: false,
        );
    }
  }

  final String label;
  final PortalTone tone;

  /// La bici sigue en el taller (o lista para retirar).
  final bool isActive;

  /// El cliente tiene algo que hacer: aprobar un presupuesto o ir a retirar.
  final bool needsCustomer;

  /// Qué hacer, en una frase, cuando [needsCustomer].
  final String? nextStep;

  /// «Specialized Rockhopper», o «Bicicleta» si el taller no anotó marca ni
  /// modelo.
  static String bikeTitle(Map<String, dynamic> data) {
    final brand =
        (data['bike_brand'] ?? data['brand_name'] ?? data['brand'] ?? '')
            .toString()
            .trim();
    final model =
        (data['bike_model'] ?? data['model_name'] ?? data['model'] ?? '')
            .toString()
            .trim();
    final title = '$brand $model'.trim();
    return title.isEmpty ? 'Bicicleta' : title;
  }
}

/// El nombre con que el portal saluda, o `null` si la cuenta no tiene uno
/// real. «Usuario» y «Cliente» son relleno que quedó guardado en algunas
/// cuentas, y la parte local del correo no es un nombre: en esos casos el
/// portal pide el nombre en vez de saludar a «Usuario».
String? customerFirstName(Map<String, dynamic>? profile) {
  final name = (profile?['name'] ?? '').toString().trim();
  if (name.isEmpty) return null;
  final lower = name.toLowerCase();
  if (lower == 'usuario' || lower == 'cliente') return null;
  final email = (profile?['email'] ?? '').toString().trim().toLowerCase();
  final at = email.indexOf('@');
  if (at > 0 && lower == email.substring(0, at)) return null;
  return name.split(RegExp(r'\s+')).first;
}

const _shortMonths = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

const _longMonths = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// «19 jul 2026», en la hora local del cliente. Sin depender de que el
/// formato de fechas en español esté cargado en la tienda.
String portalDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day} ${_shortMonths[local.month - 1]} ${local.year}';
}

/// «septiembre de 2025».
String portalMonthYear(DateTime date) {
  final local = date.toLocal();
  return '${_longMonths[local.month - 1]} de ${local.year}';
}

/// Lee una fecha de una fila de Supabase (`String` ISO o `DateTime`).
DateTime? portalParseDate(Object? value) {
  if (value is DateTime) return value;
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
