import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'form_draft_store.dart';

/// Un documento a medio armar, guardado en el equipo: una venta manual con
/// sus líneas, su cliente y su referencia.
///
/// **Por qué existe (2026-11-04).** El borrador por campos (`FormDraftScope`)
/// reconoce cada campo por su etiqueta, y las líneas de un documento repiten
/// etiquetas («Precio», «Cant.»): no se pueden recuperar así sin arriesgar que
/// un precio caiga en otra línea. Lo que se escribe a mano en una venta son
/// justamente las líneas. Este borrador guarda **el documento entero** como lo
/// arma su propio formulario y lo devuelve por el mismo camino con que el
/// formulario abre una venta guardada.
@immutable
class DocumentDraft {
  const DocumentDraft({
    required this.key,
    required this.userId,
    required this.savedAt,
    required this.data,
  });

  final String key;
  final String userId;
  final DateTime savedAt;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
        'key': key,
        'user_id': userId,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'data': data,
      };

  static DocumentDraft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final userId = raw['user_id'];
    final savedAt = DateTime.tryParse('${raw['saved_at'] ?? ''}');
    final data = raw['data'];
    if (key is! String || userId is! String || savedAt == null) return null;
    if (data is! Map) return null;
    return DocumentDraft(
      key: key,
      userId: userId,
      savedAt: savedAt.toLocal(),
      data: Map<String, Object?>.from(data),
    );
  }
}

abstract class DocumentDraftStore {
  Future<DocumentDraft?> read(String userId, String key);

  /// Los borradores de [userId] cuya llave empieza con [keyPrefix], el más
  /// reciente primero.
  Future<List<DocumentDraft>> list(String userId, String keyPrefix);
  Future<void> write(DocumentDraft draft);
  Future<void> remove(String userId, String key);
}

class SharedPreferencesDocumentDraftStore implements DocumentDraftStore {
  SharedPreferencesDocumentDraftStore({this.maxAge = const Duration(days: 14)});

  static const String _prefix = 'vb_document_draft.';
  final Duration maxAge;
  SharedPreferences? _preferences;

  Future<SharedPreferences> _instance() async =>
      _preferences ??= await SharedPreferences.getInstance();

  String _key(String userId, String key) => '$_prefix$userId|$key';

  @override
  Future<DocumentDraft?> read(String userId, String key) async {
    final preferences = await _instance();
    final raw = preferences.getString(_key(userId, key));
    if (raw == null) return null;
    DocumentDraft? draft;
    try {
      draft = DocumentDraft.fromJson(jsonDecode(raw));
    } catch (_) {
      draft = null;
    }
    if (draft == null || DateTime.now().difference(draft.savedAt) > maxAge) {
      await preferences.remove(_key(userId, key));
      return null;
    }
    return draft;
  }

  @override
  Future<List<DocumentDraft>> list(String userId, String keyPrefix) async {
    final preferences = await _instance();
    final scope = '$_prefix$userId|';
    final found = <DocumentDraft>[];
    for (final stored in preferences.getKeys().toList()) {
      if (!stored.startsWith('$scope$keyPrefix')) continue;
      final draft = await read(userId, stored.substring(scope.length));
      if (draft != null) found.add(draft);
    }
    found.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return found;
  }

  @override
  Future<void> write(DocumentDraft draft) async {
    final preferences = await _instance();
    await preferences.setString(
      _key(draft.userId, draft.key),
      jsonEncode(draft.toJson()),
    );
  }

  @override
  Future<void> remove(String userId, String key) async {
    final preferences = await _instance();
    await preferences.remove(_key(userId, key));
  }
}

/// Dónde viven los borradores de documentos. Las pruebas lo reemplazan.
class DocumentDrafts {
  DocumentDrafts._();

  static DocumentDraftStore store = SharedPreferencesDocumentDraftStore();

  /// El lugar de un documento nuevo de [base] («venta:nueva») mientras su
  /// formulario está abierto ([DraftSlots]): el borrador más reciente que
  /// ningún formulario abierto tiene o uno nuevo, `base#<uuid>`.
  ///
  /// **Por qué (2026-11-04).** El ERP abre varias pestañas. Con un solo
  /// borrador por tipo, dos ventas nuevas a la vez se pisaban el borrador y
  /// compartían su identidad (`RecordIdentities` va con la llave del
  /// borrador): el «Guardar» de una podía actualizar la otra.
  static Future<String> claim(String base, {String? userId}) {
    final user = userId ?? FormDrafts.currentUserId();
    return DraftSlots.claim(base, (prefix) async {
      if (user == null || user.isEmpty) return const [];
      final found = await store.list(user, prefix);
      return [for (final draft in found) draft.key];
    });
  }

