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

export type PublicCommerceProjectionInput =
  & MerchantIdentifierFields
  & MerchantPriceFields
  & ProductAvailabilityFields
  & {
    id?: unknown;
    name?: unknown;
    website_name?: unknown;
    website_merchant_title?: unknown;
    description?: unknown;
    website_description?: unknown;
    website_merchant_description?: unknown;
    price_currency?: unknown;
    image_url?: unknown;
    image_url_optimized?: unknown;
    website_image_url?: unknown;
    website_image_url_optimized?: unknown;
    image_urls?: unknown;
    website_image_urls?: unknown;
    brand?: unknown;
    website_merchant_brand?: unknown;
    category_id?: unknown;
    website_google_product_category?: unknown;
  };

export type PublicCommerceProjectionContext = {
  resolvedBrand?: unknown;
  categoryPath?: unknown;
};

export type PublicCommerceProjection = {
  id: string;
  sku: string;
  title: string;
  description: string;
  price: number;
  currency: string;
  availability: "in_stock" | "out_of_stock";
  image_urls: string[];
  brand: string;
  gtin: string;
  mpn: string;
  category_id: string;
  category_path: string;
  google_product_category: string;
  merchant_eligible: boolean;
  merchant_issues: string[];
};

/**
 * Resolve the same factual public-commerce contract used by landing pages,
 * Product structured data, deploy snapshots, checkout mirrors, and Merchant.
 *
 * Merchant-specific fields are explicit staff-owned overrides. This function
 * never derives identity, brand, category, GTIN, or MPN from product copy.
 */
export function projectPublicCommerceProduct(
  product: PublicCommerceProjectionInput,
  context: PublicCommerceProjectionContext = {},
): PublicCommerceProjection {
  const id = firstNonEmpty(String(product.id ?? ""));
  const sku = firstNonEmpty(product.sku);
  const title = firstNonEmpty(
    String(product.website_merchant_title ?? ""),
    String(product.website_name ?? ""),
    String(product.name ?? ""),
  );
  const description = firstNonEmpty(
    String(product.website_merchant_description ?? ""),
    String(product.website_description ?? ""),
    String(product.description ?? ""),
  );
  const price = resolveMerchantPrice(product) ?? 0;
  const currency = firstNonEmpty(
    String(product.price_currency ?? ""),
    "CLP",
  ).toUpperCase();
  const availability = resolveMerchantAvailability(product);
  const imageUrls = publicProductImageUrls(product);
  const brand = firstNonEmpty(
    String(product.website_merchant_brand ?? ""),
    String(context.resolvedBrand ?? ""),
    String(product.brand ?? ""),
  );
  const { gtin, mpn } = resolveMerchantIdentifiers(product);
  const categoryId = firstNonEmpty(String(product.category_id ?? ""));
  const categoryPath = categoryId ? firstNonEmpty(String(context.categoryPath ?? "")) : "";
  const googleProductCategory = firstNonEmpty(
    String(product.website_google_product_category ?? ""),
  );
  const hasVerifiableBrand = isVerifiableMerchantBrand(brand);
  const merchantIssues = [
    ...(!id ? ["missing_identity"] : []),
    ...(!title ? ["missing_title"] : []),
    ...(!description ? ["missing_description"] : []),
    ...(!(price > 0) ? ["invalid_price"] : []),
    ...(imageUrls.length === 0 ? ["missing_image"] : []),
    ...(!hasVerifiableBrand ? ["missing_brand"] : []),
    ...(gtin || (hasVerifiableBrand && mpn) ? [] : ["missing_product_identifiers"]),
  ];

  return {
    id,
    sku,
    title,
    description,
    price,
    currency,
    availability,
    image_urls: imageUrls,
    brand,
    gtin,
    mpn,
    category_id: categoryId,
    category_path: categoryPath,
    google_product_category: googleProductCategory,
    merchant_eligible: merchantIssues.length === 0,
    merchant_issues: merchantIssues,
  };
}

/**
 * Merchant and checkout share the same supported tax classifications.
 * Publication and stock visibility remain owned by the canonical public RPC;
 * an accessible out-of-stock offer is still a valid Merchant item.
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

function publicProductImageUrls(
  product: PublicCommerceProjectionInput,
): string[] {
  const urls: string[] = [];
  const add = (value: unknown) => {
    const url = String(value ?? "").trim();
    if (
      (!url.startsWith("https://") && !url.startsWith("http://")) ||
      urls.includes(url)
    ) {
      return;
    }
    urls.push(url);
  };

  add(firstNonEmpty(
    String(product.website_image_url_optimized ?? ""),
    String(product.image_url_optimized ?? ""),
  ));
  add(firstNonEmpty(
    String(product.website_image_url ?? ""),
    String(product.image_url ?? ""),
  ));

  const websiteGallery = Array.isArray(product.website_image_urls)
    ? product.website_image_urls
    : [];
  const baseGallery = Array.isArray(product.image_urls) ? product.image_urls : [];
  for (
    const image of websiteGallery.length > 0 ? websiteGallery : baseGallery
  ) {
    add(image);
  }

  return urls.slice(0, 10);
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
    if (hasRestrictedGs1Prefix(value)) continue;
    if (!hasValidGtinCheckDigit(value)) continue;
    return value;
  }
  return "";
}

function hasRestrictedGs1Prefix(value: string): boolean {
  // GTIN-14 begins with a packaging indicator; the GS1 prefix follows it.
  const gs1Payload = value.length === 14 ? value.slice(1) : value;
  return ["02", "04", "2", "98", "99"].some((prefix) => gs1Payload.startsWith(prefix));
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
