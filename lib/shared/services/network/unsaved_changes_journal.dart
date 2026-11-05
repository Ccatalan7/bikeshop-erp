import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'connection_status.dart';
import 'operation_identity.dart';
import 'request_safety.dart';

/// Un guardado que no llegó al servidor y quedó en el equipo.
@immutable
class UnsavedChange {
  const UnsavedChange({
    required this.id,
    required this.createdAt,
    required this.method,
    required this.url,
    required this.headers,
    required this.label,
    required this.technicalName,
    required this.effect,
    required this.resourceKey,
    required this.notSent,
    this.userId,
    this.bodyBase64,
    this.bodyHash,
    this.detail,
    this.idempotencyKey,
    this.identityColumn,
    this.attempts = 1,
    this.lastError,
    this.lastTriedAt,
    this.serverRejected = false,
    this.inFlight = false,
  });

  final String id;
  final DateTime createdAt;
  final String? userId;
  final String method;
  final String url;

  /// Sólo los encabezados del contenido: nunca la sesión ni la llave pública,
  /// que se ponen frescos al reenviar.
  final Map<String, String> headers;
  final String? bodyBase64;
  final String? bodyHash;
  final String label;
  final String technicalName;
  final String? detail;
  final RequestEffect effect;
  final String resourceKey;
  final String? idempotencyKey;

  /// En un alta con identidad, la columna que la lleva (`id` o
  /// `idempotency_key`).
  final String? identityColumn;

  /// La conexión nunca se abrió: el servidor no recibió nada.
  final bool notSent;
  final int attempts;
  final String? lastError;
  final DateTime? lastTriedAt;

  /// El servidor lo recibió y dijo que no (o no cambió nada): reenviarlo solo
  /// daría lo mismo. Queda para que la persona lo mire.
  final bool serverRejected;

  /// Se anotó antes de mandarlo y todavía no hay respuesta. Una nota así que
  /// aparece al abrir la app es un guardado que quedó a medio camino cuando la
  /// app se cerró.
  final bool inFlight;

  /// Hay con qué reenviarlo (un cuerpo muy grande, como una foto, no se guarda).
  bool get canResend => bodyBase64 != null || method == 'DELETE';

  /// Reenviarlo no puede dejarlo dos veces.
  bool get resendIsHarmless =>
      effect == RequestEffect.keyedCommand ||
      effect == RequestEffect.repeatableWrite ||
      effect == RequestEffect.identifiedInsert;

  UnsavedChange copyWith({
    int? attempts,
    String? lastError,
    DateTime? lastTriedAt,
    bool? serverRejected,
    bool? inFlight,
    bool? notSent,
    String? bodyBase64,
    String? bodyHash,
    bool clearError = false,
  }) =>
      UnsavedChange(
        id: id,
        createdAt: createdAt,
        userId: userId,
        method: method,
        url: url,
        headers: headers,
        bodyBase64: bodyBase64 ?? this.bodyBase64,
        bodyHash: bodyHash ?? this.bodyHash,
        label: label,
        technicalName: technicalName,
        detail: detail,
        effect: effect,
        resourceKey: resourceKey,
        idempotencyKey: idempotencyKey,
        identityColumn: identityColumn,
        notSent: notSent ?? this.notSent,
        attempts: attempts ?? this.attempts,
        lastError: clearError ? null : (lastError ?? this.lastError),
        lastTriedAt: lastTriedAt ?? this.lastTriedAt,
        serverRejected: serverRejected ?? this.serverRejected,
        inFlight: inFlight ?? this.inFlight,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
        'user_id': userId,
        'method': method,
        'url': url,
        'headers': headers,
        'body': bodyBase64,
        'body_hash': bodyHash,
        'label': label,
        'technical_name': technicalName,
        'detail': detail,
        'effect': effect.name,
        'resource_key': resourceKey,
        'idempotency_key': idempotencyKey,
        'identity_column': identityColumn,
        'not_sent': notSent,
        'attempts': attempts,
        'last_error': lastError,
        'last_tried_at': lastTriedAt?.toUtc().toIso8601String(),
        'server_rejected': serverRejected,
        'in_flight': inFlight,
      };

