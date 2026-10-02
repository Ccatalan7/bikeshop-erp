/// The digits `wa.me` expects for a Chilean number the owner typed in the
/// website editor: «+56 9 1234 5678», «912345678» or «56912345678» all become
/// «56912345678». Empty when nothing usable was typed.
String whatsappDigits(String input) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  if (digits.startsWith('56')) return digits;
  if (digits.length == 9 && digits.startsWith('9')) return '56$digits';
  if (digits.length == 8) return '56$digits';
  return digits;
}

/// A chat with the store, with [text] already written; null without a number.
/// Spaces go as %20, like the footer's link: a form-encoded «+» is not a
/// space for every WhatsApp client.
Uri? whatsappChatUri(String input, {String? text}) {
  final digits = whatsappDigits(input);
  if (digits.isEmpty) return null;
  final message = text?.trim() ?? '';
  return Uri.parse(
    'https://wa.me/$digits'
    '${message.isEmpty ? '' : '?text=${Uri.encodeComponent(message)}'}',
  );
}
