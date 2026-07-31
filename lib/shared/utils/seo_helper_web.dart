import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

void updateSeoImpl({
  required String title,
  String? description,
  String? imageUrl,
  String? keywords,
  String? canonicalUrl,
  String? robots,
  String ogType = 'website',
}) {
  // Update Browser Title
  SystemChrome.setApplicationSwitcherDescription(
    ApplicationSwitcherDescription(
      label: title,
      primaryColor: 0,
    ),
  );
  web.document.title = title;

  // Update Meta Description
  _updateMeta('description', description);
  _updateMeta('keywords', keywords);
  _updateMeta('robots', robots);
  _updateMeta('googlebot', robots);
  _updateCanonicalLink(canonicalUrl);

  // Open Graph Data
  _updateMetaProperty('og:title', title);
  _updateMetaProperty('og:description', description);
  _updateMetaProperty('og:image', imageUrl);
  _updateMetaProperty('og:url', canonicalUrl);
  _updateMetaProperty('og:type', ogType);
  // Twitter Cards
  _updateMeta('twitter:title', title);
  _updateMeta('twitter:description', description);
  _updateMeta('twitter:image', imageUrl);
  _updateMeta('twitter:url', canonicalUrl);
  _updateMeta(
    'twitter:card',
    imageUrl == null || imageUrl.trim().isEmpty
        ? 'summary'
        : 'summary_large_image',
  );
}

void _updateCanonicalLink(String? url) {
  final element = web.document.querySelector("link[rel='canonical']");
  if (url == null || url.isEmpty) {
    element?.remove();
    return;
  }

  if (element != null) {
    element.setAttribute('href', url);
  } else {
    final link = web.document.createElement('link') as web.HTMLLinkElement
      ..rel = 'canonical'
      ..href = url;
    web.document.head?.append(link);
  }
}

void _updateMeta(String name, String? content) {
  final element = web.document.querySelector("meta[name='$name']");
  if (content == null || content.isEmpty) {
    element?.remove();
    return;
  }

  // Try to find existing meta tag
  if (element != null) {
    element.setAttribute('content', content);
  } else {
    // Create new if not exists
    final meta = web.document.createElement('meta') as web.HTMLMetaElement
      ..name = name
      ..content = content;
    web.document.head?.append(meta);
  }
}

void _updateMetaProperty(String property, String? content) {
  final element = web.document.querySelector("meta[property='$property']");
  if (content == null || content.isEmpty) {
    element?.remove();
    return;
  }

  if (element != null) {
    element.setAttribute('content', content);
  } else {
    final meta = web.document.createElement('meta') as web.HTMLMetaElement
      ..setAttribute('property', property)
      ..content = content;
    web.document.head?.append(meta);
  }
}