  static UnsavedChange? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    final id = json['id'] as String?;
    final method = json['method'] as String?;
    final url = json['url'] as String?;
    final created = DateTime.tryParse('${json['created_at'] ?? ''}');
    final effect = RequestEffect.values
        .where((value) => value.name == json['effect'])
        .firstOrNull;
    if (id == null || method == null || url == null || created == null) {
      return null;
    }
    return UnsavedChange(
      id: id,
      createdAt: created.toLocal(),
      userId: json['user_id'] as String?,
      method: method,
      url: url,
      headers: (json['headers'] is Map)
          ? Map<String, String>.from(json['headers'] as Map)
          : const {},
      bodyBase64: json['body'] as String?,
      bodyHash: json['body_hash'] as String?,
      label: (json['label'] as String?) ?? 'Cambio',
      technicalName: (json['technical_name'] as String?) ?? '',
      detail: json['detail'] as String?,
      effect: effect ?? RequestEffect.insert,
      resourceKey: (json['resource_key'] as String?) ?? '$method $url',
      idempotencyKey: json['idempotency_key'] as String?,
      identityColumn: json['identity_column'] as String?,
      notSent: json['not_sent'] == true,
      attempts: (json['attempts'] as num?)?.toInt() ?? 1,
      lastError: json['last_error'] as String?,
      lastTriedAt:
          DateTime.tryParse('${json['last_tried_at'] ?? ''}')?.toLocal(),
      serverRejected: json['server_rejected'] == true,
      inFlight: json['in_flight'] == true,
    );
  }
}

/// Dónde vive la bandeja en el equipo.
abstract class UnsavedChangesStore {
  Future<Map<String, String>> readAll();
  Future<void> write(String id, String value);
  Future<void> remove(String id);
}

class SharedPreferencesUnsavedChangesStore implements UnsavedChangesStore {
  static const _prefix = 'vb_unsaved_change.';
  SharedPreferences? _preferences;

  Future<SharedPreferences> _instance() async =>
      _preferences ??= await SharedPreferences.getInstance();

  @override
  Future<Map<String, String>> readAll() async {
    final preferences = await _instance();
    await preferences.reload();
    return {
      for (final key in preferences.getKeys())
        if (key.startsWith(_prefix))
          key.substring(_prefix.length): preferences.getString(key) ?? '',
    };
  }

  @override
  Future<void> write(String id, String value) async {
    final preferences = await _instance();
    final ok = await preferences.setString('$_prefix$id', value);
    if (!ok) throw StateError('No se pudo guardar en el equipo');
  }

  @override
  Future<void> remove(String id) async {
    final preferences = await _instance();
    await preferences.remove('$_prefix$id');
  }
}

/// Lo que pasó al reenviar.
enum UnsavedChangeResend {
  /// Llegó: el cambio quedó guardado y salió de la bandeja.
  saved,

  /// El servidor lo recibió y lo rechazó: sigue en la bandeja con su motivo.
  rejected,

  /// Tampoco llegó esta vez.
  stillOffline,

  /// Llegó, pero el servidor no pudo atenderlo ahora (5xx): sigue en la
  /// bandeja y se puede volver a probar.
  serverBusy,

  /// No hay con qué reenviarlo, o es de otra cuenta.
  unavailable,
}

