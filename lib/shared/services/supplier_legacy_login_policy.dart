/// Cuándo un portal puede iniciar sesión solo sobre su transporte legacy.
///
/// **El caso real, medido en el portal.** `portal.rburgos.cl` publica su
/// ingreso **en las dos variantes**: la home enlaza `http://portal.rburgos.cl/
/// login/` y `https://portal.rburgos.cl/login/`, las dos responden 200 sin
/// redirigirse entre sí, y **las dos sirven el mismo formulario**, cuyo `action`
/// es siempre `http://www.rburgos.cl/sitio/aplicaciones/valida_ingreso.asp`.
/// Lo legacy no es la página: es el destino.
///
/// Por eso una declaración que fijara sólo la página HTTP no se disparaba nunca
/// al entrar por el enlace HTTPS —el caso normal—, y una que sólo mirara el
/// esquema de la página se habría disparado en páginas que no son ese
/// formulario.
///
/// **Por qué no se arregla reescribiendo a HTTPS.** Los equivalentes HTTPS de
/// `www.rburgos.cl` para `valida_ingreso.asp` y `seleccion.asp` resetean la
/// conexión: el transporte legacy es real. Se reconoce de forma estrecha, no se
/// niega ni se falsifica.
///
/// **Lo que se ata.** Un conjunto cerrado de **páginas fuente exactas** —URL
/// completa, esquema incluido— y **un destino exacto**. Cada variante que de
/// verdad se usa se declara; ninguna se infiere desde un host, un esquema ni un
/// prefijo. Si la página cargada no es una de las declaradas, o el formulario
/// no envía al destino declarado, no hay excepción: falla cerrado.
///
/// **De dónde sale el permiso.** No existe un autofill HTTP genérico. El par
/// declarado vive en `supplier_portal_probes.session_login_legacy`, que es el
/// dueño del comportamiento del portal; `supplier_credentials` sigue siendo
/// sólo identidad y secreto con su `origin_url` HTTPS. La credencial se
/// resuelve contra ese origen canónico, así que `tenant`, `supplier`, `kind`,
/// `key` y la versión del secreto no cambian: lo único que esta pieza decide es
/// si la página cargada **es** ese formulario y si envía **a ese destino**.
library;

import 'package:flutter/foundation.dart';

/// El transporte legacy declarado de un portal: sus páginas y su destino.
@immutable
class SupplierLegacyLoginTransport {
  const SupplierLegacyLoginTransport({
    required this.canonicalOrigin,
    required this.pageUrls,
    required this.actionUrl,
  });

  /// El origen HTTPS registrado. Es contra éste que se busca la credencial.
  final String canonicalOrigin;

  /// Las páginas exactas donde ese portal muestra su formulario. Pueden ser
  /// HTTPS: lo que necesita excepción es el destino, no la página.
  final List<String> pageUrls;

  /// El `action` HTTP exacto al que ese formulario envía.
  final String actionUrl;

  /// Lee la declaración administrada. **Una declaración a medias no existe.**
  static SupplierLegacyLoginTransport? fromProbe({
    required String? canonicalOrigin,
    required Object? declaration,
  }) {
    if (declaration is! Map) return null;
    final rawPages = declaration['page_urls'];
    if (rawPages is! List || rawPages.isEmpty) return null;
    final pages = <String>[];
    for (final entry in rawPages) {
      final page = entry?.toString().trim() ?? '';
      if (page.isEmpty) return null;
      pages.add(page);
    }
    final action = declaration['action_url']?.toString().trim() ?? '';
    final origin = canonicalOrigin?.trim() ?? '';
    if (action.isEmpty || origin.isEmpty) return null;
    return SupplierLegacyLoginTransport(
      canonicalOrigin: origin,
      pageUrls: List<String>.unmodifiable(pages),
      actionUrl: action,
    );
  }
}

/// El origen canónico con el que resolver la credencial, o `null` si esa página
/// y ese destino no están autorizados.
///
/// Devuelve el **origen HTTPS**, nunca el inseguro: quien llama sigue
/// consultando el mismo registro de siempre.
String? supplierLegacyLoginCanonicalOrigin({
  required String? loadedUrl,
  required String? formAction,
  required SupplierLegacyLoginTransport? transport,
}) {
  if (transport == null) return null;

  final canonical = Uri.tryParse(transport.canonicalOrigin);
  // El binding tiene que ser un ORIGEN HTTPS y nada más: un registro con
  // credencial incrustada, ruta, query o fragmento no habilita nada.
  if (canonical == null || !_isPlainHttpsOrigin(canonical)) return null;

  if (!_matchesDeclaredPage(loadedUrl, transport, canonical)) return null;
  // **El destino también.** Sin esto, autorizar la página dejaría libre a dónde
  // se manda el secreto. Y sigue teniendo que ser el bajón de esquema: un
  // destino HTTPS no necesita excepción y no la recibe por acá.
  if (!_sameExactUrl(formAction, transport.actionUrl, const {'http'})) {
    return null;
  }

  return canonical.origin;
}

