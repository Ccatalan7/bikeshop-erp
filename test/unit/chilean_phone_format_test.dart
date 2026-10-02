import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/chilean_utils.dart';

void main() {
  test('a Chilean phone reads the same however it was typed', () {
    expect(ChileanUtils.formatPhone('+56981210019'), '+56 9 8121 0019');
    expect(ChileanUtils.formatPhone('+569 66146358'), '+56 9 6614 6358');
    expect(ChileanUtils.formatPhone('56950030277'), '+56 9 5003 0277');
    expect(ChileanUtils.formatPhone('9 2383 9425'), '+56 9 2383 9425');
    expect(ChileanUtils.formatPhone('+56 2 2345 6789'), '+56 2 2345 6789');
  });

  test('what is not a Chilean number stays as written', () {
    expect(ChileanUtils.formatPhone(null), '');
    expect(ChileanUtils.formatPhone('  '), '');
    expect(ChileanUtils.formatPhone('+1 415 555 0100'), '+1 415 555 0100');
    expect(ChileanUtils.formatPhone('anexo 12'), 'anexo 12');
  });
}
