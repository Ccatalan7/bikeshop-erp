import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vinabike_erp/modules/website/services/website_image_upload_processor.dart';
import 'package:vinabike_erp/modules/website/services/website_media_service.dart';

void main() {
  test('oversized opaque uploads are bounded before server optimization',
      () async {
    final source = img.Image(width: 2800, height: 120, numChannels: 3)
      ..clear(img.ColorRgb8(210, 190, 170));
    final bytes = Uint8List.fromList(img.encodeJpg(source, quality: 96));

    final prepared = await WebsiteImageUploadProcessor.prepare(
      bytes: bytes,
      fileName: 'foto-taller.jpg',
    );

    expect(prepared.width, WebsiteImageUploadProcessor.maxSourceLongEdge);
    expect(prepared.height, lessThan(120));
    expect(prepared.contentType, 'image/jpeg');
    expect(prepared.hasTransparency, isFalse);
    expect(prepared.wasNormalized, isTrue);
    expect(
      prepared.bytes.length,
      lessThanOrEqualTo(WebsiteImageUploadProcessor.maxSourceBytes),
    );
  });

  test('transparent uploads keep alpha while bounding their source', () async {
    final source = img.Image(width: 2600, height: 160, numChannels: 4)
      ..clear(img.ColorRgba8(30, 60, 90, 255));
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < 500; x++) {
        source.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
    final bytes = Uint8List.fromList(img.encodePng(source));

    final prepared = await WebsiteImageUploadProcessor.prepare(
      bytes: bytes,
      fileName: 'producto-sin-fondo.png',
    );

    expect(prepared.width, WebsiteImageUploadProcessor.maxSourceLongEdge);
    expect(prepared.contentType, 'image/png');
    expect(prepared.hasTransparency, isTrue);
    expect(prepared.fileName, endsWith('-source.png'));
    final decoded = img.decodePng(prepared.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.getPixel(0, 0).a, 0);
  });

  test('input limit fails before a heavyweight decode', () async {
    final bytes = Uint8List(WebsiteImageUploadProcessor.maxInputBytes + 1);

    await expectLater(
      WebsiteImageUploadProcessor.prepare(
        bytes: bytes,
        fileName: 'demasiado-grande.png',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('media asset exposes canonical source and thumbnail metadata', () {
    const asset = WebsiteMediaAsset(
      name: 'producto-web.webp',
      path: 'website/media/producto-web.webp',
      publicUrl: 'https://cdn.example.com/producto-web.webp',
      metadata: <String, dynamic>{
        'website_variant': 'web',
        'source_path': 'website/media/sources/producto.png',
        'source_url': 'https://cdn.example.com/producto.png',
        'thumbnail_url': 'https://cdn.example.com/producto-thumb.webp',
        'source_bytes': 1200000,
        'web_bytes': 82000,
      },
    );

    expect(asset.isWebOptimized, isTrue);
    expect(asset.sourcePath, 'website/media/sources/producto.png');
    expect(asset.sourceUrl, 'https://cdn.example.com/producto.png');
    expect(asset.thumbnailUrl, 'https://cdn.example.com/producto-thumb.webp');
    expect(asset.sourceByteLength, 1200000);
    expect(asset.webByteLength, 82000);
  });
}
