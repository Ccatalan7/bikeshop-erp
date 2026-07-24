import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { hasSupportedEcommerceTaxRate } from "../_shared/ecommerce_tax.ts";
import { projectPublicCommerceProduct } from "../_shared/google_merchant_feed.ts";
import {
  mergeCanonicalAvailableQuantities,
  resolveAvailableProductQuantity,
} from "../_shared/product_availability.ts";
import {
  isFetchableMerchantDataSource,
  merchantDataSourceFetchUrl,
  merchantDataSourcesUrl,
  merchantProductSummary,
  merchantProductUrl,
} from "../_shared/google_merchant_api.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const merchantScope = "https://www.googleapis.com/auth/content";
const searchConsoleIntegrationKey = "search_console";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Use POST" }, 405);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const action = cleanText(body.action || "inspect");
    const productUrl = cleanText(body.productUrl);
    const offerId = cleanText(body.offerId || body.productId);
    const siteUrl = Deno.env.get("GOOGLE_SEARCH_CONSOLE_SITE_URL") || "sc-domain:vinabike.cl";
    const sitemapUrl = cleanText(body.sitemapUrl) || "https://vinabike.cl/sitemap.xml";

    if (action === "submit_sitemap") {
      return jsonResponse(await submitSearchConsoleSitemap({ siteUrl, sitemapUrl }));
    }

    if (action === "refresh_merchant_feed") {
      return jsonResponse(await refreshMerchantFeeds());
    }

    if (!productUrl) {
      return jsonResponse({ error: "Missing productUrl" }, 400);
    }

    const requiredSecrets = [
      "GOOGLE_SEARCH_CONSOLE_SITE_URL",
      "GOOGLE_SERVICE_ACCOUNT_EMAIL",
      "GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY",
      "GOOGLE_MERCHANT_ACCOUNT_ID",
    ];

    const email = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL") || "";
    const privateKey = normalizePrivateKey(
      Deno.env.get("GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY") || "",
    );
    const merchantAccountId = Deno.env.get("GOOGLE_MERCHANT_ACCOUNT_ID") || "";

    const hasServiceAccount = Boolean(email && privateKey);
    const feedEligibility = offerId ? await getMerchantFeedEligibility(offerId) : null;

    const [searchConsole, searchConsoleSitemap, merchant] = await Promise.all([
      inspectSearchConsole({ siteUrl, productUrl }),
      inspectSearchConsoleSitemap({ siteUrl, sitemapUrl }),
      hasServiceAccount && merchantAccountId && offerId
        ? inspectMerchant({
          email,
          privateKey,
          merchantAccountId,
          offerId,
          feedEligibility,
        })
        : Promise.resolve({
          configured: false,
          feedEligibility,
          requiredSecrets: [
            ...(hasServiceAccount ? [] : [
              "GOOGLE_SERVICE_ACCOUNT_EMAIL",
              "GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY",
            ]),
            ...(merchantAccountId ? [] : ["GOOGLE_MERCHANT_ACCOUNT_ID"]),
          ],
        }),
    ]);

    return jsonResponse({
      ok: true,
      generatedAt: new Date().toISOString(),
      productUrl,
      offerId,
      searchConsole,
      searchConsoleSitemap,
      merchant,
      setup: {
        requiredSecrets,
        notes: [
          "Add the service account to Search Console with full access to vinabike.cl.",
          "Add the same service account to Merchant Center with product read access.",
          "User OAuth is only a fallback when no service-account path is configured.",
        ],
      },
    });
  } catch (error) {
    console.error("google-product-diagnostics error", error);
    return jsonResponse({ error: errorMessage(error) }, 500);
  }
});

