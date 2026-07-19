import { hasSupportedEcommerceTaxRate } from "./ecommerce_tax.ts";

/**
 * Merchant may advertise only products the public checkout can actually sell.
 * Other publication/image/stock rules remain owned by the feed itself.
 */
export function filterMerchantProductsByCheckoutTax<
  T extends { tax_rate?: unknown },
>(products: T[]): T[] {
  return products.filter((product) => hasSupportedEcommerceTaxRate(product.tax_rate));
}
