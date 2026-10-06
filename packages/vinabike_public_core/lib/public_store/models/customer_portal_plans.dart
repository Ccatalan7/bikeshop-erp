// What each page of the customer portal shows and in what order, decided
// once for the Flutter portal (`lib/public_store/pages/customer_*.dart`) and
// the HTML store's portal (`services/storefront_html`). Moved out of the
// Flutter pages on 2026-10-06; the widgets only lay these out.
import '../../shared/utils/chilean_utils.dart';
import 'customer_portal_presentation.dart';
import 'online_order.dart';

/// Lo que sigue en curso en el resumen: un pedido o un trabajo, con la fecha
/// por la que se ordena (lo más nuevo primero).
class CustomerCurrentItem {
  CustomerCurrentItem.order(OnlineOrder this.order)
    : job = null,
      needsCustomer = CustomerOrderPresentation.of(order).needsCustomer,
      date = order.createdAt;

  CustomerCurrentItem.job(Map<String, dynamic> this.job)
    : order = null,
      needsCustomer = CustomerWorkshopPresentation.of(job).needsCustomer,
      date =
          portalParseDate(job['created_at']) ??
          DateTime.fromMillisecondsSinceEpoch(0);

  final OnlineOrder? order;
  final Map<String, dynamic>? job;
  final bool needsCustomer;
  final DateTime date;
}

/// El resumen de la cuenta (`/cuenta`), de arriba abajo: lo que espera al
/// cliente («Para ti ahora»), lo que sigue en curso, sus bicicletas y los
/// últimos pedidos. Sin baldosas de cifras: un cero no le dice nada a nadie.
class CustomerDashboardPlan {
  CustomerDashboardPlan._({
    required this.firstName,
    required this.forYou,
    required this.inProgress,
    required this.nothingCurrent,
    required this.previousOrders,
  });