/// Si el envío automático está autorizado.
///
/// Es la misma condición que el relleno: el dueño configuró este portal para
/// iniciar sesión solo, y rellenar sin enviar dejaría la sesión a medias.
bool supplierLegacyLoginMaySubmit({
  required String? loadedUrl,
  required String? formAction,
  required SupplierLegacyLoginTransport? transport,
}) =>
    supplierLegacyLoginCanonicalOrigin(
      loadedUrl: loadedUrl,
      formAction: formAction,
      transport: transport,
    ) !=
    null;

/// Si la página cargada es **una de las declaradas**, y esa declaración
/// pertenece al portal del binding.
///
/// El host se exige contra el origen canónico en cada página: la excepción
/// degrada el transporte de un portal registrado, no habilita otro.
bool _matchesDeclaredPage(
  String? loadedUrl,
  SupplierLegacyLoginTransport transport,
  Uri canonical,
) {
  for (final declared in transport.pageUrls) {
    final page = Uri.tryParse(declared.trim());
    if (page == null) continue;
    if (page.host.toLowerCase() != canonical.host.toLowerCase()) continue;
    if (_sameExactUrl(loadedUrl, declared, const {'http', 'https'})) {
      return true;
    }
  }
  return false;
}

/// Igualdad **exacta** de dos URL.
///
/// Compara esquema, host, puerto efectivo y ruta sin normalizar nada: el
/// contrato promete extremos exactos, y `valida_ingreso.asp` no es
/// `valida_ingreso.asp/` —son destinos distintos—.
///
/// **Los dos lados se validan.** Rechazar query, fragmento o credencial
/// incrustada sólo en el candidato dejaba que una declaración torcida perdiera
/// esos componentes al comparar y autorizara de más.
bool _sameExactUrl(String? candidate, String declared, Set<String> schemes) {
  final left = Uri.tryParse(candidate?.trim() ?? '');
  final right = Uri.tryParse(declared.trim());
  if (left == null || right == null) return false;
  if (!_isPlainUrl(left, schemes) || !_isPlainUrl(right, schemes)) return false;

  if (left.scheme != right.scheme) return false;
  if (left.host.toLowerCase() != right.host.toLowerCase()) return false;
  final defaultPort = left.scheme == 'https' ? 443 : 80;
  if ((left.hasPort ? left.port : defaultPort) !=
      (right.hasPort ? right.port : defaultPort)) {
    return false;
  }
  return left.path == right.path;
}

/// Una URL simple del esquema esperado: sin credencial incrustada, sin query y
/// sin fragmento. `file`, `data` o `about` nunca son este transporte.
bool _isPlainUrl(Uri uri, Set<String> schemes) =>
    schemes.contains(uri.scheme) &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    !uri.hasQuery &&
    !uri.hasFragment &&
    uri.path.isNotEmpty;

/// Un origen y nada más: sin credencial, sin ruta, sin query ni fragmento.
///
/// Un `origin_url` con cualquiera de esas partes no es un binding: es otra
/// cosa, y no puede prestar la credencial de un proveedor.
bool _isPlainHttpsOrigin(Uri uri) =>
    uri.scheme == 'https' &&
    uri.host.isNotEmpty &&
    uri.userInfo.isEmpty &&
    (uri.path.isEmpty || uri.path == '/') &&
    !uri.hasQuery &&
    !uri.hasFragment;

/// Busca la declaración administrada de un portal a partir de la página que se
/// cargó.
///
/// Parte del **origen canónico candidato** —`https://` con el mismo host— y
/// sólo devuelve algo si ese origen está registrado como binding de credencial,
/// su sonda declara el transporte legacy **y la página cargada es exactamente
/// una de las declaradas**. Esa última condición es la que impide que una
/// declaración alcance a otra página del mismo portal: el permiso es de una
/// URL, no de un host.
Future<SupplierLegacyLoginTransport?> findSupplierLegacyLoginTransport({
  required String? loadedUrl,
  required Future<Map<String, Object?>?> Function(String canonicalOrigin)
      readDeclaration,
}) async {
  final loaded = Uri.tryParse(loadedUrl?.trim() ?? '');
  if (loaded == null ||
      (loaded.scheme != 'http' && loaded.scheme != 'https') ||
      loaded.host.isEmpty) {
    return null;
  }
  // El candidato canónico nace del host cargado; que exista o no lo decide el
  // registro, nunca esta función.
  final candidate = 'https://${loaded.host.toLowerCase()}';
  final declaration = await readDeclaration(candidate);
  if (declaration == null) return null;
  final transport = SupplierLegacyLoginTransport.fromProbe(
    canonicalOrigin: candidate,
    declaration: declaration,
  );
  if (transport == null) return null;
  return supplierLegacyLoginCanonicalOrigin(
            loadedUrl: loadedUrl,
            formAction: transport.actionUrl,
            transport: transport,
          ) ==
          null
      ? null
      : transport;
}
