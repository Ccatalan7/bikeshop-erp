import '../../shared/utils/chilean_utils.dart';

enum PublicProductSeoValueSource { explicit, generated }

class PublicProductSeoCopy {
  final String title;
  final String description;
  final String searchPhrase;
  final PublicProductSeoValueSource titleSource;
  final PublicProductSeoValueSource descriptionSource;

  const PublicProductSeoCopy({
    required this.title,
    required this.description,
    required this.searchPhrase,
    required this.titleSource,
    required this.descriptionSource,
  });
}

/// Factual product data consumed by every public SEO-copy surface.
///
/// Keeping the raw number here (instead of accepting an already formatted
/// string) prevents runtime, editor preview and static snapshots from choosing
/// different representations for `{product_price}`.
class PublicProductSeoProductInput {
  const PublicProductSeoProductInput({
    required this.name,
    required this.sku,
    required this.price,
    required this.brand,
    required this.description,
    this.categoryPath = '',
  });

  final String name;
  final String sku;
  final double price;
  final String brand;
  final String description;
  final String categoryPath;
}

/// The single typed entry used to resolve public product SEO copy.
class PublicProductSeoCopyInput {
  const PublicProductSeoCopyInput({
    required this.product,
    required this.storeName,
    required this.locality,
    required this.titleTemplate,
    required this.descriptionTemplate,
    this.seoTitleOverride = '',
    this.seoDescriptionOverride = '',
    this.searchTerms = const [],
  });

  final PublicProductSeoProductInput product;
  final String storeName;
  final String locality;
  final String titleTemplate;
  final String descriptionTemplate;
  final String seoTitleOverride;
  final String seoDescriptionOverride;

  /// Ordered editor guidance. Only the first non-empty phrase enriches
  /// generated customer-facing copy. Secondary phrases are retained by their
  /// owner but are not emitted as metadata keywords.
  final List<String> searchTerms;
}

/// Resolves templates, factual fallback and the primary search phrase through
/// one shared path for runtime, editor preview and static snapshots.
PublicProductSeoCopy resolvePublicProductSeoCopyFromInput(
  PublicProductSeoCopyInput input, {
  int titleMaxLength = 120,
  int descriptionMaxLength = 320,
}) {
  final product = input.product;
  final templateValues = PublicProductSeoProductInput(
    name: sanitizePublicProductSeoText(product.name),
    sku: sanitizePublicProductSeoText(product.sku),
    price: product.price,
    brand: sanitizePublicProductSeoText(product.brand),
    description: sanitizePublicProductSeoText(product.description),
    categoryPath: sanitizePublicProductSeoText(product.categoryPath),
  );
  final storeName = sanitizePublicProductSeoText(input.storeName);
  final locality = sanitizePublicProductSeoText(input.locality);
  final formattedPrice = formatPublicProductSeoPriceClp(product.price);

  return resolvePublicProductSeoCopy(
    seoTitleOverride: input.seoTitleOverride,
    seoDescriptionOverride: input.seoDescriptionOverride,
    generatedTitleBase: applyPublicProductSeoTemplate(
      template: input.titleTemplate,
      storeName: storeName,
      productName: templateValues.name,
      productSku: templateValues.sku,
      productPrice: formattedPrice,
      productBrand: templateValues.brand,
      productDescription: templateValues.description,
    ),
    generatedDescriptionBase: applyPublicProductSeoTemplate(
      template: input.descriptionTemplate,
      storeName: storeName,
      productName: templateValues.name,
      productSku: templateValues.sku,
      productPrice: formattedPrice,
      productBrand: templateValues.brand,
      productDescription: templateValues.description,
    ),
    fallbackDescription: buildPublicProductSeoFallbackDescription(
      product: templateValues,
      storeName: storeName,
    ),
    storeName: storeName,
    locality: locality,
    searchTerms: input.searchTerms,
    titleMaxLength: titleMaxLength,
    descriptionMaxLength: descriptionMaxLength,
  );
}

String formatPublicProductSeoPriceClp(double price) {
  if (!price.isFinite || price <= 0) return '';
  return ChileanUtils.formatCurrency(price);
}

/// Factual fallback shared by commerce projection and all SEO-copy consumers.
String buildPublicProductSeoFallbackDescription({
  required PublicProductSeoProductInput product,
  required String storeName,
}) {
  final title = sanitizePublicProductSeoText(product.name);
  final store = sanitizePublicProductSeoText(storeName);
  final qualifiers = <String>[
    sanitizePublicProductSeoText(product.brand),
    sanitizePublicProductSeoText(product.categoryPath),
  ].where((value) => value.isNotEmpty).toList(growable: false);
  final identity =
      qualifiers.isEmpty ? title : '$title — ${qualifiers.join(' · ')}';
  final effectiveIdentity = identity.isEmpty ? 'este producto' : identity;
  final effectiveStore = store.isEmpty ? 'la tienda' : store;
  return _truncateSeoText(
    'Conoce $effectiveIdentity. Revisa precio, stock y opciones de compra en '
    '$effectiveStore.',
    320,
  );
}

