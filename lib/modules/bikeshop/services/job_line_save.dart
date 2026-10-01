import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../models/bikeshop_models.dart';
import 'bike_technical_fact_patch.dart';

/// Guardar las líneas del trabajo y lo que «Configurar» confirmó de la bici en
/// una sola transacción (`save_mechanic_job_lines_v1`, ítem 4 de
/// BIKE_WORKSHOP_MASTER_SCHEMA.md). Aquí está lo que no toca la red: la forma
/// del pedido, el recibo y los errores. El envío pasa por la bandeja del
/// equipo (`WorkshopCommandOutbox`), que lo respalda antes con su llave.

/// Lo que el formulario vio de una línea al cargarla: el servidor rechaza el
/// guardado si la línea cambió desde entonces.
class JobLineVersion {
  const JobLineVersion({required this.id, required this.version});

  final String id;

  /// El `updated_at` de la línea tal como lo mandó el servidor, en texto. Un
  /// `DateTime` en web pierde los microsegundos: la versión no volvería igual
  /// y todo guardado chocaría.
  final String version;

  Map<String, dynamic> toJson() => {'id': id, 'updated_at': version};
}

/// Una línea para el comando: la del formulario ([clientKey]) y, si ya estaba
/// guardada, su id.
class JobLineToSave {
  const JobLineToSave({
    required this.clientKey,
    required this.item,
    required this.persisted,
    this.jobBikeKey,
  });

  final String clientKey;
  final MechanicJobItem item;

  /// La llave de la bici del trabajo ([JobBikeToSave.clientKey]) cuando la
  /// bici entra en este mismo guardado y todavía no tiene id.
  final String? jobBikeKey;

  /// Ya existe en el servidor: se actualiza por su id. Si no, se inserta.
  /// Una línea nueva no trae tareas: la descripción de su producto es su
  /// instrucción, no tareas (20260929040000).
  final bool persisted;

  /// Lo que el formulario escribe de una línea. El total lo calcula la base;
  /// el taller, el trabajo y las fechas los pone ella.
  Map<String, dynamic> toJson() => {
        'client_key': clientKey,
        if (persisted) 'id': item.id,
        if (jobBikeKey == null)
          'job_bike_id': item.jobBikeId
        else
          'job_bike_key': jobBikeKey,
        'product_id': item.productId,
        'service_product_id': item.serviceProductId,
        'product_name': item.productName,
        'product_sku': item.productSku,
        'quantity': item.quantity,
        'unit_price': item.unitPrice,
        'notes': item.notes,
        'service_configuration_data': item.serviceConfigurationData,
        'item_type': item.itemType,
        'system_key': item.systemKey,
        'component_slot_key': item.componentSlotKey,
        'location_key': item.location.dbValue,
        'intervention_type': item.interventionType?.dbValue,
        'creates_lifecycle': item.createsLifecycle,
      };
}

/// Una bici del trabajo para el comando: su diagnóstico, lo pedido, las
/// notas, su hoja de diagnóstico y sus marcas. Antes se escribía aparte,
/// antes del comando, y un guardado rechazado la dejaba escrita sin las
/// líneas ni la cabecera (revisión de Codex, 2026-09-28). Viajan sólo las que
/// cambian: la nueva ([JobBikeToSave.added]), la que estaba con cada campo
/// cambiado y lo que se vio al cargar ([JobBikeToSave.changed]; si otro lo
/// cambió, nada se guarda) y la que sale ([JobBikeToSave.removed]). Una que
/// no viaja no se toca: otra persona pudo agregarla (segunda revisión).
class JobBikeToSave {
  const JobBikeToSave._(this.clientKey, this._json);

  /// Una bici nueva en el trabajo, con todo lo suyo. Sus líneas la nombran
  /// por [clientKey] ([JobLineToSave.jobBikeKey]).
  factory JobBikeToSave.added({
    required String clientKey,
    required MechanicJobBike jobBike,
  }) {
    final row = jobBike.toJson();
    return JobBikeToSave._(clientKey, {
      'client_key': clientKey,
      for (final column in mechanicJobBikeFormColumns)
        if (row.containsKey(column)) column: row[column],
    });
  }

