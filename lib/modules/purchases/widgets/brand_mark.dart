import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import 'purchase_visual_language.dart';

/// La marca de un fabricante donde el ERP la nombra: su logo
/// (`product_brands.logo_url`, un cuadrado opaco ya compuesto para leerse
/// chico) o, sin logo, sus iniciales en uno de los cuatro tonos de avatar del
/// tema, siempre el mismo para la misma marca. El dueño (2026-11-03): «¿Cómo
/// voy a poner puro texto ahí?… dale un poquito de vida… no pases para el otro
/// extremo».
///
/// [solid] pinta las iniciales blancas sobre el tono pleno, sin el fondo
/// suave: así se lee un remitente en el Correo (2026-11-06, el dueño ya no
/// quiere fondos pastel: «un verde claro que parece de jardín infantil»).
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    required this.name,
    this.logoUrl,
    this.size = 32,
    this.solid = false,
  });

  final String name;
  final String? logoUrl;
  final double size;
  final bool solid;

  /// Dos letras que se leen como la marca: «SunRace» → SR, «e*thirteen» → ET,
  /// «A-FORGE» → AF, «KMC» → KM.
  static String lettersFor(String name) {
    final all = name
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .split(RegExp(r'[^A-Za-z0-9ÁÉÍÓÚÜÑáéíóúüñ]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    // «Banco de Chile» → BC, no BD: las partículas no son la marca.
    final words =
        all.where((part) => !_particles.contains(part.toLowerCase())).toList();
    final parts = words.isEmpty ? all : words;
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final word = parts.first;
      return (word.length >= 2 ? word.substring(0, 2) : word).toUpperCase();
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  static const Set<String> _particles = {
    'de',
    'del',
    'la',
    'las',
    'los',
    'el',
    'y',
    'e',
    'da',
    'do',
    'the',
    'of',
    'and',
  };

  /// El tono de la marca: estable por nombre, uno de cuatro.
  static int toneFor(String name) {
    var hash = 0;
    for (final unit in name.toLowerCase().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return hash % 4;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final roles = VinabikeThemeRoles.of(context);
    // En oscuro los tonos plenos del tema son claros (rosado, verde claro):
    // como fondo se leen a juguete, así que ahí la marca va siempre suave.
    final full = solid && roles.brightness != Brightness.dark;
    final (background, foreground) = switch (toneFor(name)) {
      0 => full
          ? (roles.avatarA, roles.onAvatarA)
          : (roles.avatarSoftA, roles.avatarA),
      1 => full
          ? (roles.avatarB, roles.onAvatarB)
          : (roles.avatarSoftB, roles.avatarB),
      2 => full
          ? (roles.avatarC, roles.onAvatarC)
          : (roles.avatarSoftC, roles.avatarC),
      _ => full
          ? (roles.avatarD, roles.onAvatarD)
          : (roles.avatarSoftD, roles.avatarD),
    };
    final radius = BorderRadius.circular(size >= 48 ? 10 : size * 0.25);
    final letters = Center(
      child: Text(
        lettersFor(name),
        style: GoogleFonts.ibmPlexMono(
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          height: 1,
          color: foreground,
        ),
      ),
    );
    final url = logoUrl?.trim();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: url == null || url.isEmpty ? background : tokens.surface,
          borderRadius: radius,
          border: full && (url == null || url.isEmpty)
              ? null
              : Border.all(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: url == null || url.isEmpty
            ? letters
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, __, ___) => ColoredBox(
                  color: background,
                  child: letters,
                ),
              ),
      ),
    );
  }
}
