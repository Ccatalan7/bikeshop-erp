/// Lee un color del tema del sitio tal como lo guarda el editor: entero ARGB
/// decimal (`4281236786`), `0x…`, `Color(…)`, `#RRGGBB`/`#AARRGGBB` o el hex
/// legado sin `#` de seis u ocho caracteres. Devuelve el ARGB o `null`.
///
/// Dart puro: lo usan `WebsiteResolvedTheme` en la app y el generador de
/// snapshots de la tienda, que no puede importar Flutter. Un solo lector para
/// que la página instantánea y la tienda no resuelvan distinto el mismo valor.
int? parseWebsiteThemeColorValue(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;

  var cleaned = value.toLowerCase();
  if (cleaned.startsWith('color(') && cleaned.endsWith(')')) {
    cleaned = cleaned.substring(6, cleaned.length - 1).trim();
    return int.tryParse(cleaned);
  }

  if (cleaned.startsWith('0x')) {
    return int.tryParse(cleaned);
  }

  final explicitlyHex = cleaned.startsWith('#');
  if (explicitlyHex) cleaned = cleaned.substring(1);
  final isHex = RegExp(r'^[0-9a-f]+$').hasMatch(cleaned);
  // Six/eight-character bare values are the legacy RGB/ARGB form even when
  // they contain digits only. Parse them before decimal so `123456` cannot
  // silently become the integer color 0x0001E240.
  final unambiguousBareHex =
      !explicitlyHex && (cleaned.length == 6 || cleaned.length == 8);
  if (isHex && (explicitlyHex || unambiguousBareHex)) {
    final hex = int.tryParse(cleaned, radix: 16);
    if (hex == null) return null;
    return cleaned.length <= 6 ? 0xFF000000 | hex : hex;
  }

  final decimal = int.tryParse(cleaned);
  if (decimal != null) return decimal;

  if (isHex) {
    final hex = int.tryParse(cleaned, radix: 16);
    if (hex != null) {
      return cleaned.length <= 6 ? 0xFF000000 | hex : hex;
    }
  }
  return null;
}
