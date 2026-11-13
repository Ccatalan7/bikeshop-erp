// The weather for the daily briefing of the ERP: the caller's own shop, from
// its site settings, and the places that person added besides it. Any
// signed-in employee may read it. What a forecast is made of and the rules of
// its sources live in `../_shared/weather_forecast.ts`; finding and keeping
// places, in `../_shared/weather_places.ts`.
//
// Body: `{}` or `{action: "forecast", place_id?}` · `{action: "search", query}`
// · `{action: "add_place", name, region, latitude, longitude}` ·
// `{action: "remove_place", place_id}`.
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  loadPlaceWeather,
  parseWeatherLocation,
  SHOP_PLACE_KEY,
  type UpstreamAnswer,
  WEATHER_PROVIDER,
  type WeatherCacheRow,
  type WeatherDeps,
} from "../_shared/weather_forecast.ts";
import {
  MAX_PLACES_PER_PERSON,
  normalizePlaceMatches,
  photonAsNominatim,
  placeKey,
  placeSearchFallbackUrl,
  placeSearchUrl,
  zoneOf,
} from "../_shared/weather_places.ts";

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
const SEARCH_TIMEOUT_MS = 8000;
const CACHE_TABLE = "weather_forecast_cache";
const PLACES_TABLE = "weather_places";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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

  const userId = userData.user.id;
  let request: Record<string, unknown> = {};
  try {
    const parsed = await req.json();
    if (parsed !== null && typeof parsed === "object") request = parsed as Record<string, unknown>;
  } catch (_) {
    // No body is the shop's forecast, as before places existed.
  }
  const action = typeof request.action === "string" ? request.action : "forecast";

  const listPlaces = async () => {
    const { data, error } = await admin
      .from(PLACES_TABLE)
      .select("id, name, region, latitude, longitude, time_zone")
      .eq("tenant_id", tenantId)
      .eq("user_id", userId)
      .order("created_at", { ascending: true });
    if (error) throw new Error(`places read failed: ${error.code}`);
    return (data ?? []).map((row) => ({
      id: String(row.id),
      name: String(row.name),
      region: typeof row.region === "string" ? row.region : null,
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      time_zone: String(row.time_zone),
    }));
  };

  const deps: WeatherDeps = {
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
    readCache: async (tenant, placeKey) => {
      const { data, error } = await admin
        .from(CACHE_TABLE)
        .select(
          "latitude, longitude, payload, source_last_modified, fetched_at, checked_at, expires_at",
        )
        .eq("tenant_id", tenant)
        .eq("place_key", placeKey)
        .eq("provider", WEATHER_PROVIDER)
        .maybeSingle();
      if (error) throw new Error(`cache read failed: ${error.code}`);
      return (data as WeatherCacheRow | null) ?? null;
    },
    claimRefresh: async (tenant, now, claimsBefore, placeKey) => {
      const { data, error } = await admin
        .from(CACHE_TABLE)
        .update({ refresh_claimed_at: now.toISOString() })
        .eq("tenant_id", tenant)
        .eq("place_key", placeKey)
        .or(
          `refresh_claimed_at.is.null,refresh_claimed_at.lt."${claimsBefore.toISOString()}"`,
        )
        .select("tenant_id");
      if (error) throw new Error(`cache claim failed: ${error.code}`);
      return (data?.length ?? 0) === 1;
    },
    saveCache: async (tenant, row, placeKey) => {
      const { error } = await admin.from(CACHE_TABLE).upsert(
        {
          tenant_id: tenant,
          place_key: placeKey,
          provider: WEATHER_PROVIDER,
          ...row,
          refresh_claimed_at: null,
        },
        { onConflict: "tenant_id,place_key" },
      );
      if (error) throw new Error(`cache write failed: ${error.code}`);
    },
    fetchForecast,
    fetchObservations,
  };

  try {
    if (action === "search") {
      const query = typeof request.query === "string" ? request.query.trim() : "";
      if (query.length < 2 || query.length > 80) {
        return jsonResponse({ status: "invalid_query" }, 400);
      }
      const upstream: number[] = [];
      // Photon first: Nominatim turns this server away.
      try {
        const { response, body } = await get(
          placeSearchFallbackUrl(query),
          SEARCH_TIMEOUT_MS,
          {},
        );
        upstream.push(response.status);
        if (response.status === 200) {
          return jsonResponse({
            status: "ok",
            matches: normalizePlaceMatches(photonAsNominatim(body)),
          });
        }
      } catch (error) {
        console.error("[weather-forecast] place search fallback failed", error);
      }
      try {
        const { response, body } = await get(placeSearchUrl(query), SEARCH_TIMEOUT_MS, {});
        upstream.push(response.status);
        if (response.status === 200) {
          return jsonResponse({ status: "ok", matches: normalizePlaceMatches(body) });
        }
      } catch (error) {
        console.error("[weather-forecast] place search failed", error);
      }
      console.error("[weather-forecast] place search answered", upstream.join(","));
      return jsonResponse({ status: "unavailable", upstream }, 502);
    }

    if (action === "add_place") {
      const latitude = Number(request.latitude);
      const longitude = Number(request.longitude);
      const name = typeof request.name === "string" ? request.name.trim().slice(0, 80) : "";
      const region = typeof request.region === "string" && request.region.trim().length > 0
        ? request.region.trim().slice(0, 120)
        : null;
      if (
        name.length === 0 || !Number.isFinite(latitude) || !Number.isFinite(longitude) ||
        Math.abs(latitude) > 90 || Math.abs(longitude) > 180
      ) {
        return jsonResponse({ status: "invalid_place" }, 400);
      }
      const timeZone = zoneOf(latitude, longitude);
      if (timeZone === null) return jsonResponse({ status: "invalid_place" }, 400);
      const existing = await listPlaces();
      const [keyLatitude, keyLongitude] = placeKey(latitude, longitude).split(",").map(Number);
      let place = existing.find((entry) =>
        placeKey(entry.latitude, entry.longitude) === placeKey(latitude, longitude)
      ) ?? null;
      if (place === null) {
        if (existing.length >= MAX_PLACES_PER_PERSON) {
          return jsonResponse({ status: "too_many_places", places: existing }, 409);
        }
        const { data, error } = await admin
          .from(PLACES_TABLE)
          .insert({
            tenant_id: tenantId,
            user_id: userId,
            name,
            region,
            latitude: keyLatitude,
            longitude: keyLongitude,
            time_zone: timeZone,
          })
          .select("id")
          .single();
        if (error) {
          throw new Error(`place write failed: ${error.code}`);
        }
        place = {
          id: String(data.id),
          name,
          region,
          latitude: keyLatitude,
          longitude: keyLongitude,
          time_zone: timeZone,
        };
      }
      return jsonResponse({ status: "ok", place, places: await listPlaces() });
    }

    if (action === "remove_place") {
      const placeId = typeof request.place_id === "string" ? request.place_id : "";
      if (!UUID.test(placeId)) return jsonResponse({ status: "invalid_place" }, 400);
      const { error } = await admin
        .from(PLACES_TABLE)
        .delete()
        .eq("id", placeId)
        .eq("tenant_id", tenantId)
        .eq("user_id", userId);
      if (error) throw new Error(`place delete failed: ${error.code}`);
      return jsonResponse({ status: "ok", places: await listPlaces() });
    }

    if (action !== "forecast") return jsonResponse({ status: "unknown_action" }, 400);

    const places = await listPlaces();
    const shop = parseWeatherLocation(await deps.readSettings(tenantId));
    if (shop !== null) shop.time_zone = zoneOf(shop.latitude, shop.longitude);
    const extras = { places, shop_place: shop === null ? null : { name: shop.name } };

    const placeId = typeof request.place_id === "string" ? request.place_id : null;
    if (placeId !== null) {
      const place = places.find((entry) => entry.id === placeId) ?? null;
      // A place removed on another device: the app falls back to the shop.
      if (place === null) return jsonResponse({ status: "place_missing", ...extras });
      const result = await loadPlaceWeather(
        deps,
        tenantId,
        placeKey(place.latitude, place.longitude),
        place,
      );
      return jsonResponse({ ...result.body, ...extras }, result.status);
    }

    const result = await loadPlaceWeather(deps, tenantId, SHOP_PLACE_KEY, shop);
    return jsonResponse({ ...result.body, ...extras }, result.status);
  } catch (error) {
    console.error("[weather-forecast] failed", error);
    return jsonResponse({ status: "unavailable" }, 503);
  }
});
