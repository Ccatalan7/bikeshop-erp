import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../modules/messaging/utils/conversation_channel_presentation.dart';
import '../right_toolbar_service.dart';
import '../../utils/bike_finder_search.dart';
import '../authority_scoped_cache.dart';
import '../tenant_service.dart';
import '../../widgets/status_badge.dart';
import 'global_search_entry.dart';

/// Techo por clase. Hoy ningún tenant lo alcanza —el mayor tiene 1.741
/// clientes y 1.674 productos, medidos en producción el 2026-09-17— pero un
/// índice que se corta **en silencio** contesta «no existe» sobre datos que sí
/// están, y eso es peor que tardar. Cuando se corta, se dice.
const int kGlobalSearchRecordCeiling = 6000;

/// El índice de registros del buscador global.
///
/// **Por qué vive en el cliente.** Todo el tenant cabe en memoria: ~5.600 filas
/// de texto angosto. Eso permite contestar cada tecla sin viaje al servidor,
/// con tolerancia a errores de tipeo, y seguir contestando con la conexión
/// mala. Un ERP que consulta por tecla no puede hacer ninguna de las tres.
///
/// **Lo que NO entra acá.** Sueldos, datos bancarios, claves de portal: el
/// índice sólo carga las columnas por las que alguien busca. Una columna
/// sensible en un índice de búsqueda es una filtración esperando la consulta
/// correcta.
class GlobalSearchIndex extends ChangeNotifier {
  GlobalSearchIndex({SupabaseClient? client, TenantService? tenantService})
      : _client = client ?? Supabase.instance.client,
        _tenantService = tenantService ?? TenantService();

  final SupabaseClient _client;
  final TenantService _tenantService;

  final AuthorityCacheScope _scope = AuthorityCacheScope();
  late final AuthorityScopedLoad<List<GlobalSearchEntry>> _load =
      AuthorityScopedLoad<List<GlobalSearchEntry>>(_scope);

  List<GlobalSearchEntry> _records = const <GlobalSearchEntry>[];
  Set<GlobalSearchKind> _truncated = const <GlobalSearchKind>{};
  DateTime? _loadedAt;
  bool _isLoading = false;
  Object? _lastError;

  List<GlobalSearchEntry> get records => _records;
  bool get isLoading => _isLoading;
  bool get hasLoaded => _loadedAt != null;
  DateTime? get loadedAt => _loadedAt;

  /// Clases que se cortaron en [kGlobalSearchRecordCeiling].
  Set<GlobalSearchKind> get truncatedKinds => _truncated;

  /// La última carga falló. La superficie lo dice en vez de mostrar una lista
  /// vacía que afirmaría que no existe nada.
  Object? get lastError => _lastError;

  ErpAuthorityScopeKey? get authorityScope => _scope.key;

  void bindAuthorityScope(
      {required String? userId, required String? tenantId}) {
    if (!_scope.bind(userId: userId, tenantId: tenantId)) return;
    _clearAuthorityOwnedState();
  }

  void _clearAuthorityOwnedState() {
    _load.detach();
    final had = _records.isNotEmpty;
    _records = const <GlobalSearchEntry>[];
    _truncated = const <GlobalSearchKind>{};
    _loadedAt = null;
    _lastError = null;
    if (had) notifyListeners();
  }

