import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { publicProductUrl } from "../_shared/product_url.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const WHATSAPP_ACCESS_TOKEN = Deno.env.get("WHATSAPP_ACCESS_TOKEN") ?? "";
const META_ACCESS_TOKEN = Deno.env.get("META_ACCESS_TOKEN") ?? WHATSAPP_ACCESS_TOKEN;
const META_API_VERSION = Deno.env.get("META_API_VERSION") ??
  Deno.env.get("WHATSAPP_API_VERSION") ?? "v23.0";
const PRIMARY_META_CATALOG_ID = Deno.env.get("META_CATALOG_ID") ??
  Deno.env.get("WHATSAPP_CATALOG_ID") ?? "";

type JsonRecord = Record<string, unknown>;

// Honest lifecycle states. Meta accepting an upsert (returning a product id and
// visibility=published) does NOT mean the product is visible to customers in
// WhatsApp. Customer visibility is gated by the asynchronous per-product review
// field capability_to_review_status[WHATSAPP] == APPROVED. Until Meta approves,
// the product stays under_review and remains hidden from the catalog customers
// see in chat. See refreshProductReview() / fetchCatalogProductState().
type CatalogSyncStatus =
  | "pending"
  | "syncing"
  | "synced"
  | "under_review"
  | "customer_visible"
  | "rejected"
  | "removed"
  | "failed";

interface SyncRequest {
  productId?: string;
  product?: JsonRecord;
  operation?: string;
  // 'sync' (default) publishes/removes. 'refresh' only re-reads Meta's review
  // state for an already-uploaded product without re-uploading it.
  mode?: string;
}

function createAdminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
}

type AdminClient = ReturnType<typeof createAdminClient>;

async function updateSyncStatus(
  adminClient: AdminClient,
  productId: string,
  status: CatalogSyncStatus,
  options: {
    error?: string | null;
    metaProductId?: string | null;
    syncedUrl?: string | null;
    urlMatches?: boolean | null;
    verifiedAt?: string | null;
  } = {},
) {
  const values: JsonRecord = {
    whatsapp_catalog_sync_status: status,
    whatsapp_catalog_sync_error: options.error ?? null,
  };
  // Any state where Meta actually responded about the product is a successful
  // round-trip worth timestamping, even if the product is not customer-visible
  // yet (under_review) or was rejected.
  const reachedMeta = status === "synced" ||
    status === "removed" ||
    status === "under_review" ||
    status === "customer_visible" ||
    status === "rejected";
  if (reachedMeta) {
    values.whatsapp_catalog_synced_at = new Date().toISOString();
  }
  if (options.metaProductId !== undefined) {
    values.whatsapp_catalog_meta_product_id = options.metaProductId;
  }
  if (options.syncedUrl !== undefined) {
    values.whatsapp_catalog_synced_url = options.syncedUrl;
  }
  if (options.urlMatches !== undefined) {
    values.whatsapp_catalog_url_matches = options.urlMatches;
  }
  if (options.verifiedAt !== undefined) {
    values.whatsapp_catalog_verified_at = options.verifiedAt;
  }

  const { error } = await adminClient
    .from("products")
    .update(values)
    .eq("id", productId);

  if (error) {
    console.error("Could not persist WhatsApp catalog sync status", error);
  }
}