/// La bandeja de los cambios que no llegaron al servidor.
///
/// Lo que hacen los ERP profesionales con una conexión que se corta: nada se
/// pierde en silencio. Un guardado que no llegó después de los reintentos del
/// transporte queda guardado **en el equipo**, con su nombre de taller
/// («Pago de venta · $ 12.000»), y se ve hasta que llega o alguien lo descarta.
///
/// **Se anota antes de mandarlo** ([beginWrite]), como el diario de una base
/// de datos: si la app se cierra o se cae mientras dice «Guardando…», al
/// abrirla de nuevo el guardado aparece como «quedó a medio camino» en vez de
/// perderse. La nota no se ve mientras espera su respuesta; se borra apenas
/// llega una respuesta y pasa a la bandeja visible si el transporte se rinde.
///
/// Al volver la conexión se reenvía solo lo que no puede quedar dos veces
/// **aunque la persona lo haya repetido**:
/// - un comando o un alta cuya llave sostiene su dueño
///   ([StableOperationKeys]): cualquier repetición sale con la misma llave y
///   el servidor la reconoce;
/// - un cambio repetible (`PATCH`/`DELETE`) que nunca salió, de los últimos
///   [autoResendWindow], con sólo los campos que nada más nuevo cambió.
///
/// Lo demás espera a la persona: con una llave por intento, su repetición y el
/// reenvío quedarían dos veces. Un guardado posterior igual (misma llave,
/// mismo recurso o mismo contenido) que sí llega lo resuelve solo.
class UnsavedChangesJournal extends ChangeNotifier {
  UnsavedChangesJournal({
    UnsavedChangesStore? store,
    String? Function()? currentUserId,
    String? Function()? currentAccessToken,
    String? apiKey,
    this.autoResendWindow = const Duration(minutes: 10),
    this.keyedResendWindow = const Duration(hours: 24),
    this.maxAutoAttempts = 4,
  })  : _store = store ?? SharedPreferencesUnsavedChangesStore(),
        _currentUserId = currentUserId,
        _currentAccessToken = currentAccessToken,
        _apiKey = apiKey;

  static UnsavedChangesJournal instance = UnsavedChangesJournal();

  /// Encabezado con que sale un reenvío: el transporte no crea otra entrada
  /// si falla, porque ésta ya existe.
  static const String replayHeader = 'x-vb-unsaved-change';

  /// Cuerpo máximo que se guarda para reenviar (una foto no entra).
  static const int maxStoredBody = 256 * 1024;

  static const Set<String> _keptHeaders = {
    'content-type',
    'prefer',
    'accept',
    'accept-profile',
    'content-profile',
    'x-upsert',
    'cache-control',
  };

  final UnsavedChangesStore _store;
  String? Function()? _currentUserId;
  String? Function()? _currentAccessToken;
  String? _apiKey;
  final Duration autoResendWindow;
  final Duration keyedResendWindow;

  /// Después de tantos intentos lo decide la persona: un comando que el
  /// servidor no logra terminar (PostgREST reintenta un 40001 sin fin) no se
  /// manda solo cada vez que vuelve la conexión.
  final int maxAutoAttempts;

  final Map<String, UnsavedChange> _entries = {};

  /// Notas de esta ejecución que esperan su respuesta: no se muestran.
  final Set<String> _live = {};
  final Set<String> _sending = {};
  bool _loaded = false;
  int _recentlySaved = 0;
  StreamSubscription<void>? _reconnections;
  Future<http.StreamedResponse> Function(http.BaseRequest request)? _send;

  /// Conecta la bandeja con la app: con qué se manda y quién está conectado.
  void attach({
    required Future<http.StreamedResponse> Function(http.BaseRequest) send,
    required String? Function() currentUserId,
    required String? Function() currentAccessToken,
    required String apiKey,
    ConnectionStatus? status,
  }) {
    _send = send;
    _currentUserId = currentUserId;
    _currentAccessToken = currentAccessToken;
    _apiKey = apiKey;
    unawaited(_reconnections?.cancel());
    _reconnections = (status ?? ConnectionStatus.instance)
        .reconnections
        .listen((_) => unawaited(resendSafe()));
  }

  bool get isLoaded => _loaded;

