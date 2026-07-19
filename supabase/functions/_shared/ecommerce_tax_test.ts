import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { hasSupportedEcommerceTaxRate, normalizeEcommerceTaxRate } from "./ecommerce_tax.ts";

Deno.test("ecommerce tax accepts exempt and standard IVA classifications", () => {
  assertEquals(normalizeEcommerceTaxRate(0), 0);
  assertEquals(normalizeEcommerceTaxRate(19), 19);
  assertEquals(normalizeEcommerceTaxRate(0.19), 19);
});

Deno.test("ecommerce tax rejects absent and unsupported classifications", () => {
  assertEquals(hasSupportedEcommerceTaxRate(null), false);
  assertEquals(hasSupportedEcommerceTaxRate(undefined), false);
  assertEquals(hasSupportedEcommerceTaxRate(10), false);
  assertEquals(hasSupportedEcommerceTaxRate(""), false);
});
