import 'package:flutter/foundation.dart';

import '../../shared/models/public_product_visibility_policy.dart';

@immutable
class CatalogAvailabilityFacetDecision {
  const CatalogAvailabilityFacetDecision({
    required this.visible,
    required this.enabled,
  });

  final bool visible;
  final bool enabled;
}

CatalogAvailabilityFacetDecision decideCatalogAvailabilityFacet({
  required PublicCatalogStockPolicy stockPolicy,
  required bool isEditMode,
  required bool facetDataAvailable,
}) {
  final meaningful = stockPolicy != PublicCatalogStockPolicy.availableOnly;
  return CatalogAvailabilityFacetDecision(
    visible: meaningful || isEditMode,
    enabled: meaningful && (isEditMode || facetDataAvailable),
  );
}

@immutable
class CatalogCollectionFacetDecision<T> {
  const CatalogCollectionFacetDecision({
    required this.heading,
    required this.options,
    required this.siblingMode,
  });

  final String heading;
  final List<T> options;
  final bool siblingMode;
}

CatalogCollectionFacetDecision<T>? decideCatalogCollectionFacet<T>({
  required String? selectedId,
  required List<T> children,
  required String? parentName,
  required List<T> siblings,
}) {
  if (selectedId == null) return null;
  if (children.isNotEmpty) {
    return CatalogCollectionFacetDecision<T>(
      heading: 'Subcategorías',
      options: List<T>.unmodifiable(children),
      siblingMode: false,
    );
  }
  if (parentName == null || parentName.trim().isEmpty || siblings.length < 2) {
    return null;
  }
  return CatalogCollectionFacetDecision<T>(
    heading: 'Más en ${parentName.trim()}',
    options: List<T>.unmodifiable(siblings),
    siblingMode: true,
  );
}
