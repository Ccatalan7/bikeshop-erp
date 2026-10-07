import 'package:test/test.dart';
import 'package:vinabike_public_core/modules/website/models/website_block_normalization.dart';

void main() {
  test(
    'a carousel keeps only its slides, so every reader counts them alike',
    () {
      final data = normalizeWebsiteBlockData(
        blockTypeRaw: 'carousel',
        rawBlockData: {
          'slides': [
            {'title': 'Primera'},
            'no es una diapositiva',
            null,
            {'title': 'Segunda'},
          ],
        },
      );
      expect(
        [for (final slide in data['slides'] as List) (slide as Map)['title']],
        ['Primera', 'Segunda'],
      );
    },
  );
}
