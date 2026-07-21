import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  filterMerchantProductsByCheckoutTax,
  resolveMerchantAvailability,
  resolveMerchantIdentifiers,
} from "./google_merchant_feed.ts";

Deno.test("Merchant feed excludes products checkout cannot tax-classify", () => {
  const products = [
    { id: "exempt", tax_rate: 0 },
    { id: "taxed", tax_rate: 19 },
    { id: "legacy-taxed", tax_rate: 0.19 },
    { id: "missing", tax_rate: null },
    { id: "unsupported", tax_rate: 10 },
  ];

  assertEquals(
    filterMerchantProductsByCheckoutTax(products).map((product) => product.id),
    ["exempt", "taxed", "legacy-taxed"],
  );
});

Deno.test("Merchant availability matches tracked and untracked storefront stock", () => {
  assertEquals(
    resolveMerchantAvailability({ track_stock: false, stock_quantity: 0 }),
    "in_stock",
  );
  assertEquals(
    resolveMerchantAvailability({ track_stock: true, stock_quantity: 1 }),
    "in_stock",
  );
  assertEquals(
    resolveMerchantAvailability({ track_stock: true, stock_quantity: 0 }),
    "out_of_stock",
  );
});

Deno.test("Merchant identifiers never reinterpret the store SKU as MPN", () => {
  assertEquals(
    resolveMerchantIdentifiers({ sku: "AE0118" }),
    { gtin: "", mpn: "" },
  );
});

Deno.test("Merchant identifiers use explicit MPN and first valid GTIN", () => {
  assertEquals(
    resolveMerchantIdentifiers({
      website_merchant_gtin: "not-a-gtin",
      gtin: "022255354042",
      barcode: "4715575883212",
      website_merchant_mpn: "SM-DBOIL-1L",
    }),
    { gtin: "022255354042", mpn: "SM-DBOIL-1L" },
  );
});

Deno.test("Merchant identifiers reject invalid GTIN check digits", () => {
  assertEquals(
    resolveMerchantIdentifiers({
      gtin: "022255354043",
      barcode: "4715575883213",
    }),
    { gtin: "", mpn: "" },
  );
});
