import 'dart:convert';

/// Qué hace una petición al servidor y si se puede volver a mandar sin riesgo.
///
/// **Por qué existe (2026-11-04).** En el taller «cosas que yo sé que registré
/// no quedan registradas» (el encargado, por WhatsApp al dueño). Los registros
/// del servidor de ese día no tenían ni un error del Mac del taller: lo que
/// falla no llega. La conexión VTR se corta varios minutos en horario de
/// atención (el latido de `get_checked_in_employees`, una vez por minuto,
/// cae a cero), y cada pantalla mandaba su guardado una sola vez, sin tiempo
/// límite: un corte lo dejaba colgado o fallaba cuando la persona ya había
/// salido de la pantalla.
///
/// Reintentar a ciegas tampoco sirve: un alta que sí llegó, pero cuya
/// respuesta se perdió, quedaría dos veces. Por eso cada petición se clasifica
/// por lo que pasaría si se mandara de nuevo:
///
/// - **lectura**: no cambia nada;
/// - **comando con llave**: el servidor guarda un recibo por la llave de
///   operación (`p_operation_key`, `p_idempotency_key`, `p_operation_id`,
///   `p_checkout_key`) y el segundo envío devuelve el mismo resultado;
/// - **cambio repetible**: un `PATCH`, un `DELETE` o un alta con
///   `resolution=merge-duplicates` dejan lo mismo aplicados una o dos veces;
/// - **alta con identidad**: un `POST` a una tabla cuyas filas traen su `id`
///   (o su `idempotency_key`) desde el equipo. En producción toda tabla con
///   columna `id` la tiene como llave primaria (medido el 2026-11-04), así que
///   un segundo envío choca con la primera fila (409) en vez de crear otra;
/// - **alta**: un `POST` sin llave; dos envíos son dos filas;
/// - **sesión** y **función**: el refresco de la sesión rota su llave y una
///   función del borde puede mandar un WhatsApp: sólo se reintentan si la
///   petición nunca salió.
///
/// Lo que sólo se reintenta cuando no salió se decide en el transporte
/// ([TransportFailure.notSent]); acá se decide lo demás.
enum RequestEffect {
  read,
  keyedCommand,
  repeatableWrite,
  identifiedInsert,
  insert,
  auth,
  function,
}

class RequestSafety {
  const RequestSafety({
    required this.effect,
    required this.resourceKey,
    required this.label,
    this.rpcName,
    this.table,
    this.idempotencyKey,
    this.identityColumn,
    this.detail,
    this.durableElsewhere = false,
  });

  final RequestEffect effect;

  /// Método, ruta y consulta: dos envíos con la misma llave tocan lo mismo.
  /// Sirve para que un guardado posterior que sí llegó resuelva el pendiente.
  final String resourceKey;

  /// Cómo se llama esto para la persona: «Pago de venta», «Cliente».
  final String label;

  /// Un dato que reconoce el registro, sacado del cuerpo: el nombre, el monto.
  final String? detail;

  final String? rpcName;
  final String? table;

  /// La llave de operación del cuerpo, si el comando la trae, o la identidad
  /// de la fila en un alta con identidad.
  final String? idempotencyKey;

  /// En un alta con identidad, la columna que la lleva (`id` o
  /// `idempotency_key`): por ella se busca la fila si el reenvío choca.
  final String? identityColumn;

  /// La bandeja del taller y la cola de WhatsApp ya guardan en el equipo lo
  /// suyo y lo reenvían: un fallo de esas peticiones no va a «Sin guardar».
  final bool durableElsewhere;

  /// El nombre técnico (la tabla o el comando), para el detalle chico.
  String get technicalName => rpcName ?? table ?? resourceKey;

  bool get isWrite => effect != RequestEffect.read;

  /// Si no llega, queda en «Sin guardar». No van ahí la sesión (no es un
  /// cambio de nadie), las funciones del borde (un análisis con IA o un
  /// reembolso no se reenvían después sin que la persona lo mire) ni lo que ya
  /// tiene su propia cola en el equipo.
  bool get belongsInJournal =>
      isWrite &&
      !durableElsewhere &&
      effect != RequestEffect.auth &&
      effect != RequestEffect.function;

