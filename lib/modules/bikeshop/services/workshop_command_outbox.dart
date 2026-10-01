import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

// El mismo coordinador que el carrito de la tienda: Web Locks entre pestañas
// en la web, una cola compartida por el proceso en el resto.
import '../../../public_store/services/cart_lock.dart';
import '../../../public_store/services/cart_lock_stub.dart' as process_lock;
import 'mechanic_job_status_transition_coordinator.dart';
import 'mechanic_job_warranty_command_coordinator.dart';
import '../../../shared/services/tenant_service.dart';

/// Bandeja local de los comandos del taller que escriben la bici y las líneas
/// del trabajo (BIKE_WORKSHOP_MASTER_SCHEMA.md, ítems 3 y 4 de la cola).
///
/// Un comando se respalda en el dispositivo **antes** de enviarse y sale de la
/// bandeja sólo cuando el servidor dio una respuesta definitiva. Si la app se
/// cierra, se cuelga o pierde la red a mitad de camino, el comando sigue aquí
/// con su llave, y la próxima sesión lo reenvía: el servidor lo aplica si
/// nunca llegó, o devuelve su recibo (`replayed`) si ya estaba escrito.
///
/// Cada intento queda anotado (también sin red) y se entrega a
/// `record_workshop_command_attempts_v1` para que soporte distinga sin red,
/// rechazado, ficha cambiada, escrito y reconciliado. Las fotos subidas para
/// una bici que nunca se guardó se borran cuando nadie puede reclamarlas.

enum WorkshopCommandKind {
  bikeAggregateSave('bike_aggregate_save'),

  /// Las líneas del trabajo y lo que «Configurar» confirmó de la bici, en una
  /// transacción (`save_mechanic_job_lines_v1`, ítem 4).
  jobLineSave('job_line_save'),

  /// La factura de un guardado del trabajo ya escrito cuyo recibo dijo
  /// `failed` (`continue_mechanic_job_invoice_v1`): se vuelve a intentar sin
  /// otro Guardar, también después de cerrar la app (revisión del
  /// 2026-09-28).
  jobInvoiceContinuation('job_invoice_continuation'),

  /// El cambio de estado del trabajo (`transition_mechanic_job_status`), en
  /// la cola del trabajo: nunca se adelanta a un guardado pendiente del mismo
  /// trabajo, y un cierre de la app entre el guardado y el estado no lo
  /// pierde (checkpoint del cierre, 2026-09-28).
  jobStatusTransition('job_status_transition'),

  /// La decisión de garantía (`decide_mechanic_job_warranty_claim`), en la
  /// cola del trabajo: detrás del guardado de líneas que la acompaña y antes
  /// del cambio de estado. Es la dueña del documento de la garantía, así que
  /// un cierre entre el guardado y la decisión dejaba las líneas sin decisión
  /// ni documento (punto 2 del cierre, 2026-09-29).
  jobWarrantyDecision('job_warranty_decision'),

  /// El alta de un trabajo nuevo (`create_mechanic_job_v1`), con el id que
  /// eligió el formulario como llave. Se respalda con sus líneas (y, en una
  /// garantía nueva, con su registro) antes del primer envío: un cierre entre
  /// el alta y su respuesta ya no deja un trabajo sin líneas ni factura
  /// (cierre del Master Schema, 2026-09-29).
  jobCreate('job_create'),

  /// El registro de la garantía de un trabajo nuevo
  /// (`register_mechanic_job_warranty_claim`), detrás de sus líneas: el
  /// trabajo original elegido vive sólo en el formulario hasta registrarse.
  jobWarrantyRegistration('job_warranty_registration');

  const WorkshopCommandKind(this.wireName);

  final String wireName;

