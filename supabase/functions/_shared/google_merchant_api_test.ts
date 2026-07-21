import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  isFetchableMerchantDataSource,
  merchantDataSourceFetchUrl,
  merchantDataSourcesUrl,
  merchantProductSummary,
  merchantProductUrl,
} from "./google_merchant_api.ts";

Deno.test("Merchant API product names use the v1 base64url resource format", () => {
  const url = merchantProductUrl({
    accountId: "5635601285",
    contentLanguage: "es",
    feedLabel: "CL",
    offerId: "sku/with-special~characters",
  });

  assertStringIncludes(
    url,
    "https://merchantapi.googleapis.com/products/v1/accounts/5635601285/products/",
  );
  assertEquals(url.includes("shoppingcontent.googleapis.com"), false);
  assertEquals(url.includes("sku/with-special"), false);
});

Deno.test("Merchant API product summary derives Chile approval and issues", () => {
  assertEquals(
    merchantProductSummary({
      name: "accounts/1/products/example",
      productAttributes: {
        title: "Casco",
        link: "https://vinabike.cl/productos/casco",
      },
      productStatus: {
        destinationStatuses: [{
          reportingContext: "FREE_LISTINGS",
          approvedCountries: ["CL"],
        }],
        itemLevelIssues: [{ code: "example_warning" }],
      },
    }),
    {
      status: "approved",
      productId: "accounts/1/products/example",
      title: "Casco",
      link: "https://vinabike.cl/productos/casco",
      destinationStatuses: [{
        reportingContext: "FREE_LISTINGS",
        approvedCountries: ["CL"],
      }],
      itemLevelIssues: [{ code: "example_warning" }],
      issueCount: 1,
    },
  );
});

Deno.test("Merchant API refresh targets only URL-fetchable file data sources", () => {
  assertEquals(
    merchantDataSourcesUrl("5635601285"),
    "https://merchantapi.googleapis.com/datasources/v1/accounts/5635601285/dataSources",
  );
  assertEquals(
    merchantDataSourceFetchUrl("accounts/5635601285/dataSources/123"),
    "https://merchantapi.googleapis.com/datasources/v1/accounts/5635601285/dataSources/123:fetch",
  );
  assertEquals(
    isFetchableMerchantDataSource({
      fileInput: { fetchSettings: { fetchUri: "https://vinabike.cl/feed.xml" } },
    }),
    true,
  );
  assertEquals(isFetchableMerchantDataSource({ input: "API" }), false);
});