  /// Mandarla de nuevo no puede aplicar el cambio dos veces.
  bool get replayIsHarmless =>
      effect == RequestEffect.read ||
      effect == RequestEffect.keyedCommand ||
      effect == RequestEffect.repeatableWrite ||
      effect == RequestEffect.identifiedInsert;
}

/// Llaves de operación que los comandos de la base honran: la misma llave
/// deja un solo efecto (medido en producción el 2026-11-04: 80 comandos con
/// `p_operation_key`, 32 con `p_idempotency_key`, 11 con `p_operation_id` y la
/// venta del mesón con `p_checkout_key`). `p_key` no cuenta: es el nombre de un
/// ajuste.
const Set<String> requestIdempotencyKeyParams = {
  'p_operation_key',
  'p_idempotency_key',
  'p_operation_id',
  'p_checkout_key',
};

/// Prefijos de las funciones que sólo leen. Una función que escribe no se
/// llama así; las que lo hacen, pese al nombre, van en
/// [_writesDespiteReadName].
const List<String> _readPrefixes = [
  'get_',
  'list_',
  'search_',
  'inbox_',
  'preview_',
  'count_',
  'find_',
  'lookup_',
  'read_',
  'check_',
  'fetch_',
  'explain_',
  'describe_',
  'suggest_',
  'compute_',
  'calculate_',
  'estimate_',
];

/// Lecturas cuyo nombre no empieza con un prefijo de lectura.
const Set<String> _readsWithoutReadName = {
  'customer_quote_inbox_v1',
  'supplier_brands_v1',
  'brand_suppliers_v1',
  'supplier_brand_index_v1',
  'supplier_catalog_page_v1',
  'customer_quote_sold_out_summary_v1',
};

/// Funciones con nombre de lectura que hacen algo (volátiles en producción el
/// 2026-11-04): consumen un folio, dejan un registro de acceso o calculan y
/// guardan. Se tratan como altas: sin llave, no se reintentan si salieron.
const Set<String> _writesDespiteReadName = {
  'get_next_document_number',
  'get_supplier_credential_v2',
  'calculate_payroll',
};

/// Comandos que ya tienen su propia cola durable en el equipo.
const Set<String> _durableElsewhereRpcs = {
  // WorkshopCommandOutbox (lib/modules/bikeshop/services/workshop_command_outbox.dart)
  'save_bike_aggregate',
  'save_mechanic_job_lines_v1',
  'transition_mechanic_job_status',
  'create_mechanic_job_v1',
  'record_workshop_command_attempts_v1',
  // La cola de mensajes de WhatsApp (whatsapp_service.dart, clientMessageId).
  'enqueue_whatsapp_message_v1',
};

const Map<String, String> _tableLabels = {
  'customers': 'Cliente',
  'customer_addresses': 'Dirección del cliente',
  'sales_invoices': 'Venta',
  'sales_invoice_items': 'Línea de venta',
  'sales_payments': 'Pago de venta',
  'attendances': 'Asistencia',
  'loyalty': 'Puntos del cliente',
  'products': 'Producto',
  'product_categories': 'Categoría',
  'purchase_invoices': 'Compra',
  'purchase_payments': 'Pago a proveedor',
  'expenses': 'Gasto',
  'suppliers': 'Proveedor',
  'bikes': 'Bicicleta',
  'bike_events': 'Ficha de la bici',
  'bike_observations': 'Ficha de la bici',
  'bike_system_states': 'Ficha de la bici',
  'bike_interventions': 'Ficha de la bici',
  'bike_component_lifecycles': 'Ficha de la bici',
  'mechanic_jobs': 'Trabajo',
  'mechanic_job_items': 'Línea del trabajo',
  'smart_tasks': 'Tarea',
  'stock_movements': 'Movimiento de stock',
  'employees': 'Trabajador',
  'website_pages': 'Página del sitio',
  'website_blocks': 'Bloque del sitio',
  'website_settings': 'Ajuste del sitio',
};