  /// Una bici que ya estaba: cada campo que difiere de [seen] (la fila como
  /// la mandó el servidor al cargar, [MechanicJobBike.persisted], o la del
  /// último recibo), con ese valor visto. Los campos de [keep] no viajan
  /// (una hoja de diagnóstico que el formulario conserva sin mostrarla).
  /// Null si no cambió nada: no hace falta mandarla.
  static JobBikeToSave? changed({
    required String clientKey,
    required MechanicJobBike jobBike,
    required Map<String, dynamic> seen,
    Set<String> keep = const {},
  }) {
    final row = jobBike.toJson(forUpdate: true);
    final changed = <String, dynamic>{
      for (final column in mechanicJobBikeFormColumns)
        if (column != 'bike_id' &&
            !keep.contains(column) &&
            row.containsKey(column) &&
            seen.containsKey(column) &&
            !_sameColumnValue(column, seen[column], row[column]))
          column: row[column],
    };
    if (changed.isEmpty) return null;
    return JobBikeToSave._(clientKey, {
      'client_key': clientKey,
      'id': jobBike.id,
      'bike_id': jobBike.bikeId,
      ...changed,
      'expected': {for (final column in changed.keys) column: seen[column]},
    });
  }

  /// Una bici que el formulario mostraba y se quitó: sale al final, con sus
  /// líneas, y con lo que se vio de ella ([seen]): si otro la cambió desde
  /// entonces, no se borra (tercera revisión de Codex).
  factory JobBikeToSave.removed({
    required String clientKey,
    required String jobBikeId,
    required String bikeId,
    required Map<String, dynamic> seen,
  }) =>
      JobBikeToSave._(clientKey, {
        'client_key': clientKey,
        'id': jobBikeId,
        'bike_id': bikeId,
        'remove': true,
        'expected': {
          for (final column in mechanicJobBikeFormColumns)
            if (column != 'bike_id' && seen.containsKey(column))
              column: seen[column],
        },
      });

  /// La bici (`bike_id`): está una sola vez en el trabajo.
  final String clientKey;
  final Map<String, dynamic> _json;

  Map<String, dynamic> toJson() => Map<String, dynamic>.of(_json);
}

/// Los parámetros del comando, sin la llave. [lines] y [seenLines] en null
/// dejan las líneas como están (un trabajo con pago); [bikeFacts] va por bici;
/// [header], los campos de la cabecera que cambiaron ([jobHeaderPatch]);
/// [jobBikes], las bicis del trabajo: con las líneas, todas las que quedan
/// (la que falta sale con sus líneas); sin ellas, sólo las que cambian.
Map<String, dynamic> jobLineSaveParams({
  required String jobId,
  required List<JobLineVersion>? seenLines,
  required List<JobLineToSave>? lines,
  required Map<String, List<BikeTechnicalFact>> bikeFacts,
  Map<String, Map<String, dynamic>> header = const {},
  List<JobBikeToSave>? jobBikes,
  bool invoice = false,
}) {
  if ((seenLines == null) != (lines == null)) {
    throw ArgumentError('Las líneas viajan con las que vio el formulario.');
  }
  final sortedSeen = seenLines == null
      ? null
      : ([...seenLines]..sort((a, b) => a.id.compareTo(b.id)));
  final bikeIds = bikeFacts.keys.toList()..sort();
  return {
    'p_job_id': jobId,
    'p_seen_lines': sortedSeen?.map((line) => line.toJson()).toList(),
    'p_lines': lines?.map((line) => line.toJson()).toList(),
    'p_bike_facts': [
      for (final bikeId in bikeIds)
        if (bikeFacts[bikeId]!.isNotEmpty)
          {
            'bike_id': bikeId,
            'facts': bikeFacts[bikeId]!.map((fact) => fact.toJson()).toList(),
          },
    ],
    'p_header': header.isEmpty ? null : header,
    'p_job_bikes': jobBikes?.map((jobBike) => jobBike.toJson()).toList(),
    // La factura del trabajo queda al día en la misma transacción que el
    // recibo: un comando confirmado tras cerrar la app o perder la respuesta
    // también la trae.
    if (invoice) 'p_invoice': true,
  };
}