  /// El formulario de [key] se cerró: otro puede tomar su borrador.
  static void release(String key) => DraftSlots.release(key);
}

/// Guarda en el equipo, mientras se arma, la foto de un documento.
///
/// Cada [every] y cuando la app se va al fondo pide [capture]: si devuelve
/// algo distinto de lo último guardado, lo escribe; si devuelve `null` (ya no
/// queda nada que valga guardar), lo borra. [stop] escribe una última vez:
/// hay que llamarlo en el `dispose` **antes** de soltar los controladores que
/// [capture] lee. [clear] lo borra y deja de seguirlo (se guardó de verdad).
class DocumentDraftKeeper {
  DocumentDraftKeeper({
    required this.draftKey,
    required this.capture,
    this.every = const Duration(seconds: 2),
    DocumentDraftStore? store,
    String? Function()? currentUserId,
  })  : _store = store,
        _currentUserId = currentUserId;

  final String draftKey;
  final Map<String, Object?>? Function() capture;
  final Duration every;
  final DocumentDraftStore? _store;
  final String? Function()? _currentUserId;

  Timer? _timer;
  AppLifecycleListener? _lifecycle;
  String? _lastWritten;
  bool _wroteSomething = false;
  bool _active = false;

  DocumentDraftStore get _drafts => _store ?? DocumentDrafts.store;
  String? get _user => (_currentUserId ?? FormDrafts.currentUserId)();

  bool get isActive => _active;

  /// El borrador que quedó de antes, si hay.
  Future<DocumentDraft?> read() async {
    final user = _user;
    if (user == null || user.isEmpty) return null;
    try {
      final draft = await _drafts.read(user, draftKey);
      if (draft != null) {
        // Lo que ya está en el equipo cuenta como escrito: si la persona lo
        // vacía, se borra en vez de quedar para la próxima vez.
        _wroteSomething = true;
        _lastWritten = jsonEncode(draft.data);
      }
      return draft;
    } catch (error) {
      debugPrint('⚠️ [Borrador] no se pudo leer $draftKey: $error');
      return null;
    }
  }

  /// Empieza a seguir el documento.
  void start() {
    if (_active) return;
    _active = true;
    _timer = Timer.periodic(every, (_) => _tick());
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) _tick();
      },
    );
  }

  /// Escribe ahora si cambió.
  Future<void> flush() async {
    if (!_active) return;
    Map<String, Object?>? data;
    try {
      data = capture();
    } catch (error) {
      debugPrint('⚠️ [Borrador] no se pudo leer el documento: $error');
      return;
    }
    await _save(data);
  }

  void _tick() => unawaited(flush());

  Future<void> _save(Map<String, Object?>? data) async {
    final user = _user;
    if (user == null || user.isEmpty) return;
    try {
      if (data == null) {
        if (!_wroteSomething && _lastWritten == null) return;
        _lastWritten = null;
        _wroteSomething = false;
        await _drafts.remove(user, draftKey);
        return;
      }
      final encoded = jsonEncode(data);
      if (encoded == _lastWritten) return;
      _lastWritten = encoded;
      _wroteSomething = true;
      await _drafts.write(DocumentDraft(
        key: draftKey,
        userId: user,
        savedAt: DateTime.now(),
        data: data,
      ));
    } catch (error) {
      debugPrint('⚠️ [Borrador] no se pudo guardar $draftKey: $error');
    }
  }

  /// Deja de seguirlo, después de guardar una última vez lo que haya.
  void stop() {
    if (!_active) return;
    Map<String, Object?>? data;
    try {
      data = capture();
    } catch (_) {
      data = null;
    }
    _halt();
    unawaited(_save(data));
  }

  /// El documento se guardó de verdad (o la persona lo descartó): se borra y
  /// se deja de seguir.
  Future<void> clear() async {
    _halt();
    _lastWritten = null;
    _wroteSomething = false;
    final user = _user;
    if (user == null || user.isEmpty) return;
    try {
      await _drafts.remove(user, draftKey);
    } catch (error) {
      debugPrint('⚠️ [Borrador] no se pudo borrar $draftKey: $error');
    }
  }

  void _halt() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}
