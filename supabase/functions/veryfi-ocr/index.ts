import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function decodeBase64(contentBase64: string): Uint8Array {
  const binary = atob(contentBase64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function buildVeryfiHeaders(): Headers {
  const apiUrl = Deno.env.get("VERYFI_API_URL") ??
    "https://api.veryfi.com/api/v8/partner/documents";
  const clientId = Deno.env.get("VERYFI_CLIENT_ID") ?? "";
  const apiKey = Deno.env.get("VERYFI_API_KEY") ?? "";
  const username = Deno.env.get("VERYFI_USERNAME") ?? "";
  const authHeader = Deno.env.get("VERYFI_AUTH_HEADER") ?? "";
  const authValue = Deno.env.get("VERYFI_AUTH_VALUE") ?? "";

  if (!apiKey || (!clientId && !authHeader)) {
    throw new Error("OCR server not configured");
  }

  const headers = new Headers({
    "Accept": "application/json",
  });

  if (clientId) {
    headers.set("Client-Id", clientId);
  }

  if (authHeader && authValue) {
    headers.set(authHeader, authValue);
  } else if (username && apiKey) {
    headers.set("Authorization", `apikey ${username}:${apiKey}`);
  } else if (clientId && apiKey) {
    headers.set("Authorization", `apikey ${clientId}:${apiKey}`);
  } else {
    headers.set("Authorization", `apikey ${apiKey}`);
  }

  headers.set("x-veryfi-api-url", apiUrl);
  return headers;
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    const authorization = req.headers.get("Authorization");
    if (!authorization) {
      return jsonResponse({ error: "Missing authentication" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: { Authorization: authorization },
      },
    });

    const { data: userData, error: userError } = await authClient.auth.getUser();
    if (userError || !userData.user) {
      console.error("[veryfi-ocr] auth error", userError);
      return jsonResponse({ error: "Missing authentication" }, 401);
    }

    const { filename, contentBase64 } = await req.json() as {
      filename?: string;
      contentBase64?: string;
    };

    if (!filename || !contentBase64) {
      return jsonResponse({ error: "Missing filename or contentBase64" }, 400);
    }

    const veryfiHeaders = buildVeryfiHeaders();
    const apiUrl = veryfiHeaders.get("x-veryfi-api-url")!;
    veryfiHeaders.delete("x-veryfi-api-url");

    const bytes = decodeBase64(contentBase64);
    const formData = new FormData();
    formData.append("file", new Blob([bytes]), filename);

    console.log(`[veryfi-ocr] user=${userData.user.id} file=${filename} size=${bytes.length}`);

    const veryfiResponse = await fetch(apiUrl, {
      method: "POST",
      headers: veryfiHeaders,
      body: formData,
    });

    const rawText = await veryfiResponse.text();
    let parsedBody: unknown = { raw: rawText };
    try {
      parsedBody = JSON.parse(rawText);
    } catch (_) {
      // Keep raw string wrapper for non-JSON responses.
    }

    if (!veryfiResponse.ok) {
      console.error("[veryfi-ocr] Veryfi error", veryfiResponse.status, rawText);
      return jsonResponse(
        {
          error: `Veryfi API error: ${veryfiResponse.status} ${rawText}`,
        },
        veryfiResponse.status,
      );
    }

    return new Response(JSON.stringify(parsedBody), {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    });
  } catch (error) {
    console.error("[veryfi-ocr] unexpected error", error);
    return jsonResponse(
      {
        error: error instanceof Error ? error.message : String(error),
      },
      400,
    );
  }
});