async function logSyncEvent(
  adminClient: AdminClient,
  event: {
    tenantId?: string;
    productId?: string;
    catalogId?: string;
    retailerId?: string;
    metaProductId?: string | null;
    operation: string;
    status: "started" | "success" | "failed" | "skipped" | "partial";
    attemptCount?: number;
    httpStatus?: number | null;
    error?: string | null;
    requestPayload?: JsonRecord;
    responsePayload?: unknown;
  },
) {
  try {
    const { error } = await adminClient
      .from("product_catalog_sync_events")
      .insert({
        tenant_id: event.tenantId || null,
        product_id: event.productId || null,
        catalog_id: event.catalogId || null,
        retailer_id: event.retailerId || null,
        meta_product_id: event.metaProductId ?? null,
        operation: event.operation,
        status: event.status,
        attempt_count: event.attemptCount ?? null,
        http_status: event.httpStatus ?? null,
        error: event.error ?? null,
        request_payload: event.requestPayload ?? {},
        response_payload: sanitizeLogPayload(event.responsePayload),
      });

    if (error) {
      console.error("Could not persist Meta catalog sync event", error);
    }
  } catch (error) {
    console.error("Could not persist Meta catalog sync event", error);
  }
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function stringValue(value: unknown) {
  if (typeof value !== "string") return "";
  return value.trim();
}

function firstNonEmpty(values: unknown[]) {
  for (const value of values) {
    const text = stringValue(value);
    if (text) return text;
  }
  return "";
}

function numberValue(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string") {
    const parsed = Number(value.replace(",", "."));
    if (Number.isFinite(parsed)) return parsed;
  }
  return 0;
}

function arrayValue(value: unknown) {
  return Array.isArray(value) ? value : [];
}

function recordValue(value: unknown): JsonRecord {
  return value && typeof value === "object" ? value as JsonRecord : {};
}

function sanitizeLogPayload(value: unknown): unknown {
  if (value === null || value === undefined) return null;
  if (Array.isArray(value)) {
    return value.slice(0, 50).map(sanitizeLogPayload);
  }
  if (typeof value !== "object") return value;

  const source = value as JsonRecord;
  const output: JsonRecord = {};
  for (const [key, entry] of Object.entries(source)) {
    if (/token|authorization|apikey|secret/i.test(key)) continue;
    output[key] = sanitizeLogPayload(entry);
  }
  return output;
}

function decodeBase64Url(value: string) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized.padEnd(
    normalized.length + ((4 - (normalized.length % 4)) % 4),
    "=",
  );
  return atob(padded);
}

function resolveJwtPayload(authHeader: string) {
  const [scheme, token] = authHeader.split(/\s+/);
  if (scheme?.toLowerCase() !== "bearer" || !token) return null;

  const payloadPart = token.split(".")[1];
  if (!payloadPart) return null;

  try {
    return JSON.parse(decodeBase64Url(payloadPart)) as JsonRecord;
  } catch (_) {
    return null;
  }
}

async function graphRequest(path: string, options: RequestInit = {}) {
  let lastResult: {
    ok: boolean;
    status: number;
    payload: unknown;
    attempts: number;
  } | null = null;
  let lastError: unknown;

  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const response = await fetch(
        `https://graph.facebook.com/${META_API_VERSION}/${path}`,
        {
          ...options,
          headers: {
            Authorization: `Bearer ${META_ACCESS_TOKEN}`,
            ...(options.headers ?? {}),
          },
        },
      );

      const text = await response.text();
      let payload: unknown = text;
      try {
        payload = text ? JSON.parse(text) : null;
      } catch (_) {
        // Keep non-JSON Meta responses available for diagnostics.
      }

      lastResult = {
        ok: response.ok,
        status: response.status,
        payload,
        attempts: attempt,
      };
      if (response.ok || !isRetryableGraphResult(lastResult)) {
        return lastResult;
      }
    } catch (error) {
      lastError = error;
      lastResult = {
        ok: false,
        status: 0,
        payload: { error: { message: error instanceof Error ? error.message : String(error) } },
        attempts: attempt,
      };
    }

    if (attempt < 3) {
      await delay(500 * attempt * attempt);
    }
  }

  if (lastResult) return lastResult;
  throw lastError;
}

function isRetryableGraphResult(result: { status: number; payload: unknown }) {
  if ([0, 408, 409, 425, 429].includes(result.status)) return true;
  if (result.status >= 500 && result.status <= 599) return true;

  const error = recordValue(recordValue(result.payload).error);
  const code = Number(error.code);
  return [1, 2, 4, 17, 32, 613].includes(code);
}

