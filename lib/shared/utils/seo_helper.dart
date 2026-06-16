import 'seo_helper_stub.dart' if (dart.library.html) 'seo_helper_web.dart';

/// Helper to update SEO Meta Tags and Title in the browser
class SeoHelper {
  /// Updates the browser title and meta (description, keywords, og:image)
  static void updateSeo({
    required String title,
    String? description,
    String? imageUrl,
    String? keywords,
    String? canonicalUrl,
  }) {
    updateSeoImpl(
      title: title,
      description: description,
      imageUrl: imageUrl,
      keywords: keywords,
      canonicalUrl: canonicalUrl,
    );
  }
}