async function inspectSearchConsole(args: {
  siteUrl: string;
  productUrl: string;
}) {
  try {
    const tokenResult = await searchConsoleAccessToken();
    if (!tokenResult.ok) {
      return {
        configured: false,
        connectRequired: true,
        reconnectRequired: tokenResult.reconnectRequired === true,
        error: tokenResult.error,
        requiredSecrets: tokenResult.requiredSecrets || [],
      };
    }

    const response = await fetch(
      "https://searchconsole.googleapis.com/v1/urlInspection/index:inspect",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${tokenResult.accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          inspectionUrl: args.productUrl,
          siteUrl: args.siteUrl,
          languageCode: "es-CL",
        }),
      },
    );

    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const visibleSites = response.status === 403
        ? await listSearchConsoleSites(tokenResult.accessToken)
        : null;
      const permissionDenied = response.status === 403;
      const usesServiceAccount = tokenResult.source === "service_account";

      return {
        configured: true,
        ok: false,
        status: response.status,
        errorCode: payload?.error?.status || payload?.error?.code || null,
        error: permissionDenied
          ? usesServiceAccount
            ? `Agrega la cuenta técnica ${tokenResult.serviceAccountEmail} como usuario con acceso completo a ${args.siteUrl}.`
            : "La cuenta Google conectada no tiene acceso a sc-domain:vinabike.cl. Reconecta Search Console usando una cuenta propietaria o con acceso completo."
          : payload?.error?.message || JSON.stringify(payload),
        googleError: payload?.error?.message || null,
        authSource: tokenResult.source,
        serviceAccountEmail: tokenResult.serviceAccountEmail || null,
        grantServiceAccountRequired: permissionDenied && usesServiceAccount,
        connectRequired: permissionDenied && !usesServiceAccount,
        reconnectRequired: permissionDenied && !usesServiceAccount,
        searchedSiteUrl: args.siteUrl,
        availableSites: visibleSites?.sites || [],
        availableSitesError: visibleSites?.error || null,
      };
    }

    const indexStatus = payload?.inspectionResult?.indexStatusResult || {};
    const richResults = payload?.inspectionResult?.richResultsResult || {};

    return {
      configured: true,
      ok: true,
      verdict: indexStatus.verdict,
      coverageState: indexStatus.coverageState,
      robotsTxtState: indexStatus.robotsTxtState,
      indexingState: indexStatus.indexingState,
      pageFetchState: indexStatus.pageFetchState,
      lastCrawlTime: indexStatus.lastCrawlTime,
      googleCanonical: indexStatus.googleCanonical,
      userCanonical: indexStatus.userCanonical,
      canonicalMatches: canonicalUrlKey(indexStatus.userCanonical) ===
          canonicalUrlKey(args.productUrl) &&
        (!cleanText(indexStatus.googleCanonical) ||
          canonicalUrlKey(indexStatus.googleCanonical) ===
            canonicalUrlKey(args.productUrl)),
      authSource: tokenResult.source,
      serviceAccountEmail: tokenResult.serviceAccountEmail || null,
      sitemap: indexStatus.sitemap,
      richResultsVerdict: richResults.verdict,
      raw: payload,
    };
  } catch (error) {
    return {
      configured: true,
      ok: false,
      error: errorMessage(error),
    };
  }
}

async function inspectSearchConsoleSitemap(args: {
  siteUrl: string;
  sitemapUrl: string;
}) {
  try {
    const tokenResult = await searchConsoleAccessToken();
    if (!tokenResult.ok) {
      return {
        configured: false,
        connectRequired: true,
        reconnectRequired: tokenResult.reconnectRequired === true,
        error: tokenResult.error,
      };
    }
    const response = await fetch(
      `https://www.googleapis.com/webmasters/v3/sites/${encodeURIComponent(args.siteUrl)}/sitemaps`,
      {
        headers: {
          Authorization: `Bearer ${tokenResult.accessToken}`,
          Accept: "application/json",
        },
      },
    );
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      const permissionDenied = response.status === 403;
      const usesServiceAccount = tokenResult.source === "service_account";
      return {
        configured: true,
        ok: false,
        status: response.status,
        error: permissionDenied
          ? usesServiceAccount
            ? `Agrega la cuenta técnica ${tokenResult.serviceAccountEmail} como usuario con acceso completo a ${args.siteUrl}.`
            : "La cuenta Google conectada no tiene acceso al sitemap de sc-domain:vinabike.cl. Reconecta Search Console usando una cuenta propietaria o con acceso completo."
          : payload?.error?.message || JSON.stringify(payload),
        googleError: payload?.error?.message || null,
        authSource: tokenResult.source,
        serviceAccountEmail: tokenResult.serviceAccountEmail || null,
        grantServiceAccountRequired: permissionDenied && usesServiceAccount,
        connectRequired: permissionDenied && !usesServiceAccount,
        reconnectRequired: permissionDenied && !usesServiceAccount,
      };
    }
    const sitemaps = Array.isArray(payload?.sitemap) ? payload.sitemap : [];
    const sitemap = sitemaps.find(
      (entry: Record<string, unknown>) => cleanText(entry?.path) === args.sitemapUrl,
    );
    return {
      configured: true,
      ok: Boolean(sitemap),
      submitted: Boolean(sitemap),
      sitemapUrl: args.sitemapUrl,
      lastSubmitted: sitemap?.lastSubmitted || null,
      lastDownloaded: sitemap?.lastDownloaded || null,
      isPending: sitemap?.isPending ?? null,
      warnings: sitemap?.warnings ?? null,
      errors: sitemap?.errors ?? null,
      authSource: tokenResult.source,
      serviceAccountEmail: tokenResult.serviceAccountEmail || null,
      raw: sitemap || null,
    };
  } catch (error) {
    return {
      configured: true,
      ok: false,
      error: errorMessage(error),
    };
  }
}

