import '../../modules/bikeshop/models/bikeshop_models.dart';
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

  /// Lo que el cliente pidió, en una línea. El taller lo anota en
  /// `client_request` como lista («+Enrayado rueda delantera.\n+Mantención
  /// maza trasera.»); `mechanic_jobs` no tiene `description`, que es lo que
  /// el portal leía antes y nunca mostraba nada.
  static String requestSummary(Map<String, dynamic> job) {
    final raw = (job['client_request'] ?? '').toString();
    return raw
        .split(RegExp(r'[\n\r]+|(?:^|\s)\+'))
        .map((part) => part.trim().replaceAll(RegExp(r'^[+\-•·]+\s*'), ''))
        .map((part) => part.replaceAll(RegExp(r'\.$'), '').trim())
        .where((part) => part.isNotEmpty)
        .map(_sentenceCaseIfShouting)
        .join(' · ');
  }

  /// «DIAGNÓSTICO» → «Diagnóstico»: el taller a veces escribe en mayúsculas.
  static String _sentenceCaseIfShouting(String part) {
    final letters = part.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÑÜáéíóúñü]'), '');
    if (letters.length < 4 || letters != letters.toUpperCase()) return part;
    final lower = part.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  /// El total del trabajo, o `null` si todavía no tiene precio.
  static double? total(Map<String, dynamic> job) {
    for (final key in const ['total_cost', 'final_cost', 'estimated_cost']) {
      final value = job[key];
      final amount =
          value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
      if (amount != null && amount > 0) return amount;
    }
    return null;
  }

  /// Cuándo entró la bici: `arrival_date` está en todos los trabajos;
  /// `completed_at` y `delivered_at` no son confiables.
  static DateTime? receivedAt(Map<String, dynamic> job) =>
      portalParseDate(job['arrival_date']) ??
      portalParseDate(job['created_at']);
}

/// Detalle de una bici en palabras del cliente: tipo, color y aro.
///
/// El tipo usa las mismas palabras que el ERP ([BikeType.displayName]). Que
/// el formulario del ERP parta en `mountain_hardtail` es intencional: la
/// mayoría de las bicis que llegan al taller son MTB rígidas (el dueño,
/// 2026-09-25). «Otra» no dice nada y no se muestra.
String customerBikeDetails(Map<String, dynamic> bike) {
  final color = (bike['color'] ?? bike['bike_color'] ?? '').toString().trim();
  final type = BikeType.fromDbValue(
    (bike['bike_type'] ?? '').toString().trim(),
  );
  return [
    if (type != null && type != BikeType.other) type.displayName,
    if (color.isNotEmpty) color[0].toUpperCase() + color.substring(1),
    if (customerWheelSize(bike['wheel_size']) case final wheel?) 'aro $wheel',
    if (bike['year'] case final num year) '${year.toInt()}',
  ].join(' · ');
}

/// «3 servicios · último 12 sep 2026». `service_count` y
/// `last_service_date` los arma `CustomerAccountService.loadBikes` con la
/// fecha de ingreso del último trabajo.
String customerBikeServiceSummary(Map<String, dynamic> bike) {
  final count = (bike['service_count'] as num?)?.toInt() ?? 0;
  final last = portalParseDate(bike['last_service_date']);
  final services = switch (count) {
    0 => 'Sin servicios todavía',
    1 => '1 servicio',
    _ => '$count servicios',
  };
  return last == null ? services : '$services · último ${portalDate(last)}';
}

/// La foto de la bici, si el taller le sacó una.
String? customerBikeImage(Map<String, dynamic> bike) {
  final single = (bike['image_url'] ?? '').toString().trim();
  if (single.isNotEmpty) return single;
  for (final url in (bike['image_urls'] as List? ?? const [])) {
    final value = (url ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// «29», «27.5», «700c». El taller lo escribe de mil maneras: `29"`, `29''`,
/// `29`, `700`.
String? customerWheelSize(Object? raw) {
  var value = (raw ?? '').toString().trim().replaceAll(RegExp("[\"'”″]"), '');
  value = value.replaceAll(',', '.').trim();
  if (value.isEmpty) return null;
  if (value == '700') return '700c';
  return value;
}

/// Cómo ve el cliente una conversación con la tienda.
class CustomerConversationPresentation {
  const CustomerConversationPresentation._({
    required this.title,
    required this.preview,
    required this.lastActivity,
    this.statusLabel,
    this.tone = PortalTone.neutral,
  });

  factory CustomerConversationPresentation.of(
    Map<String, dynamic> conversation, {
    String? currentUserId,
  }) {
    final rawTitle = (conversation['title'] ?? '').toString().trim();
    final title = rawTitle
        .replaceFirst(RegExp(r'^chat:\s*', caseSensitive: false), '')
        .trim();

    final messages = [
      for (final message in (conversation['messages'] as List? ?? const []))
        if (message is Map) Map<String, dynamic>.from(message),
    ]..sort((a, b) => (portalParseDate(a['created_at']) ?? DateTime(0))
        .compareTo(portalParseDate(b['created_at']) ?? DateTime(0)));
    final last = messages.isEmpty ? null : messages.last;
    final content = (last?['content'] ?? '')
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final mine = currentUserId != null && last?['sender_id'] == currentUserId;

    final (label, tone) =
        switch ((conversation['status'] ?? '').toString().toLowerCase()) {
      'pending' => ('Esperando al equipo', PortalTone.warning),
      'rejected' => ('Cerrada', PortalTone.neutral),
      'resolved' || 'closed' || 'archived' => ('Archivada', PortalTone.neutral),
      _ => (null, PortalTone.neutral),
    };

    return CustomerConversationPresentation._(
      title: title.isEmpty ? 'Consulta' : title,
      preview: content.isEmpty
          ? null
          : mine
              ? 'Tú: $content'
              : content,
      lastActivity: portalParseDate(conversation['last_message_at']) ??
          portalParseDate(last?['created_at']) ??
          portalParseDate(conversation['created_at']),
      statusLabel: label,
      tone: tone,
    );
  }

  /// «Factura #FV-00573», «Trabajo #PG-00305» o «Consulta».
  final String title;

  /// El último mensaje, con «Tú:» si lo escribió el cliente.
  final String? preview;
  final DateTime? lastActivity;

  /// Sólo cuando no está abierta: una conversación activa es lo normal.
  final String? statusLabel;
  final PortalTone tone;
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

/// «hoy», «ayer» o «19 jul 2026»: para la última actividad de un chat.
String portalRelativeDay(DateTime date, {DateTime? now}) {
  final local = date.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final diff = DateTime(today.year, today.month, today.day).difference(day);
  if (diff.inDays == 0) return 'hoy';
  if (diff.inDays == 1) return 'ayer';
  return portalDate(local);
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
