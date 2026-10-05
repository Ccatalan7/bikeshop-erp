import 'seo_helper_stub.dart' if (dart.library.html) 'seo_helper_web.dart';

// The route rule (`projectStorefrontSeoRoute` and its helpers) lives in
// vinabike_public_core since 2026-10-05; the HTML storefront applies it too.
export 'package:vinabike_public_core/public_store/seo/storefront_seo_route.dart';

/// Helper to update SEO Meta Tags and Title in the browser
class SeoHelper {
  /// Updates the browser title and meta (description, keywords, og:image)
  static void updateSeo({
    required String title,
    String? description,
    String? imageUrl,
    String? keywords,
    String? canonicalUrl,
    String? robots,
    String ogType = 'website',
  }) {
    updateSeoImpl(
      title: title,
      description: description,
      imageUrl: imageUrl,
      keywords: keywords,
      canonicalUrl: canonicalUrl,
      robots: robots,
      ogType: ogType,
    );
  }
}
