// @ts-ignore - Deno imports (VS Code TS server doesn't know Deno fetch/URL)
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// @ts-ignore - Deno imports
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// @ts-ignore - Deno serve function
serve(async (req: Request): Promise<Response> => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { action, input, placeId, sessionToken, tenantId } = (await req.json()) as {
      action: string;
      input?: string;
      placeId?: string;
      sessionToken?: string;
      tenantId: string;
    };

    if (!tenantId) {
      return new Response(
        JSON.stringify({ error: "tenantId is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Get API key from website_settings
    // @ts-ignore - Deno.env is available in Deno runtime
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    // @ts-ignore - Deno.env is available in Deno runtime
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const { data: settings } = await supabase
      .from("website_settings")
      .select("value")
      .eq("tenant_id", tenantId)
      .eq("key", "google_places_api_key")
      .single();

    const apiKey = settings?.value;

    if (action === "status") {
      return new Response(
        JSON.stringify({ enabled: Boolean(apiKey) }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: "Google Places API key not configured" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let url: string;
    
    if (action === "autocomplete") {
      // Places Autocomplete
      const params = new URLSearchParams({
        input: input,
        types: "address",
        components: "country:cl",
        language: "es",
        sessiontoken: sessionToken || "",
        key: apiKey,
      });
      url = `https://maps.googleapis.com/maps/api/place/autocomplete/json?${params}`;
    } else if (action === "details") {
      // Place Details
      const params = new URLSearchParams({
        place_id: placeId,
        fields: "formatted_address,address_components,geometry",
        language: "es",
        sessiontoken: sessionToken || "",
        key: apiKey,
      });
      url = `https://maps.googleapis.com/maps/api/place/details/json?${params}`;
    } else {
      return new Response(
        JSON.stringify({ error: "Invalid action" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const response = await fetch(url);
    const data = await response.json();

    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unknown error";
    console.error("Google Places proxy error:", message);
    return new Response(
      JSON.stringify({ error: message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
