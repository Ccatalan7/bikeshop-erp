import 'package:test/test.dart';
import 'package:vinabike_public_core/public_store/models/public_related_fit.dart';

/// 2026-10-23: under a 700 x 23C road tyre the store listed 20-, 24- and
/// 26-inch tyres because related products were the category by name.
void main() {
  List<String> rank(List<String> ids, Map<String, int> shared) =>
      rankRelatedByFit(ids, idOf: (id) => id, sharedById: shared);

  test('the ones that share more come first, then the catalog order', () {
    expect(
      rank(
        ['24in', '20in', 'roadrunner-25', 'gravel-38', 'kross-38'],
        {'roadrunner-25': 2, 'gravel-38': 1, 'kross-38': 1},
      ),
      ['roadrunner-25', 'gravel-38', 'kross-38'],
    );
  });

  test('with nothing shared the category keeps its order', () {
    expect(rank(['a', 'b', 'c'], const {}), ['a', 'b', 'c']);
  });
}