String applyPublicProductSeoTemplate({
  required String template,
  required String storeName,
  required String productName,
  required String productSku,
  required String productPrice,
  required String productBrand,
  required String productDescription,
}) {
  return sanitizePublicProductSeoText(
    template
        .replaceAll('{store_name}', sanitizePublicProductSeoText(storeName))
        .replaceAll('{product_name}', sanitizePublicProductSeoText(productName))
        .replaceAll('{product_sku}', sanitizePublicProductSeoText(productSku))
        .replaceAll(
          '{product_price}',
          sanitizePublicProductSeoText(productPrice),
        )
        .replaceAll(
          '{product_brand}',
          sanitizePublicProductSeoText(productBrand),
        )
        .replaceAll(
          '{product_description}',
          sanitizePublicProductSeoText(productDescription),
        ),
  );
}

/// Resolves the title and description shared by runtime, preview, and static
/// SEO snapshots.
///
/// Search terms are product-owned guidance. Only the first explicit phrase may
/// enrich generated copy; they never override hand-written metadata and are
/// never emitted as a hidden keyword dump.
PublicProductSeoCopy resolvePublicProductSeoCopy({
  required String seoTitleOverride,
  required String seoDescriptionOverride,
  required String generatedTitleBase,
  required String generatedDescriptionBase,
  required String fallbackDescription,
  required String storeName,
  required String locality,
  required Iterable<String> searchTerms,
  int titleMaxLength = 120,
  int descriptionMaxLength = 320,
}) {
  final explicitTitle = _cleanSeoText(seoTitleOverride);
  final explicitDescription = _cleanSeoText(seoDescriptionOverride);
  final searchPhrase = searchTerms
      .map(_cleanSeoText)
      .firstWhere((term) => term.isNotEmpty, orElse: () => '');

  final title = explicitTitle.isNotEmpty
      ? _truncateSeoText(explicitTitle, titleMaxLength)
      : _buildGeneratedTitle(
          baseTitle: generatedTitleBase,
          storeName: storeName,
          locality: locality,
          searchPhrase: searchPhrase,
          maxLength: titleMaxLength,
        );

  final generatedDescription = _appendSearchPhrase(
    description: _cleanSeoText(generatedDescriptionBase).isNotEmpty
        ? generatedDescriptionBase
        : fallbackDescription,
    searchPhrase: searchPhrase,
  );
  final description = _truncateSeoText(
    explicitDescription.isNotEmpty ? explicitDescription : generatedDescription,
    descriptionMaxLength,
  );

  return PublicProductSeoCopy(
    title: title,
    description: description,
    searchPhrase: searchPhrase,
    titleSource: explicitTitle.isNotEmpty
        ? PublicProductSeoValueSource.explicit
        : PublicProductSeoValueSource.generated,
    descriptionSource: explicitDescription.isNotEmpty
        ? PublicProductSeoValueSource.explicit
        : PublicProductSeoValueSource.generated,
  );
}

String _buildGeneratedTitle({
  required String baseTitle,
  required String storeName,
  required String locality,
  required String searchPhrase,
  required int maxLength,
}) {
  final cleanStoreName = _cleanSeoText(storeName);
  final cleanLocality = _cleanSeoText(locality);
  final suffix = [cleanStoreName, cleanLocality]
      .where((part) => part.isNotEmpty)
      .join(' ');
  var root = _cleanSeoText(baseTitle);

  if (cleanStoreName.isNotEmpty) {
    root = root.replaceFirst(
      RegExp(
        r'\s*\|\s*' + RegExp.escape(cleanStoreName) + r'\s*$',
        caseSensitive: false,
      ),
      '',
    );
  }

  final shortPhrase = _shortSearchPhrase(searchPhrase, locality: cleanLocality);
  final shouldPrefix = shortPhrase.isNotEmpty &&
      !_titleAlreadyTargetsPhrase(
        _normalizeSearchText(root),
        searchPhrase,
        locality: cleanLocality,
      );
  final effectiveSuffix = suffix.isEmpty ? 'Tienda' : suffix;
  final separatorLength = shouldPrefix ? ' -  | '.length : ' | '.length;
  final availableRootLength =
      maxLength - effectiveSuffix.length - separatorLength - shortPhrase.length;
  final rootLimit = availableRootLength < 24 ? 24 : availableRootLength;
  final fittedRoot = _truncateSeoText(
    root.isEmpty ? 'Producto' : root,
    rootLimit,
  );
  final rawTitle = shouldPrefix
      ? '$shortPhrase - $fittedRoot | $effectiveSuffix'
      : '$fittedRoot | $effectiveSuffix';

  return _truncateSeoText(_cleanSeoText(rawTitle), maxLength);
}