const _timestampColumns = {
  'arrival_date',
  'deadline',
  'quotation_valid_until',
  'diagnosis_sheet_updated_at',
};

/// Los campos de la cabecera que el formulario cambió, cada uno con el valor
/// que vio: `{campo: {value, expected}}`. [seen] es la cabecera tal como la
/// mandó el servidor ([MechanicJob.persistedHeader], o la del último recibo)
/// y [edited], la que arma el formulario (`toJson(forUpdate: true)`). Un campo
/// que sólo cambia de forma (una fecha con otra precisión, 1 y 1.0) no
/// cuenta como cambio; uno que el servidor no mandó no se toca.
///
/// [shown] es lo que el formulario mostró de un campo cuando no es la
/// cabecera (el relato de la primera bici, que la cabecera repite): ese
/// campo cambió sólo si [edited] difiere de lo mostrado, y el valor esperado
/// sigue siendo el del servidor.
Map<String, Map<String, dynamic>> jobHeaderPatch({
  required Map<String, dynamic> seen,
  required Map<String, dynamic> edited,
  Map<String, dynamic> shown = const {},
}) =>
    {
      for (final column in mechanicJobFormHeaderColumns)
        if (seen.containsKey(column) &&
            edited.containsKey(column) &&
            !_sameColumnValue(
              column,
              shown.containsKey(column) ? shown[column] : seen[column],
              edited[column],
            ))
          column: {'value': edited[column], 'expected': seen[column]},
    };

/// Si lo visto y lo editado son el mismo valor de la columna: una fecha con
/// otra precisión, `1` y `1.0`, o un objeto con las claves en otro orden no
/// son un cambio.
bool _sameColumnValue(String column, Object? seen, Object? edited) {
  if (seen == null || edited == null) return seen == edited;
  if (_timestampColumns.contains(column)) {
    final a = DateTime.tryParse(seen.toString());
    final b = DateTime.tryParse(edited.toString());
    return a != null &&
        b != null &&
        a.millisecondsSinceEpoch == b.millisecondsSinceEpoch;
  }
  return _sameJsonValue(seen, edited);
}

