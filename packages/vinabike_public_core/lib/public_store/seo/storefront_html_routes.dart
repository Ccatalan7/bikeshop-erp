/// The public paths Firebase Hosting hands to the HTML storefront: the
/// `run` rewrites of the store target in `firebase.json`, in the same
/// spelling (a test keeps the two equal). Flutter still draws the way in
/// and the chats; from them it leaves for these paths with a full page
/// load, so every visitor reads the same pages.
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
