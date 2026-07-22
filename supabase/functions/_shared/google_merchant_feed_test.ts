import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  filterMerchantProductsByCheckoutTax,
  isVerifiableMerchantBrand,
  resolveMerchantAvailability,
  resolveMerchantIdentifiers,
  resolveMerchantPrice,
} from "./google_merchant_feed.ts";

Deno.test("Merchant brand rejects legacy placeholders and origin labels", () => {
  assertEquals(isVerifiableMerchantBrand("Shimano"), true);
  assertEquals(isVerifiableMerchantBrand("Genérico"), false);
  assertEquals(isVerifiableMerchantBrand("China"), false);
  assertEquals(isVerifiableMerchantBrand("Taiwan"), false);
  assertEquals(isVerifiableMerchantBrand("Aliexpress"), false);
  assertEquals(isVerifiableMerchantBrand(""), false);
});

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
  assertEquals(
    resolveMerchantAvailability({
      track_stock: true,
      is_set: true,
      stock_quantity: 0,
      full_sets_available: 2,
    }),
    "in_stock",
  );
});

Deno.test("Merchant price uses the effective positive storefront price", () => {
  assertEquals(resolveMerchantPrice({ price: 10000 }), 10000);
  assertEquals(
    resolveMerchantPrice({ price: 10000, website_price: 12990 }),
    12990,
  );
  assertEquals(resolveMerchantPrice({ price: 10000, website_price: 0 }), null);
  assertEquals(resolveMerchantPrice({ price: 0, website_price: 12990 }), 12990);
  assertEquals(resolveMerchantPrice({ price: null, website_price: null }), null);
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