  factory CustomerDashboardPlan.of({
    required Map<String, dynamic>? profile,
    required List<OnlineOrder> orders,
    required List<Map<String, dynamic>> jobs,
  }) {
    final current = <CustomerCurrentItem>[
      for (final job in jobs)
        if (CustomerWorkshopPresentation.of(job).isActive)
          CustomerCurrentItem.job(job),
      for (final order in orders)
        if (CustomerOrderPresentation.of(order).group ==
            CustomerOrderGroup.inProgress)
          CustomerCurrentItem.order(order),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return CustomerDashboardPlan._(
      firstName: customerFirstName(profile),
      forYou: [
        for (final item in current)
          if (item.needsCustomer) item,
      ],
      inProgress: [
        for (final item in current)
          if (!item.needsCustomer) item,
      ],
      nothingCurrent: current.isEmpty,
      previousOrders: orders
          .where(
            (order) =>
                CustomerOrderPresentation.of(order).group !=
                CustomerOrderGroup.inProgress,
          )
          .take(3)
          .toList(growable: false),
    );
  }

  /// Sin nombre, el resumen pide completar el perfil.
  final String? firstName;
  final List<CustomerCurrentItem> forYou;
  final List<CustomerCurrentItem> inProgress;

  /// Nada en curso: «No tienes pedidos ni bicis en el taller».
  final bool nothingCurrent;

  /// Los tres últimos pedidos que ya no están en curso.
  final List<OnlineOrder> previousOrders;

  /// «Hola, Ana» o «Tu cuenta».
  String get title => firstName == null ? 'Tu cuenta' : 'Hola, $firstName';
}

/// «Cliente desde septiembre de 2025» y «2 bicicletas · 5 pedidos», para la
/// franja del resumen. Lo que es cero no se dice.
String? customerDashboardBandMeta({
  required Map<String, dynamic>? profile,
  required int bikes,
  required int orders,
}) {
  final since = portalParseDate(profile?['created_at']);
  final counts = [
    if (bikes > 0) bikes == 1 ? '1 bicicleta' : '$bikes bicicletas',
    if (orders > 0) orders == 1 ? '1 pedido' : '$orders pedidos',
  ].join(' · ');
  final lines = [
    if (since != null) 'Cliente desde ${portalMonthYear(since)}',
    if (counts.isNotEmpty) counts,
  ];
  return lines.isEmpty ? null : lines.join('\n');
}

/// Una de las tres cosas de la franja de servicio al pie del resumen.
typedef CustomerServiceBandItem = ({
  String icon,
  String title,
  String message,
  String actionLabel,
  String href,
});

/// La franja de servicio: hablar con el taller, la garantía de las bicis y
/// los datos de contacto y envío. [CustomerServiceBandItem.icon] nombra el
/// ícono de Material (`chat_bubble_outline`…).
List<CustomerServiceBandItem> customerServiceBandItems({
  required Map<String, dynamic>? profile,
  required int addressesCount,
}) {
  final phone = (profile?['phone'] ?? '').toString().trim();
  final contactMessage = phone.isEmpty
      ? 'Agrega tu teléfono para que el taller pueda avisarte cuando tu '
            'bici esté lista.'
      : addressesCount == 0
      ? 'Guarda una dirección y no tendrás que escribirla en cada '
            'compra.'
      : 'Mantén al día tu teléfono y dónde recibes tus pedidos.';
  return [
    (
      icon: 'chat_bubble_outline',
      title: 'Habla con el taller',
      message:
          'Pregunta por tu bici o tu pedido y te responde una '
          'persona del taller.',
      actionLabel: 'Ir a soporte',
      href: '/cuenta/chats',
    ),
    (
      icon: 'verified_user_outlined',
      title: 'Garantía de tus bicis',
      message: 'Revisa hasta cuándo cubre la garantía de cada bicicleta.',
      actionLabel: 'Ver bicicletas',
      href: '/cuenta/bicicletas',
    ),
    (
      icon: 'location_on_outlined',
      title: 'Tus datos y direcciones',
      message: contactMessage,
      actionLabel: phone.isEmpty ? 'Agregar teléfono' : 'Ir a perfil',
      href: phone.isEmpty || addressesCount > 0
          ? '/cuenta/perfil'
          : '/cuenta/direcciones',
    ),
  ];
}

/// La frase de un trabajo en grande: el presupuesto cuando espera la
/// aprobación del cliente, lo que pidió en los demás casos.
String? customerJobMessage(Map<String, dynamic> job) {
  final request = CustomerWorkshopPresentation.requestSummary(job);
  final amount = CustomerWorkshopPresentation.total(job);
  final presentation = CustomerWorkshopPresentation.of(job);
  final code = (job['status'] ?? '').toString().trim().toUpperCase();
  if (code == 'ESPERANDO_APROBACION' &&
      presentation.needsCustomer &&
      amount != null) {
    final total = ChileanUtils.formatCurrency(amount);
    if (request.isEmpty) return 'Presupuesto de $total.';
    final lower = request[0].toLowerCase() + request.substring(1);
    return 'Presupuesto de $total por $lower.';
  }
  if (presentation.needsCustomer && amount != null && request.isEmpty) {
    return 'Total ${ChileanUtils.formatCurrency(amount)}.';
  }
  return request.isEmpty ? null : request;
}

/// Un trabajo que espera que el cliente apruebe el presupuesto: su ficha
/// grande lleva primero «Responder al taller».
bool customerJobAwaitsApproval(Map<String, dynamic> job) =>
    CustomerWorkshopPresentation.of(job).needsCustomer &&
    (job['status'] ?? '').toString().toUpperCase() == 'ESPERANDO_APROBACION';

/// «Pedidos» (`/cuenta/pedidos`): las pestañas agrupan por lo que pasó con
/// el pedido ([CustomerOrderPresentation]), no por el campo de pago. Una
/// pestaña sin pedidos no se ofrece, y pedirla muestra todos.
class CustomerOrdersPlan {
  CustomerOrdersPlan._(this.counts, this.group, this.visible);

