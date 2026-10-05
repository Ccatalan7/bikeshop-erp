class WebsiteFontOption {
  const WebsiteFontOption({
    required this.family,
    required this.label,
  });

  final String family;
  final String label;
}

class WebsiteFontRegistry {
  const WebsiteFontRegistry._();

  static const headingDefault = 'Oswald';
  static const bodyDefault = 'Barlow';

  /// These are the only site fonts declared in pubspec.yaml today.
  static const bundledFonts = <WebsiteFontOption>[
    WebsiteFontOption(family: headingDefault, label: 'Oswald'),
    WebsiteFontOption(family: bodyDefault, label: 'Barlow'),
  ];

  static const labelsByFamily = <String, String>{
    headingDefault: 'Oswald',
    bodyDefault: 'Barlow',
  };

  static const supportedFamilies = <String>[
    headingDefault,
    bodyDefault,
  ];

  static bool isSupported(String? family) {
    final value = family?.trim();
    return value != null &&
        value.isNotEmpty &&
        supportedFamilies.contains(value);
  }

  static String resolveHeadingFont(String? family) {
    return _resolve(family, headingDefault);
  }

  static String resolveBodyFont(String? family) {
    return _resolve(family, bodyDefault);
  }

  static String? resolveOptionalHeadingFont(String? family) {
    final value = family?.trim();
    if (value == null || value.isEmpty) return null;
    return resolveHeadingFont(value);
  }

  static String? resolveOptionalBodyFont(String? family) {
    final value = family?.trim();
    if (value == null || value.isEmpty) return null;
    return resolveBodyFont(value);
  }

  static String _resolve(String? family, String fallback) {
    final value = family?.trim();
    if (value == null || value.isEmpty) return fallback;
    return isSupported(value) ? value : fallback;
  }
}
