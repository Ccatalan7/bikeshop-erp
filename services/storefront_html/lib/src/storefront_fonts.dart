/// The storefront's fonts, as the HTML pages declare them: each face's Latin
/// subset as WOFF2 from `web/fonts/` (built by
/// `scripts/fonts/subset_storefront_fonts.sh`, ~20 KB against the ~50 KB of
/// the compressed TTF) and, for any other character, the full TTF Flutter
/// uses. The two ranges never overlap, so a page in Spanish downloads only
/// the small files and a name in another script still finds its glyph.
library;

/// Google Fonts' «latin» range, the same the subset script cuts.
const storefrontLatinRange =
    'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,'
    'U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,'
    'U+2215,U+FEFF,U+FFFD';

/// One face: its family, the file name both formats share, its weights.
typedef StorefrontFontFace = ({String family, String file, String weight});

/// The faces the store's theme can name (`WebsiteFontRegistry`); any other
/// family falls back to the system stack.
const storefrontFontFaces = <StorefrontFontFace>[
  (family: 'Oswald', file: 'Oswald-wght', weight: '200 700'),
  (family: 'Barlow', file: 'Barlow-Regular', weight: '400'),
  (family: 'Barlow', file: 'Barlow-Medium', weight: '500'),
  (family: 'Barlow', file: 'Barlow-SemiBold', weight: '600'),
  (family: 'Barlow', file: 'Barlow-Bold', weight: '700'),
  (family: 'Barlow', file: 'Barlow-ExtraBold', weight: '800 900'),
];

/// Where Firebase Hosting serves a face's Latin subset.
String storefrontLatinFontUrl(String file) => '/fonts/$file.latin.woff2';

/// The `@font-face` rules for every face, the subset and the full file.
String storefrontFontFacesCss() {
  final rest = complementOfUnicodeRange(storefrontLatinRange);
  return [
    for (final face in storefrontFontFaces) ...[
      // The full file second: a subset Hosting does not have yet (the
      // server is published before the store) costs a request, not the font.
      '@font-face{font-family:${face.family};'
          'src:url(${storefrontLatinFontUrl(face.file)}) format("woff2"),'
          'url(/assets/assets/fonts/${face.file}.ttf) format("truetype");'
          'font-weight:${face.weight};font-display:swap;'
          'unicode-range:$storefrontLatinRange}',
      '@font-face{font-family:${face.family};'
          'src:url(/assets/assets/fonts/${face.file}.ttf) format("truetype");'
          'font-weight:${face.weight};font-display:swap;'
          'unicode-range:$rest}',
    ],
  ].join('\n');
}

/// Every code point a `unicode-range` list leaves out, as another list.
String complementOfUnicodeRange(String range) {
  (int, int) bounds(String part) {
    final ends = part.trim().substring(2).split('-');
    return (int.parse(ends.first, radix: 16), int.parse(ends.last, radix: 16));
  }

  final spans = [for (final part in range.split(',')) bounds(part)]
    ..sort((a, b) => a.$1.compareTo(b.$1));
  String hex(int value) =>
      value.toRadixString(16).toUpperCase().padLeft(4, '0');
  String span(int from, int to) =>
      from == to ? 'U+${hex(from)}' : 'U+${hex(from)}-${hex(to)}';
  final gaps = <String>[];
  var next = 0;
  for (final (from, to) in spans) {
    if (from > next) gaps.add(span(next, from - 1));
    if (to + 1 > next) next = to + 1;
  }
  if (next <= 0x10FFFF) gaps.add(span(next, 0x10FFFF));
  return gaps.join(',');
}