  /// Lo que ve la persona conectada: lo suyo, lo más nuevo primero.
  List<UnsavedChange> get pending {
    final user = _currentUserId?.call();
    final visible = _entries.values
        .where((entry) => !_live.contains(entry.id) && !entry.inFlight)
        .where((entry) => entry.userId == null || entry.userId == user)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return visible;
  }

  int get pendingCount => pending.length;

  bool isSending(String id) => _sending.contains(id);

  /// Cuántos se guardaron en el último reenvío automático (para decirlo).
  int takeRecentlySaved() {
    final value = _recentlySaved;
    _recentlySaved = 0;
    return value;
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await _store.readAll();
      for (final entry in raw.entries) {
        final change = UnsavedChange.fromJson(_tryDecode(entry.value));
        if (change == null || _live.contains(change.id)) continue;
        if (change.inFlight) {
          // Se anotó, salió (o iba a salir) y la app se cerró antes de saber.
          final interrupted = change.copyWith(
            inFlight: false,
            notSent: false,
            lastError: 'La app se cerró antes de saber si llegó.',
          );
          _entries[change.id] = interrupted;
          unawaited(_persist(interrupted));
          continue;
        }
        _entries[change.id] = change;
      }
    } catch (error) {
      debugPrint('⚠️ [UnsavedChanges] no se pudo leer la bandeja: $error');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Anota en el equipo un guardado **antes** de mandarlo. Devuelve el número
  /// de la nota, o `null` si no va a la bandeja (una lectura, la sesión, una
  /// función, lo que tiene su propia cola).
  ///
  /// Un guardado con la misma llave que uno pendiente lo reemplaza: es la
  /// misma operación y éste trae lo último que la persona dejó.
  Future<String?> beginWrite({
    required http.BaseRequest request,
    required RequestSafety safety,
    required List<int>? body,
  }) async {
    if (!safety.belongsInJournal) return null;
    final note = _changeFor(
      request: request,
      safety: safety,
      body: body,
      notSent: true,
      error: null,
    ).copyWith(inFlight: true);
    _entries[note.id] = note;
    _live.add(note.id);
    final key = safety.idempotencyKey;
    if (key != null) {
      final superseded = _entries.values
          .where((entry) =>
              entry.id != note.id &&
              !_live.contains(entry.id) &&
              !_sending.contains(entry.id) &&
              entry.idempotencyKey == key)
          .toList();
      for (final entry in superseded) {
        _entries.remove(entry.id);
        unawaited(_store.remove(entry.id));
      }
      if (superseded.isNotEmpty) notifyListeners();
    }
    await _persist(note);
    return note.id;
  }

  /// Llegó una respuesta (la que sea): la nota ya no hace falta. Un rechazo
  /// del servidor lo ve la persona en su pantalla, no en la bandeja.
  void settle(String? noteId) {
    if (noteId == null) return;
    _live.remove(noteId);
    if (_entries.remove(noteId) != null) unawaited(_store.remove(noteId));
  }

  /// El transporte se rindió: la nota pasa a «Sin guardar».
  Future<UnsavedChange?> fail(
    String? noteId, {
    required http.BaseRequest request,
    required RequestSafety safety,
    required List<int>? body,
    required bool notSent,
    required Object error,
  }) async {
    final note = noteId == null ? null : _entries[noteId];
    if (note == null) {
      return record(
        request: request,
        safety: safety,
        body: body,
        notSent: notSent,
        error: error,
      );
    }
    _live.remove(note.id);
    final change = note.copyWith(
      inFlight: false,
      notSent: notSent,
      lastError: _describeError(error),
      lastTriedAt: DateTime.now(),
    );
    _entries[change.id] = change;
    notifyListeners();
    await _persist(change);
    return change;
  }

  /// Guarda en el equipo un guardado que no llegó (sin nota previa).
  Future<UnsavedChange?> record({
    required http.BaseRequest request,
    required RequestSafety safety,
    required List<int>? body,
    required bool notSent,
    required Object error,
  }) async {
    if (!safety.belongsInJournal) return null;
    final change = _changeFor(
      request: request,
      safety: safety,
      body: body,
      notSent: notSent,
      error: error,
    );
    _entries[change.id] = change;
    notifyListeners();
    await _persist(change);
    return change;
  }

  UnsavedChange _changeFor({
    required http.BaseRequest request,
    required RequestSafety safety,
    required List<int>? body,
    required bool notSent,
    required Object? error,
  }) {
    final keepBody = body != null && body.length <= maxStoredBody;
    return UnsavedChange(
      id: const Uuid().v4(),
      createdAt: DateTime.now(),
      userId: _userIdFromRequest(request) ?? _currentUserId?.call(),
      method: request.method.toUpperCase(),
      url: request.url.toString(),
      headers: {
        for (final entry in request.headers.entries)
          if (_keptHeaders.contains(entry.key.toLowerCase()))
            entry.key.toLowerCase(): entry.value,
      },
      bodyBase64: keepBody ? base64Encode(body) : null,
      bodyHash: body == null ? null : contentHashFor(safety, body),
      label: safety.label,
      technicalName: safety.technicalName,
      detail: safety.detail,
      effect: safety.effect,
      resourceKey: safety.resourceKey,
      idempotencyKey: safety.idempotencyKey,
      identityColumn: safety.identityColumn,
      notSent: notSent,
      lastError: error == null ? null : _describeError(error),
      lastTriedAt: DateTime.now(),
    );
  }

  /// Algo que escribe llegó bien: resuelve lo pendiente que ya no hace falta.
  ///
  /// Un cambio repetible pendiente sobre el mismo registro pierde sólo los
  /// campos que el nuevo también fijó: si el pendiente cambiaba el teléfono y
  /// el nuevo el correo, el teléfono sigue esperando su reenvío.
  void noteSuccess(RequestSafety safety, List<int>? body) {
    if (!safety.isWrite || _entries.isEmpty) return;
    final hash = body == null ? null : contentHashFor(safety, body);
    final resolved = <UnsavedChange>[];
    final trimmed = <UnsavedChange>[];
    for (final entry in _entries.values) {
      if (_live.contains(entry.id) || _sending.contains(entry.id)) continue;
      if (safety.idempotencyKey != null &&
          entry.idempotencyKey == safety.idempotencyKey) {
        resolved.add(entry);
        continue;
      }
      if (entry.resourceKey != safety.resourceKey) continue;
      if (entry.effect == RequestEffect.repeatableWrite &&
          safety.effect == RequestEffect.repeatableWrite) {
        final rest = entry.method == 'PATCH' && body != null
            ? _withoutFieldsOf(entry, body)
            : null;
        if (rest == null) {
          resolved.add(entry);
        } else {
          trimmed.add(rest);
        }
        continue;
      }
      if (hash != null && entry.bodyHash == hash) resolved.add(entry);
    }
    for (final entry in resolved) {
      _entries.remove(entry.id);
      unawaited(_store.remove(entry.id));
    }
    for (final entry in trimmed) {
      _entries[entry.id] = entry;
      unawaited(_persist(entry));
    }
    if (resolved.isNotEmpty || trimmed.isNotEmpty) notifyListeners();
  }

  /// [entry] sin los campos que [newer] ya fijó; `null` si no le queda nada
  /// propio (o si no se puede leer como un objeto).
  UnsavedChange? _withoutFieldsOf(UnsavedChange entry, List<int> newer) {
    final pendingBody = entry.bodyBase64;
    if (pendingBody == null) return null;
    try {
      final older = jsonDecode(utf8.decode(base64Decode(pendingBody)));
      final latest = jsonDecode(utf8.decode(newer));
      if (older is! Map || latest is! Map) return null;
      final rest = <String, Object?>{
        for (final field in older.entries)
          if (!latest.containsKey(field.key)) '${field.key}': field.value,
      };
      final own = rest.keys.where((key) => !_clockFields.contains(key));
      if (own.isEmpty) return null;
      final bytes = utf8.encode(jsonEncode(rest));
      return entry.copyWith(
        bodyBase64: base64Encode(bytes),
        bodyHash: bodyHashOf(bytes),
      );
    } catch (_) {
      return null;
    }
  }

  /// Reenvía [id] ahora.
  Future<UnsavedChangeResend> resend(String id) async {
    final change = _entries[id];
    final send = _send;
    if (change == null || send == null || _sending.contains(id)) {
      return UnsavedChangeResend.unavailable;
    }
    final user = _currentUserId?.call();
    if (!change.canResend ||
        (change.userId != null && user != null && change.userId != user)) {
      return UnsavedChangeResend.unavailable;
    }
    final token = _currentAccessToken?.call();
    if (token == null || token.isEmpty) return UnsavedChangeResend.unavailable;

    _sending.add(id);
    notifyListeners();
    try {
      final request = http.Request(change.method, Uri.parse(change.url))
        ..headers.addAll(change.headers)
        ..headers['authorization'] = 'Bearer $token'
        ..headers[replayHeader] = change.id;
      final apiKey = _apiKey;
      if (apiKey != null && apiKey.isNotEmpty) {
        request.headers['apikey'] = apiKey;
      }
      if (change.bodyBase64 != null) {
        request.bodyBytes = base64Decode(change.bodyBase64!);
      }
      final streamed = await send(request);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 401) {
        // La sesión venció mientras esperaba: no es un rechazo del cambio. Se
        // reenvía cuando la sesión se renueve.
        return UnsavedChangeResend.unavailable;
      }
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      if ((ok && !_matchedNothing(change, response)) ||
          await _alreadyThere(change, response, token)) {
        _entries.remove(id);
        await _store.remove(id);
        return UnsavedChangeResend.saved;
      }
      if (!ok && response.statusCode >= 500) {
        // El servidor no pudo atenderlo ahora: es como no haber llegado.
        final updated = change.copyWith(
          attempts: change.attempts + 1,
          lastError: _describeResponse(response),
          lastTriedAt: DateTime.now(),
        );
        _entries[id] = updated;
        await _persist(updated);
        return UnsavedChangeResend.serverBusy;
      }
      final updated = change.copyWith(
        attempts: change.attempts + 1,
        lastError: ok
            ? 'No se aplicó: el registro cambió o ya no existe. Ábrelo, '
                'revisa y vuelve a hacerlo.'
            : _describeResponse(response),
        lastTriedAt: DateTime.now(),
        serverRejected: true,
      );
      _entries[id] = updated;
      await _persist(updated);
      return UnsavedChangeResend.rejected;
    } catch (error) {
      final updated = change.copyWith(
        attempts: change.attempts + 1,
        lastError: _describeError(error),
        lastTriedAt: DateTime.now(),
      );
      _entries[id] = updated;
      await _persist(updated);
      return UnsavedChangeResend.stillOffline;
    } finally {
      _sending.remove(id);
      notifyListeners();
    }
  }

