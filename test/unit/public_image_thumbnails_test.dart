import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vinabike_public_core/public_store/models/public_image_thumbnail.dart';

import '../../scripts/generate_public_image_thumbnails.dart' as job;

const _tenant = '5443b130-cc28-45af-a420-cd500b288890';

void main() {
  group('the photos the job copies', () {
    test('are the card photo as the listing and as the page see it', () {
      final photos = job.publicCardPhotos([
        {
          'id': 'a',
          'image_url': 'https://cdn.example/a.jpg',
          'image_urls': ['https://cdn.example/a-2.jpg'],
          'website_image_url': 'https://cdn.example/a-web.jpg',
        },
        {
          'id': 'b',
          'image_urls': ['https://cdn.example/b.jpg', 'https://cdn.example/b-2.jpg'],
        },
        {'id': 'c'},
      ]);
      expect(photos, {
        'https://cdn.example/a.jpg',
        'https://cdn.example/a-web.jpg',
        'https://cdn.example/b.jpg',
      });
    });

    test('a replaced photo gets copies with new names', () {
      String path(String signature) => job.publicThumbnailPath(
        tenantId: _tenant,
        sourceUrl: 'https://cdn.example/a.jpg',
        signature: signature,
        width: 400,
      );
      expect(path('"v1"'), startsWith('public/thumbs/$_tenant/'));
      expect(path('"v1"'), endsWith('-400.jpg'));
      expect(path('"v1"'), path('"v1"'));
      expect(path('"v1"'), isNot(path('"v2"')));
    });
  });

  group('making the copies', () {
    test('narrower than the photo, keeping its shape, on a white ground', () {
      final photo = img.Image(width: 1200, height: 600, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0));
      img.fillRect(photo, x1: 0, y1: 0, x2: 599, y2: 599, color: img.ColorRgba8(200, 0, 0, 255));
      final made = job.makePublicThumbnails(img.encodePng(photo), [400, 800])!;
      expect(made.width, 1200);
      expect(made.height, 600);
      expect(made.copies.map((copy) => (copy.width, copy.height)), [
        (400, 200),
        (800, 400),
      ]);
      final small = img.decodeJpg(made.copies.first.bytes)!;
      final transparentCorner = small.getPixel(399, 0);
      expect(transparentCorner.r, greaterThan(240), reason: 'not black');
      expect(transparentCorner.g, greaterThan(240));
    });

    test('a photo already small gets no copies', () {
      final photo = img.Image(width: 220, height: 220)..clear(img.ColorRgb8(1, 2, 3));
      final made = job.makePublicThumbnails(img.encodeJpg(photo), [400, 800])!;
      expect(made.width, 220);
      expect(made.copies, isEmpty);
    });

    test('what is not an image is reported, not copied', () {
      expect(
        job.makePublicThumbnails(
          img.encodePng(img.Image(width: 1, height: 1)).sublist(0, 8),
          [400],
        ),
        isNull,
      );
    });
  });

  group('the record the storefront reads', () {
    test('offers the copies, then the photo at its own width', () {
      final thumbnail = PublicImageThumbnail.fromRow({
        'source_url': 'https://cdn.example/a b,c.jpg',
        'source_width': 1200,
        'source_height': 900,
        'variants': [
          {'width': 800, 'height': 600, 'url': 'https://cdn.example/t-800.jpg'},
          {'width': 400, 'height': 300, 'url': 'https://cdn.example/t-400.jpg'},
          // Not narrower than the photo: never offered.
          {'width': 1600, 'height': 1200, 'url': 'https://cdn.example/t-1600.jpg'},
        ],
      })!;
      expect(thumbnail.smallestUrl, 'https://cdn.example/t-400.jpg');
      expect(
        thumbnail.srcset,
        'https://cdn.example/t-400.jpg 400w, https://cdn.example/t-800.jpg 800w, '
        'https://cdn.example/a%20b%2Cc.jpg 1200w',
      );
    });

    test('a broken row is skipped', () {
      expect(PublicImageThumbnail.fromRow({'source_url': 'x'}), isNull);
      expect(
        PublicImageThumbnail.byUrl([
          null,
          {'source_url': 'https://cdn.example/a.jpg', 'source_width': 300, 'source_height': 300},
        ]).keys,
        ['https://cdn.example/a.jpg'],
      );
    });
  });
}
