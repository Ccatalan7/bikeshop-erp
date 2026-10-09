/// The public paths Firebase Hosting hands to the HTML storefront: the
/// `run` rewrites of the store target in `firebase.json`, in the same
/// spelling (a test keeps the two equal). Flutter only redeems the editor's
/// own return from Google (and draws the editor's pages with a block the
/// HTML does not draw yet); from them it leaves for these paths with a full
/// page load, so every visitor reads the same pages.
const storefrontHtmlRouteSources = <String>[
  '/',
  '/productos',
  '/productos/**',
  '/producto/**',
  '/servicios',
  '/servicios/**',
  '/nosotros',
  '/envios',
  '/devoluciones',
  '/terminos',
  '/privacidad',
  '/contacto',
  // The editor's own pages (phase 5a); one with a block the HTML does not
  // draw yet is answered with Flutter.
  '/pagina/**',
  '/guias',
  '/guias/**',
  '/carrito',
  '/carrito/**',
  '/checkout',
  '/checkout/**',
  '/pedido/**',
  // The customer portal's reading pages (phase 4a) and what they ask for.
  '/cuenta',
  '/cuenta/pedidos',
  '/cuenta/servicios',
  '/cuenta/bicicletas',
  '/cuenta/vista',
  '/cuenta/archivo',
  // The profile and the addresses (phase 4b) and where they save.
  '/cuenta/perfil',
  '/cuenta/direcciones',
  '/cuenta/accion',
  // The way in (phase 4c); only the editor's own Google return gets Flutter.
  '/cuenta/login',
  // The team's Android download and the release it reads (2026-10-08).
  '/cuenta/descargas/android',
  '/cuenta/descargas/android/version',
  // «Soporte» and each conversation (phase 4h).
  '/cuenta/chats',
  '/cuenta/chats/**',
  // Where the store lived inside the ERP's web app: a permanent redirect to
  // the same page without the prefix (2026-10-08). Flutter never leaves for
  // them; under `/tienda` its own routes answer.
  '/tienda',
  '/tienda/**',
];

/// Whether the HTML storefront answers [path] (no query, no fragment), as
/// Firebase Hosting matches [storefrontHtmlRouteSources]: an exact source,
/// or anything under a `/**` one.
bool storefrontHtmlServes(String path) {
  final clean = path.isEmpty ? '/' : path;
  for (final source in storefrontHtmlRouteSources) {
    if (source.endsWith('/**')) {
      final prefix = source.substring(0, source.length - 2);
      if (clean.startsWith(prefix) && clean.length > prefix.length) {
        return true;
      }
    } else if (clean == source) {
      return true;
    }
  }
  return false;
}
