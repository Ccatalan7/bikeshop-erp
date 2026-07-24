import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/gtin_utils.dart';

void main() {
  test('accepts the first checksum-valid non-restricted GTIN', () {
    expect(
      firstValidGtin([
        '022255354042',
        '4715575883213',
        '4715575883212',
      ]),
      '4715575883212',
    );
  });

  test('rejects invalid lengths, check digits and reserved GS1 prefixes', () {
    expect(isValidGtin('123'), isFalse);
    expect(isValidGtin('4715575883213'), isFalse);
    expect(isValidGtin('022255354042'), isFalse);
    expect(isValidGtin('4715575883212'), isTrue);
  });
}
