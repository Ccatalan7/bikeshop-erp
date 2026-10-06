import 'package:flutter/material.dart';
import 'package:vinabike_public_core/public_store/theme/public_header_contrast.dart';

export 'package:vinabike_public_core/public_store/theme/public_header_contrast.dart';

/// The shared header contrast policy (`vinabike_public_core`) with Flutter
/// colors: one rule for this header and the HTML store's.
extension PublicHeaderContrastColorX on PublicHeaderContrastMode {
  bool usesLightForeground({
    required bool isOverlay,
    required Color backgroundColor,
  }) =>
      usesLightForegroundOn(
        isOverlay: isOverlay,
        backgroundArgb: backgroundColor.toARGB32(),
      );
}
