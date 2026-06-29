// Google Business Profile API Proxy
// Bypasses CORS restrictions for web clients
// @ts-ignore - Deno imports
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface RequestBody {
    action: "fetchAccounts" | "fetchLocations" | "fetchReviews" | "updateRegularHours";
    accessToken: string;
    accountName?: string; // For fetchLocations: "accounts/123456"
    locationName?: string; // For fetchReviews: "locations/123456"
    regularHours?: Record<string, unknown>;
}

function toBusinessInfoLocationName(locationName: string) {
    const parts = locationName.split("/");
    const locationsIndex = parts.lastIndexOf("locations");
    if (locationsIndex >= 0 && parts[locationsIndex + 1]) {
        return `locations/${parts[locationsIndex + 1]}`;
    }
    return locationName;
}

// @ts-ignore - Deno serve
serve(async (req: Request): Promise<Response> => {
    // Handle CORS preflight
    if (req.method === "OPTIONS") {
        return new Response("ok", { headers: corsHeaders });
    }

    try {
        const { action, accessToken, accountName, locationName, regularHours } = (await req.json()) as RequestBody;

        if (!accessToken) {
            return new Response(
                JSON.stringify({ error: "Missing accessToken" }),
                { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
        }

        const headers = {
            "Authorization": `Bearer ${accessToken}`,
            "Content-Type": "application/json",
        };

        let url: string;

        switch (action) {
            case "fetchAccounts":
                // https://mybusinessaccountmanagement.googleapis.com/v1/accounts
                url = "https://mybusinessaccountmanagement.googleapis.com/v1/accounts";
                break;

            case "fetchLocations":
                if (!accountName) {
                    return new Response(
                        JSON.stringify({ error: "Missing accountName for fetchLocations" }),
                        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
                    );
                }
                // https://mybusinessbusinessinformation.googleapis.com/v1/{parent}/locations
                const readMask = "name,title,storeCode,storefrontAddress,latlng,phoneNumbers,regularHours,categories,metadata,languageCode,serviceArea";
                url = `https://mybusinessbusinessinformation.googleapis.com/v1/${accountName}/locations?readMask=${encodeURIComponent(readMask)}`;
                break;

            case "fetchReviews":
                if (!locationName) {
                    return new Response(
                        JSON.stringify({ error: "Missing locationName for fetchReviews" }),
                        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
                    );
                }
                // https://mybusiness.googleapis.com/v4/{name}/reviews
                url = `https://mybusiness.googleapis.com/v4/${locationName}/reviews`;
                break;

            case "updateRegularHours":
                if (!locationName) {
                    return new Response(
                        JSON.stringify({ error: "Missing locationName for updateRegularHours" }),
                        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
                    );
                }
                if (!regularHours || !Array.isArray(regularHours.periods)) {
                    return new Response(
                        JSON.stringify({ error: "Missing regularHours.periods for updateRegularHours" }),
                        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
                    );
                }
                url = `https://mybusinessbusinessinformation.googleapis.com/v1/${toBusinessInfoLocationName(locationName)}?updateMask=regularHours`;
                break;

            default:
                return new Response(
                    JSON.stringify({ error: `Invalid action: ${action}` }),
                    { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
                );
        }

        console.log(`[google-business-reviews] ${action} -> ${url}`);

        const response = await fetch(
            url,
            action === "updateRegularHours"
                ? {
                    method: "PATCH",
                    headers,
                    body: JSON.stringify({ regularHours }),
                }
                : { headers },
        );
        const responseText = await response.text();

        // Try to parse as JSON, but handle HTML error pages
        let data;
        try {
            data = JSON.parse(responseText);
        } catch {
            console.error(`[google-business-reviews] Non-JSON response: ${responseText.substring(0, 500)}`);
            return new Response(
                JSON.stringify({
                    error: `Google API returned non-JSON response (HTTP ${response.status})`,
                    details: responseText.substring(0, 200)
                }),
                { status: response.status || 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            );
        }

        // Pass through Google's response (including errors)
        return new Response(JSON.stringify(data), {
            status: response.ok ? 200 : response.status,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
        });

    } catch (error: unknown) {
        const message = error instanceof Error ? error.message : "Unknown error";
        console.error("[google-business-reviews] Error:", message);
        return new Response(
            JSON.stringify({ error: message }),
            { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
    }
});
