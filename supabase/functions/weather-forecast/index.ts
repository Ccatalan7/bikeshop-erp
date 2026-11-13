// The weather of the caller's own shop, for the daily briefing of the ERP.
// Any signed-in employee may read it; nobody chooses the place: it is the
// shop's, from its site settings. What it is made of and the rules of its
// sources live in `../_shared/weather_forecast.ts`.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  loadShopWeather,
  type UpstreamAnswer,
  WEATHER_PROVIDER,
  type WeatherCacheRow,
} from "../_shared/weather_forecast.ts";

// `x-region` pins the function next to the database
// (`kSupabaseFunctionsRegionHeaders`); without it the web ERP's POST never
// leaves the browser.
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-region",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// Both sources ask every client to say who it is and where to write to.
const UPSTREAM_USER_AGENT = Deno.env.get("WEATHER_USER_AGENT") ??
  "VinabikeERP/1 https://vinabike.cl";
const FORECAST_TIMEOUT_MS = 8000;
const OBSERVATION_TIMEOUT_MS = 5000;
const CACHE_TABLE = "weather_forecast_cache";

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function get(url: string, timeoutMs: number, headers: Record<string, string>) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      headers: { "User-Agent": UPSTREAM_USER_AGENT, "Accept": "application/json", ...headers },
      signal: controller.signal,
    });
    const body = response.status === 200 ? await response.json() : null;
    if (response.status !== 200) await response.body?.cancel();
    return { response, body };
  } finally {
    clearTimeout(timer);
  }
}

async function fetchForecast(
  url: string,
  ifModifiedSince: string | null,
): Promise<UpstreamAnswer> {
  const { response, body } = await get(
    url,
    FORECAST_TIMEOUT_MS,
    ifModifiedSince ? { "If-Modified-Since": ifModifiedSince } : {},
  );
  return {
    status: response.status,
    expires: response.headers.get("expires"),
    lastModified: response.headers.get("last-modified"),
    body,
  };
}

async function fetchObservations(box: string): Promise<unknown> {
  const { response, body } = await get(
    `https://aviationweather.gov/api/data/metar?bbox=${box}&format=json&hours=2`,
    OBSERVATION_TIMEOUT_MS,
    {},
  );
  // No aerodrome in the box answers 204, which is an answer.
  if (response.status === 204) return [];
  if (response.status !== 200) throw new Error(`observations answered ${response.status}`);
  return body;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ status: "method_not_allowed" }, 405);
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error("[weather-forecast] required server configuration is absent");
    return jsonResponse({ status: "server_not_configured" }, 503);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization) return jsonResponse({ status: "unauthorized" }, 401);
  const authClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await authClient.auth.getUser();
  if (userError || !userData.user) return jsonResponse({ status: "unauthorized" }, 401);

  const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  // One active profile names the shop; none or several name nobody.
  const { data: profiles, error: profileError } = await admin
    .from("user_profiles")
    .select("tenant_id")
    .eq("user_id", userData.user.id)
    .eq("is_active", true)
    .limit(2);
  if (profileError) {
    console.error("[weather-forecast] profile lookup failed", profileError.code);
    return jsonResponse({ status: "unavailable" }, 503);
  }
  const tenantId = profiles?.length === 1 ? String(profiles[0].tenant_id ?? "") : "";
  if (!tenantId) return jsonResponse({ status: "forbidden" }, 403);

  try {
    const result = await loadShopWeather({
      now: () => new Date(),
      readSettings: async (tenant) => {
        const { data, error } = await admin
          .from("website_settings")
          .select("key, value")
          .eq("tenant_id", tenant)
          .in("key", ["seo_geo_latitude", "seo_geo_longitude", "seo_address_city"]);
        if (error) throw new Error(`settings read failed: ${error.code}`);
        const settings: Record<string, string> = {};
        for (const row of data ?? []) {
          if (typeof row.key === "string" && typeof row.value === "string") {
            settings[row.key] = row.value;
          }
        }
        return settings;
      },
      readCache: async (tenant) => {
        const { data, error } = await admin
          .from(CACHE_TABLE)
          .select(
            "latitude, longitude, payload, source_last_modified, fetched_at, checked_at, expires_at",
          )
          .eq("tenant_id", tenant)
          .eq("provider", WEATHER_PROVIDER)
          .maybeSingle();
        if (error) throw new Error(`cache read failed: ${error.code}`);
        return (data as WeatherCacheRow | null) ?? null;
      },
      claimRefresh: async (tenant, now, claimsBefore) => {
        const { data, error } = await admin
          .from(CACHE_TABLE)
          .update({ refresh_claimed_at: now.toISOString() })
          .eq("tenant_id", tenant)
          .or(
            `refresh_claimed_at.is.null,refresh_claimed_at.lt."${claimsBefore.toISOString()}"`,
          )
          .select("tenant_id");
        if (error) throw new Error(`cache claim failed: ${error.code}`);
        return (data?.length ?? 0) === 1;
      },
      saveCache: async (tenant, row) => {
        const { error } = await admin.from(CACHE_TABLE).upsert(
          {
            tenant_id: tenant,
            provider: WEATHER_PROVIDER,
            ...row,
            refresh_claimed_at: null,
          },
          { onConflict: "tenant_id" },
        );
        if (error) throw new Error(`cache write failed: ${error.code}`);
      },
      fetchForecast,
      fetchObservations,
    }, tenantId);
    return jsonResponse(result.body, result.status);
  } catch (error) {
    console.error("[weather-forecast] failed", error);
    return jsonResponse({ status: "unavailable" }, 503);
  }
});
