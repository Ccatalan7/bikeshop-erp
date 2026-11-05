import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../form_drafts/form_draft_store.dart';

/// Qué operaciones puede reenviar sola la bandeja de cambios sin guardar.
///
/// **Por qué (2026-11-04).** Una llave de operación evita el doble sólo si el
/// segundo intento lleva la misma llave. Muchas pantallas sacan una llave nueva
/// en cada intento (`'p_operation_key': const Uuid().v4()`), y la primera
/// versión de la bandeja reenviaba sola, al volver la conexión, todo comando
/// con llave. Si la persona lo repetía a mano, el reenvío más su repetición
/// quedaban dos veces: agregar a la lista de compras o cambiar el estado de un
/// trabajo, por ejemplo. Se encontró revisándolo, antes de publicarlo.
///
/// Por eso la bandeja reenvía sola sólo la llave que su dueño **sostiene**.
/// Mientras la sostiene, todo intento de esa operación sale con esa misma
/// llave. La sostienen:
/// - la caja, con una llave por carro hasta que la venta se confirma;
/// - el cobro rápido y el formulario de pago, mientras están abiertos;
/// - un registro nuevo con borrador ([RecordIdentities]): su identidad vive
///   con el borrador, aunque se cierre el formulario o la app.
///
/// Lo demás espera a la persona en «Revisar». Reenviarlo desde ahí sigue sin
/// duplicarlo si ya había llegado; lo que sólo ella sabe es si lo volvió a
/// hacer.
class StableOperationKeys {
  StableOperationKeys._();

  static final Set<String> _held = {};

  /// [key] sale igual en cada intento de su operación mientras se sostiene.
  static void hold(String? key) {
    final clean = key?.trim();
    if (clean != null && clean.isNotEmpty) _held.add(clean);
  }

  /// Su dueño ya no la usa: el próximo intento puede llevar otra.
  static void release(String? key) {
    final clean = key?.trim();
    if (clean != null) _held.remove(clean);
  }

  static bool holds(String? key) {
    final clean = key?.trim();
    if (clean == null || clean.isEmpty) return false;
    return _held.contains(clean) || RecordIdentities.isHeld(clean);
  }

  @visibleForTesting
  static void resetForTest() => _held.clear();
}

/// La identidad de un registro nuevo mientras su formulario está abierto,
/// para los formularios sin borrador (la venta manual).
///
/// Sin borrador, un formulario nuevo vacío es otra intención: la identidad no
/// puede sobrevivirle, porque un intento viejo que sí llegó quedaría pisado por
/// la venta siguiente. Vive mientras el formulario está abierto, y por eso la
/// bandeja la reenvía sola sólo en ese tiempo.
class HeldRecordIdentity {
  String? _id;

  /// La identidad para este intento: la misma hasta [renew].
  String take() {
    final id = _id ??= const Uuid().v4();
    StableOperationKeys.hold(id);
    return id;
  }

  /// El registro quedó guardado (o el formulario se cerró): el próximo es
  /// otro.
  void renew() {
    StableOperationKeys.release(_id);
    _id = null;
  }
}

/// La identidad (`id`) de un registro nuevo mientras se crea.
///
/// Un cliente nuevo o una venta manual llevan su `id` desde el equipo. Si el
/// primer envío llegó pero la respuesta se perdió, el segundo choca con su
/// propia llave primaria y el servidor no crea otro. Para eso todos los
/// intentos tienen que llevar el mismo `id`: el de cada «Guardar», el de la
/// bandeja y el de después de cerrar la app. Por eso la identidad se guarda en
/// el equipo con la llave del borrador del formulario («cliente:nuevo») y se
/// suelta cuando el registro queda guardado, cuando se descarta el borrador o
/// cuando la persona deshace el borrador recuperado ([FormDraftScope]).
class RecordIdentities {
  RecordIdentities._();

  static const String _prefix = 'vb_record_identity.';
  static const Duration maxAge = Duration(days: 14);

  static final Map<String, _HeldIdentity> _byKey = {};
  static Future<void>? _loading;
  static SharedPreferences? _preferences;

  /// En las pruebas no hay SharedPreferences de verdad.
  @visibleForTesting
  static bool persist = true;

  static String _scoped(String draftKey) =>
      '${FormDrafts.currentUserId() ?? '-'}|$draftKey';

  /// Lee las identidades guardadas en el equipo (una vez).
  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    if (!persist) return;
    try {
      final preferences =
          _preferences ??= await SharedPreferences.getInstance();
      final now = DateTime.now();
      for (final key in preferences.getKeys()) {
        if (!key.startsWith(_prefix)) continue;
        final scoped = key.substring(_prefix.length);
        final held = _HeldIdentity.tryParse(preferences.getString(key));
        if (held == null || now.difference(held.createdAt) > maxAge) {
          unawaited(preferences.remove(key));
          continue;
        }
        _byKey.putIfAbsent(scoped, () => held);
      }
    } catch (error) {
      debugPrint('⚠️ [Identidad] no se pudo leer del equipo: $error');
    }
  }

  /// La identidad del registro que nace en el borrador [draftKey]: la misma
  /// hasta que se suelte.
  static Future<String> of(String draftKey) async {
    await load();
    final scoped = _scoped(draftKey);
    final existing = _byKey[scoped];
    if (existing != null) return existing.id;
    final held = _HeldIdentity(const Uuid().v4(), DateTime.now());
    _byKey[scoped] = held;
    await _write(scoped, held);
    return held.id;
  }

  /// La identidad de [draftKey] si ya nació, sin crearla.
  static String? peek(String draftKey) => _byKey[_scoped(draftKey)]?.id;

  /// El registro quedó guardado o se descartó: el próximo es otro.
  static Future<void> release(String draftKey) async {
    await load();
    final scoped = _scoped(draftKey);
    if (_byKey.remove(scoped) == null) return;
    if (!persist) return;
    try {
      final preferences =
          _preferences ??= await SharedPreferences.getInstance();
      await preferences.remove('$_prefix$scoped');
    } catch (error) {
      debugPrint('⚠️ [Identidad] no se pudo soltar: $error');
    }
  }

  static bool isHeld(String id) => _byKey.values.any((held) => held.id == id);

  static Future<void> _write(String scoped, _HeldIdentity held) async {
    if (!persist) return;
    try {
      final preferences =
          _preferences ??= await SharedPreferences.getInstance();
      await preferences.setString('$_prefix$scoped', held.encode());
    } catch (error) {
      debugPrint('⚠️ [Identidad] no se pudo guardar: $error');
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _byKey.clear();
    _loading = null;
    _preferences = null;
  }
}

@immutable
class _HeldIdentity {
  const _HeldIdentity(this.id, this.createdAt);

  final String id;
  final DateTime createdAt;

  String encode() => jsonEncode({
        'id': id,
        'created_at': createdAt.toUtc().toIso8601String(),
      });

  static _HeldIdentity? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final id = json['id'];
      final created = DateTime.tryParse('${json['created_at'] ?? ''}');
      if (id is! String || id.isEmpty || created == null) return null;
      return _HeldIdentity(id, created.toLocal());
    } catch (_) {
      return null;
    }
  }
}
