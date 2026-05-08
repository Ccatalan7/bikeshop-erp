// @ts-ignore - Deno imports (VS Code TS server doesn't know Deno fetch/URL)
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @ts-ignore - Deno imports
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type SettingRow = {
  tenant_id: string;
  key: string;
  value: string | null;
};

type TenantSettings = Record<string, string>;

type RefreshRequest = {
  tenantId?: string;
  force?: boolean;
  maxTenants?: number;
};

type GooglePlaceReview = {
  author_name?: string;
  author_url?: string;
  profile_photo_url?: string;
  rating?: number;
  relative_time_description?: string;
  text?: string;
  time?: number;
  language?: string;
  original_language?: string;
  translated?: boolean;
};

type GooglePlaceDetailsResult = {
  place_id?: string;
  name?: string;
  formatted_address?: string;
  url?: string;
  rating?: number;
  user_ratings_total?: number;
  reviews?: GooglePlaceReview[];
  opening_hours?: Record<string, unknown>;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-refresh-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const settingsKeys = [
  "google_places_api_key",
  "google_maps_place_id",
  "google_reviews_data",
  "google_reviews_last_synced_at",
  "google_reviews_auto_refresh_enabled",
  "google_reviews_source",
];

const staleAfterMs = 23 * 60 * 60 * 1000;

// @ts-ignore - Deno serve function
serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    authorizeRefresh(req);

    const body = await readRequestBody(req);
    const supabaseUrl = getEnv("SUPABASE_URL");
    const supabaseKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
    const supabase = createClient(supabaseUrl, supabaseKey);

    const targets = await loadRefreshTargets(supabase, body);
    const results = [];

    for (const target of targets) {
      const result = await refreshTenant(supabase, target.tenantId, target.settings, {
        force: body.force === true,
      });
      results.push(result);
    }

    return jsonResponse({
      ok: true,
      checked: results.length,
      updated: results.filter((item) => item.status === "updated").length,
      skipped: results.filter((item) => item.status === "skipped").length,
      failed: results.filter((item) => item.status === "failed").length,
      results,
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("Google public data refresh error:", message);
    return jsonResponse({ error: message }, message === "Unauthorized" ? 401 : 500);
  }
});

async function readRequestBody(req: Request): Promise<RefreshRequest> {
  try {
    return (await req.json()) as RefreshRequest;
  } catch (_) {
    return {};
  }
}

