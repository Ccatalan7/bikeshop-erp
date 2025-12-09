import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { action, input, placeId, sessionToken, tenantId } = await req.json();

    // Get API key from website_settings
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const { data: settings } = await supabase
      .from("website_settings")
      .select("value")
      .eq("tenant_id", tenantId)
      .eq("key", "google_places_api_key")
      .single();

    const apiKey = settings?.value;
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
  } catch (error) {
    console.error("Google Places proxy error:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
