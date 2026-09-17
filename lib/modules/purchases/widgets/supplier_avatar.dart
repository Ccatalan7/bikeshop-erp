import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import 'purchase_visual_language.dart';

/// El avatar de un proveedor o de una persona suya, en una sola versión.
///
/// Vivía dentro de la ficha y el directorio no tenía ninguno, así que la imagen
/// que se carga en la ficha no se veía en la lista donde se busca al proveedor.
/// Al sacarlo acá, las dos superficies usan el mismo control —`image_contract`,
/// radio 8, monograma de dos letras sobre `avatarA`— y no dos parecidos que se
/// separan con el tiempo.
class SupplierAvatar extends StatelessWidget {
  const SupplierAvatar({
    super.key,
    required this.name,
    required this.size,
    this.imageUrl,
    this.person = false,
  });

  final String name;
  final double size;
  final String? imageUrl;

  /// Una persona usa el segundo tono de avatar, para que no se confunda con
  /// la empresa.
  final bool person;

  static String lettersFor(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    return switch (words.length) {
      0 => '?',
      1 => words.first.length >= 2
          ? words.first.substring(0, 2).toUpperCase()
          : words.first.toUpperCase(),
      _ => '${words[0][0]}${words[1][0]}'.toUpperCase(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final background = person ? roles.avatarB : roles.avatarA;
    final foreground = person ? roles.onAvatarB : roles.onAvatarA;
    final url = imageUrl?.trim();
    final radius = BorderRadius.circular(PurchaseMetrics.mediaRadius);
    final letters = Text(
      lettersFor(name),
      style: GoogleFonts.ibmPlexMono(
        fontSize: size >= PurchaseMetrics.mediaInspector ? 15 : 13,
        fontWeight: FontWeight.w700,
        color: foreground,
      ),
    );
    final hasImage = url != null && url.isNotEmpty;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          border: Border.all(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        // Una marca se contiene; una cara se recorta. Un logotipo suele ser
        // mucho más ancho que alto —el de TeknoBike mide 415×77— y `cover`
        // sobre un cuadrado deja tres letras del medio.
        // El aire existe para que la marca no toque la esquina redondeada, y en
        // un avatar chico cada píxel cuenta: un logotipo apaisado ya llega
        // reducido por su propia proporción.
        padding: !hasImage || person
            ? EdgeInsets.zero
            : EdgeInsets.all(
                size >= PurchaseMetrics.mediaInspector ? size * 0.10 : 2),
        child: !hasImage
            ? letters
            : Image.network(
                url,
                fit: person ? BoxFit.cover : BoxFit.contain,
                // Contenida, la imagen la mide el hueco que deja el padding:
                // fijarle el lado completo la desborda.
                width: person ? size : null,
                height: person ? size : null,
                errorBuilder: (_, __, ___) => letters,
              ),
      ),
    );
  }
}
