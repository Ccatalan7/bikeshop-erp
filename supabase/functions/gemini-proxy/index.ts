import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const allowedGenerateModels = new Set([
  "gemini-2.5-flash-lite",
  "gemini-2.5-flash",
]);

const allowedEmbeddingModels = new Set([
  "gemini-embedding-001",
]);

class GeminiApiError extends Error {
  readonly status: number;
  readonly upstreamStatusText?: string;
  readonly upstreamCode?: number;
  readonly upstreamDetails?: Record<string, unknown>;

  constructor(
    status: number,
    message: string,
    options: {
      upstreamStatusText?: string;
      upstreamCode?: number;
      upstreamDetails?: Record<string, unknown>;
    } = {},
  ) {
    super(message);
    this.name = "GeminiApiError";
    this.status = status;
    this.upstreamStatusText = options.upstreamStatusText;
    this.upstreamCode = options.upstreamCode;
    this.upstreamDetails = options.upstreamDetails;
  }
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name) ?? "";
  if (!value) {
    throw new Error(`${name} not configured`);
  }
  return value;
}

function objectValue(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null
    ? value as Record<string, unknown>
    : undefined;
}

async function requireAuthenticatedUser(req: Request) {
  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    throw new Error("Missing authentication");
  }

  const authClient = createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_ANON_KEY"),
    {
      global: {
        headers: { Authorization: authorization },
      },
    },
  );

  const { data, error } = await authClient.auth.getUser();
  if (error || !data.user) {
    throw new Error("Missing authentication");
  }

  return data.user;
}

async function callGemini(path: string, payload: Record<string, unknown>) {
  const apiKey = requireEnv("GEMINI_API_KEY");
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/${path}?key=${apiKey}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    },
  );

  const rawText = await response.text();
  let parsed: Record<string, unknown> = { raw: rawText };
  try {
    parsed = JSON.parse(rawText);
  } catch (_) {
    // Keep raw wrapper for non-JSON responses.
  }

  if (!response.ok) {
    const errorDetails = objectValue(parsed.error);
    const upstreamMessageValue = errorDetails?.message;
    const upstreamStatusValue = errorDetails?.status;
    const upstreamCodeValue = errorDetails?.code;
    const upstreamMessage = typeof upstreamMessageValue === "string"
      ? upstreamMessageValue
      : rawText;
    const upstreamStatusText = typeof upstreamStatusValue === "string"
      ? upstreamStatusValue
      : undefined;
    const upstreamCode = typeof upstreamCodeValue === "number"
      ? upstreamCodeValue
      : response.status;

    throw new GeminiApiError(response.status, upstreamMessage, {
      upstreamStatusText,
      upstreamCode,
      upstreamDetails: errorDetails ?? parsed,
    });
  }

  return parsed;
}

function normalizeGenerateResponse(data: Record<string, unknown>) {
  const candidates = Array.isArray(data.candidates) ? data.candidates : [];
  const firstCandidate = candidates[0] as Record<string, unknown> | undefined;
  const content = firstCandidate?.content as Record<string, unknown> | undefined;
  const parts = Array.isArray(content?.parts) ? content?.parts as Array<Record<string, unknown>> : [];

  let text = "";
  const functionCalls: Array<Record<string, unknown>> = [];

  for (const part of parts) {
    if (typeof part.text === "string") {
      text += part.text;
    }

    if (typeof part.functionCall === "object" && part.functionCall !== null) {
      const functionCall = part.functionCall as Record<string, unknown>;
      functionCalls.push({
        name: (functionCall.name ?? "").toString(),
        args: typeof functionCall.args === "object" && functionCall.args !== null
          ? functionCall.args as Record<string, unknown>
          : {},
      });
    }
  }

  return {
    text: text.trim(),
    functionCalls,
  };
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse({ error: "Method not allowed" }, 405);
    }

    const user = await requireAuthenticatedUser(req);
    const body = await req.json() as Record<string, unknown>;
    const action = (body.action ?? "").toString();

    if (action === "generate-content") {
      const model = (body.model ?? "").toString();
      if (!allowedGenerateModels.has(model)) {
        return jsonResponse({ error: `Model not allowed: ${model}` }, 400);
      }

      const contents = Array.isArray(body.contents) ? body.contents : [];
      if (contents.length === 0) {
        return jsonResponse({ error: "Missing contents" }, 400);
      }

      const payload: Record<string, unknown> = {
        contents,
      };

      if (typeof body.systemInstruction === "object" && body.systemInstruction !== null) {
        payload.systemInstruction = body.systemInstruction;
      }
      if (Array.isArray(body.tools) && body.tools.length > 0) {
        payload.tools = body.tools;
      }
      if (typeof body.generationConfig === "object" && body.generationConfig !== null) {
        payload.generationConfig = body.generationConfig;
      }

      console.log(`[gemini-proxy] user=${user.id} action=generate-content model=${model}`);
      const data = await callGemini(`models/${model}:generateContent`, payload);
      return jsonResponse(normalizeGenerateResponse(data));
    }

    if (action === "embed-text") {
      const model = (body.model ?? "").toString();
      if (!allowedEmbeddingModels.has(model)) {
        return jsonResponse({ error: `Embedding model not allowed: ${model}` }, 400);
      }

      const text = (body.text ?? "").toString().trim();
      if (!text) {
        return jsonResponse({ error: "Missing text" }, 400);
      }

      const payload: Record<string, unknown> = {
        content: {
          parts: [{ text }],
        },
      };

      const outputDimensionality = Number(body.outputDimensionality ?? 0);
      if (Number.isFinite(outputDimensionality) && outputDimensionality > 0) {
        payload.outputDimensionality = outputDimensionality;
      }

      console.log(`[gemini-proxy] user=${user.id} action=embed-text model=${model}`);
      const data = await callGemini(`models/${model}:embedContent`, payload);
      const embedding = (data.embedding as Record<string, unknown> | undefined)?.values;
      if (!Array.isArray(embedding)) {
        return jsonResponse({ error: "Invalid embedding response" }, 502);
      }

      return jsonResponse({ embedding });
    }

    return jsonResponse({ error: "Invalid action" }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);

    if (error instanceof GeminiApiError) {
      console.warn(
        `[gemini-proxy] upstream error status=${error.status} apiStatus=${error.upstreamStatusText ?? "unknown"}: ${message}`,
      );
      return jsonResponse({
        error: message,
        upstreamStatus: error.status,
        upstreamStatusText: error.upstreamStatusText,
        upstreamCode: error.upstreamCode,
        upstreamDetails: error.upstreamDetails,
      }, error.status);
    }

    const status = message === "Missing authentication"
      ? 401
      : message.endsWith("not configured")
      ? 500
      : 400;
    console.error("[gemini-proxy] unexpected error", error);
    return jsonResponse({ error: message }, status);
  }
});