  /// Lo saca de la bandeja sin mandarlo.
  Future<void> discard(String id) async {
    if (_entries.remove(id) == null) return;
    notifyListeners();
    await _store.remove(id);
  }

  /// Reenvía, del más viejo al más nuevo, lo que no puede quedar dos veces
  /// aunque la persona lo haya repetido (ver la clase).
  Future<int> resendSafe() async {
    if (_send == null) return 0;
    await RecordIdentities.load();
    final now = DateTime.now();
    final candidates = pending.reversed.where((entry) {
      if (!entry.canResend || _sending.contains(entry.id)) return false;
      if (entry.serverRejected || entry.attempts >= maxAutoAttempts) {
        return false;
      }
      return resendsByItself(entry, now: now);
    }).toList();
    var saved = 0;
    for (final entry in candidates) {
      final result = await resend(entry.id);
      if (result == UnsavedChangeResend.saved) saved += 1;
      if (result == UnsavedChangeResend.stillOffline) break;
    }
    if (saved > 0) {
      _recentlySaved += saved;
      notifyListeners();
    }
    return saved;
  }

  /// Si [entry] se manda solo al volver la conexión.
  bool resendsByItself(UnsavedChange entry, {DateTime? now}) {
    final age = (now ?? DateTime.now()).difference(entry.createdAt);
    switch (entry.effect) {
      case RequestEffect.keyedCommand:
      case RequestEffect.identifiedInsert:
        return age <= keyedResendWindow &&
            StableOperationKeys.holds(entry.idempotencyKey);
      case RequestEffect.repeatableWrite:
        return entry.notSent && age <= autoResendWindow;
      case RequestEffect.read:
      case RequestEffect.insert:
      case RequestEffect.auth:
      case RequestEffect.function:
        return false;
    }
  }

