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
  "gemini-3.6-flash",
]);
const allowedEmbeddingModels = new Set(["gemini-embedding-001"]);

export function isAllowedGenerateModel(model: string): boolean {
  return allowedGenerateModels.has(model);
}

class ProxyError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    readonly publicMessage: string,
    readonly metadata: Record<string, unknown> = {},
  ) {
    super(publicMessage);
    this.name = "ProxyError";
  }
}

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function errorResponse(
  status: number,
  code: string,
  message: string,
  metadata: Record<string, unknown> = {},
): Response {
  return jsonResponse({ error: message, code, ...metadata }, status);
}

function requireEnv(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new ProxyError(500, "proxy_not_configured", "AI service is unavailable");
  return value;
}

async function requireAuthenticatedUser(request: Request): Promise<void> {
  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    throw new ProxyError(401, "invalid_session", "Authentication required");
  }
  const authClient = createClient(
    requireEnv("SUPABASE_URL"),
    requireEnv("SUPABASE_ANON_KEY"),
    { global: { headers: { Authorization: authorization } } },
  );
  const { data, error } = await authClient.auth.getUser();
  if (error || !data.user) {
    throw new ProxyError(401, "invalid_session", "Authentication required");
  }
}

async function callGemini(path: string, payload: Record<string, unknown>) {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/${path}?key=${requireEnv("GEMINI_API_KEY")}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    },
  );
  if (!response.ok) {
    const providerFailure = await safeProviderFailure(response);
    const status = response.status === 400 ? 400 : response.status === 429 ? 429 : 502;
    throw new ProxyError(
      status,
      response.status === 400 ? "provider_rejected_request" : "provider_unavailable",
      response.status === 400 ? "AI provider rejected the request" : "AI provider is unavailable",
      providerFailure,
    );
  }
  try {
    const parsed = await response.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
    return parsed as Record<string, unknown>;
  } catch (_) {
    throw new ProxyError(
      502,
      "provider_invalid_response",
      "AI provider response is invalid",
    );
  }
}

export function normalizeGenerateResponse(data: Record<string, unknown>) {
  const candidates = Array.isArray(data.candidates) ? data.candidates : [];
  const firstCandidate = candidates[0] as Record<string, unknown> | undefined;
  const content = firstCandidate?.content as Record<string, unknown> | undefined;
  const parts = Array.isArray(content?.parts)
    ? content.parts as Array<Record<string, unknown>>
    : [];
  let text = "";
  const functionCalls: Array<Record<string, unknown>> = [];
  for (const part of parts) {
    if (typeof part.text === "string") text += part.text;
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
  const rawFinishReason = firstCandidate?.finishReason;
  const finishReason = typeof rawFinishReason === "string" &&
      /^[A-Z][A-Z0-9_]{0,63}$/.test(rawFinishReason)
    ? rawFinishReason
    : null;
  return {
    text: text.trim(),
    functionCalls,
    finishReason,
    candidateCount: candidates.length,
  };
}

/// Redacts an upstream error to stable provider status/code/field pointers.
/// Provider messages and descriptions are deliberately discarded because they
/// may echo request content or schema values.
export async function safeProviderFailure(
  response: Response,
): Promise<Record<string, unknown>> {
  let payload: unknown;
  try {
    payload = await response.json();
  } catch (_) {
    payload = null;
  }
  const root = payload && typeof payload === "object" && !Array.isArray(payload)
    ? payload as Record<string, unknown>
    : {};
  const error = root.error && typeof root.error === "object" && !Array.isArray(root.error)
    ? root.error as Record<string, unknown>
    : {};
  const providerStatus = typeof error.status === "string" &&
      /^[A-Z][A-Z0-9_]{0,63}$/.test(error.status)
    ? error.status
    : null;
  const providerCode = typeof error.code === "number" && Number.isFinite(error.code)
    ? Math.trunc(error.code)
    : response.status;
  const fieldPaths: string[] = [];
  const details = Array.isArray(error.details) ? error.details : [];
  for (const detail of details) {
    if (!detail || typeof detail !== "object" || Array.isArray(detail)) continue;
    const violations = Array.isArray((detail as Record<string, unknown>).fieldViolations)
      ? (detail as Record<string, unknown>).fieldViolations as unknown[]
      : [];
    for (const violation of violations) {
      if (!violation || typeof violation !== "object" || Array.isArray(violation)) continue;
      const field = (violation as Record<string, unknown>).field;
      if (
        typeof field === "string" &&
        field.length <= 160 &&
        /^[A-Za-z0-9_.\[\]-]+$/.test(field) &&
        !fieldPaths.includes(field)
      ) {
        fieldPaths.push(field);
      }
      if (fieldPaths.length >= 10) break;
    }
    if (fieldPaths.length >= 10) break;
  }
  return {
    upstreamStatus: response.status,
    upstreamStatusText: providerStatus,
    upstreamCode: providerCode,
    providerFieldPaths: fieldPaths,
  };
}

export async function handler(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    if (request.method !== "POST") {
      return errorResponse(405, "method_not_allowed", "Method not allowed");
    }
    await requireAuthenticatedUser(request);
    const body = await request.json() as Record<string, unknown>;
    const action = (body.action ?? "").toString();
    if (action === "generate-content") {
      const model = (body.model ?? "").toString();
      if (!isAllowedGenerateModel(model)) {
        return errorResponse(400, "model_not_allowed", "Model not allowed");
      }
      const contents = Array.isArray(body.contents) ? body.contents : [];
      if (!contents.length) return errorResponse(400, "invalid_request", "Invalid request");
      const payload: Record<string, unknown> = { contents };
      if (typeof body.systemInstruction === "object" && body.systemInstruction !== null) {
        payload.systemInstruction = body.systemInstruction;
      }
      if (Array.isArray(body.tools) && body.tools.length) payload.tools = body.tools;
      if (typeof body.generationConfig === "object" && body.generationConfig !== null) {
        payload.generationConfig = body.generationConfig;
      }
      const data = await callGemini(`models/${model}:generateContent`, payload);
      return jsonResponse(normalizeGenerateResponse(data));
    }
    if (action === "embed-text") {
      const model = (body.model ?? "").toString();
      if (!allowedEmbeddingModels.has(model)) {
        return errorResponse(400, "model_not_allowed", "Model not allowed");
      }
      const text = (body.text ?? "").toString().trim();
      if (!text) return errorResponse(400, "invalid_request", "Invalid request");
      const payload: Record<string, unknown> = { content: { parts: [{ text }] } };
      const outputDimensionality = Number(body.outputDimensionality ?? 0);
      if (Number.isFinite(outputDimensionality) && outputDimensionality > 0) {
        payload.outputDimensionality = outputDimensionality;
      }
      const data = await callGemini(`models/${model}:embedContent`, payload);
      const embedding = (data.embedding as Record<string, unknown> | undefined)?.values;
      if (!Array.isArray(embedding)) {
        return errorResponse(
          502,
          "provider_invalid_response",
          "AI provider response is invalid",
        );
      }
      return jsonResponse({ embedding });
    }
    return errorResponse(400, "invalid_action", "Invalid action");
  } catch (error) {
    if (error instanceof ProxyError) {
      return errorResponse(
        error.status,
        error.code,
        error.publicMessage,
        error.metadata,
      );
    }
    return errorResponse(400, "invalid_request", "Invalid request");
  }
}

if (import.meta.main) serve(handler);
