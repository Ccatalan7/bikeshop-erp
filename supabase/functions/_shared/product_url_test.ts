import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { productUrlSlug, publicProductPath, publicProductUrl } from "./product_url.ts";

Deno.test("productUrlSlug creates a readable Spanish slug", () => {
  assertEquals(
    productUrlSlug('Neumático Vuelta MTB CB531 26x1.95" Negro'),
    "neumatico-vuelta-mtb-cb531-26x1-95-negro",
  );
});

Deno.test("publicProductPath uses website name and SKU", () => {
  assertEquals(
    publicProductPath({
      id: "9eaf3153-6bb8-4e2b-8d2e-69c5ec06c493",
      name: "Internal name",
      website_name: "Neumático Vuelta MTB CB531",
      sku: "N079",
    }),
    "/productos/neumatico-vuelta-mtb-cb531/N079",
  );
});

Deno.test("publicProductUrl trims trailing store URL slashes", () => {
  assertEquals(
    publicProductUrl("https://vinabike.cl/", {
      id: "44d273dd-1b45-41f3-9120-6e963c34b748",
      name: "Asiento Paseo C/resorte N707",
      sku: "2000000305653",
    }),
    "https://vinabike.cl/productos/asiento-paseo-c-resorte-n707/2000000305653",
  );
});
