export type ProductAvailabilityFields = {
  track_stock?: unknown;
  is_set?: unknown;
  full_sets_available?: unknown;
  stock_quantity?: unknown;
  inventory_qty?: unknown;
};

export type ProductAvailabilityRow = {
  product_id?: unknown;
  available_quantity?: unknown;
};

/**
 * Canonical sellable quantity for catalog consumers.
 *
 * Set headers intentionally persist zero stock. Their sellable quantity is the
 * number of complete sets that can be assembled from canonical components.
 */
export function resolveAvailableProductQuantity(
  product: ProductAvailabilityFields,
): number {
  const raw = product.is_set === true
    ? product.full_sets_available
    : product.stock_quantity ?? product.inventory_qty;
  const quantity = Number(raw ?? 0);
  return Number.isFinite(quantity) ? Math.max(0, quantity) : 0;
}

export function isProductAvailable(
  product: ProductAvailabilityFields,
): boolean {
  if (product.track_stock === false) return true;
  return resolveAvailableProductQuantity(product) > 0;
}

/** Merge the reservation-aware database projection into catalog rows. */
export function mergeCanonicalAvailableQuantities<
  T extends ProductAvailabilityFields & { id?: unknown },
>(
  products: T[],
  availabilityRows: ProductAvailabilityRow[],
): T[] {
  const quantities = new Map(
    availabilityRows.map((row) => [
      String(row.product_id ?? ""),
      Math.max(0, Number(row.available_quantity ?? 0)),
    ]),
  );

  return products.map((product) => {
    const quantity = quantities.get(String(product.id ?? "")) ?? 0;
    return {
      ...product,
      stock_quantity: quantity,
      ...(product.is_set === true ? { full_sets_available: quantity } : {}),
    };
  });
}