  /// Vuelve a leer si nunca se leyó, si venció, o si el llamador lo fuerza.
  Future<void> ensureLoaded({
    bool force = false,
    Duration maxAge = const Duration(minutes: 10),
  }) async {
    final loadedAt = _loadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < maxAge) {
      return;
    }

    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _scope.resolve(userId: null, tenantId: null);
      return;
    }
    final tenantId = await _tenantService.getTenantId();
    if (_client.auth.currentUser?.id != userId) return;
    if (tenantId == null || tenantId.isEmpty) {
      _scope.resolve(userId: null, tenantId: null);
      return;
    }
    final resolution = _scope.resolve(userId: userId, tenantId: tenantId);
    if (resolution.didChange) _clearAuthorityOwnedState();
    if (!resolution.isAccepted) return;

    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      await _load.run(
        load: (lease) => _fetchEverything(lease.scope.tenantId),
        publish: (value, lease) {
          _records = List<GlobalSearchEntry>.unmodifiable(value);
          _loadedAt = DateTime.now();
        },
      );
    } on AuthorityScopeChangedException {
      // Otro tenant tomó el scope mientras se leía. Lo que volvió ya no es de
      // este usuario y no se publica.
    } catch (error) {
      _lastError = error;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<GlobalSearchEntry>> _fetchEverything(String tenantId) async {
    final truncated = <GlobalSearchKind>{};

    final results = await Future.wait<List<Map<String, dynamic>>>([
      _selectOrEmpty(
        'customers',
        'id, name, rut, phone, city, is_active, updated_at',
        tenantId,
      ),
      _selectOrEmpty(
        'products',
        'id, name, sku, barcode, brand, model, category_name, '
            'stock_quantity, is_service, is_active, updated_at',
        tenantId,
      ),
      _selectOrEmpty(
        'sales_invoices',
        'id, invoice_number, customer_name, customer_rut, total, status, '
            'date, updated_at',
        tenantId,
      ),
      _selectOrEmpty(
        'mechanic_jobs',
        'id, job_number, customer_id, bike_id, client_request, status, '
            'updated_at',
        tenantId,
        excludeSoftDeleted: true,
      ),
      _selectOrEmpty(
        'bikes',
        'id, customer_id, brand, model, serial_number, qr_code, color, '
            'is_active, updated_at',
        tenantId,
      ),
      _selectOrEmpty(
        'suppliers',
        'id, name, rut, trade_name, legal_name, is_active, updated_at',
        tenantId,
      ),
      // Sólo identidad laboral: ni sueldo, ni banco, ni RUT.
      _selectOrEmpty(
        'employees',
        'id, first_name, last_name, job_title, employee_number, status, '
            'updated_at',
        tenantId,
      ),
      // Los archivos que llegaron por conversación. Se embebe la conversación
      // para saber **de quién** vino: sin eso, «PEDALES GINEYEA JUN 26.pdf» es
      // un archivo sin dueño y el resultado no se puede leer.
      _selectOrEmpty(
        'messaging_attachments',
        'id, conversation_id, storage_path, original_filename, extension, '
            'declared_mime_type, attached_at, '
            'conversations(title, counterparty_type, channel, '
            'whatsapp_conversation_bindings(contact_name, '
            'supplier_contacts(name)))',
        tenantId,
        onlyAttached: true,
      ),
      // Las conversaciones abiertas. Se embeben el vínculo de WhatsApp y su
      // contacto porque **el hilo no se llama sólo como se titula**: el de
      // TeknoBike se pide como «el de Diego», y ese nombre vive en el vínculo,
      // no en la conversación.
      _selectOrEmpty(
        'conversations',
        'id, title, type, channel, counterparty_type, status, last_message_at, '
            'whatsapp_conversation_bindings(contact_name, '
            'external_phone_number, supplier_contacts(name, role))',
        tenantId,
      ),
      _selectOrEmpty(
        'purchase_invoices',
        'id, invoice_number, supplier_name, supplier_invoice_number, total, '
            'status, date, updated_at',
        tenantId,
      ),
    ]);

    void markIfTruncated(GlobalSearchKind kind, List<dynamic> rows) {
      if (rows.length >= kGlobalSearchRecordCeiling) truncated.add(kind);
    }

    final customers = results[0];
    final products = results[1];
    final salesInvoices = results[2];
    final jobs = results[3];
    final bikes = results[4];
    final suppliers = results[5];
    final employees = results[6];
    final attachments = results[7];
    final conversations = results[8];
    final purchases = results[9];

    markIfTruncated(GlobalSearchKind.customer, customers);
    markIfTruncated(GlobalSearchKind.product, products);
    markIfTruncated(GlobalSearchKind.salesInvoice, salesInvoices);
    markIfTruncated(GlobalSearchKind.job, jobs);
    markIfTruncated(GlobalSearchKind.bike, bikes);
    markIfTruncated(GlobalSearchKind.supplier, suppliers);
    markIfTruncated(GlobalSearchKind.employee, employees);
    markIfTruncated(GlobalSearchKind.purchase, purchases);
    markIfTruncated(GlobalSearchKind.attachment, attachments);
    markIfTruncated(GlobalSearchKind.conversation, conversations);

    // El dueño de la bicicleta y el de la pega se resuelven acá, en memoria:
    // una bicicleta sin su dueño en el texto no aparece cuando alguien la
    // busca por el nombre de quien la trajo, que es como se la busca de verdad.
    final customerNames = <String, String>{
      for (final row in customers)
        if (row['id'] != null) '${row['id']}': '${row['name'] ?? ''}',
    };
    final bikeLabels = <String, String>{
      for (final row in bikes)
        if (row['id'] != null) '${row['id']}': _bikeLabel(row),
    };

    final entries = <GlobalSearchEntry>[];
    for (final row in customers) {
      entries.add(_customerEntry(row));
    }
    for (final row in products) {
      entries.add(_productEntry(row));
    }
    for (final row in salesInvoices) {
      entries.add(_salesInvoiceEntry(row));
    }
    for (final row in jobs) {
      entries.add(_jobEntry(row, customerNames, bikeLabels));
    }
    for (final row in bikes) {
      entries.add(_bikeEntry(row, customerNames));
    }
    for (final row in suppliers) {
      entries.add(_supplierEntry(row));
    }
    for (final row in employees) {
      entries.add(_employeeEntry(row));
    }
    for (final row in purchases) {
      entries.add(_purchaseEntry(row));
    }
    for (final row in attachments) {
      final entry = globalSearchAttachmentEntry(row);
      if (entry != null) entries.add(entry);
    }
    for (final row in conversations) {
      final entry = globalSearchConversationEntry(row);
      if (entry != null) entries.add(entry);
    }

    _truncated = Set<GlobalSearchKind>.unmodifiable(truncated);
    return entries;
  }

  /// Una fuente que falla no puede dejar al buscador sin las otras.
  ///
  /// `Future.wait` propaga el primer error, así que una consulta rota —una
  /// columna que cambió, un embed que el servidor rechaza— borraba el índice
  /// entero y el buscador contestaba «no hay nada» sobre un taller lleno de
  /// datos. Cada fuente responde por sí misma: la que falla queda vacía y
  /// anotada, y el resto sigue contestando.
  final Set<String> _failedSources = <String>{};

  /// Tablas que no se pudieron leer en la última carga.
  Set<String> get failedSources => _failedSources;

  Future<List<Map<String, dynamic>>> _selectOrEmpty(
    String table,
    String columns,
    String tenantId, {
    bool excludeSoftDeleted = false,
    bool onlyAttached = false,
  }) async {
    try {
      final rows = await _select(
        table,
        columns,
        tenantId,
        excludeSoftDeleted: excludeSoftDeleted,
        onlyAttached: onlyAttached,
      );
      _failedSources.remove(table);
      return rows;
    } catch (error) {
      _failedSources.add(table);
      debugPrint('[global-search] no se pudo leer $table: $error');
      return const <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _select(
    String table,
    String columns,
    String tenantId, {
    bool excludeSoftDeleted = false,
    bool onlyAttached = false,
  }) async {
    // El filtro de tenant es explícito aunque RLS ya lo imponga: en este
    // repositorio una consulta multi-tenant sin `tenant_id` es un defecto, no
    // una redundancia.
    var query = _client.from(table).select(columns).eq('tenant_id', tenantId);
    if (excludeSoftDeleted) query = query.isFilter('deleted_at', null);
    // Un archivo que no terminó de subir no tiene objeto en el bucket: ofrecerlo
    // es prometer una vista previa que no puede abrirse. En producción hay uno
    // `failed` entre 40 (2026-09-17).
    if (onlyAttached) query = query.eq('status', 'attached');
    final rows = await query
        .order('updated_at', ascending: false)
        .limit(kGlobalSearchRecordCeiling);
    return List<Map<String, dynamic>>.from(rows);
  }
}

String? _text(dynamic value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}

DateTime? _timestamp(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse('$value');
}

/// El RUT se teclea con puntos, sin puntos y a veces sin guion. Se indexan las
/// dos formas para que las tres maneras de escribirlo encuentren a la persona.
String? _compactIdentity(String? value) {
  if (value == null) return null;
  final compact = normalizeBikeFinderSearch(value).replaceAll(
    RegExp(r'[^a-z0-9]'),
    '',
  );
  return compact.isEmpty ? null : compact;
}

/// El estado de una pega llega en MAYÚSCULAS con guion bajo
/// (`ESPERANDO_REPUESTOS`, medido en producción). Se presenta como frase, que
/// es como se dice en el taller; no se traduce ni se reinterpreta.
String? _jobStatusLabel(String? status) {
  if (status == null || status.isEmpty) return null;
  final words = status.toLowerCase().replaceAll('_', ' ');
  return words[0].toUpperCase() + words.substring(1);
}

String _bikeLabel(Map<String, dynamic> row) {
  final parts = <String>[
    if (_text(row['brand']) != null) _text(row['brand'])!,
    if (_text(row['model']) != null) _text(row['model'])!,
  ];
  return parts.isEmpty ? 'Bicicleta' : parts.join(' ');
}

GlobalSearchEntry _customerEntry(Map<String, dynamic> row) {
  final name = _text(row['name']) ?? 'Cliente sin nombre';
  final rut = _text(row['rut']);
  final phone = _text(row['phone']);
  final city = _text(row['city']);
  final isActive = row['is_active'] != false;

  return GlobalSearchEntry(
    kind: GlobalSearchKind.customer,
    id: 'customer:${row['id']}',
    title: name,
    subtitle: <String>[
      if (rut != null) rut,
      if (phone != null) phone,
      if (city != null) city,
      if (!isActive) 'Inactivo',
    ].join(' · '),
    identifier: rut,
    route: '/clientes/${row['id']}',
    updatedAt: _timestamp(row['updated_at']),
    fields: <BikeFinderSearchField>[
      BikeFinderSearchField(name, weight: 135),
      BikeFinderSearchField(rut, weight: 130),
      BikeFinderSearchField(_compactIdentity(rut), weight: 130),
      BikeFinderSearchField(phone, weight: 128),
      BikeFinderSearchField(_compactIdentity(phone), weight: 128),
      BikeFinderSearchField(city, weight: 60),
    ],
  );
}

GlobalSearchEntry _productEntry(Map<String, dynamic> row) {
  final name = _text(row['name']) ?? 'Producto sin nombre';
  final sku = _text(row['sku']);
  final barcode = _text(row['barcode']);
  final brand = _text(row['brand']);
  final model = _text(row['model']);
  final category = _text(row['category_name']);
  final isService = row['is_service'] == true;
  final stock = row['stock_quantity'];

  return GlobalSearchEntry(
    kind: GlobalSearchKind.product,
    id: 'product:${row['id']}',
    title: name,
    subtitle: <String>[
      if (sku != null) 'SKU $sku',
      if (category != null) category,
      if (!isService && stock is num) _stockLabel(stock),
      if (isService) 'Servicio',
    ].join(' · '),
    identifier: sku,
    icon: isService ? Icons.handyman_outlined : null,
    route: '/inventory/products/${row['id']}/edit',
    updatedAt: _timestamp(row['updated_at']),
    fields: <BikeFinderSearchField>[
      BikeFinderSearchField(name, weight: 135),
      BikeFinderSearchField(sku, weight: 140),
      BikeFinderSearchField(barcode, weight: 130),
      BikeFinderSearchField(brand, weight: 100),
      BikeFinderSearchField(model, weight: 100),
      BikeFinderSearchField(category, weight: 70),
    ],
  );
}

String _stockLabel(num stock) {
  if (stock <= 0) return 'Sin stock';
  if (stock == 1) return '1 en stock';
  return '${stock.toStringAsFixed(0)} en stock';
}

GlobalSearchEntry _salesInvoiceEntry(Map<String, dynamic> row) {
  final number = _text(row['invoice_number']) ?? 'Factura';
  final customer = _text(row['customer_name']);
  final rawStatus = _text(row['status']);
  final status =
      rawStatus == null ? null : vinabikeDocumentStatusLabel(rawStatus);

  return GlobalSearchEntry(
    kind: GlobalSearchKind.salesInvoice,
    id: 'sales_invoice:${row['id']}',
    title: number,
    subtitle: <String>[
      if (customer != null) customer,
      if (status != null) status,
    ].join(' · '),
    identifier: number,
    route: '/sales/invoices/${row['id']}',
    updatedAt: _timestamp(row['updated_at']) ?? _timestamp(row['date']),
    fields: <BikeFinderSearchField>[
      BikeFinderSearchField(number, weight: 140),
      BikeFinderSearchField(customer, weight: 115),
      BikeFinderSearchField(_text(row['customer_rut']), weight: 120),
      BikeFinderSearchField(_compactIdentity(_text(row['customer_rut'])),
          weight: 120),
    ],
  );
}

GlobalSearchEntry _purchaseEntry(Map<String, dynamic> row) {
  final number = _text(row['invoice_number']) ?? 'Documento de compra';
  final supplier = _text(row['supplier_name']);
  final supplierNumber = _text(row['supplier_invoice_number']);
  final rawStatus = _text(row['status']);
  final status =
      rawStatus == null ? null : vinabikeDocumentStatusLabel(rawStatus);

  return GlobalSearchEntry(
    kind: GlobalSearchKind.purchase,
    id: 'purchase_invoice:${row['id']}',
    title: number,
    subtitle: <String>[
      if (supplier != null) supplier,
      if (supplierNumber != null) 'Doc. $supplierNumber',
      if (status != null) status,
    ].join(' · '),
    identifier: number,
    route: '/purchases/${row['id']}',
    updatedAt: _timestamp(row['updated_at']) ?? _timestamp(row['date']),
    fields: <BikeFinderSearchField>[
      BikeFinderSearchField(number, weight: 140),
      BikeFinderSearchField(supplier, weight: 120),
      BikeFinderSearchField(supplierNumber, weight: 125),
    ],
  );
}

GlobalSearchEntry _jobEntry(
  Map<String, dynamic> row,
  Map<String, String> customerNames,
  Map<String, String> bikeLabels,
) {
  final number = _text(row['job_number']) ?? 'Trabajo';
  final customer = customerNames[_text(row['customer_id'])];
  final bike = bikeLabels[_text(row['bike_id'])];
  final request = _text(row['client_request']);
  final status = _jobStatusLabel(_text(row['status']));

  return GlobalSearchEntry(
    kind: GlobalSearchKind.job,
    id: 'mechanic_job:${row['id']}',
    title: number,
    subtitle: <String>[
      if (customer != null && customer.isNotEmpty) customer,
      if (bike != null) bike,
      if (status != null) status,
    ].join(' · '),
    identifier: number,
    route: '/taller/pegas/${row['id']}',
    updatedAt: _timestamp(row['updated_at']),
    fields: <BikeFinderSearchField>[
      BikeFinderSearchField(number, weight: 140),
      BikeFinderSearchField(customer, weight: 120),
      BikeFinderSearchField(bike, weight: 110),
      BikeFinderSearchField(request, weight: 75),
    ],
  );
}

GlobalSearchEntry _bikeEntry(
  Map<String, dynamic> row,
  Map<String, String> customerNames,
) {
  final label = _bikeLabel(row);
  final owner = customerNames[_text(row['customer_id'])];
  final serial = _text(row['serial_number']);
  final color = _text(row['color']);

  // Una bicicleta se abre dentro de la ficha de su dueño, en la pestaña de
  // bicicletas: es donde ya vive en este ERP, y el buscador no inventa una
  // pantalla nueva para lo que ya tiene una.
  final route = Uri(
    path: '/clientes/${row['customer_id']}',
    queryParameters: <String, String>{
      'tab': 'bicicletas',
      'bike_id': '${row['id']}',
    },
  ).toString();

  return GlobalSearchEntry(
    kind: GlobalSearchKind.bike,
    id: 'bike:${row['id']}',
    title: label,
    subtitle: <String>[
      if (owner != null && owner.isNotEmpty) owner,
      if (serial != null) 'Serie $serial',
      if (color != null) color,
    ].join(' · '),
    identifier: serial,
    route: route,
    updatedAt: _timestamp(row['updated_at']),
    fields: <BikeFinderSearchField>[
      BikeFinderSearchField(label, weight: 125),
      BikeFinderSearchField(owner, weight: 118),
      BikeFinderSearchField(serial, weight: 135),
      BikeFinderSearchField(_text(row['qr_code']), weight: 135),
      BikeFinderSearchField(color, weight: 65),
    ],
  );
}

GlobalSearchEntry _supplierEntry(Map<String, dynamic> row) {
  final name = _text(row['name']) ?? 'Proveedor';
  final rut = _text(row['rut']);
  final trade = _text(row['trade_name']);
  final legal = _text(row['legal_name']);

  return GlobalSearchEntry(
    kind: GlobalSearchKind.supplier,
    id: 'supplier:${row['id']}',
    title: name,
    subtitle: <String>[
      if (rut != null) rut,
      if (trade != null && trade != name) trade,
    ].join(' · '),
    identifier: rut,
    route: '/purchases/suppliers/${row['id']}',
    updatedAt: _timestamp(row['updated_at']),
    fields: <BikeFinderSearchField>[
      BikeFinderSearchField(name, weight: 135),
      BikeFinderSearchField(trade, weight: 120),
      BikeFinderSearchField(legal, weight: 110),
      BikeFinderSearchField(rut, weight: 125),
      BikeFinderSearchField(_compactIdentity(rut), weight: 125),
    ],
  );
}

/// Convierte una fila de `messaging_attachments` en un resultado abrible.
///
/// Devuelve `null` cuando la fila no alcanza para abrir nada: sin ruta de
/// almacenamiento no hay archivo que mostrar, y una fila que no se puede abrir
/// no es un resultado.
@visibleForTesting
GlobalSearchEntry? globalSearchAttachmentEntry(Map<String, dynamic> row) {
  final path = _text(row['storage_path']);
  final name = _text(row['original_filename']);
  if (path == null || name == null) return null;

  final conversation = _firstMap(row['conversations']);
  final counterparty = _text(conversation?['title']);
  final channel = _text(conversation?['channel']);
  final person = _conversationPersonName(conversation);
  final extension =
      (_text(row['extension']) ?? name.split('.').last).toLowerCase();
  final attachedAt = _timestamp(row['attached_at']);

  // **La pista nombra la conversación entera, no sólo la empresa.** «TeknoBike»
  // dice de qué proveedor vino; en el taller ese hilo se piensa como «el de
  // Diego», y es a Diego a quien uno le pidió el catálogo. Se dice igual que lo
  // dice el encabezado del chat —«TeknoBike · Diego Muñoz»— para que el archivo
  // y su conversación se lean con las mismas palabras.
  final origin = <String>[
    if (counterparty != null) counterparty,
    if (person != null && person != counterparty) person,
    if (channel != null)
      ConversationChannelPresentation.shortLabelForChannel(channel),
  ].join(' · ');

  return GlobalSearchEntry(
    kind: GlobalSearchKind.attachment,
    id: 'attachment:${row['id']}',
    title: name,
    subtitle: <String>[
      if (origin.isNotEmpty) origin,
      if (attachedAt != null) _shortDate(attachedAt),
    ].join(' · '),
    route: '/chat',
    icon: _attachmentIcon(extension),
    updatedAt: attachedAt,
    attachment: GlobalSearchAttachment(
      storagePath: path,
      fileName: name,
      extension: extension,
      contentType:
          _text(row['declared_mime_type']) ?? 'application/octet-stream',
      origin: origin.isEmpty ? 'Conversación' : origin,
    ),
    fields: <BikeFinderSearchField>[
      BikeFinderSearchField(name, weight: 135),
      // De quién vino pesa como campo y **no** como nombre: el archivo no se
      // llama Diego, viene de Diego. Alcanza para que «diego» traiga lo que
      // mandó, sin que un catálogo compita con las personas que sí se llaman
      // así.
      BikeFinderSearchField(counterparty, weight: 110),
      BikeFinderSearchField(person, weight: 110),
      BikeFinderSearchField(extension, weight: 70),
    ],
  );
}

/// Convierte una conversación en un resultado que se abre en su hilo.
///
/// **Un hilo responde a más de un nombre.** Se titula con la empresa —el chat
/// de TeknoBike se llama «TeknoBike»— pero en el taller se pide por la persona
/// con la que uno habla: «el de Diego». Ese nombre ya está en el registro, en
/// el vínculo de WhatsApp (`contact_name`, el perfil con que llegó) y en la
/// ficha del contacto del proveedor (`supplier_contacts.name`, como lo escribió
/// alguien acá). Los dos entran como nombre de la fila, no como sinónimo
/// inventado: nadie escribió «diego significa TeknoBike», es que ese hilo se
/// llama de las dos maneras.
///
/// Devuelve `null` cuando la fila no alcanza para abrir un hilo.
@visibleForTesting
GlobalSearchEntry? globalSearchConversationEntry(Map<String, dynamic> row) {
  final id = _text(row['id']);
  if (id == null) return null;

  final binding = _firstMap(row['whatsapp_conversation_bindings']);
  final supplierContact =
      binding == null ? null : _firstMap(binding['supplier_contacts']);

  // La misma regla que usa el adjunto para decir de dónde vino: una sola.
  final contact = _conversationPersonName(row);
  final phone = _text(binding?['external_phone_number']);
  final channel = _text(row['channel']);
  final channelLabel =
      ConversationChannelPresentation.shortLabelForChannel(channel);
  final lastMessageAt = _timestamp(row['last_message_at']);

  // Un hilo sin título se llama como la persona; sin ninguno de los dos, por su
  // canal — que es lo único cierto que queda.
  final title = _text(row['title']) ?? contact ?? 'Conversación · $channelLabel';

  final normalizedTitle = normalizeBikeFinderSearch(title);
  final showsContact =
      contact != null && normalizeBikeFinderSearch(contact) != normalizedTitle;

  return GlobalSearchEntry(
    kind: GlobalSearchKind.conversation,
    id: 'conversation:$id',
    title: title,
    // El número **es** el identificador del hilo: no tiene otro. Así lo
    // encuentra quien pega «+56 9 7701 4463» desde WhatsApp, porque el calce de
    // identificador compara sin separadores y no palabra por palabra.
    identifier: phone,
    subtitle: <String>[
      if (showsContact) contact,
      channelLabel,
      if (lastMessageAt != null) _shortDate(lastMessageAt),
    ].join(' · '),
    // La ruta queda como respaldo —y como lo que se copia o se comparte—, pero
    // el resultado abre el panel del rail: ver abajo.
    route: Uri(
      path: '/chat',
      queryParameters: <String, String>{'conversation': id},
    ).toString(),
    conversationId: id,
    // Proveedores y clientes son dos bandejas distintas. Cuál es, lo dice la
    // fila que ya se leyó: no hace falta preguntarle al módulo de mensajería
    // —que puede no estar cargado— ni caer a la general y que se resuelva sola.
    toolbarTool: _text(row['counterparty_type']) == 'supplier'
        ? ToolbarTool.supplierMessages
        : ToolbarTool.messages,
    icon: ConversationChannelPresentation.iconForChannel(channel),
    updatedAt: lastMessageAt,
    alsoNamed: <String>{if (contact != null) contact},
    fields: <BikeFinderSearchField>[
      BikeFinderSearchField(title, weight: 135),
      // La persona pesa como el título porque **es** el otro nombre del hilo.
      BikeFinderSearchField(contact, weight: 132),
      BikeFinderSearchField(phone, weight: 120),
      BikeFinderSearchField(_compactIdentity(phone), weight: 120),
      BikeFinderSearchField(_text(supplierContact?['role']), weight: 70),
      // Se puede escribir, no se muestra: «proveedor», «cliente», «interno».
      BikeFinderSearchField(_text(row['counterparty_type']), weight: 55),
      BikeFinderSearchField(channelLabel, weight: 55),
    ],
  );
}

/// Con quién se habla en esa conversación, si se sabe.
///
/// El nombre de la ficha del contacto manda sobre el del perfil de WhatsApp:
/// «Diego Muñoz» lo escribió alguien de la tienda, «Diego» es como se puso él.
String? _conversationPersonName(Map<String, dynamic>? conversation) {
  final binding = _firstMap(conversation?['whatsapp_conversation_bindings']);
  if (binding == null) return null;
  return _text(_firstMap(binding['supplier_contacts'])?['name']) ??
      _text(binding['contact_name']);
}

/// PostgREST devuelve un embed uno-a-muchos como lista y uno-a-uno como mapa.
/// Se aceptan las dos formas para no depender de cómo resolvió la relación.
Map<String, dynamic>? _firstMap(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List) {
    for (final item in value) {
      if (item is Map) return Map<String, dynamic>.from(item);
    }
  }
  return null;
}

const List<String> _monthsEs = <String>[
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

String _shortDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_monthsEs[local.month - 1]}';
}

