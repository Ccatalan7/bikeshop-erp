import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/config/bottom_bracket_canonical_data.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';

void main() {
  group('bottom bracket canonical data', () {
    test('canonicalizes threaded aliases into the shared family key', () {
      expect(canonicalBottomBracketFamilyValue('threaded_bsa'), 'bsa_threaded');
      expect(canonicalBottomBracketFamilyValue('BSA Threaded'), 'bsa_threaded');
    });

    test('only pressfit-style families require shell diameter truth', () {
      expect(bottomBracketFamilyUsesShellDiameter('pressfit'), isTrue);
      expect(bottomBracketFamilyUsesShellDiameter('bb30_pf30'), isTrue);
      expect(bottomBracketFamilyUsesShellDiameter('bsa_threaded'), isFalse);
    });

    test('narrows BMX mid spindle choices to BMX-specific interfaces', () {
      final options = bottomBracketSpindleInterfaceOptionsForFamily('mid');

      expect(
        options.keys,
        containsAll(const ['bmx_19', 'bmx_22', 'bmx_24', 'unknown']),
      );
      expect(options.keys, isNot(contains('hollowtech_24')));
      expect(options.keys, isNot(contains('square_jis')));
    });
  });

  group('BikeProfileSummaryBuilder bottom bracket highlights', () {
    final bike = Bike(
      tenantId: 'tenant',
      customerId: 'customer',
      brand: 'Test',
      model: 'Fixture',
      bikeType: BikeType.mountainHardtail,
    );

    test('includes pressfit shell width, bore, and spindle interface', () {
      final highlights = BikeProfileSummaryBuilder.buildTechnicalHighlights(
        bike: bike,
        technicalValues: const <String, dynamic>{
          'bottomBracketFamily': 'pressfit',
          'bbShellWidthMm': 92,
          'bbShellDiameterMm': 41,
          'spindleInterface': 'sram_dub',
        },
      );

      expect(
        highlights,
        contains('Pedalier: Pressfit · ancho 92 mm · diam. 41 mm · SRAM DUB'),
      );
    });

    test('keeps threaded highlights free of shell diameter noise', () {
      final highlights = BikeProfileSummaryBuilder.buildTechnicalHighlights(
        bike: bike,
        technicalValues: const <String, dynamic>{
          'bottomBracketFamily': 'bsa_threaded',
          'bbShellWidthMm': 73,
          'spindleInterface': 'hollowtech_24',
        },
      );

      final highlight = highlights.firstWhere(
        (entry) => entry.startsWith('Pedalier:'),
      );

      expect(highlight,
          'Pedalier: BSA roscado · ancho 73 mm · Hollowtech / 24 mm');
      expect(highlight, isNot(contains('diam.')));
    });
  });
}
