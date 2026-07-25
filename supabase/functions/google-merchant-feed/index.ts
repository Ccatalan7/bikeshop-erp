// Supabase Edge Function: Google Merchant Center Product Feed
// Deploy with: scripts/supabase_cli.sh functions deploy google-merchant-feed --project-ref xzdvtzdqjeyqxnkqprtf
//
// Usage:
//   GET /google-merchant-feed?tenant=vinabike     (by subdomain)
//   GET /google-merchant-feed?domain=vinabike.cl  (by custom domain)

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  filterMerchantProductsByCheckoutTax,
  projectPublicCommerceProduct,
} from "../_shared/google_merchant_feed.ts";
import { publicProductUrl } from "../_shared/product_url.ts";
import { mergeCanonicalAvailableQuantities } from "../_shared/product_availability.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type MerchantProduct = {
  id: string;
  tax_rate?: unknown;
  name?: string | null;
  website_name?: string | null;
  sku?: string | null;
  description?: string | null;
  website_description?: string | null;
  website_merchant_title?: string | null;
  website_merchant_description?: string | null;
  website_merchant_brand?: string | null;
  website_merchant_gtin?: string | null;
  website_merchant_mpn?: string | null;
  website_google_product_category?: string | null;
  price: number;
  website_price?: number | null;
  price_currency?: string | null;
  stock_quantity?: number | null;
  inventory_qty?: number | null;
  track_stock?: boolean | null;
  is_set?: boolean | null;
  full_sets_available?: number | null;
  image_url?: string | null;
  image_url_optimized?: string | null;
  website_image_url?: string | null;
  website_image_url_optimized?: string | null;
  image_urls?: string[] | null;
  website_image_urls?: string[] | null;
  brand?: string | null;
  brand_id?: string | null;
  category_id?: string | null;
  category_name?: string | null;
  barcode?: string | null;
  gtin?: string | null;
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    const tenantSubdomain = url.searchParams.get("tenant");
    const customDomain = url.searchParams.get("domain");

    if (!tenantSubdomain && !customDomain) {
      return new Response(
        JSON.stringify({
          error: "Missing tenant parameter",
          usage: "Add ?tenant=your-subdomain or ?domain=your-domain.com",
        }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Create Supabase client with service role (bypasses RLS)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    );

    // Step 1: Resolve tenant ID from subdomain or custom domain
    let tenantQuery = supabase.from("tenants").select("id, shop_name, subdomain, custom_domain");

    if (tenantSubdomain) {
      tenantQuery = tenantQuery.eq("subdomain", tenantSubdomain);
    } else if (customDomain) {
      tenantQuery = tenantQuery.eq("custom_domain", customDomain);
    }

    const { data: tenant, error: tenantError } = await tenantQuery.single();

    if (tenantError || !tenant) {
      // Debug: log what we're looking for
      console.error("Tenant lookup failed:", {
        subdomain: tenantSubdomain,
        customDomain,
        error: tenantError?.message,
      });
      return new Response(
        JSON.stringify({
          error: "Tenant not found",
          debug: {
            searchedSubdomain: tenantSubdomain,
            searchedDomain: customDomain,
            dbError: tenantError?.message,
          },
        }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const tenantId = tenant.id;

    // Step 2: Get website settings for this tenant
    const { data: settings } = await supabase
      .from("website_settings")
      .select("key, value")
      .eq("tenant_id", tenantId);

    const settingsMap = new Map(
      (settings || []).map((s) => [s.key, s.value]),
    );

    // Build store URL from custom domain or subdomain
    let storeUrl: string;
    if (tenant.custom_domain) {
      storeUrl = `https://${tenant.custom_domain}`;
    } else if (tenant.subdomain) {
      // Use Firebase hosting pattern or configured URL
      storeUrl = settingsMap.get("store_url") || `https://${tenant.subdomain}.vinabike.cl`;
    } else {
      storeUrl = settingsMap.get("store_url") || "https://vinabike.cl";
    }

    const storeName = settingsMap.get("store_name") || tenant.shop_name || "Tienda";
    const storeDescription = settingsMap.get("store_description") ||
      `${storeName} - Bicicletas y accesorios`;

    // Step 3: Get all active, published products for this tenant that are enabled for Google Merchant
    const { data: products, error: productsError } = await supabase
      .from("products")
      .select(`
        id,
        name,
        website_name,
        sku,
        description,
        website_description,
        website_merchant_title,
        website_merchant_description,
        website_merchant_brand,
        website_merchant_gtin,
        website_merchant_mpn,
        website_google_product_category,
        price,
        website_price,
        price_currency,
        tax_rate,
        stock_quantity,
        inventory_qty,
        track_stock,
        is_set,
        image_url,
        image_url_optimized,
        website_image_url,
        website_image_url_optimized,
        image_urls,
        website_image_urls,
        brand,
        brand_id,
        category_id,
        category_name,
        barcode,
        gtin,
        is_active,
        is_published,
        show_on_website,
        is_google_merchant,
        lifecycle_status,
        product_type
      `)
      .eq("tenant_id", tenantId)
      .eq("is_active", true)
      .eq("is_published", true)
      .eq("show_on_website", true)
      .eq("is_google_merchant", true)
      .eq("lifecycle_status", "active")
      .eq("product_type", "product")
      .in("tax_rate", [0, 0.19, 19])
      .order("name");

    if (productsError) {
      console.error("Products error:", productsError);
      throw productsError;
    }

    // Step 4: Get brand names for products with brand_id
    const brandIds = [...new Set(products?.filter((p) => p.brand_id).map((p) => p.brand_id))];
    let brandsMap = new Map<string, string>();

    if (brandIds.length > 0) {
      const { data: brands, error: brandsError } = await supabase
        .from("product_brands")
        .select("id, name, tenant_id, is_active")
        .in("id", brandIds)
        .eq("is_active", true)
        .or(`tenant_id.eq.${tenantId},tenant_id.is.null`);

      if (brandsError) {
        console.error("Canonical brands error:", brandsError);
      }
      brandsMap = new Map((brands || []).map((b) => [b.id, b.name]));
    }

    // Step 5: Get category paths for products with category_id
    const categoryIds = [
      ...new Set(products?.filter((p) => p.category_id).map((p) => p.category_id)),
    ];
    let categoriesMap = new Map<string, string>();

    if (categoryIds.length > 0) {
      const { data: categories, error: categoriesError } = await supabase
        .from("product_categories")
        .select("id, full_path, tenant_id, is_active")
        .in("id", categoryIds)
        .eq("tenant_id", tenantId)
        .eq("is_active", true);

      if (categoriesError) {
        console.error("Canonical categories error:", categoriesError);
      }
      categoriesMap = new Map((categories || []).map((c) => [c.id, c.full_path]));
    }

    // Step 6: Keep only products whose effective storefront data is eligible.
    const feedCandidates = filterMerchantProductsByCheckoutTax(
      (products || []) as MerchantProduct[],
    ).filter((product) => {
      const projection = commerceProjection(
        product,
        brandsMap,
        categoriesMap,
      );
      return projection.merchant_eligible;
    });

    // The public catalog RPC subtracts live online-order reservations and
    // enforces the same publication, image, category, and stock policy as the
    // landing pages. Products hidden by those rules stay out of Merchant.
    // When the editor's public stock policy keeps an out-of-stock landing page
    // visible, retain it with g:availability=out_of_stock as Google requires.
    let validProducts: MerchantProduct[] = [];
    if (feedCandidates.length > 0) {
      const { data: publicProducts, error: publicProductsError } = await supabase
        .rpc("get_public_products", {
          p_tenant_id: tenantId,
          p_product_ids: feedCandidates.map((product) => product.id),
          p_only_in_stock: true,
          p_sort_by: "name",
          p_limit: feedCandidates.length,
          p_offset: 0,
        });

      if (publicProductsError) {
        console.error("Public availability error:", publicProductsError);
        throw publicProductsError;
      }

      const availableIds = new Set(
        (publicProducts || []).map((product: { id: unknown }) => String(product.id)),
      );
      validProducts = mergeCanonicalAvailableQuantities(
        feedCandidates.filter((product) => availableIds.has(product.id)),
        (publicProducts || []).map(
          (product: { id: unknown; stock_quantity?: unknown }) => ({
            product_id: product.id,
            available_quantity: product.stock_quantity,
          }),
        ),
      ).filter((product) =>
        commerceProjection(product, brandsMap, categoriesMap).merchant_eligible
      );
    }

    // Step 7: Generate XML feed
    const feed = `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:g="http://base.google.com/ns/1.0">
  <channel>
    <title>${escapeXml(storeName)}</title>
    <link>${escapeXml(storeUrl)}</link>
    <description>${escapeXml(storeDescription)}</description>
${validProducts.map((p) => generateProductItem(p, storeUrl, brandsMap, categoriesMap)).join("\n")}
  </channel>
</rss>`;

    return new Response(feed, {
      headers: {
        ...corsHeaders,
        "Content-Type": "application/xml; charset=utf-8",
        "Cache-Control": "public, max-age=3600", // Cache for 1 hour
      },
    });
  } catch (error) {
    console.error("Error generating feed:", error);
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : String(error),
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  }
});

function generateProductItem(
  product: MerchantProduct,
  storeUrl: string,
  brandsMap: Map<string, string>,
  categoriesMap: Map<string, string>,
): string {
  const productUrl = publicProductUrl(storeUrl, product);
  const projection = commerceProjection(product, brandsMap, categoriesMap);
  if (!projection.merchant_eligible) {
    throw new Error(
      `Merchant product ${product.id} is ineligible: ${projection.merchant_issues.join(",")}`,
    );
  }

  const images = projection.image_urls;
  const imageUrl = images[0];
  const additionalImages = images.slice(1, 10);

  // Price with currency (default CLP)
  const priceValue = Number.isInteger(projection.price)
    ? projection.price.toFixed(0)
    : projection.price.toFixed(2);
  const price = `${priceValue} ${projection.currency}`;

  // Build item XML
  let itemXml = `    <item>
      <g:id>${escapeXml(projection.id)}</g:id>
      <g:title>${escapeXml(projection.title)}</g:title>
      <g:description>${escapeXml(projection.description)}</g:description>
      <g:link>${escapeXml(productUrl)}</g:link>
      <g:image_link>${escapeXml(imageUrl)}</g:image_link>`;

  // Add additional images
  for (const img of additionalImages) {
    itemXml += `\n      <g:additional_image_link>${escapeXml(img)}</g:additional_image_link>`;
  }

  itemXml += `
      <g:availability>${projection.availability}</g:availability>
      <g:price>${price}</g:price>
      <g:brand>${escapeXml(projection.brand)}</g:brand>
      <g:condition>new</g:condition>`;

  // Add GTIN if available (preferred by Google)
  if (projection.gtin) {
    itemXml += `\n      <g:gtin>${escapeXml(projection.gtin)}</g:gtin>`;
  }

  // Add only an explicitly recorded manufacturer part number.
  if (projection.mpn) {
    itemXml += `\n      <g:mpn>${escapeXml(projection.mpn)}</g:mpn>`;
  }

  // Add category path as product_type (merchant's own category)
  if (projection.category_path) {
    itemXml += `\n      <g:product_type>${escapeXml(projection.category_path)}</g:product_type>`;
  }

  // Let Google categorize automatically unless staff recorded an exact
  // taxonomy value. One bicycle-parts fallback is not correct for every item.
  if (projection.google_product_category) {
    itemXml += `\n      <g:google_product_category>${
      escapeXml(projection.google_product_category)
    }</g:google_product_category>`;
  }

  itemXml += `\n    </item>`;

  return itemXml;
}

function escapeXml(unsafe: string | null | undefined): string {
  if (!unsafe) return "";

  return String(unsafe)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

function resolveMerchantBrand(
  product: MerchantProduct,
  brandsMap: Map<string, string>,
): string {
  const explicit = firstNonEmpty(product.website_merchant_brand);
  if (explicit) return explicit;
  if (product.brand_id && brandsMap.has(product.brand_id)) {
    return firstNonEmpty(brandsMap.get(product.brand_id));
  }
  return firstNonEmpty(product.brand);
}

function commerceProjection(
  product: MerchantProduct,
  brandsMap: Map<string, string>,
  categoriesMap: Map<string, string>,
) {
  return projectPublicCommerceProduct(product, {
    resolvedBrand: resolveMerchantBrand(product, brandsMap),
    categoryPath: product.category_id ? categoriesMap.get(product.category_id) : undefined,
  });
}

function firstNonEmpty(...values: Array<string | null | undefined>): string {
  for (const value of values) {
    const text = String(value ?? "").trim();
    if (text.length > 0) return text;
  }
  return "";
}
