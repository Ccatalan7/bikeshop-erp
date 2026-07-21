import '../models/inventory_models.dart';

class ProductSetAvailabilityProjection {
  const ProductSetAvailabilityProjection({
    required this.isConfigured,
    required this.completeSetsAvailable,
    required this.hasPartialStock,
    required this.hasNegativeComponentStock,
    required this.components,
  });

  final bool isConfigured;
  final int completeSetsAvailable;
  final bool hasPartialStock;
  final bool hasNegativeComponentStock;
  final List<Product> components;
}

ProductSetAvailabilityProjection projectProductSetAvailability({
  required Product setProduct,
  required Iterable<Product> allProducts,
  Map<String, int> quantityInSetByComponentId = const {},
}) {
  final setId = setProduct.id;
  final components = setId == null
      ? <Product>[]
      : allProducts
          .where((product) => product.parentSetId == setId)
          .toList(growable: false)
    ..sort(
      (a, b) => (a.componentPosition ?? 0).compareTo(b.componentPosition ?? 0),
    );
  if (components.isEmpty) {
    return const ProductSetAvailabilityProjection(
      isConfigured: false,
      completeSetsAvailable: 0,
      hasPartialStock: false,
      hasNegativeComponentStock: false,
      components: [],
    );
  }

  var completeSets = 1 << 31;
  var hasNegative = false;
  for (final component in components) {
    final quantityInSet = component.id == null
        ? 1
        : (quantityInSetByComponentId[component.id!] ?? 1)
            .clamp(1, 1 << 31)
            .toInt();
    final stock = component.inventoryQty;
    if (stock < 0) hasNegative = true;
    final available = stock <= 0 ? 0 : stock ~/ quantityInSet;
    if (available < completeSets) completeSets = available;
  }

  final hasPartial = hasNegative ||
      components.any((component) {
        final quantityInSet = component.id == null
            ? 1
            : (quantityInSetByComponentId[component.id!] ?? 1)
                .clamp(1, 1 << 31)
                .toInt();
        return component.inventoryQty > completeSets * quantityInSet;
      });

  return ProductSetAvailabilityProjection(
    isConfigured: true,
    completeSetsAvailable: completeSets,
    hasPartialStock: hasPartial,
    hasNegativeComponentStock: hasNegative,
    components: components,
  );
}

class InventoryPhysicalSummary {
  const InventoryPhysicalSummary({
    required this.inventoryCost,
    required this.lowStockCount,
    required this.outOfStockCount,
  });

  final double inventoryCost;
  final int lowStockCount;
  final int outOfStockCount;
}

InventoryPhysicalSummary summarizePhysicalInventory({
  required Iterable<Product> visibleProducts,
  required Iterable<Product> allProducts,
}) {
  final physicalById = <String, Product>{};
  for (final product in visibleProducts) {
    if (!product.tracksInventory) continue;
    if (product.isSet) {
      final setId = product.id;
      if (setId == null) continue;
      for (final component in allProducts.where(
        (candidate) => candidate.parentSetId == setId,
      )) {
        final componentId = component.id;
        if (componentId == null || !component.tracksInventory) continue;
        physicalById[componentId] = component;
      }
      continue;
    }
    final productId = product.id;
    if (productId != null) physicalById[productId] = product;
  }

  var inventoryCost = 0.0;
  var lowStockCount = 0;
  var outOfStockCount = 0;
  for (final product in physicalById.values) {
    if (product.cost > 0) {
      inventoryCost += product.cost * product.inventoryQty;
    }
    if (product.inventoryQty <= 0) {
      outOfStockCount += 1;
    } else if (product.isLowStock) {
      lowStockCount += 1;
    }
  }

  return InventoryPhysicalSummary(
    inventoryCost: inventoryCost,
    lowStockCount: lowStockCount,
    outOfStockCount: outOfStockCount,
  );
}