async function submitSearchConsoleSitemap(args: {
  siteUrl: string;
  sitemapUrl: string;
}) {
  try {
    const tokenResult = await searchConsoleAccessToken({ requireWrite: true });
    if (!tokenResult.ok) {
      return {
        ok: false,
        configured: false,
        connectRequired: true,
        reconnectRequired: tokenResult.reconnectRequired === true,
        error: tokenResult.error,
      };
    }
    if (
      !tokenResult.scope
        .split(/\s+/)
        .includes("https://www.googleapis.com/auth/webmasters")
    ) {
      return {
        ok: false,
        configured: true,
        reconnectRequired: true,
        error: "Reconecta Search Console una vez para autorizar el envío del sitemap.",
        currentScope: tokenResult.scope,
      };
    }

    const response = await fetch(
      `https://www.googleapis.com/webmasters/v3/sites/${
        encodeURIComponent(args.siteUrl)
      }/sitemaps/${encodeURIComponent(args.sitemapUrl)}`,
      {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${tokenResult.accessToken}`,
        },
      },
    );
    const payload = await response.text();
    const permissionDenied = !response.ok && response.status === 403;
    const usesServiceAccount = tokenResult.source === "service_account";
    return {
      ok: response.ok,
      configured: true,
      siteUrl: args.siteUrl,
      sitemapUrl: args.sitemapUrl,
      status: response.status,
      error: response.ok
        ? null
        : permissionDenied
        ? usesServiceAccount
          ? `Agrega la cuenta técnica ${tokenResult.serviceAccountEmail} como usuario con acceso completo a ${args.siteUrl}.`
          : "La cuenta Google conectada no puede enviar el sitemap de vinabike.cl. Reconecta Search Console usando una cuenta propietaria o con acceso completo."
        : payload,
      googleError: response.ok ? null : payload,
      authSource: tokenResult.source,
      serviceAccountEmail: tokenResult.serviceAccountEmail || null,
      grantServiceAccountRequired: permissionDenied && usesServiceAccount,
      connectRequired: permissionDenied && !usesServiceAccount,
      reconnectRequired: permissionDenied && !usesServiceAccount,
    };
  } catch (error) {
    return {
      ok: false,
      configured: false,
      reconnectRequired: true,
      error: errorMessage(error),
    };
  }
}

async function getMerchantFeedEligibility(offerId: string) {
  if (!isUuid(offerId)) {
    return {
      known: false,
      eligible: false,
      reasons: [
        "El offer id no es un UUID de producto local, así que no se pudo validar contra el feed ERP.",
      ],
    };
  }

  const client = adminClient();
  const { data, error } = await client
    .from("products")
    .select(
      "id, tenant_id, name, website_name, website_merchant_title, sku, description, website_description, website_merchant_description, is_active, is_published, show_on_website, is_google_merchant, lifecycle_status, product_type, price, website_price, price_currency, stock_quantity, inventory_qty, track_stock, is_set, tax_rate, image_url, image_url_optimized, website_image_url, website_image_url_optimized, image_urls, website_image_urls, brand_id, brand, website_merchant_brand, website_merchant_gtin, gtin, barcode, website_merchant_mpn, category_id, website_google_product_category",
    )
    .eq("id", offerId)
    .maybeSingle();

  if (error) {
    return {
      known: false,
      eligible: false,
      reasons: ["No se pudo revisar si el producto entra al feed Merchant."],
      error: error.message,
    };
  }

  if (!data) {
    return {
      known: true,
      eligible: false,
      reasons: ["El producto no existe en la base local."],
    };
  }

  const { data: availabilityRows, error: availabilityError } = await client
    .rpc("get_product_available_quantities", {
      p_tenant_id: data.tenant_id,
      p_product_ids: [data.id],
    });
  const canonicalProduct = mergeCanonicalAvailableQuantities(
    [data],
    (availabilityRows || []) as unknown as Array<Record<string, unknown>>,
  )[0];
  const { data: publicRows, error: publicCatalogError } = await client.rpc(
    "get_public_products",
    {
      p_tenant_id: data.tenant_id,
      p_product_ids: [data.id],
      p_only_in_stock: true,
      p_sort_by: "name",
      p_limit: 1,
      p_offset: 0,
    },
  );

  const reasons: string[] = [];
  if (availabilityError) {
    reasons.push("No se pudo calcular la disponibilidad vendible del producto.");
  }
  if (publicCatalogError) {
    reasons.push(
      "No se pudo verificar la misma regla pública que usa la landing del producto.",
    );
  } else if (
    !(publicRows || []).some((row: { id?: unknown }) => cleanText(row.id) === cleanText(data.id))
  ) {
    reasons.push(
      "Las reglas actuales del catálogo web no mantienen una landing pública para este producto.",
    );
  }
  if (data.is_active !== true) reasons.push("El producto no esta activo.");
  if (data.is_published !== true) {
    reasons.push("El producto no esta publicado en la tienda online.");
  }
  if (data.show_on_website !== true) {
    reasons.push("El producto no esta incluido en el catalogo web.");
  }
  if (data.is_google_merchant !== true) {
    reasons.push("Google Merchant esta desactivado para este producto.");
  }
  if (data.lifecycle_status !== "active") {
    reasons.push(
      `El ciclo de vida es ${cleanText(data.lifecycle_status) || "desconocido"}, no active.`,
    );
  }
  if (data.product_type !== "product") {
    reasons.push("Solo los productos fisicos entran al feed Merchant.");
  }
  if (!hasSupportedEcommerceTaxRate(data.tax_rate)) {
    reasons.push("La clasificación tributaria debe ser exenta (0) o afecta a IVA (19).");
  }
  let linkedBrand = "";
  if (cleanText(data.brand_id)) {
    const { data: brandRow } = await client
      .from("product_brands")
      .select("name, tenant_id, is_active")
      .eq("id", data.brand_id)
      .eq("is_active", true)
      .or(`tenant_id.eq.${data.tenant_id},tenant_id.is.null`)
      .maybeSingle();
    linkedBrand = cleanText(brandRow?.name);
  }
  const commerce = projectPublicCommerceProduct(canonicalProduct, {
    resolvedBrand: linkedBrand,
  });
  const issueMessages: Record<string, string> = {
    missing_identity: "El producto no tiene una identidad local válida.",
    missing_title: "El producto necesita un título público.",
    missing_description: "El producto necesita una descripción pública.",
    invalid_price: "El precio efectivo de la tienda debe ser mayor a 0.",
    missing_image: "El producto necesita una imagen pública HTTP(S).",
    missing_brand:
      "El producto necesita una marca de fabricante verificable; origen, marketplace o Genérico no sirven como marca.",
    missing_product_identifiers:
      "El producto necesita un GTIN válido o la combinación de marca y MPN del fabricante.",
  };
  reasons.push(
    ...commerce.merchant_issues.map((issue) =>
      issueMessages[issue] || `El producto no cumple la regla Merchant: ${issue}.`
    ),
  );

  const currency = commerce.currency;
  if (currency !== "CLP") {
    reasons.push("La moneda de la tienda para Chile debe ser CLP.");
  }
  const availableQuantity = resolveAvailableProductQuantity(canonicalProduct);
  const hasPublicImage = commerce.image_urls.length > 0;
  const hasExplicitBrand = !commerce.merchant_issues.includes("missing_brand");

  return {
    known: true,
    eligible: reasons.length === 0,
    reasons,
    product: {
      id: data.id,
      name: commerce.title,
      isActive: data.is_active === true,
      isPublished: data.is_published === true,
      showOnWebsite: data.show_on_website === true,
      isGoogleMerchant: data.is_google_merchant === true,
      lifecycleStatus: data.lifecycle_status,
      productType: data.product_type,
      price: commerce.price,
      currency,
      stockQuantity: availableQuantity,
      hasPublicImage,
      hasExplicitBrand,
      merchantBrand: commerce.brand || null,
      taxRate: data.tax_rate,
    },
  };
}

async function listSearchConsoleSites(accessToken: string): Promise<{
  sites: Array<{ siteUrl: string; permissionLevel: string }>;
  error?: string | null;
}> {
  const response = await fetch("https://www.googleapis.com/webmasters/v3/sites", {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      Accept: "application/json",
    },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    return {
      sites: [],
      error: payload?.error?.message || JSON.stringify(payload),
    };
  }

  const siteEntry = Array.isArray(payload?.siteEntry) ? payload.siteEntry : [];
  return {
    sites: siteEntry
      .map((site: Record<string, unknown>) => ({
        siteUrl: cleanText(site?.siteUrl),
        permissionLevel: cleanText(site?.permissionLevel),
      }))
      .filter((site: { siteUrl: string }) => site.siteUrl.length > 0),
    error: null,
  };
}

async function searchConsoleOAuthToken(): Promise<
  {
    ok: true;
    accessToken: string;
    scope: string;
  } | {
    ok: false;
    error: string;
    requiredSecrets?: string[];
    reconnectRequired?: boolean;
  }
> {
  const clientId = Deno.env.get("GOOGLE_SEARCH_CONSOLE_CLIENT_ID") || "";
  const clientSecret = Deno.env.get("GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET") || "";
  if (!clientId || !clientSecret) {
    return {
      ok: false,
      error: "Search Console OAuth is not configured.",
      requiredSecrets: [
        ...(clientId ? [] : ["GOOGLE_SEARCH_CONSOLE_CLIENT_ID"]),
        ...(clientSecret ? [] : ["GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET"]),
      ],
    };
  }

  const supabase = adminClient();
  const { data, error } = await supabase
    .from("google_oauth_connections")
    .select("access_token, refresh_token, expires_at, scope")
    .eq("integration_key", searchConsoleIntegrationKey)
    .maybeSingle();

  if (error) throw error;
  if (!data) {
    return {
      ok: false,
      error: "Search Console is not connected yet.",
    };
  }

  const expiresAt = data.expires_at ? new Date(data.expires_at).getTime() : 0;
  if (data.access_token && expiresAt > Date.now() + 120000) {
    return {
      ok: true,
      accessToken: data.access_token,
      scope: cleanText(data.scope),
    };
  }

  if (!data.refresh_token) {
    return {
      ok: false,
      error: "Search Console needs to be reconnected to refresh access.",
    };
  }

  let refreshed;
  try {
    refreshed = await refreshGoogleOAuthToken({
      clientId,
      clientSecret,
      refreshToken: data.refresh_token,
    });
  } catch (_) {
    return {
      ok: false,
      reconnectRequired: true,
      error: "La autorización de Search Console expiró. Reconecta Google una vez para continuar.",
    };
  }
  const expiresAtDate = new Date(
    Date.now() + Number(refreshed.expires_in || 3600) * 1000,
  );

  const { error: updateError } = await supabase
    .from("google_oauth_connections")
    .update({
      access_token: refreshed.access_token,
      token_type: refreshed.token_type || "Bearer",
      scope: refreshed.scope || data.scope || null,
      expires_at: expiresAtDate.toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("integration_key", searchConsoleIntegrationKey);

  if (updateError) throw updateError;
  return {
    ok: true,
    accessToken: refreshed.access_token,
    scope: cleanText(refreshed.scope || data.scope),
  };
}

async function searchConsoleAccessToken({
  requireWrite = false,
}: {
  requireWrite?: boolean;
} = {}): Promise<
  {
    ok: true;
    accessToken: string;
    scope: string;
    source: "oauth" | "service_account";
    serviceAccountEmail?: string;
  } | {
    ok: false;
    error: string;
    requiredSecrets?: string[];
    reconnectRequired?: boolean;
  }
> {
  const email = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL") || "";
  const privateKey = normalizePrivateKey(
    Deno.env.get("GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY") || "",
  );
  if (email && privateKey) {
    try {
      const accessToken = await serviceAccountAccessToken({
        email,
        privateKey,
        scopes: ["https://www.googleapis.com/auth/webmasters"],
      });
      return {
        ok: true,
        accessToken,
        scope: "https://www.googleapis.com/auth/webmasters",
        source: "service_account",
        serviceAccountEmail: email,
      };
    } catch (_) {
      // Fall through to the more actionable OAuth connection error.
    }
  }

  const oauth = await searchConsoleOAuthToken();
  if (oauth.ok && hasSearchConsoleScope(oauth.scope, requireWrite)) {
    return { ...oauth, source: "oauth" };
  }

  if (!oauth.ok) return oauth;
  return {
    ok: false,
    reconnectRequired: true,
    error: "Reconecta Search Console una vez para autorizar el envío del sitemap.",
  };
}

function hasSearchConsoleScope(scope: string, requireWrite: boolean) {
  const scopes = scope.split(/\s+/).filter(Boolean);
  if (scopes.includes("https://www.googleapis.com/auth/webmasters")) {
    return true;
  }
  return !requireWrite &&
    scopes.includes("https://www.googleapis.com/auth/webmasters.readonly");
}

async function refreshGoogleOAuthToken(args: {
  clientId: string;
  clientSecret: string;
  refreshToken: string;
}) {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: args.clientId,
      client_secret: args.clientSecret,
      refresh_token: args.refreshToken,
      grant_type: "refresh_token",
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload.access_token) {
    throw new Error(
      payload?.error_description || payload?.error || "Could not refresh Google OAuth token",
    );
  }
  return payload;
}

async function inspectMerchant(args: {
  email: string;
  privateKey: string;
  merchantAccountId: string;
  offerId: string;
  feedEligibility: Awaited<ReturnType<typeof getMerchantFeedEligibility>> | null;
}) {
  try {
    if (args.feedEligibility?.known && !args.feedEligibility.eligible) {
      return {
        configured: true,
        ok: false,
        status: "not_in_feed",
        error: `Este producto no se esta enviando al feed Merchant: ${
          args.feedEligibility.reasons.join(" ")
        }`,
        feedEligibility: args.feedEligibility,
      };
    }

    const token = await serviceAccountAccessToken({
      email: args.email,
      privateKey: args.privateKey,
      scopes: [merchantScope],
    });

    const attempts = [];
    for (const contentLanguage of ["es", "en"]) {
      const url = merchantProductUrl({
        accountId: args.merchantAccountId,
        contentLanguage,
        feedLabel: "CL",
        offerId: args.offerId,
      });
      const response = await fetch(
        url,
        {
          headers: {
            Authorization: `Bearer ${token}`,
            Accept: "application/json",
          },
        },
      );
      const payload = await response.json().catch(() => ({}));
      attempts.push({ contentLanguage, status: response.status, payload });
      if (response.status === 401 || response.status === 403) {
        const googleError = cleanText(payload?.error?.message);
        const registrationRequired = googleError.toLowerCase().includes(
          "not registered with the merchant account",
        );
        return {
          configured: true,
          ok: false,
          api: "merchant_v1",
          status: registrationRequired
            ? "merchant_api_registration_required"
            : "merchant_access_denied",
          registrationRequired,
          error: googleError ||
            "La cuenta tecnica de Google no tiene acceso a este Merchant Center. Agrega el service account como administrador en Merchant Center o corrige GOOGLE_MERCHANT_ACCOUNT_ID.",
          feedEligibility: args.feedEligibility,
          attempts,
        };
      }
      if (response.ok) {
        const summary = merchantProductSummary(payload);
        return {
          configured: true,
          ok: true,
          api: "merchant_v1",
          feedEligibility: args.feedEligibility,
          ...summary,
          raw: payload,
        };
      }
    }

    return {
      configured: true,
      ok: false,
      api: "merchant_v1",
      status: "not_found_or_not_ready",
      error: args.feedEligibility?.eligible
        ? "El producto cumple las reglas locales del feed, pero Merchant Center aun no lo encuentra. Fuerza una lectura del feed en Merchant Center o espera a que Google procese el item."
        : "Merchant product status was not found yet. It may still be processing, or the offer id/language/country differs.",
      feedEligibility: args.feedEligibility,
      attempts,
    };
  } catch (error) {
    return {
      configured: true,
      ok: false,
      api: "merchant_v1",
      error: errorMessage(error),
      feedEligibility: args.feedEligibility,
    };
  }
}

async function refreshMerchantFeeds() {
  const email = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL") || "";
  const privateKey = normalizePrivateKey(
    Deno.env.get("GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY") || "",
  );
  const merchantAccountId = Deno.env.get("GOOGLE_MERCHANT_ACCOUNT_ID") || "";
  if (!email || !privateKey || !merchantAccountId) {
    return {
      ok: false,
      configured: false,
      error: "Merchant feed refresh is not configured.",
    };
  }

  const token = await serviceAccountAccessToken({
    email,
    privateKey,
    scopes: [merchantScope],
  });
  const feeds = [];
  let pageToken = "";
  do {
    const listUrl = new URL(merchantDataSourcesUrl(merchantAccountId));
    if (pageToken) listUrl.searchParams.set("pageToken", pageToken);
    const listResponse = await fetch(listUrl, {
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: "application/json",
      },
    });
    const listPayload = await listResponse.json().catch(() => ({}));
    if (!listResponse.ok) {
      const googleError = cleanText(listPayload?.error?.message);
      const registrationRequired = googleError.toLowerCase().includes(
        "not registered with the merchant account",
      );
      return {
        ok: false,
        configured: true,
        api: "merchant_v1",
        status: registrationRequired ? "merchant_api_registration_required" : listResponse.status,
        registrationRequired,
        error: googleError || JSON.stringify(listPayload),
      };
    }
    if (Array.isArray(listPayload?.dataSources)) {
      feeds.push(...listPayload.dataSources);
    }
    pageToken = cleanText(listPayload?.nextPageToken);
  } while (pageToken);

  const fetchableFeeds = feeds.filter(isFetchableMerchantDataSource);
  const results = [];
  for (const feed of fetchableFeeds) {
    const name = cleanText(feed?.name);
    if (!name) continue;
    const response = await fetch(
      merchantDataSourceFetchUrl(name),
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: "{}",
      },
    );
    const payload = await response.json().catch(() => ({}));
    results.push({
      id: cleanText(feed?.dataSourceId),
      name,
      displayName: cleanText(feed?.displayName),
      ok: response.ok,
      status: response.status,
      error: response.ok ? null : payload?.error?.message || JSON.stringify(payload),
    });
  }

  return {
    ok: results.length > 0 && results.every((result) => result.ok),
    configured: true,
    api: "merchant_v1",
    feedCount: results.length,
    dataSourceCount: feeds.length,
    error: results.length === 0
      ? "Merchant API no encontro una fuente URL actualizable para este comercio."
      : null,
    results,
  };
}

async function serviceAccountAccessToken(args: {
  email: string;
  privateKey: string;
  scopes: string[];
}) {
  const now = Math.floor(Date.now() / 1000);
  const claim = {
    iss: args.email,
    scope: args.scopes.join(" "),
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const jwt = await signJwt({ claim, privateKey: args.privateKey });
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok || !payload.access_token) {
    throw new Error(
      payload?.error_description || payload?.error || "Could not get Google access token",
    );
  }
  return payload.access_token as string;
}

async function signJwt(args: {
  claim: Record<string, unknown>;
  privateKey: string;
}) {
  const encoder = new TextEncoder();
  const header = { alg: "RS256", typ: "JWT" };
  const signingInput = `${base64UrlJson(header)}.${base64UrlJson(args.claim)}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(args.privateKey),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(signingInput),
  );
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

function base64UrlJson(value: Record<string, unknown>) {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function base64Url(bytes: Uint8Array) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function pemToArrayBuffer(pem: string) {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function normalizePrivateKey(value: string) {
  return value.replace(/\\n/g, "\n").trim();
}

function adminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
}

function cleanText(value: unknown) {
  return String(value ?? "").trim();
}

function canonicalUrlKey(value: unknown) {
  const raw = cleanText(value);
  if (!raw) return "";
  try {
    const url = new URL(raw);
    const path = url.pathname === "/" ? "" : url.pathname.replace(/\/+$/g, "");
    return `${url.protocol}//${url.host}${path}${url.search}`;
  } catch (_) {
    return raw.replace(/\/+$/g, "");
  }
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function jsonResponse(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
