// @ts-ignore - Deno imports (VS Code TS server doesn't know Deno fetch/URL)
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @ts-ignore - Deno imports
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Autocompletado de direcciones del checkout. Lo llaman visitantes sin
// cuenta con la clave pública de la tienda (el gateway rechaza una llamada
// sin clave), así que la llave de Google del tenant se protege acá: sólo
// entra una tienda activa, con entradas acotadas, y sale sólo lo que lee la
// tienda. `opening_hours` ya no se pide: Google lo cobra como dato de
// contacto y el checkout nunca lo usó (endurecimiento del 2026-09-24).

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PLACE_ID = /^[A-Za-z0-9_-]{10,512}$/;
const SESSION_TOKEN = /^[A-Za-z0-9-]{1,64}$/;
const MAX_INPUT_LENGTH = 120;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// @ts-ignore - Deno serve function
serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const body = (await req.json().catch(() => null)) as {
      action?: unknown;
      input?: unknown;
      placeId?: unknown;
      sessionToken?: unknown;
      tenantId?: unknown;
    } | null;
    const action = typeof body?.action === "string" ? body.action : "";
    const tenantId = typeof body?.tenantId === "string" ? body.tenantId.trim() : "";
    const input = typeof body?.input === "string" ? body.input.trim() : "";
    const placeId = typeof body?.placeId === "string" ? body.placeId.trim() : "";
    const sessionToken =
      typeof body?.sessionToken === "string" ? body.sessionToken.trim() : "";

    if (!UUID.test(tenantId)) {
      return json({ error: "tenantId is required" }, 400);
    }
    if (!["status", "autocomplete", "details"].includes(action)) {
      return json({ error: "Invalid action" }, 400);
    }
    if (sessionToken && !SESSION_TOKEN.test(sessionToken)) {
      return json({ error: "Invalid sessionToken" }, 400);
    }
    if (action === "autocomplete" &&
        (input.length < 3 || input.length > MAX_INPUT_LENGTH)) {
      return json({ error: "Invalid input" }, 400);
    }
    if (action === "details" && !PLACE_ID.test(placeId)) {
      return json({ error: "Invalid placeId" }, 400);
    }

    // @ts-ignore - Deno.env is available in Deno runtime
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    // @ts-ignore - Deno.env is available in Deno runtime
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const { data: tenant } = await supabase
      .from("tenants")
      .select("id")
      .eq("id", tenantId)
      .eq("is_active", true)
      .maybeSingle();
    if (!tenant) {
      return json({ enabled: false }, action === "status" ? 200 : 404);
    }

    const { data: settings } = await supabase
      .from("website_settings")
      .select("value")
      .eq("tenant_id", tenantId)
      .eq("key", "google_places_api_key")
      .maybeSingle();

    const apiKey = typeof settings?.value === "string" ? settings.value.trim() : "";

    if (action === "status") {
      return json({ enabled: Boolean(apiKey) });
    }

    if (!apiKey) {
      return json({ error: "Google Places API key not configured" }, 400);
    }

    if (action === "autocomplete") {
      const params = new URLSearchParams({
        input,
        types: "address",
        components: "country:cl",
        language: "es",
        sessiontoken: sessionToken,
        key: apiKey,
      });
      const response = await fetch(
        `https://maps.googleapis.com/maps/api/place/autocomplete/json?${params}`,
      );
      const data = await response.json();
      const predictions = Array.isArray(data?.predictions) ? data.predictions : [];
      return json({
        status: data?.status ?? "UNKNOWN_ERROR",
        predictions: predictions.map((prediction: Record<string, unknown>) => ({
          place_id: prediction.place_id,
          description: prediction.description,
        })),
      });
    }

    const params = new URLSearchParams({
      place_id: placeId,
      fields: "place_id,formatted_address,address_components,geometry",
      language: "es",
      sessiontoken: sessionToken,
      key: apiKey,
    });
    const response = await fetch(
      `https://maps.googleapis.com/maps/api/place/details/json?${params}`,
    );
    const data = await response.json();
    const result = data?.result;
    return json({
      status: data?.status ?? "UNKNOWN_ERROR",
      result: result
        ? {
          place_id: result.place_id,
          formatted_address: result.formatted_address,
          address_components: result.address_components ?? [],
          geometry: result.geometry?.location
            ? { location: result.geometry.location }
            : null,
        }
        : null,
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("Google Places proxy error:", message);
    return json({ error: "Address lookup failed" }, 500);
  }
});
