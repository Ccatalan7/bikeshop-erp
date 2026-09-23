import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cliente de Supabase sin sesión para leer el catálogo público.
///
/// La tienda lee `products` como anónimo aunque el cliente haya iniciado
/// sesión. La base le entrega a `anon` sólo las columnas públicas de
/// `products` (sin costo ni proveedor), y a los usuarios con sesión sólo los
/// productos de su propia empresa: una cuenta de cliente no es staff, así
/// que con su sesión no vería el catálogo.
///
/// No tiene autenticación propia: cada pedido sale con la clave pública, y
/// ninguna sesión guardada en el navegador puede entrar en él.
class PublicCatalogClient {
  PublicCatalogClient._();

  static SupabaseClient? _anonymous;

  /// Se llama una vez al arrancar la tienda, con la misma URL y clave con que
  /// se inicializó Supabase.
  static void configure({
    required String url,
    required String anonKey,
    @visibleForTesting http.Client? httpClient,
  }) {
    _anonymous = SupabaseClient(
      url,
      anonKey,
      accessToken: () async => null,
      httpClient: httpClient,
    );
  }

  @visibleForTesting
  static void reset() => _anonymous = null;

  /// El cliente anónimo de la tienda. Donde no se configuró (el ERP, las
  /// pruebas) es el cliente normal: el staff lee su propio catálogo con su
  /// sesión.
  static SupabaseClient get instance => _anonymous ?? Supabase.instance.client;
}
