import 'dart:io';

import 'package:test/test.dart';
import 'package:vinabike_storefront_html/src/storefront_fonts.dart';

void main() {
  test('the full font covers exactly what the Latin subset leaves out', () {
    expect(
      complementOfUnicodeRange('U+0000-00FF,U+0131,U+0152-0153'),
      'U+0100-0130,U+0132-0151,U+0154-10FFFF',
    );
    // Out of order and touching spans: no gap between them.
    expect(
      complementOfUnicodeRange('U+2000-206F,U+0000-00FF,U+0100-0130'),
      'U+0131-1FFF,U+2070-10FFFF',
    );
    expect(
      complementOfUnicodeRange(storefrontLatinRange),
      startsWith('U+0100-0130,U+0132-0151,U+0154-02BA,'),
    );
  });

  test('every face has its subset in web/fonts, cut with the same range', () {
    final repository = Directory.current.parent.parent.path;
    for (final face in storefrontFontFaces) {
      final file = File('$repository/web${storefrontLatinFontUrl(face.file)}');
      expect(file.existsSync(), isTrue, reason: file.path);
      expect(
        File('$repository/assets/fonts/${face.file}.ttf').existsSync(),
        isTrue,
        reason: '${face.file}.ttf, for the characters outside the subset',
      );
    }
    final script = File(
      '$repository/scripts/fonts/subset_storefront_fonts.sh',
    ).readAsStringSync();
    expect(script, contains("RANGE='$storefrontLatinRange'"));
    for (final face in storefrontFontFaces) {
      expect(script, contains(face.file));
    }
  });

  test('a face is declared twice: the subset, then the rest of Unicode', () {
    final css = storefrontFontFacesCss();
    expect(
      css,
      contains(
        '@font-face{font-family:Barlow;'
        'src:url(/fonts/Barlow-Regular.latin.woff2) format("woff2"),'
        'url(/assets/assets/fonts/Barlow-Regular.ttf) format("truetype");'
        'font-weight:400;font-display:swap;'
        'unicode-range:$storefrontLatinRange}',
      ),
    );
    expect(
      css,
      contains(
        'src:url(/assets/assets/fonts/Barlow-Regular.ttf) format("truetype");'
        'font-weight:400;font-display:swap;unicode-range:U+0100-0130,',
      ),
    );
    expect(
      '@font-face'.allMatches(css),
      hasLength(storefrontFontFaces.length * 2),
    );
  });
}
