import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/widgets/website_carousel_media.dart';

void main() {
  test('collects saved slide and Canvas image media without duplicates', () {
    final urls = collectWebsiteCarouselSlideImageUrls({
      'imageUrl': 'https://cdn.example.test/background.webp',
      'videoFileUrl': 'https://cdn.example.test/background.mp4',
      'elements': [
        {
          'type': 'image',
          'imageUrl': 'https://cdn.example.test/camera-cutout.png',
        },
        {
          'type': 'image',
          'imageUrl': 'https://cdn.example.test/camera-cutout.png',
        },
        {
          'type': 'image',
          'mobileImageUrl': 'https://cdn.example.test/camera-mobile.webp',
        },
      ],
    });

    expect(
      urls,
      [
        'https://cdn.example.test/background.webp',
        'https://cdn.example.test/camera-cutout.png',
        'https://cdn.example.test/camera-mobile.webp',
      ],
    );
  });

  test('recognizes editor-owned composed slides', () {
    expect(
      websiteCarouselSlideUsesComposition({
        'useComposition': true,
        'elements': const [],
      }),
      isTrue,
    );
    expect(
      websiteCarouselSlideUsesComposition({
        'elements': [
          {'type': 'text'}
        ],
      }),
      isTrue,
    );
    expect(
      websiteCarouselSlideUsesComposition({
        'elements': const [],
      }),
      isFalse,
    );
  });

  test('warms only the visible and next carousel slides', () {
    expect(
      websiteCarouselPreloadOrder(slideCount: 0, currentIndex: 0),
      isEmpty,
    );
    expect(
      websiteCarouselPreloadOrder(slideCount: 1, currentIndex: 0),
      [0],
    );
    expect(
      websiteCarouselPreloadOrder(slideCount: 4, currentIndex: 1),
      [1, 2],
    );
    expect(
      websiteCarouselPreloadOrder(slideCount: 4, currentIndex: 3),
      [3, 0],
    );
  });
}
