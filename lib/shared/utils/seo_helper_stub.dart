void updateSeoImpl({
  required String title,
  String? description,
  String? imageUrl,
  String? keywords,
}) {
  // No-op on non-web platforms (mobile/desktop app)
  // Flutter handles the title via Title widget or SystemChrome,
  // but meta tags are not applicable in the same way.
}
