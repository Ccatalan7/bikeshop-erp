import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { filterMerchantProductsByCheckoutTax } from "./google_merchant_feed.ts";

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
