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

    test(
        'transparent header and its light configured panel resolve independently',
        () {
      const configuredHeaderBackground = Color(0xFFF7F5F1);

      expect(
        PublicHeaderContrastMode.automatic.usesLightForeground(
          isOverlay: true,
          backgroundColor: configuredHeaderBackground,
        ),
        isTrue,
        reason: 'The transparent header protects text over the hero',
      );
      expect(
        PublicHeaderContrastMode.automatic.usesLightForeground(
          isOverlay: false,
          backgroundColor: configuredHeaderBackground,
        ),
        isFalse,
        reason: 'The solid menu panel follows its configured light surface',
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
      expect(
        PublicHeaderContrastMode.automatic.usesLightForeground(
          isOverlay: false,
          backgroundColor: const Color(0xFF8B9A78),
        ),
        isFalse,
        reason: 'Mid-tone surfaces need the higher-contrast dark foreground',
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
