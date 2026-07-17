import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/bike_finder_search.dart';

void main() {
  const oxfordFelipe = [
    BikeFinderSearchField('Oxford South Mountain Soul', weight: 125),
    BikeFinderSearchField('Felipe Lizama', weight: 120),
    BikeFinderSearchField('+56 9 3391 5497', weight: 128),
    BikeFinderSearchField('OX-SOUTH-2024', weight: 135),
  ];

  test('combines bicycle, customer, and telephone tokens', () {
    expect(
      bikeFinderRelationalSearchScore(
        query: 'oxford felipe',
        fields: oxfordFelipe,
      ),
      greaterThan(0),
    );
    expect(
      bikeFinderRelationalSearchScore(
        query: 'oxford felipe 5497',
        fields: oxfordFelipe,
      ),
      greaterThan(0),
    );
    expect(
      bikeFinderRelationalSearchScore(
        query: 'oxford luciano',
        fields: oxfordFelipe,
      ),
      0,
    );
  });

  test('tolerates one small spelling mistake without broadening numbers', () {
    const voltta = [
      BikeFinderSearchField('Voltta Prato', weight: 125),
      BikeFinderSearchField('Axel Peters', weight: 120),
      BikeFinderSearchField('+569 94845974', weight: 128),
    ];

    expect(
      bikeFinderRelationalSearchScore(query: 'volta', fields: voltta),
      greaterThan(0),
    );
    expect(
      bikeFinderRelationalSearchScore(query: 'axle volta', fields: voltta),
      greaterThan(0),
    );
    expect(
      bikeFinderRelationalSearchScore(query: '94845975', fields: voltta),
      0,
    );
  });

  test('normalizes accents, punctuation, serials, and formatted phones', () {
    const fields = [
      BikeFinderSearchField('Joaquín Saldías'),
      BikeFinderSearchField('+56 9 2015 8558'),
      BikeFinderSearchField('DBG-DRIVETRAIN-NO-PROFILE-1777'),
    ];

    expect(
      bikeFinderRelationalSearchScore(
        query: 'joaquin 2015 8558',
        fields: fields,
      ),
      greaterThan(0),
    );
    expect(
      bikeFinderRelationalSearchScore(
        query: '56920158558',
        fields: fields,
      ),
      greaterThan(0),
    );
    expect(
      bikeFinderRelationalSearchScore(
        query: 'dbgdrivetrainnoprofile1777',
        fields: fields,
      ),
      greaterThan(0),
    );
  });

  test('exact matches rank above fuzzy matches', () {
    final exact = bikeFinderRelationalSearchScore(
      query: 'volta',
      fields: const [BikeFinderSearchField('Volta Urban')],
    );
    final fuzzy = bikeFinderRelationalSearchScore(
      query: 'volta',
      fields: const [BikeFinderSearchField('Voltta Urban')],
    );

    expect(exact, greaterThan(fuzzy));
  });
}
