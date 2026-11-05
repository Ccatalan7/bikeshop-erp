import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Un cambio que la persona hizo en un campo y todavía no se guarda: el valor
/// que tenía el campo al abrir ([before]) y el que escribió ([after]).
///
/// Guardar los dos es lo que permite recuperar sin pisar a nadie: si al volver
/// el campo ya no tiene [before], otra persona lo cambió entretanto y el
/// borrador no lo toca.
@immutable
class FormDraftChange {
  const FormDraftChange({required this.before, required this.after});

  final String before;
  final String after;

  Map<String, String> toJson() => {'before': before, 'after': after};

  static FormDraftChange? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final before = raw['before'];
    final after = raw['after'];
    if (before is! String || after is! String) return null;
    return FormDraftChange(before: before, after: after);
  }

  @override
  bool operator ==(Object other) =>
      other is FormDraftChange &&
      other.before == before &&
      other.after == after;

  @override
  int get hashCode => Object.hash(before, after);
}

/// Lo escrito en un formulario que todavía no se guarda.
@immutable
class FormDraft {
  const FormDraft({
    required this.key,
    required this.userId,
    required this.savedAt,
    required this.changes,
  });

  /// El formulario y su registro: `cliente:nuevo`, `cliente:<id>`…
  final String key;
  final String userId;
  final DateTime savedAt;

  /// Por campo (su etiqueta), sólo lo que la persona cambió.
  final Map<String, FormDraftChange> changes;

  Map<String, Object?> toJson() => {
        'key': key,
        'user_id': userId,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'changes': {
          for (final entry in changes.entries) entry.key: entry.value.toJson(),
        },
      };

  static FormDraft? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final key = raw['key'];
    final userId = raw['user_id'];
    final savedAt = DateTime.tryParse('${raw['saved_at'] ?? ''}');
    final rawChanges = raw['changes'];
    if (key is! String || userId is! String || savedAt == null) return null;
    if (rawChanges is! Map) return null;
    final changes = <String, FormDraftChange>{};
    for (final entry in rawChanges.entries) {
      final change = FormDraftChange.fromJson(entry.value);
      if (change != null) changes['${entry.key}'] = change;
    }
    if (changes.isEmpty) return null;
    return FormDraft(
      key: key,
      userId: userId,
      savedAt: savedAt.toLocal(),
      changes: changes,
    );
  }
}

/// Dónde viven los borradores: en el equipo, por persona.
abstract class FormDraftStore {
  Future<FormDraft?> read(String userId, String key);

  /// Los borradores de [userId] cuya llave empieza con [keyPrefix], el más
  /// reciente primero.
  Future<List<FormDraft>> list(String userId, String keyPrefix);
  Future<void> write(FormDraft draft);
  Future<void> remove(String userId, String key);
}

/// Los borradores en las preferencias del equipo (en la web, el
/// almacenamiento del navegador). Un borrador de más de [maxAge] ya no se
/// ofrece: se borra al leerlo.
class SharedPreferencesFormDraftStore implements FormDraftStore {
  SharedPreferencesFormDraftStore({this.maxAge = const Duration(days: 14)});

  static const String _prefix = 'vb_form_draft.';

  final Duration maxAge;
  SharedPreferences? _preferences;

  Future<SharedPreferences> _instance() async =>
      _preferences ??= await SharedPreferences.getInstance();

  static String _id(String userId, String key) => '$_prefix$userId|$key';

  @override
  Future<FormDraft?> read(String userId, String key) async {
    try {
      final preferences = await _instance();
      final raw = preferences.getString(_id(userId, key));
      if (raw == null) return null;
      final draft = FormDraft.fromJson(jsonDecode(raw));
      if (draft == null ||
          draft.userId != userId ||
          DateTime.now().difference(draft.savedAt) > maxAge) {
        await preferences.remove(_id(userId, key));
        return null;
      }
      return draft;
    } catch (error) {
      debugPrint('⚠️ [Borradores] no se pudo leer $key: $error');
      return null;
    }
  }

  @override
  Future<List<FormDraft>> list(String userId, String keyPrefix) async {
    final found = <FormDraft>[];
    try {
      final preferences = await _instance();
      final scope = _id(userId, '');
      for (final stored in preferences.getKeys().toList()) {
        if (!stored.startsWith('$scope$keyPrefix')) continue;
        final draft = await read(userId, stored.substring(scope.length));
        if (draft != null) found.add(draft);
      }
    } catch (error) {
      debugPrint('⚠️ [Borradores] no se pudieron listar $keyPrefix: $error');
    }
    found.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return found;
  }

  @override
  Future<void> write(FormDraft draft) async {
    try {
      final preferences = await _instance();
      await preferences.setString(
        _id(draft.userId, draft.key),
        jsonEncode(draft.toJson()),
      );
    } catch (error) {
      debugPrint('⚠️ [Borradores] no se pudo guardar ${draft.key}: $error');
    }
  }

  @override
  Future<void> remove(String userId, String key) async {
    try {
      final preferences = await _instance();
      await preferences.remove(_id(userId, key));
    } catch (error) {
      debugPrint('⚠️ [Borradores] no se pudo borrar $key: $error');
    }
  }
}

/// La configuración de la app: dónde se guardan y de quién son. Sin persona
/// conectada no se guarda nada.
class FormDrafts {
  FormDrafts._();

  static FormDraftStore store = SharedPreferencesFormDraftStore();
  static String? Function() currentUserId = () => null;

  /// El lugar del borrador de un registro nuevo de [base] («cliente:nuevo»)
  /// mientras su formulario está abierto ([DraftSlots]).
  static Future<String> claimNew(String base) {
    final user = currentUserId();
    return DraftSlots.claim(base, (prefix) async {
      if (user == null || user.isEmpty) return const [];
      final found = await store.list(user, prefix);
      return [for (final draft in found) draft.key];
    });
  }
}

/// Un lugar propio, mientras su formulario está abierto, para el borrador de
/// un registro nuevo que se puede abrir en dos pestañas a la vez.
///
/// **Por qué (2026-11-04).** La identidad de un registro nuevo vive en el
/// equipo con la llave de su borrador (`RecordIdentities`). Con una llave
/// fija por tipo («cliente:nuevo»), dos pestañas con el mismo formulario
/// nuevo compartían borrador e identidad: si el «Guardar» de la primera había
/// llegado sin respuesta, el de la segunda la actualizaba con otro registro.
/// Cada formulario toma el borrador más reciente que ninguno tiene abierto
/// (quedó de una pestaña que se cerró sin guardar) o uno nuevo, `base#<uuid>`,
/// y lo suelta al cerrar.
class DraftSlots {
  DraftSlots._();

  static final Set<String> _open = {};

  /// [stored] da las llaves guardadas que empiezan con el prefijo, la más
  /// reciente primero.
  static Future<String> claim(
    String base,
    Future<List<String>> Function(String prefix) stored,
  ) async {
    final prefix = '$base#';
    var keys = const <String>[];
    try {
      keys = await stored(prefix);
    } catch (error) {
      debugPrint('⚠️ [Borradores] no se pudieron listar $base: $error');
    }
    // Entre mirar y tomar no hay esperas: dos formularios que se abren a la
    // vez no toman el mismo borrador.
    for (final key in keys) {
      if (_open.add(key)) return key;
    }
    final fresh = '$prefix${const Uuid().v4()}';
    _open.add(fresh);
    return fresh;
  }

  /// El formulario de [key] se cerró: otro puede tomar su borrador.
  static void release(String key) => _open.remove(key);

  @visibleForTesting
  static void resetForTest() => _open.clear();
}
