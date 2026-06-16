type ProductUrlFields = {
  id?: unknown;
  name?: unknown;
  sku?: unknown;
  website_name?: unknown;
};

const MAX_PRODUCT_SLUG_LENGTH = 80;

function stringValue(value: unknown) {
  return typeof value === "string" ? value.trim() : "";
}

export function productUrlSlug(value: unknown) {
  const normalized = stringValue(value)
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "");

  const truncated = normalized
    .slice(0, MAX_PRODUCT_SLUG_LENGTH)
    .replace(/-+$/g, "");

  return truncated || "producto";
}

export function publicProductPath(product: ProductUrlFields) {
  const productId = stringValue(product.id);
  const sku = stringValue(product.sku);
  if (!sku) return productId ? `/productos/${productId}` : "/productos";

  const displayName = stringValue(product.website_name) || stringValue(product.name);
  return `/productos/${productUrlSlug(displayName)}/${encodeURIComponent(sku)}`;
}

export function publicProductUrl(storeUrl: string, product: ProductUrlFields) {
  return `${storeUrl.replace(/\/+$/g, "")}${publicProductPath(product)}`;
}
