import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/models/public_commerce_product_projection.dart';

/// Product names are authored in the ERP, where a line break, a tab or a double
/// space is invisible. On the storefront they are not — an embedded newline
/// splits an H1 mid-phrase, which is exactly how
/// "CADENA 1/2 X 3/32 116 E 8 VEL. Z8.3 DISPLAY\nKMC  C/U" reached the live
/// product page.
void main() {
  group('storefrontDisplayText', () {
    test('collapses the whitespace an operator never meant to publish', () {
      expect(
        storefrontDisplayText('CADENA Z8.3 DISPLAY\nKMC  C/U'),
        'CADENA Z8.3 DISPLAY KMC C/U',
      );
      expect(storefrontDisplayText('  espacios \t raros \r\n aquí  '),
          'espacios raros aquí');
    });

    test('leaves clean text untouched', () {
      expect(storefrontDisplayText('Cadena KMC Z8.3'), 'Cadena KMC Z8.3');
    });
  });

  group('storefrontDisplayTitle', () {
    test('drops the ERP unit-of-measure marker', () {
      expect(
        storefrontDisplayTitle('CADENA 1/2 X 3/32 116 E 8 VEL. Z8.3 DISPLAY\n'
            'KMC  C/U'),
        'CADENA 1/2 X 3/32 116 E 8 VEL. Z8.3 DISPLAY KMC',
      );
    });

    test('tolerates the spacing and punctuation variants in the catalog', () {
      for (final raw in <String>[
        'PASTILLA FRENO c/u',
        'PASTILLA FRENO C/U.',
        'PASTILLA FRENO  C / U',
        'PASTILLA FRENO - C/U',
      ]) {
        expect(storefrontDisplayTitle(raw), 'PASTILLA FRENO', reason: raw);
      }
    });

    test('keeps trailing words that are real product information', () {
      // A bike part sold as a pair or a kit says so in its name; stripping that
      // would remove meaning, not noise.
      expect(storefrontDisplayTitle('PASTILLAS DE FRENO PAR'),
          'PASTILLAS DE FRENO PAR');
      expect(storefrontDisplayTitle('MAZAS SHIMANO SET'), 'MAZAS SHIMANO SET');
      expect(storefrontDisplayTitle('CABLE 2 MT'), 'CABLE 2 MT');
    });

    test('only strips the marker at the end, never mid-name', () {
      expect(
        storefrontDisplayTitle('SOPORTE C/U REFORZADO'),
        'SOPORTE C/U REFORZADO',
      );
    });

    test('never empties a title that had content', () {
      expect(storefrontDisplayTitle('C/U'), 'C/U');
    });

    test('an empty name stays empty so eligibility still flags it', () {
      // PublicCommerceProductProjection reports missingTitle from this.
      expect(storefrontDisplayTitle('   \n  '), '');
    });
  });
}