  Future<void> _persist(UnsavedChange change) async {
    try {
      await _store.write(change.id, jsonEncode(change.toJson()));
    } catch (error) {
      debugPrint('⚠️ [UnsavedChanges] no se pudo guardar en el equipo: $error');
    }
  }

  @override
  void dispose() {
    unawaited(_reconnections?.cancel());
    super.dispose();
  }

  /// La huella de un cuerpo, sin las horas que el equipo le pone a cada
  /// intento (`created_at`, `updated_at`): un segundo guardado igual tiene la
  /// misma huella aunque se haya mandado un minuto después.
  /// La huella con que se reconoce el mismo contenido. En un alta con
  /// identidad no cuenta el `id`: un cliente igual guardado con otra identidad
  /// (la persona lo volvió a escribir) es el mismo cliente.
  static String contentHashFor(RequestSafety safety, List<int> body) =>
      safety.effect == RequestEffect.identifiedInsert
          ? bodyHashOf(body, ignoring: const {'id'})
          : bodyHashOf(body);

  static String bodyHashOf(List<int> body, {Set<String> ignoring = const {}}) {
    Object? normalized;
    try {
      normalized = _withoutClockFields(jsonDecode(utf8.decode(body)));
    } catch (_) {
      return crypto.sha256.convert(body).toString();
    }
    if (ignoring.isNotEmpty) {
      Object? strip(Object? row) => row is Map
          ? {
              for (final field in row.entries)
                if (!ignoring.contains(field.key)) field.key: field.value,
            }
          : row;
      normalized = normalized is List
          ? normalized.map(strip).toList()
          : strip(normalized);
    }
    return crypto.sha256
        .convert(utf8.encode(_canonicalJson(normalized)))
        .toString();
  }

