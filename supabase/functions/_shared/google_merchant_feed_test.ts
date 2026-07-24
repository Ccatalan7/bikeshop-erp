import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  filterMerchantProductsByCheckoutTax,
  isVerifiableMerchantBrand,
  projectPublicCommerceProduct,
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
    { gtin: "4715575883212", mpn: "SM-DBOIL-1L" },
  );
});

Deno.test("Merchant identifiers reject invalid and GS1-restricted GTINs", () => {
  assertEquals(
    resolveMerchantIdentifiers({
      gtin: "022255354043",
      barcode: "4715575883213",
    }),
    { gtin: "", mpn: "" },
  );
  assertEquals(
    resolveMerchantIdentifiers({
      gtin: "022255354042",
      barcode: "4715575883212",
    }),
    { gtin: "4715575883212", mpn: "" },
  );
});

Deno.test("canonical commerce projection keeps editor-owned facts unchanged", () => {
  assertEquals(
    projectPublicCommerceProduct(
      {
        id: "product-1",
        name: "Nombre catálogo",
        website_name: "Nombre web",
        website_merchant_title: "Nombre comercio",
        sku: "SKU-1",
        description: "Descripción catálogo",
        website_description: "Descripción web",
        website_merchant_description: "Descripción comercio",
        price: 10000,
        website_price: 12990,
        price_currency: "clp",
        stock_quantity: 3,
        inventory_qty: 9,
        track_stock: true,
        website_image_url: "https://cdn.example.com/product-1.webp",
        website_image_urls: [
          "https://cdn.example.com/product-1-detail.webp",
        ],
        brand: "Legacy brand",
        website_merchant_gtin: "022255354042",
        gtin: "invalid",
        barcode: "4715575883212",
        website_merchant_mpn: "SM-DBOIL-1L",
        website_google_product_category: "499713",
        category_id: "category-1",
      },
      {
        resolvedBrand: "Shimano",
        categoryPath: "Componentes / Transmisión / Cadenas",
      },
    ),
    {
      id: "product-1",
      sku: "SKU-1",
      title: "Nombre comercio",
      description: "Descripción comercio",
      price: 12990,
      currency: "CLP",
      availability: "in_stock",
      image_urls: [
        "https://cdn.example.com/product-1.webp",
        "https://cdn.example.com/product-1-detail.webp",
      ],
      brand: "Shimano",
      gtin: "4715575883212",
      mpn: "SM-DBOIL-1L",
      category_id: "category-1",
      category_path: "Componentes / Transmisión / Cadenas",
      google_product_category: "499713",
      merchant_eligible: true,
      merchant_issues: [],
    },
  );
});

Deno.test("canonical commerce projection rejects missing facts without guessing", () => {
  const projection = projectPublicCommerceProduct({
    id: "product-2",
    name: "Producto sin datos",
    sku: "RETAILER-SKU",
    description: "",
    price: 0,
    stock_quantity: 0,
    track_stock: true,
    brand: "Genérico",
    category_id: "category-2",
  });

  assertEquals(projection.merchant_eligible, false);
  assertEquals(projection.mpn, "");
  assertEquals(projection.gtin, "");
  assertEquals(projection.category_path, "");
  assertEquals(projection.merchant_issues, [
    "missing_description",
    "invalid_price",
    "missing_image",
    "missing_brand",
    "missing_product_identifiers",
  ]);
});

Deno.test("out of stock remains a valid Merchant availability", () => {
  const projection = projectPublicCommerceProduct({
    id: "product-out-of-stock",
    name: "Cámara 26",
    description: "Cámara para bicicleta aro 26.",
    price: 4990,
    stock_quantity: 0,
    track_stock: true,
    image_url: "https://cdn.example.com/camara.webp",
    brand: "RBX",
    website_merchant_mpn: "CAM-26-RBX",
  });

  assertEquals(projection.availability, "out_of_stock");
  assertEquals(projection.merchant_eligible, true);
  assertEquals(projection.merchant_issues, []);
});

Deno.test("brand alone does not replace GTIN or manufacturer MPN", () => {
  const projection = projectPublicCommerceProduct({
    id: "product-brand-only",
    name: "Cámara 29",
    description: "Cámara para bicicleta aro 29.",
    price: 5990,
    stock_quantity: 1,
    track_stock: true,
    image_url: "https://cdn.example.com/camara-29.webp",
    brand: "RBX",
  });

  assertEquals(projection.merchant_eligible, false);
  assertEquals(projection.merchant_issues, ["missing_product_identifiers"]);
});