bool _sameJsonValue(Object? a, Object? b) {
  if (a == null || b == null) return a == b;
  if (a is num || b is num) {
    final x = a is num ? a : num.tryParse(a.toString());
    final y = b is num ? b : num.tryParse(b.toString());
    return x != null && y != null && x.toDouble() == y.toDouble();
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_sameJsonValue(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_sameJsonValue(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// Una línea como quedó después del comando.
class SavedJobLine {
  const SavedJobLine({
    required this.id,
    required this.clientKey,
    required this.version,
  });

  final String id;

  /// La llave con que la mandó el formulario; null si el formulario no la
  /// mandó en este guardado.
  final String? clientKey;

  /// Su `updated_at`, en texto (ver [JobLineVersion.version]).
  final String version;
}

/// Una bici del trabajo como quedó después del comando.
class SavedJobBike {
  const SavedJobBike({
    required this.id,
    required this.clientKey,
    required this.bikeId,
    this.row = const {},
  });

  final String id;

  /// La llave con que la mandó el formulario ([JobBikeToSave.clientKey]).
  final String? clientKey;
  final String bikeId;

  /// Lo que quedó de [mechanicJobBikeFormColumns]: lo visto para el
  /// guardado siguiente.
  final Map<String, dynamic> row;
}

/// Lo que hizo el comando con la factura del trabajo (`p_invoice`): la creó,
/// la sincronizó, la dejó intacta por sus pagos, no correspondía, o no pudo
/// (el guardado igual quedó; [errorMessage] dice por qué).
class JobInvoiceOutcome {
  const JobInvoiceOutcome({
    required this.action,
    this.invoiceId,
    this.errorCode,
    this.errorMessage,
  });

  factory JobInvoiceOutcome.fromJson(Map<String, dynamic> json) {
    final error = json['error'];
    return JobInvoiceOutcome(
      action: json['action']?.toString() ?? 'none',
      invoiceId: json['invoice_id']?.toString(),
      errorCode: error is Map ? error['code']?.toString() : null,
      errorMessage: error is Map ? error['message']?.toString() : null,
    );
  }

  /// `created`, `synced`, `protected` (con pagos), `posted` (confirmada sin
  /// pagos: no se reescribe desde el trabajo, y el comando ya rechazó lo que
  /// cambiaría lo que se cobra), `none` o `failed` (el guardado quedó y su
  /// continuación, en la bandeja).
  final String action;
  final String? invoiceId;
  final String? errorCode;
  final String? errorMessage;

  bool get failed => action == 'failed';

  /// La factura ya estaba confirmada y no cambió con este guardado (que sólo
  /// pudo cambiar lo que no se cobra).
  bool get posted => action == 'posted';
}

/// El recibo del comando.
class JobLineSaveResult {
  const JobLineSaveResult({
    required this.operationId,
    required this.replayed,
    required this.lines,
    required this.bikeFacts,
    this.tasksCreated = 0,
    this.header,
    this.jobBikes,
    this.invoice,
  });

  final String operationId;

  /// La misma llave ya se había guardado: es su recibo, no se escribió otra
  /// vez.
  final bool replayed;

  /// Todas las líneas del trabajo y su versión, o null si no se tocaron.
  final List<SavedJobLine>? lines;

  /// La cabecera como quedó ([mechanicJobFormHeaderColumns]): lo que el
  /// formulario vio para el guardado siguiente.
  final Map<String, dynamic>? header;

  /// Las tareas que nacieron con las líneas nuevas. Desde 20260929040000
  /// ninguna nace de la descripción del catálogo: es 0, y sigue en el recibo
  /// porque los recibos guardados lo traen.
  final int tasksCreated;

  /// Las bicis del trabajo como quedaron, o null si no se tocaron.
  final List<SavedJobBike>? jobBikes;

  /// La factura, si el guardado la pidió.
  final JobInvoiceOutcome? invoice;

  /// La ficha que quedó, por bici.
  final Map<String, BikeAggregateSaveResult> bikeFacts;

  factory JobLineSaveResult.fromJson(Map<String, dynamic> json) {
    final operationId = json['operation_id']?.toString() ?? '';
    if (operationId.isEmpty || json['replayed'] is! bool) {
      throw const FormatException('El guardado de líneas no trajo su recibo.');
    }
    final rawLines = json['lines'];
    final rawJobBikes = json['job_bikes'];
    return JobLineSaveResult(
      invoice: json['invoice'] is Map
          ? JobInvoiceOutcome.fromJson(
              Map<String, dynamic>.from(json['invoice'] as Map))
          : null,
      jobBikes: rawJobBikes is List
          ? [
              for (final jobBike in rawJobBikes.cast<Map>())
                SavedJobBike(
                  id: jobBike['id'].toString(),
                  clientKey: jobBike['client_key']?.toString(),
                  bikeId: jobBike['bike_id'].toString(),
                  row: jobBike['row'] is Map
                      ? Map<String, dynamic>.from(jobBike['row'] as Map)
                      : const {},
                ),
            ]
          : null,
      operationId: operationId,
      replayed: json['replayed'] as bool,
      tasksCreated: (json['tasks_created'] as num?)?.toInt() ?? 0,
      header: json['header'] is Map
          ? Map<String, dynamic>.from(json['header'] as Map)
          : null,
      lines: rawLines is List
          ? [
              for (final line in rawLines.cast<Map>())
                SavedJobLine(
                  id: line['id'].toString(),
                  clientKey: line['client_key']?.toString(),
                  version: line['updated_at'].toString(),
                ),
            ]
          : null,
      bikeFacts: {
        for (final entry
            in (json['bike_facts'] as List? ?? const []).cast<Map>())
          entry['bike_id'].toString(): BikeAggregateSaveResult.fromJson(
            Map<String, dynamic>.from(entry['result'] as Map),
          ),
      },
    );
  }
}

/// Otra persona agregó, cambió o borró líneas del trabajo desde que se abrió
/// el formulario: no se guardó nada y no se pisó lo suyo.
class JobLinesChangedException implements Exception {
  const JobLinesChangedException(this.lines);

  /// Cada línea y qué le pasó: `added`, `changed` o `removed`.
  final List<({String lineId, String reason})> lines;

  @override
  String toString() {
    final count = lines.length;
    return 'Otra persona cambió ${count == 1 ? 'una línea' : '$count líneas'} '
        'de este trabajo mientras lo editabas, así que las líneas no se '
        'guardaron. Recarga el trabajo y vuelve a hacer tus cambios.';
  }
}

/// Otra persona agregó, quitó o cambió una bici de este trabajo desde que se
/// abrió el formulario: no se guardó nada y no se pisó lo suyo.
class JobBikesChangedException implements Exception {
  const JobBikesChangedException();

  @override
  String toString() =>
      'Otra persona cambió las bicis de este trabajo (agregó, quitó o '
      'escribió en una) mientras lo editabas, así que no se guardó nada. '
      'Recarga el trabajo y vuelve a hacer tus cambios.';
}

/// El servidor no respondió (sin red, la app a punto de cerrarse, un 504): no
/// se sabe si las líneas se guardaron. El comando quedó respaldado en la
/// bandeja del equipo con su llave, por taller y cuenta, y se reenvía solo;
/// el servidor lo aplica si nunca llegó o devuelve su recibo si ya estaba.
class JobLineSavePendingException implements Exception {
  const JobLineSavePendingException({this.queued = false, this.busy = false});

  /// Espera detrás de otro comando sin respuesta que escribe lo mismo.
  final bool queued;

  /// Otra pestaña lo está enviando.
  final bool busy;

  @override
  String toString() {
    final why = busy
        ? 'Otra pestaña abierta está enviando el guardado de las líneas'
        : queued
            ? 'El guardado de las líneas espera detrás de uno anterior de este '
                'trabajo que sigue sin respuesta'
            : 'El servidor no respondió al guardar las líneas';
    return '$why. Quedaron respaldadas en este equipo, con la cabecera, las '
        'bicis del trabajo y su factura, y se envían solas al volver la '
        'conexión (también al abrir este trabajo). El cambio de estado no se '
        'aplicó: guarda de nuevo cuando haya conexión.';
  }
}

/// El alta de un trabajo nuevo sigue sin respuesta del servidor: el trabajo
/// no está creado. El alta, sus líneas y lo que las seguía quedaron
/// respaldados en la bandeja del equipo con su llave y se envían solos, en
/// orden (cierre del Master Schema, 2026-09-29).
class JobCreationPendingException implements Exception {
  const JobCreationPendingException({this.queued = false, this.busy = false});

  final bool queued;
  final bool busy;

  @override
  String toString() {
    final why = busy
        ? 'Otra pestaña abierta está enviando el alta de este trabajo'
        : queued
            ? 'El alta de este trabajo espera detrás de otro cambio sin '
                'respuesta'
            : 'El servidor no respondió al crear el trabajo';
    return '$why: todavía no está creado. Quedó respaldado en este equipo, '
        'con sus líneas, y se envía solo al volver la conexión. Puedes seguir '
        'editando: el próximo Guardar lo envía primero.';
  }
}

/// El servidor no aceptó el alta del trabajo: no se creó, y sus líneas (y lo
/// que las seguía) salieron de la bandeja sin enviarse.
class JobCreationRejectedException implements Exception {
  const JobCreationRejectedException(this.cause);

  final Object cause;

  @override
  String toString() {
    final cause = this.cause;
    final detail = cause is PostgrestException ? cause.message : '$cause';
    return 'El trabajo no se creó: $detail';
  }
}

/// Otra persona cambió un campo de la cabecera que este guardado también
/// cambiaba: no se guardó nada (ni cabecera, ni líneas, ni ficha) y no se
/// pisó lo suyo.
class JobHeaderChangedException implements Exception {
  const JobHeaderChangedException(this.fields);

  /// Las columnas que chocaron.
  final List<String> fields;

  static const _labels = {
    'customer_id': 'el cliente',
    'bike_id': 'la bicicleta',
    'subject_id': 'el componente',
    'subject_notes': 'la nota del componente',
    'quotation_valid_until': 'la vigencia del presupuesto',
    'priority': 'la prioridad',
    'arrival_date': 'la fecha de ingreso',
    'deadline': 'el plazo',
    'client_request': 'lo que pidió el cliente',
    'diagnosis': 'el diagnóstico',
    'work_performed': 'el trabajo realizado',
    'notes': 'las notas',
    'estimated_duration_hours': 'las horas estimadas',
    'actual_labor_hours': 'las horas trabajadas',
    'requires_approval': 'si requiere aprobación',
    'image_urls': 'las fotos',
    'discount_amount': 'el descuento',
  };

  @override
  String toString() {
    final names = fields.map((field) => _labels[field] ?? field).join(', ');
    return 'Otra persona cambió ${names.isEmpty ? 'la cabecera' : names} de '
        'este trabajo mientras lo editabas, así que no se guardó nada. Recarga '
        'el trabajo y vuelve a hacer tus cambios.';
  }
}

/// La ficha de una bici no tomó lo que confirmó «Configurar» y, como línea y
/// ficha se guardan juntas, las líneas tampoco se guardaron. [cause] es un
/// [BikeTechnicalFactConflict] (la ficha cambió) o un
/// [BikeTechnicalFactRejected] (el servidor no acepta el dato).
class JobLineSaveBikeFactException implements Exception {
  const JobLineSaveBikeFactException({
    required this.bikeId,
    required this.cause,
  });

  final String bikeId;
  final Exception cause;

  @override
  String toString() => cause.toString();
}

/// El error del comando, con lo que el formulario necesita para decidir.
Object classifyJobLineSaveError(Object error) {
  if (error is! PostgrestException) return error;
  final hint = error.hint ?? '';
  if (error.code == 'PT409' && hint == 'job_header_changed') {
    Object? decoded;
    try {
      decoded = error.details is String
          ? jsonDecode(error.details as String)
          : error.details;
    } catch (_) {
      decoded = null;
    }
    return JobHeaderChangedException([
      if (decoded is List)
        for (final field in decoded) field.toString(),
    ]);
  }
  if (error.code == 'PT409' && hint == 'job_bikes_changed') {
    return const JobBikesChangedException();
  }
  if (error.code == 'PT409' && hint == 'job_lines_changed') {
    return JobLinesChangedException([
      for (final entry in _detailList(error.details))
        (
          lineId: entry['line_id']?.toString() ?? '',
          reason: entry['reason']?.toString() ?? '',
        ),
    ]);
  }
  // Sólo lo que dice la ficha: que cambió o que no acepta el dato. Un error
  // pasajero no descarta lo pendiente (el servidor tampoco le pone la pista).
  final code = error.code ?? '';
  final aboutTheFicha = code == 'PT409' ||
      ['22', '23', '42', 'P0'].any((prefix) => code.startsWith(prefix));
  if (hint.startsWith('bike_facts:') && aboutTheFicha) {
    final bikeId = hint.substring('bike_facts:'.length);
    return JobLineSaveBikeFactException(
      bikeId: bikeId,
      cause: error.code == 'PT409'
          ? BikeTechnicalFactConflict([
              for (final entry in _detailList(error.details))
                if (entry['key'] != null) entry['key'].toString(),
            ])
          : BikeTechnicalFactRejected(error.message),
    );
  }
  return error;
}

List<Map> _detailList(Object? details) {
  try {
    final decoded = details is String ? jsonDecode(details) : details;
    if (decoded is List) return decoded.whereType<Map>().toList();
  } catch (_) {
    // El detalle sólo nombra lo que chocó; sin él, el error igual se dice.
  }
  return const [];
}