const Map<String, String> _rpcLabels = {
  'create_atomic_sales_checkout': 'Venta del mesón',
  'register_sales_payment_with_invoice_tax': 'Pago de venta',
  'ensure_sales_invoice_journal_entry': 'Asiento de la venta',
  'create_sales_credit_note': 'Nota de crédito',
  'create_sales_return': 'Devolución',
  'create_billable_invoice_from_mechanic_job': 'Factura del trabajo',
  'convert_mechanic_job_to_billable': 'Factura del trabajo',
  'save_product_with_specs_v1': 'Producto',
  'save_product_with_specs_v2': 'Producto',
  'save_supplier_contact': 'Contacto del proveedor',
  'create_purchase_goods_receipt': 'Recepción de compra',
  'set_product_on_order_terms_v1': 'Venta a pedido del producto',
};

/// Clasifica [method] + [url] con su cuerpo. Nunca lanza: lo que no reconoce es
/// un alta, el caso más prudente.
RequestSafety classifyRequest(
  String method,
  Uri url, {
  Map<String, String> headers = const {},
  List<int> body = const [],
}) {
  final verb = method.toUpperCase();
  final path = url.path;
  final resourceKey = '$verb ${url.path}${url.hasQuery ? '?${url.query}' : ''}';
  final json = _decodeObject(body);

  if (path.contains('/auth/v1/')) {
    return RequestSafety(
      effect: verb == 'GET' ? RequestEffect.read : RequestEffect.auth,
      resourceKey: resourceKey,
      label: 'Sesión',
    );
  }
  if (path.contains('/functions/v1/')) {
    final name = path.split('/functions/v1/').last.split('/').first;
    return RequestSafety(
      effect: RequestEffect.function,
      resourceKey: resourceKey,
      label: 'Envío ($name)',
      rpcName: name,
    );
  }
  if (path.contains('/storage/v1/')) {
    final upsert = _header(headers, 'x-upsert')?.toLowerCase() == 'true';
    final signing = path.contains('/storage/v1/object/sign/') ||
        path.contains('/storage/v1/object/list/');
    final effect = verb == 'GET' || verb == 'HEAD' || signing
        ? RequestEffect.read
        : (verb == 'DELETE' || verb == 'PUT' || upsert)
            ? RequestEffect.repeatableWrite
            : RequestEffect.insert;
    return RequestSafety(
      effect: effect,
      resourceKey: resourceKey,
      label: 'Archivo',
    );
  }

  final restIndex = path.indexOf('/rest/v1/');
  if (restIndex < 0) {
    final read = verb == 'GET' || verb == 'HEAD' || verb == 'OPTIONS';
    return RequestSafety(
      effect: read ? RequestEffect.read : RequestEffect.insert,
      resourceKey: resourceKey,
      label: 'Cambio',
    );
  }
  final rest = path.substring(restIndex + '/rest/v1/'.length);

  if (rest.startsWith('rpc/')) {
    final rpc = rest.substring('rpc/'.length).split('/').first;
    final key = _idempotencyKeyOf(json);
    final label = _rpcLabels[rpc] ?? 'Cambio';
    final durable = _durableElsewhereRpcs.contains(rpc);
    if (verb == 'GET' || _isReadRpc(rpc)) {
      return RequestSafety(
        effect: RequestEffect.read,
        resourceKey: resourceKey,
        label: label,
        rpcName: rpc,
      );
    }
    return RequestSafety(
      effect: key != null ? RequestEffect.keyedCommand : RequestEffect.insert,
      resourceKey: resourceKey,
      label: label,
      rpcName: rpc,
      idempotencyKey: key,
      detail: _detailOf(json),
      durableElsewhere: durable,
    );
  }

  final table = rest.split('/').first;
  final label = _tableLabels[table] ?? 'Cambio';
  if (verb == 'GET' || verb == 'HEAD' || verb == 'OPTIONS') {
    return RequestSafety(
      effect: RequestEffect.read,
      resourceKey: resourceKey,
      label: label,
      table: table,
    );
  }
  final prefer = _header(headers, 'prefer')?.toLowerCase() ?? '';
  final upsert = prefer.contains('resolution=merge-duplicates') ||
      prefer.contains('resolution=ignore-duplicates');
  final repeatable =
      verb == 'PATCH' || verb == 'DELETE' || verb == 'PUT' || upsert;
  final identity = verb == 'POST' && !upsert ? rowIdentityOf(body) : null;
  return RequestSafety(
    effect: repeatable
        ? RequestEffect.repeatableWrite
        : identity != null
            ? RequestEffect.identifiedInsert
            : RequestEffect.insert,
    resourceKey: resourceKey,
    label: label,
    table: table,
    idempotencyKey: identity?.value,
    identityColumn: identity?.column,
    detail: _detailOf(json),
  );
}

