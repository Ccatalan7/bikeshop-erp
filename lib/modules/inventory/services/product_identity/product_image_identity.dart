/// Stable identity of a product photo, independent of the CDN transformation
/// suffix AliExpress appends (`.jpg_640x640q90.jpg_.webp`) and of which of its
/// image hosts served it.
///
/// Lives on its own so the catalog index and the matcher share one definition:
/// two copies of this normalization would silently disagree the first time one
/// of them learned a new host.
String canonicalProductImageIdentity(String? imageUrl) {
  if (imageUrl == null || imageUrl.trim().isEmpty) return '';
  final uri = Uri.tryParse(imageUrl.trim());
  if (uri == null) return imageUrl.trim().toLowerCase();
  var host = uri.host.toLowerCase();
  if (host.endsWith('.alicdn.com') ||
      host == 'alicdn.com' ||
      host.endsWith('.aliexpress-media.com') ||
      host == 'aliexpress-media.com') {
    host = 'aliexpress-image';
  }
  var path = Uri.decodeComponent(uri.path).toLowerCase();
  path = path.replaceFirstMapped(
    RegExp(r'(\.(?:jpe?g|png|webp|gif))(?:_[^/]*)$'),
    (match) => match.group(1)!,
  );
  path = path.replaceAll(RegExp(r'/+'), '/');
  return '$host$path';
}

/// Supplier listing identifiers found in free text or in a code column.
///
/// An AliExpress listing id groups the colours of one publication; it is
/// retrieval evidence, never proof of which variant was bought.
Set<String> supplierListingIdsIn(Iterable<String?> values) {
  final ids = <String>{};
  for (final value in values) {
    if (value == null || value.trim().isEmpty) continue;
    final bare = value.trim();
    if (_bareListingId.hasMatch(bare)) ids.add(bare);
    for (final match in _listingIdPatterns.allMatches(value)) {
      for (var group = 1; group <= match.groupCount; group++) {
        final id = match.group(group);
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
  }
  return ids;
}

final RegExp _bareListingId = RegExp(r'^\d{10,}$');

final RegExp _listingIdPatterns = RegExp(
  r'item\s*id\s*:?\s*(\d{8,})|itemid=(\d{8,})|/item/(\d{8,})'
  r'|productid=(\d{8,})',
  caseSensitive: false,
);
