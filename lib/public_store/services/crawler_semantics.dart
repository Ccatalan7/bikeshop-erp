import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';

import 'crawler_semantics_stub.dart'
    if (dart.library.js_interop) 'crawler_semantics_web.dart';

/// La tienda se dibuja en un canvas: sin el árbol de accesibilidad, el HTML
/// que renderiza Google no trae ni texto ni `<a href>`. Con la semántica
/// activa, Flutter escribe ese árbol en el DOM y cada destino marcado con
/// `PublicLinkSemantics` sale como un enlace real.
///
/// Se activa sólo para rastreadores: con semántica, el DOM toma los punteros
/// y el scroll de los nodos interactivos, y eso no se le cambia al cliente.
/// El contenido es el mismo que ve cualquier visitante.
final RegExp _crawlerUserAgent = RegExp(
  r'googlebot|google-inspectiontool|storebot-google|googleother|'
  r'adsbot-google|mediapartners-google|apis-google|bingbot|bingpreview|'
  r'duckduckbot|applebot|yandex(bot|images)|baiduspider|slurp|'
  r'facebookexternalhit|twitterbot|linkedinbot|petalbot',
  caseSensitive: false,
);

bool isKnownCrawlerUserAgent(String userAgent) =>
    _crawlerUserAgent.hasMatch(userAgent);

SemanticsHandle? _crawlerSemanticsHandle;

/// Verdadero cuando la tienda se está renderizando para un rastreador.
///
/// Sólo para abrir de entrada lo que un cliente abre con un toque (las
/// secciones plegadas del pie en móvil): nunca para mostrar contenido que
/// el cliente no puede ver.
bool get crawlerSemanticsActive => _crawlerSemanticsHandle != null;

/// Llamar después de `WidgetsFlutterBinding.ensureInitialized()`.
void enableSemanticsForCrawlers() {
  if (!kIsWeb || _crawlerSemanticsHandle != null) return;
  if (!isKnownCrawlerUserAgent(currentUserAgentImpl())) return;
  _crawlerSemanticsHandle = SemanticsBinding.instance.ensureSemantics();
}