final RegExp _uuidShape = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// La identidad con que nace la fila (o el lote) de un alta: su
/// `idempotency_key` si la trae (la llave que el dueño sostiene entre
/// intentos), si no su `id` con forma de uuid. Un lote la tiene sólo si todas
/// sus filas la tienen; entonces vale la de la primera, porque PostgREST
/// inserta el lote entero o nada.
({String column, String value})? rowIdentityOf(List<int> body) {
  if (body.isEmpty || body.length > 512 * 1024) return null;
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(body));
  } catch (_) {
    return null;
  }
  final rows = decoded is List ? decoded : [decoded];
  if (rows.isEmpty) return null;
  ({String column, String value})? first;
  for (final row in rows) {
    if (row is! Map) return null;
    final identity = _identityOfRow(row);
    if (identity == null) return null;
    first ??= identity;
  }
  return first;
}

({String column, String value})? _identityOfRow(Map<Object?, Object?> row) {
  final key = row['idempotency_key'];
  if (key is String && key.trim().isNotEmpty) {
    return (column: 'idempotency_key', value: key.trim());
  }
  final id = row['id'];
  if (id is String && _uuidShape.hasMatch(id.trim())) {
    return (column: 'id', value: id.trim());
  }
  return null;
}

bool _isReadRpc(String rpc) {
  if (_writesDespiteReadName.contains(rpc)) return false;
  if (_readsWithoutReadName.contains(rpc)) return true;
  return _readPrefixes.any(rpc.startsWith);
}

String? _idempotencyKeyOf(Map<String, Object?>? json) {
  if (json == null) return null;
  for (final param in requestIdempotencyKeyParams) {
    final value = json[param];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

/// Un dato que la persona reconoce: el nombre, la razón social, el monto.
String? _detailOf(Object? json) {
  final row = json is List && json.isNotEmpty ? json.first : json;
  if (row is! Map) return null;
  const names = [
    'p_customer_name',
    'name',
    'nombre',
    'title',
    'p_name',
    'full_name',
    'business_name',
    'invoice_number',
    'p_reference',
    'reference',
  ];
  for (final key in names) {
    final value = row[key];
    if (value is String && value.trim().isNotEmpty) {
      final text = value.trim();
      return text.length > 60 ? '${text.substring(0, 57)}…' : text;
    }
  }
  const amounts = ['p_amount', 'amount', 'total', 'p_total'];
  for (final key in amounts) {
    final value = row[key];
    if (value is num && value > 0) return _money(value);
  }
  return null;
}

String _money(num value) {
  final digits = value.round().abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '\$ ${value < 0 ? '-' : ''}$buffer';
}

Map<String, Object?>? _decodeObject(List<int> body) {
  if (body.isEmpty || body.length > 512 * 1024) return null;
  try {
    final decoded = jsonDecode(utf8.decode(body, allowMalformed: false));
    if (decoded is Map) return Map<String, Object?>.from(decoded);
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      return Map<String, Object?>.from(decoded.first as Map);
    }
  } catch (_) {
    // Un cuerpo que no es JSON (una foto, un formulario) no tiene llave.
  }
  return null;
}

String? _header(Map<String, String> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  return null;
}