  factory CustomerOrdersPlan.of(
    List<OnlineOrder> orders, {
    CustomerOrderGroup? group,
  }) {
    final counts = <CustomerOrderGroup, int>{};
    for (final order in orders) {
      final g = CustomerOrderPresentation.of(order).group;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final effective = group != null && (counts[group] ?? 0) > 0 ? group : null;
    return CustomerOrdersPlan._(
      counts,
      effective,
      effective == null
          ? orders
          : orders
                .where(
                  (order) =>
                      CustomerOrderPresentation.of(order).group == effective,
                )
                .toList(growable: false),
    );
  }

  static const labels = {
    CustomerOrderGroup.inProgress: 'En curso',
    CustomerOrderGroup.delivered: 'Entregados',
    CustomerOrderGroup.cancelled: 'Cancelados',
  };

  final Map<CustomerOrderGroup, int> counts;

  /// La pestaña elegida, `null` en «Todos».
  final CustomerOrderGroup? group;
  final List<OnlineOrder> visible;

  /// Las pestañas que se ofrecen después de «Todos», en orden.
  List<CustomerOrderGroup> get groups => [
    for (final g in labels.keys)
      if ((counts[g] ?? 0) > 0) g,
  ];
}

/// «Taller» (`/cuenta/servicios`): el filtro es por bici y sólo aparece si
/// hay más de una (o si llegó una por `?bike_id=`); lo que está en el taller
/// va arriba (lo que espera al cliente primero) y el historial abajo.
class CustomerServiceHistoryPlan {
  CustomerServiceHistoryPlan._({
    required this.bikes,
    required this.counts,
    required this.filterId,
    required this.visible,
    required this.active,
    required this.history,
  });

  factory CustomerServiceHistoryPlan.of(
    List<Map<String, dynamic>> jobs, {
    String? bikeId,
  }) {
    // Las bicis salen de los trabajos: así el filtro sólo ofrece bicis con
    // algo que mostrar.
    final bikes = <String, String>{};
    final counts = <String, int>{};
    for (final job in jobs) {
      final id = job['bike_id']?.toString();
      if (id == null || id.isEmpty) continue;
      bikes.putIfAbsent(id, () => CustomerWorkshopPresentation.bikeTitle(job));
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final filterId = bikeId != null && bikeId.isNotEmpty ? bikeId : null;
    final visible = filterId == null
        ? jobs
        : jobs
              .where((job) => job['bike_id']?.toString() == filterId)
              .toList(growable: false);
    final active = [
      for (final job in visible)
        if (CustomerWorkshopPresentation.of(job).isActive) job,
    ];
    // Estable: los que esperan al cliente primero, el resto en su orden.
    final waiting = [
      for (final job in active)
        if (CustomerWorkshopPresentation.of(job).needsCustomer) job,
    ];
    return CustomerServiceHistoryPlan._(
      bikes: bikes,
      counts: counts,
      filterId: filterId,
      visible: visible,
      active: [
        ...waiting,
        for (final job in active)
          if (!CustomerWorkshopPresentation.of(job).needsCustomer) job,
      ],
      history: [
        for (final job in visible)
          if (!CustomerWorkshopPresentation.of(job).isActive) job,
      ],
    );
  }

  /// Id y nombre de cada bici con trabajos, en el orden en que aparecen.
  final Map<String, String> bikes;
  final Map<String, int> counts;
  final String? filterId;
  final List<Map<String, dynamic>> visible;
  final List<Map<String, dynamic>> active;
  final List<Map<String, dynamic>> history;

  bool get showsFilter =>
      bikes.length > 1 || (filterId != null && bikes.isNotEmpty);

  /// Cuántos de los que están en el taller esperan al cliente.
  int get waitingCount => active
      .where((job) => CustomerWorkshopPresentation.of(job).needsCustomer)
      .length;
}

/// La garantía de una bici: hasta cuándo y si sigue vigente hoy, en la hora
/// del cliente.
({DateTime until, bool active})? customerBikeWarranty(
  Map<String, dynamic> bike, {
  DateTime? now,
}) {
  final warranty = portalParseDate(bike['warranty_until']);
  if (warranty == null) return null;
  final today = portalLocalTime(now ?? DateTime.now().toUtc());
  final day = portalLocalTime(warranty);
  final active = !DateTime(
    day.year,
    day.month,
    day.day,
  ).isBefore(DateTime(today.year, today.month, today.day));
  return (until: warranty, active: active);
}

/// «Tus bicicletas» en el resumen, en ancho: hasta dos bicis y la foto del
/// taller, o tres bicis si tiene más.
({List<Map<String, dynamic>> shown, bool showWorkshop}) customerDashboardBikes(
  List<Map<String, dynamic>> bikes,
) {
  final showWorkshop = bikes.length <= 2;
  return (
    shown: bikes.take(showWorkshop ? 2 : 3).toList(growable: false),
    showWorkshop: showWorkshop,
  );
}
