/// The ONE named owner of Viñabike's canonical tenant identity in the
/// storefront. Consumers must use this owner — never repeat the UUID —
/// so brand-bound behavior (e.g. the bundled logo asset) can only ever
/// attach to this tenant. `TenantDetectionService._knownDomainTenants`
/// still spells the id per domain; converging it here is a separate task.
///
/// Dart puro, como [storefrontFirstLogoSource]: los lee también el generador
/// de snapshots, que no puede importar Flutter.
class VinabikeCanonicalTenant {
  const VinabikeCanonicalTenant._();

  static const String id = '5443b130-cc28-45af-a420-cd500b288890';

  static bool owns(String? tenantId) => tenantId?.trim() == id;
}

/// Asset del logo empaquetado; en la web se sirve bajo `assets/`.
///
/// WebP sin pérdida de 1000 × 268 (15 KB). El PNG original medía 3300 × 887 y
/// pesaba 104 KB para dibujarse a lo sumo a 60 px de alto (pie de página);
/// desde la página instantánea el logo baja en los primeros segundos, junto
/// con el motor y el programa de la tienda, y ese peso se notaba.
const String storefrontBundledLogoAsset = 'assets/images/vinabike_logo.webp';

/// El logo que la tienda pública dibuja primero, en el orden de
/// `StorefrontLogoResolution` fuera del editor: `logo_url` del sitio, el logo
/// del tenant y, sólo para la tienda canónica, el empaquetado (como ruta web,
/// `assets/…`). Vacío: la tienda escribe su nombre.
String storefrontFirstLogoSource({
  required String configuredUrl,
  String? tenantLogoUrl,
  String? tenantId,
}) {
  for (final candidate in [configuredUrl, tenantLogoUrl ?? '']) {
    if (candidate.trim().isNotEmpty) return candidate.trim();
  }
  return VinabikeCanonicalTenant.owns(tenantId)
      ? 'assets/$storefrontBundledLogoAsset'
      : '';
}