function delay(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function resolveCallerTenant(
  adminClient: AdminClient,
  authHeader: string,
  productTenantId: string,
) {
  const bearer = authHeader.replace(/^Bearer\s+/i, "");
  if (bearer === SUPABASE_SERVICE_ROLE_KEY) return productTenantId;

  // The Edge Function gateway verifies the JWT before this code runs.
  const jwtPayload = resolveJwtPayload(authHeader);
  if (stringValue(jwtPayload?.role) === "service_role") return productTenantId;

  const userId = stringValue(jwtPayload?.sub);
  if (!userId) return null;

  const { data: profile, error } = await adminClient
    .from("user_profiles")
    .select("tenant_id, is_active")
    .eq("user_id", userId)
    .maybeSingle();

  const profileRecord = profile as unknown as JsonRecord | null;
  if (error || !profileRecord || profileRecord.is_active === false) return null;
  return stringValue(profileRecord.tenant_id) || null;
}

async function resolveCatalogId(
  adminClient: AdminClient,
  tenantId: string,
) {
  // Meta Commerce Catalog is the canonical product sync target for WhatsApp
  // and Meta catalog ads. Keep it explicit so WABA auto-discovery cannot
  // drift into an inaccessible or secondary catalog.
  if (PRIMARY_META_CATALOG_ID) return PRIMARY_META_CATALOG_ID;

  const { data: channel, error } = await adminClient
    .from("whatsapp_channels")
    .select("business_account_id")
    .eq("tenant_id", tenantId)
    .eq("is_active", true)
    .limit(1)
    .maybeSingle();

  if (error) throw error;
  const channelRecord = channel as unknown as JsonRecord | null;
  const businessAccountId = stringValue(channelRecord?.business_account_id);
  if (!businessAccountId) {
    throw new Error("No active WhatsApp business account is configured for this tenant");
  }

  const result = await graphRequest(
    `${businessAccountId}/product_catalogs?fields=id,name,vertical,product_count&limit=20`,
  );
  if (!result.ok) {
    throw new Error(
      metaErrorMessage(result.payload, "Meta could not load the connected WhatsApp catalog"),
    );
  }

  const catalogs = arrayValue(recordValue(result.payload).data)
    .map(recordValue)
    .filter((catalog) => stringValue(catalog.id));

  if (catalogs.length === 0) {
    throw new Error("No product catalog is connected to the active WhatsApp business account");
  }
  if (catalogs.length > 1) {
    throw new Error(
      "Multiple WhatsApp product catalogs are connected; catalog selection is ambiguous",
    );
  }

  return stringValue(catalogs[0].id);
}

function buildCatalogProductPayload(product: JsonRecord) {
  const title = firstNonEmpty([
    product.whatsapp_catalog_title,
    product.website_name,
    product.name,
  ]);
  const description = firstNonEmpty([
    product.whatsapp_catalog_description,
    product.website_description,
    product.description,
  ]);
  const imageUrl = firstNonEmpty([
    product.website_image_url_optimized,
    product.website_image_url,
    product.image_url_optimized,
    product.image_url,
  ]);
  const price = numberValue(product.whatsapp_catalog_price) ||
    numberValue(product.website_price) ||
    numberValue(product.price);
  const stock = product.stock_quantity === null || product.stock_quantity === undefined
    ? numberValue(product.inventory_qty)
    : numberValue(product.stock_quantity);
  const retailerId = catalogRetailerId(product);

  return {
    retailer_id: retailerId,
    name: title,
    description,
    image_url: imageUrl,
    url: publicProductUrl("https://vinabike.cl", product),
    availability: stock > 0 ? "in stock" : "out of stock",
    condition: "new",
    currency: "CLP",
    price: Math.round(price * 100),
    quantity_to_sell_on_facebook: Math.max(0, Math.round(stock)),
    brand: firstNonEmpty([product.brand, "Vinabike"]),
    product_type: firstNonEmpty([product.category_name, "Bicicletas y accesorios"]),
    visibility: "published",
  };
}

function catalogRetailerId(product: JsonRecord) {
  return firstNonEmpty([product.sku, product.id]);
}

function legacyCatalogRetailerIds(product: JsonRecord) {
  const current = catalogRetailerId(product);
  return [stringValue(product.id)]
    .filter((id) => id && id !== current);
}

function allCatalogRetailerIds(product: JsonRecord) {
  return [catalogRetailerId(product), ...legacyCatalogRetailerIds(product)]
    .filter((id, index, values) => id && values.indexOf(id) === index);
}

function metaErrorMessage(payload: unknown, fallback: string) {
  const error = recordValue(recordValue(payload).error);
  return stringValue(error.message) || fallback;
}

// Maps Meta's WhatsApp review value to our honest lifecycle status.
// APPROVED is the only value that means the product is visible to customers.
function mapWhatsappReviewStatus(reviewValue: string): CatalogSyncStatus {
  switch (reviewValue.toUpperCase()) {
    case "APPROVED":
      return "customer_visible";
    case "REJECTED":
      return "rejected";
    default:
      // NO_REVIEW, PENDING, OUTDATED, or unknown -> still awaiting Meta review.
      return "under_review";
  }
}

// capability_to_review_status is an array of { key, value } entries. We only
// care about the WHATSAPP capability for customer visibility in chat.
function extractWhatsappReviewValue(payload: unknown): string {
  const capabilities = arrayValue(
    recordValue(payload).capability_to_review_status,
  ).map(recordValue);
  for (const capability of capabilities) {
    if (stringValue(capability.key) === "WHATSAPP") {
      return stringValue(capability.value);
    }
  }
  return "";
}

async function fetchCatalogProductState(metaProductId: string) {
  if (!metaProductId) {
    return { reviewValue: "", url: "" };
  }
  const result = await graphRequest(
    `${metaProductId}?fields=url,capability_to_review_status`,
  );
  if (!result.ok) {
    return { reviewValue: "", url: "" };
  }
  return {
    reviewValue: extractWhatsappReviewValue(result.payload),
    url: stringValue(recordValue(result.payload).url),
  };
}

async function upsertProduct(
  adminClient: AdminClient,
  catalogId: string,
  product: JsonRecord,
) {
  const payload = buildCatalogProductPayload(product);
  const tenantId = stringValue(product.tenant_id);
  const productId = stringValue(product.id);
  const missing = [
    payload.name.length >= 10 ? "" : "title",
    payload.description.length >= 20 ? "" : "description",
    payload.image_url ? "" : "image",
    payload.price > 0 ? "" : "price",
  ].filter(Boolean) as string[];

  if (missing.length > 0) {
    await updateSyncStatus(
      adminClient,
      productId,
      "failed",
      { error: `Faltan datos obligatorios: ${missing.join(", ")}` },
    );
    await logSyncEvent(adminClient, {
      tenantId,
      productId,
      catalogId,
      retailerId: payload.retailer_id,
      operation: "upsert",
      status: "skipped",
      error: `Faltan datos obligatorios: ${missing.join(", ")}`,
      requestPayload: { missing },
    });
    return jsonResponse({
      error: "Faltan datos obligatorios para publicar en WhatsApp",
      missing,
    }, 422);
  }

  const body = new URLSearchParams();
  for (const [key, value] of Object.entries(payload)) {
    body.set(key, String(value));
  }
  body.set("allow_upsert", "true");

  const result = await graphRequest(`${catalogId}/products`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  if (!result.ok) {
    const error = metaErrorMessage(result.payload, "Meta rejected the WhatsApp catalog product");
    await updateSyncStatus(
      adminClient,
      productId,
      "failed",
      { error },
    );
    await logSyncEvent(adminClient, {
      tenantId,
      productId,
      catalogId,
      retailerId: payload.retailer_id,
      operation: "upsert",
      status: "failed",
      attemptCount: result.attempts,
      httpStatus: result.status,
      error,
      requestPayload: { retailer_id: payload.retailer_id },
      responsePayload: result.payload,
    });
    return jsonResponse({
      error,
      details: result.payload,
    }, 502);
  }

  const metaProductId = stringValue(recordValue(result.payload).id) || null;
  // Meta accepted the upsert, but acceptance is not customer visibility. Read
  // back the WhatsApp review capability so the ERP reports the real state
  // instead of falsely claiming the product is live for customers.
  const metaState = await fetchCatalogProductState(metaProductId ?? "");
  const reviewValue = metaState.reviewValue;
  const storedUrl = metaState.url;
  const urlMatches = storedUrl ? storedUrl === payload.url : null;
  const syncStatus = metaProductId ? mapWhatsappReviewStatus(reviewValue) : "under_review";
  await updateSyncStatus(
    adminClient,
    productId,
    syncStatus,
    {
      metaProductId,
      syncedUrl: storedUrl || payload.url,
      urlMatches,
      verifiedAt: new Date().toISOString(),
    },
  );
  const legacyCleanup = await removeLegacyCatalogProducts(
    adminClient,
    catalogId,
    product,
    payload.retailer_id,
  );
  await logSyncEvent(adminClient, {
    tenantId,
    productId,
    catalogId,
    retailerId: payload.retailer_id,
    metaProductId,
    operation: "upsert",
    status: legacyCleanup.failed.length > 0 ? "partial" : "success",
    attemptCount: result.attempts,
    httpStatus: result.status,
    requestPayload: { retailer_id: payload.retailer_id },
    responsePayload: {
      metaProductId,
      syncStatus,
      whatsappReview: reviewValue || "NO_REVIEW",
      legacyCleanup,
    },
  });
  return jsonResponse({
    ok: true,
    action: "upserted",
    catalogId,
    productId: product.id,
    retailerId: payload.retailer_id,
    metaProductId,
    syncStatus,
    whatsappReview: reviewValue || "NO_REVIEW",
    expectedUrl: payload.url,
    storedUrl: storedUrl || null,
    urlMatches,
    legacyCleanup,
  });
}

async function findCatalogProduct(
  catalogId: string,
  retailerId: string,
  fields = "id,retailer_id",
) {
  let after = "";

  for (let page = 0; page < 100; page += 1) {
    const cursor = after ? `&after=${encodeURIComponent(after)}` : "";
    const result = await graphRequest(
      `${catalogId}/products?fields=${fields}&limit=100${cursor}`,
    );
    if (!result.ok) {
      throw new Error(metaErrorMessage(result.payload, "Meta could not inspect catalog products"));
    }

    const payload = recordValue(result.payload);
    for (const item of arrayValue(payload.data).map(recordValue)) {
      if (stringValue(item.retailer_id) === retailerId) return item;
    }

    const paging = recordValue(payload.paging);
    const cursors = recordValue(paging.cursors);
    after = stringValue(cursors.after);
    if (!stringValue(paging.next) || !after) break;
  }

  return null;
}

async function removeProduct(
  adminClient: AdminClient,
  catalogId: string,
  product: JsonRecord,
  options: { persistStatus?: boolean; operation?: string } = {},
) {
  const persistStatus = options.persistStatus ?? true;
  const operation = options.operation ?? "remove";
  const tenantId = stringValue(product.tenant_id);
  const productId = stringValue(product.id);
  const retailerIds = allCatalogRetailerIds(product);
  const catalogProducts = await findCatalogProductsForProduct(catalogId, product);

  if (catalogProducts.length === 0) {
    if (persistStatus) {
      await updateSyncStatus(
        adminClient,
        productId,
        "removed",
        {
          metaProductId: null,
          syncedUrl: null,
          urlMatches: null,
          verifiedAt: new Date().toISOString(),
        },
      );
    }
    await logSyncEvent(adminClient, {
      tenantId,
      productId,
      catalogId,
      retailerId: retailerIds[0],
      operation,
      status: "success",
      requestPayload: { retailerIds },
      responsePayload: { action: "already_absent" },
    });
    return jsonResponse({
      ok: true,
      action: "already_absent",
      catalogId,
      productId: product.id,
      retailerId: retailerIds[0],
    });
  }

  const deleted: JsonRecord[] = [];
  const failed: JsonRecord[] = [];
  for (const catalogProduct of catalogProducts) {
    const metaProductId = stringValue(catalogProduct.id);
    const result = await graphRequest(metaProductId, { method: "DELETE" });
    if (result.ok) {
      deleted.push({
        id: metaProductId,
        retailer_id: stringValue(catalogProduct.retailer_id),
        attempts: result.attempts,
      });
    } else {
      failed.push({
        id: metaProductId,
        retailer_id: stringValue(catalogProduct.retailer_id),
        status: result.status,
        error: metaErrorMessage(result.payload, "Meta rejected removing the catalog product"),
      });
    }
  }

  if (failed.length > 0) {
    const error = failed.map((item) => item.error).filter(Boolean).join("; ") ||
      "Meta rejected removing one or more catalog products";
    if (persistStatus) {
      await updateSyncStatus(
        adminClient,
        productId,
        "failed",
        { error },
      );
    }
    await logSyncEvent(adminClient, {
      tenantId,
      productId,
      catalogId,
      retailerId: retailerIds[0],
      operation,
      status: deleted.length > 0 ? "partial" : "failed",
      error,
      requestPayload: { retailerIds },
      responsePayload: { deleted, failed },
    });
    return jsonResponse({
      error,
      deleted,
      failed,
    }, 502);
  }

  if (persistStatus) {
    await updateSyncStatus(
      adminClient,
      productId,
      "removed",
      {
        metaProductId: null,
        syncedUrl: null,
        urlMatches: null,
        verifiedAt: new Date().toISOString(),
      },
    );
  }
  await logSyncEvent(adminClient, {
    tenantId,
    productId,
    catalogId,
    retailerId: retailerIds[0],
    operation,
    status: "success",
    requestPayload: { retailerIds },
    responsePayload: { deleted },
  });
  return jsonResponse({
    ok: true,
    action: "removed",
    catalogId,
    productId: product.id,
    retailerId: retailerIds[0],
    deleted,
  });
}

async function findCatalogProductsForProduct(
  catalogId: string,
  product: JsonRecord,
) {
  const products: JsonRecord[] = [];
  const seen = new Set<string>();
  const storedMetaProductId = stringValue(product.whatsapp_catalog_meta_product_id);
  if (storedMetaProductId) {
    const result = await graphRequest(
      `${storedMetaProductId}?fields=id,retailer_id`,
    );
    if (result.ok) {
      const record = recordValue(result.payload);
      const id = stringValue(record.id);
      if (id) {
        products.push(record);
        seen.add(id);
      }
    }
  }

  for (const retailerId of allCatalogRetailerIds(product)) {
    const catalogProduct = await findCatalogProduct(catalogId, retailerId);
    const metaProductId = stringValue(catalogProduct?.id);
    if (catalogProduct && metaProductId && !seen.has(metaProductId)) {
      products.push(catalogProduct);
      seen.add(metaProductId);
    }
  }

  return products;
}

async function removeLegacyCatalogProducts(
  adminClient: AdminClient,
  catalogId: string,
  product: JsonRecord,
  currentRetailerId: string,
) {
  const deleted: JsonRecord[] = [];
  const failed: JsonRecord[] = [];
  for (const retailerId of legacyCatalogRetailerIds(product)) {
    if (retailerId === currentRetailerId) continue;
    const catalogProduct = await findCatalogProduct(catalogId, retailerId);
    if (!catalogProduct) continue;

    const metaProductId = stringValue(catalogProduct.id);
    const result = await graphRequest(metaProductId, { method: "DELETE" });
    if (result.ok) {
      deleted.push({ id: metaProductId, retailer_id: retailerId });
    } else {
      failed.push({
        id: metaProductId,
        retailer_id: retailerId,
        status: result.status,
        error: metaErrorMessage(
          result.payload,
          "Meta rejected removing the legacy catalog product",
        ),
      });
    }
  }

  if (deleted.length > 0 || failed.length > 0) {
    await logSyncEvent(adminClient, {
      tenantId: stringValue(product.tenant_id),
      productId: stringValue(product.id),
      catalogId,
      retailerId: currentRetailerId,
      operation: "legacy_cleanup",
      status: failed.length > 0 ? "partial" : "success",
      error: failed.length > 0 ? failed.map((item) => item.error).filter(Boolean).join("; ") : null,
      requestPayload: { legacyRetailerIds: legacyCatalogRetailerIds(product) },
      responsePayload: { deleted, failed },
    });
  }

  return { deleted, failed };
}

// Re-reads Meta's current WhatsApp review state for an already-uploaded product
// WITHOUT re-uploading it. Powers the ERP "re-verificar estado" action and any
// scheduled polling so the stored status converges to real customer visibility.
async function refreshProductReview(
  adminClient: AdminClient,
  catalogId: string,
  product: JsonRecord,
) {
  const retailerId = catalogRetailerId(product);
  const shouldPublish = product.is_whatsapp_catalog === true &&
    product.is_active !== false &&
    product.is_published !== false;

  let catalogProduct: JsonRecord | null = null;
  for (const candidateRetailerId of allCatalogRetailerIds(product)) {
    catalogProduct = await findCatalogProduct(
      catalogId,
      candidateRetailerId,
      "id,retailer_id,url,capability_to_review_status",
    );
    if (catalogProduct) break;
  }

  if (!catalogProduct) {
    if (shouldPublish) {
      await updateSyncStatus(adminClient, stringValue(product.id), "pending", {
        error: "Aún no está en el catálogo de WhatsApp. Vuelve a sincronizar.",
        syncedUrl: null,
        urlMatches: false,
        verifiedAt: new Date().toISOString(),
      });
      return jsonResponse({
        ok: true,
        action: "absent",
        catalogId,
        productId: product.id,
        retailerId,
        syncStatus: "pending",
      });
    }
    await updateSyncStatus(adminClient, stringValue(product.id), "removed", {
      metaProductId: null,
      syncedUrl: null,
      urlMatches: null,
      verifiedAt: new Date().toISOString(),
    });
    return jsonResponse({
      ok: true,
      action: "removed",
      catalogId,
      productId: product.id,
      retailerId,
      syncStatus: "removed",
    });
  }

  const metaProductId = stringValue(catalogProduct.id) || null;
  const reviewValue = extractWhatsappReviewValue(catalogProduct);
  const expectedUrl = publicProductUrl("https://vinabike.cl", product);
  const storedUrl = stringValue(catalogProduct.url);
  const urlMatches = storedUrl === expectedUrl;
  const syncStatus = mapWhatsappReviewStatus(reviewValue);
  await updateSyncStatus(adminClient, stringValue(product.id), syncStatus, {
    metaProductId,
    syncedUrl: storedUrl || null,
    urlMatches,
    verifiedAt: new Date().toISOString(),
  });
  await logSyncEvent(adminClient, {
    tenantId: stringValue(product.tenant_id),
    productId: stringValue(product.id),
    catalogId,
    retailerId,
    metaProductId,
    operation: "refresh",
    status: "success",
    responsePayload: {
      syncStatus,
      whatsappReview: reviewValue || "NO_REVIEW",
      urlMatches,
    },
  });
  return jsonResponse({
    ok: true,
    action: "refreshed",
    catalogId,
    productId: product.id,
    retailerId,
    metaProductId,
    syncStatus,
    whatsappReview: reviewValue || "NO_REVIEW",
    expectedUrl,
    storedUrl: storedUrl || null,
    urlMatches,
  });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !META_ACCESS_TOKEN) {
    return jsonResponse({ error: "Missing required Meta/Supabase environment variables" }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse({ error: "Missing Authorization header" }, 401);
  }

  let request: SyncRequest;
  try {
    request = await req.json();
  } catch (_) {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const productId = stringValue(request.productId);
  if (!productId) {
    return jsonResponse({ error: "productId is required" }, 400);
  }
  const mode = stringValue(request.mode) === "refresh" ? "refresh" : "sync";
  const operation = stringValue(request.operation);

  const adminClient = createAdminClient();
  let canPersistFailure = false;
  try {
    if (operation === "delete") {
      if (!isServiceRoleAuth(authHeader)) {
        return jsonResponse({
          error: "Only service-role callers can sync deleted product snapshots",
        }, 403);
      }
      const productRecord = recordValue(request.product);
      if (stringValue(productRecord.id) !== productId) {
        productRecord.id = productId;
      }
      const productTenantId = stringValue(productRecord.tenant_id);
      if (!productTenantId) {
        return jsonResponse({ error: "Deleted product snapshot requires tenant_id" }, 400);
      }
      const catalogId = await resolveCatalogId(adminClient, productTenantId);
      return await removeProduct(adminClient, catalogId, productRecord, {
        persistStatus: false,
        operation: "delete",
      });
    }

    const { data: product, error } = await adminClient
      .from("products")
      .select([
        "id",
        "tenant_id",
        "name",
        "sku",
        "description",
        "brand",
        "category_name",
        "price",
        "inventory_qty",
        "stock_quantity",
        "is_active",
        "is_published",
        "is_whatsapp_catalog",
        "whatsapp_catalog_title",
        "whatsapp_catalog_description",
        "whatsapp_catalog_price",
        "website_name",
        "website_description",
        "website_price",
        "website_image_url",
        "website_image_url_optimized",
        "image_url",
        "image_url_optimized",
        "whatsapp_catalog_meta_product_id",
      ].join(","))
      .eq("id", productId)
      .maybeSingle();

    if (error) throw error;
    if (!product) return jsonResponse({ error: "Product not found" }, 404);

    const productRecord = product as unknown as JsonRecord;
    const productTenantId = stringValue(productRecord.tenant_id);
    const callerTenantId = await resolveCallerTenant(
      adminClient,
      authHeader,
      productTenantId,
    );
    if (!callerTenantId || callerTenantId !== productTenantId) {
      return jsonResponse({ error: "Unauthorized for this product tenant" }, 403);
    }

    canPersistFailure = true;
    const catalogId = await resolveCatalogId(adminClient, productTenantId);

    if (mode === "refresh") {
      return await refreshProductReview(adminClient, catalogId, productRecord);
    }

    await updateSyncStatus(adminClient, productId, "syncing");
    const shouldPublish = productRecord.is_whatsapp_catalog === true &&
      productRecord.is_active !== false &&
      productRecord.is_published !== false;

    return shouldPublish
      ? await upsertProduct(adminClient, catalogId, productRecord)
      : await removeProduct(adminClient, catalogId, productRecord);
  } catch (error) {
    console.error("whatsapp-catalog-sync error", error);
    if (canPersistFailure) {
      await updateSyncStatus(
        adminClient,
        productId,
        "failed",
        { error: error instanceof Error ? error.message : String(error) },
      );
    }
    return jsonResponse({
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});

function isServiceRoleAuth(authHeader: string) {
  const bearer = authHeader.replace(/^Bearer\s+/i, "");
  if (bearer === SUPABASE_SERVICE_ROLE_KEY) return true;
  const jwtPayload = resolveJwtPayload(authHeader);
  return stringValue(jwtPayload?.role) === "service_role";
}