function authorizeRefresh(req: Request): void {
  const configuredSecret = getEnv("GOOGLE_PUBLIC_DATA_REFRESH_SECRET", false);
  const providedSecret = req.headers.get("x-refresh-secret")?.trim() ?? "";
  const serviceRoleKey = getEnv("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("authorization")?.trim() ?? "";

  if (configuredSecret && providedSecret === configuredSecret) {
    return;
  }

  if (authorization === `Bearer ${serviceRoleKey}`) {
    return;
  }

  throw new Error("Unauthorized");
}

async function loadRefreshTargets(
  supabase: ReturnType<typeof createClient>,
  body: RefreshRequest,
): Promise<Array<{ tenantId: string; settings: TenantSettings }>> {
  let query = supabase
    .from("website_settings")
    .select("tenant_id,key,value")
    .in("key", settingsKeys);

  if (body.tenantId) {
    query = query.eq("tenant_id", body.tenantId);
  }

  const { data, error } = await query;
  if (error) throw error;

  const grouped = new Map<string, TenantSettings>();
  for (const row of (data ?? []) as SettingRow[]) {
    const settings = grouped.get(row.tenant_id) ?? {};
    settings[row.key] = row.value ?? "";
    grouped.set(row.tenant_id, settings);
  }

  const maxTenants = Math.max(1, Math.min(body.maxTenants ?? 50, 200));
  return [...grouped.entries()]
    .filter(([, settings]) => hasRequiredGooglePlacesSettings(settings))
    .slice(0, maxTenants)
    .map(([tenantId, settings]) => ({ tenantId, settings }));
}

function hasRequiredGooglePlacesSettings(settings: TenantSettings): boolean {
  return Boolean(settings.google_places_api_key?.trim()) &&
    Boolean(settings.google_maps_place_id?.trim());
}

async function refreshTenant(
  supabase: ReturnType<typeof createClient>,
  tenantId: string,
  settings: TenantSettings,
  options: { force: boolean },
) {
  const enabledValue = settings.google_reviews_auto_refresh_enabled?.trim().toLowerCase();
  if (enabledValue === "false" || enabledValue === "0" || enabledValue === "no") {
    return { tenantId, status: "skipped", reason: "auto_refresh_disabled" };
  }

  if (!options.force && !isReviewDataStale(settings.google_reviews_last_synced_at)) {
    return { tenantId, status: "skipped", reason: "fresh" };
  }

  try {
    const place = await fetchPlaceDetails(
      settings.google_places_api_key,
      settings.google_maps_place_id,
    );
    const reviews = normalizeReviews(place.reviews ?? []);
    const existingReviews = parseStoredReviews(settings.google_reviews_data);
    const now = new Date().toISOString();

    const updates: Record<string, string> = {
      google_reviews_last_synced_at: now,
      google_reviews_auto_sync_status: "ok",
      google_reviews_auto_sync_error: "",
      google_reviews_source: "google_places",
    };

    if (shouldReplaceReviewCards({
      force: options.force,
      existingCount: existingReviews.length,
      nextCount: reviews.length,
      existingSource: settings.google_reviews_source,
    })) {
      updates.google_reviews_data = JSON.stringify(reviews);
    }

    if (typeof place.rating === "number") {
      updates.google_reviews_rating = String(place.rating);
    }
    if (typeof place.user_ratings_total === "number") {
      updates.google_reviews_total = String(place.user_ratings_total);
    }
    if (place.url) {
      updates.business_google_maps_url = place.url;
      updates.google_maps_url = place.url;
    }
    if (place.opening_hours) {
      updates.business_hours_json = JSON.stringify(place.opening_hours);
    }

    await upsertSettings(supabase, tenantId, updates);

    return {
      tenantId,
      status: "updated",
      reviews: reviews.length,
      rating: place.rating ?? null,
      total: place.user_ratings_total ?? null,
    };
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unknown error";
    await upsertSettings(supabase, tenantId, {
      google_reviews_auto_sync_status: "error",
      google_reviews_auto_sync_error: message.slice(0, 500),
      google_reviews_last_attempt_at: new Date().toISOString(),
    });
    return { tenantId, status: "failed", error: message };
  }
}

function isReviewDataStale(lastSyncedAt?: string): boolean {
  if (!lastSyncedAt) return true;
  const lastSyncMs = Date.parse(lastSyncedAt);
  if (!Number.isFinite(lastSyncMs)) return true;
  return Date.now() - lastSyncMs >= staleAfterMs;
}

async function fetchPlaceDetails(
  apiKey: string,
  placeId: string,
): Promise<GooglePlaceDetailsResult> {
  const params = new URLSearchParams({
    place_id: placeId,
    fields: "place_id,name,formatted_address,opening_hours,url,rating,user_ratings_total,reviews",
    language: "es",
    reviews_sort: "newest",
    key: apiKey,
  });

  const response = await fetch(`https://maps.googleapis.com/maps/api/place/details/json?${params}`);
  const payload = await response.json();

  if (!response.ok || payload.status !== "OK") {
    const status = payload.status ?? response.status;
    const detail = payload.error_message ? `: ${payload.error_message}` : "";
    throw new Error(`Google Places details failed (${status})${detail}`);
  }

  return payload.result as GooglePlaceDetailsResult;
}

function normalizeReviews(reviews: GooglePlaceReview[]): Array<Record<string, unknown>> {
  return reviews
    .slice(0, 5)
    .map((review) => ({
      author_name: review.author_name ?? "Cliente Google",
      author_url: review.author_url ?? "",
      photo_url: review.profile_photo_url ?? "",
      profile_photo_url: review.profile_photo_url ?? "",
      rating: review.rating ?? 5,
      relative_time: review.relative_time_description ?? "",
      relative_time_description: review.relative_time_description ?? "",
      text: review.text ?? "",
      time: review.time ?? null,
      language: review.language ?? "",
      original_language: review.original_language ?? "",
      translated: review.translated ?? false,
      source: "google_places",
    }));
}

function parseStoredReviews(raw?: string): unknown[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    return [];
  }
}

function shouldReplaceReviewCards(params: {
  force: boolean;
  existingCount: number;
  nextCount: number;
  existingSource?: string;
}): boolean {
  if (params.force) return true;
  if (params.nextCount === 0) return false;
  if (params.existingCount === 0) return true;
  if ((params.existingSource ?? "") === "google_places") return true;
  return params.nextCount >= params.existingCount;
}

async function upsertSettings(
  supabase: ReturnType<typeof createClient>,
  tenantId: string,
  values: Record<string, string>,
): Promise<void> {
  const rows = Object.entries(values).map(([key, value]) => ({
    tenant_id: tenantId,
    key,
    value,
    updated_at: new Date().toISOString(),
  }));

  const { error } = await supabase
    .from("website_settings")
    .upsert(rows, { onConflict: "tenant_id,key" });

  if (error) throw error;
}

function getEnv(key: string, required = true): string {
  // @ts-ignore - Deno.env is available in Deno runtime
  const value = Deno.env.get(key);
  if (required && !value) {
    throw new Error(`${key} is not configured`);
  }
  return value ?? "";
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}