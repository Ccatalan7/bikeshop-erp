import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/theme/public_header_contrast.dart';

void main() {
  group('PublicHeaderContrastMode', () {
    test('automatic protects an overlay header with a light foreground', () {
      expect(
        PublicHeaderContrastMode.automatic.usesLightForeground(
          isOverlay: true,
          backgroundColor: Colors.white,
        ),
        isTrue,
      );
    });

    test('automatic follows the luminance of a solid header', () {
      expect(
        PublicHeaderContrastMode.automatic.usesLightForeground(
          isOverlay: false,
          backgroundColor: const Color(0xFF101612),
        ),
        isTrue,
      );
      expect(
        PublicHeaderContrastMode.automatic.usesLightForeground(
          isOverlay: false,
          backgroundColor: Colors.white,
        ),
        isFalse,
      );
    });

    test('explicit editor modes override automatic behavior', () {
      expect(
        PublicHeaderContrastMode.light.usesLightForeground(
          isOverlay: true,
          backgroundColor: Colors.black,
        ),
        isFalse,
      );
      expect(
        PublicHeaderContrastMode.dark.usesLightForeground(
          isOverlay: false,
          backgroundColor: Colors.white,
        ),
        isTrue,
      );
    });

    test('unknown persisted values safely migrate to automatic', () {
      expect(
        PublicHeaderContrastModeX.parse('legacy'),
        PublicHeaderContrastMode.automatic,
      );
    });
  });
}
