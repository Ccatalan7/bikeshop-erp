import 'dart:html' as html;
import 'package:flutter/services.dart';

void updateSeoImpl({
  required String title,
  String? description,
  String? imageUrl,
  String? keywords,
  String? canonicalUrl,
}) {
  // Update Browser Title
  SystemChrome.setApplicationSwitcherDescription(
    ApplicationSwitcherDescription(
      label: title,
      primaryColor: 0,
    ),
  );
  html.document.title = title;

  // Update Meta Description
  _updateMeta('description', description);
  _updateMeta('keywords', keywords);
  _updateCanonicalLink(canonicalUrl);

  // Open Graph Data
  _updateMetaProperty('og:title', title);
  _updateMetaProperty('og:description', description);
  if (imageUrl != null) {
    _updateMetaProperty('og:image', imageUrl);
  }
  // Twitter Cards
  _updateMeta('twitter:title', title);
  _updateMeta('twitter:description', description);
  if (imageUrl != null) {
    _updateMeta('twitter:image', imageUrl);
  }
}

void _updateCanonicalLink(String? url) {
  final element = html.document.querySelector("link[rel='canonical']");
  if (url == null || url.isEmpty) {
    element?.remove();
    return;
  }

  if (element != null) {
    element.setAttribute('href', url);
  } else {
    final link = html.LinkElement()
      ..rel = 'canonical'
      ..href = url;
    html.document.head?.append(link);
  }
}

void _updateMeta(String name, String? content) {
  if (content == null || content.isEmpty) return;

  // Try to find existing meta tag
  final element = html.document.querySelector("meta[name='$name']");
  if (element != null) {
    element.setAttribute('content', content);
  } else {
    // Create new if not exists
    final meta = html.MetaElement()
      ..name = name
      ..content = content;
    html.document.head?.append(meta);
  }
}

void _updateMetaProperty(String property, String? content) {
  if (content == null || content.isEmpty) return;

  final element = html.document.querySelector("meta[property='$property']");
  if (element != null) {
    element.setAttribute('content', content);
  } else {
    final meta = html.MetaElement()
      ..setAttribute('property', property)
      ..content = content;
    html.document.head?.append(meta);
  }
}
