import 'package:flutter/material.dart';

import '../theme/payroll_tokens.dart';

/// Único owner visual de la identidad abreviada en Nóminas.
///
/// La persona conserva un par `avatar/onAvatar` estable, resuelto y contrastado
/// por el tema. Así ningún preset vuelve a combinar un círculo oscuro con
/// iniciales oscuras.
class PayrollPersonAvatar extends StatelessWidget {
  const PayrollPersonAvatar({
    super.key,
    required this.personId,
    required this.initials,
    this.size = 32,
    this.fontSize = 10.5,
  });

  final String personId;
  final String initials;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final palette = _avatarPalette(visual);
    final identityPair = palette[_avatarPaletteIndex(personId, palette.length)];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: identityPair.$1,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        maxLines: 1,
        style: visual.avatarInitials(fontSize).copyWith(color: identityPair.$2),
      ),
    );
  }
}

Color payrollPersonAvatarColor(
  PayrollVisualTokens visual,
  String personId,
) {
  final palette = _avatarPalette(visual);
  return palette[_avatarPaletteIndex(personId, palette.length)].$1;
}

List<(Color, Color)> _avatarPalette(PayrollVisualTokens visual) =>
    <(Color, Color)>[
      (visual.avatarCyan, visual.avatarCyanInk),
      (visual.avatarSky, visual.avatarSkyInk),
      (visual.groupLabor, visual.groupLaborInk),
      (visual.avatarAmber, visual.avatarAmberInk),
    ];

int _avatarPaletteIndex(String personId, int paletteLength) {
  var hash = 0x811c9dc5;
  for (final unit in personId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return hash % paletteLength;
}
