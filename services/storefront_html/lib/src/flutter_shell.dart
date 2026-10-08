import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vinabike_public_core/public_store/seo/public_product_structured_data.dart';

import 'site_layout.dart';

/// The Flutter store's page, which loads the Flutter app wherever it is
/// served. An editor page the HTML storefront cannot draw whole is answered
/// with it on its public path, so a block the HTML does not cover yet never
/// disappears from the site: Flutter draws the page as before.
abstract interface class FlutterShell {
  /// The page's HTML, or `null` when it cannot be read.
  Future<String?> html(String storeUrl);
}

/// Reads `<store>/app.html` from Firebase Hosting, where it is a static
/// file; before the home moves to this server that path falls through to the
/// `index.html` the store serves for every route, which is the same page.
/// Kept for a minute: it changes only when the store is published.
class HostedFlutterShell implements FlutterShell {
  HostedFlutterShell({HttpClient? client})
    : _client =
          client ??
          (HttpClient()
            ..connectionTimeout = const Duration(seconds: 5)
            ..idleTimeout = const Duration(seconds: 10));

  final HttpClient _client;
  ({String storeUrl, String html, DateTime at})? _cached;

  static const _maxAge = Duration(minutes: 1);

  @override
  Future<String?> html(String storeUrl) async {
    final cached = _cached;
    if (cached != null &&
        cached.storeUrl == storeUrl &&
        DateTime.now().difference(cached.at) < _maxAge) {
      return cached.html;
    }
    try {
      final request = await _client
          .getUrl(Uri.parse('$storeUrl/app.html'))
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || !body.contains('flutter')) {
        return cached?.html;
      }
      _cached = (storeUrl: storeUrl, html: body, at: DateTime.now());
      return body;
    } on Object catch (error) {
      stderr.writeln('flutter shell read failed: $error');
      return cached?.html;
    }
  }
}

/// The Flutter page made this page's own for whoever reads it without
/// running the app: its title, description, canonical, robots and social
/// tags from [meta], its structured data, and [main] (what the HTML server
/// drew) in place of the home's words in the no-script fallback. Without
/// this, a page answered by Flutter would tell Google it is the home.
String adaptFlutterShell(String shell, PageMeta meta, {required String main}) {
  final attribute = const HtmlEscape(HtmlEscapeMode.attribute);
  final text = const HtmlEscape(HtmlEscapeMode.element);
  var html = shell;
  String replaceContent(String html, String attr, String name, String value) {
    final tag = RegExp(
      '<meta\\s+$attr="${RegExp.escape(name)}"\\s+content="[^"]*"\\s*/?>',
    );
    return html.replaceFirst(
      tag,
      '<meta $attr="$name" content="${attribute.convert(value)}">',
    );
  }

  html = html.replaceFirst(
    RegExp(r'<title>[\s\S]*?</title>'),
    '<title>${text.convert(meta.title)}</title>',
  );
  for (final (attr, name, value) in [
    ('name', 'title', meta.title),
    ('name', 'description', meta.description),
    (
      'name',
      'robots',
      meta.indexable
          ? 'index,follow,max-image-preview:large'
          : 'noindex,follow',
    ),
    ('name', 'twitter:url', meta.canonicalUrl),
    ('name', 'twitter:title', meta.title),
    ('name', 'twitter:description', meta.description),
    ('property', 'og:type', meta.ogType),
    ('property', 'og:url', meta.canonicalUrl),
    ('property', 'og:title', meta.title),
    ('property', 'og:description', meta.description),
  ]) {
    html = replaceContent(html, attr, name, value);
  }
  html = html.replaceFirst(
    RegExp(r'<link\s+rel="canonical"\s+href="[^"]*"\s*/?>'),
    '<link rel="canonical" href="${attribute.convert(meta.canonicalUrl)}">',
  );
  if (meta.structuredData.isNotEmpty) {
    html = html.replaceFirst(
      '</head>',
      [
        for (final data in meta.structuredData)
          '<script type="application/ld+json">'
              '${encodeStructuredDataForHtml(data)}</script>',
        '</head>',
      ].join('\n'),
    );
  }
  return html.replaceFirst(
    RegExp(r'<main class="storefront-nojs-fallback">[\s\S]*?</main>'),
    '<main class="storefront-nojs-fallback">$main</main>',
  );
}

/// What a rendered page holds in its `<main>`, without the element itself.
String mainContentOf(String html) {
  final match = RegExp(r'<main\b[^>]*>([\s\S]*)</main>').firstMatch(html);
  return match?.group(1) ?? '';
}
