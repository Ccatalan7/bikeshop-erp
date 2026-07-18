import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vinabike_erp/modules/website/services/website_background_removal_processor.dart';

void main() {
  group('WebsiteBackgroundRemovalProcessor', () {
    test('removes only the uniform background connected to the border',
        () async {
      final source = img.Image(width: 12, height: 12);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(
        source,
        x1: 3,
        y1: 3,
        x2: 8,
        y2: 8,
        color: img.ColorRgb8(220, 40, 30),
      );
      // White packaging detail enclosed by the red subject must remain.
      source.setPixelRgba(5, 5, 255, 255, 255, 255);

      final result = await _process(
        Uint8List.fromList(img.encodePng(source)),
        tolerance: 24,
      );
      final output = img.decodePng(result.pngBytes)!;

      expect(output.getPixel(0, 0).a, 0);
      expect(output.getPixel(11, 11).a, 0);
      expect(output.getPixel(4, 4).a, 255);
      expect(output.getPixel(5, 5).a, 255);
      expect(result.isLikelyUniformBackground, isTrue);
    });

    test('does not report an unchanged image as a useful result', () async {
      final source = img.Image(width: 8, height: 8);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgba(
            x,
            y,
            (x * 31) % 255,
            (y * 37) % 255,
            ((x + y) * 23) % 255,
            255,
          );
        }
      }

      final result = await _process(
        Uint8List.fromList(img.encodePng(source)),
        tolerance: 8,
      );

      expect(result.isLikelyUniformBackground, isFalse);
    });

    test('preserves an image that already has a transparent background',
        () async {
      final source = img.Image(width: 20, height: 20, numChannels: 4);
      img.fill(source, color: img.ColorRgba8(0, 0, 0, 0));
      img.fillRect(
        source,
        x1: 6,
        y1: 5,
        x2: 13,
        y2: 14,
        color: img.ColorRgba8(230, 90, 20, 255),
      );

      final result = await _process(
        Uint8List.fromList(img.encodePng(source)),
      );
      final output = img.decodePng(result.pngBytes)!;

      expect(result.alreadyTransparent, isTrue);
      expect(result.isUseful, isFalse);
      expect(output.getPixel(9, 9).a, 255);
      expect(output.getPixel(0, 0).a, 0);
    });
  });
}

Future<WebsiteBackgroundRemovalResult> _process(
  Uint8List bytes, {
  int tolerance = 34,
}) {
  return Future<WebsiteBackgroundRemovalResult>.sync(
    () => WebsiteBackgroundRemovalProcessor.process(
      bytes,
      tolerance: tolerance,
    ),
  );
}
