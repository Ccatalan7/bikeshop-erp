import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/code_point_length_formatter.dart';

/// The customer chat's fields stop where the base's `length` stops: code
/// points, not Flutter's characters (Codex review, 2026-10-08).
void main() {
  const formatter = CodePointLengthFormatter(4);

  TextEditingValue value(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );

  test('a text within the limit passes as typed', () {
    final next = value('\u{1F6B2}\u{1F6B2}ab');
    expect(formatter.formatEditUpdate(value(''), next), next);
  });

  test('an accent typed apart counts as one more point', () {
    // Three characters for Flutter, five code points for the base.
    final cut = formatter.formatEditUpdate(value(''), value('e\u0301e\u0301e'));
    expect(cut.text, 'e\u0301e\u0301');
    expect(cut.text.runes.length, 4);
    expect(cut.selection, const TextSelection.collapsed(offset: 4));
  });

  test('an emoji is one point and is never split', () {
    final cut = formatter.formatEditUpdate(
      value(''),
      value('\u{1F6B2}' * 6),
    );
    expect(cut.text, '\u{1F6B2}' * 4);
    expect(cut.selection, const TextSelection.collapsed(offset: 8));
  });

  test('typing past a full field leaves it as it was', () {
    final full = value('abcd');
    expect(formatter.formatEditUpdate(full, value('abcde')), full);
  });
}
