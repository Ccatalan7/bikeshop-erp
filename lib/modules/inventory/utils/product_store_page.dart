import 'package:vinabike_public_core/modules/website/models/website_seo_settings_aliases.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';

/// La página de un producto en la tienda pública, con la dirección exacta que
/// arma la tienda.
///
/// El nombre web manda sobre el comercial, igual que en `Product.fromJson` del
/// catálogo público, y el SKU es la llave estable (sin SKU, el UUID). Con el
/// nombre comercial también se llega, pero por un 301: medido el 2026-11-02
/// con la cadena KMC HV408 gris y café (SKU 4715575883212), cuyo nombre
/// comercial es «Cadena 1/2 X 3/32 Kmc Hv408 Caja Grey/brown».
///
/// El origen es `store_url` de la configuración del sitio, su único dueño. Sin
/// una dirección https válida, o sin producto guardado, no hay enlace.
Uri? productStorePageUri({
  required String storeUrl,
  required String? productId,
  required String name,
  String? websiteName,
  required String sku,
}) {
  final origin = WebsiteSeoSettingsAliases.normalizeHttpsOrigin(storeUrl);
  final id = productId?.trim() ?? '';
  if (origin.isEmpty || id.isEmpty) return null;
  final webName = websiteName?.trim() ?? '';
  final path = buildPublicProductPath(
    name: webName.isNotEmpty ? webName : name,
    sku: sku,
    fallbackProductId: id,
  );
  return Uri.parse('$origin$path');
}
