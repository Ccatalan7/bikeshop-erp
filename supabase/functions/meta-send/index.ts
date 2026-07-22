import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  durableMetaSendSuccess,
  metaProviderFailureDisposition,
  metaProviderFailureHttpStatus,
  type MetaSendAttemptReceipt,
  type MetaSendAttemptState,
  replayedMetaSendResponse,
} from "../_shared/meta_send_receipts.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const configuredVersion = Deno.env.get("META_GRAPH_VERSION") ?? "v25.0";
const META_GRAPH_VERSION = /^v\d+\.\d+$/.test(configuredVersion) ? configuredVersion : "v25.0";

type JsonRecord = Record<string, unknown>;
// deno-lint-ignore no-explicit-any -- Edge Functions use the runtime schema.
type SupabaseClientLike = ReturnType<typeof createClient<any>>;

interface MetaSendRequest {
  conversationId?: unknown;
  message?: unknown;
  clientMessageId?: unknown;
  metadata?: unknown;
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function stringValue(value: unknown, maxLength = Number.MAX_SAFE_INTEGER) {
  if (typeof value !== "string") return null;
  const result = value.trim();
  return result && result.length <= maxLength ? result : null;
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function parseJsonResponse(response: Response) {
  const raw = await response.text();
  try {
    const value = JSON.parse(raw);
    return value && typeof value === "object" ? value as JsonRecord : {};
  } catch {
    return {};
  }
}

function sanitizedProviderResponse(value: JsonRecord) {
  const error = value.error && typeof value.error === "object" ? value.error as JsonRecord : null;
  return {
    ...(stringValue(value.message_id, 512)
      ? { message_id: stringValue(value.message_id, 512) }
      : {}),
    ...(stringValue(value.recipient_id, 512)
      ? { recipient_id: stringValue(value.recipient_id, 512) }
      : {}),
    ...(error
      ? {
        error: {
          ...(stringValue(error.message, 500) ? { message: stringValue(error.message, 500) } : {}),
          ...(stringValue(error.type, 120) ? { type: stringValue(error.type, 120) } : {}),
          ...(typeof error.code === "number" ? { code: error.code } : {}),
          ...(typeof error.error_subcode === "number"
            ? { error_subcode: error.error_subcode }
            : {}),
          ...(stringValue(error.fbtrace_id, 160)
            ? { fbtrace_id: stringValue(error.fbtrace_id, 160) }
            : {}),
        },
      }
      : {}),
  };
}

function attemptReceipt(value: JsonRecord): MetaSendAttemptReceipt {
  return {
    attempt_id: String(value.attempt_id ?? ""),
    state: String(value.state ?? "prepared") as MetaSendAttemptState,
    message_id: stringValue(value.message_id, 100),
    client_message_id: stringValue(value.client_message_id, 200),
    external_message_id: stringValue(value.external_message_id, 512),
    external_status: stringValue(value.external_status, 40),
    error_code: stringValue(value.error_code, 120),
    error_message: stringValue(value.error_message, 500),
  };
}

async function markAttempt(
  client: SupabaseClientLike,
  attemptId: string,
  state: "preflight_failed" | "provider_rejected" | "outcome_unknown",
  errorCode: string,
  errorMessage: string,
  providerResponse: JsonRecord,
) {
  const { error } = await client.rpc("mark_meta_outbound_attempt", {
    p_attempt_id: attemptId,
    p_state: state,
    p_error_code: errorCode,
    p_error_message: errorMessage,
    p_provider_response: providerResponse,
  });
  if (error) {
    console.error("[META-SEND] Could not persist terminal attempt", error.code);
  }
}

serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: { code: "method_not_allowed" } }, 405);
  }
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    console.error("[META-SEND] Required Supabase configuration is absent");
    return jsonResponse({ ok: false, error: { code: "server_not_configured" } }, 503);
  }

  const authorization = request.headers.get("authorization") ?? "";
  const jwt = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!jwt) return jsonResponse({ ok: false, error: { code: "unauthorized" } }, 401);

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser(jwt);
  if (userError || !userData.user) {
    return jsonResponse({ ok: false, error: { code: "unauthorized" } }, 401);
  }

  let input: MetaSendRequest;
  try {
    input = await request.json() as MetaSendRequest;
  } catch {
    return jsonResponse({ ok: false, error: { code: "invalid_json" } }, 400);
  }
  const conversationId = stringValue(input.conversationId, 100);
  const message = stringValue(input.message, 2000);
  const clientMessageId = stringValue(input.clientMessageId, 200);
  if (!conversationId || !message || !clientMessageId) {
    return jsonResponse({
      ok: false,
      error: {
        code: "invalid_request",
        message: "conversationId, message y clientMessageId son obligatorios.",
      },
    }, 400);
  }

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const fingerprint = await sha256Hex(`${conversationId}\n${message}`);
  const { data: beginData, error: beginError } = await adminClient.rpc(
    "begin_meta_outbound_send",
    {
      p_actor_id: userData.user.id,
      p_conversation_id: conversationId,
      p_idempotency_key: clientMessageId,
      p_request_fingerprint: fingerprint,
      p_message_text: message,
    },
  );
  if (beginError || !beginData) {
    const replyWindowClosed = beginError?.hint === "reply_window_closed" ||
      beginError?.message?.includes("24-hour reply window");
    const forbidden = beginError?.code === "42501";
    return jsonResponse({
      ok: false,
      accepted: false,
      provider_accepted: false,
      outcome_unknown: false,
      retry_safe: true,
      error: {
        code: replyWindowClosed
          ? "reply_window_closed"
          : forbidden
          ? "forbidden"
          : "send_not_prepared",
        message: replyWindowClosed
          ? "La ventana de respuesta de 24 horas está cerrada."
          : "No fue posible preparar el envío.",
      },
    }, replyWindowClosed ? 409 : forbidden ? 403 : 400);
  }

  const prepared = beginData as JsonRecord;
  const attemptId = String(prepared.attempt_id ?? "");
  if (!attemptId) {
    return jsonResponse({ ok: false, error: { code: "invalid_send_receipt" } }, 500);
  }
  if (prepared.replayed === true) {
    const receipt = attemptReceipt(prepared);
    if (receipt.state === "provider_accepted" && receipt.external_message_id) {
      const { data: finalized, error: finalizeError } = await adminClient.rpc(
        "finalize_meta_outbound_send",
        {
          p_attempt_id: attemptId,
          p_external_message_id: receipt.external_message_id,
          p_provider_response: {},
        },
      );
      if (!finalizeError && finalized) {
        return jsonResponse(durableMetaSendSuccess(
          attemptReceipt(finalized as JsonRecord),
        ));
      }
    }
    const replay = replayedMetaSendResponse(receipt);
    return jsonResponse(replay.body, replay.status);
  }

  const channelId = stringValue(prepared.channel_id, 100);
  const provider = stringValue(prepared.provider, 60);
  const accountId = stringValue(prepared.external_account_id, 512);
  const recipientId = stringValue(prepared.external_user_id, 512);
  if (!channelId || !provider || !accountId || !recipientId) {
    await markAttempt(
      adminClient,
      attemptId,
      "preflight_failed",
      "invalid_channel_receipt",
      "El canal Meta no pudo resolverse.",
      {},
    );
    return jsonResponse({
      ok: false,
      accepted: false,
      provider_accepted: false,
      outcome_unknown: false,
      retry_safe: true,
      attempt_id: attemptId,
      error: { code: "invalid_channel_receipt" },
    }, 500);
  }

  const { data: credentialData, error: credentialError } = await adminClient.rpc(
    "get_meta_channel_access_token",
    { p_channel_id: channelId },
  );
  const credential = (credentialData ?? {}) as JsonRecord;
  const accessToken = stringValue(credential.access_token, 20_000);
  if (credentialError || !accessToken) {
    await markAttempt(
      adminClient,
      attemptId,
      "preflight_failed",
      "credential_unavailable",
      "La credencial del canal Meta no está disponible.",
      {},
    );
    return jsonResponse({
      ok: false,
      accepted: false,
      provider_accepted: false,
      outcome_unknown: false,
      retry_safe: true,
      attempt_id: attemptId,
      error: { code: "credential_unavailable" },
    }, 503);
  }

  const providerBody: JsonRecord = {
    recipient: { id: recipientId },
    message: { text: message },
    ...(provider === "facebook_messenger" ? { messaging_type: "RESPONSE" } : {}),
  };
  let providerResponse: Response;
  try {
    providerResponse = await fetch(
      `https://graph.facebook.com/${META_GRAPH_VERSION}/${encodeURIComponent(accountId)}/messages`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(providerBody),
        signal: AbortSignal.timeout(20_000),
      },
    );
  } catch (error) {
    const code = error instanceof DOMException && error.name === "TimeoutError"
      ? "provider_timeout"
      : "provider_network_error";
    await markAttempt(
      adminClient,
      attemptId,
      "outcome_unknown",
      code,
      "No se recibió una respuesta concluyente de Meta.",
      {},
    );
    return jsonResponse({
      ok: false,
      accepted: false,
      provider_accepted: false,
      outcome_unknown: true,
      retry_safe: false,
      attempt_id: attemptId,
      error: { code, message: "El resultado del envío no es concluyente." },
    }, 502);
  }

  const rawProviderData = await parseJsonResponse(providerResponse);
  const safeProviderData = sanitizedProviderResponse(rawProviderData);
  if (!providerResponse.ok) {
    const providerError = safeProviderData.error as JsonRecord | undefined;
    const providerCode = typeof providerError?.code === "number"
      ? `meta_${providerError.code}`
      : `meta_http_${providerResponse.status}`;
    const providerMessage = stringValue(providerError?.message, 500) ??
      "Meta rechazó el mensaje.";
    const disposition = metaProviderFailureDisposition(providerResponse.status);
    await markAttempt(
      adminClient,
      attemptId,
      disposition.attemptState,
      providerCode,
      providerMessage,
      safeProviderData,
    );
    return jsonResponse({
      ok: false,
      accepted: false,
      provider_accepted: false,
      outcome_unknown: disposition.outcomeUnknown,
      retry_safe: disposition.retrySafe,
      attempt_id: attemptId,
      error: { code: providerCode, message: providerMessage },
    }, metaProviderFailureHttpStatus(providerResponse.status));
  }

  const externalMessageId = stringValue(rawProviderData.message_id, 512);
  if (!externalMessageId) {
    await markAttempt(
      adminClient,
      attemptId,
      "outcome_unknown",
      "provider_missing_message_id",
      "Meta respondió sin un identificador de mensaje.",
      safeProviderData,
    );
    return jsonResponse({
      ok: false,
      accepted: false,
      provider_accepted: false,
      outcome_unknown: true,
      retry_safe: false,
      attempt_id: attemptId,
      error: { code: "provider_missing_message_id" },
    }, 502);
  }

  const { error: acceptanceError } = await adminClient.rpc(
    "accept_meta_outbound_attempt",
    {
      p_attempt_id: attemptId,
      p_external_message_id: externalMessageId,
      p_provider_response: safeProviderData,
    },
  );
  if (acceptanceError) {
    console.error("[META-SEND] Provider acceptance could not be persisted", acceptanceError.code);
    return jsonResponse({
      ok: true,
      accepted: true,
      provider_accepted: true,
      outcome_unknown: false,
      retry_safe: false,
      persistence_pending: true,
      attempt_id: attemptId,
      message_id: null,
      external_message_id: externalMessageId,
      external_status: "accepted",
      error: { code: "acceptance_persistence_pending" },
    }, 202);
  }

  const { data: finalizedData, error: finalizeError } = await adminClient.rpc(
    "finalize_meta_outbound_send",
    {
      p_attempt_id: attemptId,
      p_external_message_id: externalMessageId,
      p_provider_response: safeProviderData,
    },
  );
  if (finalizeError || !finalizedData) {
    console.error(
      "[META-SEND] Provider acceptance awaits message finalization",
      finalizeError?.code,
    );
    const pending = replayedMetaSendResponse({
      attempt_id: attemptId,
      state: "provider_accepted",
      external_message_id: externalMessageId,
    });
    return jsonResponse(pending.body, pending.status);
  }
  return jsonResponse(durableMetaSendSuccess(
    attemptReceipt(finalizedData as JsonRecord),
  ));
});
