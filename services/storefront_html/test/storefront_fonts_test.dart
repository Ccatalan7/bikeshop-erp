import 'dart:io';
import 'dart:typed_data';

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
        'font-weight:400;font-display:swap;'
        'unicode-range:${storefrontFullFontRanges['Barlow']}}',
      ),
    );
    expect(
      '@font-face'.allMatches(css),
      hasLength(storefrontFontFaces.length * 2),
    );
  });

  test('the full file is asked only for what it draws', () {
    final repository = Directory.current.parent.parent.path;
    final latin = _ranges(storefrontLatinRange);
    for (final face in storefrontFontFaces) {
      final declared = _ranges(storefrontFullFontRanges[face.family]!);
      final drawn = _cmap(
        File('$repository/assets/fonts/${face.file}.ttf').readAsBytesSync(),
      );
      // Every face draws all of Spanish and more: a reader that found
      // nothing would pass the check below in vain.
      expect(drawn.length, greaterThan(400), reason: face.file);
      for (final code in drawn) {
        if (_inside(latin, code)) continue;
        expect(
          _inside(declared, code),
          isTrue,
          reason: '${face.file} draws U+${code.toRadixString(16)}',
        );
      }
      // An emoji, a sparkle and a star: no store font draws them.
      for (final code in [0x1F44C, 0x2728, 0x2605]) {
        expect(drawn.contains(code), isFalse);
        expect(_inside(declared, code), isFalse, reason: face.file);
      }
    }
  });
}

List<(int, int)> _ranges(String css) => [
  for (final part in css.split(','))
    if (part.trim().substring(2).split('-') case final ends)
      (int.parse(ends.first, radix: 16), int.parse(ends.last, radix: 16)),
];

bool _inside(List<(int, int)> ranges, int code) =>
    ranges.any((range) => range.$1 <= code && code <= range.$2);

/// The code points a TrueType file maps to a glyph (its `cmap`, format 4 or
/// 12).
Set<int> _cmap(List<int> bytes) {
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  int u16(int at) => data.getUint16(at);
  int u32(int at) => data.getUint32(at);
  var cmap = 0;
  for (var i = 0; i < u16(4); i++) {
    final entry = 12 + 16 * i;
    if (String.fromCharCodes(bytes.sublist(entry, entry + 4)) == 'cmap') {
      cmap = u32(entry + 8);
    }
  }
  int? format4;
  int? format12;
  for (var i = 0; i < u16(cmap + 2); i++) {
    final sub = cmap + u32(cmap + 4 + 8 * i + 4);
    switch (u16(sub)) {
      case 4:
        format4 ??= sub;
      case 12:
        format12 ??= sub;
    }
  }
  final codes = <int>{};
  if (format12 case final at?) {
    for (var i = 0; i < u32(at + 12); i++) {
      final group = at + 16 + 12 * i;
      for (var c = u32(group); c <= u32(group + 4); c++) {
        codes.add(c);
      }
    }
    return codes;
  }
  final at = format4!;
  final segments = u16(at + 6) ~/ 2;
  final ends = at + 14;
  final starts = ends + 2 * segments + 2;
  final deltas = starts + 2 * segments;
  final offsets = deltas + 2 * segments;
  for (var i = 0; i < segments; i++) {
    final start = u16(starts + 2 * i);
    final end = u16(ends + 2 * i);
    final delta = data.getInt16(deltas + 2 * i);
    final offset = u16(offsets + 2 * i);
    for (var c = start; c <= end && c != 0xFFFF; c++) {
      var glyph = 0;
      if (offset == 0) {
        glyph = (c + delta) & 0xFFFF;
      } else {
        glyph = u16(offsets + 2 * i + offset + 2 * (c - start));
        if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
      }
      if (glyph != 0) codes.add(c);
    }
  }
  return codes;
}
