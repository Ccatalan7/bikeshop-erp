import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// La referencia de la fila/backup permanece estable. Sólo su presentación
/// obtiene una URL temporal; un fallo privado nunca vuelve a la URL pública.
class WorkshopAssetService {
  WorkshopAssetService(this._client);

  final SupabaseClient _client;
  static const privateBucket = 'workshop-legacy-private';

  static bool needsResolution(String reference) {
    final uri = Uri.tryParse(reference);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.path.startsWith(
          '/storage/v1/object/public/vinabike-assets/mechanic_jobs/',
        );
  }

  Future<String> resolve(String reference) async {
    if (!needsResolution(reference)) return reference;
    final actor = _client.auth.currentUser?.id;
    final expectedPrefix =
        _client.storage.from('vinabike-assets').getPublicUrl('mechanic_jobs/');
    if (actor == null || !reference.startsWith(expectedPrefix)) {
      throw const WorkshopAssetUnavailable();
    }
    try {
      final raw = await _client.rpc('workshop_legacy_asset_read_v1', params: {
        'p_reference': reference,
      });
      _checkActor(actor);
      if (raw is! Map) throw const WorkshopAssetUnavailable();
      if (raw['mode'] == 'legacy' && raw['url'] == reference) return reference;
      if (raw['mode'] != 'private' || raw['bucket'] != privateBucket) {
        throw const WorkshopAssetUnavailable();
      }
      final path = raw['path'];
      if (path is! String || path.split('/').length != 4) {
        throw const WorkshopAssetUnavailable();
      }
      final url =
          await _client.storage.from(privateBucket).createSignedUrl(path, 300);
      _checkActor(actor);
      return url;
    } catch (_) {
      // No SDK/server payload ni URL privada en el texto del operador.
      throw const WorkshopAssetUnavailable();
    }
  }

  /// Para un PDF: los bytes autorizados quedan dentro del documento. No se
  /// incrusta una URL que expire ni se vuelve al origen si la copia falla.
  Future<Uint8List> download(String reference) async {
    final actor = _client.auth.currentUser?.id;
    if (actor == null) throw const WorkshopAssetUnavailable();
    try {
      final url = await resolve(reference);
      _checkActor(actor);
      final response = await http.get(Uri.parse(url));
      _checkActor(actor);
      if (response.statusCode != 200 ||
          response.bodyBytes.isEmpty ||
          response.bodyBytes.length > 20971520) {
        throw const WorkshopAssetUnavailable();
      }
      return response.bodyBytes;
    } catch (_) {
      throw const WorkshopAssetUnavailable();
    }
  }

  void _checkActor(String actor) {
    if (_client.auth.currentUser?.id != actor) {
      throw const WorkshopAssetUnavailable();
    }
  }
}

class WorkshopAssetUnavailable implements Exception {
  const WorkshopAssetUnavailable();

  @override
  String toString() =>
      'No se pudo abrir el archivo del trabajo. Revisa tu conexión o pide al taller que lo revise.';
}
