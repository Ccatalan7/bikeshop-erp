/// «Te puede faltar» under the cart's lines (2026-10-24): what fits the
/// tyres or the tubes in the cart (`get_public_product_fits_v1`), in the
/// same words in the Flutter cart and the HTML one.
abstract final class CartSuggestionsCopy {
  /// The most the cart offers, after the first three lines' fits.
  static const limit = 4;

  /// How many of the cart's lines are asked what fits them.
  static const askedLines = 3;

  static const eyebrow = 'Te puede faltar';

  /// [kind] is `tubes` (for the cart's tyres) or `tyres` (for its tubes).
  static String title(String kind) => kind == 'tyres'
      ? 'Neumáticos para tu cámara'
      : 'Cámaras que calzan con tu neumático';

  /// Why they fit, and what the buyer still chooses.
  static String note(String kind) => kind == 'tyres'
      ? 'Mismo aro, y su ancho cabe en el rango de tu cámara.'
      : 'Mismo aro y ancho que tu neumático. Elige la válvula de tu llanta: '
            'americana (auto) o francesa (Presta).';

  static const add = 'Agregar';
  static const added = 'Agregado';
}