  static const Set<String> _clockFields = {
    'created_at',
    'updated_at',
    'p_client_sent_at',
  };

  static Object? _withoutClockFields(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (!_clockFields.contains(entry.key))
            '${entry.key}': _withoutClockFields(entry.value),
      };
    }
    if (value is List) return value.map(_withoutClockFields).toList();
    return value;
  }

  static String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
    }
    if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
    return jsonEncode(value);
  }

  static Object? _tryDecode(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  /// La cuenta que mandó la petición, leída del JWT (sin verificarlo: sólo
  /// decide a quién se le muestra en este equipo).
  static String? _userIdFromRequest(http.BaseRequest request) {
    final authorization = request.headers.entries
        .where((entry) => entry.key.toLowerCase() == 'authorization')
        .map((entry) => entry.value)
        .firstOrNull;
    if (authorization == null || !authorization.startsWith('Bearer ')) {
      return null;
    }
    final parts = authorization.substring(7).split('.');
    if (parts.length != 3) return null;
    try {
      final payload =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final json = jsonDecode(payload);
      if (json is Map && json['role'] == 'authenticated') {
        final sub = json['sub'];
        return sub is String && sub.isNotEmpty ? sub : null;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String _describeError(Object error) {
    final text = error.toString();
    if (text.contains('Failed host lookup') ||
        text.contains('Network is unreachable') ||
        text.contains('No route to host') ||
        text.contains('Connection refused')) {
      return 'Sin internet: no se pudo conectar con el servidor.';
    }
    if (text.contains('Connection reset') ||
        text.contains('Connection closed') ||
        text.contains('Broken pipe')) {
      return 'La conexión se cortó a mitad del envío.';
    }
    if (text.contains('no respondió a tiempo') || text.contains('Timeout')) {
      return 'El servidor no respondió a tiempo.';
    }
    return text.length > 160 ? '${text.substring(0, 157)}…' : text;
  }

  /// Una edición que pidió de vuelta las filas y no recibió ninguna no tocó
  /// nada: el filtro ya no calza (otro la cambió, o se borró). Un borrado
  /// que no encuentra la fila sí dejó las cosas como se pedían.
  static bool _matchedNothing(UnsavedChange change, http.Response response) {
    if (change.method != 'PATCH' && change.method != 'PUT') return false;
    return _textOf(response).trim() == '[]';
  }

  /// Un alta con identidad que choca (409, 23505) ya estaba guardada si su
  /// fila existe: el primer envío había llegado.
  ///
  /// El choque no dice con qué fila: con RLS, Postgres no pone los valores de
  /// la llave en el detalle (medido en producción el 2026-11-04, el detalle
  /// llega vacío), y el choque puede ser con otra llave única (el RUT). Por eso
  /// se lee la fila por su identidad, con la misma sesión.
  Future<bool> _alreadyThere(
    UnsavedChange change,
    http.Response response,
    String token,
  ) async {
    final key = change.idempotencyKey;
    final column = change.identityColumn ?? 'id';
    final send = _send;
    if (change.effect != RequestEffect.identifiedInsert ||
        response.statusCode != 409 ||
        key == null ||
        send == null ||
        !_textOf(response).contains('23505')) {
      return false;
    }
    final url = Uri.parse(change.url);
    final lookup = http.Request(
      'GET',
      url.replace(queryParameters: {column: 'eq.$key', 'select': column}),
    )
      ..headers['accept'] = 'application/json'
      ..headers['authorization'] = 'Bearer $token'
      ..headers[replayHeader] = change.id;
    final apiKey = _apiKey;
    if (apiKey != null && apiKey.isNotEmpty) lookup.headers['apikey'] = apiKey;
    for (final entry in change.headers.entries) {
      if (entry.key == 'accept-profile' || entry.key == 'content-profile') {
        lookup.headers['accept-profile'] = entry.value;
      }
    }
    try {
      final found = await http.Response.fromStream(await send(lookup));
      if (found.statusCode < 200 || found.statusCode >= 300) return false;
      final rows = jsonDecode(_textOf(found));
      return rows is List && rows.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// El cuerpo como texto UTF-8 aunque la respuesta no declare su juego de
  /// caracteres (`http` asume Latin-1 y «está» llegaría como «estÃ¡»).
  static String _textOf(http.Response response) =>
      utf8.decode(response.bodyBytes, allowMalformed: true);

  static String _describeResponse(http.Response response) {
    try {
      final json = jsonDecode(_textOf(response));
      if (json is Map) {
        final message = json['message'] ?? json['msg'] ?? json['error'];
        if (message is String && message.trim().isNotEmpty) {
          return 'El servidor lo rechazó: ${message.trim()}';
        }
      }
    } catch (_) {
      // Sin cuerpo legible: basta el código.
    }
    return 'El servidor lo rechazó (código ${response.statusCode}).';
  }
}