IconData _attachmentIcon(String extension) => switch (extension) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'jpg' ||
      'jpeg' ||
      'png' ||
      'gif' ||
      'webp' ||
      'heic' =>
        Icons.image_outlined,
      'xlsx' || 'xls' || 'csv' => Icons.table_chart_outlined,
      'doc' || 'docx' => Icons.article_outlined,
      _ => Icons.insert_drive_file_outlined,
    };

GlobalSearchEntry _employeeEntry(Map<String, dynamic> row) {
  final name = <String>[
    if (_text(row['first_name']) != null) _text(row['first_name'])!,
    if (_text(row['last_name']) != null) _text(row['last_name'])!,
  ].join(' ');
  final role = _text(row['job_title']);
  final number = _text(row['employee_number']);

  return GlobalSearchEntry(
    kind: GlobalSearchKind.employee,
    id: 'employee:${row['id']}',
    title: name.isEmpty ? 'Persona del equipo' : name,
    subtitle: <String>[
      if (role != null) role,
      if (_text(row['status']) != null) _text(row['status'])!,
    ].join(' · '),
    identifier: number,
    route: '/hr/employees/${row['id']}',
    updatedAt: _timestamp(row['updated_at']),
    fields: <BikeFinderSearchField>[
      BikeFinderSearchField(name, weight: 135),
      BikeFinderSearchField(role, weight: 90),
      BikeFinderSearchField(number, weight: 120),
    ],
  );
}