  static WorkshopCommandKind? fromWire(Object? value) {
    for (final kind in values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

/// Cómo terminó un intento. Sólo [offline] deja el comando pendiente.
enum WorkshopCommandOutcome {
  /// El servidor respondió con lo escrito.
  committed,

  /// La respuesta se perdió, pero el recibo prueba que se escribió.
  reconciled,

  /// El servidor lo rechazó y no aplicó nada.
  rejected,

  /// La bici cambió desde que se cargó; el servidor no aplicó nada.
  stale,

  /// No hubo respuesta: sigue pendiente con su llave.
  offline,

  /// Alguien lo descartó antes de que llegara.
  discarded;

  bool get wrote => this == committed || this == reconciled;

  bool get isFinal => this != offline;
}

enum WorkshopCommandTrigger { save, retry, resume, discard }

/// Taller y persona dueños de una bandeja: otra cuenta en el mismo equipo no
/// ve ni reenvía lo pendiente de ésta.
@immutable
class WorkshopCommandScope {
  const WorkshopCommandScope({required this.tenantId, required this.userId});

  final String tenantId;
  final String userId;

  /// Prefijo de las entradas de esta bandeja: una por comando, foto e
  /// intento, para que dos pestañas que escriben a la vez no se borren lo
  /// que agregó la otra (revisión de Codex, 2026-09-28).
  String get storageKey => 'workshop-command-outbox-v2:$tenantId:$userId';

  @override
  bool operator ==(Object other) =>
      other is WorkshopCommandScope &&
      other.tenantId == tenantId &&
      other.userId == userId;

  @override
  int get hashCode => Object.hash(tenantId, userId);
}

/// Un comando respaldado: los parámetros exactos del RPC y su llave.
@immutable
class PendingWorkshopCommand {
  const PendingWorkshopCommand({
    required this.operationKey,
    required this.kind,
    required this.params,
    required this.createdAt,
    this.bikeId,
    this.jobId,
    this.label,
    this.attempts = 0,
    this.lastAttemptAt,
    this.lastOutcome,
    this.lastError,
    this.lastErrorCode,
    this.inFlight = false,
    this.lastTrigger,
    this.inFlightSession,
    this.dependsOn,
  });

  final String operationKey;
  final WorkshopCommandKind kind;
  final Map<String, dynamic> params;
  final DateTime createdAt;
  final String? bikeId;
  final String? jobId;

  /// Cómo nombrar la bici en un aviso («Trek Marlin 5»).
  final String? label;
  final int attempts;
  final DateTime? lastAttemptAt;
  final WorkshopCommandOutcome? lastOutcome;
  final String? lastError;

  /// El código del último intento (`invoice_failed:23514`, `55P03`…).
  final String? lastErrorCode;

  /// Una continuación de factura que ya falló [invoiceRetryPause] veces por
  /// un error del dato no se reintenta sola cada hora: sigue en la bandeja y
  /// se vuelve a intentar al abrir el trabajo o al iniciar sesión (revisión
  /// de Codex, 2026-09-28).
  static const int invoiceRetryPause = 3;

  bool get pausedForInvoiceData =>
      kind == WorkshopCommandKind.jobInvoiceContinuation &&
      (lastErrorCode?.startsWith('invoice_failed:') ?? false) &&
      attempts >= invoiceRetryPause;

  /// Un envío empezó y no terminó en este registro: si la app murió a mitad,
  /// el próximo intento anota ése como interrumpido.
  final bool inFlight;
  final WorkshopCommandTrigger? lastTrigger;

  /// La sesión que lo está enviando: si sigue viva (otra pestaña), no se
  /// reenvía ni se anota como interrumpido.
  final String? inFlightSession;

  /// La llave del comando que tiene que escribirse antes que éste: la
  /// decisión de garantía que acompaña un guardado de líneas, el cambio de
  /// estado que sigue a esa decisión. Se respaldan en la misma escritura que
  /// ése y esperan en la bandeja; si ése se escribe, dejan de depender de él;
  /// si el servidor no lo aplica o alguien lo descarta, salen con él sin
  /// enviarse (punto 2 del cierre, 2026-09-29).
  final String? dependsOn;

  /// Este comando detrás de [prerequisite]: depende de él y se respalda un
  /// milisegundo después, para que la cola lo ordene igual en cada puerta.
  PendingWorkshopCommand after(PendingWorkshopCommand prerequisite) =>
      PendingWorkshopCommand(
        operationKey: operationKey,
        kind: kind,
        params: params,
        createdAt: prerequisite.createdAt.add(const Duration(milliseconds: 1)),
        bikeId: bikeId,
        jobId: jobId,
        label: label,
        dependsOn: prerequisite.operationKey,
      );

  /// Lo que el comando escribe y otro comando del equipo también puede
  /// escribir: la bici que guarda, el trabajo cuyas líneas guarda y las bicis
  /// cuya ficha toca. Dos comandos que comparten algo van en orden, porque el
  /// segundo se armó sobre lo que el primero quizá ya cambió.
  Set<String> get queueKeys {
    final facts =
        kind == WorkshopCommandKind.jobLineSave ? params['p_bike_facts'] : null;
    return {
      if (bikeId != null) 'bike:$bikeId',
      if ((kind == WorkshopCommandKind.jobLineSave ||
              kind == WorkshopCommandKind.jobStatusTransition ||
              kind == WorkshopCommandKind.jobWarrantyDecision ||
              kind == WorkshopCommandKind.jobCreate ||
              kind == WorkshopCommandKind.jobWarrantyRegistration) &&
          jobId != null)
        'job:$jobId',
      if (facts is List)
        for (final entry in facts)
          if (entry is Map && entry['bike_id'] is String)
            'bike:${entry['bike_id']}',
    };
  }

  /// Las fotos que el comando deja en la bici, o los adjuntos que deja en el
  /// trabajo (la cabecera del guardado, si los cambió).
  List<String> get imageUrls {
    final Object? urls = switch (kind) {
      WorkshopCommandKind.bikeAggregateSave => switch (
            params['p_bike_payload']) {
          final Map bike => bike['image_urls'],
          _ => null,
        },
      WorkshopCommandKind.jobLineSave => switch (params['p_header']) {
          final Map header => switch (header['image_urls']) {
              final Map field => field['value'],
              _ => null,
            },
          _ => null,
        },
      // Los adjuntos que el alta deja en el trabajo nuevo: mientras siga
      // pendiente, el barrido no los borra.
      WorkshopCommandKind.jobCreate => switch (params['p_job']) {
          final Map job => job['image_urls'],
          _ => null,
        },
      WorkshopCommandKind.jobInvoiceContinuation ||
      WorkshopCommandKind.jobStatusTransition ||
      WorkshopCommandKind.jobWarrantyDecision ||
      WorkshopCommandKind.jobWarrantyRegistration =>
        null,
    };
    return urls is List ? urls.map((url) => url.toString()).toList() : const [];
  }

  /// De [imageUrls], las que el comando agrega: en un guardado de líneas, las
  /// que el formulario no vio ya en el trabajo; en un alta o una bici, todas.
  /// Un adjunto que el trabajo ya muestra no es nuevo y no se juzga.
  List<String> get newImageUrls {
    final urls = imageUrls;
    if (kind != WorkshopCommandKind.jobLineSave) return urls;
    final header = params['p_header'];
    final field = header is Map ? header['image_urls'] : null;
    final seen = field is Map ? field['expected'] : null;
    if (seen is! List) return urls;
    final shown = seen.map((url) => '$url').toSet();
    return [
      for (final url in urls)
        if (!shown.contains(url)) url
    ];
  }

  PendingWorkshopCommand copyWith({
    int? attempts,
    DateTime? lastAttemptAt,
    WorkshopCommandOutcome? lastOutcome,
    String? lastError,
    String? lastErrorCode,
    bool? inFlight,
    WorkshopCommandTrigger? lastTrigger,
    String? inFlightSession,
    String? dependsOn,
    bool clearDependsOn = false,
    DateTime? createdAt,
  }) =>
      PendingWorkshopCommand(
        operationKey: operationKey,
        kind: kind,
        params: params,
        createdAt: createdAt ?? this.createdAt,
        bikeId: bikeId,
        jobId: jobId,
        label: label,
        attempts: attempts ?? this.attempts,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
        lastOutcome: lastOutcome ?? this.lastOutcome,
        lastError: lastError ?? this.lastError,
        lastErrorCode: lastErrorCode ?? this.lastErrorCode,
        inFlight: inFlight ?? this.inFlight,
        lastTrigger: lastTrigger ?? this.lastTrigger,
        inFlightSession: inFlightSession ?? this.inFlightSession,
        dependsOn: clearDependsOn ? null : dependsOn ?? this.dependsOn,
      );

  Map<String, dynamic> toJson() => {
        'operation_key': operationKey,
        'kind': kind.wireName,
        'params': params,
        'created_at': createdAt.toUtc().toIso8601String(),
        'bike_id': bikeId,
        'job_id': jobId,
        'label': label,
        'attempts': attempts,
        'last_attempt_at': lastAttemptAt?.toUtc().toIso8601String(),
        'last_outcome': lastOutcome?.name,
        'last_error': lastError,
        'last_error_code': lastErrorCode,
        'in_flight': inFlight,
        'last_trigger': lastTrigger?.name,
        'in_flight_session': inFlightSession,
        if (dependsOn != null) 'depends_on': dependsOn,
      };

  /// La continuación de la factura de [save], un guardado del trabajo ya
  /// escrito cuyo recibo dijo `failed`. Sólo lleva la llave del guardado: el
  /// servidor hace la factura con lo que el trabajo tiene ahora.
  static PendingWorkshopCommand invoiceContinuationOf(
    PendingWorkshopCommand save, {
    required DateTime createdAt,
  }) =>
      PendingWorkshopCommand(
        operationKey: '${save.operationKey}:factura',
        kind: WorkshopCommandKind.jobInvoiceContinuation,
        params: {'p_operation_key': save.operationKey},
        createdAt: createdAt,
        jobId: save.jobId,
        label: save.label,
      );

  static PendingWorkshopCommand? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = WorkshopCommandKind.fromWire(json['kind']);
    final key = json['operation_key'];
    final params = json['params'];
    final createdAt = DateTime.tryParse('${json['created_at']}');
    if (kind == null || key is! String || params is! Map || createdAt == null) {
      return null;
    }
    return PendingWorkshopCommand(
      operationKey: key,
      kind: kind,
      params: Map<String, dynamic>.from(params),
      createdAt: createdAt,
      bikeId: json['bike_id'] as String?,
      jobId: json['job_id'] as String?,
      label: json['label'] as String?,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      lastAttemptAt: DateTime.tryParse('${json['last_attempt_at']}'),
      lastOutcome: WorkshopCommandOutcome.values
          .where((outcome) => outcome.name == json['last_outcome'])
          .firstOrNull,
      lastError: json['last_error'] as String?,
      lastErrorCode: json['last_error_code'] as String?,
      inFlight: json['in_flight'] == true,
      inFlightSession: json['in_flight_session'] as String?,
      lastTrigger: WorkshopCommandTrigger.values
          .where((trigger) => trigger.name == json['last_trigger'])
          .firstOrNull,
      dependsOn: json['depends_on'] as String?,
    );
  }
}

/// Una foto de bici, o un adjunto de trabajo, subido (o por subir) que todavía
/// no quedó guardado en su bici o su trabajo. [operationKey] es el comando que
/// la lleva, si ya se envió.
@immutable
class PendingBikeImage {
  const PendingBikeImage({
    required this.bucket,
    required this.objectPath,
    required this.publicUrl,
    required this.createdAt,
    this.bikeId,
    this.jobId,
    this.operationKey,
    this.uploaded = false,
    this.ownerSession,
    this.ownerForm,
    this.deletingAt,
    this.deletedAt,
  }) : assert(bikeId != null || jobId != null);

  final String bucket;
  final String objectPath;
  final String publicUrl;

  /// De quién es: una bici o un trabajo.
  final String? bikeId;
  final String? jobId;
  final DateTime createdAt;
  final String? operationKey;
  final bool uploaded;

  /// La sesión de la app (el proceso) y el formulario que la subieron. Un
  /// formulario sólo libera las suyas, y el barrido sólo toca las de sesiones
  /// que ya no existen (revisión de Codex, 2026-09-28).
  final String? ownerSession;
  final String? ownerForm;

  /// Desde cuándo se está borrando de Storage. Se marca bajo el candado de la
  /// bandeja, en la misma escritura que decide que nadie la lleva, antes del
  /// borrado: desde ahí ningún comando la acepta, aunque el borrado falle o
  /// la app se cierre a mitad (el archivo puede ya no estar). No se desmarca;
  /// el barrido reintenta el borrado (carrera del barrido, 2026-09-29).
  final DateTime? deletingAt;

  /// Cuándo se borró: queda como lápida [WorkshopCommandOutbox.removedImageMemory]
  /// para que una ventana que la tenía en un formulario no la guarde.
  final DateTime? deletedAt;

  /// Borrada o borrándose: ningún comando la lleva.
  bool get retired => deletingAt != null || deletedAt != null;

  PendingBikeImage copyWith({
    String? operationKey,
    bool clearOperationKey = false,
    bool? uploaded,
    String? ownerSession,
    DateTime? deletingAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) =>
      PendingBikeImage(
        bucket: bucket,
        objectPath: objectPath,
        publicUrl: publicUrl,
        bikeId: bikeId,
        jobId: jobId,
        createdAt: createdAt,
        operationKey:
            clearOperationKey ? null : operationKey ?? this.operationKey,
        uploaded: uploaded ?? this.uploaded,
        ownerSession: ownerSession ?? this.ownerSession,
        ownerForm: ownerForm,
        deletingAt: deletingAt ?? this.deletingAt,
        deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      );

  Map<String, dynamic> toJson() => {
        'bucket': bucket,
        'object_path': objectPath,
        'public_url': publicUrl,
        'bike_id': bikeId,
        'job_id': jobId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'operation_key': operationKey,
        'uploaded': uploaded,
        'owner_session': ownerSession,
        'owner_form': ownerForm,
        if (deletingAt != null)
          'deleting_at': deletingAt!.toUtc().toIso8601String(),
        if (deletedAt != null)
          'deleted_at': deletedAt!.toUtc().toIso8601String(),
      };

  static PendingBikeImage? fromJson(Object? json) {
    if (json is! Map) return null;
    final createdAt = DateTime.tryParse('${json['created_at']}');
    final bucket = json['bucket'];
    final path = json['object_path'];
    final url = json['public_url'];
    final bikeId = json['bike_id'];
    final jobId = json['job_id'];
    if (bucket is! String ||
        path is! String ||
        url is! String ||
        (bikeId is! String && jobId is! String) ||
        createdAt == null) {
      return null;
    }
    return PendingBikeImage(
      bucket: bucket,
      objectPath: path,
      publicUrl: url,
      bikeId: bikeId is String ? bikeId : null,
      jobId: jobId is String ? jobId : null,
      createdAt: createdAt,
      operationKey: json['operation_key'] as String?,
      uploaded: json['uploaded'] == true,
      ownerSession: json['owner_session'] as String?,
      ownerForm: json['owner_form'] as String?,
      deletingAt: json['deleting_at'] == null
          ? null
          : DateTime.tryParse('${json['deleting_at']}'),
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.tryParse('${json['deleted_at']}'),
    );
  }
}

/// Un intento, tal como lo recibe `record_workshop_command_attempts_v1`.
@immutable
class WorkshopCommandAttempt {
  const WorkshopCommandAttempt({
    required this.attemptId,
    required this.operationKey,
    required this.kind,
    required this.attemptNumber,
    required this.trigger,
    required this.outcome,
    required this.startedAt,
    required this.durationMs,
    this.errorCode,
    this.errorMessage,
    this.bikeId,
    this.jobId,
    this.clientPlatform,
    this.appVersion,
  });

  final String attemptId;
  final String operationKey;
  final WorkshopCommandKind kind;
  final int attemptNumber;
  final WorkshopCommandTrigger trigger;
  final WorkshopCommandOutcome outcome;
  final DateTime startedAt;
  final int durationMs;
  final String? errorCode;
  final String? errorMessage;
  final String? bikeId;
  final String? jobId;
  final String? clientPlatform;
  final String? appVersion;

  Map<String, dynamic> toJson() => {
        'attempt_id': attemptId,
        'operation_key': operationKey,
        'command_kind': kind.wireName,
        'attempt_number': attemptNumber,
        'trigger': trigger.name,
        'outcome': outcome.name,
        'error_code': errorCode,
        'error_message': errorMessage,
        'bike_id': bikeId,
        'job_id': jobId,
        'client_started_at': startedAt.toUtc().toIso8601String(),
        'duration_ms': durationMs,
        'client_platform': clientPlatform,
        'app_version': appVersion,
      };
}

/// El resultado de un intento, para quien lo pidió y para los avisos.
@immutable
class WorkshopCommandRun {
  const WorkshopCommandRun({
    required this.command,
    required this.outcome,
    required this.trigger,
    this.response,
    this.error,
    this.droppedFollowUps = const [],
  });

  final PendingWorkshopCommand command;
  final WorkshopCommandOutcome outcome;
  final WorkshopCommandTrigger trigger;

  /// Lo que dependía de [command] y salió de la bandeja sin enviarse porque
  /// [command] no se escribió (la decisión de garantía y el cambio de estado
  /// que acompañaban un guardado rechazado).
  final List<PendingWorkshopCommand> droppedFollowUps;

  /// Lo que devolvió el servidor (o su recibo), si escribió.
  final Map<String, dynamic>? response;

  /// El error del intento, si no escribió.
  final Object? error;
}

class WorkshopOutboxPersistenceException implements Exception {
  const WorkshopOutboxPersistenceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// La sesión de la app ya no es la del taller y la persona de la bandeja
/// (cerró sesión, entró otra cuenta): no se envía nada con otra identidad.
class WorkshopScopeChangedException implements Exception {
  const WorkshopScopeChangedException();

  @override
  String toString() => 'La sesión cambió; lo pendiente espera a su dueño.';
}

/// Lo que decidió quien crea una bici nueva: las altas pendientes de ese
/// cliente que vio y dijo que son otra bici. La bandeja la vuelve a comprobar
/// al respaldar el alta, con la misma lectura con que la escribe.
class WorkshopCreationGuard {
  const WorkshopCreationGuard({
    required this.customerId,
    required this.acknowledgedBikeIds,
  });

  final String customerId;
  final Set<String> acknowledgedBikeIds;
}

/// Mientras se guardaba, quedó en la bandeja otra alta de ese cliente que
/// nadie vio (otra pestaña), o una que esta versión no sabe leer: el alta no
/// se respalda ni se envía.
class WorkshopPendingCreationException implements Exception {
  const WorkshopPendingCreationException({
    required this.labels,
    required this.unreadable,
  });

  final List<String> labels;
  final bool unreadable;

  @override
  String toString() => unreadable
      ? 'Hay un cambio pendiente de este cliente que esta versión no sabe '
          'leer; puede ser esta misma bicicleta.'
      : 'Mientras guardabas quedó pendiente otra bicicleta nueva de este '
          'cliente (${labels.join(', ')}).';
}

/// Otra pestaña abierta está enviando este mismo comando: su resultado lo
/// saca de la bandeja o lo deja pendiente.
/// No hay un comando pendiente con esa llave: nunca se respaldó, o otra
/// pestaña o la reanudación ya lo resolvió y lo sacó de la bandeja. Su
/// recibo dice cuál ([WorkshopCommandOutbox.runOrReconcile]).
class WorkshopCommandNotPendingError extends StateError {
  WorkshopCommandNotPendingError(this.operationKey)
      : super('No hay un cambio pendiente con la llave $operationKey.');

  final String operationKey;
}

/// Un comando lleva un adjunto nuevo que la bandeja ya borró o está borrando
/// ([removedUrls]), o que se subió para otro trabajo u otra bici
/// ([foreignUrls]). No se respalda: el trabajo o la bici quedaría mostrando
/// un archivo que no existe, o uno ajeno.
class WorkshopImageUnavailableException implements Exception {
  const WorkshopImageUnavailableException({
    this.removedUrls = const [],
    this.foreignUrls = const [],
  });

  final List<String> removedUrls;
  final List<String> foreignUrls;

  @override
  String toString() {
    final parts = [
      if (removedUrls.isNotEmpty)
        removedUrls.length == 1
            ? 'Un adjunto nuevo ya no está: se borró de este equipo porque '
                'la ventana estuvo inactiva mucho rato.'
            : '${removedUrls.length} adjuntos nuevos ya no están: se borraron '
                'de este equipo porque la ventana estuvo inactiva mucho rato.',
      if (foreignUrls.isNotEmpty)
        foreignUrls.length == 1
            ? 'Un adjunto se subió para otro trabajo o bici.'
            : '${foreignUrls.length} adjuntos se subieron para otro trabajo o '
                'bici.',
    ];
    return '${parts.join(' ')} No se guardó nada: vuelve a adjuntarlo y '
        'guarda.';
  }
}

/// El recibo de esa llave es de otro contenido: esa llave ya escribió otra
/// cosa y este comando nunca se va a escribir con ella.
class WorkshopCommandContentConflictException implements Exception {
  const WorkshopCommandContentConflictException();

  @override
  String toString() =>
      'esa llave ya se usó con otro contenido; lo que se escribió con ella '
      'está en el servidor (búscalo en Trabajos)';
}

class WorkshopCommandBusyException implements Exception {
  const WorkshopCommandBusyException();

  @override
  String toString() => 'Se está enviando desde otra pestaña abierta.';
}

/// El comando quedó en la bandeja detrás de otro de la misma bici que sigue
/// sin respuesta: se envía cuando ése se resuelva.
class WorkshopCommandQueuedException implements Exception {
  const WorkshopCommandQueuedException();

  @override
  String toString() =>
      'Espera a un cambio anterior de esta bici que sigue sin respuesta.';
}

/// Sin red de verdad (o sin respuesta): el comando no llegó a ejecutarse o no
/// se sabe. Lo usa también la falla de depuración.
/// La continuación llegó al servidor y la factura sigue sin poder hacerse
/// (el recibo sigue en `failed`): queda pendiente y se vuelve a intentar.
class WorkshopInvoicePendingException implements Exception {
  const WorkshopInvoicePendingException({this.code, this.message});

  final String? code;
  final String? message;

  @override
  String toString() => message?.isNotEmpty == true
      ? message!
      : 'La factura del trabajo sigue pendiente.';
}

/// El comando del que dependía éste no se escribió (el servidor no lo aplicó
/// o alguien lo descartó): éste salió de la bandeja sin enviarse.
class WorkshopCommandPrerequisiteNotWrittenException implements Exception {
  const WorkshopCommandPrerequisiteNotWrittenException(this.prerequisite);

  /// Null cuando ya no está en la bandeja: un corte a mitad de respaldarlo o
  /// de sacarlo (revisión de Codex, 2026-09-29).
  final PendingWorkshopCommand? prerequisite;

  @override
  String toString() => switch (prerequisite?.kind) {
        WorkshopCommandKind.jobLineSave =>
          'El guardado de las líneas que acompañaba no se guardó.',
        WorkshopCommandKind.jobWarrantyDecision =>
          'La decisión de garantía que iba antes no se aplicó.',
        null => 'Lo que iba antes no quedó guardado en este equipo.',
        _ => 'El cambio que iba antes no se guardó.',
      };
}

class WorkshopCommandTransportException implements Exception {
  const WorkshopCommandTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Dónde se guarda la bandeja: una entrada por comando, foto e intento bajo
/// el prefijo del taller y la persona.
abstract interface class WorkshopOutboxStore {
  Future<Map<String, String>> readAll(String prefix);

  Future<void> write(String key, String value);

  Future<void> remove(String key);
}

class SharedPreferencesWorkshopOutboxStore implements WorkshopOutboxStore {
  SharedPreferences? _preferences;

  Future<SharedPreferences> _instance() async =>
      _preferences ??= await SharedPreferences.getInstance();

  @override
  Future<Map<String, String>> readAll(String prefix) async {
    try {
      final preferences = await _instance();
      // Otra pestaña (web) pudo escribir la bandeja desde la última lectura.
      await preferences.reload();
      return {
        for (final key in preferences.getKeys())
          if (key.startsWith(prefix) && preferences.getString(key) != null)
            key: preferences.getString(key)!,
      };
    } catch (error) {
      throw WorkshopOutboxPersistenceException(
        'No se pudo leer lo pendiente en este equipo ($error).',
      );
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final bool written;
    try {
      final preferences = await _instance();
      // Sólo cuenta lo que dice la plataforma: releer el caché justo después
      // puede toparse con un `reload()` ajeno y dar una falla falsa.
      written = await preferences.setString(key, value);
    } catch (error) {
      throw WorkshopOutboxPersistenceException(
        'No se pudo respaldar el cambio en este equipo ($error).',
      );
    }
    if (!written) {
      throw const WorkshopOutboxPersistenceException(
        'No se pudo respaldar el cambio en este equipo antes de enviarlo.',
      );
    }
  }

  @override
  Future<void> remove(String key) async {
    final bool removed;
    try {
      final preferences = await _instance();
      removed = await preferences.remove(key);
    } catch (error) {
      throw WorkshopOutboxPersistenceException(
        'No se pudo actualizar lo pendiente en este equipo ($error).',
      );
    }
    // Como al escribir: un borrado que la plataforma no hizo detiene los
    // siguientes. Si el alta no salió y sus líneas sí, la reanudación la
    // enviaba sola (segunda revisión de Codex del alta, 2026-09-29).
    if (!removed) {
      throw const WorkshopOutboxPersistenceException(
        'No se pudo actualizar lo pendiente en este equipo.',
      );
    }
  }
}

/// Lo que la bandeja necesita del servidor.
abstract interface class WorkshopCommandTransport {
  /// Si la sesión de la app sigue siendo la de [scope].
  bool isCurrent(WorkshopCommandScope scope);

  Future<Map<String, dynamic>> send(
    WorkshopCommandKind kind,
    Map<String, dynamic> params,
  );

  /// Tras una respuesta perdida: el recibo del comando si el servidor lo
  /// escribió, o null si no lo tiene.
  Future<Map<String, dynamic>?> probe(
    WorkshopCommandScope scope,
    PendingWorkshopCommand command,
  );

  Future<void> recordAttempts(List<Map<String, dynamic>> attempts);

  /// De [urls], las que alguna bici del taller ya tiene como foto.
  Future<Set<String>> referencedImageUrls(
    WorkshopCommandScope scope,
    List<String> urls,
  );

  Future<void> removeImages(String bucket, List<String> objectPaths);
}

class SupabaseWorkshopCommandTransport implements WorkshopCommandTransport {
  SupabaseClient get _client => Supabase.instance.client;

  @override

  /// La cuenta **y** el taller activos son los de la bandeja. Con la misma
  /// cuenta en otro taller (su perfil activo cambió), lo de éste ni se envía
  /// ni se da por rechazado: el servidor lo buscaría en el otro taller y
  /// contestaría que no existe (revisión de Codex, 2026-09-28).
  bool isCurrent(WorkshopCommandScope scope) =>
      _client.auth.currentUser?.id == scope.userId &&
      TenantService().currentTenantId == scope.tenantId;

  static const Map<WorkshopCommandKind, String> _rpcByKind = {
    WorkshopCommandKind.bikeAggregateSave: 'save_bike_aggregate',
    WorkshopCommandKind.jobLineSave: 'save_mechanic_job_lines_v1',
    WorkshopCommandKind.jobInvoiceContinuation:
        'continue_mechanic_job_invoice_v1',
    WorkshopCommandKind.jobStatusTransition: 'transition_mechanic_job_status',
    WorkshopCommandKind.jobWarrantyDecision:
        'decide_mechanic_job_warranty_claim',
    WorkshopCommandKind.jobCreate: 'create_mechanic_job_v1',
    WorkshopCommandKind.jobWarrantyRegistration:
        'register_mechanic_job_warranty_claim',
  };

  @override
  Future<Map<String, dynamic>> send(
    WorkshopCommandKind kind,
    Map<String, dynamic> params,
  ) async {
    final data = await _client.rpc(_rpcByKind[kind]!, params: params);
    if (data is! Map) {
      throw FormatException('Respuesta inválida de ${_rpcByKind[kind]}');
    }
    return Map<String, dynamic>.from(data);
  }

  @override
  Future<Map<String, dynamic>?> probe(
    WorkshopCommandScope scope,
    PendingWorkshopCommand command,
  ) async {
    switch (command.kind) {
      case WorkshopCommandKind.bikeAggregateSave:
        final data = await _client.rpc(
          'get_bike_aggregate_save_operation',
          params: {'p_operation_key': command.operationKey},
        );
        return data is Map ? Map<String, dynamic>.from(data) : null;
      case WorkshopCommandKind.jobLineSave:
        final data = await _client.rpc(
          'get_mechanic_job_line_save_v1',
          params: {'p_operation_key': command.operationKey},
        );
        return data is Map ? Map<String, dynamic>.from(data) : null;
      case WorkshopCommandKind.jobInvoiceContinuation:
        // Repetirla no hace dos facturas: sin respuesta, se vuelve a llamar.
        return null;
      case WorkshopCommandKind.jobStatusTransition:
        final row = await _client
            .from('mechanic_job_status_transition_events')
            .select()
            .eq('tenant_id', scope.tenantId)
            .eq('job_id', '${command.params['p_job_id']}')
            .eq('operation_key', command.operationKey)
            .maybeSingle();
        return row == null ? null : Map<String, dynamic>.from(row);
      case WorkshopCommandKind.jobWarrantyDecision:
        // El evento inmutable de la decisión, por taller, trabajo y llave.
        final row = await _client
            .from('mechanic_job_warranty_claim_events')
            .select()
            .eq('tenant_id', scope.tenantId)
            .eq('warranty_job_id', '${command.params['p_warranty_job_id']}')
            .eq('operation_key', command.operationKey)
            .eq('event_type', 'decision')
            .maybeSingle();
        return row == null ? null : Map<String, dynamic>.from(row);
      case WorkshopCommandKind.jobCreate:
        // El recibo del alta, por su llave, del taller de quien pregunta.
        final data = await _client.rpc(
          'get_mechanic_job_creation_v1',
          params: {
            'p_operation_key': command.operationKey,
            'p_job': command.params['p_job'],
          },
        );
        return data is Map ? Map<String, dynamic>.from(data) : null;
      case WorkshopCommandKind.jobWarrantyRegistration:
        final row = await _client
            .from('mechanic_job_warranty_claim_events')
            .select()
            .eq('tenant_id', scope.tenantId)
            .eq('warranty_job_id', '${command.params['p_warranty_job_id']}')
            .eq('operation_key', command.operationKey)
            .eq('event_type', 'registration')
            .maybeSingle();
        return row == null ? null : Map<String, dynamic>.from(row);
    }
  }

  @override
  Future<void> recordAttempts(List<Map<String, dynamic>> attempts) async {
    await _client.rpc(
      'record_workshop_command_attempts_v1',
      params: {'p_attempts': attempts},
    );
  }

  @override
  Future<Set<String>> referencedImageUrls(
    WorkshopCommandScope scope,
    List<String> urls,
  ) async {
    if (urls.isEmpty) return const {};
    final inList = await _client
        .from('bikes')
        .select('image_urls, image_url')
        .eq('tenant_id', scope.tenantId)
        .overlaps('image_urls', urls);
    final primary = await _client
        .from('bikes')
        .select('image_urls, image_url')
        .eq('tenant_id', scope.tenantId)
        .inFilter('image_url', urls);
    // Los adjuntos de un trabajo también: uno que algún trabajo muestra nunca
    // se borra.
    final inJobs = await _client
        .from('mechanic_jobs')
        .select('image_urls')
        .eq('tenant_id', scope.tenantId)
        .overlaps('image_urls', urls);
    final referenced = <String>{};
    for (final row in inJobs) {
      final list = row['image_urls'];
      if (list is List) referenced.addAll(list.map((url) => url.toString()));
    }
    for (final row in [...inList, ...primary]) {
      final list = row['image_urls'];
      if (list is List) referenced.addAll(list.map((url) => url.toString()));
      final single = row['image_url'];
      if (single is String) referenced.add(single);
    }
    return referenced.intersection(urls.toSet());
  }

  @override
  Future<void> removeImages(String bucket, List<String> objectPaths) async {
    if (objectPaths.isEmpty) return;
    await _client.storage.from(bucket).remove(objectPaths);
  }
}

/// Sólo en depuración: la próxima llamada al servidor falla como si se
/// hubiera ido la red, antes de enviarse o después de escribir. Es el arnés
/// para probar la bandeja en la app real sin cortar la red del equipo
/// (docs/development/AGENT_MACOS_APP_CONTROL.md).
enum WorkshopOutboxDebugFault { offlineBeforeSend, loseResponseAfterCommit }

/// El pedido de la decisión de garantía que respalda [command], o null si sus
/// parámetros no alcanzan para armarlo.
MechanicJobWarrantyCommandRequest? warrantyDecisionRequestOf(
  PendingWorkshopCommand command,
) {
  if (command.kind != WorkshopCommandKind.jobWarrantyDecision) return null;
  final params = command.params;
  try {
    return MechanicJobWarrantyCommandRequest.decision(
      warrantyJobId: '${params['p_warranty_job_id'] ?? ''}',
      outcome: '${params['p_outcome'] ?? ''}',
      reason: params['p_reason'] as String?,
      operationKey: command.operationKey,
    );
  } on ArgumentError {
    return null;
  }
}

/// El pedido del registro de garantía que respalda [command], o null si sus
/// parámetros no alcanzan para armarlo.
MechanicJobWarrantyCommandRequest? warrantyRegistrationRequestOf(
  PendingWorkshopCommand command,
) {
  if (command.kind != WorkshopCommandKind.jobWarrantyRegistration) return null;
  final params = command.params;
  try {
    return MechanicJobWarrantyCommandRequest.registration(
      warrantyJobId: '${params['p_warranty_job_id'] ?? ''}',
      sourceJobId: '${params['p_source_job_id'] ?? ''}',
      operationKey: command.operationKey,
    );
  } on ArgumentError {
    return null;
  }
}

/// La llave con que sale la decisión de garantía [requested]: la de la última
/// decisión pendiente de ese trabajo en [pending] si es la misma (resultado y
/// motivo), para que volver a elegirla —también después de reiniciar la app—
/// no haga otra; si no, la suya, detrás de las pendientes.
String warrantyDecisionKeyFor(
  List<PendingWorkshopCommand> pending,
  PendingWorkshopCommand requested,
) {
  String canonical(PendingWorkshopCommand command) {
    final reason = '${command.params['p_reason'] ?? ''}'.trim();
    return '${command.params['p_warranty_job_id']}|'
        '${command.params['p_outcome']}|$reason';
  }

  final last = pending
      .where((command) =>
          command.kind == WorkshopCommandKind.jobWarrantyDecision &&
          command.jobId == requested.jobId)
      .lastOrNull;
  return last != null && canonical(last) == canonical(requested)
      ? last.operationKey
      : requested.operationKey;
}

/// Qué intento sale de un error del servidor o del transporte.
WorkshopCommandOutcome classifyWorkshopCommandError(Object error) {
  if (error is PostgrestException) {
    final code = error.code ?? '';
    // PT409 es el conflicto de la ficha desde 20260928052000; 40001 queda
    // para una versión sin desplegar (PostgREST 14 lo reintenta sin fin y
    // llega como 504, ver [_isTransientServerCode]).
    if (code == 'PT409' ||
        code == '40001' ||
        error.message.contains('changed since it was loaded') ||
        error.message.contains('changed since they were loaded')) {
      return WorkshopCommandOutcome.stale;
    }
    if (code.isEmpty || _isTransientServerCode(code)) {
      return WorkshopCommandOutcome.offline;
    }
    return WorkshopCommandOutcome.rejected;
  }
  // Sin respuesta del servidor (red, tiempo agotado, respuesta ilegible): no
  // se sabe si llegó. El comando sigue pendiente y el recibo lo resuelve.
  return WorkshopCommandOutcome.offline;
}

/// Códigos con los que el servidor no ejecutó el comando o no se sabe: la
/// conexión (08), recursos (53), cancelación o tiempo (57), un bloqueo mutuo
/// (40P01) o uno que no se alcanzó a tomar (55P03), la sesión vencida o el
/// pool de PostgREST (PGRST0xx/3xx) y un 5xx del gateway (un 504 puede llegar
/// después de escribir).
bool _isTransientServerCode(String code) =>
    code.startsWith('08') ||
    code.startsWith('53') ||
    code.startsWith('57') ||
    code == '40P01' ||
    code == '55P03' ||
    code.startsWith('PGRST0') ||
    code.startsWith('PGRST3') ||
    RegExp(r'^5\d\d$').hasMatch(code);

/// JSON con las claves ordenadas: el mismo comando respaldado por otra
/// versión de la app puede traer los campos en otro orden.
String _canonicalJson(Object? value) {
  Object? sorted(Object? node) {
    if (node is Map) {
      final keys = node.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: sorted(node[key])};
    }
    if (node is List) return node.map(sorted).toList();
    return node;
  }

  return jsonEncode(sorted(value));
}

String _errorCode(Object error) => error is PostgrestException
    ? (error.code?.isNotEmpty == true ? error.code! : 'postgrest')
    : error is WorkshopInvoicePendingException
        ? 'invoice_failed:${error.code ?? '?'}'
        : error.runtimeType.toString();

String _errorMessage(Object error) {
  final text = error is PostgrestException ? error.message : error.toString();
  return text.length <= 300 ? text : '${text.substring(0, 300)}…';
}

class _OutboxState {
  _OutboxState(this._loaded);

  /// Lo que había en el almacenamiento al leer, para escribir sólo lo que
  /// cambió.
  final Map<String, String> _loaded;
  final Map<String, PendingWorkshopCommand> commands = {};
  final Map<String, PendingBikeImage> images = {};
  final List<Map<String, dynamic>> attempts = [];
  int droppedAttempts = 0;

  /// Entradas que esta versión no sabe leer (otra versión de la app en otra
  /// pestaña, un formato nuevo). No se tocan ni se borran: pueden ser un
  /// comando pendiente de verdad. Se guarda la bici si se alcanza a leer.
  final Set<String> unreadableKeys = {};

  /// Las llaves de los comandos que esta versión no sabe leer: siguen en la
  /// bandeja, y lo que depende de ellos no es huérfano (otra versión de la
  /// app pudo enviarlos).
  final Set<String> unreadableCommandKeys = {};
  final Set<String> unreadableBikeIds = {};

  /// Las colas que se alcanzan a leer de esos comandos (`bike:`, `job:`,
  /// como [PendingWorkshopCommand.queueKeys]): lo que comparte una espera,
  /// porque el ilegible puede ser anterior y seguir sin respuesta.
  final Set<String> unreadableQueueKeys = {};

  /// Clientes de los comandos ilegibles, cuando se alcanza a leer: un alta
  /// ilegible de ese cliente puede ser la misma bici que se va a crear.
  final Set<String> unreadableCustomerIds = {};

  /// Último latido de cada sesión de la app (cada pestaña web es una): una
  /// sesión sin latido reciente ya no existe.
  final Map<String, DateTime> heartbeats = {};

  static const _command = 'c:';
  static const _image = 'i:';
  static const _attempt = 'a:';
  static const _dropped = 'dropped';
  static const _heartbeat = 'h:';

  /// Una entrada ilegible se salta: no tumba el resto de la bandeja.
  static _OutboxState fromEntries(String prefix, Map<String, String> entries) {
    final state = _OutboxState(entries);
    for (final entry in entries.entries) {
      final name = entry.key.substring(prefix.length);
      if (name == _dropped) {
        state.droppedAttempts = int.tryParse(entry.value) ?? 0;
        continue;
      }
      if (name.startsWith(_heartbeat)) {
        final at = DateTime.tryParse(entry.value);
        if (at != null) {
          state.heartbeats[name.substring(_heartbeat.length)] = at;
        }
        continue;
      }
      Object? json;
      try {
        json = jsonDecode(entry.value);
      } on FormatException {
        json = null;
      }
      if (name.startsWith(_command)) {
        final command = PendingWorkshopCommand.fromJson(json);
        if (command != null) {
          state.commands[command.operationKey] = command;
        } else {
          state.unreadableKeys.add(entry.key);
          state.unreadableCommandKeys.add(name.substring(_command.length));
          final bikeId = json is Map ? json['bike_id'] : null;
          if (bikeId is String) state.unreadableBikeIds.add(bikeId);
          final params = json is Map ? json['params'] : null;
          final customerId = params is Map ? params['p_customer_id'] : null;
          if (customerId is String) {
            state.unreadableCustomerIds.add(customerId);
          }
          final facts = params is Map ? params['p_bike_facts'] : null;
          state.unreadableQueueKeys.addAll([
            if (bikeId is String) 'bike:$bikeId',
            for (final jobId in [
              json is Map ? json['job_id'] : null,
              params is Map ? params['p_job_id'] : null,
            ])
              if (jobId is String) 'job:$jobId',
            if (facts is List)
              for (final fact in facts)
                if (fact is Map && fact['bike_id'] is String)
                  'bike:${fact['bike_id']}',
          ]);
        }
      } else if (name.startsWith(_image)) {
        final image = PendingBikeImage.fromJson(json);
        if (image != null) {
          state.images[image.objectPath] = image;
        } else {
          state.unreadableKeys.add(entry.key);
        }
      } else if (name.startsWith(_attempt) && json is Map) {
        state.attempts.add(Map<String, dynamic>.from(json));
      } else {
        state.unreadableKeys.add(entry.key);
      }
    }
    state.attempts.sort((a, b) {
      final byTime =
          '${a['client_started_at']}'.compareTo('${b['client_started_at']}');
      return byTime != 0
          ? byTime
          : ((a['attempt_number'] as num?) ?? 0)
              .compareTo((b['attempt_number'] as num?) ?? 0);
    });
    return state;
  }

  /// Lo que depende de un comando que ya no está en la bandeja, y lo que
  /// depende de eso: un corte a mitad de respaldar la cadena o de sacarla.
  /// Nunca se envía ni se muestra como pendiente; sale sin enviarse
  /// (revisión de Codex, 2026-09-29).
  Set<String> get orphanKeys {
    final orphans = <String>{};
    var grew = true;
    while (grew) {
      grew = false;
      for (final command in commands.values) {
        final prerequisite = command.dependsOn;
        if (prerequisite == null || orphans.contains(command.operationKey)) {
          continue;
        }
        if ((!commands.containsKey(prerequisite) &&
                !unreadableCommandKeys.contains(prerequisite)) ||
            orphans.contains(prerequisite)) {
          orphans.add(command.operationKey);
          grew = true;
        }
      }
    }
    return orphans;
  }

  /// Cuántos comandos de la bandeja van antes que [command] en su cadena.
  int _dependencyDepth(PendingWorkshopCommand command) {
    var depth = 0;
    final seen = <String>{};
    for (var next = command.dependsOn;
        next != null && seen.add(next);
        next = commands[next]?.dependsOn) {
      depth++;
    }
    return depth;
  }

  Map<String, String> toEntries(String prefix) => {
        // Lo que depende de otro comando se escribe antes que ése: cada llave
        // es una escritura aparte, y un corte entre dos deja lo dependiente
        // sin su comando (sale sin enviarse), nunca el comando sin lo que lo
        // seguía, como unas líneas sin su decisión de garantía (revisión de
        // Codex, 2026-09-29).
        for (final command
            in commands.values.toList()
              ..sort(
                  (a, b) => _dependencyDepth(b).compareTo(_dependencyDepth(a))))
          '$prefix$_command${command.operationKey}':
              jsonEncode(command.toJson()),
        for (final image in images.values)
          '$prefix$_image${image.objectPath}': jsonEncode(image.toJson()),
        for (final attempt in attempts)
          '$prefix$_attempt${attempt['attempt_id']}': jsonEncode(attempt),
        if (droppedAttempts > 0) '$prefix$_dropped': '$droppedAttempts',
        for (final beat in heartbeats.entries)
          '$prefix$_heartbeat${beat.key}': beat.value.toUtc().toIso8601String(),
      };

  Map<String, String> get loaded => _loaded;
}

class WorkshopCommandOutbox {
  WorkshopCommandOutbox({
    WorkshopOutboxStore? store,
    WorkshopCommandTransport? transport,
    DateTime Function()? clock,
    String Function()? idFactory,
    String? clientPlatform,
    String? appVersion,
    bool? concurrentSessions,
    CartLockCoordinator? lock,
  })  : _lock = lock ?? createCartLockCoordinator(),
        _store = store ?? SharedPreferencesWorkshopOutboxStore(),
        _transport = transport ?? SupabaseWorkshopCommandTransport(),
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _idFactory = idFactory ?? (() => const Uuid().v4()),
        _clientPlatform = clientPlatform ?? _defaultPlatform(),
        _appVersion = appVersion ?? _defaultAppVersion(),
        concurrentSessions = concurrentSessions ?? kIsWeb,
        sessionId = const Uuid().v4();

  /// Esta ejecución de la app. Las fotos anotadas por una sesión que ya no
  /// existe son las únicas que el barrido puede reclamar.
  final String sessionId;

  /// Si otras sesiones pueden estar vivas a la vez con la misma bandeja: sólo
  /// en la web, donde cada pestaña es una sesión y todas comparten el
  /// almacenamiento. En el Mac, el teléfono o la tableta corre un solo
  /// proceso, así que otra sesión es siempre una que ya terminó.
  final bool concurrentSessions;

  /// Una pestaña sin latido en este plazo ya no existe. Late al reanudar
  /// (cada 5 minutos y al volver al frente), al anotar una foto y al enviar.
  static const Duration sessionTimeout = Duration(minutes: 30);

  /// Un envío de otra pestaña viva más nuevo que esto sigue en camino.
  static const Duration sendTimeout = Duration(minutes: 2);

  /// Cuánto recuerda la bandeja un adjunto que borró: una ventana que lo
  /// tenía en un formulario y vuelve dentro de ese plazo no lo guarda. Más
  /// tarde ya no hay evidencia y el adjunto se juzga como uno cualquiera.
  static const Duration removedImageMemory = Duration(days: 30);

  bool _isLive(_OutboxState state, String? session) {
    if (session == null) return false;
    if (session == sessionId) return true;
    if (!concurrentSessions) return false;
    final beat = state.heartbeats[session];
    return beat != null && _clock().difference(beat) < sessionTimeout;
  }

  void _beat(_OutboxState state) {
    if (!concurrentSessions) return;
    final now = _clock();
    state.heartbeats[sessionId] = now;
    state.heartbeats.removeWhere(
      (_, at) => now.difference(at) > const Duration(days: 1),
    );
  }

  static WorkshopCommandOutbox? _shared;

  static WorkshopCommandOutbox get shared =>
      _shared ??= WorkshopCommandOutbox();

  @visibleForTesting
  static set shared(WorkshopCommandOutbox outbox) => _shared = outbox;

  /// Intentos que se guardan sin red antes de descartar los más viejos.
  static const int maxJournaledAttempts = 300;

  static WorkshopOutboxDebugFault? _debugNextFault;
  static int _debugFaultsLeft = 0;

  /// Arma una falla de red para la próxima llamada (sólo en depuración). Desde
  /// afuera se arma con la extensión de [registerDebugExtension].
  static String debugArmFault(String name, {int times = 1}) {
    if (!kDebugMode) return 'sólo en depuración';
    _debugNextFault = WorkshopOutboxDebugFault.values
        .where((fault) => fault.name == name)
        .firstOrNull;
    _debugFaultsLeft = _debugNextFault == null ? 0 : times.clamp(1, 20);
    return 'armada: ${_debugNextFault?.name} ×$_debugFaultsLeft';
  }

  static bool _debugExtensionRegistered = false;

  /// La misma falla desde afuera, por el servicio de la VM, cuando la sesión
  /// de depuración no compila expresiones:
  /// `ext.vinabike.outbox.armFault?fault=loseResponseAfterCommit`. Sólo en
  /// depuración, como `registerAgentInputExtensions`.
  static void registerDebugExtension() {
    if (!kDebugMode || _debugExtensionRegistered) return;
    _debugExtensionRegistered = true;
    developer.registerExtension('ext.vinabike.outbox.armFault',
        (_, params) async {
      return developer.ServiceExtensionResponse.result(
        jsonEncode({
          'result': debugArmFault(
            params['fault'] ?? '',
            times: int.tryParse(params['times'] ?? '') ?? 1,
          ),
        }),
      );
    });
  }

  final WorkshopOutboxStore _store;
  final WorkshopCommandTransport _transport;
  final DateTime Function() _clock;
  final String Function() _idFactory;
  final String _clientPlatform;
  final String? _appVersion;

  final StreamController<WorkshopCommandRun> _runs =
      StreamController<WorkshopCommandRun>.broadcast();
  final Map<String, Future<WorkshopCommandRun>> _inFlight = {};
  final Set<String> _flushing = {};
  final CartLockCoordinator _lock;
  bool _crossTabLockUnavailable = false;

  /// Una sola bandeja por origen: todas las pestañas toman el mismo lock.
  static const String _lockName = 'workshop-command-outbox';

  /// Cada intento terminado, para refrescar pantallas y avisar.
  Stream<WorkshopCommandRun> get runs => _runs.stream;

  static String _defaultPlatform() =>
      kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

  static String? _defaultAppVersion() {
    const tag = String.fromEnvironment('VINABIKE_BUILD_TAG');
    if (tag.isNotEmpty) return tag;
    return kDebugMode ? 'debug' : null;
  }

  /// Leer, decidir y escribir la bandeja va de a uno, también entre
  /// pestañas: en la web cada pestaña es otra instancia sobre el mismo
  /// almacenamiento, y una cola por instancia dejaba que dos altas leyeran la
  /// bandeja vacía y se respaldaran las dos (revisión del 2026-09-28). En la
  /// web es un Web Lock del origen, que se suelta solo si la pestaña muere;
  /// en el Mac, el teléfono y las pruebas, una cola compartida por el
  /// proceso. Un navegador sin Web Locks usa esa cola (sólo su pestaña).
  Future<T> _locked<T>(Future<T> Function() body) async {
    late T result;
    var entered = false;
    Future<void> action() async {
      entered = true;
      result = await body();
    }

    if (_crossTabLockUnavailable) {
      await process_lock.createCartLockCoordinator().synchronized(
            _lockName,
            action,
          );
      return result;
    }
    try {
      await _lock.synchronized(_lockName, action);
    } on UnsupportedError {
      if (entered) rethrow;
      _crossTabLockUnavailable = true;
      await process_lock.createCartLockCoordinator().synchronized(
            _lockName,
            action,
          );
    }
    return result;
  }

  String _prefix(WorkshopCommandScope scope) => '${scope.storageKey}:';

  Future<_OutboxState> _load(WorkshopCommandScope scope) async {
    final prefix = _prefix(scope);
    return _OutboxState.fromEntries(prefix, await _store.readAll(prefix));
  }

  /// Escribe sólo las entradas que cambiaron y borra las que ya no están.
  Future<void> _save(WorkshopCommandScope scope, _OutboxState state) async {
    final prefix = _prefix(scope);
    final entries = state.toEntries(prefix);
    for (final entry in entries.entries) {
      if (state.loaded[entry.key] != entry.value) {
        await _store.write(entry.key, entry.value);
      }
    }
    // Lo que no se supo leer no se borra por omisión: sólo se borra lo que
    // esta versión leyó y sacó a propósito.
    final removals = [
      for (final key in state.loaded.keys)
        if (!entries.containsKey(key) && !state.unreadableKeys.contains(key))
          key,
    ];
    for (final key in _prerequisitesFirst(prefix, removals, state.loaded)) {
      await _store.remove(key);
    }
  }

  /// [removals] con cada comando antes que lo que dependía de él: cada
  /// borrado es aparte, y un corte entre dos deja lo dependiente sin su
  /// comando (sale sin enviarse), nunca el comando sin lo que lo seguía. Al
  /// sacar una cadena rechazada, borrar primero las líneas dejaba el alta
  /// sola, y la reanudación la enviaba sin ellas (revisión de Codex del alta,
  /// 2026-09-29).
  static List<String> _prerequisitesFirst(
    String prefix,
    List<String> removals,
    Map<String, String> loaded,
  ) {
    final commandPrefix = '$prefix${_OutboxState._command}';
    final prerequisiteOf = <String, String?>{};
    for (final key in removals) {
      if (!key.startsWith(commandPrefix)) continue;
      String? dependsOn;
      try {
        final json = jsonDecode(loaded[key] ?? '');
        if (json is Map && json['depends_on'] is String) {
          dependsOn = json['depends_on'] as String;
        }
      } on FormatException {
        dependsOn = null;
      }
      prerequisiteOf[key.substring(commandPrefix.length)] = dependsOn;
    }
    int depth(String key) {
      if (!key.startsWith(commandPrefix)) return 0;
      var depth = 0;
      final seen = <String>{};
      for (var next = prerequisiteOf[key.substring(commandPrefix.length)];
          next != null && prerequisiteOf.containsKey(next) && seen.add(next);
          next = prerequisiteOf[next]) {
        depth++;
      }
      return depth;
    }

    final depths = {for (final key in removals) key: depth(key)};
    return [...removals]..sort((a, b) => depths[a]!.compareTo(depths[b]!));
  }

  /// Lo pendiente del taller y la persona, del más viejo al más nuevo.
  Future<List<PendingWorkshopCommand>> pending(
    WorkshopCommandScope scope, {
    String? bikeId,
    String? jobId,
  }) =>
      _locked(() async {
        final state = await _load(scope);
        final orphans = state.orphanKeys;
        return state.commands.values
            .where((command) => !orphans.contains(command.operationKey))
            .where((command) => bikeId == null || command.bikeId == bikeId)
            .where((command) => jobId == null || command.jobId == jobId)
            .toList()
          ..sort(_commandOrder);
      });

  /// El orden de la cola, el mismo en cada puerta: la hora en que se
  /// respaldó y, a igual hora, la llave. Con sólo la hora, dos comandos del
  /// mismo milisegundo (web) no esperaban uno al otro (tercera revisión de
  /// Codex).
  static int _commandOrder(
    PendingWorkshopCommand a,
    PendingWorkshopCommand b,
  ) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime : a.operationKey.compareTo(b.operationKey);
  }

  Future<Set<String>> _unreadableQueueKeys(WorkshopCommandScope scope) =>
      _locked(() async => {...(await _load(scope)).unreadableQueueKeys});

  /// Si hay un comando de [bikeId] que esta versión no sabe leer: puede ser un
  /// guardado pendiente de verdad, así que quien edita esa bici espera.
  Future<bool> hasUnreadableFor(WorkshopCommandScope scope, String bikeId) =>
      _locked(
          () async => (await _load(scope)).unreadableBikeIds.contains(bikeId));

  /// Las altas de bici de [customerId] que siguen en la bandeja, leídas en
  /// ese momento del almacenamiento (otra pestaña pudo dejar una después de
  /// abrir el formulario), y si hay un comando ilegible de ese cliente. Un
  /// error de lectura se lanza: quien crea una bici no debe seguir a ciegas
  /// (revisión del 2026-09-28).
  Future<({List<PendingWorkshopCommand> creations, bool unreadable})>
      pendingCreationsFor(WorkshopCommandScope scope, String customerId) =>
          _locked(() async {
            final state = await _load(scope);
            final creations = state.commands.values
                .where((command) => _isCreationFor(command, customerId))
                .toList()
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
            return (
              creations: creations,
              unreadable: state.unreadableCustomerIds.contains(customerId),
            );
          });

  static bool _isCreationFor(
    PendingWorkshopCommand command,
    String customerId,
  ) =>
      command.kind == WorkshopCommandKind.bikeAggregateSave &&
      command.bikeId != null &&
      command.params['p_customer_id'] == customerId &&
      command.params['p_expected_bike_updated_at'] == null;

  /// Respalda [requested] antes de enviarlo y devuelve la llave que quedó:
  /// la suya, o la de una decisión de garantía igual que ya estaba pendiente
  /// en ese trabajo ([warrantyDecisionKeyFor]). Un cambio de estado queda
  /// dependiendo de la decisión de garantía pendiente de su trabajo. Si la
  /// llave ya está, debe traer el
  /// mismo contenido: una llave nunca cambia de comando (el servidor también
  /// lo rechaza). Falla cerrado: sin respaldo no se envía. Con
  /// [creationGuard], un alta nueva no se respalda si en la bandeja hay otra
  /// de ese cliente que quien guarda no vio: la decisión «¿es otra bici?» se
  /// comprueba con la misma lectura con que se escribe, no antes de subir las
  /// fotos (revisión de Codex, 2026-09-28).
  ///
  /// [followUps] van en la misma escritura, cada uno detrás del anterior
  /// ([PendingWorkshopCommand.after]): lo que sigue a [requested] y sólo
  /// tiene sentido si [requested] se escribe. Así un cierre justo después de
  /// enviar [requested] no los pierde (punto 2 del cierre, 2026-09-29).
  Future<String> enqueue(
    WorkshopCommandScope scope,
    PendingWorkshopCommand requested, {
    WorkshopCreationGuard? creationGuard,
    List<PendingWorkshopCommand> followUps = const [],
  }) async =>
      (await _enqueue(
        scope,
        requested,
        creationGuard: creationGuard,
        followUps: followUps,
      ))
          .operationKey;

  /// [enqueue], devolviendo el comando tal como quedó respaldado (el mismo,
  /// o la decisión igual que ya estaba): quien lo envía lo necesita si otra
  /// pestaña lo saca antes (segunda revisión de Codex del alta).
  Future<PendingWorkshopCommand> _enqueue(
    WorkshopCommandScope scope,
    PendingWorkshopCommand requested, {
    WorkshopCreationGuard? creationGuard,
    List<PendingWorkshopCommand> followUps = const [],
  }) =>
      _locked(() async {
        var state = await _load(scope);
        // Un adjunto nuevo que la bandeja borró o está borrando, o que es de
        // otro trabajo o bici, nunca entra: se decide bajo el mismo candado
        // con que el barrido lo marca antes de borrarlo, y antes de escribir
        // nada (carrera del barrido, 2026-09-29).
        _refuseUnavailableImages(state, [requested, ...followUps]);
        // Lo que quedó sin su comando previo (un corte a mitad de respaldar)
        // sale antes de respaldar nada, en su propia escritura: si la llave
        // de ese comando vuelve (el mismo trabajo nuevo, guardado otra vez),
        // lo viejo revivía detrás de ella con la hora de antes, y cada uno
        // esperaba al otro para siempre (revisión de Codex del alta,
        // 2026-09-29).
        if (state.orphanKeys.isNotEmpty) {
          final at = _clock();
          for (final key in state.orphanKeys) {
            final orphan = state.commands[key];
            if (orphan == null ||
                state.commands.containsKey(orphan.dependsOn)) {
              continue;
            }
            _dropOrphan(state, orphan, at);
          }
          await _save(scope, state);
          state = await _load(scope);
        }
        final orphans = state.orphanKeys;
        final visible = state.commands.values
            .where((other) => !orphans.contains(other.operationKey))
            .toList()
          ..sort(_commandOrder);
        var command = requested;
        if (!state.commands.containsKey(command.operationKey)) {
          // Lo que se decide leyendo la bandeja se decide aquí, bajo el mismo
          // candado que la escribe: dos ventanas que leían antes de respaldar
          // hacían dos decisiones iguales con llaves distintas (revisión de
          // Codex, 2026-09-29).
          // Lo que la seguía queda detrás de la que ya estaba.
          if (command.kind == WorkshopCommandKind.jobWarrantyDecision) {
            final key = warrantyDecisionKeyFor(visible, command);
            if (key != command.operationKey) command = state.commands[key]!;
          }
          // Un cambio de estado pedido con una decisión de garantía del mismo
          // trabajo pendiente depende de ella: si el servidor no la aplica,
          // el estado no se aplica sobre la cobertura de antes.
          if (command.kind == WorkshopCommandKind.jobStatusTransition &&
              command.dependsOn == null) {
            final decision = visible
                .where((other) =>
                    other.kind == WorkshopCommandKind.jobWarrantyDecision &&
                    other.jobId == command.jobId)
                .lastOrNull;
            if (decision != null) {
              // Y va después de ella también en la cola: con la misma hora y
              // una llave que ordena antes, cada uno esperaba al otro
              // (segunda revisión de Codex).
              final after =
                  decision.createdAt.add(const Duration(milliseconds: 1));
              command = command.copyWith(
                dependsOn: decision.operationKey,
                createdAt: command.createdAt.isAfter(after)
                    ? command.createdAt
                    : after,
              );
            }
          }
        }
        final chained = <PendingWorkshopCommand>[];
        var previous = command;
        for (final followUp in followUps) {
          final next = followUp.after(previous);
          chained.add(next);
          previous = next;
        }
        // Una llave nunca cambia de comando, tampoco la de lo que sigue.
        for (final candidate in [command, ...chained]) {
          final existing = state.commands[candidate.operationKey];
          if (existing != null &&
              (existing.kind != candidate.kind ||
                  _canonicalJson(existing.params) !=
                      _canonicalJson(candidate.params))) {
            throw StateError(
              'La llave ${candidate.operationKey} ya respalda otro cambio.',
            );
          }
        }
        if (state.commands.containsKey(command.operationKey)) {
          final added = [
            for (final next in chained)
              if (!state.commands.containsKey(next.operationKey)) next,
          ];
          if (added.isEmpty) {
            return state.commands[command.operationKey] ?? command;
          }
          for (final next in added) {
            state.commands[next.operationKey] = next;
          }
          await _save(scope, state);
          return state.commands[command.operationKey] ?? command;
        }
        final guard = creationGuard;
        if (guard != null) {
          final unseen = state.commands.values
              .where((other) =>
                  _isCreationFor(other, guard.customerId) &&
                  other.bikeId != command.bikeId &&
                  !guard.acknowledgedBikeIds.contains(other.bikeId))
              .toList();
          final unreadable =
              state.unreadableCustomerIds.contains(guard.customerId);
          if (unseen.isNotEmpty || unreadable) {
            throw WorkshopPendingCreationException(
              labels: [for (final other in unseen) other.label ?? 'sin nombre'],
              unreadable: unreadable,
            );
          }
        }
        state.commands[command.operationKey] = command;
        for (final next in chained) {
          state.commands.putIfAbsent(next.operationKey, () => next);
        }
        final urls = command.imageUrls.toSet();
        for (final image in state.images.values.toList()) {
          if (!image.retired && urls.contains(image.publicUrl)) {
            state.images[image.objectPath] =
                image.copyWith(operationKey: command.operationKey);
          }
        }
        await _save(scope, state);
        return state.commands[command.operationKey] ?? command;
      });

  /// De las URL nuevas de [command], las que la bandeja borró o está
  /// borrando.
  static List<String> _retiredNewUrls(
    _OutboxState state,
    PendingWorkshopCommand command,
  ) {
    final retired = {
      for (final image in state.images.values)
        if (image.retired) image.publicUrl,
    };
    return [
      for (final url in command.newImageUrls)
        if (retired.contains(url)) url,
    ];
  }

  static void _refuseUnavailableImages(
    _OutboxState state,
    List<PendingWorkshopCommand> commands,
  ) {
    final byUrl = {
      for (final image in state.images.values) image.publicUrl: image,
    };
    final removed = <String>[];
    final foreign = <String>[];
    for (final command in commands) {
      for (final url in command.newImageUrls) {
        final image = byUrl[url];
        // Sin anotación: ya en el trabajo o la bici, o de antes de la bandeja.
        if (image == null) continue;
        if (image.retired) {
          removed.add(url);
        } else if (!_imageBelongsTo(image, command)) {
          foreign.add(url);
        }
      }
    }
    if (removed.isNotEmpty || foreign.isNotEmpty) {
      throw WorkshopImageUnavailableException(
        removedUrls: removed,
        foreignUrls: foreign,
      );
    }
  }

  /// La anotación de un adjunto dice de quién es: la bici de una bici, el
  /// trabajo (con el id que eligió el formulario, también en un alta) de un
  /// trabajo.
  static bool _imageBelongsTo(
    PendingBikeImage image,
    PendingWorkshopCommand command,
  ) =>
      command.kind == WorkshopCommandKind.bikeAggregateSave
          ? image.bikeId != null && image.bikeId == command.bikeId
          : image.jobId != null && image.jobId == command.jobId;

  /// Respalda y envía.
  Future<WorkshopCommandRun> submit(
    WorkshopCommandScope scope,
    PendingWorkshopCommand command, {
    WorkshopCommandTrigger trigger = WorkshopCommandTrigger.save,
    WorkshopCreationGuard? creationGuard,
    List<PendingWorkshopCommand> followUps = const [],
  }) async {
    // Lo que quedó respaldado: [command], o una decisión igual que ya estaba
    // pendiente.
    final backedUp = await _enqueue(
      scope,
      command,
      creationGuard: creationGuard,
      followUps: followUps,
    );
    final key = backedUp.operationKey;
    // Una bici o un trabajo es una cola: lo anterior que escribe lo mismo va
    // primero, y si sigue sin respuesta, éste espera en la bandeja (revisión
    // de Codex, 2026-09-28). Se ordena con el comando como quedó respaldado:
    // reenviar uno ya pendiente con otra hora lo ponía detrás de lo que lo
    // sigue (revisión de Codex, 2026-09-29).
    final queueKeys = command.queueKeys;
    if (queueKeys.isNotEmpty) {
      final all = await pending(scope);
      final self =
          all.where((other) => other.operationKey == key).firstOrNull ??
              command;
      final earlier = all
          .where((other) =>
              other.operationKey != key &&
              _commandOrder(other, self) < 0 &&
              other.queueKeys.any(queueKeys.contains))
          .toList();
      for (final other in earlier) {
        WorkshopCommandRun previous;
        try {
          previous = await run(
            scope,
            other.operationKey,
            trigger: WorkshopCommandTrigger.resume,
          );
        } on StateError {
          continue;
        }
        if (!previous.outcome.isFinal) {
          return WorkshopCommandRun(
            command: self,
            outcome: WorkshopCommandOutcome.offline,
            trigger: trigger,
            error: const WorkshopCommandQueuedException(),
          );
        }
      }
    }
    // Otra pestaña o la reanudación pudo enviarlo y sacarlo entre el
    // respaldo y este envío: su recibo dice qué pasó, en vez de un error
    // para un cambio que quizá se escribió (revisión de Codex del alta,
    // 2026-09-29).
    return runOrReconcile(scope, backedUp, trigger: trigger);
  }

  /// Envía [command] si sigue pendiente ([run]). Si ya no está en la bandeja
  /// (otra pestaña o la reanudación lo resolvió, o nunca se respaldó), su
  /// recibo decide: `reconciled` si se escribió, `discarded` con
  /// [WorkshopCommandNotPendingError] si no hay recibo, `offline` si no se
  /// pudo preguntar o el recibo no es de este comando.
  Future<WorkshopCommandRun> runOrReconcile(
    WorkshopCommandScope scope,
    PendingWorkshopCommand command, {
    required WorkshopCommandTrigger trigger,
  }) async {
    try {
      return await run(scope, command.operationKey, trigger: trigger);
    } on WorkshopCommandNotPendingError catch (gone) {
      if (!_transport.isCurrent(scope)) {
        throw const WorkshopScopeChangedException();
      }
      final Map<String, dynamic>? receipt;
      try {
        receipt = await _probe(scope, command);
      } catch (error) {
        return WorkshopCommandRun(
          command: command,
          outcome: WorkshopCommandOutcome.offline,
          trigger: trigger,
          error: error,
        );
      }
      if (receipt == null) {
        return WorkshopCommandRun(
          command: command,
          outcome: WorkshopCommandOutcome.discarded,
          trigger: trigger,
          error: gone,
        );
      }
      // Fuera de la bandeja nadie lo va a reenviar: un recibo de otro
      // contenido es definitivo, no una espera sin fin (segunda revisión de
      // Codex del alta, 2026-09-29).
      if (receipt['payload_matches'] == false) {
        return WorkshopCommandRun(
          command: command,
          outcome: WorkshopCommandOutcome.rejected,
          trigger: trigger,
          error: const WorkshopCommandContentConflictException(),
        );
      }
      try {
        return WorkshopCommandRun(
          command: command,
          outcome: WorkshopCommandOutcome.reconciled,
          trigger: trigger,
          response: _validReceipt(command, receipt, scope.tenantId),
        );
      } on FormatException catch (error) {
        return WorkshopCommandRun(
          command: command,
          outcome: WorkshopCommandOutcome.offline,
          trigger: trigger,
          error: error,
        );
      }
    }
  }

  /// Envía el comando pendiente [operationKey] y lo clasifica. Dos llamadas a
  /// la vez con la misma llave comparten el mismo intento.
  Future<WorkshopCommandRun> run(
    WorkshopCommandScope scope,
    String operationKey, {
    required WorkshopCommandTrigger trigger,
  }) {
    final flightKey = '${scope.storageKey}|$operationKey';
    final running = _inFlight[flightKey];
    if (running != null) return running;
    final future = _runOnce(scope, operationKey, trigger);
    _inFlight[flightKey] = future;
    return future.whenComplete(() {
      if (identical(_inFlight[flightKey], future)) _inFlight.remove(flightKey);
    });
  }

  Future<WorkshopCommandRun> _runOnce(
    WorkshopCommandScope scope,
    String operationKey,
    WorkshopCommandTrigger trigger,
  ) async {
    if (!_transport.isCurrent(scope)) {
      throw const WorkshopScopeChangedException();
    }
    final startedAt = _clock();
    // El intento cuenta desde antes de enviarse: si la app muere a mitad de
    // camino, el siguiente sabe que éste existió y lo anota como interrumpido.
    final claimed = await _locked(() async {
      final state = await _load(scope);
      final current = state.commands[operationKey];
      if (current == null) {
        throw WorkshopCommandNotPendingError(operationKey);
      }
      // Lo que depende de un comando que ya no está nunca se envía: un corte
      // a mitad de respaldar la cadena o de sacarla lo dejó sin él.
      // Uno que lleva un adjunto nuevo que la bandeja borró o está borrando
      // no se envía: el trabajo o la bici quedaría con un enlace roto. Sólo
      // pasa si la marca llegó sin candado compartido (una pestaña sin Web
      // Locks); sale rechazado, con lo que lo seguía (revisión de Codex del
      // barrido, 2026-09-29).
      final retired = _retiredNewUrls(state, current);
      if (retired.isNotEmpty) {
        state.commands.remove(operationKey);
        final dropped = _settleDependents(
          state,
          current,
          wrote: false,
          at: startedAt,
        );
        final refusal = WorkshopImageUnavailableException(removedUrls: retired);
        _journal(
          state,
          WorkshopCommandAttempt(
            attemptId: _idFactory(),
            operationKey: operationKey,
            kind: current.kind,
            attemptNumber: current.attempts,
            trigger: trigger,
            outcome: WorkshopCommandOutcome.rejected,
            startedAt: startedAt,
            durationMs: 0,
            errorCode: 'image_unavailable',
            errorMessage: refusal.toString(),
            bikeId: current.bikeId,
            jobId: current.jobId,
            clientPlatform: _clientPlatform,
            appVersion: _appVersion,
          ),
        );
        await _save(scope, state);
        return (
          command: current,
          busy: false,
          queued: false,
          orphanDropped: null,
          refused: (error: refusal, dropped: dropped),
        );
      }
      if (state.orphanKeys.contains(operationKey)) {
        final dropped = _dropOrphan(state, current, startedAt);
        await _save(scope, state);
        return (
          command: current,
          busy: false,
          queued: false,
          orphanDropped: dropped,
          refused: null,
        );
      }
      // Una bici o un trabajo es una cola también aquí, en la puerta común
      // de envío: un comando anterior de lo mismo sin resolver, o uno que
      // esta versión no sabe leer, va primero. Antes sólo `submit` y
      // `resume` miraban la cola, y resolver un pendiente por su llave la
      // saltaba (segunda revisión de Codex, 2026-09-28).
      // Lo que depende de otro comando espera a que ése se escriba (si no se
      // escribe, sale con él y nunca llega aquí).
      final prerequisite = current.dependsOn;
      if (prerequisite != null && state.commands.containsKey(prerequisite)) {
        return (
          command: current,
          busy: false,
          queued: true,
          orphanDropped: null,
          refused: null,
        );
      }
      final queueKeys = current.queueKeys;
      if (queueKeys.isNotEmpty &&
          (state.unreadableQueueKeys.any(queueKeys.contains) ||
              state.commands.values.any((other) =>
                  other.operationKey != operationKey &&
                  _commandOrder(other, current) < 0 &&
                  other.queueKeys.any(queueKeys.contains)))) {
        return (
          command: current,
          busy: false,
          queued: true,
          orphanDropped: null,
          refused: null,
        );
      }
      final lastAttemptAt = current.lastAttemptAt;
      if (current.inFlight &&
          current.inFlightSession != sessionId &&
          _isLive(state, current.inFlightSession) &&
          lastAttemptAt != null &&
          startedAt.difference(lastAttemptAt) < sendTimeout) {
        // Otra pestaña viva lo está enviando: su resultado decide.
        return (
          command: current,
          busy: true,
          queued: false,
          orphanDropped: null,
          refused: null,
        );
      }
      if (current.inFlight) {
        _journal(
          state,
          WorkshopCommandAttempt(
            attemptId: _idFactory(),
            operationKey: operationKey,
            kind: current.kind,
            attemptNumber: current.attempts,
            trigger: current.lastTrigger ?? WorkshopCommandTrigger.save,
            outcome: WorkshopCommandOutcome.offline,
            startedAt: current.lastAttemptAt ?? startedAt,
            durationMs: 0,
            errorCode: 'interrupted',
            errorMessage: 'La app se cerró antes de saber el resultado.',
            bikeId: current.bikeId,
            jobId: current.jobId,
            clientPlatform: _clientPlatform,
            appVersion: _appVersion,
          ),
        );
      }
      final counted = current.copyWith(
        attempts: current.attempts + 1,
        lastAttemptAt: startedAt,
        inFlight: true,
        lastTrigger: trigger,
        inFlightSession: sessionId,
      );
      state.commands[operationKey] = counted;
      _beat(state);
      await _save(scope, state);
      return (
        command: counted,
        busy: false,
        queued: false,
        orphanDropped: null,
        refused: null,
      );
    });
    final command = claimed.command;
    final refused = claimed.refused;
    if (refused != null) {
      final run = WorkshopCommandRun(
        command: command,
        outcome: WorkshopCommandOutcome.rejected,
        trigger: trigger,
        error: refused.error,
        droppedFollowUps: refused.dropped,
      );
      _runs.add(run);
      unawaited(flushAttempts(scope));
      return run;
    }
    final orphanDropped = claimed.orphanDropped;
    if (orphanDropped != null) {
      return _orphanRun(scope, command, trigger, orphanDropped);
    }
    if (claimed.queued) {
      return WorkshopCommandRun(
        command: command,
        outcome: WorkshopCommandOutcome.offline,
        trigger: trigger,
        error: const WorkshopCommandQueuedException(),
      );
    }
    if (claimed.busy) {
      return WorkshopCommandRun(
        command: command,
        outcome: WorkshopCommandOutcome.offline,
        trigger: trigger,
        error: const WorkshopCommandBusyException(),
      );
    }

    Map<String, dynamic>? response;
    Object? error;
    WorkshopCommandOutcome outcome;
    try {
      // La cuenta pudo cambiar mientras se respaldaba: nunca se envía lo de
      // una persona con la sesión de otra.
      if (!_transport.isCurrent(scope)) {
        throw const WorkshopScopeChangedException();
      }
      response = _validReceipt(command, await _send(command), scope.tenantId);
      // La decisión de garantía dice `replay` cuando la llave ya estaba.
      outcome = response['replayed'] == true ||
              ((command.kind == WorkshopCommandKind.jobWarrantyDecision ||
                      command.kind ==
                          WorkshopCommandKind.jobWarrantyRegistration) &&
                  response['replay'] == true)
          ? WorkshopCommandOutcome.reconciled
          : WorkshopCommandOutcome.committed;
    } catch (sendError) {
      error = sendError;
      outcome = classifyWorkshopCommandError(sendError);
      // En la decisión de garantía, 40001 no es una ficha cambiada: el
      // vínculo con la factura cambió mientras se tomaba y el servidor pide
      // volver a intentarlo, sin haber escrito nada.
      if (command.kind == WorkshopCommandKind.jobWarrantyDecision &&
          sendError is PostgrestException &&
          sendError.code == '40001') {
        outcome = WorkshopCommandOutcome.offline;
      }
      // Un rechazo con otra cuenta ya adentro no prueba nada sobre la de este
      // comando: sigue pendiente para su dueño.
      if (!outcome.wrote && outcome.isFinal && !_transport.isCurrent(scope)) {
        error = const WorkshopScopeChangedException();
        outcome = WorkshopCommandOutcome.offline;
      }
      if (outcome == WorkshopCommandOutcome.offline &&
          sendError is! WorkshopScopeChangedException &&
          _transport.isCurrent(scope)) {
        // La respuesta pudo perderse después de escribir: el recibo decide.
        try {
          final receipt = await _probe(scope, command);
          if (receipt != null) {
            response = _validReceipt(command, receipt, scope.tenantId);
            outcome = WorkshopCommandOutcome.reconciled;
          }
        } catch (_) {
          // Sin recibo a la vista, sigue pendiente con su llave.
        }
      }
    }

    final finishedAt = _clock();
    final attempt = WorkshopCommandAttempt(
      attemptId: _idFactory(),
      operationKey: operationKey,
      kind: command.kind,
      attemptNumber: command.attempts,
      trigger: trigger,
      outcome: outcome,
      startedAt: startedAt,
      durationMs: finishedAt.difference(startedAt).inMilliseconds,
      errorCode: outcome.wrote || error == null ? null : _errorCode(error),
      errorMessage:
          outcome.wrote || error == null ? null : _errorMessage(error),
      bikeId: command.bikeId,
      jobId: command.jobId,
      clientPlatform: _clientPlatform,
      appVersion: _appVersion,
    );

    final settled = await _locked(() async {
      final state = await _load(scope);
      final orphaned = <PendingBikeImage>[];
      var dropped = const <PendingWorkshopCommand>[];
      if (outcome.isFinal) {
        state.commands.remove(operationKey);
        dropped = _settleDependents(
          state,
          command,
          wrote: outcome.wrote,
          at: finishedAt,
        );
        _continueInvoice(state, command, outcome, response, finishedAt);
        for (final image in state.images.values.toList()) {
          if (image.operationKey != operationKey) continue;
          if (outcome.wrote) {
            // Ya es foto de una bici guardada.
            state.images.remove(image.objectPath);
          } else if (!_isLive(state, image.ownerSession)) {
            // La subió una sesión que ya no existe: nadie más la reclama.
            orphaned.add(image);
          } else {
            // Un formulario de esta sesión puede seguir abierto y volver a
            // enviarla (tras recargar una ficha cambiada); la libera al
            // cerrarse, o el barrido de la próxima sesión.
            state.images[image.objectPath] =
                image.copyWith(clearOperationKey: true);
          }
        }
      } else if (state.commands.containsKey(operationKey)) {
        // Si alguien lo descartó mientras volaba, no se revive.
        state.commands[operationKey] = command.copyWith(
          lastOutcome: outcome,
          lastError: attempt.errorMessage,
          lastErrorCode: attempt.errorCode,
          inFlight: false,
        );
      }
      _journal(state, attempt);
      await _save(scope, state);
      return (orphaned: orphaned, dropped: dropped);
    });

    if (settled.orphaned.isNotEmpty) {
      await _removeOrphans(scope, settled.orphaned);
    }

    final run = WorkshopCommandRun(
      command: command,
      outcome: outcome,
      trigger: trigger,
      response: response,
      error: outcome.wrote ? null : error,
      droppedFollowUps: settled.dropped,
    );
    _runs.add(run);
    unawaited(flushAttempts(scope));
    return run;
  }

  /// Lo que dependía de [command], que ya terminó: si se escribió, deja de
  /// esperarlo; si no, sale de la bandeja sin enviarse (y lo que dependía de
  /// eso, también), con su intento anotado como descartado. Devuelve lo que
  /// salió.
  List<PendingWorkshopCommand> _settleDependents(
    _OutboxState state,
    PendingWorkshopCommand command, {
    required bool wrote,
    required DateTime at,
  }) {
    if (wrote) {
      for (final entry in state.commands.entries.toList()) {
        if (entry.value.dependsOn == command.operationKey) {
          state.commands[entry.key] =
              entry.value.copyWith(clearDependsOn: true);
        }
      }
      return const [];
    }
    final dropped = <PendingWorkshopCommand>[];
    final gone = [command];
    while (gone.isNotEmpty) {
      final prerequisite = gone.removeAt(0);
      for (final dependent in state.commands.values
          .where((other) => other.dependsOn == prerequisite.operationKey)
          .toList()) {
        state.commands.remove(dependent.operationKey);
        _journal(
          state,
          WorkshopCommandAttempt(
            attemptId: _idFactory(),
            operationKey: dependent.operationKey,
            kind: dependent.kind,
            attemptNumber: dependent.attempts,
            trigger: WorkshopCommandTrigger.discard,
            outcome: WorkshopCommandOutcome.discarded,
            startedAt: at,
            durationMs: 0,
            errorCode: 'prerequisite_not_written',
            errorMessage:
                WorkshopCommandPrerequisiteNotWrittenException(prerequisite)
                    .toString(),
            bikeId: dependent.bikeId,
            jobId: dependent.jobId,
            clientPlatform: _clientPlatform,
            appVersion: _appVersion,
          ),
        );
        dropped.add(dependent);
        gone.add(dependent);
      }
    }
    return dropped;
  }

  /// Saca de la bandeja, sin enviarlo, [orphan] (su comando previo ya no
  /// está) y lo que depende de él, con su intento anotado. Devuelve lo que
  /// dependía de él.
  List<PendingWorkshopCommand> _dropOrphan(
    _OutboxState state,
    PendingWorkshopCommand orphan,
    DateTime at,
  ) {
    state.commands.remove(orphan.operationKey);
    _journal(
      state,
      WorkshopCommandAttempt(
        attemptId: _idFactory(),
        operationKey: orphan.operationKey,
        kind: orphan.kind,
        attemptNumber: orphan.attempts,
        trigger: WorkshopCommandTrigger.discard,
        outcome: WorkshopCommandOutcome.discarded,
        startedAt: at,
        durationMs: 0,
        errorCode: 'prerequisite_not_written',
        errorMessage: const WorkshopCommandPrerequisiteNotWrittenException(null)
            .toString(),
        bikeId: orphan.bikeId,
        jobId: orphan.jobId,
        clientPlatform: _clientPlatform,
        appVersion: _appVersion,
      ),
    );
    return _settleDependents(state, orphan, wrote: false, at: at);
  }

  WorkshopCommandRun _orphanRun(
    WorkshopCommandScope scope,
    PendingWorkshopCommand orphan,
    WorkshopCommandTrigger trigger,
    List<PendingWorkshopCommand> dropped,
  ) {
    final run = WorkshopCommandRun(
      command: orphan,
      outcome: WorkshopCommandOutcome.discarded,
      trigger: trigger,
      error: const WorkshopCommandPrerequisiteNotWrittenException(null),
      droppedFollowUps: dropped,
    );
    _runs.add(run);
    unawaited(flushAttempts(scope));
    return run;
  }

  /// Lo que quedó sin su comando previo sale al reanudar: no aparece como
  /// pendiente y nadie más lo enviaría.
  Future<List<WorkshopCommandRun>> _sweepOrphans(
    WorkshopCommandScope scope,
  ) async {
    final at = _clock();
    final swept = await _locked(() async {
      final state = await _load(scope);
      final orphans = state.orphanKeys;
      if (orphans.isEmpty) {
        return const <({
          PendingWorkshopCommand orphan,
          List<PendingWorkshopCommand> dropped,
        })>[];
      }
      final result = <({
        PendingWorkshopCommand orphan,
        List<PendingWorkshopCommand> dropped,
      })>[];
      for (final key in orphans) {
        final orphan = state.commands[key];
        // Lo que depende de otro huérfano sale con él.
        if (orphan == null || state.commands.containsKey(orphan.dependsOn)) {
          continue;
        }
        result.add((orphan: orphan, dropped: _dropOrphan(state, orphan, at)));
      }
      await _save(scope, state);
      return result;
    });
    return [
      for (final entry in swept)
        _orphanRun(
          scope,
          entry.orphan,
          WorkshopCommandTrigger.resume,
          entry.dropped,
        ),
    ];
  }

  /// Sólo un recibo completo saca un comando de la bandeja: una respuesta sin
  /// `operation_id` o sin `replayed` no prueba que se escribió y queda como
  /// resultado incierto, con su llave (revisión del 2026-09-28). Un guardado
  /// del trabajo que pidió su factura (`p_invoice`) necesita además que el
  /// recibo diga qué pasó con ella: sin eso, un servidor que no la hizo
  /// sacaría el comando y la factura quedaría sin hacer (revisión de Codex).
  static const _invoiceActions = {
    'created',
    'synced',
    'protected',
    'posted',
    'none',
    'failed',
  };

  static Map<String, dynamic> _validReceipt(
    PendingWorkshopCommand command,
    Map<String, dynamic> response,
    String tenantId,
  ) {
    // El cambio de estado tiene su propio comprobante: sólo sale el que dice
    // este trabajo, este estado y esta llave (la misma regla que el
    // coordinador de la transición).
    if (command.kind == WorkshopCommandKind.jobStatusTransition) {
      final request = MechanicJobStatusTransitionRequest(
        jobId: '${command.params['p_job_id']}',
        statusId: '${command.params['p_status_id']}',
        operationKey: command.operationKey,
      );
      if (!request.matchesReceipt(response)) {
        throw const FormatException(
            'Comprobante del cambio de estado incompleto o de otro cambio');
      }
      return response;
    }
    // La decisión de garantía: sólo sale el evento de este trabajo, esta
    // llave, esta decisión y este motivo (la regla del coordinador de
    // garantías). Su repetición no trae `operation_id`, pero el evento es el
    // mismo. Es la fila del evento: trae su `id` y su taller, que tiene que
    // ser el de esta bandeja (revisión de Codex, 2026-09-29).
    if (command.kind == WorkshopCommandKind.jobWarrantyDecision) {
      final request = warrantyDecisionRequestOf(command);
      final eventId = response['id'];
      if (request == null ||
          !request.matchesEvent(response) ||
          eventId is! String ||
          eventId.trim().isEmpty ||
          response['tenant_id'] != tenantId) {
        throw const FormatException(
            'Comprobante de la decisión de garantía incompleto o de otra '
            'decisión');
      }
      return response;
    }
    // El registro de la garantía de un trabajo nuevo: el evento de este
    // trabajo, este trabajo original y esta llave (o el registro que ya
    // estaba, que el servidor devuelve como repetición), de este taller.
    if (command.kind == WorkshopCommandKind.jobWarrantyRegistration) {
      final request = warrantyRegistrationRequestOf(command);
      final eventId = response['id'];
      if (request == null ||
          !request.matchesResponse(response) ||
          eventId is! String ||
          eventId.trim().isEmpty ||
          response['tenant_id'] != tenantId) {
        throw const FormatException(
            'Comprobante del registro de la garantía incompleto o de otro '
            'registro');
      }
      return response;
    }
    final operationId = response['operation_id'];
    if (operationId is! String ||
        operationId.isEmpty ||
        response['replayed'] is! bool) {
      throw const FormatException('Respuesta sin recibo completo');
    }
    // El alta: el trabajo con el id que eligió el formulario, de este taller.
    if (command.kind == WorkshopCommandKind.jobCreate) {
      final job = response['job'];
      final requested = command.params['p_job'];
      if (job is! Map ||
          requested is! Map ||
          job['id'] == null ||
          job['id'] != requested['id'] ||
          job['tenant_id'] != tenantId) {
        throw const FormatException('Recibo del alta de otro trabajo');
      }
      // La consulta del recibo lleva el contenido y el servidor dice si es
      // el que escribió esa llave: el recibo de otro contenido no confirma
      // éste (revisión de Codex del alta, 2026-09-29).
      if (response['payload_matches'] == false) {
        throw const FormatException(
            'El recibo del alta es de otro contenido con la misma llave');
      }
      return response;
    }
    final invoice = response['invoice'];
    final needsInvoice =
        command.kind == WorkshopCommandKind.jobInvoiceContinuation ||
            (command.kind == WorkshopCommandKind.jobLineSave &&
                command.params['p_invoice'] == true);
    if (needsInvoice &&
        (invoice is! Map || !_invoiceActions.contains(invoice['action']))) {
      throw const FormatException('Recibo sin el resultado de la factura');
    }
    // La continuación que sigue en `failed` no sale de la bandeja: espera y
    // se vuelve a intentar.
    if (command.kind == WorkshopCommandKind.jobInvoiceContinuation &&
        invoice is Map &&
        invoice['action'] == 'failed') {
      final error = invoice['error'];
      throw WorkshopInvoicePendingException(
        code: error is Map ? error['code']?.toString() : null,
        message: error is Map ? error['message']?.toString() : null,
      );
    }
    return response;
  }

  /// Un guardado del trabajo escrito cuya factura quedó en `failed` deja su
  /// continuación en la bandeja, en la misma escritura que lo retira: sin
  /// ella, la factura esperaba a otro Guardar y un reinicio la dejaba
  /// pendiente para siempre (revisión del 2026-09-28). Una por trabajo: la
  /// del guardado más nuevo, que hace la factura con lo que el trabajo tiene
  /// ahora. Un guardado escrito con la factura resuelta retira la que hubiera.
  static void _continueInvoice(
    _OutboxState state,
    PendingWorkshopCommand command,
    WorkshopCommandOutcome outcome,
    Map<String, dynamic>? response,
    DateTime now,
  ) {
    if (!outcome.wrote ||
        command.kind != WorkshopCommandKind.jobLineSave ||
        command.params['p_invoice'] != true ||
        command.jobId == null) {
      return;
    }
    state.commands.removeWhere((_, other) =>
        other.kind == WorkshopCommandKind.jobInvoiceContinuation &&
        other.jobId == command.jobId);
    final invoice = response?['invoice'];
    if (invoice is Map && invoice['action'] == 'failed') {
      final continuation =
          PendingWorkshopCommand.invoiceContinuationOf(command, createdAt: now);
      state.commands[continuation.operationKey] = continuation;
    }
  }

  Future<Map<String, dynamic>> _send(PendingWorkshopCommand command) async {
    final fault = _takeDebugFault();
    if (fault == WorkshopOutboxDebugFault.offlineBeforeSend) {
      throw const WorkshopCommandTransportException(
        'Sin red (falla de depuración antes de enviar)',
      );
    }
    final response = await _transport.send(command.kind, command.params);
    if (fault == WorkshopOutboxDebugFault.loseResponseAfterCommit) {
      _debugLoseProbe = true;
      throw const WorkshopCommandTransportException(
        'Respuesta perdida (falla de depuración después de escribir)',
      );
    }
    return response;
  }

  bool _debugLoseProbe = false;

  Future<Map<String, dynamic>?> _probe(
    WorkshopCommandScope scope,
    PendingWorkshopCommand command,
  ) {
    if (_debugLoseProbe) {
      _debugLoseProbe = false;
      throw const WorkshopCommandTransportException(
        'Sin red para buscar el recibo (falla de depuración)',
      );
    }
    return _transport.probe(scope, command);
  }

  WorkshopOutboxDebugFault? _takeDebugFault() {
    if (!kDebugMode) return null;
    final fault = _debugNextFault;
    if (fault != null && --_debugFaultsLeft <= 0) _debugNextFault = null;
    return fault;
  }

  void _journal(_OutboxState state, WorkshopCommandAttempt attempt) {
    state.attempts.add(attempt.toJson());
    final overflow = state.attempts.length - maxJournaledAttempts;
    if (overflow > 0) {
      state.attempts.removeRange(0, overflow);
      state.droppedAttempts += overflow;
    }
  }

  /// Cuánto espera la reanudación automática después del intento [attempts]:
  /// 1, 2, 4… minutos, hasta una hora. Un comando que el servidor no contesta
  /// (un 504) no se reenvía cada pocos minutos para siempre.
  static Duration backoffAfter(int attempts) {
    final doublings = (attempts - 1).clamp(0, 6);
    return Duration(minutes: (1 << doublings).clamp(1, 60));
  }

  /// Reenvía lo pendiente (de una bici o un trabajo, o todo), del más viejo
  /// al más nuevo. Una bici o un trabajo es una cola: si un comando sigue sin
  /// respuesta, los siguientes que escriben lo mismo
  /// ([PendingWorkshopCommand.queueKeys]) esperan, porque se armaron sobre lo
  /// que ese comando quizá ya cambió. Con [respectBackoff] (la
  /// reanudación automática) se salta lo que se intentó hace menos de
  /// [backoffAfter]; quien abre la bici o el trabajo reenvía igual. Con
  /// [sweepImages], al abrir la sesión, además borra las fotos de sesiones que
  /// ya no existen y que ningún comando pendiente lleva.
  Future<List<WorkshopCommandRun>> resume(
    WorkshopCommandScope scope, {
    String? bikeId,
    String? jobId,
    bool sweepImages = false,
    bool respectBackoff = false,
  }) async {
    if (concurrentSessions) {
      await _locked(() async {
        final state = await _load(scope);
        _beat(state);
        await _save(scope, state);
      });
    }
    final runs = <WorkshopCommandRun>[...await _sweepOrphans(scope)];
    final now = _clock();
    // Lo que comparte cola con un comando ilegible espera: puede ser anterior.
    final waiting = await _unreadableQueueKeys(scope);
    // De una bici, también lo que toca su ficha desde un trabajo; y antes, lo
    // anterior que escribe lo mismo, aunque sea de otra bici o trabajo.
    final needed = <String>{};
    final selected = <PendingWorkshopCommand>[];
    for (final command in (await pending(scope)).reversed) {
      final matches = (jobId == null || command.jobId == jobId) &&
          (bikeId == null || command.queueKeys.contains('bike:$bikeId'));
      if (matches || command.queueKeys.any(needed.contains)) {
        selected.insert(0, command);
        needed.addAll(command.queueKeys);
      }
    }
    for (final command in selected) {
      final queueKeys = command.queueKeys;
      if (queueKeys.any(waiting.contains)) {
        waiting.addAll(queueKeys);
        continue;
      }
      final lastAttemptAt = command.lastAttemptAt;
      if (respectBackoff &&
          (command.pausedForInvoiceData ||
              (lastAttemptAt != null &&
                  now.difference(lastAttemptAt) <
                      backoffAfter(command.attempts)))) {
        waiting.addAll(queueKeys);
        continue;
      }
      try {
        final run = await this.run(
          scope,
          command.operationKey,
          trigger: WorkshopCommandTrigger.resume,
        );
        runs.add(run);
        if (!run.outcome.isFinal) waiting.addAll(queueKeys);
      } on StateError {
        // Otro intento lo resolvió mientras tanto.
      } on WorkshopScopeChangedException {
        return runs;
      }
    }
    if (sweepImages) {
      await sweepOrphanImages(scope);
    } else {
      await _retryMarkedDeletions(scope);
    }
    await flushAttempts(scope);
    return runs;
  }

  /// Lo que quedó borrándose (un borrado que falló) se vuelve a intentar en
  /// cada reanudación, no sólo al abrir la sesión: la app puede quedar
  /// abierta días (revisión de Codex del barrido, 2026-09-29).
  Future<void> _retryMarkedDeletions(WorkshopCommandScope scope) async {
    final marked = await _locked(() async => [
          for (final image in (await _load(scope)).images.values)
            if (image.deletingAt != null && image.deletedAt == null) image,
        ]);
    if (marked.isNotEmpty) await _removeOrphans(scope, marked);
  }

  /// Saca un comando sin enviarlo. Sus fotos se borran sólo si ninguna bici
  /// las tiene: si el comando alcanzó a escribirse, la bici ya las muestra.
  Future<WorkshopCommandRun?> discard(
    WorkshopCommandScope scope,
    String operationKey,
  ) async {
    final startedAt = _clock();
    final result = await _locked(() async {
      final state = await _load(scope);
      final current = state.commands[operationKey];
      if (current == null) return null;
      // Uno que una sesión viva está enviando no se descarta: el servidor
      // puede estar escribiéndolo, con sus adjuntos, y soltarlos los dejaría
      // al barrido (revisión de Codex del barrido, 2026-09-29).
      final sentAt = current.lastAttemptAt;
      if (current.inFlight &&
          _isLive(state, current.inFlightSession) &&
          sentAt != null &&
          startedAt.difference(sentAt) < sendTimeout) {
        throw const WorkshopCommandBusyException();
      }
      final command = state.commands.remove(operationKey)!;
      final dropped = _settleDependents(
        state,
        command,
        wrote: false,
        at: startedAt,
      );
      final images = state.images.values
          .where((image) => image.operationKey == operationKey)
          .toList();
      final attempt = WorkshopCommandAttempt(
        attemptId: _idFactory(),
        operationKey: operationKey,
        kind: command.kind,
        attemptNumber: command.attempts,
        trigger: WorkshopCommandTrigger.discard,
        outcome: WorkshopCommandOutcome.discarded,
        startedAt: startedAt,
        durationMs: 0,
        bikeId: command.bikeId,
        jobId: command.jobId,
        clientPlatform: _clientPlatform,
        appVersion: _appVersion,
      );
      _journal(state, attempt);
      await _save(scope, state);
      return (
        command: command,
        images: images,
        dropped: dropped,
        live: {
          for (final image in images)
            if (_isLive(state, image.ownerSession)) image.objectPath,
        },
      );
    });
    if (result == null) return null;
    // Las de un formulario de una sesión viva quedan sueltas: las libera él
    // al cerrarse. Las de una sesión muerta se borran si ninguna bici las tiene.
    final foreign = result.images
        .where((image) => !result.live.contains(image.objectPath))
        .toList();
    final own = result.live;
    if (own.isNotEmpty) {
      await _locked(() async {
        final state = await _load(scope);
        for (final path in own) {
          final image = state.images[path];
          if (image != null) {
            state.images[path] = image.copyWith(clearOperationKey: true);
          }
        }
        await _save(scope, state);
      });
    }
    if (foreign.isNotEmpty) await _removeOrphans(scope, foreign);
    final run = WorkshopCommandRun(
      command: result.command,
      outcome: WorkshopCommandOutcome.discarded,
      trigger: WorkshopCommandTrigger.discard,
      droppedFollowUps: result.dropped,
    );
    _runs.add(run);
    unawaited(flushAttempts(scope));
    return run;
  }

  // ==========================================================================
  // Fotos
  // ==========================================================================

  /// Anota una foto antes de subirla: si la app muere a mitad de la subida, la
  /// próxima sesión sabe que puede haber quedado un archivo.
  Future<void> recordImageIntent(
    WorkshopCommandScope scope,
    PendingBikeImage image,
  ) =>
      _locked(() async {
        final state = await _load(scope);
        state.images[image.objectPath] =
            image.copyWith(ownerSession: sessionId);
        _beat(state);
        await _save(scope, state);
      });

  Future<void> markImageUploaded(
    WorkshopCommandScope scope,
    String objectPath,
  ) =>
      _locked(() async {
        final state = await _load(scope);
        final image = state.images[objectPath];
        if (image == null) return;
        // Una subida que terminó después de que el barrido la diera por
        // abandonada y la borrara (aún sin archivo) dejó un archivo nuevo:
        // vuelve a quedar borrándose, y la reanudación lo borra (segunda
        // revisión de Codex del barrido, 2026-09-29). Ningún comando la toma.
        state.images[objectPath] = image.retired
            ? image.copyWith(
                uploaded: true,
                deletingAt: _clock(),
                clearDeletedAt: true,
              )
            : image.copyWith(uploaded: true);
        await _save(scope, state);
      });

  /// El formulario [ownerForm] se cerró sin guardar: las fotos que subió y que
  /// no van en un comando pendiente ya no las reclama nadie. Las de otro
  /// formulario abierto de la misma bici no se tocan.
  Future<void> releaseImages(
    WorkshopCommandScope scope, {
    required String ownerForm,
  }) async {
    final images = await _locked(() async {
      final state = await _load(scope);
      return state.images.values
          .where((image) => image.deletedAt == null)
          .where((image) =>
              image.ownerSession == sessionId && image.ownerForm == ownerForm)
          .where((image) =>
              image.operationKey == null ||
              !state.commands.containsKey(image.operationKey))
          .toList();
    });
    if (images.isNotEmpty) await _removeOrphans(scope, images);
  }

  /// Las fotos que anotó una sesión que ya no existe y que ningún comando
  /// pendiente lleva son huérfanas. Las de esta sesión, o de otra pestaña con
  /// latido, son de formularios que pueden seguir abiertos: ésas las libera
  /// cada formulario al cerrarse.
  ///
  /// Una que se estaba borrando se vuelve a borrar, sea de quien sea: su
  /// archivo quizá ya no está. Una lápida más vieja que [removedImageMemory]
  /// sale.
  Future<void> sweepOrphanImages(WorkshopCommandScope scope) async {
    final images = await _locked(() async {
      final state = await _load(scope);
      final now = _clock();
      final expired = [
        for (final image in state.images.values)
          if (image.deletedAt case final deletedAt?)
            if (now.difference(deletedAt) > removedImageMemory)
              image.objectPath,
      ];
      if (expired.isNotEmpty) {
        expired.forEach(state.images.remove);
        await _save(scope, state);
      }
      return state.images.values
          .where((image) => image.deletedAt == null)
          .where((image) =>
              image.deletingAt != null ||
              (!_isLive(state, image.ownerSession) &&
                  (image.operationKey == null ||
                      !state.commands.containsKey(image.operationKey))))
          .toList();
    });
    if (images.isNotEmpty) await _removeOrphans(scope, images);
  }

  /// Borra del almacenamiento las fotos y adjuntos que ningún trabajo ni bici
  /// muestra. Lo que se va a borrar queda marcado antes, bajo el candado y en
  /// la misma escritura que comprueba que nadie lo lleva; borrado, queda como
  /// lápida. Si el borrado falla, sigue marcado y el próximo barrido lo
  /// intenta de nuevo; mientras tanto ningún comando lo acepta.
  Future<void> _removeOrphans(
    WorkshopCommandScope scope,
    List<PendingBikeImage> images,
  ) async {
    final Set<String> referenced;
    try {
      referenced = await _transport.referencedImageUrls(
        scope,
        images.map((image) => image.publicUrl).toList(),
      );
    } catch (_) {
      // Sin saber qué muestran los trabajos y las bicis no se toca nada: ni
      // se borra ni se suelta un reclamo, que otro comando pudo tomar
      // mientras se preguntaba (revisión de Codex del barrido, 2026-09-29).
      return;
    }

    // Justo antes de borrar se vuelve a mirar la bandeja: otra pestaña pudo
    // ponerla en un comando, o la sesión dueña volvió a latir, mientras se
    // consultaban las bicis (revisión de Codex, 2026-09-28). Lo que ya no es
    // huérfano no se borra ni se toca. Lo que sí, se marca en esa misma
    // escritura, antes de soltar el candado: antes el borrado en Storage iba
    // sin marca, y otra ventana podía poner el adjunto en un alta o un
    // guardado de líneas mientras se borraba (revisión de Codex del alta,
    // 2026-09-29).
    final toDelete = await _locked(() async {
      final state = await _load(scope);
      final now = _clock();
      final marked = <PendingBikeImage>[];
      var changed = false;
      // Lo protege cualquier comando pendiente que lo lleve, no sólo el que
      // lo reclamó: un corte entre escribir el comando y su reclamo, o un
      // segundo comando con la misma URL, lo dejaban sin dueño (revisión de
      // Codex del barrido, 2026-09-29).
      final carried = {
        for (final command in state.commands.values) ...command.imageUrls,
      };
      // Sin Web Locks cada pestaña tiene su candado y la marca no excluye a
      // las otras: lo de otra sesión no se borra desde aquí (queda para una
      // sesión con candado compartido). Lo propio de un formulario que se
      // cerró, sí.
      final foreignAllowed = !(_crossTabLockUnavailable && concurrentSessions);
      for (final image in images) {
        final current = state.images[image.objectPath];
        if (current == null || current.deletedAt != null) continue;
        final orphan = current.deletingAt != null ||
            (!carried.contains(current.publicUrl) &&
                (current.ownerSession == sessionId
                    ? current.ownerForm == image.ownerForm
                    : foreignAllowed && !_isLive(state, current.ownerSession)));
        if (!orphan) continue;
        changed = true;
        if (referenced.contains(current.publicUrl)) {
          // Un trabajo o una bici ya lo muestra: no se borra, sólo sale.
          state.images.remove(current.objectPath);
          continue;
        }
        final mark = current.copyWith(
          clearOperationKey: true,
          deletingAt: current.deletingAt ?? now,
        );
        state.images[current.objectPath] = mark;
        marked.add(mark);
      }
      if (changed) await _save(scope, state);
      return marked;
    });
    if (toDelete.isEmpty) return;

    final removed = <String>{};
    final byBucket = <String, List<PendingBikeImage>>{};
    for (final image in toDelete) {
      byBucket.putIfAbsent(image.bucket, () => []).add(image);
    }
    for (final entry in byBucket.entries) {
      try {
        await _transport.removeImages(
          entry.key,
          entry.value.map((image) => image.objectPath).toList(),
        );
        removed.addAll(entry.value.map((image) => image.objectPath));
      } catch (_) {
        // Siguen marcadas: el próximo barrido lo intenta de nuevo.
      }
    }
    if (removed.isEmpty) return;

    await _locked(() async {
      final state = await _load(scope);
      final now = _clock();
      for (final path in removed) {
        final current = state.images[path];
        if (current != null) {
          state.images[path] = current.copyWith(deletedAt: now);
        }
      }
      await _save(scope, state);
    });
  }

  // ==========================================================================
  // Intentos
  // ==========================================================================

  /// Entrega los intentos anotados. Sin red o sin la función en el servidor,
  /// siguen en el equipo para la próxima vez.
  Future<void> flushAttempts(WorkshopCommandScope scope) async {
    if (!_flushing.add(scope.storageKey)) return;
    try {
      while (true) {
        final batch = await _locked(() async {
          final state = await _load(scope);
          return state.attempts.take(100).toList();
        });
        if (batch.isEmpty) return;
        // El servidor pone el taller y la persona de la sesión: con otra
        // cuenta adentro, los intentos esperan a su dueño.
        if (!_transport.isCurrent(scope)) return;
        try {
          await _transport.recordAttempts(batch);
        } catch (_) {
          return;
        }
        final sent = batch.map((attempt) => attempt['attempt_id']).toSet();
        await _locked(() async {
          final state = await _load(scope);
          state.attempts
              .removeWhere((attempt) => sent.contains(attempt['attempt_id']));
          await _save(scope, state);
        });
      }
    } on WorkshopOutboxPersistenceException catch (error) {
      // Se llama sin esperar después de cada intento: un almacenamiento que
      // no se deja leer o escribir no puede quedar como error sin atrapar.
      // Los intentos siguen en el equipo (o se reenvían y el servidor no los
      // duplica).
      debugPrint('Intentos del taller sin entregar: $error');
    } finally {
      _flushing.remove(scope.storageKey);
    }
  }

  /// Lo que la bandeja guarda sin enviar, para soporte en el propio equipo.
  Future<({int commands, int images, int attempts, int dropped})> counts(
    WorkshopCommandScope scope,
  ) =>
      _locked(() async {
        final state = await _load(scope);
        return (
          commands: state.commands.length,
          // Las borradas o borrándose no son de nadie: no cuentan.
          images: state.images.values.where((image) => !image.retired).length,
          attempts: state.attempts.length,
          dropped: state.droppedAttempts,
        );
      });
}
