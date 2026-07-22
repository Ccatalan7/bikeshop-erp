import { hasSupportedEcommerceTaxRate } from "./ecommerce_tax.ts";
import { isProductAvailable, type ProductAvailabilityFields } from "./product_availability.ts";

type MerchantIdentifierFields = {
  sku?: string | null;
  website_merchant_gtin?: string | null;
  gtin?: string | null;
  barcode?: string | null;
  website_merchant_mpn?: string | null;
};

export type MerchantIdentifiers = {
  gtin: string;
  mpn: string;
};

type MerchantPriceFields = {
  price?: unknown;
  website_price?: unknown;
};

/**
 * Merchant may advertise only products the public checkout can actually sell.
 * Other publication/image/stock rules remain owned by the feed itself.
 */
export function filterMerchantProductsByCheckoutTax<
  T extends { tax_rate?: unknown },
>(products: T[]): T[] {
  return products.filter((product) => hasSupportedEcommerceTaxRate(product.tax_rate));
}

/**
 * Resolve only identifiers whose provenance is appropriate for Merchant.
 *
 * A store-assigned SKU is not a manufacturer part number. Products without a
 * verified GTIN or explicit manufacturer MPN intentionally omit identifiers;
 * the feed must not guess either an MPN or `identifier_exists=false`.
 */
export function resolveMerchantIdentifiers(
  product: MerchantIdentifierFields,
): MerchantIdentifiers {
  return {
    gtin: validGtin(
      product.website_merchant_gtin,
      product.gtin,
      product.barcode,
    ),
    mpn: firstNonEmpty(product.website_merchant_mpn),
  };
}

/** Keep Merchant availability aligned with the public storefront contract. */
export function resolveMerchantAvailability(
  product: ProductAvailabilityFields,
): "in_stock" | "out_of_stock" {
  return isProductAvailable(product) ? "in_stock" : "out_of_stock";
}

/** Resolve the exact positive price rendered by the public storefront. */
export function resolveMerchantPrice(
  product: MerchantPriceFields,
): number | null {
  const price = Number(product.website_price ?? product.price);
  return Number.isFinite(price) && price > 0 ? price : null;
}

/**
 * Require a factual manufacturer/brand, not a marketplace, origin country, or
 * generic placeholder recorded in a legacy catalog field.
 */
export function isVerifiableMerchantBrand(value: unknown): boolean {
  const normalized = String(value ?? "")
    .trim()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
  if (!normalized) return false;
  return !new Set(["generico", "generic", "china", "taiwan", "aliexpress"])
    .has(normalized);
}

function firstNonEmpty(...values: Array<string | null | undefined>): string {
  for (const value of values) {
    const text = String(value ?? "").trim();
    if (text.length > 0) return text;
  }
  return "";
}

function validGtin(...values: Array<string | null | undefined>): string {
  for (const rawValue of values) {
    const value = String(rawValue ?? "").trim().replace(/[\s-]+/g, "");
    if (!/^\d+$/.test(value)) continue;
    if (![8, 12, 13, 14].includes(value.length)) continue;
    if (!hasValidGtinCheckDigit(value)) continue;
    return value;
  }
  return "";
}

function hasValidGtinCheckDigit(value: string): boolean {
  const digits = value.split("").map((digit) => Number.parseInt(digit, 10));
  const checkDigit = digits[digits.length - 1];
  let sum = 0;
  let positionFromRight = 1;

  for (let i = digits.length - 2; i >= 0; i--) {
    sum += digits[i] * (positionFromRight % 2 === 1 ? 3 : 1);
    positionFromRight++;
  }

  return (10 - (sum % 10)) % 10 === checkDigit;
}
