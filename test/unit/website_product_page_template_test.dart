import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_public_core/modules/website/models/website_product_page_template.dart';

void main() {
  group('the product page template', () {
    test('without a saved one, every product page is drawn as before', () {
      for (final raw in [null, '', 'not json', '[]']) {
        final template = WebsiteProductPageTemplate.decode(raw);
        expect(template, const WebsiteProductPageTemplate(), reason: '$raw');
      }
      const template = WebsiteProductPageTemplate();
      expect(template.taxNote, 'Precio final con IVA incluido');
      expect(template.resolvedAddToCartLabel, 'Agregar al carrito');
      expect(template.resolvedBuyNowLabel, 'Comprar ahora');
      expect(template.resolvedRelatedTitle, 'Productos relacionados');
      expect(template.resolvedSheetTitle(technical: true), 'Ficha técnica');
      expect(
        template.resolvedSheetTitle(technical: false),
        'Detalles del producto',
      );
      expect(
        template.resolvedHelpTitle(technical: true),
        '¿Le sirve a tu bicicleta?',
      );
      expect(template.resolvedHelpTitle(technical: false), '¿Tienes una duda?');
      expect(template.photoSide, WebsiteProductPhotoSide.left);
      // What goes with a tyre or a tube shows by default (2026-10-23), so a
      // site saved before it, or by an older ERP, still offers it.
      expect(template.showFits, isTrue);
      expect(template.resolvedFitsTitle('tubes'), 'Cámaras que calzan');
      expect(
        template.resolvedFitsTitle('tyres'),
        'Neumáticos para esta cámara',
      );
      expect(
        WebsiteProductPageTemplate.fromJson(const {'version': 1}).showFits,
        isTrue,
      );
    });

    test('round-trips every choice and says what a blank means', () {
      const custom = WebsiteProductPageTemplate(
        photoSide: WebsiteProductPhotoSide.right,
        taxNote: '',
        showHighlights: false,
        addToCartLabel: 'Lo quiero',
        showBuyNow: false,
        buyNowLabel: 'Ya',
        showPromises: false,
        sheetTitle: 'Especificaciones',
        showOriginNote: false,
        showHelp: false,
        helpTitle: '¿Dudas?',
        helpText: 'Escríbenos.',
        showRelated: false,
        relatedTitle: 'Te puede servir',
        showFits: false,
        fitsTitle: 'Para tu rueda',
      );
      final decoded = WebsiteProductPageTemplate.decode(custom.encode());
      expect(decoded, custom);
      // An explicit empty note hides it; a missing one is the default.
      expect(decoded.taxNote, isEmpty);
      expect(
        WebsiteProductPageTemplate.fromJson(const {'version': 1}).taxNote,
        WebsiteProductPageTemplate.defaultTaxNote,
      );
      // A blank title or label is the page's own words, by the product.
      final blank = custom.copyWith(
        sheetTitle: '  ',
        addToCartLabel: '',
        relatedTitle: '',
      );
      expect(
          blank.resolvedSheetTitle(technical: false), 'Detalles del producto');
      expect(blank.resolvedAddToCartLabel, 'Agregar al carrito');
      expect(blank.resolvedRelatedTitle, 'Productos relacionados');
      expect(custom.resolvedHelpTitle(technical: true), '¿Dudas?');
    });
  });
}