String _appendSearchPhrase({
  required String description,
  required String searchPhrase,
}) {
  final cleanDescription = _cleanSeoText(description);
  if (searchPhrase.isEmpty) return cleanDescription;

  final normalizedDescription = _normalizeSearchText(cleanDescription);
  final normalizedPhrase = _normalizeSearchText(searchPhrase);
  if (normalizedDescription.contains(normalizedPhrase)) {
    return cleanDescription;
  }

  final prefix = cleanDescription.isEmpty ? '' : '$cleanDescription ';
  return _cleanSeoText(
    '${prefix}Ideal si buscas $searchPhrase.',
  );
}

bool _titleAlreadyTargetsPhrase(
  String normalizedTitle,
  String searchPhrase, {
  required String locality,
}) {
  final wheelSize = _extractWheelSize(searchPhrase);
  if (wheelSize.isNotEmpty) {
    return normalizedTitle.contains('aro ${_normalizeWheelSize(wheelSize)}');
  }

  var normalizedPhrase = _normalizeSearchText(searchPhrase);
  final normalizedLocality = _normalizeSearchText(locality);
  if (normalizedLocality.isNotEmpty) {
    normalizedPhrase = normalizedPhrase
        .replaceAll(' para bicicleta en $normalizedLocality', '')
        .replaceAll(' en $normalizedLocality', '');
  }
  return normalizedPhrase.isNotEmpty &&
      normalizedTitle.contains(normalizedPhrase);
}

String _shortSearchPhrase(String searchPhrase, {required String locality}) {
  if (searchPhrase.isEmpty) return '';
  var shortened = _cleanSeoText(searchPhrase);
  if (locality.isNotEmpty) {
    shortened = shortened.replaceAll(
      ' para bicicleta en $locality',
      ' $locality',
    );
  }
  if (shortened.isEmpty) return '';
  return '${shortened[0].toUpperCase()}${shortened.substring(1)}';
}

String _extractWheelSize(String text) {
  final normalized = _normalizeSearchText(text);
  final patterns = <RegExp>[
    RegExp(r'\baro\s*(700c?|29|28|27[.,]?5|26|24|20|18|16|14|12)\b'),
    RegExp(r'\b(700c?|29|28|27[.,]?5|26|24|20|18|16|14|12)\s*(?:x|×)\b'),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(normalized);
    if (match != null) return _normalizeWheelSize(match.group(1) ?? '');
  }
  return '';
}

String _normalizeWheelSize(String size) {
  final normalized = size.toLowerCase().replaceAll(',', '.').trim();
  if (normalized == '700') return '700c';
  if (normalized == '27.5') return '27.5';
  return normalized.replaceAll(RegExp(r'[^0-9a-z.]'), '');
}

String _normalizeSearchText(String text) {
  var normalized = text.toLowerCase();
  const replacements = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  replacements
      .forEach((from, to) => normalized = normalized.replaceAll(from, to));
  return normalized.replaceAll('×', 'x').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String sanitizePublicProductSeoText(String value) {
  var clean = value
      .replaceAll(
        RegExp(
          r'<(?:script|style)\b[^>]*>.*?</(?:script|style)>',
          caseSensitive: false,
          dotAll: true,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  clean = clean
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#160;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
  clean = clean.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (match) {
      final value = int.tryParse(match.group(1) ?? '');
      return value == null || value < 0 || value > 0x10ffff
          ? match.group(0)!
          : String.fromCharCode(value);
    },
  );
  clean = clean.replaceAllMapped(
    RegExp(r'&#x([0-9a-f]+);', caseSensitive: false),
    (match) {
      final value = int.tryParse(match.group(1) ?? '', radix: 16);
      return value == null || value < 0 || value > 0x10ffff
          ? match.group(0)!
          : String.fromCharCode(value);
    },
  );
  // Encoded markup such as `&lt;b&gt;texto&lt;/b&gt;` becomes markup only
  // after entity decoding. Strip once more so every caller receives plain text.
  clean = clean
      .replaceAll(
        RegExp(
          r'<(?:script|style)\b[^>]*>.*?</(?:script|style)>',
          caseSensitive: false,
          dotAll: true,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'<[^>]+>'), ' ');
  return clean.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _cleanSeoText(String value) => sanitizePublicProductSeoText(value);

String _truncateSeoText(String value, int maxLength) {
  final clean = _cleanSeoText(value);
  if (clean.length <= maxLength) return clean;
  final cut = clean.substring(0, maxLength).trim();
  final lastSpace = cut.lastIndexOf(' ');
  return lastSpace > (maxLength * 0.75).floor()
      ? cut.substring(0, lastSpace).trim()
      : cut;
}
