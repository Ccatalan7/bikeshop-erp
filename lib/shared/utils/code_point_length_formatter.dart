import 'package:flutter/services.dart';

/// Stops a field at [maxLength] code points, the way PostgreSQL's `length`
/// counts a text. Flutter's `LengthLimitingTextInputFormatter` counts
/// characters (grapheme clusters): an accent typed apart from its letter is
/// one character there and two code points in the base, so a text it lets
/// through could still be refused on send (Codex review, 2026-10-08).
class CodePointLengthFormatter extends TextInputFormatter {
  const CodePointLengthFormatter(this.maxLength) : assert(maxLength > 0);

  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.runes.length <= maxLength) return newValue;
    // Typing past the limit leaves the text as it was; a paste is cut.
    if (oldValue.text.runes.length == maxLength) return oldValue;
    final text = String.fromCharCodes(newValue.text.runes.take(maxLength));
    int clamp(int offset) => offset < 0 ? offset : offset.clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: newValue.selection.copyWith(
        baseOffset: clamp(newValue.selection.baseOffset),
        extentOffset: clamp(newValue.selection.extentOffset),
      ),
    );
  }
}
